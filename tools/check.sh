#!/bin/bash
# 全部檢查：Lua 5.1 語法（luajit）、禁用語法掃描、Lua 測試、Python 測試
set -uo pipefail
cd "$(dirname "$0")/.."
rc=0
for f in $(find . -name "*.lua" -not -path "./tests/*" -not -path "./.git/*" -not -path "./.superpowers/*" -not -path "./tools/.cache/*"); do
  luajit -b "$f" /dev/null || { echo "語法錯誤：$f"; rc=1; }
done
if grep -rnE --include='*.lua' --exclude-dir=tests --exclude-dir=.git --exclude-dir=.superpowers --exclude-dir=.cache '//|\bgoto\b|table\.unpack|<const>|<close>' . 2>/dev/null | grep -v '^\S*:[0-9]*:\s*--'; then
  echo "出現 Lua 5.1 不接受的語法"; rc=1
fi
python3.12 tools/check_globals.py || rc=1
luajit tests/harness.lua . tests/test_*.lua || rc=1
bash tools/test_package.sh || rc=1
python3.12 -m unittest discover -s .github/scripts || rc=1
if ls tools/test_*.py >/dev/null 2>&1; then python3.12 -m pytest -q tools || rc=1; fi
exit $rc
