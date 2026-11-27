-- 任務 Shift 點擊貼到聊天（2026-11-28 使用者選 A）：面板清單的任務列、明細標題列 Shift 點 → 貼進聊天輸入框。
-- 日誌裡的任務：遊戲有 GetQuestLink 就用它，沒有就自組 |Hquest:<id>:0|h[名稱]|h（實機確認等級欄要 0 才送得出去）；
-- 不在日誌裡的任務貼純文字「[名稱]」（伺服器會把這種連結剝成純文字）。
-- 聊天輸入框沒開時（ChatEdit_InsertLink 回 false）用 ChatFrame_OpenChat 開一個帶入。
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local mapId = opts.mapId or 1429
  local wm = H.widget("Frame")
  wm.GetMapID = function() return mapId end
  wm.OnMapChanged = function() end
  wm.SetMapID = function(self, id) mapId = id; self.OnMapChanged(self) end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  _G.C_Item = { GetItemInfo = function() end }; H.installed.C_Item = true
  H.now = 1000
  _G.time = function() return H.now end; H.installed.time = true
  -- 副本狀態與任務日誌（測試逐步改）
  H.inst = { inside = opts.inside or false, id = opts.instanceID or 33, name = "影牙城堡" }
  H.log = opts.log or {}   -- { [questID] = 已完成數 }
  _G.IsInInstance = function() return H.inst.inside, H.inst.inside and "party" or "none" end; H.installed.IsInInstance = true
  _G.GetInstanceInfo = function()
    if not H.inst.inside then return "艾澤拉斯", "none", 0, "", 0, 0, false, 0 end
    return H.inst.name, "party", 1, "普通", 5, 0, false, H.inst.id
  end
  H.installed.GetInstanceInfo = true
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function() local n = 0 for _ in pairs(H.log) do n = n + 1 end return n end,
    GetInfo = function(i)
      local ids = {} for id in pairs(H.log) do ids[#ids + 1] = id end table.sort(ids)
      return ids[i] and { questID = ids[i], isHeader = false } or nil
    end,
    GetQuestObjectives = function(qid) local d = H.log[qid] return d and { { numFulfilled = d, numRequired = 9 } } or nil end,
  }
  H.installed.C_QuestLog = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = opts.mapType or 3, name = "地圖" .. id } end,
               GetBestMapForUnit = function() return mapId end }
  H.installed.C_Map = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); if ns.Panel.frame then ns.Panel.frame:Show() end
  return ns, wm
end

-- 日誌狀態：預設 9900001 在日誌裡
local function inLog(ns, ids)
  local set = {}
  for _, id in ipairs(ids or { 9900001 }) do set[id] = true end
  ns.Status.of = function(id) return set[id] and "log" or "open" end
end

local function install(opts)
  H.shift = opts.shift
  _G.IsShiftKeyDown = function() return H.shift end; H.installed.IsShiftKeyDown = true
  H.inserted, H.opened = {}, {}
  _G.ChatEdit_InsertLink = function(l) H.inserted[#H.inserted + 1] = l; return opts.chatOpen ~= false end
  H.installed.ChatEdit_InsertLink = true
  _G.ChatFrame_OpenChat = function(l) H.opened[#H.opened + 1] = l end; H.installed.ChatFrame_OpenChat = true
end

local function rowFor(ns, qid)
  for _, f in ipairs(H.frames) do
    if f._parent == ns.Panel.frame and f.questId == qid and f._shown then return f end
  end
end

local function titleRow(ns)
  for _, f in ipairs(H.frames) do
    if f._parent == ns.Detail.frame and f.fs and f._shown and f.fs:GetText() and f.fs:GetText():find("測試任務一", 1, true) then return f end
  end
end

-- 1. 面板任務列：Shift 點 → 自組連結貼進聊天，不開明細
local ns = setup()
install({ shift = true }); inLog(ns)
ns.Panel.Refresh(1429)
ns.Panel.SetTab("all")
local row = rowFor(ns, 9900001)
H.check(row ~= nil, "清單有 9900001 列")
local opened = 0
local realOpen = ns.Detail.Open
ns.Detail.Open = function(...) opened = opened + 1; return realOpen(...) end
row._scripts.OnClick(row)
H.eq(H.inserted[1], "|cffffff00|Hquest:9900001:0|h[測試任務一]|h|r", "自組任務連結：等級欄固定 0（實機：遊戲自己的連結也是 0，填真實等級會被伺服器剝成文字）")
H.eq(opened, 0, "Shift 點不開明細")
-- 一般點擊照舊開明細、不貼
H.shift = false
row._scripts.OnClick(row)
H.eq(#H.inserted, 1, "一般點擊不貼")
H.eq(opened, 1, "一般點擊開明細")
ns.Detail.Open = realOpen

-- 2. 明細標題列：Shift 點 → 貼連結；一般點擊不動作
ns = setup()
install({ shift = true }); inLog(ns)
ns.Detail.Open(9900001)
local t = titleRow(ns)
H.check(t ~= nil, "明細標題列是按鈕")
t._scripts.OnClick(t)
H.eq(H.inserted[1], "|cffffff00|Hquest:9900001:0|h[測試任務一]|h|r", "明細標題 Shift 點貼連結")
H.shift = false
t._scripts.OnClick(t)
H.eq(#H.inserted, 1, "明細標題一般點擊不貼")

-- 3. 遊戲有 GetQuestLink：用遊戲的連結
ns = setup()
install({ shift = true }); inLog(ns)
_G.GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. ":7|h[官方]|h|r" end; H.installed.GetQuestLink = true
H.check(ns.Detail.QuestLinkClick(9900001), "Shift 點回 true")
H.eq(H.inserted[1], "|cffffff00|Hquest:9900001:7|h[官方]|h|r", "有 GetQuestLink 用遊戲的")
_G.GetQuestLink = function() error("boom") end
ns.Detail.QuestLinkClick(9900001)
H.eq(H.inserted[2], "|cffffff00|Hquest:9900001:0|h[測試任務一]|h|r", "GetQuestLink 出錯退回自組")
_G.GetQuestLink = nil

-- 4. 聊天輸入框沒開：用 ChatFrame_OpenChat 開一個帶入
ns = setup()
install({ shift = true, chatOpen = false }); inLog(ns)
ns.Detail.QuestLinkClick(9900001)
H.eq(H.opened[1], "|cffffff00|Hquest:9900001:0|h[測試任務一]|h|r", "聊天框沒開就開一個帶入連結")

-- 5. 沒有等級的任務用 0；名稱裡的 | 不會弄壞連結；沒有 Shift 回 false
ns = setup()
install({ shift = false }); inLog(ns)
H.check(not ns.Detail.QuestLinkClick(9900001), "沒按 Shift 回 false")
H.eq(#H.inserted, 0, "沒按 Shift 不貼")
H.eq(ns.Detail.QuestLink(12345678), nil, "資料沒有的任務不產連結")
-- 名稱裡的 | 拿掉（不會被當成跳脫碼弄壞連結）
local realQuest = ns.Data.quest
ns.Data.quest = function(id) local q = realQuest(id); if id == 9900001 and q then q.n = { zh = "甲|乙", en = "A|B" } end return q end
H.eq(ns.Detail.QuestLink(9900001), "|cffffff00|Hquest:9900001:0|h[甲乙]|h|r", "名稱裡的 | 拿掉")
ns.Data.quest = realQuest

-- 6. 實機（2026-11-28，使用者選 A）：不在日誌裡的任務，格式對了伺服器仍剝成文字 → 改貼純文字「[名稱]」；
-- 日誌裡的照樣貼連結（遊戲 GetQuestLink，實機確認送得出去）
ns = setup()
install({ shift = true }); inLog(ns, {})
_G.GetQuestLink = function(id) return "|cffffff00|Hquest:" .. id .. ":0|h[官方]|h|r" end; H.installed.GetQuestLink = true
ns.Detail.QuestLinkClick(9900001)
H.eq(H.inserted[1], "[測試任務一]", "不在日誌裡：貼純文字名稱")
H.check(not H.inserted[1]:find("|", 1, true), "純文字不含跳脫碼")
inLog(ns, { 9900001 })
ns.Detail.QuestLinkClick(9900001)
H.eq(H.inserted[2], "|cffffff00|Hquest:9900001:0|h[官方]|h|r", "在日誌裡：貼遊戲連結")
_G.GetQuestLink = nil
H.checkPrinted("任務連結")

