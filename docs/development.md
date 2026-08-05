# Development Environment

The projects have not been bootstrapped. Commands below are prerequisite checks only; `plan.md` P0-03 must add executable restore/build/test commands after manifests exist.

## Required Checks

```powershell
dotnet --info
flutter doctor -v
```

Expected baseline:

- x64 Windows 10 22H2 or Windows 11.
- .NET 10 LTS SDK.
- Stable Flutter SDK with Android toolchain.
- Android physical device with USB debugging for early tests.
- ViGEmBus 1.22.0 for diagnostics and hardware smoke tests only.

## Observed Prerequisites

Observed 2026-08-05 on x64 Windows 10 Pro 22H2 (build 19045):

- `dotnet --info`: .NET SDK 10.0.302 and .NET host 10.0.10, x64.
- `flutter doctor -v`: Flutter stable 3.44.8 with Dart 3.12.2; Android SDK platform 36 and accepted Android licenses are available. Visual Studio's Windows desktop workload is not installed, which is not required for the Android client or the .NET WPF host.
- Windows architecture: x64-based PC and 64-bit operating system.
- ViGEmBus: ViGEmBus package 1.22.0 is installed and the Nefarius virtual bus driver is detected.

Do not install toolchains, drivers, Visual Studio workloads, or Android SDK packages without user approval. Record a missing prerequisite as a blocker with the exact diagnostic output.

## Separation Of Test Types

- Driver-free tests must run in normal development and CI.
- Driver diagnostics require Windows x64, ViGEmBus, and interactive hardware inspection.
- Game compatibility requires a human, the installed game, and the procedure in `docs/compatibility-test.md`.
- Flutter widget/unit tests do not prove network, lifecycle, or multitouch behavior on a physical phone.
