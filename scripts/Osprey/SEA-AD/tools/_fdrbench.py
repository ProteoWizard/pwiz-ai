"""Locate an Osprey --fdrbench output inside a run directory.

Osprey names the file differently depending on how the run was launched, and both
layouts exist among the SEA-AD runs:

    --fdrbench-pass 2      ->  fdrbench.tsv        + fdrbench.tsv.pairing.tsv
    --fdrbench-pass both   ->  fdrbench.pass2.tsv  + fdrbench.pass2.tsv.pairing.tsv
                               (and the .pass1 pair, when the first-pass pool was retained)

Readers that hardcode one name silently report "MISSING" against runs launched the other
way, which reads as "the run failed" rather than "I looked for the wrong file". Resolving
both here keeps that decision in one place.
"""
import os

# Most specific first: an explicit .passN file beats the unsuffixed one when both exist.
_STEMS = {
    1: ('fdrbench.pass1.tsv', 'fdrbench.tsv'),
    2: ('fdrbench.pass2.tsv', 'fdrbench.tsv'),
}


def resolve(run_dir, which=2):
    """Return (fdrbench_path, pairing_path) for the pass, or (None, None) if absent.

    A pairing file is required: without it there is no target/entrapment labelling and
    no FDP can be computed, so a lone fdrbench.tsv is not a usable result.
    """
    for stem in _STEMS[which]:
        fb = os.path.join(run_dir, stem)
        pr = fb + '.pairing.tsv'
        if os.path.exists(fb) and os.path.exists(pr):
            return fb, pr
    return None, None


def missing_message(run_dir, which=2):
    """Explain what was looked for, so a miss is diagnosable without reading this module."""
    names = ' or '.join(_STEMS[which])
    return (f"no pass-{which} FDRBench output in {run_dir} "
            f"(looked for {names}, each with a .pairing.tsv beside it)")
