# build_android.ps1
param (
    [string]$NdkPath = "C:\Users\PC\AppData\Local\Android\Sdk\ndk\29.0.14206865",
    [string]$Abi = "arm64-v8a"
)

$CMakeBin = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$NinjaBin = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"

if (-not (Test-Path $NdkPath)) {
    Write-Error "NDK path not found: $NdkPath"
    exit 1
}

$BuildDir = "build_android_$Abi"

if (Test-Path $BuildDir) {
    Remove-Item -Path $BuildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildDir

& $CMakeBin -S . -B $BuildDir -G Ninja `
    -DCMAKE_MAKE_PROGRAM=$NinjaBin `
    -DCMAKE_TOOLCHAIN_FILE="$NdkPath/build/cmake/android.toolchain.cmake" `
    -DANDROID_ABI=$Abi `
    -DANDROID_PLATFORM=android-21 `
    -DANDROID_STL=c++_shared

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $CMakeBin --build $BuildDir

Write-Host "Build finished. Library should be in $BuildDir/libSentencePieceWrapper.so"
