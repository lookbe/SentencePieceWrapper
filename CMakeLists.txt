# CMakeLists.txt
cmake_minimum_required(VERSION 3.11)
project(SentencePieceWrapper CXX)

# --- Configuration ---
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# --- 1. Fetch SentencePiece Automatically ---
include(FetchContent)

FetchContent_Declare(
  sentencepiece
  GIT_REPOSITORY https://github.com/google/sentencepiece.git
  GIT_TAG        v0.2.0 # Use a stable tag
)

# Set SentencePiece options before building
set(SPM_ENABLE_SHARED OFF CACHE BOOL "Build static library" FORCE)
set(SPM_ENABLE_TCMALLOC OFF CACHE BOOL "Disable tcmalloc" FORCE)
set(SPM_BUILD_TESTS OFF CACHE BOOL "Disable tests" FORCE)
set(SPM_ENABLE_NFKC_COMPILE OFF CACHE BOOL "Disable NFKC compilation if not needed" FORCE)

FetchContent_MakeAvailable(sentencepiece)

# --- 2. Define the Wrapper Shared Library ---
set(WRAPPER_SOURCES
    src/SentencePieceWrapper.cpp
)

# Create the shared library (DLL/SO)
add_library(SentencePieceWrapper SHARED ${WRAPPER_SOURCES})

# --- 3. Link the Wrapper to SentencePiece ---
# When using FetchContent, sentencepiece-static is the target name for the static lib
target_link_libraries(SentencePieceWrapper PRIVATE sentencepiece-static)

if(ANDROID)
    # The static library needs the log library for its internal protobuf-lite
    target_link_libraries(sentencepiece-static INTERFACE log)
    target_link_libraries(SentencePieceWrapper PRIVATE log)
endif()

# Ensure includes are found
target_include_directories(SentencePieceWrapper PRIVATE 
    ${sentencepiece_SOURCE_DIR}/src
)

# Set the output name expected by the C# DllImport
set_target_properties(SentencePieceWrapper PROPERTIES 
    OUTPUT_NAME "SentencePieceWrapper"
)
