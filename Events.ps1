# Determine the path of the currently running script and set the working directory to that path
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path

# Load your helper functions
. .\Helpers.ps1 -n $scriptName

# Load settings from a JSON file located in the same directory as the script
$settings = Get-Settings

# Initialize a script-scoped dictionary to store variables.
# This dictionary is used to pass parameters to functions that might not have direct access to script scope, like background jobs.
if (-not $script:arguments) {
    $script:arguments = @{}
}


# Function to execute at the start of a stream
function OnStreamStart {
    # Load RTSS type helpers
    . .\RTSSType.ps1 -rtssInstallPath $settings.RTSSInstallPath

    # ---------------------------------------------------------------------
    # 1. Grab FPS from env‑vars and normalise decimal separator
    # ---------------------------------------------------------------------
    $fpsRaw = $env:APOLLO_CLIENT_FPS
    if (-not $fpsRaw) { $fpsRaw = $env:SUNSHINE_CLIENT_FPS }
    if (-not $fpsRaw) { throw "No FPS environment variable set." }

    $normalizedFpsRaw = $fpsRaw -replace ',', '.'
    if (-not ($normalizedFpsRaw -match '^[0-9]+(\.[0-9]+)?$')) {
        throw "Invalid FPS value: $fpsRaw"
    }
    $fps = [double]$normalizedFpsRaw

    # ---------------------------------------------------------------------
    # 2. Compute denominator & integer numerator expected by RTSS
    # ---------------------------------------------------------------------
    $currentDenominator = 1
    if ($normalizedFpsRaw -like '*.*') {
        $fractionPart      = ($normalizedFpsRaw -split '\.')[1]
        $currentDenominator = [math]::Pow(10, $fractionPart.Length)
    }
    $scaledLimit = [math]::Round($fps * $currentDenominator)

    # ---------------------------------------------------------------------
    # 3. Switch denominator on disk (if needed) and remember the original
    # ---------------------------------------------------------------------
    $originalDenominator = if ($currentDenominator -gt 1) {
        Set-LimitDenominator -newDenominator $currentDenominator
    } else { 1 }

    # ---------------------------------------------------------------------
    # 4. Push new framerate limit via RTSS API, recording the previous value
    # ---------------------------------------------------------------------
    $originalLimit = Set-Limit `
        -newLimit           $scaledLimit `
        -currentDenominator $currentDenominator `
        -oldDenominator     $originalDenominator

    # ---------------------------------------------------------------------
    # 0. Set SyncLimiter property from settings
    # ---------------------------------------------------------------------
    $syncLimiterValue = Get-SyncLimiterValue -type $settings.frame_limit_type
    $originalSyncLimiter = Set-SyncLimiter -value $syncLimiterValue
    $script:arguments["OriginalSyncLimiter"] = $originalSyncLimiter

    # ---------------------------------------------------------------------
    # 5. Stash state for OnStreamEnd
    # ---------------------------------------------------------------------
    $script:arguments["OriginalLimit"]      = $originalLimit
    $script:arguments["OriginalDenominator"] = $originalDenominator
    $script:arguments["CurrentDenominator"]  = $currentDenominator
    $script:arguments["RTSSInstallPath"]     = $settings.RTSSInstallPath
}


function OnStreamEnd {
    param($kwargs)
    . .\RTSSType.ps1 -rtssInstallPath $kwargs["RTSSInstallPath"]

    # Restore SyncLimiter
    if ($null -ne $kwargs["OriginalSyncLimiter"]) {
        Set-SyncLimiter -value $kwargs["OriginalSyncLimiter"] | Out-Null
    }

    # 1. Restore the original denominator in the config file
    if ($null -ne $kwargs["OriginalDenominator"]) {
        Set-LimitDenominator -newDenominator $kwargs["OriginalDenominator"] | Out-Null
    }

    # 2. Restore the original frame‑limit (console message reflects both bases)
    Set-Limit `
        -newLimit           $kwargs["OriginalLimit"] `
        -currentDenominator $kwargs["OriginalDenominator"] `
        -oldDenominator     $kwargs["CurrentDenominator"] | Out-Null

    return $true
}


function Set-Limit {
    param(
        [Parameter(Mandatory)][int]$newLimit,
        [int]$currentDenominator = 1,
        [int]$oldDenominator     = $currentDenominator  # optional override
    )

    $profileName = ""  # empty → global profile
    $ptr         = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)

    try {
        [RTSS]::LoadProfile($profileName)

        # Fetch previous raw value
        $gotOld   = [RTSS]::GetProfileProperty("FramerateLimit", $ptr, 4)
        $oldLimit = if ($gotOld) {
            [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr)
        } else { 0 }

        # Write the new raw value
        [System.Runtime.InteropServices.Marshal]::WriteInt32($ptr, $newLimit)
        [RTSS]::SetProfileProperty("FramerateLimit", $ptr, 4) | Out-Null

        [RTSS]::SaveProfile($profileName)
        [RTSS]::UpdateProfiles()

        # -------------------------------------------------------------
        # Console output (culture‑independent)
        # -------------------------------------------------------------
        $ci = [CultureInfo]::InvariantCulture
        $fmtNew = if ($currentDenominator -gt 1) { ($newLimit / $currentDenominator).ToString($ci) } else { $newLimit }
        $fmtOld = if ($oldDenominator     -gt 1) { ($oldLimit / $oldDenominator).ToString($ci) } else { $oldLimit }

        Write-Host "RTSS frame rate limit set to $fmtNew fps (old limit was $fmtOld fps)."
        return $oldLimit  # raw value so the caller can decide how to format later
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}

function Set-LimitDenominator {
    param([Parameter(Mandatory)][int]$newDenominator)

    $configFilePath = Join-Path $settings.RTSSInstallPath "Profiles/Global"
    if (-not (Test-Path $configFilePath)) {
        Write-Host "Global profile not found at $configFilePath - check settings.json."
        return $null
    }

    $content        = Get-Content $configFilePath -Raw
    $oldDenominator = if ($content -match 'LimitDenominator=(\d+)') { [int]$Matches[1] } else { 1 }

    $content = $content -replace 'LimitDenominator=\d+', "LimitDenominator=$newDenominator"
    Set-Content $configFilePath -Value $content

    Write-Host "Frame rate denominator updated from $oldDenominator to $newDenominator."
    return $oldDenominator
}

# Function to map frame_limit_type to SyncLimiter value
function Get-SyncLimiterValue {
    param([string]$type)
    switch ($type.ToLower()) {
        'async'             { return 0 }
        'front edge sync'   { return 1 }
        'back edge sync'    { return 2 }
        'nvidia reflex'     { return 3 }
        default             { throw "Unknown frame_limit_type: $type" }
    }
}

# Function to set SyncLimiter property via RTSS hooks
function Set-SyncLimiter {
    param(
        [Parameter(Mandatory)][int]$value
    )
    $profileName = ""  # global profile
    $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)
    try {
        [RTSS]::LoadProfile($profileName)
        # Fetch previous value
        $gotOld = [RTSS]::GetProfileProperty("SyncLimiter", $ptr, 4)
        $oldValue = if ($gotOld) {
            [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr)
        } else { 0 }
        # Write new value
        [System.Runtime.InteropServices.Marshal]::WriteInt32($ptr, $value)
        [RTSS]::SetProfileProperty("SyncLimiter", $ptr, 4) | Out-Null
        [RTSS]::SaveProfile($profileName)
        [RTSS]::UpdateProfiles()
        Write-Host "RTSS SyncLimiter set to $value (old value was $oldValue)."
        return $oldValue
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}
