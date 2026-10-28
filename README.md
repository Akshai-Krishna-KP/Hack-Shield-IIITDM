# Hack & Shield IIITDM Lab

This repository currently provisions Services 1–5, 8, and 9 on an Ubuntu Server 24.04 VM. It does not build the VM image; install Ubuntu first, clone this repository inside the guest, and run the installer below from a sudo-capable administrator account.

## Provision the guest

```bash
git clone <repository-url> Hack-Shield-IIITDM
cd Hack-Shield-IIITDM
sudo bash script/setup.sh
```

The script installs system dependencies, creates `player`, `user1`–`user5`, `user8`, `user9`, and the `hs-service-editors` group, then deploys those seven services and systemd units. Service 9 installs MongoDB from its official Ubuntu repository and binds it locally. MongoDB needs AVX exposed to the guest; use `-cpu host` with QEMU. It prompts to set a password when creating `player` in an interactive terminal. If run non-interactively, set one later with `sudo passwd player`. Log out and back in as `player` after setup so the new group membership takes effect.

The install needs access to Ubuntu package repositories and Python package indexes, plus MongoDB's package repository for Service 9. Fresh installs generate per-VM flags; to supply organizer-selected values, pass the relevant `SERVICE1_FLAG`, `SERVICE1_RAIHAN_PASSWORD`, `SERVICE2_FLAG`, `SERVICE2_ADMIN_PASSWORD`, `SERVICE3_FLAG`, `SERVICE4_SSRF_FLAG`, `SERVICE5_FLAG`, `SERVICE8_FLAG`, `SERVICE8_JWT_SECRET`, or `SERVICE9_FLAG` variables through `sudo --preserve-env=...`. Service 2, 5, and 9 preserve persistent data on reruns; `SERVICE2_RESEED=1` and `SERVICE9_RESEED=1` request reseeding.

For example, after exporting chosen values, run `sudo --preserve-env=SERVICE2_ADMIN_PASSWORD,SERVICE4_SSRF_FLAG,SERVICE5_FLAG,SERVICE8_FLAG,SERVICE8_JWT_SECRET,SERVICE9_FLAG bash script/setup.sh`.

## QEMU networking

Guest setup cannot change QEMU's host-side port forwarding. Start QEMU with host forwards for the services you intend to expose: guest ports `9001` (Service 1), `3306` (the intentionally exposed MySQL challenge), `4444` (Service 2), `1337` (Service 3), `7007` (Service 4), `8005` (Service 5), `5001` (Service 8), and `5002` (Service 9). Change host-side ports if they conflict and update the team port map. Do **not** forward `7108` (Service 4's loopback-only SSRF target) or `27017` (Service 9's MongoDB). Restrict forwarded ports to the isolated competition network.

## Current scope and status

Service 4's public preview app and internal inventory API are supervised by one unit, `hackshield-service4.service`. Service 5 is HackMart, a coupon TOCTOU/race-condition challenge on port `8005`. Service 8 is the JWT legacy-header validation challenge on port `5001`; Service 9 is the MongoDB operator-injection challenge on port `5002`. Each is supervised by its matching systemd unit. Services 4–5 and 8–9 use `/opt/flag/flagN`; Services 1–3 use `/opt/flags/flagN`. `player` can restart only the seven deployed service units through a narrow sudoers rule.

Services 6–7 and the 20-service selection, game server, scoring, monitoring, per-round reset, and host firewall/network policy are not implemented. Root-level Markdown notes are excluded by `.gitignore` and some include manual deployment examples; use the scripts and files in this checkout as the current implementation reference.

The current flag model also has a known limit: participants can edit service code and restart it, and the service account can read that service's own flag. A modified service can therefore expose its own flag. If the rules require preventing that, add an out-of-process flag broker/validator before the competition; filesystem permissions alone cannot close this gap.

These challenge services are deliberately vulnerable. Deploy them only in the isolated lab and review the QEMU host firewall before exposing any forwarded port.
