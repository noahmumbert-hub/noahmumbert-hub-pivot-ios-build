"""Two bounded read-only API observations; never score prediction accuracy."""
import datetime as dt
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

BASE = 'https://pivot-reopen-radar.akpotato.chatgpt.site'
MAX_BYTES = 2 * 1024 * 1024


def classify(status, content_type, body, park):
    result = {'httpStatus': status, 'contentType': content_type,
              'bodyBytes': len(body), 'bodySha256': hashlib.sha256(body).hexdigest()}
    if not 200 <= status < 300:
        return result | {'classification': 'http_error'}
    if 'application/json' not in content_type.lower():
        return result | {'classification': 'unexpected_content_type'}
    try:
        payload = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return result | {'classification': 'invalid_json'}
    if (not isinstance(payload, dict) or payload.get('parkId') != park
            or not isinstance(payload.get('rides'), list)
            or not isinstance(payload.get('fetchedAt'), str)):
        return result | {'classification': 'unexpected_snapshot_contract'}
    try:
        fetched = dt.datetime.fromisoformat(payload['fetchedAt'].replace('Z', '+00:00'))
        age = (dt.datetime.now(dt.timezone.utc) - fetched).total_seconds()
    except (ValueError, TypeError):
        return result | {'classification': 'invalid_fetch_clock'}
    # This is an observation threshold, not a model deadline or provider status age.
    classification = ('inactive_park_observed' if payload.get('parkActive') is False else
                      'feed_unhealthy_or_unknown' if payload.get('feedHealthy') is not True else
                      'snapshot_clock_outside_5m_observation_limit' if not -60 <= age <= 300 else
                      'empty_rides_unverified' if not payload['rides'] else
                      'snapshot_observed')
    return result | {'classification': classification, 'parkId': park,
        'parkActive': payload.get('parkActive'), 'feedHealthy': payload.get('feedHealthy'),
        'fetchedAt': payload['fetchedAt'], 'fetchAgeSeconds': round(age, 3),
        'sourceUpdatedAt': payload.get('sourceUpdatedAt'),
        'sourceUpdatedAtByProvider': payload.get('sourceUpdatedAtByProvider'),
        'cacheAgeSeconds': payload.get('cacheAgeSeconds'), 'rideCount': len(payload['rides']),
        'forecastCount': sum(isinstance(r, dict) and r.get('estimate') is not None
                             for r in payload['rides'])}


def observe(park):
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    clock = time.monotonic()
    with tempfile.TemporaryDirectory() as folder:
        body_path = Path(folder) / 'body'
        try:
            response = subprocess.run(['curl', '--silent', '--show-error', '--proto', '=https',
                '--connect-timeout', '5', '--max-time', '15', '--max-filesize', str(MAX_BYTES),
                '--retry', '0', '--header', 'Accept: application/json',
                '--user-agent', 'PIVOT-native-monitor/1.0', '--output', str(body_path),
                '--write-out', '%{http_code}\n%{content_type}', f'{BASE}/api/live?park={park}'],
                capture_output=True, text=True, timeout=20)
            if response.returncode:
                result = {'classification': 'transport_or_body_limit_error',
                          'curlExitCode': response.returncode}
            else:
                status, _, content_type = response.stdout.partition('\n')
                result = classify(int(status), content_type, body_path.read_bytes(), park)
        except (subprocess.TimeoutExpired, OSError, ValueError):
            result = {'classification': 'observation_error'}
    return result | {'requestedPark': park, 'requestStartedAt': started,
                     'requestFinishedAt': dt.datetime.now(dt.timezone.utc).isoformat(),
                     'elapsedSeconds': round(time.monotonic() - clock, 3)}


def main():
    records = [observe(park) for park in (5, 65)]
    report = {'kind': 'live_api_observation', 'observations': records,
              'limits': 'Two GETs, no retries, 15 seconds and 2 MiB each; no continuity or prediction score.'}
    output = Path('build/monitor')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'live-api.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return 0 if all(r['classification'] in ('snapshot_observed', 'inactive_park_observed')
                    for r in records) else 1


if __name__ == '__main__':
    raise SystemExit(main())
