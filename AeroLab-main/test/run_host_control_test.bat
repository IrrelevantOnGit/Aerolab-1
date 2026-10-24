@echo off
setlocal
where g++ >nul 2>nul
if errorlevel 1 (
  echo g++ not found. Install MinGW-w64 or use the ESP32 PlatformIO build.
  exit /b 2
)
g++ -std=c++17 -Wall -Wextra -I. test\host_control_test.cpp -o "%TEMP%\aerolab_host_control_test.exe"
if errorlevel 1 exit /b %errorlevel%
"%TEMP%\aerolab_host_control_test.exe"
set "RESULT=%ERRORLEVEL%"
del "%TEMP%\aerolab_host_control_test.exe"
exit /b %RESULT%
