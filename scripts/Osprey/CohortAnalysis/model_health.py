#!/usr/bin/env python3
"""Is the first-pass model itself worse at F=60? Per-file run-level passing drops 13.6% for
EVERY file when files 41-60 join, then recovers when 61-82 join - non-monotone, so check the
trained-model summary (degenerate flag, feature count, pool composition) across cohort sizes.
"""
import os

import mbn_surface as M

ARMS = [
    ('max20', 'seaad-20files-libdecoy-r1.0-percolator-f20n0'),
    ('max30', 'seaad-30files-libdecoy-r1.0-percolator-f30n0'),
    ('max40', 'seaad-40files-libdecoy-r1.0-percolator-f40n0'),
    ('max60', 'seaad-60files-libdecoy-r1.0-percolator-f60n0'),
    ('max82', 'pass2ab-82file-percolator-5day'),
]

print(f'{"arm":7} {"degen":6} {"nFeat":>5} {"nTarget":>9} {"nDecoy":>8} {"nPTarget":>9} '
      f'{"nPDecoy":>8}  composite')
for name, d in ARMS:
    j = M.load(os.path.join(M.RUNS, d))
    if not j:
        print(f'{name:7} (missing)')
        continue
    print(f'{name:7} {str(j.get("modelDegenerate")):6} {j.get("featureCount", 0):>5} '
          f'{j.get("nTarget", 0):>9,} {j.get("nDecoy", 0):>8,} {j.get("npTarget", 0):>9,} '
          f'{j.get("npDecoy", 0):>8,}  {str(j.get("modelComposite"))[:44]}')

# Top model weights per cohort: a composition-driven model shift should show up as the
# feature ranking changing, not just as fewer IDs.
print('\ntop-6 features by |weight| (name: weight)')
for name, d in ARMS:
    j = M.load(os.path.join(M.RUNS, d))
    if not j or not j.get('model'):
        continue
    rows = j['model']
    key = 'weight' if 'weight' in rows[0] else next((k for k in rows[0] if 'eight' in k), None)
    nm = 'name' if 'name' in rows[0] else next(iter(rows[0]))
    top = sorted(rows, key=lambda r: -abs(r.get(key) or 0))[:6]
    print(f'  {name:7} ' + '  '.join(f'{r[nm][:16]}:{r[key]:+.2f}' for r in top))
