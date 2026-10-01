import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location(
    'activity', Path(__file__).parents[1] / 'scripts/repository_activity.py')
activity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(activity)
NOW = datetime(2026, 10, 1, 6, 23, tzinfo=timezone.utc)


def payload(rows):
    return {'count': sum(c for _, c in rows), 'clones': [
        {'timestamp': f'{date}T00:00:00Z', 'count': count}
        for date, count in rows]}


class ActivityTests(unittest.TestCase):
    def test_utc_window_ends_yesterday_and_excludes_today(self):
        days = activity.daily_counts(payload([
            ('2026-09-17', 100), ('2026-09-30', 19), ('2026-10-01', 2)]), NOW)
        self.assertEqual(len(days), 14)
        self.assertEqual(days[0][0].isoformat(), '2026-09-17')
        self.assertEqual(days[-1][0].isoformat(), '2026-09-30')
        self.assertEqual(days[-1][1], 19)
        self.assertEqual(sum(c for _, c in days), 119)
        svg = activity.render_svg(days, NOW)
        ET.fromstring(svg)
        self.assertIn('119 Git clones, including 19 yesterday', svg)
        self.assertNotIn('Today', svg)
        self.assertNotIn('unique users', svg)
        self.assertIn('Oct 01, 2026 06:23 UTC', svg)

    def test_valid_zero_activity_is_renderable(self):
        days = activity.daily_counts({'count': 0, 'clones': []}, NOW,
                                    {'days': [{'date': '2026-09-17', 'count': 0}]})
        self.assertEqual(sum(c for _, c in days), 0)
        svg = activity.render_svg(days, NOW)
        root = ET.fromstring(svg)
        bars = root.findall("{http://www.w3.org/2000/svg}rect[@class='zero']")
        self.assertEqual(len(bars), 14)
        self.assertNotIn('nan', svg.lower())

    def test_bad_responses_do_not_turn_into_zero_counts(self):
        bad = [{}, {'message': 'Bad credentials'}, {'count': 2, 'clones': []},
               {'count': -1, 'clones': []}, {'count': True, 'clones': []}]
        for data in bad:
            with self.subTest(data=data), self.assertRaises(ValueError):
                activity.daily_counts(data, NOW)

    def test_duplicate_future_and_negative_readings_rejected(self):
        for rows in [ [('2026-10-01', 1), ('2026-10-01', 1)],
                      [('2026-10-02', 1)], [('2026-10-01', -1)] ]:
            with self.subTest(rows=rows), self.assertRaises(ValueError):
                activity.daily_counts(payload(rows), NOW)

    def test_year_boundary(self):
        now = datetime(2027, 1, 1, tzinfo=timezone.utc)
        days = activity.daily_counts(payload([('2026-12-31', 3)]), now)
        self.assertEqual(days[0][0].isoformat(), '2026-12-18')
        self.assertEqual(days[-1][1], 3)

    def test_oldest_day_preserved_when_it_expires_from_api(self):
        previous = {'days': [{'date': '2026-09-17', 'count': 7},
                             {'date': '2026-09-30', 'count': 5}]}
        days = activity.daily_counts(payload([('2026-09-30', 19)]), NOW, previous)
        self.assertEqual(days[0][1], 7)
        self.assertEqual(days[-1][1], 19)

    def test_missing_oldest_day_is_not_reported_as_zero(self):
        days = activity.daily_counts(payload([('2026-09-30', 19)]), NOW)
        self.assertIsNone(days[0][1])
        svg = activity.render_svg(days, NOW)
        self.assertIn('≥19', svg)
        self.assertIn('1 day(s) unavailable', svg)

    def test_history_preserves_completed_days_for_total_but_excludes_today(self):
        previous = {'history': [{'date': '2025-01-01', 'count': 100},
                                {'date': '2026-09-17', 'count': 7},
                                {'date': '2026-10-01', 'count': 50}]}
        history = activity.collected_counts(payload([('2026-10-01', 100)]), NOW, previous)
        self.assertNotIn(NOW.date(), history)
        self.assertTrue(all(d < NOW.date() for d in history))
        self.assertEqual(sum(history.values()), 107)
        svg = activity.render_svg(activity.completed_days(history, NOW), NOW, history)
        self.assertIn('Total tracked: 107', svg)
        self.assertIn('since 2025-01-01', svg)

    def test_repeat_snapshots_do_not_double_count(self):
        data = payload([('2026-09-17', 7), ('2026-09-30', 19)])
        previous = {'history': [{'date': '2026-09-17', 'count': 7},
                                {'date': '2026-09-30', 'count': 15}]}
        history = activity.collected_counts(data, NOW, previous)
        self.assertEqual(sum(history.values()), 26)
        repeated = {'history': [{'date': d.isoformat(), 'count': c} for d, c in history.items()]}
        self.assertEqual(activity.collected_counts(data, NOW, repeated), history)

    def test_axis_contains_peak(self):
        for peak in (0, 1, 5, 9, 19, 35, 100, 1423, 10000):
            self.assertGreaterEqual(activity.axis_max(peak), peak)

    def test_missing_secret_performs_no_requests(self):
        with patch.dict('os.environ', {'GITHUB_REPOSITORY': activity.REPOSITORY}, clear=True):
            with patch.object(activity.GitHub, 'call') as request:
                with self.assertRaisesRegex(RuntimeError, 'TRAFFIC_TOKEN'):
                    activity.main()
                request.assert_not_called()

    def test_fetch_failure_cannot_publish(self):
        env = {'GITHUB_REPOSITORY': activity.REPOSITORY,
               'GITHUB_TOKEN': 'test-only', 'TRAFFIC_TOKEN': 'test-only'}
        with patch.dict('os.environ', env, clear=True):
            with patch.object(activity.GitHub, 'call', side_effect=RuntimeError('HTTP 403')):
                with patch.object(activity, 'publish') as publish:
                    with self.assertRaises(RuntimeError):
                        activity.main()
                    publish.assert_not_called()


class FakeAPI:
    def __init__(self, existing=False, unrelated=False):
        self.existing, self.unrelated = existing, unrelated
        self.calls = []

    def call(self, path, method='GET', data=None, missing_ok=False):
        self.calls.append((path, method, data))
        if path == 'git/ref/heads/stats':
            return {'object': {'sha': 'old-head'}} if self.existing else None
        if path == 'git/commits/old-head':
            return {'tree': {'sha': 'old-tree'}}
        if path == 'git/trees/old-tree':
            return {'tree': [{'path': 'unrelated.txt' if self.unrelated else 'activity.json'}]}
        return {'sha': {'git/blobs': 'blob', 'git/trees': 'new-tree',
                        'git/commits': 'new-head'}.get(path, 'ok')}


class PublishingTests(unittest.TestCase):
    def test_initial_stats_branch_is_isolated(self):
        api = FakeAPI()
        activity.publish(api, {'repository-activity.svg': '<svg/>'}, NOW)
        commit = next(data for path, _, data in api.calls if path == 'git/commits')
        self.assertEqual(commit['parents'], [])
        self.assertEqual(api.calls[-1], ('git/refs', 'POST',
                                        {'ref': 'refs/heads/stats', 'sha': 'new-head'}))
        self.assertFalse(any('main' in path or 'tags/' in path for path, _, _ in api.calls))

    def test_updates_preserve_history_and_never_force(self):
        api = FakeAPI(existing=True)
        activity.publish(api, {'repository-activity.svg': '<svg/>'}, NOW)
        commit = next(data for path, _, data in api.calls if path == 'git/commits')
        self.assertEqual(commit['parents'], ['old-head'])
        self.assertEqual(api.calls[-1], ('git/refs/heads/stats', 'PATCH',
                                        {'sha': 'new-head', 'force': False}))

    def test_unrelated_branch_is_not_overwritten(self):
        api = FakeAPI(existing=True, unrelated=True)
        with self.assertRaisesRegex(RuntimeError, 'unrelated files'):
            activity.publish(api, {'repository-activity.svg': '<svg/>'}, NOW)
        self.assertTrue(all(method == 'GET' for _, method, _ in api.calls))


if __name__ == '__main__':
    unittest.main()
