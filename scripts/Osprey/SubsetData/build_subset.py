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
        subset_library='stellar-subset-library.tsv', subset_fasta='stellar-subset-proteins.fasta', readme='StellarSubset-README.txt',
        runs=['Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20', 'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21',
              'Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22'],
        target=594.5201, half_width=2.0, window_step=4.0018, windows=2, fasta='hela-filtered.fasta', rt_min=6.0, rt_max=18.0, rt_pad=0.5, ms1_lo=590.5, ms1_hi=600.5,
        undetected_max=720, mz_drop_bits=8, inten_drop_bits=12,
        libdecoy='stellar-libdecoy/stellar-libdecoy-v3', libdecoy_prefix='stellar-subset-libdecoy'),
    # HRAM: m/z keeps all but 3 mantissa bits (~0.5 ppm). Two runs, not three, to stay under
    # 5 MB zipped - three-run reconciliation is the Stellar subset's job.
    'astral': dict(
        folder='astral', library='SkylineAI_spectral_library.tsv',
        subset_library='astral-subset-library.tsv', subset_fasta='astral-subset-proteins.fasta', readme='AstralSubset-README.txt',
        runs=['Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49', 'Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55'],
        target=479.9681, half_width=1.5, window_step=None, windows=1, fasta='uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta', rt_min=7.0, rt_max=9.0, rt_pad=0.5, ms1_lo=476.5, ms1_hi=484.5,
        undetected_max=200, mz_drop_bits=3, inten_drop_bits=16,
        libdecoy=None, libdecoy_prefix=None),
}


def write_zip(path, work, extensions):
    # Fixed timestamps and sorted names, so the same inputs give a byte-identical zip.
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(os.listdir(work)):
            if f.endswith(extensions):
                zi = zipfile.ZipInfo(f, date_time=(2026, 9, 27, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                with open(os.path.join(work, f), 'rb') as fh:
                    z.writestr(zi, fh.read(), compresslevel=9)
    print('wrote %s (%d bytes)' % (path, os.path.getsize(path)))


def write_perf_zip(path, work, folder):
    # The regression data's layout, <zip stem>/<dataset folder>/..., which OspreySearchPerfTest extracts
    # in place beside the zip; same fixed timestamps as the committed zips.
    stem = os.path.splitext(os.path.basename(path))[0]
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for f in sorted(os.listdir(work)):
            if f.endswith(('.mzML', '.fasta')):
                zi = zipfile.ZipInfo('%s/%s/%s' % (stem, folder, f), date_time=(2026, 9, 27, 0, 0, 0))
                zi.compress_type = zipfile.ZIP_DEFLATED
                with open(os.path.join(work, f), 'rb') as fh:
                    z.writestr(zi, fh.read(), compresslevel=6)
    print('wrote %s (%d bytes)' % (path, os.path.getsize(path)))


def run(args):
    print(' '.join(args))
    subprocess.check_call([sys.executable] + args)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dataset', choices=sorted(PRESETS))
    ap.add_argument('--data-root', required=True, help='the extracted osprey-testfiles-mzML-v2 folder')
    ap.add_argument('--full-blib', required=True)
    ap.add_argument('--out-zip', default=None, help='omit with --keep-dir to leave only the files')
    ap.add_argument('--keep-dir', default=None, help='leave the unzipped files here')
    # Candidate overrides (Measure-Subset.ps1). Without them the preset is cut exactly as committed.
    ap.add_argument('--windows', type=int, default=None,
                    help='contiguous isolation windows centred on the preset target (extra one goes above)')
    ap.add_argument('--rt-min', type=float, default=None, help='override the preset RT slice start (min)')
    ap.add_argument('--rt-max', type=float, default=None, help='override the preset RT slice end (min)')
    ap.add_argument('--undetected-max', type=int, default=None, help='override the preset cap; -1 keeps all')
    ap.add_argument('--real-proteins', action='store_true',
                    help='keep the real accessions and write their records from the dataset FASTA')
    ap.add_argument('--fasta', action='store_true',
                    help='also write the subset FASTA: real proteins, or concatenated synthetic ones')
    ap.add_argument('--no-libdecoy', action='store_true', help='skip the library-decoy variant')
    ap.add_argument('--functional-zip', default=None,
                    help='also write the Skyline functional-test zip (mzMLs + FASTA; implies --fasta), '
                         'as Skyline TestFunctional/OspreySearchTest.zip')
    ap.add_argument('--perf-zip', default=None,
                    help='also write the Skyline perf-test zip (<stem>/<dataset folder>/ mzMLs + FASTA; implies --fasta)')
    a = ap.parse_args()
    p = dict(PRESETS[a.dataset])
    if a.rt_min is not None:
        p['rt_min'] = a.rt_min
    if a.rt_max is not None:
        p['rt_max'] = a.rt_max
    if a.undetected_max is not None:
        p['undetected_max'] = a.undetected_max
    if a.no_libdecoy:
        p['libdecoy'] = None
    if a.windows is not None:
        p['windows'] = a.windows
    if a.functional_zip or a.perf_zip:
        a.fasta = True
    if a.out_zip is None and a.functional_zip is None and a.perf_zip is None and not a.keep_dir:
        ap.error('--keep-dir is required without --out-zip, --functional-zip or --perf-zip')

    data_dir = os.path.join(a.data_root, p['folder'])
    below = (p['windows'] - 1) // 2
    above = p['windows'] - 1 - below
    t_lo, t_hi = p['target'] - below * p['window_step'], p['target'] + above * p['window_step']
    mz_lo, mz_hi = t_lo - p['half_width'], t_hi + p['half_width']
    ms1_lo, ms1_hi = p['ms1_lo'] - (p['target'] - t_lo), p['ms1_hi'] + (t_hi - p['target'])
    target_args = ['--target', str(p['target'])] if p['windows'] == 1 else \
        ['--target-lo', '%.4f' % t_lo, '--target-hi', '%.4f' % t_hi]
    work = a.keep_dir or tempfile.mkdtemp(prefix='osprey-subset-')
    os.makedirs(work, exist_ok=True)
    try:
        subset_library = os.path.join(work, p['subset_library'])
        run([os.path.join(HERE, 'subset_library.py'), a.full_blib, os.path.join(data_dir, p['library']),
             subset_library, '--mz-lo', '%.2f' % mz_lo, '--mz-hi', '%.2f' % mz_hi,
             '--rt-min', str(p['rt_min']), '--rt-max', str(p['rt_max']),
             '--undetected-max', str(p['undetected_max']),
             '--synthetic-proteins', '0' if a.real_proteins else '4',
             '--manifest', os.path.join(work, 'manifest.tsv')])
        if a.fasta:
            fasta_args = [os.path.join(data_dir, p['fasta']), os.path.join(work, p['subset_fasta']),
                          subset_library]
            if not a.real_proteins:
                fasta_args = ['-'] + fasta_args[1:] + ['--concatenated']
            run([os.path.join(HERE, 'subset_fasta.py')] + fasta_args)
        for r in p['runs']:
            run([os.path.join(HERE, 'subset_mzml.py'), os.path.join(data_dir, r + '.mzML'),
                 os.path.join(work, r + '.mzML')] + target_args +
                ['--rt-min', str(p['rt_min'] - p['rt_pad']), '--rt-max', str(p['rt_max'] + p['rt_pad']),
                 '--ms1-lo', str(ms1_lo), '--ms1-hi', str(ms1_hi),
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

        # The full fixture (Osprey.Test\TestData) and the wizard's (TestFunctional\OspreySearchTest.zip:
        # the runs and the proteins only - the wizard predicts its own library from the FASTA).
        if a.out_zip:
            write_zip(a.out_zip, work, ('.mzML', '.tsv', '.txt', '.fasta') if a.fasta else ('.mzML', '.tsv', '.txt'))
        if a.functional_zip:
            write_zip(a.functional_zip, work, ('.mzML', '.fasta'))
        if a.perf_zip:
            write_perf_zip(a.perf_zip, work, p['folder'])
    finally:
        if not a.keep_dir:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == '__main__':
    main()
