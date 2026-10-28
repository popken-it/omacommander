.pragma library

function bytes(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return "0 B"
  var units = ["B", "kB", "MB", "GB", "TB", "PB"]
  var i = 0
  while (n >= 1000 && i < units.length - 1) {
    n = n / 1000
    i++
  }
  var text = (i === 0 || n >= 100) ? Math.round(n) : Math.round(n * 10) / 10
  return text + " " + units[i]
}

function pad(value) {
  return value < 10 ? "0" + value : "" + value
}

function date(seconds) {
  var d = new Date(Number(seconds) * 1000)
  if (isNaN(d.getTime())) return ""
  var now = new Date()
  var yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  if (d.toDateString() === now.toDateString())
    return pad(d.getHours()) + ":" + pad(d.getMinutes())
  if (d.toDateString() === yesterday.toDateString()) return "Yesterday"
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  var label = d.getDate() + " " + months[d.getMonth()]
  if (d.getFullYear() !== now.getFullYear()) label += " " + d.getFullYear()
  return label
}

function naturalKey(value) {
  return String(value || "").toLowerCase().replace(/(\d+)/g, function(match) {
    return "\u0001" + ("0000000000" + match).slice(-10)
  })
}
