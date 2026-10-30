# Hack & Shield VM review (branch main @ review time)

Scope: README.md, HS-2026/VM Setup.md, script/setup.sh, script/service/0*_service.sh, service1..9/, systemd/, sql/, nodejs/service9_seed.js,
checked against the game server (Hack_n_Shield@zapdos: web_server.py `register_boot`, flagauthenticator.py, scanner.py, game_state.py)
and the launcher /home/zapdos/hacknshield26/run-hackshield.sh. No code was changed.

**Bottom line:** the VM does not integrate with the game server at all. Nothing reads fw_cfg, nothing calls `/api/register_boot`,
flags are static random `HS{serviceN_<hex>}` strings (not HMAC `FLAG{team_service_hex}`), never rotate, and every service binds a
hardcoded port instead of the `port_mapping` ports 5000-5050 the scanner checks. As-is, every team will score 0 on SLA and every
submitted flag will be rejected.

## 🔴 Blockers (game will not work)

- [ ] **No boot registration / fw_cfg reader.** `grep -r 'fw_cfg\|register_boot\|GAME_SERVER' .` returns nothing. script/setup.sh:1-101 ends without installing any agent.
  Fix: add `/usr/local/sbin/hs-boot-agent` + `hackshield-boot.service` (oneshot, `After=network-online.target`, enabled) that reads
  `/sys/firmware/qemu_fw_cfg/by_name/opt/org.hackshield/boot-config/raw` (needs `modprobe qemu_fw_cfg`), parses TEAM_NAME/GAME_SERVER_ADDR,
  takes `boot_time = int(time.time()*1000)`, POSTs `{team, boot_time}` with retries, and stores the response (`port_mapping`) in a root-only file
  e.g. `/etc/hackshield/runtime.json`. Run it before the service units (`Before=hackshield-service*.service`).
- [ ] **Flag format and generation mismatch.** script/service/01_service.sh:129 (and same pattern in 02..09, e.g. 03_service.sh:104, 09_service.sh:229) writes `HS{serviceN_<random>}` once.
  Server expects `FLAG{team_service_hex}` with hex = HMAC-SHA256(b"Hack&Shield", f"{team}-{service}-{tick}"), tick = boot_time + k*60000 ms, valid 5 min.
  Fix: a `hackshield-flagd.service` (root) / systemd timer every 60 s that computes the current tick from the stored boot_time
  (`tick = boot_time + ((now_ms-boot_time)//60000)*60000`) and atomically writes `/opt/flags/flagN` (keep owner userN, mode 0400) using the
  server's service name for that slot. Use exactly the same team string the server uses and the same hex digest length as flagauthenticator.py.
- [ ] **Flags are cached in memory, so rotation would not reach players.** service6/app.py:42 and service7/app.py:16 read the flag at import; service9 stores it in MongoDB once (script/service/09_service.sh:256-265, nodejs/service9_seed.js:6,172).
  Fix: read the file per request in 6/7 (as 1/2/4/5/8 already do); for service 9 have the flag daemon also run the `updateOne` (09_service.sh:264) each tick, or make app.py:144 read `/opt/flags/flag9` instead of `record.get("flag")`.
- [ ] **Services bind hardcoded ports, not `port_mapping`.** service1/server.py:14 (9001), service2/app.py:120 (4444), service3/run.py:3 (1337), service4/app.py:36 (7007), service5/app.py:337 (8005), systemd/hackshield-service6..9.service `Environment=PORT=8006/5007/5001/5002`.
  The scanner TCP-checks 6 random ports in 5000-5050 on the team IP -> all checks fail. Fix: make every app honour `PORT` env, and have the boot agent write
  `/etc/hackshield/serviceN.port.env` (`PORT=50xx`) from `port_mapping`, referenced via `EnvironmentFile=-` in each unit; only start the units listed in the mapping.
  Alternatively simpler for tomorrow: keep apps on fixed ports and add iptables `nat PREROUTING REDIRECT --to-ports` from each mapped 50xx port to the service's fixed port.
- [ ] **service10 does not exist.** game_state.py:43 samples from service1..service10; the VM only ships 1-9. ~40% of games will assign service10 and that slot is permanently down / unflaggable.
  Fix: remove `service10` from SERVICES on the server, or ship a 10th service.
- [ ] **Launcher forwards do not match.** run-hackshield.sh:63 forwards 22, 9001, 3306, 4444, 1337, 8005, 5006, 7007. Service 6 listens on 8006 (not 5006), 7/8/9 (5007/5001/5002) are not forwarded, and none of 5000-5050 is forwarded.
  Fix: forward the full 5000-5050 range (or the mapped ports) and drop the fixed per-service forwards; also note that with `-nic user` (SLIRP) all teams on one host reach the game server from the *host* IP, so `register_boot` (identifies team by source IP, web_server.py:640-644) cannot distinguish teams -> use bridged/tap networking with a per-team IP.
- [ ] **Units are installed but never enabled or started.** No `systemctl enable` for hackshield-service*.service in any script (only mysql/mongod: 01_service.sh:75, 09_service.sh:175); 01_service.sh:208 says "start managed externally". After reboot of the qcow2 nothing listens.
  Fix: `systemctl enable --now hackshield-serviceN.service` at the end of each 0N script (or enable them from the boot agent after the port mapping arrives).

## 🟠 High (unintended leaks, trivial kills, setup breakage)

- [ ] **Not Debian-compatible.** 01_service.sh:68-72 installs `mysql-server` and edits `/etc/mysql/mysql.conf.d/mysqld.cnf` (Ubuntu-only path; Debian has `default-mysql-server`/MariaDB and `/etc/mysql/mariadb.conf.d/50-server.cnf`) -> script exits at 01_service.sh:101. 09_service.sh:108 hardcodes `repo.mongodb.org/apt/ubuntu noble`. 09 also uses `gpg` (09_service.sh:106) which is not in setup.sh:30-33 install list.
  Fix: pin the guest to Ubuntu 24.04 (README says so) or branch on `/etc/os-release`; add `gnupg ca-certificates` to setup.sh's apt list.
- [ ] **Service 5 session secret is public.** service5/app.py:15 falls back to `"local-ctf-secret-change-me"`; systemd/hackshield-service5.service has no EnvironmentFile/HACKMART_SECRET. Anyone can forge a Flask session for any user_id (e.g. one that already bought FLAG.txt) - bypasses the race-condition vuln. Fix: generate `/etc/hackshield/service5.env` with `HACKMART_SECRET` like 08_service.sh:150-158 and add `EnvironmentFile=` to the unit.
- [ ] **Service 6 LFI reads the flag file directly.** service6/app.py `/api/files` resolves `PUBLIC_DIR / path` with no containment, running as user6 who owns `/opt/flags/flag6` (06_service.sh:84). `?path=/opt/flags/flag6` returns the flag in one request, skipping the .env/admin-key chain. Acceptable if intended; otherwise make the flag readable only by a different user and serve it via the admin portal.
- [ ] **Service 4 SSRF reaches every local service.** service4/app.py:24-34 follows redirects to any host, including 127.0.0.1:27017-adjacent HTTP apps and other teams' boxes on the game network (pivot/reflection attacks against third parties). Fine for the challenge, but restrict egress of user4 with `IPAddressDeny=any` + `IPAddressAllow=localhost` in the unit if cross-team abuse is a concern.
- [ ] **Service 3 SSTI = RCE with no resource limits.** service3/application/util.py:`generate_render` passes user text into `Template(...)`. Intended, but any team can fork-bomb / fill disk / burn CPU and take the whole VM (all services) down. Fix: add to every unit `TasksMax=64`, `MemoryMax=256M`, `CPUQuota=50%`, `LimitNOFILE=1024`; consider `ReadWritePaths=` nothing for user3 and `PrivateDevices=true`.
- [ ] **MySQL bound to 0.0.0.0 with passwordless `svc_reader`.** 01_service.sh:105-117 and the check at 01_service.sh:198. Confirm svc_reader has only SELECT on `employees` (sql/service1_seed.sql); any extra grant (FILE, DROP, SUPER) lets teams wipe the DB or read files. Also set `max_connections`/`max_user_connections` so connection floods do not kill service 1.
- [ ] **Players can edit and restart, but flags are file-based.** README "Flags and deployment scope" admits a team that modifies its own service can print its own flag; with HMAC flags that is harmless (they cannot submit their own). However `hs-service-editors` (player) gets write on all deployed code (01_service.sh:181-185) - make sure the flag daemon/boot agent live outside `/opt/hackshield/services` and are root-owned.

## 🟡 Medium / Low

- [ ] **Committed bytecode junk:** service4/__pycache__/app.cpython-313.pyc, app.cpython-314.pyc, internal_api.cpython-314.pyc, service5/__pycache__/app.cpython-314.pyc. Fix: `git rm -r --cached service4/__pycache__ service5/__pycache__` and add `__pycache__/` + `*.pyc` to .gitignore.
- [ ] **.gitignore ignores `*.md`** (.gitignore:2) - REVIEW.md / VM Setup.md only tracked because force-added. Narrow the pattern if docs should be versioned.
- [ ] **Committed demo secrets** service6/challenge_fs/.env:3 and service8/challenge_fs/.env:3. Both are overridden at deploy (06_service.sh:71-76, 08_service.sh:150), good; but service8/app.py:27-29 still falls back to the committed key if `/etc/hackshield/service8.env` is missing - fail closed instead.
- [ ] **Port collisions in the 5000-5050 range.** Services 8/9 hardcode 5001/5002 (systemd units), which may collide with a mapped port for another service. Moot once ports come from `port_mapping`.
- [ ] **setup.sh requires internet** (apt, PyPI, MongoDB repo). If the event network is offline, build the qcow2 in advance and do not re-run setup at the venue.
- [ ] **HS-2026/VM Setup.md is a 7-line stub** with no steps; README does not mention the game server, fw_cfg, or the restart procedure. Document: boot -> agent registers -> mapping -> units start -> flagd rotates.
- [ ] **Service 3 helper `font2/3` map space to `''`/`' '`** etc. - cosmetic; SSTI path is font4 (pass-through) so payloads with `${...}` work. Verified intended vuln is reachable.
- [ ] **ProtectSystem=strict without ReadWritePaths** on service2 is OK only because it opens SQLite read-only (service2/app.py:16); keep that in mind if anyone adds writes.
