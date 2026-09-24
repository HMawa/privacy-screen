#requires -Version 5.1
<#
  Compile silent-launch.exe: a small GUI-subsystem launcher (no console window of its own)
  that starts privacy-screen.ps1 with CreateNoWindow, so no terminal window pops up
  even when Windows Terminal is the default terminal on Windows 11.

  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\build-launcher.ps1
  Pass args to main program: silent-launch.exe -Mode black   (args are forwarded as-is)
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$code = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

public static class PrivacyScreenLauncher
{
    [STAThread]
    public static void Main(string[] args)
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "privacy-screen.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("Cannot find privacy-screen.ps1. Place this launcher in the same directory.", "Privacy Screen",
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
            @"WindowsPowerShell\v1.0\powershell.exe");

        string extra = "";
        if (args != null && args.Length > 0) extra = " " + string.Join(" ", args);

        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = ps;
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\" -HideConsole" + extra;
        psi.WorkingDirectory = dir;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        Process.Start(psi);
    }
}
'@

$out = Join-Path $PSScriptRoot 'silent-launch.exe'
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition $code -OutputAssembly $out -OutputType WindowsApplication -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

if (Test-Path -LiteralPath $out) {
    Write-Host "OK: Generated $out"
} else {
    Write-Host 'Failed: exe not generated'
    exit 1
}
