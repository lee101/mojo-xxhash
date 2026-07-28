"""Python-compatible API backed by Mojo implementations of xxHash."""

from __future__ import annotations

from typing import Any

from ._lib import hash_bytes

VERSION = "0.1.0"
VERSION_TUPLE = (0, 1, 0)
XXHASH_VERSION = "0.8.3-compatible"
algorithms_available = {"xxh32", "xxh64", "xxh3_64"}


def _bytes(value: Any) -> bytes:
    if isinstance(value, bytes):
        return value
    if isinstance(value, str):
        return value.encode()
    try:
        return bytes(memoryview(value))
    except TypeError:
        raise TypeError(
            f"a bytes-like object is required, not '{type(value).__name__}'"
        ) from None


class _Hash:
    _symbol = ""
    _bits = 0
    name = ""
    digest_size = 0
    block_size = 0

    def __init__(self, input: Any = b"", seed: int = 0):
        self.seed = int(seed) & ((1 << self._bits) - 1)
        self._data = bytearray(_bytes(input))

    def update(self, input: Any) -> None:
        self._data.extend(_bytes(input))

    def intdigest(self) -> int:
        return hash_bytes(self._symbol, self._data, self.seed)

    def digest(self) -> bytes:
        return self.intdigest().to_bytes(self.digest_size, "big")

    def hexdigest(self) -> str:
        return f"{self.intdigest():0{self.digest_size * 2}x}"

    def copy(self):
        duplicate = object.__new__(type(self))
        duplicate.seed = self.seed
        duplicate._data = self._data.copy()
        return duplicate


class xxh32(_Hash):
    _symbol = "mojo_xxh32"
    _bits = 32
    name = "XXH32"
    digest_size = 4
    block_size = 16


class xxh64(_Hash):
    _symbol = "mojo_xxh64"
    _bits = 64
    name = "XXH64"
    digest_size = 8
    block_size = 32


class xxh3_64(_Hash):
    _symbol = "mojo_xxh3_64"
    _bits = 64
    name = "XXH3_64"
    digest_size = 8
    block_size = 32


def _one_shot(symbol: str, bits: int, input: Any, seed: int) -> int:
    if isinstance(input, str):
        input = input.encode()
    try:
        return hash_bytes(symbol, input, int(seed) & ((1 << bits) - 1))
    except (TypeError, BufferError):
        raise TypeError(
            f"a bytes-like object is required, not '{type(input).__name__}'"
        ) from None


def xxh32_intdigest(input: Any, seed: int = 0) -> int:
    return _one_shot("mojo_xxh32", 32, input, seed)


def xxh32_digest(input: Any, seed: int = 0) -> bytes:
    return xxh32_intdigest(input, seed).to_bytes(4, "big")


def xxh32_hexdigest(input: Any, seed: int = 0) -> str:
    return f"{xxh32_intdigest(input, seed):08x}"


def xxh64_intdigest(input: Any, seed: int = 0) -> int:
    return _one_shot("mojo_xxh64", 64, input, seed)


def xxh64_digest(input: Any, seed: int = 0) -> bytes:
    return xxh64_intdigest(input, seed).to_bytes(8, "big")


def xxh64_hexdigest(input: Any, seed: int = 0) -> str:
    return f"{xxh64_intdigest(input, seed):016x}"


def xxh3_64_intdigest(input: Any, seed: int = 0) -> int:
    return _one_shot("mojo_xxh3_64", 64, input, seed)


def xxh3_64_digest(input: Any, seed: int = 0) -> bytes:
    return xxh3_64_intdigest(input, seed).to_bytes(8, "big")


def xxh3_64_hexdigest(input: Any, seed: int = 0) -> str:
    return f"{xxh3_64_intdigest(input, seed):016x}"


__all__ = [
    "xxh32",
    "xxh32_digest",
    "xxh32_intdigest",
    "xxh32_hexdigest",
    "xxh64",
    "xxh64_digest",
    "xxh64_intdigest",
    "xxh64_hexdigest",
    "xxh3_64",
    "xxh3_64_digest",
    "xxh3_64_intdigest",
    "xxh3_64_hexdigest",
    "VERSION",
    "VERSION_TUPLE",
    "XXHASH_VERSION",
    "algorithms_available",
]
