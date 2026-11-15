# Changelog

## 0.19-rf (in development)

### Changed
- Calimero 2.5.1 → **2.6** (`calimero-usb` 2.6, SLF4J 2.0.17), Java runtime 21 (jlink, `java.base` + `java.xml`).
- `commons-lang3` 3.8.1 → 3.21.0 (CVE-2025-48924).
- All downloaded libraries are verified by SHA-256 (`dependencies.sha256`); nrjavaserial and libusb4java sources are verified by Git commit.
- Base image pinned to `aarch64-base:3.24-2026.10.0` instead of `latest`.
- FT1.2 cEMI is configured as `type="ft12" format="cemi"` (Calimero 2.6 no longer accepts `ft12-cemi`; the option value `ft12-cemi` is unchanged).
- Calimero starts with a fresh interface object server state on every start (`appData` in `/tmp`).

### Fixed
- Startup race: if a client (e.g. Home Assistant) connected while Calimero was still opening the USB interface, a second link was opened (`An interface is already claimed`, endless retries). The subnet link is now opened before the server endpoints start (`patches/0001`).
- Time server group addresses (`expose_*`) are validated; invalid values stopped Calimero at startup.

### Tests
- GitHub Actions: shellcheck, hadolint, regression tests, Calimero config acceptance test, race test, KnxUsbProbe, aarch64 image build.

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
