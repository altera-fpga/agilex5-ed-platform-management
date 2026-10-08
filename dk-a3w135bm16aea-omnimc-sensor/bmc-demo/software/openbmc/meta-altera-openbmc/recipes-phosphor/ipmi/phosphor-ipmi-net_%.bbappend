# Hostless BMC — network IPMI (RMCP) is not needed (no host to control).
# Stub all build tasks. populate_sysroot is left to run against the empty
# ${D} so a valid manifest exists for any further dependency resolution.
do_configure[noexec] = "1"
do_compile[noexec] = "1"
do_install[noexec] = "1"
do_package[noexec] = "1"
# do_packagedata MUST also be noexec: on this OpenBMC/OE base it is an
# independent task that still runs after a noexec do_package and then fails
# copying the never-created ${WORKDIR}/pkgdata (PKGDESTWORK). Stub it too.
do_packagedata[noexec] = "1"
do_package_write_ipk[noexec] = "1"
ALLOW_EMPTY:${PN} = "1"
