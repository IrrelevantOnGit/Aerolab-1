@echo off
title AeroLab Bridge
cd /d "%~dp0"
echo Starting bridge on http://127.0.0.1:8088 ...
python matlab_bridge.py
pause
