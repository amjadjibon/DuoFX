import AppKit

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.duofx.DuoFX")
for app in apps where !app.isTerminated {
    guard app.terminate() else {
        fputs("DuoFX could not quit. Use Quit DuoFX in the menu bar, then run the installer again.\n", stderr)
        exit(1)
    }
}
let deadline = Date().addingTimeInterval(15)
while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if apps.contains(where: { !$0.isTerminated }) {
    fputs("DuoFX is still shutting down. Quit it from the menu bar and retry installation.\n", stderr)
    exit(1)
}
