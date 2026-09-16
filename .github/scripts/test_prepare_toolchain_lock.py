#!/usr/bin/env python3
"""Offline Gate A failures. No gems downloaded/installed; no Apple runtime."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock
import prepare_toolchain_lock as gate


def lock_fixture():
    specs = '\n'.join('    ' + name + ' (1.16.2)' for name in gate.TOP_HASHES)
    sums = '\n'.join('  ' + name + ' (1.16.2) sha256=' + sha for name, sha in gate.TOP_HASHES.items())
    return (f'GEM\n  remote: https://rubygems.org/\n  specs:\n{specs}\n\n'
            'PLATFORMS\n  arm64-darwin-24\n  ruby\n\n'
            'DEPENDENCIES\n  cocoapods (= 1.16.2)\n  cocoapods-core (= 1.16.2)\n\n'
            f'CHECKSUMS\n{sums}\n\nBUNDLED WITH\n   2.6.9\n').encode()


class GateTests(unittest.TestCase):
    def test_valid_lock_has_exact_checksum_coverage(self):
        result = gate.validate_lock(lock_fixture())
        self.assertEqual(result['checksum_count'], result['spec_count'])
        self.assertEqual(result['spec_count'], 2)

    def test_bad_lock_sources_pins_checksums_and_extra_content_rejected(self):
        original = lock_fixture()
        cases = [
            original.replace(b'https://rubygems.org/', b'https://private.invalid/'),
            original.replace(b'GEM\n', b'GIT\n'),
            original.replace(b'GEM\n', b'PATH\n'),
            original.replace(b'(= 1.16.2)', b'(= 1.17.0)'),
            original.replace(b'   2.6.9', b'   2.7.0'),
            original.replace(b'CHECKSUMS\n', b'OTHER\n'),
            original.replace(gate.TOP_HASHES['cocoapods'].encode(), b'0' * 64),
            original.replace(b'  cocoapods (1.16.2) sha256=' + gate.TOP_HASHES['cocoapods'].encode() + b'\n', b''),
            original.replace(b'  ruby\n', b'  unknown-platform\n'),
            original + b'raw secret\n',
        ]
        for data in cases:
            with self.subTest(data_hash=gate.digest(data)), self.assertRaises(gate.Rejected):
                gate.validate_lock(data)

    def test_unchecksummed_transitive_gem_rejected(self):
        data = lock_fixture().replace(b'  specs:\n', b'  specs:\n    extra (1.0.0)\n')
        with self.assertRaisesRegex(gate.Rejected, '^LOCK_CHECKSUM_COVERAGE$'):
            gate.validate_lock(data)

    def test_duplicate_spec_or_checksum_rejected(self):
        for old, new in [(b'    cocoapods (1.16.2)\n', b'    cocoapods (1.16.2)\n' * 2),
                         (b'CHECKSUMS\n', b'CHECKSUMS\n  cocoapods (1.16.2) sha256=' + b'0' * 64 + b'\n')]:
            with self.assertRaises(gate.Rejected):
                gate.validate_lock(lock_fixture().replace(old, new))

    def test_oversized_or_non_ascii_lock_rejected(self):
        for data in [b'a' * 65537, b'\xff']:
            with self.assertRaises(gate.Rejected):
                gate.validate_lock(data)

    def test_resolver_added_platforms_are_metadata_and_native_coverage_still_required(self):
        data = lock_fixture().replace(b'  arm64-darwin-24\n', b'  arm64-darwin\n  x86_64-linux-gnu\n  aarch64-linux-musl\n')
        result = gate.validate_lock(data)
        gate.validate_native_coverage('arm64-darwin-24', result['platforms'])
        for platforms in [['ruby'], ['x86_64-darwin'], ['arm64-darwin-23'], ['x86_64-linux-gnu']]:
            with self.assertRaisesRegex(gate.Rejected, '^LOCK_RUNTIME_PLATFORM$'):
                gate.validate_native_coverage('arm64-darwin-24', platforms)

    def test_environment_drops_ambient_credentials_and_ruby_bundler_overrides(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            'BUNDLE_GEMFILE': '/untrusted/Gemfile', 'BUNDLE_CONFIG': 'secret',
            'RUBYOPT': '-runsafe', 'RUBYLIB': '/unsafe', 'GEM_HOME': '/unsafe',
            'HTTPS_PROXY': 'https://token.invalid', 'GITHUB_TOKEN': 'private',
        }):
            task = Path(folder)
            env = gate.isolated_environment(task)
            for key in ['RUBYOPT', 'RUBYLIB', 'BUNDLE_CONFIG', 'HTTPS_PROXY', 'GITHUB_TOKEN', 'HOME']:
                self.assertNotIn(key, env)
            self.assertEqual(env['BUNDLE_GEMFILE'], str(task / 'Gemfile'))
            self.assertEqual(env['BUNDLE_IGNORE_CONFIG'], 'true')
            for key in ['GEM_HOME', 'GEM_PATH', 'GEM_SPEC_CACHE', 'BUNDLE_PATH', 'BUNDLE_USER_HOME', 'BUNDLE_APP_CONFIG']:
                self.assertTrue(Path(env[key]).is_relative_to(task))

    def test_redirects_never_followed(self):
        for url in ['https://evil.invalid/gem', gate.PACKAGE_URL, 'http://rubygems.org/gem']:
            with self.assertRaisesRegex(gate.Rejected, '^BOOTSTRAP_REDIRECT$'):
                gate.NoRedirect().redirect_request(None, None, 302, '', {}, url)

    def test_wrong_download_hash_never_installed(self):
        with tempfile.TemporaryDirectory() as folder:
            response = Mock()
            response.__enter__ = Mock(return_value=response)
            response.__exit__ = Mock(return_value=False)
            response.geturl.return_value = gate.PACKAGE_URL
            response.read.side_effect = [b'not a trusted gem', b'']
            opener = Mock()
            opener.open.return_value = response
            with patch.object(gate.urllib.request, 'build_opener', return_value=opener), patch.object(gate, 'bounded') as command:
                with self.assertRaisesRegex(gate.Rejected, '^BOOTSTRAP_HASH$'):
                    gate.bootstrap('/ruby', '/gem', Path(folder), {})
                command.assert_not_called()
                self.assertFalse((Path(folder) / 'bundler.gem').exists())

    def test_download_uses_total_deadline_and_removes_it(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.urllib.request, 'build_opener') as opener, \
                patch.object(gate.signal, 'setitimer') as timer:
            opener.return_value.open.side_effect = OSError('private data')
            with self.assertRaises(OSError):
                gate.download_package(Path(folder) / 'gem')
            self.assertEqual(timer.call_args_list[0].args, (gate.signal.ITIMER_REAL, 30))
            self.assertEqual(timer.call_args_list[-1].args, (gate.signal.ITIMER_REAL, 0))

    def test_runtime_minimums_and_platform_fail_closed(self):
        good = {'ruby': '3.3.12', 'rubygems': '3.6.9', 'platform': 'arm64-darwin-24'}
        for key, bad in [('ruby', '3.0.9'), ('rubygems', '3.3.2'), ('ruby', 'secret'), ('platform', 'x86_64-linux')]:
            with patch.object(gate, 'bounded', return_value=json.dumps({**good, key: bad}).encode()):
                with self.assertRaises(gate.Rejected):
                    gate.runtime_tuple('/ruby', Path('/tmp'), {})
        with patch.object(gate, 'bounded', return_value=json.dumps(good).encode()) as command:
            self.assertEqual(gate.runtime_tuple('/ruby', Path('/tmp'), {}), good)
            self.assertEqual(command.call_args.args[0][:2], ['/ruby', '--disable=gems'])

    def test_only_verified_local_bundler_installed_and_same_ruby_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            bundle = task / 'bootstrap/gems/bundler-2.6.9/exe/bundle'
            bundle.parent.mkdir(parents=True)
            bundle.write_text('placeholder, never executed')
            def download(target): target.write_bytes(b'synthetic verified bytes')
            with patch.object(gate, 'download_package', side_effect=download), patch.object(gate, 'digest', return_value=gate.PACKAGE_SHA), \
                    patch.object(gate, 'bounded', return_value=b'Bundler version 2.6.9\n') as command:
                result = gate.bootstrap('/fixed/ruby', '/fixed/gem', task, {})
                install = command.call_args_list[0].args[0]
                self.assertEqual(install[:4], ['/fixed/ruby', '/fixed/gem', '--norc', 'install'])
                self.assertEqual(install[4], str(task / 'bundler.gem'))
                self.assertIn('--local', install)
                self.assertIn('--ignore-dependencies', install)
                self.assertEqual(result, ['/fixed/ruby', str(bundle)])
                self.assertEqual(command.call_args_list[1].args[0], result + ['--version'])

    def test_wrong_bundler_version_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            bundle = task / 'bootstrap/gems/bundler-2.6.9/exe/bundle'
            bundle.parent.mkdir(parents=True)
            bundle.touch()
            (task / 'bundler.gem').touch()
            with patch.object(gate, 'download_package'), patch.object(gate, 'digest', return_value=gate.PACKAGE_SHA), \
                    patch.object(gate, 'bounded', return_value=b'Bundler version 99.0.0'):
                with self.assertRaisesRegex(gate.Rejected, '^BUNDLER_VERSION$'):
                    gate.bootstrap('/ruby', '/gem', task, {})

    def test_resolve_invokes_lock_only_after_bootstrap(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            def resolve(command, *_):
                self.assertEqual(command, ['/ruby', '/bundle', 'lock', '--gemfile', str(task / 'Gemfile'), '--lockfile', str(task / 'Gemfile.lock'), '--add-checksums'])
                (task / 'Gemfile.lock').write_bytes(lock_fixture())
            with patch.object(gate.os, 'uname', return_value=Mock(sysname='Darwin')), \
                    patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                    patch.object(gate, 'runtime_tuple', return_value={'platform': 'arm64-darwin-24'}), \
                    patch.object(gate, 'bootstrap', return_value=['/ruby', '/bundle']), patch.object(gate, 'bounded', side_effect=resolve) as command:
                self.assertEqual(gate.prepare(root, task, {}), lock_fixture())
                self.assertEqual(command.call_count, 1)

    def test_failure_sanitizes_raw_command_output(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(gate.Rejected, '^COMMAND_FAILED$') as error:
                gate.bounded([sys.executable, '-c', 'print("private-token-and-url"); exit(1)'], Path(folder), {}, 5)
            self.assertNotIn('private', str(error.exception))

    def test_timeout_terminates_actual_child(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(gate.Rejected, '^COMMAND_TIMEOUT$'):
                gate.bounded([sys.executable, '-c', 'import time; time.sleep(30)'], Path(folder), {}, 0.05)

    def test_interrupt_terminates_group_and_reaps(self):
        process = Mock(pid=123, returncode=None)
        process.wait.return_value = 0
        selector = Mock()
        selector.select.side_effect = KeyboardInterrupt()
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.subprocess, 'Popen', return_value=process), patch.object(gate.os, 'killpg') as kill, \
                patch.object(gate.selectors, 'DefaultSelector', return_value=selector):
            with self.assertRaises(KeyboardInterrupt):
                gate.bounded(['synthetic'], Path(folder), {}, 1)
            self.assertEqual([call.args for call in kill.call_args_list], [(123, gate.signal.SIGTERM), (123, gate.signal.SIGKILL)])
            self.assertEqual(process.wait.call_count, 3)

    def test_command_output_limit_without_capping_dependency_cache_files(self):
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            code = 'from pathlib import Path; Path("cache").write_bytes(b"x"*5000000); print("ok")'
            self.assertEqual(gate.bounded([sys.executable, '-c', code], task, {}, 5), b'ok\n')
            with self.assertRaisesRegex(gate.Rejected, '^COMMAND_OUTPUT_LIMIT$'):
                gate.bounded([sys.executable, '-c', 'print("x"*5000000)'], task, {}, 5)

    def test_workflow_is_branch_only_and_contains_no_native_actions(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / '.github/workflows/isolated-toolchain-lock.yml').read_text()
        self.assertIn('branches: [codex/ope722-toolchain-lock]', workflow)
        self.assertIn('contents: read', workflow)
        for forbidden in ['pull_request:', 'workflow_dispatch:', 'secrets.', 'pod install', 'xcodebuild', 'simctl', 'fastlane', 'bundle install']:
            self.assertNotIn(forbidden, workflow)
        self.assertEqual((root / 'UnitTestSupport/Toolchain/Gemfile').read_bytes(), gate.GEMFILE)

    def test_invalid_temporary_path_emits_enum_without_traceback(self):
        environment = {**os.environ, 'RUNNER_TEMP': '/nonexistent-private-path', 'PYTHONDONTWRITEBYTECODE': '1'}
        result = subprocess.run([sys.executable, gate.__file__, '--expected-head', 'a' * 40],
                                env=environment, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, b'')
        self.assertEqual(json.loads(result.stdout)['reason'], 'RUNNER_TEMP_REQUIRED')
        self.assertNotIn(b'private-path', result.stdout)

    def test_existing_output_is_preserved_and_failure_is_sanitized(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'ope722-toolchain-lock-result'
            output.mkdir()
            sentinel = output / 'provenance.json'
            sentinel.write_text('previous result')
            environment = {**os.environ, 'RUNNER_TEMP': folder, 'PYTHONDONTWRITEBYTECODE': '1'}
            result = subprocess.run([sys.executable, gate.__file__, '--expected-head', 'a' * 40],
                                    env=environment, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, b'')
            self.assertEqual(json.loads(result.stdout)['reason'], 'UNEXPECTED_FAILURE')
            self.assertEqual(sentinel.read_text(), 'previous result')


if __name__ == '__main__':
    unittest.main()
