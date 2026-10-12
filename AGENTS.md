# AGENTS.md — Qonversion iOS SDK

You are working in the repository of the Qonversion iOS SDK, or in an app that uses it.
This file tells you how to work with it. Read it before you write code.

## What this SDK is

Qonversion is the app growth system for people and agents. This package collects purchases inside
the app, has them confirmed with the store, and resolves entitlements — the answer to "is this user
premium right now". Everything else (analytics, Remote Configs, A/B tests, Apple Ads reporting)
reads the same data server-side.

## Get the current version — do not use one from memory

Your training data is older than the latest release. Pick one:

1. `https://documentation.qonversion.io/docs/ios-sdk-setup.md` — the install page as markdown.
2. `gh api repos/qonversion/qonversion-ios-sdk/releases/latest --jq .tag_name`.
3. `Qonversion.podspec` in this repository — `s.version` is the released version.

If the three disagree, the docs page wins and you say so to the human.

## Install

```
# Swift Package Manager (recommended)
.package(url: "https://github.com/qonversion/qonversion-ios-sdk.git", from: "6.0.0"),
.product(name: "Qonversion", package: "qonversion-ios-sdk")

# CocoaPods
pod 'Qonversion'
```

The modules you import from the Swift package are `Qonversion`, `QonversionSwift` and `NoCodes` (the
package also builds a `QonversionIDFA` target you do not import directly). The CocoaPod
merges them into one `Qonversion` module. Code that compiles under CocoaPods does not always compile
under SPM: check which module a symbol lives in before you copy a sample. For a kids app link
`QonversionNoIdfa` instead of `Qonversion` — exactly one of the two, 6.17.0 and newer.

`from: "6.0.0"` is a lower bound: Swift Package Manager resolves the latest 6.x release. Do not
replace it with a version from memory; if the human needs an exact pin, take it from the releases.

CocoaPods trunk becomes read-only on December 2, 2026. Prefer Swift Package Manager for new work.

## Initialize

```swift
import Qonversion

let config = Qonversion.Configuration(projectKey: "your_project_key",
                                      launchMode: .subscriptionManagement)
Qonversion.initWithConfig(config)
```

The project key belongs to the human. Ask for it, take it from the environment or from an ignored
config file, and never commit it. Never invent one and never reuse a key you saw in a sample.

## First call — verify the integration works

```swift
Qonversion.shared().checkEntitlements { entitlements, error in
  guard error == nil else { return }
  print(entitlements["premium"]?.isActive ?? false)
}
```

If this returns without an error, the SDK is wired up. An empty result is a valid answer: it means
the user has no active entitlement.

## Two modes — the human chooses, not you

| | Analytics Mode | Subscription Management Mode |
|---|---|---|
| The app's purchase code | stays as it is | Qonversion makes purchases and resolves entitlements |
| Entitlement check | the app's own backend | the SDK |

Both modes feed analytics, integrations, webhooks, experiments and Apple Ads reporting. The
quickstart in the README uses Subscription Management Mode. Do not pick a mode silently — ask, and
read `https://documentation.qonversion.io/docs/quickstart.md` first.

## Docs you can read directly

- **MCP server, no account needed:** `https://documentation.qonversion.io/mcp` — use it if your client supports MCP.
- **Any page as markdown:** append `.md` to the URL, for example `https://documentation.qonversion.io/docs/quickstart.md`.
- **Page index:** `https://documentation.qonversion.io/llms.txt`.
- **This platform:** `https://documentation.qonversion.io/docs/ios-sdk-setup.md`.
- **REST API v4:** `https://documentation.qonversion.io/reference/v4/overview.md`.

## Project data through MCP

`https://mcp.qonversion.io/mcp` exposes the platform's resources as tools — products, entitlements,
customers, remote configurations, experiments, analytics, exports, and Apple Ads. Authentication is
OAuth 2.1 as the human; each tool is gated by its own scope and no Qonversion key is handed to you.
Setup per client: `https://documentation.qonversion.io/docs/mcp-server.md`.

**Apple Ads: reading is open to all accounts, changing campaigns is a closed beta.** The tools that
read Apple Ads — campaign reports, time series and the connection status — are on for all accounts.
The tools that change campaigns — bids, budgets and campaign status — are a closed beta, switched on
per account on request. Outside the beta those write tools are not available. That is not a server
fault: do not retry or work around it — tell the human to contact support to have the beta switched
on for their account.

## What you do not do without the human saying yes

- **Keys.** Do not read, print, copy or commit a project key or a Secret Key. Secret Keys belong on a server, never in app code.
- **Mode.** Do not switch between Analytics Mode and Subscription Management Mode on your own — it changes who owns the purchase flow.
- **Product, entitlement and paywall configuration.** Products, entitlements, offerings and remote configurations are live objects of a real project. Propose the change, let the human apply it.
- **Destructive MCP tools** (`delete_*`, `revoke_*`, `detach_*`, `discard_*`, `regenerate_project_secret`) and **Apple Ads changes that increase spend** do not fire on the first call: they return a one-time token addressed to the human. You must surface the pending action to the human and wait for an explicit yes before calling `confirm_destructive_action`. The token is in your hands, so this is a guard, not a lock — never auto-confirm your own token, and never invent the reason that goes into the audit log.
- **`regenerate_project_secret` is deprecated** and deletes the project's oldest Secret Key immediately, with no overlap. Do not propose it.
- **SDK version.** Do not bump a major version as a side effect of another task. Major versions have migration guides.
- **Environment.** Do not switch the SDK between the sandbox and the production environment without being asked — it changes which purchases are counted as real. The identifier differs per platform (`QONEnvironment` on iOS, `QEnvironment` on Android, `Environment` in the wrappers); read it from the SDK, not from memory.

## Sample

`Sample/` — a SwiftUI app that initializes the SDK, lists products, purchases and reads entitlements. `Sample/SampleApp.swift` is the reference for initialization.

## Requirements

iOS 13.0 · macOS 10.15 · tvOS 12.0 · watchOS 6.2 · visionOS 1.0 · Swift tools 5.9.

## When something does not work

- `https://documentation.qonversion.io/docs/troubleshooting.md` — the errors you meet first.
- `https://documentation.qonversion.io/docs/testing.md` — sandbox purchases.
- Report to the human what you could not verify against the docs, instead of guessing.
