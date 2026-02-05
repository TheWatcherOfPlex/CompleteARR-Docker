#Requires -Version 7.0
<#
    CompleteARR_LogTest_Launcher.ps1
    ---------------------------------------------
    Runs the CompleteARR_LogTest.ps1 helper to validate
    Full Logs + Error Logs creation.
#>

[CmdletBinding()]
param(
    [string]$LogsRoot
)

function Wait-IfInteractive {
    param([string]$Prompt)
    if ($env:COMPLETEARR_NO_PAUSE -eq '1') { return }
    Read-Host $Prompt
}

$CompleteArrRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$CompleteArrRoot = Split-Path -Path $CompleteArrRoot -Parent

$TestScriptPath = Join-Path $CompleteArrRoot 'CompleteARR_Scripts\CompleteARR_LogTest.ps1'

if (-not (Test-Path -LiteralPath $TestScriptPath)) {
    Write-Host "ERROR: Could not find LogTest script at:" -ForegroundColor Red
    Write-Host "  $TestScriptPath" -ForegroundColor Red
    Wait-IfInteractive "Press ENTER to close this window"
    exit 1
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " 🧪 CompleteARR Log Test - Starting Up!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($LogsRoot) {
    & $TestScriptPath -LogsRoot $LogsRoot
} else {
    & $TestScriptPath
}

Write-Host ""
Write-Host "✅ Log test finished." -ForegroundColor Green
Write-Host ""

Wait-IfInteractive "Press ENTER to close this window:"
