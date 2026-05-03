#!/usr/bin/env python3
"""
Flux Language Server (flux_lsp.py)
Diagnostics-only v1 LSP server for the Flux language.

Requirements:
    pip install pygls lsprotocol

Usage:
    python3 flux_lsp.py          # stdio mode (default, for editors)
    python3 flux_lsp.py --tcp    # TCP mode on port 2087 (for debugging)

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
except ImportError:
    print(
        "ERROR: pygls and lsprotocol are required.\n"
        "Install them with:  pip install pygls lsprotocol",
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# Flux compiler imports  (lazy-ish — we catch errors gracefully)
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

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
SERVER_NAME    = "flux-language-server"
SERVER_VERSION = "0.1.0"

server = LanguageServer(SERVER_NAME, SERVER_VERSION)


# ---------------------------------------------------------------------------
# Diagnostic helpers
# ---------------------------------------------------------------------------

def _uri_to_path(uri: str) -> str:
    """Convert a file:// URI to an OS path."""
    parsed = urlparse(uri)
    path   = unquote(parsed.path)
    # On Windows the path starts with /C:/... — strip the leading slash
    if sys.platform == "win32" and path.startswith("/") and len(path) > 2 and path[2] == ":":
        path = path[1:]
    return path


def _make_range(line: int, col: int, end_col: Optional[int] = None) -> lsp.Range:
    """
    Build an LSP Range from 1-based line/col (Flux convention) to 0-based
    (LSP convention).  If end_col is not given we highlight the single
    character at col.
    """
    ln  = max(0, line - 1)
    sc  = max(0, col  - 1)
    ec  = (sc + 1) if end_col is None else max(sc + 1, end_col - 1)
    return lsp.Range(
        start=lsp.Position(line=ln, character=sc),
        end  =lsp.Position(line=ln, character=ec),
    )


_PARSE_ERROR_RE = re.compile(
    r"at\s+(\d+):(\d+)",          # "at <line>:<col>"
)

_LEX_ERROR_RE = re.compile(
    r"[Ll]ine\s+(\d+)[,\s]+[Cc]ol(?:umn)?\s+(\d+)",   # "line N, col M"
)


def _diagnostic_from_parse_error(exc: Exception) -> lsp.Diagnostic:
    """
    Turn a ParseError (or any exception from the Flux pipeline) into an
    LSP Diagnostic.  We try to extract line/col from the exception; if we
    can't we fall back to 0:0.
    """
    msg = str(exc)

    # ParseError stores .token with .line / .column
    token = getattr(exc, "token", None)
    if token is not None:
        rng = _make_range(token.line, token.column)
    else:
        # Try parsing "at <line>:<col>" from the formatted message
        m = _PARSE_ERROR_RE.search(msg) or _LEX_ERROR_RE.search(msg)
        if m:
            rng = _make_range(int(m.group(1)), int(m.group(2)))
        else:
            rng = _make_range(1, 1)

    # Trim the inline source snippet — editors show their own underlines
    # Keep only up to the first blank line (which separates the message
    # from the snippet in ParseError._format).
    clean_msg = msg.split("\n\n")[0].strip()

    return lsp.Diagnostic(
        range   =rng,
        message =clean_msg,
        severity=lsp.DiagnosticSeverity.Error,
        source  =SERVER_NAME,
    )


def _lex_diagnostics(source: str) -> List[lsp.Diagnostic]:
    """Run only the lexer and collect any lex-time errors."""
    diags: List[lsp.Diagnostic] = []
    try:
        lexer  = FluxLexer(source)
        lexer.tokenize()
    except Exception as exc:
        diags.append(_diagnostic_from_parse_error(exc))
    return diags


def _parse_diagnostics(source: str, file_path: str) -> List[lsp.Diagnostic]:
    """
    Run the full Flux pipeline (preprocess → lex → parse) and collect
    diagnostics.  Returns an empty list on success.
    """
    diags: List[lsp.Diagnostic] = []

    try:
        # Preprocess
        # FXPreprocessor expects the real file path for #import resolution.
        # We write the live buffer to a temp file only when the path exists
        # on disk; otherwise we skip preprocessing and just lex/parse directly.
        preprocessed: str
        path = Path(file_path)
        if path.exists():
            preprocessor = FXPreprocessor(file_path)
            preprocessed = preprocessor.process()
        else:
            preprocessed = source

        # Lex
        lexer  = FluxLexer(preprocessed)
        tokens = lexer.tokenize()

        # Parse
        source_lines = preprocessed.splitlines(keepends=True)
        parser = FluxParser(tokens, source_lines=source_lines)
        parser.parse()

    except ParseError as exc:
        diags.append(_diagnostic_from_parse_error(exc))
    except ValueError as exc:
        # FluxParser wraps ParseError in ValueError with "Parse error: …"
        inner_msg = str(exc)
        if inner_msg.startswith("\nParse error:"):
            inner_msg = inner_msg[len("\nParse error:"):].strip()
        diags.append(
            lsp.Diagnostic(
                range   =_make_range(1, 1),
                message =inner_msg,
                severity=lsp.DiagnosticSeverity.Error,
                source  =SERVER_NAME,
            )
        )
    except Exception as exc:
        log.debug("Unexpected error during validation: %s", traceback.format_exc())
        diags.append(
            lsp.Diagnostic(
                range   =_make_range(1, 1),
                message =f"Internal compiler error: {exc}",
                severity=lsp.DiagnosticSeverity.Error,
                source  =SERVER_NAME,
            )
        )

    return diags


def _validate(ls: LanguageServer, uri: str, source: str) -> None:
    """Validate *source* and publish diagnostics for *uri*."""
    if _flux_import_error:
        ls.publish_diagnostics(
            uri,
            [
                lsp.Diagnostic(
                    range   =_make_range(1, 1),
                    message =_flux_import_error,
                    severity=lsp.DiagnosticSeverity.Error,
                    source  =SERVER_NAME,
                )
            ],
        )
        return

    file_path = _uri_to_path(uri)
    log.debug("Validating %s", file_path)

    diags = _parse_diagnostics(source, file_path)
    ls.publish_diagnostics(uri, diags)
    log.debug("Published %d diagnostic(s) for %s", len(diags), file_path)


# ---------------------------------------------------------------------------
# LSP lifecycle
# ---------------------------------------------------------------------------

@server.feature(lsp.INITIALIZE)
def on_initialize(ls: LanguageServer, params: lsp.InitializeParams):
    log.info("Flux LSP initializing (client: %s)", getattr(params, "client_info", "unknown"))
    if _flux_import_error:
        log.error(_flux_import_error)


@server.feature(lsp.INITIALIZED)
def on_initialized(ls: LanguageServer, params: lsp.InitializedParams):
    log.info("Flux LSP ready.")


# ---------------------------------------------------------------------------
# Document sync → re-validate on every change
# ---------------------------------------------------------------------------

@server.feature(
    lsp.TEXT_DOCUMENT_DID_OPEN,
)
def did_open(ls: LanguageServer, params: lsp.DidOpenTextDocumentParams):
    doc = params.text_document
    _validate(ls, doc.uri, doc.text)


@server.feature(lsp.TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls: LanguageServer, params: lsp.DidChangeTextDocumentParams):
    # We use full-document sync, so the last change has the whole text.
    if params.content_changes:
        text = params.content_changes[-1].text
        _validate(ls, params.text_document.uri, text)


@server.feature(lsp.TEXT_DOCUMENT_DID_SAVE)
def did_save(ls: LanguageServer, params: lsp.DidSaveTextDocumentParams):
    # Re-validate on save (picks up changes to #imported files)
    doc = ls.workspace.get_text_document(params.text_document.uri)
    _validate(ls, params.text_document.uri, doc.source)


@server.feature(lsp.TEXT_DOCUMENT_DID_CLOSE)
def did_close(ls: LanguageServer, params: lsp.DidCloseTextDocumentParams):
    # Clear diagnostics when the file is closed
    ls.publish_diagnostics(params.text_document.uri, [])


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Flux Language Server")
    ap.add_argument(
        "--tcp",
        action="store_true",
        help="Run in TCP mode on port 2087 instead of stdio",
    )
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=2087)
    args = ap.parse_args()

    if args.tcp:
        log.info("Starting in TCP mode on %s:%d", args.host, args.port)
        server.start_tcp(args.host, args.port)
    else:
        log.info("Starting in stdio mode")
        server.start_io()


if __name__ == "__main__":
    main()