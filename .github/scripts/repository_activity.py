"""Publish a 14-day clone chart via GitHub's API, without cloning the repo."""

from datetime import datetime, timedelta, timezone
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


def daily_counts(payload, now):
    """Include today (partial) and the preceding 13 UTC calendar days."""
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
        date = datetime.strptime(stamp, '%Y-%m-%dT%H:%M:%SZ').date()
        if not stamp.endswith('T00:00:00Z') or date in rows or date > now.date():
            raise ValueError('Invalid or duplicate clone date.')
        rows[date] = count
    if sum(rows.values()) != total:
        raise ValueError('Clone total does not match daily readings.')
    start = now.date() - timedelta(days=13)
    return [(start + timedelta(days=i), rows.get(start + timedelta(days=i), 0))
            for i in range(14)]


def axis_max(peak):
    if peak <= 4:
        return 4
    magnitude = 10 ** math.floor(math.log10(peak))
    for factor in (1, 2, 4, 5, 10):
        if factor * magnitude >= peak:
            return factor * magnitude


def render_svg(days, now):
    total = sum(count for _, count in days)
    yesterday = days[-2][1]
    ceiling = axis_max(max(count for _, count in days))
    date_range = f'{days[0][0]:%b %d}–{days[-1][0]:%b %d, %Y}'
    updated = now.strftime('%b %d, %Y %H:%M UTC')
    svg = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="860" height="260" viewBox="0 0 860 260" role="img" aria-labelledby="title description">
<title id="title">Repository activity — Git clones</title>
<desc id="description">{escape(date_range)}: {total:,} Git clones, including {yesterday:,} yesterday. Today is partial. Clones are not unique users or app downloads. Updated {updated}.</desc>
<style>
.card{{fill:#fff;stroke:#d1d9e0}}.main{{fill:#1f2328}}.muted{{fill:#59636e}}
.grid{{stroke:#d1d9e0;stroke-opacity:.65}}.bar{{fill:#5798e8}}.zero{{fill:#d1d9e0}}
text{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}}
@media(prefers-color-scheme:dark){{.card{{fill:#0d1117;stroke:#30363d}}.main{{fill:#f0f6fc}}.muted{{fill:#9198a1}}.grid{{stroke:#30363d}}.bar{{fill:#79aff4}}.zero{{fill:#30363d}}}}
</style>
<rect class="card" x=".5" y=".5" width="859" height="259" rx="12"/>
<text class="main" x="24" y="34" font-size="17" font-weight="600">Repository activity</text>
<text class="muted" x="24" y="56" font-size="12">Git clones · {date_range} · UTC</text>
<text class="main" x="596" y="35" font-size="26" font-weight="600">{yesterday:,}</text>
<text class="muted" x="596" y="55" font-size="11">Yesterday</text>
<text class="main" x="729" y="35" font-size="26" font-weight="600">{total:,}</text>
<text class="muted" x="729" y="55" font-size="11">Last 14 days</text>''']
    for tick in (0, ceiling / 2, ceiling):
        y = 190 - tick / ceiling * 102
        label = f'{tick:g}' if tick < 1000 else f'{tick / 1000:g}k'
        svg.append(f'<line class="grid" x1="24" x2="807" y1="{y:g}" y2="{y:g}"/>')
        svg.append(f'<text class="muted" x="818" y="{y+4:g}" font-size="10">{label}</text>')
    for i, (date, count) in enumerate(days):
        x = 28 + i * 56
        height = max(2, count / ceiling * 102)
        cls = 'bar' if count else 'zero'
        opacity = '.65' if date == now.date() else '1'
        label = 'Today' if date == now.date() else f'{date.day} {date:%b}'
        svg.append(f'<rect class="{cls}" opacity="{opacity}" x="{x}" y="{190-height:.2f}" width="34" height="{height:.2f}" rx="3"/>')
        if count:
            svg.append(f'<text class="main" x="{x+17}" y="{183-height:.2f}" text-anchor="middle" font-size="10">{count:,}</text>')
        svg.append(f'<text class="muted" x="{x+17}" y="211" text-anchor="middle" font-size="10">{label}</text>')
    svg.append(f'<text class="muted" x="24" y="240" font-size="11">Updated {updated} · Today is partial · Clones aren’t unique users.</text></svg>')
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
    days = daily_counts(payload, now)
    files = {
        'repository-activity.svg': render_svg(days, now),
        'activity.json': json.dumps({
            'updated_at': now.isoformat(), 'timezone': 'UTC',
            'metric': 'git_clones', 'today_is_partial': True,
            'days': [{'date': date.isoformat(), 'count': count} for date, count in days],
        }, indent=2) + '\n',
        'README.md': '# Repository activity\n\nGenerated daily for [PerformanceHUD](https://github.com/zzoko/PerformanceHUD).\n'
                     '\nGit clones are operations, not unique users or app downloads. Today is partial; dates are UTC.\n'
                     '\n![Repository activity](repository-activity.svg)\n',
    }
    publish(GitHub(write_token), files, now)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        print(f'Activity update failed: {error}', file=sys.stderr)
        sys.exit(1)
