pragma Singleton
import QtQuick
QtObject {
  property bool hasTrack: true
  property string trackTitle: "Contour Lines"
  property string trackArtist: "The Dotfiles"
  property string trackAlbum: "Tokyo Nights"
  property string trackArtUrl: "file://" + fixtureRoot + "/art.png"
  property string sourceLabel: "Lyne Player"
  property string sourceGlyph: glyphMusic
  property real length: 214
  property real effectivePosition: 88
  readonly property real progress: effectivePosition / length
  property bool dragging: false
  property bool canSeek: true
  property bool canNext: true
  property bool canPrevious: true
  property bool canTogglePlaying: true
  property bool loopSupported: true
  property bool shuffleSupported: true
  property bool volumeSupported: true
  property bool canRaise: true
  property bool isPlaying: true
  property bool shuffle: false
  property bool loopActive: false
  property real volume: 0.7
  readonly property string glyphMusic: String.fromCodePoint(0xf075a)
  readonly property string glyphPrevious: String.fromCodePoint(0xf04ae)
  readonly property string glyphNext: String.fromCodePoint(0xf04ad)
  readonly property string glyphOpen: String.fromCodePoint(0xf03cc)
  readonly property string glyphVolume: String.fromCodePoint(0xf057e)
  readonly property string playGlyph: String.fromCodePoint(0xf03e4)
  readonly property string loopGlyph: String.fromCodePoint(0xf0457)
  readonly property string shuffleGlyph: String.fromCodePoint(0xf049e)
  function formatTime(s) { const t = Math.floor(s); return Math.floor(t/60) + ":" + String(t%60).padStart(2,"0") }
  function seekToFraction(f) {} function toggleShuffle() {} function previous() {} function next() {}
  function togglePlaying() {} function cycleLoop() {} function setVolume(v) {} function raisePlayer() {}
}
