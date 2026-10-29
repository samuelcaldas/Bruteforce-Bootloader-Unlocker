#!/usr/bin/env python3
"""Compare identical ordered batches; no fastboot, UI or state disk writes.
Usage: python3 tests/benchmark_candidates.py [count=500] [repeats=3]
Python is needed only for this development benchmark, not for the application.
"""
import hashlib
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "58fbbec336bc0469f0e4d2295dd049b8af461cbc"
COUNT = int(sys.argv[1]) if len(sys.argv) > 1 else 500
REPEATS = int(sys.argv[2]) if len(sys.argv) > 2 else 3
if not 0 < COUNT <= 10000 or REPEATS < 1:
    raise SystemExit("Use count 1..10000 and positive repeats")
OLD = r'''
set -euo pipefail
source "$1/lib/constants.sh"
source "$2"
for ((i=0;i<$4;i++)); do
  code=$(generate_code_from_offset "$i" "$3" "$CHARSET_UPPER_ALPHANUMERIC")
  printf '%s\n' "$code"
done
'''
NEW = r'''
set -euo pipefail
source "$1/lib/constants.sh"
source "$1/lib/pattern_engine.sh"
source "$1/lib/unlock_runner.sh"
CONFIG_PATTERNS="bench:$3:1" CONFIG_ACTIVE_CHARSET=$CHARSET_UPPER_ALPHANUMERIC
CONFIG_STRATEGY=sequential CONFIG_KNOWN_POSITIONS='' STATE_GLOBAL_CURSOR=0
engine_compile
engine_seek 0
for ((i=0;i<$4;i++)); do
  fetch_next_candidate_code
  printf '%s\n' "$CURRENT_CANDIDATE_CODE"
  advance_runtime_cursor
done
'''
print(f"Baseline: {BASELINE}; {platform.platform()}")
print(subprocess.check_output(["bash", "--version"], text=True).splitlines()[0])
print(f"{COUNT} candidates per batch, {REPEATS} runs; median wall time including startup/compilation")
with tempfile.TemporaryDirectory(prefix="bbu_benchmark_") as tmp:
    old_file = Path(tmp) / "old_engine.sh"
    old_file.write_bytes(subprocess.check_output(
        ["git", "show", f"{BASELINE}:lib/pattern_engine.sh"], cwd=ROOT))
    for mask in ("9{4}", "X{20}"):
        times = {"old": [], "new": []}
        outputs = {}
        for _ in range(REPEATS):
            for name, script in (("old", OLD), ("new", NEW)):
                start = time.perf_counter()
                output = subprocess.check_output(
                    ["bash", "-c", script, "benchmark", str(ROOT), str(old_file), mask, str(COUNT)])
                times[name].append(time.perf_counter() - start)
                outputs[name] = output
            assert outputs["old"] == outputs["new"], "Candidate batches differ"
        old, new = (statistics.median(times[name]) for name in ("old", "new"))
        print(f"{mask}: old={old:.6f}s ({COUNT/old:.1f}/s), new={new:.6f}s ({COUNT/new:.1f}/s), speedup={old/new:.2f}x")
        print(f"  runs={times}; SHA256={hashlib.sha256(outputs['new']).hexdigest()}")
