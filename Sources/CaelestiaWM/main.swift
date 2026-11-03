import CaelestiaWMKit

// CaelestiaWM: the tiling window manager daemon (see WMDaemon).
MainActor.assumeIsolated {
    WMDaemon().run()
}
