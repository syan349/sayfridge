import unittest
from regression_summary import REQUIRED, summarize

class AggregateTests(unittest.TestCase):
    def test_all_succeeded(self):
        self.assertTrue(summarize({name: {'result': 'success'} for name in REQUIRED})[1])
    def test_any_unsuccessful_job_fails_aggregate(self):
        for name in REQUIRED:
            for result in ['failure', 'cancelled', 'skipped']:
                jobs = {key: {'result': 'success'} for key in REQUIRED}
                jobs[name]['result'] = result
                self.assertFalse(summarize(jobs)[1], (name, result))
    def test_missing_job_fails_aggregate(self):
        self.assertFalse(summarize({})[1])

if __name__ == '__main__':
    unittest.main()
