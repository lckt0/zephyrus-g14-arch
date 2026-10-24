// Close rofi automatically when it loses focus.
//
// How it works:
//   - rofi is started with `-normal-window`, so KWin sees it as a normal
//     window (a layer-shell surface would not appear in the window list).
//   - When another window becomes active, `rofi-kill.service` is started; it
//     runs `pkill -x rofi`, which kills ONLY the rofi process.
//   - KWin scripts cannot run commands; `callDBus` is the only way out.
//     `closeWindow()` does not help: rofi ignores the close request.
//
// Do not kill a cgroup/scope instead (e.g. systemd KillUnit on a rofi scope):
// the application rofi launches is born in the same scope and would be killed
// too, so nothing could be launched from rofi.

var KILL_UNIT = "rofi-kill.service";

function isRofi(w) {
    return !!w && String(w.resourceClass || "").toLowerCase() === "rofi";
}

function rofiIsOpen() {
    var list = workspace.windowList();
    for (var i = 0; i < list.length; i++) {
        if (isRofi(list[i])) {
            return true;
        }
    }
    return false;
}

workspace.windowActivated.connect(function (active) {
    if (isRofi(active) || !rofiIsOpen()) {
        return;
    }
    callDBus("org.freedesktop.systemd1",
             "/org/freedesktop/systemd1",
             "org.freedesktop.systemd1.Manager",
             "StartUnit",
             KILL_UNIT, "replace");
});
