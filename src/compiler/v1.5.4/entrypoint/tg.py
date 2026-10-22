#!/usr/bin/env python3
"""
Flux Type Geometry Visualizer (tg.py)

Standalone entry point. All render logic lives in vizcore.py.

Usage:
    python tg.py
    python tg.py --expr "D !~= B & [A !@ A] !~= C !`< D !-= A"
"""

import sys
import argparse

def main():
    ap = argparse.ArgumentParser(description='Flux Type Geometry Visualizer')
    ap.add_argument('--expr', default='D !~= B & [A !@ A] !~= C !`< D !-= A',
                    help='Initial type constraint expression to visualize')
    args = ap.parse_args()

    from vizcore import launch_type_full
    launch_type_full(args.expr)

if __name__ == '__main__':
    main()