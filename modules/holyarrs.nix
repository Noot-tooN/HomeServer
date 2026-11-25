{pkgs, ...}: let
  version = "1.3.1";
  executable = pkgs.fetchurl {
    url = "https://github.com/HolyArrs/HolyArrs/releases/download/${version}/holyarrs_${version}_linux_amd64";
    sha256 = "d0eaa725eabc7bc08196ee2fd0cb8f00fd035ed67719207b989508fd17c31277";
  };
  holyarrs = pkgs.runCommand "holyarrs-${version}" {} ''
    install -Dm755 ${executable} "$out/bin/holyarrs"
  '';
  mediaRoot = "/srv/holyarrs-media";
in {
  systemd.tmpfiles.rules = map
    (suffix: "d ${mediaRoot}${suffix} 0750 media media -")
    ["" "/downloads" "/movies" "/shows" "/music"];

  systemd.services.holyarrs = {
    description = "HolyArrs media manager";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment = {
      HOLYARRS_ADDR = "127.0.0.1:6262";
      HOLYARRS_URL_BASE = "/holyarrs";
      HOLYARRS_TRUSTED_PROXIES = "127.0.0.1";
      HOLYARRS_SAVE_PATH = "${mediaRoot}/downloads";
      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    };
    serviceConfig = {
      ExecStart = "${holyarrs}/bin/holyarrs -config /var/lib/holyarrs";
      User = "media";
      Group = "media";
      StateDirectory = "holyarrs";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/holyarrs";
      Restart = "on-failure";
      RestartSec = "5s";
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [mediaRoot];
      NoNewPrivileges = true;
    };
  };
}
