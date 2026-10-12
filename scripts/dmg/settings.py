# dmgbuild settings for GitIsle.dmg: the app and an Applications shortcut over a branded
# background, as in other Mac apps' installers. package-release.sh passes `app`,
# `background` (a Retina TIFF) and `icon` with -D.
import os.path

app = defines["app"]  # noqa: F821 (provided by dmgbuild)
format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon")  # noqa: F821
background = defines["background"]  # noqa: F821

# The window's height includes its title bar (32 pt), so it is 32 pt taller than the
# 660 x 420 background; icons sit on the arrow's ends.
window_rect = ((200, 140), (660, 452))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 205),
    "Applications": (490, 205),
    # Hidden files only show when Finder shows all files. Left where Finder puts them, they
    # land below the icons and scroll the window; keep them beside the visible area instead.
    ".background.tiff": (900, 205),
    ".VolumeIcon.icns": (1000, 205),
}
