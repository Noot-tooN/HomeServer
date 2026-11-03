{config, lib, pkgs, ...}: let
  host = "homeserver.tail0fa2e4.ts.net";
  origin = "https://${host}";
  apps = [
    {
      name = "Heating";
      path = "/heating";
      icon = "fas fa-temperature-half";
      port = 8443;
      upstream = config.services.smartthermweb.port;
      legacyHost = "heating.homeserver.com";
    }
    {
      name = "Torrents";
      path = "/torrents";
      icon = "fas fa-download";
      port = 8445;
      upstream = 8080;
      stripPrefix = true;
      legacyHost = "torrent.homeserver.com";
      # qBittorrent validates Host against its backend port. Normalize only
      # our own Origin/Referer; foreign origins stay unchanged and are rejected.
      requestGuards = ''
        @foreignOrigin {
          header Origin *
          not header Origin ${origin}
        }
        respond @foreignOrigin 403
        @foreignReferer {
          header Referer *
          not header Referer ${origin}/*
        }
        respond @foreignReferer 403
      '';
      proxyHeaders = ''
        header_up Host {upstream_hostport}
        header_up X-Forwarded-Host {upstream_hostport}
        header_up Origin ^https://${builtins.replaceStrings ["."] ["[.]"] host}$ http://127.0.0.1:8080
        header_up Referer ^https://${builtins.replaceStrings ["."] ["[.]"] host}(/|$) http://127.0.0.1:8080$1
        header_down Set-Cookie "(?i)(;[ ]*path=)/([;]|$)" "$1/torrents/$2"
      '';
    }
    {
      name = "Media";
      path = "/media";
      icon = "fas fa-film";
      port = 8446;
      upstream = 8096;
      legacyHost = "media.homeserver.com";
    }
    {
      name = "Jackett";
      path = "/jackett";
      icon = "fas fa-magnifying-glass";
      port = 8447;
      upstream = 9117;
    }
  ];
  legacyApps = builtins.filter (app: app ? legacyHost) apps;
  hosts = [host] ++ map (app: app.legacyHost) legacyApps;
  hostRule = lib.concatMapStringsSep " || " (name: "Host(`${name}`)") hosts;
  sniRule = lib.concatMapStringsSep " || " (name: "HostSNI(`${name}`)") hosts;
  metadata = name: {inherit name; namespace = "kube-system";};
  backendPorts = [
    {name = "https"; port = 8444; protocol = "TCP";}
    {name = "http"; port = 8081; protocol = "TCP";}
  ];
in {
  services.smartthermweb.publicOrigin = origin;
  services.smartthermweb.basePath = "/heating";

  # Apply only URL settings while each service is stopped. Existing credentials,
  # libraries and indexer settings stay in their private runtime config files.
  systemd.services.jellyfin.preStart = lib.mkBefore ''
    ${pkgs.python3}/bin/python3 ${../scripts/service_base_path.py} jellyfin ${lib.escapeShellArg "${config.services.jellyfin.configDir}/network.xml"} /media
  '';
  systemd.services.jackett.preStart = lib.mkBefore ''
    ${pkgs.python3}/bin/python3 ${../scripts/service_base_path.py} jackett /var/lib/jackett/.config/Jackett/ServerConfig.json /jackett
  '';

  # Caddy asks tailscaled for the node certificate and renews it automatically.
  # HTTPS Certificates must first be enabled in the tailnet's DNS settings.
  services.tailscale.permitCertUid = "caddy";

  services.homer = {
    enable = true;
    virtualHost = {
      caddy.enable = true;
      domain = "https://${host}:8444";
    };
    settings = {
      title = "Home";
      subtitle = "";
      documentTitle = "HomeServer";
      icon = "fas fa-house";
      header = true;
      footer = false;
      columns = "4";
      connectivityCheck = true;
      links = [];
      defaults = {
        layout = "list";
        colorTheme = "auto";
      };
      services = [{
        items = map (app: {
          inherit (app) name icon;
          url = "${origin}${app.path}/";
        }) apps;
      }];
    };
  };

  services.caddy = {
    enable = true;
    virtualHosts = lib.listToAttrs (
      # Keep old port bookmarks usable while all dashboard links use :443.
      map (app: lib.nameValuePair "https://${host}:${toString app.port}" {
        extraConfig = ''
          @prefixed path ${app.path} ${app.path}/*
          redir @prefixed ${origin}{uri} 308
          redir ${origin}${app.path}{uri} 308
        '';
      }) apps
      ++ map (app: lib.nameValuePair "https://${app.legacyHost}:8444" {
        # An old HTTPS bookmark still needs the old CA before its redirect can
        # run. All dashboard links use the trusted Tailscale hostname instead.
        extraConfig = ''
          tls internal
          @prefixed path ${app.path} ${app.path}/*
          redir @prefixed ${origin}{uri} 308
          redir ${origin}${app.path}{uri} 308
        '';
      }) legacyApps
      ++ map (name: lib.nameValuePair "http://${name}:8081" {
        extraConfig = let
          matchingApps = builtins.filter (app: (app.legacyHost or "") == name) apps;
          destination = if matchingApps == [] then origin else "${origin}${(builtins.head matchingApps).path}";
        in ''
          redir ${destination}{uri} 308
        '';
      }) hosts
    ) // {
      "https://${host}:8444".extraConfig = ''
        header Referrer-Policy same-origin
        ${lib.concatMapStringsSep "\n" (app: ''
          redir ${app.path} ${app.path}/ 308
          ${if app.stripPrefix or false then "handle_path" else "handle"} ${app.path}/* {
            ${app.requestGuards or ""}
            reverse_proxy 127.0.0.1:${toString app.upstream} {
              ${app.proxyHeaders or ""}
              flush_interval -1
              transport http {
                response_header_timeout 400s
              }
            }
          }
        '') apps}
      '';
    };
  };

  # k3s ServiceLB owns external :80/:443. Route only our hostnames to Caddy.
  # Preserve the existing manifest/resource names so the old route is updated
  # in place rather than leaving an unmanaged resource behind.
  # 10.42.0.1 is this single-node cluster's existing cni0 host address.
  networking.firewall.interfaces.cni0.allowedTCPPorts = [8081 8444];
  services.k3s.manifests.smartthermweb-ingress.content = [
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = metadata "smartthermweb-caddy";
      spec.ports = backendPorts;
    }
    {
      apiVersion = "v1";
      kind = "Endpoints";
      metadata = metadata "smartthermweb-caddy";
      subsets = [{
        addresses = [{ip = "10.42.0.1";}];
        ports = backendPorts;
      }];
    }
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRouteTCP";
      metadata = metadata "smartthermweb";
      spec = {
        entryPoints = ["websecure"];
        routes = [{
          match = sniRule;
          services = [{name = "smartthermweb-caddy"; port = 8444;}];
        }];
        tls.passthrough = true;
      };
    }
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRoute";
      metadata = metadata "home-dashboard-http";
      spec = {
        entryPoints = ["web"];
        routes = [{
          kind = "Rule";
          match = hostRule;
          services = [{name = "smartthermweb-caddy"; port = 8081;}];
        }];
      };
    }
  ];
}
