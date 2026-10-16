"""Copy the translation-archive files used by the drafting process out of the team's Localization
archive (a shared Google Drive folder; ask Brendan for access) and convert each to UTF-8 text
beside the copy:
xlsx/xls -> one .tsv per sheet, docx -> .txt, csv/tmx -> copied as-is.

extract_archive.py <archive dir> <out dir> [downloads dir]

The two glossaries mapped from DL were received by email and are not in the archive folder;
pass the folder holding them as [downloads dir], or they are reported MISSING.
"""
import csv
import os
import shutil
import sys

ARCH = sys.argv[1] if len(sys.argv) > 1 else ''
DL = sys.argv[3] if len(sys.argv) > 3 else '<downloads dir not given>'
FILES = {
    # glossaries / term bases
    'ja/glossary_72177_2014-01-15.xlsx': DL + r'\72177_Skyline_glossary_1-15-14.xlsx',
    'ja/termbase_2016-04_latest.xlsx': ARCH + r'\Software\Japanese\Term Base\Skyline-Japanese_Term_Base_04_2016_Latestxlsx.xlsx',
    'ja/termbase_2016-04_yasushi.xlsx': ARCH + r'\Software\Japanese\Term Base\Archive\Skyline-Japanese_Term_Base_Yasushi_edits_04_2016.xlsx',
    'ja/termbase_2016-04_edits.xlsx': ARCH + r'\Software\Japanese\Term Base\Archive\Skyline-Japanese_Term_Base_04_2016_edits.xlsx',
    'zh/glossary_summary_2014-05-05.xlsx': DL + r'\Skyline_Chinese_Glossary_Summary_05-05-14.xlsx',
    'zh/glossary_2014-05-23_final_reviewed.xls': ARCH + r'\Software\Chinese\Archive\Skyline_Chinese_Glossary_05-23-2014_Acclaro_final-reviewed.xls',
    'zh/glossary_2014-06-03.xls': ARCH + r'\Software\Chinese\Archive\Skyline_Chinese_Glossary_06-03-2014.xls',
    'zh/glossary_review_YP.xls': ARCH + r'\Software\Chinese\Review_Glossary2\Skyline_Chinese_Glossary_05-12-14_Acclaro_YP.xls',
    'zh/glossary_review_TL.xls': ARCH + r'\Software\Chinese\Review_Glossary2\Skyline_Chinese_Glossary_05-12-14_Acclaro_TL.xls',
    'zh/glossary_review_Chaochao_Tao_YP.xls': ARCH + r'\Software\Chinese\Review_Glossary2\Skyline_Chinese_Glossary_05-12-14_Acclaro_Chaochao_Tao_YP.xls',
    # style guides / review instructions
    'zh/styleguide_acclaro.doc': ARCH + r'\Software\Chinese\Archive\Acclaro_StyleGuide_UW-Skyline_Simplified Chinese-bm.doc',
    'zh/client_review_instructions.pdf': ARCH + r'\Software\Chinese\Skyline_20_1\Client Review Instructions.pdf',
    'ja/ls_client_review_guidelines.pdf': ARCH + r'\Software\Japanese\Archive\LS_Client_review_Guidelines.pdf',
    'tutorial_style_guide.docx': ARCH + r'\Tutorials\Skyline Tutorial Style Guide.docx',
    # translation memories
    'ja/skyline_japanese.tmx': ARCH + r'\Software\Japanese\Archive\Skyline Japanese.tmx',
    'zh/skyline_chinese.tmx': ARCH + r'\Software\Chinese\Archive\Skyline Chinese.tmx',
    # translator draft vs reviewed final (evaluation ground truth)
    'ja/25_1/localization.ja-LS.csv': ARCH + r'\Software\Japanese\Skyline_25_1\localization.ja-LS.csv',
    'ja/25_1/localization.ja.csv': ARCH + r'\Software\Japanese\Skyline_25_1\localization.ja.csv',
    'ja/25_1/tutorial.ja-LS.csv': ARCH + r'\Software\Japanese\Skyline_25_1\tutorial.ja-LS.csv',
    'zh/25_1/localization.zh-CHS-LS.csv': ARCH + r'\Software\Chinese\Skyline_25_1\localization.zh-CHS-LS.csv',
    'zh/25_1/localization.zh-CHS.csv': ARCH + r'\Software\Chinese\Skyline_25_1\localization.zh-CHS.csv',
    'zh/25_1/tutorial.zh-LS.csv': ARCH + r'\Software\Chinese\Skyline_25_1\tutorial.zh-LS.csv',
    'ja/24_1/localization.ja_MI_KS.xlsx': ARCH + r'\Software\Japanese\Skyline_24_1\Reviews\localization.ja_JA-JP_MI_KS.xlsx',
    'zh/24_1/localization.zh-CHS_MGH.csv': ARCH + r'\Software\Chinese\Skyline_24_1\Reviews\localization.zh-CHS_ZH-CN_MGH.csv',
    'zh/23_1/translator_project_TL.xlsx': ARCH + r'\Software\Chinese\Skyline_23_1\Reviews\Skyline-23_1-TranslatorProject_zh_TL.xlsx',
    'ja/20_2/translator_project_MI_KS.xlsx': ARCH + r'\Software\Japanese\Skyline_20_2\Skyline-20_2-TranslatorProject_ja_JP_MI_KSv1023.xlsx',
    'ja/20_2/from_reviewers.xlsx': ARCH + r'\Software\Japanese\Skyline_20_2\Skyline-20_2-fromReviewers.xlsx',
    'zh/20_2/translator_project_reviewed.xlsx': ARCH + r'\Software\Chinese\Skyline_20_2\Skyline-20_2-TranslatorProject_Reviewed.xlsx',
    'zh/20_2/translator_project_LS_accepted.xlsx': ARCH + r'\Software\Chinese\Skyline_20_2\Skyline-20_2-TranslatorProject_LS_accepted.xlsx',
    'ja/3_6/consistency_final.xlsx': ARCH + r'\Software\Japanese\Skyline_3_6\Consistency check\Skyline3 6_new_strings_20161201_Consistency_Final.xlsx',
    'ja/4_2/review_recommendations.xlsx': ARCH + r'\Software\Japanese\Skyline_4_2\Skyline 4 2_Review Recommendations Nov 2018.xlsx',
    'ja/4_2/ls_review_comments.xlsx': ARCH + r'\Software\Japanese\Skyline_4_2\Skyline 4 2_LS Review comments.xlsx',
}


def cell(v):
    if v is None:
        return ''
    return str(v).replace('\t', '\\t').replace('\r\n', '\\n').replace('\n', '\\n')


def dump_rows(out_base, sheet_name, rows):
    path = '%s.%s.tsv' % (out_base, sheet_name.replace(' ', '_').replace('/', '_'))
    n = 0
    with open(path, 'w', encoding='utf-8', newline='') as f:
        for row in rows:
            vals = [cell(v) for v in row]
            while vals and not vals[-1]:
                vals.pop()
            if vals:
                f.write('\t'.join(vals) + '\n')
                n += 1
    return path, n


def convert(path):
    base, ext = os.path.splitext(path)
    ext = ext.lower()
    if ext == '.xlsx':
        import openpyxl
        wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
        return [dump_rows(base, ws.title, ws.iter_rows(values_only=True)) for ws in wb.worksheets]
    if ext == '.xls':
        import xlrd
        wb = xlrd.open_workbook(path)
        return [dump_rows(base, sh.name, (sh.row_values(r) for r in range(sh.nrows))) for sh in wb.sheets()]
    if ext == '.docx':
        import docx
        d = docx.Document(path)
        lines = [p.text for p in d.paragraphs]
        for t in d.tables:
            for r in t.rows:
                lines.append('\t'.join(cell(c.text) for c in r.cells))
        with open(base + '.txt', 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        return [(base + '.txt', len(lines))]
    return []


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out = sys.argv[2]
    for rel, src in FILES.items():
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(src):
            print('MISSING', src)
            continue
        shutil.copy2(src, dst)
        try:
            for p, n in convert(dst):
                print('%6d  %s' % (n, os.path.relpath(p, out)))
        except Exception as e:  # report and keep going; one bad sheet should not stop the rest
            print('FAILED', rel, type(e).__name__, e)


if __name__ == '__main__':
    main()
