/// One second of the Mac, as the phone receives it (design §6). A metric that could not be read is left out
/// of the JSON; the dashboard shows "—" for it. `apps` is sent every third second; `media` only while something
/// is playing (or paused), `audio` only for an output with volume control and `phone` only while one iPhone is
/// plugged in over USB and its battery could be read.
public struct Snapshot: Equatable, Codable, Sendable {
    /// Milliseconds since 1970.
    public var t: Int64
    public var cpu: CPUSample?
    public var mem: MemorySample?
    public var gpu: GPUSample?
    public var temp: TemperatureSample?
    public var power: PowerSample?
    public var net: NetworkSample?
    public var disk: DiskSample?
    public var battery: BatterySample?
    public var apps: [AppSample]?
    public var media: MediaSample?
    public var audio: AudioSample?
    public var phone: PhoneBatterySample?

    public init(t: Int64, cpu: CPUSample? = nil, mem: MemorySample? = nil, gpu: GPUSample? = nil,
                temp: TemperatureSample? = nil, power: PowerSample? = nil, net: NetworkSample? = nil,
                disk: DiskSample? = nil, battery: BatterySample? = nil, apps: [AppSample]? = nil,
                media: MediaSample? = nil, audio: AudioSample? = nil, phone: PhoneBatterySample? = nil) {
        self.t = t
        self.cpu = cpu
        self.mem = mem
        self.gpu = gpu
        self.temp = temp
        self.power = power
        self.net = net
        self.disk = disk
        self.battery = battery
        self.apps = apps
        self.media = media
        self.audio = audio
        self.phone = phone
    }
}
