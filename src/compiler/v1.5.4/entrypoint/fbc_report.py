"""
fbc_report.py -- Violation reporting for the Flux Borrow Checker.
Supports human-readable and JSON output modes.

Copyright (C) 2026 Karac V. Thweatt
"""

import json
import sys
from fbc_alias import Violation


COLORS = {
    'red':    '\033[91m',
    'yellow': '\033[93m',
    'cyan':   '\033[96m',
    'dim':    '\033[2m',
    'bold':   '\033[1m',
    'reset':  '\033[0m',
}

KIND_COLOR = {
    'mutable_alias':   'red',
    'scope_escape':    'red',
    'use_after_scope': 'red',
    'thread_escape':   'yellow',
    'thread_race':     'red',
    'thread_self_race':'yellow',
    'heap_leak':       'yellow',
    'potential_leak':  'yellow',
    'use_after_free':  'red',
    'buffer_overflow': 'red',
    'out_of_bounds':   'red',
}


def _c(key: str, text: str, use_color: bool) -> str:
    if not use_color:
        return text
    return f"{COLORS.get(key, '')}{text}{COLORS['reset']}"


def print_violations(violations: list[Violation], mode: str = 'error',
                     use_color: bool = True, json_out: bool = False,
                     file=sys.stderr):
    """
    Print all violations.
    mode: 'error' prints to stderr and marks as errors,
          'warn'  prints to stderr and marks as warnings.
    json_out: emit JSON array instead of human text.
    """
    if not violations:
        return

    if json_out:
        out = []
        for v in violations:
            out.append({
                'kind':    v.kind,
                'message': v.message,
                'file':    v.file,
                'line':    v.line,
                'detail':  v.detail,
                'level':   mode,
            })
        print(json.dumps(out, indent=2))
        return

    level_str = 'error' if mode == 'error' else 'warning'
    level_color = 'red' if mode == 'error' else 'yellow'

    _fatal = ('async_contradiction',)
    for v in violations:
        color = KIND_COLOR.get(v.kind, 'red')
        lvl = 'error' if v.kind in _fatal else level_str
        print(
            f"{_c('bold', f'[FBC {lvl}]', use_color)} "
            f"{_c(color, v.kind, use_color)}",
            file=file
        )
        print(
            f"  {_c('cyan', f'{v.file}:{v.line}', use_color)}  {v.message}",
            file=file
        )
        for d in v.detail:
            print(f"  {_c('dim', d, use_color)}", file=file)
        print(file=file)


def print_summary(violations: list[Violation], files_checked: int,
                  funcs_checked: int, use_color: bool = True,
                  json_out: bool = False, file=sys.stdout):
    """Print a summary line after all violations."""
    if json_out:
        return  # JSON output already contains everything

    n = len(violations)
    if n == 0:
        print(
            _c('bold', f'[FBC] ', use_color) +
            _c('cyan', f'OK', use_color) +
            f' -- {files_checked} file(s), {funcs_checked} function(s) checked, no violations found.',
            file=file
        )
    else:
        kinds = {}
        for v in violations:
            kinds[v.kind] = kinds.get(v.kind, 0) + 1
        kind_str = ', '.join(f"{k}: {c}" for k, c in sorted(kinds.items()))
        print(
            _c('bold', f'[FBC] ', use_color) +
            _c('red', f'{n} violation(s)', use_color) +
            f' -- {files_checked} file(s), {funcs_checked} function(s) checked',
            file=file
        )
        print(f'  {kind_str}', file=file)