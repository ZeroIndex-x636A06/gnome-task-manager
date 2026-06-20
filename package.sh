#!/usr/bin/env bash
# Build .deb and .rpm packages from the local source tree.
#
# Run from the repository root (does NOT require root):
#   ./package.sh
#
# Required tools:
#   .deb  — dpkg-deb   (Arch: sudo pacman -S dpkg)
#                      (Fedora: sudo dnf install dpkg)
#                      (Debian/Ubuntu: already present)
#   .rpm  — rpmbuild   (Arch: sudo pacman -S rpm-tools)
#                      (Fedora/RHEL: sudo dnf install rpm-build)
#                      (Debian/Ubuntu: sudo apt-get install rpm)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.2.0"
RELEASE="1"
DIST_DIR="$ROOT_DIR/dist"

# Detect architecture
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64)  DEB_ARCH="amd64";  RPM_ARCH="x86_64"  ;;
  aarch64) DEB_ARCH="arm64";  RPM_ARCH="aarch64"  ;;
  i686)    DEB_ARCH="i386";   RPM_ARCH="i686"      ;;
  *)       DEB_ARCH="$ARCH_RAW"; RPM_ARCH="$ARCH_RAW" ;;
esac

DAEMON_BIN="$ROOT_DIR/target/release/task-scheduler-daemon"
GUI_BIN="$ROOT_DIR/target/release/task-scheduler"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "==> Building workspace (release)"
AUGMENTED_PATH="${HOME}/.cargo/bin:${PATH}"
env PATH="$AUGMENTED_PATH" cargo build --release --workspace

if [[ ! -x "$DAEMON_BIN" ]]; then
  echo "ERROR: daemon binary not found at $DAEMON_BIN" >&2; exit 1
fi
if [[ ! -x "$GUI_BIN" ]]; then
  echo "ERROR: GUI binary not found at $GUI_BIN" >&2; exit 1
fi

mkdir -p "$DIST_DIR"

# ── .deb ─────────────────────────────────────────────────────────────────────
build_deb() {
  if ! command -v dpkg-deb &>/dev/null; then
    echo
    echo "warn: dpkg-deb not found — skipping .deb"
    echo "      Arch:          sudo pacman -S dpkg"
    echo "      Fedora/RHEL:   sudo dnf install dpkg"
    echo "      Debian/Ubuntu: already present"
    return 0
  fi

  local STAGING="$DIST_DIR/.deb-staging"
  rm -rf "$STAGING"

  # ── DEBIAN metadata ──────────────────────────────────────────────────────
  mkdir -p "$STAGING/DEBIAN"

  cat > "$STAGING/DEBIAN/control" <<EOF
Package: task-scheduler
Version: ${VERSION}-${RELEASE}
Architecture: ${DEB_ARCH}
Maintainer: Caleb Jarrell <calebjarrell2006@gmail.com>
Depends: libgtk-4-1, libadwaita-1-0, dbus, policykit-1, systemd
Recommends: cron
Section: admin
Priority: optional
Homepage: https://github.com/ZeroIndex-x636A06/gnome-task-scheduler
Description: GTK4/libadwaita scheduler for system and user tasks
 Task Scheduler is a desktop frontend for scheduling cron and systemd
 timer tasks. It ships a privileged DBus daemon that performs the
 system-scope work, gated behind polkit, and a GTK4/libadwaita GUI.
EOF

  # Maintainer scripts (must be executable)
  install -Dm755 "$ROOT_DIR/packaging/deb/debian/task-scheduler.postinst" \
    "$STAGING/DEBIAN/postinst"
  install -Dm755 "$ROOT_DIR/packaging/deb/debian/task-scheduler.prerm" \
    "$STAGING/DEBIAN/prerm"
  install -Dm755 "$ROOT_DIR/packaging/deb/debian/task-scheduler.postrm" \
    "$STAGING/DEBIAN/postrm"

  # ── Payload ──────────────────────────────────────────────────────────────
  install -Dm755 "$GUI_BIN"    "$STAGING/usr/bin/task-scheduler"
  install -Dm755 "$DAEMON_BIN" "$STAGING/usr/bin/task-scheduler-daemon"
  strip --strip-unneeded "$STAGING/usr/bin/task-scheduler" \
                         "$STAGING/usr/bin/task-scheduler-daemon" 2>/dev/null || true

  install -Dm644 "$ROOT_DIR/packaging/org.linux.TaskScheduler.conf" \
    "$STAGING/usr/share/dbus-1/system.d/org.linux.TaskScheduler.conf"

  install -Dm644 "$ROOT_DIR/packaging/org.linux.TaskScheduler.policy" \
    "$STAGING/usr/share/polkit-1/actions/org.linux.TaskScheduler.policy"

  mkdir -p "$STAGING/usr/lib/systemd/system"
  sed 's|/usr/local/bin/|/usr/bin/|g' \
    "$ROOT_DIR/packaging/task-scheduler-daemon.service" \
    > "$STAGING/usr/lib/systemd/system/task-scheduler-daemon.service"
  chmod 644 "$STAGING/usr/lib/systemd/system/task-scheduler-daemon.service"

  install -Dm644 "$ROOT_DIR/packaging/org.linux.TaskScheduler.desktop" \
    "$STAGING/usr/share/applications/org.linux.TaskScheduler.desktop"
  install -Dm644 "$ROOT_DIR/packaging/task-scheduler.png" \
    "$STAGING/usr/share/icons/hicolor/512x512/apps/task-scheduler.png"

  install -d -m 0755 "$STAGING/var/lib/task-scheduler/snapshots"

  local DEB_FILE="$DIST_DIR/task-scheduler_${VERSION}-${RELEASE}_${DEB_ARCH}.deb"
  dpkg-deb --build --root-owner-group "$STAGING" "$DEB_FILE"
  rm -rf "$STAGING"
  echo "==> .deb: $DEB_FILE"
}

# ── .rpm ─────────────────────────────────────────────────────────────────────
build_rpm() {
  if ! command -v rpmbuild &>/dev/null; then
    echo
    echo "warn: rpmbuild not found — skipping .rpm"
    echo "      Arch:          sudo pacman -S rpm-tools"
    echo "      Fedora/RHEL:   sudo dnf install rpm-build"
    echo "      Debian/Ubuntu: sudo apt-get install rpm"
    return 0
  fi

  local RPMROOT="$DIST_DIR/.rpmbuild"
  mkdir -p "$RPMROOT"/{SPECS,SOURCES,BUILD,RPMS,SRPMS,BUILDROOT}

  # ── Spec for pre-built binary RPM ─────────────────────────────────────────
  cat > "$RPMROOT/SPECS/task-scheduler.spec" <<SPEC
%global debug_package %{nil}

Name:           task-scheduler
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        GTK4/libadwaita scheduler for system and user tasks
License:        MIT
URL:            https://github.com/ZeroIndex-x636A06/gnome-task-scheduler
BuildArch:      ${RPM_ARCH}

Requires:       gtk4
Requires:       libadwaita
Requires:       dbus
Requires:       polkit
Requires:       systemd
Recommends:     cronie

%description
Task Scheduler is a desktop frontend for scheduling cron and systemd
timer tasks. It ships a privileged DBus daemon that performs the
system-scope work, gated behind polkit, and a GTK4/libadwaita GUI.

%prep
# Binaries are pre-built; nothing to prepare.

%build
# Binaries are pre-built; nothing to build.

%install
install -Dm755 ${ROOT_DIR}/target/release/task-scheduler \\
  %{buildroot}%{_bindir}/task-scheduler
install -Dm755 ${ROOT_DIR}/target/release/task-scheduler-daemon \\
  %{buildroot}%{_bindir}/task-scheduler-daemon
strip --strip-unneeded \\
  %{buildroot}%{_bindir}/task-scheduler \\
  %{buildroot}%{_bindir}/task-scheduler-daemon 2>/dev/null || true

install -Dm644 ${ROOT_DIR}/packaging/org.linux.TaskScheduler.conf \\
  %{buildroot}%{_datadir}/dbus-1/system.d/org.linux.TaskScheduler.conf

install -Dm644 ${ROOT_DIR}/packaging/org.linux.TaskScheduler.policy \\
  %{buildroot}%{_datadir}/polkit-1/actions/org.linux.TaskScheduler.policy

mkdir -p %{buildroot}/usr/lib/systemd/system
sed 's|/usr/local/bin/|%{_bindir}/|g' \\
  ${ROOT_DIR}/packaging/task-scheduler-daemon.service \\
  > %{buildroot}/usr/lib/systemd/system/task-scheduler-daemon.service
chmod 644 %{buildroot}/usr/lib/systemd/system/task-scheduler-daemon.service

install -Dm644 ${ROOT_DIR}/packaging/org.linux.TaskScheduler.desktop \\
  %{buildroot}%{_datadir}/applications/org.linux.TaskScheduler.desktop
install -Dm644 ${ROOT_DIR}/packaging/task-scheduler.png \\
  %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/task-scheduler.png

install -d -m 0755 %{buildroot}/var/lib/task-scheduler/snapshots

%post
systemctl daemon-reload || true
systemctl reload dbus 2>/dev/null || systemctl restart dbus || true
systemctl enable --now task-scheduler-daemon.service || true
update-desktop-database %{_datadir}/applications 2>/dev/null || true
gtk-update-icon-cache -f %{_datadir}/icons/hicolor 2>/dev/null || true

%preun
if [ \$1 -eq 0 ]; then
  systemctl disable --now task-scheduler-daemon.service 2>/dev/null || true
fi

%postun
if [ \$1 -eq 0 ]; then
  systemctl daemon-reload || true
  systemctl reload dbus 2>/dev/null || true
  update-desktop-database %{_datadir}/applications 2>/dev/null || true
  gtk-update-icon-cache -f %{_datadir}/icons/hicolor 2>/dev/null || true
fi

%files
%{_bindir}/task-scheduler
%{_bindir}/task-scheduler-daemon
%{_datadir}/dbus-1/system.d/org.linux.TaskScheduler.conf
%{_datadir}/polkit-1/actions/org.linux.TaskScheduler.policy
/usr/lib/systemd/system/task-scheduler-daemon.service
%{_datadir}/applications/org.linux.TaskScheduler.desktop
%{_datadir}/icons/hicolor/512x512/apps/task-scheduler.png
%dir /var/lib/task-scheduler
%dir /var/lib/task-scheduler/snapshots

%changelog
* Thu Jun 19 2026 Caleb Jarrell <calebjarrell2006@gmail.com> - ${VERSION}-${RELEASE}
- Initial RPM packaging.
SPEC

  rpmbuild -bb \
    --define "_topdir ${RPMROOT}" \
    "$RPMROOT/SPECS/task-scheduler.spec"

  local RPM_FILE
  RPM_FILE="$(find "$RPMROOT/RPMS" -name "*.rpm" | head -1)"
  if [[ -n "$RPM_FILE" ]]; then
    cp "$RPM_FILE" "$DIST_DIR/"
    echo "==> .rpm: $DIST_DIR/$(basename "$RPM_FILE")"
  fi

  rm -rf "$RPMROOT"
}

# ── Run ───────────────────────────────────────────────────────────────────────
build_deb
build_rpm

echo
echo "Output directory: $DIST_DIR/"
ls -lh "$DIST_DIR/"
