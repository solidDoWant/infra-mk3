#!/usr/bin/env sh
# NVMe Identify Controller temperature thresholds (WCTEMP/CCTEMP) are not
# emitted in `smartctl --json` output (only in the human-readable `-x` form).
# This script parses the text output and writes the thresholds as
# node-exporter textfile-collector metrics. The file is swapped atomically on
# each iteration so the collector never reads a partial write.
set -eu

OUT=/textfile/smartctl_nvme_thresholds.prom

write_metrics() {
  echo "# HELP smartctl_nvme_warning_temp_celsius NVMe Warning Composite Temperature Threshold (WCTEMP) from Identify Controller"
  echo "# TYPE smartctl_nvme_warning_temp_celsius gauge"
  echo "# HELP smartctl_nvme_critical_temp_celsius NVMe Critical Composite Temperature Threshold (CCTEMP) from Identify Controller"
  echo "# TYPE smartctl_nvme_critical_temp_celsius gauge"

  # Match /dev/nvme<N> controller nodes only (single- and double-digit).
  # Namespace devices like /dev/nvme0n1 are skipped — thresholds are a
  # controller-level property.
  for dev in /dev/nvme[0-9] /dev/nvme[0-9][0-9]; do
    [ -e "$dev" ] || continue
    name=$(basename "$dev")
    # Cap each smartctl call at 30s so a misbehaving drive can't stall the
    # whole loop. Safe under `set -e` because exit code 124 (timeout fired)
    # is consumed by the pipe — awk's exit code becomes the pipeline's.
    timeout 30 smartctl -x "$dev" 2>/dev/null | awk -v d="$name" '
      /^Warning  Comp\. Temp\. Threshold:/ {
        printf "smartctl_nvme_warning_temp_celsius{device=\"%s\"} %s\n", d, $5
      }
      /^Critical Comp\. Temp\. Threshold:/ {
        printf "smartctl_nvme_critical_temp_celsius{device=\"%s\"} %s\n", d, $5
      }'
  done
}

while :; do
  TMP="${OUT}.tmp"
  write_metrics > "$TMP"
  mv "$TMP" "$OUT"
  sleep 300
done
