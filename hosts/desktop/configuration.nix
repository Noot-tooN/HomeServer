# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  config,
  pkgs,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  services.dnsmasq = {
    enable = true;
    settings = {
      "address" = ["/homeserver.com/100.82.238.95"];
    };
  };

  services.caddy = {
    enable = true;

    virtualHosts."torrent.homeserver.com".extraConfig = ''
      tls internal
      reverse_proxy http://127.0.0.1:8080
    '';
    virtualHosts."media.homeserver.com".extraConfig = ''
      tls internal
      reverse_proxy http://127.0.0.1:8096
    '';
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client"; # maybe use both?
    openFirewall = true;
    extraUpFlags = ["--ssh"];
    authKeyFile = "/etc/tailscale/authkey";
  };

  services.jellyfin = {
    enable = true;
    user = "media";
    group = "media";
  };

  services.jackett = {
    enable = true;
    user = "media";
    group = "media";
  };

  services.qbittorrent = {
    enable = true;
    user = "media";
    group = "media";
  };

  services.k3s = {
    enable = true;
    role = "server";
    clusterInit = true;
  };

  # Set your time zone.
  time.timeZone = "Europe/Belgrade";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  programs.zsh.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.nirdala = {
    isNormalUser = true;
    description = "nirdala";
    extraGroups = ["networkmanager" "wheel" "media"];
    shell = pkgs.zsh;
  };

  users.users.media = {
    isSystemUser = true;
    group = "media";
    description = "media";
    uid = 1025;
  };

  users.groups.media = {gid = 1025;};

  environment.variables = {
    EDITOR = "vim";
    VISUAL = "vim";
    TERMINAL = "kitty";
  };

  # Enable automatic login for the user.
  # services.getty.autologinUser = "nirdala";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    #  wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
  networking.firewall = {
    enable = true;

    trustedInterfaces = ["tailscale0"];

    allowedTCPPorts = [443];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
