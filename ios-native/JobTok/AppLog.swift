import os

/// Central loggers. Use these instead of print() — output is visible in
/// Console.app / Xcode with subsystem filtering and stripped of PII by
/// default (os.Logger redacts interpolated values unless marked public).
enum AppLog {
    private static let subsystem = "com.jobtok.jobtok"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
