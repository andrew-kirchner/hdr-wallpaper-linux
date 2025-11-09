# HDRpaper
*A tool for displaying static and live wallpapers in HDR*

[Gitlab](https://gitlab.com/andrewkirchner/HDRpaper)
by Andrew Kirchner, [License](https://gitlab.com/andrewkirchner/HDRpaper-linux/-/blob/bb045731997204e52009c3b6c91d5f5221f05613/LICENSE#L13)

*[andrewcontact@tuta.com](mailto:andrewcontact@tuta.com)*

---
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

---
## Installation
&nbsp;&nbsp;&nbsp;&nbsp;You can just clone this project with the code button, drop all the files in a directory, and run the bash script to immediately
start displaying wallpapers! The first time you run the script it won't require any configuration, and it will drop
a symbolic link in ~/.local/bin so you can run the script anytime with the command `hdr` in your terminal.
You can also start it quickly in Krunner with `Alt+space`; before you do that, though, you should just run it in
a terminal emulator like Konsole just to get your configuration and any output/errors down.
*Make sure to do `hdr --help` in the terminal if--or before--you are lost!* You can do `hdr q` or Q or quit or QUIT to get out any time.
### mpv.conf
The `mpv.conf` file included will be used automatically so long as they all live in the project directory, and **your own config will also be used** so long as you do not pass `--no-config` to the script. If something is broken, check `--no-config`, then the script! Then email me
### Plasma 6.4 HDR Calibration
&nbsp;&nbsp;&nbsp;&nbsp;This tool is useful to know what your monitor is actually capable of. It should be under the HDR toggle in system settings, and you can figure out your monitor's peak brightness with its current settings.
Once you figure out your peak brightness, **you should set it manually as target-peak in mpv.conf**.
The difference is important for color accuracy on HDR media, though for *inverse tone mapping* `target-peak` is important for what brightness range your  picture will be converted to. The **average picture brightness** of your ITM SDR content may appear lower, but this is a normal part of HDR content to make the highlights brighter.
### So Where do I Actually get HDR Wallpapers?
&nbsp;&nbsp;&nbsp;&nbsp;Procuring HDR content is a bit difficult, with videos ironically being easier than pictures; the easiest option is videos, namely demonstration footage like from [4kmedia.org](https://4kmedia.org) with the tags `HDR` and `10 bit`. SDR media is most of what you will find, and still will look very nice with inverse tone mapping; anything from [Unsplash](https://unsplash.com) to [the PIKMIN GARDEN collection](https://www.nintendo.com/jp/character/pikmin/gallery/index.html) should have good results regardless of filetype. Some videos are only available on Youtube or torrenting, the former you should avoid for quality and the latter you should check for legality.

Some cool creators of 4k/8k HDR content beyond Demo Videos include
[Roman De Giuli](https://terracollage.com) and [Eugene Belsky](https://artvision.camera).

---
## Command Line options
```
Usage: wallpaper.sh [subcommand]? or [options] [mediapath1 mediapath2 ...]
Play media file(s) as desktop wallpapers.
==|==========================================================================|==
Subcommands (e.g. git pull, git commit)
These one word subcommands are used to show information or possibly
modify the current instance instead of creating a new one.

    HELP    Display me then exit
    QUIT    Force close mpv and script, throws if not found
    SKIP    End the current media file and play the next one
              as per REPEAT then --sort
    REPEAT  Loop the current media file once once it ends;
              throws if file is set to loop forever
    OSD     Toggle OSD, or more specifically the ability
              for the window to receive pointer events.
              Will also capture exclusively mpv shortcuts!
    AUDIO   Enable audio for the current instance. Audio
              is not just muted but disabled by default!
    ITM     Toggle inverse tone mapping for SDR media.
              Test the differnece for both images and videos!
    DEBUG   Toggle the "Stats for nerds" display showing HDR information!
==|==========================================================================|==
Boolean Flags [ -m --mode ] ?= false
These options are used only on initialization of a new instance.

    -l, --loop      Loop media indefinitely until SKIP is called.
    -t, --toast     Show a short toast of the filename in the background.
    --no-config     Alias for mpv option, do not use personal config.
    --only-images   Ignore videos when looking for media files.
    --only-videos   Ignore images when looking for media files.

Arguments with values [ -k value --key value --key=value ] ?= default
These options require a value and are only passed on a new instance.

    -s, --sort ?= proportional
    Control the order in which any media
    files that are found are played.
      =proportional     Pick media inversely proportional to its respective
                          duration, such that each file would approach being
                          on screen the same amount of time. Images are given
                          the duration of the average of all videos! Falls
                          back to random if no videos are supplied.
      =random           Pick all media in paths with uniform distribution
      =randarg          Pick a random top level mediapath then file each time
      =alphabetical     Play in order based on basename of all media files
      =newest           Play files in order of the date last moved
      =none             Play in whatever order supplied by the find command
    --itm ?= all
    Choose what type of SDR media inverse tone mapping upto HDR is applied to.
      =all             Use bt.2446a for images and videos. Set target-peak!
      =only-images     Use bt.2446a for images only. Videos unchanged
      =only-videos     Use bt.2446a for videos only. Images unchanged
      =none            Disable itm always, displaying SDR in SDR or P3

==|==========================================================================|==
```
