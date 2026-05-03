#!/usr/bin/env python3
"""
Flux Language Server (flux_lsp.py)
Diagnostics-only v1 LSP server for the Flux language.

Requirements:
    pip install pygls lsprotocol

Usage:
    python flux_lsp.py          # stdio mode (default, for editors)
    python flux_lsp.py --tcp    # TCP mode on port 2087 (for debugging)

The server expects to be launched from the Flux repo root, or for
FLUXC_SRCDIR to be set so that fparser.py / flexer.py etc. are importable.

Editor config examples
----------------------
VS Code (settings.json, requires a generic LSP client extension):
    "languageServerExample.serverPath": "/path/to/flux_lsp.py"

Neovim (init.lua):
    vim.lsp.start({
        name = "flux",
        cmd  = { "python3", "/path/to/flux_lsp.py" },
        filetypes = { "flux" },
        root_dir = vim.fn.getcwd(),
    })

Helix (languages.toml):
    [[language]]
    name = "flux"
    language-servers = ["flux-lsp"]
    file-types = ["fx"]

    [language-server.flux-lsp]
    command = "python3"
    args    = ["/path/to/flux_lsp.py"]
"""

import sys
import os
import re
import logging
import traceback
from pathlib import Path
from typing import List, Optional
from urllib.parse import unquote, urlparse

# ---------------------------------------------------------------------------
# Make the Flux compiler modules importable
# ---------------------------------------------------------------------------
_FLUXC_SRCDIR = os.environ.get("FLUXC_SRCDIR", str(Path(__file__).parent.resolve()))
if _FLUXC_SRCDIR not in sys.path:
    sys.path.insert(0, _FLUXC_SRCDIR)

# ---------------------------------------------------------------------------
# pygls / lsprotocol imports
# ---------------------------------------------------------------------------
try:
    from pygls.server import LanguageServer
    from lsprotocol import types as lsp
except Exception as e:
    print(
        f"ERROR: Could not import pygls/lsprotocol: {e}\n"
        "Install them with:  pip install pygls lsprotocol",
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# Flux compiler imports
# ---------------------------------------------------------------------------
_flux_import_error: Optional[str] = None
try:
    from flexer import FluxLexer, TokenType
    from fpreprocess import FXPreprocessor
    from fparser import FluxParser, ParseError
except Exception as exc:
    _flux_import_error = (
        f"Could not import Flux compiler modules: {exc}\n"
        f"Make sure FLUXC_SRCDIR points to the Flux repo root, or run this\n"
        f"script from that directory.\n"
        f"FLUXC_SRCDIR = {_FLUXC_SRCDIR}"
    )

# ---------------------------------------------------------------------------
# Logging  (goes to stderr so it doesn't corrupt stdio LSP traffic)
# ---------------------------------------------------------------------------
logging.basicConfig(
    stream=sys.stderr,
    level=logging.DEBUG,
    format="%(asctime)s [flux-lsp] %(levelname)s  %(message)s",
)
log = logging.getLogger("flux-lsp")

import builtins
_real_print = builtins.print
def _silent_print(*args, **kwargs):
    kwargs['file'] = sys.stderr
    _real_print(*args, **kwargs)
builtins.print = _silent_print

# ---------------------------------------------------------------------------
# Server instance
# ---------------------------------------------------------------------------
SERVER_NAME    = "flux-language-server"
SERVER_VERSION = "0.1.0"

flux_server = LanguageServer(SERVER_NAME, SERVER_VERSION)

# ---------------------------------------------------------------------------
# Diagnostic helpers
# ---------------------------------------------------------------------------

def _uri_to_path(uri: str) -> str:
    """Convert a file:// URI to an OS path."""
    parsed = urlparse(uri)
    path   = unquote(parsed.path)
    if sys.platform == "win32" and path.startswith("/") and len(path) > 2 and path[2] == ":":
        path = path[1:]
    return path


def _make_range(line: int, col: int, end_col: Optional[int] = None) -> lsp.Range:
    ln = max(0, line - 1)
    sc = max(0, col  - 1)
    ec = (sc + 1) if end_col is None else max(sc + 1, end_col - 1)
    return lsp.Range(
        start=lsp.Position(line=ln, character=sc),
        end  =lsp.Position(line=ln, character=ec),
    )


_PARSE_ERROR_RE = re.compile(r"at\s+(\d+):(\d+)")
_LEX_ERROR_RE   = re.compile(r"[Ll]ine\s+(\d+)[,\s]+[Cc]ol(?:umn)?\s+(\d+)")


def _diagnostic_from_exc(exc: Exception) -> lsp.Diagnostic:
    msg   = str(exc)
    token = getattr(exc, "token", None)
    if token is not None:
        rng = _make_range(token.line, token.column)
    else:
        m   = _PARSE_ERROR_RE.search(msg) or _LEX_ERROR_RE.search(msg)
        rng = _make_range(int(m.group(1)), int(m.group(2))) if m else _make_range(1, 1)

    clean_msg = msg.split("\n\n")[0].strip()
    return lsp.Diagnostic(
        range   =rng,
        message =clean_msg,
        severity=lsp.DiagnosticSeverity.Error,
        source  =SERVER_NAME,
    )


def _semantic_diagnostics(program, symbol_table) -> List[lsp.Diagnostic]:
    """
    Walk the AST and emit diagnostics for semantic issues the parser doesn't
    catch — currently: calls to functions that were never declared/defined.

    Strategy
    --------
    1. Collect every 'using' namespace path from UsingStatement nodes so we
       can replicate the namespace resolution that the real compiler does at
       codegen time.
    2. Walk every node recursively.  For each FunctionCall whose name is a
       plain string (not a MethodCall / member-access), ask the parser's
       own SymbolTable whether a FUNCTION entry exists under that name or
       any of the active using-namespaces.
    3. Skip names that look like template instantiations (contain '<') or
       constructors (contain '__init') — those are resolved later.
    """
    diags: List[lsp.Diagnostic] = []

    # ── imports we need from the compiler modules ──────────────────────────
    try:
        from fast import FunctionCall, UsingStatement, MethodCall
        from ftypesys import SymbolKind
    except Exception as exc:
        log.debug("_semantic_diagnostics: cannot import fast/ftypesys: %s", exc)
        return diags

    # ── 1. gather active using-namespaces from the AST ─────────────────────
    using_namespaces: List[str] = []

    def _collect_using(node):
        if isinstance(node, UsingStatement):
            # UsingStatement stores the path as a double-underscore mangled
            # string, e.g. "standard__io__console".
            ns = getattr(node, 'namespace', None) or getattr(node, 'path', None)
            if ns and ns not in using_namespaces:
                using_namespaces.append(ns)

    _walk_ast(program, _collect_using)

    # ── 2. helper: is 'name' resolvable as a function? ─────────────────────
    def _is_known_function(name: str) -> bool:
        # Direct lookup (handles builtins, top-level defs, already-mangled names)
        if symbol_table.lookup_function(name) is not None:
            return True
        # Try each active using-namespace (e.g. "standard__io__console__println")
        for ns in using_namespaces:
            qualified = f"{ns}__{name}"
            if symbol_table.lookup_function(qualified) is not None:
                return True
        return False

    # ── 3. walk and check every FunctionCall ───────────────────────────────
    def _check_node(node):
        if not isinstance(node, FunctionCall):
            return
        # name can be a str or an Identifier/expression node
        raw = getattr(node, 'name', None) or getattr(node, 'func_name', None)
        if not isinstance(raw, str):
            return  # complex callee (e.g. function pointer) — skip
        name = raw
        # Skip special / compiler-generated names
        if '<' in name or '__init' in name or '__exit' in name:
            return
        # Strip leading namespace prefix already embedded in the mangled name
        # (the parser sometimes pre-mangles template/overload names)
        if not _is_known_function(name):
            line = getattr(node, 'line', 1)
            col  = getattr(node, 'column', 1)
            end_col = col + len(name)
            diags.append(lsp.Diagnostic(
                range    = _make_range(line, col, end_col),
                message  = f"Undefined function: '{name}'",
                severity = lsp.DiagnosticSeverity.Error,
                source   = SERVER_NAME,
            ))

    _walk_ast(program, _check_node)
    return diags


def _walk_ast(node, visitor_fn) -> None:
    """
    Generic depth-first AST walk.  Calls visitor_fn(node) on every node.
    Understands dataclass nodes (recurse into fields), lists, and tuples.
    """
    if node is None:
        return
    visitor_fn(node)
    if isinstance(node, list):
        for child in node:
            _walk_ast(child, visitor_fn)
    elif isinstance(node, tuple):
        for child in node:
            _walk_ast(child, visitor_fn)
    elif hasattr(node, '__dataclass_fields__'):
        for field_name in node.__dataclass_fields__:
            _walk_ast(getattr(node, field_name, None), visitor_fn)


def _parse_diagnostics(source: str, file_path: str) -> List[lsp.Diagnostic]:
    diags: List[lsp.Diagnostic] = []
    try:
        path = Path(file_path)
        # Preprocessor uses Path("build") — a relative path — so we must run
        # it from the repo root so that resolves correctly.
        _prev_cwd = os.getcwd()
        if path.exists():
            try:
                os.chdir(_FLUXC_SRCDIR)
                preprocessor = FXPreprocessor(file_path)
                preprocessed = preprocessor.process()
            finally:
                os.chdir(_prev_cwd)
        else:
            preprocessed = source

        lexer        = FluxLexer(preprocessed)
        tokens       = lexer.tokenize()
        source_lines = preprocessed.splitlines(keepends=True)
        parser       = FluxParser(tokens, source_lines=source_lines)
        program      = parser.parse()

        # Syntax clean — now do semantic checks
        diags.extend(_semantic_diagnostics(program, parser.symbol_table))

    except ParseError as exc:
        diags.append(_diagnostic_from_exc(exc))
    except ValueError as exc:
        inner = str(exc)
        if inner.startswith("\nParse error:"):
            inner = inner[len("\nParse error:"):].strip()
        diags.append(lsp.Diagnostic(
            range   =_make_range(1, 1),
            message =inner,
            severity=lsp.DiagnosticSeverity.Error,
            source  =SERVER_NAME,
        ))
    except Exception as exc:
        log.debug("Unexpected error during validation:\n%s", traceback.format_exc())
        diags.append(lsp.Diagnostic(
            range   =_make_range(1, 1),
            message =f"Internal compiler error: {exc}",
            severity=lsp.DiagnosticSeverity.Error,
            source  =SERVER_NAME,
        ))

    return diags


def _validate(ls: LanguageServer, uri: str, source: str) -> None:
    if _flux_import_error:
        ls.publish_diagnostics(uri, [lsp.Diagnostic(
            range   =_make_range(1, 1),
            message =_flux_import_error,
            severity=lsp.DiagnosticSeverity.Error,
            source  =SERVER_NAME,
        )])
        return

    file_path = _uri_to_path(uri)
    log.debug("Validating %s", file_path)
    diags = _parse_diagnostics(source, file_path)
    ls.publish_diagnostics(uri, diags)
    log.debug("Published %d diagnostic(s) for %s", len(diags), file_path)


# ---------------------------------------------------------------------------
# LSP lifecycle
# ---------------------------------------------------------------------------

@flux_server.feature(lsp.INITIALIZE)
def on_initialize(ls: LanguageServer, params: lsp.InitializeParams):
    log.info("Flux LSP initializing (client: %s)", getattr(params, "client_info", "unknown"))
    if _flux_import_error:
        log.error(_flux_import_error)


@flux_server.feature(lsp.INITIALIZED)
def on_initialized(ls: LanguageServer, params: lsp.InitializedParams):
    log.info("Flux LSP ready.")


@flux_server.feature(lsp.TEXT_DOCUMENT_DID_OPEN)
def did_open(ls: LanguageServer, params: lsp.DidOpenTextDocumentParams):
    doc = params.text_document
    _validate(ls, doc.uri, doc.text)


@flux_server.feature(lsp.TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls: LanguageServer, params: lsp.DidChangeTextDocumentParams):
    if params.content_changes:
        uri = params.text_document.uri
        doc = ls.workspace.get_text_document(uri)
        _validate(ls, uri, doc.source)


@flux_server.feature(lsp.TEXT_DOCUMENT_DID_SAVE)
def did_save(ls: LanguageServer, params: lsp.DidSaveTextDocumentParams):
    doc = ls.workspace.get_text_document(params.text_document.uri)
    _validate(ls, params.text_document.uri, doc.source)


@flux_server.feature(lsp.TEXT_DOCUMENT_DID_CLOSE)
def did_close(ls: LanguageServer, params: lsp.DidCloseTextDocumentParams):
    ls.publish_diagnostics(params.text_document.uri, [])


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Flux Language Server")
    ap.add_argument("--tcp",  action="store_true", help="TCP mode on port 2087")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=2087)
    args = ap.parse_args()

    if args.tcp:
        log.info("Starting in TCP mode on %s:%d", args.host, args.port)
        flux_server.start_tcp(args.host, args.port)
    else:
        log.info("Starting in stdio mode")
        flux_server.start_io()


if __name__ == "__main__":
    main()