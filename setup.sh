#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
config_home="${HOME:?HOME is not set}/.config"
plugin_id=connor.videodevices
plugin_dir="$config_home/omarchy/plugins/$plugin_id"

mkdir -p "$plugin_dir"
rsync -av --exclude '.git/' "$script_dir/" "$plugin_dir/"

omarchy-shell shell rescanPlugins
omarchy plugin enable "$plugin_id"
omarchy restart shell
