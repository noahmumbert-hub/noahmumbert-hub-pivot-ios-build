#!/usr/bin/env python3
"""Verify every immutable public original; no credentials, uploads or retries."""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REPO = 'noahmumbert-hub/noahmumbert-hub-pivot-ios-build'


def verify(record, variant):
    filename = record[variant + 'File']
    url = ('https://raw.githubusercontent.com/' + REPO + '/' + record['downloadSourceCommit']
           + '/PIVOT/Resources/RideIllustrations/' + filename)
    expected = record[variant + 'Bytes']
    request = urllib.request.Request(url, headers={'User-Agent': 'PIVOT-original-artwork-verification',
        'Accept-Encoding': 'identity'})
    try:
        digest = hashlib.sha256()
        count = 0
        with urllib.request.urlopen(request, timeout=30) as response:
            assert response.status == 200
            assert urllib.parse.urlparse(response.geturl()).hostname == 'raw.githubusercontent.com'
            for chunk in iter(lambda: response.read(64 * 1024), b''):
                count += len(chunk)
                assert count <= expected, 'Response exceeds original length'
                digest.update(chunk)
            length = response.headers.get('Content-Length')
            assert length is None or int(length) == count
        assert count == expected and digest.hexdigest() == record[variant + 'SHA256'], 'Original bytes differ'
        return {'file': filename, 'url': url, 'bytes': count, 'sha256': digest.hexdigest(), 'status': 200}
    except urllib.error.HTTPError as error:
        raise RuntimeError(filename + ': HTTP ' + str(error.code) + ' ' + error.reason) from None
    except urllib.error.URLError as error:
        raise RuntimeError(filename + ': transport ' + type(error.reason).__name__) from None


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--reuse-verified', type=Path, help='Reuse only exact matching previously verified immutable originals')
    arguments = parser.parse_args()
    manifest = ROOT / 'PIVOT/Resources/RideIllustrationMetadata/catalog.json'
    records = json.loads(manifest.read_text())['records']
    results, failures = [], []
    previous = json.loads(arguments.reuse_verified.read_text()) if arguments.reuse_verified else {}
    reusable = {item['url']: item for item in previous.get('files', []) if item.get('status') == 200}
    jobs = []
    for record in records:
        for variant in ['thumbnail', 'detail']:
            url = ('https://raw.githubusercontent.com/' + REPO + '/' + record['downloadSourceCommit']
                + '/PIVOT/Resources/RideIllustrations/' + record[variant + 'File'])
            old = reusable.get(url)
            if old and old['bytes'] == record[variant + 'Bytes'] and old['sha256'] == record[variant + 'SHA256']:
                results.append(old)
            else:
                jobs.append((record, variant))
    print('Reusing exactly verified originals:', len(results), 'new checks:', len(jobs), flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        pending = [executor.submit(verify, record, variant) for record, variant in jobs]
        for future in concurrent.futures.as_completed(pending):
            try:
                results.append(future.result())
            except Exception as error:
                failures.append(str(error))
                for item in pending:
                    item.cancel()
                break
            if len(results) % 100 == 0:
                print('Verified original files:', len(results), flush=True)
    report = {'manifestSHA256': hashlib.sha256(manifest.read_bytes()).hexdigest(),
        'verifiedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'verifiedFiles': len(results), 'verifiedBytes': sum(item['bytes'] for item in results),
        'allOriginalPublicFilesVerified': len(results) == 2 * len(records) and not failures,
        'repository': REPO, 'failures': failures, 'files': sorted(results, key=lambda item: item['file'])}
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: value for key, value in report.items() if key != 'files'}, indent=2))
    if failures or not report['allOriginalPublicFilesVerified']:
        raise SystemExit(1)
