# undroidwish-extras — borg demo, BLE debugger, Debug menu, window placement

Four conveniences ported from **iWish** (the iOS/Catalyst AndroWish port) to the
native arm64 desktop **undroidwish**. All of it ships inside the embedded
`assets.zip`; nothing changes for `undroidwish <script>` launches (e.g.
`unde1plus-arm64.sh` running `de1plus.tcl`) — the boot script only runs on a
**bare** launch (double-click / `undroidwish` with no arguments).

Files live in [`undroidwish-extras/`](undroidwish-extras/) and are copied into
`<androwish>/undroid/undroidwish-extras/` by `apply-patches.sh`; patch **10**
makes `build-undroidwish-macosx.sh` fold them into `assets.zip`.

## The four features

1. **borg sample program** — `undroidwish-demos/borgdemo.tcl`. A small GUI that
   exercises the macOS `borg` bridge (`patches/05`): toast, `say` TTS, system
   beeps, screen-brightness slider, and live `osbuildinfo`/`displaymetrics`/
   `locale`/`networkinfo`. Launch from the Debug menu or `undroidwish borgdemo`.

2. **BLE debugging program** — `undroidwish-demos/bledemo.tcl`. A LightBlue-style
   Bluetooth-LE debugger: scan → connect → browse services/characteristics →
   read / subscribe / write, plus a background 0x2A00 name-resolution sweep.
   Launch from the Debug menu or `undroidwish bledemo`.

3. **Debug menu in the console** — `main.tcl` injects a **Debug** cascade into
   the Tk console's menubar (it runs in a separate interp, so it is driven via
   `console eval` / `consoleinterp eval`, retried until the menubar realizes).
   Entries: borg demo, BLE debugger, and the bundled AndroWish dev tools
   (widget, tkcon, tkinspect, tksqlite, tkchat, 3ddemo). Unbundled entries grey
   out.

4. **Initial window placement** — `main.tcl` puts the main `.` window near the
   top-left (`+20+20`) and centers the console, deferred so Tk has mapped the
   windows first.

## How the boot script auto-runs (patch 09)

Stock undroidwish boots straight to a bare `wish` console — it has no
per-launch startup script (unlike iWish, whose Catalyst/iOS `tkAppInit.c` runs a
bundled `main.tcl`). Patch **09** adds the desktop equivalent to
`jni/sdl2tk/generic/**tkZipMain.c**` (the SDL wish's real `Tk_MainEx`, *not*
`tkMain.c`, whose `Tk_MainEx` is shadowed by the stub-lib copy): in the
interactive / no-startup-script branch, right after `Tcl_SourceRCFile`, it
sources `[info nameofexecutable]/main.tcl` if present. The embedded zip is
mounted on the executable path, so that resolves to the zip root. Only a build
whose zip carries a root `main.tcl` (i.e. undroidwish) is affected;
`wish <script>` sets a startup script and takes the other branch.

## The `ble` package (`ble1.0/`)

The tcl-ble-osx CoreBluetooth package. Its default backend is the
**Developer-ID-signed, universal (arm64+x86_64) `bin/ble_helper.bin`
subprocess** — the in-process native dylib is a deliberate opt-in it avoids, so
no arm64 native build is needed. One undroidwish-specific change to `ble.tcl`:
`ensure_helper` copies the helper out of the read-only zipfs mount to a real
temp path before `exec` (you cannot exec a binary from a VFS). The Developer-ID
code identity is path-independent, so the Bluetooth TCC grant survives the copy.

`bin/ble_helper.bin` is built from
[tcl-ble-osx](https://github.com/decentespresso) (`build.sh`); the copy here is
the signed universal binary.

## Borg pkgIndex fix

`Borg_Init` (patch 05, `tkBorgOSX.c`) calls `Tcl_PkgProvide` as capital
**`Borg`**. Patch 10 rewrites `assets/Borg1.0/pkgIndex.tcl` to add a lowercase
`borg` alias so `package require borg` (what the demos / de1app use) resolves.
