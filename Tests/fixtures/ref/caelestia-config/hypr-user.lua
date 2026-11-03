-- Gabby's user config (ported from Noctalia setup)
hl.monitor({ output = "DP-2", mode = "5120x1440@119.97", position = "0x0", scale = "1" })

hl.config({ input = { kb_layout = "no" } })

hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- removed: GTK_THEME forced Adwaita and blocked adw-gtk3 + Caelestia colours
-- hl.env("GTK_THEME", "Adwaita:dark")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

hl.on("hyprland.start", function ()
  hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
  hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)

-- Riko's springy motion
hl.curve("riko", { type = "spring", mass = 1, stiffness = 180, damping = 20 })
hl.curve("snappy", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.05} } })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 3.2, spring = "riko", style = "popin 80%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.2, spring = "riko" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 3.2, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 3.2, bezier = "snappy", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 3.2, bezier = "snappy", style = "slide" })

hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
