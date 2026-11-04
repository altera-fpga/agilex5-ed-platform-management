# Enable Redfish BMC journal access (off by default upstream) so the WebUI and
# Redfish clients can read the BMC system journal via
# /redfish/v1/Managers/bmc/LogServices/Journal.
#
# Enable the D-Bus-backed Redfish Event Log (off by default upstream) so that
# entries created on xyz.openbmc_project.Logging (e.g. the switch-triggered
# fault messages posted by qtpy-uart-bridge via Logging.Create) surface in the
# Redfish Event Log at /redfish/v1/Systems/system/LogServices/EventLog, which
# both the stock WebUI (Logs -> Event Logs) and the custom /dashboard read.
# Without this, bmcweb serves the Event Log from the systemd journal
# (REDFISH_MESSAGE_ID-tagged) only, and D-Bus Logging entries never appear.
PACKAGECONFIG:append = " redfish-bmc-journal redfish-dbus-log"
