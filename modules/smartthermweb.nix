{pkgs, smartthermweb, ...}: {
  services.smartthermweb = {
    enable = true;
    package = smartthermweb.packages.${pkgs.stdenv.hostPlatform.system}.default;
    publicOrigin = "https://heating.homeserver.com";
    port = 3000;
  };

  services.caddy.virtualHosts."heating.homeserver.com".extraConfig = ''
    tls internal
    reverse_proxy 127.0.0.1:3000 {
      flush_interval -1
      transport http {
        response_header_timeout 400s
      }
    }
  '';
}
