
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
rsync -av --exclude '.git' $SCRIPT_DIR/ /home/connor/.config/omarchy/plugins/connor.videodevices

omarchy-shell shell rescanPlugins
omarchy plugin enable connor.videodevices
omarchy restart shell