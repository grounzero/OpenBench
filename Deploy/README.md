# Cadence's OpenBench deployment

This branch is upstream OpenBench at `2b8949d` (client version 49) plus the
configuration for a single private engine, Cadence, and the service files to
run it. Nothing under `Client/` or `OpenBench/` is modified, so the worker
code a machine downloads from this branch is byte-for-byte upstream's.

What differs from upstream, by file:

- `Config/config.json` — one engine (`Cadence`), four books, `require_login_to_view`
  and `require_manual_registration` on, cross-approval off (one developer), and
  the client repo pointed at this fork and branch so workers fetch a pinned client.
- `Engines/Cadence.json` — private engine, source `grounzero/cadence`, built
  with `cargo` via the repo's root Makefile shim, on Linux and Darwin. Presets
  follow the engine's CLAUDE.md §5.1: STC 8+0.08 `[0, 5]`, LTC 40+0.4 `[0, 3]`,
  non-regression `[-3, 1]`, α = β = 0.05. `nps` is 28,000,000: the M5 Max's
  bench speed measured as **6** concurrent copies, which is the concurrency
  every SPRT runs at, and the only measurement of the four taken that is
  stable (the two benches of a workload agree to 1.6%, against 19% at twelve
  copies). Any other machine is scaled to it.
- `OpenSite/settings.py` — `DEBUG = False`, secret key read from a file outside
  the checkout, `ALLOWED_HOSTS` for the LAN address, `STATIC_ROOT` for nginx.

## Server (Debian 13 container, 10.0.0.55)

```
useradd --system --create-home --home-dir /opt/openbench --shell /usr/sbin/nologin openbench
git clone -b cadence https://github.com/grounzero/OpenBench /opt/openbench/OpenBench
python3 -m venv /opt/openbench/venv
/opt/openbench/venv/bin/pip install -r /opt/openbench/OpenBench/requirements.txt gunicorn
python3 -c 'import secrets; print(secrets.token_urlsafe(48))' > /opt/openbench/secret_key
install -m 600 -o openbench -g openbench <pat-file> /opt/openbench/OpenBench/Config/credentials.cadence
chown -R openbench:openbench /opt/openbench; chmod 600 /opt/openbench/secret_key
sudo -u openbench /opt/openbench/venv/bin/python manage.py migrate
sudo -u openbench /opt/openbench/venv/bin/python manage.py collectstatic --noinput
# Two accounts, both needing a Profile row -- a superuser without one renders
# "This is not a real OpenBench User" and cannot create tests:
#   openbench : human login,  Profile(enabled=True,  approver=True)
#   mg        : worker only,  Profile(enabled=True,  approver=False)
# manage.py shell -> User.objects.create_user(...); Profile.objects.create(...)
cp Deploy/openbench.service /etc/systemd/system/ && systemctl enable --now openbench
cp Deploy/nginx-openbench.conf /etc/nginx/sites-available/openbench && ln -s ../sites-available/openbench /etc/nginx/sites-enabled/ && rm /etc/nginx/sites-enabled/default && nginx -t && systemctl reload nginx
```

`credentials.cadence` is the fine-grained GitHub PAT (Contents: read, one repo),
first line only, mode 600, owned by `openbench`. It is gitignored.

## Worker (macOS)

```
git clone -b cadence https://github.com/grounzero/OpenBench ~/git/OpenBench
python3 -m venv ~/git/OpenBench/venv && ~/git/OpenBench/venv/bin/pip install -r ~/git/OpenBench/Client/requirements.txt
install -m 600 <pat-file> ~/git/OpenBench/Client/credentials.cadence
# ~/.config/openbench/worker.env (mode 600): OPENBENCH_USERNAME= OPENBENCH_PASSWORD= OPENBENCH_SERVER=http://10.0.0.55/
cp Deploy/com.cadence.openbench-worker.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.cadence.openbench-worker.plist
```

The worker runs **6** concurrent games, not more; `worker-macos.sh` says why,
and the measurement behind it is in `docs/testing-infrastructure.md` in the
Cadence repo.

The worker needs `make`, `clang++` (Xcode CLT) and `cargo` on PATH; the plist
and the script both seed `~/.cargo/bin`. Logs go to `~/Library/Logs/openbench-worker.log`.
