import AppKit
import Foundation

public enum RunningAppActivation {
    /// A successful request is not proof of activation. Keep the main run loop
    /// alive and read back the frontmost application before reporting success.
    public static func activate(_ app: NSRunningApplication) -> Bool {
        verify(request: { app.activate(options: []) },
               isFrontmost: {
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
               },
               tick: { RunLoop.current.run(until: Date().addingTimeInterval(0.04)) })
    }

    static func verify(request: () -> Bool, isFrontmost: () -> Bool,
                       tick: () -> Void, maximumChecks: Int = 25) -> Bool {
        guard request() else { return false }
        for _ in 0..<maximumChecks {
            tick()
            if isFrontmost() { return true }
        }
        return false
    }
}
