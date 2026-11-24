// Pure helpers for the Screenshots bar panel. No QML here, so Node can test
// them (tests/model.test.js).

var IMAGE_PATTERN = /\.(png|jpe?g|webp|gif|bmp|avif)$/i
var MAX_PATH = 4096

// Parses lines of `find -printf '%T@\t%s\t%p\n'` into screenshots, newest
// first, capped at `limit`. Lines that don't look right are skipped.
function parseListing(text, limit) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line === "") continue
    var a = line.indexOf("\t")
    var b = a < 0 ? -1 : line.indexOf("\t", a + 1)
    if (b < 0) continue
    var mtime = Number(line.slice(0, a))
    var size = Number(line.slice(a + 1, b))
    var path = line.slice(b + 1)
    if (!isFinite(mtime) || !isFinite(size) || path === "" || path.length > MAX_PATH) continue
    if (path.charAt(0) !== "/" || !IMAGE_PATTERN.test(path)) continue
    var name = path.slice(path.lastIndexOf("/") + 1)
    out.push({ path: path, name: name, mtime: mtime, size: size, haystack: haystack(name) })
  }
  out.sort(function(x, y) { return y.mtime - x.mtime || (x.name < y.name ? -1 : x.name > y.name ? 1 : 0) })
  var cap = Number(limit) > 0 ? Number(limit) : out.length
  return out.slice(0, cap)
}

// Lowercased name with separators turned into spaces, so "t3 code error"
// finds 2026-11-18_07-36-12_t3-code-home-unavailable-error.png.
function haystack(name) {
  return String(name).toLowerCase().replace(/\.[a-z0-9]+$/, "").replace(/[-_.]+/g, " ")
}

function tokens(query) {
  return String(query || "").toLowerCase().replace(/[-_.]+/g, " ").split(/\s+/).filter(function(t) { return t !== "" })
}

// Every word of the query must appear somewhere in the name, in any order.
function filter(items, query) {
  var words = tokens(query)
  if (words.length === 0) return items
  var out = []
  for (var i = 0; i < items.length; i++) {
    var h = items[i].haystack
    var ok = true
    for (var j = 0; j < words.length && ok; j++) ok = h.indexOf(words[j]) >= 0
    if (ok) out.push(items[i])
  }
  return out
}

// Omasnap names files <date>_<time>_<title>.png; the readable title is the
// part after the timestamp. Other names are shown without their extension.
function title(name) {
  var base = String(name).replace(/\.[A-Za-z0-9]+$/, "")
  var m = /^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?:_(.*))?$/.exec(base)
  if (!m) return base
  return m[1] ? m[1].replace(/[-_]+/g, " ") : ""
}

// How long ago, as { unit, count }: unit is "now" (under a minute, or in
// the future), "minute", "hour", "day", "week", "month" or "year", and count
// is whole units, rounded down. Both times are in ms except mtime (seconds).
function relativeTime(mtimeSeconds, nowMs) {
  var s = Math.floor((nowMs - mtimeSeconds * 1000) / 1000)
  if (!(s >= 60)) return { unit: "now", count: 0 }
  var steps = [["year", 31536000], ["month", 2592000], ["week", 604800], ["day", 86400], ["hour", 3600], ["minute", 60]]
  for (var i = 0; i < steps.length; i++)
    if (s >= steps[i][1]) return { unit: steps[i][0], count: Math.floor(s / steps[i][1]) }
}

function clampIndex(index, count) {
  if (count <= 0) return -1
  return Math.max(0, Math.min(count - 1, index))
}

if (typeof module !== "undefined") {
  module.exports = {
    parseListing: parseListing,
    haystack: haystack,
    tokens: tokens,
    filter: filter,
    title: title,
    relativeTime: relativeTime,
    clampIndex: clampIndex
  }
}
