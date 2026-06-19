# `borg` on macOS desktop (undroidwish) — command reference

`jni/src/tkBorgOSX.c` (patches 05/06) re-introduces the AndroWish **`borg`**
command for the macOS desktop build of undroidwish, which otherwise ships
"sans the borg". This document lists **every** documented Android `borg`
subcommand (per <https://androwish.org/home/wiki?name=Android+facilities>) and
states, for each, whether this macOS port implements it, how it compares to the
Android behaviour, and — where it does nothing useful — why it can't.

## Why a separate file instead of porting `tkBorg.c`

The Android `borg` (`jni/src/tkBorg.c`, ~6900 lines) is a JNI bridge to the
Android framework — every subcommand calls into Java. None of that exists on the
desktop. Rather than `#ifdef`-shred the JNI file, `tkBorgOSX.c` is a clean,
self-contained reimplementation guarded by `__APPLE__` that:

* exposes the **same subcommand surface** as the documented Android command, so
  existing AndroWish / de1app code runs unmodified;
* **never raises a Tcl error on a well-formed call** — subcommands with no macOS
  analogue are accepted no-ops returning the Android-shaped "empty" value;
* uses only facilities already available to the build — libc, Tcl, CoreFoundation,
  IOKit, CoreGraphics, plus the standard CLI tools `say`, `open`, `osascript`,
  `system_profiler`, `afplay` (launched with `posix_spawn`). The one private API
  (screen brightness via `DisplayServices`) is reached lazily with `dlopen`, so
  there is no new hard link dependency.

It builds as a **loadable Tcl stubs package** (`package require Borg`) bundled
into `assets.zip` — the same mechanism undroidwish already uses for all its
batteries.

### Platform identified from standard `osbuildinfo` keys

This port fills the **existing** Android-shaped `osbuildinfo` keys with real
Apple values, and callers identify the platform from those:

- **`manufacturer`** = `Apple` → an Apple build (Android reports the device maker).
- **`product`** = `undroidwish` here, `iWish` from the iWish iOS/Catalyst borg →
  distinguishes the two Apple builds (both run on Mac hardware under Catalyst).
- **`model`** = `Mac16,12` here (real `hw.model`); the iWish borg reports the real
  `iPad..`/`iPhone..` model on iOS and a `Mac..` model on Catalyst → tells iOS
  hardware from Mac.

So de1app sets `::iwish` from `product eq "iWish"` and `::ios` from an
iPad/iPhone/iPod `model`. Full key reference and per-platform values are below.

---

## `osbuildinfo` — full key reference & platform identification

`borg osbuildinfo` returns a flat Tcl dict modeled on Android's
`android.os.Build.*`. Every AndroWish-family build fills these **standard keys**
with real values for its platform, so callers identify the platform from the
existing keys alone — no extra/custom key is added.

Real values are all available (`sysctl` on Mac, `UIDevice`/`hw.machine` on iOS).
The per-platform fills:

### Keys, per platform

| key | Android (e.g. Teclast) | macOS desktop (undroidwish) | iWish — iOS device | iWish — Mac Catalyst |
|---|---|---|---|---|
| `manufacturer` | device maker (`Teclast`) | `Apple` | `Apple` | `Apple` |
| `brand` | device brand | `Apple` | `Apple` | `Apple` |
| `product` | build product (`M50Mini`) | **`undroidwish`** | **`iWish`** | **`iWish`** |
| `model` | `M50Mini` | `Mac16,12` (`hw.model`) | `iPad13,1` (`hw.machine`) | `Mac16,12` (`hw.model`) |
| `device` | `M50Mini` | = model | = model | = model |
| `cpu_abi` | `arm64-v8a` | `arm64` (`hw.machine`) | `arm64` | `arm64` |
| `version.release` | `14` (Android) | `26.2` (`kern.osproductversion`) | iOS ver (`UIDevice.systemVersion`) | iOS-compat ver |
| `version.sdk` | `34` (API level) | `0` (n/a) | `0` | `0` |
| `board` | `mt6771` | `hw.target` | = model | = model |
| `hardware` | `mt8788` | `Apple M4` (cpu brand) | = model | = model |
| `fingerprint` | Android format | `Apple/undroidwish/<model>:<rel>/<darwin>/0:user/release-keys` | `Apple/iWish/<model>:<rel>/0:user/release-keys` | same form |
| `serial` | `unknown` | `unknown` | `unknown` | `unknown` |
| `version.codename`/`tags`/`type` | `REL`/`release-keys`/`user` | same | same | same |
| `version.incremental`/`id`/`display` | Android build ids | `kern.osversion` (Darwin, e.g. `25C56`) | — | — |
| `bootloader`/`cpu_abi2`/`radio`/`time` | device values | empty / `0` | empty / `0` | empty / `0` |

### How a caller identifies the platform

```tcl
set bi [borg osbuildinfo]
set apple [expr {[dict exists $bi manufacturer] && [dict get $bi manufacturer] eq "Apple"}]

# Which Apple build? iOS + Catalyst are the same iWish build; desktop is undroidwish.
set iwish [expr {[dict exists $bi product] && [dict get $bi product] eq "iWish"}]

# Real iOS hardware (iPad/iPhone/iPod) -- NOT Mac Catalyst, whose model is "Mac..".
set ios [expr {$apple && [dict exists $bi model] \
               && [regexp {^(iPad|iPhone|iPod)} [dict get $bi model]]}]
```

| platform | `manufacturer` | `product` | `model` | apple | iwish | ios |
|---|---|---|---|:--:|:--:|:--:|
| Android | device maker | build product | device model | 0 | 0 | 0 |
| macOS desktop (undroidwish) | `Apple` | `undroidwish` | `Mac…` | 1 | 0 | 0 |
| iWish iOS device / simulator | `Apple` | `iWish` | `iPad…`/`iPhone…` | 1 | 1 | 1 |
| iWish Mac Catalyst | `Apple` | `iWish` | `Mac…` | 1 | 1 | 0 |

### Rationale / gotchas

- **Standard keys only** — no custom/extra key is added; the platform is read
  entirely from the values above.
- **`product` carries the build identity** (`undroidwish` vs `iWish`). Necessary
  because Catalyst-iWish and desktop-undroidwish run on **identical Mac hardware**
  (same `model`/`manufacturer`/`version.release`) — only the app differs.
- **`model` is read from `sysctl`, not `[UIDevice model]`.** On Mac Catalyst
  `[UIDevice currentDevice].model` returns `"iPad"`, which would make Catalyst
  look like iOS. The iWish borg uses (compile-time, one dylib per target):
  `hw.machine` on iOS, `SIMULATOR_MODEL_IDENTIFIER` in the simulator, `hw.model`
  on Catalyst. The macOS port uses `hw.model`.
- **`version.sdk` is Android-only** (the API level — `34` = Android 14). No Apple
  equivalent, so `0` on Apple. The strongest "this is Android" tells are
  `version.sdk` (a real API level), the Android-format `fingerprint`, and
  `cpu_abi arm64-v8a`.
- **Android is not detected via osbuildinfo** by de1app — it uses the presence of
  the real `ble`/`BLT` packages. osbuildinfo's role here is to split the *Apple*
  builds (iOS vs Catalyst vs desktop).

### Where this is implemented
- macOS desktop (undroidwish): `jni/src/tkBorgOSX.c` → `BorgOSBuildInfo()` (this
  patch set, `patches/05`).
- iWish (iOS/iPadOS/Catalyst): `tclBorgios.m` `osbuildinfo` case — see
  [`johnbuckman/iwish` → `src-ios/borg-ios/OSBUILDINFO.md`](https://github.com/johnbuckman/iwish/blob/main/src-ios/borg-ios/OSBUILDINFO.md).
- de1app consumer: `de1plus/ios.tcl` (`::iwish`/`::ios`) and `de1plus/utils.tcl`
  (`running_on_ios`).

---

## Legend

| mark | meaning |
|------|---------|
| ✅ **native** | real macOS behaviour, functionally equivalent to Android |
| 🟡 **partial** | works for the common case; some Android capability not reproduced |
| ⛔ **stub** | accepted (never errors) but does nothing useful — no macOS analogue, or not bridged |

---

## ✅ Implemented natively

| subcommand | Android does | macOS port does | same / different |
|---|---|---|---|
| `log prio tag msg` | writes to the Android system log (logcat) | writes `tag: msg` to `stderr` | same role, different sink |
| `trace msg script` | wraps `script` in systrace begin/end markers, evals it | evals `script` (errors propagate); marker ignored | same result, no systrace |
| `beep ?uri?` | plays a notification sound | `afplay <uri>` if given, else `osascript -e beep` | same |
| `speak text ?lang pitch rate?` | Android TextToSpeech | macOS `say`; `rate` mapped to words-per-minute; tracks the child pid | same role (TTS); `lang`/`pitch` not mapped |
| `stopspeak` | stops TTS | `SIGTERM`s the `say` child | same |
| `isspeaking` | TTS speaking? | `kill(pid,0)` liveness of the `say` child | same |
| `endspeak` | stop TTS + release engine | same as `stopspeak` | same (no engine to release) |
| `toast text ?long?` | native ephemeral Toast overlay | a borderless, top-most Tk overlay that auto-dismisses (2 s / 3.5 s) | same UX, Tk implementation |
| `spinner bool` | shows/hides a busy indicator | sets/clears the `watch` cursor on `.` | same intent |
| `displaymetrics` | `density densitydpi width height xdpi ydpi scaleddensity rotation` | **same keys**, computed from CoreGraphics pixel size + physical size; `rotation 0` | same format, different source |
| `osbuildinfo` | flat `{key value …}` of `android.os.Build.*` | **same key set**, filled with real Apple values from `sysctl` (`manufacturer Apple`, `model` `hw.model`, `product undroidwish`, `cpu_abi` `hw.machine`, `version.release` `kern.osproductversion`, a built `fingerprint`, …) | same shape; platform is read from these standard keys |
| `systemproperties ?name?` | Android system properties | `sysctlbyname(name)`; no name → a representative set | analogous |
| `networkinfo` | `none` / `wifi` / `mobile …` / type name | `none` / `wifi` / `ethernet` via `getifaddrs` | same vocabulary (no cellular) |
| `keyboardinfo` | `keyboard … hidden …` from the device config | `keyboard qwerty hidden 0 hardhidden 0` (desktop always has a keyboard) | simplified |
| `locale ?set\|lang\|tts ?lang??` | JVM locale get/set | `setlocale` get/set | same role |
| `brightness ?pct?` | screen brightness 0–100 | real brightness via `DisplayServicesGetBrightness`/`SetBrightness` (dlopen); falls back to `100`/no-op if unavailable | same (now controls the real display) |
| `osenvironment op` | Android storage dirs/state | mapped to macOS: `datadir`→`~/Library/Application Support/undroidwish`, `downloadcachedir`→`~/Library/Caches`, `externalstoragepublicdir`→`~/Documents`, `rootdir`→`/`, `externalstoragestate`→`mounted` | analogous paths |
| `sharedpreferences file op ?k v?` | Android SharedPreferences (typed KV) | a typed KV store, one Tcl-dict file per `file` under `~/Library/Application Support/undroidwish/prefs/`; supports `get/set {boolean,float,int,long,string}`, `remove`, `clear`, `all`, `alltypes`, `keys`, with defaults | functionally equivalent |
| `usbdevices ?extended?` | list of connected USB devices | IOKit `IOUSBDevice` enumeration → `{vendor product manufacturer name serial}` per device | same |
| `withdraw` | hide the app window | `wm withdraw .` | same |

## 🟡 Partial

| subcommand | Android does | macOS port does | gap |
|---|---|---|---|
| `activity action uri type …` | launches any Android Intent | the common **VIEW** intent → `open <uri>`; other actions accepted as no-ops | only URL/file opening is mapped |
| `notification add\|delete\|led` | full notification-area control | `add` → `osascript display notification` (title/text); `delete`/`led` are no-ops | macOS has no per-id removal or LED here |
| `bluetooth state\|on\|off\|…` | full adapter control + paired list | `state` parsed from `system_profiler SPBluetoothDataType`; `on`/`off` via `blueutil` if installed (else no-op); `devices`/`myaddress`/`remoteaddress`/`scanmode`/discovery → empty/no-op | no device enumeration or programmatic power without `blueutil` |
| `usbpermission device ?ask?` | request/query USB permission | always returns granted (`1`) | macOS has no per-device USB permission gate |
| `checkpermission ?perms… ask?` | runtime permission request/query | reports everything granted | macOS app-permission model differs; nothing to request here |
| `onintent ?command?` | set/get the incoming-intent callback | stores and returns the command, but it never fires | no Android intent delivery on the desktop |

## ⛔ Stub only — could **not** be made to work

These are accepted and never error (so AndroWish/de1app code runs), but they do
nothing useful. Reason given for each.

| subcommand | why it can't work on macOS desktop |
|---|---|
| `vibrate duration` | no vibration hardware |
| `sendsms phone msg …` | no telephony stack |
| `phoneinfo` | no telephony — returns empty |
| `tetherinfo` | no Android tethering service — returns the empty `active {} available {} error {}` shape |
| `ndefread` / `ndefwrite` / `ndefformat` | Macs have no NFC radio |
| `screenorientation ?orient?` | desktop displays don't rotate — reports `landscape`, set ignored |
| `systemui ?flags?` | no Android system-UI/immersive flags — reports `0`, set ignored |
| `sensor list\|enable\|disable\|state\|get` | Android's indexed sensor framework has no macOS equivalent (Macs expose a different, small sensor set) — returns empty / `0` |
| `camera …` | AVFoundation capture is not bridged yet — reports `0` cameras, `closed`, etc. (see "future work") |
| `location get\|gps\|nmea\|satellites\|start\|stop` | CoreLocation needs a bundled app with a usage-description and user consent — not bridged (see "future work") |
| `speechrecognition intent\|callback\|start\|stop\|cancel` | on-device dictation (Speech.framework) not bridged — accepted no-op (see "future work") |
| `broadcast list\|register\|send\|unregister` | there is no system-wide broadcast bus to join — `list` → empty, rest no-op |
| `shortcut add\|delete` | creating Desktop/Dock launchers is intentionally not done (invasive) — no-op |
| `alarm clear\|set\|wakeup` | no per-app alarm service; `pmset schedule` needs root — no-op |
| `packageinfo ?name?` | no Android PackageManager — returns empty |
| `providerinfo` | no content-provider registry — returns empty |
| `queryactivities` / `queryservices` / `querybroadcastreceivers` | no Intent resolver — return empty |
| `queryconsts classname` / `queryfields classname` | reflect Java/JVM class constants; there is no JVM — return empty |
| `queryfeatures` | no Android hardware-feature registry — returns empty |
| `cancel id` | no pending Android activities to cancel — no-op |
| `content query\|insert\|update\|delete` (+ the `$cursor` object) | Android content providers (contacts, media, …) have no analogue. To keep callers safe, `content query` returns a working **empty** cursor (`count`→0, `getstring`→"", `move`→0, …) and `insert/update/delete` return `0` rows |

### Future work (bridgeable, just not done)
- `camera …` — via AVFoundation (or the existing `tcluvc` battery).
- `location …` — via CoreLocation (requires an app bundle entitlement + consent prompt).
- `speechrecognition …` — via Speech.framework (`SFSpeechRecognizer`).
- `bluetooth` device enumeration / power — via IOBluetooth (Objective-C).

---

## Status

Implemented and verified on Apple Silicon (macOS 26 / Darwin 25): every
documented subcommand loads and runs; the ✅ commands return correct data;
malformed calls still report the usual `wrong # args` / `bad option` diagnostics,
matching the Android command. de1app drives this borg directly — its own
desktop borg stub steps aside automatically when the real command is present
(`if {[llength [info commands borg]] == 0}` gate in `utils.tcl`).

This is offered for upstream review — undroidwish deliberately omits borg, so
whether to ship a desktop borg is the maintainer's call.
