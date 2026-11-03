{pkgs, smartthermweb, ...}: {
  services.smartthermweb = {
    enable = true;
    package = smartthermweb.packages.${pkgs.stdenv.hostPlatform.system}.default;
    port = 3000;
    # The public origin and reverse proxy are configured with the dashboard.
  };
}
