"""舊格式（schema 2 輸出：QMG_Quests／QMG_Entities／QMG_ByMap 三個全域表）的產生器。

只給測試用：`test_data_api_same_answers_as_before` 拿它當對照，`test_build_size_reduced` 拿它當記憶體基準。
正式輸出已改成 build_data.py 的打包格式（Data.lua 讀取）。
"""
import sys

import build_data
from build_data import (BuildError, NIL, SCHEMA, check_simplified, entity_key, entity_record, lua_num, lua_str,
                        quest_record, LUA_KEYWORDS)

# 一個 Lua function 的常數表上限是 2^18（Lua 5.1 的 MAXARG_Bx）。luajit 的上限更寬，
# 編譯成功不代表遊戲內的 PUC Lua 5.1 不會爆，所以自己數、分段，並留餘裕。
# （實測 LuaJIT 的上限是 2^16，反而更嚴；預算抓 30000 兩邊都過。）
CONST_HARD_LIMIT = 2 ** 18
CONST_BUDGET = 30_000  # 同時守住 LuaJIT 的 2^16（數字與字串各自索引）

class Consts:
    """一個 Lua function 的常數集合（字串與數字各自去重，與編譯器一致）。"""

    def __init__(self):
        self.s = set()

    def add(self, v):
        self.s.add((type(v) is str, v))

    def __len__(self):
        return len(self.s)


def ser(v, consts: Consts) -> str:
    """序列化。dict 的字串鍵寫成 key=、整數鍵寫成 [n]=；list 寫成陣列。"""
    if v is NIL:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, str):
        consts.add(v)
        return lua_str(v)
    if isinstance(v, (int, float)):
        consts.add(v)
        return lua_num(v)
    if isinstance(v, list):
        return "{" + ",".join(ser(x, consts) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if isinstance(k, str) and k.isidentifier() and k.isascii() and k not in LUA_KEYWORDS:
                consts.add(k)
                parts.append(f"{k}={ser(x, consts)}")
            else:
                parts.append(f"[{ser(k, consts)}]={ser(x, consts)}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"無法序列化 {type(v)}")


def _function_chunks(stmts):
    """stmts: [(語句文字, 該語句的常數 set)]。依常數預算切成多個 function。回傳 [(文字, 常數數)]。"""
    chunks, cur, consts = [], [], Consts()
    for text, cs in stmts:
        if cur and len(consts.s) + len(cs - consts.s) > CONST_BUDGET:
            chunks.append(("".join(cur), len(consts)))
            cur, consts = [], Consts()
        cur.append(text)
        consts.s |= cs
    if cur:
        chunks.append(("".join(cur), len(consts)))
    return chunks


def _stmt(prefix, key, value, what):
    c = Consts()
    # prefix 是函式參數名（區域變數），鍵與值才產生常數
    try:
        text = f"{prefix}[{ser(key, c)}]={ser(value, c)}\n"
    except TypeError as ex:
        raise BuildError(f"{what} 含無法序列化的值（null 出現在不允許的位置）：{ex}") from None
    return text, c.s


def build_quests_lua(data):
    """回傳 (文字片段 list, 每個 Lua function 的常數數 list)。"""
    if data.get("schemaVersion") != SCHEMA:
        raise BuildError(f"schemaVersion 必須是 {SCHEMA}，得到 {data.get('schemaVersion')!r}")
    if data.get("env") != "prod":
        print(f"警告：匯出的 env 是 {data.get('env')!r} 不是 prod；發佈用的資料必須來自 prod", file=sys.stderr)
    check_simplified(data)

    quests = sorted(data["quests"], key=lambda q: q["questId"])
    ids = [q["questId"] for q in quests]
    if len(set(ids)) != len(ids):
        raise BuildError("questId 重複")
    entities = {}
    for e in data.get("entities") or []:
        k = entity_key(e.get("kind"), e["entityId"])
        if k in entities:
            raise BuildError(f"entity 重複：{k}")
        entities[k] = entity_record(e, k)

    records = {}
    for q in quests:
        try:
            records[q["questId"]] = quest_record(q)
        except BuildError:
            raise
        except (KeyError, TypeError, ValueError, AttributeError) as ex:
            raise BuildError(f"任務 {q['questId']} 資料格式錯誤：{ex!r}") from None
    dangling = {k for r in records.values() for k in (r.get("s") or []) + (r.get("e") or [])} - set(entities)
    if dangling:
        print(f"警告：{len(dangling)} 個起終點 entity 不在 entities 裡（pins 會缺）", file=sys.stderr)
    by_map: dict[int, list[int]] = {}
    for qid in ids:
        for m in records[qid]["maps"]:
            by_map.setdefault(m, []).append(qid)

    meta = {"schema": SCHEMA, "sourceVersion": data.get("sourceVersion"),
            "officialExportDate": data.get("officialExportDate"), "wagoBuild": data.get("wagoBuild"),
            "exportedAt": data.get("exportedAt"), "env": data.get("env"),
            "quests": len(quests), "entities": len(entities)}
    meta = {k: v for k, v in meta.items() if v is not None}

    head_c = Consts()
    head = ("-- 由 tools/build_data.py 產生，請勿手改。資料來源與授權見 NOTICE。\n"
            "-- 欄位 nil = 未知，空表 = 已知為空。位置式欄位：\n"
            "--   sk = {skillId, value}；ri = {{itemId, count, isChoice}, ...}\n"
            "--   sk[2] 與 ri[*][2] 可能是 nil（未知，不是 0 或 1）：只能用 [1]/[2]/[3] 取值，禁止對這些表用 # 或 ipairs\n"
            "--   s / e = QMG_Entities 的鍵（\"n<id>\" npc、\"o<id>\" object）\n"
            "QMG_Quests = {}\nQMG_Entities = {}\nQMG_ByMap = {}\n"
            f"QMG_Meta = {ser(meta, head_c)};\n")
    parts, stats = [head], [len(head_c)]

    def emit(var, glob, stmts):
        for text, n in _function_chunks(stmts):
            if n >= CONST_HARD_LIMIT:
                raise BuildError(f"單一 chunk 常數 {n} 超過 2^18")
            parts.append(f"(function({var})\n{text}end)({glob});\n")
            stats.append(n)

    emit("Q", "QMG_Quests", [_stmt("Q", qid, records[qid], f"任務 {qid}") for qid in ids])
    emit("E", "QMG_Entities", [_stmt("E", k, entities[k], f"entity {k}") for k in sorted(entities)])
    emit("B", "QMG_ByMap", [_stmt("B", m, by_map[m], f"ByMap[{m}]") for m in sorted(by_map)])
    return parts, stats


def build_legacy_lua(data):
    """回傳 (文字片段 list, 每個 Lua function 的常數數 list)。"""
    if data.get("schemaVersion") != SCHEMA:
        raise BuildError(f"schemaVersion 必須是 {SCHEMA}，得到 {data.get('schemaVersion')!r}")
    if data.get("env") != "prod":
        print(f"警告：匯出的 env 是 {data.get('env')!r} 不是 prod；發佈用的資料必須來自 prod", file=sys.stderr)
    check_simplified(data)

    quests = sorted(data["quests"], key=lambda q: q["questId"])
    ids = [q["questId"] for q in quests]
    if len(set(ids)) != len(ids):
        raise BuildError("questId 重複")
    entities = {}
    for e in data.get("entities") or []:
        k = entity_key(e.get("kind"), e["entityId"])
        if k in entities:
            raise BuildError(f"entity 重複：{k}")
        entities[k] = entity_record(e, k)

    records = {}
    for q in quests:
        try:
            records[q["questId"]] = quest_record(q)
        except BuildError:
            raise
        except (KeyError, TypeError, ValueError, AttributeError) as ex:
            raise BuildError(f"任務 {q['questId']} 資料格式錯誤：{ex!r}") from None
    dangling = {k for r in records.values() for k in (r.get("s") or []) + (r.get("e") or [])} - set(entities)
    if dangling:
        print(f"警告：{len(dangling)} 個起終點 entity 不在 entities 裡（pins 會缺）", file=sys.stderr)
    by_map: dict[int, list[int]] = {}
    for qid in ids:
        for m in records[qid]["maps"]:
            by_map.setdefault(m, []).append(qid)

    meta = {"schema": SCHEMA, "sourceVersion": data.get("sourceVersion"),
            "officialExportDate": data.get("officialExportDate"), "wagoBuild": data.get("wagoBuild"),
            "exportedAt": data.get("exportedAt"), "env": data.get("env"),
            "quests": len(quests), "entities": len(entities)}
    meta = {k: v for k, v in meta.items() if v is not None}

    head_c = Consts()
    head = ("-- 由 tools/build_data.py 產生，請勿手改。資料來源與授權見 NOTICE。\n"
            "-- 欄位 nil = 未知，空表 = 已知為空。位置式欄位：\n"
            "--   sk = {skillId, value}；ri = {{itemId, count, isChoice}, ...}\n"
            "--   sk[2] 與 ri[*][2] 可能是 nil（未知，不是 0 或 1）：只能用 [1]/[2]/[3] 取值，禁止對這些表用 # 或 ipairs\n"
            "--   s / e = QMG_Entities 的鍵（\"n<id>\" npc、\"o<id>\" object）\n"
            "QMG_Quests = {}\nQMG_Entities = {}\nQMG_ByMap = {}\n"
            f"QMG_Meta = {ser(meta, head_c)};\n")
    parts, stats = [head], [len(head_c)]

    def emit(var, glob, stmts):
        for text, n in _function_chunks(stmts):
            if n >= CONST_HARD_LIMIT:
                raise BuildError(f"單一 chunk 常數 {n} 超過 2^18")
            parts.append(f"(function({var})\n{text}end)({glob});\n")
            stats.append(n)

    emit("Q", "QMG_Quests", [_stmt("Q", qid, records[qid], f"任務 {qid}") for qid in ids])
    emit("E", "QMG_Entities", [_stmt("E", k, entities[k], f"entity {k}") for k in sorted(entities)])
    emit("B", "QMG_ByMap", [_stmt("B", m, by_map[m], f"ByMap[{m}]") for m in sorted(by_map)])
    return parts, stats


