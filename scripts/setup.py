#!/usr/bin/env python3
"""Prepare persistent Docker bind mounts and fetch the pinned Mineclonia game."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def prepare(root: Path):
    for directory in ('games', 'config', 'runtime/.minetest/worlds/hacked/worldmods/ai_gate', 'runtime/cache'):
        (root / directory).mkdir(parents=True, exist_ok=True)
    config = root / 'config/minetest.conf'
    if not config.exists():
        config.write_bytes((root / 'minetest.conf.example').read_bytes())
    env = root / '.env'
    if not env.exists():
        env.write_text(f'PUID={os.getuid()}\nPGID={os.getgid()}\nPUBLISH_ADDRESS=127.0.0.1\nSERVER_PORT=30000\n')
    world = root / 'runtime/.minetest/worlds/hacked/world.mt'
    if not world.exists():
        world.write_text('gameid = mineclonia\nbackend = sqlite3\nplayer_backend = sqlite3\n'
                         'auth_backend = sqlite3\nmod_storage_backend = sqlite3\nload_mod_ai_gate = true\n')
    else:
        text = world.read_text()
        if not re.search(r'^\s*gameid\s*=\s*mineclonia\s*$', text, re.M):
            raise RuntimeError('Existing world is not identified as Mineclonia; left unchanged.')
        # Existing backend settings/data must never be replaced by defaults.
        if re.search(r'^\s*load_mod_ai_gate\s*=', text, re.M):
            text = re.sub(r'^\s*load_mod_ai_gate\s*=.*$', 'load_mod_ai_gate = true', text, flags=re.M)
        else:
            text = text.rstrip() + '\nload_mod_ai_gate = true\n'
        world.write_text(text)


def fetch_game(root: Path):
    lock = json.loads((root / 'mineclonia.lock.json').read_text())
    destination = root / 'games/mineclonia'
    if destination.exists():
        actual = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
        if actual != lock['revision']:
            raise RuntimeError('Existing Mineclonia revision differs from the lock; not overwritten.')
        return
    temporary = Path(tempfile.mkdtemp(prefix='.mineclonia-fetch-', dir=root / 'games'))
    try:
        subprocess.run(['git', 'init', str(temporary)], check=True)
        subprocess.run(['git', '-C', str(temporary), 'remote', 'add', 'origin', lock['repository']], check=True)
        subprocess.run(['git', '-C', str(temporary), 'fetch', '--depth', '1', 'origin', lock['revision']], check=True)
        subprocess.run(['git', '-C', str(temporary), 'checkout', '--detach', 'FETCH_HEAD'], check=True)
        temporary.rename(destination)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only', action='store_true', help='Prepare files without downloading the game')
    args = parser.parse_args()
    prepare(ROOT)
    if not args.prepare_only:
        fetch_game(ROOT)
    print('Prepared. Review .env and config/minetest.conf, then run: docker compose up -d')


if __name__ == '__main__':
    main()
