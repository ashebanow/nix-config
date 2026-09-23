# nix-config

Glossary for the NixOS/dendritic configuration of ashebanow's machines. It is a
glossary only: the vocabulary this config uses, and the words it deliberately
does not.

## Configuration model

**capability flag**:
A `my.<name>` boolean declared in `lib/my-options-module.nix` and set by a host;
a feature module activates its config only when its flag is true.
_Avoid_: feature toggle, enable option.

**feature module**:
A self-registering file under `modules/features/` that contributes config to
`my.modules.nixos` or `my.modules.home-manager` and is guarded by a capability
flag.
_Avoid_: service module, plugin.

**NixOS scope**, **Home Manager scope**:
The two module-system instances that evaluate a host — NixOS modules and Home
Manager modules. They do not share `config.my`: a value that only NixOS modules
read may be set in the host config, but a value a Home Manager module reads must
be set somewhere both scopes import.
_Avoid_: system scope, user scope.

## Desktop

**session**:
One selectable entry at the login screen that starts a graphical session, named
by its compositor or desktop environment (`niri`, `gnome`).
_Avoid_: desktop, DE, WM.

**default session**:
The session the display manager starts when nobody chooses one
(`my.desktopDefaultSession`).
_Avoid_: primary session, main desktop.

**desktop environment**:
A complete environment that brings its own shell, settings daemon and
applications — GNOME on these hosts.
_Avoid_: desktop.

**compositor**:
A Wayland compositor: windows, inputs and outputs, with no shell or status bar
of its own — niri on these hosts.
_Avoid_: window manager, WM.

**shell**:
The layer drawn on top of a compositor — bar, launcher, notifications,
clipboard, lock screen. DankMaterialShell is one, and it is why this config
needs no separate bar, launcher or notification daemon.
_Avoid_: desktop, bar.

**display manager**:
The program that presents the login screen and launches the chosen session —
GDM here; its login UI is a greeter, and DankGreeter would be a greetd-based
alternative to GDM itself, not an addition to it.
_Avoid_: greeter, login manager.
