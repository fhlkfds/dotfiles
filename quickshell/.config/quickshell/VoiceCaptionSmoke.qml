import Quickshell
import QtQuick
import "voicecaption/VoiceCaptionLogic.js" as VoiceCaptionLogic

// Builds the dictation pill from fake captions, and drives the reducer through
// a scripted run of event lines. No socket: VoiceCaptionState is not loaded.
Scope {
  id: smoke
  property int failures: 0

  function findByName(item, name) {
    if (item.objectName === name) return item
    for (let i = 0; i < item.children.length; ++i) {
      const hit = findByName(item.children[i], name)
      if (hit) return hit
    }
    return null
  }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  function line(seq, phase, committed, tentative, note) {
    return JSON.stringify({ type: "state", v: 1, seq: seq, id: "1.5", phase: phase,
      committed: committed || "", tentative: tentative || "", note: note || "" })
  }

  QtObject {
    id: fake
    property bool visible: false
    property string phase: "idle"
    property string hint: ""
    property real level: 0
  }
  Item { visible: true; VoiceCaptionPill { id: pill; caption: fake } }

  function bars() {
    const meter = findByName(pill, "captionMeter")
    const out = []
    if (meter) for (let i = 0; i < meter.children.length; ++i)
      if (meter.children[i].objectName === "meterBar") out.push(meter.children[i].targetHeight)
    return out
  }

  // Every Text in the pill other than the microphone glyph, joined.
  function words(item) {
    let out = ""
    for (let i = 0; i < item.children.length; ++i) {
      const child = item.children[i]
      if (child.visible && typeof child.text === "string" && child.font.family !== Theme.glyphFamily) out += child.text
      out += words(child)
    }
    return out
  }

  function show(state) {
    const view = VoiceCaptionLogic.display(state)
    fake.visible = view.visible
    fake.phase = view.phase
    fake.hint = view.hint
    fake.level = view.level
  }

  Component.onCompleted: {
    const hint = findByName(pill, "captionHint")
    let state = VoiceCaptionLogic.initialState()
    show(state)
    check("hidden at idle", pill.targetOpacity === 0)

    state = VoiceCaptionLogic.receive(state, line(1, "armed"))
    show(state)
    check("armed shows the pill with no text", pill.targetOpacity > 0 && words(pill) === "" && !hint.visible)
    const bare = pill.implicitWidth

    state = VoiceCaptionLogic.receive(state, line(2, "listening", "and then we can", "ship"))
    show(state)
    check("spoken words never show in the pill", words(pill) === "" && !hint.visible)
    check("words do not widen the pill", pill.implicitWidth === bare)
    check("listening is not dimmed", !pill.dimmed)

    const flat = bars()
    check("the meter has five bars", flat.length === 5)
    check("the meter is flat before any level", flat.every(h => h === flat[0]))
    const level = v => JSON.stringify({ type: "level", v: 1, id: "1.5", level: v })
    state = VoiceCaptionLogic.receive(state, level(0.85))
    show(state)
    const loud = bars()
    check("loud speech raises the meter, tallest in the middle", loud[2] > flat[2] && loud[2] > loud[0] && loud[0] > flat[0])
    state = VoiceCaptionLogic.receive(state, level(0.3))
    show(state)
    check("room noise leaves the meter flat", bars().every((h, i) => h === flat[i]))
    state = VoiceCaptionLogic.receive(state, level(0.85))

    const before = state
    state = VoiceCaptionLogic.receive(state, "not json")
    state = VoiceCaptionLogic.receive(state, JSON.stringify({ type: "mystery", seq: 99, phase: "idle" }))
    state = VoiceCaptionLogic.receive(state, line(2, "idle"))
    state = VoiceCaptionLogic.receive(state, line(1, "idle"))
    check("junk, unknown types and stale seqs change nothing", state === before)

    state = VoiceCaptionLogic.receive(state, line(4, "typing", "and then we can ship"))
    show(state)
    check("typing dims the pill and still shows no text", pill.dimmed && pill.targetOpacity > 0 && words(pill) === "")
    check("typing flattens the meter", bars().every((h, i) => h === flat[i]))

    state = VoiceCaptionLogic.receive(state, line(5, "listening", "", "", "loading"))
    show(state)
    check("the loading note shows its hint", hint.visible && words(pill) === "Loading speech model…" && !pill.dimmed)
    check("a hint widens the pill and fits inside it",
      pill.implicitWidth > bare && hint.x + hint.implicitWidth <= pill.implicitWidth - Theme.gapL + 0.5)
    state = VoiceCaptionLogic.receive(state, line(6, "listening", "", "", "no-audio"))
    show(state)
    check("the no-audio note shows its hint", words(pill) === "No microphone audio")
    state = VoiceCaptionLogic.receive(state, line(7, "listening", "said <b> & more", "", "engine-failed"))
    show(state)
    check("the engine-failed note shows its hint and nothing else", words(pill) === "Live captions unavailable")

    state = VoiceCaptionLogic.receive(state, line(8, "idle"))
    show(state)
    check("idle fades the pill out", pill.targetOpacity === 0 && pill.implicitWidth === bare)

    state = VoiceCaptionLogic.receive(state, line(9, "listening"))
    state = VoiceCaptionLogic.disconnected(state)
    show(state)
    check("a dropped connection hides the pill", pill.targetOpacity === 0)
    state = VoiceCaptionLogic.receive(state, line(1, "armed"))
    check("seq restarts after a reconnect", state.phase === "armed")

    console.log("voice caption smoke done: " + smoke.failures + " failures")
    Qt.exit(smoke.failures === 0 ? 0 : 1)
  }
}
