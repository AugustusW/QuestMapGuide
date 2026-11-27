-- 內建資料的讀取介面（ns.Data）。Panel／Pins 只准透過這裡讀資料；資料檔的格式只有這個檔與 tools/build_data.py 知道。
-- 格式與編碼說明見 tools/build_data.py 開頭。載入順序：Data/Forever/Quests.lua（定義 QMG_Data）→ 本檔 → LoadEnd.lua，
-- 所以索引的記憶體與時間會算進 /qmg stats。
--
-- 回傳的表一律是「讀取當下新解碼的」：呼叫端可以改，不影響資料；欄位語意（缺＝未知、{}＝已知為空、
-- sk／ri 內可能有 nil 位置）與舊格式完全相同。呼叫端已經有 entity 表時，把表直接傳給 spawns() 就不必再解碼一次。
local _, ns = ...

local Data = {}
ns.Data = Data

local byte, sub, match, gmatch = string.byte, string.sub, string.match, string.gmatch
local tonumber = tonumber

-- 從 s 的第 p 個位元組解出一個值，回傳 值, 下一個位置
local function dec(s, p)
  local c = byte(s, p)
  if c == 123 then                      -- {
    local t, n = {}, 0
    p = p + 1
    if byte(s, p) == 125 then return t, p + 1 end
    while true do
      local k = match(s, "^([%a_][%w_]*)=", p)
      local v
      if k then
        v, p = dec(s, p + #k + 1)
        t[k] = v
      else
        n = n + 1
        v, p = dec(s, p)
        t[n] = v                        -- 位置式的 nil 只佔位置
      end
      local d = byte(s, p)
      p = p + 1
      if d ~= 44 then return t, p end   -- 44 是逗號；其餘一定是 }
    end
  elseif c == 115 then                  -- s<len>:bytes
    local len, q = match(s, "^(%d+):()", p + 1)
    len = tonumber(len)
    return sub(s, q, q + len - 1), q + len
  elseif c == 126 then return nil, p + 1   -- ~
  elseif c == 84 then return true, p + 1   -- T
  elseif c == 70 then return false, p + 1  -- F
  end
  local num, q = match(s, "^(-?[%d.]+)()", p)
  return tonumber(num), q
end

local FORMAT = 1
local EMPTY = { s = "", idx = {} }

-- 掃索引字串 "鍵:位元組數,…"，建出 鍵 → 記錄起點
local function open(group)
  if type(group) ~= "table" or type(group.ix) ~= "string" or type(group.s) ~= "string" then return EMPTY end
  local idx, pos = {}, 1
  for k, len in gmatch(group.ix, "([^:,]+):(%d+)") do
    idx[tonumber(k) or k] = pos
    pos = pos + tonumber(len)
  end
  -- 完整性：各記錄長度加總必須等於資料字串長度；不符代表資料檔壞了，整組當作空，不讀出錯位的記錄
  if pos - 1 ~= #group.s then return EMPTY end
  return { s = group.s, idx = idx }
end

local Q, E, M, DS, G, X = EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY
local raw = QMG_Data
if type(raw) == "table" and raw.fmt == FORMAT then
  Q, E, M, DS = open(raw.q), open(raw.e), open(raw.m), open(raw.d)
  G, X = open(raw.g), open(raw.x)   -- V298 副本與副本索引；舊資料檔沒有這兩組就是空
end
QMG_Data = nil   -- 字串只留在上面幾組；全域表與索引字串不必常駐

local function get(group, key)
  local p = key ~= nil and group.idx[key]
  if not p then return nil end
  return (dec(group.s, p))
end

local function sortedKeys(group)
  local t, n = {}, 0
  for k in pairs(group.idx) do n = n + 1; t[n] = k end
  table.sort(t)
  return t
end

-- ── 遊戲紀錄（Observe.lua 寫的 QuestMapGuideDB.obs）疊加 ─────────────────────────────
-- 原則：內建資料有值就不動，只補缺的（起點、交任務、獎勵物品為 nil 或空時），後續任務取聯集。
-- 補上的欄位記在 q.obs = { s=true, e=true, ri=true, next={[id]=true} }，明細據此標「遊戲紀錄」。
-- 起點／交任務的 NPC 若在內建資料裡且有座標，用內建 entity 鍵（位置與名稱較完整）；否則用合成鍵
-- "x<c|o><id>@<questId>@<s|e>"，Data.entity 由紀錄合成 {n, zh, sp}（座標換成 0–100）。
local function obsQuests()
  local db = ns.Core and ns.Core.db and ns.Core.db()
  local obs = type(db) == "table" and db.obs
  local qs = type(obs) == "table" and obs.quests
  return type(qs) == "table" and qs or nil
end
Data.obsQuests = obsQuests

local function obsKeys(list, qid, role)
  local keys, seen = {}, {}
  if type(list) ~= "table" then return keys end
  local recs = {}
  for k, r in pairs(list) do if type(r) == "table" and type(r.id) == "number" then recs[#recs + 1] = { k = k, r = r } end end
  table.sort(recs, function(a, b) return a.k < b.k end)
  for _, it in ipairs(recs) do
    local r = it.r
    local real = (r.kind == "o" and "o" or "n") .. r.id
    local key
    local e = get(E, real)
    if e and type(e.sp) == "table" and e.sp[1] then key = real
    else key = "x" .. (r.kind == "o" and "o" or "c") .. r.id .. "@" .. qid .. "@" .. role end
    if not seen[key] then seen[key] = true; keys[#keys + 1] = key end
  end
  return keys
end

local function empty(t) return t == nil or (type(t) == "table" and next(t) == nil) end

local function overlay(id, q, o)
  local mark = {}
  if not q then
    if type(o.title) ~= "string" then return nil end
    q = { n = { zh = o.title, en = o.title }, obsOnly = true }
  end
  if empty(q.s) then
    local keys = obsKeys(o.starts, id, "s")
    if keys[1] then q.s = keys; mark.s = true end
  end
  if empty(q.e) then
    local keys = obsKeys(o.ends, id, "e")
    if keys[1] then q.e = keys; mark.e = true end
  end
  local rw = type(o.rewards) == "table" and o.rewards or nil
  if rw and empty(q.ri) then
    local ri = {}
    for _, part in ipairs({ { rw.items, false }, { rw.choices, true } }) do
      if type(part[1]) == "table" then
        local ids = {}
        for itemId in pairs(part[1]) do if type(itemId) == "number" then ids[#ids + 1] = itemId end end
        table.sort(ids)
        for _, itemId in ipairs(ids) do ri[#ri + 1] = { itemId, tonumber(part[1][itemId]) or 1, part[2] } end
      end
    end
    if ri[1] then q.ri = ri; mark.ri = true end
  end
  if type(o.nexts) == "table" then
    local have, add = {}, {}
    for _, n in ipairs(q.next or {}) do have[n] = true end
    for n in pairs(o.nexts) do if type(n) == "number" and not have[n] then add[#add + 1] = n end end
    if add[1] then
      table.sort(add)
      q.next = q.next or {}
      mark.next = {}
      for _, n in ipairs(add) do q.next[#q.next + 1] = n; mark.next[n] = true end
    end
  end
  -- V298（G13 本機預覽）：內建沒有副本時，用自己記到的副本補（只限地下城 81／團隊 62 類型，與 golden 同規則）
  if empty(q.dg) and (q.t == 81 or q.t == 62) and type(o.dungeons) == "table" then
    local dg = {}
    for mid, n in pairs(o.dungeons) do
      if type(mid) == "number" and type(n) == "number" and n >= 1 and get(G, mid) then dg[#dg + 1] = mid end
    end
    if dg[1] then table.sort(dg); q.dg = dg; mark.dg = true end
  end
  if next(mark) then q.obs = mark end
  return q
end

-- 任務：id 是數字。沒有就 nil（內建沒有、但遊戲紀錄有名稱的任務也會回傳，q.obsOnly = true）
function Data.quest(id)
  local q = get(Q, id)
  local qs = obsQuests()
  local o = qs and qs[id]
  if type(o) ~= "table" then return q end
  return overlay(id, q, o)
end

-- 任務描述：questId → 字串（獨立一組，任務記錄不含；只在開明細時讀）。沒有就 nil。
-- DescDecodes() 是測試用計數器：搜尋與清單不該讀描述，測試靠它確認
local descDecodes = 0
function Data.desc(id)
  local p = id ~= nil and DS.idx[id]
  if not p then return nil end
  descDecodes = descDecodes + 1
  return (dec(DS.s, p))
end
function Data.DescDecodes() return descDecodes end

-- entity：鍵是 "n<id>"（npc）或 "o<id>"（object）。回傳 {n=名稱, sp={{m=,x=,y=}…}}；沒有就 nil
-- 合成鍵 "x..."：由遊戲紀錄合成（見上方 obsKeys），名稱同時放 n 與 zh
local function obsEntity(key)
  local kind, id, qid, role = match(key, "^x([co])(%d+)@(%d+)@([se])$")
  if not kind then return nil end
  local qs = obsQuests()
  local o = qs and qs[tonumber(qid)]
  local list = type(o) == "table" and o[role == "s" and "starts" or "ends"]
  local r = type(list) == "table" and list[kind .. id]
  if type(r) ~= "table" then return nil end
  local name = type(r.name) == "string" and r.name ~= "" and r.name or ("#" .. id)
  local e = { n = name, zh = name, obs = true, sp = {} }
  if type(r.map) == "number" and type(r.x) == "number" and type(r.y) == "number" then
    e.sp[1] = { m = r.map, x = r.x * 100, y = r.y * 100 }
  end
  return e
end

function Data.entity(key)
  if type(key) == "string" and byte(key, 1) == 120 then return obsEntity(key) end   -- 120 是 x
  return get(E, key)
end

-- 只查索引、不解碼：這個 entity 鍵在資料裡嗎（合成鍵不算）
function Data.hasEntity(key) return key ~= nil and E.idx[key] ~= nil end

-- 顯示用名稱：內建繁中（資料若帶 zh）→ 學到的繁中 → 英文；只有 zhTW 客戶端才用中文，其他語系一律英文。
-- 回傳 name, lang（"zh"／"learned"／"en"）, 英文名（搜尋用）；沒有這個 entity 回 nil。
-- key 是 "n<id>"；第二個參數可傳已解碼的 entity 表（省一次解碼）。第一個參數本身是 entity 表時，只用表內資料（查不到學到的名稱）。
function Data.npcName(key, ent)
  local e, id
  if type(key) == "table" then e = key
  else
    e = ent or Data.entity(key)
    id = type(key) == "string" and tonumber(key:match("^n(%d+)$"))
  end
  if not e then return nil end
  if GetLocale() ~= "zhTW" then return e.n, "en", e.n end
  if type(e.zh) == "string" and e.zh ~= "" then return e.zh, "zh", e.n end
  local db = ns.Core and ns.Core.db and ns.Core.db()
  local rec = id and type(db) == "table" and type(db.npcNames) == "table" and db.npcNames[id]
  if type(rec) == "table" and type(rec.name) == "string" and rec.name ~= "" then return rec.name, "learned", e.n end
  return e.n, "en", e.n
end

-- 這張地圖上的 questId 清單（遞增）；沒收錄回空表
-- 遊戲紀錄的起點在這張地圖上的任務也加進來（內建清單沒有的才加，結果維持遞增）
function Data.byMap(uiMapId)
  local list = get(M, uiMapId) or {}
  local qs = obsQuests()
  if not qs or uiMapId == nil then return list end
  local have, added = {}, false
  for _, id in ipairs(list) do have[id] = true end
  for id, o in pairs(qs) do
    if type(id) == "number" and not have[id] and type(o) == "table" and type(o.starts) == "table" then
      for _, r in pairs(o.starts) do
        if type(r) == "table" and r.map == uiMapId then
          local q = Data.quest(id)
          -- 在這張地圖上親眼接到過，就列在這張地圖（內建把它歸在別張地圖也一樣）
          if q then list[#list + 1] = id; have[id] = true; added = true end
          break
        end
      end
    end
  end
  if added then table.sort(list) end
  return list
end

-- ── 副本（V298）────────────────────────────────────────────────────────────────
-- 副本：mapId → {id, n=繁中名, t="dungeon"|"raid", lv=建議等級或 nil, b={首領名…}}；沒有就 nil
function Data.dungeon(mapId)
  local d = get(G, mapId)
  if not d then return nil end
  d.id = mapId
  d.b = d.b or {}
  return d
end

-- 全部副本：地城在前、團隊副本在後；同組依建議等級，沒有等級的放最後；再依名稱、mapId
function Data.dungeons()
  local list = {}
  for _, mid in ipairs(sortedKeys(G)) do list[#list + 1] = Data.dungeon(mid) end
  table.sort(list, function(a, b)
    if a.t ~= b.t then return a.t == "dungeon" end
    if (a.lv == nil) ~= (b.lv == nil) then return a.lv ~= nil end
    if a.lv ~= b.lv then return a.lv < b.lv end
    if a.n ~= b.n then return a.n < b.n end
    return a.id < b.id
  end)
  return list
end

-- 這個副本的 questId（遞增）；自己記到（遊戲紀錄）且類型是地下城／團隊的任務也加進來
function Data.byDungeon(mapId)
  local list = get(X, mapId) or {}
  local qs = obsQuests()
  if not qs or mapId == nil then return list end
  local have, added = {}, false
  for _, id in ipairs(list) do have[id] = true end
  for id, o in pairs(qs) do
    if type(id) == "number" and not have[id] and type(o) == "table" and type(o.dungeons) == "table" and o.dungeons[mapId] then
      local q = Data.quest(id)
      if q and q.obs and q.obs.dg then list[#list + 1] = id; have[id] = true; added = true end
    end
  end
  if added then table.sort(list) end
  return list
end

local function noop() end

-- entity 的出現位置：for x, y in Data.spawns(key, uiMapId) do；uiMapId 不給就是全部地圖。
-- key 也可以是 Data.entity() 回傳的表（已經解出來的就不再解碼）
function Data.spawns(key, uiMapId)
  local e = type(key) == "table" and key or Data.entity(key)
  local sp = e and e.sp
  if not sp then return noop end
  local i = 0
  return function()
    while true do
      i = i + 1
      local s = sp[i]
      if not s then return nil end
      if uiMapId == nil or s.m == uiMapId then return s.x, s.y end
    end
  end
end

-- 地圖名稱（遊戲值：型別與保密值都檢查，用不了就回 nil）。Panel 搜尋結果與 Detail 起點列共用
function Data.mapName(mapId)
  if not mapId or not (C_Map and C_Map.GetMapInfo) then return nil end
  local mi = C_Map.GetMapInfo(mapId)
  local nm = type(mi) == "table" and mi.name or nil
  -- 順序固定：型別 → 保密 → 才比較（遊戲值在確認非保密前不比較）
  if type(nm) ~= "string" or ns.Core.secret(nm) or nm == "" then return nil end
  return nm
end

-- 地點文字（清單副標、明細起點／交任務共用）：「NPC · 地圖名(x, y)」；沒有地圖名「NPC (x, y)」；沒有 NPC「地圖名(x, y)」
function Data.place(npc, mapName, x, y)
  local xy = string.format("(%.1f, %.1f)", x, y)
  if mapName then
    return (npc and (npc .. " · ") or "") .. mapName .. xy
  end
  return npc and (npc .. " " .. xy) or xy
end

-- 全部 questId（遞增）／entity 鍵（排序）。給測試與工具用，每次呼叫都會建新表
function Data.questIds()
  local ids = sortedKeys(Q)
  local qs = obsQuests()
  if not qs then return ids end
  local extra = false
  for id, o in pairs(qs) do
    if type(id) == "number" and not Q.idx[id] and type(o) == "table" and type(o.title) == "string" then
      ids[#ids + 1] = id; extra = true
    end
  end
  if extra then table.sort(ids) end
  return ids
end
function Data.entityKeys() return sortedKeys(E) end
