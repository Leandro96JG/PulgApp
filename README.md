# Pulgapp

Pulgapp will turn up to eight phones on a local network into independent Windows virtual gamepads: four Xbox 360/XInput targets and four DualShock 4 HID targets.

The repository currently contains the implementation contract, not application code. The first build task is the ViGEm and Pummel Party compatibility spike in `plan.md`.

## Agent Entry Point

OpenCode loads `AGENTS.md`, `plan.md`, and the protocol automatically through `opencode.json`.

Run the project command:

```text
/implement-next
```

This loads the local `implement-pulgapp` skill and executes the next unchecked task. Restart OpenCode after pulling or changing files under `.opencode/` so configuration-time changes are loaded.

For another coding agent, use the prompt in `docs/ai-handoff.md`.

## Documents

| File | Purpose |
|---|---|
| `AGENTS.md` | Non-negotiable product and safety constraints |
| `plan.md` | Ordered tasks, current status, and gates |
| `protocol/protocol-v1.md` | Normative wire protocol |
| `docs/architecture.md` | Module ownership and execution flow |
| `docs/acceptance.md` | Required evidence for each phase |
| `docs/compatibility-test.md` | Manual ViGEm/game gate procedure |
| `docs/development.md` | Toolchain prerequisites and test separation |
