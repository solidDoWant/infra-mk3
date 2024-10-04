# Factory reset

After physically configuring the server, the NVRAM (BIOS settings storage) needs to be reset. As [documented here](https://www.dell.com/support/kbdoc/en-us/000128677/how-to-reset-the-bios-of-a-dell-poweredge-server), do this by:
1. Turn off the server and remove AC power.
2. Open the top panel to access the motherboard.
3. Move the `NVRAM_CLR` jumper from pins 3-5 to pins 1-3. This jumper can be found behind DIMM slot `A1`, near the power supplies.
4. After at least ten seconds, move the jumper back to pins 3-5.
5. If needed, disable the BIOS password by moving the `PWRD_EN` jumper from pins 2-4 to pins 4-6.
6. Close the server up and connect it to power. It is not necessary to press the power button at this time.

# XGS-PON transceiver

The XGS-PON transceiver needs it's firmware replaced, and needs to be configured for the remainder of the setup. To do this:
1. Plug the transceiver into a SFP+ cage in your local computer or a switch.
2. Connect your local computer to the same subnet. Set your IP address to 192.168.11.2/24.
3. Run `task r730xd:os-install:xgs-pon:full-configuration`. This will:
   * Install the [replacement firmware](https://github.com/djGrrr/8311-was-110-firmware-builder).
   * Change the root user password and import the SSH key.
   * Setup to authenticate with the ISP.
4. Install the transceiver into SFP+ cage 1 in the rear of the R730XD.

# iDRAC and BIOS configuration

To configure iDRAC, do the following:
1. Connect the iDRAC port and your local computer to the same subnet (direct link or via a switch).
2. Power the server on.
3. During boot up, press `F2` repeatedly to enter System Setup.
4. Go to `iDRAC Settings > Network`
5. Configure the following settings:

    ```yaml
    IPV4 SETTINGS:
      Enable IPv4: Enabled
      Enable DHCP: Disabled
      Static IP Address: 10.1.2.1
      Static Gateway: 10.1.0.254
      Static Subnet Mask: 255.255.0.0
    ```
6. Run `task r730xd:idrac:setup:full-configuration`.

# Proxmox install

Proxmox is installed automatically via a flash drive installed to the back of the R730XD. This drive is formatted with a custom Proxmox ISO that contains [an "answer" file](https://pve.proxmox.com/wiki/Automated_Installation) detailing the initial configuration.

<!-- TODO switch to HTTPS boot via rEFInd and chain boot managers -->

Unfortunately answer files are fairly limited and restrictive. The answer file is not flexible enough to support the network configuration required. To mitigate this issue, a custom "network config" Debian package is built and injected into the ISO. This package contains a `/etc/networks/interfaces` file that is templated from the configuration file [here](../docs/network.yaml). It also contains a kernel module configuration file for the Mellanox ConnectX-3 NIC, which switches the port type from InfiniBand to Ethernet. The installer automatically unpacks and installs this package, configuring the network.

To install Proxmox:
1. Attach a USB flash drive into your local computer.
2. Run `task r730xd:os-install:proxmox:create-install-iso`. This will place a `proxmox.iso` file in your current working directory.
3. Burn the ISO to the flash drive. This can be done on Linux with `dd bs=512 if=proxmox.iso of=/dev/&lt;YOUR_DEV&gt; status=progress oflag=sync; sync`, or on Windows via [Rufus](https://github.com/pbatard/rufus).
4. After all writes are complete, remove the flash drive from your local computer and install it into one of the rear USB ports.
5. Boot the server.
6. Wait for the OS to install (10 to 15 minutes).
7. Remove the install flash drive.

# Bootloader setup

The R730XD does not natively support NVMe boot. Supposedly the U.2 enablement kit is supposed to support this, however, this seems to be dependent on what HBA is attached to the SAS backplane, what firmware version it uses, and is extremely finicky. Previously I have used [Clover Bootloader](https://github.com/CloverHackyColor/CloverBootloader) to boot from NVMe drives, however, it is mainly designed for booting MacOS and has somewhat limited options for booting Linux.

Instead, I'm using [ZFSBootMenu](https://zfsbootmenu.org/). ZFSBootMenu is an EFI program that contains a small Linux kernel, and tools to automatically load a root filesystem from a zpool. Upon finding a root filesystem, ZFSBootMenu bypasses other bootloaders and boot managers (such as GRUB) and uses `kexec` to launch the discovered kernel.

> [!NOTE]
> This will ignore any Linux `cmdline` changes to GRUB, which may be deployed upon OS update.

Using a boot manager like ZFSBootMenu or Clover requires that the boot manager itself be placed on a drive and filesystem that the UEFI understands. Normally this would be a USB flash drive installed internally. Fortunately, Dell PowerEdge servers support an [Internal Dual SD Module](https://www.dell.com/learn/us/en/04/business~solutions~whitepapers~en/documents~poweredge-idsdm-whitepaper-en.pdf). This is a special SD card reader that supports a mirrored pair of SD cards. SD cards are infamous for poor write endurance, however, there should be little to no writing to these cards outside of bootloader updates. Installing the boot manager to these cards removes the single point of failure (USB flash drive) that would otherwise be needed.

To setup the bootloader:
1. Shut down the server.
2. Attach a SD card to your local computer.
3. Run `task r730xd:os-install:zfsbootmenu:create-install-iso`. This will place a `zfsbootmenu.iso` file in your current working directory.
4. Burn the ISO to the SD card. This can be done on Linux with `dd bs=8M if=clover.iso of=/dev/&lt;YOUR_DEV&gt; status=progress oflag=sync; sync`, or on Windows via [Rufus](https://github.com/pbatard/rufus).
5. After all writes are complete, remove the SD card from your local computer and install it in slot `SD1` in the IDSDM.
6. Install a blank SD card in the IDSDM `SD2` slot.
7. Boot the server.
8. When prompted, press `y` during boot to rebuild the mirror array from `SD1`.
9. The server will now automatically boot Proxmox.
