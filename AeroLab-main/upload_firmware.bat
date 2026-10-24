@echo off
title AeroLab ESP32 Firmware Flasher
echo =======================================================
echo   Flashing ESP32 Flight Control and Digital Twin Firmware
echo   Target: Auto-Detect USB Serial ^| Baud: 921600
echo =======================================================
echo.
echo NOTE: Make sure dashboard.html is CLOSED or Disconnected so COM port is free!
echo.
cd /d "%~dp0"
set "PIO=%USERPROFILE%\.platformio\penv\Scripts\platformio.exe"
if not exist "%PIO%" set "PIO=pio"
"%PIO%" run -e esp32doit-devkit-v1 -t upload -d "%~dp0."
echo.
if %ERRORLEVEL% EQU 0 (
    echo =======================================================
    echo   SUCCESS! Firmware uploaded successfully.
    echo   Watch the physical boot test:
    echo   - Damper Servo sweeps: 0 -^> 180 -^> 90 degrees
    echo   - Buzzer plays gentle whisper ready chime
    echo   - Status LEDs switch: Red -^> Yellow -^> Green
    echo   - OLED displays: "UAV AVIONICS TESTBED"
    echo   Now open dashboard.html or dashboard_analytics.html!
    echo =======================================================
) else (
    echo.
    echo FAILED: Make sure the ESP32 is plugged into USB and any open dashboard/monitor is closed!
)
pause
