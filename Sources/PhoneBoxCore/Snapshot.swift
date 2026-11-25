/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. Plan 3 adds the other metrics as further optional fields.
public struct Snapshot: Equatable, Codable, Sendable {
    /// Milliseconds since 1970.
    public var t: Int64
    public var cpu: CPUSample?
    public var mem: MemorySample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil) {
        self.t = t
        self.cpu = cpu
        self.mem = mem
    }
}
