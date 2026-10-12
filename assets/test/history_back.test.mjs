import assert from "node:assert/strict"
import {test} from "node:test"
import HistoryBack from "../js/hooks/history_back.js"

function setup(length) {
  let backCalls = 0
  let handler
  const el = {
    addEventListener(type, listener) {
      assert.equal(type, "click")
      handler = listener
    },
    removeEventListener(type, listener) {
      assert.equal(type, "click")
      assert.equal(listener, handler)
      handler = null
    },
  }
  globalThis.window = {history: {length, back: () => backCalls++}}
  const hook = {el}
  HistoryBack.mounted.call(hook)

  return {
    click(overrides = {}) {
      let prevented = false
      handler({button: 0, preventDefault: () => { prevented = true }, ...overrides})
      return {prevented, backCalls}
    },
    destroy() {
      HistoryBack.destroyed.call(hook)
      assert.equal(handler, null)
    },
  }
}

test("back uses browser history instead of the fallback link", () => {
  const hook = setup(3)
  assert.deepEqual(hook.click(), {prevented: true, backCalls: 1})
  hook.destroy()
})

test("direct visits follow the fallback link", () => {
  const hook = setup(1)
  assert.deepEqual(hook.click(), {prevented: false, backCalls: 0})
  hook.destroy()
})

test("modified clicks and already handled clicks retain their normal behavior", () => {
  const hook = setup(3)
  for (const overrides of [{ctrlKey: true}, {metaKey: true}, {shiftKey: true}, {altKey: true}, {button: 1}, {defaultPrevented: true}]) {
    assert.deepEqual(hook.click(overrides), {prevented: false, backCalls: 0})
  }
  hook.destroy()
})
