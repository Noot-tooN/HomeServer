{...}: {
  # Provision this machine's own age identity separately, as root:root 0400
  # inside a root:root 0700 directory. No identity is created by this module.
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    generateKey = false;
    sshKeyPaths = [];
  };
  sops.gnupg.sshKeyPaths = [];

  # Secret files and their recipients will be configured after key provisioning.
}
