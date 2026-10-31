{pkgs, quantum-secrets, ...}: {
  environment.systemPackages = [pkgs.sops];

  # Provision this machine's own age identity separately, as root:root 0400
  # inside a root:root 0700 directory. No identity is created by this module.
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    generateKey = false;
    sshKeyPaths = [];
  };
  sops.gnupg.sshKeyPaths = [];

  sops.defaultSopsFile = "${quantum-secrets}/hosts/homeserver.yaml";
  sops.secrets.github-reporting-token = {
    key = "github_reporting_token";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = ["homeserver-reporting.service"];
  };
}
