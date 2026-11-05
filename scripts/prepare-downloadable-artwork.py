#!/usr/bin/env python3
"""Build metadata only; never copy or reencode the accepted JPEGs."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SOURCE = '77191e42fb6dde600e6bc9a3ab948c7ce09ed4c2'
DESTINATION = ROOT / 'PIVOT/Resources/RideIllustrationMetadata/catalog.json'


def expected_catalog():
    original = subprocess.check_output(['git', '-C', str(ROOT), 'show',
        SOURCE + ':PIVOT/Resources/RideIllustrations/index.json'])
    selection = json.loads((ROOT / 'docs/ride-artwork/staged-release-selection-2026-11-04.json').read_text())
    assert hashlib.sha256(original).hexdigest() == selection['fullIndexSHA256']
    keys = set(selection['selectedKeys']) | set(selection['deferredKeys'])
    records = [dict(record, downloadSourceCommit=SOURCE) for record in json.loads(original)['records']
        if str(record['parkId']) + '-' + str(record['rideId']) in keys]
    assert len(records) == 1082
    return (json.dumps({'schemaVersion': 1, 'records': records}, ensure_ascii=False,
                       indent=2) + '\n').encode()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    arguments = parser.parse_args()
    payload = expected_catalog()
    if arguments.check:
        assert DESTINATION.read_bytes() == payload, 'Downloadable metadata differs from immutable accepted source'
    else:
        assert not DESTINATION.exists(), 'Refusing to replace existing metadata; review it first'
        DESTINATION.parent.mkdir(exist_ok=True)
        DESTINATION.write_bytes(payload)
    print(json.dumps({'records': 1082, 'files': 2164, 'originalJPEGBytes': 218526843,
        'manifestBytes': len(payload), 'manifestSHA256': hashlib.sha256(payload).hexdigest(),
        'immutableSource': SOURCE, 'imagesModified': False}, indent=2))
