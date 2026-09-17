#!/usr/bin/env python3
"""Gate B candidate: frozen Ruby tooling, then the unchanged build-only helper."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import prepare_toolchain_lock as toolchain
import unit_isolation_build as build

EXECUTION_AUTHORIZED = True
LOCK_SHA = '08b51056c2bc276c84c9f99a4b277df6ae357e33efaf3cffcb63381efec36333'
RUNTIME = {'ruby': '3.3.12', 'rubygems': '4.0.20', 'platform': 'arm64-darwin-24'}
NATIVE_EXTENSIONS = {'bigdecimal', 'json', 'nkf'}

# Pinned Bundler's platform matcher is also used by resolution. Inspect metadata
# before installation, so the generic ffi extension cannot become a fallback.
SELECT_FROM_LOCK = '''
require "bundler/gem_helpers"
require "bundler/lockfile_parser"
lock = Bundler::LockfileParser.new(File.read(ARGV.fetch(0)))
rows = lock.specs.group_by(&:name).sort.flat_map do |name, specs|
  chosen = Bundler::GemHelpers.select_best_platform_match(specs, Gem::Platform.local)
  raise "selection_not_unique" unless chosen.length == 1
  chosen.map { |s| {name: s.name, version: s.version.to_s, platform: s.platform.to_s} }
end
require "json"
puts JSON.generate({bundler: Bundler::VERSION, specs: rows})
'''

INSTALLED_METADATA = '''
require "bundler/setup"
require "json"
bundle_root = File.realpath(ENV.fetch("BUNDLE_PATH")) + "/"
default_root = File.realpath(Gem.default_dir) + "/"
# bundler/setup changes GEM_HOME to BUNDLE_PATH. The expected bootstrap root
# comes from the parent's immutable, verified installation path instead.
bootstrap_root = File.realpath(ARGV.fetch(0)) + "/"
rows = Bundler.load.specs.map do |s|
  location = File.realpath(s.full_gem_path)
  {name: s.name, version: s.version.to_s, platform: s.platform.to_s,
   isolated: location.start_with?(bundle_root), default: s.default_gem?,
   bootstrap_path: location.start_with?(bootstrap_root),
   runtime_default_path: location.start_with?(default_root), extensions: !s.extensions.empty?}
end
puts JSON.generate({bundler: Bundler::VERSION, specs: rows})
'''


def accepted_inputs(root):
    directory = root / 'UnitTestSupport/Toolchain'
    lock = (directory / 'Gemfile.lock').read_bytes()
    toolchain.require(toolchain.digest(lock) == LOCK_SHA, 'ACCEPTED_LOCK_HASH')
    toolchain.require((directory / 'Gemfile').read_bytes() == toolchain.GEMFILE, 'ACCEPTED_GEMFILE_HASH')
    manifest = json.loads((directory / 'accepted-runtime.json').read_text())
    toolchain.require(manifest['lock_sha256'] == LOCK_SHA and manifest['runtime'] == RUNTIME
                      and manifest['bundler'] == toolchain.BUNDLER, 'ACCEPTED_RUNTIME_MANIFEST')
    toolchain.validate_lock(lock)
    expected = {}
    for name, version, platform in re.findall(r'^    ([A-Za-z0-9_.-]+) \(([0-9.]+)(?:-([A-Za-z0-9_.-]+))?\)$', lock.decode(), re.M):
        if name in expected:
            toolchain.require(expected[name] == version, 'LOCK_MULTIPLE_VERSIONS')
        expected[name] = version
    toolchain.require(len(expected) == 45, 'LOCK_NAME_COUNT')
    return lock, expected


def frozen_environment(task, ruby):
    env = toolchain.isolated_environment(task)
    env.update(BUNDLE_FROZEN='true', BUNDLE_DEPLOYMENT='true',
               BUNDLE_FORCE_RUBY_PLATFORM='false', BUNDLE_DISABLE_CHECKSUM_VALIDATION='false',
               COCOAPODS_DISABLE_STATS='true')
    env['PATH'] = str(Path(ruby).parent) + ':' + env['PATH']
    return env


def validate_selection(document, expected, installed=False):
    toolchain.require(isinstance(document, dict) and document.get('bundler') == toolchain.BUNDLER,
                      'SELECTED_BUNDLER_RUNTIME_VERSION')
    rows = document.get('specs')
    toolchain.require(isinstance(rows, list) and 45 <= len(rows) <= 46, 'SELECTED_SPEC_COUNT')
    selected = {}
    defaults = []
    for row in rows:
        toolchain.require(isinstance(row, dict), 'SELECTED_SPEC_FORMAT')
        name, version, platform = row.get('name'), row.get('version'), row.get('platform')
        if installed and name == 'bundler':
            toolchain.require(version == toolchain.BUNDLER, 'SELECTED_BUNDLER_SPEC_VERSION')
            toolchain.require(platform == 'ruby', 'SELECTED_BUNDLER_SPEC_PLATFORM')
            toolchain.require(row.get('bootstrap_path') is True, 'SELECTED_BUNDLER_SPEC_PATH')
            continue
        toolchain.require(name in expected and name not in selected and version == expected[name], 'SELECTED_SPEC_VERSION')
        toolchain.require(platform == ('arm64-darwin' if name == 'ffi' else 'ruby'), 'SELECTED_SPEC_PLATFORM')
        selected[name] = version
        if installed:
            toolchain.require(all(isinstance(row.get(key), bool) for key in
                                  ['isolated', 'default', 'runtime_default_path', 'extensions']), 'SELECTED_SPEC_FORMAT')
            toolchain.require(row['isolated'] or (row['default'] and row['runtime_default_path']), 'SELECTED_SPEC_PATH')
            toolchain.require(not row['extensions'] or name in NATIVE_EXTENSIONS, 'UNEXPECTED_NATIVE_EXTENSION')
            if not row['isolated']:
                defaults.append({'name': name, 'version': version, 'platform': platform, 'source_class': 'runtime_default'})
    toolchain.require(set(selected) == set(expected), 'SELECTED_SPEC_COVERAGE')
    return {'selected_names': len(selected), 'ffi_version': selected['ffi'], 'ffi_platform': 'arm64-darwin',
            'runtime_default_gem_count': len(defaults), 'runtime_default_gems': sorted(defaults, key=lambda row: row['name'])}


def metadata(ruby, bundle, program, task, env, args=()):
    lib = Path(bundle[1]).parent.parent / 'lib'
    stdout, _ = toolchain.bounded([ruby, '-I', str(lib), '-r', 'bundler', '-e', program, *map(str, args)],
                                  task, env, 30, split_output=True)
    toolchain.require(len(stdout) <= 65536, 'SELECTED_METADATA_SIZE')
    try:
        return json.loads(stdout)
    except ValueError:
        raise toolchain.Rejected('SELECTED_METADATA_FORMAT') from None


def unchanged_lock(task):
    toolchain.require(toolchain.digest((task / 'Gemfile.lock').read_bytes()) == LOCK_SHA, 'FROZEN_LOCK_CHANGED')
    toolchain.require((task / 'Gemfile').read_bytes() == toolchain.GEMFILE, 'FROZEN_GEMFILE_CHANGED')


def pod_environment(task, env, state):
    pod = task / 'bin/pod'
    toolchain.require(pod.is_file() and not pod.is_symlink() and pod.resolve().is_relative_to(task.resolve())
                      and os.access(pod, os.X_OK), 'POD_BINSTUB_PATH')
    result = {**env, 'PATH': str(task / 'bin') + ':' + env['PATH']}
    toolchain.require(shutil.which('pod', path=result['PATH']) == str(pod), 'POD_BINSTUB_RESOLUTION')
    state['pod_binstub_sha256'] = toolchain.digest(pod.read_bytes())
    return result


def tooling(root, task, state):
    toolchain.require(sys.platform == 'darwin', 'MACOS_REQUIRED')
    lock, expected = accepted_inputs(root)
    ruby, gem = shutil.which('ruby'), shutil.which('gem')
    toolchain.require(ruby is not None and gem is not None, 'RUBY_TOOLING_MISSING')
    ruby, gem = str(Path(ruby).resolve()), str(Path(gem).resolve())
    env = frozen_environment(task, ruby)
    state['stage'] = 'EXACT_RUNTIME'
    actual = toolchain.runtime_tuple(ruby, task, env)
    state['runtime'] = actual
    toolchain.require(actual == RUNTIME, 'RUNTIME_TUPLE_MISMATCH')
    bundle = toolchain.bootstrap(ruby, gem, task, env, state)
    (task / 'Gemfile').write_bytes(toolchain.GEMFILE)
    (task / 'Gemfile.lock').write_bytes(lock)
    state['stage'] = 'LOCK_PLATFORM_SELECTION'
    state['selection_before_install'] = validate_selection(metadata(ruby, bundle, SELECT_FROM_LOCK, task, env,
                                                                    [task / 'Gemfile.lock']), expected)
    state['stage'] = 'FROZEN_INSTALL'
    toolchain.bounded(bundle + ['install', '--gemfile', str(task / 'Gemfile'), '--jobs', '2', '--retry', '1'],
                      task, env, 300)
    unchanged_lock(task)
    state['stage'] = 'INSTALLED_SELECTION'
    state['installed_selection'] = validate_selection(metadata(ruby, bundle, INSTALLED_METADATA, task, env,
                                                               [task / 'bootstrap']),
                                                       expected, installed=True)
    state['stage'] = 'POD_BINSTUB'
    toolchain.bounded(bundle + ['binstubs', 'cocoapods', '--path', str(task / 'bin')], task, env, 30)
    unchanged_lock(task)
    return pod_environment(task, env, state)


def existing_build(expected_head, output, env):
    # Same-process invocation preserves the SIGTERM->KeyboardInterrupt handler,
    # allowing the existing bounded helper to stop its separate-session child.
    previous_env, previous_argv = dict(os.environ), sys.argv
    try:
        os.environ.clear()
        os.environ.update(env)
        sys.argv = ['unit_isolation_build.py', '--expected-head', expected_head, '--output', str(output)]
        try:
            build.main()
        except SystemExit:
            raise toolchain.Rejected('BUILD_HELPER_FAILED') from None
    finally:
        os.environ.clear()
        os.environ.update(previous_env)
        sys.argv = previous_argv
    raw = (output / 'build-verdict.json').read_bytes()
    toolchain.require(len(raw) <= 8192, 'BUILD_VERDICT_SIZE')
    result = json.loads(raw)
    toolchain.require(result.get('status') == 'BUILD_ONLY_PASS' and result.get('head') == expected_head
                      and result.get('sdk_executed') is False and result.get('tests_executed') is False
                      and result.get('native_isolation_proven') is False, 'BUILD_VERDICT_INVALID')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-head', required=True)
    args = parser.parse_args()
    if not EXECUTION_AUTHORIZED:
        print(json.dumps({'status': 'GATE_B_DISABLED'}))
        return 1
    toolchain.require(re.fullmatch(r'[a-f0-9]{40}', args.expected_head), 'HEAD_FORMAT')
    os.umask(0o077)
    root = Path(__file__).resolve().parents[2]
    runner = Path(os.environ.get('RUNNER_TEMP', ''))
    toolchain.require(runner.is_absolute() and runner.is_dir() and not runner.resolve().is_relative_to(root), 'RUNNER_TEMP_REQUIRED')
    output = runner / 'ope722-frozen-build-result'
    output.mkdir(mode=0o700)
    state = {'status': 'FROZEN_BUILD_FAILED', 'head': args.expected_head, 'stage': 'SOURCE', 'reason': None,
             'lock_sha256': LOCK_SHA, 'sdk_executed': False, 'tests_executed': False, 'native_isolation_proven': False}
    try:
        head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], timeout=10, stderr=subprocess.DEVNULL).decode().strip()
        toolchain.require(head == args.expected_head, 'HEAD_MISMATCH')
        toolchain.require(not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], timeout=10,
                                                      stderr=subprocess.DEVNULL), 'SOURCE_DIRTY')
        with tempfile.TemporaryDirectory(prefix='ope722-frozen-', dir=runner) as directory:
            task = Path(directory)
            env = tooling(root, task, state)
            state['stage'] = 'EXISTING_BUILD_ONLY'
            existing_build(args.expected_head, output / 'native-build', env)
            unchanged_lock(task)
        state.update(status='FROZEN_BUILD_ONLY_PASS', stage='COMPLETE')
    except toolchain.Rejected as error:
        state['reason'] = str(error)
    except (KeyboardInterrupt, SystemExit):
        state['reason'] = 'INTERRUPTED'
    except Exception:
        state['reason'] = 'UNEXPECTED_FAILURE'
    data = json.dumps(state, sort_keys=True, indent=2) + '\n'
    toolchain.require(len(data.encode()) <= 8192, 'VERDICT_SIZE')
    (output / 'toolchain-verdict.json').write_text(data)
    print(json.dumps({'status': state['status'], 'stage': state['stage'], 'reason': state['reason']}))
    return 0 if state['status'] == 'FROZEN_BUILD_ONLY_PASS' else 1


if __name__ == '__main__':
    previous = signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        result = main()
    except (Exception, KeyboardInterrupt):
        print(json.dumps({'status': 'FROZEN_BUILD_FAILED', 'stage': 'PREFLIGHT', 'reason': 'UNEXPECTED_FAILURE'}))
        result = 1
    finally:
        signal.signal(signal.SIGTERM, previous)
    raise SystemExit(result)
