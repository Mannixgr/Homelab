# Tailscale Funnel: public access to the portfolio site

The portfolio site is served by Caddy on CT101 and exposed to the public
internet through Tailscale Funnel. No ports are forwarded on the router, and
the site is not reachable through the home network's public IP.

## Traffic path

    Visitor (HTTPS) -> Tailscale Funnel -> CT101 tailscaled -> Caddy (127.0.0.1:80)

- TLS is terminated by Tailscale, so Caddy only listens on plain HTTP.
- Funnel is enabled on CT101 itself, not on the Proxmox host.
- The RV260 sits behind the Rogers gateway (double NAT), so inbound port
  forwarding wasn't an option anyway. Funnel works through outbound
  connections, which sidesteps this.

## Status output

    $ tailscale funnel status

    https://portfolio-site.<tailnet>.ts.net (Funnel on)
    |-- / proxy http://127.0.0.1:80

## Related

- Caddy config: ../caddy/Caddyfile
- Deploy pipeline (GitHub Actions -> tailnet -> rsync): ../../docs/2026-09-deploy-pipeline.md
