# Determine the path of the currently running script and set the working directory to that path
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path

# Load settings from a JSON file located in the same directory as the script
$settings = Get-Settings

# Load your helper functions
. .\Helpers.ps1 -n $scriptName

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
        $frameLimit = $frameLimit / 1000
    }
    
    $script:arguments["OldLimit"] = Set-Limit -newLimit $frameLimit
    $script:arguments["RTSSInstallPath"] = $settings.RTSSInstallPath
}

# Function to execute at the end of a stream. This function is called in a background job,
# and hence doesn't have direct access to the script scope. $kwargs is passed explicitly to emulate script:arguments.
function OnStreamEnd {
    param($kwargs)
    . .\RTSSType.ps1 -rtssInstallPath $kwargs["RTSSInstallPath"]
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

        Write-Host "RTSS frame rate limit set to $newLimit fps (old limit was $oldLimit fps)."
        return $oldLimit
    }
    finally {
        # Always free the unmanaged memory
        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($ptr)
    }
}
