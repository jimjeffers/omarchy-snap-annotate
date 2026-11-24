// Run with: node tests/model.test.js
const assert = require("assert")
const M = require("../Model.js")

const listing = [
  "1763900000.5\t1000\t/home/u/Pictures/Screenshots/2026-11-23_09-21-25_lumen-monitors-settings-panel.png",
  "1763400000\t2000\t/home/u/Pictures/Screenshots/2026-11-18_07-36-12_t3-code-home-unavailable-error.png",
  "1763500000\t3000\t/home/u/Pictures/Screenshots/notes.txt",
  "garbage line",
  "abc\t1\t/home/u/x.png",
  "1763600000\t10\trelative/path.png",
  "1763700000\t10\t/home/u/Pictures/Screenshots/My Shot <b>.JPG",
  ""
].join("\n")

const items = M.parseListing(listing)
assert.deepStrictEqual(items.map(i => i.name), [
  "2026-11-23_09-21-25_lumen-monitors-settings-panel.png",
  "My Shot <b>.JPG",
  "2026-11-18_07-36-12_t3-code-home-unavailable-error.png"
])
assert.strictEqual(M.parseListing(listing, 1).length, 1)
assert.deepStrictEqual(M.parseListing(""), [])
assert.deepStrictEqual(M.parseListing(null), [])

// Search: words in any order, separators ignored, case-insensitive.
assert.deepStrictEqual(M.filter(items, "").length, 3)
assert.deepStrictEqual(M.filter(items, "ERROR t3").map(i => i.name), [items[2].name])
assert.deepStrictEqual(M.filter(items, "home-unavailable").map(i => i.name), [items[2].name])
assert.deepStrictEqual(M.filter(items, "2026-11-23").map(i => i.name), [items[0].name])
assert.deepStrictEqual(M.filter(items, "nothing here"), [])
assert.deepStrictEqual(M.filter(items, "<b>").map(i => i.name), [items[1].name])

// Titles
assert.strictEqual(M.title("2026-11-23_09-21-25_lumen-monitors-settings-panel.png"), "lumen monitors settings panel")
assert.strictEqual(M.title("2026-11-23_09-21-25.png"), "")
assert.strictEqual(M.title("My Shot <b>.JPG"), "My Shot <b>")

// Relative time
const now = new Date(2026, 10, 23, 12, 0, 0).getTime()
const ago = secs => (now / 1000) - secs
assert.deepStrictEqual(M.relativeTime(ago(30), now), { unit: "now", count: 0 })
assert.deepStrictEqual(M.relativeTime(ago(-120), now), { unit: "now", count: 0 })
assert.deepStrictEqual(M.relativeTime(ago(60), now), { unit: "minute", count: 1 })
assert.deepStrictEqual(M.relativeTime(ago(59 * 60 + 59), now), { unit: "minute", count: 59 })
assert.deepStrictEqual(M.relativeTime(ago(3 * 3600 + 5), now), { unit: "hour", count: 3 })
assert.deepStrictEqual(M.relativeTime(ago(2 * 86400), now), { unit: "day", count: 2 })
assert.deepStrictEqual(M.relativeTime(ago(15 * 86400), now), { unit: "week", count: 2 })
assert.deepStrictEqual(M.relativeTime(ago(65 * 86400), now), { unit: "month", count: 2 })
assert.deepStrictEqual(M.relativeTime(ago(400 * 86400), now), { unit: "year", count: 1 })

assert.strictEqual(M.clampIndex(5, 3), 2)
assert.strictEqual(M.clampIndex(-1, 3), 0)
assert.strictEqual(M.clampIndex(0, 0), -1)

console.log("ok")
