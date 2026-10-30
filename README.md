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

### SSH access

OpenSSH requires a public key and is reachable only over the Tailscale
network. Tailscale's built-in SSH server is explicitly disabled for both
existing enrollment and future logins. Password, keyboard-interactive, and
root SSH logins are disabled.

Connect to the server's Tailscale name or address using an authorized SSH key.
Tailscale's network policy must allow the connection; OpenSSH then checks the
key against its authorized keys. The existing Bitwarden-managed HomeServer
key is installed in the user's local `~/.ssh/authorized_keys` file.

The firewall fully trusts `tailscale0`, allowing every port over Tailscale.
The LAN interface `enp1s0` is not trusted; it allows only the service ports
listed below. SSH is not in that list. This uses ordinary NixOS interface
firewall options, without custom commands or socket activation.
If Tailscale access is unavailable, recovery requires the local console;
there is no direct LAN SSH fallback.

### LAN service access

| Service | TCP ports | UDP ports |
| --- | --- | --- |
| DNS | 53 | 53 |
| HTTP, HTTPS, HTTP/3 and ingress | 80, 443 | 443 |
| Kubernetes API | 6443 | — |
| qBittorrent web UI and peers | 8080, 42715 | 42715, 6771 |
| Jellyfin and media discovery | 8096 | 7359, 1900 |
| Jackett | 9117 | — |
| Netdata | 19999 | — |
| Existing Traefik NodePorts | 31134, 31731 | — |

The qBittorrent peer port comes from its existing persisted settings; update
the allowlist if that port changes. Kubernetes manages its own forwarding
and published NodePorts, so new Kubernetes exposures also require review.
This single-node cluster does not need LAN access to etcd, kubelet, or VXLAN
ports. Tailscale's WireGuard transport port remains opened by its NixOS module.

The existing `*.homeserver.com` DNS records still point to the Tailscale IP;
direct LAN access uses `192.168.0.200`. This change does not modify DNS routing.

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

## Weekly package updates

The `Weekly updates` GitHub Actions workflow runs Sundays at 02:23 UTC
(03:23 in Belgrade in winter, 04:23 in summer), and can also be started from
the Actions page. It updates only `nixpkgs`, `nixpkgs-unstable`, and
`home-manager`. Comin and the release branch URLs are not automatically changed.

Each update creates a bot PR and explicitly dispatches `Validate NixOS`.
This avoids requiring a human to approve CI triggered by `GITHUB_TOKEN`.
Validation builds `nixosConfigurations.desktop.config.system.build.toplevel`
at the exact PR revision, with lock-file writes disabled. A separate job posts
the required `NixOS system build` commit status and merges only successful,
bot-authored, lock-only updates. It verifies that the PR head and `master`
still match the validated revisions and checks the lock graph for changes
outside the allowed inputs. A changed base requires revalidation; it is never
merged using a stale build.

`master` must require the `NixOS system build` status with strict/up-to-date
checks. The repository must permit GitHub Actions to create pull requests.
No personal access token is used by these update/build workflows. Human PRs
are validated but are not automatically merged. No reboot is scheduled.

To revalidate an existing same-repository PR, dispatch `Validate NixOS` with
its PR number. Only eligible weekly bot PRs can use `auto_merge=true`.

## Failure reporting

CI failures in either update or validation workflows create a sanitized issue
in this repository with a workflow run link. No log text is copied into issues.

On the server, `homeserver-reporting.timer` samples comin every two minutes;
build and deployment hooks also request a sample. It detects fetch, evaluation,
build, deployment and unavailable-comin failures, including recent generation
history. Events and bounded diagnostic snapshots are persisted under
`/var/lib/homeserver-reporting/events/` with root-only access. Repeated identical
failures reuse the same incident. Delivery failures retain the local queue.

Public server issues contain **only** a fixed machine label, phase, validated
commit SHA, and incident ID. Error text, commit messages, status snapshots, and
journal excerpts never enter the issue payload. A future repair worker must
retrieve diagnostics through authenticated server access. Issues are historical
records and are not automatically closed: verify the current deployment before
repairing or resolving an incident. This does not monitor application health,
or detect a powered-off/disconnected machine from outside the server.

### Token provisioning (deferred until SOPS setup)

CI reports use `GITHUB_TOKEN` and work without a separate credential. Server
reports queue locally until `/var/lib/homeserver-reporting/github-token` exists.
Provision this path with SOPS later using a fine-grained GitHub token limited
to this repository, with **Issues: Read and write** and **Metadata: Read** only.
The directory must be root-owned mode `0700`, and the token file root-owned mode
`0600`. Never put the token in Nix source, Git, command arguments, or an issue.
No token or SOPS keys are included in this change.

```sh
systemctl status homeserver-reporting.timer
sudo journalctl -u homeserver-reporting.service -n 30 --no-pager
sudo systemctl start homeserver-reporting.service
```

Once the token is provisioned, delivery resumes on the next timer run. To test
GitHub delivery without breaking comin, run
`sudo homeserver-report-failures --self-test`; it creates one deduplicated test
incident, which can be closed afterward.
