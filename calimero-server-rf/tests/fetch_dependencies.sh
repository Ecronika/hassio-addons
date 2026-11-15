#!/usr/bin/env bash
# Laedt alle Java-Bibliotheken aus dependencies.sha256 nach <ziel> und prueft die SHA-256-Summen
# (fuer CI und lokale Tests; das Dockerfile macht dasselbe beim Image-Build).
#   tests/fetch_dependencies.sh <zielverzeichnis>
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST=${1:?Zielverzeichnis angeben}
mkdir -p "$DEST"
while read -r sha url; do
    file="${url##*/}"
    [ -s "$DEST/$file" ] || curl -fsSL --retry 5 --retry-delay 3 -o "$DEST/$file" "$url"
    echo "$sha  $DEST/$file" | sha256sum -c --quiet -
done < "$HERE/../dependencies.sha256"
# Quellen-Jar gehoert nicht in den Classpath
mkdir -p "$DEST/sources" && mv -f "$DEST"/*-sources.jar "$DEST/sources/"
echo "OK: $(find "$DEST" -maxdepth 1 -name '*.jar' | wc -l) Jars in $DEST"
