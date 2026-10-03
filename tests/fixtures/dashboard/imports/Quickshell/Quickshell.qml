pragma Singleton
import QtQuick
QtObject {
  function env(n) { return n === "HOME" ? fixtureRoot + "/home" : "" }
  function statePath(p) { return fixtureRoot + "/state/" + p }
  function execDetached(cmd) { throw new Error("Detached commands are forbidden in this fixture") }
}
