#Requires -Version 7.0
<#
    CompleteARR_FetchInfo.ps1
    ------------------------------------------------------------
    
    🎯 WHAT THIS SCRIPT DOES:
    - Reads both Sonarr and Radarr configuration files
    - Fetches quality profiles and root folders from both instances
    - Displays the information in a structured format
    - Saves detailed information to log files for reference
    - Helps configure the CompleteARR scripts for both Sonarr and Radarr
    
    🔍 HOW IT WORKS:
    1. Reads CompleteARR_SONARR_Settings.yml and CompleteARR_RADARR_Settings.yml
    2. Connects to both Sonarr and Radarr instances using their API
    3. Fetches quality profiles and root folders
    4. Displays the information for easy configuration
    5. Saves detailed logs to CompleteARR_Logs folder
    
    💡 TIP: Use this information to populate the sets and profileRootMappings
            sections in your configuration files!
#>

[CmdletBinding()]
param(
    [switch]$ShowSonarr,
    [switch]$ShowRadarr
)

$ErrorActionPreference = 'Stop'

# If no switches are provided, show both by default
if (-not $ShowSonarr -and -not $ShowRadarr) {
    $ShowSonarr = $true
    $ShowRadarr = $true
}

# Initialize logging
$ScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
$ProjectRoot = Split-Path -Path $ScriptRoot -Parent

$loggingHelpersPath = Join-Path $ScriptRoot 'CompleteARR_Logging.ps1'
if (Test-Path -LiteralPath $loggingHelpersPath) {
    . $loggingHelpersPath
}

$timestamp = (Get-Date).ToString('yyyy-MM-dd_HHmm')

$logsBaseOverride = $null
try {
    # If either settings file specifies Logging.LogsRoot, use it.
    $sonarrConfig = Join-Path $ProjectRoot 'CompleteARR_Settings\CompleteARR_SONARR_Settings.yml'
    $radarrConfig = Join-Path $ProjectRoot 'CompleteARR_Settings\CompleteARR_RADARR_Settings.yml'
    if (Test-Path -LiteralPath $sonarrConfig) {
        $sraw = Get-Content -LiteralPath $sonarrConfig -Raw
        $scfg = $sraw | ConvertFrom-Yaml
        if ($scfg?.logging?.logsRoot) { $logsBaseOverride = $scfg.logging.logsRoot }
    }
    if (-not $logsBaseOverride -and (Test-Path -LiteralPath $radarrConfig)) {
        $rraw = Get-Content -LiteralPath $radarrConfig -Raw
        $rcfg = $rraw | ConvertFrom-Yaml
        if ($rcfg?.logging?.logsRoot) { $logsBaseOverride = $rcfg.logging.logsRoot }
    }
} catch { }

if (Get-Command -Name Initialize-CompleteARRLogPaths -ErrorAction SilentlyContinue) {
    $paths = Initialize-CompleteARRLogPaths -ScriptRoot $ProjectRoot -ScriptName 'CompleteARR_FetchInfo' -Extension '.log' -LogsBase $logsBaseOverride
    $logFile = $paths.FullLogFile
    $errorLogFile = $paths.ErrorLogFile
} else {
    $LogsRoot = Join-Path $ProjectRoot 'CompleteARR_Logs'
    if (-not (Test-Path -LiteralPath $LogsRoot)) {
        New-Item -Path $LogsRoot -ItemType Directory -Force | Out-Null
    }
    $logFile = Join-Path $LogsRoot "CompleteARR_FetchInfo_$timestamp.log"
    $errorLogFile = Join-Path $LogsRoot "CompleteARR_FetchInfo_${timestamp}_ERRORS.log"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level.ToUpperInvariant(), $Message
    
    # Write to console with colors
    switch ($Level.ToUpperInvariant()) {
        'ERROR'   { Write-Host $line -ForegroundColor 'Red' }
        'WARNING' { Write-Host $line -ForegroundColor 'Yellow' }
        'INFO'    { Write-Host $line -ForegroundColor 'Cyan' }
        'SUCCESS' { Write-Host $line -ForegroundColor 'Green' }
        default   { Write-Host $line -ForegroundColor 'White' }
    }
    
    # Always write to full log file
    Add-Content -LiteralPath $logFile -Value $line

    # Write errors to the error-only log as well
    if ($Level.ToUpperInvariant() -eq 'ERROR') {
        try {
            Add-Content -LiteralPath $errorLogFile -Value $line
        } catch { }
    }
}

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
    Write-Log -Message $Message -Level "INFO"
}

function Invoke-ArrApi {
    param(
        [string]$BaseUrl,
        [string]$ApiKey,
        [string]$Path,
        [string]$InstanceType
    )
    
    $uri = "$BaseUrl/api/v3/$Path"
    
    $headers = @{
        'X-Api-Key' = $ApiKey
    }
    
    try {
        Write-Host "Fetching $Path from $InstanceType..." -ForegroundColor Cyan
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
        return $response
    }
    catch {
        Write-ColorOutput "ERROR: Failed to fetch $Path from $InstanceType" "Red"
        Write-ColorOutput "  Error: $($_.Exception.Message)" "Yellow"
        return $null
    }
}

function Get-ArrInfo {
    param(
        [string]$ConfigPath,
        [string]$InstanceType
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-ColorOutput "Config file not found: $ConfigPath" "Yellow"
        return $null
    }
    
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw
        $cfg = $raw | ConvertFrom-Yaml
        
        if ($InstanceType -eq "Sonarr") {
            $url = $cfg.sonarr.url
            $apiKey = $cfg.sonarr.apiKey
        } else {
            $url = $cfg.radarr.url
            $apiKey = $cfg.radarr.apiKey
        }
        
        if (-not $url -or -not $apiKey) {
            Write-ColorOutput "ERROR: Missing URL or API key in $ConfigPath" "Red"
            return $null
        }
        
        # Fetch quality profiles
        $profiles = Invoke-ArrApi -BaseUrl $url -ApiKey $apiKey -Path "qualityprofile" -InstanceType $InstanceType
        if (-not $profiles) { return $null }
        
        # Fetch root folders
        $rootFolders = Invoke-ArrApi -BaseUrl $url -ApiKey $apiKey -Path "rootfolder" -InstanceType $InstanceType
        if (-not $rootFolders) { return $null }
        
        return @{
            Profiles = $profiles
            RootFolders = $rootFolders
            Url = $url
        }
    }
    catch {
        Write-ColorOutput "ERROR: Failed to process $ConfigPath" "Red"
        Write-ColorOutput "  Error: $($_.Exception.Message)" "Yellow"
        return $null
    }
}

function Show-ArrInfo {
    param(
        [string]$InstanceType,
        [object]$Info
    )
    
    if (-not $Info) { return }
    
    Write-ColorOutput "`n" "White"
    Write-ColorOutput "================================================================================" "Green"
    Write-ColorOutput "$InstanceType INFORMATION" "Green"
    Write-ColorOutput "URL: $($Info.Url)" "Green"
    Write-ColorOutput "================================================================================" "Green"
    
    # Show Quality Profiles
    Write-ColorOutput "`nQUALITY PROFILES:" "Cyan"
    Write-ColorOutput "----------------------------------------" "Cyan"
    foreach ($qualityProfile in $Info.Profiles) {
        Write-ColorOutput "  Name: $($qualityProfile.name) (ID: $($qualityProfile.id))" "White"
    }
    
    # Show Root Folders
    Write-ColorOutput "`nROOT FOLDERS:" "Cyan"
    Write-ColorOutput "----------------------------------------" "Cyan"
    foreach ($folder in $Info.RootFolders) {
        Write-ColorOutput "  Path: $($folder.path) (ID: $($folder.id))" "White"
    }
    
    Write-ColorOutput "`n" "White"
}

# Main execution
try {
    Write-ColorOutput "CompleteARR Fetch Info Tool" "Green"
    Write-ColorOutput "==================================================" "Green"
    Write-ColorOutput "This tool helps configure CompleteARR scripts" "White"
    Write-ColorOutput "by fetching information from Sonarr and Radarr" "White"
    Write-ColorOutput "==================================================" "Green"
    
    # Check for required module
    if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
        Write-ColorOutput "ERROR: powershell-yaml module is required." "Red"
        Write-ColorOutput "Install it with: Install-Module -Name powershell-yaml" "Yellow"
        return
    }
    
    Import-Module powershell-yaml -ErrorAction Stop
    
    if ($ShowSonarr) {
        $sonarrConfig = Join-Path $ProjectRoot 'CompleteARR_Settings\CompleteARR_SONARR_Settings.yml'
        $sonarrInfo = Get-ArrInfo -ConfigPath $sonarrConfig -InstanceType "Sonarr"
        Show-ArrInfo -InstanceType "SONARR" -Info $sonarrInfo
    }
    
    if ($ShowRadarr) {
        $radarrConfig = Join-Path $ProjectRoot 'CompleteARR_Settings\CompleteARR_RADARR_Settings.yml'
        $radarrInfo = Get-ArrInfo -ConfigPath $radarrConfig -InstanceType "Radarr"
        Show-ArrInfo -InstanceType "RADARR" -Info $radarrInfo
    }
    
    Write-ColorOutput "`nNEXT STEPS:" "Yellow"
    Write-ColorOutput "1. Use the information above to configure your settings files" "White"
    Write-ColorOutput "2. Run the launchers to run the scripts" "White"
}
catch {
    Write-ColorOutput "FATAL ERROR: $($_.Exception.Message)" "Red"
    Write-ColorOutput "Stack trace: $($_.ScriptStackTrace)" "Yellow"
}
