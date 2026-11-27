"""build_data.py quests 的測試。Lua 端用 luajit 載入產出檔驗證。"""
import copy
import json
import pathlib
import re
import shutil
import subprocess

import pytest

import build_data
import legacy_format

HERE = pathlib.Path(__file__).resolve().parent
DATA_LUA = HERE.parent / "Data.lua"
FIXTURE = HERE / "fixtures" / "export_v2_small.json"


def load_fixture():
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def run_lua(lua_file, expr):
    """載入產出檔後印出 expr 的值。"""
    code = (f'dofile({json.dumps(str(lua_file))}); local ns = {{}}; '
            f'assert(loadfile({json.dumps(str(DATA_LUA))}))("QuestMapGuide", ns); D = ns.Data; io.write(tostring({expr}))')
    r = subprocess.run(["luajit", "-e", code], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return r.stdout


def build_to(tmp_path, data):
    out = tmp_path / "Quests.lua"
    build_data.write_quests_lua(data, out)
    return out


def test_quests_lua_shape(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "D.quest(9900001).n.zh") == "測試任務一"
    assert run_lua(out, "D.quest(9900001).n.en") == "Test Quest One"
    assert run_lua(out, "D.quest(9900002).n.zh") == "nil"
    assert run_lua(out, "#D.byMap(1429)") == "1"
    assert run_lua(out, "D.byMap(1429)[1]") == "9900001"
    assert run_lua(out, "table.concat(D.byMap(1453), ',')") == "9900001,9900002"
    assert run_lua(out, "#D.byMap(0)") == "0"  # 沒收錄的地圖回空表
    q = "D.quest(9900001)"
    assert run_lua(out, f"{q}.lv .. '/' .. {q}.min .. '/' .. {q}.f .. '/' .. {q}.xp .. '/' .. {q}.cu .. '/' .. {q}.t") == "7/5/A/450/1200/0"
    assert run_lua(out, "D.quest(9900002).f") == "H"
    assert run_lua(out, "D.quest(9900003).f") == "nil"
    assert run_lua(out, f"{q}.sk[1] .. ',' .. {q}.sk[2]") == "164,25"
    assert run_lua(out, "D.quest(9900002).sk") == "nil"
    assert run_lua(out, f"table.concat({q}.cls, ',')") == "1,2"
    assert run_lua(out, f"table.concat({q}.race, ',')") == "1,4"
    # null = 未知 → 欄位不存在；[] = 已知為空 → 空表
    assert run_lua(out, "D.quest(9900002).cls") == "nil"
    assert run_lua(out, "#D.quest(9900003).cls") == "0"
    assert run_lua(out, "D.quest(9900001).conc") == "nil"
    assert run_lua(out, "#D.quest(9900002).conc") == "2"
    assert run_lua(out, "#D.quest(9900005).conc") == "0"
    assert run_lua(out, f"{q}.next[1]") == "9900002"
    assert run_lua(out, f"{q}.excl[1]") == "9900003"
    assert run_lua(out, "D.quest(9900002).prev[1]") == "9900001"
    # 匯出的關聯是 {source, questId} 物件；建置後必須是純數字 questId（Detail／Filter 直接當數字用）
    assert run_lua(out, "type(D.quest(9900002).prev[1])") == "number"
    assert run_lua(out, "table.concat(D.quest(9900002).conc, ',')") == "9900004,9900005"
    assert run_lua(out, f"type({q}.next[1]) .. type({q}.excl[1])") == "numbernumber"
    # 獎勵物品
    assert run_lua(out, f"{q}.ri[1][1] .. ',' .. {q}.ri[1][2] .. ',' .. tostring({q}.ri[1][3])") == "12345,2,false"
    assert run_lua(out, f"tostring({q}.ri[2][3])") == "true"
    assert run_lua(out, f"{q}.maps[2]") == "1453"
    assert run_lua(out, "#D.quest(9900003).maps") == "0"


def test_entity_keys_split_npc_and_object(tmp_path):
    """npc 與 object 的 id 會撞，所以用 kind 前綴：n<id> / o<id>。"""
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, 'D.entity("n9901001").n') == 'Fixture "Quoter" NPC'
    assert run_lua(out, 'D.entity("o9901001").n') == "Fixture Object"
    assert run_lua(out, "D.entity(9901001)") == "nil"
    assert run_lua(out, 'D.quest(9900001).s[1]') == "n9901001"
    assert run_lua(out, 'D.quest(9900001).e[1]') == "o9901001"
    assert run_lua(out, 'D.quest(9900002).s[1]') == "o9901001"
    assert run_lua(out, 'D.quest(9900002).e[1]') == "n9901001"
    sp = 'D.entity("n9901001").sp'
    assert run_lua(out, f"#{sp}") == "2"
    assert run_lua(out, f"{sp}[1].m .. ',' .. {sp}[1].x .. ',' .. {sp}[1].y") == "1429,45.3,60.1"
    assert run_lua(out, f"{sp}[2].m") == "1453"
    # 沒有 nameEnUs 的 entity 不能壞掉
    assert run_lua(out, "#D.quest(9900003).s") == "0"


def test_meta(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "QMG_Meta.schema") == "5"
    assert run_lua(out, "QMG_Meta.quests") == "5"
    assert run_lua(out, "QMG_Meta.entities") == "2"
    assert run_lua(out, "QMG_Meta.env") == "prod"
    assert run_lua(out, "QMG_Meta.wagoBuild") == "1.15.0.99999"
    assert run_lua(out, "QMG_Meta.sourceVersion") == "fixture-1"
    assert run_lua(out, "QMG_Meta.officialExportDate") == "2026-11-01"
    assert run_lua(out, "QMG_Meta.exportedAt") == "2026-11-23T00:00:00+00:00"


def test_meta_records_questie_commit(tmp_path):
    """NOTICE 承諾：之後的資料包把實際轉出的 Questie commit 記在 QMG_Meta（Product V294 匯出 sourceVersions）。"""
    data = load_fixture()
    data["sourceVersions"] = {"cmangos": "fixture-1", "questie": "4377c981ac368d1593ec92788218e0a689a6a02b"}
    out = build_to(tmp_path, data)
    assert run_lua(out, "QMG_Meta.questieCommit") == "4377c981ac368d1593ec92788218e0a689a6a02b"
    out2 = build_to(tmp_path / "old", load_fixture())        # 舊匯出沒有 sourceVersions：不寫這個鍵
    assert run_lua(out2, "tostring(QMG_Meta.questieCommit)") == "nil"


def test_rejects_zh_cn_key():
    d = load_fixture()
    d["quests"][1]["names"]["zh_CN"] = "x"
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "9900002" in str(e.value)


def test_rejects_simplified_chars():
    d = load_fixture()
    d["quests"][0]["names"]["zh_TW"] = "这是简体"
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "9900001" in str(e.value)


def test_simplified_table_size():
    assert len(set(build_data.SIMPLIFIED_CHARS)) >= 50


def test_simplified_table_does_not_hit_fixture_traditional():
    # 防線不能誤傷正體：fixture 的正體字不得在簡體表裡
    d = load_fixture()
    for q in d["quests"]:
        assert not (set(q["names"].get("zh_TW", "")) & set(build_data.SIMPLIFIED_CHARS))


def test_rejects_schema_v1():
    d = load_fixture()
    d["schemaVersion"] = 1
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "schemaVersion" in str(e.value)


def test_no_source_field_in_output():
    text = "".join(build_data.build_quests_lua(load_fixture())[0])
    assert "source=" not in text and '"source"' not in text  # Meta.sourceVersion 是匯出版本，不是來源欄位
    assert "correction" not in text
    assert "cmangos" not in text


def test_warns_when_env_not_prod(capsys):
    d = load_fixture()
    d["env"] = "dev"
    build_data.build_quests_lua(d)  # 只警告，不失敗
    assert "dev" in capsys.readouterr().err
    d["env"] = "prod"
    build_data.build_quests_lua(d)
    assert capsys.readouterr().err == ""


def synthetic(n):
    d = load_fixture()
    base = d["quests"][0]
    d["quests"] = []
    d["entities"] = []
    for i in range(n):
        q = copy.deepcopy(base)
        q["questId"] = 9_900_000 + i
        q["names"] = {"zh_TW": f"任務{i}", "en_US": f"Quest number {i}"}
        q["starts"] = [{"kind": "npc", "entityId": 8_000_000 + i}]
        q["ends"] = [{"kind": "npc", "entityId": 8_000_000 + i}]
        q["rewardItems"] = [{"id": 1_000_000 + i, "count": 1, "choice": False, "source": "official"}]
        q["uiMapIds"] = [1000 + i % 300]
        q["minLevel"], q["questLevel"] = i % 60, i % 61
        q["rewards"] = {"experience": i * 3, "moneyCopper": i * 7}
        d["quests"].append(q)
        d["entities"].append({"kind": "npc", "entityId": 8_000_000 + i, "nameEnUs": f"NPC {i}", "nameZhTw": None,
                              "spawns": [{"x": (i % 1000) / 10, "y": (i % 997) / 10, "uiMapId": 1000 + i % 300, "mapName": "m"}]})
    return d


def test_large_data_loads(tmp_path):
    d = synthetic(30000)
    chunks, stats = build_data.build_quests_lua(d)
    out = tmp_path / "Quests.lua"
    out.write_text("".join(chunks), encoding="utf-8")
    assert run_lua(out, "QMG_Meta.quests") == "30000"
    assert run_lua(out, "D.quest(9929999).n.en") == "Quest number 29999"
    assert run_lua(out, "D.entity('n8029999').n") == "NPC 29999"
    assert run_lua(out, "#D.questIds()") == "30000"
    luac = shutil.which("luac5.1") or shutil.which("luac")
    if luac:
        r = subprocess.run([luac, "-p", str(out)], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr


def test_fixture_lua_is_current():
    """tools/fixtures/export_v2_small.lua（給 Lua 測試載入）必須是 fixture 重新產生的結果。"""
    expected = "".join(build_data.build_quests_lua(load_fixture())[0])
    assert (HERE / "fixtures" / "export_v2_small.lua").read_text(encoding="utf-8") == expected


def test_deterministic():
    a = "".join(build_data.build_quests_lua(load_fixture())[0])
    d = load_fixture()
    d["quests"].reverse()
    d["entities"].reverse()
    assert "".join(build_data.build_quests_lua(d)[0]) == a


def test_cli_quests(tmp_path):
    out = tmp_path / "o.lua"
    assert build_data.main(["quests", "--in", str(FIXTURE), "--out", str(out)]) == 0
    assert run_lua(out, "QMG_Meta.quests") == "5"
    bad = tmp_path / "bad.json"
    d = load_fixture()
    d["schemaVersion"] = 1
    bad.write_text(json.dumps(d), encoding="utf-8")
    assert build_data.main(["quests", "--in", str(bad), "--out", str(tmp_path / "x.lua")]) == 1
    assert not (tmp_path / "x.lua").exists()


def test_null_means_unknown_for_starts_ends_rewards(tmp_path):
    out = build_to(tmp_path, load_fixture())
    for f in ("s", "e", "ri", "xp", "cu", "t"):
        assert run_lua(out, f"D.quest(9900004).{f}") == "nil", f
    for f in ("s", "e", "ri"):  # [] 是已知為空
        assert run_lua(out, f"#D.quest(9900003).{f}") == "0", f
        assert run_lua(out, f"type(D.quest(9900003).{f})") == "table", f
    assert run_lua(out, "D.quest(9900003).xp") == "10"


def _fail(d, *needles):
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    for n in needles:
        assert n in str(e.value)


def test_rejects_cjk_in_english_names():
    d = load_fixture()
    d["quests"][1]["names"]["en_US"] = "Only 英文 Name"
    _fail(d, "9900002")
    d = load_fixture()
    d["entities"][1]["nameEnUs"] = "Fixture 物件"
    _fail(d, "o9901001")


def test_rejects_bad_spawns():
    for key, val in (("x", 100.5), ("x", -1), ("y", 101), ("y", "5"), ("uiMapId", 0), ("uiMapId", -3), ("uiMapId", "1429"), ("uiMapId", 1.5), ("x", None)):
        d = load_fixture()
        d["entities"][0]["spawns"][0][key] = val
        _fail(d, "n9901001")


def test_dedupes_ui_map_ids(tmp_path):
    d = load_fixture()
    d["quests"][0]["uiMapIds"] = [1429, 1453, 1429]
    out = build_to(tmp_path, d)
    assert run_lua(out, "#D.byMap(1429)") == "1"
    assert run_lua(out, "#D.quest(9900001).maps") == "2"


def test_missing_entity_id_warns(capsys):
    d = load_fixture()
    d["quests"][0]["starts"].append({"kind": "item", "entityId": None})
    build_data.build_quests_lua(d)
    assert "9900001" in capsys.readouterr().err


def test_enc_basics():
    assert build_data.enc({"a": [1, build_data.NIL, True, False], "b": 1.5, "c": -3}) == "{a={1,~,T,F},b=1.5,c=-3}"
    assert build_data.enc({}) == "{}"
    assert build_data.enc([]) == "{}"


def test_enc_string_length_is_bytes():
    assert build_data.enc("測試") == "s6:測試"
    assert build_data.enc('a"b\nc,}') == 's7:a"b\nc,}'


def test_enc_rejects_non_identifier_keys():
    for k in ("a b", "1x", "", "é"):
        with pytest.raises(TypeError):
            build_data.enc({k: 1})
    assert build_data.enc({"end": 1}) == "{end=1}"  # 保留字也是合法的鍵（自己的格式，不是 Lua 語法）


def test_string_with_delimiters_roundtrips(tmp_path):
    d = load_fixture()
    d["quests"][0]["names"]["en_US"] = 'Evil },{ "name"=~, s5:x \\ end'
    out = build_to(tmp_path, d)
    assert run_lua(out, "D.quest(9900001).n.en") == 'Evil },{ "name"=~, s5:x \\ end'
    assert run_lua(out, "D.quest(9900001).lv") == "7"


def test_format_version_in_output(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "QMG_Data and 1") == "nil"  # Data.lua 載入後把全域 QMG_Data 清掉
    assert "QMG_Data = {fmt=%d}" % build_data.FORMAT in out.read_text(encoding="utf-8")


def test_output_mode_and_header(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert out.stat().st_mode & 0o777 == 0o644
    head = out.read_text(encoding="utf-8").split("QMG_Meta")[0]
    assert "sk" in head and "ri" in head


def test_malformed_input_is_one_line_error(tmp_path, capsys):
    d = load_fixture()
    del d["quests"][1]["questLevel"]
    d["quests"][1]["rewardItems"] = [{"id": 1}]
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps(d), encoding="utf-8")
    assert build_data.main(["quests", "--in", str(bad), "--out", str(tmp_path / "x.lua")]) == 1
    err = capsys.readouterr().err
    assert "9900002" in err and "Traceback" not in err and err.strip().count("\n") == 0


def test_null_positional_slots_become_lua_nil(tmp_path):
    out = build_to(tmp_path, load_fixture())
    q = "D.quest(9900005)"
    assert run_lua(out, f"{q}.ri[1][1]") == "159"
    assert run_lua(out, f"{q}.ri[1][2]") == "nil"
    assert run_lua(out, f"{q}.ri[1][3]") == "true"
    assert run_lua(out, f"{q}.ri[2][2]") == "3"
    assert run_lua(out, f"{q}.sk[1]") == "171"
    assert run_lua(out, f"{q}.sk[2]") == "nil"


def test_other_none_in_list_still_fails_with_quest_id():
    d = load_fixture()
    d["quests"][0]["classes"] = [1, None]
    _fail(d, "9900001")
    d = load_fixture()
    d["quests"][4]["rewardItems"][0]["id"] = None
    _fail(d, "9900005")
    d = load_fixture()
    d["quests"][4]["skill"]["id"] = None
    _fail(d, "9900005")


def test_header_warns_about_length_operator(tmp_path):
    head = build_to(tmp_path, load_fixture()).read_text(encoding="utf-8").split("QMG_Meta")[0]
    assert "#" in head


# ---- Task 5：資料瘦身 ----
SCHEMA_OF_TEST_EXPORT = build_data.SCHEMA
REAL_EXPORT = HERE.parent / "build" / "export.json"

DEEP_EQ = r"""
local function deq(a, b, path, errs)
  if type(a) ~= type(b) then errs[#errs + 1] = path .. " 型別 " .. type(a) .. " vs " .. type(b); return end
  if type(a) ~= "table" then
    if a ~= b then errs[#errs + 1] = path .. " " .. tostring(a) .. " vs " .. tostring(b) end
    return
  end
  for k, v in pairs(a) do deq(v, b[k], path .. "." .. tostring(k), errs) end
  for k in pairs(b) do if a[k] == nil then errs[#errs + 1] = path .. "." .. tostring(k) .. " 多出" end end
end
"""


def _same_answers_script(legacy, new):
    return DEEP_EQ + f"""
dofile({json.dumps(str(legacy))})
local L = {{ Q = QMG_Quests, E = QMG_Entities, B = QMG_ByMap, M = QMG_Meta }}
QMG_Quests, QMG_Entities, QMG_ByMap, QMG_Meta = nil, nil, nil, nil
dofile({json.dumps(str(new))})
local ns = {{}}
assert(loadfile({json.dumps(str(DATA_LUA))}))("QuestMapGuide", ns)
local D = ns.Data
local errs, nq, ne, nb = {{}}, 0, 0, 0
for id, q in pairs(L.Q) do nq = nq + 1; deq(D.quest(id), q, "Q" .. id, errs) end
for k, e in pairs(L.E) do ne = ne + 1; deq(D.entity(k), e, "E" .. k, errs) end
for m, l in pairs(L.B) do nb = nb + 1; deq(D.byMap(m), l, "B" .. m, errs) end
L.M.questieCommit = QMG_Meta.questieCommit  -- 舊格式沒有這個鍵（新增的中繼資料，不影響 Data API）
deq(QMG_Meta, L.M, "Meta", errs)
if #D.questIds() ~= nq then errs[#errs + 1] = "questIds 數量 " .. #D.questIds() .. " vs " .. nq end
if #D.entityKeys() ~= ne then errs[#errs + 1] = "entityKeys 數量" end
-- spawns 與 entity.sp 一致
for k, e in pairs(L.E) do
  for _, sp in ipairs(e.sp) do
    local found = false
    for x, y in D.spawns(k, sp.m) do if x == sp.x and y == sp.y then found = true end end
    if not found then errs[#errs + 1] = "spawns 缺 " .. k end
  end
end
io.write(#errs == 0 and "OK" or table.concat(errs, "\\n", 1, math.min(#errs, 10)), " ", nq, " ", ne, " ", nb)
"""


def _run_same_answers(tmp_path, data):
    legacy = tmp_path / "legacy.lua"
    legacy.write_text("".join(legacy_format.build_legacy_lua(data)[0]), encoding="utf-8")
    new = build_to(tmp_path, data)
    r = subprocess.run(["luajit", "-e", _same_answers_script(legacy, new)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith("OK "), r.stdout
    return r.stdout


def test_data_api_same_answers_as_before_fixture(tmp_path):
    assert _run_same_answers(tmp_path, load_fixture()) == "OK 5 2 2"


@pytest.mark.skipif(not REAL_EXPORT.exists(), reason="build/export.json 是 gitignored 的 prod 匯出，CI 沒有")
def test_data_api_same_answers_as_before_real_export(tmp_path):
    data = json.loads(REAL_EXPORT.read_text(encoding="utf-8"))
    data["schemaVersion"] = SCHEMA_OF_TEST_EXPORT  # build/export.json 可能還是舊版（無描述）；兩種格式的比對與描述無關
    out = _run_same_answers(tmp_path, data)
    # 數量跟著本機的 prod 匯出走（每次重新匯出都會變），不寫死
    assert out.startswith(f"OK {len(data['quests'])} ")


def _mem_delta_kb(lua_file, with_data_lua):
    code = f"""
collectgarbage(); collectgarbage()
local a = collectgarbage("count")
dofile({json.dumps(str(lua_file))})
KEEP = {{}}  -- ns 要留著，打包字串才不會被回收
if {str(with_data_lua).lower()} then assert(loadfile({json.dumps(str(DATA_LUA))}))("QuestMapGuide", KEEP) end
collectgarbage(); collectgarbage()
io.write(string.format("%.1f", collectgarbage("count") - a))
"""
    r = subprocess.run(["luajit", "-e", code], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    return float(r.stdout)


@pytest.mark.skipif(not REAL_EXPORT.exists(), reason="build/export.json 是 gitignored 的 prod 匯出，CI 沒有")
def test_build_size_reduced(tmp_path):
    data = json.loads(REAL_EXPORT.read_text(encoding="utf-8"))
    data["schemaVersion"] = SCHEMA_OF_TEST_EXPORT  # build/export.json 可能還是舊版（無描述）；兩種格式的比對與描述無關
    old = tmp_path / "old.lua"
    old.write_text("".join(legacy_format.build_legacy_lua(data)[0]), encoding="utf-8")
    new = build_to(tmp_path, data)
    old_kb = _mem_delta_kb(old, False)
    new_kb = _mem_delta_kb(new, True)
    print(f"\nluajit 記憶體增量：舊 {old_kb / 1024:.2f} MB → 新 {new_kb / 1024:.2f} MB（{(1 - new_kb / old_kb) * 100:.1f}% 減少）；"
          f"檔案 舊 {old.stat().st_size} → 新 {new.stat().st_size} bytes")
    assert new_kb <= old_kb * 0.75, "資料瘦身目標：luajit 增量至少減少 25%"


def test_entity_zh_name_is_written_when_present(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, 'D.entity("n9901001").zh') == "測試NPC"
    assert run_lua(out, 'D.entity("o9901001").zh') == "nil"   # nameZhTw 為 null：不寫


# ---- 任務描述組 d（schema 3）----
DESC1 = '甲\n他說：「"快來"」\n乙\\丙'


def test_rejects_schema_v2():
    d = load_fixture()
    d["schemaVersion"] = 2
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "schemaVersion" in str(e.value)


def test_description_group_newlines_normalized_and_absent_keys(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "D.desc(9900001)") == DESC1  # \r\n 與 \r 都轉成 \n，引號與反斜線原樣
    assert run_lua(out, "D.desc(9900002)") == "Plain English description."
    assert run_lua(out, "D.desc(9900003)") == "nil"  # null → 沒有該鍵
    assert run_lua(out, "D.desc(9900004)") == "nil"  # 缺鍵
    assert run_lua(out, "D.desc(1)") == "nil" and run_lua(out, "D.desc(nil)") == "nil"
    text = "".join(build_data.build_quests_lua(load_fixture())[0])
    assert "\r" not in text


def test_description_not_in_quest_record(tmp_path):
    d = load_fixture()
    rec = build_data.quest_record(d["quests"][0])
    assert "description" not in rec and "d" not in rec and "desc" not in rec
    out = build_to(tmp_path, d)
    assert run_lua(out, "D.quest(9900001).description") == "nil"
    assert run_lua(out, "D.quest(9900001).d") == "nil"
    # 描述文字不會出現在任務組 q 的資料字串裡
    q_s = re.search(r"QMG_Data\.q = \{\nix=\"[^\"]*\",\ns=\"(.*?)\"\}\n", out.read_text(encoding="utf-8"), re.S).group(1)
    assert "快來" not in q_s and "Plain English" not in q_s


def test_description_raw_utf8_no_escape(tmp_path):
    out = build_to(tmp_path, load_fixture())
    text = out.read_text(encoding="utf-8")
    assert "甲" in text and "快來" in text  # 中文原始 UTF-8，不跳脫成 \\ddd
    assert not re.search(r"\\\d{3}", text)
    assert "Plain English description." in text  # 原樣，不跳脫成 \ddd


def test_rejects_simplified_in_description():
    d = load_fixture()
    d["quests"][0]["description"] = "这是简体描述"
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "9900001" in str(e.value) and "description" in str(e.value)


def test_description_must_be_string():
    d = load_fixture()
    d["quests"][0]["description"] = 123
    with pytest.raises(build_data.BuildError):
        build_data.build_quests_lua(d)


@pytest.mark.parametrize("bad", [
    [{"source": "cmangos"}],
    [{"source": "cmangos", "questId": None}],
    [{"source": "cmangos", "questId": "6383"}],
    [{"source": "cmangos", "questId": True}],
    [6383],
])
def test_relation_element_without_integer_questid_fails(tmp_path, bad):
    data = load_fixture()
    data["quests"][1]["prevs"] = bad
    with pytest.raises(build_data.BuildError):
        build_to(tmp_path, data)


# ===== 0.2.0 節慶：categoryId → h（1＝節慶、2＝暗月馬戲團，其他不寫） =====
def _q(cat, **extra):
    q = copy.deepcopy(load_fixture()["quests"][0])
    if cat == "absent":
        q.pop("categoryId", None)
    else:
        q["categoryId"] = cat
    q.update(extra)
    return q


@pytest.mark.parametrize("cat,h", [(22, 1), (366, 1), (369, 1), (364, 2), (12, None), (None, None), ("absent", None)])
def test_category_maps_to_holiday_field(cat, h):
    r = build_data.quest_record(_q(cat))
    assert r.get("h") == h
    assert "categoryId" not in r


def test_holiday_categories_in_one_constant():
    assert build_data.HOLIDAY_CATEGORY == {22: 1, 366: 1, 369: 1, 364: 2}


def test_category_must_be_integer():
    with pytest.raises(build_data.BuildError) as e:
        build_data.quest_record(_q("22"))
    assert "categoryId" in str(e.value)
    with pytest.raises(build_data.BuildError):
        build_data.quest_record(_q(True))


def test_holiday_field_in_lua(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "D.quest(9900005).h") == "1"   # fixture：366 新年慶典
    assert run_lua(out, "D.quest(9900004).h") == "2"   # fixture：364 暗月馬戲團
    assert run_lua(out, "D.quest(9900002).h") == "nil"  # fixture：其他分類
    assert run_lua(out, "D.quest(9900001).h") == "nil"  # fixture：沒有 categoryId


# ---- V298：副本維度（spec 2026-11-27-wow-quest-dungeons-design.md 第六節）
def test_dungeon_group_and_dg(tmp_path):
    out = build_to(tmp_path, load_fixture())
    assert run_lua(out, "table.concat(D.quest(9900002).dg, ',')") == "33,409"
    assert run_lua(out, "D.quest(9900003).dg") == "nil"
    assert run_lua(out, "table.concat(D.byDungeon(33), ',')") == "9900001,9900002"
    assert run_lua(out, "#D.byDungeon(2875)") == "0"
    assert run_lua(out, "D.dungeon(33).n .. '/' .. D.dungeon(33).t .. '/' .. D.dungeon(33).lv") == "影牙城堡/dungeon/18"
    assert run_lua(out, "D.dungeon(2875).lv") == "nil"
    assert run_lua(out, "table.concat(D.dungeon(33).b, ',')") == "雷希戈爾,大法師阿魯高"
    assert run_lua(out, "#D.dungeon(409).b") == "0"
    assert run_lua(out, "D.dungeon(1)") == "nil"
    # 清單：地城在前、團隊在後；同組依建議等級，沒有等級的放最後
    assert run_lua(out, "(function() local t = {} for _, x in ipairs(D.dungeons()) do t[#t+1] = x.id end return table.concat(t, ',') end)()") == "33,2875,409"


def test_missing_dungeons_key_fails():
    d = load_fixture()
    del d["dungeons"]
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "dungeons" in str(e.value)


def test_quest_dungeon_not_in_table_fails():
    d = load_fixture()
    d["quests"][0]["dungeons"] = [99999]
    with pytest.raises(build_data.BuildError) as e:
        build_data.build_quests_lua(d)
    assert "99999" in str(e.value)
