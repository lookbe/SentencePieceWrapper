@echo off
setlocal

set ABI=arm64-v8a
set ROOT_DIR=%~dp0..

set BUILD_DIR=%~dp0build_android_%ABI%
set APP_JNILIBS=%ROOT_DIR%\android-tts-studio\composeApp\src\androidMain\jniLibs\%ABI%
set SYMBOLS_DIR=%ROOT_DIR%\native-debug-symbols\%ABI%
set UNSTRIPPED_SO=%BUILD_DIR%\libSentencePieceWrapper.so
set STRIPPED_SO=%BUILD_DIR%\stripped\libSentencePieceWrapper.so
set APP_SOURCE_SO=

echo --- Copying SentencePieceWrapper library for %ABI% ---

if not exist "%APP_JNILIBS%" mkdir "%APP_JNILIBS%"
if not exist "%SYMBOLS_DIR%" mkdir "%SYMBOLS_DIR%"

if exist "%STRIPPED_SO%" (
    set APP_SOURCE_SO=%STRIPPED_SO%
) else (
    if exist "%UNSTRIPPED_SO%" (
        echo Stripped .so not found. Using unstripped build output, Debug-friendly.
        set APP_SOURCE_SO=%UNSTRIPPED_SO%
    ) else (
        echo Error: No library found. Expected one of:
        echo   %STRIPPED_SO%
        echo   %UNSTRIPPED_SO%
        exit /b 1
    )
)

echo Copying App library...
copy /Y "%APP_SOURCE_SO%" "%APP_JNILIBS%\libSentencePieceWrapper.so"
if errorlevel 1 exit /b %errorlevel%

echo Copying Unstripped (Symbols) to native-debug-symbols...
copy /Y "%UNSTRIPPED_SO%" "%SYMBOLS_DIR%\libSentencePieceWrapper.so"
if errorlevel 1 exit /b %errorlevel%

echo Done!
endlocal
