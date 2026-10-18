import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import live_api
import report_results


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

    def test_summary_keeps_text_and_omits_binary_screenshots(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'source-sha.txt').write_text('released-sha')
            (root / 'fixtures-summary.json').write_text('{"passedTests": 191}')
            (root / 'fixtures-screenshots').mkdir()
            (root / 'fixtures-screenshots' / 'screen.png').write_bytes(b'SECRET_BINARY_IMAGE')
            result = report_results.render(root)
            self.assertIn('released-sha', result)
            self.assertIn('passedTests', result)
            self.assertIn('191', result)
            self.assertIn('Screenshots are transient', result)
            self.assertNotIn('SECRET_BINARY_IMAGE', result)
            self.assertIn('unverified / no completion record', result)

    def test_summary_bounds_text_and_preserves_performance_measurement(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'fixtures-summary.json').write_text('x' * 100000)
            (root / 'fixtures.log').write_text('PIVOT_PERF {"samples": 7}\n')
            result = report_results.render(root)
            self.assertIn('truncated', result)
            self.assertIn('PIVOT_PERF', result)
            self.assertLess(len(result), 50000)


if __name__ == '__main__':
    unittest.main()
