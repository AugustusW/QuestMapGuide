#!/usr/bin/env python3.12
"""用遊戲內 /qmg probe 存下的 SavedVariables 產生 tests/api_manifest.lua（測試白名單）。

用法：python3.12 tools/gen_manifest.py <SavedVariables.lua> [--flavor forever|retail] [--out tests/api_manifest.lua]
- globals：探測清單中存在的頂層名稱（含路徑的取第一段，例如 C_Spell）
- methods：Frame／Button／EditBox／ScrollFrame／CheckButton 的實際方法；FontString／Texture 探測沒涵蓋，沿用暫定清單
- templates：可建立的 template
"""
import argparse, json, pathlib, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROVISIONAL_EXTRA = {
    "FontString": ["SetText", "GetText", "SetPoint", "GetStringWidth", "SetFontObject", "SetJustifyH",
                   "SetTextColor", "SetWidth", "SetWordWrap", "ClearAllPoints", "Show", "Hide", "SetShown",
                   "GetStringHeight"],
    "Texture": ["SetTexture", "SetPoint", "SetSize", "SetAllPoints", "SetColorTexture", "Show", "Hide",
                "SetTexCoord", "SetShown", "ClearAllPoints", "SetVertexColor", "SetAlpha", "SetDesaturated",
                "SetRotation"],
}
# Lua 內建或 harness 自己提供、不在探測清單的全域。
# 依版本分開：正式版沒有職業訓練師，混進永恆專屬的全域會讓「沒有訓練師全域也不報錯」的測試假綠。
ALWAYS_COMMON = ["UIParent", "UISpecialFrames", "SlashCmdList", "hash_SlashCmdList", "tinsert", "GetLocale",
                 "C_TooltipInfo", "hooksecurefunc", "C_Timer",
                 # 2026-11-08 使用者 /run 確認存在（7 個 true）
                 "C_CurrencyInfo", "GetMoneyString",
                 # 各版本都有的核心單位 API（探測未列，載入時才會用到）
                 "UnitLevel",
                 # 2026-11-08 使用者 /run 實測：永恆 18、正式版 1
                 "WOW_PROJECT_ID"]
# 探測清單之外、使用者 /run 實測確認存在的「完整路徑」API（記憶 2524/2525：GetAllCompletedQuestIDs 回 234 筆）
VERIFIED_APIS = ["C_QuestLog.GetAllCompletedQuestIDs"]
ALWAYS_FOREVER: list[str] = []  # 本插件只有永恆；探測清單之外確認存在的永恆專屬全域放這裡


def lua_set(items):
    return "set({ " + ", ".join(f'"{x}"' for x in sorted(set(items))) + " })"


def build_manifest(sv: dict, flavor: str) -> tuple[str, set]:
    m = sv["manifest"]
    build = sv.get("probe", {}).get("build", "?").strip()
    globals_ = {name.split(".")[0] for name, ok in m["globals"].items() if ok}
    globals_.update(ALWAYS_COMMON)
    if flavor == "forever":
        globals_.update(ALWAYS_FOREVER)
    out = ["-- 由 tools/gen_manifest.py 依遊戲內 /qmg probe 結果產生（build " + build + "），不要手改",
           "-- FontString／Texture 探測沒涵蓋，沿用暫定清單",
           "local function set(t) local s = {} for _, k in ipairs(t) do s[k] = true end return s end",
           "return {", "  provisional = false,", f"  globals = {lua_set(globals_)},",
           f"  apis = {lua_set([a for a, ok in m.get('apis', {}).items() if ok] + VERIFIED_APIS)},", "  methods = {"]
    for kind, methods in sorted(m["methods"].items()):
        out.append(f"    {kind} = {lua_set(methods)},")
    for kind, methods in PROVISIONAL_EXTRA.items():
        out.append(f"    {kind} = {lua_set(methods)},")
    out += ["  },", f"  templates = {lua_set([t for t, ok in m['templates'].items() if ok])},", "}"]
    return "\n".join(out) + "\n", globals_


def missing_apis(sv: dict) -> list[str]:
    """m.apis 保留完整路徑（C_Map.GetMapInfo 這類）；globals 只留第一段會漏掉巢狀缺項。"""
    return sorted(p for p, ok in sv["manifest"].get("apis", {}).items() if not ok)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("sv")
    ap.add_argument("--flavor", choices=["forever", "retail"], default="forever")
    ap.add_argument("--accept-missing", action="store_true", help="允許 apis 有 false 項目（預設遇到就失敗）")
    ap.add_argument("--out", default=str(ROOT / "tests" / "api_manifest.lua"))
    a = ap.parse_args(argv)
    sv = json.loads(subprocess.run(["luajit", str(ROOT / "tools" / "sv2json.lua"), a.sv],
                                   check=True, capture_output=True, text=True).stdout)
    missing = missing_apis(sv)
    if missing and not a.accept_missing:
        print("探測結果有不存在的 API（完整路徑）：", file=sys.stderr)
        for path in missing:
            print("  " + path, file=sys.stderr)
        print("確認程式都有先判斷再用後，加 --accept-missing 重跑。", file=sys.stderr)
        sys.exit(1)
    text, globals_ = build_manifest(sv, a.flavor)
    pathlib.Path(a.out).write_text(text, encoding="utf-8")
    print(f"{a.flavor} globals={len(globals_)} " + " ".join(f"{k}={len(v)}" for k, v in sv["manifest"]["methods"].items()))


if __name__ == "__main__":
    main()
