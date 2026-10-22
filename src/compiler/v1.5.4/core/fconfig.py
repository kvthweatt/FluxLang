#!/usr/bin/env python3
"""
Flux Compiler Configuration Loader
"""

import os
from pathlib import Path


_DEFAULTS = {
    'linker':               'lld-link',
    'architecture':         'x86-64',
    'cpu':                  'native',
    'mattr':                '',
    'subsystem':            'console',
    'mode':                 'release',
    'entrypoint':           'FRTStartup',
    'no_default_libraries': '0',
    'remove_unused_funcs':  '1',
    'comdat_folding':       '1',
    'marge_data_and_code':  '0',
    'merge_read_only_w_text': '0',
    'memory_alignment':     '0',
    'bin_disk_alignment':   '0',
    'driver_mode':          '0',
    'fixed_base_address':   '0',
    'incremental_linking':  '1',
    'strip_executable':     '0',
    'control_flow_guard':   '0',
    'aslr':                 '0',
    'dep_compatibility':    '0',
    'all_cores_for_lto':    '1',
    'lto_optimization_level': '3',
    'lib_files':            '',
    'debug_level':          'none',
    'default_byte_width':   '8',
}


def load_config():
    """Load config from flux_config.cfg"""
    # Find config file relative to compiler root (FLUXC_SRCDIR env var set by fxc.py)
    # Falls back to two levels up from this file (src/compiler -> root) if env not set
    srcdir = os.environ.get('FLUXC_SRCDIR')
    if srcdir:
        current_dir = Path(srcdir)
    else:
        current_dir = Path(__file__).parent.parent.parent  # src/compiler -> root
    config_file = current_dir / "config" / "flux_config.cfg"

    # Start with defaults so bare config['key'] accesses never KeyError
    config = dict(_DEFAULTS)

    if not os.path.exists(config_file):
        print(f"Warning: Config file not found at {config_file}")
        return config

    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()

            # Skip comments and empty lines
            if not line or line.startswith(';'):
                continue

            # Parse key=value
            if '=' in line:
                key, value = line.split('=', 1)
                key = key.strip()
                value = value.strip()

                # Remove inline comments
                if ';' in value:
                    value = value.split(';')[0].strip()

                config[key] = value

    return config


VALID_BYTE_WIDTHS = {4, 6, 7, 8, 9, 12, 18, 24, 36}


def get_byte_width(cfg: dict) -> int:
    """Return the configured byte width, validated against the allowed set."""
    raw = cfg.get('default_byte_width', '8')
    try:
        width = int(raw)
    except ValueError:
        print(f"Error: default_byte_width '{raw}' is not an integer. Defaulting to 8.")
        return 8
    if width not in VALID_BYTE_WIDTHS:
        print(f"Error: default_byte_width {width} is not a valid byte width.")
        print(f"       Valid widths: {sorted(VALID_BYTE_WIDTHS)}")
        raise SystemExit(1)
    return width


# Load config when module is imported
config = load_config()