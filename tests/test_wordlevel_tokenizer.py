# Usage: python -I test_wordlevel_tokenizer.py <SentencePieceWrapper.dll|.so|.dylib> <path to a WordLevel tokenizer.json, e.g. Cairo-TTS/tokenizer.json>
# Verifies the wrapper turns an HF WordLevel tokenizer.json (the character-level vocabulary Cairo-TTS ships) into a
# processor whose ids equal what HF's WordLevel + Split pre-tokenizer produce: one id per character, a ta marbuta
# followed by a vowel mark as one piece, space -> the "space" id, unknown characters -> the unk id.
import ctypes, json, re, sys

sys.stdout.reconfigure(encoding="utf-8")
dll_path, tok_path = sys.argv[1], sys.argv[2]
dll = ctypes.CDLL(dll_path)


class SA(ctypes.Structure):
    _fields_ = [("pieces", ctypes.POINTER(ctypes.c_void_p)), ("count", ctypes.c_int)]


dll.spw_load_processor.restype = ctypes.c_void_p
dll.spw_load_processor.argtypes = [ctypes.c_char_p]
dll.spw_load_processor_from_buffer.restype = ctypes.c_void_p
dll.spw_load_processor_from_buffer.argtypes = [ctypes.c_void_p, ctypes.c_int]
dll.spw_encode_to_pieces.restype = SA
dll.spw_encode_to_pieces.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
dll.spw_piece_to_id.restype = ctypes.c_int
dll.spw_piece_to_id.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
dll.spw_dispose_processor.argtypes = [ctypes.c_void_p]

tok = json.load(open(tok_path, encoding="utf-8"))
assert tok["model"]["type"] == "WordLevel", "this test is for a WordLevel tokenizer.json"
vocab = tok["model"]["vocab"]
unk = vocab[tok["model"].get("unk_token", "[UNK]")]
split = re.compile(tok["pre_tokenizer"]["pattern"]["Regex"])


def reference_ids(text):
    return [vocab.get(piece, unk) for piece in split.findall(text)]


def sp_ids(h, text):
    a = dll.spw_encode_to_pieces(h, text.encode("utf8"))
    pieces = [ctypes.string_at(a.pieces[i]).decode("utf8") for i in range(a.count)]
    return [dll.spw_piece_to_id(h, p.encode("utf8")) for p in pieces]


fails = 0


def check(name, cond, detail=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (("  " + detail) if detail and not cond else ""))
    if not cond:
        fails += 1


raw = open(tok_path, "rb").read()
h_path = dll.spw_load_processor(tok_path.encode())
buf = ctypes.create_string_buffer(raw, len(raw))
h_buf = dll.spw_load_processor_from_buffer(buf, len(raw))
check("load WordLevel .json by path", bool(h_path))
check("load WordLevel .json from buffer", bool(h_buf))
if not (h_path and h_buf):
    sys.exit(1)

# every vocabulary piece round-trips to its own id (the ids index the model's embedding table)
bad = [(p, i, dll.spw_piece_to_id(h_path, ("▁" if p == " " else p).encode("utf8"))) for p, i in vocab.items() if p and p != tok["model"].get("unk_token", "[UNK]")]
bad = [b for b in bad if b[1] != b[2]]
check("piece_to_id matches the WordLevel id for every piece", not bad, str(bad[:5]))

samples = [
    "مرحبا بيك.",                                     # plain Arabic + period
    "رحمةً الله،",                         # ta marbuta + tanween -> one piece
    "مدرسةَ ومدينةِ جميلةُ.",  # ta marbuta + each vowel
    "ال meeting بكره الصبح.",          # code-switching
    "بَتمَشَّى, اتْحرجت.",  # shadda / sukun
    "a b c, d.",
    "  leading and double  spaces ",
    "ةًةًة",                                                          # repeated cluster
    "ة",                                                                                  # lone ta marbuta
    "ة ً",                                                                           # ta marbuta then a space, then a mark
]
for text in samples:
    check(f"ids == WordLevel ids: {text!r}", sp_ids(h_path, text) == reference_ids(text), f"{sp_ids(h_path, text)} != {reference_ids(text)}")
    check(f"buffer load agrees:  {text!r}", sp_ids(h_buf, text) == sp_ids(h_path, text))

# unknown characters: WordLevel emits one unk per character; SentencePiece merges a run into one unk piece. Same id either way.
ids = sp_ids(h_path, "ا☃ب")
check("unknown character maps to the unk id", ids[1:2] == [unk] and ids[0] == vocab["ا"] and ids[-1] == vocab["ب"], str(ids))

dll.spw_dispose_processor(h_path)
dll.spw_dispose_processor(h_buf)
print("FAILED" if fails else "ALL PASSED")
sys.exit(1 if fails else 0)
