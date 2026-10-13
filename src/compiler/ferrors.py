#!/usr/bin/env python3
"""
Flux Compiler Error System

Copyright (C) 2026 Karac V. Thweatt

Centralised diagnostic infrastructure for all Flux compiler components.
The parser, type system, and code generator all route through here so that
error formatting, caret rendering, suggestion logic, and severity handling
live in exactly one place.

Components import the exception classes they need:

    from ferrors import FluxParseError, FluxSyntaxError

Then raise them directly or via the parser helper methods (error/warn).

Error code ranges
-----------------
    E001-E199   Parse errors
    W001-W099   Warnings (any component)
    (T/G ranges reserved for future type-system and codegen integration)
"""

import re
import sys
from enum import Enum, auto
from typing import Optional, List

# ---------------------------------------------------------------------------
# Token symbol display map - imported from the lexer is not possible here
# without a circular import, so we keep a local copy of the display strings
# that the formatter uses. This table is intentionally minimal: only symbols
# that can appear in suggestions or caret hints need entries.
# ---------------------------------------------------------------------------
from flexer import TokenType

_TOKEN_SYMBOL_MAP = {
    TokenType.PLUS:             '+',
    TokenType.MINUS:            '-',
    TokenType.MULTIPLY:         '*',
    TokenType.DIVIDE:           '/',
    TokenType.MODULO:           '%',
    TokenType.LESS_THAN:        '<',
    TokenType.GREATER_THAN:     '>',
    TokenType.ASSIGN:           '=',
    TokenType.LOGICAL_OR:       '|',
    TokenType.LOGICAL_AND:      '&',
    TokenType.BITXOR_OP:        '^',
    TokenType.NOT:              '!',
    TokenType.QUESTION:         '?',
    TokenType.ADDRESS_OF:       '@',
    TokenType.TIE:              '~',
    TokenType.INCREMENT:        '++',
    TokenType.DECREMENT:        '--',
    TokenType.EQUAL:            '==',
    TokenType.NOT_EQUAL:        '!=',
    TokenType.LESS_EQUAL:       '<=',
    TokenType.GREATER_EQUAL:    '>=',
    TokenType.NAND_OP:          '!&',
    TokenType.NOR_OP:           '!|',
    TokenType.XOR_OP:           '^|',
    TokenType.BITSHIFT_LEFT:    '<<',
    TokenType.BITSHIFT_RIGHT:   '>>',
    TokenType.BITNAND_OP:       '`!&',
    TokenType.BITNOR_OP:        '`!|',
    TokenType.BITXNAND:         '`^|!&',
    TokenType.BITXNOR:          '`^|!|',
    TokenType.LEFT_PAREN:       '(',
    TokenType.RIGHT_PAREN:      ')',
    TokenType.LEFT_BRACE:       '{',
    TokenType.RIGHT_BRACE:      '}',
    TokenType.LEFT_BRACKET:     '[',
    TokenType.RIGHT_BRACKET:    ']',
    TokenType.SEMICOLON:        ';',
    TokenType.COLON:            ':',
    TokenType.COMMA:            ',',
    TokenType.DOT:              '.',
    TokenType.RETURN_ARROW:     '->',
    TokenType.SCOPE:            '::',
    TokenType.BACKSLASH:        '\\',
}

# Token types whose missing token belongs at the END of the previous line
# rather than at the start of the current (wrong) token.
_END_OF_PREV_LINE_TYPES = {TokenType.SEMICOLON, TokenType.COMMA}

TAB_WIDTH = 4


# ---------------------------------------------------------------------------
# Severity
# ---------------------------------------------------------------------------

class Severity(Enum):
    WARNING = auto()
    ERROR   = auto()


# ---------------------------------------------------------------------------
# SuggestedFix - a resolved replacement line to show after the caret
# ---------------------------------------------------------------------------

class SuggestedFix:
    """A concrete suggested source-line fix to display beneath the caret."""

    __slots__ = ('fixed_line',)

    def __init__(self, fixed_line: str):
        # fixed_line should already include the trailing '  // try this' label.
        self.fixed_line = fixed_line


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _expand_tabs(raw_line: str, stop_col: int):
    """
    Expand tab characters in *raw_line* to TAB_WIDTH-aligned spaces.

    Returns (expanded_line, visual_col) where visual_col is the 1-based
    visual position corresponding to raw column *stop_col* (1-based) after
    expansion.
    """
    expanded = ''
    visual_col = 1
    for i, ch in enumerate(raw_line):
        col_in_raw = i + 1
        if ch == '\t':
            spaces = TAB_WIDTH - (len(expanded) % TAB_WIDTH)
            expanded += ' ' * spaces
            if col_in_raw < stop_col:
                visual_col += spaces
        else:
            expanded += ch
            if col_in_raw < stop_col:
                visual_col += 1
    return expanded, visual_col


def _build_suggestion(
    expected_type,
    current_token,
    prev_token,
    src_line: str,
    raw_line: str,
    dash_count: int,
) -> str:
    """
    Derive a suggested fix string from the expected token type and context.

    Returns the fixed source line with the '  // try this' suffix, or '' if
    no automatic suggestion is possible for this combination.
    """
    fix_sym = _TOKEN_SYMBOL_MAP.get(expected_type) if expected_type is not None else None
    if fix_sym is None:
        return ''

    if expected_type in _END_OF_PREV_LINE_TYPES:
        # Special case: expected ';' but got '[' - user wrote C-style array syntax.
        if (expected_type == TokenType.SEMICOLON
                and current_token is not None
                and current_token.type == TokenType.LEFT_BRACKET
                and prev_token is not None):
            raw = raw_line.rstrip()
            m = re.match(r'^(\s*)(\S+)\s+(\S+?)(\[\d+\])(;?)$', raw)
            if m:
                _indent, _typ, _varname, _brackets, _semi = m.groups()
                return f'{_indent}{_typ}{_brackets} {_varname};  // try this'

        # Spurious-token case: current_token and prev_token are on the same line,
        # meaning something unexpected sits between the last valid token and where
        # the terminator belongs.  Only suggest a fix if the terminator is actually
        # missing - if the line already ends with it, something else is wrong and
        # we emit no suggestion.
        if (prev_token is not None
                and current_token is not None
                and prev_token.line == current_token.line):
            if raw_line.rstrip().endswith(fix_sym):
                return ''
            col = current_token.column - 1  # 0-based
            tok_val = getattr(current_token, 'value', '') or ''
            end_col = col + len(tok_val)
            before = raw_line[:col].rstrip()
            after  = raw_line[end_col:].lstrip()
            fixed  = (before + (' ' if before and after and not after.startswith(fix_sym) else '') + after).rstrip()
            if not fixed.endswith(fix_sym):
                fixed = fixed + fix_sym
            return fixed + '  // try this'

        # Default: append terminator at end of line.
        return src_line + fix_sym + '  // try this'

    if expected_type == TokenType.RETURN_ARROW:
        return src_line[:dash_count] + fix_sym + ' ' + src_line[dash_count:].lstrip() + '  // try this'

    if (expected_type == TokenType.ASSIGN
            and current_token is not None
            and current_token.type == TokenType.LEFT_BRACE):
        return src_line[:dash_count] + fix_sym + ' ' + src_line[dash_count:].lstrip() + '  // try this'

    return ''


def _render_diagnostic(
    severity: Severity,
    code: str,
    message: str,
    token=None,
    source_lines: Optional[List[str]] = None,
    line_map: Optional[List[tuple]] = None,
    expected_type=None,
    prev_token=None,
    annotation: str = '',
    fix: Optional[SuggestedFix] = None,
    prev_source_line: str = '',
) -> tuple:
    """
    Render a diagnostic into a formatted string.

    Returns (formatted_str, display_line, display_col) where display_line /
    display_col are the resolved (file-local) coordinates, or None when a
    token is not available.
    """
    if token is None:
        return message, None, None

    line_no = token.line
    col     = token.column  # 1-based

    if not source_lines:
        return f"{message} at {line_no}:{col}", line_no, col

    # ------------------------------------------------------------------
    # Determine the line/col to point at.
    # For end-of-line token types, redirect to the end of the previous line.
    # ------------------------------------------------------------------
    show_line_no = line_no
    show_col     = col
    if (expected_type in _END_OF_PREV_LINE_TYPES
            and prev_token is not None
            and prev_token.line < line_no
            and 1 <= prev_token.line <= len(source_lines)):
        show_line_no = prev_token.line
        prev_src = source_lines[show_line_no - 1].rstrip('\n')
        show_col = len(prev_src) + 1

    # Resolve to file-local line number via line_map.
    lm = line_map or []
    display_line_no = lm[show_line_no - 1][1] if lm and 1 <= show_line_no <= len(lm) else show_line_no
    display_col     = show_col

    if not (1 <= show_line_no <= len(source_lines)):
        return f"{message} at {display_line_no}:{display_col}", display_line_no, display_col

    raw_line = source_lines[show_line_no - 1].rstrip('\n')
    src_line, expanded_col = _expand_tabs(raw_line, show_col)

    # ------------------------------------------------------------------
    # Caret placement
    # ------------------------------------------------------------------
    if show_col > len(raw_line):
        dash_count = len(src_line)
    else:
        dash_count = max(0, expanded_col - 1)

    hint = ''
    if expected_type is not None:
        sym = _TOKEN_SYMBOL_MAP.get(expected_type)
        hint = f' {sym} expected here' if sym else f' {expected_type.name} expected here'
    caret_line = '-' * dash_count + '^' + hint

    # ------------------------------------------------------------------
    # Suggestion / annotation
    # ------------------------------------------------------------------
    # An explicit SuggestedFix overrides the auto-derived suggestion.
    if fix is not None:
        suggestion = fix.fixed_line
    else:
        suggestion = _build_suggestion(
            expected_type, token, prev_token, src_line, raw_line, dash_count
        )

    header = f"{message} at {display_line_no}:{display_col}"

    # Optional preceding context line. Pass through _expand_tabs in case the
    # raw line contains literal tab characters; if it is already space-expanded
    # (as preprocessed source_lines may be) this is a no-op.
    if prev_source_line:
        ctx_prev = prev_source_line.expandtabs(TAB_WIDTH)
        ctx_prefix = f"{ctx_prev}\n"
    else:
        ctx_prefix = ""

    if suggestion:
        formatted = f"{header}\n{ctx_prefix}{src_line}\n{caret_line}\n{suggestion}"
    elif annotation:
        if annotation.startswith('//'):
            formatted = f"{header}\n{ctx_prefix}{src_line}\n{caret_line} {annotation}"
        else:
            formatted = f"{header}\n{ctx_prefix}{src_line}\n{caret_line} {annotation}"
    else:
        formatted = f"{header}\n{ctx_prefix}{src_line}\n{caret_line}"

    return formatted, display_line_no, display_col


# ---------------------------------------------------------------------------
# Public exception hierarchy
# ---------------------------------------------------------------------------

class FluxDiagnosticBase(Exception):
    """
    Base for all user-facing Flux compiler diagnostics.

    Subclasses set ``severity`` and ``default_code``.  The formatted message
    (caret + suggestion) is computed once in __init__ and stored as the
    Exception string so that any bare ``str(e)`` or ``print(e)`` produces
    the full diagnostic automatically.
    """

    severity:     Severity = Severity.ERROR
    default_code: str      = 'E000'

    def __init__(
        self,
        message: str,
        token=None,
        source_lines: Optional[List[str]] = None,
        expected_type=None,
        prev_token=None,
        line_map=None,
        annotation: str = '',
        fix: Optional[SuggestedFix] = None,
        code: str = None,
        prev_source_line: str = '',
    ):
        self.message          = message
        self.token            = token
        self.source_lines     = source_lines
        self.expected_type    = expected_type
        self.prev_token       = prev_token
        self.line_map         = line_map or []
        self.annotation       = annotation
        self.fix              = fix
        self.code             = code or self.default_code
        self.prev_source_line = prev_source_line

        formatted, self.display_line, self.display_col = _render_diagnostic(
            severity         = self.severity,
            code             = self.code,
            message          = self.message,
            token            = self.token,
            source_lines     = self.source_lines,
            line_map         = self.line_map,
            expected_type    = self.expected_type,
            prev_token       = self.prev_token,
            annotation       = self.annotation,
            fix              = self.fix,
            prev_source_line = self.prev_source_line,
        )
        super().__init__(formatted)


class FluxParseError(FluxDiagnosticBase):
    """Fatal parse error - compilation cannot continue."""
    severity     = Severity.ERROR
    default_code = 'E001'


class FluxSyntaxError(FluxDiagnosticBase):
    """Syntax error raised at a specific parse site."""
    severity     = Severity.ERROR
    default_code = 'E002'


class FluxWarning(FluxDiagnosticBase):
    """Non-fatal diagnostic - printed to stderr, does not halt compilation."""
    severity     = Severity.WARNING
    default_code = 'W001'


class FluxCodegenError(Exception):
    """
    Fatal code generation error with source location and caret.

    Unlike FluxDiagnosticBase (which works from Token + source_lines),
    codegen errors are raised with an AST node and the llvmlite module,
    since that is what is available during IR generation.

    The formatted message is built immediately using _src_loc_with_source
    from fcodegen so the same file-open + caret logic is reused.
    """

    def __init__(self, message: str, node=None, module=None):
        self.message  = message
        self.node     = node
        self.module   = module

        # Resolve location and source line via the existing codegen helper.
        # Import here to avoid a circular dependency at module load time.
        try:
            from fcodegen import _src_loc_with_source
            loc_str = _src_loc_with_source(node, module) if node is not None else ''
        except Exception:
            loc_str = ''

        if loc_str:
            formatted = f"{message}\n{loc_str}"
        else:
            formatted = message

        self.display_line = getattr(node, 'source_line', None)
        self.display_col  = getattr(node, 'source_col',  None)

        super().__init__(formatted)


# ---------------------------------------------------------------------------
# Backward-compatible alias
# ---------------------------------------------------------------------------
# fparser.py catches ParseError by name in several places.  Keep the alias
# so we can rename the internal class without a flag-day across the codebase.
ParseError = FluxParseError


# ---------------------------------------------------------------------------
# Warning emitter (non-raising path)
# ---------------------------------------------------------------------------

def emit_warning(
    message: str,
    token=None,
    source_lines: Optional[List[str]] = None,
    line_map: Optional[List[tuple]] = None,
) -> None:
    """
    Format and print a warning to stderr immediately.

    Does not raise; call this from parser.warn() or any other component that
    produces non-fatal diagnostics.
    """
    formatted, _, _ = _render_diagnostic(
        severity     = Severity.WARNING,
        code         = 'W001',
        message      = f"Warning: {message}",
        token        = token,
        source_lines = source_lines,
        line_map     = line_map,
    )
    print(formatted, file=sys.stderr)