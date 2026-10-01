"""Publish a 14-day clone chart via GitHub's API, without cloning the repo."""

import base64
from datetime import date, datetime, timedelta, timezone
from html import escape
import json
import math
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPOSITORY = 'zzoko/PerformanceHUD'
BRANCH = 'stats'
API = 'https://api.github.com'


class GitHub:
    def __init__(self, token):
        self.token = token

    def call(self, path, method='GET', data=None, missing_ok=False):
        request = Request(
            f'{API}/repos/{REPOSITORY}/{path}',
            data=None if data is None else json.dumps(data).encode(),
            method=method,
            headers={
                'Authorization': f'Bearer {self.token}',
                'Accept': 'application/vnd.github+json',
                'X-GitHub-Api-Version': '2022-11-28',
                'User-Agent': 'PerformanceHUD-repository-activity',
                'Content-Type': 'application/json',
            },
        )
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            if missing_ok and error.code == 404:
                return None
            # Never print request headers, credentials, or raw response bodies.
            raise RuntimeError(f'GitHub API {method} {path}: HTTP {error.code}') from None
        except URLError:
            raise RuntimeError('Could not reach the GitHub API; previous graph preserved.') from None


def collected_counts(payload, now, previous=None):
    """Keep recent known readings so the oldest complete day can leave the API window."""
    if not isinstance(payload, dict) or not isinstance(payload.get('clones'), list):
        raise ValueError('Invalid clone statistics response.')
    total = payload.get('count')
    if type(total) is not int or total < 0:
        raise ValueError('Invalid clone total.')
    rows = {}
    for item in payload['clones']:
        stamp = item['timestamp']
        count = item['count']
        if type(count) is not int or count < 0:
            raise ValueError('Invalid daily clone count.')
        day = datetime.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ').date()
        if not stamp.endswith('T00:00:00Z') or day in rows or day > now.date():
            raise ValueError('Invalid or duplicate clone date.')
        rows[day] = count
    if sum(rows.values()) != total:
        raise ValueError('Clone total does not match daily readings.')
    history = {}
    for item in (previous or {}).get('history', (previous or {}).get('days', [])):
        day = date.fromisoformat(item['date'])
        count = item['count']
        if count is None:
            continue
        if type(count) is not int or count < 0:
            raise ValueError('Invalid saved clone count.')
        if day < now.date():
            history[day] = count
    # Missing days inside the API's recent window represent zero activity.
    # Do not invent a zero for an older day that may already have expired.
    for i in range(1, 14):
        day = now.date() - timedelta(days=i)
        history[day] = rows.get(day, 0)
    history.update({day: count for day, count in rows.items()
                    if now.date() - timedelta(days=30) <= day < now.date()})
    return history


def completed_days(history, now):
    start = now.date() - timedelta(days=14)
    return [(start + timedelta(days=i), history.get(start + timedelta(days=i)))
            for i in range(14)]


def daily_counts(payload, now, previous=None):
    return completed_days(collected_counts(payload, now, previous), now)


def axis_max(peak):
    if peak <= 4:
        return 4
    magnitude = 10 ** math.floor(math.log10(peak))
    for factor in (1, 2, 4, 5, 10):
        if factor * magnitude >= peak:
            return factor * magnitude


def render_svg(days, now, history=None):
    total = sum(count or 0 for _, count in days)
    missing = sum(count is None for _, count in days)
    total_label = f'≥{total:,}' if missing else f'{total:,}'
    yesterday = days[-1][1]
    ceiling = axis_max(max(count or 0 for _, count in days))
    date_range = f'{days[0][0]:%b %d}–{days[-1][0]:%b %d, %Y}'
    updated = now.strftime('%b %d, %Y %H:%M UTC')
    tracked = history if history is not None else {d: c for d, c in days if c is not None}
    tracked_total = sum(tracked.values())
    tracked_since = min(tracked).isoformat() if tracked else 'unavailable'
    svg = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="860" height="260" viewBox="0 0 860 260" role="img" aria-labelledby="title description">
<title id="title">Repository activity — Git clones</title>
<desc id="description">{escape(date_range)}: {total_label} Git clones, including {yesterday:,} yesterday. Total tracked: {tracked_total:,} across saved dates since {tracked_since}. Completed UTC days only. Updated {updated}.</desc>
<style>
.card{{fill:#fff;stroke:#d1d9e0}}.main{{fill:#1f2328}}.muted{{fill:#59636e}}
.grid{{stroke:#d1d9e0;stroke-opacity:.65}}.bar{{fill:#5798e8}}.zero{{fill:#d1d9e0}}
text{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}}
@media(prefers-color-scheme:dark){{.card{{fill:#0d1117;stroke:#30363d}}.main{{fill:#f0f6fc}}.muted{{fill:#9198a1}}.grid{{stroke:#30363d}}.bar{{fill:#79aff4}}.zero{{fill:#30363d}}}}
</style>
<rect class="card" x=".5" y=".5" width="859" height="259" rx="12"/>
<text class="main" x="24" y="34" font-size="17" font-weight="600">Repository activity</text>
<text class="muted" x="24" y="56" font-size="12">Git clones · {date_range} · UTC</text>
<text class="main" x="464" y="35" font-size="26" font-weight="600">{yesterday:,}</text>
<text class="muted" x="464" y="55" font-size="11">Yesterday</text>
<text class="main" x="594" y="35" font-size="26" font-weight="600">{total_label}</text>
<text class="muted" x="594" y="55" font-size="11">Last 14 days</text>
<text class="main" x="724" y="35" font-size="26" font-weight="600">{tracked_total:,}</text>
<text class="muted" x="724" y="55" font-size="11">Total tracked</text>''']
    for tick in (0, ceiling / 2, ceiling):
        y = 190 - tick / ceiling * 102
        label = f'{tick:g}' if tick < 1000 else f'{tick / 1000:g}k'
        svg.append(f'<line class="grid" x1="24" x2="807" y1="{y:g}" y2="{y:g}"/>')
        svg.append(f'<text class="muted" x="818" y="{y+4:g}" font-size="10">{label}</text>')
    for i, (date, count) in enumerate(days):
        x = 28 + i * 56
        height = max(2, (count or 0) / ceiling * 102)
        cls = 'bar' if count else 'zero'
        label = f'{date.day} {date:%b}'
        if count is None:
            svg.append(f'<text class="muted" x="{x+17}" y="183" text-anchor="middle" font-size="12">—</text>')
        else:
            svg.append(f'<rect class="{cls}" x="{x}" y="{190-height:.2f}" width="34" height="{height:.2f}" rx="3"/>')
        if count:
            svg.append(f'<text class="main" x="{x+17}" y="{183-height:.2f}" text-anchor="middle" font-size="10">{count:,}</text>')
        svg.append(f'<text class="muted" x="{x+17}" y="211" text-anchor="middle" font-size="10">{label}</text>')
    missing_note = f' · {missing} day(s) unavailable' if missing else ''
    svg.append(f'<text class="muted" x="24" y="240" font-size="11">Updated {updated}{missing_note}</text></svg>')
    return '\n'.join(svg) + '\n'


def publish(api, files, now):
    """Create an isolated stats branch or fast-forward it; never touch main."""
    ref = api.call(f'git/ref/heads/{BRANCH}', missing_ok=True)
    head = None if ref is None else ref['object']['sha']
    base_tree = None
    if head:
        commit = api.call(f'git/commits/{head}')
        base_tree = commit['tree']['sha']
        existing = api.call(f'git/trees/{base_tree}')
        # Do not accidentally repurpose an unrelated branch named stats.
        allowed = {'repository-activity.svg', 'activity.json', 'README.md'}
        if existing.get('truncated') or any(e['path'] not in allowed for e in existing['tree']):
            raise RuntimeError('The stats branch contains unrelated files; refusing to overwrite it.')
    entries = []
    for path, content in files.items():
        blob = api.call('git/blobs', 'POST', {'content': content, 'encoding': 'utf-8'})
        entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})
    tree_body = {'tree': entries}
    if base_tree:
        tree_body['base_tree'] = base_tree
    tree = api.call('git/trees', 'POST', tree_body)
    if tree['sha'] == base_tree:
        print('Graph is already current.')
        return
    commit = api.call('git/commits', 'POST', {
        'message': f'Update repository activity ({now:%Y-%m-%d})',
        'tree': tree['sha'], 'parents': [] if head is None else [head],
    })
    if head:
        api.call(f'git/refs/heads/{BRANCH}', 'PATCH', {'sha': commit['sha'], 'force': False})
    else:
        api.call('git/refs', 'POST', {'ref': f'refs/heads/{BRANCH}', 'sha': commit['sha']})
    print('Updated the stats branch. Main and release tags were not changed.')


def main():
    if os.environ.get('GITHUB_REPOSITORY') != REPOSITORY:
        raise RuntimeError('This publisher is restricted to zzoko/PerformanceHUD.')
    traffic_token = os.environ.get('TRAFFIC_TOKEN', '')
    write_token = os.environ.get('GITHUB_TOKEN', '')
    if not traffic_token:
        raise RuntimeError('Add the TRAFFIC_TOKEN Actions secret with Administration: read access to this repository.')
    if not write_token:
        raise RuntimeError('GITHUB_TOKEN is missing.')
    now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
    # Only aggregate counts are published; authentication failures never become zeros.
    payload = GitHub(traffic_token).call('traffic/clones?per=day')
    writer = GitHub(write_token)
    saved = writer.call('contents/activity.json?ref=stats', missing_ok=True)
    previous = None if saved is None else json.loads(base64.b64decode(saved['content']))
    history = collected_counts(payload, now, previous)
    days = completed_days(history, now)
    files = {
        'repository-activity.svg': render_svg(days, now, history),
        'activity.json': json.dumps({
            'updated_at': now.isoformat(), 'timezone': 'UTC',
            'metric': 'git_clones', 'completed_days_only': True,
            'total_tracked': sum(history.values()),
            'tracked_since': min(history).isoformat() if history else None,
            'days': [{'date': date.isoformat(), 'count': count} for date, count in days],
            'history': [{'date': date.isoformat(), 'count': count}
                        for date, count in sorted(history.items())],
        }, indent=2) + '\n',
        'README.md': '# Repository activity\n\nGenerated daily for [PerformanceHUD](https://github.com/zzoko/PerformanceHUD).\n'
                     '\nGit clones are operations, not unique users or app downloads. The graph covers 14 completed UTC days, ending yesterday.\n'
                     '\n![Repository activity](repository-activity.svg)\n',
    }
    publish(writer, files, now)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        print(f'Activity update failed: {error}', file=sys.stderr)
        sys.exit(1)
