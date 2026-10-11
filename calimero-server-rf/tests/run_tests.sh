#!/usr/bin/env bash
# Regressionstest fuer run.sh: erzeugt die Calimero-XML fuer alle Testfaelle mit
# echtem bashio (Supervisor-API gemockt) und vergleicht sie mit tests/expected/.
#
#   tests/run_tests.sh            Tests ausfuehren
#   tests/run_tests.sh --update   Erwartete Ergebnisse neu schreiben (danach Diff pruefen!)
#
# Umgebung: BASHIO_LIB=/pfad/zu/bashio/lib (sonst wird bashio von GitHub geklont),
#           RUN_SH=/pfad/zu/run.sh (Default: ../run.sh)
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_SH=${RUN_SH:-$HERE/../run.sh}
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if [ -z "${BASHIO_LIB:-}" ]; then
    git clone -q --depth 1 https://github.com/hassio-addons/bashio.git "$WORK/bashio" || exit 2
    BASHIO_LIB="$WORK/bashio/lib"
fi

# ip-Mock: gibt MOCK_IP_ROUTE aus (Default: Raspberry Pi mit HAOS >= 11)
mkdir -p "$WORK/bin"
cat > "$WORK/bin/ip" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_IP_ROUTE-default via 192.168.1.1 dev end0 proto dhcp src 192.168.1.10 metric 100}"
EOF
chmod +x "$WORK/bin/ip"

mkdir -p "$HERE/expected"
pass=0; fail=0
for options in "$HERE"/cases/*.json; do
    name=$(basename "$options" .json)
    tmp="$WORK/$name"; mkdir -p "$tmp"
    out="$tmp/server-config.xml"; log="$tmp/log.txt"

    (
        export PATH="$WORK/bin:$PATH" CALIMERO_DRY_RUN=1 CALIMERO_CONFIG_FILE="$out"
        export OPTIONS_FILE="$options" BASHIO_LIB RUN_SH
        unset MOCK_IP_ROUTE CALIMERO_SERIAL_CANDIDATES TOUCH
        if [ -f "$HERE/cases/$name.env" ]; then
            # shellcheck disable=SC1090
            source <(sed "s#@TMP@#$tmp#g" "$HERE/cases/$name.env")
            export CALIMERO_SERIAL_CANDIDATES
            [ -n "${MOCK_IP_ROUTE+x}" ] && export MOCK_IP_ROUTE
            [ -n "${TOUCH:-}" ] && touch "$TOUCH"
        fi
        bash -c '
            source "$BASHIO_LIB/bashio.sh"
            bashio::app.config() { cat "$OPTIONS_FILE"; }
            source "$RUN_SH"
        '
    ) > "$log" 2>&1
    rc=$?

    if [ -f "$HERE/expected/$name.err" ] || [[ "$name" == err-* ]]; then
        expected_text=$(cat "$HERE/expected/$name.err" 2>/dev/null)
        if [ "$UPDATE" = 1 ]; then
            grep -m1 'FATAL' "$log" | sed 's/.*FATAL: //; s/\x1b\[[0-9;]*m//g' > "$HERE/expected/$name.err"
            echo "UPDATE $name"; continue
        fi
        if [ "$rc" -ne 0 ] && grep -qF -- "$expected_text" "$log"; then
            echo "PASS  $name"; pass=$((pass + 1))
        else
            echo "FAIL  $name (rc=$rc, erwartet Fehler: $expected_text)"; sed 's/^/      /' "$log"; fail=$((fail + 1))
        fi
        continue
    fi

    # Pfade aus dem Testverzeichnis neutralisieren
    [ -f "$out" ] && sed -i "s#$tmp#@TMP@#g" "$out"
    if [ "$rc" -ne 0 ] || [ ! -f "$out" ]; then
        echo "FAIL  $name (rc=$rc)"; sed 's/^/      /' "$log"; fail=$((fail + 1)); continue
    fi
    if command -v xmllint >/dev/null && ! xmllint --noout "$out" 2>"$tmp/xmllint.txt"; then
        echo "FAIL  $name (XML nicht wohlgeformt)"; sed 's/^/      /' "$tmp/xmllint.txt"; fail=$((fail + 1)); continue
    fi
    if [ "$UPDATE" = 1 ]; then
        cp "$out" "$HERE/expected/$name.xml"; echo "UPDATE $name"; continue
    fi
    if diff -u "$HERE/expected/$name.xml" "$out" > "$tmp/diff.txt"; then
        echo "PASS  $name"; pass=$((pass + 1))
    else
        echo "FAIL  $name"; sed 's/^/      /' "$tmp/diff.txt"; fail=$((fail + 1))
    fi
done

echo "----"
echo "$pass bestanden, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
