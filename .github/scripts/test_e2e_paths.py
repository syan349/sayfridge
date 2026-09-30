import unittest
from e2e_paths import needs_e2e

class PathSelectionTests(unittest.TestCase):
    def test_documentation_only(self):
        self.assertFalse(needs_e2e(['README.md', 'docs/testing/README.md']))
    def test_business_code(self):
        self.assertTrue(needs_e2e(['backend/app/services/inventory.py']))
    def test_migration(self):
        self.assertTrue(needs_e2e(['backend/migrations/versions/new.py']))
    def test_browser_client(self):
        self.assertTrue(needs_e2e(['web/src/api/client.ts']))
    def test_locks_and_workflow(self):
        for path in ['web/package-lock.json', 'backend/requirements.txt', '.github/workflows/core-e2e.yml']:
            self.assertTrue(needs_e2e([path]))
    def test_flutter_only(self):
        self.assertFalse(needs_e2e(['mobile/lib/main.dart', 'mobile/pubspec.lock']))

if __name__ == '__main__':
    unittest.main()
