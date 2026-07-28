"""Compare Mojo one-shot hashes with the upstream Python xxhash extension."""

from __future__ import annotations

import os
import platform
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import mojo_xxhash as mojo  # noqa: E402
import xxhash as upstream  # noqa: E402


def best_time(function, iterations: int, repeats: int = 5) -> float:
    best = float("inf")
    for _ in range(repeats):
        start = time.perf_counter()
        for _ in range(iterations):
            function()
        best = min(best, (time.perf_counter() - start) / iterations)
    return best


def cpu_name() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or platform.machine()


def rate(size: int, seconds: float) -> str:
    if size < 1024:
        return f"{seconds * 1e6:.2f} us"
    return f"{size / seconds / 1e9:.2f} GB/s"


def main() -> None:
    cases = (
        ("64 B", bytes(range(64)), 50_000),
        ("4 KiB", os.urandom(4 * 1024), 10_000),
        ("1 MiB", os.urandom(1024 * 1024), 100),
        ("16 MiB", os.urandom(16 * 1024 * 1024), 8),
    )
    print(f"Machine: {cpu_name()}; {platform.system()} {platform.machine()}; Python {platform.python_version()}")
    print()
    print("| Algorithm | Input | Mojo | Upstream xxhash | Mojo / upstream |")
    print("|---|---:|---:|---:|---:|")
    for algorithm in ("xxh32", "xxh64", "xxh3_64"):
        mojo_fn = getattr(mojo, f"{algorithm}_intdigest")
        upstream_fn = getattr(upstream, f"{algorithm}_intdigest")
        for label, data, iterations in cases:
            assert mojo_fn(data) == upstream_fn(data)
            mojo_s = best_time(lambda: mojo_fn(data), iterations)
            upstream_s = best_time(lambda: upstream_fn(data), iterations)
            ratio = upstream_s / mojo_s
            print(
                f"| {algorithm} | {label} | {rate(len(data), mojo_s)} | "
                f"{rate(len(data), upstream_s)} | {ratio:.2f}x |"
            )


if __name__ == "__main__":
    main()
