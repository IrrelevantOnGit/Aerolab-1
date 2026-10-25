@echo off
title AeroLab Live MATLAB Scope Launcher
cd /d "%~dp0"
set "MATLAB=C:\Program Files\MATLAB\R2025b\bin\matlab.exe"
if not exist "%MATLAB%" set "MATLAB=matlab"
set "PYTHON=C:\Users\manav\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PYTHON%" set "PYTHON=python"
rem Start the bridge once via start_bridge.bat when selecting bridge telemetry.
rem Do not spawn duplicate bridge processes from scope launchers.
start "AeroLab MATLAB Scope" "%MATLAB%" -nosplash -logfile "%~dp0matlab_scope_startup.log" -r "cd('%~dp0'); try, matlab_realtime_scope; catch ME, disp(getReport(ME,'extended')); fprintf(2,'SCOPE STARTUP FAILED: %%s\\n',ME.message); end;"
exit
