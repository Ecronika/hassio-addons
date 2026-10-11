# Home Assistant Add-On: Calimero Server

A KNXnet/IP server (https://github.com/calimero-project/calimero-server) for running your own KNXnet/IP server in software. This add-on can be used for accessing the KNX bus via FT1.2/TPUART serial adapters or USB KNX devices. 

The add-on uses Java 17 (java.base, java.xml); a custom Java runtime is created via jlink. Supported media: TP1, KNX RF and PL110 (USB). nrjavaserial+usb4java needs to be compiled for Alpine with musl, the release jar is updated with this binary.

## Add-On Configuration

The add-on requires the following configuration:
```
knx_address: 1.1.0
client_address_start: 1.1.101
client_address_count: 5
interface_type: auto
routing: false
knx_source_override: true
```

Example for a KNX RF USB interface (tunneling only) – interface, medium and RF domain address are read from the USB interface:
```
knx_address: 1.1.0
client_address_start: 1.1.101
client_address_count: 5
interface_type: auto
routing: false
```
The detected values are shown in the add-on log, e.g. `KNX-USB-Interface erkannt: 135e:0122, serial 0072FB00313E, medium rf, medium_mask 0x0010, domain 00FA5D40C82A`.

`knx_address` of the service container, will be visible in e.g. ETS-tool. If routing is activated, requires a coupler/backbone address (x.y.0 or x.0.0).

`client_address_start` Start address of KNX individual addresses, which are assigned to KNXnet/IP tunneling connections.

`client_address_count` number of KNX individual addresses/possible tunneling connections. The addresses must be in the same area/line as `knx_address`, must not include `knx_address` and must not exceed x.y.255.

`interface_type` can be one of:
* `auto` (default) – use a KNX USB interface if one is connected, otherwise `ft12-cemi`
* `ft12-cemi` for e.g. the [KNX BAOS Module 838 kBerry](https://www.weinzierl.de/index.php/en/all-knx/knx-module-en/knx-baos-module-838-en) 
* `tpuart` for e.g. [TPUART USB Modul](http://shop.busware.de/product_info.php/products_id/59)
* `usb`

`serial_device` (optional) uart device name, only used for `ft12-cemi` and `tpuart`. If empty, the add-on detects `/dev/ttyAMA0`, `/dev/ttyS1` or `/dev/ttyAML1` automatically.

`usb_device` specify the vendorId:productId or vendor name, e.g. siemens; if USB device identifier is left empty, the first found KNX USB device is used

`usb_medium` (optional) KNX medium of the USB interface: `tp1`, `rf` or `pl110`. If empty, the medium is read from the USB interface (fallback `tp1` if the interface cannot be queried). If the interface reports more than one medium, `usb_medium` must be set.

`rf_domain_address` (optional) domain address for `rf` (12 hex characters, 6 bytes, e.g. `000000004b01`; the ETS notation `00FA:5D40C82A` from the properties of the RF line can be pasted as is) or `pl110` (4 hex characters, 2 bytes). Ignored for `tp1`. If empty, the domain address stored in the USB interface is used. A configured value always takes precedence; a different value in the interface is reported as a warning.

`routing` if true activate KNX IP routing (multicast), if false routing is disabled (default). For Home Assistant, tunneling (`routing: false`) is the recommended connection type.

`knx_source_override` if true activate static default source address assignment (required for devices that don't like the source address to be changed or set, e.g. for the Weinzierl kBerry). Only applied to `ft12-cemi`; ignored for `tpuart` and `usb`.

The network interface for KNXnet/IP is detected automatically from the default route (e.g. `end0`, `eth0`, `wlan0`).

`loglevel` is optional and can be one of the slf4j log levels. It logs everything to standard output. 

`expose_date` Cyclically transmit date (11.001) to this group address using the default time zone

`expose_time` Cyclically transmit time (10.001) to this group address using the default time zone

`expose_datetime` Cyclically transmit date+time (19.001) to this group address using the default time zone

`timeserver_expiration` Expiration timeout specifies tx cycle in seconds, e.g., 1 min = 60, 1 hour = 3600, 12 hours = 43200 

## Configure serial communication 

### Raspberry Pi 3 / 4
 
In order to use the KNX BAOS Module 838 kBerry the serial port on the Raspberry Pi needs to be enabled in `config.txt` (which is by default occupied by the bluetooth module).

Raspberry Pi 3
```
dtoverlay=pi3-disable-bt
```

[Raspberry Pi 4](https://github.com/knxd/knxd/issues/469#issuecomment-723936998)

```
dtoverlay=disable-bt
dtoverlay=uart0
[all]
uart0=on
```

### ODROID C4

The correct device for the serial port is '/dev/ttyAML1' (the device is pin compatible to the Raspberry Pi)

ODROID support required to add a property to the run command for the serial port 'detection' to work.
```
java -Dgnu.io.rxtx.SerialPorts=/dev/ttyAMA0 ...
```

## Links

* Enable SSH access to the host: https://developers.home-assistant.io/docs/operating-system/debugging/
* Add RXTX unkown UART device names via property: https://angryelectron.com/rxtx-on-raspbian/                                                                                           
* usb4java also needs to be compiled for musl on Alpine: http://usb4java.org/nativelibs.html
