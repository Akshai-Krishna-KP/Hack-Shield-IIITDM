# Hack & Shield IIITDM Lab

This repository provisions Services 1–9 on an Ubuntu Server 24.04 VM. It does not build the VM image; install Ubuntu, clone this repository in the guest, and run the installer from a sudo-capable administrator account.

## Provision the guest

```bash
git clone <repository-url> Hack-Shield-IIITDM
cd Hack-Shield-IIITDM
sudo bash script/setup.sh
```

The script installs system dependencies, creates `player`, `user1`–`user9`, and the `hs-service-editors` group, then runs all nine deployment scripts. At boot, the guest reads its QEMU boot configuration, registers with the game server, and starts only the six services and ports returned by that server. Setup prompts for a `player` password when interactive; otherwise set one later with `sudo passwd player`. Log out and back in as `player` after setup so group membership takes effect.

The install needs Ubuntu and Python package indexes, plus MongoDB's package repository for Service 9. Fresh installs generate per-VM flags; organizer overrides can be passed through the corresponding `SERVICE1_FLAG` through `SERVICE9_FLAG` variables and service-specific settings such as `SERVICE8_JWT_SECRET`, `SERVICE9_RESEED`, and `MONGODB_SERIES`. Service 2, 5, and 9 preserve persistent data on reruns unless their reseed option is enabled.

## QEMU networking

Guest setup cannot change host-side forwarding. The game server assigns each of the six services a random port in `5000`–`5050`, so QEMU must forward that whole range (`script/run-hackshield.sh` does this). Forward MySQL port `3306` for Service 1's intentional database exposure; the guest starts MySQL only when Service 1 is allocated. Do **not** forward `7108` (Service 4's loopback SSRF target), `6006`, or MongoDB port `27017`. Restrict access to the isolated competition network.

## Flags and deployment scope

All service flags use `/opt/flags/flagN`. Service 9's `hackshield-service9-flag-sync.path` watches `flag9` and updates its classified MongoDB record only while `hackshield-service9.service` is active. The manager grants `player` restart permission only for the six currently allocated services. Service 4's public preview app and internal inventory API share `hackshield-service4.service`; Service 5 is the HackMart race-condition challenge; Services 6–9 provide their documented LFI, weak-cookie, JWT, and NoSQL-injection challenges.

This repository does not implement the 20-service selection, game server, scoring, monitoring, per-round reset, or host firewall/network policy. Root-level Markdown notes are excluded by `.gitignore`; use the scripts and files in this checkout as the deployment reference. These services are deliberately vulnerable and belong only in an isolated lab. The current flag model allows participants who can modify and restart a service to expose that service's own flag; a separate flag broker is needed to prevent that.
