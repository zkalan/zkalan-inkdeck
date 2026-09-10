import AppKit

// Normal lifecycle requests only; never force-terminate or touch another app.
let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
let allowed = ["Zkalan InkDeck.app", "触控板手写 2.app"].map { applications.appendingPathComponent($0).standardizedFileURL }
let running = ["io.github.zkalan.inkdeck", "local.trackpad-ink.app.v2"].flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
guard running.allSatisfy({ app in allowed.contains { $0 == app.bundleURL?.standardizedFileURL } }) else {
    fputs("Another copy of InkDeck is running; leave all copies unchanged.\n", stderr)
    exit(1)
}
if CommandLine.arguments.contains("--quit") {
    for app in running where !app.isTerminated {
        guard app.terminate() else { fputs("Normal quit request was declined.\n", stderr); exit(2) }
    }
    let deadline = Date().addingTimeInterval(20)
    while running.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard running.allSatisfy({ $0.isTerminated }) else { fputs("App has not finished saving and quitting; update aborted.\n", stderr); exit(3) }
    print("Installed app stopped normally; safe to update.")
} else {
    print("Installed app running instances: \(running.count)")
    for app in running { print("PID \(app.processIdentifier), finishedLaunching: \(app.isFinishedLaunching), path: \(app.bundleURL!.path)") }
}
