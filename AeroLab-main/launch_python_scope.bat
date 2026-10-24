@echo off
title AeroLab Python Scope
cd /d "%~dp0"
set "PYTHON=C:\Users\manav\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"
rem Bridge is optional for direct USB/Wi-Fi mode and should be started once via start_bridge.bat.
rem Auto/bridge mode reconnects if no bridge is running; avoid spawning duplicate port-8088 owners.
start "AeroLab Python Scope" "%PYTHON%" python_realtime_scope.py %*
exit
