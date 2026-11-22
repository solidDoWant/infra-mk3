#!/usr/bin/env bash
# Runs every unit test of ci-tools and shellchecks its scripts. Runs inside
# the ci-tools image (make test), whose Python is the Nix one the stage
# environment tests need.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
failed=()
for t in tests/*_test.sh; do
	if bash "$t" >/tmp/test.log 2>&1; then echo "ok   $t"; else echo "FAIL $t"; cat /tmp/test.log; failed+=("$t"); fi
done
for t in tests/*_test.py; do
	if python3 "$t" >/tmp/test.log 2>&1; then echo "ok   $t"; else echo "FAIL $t"; cat /tmp/test.log; failed+=("$t"); fi
done
mapfile -t scripts < <(grep -l -s -E '^#!/(usr/bin/env (ba)?sh|bin/(ba)?sh)' bin/* lib/* tests/*.sh)
if shellcheck -x "${scripts[@]}"; then echo "ok   shellcheck"; else echo "FAIL shellcheck"; failed+=(shellcheck); fi
for f in bin/* lib/*.py; do
	if [ -f "$f" ] && head -n1 "$f" | grep -q python; then
		python3 -m py_compile "$f" 2>/dev/null || { echo "FAIL compile $f"; failed+=("$f"); }
	fi
done
if ((${#failed[@]})); then
	echo "failed: ${failed[*]}" >&2
	exit 1
fi
echo "all ci-tools tests passed"
