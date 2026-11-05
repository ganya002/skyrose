import CaelestiaWMKit

// SkyRoseWM: the tiling window manager daemon (see WMDaemon).
// `--permissions-probe <file>` only reports this app's permissions and exits (SkyRose Settings).
PermissionProbe.runIfRequested()
MainActor.assumeIsolated {
    WMDaemon().run()
}
