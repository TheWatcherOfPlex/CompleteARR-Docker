#Requires -Version 7.0
<#
    CompleteARR_ExtractErrorLogs.ps1

    Creates small, AI-readable error-only logs from existing full logs.

    Folder layout (under a single base folder):
      - Full Logs\  : full logs live here
      - Error Logs\ : extracted error logs written here

    This script is designed to be safe for HUGE log files:
      - Uses streaming Select-String (does not load entire file into memory)
      - Can cap matches per file to keep output small
      - Can add a small amount of context around each match
#>

[CmdletBinding()]
param(
    # Base logs folder (contains "Full Logs" and "Error Logs")
    [Parameter(Mandatory)]
    [string]$LogsBase,

    # Regex pattern that marks an error line in CompleteARR logs.
    [string]$Pattern = '\[(ERROR|FATAL)\]|\[[0-9;]*m\[(ERROR|FATAL)\]',

    # How many matching blocks to capture per file.
    # Each "match" includes the matched line + context lines.
    [int]$MaxMatchesPerFile = 200,

    # Context lines before/after each match.
    [int]$ContextBefore = 2,
    [int]$ContextAfter = 2,

    # Only process files modified within this many days (0 = all files)
    [int]$SinceDays = 0
)

$ErrorActionPreference = 'Stop'

$fullDir  = Join-Path $LogsBase 'Full Logs'
$errorDir = Join-Path $LogsBase 'Error Logs'

if (-not (Test-Path -LiteralPath $fullDir)) {
    throw "Full logs folder not found: $fullDir"
}

New-Item -ItemType Directory -Force -Path $errorDir | Out-Null

$cutoff = if ($SinceDays -gt 0) { (Get-Date).AddDays(-$SinceDays) } else { $null }

$files = Get-ChildItem -LiteralPath $fullDir -File -Filter '*.log' -ErrorAction Stop |
    Sort-Object LastWriteTime -Descending

if ($cutoff) {
    $files = $files | Where-Object { $_.LastWriteTime -ge $cutoff }
}

Write-Host "Scanning $($files.Count) log files in: $fullDir" -ForegroundColor Cyan
Write-Host "Writing error-only logs to: $errorDir" -ForegroundColor Cyan
Write-Host "Pattern: $Pattern" -ForegroundColor DarkGray

foreach ($file in $files) {
    $outName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) + '_ERRORS_EXTRACTED.log'
    $outPath = Join-Path $errorDir $outName

    # Ensure we start fresh each run.
    if (Test-Path -LiteralPath $outPath) {
        Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
    }

    $matchCount = 0
    $hadAny = $false

    # Header
    Add-Content -LiteralPath $outPath -Value ("Source: {0}" -f $file.FullName)
    Add-Content -LiteralPath $outPath -Value ("Generated: {0:yyyy-MM-dd HH:mm:ss}" -f (Get-Date))
    Add-Content -LiteralPath $outPath -Value ("MaxMatchesPerFile: {0}, Context: {1} before / {2} after" -f $MaxMatchesPerFile, $ContextBefore, $ContextAfter)
    Add-Content -LiteralPath $outPath -Value ('-' * 110)

    try {
        $results = Select-String -LiteralPath $file.FullName -Pattern $Pattern -Context $ContextBefore,$ContextAfter
        foreach ($r in $results) {
            $hadAny = $true
            $matchCount++

            Add-Content -LiteralPath $outPath -Value ("\n# Match {0} at line {1}" -f $matchCount, $r.LineNumber)
            if ($r.Context.PreContext) {
                foreach ($line in $r.Context.PreContext) {
                    Add-Content -LiteralPath $outPath -Value ("  {0}" -f $line)
                }
            }
            Add-Content -LiteralPath $outPath -Value ("> {0}" -f $r.Line)
            if ($r.Context.PostContext) {
                foreach ($line in $r.Context.PostContext) {
                    Add-Content -LiteralPath $outPath -Value ("  {0}" -f $line)
                }
            }

            if ($matchCount -ge $MaxMatchesPerFile) {
                Add-Content -LiteralPath $outPath -Value ("\n[TRUNCATED] Hit MaxMatchesPerFile={0}." -f $MaxMatchesPerFile)
                break
            }
        }
    }
    catch {
        # If Select-String itself fails (permissions/IO), capture that as a single error.
        Add-Content -LiteralPath $outPath -Value ("\n[EXTRACTOR ERROR] Failed to scan file: {0}" -f $_.Exception.Message)
        $hadAny = $true
    }

    if (-not $hadAny) {
        # Keep directory clean: remove empty extracted logs.
        Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
    }
    else {
        # Stamp file time similar to the source for easier sorting.
        try { (Get-Item -LiteralPath $outPath).LastWriteTime = $file.LastWriteTime } catch { }
        Write-Host ("{0} -> {1} matches" -f $file.Name, $matchCount) -ForegroundColor Green
    }
}

Write-Host "Done." -ForegroundColor Cyan
