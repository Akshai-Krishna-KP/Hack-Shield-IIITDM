# Hack & Shield IIITDM Lab

This repository currently provisions five intentionally vulnerable services on an Ubuntu Server 24.04 VM. It does not build the VM image; install Ubuntu first, clone this repository inside the guest, and run the installer below from a sudo-capable administrator account.

## Provision the guest

```bash
git clone <repository-url> Hack-Shield-IIITDM
cd Hack-Shield-IIITDM
sudo bash script/setup.sh
```

The script installs system dependencies, creates `player`, `user1`–`user5`, and the `hs-service-editors` group, then deploys the numbered services and systemd units. It prompts to set a password when creating `player` in an interactive terminal. If run non-interactively, set one later with `sudo passwd player`. Log out and back in as `player` after setup so the new group membership takes effect.

The install needs access to Ubuntu package repositories and Python package indexes. Fresh installs generate per-VM flags; to supply organizer-selected values, pass the relevant `SERVICE1_FLAG`, `SERVICE1_RAIHAN_PASSWORD`, `SERVICE2_FLAG`, `SERVICE2_ADMIN_PASSWORD`, `SERVICE3_FLAG`, `SERVICE4_SSRF_FLAG`, or `SERVICE5_FLAG` variables through `sudo --preserve-env=...`. Existing flags and Service 2 and Service 5 databases are preserved on reruns unless `SERVICE2_RESEED=1` is set.

For example, after exporting chosen values, run `sudo --preserve-env=SERVICE2_ADMIN_PASSWORD,SERVICE4_SSRF_FLAG,SERVICE5_FLAG bash script/setup.sh`.

## QEMU networking

Guest setup cannot change QEMU's host-side port forwarding. Start QEMU with host forwards for the services you intend to expose: guest ports `9001` (Service 1), `3306` (the intentionally exposed MySQL challenge), `4444` (Service 2), `1337` (Service 3), `7007` (Service 4), and `8005` (Service 5). Change the host-side ports if they conflict with host services and update the team port map. Do **not** forward `7108`; it is Service 4's loopback-only SSRF target. Restrict forwarded ports to the isolated competition network.

## Current scope and status

Service 4's public preview app and internal inventory API are supervised by one unit, `hackshield-service4.service`. Service 5 is HackMart, a coupon TOCTOU/race-condition challenge on port `8005`, supervised by `hackshield-service5.service`; its flag is `/opt/flag/flag5`. Service 4 uses `/opt/flag/flag4`; Services 1–3 use `/opt/flags/flag1` through `flag3`. `player` can restart only the five named units through a narrow sudoers rule.

This repository does not yet implement the 20-service selection described in the planning documents, nor the game server, scoring, monitoring, per-round reset, or host firewall/network policy. Root-level Markdown notes are excluded by `.gitignore` and include older service numbering and manual deployment examples; use the scripts and files in this checkout as the current implementation reference.

The current flag model also has a known limit: participants can edit service code and restart it, and the service account can read that service's own flag. A modified service can therefore expose its own flag. If the rules require preventing that, add an out-of-process flag broker/validator before the competition; filesystem permissions alone cannot close this gap.

These challenge services are deliberately vulnerable. Deploy them only in the isolated lab and review the QEMU host firewall before exposing any forwarded port.
