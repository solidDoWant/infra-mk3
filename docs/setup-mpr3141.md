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
<!-- TODO SNMP -->
