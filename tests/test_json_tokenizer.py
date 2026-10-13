# Usage: python -I test_json_tokenizer.py <SentencePieceWrapper.dll|.so|.dylib> <dir containing tokenizer.model AND tokenizer.json for the same vocab>
# Verifies the wrapper loads HF tokenizer.json (path, buffer, mis-named) and encodes identically to tokenizer.model.
import ctypes, sys, shutil, os, tempfile

sys.stdout.reconfigure(encoding="utf-8")
dll_path, hf = sys.argv[1], sys.argv[2]
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


def enc(h, text):
    a = dll.spw_encode_to_pieces(h, text.encode("utf8"))
    out = [ctypes.string_at(a.pieces[i]).decode("utf8") for i in range(a.count)]
    return out


fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails += 1

model = dll.spw_load_processor(os.path.join(hf, "tokenizer.model").encode())
js = dll.spw_load_processor(os.path.join(hf, "tokenizer.json").encode())
check("load .model", bool(model))
check("load .json by path", bool(js))

raw = open(os.path.join(hf, "tokenizer.json"), "rb").read()
buf = ctypes.create_string_buffer(raw, len(raw))
jb = dll.spw_load_processor_from_buffer(buf, len(raw))
check("load .json from buffer", bool(jb))

# mis-named: json content under tokenizer.model name
tmp = tempfile.mkdtemp()
fake = os.path.join(tmp, "tokenizer.model")
shutil.copy(os.path.join(hf, "tokenizer.json"), fake)
fh = dll.spw_load_processor(fake.encode())
check("json content named .model loads (content sniff)", bool(fh))

samples = [
    "Merhaba dünya, bugün hava çok güzel.",
    "İstanbul'da yaşıyorum ve ŞĞÜÖÇı harfleri var.",
    "  leading and  double  spaces ",
    "Hello world 123 emoji 😀 and 日本語",
    "",
    "a",
    "Çocuklar okula gitti; öğretmen onları bekliyordu!",
]
for s in samples:
    a, b = enc(model, s), enc(js, s)
    check("json==model pieces %r" % s[:30], a == b)
    if a != b:
        print("   model:", a); print("   json :", b)
    check("buffer==path %r" % s[:30], enc(jb, s) == b)

for p in ["<unk>", "<s>", "</s>", "<pad>", "▁merhaba", "<0x41>", "zzzz-not-a-piece"]:
    check("piece_to_id %s" % p, dll.spw_piece_to_id(model, p.encode()) == dll.spw_piece_to_id(js, p.encode()))
check("unk probe equal", dll.spw_piece_to_id(js, b"pocket-tts-unk-probe") == dll.spw_piece_to_id(model, b"pocket-tts-unk-probe") == 0)

# failure paths must return null, not crash
bad = os.path.join(tmp, "bad.json"); open(bad, "w").write("{not json")
check("malformed json -> null", not dll.spw_load_processor(bad.encode()))
bpe = os.path.join(tmp, "bpe.json"); open(bpe, "w").write('{"model":{"type":"BPE","vocab":{}}}')
check("non-unigram json -> null", not dll.spw_load_processor(bpe.encode()))
check("missing file -> null", not dll.spw_load_processor(os.path.join(tmp, "nope.model").encode()))

print("FAILURES:", fails)
sys.exit(1 if fails else 0)
