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
    /// A regular (Dock) app, as opposed to a helper macOS lists too (an accessory or background app).
    public var regular: Bool

    public init(pid: Int32, bundleId: String?, name: String, quittable: Bool, regular: Bool) {
        self.pid = pid
        self.bundleId = bundleId
        self.name = name
        self.quittable = quittable
        self.regular = regular
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
        bundlePaths(forExecutable: path).first
    }

    /// Every `.app` bundle that contains an executable, outermost first.
    static func bundlePaths(forExecutable path: String) -> [String] {
        var components: [Substring] = []
        var bundles: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            components.append(component)
            if component.hasSuffix(".app") { bundles.append(components.joined(separator: "/")) }
        }
        return bundles
    }

    /// The bundle a process is filed under: the innermost `.app` around it that runs as a regular (Dock) app, so that
    /// Simulator inside Xcode is "Simulator"; otherwise the outermost, so that a helper counts as its app even when
    /// macOS lists the helper too. Nil when the executable is not inside an app.
    public static func bundlePath(forExecutable path: String, apps: [String: AppInfo]) -> String? {
        let bundles = bundlePaths(forExecutable: path)
        return bundles.last { apps[$0]?.regular == true } ?? bundles.first
    }

    /// Longest name sent to the phone, in characters (grapheme clusters).
    public static let maxNameLength = 80

    /// Cleans a name that an app or a web page chose before it reaches the phone: invisible format characters
    /// (direction marks such as WhatsApp's leading U+200E, zero-width spaces) are removed, except the zero-width
    /// joiner and non-joiner that emoji sequences and Persian or Indic text need; control characters, line
    /// and paragraph separators and runs of white space become one space; the result is trimmed and keeps at most
    /// `maxNameLength` characters (and at most four times as many Unicode scalars, so a letter piled with combining
    /// marks stays small).
    public static func displayName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in raw.unicodeScalars {
            if scalars.count >= maxNameLength * 4 { break }
            switch scalar.properties.generalCategory {
            case .format where scalar.value != 0x200C && scalar.value != 0x200D:
                continue
            case .control, .lineSeparator, .paragraphSeparator, .spaceSeparator:
                pendingSpace = true
            default:
                if pendingSpace, !scalars.isEmpty { scalars.append(" ") }
                pendingSpace = false
                scalars.append(scalar)
            }
        }
        return String(String(scalars).prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
    }

    /// The first of the app's own name, its bundle's file name and the executable's file name that is not empty
    /// after cleaning.
    static func name(app: String?, bundle: String?, executable: String) -> String {
        let candidates = [app, bundle.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension },
                          (executable as NSString).lastPathComponent]
        for case let candidate? in candidates {
            let cleaned = displayName(candidate)
            if !cleaned.isEmpty { return cleaned }
        }
        return "?"
    }

    /// Busiest first; equal rows keep a stable order (by name, then pid) so the phone's list does not flicker.
    static func busier(_ a: AppSample, _ b: AppSample) -> Bool {
        if a.cpu != b.cpu { return a.cpu > b.cpu }
        if a.mem != b.mem { return a.mem > b.mem }
        if a.name != b.name { return a.name < b.name }
        return a.pid < b.pid
    }

    static func larger(_ a: AppSample, _ b: AppSample) -> Bool {
        a.mem != b.mem ? a.mem > b.mem : busier(a, b)
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
            let bundle = bundlePath(forExecutable: process.path, apps: apps)
            let key = bundle ?? process.path
            var group = groups[key] ?? {
                if let bundle, let info = apps[bundle] {
                    return Group(pid: info.pid, bundleId: info.bundleId,
                                 name: name(app: info.name, bundle: bundle, executable: process.path), quittable: info.quittable)
                }
                return Group(pid: process.pid, bundleId: nil, name: name(app: nil, bundle: bundle, executable: process.path),
                             quittable: false)
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
        let byCPU = samples.sorted(by: busier).prefix(topCount)
        let byMemory = samples.sorted(by: larger).prefix(topCount)
        var result = Array(byCPU)
        for sample in byMemory where !result.contains(where: { $0.pid == sample.pid && $0.name == sample.name }) {
            result.append(sample)
        }
        return result
    }
}
