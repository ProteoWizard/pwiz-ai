"""Regenerate the Osprey.Test subset data zips (pwiz_tools/Osprey/Osprey.Test/TestData).

Cuts one isolation window x a few minutes out of regression runs and the matching precursors
out of their library. Needs the regression data (<Downloads>\\Perftests\\osprey-testfiles-mzML-v2)
and the output.blib of a straight-through regression run of the same dataset
(regression.ps1 -Dataset Stellar|Astral leaves one in TestResults\\regression-<stamp>\\<Dataset>\\straight),
which says which precursors are detected.

Usage:
  python build_subset.py stellar --data-root D:/.../osprey-testfiles-mzML-v2 --full-blib .../output.blib
                         --out-zip C:/.../Osprey.Test/TestData/StellarSubset.zip
  python build_subset.py astral  --data-root ... --full-blib ... --out-zip .../AstralSubset.zip
The presets are the parameters of the committed zips; see README.md for why each was chosen.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))

PRESETS = {
    # Unit resolution: m/z rounding of 8 mantissa bits (~0.015 Th at 600) is far inside 0.5 Th.
    'stellar': dict(
        folder='stellar', library='hela-filtered-SkylineAI_spectral_library.tsv',
        subset_library='stellar-subset-library.tsv', readme='StellarSubset-README.txt',
        runs=['Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20', 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
              'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22'],
        target=594.5201, half_width=2.0, rt_min=7.0, rt_max=13.0, rt_pad=0.5, ms1_lo=590.5, ms1_hi=600.5,
        undetected_max=180, mz_drop_bits=8, inten_drop_bits=12,
        libdecoy='stellar-libdecoy/stellar-libdecoy-v3', libdecoy_prefix='stellar-subset-libdecoy'),
    # HRAM: m/z keeps all but 3 mantissa bits (~0.5 ppm). Two runs, not three, to stay under
    # 5 MB zipped - three-run reconciliation is the Stellar subset's job.
    'astral': dict(
        folder='astral', library='SkylineAI_spectral_library.tsv',
        subset_library='astral-subset-library.tsv', readme='AstralSubset-README.txt',
        runs=['Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49', 'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55'],
        target=479.9681, half_width=1.5, rt_min=7.0, rt_max=9.0, rt_pad=0.5, ms1_lo=476.5, ms1_hi=484.5,
        undetected_max=200, mz_drop_bits=3, inten_drop_bits=16,
        libdecoy=None, libdecoy_prefix=None),
}


def run(args):
    print(' '.join(args))
    subprocess.check_call([sys.executable] + args)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dataset', choices=sorted(PRESETS))
    ap.add_argument('--data-root', required=True, help='the extracted osprey-testfiles-mzML-v2 folder')
    ap.add_argument('--full-blib', required=True)
    ap.add_argument('--out-zip', required=True)
    ap.add_argument('--keep-dir', default=None, help='leave the unzipped files here')
    a = ap.parse_args()
    p = PRESETS[a.dataset]

    data_dir = os.path.join(a.data_root, p['folder'])
    mz_lo, mz_hi = p['target'] - p['half_width'], p['target'] + p['half_width']
    work = a.keep_dir or tempfile.mkdtemp(prefix='osprey-subset-')
    os.makedirs(work, exist_ok=True)
    try:
        subset_library = os.path.join(work, p['subset_library'])
        run([os.path.join(HERE, 'subset_library.py'), a.full_blib, os.path.join(data_dir, p['library']),
             subset_library, '--mz-lo', '%.2f' % mz_lo, '--mz-hi', '%.2f' % mz_hi,
             '--rt-min', str(p['rt_min']), '--rt-max', str(p['rt_max']),
             '--undetected-max', str(p['undetected_max']), '--synthetic-proteins', '4',
             '--manifest', os.path.join(work, 'manifest.tsv')])
        for r in p['runs']:
            run([os.path.join(HERE, 'subset_mzml.py'), os.path.join(data_dir, r + '.mzML'),
                 os.path.join(work, r + '.mzML'), '--target', str(p['target']),
                 '--rt-min', str(p['rt_min'] - p['rt_pad']), '--rt-max', str(p['rt_max'] + p['rt_pad']),
                 '--ms1-lo', str(p['ms1_lo']), '--ms1-hi', str(p['ms1_hi']),
                 '--float32', '--mz-drop-bits', str(p['mz_drop_bits']),
                 '--inten-drop-bits', str(p['inten_drop_bits'])])
        if p['libdecoy']:
            libdecoy_dir = os.path.join(a.data_root, p['libdecoy'])
            run([os.path.join(HERE, 'subset_libdecoy.py'), subset_library,
                 os.path.join(libdecoy_dir, 'carafe_spectral_library.tsv'),
                 os.path.join(libdecoy_dir, 'osprey_library_db_pairing.tsv'),
                 os.path.join(work, p['libdecoy_prefix'] + '.tsv'),
                 os.path.join(work, p['libdecoy_prefix'] + '-pairing.tsv'),
                 '--mz-lo', '%.2f' % mz_lo, '--mz-hi', '%.2f' % mz_hi])
        # LF whatever the checkout's line endings, so the zip does not depend on git's autocrlf.
        with open(os.path.join(HERE, p['readme'])) as src:
            readme = src.read()
        with open(os.path.join(work, 'README.txt'), 'w', newline='\n') as dst:
            dst.write(readme)

        # Fixed timestamps and sorted names, so the same inputs give a byte-identical zip.
        with zipfile.ZipFile(a.out_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in sorted(os.listdir(work)):
                if f.endswith(('.mzML', '.tsv', '.txt')):
                    zi = zipfile.ZipInfo(f, date_time=(2026, 9, 27, 0, 0, 0))
                    zi.compress_type = zipfile.ZIP_DEFLATED
                    with open(os.path.join(work, f), 'rb') as fh:
                        z.writestr(zi, fh.read(), compresslevel=9)
        print('wrote %s (%d bytes)' % (a.out_zip, os.path.getsize(a.out_zip)))
    finally:
        if not a.keep_dir:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
