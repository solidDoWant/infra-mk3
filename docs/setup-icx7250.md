# Update, factory reset, and initial configuration

As with the SX6036, this switch needs to be reset to factory defaults prior to configuration. The firmware may also need to be updated at this stage. To do so:

> [!IMPORTANT]
> Read the following steps before starting. Some of them require quick action after completing the previous step.

1. Purchase a console cable or build one as [documented here](../custom%20hardware/Brocade%20ICX%207250/Console%20cable/README.md).
2. Connect the console cable to your local computer.
3. Connect the management port and your local computer to the same subnet (direct link or via another switch).
4. Connect to the switch via a terminal program, i.e. `minicom -D /dev/ttyS3 -b 9600`. The bus should be configured as follows:
   
   ```yaml:
   Baud rate: 9600
   Data bits: 8
   Stop bits: 1
   Parity: None
   Flow Control: None
   ```
5. Run `task icx7250:firmware-service` to start a TFTP server to provide firmware to the switch.

    > [!NOTE]
    > This _really_ does not play nice with WSL2-backed Docker, due to a WSL2 bug. Run this in a VM with host network bridging if needed.

6. Boot the switch.
7. Press the `b` key repeatedly until the terminal shows that the switch has stopped at a bootloader prompt.
8. Run the following to update the bootloader:

    ```shell
    # Switch management interface config
    setenv ipaddr 10.254.0.129
    setenv netmask 255.255.255.0

    # TFTP config
    setenv serverip 10.254.0.254
    setenv image_name SPR08095pufi.bin
    setenv uboot spz10118.bin

    # Bootloader update
    update_uboot

    # Save config and reboot
    saveenv
    reset
    ```
9. Press the `b` key repeatedly until the terminal shows that the switch has stopped at a bootloader prompt.
10. Run the following to update the firmware, clear the TFTP config, and factory reset the switch:

    ```shell
    # Firmware update
    update_primary

    # Clear TFTP server config
    setenv ipaddr
    saveenv

    # Factory reset
    factory set-default

    # Restart
    reset
    ```
11. After the switch boots, wait five to ten minutes before using it to allow the PoE firmware to update.
12. Press `enter`, and log in with credentials `super/sp-admin`. When prompted, set the new password to `super`. This will be updated in a subsequent configuration step.
13. Enable and assign an IP address to the management port:

    ```shell
    enable
    configure terminal
    interface management 1

    # Set IP
    ip address 10.254.0.129/24
    end
    write memory
    ```

# Production configuration

Update the following files with your own values:
* [Ansible values (licenses and credentials)](../ansible/remote/switches/icx7250/group_vars/icx7250.sops.yaml)

Run `task icx7250:setup:full-configuration` to make the following changes:
* Load all licenses
* Load SSH key (IMPORTANT: THIS IS NOT TIED TO A SPECIFIC ACCOUNT), and disable insecure SSH encryption options
* Update account passwords
* Update the clock to current time
* Enabled HTTPS-only web management
* Enable jumbo frames
* Configure all ports (name, VLANs, LAGs, set MTU, etc.)

# Port configuration and VLAN assignment reference

Ports are connected as follows:

| Port   | Untagged VLAN | Tagged VLANs | LAG number | Host name          | Host port | Cable type |
| ------ | ------------- | ------------ | ---------- | ------------------ | --------- | ---------- |
| 1/1/1  | Management    |              |            | talos-k8s-mixed-01 |           |            |
| 1/1/2  | Management    |              |            | talos-k8s-mixed-02 |           |            |
| 1/1/3  | Management    |              |            | talos-k8s-mixed-03 |           |            |
| 1/1/4  | Management    |              |            | talos-k8s-mixed-04 |           |            |
| 1/1/5  | Management    |              |            | proxmox-vm-host-01 |           |            |
| 1/1/6  | Management    |              |            |                    |           |            |
| 1/1/7  | Management    |              |            | switch-01          |           |            |
| 1/1/8  | Management    |              |            | switch-02          |           |            |
| 1/1/9  | Management    |              |            | pdu-01             |           |            |
| 1/1/10 | Management    |              |            | ups-01             |           |            |
| 1/1/11 | Management    |              |            | tape-library-01    |           |            |
| 1/1/12 | Management    |              |            | kvm-01             |           |            |
| 1/1/13 | Hosts         |              |            |                    |           |            |
| 1/1/14 | Hosts         |              |            |                    |           |            |
| 1/1/15 | Hosts         |              |            |                    |           |            |
| 1/1/16 | Hosts         |              |            |                    |           |            |
| 1/1/17 | User devices  |              |            |                    |           |            |
| 1/1/18 | User devices  |              |            |                    |           |            |
| 1/1/19 | User devices  |              |            |                    |           |            |
| 1/1/20 | User devices  |              |            |                    |           |            |
| 1/1/21 | Guest devices | IoT devices  |            | switch-03          |           |            |
| 1/1/22 | Guest devices | IoT devices  |            | switch-04          |           |            |
| 1/1/23 | Guest devices | IoT devices  |            | ap-01              |           |            |
| 1/1/24 | Guest devices | IoT devices  |            | ap-02              |           |            |
| 1/2/1  |               | all          | 5          | switch-02          | 1/33/1    | DAC SFP+   |
| 1/2/2  |               | all          | 5          | switch-02          | 1/33/2    | DAC SFP+   |
| 1/2/3  |               | all          | 5          | switch-02          | 1/33/3    | DAC SFP+   |
| 1/2/4  |               | all          | 5          | switch-02          | 1/33/4    | DAC SFP+   |
| 1/2/5  | User devices  |              |            |                    |           | LC fiber   |
| 1/2/6  | User devices  |              |            |                    |           | LC fiber   |
| 1/2/7  | User devices  |              |            |                    |           | LC fiber   |
| 1/2/8  | User devices  |              |            |                    |           | LC fiber   |

# Relevant links

* [Hardware install guide](https://gzhls.at/blob/ldb/a/b/e/7/6633931b0f02f6c5019f7d4e6b199bc36d38.pdf)
* [General setup information](https://fohdeesha.com/docs/icx7250.html)
