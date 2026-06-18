# Changelog

## 1.1.0 - 2026-06-19

- Added detailed memory breakdown: Wired, Compressed, Purgeable, Active, Swap.
- Added memory pressure assessment (normal/light/moderate/heavy) with weighted scoring.
- Added I/O rate tracking: page-ins/sec and swap-ins/sec.
- Added Chinese optimization tips generated dynamically from system state.
- Added top 8 processes ranked by resident memory usage.
- Expanded popover to 420px to accommodate new analysis panel.
- Added MemoryPressure and analysis tests.

## 1.0.1 - 2026-06-19

- Added single-instance protection (runtime check + LSMultipleInstancesProhibited).
- Migrated to pure SPM build system, removed XcodeGen dependency.
- Removed duplicate source code directories (SystemPulse/, SystemPulseTests/).
- Simplified CI to use `swift build` + `swift test`.
- Added percent formatting and overall level tests.
- Updated README with SPM build instructions.

## 1.0.0 - 2026-06-14

- Added real-time CPU and memory monitoring in the macOS menu bar.
- Added a bidirectional dual-chamber gauge.
- Added four usage levels: green, orange, red, and deep red.
- Added 60-sample history charts and CPU/memory breakdowns.
- Added configurable refresh intervals and launch-at-login support.
- Added a Chinese interface and accessibility labels.
