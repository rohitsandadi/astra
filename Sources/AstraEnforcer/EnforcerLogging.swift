import OSLog

enum EnforcerLog {
    static let lifecycle = Logger(subsystem: "com.rohitsandadi.astra.enforcer", category: "lifecycle")
    static let xpc = Logger(subsystem: "com.rohitsandadi.astra.enforcer", category: "xpc")
    static let applications = Logger(subsystem: "com.rohitsandadi.astra.enforcer", category: "applications")
    static let browsers = Logger(subsystem: "com.rohitsandadi.astra.enforcer", category: "browsers")
}
