# Task Scheduler
A native, Windows-Task-Scheduler-style app for Linux. Built with Rust, GTK4, and libadwaita on the frontend, with a small zbus DBus daemon on the backend for system-wide tasks.

## Why use this?
Linux lacks a native GUI for scheduling recurring tasks. `cron` and systemd timers are powerful, but require editing config files by hand. Existing GUI tools are either outdated or tied to a specific desktop environment.

**Task Scheduler** solves this by:
1. Providing a polished GTK4/libadwaita GUI that feels at home on GNOME and other desktop environments.
2. Writing proper systemd `.service` and `.timer` units so your tasks survive reboots and integrate with `journalctl`.
3. Optionally running a privileged DBus daemon so tasks can be scheduled system-wide (as root) without giving the GUI elevated permissions.

## Compatibility
* **Distros:** Works on any Linux distribution (Arch, Fedora, Debian, Ubuntu, etc.).
* **Desktop Environments:**
  * **GNOME:** Native Adwaita look and feel.
  * **KDE Plasma:** Reads accent color from `~/.config/kdeglobals`.
  * **XFCE / Cinnamon / MATE:** Detects dark mode and adjusts chrome accordingly.
  * **Tiling WMs (Sway, Hyprland, i3):** Hides title-bar controls so your compositor's own borders take over.
* **Task Scope:**
  * **User tasks:** Stored in `~/.config/systemd/user/` — no root required, no daemon needed.
  * **System tasks:** Stored in `/etc/systemd/system/` via the privileged DBus daemon.

## Dependencies
* `rust` (stable toolchain, for building from source)
* `gtk4`
* `libadwaita`
* `dbus`
* `systemd`
* `polkit` *(optional, required for per-method authorization prompts)*

### System packages

**Debian / Ubuntu / Mint:**
```bash
sudo apt install build-essential pkg-config \
                 libgtk-4-dev libadwaita-1-dev libdbus-1-dev
```

**Arch / Manjaro / EndeavourOS:**
```bash
sudo pacman -S gtk4 libadwaita dbus polkit
```

**Fedora / RHEL:**
```bash
sudo dnf install gtk4-devel libadwaita-devel dbus-devel polkit
```

## Installation

### Manual
1. Change directory to home directory:
   ```bash
   cd ~
   ```
2. Clone the repository:
   ```bash
   git clone https://github.com/ZeroIndex-x636A06/gnome-task-manager.git task-scheduler
   ```
3. Change directory to the task-scheduler install folder:
   ```bash
   cd task-scheduler
   ```
4. Make the install script executable and run it:
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

The install script will:
* Build both the GUI and daemon in release mode.
* Install binaries to `/usr/local/bin/`.
* Install the DBus system policy to `/etc/dbus-1/system.d/`.
* Install the polkit policy to `/usr/share/polkit-1/actions/` (if polkit is present).
* Install and enable `task-scheduler-daemon.service` via systemd.
* Install the `.desktop` entry and app icon.

## Usage

### Launching the GUI
```bash
task-scheduler
```
Or find **Task Scheduler** in your application launcher.

### Creating a user-scope task (no root required)
Open the app, click **New Task**, fill in the name, command, and trigger (time, interval, or device attach), then click **Save**. The app writes a systemd `.timer` + `.service` pair to `~/.config/systemd/user/`.

### Creating a system-wide task (runs as root)
Same as above, but toggle **"Run as system (root)"** in the New Task dialog. The request is sent over DBus to the privileged daemon, which writes the units to `/etc/systemd/system/`.

### Viewing logs for a task
```bash
journalctl -u <task-name>.service -f
```

### Viewing daemon logs
```bash
journalctl -u task-scheduler-daemon -f
```

## Workspace layout

```text
core/        Shared Task / Trigger / TaskScheduler trait
gui/         GTK4 + libadwaita application (unprivileged)
daemon/      zbus system-bus daemon, runs as root
packaging/   DBus policy, polkit policy, systemd unit, .desktop entry
install.sh   Build + deploy
uninstall.sh Remove all installed files
```

## Development (no daemon)

To run the GUI during development without installing the daemon:
```bash
cargo run -p task-scheduler
```
User-scope tasks work fully in this mode. System-scope tasks require the daemon to be installed and running.

## Un-installation

### Manual
1. Change directory to home directory:
   ```bash
   cd ~
   ```
2. Change directory to the task-scheduler install folder:
   ```bash
   cd task-scheduler
   ```
   *IF YOU DELETED THE TASK-SCHEDULER DIRECTORY, RERUN THE CLONE COMMAND:*

   Clone the repository:
   ```bash
   git clone https://github.com/ZeroIndex-x636A06/gnome-task-manager.git task-scheduler
   cd task-scheduler
   ```
3. Make the un-install script executable and run it:
   ```bash
   chmod +x uninstall.sh
   sudo ./uninstall.sh
   ```

This removes the daemon binary, GUI binary, DBus policy, polkit policy, systemd unit, desktop entry, and icon. It does **not** touch user-scope tasks in `~/.config/systemd/user/` — those are managed from within the app.

### Un-install and delete all system tasks
To also remove every system-wide task created by Task Scheduler, pass `--purge-tasks`:
```bash
sudo ./uninstall.sh --purge-tasks
```
This additionally removes all systemd units and udev rules written by the daemon, and deletes the snapshot store at `/var/lib/task-scheduler`.

## Security notes

The DBus policy currently allows **any local user** to invoke the daemon. Polkit per-method authorization is planned for a future release — once implemented, scheduling system-wide tasks will prompt for your administrator password.
