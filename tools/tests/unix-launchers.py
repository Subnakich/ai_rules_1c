"""Unix launcher behavior without a PowerShell installation or network."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
INSTALL = REPO / 'install.sh'
PLUGIN = REPO / 'plugins/1c-rules/scripts/invoke-install.sh'


class Launchers(unittest.TestCase):
    def test_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory(prefix='1c launcher ') as work:
            binary = Path(work) / 'pwsh'
            binary.write_text('#!/bin/sh\nprintf "<%s>\\n" "$@"\nexit 19\n')
            binary.chmod(0o755)
            env = dict(os.environ, PATH=f'{work}:/usr/bin:/bin')
            for script, args in [
                (INSTALL, ['init', '-Tools', 'cursor', '-ProjectRoot', '/tmp/Проект с пробелами']),
                (PLUGIN, ['init', 'cursor', '-ProjectRoot', '/tmp/Проект с пробелами']),
            ]:
                result = subprocess.run(['/bin/sh', str(script), *args], env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 19, result.stderr)
                self.assertIn('</tmp/Проект с пробелами>', result.stdout)
                self.assertIn('<-File>', result.stdout)
                self.assertIn('<cursor>', result.stdout)

    def test_missing_runtime(self):
        # Restricted PATH with dirname only makes the test independent of CI pwsh.
        with tempfile.TemporaryDirectory() as work:
            dirname = Path(work) / 'dirname'
            dirname.symlink_to('/usr/bin/dirname')
            env = dict(os.environ, PATH=work)
            for script, args, expected in [
                (INSTALL, ['init'], 127),
                (PLUGIN, ['init', 'cursor'], 127),
                (PLUGIN, ['update', 'cursor'], 127),
                (PLUGIN, ['ensure', 'cursor'], 0),
            ]:
                result = subprocess.run(['/bin/sh', str(script), *args], env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertIn('PowerShell', result.stderr)


if __name__ == '__main__':
    unittest.main()
