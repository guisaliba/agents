#!/usr/bin/env bash
# Focused offline checks. Live verifiers remain explicit and separate.
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$ROOT"
bash -n install.sh test.sh bin/pi-port bin/pi-port-memory lib/platform.sh
python3 -B pi/test-launch.py -v
python3 -B pi/test-portability.py -v
python3 -B - <<'PY'
import ast
from pathlib import Path
for folder in ('pi', 'lib'):
    for file in Path(folder).glob('*.py'):
        ast.parse(file.read_text(), filename=str(file))
print('PASS: Python syntax and Bash syntax')
PY
