"""Retain compact summaries, log tails and screenshots within a strict 20 MiB ZIP cap."""
import hashlib
import json
import os
from pathlib import Path
import zipfile

LIMIT = 20 * 1024 * 1024
RESERVE = 256 * 1024


def package(root, output):
    included, omitted = [], []
    used = 0
    # Summaries first, then screenshots. Never archive the unbounded xcresult databases.
    files = sorted((p for p in root.rglob('*') if p.is_file()),
                   key=lambda p: (p.suffix.lower() in ('.png', '.jpeg', '.jpg'), str(p)))
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            name = str(path.relative_to(root))
            size = path.stat().st_size
            if path.suffix == '.log':
                with path.open('rb') as stream:
                    stream.seek(max(0, size - 65536))
                    data = stream.read(65536)
            elif size <= LIMIT - RESERVE - used:
                data = path.read_bytes()
            else:
                omitted.append(name)
                continue
            if used + len(data) > LIMIT - RESERVE or len(included) >= 100:
                omitted.append(name)
                continue
            archive.writestr(name, data)
            included.append({'path': name, 'bytes': len(data), 'originalBytes': size,
                             'sha256': hashlib.sha256(data).hexdigest()})
            used += len(data)
        manifest = {'included': included, 'omitted': omitted, 'maximumZipBytes': LIMIT,
            'note': 'Logs may be tails. Exported test summaries and screenshots, not full xcresult. Missing evidence is unverified.'}
        manifest_data = json.dumps(manifest, indent=2).encode()
        if len(manifest_data) > RESERVE // 2:
            raise RuntimeError('Evidence manifest exceeds reserved space')
        archive.writestr('manifest.json', manifest_data)
    if output.stat().st_size > LIMIT:
        output.unlink()
        raise RuntimeError('Evidence ZIP exceeded 20 MiB; upload prevented')
    return manifest


def main():
    root = Path('build/monitor')
    root.mkdir(parents=True, exist_ok=True)
    manifest = package(root, Path('build/monitor-evidence.zip'))
    summary = ['Native monitoring evidence', '',
        'Fixture, live UI and live API outcomes are separate observations. No prediction accuracy or continuous uptime claim.', '',
        f"Retained files: {len(manifest['included'])}; omitted by cap: {len(manifest['omitted'])}.",
        'Retention: 1 day; ZIP limit: 20 MiB. Full xcresult databases are not uploaded.']
    for name in ('build', 'fixtures', 'live-ui'):
        path = root / f'{name}-execution.json'
        summary.append(f'{name}: ' + (path.read_text() if path.exists() else 'unverified / no completion record'))
    api = root / 'live-api.json'
    if api.exists():
        for record in json.loads(api.read_text())['observations']:
            summary.append(f"Live API park {record['requestedPark']}: {record['classification']}")
    else:
        summary.append('Live API: unverified / no observation record')
    text = '\n\n'.join(summary) + '\n'
    print(text)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
            stream.write(text)


if __name__ == '__main__':
    main()
