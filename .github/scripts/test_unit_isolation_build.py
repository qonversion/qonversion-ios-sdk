import copy
import os
from pathlib import Path
import unittest
import sys
import tempfile
import time
from unittest.mock import patch, Mock
import signal
import json
import ast
import inspect
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

def cached_spec_fixture(folder):
    root=Path(folder)/'source';task=Path(folder)/'task'
    (root/'UnitTestSupport/Dependencies').mkdir(parents=True)
    original=Path(__file__).resolve().parents[2]/'UnitTestSupport/Dependencies/Podfile.lock'
    (root/'UnitTestSupport/Dependencies/Podfile.lock').write_bytes(original.read_bytes())
    (task/'tmp').mkdir(parents=True,mode=0o700)
    repo=task/'pod-repos';path=repo/'trunk/Specs/c/0/6/OCMock/3.9.4/OCMock.podspec.json'
    path.parent.mkdir(parents=True,mode=0o700)
    path.write_bytes((Path(__file__).parent/'fixtures/OCMock-3.9.4.podspec.json').read_bytes())
    return root,path,{'TMPDIR':str(task/'tmp'),'CP_REPOS_DIR':str(repo)}

class BuildOnlyTests(unittest.TestCase):
    def test_exact_public_cdn_spec_hash_and_existing_metadata_guard(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,path,env=cached_spec_fixture(tmp)
            with patch.dict(build.os.environ,env):spec=build.cached_ocmock_spec(root)
            self.assertEqual(build.hashlib.sha1(path.read_bytes()).hexdigest(),build.OCMOCK_SHA1)
            self.assertEqual(build.hashlib.sha256(path.read_bytes()).hexdigest(),build.OCMOCK_SHA256)
            self.assertEqual(build.validate_pods(pods()[0],spec)['version'],'3.9.4')
    def test_cached_spec_wrong_hash_version_size_and_lock_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,path,env=cached_spec_fixture(tmp);original=path.read_bytes()
            with patch.dict(build.os.environ,env):
                for value in [original+b' ',original.replace(b'3.9.4',b'3.9.5')]:
                    path.write_bytes(value)
                    with self.assertRaisesRegex(ValueError,'^Dependency spec hash rejected$'):build.cached_ocmock_spec(root)
                path.write_bytes(b'x'*65537)
                with self.assertRaisesRegex(ValueError,'^Dependency spec size rejected$'):build.cached_ocmock_spec(root)
                path.write_bytes(original)
                (root/'UnitTestSupport/Dependencies/Podfile.lock').write_text('  OCMock: '+'0'*40+'\n')
                with self.assertRaisesRegex(ValueError,'^Dependency spec lock rejected$'):build.cached_ocmock_spec(root)
    def test_missing_and_foreign_cache_fail_without_glob_or_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,path,env=cached_spec_fixture(tmp)
            with patch.dict(build.os.environ,env):
                path.unlink()
                with self.assertRaisesRegex(FileNotFoundError,'^Dependency cached spec missing$') as caught:
                    build.cached_ocmock_spec(root)
                self.assertEqual(build.failure_reason(caught.exception),'DEPENDENCY_SPEC_MISSING')
            for invalid in ['', 'relative/path', str(Path(tmp)/'foreign')]:
                with patch.dict(build.os.environ,{**env,'CP_REPOS_DIR':invalid}):
                    with self.assertRaisesRegex(ValueError,'^Dependency cache path rejected$'):build.cached_ocmock_spec(root)
    def test_spec_file_and_parent_symlinks_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root,path,env=cached_spec_fixture(tmp);copy=Path(tmp)/'public-copy.json';copy.write_bytes(path.read_bytes())
            with patch.dict(build.os.environ,env):
                path.unlink();path.symlink_to(copy)
                with self.assertRaisesRegex(ValueError,'^Dependency cache path rejected$'):build.cached_ocmock_spec(root)
                path.unlink();directory=path.parent;backup=directory.with_name('moved');directory.rename(backup);directory.symlink_to(backup,target_is_directory=True)
                with self.assertRaisesRegex(ValueError,'^Dependency cache path rejected$'):build.cached_ocmock_spec(root)
    def test_antecedent_missing_files_have_distinct_fixed_reasons(self):
        with tempfile.TemporaryDirectory() as tmp:
            for reason,enum in [('Dependency manifest missing','DEPENDENCY_MANIFEST_MISSING'),
                                ('Dependency project missing','DEPENDENCY_PROJECT_MISSING')]:
                with self.assertRaises(FileNotFoundError) as caught:build.required_dependency_file(Path(tmp)/'missing',reason)
                self.assertEqual(build.failure_reason(caught.exception),enum)
    def test_settings(self): self.assertTrue(build.validate_settings(settings())['isolation_flags_verified'])
    def test_settings_json_failure_and_guard_failure_have_distinct_reasons(self):
        for raw in [b'{"private":"secret"',b'\xff']:
            state={}
            with self.assertRaises(ValueError) as caught:build.inspect_settings(raw,state)
            self.assertEqual(build.failure_reason(caught.exception),'SETTINGS_JSON_REJECTED')
            self.assertEqual(state,{'settings_validation':{'schema':'INVALID_JSON'}})
        state={};rows=settings();rows[0]['buildSettings']['CONFIGURATION']='private-config'
        with self.assertRaises(ValueError) as caught:build.inspect_settings(json.dumps(rows),state)
        self.assertEqual(build.failure_reason(caught.exception),'SETTINGS_CONFIGURATION')
        self.assertFalse(state['settings_validation']['targets'][rows[0]['target']]['checks']['configuration'])
        self.assertNotIn('private',json.dumps(state))
    def test_each_settings_guard_still_rejects_with_specific_reason(self):
        mutations=[
            ('target','private-target','SETTINGS_UNEXPECTED_TARGET'),
            ('duplicate',None,'SETTINGS_DUPLICATE_TARGET'),
            ('missing',None,'SETTINGS_MISSING_TARGET'),
            ('CONFIGURATION','private','SETTINGS_CONFIGURATION'),
            ('PLATFORM_NAME','iphoneos','SETTINGS_PLATFORM'),
            ('CODE_SIGNING_ALLOWED','YES','SETTINGS_SIGNING'),
            ('GCC_PREPROCESSOR_DEFINITIONS','DEBUG=1','SETTINGS_OBJC_ISOLATION'),
            ('SWIFT_ACTIVE_COMPILATION_CONDITIONS','DEBUG','SETTINGS_SWIFT_ISOLATION'),
            ('TEST_HOST','/private/Sample.app/Sample','SETTINGS_TEST_HOST'),
            ('BUNDLE_LOADER','/private/other','SETTINGS_BUNDLE_LOADER'),
            ('PODS_ROOT','/private/Pods','SETTINGS_PODS_PATH'),
            ('PODS_PODFILE_DIR_PATH','/private','SETTINGS_PODFILE_PATH'),
            ('PRODUCT_BUNDLE_IDENTIFIER','private.customer','SETTINGS_HOST_IDENTITY')]
        for field,value,reason in mutations:
            with self.subTest(field=field):
                rows=settings()
                if field=='target':rows[0]['target']=value
                elif field=='duplicate':rows.append(copy.deepcopy(rows[0]))
                elif field=='missing':rows.pop()
                else:
                    name='QonversionUnitTestHost' if field=='PRODUCT_BUNDLE_IDENTIFIER' else 'QonversionTests'
                    next(r for r in rows if r['target']==name)['buildSettings'][field]=value
                with self.assertRaises(ValueError) as caught:build.inspect_settings(json.dumps(rows),{})
                self.assertEqual(build.failure_reason(caught.exception),reason)
    def test_owned_settings_descriptor_and_dependency_messages_have_fixed_enums(self):
        for validator in [build.validate_settings,build.validate_xctestrun,build.validate_pods]:
            for node in ast.walk(ast.parse(inspect.getsource(validator))):
                if isinstance(node,ast.Call) and isinstance(node.func,ast.Name) and node.func.id=='require':
                    self.assertIsInstance(node.args[1],ast.Constant)
                    self.assertNotEqual(build.failure_reason(ValueError(node.args[1].value)),'VALIDATION_REJECTED')
        self.assertEqual(build.failure_reason(RuntimeError('private-path/token')),'BUILD_STAGE_ERROR')
        self.assertEqual(build.failure_reason(ValueError('Wrong resolved test host: private')),'VALIDATION_REJECTED')
    def test_settings_summary_schema_unknown_names_duplicates_and_limits(self):
        for value,kind in [(None,'NULL'),({},'OBJECT'),('private','STRING'),(1,'NUMBER'),(True,'BOOLEAN')]:
            self.assertEqual(build.settings_summary(value)['schema'],kind)
            self.assertNotIn('private',json.dumps(build.settings_summary(value)))
        rows=settings()+[{'target':'private-target','buildSettings':{'TOKEN':'secret'}},None,settings()[0]]
        summary=build.settings_summary(rows)
        self.assertEqual(summary['unknown_targets'],1);self.assertEqual(summary['malformed_rows'],1)
        self.assertEqual(summary['target_counts']['Qonversion'],2)
        self.assertEqual(set(summary['targets']),build.EXPECTED)
        raw=json.dumps(summary)
        for private in ['private','secret','TOKEN','/derived','io.qonversion','/source']:self.assertNotIn(private,raw)
        summary=build.settings_summary([{'target':'private'}]*1000)
        self.assertEqual(summary['rows'],1000);self.assertEqual(summary['inspected_rows'],64)
        self.assertEqual(summary['unknown_targets'],64);self.assertTrue(summary['truncated'])
    def test_settings_nonstring_fields_are_diagnostic_only_not_coerced(self):
        rows=settings();rows[0]['buildSettings']['GCC_PREPROCESSOR_DEFINITIONS']=['private']
        state={}
        with self.assertRaises(AttributeError) as caught:build.inspect_settings(json.dumps(rows),state)
        detail=state['settings_validation']['targets'][rows[0]['target']]
        self.assertEqual(detail['types']['GCC_PREPROCESSOR_DEFINITIONS'],'ARRAY')
        self.assertIsNone(detail['checks']['objc_isolation'])
        self.assertEqual(build.failure_reason(caught.exception),'BUILD_STAGE_ERROR')
        self.assertNotIn('private',json.dumps(state))
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
    def test_settings_query_selects_testing_action_without_changing_build_options(self):
        derived=Path('/tmp/synthetic-derived')
        args=build.settings_command(derived)
        self.assertEqual(args[:-3],build.build_command(derived))
        self.assertEqual(args[-3:],['build-for-testing','-showBuildSettings','-json'])
        for action in ['test','test-without-building','build','run','archive']:
            self.assertNotIn(action,args)
        self.assertEqual(args[args.index('-destination')+1],'generic/platform=iOS Simulator')
        self.assertEqual(args[args.index('-configuration')+1],'UnitIsolation')
        self.assertIn('CODE_SIGNING_ALLOWED=NO',args)
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
    def test_verbose_pod_output_limit_stops_process_and_caps_private_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'private.log'
            with self.assertRaisesRegex(ValueError,'^Native dependency output exceeded limit$') as caught:
                build.bounded([sys.executable,'-c','import sys,time; sys.stdout.write("synthetic-private"*10000); sys.stdout.flush(); time.sleep(60)'],tmp,1,log,output_limit=128)
            self.assertLessEqual(log.stat().st_size,128)
            self.assertEqual(build.failure_reason(caught.exception),'DEPENDENCY_OUTPUT_LIMIT')
    def test_verbose_pod_timeout_and_nonlog_cache_are_bounded_separately(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'private.log'
            build.bounded([sys.executable,'-c','from pathlib import Path; import sys; Path("cache").write_bytes(b"x"*(5*1024*1024)); print("ok"); print("private",file=sys.stderr)'],tmp,2,log,output_limit=128)
            self.assertEqual((Path(tmp)/'cache').stat().st_size,5*1024*1024)
            self.assertLessEqual(log.stat().st_size,128)
            with self.assertRaisesRegex(ValueError,'^Native build stage timed out$'):
                build.bounded([sys.executable,'-c','import time; time.sleep(60)'],tmp,.05,log,output_limit=128)
    def test_settings_streams_separate_and_failure_preserves_private_diagnostics(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)
            command=[sys.executable,'-c','import sys; print("[]"); print("synthetic-private-stderr",file=sys.stderr)']
            self.assertEqual(json.loads(build.bounded_settings(command,tmp,1,output)),[])
            self.assertEqual(json.loads((output/'settings-private.json').read_text()),[])
            self.assertIn('synthetic-private-stderr',(output/'settings-private.log').read_text())
            with self.assertRaisesRegex(ValueError,'^Native build command failed; inspect private build log$'):
                build.bounded_settings(
                    [sys.executable,'-c','import sys; print("[]"); print("xcodebuild: error: synthetic-private",file=sys.stderr); sys.exit(9)'],tmp,1,output)
            self.assertIn('synthetic-private',(output/'settings-private.log').read_text())
    def test_settings_shared_output_cap_and_deadline(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)
            with self.assertRaisesRegex(ValueError,'^Native settings output exceeded limit$') as caught:
                build.bounded_settings([sys.executable,'-c','import sys,time; sys.stdout.write("x"*80); sys.stdout.flush(); sys.stderr.write("y"*80); sys.stderr.flush(); time.sleep(60)'],tmp,1,output,output_limit=128)
            self.assertEqual(build.failure_reason(caught.exception),'SETTINGS_OUTPUT_LIMIT')
            self.assertLessEqual(sum((output/name).stat().st_size for name in ['settings-private.json','settings-private.log']),128)
            with self.assertRaisesRegex(ValueError,'^Native build stage timed out$'):
                build.bounded_settings([sys.executable,'-c','import time; time.sleep(60)'],tmp,.05,output)
    def test_settings_capture_interrupt_uses_owned_group_cleanup(self):
        selector=build.selectors.DefaultSelector()
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(build.selectors,'DefaultSelector',return_value=selector), \
                patch.object(selector,'select',side_effect=KeyboardInterrupt), \
                patch.object(build,'stop_owned_group',wraps=build.stop_owned_group) as stop:
            with self.assertRaises(KeyboardInterrupt):
                build.bounded_settings([sys.executable,'-c','import sys,time; print("ready",flush=True); time.sleep(60)'],tmp,1,Path(tmp))
            stop.assert_called_once()
            process=stop.call_args.args[0]
            self.assertIsNotNone(process.poll())
            self.assertTrue(process.stdout.closed and process.stderr.closed)
    def test_settings_timeout_kills_term_ignoring_descendant_after_leader_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);pid_file=root/'descendant.pid';heartbeat=root/'heartbeat'
            child_code=('import os,signal,time; from pathlib import Path; '
                        'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                        f'Path({str(pid_file)!r}).write_text(str(os.getpid())); '
                        f'p=Path({str(heartbeat)!r}); n=0\n'
                        'while True:\n n+=1; p.write_text(str(n)); time.sleep(.01)\n')
            parent_code=('import subprocess,sys,time; from pathlib import Path; '
                         f'subprocess.Popen([sys.executable,"-c",{child_code!r}]); '
                         f'p=Path({str(heartbeat)!r})\n'
                         'while not p.exists(): time.sleep(.01)\n'
                         'print("[]",flush=True); time.sleep(60)\n')
            real_killpg=os.killpg
            try:
                with patch.object(build.os,'killpg',wraps=real_killpg) as kills:
                    with self.assertRaisesRegex(ValueError,'^Native build stage timed out$'):
                        build.bounded_settings([sys.executable,'-c',parent_code],tmp,.5,root)
                    self.assertTrue(any(call.args[1]==signal.SIGKILL for call in kills.call_args_list))
                self.assertTrue(heartbeat.exists())
                time.sleep(.05);before=heartbeat.read_bytes();time.sleep(.15)
                self.assertEqual(heartbeat.read_bytes(),before)
            finally:
                if pid_file.exists():
                    try:os.kill(int(pid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError:pass
    def test_output_cap_kills_term_ignoring_descendant_after_leader_exits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);pid_file=root/'descendant.pid';heartbeat=root/'heartbeat'
            child_code=('import os,signal,time; from pathlib import Path; '
                        'signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                        f'Path({str(pid_file)!r}).write_text(str(os.getpid())); '
                        f'p=Path({str(heartbeat)!r}); n=0\n'
                        'while True:\n n+=1; p.write_text(str(n)); time.sleep(.01)\n')
            parent_code=('import subprocess,sys,time; from pathlib import Path; '
                         f'subprocess.Popen([sys.executable,"-c",{child_code!r}]); '
                         f'p=Path({str(heartbeat)!r})\n'
                         'while not p.exists(): time.sleep(.01)\n'
                         'sys.stdout.write("x"*65536); sys.stdout.flush(); time.sleep(60)\n')
            real_killpg=os.killpg
            try:
                with patch.object(build.os,'killpg',wraps=real_killpg) as kills:
                    with self.assertRaisesRegex(ValueError,'^Native dependency output exceeded limit$'):
                        build.bounded([sys.executable,'-c',parent_code],tmp,3,root/'private.log',output_limit=128)
                    self.assertTrue(any(call.args[1]==signal.SIGKILL for call in kills.call_args_list))
                time.sleep(.05);before=heartbeat.read_bytes();time.sleep(.15)
                self.assertEqual(heartbeat.read_bytes(),before)
            finally:
                if pid_file.exists():
                    try:os.kill(int(pid_file.read_text()),signal.SIGKILL)
                    except ProcessLookupError:pass
    def test_parent_interrupt_stops_and_reaps_group(self):
        child = Mock(pid=12345, stdout=Mock())
        child.communicate.side_effect = KeyboardInterrupt
        with patch.object(build.subprocess, 'Popen', return_value=child), patch.object(build.os, 'killpg') as kill:
            with self.assertRaises(KeyboardInterrupt): build.bounded(['synthetic-never-executed'], '.', 1)
            self.assertEqual([call.args for call in kill.call_args_list],[(12345,signal.SIGTERM),(12345,0),(12345,signal.SIGKILL)])
            self.assertEqual(child.wait.call_count,2)
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
    def test_pod_identifiers_and_counts_do_not_export_private_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'pods-private.log'
            log.write_text("\x1b[31m[!] There were changes to the lockfile in deployment mode:\x1b[0m\n"
                           "PRIVATE_ENV=synthetic-private-token /private/customer/project\n"
                           "[!] CDN: private-name URL couldn't be downloaded: https://private.invalid/token Response: 403 secret\n"
                           "certificate verify failed: /private/cert synthetic-private-token\n"
                           "ArgumentError - secret https://private.invalid/token\n")
            result=build.collect_pod_diagnostics(log)
            counts={row['category']:row['records'] for row in result['categories']}
            self.assertEqual(counts,{'DEPLOYMENT_LOCKFILE_CHANGED':1,'CDN_DOWNLOAD_FAILED':1,
                                    'TLS_VERIFY_FAILED':1,'HTTP_403':1,'RUBY_ARGUMENT_ERROR':1})
            self.assertEqual(result['unmatched_lines'],1)
            raw=json.dumps(result)
            for value in [tmp,'PRIVATE_ENV','synthetic','private-name','private.invalid','/private','secret']:
                self.assertNotIn(value,raw)
    def test_xcode_categories_preserve_no_paths_or_free_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'settings-private.log'
            log.write_text('error: Unable to open base configuration reference file /private/token.xcconfig\n'
                           'xcodebuild: error: Scheme private-customer is not currently configured for the build action.\n'
                           'xcodebuild: error: Unable to find a destination matching secret-device\n'
                           'error: SDK private-sdk cannot be located at https://private.invalid/token\n'
                           'xcodebuild: error: other-private-cause\n')
            result=build.collect_xcode_diagnostics(log)
            self.assertEqual({r['category']:r['records'] for r in result['categories']},
                {'XCCONFIG_MISSING':1,'SCHEME_ACTION_UNAVAILABLE':1,'DESTINATION_NOT_FOUND':1,'SDK_NOT_FOUND':1})
            self.assertEqual(result['unclassified_error_lines'],1)
            raw=json.dumps(result)
            for private in ['private','token','secret','https:']:self.assertNotIn(private,raw)
    def test_xcode_diagnostics_are_bounded_and_unknown_is_not_invented(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'settings-private.log'
            log.write_bytes(b'x'*(4*1024*1024)+b'\n'+b'progress\n'*11000+
                            b'xcodebuild: error: synthetic-private\n'*1001)
            result=build.collect_xcode_diagnostics(log)
            self.assertTrue(result['truncated']);self.assertEqual(result['categories'],[])
            self.assertEqual(result['unclassified_error_lines'],999)
            self.assertLess(len(json.dumps(result)),2048)
    def test_pod_unknown_errors_remain_unknown_without_raw_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'pods-private.log'
            log.write_text('[!] Unknown synthetic-private-token\n### Error\nSyntheticError: other-secret\n')
            result=build.collect_pod_diagnostics(log)
            self.assertEqual(result['categories'],[])
            self.assertEqual(result['unclassified_error_lines'],2)
            self.assertEqual(result['unmatched_lines'],3)
            self.assertNotIn('SyntheticError',json.dumps(result))
            self.assertFalse(build.collect_pod_diagnostics(Path(tmp)/'missing')['available'])
    def test_nested_cocoapods_cache_cause_is_classified_without_private_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'pods-private.log'
            log.write_text("[!] Unable to add a source with url `https://secret.invalid` named `secret`.\n"
                           "(Could not create '/private/customer/repos', the CocoaPods repo cache directory.\n"
                           "Errno::EACCES: Permission denied - /private/customer/repos)\n")
            result=build.collect_pod_diagnostics(log)
            self.assertEqual({r['category']:r['records'] for r in result['categories']},
                             {'SOURCE_SETUP_FAILED':1,'COCOAPODS_CACHE_CREATE_FAILED':1,'FILESYSTEM_ACCESS_DENIED':1})
            for private in ['secret','customer','/private','https:']:self.assertNotIn(private,json.dumps(result))
    def test_pod_tail_line_and_count_limits_preserve_late_diagnostics(self):
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'pods-private.log'
            log.write_bytes(b'x'*(4*1024*1024)+b'\n'+b'progress\n'*11000+
                            b'private'+b'x'*4096+b'\n'+b'LoadError secret\n'*1001)
            result=build.collect_pod_diagnostics(log)
            self.assertTrue(result['truncated'])
            self.assertEqual(result['categories'],[{'category':'RUBY_LOAD_ERROR','records':999}])
            self.assertLess(len(json.dumps(result)),2048)
    def test_dependency_failure_verdict_keeps_fixed_categories_and_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'new-output'
            def failed(root,args,state):
                state.update(stage='DEPENDENCY_INSTALL',head='0'*40,pod_version='1.16.2')
                (args.output/'pods-private.log').write_text('[!] Unable to find a target named `private-target` in project `/private/customer`\n')
                raise ValueError('Native build command failed; inspect private build log')
            with patch.object(sys,'argv',['unit_isolation_build.py','--expected-head','0'*40,'--output',str(output)]), \
                    patch.object(build,'run_build',side_effect=failed),patch('builtins.print'):
                with self.assertRaises(SystemExit):build.main()
            raw=(output/'build-verdict.json').read_text();result=json.loads(raw)
            self.assertEqual(result['status'],'BUILD_ONLY_FAILED')
            self.assertEqual(result['dependency_diagnostics']['categories'],[{'category':'TARGET_NOT_FOUND','records':1}])
            self.assertNotIn('private',raw);self.assertLessEqual(len(raw.encode()),8192)
    def test_settings_failure_verdict_keeps_safe_classification_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'new-output'
            def failed(root,args,state):
                state.update(stage='RESOLVED_SETTINGS',head='0'*40,pod_version='1.16.2')
                (args.output/'settings-private.log').write_text('error: Unable to open base configuration reference file /private/token.xcconfig\n')
                (args.output/'settings-private.json').write_text('{"ENV":"synthetic-private"}')
                raise ValueError('Native build command failed; inspect private build log')
            with patch.object(sys,'argv',['unit_isolation_build.py','--expected-head','0'*40,'--output',str(output)]), \
                    patch.object(build,'run_build',side_effect=failed),patch('builtins.print'):
                with self.assertRaises(SystemExit):build.main()
            raw=(output/'build-verdict.json').read_text();result=json.loads(raw)
            self.assertEqual(result['status'],'BUILD_ONLY_FAILED')
            self.assertEqual(result['settings_diagnostics']['categories'],[{'category':'XCCONFIG_MISSING','records':1}])
            self.assertNotIn('private',raw);self.assertLessEqual(len(raw.encode()),8192)
            workflow=(Path(__file__).resolve().parents[2]/'.github/workflows/isolated-frozen-build.yml').read_text()
            self.assertNotIn('settings-private',workflow)
    def test_settings_predicates_survive_warning_flood_within_verdict_cap(self):
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'new-output';relative='Sources/'+('a'*190)+'.m'
            def failed(root,args,state):
                state.update(stage='RESOLVED_SETTINGS',head='0'*40,pod_version='1.16.2',tracked=[relative])
                (args.output/'settings-private.log').write_text(''.join(
                    f'{root}/{relative}:{10000000-i}:10000000: warning: property synthetic-private not found\n' for i in range(20)) +
                    'No profiles for private; SDK private not found; no such module private; no buildable entries; '
                    'No space left on device; Permission denied; unable to find utility; runFirstLaunch; '
                    'dependency cycle; certificate verify failed\n')
                rows=settings()
                next(r for r in rows if r['target']=='QonversionTests')['buildSettings']['TEST_HOST']='/private/Sample.app/Sample'
                build.inspect_settings(json.dumps(rows),state)
            with patch.object(sys,'argv',['unit_isolation_build.py','--expected-head','0'*40,'--output',str(output)]), \
                    patch.object(build,'run_build',side_effect=failed),patch('builtins.print'):
                with self.assertRaises(SystemExit):build.main()
            raw=(output/'build-verdict.json').read_text();result=json.loads(raw)
            self.assertLessEqual(len(raw.encode()),8192)
            self.assertEqual(result['reason'],'SETTINGS_TEST_HOST')
            self.assertFalse(result['settings_validation']['targets']['QonversionTests']['checks']['dedicated_host_suffix'])
            self.assertTrue(result['diagnostics']['truncated'])
            self.assertFalse(result['sdk_executed']);self.assertFalse(result['tests_executed'])
            for private in ['synthetic-private','/private','Sample.app','/derived','/source']:
                self.assertNotIn(private,raw)
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
            self.assertNotIn('dependency_diagnostics',result)
            self.assertFalse(result['sdk_executed']);self.assertNotIn('synthetic-private-token',raw)
            self.assertLessEqual(len(raw.encode()),8192)
    def test_oversized_verdict_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError,'exceeds limit'):build.write_verdict(Path(tmp),{'bad':'x'*8192})
            self.assertFalse((Path(tmp)/'build-verdict.json').exists())
    def test_pod_version_and_install_use_same_resolved_executable(self):
        state={};root=Path('/synthetic-source')
        with patch.object(build.shutil,'which',return_value='/synthetic-tools/pod') as which,patch.object(build,'bounded',return_value=b'1.16.2\n') as run:
            command=build.pinned_pod_install_command(root,state)
            which.assert_called_once_with('pod')
            run.assert_called_once_with(['/synthetic-tools/pod','--version'],root,30)
            self.assertEqual(command,['/synthetic-tools/pod','install','--deployment','--verbose','--project-directory=UnitTestSupport/Dependencies'])
            self.assertEqual(state['pod_version'],'1.16.2')
    def test_wrong_pod_version_rejected_before_install_command(self):
        state={}
        with patch.object(build.shutil,'which',return_value='/synthetic-tools/pod'),patch.object(build,'bounded',return_value=b'1.17.0\n') as run:
            with self.assertRaisesRegex(ValueError,'version mismatch') as caught:build.pinned_pod_install_command(Path('/synthetic'),state)
            self.assertEqual(run.call_count,1);self.assertEqual(state['pod_version'],'1.17.0')
            self.assertEqual(build.failure_reason(caught.exception),'DEPENDENCY_VERSION_MISMATCH')
    def test_pod_free_text_is_not_exported_as_version(self):
        state={}
        with patch.object(build.shutil,'which',return_value='/synthetic-tools/pod'),patch.object(build,'bounded',return_value=b'1.16.2 synthetic-private-token\n'):
            with self.assertRaisesRegex(ValueError,'not numeric'):build.pinned_pod_install_command(Path('/synthetic'),state)
            self.assertIsNone(state['pod_version'])
    def test_missing_pod_rejected_without_commands(self):
        with patch.object(build.shutil,'which',return_value=None),patch.object(build,'bounded') as run:
            with self.assertRaises(FileNotFoundError):build.pinned_pod_install_command(Path('/synthetic'),{})
            run.assert_not_called()

if __name__ == '__main__': unittest.main(verbosity=2)
