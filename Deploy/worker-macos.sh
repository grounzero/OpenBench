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
# -T 6 on an 18-core M5 Max (6 Super + 12 Performance, no efficiency tier).
# Not headroom for the OS -- fairness. Twelve was tried first and measured
# wrong: a null test of the engine against a byte-identical copy of itself
# came back with lopsided outer pentanomial buckets (86 versus 62 across
# 1,035 pairs, 14% apart, and the gap grew with sample size), which is the
# shape unequal cores produce and not a property of chess. At six the same
# test gives 3 versus 2, symmetric. The mechanism is visible in the bench
# too: twelve concurrent copies of a deterministic benchmark disagree with
# each other by 19% and sustain 9.3 Mnps after a long match, six disagree by
# 1.6% and sustain 24.8. macOS offers no affinity control, so concurrency is
# the only lever. It costs half the throughput -- 959 games/hour against
# 1,830 measured -- and that is the price of a fair pairing.
# See docs/testing-infrastructure.md in the Cadence repo.

set -eu

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

. "$HOME/.config/openbench/worker.env"
export OPENBENCH_USERNAME OPENBENCH_PASSWORD OPENBENCH_SERVER

# -u: launchd's stdout is a file, so Python block-buffers it and the log
# lags the worker by kilobytes. The log is the only view of a service.
cd "$(dirname "$0")/../Client"
exec ../venv/bin/python3 -u client.py \
    -T "${OPENBENCH_THREADS:-6}" \
    -N 1 \
    -I "${OPENBENCH_IDENTITY:-m5max}"
