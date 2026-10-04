"""Run: python3 tests/test_sbom.py IMAGE REDIS_VERSION (requires Docker)."""
import json
import subprocess
import sys

image, version = sys.argv[1:]
for name, base in [('redis', 'redis'), ('wait-for-port', 'common')]:
    result = subprocess.run(['docker', 'run', '--rm', '--entrypoint', '/bin/cat', image,
                             f'/opt/bitnami/{base}/.spdx-{name}.json'],
                            capture_output=True, text=True, check=True)
    sbom = json.loads(result.stdout)
    assert sbom['spdxVersion'] == 'SPDX-2.3'
    assert sbom['packages']
    assert 'Broadcom' not in str(sbom['creationInfo'])
    if name == 'redis':
        assert any(p['name'] == 'redis' and p.get('versionInfo') == version for p in sbom['packages'])
    else:
        assert any(p['name'] == 'github.com/bitnami/wait-for-port' for p in sbom['packages'])
        assert any(p['name'] == 'github.com/jessevdk/go-flags' for p in sbom['packages'])
    print(f'PASS: {name} SPDX describes installed components')
subprocess.run(['docker', 'run', '--rm', '--entrypoint', '/bin/sh', image, '-c',
                'test ! -e /usr/local/bin/syft && test ! -d /.cache/syft && test ! -d /tmp/syft-home/cache'], check=True)
print('PASS: scanner and its cache absent from runtime image')
