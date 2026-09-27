#!/bin/sh

APP="QNAP-PWM"
MODEL_CONF="/etc/model.conf"
EXPECTED_CONF="/etc/model_Q04Z0_Q0500_10_10.conf"
LOG="/mnt/HDA_ROOT/.config/qnap-pwm.log"
HAL_EVENT="/sbin/hal_event"

log()
{
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$APP] $*" >> "$LOG"
}

apply_pwm()
{
    log "Starting PWM patch"

    count=0
    while [ ! -e "$MODEL_CONF" ]; do
        count=$((count + 1))
        if [ "$count" -ge 60 ]; then
            log "ERROR: $MODEL_CONF did not appear after 60 seconds"
            return 1
        fi
        sleep 1
    done

    real_conf="$(readlink -f "$MODEL_CONF" 2>/dev/null || true)"
    if [ -z "$real_conf" ] || [ ! -f "$real_conf" ]; then
        log "ERROR: unable to resolve $MODEL_CONF"
        return 1
    fi
    if [ "$real_conf" != "$EXPECTED_CONF" ]; then
        log "ERROR: unexpected model config '$real_conf'; expected '$EXPECTED_CONF'"
        return 1
    fi

    log "Model config: $real_conf"

    if ! grep -q '^\[System FAN\]$' "$real_conf"; then
        log "ERROR: [System FAN] section not found"
        return 1
    fi
    if ! sed -n '/^\[System FAN\]$/,/^\[/p' "$real_conf" | grep -q '^FAN_UNIT = MCU$'; then
        log "ERROR: FAN_UNIT is not MCU; refusing to modify configuration"
        return 1
    fi
    if ! sed -n '/^\[System FAN\]$/,/^\[/p' "$real_conf" | grep -q '^FAN_1 = I1:C0$'; then
        log "ERROR: unexpected FAN_1 mapping; refusing to modify configuration"
        return 1
    fi

    current_pwm="$(sed -n '/^\[System FAN\]$/,/^\[/ {
        s/^MAX_PWM = \([0-9][0-9]*\)$/\1/p
    }' "$real_conf" | head -n 1)"
    log "Current MAX_PWM=$current_pwm"

    case "$current_pwm" in
        178)
            sed -i '/^\[System FAN\]$/,/^\[/ s/^MAX_PWM = 178$/MAX_PWM = 255/' "$real_conf"
            if ! sed -n '/^\[System FAN\]$/,/^\[/p' "$real_conf" | grep -q '^MAX_PWM = 255$'; then
                log "ERROR: failed to change MAX_PWM to 255"
                return 1
            fi
            log "MAX_PWM changed: 178 -> 255"
            ;;
        255)
            log "MAX_PWM already set to 255"
            ;;
        *)
            log "ERROR: unexpected MAX_PWM='$current_pwm'; refusing to modify configuration"
            return 1
            ;;
    esac

    if [ ! -x "$HAL_EVENT" ]; then
        log "ERROR: $HAL_EVENT is missing or not executable"
        return 1
    fi

    log "Triggering HAL fan configuration reload"
    "$HAL_EVENT" --se_set_fan_force_speed fan_level=7 || {
        log "ERROR: failed to set temporary HAL fan level"
        return 1
    }
    sleep 3
    "$HAL_EVENT" --se_clear_fan_force_speed || {
        log "ERROR: failed to clear temporary HAL fan level"
        return 1
    }

    log "PWM patch successfully applied"
    return 0
}

case "${1:-}" in
    start|restart)
        apply_pwm
        ;;
    stop)
        # QTS regenerates the model profile on boot. Runtime stop is a no-op.
        exit 0
        ;;
    status)
        if grep -q '^MAX_PWM = 255$' "$MODEL_CONF" 2>/dev/null; then
            echo "$APP: applied"
            exit 0
        fi
        echo "$APP: not applied"
        exit 1
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}" >&2
        exit 2
        ;;
esac
