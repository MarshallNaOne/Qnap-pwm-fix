# Release artifacts

`QNAP-PWM_1.0.0.qpkg` is an unsigned QPKG built from `../qpkg` with official
QDK 2.3.11. Verify its checksums before manual installation through App Center.

The package contains only a POSIX shell service script; there is no compiled
CPU-specific executable payload.

This repository artifact was rebuilt in an Ubuntu 22.04 container and its
control archive and payload were extracted and compared byte-for-byte with the
committed sources. The earlier 1.0.0 package from the investigation was
successfully installed on the NAS; this reproducible rebuild includes the same
mechanism plus stricter profile/mapping checks, but has not yet been installed
on the NAS in the current session.
