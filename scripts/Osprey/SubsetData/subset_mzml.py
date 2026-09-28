"""Cut a small rectangle of DIA data out of an mzML.

Keeps:
  * MS2 spectra whose isolation-window target is within 0.01 of --target, with RT in [rt-min, rt-max]
  * MS1 spectra with RT in [rt-min, rt-max], peaks trimmed to [ms1-lo, ms1-hi]

Writes a plain (non-indexed) mzML with spectrum indices renumbered and the
chromatogram list dropped. MS1 summary cvParams (TIC, base peak, observed m/z range)
are recomputed so the header agrees with the trimmed arrays.

Usage:
  python subset_mzml.py IN OUT --target 602.52 --rt-min 10 --rt-max 13 --ms1-lo 598 --ms1-hi 610
"""
import argparse
import base64
import re
import zlib

import numpy as np

RE_LEVEL = re.compile(r'name="ms level" value="(\d)"')
RE_RT = re.compile(r'name="scan start time" value="([^"]+)"')
RE_TGT = re.compile(r'name="isolation window target m/z" value="([^"]+)"')
RE_BDA = re.compile(r'(<binaryDataArray encodedLength=")(\d+)(">)(.*?)(<binary>)(.*?)(</binary>)', re.S)


def iter_spectra(f):
    buf = []
    inside = False
    for line in f:
        if not inside:
            if '<spectrum ' in line:
                inside = True
                buf = [line]
            continue
        buf.append(line)
        if '</spectrum>' in line:
            inside = False
            yield ''.join(buf)


def decode(params, text):
    raw = base64.b64decode(text)
    if 'MS:1000574' in params:
        raw = zlib.decompress(raw)
    dtype = np.float64 if 'MS:1000523' in params else np.float32
    return np.frombuffer(raw, dtype=dtype)


def encode(params, arr):
    dtype = np.float64 if 'MS:1000523' in params else np.float32
    raw = np.asarray(arr, dtype=dtype).tobytes()
    if 'MS:1000574' in params:
        raw = zlib.compress(raw)
    return base64.b64encode(raw).decode('ascii')


F64_CV = '<cvParam cvRef="MS" accession="MS:1000523" name="64-bit float" value=""/>'
F32_CV = '<cvParam cvRef="MS" accession="MS:1000521" name="32-bit float" value=""/>'


def round_mantissa(arr, drop_bits):
    """Round float32 values to nearest, clearing the low drop_bits of the mantissa."""
    if drop_bits <= 0:
        return arr.astype(np.float32)
    u = arr.astype(np.float32).view(np.uint32).astype(np.uint64)
    half = np.uint64(1 << (drop_bits - 1))
    mask = np.uint64((0xFFFFFFFF >> drop_bits) << drop_bits)
    return ((u + half) & mask).astype(np.uint32).view(np.float32)


def to_float32(s, mz_drop=0, inten_drop=0):
    """Re-encode every 64-bit binary array in a spectrum as 32-bit float, optionally rounded."""
    def repl(m):
        params = m.group(4)
        if 'MS:1000523' not in params:
            return m.group(0)
        arr = decode(params, m.group(6))
        arr = round_mantissa(arr, mz_drop if 'MS:1000514' in params else inten_drop)
        new_params = params.replace(F64_CV, F32_CV)
        t = encode(new_params, arr)
        return m.group(1) + str(len(t)) + m.group(3) + new_params + m.group(5) + t + m.group(7)
    return RE_BDA.sub(repl, s)


def set_cv(s, name, value):
    pat = re.compile(r'(name="%s" value=")[^"]*(")' % re.escape(name))
    return pat.sub(lambda m: m.group(1) + value + m.group(2), s, count=1)


def trim_ms1(s, lo, hi):
    arrays = list(RE_BDA.finditer(s))
    mz_i = next(i for i, m in enumerate(arrays) if 'MS:1000514' in m.group(4))
    in_i = next(i for i, m in enumerate(arrays) if 'MS:1000515' in m.group(4))
    mz = decode(arrays[mz_i].group(4), arrays[mz_i].group(6))
    inten = decode(arrays[in_i].group(4), arrays[in_i].group(6))
    keep = (mz >= lo) & (mz <= hi)
    mz, inten = mz[keep], inten[keep]
    new_text = {mz_i: encode(arrays[mz_i].group(4), mz), in_i: encode(arrays[in_i].group(4), inten)}

    def repl(m, idx=[0]):
        i = idx[0]
        idx[0] += 1
        t = new_text[i]
        return m.group(1) + str(len(t)) + m.group(3) + m.group(4) + m.group(5) + t + m.group(7)

    s = RE_BDA.sub(repl, s)
    n = len(mz)
    s = re.sub(r'defaultArrayLength="\d+"', 'defaultArrayLength="%d"' % n, s, count=1)
    if n:
        bp = int(np.argmax(inten))
        s = set_cv(s, 'base peak m/z', repr(float(mz[bp])))
        s = set_cv(s, 'base peak intensity', repr(float(inten[bp])))
        s = set_cv(s, 'total ion current', repr(float(inten.sum())))
        s = set_cv(s, 'lowest observed m/z', repr(float(mz[0])))
        s = set_cv(s, 'highest observed m/z', repr(float(mz[-1])))
    else:
        s = set_cv(s, 'base peak intensity', '0')
        s = set_cv(s, 'total ion current', '0')
    return s, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inp')
    ap.add_argument('out')
    ap.add_argument('--target', type=float, required=True)
    ap.add_argument('--rt-min', type=float, required=True)
    ap.add_argument('--rt-max', type=float, required=True)
    ap.add_argument('--ms1-lo', type=float, required=True)
    ap.add_argument('--ms1-hi', type=float, required=True)
    ap.add_argument('--float32', action='store_true', help='re-encode binary arrays as 32-bit float')
    ap.add_argument('--mz-drop-bits', type=int, default=0, help='with --float32: mantissa bits rounded off m/z')
    ap.add_argument('--inten-drop-bits', type=int, default=0,
                    help='with --float32: mantissa bits rounded off intensity')
    a = ap.parse_args()

    header = []
    kept = []
    n_ms1 = n_ms2 = ms1_peaks = 0
    with open(a.inp, 'r', encoding='utf-8') as f:
        for line in f:
            if '<spectrumList ' in line:
                header.append(line)
                break
            header.append(line)
        for s in iter_spectra(f):
            rt = float(RE_RT.search(s).group(1))
            if rt < a.rt_min:
                continue
            if rt > a.rt_max:
                break
            level = RE_LEVEL.search(s).group(1)
            if level == '1':
                s, n = trim_ms1(s, a.ms1_lo, a.ms1_hi)
                ms1_peaks += n
                n_ms1 += 1
            else:
                t = RE_TGT.search(s)
                if not t or abs(float(t.group(1)) - a.target) > 0.01:
                    continue
                n_ms2 += 1
            if a.float32:
                s = to_float32(s, a.mz_drop_bits, a.inten_drop_bits)
            kept.append(s)

    head = ''.join(header)
    # Drop the indexedmzML wrapper: the index offsets would be wrong after the cut.
    head = re.sub(r'<indexedmzML[^>]*>\s*', '', head, count=1)
    head = re.sub(r'<spectrumList count="\d+"', '<spectrumList count="%d"' % len(kept), head, count=1)
    with open(a.out, 'w', encoding='utf-8', newline='\n') as w:
        w.write(head)
        for i, s in enumerate(kept):
            w.write(re.sub(r'<spectrum index="\d+"', '<spectrum index="%d"' % i, s, count=1))
        w.write('      </spectrumList>\n    </run>\n</mzML>\n')
    print('kept %d spectra (%d MS1, %d MS2), MS1 peaks %d' % (len(kept), n_ms1, n_ms2, ms1_peaks))


if __name__ == '__main__':
    main()
