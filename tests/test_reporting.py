import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

spec = importlib.util.spec_from_file_location("reporter", Path(__file__).parents[1] / "scripts/report-failures.py")
reporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporter)


class ReportingTests(unittest.TestCase):
    def test_public_report_does_not_contain_diagnostics(self):
        secret = "ghp_super-secret-token https://user:password@private.example"
        item = reporter.event("build", "a" * 40, secret)
        item.update(local_logs=secret, status_snapshot={"secret": secret}, machine=secret)
        payload = json.dumps(reporter.public_issue(item))
        for value in [secret, "super-secret", "password", "private.example", "status_snapshot", "local_logs"]:
            self.assertNotIn(value, payload)
        self.assertIn("a" * 40, payload)
        self.assertIn(item["id"], payload)

    def test_untrusted_commit_cannot_enter_issue(self):
        item = reporter.event("evaluation", "secret-from-error", "private diagnostic")
        self.assertEqual(item["commit"], "unknown")
        self.assertNotIn("secret-from-error", json.dumps(reporter.public_issue(item)))

    def test_failure_history_and_current_state_are_deduplicated(self):
        generation = {"source": {"git": {"selected_commit_id": "b" * 40}}, "eval_err": "evaluation failed"}
        status = {"builder": {"generation": generation}, "store": {"generations": [generation]},
                  "fetcher": {"git_repository_status": {"remotes": [{"fetch_error_msg": "authentication failed"}]}},
                  "deployer": {"deployment": {"status": "failed", "generation": generation, "error_msg": "activation failed"}}}
        items = list(reporter.failures(status))
        self.assertEqual({x['phase'] for x in items}, {"fetch", "evaluation", "deployment"})
        self.assertEqual(len(items), 3)
        self.assertEqual(next(x for x in items if x['phase'] == 'fetch')['commit'], 'unknown')

    def test_healthy_and_superseded_generations_do_not_report(self):
        self.assertEqual(list(reporter.failures({})), [])
        self.assertEqual(list(reporter.failures({"builder": {"generation": {"build_err": "context canceled"}}})), [])

    def test_existing_issue_is_reused_even_after_local_receipt_loss(self):
        item = reporter.event("build", "a" * 40, "failure")
        existing = {"number": 42, "body": reporter.public_issue(item)["body"]}
        with patch.object(reporter, "request", return_value=[existing]) as request:
            self.assertEqual(reporter.deliver(item, "token"), 42)
            self.assertEqual(request.call_count, 1)

    def test_delivery_failure_keeps_diagnostic_queue(self):
        with tempfile.TemporaryDirectory() as directory:
            token = Path(directory) / "token"
            token.write_text("secret")
            args = ["reporter", "--self-test", "--state-dir", directory, "--token-file", str(token)]
            with patch('sys.argv', args), patch.object(reporter, 'deliver', side_effect=urllib.error.URLError("offline")), patch.object(reporter.subprocess, 'run', side_effect=FileNotFoundError):
                reporter.main()
            records = list((Path(directory) / "events").glob("*.json"))
            self.assertEqual(len(records), 1)
            self.assertNotIn("issue_number", json.loads(records[0].read_text()))
            with patch('sys.argv', args), patch.object(reporter, 'deliver', return_value=7), patch.object(reporter.subprocess, 'run', side_effect=FileNotFoundError):
                reporter.main()
            self.assertEqual(json.loads(records[0].read_text())["issue_number"], 7)


if __name__ == '__main__':
    unittest.main()
