import { afterEach, expect, mock, test } from "bun:test"
import { join } from "node:path"

const existingPaths = new Set<string>()
const fakeHome = "/rtk-resolver-test-home"
const savedEnvironment = new Map<string, { present: boolean; value: string | undefined }>()

mock.module("node:fs", () => ({
  existsSync: (path: string) => existingPaths.has(path),
}))
mock.module("node:os", () => ({ homedir: () => fakeHome }))

const pluginModule = await import("./rtk.ts")

function setEnvironment(name: string, value: string | undefined) {
  if (!savedEnvironment.has(name)) {
    savedEnvironment.set(name, {
      present: Object.hasOwn(process.env, name),
      value: process.env[name],
    })
  }
  if (value === undefined) delete process.env[name]
  else process.env[name] = value
}

afterEach(() => {
  pluginModule._resetCachedRtkPath()
  existingPaths.clear()
  for (const [name, original] of savedEnvironment) {
    if (original.present) process.env[name] = original.value!
    else delete process.env[name]
  }
  savedEnvironment.clear()
})

test("expands a tilde in RTK_BIN and gives it precedence", () => {
  const configured = join(fakeHome, "custom", "rtk")
  existingPaths.add(configured)
  setEnvironment("RTK_BIN", "~/custom/rtk")

  expect(pluginModule.expandHome("~/custom/rtk")).toBe(configured)
  expect(pluginModule.resolveRtkPath()).toBe(configured)
})

test("resolves RTK from PATH before fallback directories", () => {
  const pathBinary = "/fixture/bin/rtk"
  const localBinary = join(fakeHome, ".local", "bin", "rtk")
  existingPaths.add(pathBinary)
  existingPaths.add(localBinary)
  setEnvironment("RTK_BIN", undefined)
  setEnvironment("PATH", "/fixture/bin")

  expect(pluginModule.resolveRtkPath()).toBe(pathBinary)
})

test("searches each documented fallback directory", () => {
  const fallbacks = [
    join(fakeHome, ".local", "bin", "rtk"),
    join(fakeHome, ".cargo", "bin", "rtk"),
    "/opt/homebrew/bin/rtk",
    "/usr/local/bin/rtk",
  ]
  setEnvironment("RTK_BIN", undefined)
  setEnvironment("PATH", "")

  for (const expected of fallbacks) {
    pluginModule._resetCachedRtkPath()
    existingPaths.clear()
    existingPaths.add(expected)
    expect(pluginModule.resolveRtkPath()).toBe(expected)
  }
})

test("replaces a cached path after it disappears", () => {
  const first = "/fixture/first/rtk"
  const second = "/fixture/second/rtk"
  existingPaths.add(first)
  existingPaths.add(second)
  setEnvironment("RTK_BIN", first)
  setEnvironment("PATH", "")

  expect(pluginModule.resolveRtkPath()).toBe(first)
  setEnvironment("RTK_BIN", second)
  expect(pluginModule.resolveRtkPath()).toBe(first)
  existingPaths.delete(first)
  expect(pluginModule.resolveRtkPath()).toBe(second)
})

test("does not register a hook when no RTK binary exists", async () => {
  setEnvironment("RTK_BIN", undefined)
  setEnvironment("PATH", "")
  let registered = false

  await pluginModule.default.setup({
    tool: {
      hook: async () => {
        registered = true
      },
    },
  })

  expect(pluginModule.resolveRtkPath()).toBeNull()
  expect(registered).toBe(false)
})
