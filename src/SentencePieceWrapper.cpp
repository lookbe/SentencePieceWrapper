#include <sentencepiece_processor.h>
#include <builtin_pb/sentencepiece_model.pb.h>
#include <string>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <cctype>
#include <algorithm>
#include <fstream>
#include <iterator>
#include <memory>
#include <stdexcept>

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

// ---------------------------------------------------------------------------
// HuggingFace tokenizer.json support.
//
// Newer pocket-tts language repos ship `tokenizer.json` (HF "tokenizers" Unigram
// model) instead of a SentencePiece `tokenizer.model`. Rather than add a second
// tokenizer engine, the JSON is converted in-memory to the equivalent
// SentencePiece ModelProto and loaded through LoadFromSerializedProto, so Encode /
// PieceToId behave identically for both formats. Only the Unigram model type is
// supported; anything else fails the load (nullptr), same as a corrupt .model.
// ---------------------------------------------------------------------------
namespace {

struct JsonValue {
    enum Kind { Null, Bool, Number, String, Array, Object } kind = Null;
    bool b = false;
    double num = 0;
    std::string str;
    std::vector<JsonValue> arr;
    std::vector<std::pair<std::string, JsonValue>> obj;

    const JsonValue* Get(const char* key) const {
        if (kind != Object) return nullptr;
        for (const auto& kv : obj) if (kv.first == key) return &kv.second;
        return nullptr;
    }
};

class JsonParser {
public:
    JsonParser(const char* d, size_t n) : p_(d), end_(d + n) {}
    JsonValue Parse() {
        JsonValue v = ParseValue();
        SkipWs();
        if (p_ != end_) throw std::runtime_error("trailing json data");
        return v;
    }
private:
    const char* p_;
    const char* end_;
    int depth_ = 0;

    void SkipWs() { while (p_ < end_ && (*p_ == ' ' || *p_ == '\t' || *p_ == '\n' || *p_ == '\r')) ++p_; }
    void Expect(char c) { SkipWs(); if (p_ >= end_ || *p_ != c) throw std::runtime_error("json: unexpected char"); ++p_; }
    bool Lit(const char* w) {
        size_t n = std::strlen(w);
        if (static_cast<size_t>(end_ - p_) >= n && std::memcmp(p_, w, n) == 0) { p_ += n; return true; }
        return false;
    }
    static void AppendUtf8(std::string& o, unsigned cp) {
        if (cp < 0x80) o += static_cast<char>(cp);
        else if (cp < 0x800) { o += static_cast<char>(0xC0 | (cp >> 6)); o += static_cast<char>(0x80 | (cp & 0x3F)); }
        else if (cp < 0x10000) { o += static_cast<char>(0xE0 | (cp >> 12)); o += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); o += static_cast<char>(0x80 | (cp & 0x3F)); }
        else { o += static_cast<char>(0xF0 | (cp >> 18)); o += static_cast<char>(0x80 | ((cp >> 12) & 0x3F)); o += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); o += static_cast<char>(0x80 | (cp & 0x3F)); }
    }
    unsigned Hex4() {
        if (end_ - p_ < 4) throw std::runtime_error("json: bad \\u escape");
        unsigned v = 0;
        for (int i = 0; i < 4; ++i) {
            char c = *p_++;
            v <<= 4;
            if (c >= '0' && c <= '9') v |= c - '0';
            else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
            else throw std::runtime_error("json: bad \\u escape");
        }
        return v;
    }
    std::string ParseString() {
        Expect('"');
        std::string out;
        while (true) {
            if (p_ >= end_) throw std::runtime_error("json: unterminated string");
            char c = *p_++;
            if (c == '"') break;
            if (c != '\\') { out += c; continue; }
            if (p_ >= end_) throw std::runtime_error("json: bad escape");
            char e = *p_++;
            switch (e) {
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    unsigned cp = Hex4();
                    if (cp >= 0xD800 && cp < 0xDC00 && end_ - p_ >= 6 && p_[0] == '\\' && p_[1] == 'u') {
                        p_ += 2;
                        unsigned lo = Hex4();
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    }
                    AppendUtf8(out, cp);
                    break;
                }
                default: throw std::runtime_error("json: bad escape");
            }
        }
        return out;
    }
    JsonValue ParseValue() {
        SkipWs();
        if (p_ >= end_) throw std::runtime_error("json: unexpected end");
        if (++depth_ > 64) throw std::runtime_error("json: too deep");
        JsonValue v;
        char c = *p_;
        if (c == '{') {
            ++p_; v.kind = JsonValue::Object; SkipWs();
            if (p_ < end_ && *p_ == '}') ++p_;
            else while (true) {
                SkipWs();
                std::string k = ParseString();
                Expect(':');
                v.obj.emplace_back(std::move(k), ParseValue());
                SkipWs();
                if (p_ < end_ && *p_ == ',') { ++p_; continue; }
                Expect('}'); break;
            }
        } else if (c == '[') {
            ++p_; v.kind = JsonValue::Array; SkipWs();
            if (p_ < end_ && *p_ == ']') ++p_;
            else while (true) {
                v.arr.push_back(ParseValue());
                SkipWs();
                if (p_ < end_ && *p_ == ',') { ++p_; continue; }
                Expect(']'); break;
            }
        } else if (c == '"') {
            v.kind = JsonValue::String; v.str = ParseString();
        } else if (Lit("true")) { v.kind = JsonValue::Bool; v.b = true; }
        else if (Lit("false")) { v.kind = JsonValue::Bool; v.b = false; }
        else if (Lit("null")) { v.kind = JsonValue::Null; }
        else {
            char* endp = nullptr;
            std::string tmp(p_, std::min<size_t>(64, static_cast<size_t>(end_ - p_)));
            v.num = std::strtod(tmp.c_str(), &endp);
            if (endp == tmp.c_str()) throw std::runtime_error("json: bad value");
            p_ += (endp - tmp.c_str());
            v.kind = JsonValue::Number;
        }
        --depth_;
        return v;
    }
};

std::string Base64Decode(const std::string& in) {
    std::string out;
    unsigned buf = 0; int bits = 0;
    for (char c : in) {
        int v;
        if (c >= 'A' && c <= 'Z') v = c - 'A';
        else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
        else if (c >= '0' && c <= '9') v = c - '0' + 52;
        else if (c == '+') v = 62;
        else if (c == '/') v = 63;
        else continue; // '=' padding / whitespace
        buf = (buf << 6) | static_cast<unsigned>(v);
        bits += 6;
        if (bits >= 8) { bits -= 8; out += static_cast<char>((buf >> bits) & 0xFF); }
    }
    return out;
}

bool IsByteToken(const std::string& s) {
    // "<0xNN>"
    return s.size() == 6 && s[0] == '<' && s[1] == '0' && s[2] == 'x' && std::isxdigit((unsigned char)s[3]) &&
           std::isxdigit((unsigned char)s[4]) && s[5] == '>';
}

// Walks a normalizer (possibly a Sequence) collecting what maps onto SentencePiece's NormalizerSpec.
void CollectNormalizer(const JsonValue* n, bool& prepend, std::string& charsmap) {
    if (!n || n->kind != JsonValue::Object) return;
    const JsonValue* t = n->Get("type");
    const std::string type = (t && t->kind == JsonValue::String) ? t->str : "";
    if (type == "Sequence") {
        const JsonValue* list = n->Get("normalizers");
        if (list && list->kind == JsonValue::Array) for (const auto& c : list->arr) CollectNormalizer(&c, prepend, charsmap);
    } else if (type == "Prepend") {
        prepend = true;
    } else if (type == "Precompiled") {
        const JsonValue* cm = n->Get("precompiled_charsmap");
        if (cm && cm->kind == JsonValue::String) charsmap = Base64Decode(cm->str);
    }
}

// Returns the serialized SentencePiece ModelProto equivalent to an HF Unigram tokenizer.json.
std::string TokenizerJsonToSerializedModel(const char* data, size_t size) {
    JsonValue root = JsonParser(data, size).Parse();
    const JsonValue* model = root.Get("model");
    if (!model || model->kind != JsonValue::Object) throw std::runtime_error("tokenizer.json: no model");
    const JsonValue* type = model->Get("type");
    if (!type || type->kind != JsonValue::String || type->str != "Unigram")
        throw std::runtime_error("tokenizer.json: only Unigram models are supported");
    const JsonValue* vocab = model->Get("vocab");
    if (!vocab || vocab->kind != JsonValue::Array || vocab->arr.empty()) throw std::runtime_error("tokenizer.json: no vocab");

    int unkId = 0;
    if (const JsonValue* u = model->Get("unk_id")) if (u->kind == JsonValue::Number) unkId = static_cast<int>(u->num);
    bool byteFallback = false;
    if (const JsonValue* b = model->Get("byte_fallback")) byteFallback = (b->kind == JsonValue::Bool && b->b);

    // Ids that HF flags as special added tokens (<s>, </s>, <pad>, ...) are CONTROL pieces.
    std::vector<bool> special(vocab->arr.size(), false);
    if (const JsonValue* added = root.Get("added_tokens")) if (added->kind == JsonValue::Array) {
        for (const auto& a : added->arr) {
            const JsonValue* id = a.Get("id"); const JsonValue* sp = a.Get("special");
            if (id && id->kind == JsonValue::Number && sp && sp->kind == JsonValue::Bool && sp->b) {
                int i = static_cast<int>(id->num);
                if (i >= 0 && i < static_cast<int>(special.size())) special[i] = true;
            }
        }
    }

    sentencepiece::ModelProto proto;
    auto* ts = proto.mutable_trainer_spec();
    ts->set_model_type(sentencepiece::TrainerSpec::UNIGRAM);
    ts->set_vocab_size(static_cast<int32_t>(vocab->arr.size()));
    ts->set_byte_fallback(byteFallback);
    ts->set_unk_id(unkId);
    ts->set_bos_id(-1);
    ts->set_eos_id(-1);
    ts->set_pad_id(-1);

    for (size_t i = 0; i < vocab->arr.size(); ++i) {
        const JsonValue& e = vocab->arr[i];
        if (e.kind != JsonValue::Array || e.arr.size() < 2 || e.arr[0].kind != JsonValue::String || e.arr[1].kind != JsonValue::Number)
            throw std::runtime_error("tokenizer.json: bad vocab entry");
        const std::string& piece = e.arr[0].str;
        auto* sp = proto.add_pieces();
        sp->set_piece(piece);
        sp->set_score(static_cast<float>(e.arr[1].num));
        if (static_cast<int>(i) == unkId) sp->set_type(sentencepiece::ModelProto::SentencePiece::UNKNOWN);
        else if (special[i]) sp->set_type(sentencepiece::ModelProto::SentencePiece::CONTROL);
        else if (byteFallback && IsByteToken(piece)) sp->set_type(sentencepiece::ModelProto::SentencePiece::BYTE);
        else sp->set_type(sentencepiece::ModelProto::SentencePiece::NORMAL);

        if (special[i]) {
            if (piece == "<s>") { ts->set_bos_id(static_cast<int32_t>(i)); ts->set_bos_piece(piece); }
            else if (piece == "</s>") { ts->set_eos_id(static_cast<int32_t>(i)); ts->set_eos_piece(piece); }
            else if (piece == "<pad>") { ts->set_pad_id(static_cast<int32_t>(i)); ts->set_pad_piece(piece); }
        }
    }
    if (unkId >= 0 && unkId < static_cast<int>(vocab->arr.size()))
        ts->set_unk_piece(proto.pieces(unkId).piece());

    bool prepend = false;
    std::string charsmap;
    CollectNormalizer(root.Get("normalizer"), prepend, charsmap);
    if (const JsonValue* pre = root.Get("pre_tokenizer")) {
        const JsonValue* t = pre->Get("type");
        if (t && t->kind == JsonValue::String && t->str == "Metaspace") {
            const JsonValue* scheme = pre->Get("prepend_scheme");
            if (!scheme || scheme->kind != JsonValue::String || scheme->str != "never") prepend = true;
        }
    }
    auto* ns = proto.mutable_normalizer_spec();
    ns->set_name(charsmap.empty() ? "identity" : "nmt_nfkc");
    ns->set_precompiled_charsmap(charsmap);
    ns->set_add_dummy_prefix(prepend);
    ns->set_remove_extra_whitespaces(false);
    ns->set_escape_whitespaces(true);

    return proto.SerializeAsString();
}

bool LooksLikeJson(const char* data, size_t size) {
    for (size_t i = 0; i < size; ++i) {
        unsigned char c = static_cast<unsigned char>(data[i]);
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') continue;
        if (c == 0xEF && i + 2 < size && (unsigned char)data[i + 1] == 0xBB && (unsigned char)data[i + 2] == 0xBF) { i += 2; continue; } // UTF-8 BOM
        return c == '{';
    }
    return false;
}

// Loads a processor from tokenizer.json bytes; nullptr on any failure.
SentencePieceProcessor* LoadProcessorFromJson(const char* data, size_t size) {
    try {
        std::string serialized = TokenizerJsonToSerializedModel(data, size);
        auto processor = std::make_unique<SentencePieceProcessor>();
        if (!processor->LoadFromSerializedProto(serialized).ok()) return nullptr;
        return processor.release();
    } catch (...) {
        return nullptr;
    }
}

} // namespace

EXPORT SPProcessorHandle spw_load_processor(const char* model_path) {
    try {
        // A tokenizer.json is detected by content, not extension, so a mis-named file still loads.
        {
            std::ifstream in(std::string(model_path), std::ios::binary);
            if (in) {
                std::string head(256, '\0');
                in.read(&head[0], static_cast<std::streamsize>(head.size()));
                head.resize(static_cast<size_t>(in.gcount()));
                if (LooksLikeJson(head.data(), head.size())) {
                    in.clear();
                    in.seekg(0);
                    std::string all((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
                    return LoadProcessorFromJson(all.data(), all.size());
                }
            }
        }
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

EXPORT SPProcessorHandle spw_load_processor_from_buffer(const void* model_data, int model_size) {
    try {
        if (!model_data || model_size <= 0) return nullptr;
        if (LooksLikeJson(static_cast<const char*>(model_data), static_cast<size_t>(model_size)))
            return LoadProcessorFromJson(static_cast<const char*>(model_data), static_cast<size_t>(model_size));
        auto* processor = new SentencePieceProcessor();
        absl::string_view sv(static_cast<const char*>(model_data), static_cast<size_t>(model_size));
        if (!processor->LoadFromSerializedProto(sv).ok()) {
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