"""Build the English -> ja / zh-Hans parallel corpus from every localized .resx pair in a pwiz
checkout (Osprey excluded), as the reviewed-final evidence for the glossary and translation memory.

corpus.py <pwiz root> <out.tsv>

Columns: file, key, en, ja, zh   (\\n and \\t escaped). A localized value equal to the English is
kept but marked by an empty cell, since Skyline's untranslated strings carry the English.
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

LANGS = [('ja', '.ja.resx'), ('zh', '.zh-Hans.resx')]
LOCALIZED = re.compile(r'\.[a-z]{2}(-[A-Za-z]+)?\.resx$')
SKIP_DIRS = (os.sep + 'Osprey' + os.sep, os.sep + 'bin' + os.sep, os.sep + 'obj' + os.sep)
# form .resx carry layout and type metadata as data too; keep only text-bearing members
TEXT_MEMBER = re.compile(r'\.(Text|ToolTip|HeaderText|Caption|Title|Description|ToolTipText)$')


def read(path):
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, OSError):
        return {}
    out = {}
    for d in root.iter('data'):
        if d.get('type') or d.get('mimetype'):
            continue
        name = d.get('name')
        if not name or name.startswith('>>') or name.startswith('$this.') and not name.endswith('.Text'):
            continue
        if '.' in name and not TEXT_MEMBER.search(name):
            continue
        v = d.find('value')
        if v is None or v.text is None:
            continue
        out[name] = v.text
    return out


def esc(s):
    return (s or '').replace('\\', '\\\\').replace('\t', '\\t').replace('\r\n', '\\n').replace('\n', '\\n')


def main():
    root, out_path = sys.argv[1], sys.argv[2]
    files = [p for p in glob.glob(os.path.join(root, 'pwiz_tools', '**', '*.resx'), recursive=True)
             if not LOCALIZED.search(p) and not any(s in p for s in SKIP_DIRS)]
    rows = 0
    per_lang = {'ja': 0, 'zh': 0}
    with open(out_path, 'w', encoding='utf-8', newline='') as f:
        f.write('file\tkey\ten\tja\tzh\n')
        for eng_path in sorted(files):
            locs = {}
            for lang, suffix in LANGS:
                p = eng_path[:-5] + suffix
                if os.path.exists(p):
                    locs[lang] = read(p)
            if not locs:
                continue
            english = read(eng_path)
            rel = os.path.relpath(eng_path, root).replace('\\', '/')
            for key, en in english.items():
                if not en.strip():
                    continue
                vals = {}
                for lang in ('ja', 'zh'):
                    v = locs.get(lang, {}).get(key)
                    vals[lang] = v if v and v != en else ''
                    if vals[lang]:
                        per_lang[lang] += 1
                if not vals['ja'] and not vals['zh']:
                    continue
                f.write('\t'.join([rel, key, esc(en), esc(vals['ja']), esc(vals['zh'])]) + '\n')
                rows += 1
    print(rows, 'rows;', per_lang)


if __name__ == '__main__':
    main()
