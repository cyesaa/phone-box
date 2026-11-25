import Darwin

/// `mach_host_self()` hands out a new send right on every call; ask once instead of twice a second.
enum HostPort {
    static let host: host_t = mach_host_self()
}
