# Frozen tooling and build-only candidate (OPE-722)

The first build-only validation is enabled after root and independent source
review of the frozen candidate. Publication targets only this separate branch. It introduces no
SDK, host, test-source or existing workflow changes. Runtime tests and SDK launches
remain outside its scope; a successful build does not close OPE-722.

The accepted lock comes from Gate A run35162865985/attempt1 atc2469b4. Its SHA256 is
`08b51056c2bc276c84c9f99a4b277df6ae357e33efaf3cffcb63381efec36333`.
Independent read-only review matched all55 registry/package checksums,45 names
and57 dependency edges. The11 recorded platforms are lock metadata. Installation
requires the exact observed Ruby3.3.12/RubyGems4.0.20/arm64-darwin-24 tuple and
the existing checksum-verified Bundler2.6.9 bootstrap. No tooling upgrade/fallback,
lock update, checksum bypass, private source or global installation is allowed.

Before installation, pinned Bundler's lock parser/platform matcher must select
the exact45 locked name/version pairs, with ffi1.17.4-arm64-darwin and every other
spec on ruby. The precompiled ffi package contains the Ruby3.3 binary. A generic,
Linux or x86_64 ffi selection fails before installation. The frozen install uses
two jobs and one retry, with a300-second bound. Native extension compilation is
explicitly permitted for reviewed bigdecimal4.1.3, json3.0.2 and nkf0.3.0 tooling
gems. These Ruby/compiler operations are not sandboxed package execution and are
not SDK runtime. No additional extension-bearing package is accepted.
The isolated PATH includes the resolved Ruby directory and system build tools;
a missing compiler or build tool fails this tooling stage without a fallback.

After installation, the same exact selected set is checked again. Non-default
gems must come from the private bundle directory; the Bundler spec, if listed,
must come from its verified bootstrap. A Ruby default gem may be reused only at
the exact locked name/version/platform and from the observed runtime's default
gem directory. Such reuse is reported explicitly with its source class; it is
never represented as a downloaded archive verification. All other ambient gem
paths are rejected. The Gemfile/lock are checked again after each mutating stage.

A temporary CocoaPods binstub provides the only pod executable on the selected
PATH. The existing build-only helper is invoked unchanged in the same Python
process under the isolated environment; its1.16.2 version check, exact OCMock3.9.4
lock, generated-target validation, source-clean guard, build-for-testing command
and xctestrun checks remain mandatory. SIGTERM is converted to KeyboardInterrupt
so the existing child's bounded cleanup runs. Environment/arguments/signals are
restored on return. No test, simulator launch, Sample/NoCodes init or release runs.

The new workflow triggers only on codex/ope722-frozen-build pushes, with read-only
repository permission and pinned checkout/upload actions. Existing exact-branch
workflows match other branches; Checks still requires a PR. Do not open a PR as
part of this first build-only validation. Job timeout is35minutes; individual
tooling/build operations retain their own smaller deadlines and cleanup.

Artifacts contain only the existing sanitized build-verdict.json and a tooling
receipt capped at8KiB. No private logs, package archives, generated binaries,
DerivedData, environment or credentials are uploaded. Compiler diagnostics stay
under the previously reviewed bounded tracked-file/category policy.

Native assumptions are still unverified: dependency compilation on this exact
runner, pinned Bundler platform-query behavior, OCMock project generation and
Objective-C/Swift build compatibility. Offline negative tests establish the
candidate's intended stopping conditions, not native success or runtime isolation.
