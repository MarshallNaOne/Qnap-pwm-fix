#!/bin/sh
# QNAP TS-230 fan-cap inspection/apply helper.  Default mode is read-only.
set -eu

MODEL_LINK=/etc/model.conf
EXPECTED_TARGET=/etc/model_Q04Z0_Q0500_10_10.conf
TARGET_PWM=255

usage() {
  echo "Usage: $0 [--apply-255 | --rollback]"
  echo "No option: inspect only. No direct PWM-register writes are ever made."
}

mode=inspect
case "${1:-}" in
  '') ;;
  --apply-255) mode=apply ;;
  --rollback) mode=rollback ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

[ -L "$MODEL_LINK" ] || { echo "ERROR: $MODEL_LINK is not a symlink" >&2; exit 1; }
resolved=$(readlink -f "$MODEL_LINK" 2>/dev/null || readlink "$MODEL_LINK")
[ "$resolved" = "$EXPECTED_TARGET" ] || {
  echo "ERROR: refusing unexpected model target: $resolved" >&2; exit 1;
}
[ -f "$resolved" ] || { echo "ERROR: missing model file: $resolved" >&2; exit 1; }

line=$(grep '^MAX_PWM = ' "$resolved" || true)
[ -n "$line" ] || { echo "ERROR: MAX_PWM line not found" >&2; exit 1; }
current=${line#MAX_PWM = }
case "$current" in
  ''|*[!0-9]*) echo "ERROR: non-numeric MAX_PWM: $current" >&2; exit 1 ;;
esac
[ "$current" -ge 0 ] && [ "$current" -le 255 ] || {
  echo "ERROR: MAX_PWM out of range: $current" >&2; exit 1;
}

echo "Model link: $MODEL_LINK -> $resolved"
echo "Current: $line"
grep -A5 '^\[System FAN\]' "$resolved" || true

case "$mode" in
  inspect) echo "Read-only inspection complete."; exit 0 ;;
  apply|rollback) ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "ERROR: rerun with sudo" >&2; exit 1; }
backup="$resolved.bak"
if [ "$mode" = apply ]; then
  [ "$current" = 178 ] || {
    echo "ERROR: apply only accepts expected original MAX_PWM=178 (found $current)" >&2; exit 1;
  }
  if [ ! -e "$backup" ]; then
    cp -p "$resolved" "$backup"
    echo "Created backup: $backup"
  else
    echo "Using existing backup without overwriting it: $backup"
  fi
  sed -i 's/^MAX_PWM = 178$/MAX_PWM = 255/' "$resolved"
  grep -qx 'MAX_PWM = 255' "$resolved" || { echo "ERROR: verification failed" >&2; exit 1; }
  echo "Applied MAX_PWM = $TARGET_PWM. Reapply 50% then 100% in QTS GUI."
else
  [ -f "$backup" ] || { echo "ERROR: rollback backup missing: $backup" >&2; exit 1; }
  cp -p "$backup" "$resolved"
  grep -qx 'MAX_PWM = 178' "$resolved" || { echo "ERROR: rollback verification failed" >&2; exit 1; }
  echo "Restored backup. Reapply 50% then 100% in QTS GUI."
fi
