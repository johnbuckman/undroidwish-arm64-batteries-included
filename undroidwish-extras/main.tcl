# undroidwish boot script (run automatically on a bare launch by the desktop
# main-thread hook in tkZipMain.c when the embedded zip carries a root main.tcl
# and no script argument was given). It:
#   * registers the batteries-included packages on auto_path,
#   * adds a "Demos" submenu to the console's File menu (borg bridge demo,
#     Bluetooth LE debugger, and the bundled AndroWish demos), and
#   * gives the console and the main "." window a sensible initial placement.
# Running `undroidwish <script>` (an explicit startup script) skips all of this,
# so de1plus / the demo dispatchers are unaffected.

# The embedded assets.zip is mounted on the executable path; its root is the
# batteries root.
set ::uw_root [info nameofexecutable]

# Optional trace (off by default): set UNDROIDWISH_BOOT_LOG to a path to trace
# boot + Demos-menu install (used to verify the real double-click launch path).
proc _uwlog {m} {
    if {[info exists ::env(UNDROIDWISH_BOOT_LOG)]} {
        catch {set fh [open $::env(UNDROIDWISH_BOOT_LOG) a]; puts $fh $m; close $fh}
    }
}
_uwlog "boot: root=$::uw_root"

# --- batteries-included packages on auto_path --------------------------------
# The root is already on auto_path (Tcl scans it one level deep), but register
# every package dir recursively so demos' nested `package require`s resolve.
if {$::uw_root ni $::auto_path} { lappend ::auto_path $::uw_root }
proc ::uw_add_pkgdirs {root} {
    if {[file exists [file join $root pkgIndex.tcl]] && ($root ni $::auto_path)} {
        lappend ::auto_path $root
    }
    foreach d [glob -nocomplain -type d -directory $root *] { ::uw_add_pkgdirs $d }
}
catch { ::uw_add_pkgdirs $::uw_root }

# Some C extensions find their companion .tcl via a *_LIBRARY env var / global.
foreach {_sub _envv} {itcl4* ITCL_LIBRARY treectrl* TREECTRL_LIBRARY itk* ITK_LIBRARY vu* VU_LIBRARY} {
    set _hits [glob -nocomplain -type d -directory $::uw_root $_sub]
    if {[llength $_hits]} { set ::env($_envv) [lindex $_hits 0] }
}
set _tc [glob -nocomplain -type d -directory $::uw_root treectrl*]
if {[llength $_tc]} { set ::treectrl_library [lindex $_tc 0] }
_uwlog "boot: auto_path ready (len [llength $::auto_path])"

# --- demo launching (runs in THIS, the main, interp) -------------------------
# key -> {Menu label   root-relative dispatcher}.  The dispatcher is a script at
# the zip root (the same ones you can pass as `undroidwish <key>`).  borg/BLE
# first, then the bundled AndroWish demos (greyed out if not present).
set ::uw_demos {
    borgdemo    {"borg — device bridge demo"       borgdemo}
    bledemo     {"Bluetooth LE debugger"                bledemo}
    -sep1       {}
    widget      {"Tk widget demo"                       widget}
    tkcon       {"tkcon — enhanced console"        tkcon}
    tkinspect   {"tkinspect — widget inspector"    tkinspect}
    tksqlite    {"TkSQLite — SQLite GUI"           tksqlite}
    tktable     {"Tktable — spreadsheet"           tktable}
    treectrl    {"TreeCtrl"                             treectrl}
    tkchat      {"tkchat"                               tkchat}
    tkpdemo     {"tkpath demos"                         tkpdemo}
    zinc-widget {"Tkzinc widget"                        zinc-widget}
    zint        {"zint — barcodes"                 zint}
    imgdemo     {"Img demo"                             imgdemo}
    notebook    {"notebook"                             notebook}
    stardom     {"stardom"                              stardom}
    vncviewer   {"VNC viewer"                           vncviewer}
    helpviewer  {"help viewer"                          helpviewer}
}
proc uw_demo_resolve {entry} {
    if {$entry eq ""} { return "" }
    set p [file join $::uw_root $entry]
    return [expr {[file exists $p] ? $p : ""}]
}
proc uw_run_demo {key} {
    foreach {k spec} $::uw_demos {
        if {$k ne $key} continue
        set path [uw_demo_resolve [lindex $spec 1]]
        if {$path eq ""} {
            catch {tk_messageBox -icon info -title "Demos" -message \
                "\"$key\" is not bundled in this undroidwish build."}
            return
        }
        set ::argv0 $path; set ::argv {}
        if {[catch {uplevel #0 [list source $path]} err]} {
            catch {tk_messageBox -icon error -title "Demos: $key" -message $err}
        }
        return
    }
}
# {key label available?} triples the console menu asks for.
proc uw_demo_menuspec {} {
    set out {}
    foreach {k spec} $::uw_demos {
        if {[string match -* $k]} { lappend out $k {} 0; continue }
        lappend out $k [lindex $spec 0] [expr {[uw_demo_resolve [lindex $spec 1]] ne ""}]
    }
    return $out
}

# --- install the "Demos" submenu on the console's File menu ------------------
# The console runs in a separate interp: drive it via `console eval`, and have
# its items call back into this (main) interp via `consoleinterp eval`. Retry
# until the console's File menu has been realized (iWish pattern).
proc uw_install_demos_menu {{tries 0}} {
    if {[catch {console eval {winfo exists .menubar.file}} ok] || !$ok} {
        if {$tries < 60} { after 150 [list uw_install_demos_menu [expr {$tries+1}]] } \
        else { _uwlog "demos: gave up (no .menubar.file after $tries tries)" }
        return
    }
    set rc [catch {console eval {
        if {![winfo exists .menubar.file.demos]} {
            menu .menubar.file.demos -tearoff 0
            set idx -1
            for {set i 0} {$i <= [.menubar.file index end]} {incr i} {
                if {[catch {.menubar.file type $i} t] || $t ne "command"} continue
                set l [.menubar.file entrycget $i -label]
                if {[string match -nocase *xit* $l] || [string match -nocase *quit* $l]} { set idx $i; break }
            }
            if {$idx >= 0} {
                .menubar.file insert $idx cascade -label "Demos" -menu .menubar.file.demos
            } else {
                .menubar.file add cascade -label "Demos" -menu .menubar.file.demos
            }
            foreach {k label avail} [consoleinterp eval uw_demo_menuspec] {
                if {[string match -* $k]} { .menubar.file.demos add separator; continue }
                .menubar.file.demos add command -label $label \
                    -state [expr {$avail ? "normal" : "disabled"}] \
                    -command [list consoleinterp eval [list uw_run_demo $k]]
            }
        }
        winfo exists .menubar.file.demos
    }} res]
    _uwlog "demos: installed (tries=$tries rc=$rc res=$res)"
}
after 300 uw_install_demos_menu

# --- initial window placement ------------------------------------------------
# Main "." window near the top-left; console centered on the screen. Deferred so
# Tk has mapped the windows first; the console lives in its own interp.
catch {wm title . "undroidwish"}
after 300 {catch {console show}}
after 300 {catch {wm geometry . +20+20}}
proc uw_center_console {{tries 0}} {
    if {[catch {console eval {winfo exists .}} ok] || !$ok} {
        if {$tries < 60} { after 150 [list uw_center_console [expr {$tries+1}]] }
        return
    }
    catch {console eval {
        wm title . "undroidwish console"
        update idletasks
        set w [winfo width .];  if {$w <= 1} { set w [winfo reqwidth .] }
        set h [winfo height .]; if {$h <= 1} { set h [winfo reqheight .] }
        set x [expr {([winfo screenwidth .]  - $w) / 2}]
        set y [expr {([winfo screenheight .] - $h) / 2}]
        if {$x < 0} { set x 0 }
        if {$y < 0} { set y 0 }
        wm geometry . +$x+$y
    }}
    _uwlog "placement: console centered"
}
after 300 uw_center_console
_uwlog "boot: main.tcl scheduled afters"
