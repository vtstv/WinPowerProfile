@echo off
REM Copyright (c) 2025 Murr (https://github.com/vtstv)
REM Licensed under MIT License

REM PowerProfile Launcher - Run PowerShell script as Administrator

cd /d "%~dp0"

REM Check if -toggle parameter is provided
if /i "%~1"=="-toggle" (
    REM Create a flag file to signal toggle mode
    echo toggle > "%TEMP%\PowerProfile_ToggleMode.flag"
    powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoProfile -File \"%~dp0PowerProfile.ps1\"' -Verb RunAs"
) else (
    powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoExit -File \"%~dp0PowerProfile.ps1\"' -Verb RunAs"
)
