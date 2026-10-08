# Hostless BMC — no KCS host IPMI needed. Skip all build and install tasks.
# do_populate_sysroot is intentionally NOT set noexec: it must run (against the
# empty ${D} left by the noexec do_install) so that a valid sstate manifest is
# written. Without the manifest, any recipe that DEPENDS on phosphor-ipmi-host
# (e.g. phosphor-ipmi-fru, phosphor-ipmi-net) will fail do_prepare_recipe_sysroot.
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
