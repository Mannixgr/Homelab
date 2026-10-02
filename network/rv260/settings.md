# Cisco RV260 settings (sanitized)

Source: web UI, read by hand. The raw backup file is not published.

## Role
Router, firewall and DHCP server for the lab LAN. Sits behind the Rogers
gateway (double NAT), because the gateway cannot be put into bridge mode.

## VLANs
| VLAN ID | Name | Subnet | Inter-VLAN routing | Device management |
|---------|------|--------|--------------------|-------------------|
| 1 | Default | 192.168.1.0/24 | Enabled | Enabled |

All LAN ports (LAN1-LAN8) are untagged members of VLAN 1. The network is
currently flat; segmentation into separate VLANs is planned, not built.

## DHCP
- Server on VLAN 1, address pool 192.168.1.100 - 192.168.1.149
- CT100 (Homepage) uses 192.168.1.100, which is inside the pool. It has a
  static DHCP reservation so the router cannot hand that address to another
  device.

## Ports
- WAN: 1000 Mbps full duplex, private address from the Rogers gateway
- LAN8: the only LAN port in use (100 Mbps full duplex); the rest of the
  lab connects through it
