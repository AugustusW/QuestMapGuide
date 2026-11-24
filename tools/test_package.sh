#!/bin/bash
# package.sh 與發布白名單的檢查：
# 1. zip 含 TOC、LICENSE、NOTICE（GPL 與 CMaNGOS 資料來源聲明不可漏）
# 2. TOC 列出的每個檔都被 .publish-allowlist 涵蓋（記憶 2260：oss_publish --dry-run 不會警告漏列）
# 在暫存 worktree 跑（package.sh 要求工作目錄乾淨），所以只檢查已 commit 的內容。
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$(pwd)
rc=0

python3.12 - <<'EOF' || rc=1
import fnmatch, pathlib, sys
root = pathlib.Path(".")
pats = [l.strip() for l in (root / ".publish-allowlist").read_text(encoding="utf-8").splitlines()
        if l.strip() and not l.startswith("#")]
need = ["LICENSE", "NOTICE", "README.md"]
for toc in sorted(root.glob("QuestMapGuide_*.toc")):
    need.append(toc.name)
    need += [l.strip() for l in toc.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]
# 打包會帶整個 Media/（toc IconTexture 指向的圖示），GitHub 端打包也要有：白名單必須涵蓋每個追蹤中的 Media 檔
import subprocess
need += [f for f in subprocess.run(["git", "ls-files", "Media"], capture_output=True, text=True).stdout.split() if f]
miss = [f for f in need if not any(fnmatch.fnmatch(f, p) for p in pats)]
for f in miss:
    print("FAIL 白名單沒有涵蓋：" + f)
print("PASS 白名單涵蓋 TOC 檔案、Media 與授權檔" if not miss else "", end="\n" if not miss else "")
sys.exit(1 if miss else 0)
EOF

TMP=$(mktemp -d)
WT="$TMP/QuestMapGuide"
git worktree add -q --detach "$WT" HEAD || exit 1
cleanup() { git -C "$REPO" worktree remove --force "$WT"; rm -rf "$TMP"; }
trap cleanup EXIT
cd "$WT"
# 先把清單存起來再比對：pipefail 下 `unzip | grep -q` 會因 SIGPIPE 時好時壞
if bash tools/package.sh >/dev/null 2>&1 && LIST=$(unzip -l dist/*.zip) \
  && [[ "$LIST" == *QuestMapGuide/QuestMapGuide_Forever.toc* && "$LIST" == *QuestMapGuide/LICENSE* \
        && "$LIST" == *QuestMapGuide/NOTICE* && "$LIST" == *QuestMapGuide/Core.lua* ]]; then
  echo "PASS zip 含 TOC、LICENSE、NOTICE、Core.lua"
else echo "FAIL zip 應含 TOC、LICENSE、NOTICE、Core.lua"; rc=1; fi

# 以下在暫存 worktree 的外面跑，重新建一個拋棄式 worktree
cd "$REPO"
# 可重現：同一個 commit 打兩次，zip 的 sha256 要相同（檔案時間不能跟著打包當下走）
bash "$WT/tools/package.sh" >/dev/null 2>&1; H1=$(shasum -a 256 "$WT"/dist/*.zip | cut -d' ' -f1)
sleep 1
bash "$WT/tools/package.sh" >/dev/null 2>&1; H2=$(shasum -a 256 "$WT"/dist/*.zip | cut -d' ' -f1)
if [[ -n "$H1" && "$H1" == "$H2" ]]; then echo "PASS 同一 commit 打包兩次 sha256 相同"
else echo "FAIL 同一 commit 打包兩次 sha256 不同（$H1 / $H2）"; rc=1; fi

# PKG_NAME：目錄名不是插件名時（worktree、發布端 clone）用環境變數指定
WT2="$TMP/wt-x"
git -C "$REPO" worktree add -q --detach "$WT2" HEAD || exit 1
if (cd "$WT2" && PKG_NAME=QuestMapGuide bash tools/package.sh >/dev/null 2>&1) \
   && LIST=$(cd "$WT2" && unzip -Z1 dist/*.zip) && [[ "$(printf '%s\n' "$LIST" | cut -d/ -f1 | sort -u)" == "QuestMapGuide" ]]; then
  echo "PASS PKG_NAME 覆蓋目錄名，zip 最外層是 QuestMapGuide/"
else echo "FAIL PKG_NAME 應覆蓋目錄名"; rc=1; fi
git -C "$REPO" worktree remove --force "$WT2"
exit $rc
