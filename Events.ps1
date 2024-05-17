# Determine the path of the currently running script and set the working directory to that path
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [Alias("n")]
    [string]$scriptName
)
$path = (Split-Path $MyInvocation.MyCommand.Path -Parent)
Set-Location $path
. .\Helpers.ps1 -n $scriptName

# Load settings from a JSON file located in the same directory as the script
$settings = Get-Settings

# Initialize a script scoped dictionary to store variables.
# This dictionary is used to pass parameters to functions that might not have direct access to script scope, like background jobs.
if (-not $script:arguments) {
    $script:arguments = @{}
}

# Function to execute at the start of a stream
function OnStreamStart() {
    $script:arguments["OldLimit"] = Apply-Limit -configFilePath $settings.RTSSConfigPath -newLimit $env:SUNSHINE_CLIENT_FPS
}


# Function to execute at the end of a stream. This function is called in a background job,
# and hence doesn't have direct access to the script scope. $kwargs is passed explicitly to emulate script:arguments.
function OnStreamEnd($kwargs) {
    Apply-Limit -configFilePath $settings.RTSSConfigPath -newLimit $kwargs["OldLimit"]
    return $true
}


function Set-Limit {
    param (
        [string]$configFilePath,
        [int]$newLimit
    )

    # Check if the file exists
    if (Test-Path $configFilePath) {
        # Read the entire content of the file
        $configContent = Get-Content $configFilePath -Raw

        # Capture the old limit first, before replacing
        $oldLimit = 0
        if ($configContent -match 'Limit=(\d+)') {
            $oldLimit = [int]$Matches[1]
        } else {
            Write-Output "No existing frame limit found in the config file, assuming it is unlimited."
            return 0
        }

        # Find and replace the line that sets the frame rate limit
        $configContent = $configContent -replace 'Limit=\d+', "Limit=$newLimit"

        # Write the updated content back to the file
        Set-Content $configFilePath -Value $configContent

        Write-Output "Frame rate limit updated to $newLimit in $configFilePath."
        return $oldLimit
    } else {
        Write-Output "Global file not found at $configFilePath, please correct the path in settings.json."
        return $null
    }
}
