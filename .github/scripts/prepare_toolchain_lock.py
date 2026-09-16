#!/usr/bin/env python3
"""Gate A only: bootstrap verified Bundler and resolve a lock. Never run pod/Xcode."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import tempfile
import time
import urllib.request

BUNDLER = '2.6.9'
PACKAGE_URL = 'https://rubygems.org/downloads/bundler-2.6.9.gem'
PACKAGE_SHA = 'a25675ffbd055ae1186766cc1e120b4cf62588e88abb59b99c57e22b1c55c9eb'
TOP_HASHES = {
    'cocoapods': '0ff1c860f32df3db8b16df09b58da1a6bb2a12fe55f6d5e8be994a74fadd1e5e',
    'cocoapods-core': '4bb1b5c420691e60cf36fa227dec6bc48c096c34c97bb7aa512ea7f3246fc12b',
}
GEMFILE = b'source "https://rubygems.org"\ngem "cocoapods", "= 1.16.2"\ngem "cocoapods-core", "= 1.16.2"\n'
VERSION = r'[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
MAX_LOG = 4 * 1024 * 1024


class Rejected(Exception):
    """Only fixed reason enums may leave the helper."""


def require(condition, reason):
    if not condition:
        raise Rejected(reason)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def isolated_environment(task):
    # Construct, do not inherit: exclude credentials/proxies, RUBYOPT/RUBYLIB,
    # ambient GEM_*/BUNDLE_* and user configuration. HOME is not repurposed.
    values = {
        'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'LANG': 'en_US.UTF-8',
        'LC_ALL': 'en_US.UTF-8', 'GEM_HOME': str(task / 'bootstrap'),
        'GEM_PATH': str(task / 'bootstrap'), 'GEM_SPEC_CACHE': str(task / 'spec-cache'),
        'BUNDLE_USER_HOME': str(task / 'bundle-user'), 'BUNDLE_PATH': str(task / 'bundle-path'),
        'BUNDLE_APP_CONFIG': str(task / 'bundle-config'), 'BUNDLE_USER_CACHE': str(task / 'bundle-cache'),
        'BUNDLE_GEMFILE': str(task / 'Gemfile'), 'BUNDLE_IGNORE_CONFIG': 'true',
        'BUNDLE_DISABLE_SHARED_GEMS': 'true', 'BUNDLE_RETRY': '0', 'BUNDLE_TIMEOUT': '15',
        'TMPDIR': str(task / 'tmp'), 'GEMRC': str(task / 'empty-gemrc'),
    }
    for name in ['bootstrap', 'spec-cache', 'bundle-user', 'bundle-path', 'bundle-config', 'bundle-cache', 'tmp']:
        (task / name).mkdir(mode=0o700)
    (task / 'empty-gemrc').write_text('--- {}\n')
    return values


def bounded(command, task, env, timeout):
    """Private capped output; kill/reap the process group on timeout or interrupt."""
    process = subprocess.Popen(command, cwd=task, env=env, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, start_new_session=True)
    selector = selectors.DefaultSelector()
    output = bytearray()
    deadline = time.monotonic() + timeout
    try:
        selector.register(process.stdout, selectors.EVENT_READ)
        while True:
            remaining = deadline - time.monotonic()
            require(remaining > 0, 'COMMAND_TIMEOUT')
            if not selector.select(min(remaining, 0.25)):
                continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            require(len(output) + len(chunk) <= MAX_LOG, 'COMMAND_OUTPUT_LIMIT')
            output.extend(chunk)
        process.wait(timeout=max(0.001, deadline - time.monotonic()))
        require(process.returncode == 0, 'COMMAND_FAILED')
        return bytes(output)
    except BaseException as error:
        for sig in [signal.SIGTERM, signal.SIGKILL]:
            try:
                os.killpg(process.pid, sig)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
        process.wait(timeout=2)
        if isinstance(error, subprocess.TimeoutExpired):
            raise Rejected('COMMAND_TIMEOUT') from None
        raise
    finally:
        selector.close()
        process.stdout.close()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # No redirect is necessary for this exact registry asset; reject all.
        raise Rejected('BOOTSTRAP_REDIRECT')


def download_package(target):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    data = bytearray()
    def expired(*_):
        raise Rejected('BOOTSTRAP_TIMEOUT')
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 30)
    try:
        with opener.open(PACKAGE_URL, timeout=30) as response:
            require(response.geturl() == PACKAGE_URL, 'BOOTSTRAP_ORIGIN')
            while True:
                chunk = response.read(65536)
                if not chunk:
                    break
                data.extend(chunk)
                require(len(data) <= 5 * 1024 * 1024, 'BOOTSTRAP_SIZE')
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    require(digest(data) == PACKAGE_SHA, 'BOOTSTRAP_HASH')
    target.write_bytes(data)
    return PACKAGE_SHA


def numeric(value, minimum=None):
    require(isinstance(value, str) and re.fullmatch(VERSION, value), 'RUNTIME_VERSION_FORMAT')
    if minimum:
        require(tuple(map(int, value.split('.'))) >= minimum, 'RUNTIME_VERSION_UNSUPPORTED')
    return value


def runtime_tuple(ruby, task, env):
    program = 'require "rubygems"; require "json"; puts JSON.generate({ruby: RUBY_VERSION, rubygems: Gem::VERSION, platform: Gem::Platform.local.to_s})'
    raw = bounded([ruby, '--disable=gems', '-e', program], task, env, 15)
    try:
        values = json.loads(raw)
    except (ValueError, TypeError):
        raise Rejected('RUNTIME_FORMAT') from None
    require(isinstance(values, dict) and set(values) == {'ruby', 'rubygems', 'platform'}, 'RUNTIME_FORMAT')
    numeric(values['ruby'], (3, 1, 0))
    numeric(values['rubygems'], (3, 3, 3))
    require(isinstance(values['platform'], str) and re.fullmatch(r'(arm64|x86_64)-darwin-[0-9]{1,3}', values['platform']), 'RUNTIME_PLATFORM')
    return values


def bootstrap(ruby, gem, task, env):
    package = task / 'bundler.gem'
    download_package(package)
    # Recheck the on-disk bytes immediately before code loading.
    require(digest(package.read_bytes()) == PACKAGE_SHA, 'BOOTSTRAP_HASH')
    bounded([ruby, gem, '--norc', 'install', str(package), '--local', '--ignore-dependencies',
             '--no-document', '--install-dir', str(task / 'bootstrap'),
             '--bindir', str(task / 'bootstrap/bin')], task, env, 120)
    bundle = task / 'bootstrap/gems' / ('bundler-' + BUNDLER) / 'exe/bundle'
    require(bundle.is_file() and bundle.resolve().is_relative_to(task.resolve()), 'BUNDLER_EXECUTABLE')
    command = [ruby, str(bundle)]
    actual = bounded(command + ['--version'], task, env, 15).decode('utf-8', errors='replace').strip()
    require(actual == 'Bundler version ' + BUNDLER, 'BUNDLER_VERSION')
    return command


def validate_lock(data):
    require(len(data) <= 65536, 'LOCK_SIZE')
    try:
        text = data.decode('ascii')
    except UnicodeError:
        raise Rejected('LOCK_FORMAT') from None
    sections = {}
    current = None
    for line in text.splitlines():
        if not line:
            continue
        if not line.startswith(' '):
            require(line in {'GEM', 'PLATFORMS', 'DEPENDENCIES', 'CHECKSUMS', 'BUNDLED WITH'} and line not in sections, 'LOCK_SECTIONS')
            current = line
            sections[current] = []
        else:
            require(current is not None, 'LOCK_FORMAT')
            sections[current].append(line)
    require(set(sections) == {'GEM', 'PLATFORMS', 'DEPENDENCIES', 'CHECKSUMS', 'BUNDLED WITH'}, 'LOCK_SECTIONS')
    require(sections['GEM'][:2] == ['  remote: https://rubygems.org/', '  specs:'], 'LOCK_SOURCE')
    specs = set()
    for line in sections['GEM'][2:]:
        match = re.fullmatch(r'    ([A-Za-z0-9_.-]+ \([A-Za-z0-9_.-]+\))', line)
        if match:
            require(match[1] not in specs, 'LOCK_DUPLICATE')
            specs.add(match[1])
        else:
            require(re.fullmatch(r'      [A-Za-z0-9_.-]+(?: \([~>=<0-9A-Za-z., -]+\))?', line), 'LOCK_DEPENDENCY_FORMAT')
    require(2 <= len(specs) <= 100, 'LOCK_SPEC_COUNT')
    require(sections['DEPENDENCIES'] == ['  cocoapods (= 1.16.2)', '  cocoapods-core (= 1.16.2)'], 'LOCK_TOP_PINS')
    require(sections['BUNDLED WITH'] == ['   ' + BUNDLER], 'LOCK_BUNDLER')
    platforms = [line.removeprefix('  ') for line in sections['PLATFORMS']]
    require(1 <= len(platforms) <= 20 and len(set(platforms)) == len(platforms), 'LOCK_PLATFORMS')
    # Bundler 2.6.9 adds complete extra platforms to a fresh lock. These public
    # variants are proposal metadata only; none is approved for installation.
    platform_pattern = r'ruby|(?:arm64|x86_64)-darwin(?:-[0-9]{1,3})?|(?:aarch64|arm|arm64|x86|x86_64)-linux(?:-gnu|-musl)?'
    require(all(re.fullmatch(platform_pattern, item) for item in platforms), 'LOCK_PLATFORMS')
    checksums = {}
    for line in sections['CHECKSUMS']:
        match = re.fullmatch(r'  ([A-Za-z0-9_.-]+ \([A-Za-z0-9_.-]+\)) sha256=([a-f0-9]{64})', line)
        require(match is not None and match[1] not in checksums, 'LOCK_CHECKSUM_FORMAT')
        checksums[match[1]] = match[2]
    require(set(checksums) == specs, 'LOCK_CHECKSUM_COVERAGE')
    for name, sha in TOP_HASHES.items():
        require(checksums.get(name + ' (1.16.2)') == sha, 'LOCK_TOP_CHECKSUM')
    return {'spec_count': len(specs), 'checksum_count': len(checksums), 'platforms': platforms, 'lock_sha256': digest(data)}


def validate_native_coverage(runtime, platforms):
    # add_extra_platforms! may remove the OS-version-specific native entry when
    # it adds a mutually compatible generic Darwin entry for the same CPU.
    generic = runtime.rsplit('-', 1)[0]
    require(runtime in platforms or generic in platforms, 'LOCK_RUNTIME_PLATFORM')


def prepare(root, task, state):
    require(os.uname().sysname == 'Darwin', 'MACOS_REQUIRED')
    ruby, gem = shutil.which('ruby'), shutil.which('gem')
    require(ruby is not None and gem is not None, 'RUBY_TOOLING_MISSING')
    ruby, gem = str(Path(ruby).resolve()), str(Path(gem).resolve())
    env = isolated_environment(task)
    state['stage'] = 'RUNTIME'
    state['runtime'] = runtime_tuple(ruby, task, env)
    state['stage'] = 'BOOTSTRAP'
    bundle = bootstrap(ruby, gem, task, env)
    state['bootstrap_sha256'] = PACKAGE_SHA
    require((root / 'UnitTestSupport/Toolchain/Gemfile').read_bytes() == GEMFILE, 'GEMFILE_PIN')
    (task / 'Gemfile').write_bytes(GEMFILE)
    state['stage'] = 'LOCK_RESOLUTION'
    bounded(bundle + ['lock', '--gemfile', str(task / 'Gemfile'), '--lockfile', str(task / 'Gemfile.lock'), '--add-checksums'], task, env, 180)
    state['stage'] = 'LOCK_VALIDATION'
    data = (task / 'Gemfile.lock').read_bytes()
    state.update(validate_lock(data))
    validate_native_coverage(state['runtime']['platform'], state['platforms'])
    return data


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-head', required=True)
    args = parser.parse_args()
    require(re.fullmatch(r'[a-f0-9]{40}', args.expected_head), 'HEAD_FORMAT')
    root = Path(__file__).resolve().parents[2]
    runner = Path(os.environ.get('RUNNER_TEMP', ''))
    require(runner.is_absolute() and runner.is_dir() and runner.resolve() != root and not runner.resolve().is_relative_to(root), 'RUNNER_TEMP_REQUIRED')
    output = runner / 'ope722-toolchain-lock-result'
    output.mkdir(mode=0o700)  # Never consume or overwrite an earlier result.
    state = {'status': 'TOOLCHAIN_LOCK_FAILED', 'stage': 'SOURCE', 'reason': None,
             'head': args.expected_head, 'source': 'https://rubygems.org', 'bundler': BUNDLER,
             'helper_sha256': digest(Path(__file__).read_bytes()), 'gemfile_sha256': digest(GEMFILE),
             'cocoapods_dependencies_installed': False, 'sdk_executed': False, 'tests_executed': False,
             'build_executed': False, 'gate_b_authorized': False}
    try:
        actual = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], timeout=10, stderr=subprocess.DEVNULL).decode().strip()
        require(actual == args.expected_head, 'HEAD_MISMATCH')
        require(not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], timeout=10, stderr=subprocess.DEVNULL), 'SOURCE_DIRTY')
        with tempfile.TemporaryDirectory(prefix='ope722-toolchain-', dir=runner) as directory:
            task = Path(directory)
            data = prepare(root, task, state)
            require(not subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], timeout=10, stderr=subprocess.DEVNULL), 'SOURCE_CHANGED')
            (output / 'Gemfile').write_bytes(GEMFILE)
            (output / 'Gemfile.lock').write_bytes(data)
        state.update(status='TOOLCHAIN_LOCK_PREPARED', stage='COMPLETE')
    except Rejected as error:
        state['reason'] = str(error)
    except (KeyboardInterrupt, SystemExit):
        state['reason'] = 'INTERRUPTED'
    except Exception:
        state['reason'] = 'UNEXPECTED_FAILURE'
    encoded = json.dumps(state, sort_keys=True, indent=2) + '\n'
    require(len(encoded.encode()) <= 8192, 'VERDICT_SIZE')
    (output / 'provenance.json').write_text(encoded)
    print(json.dumps({'status': state['status'], 'stage': state['stage'], 'reason': state['reason']}))
    return 0 if state['status'] == 'TOOLCHAIN_LOCK_PREPARED' else 1


if __name__ == '__main__':
    # Turn CI's SIGTERM into the same bounded child cleanup as Ctrl-C.
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        result = main()
    except Rejected as error:
        print(json.dumps({'status': 'TOOLCHAIN_LOCK_FAILED', 'stage': 'PREFLIGHT', 'reason': str(error)}))
        result = 1
    except Exception:
        print(json.dumps({'status': 'TOOLCHAIN_LOCK_FAILED', 'stage': 'PREFLIGHT', 'reason': 'UNEXPECTED_FAILURE'}))
        result = 1
    raise SystemExit(result)
