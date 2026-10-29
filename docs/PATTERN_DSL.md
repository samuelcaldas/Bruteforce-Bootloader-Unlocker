# Pattern DSL and enumeration

| Token | Ordered alphabet |
|---|---|
| `9` | `0123456789` |
| `A` / `a` | `A-Z` / `a-z` |
| `X` | `A-Z` followed by `0-9` |
| `x` | `A-Z`, `a-z`, then `0-9` |
| `H` / `h` | `0-9A-F` / `0-9a-f` |
| `?` | Active charset: `numeric` gives digits; legacy `alpha` and `moto` both give uppercase alphanumeric |
| `{n}` | Repeat preceding token or literal, with a positive decimal count |
| Other characters | Literals, such as `-` and `.`; braces are syntax, colon/semicolon are reserved schedule separators |

Masks expand to at most 4096 positions. Malformed braces, zero/oversized repeat
counts and line breaks are rejected. Numeric CLI values use canonical decimal
(no leading zeros except `0`) and must fit signed 64-bit integers. A schedule is
`name:mask:weight[:description];name:mask:weight[:description]`, with positive
weights whose total fits `9223372036854775807`.

```bash
# Inspect a tiny space without fastboot or any state read/write
./bootloader_unlocker --type numeric --length 2 --preview 5
# Prints 70 through 79 once, then stops
./bootloader_unlocker --pattern '9{2}' --known-positions '0:7' --preview 100
# Overlap: decimal candidates belong to digits; hex supplies A through F
./bootloader_unlocker --patterns 'digits:9:2;hex:H:1' --strategy smart --preview 30
```

`--known-positions '0:A;4:7'` uses zero-based positions. Each value must be one
character already permitted by that position in **every** selected mask.
Duplicate positions, out-of-range positions and incompatible characters are
errors. Known positions become singleton alphabets during compilation, so they
reduce the enumerated space instead of overwriting multiple generated keys with
the same value.

## Strategies

Each mask compiles once to ordered alphabets, bases and a mixed-radix digit
vector. The rightmost position changes fastest, with carry to the left. The hot
path performs no mask expansion, whole-offset division or subprocess per
character. Space size is the product of the compiled bases; `huge` indicates a
product beyond signed 64-bit range, not an overflowed value.

- `sequential`: exhausts each compiled pattern in input order, then moves on.
- `smart`: cycles through active patterns, emitting up to that pattern's weight
  in each turn. Exhausted patterns are skipped. Weights express scheduling
  preference, never demonstrated likelihood of unlocking.
- `random`: chooses a weighted pattern and samples each alphabet using rejection
  sampling. Sampling is **with replacement**: duplicates are possible and this
  strategy does not exhaust. The PRNG is Bash `RANDOM`, not a cryptographic RNG.

Compiled-identical masks are collapsed, retaining the first mask's name and
weight. For deterministic strategies, each candidate belongs to the first
compatible compiled pattern. Later patterns skip it without retaining an
unbounded set of previously emitted keys. Checking overlap costs work proportional
to earlier masks and key length; heavily overlapping large spaces can still take
a long time to skip. Both deterministic strategies terminate once all patterns
are exhausted. Exit status 0 on exhaustion means the search completed, not that
unlocking succeeded; no success file is created.

## Start and resume

`--start N` explicitly starts at raw mixed-radix offset N in **each** retained
pattern, then applies the ownership rule. N must be within every pattern's
space; an offset equal to a finite space is rejected. This is not a global index
into the deduplicated union. `--start 0` is an explicit restart. For random mode,
offset has no predictive meaning for sampled keys; only `--start 0` is accepted.

Version 2 device states store the effective configuration, positional digit
vectors, exhaustion flags, per-pattern diagnostic offsets, scheduler slot/quota
and the attempt counter. Identical deterministic configuration resumes at the
next unconsumed candidate. State is parsed as data, never sourced as shell code.
Random state does not save Bash's PRNG sequence, so exact random replay is not
promised.

Configuration changes, unsupported versions and malformed vectors are rejected
before writing state. Restart explicitly with `--start 0` (or a valid offset);
the CLI retains the old file as `<device>.dat.before-restart.XXXXXX` before saving
the new state. Preview ignores device states entirely and never writes them.

Legacy offsets are migrated only for one unchanged deterministic pattern with
no fixed positions and equivalent charset/order. Multi-pattern schedules,
post-generation fixed characters, random runs, out-of-space offsets and generic
numeric runs affected by the old `X{length}` bug require an explicit restart.
States with position vectors can resume exhausted spaces without retrying them.

Position vectors can represent spaces larger than a signed integer. The total
attempt counter stops with an explicit error at `9223372036854775807`; it never
wraps. Diagnostic pattern offsets beyond that limit become `huge`. Atomic
checkpoints and clean exits preserve progress; a hard kill/power loss can repeat
attempts since the last checkpoint, as no per-attempt durable transaction is
performed with the device.

See [key profile evidence](KEY_PROFILES.md) and [local benchmark](BENCHMARK.md).
