-- 遊戲任務日誌點任務 → 面板切到那個任務（開明細＋標記起點）。post-hook，不取代遊戲函式。
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    if type(old) ~= "function" then error("Attempt to hook a non-existing function: " .. tostring(name)) end
    t[name] = function(...) old(...) fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = opts.secret or function() return false end; H.installed.issecretvalue = true
  _G.GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
  H.installed.GameTooltip = true
  local calls = { show = 0, sel = 0, entry = 0 }
  local log = opts.log or { [1] = { questID = 9900002 }, [2] = { isHeader = true, questID = 9900001 }, [3] = { questID = 4242 } }
  if not opts.noShowDetails then
    _G.QuestMapFrame_ShowQuestDetails = function() calls.show = calls.show + 1 end; H.installed.QuestMapFrame_ShowQuestDetails = true
  end
  if not opts.noSetSelection then
    _G.QuestLog_SetSelection = function() calls.sel = calls.sel + 1 end; H.installed.QuestLog_SetSelection = true
  end
  _G.SelectQuestLogEntry = function() calls.entry = calls.entry + 1 end; H.installed.SelectQuestLogEntry = true
  if not opts.noGetInfo then
    _G.C_QuestLog = { GetInfo = function(i) return log[i] end }; H.installed.C_QuestLog = true
  end
  if opts.title then
    _G.GetQuestLogTitle = function(i) local e = log[i]; if e then return "t", 1, nil, e.isHeader, nil, nil, nil, e.questID end end
    H.installed.GetQuestLogTitle = true
  end
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  ns.Panel.Refresh(1429)
  return ns, wm, calls
end

-- 現代式日誌：QuestMapFrame_ShowQuestDetails(questID)
do
  local ns, wm, calls = setup()
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(calls.show, 1, "遊戲原本的函式照常執行（post-hook）")
  H.eq(ns.Detail.Current(), 9900001, "日誌點任務：開明細")
  H.eq(ns.Pins.Selected(), 9900001, "日誌點任務：標記起點")
  -- 不在資料裡：不理
  QuestMapFrame_ShowQuestDetails(4242)
  H.eq(ns.Detail.Current(), 9900001, "資料裡沒有的任務：不切換")
  H.eq(ns.Pins.Selected(), 9900001, "資料裡沒有的任務：標記不變")
  -- 非數字參數：不理也不報錯
  QuestMapFrame_ShowQuestDetails(nil)
  QuestMapFrame_ShowQuestDetails("x")
  H.eq(ns.Detail.Current(), 9900001, "非數字參數不切換")
end

-- 經典式日誌：QuestLog_SetSelection(index) → C_QuestLog.GetInfo(index).questID
do
  local ns = setup()
  QuestLog_SetSelection(1)
  H.eq(ns.Detail.Current(), 9900002, "經典日誌：index 換成 questID")
  QuestLog_SetSelection(2)
  H.eq(ns.Detail.Current(), 9900002, "標題列：不切換")
  QuestLog_SetSelection(99)
  H.eq(ns.Detail.Current(), 9900002, "沒有這一列：不切換")
  SelectQuestLogEntry(1)
  H.eq(ns.Detail.Current(), 9900002, "SelectQuestLogEntry 也會處理（同一個任務）")
end
-- 沒有 C_QuestLog.GetInfo：退回 GetQuestLogTitle 第 8 個回傳值
do
  local ns = setup({ noGetInfo = true, title = true })
  QuestLog_SetSelection(1)
  H.eq(ns.Detail.Current(), 9900002, "GetQuestLogTitle 第 8 個回傳值是 questID")
end
-- 兩個都沒有：不報錯、不切換
do
  local ns = setup({ noGetInfo = true })
  QuestLog_SetSelection(1)
  H.eq(ns.Detail.Current(), nil, "查不到 questID：不切換")
end

-- 同一次點擊兩個 hook 都觸發：只處理一次
do
  local ns = setup()
  local b0 = ns.Detail.BuildCount()
  QuestLog_SetSelection(1)
  SelectQuestLogEntry(1)
  QuestMapFrame_ShowQuestDetails(9900002)
  H.eq(ns.Detail.BuildCount() - b0, 1, "同一個任務連續觸發：明細只建一次")
  -- 關掉明細後再點同一個任務：要再開
  ns.Detail.Close()
  QuestMapFrame_ShowQuestDetails(9900002)
  H.eq(ns.Detail.Current(), 9900002, "關掉後再點同一個任務：重新開")
  -- 換別的任務：切換
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(ns.Detail.Current(), 9900001, "換任務：切換")
end

-- 面板看不到時：記下來，地圖打開時才切
do
  local ns, wm = setup()
  wm:Hide()
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(ns.Detail.Current(), nil, "面板看不到：先不開明細")
  H.eq(ns.Pins.Selected(), nil, "面板看不到：先不標記")
  wm:Show()
  H.eq(ns.Detail.Current(), 9900001, "地圖打開：切到記下的任務")
  H.eq(ns.Pins.Selected(), 9900001, "地圖打開：標記")
  ns.Detail.Close()
  wm:Hide(); wm:Show()
  H.eq(ns.Detail.Current(), nil, "記下的任務只用一次")
end

-- 保密值不碰
do
  local ns = setup({ secret = function(v) return v == 9900001 end })
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(ns.Detail.Current(), nil, "保密的 questID：不切換")
  QuestLog_SetSelection(1)
  H.eq(ns.Detail.Current(), 9900002, "非保密照常")
end

-- 遊戲函式不存在：不報錯；之後才載入（按需載入的 Blizzard 插件）再掛
do
  local ns = setup({ noShowDetails = true, noSetSelection = true })
  H.check(ns.LogSelect ~= nil, "有 LogSelect")
  H.eq(ns.LogSelect.Hooked().QuestMapFrame_ShowQuestDetails, nil, "不存在的函式沒掛")
  _G.QuestMapFrame_ShowQuestDetails = function() end
  H.fire("ADDON_LOADED", "Blizzard_WorldMap")
  H.eq(ns.LogSelect.Hooked().QuestMapFrame_ShowQuestDetails, true, "之後載入：掛上")
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(ns.Detail.Current(), 9900001, "晚掛的 hook 也有效")
  -- 不重複掛
  local n = 0
  local f = _G.QuestMapFrame_ShowQuestDetails
  H.fire("ADDON_LOADED", "Other")
  H.check(_G.QuestMapFrame_ShowQuestDetails == f, "已掛過不再包一層")
  n = ns.Detail.BuildCount()
  ns.Detail.Close()
  QuestMapFrame_ShowQuestDetails(9900001)
  H.eq(ns.Detail.BuildCount() - n, 1, "只觸發一次")
end

-- /qmg probe 會回報這些名稱
do
  local ns = setup()
  local want = { QuestMapFrame_ShowQuestDetails = true, QuestLog_SetSelection = true, SelectQuestLogEntry = true, GetQuestLogTitle = true }
  for _, n in ipairs(ns.Probe.APIS) do want[n] = nil end
  H.check(next(want) == nil, "Probe.APIS 含日誌 hook 用到的名稱（缺：" .. tostring(next(want)) .. "）")
end
