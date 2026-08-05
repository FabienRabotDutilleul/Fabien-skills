---
name: anti-sleep
description: Keep the Windows machine awake from WSL for a set duration or while a process runs.
disable-model-invocation: true
---

# Anti-Sleep (Windows depuis WSL)

Use the bundled launcher from this skill directory. It holds a Windows power
assertion (`SetThreadExecutionState`) via a hidden PowerShell process launched
**detached on the Windows side**, so it survives the agent shell, WSL restarts,
and `wsl --shutdown`. Always go through the launcher: a `powershell.exe` run
directly from a WSL shell dies with that shell.

Resolve `scripts/anti-sleep.sh` relative to this `SKILL.md`; never assume the
user's current directory.

## Required workflow

1. Inspect current state:

```bash
scripts/anti-sleep.sh status
```

2. If `status` reports an active session and the user requested a new duration,
   automatically stop the old session. **Never ask for confirmation.**

```bash
scripts/anti-sleep.sh stop
```

3. Start the new timer for the requested duration:

```bash
scripts/anti-sleep.sh start 10800    # 3 hours
```

To stay awake while a WSL process runs, use `start-pid` with the same
automatic replacement rule:

```bash
scripts/anti-sleep.sh start-pid <PID>
```

4. In a **separate tool/shell call after the start command has returned**, verify:

```bash
scripts/anti-sleep.sh verify
```

Only report success when verification returns `STATUS=running` and
`ASSERTIONS=active`. Confirm the Windows PID, flags, and wall-clock expiry.
If verification fails, run `stop` and do not claim the machine is protected.

## Assertion flags

The default is `-d -i`: keep the display on and prevent system sleep. Pass
explicit flags after the duration or PID when needed:

| Flags | Effect |
|---|---|
| `-i` | Prevent system sleep; display may turn off |
| `-d` | Keep the display on (implies `-i`) |

```bash
scripts/anti-sleep.sh start 10800 -i
```

## Status and stop

```bash
scripts/anti-sleep.sh status
scripts/anti-sleep.sh stop
```

The launcher tracks one exact Windows PID plus start time and expiry under
`%LOCALAPPDATA%\anti-sleep`. `stop` kills only that PID; Windows clears the
power assertion itself the moment the process dies.

## Notes

- `start-pid` polls the WSL PID every 20 s via `wsl.exe`; if the distro is
  down, the watcher sees the PID gone and exits, releasing the assertion.
- To double-check from the Windows side: `powercfg /requests` in an **admin**
  terminal lists active power requests.
- When the question is whether *processes kept running* rather than whether the
  machine slept — long agent runs that die during a lock, Modern Standby
  machines — measure it with the heartbeat probe in [`PROBE.md`](PROBE.md).
- If the launcher fails (interop disabled, PowerShell blocked), tell the user
  to plug in and disable sleep manually (Settings → System → Power) instead of
  starting an unreliable background job.
