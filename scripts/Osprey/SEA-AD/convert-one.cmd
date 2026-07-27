@echo off
setlocal
rem Verbatim reproduction of Mike MacCoss's msconvert command line for SEA-AD DIA.
rem %1 = full path to input .raw   %2 = output directory   %3 = full path to msconvert.exe
rem The triple-quote / caret escaping in the titleMaker filter is intentional cmd
rem quoting (embeds literal quotes around SourcePath/Id, keeps <> literal). Do not reformat.
rem This stays a .cmd for exactly that reason: the quoting is proven here and does not
rem survive being rewritten as a PowerShell native-command invocation.
set "MSCONVERT=%~3"
if "%MSCONVERT%"=="" set "MSCONVERT=msconvert.exe"
"%MSCONVERT%" --zlib --simAsSpectra --filter "peakPicking vendor msLevel=1-" --filter "titleMaker <RunId>.<ScanNumber>.<ScanNumber>.<ChargeState> File:"""^<SourcePath^>""", NativeID:"""^<Id^>"""" -o "%~2" "%~1"
exit /b %ERRORLEVEL%
