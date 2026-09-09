import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "connor.videodevices"

  property var deviceNames: []

  readonly property string tooltip: {
    if (deviceNames.length === 0) return "No video devices available"
    return "Video devices\n" + deviceNames.join("\n")
  }

  function refresh() {
    if (!deviceProcess.running) deviceProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: deviceProcess
    command: ["sh", "-c",
      "for device in /sys/class/video4linux/video*; do " +
      "[ -r \"$device/name\" ] && IFS= read -r name < \"$device/name\" && printf '%s\\n' \"$name\"; " +
      "done"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var names = []
        var seen = ({})
        var lines = text.trim().split("\n")

        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name !== "" && !seen[name]) {
            seen[name] = true
            names.push(name)
          }
        }

        root.deviceNames = names
      }
    }
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: root.tooltip
  }
}
