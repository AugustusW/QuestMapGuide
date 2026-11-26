-- 遊戲內任務觀察：每個任務一份彙整，寫進 QuestMapGuideDB.obs（帳號共用）。Data.lua 讀它補內建缺的欄位（明細標「遊戲紀錄」）。
-- 格式 v1（正式版會沿用並匯入 AgentSpace）：
--   obs = { v = 1, quests = { [questId] = {
--     title, objective, first, last,                         -- 時間是 time()
--     starts = { [key] = { kind, id, name, map, x, y, n, last } },   -- key＝"c2986"／"o123"；QUEST_DETAIL 時的 NPC 與玩家位置
--     ends   = { [key] = { ... 同上 } },                        -- QUEST_COMPLETE（交任務獎勵畫面）時
--     rewards = { xp, xpLevel, money, items = { [itemId] = count }, choices = { [itemId] = count } },
--     nexts  = { [questId] = n },                               -- 交完本任務後數秒內，同一 NPC 打開的任務說明
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
  db.obs = db.obs or { v = 1, quests = {} }
  db.obs.quests = db.obs.quests or {}
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
        local id = itemId(kind, i)
        if id then
          local _, _, count = call(GetQuestItemInfo, kind, i)
          t[id] = num(count) or 1
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

ns.Core.slash.obs = function()
  local qs = store()
  local n = 0
  if qs then for _ in pairs(qs) do n = n + 1 end end
  print("|cff33ff99QMG|r 已記錄 " .. n .. " 個任務的遊戲觀察")
end
