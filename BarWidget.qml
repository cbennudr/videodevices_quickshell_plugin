import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "connor.videodevices"

  property var devices: []
  property bool popupOpen: false
  readonly property var widthSamples: {
    var samples = {
      camera: "",
      device: "No video devices available",
      format: "No formats reported",
      choice: ""
    }

    for (var cameraIndex = 0; cameraIndex < devices.length; cameraIndex++) {
      var camera = devices[cameraIndex]
      if (camera.name.length > samples.camera.length) samples.camera = camera.name

      for (var nodeIndex = 0; nodeIndex < camera.nodes.length; nodeIndex++) {
        var node = camera.nodes[nodeIndex]
        if (node.path.length > samples.device.length) samples.device = node.path

        for (var formatIndex = 0; formatIndex < node.formats.length; formatIndex++) {
          var format = node.formats[formatIndex]
          if (format.name.length > samples.format.length) samples.format = format.name

          for (var sizeIndex = 0; sizeIndex < format.sizes.length; sizeIndex++) {
            var size = format.sizes[sizeIndex]
            if (size.intervals.length === 0 && size.name.length > samples.choice.length)
              samples.choice = size.name

            for (var intervalIndex = 0; intervalIndex < size.intervals.length; intervalIndex++) {
              var choice = size.name + " — " + size.intervals[intervalIndex].name
              if (choice.length > samples.choice.length) samples.choice = choice
            }
          }
        }
      }
    }
    return samples
  }

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

  function fpsFraction(fps) {
    var value = Number(fps)
    if (!isFinite(value) || value <= 0) return ""

    if (Math.abs(value - 23.976) < 0.01) return "24000/1001"
    if (Math.abs(value - 29.97) < 0.01) return "30000/1001"
    if (Math.abs(value - 59.94) < 0.01) return "60000/1001"
    if (Math.abs(value - Math.round(value)) < 0.001)
      return Math.round(value) + "/1"

    var numerator = Math.round(value * 1000)
    var denominator = 1000
    var a = numerator
    var b = denominator
    while (b !== 0) {
      var remainder = a % b
      a = b
      b = remainder
    }
    return (numerator / a) + "/" + (denominator / a)
  }

  function launchFormat(nodePath, formatCode, width, height, fps) {
    var rawFormatNames = {
      "YUYV": "YUY2",
      "YU12": "I420",
      "RGB3": "RGB",
      "BGR3": "BGR",
      "GREY": "GRAY8"
    }
    var caps = ""
    var decoder = ""

    if (formatCode === "MJPG" || formatCode === "JPEG") {
      caps = "image/jpeg"
      decoder = "jpegdec"
    } else if (formatCode === "H264") {
      caps = "video/x-h264"
      decoder = "decodebin"
    } else if (formatCode === "HEVC") {
      caps = "video/x-h265"
      decoder = "decodebin"
    } else {
      var gstFormat = rawFormatNames[formatCode] || formatCode
      caps = "video/x-raw,format=" + gstFormat
    }

    caps += ",width=" + width + ",height=" + height
    var framerate = fpsFraction(fps)
    if (framerate !== "") caps += ",framerate=" + framerate

    var command = ["gst-launch-1.0", "v4l2src", "device=" + nodePath, "!", caps, "!"]
    if (decoder !== "") command.push(decoder, "!")
    command.push("videoconvert", "!", "autovideosink")

    popupOpen = false
    Quickshell.execDetached(command)
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
            var formatCode = formatMatch[1].trim()
            var description = formatMatch[2].trim()
            var displayName = formatCode
              + (description === "" ? "" : " " + description)
            currentFormat = { code: formatCode, name: displayName, sizes: [] }
            currentNode.formats.push(currentFormat)
            currentSize = null
            continue
          }

          if (currentFormat === null) continue

          var sizeMatch = line.match(/^\s*Size:\s*(?:Discrete|Stepwise|Continuous)\s+(.+)$/)
          if (sizeMatch !== null) {
            var sizeName = sizeMatch[1].trim()
            var dimensions = sizeName.match(/^(\d+)x(\d+)$/)
            currentSize = null
            for (var sizeIndex = 0; sizeIndex < currentFormat.sizes.length; sizeIndex++) {
              if (currentFormat.sizes[sizeIndex].name === sizeName) {
                currentSize = currentFormat.sizes[sizeIndex]
                break
              }
            }

            if (currentSize === null) {
              currentSize = {
                name: sizeName,
                width: dimensions !== null ? Number(dimensions[1]) : 0,
                height: dimensions !== null ? Number(dimensions[2]) : 0,
                intervals: []
              }
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
            var duplicateInterval = false
            for (var intervalIndex = 0; intervalIndex < currentSize.intervals.length; intervalIndex++) {
              if (currentSize.intervals[intervalIndex].name === intervalName) {
                duplicateInterval = true
                break
              }
            }
            if (!duplicateInterval) {
              currentSize.intervals.push({
                name: intervalName,
                fps: fpsMatch !== null ? Number(fpsMatch[1]) : 0
              })
            }
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

  TextMetrics {
    id: cameraMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.heading
    font.bold: true
    text: root.widthSamples.camera
  }

  TextMetrics {
    id: deviceMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.bold: true
    text: root.widthSamples.device
  }

  TextMetrics {
    id: formatMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    text: root.widthSamples.format
  }

  TextMetrics {
    id: choiceMetrics
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    text: root.widthSamples.choice
  }

  PopupCard {
    id: infoPopup
    anchorItem: button
    bar: root.bar
    owner: popupOwner
    triggerMode: "hover"
    open: root.popupOpen
    contentWidth: fittedContentWidth(Math.ceil(Math.max(
      Style.space(220),
      cameraMetrics.width,
      deviceMetrics.width,
      Style.space(16) + formatMetrics.width,
      Style.space(32) + choiceMetrics.width
    ) + padding * 2 + Style.space(8)))
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
              id: nodeColumn
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
                  id: formatColumn
                  required property var modelData
                  readonly property var choices: {
                    var result = []
                    for (var sizeIndex = 0; sizeIndex < modelData.sizes.length; sizeIndex++) {
                      var size = modelData.sizes[sizeIndex]
                      if (size.intervals.length === 0) {
                        result.push({ name: size.name, width: size.width, height: size.height, fps: 0 })
                        continue
                      }

                      for (var intervalIndex = 0; intervalIndex < size.intervals.length; intervalIndex++) {
                        var interval = size.intervals[intervalIndex]
                        result.push({
                          name: size.name + " — " + interval.name,
                          width: size.width,
                          height: size.height,
                          fps: interval.fps
                        })
                      }
                    }
                    return result
                  }
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
                    model: formatColumn.choices

                    delegate: Rectangle {
                      id: choiceButton
                      required property var modelData
                      x: Style.space(16)
                      width: parent.width - x
                      height: choiceLabel.implicitHeight + Style.space(6)
                      color: choiceMouse.containsMouse
                        ? Style.hoverFillFor(root.bar ? root.bar.barForeground : Color.foreground, Color.accent)
                        : "transparent"
                      radius: Style.cornerRadius

                      Text {
                        id: choiceLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Style.space(4)
                        anchors.rightMargin: Style.space(4)
                        text: choiceButton.modelData.name
                        color: choiceMouse.containsMouse ? Color.accent : Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.underline: choiceMouse.containsMouse
                        horizontalAlignment: Text.AlignLeft
                        wrapMode: Text.Wrap
                      }

                      MouseArea {
                        id: choiceMouse
                        anchors.fill: parent
                        enabled: choiceButton.modelData.width > 0 && choiceButton.modelData.height > 0
                        hoverEnabled: enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.launchFormat(
                          nodeColumn.modelData.path,
                          formatColumn.modelData.code,
                          choiceButton.modelData.width,
                          choiceButton.modelData.height,
                          choiceButton.modelData.fps
                        )
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
