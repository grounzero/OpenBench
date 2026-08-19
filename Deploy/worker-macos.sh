#!/bin/sh
# OpenBench worker on macOS, run by launchd (Deploy/com.cadence.openbench-worker.plist).
#
# Credentials come from ~/.config/openbench/worker.env (mode 600), which sets
#   OPENBENCH_USERNAME, OPENBENCH_PASSWORD, OPENBENCH_SERVER
# and may set OPENBENCH_THREADS to override the -T below.
#
# PATH is set explicitly, and ~/.cargo/bin first, because launchd starts
# agents with a bare PATH and the OpenBench server does not check that a
# worker can compile a *private* engine before assigning it the job: a
# worker without cargo does not decline the work, it crashes at build time.
#
# -T 12 on an 18-core M5 Max (6 Super + 12 Performance, no efficiency tier)
# is deliberate headroom. Each game occupies one core at a time, so this is
# 12 concurrent games with 6 cores spare for the OS, fastchess, and whatever
# else the machine is doing, so an engine is never descheduled mid-move.
# There is no core-affinity control on macOS; the bench nps spread across
# 12 concurrent copies was measured at 22.1-22.8 Mnps (3%), across 18 at
# 20.4-21.6 (6%), so the Super/Performance asymmetry is noise at this
# concurrency, and the null test is what bounds it.

set -eu

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

. "$HOME/.config/openbench/worker.env"
export OPENBENCH_USERNAME OPENBENCH_PASSWORD OPENBENCH_SERVER

# -u: launchd's stdout is a file, so Python block-buffers it and the log
# lags the worker by kilobytes. The log is the only view of a service.
cd "$(dirname "$0")/../Client"
exec ../venv/bin/python3 -u client.py \
    -T "${OPENBENCH_THREADS:-12}" \
    -N 1 \
    -I "${OPENBENCH_IDENTITY:-m5max}"
