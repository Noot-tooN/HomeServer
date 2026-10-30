# HomeServer

## Deployment with comin

Comin polls this repository's `master` branch and deploys
`nixosConfigurations.desktop` on the server. Its actual hostname remains
`nixos`. Testing branches are disabled. The public HTTPS remote needs no GitHub
credential, and metrics listen only on `127.0.0.1:4243`.

Commit `flake.lock` alongside configuration changes. To update dependencies,
run `nix flake update` in a development checkout, build the system, then commit
and push the lock file. Comin deploys committed versions; it does not update
the lock file itself.

```sh
nix build .#nixosConfigurations.desktop.config.system.build.toplevel
```

### First installation

Preserve the server's existing `flake.lock` before adding comin, then run
`nix flake lock` to add the new input without upgrading existing inputs.
Build and publish the configuration to `master` before enabling the service,
so its first fetch includes comin itself.

From the server checkout containing that committed configuration:

```sh
sudo nixos-rebuild switch --flake .#desktop
systemctl status comin
journalctl -u comin -n 100 --no-pager
```

This server currently uses a wrapper flake in `/etc/nixos` with a `my-config`
input pointing to this repository. After publishing the change, update that
input once and rebuild from the wrapper instead:

```sh
sudo nix flake update --flake /etc/nixos my-config
sudo nixos-rebuild switch --flake /etc/nixos#desktop
```

Comin then fetches the repository directly. The wrapper is a manual fallback;
update its `my-config` input before using it to rebuild a newer Git revision.

Keep `/etc/tailscale/authkey` provisioned on the server. Comin does not manage
this existing runtime secret. No reboot is scheduled by this configuration.

### Recovery

Stop comin before a manual rollback so automatic deployment does not compete
with recovery:

```sh
sudo systemctl stop comin
sudo nixos-rebuild switch --rollback
```

Publish a corrective commit (or a Git revert) on `master`, then start comin
again. Avoid rewriting deployment history with a force push. Comin retains
five successful boot entries; avoid manually deleting those generations if
you need them for recovery. A system rollback does not restore application
databases or other mutable data.

Weekly lock-file automation and external failure reporting are separate from
this initial comin installation.
