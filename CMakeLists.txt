# CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MarianSpmWrapper CXX)

# --- Configuration ---
set(CMAKE_CXX_STANDARD 17)
# Essential for creating a shared library that links against a static or shared dependency
set(CMAKE_POSITION_INDEPENDENT_CODE ON) 

# --- 1. Define the External SentencePiece Library as an IMPORTED target ---
# Define a target for the pre-built SentencePiece library.
# Replace 'sentencepiece.a' with the actual filename of your library (e.g., 'sentencepiece.lib' on Windows).
add_library(SentencePieceLib STATIC IMPORTED) 

# Specify the location of the SentencePiece library file.
set_target_properties(SentencePieceLib PROPERTIES 
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/lib/sentencepiece.lib"
)

# Specify the public include path required to compile against SentencePiece.
target_include_directories(SentencePieceLib INTERFACE 
    "${CMAKE_CURRENT_SOURCE_DIR}/includes"
)


# --- 2. Define the Wrapper Shared Library ---
set(WRAPPER_SOURCES
    src/SentencePieceWrapper.cpp
)

# Create the shared library (DLL/SO)
add_library(MarianSpmWrapper SHARED ${WRAPPER_SOURCES})

# Set the output name expected by the C# DllImport (e.g., SentencePieceWrapper.dll or libSentencePieceWrapper.so)
set_target_properties(MarianSpmWrapper PROPERTIES 
    OUTPUT_NAME "SentencePieceWrapper"
)

# --- 3. Link the Wrapper to the Imported Library ---
# Link your wrapper implementation against the imported SentencePiece library.
# We use PRIVATE because consumers of MarianSpmWrapper won't need SentencePieceLib's headers or linkage flags.
target_link_libraries(MarianSpmWrapper PRIVATE 
    SentencePieceLib
)