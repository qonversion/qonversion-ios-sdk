import copy
from pathlib import Path
import unittest
import sys
import tempfile
import time
from unittest.mock import patch, Mock
import signal
import json
import unit_isolation_build as build

def settings():
    rows = []
    for target in sorted(build.EXPECTED):
        value = {'CONFIGURATION': build.CONFIG, 'PLATFORM_NAME': 'iphonesimulator', 'CODE_SIGNING_ALLOWED': 'NO',
                 'GCC_PREPROCESSOR_DEFINITIONS': 'DEBUG=1 QN_UNIT_TEST_ISOLATION=1',
                 'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG QN_UNIT_TEST_ISOLATION',
                 'PRODUCT_BUNDLE_IDENTIFIER': 'io.qonversion.unit-test-host',
                 'TEST_HOST': '/derived/QonversionUnitTestHost.app/QonversionUnitTestHost',
                 'BUNDLE_LOADER': '/derived/QonversionUnitTestHost.app/QonversionUnitTestHost',
                 'PODS_ROOT': '/source/UnitTestSupport/Dependencies/Pods',
                 'PODS_PODFILE_DIR_PATH': '/source/UnitTestSupport/Dependencies'}
        rows.append({'target': target, 'buildSettings': value})
    return rows

def descriptor():
    return {'__xctestrun_metadata__': {'FormatVersion': 2}, 'TestConfigurations': [{'TestTargets': [{
        'BlueprintName': 'QonversionTests', 'TestHostPath': '__TESTROOT__/QonversionUnitTestHost.app',
        'TestBundlePath': '__TESTHOST__/PlugIns/QonversionTests.xctest', 'IsUITestBundle': False}]}]}

def pods():
    objects = {str(i): {'isa': 'PBXNativeTarget', 'name': name, 'buildConfigurationList': 'config'} for i,name in enumerate(sorted(build.PODS))}
    objects.update({'config': {'buildConfigurations': ['unit']}, 'unit': {'name': build.CONFIG}})
    return objects, {'name': 'OCMock', 'version': '3.9.4', 'source': {'git': 'https://github.com/erikdoe/ocmock.git', 'tag': 'v3.9.4'}}

class BuildOnlyTests(unittest.TestCase):
    def test_settings(self): self.assertTrue(build.validate_settings(settings())['isolation_flags_verified'])
    def test_generated_descriptor(self): self.assertTrue(build.validate_xctestrun(descriptor())['dedicated_host_verified'])
    def test_sample_resolved_host_rejected(self):
        rows = settings(); next(r for r in rows if r['target'] == 'QonversionTests')['buildSettings']['TEST_HOST'] = '/derived/Sample.app/Sample'
        with self.assertRaisesRegex(ValueError, 'host'): build.validate_settings(rows)
    def test_missing_resolved_flag_rejected(self):
        rows = settings(); rows[0]['buildSettings']['GCC_PREPROCESSOR_DEFINITIONS'] = 'DEBUG=1'
        with self.assertRaisesRegex(ValueError, 'ObjC'): build.validate_settings(rows)
    def test_watch_target_rejected(self):
        rows = settings() + [{'target': 'Watch Sample Watch App', 'buildSettings': {}}]
        with self.assertRaisesRegex(ValueError, 'Unexpected'): build.validate_settings(rows)
    def test_real_device_rejected(self):
        rows = settings(); rows[0]['buildSettings']['PLATFORM_NAME'] = 'iphoneos'
        with self.assertRaisesRegex(ValueError, 'Simulator'): build.validate_settings(rows)
    def test_integration_descriptor_rejected(self):
        doc = descriptor(); doc['TestConfigurations'][0]['TestTargets'].append({'BlueprintName': 'IntegrationTests'})
        with self.assertRaisesRegex(ValueError, 'suites'): build.validate_xctestrun(doc)
    def test_sample_descriptor_rejected(self):
        doc = descriptor(); doc['TestConfigurations'][0]['TestTargets'][0]['TestHostPath'] = '__TESTROOT__/Sample.app'
        with self.assertRaisesRegex(ValueError, 'host'): build.validate_xctestrun(doc)
    def test_unknown_descriptor_format_rejected(self):
        with self.assertRaisesRegex(ValueError, 'format'): build.validate_xctestrun({})
    def test_command_does_not_request_execution_or_signing(self):
        args = build.build_command(Path('/tmp/synthetic-derived'))
        self.assertNotIn('test', args); self.assertNotIn('test-without-building', args)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', args)
        self.assertNotIn('-allowProvisioningUpdates', args)
    def test_bounded_failure_does_not_expose_process_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, '^Native build command failed; inspect private build log$'):
                build.bounded([sys.executable, '-c', 'import sys; print("synthetic-private-output"); sys.exit(7)'], tmp, 1, Path(tmp)/'private.log')
    def test_bounded_timeout_terminates_process(self):
        before = time.monotonic()
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, '^Native build stage timed out$'):
                build.bounded([sys.executable, '-c', 'import time; time.sleep(60)'], tmp, 0.05)
        self.assertLess(time.monotonic()-before, 4)
    def test_parent_interrupt_stops_and_reaps_group(self):
        child = Mock(pid=12345, stdout=Mock())
        child.communicate.side_effect = KeyboardInterrupt
        with patch.object(build.subprocess, 'Popen', return_value=child), patch.object(build.os, 'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt): build.bounded(['synthetic-never-executed'], '.', 1)
            kill.assert_called_once_with(12345, signal.SIGTERM)
            child.wait.assert_called_once_with(timeout=3)
            child.stdout.close.assert_called_once()
    def test_pinned_dependency_graph(self): self.assertEqual(build.validate_pods(*pods())['dependency_shell_phases'], 0)
    def test_sample_dependency_rejected(self):
        objects,spec=pods(); objects['extra']={'isa':'PBXNativeTarget','name':'Pods-Sample'}
        with self.assertRaisesRegex(ValueError, 'targets'): build.validate_pods(objects,spec)
    def test_dependency_shell_script_rejected(self):
        objects,spec=pods(); objects['script']={'isa':'PBXShellScriptBuildPhase'}
        with self.assertRaisesRegex(ValueError, 'script'): build.validate_pods(objects,spec)
    def test_dependency_upgrade_rejected(self):
        objects,spec=pods(); spec['version']='3.9.5'
        with self.assertRaisesRegex(ValueError, 'version'): build.validate_pods(objects,spec)
    def test_dependency_install_hook_rejected(self):
        objects,spec=pods(); spec['prepare_command']='synthetic-not-executed'
        with self.assertRaisesRegex(ValueError, 'hooks'): build.validate_pods(objects,spec)
    def test_root_pods_path_rejected(self):
        rows=settings(); next(r for r in rows if r['target']=='QonversionTests')['buildSettings']['PODS_ROOT']='/source/Pods'
        with self.assertRaisesRegex(ValueError,'Pods path'):build.validate_settings(rows)
    def test_diagnostic_exposes_only_tracked_location_and_category(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); log=root/'private.log'
            log.write_text(f'{root}/Sources/Synthetic.swift:12:3: error: cannot find "synthetic-secret" https://private.invalid/key\nENV=synthetic-secret\n/untracked/file.swift:9:1: error: another secret\n')
            result=build.collect_diagnostics(log,root,['Sources/Synthetic.swift'])
            self.assertEqual(result['compiler'],[{'file':'Sources/Synthetic.swift','line':12,'column':3,'severity':'error','category':'UNKNOWN_SYMBOL'}])
            encoded=json.dumps(result)
            for private in [tmp,'synthetic-secret','private.invalid','untracked','ENV']:self.assertNotIn(private,encoded)
    def test_diagnostic_count_and_serialized_size_bound(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); log=root/'private.log'; relative='Sources/'+('a'*180)+'.m'
            log.write_text(''.join(f'{root}/{relative}:{i+1}:2: error: invalid synthetic\n' for i in range(30)))
            result=build.collect_diagnostics(log,root,[relative])
            self.assertEqual(len(result['compiler']),20);self.assertTrue(result['truncated'])
            self.assertLess(len(json.dumps(result).encode()),8192)
    def test_linker_only_emits_group_counts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);log=root/'private.log'
            log.write_text('Undefined symbols for architecture arm64:\n  "_synthetic_private_symbol" in /private/absolute/path\nclang: error: linker command failed with exit code 1\n')
            result=build.collect_diagnostics(log,root,[])
            self.assertEqual(result['linker'],[{'category':'LINK_UNDEFINED','records':1},{'category':'LINK_COMMAND_FAILED','records':1}])
            self.assertNotIn('synthetic',json.dumps(result));self.assertNotIn('/private',json.dumps(result))
    def test_late_error_has_priority_over_earlier_warning_flood(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);log=root/'private.log';relative='Sources/Synthetic.m'
            log.write_text(''.join(f'{root}/{relative}:{i+1}:2: warning: synthetic deprecated\n' for i in range(30)) + f'{root}/{relative}:999:4: fatal error: synthetic file not found\n')
            result=build.collect_diagnostics(log,root,[relative])
            self.assertEqual(len(result['compiler']),20);self.assertTrue(result['truncated'])
            self.assertEqual(result['compiler'][0],{'file':relative,'line':999,'column':4,'severity':'error','category':'MISSING_MODULE'})
    def test_unknown_failure_message_not_exported(self):
        self.assertEqual(build.failure_reason(ValueError('synthetic-private-token')), 'VALIDATION_REJECTED')
    def test_failed_build_writes_always_verdict(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'new-output'
            def failed(root,args,state):
                state.update(stage='BUILD_FOR_TESTING',head='0'*40,tracked=['Sources/Synthetic.swift'])
                (args.output/'build-private.log').write_text(f'{root}/Sources/Synthetic.swift:9:4: error: unknown type "synthetic-private-token"\n')
                raise ValueError('Native build command failed; inspect private build log')
            with patch.object(sys,'argv',['unit_isolation_build.py','--expected-head','0'*40,'--output',str(output)]),patch.object(build,'run_build',side_effect=failed),patch('builtins.print'):
                with self.assertRaises(SystemExit):build.main()
            raw=(output/'build-verdict.json').read_text();result=json.loads(raw)
            self.assertEqual(result['stage'],'BUILD_FOR_TESTING');self.assertEqual(result['reason'],'COMMAND_FAILED')
            self.assertFalse(result['sdk_executed']);self.assertNotIn('synthetic-private-token',raw)
            self.assertLessEqual(len(raw.encode()),8192)
    def test_oversized_verdict_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,'exceeds limit'):build.write_verdict(Path(tmp),{'bad':'x'*8192})
            self.assertFalse((Path(tmp)/'build-verdict.json').exists())

if __name__ == '__main__': unittest.main(verbosity=2)
