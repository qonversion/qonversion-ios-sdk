# OPE-722: isolated unit host candidate

Status: local source/build-graph candidate. No native build or runtime test has run.
The separate Foundation proof on `857e81b` covers the scalar Attempt header only;
it does not validate this host, URLProtocol, StoreKit fakes, or the existing suite.
This branch does not change PR 762. Do not run the old `Checks`/Sample test path.

## Boundary and normal behavior

`QonversionUnitTests.xcscheme` builds only the Qonversion framework, the dedicated
UIKit host, and QonversionTests (plus the unit target's CocoaPods dependencies).
The host contains no SDK/NoCodes initialization, Sample sources, or watch target.
`UnitIsolation` sets both Objective-C and Swift flags on the SDK and unit target.
The normal Sample, integration, and framework Debug/Release settings are unchanged.
The offline preflight compares the normal SDK source projections against pinned
`857e81b501eb5ed68fbd54fb704948fe422c5f9b`; test-only code is compiled out there.

The mandatory factory replaces all six SDK session construction paths:
QNAPIClient, QONRedemptionManager, both NetworkProvider initializers,
ServicesAssembly.urlSession, and ImagePreloader's default session. It installs
one non-forwarding URLProtocol, disables cache/cookies/credentials/proxy state,
and rejects background sessions. Writable ObjC session setters and task creation
check session identity. Only explicit OCMock class fakes may be registered for the
existing memory-only APIClient tests; native NSURLSession objects cannot opt out.
Native confirmation of OCMock's runtime class is still required.

StoreKit observer registration goes to an in-memory queue before SDK init. Product,
payment, restore, redemption-sheet and receipt-refresh requests fail before native
request construction/start. Receipt reads return nil; storefront is deterministic.
StoreKit2 sequences/products fail before async platform access. NoCodes WebKit,
Safari and deep-link paths, and delayed Apple attribution collection, fail locally.
This is a unit-mode boundary, not a new production transport policy or a fix for
production TLS behavior.

Fixtures are exact method/URL matches, with at most 64 queued responses/requests,
1 MiB response bodies, a 15-second case budget, and a 2-second current-task drain.
Unmatched/expired/exhausted requests return a fixed non-transient error, with no
network fallback. Full request bodies/URLs remain private memory for synthetic
assertions and are never exported by the build helper.

Exactly **one fixture case may begin per host-process lifetime**. A second begin
fails even after finish. A task snapshot cannot prove future callback quiescence;
this restriction prevents a delayed callback from case A consuming case B's data.
Late requests remain denied. The late-A/second-B negative verifies this behavior.
Existing shared-process suite execution is intentionally blocked in `fastlane tests`.
Serial XCTest workers alone would not fix this. Integration tests retain their
separate original configuration and are not part of this candidate's execution.

## First native action: build only

1. Use a clean reviewed commit on a new branch, with no PR event or old Checks
   dispatch. The branch-only `isolated-unit-build.yml` is a separate review gate
   and has not been published or run.
   Do not use `fastlane tests`, `xcodebuild test`, `test-without-building`, `simctl`
   boot/launch, or the Sample scheme in this first stage.
2. On a macOS/Xcode runner, prepare dependencies with CocoaPods 1.16.2 and the
   checked-in lock. The helper uses a separate
   `UnitTestSupport/Dependencies/Podfile` and exact lock containing only OCMock
   3.9.4 (the same version/checksum as the existing unit dependency).
   `integrate_targets: false` generates Pods without modifying the user project.
   A checked-in isolated workspace and UnitIsolation-only xcconfig reference wire
   it in. The original Podfile/lock/workspace and their Sample/watch pods stay out
   of this build path. The helper requires CocoaPods 1.16.2, `--deployment`, an
   identical generated Manifest.lock, no tracked/untracked source changes, exactly
   OCMock + Pods-QonversionTests targets and no dependency shell phases/hooks.
   CocoaPods generation and Swift/Clang flag propagation are not proven on Linux.
   A failure stops before build; do not relax the lock or clean-tree gate.
3. Run the offline tests, then the build-only helper:

   ```sh
   PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/test_unit_isolation.py
   PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/test_unit_isolation_build.py
   PYTHONDONTWRITEBYTECODE=1 python3 .github/scripts/unit_isolation_build.py \
     --expected-head REVIEWED_40_HEX_COMMIT --output /tmp/ope722-build-only
   ```

   The helper rejects Linux, dirty input, wrong revision/config/flags, Sample/watch
   targets and wrong TEST_HOST. It inspects resolved settings, invokes only
   `build-for-testing`, then validates the generated xctestrun's sole unit target
   and dedicated host. Dependency timeout is 180 seconds, build timeout 900 seconds, settings timeout 90 seconds;
   timeout kills the child process group. Signing/provisioning are disabled.
   Unsupported xctestrun formats fail closed; review actual metadata rather than
   weakening validation. No Simulator or SDK application is launched.
4. Share only `build-verdict.json`, source hashes and sanitized compiler findings.
   Private build logs and generated products are not publication artifacts. A
   BUILD_ONLY_PASS explicitly says `native_isolation_proven: false`. On failure,
   the always-uploaded verdict records a fixed stage/reason enum and at most 20
   tracked relative source locations with line/column/severity/category. It never
   includes compiler free text, source excerpts, linker symbols, URLs, absolute
   paths, commands or environment. Linker findings are only category counts.
   The parser inspects at most the last 4 MiB of private build output and marks
   truncation; the complete verdict is capped at 8 KiB. Unknown diagnostics may
   need a later scoped follow-up; private logs are not uploaded.

## Later runtime stages — not authorized or implemented by this build helper

`native-stages.json` lists concrete individual selectors. Execute one selector in
one fresh host process per invocation; never select an entire class or suite.
A later runner must verify that XCTest executed exactly that one selector, exited,
and the next process is new. It must impose a whole-process deadline and collect
only aggregate counters/assertion outcomes. Do not infer a process reset from
serialized scheduling. The manifest is not a launcher or permission to dispatch.

- Stage 1: host identity, numeric IPv4 loopback positive control followed by denied
  guarded request, configuration override, injected native session, exhausted
  fixture and late-A/second-B negatives. The loopback canary certifies only this
  actual primitive/path; it is not a system-wide Simulator egress proof.
- Stage 2: fake StoreKit observer, blocked product/restore/attribution, StoreKit2,
  and secondary WebKit view construction. Confirm no native store request starts.
- Stage 3: real secondary SDK and NoCodes initialization with synthetic keys,
  isolated defaults and numeric loopback proxy. Detached NoCodes work is observed
  with a bounded wait, not claimed permanently drained. End the process afterward.
- Stage 4: existing tests, each in a new process, only after prior native evidence
  passes and the executor is reviewed. First select QRequestSerializerTests for
  PR 762. Redemption fixture conversion and OCMock compatibility need native
  validation. No full-suite completion, no release, and no OPE-722 closure yet.

Remaining native assumptions: CocoaPods/Xcode build graph after generation; Swift
import of the test-only ObjC header; URLProtocol interception for async URLSession;
actual XCTest selector and process isolation; lifecycle ordering in SDK/NoCodes;
StoreKit/WebKit negative assertions; OCMock runtime identity. A failing fixture or
compile error must be investigated, never converted into a network opt-out.

## Dependency/workflow provenance

The original lock records local Qonversion 6.9.0 while the pinned podspec is 6.14.0.
This candidate does not repair that unrelated general Sample dependency graph.
The isolated OCMock version/checksum comes from the existing lock. CocoaPods 1.16.2
source confirms that `integrate_targets: false` skips user-project integration but
keeps Pods generation, and takes explicit build configurations from the Podfile:
[installer](https://github.com/CocoaPods/CocoaPods/blob/1.16.2/lib/cocoapods/installer.rb),
[analyzer](https://github.com/CocoaPods/CocoaPods/blob/1.16.2/lib/cocoapods/installer/analyzer.rb).
The pinned [OCMock podspec](https://github.com/erikdoe/ocmock/blob/v3.9.4/OCMock.podspec)
has no prepare/build script hooks or child dependencies. Runtime installation still
has to pass the generated graph validator before xcodebuild.

At the parent revision, Checks runs only on PR open/synchronize/reopen; the old
Foundation workflow has a different exact push branch; release workflows are
manual/release/merged-release-PR; integration and stale-issue workflows are
scheduled/manual. A push only to `codex/ope722-unit-isolation`, without opening or
updating a PR, matches only the new build workflow. It uses pinned checkout/upload
actions, contents:read, no persisted checkout credential, no repository secrets, no
release step, no cache from Sample, and a 25-minute job deadline. Publish and native
execution remain owned by the parent operator after independent review.
