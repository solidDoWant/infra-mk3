# Factory reset BIOS

The BIOS can be factory reset by disconnecting the internal battery. To do this:

1. Depress the rear case release button on the chassis.
2. Slide the electronics assembly out from the chassis.
3. Use a pair of tweezers to disconnect the battery connector from the motherboard. The connector is located at the front of the case, on the top side of the motherboard, underneath the front bezel.
4. Wait 15 seconds.
5. Reattach the battery. All BIOS settings, including passwords, will be cleared.
6. Slide the electronics assembly back into the chassis.

# Re-paste the CPU

It's [fairly well known](https://forums.servethehome.com/index.php?threads/minisforum-ms-01-heating-problem.43519/) that the MS-01 uses terribly low-quality thermal paste. Replacing it withe decent
paste consistently results in a 10&deg; C drop in CPU temperatures. Mine dropped around 15&deg; C with [this paste](https://www.amazon.com/gp/product/B00ZJS8Q6S). To repaste the CPU:

1. Depress the rear case release button on the chassis.
2. Slide the electronics assembly out from the chassis.
3. Unscrew the blower fan attached to the CPU heat sink on the top side.
4. Locate the two screws underneath the foam that covers the CPU heatsink. They are in line with the rear two screws, and with each other (forming a rectangle). One can be seen from the side,
   between the heatsink and the board. The foam should flex more above these screws.
5. Use a scalpel to remove the foam directly above these screws. There is no need to remove all of the foam.
6. Unscrew all four screws that attach the CPU heatsink to the motherboard.
7. Remove the CPU heatsink. The paste is likely dried and hardened, so this may take a little bit of force.
8. Use isopropyl alcohol (the higher percentage the better) and a cloth to remove the existing CPU paste. Both the heatsink and the CPU should be shiny when completed.
9. Wait for the alcohol to dry (should be nearly immediate).
10. Spread the new thermal paste over the CPU in as thing of a layer as possible, while still completely covering it.
11. Place the CPU heatsink back on the CPU.
12. Screw the CPU heatsink screws back in.
13. Re-attach the CPU blower fan.
14. Slide the electronics assembly back into the chassis.

# BIOS upgrade

The BIOS must be upgraded to v1.24 or later to support secure boot with custom keys. To update the BIOS:

1. Download the v1.26 BIOS update [here](https://www.minisforum.com/new/support?lang=en#/support/page/download/108).
2. Attach a FAT32 formatted flash drive to your local computer.
3. Extract the BIOS update zip file to the root of the flash drive.
4. Attach the flash drive to the MS-01.
5. Boot into the UEFI shell. This may require changing the boot order, priority, or other options. The `delete` key can be used to enter the BIOS configuration screen, and `F7` can be used to change
   the boot disk.
6. List the available disks with `map -r`. Determine which one is the flash drive. It will have `USB` in the device path.
7. Select the drive by typing in the drive name followed by a colon, i.e. `FS0:`. Verify that this is the correct drive by running `ls` and ensuring that the files are what's expected.
8. Run `AfuEfiFlash.nsh` to begin the BIOS update.
9. Wait for the device to reboot.
10. Remove the flash drive.

# BIOS configuration

Boot into the BIOS and manually change the following BIOS settings:

```yaml
Advanced:
	Onboard device settings:
		# ASPM seems to cause nothing but problems
		SA-PCIE Port:
			PCIE4.0x4 SSD ASPM: Disabled
		PCH-PCIE Port:
			I226-V NIC ASPM: Disabled
			I226-LM NIC ASPM: Disabled
			WIFI ASPM: Disabled
		# Not currently affected by memory stability issues, so this can be enabled
		SA GV: Enabled
	ACPI settings:
		Restore On AC Power Loss: Always On
		Wake Up On LAN: Disabled
```

Optionally, change the BIOS password.

Afterwards, save and exit. The next reboot may take a few minutes.

## Install media creation and OS configuration

The OS and boot media is entirely controlled by [these files](../talos/). Install ISOs (specific to each node) can be built via `task talos:setup:download-iso`, and burned to a USB flash drive.

>[!WARNING] Rufus users
> When using Rufus to create flash drives from the ISO, an additional step must be taken until a Talos bug is fixed. After "burning" the ISO to a flash drive, rename the file at
> `EFI/Linux/Talos-v1.8.1` to `EFI/Linux/Talos-v1.8.1.efi`. Otherwise, the boot loader will fail to find and boot the EFI stub.
>
> This should be fixed in v1.9.0 onwards. I worked with the Talos devs and personally verified the fix.
>
> Reference issues:
> * https://github.com/siderolabs/talos/issues/9397
> * https://github.com/siderolabs/talos/issues/9565

## Secure boot

Secure boot is an extra line of defense against certain types of malware (rootkits). To enable secure boot:

1. Open the BIOS configuration during boot (press the `delete` key repeatedly).
2. Change the following settings:
	```yaml
	Security:
		Secure Boot:
			Secure Boot: Enabled
			Secure Boot Mode: Custom
			Key Management:
				Factory Key Provision: Disabled
	```
3. Save and exit.
4. Open the BIOS configuration during boot (press the `delete` key repeatedly).
5. Insert the Talos install drive into the node.
6. Navigate to `Security > Secure Boot` and select `Reset To Setup Mode`, and confirm.
7. The device will reboot. When prompted, select `Enroll Secure Boot keys: AUTO`.
8. Wait for the keys to install and the device to restart.
9.  Open the BIOS configuration during boot (press the `delete` key repeatedly).
10. Re-enable secure boot by changing the settings to those described in (2) again.
11. After the Talos installer boots, ensure that `SECUREBOOT: True` is displayed in green in the upper left corner of the screen.

<!-- TODO implement custom keys -->

## OS install and Talos bootstrap

With secure boot enabled and the Talos installer online, the OS can be configured, and the cluster can be bootstrapped via `task talos:setup:bootstrap`. Afterwards, the USB flash drives can be
removed.
