SentencePieceWrapper

A lightweight SentencePiece wrapper for Unity Opus-MT.
This library provides a native bridge so Unity can run SentencePiece tokenization required by Opus-MT models.

🔧 Overview

SentencePieceWrapper exposes essential SentencePiece encode/decode functionality in a Unity-friendly way.

📦 Requirements

Before building this wrapper, you need to:

Download the official SentencePiece source
https://github.com/google/sentencepiece

Build the SentencePiece library in Release mode:

Build sentencepiece.lib

After building, place the files as follows:

```
/SentencePieceWrapper
 ├─ /lib
 │   └─ sentencepiece.lib
 ├─ /includes
 │   └─ sentencepiece_processor.h
 └─ CMakeLists.txt
```

Make sure the includes folder contains all required header files from the official SentencePiece build.

🛠️ Building SentencePieceWrapper (CMake)

Once your lib and includes directories are set up:

```
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

The output native plugin (e.g., .dll on Windows) will appear inside the build output directory.
You can then place the produced plugin inside your Unity project's Plugins folder.

📘 Notes

This wrapper currently targets Windows.

You must build SentencePiece yourself—no prebuilt binaries are included.

Compatible with Opus-MT ONNX models running inside Unity.
