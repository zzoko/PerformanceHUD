"""Puts a new HUD explorer render into the homepage: the stills' sizes and the row positions.
Usage (from site/): python3 tools/explorer_data.py ../MaintainerNotes/website-hero/out/final/hud-explorer.json"""
from pathlib import Path
import json, re, sys

d = json.loads(Path(sys.argv[1]).read_text())
widest = max(v['closed']['size'][0] for v in d.values())
page = {}
for preset, states in d.items():
    page[preset] = {'width': round(states['closed']['size'][0] / widest, 4)}
    for state in ('closed', 'open'):
        rows = dict(states[state]['rows']); glass = rows.pop('_glass')
        w, h = states[state]['size']
        page[preset][state] = {'ratio': round(w / h, 5), 'glass': glass, 'rows': rows}
p = Path(__file__).resolve().parent.parent / 'pages/index.html'
s = p.read_text()
m = re.search(r'(<script type="application/json" class="explorer-data">)(.*?)(</script>)', s, re.S)
s = s[:m.start(2)] + json.dumps(page, separators=(',', ':')) + s[m.end(2):]
for preset, states in d.items():
    for state in ('closed', 'open'):
        w, h = states[state]['size']
        s, n = re.subn(rf'(data-preset="{preset}" data-state="{state}" src="[^"]*" )width="\d+" height="\d+"', rf'\1width="{w}" height="{h}"', s)
        assert n == 1, (preset, state)
p.write_text(s)
print('explorer data updated')
