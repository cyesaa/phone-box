import Foundation

/// Strict readers for values from `JSONSerialization`, which turns `true`, `1` and `1.0` alike into `NSNumber`.
enum JSONValue {
    /// Largest integer a JavaScript number holds exactly (`Number.MAX_SAFE_INTEGER`).
    static let maxSafeInteger = 9_007_199_254_740_991

    /// Only `true` or `false`, not `1` or `0`.
    static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// A whole number written without a fraction or exponent (`7`, not `7.0` or `true`), within ±2⁵³−1.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number)
        else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) <= Double(maxSafeInteger) else { return nil }
        return number.intValue
    }

    /// Any finite number, but not a boolean.
    static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
}
