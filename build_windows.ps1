# build_windows.ps1
$CMakePath = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
if ($env:PATH -notlike "*$CMakePath*") {
    $env:PATH = "$CMakePath;$env:PATH"
}

$BuildDir = "build_win"

if (!(Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir
}

cmake -S . -B $BuildDir -A x64
cmake --build $BuildDir --config Release

Write-Host "Build finished. DLL should be in $BuildDir/Release/SentencePieceWrapper.dll"
