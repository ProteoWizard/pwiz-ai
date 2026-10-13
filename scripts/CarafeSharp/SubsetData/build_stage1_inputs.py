"""Regenerate pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/Stage1Inputs.zip.

The committed inputs of EntrapmentFastaParityTest.TestSubsetFastaBuildsMatchCarafe, which reruns
the stage-1 entrapment FASTA builds of carafesharp-testfiles-v1 on every commit. Their outputs
(23-62 MB each, about 1 GB in all) are not kept: each folder that has outputs gets an
expected.sha256 instead, with the SHA-256 the package's MANIFEST.sha256 records for them, and the
test compares whole-output hashes.

The zip is one folder, carafesharp-testfiles-v1/, laid out as the package is, holding:
  * the --inputs files, unchanged (by default stellar/hela-filtered.fasta and
    stage1/fixtures/mouse-subset1500.fasta, about 1.9 MB compressed);
  * every *.carafe.sig of the two Stellar GUI runs (stellar/carafe-osprey-entrapment and
    stellar/carafe-osprey), whose -db must be one of the inputs, and an expected.sha256 per run
    for the peptide FASTAs and pairing manifests they record;
  * every stage1/builds subfolder whose command.txt reads only those inputs ({DATA}/ paths): its
    command.txt and an expected.sha256 for peptides.fasta and pairing.tsv. A build that reads
    anything else is left out and stays download-only; by default foreign-mouse and
    foreign-mouse-r025, which need the 14.4 MB stage1/uniprot_mouse_dec2024_yeastENO1.fasta (8 MB
    compressed). The mouse-subset1500 builds cover the same foreign-database path;
  * README.txt, describing the subset, and MANIFEST.sha256 (CRLF, '<sha256>  <path>', as the
    package writes it) of every other file, as the zip's last entry.
Every copied file is checked against the package's MANIFEST.sha256 first.

Usage:
  python build_stage1_inputs.py --data-root D:/Users/<you>/Downloads/Perftests
      --out-zip C:/.../pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/Stage1Inputs.zip
The defaults are the parameters of the committed zip. The output is byte-identical for the same
inputs: fixed timestamps and attributes, entries in sorted order, MANIFEST.sha256 last.
"""
import argparse
import hashlib
import json
import os
import sys
import zipfile

PACKAGE = 'carafesharp-testfiles-v1'
MANIFEST = 'MANIFEST.sha256'
EXPECTED = 'expected.sha256'
DATA_TOKEN = '{DATA}/'
REFERENCE_RUNS = ['stellar/carafe-osprey-entrapment', 'stellar/carafe-osprey']
BUILDS = 'stage1/builds'
BUILD_OUTPUTS = ['peptides.fasta', 'pairing.tsv']
SIGNATURE_SUFFIX = '.carafe.sig'
DEFAULT_INPUTS = ['stellar/hela-filtered.fasta', 'stage1/fixtures/mouse-subset1500.fasta']
ZIP_TIME = (1980, 1, 1, 0, 0, 0)


def read_manifest(package_root):
    hashes = {}
    with open(os.path.join(package_root, MANIFEST), encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if line:
                sha, path = line.split('  ', 1)
                hashes[path] = sha
    return hashes


def read_checked(package_root, hashes, relative):
    """The bytes of a package file, which must match the package's MANIFEST.sha256."""
    with open(os.path.join(package_root, *relative.split('/')), 'rb') as f:
        data = f.read()
    if hashes.get(relative) != hashlib.sha256(data).hexdigest():
        sys.exit('%s does not match its %s entry' % (relative, MANIFEST))
    return data


def expected_file(hashes, folder, names):
    """An expected.sha256 for the outputs in folder, from the package manifest."""
    lines = []
    for name in sorted(names):
        sha = hashes.get(folder + '/' + name)
        if sha is None:
            sys.exit('%s lists no %s/%s' % (MANIFEST, folder, name))
        lines.append('%s  %s\r\n' % (sha, name))
    return ''.join(lines).encode('ascii')


def signature_command(data):
    return json.loads(data.decode('utf-8'))['command'].split()


def option_value(args, option):
    return args[args.index(option) + 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data-root', required=True, help='the folder holding the extracted carafesharp-* packages')
    ap.add_argument('--out-zip', required=True)
    ap.add_argument('--inputs', nargs='+', default=DEFAULT_INPUTS,
                    help='package-relative input files to keep; builds reading any other file are left out')
    a = ap.parse_args()

    package_root = os.path.join(a.data_root, PACKAGE)
    hashes = read_manifest(package_root)
    inputs = set(a.inputs)
    input_names = {i.rsplit('/', 1)[-1] for i in inputs}
    files = {}  # package-relative path -> bytes
    for relative in sorted(inputs):
        files[relative] = read_checked(package_root, hashes, relative)

    signatures = []
    for run in REFERENCE_RUNS:
        run_dir = os.path.join(package_root, *run.split('/'))
        outputs = []
        for name in sorted(os.listdir(run_dir)):
            if not name.endswith(SIGNATURE_SUFFIX):
                continue
            relative = run + '/' + name
            data = read_checked(package_root, hashes, relative)
            args = signature_command(data)
            db = option_value(args, '-db').replace('\\', '/').rsplit('/', 1)[-1]
            if db not in input_names:
                sys.exit('%s builds from %s, which is not an input' % (relative, db))
            files[relative] = data
            for option in ('-build_entrapment_fasta', '-manifest'):
                outputs.append(option_value(args, option).replace('\\', '/').rsplit('/', 1)[-1])
            signatures.append(relative)
        if not outputs:
            sys.exit('No *%s in %s' % (SIGNATURE_SUFFIX, run))
        files[run + '/' + EXPECTED] = expected_file(hashes, run, outputs)

    kept, left_out = [], []
    builds_dir = os.path.join(package_root, *BUILDS.split('/'))
    for name in sorted(os.listdir(builds_dir)):
        build = BUILDS + '/' + name
        command_path = build + '/command.txt'
        if command_path not in hashes:
            continue
        command = read_checked(package_root, hashes, command_path)
        data_paths = [line.strip()[len(DATA_TOKEN):] for line in command.decode('utf-8').splitlines()
                      if line.strip().startswith(DATA_TOKEN)]
        missing = [p for p in data_paths if p not in inputs]
        if missing:
            left_out.append((name, missing))
            continue
        files[command_path] = command
        files[build + '/' + EXPECTED] = expected_file(hashes, build, BUILD_OUTPUTS)
        kept.append(name)

    readme = (
        'CarafeSharp stage-1 inputs subset of %s (built by ai/scripts/CarafeSharp/SubsetData/build_stage1_inputs.py)\r\n\r\n'
        'The inputs of the stage-1 entrapment FASTA builds, without their outputs: each folder that had\r\n'
        'outputs has an %s with the SHA-256 the full package records for them.\r\n\r\n'
        'Inputs, unchanged: %s\r\n'
        'Carafe GUI signatures: %s\r\n'
        'Builds kept (%d): %s\r\n'
        'Builds left out, download-only (%d): %s\r\n'
        % (PACKAGE, EXPECTED, ', '.join(sorted(inputs)), ', '.join(signatures), len(kept), ', '.join(kept),
           len(left_out), ', '.join('%s (reads %s)' % (n, ', '.join(m)) for n, m in left_out)))
    files['README.txt'] = readme.encode('ascii')

    manifest = ''.join('%s  %s\r\n' % (hashlib.sha256(files[p]).hexdigest(), p) for p in sorted(files))
    entries = [(PACKAGE + '/' + p, files[p]) for p in sorted(files)]
    entries.append((PACKAGE + '/' + MANIFEST, manifest.encode('ascii')))
    with zipfile.ZipFile(a.out_zip, 'w') as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data, compresslevel=9)
    print('%s: %d bytes, %d files; %d signatures; %d builds kept (%s); left out: %s'
          % (a.out_zip, os.path.getsize(a.out_zip), len(entries), len(signatures), len(kept), ', '.join(kept),
             ', '.join(n for n, _ in left_out) or 'none'))


if __name__ == '__main__':
    main()
