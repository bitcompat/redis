"""Run with python3 tests/test_permissions.py; exercise runtime permission policy."""
from pathlib import Path
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
libs = list((root / 'prebuildfs/opt/bitnami/scripts').glob('lib*.sh'))
libs += [root / 'rootfs/opt/bitnami/scripts/libredis.sh',
         root / 'rootfs/opt/bitnami/scripts/redis-env.sh']
assert len(libs) == 14
assert all(path.stat().st_mode & 0o7777 == 0o644 for path in libs)
for name in ['entrypoint.sh', 'run.sh', 'setup.sh', 'postunpack.sh']:
    assert (root / 'rootfs/opt/bitnami/scripts/redis' / name).stat().st_mode & 0o111
command = next(line.strip() for line in (root / 'Dockerfile').read_text().splitlines()
               if line.strip().startswith('find / -xdev'))
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    for name, mode in [('setuid', 0o4755), ('setgid', 0o2755), ('plain', 0o755)]:
        sample = path / name
        sample.touch()
        sample.chmod(mode)
    subprocess.run(['bash', '-e', '-c', command.replace('find / ', 'find ' + shlex.quote(directory) + ' ', 1)], check=True)
    assert all(sample.stat().st_mode & 0o7777 == 0o755 for sample in path.iterdir())
print('PASS: sourced scripts are 0644; lifecycle scripts executable; SUID/SGID removed')
