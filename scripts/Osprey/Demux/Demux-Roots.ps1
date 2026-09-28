# The data roots every demux driver reads and writes, dot-sourced after each script's param block.
# Set DEMUX_DATA_ROOT (the vendor files) and DEMUX_RUN_ROOT (everything written) to move them; the
# defaults are the machine the work started on. demux_roots.py is the same for the Python scripts.
$dataRoot = $env:DEMUX_DATA_ROOT ?? 'D:\demux-test-data'
$runRoot = $env:DEMUX_RUN_ROOT ?? 'D:\test\osprey-runs'
