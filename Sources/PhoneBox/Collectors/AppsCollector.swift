import AppKit
import Darwin
import PhoneBoxCore

/// The apps using the most CPU and memory (design §6). Reads every process this user may inspect through `libproc`;
/// processes of other users (root daemons such as WindowServer) cannot be read without privileges and are skipped.
@MainActor
final class AppsCollector {
    /// Asking `NSWorkspace` for the running apps is costly; a list up to 10 s old is good enough for names.
    static let appListInterval: UInt64 = 10_000_000_000
    private var previousCPU: [Int32: UInt64] = [:]
    private var previousTime: UInt64?
    private var apps: [String: AppInfo] = [:]
    private var appsTime: UInt64?

    func reset() {
        previousCPU = [:]
        previousTime = nil
        appsTime = nil
    }

    func sample() -> [AppSample]? {
        let now = DispatchTime.now().uptimeNanoseconds
        let readings = Self.readProcesses()
        // A failed process listing is not "no apps": keep the earlier readings and let the page keep its list.
        guard !readings.isEmpty else { return nil }
        defer {
            previousCPU = Dictionary(readings.map { ($0.pid, $0.cpuNanos) }, uniquingKeysWith: { first, _ in first })
            previousTime = now
        }
        guard let previousTime, now > previousTime else { return nil }
        if appsTime.map({ now - $0 >= Self.appListInterval }) ?? true {
            apps = Self.runningApps()
            appsTime = now
        }
        return AppUsage.top(previousCPU: previousCPU, current: readings, elapsedNanos: now - previousTime, apps: apps)
    }

    /// `rusage` CPU times are in Mach absolute time units; this converts them to nanoseconds.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(1, info.denom)))
    }()

    static func readProcesses() -> [ProcessReading] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        var readings: [ProcessReading] = []
        readings.reserveCapacity(Int(count))
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard result == 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
            let ticks = usage.ri_user_time &+ usage.ri_system_time
            let nanos = ticks.multipliedReportingOverflow(by: timebase.numer)
            readings.append(ProcessReading(pid: pid, path: String(cString: path),
                                           cpuNanos: nanos.overflow ? ticks : nanos.partialValue / timebase.denom,
                                           memory: usage.ri_phys_footprint))
        }
        return readings
    }

    /// Running apps keyed by bundle path, so helper processes can be named after their app.
    static func runningApps() -> [String: AppInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var apps: [String: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let path = app.bundleURL?.path else { continue }
            let quittable = app.activationPolicy == .regular && app.bundleIdentifier != "com.apple.finder"
                && app.processIdentifier != ownPID
            apps[path] = AppInfo(pid: app.processIdentifier, bundleId: app.bundleIdentifier,
                                 name: app.localizedName ?? (path as NSString).lastPathComponent, quittable: quittable)
        }
        return apps
    }
}
