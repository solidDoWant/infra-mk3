{
  lib,
  config,
  pkgs,
  ...
}:
# A headless X11 desktop for the workspace VM, reached through Teleport's Linux
# desktop service (Teleport >= 18.11.0 - see ../teleport for how that version is
# built).
#
# Nothing here runs an X server at boot. Teleport starts one Xvfb per connection
# and launches the chosen session inside it, so a workspace nobody is looking at
# costs nothing beyond the disk the packages occupy. That is also why there is no
# display manager: `startx` below is NixOS' dummy pseudo-display-manager, whose
# purpose is exactly this - enable the X stack without pulling in and starting
# LightDM or SDDM.
#
# Xfce is the desktop, chosen because it is X11-native (Teleport's desktop access
# is X11-only; there is no Wayland support), light enough to be usable over a
# remote display protocol, and does not assume a systemd user session the way
# GNOME and KDE do.
#
# This module is only in the `-desktop` image variant - see ../../flake.nix.
let
  # Where NixOS puts the generated session .desktop files. Teleport reads
  # /usr/share/xsessions by default, which does not exist here, but it honours
  # TELEPORT_XSESSIONS_PATH (lib/srv/desktop/x11/xsession.go) - so point it at the
  # real location rather than faking an FHS path.
  xsessionsPath = "${config.services.displayManager.sessionData.desktops}/share/xsessions";

  # Teleport runs the session's Exec line through a distro "session wrapper" when
  # it finds one, probing /etc/X11/Xsession and friends - none of which exist on
  # NixOS. Hand it NixOS' own xsession wrapper instead: it sources /etc/profile
  # and ~/.xprofile, merges X resources, then `eval exec "$@"`, which is precisely
  # the contract Teleport expects (wrapper + escaped Exec). Without it the session
  # starts, but outside the environment NixOS builds for graphical logins.
  sessionWrapper = config.services.displayManager.sessionData.wrapper;
in
{
  # Populates services.displayManager.sessionData (the generated session .desktop
  # files and the xsession wrapper Teleport is pointed at below). It is the shared
  # display-manager *integration*, not a display manager: the unit that would
  # actually run one lives behind services.displayManager.generic, which nothing
  # here enables. Real display managers turn this on for themselves; startx does
  # not, so with only startx the session data would come out empty.
  services.displayManager.enable = true;

  # XDG_RUNTIME_DIR, which nothing else in this VM provides.
  #
  # It is normally created by pam_systemd when logind opens a session, but
  # Teleport's desktop service does not open one - /run/user stays empty and
  # `loginctl list-sessions` shows none. Plenty of desktop software treats the
  # variable as guaranteed: PipeWire and the xdg portals need it, the per-user
  # D-Bus socket lives there, and Blender segfaults outright inside
  # wl_display_connect (it probes its Wayland backend before falling back to X11,
  # and handles the unset variable by crashing rather than by failing over).
  #
  # Lingering makes logind start a user manager at boot, which creates
  # /run/user/1000 and keeps it there for the life of the VM, independent of any
  # session. sessionCommands then exports it for the desktop session - the
  # session wrapper Teleport is pointed at runs these, after /etc/profile and
  # before the session itself. Guarded, so a real logind session would win.
  users.users.coder.linger = true;

  services.xserver = {
    displayManager.sessionCommands = ''
      if [ -z "$XDG_RUNTIME_DIR" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(${pkgs.coreutils}/bin/id -u)"
      fi
    '';

    # Brings in the X server, drivers, and the session plumbing. On its own it
    # starts nothing: with startx as the display manager there is no
    # display-manager.service to run at boot.
    enable = true;

    # The dummy "display manager". Nothing invokes startx either - Teleport spawns
    # its own X server - so this exists purely to keep a real display manager out
    # of the image. generateScript is left off: the system-wide xinitrc it writes
    # is for interactive `startx`, which this VM has no console to run from.
    displayManager.startx.enable = true;

    desktopManager = {
      xfce = {
        enable = true;
        # xfce4-screensaver would lock the session behind a password the coder
        # user does not have (hashedPassword = "" in ../../configuration.nix -
        # access is via the Coder agent and Teleport, never a password), making the
        # lock unrecoverable from inside the session. There is also nothing to
        # blank: the display only exists while someone is connected.
        enableScreensaver = false;
      };
      # services.xserver.enable would otherwise register a bare xterm session,
      # which Teleport would offer next to Xfce as a second, much worse choice.
      xterm.enable = false;
    };
  };

  # Teleport's Linux desktop service. Enabled here rather than in
  # ../teleport-node so that it exists only in the desktop image variant - the
  # base image has no X session for it to offer. Both modules contribute to the
  # same services.teleport.settings attrset.
  services.teleport.settings.linux_desktop_service = {
    enabled = true;
    # Mirrors the ssh_service labels in ../teleport-node, so one role predicate
    # (linux_desktop_labels) covers every workspace.
    labels.type = "coder-workspace";
    session_wrapper = sessionWrapper;
  };

  systemd.services.teleport = {
    # Teleport resolves these by name with exec.LookPath at connection time:
    # Xvfb for the virtual display, xauth for the per-session X authority cookie,
    # and dbus-run-session to give each session its own bus (it logs a warning and
    # starts a degraded session if that one is missing). The unit's PATH is
    # otherwise just getent/shadow/sudo from the upstream NixOS module.
    path = [
      pkgs.xorg-server # Xvfb
      pkgs.xauth
      pkgs.dbus # dbus-run-session
    ];
    environment.TELEPORT_XSESSIONS_PATH = xsessionsPath;
  };

  environment = {
    systemPackages = with pkgs; [
      # Also on the interactive PATH, so the session and anyone debugging it by
      # hand see the same tools the service uses.
      xorg-server
      xauth
      xrandr
      # A usable baseline inside the desktop. Xfce brings its own terminal and
      # file manager; these are the ones whose absence is immediately felt.
      firefox
      xfce4-screenshooter
      xclip
    ];

    # Mesa's software rasterizer. No GPU is passed through to this VM (the hosts
    # have no IOMMU enabled, and KubeVirt's virtio-gpu offers no 3D acceleration),
    # so every GL client renders on the CPU. Say so explicitly rather than letting
    # applications discover there is no hardware GL and crash: llvmpipe advertises
    # GL 4.5, which clears the version floor most 3D applications check.
    sessionVariables.LIBGL_ALWAYS_SOFTWARE = "1";
  };

  # Without these the session renders boxes. Xfce pulls some fonts in
  # transitively; pin the basics rather than rely on that.
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      dejavu_fonts
      liberation_ttf
      noto-fonts
      noto-fonts-color-emoji
    ];
  };

  # Xfce keeps its per-user state (panel layout, xfconf, theme) under ~/.config
  # and ~/.local. /home/coder is already an impermanence bind mount onto the
  # persistent disk (../persistence), so the desktop keeps its layout across
  # restarts and base-image bumps with nothing extra here.
}
