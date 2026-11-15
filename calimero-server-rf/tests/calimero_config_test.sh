#!/usr/bin/env bash
# Startet den Calimero-Server kurz mit jeder erwarteten XML aus tests/expected/ und prueft,
# dass Calimero die Konfiguration akzeptiert (keine KNXMLException, Server-Endpunkte starten).
# Hardware ist nicht noetig: USB/seriell schlagen erwartungsgemaess fehl und werden im
# Hintergrund wiederholt.
#
#   tests/calimero_config_test.sh <jar-verzeichnis> [patch-verzeichnis]
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JARS=${1:?Verzeichnis mit Calimero-Jars angeben}
PATCH=${2:-}
CP="$JARS/*"; [ -n "$PATCH" ] && CP="$PATCH:$CP"
JAVA=${JAVA:-java}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

SKIP=${SKIP:-xml-special-chars}
pass=0; fail=0; port=23671
for xml in "$HERE"/expected/*.xml; do
    name=$(basename "$xml" .xml)
    # reiner Escaping-Test mit absichtlich unbrauchbarem Geraetenamen
    case " $SKIP " in *" $name "*) echo "SKIP  $name"; continue ;; esac
    port=$((port + 1))
    # lokales Interface/Port statt end0/3671, Platzhalterpfade unkritisch
    mkdir -p "$WORK/$name"
    sed -e 's/listenNetIf="[^"]*"/listenNetIf="lo"/' -e "s/udpPort=\"3671\"/udpPort=\"$port\"/" \
        -e "s#@TMP@#$WORK/$name#g" "$xml" > "$WORK/$name.xml"
    if ! grep -q 'listenNetIf="lo"' "$WORK/$name.xml"; then
        sed -i "s/udpPort=\"$port\">/udpPort=\"$port\" listenNetIf=\"lo\">/" "$WORK/$name.xml"
    fi
    (cd "$WORK/$name" && timeout 8 "$JAVA" -cp "$CP" tuwien.auto.calimero.server.Launcher --no-stdin "$WORK/$name.xml" > "$WORK/$name.log" 2>&1)
    if grep -qE 'KNXMLException|Exception in thread "main"|NoClassDefFoundError|cannot launch' "$WORK/$name.log" \
        || ! grep -q 'control endpoint .* is up and running' "$WORK/$name.log"; then
        echo "FAIL  $name"; grep -vE '^\s+at ' "$WORK/$name.log" | head -8 | sed 's/^/      /'; fail=$((fail + 1))
    else
        echo "PASS  $name"; pass=$((pass + 1))
    fi
done
echo "----"
echo "$pass bestanden, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
