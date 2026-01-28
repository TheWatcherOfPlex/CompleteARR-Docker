#Requires -Version 7.0
<#
    ############################################################
    # CompleteARR_RADARR_FilmEngine.ps1
    #
    # 🎯 MAIN ENGINE FOR CompleteARR RADARR
    #
    # This is the core script that manages your movie organization.
    #
    # 🔧 WHAT IT DOES:
    #   - Loads your CompleteARR RADARR settings
    #   - Connects to your Radarr server
    #   - Enforces profile-to-root folder mapping for movies
    #   - Ensures movies are in the correct folders based on their quality profiles
    #
    # 📊 PERFORMANCE NOTE:
    #   This script checks movies for profile/root folder consistency.
    #   If you have a very large library (5,000+ movies), this can be slow.
    #   Consider increasing the 'throttleMs' setting in your config to avoid
    #   overwhelming your Radarr server with too many API calls at once.
    #
    # 🚀 USAGE:
    #   Usually run by CompleteARR_RADARR_Launcher.ps1, but you can also run it directly:
    #   pwsh .\CompleteARR_Scripts\CompleteARR_RADARR_FilmEngine.ps1 -ConfigPath 'X:\Path\CompleteARR_RADARR_Settings.yml'
    #
    ############################################################
#>

[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# INTERNAL GLOBALS
# ------------------------------------------------------------

# Determine CompleteARR root folder (one level above the Scripts folder this engine lives in).
$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptDir  = Split-Path -Path $thisScriptPath -Parent
$Script:CompleteARR_ScriptRoot = Split-Path -Path $thisScriptDir -Parent

$Global:CompleteARR_Config      = $null
$Global:CompleteARR_LogFilePath = $null
$Global:CompleteARR_LogMinLevel = 'Info'
$Global:CompleteARR_LogToFile   = $true
$Global:CompleteARR_LogToConsole= $true
$Global:CompleteARR_UseColors   = $true
$Global:CompleteARR_ThrottleMs  = 200
$Global:CompleteARR_Behavior    = $null
$Global:CompleteARR_MoveVerification = $null

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "ERROR: powershell-yaml module is required." -ForegroundColor Red
    Write-Host "Install it with: Install-Module -Name powershell-yaml" -ForegroundColor Yellow
    throw "Missing powershell-yaml module"
}

Import-Module powershell-yaml -ErrorAction Stop

$Global:CompleteARR_Summary = [PSCustomObject]@{
    MoviesChecked               = 0
    MoviesSkipped               = 0
    MoviesAlreadyCorrect        = 0
    RootCorrections             = 0
    Errors                      = 0
}

# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

# Log level rank mapping (0=lowest, 6=highest)
$logLevelRanks = @{
    'TRACE'   = 0
    'DEBUG'   = 1
    'INFO'    = 2
    'WARNING' = 3
    'ERROR'   = 4
    'SUCCESS' = 5
    'FILE'    = 6
}

# Log level color mapping
$logLevelColors = @{
    'TRACE'   = 'DarkGray'
    'DEBUG'   = 'Gray'
    'INFO'    = 'Cyan'
    'WARNING' = 'Yellow'
    'ERROR'   = 'Red'
    'SUCCESS' = 'Green'
    'FILE'    = 'Magenta'
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Message,
        [string]$HighlightText = $null,
        [string]$HighlightColor = 'Green'
    )

    $levelUpper = $Level.ToUpperInvariant()
    $minRank    = $logLevelRanks[$Global:CompleteARR_LogMinLevel.ToUpperInvariant()]
    $thisRank   = $logLevelRanks[$levelUpper]
    if ($thisRank -lt $minRank) { return }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line      = "[{0}] [{1}] {2}" -f $timestamp, $levelUpper, $Message

    # Always write to console (color-coded)
    if ($Global:CompleteARR_UseColors) {
        $baseColor = $logLevelColors[$levelUpper]
        if (-not $baseColor) { $baseColor = $Host.UI.RawUI.ForegroundColor }

        if ($HighlightText -and $Message -match [regex]::Escape($HighlightText)) {
            # Write timestamp and level prefix
            Write-Host "[$timestamp] [$levelUpper] " -NoNewline -ForegroundColor $baseColor
            # Split the message and write with different colors
            $parts = [regex]::Split($Message, "($([regex]::Escape($HighlightText)))", "IgnoreCase")
            foreach ($part in $parts) {
                if ($part -eq $HighlightText) {
                    Write-Host $part -NoNewline -ForegroundColor $HighlightColor
                } else {
                    Write-Host $part -NoNewline -ForegroundColor $baseColor
                }
            }
            Write-Host ""  # New line
        } else {
            Write-Host $line -ForegroundColor $baseColor
        }
    } else {
        Write-Host $line
    }

    # File logging still respects logToFile + path
    if ($Global:CompleteARR_LogToFile -and $Global:CompleteARR_LogFilePath) {
        Add-Content -Path $Global:CompleteARR_LogFilePath -Value $line
    }
}


function Import-CompleteARRConfig {
    param([string]$Path)

    if (-not $Path) {
        $Path = Join-Path (Join-Path $Script:CompleteARR_ScriptRoot 'CompleteARR_Settings') 'CompleteARR_RADARR_Settings.yml'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log 'ERROR' "Config file not found: $Path"
        throw "Config file not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    $cfg = $raw | ConvertFrom-Yaml
    return ,@($cfg, $Path)
}

function Initialize-LoggingFromConfig {
    param(
        [pscustomobject]$Config,
        [string]$ConfigPath
    )

    $logging = $Config.logging

    $logFileName = $logging.logFileName
    if (-not $logFileName) { $logFileName = 'CompleteARR.log' }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HHmm')
    $ext       = [System.IO.Path]::GetExtension($logFileName)
    if (-not $ext) { $ext = '.log' }

    $logsRoot = Join-Path $Script:CompleteARR_ScriptRoot 'CompleteARR_Logs'
    if (-not (Test-Path -LiteralPath $logsRoot)) {
        New-Item -Path $logsRoot -ItemType Directory -Force | Out-Null
    }

    # Use script-specific name for log file
    $scriptName = "CompleteARR_RADARR_FilmEngine"
    $logFile = Join-Path $logsRoot ("{0}_{1}{2}" -f $scriptName, $timestamp, $ext)

    $Global:CompleteARR_LogFilePath  = $logFile
    $Global:CompleteARR_LogMinLevel  = if ($logging.minLevel) { $logging.minLevel } else { 'Info' }
    $Global:CompleteARR_LogToFile    = if ($null -ne $logging.logToFile) { $logging.logToFile } else { $true }
    $Global:CompleteARR_LogToConsole = if ($null -ne $logging.logToConsole) { $logging.logToConsole } else { $true }
    $Global:CompleteARR_UseColors    = if ($null -ne $logging.useColors) { $logging.useColors } else { $true }
    $Global:CompleteARR_ThrottleMs   = if ($null -ne $logging.throttleMs) { $logging.throttleMs } else { 200 }
    $Global:CompleteARR_Behavior     = $Config.behavior

    Write-Log 'FILE' ("Using configuration file: {0}" -f $ConfigPath)
    Write-Log 'FILE' ("Log file: {0}" -f $logFile)
}


# ------------------------------------------------------------
# RADARR API HELPERS
# ------------------------------------------------------------

function Invoke-RadarrApi {
    <#
        Generic Radarr API wrapper.

        - $Path is a relative path like "system/status" or "movie"
          (we automatically prepend "api/v3/" unless you already did).
        - $Query is a hashtable of query string parameters.
        - $Body is a PSObject that will be converted to JSON for POST/PUT.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('GET','POST','PUT','DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Query = $null,
        [object]$Body = $null,
        [string]$ErrorContext = ''
    )

    $baseUrl = $Global:CompleteARR_Config.radarr.url
    if (-not $baseUrl) {
        throw "Radarr base URL not configured (radarr.url in YAML)."
    }
    $baseUrl = $baseUrl.TrimEnd('/')

    # If the path is a full URL, use it directly.
    if ($Path -match '^https?://') {
        $uri = $Path
    }
    else {
        $pathPart = $Path.TrimStart('/')

        if (-not $pathPart.ToLower().StartsWith('api/')) {
            $pathPart = "api/v3/$pathPart"
        }

        $uri = "$baseUrl/$pathPart"
    }

    # Append query string correctly: use "?" if none yet, otherwise "&"
    if ($Query -and $Query.Count -gt 0) {
        $qsPairs = @()
        foreach ($kv in $Query.GetEnumerator()) {
            $k = [uri]::EscapeDataString([string]$kv.Key)
            $v = [uri]::EscapeDataString([string]$kv.Value)
            $qsPairs += "$k=$v"
        }
        $qs  = $qsPairs -join '&'
        if ($uri.Contains('?')) { $sep = '&' } else { $sep = '?' }
        $uri = "$uri$sep$qs"
    }

    Write-Log 'DEBUG' "RADARR $Method $uri"

    $headers = @{
        'X-Api-Key' = $Global:CompleteARR_Config.radarr.apiKey
    }

    $invokeParams = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $invokeParams['ContentType'] = 'application/json'
        $invokeParams['Body']        = ($Body | ConvertTo-Json -Depth 10)
    }

    try {
        if ($Global:CompleteARR_ThrottleMs -gt 0) {
            Start-Sleep -Milliseconds $Global:CompleteARR_ThrottleMs
        }
        return Invoke-RestMethod @invokeParams
    }
    catch {
        $ctx = if ($ErrorContext) { $ErrorContext } else { "$Method $Path" }
        Write-Log 'ERROR' ("Radarr API error ({0}): {1}" -f $ctx, $_.Exception.Message)
        throw
    }
}

function Get-RadarrSystemStatus {
    return Invoke-RadarrApi -Method 'GET' -Path 'system/status' -ErrorContext 'system/status'
}

function Get-RadarrQualityProfiles {
    return Invoke-RadarrApi -Method 'GET' -Path 'qualityprofile' -ErrorContext 'qualityprofile'
}

function Get-RadarrMovies {
    return Invoke-RadarrApi -Method 'GET' -Path 'movie' -ErrorContext 'movie'
}

function Update-RadarrMovie {
    param(
        [pscustomobject]$Movie,
        [string]$Context,
        [bool]$MoveFiles = $true
    )

    if ($Global:CompleteARR_Behavior.dryRun) {
        Write-Log 'FILE' ("[DRY RUN] Would PUT movie/{0} ({1})" -f $Movie.id, $Context)
        return
    }

    $path  = "movie/{0}" -f $Movie.id
    $query = @{ moveFiles = ($MoveFiles ? 'true' : 'false') }

    Write-Log 'DEBUG' ("RADARR PUT api/v3/{0}?moveFiles={1}" -f $path, $query.moveFiles)
    $null = Invoke-RadarrApi -Method 'PUT' -Path $path -Query $query -Body $Movie -ErrorContext $Context
}

function Get-RadarrMovieById {
    param(
        [int]$MovieId
    )

    return Invoke-RadarrApi -Method 'GET' -Path ("movie/{0}" -f $MovieId) -ErrorContext ("movie/{0}" -f $MovieId)
}

function Test-MovieMoveCompleted {
    param(
        [pscustomobject]$Movie,
        [string]$ExpectedPath,
        [pscustomobject]$MoveConfig
    )

    $mode = ($MoveConfig.MoveVerifyMode ?? 'radarr').ToLowerInvariant()
    $expectedNormalized = $ExpectedPath.TrimEnd('/')

    $radarrOk = $false
    $fsOk = $false

    if ($mode -eq 'radarr' -or $mode -eq 'both') {
        $movieFresh = Get-RadarrMovieById -MovieId $Movie.id
        if ($movieFresh -and $movieFresh.path) {
            $radarrPath = $movieFresh.path.TrimEnd('/')
            $radarrOk = ($radarrPath -eq $expectedNormalized)
        }
    } else {
        $radarrOk = $true
    }

    if ($mode -eq 'filesystem' -or $mode -eq 'both') {
        try {
            $fsOk = Test-Path -LiteralPath $ExpectedPath
        } catch {
            $fsOk = $false
        }
    } else {
        $fsOk = $true
    }

    return ($radarrOk -and $fsOk)
}

function Invoke-MovieMoveWithVerification {
    param(
        [pscustomobject]$Movie,
        [string]$OldPath,
        [string]$NewPath,
        [string]$Context
    )

    $moveConfig = $Global:CompleteARR_MoveVerification
    if (-not $moveConfig) {
        Update-RadarrMovie -Movie $Movie -Context $Context -MoveFiles:$true
        return $true
    }

    $verifyEnabled = [bool]($moveConfig.MoveVerifyEnabled ?? $true)
    $retries = [int]($moveConfig.MoveVerifyRetries ?? 3)
    $delaySeconds = [int]($moveConfig.MoveVerifyDelaySeconds ?? 5)
    $backoffSeconds = [int]($moveConfig.MoveVerifyBackoffSeconds ?? 2)
    $reattemptMove = [bool]($moveConfig.MoveVerifyReattemptMove ?? $true)
    $revertOnFailure = [bool]($moveConfig.MoveVerifyRevertOnFailure ?? $true)

    Update-RadarrMovie -Movie $Movie -Context $Context -MoveFiles:$true

    if (-not $verifyEnabled -or $Global:CompleteARR_Behavior.dryRun) {
        return $true
    }

    $attempt = 0
    $currentDelay = $delaySeconds
    while ($attempt -le $retries) {
        Start-Sleep -Seconds $currentDelay
        if (Test-MovieMoveCompleted -Movie $Movie -ExpectedPath $NewPath -MoveConfig $moveConfig) {
            Write-Log 'SUCCESS' ("Move verified for movie '{0}' (id={1})" -f $Movie.title, $Movie.id)
            return $true
        }

        if ($attempt -lt $retries -and $reattemptMove) {
            Write-Log 'WARNING' ("Move not verified for movie '{0}' (id={1}). Retrying move (attempt {2}/{3})" -f $Movie.title, $Movie.id, ($attempt + 1), $retries)
            Update-RadarrMovie -Movie $Movie -Context ("retry move for movie {0}" -f $Movie.id) -MoveFiles:$true
        }

        $attempt++
        $currentDelay += $backoffSeconds
    }

    Write-Log 'ERROR' ("Move verification failed for movie '{0}' (id={1}) after {2} attempts." -f $Movie.title, $Movie.id, ($retries + 1))

    if ($revertOnFailure -and $OldPath) {
        Write-Log 'WARNING' ("Reverting Radarr path for movie '{0}' to '{1}' to resync." -f $Movie.title, $OldPath)
        $Movie.path = $OldPath
        Update-RadarrMovie -Movie $Movie -Context ("revert path for movie {0}" -f $Movie.id) -MoveFiles:$false
    }

    $Global:CompleteARR_Summary.Errors++
    return $false
}

# ------------------------------------------------------------
# MOVIE LOGIC
# ------------------------------------------------------------

function Join-RadarrRootAndLeaf {
    param(
        [string]$RootFolder,
        [string]$Leaf
    )

    $root = $RootFolder.TrimEnd('/')
    if ([string]::IsNullOrWhiteSpace($Leaf)) {
        return $root
    }
    return "$root/$Leaf"
}

function Get-ExpectedRootForProfile {
    <#
        🎯 DETERMINES THE CORRECT ROOT FOLDER FOR A MOVIE BASED ON ITS PROFILE
        
        This function looks up the profile-to-root mapping from the configuration
        and returns the expected root folder for a given quality profile.
        
        Why this matters:
        - Movies should be organized by content type (Adult, Family, Anime, etc.)
        - Each quality profile corresponds to a specific root folder
        - This ensures consistent organization across your library
    #>
    param(
        [int]$ProfileId,
        [hashtable]$ProfilesById,
        [hashtable]$ProfileRootMappings
    )

    # Find the profile name for this ID (O(1) lookup)
    $profileName = $ProfilesById[$ProfileId]

    if (-not $profileName) {
        Write-Log 'DEBUG' ("Profile ID {0} not found in profiles list" -f $ProfileId)
        return $null
    }

    # Look up the root folder for this profile (hashtable format)
    if ($ProfileRootMappings.ContainsKey($profileName)) {
        return $ProfileRootMappings[$profileName]
    }

    Write-Log 'DEBUG' ("No root folder mapping found for profile '{0}'" -f $profileName)
    return $null
}

function Update-MoviePathInRoot {
    <#
        🗂️  ENSURES MOVIES ARE IN THE CORRECT FOLDERS
        
        This function checks if a movie is in the right root folder and fixes it if not.
        
        Why this happens:
        - Sometimes movies get moved manually or by other processes
        - File system changes might affect folder paths
        - This ensures consistency across your library
        
        What it does:
        - Checks if the movie's current path matches the expected root
        - If not, moves it to the correct location
        - Keeps the same folder name (just changes the parent path)
        
        💡 TIP: This is a safety feature that keeps your library organized!
    #>
    param(
        [pscustomobject]$Movie,
        [string]$ExpectedRoot
    )

    $expectedRoot = $ExpectedRoot.TrimEnd('/')
    $currentPath  = $Movie.path

    if (-not $currentPath) {
        return $false
    }

    if ($currentPath.StartsWith("$expectedRoot/")) {
        return $false
    }

    $leaf    = Split-Path -Path $currentPath -Leaf
    $newPath = Join-RadarrRootAndLeaf -RootFolder $expectedRoot -Leaf $leaf

    Write-Log 'FILE' ("Target root folder for movie path correction is: {0}" -f $expectedRoot)
    Write-Log 'SUCCESS' ("Movie '{0}' (id={1}) - ROOT CORRECTION: path '{2}' -> '{3}'" -f $Movie.title, $Movie.id, $currentPath, $newPath)

    $Movie.path = $newPath
    $Global:CompleteARR_Summary.RootCorrections++
    return $true
}

function Update-MovieLocation {
    <#
        🔄 UPDATES A SINGLE MOVIE FOR PROFILE/ROOT FOLDER CONSISTENCY
        
        This function ensures each movie is in the correct location based on its quality profile.
        
        What it checks:
        - Is the movie in the correct root folder for its profile?
        - If not, should we move it to the correct location?
        
        Configuration-driven:
        - Uses the profileRootMappings from the config file
        - Respects dryRun mode for testing
        - Handles errors gracefully
    #>
    param(
        [pscustomobject]$Movie,
        [hashtable]$ProfilesByName,
        [hashtable]$ProfilesById,
        [hashtable]$ProfileRootMappings
    )

    $Global:CompleteARR_Summary.MoviesChecked++

    try {
        # Get profile name for human-readable logging
        $profileId = [int]$Movie.qualityProfileId
        $profileName = $ProfilesById[$profileId]
        if (-not $profileName) {
            Write-Log 'WARNING' ("Movie '{0}' (id={1}) - Profile ID {2} not found in profiles list. Skipping." -f $Movie.title, $Movie.id, $profileId)
            $Global:CompleteARR_Summary.MoviesSkipped++
            return
        }

        $expectedRoot = Get-ExpectedRootForProfile -ProfileId $profileId -ProfilesById $ProfilesById -ProfileRootMappings $ProfileRootMappings
        
        if (-not $expectedRoot) {
            Write-Log 'WARNING' ("Movie '{0}' (id={1}) - No root folder mapping found for profile '{2}' (ID {3}). Skipping." -f $Movie.title, $Movie.id, $profileName, $profileId)
            $Global:CompleteARR_Summary.MoviesSkipped++
            return
        }

        $currentPath = $Movie.path
        if (-not $currentPath) {
            Write-Log 'WARNING' ("Movie '{0}' (id={1}) - No path configured. Skipping." -f $Movie.title, $Movie.id)
            $Global:CompleteARR_Summary.MoviesSkipped++
            return
        }

        # Check if movie is in the correct root folder
        if ($currentPath.StartsWith("$expectedRoot/")) {
            Write-Log 'DEBUG' ("Movie '{0}' (id={1}) - Already in correct root folder: {2}" -f $Movie.title, $Movie.id, $expectedRoot)
            $Global:CompleteARR_Summary.MoviesAlreadyCorrect++
            return
        }

        # Movie needs to be moved to correct root folder
        Write-Log 'INFO' ("Movie '{0}' (id={1}) - Needs root folder correction" -f $Movie.title, $Movie.id)
        
        $oldPath = $Movie.path
        $changed = Update-MoviePathInRoot -Movie $Movie -ExpectedRoot $expectedRoot
        if ($changed) {
            $moveOk = Invoke-MovieMoveWithVerification -Movie $Movie -OldPath $oldPath -NewPath $Movie.path -Context ("root correction for movie {0}" -f $Movie.id)
            if (-not $moveOk) {
                $Global:CompleteARR_Summary.MoviesSkipped++
            }
        }

    }
    catch {
        Write-Log 'ERROR' ("Error processing movie '{0}' (id={1}): {2}" -f $Movie.title, $Movie.id, $_.Exception.Message)
        $Global:CompleteARR_Summary.Errors++
    }
}

# ------------------------------------------------------------
# ENTRY POINT
# ------------------------------------------------------------

try {
    Write-Log 'INFO' ("CompleteARR RADARR engine starting. ScriptRoot = {0}" -f $Script:CompleteARR_ScriptRoot)

    $cfgAndPath = Import-CompleteARRConfig -Path $ConfigPath
    $config     = $cfgAndPath[0]
    $configPath = $cfgAndPath[1]
    $Global:CompleteARR_Config = $config

    Initialize-LoggingFromConfig -Config $config -ConfigPath $configPath

    $Global:CompleteARR_Behavior = $config.behavior
    $Global:CompleteARR_MoveVerification = $config.behavior.moveVerification

    $dryRun    = [bool]$Global:CompleteARR_Behavior.dryRun
    if ($null -ne $Global:CompleteARR_Behavior.preflightSeconds) {
        $preflight = [int]$Global:CompleteARR_Behavior.preflightSeconds
    } else {
        $preflight = 0
    }

    Write-Log 'DEBUG' ("Behavior: dryRun={0}, throttleMs={1}" -f $dryRun, $Global:CompleteARR_ThrottleMs)

    if ($preflight -gt 0) {
        Write-Log 'INFO' ("Preflight delay {0} seconds before starting work..." -f $preflight)
        Start-Sleep -Seconds $preflight
    }

    Write-Log 'INFO' "----- BEGIN CompleteARR RADARR run -----"

    # Connect to Radarr
    $status = Get-RadarrSystemStatus
    Write-Log 'SUCCESS' ("Connected to Radarr version {0} at {1}" -f $status.version, $config.radarr.url)

    # Load quality profiles
    $profiles = Get-RadarrQualityProfiles
    Write-Log 'DEBUG' ("Loaded {0} quality profiles from Radarr." -f $profiles.Count)

    $profilesByName = @{}
    $profilesById = @{}
    foreach ($p in $profiles) {
        $profilesByName[$p.name] = $p.id
        $profilesById[[int]$p.id] = $p.name
    }

    # Load all movies
    $allMovies = Get-RadarrMovies
    Write-Log 'DEBUG' ("Loaded {0} movies from Radarr." -f $allMovies.Count)

    # Get profile-to-root mappings from config
    $profileRootMappings = @{}
    if ($config.filmEngine -and $config.filmEngine.profileRootMappings) {
        $profileRootMappings = $config.filmEngine.profileRootMappings
    } else {
        Write-Log 'ERROR' "No profileRootMappings found in configuration. Please configure filmEngine.profileRootMappings in your settings file."
        throw "Missing profileRootMappings configuration"
    }

    Write-Log 'INFO' ("Processing {0} movies for profile/root folder consistency..." -f $allMovies.Count)

    # Process each movie with progress tracking
    $movieCount = $allMovies.Count
    $movieIndex = 0
    
    foreach ($movie in $allMovies) {
        $movieIndex++
        $progressLabel = "[{0}/{1}]" -f $movieIndex, $movieCount
        $progressMessage = "{0} Processing movie '{1}' (ID={2})" -f $progressLabel, $movie.title, $movie.id
        Write-Log 'INFO' $progressMessage -HighlightText $progressLabel -HighlightColor 'DarkMagenta'
        Update-MovieLocation -Movie $movie -ProfilesByName $profilesByName -ProfilesById $profilesById -ProfileRootMappings $profileRootMappings
    }

    # SUMMARY
    Write-Log 'INFO' "----- COMPLETEARR RADARR SUMMARY -----"
    Write-Log 'INFO' ("  Movies checked           : {0}" -f $Global:CompleteARR_Summary.MoviesChecked)
    Write-Log 'INFO' ("  Movies already correct   : {0}" -f $Global:CompleteARR_Summary.MoviesAlreadyCorrect)
    Write-Log 'INFO' ("  Movies skipped           : {0}" -f $Global:CompleteARR_Summary.MoviesSkipped)
    Write-Log 'INFO' ("  Root corrections         : {0}" -f $Global:CompleteARR_Summary.RootCorrections)
    Write-Log 'INFO' ("  Errors                   : {0}" -f $Global:CompleteARR_Summary.Errors)
    Write-Log 'INFO' "----- END CompleteARR RADARR run -----"
    
    # Return summary for master summary display
    return $Global:CompleteARR_Summary
}
catch {
    Write-Log 'ERROR' ("FATAL ERROR: {0}" -f $_.Exception.Message)
    Write-Log 'DEBUG' ("Stack trace:`n{0}" -f $_.ScriptStackTrace)
    throw
}
