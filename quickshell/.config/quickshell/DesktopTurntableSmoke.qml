import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Window

// Headless harness for the desktop Turntable. Stand-in players replace MPRIS,
// so it never reads or drives a real player.
//
// With TURNTABLE_SHOT set to a directory it also renders one PNG per entry in
// TURNTABLE_SCREENS ("name:WxH,name:WxH") over TURNTABLE_WALLPAPER, for
// previews. Rendering is offscreen; nothing is drawn on a live desktop.
Scope {
  id: smoke
  property int failures: 0
  property bool shooting: false

  readonly property string shotDir: Quickshell.env("TURNTABLE_SHOT") || ""
  readonly property string wallpaper: Quickshell.env("TURNTABLE_WALLPAPER") || ""
  readonly property var screenSpecs: (Quickshell.env("TURNTABLE_SCREENS") || "fixture:1920x1080")
    .split(",").map(function (entry) {
      const parts = entry.split(":")
      const dims = parts[1].split("x")
      return { name: parts[0], width: Number(dims[0]), height: Number(dims[1]) }
    })

  component Player: QtObject {
    property string dbusName: ""
    property string identity: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string trackArtUrl: ""
    property int playbackState: MprisPlaybackState.Stopped
  }

  Player {
    id: browser
    dbusName: "chromium.instance2303"
    identity: "Chromium"
    trackTitle: "Some video"
    trackArtist: "A channel"
    playbackState: MprisPlaybackState.Playing
  }

  Player {
    id: spotify
    dbusName: "org.mpris.MediaPlayer2.spotify"
    identity: "Spotify"
    trackTitle: Quickshell.env("TURNTABLE_TITLE") || "Shared Shelter"
    trackArtist: Quickshell.env("TURNTABLE_ARTIST") || "Biba Dupont"
    trackArtUrl: Quickshell.env("TURNTABLE_ART") || ""
    playbackState: MprisPlaybackState.Playing
  }

  // pear-desktop, the YouTube Music client.
  Player {
    id: ytMusic
    dbusName: "org.mpris.MediaPlayer2.YoutubeMusic"
    identity: "YouTube Music"
    trackTitle: "Another Song"
    trackArtist: "Someone Else"
    playbackState: MprisPlaybackState.Paused
  }

  // A second, idle Spotify client (spotifyd) that must not shadow the real one.
  Player {
    id: spotifyd
    dbusName: "org.mpris.MediaPlayer2.spotifyd"
    identity: "Spotifyd"
  }

  // The scene needs a visible parent, or Qt reports it as invisible and the
  // spin assertions would depend on scene start-up order.
  Item {
    id: host
    visible: true
    width: 1920
    height: 1080
    DesktopTurntableScene { id: scene; anchors.fill: parent }
  }

  function check(name, condition) {
    if (condition) console.log("ok   " + name)
    else { console.log("FAIL " + name); ++smoke.failures }
  }

  Component.onCompleted: {
    const state = TurntableState

    state.playersOverride = []
    check("no players means no record", state.player === null && !state.hasTrack)

    state.playersOverride = [browser]
    check("a browser player alone is ignored", state.player === null && !state.hasTrack)

    state.playersOverride = [browser, spotify]
    check("spotify is picked over a playing browser", state.player === spotify)
    check("a playing spotify track shows the record", state.hasTrack && state.isPlaying)
    check("title is projected", state.trackTitle === spotify.trackTitle)

    check("scene reads TurntableState by default", scene.media === state)
    check("record spins while playing", scene.spinning)
    check("tonearm lowers while playing", scene.playing)
    scene.spinAllowed = false
    check("record stops when covered by windows", !scene.spinning)
    scene.spinAllowed = true

    spotify.playbackState = MprisPlaybackState.Paused
    check("paused keeps the record up", state.hasTrack && !state.isPlaying)
    check("record holds still while paused", !scene.spinning && !scene.playing)

    spotify.playbackState = MprisPlaybackState.Stopped
    check("stopped hides the record", !state.hasTrack)

    spotify.playbackState = MprisPlaybackState.Playing
    spotify.trackTitle = ""
    check("an empty title hides the record", !state.hasTrack)
    check("record does not spin while hidden", !scene.spinning)
    spotify.trackTitle = Quickshell.env("TURNTABLE_TITLE") || "Shared Shelter"

    state.playersOverride = [browser, ytMusic]
    check("youtube music is an allowed player", state.player === ytMusic && state.hasTrack)
    ytMusic.identity = "Cider"
    ytMusic.dbusName = "org.mpris.MediaPlayer2.cider"
    check("cider is an allowed player", state.player === ytMusic)
    ytMusic.identity = "YouTube Music"
    ytMusic.dbusName = "org.mpris.MediaPlayer2.YoutubeMusic"

    state.playersOverride = [spotify, ytMusic]
    check("a playing player beats a paused one", state.player === spotify)
    spotify.playbackState = MprisPlaybackState.Paused
    MediaState.lastStamps = { "org.mpris.MediaPlayer2.spotify": 1, "org.mpris.MediaPlayer2.YoutubeMusic": 2 }
    check("of two paused players the one played last wins", state.player === ytMusic)
    MediaState.lastStamps = { "org.mpris.MediaPlayer2.spotify": 3, "org.mpris.MediaPlayer2.YoutubeMusic": 2 }
    check("and it follows when the other was played after", state.player === spotify)
    MediaState.lastStamps = {}
    spotify.playbackState = MprisPlaybackState.Playing

    state.playersOverride = [spotifyd, spotify]
    check("an idle spotify instance listed first does not shadow a playing one",
      state.player === spotify)
    spotify.playbackState = MprisPlaybackState.Paused
    check("a paused spotify with a track beats an idle instance", state.player === spotify)
    spotify.playbackState = MprisPlaybackState.Playing

    // Each new cover pushes the last one onto the pile: newest first, four at
    // most, never the one playing, and no repeats.
    state.playersOverride = [spotify]
    state.recentCovers = []
    const covers = ["a", "b", "c", "b", "d", "e", "f"]
    for (var i = 0; i < covers.length; i++)
      spotify.trackArtUrl = "file:///covers/" + covers[i] + ".jpg"
    check("the pile keeps the last four covers, newest first",
      state.recentCovers.map(function (u) { return u.slice(-5, -4) }).join("") === "edbc")
    spotify.trackArtUrl = "file:///covers/e.jpg"
    check("the cover playing again leaves the pile",
      state.recentCovers.indexOf("file:///covers/e.jpg") === -1
      && state.recentCovers[0] === "file:///covers/f.jpg")
    spotify.trackArtUrl = ""
    check("a track without art leaves the pile alone", state.recentCovers.length === 4)
    spotify.trackArtUrl = Quickshell.env("TURNTABLE_ART") || ""

    check("the scene fills its window",
      scene.k > 0 && scene.r(1300) <= host.width + 0.5 && scene.r(724) <= host.height + 0.5)

    // Paused past the timeout fades out; checked once the timer has had time.
    state.playersOverride = [spotify]
    state.pauseTimeout = 100
    spotify.playbackState = MprisPlaybackState.Paused
    timeoutCheck.start()
  }

  Timer {
    id: timeoutCheck
    interval: 400
    onTriggered: {
      const state = TurntableState
      check("paused past the timeout hides the record", !state.hasTrack && state.pausedOut)
      spotify.playbackState = MprisPlaybackState.Playing
      check("playing again brings it back", state.hasTrack)
      state.pauseTimeout = 5 * 60 * 1000

      if (smoke.failures === 0)
        console.log("ok: Desktop turntable")

      if (smoke.shotDir === "")
        quitTimer.start()
      else
        smoke.shooting = true
    }
  }

  // --- optional preview renders ----------------------------------------------

  property int shotsPending: shotDir === "" ? 0 : screenSpecs.length

  Variants {
    model: smoke.shooting ? smoke.screenSpecs : []

    Window {
      id: shotWindow
      required property var modelData
      width: modelData.width
      height: modelData.height
      visible: true
      color: "black"

      Image {
        anchors.fill: parent
        source: smoke.wallpaper === "" ? "" : "file://" + smoke.wallpaper
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
      }

      DesktopTurntableScene {
        anchors.fill: parent
      }

      Timer {
        // Long enough for the async album art, the tonearm and the shadow
        // layer to settle.
        interval: 2500
        running: true
        onTriggered: shotWindow.contentItem.grabToImage(function (result) {
          const path = smoke.shotDir + "/turntable-" + shotWindow.modelData.name + ".png"
          console.log(result.saveToFile(path) ? "shot " + path : "FAIL shot " + path)
          if (--smoke.shotsPending === 0)
            quitTimer.start()
        })
      }
    }
  }

  Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
}
