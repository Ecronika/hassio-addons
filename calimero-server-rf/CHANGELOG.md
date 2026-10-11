# Changelog

## 0.18-rf

### Fixed
- KNX RF/PL110 over USB: `knx_source_override` no longer replaces the medium settings (medium, domain address) of the USB link with TP1 settings. The override is now only applied to `ft12-cemi`.
- USB without `serial_device` no longer stops silently because no serial port was found.
- Empty `usb_device` now selects the first KNX USB device instead of searching for a device named "null".
- Serial fallback assigned `/dev/ttyS1` incorrectly (`==`).

### Changed
- Network interface for KNXnet/IP is detected from the default route instead of the fixed `end0`.
- `serial_device` is optional; `/dev/ttyAMA0`, `/dev/ttyS1` and `/dev/ttyAML1` are detected automatically for `ft12-cemi`/`tpuart`.
- Validation of `knx_address`, `client_address_start`, `client_address_count` and `rf_domain_address` (RF: 12, PL110: 4 hex characters); clear error messages in the log.
- `rf_domain_address` is only used for `rf` and `pl110`.
- Option values are XML-escaped.
- Repository URL points to this fork.

### Added
- `tests/run_tests.sh`: regression tests for the generated Calimero configuration (all interface types and media).
