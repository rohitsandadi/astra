import Foundation

if CommandLine.arguments.dropFirst().contains("--diagnose") {
    do {
        FileHandle.standardOutput.write(try EnforcerDiagnostics.encodedReport())
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(EXIT_SUCCESS)
    } catch {
        fputs("AstraEnforcer diagnostics failed: \(error)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

EnforcerLog.lifecycle.notice("Astra Enforcer starting")
let coordinator = EnforcementCoordinator()
do {
    try coordinator.restore()
} catch {
    EnforcerLog.lifecycle.error("Failed to restore active session: \(error.localizedDescription, privacy: .public)")
    fputs("AstraEnforcer could not restore its last session: \(error)\n", stderr)
}

let service = AstraEnforcerXPCService(coordinator: coordinator)
let listenerDelegate = AstraEnforcerXPCListenerDelegate(service: service)
let listener = NSXPCListener(machServiceName: "com.rohitsandadi.astra.enforcer")
listener.delegate = listenerDelegate
listener.resume()
EnforcerLog.lifecycle.notice("Mach service listener resumed")
RunLoop.current.run()
