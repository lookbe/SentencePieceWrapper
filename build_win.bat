@echo off
setlocal

:: Builds SentencePieceWrapper.dll as Debug AND RelWithDebInfo into build_win\<Config>\
:: (same build dir as build_windows.ps1, which only does Release and never wipes it).
:: Usage: build_win.bat [Debug|RelWithDebInfo]   (default: both). Then run copy_dll.bat.
:: First run fetches sentencepiece via CMake FetchContent (needs network).

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set BUILD_DIR=%SCRIPT_DIR%\build_win
set CMAKE="C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set CONFIGS=Debug RelWithDebInfo
if not "%~1"=="" set CONFIGS=%~1

echo --- Configuring SentencePieceWrapper ---
%CMAKE% -S "%SCRIPT_DIR%" -B "%BUILD_DIR%" -A x64
if %errorlevel% neq 0 exit /b %errorlevel%

for %%C in (%CONFIGS%) do (
    echo --- Building SentencePieceWrapper [%%C] ---
    %CMAKE% --build "%BUILD_DIR%" --config %%C
    if errorlevel 1 exit /b 1
)

echo --- Build Successful. Now run copy_dll.bat ---
endlocal
