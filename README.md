# Activate Linux Quickshell Plugin


Copy to omarchy plugins directory
```bash
cp -r . /home/connor/.config/omarchy/plugins/connor.videodevices
```

Ask the running shell to discover it, then enable it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable connor.videodevices
```

The enable command adds this entry to the top-level `plugins` array in
`~/.config/omarchy/shell.json`:

```json
{ "id": "connor.videodevices" }
```

Changes under `~/.config/omarchy/plugins/` normally hot-reload. If needed, restart the shell with:

```bash
omarchy restart shell
```

Verify discovery and inspect loader errors with:

```bash
omarchy-shell shell listPlugins
journalctl --user -u omarchy-shell -n 100 --no-pager
```
