import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import live_api
import package_evidence


class MonitorChecks(unittest.TestCase):
    def payload(self, **changes):
        value = dict(parkId=5, rides=[{'estimate': None}], parkActive=True, feedHealthy=True,
                     fetchedAt=dt.datetime.now(dt.timezone.utc).isoformat(),
                     sourceUpdatedAt='2026-10-17T00:00:00Z')
        return json.dumps(value | changes).encode()

    def classify(self, body, status=200, content_type='application/json'):
        return live_api.classify(status, content_type, body, 5)

    def test_html_502_is_http_failure_not_json_or_zero_rides(self):
        result = self.classify(b'<html>Bad Gateway</html>', 502, 'text/html')
        self.assertEqual(result['classification'], 'http_error')
        self.assertNotIn('rideCount', result)

    def test_html_200_is_content_failure(self):
        self.assertEqual(self.classify(b'<html/>', content_type='text/html')['classification'],
                         'unexpected_content_type')

    def test_invalid_json_and_wrong_park_are_rejected(self):
        self.assertEqual(self.classify(b'{')['classification'], 'invalid_json')
        self.assertEqual(self.classify(self.payload(parkId=65))['classification'],
                         'unexpected_snapshot_contract')

    def test_provider_clock_not_replaced_or_used_as_fetch_age(self):
        result = self.classify(self.payload())
        self.assertEqual(result['classification'], 'snapshot_observed')
        self.assertEqual(result['sourceUpdatedAt'], '2026-10-17T00:00:00Z')

    def test_empty_data_and_unhealthy_feed_are_unverified(self):
        self.assertEqual(self.classify(self.payload(rides=[]))['classification'], 'empty_rides_unverified')
        self.assertEqual(self.classify(self.payload(feedHealthy=False))['classification'], 'feed_unhealthy_or_unknown')

    def test_stale_future_and_timezone_free_fetch_clocks(self):
        for hours in (-1, 1):
            date = dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=hours)
            self.assertEqual(self.classify(self.payload(fetchedAt=date.isoformat()))['classification'],
                             'snapshot_clock_outside_5m_observation_limit')
        self.assertEqual(self.classify(self.payload(fetchedAt='2026-10-18T12:00:00'))['classification'],
                         'invalid_fetch_clock')

    def test_inactive_park_does_not_become_prediction_failure(self):
        result = self.classify(self.payload(parkActive=False, rides=[], feedHealthy=False))
        self.assertEqual(result['classification'], 'inactive_park_observed')

    def test_transport_timeout_is_a_gap(self):
        with patch.object(live_api.subprocess, 'run', side_effect=live_api.subprocess.TimeoutExpired('curl', 20)) as run:
            result = live_api.observe(5)
        self.assertEqual(result['classification'], 'observation_error')
        args = run.call_args.args[0]
        self.assertIn('--max-time', args)
        self.assertNotIn('--location', args)
        self.assertEqual(args[-1], live_api.BASE + '/api/live?park=5')

    def test_evidence_cap_and_log_tail_preserve_small_screenshot(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'evidence'
            root.mkdir()
            (root / 'a.log').write_bytes(b'x' * 100000 + b'final-line')
            (root / 'screen.png').write_bytes(b'example screenshot')
            with (root / 'oversized.png').open('wb') as stream:
                stream.truncate(package_evidence.LIMIT + 1)
            output = Path(folder) / 'evidence.zip'
            report = package_evidence.package(root, output)
            self.assertLessEqual(output.stat().st_size, package_evidence.LIMIT)
            self.assertIn('oversized.png', report['omitted'])
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(len(archive.read('a.log')), 65536)
                self.assertTrue(archive.read('a.log').endswith(b'final-line'))
                self.assertEqual(archive.read('screen.png'), b'example screenshot')


if __name__ == '__main__':
    unittest.main()
