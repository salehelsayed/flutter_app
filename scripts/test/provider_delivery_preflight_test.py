"""Private provider credentials must bind to the production Firebase client."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mknoon_checks as checks


class ProviderCredentialPreflightTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='provider-preflight-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        client = self.root / 'android/app/google-services.json'
        client.parent.mkdir(parents=True)
        client.write_text(json.dumps({'project_info': {'project_id': 'fixture-project'}}))
        self.credential = self.root / 'private-provider.json'
        self.credential.write_text(json.dumps({
            'project_id': 'fixture-project',
            'client_email': 'fixture@example.invalid',
            'private_key': 'fixture-key',
        }))
        self.credential.chmod(0o600)
        self.config = {'full_suite': {'service_account': str(self.credential)}}

    def test_matching_private_service_account_is_ready(self):
        self.assertTrue(checks.provider_credential_matches(self.root, self.config))

    def test_missing_foreign_or_public_credential_is_rejected(self):
        self.assertFalse(checks.provider_credential_matches(self.root, {}))
        self.credential.write_text(json.dumps({
            'project_id': 'foreign-project',
            'client_email': 'fixture@example.invalid',
            'private_key': 'fixture-key',
        }))
        self.assertFalse(checks.provider_credential_matches(self.root, self.config))
        self.credential.write_text(json.dumps({
            'project_id': 'fixture-project',
            'client_email': 'fixture@example.invalid',
            'private_key': 'fixture-key',
        }))
        self.credential.chmod(0o644)
        self.assertFalse(checks.provider_credential_matches(self.root, self.config))


if __name__ == '__main__':
    unittest.main()
