import Quickshell
import QtQuick
import "voicecaption/VoiceCaptionLogic.js" as VoiceCaptionLogic

// Builds the caption pill from fake captions, and drives the reducer through a
// scripted run of event lines. No socket: VoiceCaptionState is not loaded.
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

  function caption(state) {
    return VoiceCaptionLogic.display(state, 60)
  }

  function line(seq, phase, committed, tentative, note) {
    return JSON.stringify({ type: "state", v: 1, seq: seq, id: "1.5", phase: phase,
      committed: committed || "", tentative: tentative || "", note: note || "" })
  }

  QtObject {
    id: fake
    property bool visible: false
    property string phase: "idle"
    property string settled: ""
    property string pending: ""
    property string hint: ""
  }
  Item { visible: true; VoiceCaptionPill { id: pill; caption: fake } }

  function show(view) {
    fake.visible = view.visible
    fake.phase = view.phase
    fake.settled = view.settled
    fake.pending = view.pending
    fake.hint = view.hint
  }

  Component.onCompleted: {
    let state = VoiceCaptionLogic.initialState()
    show(caption(state))
    check("hidden at idle", pill.targetOpacity === 0 && pill.markup === "")

    state = VoiceCaptionLogic.receive(state, line(1, "armed"))
    show(caption(state))
    check("armed shows the placeholder", pill.targetOpacity > 0 && pill.markup.indexOf("Listening…") >= 0)

    state = VoiceCaptionLogic.receive(state, line(2, "listening", "and then we can", "ship"))
    show(caption(state))
    check("listening shows the settled text", pill.markup.indexOf("and then we can") >= 0 && pill.markup.indexOf("ship") >= 0)
    check("the placeholder is gone once words arrive", pill.markup.indexOf("Listening…") < 0)
    check("settled text uses the bright colour", pill.markup.indexOf(pill.hex(Theme.foregroundBright)) >= 0)
    check("pending text uses the muted colour", pill.markup.indexOf(pill.hex(Theme.textMuted)) >= 0)
    check("listening is not dimmed", !pill.dimmed)

    const before = state
    state = VoiceCaptionLogic.receive(state, "not json")
    state = VoiceCaptionLogic.receive(state, JSON.stringify({ type: "mystery", seq: 99, phase: "idle" }))
    state = VoiceCaptionLogic.receive(state, line(2, "idle"))
    state = VoiceCaptionLogic.receive(state, line(1, "idle"))
    check("junk, unknown types and stale seqs change nothing", state === before)

    const long = "the quick brown fox jumps over the lazy dog while the rest of the sentence keeps growing"
    state = VoiceCaptionLogic.receive(state, line(3, "listening", long))
    show(caption(state))
    check("long text keeps the newest words", fake.settled.endsWith("keeps growing"))
    check("long text elides the head", fake.settled.startsWith("…") && fake.settled.indexOf("quick") < 0)

    // Layout, not just markup: a full 150-character tail must still show its
    // last words inside the two-line window.
    fake.settled = "…" + "word ".repeat(28) + "newest"
    const win = findByName(pill, "captionWindow"), words = findByName(pill, "captionWords")
    check("the caption window is at most two lines", win !== null && words !== null && words.lineCount > 2 && win.height < words.height)
    check("the newest line is inside the window", win !== null && words !== null && Math.abs(words.y + words.height - win.height) < 1)
    show(caption(state))

    state = VoiceCaptionLogic.receive(state, line(4, "typing", long))
    show(caption(state))
    check("typing keeps the text and dims it", pill.dimmed && pill.markup.indexOf("growing") >= 0 && pill.targetOpacity > 0)

    state = VoiceCaptionLogic.receive(state, line(5, "listening", "", "", "loading"))
    show(caption(state))
    check("the loading note shows its hint", pill.markup.indexOf("Loading speech model…") >= 0 && !pill.dimmed)
    state = VoiceCaptionLogic.receive(state, line(6, "listening", "", "", "no-audio"))
    show(caption(state))
    check("the no-audio note shows its hint", pill.markup.indexOf("No microphone audio") >= 0)
    state = VoiceCaptionLogic.receive(state, line(7, "listening", "", "", "engine-failed"))
    show(caption(state))
    check("the engine-failed note shows its hint", pill.markup.indexOf("Live captions unavailable") >= 0)

    state = VoiceCaptionLogic.receive(state, line(8, "idle"))
    show(caption(state))
    check("idle fades the pill out", pill.targetOpacity === 0)

    state = VoiceCaptionLogic.receive(state, line(9, "listening", "hi <b> & bye"))
    show(caption(state))
    check("markup characters in speech are escaped", pill.markup.indexOf("&lt;b>") >= 0 && pill.markup.indexOf("&amp;") >= 0)

    state = VoiceCaptionLogic.disconnected(state)
    show(caption(state))
    check("a dropped connection hides the pill", pill.targetOpacity === 0)
    state = VoiceCaptionLogic.receive(state, line(1, "armed"))
    check("seq restarts after a reconnect", state.phase === "armed")

    console.log("voice caption smoke done: " + smoke.failures + " failures")
    Qt.exit(smoke.failures === 0 ? 0 : 1)
  }
}
