#!/bin/sh
set -eu

cd "$(dirname "$0")"
chmod 755 shared/QNAP-PWM.sh
qbuild --strict --verbose
