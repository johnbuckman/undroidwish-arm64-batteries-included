# Tcl package index for the macOS "ble" command (tcl-ble-osx), bundled into
# undroidwish. Provides lowercase `ble` (what de1app / the bledemo require).
package ifneeded ble 1.0 [list source [file join $dir ble.tcl]]
