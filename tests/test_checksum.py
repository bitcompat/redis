"""Run with python3 tests/test_checksum.py; checks the Dockerfile checksum command."""

import hashlib
from pathlib import Path
import subprocess
import tempfile

dockerfile = (Path(__file__).resolve().parents[1] / "Dockerfile").read_text()
command = next(line.strip() for line in dockerfile.splitlines() if "sha256sum -c -" in line)
command = command.replace(r"\$", "$")
payload = b"test Redis archive\n"
digest = hashlib.sha256(payload).hexdigest()
record = f"hash redis-8.2.1.tar.gz sha256 {digest} https://example.invalid/redis\n"

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    (root / "redis.tar.gz").write_bytes(payload)
    for name, manifest, expected in [
        ("exact filename", record + "hash redis-8.2.10.tar.gz sha256 " + "0" * 64 + " unused\n", True),
        ("missing version", record.replace("8.2.1", "8.2.10"), False),
        ("duplicate version", record * 2, False),
        ("wrong algorithm", record.replace("sha256", "sha1"), False),
        ("corrupt archive", record.replace(digest, "0" * 64), False),
    ]:
        (root / "README.md").write_text(manifest)
        result = subprocess.run(
            ["bash", "-o", "pipefail", "-c", "BUILD_VERSION=8.2.1; " + command],
            cwd=root, capture_output=True, text=True,
        )
        assert (result.returncode == 0) == expected, (name, result.stdout, result.stderr)
        print("PASS:", name)
