# Changelog

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
