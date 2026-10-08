SUMMARY = "QT Py UART telemetry bridge for the Altera sensor board (bring-up/demo)"
DESCRIPTION = "Reads line-based ASCII telemetry (KEY:VALUE tokens) from the \
Altera sensor board's QT Py MCU over the Pi-header UART (/dev/ttyS1 = HPS UART1, \
FPGA pin-muxed to AF24/AG24). The token->ExternalSensor mapping is data-driven, \
loaded from /etc/qtpy-uart-bridge.conf (TOKEN path scale offset min max), so new \
QT Py values are surfaced by adding a config line plus an entity-manager \
ExternalSensor entry, with no recompile. By default the potentiometer knob is \
scaled to 0-100% and mirrored onto the Heater_PWM ExternalSensor (humidity \
namespace) so it appears on the Redfish dashboard; a /run/qtpy/heater.json debug \
dump is also written. Tolerant parser so the QT Py line format can evolve; see \
qtpy-uart-protocol.md. Test now by driving /dev/ttyS1 from a Raspberry Pi."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# libsystemd (sd-bus) is used to push the slider onto the ExternalSensor.
DEPENDS = "systemd"

inherit systemd

# file:// sources unpack directly into ${UNPACKDIR}
S = "${UNPACKDIR}"

SRC_URI = " \
    file://qtpy-uart-bridge.c \
    file://qtpy-uart-bridge.conf \
    file://qtpy-uart-bridge.service \
    "

SYSTEMD_SERVICE:${PN} = "qtpy-uart-bridge.service"
# Enabled by default: it blocks harmlessly on /dev/ttyS1 until bytes arrive, so
# it is safe to ship before the sensor board exists (drive ttyS1 from a Pi to
# emulate the QT Py).
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_compile() {
    ${CC} ${CFLAGS} ${LDFLAGS} -o qtpy-uart-bridge \
        ${UNPACKDIR}/qtpy-uart-bridge.c -lsystemd
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 qtpy-uart-bridge ${D}${bindir}/qtpy-uart-bridge

    install -d ${D}${sysconfdir}
    install -m 0644 ${UNPACKDIR}/qtpy-uart-bridge.conf \
        ${D}${sysconfdir}/qtpy-uart-bridge.conf

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/qtpy-uart-bridge.service \
        ${D}${systemd_system_unitdir}/qtpy-uart-bridge.service
}

CONFFILES:${PN} = "${sysconfdir}/qtpy-uart-bridge.conf"

FILES:${PN} = " \
    ${bindir}/qtpy-uart-bridge \
    ${sysconfdir}/qtpy-uart-bridge.conf \
    ${systemd_system_unitdir}/qtpy-uart-bridge.service \
    "
