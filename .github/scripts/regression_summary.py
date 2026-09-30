"""Write aggregate evidence and fail unless every required job succeeded."""
import json
import os
from pathlib import Path

REQUIRED = ('revision', 'backend-full', 'frontend-full', 'browser-e2e')

def summarize(jobs):
    statuses = {name: jobs.get(name, {}).get('result', 'missing') for name in REQUIRED}
    return statuses, all(result == 'success' for result in statuses.values())

if __name__ == '__main__':
    statuses, passed = summarize(json.loads(os.environ['JOB_RESULTS']))
    report = {
        'commit': os.environ['TEST_COMMIT'],
        'workflow_commit': os.environ['GITHUB_SHA'],
        'run_id': os.environ['GITHUB_RUN_ID'],
        'jobs': statuses,
        'passed': passed,
        'scope': 'Backend offline full suite; Web Vitest/typecheck/build; Flutter unit/widget suite; 8 Chromium E2E scenarios',
        'excluded': ['live OpenAI opt-in tests', 'manual_preview screenshot exporters', 'Android/iOS builds and device testing'],
    }
    Path('regression-summary.json').write_text(json.dumps(report, indent=2) + '\n')
    text = f"# Full regression\n\nTest commit: `{report['commit']}`\n\n| Job | Result |\n| --- | --- |\n"
    text += ''.join(f'| {name} | {result} |\n' for name, result in statuses.items())
    text += f"\nOverall: **{'PASS' if passed else 'FAIL'}**\n\n{report['scope']}\n\nExcluded: {', '.join(report['excluded'])}.\n"
    Path('regression-summary.md').write_text(text)
    with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
        summary.write(text)
    raise SystemExit(0 if passed else 1)
