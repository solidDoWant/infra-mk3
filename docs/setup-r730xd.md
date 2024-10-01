# Factory reset

After physically configuring the server, the NVRAM (BIOS settings storage) needs to be reset. As [documented here](https://www.dell.com/support/kbdoc/en-us/000128677/how-to-reset-the-bios-of-a-dell-poweredge-server), do this by:
1. Turn off the server and remove AC power.
2. Open the top panel to access the motherboard.
3. Move the `NVRAM_CLR` jumper from pins 3-5 to pins 1-3. This jumper can be found behind DIMM slot `A1`, near the power supplies.
4. After at least ten seconds, move the jumper back to pins 3-5.
5. If needed, disable the BIOS password by moving the `PWRD_EN` jumper from pins 2-4 to pins 4-6.
6. Close the server up and connect it to power. It is not necessary to press the power button at this time.

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
      Static IP Address: 10.0.1.4
      Static Gateway: 10.0.1.1
      Static Subnet Mask: 255.255.0.0
    ```
6. Run `task r730xd:idrac:setup:full-configuration`.

# Bootloader setup

The R730XD does not natively support NVMe boot. Supposedly the U.2 enablement kit is supposed to support this, however, this seems to be dependent on what HBA is attached to the SAS backplane, what firmware version it uses, and is extremely finicky. To mitigate this issue, [Clover Bootloader](https://github.com/CloverHackyColor/CloverBootloader) is installed on a Dell Internal Dual SD Module (IDSDM). This bootloader loads NVMe UEFI drivers and boots the OS from U.2 drives. The IDSDM contains two mirrored SD cards, so if one fails, the other can take over. While SD cards are infamous for poor write endurance, however, there should be little to no writing to these cards outside of bootloader updates.

To setup the bootloader:
1. Attach a SD card to your local computer.
2. Run `task r730xd:os-install:clover:create-install-iso`. This will place a `clover.iso` file in your current working directory.
3. Burn the ISO to the SD card. This can be done on Linux with `dd bs=8M if=clover.iso of=/dev/&lt;YOUR_DEV&gt; status=progress oflag=sync; sync`, or on Windows via [Rufus](https://github.com/pbatard/rufus).
4. After all writes are complete, remove the SD card from your local computer and install it in slot `SD1` in the IDSDM.
5. Install a blank SD card in the IDSDM `SD2` slot.
6. Boot the server.
7. When prompted, press `y` during boot to rebuild the mirror array from `SD1`.
