#!/usr/bin/env python3
"""CLI only; arithmetic, metrics, experiments and reporting live in subpackages."""
from pathlib import Path
import argparse
import sys
package_parent = Path(__file__).resolve().parents[1]
bootstrap = argparse.ArgumentParser(add_help=False)
bootstrap.add_argument('--repo-root', type=Path, default=package_parent.parent)
bootstrap_args, _ = bootstrap.parse_known_args()
sys.path.insert(0, str(bootstrap_args.repo_root.resolve() / 'analyze'))
sys.path.insert(0, str(package_parent))
from exp_v18a.pipeline import main

if __name__=='__main__':
    raise SystemExit(main())
