-- 任務狀態（done / log / open）與面板整合。資料用 fixture。
-- 假的 C_QuestLog：completed 是已完成集合、log 是任務日誌（含標題列）；C_Timer.After 手動推進。
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 日誌 questId 要過保密檢查（fail-closed）
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local S = { completed = opts.completed or {}, log = opts.log or {}, timers = {}, calls = { all = 0, flagged = 0 } }
  local ql = {
    IsQuestFlaggedCompleted = function(id) S.calls.flagged = S.calls.flagged + 1; return S.completed[id] == true end,
    GetNumQuestLogEntries = function()
      local n = 0
      for _, e in ipairs(S.log) do if e.questID and not e.isHeader then n = n + 1 end end
      return #S.log, n
    end,
    GetInfo = function(i) S.calls.info = (S.calls.info or 0) + 1; return S.log[i] end,
  }
  S.onQuest = {}
  if opts.isOnQuest then ql.IsOnQuest = function(id) return S.onQuest[id] == true end end
  if not opts.noGetAll then
    ql.GetAllCompletedQuestIDs = function()
      S.calls.all = S.calls.all + 1
      local t = {}
      for id in pairs(S.completed) do t[#t + 1] = id end
      return t
    end
  end
  _G.C_QuestLog = ql; H.installed.C_QuestLog = true
  _G.C_Timer = { After = function(d, fn) S.timers[#S.timers + 1] = { d = d, fn = fn } end }; H.installed.C_Timer = true
  function S.flush() local t = S.timers; S.timers = {}; for _, x in ipairs(t) do x.fn() end end
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm:Show(); S.wm = wm
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  if not opts.noLogin then H.fire("PLAYER_LOGIN") end
  return ns, S
end
local function ids(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.questId end return t end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local ns, S = setup()
H.eq(type(ns.Status), "table", "ns.Status 存在")
H.eq(ns.Status.of(9900001), "open", "沒接沒完成是 open")

-- 登入時一次取已完成集合；之後 of() 不再逐筆呼叫 API
ns, S = setup({ completed = { [9900002] = true } })
H.eq(ns.Status.of(9900002), "done", "登入時已完成的任務是 done")
H.check(S.calls.all >= 1, "登入時呼叫 GetAllCompletedQuestIDs")
S.calls.flagged = 0
ns.Status.of(9900002)
H.eq(S.calls.flagged, 0, "集合已有的 id 不再逐筆查")

-- 沒有 GetAllCompletedQuestIDs 時退回逐筆查
ns, S = setup({ noGetAll = true, completed = { [9900002] = true } })
H.eq(ns.Status.of(9900002), "done", "沒有批次 API 時退回 IsQuestFlaggedCompleted")
H.eq(ns.Status.of(9900001), "open", "沒有批次 API 時未完成是 open")

-- 登入前（集合未建立）也不爆：退回逐筆查
ns, S = setup({ noLogin = true, completed = { [9900002] = true } })
H.eq(ns.Status.of(9900002), "done", "登入事件前退回逐筆查")

-- 登入時清單是空的、之後 IsQuestFlaggedCompleted 為 true → done（of() 補一道）
ns, S = setup()
S.completed = {}
H.eq(ns.Status.of(9900001), "open", "尚未完成")
S.completed[9900001] = true
H.eq(ns.Status.of(9900001), "done", "集合沒有但 IsQuestFlaggedCompleted 為 true → done")
-- 之後的重掃把新完成的併入集合（不必再逐筆查）
S.completed[9900002] = true
H.fire("PLAYER_ENTERING_WORLD")
S.calls.flagged = 0
H.eq(ns.Status.of(9900002), "done", "重掃後 done")
H.eq(S.calls.flagged, 0, "重掃後已併入集合")
-- PLAYER_ENTERING_WORLD 也重掃
S.completed[9900003] = true
H.fire("PLAYER_ENTERING_WORLD")
S.calls.flagged = 0
ns.Status.of(9900003)
H.eq(S.calls.flagged, 0, "PLAYER_ENTERING_WORLD 重建了集合")
H.eq(ns.Status.of(9900003), "done", "PLAYER_ENTERING_WORLD 後該任務是 done")
-- 重掃是整組取代：API 不再列出（每日任務重置）就清掉
S.completed = {}
_G.C_QuestLog.IsQuestFlaggedCompleted = function() return false end
H.fire("PLAYER_ENTERING_WORLD")
H.eq(ns.Status.of(9900003), "open", "重置後不再列為完成（取代而非併入）")
H.eq(ns.Status.of(9900002), "open", "舊的完成也隨之清掉")
-- 沒有 IsQuestFlaggedCompleted 也不爆
_G.C_QuestLog.IsQuestFlaggedCompleted = nil
H.eq(ns.Status.of(9900004), "open", "沒有 IsQuestFlaggedCompleted 不報錯")

-- IsOnQuest 存在：直接問它，不需要掃日誌（收合標題下的任務 GetInfo 不回）
ns, S = setup({ isOnQuest = true })
S.log = { { questID = 9900001 } }   -- 日誌裡有一筆：若實作誤掃 GetInfo，下面的計數就會 > 0
S.onQuest[9900002] = true      -- 日誌掃描看不到 9900002，但 IsOnQuest 說在
S.calls.info = 0
H.fire("QUEST_ACCEPTED", 1, 9900002)
H.eq(ns.Status.of(9900002), "log", "IsOnQuest 為 true → log")
H.eq(S.calls.info, 0, "有 IsOnQuest 時不掃 GetInfo")
H.eq(ns.Status.of(9900001), "open", "IsOnQuest 為 false → open")
S.onQuest[9900002] = nil
H.eq(ns.Status.of(9900002), "open", "IsOnQuest 回 false 後 open")
-- IsOnQuest 缺：用掃描
ns, S = setup()
S.log = { { questID = 9900002 } }
H.fire("QUEST_ACCEPTED", 1, 9900002)
H.eq(ns.Status.of(9900002), "log", "沒有 IsOnQuest 時用日誌掃描")
H.check((S.calls.info or 0) > 0, "有掃 GetInfo")
-- 有 IsOnQuest 時 QUEST_LOG_UPDATE 仍會因任務數改變而更新面板
ns, S = setup({ isOnQuest = true })
S.wm:Show(); ns.Panel.frame:Show(); ns.Panel.Refresh(1453)
local nref = 0
local realRef = ns.Panel.Refresh
ns.Panel.Refresh = function(...) nref = nref + 1; return realRef(...) end
S.log = { { questID = 9900001 } }; S.onQuest[9900001] = true
H.fire("QUEST_LOG_UPDATE"); S.flush()
H.eq(nref, 1, "任務數變了就重畫（IsOnQuest 路徑）")
H.eq(ns.Panel.Counts().log, 1, "IsOnQuest 路徑的面板 log 計數")

-- 立即重掃取代排好的延後重掃（不重複掃）
ns, S = setup()
H.fire("QUEST_LOG_UPDATE")
local pendingTimers = #S.timers
local c0 = S.calls.info or 0
S.log = { { questID = 9900001 } }
H.fire("QUEST_ACCEPTED", 1, 9900001)
local c1 = S.calls.info or 0
S.flush()
H.eq(pendingTimers, 1, "排了一個計時器")
H.eq(S.calls.info or 0, c1, "立即重掃後，舊計時器到點不再重掃")
H.eq(c1, c0 + 1, "立即重掃只掃一次")

-- 接任務：QUEST_ACCEPTED 後是 log，面板的 log 計數 +1，仍列在面板
ns, S = setup()
ns.Panel.frame:Show()
ns.Filter.set("tab", "all")   -- 預設分頁是未接；這一段要看進行中的任務也列在清單，用全部分頁
ns.Panel.Refresh(1453)
H.eq(ns.Panel.Counts().log, 0, "開始時 log 計數 0")
H.eq(ns.Panel.Counts().open, 1, "開始時 open 計數 1（9900002 的前置未完成，淡化不算可接）")
H.eq(ns.Panel.Counts().openAll, 2, "未接分頁數字含淡化的")
S.log = { { isHeader = true, title = "標題", questID = 0 }, { questID = 9900002, isHeader = false, title = "x" } }
H.fire("QUEST_ACCEPTED", 1, 9900002)
H.eq(ns.Status.of(9900002), "log", "接任務後 of == log")
H.eq(ns.Status.of(9900001), "open", "標題列不污染：其他任務仍 open")
H.eq(ns.Panel.Counts().log, 1, "面板 log 計數 +1")
H.eq(ns.Panel.Counts().open, 1, "面板 open 計數：剩 9900001")
H.eq(ns.Panel.Counts().openAll, 1, "未接分頁數字 -1")
H.check(same(ids(ns.Panel.Rows()), { 9900001, 9900002 }), "log 的任務仍列在面板")
local row2 = ns.Panel.Rows()[2]
H.eq(row2.status, "log", "列帶 status")

-- 放棄任務：QUEST_REMOVED 後回到 open
S.log = {}
H.fire("QUEST_REMOVED", 9900002)
H.eq(ns.Status.of(9900002), "open", "放棄後回 open")
H.eq(ns.Panel.Counts().log, 0, "面板 log 計數回 0")

-- 交任務：QUEST_TURNED_IN 後 done；完成的任務預設不在面板清單（也不在 open 計數）
S.log = { { questID = 9900002, isHeader = false } }
H.fire("QUEST_ACCEPTED", 1, 9900002)
S.log = {}; S.completed[9900002] = true
H.fire("QUEST_TURNED_IN", 9900002)
H.eq(ns.Status.of(9900002), "done", "交任務後 done")
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "完成的任務預設不列在面板")
H.eq(ns.Panel.Counts().done, 1, "done 計數 1")
H.eq(ns.Panel.Counts().open, 1, "open 計數 1")
-- 交任務事件本身就能標 done，不必等日誌或批次 API
S.completed = { [9900002] = true }   -- 9900002 仍完成（重掃是取代，不再靠舊集合）；9900001 只靠 TURNED_IN 事件
ns.Status.of(9900001)
H.fire("QUEST_TURNED_IN", 9900001)
H.eq(ns.Status.of(9900001), "done", "QUEST_TURNED_IN 直接把該任務標為 done")
H.eq(#ns.Panel.Rows(), 0, "兩筆都完成：面板清單空")
ns.Panel.SetTab("open")
H.eq(ns.Panel.Message(), "這張地圖沒有未完成的任務", "全部完成時（未接分頁）的空狀態文字")

-- QUEST_LOG_UPDATE：合併（0.5 秒內只重掃一次），面板顯示時才更新
ns, S = setup()
ns.Panel.frame:Show()
ns.Panel.Refresh(1453)
local scans = 0
local realNum = _G.C_QuestLog.GetNumQuestLogEntries
_G.C_QuestLog.GetNumQuestLogEntries = function() scans = scans + 1; return realNum() end
for _ = 1, 50 do H.fire("QUEST_LOG_UPDATE") end
H.eq(#S.timers, 1, "50 次 QUEST_LOG_UPDATE 只排一個計時器")
H.eq(S.timers[1].d, 0.5, "計時 0.5 秒")
H.eq(scans, 0, "計時結束前不重掃")
S.flush()
H.eq(scans, 1, "計時結束後重掃一次")
S.log = { { questID = 9900001 } }
H.fire("QUEST_LOG_UPDATE"); S.flush()
H.eq(ns.Status.of(9900001), "log", "QUEST_LOG_UPDATE 重掃後反映日誌")
-- 沒變化就不更新面板
local refreshes = 0
local realRefresh = ns.Panel.Refresh
ns.Panel.Refresh = function(...) refreshes = refreshes + 1; return realRefresh(...) end
H.fire("QUEST_LOG_UPDATE"); S.flush()
H.eq(refreshes, 0, "日誌沒變就不重畫面板")
-- 大地圖關著（面板的父框架隱藏）：變了也不畫，顯示時補畫
S.wm:Hide()
S.log = {}
H.fire("QUEST_LOG_UPDATE"); S.flush()
H.eq(refreshes, 0, "地圖隱藏時不重畫")
H.eq(ns.Status.of(9900001), "open", "但狀態已更新")
S.wm:Show()
ns.Panel.frame._scripts.OnShow(ns.Panel.frame)
H.eq(refreshes, 1, "顯示時補畫一次")

-- 沒有 C_Timer.After（不應發生）也不爆：直接重掃
ns, S = setup()
_G.C_Timer = nil
S.log = { { questID = 9900002 } }
H.check(pcall(H.fire, "QUEST_LOG_UPDATE"), "沒有 C_Timer 不報錯")
H.eq(ns.Status.of(9900002), "log", "沒有 C_Timer 時直接重掃")

-- 日誌裡的壞項目（nil、缺 questID）不爆
ns, S = setup()
S.log = { { isHeader = true }, {}, { questID = 9900001 } }
H.check(pcall(H.fire, "QUEST_ACCEPTED", 1, 9900001), "壞項目不報錯")
H.eq(ns.Status.of(9900001), "log", "壞項目之外的正常項目照常")

-- 文案
H.eq(ns.L("panelAllDone"), "這張地圖沒有未完成的任務", "zhTW 文案")
ns = setup({ locale = "enUS" })
H.eq(ns.L("panelAllDone"), "No unfinished quests on this map", "enUS 文案")
