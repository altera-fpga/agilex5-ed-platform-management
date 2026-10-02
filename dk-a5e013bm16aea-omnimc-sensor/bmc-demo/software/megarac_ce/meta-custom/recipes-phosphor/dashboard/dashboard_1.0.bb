SUMMARY = "Custom live Redfish chassis dashboard served by bmcweb"
DESCRIPTION = "Installs the auto-refreshing chassis dashboard into the bmcweb web \
root so it is served same-origin at https://<bmc>/dashboard/ after boot. It polls \
Redfish on a timer and renders live values + sparklines, so no manual refresh, no \
separate web server, and no CORS config are needed (it shares bmcweb's origin and \
session cookie). bmcweb recursively scans /usr/share/www at startup and registers \
a route per file; an index.html in a subdir is served at that subdir's path. The \
dashboard sources are kept in this recipe's files/ dir (see README.md)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit allarch

# Everything ships same-origin because bmcweb's Content-Security-Policy
# (style-src 'self'; script-src 'self'; img-src 'self') blocks inline CSS/JS
# and CDNs. Chart.js is vendored locally for the sparklines; the Altera wordmark
# is inlined as <svg> in index.html (no external image fetch needed).
SRC_URI = " \
    file://index.html \
    file://dashboard.css \
    file://dashboard.js \
    file://chart.umd.min.js \
    file://deploy-dashboard.sh \
    file://CUSTOMIZE.md \
    "

# file:// sources unpack directly into ${UNPACKDIR}
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${datadir}/www/dashboard
    install -m 0644 ${UNPACKDIR}/index.html \
        ${D}${datadir}/www/dashboard/index.html
    install -m 0644 ${UNPACKDIR}/dashboard.css \
        ${D}${datadir}/www/dashboard/dashboard.css
    install -m 0644 ${UNPACKDIR}/dashboard.js \
        ${D}${datadir}/www/dashboard/dashboard.js
    install -m 0644 ${UNPACKDIR}/chart.umd.min.js \
        ${D}${datadir}/www/dashboard/chart.umd.min.js

    # On-board deploy helper for pushing edited dashboard files to a running BMC.
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/deploy-dashboard.sh \
        ${D}${bindir}/deploy-dashboard

    # Front-end customization guide (not under the web root; a reference doc).
    install -d ${D}${datadir}/dashboard
    install -m 0644 ${UNPACKDIR}/CUSTOMIZE.md \
        ${D}${datadir}/dashboard/CUSTOMIZE.md
}

FILES:${PN} = " \
    ${datadir}/www/dashboard \
    ${bindir}/deploy-dashboard \
    ${datadir}/dashboard \
    "

RDEPENDS:${PN} = "bmcweb"
