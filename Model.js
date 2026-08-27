.pragma library

// Shared helpers for the Omasplash plugin surfaces. Anything that is pure
// data shaping lives here so BarWidget, Browser, and Service agree on it.

var ORIENTATIONS = ["landscape", "portrait", "squarish", "any"]

// Rotation choices, in minutes. 0 is "off" and is what a fresh config gets.
var INTERVALS = [
  { label: "Off", minutes: 0 },
  { label: "15m", minutes: 15 },
  { label: "30m", minutes: 30 },
  { label: "1h", minutes: 60 },
  { label: "3h", minutes: 180 },
  { label: "6h", minutes: 360 },
  { label: "Daily", minutes: 1440 }
]

// Process output is untrusted input as far as the shell process is concerned:
// a wedged curl or an API error page must not be able to blow up the parse.
function parseJson(raw, fallback, limit) {
  try {
    if (typeof raw !== "string") return fallback
    if (raw.length > (limit || 2097152)) return fallback
    var trimmed = raw.trim()
    if (trimmed === "") return fallback
    var parsed = JSON.parse(trimmed)
    return parsed === null || parsed === undefined ? fallback : parsed
  } catch (error) {
    return fallback
  }
}

function singleLine(value, max) {
  if (typeof value !== "string") return ""
  var flat = value.replace(/\s+/g, " ").trim()
  var limit = max || 200
  return flat.length > limit ? flat.slice(0, limit - 1) + "…" : flat
}

function isPhoto(row) {
  return !!row && typeof row.id === "string" && typeof row.thumb === "string"
}

function photoRows(parsed) {
  if (!Array.isArray(parsed)) return []
  var rows = []
  for (var i = 0; i < parsed.length; i++) {
    if (!isPhoto(parsed[i])) continue
    rows.push({
      id: parsed[i].id,
      thumb: parsed[i].thumb,
      preview: parsed[i].preview || parsed[i].thumb,
      color: parsed[i].color || "#222222",
      alt: singleLine(parsed[i].alt, 120),
      user: singleLine(parsed[i].user, 60),
      userLink: parsed[i].userLink || "https://unsplash.com",
      json: JSON.stringify(parsed[i])
    })
  }
  return rows
}

function topicRows(parsed) {
  if (!Array.isArray(parsed)) return []
  var rows = []
  for (var i = 0; i < parsed.length; i++) {
    var slug = parsed[i] && parsed[i].slug
    if (typeof slug !== "string" || slug === "") continue
    rows.push({ slug: slug, title: singleLine(parsed[i].title || slug, 40) })
  }
  return rows
}

function intervalLabel(minutes) {
  for (var i = 0; i < INTERVALS.length; i++)
    if (INTERVALS[i].minutes === minutes) return INTERVALS[i].label
  return minutes + "m"
}

// Attribution is a licence obligation, not decoration — every surface that
// names a photo renders it through here so the wording stays identical.
function credit(photo) {
  if (!photo || !photo.user) return ""
  return (photo.alt ? photo.alt + " — " : "") + "Photo by " + photo.user + " on Unsplash"
}

function barTooltip(state) {
  var lines = []
  if (!state.hasKey) {
    lines.push("Omasplash: no Unsplash access key")
    lines.push("Click to open the browser and add one")
    return lines.join("\n")
  }
  lines.push(credit(state.photo) || "Omasplash")
  lines.push(state.filterLabel ? "Filter: " + state.filterLabel : "Filter: all photos")
  lines.push(state.rotateMinutes > 0
    ? "Rotating every " + intervalLabel(state.rotateMinutes)
    : "Rotation off")
  lines.push("Left: browse · Middle: next · Right: toggle rotation")
  return lines.join("\n")
}
