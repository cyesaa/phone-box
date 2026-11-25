import os

/// `log stream --predicate 'subsystem == "com.phonebox.PhoneBox"'` shows these. Nothing is written to files.
enum Log {
    static let app = Logger(subsystem: "com.phonebox.PhoneBox", category: "app")
    static let server = Logger(subsystem: "com.phonebox.PhoneBox", category: "server")
}
