' Privacy Screen - Silent launcher (fallback, prefer silent-launch.exe)
Option Explicit
Dim fso, sh, dir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\privacy-screen.ps1"" -HideConsole"
sh.Run cmd, 0, False
