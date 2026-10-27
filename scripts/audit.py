#!/usr/bin/env python3
"""Reject publication of paths outside the server source/deployment allowlist."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FILES = {'.gitignore', 'README.md', 'compose.yaml', 'mineclonia.lock.json', 'minetest.conf.example',
         '.github/workflows/test.yml', 'mods/ai_gate/init.lua', 'mods/ai_gate/dsl.lua',
         'mods/ai_gate/complexity.lua', 'mods/ai_gate/transport.lua', 'mods/ai_gate/mod.conf',
         'mods/ai_gate/settingtypes.txt', 'tests/ai_gate_test.lua', 'tests/complexity_test.lua',
         'tests/test_setup.py', 'scripts/setup.py', 'scripts/audit.py'}


def main():
    tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
    unexpected = sorted(set(filter(None, tracked)) - FILES)
    if unexpected:
        raise SystemExit('Unexpected tracked paths; not safe to publish: ' + ', '.join(unexpected))
    print(f'Publication audit passed: {len(list(filter(None, tracked)))} server-only tracked files.')


if __name__ == '__main__':
    main()
