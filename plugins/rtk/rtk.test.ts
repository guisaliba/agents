import { afterEach, expect, test } from "bun:test"
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

import plugin, { RtkOpenCodePlugin, _resetCachedRtkPath, runRtkRewrite, tryRewriteCommand } from "./rtk.ts"

type SavedEnvironmentValue = { present: boolean; value: string | undefined }
const savedEnvironment = new Map<string, SavedEnvironmentValue>()
let fixtureRoot: string

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

function writeExecutable(name: string, contents: string): string {
  const path = join(fixtureRoot, name)
  writeFileSync(path, contents)
  chmodSync(path, 0o755)
  return path
}

afterEach(() => {
  _resetCachedRtkPath()
  for (const [name, original] of savedEnvironment) {
    if (original.present) process.env[name] = original.value!
    else delete process.env[name]
  }
  savedEnvironment.clear()

  if (fixtureRoot) rmSync(fixtureRoot, { recursive: true, force: true })
  fixtureRoot = ""
})

test("the default export has the pinned OpenCode V2 plugin shape", () => {
  expect(typeof plugin).toBe("object")
  expect(plugin).toBe(RtkOpenCodePlugin)
  expect(plugin.id).toBe("rtk")
  expect(plugin.setup).toBeFunction()
  expect(plugin.server).toBeFunction()
})

test("the V2 setup hook rewrites a shell command", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-plugin-test-"))
  const rtkBin = writeExecutable("rtk", "#!/bin/sh\nprintf '%s' 'rtk git status --short'\n")
  setEnvironment("RTK_BIN", rtkBin)

  let hookName: string | undefined
  let hookCallback: ((event: any) => Promise<void>) | undefined
  await plugin.setup({
    tool: {
      hook: async (name: string, callback: (event: any) => Promise<void>) => {
        hookName = name
        hookCallback = callback
      },
    },
  })

  expect(hookName).toBe("execute.before")
  expect(hookCallback).toBeFunction()

  const event = { tool: "bash", input: { command: "git status --short" } }
  await hookCallback!(event)

  expect(event.input.command).toBe("rtk git status --short")
})

test("accepts changed rewrite output with RTK exit code 0 or 3", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-rewrite-test-"))

  for (const exitCode of [0, 3]) {
    const rtkBin = writeExecutable(
      `rtk-${exitCode}`,
      `#!/bin/sh\nprintf '%s' '  rtk git status --short  '\nexit ${exitCode}\n`,
    )
    expect(await runRtkRewrite(rtkBin, "git status --short")).toBe("rtk git status --short")
  }
})

test("rejects empty or unchanged rewrite output", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-output-test-"))
  const cases = [
    { name: "empty", output: "", expected: null },
    { name: "unchanged", output: "git status --short", expected: null },
  ]

  for (const { name, output, expected } of cases) {
    const rtkBin = writeExecutable(name, `#!/bin/sh\nprintf '%s' '${output}'\n`)
    expect(await runRtkRewrite(rtkBin, "git status --short")).toBe(expected)
  }
})

test("rejects output from RTK error exit codes", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-error-test-"))

  for (const exitCode of [1, 2, 9]) {
    const rtkBin = writeExecutable(
      `rtk-${exitCode}`,
      `#!/bin/sh\nprintf '%s' 'rtk partial output'\nexit ${exitCode}\n`,
    )
    expect(await runRtkRewrite(rtkBin, "git status --short")).toBeNull()
  }
})

test("passes rewrite and the original command as separate RTK arguments", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-arguments-test-"))
  const argsLog = join(fixtureRoot, "args.log")
  const rtkBin = writeExecutable(
    "rtk",
    "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$RTK_ARGS_LOG\"\nprintf '%s' 'rtk git status --short'\n",
  )
  setEnvironment("RTK_ARGS_LOG", argsLog)

  expect(await runRtkRewrite(rtkBin, "git status --short")).toBe("rtk git status --short")
  expect(await Bun.file(argsLog).text()).toBe("rewrite\ngit status --short\n")
})

test("leaves commands unchanged for non-shell tools and invalid shell input", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-input-test-"))
  const argsLog = join(fixtureRoot, "args.log")
  const rtkBin = writeExecutable(
    "rtk",
    "#!/bin/sh\nprintf '%s\\n' called >> \"$RTK_ARGS_LOG\"\nprintf '%s' 'rtk rewritten'\n",
  )
  setEnvironment("RTK_BIN", rtkBin)
  setEnvironment("RTK_ARGS_LOG", argsLog)

  for (const [tool, command] of [
    ["read", "git status --short"],
    ["bash", "   "],
    ["shell", 42],
  ] as const) {
    expect(await tryRewriteCommand(tool, command)).toBeNull()
  }
  expect(await Bun.file(argsLog).exists()).toBe(false)
})

test("fails open when the RTK executable cannot launch", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-launch-test-"))
  const rtkBin = join(fixtureRoot, "not-executable")
  writeFileSync(rtkBin, "#!/bin/sh\nprintf '%s' 'rtk rewritten'\n")
  chmodSync(rtkBin, 0o644)

  expect(await runRtkRewrite(rtkBin, "git status --short")).toBeNull()
})

test("rejects partial output when the RTK process receives a signal", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-signal-test-"))
  const rtkBin = writeExecutable(
    "rtk",
    "#!/bin/sh\nprintf '%s' 'rtk partial output'\nkill -TERM $$\n",
  )

  expect(await runRtkRewrite(rtkBin, "git status --short")).toBeNull()
})

test("rejects partial output when the RTK process times out", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-timeout-test-"))
  const rtkBin = writeExecutable(
    "rtk",
    "#!/bin/sh\nprintf '%s' 'rtk partial output'\n/bin/sleep 2\n",
  )

  expect(await runRtkRewrite(rtkBin, "git status --short", 50)).toBeNull()
})

test("accepts mixed-case shell tool names and ignores missing hook containers", async () => {
  fixtureRoot = mkdtempSync(join(tmpdir(), "rtk-hook-event-test-"))
  const rtkBin = writeExecutable("rtk", "#!/bin/sh\nprintf '%s' 'rtk git status --short'\n")
  setEnvironment("RTK_BIN", rtkBin)

  let callback: ((event: any) => Promise<void>) | undefined
  await plugin.setup({
    tool: {
      hook: async (_name: string, registered: (event: any) => Promise<void>) => {
        callback = registered
      },
    },
  })

  const event = { tool: "ShElL", input: { command: "git status --short" } }
  await callback!(event)
  expect(event.input.command).toBe("rtk git status --short")
  await callback!(undefined)
  await callback!({ tool: "shell" })
  await callback!({ tool: "shell", input: null })
})
