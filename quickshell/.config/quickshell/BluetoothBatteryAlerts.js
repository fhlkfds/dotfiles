// Low-battery alerts for Bluetooth devices: one at 10%, one at 5%, and one
// when the device dies. Pure logic, fed each BluetoothState poll and unit-tested
// from Node (tests/bluetooth-battery-alerts.logic.test.js).
//
// BlueZ reports no charging state for peripherals, so a device is re-armed
// once a reading climbs back above REARM. The gap above LOW stops a reading
// that wobbles between 10% and 11% from alerting twice.
var LOW = 10
var CRITICAL = 5
var REARM = 15

function entryFor(previous) {
  var was = previous || {}
  return {
    connected: was.connected === true,
    battery: typeof was.battery === "number" ? was.battery : -1,
    low: was.low === true,
    critical: was.critical === true,
    dead: was.dead === true
  }
}

// `previous` maps address -> entry. `ok` is false when the adapter is off or
// the poll failed: every device then reads as disconnected without alerting,
// so turning Bluetooth off is never mistaken for a dead battery.
function update(previous, ok, devices) {
  var state = {}
  var alerts = []
  var list = Array.isArray(devices) ? devices : []

  if (!ok) {
    for (var address in previous || {}) {
      state[address] = entryFor(previous[address])
      state[address].connected = false
    }
    return { state: state, alerts: alerts }
  }

  for (var i = 0; i < list.length; i++) {
    var device = list[i]
    var was = entryFor((previous || {})[device.address])
    var now = entryFor(was)
    var battery = typeof device.battery === "number" ? device.battery : -1
    var alert = function(level, percent) {
      alerts.push({ level: level, address: device.address,
                    name: device.name || device.address,
                    icon: device.icon || "", battery: percent })
    }
    now.connected = device.connected === true

    if (now.connected && battery >= 0) {
      now.battery = battery
      if (battery > REARM) {
        now.low = false; now.critical = false; now.dead = false
      } else if (battery === 0) {
        if (!now.dead) alert("dead", 0)
        now.low = true; now.critical = true; now.dead = true
      } else if (battery <= CRITICAL) {
        if (!now.critical) alert("critical", battery)
        now.low = true; now.critical = true
      } else if (battery <= LOW && !now.low) {
        alert("low", battery)
        now.low = true
      }
    } else if (!now.connected && was.connected && was.battery >= 0
               && was.battery <= CRITICAL && !was.dead) {
      // A device that drops off while nearly flat has almost certainly died.
      alert("dead", was.battery)
      now.dead = true
    }
    state[device.address] = now
  }
  return { state: state, alerts: alerts }
}

function message(alert) {
  if (alert.level === "dead")
    return { title: alert.name + " died",
             body: alert.battery > 0
               ? "Disconnected at " + alert.battery + "% battery."
               : "The battery is empty." }
  return { title: alert.name + " at " + alert.battery + "%",
           body: alert.level === "critical" ? "About to die. Charge it now."
                                            : "Battery low. Charge it soon." }
}

if (typeof module !== "undefined") {
  module.exports = { update: update, message: message }
}
