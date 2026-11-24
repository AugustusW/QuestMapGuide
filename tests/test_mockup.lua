-- Task 5e：mockup 回饋調整（金錢、連鎖步驟、物品一欄、低等任務、頁首計數、羊皮紙底、已完成列）
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  if opts.level then _G.UnitLevel = function() return opts.level end; H.installed.UnitLevel = true end
  local cache = {}
  _G.C_Item = { GetItemInfo = function(id) local n = cache[id]; if n then return n, "|Hitem:" .. id .. "|h[" .. n .. "]|h", cache.q end end }
  H.installed.C_Item = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  return ns, wm, cache
end

-- 用假任務表取代 ns.Data 的讀取（API 層替身）；list 是 { [id] = record }
local function fake(ns, list, mapIds)
  ns.Data.quest = function(id)
    local q = list[id]
    if not q then return nil end
    local c = {}
    for k, v in pairs(q) do c[k] = v end
    return c
  end
  ns.Data.byMap = function() return mapIds end
  local all = {}
  for id in pairs(list) do all[#all + 1] = id end
  table.sort(all)
  ns.Data.questIds = function() return all end
  ns.Data.desc = function() return nil end
  ns.Panel.InvalidateIndex()
  ns.Filter.ResetSteps()
end

local function nm(s) return { zh = s } end
local CAP = "桑德爾船長的寶藏"
local CHAIN = {
  [9910001] = { n = nm(CAP), lv = 10, prev = {}, next = { 9910002 } },
  [9910002] = { n = nm(CAP), lv = 10, prev = { 9910001 }, next = { 9910003 }, t = 81 },
  [9910003] = { n = nm(CAP), lv = 10, prev = { 9910002 }, next = {} },
  -- 分岔：9920001 之後有兩條
  [9920001] = { n = nm("分岔"), lv = 10, prev = {}, next = { 9920002, 9920003 } },
  [9920002] = { n = nm("分岔"), lv = 10, prev = { 9920001 }, next = {} },
  [9920003] = { n = nm("分岔"), lv = 10, prev = { 9920001 }, next = {} },
  -- 名稱不同
  [9930001] = { n = nm("甲"), lv = 10, prev = {}, next = { 9930002 } },
  [9930002] = { n = nm("乙"), lv = 10, prev = { 9930001 }, next = {} },
  -- 鏈長 1
  [9940001] = { n = nm("單獨"), lv = 10, prev = {}, next = {} },
  -- 排序用：questId 小的是第 2 步
  [9960001] = { n = nm("丙"), lv = 10, prev = { 9960002 }, next = {} },
  [9960002] = { n = nm("丙"), lv = 10, prev = {}, next = { 9960001 } },
  -- 前置不在資料裡
  [9970001] = { n = nm("丁"), lv = 10, prev = { 9979999 }, next = { 9970002 } },
  [9970002] = { n = nm("丁"), lv = 10, prev = { 9970001 }, next = {} },
}
local ALL = { 9910001, 9910002, 9910003, 9920001, 9920002, 9920003, 9930001, 9930002, 9940001, 9960001, 9960002, 9970001, 9970002 }

local function titleOf(ns, id)
  for _, f in ipairs(H.frames) do
    if f.title and f.questId == id and f._shown then return f.title:GetText(), f end
  end
end

-- ===== 2. 連鎖步驟 =====
do
  local ns = setup()
  fake(ns, CHAIN, ALL)
  local n, m = ns.Filter.step(9910001); H.eq(n, 1, "鏈 1/3 n"); H.eq(m, 3, "鏈 1/3 m")
  n, m = ns.Filter.step(9910002); H.eq(n, 2, "鏈 2/3 n"); H.eq(m, 3, "鏈 2/3 m")
  n, m = ns.Filter.step(9910003); H.eq(n, 3, "鏈 3/3 n")
  H.eq(ns.Filter.step(9920001), nil, "分岔起點不加")
  H.eq(ns.Filter.step(9920002), nil, "分岔分支不加")
  H.eq(ns.Filter.step(9930001), nil, "名稱不同不加")
  H.eq(ns.Filter.step(9940001), nil, "鏈長 1 不加")
  H.eq(ns.Filter.step(9970002), nil, "前置不在資料裡不加")
  H.eq(ns.Filter.titled("丙", nil, 9960002), "丙 (1/2)", "titled 附步驟")
  H.eq(ns.Filter.titled(CAP, 81, 9910002), CAP .. " (2/3) (地下城)", "步驟在類型標示之前")
  H.eq(ns.Filter.titled("單獨", 81, 9940001), "單獨 (地下城)", "沒有步驟只有類型")
  -- 快取：資料換掉後仍用舊結果，直到 ResetSteps
  local calls = 0
  local real = ns.Data.quest
  ns.Data.quest = function(id) calls = calls + 1; return real(id) end
  ns.Filter.step(9910001)
  H.eq(calls, 0, "步驟結果快取，不再走鏈")
  ns.Filter.ResetSteps()
  ns.Filter.step(9910001)
  H.check(calls > 0, "ResetSteps 後重算")

  ns, _ = setup()
  fake(ns, CHAIN, { 9910001, 9910002, 9910003, 9960001, 9960002, 9940001 })
  ns.Panel.Refresh(1429)
  local rows = ns.Panel.Rows()
  local order = {}
  for i, r in ipairs(rows) do order[i] = r.questId; H.check(not r.name:find("%("), "row.name 不含步驟：" .. r.name) end
  H.eq(table.concat(order, ","), "9960001,9960002,9940001,9910001,9910002,9910003", "排序不受步驟影響（同名同等級依 questId）")
  local t = titleOf(ns, 9910002)
  H.eq(t, "[10] " .. CAP .. " (2/3) (地下城)", "清單列標題含步驟與類型")
  H.eq((titleOf(ns, 9940001)), "[10] 單獨", "無步驟列照舊")
  -- 搜尋
  ns.Panel.SetSearch("桑德爾")
  t = titleOf(ns, 9910003)
  H.eq(t, "[10] " .. CAP .. " (3/3)", "搜尋結果列含步驟")
  for _, r in ipairs(ns.Panel.Rows()) do H.eq(r.name, CAP, "搜尋 row.name 是純名稱") end
  ns.Panel.SetSearch("")
  -- 明細
  ns.Detail.Open(9910002)
  local lines = ns.Detail.Lines()
  H.eq(lines[1], CAP .. " (2/3) (地下城)", "明細標題含步驟與類型")
  local s = table.concat(lines, "\n")
  H.check(s:find("  " .. CAP .. " (1/3)", 1, true) ~= nil, "前置連結含步驟")
  H.check(s:find("  " .. CAP .. " (3/3)", 1, true) ~= nil, "後續連結含步驟")
end

-- 連結只有一邊宣告：取兩邊宣告的聯集；分岔只由一邊宣告也要擋
do
  local ns = setup()
  fake(ns, {
    [9981001] = { n = nm("單邊"), lv = 10, next = { 9981002 } },          -- 只有 next 宣告
    [9981002] = { n = nm("單邊"), lv = 10 },
    [9981003] = { n = nm("反向"), lv = 10 },
    [9981004] = { n = nm("反向"), lv = 10, prev = { 9981003 } },          -- 只有 prev 宣告
    [9982001] = { n = nm("暗岔"), lv = 10, next = { 9982002 } },
    [9982002] = { n = nm("暗岔"), lv = 10 },
    [9982003] = { n = nm("暗岔"), lv = 10, prev = { 9982001 } },          -- 分岔只由子端宣告
  }, {})
  local n, m = ns.Filter.step(9981001); H.check(n == 1 and m == 2, "只有 next 宣告的連結仍有 (1/2)")
  n, m = ns.Filter.step(9981002); H.check(n == 2 and m == 2, "只有 next 宣告：後端 (2/2)")
  n, m = ns.Filter.step(9981003); H.check(n == 1 and m == 2, "只有 prev 宣告：前端 (1/2)")
  n, m = ns.Filter.step(9981004); H.check(n == 2 and m == 2, "只有 prev 宣告：後端 (2/2)")
  -- 不同名的鄰居是鏈的邊界，不影響同名段
  fake(ns, {
    [9983001] = { n = nm("別名"), lv = 10, next = { 9983002 } },
    [9983002] = { n = nm("同段"), lv = 10, prev = { 9983001 }, next = { 9983003 } },
    [9983003] = { n = nm("同段"), lv = 10, prev = { 9983002 } },
  }, {})
  n, m = ns.Filter.step(9983002); H.check(n == 1 and m == 2, "前面接著不同名任務：同名段仍標 (1/2)")
  H.eq(ns.Filter.step(9983001), nil, "不同名的鄰居本身不加")
  -- 兩個同名前驅匯入同一點＝非線性
  fake(ns, {
    [9984001] = { n = nm("匯"), lv = 10, next = { 9984003 } },
    [9984002] = { n = nm("匯"), lv = 10, next = { 9984003 } },
    [9984003] = { n = nm("匯"), lv = 10 },
  }, {})
  H.eq(ns.Filter.step(9984003), nil, "兩個同名前驅匯入不加")
  fake(ns, {
    [9982001] = { n = nm("暗岔"), lv = 10, next = { 9982002 } },
    [9982002] = { n = nm("暗岔"), lv = 10 },
    [9982003] = { n = nm("暗岔"), lv = 10, prev = { 9982001 } },
  }, {})
  H.eq(ns.Filter.step(9982001), nil, "只由一邊宣告的分岔起點不加")
  H.eq(ns.Filter.step(9982002), nil, "只由一邊宣告的分岔分支不加")
  H.eq(ns.Filter.step(9982003), nil, "只由一邊宣告的分岔另一分支不加")
end

-- ===== 1. 金錢 =====
local function detailText(cu, xp, ri)
  local ns = setup()
  local rq = ns.Data.quest
  ns.Data.quest = function(id) local q = rq(id); if id == 9900001 and q then q.cu, q.xp, q.ri = cu, xp, ri end return q end
  ns.Data.desc = function() return nil end
  ns.Detail.Open(9900001)
  return table.concat(ns.Detail.Lines(), "\n")
end
do
  local s = detailText(nil, 450, {})
  H.check(not s:find("金錢", 1, true), "cu nil 不顯示金錢列")
  H.check(s:find("你還會得到", 1, true) and s:find("經驗值：450", 1, true), "cu nil 仍顯示經驗值")
  s = detailText(0, 450, {})
  H.check(not s:find("金錢", 1, true), "cu 0 不顯示金錢列")
  s = detailText(1200, 450, {})
  H.check(s:find("12|TInterface\\MoneyFrame\\UI-SilverIcon", 1, true) ~= nil, "cu > 0 顯示")
  s = detailText(nil, 0, { { 6087, 1, false } })
  H.check(s:find("獎勵", 1, true) and not s:find("你還會得到", 1, true), "底下沒有任何列時「你還會得到」標題不出現")
  s = detailText(nil, nil, {})
  H.check(s:find("經驗值：資料未收錄", 1, true) and s:find("你還會得到", 1, true), "xp 未知照舊顯示資料未收錄")
  s = detailText(nil, 0, {})
  H.check(not s:find("獎勵", 1, true), "cu nil、xp 0、ri 空：整段省略")
end

-- ===== 3. 物品一欄 =====
do
  local ns, _, cache = setup()
  local rq = ns.Data.quest
  local names = { "短", "一個名字相當長的物品名稱用來測試完整顯示", "丙", "丁" }
  for i, n in ipairs(names) do cache[6000 + i] = n end
  ns.Data.quest = function(id) local q = rq(id); if id == 9900001 and q then q.ri, q.cu, q.xp = { { 6001, 1, true }, { 6002, 1, true }, { 6003, 1, false }, { 6004, 2, false } }, 0, 0 end return q end
  ns.Data.desc = function() return nil end
  ns.Detail.Open(9900001)
  local bs = {}
  for _, f in ipairs(H.frames) do if f.itemBtn and f._shown then bs[#bs + 1] = f end end
  H.eq(#bs, 4, "4 個按鈕都顯示")
  local ys = {}
  for _, b in ipairs(bs) do
    H.eq(b._pt[4], 12, "物品按鈕靠左一欄（x=PAD）")
    H.eq(b._width, 360 - 24, "物品按鈕寬度＝明細內容寬")
    H.check(not ys[b._pt[5]], "每列一個按鈕（y 不重複）")
    ys[b._pt[5]] = true
    H.eq(b.nameFs._width, 360 - 24 - 37 - 8, "名稱欄位寬度＝內容寬扣圖示")
  end
end

-- ===== 4. 低等任務篩選 =====
do
  local LOW = {
    [9980001] = { n = nm("低等"), lv = 10, min = 1 },
    [9980002] = { n = nm("同級"), lv = 58, min = 1 },
    [9980003] = { n = nm("高等"), lv = 70, min = 1 },
  }
  local ns = setup({ level = 60 })
  fake(ns, LOW, { 9980001, 9980002, 9980003 })
  -- 只隱藏「未接」的灰色任務：進行中與已完成的灰色任務照常顯示
  do
    local st, realOf = {}, ns.Status.of
    ns.Status.of = function(id) return st[id] or "open" end
    ns.Panel.Refresh(1429)
    H.eq(#ns.Panel.Rows(), 2, "灰色未接隱藏")
    st[9980001] = "log"
    ns.Panel.Refresh(1429)
    ns.Panel.SetTab("log")
    H.eq(#ns.Panel.Rows(), 1, "灰色進行中任務在日誌中分頁可見（篩選關閉）")
    H.eq(ns.Panel.Counts().log, 1, "日誌計數含灰色進行中")
    ns.Panel.SetTab("all")
    H.eq(#ns.Panel.Rows(), 3, "全部分頁含灰色進行中")
    H.eq(ns.Panel.Counts().all, 3, "全部計數一致")
    ns.Panel.SetTab("open")
    H.eq(#ns.Panel.Rows(), 2, "未接分頁仍不含灰色")
    st[9980001] = "done"
    ns.Panel.Refresh(1429)
    ns.Panel.SetTab("done")
    H.eq(#ns.Panel.Rows(), 1, "灰色已完成任務在已完成分頁可見")
    H.eq(ns.Panel.Counts().done, 1, "已完成計數含灰色")
    ns.Panel.SetTab("open")
    ns.Panel.SetSearch("低等")
    ns.Panel.SetTab("done")
    H.eq(#ns.Panel.Rows(), 1, "搜尋：灰色已完成任務可見")
    ns.Panel.SetTab("open")
    H.eq(#ns.Panel.Rows(), 0, "搜尋：灰色未接仍隱藏")
    ns.Panel.SetSearch("")
    st[9980001] = nil
    ns.Status.of = realOf
    ns.Panel.Refresh(1429)
  end
  H.eq(ns.Filter.get("showLow"), false, "showLow 預設不勾")
  ns.Panel.Refresh(1429)
  local c = ns.Panel.Counts()
  H.eq(#ns.Panel.Rows(), 2, "預設隱藏灰色任務")
  H.eq(c.all, 2, "全部計數不含灰色"); H.eq(c.openAll, 2, "未接計數不含灰色")
  H.check(ns.Panel.TabText("open"):find("%(2%)") ~= nil, "分頁數字一致")
  ns.Panel.SetSearch("低等")
  H.eq(#ns.Panel.Rows(), 0, "搜尋也隱藏灰色任務")
  ns.Panel.SetSearch("")
  ns.Panel.SetCheck("showLow", true)
  H.eq(#ns.Panel.Rows(), 3, "勾選後灰色任務出現")
  H.eq(ns.Panel.Counts().all, 3, "勾選後全部計數 3")
  H.eq(ns.Panel.Rows()[1].questId, 9980001, "排序仍純照等級（灰色在最前）")
  ns.Panel.SetSearch("低等")
  H.eq(#ns.Panel.Rows(), 1, "勾選後搜尋命中灰色任務")
  H.eq(QuestMapGuideCharDB.filter.showLow, true, "存在角色存檔")
  -- 使用 GetQuestDifficultyColor 的灰色判定
  ns = setup({ level = 60 })
  _G.GetQuestDifficultyColor = function(lv) if lv < 50 then return { r = 0.5, g = 0.5, b = 0.5 } end return { r = 1, g = 1, b = 0 } end
  H.installed.GetQuestDifficultyColor = true
  fake(ns, LOW, { 9980001, 9980002, 9980003 })
  ns.Panel.Refresh(1429)
  H.eq(#ns.Panel.Rows(), 2, "遊戲難度色為灰時隱藏")
  _G.GetQuestDifficultyColor = nil; H.installed.GetQuestDifficultyColor = nil
end

-- ===== 5. 頁首計數 =====
do
  local ns = setup()
  ns.Panel.Refresh(1429)
  for _, tab in ipairs({ "open", "log", "done", "all" }) do
    ns.Panel.SetTab(tab)
    local n = ns.Panel.TabText(tab):match("%((%d+)%)")
    H.eq(ns.Panel.Header(), ns.L("tab" .. tab:sub(1, 1):upper() .. tab:sub(2)) .. " " .. n .. " 筆", "頁首與分頁一致：" .. tab)
  end
  ns.Panel.SetTab("open")
  H.check(ns.Panel.Header():find("^未接 %d+ 筆$") ~= nil, "格式「未接 N 筆」")
  ns.Panel.SetSearch("測試")
  H.check(ns.Panel.Header():find("^搜尋結果 %d+ 筆") ~= nil, "搜尋時維持搜尋結果筆數")
  local ne = setup({ locale = "enUS" })
  ne.Panel.Refresh(1429)
  H.check(ne.Panel.Header():find("^Open: %d+$") ~= nil, "英文頁首格式")
end

-- ===== 6. 羊皮紙底 =====
local function near(a, b) return math.abs(a - b) < 0.02 end
do
  local ns, _, cache = setup()
  ns.Data.desc = function() return "描述" end
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900002)   -- 有前置連結
  local d = ns.Detail
  H.check(type(d.parchment) == "table" and tostring(d.parchment._tex):find("QuestFrame", 1, true) ~= nil, "明細背景設了任務視窗羊皮紙材質")
  H.check(type(d.parchment._texcoord) == "table", "羊皮紙材質有裁切座標")
  H.check(type(d.underlay) == "table" and d.underlay._ct ~= nil, "材質下有底色當退路")
  local function btnOf(text)
    for _, f in ipairs(H.frames) do if f.fs and f._shown and f.fs:GetText() and f.fs:GetText():find(text, 1, true) then return f end end
  end
  local txt = btnOf("狀態")
  local c = txt.fs._tc
  H.check(near(c[1], 0.18) and near(c[2], 0.12) and near(c[3], 0.06), "一般文字深褐")
  local link = btnOf("測試任務一")
  c = link.fs._tc
  H.check(link.quest ~= nil and near(c[1], 0.043) and near(c[2], 0.184) and near(c[3], 0.541), "連結深藍 0b2f8a")
  local head = btnOf("起點")
  H.check(head.fs._tc[1] < 0.5 and head.fs._tc[2] < 0.35, "分段標題深色")
  H.check(d.backButton.fs._tc ~= nil and d.backButton.fs._tc[1] < 0.5, "回清單文字深色")
  -- 等級色加深
  local title = btnOf("Only English Name")
  H.check(title.fs._tc[1] < 0.8 and title.fs._tc[2] < 0.8, "標題等級色加深")
  -- 品質色
  local rq = ns.Data.quest
  ns.Data.quest = function(id) local q = rq(id); if id == 9900001 and q then q.ri, q.cu, q.xp = { { 6001, 1, false } }, 0, 0 end return q end
  cache[6001] = "綠裝"; cache.q = 2
  _G.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }; H.installed.ITEM_QUALITY_COLORS = true
  d.Open(9900001)
  local ib
  for _, f in ipairs(H.frames) do if f.itemBtn and f._shown then ib = f end end
  H.check(ib.nameFs._tc[2] < 0.7, "綠色物品名稱在羊皮紙上加深")
end

-- ===== 7. 已完成列 =====
do
  local ns = setup()
  ns.Panel.SetCheck("showDone", true)
  ns.Status.of = function(id) return id == 9900001 and "done" or "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetTab("all")
  local _, b = titleOf(ns, 9900001)
  H.check(b ~= nil, "找到已完成列")
  local tc = b.title._tc
  H.check(near(tc[1], ns.Theme.MUTED[1]) and near(tc[2], ns.Theme.MUTED[2]) and near(tc[3], ns.Theme.MUTED[3]), "已完成名稱用灰色資訊色（羊皮紙底）")
  H.eq(b.sub:GetText(), "已完成", "已完成副標")
  ns = setup({ locale = "enUS" })
  ns.Panel.SetCheck("showDone", true)
  ns.Status.of = function(id) return id == 9900001 and "done" or "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetTab("all")
  _, b = titleOf(ns, 9900001)
  H.eq(b.sub:GetText(), "Completed", "已完成副標 enUS")
  -- 搜尋帶出的別張地圖已完成任務：副標「已完成 · 地圖名」
  ns = setup()
  ns.Status.of = function(id) return id == 9900002 and "done" or "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetSearch("Only English")
  ns.Panel.SetTab("done")
  _, b = titleOf(ns, 9900002)
  H.check(b ~= nil and b.sub:GetText():find("^已完成 · ") ~= nil and #b.sub:GetText() > #"已完成 · ", "別張地圖已完成：副標含已完成與地圖名")
  -- 非完成列不是灰色
  ns = setup()
  ns.Panel.Refresh(1429)
  _, b = titleOf(ns, 9900001)
  H.check(b.sub:GetText() ~= "已完成", "未完成列副標不是已完成")
end

-- ===== Locale 兩語系都有新字串 =====
for _, loc in ipairs({ "zhTW", "enUS" }) do
  local ns = setup({ locale = loc })
  H.check(ns.L("showLow") ~= "showLow", loc .. " showLow")
  H.check(ns.L("headerTab") ~= "headerTab", loc .. " headerTab")
end
H.eq(setup().L("showLow"), "顯示低等任務", "showLow zh")
H.eq(setup({ locale = "enUS" }).L("showLow"), "Show low-level quests", "showLow en")
