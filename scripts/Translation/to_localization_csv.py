"""Convert the reconciled Osprey draft tables into ResourcesOrganizer's localization CSVs, so the
drafts enter the RESX files through ImportLocalizationCsvFiles exactly like a translation company's.

to_localization_csv.py <osprey.ja.tsv> <osprey.zh.tsv> <scratch dir>
Writes <scratch>/localization.ja.csv and <scratch>/localization.zh-Hans.csv with columns
Name, Comment, English, Translation, Issue, OldEnglish, OldLocalized, FileCount, File.

Issue is "New resource" on every row: the import then keeps a "Needs Review:" comment on each
entry, the state of any unreviewed Skyline string, and GenerateLocalizationCsvFiles later hands the
expert reviewers these rows with the drafts filled in. File is left empty: rows match on
Name + English, and Osprey keys are Class_Member_Text names unique to Osprey.
"""
import csv
import os
import sys


def unesc(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            out.append({'n': '\n', 't': '\t', '\\': '\\'}.get(s[i + 1], '\\' + s[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def convert(src, dst):
    rows = [l.rstrip('\n').split('\t') for l in open(src, encoding='utf-8')][1:]
    with open(dst, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerow(['Name', 'Comment', 'English', 'Translation', 'Issue', 'OldEnglish', 'OldLocalized', 'FileCount', 'File'])
        for r in rows:
            english, translation = unesc(r[2]), unesc(r[3])
            # A value deliberately identical to the English (product names, units) has nothing to
            # review, and ExportResx drops a "New resource" entry whose value equals the English -
            # so it would vanish from the localized file. Import it as accepted instead.
            issue = '' if translation == english else 'New resource'
            w.writerow([r[1], '', english, translation, issue, '', '', '1', ''])
    print(dst, len(rows), 'rows')


def main():
    ja, zh, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    convert(ja, os.path.join(out, 'localization.ja.csv'))
    convert(zh, os.path.join(out, 'localization.zh-Hans.csv'))


if __name__ == '__main__':
    main()
