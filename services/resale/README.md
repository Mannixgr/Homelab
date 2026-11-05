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

Debian 12, unprivileged, 1 vCPU, 512 MB RAM, 8 GB disk, hostname `resale`, IP `192.168.1.21`. Add a DHCP reservation on the RV260 (or a static IP) so the address never moves.

## 3. Proxmox firewall (CT102, firewall on)

- IN: drop everything except tcp/22 from `<mac-lan-ip>`.
- OUT: allow udp/tcp 53 to the gateway; drop `192.168.1.0/24` and `10.0.0.0/24`; allow everything else.

Why: it is a public login surface, so a compromise must not reach the LAN, the strongSwan VM or the portfolio LXC. Put the allow-DNS rule above the drops.

## 4. Base hardening (inside CT102)

- SSH key-only, `PermitRootLogin no`, a non-root `<admin>` user.
- `apt install unattended-upgrades sqlite3 awscli python3-venv rsync`.
- `useradd --system --home /var/lib/resale --shell /usr/sbin/nologin resale`; `install -d -m 0700 -o resale /var/lib/resale /var/lib/resale/receipts`; `install -d -m 0700 /var/backups/resale`.

## 5. Tailscale and Funnel

1. Install Tailscale, `tailscale up --hostname=resale`.
2. In the Tailscale admin, enable HTTPS and give the node the Funnel attribute (see `services/tailscale/funnel.md`). Do not widen the `tag:ci` ACL.
3. `tailscale funnel --bg 8000`. The URL is `https://resale.<tailnet>.ts.net`.

## 6. Deploy

From the Mac, in the app repo:

```
rsync -av --delete --exclude .venv --exclude tests --exclude web-test ./ <admin>@192.168.1.21:/opt/resale/
```

On CT102:

```
cd /opt/resale && python3 -m venv .venv && .venv/bin/pip install --require-hashes -r requirements.lock
cp deploy/resale.service deploy/resale-backup.service deploy/resale-backup.timer /etc/systemd/system/
```

Write `/etc/resale.env` (`chmod 0600`, owner root, never in git):

```
RESALE_DB=/var/lib/resale/resale.db
RESALE_RECEIPTS=/var/lib/resale/receipts
RESALE_ORIGIN=https://resale.<tailnet>.ts.net
BACKUP_BUCKET=<bucket name from terraform output>
```

Then `systemctl daemon-reload && systemctl enable --now resale.service resale-backup.timer`. Create the first admin invite as the `resale` user with the env loaded:
`python -m app.cli invite --name Mannix --share 2500 --admin`, and open the link.

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
