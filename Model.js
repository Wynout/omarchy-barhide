// Shared screen-matching helpers for Bar Hide. Pure functions so both the
// bar and the picker panel agree on how a stored reference identifies a
// live screen.
//
// A reference is either:
//   - { name, model, serial } — captured from a live screen when picked, or
//   - a plain string — matched as a case-insensitive substring of the
//     screen's model or name.
//
// Empty reference fields never take part in a match, so a screen captured
// without a serial still matches after the move to another port.

function eqField(want, have, caseInsensitive) {
  if (want === undefined || want === null || String(want) === "") return false
  if (have === undefined || have === null || String(have) === "") return false
  if (caseInsensitive) return String(want).toLowerCase() === String(have).toLowerCase()
  return String(want) === String(have)
}

// Specificity score of a structured match — the sum of agreeing fields:
//   name +2, serial +1, model +1 (only fields present on both sides count).
// The name outweighs the rest because it is the only field that tells apart
// two screens shipping with the same model and serial, while a serial/model
// agreement still carries a match when the monitor moves to another port
// (where its name changes with the cable).
function screenScore(ref, screen) {
  if (!ref || typeof ref !== "object" || !screen) return 0
  var score = 0
  if (eqField(ref.name, screen.name, true)) score += 2
  if (eqField(ref.serial, screen.serial, false)) score += 1
  if (eqField(ref.model, screen.model, true)) score += 1
  return score
}

function stringMatches(ref, screen) {
  var needle = String(ref).toLowerCase()
  if (needle === "") return false
  return String(screen.model || "").toLowerCase().indexOf(needle) !== -1
    || String(screen.name || "").toLowerCase().indexOf(needle) !== -1
}

// First live screen matching a reference, or null. Structured refs resolve
// to the single highest-scoring screen; a tie at the top (two screens the
// reference cannot tell apart) refuses to guess. String refs substring-match
// model or name.
function findScreen(screens, ref) {
  if (!ref || !screens) return null
  if (typeof ref === "string") {
    for (var i = 0; i < screens.length; i++)
      if (stringMatches(ref, screens[i])) return screens[i]
    return null
  }
  if (typeof ref !== "object") return null
  var best = null
  var bestScore = 0
  var tied = 0
  for (var j = 0; j < screens.length; j++) {
    var score = screenScore(ref, screens[j])
    if (score === 0) continue
    if (score > bestScore) {
      best = screens[j]
      bestScore = score
      tied = 1
    } else if (score === bestScore) {
      tied++
    }
  }
  return tied > 1 ? null : best
}

// True when a reference identifies this exact screen — every non-empty
// stored field must agree with the screen. Used for the badges and role
// read-outs in the picker, which describe stored state rather than resolve
// a live target, so two screens sharing a model and serial stay distinct.
function refMatches(ref, screen) {
  if (!ref || !screen) return false
  if (typeof ref === "string") return stringMatches(ref, screen)
  if (typeof ref !== "object") return false
  var fields = ["serial", "model", "name"]
  var compared = 0
  var agreed = 0
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i]
    var want = ref[f]
    if (want === undefined || want === null || String(want) === "") continue
    var have = screen[f]
    if (have === undefined || have === null || String(have) === "") continue
    compared++
    if (eqField(want, have, f !== "serial")) agreed++
  }
  return compared > 0 && agreed === compared
}

// Human-readable form of a reference for the picker's read-outs.
function refLabel(ref) {
  if (!ref) return "not set"
  if (typeof ref === "string") return "'" + ref + "'"
  if (typeof ref !== "object") return "not set"
  var parts = []
  if (ref.name) parts.push(String(ref.name))
  if (ref.model) parts.push(String(ref.model))
  return parts.length ? parts.join(" · ") : "not set"
}
