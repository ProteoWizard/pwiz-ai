# Convert only files currently added/modified in Git to CRLF and verify
#
# Usage: .\fix-crlf.ps1
# Scope: Only processes files in 'git status' (modified/added)
#        Also processes the ai/ submodule (pwiz-ai) explicitly
#
# This script was created during the webclient_replacement work (Oct 2025)
# when LLM tools (which prefer Linux-style LF) inadvertently changed
# line endings from Windows CRLF to LF-only, causing large Git diffs.
#
# The project standard is CRLF on Windows. Run this script before committing
# if you notice files with unwanted line ending changes.

# Function to check if a file is binary
function Test-BinaryFile {
  param([string]$filePath)

  # Check Git attributes for binary marking
  $attr = git check-attr binary -- $filePath 2>$null
  if ($attr -match 'binary:\s+set') {
    return $true
  }

  # Check common binary file extensions
  $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.ico', '.zip',
                        '.gz', '.tar', '.skyd', '.mzml', '.mzxml', '.raw',
                        '.wiff', '.dll', '.exe', '.so', '.dylib', '.pdf')
  $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
  if ($binaryExtensions -contains $ext) {
    return $true
  }

  return $false
}

# Function to get modified files from git status
function Get-ModifiedFiles {
  param([string]$workDir = ".")

  Push-Location $workDir
  try {
    $files = git status --porcelain 2>$null | Where-Object { $_ -match '^( M|AM|A )' } |
             ForEach-Object { $_ -replace '^...','' }
    return $files
  } finally {
    Pop-Location
  }
}

# Function to convert files to CRLF
function Convert-ToCRLF {
  param(
    [string[]]$files,
    [string]$baseDir = "."
  )

  $converted = @()
  foreach ($f in $files) {
    $fullPath = Join-Path $baseDir $f
    if (Test-Path $fullPath) {
      # Skip directories (including submodules)
      if (Test-Path $fullPath -PathType Container) {
        continue
      }
      # Skip binary files
      if (Test-BinaryFile -filePath $fullPath) {
        continue
      }

      $absolutePath = (Resolve-Path -LiteralPath $fullPath).Path
      $text  = [System.IO.File]::ReadAllText($absolutePath, [System.Text.UTF8Encoding]::new($false))
      $fixed = [regex]::Replace($text, "`r?`n", "`r`n")
      if ($fixed -ne $text) {
        [System.IO.File]::WriteAllText($absolutePath, $fixed, [System.Text.UTF8Encoding]::new($false))
        $converted += $fullPath
        Write-Host "Converted: $fullPath"
      }
    }
  }
  return $converted
}

# Function to verify no LF-only files remain
function Test-NoLFOnly {
  param(
    [string[]]$files,
    [string]$baseDir = "."
  )

  $bad = @()
  foreach ($f in $files) {
    $fullPath = Join-Path $baseDir $f
    if (Test-Path $fullPath) {
      # Skip directories (including submodules)
      if (Test-Path $fullPath -PathType Container) {
        continue
      }
      # Skip binary files
      if (Test-BinaryFile -filePath $fullPath) {
        continue
      }

      $absolutePath = (Resolve-Path -LiteralPath $fullPath).Path
      $s = [System.IO.File]::ReadAllText($absolutePath, [System.Text.UTF8Encoding]::new($false))
      if ($s -match '(?<!\r)\n') { $bad += $absolutePath }
    }
  }
  return $bad
}

# --- Main script ---

$allBad = @()
$anyFiles = $false

# Detect mode: sibling (ai/ is the repo) vs child (ai/ is inside pwiz/)
$gitRoot = git rev-parse --show-toplevel 2>$null
if (-not $gitRoot) {
  Write-Host "Not in a git repository" -ForegroundColor Red
  exit 1
}

$isSiblingMode = (Split-Path $gitRoot -Leaf) -eq 'ai'

if ($isSiblingMode) {
  # Sibling mode: we're in the ai/ repo (pwiz-ai), process it directly
  $aiFiles = Get-ModifiedFiles -workDir $gitRoot
  if ($aiFiles) {
    $anyFiles = $true
    Write-Host "Processing ai/ repository (sibling mode)..." -ForegroundColor Cyan
    Convert-ToCRLF -files $aiFiles -baseDir $gitRoot | Out-Null
    $allBad += Test-NoLFOnly -files $aiFiles -baseDir $gitRoot
  }
} else {
  # Child mode: process parent repo and ai/ clone separately
  $parentFiles = Get-ModifiedFiles -workDir "."
  if ($parentFiles) {
    $anyFiles = $true
    Convert-ToCRLF -files $parentFiles -baseDir "." | Out-Null
    $allBad += Test-NoLFOnly -files $parentFiles -baseDir "."
  }

  # Process ai/ clone explicitly (pwiz-ai)
  $aiPath = Join-Path $gitRoot "ai"
  if (Test-Path $aiPath -PathType Container) {
    $aiFiles = Get-ModifiedFiles -workDir $aiPath
    if ($aiFiles) {
      $anyFiles = $true
      Write-Host "`nProcessing ai/ clone..." -ForegroundColor Cyan
      Convert-ToCRLF -files $aiFiles -baseDir $aiPath | Out-Null
      $allBad += Test-NoLFOnly -files $aiFiles -baseDir $aiPath
    }
  }
}

if (-not $anyFiles) {
  Write-Host 'No modified/added files found.' -ForegroundColor Yellow
  exit 0
}

if ($allBad.Count) {
  Write-Host "`nLF-only still present in:" -ForegroundColor Red
  $allBad | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
  exit 1
} else {
  Write-Host "`nAll converted to CRLF." -ForegroundColor Green
}
