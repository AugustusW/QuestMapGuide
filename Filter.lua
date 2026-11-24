-- 篩選、等級顏色、前置／同組淡化。純讀取：不建 frame、不改任務資料。
--   ns.Filter.visible(questId, opts, quest) -> bool, reason   reason：nil | "class" | "faction" | "profession" | "low" | "holiday"
--   ns.Filter.holidayHidden(questId, quest, opts, status) -> bool  未接的節慶任務（h=1）且沒勾「顯示節慶任務」；暗月（h=2）永遠 false
--   ns.Filter.dim(questId)           -> nil | { kind = "prereq" | "group", name }
--   ns.Filter.color(questId)         -> r, g, b, low   low＝難度色是灰色（trivial）
--   ns.Filter.step(questId)          -> n, m | nil     同名線性連鎖的第幾步／共幾步
--   ns.Filter.profLow(questId)       -> bool            有該專業但點數不足
-- 每個函式的最後一個參數 quest 可傳已解碼的任務表（呼叫端已經解過就不必再解一次）。
-- 設定存角色存檔 QuestMapGuideCharDB.filter：exclClass／exclProf／exclFaction（勾＝排除，預設全勾）、showDone、showLow（顯示灰色低等任務，預設不勾）、showHoliday（顯示節慶任務，預設不勾）、tab。
-- 玩家資訊取不到（API 不存在或回傳不是預期型別）就不排除：寧可多列，不要誤藏。
-- 前置多個時用「全部完成」才不淡化（classic-db PrevQuestId／NextQuestId 規則尚未查證，spec 規定先照此處理）；
-- 前置任務不在內建資料裡就略過（沒有名稱可顯示，也無從判斷）。
local _, ns = ...

local Filter = {}
ns.Filter = Filter

local DEFAULTS = { exclClass = true, exclProf = true, exclFaction = true, showDone = false, showLow = false, showHoliday = false, tab = "open" }
local fallback = {}   -- 角色存檔還不存在時（理論上不會）暫存

local function store()
  local db = ns.Core and ns.Core.charDb and ns.Core.charDb()
  if not db then return fallback end
  if type(db.filter) ~= "table" then db.filter = {} end
  return db.filter
end

function Filter.get(key)
  local v = store()[key]
  if v == nil then return DEFAULTS[key] end
  return v
end

function Filter.set(key, value) store()[key] = value end

local function optOf(opts, key)
  if opts and opts[key] ~= nil then return opts[key] end
  return Filter.get(key)
end

-- 只有這些 skillLine 算專業／副專業（排除與「不足」標示只管它們；武器、騎術等其他技能 id 一律不排除）
local PROFESSIONS = {}
for _, id in ipairs({ 171, 164, 333, 202, 182, 165, 186, 197, 393, 185, 129, 356 }) do PROFESSIONS[id] = true end

-- 玩家資訊快照：Filter.reload() 重讀（Panel.Refresh 開頭呼叫）
local me = { level = nil, faction = nil, classId = nil, raceId = nil, skills = nil }
local levelHint   -- PLAYER_LEVEL_UP 事件帶的新等級；UnitLevel 在事件當下可能還是舊值

function Filter.levelUp(level)
  if type(level) == "number" then levelHint = level; Filter.reload() end
end

function Filter.reload()
  me = { skills = nil }
  if type(UnitLevel) == "function" then
    local lv = UnitLevel("player")
    if type(lv) == "number" then me.level = lv end
  end
  if levelHint then
    if me.level and me.level >= levelHint then levelHint = nil else me.level = levelHint end
  end
  if type(UnitRace) == "function" then
    local _, _, id = UnitRace("player")
    if type(id) == "number" then me.raceId = id end
  end
  if type(UnitFactionGroup) == "function" then
    local f = UnitFactionGroup("player")
    if f == "Alliance" then me.faction = "A" elseif f == "Horde" then me.faction = "H" end
  end
  if type(UnitClass) == "function" then
    local _, _, id = UnitClass("player")
    if type(id) == "number" then me.classId = id end
  end
  -- 專業：skillLine 是 GetProfessionInfo 的第 7 個回傳值（retail 簽章；Forever 版只驗證過函式存在）。
  -- 任何一個專業取不到數字型 skillLine 就整組當未知，不排除也不標不足。
  if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
    local skills, known = {}, true
    local n = select("#", GetProfessions())
    local slots = { GetProfessions() }
    for i = 1, n do
      local idx = slots[i]
      if idx then
        local _, _, rank, _, _, _, line = GetProfessionInfo(idx)
        if type(line) == "number" then skills[line] = type(rank) == "number" and rank or 0 else known = false end
      end
    end
    if known then me.skills = skills end
  end
end
Filter.reload()

local function has(list, v)
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

-- 節慶任務（資料 h=1）預設隱藏，但跟低等任務一樣只藏「未接」的：日誌裡的任務不能從面板消失，已完成的也照常列。
-- 暗月馬戲團（h=2）只標示、不隱藏。地圖標記不看這個（明確打開的任務一律標記）
function Filter.holidayHidden(questId, q, opts, status)
  if type(q) ~= "table" or q.h ~= 1 or optOf(opts, "showHoliday") then return false end
  return (status or ns.Status.of(questId)) == "open"
end

function Filter.visible(questId, opts, quest, status)
  local q = quest or ns.Data.quest(questId)
  if not q then return true end
  if Filter.holidayHidden(questId, q, opts, status) then return false, "holiday" end
  if optOf(opts, "exclFaction") then
    if me.faction and q.f and q.f ~= me.faction then return false, "faction" end
    -- 種族限制：race 非空且玩家種族已知才排除（空表＝不限，缺＝未知）
    if me.raceId and type(q.race) == "table" and #q.race > 0 and not has(q.race, me.raceId) then return false, "faction" end
  end
  if optOf(opts, "exclClass") and me.classId and type(q.cls) == "table" and #q.cls > 0 and not has(q.cls, me.classId) then
    return false, "class"
  end
  if optOf(opts, "exclProf") and me.skills and type(q.sk) == "table" and PROFESSIONS[q.sk[1]] and me.skills[q.sk[1]] == nil then
    return false, "profession"
  end
  -- 低等任務只藏「未接」的：進行中與已完成的灰色任務照常列出
  if not optOf(opts, "showLow") then
    local _, _, _, low = Filter.color(questId, q)
    if low and (status or ns.Status.of(questId)) == "open" then return false, "low" end
  end
  return true
end

-- 有該專業但點數低於需求（需求點數未知就不算）
function Filter.profLow(questId, quest)
  local q = quest or ns.Data.quest(questId)
  if not q or not me.skills or type(q.sk) ~= "table" or not PROFESSIONS[q.sk[1]] or not q.sk[2] then return false end
  local rank = me.skills[q.sk[1]]
  return rank ~= nil and rank < q.sk[2]
end

function Filter.name(n)
  if not n then return "" end
  if GetLocale() == "zhTW" then return n.zh or n.en or "" end
  return n.en or n.zh or ""
end

-- 任務類型標示：名稱後加「 (類型)」；只標已知類型，其他值或 nil 不標。只用於顯示，排序與搜尋用不含類型的名稱。
local TYPE_KEY = { [1] = "qType1", [81] = "qType81", [62] = "qType62", [41] = "qType41", [83] = "qType83" }
-- 節慶標示（資料 h）：接在類型標示後面
local HOLIDAY_KEY = { [1] = "qHoliday", [2] = "qDarkmoon" }
-- 同名連鎖步驟：沿 prev／next 走出線性鏈（每一步前後最多各一個、都在資料裡），鏈中任務同名才有。
-- 結果整條鏈一次算好、存在 session 內（資料不變）；Panel.InvalidateIndex 學到新名稱時一併清掉。
local stepCache = {}
-- 連結取兩邊宣告的聯集：A→B 成立＝A.next 有 B，或 B.prev 有 A（真實資料有單邊宣告）。
-- 反向索引第一次用到時掃一次全部任務建好（整個 session 保留，ResetSteps 清掉）。
local revPrev, revNext   -- revPrev[x] = 宣告 prev 含 x 的任務（x 的後繼）；revNext[x] = 宣告 next 含 x 的任務（x 的前驅）
local function reverseIndex()
  if revPrev then return end
  revPrev, revNext = {}, {}
  for _, id in ipairs(ns.Data.questIds()) do
    local q = ns.Data.quest(id)
    if q then
      if type(q.prev) == "table" then
        for _, p in ipairs(q.prev) do
          local t = revPrev[p]; if not t then t = {}; revPrev[p] = t end
          t[#t + 1] = id
        end
      end
      if type(q.next) == "table" then
        for _, n in ipairs(q.next) do
          local t = revNext[n]; if not t then t = {}; revNext[n] = t end
          t[#t + 1] = id
        end
      end
    end
  end
end
function Filter.ResetSteps() stepCache = {}; revPrev, revNext = nil, nil end

-- 一個任務在聯集圖裡的前驅或後繼，只算同名的（不同名的鄰居是鏈的邊界，不算）；
-- 鄰居不在資料裡就無從判斷，整條不算。回傳 唯一的 id（沒有回 false）、是否線性（至多一個）
local function links(name, id, own, rev)
  local set, n, one = {}, 0, false
  local function add(x)
    if set[x] then return true end
    set[x] = true
    local r = ns.Data.quest(x)
    if not r then return false end
    if Filter.name(r.n) == name then n = n + 1; one = x end
    return true
  end
  for _, x in ipairs(type(own) == "table" and own or {}) do if not add(x) then return false, false end end
  for _, x in ipairs(rev[id] or {}) do if not add(x) then return false, false end end
  if n == 0 then return false, true end
  if n == 1 then return one, true end
  return false, false
end

local function walk(questId)
  reverseIndex()
  local q = ns.Data.quest(questId)
  if not q then return nil end
  local name = Filter.name(q.n)
  local seen = { [questId] = true }
  local chain = { questId }
  local function pred(id, rec) return links(name, id, rec.prev, revNext) end
  local function succ(id, rec) return links(name, id, rec.next, revPrev) end
  local cur, cq = questId, q
  while true do   -- 往前
    local p, ok = pred(cur, cq)
    if not ok then return nil end
    if not p then break end
    local pq = ns.Data.quest(p)
    if seen[p] then return nil end
    local ps, pok = succ(p, pq)
    if not pok or ps ~= cur then return nil end
    seen[p] = true
    table.insert(chain, 1, p)
    cur, cq = p, pq
  end
  cur, cq = questId, q
  while true do   -- 往後
    local nx, ok = succ(cur, cq)
    if not ok then return nil end
    if not nx then break end
    local nq = ns.Data.quest(nx)
    if seen[nx] then return nil end
    local np, pok = pred(nx, nq)
    if not pok or np ~= cur then return nil end
    seen[nx] = true
    chain[#chain + 1] = nx
    cur, cq = nx, nq
  end
  if #chain < 2 then return nil end
  return chain
end

function Filter.step(questId)
  local c = stepCache[questId]
  if c == nil then
    local chain = walk(questId)
    if chain then
      for i, id in ipairs(chain) do stepCache[id] = { i, #chain } end
      c = stepCache[questId]
    else
      c = false
      stepCache[questId] = false
    end
  end
  if c then return c[1], c[2] end
  return nil
end

-- 名稱後附步驟「 (n/m)」（沒有就原樣）
function Filter.withStep(name, questId)
  local n, m = Filter.step(questId)
  if n then return name .. " (" .. n .. "/" .. m .. ")" end
  return name
end

-- 顯示用標題：名稱 (步驟) (類型) (節慶／暗月)。排序與搜尋用不含步驟與標示的名稱。
function Filter.titled(name, typeId, questId, h)
  if questId then name = Filter.withStep(name, questId) end
  local key = type(typeId) == "number" and TYPE_KEY[typeId]
  if key then name = name .. " (" .. ns.L(key) .. ")" end
  local hk = type(h) == "number" and HOLIDAY_KEY[h]
  if hk then name = name .. " (" .. ns.L(hk) .. ")" end
  return name
end

-- 淡化只對「可接」的任務；進行中與已完成不淡化
function Filter.dim(questId, quest, status)
  if (status or ns.Status.of(questId)) ~= "open" then return nil end
  local q = quest or ns.Data.quest(questId)
  if not q then return nil end
  if type(q.excl) == "table" then
    for _, id in ipairs(q.excl) do
      local o = ns.Data.quest(id)
      if o and ns.Status.of(id) == "done" then return { kind = "group", name = Filter.name(o.n) } end
    end
  end
  if type(q.prev) == "table" then
    for _, id in ipairs(q.prev) do
      local p = ns.Data.quest(id)
      if p and ns.Status.of(id) ~= "done" then return { kind = "prereq", name = Filter.name(p.n) } end
    end
  end
  return nil
end

-- 難度色：玩家等級低於可接等級（min）紅色；否則 GetQuestDifficultyColor(questLevel)；API 缺就用經典規則
local RED_R, RED_G, RED_B = 1, 0.1, 0.1
local function classic(level, lv)
  local d = lv - level
  if d >= 5 then return 1, 0.1, 0.1 end
  if d >= 3 then return 1, 0.5, 0.25 end
  if d >= -2 then return 1, 1, 0 end
  if -d <= 8 then return 0.25, 0.75, 0.25 end   -- 灰色門檻簡化：低 9 級以上灰
  return 0.5, 0.5, 0.5
end

function Filter.color(questId, quest)
  local q = quest or ns.Data.quest(questId)
  if not q then return 1, 1, 1, false end
  if me.level and q.min and me.level < q.min then return RED_R, RED_G, RED_B, false end
  if q.lv and q.lv > 0 then
    if type(GetQuestDifficultyColor) == "function" then
      local c = GetQuestDifficultyColor(q.lv)
      if type(c) == "table" and c.r then
        -- 灰色（trivial）：三色相等且約 0.5
        local low = math.abs(c.r - 0.5) < 0.02 and math.abs(c.g - 0.5) < 0.02 and math.abs(c.b - 0.5) < 0.02
        return c.r, c.g, c.b, low
      end
    end
    if me.level then
      local r, g, b = classic(me.level, q.lv)
      return r, g, b, r == 0.5 and g == 0.5
    end
  end
  return 1, 1, 1, false
end
