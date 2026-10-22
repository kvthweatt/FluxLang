#!/usr/bin/env python3
"""
Flux Effect Geometry Visualizer (eg.py)

Standalone entry point. All render logic lives in vizcore.py.

Usage:
    python eg.py
    python eg.py --expr "*Hook.Detour & !Alloc"
"""

import sys
import argparse

def main():
    ap = argparse.ArgumentParser(description='Flux Effect Geometry Visualizer')
    ap.add_argument('--expr', default='*Hook.Detour & !Alloc & ~IO & Hook.Detour ^| Process.Inject',
                    help='Initial effect expression to visualize')
    args = ap.parse_args()

    from vizcore import launch_effect_full
    launch_effect_full(args.expr)

if __name__ == '__main__':
    main()