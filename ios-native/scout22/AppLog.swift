import os

/// Central loggers. Use these instead of print() — output is visible in
/// Console.app / Xcode with subsystem filtering and stripped of PII by
/// default (os.Logger redacts interpolated values unless marked public).
enum AppLog {
    private static let subsystem = "com.tryscout22.scout22"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    /// ATS autofill/capture inside the apply WebView. Field labels and values
    /// stay redacted by default — only mark a value public when it is known
    /// non-PII (a host name, a field count).
    static let autofill = Logger(subsystem: subsystem, category: "autofill")
}
