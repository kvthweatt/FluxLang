#!/usr/bin/env python3
"""
Flux Compiler Configuration Loader
"""

import os
from pathlib import Path


def load_config():
    """Load config from flux_config.cfg"""
    # Find config file: cwd/config/flux_config.cfg
    current_dir = Path.cwd()
    config_file = current_dir / "config" / "flux_config.cfg"
    
    config = {}
    
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