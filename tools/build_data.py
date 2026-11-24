#!/usr/bin/env python3.12
"""AgentSpace v3 匯出 JSON 轉成 addon 載入的 Lua 資料檔。

用法：python3.12 tools/build_data.py quests --in build/export.json --out Data/Forever/Quests.lua

輸出（Lua 5.1 全域）：
  QMG_Meta   匯出資訊（小表，載入後直接可讀）
  QMG_Data   打包資料，由 Data.lua 建索引後以 ns.Data 提供讀取；Panel／Pins 不直接碰它
             {fmt=格式版本, q=任務, e=entity, m=地圖索引, d=任務描述}，每一組是 {ix=索引字串, s=資料字串}：
             s 是一長串依序接起來的記錄，ix 是 "鍵:記錄位元組數,鍵:位元組數,…"（Data.lua 載入時掃一遍成雜湊）。
             記錄只在被讀取時才解碼成表，所以常駐記憶體只有字串本身。
             鍵：任務是 questId 數字；entity 是 "n<id>"（npc）或 "o<id>"（object）——id 會撞，所以加 kind 前綴，
             任務的 s／e 引用同一種鍵；地圖是 uiMapId，值是遞增的 questId 清單。
             d 是 questId → 描述字串（值是字串不是表；換行一律 \n；沒有描述的任務沒有該鍵）。任務記錄不含描述。
記錄編碼（解碼器是 Data.lua 的 dec）：
  {…}        表；內容是 "鍵=值" 或位置式的值，以逗號分隔（位置式的 nil 寫 ~，佔一個位置）
  ~ T F      nil／true／false
  數字       [-]數字[.小數]（不寫指數）
  s<n>:…     字串，n 是位元組數（內容原樣，不跳脫）
任務的 prev／next／conc／excl 是純 questId 數字清單（匯出的 {source, questId} 物件在建置時轉換，元素缺整數 questId 即 BuildError）。
欄位為 nil＝未知；空表＝已知為空。輸出不含 source／correction 等來源欄位。
"""
import argparse
import json
import keyword
import os
import re
import sys
import tempfile
from pathlib import Path

SCHEMA = 3
FORMAT = 1  # QMG_Data.fmt；編碼或索引改變時加一，Data.lua 不認得的版本就當沒有資料
KIND_PREFIX = {"npc": "n", "object": "o"}
FACTION = {"ALLIANCE": "A", "HORDE": "H"}

# 簡體防線：zh_TW 出現這些字（正體寫法不同的簡體字）就是資料混進簡體。
# 只收「正體不會用」的字；兩岸同形或正體也用的字（云、余、干、后、里…）不收，避免誤傷。
SIMPLIFIED_CHARS = (
    "这们个为说时来对发会过还进关点门问间现东车长马鸟鱼龙书买卖汉号务区华单历县叶吗乐习乡产亲从众优传伤价"
    "见观认让话请谁语读该总带师兴爱态难队阳阴风飞饭馆骑杀轮红级纪给结线练续约经绿网尔"
)


CJK = re.compile("[\u2e80-\u303f\u3040-\u30ff\u3100-\u312f\u3400-\u4dbf\u4e00-\u9fff\uac00-\ud7af\uf900-\ufaff\uff00-\uffef]")
LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
                "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


class BuildError(Exception):
    pass


def lua_str(s: str) -> str:
    out = ['"']
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 32:
            out.append("\\%03d" % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_num(v) -> str:
    if isinstance(v, int):
        return str(v)
    s = ("%.1f" % v).rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


class _Nil:
    """位置式欄位裡的 nil（未知）。只有 sk[2] 與 ri[*][2] 允許。"""


NIL = _Nil()


def entity_key(kind, entity_id) -> str:
    if kind not in KIND_PREFIX:
        raise BuildError(f"不認得的 entity kind：{kind!r}（entityId {entity_id}）")
    return f"{KIND_PREFIX[kind]}{int(entity_id)}"


def _ids(refs, qid, what):
    """起點／終點 → 去重、保序的 entity 鍵。None（未知）原樣回傳 None；沒有 entityId 的項目警告後略過。"""
    if refs is None:
        return None
    seen, out = set(), []
    for r in refs:
        if r.get("entityId") is None:
            print(f"警告：任務 {qid} 的 {what} 有一筆沒有 entityId（kind={r.get('kind')!r}），已略過", file=sys.stderr)
            continue
        k = entity_key(r.get("kind"), r["entityId"])
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


def check_simplified(data) -> None:
    bad = []
    for q in data["quests"]:
        names = q.get("names") or {}
        if "zh_CN" in names:
            bad.append(f"任務 {q['questId']} names 有 zh_CN 鍵")
        if CJK.search(names.get("en_US") or ""):
            bad.append(f"任務 {q['questId']} en_US 含中日韓字元")
        hit = sorted(set(names.get("zh_TW") or "") & set(SIMPLIFIED_CHARS))
        if hit:
            bad.append(f"任務 {q['questId']} zh_TW 含簡體字 {''.join(hit)}")
        hit = sorted(set(q.get("description") or "") & set(SIMPLIFIED_CHARS)) if isinstance(q.get("description"), str) else []
        if hit:
            bad.append(f"任務 {q['questId']} description 含簡體字 {''.join(hit)}")
    for e in data.get("entities") or []:
        if CJK.search(e.get("nameEnUs") or ""):
            bad.append(f"entity {KIND_PREFIX.get(e.get('kind'), '?')}{e.get('entityId')} nameEnUs 含中日韓字元")
        hit = sorted(set(e.get("nameZhTw") or "") & set(SIMPLIFIED_CHARS))
        if hit:
            bad.append(f"entity {KIND_PREFIX.get(e.get('kind'), '?')}{e.get('entityId')} nameZhTw 含簡體字 {''.join(hit)}")
    if bad:
        raise BuildError("簡體防線失敗：\n  " + "\n  ".join(bad))


def description_text(q):
    """匯出的 description → 建置用字串（\r\n、\r 轉 \n）；null／缺鍵／空白回 None。"""
    d = q.get("description")
    if d is None:
        return None
    if not isinstance(d, str):
        raise BuildError(f"任務 {q['questId']} description 必須是字串或 null，得到 {type(d).__name__}")
    d = d.replace("\r\n", "\n").replace("\r", "\n")
    return d if d.strip() else None


def _relation_ids(lst, qid, field):
    """匯出的關聯元素是 {"source":…, "questId":N}；建置後只留 questId 整數（addon 端當數字用）。"""
    out = []
    for i, e in enumerate(lst):
        v = e.get("questId") if isinstance(e, dict) else None
        if not (isinstance(v, int) and not isinstance(v, bool)):
            raise BuildError(f"任務 {qid} {field}[{i}] 必須是含整數 questId 的物件，得到 {e!r}")
        out.append(v)
    return out


def quest_record(q) -> dict:
    names = q.get("names") or {}
    n = {}
    if names.get("zh_TW"):
        n["zh"] = names["zh_TW"]
    if names.get("en_US"):
        n["en"] = names["en_US"]
    r = {"n": n, "lv": q.get("questLevel"), "min": q.get("minLevel")}
    f = FACTION.get(q.get("faction"))
    if f:
        r["f"] = f
    for src, dst in (("classes", "cls"), ("races", "race")):
        if q.get(src) is not None:
            r[dst] = list(q[src])
    sk = q.get("skill")
    if sk:
        if sk["id"] is None:
            raise BuildError(f"任務 {q['questId']} skill.id 是 null")
        r["sk"] = [sk["id"], NIL if sk["value"] is None else sk["value"]]
    r["maps"] = list(dict.fromkeys(q.get("uiMapIds") or []))
    r["s"] = _ids(q.get("starts"), q["questId"], "starts")
    r["e"] = _ids(q.get("ends"), q["questId"], "ends")
    for src, dst in (("prevs", "prev"), ("nexts", "next"), ("concurrents", "conc"), ("exclusives", "excl")):
        if q.get(src) is not None:
            r[dst] = _relation_ids(q[src], q["questId"], src)
    if q.get("rewardItems") is not None:
        for i in q["rewardItems"]:
            if i["id"] is None:
                raise BuildError(f"任務 {q['questId']} rewardItems 有 id 為 null")
        r["ri"] = [[i["id"], NIL if i["count"] is None else i["count"], bool(i["choice"])] for i in q["rewardItems"]]
    rw = q.get("rewards") or {}
    r["xp"] = rw.get("experience")
    r["cu"] = rw.get("moneyCopper")
    r["t"] = q.get("typeId")
    return {k: v for k, v in r.items() if v is not None}


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def entity_record(e, key) -> dict:
    sp = []
    for i, s in enumerate(e.get("spawns") or []):
        m, x, y = s.get("uiMapId"), s.get("x"), s.get("y")
        if not (isinstance(m, int) and not isinstance(m, bool) and m > 0):
            raise BuildError(f"entity {key} spawn[{i}] uiMapId 必須是正整數，得到 {m!r}")
        if not (_num(x) and _num(y) and 0 <= x <= 100 and 0 <= y <= 100):
            raise BuildError(f"entity {key} spawn[{i}] x/y 必須在 0–100，得到 {x!r}, {y!r}")
        sp.append({"m": m, "x": round(float(x), 1), "y": round(float(y), 1)})
    rec = {"n": e.get("nameEnUs") or "", "sp": sp}
    zh = e.get("nameZhTw")
    if isinstance(zh, str) and zh:
        rec["zh"] = zh   # 內建繁中名稱；沒有就省略（顯示時退回學到的名稱或英文）
    return rec


KEY = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


def enc(v) -> str:
    """把一個值編成記錄文字（格式見模組說明）。dict 的鍵必須是識別字；list 內可以有 NIL。"""
    if v is NIL:
        return "~"
    if v is True:
        return "T"
    if v is False:
        return "F"
    if isinstance(v, str):
        return f"s{len(v.encode('utf-8'))}:{v}"
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, list):
        return "{" + ",".join(enc(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if not (isinstance(k, str) and KEY.match(k)):
                raise TypeError(f"鍵必須是識別字：{k!r}")
            parts.append(f"{k}={enc(x)}")
        return "{" + ",".join(parts) + "}"
    raise TypeError(f"無法編碼 {type(v)}")


def pack(items, what):
    """items: [(鍵, 值)] → (索引字串, 資料字串)。鍵的順序就是記錄的順序。"""
    ix, body = [], []
    for key, value in items:
        try:
            rec = enc(value)
        except TypeError as ex:
            raise BuildError(f"{what} {key} 含無法編碼的值（null 出現在不允許的位置）：{ex}") from None
        ix.append(f"{key}:{len(rec.encode('utf-8'))}")
        body.append(rec)
    return ",".join(ix), "".join(body)


def prepare(data):
    """驗證匯出並整理成 (ids, records, entities, by_map, meta, descs)。"""
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
    descs = {}
    for q in quests:
        d = description_text(q)
        if d is not None:
            descs[q["questId"]] = d
    by_map: dict[int, list[int]] = {}
    for qid in ids:
        for m in records[qid]["maps"]:
            by_map.setdefault(m, []).append(qid)

    meta = {"schema": SCHEMA, "sourceVersion": data.get("sourceVersion"),
            "officialExportDate": data.get("officialExportDate"), "wagoBuild": data.get("wagoBuild"),
            "exportedAt": data.get("exportedAt"), "env": data.get("env"),
            "quests": len(quests), "entities": len(entities)}
    meta = {k: v for k, v in meta.items() if v is not None}
    return ids, records, entities, by_map, meta, descs


def _lua_meta(meta) -> str:
    return "{" + ",".join(f"{k}={lua_str(v) if isinstance(v, str) else lua_num(v)}" for k, v in meta.items()) + "}"


def build_quests_lua(data):
    """回傳 (文字片段 list, 每段的資料字串位元組數 list)。"""
    ids, records, entities, by_map, meta, descs = prepare(data)
    head = ("-- 由 tools/build_data.py 產生，請勿手改。資料來源與授權見 NOTICE。\n"
            "-- 打包格式（說明見 tools/build_data.py 開頭）：程式不直接讀 QMG_Data，一律走 Data.lua 的 ns.Data。\n"
            "-- 欄位 nil = 未知，空表 = 已知為空。位置式欄位（解碼後）：\n"
            "--   sk = {skillId, value}；ri = {{itemId, count, isChoice}, ...}\n"
            "--   sk[2] 與 ri[*][2] 可能是 nil（未知，不是 0 或 1）：只能用 [1]/[2]/[3] 取值，禁止對這些表用 # 或 ipairs\n"
            "--   s / e = entity 鍵（\"n<id>\" npc、\"o<id>\" object）\n"
            f"QMG_Meta = {_lua_meta(meta)}\n"
            f"QMG_Data = {{fmt={FORMAT}}}\n")
    parts, stats = [head], []
    groups = (("q", "任務", [(qid, records[qid]) for qid in ids]),
              ("e", "entity", [(k, entities[k]) for k in sorted(entities)]),
              ("m", "ByMap", [(m, by_map[m]) for m in sorted(by_map)]),
              ("d", "描述", [(qid, descs[qid]) for qid in ids if qid in descs]))
    for var, what, items in groups:
        ix, body = pack(items, what)
        parts.append(f"QMG_Data.{var} = {{\nix={lua_str(ix)},\ns={lua_str(body)}}}\n")
        stats.append(len(body.encode("utf-8")))
    return parts, stats


def write_quests_lua(data, out: Path) -> list[int]:
    parts, stats = build_quests_lua(data)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", newline="\n", dir=out.parent, suffix=".tmp", delete=False) as f:
            tmp = f.name
            f.write("".join(parts))
        os.chmod(tmp, 0o644)
        os.replace(tmp, out)
    except BaseException:
        if tmp:
            Path(tmp).unlink(missing_ok=True)
        raise
    return stats


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)
    q = sub.add_parser("quests", help="任務／entity／地圖索引")
    q.add_argument("--in", dest="inp", required=True)
    q.add_argument("--out", required=True)
    a = p.parse_args(argv)
    try:
        data = json.loads(Path(a.inp).read_text(encoding="utf-8"))
        stats = write_quests_lua(data, Path(a.out))
    except (BuildError, OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        print(f"失敗：{e!r}" if not isinstance(e, BuildError) else f"失敗：{e}", file=sys.stderr)
        return 1
    print(f"{a.out}: {len(data['quests'])} quests，資料字串 {sum(stats)} 位元組")
    return 0


if __name__ == "__main__":
    sys.exit(main())
