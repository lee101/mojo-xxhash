from __future__ import annotations

import random
import ctypes

import numpy as np
import pytest
import xxhash as upstream

import mojo_xxhash as mojo
from mojo_xxhash._lib import lib


ALGORITHMS = ("xxh32", "xxh64", "xxh3_64")
BOUNDARIES = (
    0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65,
    95, 96, 97, 127, 128, 129, 159, 191, 239, 240, 241, 255, 256,
    511, 512, 1023, 1024, 1025, 2048, 4097,
)
SEEDS = (0, 1, 0x12345678, 0xFFFFFFFF, 0x0123456789ABCDEF)


def data_for(length: int) -> bytes:
    rng = random.Random(length)
    return rng.randbytes(length)


@pytest.mark.parametrize("algorithm", ALGORITHMS)
@pytest.mark.parametrize("length", BOUNDARIES)
def test_intdigest_parity_at_algorithm_boundaries(algorithm, length):
    data = data_for(length)
    ours = getattr(mojo, f"{algorithm}_intdigest")(data)
    expected = getattr(upstream, f"{algorithm}_intdigest")(data)
    assert ours == expected


@pytest.mark.parametrize("algorithm", ALGORITHMS)
@pytest.mark.parametrize("seed", SEEDS)
def test_seeded_helpers_match_upstream(algorithm, seed):
    data = data_for(777)
    for suffix in ("intdigest", "digest", "hexdigest"):
        ours = getattr(mojo, f"{algorithm}_{suffix}")(data, seed=seed)
        expected = getattr(upstream, f"{algorithm}_{suffix}")(data, seed=seed)
        assert ours == expected


@pytest.mark.parametrize("algorithm", ALGORITHMS)
def test_incremental_update_copy_and_metadata(algorithm):
    ours = getattr(mojo, algorithm)(b"prefix", seed=42)
    expected = getattr(upstream, algorithm)(b"prefix", seed=42)
    for chunk in (b"", bytearray(b"-middle"), memoryview(b"-suffix")):
        assert ours.update(chunk) is expected.update(chunk) is None
    copied = ours.copy()
    expected_copy = expected.copy()
    ours.update(b"-left")
    expected.update(b"-left")
    copied.update(b"-right")
    expected_copy.update(b"-right")
    assert ours.digest() == expected.digest()
    assert copied.digest() == expected_copy.digest()
    assert ours.name == expected.name
    assert ours.digest_size == expected.digest_size
    assert ours.block_size == expected.block_size
    assert ours.seed == expected.seed


@pytest.mark.parametrize("algorithm", ALGORITHMS)
def test_digest_forms_and_string_input(algorithm):
    ours = getattr(mojo, algorithm)("café", seed=-1)
    expected = getattr(upstream, algorithm)("café", seed=-1)
    assert ours.intdigest() == expected.intdigest()
    assert ours.digest() == expected.digest()
    assert ours.hexdigest() == expected.hexdigest()


@pytest.mark.parametrize("algorithm", ALGORITHMS)
def test_rejects_non_buffer_input(algorithm):
    with pytest.raises(TypeError, match="bytes-like object"):
        getattr(mojo, algorithm)(123)


@pytest.mark.parametrize("algorithm", ALGORITHMS)
@pytest.mark.parametrize("length", (257, 1023, 1025, 4099))
def test_simd_stripes_and_scalar_tails(algorithm, length):
    storage = data_for(length + 1)
    data = memoryview(storage)[1:]
    ours = getattr(mojo, f"{algorithm}_intdigest")(data, seed=42)
    expected = getattr(upstream, f"{algorithm}_intdigest")(data, seed=42)
    assert ours == expected


@pytest.mark.parametrize("length", (16, 17, 31, 32, 33, 4099))
@pytest.mark.parametrize("seed", (0, 0xFFFFFFFF))
def test_xxh32_independent_lanes_and_tails(length, seed):
    data = data_for(length)
    assert mojo.xxh32_intdigest(data, seed=seed) == upstream.xxh32_intdigest(
        data, seed=seed
    )


@pytest.mark.parametrize("algorithm", ALGORITHMS)
def test_contiguous_numpy_buffers_match_upstream(algorithm):
    data = np.arange(4099, dtype=np.uint8)
    ours = getattr(mojo, f"{algorithm}_intdigest")(data, seed=7)
    expected = getattr(upstream, f"{algorithm}_intdigest")(data, seed=7)
    assert ours == expected


@pytest.mark.parametrize("algorithm", ALGORITHMS)
@pytest.mark.parametrize(
    "data",
    (
        np.array([], dtype=np.uint8),
        np.arange(12, dtype=np.uint16).reshape(3, 4),
    ),
)
def test_contiguous_numpy_buffers_are_hashed_as_raw_bytes(algorithm, data):
    ours = getattr(mojo, f"{algorithm}_intdigest")(data, seed=7)
    expected = getattr(upstream, f"{algorithm}_intdigest")(data, seed=7)
    assert ours == expected


@pytest.mark.parametrize("algorithm", ALGORITHMS)
def test_strided_buffers_are_rejected(algorithm):
    data = np.arange(32, dtype=np.uint8)[::2]
    with pytest.raises(ValueError, match="not C-contiguous"):
        getattr(mojo, f"{algorithm}_intdigest")(data)


def test_ffi_calls_retain_gil_while_borrowing_buffer_storage():
    assert isinstance(lib(), ctypes.PyDLL)
