#Requires -Version 7.0
<#
    CompleteARR_Launch_All_Scripts.ps1
    ---------------------------------------------
    Orchestrates the CompleteARR suite for BOTH Radarr and Sonarr:

      1) Fetches Info (Logs current configuration)
      2) Runs Radarr Film Engine
      3) Runs Sonarr Series Engine

    This is your "Run Everything" button for CompleteARR!
    Use the individual launchers if you only want to run one or the other.
#>

[CmdletBinding()]
param(
    # Optional override for Sonarr settings file
    [string]$SonarrConfigPath,
    # Optional override for Radarr settings file
    [string]$RadarrConfigPath
)

function Wait-IfInteractive {
    param([string]$Prompt)
    # In Docker/UI runs we must not block on Read-Host.
    if ($env:COMPLETEARR_NO_PAUSE -eq '1') { return }
    Read-Host $Prompt
}

# ------------------------------------------------------------
# Resolve paths
# ------------------------------------------------------------

$CompleteArrRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$CompleteArrRoot = Split-Path -Path $CompleteArrRoot -Parent

# All scripts
$FetchInfoPath        = Join-Path $CompleteArrRoot 'CompleteARR_Scripts\CompleteARR_FetchInfo.ps1'
$RadarrEnginePath     = Join-Path $CompleteArrRoot 'CompleteARR_Scripts\CompleteARR_RADARR_FilmEngine.ps1'
$SonarrEnginePath     = Join-Path $CompleteArrRoot 'CompleteARR_Scripts\CompleteARR_SONARR_SeriesEngine.ps1'

# Default settings paths
$DefaultSonarrSettingsPath = Join-Path $CompleteArrRoot 'CompleteARR_Settings' 'CompleteARR_SONARR_Settings.yml'
$DefaultRadarrSettingsPath = Join-Path $CompleteArrRoot 'CompleteARR_Settings' 'CompleteARR_RADARR_Settings.yml'

if (-not $SonarrConfigPath) {
    $SonarrConfigPath = $DefaultSonarrSettingsPath
}
if (-not $RadarrConfigPath) {
    $RadarrConfigPath = $DefaultRadarrSettingsPath
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " 🎬 CompleteARR Launch All Scripts - Starting Up!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "📁 Working from folder: $CompleteArrRoot" -ForegroundColor Cyan
Write-Host "🎥 Radarr settings: $RadarrConfigPath" -ForegroundColor Cyan
Write-Host "🎬 Sonarr settings: $SonarrConfigPath" -ForegroundColor Cyan
Write-Host ""
Write-Host "🔍 Checking your files and settings..." -ForegroundColor Cyan
Write-Host ""

# Quick checks so errors are obvious
$allScriptsExist = $true

if (-not (Test-Path -LiteralPath $FetchInfoPath)) {
    Write-Host "ERROR: Could not find Fetch Info script at:" -ForegroundColor Red
    Write-Host "  $FetchInfoPath" -ForegroundColor Red
    $allScriptsExist = $false
}

if (-not (Test-Path -LiteralPath $RadarrEnginePath)) {
    Write-Host "ERROR: Could not find Radarr Engine script at:" -ForegroundColor Red
    Write-Host "  $RadarrEnginePath" -ForegroundColor Red
    $allScriptsExist = $false
}

if (-not (Test-Path -LiteralPath $SonarrEnginePath)) {
    Write-Host "ERROR: Could not find Sonarr Engine script at:" -ForegroundColor Red
    Write-Host "  $SonarrEnginePath" -ForegroundColor Red
    $allScriptsExist = $false
}

if (-not $allScriptsExist) {
    Wait-IfInteractive "Press ENTER to close this window"
    exit 1
}

if (-not (Test-Path -LiteralPath $RadarrConfigPath)) {
    Write-Host "WARNING: Radarr config file not found at:" -ForegroundColor Yellow
    Write-Host "  $RadarrConfigPath" -ForegroundColor Yellow
    Write-Host "Radarr scripts may fail to start if they rely on this path." -ForegroundColor Yellow
}

if (-not (Test-Path -LiteralPath $SonarrConfigPath)) {
    Write-Host "WARNING: Sonarr config file not found at:" -ForegroundColor Yellow
    Write-Host "  $SonarrConfigPath" -ForegroundColor Yellow
    Write-Host "Sonarr scripts may fail to start if they rely on this path." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✅ All scripts found! Starting CompleteARR..." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Run Fetch Info (Step 1)
# ------------------------------------------------------------

$overallSuccess = $true

Write-Host "============================================" -ForegroundColor Green
Write-Host " 📊 STEP 1: Fetching Configuration Info" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "📋 The Fetch Info tool will:" -ForegroundColor Green
Write-Host "   • Read your Sonarr and Radarr configuration" -ForegroundColor Green
Write-Host "   • Fetch quality profiles and root folders" -ForegroundColor Green
Write-Host "   • Log the current state for troubleshooting" -ForegroundColor Green
Write-Host "   • Run automatically without waiting for input" -ForegroundColor Green
Write-Host ""

try {
    & $FetchInfoPath
    Write-Host ""
    Write-Host "✅ Fetch Info completed successfully!" -ForegroundColor Green
    Write-Host "   Configuration info logged for troubleshooting." -ForegroundColor Green
}
catch {
    $overallSuccess = $false
    Write-Host ""
    Write-Host "ERROR: CompleteARR Fetch Info failed with error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: Continuing to run other scripts anyway." -ForegroundColor Yellow
}

Write-Host ""

# ------------------------------------------------------------
# Run Radarr Suite
# ------------------------------------------------------------

Write-Host "============================================" -ForegroundColor Magenta
Write-Host " 🎥 RADARR SUITE - Starting" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host " 🔄 STEP 2: Running Radarr Film Engine" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-Host "📋 The Radarr Film Engine will:" -ForegroundColor Yellow
Write-Host "   • Ensure movies are in the correct folders" -ForegroundColor Yellow
Write-Host "   • Maintain profile-to-root folder consistency" -ForegroundColor Yellow
Write-Host "   • Keep your movie library organized" -ForegroundColor Yellow
Write-Host ""

$radarrFilmEngineSummary = $null
try {
    if (Test-Path -LiteralPath $RadarrConfigPath) {
        $radarrFilmEngineSummary = & $RadarrEnginePath -ConfigPath $RadarrConfigPath
    }
    else {
        $radarrFilmEngineSummary = & $RadarrEnginePath
    }
    Write-Host ""
    Write-Host "✅ Radarr Film Engine completed successfully!" -ForegroundColor Green
    Write-Host "   Movies are organized in their correct folders." -ForegroundColor Green
}
catch {
    $overallSuccess = $false
    Write-Host ""
    Write-Host "ERROR: CompleteARR Radarr Engine failed with error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Magenta
Write-Host " 🎥 RADARR SUITE - Complete" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Magenta
Write-Host ""

# ------------------------------------------------------------
# Run Sonarr Suite
# ------------------------------------------------------------

Write-Host "============================================" -ForegroundColor Blue
Write-Host " 🎬 SONARR SUITE - Starting" -ForegroundColor Blue
Write-Host "============================================" -ForegroundColor Blue
Write-Host ""

Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host " 🔄 STEP 3: Running Sonarr Series Engine" -ForegroundColor Yellow
Write-Host "------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-Host "📋 The Sonarr Series Engine will:" -ForegroundColor Yellow
Write-Host "   • Check which shows are 'Complete' (all episodes downloaded)" -ForegroundColor Yellow
Write-Host "   • Move complete shows to 'Complete' folders (visible to users)" -ForegroundColor Yellow
Write-Host "   • Move incomplete shows back if new episodes are missing" -ForegroundColor Yellow
Write-Host "   • Manage special episode monitoring" -ForegroundColor Yellow
Write-Host ""

$sonarrSeriesEngineSummary = $null
try {
    if (Test-Path -LiteralPath $SonarrConfigPath) {
        $sonarrSeriesEngineSummary = & $SonarrEnginePath -ConfigPath $SonarrConfigPath
    }
    else {
        $sonarrSeriesEngineSummary = & $SonarrEnginePath
    }
    Write-Host ""
    Write-Host "✅ Sonarr Series Engine completed successfully!" -ForegroundColor Green
    Write-Host "   Shows have been promoted/demoted as needed." -ForegroundColor Green
}
catch {
    $overallSuccess = $false
    Write-Host ""
    Write-Host "ERROR: CompleteARR Sonarr Engine failed with error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Blue
Write-Host " 🎬 SONARR SUITE - Complete" -ForegroundColor Blue
Write-Host "============================================" -ForegroundColor Blue
Write-Host ""

# ------------------------------------------------------------
# Final message
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " 🎉 CompleteARR All Scripts Finished!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if ($overallSuccess) {
    Write-Host "✅ All tasks completed successfully!" -ForegroundColor Green
    Write-Host "   Your entire media library is now organized and ready for users." -ForegroundColor Green
}
else {
    Write-Host "⚠️  Some tasks encountered errors." -ForegroundColor Yellow
    Write-Host "   Check the logs in the CompleteARR_Logs folder for details." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "📁 Log files are saved in: CompleteARR_Logs/" -ForegroundColor Cyan
Write-Host ""
Write-Host "🎯 Available launchers:" -ForegroundColor Cyan
Write-Host "   • CompleteARR_Launch_All_Scripts.ps1 - Run everything (this script)" -ForegroundColor White
Write-Host "   • CompleteARR_RADARR_Launcher.ps1   - Run only Radarr (movies)" -ForegroundColor White
Write-Host "   • CompleteARR_SONARR_Launcher.ps1   - Run only Sonarr (TV shows)" -ForegroundColor White
Write-Host ""

# ------------------------------------------------------------
# Master Summary
# ------------------------------------------------------------

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " 📊 MASTER SUMMARY - CompleteARR Results" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Radarr Film Engine Summary
if ($radarrFilmEngineSummary) {
    Write-Host "🎥 RADARR FILM ENGINE:" -ForegroundColor Magenta
    Write-Host ("  Movies checked             : {0}" -f $radarrFilmEngineSummary.MoviesChecked) -ForegroundColor White
    Write-Host ("  Movies skipped             : {0}" -f $radarrFilmEngineSummary.MoviesSkipped) -ForegroundColor White
    Write-Host ("  Root corrections           : {0}" -f $radarrFilmEngineSummary.RootCorrections) -ForegroundColor White
    Write-Host ("  Errors                     : {0}" -f $radarrFilmEngineSummary.Errors) -ForegroundColor White
    Write-Host ""
}

# Sonarr Series Engine Summary
if ($sonarrSeriesEngineSummary) {
    Write-Host "🎬 SONARR SERIES ENGINE:" -ForegroundColor Blue
    Write-Host ("  Series checked             : {0}" -f $sonarrSeriesEngineSummary.SeriesChecked) -ForegroundColor White
    Write-Host ("  Series skipped             : {0}" -f $sonarrSeriesEngineSummary.SkippedDueToErrors) -ForegroundColor White
    Write-Host ("  Series promoted            : {0}" -f $sonarrSeriesEngineSummary.Promotions) -ForegroundColor White
    Write-Host ("  Series demoted             : {0}" -f $sonarrSeriesEngineSummary.Demotions) -ForegroundColor White
    Write-Host ("  Specials monitored         : {0}" -f $sonarrSeriesEngineSummary.SpecialsMonitoredInComplete) -ForegroundColor White
    Write-Host ("  Root corrections           : {0}" -f $sonarrSeriesEngineSummary.RootCorrections) -ForegroundColor White
    Write-Host ("  Errors                     : {0}" -f $sonarrSeriesEngineSummary.Errors) -ForegroundColor White
    Write-Host ""
}

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " 🎉 CompleteARR Master Summary Complete!" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Wait-IfInteractive "Press ENTER to close this window:"
