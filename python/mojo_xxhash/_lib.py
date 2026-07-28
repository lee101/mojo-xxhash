"""ctypes bridge to the compiled Mojo hashing kernels."""

from __future__ import annotations

import ctypes
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB_PATH = ROOT / "dist" / "libmojo-xxhash.so"

_I64 = ctypes.c_int64
_U32 = ctypes.c_uint32
_U64 = ctypes.c_uint64
_lib: ctypes.PyDLL | None = None
_symbols: dict[str, ctypes._CFuncPtr] = {}
_bytes_address = ctypes.pythonapi.PyBytes_AsString
_bytes_address.argtypes = [ctypes.py_object]
_bytes_address.restype = ctypes.c_void_p


class _PyBuffer(ctypes.Structure):
    _fields_ = [
        ("buf", ctypes.c_void_p),
        ("obj", ctypes.c_void_p),
        ("len", ctypes.c_ssize_t),
        ("itemsize", ctypes.c_ssize_t),
        ("readonly", ctypes.c_int),
        ("ndim", ctypes.c_int),
        ("format", ctypes.c_char_p),
        ("shape", ctypes.POINTER(ctypes.c_ssize_t)),
        ("strides", ctypes.POINTER(ctypes.c_ssize_t)),
        ("suboffsets", ctypes.POINTER(ctypes.c_ssize_t)),
        ("internal", ctypes.c_void_p),
    ]


_get_buffer = ctypes.pythonapi.PyObject_GetBuffer
_get_buffer.argtypes = [ctypes.py_object, ctypes.POINTER(_PyBuffer), ctypes.c_int]
_get_buffer.restype = ctypes.c_int
_release_buffer = ctypes.pythonapi.PyBuffer_Release
_release_buffer.argtypes = [ctypes.POINTER(_PyBuffer)]
_release_buffer.restype = None


def lib() -> ctypes.PyDLL:
    global _lib, _symbols
    if _lib is None:
        if not LIB_PATH.exists():
            raise RuntimeError("Mojo library is missing; run `pixi run build`")
        # Keep the GIL for the duration of the call.  The pointer below borrows
        # exporter-owned storage; releasing the GIL would let another thread
        # resize a bytearray and invalidate that pointer while Mojo is reading.
        loaded = ctypes.PyDLL(str(LIB_PATH))
        loaded.mojo_xxh32.argtypes = [_I64, _I64, _U32]
        loaded.mojo_xxh32.restype = _U32
        loaded.mojo_xxh64.argtypes = [_I64, _I64, _U64]
        loaded.mojo_xxh64.restype = _U64
        loaded.mojo_xxh3_64.argtypes = [_I64, _I64, _U64]
        loaded.mojo_xxh3_64.restype = _U64
        _lib = loaded
        _symbols = {
            "mojo_xxh32": loaded.mojo_xxh32,
            "mojo_xxh64": loaded.mojo_xxh64,
            "mojo_xxh3_64": loaded.mojo_xxh3_64,
        }
    return _lib


def hash_bytes(symbol: str, data: object, seed: int) -> int:
    lib()
    function = _symbols[symbol]
    if isinstance(data, bytes):
        return int(function(_bytes_address(data), len(data), seed))
    view = _PyBuffer()
    # PyBUF_SIMPLE requests a C-contiguous byte view.  view.len is the number
    # of bytes, independent of the exporter's element dtype and dimensions.
    _get_buffer(data, ctypes.byref(view), 0)
    try:
        address = view.buf or _bytes_address(b"")
        return int(function(address, view.len, seed))
    finally:
        _release_buffer(ctypes.byref(view))
