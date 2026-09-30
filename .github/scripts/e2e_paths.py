"""Select changes that affect real browser/API/database integration."""
from fnmatch import fnmatchcase
import subprocess
import sys

PATTERNS = (
    'backend/app/**', 'backend/migrations/**', 'backend/scripts/**',
    'backend/requirements*.txt', 'backend/pyproject.toml', 'backend/.python-version',
    'backend/.env.e2e.example', 'backend/alembic.ini',
    'web/src/**', 'web/public/**', 'web/e2e/**', 'web/package*.json',
    'web/*config*', 'web/index.html',
    '.github/workflows/**', '.github/scripts/**',
)

def needs_e2e(paths):
    return any(fnmatchcase(path, pattern) for path in paths for pattern in PATTERNS)

if __name__ == '__main__':
    paths = subprocess.check_output(['git', 'diff', '--name-only', '-z', sys.argv[1], sys.argv[2]]).decode().split('\0')
    print(f"run={'true' if needs_e2e(paths) else 'false'}")
