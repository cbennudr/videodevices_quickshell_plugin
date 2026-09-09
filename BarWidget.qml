import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "connor.videodevices"

  property var devices: []

  readonly property string tooltip: {
    if (devices.length === 0) return "No video devices available"

    var lines = ["Video devices"]
    for (var i = 0; i < devices.length; i++) {
      lines.push(devices[i].name)
      for (var j = 0; j < devices[i].nodes.length; j++)
        lines.push("  " + devices[i].nodes[j])
    }
    return lines.join("\n")
  }

  function refresh() {
    if (!deviceProcess.running) deviceProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: deviceProcess
    /*
    - sh -c asks the shell to execute the following string as a command.
    - /sys/class/video4linux/video* matches Linux video-device directories such as video0 and video1.
    - for device in ... processes each directory individually.
    - [ -r "$device/name" ] checks whether its name file exists and is readable.
    - IFS= read -r name < "$device/name" reads the device name without interpreting backslashes or trimming whitespace.
    - ${device##/} removes the sysfs path, leaving a node name such as video0.
    - printf writes the camera name and its /dev/videoX path, separated by a tab.
    */
    command: ["sh", "-c",
      "for device in /sys/class/video4linux/video*; do " +
      "[ -r \"$device/name\" ] && IFS= read -r name < \"$device/name\" && " +
      "printf '%s\\t/dev/%s\\n' \"$name\" \"${device##*/}\"; " +
      "done"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var groupedDevices = []
        var lines = text.trim().split("\n")

        for (var i = 0; i < lines.length; i++) {
          var separator = lines[i].indexOf("\t")
          if (separator < 0) continue

          var name = lines[i].slice(0, separator).trim()
          var node = lines[i].slice(separator + 1).trim()
          if (name === "" || node === "") continue

          var group = null
          for (var j = 0; j < groupedDevices.length; j++) {
            if (groupedDevices[j].name === name) {
              group = groupedDevices[j]
              break
            }
          }

          if (group === null) {
            group = { name: name, nodes: [] }
            groupedDevices.push(group)
          }
          group.nodes.push(node)
        }

        root.devices = groupedDevices
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
