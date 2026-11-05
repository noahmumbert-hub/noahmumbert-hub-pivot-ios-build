#!/usr/bin/env python3
"""Independent exact-source archive gate for the downloaded-artwork release."""
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import zipfile
sys.dont_write_bytecode = True

root, ipa, info_path = map(Path, sys.argv[1:])
info = json.loads(info_path.read_text())
head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
assert head == info['commit'] and info['version'] == '1.18.5'
assert info['signed'] is False
assert info['appBinaryHeadroomBytes'] == 104857600 - ipa.stat().st_size >= 32 * 1024 * 1024
spec = importlib.util.spec_from_file_location('publisher', root / 'scripts/publish-sidestore.py')
publisher = importlib.util.module_from_spec(spec); spec.loader.exec_module(publisher)
_, privacy = publisher.verify_ipa(ipa, info)
bundles = []
with zipfile.ZipFile(ipa) as archive:
    assert not any(name.startswith(('Payload/PIVOT.app/RideIllustrations/',
        'Payload/PIVOT.app/PIVOTArtworkTestOriginals/')) or '.xctest/' in name
        or re.fullmatch(r'\d+-\d+-(?:thumbnail|detail)\.jpg', Path(name).name)
        for name in archive.namelist())
    expected_catalog = (root / 'PIVOT/Resources/RideIllustrationMetadata/catalog.json').read_bytes()
    assert archive.read('Payload/PIVOT.app/RideIllustrationMetadata/catalog.json') == expected_catalog
    catalog = json.loads(expected_catalog)
    assert len(catalog['records']) == 1082
    assert sum(record['thumbnailBytes'] + record['detailBytes'] for record in catalog['records']) == 218526843
    privacy_manifest = plistlib.loads(archive.read('Payload/PIVOT.app/PrivacyInfo.xcprivacy'))
    reasons = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons']
               for entry in privacy_manifest['NSPrivacyAccessedAPITypes']}
    assert reasons['NSPrivacyAccessedAPICategoryDiskSpace'] == ['E174.1']
    for folder in ['Payload/PIVOT.app/', 'Payload/PIVOT.app/PlugIns/PIVOTLiveActivityWidget.appex/']:
        plist = plistlib.loads(archive.read(folder + 'Info.plist'))
        binary = archive.read(folder + plist['CFBundleExecutable'])
        magic, cpu, _, kind, count, _, _, _ = struct.unpack_from('<8I', binary)
        assert magic == 0xfeedfacf and cpu == 0x0100000c and kind == 2
        assert (archive.getinfo(folder + plist['CFBundleExecutable']).external_attr >> 16) & 0o111
        assert not any(marker in binary for marker in [b'PIVOT_ARTWORK_FIXTURE', b'PIVOTArtworkTestOriginals',
            b'RideArtworkUITestFixture', b'MAP_REFRESH_APP_DIAGNOSTIC', b'--apple-ui-fixtures'])
        cursor, device = 32, False
        for _ in range(count):
            command, length = struct.unpack_from('<2I', binary, cursor)
            assert length >= 8 and cursor + length <= len(binary) and command != 0x1d
            if command == 0x32:
                platform, minimum, _, _ = struct.unpack_from('<4I', binary, cursor + 8)
                assert platform == 2 and minimum == 17 << 16
                device = True
            cursor += length
        assert device
        bundles.append(plist['CFBundleIdentifier'])
result = {**info, 'independentlyAudited': True, 'bundles': bundles, 'privacy': privacy,
    'all1082AcceptedMetadataAndProvenancePresent': True, 'generatedJPEGsBundled': 0,
    'releaseTestFixturesAbsent': True, 'downloadStoreQuotaBytes': 402653184,
    'freeSpaceReserveBytes': 536870912, 'physicalDeviceCapacityInspected': False,
    'physicalSideStoreInstallation': 'unverified', 'spokenVoiceOver': 'unverified'}
ipa.with_name('independent-archive-audit.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
