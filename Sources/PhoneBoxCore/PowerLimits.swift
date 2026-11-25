/// Where the page's power tile starts turning red and where it is fully red, in watts (design §8 "Sınıra
/// yaklaşınca kızarma"). The figures are rough, per chip family, and open to community testing.
public struct PowerLimits: Equatable, Sendable {
    public var start: Double
    public var full: Double

    public init(start: Double, full: Double) {
        self.start = start
        self.full = full
    }

    /// A plain M-series chip, whole Mac; also used for a chip PhoneBox does not know.
    public static let standard = PowerLimits(start: 15, full: 35)

    /// `brand` is `machdep.cpu.brand_string`, e.g. "Apple M4 Pro". `wholeMac` is true when the power tile shows the
    /// whole Mac (MacBooks); desktop Macs only report the GPU's power.
    public static func forChip(_ brand: String, wholeMac: Bool) -> PowerLimits {
        let tier = brand.split(separator: " ").last.map(String.init) ?? ""
        switch (tier, wholeMac) {
        case ("Pro", true): return PowerLimits(start: 25, full: 60)
        case ("Pro", false): return PowerLimits(start: 10, full: 30)
        case ("Max", true): return PowerLimits(start: 35, full: 100)
        case ("Max", false): return PowerLimits(start: 20, full: 60)
        case ("Ultra", true): return PowerLimits(start: 50, full: 160)
        case ("Ultra", false): return PowerLimits(start: 30, full: 90)
        case (_, false): return PowerLimits(start: 5, full: 15)
        default: return standard
        }
    }
}

extension PowerLimits: Encodable {
    private enum Keys: String, CodingKey { case power }

    /// `{"power":[15,35]}`, the `limits` object of the `ready` message (design §5).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode([start, full], forKey: .power)
    }
}
