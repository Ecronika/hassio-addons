#!/usr/bin/with-contenv bashio
# shellcheck shell=bash
# Calimero KNXnet/IP Server – Start-Skript
# Erzeugt /etc/server-config.xml aus den Add-on-Optionen und startet Calimero.
# Unterstuetzt alle Zugangswege (ft12-cemi, tpuart, usb) und Medien (tp1, rf, pl110).

CONFIG_FILE="${CALIMERO_CONFIG_FILE:-/etc/server-config.xml}"

# --- Hilfsfunktionen ---------------------------------------------------------

# Liefert den Optionswert oder einen leeren String, wenn die Option nicht gesetzt ist
# (bashio::config gibt fuer fehlende Optionen den String "null" zurueck).
config_value() {
    if bashio::config.is_empty "$1"; then
        echo ""
    else
        bashio::config "$1"
    fi
}

# Maskiert Sonderzeichen fuer XML-Attribute und -Texte.
xml_escape() {
    local s=$1
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    s=${s//\"/&quot;}
    printf '%s' "$s"
}

# Prueft eine KNX-Einzeladresse (Bereich 0-15, Linie 0-15, Teilnehmer 0-255).
is_individual_address() {
    [[ "$1" =~ ^([0-9]|1[0-5])\.([0-9]|1[0-5])\.([0-9]{1,3})$ ]] && [ "${BASH_REMATCH[3]}" -le 255 ]
}

# --- Optionen einlesen -------------------------------------------------------

KNX_ADDRESS=$(bashio::config 'knx_address')
CLIENT_ADDRESS_START=$(bashio::config 'client_address_start')
CLIENT_ADDRESS_COUNT=$(bashio::config 'client_address_count')
INTERFACE_TYPE=$(bashio::config 'interface_type')
SERIAL_DEVICE=$(config_value 'serial_device')
USB_DEVICE=$(config_value 'usb_device')
ROUTING=$(bashio::config 'routing')

# KNX-Medium fuer USB: tp1 | rf | pl110 – leer = automatisch vom Interface lesen
USB_MEDIUM=$(config_value 'usb_medium')

# --- Plausibilitaetspruefungen -----------------------------------------------

if ! is_individual_address "$KNX_ADDRESS"; then
    bashio::exit.nok "knx_address '${KNX_ADDRESS}' ist keine gueltige KNX-Einzeladresse (z. B. 1.1.0)."
fi
if ! is_individual_address "$CLIENT_ADDRESS_START"; then
    bashio::exit.nok "client_address_start '${CLIENT_ADDRESS_START}' ist keine gueltige KNX-Einzeladresse (z. B. 1.1.101)."
fi
KNX_ADDRESS_PREFIX=$(echo "$CLIENT_ADDRESS_START" | cut -d'.' -f 1-2)
START_OCTET=$(echo "$CLIENT_ADDRESS_START" | cut -d'.' -f 3)
LAST_OCTET=$((START_OCTET + CLIENT_ADDRESS_COUNT - 1))
if [ "$CLIENT_ADDRESS_COUNT" -gt 0 ] && [ "$LAST_OCTET" -gt 255 ]; then
    bashio::exit.nok "client_address_start ${CLIENT_ADDRESS_START} + client_address_count ${CLIENT_ADDRESS_COUNT} ueberschreitet ${KNX_ADDRESS_PREFIX}.255."
fi
if bashio::var.true "$ROUTING" && [[ ! "$KNX_ADDRESS" =~ \.0$ ]]; then
    bashio::log.warning "Routing ist aktiv, knx_address ${KNX_ADDRESS} ist aber keine Koppler-/Backbone-Adresse (x.y.0 bzw. x.0.0)."
fi

RF_DOMAIN_ADDRESS_RAW=$(config_value 'rf_domain_address')
# Trennzeichen entfernen, damit die ETS-Schreibweise (z. B. 00FA:5D40C82A) direkt uebernommen werden kann
RF_DOMAIN_ADDRESS=${RF_DOMAIN_ADDRESS_RAW//[:. -]/}

# --- KNX-USB-Interface automatisch erkennen ----------------------------------
# KnxUsbProbe liest per cEMI Local Device Management Medium, Domain-Adresse und
# Seriennummer aus dem Interface. Konfigurierte Optionen haben immer Vorrang.

run_usb_probe() {
    if [ -n "${CALIMERO_PROBE_OUTPUT+x}" ]; then   # Testumgebung
        printf '%b\n' "$CALIMERO_PROBE_OUTPUT"
        return
    fi
    timeout 30 /opt/jdk/bin/java -cp "/opt/calimero/*:/opt/calimero/probe" KnxUsbProbe "$1" 2>/dev/null || true
}

probe_value() {
    printf '%s\n' "$PROBE_RESULT" | sed -n "s/^$1=//p" | head -n 1
}

PROBE_RESULT=""
PROBE_STATUS=""
if [ "$INTERFACE_TYPE" = "usb" ] || [ "$INTERFACE_TYPE" = "auto" ]; then
    PROBE_RESULT=$(run_usb_probe "$USB_DEVICE")
    PROBE_STATUS=$(probe_value status)
    case "$PROBE_STATUS" in
        ok)
            PROBE_SUMMARY="$(probe_value device)"
            for key in serial medium medium_mask domain; do
                if [ -n "$(probe_value "$key")" ]; then
                    PROBE_SUMMARY="${PROBE_SUMMARY}, ${key} $(probe_value "$key")"
                fi
            done
            bashio::log.info "KNX-USB-Interface erkannt: ${PROBE_SUMMARY}"
            ;;
        no_device)
            bashio::log.info "Kein KNX-USB-Interface gefunden."
            ;;
        *)
            bashio::log.warning "KNX-USB-Interface konnte nicht abgefragt werden: $(probe_value error)"
            ;;
    esac
fi

if [ "$INTERFACE_TYPE" = "auto" ]; then
    if [ "$PROBE_STATUS" = "ok" ] || [ "$(probe_value knx_usb_devices)" -gt 0 ] 2>/dev/null; then
        INTERFACE_TYPE="usb"
        bashio::log.info "Zugangsweg automatisch erkannt: usb"
    else
        INTERFACE_TYPE="ft12-cemi"
        bashio::log.warning "Kein KNX-USB-Interface – verwende ft12-cemi (serielle Schnittstelle). Fuer TPUART interface_type: tpuart setzen."
    fi
fi

if [ "$INTERFACE_TYPE" = "usb" ]; then
    DETECTED_MEDIUM=$(probe_value medium)
    DETECTED_DOMAIN=$(probe_value domain)
    if [ -z "$USB_MEDIUM" ]; then
        if [ -n "$DETECTED_MEDIUM" ]; then
            USB_MEDIUM="$DETECTED_MEDIUM"
            bashio::log.info "Medium automatisch erkannt: ${USB_MEDIUM}"
        else
            USB_MEDIUM="tp1"
            bashio::log.warning "Medium nicht ermittelbar – verwende tp1. Bei RF/PL110 usb_medium setzen."
        fi
    elif [ -n "$DETECTED_MEDIUM" ] && [ "$DETECTED_MEDIUM" != "$USB_MEDIUM" ]; then
        bashio::log.warning "usb_medium ist ${USB_MEDIUM}, das Interface meldet aber ${DETECTED_MEDIUM}."
    fi
    if [ "$USB_MEDIUM" = "$DETECTED_MEDIUM" ] && [ -n "$DETECTED_DOMAIN" ]; then
        if [ -z "$RF_DOMAIN_ADDRESS" ]; then
            RF_DOMAIN_ADDRESS="$DETECTED_DOMAIN"
            RF_DOMAIN_ADDRESS_RAW="$DETECTED_DOMAIN"
            bashio::log.info "Domain-Adresse automatisch erkannt: ${RF_DOMAIN_ADDRESS}"
        elif [ "${RF_DOMAIN_ADDRESS^^}" != "${DETECTED_DOMAIN^^}" ]; then
            bashio::log.warning "rf_domain_address ${RF_DOMAIN_ADDRESS} weicht von der im Interface gespeicherten Domain ${DETECTED_DOMAIN} ab – verwende den konfigurierten Wert."
        fi
    fi
fi

# Domain-Adresse nur fuer offene Medien (RF: 6 Byte, PL110: 2 Byte)
ADD_DOMAIN_ADDRESS=""
if [ "$INTERFACE_TYPE" = "usb" ]; then
    case "$USB_MEDIUM" in
        rf)
            if [ -n "$RF_DOMAIN_ADDRESS" ]; then
                [[ "$RF_DOMAIN_ADDRESS" =~ ^[0-9A-Fa-f]{12}$ ]] \
                    || bashio::exit.nok "rf_domain_address '${RF_DOMAIN_ADDRESS_RAW}' ungueltig: Fuer KNX RF sind 12 Hex-Zeichen (6 Byte) erforderlich, z. B. 000000004b01."
            else
                bashio::log.warning "Keine RF-Domain-Adresse gesetzt – Calimero verwendet die Broadcast-Domain. Domain-Adresse der RF-Linie aus der ETS eintragen."
            fi
            ;;
        pl110)
            if [ -n "$RF_DOMAIN_ADDRESS" ]; then
                [[ "$RF_DOMAIN_ADDRESS" =~ ^[0-9A-Fa-f]{4}$ ]] \
                    || bashio::exit.nok "rf_domain_address '${RF_DOMAIN_ADDRESS_RAW}' ungueltig: Fuer KNX PL110 sind 4 Hex-Zeichen (2 Byte) erforderlich."
            fi
            ;;
        *)
            if [ -n "$RF_DOMAIN_ADDRESS" ]; then
                bashio::log.warning "rf_domain_address wird ignoriert, da das Medium ${USB_MEDIUM} keine Domain-Adresse verwendet."
                RF_DOMAIN_ADDRESS=""
            fi
            ;;
    esac
    if [ -n "$RF_DOMAIN_ADDRESS" ]; then
        ADD_DOMAIN_ADDRESS=" domainAddress=\"${RF_DOMAIN_ADDRESS}\""
    fi
fi

# --- Serielle Schnittstelle (nur fuer ft12-cemi / tpuart) --------------------

if [ "$INTERFACE_TYPE" = "ft12-cemi" ] || [ "$INTERFACE_TYPE" = "tpuart" ]; then
    if [ -z "$SERIAL_DEVICE" ]; then
        # Raspberry Pi 3/4/5 | Asus Tinker Board S | ODROID C4
        for candidate in ${CALIMERO_SERIAL_CANDIDATES:-/dev/ttyAMA0 /dev/ttyS1 /dev/ttyAML1}; do
            if [ -e "$candidate" ]; then
                SERIAL_DEVICE="$candidate"
                break
            fi
        done
        if [ -z "$SERIAL_DEVICE" ]; then
            bashio::exit.nok "Keine serielle Schnittstelle gefunden (geprueft: /dev/ttyAMA0, /dev/ttyS1, /dev/ttyAML1). Option serial_device setzen."
        fi
        bashio::log.info "Serielle Schnittstelle automatisch erkannt: ${SERIAL_DEVICE}"
    fi
fi

# Quelladress-Override nur fuer FT1.2 (z. B. Weinzierl kBerry). Bei USB setzt Calimero
# fuer TP1 ohnehin 0.0.0; bei RF/PL110 wuerde der Override die Medium-Einstellungen
# (Medium, Domain-Adresse) durch TP1-Einstellungen ersetzen.
ADD_KNX_SOURCE_OVERRIDE=""
if bashio::config.true 'knx_source_override'; then
    if [ "$INTERFACE_TYPE" = "ft12-cemi" ]; then
        ADD_KNX_SOURCE_OVERRIDE=" knxAddress=\"0\""
    else
        bashio::log.info "knx_source_override gilt nur fuer ft12-cemi und wird fuer ${INTERFACE_TYPE} ignoriert."
    fi
fi

# --- Netzwerk-Interface automatisch ermitteln --------------------------------

LISTEN_NETIF=$(ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}' || true)
ADD_LISTEN_NETIF=""
if [ -n "$LISTEN_NETIF" ]; then
    ADD_LISTEN_NETIF=" listenNetIf=\"$(xml_escape "$LISTEN_NETIF")\""
    bashio::log.info "Netzwerk-Interface automatisch erkannt (Default-Route): ${LISTEN_NETIF}"
else
    bashio::log.warning "Keine Default-Route gefunden – Calimero verwendet das Standard-Netzwerkinterface des Hosts."
fi

ADD_TIMESERVER_EXPIRATION=""
if bashio::config.exists 'timeserver_expiration'; then
    ADD_TIMESERVER_EXPIRATION="
				<expiration timeout=\"$(bashio::config 'timeserver_expiration')\" />"
fi

# --- XML erzeugen -------------------------------------------------------------

CONFIG_XML="<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!-- Calimero server settings (required for startup) -->
<knxServer name=\"knx-server\" friendlyName=\"Hass OS KNXnet/IP Server\">
	<!-- KNXnet/IP search & discovery -->
	<discovery listenNetIf=\"all\" outgoingNetIf=\"all\" activate=\"true\" />
	<!-- Provides the KNXnet/IP-side configuration for access to one KNX subnet -->
	<serviceContainer activate=\"true\" routing=\"$ROUTING\" networkMonitoring=\"true\"
		udpPort=\"3671\"${ADD_LISTEN_NETIF}>
		<knxAddress type=\"individual\">$KNX_ADDRESS</knxAddress>"
if [ "$INTERFACE_TYPE" = "ft12-cemi" ]; then
CONFIG_XML="$CONFIG_XML
		<knxSubnet type=\"ft12-cemi\" medium=\"tp1\"$ADD_KNX_SOURCE_OVERRIDE>$(xml_escape "$SERIAL_DEVICE")</knxSubnet>"
fi
if [ "$INTERFACE_TYPE" = "tpuart" ]; then
CONFIG_XML="$CONFIG_XML
		<knxSubnet type=\"tpuart\" medium=\"tp1\">$(xml_escape "$SERIAL_DEVICE")</knxSubnet>"
fi
if [ "$INTERFACE_TYPE" = "usb" ]; then
CONFIG_XML="$CONFIG_XML
		<knxSubnet type=\"usb\" medium=\"$USB_MEDIUM\"$ADD_DOMAIN_ADDRESS>$(xml_escape "$USB_DEVICE")</knxSubnet>"
fi
CONFIG_XML="$CONFIG_XML
		<!-- KNX group address filter applied by the server for this service container (optional) -->
		<groupAddressFilter>
		</groupAddressFilter>
		<!-- Additional KNX individual addresses assigned to client KNXnet/IP connections (optional) -->
		<additionalAddresses>"
# Add new KNX Client Address elements
i=1
while [ "$i" -le "$CLIENT_ADDRESS_COUNT" ]; do
CURRENT_OCTET=$((START_OCTET + i - 1))
CONFIG_XML="$CONFIG_XML
			<knxAddress type=\"individual\">$KNX_ADDRESS_PREFIX.$CURRENT_OCTET</knxAddress>"
i=$(( i + 1 ))
done
CONFIG_XML="$CONFIG_XML
		</additionalAddresses>"
if bashio::config.exists 'expose_date' || bashio::config.exists 'expose_time' || bashio::config.exists 'expose_datetime'; then
    CONFIG_XML="$CONFIG_XML
		<timeServer>"
    if bashio::config.exists 'expose_date'; then
    CONFIG_XML="$CONFIG_XML
			<datapoint stateBased=\"true\" name=\"current date\" dptID=\"11.001\" priority=\"low\">
				<knxAddress type=\"group\">$(xml_escape "$(bashio::config 'expose_date')")</knxAddress>$ADD_TIMESERVER_EXPIRATION
			</datapoint>"
    fi
    if bashio::config.exists 'expose_time'; then
    CONFIG_XML="$CONFIG_XML
			<datapoint stateBased=\"true\" name=\"current time\" dptID=\"10.001\" priority=\"low\">
				<knxAddress type=\"group\">$(xml_escape "$(bashio::config 'expose_time')")</knxAddress>$ADD_TIMESERVER_EXPIRATION
			</datapoint>"
    fi
    if bashio::config.exists 'expose_datetime'; then
    CONFIG_XML="$CONFIG_XML
			<datapoint stateBased=\"true\" name=\"current datetime\" dptID=\"19.001\" priority=\"low\">
				<knxAddress type=\"group\">$(xml_escape "$(bashio::config 'expose_datetime')")</knxAddress>$ADD_TIMESERVER_EXPIRATION
			</datapoint>"
    fi
    CONFIG_XML="$CONFIG_XML
		</timeServer>"
fi
CONFIG_XML="$CONFIG_XML
	</serviceContainer>
	<!-- Add next service container (optional) -->
</knxServer>"

echo "$CONFIG_XML" > "$CONFIG_FILE"

cat "$CONFIG_FILE"

# --- Start --------------------------------------------------------------------

JAVA_OPTS=()
if ! bashio::config.is_empty 'loglevel' && ! bashio::config.equals 'loglevel' 'off'; then
    JAVA_OPTS+=("-Dorg.slf4j.simpleLogger.defaultLogLevel=$(bashio::config 'loglevel')")
fi
if [ -n "$SERIAL_DEVICE" ]; then
    JAVA_OPTS+=("-Dgnu.io.rxtx.SerialPorts=${SERIAL_DEVICE}")
fi

if [ -n "${CALIMERO_DRY_RUN:-}" ]; then
    echo "DRY RUN: /opt/jdk/bin/java -XX:+UseShenandoahGC -cp /opt/calimero/* ${JAVA_OPTS[*]} tuwien.auto.calimero.server.Launcher --no-stdin ${CONFIG_FILE}"
    exit 0
fi

exec /opt/jdk/bin/java -XX:+UseShenandoahGC -cp "/opt/calimero/*" "${JAVA_OPTS[@]}" tuwien.auto.calimero.server.Launcher --no-stdin "$CONFIG_FILE"
