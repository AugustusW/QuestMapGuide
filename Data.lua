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

local Q, E, M, DS = EMPTY, EMPTY, EMPTY, EMPTY
local raw = QMG_Data
if type(raw) == "table" and raw.fmt == FORMAT then
  Q, E, M, DS = open(raw.q), open(raw.e), open(raw.m), open(raw.d)
end
QMG_Data = nil   -- 字串只留在上面四組；全域表與索引字串不必常駐

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

-- 任務：id 是數字。沒有就 nil
function Data.quest(id) return get(Q, id) end

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
function Data.entity(key) return get(E, key) end

-- 只查索引、不解碼：這個 entity 鍵在資料裡嗎
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
function Data.byMap(uiMapId)
  return get(M, uiMapId) or {}
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
function Data.questIds() return sortedKeys(Q) end
function Data.entityKeys() return sortedKeys(E) end
