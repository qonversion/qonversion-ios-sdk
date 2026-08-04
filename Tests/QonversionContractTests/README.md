# Contract tests

The guard that the backend has not drifted away from what this SDK expects.

The real assembly, services, network stack and decoders run against a **real**
backend over a real socket — nothing is stubbed. Every assertion is about what
the SDK ends up holding after decoding, not about raw JSON.

```bash
# from the dev repo, which brings the local stack's fixtures up first
tests/integration/v4sdk/run-sdk-contract.sh

# or directly, against any backend
QON_CONTRACT_BASE_URL=http://localhost:7101 \
QON_CONTRACT_API_KEY=<project access token> \
swift test --filter QonversionContractTests
```

Without `QON_CONTRACT_BASE_URL` every test **skips**, so a plain `swift test`
stays a fully offline run.

## Why this layer exists

The unit and integration suites stub HTTP. They prove the SDK behaves correctly
*given a response of the agreed shape* — they cannot notice when the backend
stops producing that shape, because they are the ones producing it.

This suite closes that gap, and it is the only place where a real backend
response meets the real decoders.

## `unknown` is a failure here

Most decoded enums carry an `unknown` case so an unrecognised value degrades
instead of crashing someone's app. That tolerance is right at runtime and wrong
in a contract test: `source: "app_store"` instead of `"appstore"` would decode
happily, land on `.unknown`, and every other assertion would still pass — which
is exactly how a broken contract ships unnoticed.

So `assertKnown` fails on any `.unknown` that came off the wire.

There is one deliberate exception, documented at `assertNoUnknownEnums`:
`renewState` on a **manual grant**. It is not decoded at all — the backend sends
a renew state only inside `product.subscription`, which a hand-granted
entitlement has none of, so the SDK derives it and deliberately derives
`.unknown`: claiming `.nonRenewable` would assert something nobody said. The
rule stays enforced for every store-backed entitlement.

## What is not covered

A successful purchase. It needs real App Store Connect credentials and a
genuinely signed JWS, neither of which exists on a local stack. What *is*
covered is the failure contract — an unconfirmable purchase must stay retryable,
because the SDK drops a purchase from its offline queue on a 4xx and the revenue
is then unrecoverable.

## Fixtures

Seeded by `tests/integration/v4sdk/seed.sh` in the dev repo: 25 linked
product/entitlement pairs (more than the dashboard page size, so a paginated
listing is visible as a mapping that lost entries), an experiment, a remote
configuration, and one fixture user carrying two entitlements of different
provenance — one granted by hand, one backed by a subscription with three stored
transactions and no receipt, which is what a transaction-native SDK produces.

## Keeping the suite honest

Every assertion here was checked by mutation — the expected value was broken on
purpose and the test had to turn red. The `unknown` rule was checked against the
live stack instead: the fixture's store source was changed in the database to a
value the SDK does not know, and the rule fired first. A test that survives its
own mutation asserts nothing; do the same before trusting a new one.
