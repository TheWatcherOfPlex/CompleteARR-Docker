# CompleteARR FetchInfo Launcher
# This script launches the CompleteARR FetchInfo script

# Get the directory where this script is located
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ParentDir = Split-Path -Parent $ScriptDir

# Define the path to the FetchInfo script
$FetchInfoScript = Join-Path $ParentDir "CompleteARR_Scripts" "CompleteARR_FetchInfo.ps1"

# Check if the FetchInfo script exists
if (Test-Path $FetchInfoScript) {
    Write-Host "Launching CompleteARR FetchInfo..." -ForegroundColor Green
    & $FetchInfoScript
} else {
    Write-Host "Error: FetchInfo script not found at $FetchInfoScript" -ForegroundColor Red
    Write-Host "Please ensure the CompleteARR_Scripts directory contains CompleteARR_FetchInfo.ps1" -ForegroundColor Yellow
    if ($env:COMPLETEARR_NO_PAUSE -ne '1') {
        Read-Host "Press Enter to exit"
    }
}
