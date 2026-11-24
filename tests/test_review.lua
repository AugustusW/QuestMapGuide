-- 最終審查修正：計時器回呼 pcall、事件註冊失敗、完成清單重讀頻率、搜尋計數、明細隱藏時不重建、
-- 任務表只解一次、語系分隔符、搜尋結果地圖名
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 日誌 questId 要過保密檢查（fail-closed）
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local T = { timers = {}, calls = { all = 0, info = 0 }, completed = {}, log = {} }
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  wm:Show()
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3, name = "Map" .. id } end }; H.installed.C_Map = true
  _G.C_Timer = { After = function(d, fn) T.timers[#T.timers + 1] = fn end }; H.installed.C_Timer = true
  function T.flush() local t = T.timers; T.timers = {}; for _, f in ipairs(t) do f() end end
  _G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return T.completed[id] == true end,
    GetNumQuestLogEntries = function()
      if T.failNum then error("boom-num") end
      return #T.log, #T.log
    end,
    GetInfo = function(i) T.calls.info = T.calls.info + 1; return T.log[i] end,
    GetAllCompletedQuestIDs = function()
      T.calls.all = T.calls.all + 1
      local t = {}
      for id in pairs(T.completed) do t[#t + 1] = id end
      return t
    end,
  }
  H.installed.C_QuestLog = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.time = function() return T.now or 1000 end; H.installed.time = true
  if opts.whitelist then H.eventWhitelist = opts.whitelist end
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  if ns.Panel.frame then ns.Panel.frame:Show() end
  return ns, T, wm
end

-- M1：Core.after 與 Status／Panel 的計時器回呼出錯不外洩，同一則錯誤只印一次
local ns, T = setup()
local failing = function() error("boom-after") end
H.check(ns.Core.after(1, failing), "Core.after 有 C_Timer 時回 true")
H.check(pcall(T.flush), "計時器回呼出錯不外洩")
H.eq(#H.printed, 1, "錯誤印一次")
H.check(H.printed[1] and H.printed[1]:find("boom-after", 1, true) ~= nil, "訊息含錯誤內容")
ns.Core.after(1, failing); T.flush()
H.eq(#H.printed, 1, "同一則錯誤不重複印")
H.printed = {}
T.failNum = true
H.fire("QUEST_LOG_UPDATE")
H.check(pcall(T.flush), "Status 延後重掃出錯不外洩")
H.eq(#H.printed, 1, "Status 計時器錯誤走回報路徑")
H.printed = {}
T.failNum = false
ns.Panel.QueueSearch("quest")
ns.Panel.SetSearch = function() error("boom-search") end
H.check(pcall(T.flush), "Panel 防抖搜尋回呼出錯不外洩")
H.eq(#H.printed, 1, "防抖搜尋錯誤走回報路徑")
H.printed = {}
_G.C_Timer = nil; H.installed.C_Timer = nil
H.eq(ns.Core.after(1, function() end), false, "沒有 C_Timer 回 false")

-- M2：事件註冊失敗不擋其他事件，並記進存檔
do
  local wl, seen = {}, {}
  for _, f in ipairs(H.tocFiles("QuestMapGuide_Forever.toc")) do
    local fh = io.open(H.dir .. "/" .. f, "r")
    local text = fh:read("*a"); fh:close()
    for ev in text:gmatch('Core%.on%("([A-Z_]+)"') do if not seen[ev] then seen[ev] = true; wl[ev] = true end end
  end
  H.check(wl.PLAYER_TARGET_CHANGED and wl.UPDATE_MOUSEOVER_UNIT, "掃到 Learn 的事件")
  wl.PLAYER_TARGET_CHANGED = nil   -- 假裝這個客戶端不認得
  local ok, ns2 = pcall(setup, { whitelist = wl })
  H.check(ok, "不認得的事件名不讓載入失敗：" .. tostring(ns2))
  if ok then
    local bad = QuestMapGuideDB.probe and QuestMapGuideDB.probe.badEvents
    H.check(type(bad) == "table" and bad[1] == "PLAYER_TARGET_CHANGED", "probe.badEvents 記下失敗的事件")
    H.eq(#(bad or {}), 1, "只有一個失敗事件")
    _G.UnitGUID = function() return "Creature-0-4379-1-12-9901001-0000ABCDEF" end
    _G.UnitName = function() return "村長" end
    H.installed.UnitGUID = true; H.installed.UnitName = true
    _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
    H.fire("UPDATE_MOUSEOVER_UNIT")
    H.check(QuestMapGuideDB.npcNames[9901001] ~= nil, "其他事件照常運作")
  end
  H.eventWhitelist = nil
  -- 全部認得時沒有 badEvents
  local ns3 = setup({ whitelist = (function() local t = {} for k in pairs(wl) do t[k] = true end t.PLAYER_TARGET_CHANGED = true return t end)() })
  H.eq(QuestMapGuideDB.probe and QuestMapGuideDB.probe.badEvents, nil, "全部註冊成功時不寫 badEvents")
end

-- M5：完成清單只在登入／進世界／交任務，或距上次超過 60 秒才重讀
ns, T = setup()
T.now = 1000
H.fire("PLAYER_LOGIN")
H.eq(T.calls.all, 1, "登入重讀完成清單")
H.fire("PLAYER_ENTERING_WORLD")
H.eq(T.calls.all, 2, "進世界重讀")
H.fire("QUEST_TURNED_IN", 9900001)
H.eq(T.calls.all, 3, "交任務重讀")
H.fire("QUEST_LOG_UPDATE"); T.flush(); H.fire("QUEST_LOG_UPDATE"); T.flush()
H.eq(T.calls.all, 3, "QUEST_LOG_UPDATE 的延後重掃不重讀完成清單")
T.now = 1010
H.fire("QUEST_ACCEPTED", 1, 9900001)
H.eq(T.calls.all, 3, "接任務：60 秒內不重讀")
T.now = 1070
H.fire("QUEST_REMOVED", 9900001)
H.eq(T.calls.all, 4, "超過 60 秒的下一次重掃才重讀")
T.log = { { questID = 9900001 } }
local info0 = T.calls.info
H.fire("QUEST_LOG_UPDATE"); T.flush()
H.check(T.calls.info > info0, "延後重掃仍更新日誌集合")
H.eq(ns.Status.of(9900001), "log", "日誌集合已更新")

-- M6：搜尋中標題與分頁不顯示地圖計數；被截斷只在超過上限時
ns, T = setup()
ns.Panel.Refresh(1429)
H.eq(ns.Panel.Header(), "未接 1 筆", "無搜尋：標題是目前分頁筆數")
H.check(ns.Panel.TabText("open"):find("%(%d+%)") ~= nil, "無搜尋：分頁有數字")
ns.Panel.SetSearch("quest")
H.eq(ns.Panel.Header(), "搜尋結果 " .. #ns.Panel.Rows() .. " 筆", "搜尋中：標題顯示搜尋結果筆數")
H.eq(ns.Panel.TabText("open"), "未接", "搜尋中：分頁不帶地圖計數")
ns.Panel.SetSearch("")
H.eq(ns.Panel.Header(), "未接 1 筆", "清空搜尋後恢復分頁筆數")
do
  local realQ = ns.Data.quest
  ns.Filter.set("tab", "all")
  local function fake(n)
    local ids = {}
    for i = 1, n do ids[i] = 8000000 + i end
    ns.Data.questIds = function() return ids end
    ns.Data.quest = function(id)
      if id >= 8000000 then return { n = { en = "Bulk " .. id }, lv = 1, min = 1 } end
      return realQ(id)
    end
    ns.Panel.InvalidateIndex()
    ns.Panel.SetSearch("bulk")
  end
  fake(200)
  H.eq(#ns.Panel.Rows(), 200, "剛好 200 筆")
  H.eq(ns.Panel.Capped(), false, "剛好上限不算截斷")
  H.eq(ns.Panel.Header(), "搜尋結果 200 筆", "未截斷標題無 +")
  fake(201)
  H.eq(#ns.Panel.Rows(), 200, "超過上限只列 200")
  H.eq(ns.Panel.Capped(), true, "超過上限才算截斷")
  H.eq(ns.Panel.Header(), "搜尋結果 200 筆+", "截斷時標題帶 +")
  ns.Data.quest = realQ
end
ns, T = setup({ locale = "enUS" })
ns.Panel.Refresh(1429); ns.Panel.SetSearch("quest")
H.check(ns.Panel.Header():find("search results", 1, true) ~= nil, "英文搜尋標題")

-- M7：地圖（面板）隱藏時不重建明細，顯示時補建
ns, T, wm = setup()
ns.Panel.Refresh(1429)
ns.Detail.Open(9900001)
local b0 = ns.Detail.BuildCount()
ns.Detail.Refresh()
H.eq(ns.Detail.BuildCount(), b0 + 1, "看得到時照常重建")
wm:Hide()
ns.Panel.StatusChanged()
ns.Detail.Refresh()
H.eq(ns.Detail.BuildCount(), b0 + 1, "地圖隱藏時不重建")
H.eq(ns.Detail.IsStale(), true, "標記過期")
wm:Show()
H.eq(ns.Detail.BuildCount(), b0 + 2, "顯示時補建一次")
H.eq(ns.Detail.IsStale(), false, "過期標記清掉")

-- M8：每筆任務、entity 在一次 Refresh 內只解一次
ns, T = setup()
local origQ, origE = ns.Data.quest, ns.Data.entity
local qc, ec = 0, 0
ns.Data.quest = function(id) if id == 9900001 then qc = qc + 1 end return origQ(id) end
ns.Data.entity = function(k) if k == "n9901001" then ec = ec + 1 end return origE(k) end
ns.Panel.Refresh(1429)
H.eq(qc, 1, "Refresh：任務表只解一次")
H.eq(ec, 1, "Refresh：起點 entity 只解一次（npcName 沿用已解的表）")
_G.UnitFactionGroup = function() return "Alliance" end; H.installed.UnitFactionGroup = true; ns.Filter.reload()
H.eq(ns.Filter.visible(9900001, nil, { f = "H" }), false, "Filter.visible 可傳已解碼的任務表（陣營 H 被排除）")
H.eq(select(1, ns.Filter.color(9900001, { lv = 0 })), 1, "Filter.color 可傳任務表")

-- M9：分隔符走語系
ns = setup({ locale = "enUS" })
ns.Data.desc = function() return nil end   -- 描述是資料本身的內容（含全形引號），不屬於分隔符檢查
ns.Panel.Refresh(1429); ns.Detail.Open(9900001)
local en = table.concat(ns.Detail.Lines(), "\n")
H.check(not en:find("：", 1, true) and not en:find("　", 1, true) and not en:find("、", 1, true), "英文明細沒有全形標點")
H.check(en:find("Status: ", 1, true) and en:find("Experience: 450", 1, true), "英文用「: 」")
H.check(en:find("Level 7 Min 5", 1, true), "英文等級列用半形空白")
H.check(en:find("#1, #2", 1, true), "英文清單分隔用「, 」")
ns = setup()
ns.Panel.Refresh(1429); ns.Detail.Open(9900001)
local zh = table.concat(ns.Detail.Lines(), "\n")
H.check(zh:find("經驗值：450", 1, true) and zh:find("#1、#2", 1, true), "中文仍用全形")

-- M10：搜尋結果的地圖名：先看起點 NPC 的第一個 spawn 地圖，沒有才用任務的第一張地圖
ns = setup()
do
  local realQ = ns.Data.quest
  ns.Data.questIds = function() return { 8000001, 8000002 } end
  ns.Data.quest = function(id)
    if id == 8000001 then return { n = { en = "Mapname Probe" }, s = { "n9901001" }, maps = { 1453 } } end
    if id == 8000002 then return { n = { en = "Mapname Fallback" }, s = {}, maps = { 1453 } } end
    return realQ(id)
  end
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 地圖名要過保密檢查
  ns.Panel.InvalidateIndex()
  ns.Panel.Refresh(1429)
  ns.Filter.set("tab", "all")
  ns.Panel.SetSearch("mapname probe")
  H.eq(ns.Panel.Rows()[1] and ns.Panel.Rows()[1].mapName, "Map1429", "用起點 NPC 第一個 spawn 的地圖")
  ns.Panel.SetSearch("mapname fallback")
  H.eq(ns.Panel.Rows()[1] and ns.Panel.Rows()[1].mapName, "Map1453", "沒有起點資料退回任務的第一張地圖")
end
