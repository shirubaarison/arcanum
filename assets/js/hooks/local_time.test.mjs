import assert from "node:assert/strict"
import test from "node:test"
import LocalTime, {formatLocalTime} from "./local_time.js"

test("UTC instants convert to the viewer's date and hour across midnight", () => {
  const utc = "2026-01-15T01:30:00Z"
  assert.match(formatLocalTime(utc, "en-US", "UTC"), /Jan 15, 2026.*01:30 AM/)
  assert.match(formatLocalTime(utc, "en-US", "America/Los_Angeles"), /Jan 14, 2026.*05:30 PM/)
  assert.match(formatLocalTime(utc, "en-US", "Asia/Tokyo"), /Jan 15, 2026.*10:30 AM/)
})

test("daylight saving offsets come from the timestamp's date", () => {
  assert.match(formatLocalTime("2026-01-15T20:00:00Z", "en-US", "America/New_York"), /03:00 PM/)
  assert.match(formatLocalTime("2026-07-15T20:00:00Z", "en-US", "America/New_York"), /04:00 PM/)
})

test("the default time zone is the viewer's environment", () => {
  const previous = process.env.TZ
  try {
    process.env.TZ = "Asia/Tokyo"
    assert.match(formatLocalTime("2026-01-15T01:30:00Z", "en-US"), /10:30 AM/)
  } finally {
    if (previous === undefined) delete process.env.TZ
    else process.env.TZ = previous
  }
})

test("hooks localize mounted and updated timestamps without changing the UTC value", () => {
  const context = {
    el: {dataset: {utc: "2026-01-15T01:30:00Z"}, textContent: "UTC fallback"},
    renderTime: LocalTime.renderTime,
  }
  LocalTime.mounted.call(context)
  assert.equal(context.el.textContent, formatLocalTime(context.el.dataset.utc))
  assert.equal(context.el.dataset.utc, "2026-01-15T01:30:00Z")

  context.el.dataset.utc = "2026-07-15T20:00:00Z"
  LocalTime.updated.call(context)
  assert.equal(context.el.textContent, formatLocalTime(context.el.dataset.utc))
})

test("invalid timestamps leave the fallback intact", () => {
  const context = {el: {dataset: {utc: "invalid"}, textContent: "UTC fallback"}}
  LocalTime.renderTime.call(context)
  assert.equal(context.el.textContent, "UTC fallback")
})

test("local timestamps do not display a time zone suffix", () => {
  const formatted = formatLocalTime("2026-01-15T20:00:00Z", "en-US", "America/Sao_Paulo")
  assert.match(formatted, /05:00 PM$/)
  assert.doesNotMatch(formatted, /GMT|UTC|BRT/)
})
