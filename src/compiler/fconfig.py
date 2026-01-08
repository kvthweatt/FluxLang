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


# Load config when module is imported
config = load_config()