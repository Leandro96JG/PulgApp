---
name: implement-pulgapp
description: Use when implementing Pulgapp, continuing plan.md, building a phase, or asking for the next project task. Enforces protocol, safety gates, evidence, and one-task-at-a-time execution.
---

# Implement Pulgapp

## Start Every Run

1. Read `AGENTS.md`, `plan.md`, and `protocol/protocol-v1.md` in that order.
2. Read `docs/architecture.md` and the acceptance document for the current phase.
3. Inspect manifests, lockfiles, CI, and the files owned by the next unchecked task.
4. Check the worktree and preserve unrelated user or agent changes.
5. State the exact task ID being executed. Work on one task unless the user explicitly names a larger scope.

## Choose Work

- Use `plan.md` Current Status and the first unchecked item in the current task.
- If those disagree, use the earliest unchecked task and repair Current Status in the same change.
- Do not cross a gate whose evidence is pending.
- Never perform or mark a human game/hardware observation yourself.
- If the next step requires driver installation, game access, a physical phone, or missing SDK approval, prepare everything possible and ask one concise blocker question.

## Implement

- Follow the module ownership and dependency direction in `docs/architecture.md`.
- Treat the protocol document and fixtures as immutable during ordinary implementation.
- Keep normal tests driver-free; put ViGEm and game checks in explicit diagnostics/smoke paths.
- Prefer the smallest implementation that satisfies the current task. Do not pre-build later phases.
- Preserve full-state input, per-target serialization, token validation, timeout neutralization, fixed slot types, and LAN-only security.
- Add dependencies only in the module that owns the external concern and pin them in the relevant lockfile.

## Verify

1. Run the narrowest test that proves the changed behavior.
2. Run the current module's full driver-free suite.
3. Run formatting/analyzers required by manifests or CI.
4. For protocol work, run both language fixture suites once both clients exist.
5. Never replace missing execution with a claim that code looks correct.

## Update The Plan

- Check an item only after its required implementation and verification pass.
- Add concise evidence with exact command, result, test count, and relevant relative artifact paths.
- Keep manual items unchecked and label them `pending human verification`.
- Update Current Status and Next Task before ending.
- Add newly established exact commands to `AGENTS.md`; remove stale commands when manifests change.

## Stop Conditions

Stop and report a blocker instead of improvising when:

- A requested change conflicts with `AGENTS.md` or protocol v1.
- The 60-byte fixture would need to change.
- Pummel Party fails the eight-player gate.
- ViGEm cannot create the required target type.
- A destructive action, driver installation, firewall elevation, or external distribution needs user approval.
