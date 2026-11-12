# Homelab

Configs, diagrams and write-ups for my home lab (Proxmox, Cisco RV260 and
Catalyst 3550, Tailscale, strongSwan) and its site-to-site VPN to AWS. Secrets, public IPs and credentials are removed.

![Network diagram](https://raw.githubusercontent.com/Mannixgr/mannix-portfolio/main/homelab-network.svg)

## What's here

| Path | Contents | Status |
|------|----------|--------|
| Network diagram (above) | Lives in the `mannix-portfolio` repo, linked here so one edit updates every README | Implemented, VLAN zones planned |
| `docs/2026-09-deploy-pipeline.md` | Write-up: what broke building the deploy pipeline | Done |
| `ci/deploy.yml` | GitHub Actions deploy workflow (reference copy) | Implemented |
| `services/caddy/` | Caddy config for the portfolio site | Implemented |
| `services/tailscale/` | Funnel setup and CI access policy | Implemented |
| `services/resale/` | Runbook: CT104 LXC for the resale dashboard, firewall, Funnel, deploy, backups, restore drill | Implemented |
| `scripts/rsync-wrapper.sh` | Restricts the deploy key to one rsync target | Implemented |
| `network/rv260/` | Sanitized RV260 settings: VLAN, DHCP, static route, firewall | Implemented |
| `network/strongswan/` | strongSwan VM: IPsec VPN to the AWS dev VPC, rebuild runbook | Implemented |
| `network/` (Catalyst 3550) | Sanitized switch config | Coming soon |
