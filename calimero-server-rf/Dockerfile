# Basisimage fest gepinnt (Alpine 3.24, HA base 2026.10.0) – Aktualisierung bewusst per Commit
ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.24-2026.10.0
# hadolint ignore=DL3006
FROM $BUILD_FROM AS build

ENV LANG=C.UTF-8
SHELL ["/bin/ash", "-o", "pipefail", "-c"]
ARG JDK=/usr/lib/jvm/java-21-openjdk

# hadolint ignore=DL3018
RUN apk add --no-cache openjdk21-jdk openjdk21-jmods wget unzip zip git patch \
        build-base linux-headers lockdev cmake libusb-dev eudev-dev

# Schlanke Java-Laufzeit (Calimero, KnxUsbProbe und SLF4J brauchen nur java.base + java.xml)
# hadolint ignore=DL3059
RUN ${JDK}/bin/jlink \
    --add-modules java.base,java.xml \
    --compress zip-6 \
    --strip-debug \
    --no-header-files \
    --no-man-pages \
    --output /opt/jdk

# Java-Bibliotheken – jede Datei wird gegen ihre SHA-256-Prüfsumme geprüft
COPY dependencies.sha256 /tmp/dependencies.sha256
WORKDIR /opt/calimero
RUN while read -r sha url; do \
        file="${url##*/}"; \
        wget -q -O "$file" "$url"; \
        echo "$sha  $file" | sha256sum -c -; \
    done < /tmp/dependencies.sha256 \
    && mv calimero-server-2.6-sources.jar /tmp/

# nrjavaserial (seriell: FT1.2/TPUART) für Alpine/musl neu kompilieren – Quelle per Git-Tag + Commit geprüft
# hadolint ignore=DL3003
RUN git clone -q --depth 1 --branch 5.2.1 https://github.com/NeuronRobotics/nrjavaserial.git /tmp/nrjavaserial \
    && test "$(git -C /tmp/nrjavaserial rev-parse HEAD)" = "5d6d4e6a8ee4d6706e3c7b19467aabccde58f765" \
    && cd /tmp/nrjavaserial/src/main/c \
    && mkdir build \
    && for src in fixup fuserImp SerialImp; do \
        gcc -I./include -I./include/target -I${JDK}/include -I${JDK}/include/linux -O3 -Wall -c -fmessage-length=0 -fPIC -MMD -MP "src/${src}.c" -o "build/${src}.o"; \
    done \
    && mkdir -p /opt/calimero/native/linux/ARM_64/ \
    && g++ -shared -fPIC -nostdlib -o /opt/calimero/native/linux/ARM_64/libNRJavaSerialv8.so build/fixup.o build/fuserImp.o build/SerialImp.o \
    && cd /opt/calimero \
    && zip -q -u nrjavaserial-5.2.1.jar native/linux/ARM_64/libNRJavaSerialv8.so \
    && rm -r native /tmp/nrjavaserial

# libusb4java (USB) für Alpine/musl neu kompilieren – Quelle per Git-Tag + Commit geprüft
# hadolint ignore=DL3003
RUN git clone -q --depth 1 --branch libusb4java-1.3.0 https://github.com/usb4java/libusb4java.git /tmp/libusb4java \
    && test "$(git -C /tmp/libusb4java rev-parse HEAD)" = "2df684b0bb5495276858dcc6c945b0ca2e13a6c5" \
    && mkdir /tmp/libusb4java/build \
    && cd /tmp/libusb4java/build \
    && JAVA_HOME=${JDK} cmake -DCMAKE_POLICY_VERSION_MINIMUM=3.5 .. \
    && make install/strip \
    && mkdir -p /opt/calimero/org/usb4java/linux-aarch64/ \
    && cp /usr/local/lib/libusb4java.so /opt/calimero/org/usb4java/linux-aarch64/ \
    && cd /opt/calimero \
    && zip -q libusb4java-1.3.0-linux-aarch64.jar org/usb4java/linux-aarch64/libusb4java.so \
    && rm -r org /tmp/libusb4java

# Calimero-Patches (siehe patches/README) – gepatchte Klassen liegen im Classpath vor den Jars
COPY patches/ /tmp/patches/
# hadolint ignore=DL3003
RUN mkdir -p /tmp/calimero-src /opt/calimero/patch \
    && cd /tmp/calimero-src \
    && unzip -q /tmp/calimero-server-2.6-sources.jar 'tuwien/auto/calimero/server/gateway/KnxServerGateway.java' \
    && for p in /tmp/patches/*.patch; do patch -p1 < "$p"; done \
    && ${JDK}/bin/javac --release 17 -nowarn -cp "/opt/calimero/*" -d /opt/calimero/patch \
        tuwien/auto/calimero/server/gateway/KnxServerGateway.java

# KnxUsbProbe: liest Medium/Domain-Adresse aus dem KNX-USB-Interface (automatische Erkennung in run.sh)
COPY probe/KnxUsbProbe.java /tmp/probe/
RUN ${JDK}/bin/javac --release 17 -nowarn -cp "/opt/calimero/*" -d /opt/calimero/probe /tmp/probe/KnxUsbProbe.java

# hadolint ignore=DL3006
FROM $BUILD_FROM

ENV LANG=C.UTF-8

# hadolint ignore=DL3018
RUN apk add --no-cache libusb eudev

COPY --from=build /opt/jdk /opt/jdk
COPY --from=build /opt/calimero /opt/calimero

COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
