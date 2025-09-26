#!/bin/sh
# Run edge + origin synthetics N times and compute median latency.
# Usage: N=3 DOMAIN=example.com ./scripts/slo-gate.sh
set -eu

N=${N:-3}
DOMAIN=${DOMAIN:-}
if [ -z "$DOMAIN" ]; then
	echo "DOMAIN environment variable required" >&2
	exit 2
fi

# Thresholds in ms (can be overridden)
EDGE_THRESH_MS=${EDGE_THRESH_MS:-1500}
ORIGIN_THRESH_MS=${ORIGIN_THRESH_MS:-1500}

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t slo)
edge_times="$tmpdir/edge.times"
origin_times="$tmpdir/origin.times"
fail_count=0

i=0
while [ "$i" -lt "$N" ]; do
	i=$((i+1))
	printf "Run %d/%d: edge... " "$i" "$N"
	if ./scripts/synthetic-edge.sh >/tmp/synthetic_edge_out 2>&1; then
		# parse ms from output
		grep -Eo '[0-9]+ms' /tmp/synthetic_edge_out | grep -Eo '[0-9]+' >>"$edge_times" || true
		echo "OK"
	else
		echo "FAIL (edge)"
		cat /tmp/synthetic_edge_out >&2
		fail_count=$((fail_count+1))
	fi

	printf "Run %d/%d: origin... " "$i" "$N"
	if ./scripts/synthetic-origin.sh >/tmp/synthetic_origin_out 2>&1; then
		grep -Eo '[0-9]+ms' /tmp/synthetic_origin_out | grep -Eo '[0-9]+' >>"$origin_times" || true
		echo "OK"
	else
		echo "FAIL (origin)"
		cat /tmp/synthetic_origin_out >&2
		fail_count=$((fail_count+1))
	fi
done

median() {
	file="$1"
	if [ ! -s "$file" ]; then
		echo "NA"
		return
	fi
	# compute median
	count=$(wc -l <"$file" | tr -d ' ')
	sort -n "$file" >"$file.sorted"
	if [ "$count" -eq 0 ]; then
		echo "NA"
		return
	fi
	mid=$(( (count + 1) / 2 ))
	if [ $((count % 2)) -eq 1 ]; then
		sed -n "${mid}p" "$file.sorted"
	else
		a=$(sed -n "${mid}p" "$file.sorted")
		b=$(sed -n "$((mid+1))p" "$file.sorted")
		printf "%d\n" $(( (a + b) / 2 ))
	fi
}

EDGE_MED=$(median "$edge_times")
ORIGIN_MED=$(median "$origin_times")

echo "Median edge latency: $EDGE_MED ms"
echo "Median origin latency: $ORIGIN_MED ms"
echo "Failures during runs: $fail_count"

# Decide pass/fail: any failures or median above thresholds => non-zero
if [ "$fail_count" -gt 0 ]; then
	echo "SLO GATE: FAIL (synthetic failures)"
	exit 1
fi

if [ "$EDGE_MED" != "NA" ] && [ "$EDGE_MED" -gt "$EDGE_THRESH_MS" ]; then
	echo "SLO GATE: FAIL (edge median ${EDGE_MED}ms > ${EDGE_THRESH_MS}ms)"
	exit 1
fi

if [ "$ORIGIN_MED" != "NA" ] && [ "$ORIGIN_MED" -gt "$ORIGIN_THRESH_MS" ]; then
	echo "SLO GATE: FAIL (origin median ${ORIGIN_MED}ms > ${ORIGIN_THRESH_MS}ms)"
	exit 1
fi

echo "SLO GATE: PASS"
exit 0
