# MEMORY - Pulgapp

Living memory, architectural decisions, and current state of the Pulgapp project.

---

## 1. Architectural Decisions (ADR)

- **Transport Architecture**:
  - **TCP / WebSocket (Puerto 26760)**: Handshake, PIN auth, lobby state, heartbeat de control, renegociación de sesión, reconexión y eventos de rumble (`rumble_v1`).
  - **UDP (Puerto 26761)**: Snapshots binarios de entrada idempotentes de 60 bytes a 120 Hz (`input-state-v1.bin`). Los deltas están prohibidos por diseño. Descarte de paquetes duplicados o desordenados mediante números de secuencia Little-Endian de 64 bits.
- **Topología de Mandos Virtuales (8 jugadores locales)**:
  - **Slots 1 a 4**: Mandos virtuales Xbox 360 / XInput (limitación externa de XInput en Windows).
  - **Slots 5 a 8**: Mandos virtuales DualShock 4 HID (vía DirectInput / Raw Input / SDL).
  - Emulación gestionada con `Nefarius.ViGEm.Client` (1.21.256) sobre ViGEmBus (1.22.0).
- **Seguridad y Neutralización de Entrada**:
  - Neutralización automática tras 250 ms sin recibir paquetes UDP válidos.
  - Neutralización inmediata ante pérdida de WebSocket, suspensión de la app, salida explícita o cierre del servidor.
  - Los reportes a ViGEm se envían completos con `AutoSubmitReport = false` para evitar reportes inconsistentes o botones atascados.
- **Cliente Mobile (Android-First con Flutter)**:
  - Layout táctil touch-first con joysticks flotantes dinámicos, D-Pad deslizable de 8 direcciones, gatillos analógicos/digitales y zonas de botones con gutters seguros.
  - Soporte de estilos de control intercambiables: Xbox (A/B/X/Y) y PlayStation 4 (Cross/Circle/Square/Triangle/L1/R1/L2/R2).
  - Emparejamiento rápido mediante escaneo QR (`pulgapp://pair?ip={ip}&port={port}&pin={pin}`) vía `mobile_scanner`.
- **Servidor Windows (.NET 10 WPF)**:
  - Interfaz moderna oscura tipo consola con panel de 8 slots en tiempo real, generador de QR, bandeja del sistema (`SystemTrayManager`), soporte de instancia única con named pipes (`SingleInstanceManager`) e inicio con Windows (`WindowsStartupManager`).

---

## 2. Estado Actual & Roadmap

### Fase Actual: P5 (Product UX And Optional Feedback)
- [x] **P0**: Validación de toolchains, spike de compatibilidad ViGEm/Pummel Party (Gate G0: PASS).
- [x] **P1**: Conexión end-to-end 1 cliente -> 1 X360 con neutralización por timeout (Gate G1: PASS).
- [x] **P2**: Soporte de 4 mandos X360 independientes y gestión de leases/reconexión (Gate G2: PASS).
- [x] **P3**: Soporte de mandos DS4 en slots 5-8 (Gate G3: simulador 8 clientes superado; prueba física de 2 horas aplazada por excepción autorizada).
- [x] **P4**: Descubrimiento mDNS y reconexión resiliente (Gate G4: PASS).
- [x] **P5-01 a P5-05**: Rediseño táctil ergonómico, perfiles locales, remapeo de botones, dead zones, vibración táctil nativa, rumble sobre WebSocket, emparejamiento QR, bandeja del sistema, single-instance y rediseño visual moderno.
- [x] **Release v1.0.0**: Tag y rama empujados a GitHub (`v1.0.0`), README moderno publicado y pipeline de CI/CD para compilación de ejecutables activo.
- [ ] **P5-06 (Siguiente Tarea)**: Verificación de áreas seguras y multitouch en teléfonos pequeños y tablets (Gate G5).
- [ ] **Fase P6**: Empaquetado formal con instalador WiX, reglas de firewall y hardening de release (Gate G6).

---

## 3. Lecciones Aprendidas (Learnings)

- **ViGEm Threading**: Todas las actualizaciones a un target de ViGEm deben serializarse; llamar a `SubmitReport()` concurrentemente corrompe el estado interno del controlador.
- **Ejes Y del Stick**: La especificación canónica de Pulgapp define Y positivo hacia arriba. El mapeador DS4 debe invertir Y en su capa de adaptación, mientras que X360 no lo hace.
- **Cross-drive en Flutter/Gradle**: En Windows, compilar con Gradle a través de rutas relativas entre unidades distintas puede fallar si la compilación incremental de Kotlin está activa; `kotlin.incremental=false` en `android/gradle.properties` garantiza compilaciones deterministas.
- **Aislamiento de Tests sin Driver**: Toda la lógica de protocolo, orquestación y mapeo se valida con fakes (`FakeVirtualController`), lo que permite que el 100% de los tests unitarios y de integración se ejecuten sin requerir el driver físico ViGEmBus en CI.

---

## 4. Convenciones y Comandos Clave del Proyecto

### Windows (.NET 10, x64)
- Restauración: `dotnet restore windows/Pulgapp.sln --force-evaluate`
- Compilación: `dotnet build windows/Pulgapp.sln --configuration Release --no-restore -p:Platform=x64`
- Tests Unitarios e Integración: `dotnet test windows/Pulgapp.sln --configuration Release --no-build -p:Platform=x64`
- Herramienta de Carga: `dotnet run --project windows/tools/Pulgapp.LoadGenerator/Pulgapp.LoadGenerator.csproj --configuration Release --no-build -p:Platform=x64 -- --clients 8 --rate-hz 120 --duration-seconds 10`

### Mobile (Flutter / Dart)
- Dependencias: `flutter pub get` (desde `mobile/`)
- Análisis estático: `flutter analyze --no-pub`
- Tests unitarios y de widgets: `flutter test --no-pub`
- Compilación debug APK: `flutter build apk --debug --no-pub`

### Distribución y Empaquetado de Releases
- Empaquetado Completo Local: `.\tools\package-release.ps1` (genera `Pulgapp-Server-win-x64.zip` y `Pulgapp-Android.apk` en `release/`)
- GitHub Actions CI/CD: `.github/workflows/release.yml` compila ambos artefactos y publica en GitHub Releases al crear tags `v*.*.*` o manualmente vía `workflow_dispatch`.
