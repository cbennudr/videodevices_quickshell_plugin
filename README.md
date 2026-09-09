# Video Devices

An Omarchy bar plugin that shows a video-camera icon in the right section of
the bar. Hover over the icon to see each video device's formats, resolutions,
and frame rates. Click a resolution/frame-rate row to preview that exact
device, format, resolution, and frame rate with GStreamer. The list refreshes
every five seconds.

## Requirements

The plugin uses `v4l2-ctl` for device capabilities and GStreamer for previews:

```bash
omarchy pkg add v4l-utils gstreamer gst-plugins-base gst-plugins-good
```

## Install from this checkout

Copy the plugin to the Omarchy plugins directory:

```bash
# cp -r . /home/connor/.config/omarchy/plugins/connor.videodevices
rsync -av --exclude '.git' . /home/connor/.config/omarchy/plugins/connor.videodevices
```

Ask the running shell to discover it, then enable it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable connor.videodevices
```

The enable command adds the widget to `~/.config/omarchy/shell.json`. Its
manifest requests the right side of the bar by default.

Changes under `~/.config/omarchy/plugins/` normally hot-reload. If needed, restart the shell with:

```bash
omarchy restart shell
```

Verify discovery and inspect loader errors with:

```bash
omarchy-shell shell listPlugins
journalctl --user -u omarchy-shell -n 100 --no-pager
```
