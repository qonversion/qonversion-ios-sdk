# CocoaPods lock preparation (OPE-722, Gate A)

This branch-only workflow prepares a reviewable dependency lock. It does not run
CocoaPods, install its dependencies, build Xcode targets, or launch any SDK/test.
Gate B (frozen dependency installation and the existing build-only pipeline)
requires independent review of the generated lock and is not implemented here.

The actual earlier macOS run 35158696964/1 reported system CocoaPods 1.17.0,
while the isolated build requires 1.16.2. This preparation does not alter either
version or the existing unit-isolation workflow.

The only installed package is Bundler 2.6.9, from
`https://rubygems.org/downloads/bundler-2.6.9.gem`, verified before loading against
SHA256 `a25675ffbd055ae1186766cc1e120b4cf62588e88abb59b99c57e22b1c55c9eb`.
The [version metadata](https://rubygems.org/api/v2/rubygems/bundler/versions/2.6.9.json)
declares no runtime dependencies; only this bootstrap uses `--ignore-dependencies`.
Ruby >=3.1.0 and RubyGems >=3.3.3 are required. The resolved Ruby interprets the
resolved gem script and the exact temporary Bundler executable. No Ruby/Brew
installation, system/user gem modification, or fallback occurs.

All package/cache/config/log paths live in a new private `RUNNER_TEMP` subdirectory.
Ambient Ruby/Bundler settings, credentials and proxies are excluded. Registry
access remains ordinary verified HTTPS. This is not a sandbox for trusted Ruby
package code. The fixed Gemfile has one public source and exact CocoaPods/core
1.16.2 pins. `bundle lock --add-checksums` resolves metadata without installing
the resolved graph, as implemented by
[Bundler 2.6.9](https://github.com/rubygems/rubygems/blob/v3.6.9/bundler/lib/bundler/cli/lock.rb).

Limits: bootstrap download 30 seconds/5 MiB; bootstrap install 120 seconds;
lock resolution 180 seconds; private command output 4 MiB; job 10 minutes.
Timeout/interrupt kills and reaps the command process group. Logs are never
uploaded. Failure output contains fixed enums, not raw errors or environment.

The only artifacts are a <=8 KiB provenance JSON and, on successful validation,
Gemfile/Gemfile.lock (<=64 KiB). The lock must cover every spec with SHA256,
match the known CocoaPods/core package hashes, use only the public registry,
and cover the observed native macOS CPU/platform (exact or generic Darwin).
Pinned Bundler's [add_extra_platforms!](https://github.com/rubygems/rubygems/blob/v3.6.9/bundler/lib/bundler/spec_set.rb)
adds complete extra platforms and may generalize the local Darwin entry. Bounded
public Darwin/Linux variants are accepted as proposed lock metadata only. Every
platform variant and transitive package requires independent review before Gate B. A successful
`TOOLCHAIN_LOCK_PREPARED` receipt proves neither build success nor runtime isolation.

Only a push to `codex/ope722-toolchain-lock` starts this workflow. Existing Checks
has a PR trigger; existing Foundation/unit-isolation workflows match other exact
branches. Do not open a PR or enable their runtime lanes as part of preparation.
