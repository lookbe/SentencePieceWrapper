@echo off
setlocal

:: --- Configuration ---
set NDK_PATH=C:\Users\PC\AppData\Local\Android\Sdk\ndk\29.0.14206865
set ABI=arm64-v8a
set MIN_SDK=24
set BUILD_TYPE=Debug

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

set BUILD_DIR=%SCRIPT_DIR%\build_android_%ABI%
set TOOLCHAIN=%NDK_PATH%\build\cmake\android.toolchain.cmake
set MAKE_EXE=%NDK_PATH%\prebuilt\windows-x86_64\bin\make.exe

echo --- Building for Android (%ABI%, API %MIN_SDK%) ---
echo NDK Path: %NDK_PATH%
echo Make Path: %MAKE_EXE%

if not exist "%MAKE_EXE%" (
    echo Error: Make not found at %MAKE_EXE%
    exit /b 1
)

if exist "%BUILD_DIR%" rmdir /s /q "%BUILD_DIR%"
mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

:: Run CMake with Make from NDK
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" -G "Unix Makefiles" ^
    -DCMAKE_MAKE_PROGRAM="%MAKE_EXE%" ^
    -DCMAKE_TOOLCHAIN_FILE="%TOOLCHAIN%" ^
    -DANDROID_ABI=%ABI% ^
    -DANDROID_PLATFORM=android-%MIN_SDK% ^
    -DANDROID_STL=c++_shared ^
    -DCMAKE_BUILD_TYPE=%BUILD_TYPE% ^
    -DANDROID=ON ^
    -S "%SCRIPT_DIR%" -B "%BUILD_DIR%"

if %errorlevel% neq 0 (
    echo CMake configuration failed!
    exit /b %errorlevel%
)

:: Build
"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" --build . --config %BUILD_TYPE%
if %errorlevel% neq 0 (
    echo Build failed!
    exit /b %errorlevel%
)

echo --- Build Successful ---

set OUTPUT_SO=%BUILD_DIR%\libSentencePieceWrapper.so
set STRIP_EXE=%NDK_PATH%\toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-strip.exe

if "%BUILD_TYPE%"=="RelWithDebInfo" goto STRIP_IT
if "%BUILD_TYPE%"=="Release" goto STRIP_IT

:: If Debug:
echo Build is %BUILD_TYPE%, leaving unstripped.
echo Output: %OUTPUT_SO%
goto END

:STRIP_IT
echo Stripping library for %BUILD_TYPE%...
mkdir "%BUILD_DIR%\stripped" 2>nul
set STRIPPED_SO=%BUILD_DIR%\stripped\libpocket-tts-lib.so
copy "%OUTPUT_SO%" "%STRIPPED_SO%" >nul
"%STRIP_EXE%" --strip-all "%STRIPPED_SO%"

echo.
echo [Play Store Symbols]: %OUTPUT_SO%
echo [Stripped for App]  : %STRIPPED_SO%
echo.

:END
endlocal
