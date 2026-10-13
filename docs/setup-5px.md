# Network card

The UPS is managed by an Eaton Network-MS card. It serves a web UI on port 80, SSH on port 22, and SNMP (v1 and v3) on UDP port 161.

The card can be overwhelmed by full port scans, and stops responding until the scan ends. Scan only specific ports.

# Default credentials

| Interface                   | Username    | Password    |
| --------------------------- | ----------- | ----------- |
| Web UI, SSH, serial console | `admin`     | `admin`     |
| SNMPv1 read community       | `public`    |             |
| SNMPv3 read-only user       | `readuser`  | `readuser`  |
| SNMPv3 read-write user      | `writeuser` | `writeuser` |

# Factory reset

If the login is lost, connect to the card's serial port at 9600 baud, 8N1, no flow control. Enter `admin` to open the menu, then select "Set Login Password to Default". "Return to Default Configuration" resets everything else.

# Initial configuration

1. Connect the card to the Management VLAN.
2. Assign a static DHCP lease in OPNsense, using the card's MAC address (printed on the card and shown on the web UI's "About" page).
3. Log in to the web UI and change the default password under Settings > Access Control.

<!-- TODO SNMPv3 setup -->
