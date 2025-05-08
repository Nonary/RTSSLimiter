
param(
    [Parameter(Mandatory = $true)]
    [string]$rtssInstallPath
)


$env:Path = "$rtssInstallPath;$env:Path"


if (-not ("RTSS" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class RTSS
{
    [DllImport("RTSSHooks64.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Ansi)]
    public static extern bool SetProfileProperty(string name, IntPtr data, uint size);

    [DllImport("RTSSHooks64.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Ansi)]
    public static extern bool GetProfileProperty(string name, IntPtr data, uint size);

    [DllImport("RTSSHooks64.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Ansi)]
    public static extern void LoadProfile(string profile);

    [DllImport("RTSSHooks64.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Ansi)]
    public static extern void SaveProfile(string profile);

    [DllImport("RTSSHooks64.dll", CallingConvention = CallingConvention.StdCall)]
    public static extern void UpdateProfiles();
}
"@
}