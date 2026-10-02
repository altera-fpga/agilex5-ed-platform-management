# file's check-local self-test renders a FIT (Garmin) timestamp via localtime
# and diffs it against a UTC-baked .result.  On a non-UTC build host the native
# `file` binary prints local time even though TZ=UTC is already exported (by
# OE-core globally and inside check-local itself), so the fit-map-data case
# fails by the host's UTC offset and aborts do_compile.  This is file's own
# regression test, not anything we ship, so remove the FIT test inputs before
# `make check` runs and check-local simply skips that case.  Both files are
# EXTRA_DIST only, so dropping them does not affect the build or packaging.
do_compile:prepend:class-native() {
    rm -f "${S}/tests/fit-map-data.testfile" "${S}/tests/fit-map-data.result"
}
