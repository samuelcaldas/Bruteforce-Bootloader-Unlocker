# Architecture & Modular Subsystems

## Overview

The Bootloader Unlocker is engineered as a modular, fail-fast CLI application adhering to **SOLID principles** and **Object Calisthenics** constraints.

```
bootloader_unlocker (Entrypoint Orchestrator)
 │
 ├── lib/constants.sh        - System constants, charsets, boundaries, exit codes
 ├── lib/terminal_ui.sh      - Terminal styling, responsive width, banners, status loggers
 ├── lib/device_storage.sh   - Atomic serialization, device state files, success records
 ├── lib/pattern_engine.sh   - Bounded DSL expansion and compatibility helpers
 ├── lib/candidate_engine.sh - Compiled alphabets, carry counters, ownership, scheduling
 ├── lib/runtime_config.sh   - Configuration resolution, state compatibility, preview
 ├── lib/fastboot_client.sh  - Transport adapter, tool probing, payload dispatch
 ├── lib/argument_parser.sh  - Command-line parsing, validation, help & table rendering
 └── lib/unlock_runner.sh    - Execution loop, confirmation guard, progress reporting
```

---

## Subsystems

### 1. `lib/constants.sh`
- Declares read-only constants (`readonly`) to prevent accidental mutation.
- Defines standard exit codes: `0` (Success), `1` (General error), `2` (Terminal fastboot error), `130` (Interrupt).
- Defines immutable character set lookup tables and built-in pattern schedules.

### 2. `lib/terminal_ui.sh`
- Handles visual hierarchy and ANSI styling.
- Inspects `NO_COLOR`, `TERM=dumb`, and interactive TTY status (`-t 1`).
- Dynamically queries terminal dimensions via `tput cols` or `$COLUMNS`.
- Truncates single-line dynamic progress rendering to fit narrow terminal screens.

### 3. `lib/device_storage.sh`
- Sanitizes device serials (`tr -c 'A-Za-z0-9._-' '_'`) to prevent directory traversal or unsafe characters.
- Implements atomic writes (`.tmp.$$` moved over destination file via `mv -f`) to guarantee state integrity on unexpected kill signals.
- Stores version 2 configuration, positional vectors, exhaustion, scheduler quota and counters.
- Refuses incompatible state before writing; explicit restarts retain a backup.

### 4. `lib/pattern_engine.sh`
- Expands pattern DSL masks including `{n}` repetitions.
- Performs combination space calculation with 64-bit integer overflow protection (`huge` return for spaces exceeding `9223372036854775807`).
- Loads `candidate_engine.sh`, which compiles masks once and uses a mixed-radix counter.
- Runtime calls return candidates through variables in the parent shell, preserving vectors.
- Earlier compatible masks own overlapping candidates; compiled duplicates are collapsed.
- `runtime_config.sh` validates effective settings and conservatively migrates legacy states.
- Preview exits before tool discovery, device detection and state access.

### 5. `lib/fastboot_client.sh`
- Encapsulates interaction with the `fastboot` binary.
- Normalizes Windows carriage-return outputs (`\r\n` -> `\n`) when running under WSL or calling `fastboot.exe`.
- Probes device properties safely without issuing destructive commands:
  - `flashing get_unlock_ability`
  - `oem get_unlock_data`
  - `getvar product`
- Detects non-retryable terminal errors (e.g. OEM unlock disabled, FRP active, carrier lock).

### 6. `lib/argument_parser.sh`
- Validates all CLI flags and parameters with fail-fast guards.
- Enforces numeric range validation on `--length` and `--start`.
- Renders styled, structured help guides and pattern tables.

### 7. `lib/unlock_runner.sh`
- Enforces an explicit `AUTHORIZED` confirmation prompt before initiating any commands.
- Orchestrates the evaluation loop with periodic atomic persistence.
- Formats dynamic percentages with 3-decimal precision and human-readable time-to-completion estimates.
