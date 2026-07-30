# Shared UserDefaults and Vendor ID Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Qonversion and NoCodes share caller-selected or SDK-owned defaults and return one fallback vendor ID under concurrent initialization.

**Architecture:** The Qonversion target owns an SPI-visible defaults factory and vendor-ID resolver with a process-wide lock. Both public configurations carry an optional `UserDefaults`; nil resolves to the same SDK suite, while the main SDK performs an allowlisted migration from `.standard`.

**Tech Stack:** Swift 5.10, Foundation `UserDefaults`, XCTest, Swift Package Manager.

## Global Constraints

- Preserve the existing `Qonversion.Configuration(userDefaults:)` source API.
- Add the same optional parameter to `NoCodesConfiguration`.
- Use `io.qonversion.sdk` when the caller supplies no defaults.
- Never copy unrelated host application defaults.
- Keep all work local; do not commit or push.

---

### Task 1: Shared defaults resolution

**Files:**
- Create: `Sources/Other/LocalStorage/QonversionDefaults.swift`
- Modify: `Sources/Configuration.swift`
- Modify: `Sources/NoCodes/NoCodesConfiguration.swift`
- Modify: `Sources/Assemblies/QonversionAssembly.swift`
- Modify: `Sources/NoCodes/Assemblies/NoCodesAssembly.swift`
- Test: `Tests/QonversionUnitTests/ConfigurationTests.swift`
- Test: `Tests/NoCodesTests/ConfigurationTests.swift`

**Interfaces:**
- Produces: `QonversionDefaults.resolve(_:) -> UserDefaults`
- Produces: `NoCodesConfiguration.userDefaults: UserDefaults?`

- [x] Write tests showing custom defaults are preserved and nil defaults resolve to `io.qonversion.sdk`.
- [x] Run focused tests and confirm failures are caused by missing shared resolution and NoCodes configuration.
- [x] Implement the shared defaults factory and wire both assemblies.
- [x] Run focused tests and confirm they pass.

### Task 2: Shared atomic vendor-ID resolver

**Files:**
- Modify: `Sources/Services/Device/VendorIdResolver.swift`
- Delete: `Sources/NoCodes/Device/VendorIdResolver.swift`
- Modify: `Sources/NoCodes/Device/DeviceInfoCollector.swift`
- Test: `Tests/QonversionUnitTests/VendorIdResolverTests.swift`
- Test: `Tests/NoCodesTests/VendorIdResolverTests.swift`

**Interfaces:**
- Produces: SPI-visible `VendorIdResolver`
- Consumes: the exact `UserDefaults` selected by each assembly

- [x] Add a concurrent multi-instance test whose UUID providers produce distinct values but whose results must all be identical.
- [x] Add a NoCodes wiring test proving it uses the shared resolver over its configured defaults.
- [x] Run focused tests and confirm the concurrency test fails against instance-local locks.
- [x] Move resolver ownership to Qonversion, give it one static lock, and expose only the required SPI surface.
- [x] Run focused tests and confirm they pass.

### Task 3: Allowlisted standard-to-suite migration

**Files:**
- Create: `Sources/Other/LocalStorage/DefaultSuiteMigration.swift`
- Modify: `Sources/StorageConstants.swift`
- Modify: `Sources/Assemblies/QonversionAssembly.swift`
- Modify: `Sources/NoCodes/Assemblies/NoCodesAssembly.swift`
- Test: `Tests/QonversionUnitTests/DefaultSuiteMigrationTests.swift`
- Test: `Tests/NoCodesTests/DefaultSuiteMigrationTests.swift`

**Interfaces:**
- Produces: an idempotent migration that copies only known SDK keys when internal defaults are selected

- [x] Write tests for allowlisted copy, destination-wins semantics, idempotence, and unrelated-key exclusion.
- [x] Run focused tests and confirm they fail because migration does not exist.
- [x] Implement the minimum allowlisted migration and run it before services read storage.
- [x] Run focused tests and confirm they pass.

### Task 4: Full verification

**Files:**
- Modify documentation comments only where needed to match behavior.

- [x] Run `swift test` with isolated build and module-cache directories.
- [x] Run the NoCodes scheme for a generic iOS destination with code signing disabled.
- [x] Run `git diff --check`.
- [x] Inspect `git status --short` and confirm no unrelated files changed.
- [x] Run a read-only review of the completed diff and fix its actionable source-override finding.
