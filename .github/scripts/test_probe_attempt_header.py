"""Offline fail-closed runner tests; these are not native Foundation evidence."""
import importlib.util
import pathlib
import socket
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('probe', pathlib.Path(__file__).with_name('probe_attempt_header.py'))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ProbeTests(unittest.TestCase):
    def boundary(self, positive=0, negative=20, unexpected_accept=False):
        listener = MagicMock()
        listener.__enter__.return_value = listener
        listener.getsockname.return_value = ('127.0.0.1', 12345)
        connection = MagicMock()
        listener.accept.side_effect = [(connection, None),
                                       (connection, None) if unexpected_accept else socket.timeout()]
        runs = [subprocess.CompletedProcess([], code) for code in [0, positive, negative]]
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(probe.socket, 'socket', return_value=listener), patch.object(probe.subprocess, 'run', side_effect=runs) as run:
                result = probe.verify_boundary(pathlib.Path(directory))
        self.assertEqual(run.call_args_list[2].args[0][0:3],
                         ['/usr/bin/sandbox-exec', '-p', probe.SANDBOX_PROFILE])
        listener.bind.assert_called_once_with(('127.0.0.1', 0))
        return result

    def test_positive_and_explicit_denial_are_both_required(self):
        self.assertEqual(self.boundary()['sandbox_listener_connections'], 0)

    def test_failed_positive_control_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'positive control'):
            self.boundary(positive=14)

    def test_successful_sandbox_connect_rejected(self):
        with self.assertRaisesRegex(SystemExit, 'policy-denied'):
            self.boundary(negative=0)

    def test_unrelated_network_failure_is_not_policy_proof(self):
        with self.assertRaisesRegex(SystemExit, 'policy-denied'):
            self.boundary(negative=14)

    def test_listener_observation_overrides_claimed_denial(self):
        with self.assertRaisesRegex(SystemExit, 'reached the listener'):
            self.boundary(unexpected_accept=True)

    def test_exact_new_method_extracted(self):
        method = probe.extract(probe.SERIALIZER_PATH)
        self.assertIn('setValue:attempt', method)

    def test_unreviewed_method_statement_rejected(self):
        method = probe.extract(probe.SERIALIZER_PATH)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'bad.m'
            path.write_text(method.replace('return request;', 'system("unexpected");\nreturn request;') + '\n')
            with self.assertRaisesRegex(SystemExit, 'reviewed source shape'):
                probe.extract(path)

    def test_bad_expected_commit_rejected_before_blob_read(self):
        with patch.dict(probe.os.environ, {'GITHUB_SHA': 'invalid'}), patch.object(probe.subprocess, 'check_output', return_value='a' * 40 + '\n') as command:
            with self.assertRaisesRegex(SystemExit, 'exact GITHUB_SHA'):
                probe.verify_provenance('unused', 'unused')
            self.assertEqual(command.call_count, 1)

    def test_no_native_substitute_on_linux(self):
        with patch.object(probe.platform, 'system', return_value='Linux'), patch.object(probe.sys, 'argv', ['probe', 'old', 'new', 'out']), patch.object(probe.subprocess, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'native macOS'):
                probe.main()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
