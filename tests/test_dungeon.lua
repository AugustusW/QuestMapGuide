-- V298 副本維度：遊戲紀錄 obs v2（任務目標在副本裡推進時記副本）、Data 副本 API、面板副本指南與選單、明細「副本」列
-- fixture：9900001 dg={33}、9900002 dg={33,409}；副本 33 影牙城堡（地城 18，首領 2）、409 熔火之心（團隊 60）、2875 卡拉贊墓穴（地城，無等級）

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

local function has(s, sub) return s and s:find(sub, 1, true) ~= nil end

-- 1. Data 副本 API
local ns = setup()
H.eq(ns.Data.dungeon(33).n, "影牙城堡", "副本名稱")
H.eq(table.concat(ns.Data.byDungeon(33), ","), "9900001,9900002", "副本任務")
local order = {}
for _, d in ipairs(ns.Data.dungeons()) do order[#order + 1] = d.id end
H.eq(table.concat(order, ","), "33,2875,409", "選單順序：地城依等級、沒等級最後、團隊在後")

-- 2. obs v2：在副本裡目標推進才記，野外推進不記；v1 存檔就地升級
ns = setup({ log = { [9900003] = 0 } })
QuestMapGuideDB.obs = { v = 1, quests = { [9900003] = { title = "舊紀錄", first = 1, last = 1 } } }
H.log[9900003] = 1; H.fire("QUEST_LOG_UPDATE")      -- 野外推進
H.check(QuestMapGuideDB.obs.quests[9900003].dungeons == nil, "野外推進不記副本")
H.inst.inside = true
H.now = H.now + 5
H.fire("QUEST_LOG_UPDATE")                          -- 進副本：建基準
H.check(QuestMapGuideDB.obs.quests[9900003].dungeons == nil, "進副本前的進度不算")
H.now = H.now + 5
H.log[9900003] = 2; H.fire("QUEST_LOG_UPDATE")      -- 副本裡推進
H.eq(QuestMapGuideDB.obs.v, 2, "格式升到 v2")
H.eq(QuestMapGuideDB.obs.quests[9900003].title, "舊紀錄", "升級不丟舊資料")
H.eq(QuestMapGuideDB.obs.quests[9900003].dungeons[33], 1, "副本裡推進記下副本 33")
H.now = H.now + 5
H.fire("QUEST_LOG_UPDATE")                          -- 沒有推進
H.eq(QuestMapGuideDB.obs.quests[9900003].dungeons[33], 1, "沒推進不累加")
H.log[9900099] = 0; H.now = H.now + 5; H.fire("QUEST_LOG_UPDATE")
H.check(QuestMapGuideDB.obs.quests[9900099] == nil, "新接的任務第一次看到不算推進")

-- 審查 M7：不在資料裡的副本（戰場等）推進不記；M5：保密的 IsInInstance 不比較、當作不在副本
ns = setup({ log = { [9900003] = 0 }, inside = true, instanceID = 489 })
H.now = H.now + 5; H.fire("QUEST_LOG_UPDATE")
H.log[9900003] = 1; H.now = H.now + 5; H.fire("QUEST_LOG_UPDATE")
H.check(not (QuestMapGuideDB.obs and QuestMapGuideDB.obs.quests and QuestMapGuideDB.obs.quests[9900003]), "資料沒有的副本不記")
ns = setup({ inside = true, instanceID = 33, mapType = 4 })
local SECRET = {}
_G.IsInInstance = function() return SECRET, "party" end
_G.issecretvalue = function(v) return v == SECRET end
ns.Panel.Refresh(1429)
H.check(ns.Panel.Guide() == nil, "保密的 IsInInstance 當作不在副本")
H.checkPrinted("保密 IsInInstance")

-- 3. 本機預覽（G13）：類型是地下城的任務，自己記到的副本補進 dg；不是地下城類型不補
ns = setup()
QuestMapGuideDB.obs = { v = 2, quests = {
  [9900004] = { title = "x", dungeons = { [2875] = 1 } },
  [9900005] = { title = "y", dungeons = { [2875] = 1 } } } }
local q4, q5 = ns.Data.quest(9900004), ns.Data.quest(9900005)
H.check(q5.t == 81, "fixture：9900005 是地下城類型")
H.eq(q5.dg and q5.dg[1], 2875, "地下城類型用遊戲紀錄補副本")
H.check(q5.obs and q5.obs.dg, "標遊戲紀錄")
H.check(q4.dg == nil, "類型未知不補")
H.eq(table.concat(ns.Data.byDungeon(2875), ","), "9900005", "副本清單含本機紀錄任務")

-- 4. 面板：人在副本裡打開地圖 → 副本指南（不顯示放大提示）；首領與任務
ns = setup({ inside = true, instanceID = 33, mapType = 4 })
H.eq(ns.Panel.Guide(), 33, "副本裡自動顯示副本指南")
H.check(not has(ns.Panel.Message() or "", "放大"), "不顯示放大提示")
H.check(has(ns.Panel.Header(), "影牙城堡"), "頁首是副本名稱")
H.eq(table.concat(ns.Panel.BossLines(), "|"), "1. 雷希戈爾|2. 大法師阿魯高", "首領依順序")
local ids = {}
ns.Panel.SetTab("all")
for _, r in ipairs(ns.Panel.Rows()) do ids[#ids + 1] = r.questId end
table.sort(ids)
H.eq(table.concat(ids, ","), "9900001,9900002", "任務是這個副本的任務（全部分頁）")

-- 審查 I1（2026-11-28）：副本指南藏了勾選框，所以低等、節慶、顯示已完成這些「顯示」類設定不套用（否則高等玩家看低等副本全空、
-- 也沒有勾選框可以改）；排除職業／陣營照用（跟自己有關，且預設開）
ns = setup({ inside = true, instanceID = 33, mapType = 4 })
_G.GetQuestDifficultyColor = function() return { r = 0.5, g = 0.5, b = 0.5 } end; H.installed.GetQuestDifficultyColor = true
ns.Status.of = function(id) return id == 9900002 and "done" or "open" end
ns.Panel.Refresh(1429)
ns.Panel.SetTab("open")
ids = {}
for _, r in ipairs(ns.Panel.Rows()) do ids[#ids + 1] = r.questId end
H.eq(table.concat(ids, ","), "9900001", "副本指南：灰色低等任務照列（沒有勾選框可開）")
ns.Panel.SetTab("all")
ids = {}
for _, r in ipairs(ns.Panel.Rows()) do ids[#ids + 1] = r.questId end
table.sort(ids)
H.eq(table.concat(ids, ","), "9900001,9900002", "副本指南全部分頁含已完成")
_G.GetQuestDifficultyColor = nil

-- 審查 I4：首領區只在副本指南時顯示（不顯示時不吃搜尋框那一塊的滾輪）
H.check(ns.Panel.bossArea._shown, "副本指南：首領區顯示")
ns.Panel.PickDungeon(nil)
ns = setup()
ns.Panel.Refresh(1429)
H.check(not ns.Panel.bossArea._shown, "一般清單：首領區藏起來")

-- 認不得的副本：照舊顯示放大提示
ns = setup({ inside = true, instanceID = 99999, mapType = 4 })
H.check(ns.Panel.Guide() == nil, "認不得的副本不進指南")
H.check(has(ns.Panel.Message() or "", "放大"), "照舊顯示放大提示")

-- 5. 選單：野外也能選；選了就顯示該副本，選「目前地圖」回到原本清單；面板關掉再開回到目前地圖
ns = setup()
local items = ns.Panel.MenuItems()
local labels = {}
for _, it in ipairs(items) do labels[#labels + 1] = it.label end
H.eq(table.concat(labels, "|"), "目前地圖|地城|影牙城堡|卡拉贊墓穴|團隊副本|熔火之心", "選單分組與順序")
H.eq(items[3].lv, "18", "選單顯示建議等級")
H.eq(items[4].lv, "等級尚未收錄", "沒有等級的標示")
ns.Panel.PickDungeon(409)
H.eq(ns.Panel.Guide(), 409, "野外選副本")
H.eq(#ns.Panel.BossLines(), 1, "首領 0 個顯示一行說明")
H.check(has(ns.Panel.BossLines()[1], "尚未收錄"), "首領尚未收錄")
H.check(ns.Panel.MenuItems()[6].current, "目前選的打勾")
ns.Panel.PickDungeon(nil)
H.check(ns.Panel.Guide() == nil, "回到目前地圖")
ns.Panel.PickDungeon(2875)
ns.Panel.SetTab("all")
H.check(has(ns.Panel.Message() or "", "還沒有關聯的任務"), "副本沒有任務的空狀態")
ns.Panel.frame:Hide(); ns.Panel.frame:Show()
H.check(ns.Panel.Guide() == nil, "面板關掉再開回到目前地圖")

-- 5b. 實機回報（2026-11-27）：選單半透明看不清、54 項超出面板、▾ 與 ✓ 遊戲字型沒有（顯示成方框）
ns = setup()
ns.Panel.Refresh(1429)
local mf = ns.Panel.menuFrame
H.eq(mf.box.bg._ct[4], 1, "選單底色不透明")
H.check(not has(ns.Panel.dungeonButton.label:GetText() or "", "▾"), "按鈕不用 ▾ 字元")
H.check(ns.Panel.dungeonButton.arrow._tex ~= nil, "按鈕箭頭用材質")
ns.Panel.MENU_ROWS = 3
ns.Panel.ShowMenu()
H.eq(table.concat(ns.Panel.MenuVisible(), "|"), "目前地圖|地城|影牙城堡", "選單只顯示前 MENU_ROWS 項")
ns.Panel.ScrollMenu(-1)
H.eq(table.concat(ns.Panel.MenuVisible(), "|"), "地城|影牙城堡|卡拉贊墓穴", "滾輪往下捲一項")
ns.Panel.ScrollMenu(-10)
H.eq(table.concat(ns.Panel.MenuVisible(), "|"), "卡拉贊墓穴|團隊副本|熔火之心", "捲到底就停")
ns.Panel.ScrollMenu(10)
H.eq(ns.Panel.MenuVisible()[1], "目前地圖", "捲到頂就停")
H.check(mf._height <= 12 + 3 * 16 + 16, "選單高度有上限")
ns.Panel.PickDungeon(409)
ns.Panel.ShowMenu()
local vis = ns.Panel.MenuVisible()
H.eq(vis[#vis], "熔火之心", "打開選單時目前選的那項在可見範圍內")
local cur
for _, b in ipairs(ns.Panel.menuButtons) do if b:IsShown() and b.id == 409 then cur = b end end
H.check(cur.check._shown and cur.check._tex ~= nil, "目前選的用勾勾材質")
H.eq(cur.text:GetText(), "熔火之心", "項目文字不含 ✓")
for _, f in ipairs({ "Panel.lua", "Detail.lua", "Locale.lua", "Data.lua" }) do
  local src = io.open(H.dir .. "/" .. f):read("*a"):gsub("%-%-[^\n]*", "")
  for _, g in ipairs({ "▾", "✓", "・" }) do
    H.check(not src:find(g, 1, true), f .. " 不含遊戲字型沒有的字元 " .. g)
  end
end

-- 6. 明細：副本列，點了切到該副本指南；本機紀錄補的標遊戲紀錄
ns = setup()
ns.Detail.Open(9900002)
local lines = ns.Detail.Lines()
local found
for _, l in ipairs(lines) do if has(l, "副本") and has(l, "影牙城堡") then found = l end end
H.check(found ~= nil, "明細有副本列")
H.check(has(table.concat(lines, "\n"), "熔火之心"), "多個副本都列出")
H.check(ns.Detail.ClickDungeon(409), "副本列可點")
H.eq(ns.Panel.Guide(), 409, "點了切到副本指南")
