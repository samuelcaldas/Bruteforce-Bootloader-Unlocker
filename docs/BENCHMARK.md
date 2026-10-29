# Candidate generation benchmark

Measured on 2026-10-29, Linux x86_64 (kernel 7.0.0-38-generic), Bash
5.3.9(1)-release, glibc 2.43. This measures local generation, not USB throughput
or probability of finding a valid device-bound key.

Reproduce from the repository root (Python 3 and Git required only for this
benchmark):

```bash
python3 tests/benchmark_candidates.py 500 3
```

Baseline: `58fbbec336bc0469f0e4d2295dd049b8af461cbc:lib/pattern_engine.sh`.
The script retrieves the old generator from Git into a temporary directory.
Both engines generate the same ordered 500-candidate batch starting at zero,
with no known positions, UI, fastboot calls or state persistence. The baseline
calls its offset generator for every key; the new engine compiles once, then
fetches and advances vectors. Each process includes Bash startup; the new
measurements include compilation. Output is captured in memory and compared
byte for byte on every run. Reported values are the median of three runs.

| Mask | Old time | Old candidates/s | New time | New candidates/s | Speedup |
|---|---:|---:|---:|---:|---:|
| `9{4}` | 1.003890 s | 498.1 | 0.079556 s | 6,284.9 | 12.62× |
| `X{20}` | 3.197454 s | 156.4 | 0.148720 s | 3,362.0 | 21.50× |

Raw seconds:

- `9{4}` old: 1.014391, 1.003890, 0.998979; new: 0.079752, 0.079513, 0.079556.
- `X{20}` old: 3.238659, 3.197454, 3.179960; new: 0.152848, 0.147427, 0.148720.

Batch SHA-256 (identical for both engines):

```text
9{4}  a16c626eb966cd6ffb487b252bad6e212007fdc3fc2bfd39a38441bddaf6b637
X{20} 7f594939735c30995ccc05ddf01135b4968567386cfbc87c8344ccf7f27c816f
```

These are small single-mask workloads on this host, not a universal speed claim.
Multiple overlapping masks add compatibility checks and skipped-candidate work;
USB latency, device lockouts and command execution are deliberately excluded.
