# Resale dashboard on CT102

Invite-only web app (FastAPI + SQLite, receipts on disk) in its own unprivileged LXC, public through Tailscale Funnel. App repo: `resale-dashboard` (`deploy/`, `infra/`, `requirements.lock`). Decisions D-60 to D-62.

```
Internet -> Funnel 443 -> CT102 192.168.1.21 -> 127.0.0.1:8000 (uvicorn)
```

Status: written, not yet run. Every step below changes live infrastructure; do them yourself, in order. `<tailnet>`, `<admin>` and `<mac-lan-ip>` are placeholders.

## 1. Before the first deploy (in the app repo)

1. `pip-audit -r requirements.lock` must say no known vulnerabilities.
2. Run `/security-review` on the branch (or a fresh reviewer, told to check against ASVS L2 V2/V3/V4/V12/V14). Fix Critical/High first.
3. Work through the "Needs a human check" list in the app README.

## 2. Create CT102 (Proxmox, `192.168.1.50`)

Debian 12, unprivileged, 1 vCPU, 512 MB RAM, 8 GB disk, hostname `resale`, IP `192.168.1.21`. Use a **static** IP `192.168.1.21/24` (gateway `192.168.1.1`) in the Proxmox net config, not DHCP: the firewall blocks the gateway except for DNS, so DHCP would not work.

Tailscale needs `/dev/net/tun`, which an unprivileged CT does not get by default. On the Proxmox host, add to `/etc/pve/lxc/102.conf` either (PVE 8.1 or later):

```
dev0: /dev/net/tun
```

or (older PVE):

```
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

Then `pct reboot 102` (a full restart; the device is only added at start) and check `ls -l /dev/net/tun` inside the CT.

## 3. Proxmox firewall (CT102, firewall on)

- IN: drop everything except tcp/22 from `<mac-lan-ip>`.
- OUT, an allow-list, in this order:
  1. allow udp/tcp 53 to the gateway
  2. drop `192.168.1.0/24`, `10.0.0.0/24`, `10.20.0.0/16`
  3. allow tcp 80, tcp 443, udp 41641, udp 3478 (web, HTTPS, Tailscale)
  4. drop all other outbound

Why: it is a public login surface, so a compromise must not reach the LAN, the strongSwan VM or the portfolio LXC. Keep the rules in that order.

## 4. Base hardening (inside CT102)

- SSH key-only, `PermitRootLogin no`, a non-root `<admin>` user.
- `apt install unattended-upgrades sqlite3 awscli curl`. Debian 12 ships Python 3.11 and the app needs 3.12, so install it with uv (step 6).
- `useradd --system --home /var/lib/resale --shell /usr/sbin/nologin resale`; `install -d -m 0700 -o resale /var/lib/resale /var/lib/resale/receipts`; `install -d -m 0700 /var/backups/resale`.

## 5. Tailscale and Funnel

Check step 2's `/dev/net/tun` is present first; without it `tailscaled` fails to start.

1. In the Tailscale admin, add `tag:resale` to `tagOwners` and a `nodeAttrs` entry giving it `funnel` (see `services/tailscale/acl-excerpt.hujson`). Add **no** grants with `src` `tag:resale`: default deny means a compromised CT102 cannot reach any other tailnet node. Enable HTTPS (`services/tailscale/funnel.md`). Do not widen the `tag:ci` ACL.
2. Install Tailscale on CT102 and join as the tag: `tailscale up --hostname=resale --advertise-tags=tag:resale`. Approve in the admin console if asked, and check the node shows `tag:resale`.
3. `tailscale funnel --bg 8000`. The URL is `https://resale.<tailnet>.ts.net`.

## 6. Deploy

`/opt/resale` stays root-owned and read-only to `resale`; the service writes only `/var/lib/resale`. Once, on CT102:

```
sudo install -d -m 0755 -o root -g root /opt/resale
```

From the Mac, in the app repo, ship the committed tree only (no `.git`, `.superpowers`, `.venv` or caches):

```
git archive HEAD | ssh <admin>@192.168.1.21 'sudo tar -x --no-same-owner -C /opt/resale'
```

Redeploys use the same command. `tar -x` overwrites but does not delete, so after removing a file from the repo, delete it from `/opt/resale` too.

On CT102 (first deploy; after a redeploy, rerun only the `uv pip install` line if `requirements.lock` changed, then `systemctl restart resale`):

```
curl -LsSf https://astral.sh/uv/install.sh | sh   # or a Debian package if one exists
# root's default Python dir is under /root, which the resale user can't read and ProtectHome=yes hides
export UV_PYTHON_INSTALL_DIR=/opt/uv-python
uv python install 3.12
chmod -R a+rX /opt/uv-python
uv venv --python 3.12 /opt/resale/.venv
uv pip install --python /opt/resale/.venv --require-hashes -r /opt/resale/requirements.lock
runuser -u resale -- /opt/resale/.venv/bin/python -V   # must print Python 3.12.x
cp /opt/resale/deploy/resale.service /opt/resale/deploy/resale-backup.service /opt/resale/deploy/resale-backup.timer /etc/systemd/system/
```

Write `/etc/resale.env` (`chmod 0600`, owner root, never in git):

```
RESALE_DB=/var/lib/resale/resale.db
RESALE_RECEIPTS=/var/lib/resale/receipts
RESALE_ORIGIN=https://resale.<tailnet>.ts.net
BACKUP_BUCKET=<bucket name from terraform output>
AWS_DEFAULT_REGION=ca-central-1
```

Then `systemctl daemon-reload && systemctl enable --now resale.service resale-backup.timer`. Create the first admin invite as root, running as the `resale` user with the env loaded:

```
cd /opt/resale && sudo bash -c 'set -a; . /etc/resale.env; exec runuser -u resale -- /opt/resale/.venv/bin/python -m app.cli invite --name Mannix --share 2500 --admin'
```

Open the printed link.

## 7. Backups

1. In `infra/`, copy `backend.hcl.example` to `backend.hcl`, fill in the state bucket, then `terraform init -backend-config=backend.hcl`, `terraform plan`, and `terraform apply -var bucket_name=<unique name>` (you apply; the bucket and a put-only IAM user are created).
2. Create the IAM user's access key in the console or CLI (outside Terraform, so it stays out of state). Put it in `/root/.aws/credentials` on CT102 (`0600`), readable by root only. The web service does not see it.
3. Run `systemctl start resale-backup.service` once and check the two objects under `backups/` in the bucket.
4. Add a Proxmox `vzdump` schedule for CT102.

The nightly timer runs 03:30, keeps 14 local copies, S3 expires objects after 30 days.

## 8. Verify

- From a phone off Wi-Fi and off the tailnet, `https://resale.<tailnet>.ts.net` shows the login page.
- `curl -I` shows CSP, HSTS and nosniff. `/docs` returns 404. A POST with another Origin returns 403.
- Six wrong passwords from the phone give "Too many tries". Your own login still needs the authenticator code.
- From CT102, `curl 192.168.1.20` and `ping 192.168.1.30` fail; `curl https://example.com` works.
- The portfolio's Funnel is unchanged.

## 9. Restore drill

Download a `db-*.db` and `receipts-*.tar.gz` from S3 (with your admin profile, since the backup user cannot read), extract the receipts, and start a local run with `RESALE_DB` and `RESALE_RECEIPTS` pointing at them (see the app README). Log in and open a receipt. Repeat after any change to the backup path.
