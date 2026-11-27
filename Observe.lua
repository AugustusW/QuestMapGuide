-- 遊戲內任務觀察：每個任務一份彙整，寫進 QuestMapGuideDB.obs（帳號共用）。Data.lua 讀它補內建缺的欄位（明細標「遊戲紀錄」）。
-- 格式 v2（V298；v1 存檔載入時就地升級，資料不變）：
--   obs = { v = 2, quests = { [questId] = {
--     title, objective, first, last,                         -- 時間是 time()
--     starts = { [key] = { kind, id, name, map, x, y, n, last } },   -- key＝"c2986"／"o123"；QUEST_DETAIL 時的 NPC 與玩家位置
--     ends   = { [key] = { ... 同上 } },                        -- QUEST_COMPLETE（交任務獎勵畫面）時
--     rewards = { xp, xpLevel, money, items = { [itemId] = count }, choices = { [itemId] = count } },   -- 任務視窗記；沒有時登入從任務日誌補物品
--     nexts  = { [questId] = n },                               -- 交完本任務後數秒內，同一 NPC 打開的任務說明
--     dungeons = { [instanceID] = n },                          -- v2：人在副本裡時這個任務的目標推進了（instanceID＝GetInstanceInfo 第 8 個回傳值）
--   } } }
-- 所有遊戲值先確認不是保密值（Core.secret）才比較或存。
local _, ns = ...

local Observe = {}
ns.Observe = Observe

local NEXT_WINDOW = 5   -- 交任務後幾秒內同一 NPC 打開的說明算「後續」

local function ok(x) return x ~= nil and not ns.Core.secret(x) end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return select(2, unpack(r))
end

local function num(x) if ok(x) and type(x) == "number" then return x end end
local function str(x) if ok(x) and type(x) == "string" and x ~= "" then return x end end

local function round(x) return math.floor(x * 10000 + 0.5) / 10000 end

-- 對話中的 NPC／物件：{kind="c"|"o", id, name}；不是生物或物件（例如物品開的任務）回 nil
local function talker()
  for _, unit in ipairs({ "questnpc", "npc" }) do
    local g = str(call(UnitGUID, unit))
    if g then
      local kind, id = g:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
      local k = (kind == "Creature" or kind == "Vehicle") and "c" or (kind == "GameObject" and "o") or nil
      if k and tonumber(id) then
        return { kind = k, id = tonumber(id), name = str(call(UnitName, unit)) }
      end
    end
  end
end

local function where()
  if type(C_Map) ~= "table" then return nil end
  local map = num(call(C_Map.GetBestMapForUnit, "player"))
  if not map then return nil end
  local pos = call(C_Map.GetPlayerMapPosition, map, "player")
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return map end
  local okXY, x, y = pcall(pos.GetXY, pos)
  if not okXY or not num(x) or not num(y) then return map end
  return map, round(x), round(y)
end

local function store()
  local db = ns.Core.db()
  if type(db) ~= "table" then return nil end
  db.obs = db.obs or { v = 2, quests = {} }
  db.obs.quests = db.obs.quests or {}
  if db.obs.v == 1 then db.obs.v = 2 end   -- v2 只多了 dungeons，舊資料原樣保留
  return db.obs.quests
end

local function questRec(qid)
  local qs = store()
  if not qs then return nil end
  local now = time()
  local q = qs[qid]
  if type(q) ~= "table" then
    q = { first = now }
    qs[qid] = q
  end
  q.last = now
  return q
end

local function place(list, who)
  local key = who.kind .. who.id
  local map, x, y = where()
  local r = list[key]
  if type(r) ~= "table" then
    r = { kind = who.kind, id = who.id, n = 0 }
    list[key] = r
  end
  r.name = who.name or r.name
  -- 位置只在第一次（或之前沒有位置）時記：之後同一 NPC 的位置不覆蓋，避免邊走邊點造成漂移
  if map and not r.map then r.map, r.x, r.y = map, x, y end
  r.n = (r.n or 0) + 1
  r.last = time()
end

local function itemId(kind, i)
  local link = str(call(GetQuestItemLink, kind, i))
  return link and tonumber(link:match("item:(%d+)"))
end

local function rewards(q)
  local r = q.rewards or {}
  q.rewards = r
  local xp = num(call(GetRewardXP))
  if xp then r.xp, r.xpLevel = xp, num(call(UnitLevel, "player")) end
  local money = num(call(GetRewardMoney))
  if money then r.money = money end
  for kind, field in pairs({ reward = { "items", GetNumQuestRewards }, choice = { "choices", GetNumQuestChoices } }) do
    local n = num(call(field[2]))
    if n then
      local t = {}
      for i = 1, math.min(n, 10) do
        local r = { pcall(GetQuestItemInfo or error, kind, i) }
        -- 連結拿不到（實機：固定獎勵）改用第 6 個回傳的 itemID（pcall 旗標佔 r[1]，所以在 r[7]）
        local id = itemId(kind, i) or (r[1] and num(r[7])) or nil
        if id and id > 0 then
          t[id] = (r[1] and num(r[4])) or 1
        end
      end
      r[field[1]] = t
    end
  end
end

local lastTurnIn  -- { qid, key, t }：最近一次交任務

-- 紀錄變了：面板的搜尋索引與地圖清單要重建（同 Learn.lua 學到新名稱）
local function changed()
  if ns.Panel and ns.Panel.InvalidateIndex then ns.Panel.InvalidateIndex() end
end

ns.Core.on("QUEST_DETAIL", function()
  local qid = num(call(GetQuestID))
  if not qid or qid == 0 then return end
  local q = questRec(qid)
  if not q then return end
  q.title = str(call(GetTitleText)) or q.title
  q.objective = str(call(GetObjectiveText)) or q.objective
  local who = talker()
  if who then
    q.starts = q.starts or {}
    place(q.starts, who)
    local lt = lastTurnIn
    if lt and lt.qid ~= qid and lt.key == who.kind .. who.id and time() - lt.t <= NEXT_WINDOW then
      local prev = questRec(lt.qid)
      prev.nexts = prev.nexts or {}
      prev.nexts[qid] = (prev.nexts[qid] or 0) + 1
    end
  end
  rewards(q)
  changed()
end)

ns.Core.on("QUEST_COMPLETE", function()
  local qid = num(call(GetQuestID))
  if not qid or qid == 0 then return end
  local q = questRec(qid)
  if not q then return end
  q.title = str(call(GetTitleText)) or q.title
  local who = talker()
  if who then
    q.ends = q.ends or {}
    place(q.ends, who)
  end
  rewards(q)
  changed()
end)

ns.Core.on("QUEST_TURNED_IN", function(qid)
  qid = num(qid)
  if not qid then return end
  local who = talker()
  lastTurnIn = { qid = qid, key = who and (who.kind .. who.id), t = time() }
end)

-- ── V298：任務目標在副本裡推進 → 記下副本 ─────────────────────────────────────
-- 只在人在副本裡時掃：每次任務日誌更新算一次各任務已完成的目標數，跟上一次比，數字變大就記這個副本。
-- 進副本後第一次看到的任務只建基準不算推進（進副本前的進度、剛接的任務）。不在副本裡不掃日誌（Status.lua 已有合併重掃，這裡不重複），基準清空。
local progress = {}
local lastScan = nil

local function instanceId()
  local inside = call(IsInInstance)
  if not ok(inside) or inside ~= true then return nil end   -- 先判保密再比較
  local r = { pcall(GetInstanceInfo) }
  if not r[1] then return nil end
  local id = num(r[9])   -- pcall 的第一個值是成功旗標，所以 instanceID（第 8 個回傳值）在 r[9]
  -- 只記資料裡有的副本（戰場等其他 instance 不記，存檔保持乾淨；審查 2026-11-28）
  if not id or id <= 0 or not (ns.Data and ns.Data.dungeon and ns.Data.dungeon(id)) then return nil end
  return id
end

local function fulfilled(qid)
  local objs = type(C_QuestLog) == "table" and call(C_QuestLog.GetQuestObjectives, qid)
  if type(objs) ~= "table" then return nil end
  local total = 0
  for _, o in ipairs(objs) do
    local n = type(o) == "table" and num(o.numFulfilled)
    if n then total = total + n end
  end
  return total
end

local function scanLog()
  if type(C_QuestLog) ~= "table" then return end
  local inst = instanceId()
  if not inst then progress = {}; return end
  local now = time()
  if lastScan == now then return end   -- 同一秒只算一次（QUEST_LOG_UPDATE 很頻繁）
  lastScan = now
  local n = num(call(C_QuestLog.GetNumQuestLogEntries)) or 0
  local seen = {}
  for i = 1, math.min(n, 100) do
    local info = call(C_QuestLog.GetInfo, i)
    local qid = type(info) == "table" and not info.isHeader and num(info.questID)
    if qid and qid > 0 then
      seen[qid] = true
      local cur = fulfilled(qid)
      local prev = progress[qid]
      if cur and prev and cur > prev then
        local q = questRec(qid)
        if q then
          q.dungeons = q.dungeons or {}
          q.dungeons[inst] = (q.dungeons[inst] or 0) + 1
          changed()
        end
      end
      if cur then progress[qid] = cur end
    end
  end
  for qid in pairs(progress) do if not seen[qid] then progress[qid] = nil end end
end

ns.Core.on("QUEST_LOG_UPDATE", scanLog)
ns.Core.on("UNIT_QUEST_LOG_CHANGED", function(unit) if unit == "player" then scanLog() end end)

-- ── 任務日誌獎勵（2026-11-27）：接任務時沒記到獎勵的任務（例：紀錄功能上線前接的），登入時從日誌補 ─────────
-- 永恆 1.60 沒有 SelectQuestLogEntry：用 C_QuestLog.SetSelectedQuest(questId) 選取，讀完還原原選取。
-- 只補還沒有物品獎勵紀錄的任務（任務說明視窗記的優先）；沒有物品獎勵不建紀錄。戰鬥中不讀，脫離戰鬥再讀。
-- 物品 ID 先取 GetQuestLogItemLink，拿不到改用 Get…Info 第 6 個回傳值（實機：固定獎勵的連結拿不到）；都拿不到就不記。
local logRead = {}       -- 這次登入讀過的任務
local logPending = false

local function logItems(kind, n, infoFn, qid)
  local t, any = {}, false
  for i = 1, math.min(n, 10) do
    local link = str(call(GetQuestLogItemLink, kind, i))
    local id = link and tonumber(link:match("item:(%d+)"))
    local r = { pcall(infoFn or error, i, qid) }
    if not id and r[1] then id = num(r[7]) end   -- pcall 旗標佔 r[1]，itemID（第 6 個回傳值）在 r[7]
    if id and id > 0 then
      t[id] = (r[1] and num(r[4])) or 1
      any = true
    end
  end
  return any and t or nil
end

local function scanLogRewards()
  local ql = C_QuestLog
  if type(ql) ~= "table" or type(ql.SetSelectedQuest) ~= "function" or type(ql.GetSelectedQuest) ~= "function"
      or type(ql.GetInfo) ~= "function" then return end
  if type(GetNumQuestLogChoices) ~= "function" or type(GetNumQuestLogRewards) ~= "function"
      or type(GetQuestLogItemLink) ~= "function" then return end
  if type(InCombatLockdown) == "function" and InCombatLockdown() then logPending = true; return end
  logPending = false
  local n = num(call(ql.GetNumQuestLogEntries)) or 0
  local orig = num(call(ql.GetSelectedQuest))
  if not orig then return end   -- 拿不到原選取（nil／保密）就不選取，避免讀完停在別的任務（審查 2026-11-28）
  local any, moved = false, false
  for i = 1, math.min(n, 100) do
    local info = call(ql.GetInfo, i)
    local qid = type(info) == "table" and info.isHeader ~= true and num(info.questID)
    if qid and qid > 0 and not logRead[qid] then
      logRead[qid] = true
      local qs = store()
      local o = qs and qs[qid]
      local have = type(o) == "table" and type(o.rewards) == "table"
        and (next(o.rewards.items or {}) or next(o.rewards.choices or {}))
      if qs and not have then
        moved = true
        local okSel = pcall(ql.SetSelectedQuest, qid)
        if okSel then
          local items = logItems("reward", num(call(GetNumQuestLogRewards, qid)) or 0, GetQuestLogRewardInfo, qid)
          local choices = logItems("choice", num(call(GetNumQuestLogChoices, qid)) or 0, GetQuestLogChoiceInfo, qid)
          if items or choices then
            local q = questRec(qid)
            q.rewards = q.rewards or {}
            -- 空表視同沒有（實機：任務說明視窗拿不到固定獎勵連結時記成 items={}）
            if items and not next(q.rewards.items or {}) then q.rewards.items = items end
            if choices and not next(q.rewards.choices or {}) then q.rewards.choices = choices end
            any = true
          end
        end
      end
    end
  end
  if moved then pcall(ql.SetSelectedQuest, orig) end
  if any then changed() end
end
Observe.scanLogRewards = scanLogRewards

ns.Core.on("PLAYER_ENTERING_WORLD", scanLogRewards)
ns.Core.on("PLAYER_REGEN_ENABLED", function() if logPending then scanLogRewards() end end)

ns.Core.slash.obs = function()
  local qs = store()
  local n = 0
  if qs then for _ in pairs(qs) do n = n + 1 end end
  print("|cff33ff99QMG|r 已記錄 " .. n .. " 個任務的遊戲觀察")
end
