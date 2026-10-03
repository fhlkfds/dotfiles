pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

// Spotify-only view of MPRIS for the desktop now-playing card.
//
// MediaState follows whichever player most recently started, which is right
// for the bar but would let a browser tab take over the desktop card. This
// singleton ignores every player except Spotify, so the card stays put while a
// YouTube tab plays and disappears entirely when Spotify is closed.
//
// Positions and lengths from Quickshell are in SECONDS.
Singleton {
  id: root

  // Smoke harnesses assign an array of stand-in players here so they never
  // touch the real session bus.
  property var playersOverride: null

  readonly property var players: playersOverride !== null
    ? playersOverride
    : (Mpris.players ? Mpris.players.values : [])

  function isSpotify(p) {
    if (!p)
      return false
    const bus = (p.dbusName || "").toLowerCase()
    const name = (p.identity || "").toLowerCase()
    return bus.indexOf("spotify") !== -1 || name.indexOf("spotify") !== -1
  }

  // With more than one Spotify client on the bus (spotifyd next to the desktop
  // app, say), prefer the one playing, then one with a track loaded, so an idle
  // instance listed first cannot shadow the one in use.
  readonly property var player: {
    const list = root.players
    var loaded = null
    var idle = null
    for (var i = 0; i < list.length; i++) {
      const p = list[i]
      if (!root.isSpotify(p))
        continue
      if (p.playbackState === MprisPlaybackState.Playing)
        return p
      if (loaded === null && p.trackTitle !== ""
          && p.playbackState !== MprisPlaybackState.Stopped)
        loaded = p
      if (idle === null)
        idle = p
    }
    return loaded !== null ? loaded : idle
  }

  // Spotify sits at Stopped with no track right after launch; that is not
  // worth a card. Paused keeps it, so the desktop shows what you left off on.
  readonly property bool hasTrack: player !== null
    && player.trackTitle !== ""
    && player.playbackState !== MprisPlaybackState.Stopped

  readonly property bool isPlaying: player !== null
    && player.playbackState === MprisPlaybackState.Playing

  readonly property string trackTitle: player ? player.trackTitle : ""
  readonly property string trackArtist: player ? player.trackArtist : ""
  readonly property string trackArtUrl: player ? player.trackArtUrl : ""
  readonly property real length: player && player.lengthSupported ? player.length : 0

  // Quickshell extrapolates MprisPlayer.position itself but never signals it;
  // emitting positionChanged() is the documented way to refresh bindings.
  // One signal a second, and only while the track is moving.
  readonly property real position: player && player.positionSupported ? player.position : 0
  readonly property real progress: length > 0
    ? Math.max(0, Math.min(1, position / length)) : 0

  function refreshPosition() {
    try {
      if (root.player)
        root.player.positionChanged()
    } catch (e) {
      // stand-in players without the signal simply keep their value
    }
  }

  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.isPlaying
    onTriggered: root.refreshPosition()
  }

  // The timer stops with playback; one last read lands the time on where the
  // track actually paused instead of up to a second before it.
  onIsPlayingChanged: refreshPosition()

  readonly property bool canNext: player !== null && player.canGoNext
  readonly property bool canPrevious: player !== null && player.canGoPrevious
  readonly property bool canTogglePlaying: player !== null && player.canTogglePlaying

  function next() { if (canNext) player.next() }
  function previous() { if (canPrevious) player.previous() }
  function togglePlaying() { if (canTogglePlaying) player.togglePlaying() }
}
