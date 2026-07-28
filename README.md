# mojo-xxhash

`mojo-xxhash` is a standalone Mojo port of the compute-heavy one-shot kernels
from the [xxHash project](https://github.com/Cyan4973/xxHash), with a Python
API modeled on the upstream [`xxhash`](https://pypi.org/project/xxhash/)
package. It implements the algorithms rather than linking to `libxxhash`.

The covered subset is:

- XXH32 and XXH64, including 32-bit and 64-bit seeds
- XXH3-64, including every input-length path and 64-bit seeds
- Constructor objects with `update`, `digest`, `hexdigest`, `intdigest`, and
  `copy`
- One-shot helpers such as `xxh64_intdigest` and `xxh3_64_hexdigest`

XXH3-128/XXH128, custom-secret APIs, and native constant-memory streaming
states are not covered. Incremental Python objects are API-compatible, but
retain their input and invoke the one-shot Mojo kernel when a digest is
requested.

## Install and build

Install the pinned Mojo nightly and all Python dependencies, then build the
shared library:

```bash
pixi install
pixi run build
```

Run the parity tests and benchmarks with:

```bash
pixi run test
pixi run bench
```

## Usage

With the Pixi environment active, `python/` is already on `PYTHONPATH`:

```python
import mojo_xxhash as xxhash

assert xxhash.xxh64_hexdigest(b"hello") == "26c7827d889f6da3"

hasher = xxhash.xxh3_64(seed=42)
hasher.update(b"hello ")
hasher.update(b"world")
print(hasher.hexdigest())
```

## Benchmarks

These are best-of-five measurements from `pixi run bench` on this checkout,
taken on an Intel Xeon E5-2697 v4 at 2.30 GHz, Linux x86-64, Python 3.13.14. Throughput
includes the Python call and ctypes boundary. A ratio below `1.00x` means Mojo
was slower.

| Algorithm | Input | Mojo | Upstream xxhash | Mojo / upstream |
|---|---:|---:|---:|---:|
| xxh32 | 64 B | 3.52 us | 0.30 us | 0.09x |
| xxh32 | 4 KiB | 0.91 GB/s | 4.29 GB/s | 0.21x |
| xxh32 | 1 MiB | 2.77 GB/s | 5.30 GB/s | 0.52x |
| xxh32 | 16 MiB | 2.38 GB/s | 3.86 GB/s | 0.62x |
| xxh64 | 64 B | 2.09 us | 0.21 us | 0.10x |
| xxh64 | 4 KiB | 1.74 GB/s | 6.82 GB/s | 0.25x |
| xxh64 | 1 MiB | 10.49 GB/s | 10.87 GB/s | 0.96x |
| xxh64 | 16 MiB | 9.86 GB/s | 9.16 GB/s | 1.08x |
| xxh3_64 | 64 B | 1.98 us | 0.20 us | 0.10x |
| xxh3_64 | 4 KiB | 1.74 GB/s | 7.04 GB/s | 0.25x |
| xxh3_64 | 1 MiB | 12.35 GB/s | 10.65 GB/s | 1.16x |
| xxh3_64 | 16 MiB | 12.12 GB/s | 10.51 GB/s | 1.15x |

The fixed ctypes cost is visible on short inputs. XXH32 remains slower in this
run, while the largest XXH64 input and large XXH3 inputs exceed upstream
throughput. XXH32 uses
four independent SIMD recurrence lanes, and XXH3 updates and scrambles its
accumulator lanes in SIMD groups. Both retain scalar
remainder handling for inputs that end between full stripes.

There is no parallel or GPU path. A single digest has order-dependent block
state, and this port only implements the CPU algorithms.

## How it works

`src/xxhash.mojo` is one compilation unit containing all three kernels and
three C ABI exports. `build/build.sh` compiles it with
`mojo build --emit shared-lib` to `dist/libmojo-xxhash.so`.

Python byte strings and other C-contiguous buffers, including NumPy arrays, stay
in their existing storage and are hashed as raw bytes regardless of element
dtype. Strided buffers are rejected, matching the upstream Python package. The
ctypes bridge retains the GIL while it borrows the buffer, acquires its address
and byte length, and passes those plus the seed by value. Mojo
reconstructs a mutable-origin `UInt8` pointer and uses explicitly unaligned
little-endian word and SIMD loads. Contiguous slices therefore work without an
alignment-dependent result. Only the integer digest crosses back through the ABI;
Python formats it as upstream-compatible big-endian bytes or hexadecimal text.

XXH3 uses the reference 192-byte default secret, length-specialized mixing up
to 240 bytes, and the eight-lane scalar accumulator for longer inputs. Seeded
long inputs derive the same alternating add/subtract secret words used by the
reference algorithm.
