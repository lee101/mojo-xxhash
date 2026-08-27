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
| xxh32 | 64 B | 1.36 us | 0.19 us | 0.14x |
| xxh32 | 4 KiB | 2.05 GB/s | 4.66 GB/s | 0.44x |
| xxh32 | 1 MiB | 6.09 GB/s | 5.71 GB/s | 1.07x |
| xxh32 | 16 MiB | 5.73 GB/s | 5.59 GB/s | 1.03x |
| xxh64 | 64 B | 1.41 us | 0.21 us | 0.15x |
| xxh64 | 4 KiB | 2.35 GB/s | 7.77 GB/s | 0.30x |
| xxh64 | 1 MiB | 11.29 GB/s | 10.95 GB/s | 1.03x |
| xxh64 | 16 MiB | 11.29 GB/s | 11.18 GB/s | 1.01x |
| xxh3_64 | 64 B | 1.37 us | 0.18 us | 0.13x |
| xxh3_64 | 4 KiB | 2.53 GB/s | 7.64 GB/s | 0.33x |
| xxh3_64 | 1 MiB | 13.46 GB/s | 11.97 GB/s | 1.12x |
| xxh3_64 | 16 MiB | 13.42 GB/s | 11.12 GB/s | 1.21x |

The fixed ctypes cost is visible on short inputs. Bytes now cross ctypes
directly instead of making a second ctypes call to obtain their address.
XXH32 keeps four independent scalar recurrence lanes so Broadwell can overlap
its integer multiplies; packing them into one SIMD value created a slower
high-latency `vpmulld` dependency chain. XXH3 updates and scrambles its
accumulator lanes at the native float64 SIMD width, with scalar remainder
handling for inputs that end between full groups. In the final run, XXH32 and
XXH64 reached upstream parity on large inputs and XXH3 remained ahead. Absolute
1 MiB/16 MiB XXH64 and XXH3 throughput was lower than the initial run despite
unchanged kernel structure, reflecting the run-to-run contention visible on
this shared machine.

There is no parallel or GPU path. A single digest has order-dependent block
state, so its blocks are not independent parallel work. These hashes also have
low arithmetic intensity, and device transfer plus launch overhead would cost
more than a GPU could recover.

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
