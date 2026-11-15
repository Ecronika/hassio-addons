#!/usr/bin/env bash
# Regressionstest fuer patches/0001 (Startreihenfolge): Ein Client verbindet sich, waehrend der
# Subnetz-Link noch oeffnet (SlowLink, 3 s). Ohne Patch oeffnet Calimero den Link ein zweites Mal
# (bei USB: "interface is already claimed"), mit Patch genau einmal.
#
#   tests/race_test.sh <jar-verzeichnis> <patch-verzeichnis>
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JARS=${1:?Verzeichnis mit Calimero-Jars angeben}
PATCH=${2:?Verzeichnis mit gepatchten Klassen angeben}
JAVA=${JAVA:-java}; JAVAC=${JAVAC:-javac}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

"$JAVAC" --release 17 -nowarn -cp "$JARS/*" -d "$WORK/classes" "$HERE"/race/*.java 2>&1 | grep -v -E 'warning|bad path' || true
cat > "$WORK/server.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<knxServer name="race" friendlyName="race" appData="$WORK">
	<discovery listenNetIf="lo" outgoingNetIf="lo" activate="false" />
	<serviceContainer activate="true" routing="false" networkMonitoring="true" udpPort="13671" listenNetIf="lo">
		<knxAddress type="individual">1.1.0</knxAddress>
		<knxSubnet type="user-supplied" medium="tp1" class="race.SlowLink">x</knxSubnet>
		<additionalAddresses><knxAddress type="individual">1.1.101</knxAddress></additionalAddresses>
	</serviceContainer>
</knxServer>
XML

run() {
    local cp="$WORK/classes:$JARS/*"; [ -n "$1" ] && cp="$1:$cp"
    ( cd "$WORK" && timeout 16 "$JAVA" -cp "$cp" tuwien.auto.calimero.server.Launcher --no-stdin "$WORK/server.xml" 2>&1 &
      timeout 14 "$JAVA" -cp "$WORK/classes:$JARS/*" race.Client 1200 2>&1; wait ) | grep RACETEST
}

result=0
echo "## ohne Patch (erwartet: 2 Oeffnungen = Fehler reproduziert)"
out=$(run ""); echo "$out"
[ "$(grep -c 'RACETEST open #[0-9]* in' <<< "$out")" -ge 2 ] || echo "HINWEIS: Race ohne Patch nicht reproduziert"
echo "## mit Patch (erwartet: 1 Oeffnung, Client verbunden)"
out=$(run "$PATCH"); echo "$out"
if [ "$(grep -c 'RACETEST open #[0-9]* in' <<< "$out")" -eq 1 ] && grep -q 'client connected' <<< "$out"; then
    echo "PASS  race"
else
    echo "FAIL  race"; result=1
fi
exit $result
