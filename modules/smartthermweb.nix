{pkgs, smartthermweb, ...}: {
  services.smartthermweb = {
    enable = true;
    package = smartthermweb.packages.${pkgs.stdenv.hostPlatform.system}.default;
    publicOrigin = "https://heating.homeserver.com";
    port = 3000;
  };

  services.caddy.virtualHosts."https://heating.homeserver.com:8444".extraConfig = ''
    tls internal
    reverse_proxy 127.0.0.1:3000 {
      flush_interval -1
      transport http {
        response_header_timeout 400s
      }
    }
  '';
  # Traefik owns external :443 through k3s ServiceLB. Pass only this SNI
  # host through to Caddy; Caddy retains the certificate and TLS termination.
  # 10.42.0.1 is this single-node cluster's existing cni0 host address.
  networking.firewall.interfaces.cni0.allowedTCPPorts = [8444];
  services.k3s.manifests.smartthermweb-ingress.content = [
    {
      apiVersion = "v1";
      kind = "Service";
      metadata = { name = "smartthermweb-caddy"; namespace = "kube-system"; };
      spec.ports = [{ name = "https"; port = 8444; protocol = "TCP"; }];
    }
    {
      apiVersion = "v1";
      kind = "Endpoints";
      metadata = { name = "smartthermweb-caddy"; namespace = "kube-system"; };
      subsets = [{
        addresses = [{ ip = "10.42.0.1"; }];
        ports = [{ name = "https"; port = 8444; protocol = "TCP"; }];
      }];
    }
    {
      apiVersion = "traefik.io/v1alpha1";
      kind = "IngressRouteTCP";
      metadata = { name = "smartthermweb"; namespace = "kube-system"; };
      spec = {
        entryPoints = ["websecure"];
        routes = [{
          match = "HostSNI(`heating.homeserver.com`)";
          services = [{ name = "smartthermweb-caddy"; port = 8444; }];
        }];
        tls.passthrough = true;
      };
    }
  ];
}
