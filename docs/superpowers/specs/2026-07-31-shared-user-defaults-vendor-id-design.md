# Shared UserDefaults and Vendor ID Design

## Goal

Make the main Qonversion SDK and NoCodes use the same configured persistence
domain and the same atomically created fallback vendor identifier.

## Public configuration

- `Qonversion.Configuration` keeps its existing
  `userDefaults: UserDefaults? = nil` parameter.
- `NoCodesConfiguration` gains the same
  `userDefaults: UserDefaults? = nil` parameter.
- A non-nil value is used exactly as supplied.
- A nil value resolves to the SDK-owned suite `io.qonversion.sdk`.
- `.standard` is no longer the normal default storage for either module.

## Shared implementation

The Qonversion target owns a single storage factory and fallback vendor-ID
resolver. NoCodes accesses the minimal required surface through an internal
Swift SPI instead of maintaining a duplicate implementation.

The resolver uses one process-wide lock in the Qonversion module. Under that
lock it:

1. returns an existing non-empty fallback;
2. otherwise returns a non-empty system vendor identifier;
3. otherwise generates, persists, and returns one UUID.

Once created, the fallback remains authoritative to avoid creating a second
backend device if IDFV later becomes available.

This guarantees one result across main-SDK and NoCodes resolver instances in
the same process. `UserDefaults` alone cannot guarantee an atomic
read-generate-write transaction between separate application/extension
processes when only a `UserDefaults` object, rather than its suite name or a
shared lock-file location, is provided.

## Default-suite migration

When the caller does not supply custom defaults, the main SDK performs a
one-time, allowlisted migration of Qonversion-owned keys from `.standard` to
the internal suite. Existing values in the destination win. Unrelated host
application settings are never copied.

The allowlist includes the unscoped SDK keys, API-key marker, project-scoped
products and request queues for the known stored/current API keys, and the
fallback vendor ID. NoCodes' first-launch marker is also migrated by NoCodes.
Source and source-version overrides remain in `.standard` because wrappers
may update them there on every launch; their latest values are synchronized
into the internal suite before headers are built. Clearing either override
also clears its stale internal-suite copy.

Custom defaults are not migrated because the caller-selected domain is the
source of truth.

## Verification

Tests must prove:

- custom defaults are preserved by both configurations;
- nil defaults resolve to the same internal suite;
- concurrent resolver instances return one generated UUID;
- main SDK and NoCodes use the same shared resolver behavior;
- an existing fallback remains authoritative;
- only SDK-owned keys migrate from `.standard`;
- existing destination values are not overwritten;
- unrelated application keys remain in `.standard`.
