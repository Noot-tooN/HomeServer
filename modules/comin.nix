{...}: {
  services.comin = {
    enable = true;
    # The flake output is named desktop; the machine hostname is nixos.
    hostname = "desktop";
    remotes = [{
      name = "origin";
      url = "https://github.com/Noot-tooN/HomeServer.git";
      branches.main.name = "master";
      branches.testing.name = "";
    }];

    exporter.listen_address = "127.0.0.1";
    buildTimeout = 7200;
    retention.deployment_boot_entry_capacity = 5;
  };
}
