#!/usr/bin/env python3
"""Offline Gate B fixtures; no Ruby/gem/pod/Xcode installation or execution."""
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch
import frozen_toolchain_build as gate

ROOT = Path(__file__).resolve().parents[2]


def selection(installed=False):
    _, expected = gate.accepted_inputs(ROOT)
    rows = []
    for name, version in expected.items():
        row = {'name': name, 'version': version, 'platform': 'arm64-darwin' if name == 'ffi' else 'ruby'}
        if installed:
            row.update(isolated=True, default=False, runtime_default_path=False, extensions=name in gate.NATIVE_EXTENSIONS)
        rows.append(row)
    return {'bundler': '2.6.9', 'specs': rows}, expected


class FrozenTests(unittest.TestCase):
    def test_disabled_candidate_launches_nothing(self):
        with patch.object(gate, 'EXECUTION_AUTHORIZED', False), \
                patch('sys.argv', ['candidate', '--expected-head', 'a' * 40]), patch.object(gate, 'tooling') as tooling, \
                patch.object(gate.subprocess, 'check_output') as command, redirect_stdout(io.StringIO()):
            self.assertEqual(gate.main(), 1)
        tooling.assert_not_called()
        command.assert_not_called()

    def test_accepted_lock_and_manifest_match(self):
        lock, expected = gate.accepted_inputs(ROOT)
        self.assertEqual(gate.toolchain.digest(lock), gate.LOCK_SHA)
        self.assertEqual(len(expected), 45)
        self.assertEqual(expected['ffi'], '1.17.4')

    def test_missing_and_changed_lock_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            directory = root / 'UnitTestSupport/Toolchain'
            directory.mkdir(parents=True)
            with self.assertRaises(FileNotFoundError):
                gate.accepted_inputs(root)
            (directory / 'Gemfile.lock').write_text('unreviewed')
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^ACCEPTED_LOCK_HASH$'):
                gate.accepted_inputs(root)

    def test_environment_frozen_isolated_and_no_ambient_overrides(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(os.environ, {
            'BUNDLE_FORCE_RUBY_PLATFORM': 'true', 'BUNDLE_DISABLE_CHECKSUM_VALIDATION': 'true',
            'BUNDLE_GEMFILE': '/unsafe/Gemfile', 'PRIVATE_TOKEN': 'private', 'RUBYOPT': '-runsafe'}):
            task = Path(folder)
            env = gate.frozen_environment(task, '/approved/bin/ruby')
            self.assertEqual(env['BUNDLE_FORCE_RUBY_PLATFORM'], 'false')
            self.assertEqual(env['BUNDLE_DISABLE_CHECKSUM_VALIDATION'], 'false')
            self.assertEqual(env['BUNDLE_FROZEN'], 'true')
            self.assertEqual(env['BUNDLE_DEPLOYMENT'], 'true')
            self.assertEqual(env['BUNDLE_GEMFILE'], str(task / 'Gemfile'))
            self.assertTrue(env['PATH'].startswith('/approved/bin:'))
            for key in ['PRIVATE_TOKEN', 'RUBYOPT', 'HOME']:
                self.assertNotIn(key, env)

    def test_exact_runtime_mismatch_stops_before_bootstrap(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.sys, 'platform', 'darwin'), \
                patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                patch.object(gate.toolchain, 'runtime_tuple', return_value={**gate.RUNTIME, 'ruby': '3.3.13'}), \
                patch.object(gate.toolchain, 'bootstrap') as bootstrap:
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^RUNTIME_TUPLE_MISMATCH$'):
                gate.tooling(ROOT, Path(folder), {})
            bootstrap.assert_not_called()

    def test_native_ffi_selection_and_all_versions(self):
        document, expected = selection()
        result = gate.validate_selection(document, expected)
        self.assertEqual(result['ffi_platform'], 'arm64-darwin')
        self.assertEqual(result['selected_names'], 45)
        for platform in ['ruby', 'x86_64-darwin', 'aarch64-linux-gnu']:
            changed = json.loads(json.dumps(document))
            next(row for row in changed['specs'] if row['name'] == 'ffi')['platform'] = platform
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_SPEC_PLATFORM$'):
                gate.validate_selection(changed, expected)
        document['specs'][0]['version'] = '0.0.0'
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_SPEC_VERSION$'):
            gate.validate_selection(document, expected)

    def test_generic_ffi_stops_before_install(self):
        document, _ = selection()
        next(row for row in document['specs'] if row['name'] == 'ffi')['platform'] = 'ruby'
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.sys, 'platform', 'darwin'), \
                patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                patch.object(gate.toolchain, 'runtime_tuple', return_value=gate.RUNTIME), \
                patch.object(gate.toolchain, 'bootstrap', return_value=['/ruby', '/bundle']), \
                patch.object(gate, 'metadata', return_value=document), patch.object(gate.toolchain, 'bounded') as command:
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_SPEC_PLATFORM$'):
                gate.tooling(ROOT, Path(folder), {})
            command.assert_not_called()

    def test_install_failure_stops_before_binstub_or_build(self):
        document, _ = selection()
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.sys, 'platform', 'darwin'), \
                patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                patch.object(gate.toolchain, 'runtime_tuple', return_value=gate.RUNTIME), \
                patch.object(gate.toolchain, 'bootstrap', return_value=['/ruby', '/bundle']), \
                patch.object(gate, 'metadata', return_value=document), \
                patch.object(gate.toolchain, 'bounded', side_effect=gate.toolchain.Rejected('COMMAND_FAILED')) as command:
            state = {}
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^COMMAND_FAILED$'):
                gate.tooling(ROOT, Path(folder), state)
            self.assertEqual(state['stage'], 'FROZEN_INSTALL')
            self.assertEqual(command.call_count, 1)
            self.assertEqual(command.call_args.args[0][:3], ['/ruby', '/bundle', 'install'])

    def test_lock_mutation_stops_before_post_install_metadata(self):
        document, _ = selection()
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            def mutate(*_): (task / 'Gemfile.lock').write_text('changed')
            with patch.object(gate.sys, 'platform', 'darwin'), patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                    patch.object(gate.toolchain, 'runtime_tuple', return_value=gate.RUNTIME), \
                    patch.object(gate.toolchain, 'bootstrap', return_value=['/ruby', '/bundle']), \
                    patch.object(gate, 'metadata', return_value=document) as metadata, patch.object(gate.toolchain, 'bounded', side_effect=mutate):
                with self.assertRaisesRegex(gate.toolchain.Rejected, '^FROZEN_LOCK_CHANGED$'):
                    gate.tooling(ROOT, task, {})
                self.assertEqual(metadata.call_count, 1)

    def test_installed_external_paths_and_unexpected_extensions_fail(self):
        document, expected = selection(installed=True)
        result = gate.validate_selection(document, expected, installed=True)
        self.assertEqual(result['runtime_default_gem_count'], 0)
        row = next(row for row in document['specs'] if row['name'] == 'base64')
        row.update(isolated=False, default=False, runtime_default_path=False)
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_SPEC_PATH$'):
            gate.validate_selection(document, expected, installed=True)
        row.update(default=True, runtime_default_path=True)
        self.assertEqual(gate.validate_selection(document, expected, installed=True)['runtime_default_gems'], [
            {'name': 'base64', 'version': expected['base64'], 'platform': 'ruby', 'source_class': 'runtime_default'}])
        row['extensions'] = True
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^UNEXPECTED_NATIVE_EXTENSION$'):
            gate.validate_selection(document, expected, installed=True)

    def test_bundler_spec_cannot_come_from_ambient_runtime(self):
        document, expected = selection(installed=True)
        row = {'name': 'bundler', 'version': '2.6.9', 'platform': 'ruby', 'bootstrap_path': False}
        document['specs'].append(row)
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_BUNDLER_SPEC_PATH$'):
            gate.validate_selection(document, expected, installed=True)
        row['bootstrap_path'] = True
        self.assertEqual(gate.validate_selection(document, expected, installed=True)['selected_names'], 45)

    def test_installed_metadata_uses_immutable_bootstrap_after_gem_home_changes(self):
        document, _ = selection(installed=True)
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            env = {'GEM_HOME': str(task / 'bundle'), 'BUNDLE_PATH': str(task / 'bundle')}
            bundle = ['/ruby', str(task / 'bootstrap/gems/bundler-2.6.9/exe/bundle')]
            with patch.object(gate.toolchain, 'bounded', return_value=(json.dumps(document).encode(), b'')) as command:
                gate.metadata('/ruby', bundle, gate.INSTALLED_METADATA, task, env, [task / 'bootstrap'])
            self.assertEqual(command.call_args.args[0][-1], str(task / 'bootstrap'))
            self.assertNotEqual(command.call_args.args[0][-1], env['GEM_HOME'])
            self.assertIn('File.realpath(ARGV.fetch(0))', gate.INSTALLED_METADATA)
            self.assertNotIn('ENV.fetch("GEM_HOME")', gate.INSTALLED_METADATA)

    def test_tooling_passes_verified_bootstrap_root_to_installed_query(self):
        before, _ = selection()
        after, _ = selection(installed=True)
        with tempfile.TemporaryDirectory() as folder, patch.object(gate.sys, 'platform', 'darwin'), \
                patch.object(gate.shutil, 'which', side_effect=['/ruby', '/gem']), \
                patch.object(gate.toolchain, 'runtime_tuple', return_value=gate.RUNTIME), \
                patch.object(gate.toolchain, 'bootstrap', return_value=['/ruby', '/bundle']), \
                patch.object(gate, 'metadata', side_effect=[before, after]) as metadata, \
                patch.object(gate.toolchain, 'bounded'), patch.object(gate, 'pod_environment', return_value={}):
            task = Path(folder)
            gate.tooling(ROOT, task, {})
            self.assertEqual(metadata.call_args_list[1].args[-1], [task / 'bootstrap'])

    def test_bundler_failures_have_distinct_fixed_reasons(self):
        document, expected = selection(installed=True)
        document['bundler'] = '2.7.0'
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_BUNDLER_RUNTIME_VERSION$'):
            gate.validate_selection(document, expected, installed=True)
        document['bundler'] = '2.6.9'
        row = {'name': 'bundler', 'version': '2.7.0', 'platform': 'ruby', 'bootstrap_path': True}
        document['specs'].append(row)
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_BUNDLER_SPEC_VERSION$'):
            gate.validate_selection(document, expected, installed=True)
        row.update(version='2.6.9', platform='arm64-darwin')
        with self.assertRaisesRegex(gate.toolchain.Rejected, '^SELECTED_BUNDLER_SPEC_PLATFORM$'):
            gate.validate_selection(document, expected, installed=True)

    def test_pod_binstub_is_temporary_executable_and_not_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            task = Path(folder)
            (task / 'bin').mkdir()
            pod = task / 'bin/pod'
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^POD_BINSTUB_PATH$'):
                gate.pod_environment(task, {'PATH': '/usr/bin'}, {})
            pod.write_text('#!/usr/bin/ruby\n')
            pod.chmod(0o700)
            env = gate.pod_environment(task, {'PATH': '/usr/bin'}, {})
            self.assertTrue(env['PATH'].startswith(str(task / 'bin') + ':'))
            pod.unlink()
            pod.symlink_to(ROOT / 'UnitTestSupport/Toolchain/Gemfile')
            with self.assertRaisesRegex(gate.toolchain.Rejected, '^POD_BINSTUB_PATH$'):
                gate.pod_environment(task, {'PATH': '/usr/bin'}, {})

    def test_build_helper_arguments_environment_and_restoration(self):
        before_env, before_argv = dict(os.environ), sys.argv
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / 'build'
            def fake_main():
                self.assertEqual(sys.argv, ['unit_isolation_build.py', '--expected-head', 'a' * 40, '--output', str(output)])
                self.assertEqual(dict(os.environ), {'PATH': '/temporary/bin:/usr/bin', 'COCOAPODS_DISABLE_STATS': 'true'})
                output.mkdir()
                (output / 'build-verdict.json').write_text(json.dumps({'status': 'BUILD_ONLY_PASS', 'head': 'a' * 40,
                    'sdk_executed': False, 'tests_executed': False, 'native_isolation_proven': False}))
            with patch.object(gate.build, 'main', side_effect=fake_main) as invoked:
                gate.existing_build('a' * 40, output, {'PATH': '/temporary/bin:/usr/bin', 'COCOAPODS_DISABLE_STATS': 'true'})
                invoked.assert_called_once()
        self.assertTrue(dict(os.environ) == before_env)
        self.assertIs(sys.argv, before_argv)

    def test_build_failure_and_interrupt_restore_environment(self):
        before = dict(os.environ)
        for error in [SystemExit(1), KeyboardInterrupt()]:
            with patch.object(gate.build, 'main', side_effect=error):
                with self.assertRaises((gate.toolchain.Rejected, KeyboardInterrupt)):
                    gate.existing_build('a' * 40, Path('/unused'), {'PATH': '/synthetic'})
            self.assertTrue(dict(os.environ) == before)

    def test_workflow_and_ruby_selection_scope(self):
        text = (ROOT / '.github/workflows/isolated-frozen-build.yml').read_text()
        self.assertIn('branches: [codex/ope722-frozen-build]', text)
        self.assertIn('contents: read', text)
        for forbidden in ['pull_request:', 'workflow_dispatch:', 'secrets.', 'test-without-building', 'simctl', 'fastlane']:
            self.assertNotIn(forbidden, text)
        self.assertIn('select_best_platform_match', gate.SELECT_FROM_LOCK)
        self.assertNotIn('require "ffi"', gate.SELECT_FROM_LOCK)
        self.assertNotIn('require "cocoapods"', gate.SELECT_FROM_LOCK)


if __name__ == '__main__':
    unittest.main()
