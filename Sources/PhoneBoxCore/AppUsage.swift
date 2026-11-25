import Foundation

/// One process as `libproc` reports it.
public struct ProcessReading: Equatable, Sendable {
    public var pid: Int32
    /// Path of the executable.
    public var path: String
    /// User + system CPU time so far, in nanoseconds.
    public var cpuNanos: UInt64
    /// Physical footprint in bytes (what Activity Monitor calls Memory).
    public var memory: UInt64

    public init(pid: Int32, path: String, cpuNanos: UInt64, memory: UInt64) {
        self.pid = pid
        self.path = path
        self.cpuNanos = cpuNanos
        self.memory = memory
    }
}

/// What macOS knows about a running app, keyed by its bundle path (from `NSRunningApplication`).
public struct AppInfo: Equatable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    /// A regular (Dock) app that the phone may quit later (Plan 3B); Finder and PhoneBox are never quittable.
    public var quittable: Bool

    public init(pid: Int32, bundleId: String?, name: String, quittable: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.quittable = quittable
    }
}

/// One row of the "apps" list (design §6).
public struct AppSample: Equatable, Codable, Sendable {
    public var pid: Int32
    public var bundleId: String?
    public var name: String
    /// Percent of one core, like Activity Monitor (can exceed 100).
    public var cpu: Double
    /// Bytes.
    public var mem: UInt64
    public var quittable: Bool

    public init(pid: Int32, bundleId: String?, name: String, cpu: Double, mem: UInt64, quittable: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.cpu = cpu
        self.mem = mem
        self.quittable = quittable
    }
}

public enum AppUsage {
    public static let topCount = 5

    /// The outermost `.app` bundle that contains an executable, so that "Google Chrome Helper (Renderer)" deep
    /// inside Chrome counts as Chrome. Nil when the executable is not inside an app.
    public static func bundlePath(forExecutable path: String) -> String? {
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            components.append(component)
            if component.hasSuffix(".app") { return components.joined(separator: "/") }
        }
        return nil
    }

    /// Removes the invisible direction marks some apps put in their names (WhatsApp starts with U+200E) and trims.
    public static func displayName(_ raw: String) -> String {
        let marks: Set<Unicode.Scalar> = ["\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}",
                                          "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}"]
        let kept = raw.unicodeScalars.filter { !marks.contains($0) }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Groups processes into apps, turns CPU time into percent of one core over `elapsedNanos`, and returns the
    /// top apps by CPU followed by the top apps by memory that are not already listed (at most 2 × `topCount`).
    /// A process with no earlier reading (or whose counter went backwards) counts as 0 % this time.
    public static func top(previousCPU: [Int32: UInt64], current: [ProcessReading], elapsedNanos: UInt64,
                           apps: [String: AppInfo]) -> [AppSample] {
        guard elapsedNanos > 0 else { return [] }
        struct Group {
            var pid: Int32
            var bundleId: String?
            var name: String
            var quittable: Bool
            var cpuNanos: UInt64 = 0
            var memory: UInt64 = 0
        }
        var groups: [String: Group] = [:]
        for process in current {
            let bundle = bundlePath(forExecutable: process.path)
            let key = bundle ?? process.path
            var group = groups[key] ?? {
                if let bundle, let info = apps[bundle] {
                    return Group(pid: info.pid, bundleId: info.bundleId, name: displayName(info.name),
                                 quittable: info.quittable)
                }
                let fallback = bundle.map { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "") }
                return Group(pid: process.pid, bundleId: nil,
                             name: displayName(fallback ?? (process.path as NSString).lastPathComponent), quittable: false)
            }()
            if let before = previousCPU[process.pid], process.cpuNanos >= before {
                group.cpuNanos += process.cpuNanos - before
            }
            group.memory += process.memory
            groups[key] = group
        }
        let samples = groups.values.map { group in
            AppSample(pid: group.pid, bundleId: group.bundleId, name: group.name,
                      cpu: CPULoad.rounded(Double(group.cpuNanos) / Double(elapsedNanos) * 100),
                      mem: group.memory, quittable: group.quittable)
        }
        let byCPU = samples.sorted { ($0.cpu, $0.mem) > ($1.cpu, $1.mem) }.prefix(topCount)
        let byMemory = samples.sorted { $0.mem > $1.mem }.prefix(topCount)
        var result = Array(byCPU)
        for sample in byMemory where !result.contains(where: { $0.pid == sample.pid && $0.name == sample.name }) {
            result.append(sample)
        }
        return result
    }
}
