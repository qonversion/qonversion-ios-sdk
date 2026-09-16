#!/usr/bin/env python3
"""Run exact serializer method bodies on macOS Foundation under a network-deny sandbox.

Usage: python3 foundation-attempt-probe.py OLD_SERIALIZER_M NEW_SERIALIZER_M OUTPUT_DIR
This is a native Foundation method probe, not the full iOS SDK or a wire/lifecycle test.
"""
import hashlib
import json
import pathlib
import platform
import os
import re
import socket
import subprocess
import sys

SANDBOX_PROFILE = '(version 1)(allow default)(deny network*)'
BASE_COMMIT = 'eb5641d08978633d903c80e29ac7c1f84a4fdcdb'
SERIALIZER_PATH = 'Sources/Qonversion/Qonversion/Core/QNRequestSerializer/QNRequestSerializer.m'
WORKFLOW_PATH = '.github/workflows/isolated-foundation-proof.yml'
BOUNDARY_SOURCE = r'''
#include <arpa/inet.h>
#include <errno.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <unistd.h>
int main(int argc, char **argv) {
  if (argc != 2) return 11;
  int port = atoi(argv[1]);
  if (port < 1 || port > 65535) return 12;
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return (errno == EPERM || errno == EACCES) ? 20 : 13;
  struct sockaddr_in address = {0};
  address.sin_family = AF_INET;
  address.sin_port = htons(port);
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int result = connect(fd, (struct sockaddr *)&address, sizeof(address));
  int saved_errno = errno;
  close(fd);
  if (result == 0) return 0;
  return (saved_errno == EPERM || saved_errno == EACCES) ? 20 : 14;
}
'''


def sandbox_command(binary, *args):
    return ['/usr/bin/sandbox-exec', '-p', SANDBOX_PROFILE, str(binary), *args]


def verify_boundary(output):
    """Only numeric loopback is contacted; denied connect must be policy-denied."""
    source, binary = output / 'network-boundary.c', output / 'network-boundary'
    source.write_text(BOUNDARY_SOURCE)
    subprocess.run(['xcrun', 'clang', str(source), '-o', str(binary)], check=True, timeout=60)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(('127.0.0.1', 0))
        listener.listen(2)
        listener.settimeout(1)
        port = str(listener.getsockname()[1])
        positive = subprocess.run([str(binary), port], capture_output=True, timeout=5)
        if positive.returncode != 0:
            raise SystemExit('Boundary positive control did not connect')
        connection, _ = listener.accept()
        connection.close()
        negative = subprocess.run(sandbox_command(binary, port), capture_output=True, timeout=5)
        if negative.returncode != 20:
            raise SystemExit('Boundary negative control was not explicitly policy-denied')
        try:
            connection, _ = listener.accept()
        except socket.timeout:
            pass
        else:
            connection.close()
            raise SystemExit('Boundary negative control reached the listener')
    return {'positive_loopback_connected': True, 'sandbox_connect_policy_denied': True,
            'sandbox_listener_connections': 0,
            'scope': 'IPv4_loopback_TCP_canary_not_iOS_Simulator_or_URLSession_proof',
            'source_sha256': hashlib.sha256(BOUNDARY_SOURCE.encode()).hexdigest(),
            'profile_sha256': hashlib.sha256(SANDBOX_PROFILE.encode()).hexdigest()}


def verify_provenance(old_path, new_path):
    expected = os.environ.get('GITHUB_SHA', '')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{40}', expected) or head != expected:
        raise SystemExit('Expected exact GITHUB_SHA checkout')
    old_bytes = subprocess.check_output(['git', 'show', BASE_COMMIT + ':' + SERIALIZER_PATH])
    new_bytes = subprocess.check_output(['git', 'show', head + ':' + SERIALIZER_PATH])
    if pathlib.Path(old_path).read_bytes() != old_bytes or pathlib.Path(new_path).read_bytes() != new_bytes:
        raise SystemExit('Serializer input does not match pinned git blobs')
    for path in [pathlib.Path(__file__), pathlib.Path(WORKFLOW_PATH)]:
        relative = path.resolve().relative_to(pathlib.Path.cwd()).as_posix()
        if path.read_bytes() != subprocess.check_output(['git', 'show', head + ':' + relative]):
            raise SystemExit('Runner/workflow differs from exact source commit')
    return {'source_commit': head, 'baseline_commit': BASE_COMMIT,
            'workflow_sha256': hashlib.sha256(pathlib.Path(WORKFLOW_PATH).read_bytes()).hexdigest(),
            'run_id': os.environ.get('GITHUB_RUN_ID'), 'run_attempt': os.environ.get('GITHUB_RUN_ATTEMPT')}


def extract(path):
    source = pathlib.Path(path).read_text()
    start = source.index('- (NSURLRequest *)addTryCountToHeader:')
    end = source.index('\n}\n', start) + 2
    method = source[start:end]
    # Fail closed if the method grows beyond the source pattern independently reviewed.
    lines = [line.strip() for line in method.splitlines() if line.strip()]
    expected = [
        '- (NSURLRequest *)addTryCountToHeader:(NSNumber *)tryCount request:(NSURLRequest *)request {',
        'NSMutableURLRequest *mutableRequest = [request mutableCopy];',
        'NSString *attempt = [NSString stringWithFormat:@"%ld", (long)tryCount.integerValue + 1];',
        None,
        'request = [mutableRequest copy];',
        'return request;',
        '}',
    ]
    if len(lines) != len(expected) or any(e is not None and a != e for a, e in zip(lines, expected)):
        raise SystemExit('Serializer method differs from independently reviewed source shape')
    if lines[3] not in ['[mutableRequest addValue:attempt forHTTPHeaderField:@"Attempt"];',
                        '[mutableRequest setValue:attempt forHTTPHeaderField:@"Attempt"];']:
        raise SystemExit('Unexpected header operation')
    return method


PREFIX = '''#import <Foundation/Foundation.h>
#include <stdio.h>
@interface QNRequestSerializer : NSObject
- (NSURLRequest *)addTryCountToHeader:(NSNumber *)tryCount request:(NSURLRequest *)request;
@end
@implementation QNRequestSerializer
'''
SUFFIX = '''
@end
int main(void) {
  @autoreleasepool {
    QNRequestSerializer *serializer = [QNRequestSerializer new];
    NSMutableURLRequest *initial = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://example.invalid/v1/user/init"]];
    initial.HTTPMethod = @"POST";
    initial.HTTPBody = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    [initial setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLRequest *request = initial;
    NSMutableArray *attempts = [NSMutableArray new];
    BOOL chainPass = YES;
    BOOL preservationPass = YES;
    for (NSInteger index = 0; index < 4; index++) {
      NSURLRequest *previous = request;
      NSString *previousAttempt = [previous valueForHTTPHeaderField:@"Attempt"];
      request = [serializer addTryCountToHeader:@(index) request:previous];
      NSString *actual = [request valueForHTTPHeaderField:@"Attempt"];
      [attempts addObject:actual ?: @"missing"];
      chainPass &= [actual isEqualToString:[NSString stringWithFormat:@"%ld", (long)index + 1]];
      NSString *after = [previous valueForHTTPHeaderField:@"Attempt"];
      preservationPass &= (after == previousAttempt || [after isEqualToString:previousAttempt]);
      preservationPass &= [request.URL isEqual:initial.URL] && [request.HTTPMethod isEqual:initial.HTTPMethod];
      preservationPass &= [request.HTTPBody isEqual:initial.HTTPBody];
      preservationPass &= [[request valueForHTTPHeaderField:@"Content-Type"] isEqualToString:@"application/json"];
    }
    preservationPass &= [initial valueForHTTPHeaderField:@"Attempt"] == nil;
    NSMutableURLRequest *stored = [initial mutableCopy];
    [stored setValue:@"1,2,3,4" forHTTPHeaderField:@"Attempt"];
    NSURLRequest *replayed = [serializer addTryCountToHeader:@0 request:stored];
    NSString *replayAttempt = [replayed valueForHTTPHeaderField:@"Attempt"];
    BOOL replayPass = [replayAttempt isEqualToString:@"1"];
    preservationPass &= [[stored valueForHTTPHeaderField:@"Attempt"] isEqualToString:@"1,2,3,4"];
    NSDictionary *result = @{@"runtime": @"native_macos_Foundation_method_probe", @"attempts": attempts,
      @"replayed_attempt": replayAttempt, @"chain_pass": @(chainPass),
      @"replay_pass": @(replayPass), @"preservation_pass": @(preservationPass)};
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    return chainPass && replayPass && preservationPass ? 0 : 1;
  }
}
'''


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    if platform.system() != 'Darwin':
        raise SystemExit('Requires native macOS Foundation; no substitute runtime is accepted')
    if not pathlib.Path('/usr/bin/sandbox-exec').exists():
        raise SystemExit('Required network-deny sandbox-exec is unavailable')
    provenance = verify_provenance(sys.argv[1], sys.argv[2])
    old, new = extract(sys.argv[1]), extract(sys.argv[2])
    if ' addValue:' not in old or ' setValue:' not in new:
        raise SystemExit('Expected old addValue and new setValue implementations')
    output = pathlib.Path(sys.argv[3]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    boundary = verify_boundary(output)
    results = {'schema_version': 1, 'provenance': provenance, 'network_boundary': boundary,
               'limitations': ['Foundation method only; no iOS SDK/XCTest/NoCodes execution',
                               'Does not satisfy OPE-722 host isolation acceptance'],
               'runtime_platform': {'system': platform.system(), 'macos': platform.mac_ver()[0],
                                    'machine': platform.machine()},
               'runner_sha256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest()}
    for label, method in [('old', old), ('new', new)]:
        source, binary = output / (label + '.m'), output / label
        source.write_text(PREFIX + method + SUFFIX)
        subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation', str(source), '-o', str(binary)],
                       check=True, timeout=60)
        run = subprocess.run(sandbox_command(binary),
                             text=True, capture_output=True, timeout=10)
        if run.returncode not in (0, 1):
            raise SystemExit(label + ' native probe did not complete normally')
        results[label] = json.loads(run.stdout)
        results[label]['exit_code'] = run.returncode
        results[label]['method_sha256'] = hashlib.sha256(method.encode()).hexdigest()
        results[label]['harness_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        input_file = sys.argv[1] if label == 'old' else sys.argv[2]
        results[label]['source_file_sha256'] = hashlib.sha256(pathlib.Path(input_file).read_bytes()).hexdigest()
    passed = results['old']['exit_code'] == 1 and results['new']['exit_code'] == 0
    passed &= not results['old']['chain_pass'] and not results['old']['replay_pass']
    passed &= results['old']['preservation_pass'] and results['new']['preservation_pass']
    results['regression_proven'] = bool(passed)
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2))
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
