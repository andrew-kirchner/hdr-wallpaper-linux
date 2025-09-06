# HDRpaper
A tool for displaying static and live wallpapers in HDR

---
## [Gitlab](https://gitlab.com/andrewkirchner/HDRpaper)
by Andrew Kirchner, [License](https://gitlab.com/andrewkirchner/HDRpaper-linux/-/blob/bb045731997204e52009c3b6c91d5f5221f05613/LICENSE#L13)

*[andrewcontact@tuta.com](mailto:andrewcontact@tuta.com)*
## Overview
&nbsp;&nbsp;&nbsp;&nbsp;A simple yet full-featured bash script to display HDR content
as an unobtrusive desktop wallpaper using mpv. You can play a mix of SDR and HDR
images and videos from an arbitrary list of files and directories, for which the script
can automatically adapt to sort images and videos and display them for equal amounts of time.
You can also choose by default to upscale SDR images and/or videos to HDR, producing great results on
SDR images while tastefully maintaining color accuracy. It similarly helps videos, though
may look a bit more unnatural; HDR media is completely unchanged and should
display well without any extra configuration so long as HDR is enabled in your settings app.
All of these are configurable with command line options, subcommands to change content as it plays,
as well as the mpv options themselves which you can just edit directly or through your personal configuration files.

&nbsp;&nbsp;&nbsp;&nbsp;It is designed specifically for KDE Plasma,
automatically adding KDE window rules for only the wallpapers mpv instances to
set them into the background and leave panel (taskbar) behavior unchanged.
The script will otherwise work identically on any modern Wayland compositor,
so long as mpv is up to date as is HDR support.

&nbsp;&nbsp;&nbsp;&nbsp;The script is not too long, so I encourage you to look over it, if only to see
some presets and command line options. In Plasma under Autostart you add the script
to startup with any of these! The simple command `hdr --only-images` can show you
your pictures in the background without using too much power or battery life.
## Installation
&nbsp;&nbsp;&nbsp;&nbsp;You can just clone this project with the code button, drop all the files in a directory, and run the bash script to immediately
start displaying wallpapers! The first time you run the script it won't require any configuration, and it will drop
a symbolic link in ~/.local/bin so you can run the script anytime with the command `hdr` in your terminal.
You can also start it quickly in Krunner with `Alt+space`; before you do that, though, you should just run it in
a terminal emulator like Konsole just to get your configuration and any output/errors down.
*Make sure to do `hdr --help` in the terminal if--or before--you are lost!* You can do `hdr q` or Q or quit or QUIT to get out any time.
## Command Line options
look here later just do hdr HELP though