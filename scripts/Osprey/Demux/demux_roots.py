"""The data roots the demux scripts read and write (Demux-Roots.ps1 is the same for the drivers).

Set DEMUX_DATA_ROOT (the vendor files) and DEMUX_RUN_ROOT (everything written) to move them; the
defaults are the machine the work started on.
"""
import os

DATA_ROOT = os.environ.get('DEMUX_DATA_ROOT') or r'D:\demux-test-data'
RUN_ROOT = os.environ.get('DEMUX_RUN_ROOT') or r'D:\test\osprey-runs'
