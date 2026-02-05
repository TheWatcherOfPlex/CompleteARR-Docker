#Requires -Version 7.0
<#
    CompleteARR_LogTest.ps1

    Minimal logging test to verify full + error logs are created correctly.
    Writes INFO + ERROR lines and prints the log paths to console.
#>

[CmdletBinding()]
param(
    [string]$LogsRoot
)

$ErrorActionPreference = 'Stop'

$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptDir  = Split-Path -Path $thisScriptPath -Parent
$projectRoot    = Split-Path -Path $thisScriptDir -Parent

$loggingHelpersPath = Join-Path $projectRoot 'CompleteARR_Scripts' 'CompleteARR_Logging.ps1'
if (Test-Path -LiteralPath $loggingHelpersPath) {
    . $loggingHelpersPath
}

if (-not $LogsRoot) {
    $LogsRoot = Join-Path $projectRoot 'CompleteARR_Logs'
}

$paths = Initialize-CompleteARRLogPaths -ScriptRoot $projectRoot -ScriptName 'CompleteARR_LogTest' -Extension '.log' -LogsBase $LogsRoot

Write-Host "Full log:  $($paths.FullLogFile)" -ForegroundColor Cyan
Write-Host "Error log: $($paths.ErrorLogFile)" -ForegroundColor Cyan

Add-Content -LiteralPath $paths.FullLogFile -Value "[INFO] Log test started."
Add-Content -LiteralPath $paths.FullLogFile -Value "[ERROR] Log test generated a sample error entry."

# Ensure error log receives the error line
if (Get-Command -Name Add-CompleteARRErrorLogLine -ErrorAction SilentlyContinue) {
    Add-CompleteARRErrorLogLine -ErrorLogPath $paths.ErrorLogFile -Line "[ERROR] Log test generated a sample error entry."
} else {
    Add-Content -LiteralPath $paths.ErrorLogFile -Value "[ERROR] Log test generated a sample error entry."
}

Write-Host "Log test complete." -ForegroundColor Green
