#!/bin/sh
# Tests scripts/ci/cpuset-first.sh: the first N CPUs of a cpuset list, and how
# many that is when the list has fewer.
set -eu
cd "$(dirname "$0")"
failed=0
check() {
	list="$1" want_count="$2" want="$3"
	got=$(./cpuset-first.sh "$list" "$want_count")
	if [ "$got" != "$want" ]; then
		echo "cpuset-first.sh '$list' $want_count printed '$got', want '$want'" >&2
		failed=1
	fi
}
check 0-31 8 '0,1,2,3,4,5,6,7 8'
check 0-7 8 '0,1,2,3,4,5,6,7 8'
check 0-6 8 '0,1,2,3,4,5,6 7'
check 0 8 '0 1'
check 0-1,4-9 5 '0,1,4,5,6 5'
check 2,5,7-30 3 '2,5,7 3'
check 0-31 1 '0 1'
# A fixed pair of /proc/stat samples: CPUs 0-3 busy by 100 ticks, 4-7 by 0,
# 8-11 by 50, in a cpuset of 0-11 with a budget of 4.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do echo "cpu$i 10 0 10 100 5 0 0 0 0 0"; done >"$tmp/a"
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
	case $i in
	[0-3]) echo "cpu$i 110 0 10 100 5 0 0 0 0 0" ;;
	[4-7]) echo "cpu$i 10 0 10 200 5 0 0 0 0 0" ;;
	*) echo "cpu$i 60 0 10 150 5 0 0 0 0 0" ;;
	esac
done >"$tmp/b"
got=$(./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/b" | head -n 1)
[ "$got" = '4,5,6,7 4' ] || { echo "sampled pick printed '$got', want '4,5,6,7 4'" >&2; failed=1; }
got=$(./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/b" | tail -n 1)
want='0=100,1=100,2=100,3=100,4=0,5=0,6=0,7=0,8=50,9=50,10=50,11=50'
[ "$got" = "$want" ] || { echo "busy line printed '$got', want '$want'" >&2; failed=1; }
got=$(./cpuset-first.sh 8-11 6 "$tmp/a" "$tmp/b" | head -n 1)
[ "$got" = '8,9,10,11 4' ] || { echo "small cpuset with samples printed '$got'" >&2; failed=1; }
got=$(./cpuset-first.sh 2,3,8-11 2 "$tmp/a" "$tmp/b" | head -n 1)
[ "$got" = '8,9 2' ] || { echo "split cpuset with samples printed '$got'" >&2; failed=1; }
# No load anywhere: the seed picks the block, the same seed always the same one,
# and different seeds spread over the aligned blocks.
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do echo "cpu$i 10 0 10 100 5 0 0 0 0 0"; done >"$tmp/idle"
first=$(./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/idle" run-one | head -n 1)
again=$(./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/idle" run-one | head -n 1)
[ "$first" = "$again" ] || { echo "same seed gave '$first' then '$again'" >&2; failed=1; }
blocks=$(for n in 1 2 3 4 5 6 7 8 9 10 11 12; do ./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/idle" "pod-$n" | head -n 1; done | sort -u)
count=$(echo "$blocks" | wc -l)
[ "$count" = 3 ] || { echo "12 seeds gave $count blocks, want 3: $blocks" >&2; failed=1; }
echo "$blocks" | grep -qvx '0,1,2,3 4\|4,5,6,7 4\|8,9,10,11 4' && { echo "unaligned block in: $blocks" >&2; failed=1; }
# A seed never overrides a sample that shows load.
got=$(./cpuset-first.sh 0-11 4 "$tmp/a" "$tmp/b" run-one | head -n 1)
[ "$got" = '4,5,6,7 4' ] || { echo "seeded pick under load printed '$got'" >&2; failed=1; }
if ./cpuset-first.sh '' 8 >/dev/null 2>&1; then
	echo "cpuset-first.sh accepted an empty cpuset list" >&2
	failed=1
fi
if ./cpuset-first.sh 'x-y' 8 >/dev/null 2>&1; then
	echo "cpuset-first.sh accepted a malformed cpuset list" >&2
	failed=1
fi
[ "$failed" = 0 ] || exit 1
echo "cpuset-first_test.sh: ok"
