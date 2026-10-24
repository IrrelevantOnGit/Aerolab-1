@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
cl.exe /std:c++17 /EHsc /I. test\host_control_test.cpp /Fe:test\host_control_test.exe
if errorlevel 1 exit /b 1
test\host_control_test.exe
