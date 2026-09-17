#!/usr/bin/env python3
"""First native stage: inspect/build only. Never launches tests, SDK or simulator."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import selectors
import signal
import shutil
import subprocess
import sys
import time
from check_unit_isolation import verify, require
from openstep_read import parse

SCHEME = 'QonversionUnitTests'
CONFIG = 'UnitIsolation'
EXPECTED = {'Qonversion', 'QonversionTests', 'QonversionUnitTestHost'}
PODS = {'OCMock', 'Pods-QonversionTests'}

def validate_settings(rows):
    selected = {}
    for row in rows:
        target = row.get('target')
        require(target in EXPECTED | PODS, 'Unexpected resolved build target')
        if target in EXPECTED:
            require(target not in selected, 'Duplicate resolved target')
            selected[target] = row['buildSettings']
    require(set(selected) == EXPECTED, 'Missing resolved build targets')
    for target, settings in selected.items():
        require(settings.get('CONFIGURATION') == CONFIG, 'Wrong resolved configuration')
        require(settings.get('PLATFORM_NAME') == 'iphonesimulator', 'Build must target iOS Simulator')
        require(settings.get('CODE_SIGNING_ALLOWED') == 'NO', 'Signing must be disabled')
    for target in ['Qonversion', 'QonversionTests']:
        settings = selected[target]
        require('QN_UNIT_TEST_ISOLATION=1' in settings.get('GCC_PREPROCESSOR_DEFINITIONS', '').split(), 'Missing resolved ObjC isolation flag')
        require('QN_UNIT_TEST_ISOLATION' in settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '').split(), 'Missing resolved Swift isolation flag')
    unit = selected['QonversionTests']
    require(unit.get('TEST_HOST', '').endswith('/QonversionUnitTestHost.app/QonversionUnitTestHost'), 'Wrong resolved test host')
    require(unit.get('BUNDLE_LOADER') == unit['TEST_HOST'], 'Wrong resolved bundle loader')
    require(unit.get('PODS_ROOT', '').endswith('/UnitTestSupport/Dependencies/Pods'), 'Wrong resolved Pods path')
    require(unit.get('PODS_PODFILE_DIR_PATH', '').endswith('/UnitTestSupport/Dependencies'), 'Wrong resolved Podfile path')
    require(selected['QonversionUnitTestHost'].get('PRODUCT_BUNDLE_IDENTIFIER') == 'io.qonversion.unit-test-host', 'Wrong resolved host identity')
    return {'resolved_targets': sorted(selected), 'isolation_flags_verified': True}

def validate_xctestrun(document):
    # Xcode's v2 structure; reject unexpected/legacy formats rather than guessing.
    require(document.get('__xctestrun_metadata__', {}).get('FormatVersion') == 2, 'Unsupported xctestrun format')
    configurations = document.get('TestConfigurations', [])
    require(len(configurations) == 1, 'Unexpected test configurations')
    targets = configurations[0].get('TestTargets', [])
    require(len(targets) == 1, 'Unexpected xctestrun suites')
    target = targets[0]
    require(target.get('BlueprintName') == 'QonversionTests', 'Unexpected xctestrun suite')
    require(target.get('TestHostPath', '').endswith('/QonversionUnitTestHost.app'), 'Wrong xctestrun host')
    require(target.get('TestBundlePath', '').endswith('/QonversionTests.xctest'), 'Wrong xctestrun bundle')
    require(target.get('IsUITestBundle') is not True, 'Unexpected UI test runner')
    return {'xctestrun_testables': 1, 'dedicated_host_verified': True}

def validate_pods(objects, spec):
    targets = [value for value in objects.values() if value.get('isa') in ('PBXNativeTarget', 'PBXAggregateTarget')]
    require(len(targets) == 2 and {value['name'] for value in targets} == PODS, 'Unexpected generated dependency targets')
    require(not any(value.get('isa') == 'PBXShellScriptBuildPhase' for value in objects.values()), 'Dependency build script not allowed')
    for target in targets:
        names = {objects[c]['name'] for c in objects[target['buildConfigurationList']]['buildConfigurations']}
        require(CONFIG in names, 'Dependency isolation configuration missing')
    require(spec.get('name') == 'OCMock' and spec.get('version') == '3.9.4', 'Wrong dependency version')
    require(spec.get('source') == {'git': 'https://github.com/erikdoe/ocmock.git', 'tag': 'v3.9.4'}, 'Wrong dependency source')
    require(not any(spec.get(key) for key in ['prepare_command', 'script_phases', 'dependencies', 'subspecs']), 'Unexpected dependency hooks or graph')
    return {'dependency': 'OCMock', 'version': '3.9.4', 'generated_targets': sorted(PODS), 'dependency_shell_phases': 0}

def bounded(command, cwd, timeout, log_path=None, output_limit=None):
    # Terminate the whole build process group on timeout. Logs are private and are
    # not artifacts; only fixed verdicts/source revision are printed by this tool.
    with open(log_path or os.devnull, 'wb') as error_log:
        process = subprocess.Popen(command, cwd=cwd,
                                   stdout=subprocess.PIPE if log_path is None or output_limit is not None else error_log,
                                   stderr=subprocess.STDOUT if output_limit is not None else error_log, start_new_session=True)
        def stop_group():
            try: os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired: pass
            # The leader can exit on TERM while a descendant ignores it. Check
            # the owned session's group even after wait has reaped the leader.
            try: os.killpg(process.pid, 0)
            except ProcessLookupError: pass
            else:
                try: os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
            process.wait(timeout=3)
            if process.stdout is not None: process.stdout.close()
        try:
            if output_limit is None:
                out, _ = process.communicate(timeout=timeout)
            else:
                # Only the verbose CocoaPods command uses this bounded pipe.
                # Limit its private log without limiting generated dependency files.
                deadline, total, out = time.monotonic() + timeout, 0, None
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    while selector.get_map():
                        remaining = deadline - time.monotonic()
                        if remaining <= 0: raise subprocess.TimeoutExpired(command, timeout)
                        for key, _ in selector.select(min(remaining, .25)):
                            chunk = os.read(key.fileobj.fileno(), 65536)
                            if not chunk:
                                selector.unregister(key.fileobj)
                                continue
                            available = max(0, output_limit - total)
                            error_log.write(chunk[:available])
                            total += len(chunk)
                            require(total <= output_limit, 'Native dependency output exceeded limit')
                process.wait(timeout=max(.001, deadline - time.monotonic()))
                process.stdout.close()
        except subprocess.TimeoutExpired:
            stop_group()
            raise ValueError('Native build stage timed out') from None
        except BaseException:
            stop_group()
            raise
        require(process.returncode == 0, 'Native build command failed; inspect private build log')
        return out

def build_command(derived):
    return ['xcodebuild', '-workspace', 'QonversionUnitIsolation.xcworkspace', '-scheme', SCHEME,
            '-configuration', CONFIG, '-destination', 'generic/platform=iOS Simulator',
            '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO',
            'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=']

def pinned_pod_install_command(root, state):
    executable = shutil.which('pod')
    if executable is None: raise FileNotFoundError('CocoaPods executable unavailable')
    # Homebrew and RubyGems launchers need not accept the same _version_ syntax.
    # Pin the ordinary CLI's reported version, then reuse that exact executable.
    version = bounded([executable, '--version'], root, 30).decode('utf-8', errors='replace').strip()
    state['pod_version'] = version if re.fullmatch(r'[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}', version) else None
    require(state['pod_version'] is not None, 'CocoaPods version is not numeric')
    require(state['pod_version'] == '1.16.2', 'Pinned CocoaPods version mismatch')
    return [executable, 'install', '--deployment', '--verbose', '--project-directory=UnitTestSupport/Dependencies']

def diagnostic_category(message):
    # Only the category leaves this function; never the compiler's free text.
    rules = [
        ('MISSING_MODULE', r'no such module|module .* not found|file not found'),
        ('UNKNOWN_SYMBOL', r'cannot find|undeclared identifier|unknown type|no type named'),
        ('ACCESS_CONTROL', r'inaccessible|protection level'),
        ('SELECTOR_OR_PROPERTY', r'no visible @interface|no known class method|property .* not found|unrecognized selector'),
        ('TYPE_MISMATCH', r'cannot convert|incompatible|cannot assign|cannot infer|ambiguous|missing argument|extraneous argument|no matching'),
        ('AVAILABILITY', r'only available|unavailable'),
        ('SYNTAX', r'expected|unterminated|consecutive|extraneous|invalid'),
    ]
    return next((name for name, pattern in rules if re.search(pattern, message, re.I)), 'OTHER_COMPILER')

def collect_diagnostics(log_path, root, tracked):
    result = {'compiler': [], 'linker': [], 'truncated': False}
    if not log_path.exists(): return result
    # Only tracked relative source filenames can leave the process. No message,
    # URL, environment, command, source excerpt, caret line or linker symbol dump.
    paths = {}
    for relative in tracked:
        if relative and len(relative) <= 200 and Path(relative).suffix in ('.m', '.mm', '.h', '.swift'):
            paths[relative] = relative
            paths[str(root / relative)] = relative
    with log_path.open('rb') as source:
        offset = max(0, source.seek(0, 2) - 4 * 1024 * 1024)
        source.seek(offset)
        data = source.read(4 * 1024 * 1024)
    if offset:
        data = data.partition(b'\n')[2]; result['truncated'] = True
    linker = {'LINK_UNDEFINED': 0, 'LINK_COMMAND_FAILED': 0}
    errors, warnings = [], []
    for raw in data.decode('utf-8', errors='replace').splitlines():
        if len(raw) > 4096: result['truncated'] = True; continue
        if re.match(r'^Undefined symbols for architecture [A-Za-z0-9_]+:', raw): linker['LINK_UNDEFINED'] += 1
        if re.search(r'^(?:clang|ld): (?:error: )?.*linker command failed', raw): linker['LINK_COMMAND_FAILED'] += 1
        match = re.match(r'^(.*?):([0-9]+):([0-9]+):\s*(fatal error|error|warning):\s*(.*)$', raw)
        if not match or match[1] not in paths: continue
        if int(match[2]) > 10000000 or int(match[3]) > 10000000: continue
        selected = warnings if match[4] == 'warning' else errors
        if len(selected) == 20: result['truncated'] = True; continue
        selected.append({'file': paths[match[1]], 'line': int(match[2]), 'column': int(match[3]),
                         'severity': 'warning' if match[4] == 'warning' else 'error',
                         'category': diagnostic_category(match[5])})
    result['compiler'] = (errors + warnings)[:20]
    if len(errors) + len(warnings) > 20: result['truncated'] = True
    result['linker'] = [{'category': name, 'records': count} for name,count in linker.items() if count]
    return result

def collect_pod_diagnostics(log_path):
    # Match fixed identifiers only. No exception message, URL, path, dependency
    # name, command, environment value or stack frame can leave this function.
    rules = [
        ('PODFILE_MISSING', r'No `Podfile\x27 found in the project directory'),
        ('LOCKFILE_MISSING', r'No `Podfile\.lock\x27 found in the project directory'),
        ('DEPLOYMENT_PODFILE_CHANGED', r'There were changes to the podfile in deployment mode'),
        ('DEPLOYMENT_LOCKFILE_CHANGED', r'There were changes to the lockfile in deployment mode'),
        ('PROJECT_NOT_FOUND', r'Unable to find the Xcode project'),
        ('PROJECT_AMBIGUOUS', r'Could not automatically select an Xcode project'),
        ('TARGET_NOT_FOUND', r'Unable to find a target named'),
        ('PLATFORM_REQUIRED', r'It is necessary to specify the platform in the Podfile if not integrating'),
        ('UNKNOWN_BUILD_CONFIGURATION', r'Unknown configurations? whitelisted'),
        ('SPEC_NOT_FOUND', r'Unable to find a specification for|None of your spec sources contain a spec satisfying'),
        ('RESOLUTION_CONFLICT', r'CocoaPods could not find compatible versions for pod'),
        ('MINIMUM_DEPLOYMENT_TARGET', r'required a higher minimum deployment target'),
        ('SOURCE_SETUP_FAILED', r'Unable to add a source with url'),
        ('COCOAPODS_CACHE_CREATE_FAILED', r'Could not create .*the CocoaPods repo cache directory'),
        ('CDN_REPO_TYPE_FAILED', r'Couldn\x27t determine repo type for URL'),
        ('CDN_DOWNLOAD_FAILED', r'CDN: .*URL couldn\x27t be downloaded'),
        ('CDN_REPO_UPDATE_FAILED', r'CDN: .*Repo update failed'),
        ('TLS_VERIFY_FAILED', r'certificate verify failed|SSL certificate problem|SSL peer certificate.*not OK'),
        ('DNS_LOOKUP_FAILED', r'Could not resolve host|Couldn\x27t resolve host name|getaddrinfo: nodename nor servname'),
        ('CONNECTION_FAILED', r'Failed to connect to|Connection refused|Connection timed out'),
        ('HTTP_401', r'(?:Response:|HTTP[^\r\n]{0,12})\s*401\b'),
        ('HTTP_403', r'(?:Response:|HTTP[^\r\n]{0,12})\s*403\b'),
        ('HTTP_404', r'(?:Response:|HTTP[^\r\n]{0,12})\s*404\b'),
        ('HTTP_429', r'(?:Response:|HTTP[^\r\n]{0,12})\s*429\b'),
        ('HTTP_5XX', r'(?:Response:|HTTP[^\r\n]{0,12})\s*5[0-9]{2}\b'),
        ('GIT_ACCESS_FAILED', r'Permission denied \(publickey\)|fatal: could not read Username|fatal: Authentication failed'),
        ('GIT_REF_NOT_FOUND', r'Remote branch .* not found in upstream|Couldn\x27t find remote ref'),
        ('XCODE_LICENSE', r'You have not agreed to the Xcode license'),
        ('RUBY_LOAD_ERROR', r'\bLoadError\b|cannot load such file --'),
        ('RUBY_ARGUMENT_ERROR', r'\bArgumentError\b'),
        ('RUBY_NO_METHOD_ERROR', r'\bNoMethodError\b'),
        ('RUBY_NAME_ERROR', r'\bNameError\b'),
        ('RUBY_TYPE_ERROR', r'\bTypeError\b'),
        ('RUBY_FFI_LOAD_ERROR', r'Could not open library|incompatible architecture|Library not loaded:'),
        ('FILESYSTEM_ACCESS_DENIED', r'Errno::EACCES|Permission denied(?! \(publickey\))'),
        ('FILESYSTEM_READ_ONLY', r'Errno::EROFS|Read-only file system'),
        ('FILESYSTEM_NO_SPACE', r'Errno::ENOSPC|No space left on device'),
        ('FILESYSTEM_EXISTS', r'Errno::EEXIST|File exists'),
        ('FILESYSTEM_MISSING', r'Errno::ENOENT|No such file or directory'),
        ('FILESYSTEM_NOT_DIRECTORY', r'Errno::ENOTDIR|Not a directory'),
    ]
    result = {'available': log_path.is_file(), 'categories': [], 'unclassified_error_lines': 0,
              'unmatched_lines': 0, 'truncated': False}
    if not result['available']: return result
    with log_path.open('rb') as source:
        offset = max(0, source.seek(0, 2) - 4 * 1024 * 1024)
        source.seek(offset)
        data = source.read(4 * 1024 * 1024)
    if offset:
        data = data.partition(b'\n')[2]; result['truncated'] = True
    counts = {category: 0 for category, _ in rules}
    lines = data.decode('utf-8', errors='replace').splitlines()
    if len(lines) > 10000: result['truncated'] = True
    patterns = [(category, re.compile(pattern, re.I)) for category, pattern in rules]
    for line in lines[-10000:]:
        if len(line) > 4096: result['truncated'] = True; continue
        line = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', line)
        if not line.strip(): continue
        matched = False
        for category, pattern in patterns:
            if pattern.search(line):
                matched = True
                if counts[category] == 999: result['truncated'] = True
                counts[category] = min(999, counts[category] + 1)
        if not matched:
            if result['unmatched_lines'] == 65535: result['truncated'] = True
            result['unmatched_lines'] = min(65535, result['unmatched_lines'] + 1)
            if re.match(r'^\s*(?:\[!\]|### Error|(?:fatal|error):)', line, re.I):
                if result['unclassified_error_lines'] == 999: result['truncated'] = True
                result['unclassified_error_lines'] = min(999, result['unclassified_error_lines'] + 1)
    result['categories'] = [{'category': name, 'records': count} for name,count in counts.items() if count]
    return result

def failure_reason(error):
    if isinstance(error, KeyboardInterrupt): return 'INTERRUPTED'
    if isinstance(error, FileNotFoundError): return 'REQUIRED_TOOL_OR_FILE_MISSING'
    if isinstance(error, subprocess.TimeoutExpired): return 'TIMEOUT'
    if isinstance(error, ValueError):
        return {'Native build stage timed out': 'TIMEOUT',
                'Native build command failed; inspect private build log': 'COMMAND_FAILED',
                'Native dependency output exceeded limit': 'DEPENDENCY_OUTPUT_LIMIT',
                'Native build-only stage requires macOS': 'PLATFORM_UNSUPPORTED',
                'Source revision mismatch': 'SOURCE_REVISION_MISMATCH',
                'CocoaPods version is not numeric': 'DEPENDENCY_VERSION_UNPARSEABLE',
                'Pinned CocoaPods version mismatch': 'DEPENDENCY_VERSION_MISMATCH',
                'Build input must be committed and clean': 'DIRTY_INPUT',
                'Dependency preparation mutated source': 'DEPENDENCY_MUTATED_SOURCE'}.get(str(error), 'VALIDATION_REJECTED')
    return 'BUILD_STAGE_ERROR'

def write_verdict(output, result):
    data = json.dumps(result, separators=(',', ':')) + '\n'
    require(len(data.encode()) <= 8192, 'Sanitized verdict exceeds limit')
    (output / 'build-verdict.json').write_text(data)
    print(data.strip())

def run_build(root, args, state):
    require(sys.platform == 'darwin', 'Native build-only stage requires macOS')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    state['head'] = head if re.fullmatch(r'[0-9a-f]{40}', head) else None
    require(head == args.expected_head and len(head) == 40, 'Source revision mismatch')
    require(not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip(), 'Build input must be committed and clean')
    state['tracked'] = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    static_result = verify(root)
    os.environ['COCOAPODS_DISABLE_STATS'] = 'true'
    state['stage'] = 'DEPENDENCY_VERSION'
    install_command = pinned_pod_install_command(root, state)
    locked = (root / 'UnitTestSupport/Dependencies/Podfile.lock').read_bytes()
    state['stage'] = 'DEPENDENCY_INSTALL'
    bounded(install_command, root, 180, args.output / 'pods-private.log', output_limit=4*1024*1024)
    state['stage'] = 'DEPENDENCY_VALIDATE'
    require((root / 'UnitTestSupport/Dependencies/Podfile.lock').read_bytes() == locked, 'Dependency lock changed')
    require((root / 'UnitTestSupport/Dependencies/Pods/Manifest.lock').read_bytes() == locked, 'Dependency manifest differs from lock')
    require(not subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip(), 'Dependency preparation mutated source')
    pods_root = root / 'UnitTestSupport/Dependencies/Pods'
    dependency = validate_pods(parse((pods_root / 'Pods.xcodeproj/project.pbxproj').read_text())['objects'],
                               json.loads((pods_root / 'Local Podspecs/OCMock.podspec.json').read_text()))
    verify(root)
    derived = args.output / 'DerivedData'
    command = build_command(derived)
    state['stage'] = 'RESOLVED_SETTINGS'
    settings = json.loads(bounded(command + ['-showBuildSettings', '-json'], root, 90))
    resolved = validate_settings(settings)
    # No test/test-without-building, simctl boot/launch, fastlane, or host executable.
    state['stage'] = 'BUILD_FOR_TESTING'
    bounded(command + ['build-for-testing'], root, 900, args.output / 'build-private.log')
    state['stage'] = 'XCTESTRUN_VALIDATE'
    paths = list((derived / 'Build/Products').glob('*.xctestrun'))
    require(len(paths) == 1, 'Expected exactly one generated xctestrun')
    with paths[0].open('rb') as source: descriptor = validate_xctestrun(plistlib.load(source))
    state['stage'] = 'COMPLETE'
    return {'status': 'BUILD_ONLY_PASS', 'stage': 'COMPLETE', 'head': head, 'sdk_executed': False,
            'tests_executed': False, 'native_isolation_proven': False,
            'pod_version': state['pod_version'],
            'static_preflight': static_result, 'dependency': dependency, **resolved, **descriptor}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
    root = Path(__file__).resolve().parents[2]
    state = {'stage': 'SOURCE_PREFLIGHT', 'head': None, 'tracked': [], 'pod_version': None}
    try:
        result = run_build(root, args, state)
    except (Exception, KeyboardInterrupt) as error:
        result = {'status': 'BUILD_ONLY_FAILED', 'stage': state['stage'], 'head': state['head'],
                  'reason': failure_reason(error), 'sdk_executed': False, 'tests_executed': False,
                  'pod_version': state['pod_version'],
                  'native_isolation_proven': False,
                  'diagnostics': collect_diagnostics(args.output / 'build-private.log', root, state['tracked'])}
        if state['stage'] == 'DEPENDENCY_INSTALL':
            result['dependency_diagnostics'] = collect_pod_diagnostics(args.output / 'pods-private.log')
        write_verdict(args.output, result)
        raise SystemExit(1)
    write_verdict(args.output, result)

if __name__ == '__main__':
    try: main()
    except (ValueError, subprocess.SubprocessError, OSError, json.JSONDecodeError):
        # Output-directory or publishing failure: no arbitrary exception text.
        print(json.dumps({'status': 'BUILD_ONLY_FAILED', 'reason': 'VERDICT_UNAVAILABLE'}))
        raise SystemExit(1)
