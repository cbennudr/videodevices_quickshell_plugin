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
      for (var j = 0; j < devices[i].nodes.length; j++) {
        var node = devices[i].nodes[j]
        lines.push("  " + node.path)

        if (node.formats.length === 0) {
          lines.push("    No formats reported")
          continue
        }

        for (var k = 0; k < node.formats.length; k++) {
          var format = node.formats[k]
          lines.push("    " + format.name)
          for (var sizeIndex = 0; sizeIndex < format.sizes.length; sizeIndex++) {
            var size = format.sizes[sizeIndex]
            var detail = size.intervals.length > 0
              ? size.name + " — " + size.intervals.join(", ")
              : size.name
            lines.push("      " + detail)
          }
        }
      }
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
    - The shell path suffix expression leaves a node name such as video0.
    - printf writes a marker containing the camera name and its /dev/videoX path.
    - v4l2-ctl prints the formats, resolutions, and frame intervals for that node.
    */
    command: ["sh", "-c",
      "for device in /sys/class/video4linux/video*; do " +
      "[ -r \"$device/name\" ] && IFS= read -r name < \"$device/name\" && " +
      "printf '@@DEVICE@@\\t%s\\t/dev/%s\\n' \"$name\" \"${device##*/}\" && " +
      "timeout 2s v4l2-ctl --device \"/dev/${device##*/}\" --list-formats-ext 2>/dev/null; " +
      "done"
    ]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var groupedDevices = []
        var lines = text.trim().split("\n")
        var currentNode = null
        var currentFormat = null
        var currentSize = null

        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]

          if (line.indexOf("@@DEVICE@@\t") === 0) {
            var fields = line.split("\t")
            if (fields.length < 3) continue

            var cameraName = fields[1].trim()
            var nodePath = fields[2].trim()
            var camera = null
            for (var cameraIndex = 0; cameraIndex < groupedDevices.length; cameraIndex++) {
              if (groupedDevices[cameraIndex].name === cameraName) {
                camera = groupedDevices[cameraIndex]
                break
              }
            }

            if (camera === null) {
              camera = { name: cameraName, nodes: [] }
              groupedDevices.push(camera)
            }

            currentNode = { path: nodePath, formats: [] }
            camera.nodes.push(currentNode)
            currentFormat = null
            currentSize = null
            continue
          }

          if (currentNode === null) continue

          var formatMatch = line.match(/^\s*\[\d+\]:\s*'([^']+)'\s*(.*)$/)
          if (formatMatch !== null) {
            var description = formatMatch[2].trim()
            var displayName = formatMatch[1]
              + (description === "" ? "" : " " + description)
            currentFormat = { name: displayName, sizes: [] }
            currentNode.formats.push(currentFormat)
            currentSize = null
            continue
          }

          if (currentFormat === null) continue

          var sizeMatch = line.match(/^\s*Size:\s*(?:Discrete|Stepwise|Continuous)\s+(.+)$/)
          if (sizeMatch !== null) {
            var sizeName = sizeMatch[1].trim()
            currentSize = null
            for (var sizeIndex = 0; sizeIndex < currentFormat.sizes.length; sizeIndex++) {
              if (currentFormat.sizes[sizeIndex].name === sizeName) {
                currentSize = currentFormat.sizes[sizeIndex]
                break
              }
            }

            if (currentSize === null) {
              currentSize = { name: sizeName, intervals: [] }
              currentFormat.sizes.push(currentSize)
            }
            continue
          }

          var intervalMatch = line.match(/^\s*Interval:\s*(?:Discrete|Stepwise|Continuous)\s+(.+)$/)
          if (intervalMatch !== null && currentSize !== null) {
            var intervalDescription = intervalMatch[1].trim()
            var fpsMatch = intervalDescription.match(/\(([0-9.]+)\s+fps\)/)
            var intervalName = fpsMatch !== null
              ? Number(fpsMatch[1]).toString() + " fps"
              : intervalDescription
            if (currentSize.intervals.indexOf(intervalName) < 0)
              currentSize.intervals.push(intervalName)
          }
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
