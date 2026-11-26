/// The port the dashboard listens on, as typed into the menu's "Port…" dialog (design §8 "Menü çubuğu").
public enum PortChoice {
    /// Below 1024 needs root; 4747 is the default.
    public static let range: ClosedRange<Int> = 1024...65535

    /// The port in `text` (spaces around it are fine), or nil when it is not a whole number in `range`.
    public static func parse(_ text: String) -> UInt16? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, digits.count <= 5, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(digits), range.contains(number)
        else { return nil }
        return UInt16(number)
    }
}
