#include <sentencepiece_processor.h>
#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>

#ifdef _WIN32
    #define EXPORT extern "C" __declspec(dllexport)
#else
    #define EXPORT extern "C"
#endif

typedef void* SPProcessorHandle;

typedef struct {
    char** pieces;
    int count;
} StringArray;

using namespace sentencepiece;

char* copy_c_string(const std::string& s) {
    size_t len = s.length();
    char* c_str = (char*)std::malloc(len + 1); 
    if (c_str) {
        std::memcpy(c_str, s.c_str(), len + 1);
    }
    return c_str;
}

EXPORT SPProcessorHandle spw_load_processor(const char* model_path) {
    try {
        auto* processor = new SentencePieceProcessor();
        if (!processor->Load(std::string(model_path)).ok()) {
            delete processor;
            return nullptr;
        }
        return processor;
    } catch (...) {
        return nullptr;
    }
}

EXPORT void spw_dispose_processor(SPProcessorHandle handle) {
    delete static_cast<SentencePieceProcessor*>(handle);
}

EXPORT StringArray spw_encode_to_pieces(SPProcessorHandle handle, const char* text) {
    auto* processor = static_cast<SentencePieceProcessor*>(handle);
    std::vector<std::string> pieces;
    
    if (processor == nullptr || !processor->Encode(std::string(text), &pieces).ok()) {
        return {nullptr, 0};
    }

    StringArray result;
    result.count = static_cast<int>(pieces.size());
    
    result.pieces = (char**)std::malloc(result.count * sizeof(char*));
    if (result.pieces == nullptr) {
        return {nullptr, 0};
    }

    for (int i = 0; i < result.count; ++i) {
        result.pieces[i] = copy_c_string(pieces[i]);
    }
    return result;
}

EXPORT void spw_free_string_array(StringArray array) {
    if (array.pieces) {
        std::free(array.pieces);
    }
}

EXPORT void spw_free_string(char* str) {
    if (str) {
        std::free(str);
    }
}

EXPORT int spw_piece_to_id(SPProcessorHandle handle, const char* piece) {
    auto* processor = static_cast<SentencePieceProcessor*>(handle);
    if (processor == nullptr) return -1;

    return processor->PieceToId(std::string(piece));
}

EXPORT char* spw_id_to_piece(SPProcessorHandle handle, int id) {
    auto* processor = static_cast<SentencePieceProcessor*>(handle);
    if (processor == nullptr) return copy_c_string(""); 

    std::string piece = processor->IdToPiece(id);

    return copy_c_string(piece);
}