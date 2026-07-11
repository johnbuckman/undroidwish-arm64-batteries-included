# undroidwish-extras

Files copied into the embedded assets.zip by build-undroidwish-macosx.sh to add:

* `main.tcl` — bare-launch boot script (auto-sourced by the tkZipMain.c hook):
  registers batteries on auto_path, adds a **Debug** menu to the console
  (borg demo, Bluetooth LE debugger, and bundled AndroWish dev tools), and
  places the console + main "." window on launch.
* `undroidwish-demos/borgdemo.tcl` — sample program exercising the `borg`
  desktop device bridge (toast/speak/beep/brightness/device-info).
* `undroidwish-demos/bledemo.tcl` — a LightBlue-style Bluetooth LE debugger.
* `ble1.0/` — the tcl-ble-osx `ble` package (CoreBluetooth). Default backend is
  the Developer-ID-signed, universal (arm64+x86_64) `bin/ble_helper.bin`
  subprocess. `ensure_helper` was patched to copy the helper out of the
  read-only zipfs mount to a real temp path before exec (you can't exec from
  a VFS); the Developer-ID identity is path-independent so the Bluetooth TCC
  grant survives the copy.
