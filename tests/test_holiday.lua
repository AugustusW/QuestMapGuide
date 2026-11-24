-- 0.2.0 節慶任務：標示（節慶／暗月）、「顯示節慶任務」勾選（預設不勾）隱藏節慶任務，暗月馬戲團只標示不隱藏
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3, name = "地圖" .. id } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  _G.GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
  H.installed.GameTooltip = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  if opts.charDb then QuestMapGuideCharDB = opts.charDb end
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  return ns
end
local function nm(s) return { zh = s, en = s } end
local function fake(ns, list, onMap)
  ns.Data.quest = function(id)
    local q = list[id]; if not q then return nil end
    local c = {}; for k, v in pairs(q) do c[k] = v end
    return c
  end
  local ids = {}
  for id in pairs(list) do ids[#ids + 1] = id end
  table.sort(ids)
  ns.Data.byMap = function() return onMap or ids end
  ns.Data.questIds = function() return ids end
  ns.Panel.InvalidateIndex()
end
local function rowIds(ns)
  local t = {}
  for _, r in ipairs(ns.Panel.Rows()) do t[r.questId] = true end
  return t
end
local QUESTS = {
  [9960001] = { n = nm("一般任務"), lv = 10, prev = {}, next = {} },
  [9960002] = { n = nm("冬幕節任務"), lv = 11, h = 1, prev = {}, next = {} },
  [9960003] = { n = nm("暗月任務"), lv = 12, h = 2, prev = {}, next = {} },
  [9960004] = { n = nm("節慶地下城"), lv = 13, h = 1, t = 81, prev = {}, next = {} },
}

-- 設定：預設不勾、存角色存檔
do
  local ns = setup()
  H.eq(ns.Filter.get("showHoliday"), false, "顯示節慶任務預設不勾")
  ns.Panel.SetCheck("showHoliday", true)
  H.eq(QuestMapGuideCharDB.filter.showHoliday, true, "勾選存進角色存檔")
  ns = setup({ charDb = { filter = { showHoliday = true } } })
  H.eq(ns.Filter.get("showHoliday"), true, "載入時還原")
  H.eq(ns.Panel.CheckButton("showHoliday"):GetChecked(), true, "勾選框照存檔")
end

-- Filter.visible
do
  local ns = setup()
  local F = ns.Filter
  local ok, why = F.visible(1, nil, { h = 1 }, "open")
  H.eq(ok, false, "節慶任務預設不顯示"); H.eq(why, "holiday", "原因 holiday")
  H.eq((F.visible(1, nil, { h = 2 }, "open")), true, "暗月馬戲團不隱藏")
  -- 跟「顯示低等任務」一樣只藏未接的：日誌中、已完成的節慶任務照常顯示（舊行為會藏）
  H.eq((F.visible(1, nil, { h = 1 }, "log")), true, "日誌中的節慶任務不隱藏")
  H.eq((F.visible(1, nil, { h = 1 }, "done")), true, "已完成的節慶任務不隱藏")
  H.eq((F.visible(1, { showHoliday = true }, { h = 1 }, "open")), true, "勾了就顯示")
  F.set("showHoliday", true)
  H.eq((F.visible(1, nil, { h = 1 }, "open")), true, "存檔勾了就顯示")
  F.set("showHoliday", false)
  H.eq((F.visible(1, nil, { h = 2 }, "open", nil)), true, "暗月馬戲團不受勾選影響")
  -- 沒傳狀態時自己查
  ns.Status.of = function() return "log" end
  H.eq((F.visible(1, nil, { h = 1 })), true, "沒傳狀態：查到日誌中就不隱藏")
  ns.Status.of = function() return "open" end
  H.eq((F.visible(1, nil, { h = 1 })), false, "沒傳狀態：查到未接就隱藏")
end

-- 名稱標示：名稱 (步驟) (類型) (節慶)
do
  local ns = setup()
  local F = ns.Filter
  H.eq(F.titled("甲", nil, nil, 1), "甲 (節慶)", "節慶標示")
  H.eq(F.titled("甲", nil, nil, 2), "甲 (暗月)", "暗月標示")
  H.eq(F.titled("甲", 81, nil, 1), "甲 (地下城) (節慶)", "類型在前、節慶在後")
  H.eq(F.titled("甲", nil, nil, nil), "甲", "一般任務沒有標示")
  H.eq(F.titled("甲", nil, nil, 3), "甲", "不認得的值不標")
  ns = setup({ locale = "enUS" })
  H.eq(ns.Filter.titled("A", nil, nil, 1), "A (Holiday)", "enUS Holiday")
  H.eq(ns.Filter.titled("A", 81, nil, 2), "A (Dungeon) (Darkmoon)", "enUS Darkmoon")
end

-- 清單、計數、搜尋、明細
do
  local ns = setup()
  fake(ns, QUESTS)
  ns.Panel.Refresh(1429)
  local ids = rowIds(ns)
  H.check(ids[9960001] and ids[9960003], "一般與暗月列出")
  H.check(not ids[9960002] and not ids[9960004], "節慶任務預設不列")
  H.eq(ns.Panel.Counts().openAll, 2, "未接計數不含節慶")
  H.eq(ns.Panel.Counts().all, 2, "全部計數不含節慶")
  -- 列標題帶標示
  local title
  for _, f in ipairs(H.frames) do if f.title and f.questId == 9960003 and f._shown then title = f.title:GetText() end end
  H.eq(title, "[12] 暗月任務 (暗月)", "清單列標題標示暗月")
  -- 搜尋：節慶任務也排除
  ns.Panel.SetSearch("冬幕")
  H.eq(#ns.Panel.Rows(), 0, "搜尋不出隱藏的節慶任務")
  ns.Panel.SetSearch("")
  -- 勾選後出現，並標示
  ns.Panel.SetCheck("showHoliday", true)
  ids = rowIds(ns)
  H.check(ids[9960002] and ids[9960004], "勾選後節慶任務列出")
  H.eq(ns.Panel.Counts().openAll, 4, "勾選後計數含節慶")
  for _, f in ipairs(H.frames) do if f.title and f.questId == 9960004 and f._shown then title = f.title:GetText() end end
  H.eq(title, "[13] 節慶地下城 (地下城) (節慶)", "清單列：類型與節慶標示")
  ns.Panel.SetSearch("冬幕")
  H.eq(#ns.Panel.Rows(), 1, "勾選後搜尋得到")
  ns.Panel.SetSearch("")
  -- 搜尋帶出的別張地圖節慶任務：不在這張地圖也要排除
  ns.Panel.SetCheck("showHoliday", false)
  fake(ns, QUESTS, { 9960001 })
  ns.Panel.Refresh(1429)
  ns.Panel.SetSearch("任務")
  local s = rowIds(ns)
  H.check(s[9960003] and not s[9960002], "跨地圖搜尋：暗月有、節慶沒有")
  -- 明細標題
  ns.Detail.Open(9960002)
  H.eq(ns.Detail.Lines()[1], "冬幕節任務 (節慶)", "明細標題標示節慶")
end

-- 勾選框位置：第三列第二欄（顯示低等任務右邊），標籤不重疊、不超出面板
do
  for _, loc in ipairs({ "zhTW", "enUS" }) do
    local ns = setup({ locale = loc })
    local P = ns.Panel
    local hol, low = P.CheckButton("showHoliday"), P.CheckButton("showLow")
    H.check(hol ~= nil, loc .. " 有顯示節慶任務勾選框")
    H.eq(hol.label:GetText(), loc == "zhTW" and "顯示節慶任務" or "Show holiday quests", loc .. " 標籤文字")
    H.eq(hol._pt[5], low._pt[5], loc .. " 與顯示低等任務同一列")
    H.check(hol._pt[4] > low._pt[4], loc .. " 在顯示低等任務右邊")
    H.eq(hol._pt[4], P.CheckButton("showDone")._pt[4], loc .. " 與第二欄對齊")
    local W = ns.Theme.PANEL_W
    -- 每個標籤：限寬、不換行；左欄標籤的右緣不碰到右欄勾選框，右欄不超出面板
    for _, key in ipairs({ "exclClass", "exclProf", "exclFaction", "showDone", "showLow", "showHoliday" }) do
      local c = P.CheckButton(key)
      local lw = c.label._width
      H.check(lw ~= nil and c.label._wrap == false, loc .. " " .. key .. " 標籤限寬不換行")
      local right = c._pt[4] + 22 + (lw or 999)
      if c._pt[4] < hol._pt[4] then
        H.check(right <= hol._pt[4], loc .. " " .. key .. " 左欄標籤不壓到右欄")
      else
        H.check(right <= W, loc .. " " .. key .. " 右欄標籤不超出面板")
      end
      H.check(math.min(c.label:GetStringWidth(), lw or 0) > 0, loc .. " " .. key .. " 有文字")
    end
  end
end

-- 日誌中／已完成的節慶任務：沒勾也留在分頁、計數裡
do
  local ns = setup()
  fake(ns, QUESTS)
  ns.Status.of = function(id) return id == 9960002 and "log" or (id == 9960004 and "done" or "open") end
  ns.Panel.Refresh(1429)
  H.eq(ns.Panel.Counts().log, 1, "日誌中計數含節慶任務")
  H.eq(ns.Panel.Counts().done, 1, "已完成計數含節慶任務")
  ns.Panel.SetTab("log")
  H.check(rowIds(ns)[9960002], "日誌中分頁列出節慶任務")
  ns.Panel.SetTab("done")
  H.check(rowIds(ns)[9960004], "已完成分頁列出節慶任務")
  ns.Panel.SetTab("open")
  H.check(not rowIds(ns)[9960002] and not rowIds(ns)[9960004], "未接分頁沒有它們")
  -- 未接的節慶任務仍然藏
  ns.Status.of = function() return "open" end
  ns.Panel.Refresh(1429)
  H.check(not rowIds(ns)[9960002], "未接的節慶任務仍然藏")
end

-- 搜尋：這張地圖上、日誌中的節慶任務，沒勾顯示節慶任務也搜得到
do
  local ns = setup()
  fake(ns, QUESTS)
  ns.Status.of = function(id) return id == 9960002 and "log" or "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetTab("log")
  ns.Panel.SetSearch("冬幕")
  H.check(rowIds(ns)[9960002], "日誌中的節慶任務：搜尋結果裡有")
  ns.Panel.SetTab("all")
  H.check(rowIds(ns)[9960002], "全部分頁搜尋也有")
  -- 對照：未接時同樣的搜尋找不到
  ns.Status.of = function() return "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetSearch("冬幕")
  H.check(not rowIds(ns)[9960002], "未接的節慶任務：搜尋找不到")
end
