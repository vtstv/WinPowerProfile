@echo off
REM Copyright (c) 2025 Murr (https://github.com/vtstv)
REM Licensed under MIT License

REM PowerProfile Launcher - Run PowerShell script as Administrator

cd /d "%~dp0"

REM Request elevation and run the script
powershell.exe -Command "Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -NoExit -File \"%~dp0PowerProfile.ps1\"' -Verb RunAs"
