# Large Osprey test datasets - candidate catalog

Datasets bigger than the 82-file SEA-AD Pilot set, for scaling and cross-sample validation
work. SEA-AD is the current standard >3-file set (see
`ai/scripts/Osprey/SEA-AD/README.md`); this is the shortlist for what comes after it.

**Every count and size below was MEASURED with a WebDAV PROPFIND**, not estimated from a
portal page. Verified 2026-07-28 from BRENDANX-UW8.

## Quick comparison

All four MEASURED 2026-07-28 (Agents group granted read on the three collaboration
containers that day).

| dataset | runs | raw size | avg/run | fits D:? | why it is interesting |
|---|---|---|---|---|---|
| SEA-AD Pilot (current) | 82 | 484 GB | 5.9 GB | staged | today's standard large set |
| **CHS-SeerData (Floyd)** | **446** | **1,774 GB** | 4.0 GB | tight | **different composition across samples** - directly exercises reconciliation + consensus RT |
| TDP-43 Plasma EV-Quant | **164** | **784 GB** | 4.8 GB | yes | human plasma EVs; exactly 2x SEA-AD in both runs and bytes |
| AHA Plasma Stroke EV | **200** | **1,167 GB** | 5.8 GB | yes | 2 plates x (96 quant + 4 ChromLib); aortic arch replacement |
| TEIREX Experiment 2 | 936 | 8,296 GB | 8.9 GB | **no** | 10 x 96-well mouse plates; one plate fits, the set does not |

## 1. CHS-SeerData (UW-Floyd Lab) - RECOMMENDED NEXT

* Portal: https://panoramaweb.org/MacCoss/Collaborations/UW-Floyd%20Lab/CHS-SeerData/project-begin.view
* WebDAV raw: `https://panoramaweb.org/_webdav/MacCoss/Collaborations/UW-Floyd%20Lab/CHS-SeerData/%40files/RAW%20data%20files/`
* **Access: OK (207).** MEASURED: **446 files, 1,774.4 GB, avg 3.98 GB** - a FLAT directory,
  no per-plate subfolders, so the plate/bead split (plates 59-64) has to come from the file
  names, not the layout. Sibling dirs: `PlateLayouts`, `ProcessedResultsFromSeer`,
  `ResultsTables_DIANN_LibraryFree`, plus 4 x ~9 GB `.sky.zip` at the root.

Seer dataset. ~200 samples, each run twice with a different bead, so **~400 runs**. Plates
annotated 59 through 64; the Skyline convention is one document per plate, and here also
divided by bead. Astral data collected with unusual acquisition parameters, but the samples
themselves are valuable.

**Why this one for Osprey:** samples differ in composition, which is exactly the condition
that stresses **reconciliation and cross-run consensus RT** - the Stage 6 code path. SEA-AD
is 82 runs of comparatively similar material; it cannot fail that way. This is a
correctness question, not just a scale question, which is what makes it the better next
step than "SEA-AD but bigger".

Library note (Mike): for fine-tuning the library he used a file collected around the middle
of the experiment, not the start.

## 2. TDP-43 Plasma EV-Quant (UW-Latimer)

* Portal: https://panoramaweb.org/MacCoss/Collaborations/UW-Latimer/2025-TDP43-CSF-Plasma/TDP-43%20Plasma%20EV-Quant/project-begin.view
* WebDAV raw: `https://panoramaweb.org/_webdav/MacCoss/Collaborations/UW-Latimer/2025-TDP43-CSF-Plasma/TDP-43%20Plasma%20EV-Quant/%40files/RawFiles/`
* **Access: OK (207).** MEASURED: **164 files, 784.2 GB, avg 4.78 GB**, flat directory.

Human plasma extracellular vesicles. Mike's "2x SEA-AD" is exact in both dimensions:
82 -> 164 runs, 484 -> 784 GB. The natural "one step up in scale" option, and the cheapest
of the three to stage.

## 3. AHA Plasma Stroke EV (UW-Levitt Lab)

* Portal: https://panoramaweb.org/MacCoss/Collaborations/UW-Levitt%20Lab/AHA%20Plasma%20Stroke%20EV/Plasma%20Stroke%20EV-Exp1%20Repeat/Plasma%20EV-Exp%201%20Quant/project-begin.view
* WebDAV raw: `https://panoramaweb.org/_webdav/MacCoss/Collaborations/UW-Levitt%20Lab/AHA%20Plasma%20Stroke%20EV/Plasma%20Stroke%20EV-Exp1%20Repeat/Plasma%20EV-Exp%201%20Quant/%40files/RawFiles/`
* **Access: OK (207).** MEASURED: **200 files, 1,166.7 GB**, split by plate:

| subfolder | files | raw GB | avg GB |
|---|---|---|---|
| Plate 1-ChromLib | 4 | 13.4 | 3.35 |
| Plate 1-QuantFiles | 96 | 604.2 | 6.29 |
| Plate 2-ChromLib | 4 | 11.3 | 2.83 |
| Plate 2-QuantFiles | 96 | 537.7 | 5.60 |

EVs in patients undergoing aortic arch replacement. The only one of the three that ships a
**chromatogram library** (ChromLib) alongside the quant runs, and the only one already
split by plate on disk - so a single 96-run plate is a self-contained unit to stage.

## 4. TEIREX Experiment 2 (Panorama Public) - MEASURED

* Portal: https://panoramaweb.org/Panorama%20Public/2026/TEIREX%20-%20A%20quantitative%20proteomics%20dataset%20for%20assessment%20and%20prediction%20of%20low%20dose%20X-ray%20radiation%20exposure%20in%20mice/Experiment%202/project-begin.view
* WebDAV root: `https://panoramaweb.org/_webdav/Panorama%20Public/2026/TEIREX%20-%20A%20quantitative%20proteomics%20dataset%20for%20assessment%20and%20prediction%20of%20low%20dose%20X-ray%20radiation%20exposure%20in%20mice/Experiment%202/%40files/`
* **Access: public, no credentials needed.**

Mouse samples, 10 x 96-well plates. Radiation dose response.

```
RawFiles/raw_files/Plate<N>_quant/       .raw, 96 per plate (Plate10 has 72)
RawFiles/mzML_for_carafe/                1 x 8.2 GB mzML (the library-tuning file)
RawFiles/DIANN/                          DIA-NN output
LevelData/, TnE_2a_rerun_..._annotated/  per-plate Skyline documents
<root>                                   10 x .sky.zip, 553.8 GB total
```

| plate | files | raw GB | avg GB |
|---|---|---|---|
| 1 | 96 | 942.1 | 9.81 |
| 2 | 96 | 843.3 | 8.78 |
| 3 | 96 | 908.5 | 9.46 |
| 4 | 96 | 946.7 | 9.86 |
| 5 | 96 | 931.8 | 9.71 |
| 6 | 96 | 817.3 | 8.51 |
| 7 | 96 | 773.0 | 8.05 |
| 8 | 96 | 740.0 | 7.71 |
| 9 | 96 | 817.0 | 8.51 |
| 10 | 72 | 576.6 | 8.01 |
| **total** | **936** | **8,296.2** | 8.86 |

**The whole set does not fit on this machine** (5,883 GB free on D:). ONE plate does: ~950 GB
raw, plus mzML and caches (see budgeting below). Note the per-file average is ~8.9 GB versus
SEA-AD's 5.9 GB, so a TEIREX plate is heavier per run as well as more numerous.

Mike's note: this set needs ~500 GB RAM for the DIA-NN neural-net step. That is a DIA-NN
constraint, not an Osprey one, but it indicates the scale.

## Budgeting a download

Ratios measured on SEA-AD (Astral .raw -> mzML -> Osprey cache):

* **mzML ~= 0.73 x raw** (SEA-AD: 484 GB raw -> 324.5 GB mzML)
* **.spectra.bin ~= 1.07 x mzML** (324.5 GB mzML -> 345.9 GB caches)
* So **raw + mzML + caches ~= 2.5 x raw**, and Stage 1-5 artifacts add roughly another
  0.5x (parquets; ~150 GB for 82 SEA-AD files).

Raw can be deleted after conversion, which is the cheapest way to halve the footprint - but
only once the mzML are verified, since re-downloading is the expensive part.

Applied to the candidates (5,880 GB free on D: as of 2026-07-28):

| dataset | raw | + mzML | + caches | + parquets | peak need |
|---|---|---|---|---|---|
| TDP-43 (164) | 784 | 572 | 612 | ~390 | **2,358 GB** - comfortable |
| AHA (200) | 1,167 | 852 | 911 | ~580 | **3,510 GB** - fits |
| AHA one plate (100) | 618 | 451 | 482 | ~310 | **1,861 GB** - easy |
| CHS (446) | 1,774 | 1,295 | 1,386 | ~890 | **5,345 GB** - 91% of free, too tight |
| CHS by plate (~74) | 294 | 215 | 230 | ~150 | **889 GB** - easy |

Deleting raw after a verified conversion drops the CHS whole-set peak to ~3,571 GB, which
fits - but staging plate by plate is safer and matches how these are imported into Skyline
anyway (one document per plate).

Osprey reads mzML only (`Osprey.IO` has no `.raw` reader), so **every raw dataset needs an
msconvert pass**. See `ai/scripts/Osprey/SEA-AD/Convert-SeaAdRaw.ps1` and `convert-one.cmd`
for the exact command line already in use.

## How to get these numbers for a new dataset

The counts and sizes here are not read off a portal page - they are computed from WebDAV
metadata, which is why they can be broken down by extension and by subfolder.

**1. Turn the portal URL into a WebDAV URL.** Insert `_webdav/` after the host, drop the
`.view` action, append `%40files/` (LabKey's `@files` root):

```
https://panoramaweb.org/<container path>/project-begin.view
->  https://panoramaweb.org/_webdav/<container path>/%40files/
```

Spaces stay `%20`. A wrong path returns 404, so a successful listing IS the verification
that you derived it correctly.

**2. PROPFIND it.** `Depth: 1` returns one `<d:response>` per child with `getcontentlength`
(exact bytes) and `resourcetype` (file vs collection):

```powershell
curl.exe -s --netrc -o out.xml -w "%{http_code}" -X PROPFIND -H "Depth: 1" <webdav-url>
```

Sum the lengths, count the entries. `ai/scripts/Osprey/Get-PanoramaFiles.ps1 -WhatIf` does
exactly this and prints the inventory without downloading.

**3. Descend to find the raw files.** There is no naming convention - the four datasets
here use `RawFiles/`, `RAW data files/`, and `RawFiles/raw_files/Plate<N>_quant/`
respectively. List each level rather than assuming.

## Getting access to a container that returns 403

The account authenticates (a 401 would mean no credentials); 403 means the container is not
shared. Ask for the **Agents group** to be granted read on the specific container - the
grant does not inherit from a parent, which is why SEA-AD needed its own even though
`MacCoss/Collaborations` itself is readable.

Verify with a PROPFIND before planning a download:

```powershell
curl.exe -s --netrc -o out.xml -w "%{http_code}" -X PROPFIND -H "Depth: 1" <webdav-url>
```

`207` = readable, `403` = needs a grant, `401` = credentials missing from netrc.
