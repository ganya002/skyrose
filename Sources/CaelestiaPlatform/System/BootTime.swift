import Darwin

public enum BootTime {
    /// `kern.boottime` in seconds.
    public static var current: Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6
    }
}
