-- 任務日誌獎勵（2026-11-27 實機：96988 在日誌裡有可選獎勵，資料與遊戲紀錄都沒有）：
-- 登入（PLAYER_ENTERING_WORLD）時讀日誌裡每個任務的獎勵物品，補進遊戲紀錄 obs.quests[q].rewards。
-- 永恆 1.60 沒有 SelectQuestLogEntry：用 C_QuestLog.SetSelectedQuest(questId) 選取，取完還原。
-- fixture：9900003 ri={}（資料沒有獎勵）、9900001 有資料獎勵 {12345, 12346}

local function setup(opts)
  opts = opts or {}
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function(v) return H.secret ~= nil and v == H.secret end; H.installed.issecretvalue = true
  _G.C_Item = { GetItemInfo = function() end }; H.installed.C_Item = true
  H.now = 1000
  _G.time = function() return H.now end; H.installed.time = true
  H.combat = false
  _G.InCombatLockdown = function() return H.combat end; H.installed.InCombatLockdown = true
  -- 日誌：questId → { c = {{id, n}}, r = {{id, n, noLink?, noInfoId?}} }
  H.LOG = opts.log or {}
  H.order = opts.order or {}
  H.sel = 4242
  H.selCalls = 0
  local function cur() return H.LOG[H.sel] end
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #H.order end,
    GetInfo = function(i) local q = H.order[i] return q and { questID = q, isHeader = false } or nil end,
    GetSelectedQuest = function() return H.sel end,
    SetSelectedQuest = function(q) H.sel = q; H.selCalls = H.selCalls + 1 end,
    GetQuestObjectives = function() return nil end,
  }
  H.installed.C_QuestLog = true
  local function list(kind) local c = cur() return c and c[kind == "choice" and "c" or "r"] or {} end
  local api = {
    GetNumQuestLogChoices = function() return #list("choice") end,
    GetNumQuestLogRewards = function() return #list("reward") end,
    GetQuestLogItemLink = function(kind, i)
      local it = list(kind)[i]
      if not it or it.noLink then return nil end
      return "|cff1eff00|Hitem:" .. it[1] .. "::::::::33:::::|h[x]|h|r"
    end,
    -- 遊戲回傳：name, texture, count, quality, isUsable, itemID
    GetQuestLogChoiceInfo = function(i) local it = list("choice")[i] return "x", 1, it and it[2], 2, true, it and not it.noInfoId and it[1] or nil end,
    GetQuestLogRewardInfo = function(i) local it = list("reward")[i] return "x", 1, it and it[2], 2, true, it and not it.noInfoId and it[1] or nil end,
  }
  for k, v in pairs(api) do _G[k] = v; H.installed[k] = true end
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  return ns
end

local function obsOf(q)
  local o = QuestMapGuideDB.obs and QuestMapGuideDB.obs.quests[q]
  return o and o.rewards
end

-- 1. 登入時讀日誌：資料沒有獎勵的任務補進遊戲紀錄，明細顯示並標遊戲紀錄
local ns = setup({ order = { 9900003, 9900001 },
  log = { [9900003] = { c = { { 21001, 1 }, { 21002, 1 } }, r = { { 21003, 5 } } },
          [9900001] = { c = { { 12346, 1 } }, r = { { 12345, 2 } } } } })
H.fire("PLAYER_ENTERING_WORLD")
local rw = obsOf(9900003)
H.check(rw ~= nil, "日誌任務的獎勵記進遊戲紀錄")
H.eq(rw.choices[21001], 1, "可選獎勵 1")
H.eq(rw.choices[21002], 1, "可選獎勵 2")
H.eq(rw.items[21003], 5, "固定獎勵與數量")
H.eq(H.sel, 4242, "讀完還原原本選取的任務")
local q = ns.Data.quest(9900003)
H.eq(#q.ri, 3, "資料沒有獎勵：明細用遊戲紀錄補")
H.check(q.obs and q.obs.ri, "補上的獎勵標遊戲紀錄")
local q1 = ns.Data.quest(9900001)
H.eq(q1.ri[1][1], 12345, "資料已有獎勵：照資料")
H.check(not (q1.obs and q1.obs.ri), "資料已有獎勵：不標遊戲紀錄")

-- 2. 同一次登入期間不重讀；任務說明視窗記到的獎勵不被日誌覆蓋
local calls = H.selCalls
H.fire("PLAYER_ENTERING_WORLD")
H.eq(H.selCalls, calls, "讀過的任務這次登入不再選取")
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = { { 21001, 1 } }, r = {} } } })
QuestMapGuideDB.obs = { v = 2, quests = { [9900003] = { first = 1, last = 1, rewards = { choices = { [30001] = 1 } } } } }
H.fire("PLAYER_ENTERING_WORLD")
H.eq(obsOf(9900003).choices[30001], 1, "任務說明視窗記的保留")
H.eq(obsOf(9900003).choices[21001], nil, "已有獎勵紀錄就不從日誌覆蓋")

-- 3. 固定獎勵連結拿不到（實機：霜喉雪人等），改用 GetQuestLogRewardInfo 第 6 個回傳的物品 ID；都拿不到就不記
ns = setup({ order = { 9900003 },
  log = { [9900003] = { c = {}, r = { { 6720, 1, noLink = true }, { 6721, 1, noLink = true, noInfoId = true } } } } })
H.fire("PLAYER_ENTERING_WORLD")
rw = obsOf(9900003)
H.eq(rw.items[6720], 1, "連結拿不到改用 RewardInfo 的物品 ID")
H.eq(rw.items[6721], nil, "兩種都拿不到就不記")
H.eq(rw.items[0], nil, "不記物品 0")

-- 4. 沒有物品獎勵的任務：不建紀錄
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = {}, r = {} } } })
H.fire("PLAYER_ENTERING_WORLD")
H.check(not (QuestMapGuideDB.obs and QuestMapGuideDB.obs.quests[9900003]), "沒有獎勵不建紀錄")

-- 5. 戰鬥中不讀，脫離戰鬥再讀
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = { { 21001, 1 } }, r = {} } } })
H.combat = true
H.fire("PLAYER_ENTERING_WORLD")
H.eq(H.selCalls, 0, "戰鬥中不選取任務")
H.combat = false
H.fire("PLAYER_REGEN_ENABLED")
H.eq(obsOf(9900003).choices[21001], 1, "脫離戰鬥後補讀")

-- 6. 保密的 questId 跳過；選取函式不存在就不讀
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = { { 21001, 1 } }, r = {} } } })
H.secret = 9900003
H.fire("PLAYER_ENTERING_WORLD")
H.eq(H.selCalls, 0, "保密 questId 不選取")
H.secret = nil
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = { { 21001, 1 } }, r = {} } } })
C_QuestLog.SetSelectedQuest = nil
H.fire("PLAYER_ENTERING_WORLD")
H.check(not (QuestMapGuideDB.obs and QuestMapGuideDB.obs.quests[9900003]), "沒有 SetSelectedQuest 不讀")
-- 審查 I2：拿不到原本選取的任務（nil／保密）就不選取，避免讀完停在別的任務
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = { { 21001, 1 } }, r = {} } } })
C_QuestLog.GetSelectedQuest = function() return nil end
H.fire("PLAYER_ENTERING_WORLD")
H.eq(H.selCalls, 0, "原選取拿不到就不選取")
H.checkPrinted("日誌獎勵")

-- 7. 實機（2026-11-28 存檔）：1136 在任務說明視窗時固定獎勵連結也拿不到，紀錄是 items={}（空表）。
-- 空表視同沒有：日誌讀到就補上
ns = setup({ order = { 9900003 }, log = { [9900003] = { c = {}, r = { { 6720, 1, noLink = true } } } } })
QuestMapGuideDB.obs = { v = 2, quests = { [9900003] = { first = 1, last = 1, rewards = { xp = 10, items = {}, choices = {} } } } }
H.fire("PLAYER_ENTERING_WORLD")
H.eq(obsOf(9900003).items[6720], 1, "空的獎勵紀錄由日誌補上")
H.eq(obsOf(9900003).xp, 10, "其他欄位保留")
