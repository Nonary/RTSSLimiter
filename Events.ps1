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
    Write-Host "Stream started!"
    Write-Debug "Optional Debug Message"
    # Add a new key-value pair to the dictionary, demonstrating parameter storage for future retrieval
    $script:arguments.Add("Message", "This is an example of retrieving parameters in the future")
}

# Function to execute at the end of a stream. This function is called in a background job,
# and hence doesn't have direct access to the script scope. $kwargs is passed explicitly to emulate script:arguments.
function OnStreamEnd($kwargs) {
    Write-Host "Ending Stream!"
    # Access the script variable defined earlier via OnStreamStart()
    Write-Host $kwargs["Message"]
    Write-Debug "Optional Debug Message"
    # Always return a boolean here, that way the job knows it has been completed or not.
    return $true
}