#!/usr/bin/env python3.12
"""靜態檢查：addon 用到的全域名稱都要在 tests/api_manifest.lua（遊戲內探測）裡，
或是 Lua 內建／本 addon 自己定義的。用 luajit -bl 列出 GGET。
測試的萬用替身測不出「呼叫不存在的 API」，這一關補上（記憶 2023）。
"""
import pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LUA_BUILTINS = set("""assert error ipairs pairs next pcall xpcall select tonumber tostring type unpack rawget rawset
setmetatable getmetatable collectgarbage math string table date time print _G strsplit wipe""".split())
# 探測確認不存在或沒測到、但程式只在 `if X then` 之後才用的名稱（逐一列出，新增要附理由）
GUARDED: set[str] = {"debugprofilestop", "UnitGUID", "UnitName", "issecretvalue", "GetCoinTextureString", "C_CreatureInfo", "GetQuestLogRewardXP", "UnitSex", "HandleModifiedItemClick", "ChatEdit_InsertLink", "DressUpItemLink", "IsShiftKeyDown", "IsControlKeyDown", "GetQuestID", "GetTitleText", "GetObjectiveText", "GetRewardXP", "GetRewardMoney", "GetNumQuestRewards", "GetNumQuestChoices", "GetQuestItemLink", "GetQuestItemInfo", "IsInInstance", "GetInstanceInfo", "GetNumQuestLogChoices", "GetNumQuestLogRewards", "GetQuestLogItemLink", "GetQuestLogChoiceInfo", "GetQuestLogRewardInfo", "GetQuestLogSelection", "GetQuestLink", "ChatFrame_OpenChat", "ToggleWorldMap"}  # GetQuestLink／ChatFrame_OpenChat（2026-11-28 任務貼聊天）：已加進 Probe.APIS 尚待探測，Detail.QuestLinkClick 先判斷 type(...)=="function" 並包 pcall；  # 任務日誌獎勵六個（GetQuestLogSelection 永恆 1.60 沒有，只留在 APIS 探測）（2026-11-27）：已加進 Probe.APIS、尚待實機探測，Probe.logRewards 先判斷 type(...)=="function" 並包 pcall；  # IsInInstance／GetInstanceInfo（V298 副本）：已加進 Probe.APIS，副本 spike（409946b）尚待實機存檔確認回傳值；Observe／Panel 一律先判斷 type(...)=="function" 並包 pcall，拿不到就當不在副本； GetQuestID 等九個任務視窗 API：2026-11-26 探測版（spike c71d070）在永恆實測有值、非保密（GetQuestItemLink／GetQuestItemInfo 尚未遇到物品獎勵），已加進 Probe.APIS；Observe.lua 一律經 call() 先判斷 type(...)=="function" 並包 pcall； GetQuestLogRewardXP／UnitSex：不在探測白名單，Reward.lua 用前先判斷 type(...)=="function"，沒有就退回資料值／甲； GetCoinTextureString／C_CreatureInfo：已加進 Probe.APIS、尚未探測，Detail.lua 用前先判斷 type(...)=="function" 或欄位存在，沒有就退回文字／「#id」； debugprofilestop：尚未探測（/sigprobe 沒涵蓋），LoadStart/LoadEnd 先判斷才用；UnitGUID/UnitName/issecretvalue：探測版專用，Probe.lua 用前先判斷 type(...)=="function" 並包 pcall；HandleModifiedItemClick／ChatEdit_InsertLink／IsShiftKeyDown：SkillsItemsGuide 的永恆探測確認存在，DressUpItemLink／IsControlKeyDown 未探測，五個都已加進 Probe.APIS，Detail.ModifiedItemClick 用前一律判斷 type(...)=="function"，沒有就不動作
OWN = re.compile(r"^(QuestMapGuide\w*|SLASH_\w+|QMG_\w+)$")  # QMG_* 由 Data 檔定義，只讀


def manifest_globals():
    text = (ROOT / "tests" / "api_manifest.lua").read_text(encoding="utf-8")
    m = re.search(r"globals = set\(\{(.*?)\}\)", text, re.S)
    return set(re.findall(r'"([^"]+)"', m.group(1)))


def toc_files():
    """所有 TOC（_Forever／_Mainline）列出的檔案聯集。"""
    files = []
    for toc in sorted(ROOT.glob("QuestMapGuide_*.toc")):
        for l in toc.read_text(encoding="utf-8").splitlines():
            l = l.strip()
            if l and not l.startswith("#") and l not in files:
                files.append(l)
    return files


def main():
    allowed = manifest_globals() | LUA_BUILTINS | GUARDED
    bad = []
    for f in toc_files():
        if f.startswith("Data/"):
            continue
        out = subprocess.run(["luajit", "-bl", str(ROOT / f)], capture_output=True, text=True, errors="replace", check=True).stdout
        for name in sorted(set(re.findall(r'G[GS]ET\s+\d+\s+\d+\s+; "([^"]+)"', out))):
            if name not in allowed and not OWN.match(name):
                bad.append(f"{f}: {name}")
    for b in bad:
        print("不在探測白名單的全域：" + b)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
