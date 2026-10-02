# phosphor-ipmi-net (netipmid / RMCP) is stubbed by meta-altera/meta-common for
# this hostless BSP build: it sets do_install[noexec]=1 and SYSTEMD_PACKAGES=""
# but does NOT clear SYSTEMD_SERVICE, so do_package fails ("Didn't find service
# unit") when the hash changes and the task must re-run. Clear SYSTEMD_SERVICE
# so do_package agrees with the empty install.
# (Mirrors meta-altera/meta-agilex3/meta-custom, which we do not enable.)
SYSTEMD_SERVICE:${PN} = ""
SYSTEMD_PACKAGES = ""
