# Calimero-Patches

Die Patches werden beim Image-Build auf die Quellen von `calimero-server` (Version siehe
`dependencies.sha256`) angewendet. Die daraus kompilierten Klassen liegen in `/opt/calimero/patch`
und stehen im Classpath vor den Jars (`run.sh`: `CALIMERO_CLASSPATH`).

| Patch | Problem | Upstream |
|---|---|---|
| `0001-open-subnet-links-before-server-launch.patch` | `KnxServerGateway.run()` startet die Server-Endpunkte vor dem Öffnen der Subnetz-Links. Verbindet sich ein Client in diesem Zeitfenster (z. B. Home Assistant nach einem Add-on-Neustart), öffnet Calimero den Link ein zweites Mal; bei USB folgt `An interface is already claimed` mit Endlos-Wiederholungen. Der Patch öffnet die Links zuerst. | Issue folgt – Patch entfernen, sobald upstream behoben |

Regressionstest: `tests/race_test.sh <jars> <patch-klassen>` (simuliert ein langsam öffnendes Interface).
