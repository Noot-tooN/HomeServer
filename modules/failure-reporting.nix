{config, lib, pkgs, ...}: let
  reporter = pkgs.writeShellApplication {
    name = "homeserver-report-failures";
    runtimeInputs = [config.services.comin.package pkgs.python3 pkgs.systemd];
    text = ''
      exec python3 ${../scripts/report-failures.py} "$@"
    '';
  };
in {
  environment.systemPackages = [reporter];
  services.comin.postBuildCommand = pkgs.writeShellScript "report-comin-build" ''
    ${pkgs.systemd}/bin/systemctl --no-block start homeserver-reporting.service
  '';
  services.comin.postDeploymentCommand = pkgs.writeShellScript "report-comin-deploy" ''
    ${pkgs.systemd}/bin/systemctl --no-block start homeserver-reporting.service
  '';
  systemd.services.homeserver-reporting = {
    description = "Report sanitized comin failures to GitHub Issues";
    after = ["network-online.target"] ++ lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
    requires = lib.optional config.sops.useSystemdActivation "sops-install-secrets.service";
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = ["github-token:${config.sops.secrets.github-reporting-token.path}"];
      ExecStart = "${reporter}/bin/homeserver-report-failures --token-file %d/github-token";
      StateDirectory = "homeserver-reporting";
      StateDirectoryMode = "0700";
      UMask = "0077";
      TimeoutStartSec = 180;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    };
  };
  systemd.timers.homeserver-reporting = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "2min";
      Unit = "homeserver-reporting.service";
    };
  };
}
