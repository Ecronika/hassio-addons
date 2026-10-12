/*
 * KnxUsbProbe – liest per cEMI Local Device Management aus einem KNX-USB-Interface,
 * was das Add-on automatisch erkennen soll: Medium, Domain-Adresse und Seriennummer.
 *
 * Aufruf:  java -cp "/opt/calimero/*:/opt/calimero/probe" KnxUsbProbe [usb_device]
 *          usb_device leer = erstes KNX-USB-Gerät (wie Calimero selbst)
 * Ausgabe: key=value-Zeilen auf stdout (Logging von Calimero geht nach stderr), z. B.
 *          knx_usb_devices=1, device=135e:0122, serial=0072FB00313E,
 *          medium_mask=0x0010, medium=rf, domain=00FA5D40C82A, status=ok
 * Der Exit-Code ist immer 0; das Ergebnis steht in status=ok|no_device|error.
 */
import java.util.HexFormat;
import java.util.Optional;

import tuwien.auto.calimero.KNXException;
import tuwien.auto.calimero.mgmt.LocalDeviceManagementUsb;
import tuwien.auto.calimero.serial.usb.UsbConnection;

public final class KnxUsbProbe {
	private static final int DeviceObject = 0;
	private static final int CemiServerObject = 8;
	private static final int PidSerialNumber = 11;
	private static final int PidMediumType = 51;
	private static final int PidDomainAddress = 70;
	private static final int PidRfDomainAddress = 82;

	// PID_MEDIUM_TYPE (cEMI server object): bit set = medium supported
	private static final int MediumTp1 = 0x02;
	private static final int MediumPl110 = 0x04;
	private static final int MediumRf = 0x10;

	public static void main(final String[] args) {
		final String device = args.length > 0 ? args[0].trim() : "";
		try {
			final int found = UsbConnection.getKnxDevices().size();
			out("knx_usb_devices", Integer.toString(found));
			if (found == 0 && device.isEmpty()) {
				out("status", "no_device");
				return;
			}
			try (var c = new UsbConnection(device); var ldm = new LocalDeviceManagementUsb(c, e -> {}, false)) {
				out("device", c.name());
				read(ldm, DeviceObject, PidSerialNumber).ifPresent(v -> out("serial", hex(v)));

				final Optional<byte[]> maskData = read(ldm, CemiServerObject, PidMediumType);
				final int mask = maskData.map(KnxUsbProbe::unsigned).orElse(0);
				maskData.ifPresent(v -> out("medium_mask", String.format("0x%04X", mask)));
				final String medium = medium(mask);
				if (!medium.isEmpty())
					out("medium", medium);

				if ("rf".equals(medium))
					read(ldm, DeviceObject, PidRfDomainAddress).ifPresent(v -> out("domain", hex(v)));
				else if ("pl110".equals(medium))
					read(ldm, DeviceObject, PidDomainAddress).ifPresent(v -> out("domain", hex(v)));
			}
			out("status", "ok");
		}
		catch (final InterruptedException e) {
			Thread.currentThread().interrupt();
			error(e);
		}
		catch (final Exception | LinkageError e) {
			error(e);
		}
		finally {
			System.out.flush();
			// usb4java event threads must not keep the JVM alive
			Runtime.getRuntime().halt(0);
		}
	}

	// exactly one supported medium -> that medium; none or several -> undetermined
	private static String medium(final int mask) {
		final int known = mask & (MediumTp1 | MediumPl110 | MediumRf);
		switch (known) {
		case MediumTp1: return "tp1";
		case MediumPl110: return "pl110";
		case MediumRf: return "rf";
		default: return "";
		}
	}

	private static Optional<byte[]> read(final LocalDeviceManagementUsb ldm, final int objectType, final int pid)
		throws InterruptedException {
		try {
			final byte[] data = ldm.getProperty(objectType, 1, pid, 1, 1);
			return data != null && data.length > 0 ? Optional.of(data) : Optional.empty();
		}
		catch (final KNXException e) {
			return Optional.empty();
		}
	}

	private static int unsigned(final byte[] data) {
		int v = 0;
		for (final byte b : data)
			v = (v << 8) | (b & 0xff);
		return v;
	}

	private static String hex(final byte[] data) {
		return HexFormat.of().withUpperCase().formatHex(data);
	}

	private static void error(final Throwable e) {
		out("status", "error");
		final String msg = String.valueOf(e.getMessage()).replaceAll("[\\r\\n]+", " ");
		out("error", e.getClass().getSimpleName() + ": " + msg);
	}

	private static void out(final String key, final String value) {
		System.out.println(key + "=" + value);
	}
}
