import importlib.util
from pathlib import Path
import tempfile
import subprocess
from unittest.mock import patch
import unittest

spec = importlib.util.spec_from_file_location('cloud_setup', Path(__file__).parents[1] / 'scripts/setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def test_fresh_world_uses_sqlite_and_enables_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'minetest.conf.example').write_text('ai_gate_deadline = 4\n')
            setup.prepare(root)
            text = (root / 'runtime/.minetest/worlds/hacked/world.mt').read_text()
            self.assertIn('auth_backend = sqlite3', text)
            self.assertIn('player_backend = sqlite3', text)
            self.assertIn('mod_storage_backend = sqlite3', text)
            self.assertIn('load_mod_ai_gate = true', text)

    def test_existing_data_config_and_backends_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'minetest.conf.example').write_text('ai_gate_deadline = 4\n')
            setup.prepare(root)
            config = root / 'config/minetest.conf'
            config.write_text('fixture_private_setting = preserve\n')
            world = root / 'runtime/.minetest/worlds/hacked'
            (world / 'world.mt').write_text('gameid = mineclonia\nauth_backend = files\nload_mod_ai_gate = false\n')
            (world / 'auth.txt').write_bytes(b'fixture-account-data')
            setup.prepare(root)
            self.assertEqual(config.read_text(), 'fixture_private_setting = preserve\n')
            self.assertIn('auth_backend = files', (world / 'world.mt').read_text())
            self.assertIn('load_mod_ai_gate = true', (world / 'world.mt').read_text())
            self.assertEqual((world / 'auth.txt').read_bytes(), b'fixture-account-data')

    def test_other_game_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'minetest.conf.example').write_text('')
            setup.prepare(root)
            world = root / 'runtime/.minetest/worlds/hacked/world.mt'
            world.write_text('gameid = another_game\n')
            with self.assertRaises(RuntimeError):
                setup.prepare(root)
            self.assertEqual(world.read_text(), 'gameid = another_game\n')

    def test_failed_download_is_retryable_and_leaves_no_partial_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'games').mkdir()
            (root / 'mineclonia.lock.json').write_text('{"repository":"fixture", "revision":"fixture-revision"}')
            with patch.object(setup.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'fixture-git')):
                with self.assertRaises(subprocess.CalledProcessError):
                    setup.fetch_game(root)
            self.assertEqual(list((root / 'games').iterdir()), [])
