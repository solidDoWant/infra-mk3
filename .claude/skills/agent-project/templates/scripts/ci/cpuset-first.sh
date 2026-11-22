#!/bin/sh
# Picks COUNT CPUs of a Linux cpuset list (such as cpuset.cpus.effective,
# "0-3,8-11") for the --cpuset-cpus option of Docker. Prints the chosen list,
# then how many CPUs that list has (fewer than COUNT when the cpuset is
# smaller).
#
# With two samples of /proc/stat taken a moment apart, it picks the run of COUNT
# neighbouring CPUs of the cpuset that were busiest the least between the
# samples, so runs on one node don't pin to the same CPUs. It then prints a
# second line with the busy ticks of each CPU of the cpuset. Without samples it
# takes the first COUNT CPUs.
#
# When several places are equally idle (a sample cannot see other runs on the
# node, so with no load every place ties), SEED, such as the pod name, picks
# among them by its checksum, preferring blocks of COUNT aligned to the start of
# the cpuset. Runs with different seeds then spread over the blocks. Without a
# SEED the first tied place wins.
#
#   scripts/ci/cpuset-first.sh LIST COUNT [STAT_BEFORE STAT_AFTER [SEED]]
set -eu
list="${1:?usage: cpuset-first.sh LIST COUNT [STAT_BEFORE STAT_AFTER]}"
count="${2:?usage: cpuset-first.sh LIST COUNT [STAT_BEFORE STAT_AFTER]}"
before="${3:-/dev/null}"
after="${4:-/dev/null}"
seed="${5:-}"
hash=0
if [ -n "$seed" ]; then
	hash=$(printf '%s' "$seed" | cksum | cut -d' ' -f1)
fi
# The samples come first, so awk can tell them from the list by file number.
awk -v hash="$hash" -v list="$list" -v want="$count" '
	# Busy ticks per CPU: everything but idle and iowait (fields 5 and 6).
	/^cpu[0-9]+ / {
		cpu = substr($1, 4) + 0
		total = 0
		for (i = 2; i <= NF; i++) total += $i
		busy = total - $5 - $6
		if (FILENAME == ARGV[1]) first[cpu] = busy
		else { delta[cpu] = busy - first[cpu]; sampled = 1 }
	}
	END {
		n = split(list, parts, ",")
		m = 0
		for (i = 1; i <= n; i++) {
			if (parts[i] !~ /^[0-9]+(-[0-9]+)?$/) { bad = 1; break }
			split(parts[i], r, "-")
			last = (r[2] == "") ? r[1] : r[2]
			for (c = r[1] + 0; c <= last + 0; c++) cpus[++m] = c
		}
		if (bad || m == 0) { print "not a cpuset list: " list > "/dev/stderr"; exit 1 }
		take = (m < want + 0) ? m : want + 0
		sum = 0
		for (i = 1; i <= take; i++) sum += delta[cpus[i]] + 0
		# Window sums for every start; ties keep all their starts.
		wins = 0
		sums[1] = sum
		for (s = 2; s + take - 1 <= m; s++) {
			sum += delta[cpus[s + take - 1]] - delta[cpus[s - 1]]
			sums[s] = sum
		}
		wins = m - take + 1
		best = sums[1]
		for (s = 2; s <= wins; s++) if (sums[s] < best) best = sums[s]
		nt = 0; na = 0
		for (s = 1; s <= wins; s++) if (sums[s] == best) {
			tied[++nt] = s
			if ((s - 1) % take == 0) aligned[++na] = s
		}
		if (na > 0) start = aligned[(hash % na) + 1]
		else start = tied[(hash % nt) + 1]
		out = ""
		for (i = start; i < start + take; i++) out = (i == start) ? cpus[i] : out "," cpus[i]
		print out, take
		if (sampled) {
			info = ""
			for (i = 1; i <= m; i++) info = info (i > 1 ? "," : "") cpus[i] "=" (delta[cpus[i]] + 0)
			print info
		}
	}
' "$before" "$after"
