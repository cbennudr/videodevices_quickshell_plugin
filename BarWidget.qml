import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "connor.videodevices"

  property var devices: []
  property bool popupOpen: false

  function syncPopup() {
    if (button.tooltipHovered || infoPopup.containsMouse) {
      closePopupTimer.stop()
      popupOpen = true
    } else {
      closePopupTimer.restart()
    }
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

  Timer {
    id: closePopupTimer
    interval: 150
    onTriggered: {
      if (!button.tooltipHovered && !infoPopup.containsMouse)
        root.popupOpen = false
    }
  }

  QtObject {
    id: popupOwner
    function close() { root.popupOpen = false }
  }

  PopupCard {
    id: infoPopup
    anchorItem: button
    bar: root.bar
    owner: popupOwner
    triggerMode: "hover"
    open: root.popupOpen
    contentWidth: fittedContentWidth(Style.space(520))
    contentHeight: fittedContentHeight(contentColumn.implicitHeight)

    onContainsMouseChanged: root.syncPopup()

    Column {
      id: contentColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        visible: root.devices.length === 0
        width: parent.width
        text: "No video devices available"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
      }

      Repeater {
        model: root.devices

        delegate: Column {
          required property var modelData
          width: contentColumn.width
          spacing: Style.space(5)

          Text {
            width: parent.width
            text: modelData.name
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }

          Repeater {
            model: modelData.nodes

            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(3)

              Text {
                width: parent.width
                text: modelData.path
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignLeft
              }

              Text {
                visible: modelData.formats.length === 0
                x: Style.space(16)
                width: parent.width - x
                text: "No formats reported"
                color: Color.foreground
                opacity: 0.75
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignLeft
              }

              Repeater {
                model: modelData.formats

                delegate: Column {
                  required property var modelData
                  x: Style.space(16)
                  width: parent.width - x
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: modelData.name
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.Wrap
                  }

                  Repeater {
                    model: modelData.sizes

                    delegate: Text {
                      required property var modelData
                      readonly property string detail: modelData.intervals.length > 0
                        ? modelData.name + " — " + modelData.intervals.join(", ")
                        : modelData.name

                      x: Style.space(16)
                      width: parent.width - x
                      text: detail
                      color: Color.foreground
                      opacity: 0.85
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      horizontalAlignment: Text.AlignLeft
                      wrapMode: Text.Wrap
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: ""
    onTooltipHoveredChanged: root.syncPopup()
  }
}
