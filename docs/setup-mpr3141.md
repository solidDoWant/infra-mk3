# Factory reset

The device needs to be reset to factory defaults. To do so, navigate through the menu on the RPC2 module to factory reset the device.

# Firmware update

Do not update the device. I attempted to update the firmware on one PDU, following the instructions exactly, and bricked it.

# Initial configuration

The device needs some minimal manual configuration. To do so:

1. Connect the device to the Management VLAN.
2. Assign a static DHCP lease in OPNsense (optional). The PDU does not obey static IPv4 configurations and resets it every few seconds.
3. SSH into the PDU with a username/password of `admin/admin`.
4. Run the following commands:

    ```shell
    network ipv6 disable
    network ipv4 bootmode dhcp
    password admin admin <new password> <new password>
    reboot
    ```
5. Wait for the device to reboot.

# Full configuration

After the initial manual setup is complete, run `task mpr3141:full-configuration`. This will:
* Set the device name and hostname
* Set the time zone
* Raise the input (L1 and neutral) current thresholds from 45%/40% to 90%/80% of rating. The defaults sit at the rack's normal load.
* Create a read-only SNMPv3 user (SHA/AES) in slot 1, from `ansible/remote/power/mpr3141/group_vars/mpr3141.sops.yaml`
* Disable SNMP v1/v2, whose default communities allow writes (outlet control) from any address
* Restart the RPC2 card to apply the SNMP settings

The same SNMPv3 credentials are in the `pdu` auth in `cluster/gitops/monitoring/exporters/snmp/snmp-exporter-auth.sops.yaml`.

# SNMP notes

* SNMP settings take effect only after the card restarts. `reboot` asks for confirmation on a TTY, and the card goes down about 2 minutes later. It restarts only the RPC2 card; outlet power is unaffected.
* A v3 user with a blank `Source` authenticates but gets `authorizationError` for every request. snmp_exporter treats that as an empty walk, not a failure.
* Full walks are slow (~1s per request, ~35s for the `liebert_pdu` module).
* The Liebert MIB objects can take a few minutes to appear after a restart.
