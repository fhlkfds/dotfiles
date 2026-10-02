import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Window

// Headless harness for the desktop now-playing card. Stand-in players replace
// MPRIS, so it never reads or drives the real Spotify session.
//
// With NOW_PLAYING_SHOT set to a directory it also renders one PNG per entry
// in NOW_PLAYING_SCREENS ("name:WxH,name:WxH") over NOW_PLAYING_WALLPAPER, for
// previews. Rendering is offscreen; nothing is drawn on a live desktop.
Scope {
  id: smoke
  property int failures: 0

  readonly property string shotDir: Quickshell.env("NOW_PLAYING_SHOT") || ""
  readonly property string wallpaper: Quickshell.env("NOW_PLAYING_WALLPAPER") || ""
  readonly property var screenSpecs: (Quickshell.env("NOW_PLAYING_SCREENS") || "fixture:1920x1080")
    .split(",").map(function (entry) {
      const parts = entry.split(":")
      const dims = parts[1].split("x")
      return { name: parts[0], width: Number(dims[0]), height: Number(dims[1]) }
    })

  QtObject {
    id: browser
    property string dbusName: "chromium.instance2303"
    property string identity: "Chromium"
    property string trackTitle: "Some video"
    property string trackArtist: "A channel"
    property string trackArtUrl: ""
    property int playbackState: MprisPlaybackState.Playing
    property bool lengthSupported: true
    property real length: 600
    property bool positionSupported: true
    property real position: 30
    property bool canGoNext: false
    property bool canGoPrevious: false
    property bool canTogglePlaying: true
  }

  QtObject {
    id: spotify
    property string dbusName: "spotify"
    property string identity: "Spotify"
    property string trackTitle: Quickshell.env("NOW_PLAYING_TITLE") || "Shared Shelter"
    property string trackArtist: Quickshell.env("NOW_PLAYING_ARTIST") || "Biba Dupont"
    property string trackArtUrl: Quickshell.env("NOW_PLAYING_ART") || ""
    property int playbackState: MprisPlaybackState.Playing
    property bool lengthSupported: true
    property real length: 161
    property bool positionSupported: true
    property real position: 55
    property bool canGoNext: true
    property bool canGoPrevious: true
    property bool canTogglePlaying: true
    property int nextCalls: 0
    property int previousCalls: 0
    property int toggleCalls: 0
    function next() { nextCalls++ }
    function previous() { previousCalls++ }
    function togglePlaying() { toggleCalls++ }
  }

  // The card needs a visible parent, or Qt reports it as invisible and the
  // spin assertions would depend on scene start-up order.
  Item { id: host; visible: true; DesktopNowPlayingCard { id: card } }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  Component.onCompleted: {
    const state = SpotifyState

    state.playersOverride = []
    check("no players means no card", state.player === null && !state.hasTrack)

    state.playersOverride = [browser]
    check("a browser player alone is ignored", state.player === null && !state.hasTrack)

    state.playersOverride = [browser, spotify]
    check("spotify is picked over a playing browser", state.player === spotify)
    check("a playing spotify track shows the card", state.hasTrack && state.isPlaying)
    check("title is projected", state.trackTitle === spotify.trackTitle)
    check("progress is position over length", Math.abs(state.progress - 55 / 161) < 1e-6)

    check("card reads SpotifyState by default", card.media === state)
    check("card shows elapsed over total time", card.timeText === "0:55 / 2:41")
    check("card has a real size", card.implicitWidth > card.discSize && card.implicitHeight === card.discSize)
    check("record spins while playing", card.spinning)
    card.spinAllowed = false
    check("record stops when covered by windows", !card.spinning)
    card.spinAllowed = true

    state.next(); state.previous(); state.togglePlaying()
    check("controls reach the spotify player",
      spotify.nextCalls === 1 && spotify.previousCalls === 1 && spotify.toggleCalls === 1)

    spotify.playbackState = MprisPlaybackState.Paused
    check("paused keeps the card up", state.hasTrack && !state.isPlaying)
    check("record holds still while paused", !card.spinning)

    spotify.playbackState = MprisPlaybackState.Stopped
    check("stopped hides the card", !state.hasTrack)

    spotify.playbackState = MprisPlaybackState.Playing
    spotify.trackTitle = ""
    check("an empty title hides the card", !state.hasTrack)
    spotify.trackTitle = Quickshell.env("NOW_PLAYING_TITLE") || "Shared Shelter"

    spotify.canGoNext = false
    state.next()
    check("next is not sent when spotify cannot go next", spotify.nextCalls === 1)
    spotify.canGoNext = true

    spotify.dbusName = "org.mpris.MediaPlayer2.ncspot"
    spotify.identity = "spotify"
    check("identity alone is enough to match spotify", state.player === spotify)
    spotify.dbusName = "spotify"

    if (smoke.failures === 0)
      console.log("ok: Desktop now-playing card")

    if (smoke.shotDir === "")
      quitTimer.start()
  }

  // --- optional preview renders ----------------------------------------------

  property int shotsPending: shotDir === "" ? 0 : screenSpecs.length

  Variants {
    model: smoke.shotDir === "" ? [] : smoke.screenSpecs

    Window {
      id: shotWindow
      required property var modelData
      width: modelData.width
      height: modelData.height
      visible: true
      color: "black"

      Image {
        id: wall
        anchors.fill: parent
        source: smoke.wallpaper === "" ? "" : "file://" + smoke.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
      }

      DesktopNowPlayingCard {
        id: shotCard
        x: Theme.fs(56) + Theme.fs(4)
        y: shotWindow.height - Theme.fs(56) - Theme.fs(4) - height
        width: implicitWidth
        height: implicitHeight
        spinAllowed: false
      }

      Timer {
        // Long enough for the async album art and the shadow layer to settle.
        interval: 1500
        running: true
        onTriggered: shotWindow.contentItem.grabToImage(function (result) {
          const path = smoke.shotDir + "/now-playing-" + shotWindow.modelData.name + ".png"
          console.log(result.saveToFile(path) ? "shot " + path : "FAIL shot " + path)
          if (--smoke.shotsPending === 0)
            quitTimer.start()
        })
      }
    }
  }

  Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
}
