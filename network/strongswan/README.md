# strongSwan VM: site-to-site VPN to AWS

The homelab end of the IPsec VPN to the AWS dev VPC (`10.20.0.0/16`). The AWS
side (Virtual Private Gateway, customer gateway, static VPN connection) is
Terraform in the `enterprise-hybrid-aws` repo. Pre-shared keys, tunnel
endpoint IPs and the home public IP are not published.

## Host
- Debian 13 VM on Proxmox, `192.168.1.30`, strongSwan 6.0.1 (`swanctl`)
- Route-based IPsec with XFRM interfaces (not VTI), static routing (no BGP)
- The RV260 sends `10.20.0.0/16` to this VM (see `../rv260/settings.md`)

## Files on the VM
| File | Contents |
|------|----------|
| `/etc/swanctl/conf.d/aws.conf` | Two connections, one per AWS tunnel |
| `/etc/swanctl/conf.d/aws-secrets.conf` | Pre-shared keys (mode 600) |
| `/etc/strongswan.d/charon-aws.conf` | `install_routes = no`; routes come from the XFRM interfaces |
| `/etc/sysctl.d/90-aws-vpn.conf` | `ip_forward = 1`, `rp_filter = 2` |
| `/etc/network/interfaces.d/aws-vpn` | `xfrm1`/`xfrm2` interfaces and routes (ifupdown) |

## Tunnel settings
| | Tunnel 1 | Tunnel 2 |
|--|----------|----------|
| Interface | `xfrm1`, `if_id 1` | `xfrm2`, `if_id 2` |
| Inside address (VM / AWS) | `169.254.10.2/30` / `.10.1` | `169.254.11.2/30` / `.11.1` |
| Route to `10.20.0.0/16` | metric 100 | metric 200 |

- MTU 1399 on both interfaces
- IKEv2, `aes256-sha256-modp2048`; local ID is the home public IP
- `start_action = start`, DPD 10s, child SA rekey 50m, `mobike = no`
- NAT traversal is required: the VM sits behind double NAT (Rogers gateway, RV260)

## Verified
- Both tunnels ESTABLISHED, pings to `169.254.10.1` and `169.254.11.1`, AWS
  tunnel telemetry UP
- Survived a VM reboot; no retransmits overnight
- Not yet tested: traffic from another LAN host (for example the LXC at
  `192.168.1.20`) to an address in the VPC

## Rebuild runbook
The AWS dev environment is destroyed when idle. Each rebuild creates new
tunnel endpoint IPs and new pre-shared keys. The inside addresses are pinned
in Terraform, so the interface file does not change.

1. Apply dev through the pipeline (`enterprise-hybrid-aws`).
2. Read the new tunnel outside IPs and PSKs from the VPN connection.
3. On the VM, put the outside IPs in `aws.conf` and the PSKs in `aws-secrets.conf`.
4. `sudo swanctl --load-all`, then `sudo swanctl --list-sas`: both SAs ESTABLISHED.
5. Ping `169.254.10.1` and `169.254.11.1`, and check that the tunnels show UP in the AWS console.

If the home public IP changes, Terraform replaces the customer gateway and the
VPN connection, so the same steps apply.
