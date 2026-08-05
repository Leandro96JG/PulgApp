# Architecture

## System Context

```text
Flutter phone
  |-- WebSocket/TCP 26760: identity, PIN, lobby, status, resume
  `-- UDP 26761: authenticated 60-byte full-state snapshots
           |
           v
WPF process
  |-- control host
  |-- UDP receiver
  |-- session coordinator and lobby
  |-- one serialized worker per virtual target
  `-- ViGEm adapters
           |
           v
ViGEmBus -> four X360 + four DS4 HID devices -> local Windows game
```

The WPF application is the only production process. Do not add a Windows Service or a separate network daemon in v1.

## Dependency Direction

```text
Pulgapp.Server.App
  -> Pulgapp.Server.Infrastructure
  -> Pulgapp.Server.Core
  -> Pulgapp.Server.Protocol

Pulgapp.Server.Infrastructure
  -> Pulgapp.Server.Core
  -> Pulgapp.Server.Protocol

Pulgapp.Server.Core
  -> Pulgapp.Server.Protocol only when it needs protocol value types

Pulgapp.Server.Protocol
  -> no repository project
```

`Core` must not reference WPF, ASP.NET Core, sockets, or Nefarius packages. Normal automated tests must execute without ViGEmBus installed.

## Windows Modules

### Protocol

Owns JSON message DTOs, validation, the UDP decoder, sequence arithmetic, constants, and fixture tests. It does not allocate sessions or targets.

### Core

Owns canonical input, slots, leases, session state, timeout policy, and the orchestration interface used by transports.

Required narrow seams:

```text
VirtualController
  Kind
  Connect()
  Apply(GamepadState)
  Neutralize()
  Disconnect()

VirtualControllerFactory
  Create(ControllerKind)
```

There are two real controller adapters, so this seam is not hypothetical. Tests use a fake adapter at the same seam.

`SessionCoordinator` is the transport-facing module. Transport code must not mutate lobby collections or ViGEm targets directly.

### Infrastructure

Owns Kestrel/WebSocket, UDP, ViGEm, configuration, logging, firewall diagnostics, and later mDNS. It adapts external systems to Core interfaces.

Use one process-wide `ViGEmClient`. Each created target has exactly one `SessionInputWorker` while connected or leased.

### App

Owns the WPF composition root, dashboard, view models, tray, and orderly shutdown. UI actions call the coordinator and never call ViGEm directly.

## Session And Input Flow

```text
WebSocket hello
  -> validate version and PIN/resume token
  -> atomically reserve lowest slot
  -> create target for slot kind
  -> connect target
  -> publish active session
  -> return welcome and UDP credentials

UDP datagram
  -> validate exact length/header
  -> look up session ID
  -> constant-time token check
  -> validate source IP
  -> discard duplicate/older sequence
  -> normalize impossible D-pad pairs
  -> enqueue latest state in capacity-one worker
  -> map complete report
  -> submit once
```

The worker channel retains only the newest pending state. It must never reorder states or call one target concurrently.

## Safety State Machine

```text
Free
  -> Connecting
  -> Active
  -> InputTimedOut (WebSocket alive, target neutral)
  -> Active (valid newer UDP resumes input)
  -> Reserved (control lost, target neutral, 15-second lease)
  -> Active (valid resume, same target, fresh tokens)
  -> Free (lease expiry, explicit leave, kick, or target failure)
```

Any transition away from `Active` neutralizes before doing cleanup. Shutdown order is: stop accepting joins, invalidate input sessions, neutralize all targets, disconnect targets, dispose sockets/host, dispose `ViGEmClient`.

## Mobile Modules

`GamepadInputModel` owns one immutable canonical snapshot. Widgets report pointer transitions to it; widgets never send network messages.

`ControllerConnection` owns both transports and exposes connection state plus `sendState`. UI code does not handle tokens or UDP endpoints.

`InputSendScheduler` sends changed state at no more than about 120 Hz and unchanged heartbeat every 50 ms. Lifecycle loss resets the model first, then sends redundant neutral snapshots and suspends control.

Use raw pointer IDs. Every control must handle down, move, up, and cancel. A control stays pressed while at least one owned pointer remains.

## Canonical Mapping

- Canonical X and Y are signed 16-bit; positive X is right and positive Y is up.
- Canonical triggers are unsigned 16-bit.
- X360 receives canonical Y unchanged.
- DS4 alone inverts Y while converting to byte-centered axes.
- Controller-specific names and report constants remain in Infrastructure adapters, not mobile or protocol state.

## Configuration And Data

Windows data lives under `%LocalAppData%/Pulgapp/`. Persist server identity and user settings, but never PINs or session tokens. Logs rotate and contain aggregate packet metrics, not per-packet payloads.

Mobile persists a client UUID, user preferences, and the last endpoint. A resume token may be retained only for its short lease lifetime. Do not persist the PIN by default.

## Observability

Per slot expose connection state, controller kind, client name, source IP, packet rate, estimated missing sequences, RTT, last valid input age, and XInput user index when ViGEm reports it. Never label a Pulgapp slot as the in-game player number.
