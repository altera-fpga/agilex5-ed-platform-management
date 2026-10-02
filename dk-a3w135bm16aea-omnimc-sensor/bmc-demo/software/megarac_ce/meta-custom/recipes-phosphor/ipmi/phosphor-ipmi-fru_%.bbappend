# The altera-common (meta-altera/meta-common) bbappend stubs do_install[noexec]=1
# for this hostless BMC but leaves SYSTEMD_SERVICE set (the base recipe adds
# obmc-read-eeprom@.service). When the recipe hash changes and do_package must
# re-run, it looks for service units that were never installed and fails with
# "Didn't find service unit 'obmc-read-eeprom@.service'". Clear SYSTEMD_SERVICE
# and SYSTEMD_PACKAGES so do_package agrees with the empty install.
# (Mirrors meta-altera/meta-agilex3/meta-custom, which we do not enable.)
SYSTEMD_SERVICE:${PN} = ""
SYSTEMD_PACKAGES = ""
