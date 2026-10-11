# Changelog

## 0.18-rf

### Fixed
- KNX RF/PL110 over USB: `knx_source_override` no longer replaces the medium settings (medium, domain address) of the USB link with TP1 settings. The override is now only applied to `ft12-cemi`.
- USB without `serial_device` no longer stops silently because no serial port was found.
- Empty `usb_device` now selects the first KNX USB device instead of searching for a device named "null".
- Serial fallback assigned `/dev/ttyS1` incorrectly (`==`).
- XML escaping of option values was wrong with Bash >= 5.2 (`patsub_replacement`).

### Added
- Automatic detection of the KNX USB interface (`KnxUsbProbe`, cEMI local device management): medium (PID 51) and domain address (PID 82 RF / PID 70 PL110) are read from the interface when `usb_medium` / `rf_domain_address` are empty. Configured values take precedence; mismatches are logged as warnings.
- `interface_type: auto` (new default for new installations): uses a KNX USB interface if one is connected, otherwise `ft12-cemi`. Existing configurations keep their value.

### Changed
- Network interface for KNXnet/IP is detected from the default route instead of the fixed `end0`.
- `serial_device` is optional; `/dev/ttyAMA0`, `/dev/ttyS1` and `/dev/ttyAML1` are detected automatically for `ft12-cemi`/`tpuart`.
- Validation of `knx_address`, `client_address_start`, `client_address_count` and `rf_domain_address` (RF: 12, PL110: 4 hex characters); clear error messages in the log.
- `rf_domain_address` is only used for `rf` and `pl110`.
- `rf_domain_address` accepts the ETS notation with separators (e.g. `00FA:5D40C82A`).
- Option values are XML-escaped.
- Tunneling addresses must be in the same area/line as `knx_address` and must not include it.
- If the USB interface reports more than one medium, the add-on stops and asks for `usb_medium` instead of assuming `tp1`.
- `routing: false` is the default for new installations (tunneling is recommended for Home Assistant). Existing configurations keep their value.
- Repository URL points to this fork.

### Tests
- `tests/run_tests.sh`: regression tests for the generated Calimero configuration (all interface types and media).
