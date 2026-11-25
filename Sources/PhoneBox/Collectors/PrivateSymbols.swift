import Foundation

/// Looks up a function in a private library at run time. If macOS removes it, the collector that needs it returns
/// nil and the dashboard shows "—" for that metric (design §13, "Resmi olmayan API'ler").
enum PrivateSymbols {
    static func function<T>(_ library: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
        guard let library, let pointer = dlsym(library, name) else {
            Log.app.notice("Private symbol \(name, privacy: .public) is not available")
            return nil
        }
        return unsafeBitCast(pointer, to: type)
    }

    static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    static let ioReport = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)
    static let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW)
}
