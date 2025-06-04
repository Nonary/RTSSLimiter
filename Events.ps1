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
    . .\RTSSType.ps1 -rtssInstallPath $settings.RTSSInstallPath

    $frameLimitRaw = $env:SUNSHINE_CLIENT_FPS

    $frameLimit = $frameLimitRaw -as [int]

    
    if($frameLimit -ge 1000){
        $script:arguments["OldLimitDenominator"] = Set-LimitDenominator -configFilePath $settings.RTSSConfigFilePath -newDenominator 100
    }
    
    $script:arguments["OldLimit"] = Set-Limit -newLimit $frameLimit
    
    $script:arguments["RTSSInstallPath"] = $settings.RTSSInstallPath
}

# Function to execute at the end of a stream. This function is called in a background job,
# and hence doesn't have direct access to the script scope. $kwargs is passed explicitly to emulate script:arguments.
function OnStreamEnd {
    param($kwargs)
    . .\RTSSType.ps1 -rtssInstallPath $kwargs["RTSSInstallPath"]
    if($null -ne $kwargs["OldLimitDenominator"]) {
        Set-LimitDenominator -configFilePath $settings.RTSSConfigFilePath -newDenominator $kwargs["OldLimitDenominator"]
    }
    Set-Limit -configFilePath -newLimit $kwargs["OldLimit"]
    return $true
}

function Set-Limit {
    param (
        [int]$newLimit
    )

    $profileName = ""  # empty = global profile

    # Allocate unmanaged memory for a 32-bit integer
    $ptr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)

    try {
        # Load the target profile (global or per-game)
        [RTSS]::LoadProfile($profileName)

        # Read the existing limit
        $gotOld = [RTSS]::GetProfileProperty("FramerateLimit", $ptr, 4)
        $oldLimit = if ($gotOld) {
            [System.Runtime.InteropServices.Marshal]::ReadInt32($ptr)
        } else {
            Write-Host "Warning: could not read existing frame limit; assuming 0."
            0
        }

        # Write the new limit value into the same buffer
        [System.Runtime.InteropServices.Marshal]::WriteInt32($ptr, $newLimit)
        [RTSS]::SetProfileProperty("FramerateLimit", $ptr, 4) | Out-Null

        # Persist the change and notify running games
        [RTSS]::SaveProfile($profileName)
        [RTSS]::UpdateProfiles()

        $formattedLimit = if ($newLimit -ge 1000) { $newLimit / 100 } else { $newLimit }
        $formattedOldLimit = if ($oldLimit -ge 1000) { $oldLimit / 100 } else { $oldLimit }

        Write-Host "RTSS frame rate limit set to $formattedLimit fps (old limit was $formattedOldLimit fps)."
        return $oldLimit
    }
    finally {
        # Always free the unmanaged memory
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}

function Set-LimitDenominator {
    param (
        [int]$newDenominator
    )

    $settings = Get-Settings
    $configFilePath = Join-Path $settings.RTSSInstallPath "Profiles/Global"


    # Check if the file exists
    if (Test-Path $configFilePath) {
        # Read the entire content of the file
        $configContent = Get-Content $configFilePath -Raw

        # Capture the old denominator first, before replacing
        $oldDenominator = 0
        if ($configContent -match 'LimitDenominator=(\d+)') {
            $oldDenominator = [int]$Matches[1]
        } else {
            Write-Host "No existing LimitDenominator found in the config file."
            return 0
        }

        # Find and replace the line that sets the denominator
        $configContent = $configContent -replace 'LimitDenominator=\d+', "LimitDenominator=$newDenominator"

        # Write the updated content back to the file
        Set-Content $configFilePath -Value $configContent

        Write-Host "Frame rate denominator updated from $oldDenominator to $newDenominator."
        return $oldDenominator
    } else {
        Write-Host "Global file not found at $configFilePath, please correct the path in settings.json."
        return $null
    }
}

