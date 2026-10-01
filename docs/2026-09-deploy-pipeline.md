# What broke: building a git-push deploy pipeline for the homelab

## Summary

I replaced manual `scp` uploads for my portfolio site with a GitHub Actions
deploy. A push to `main` starts a runner that joins my tailnet, then rsyncs
the site over SSH to a container in the homelab. Getting it to work took
four separate fixes, each of which failed with a different error.

## Setup

    GitHub Actions runner
      -> Tailscale (OAuth client, ephemeral node tagged tag:ci)
      -> SSH as `deploy` on CT101 (192.168.1.20)
      -> rsync into /var/www/html
      -> served by Caddy

The `deploy` user has no shell. Its key is restricted in `authorized_keys`
so it can only run an rsync receive command.

## Problem 1: wrong deploy path

The workflow and the `authorized_keys` restriction both targeted
`/var/www/portfolio/`, a path I had assumed. Before creating it, I checked
what Caddy actually serves:

    $ cat /etc/caddy/Caddyfile
    :80 {
        root * /var/www/html
        file_server
    }

Syncing to the wrong directory would have reported success while Caddy kept
serving the old files. I updated both the workflow destination and the
`authorized_keys` command to `/var/www/html/`.

## Problem 2: empty secrets

    Error: The ssh-private-key argument is empty. Maybe the secret has not
    been configured, or you are using a wrong secret name in your workflow file.

The Tailscale OAuth credentials hit the same error earlier. The workflow
parses fine with missing secrets and only fails at the step that uses them.
I set the secrets from the CLI, reading the key file directly to avoid
whitespace problems from copy-paste:

    gh secret set DEPLOY_SSH_KEY --repo <owner>/<repo> < ~/.ssh/<deploy-key>

## Problem 3: rsync not installed on the container

    bash: line 1: rsync: command not found
    rsync: connection unexpectedly closed (0 bytes received so far) [sender]
    rsync error: remote command not found (code 127) at io.c(232)

The log showed the host key being accepted and the connection working, so
Tailscale and SSH auth were fine and the failure was the remote command.
The minimal Debian container image didn't include rsync.

    apt update && apt install -y rsync
    which rsync    # /usr/bin/rsync

## Problem 4: protocol error from the forced command

    [Receiver] Invalid dir index: -1 (-101 - -100)
    rsync error: protocol incompatibility (code 2) at flist.c(2790)

My `authorized_keys` entry forced one fixed command, regardless of what the
client asked for:

    command="rsync --server -vlogDtprze.iLsfxC . /var/www/html/",restrict <public key>

The client and server disagreed on the transfer options, so the file list
exchange broke. I replaced the hardcoded string with a wrapper script, so
the key can still only run rsync into one directory:

    command="/home/deploy/rsync-wrapper.sh",restrict <public key>

The wrapper (also in `scripts/rsync-wrapper.sh`) runs the client's own
command only if it is an rsync server invocation that ends at the web root,
and rejects everything else:

    #!/bin/bash
    if [[ "$SSH_ORIGINAL_COMMAND" == "rsync --server "*" /var/www/html/" ]]; then
        exec $SSH_ORIGINAL_COMMAND
    else
        echo "Rejected command: $SSH_ORIGINAL_COMMAND" >&2
        exit 1
    fi

SSH puts the command the client requested into `SSH_ORIGINAL_COMMAND`. The
key can still only run rsync into one directory, but the transfer options
now come from the client, so they always match what it expects.

## Hardening: scoping the CI node on the tailnet

My Tailscale policy started with an allow-all grant (`*` to `*`), which also
covered the ephemeral CI node. I narrowed it so members keep full access and
`tag:ci` can reach exactly one host and port:

    "grants": [
      { "src": ["autogroup:member"], "dst": ["*"],             "ip": ["*"]  },
      { "src": ["tag:ci"],           "dst": ["192.168.1.20"],   "ip": ["22"] }
    ]

## What I'd do differently

Check the real web root and installed tools on the target before writing
the workflow, and test the SSH restriction with a manual rsync from my
laptop before pushing it into CI.
## Safeguards and next improvements

- `rsync --delete` mirrors the repo exactly, so a wrong destination path can
  wipe the wrong directory. Changing the path now means previewing first
  with `--dry-run`.
- The deploy user is restricted to rsync via `authorized_keys`, and the CI
  node is limited to SSH on one host through a Tailscale grant (see
  `services/tailscale/acl-excerpt.hujson`).
- Planned: pin the container's SSH host key in the workflow instead of
  `StrictHostKeyChecking=accept-new`.
