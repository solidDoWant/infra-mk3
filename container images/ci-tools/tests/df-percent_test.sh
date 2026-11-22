#!/bin/sh
# Tests lib/df-percent.sh, and that it needs no tool beyond the shell:
# it runs with an empty PATH.
set -eu
cd "$(dirname "$0")/../lib"
sample='Filesystem     1024-blocks      Used Available Capacity Mounted on
/dev/sda1        100000000  42000000  58000000      42% /storage'
got=$(printf '%s\n' "$sample" | PATH=/nonexistent /bin/sh ./df-percent.sh)
[ "$got" = 42 ] || { echo "df-percent.sh printed '$got', want 42" >&2; exit 1; }
got=$(printf 'h\nx 1 2 3 100%% /\n' | PATH=/nonexistent /bin/sh ./df-percent.sh)
[ "$got" = 100 ] || { echo "df-percent.sh printed '$got', want 100" >&2; exit 1; }
echo "df-percent_test.sh: ok"
