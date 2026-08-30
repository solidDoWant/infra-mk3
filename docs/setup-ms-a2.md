# BIOS configuration

Boot into the BIOS and manually change the following settings.

## PCIe link speed for the Ceph OSD

The M.2 slot holding the Samsung PM9A3 (on the M.2-to-U.2 adapter, slot 1) **must** be pinned to PCIe Gen3.

At Gen4 the link throws roughly 17 correctable `RxErr` per second while the machine is completely idle, with `BadTLP` at 0 — pure signal-integrity marginality rather than data loss — and floods the kernel ring buffer. Pinning to Gen3 takes it to a clean 0, including under sustained Ceph backfill.

This setting exists only in the BIOS. It is **not** captured in git, so a BIOS reset or reflash silently loses it. Re-apply it after any such event.

## Power behaviour

```yaml
ACPI settings:
  Restore On AC Power Loss: Always On
  Wake Up On LAN: Disabled
```

<!--
TODO: confirm the remaining BIOS menu paths against the hardware and record them
here, in particular the ASPM settings for the onboard NICs (Realtek RTL8125 and
Intel I226-V) and the NVMe slots.
-->

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

>[!WARNING]
> Booting the ISO runs the installer, because `-talos.halt_if_installed` is negated in [`talconfig.yaml`](../talos/talconfig.yaml). The installer wipes `EPHEMERAL`, which holds `/var/lib/rook` (the CephCluster's `dataDirHostPath`, including this node's mon store) and `/var/lib/etcd`.
>
> This procedure is for a **new or rebuilt** node. To change the configuration of a node that is already running, use `talosctl apply-config`, which never reinstalls. `talosctl upgrade` also preserves `EPHEMERAL`.
