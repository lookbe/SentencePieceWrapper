@echo off
setlocal

:: Copies SentencePieceWrapper.dll (+ PDB) into tobe-said-win\NativeLibs\<Config>\
:: (the "jniLibs" of the Windows app). Usage: copy_dll.bat [Debug|RelWithDebInfo] (default: both)

set BUILD_DIR=%~dp0build_win
set DEST_ROOT=%~dp0..\tobe-said-win\NativeLibs
set CONFIGS=Debug RelWithDebInfo
if not "%~1"=="" set CONFIGS=%~1
set COPIED=0

for %%C in (%CONFIGS%) do call :copy_cfg %%C
if "%COPIED%"=="0" (
    echo Error: nothing copied -- run build_win.bat first.
    exit /b 1
)
echo Done!
endlocal
exit /b 0

:copy_cfg
set SRC=%BUILD_DIR%\%1
set DEST=%DEST_ROOT%\%1
if not exist "%SRC%\SentencePieceWrapper.dll" (
    echo [skip] %1: %SRC%\SentencePieceWrapper.dll not found
    exit /b 0
)
if not exist "%DEST%" mkdir "%DEST%"
echo Copying SentencePieceWrapper [%1] to %DEST%
copy /Y "%SRC%\SentencePieceWrapper.dll" "%DEST%\" >nul
if exist "%SRC%\SentencePieceWrapper.pdb" copy /Y "%SRC%\SentencePieceWrapper.pdb" "%DEST%\" >nul
set COPIED=1
exit /b 0
