#Requires -Version 7.0
<#
    CompleteARR_Logging.ps1
    Shared logging helpers.

    Goals:
      - Keep full logs in:   CompleteARR_Logs/Full Logs
      - Keep error-only in:  CompleteARR_Logs/Error Logs
      - Make it easy to write a small, AI-readable error log.
#>

function Initialize-CompleteARRLogPaths {
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter(Mandatory)][string]$Extension,

        # Optional override for the base log folder (the folder that contains Full Logs/ + Error Logs/)
        [string]$LogsBase = $null
    )

    if ([string]::IsNullOrWhiteSpace($LogsBase)) {
        $LogsBase = Join-Path $ScriptRoot 'CompleteARR_Logs'
    }

    $logsBase = $LogsBase
    $fullLogs = Join-Path $logsBase 'Full Logs'
    $errorLogs = Join-Path $logsBase 'Error Logs'

    foreach ($dir in @($logsBase, $fullLogs, $errorLogs)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }
    }

    # Move any old *.log files living in the base logs folder into Full Logs.
    Get-ChildItem -LiteralPath $logsBase -File -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -eq $logsBase } |
        ForEach-Object {
            try { Move-Item -LiteralPath $_.FullName -Destination $fullLogs -Force -ErrorAction Stop } catch { }
        }

    # Move any existing error logs (if present) into Error Logs.
    Get-ChildItem -LiteralPath $fullLogs -File -Filter '*_ERRORS*.log' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { Move-Item -LiteralPath $_.FullName -Destination $errorLogs -Force -ErrorAction Stop } catch { }
        }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HHmm')
    $fullLogFile = Join-Path $fullLogs ("{0}_{1}{2}" -f $ScriptName, $timestamp, $Extension)
    $errorLogFile = Join-Path $errorLogs ("{0}_{1}_ERRORS{2}" -f $ScriptName, $timestamp, $Extension)

    # Ensure the files exist (even if empty) so users can find them reliably.
    try { New-Item -Path $fullLogFile -ItemType File -Force | Out-Null } catch { }
    try { New-Item -Path $errorLogFile -ItemType File -Force | Out-Null } catch { }

    # Stamp log paths so troubleshooting can always confirm file locations.
    try {
        Add-Content -LiteralPath $fullLogFile -Value ("[LOG] Full log file   : {0}" -f $fullLogFile)
        Add-Content -LiteralPath $fullLogFile -Value ("[LOG] Error log file  : {0}" -f $errorLogFile)
        Add-Content -LiteralPath $fullLogFile -Value ("[LOG] Logs base       : {0}" -f $logsBase)
        Add-Content -LiteralPath $fullLogFile -Value ("[LOG] Timestamp       : {0}" -f $timestamp)
    } catch { }

    return [PSCustomObject]@{
        LogsBase = $logsBase
        FullLogsDir = $fullLogs
        ErrorLogsDir = $errorLogs
        FullLogFile = $fullLogFile
        ErrorLogFile = $errorLogFile
        Timestamp = $timestamp
    }
}

function Resolve-CompleteARRLogsBase {
    <#
      Resolves the logs base directory.

      Priority:
        1) Config.Logging.LogsRoot (if present)
        2) Default: <ScriptRoot>\CompleteARR_Logs
    #>
    param(
        [Parameter(Mandatory)][string]$ScriptRoot,
        [pscustomobject]$Config
    )

    $fromConfig = $null
    try {
        $fromConfig = $Config?.logging?.logsRoot
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace($fromConfig)) {
        return $fromConfig
    }

    return (Join-Path $ScriptRoot 'CompleteARR_Logs')
}

function Add-CompleteARRErrorLogLine {
    param(
        [Parameter(Mandatory)][string]$ErrorLogPath,
        [Parameter(Mandatory)][string]$Line
    )

    if (-not $ErrorLogPath) { return }
    try {
        Add-Content -LiteralPath $ErrorLogPath -Value $Line
    } catch {
        # Ignore error-log write failures; should never break the main run.
    }
}
