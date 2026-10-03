pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick

// What the desktop Turntable shows: the allowed player that most recently
// started playing.
//
// MediaState follows any player, which is right for the bar and its panel but
// would let a browser tab take over the desktop. This singleton only looks at
// allowed players, so the record stays on Spotify while a YouTube tab plays,
// and fades out entirely when nothing allowed has a track.
Singleton {
  id: root

  // --- settings: edit these, Quickshell reloads on save -----------------------

  // Matched case-insensitively against each player's bus name and identity.
  // "youtube" catches pear-desktop (YouTube Music); a browser is never matched,
  // because its bus name and identity are the browser's, not the site's.
  property var allowedPlayers: ["spotify", "youtube", "pear", "cider"]
  // Paused this long counts as finished, and the Turntable fades out.
  property int pauseTimeout: 5 * 60 * 1000

  // ----------------------------------------------------------------------------

  // Smoke harnesses assign an array of stand-in players here so they never
  // touch the real session bus.
  property var playersOverride: null

  readonly property var players: playersOverride !== null
    ? playersOverride
    : (Mpris.players ? Mpris.players.values : [])

  function isAllowed(p) {
    if (!p)
      return false
    const bus = (p.dbusName || "").toLowerCase()
    const name = (p.identity || "").toLowerCase()
    return root.allowedPlayers.some(function (a) {
      return bus.indexOf(a) !== -1 || name.indexOf(a) !== -1
    })
  }

  function hasLoaded(p) {
    return p.trackTitle !== "" && p.playbackState !== MprisPlaybackState.Stopped
  }

  // Playing beats loaded beats idle; within a tier the most recent wins, by the
  // start/last-playing stamps MediaState already keeps for every player. So an
  // idle spotifyd listed first cannot shadow the desktop app, and pausing
  // YouTube Music after Spotify keeps YouTube Music on the record.
  readonly property var player: {
    const list = root.players
    const starts = MediaState.startStamps
    const lasts = MediaState.lastStamps
    var best = null
    var bestTier = -1
    var bestKey = -1
    for (var i = 0; i < list.length; i++) {
      const p = list[i]
      if (!root.isAllowed(p))
        continue
      const playing = p.playbackState === MprisPlaybackState.Playing
      const tier = playing ? 2 : (root.hasLoaded(p) ? 1 : 0)
      const key = (playing ? starts[p.dbusName] : lasts[p.dbusName]) || 0
      if (tier > bestTier || (tier === bestTier && key > bestKey)) {
        best = p
        bestTier = tier
        bestKey = key
      }
    }
    return best
  }

  readonly property bool isPlaying: player !== null
    && player.playbackState === MprisPlaybackState.Playing
  readonly property bool isPaused: player !== null
    && player.playbackState === MprisPlaybackState.Paused

  // Set once the player has sat paused for pauseTimeout; any new playback,
  // track or player clears it.
  property bool pausedOut: false

  // A player sits at Stopped with no track right after launch; that is not
  // worth a record. Paused keeps it until the timeout.
  readonly property bool hasTrack: player !== null && hasLoaded(player) && !pausedOut

  readonly property string trackTitle: player ? player.trackTitle : ""
  readonly property string trackArtist: player ? player.trackArtist : ""
  readonly property string trackArtUrl: player ? player.trackArtUrl : ""

  // Repeats rather than single-shot: a one-shot Timer clears its own `running`
  // after firing, which would fight this binding.
  Timer {
    interval: root.pauseTimeout
    repeat: true
    running: root.isPaused && root.player.trackTitle !== ""
    onTriggered: root.pausedOut = true
  }

  // Covers played before this one, newest first, for the pile on the desk.
  // Session-only, like MediaState's stamps.
  property var recentCovers: []
  property string lastCover: ""

  onTrackArtUrlChanged: {
    if (trackArtUrl === "")
      return
    if (lastCover !== "" && lastCover !== trackArtUrl) {
      const current = trackArtUrl
      const previous = lastCover
      recentCovers = [previous].concat(recentCovers.filter(function (u) {
        return u !== previous && u !== current
      })).slice(0, 4)
    }
    lastCover = trackArtUrl
  }

  // The current wallpaper, hung in the frame on the wall. hypr-wallpaper-picker
  // writes {"path": ...} here whenever it applies one.
  property string wallpaper: ""

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
          + "/hyprland-desktop/wallpaper/current"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.wallpaper = JSON.parse(text()).path || ""
      } catch (e) {}
    }
  }

  onIsPlayingChanged: if (isPlaying) pausedOut = false
  onPlayerChanged: pausedOut = false
  onTrackTitleChanged: pausedOut = false
}
