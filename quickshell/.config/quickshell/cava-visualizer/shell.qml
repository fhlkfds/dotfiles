//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io

// Standalone cava visualizer: a transparent background-layer panel per
// monitor drawing 64 bottom-up audio bars. This is a separate named
// Quickshell config (launch with `quickshell -c cava-visualizer` or
// `qs -c cava-visualizer`) so it never interferes with the bare shell.qml
// bar instance. It ships its own cava config (cava.conf in this folder)
// and does not touch ~/.config/cava/config or cava/bar.conf.

ShellRoot {
    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: panel

                required property var modelData
                readonly property int barCount: 64
                // Levels normalised to 0..1, one entry per bar.
                property var levels: {
                    const out = []
                    for (let i = 0; i < barCount; i++)
                        out.push(0)
                    return out
                }
                // True once cava has produced at least one valid frame.
                // When false (cava missing or not yet producing frames)
                // only the baseline line is drawn.
                property bool available: false
                readonly property color accentColor: "#89b4fa"
                readonly property real accentOpacity: 0.78
                // Throttle repaints to ~30fps to match the cava framerate.
                readonly property int frameIntervalMs: 33
                property bool paintPending: false

                screen: modelData

                WlrLayershell.layer: WlrLayershell.Background
                anchors {
                    bottom: true
                    left: true
                    right: true
                }
                exclusiveZone: -1
                exclusionMode: ExclusionMode.Ignore
                keyboardFocus: WlrKeyboardFocus.None
                color: "transparent"
                implicitHeight: 120

                Process {
                    id: cavaProc

                    command: [
                        "cava",
                        "-p",
                        Quickshell.env("HOME") + "/.config/quickshell/cava-visualizer/cava.conf"
                    ]
                    running: true
                    stdout: SplitParser {
                        // One frame per line: 64 space-separated ints 0..100.
                        onRead: line => panel.handleLine(line)
                    }
                    stderr: StdioCollector {}
                    // If cava is missing or dies, `available` stays/becomes
                    // false and only the baseline line is shown.
                    onExited: {
                        panel.available = false
                    }
                }

                function handleLine(line) {
                    const parts = String(line).trim().split(/\s+/).filter(p => p !== "")
                    if (parts.length === 0)
                        return
                    const out = []
                    for (let i = 0; i < barCount; i++) {
                        const n = Number(parts[i] || 0)
                        out.push(Math.min(1, Math.max(0, (isFinite(n) ? n : 0) / 100)))
                    }
                    levels = out
                    available = true
                }

                Timer {
                    id: frameTimer

                    interval: panel.frameIntervalMs
                    repeat: true
                    running: panel.available
                    onTriggered: {
                        if (!panel.paintPending) {
                            panel.paintPending = true
                            canvas.requestPaint()
                        }
                    }
                }

                Canvas {
                    id: canvas

                    anchors.fill: parent
                    // Monitor width is read at runtime from the panel size,
                    // which tracks the screen; bars are recomputed per paint.
                    onPaint: {
                        const ctx = getContext("2d")
                        const w = width
                        const h = height
                        ctx.clearRect(0, 0, w, h)

                        // Flat baseline near the bottom; always visible.
                        const baseline = h - 1.5
                        ctx.strokeStyle = Qt.rgba(
                            panel.accentColor.r,
                            panel.accentColor.g,
                            panel.accentColor.b,
                            panel.accentOpacity)
                        ctx.lineWidth = 1
                        ctx.beginPath()
                        ctx.moveTo(0, baseline)
                        ctx.lineTo(w, baseline)
                        ctx.stroke()

                        if (!panel.available)
                            return

                        // 64 evenly spaced bars across the full width.
                        const n = panel.barCount
                        const slot = w / n
                        const barWidth = Math.max(1, slot * 0.7)
                        const maxBarHeight = h - 4
                        ctx.fillStyle = Qt.rgba(
                            panel.accentColor.r,
                            panel.accentColor.g,
                            panel.accentColor.b,
                            panel.accentOpacity)
                        for (let i = 0; i < n; i++) {
                            const level = panel.levels[i] || 0
                            if (level <= 0)
                                continue
                            const barHeight = Math.max(1, level * maxBarHeight)
                            const x = i * slot + (slot - barWidth) / 2
                            // Bottom-up from the baseline.
                            ctx.fillRect(x, baseline - barHeight, barWidth, barHeight)
                        }
                        panel.paintPending = false
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                }
            }
        }
    }
}
