-- Task 5f：清單羊皮紙、共用配色、副標補齊
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id)
    return { mapID = id, mapType = 3, name = (not opts.noMapName) and ("地圖" .. id) or nil }
  end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  return ns
end
local function near(a, b) return math.abs(a - b) < 0.02 end
local function rowOf(id)
  for _, f in ipairs(H.frames) do
    if f.title and f.questId == id and f._shown then return f end
  end
end
-- 用假任務表（API 層替身）
local function fake(ns, list)
  ns.Data.quest = function(id)
    local q = list[id]; if not q then return nil end
    local c = {}; for k, v in pairs(q) do c[k] = v end
    return c
  end
  local ids = {}
  for id in pairs(list) do ids[#ids + 1] = id end
  table.sort(ids)
  ns.Data.byMap = function() return ids end
  ns.Data.questIds = function() return ids end
end
local function nm(s) return { zh = s, en = s } end

-- ===== 副標 =====
do
  local ns = setup()
  fake(ns, {
    [9950001] = { n = nm("別圖"), lv = 10, s = { "o9901001" }, prev = {}, next = {} },   -- 起點只在 1453
    [9950002] = { n = nm("無資料"), lv = 11, prev = {}, next = {} },
    [9950003] = { n = nm("查無實體"), lv = 12, s = { "n9999999" }, prev = {}, next = {} },
    [9950004] = { n = nm("有座標"), lv = 13, s = { "n9901001" }, prev = {}, next = {} },
  })
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9950001).sub:GetText(), "起點：地圖1453", "起點在別張地圖：起點：地圖名")
  H.eq(rowOf(9950002).sub:GetText(), "起點未收錄", "沒有起點資料：起點未收錄")
  H.eq(rowOf(9950003).sub:GetText(), "起點未收錄", "起點實體查無：起點未收錄")
  H.check(rowOf(9950004).sub:GetText():find("(45.3, 60.1)", 1, true) ~= nil, "有座標：NPC · 地圖名(x, y)")
  -- 既有規則優先
  ns.Filter.dim = function(id) if id == 9950001 then return { kind = "prereq", name = "前置甲" } end end
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9950001).sub:GetText(), ns.L("needPrereq"):format("前置甲"), "淡化列：需先完成優先")
  ns.Filter.dim = function() return nil end
  ns.Status.of = function(id) return id == 9950002 and "done" or "open" end
  ns.Panel.SetCheck("showDone", true)
  ns.Panel.SetTab("done")
  H.eq(rowOf(9950002).sub:GetText(), "已完成", "已完成列：已完成優先")
  -- 搜尋列：不在這張地圖且有地圖名，維持原規則
  ns.Panel.SetTab("open")
  ns.Panel.SetSearch("別圖")
  H.check(rowOf(9950001) ~= nil and rowOf(9950001).sub:GetText() ~= "", "搜尋列副標不為空")
end
do
  local ns = setup({ noMapName = true })
  fake(ns, { [9950001] = { n = nm("別圖"), lv = 10, s = { "o9901001" }, prev = {}, next = {} } })
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9950001).sub:GetText(), "起點未收錄", "取不到地圖名：落到起點未收錄")
end
do
  local ns = setup({ locale = "enUS" })
  fake(ns, {
    [9950001] = { n = nm("A"), lv = 10, s = { "o9901001" }, prev = {}, next = {} },
    [9950002] = { n = nm("B"), lv = 11, prev = {}, next = {} },
  })
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9950001).sub:GetText(), "Starts: 地圖1453", "enUS 起點：")
  H.eq(rowOf(9950002).sub:GetText(), "Start unknown", "enUS 起點未收錄")
end

-- ===== 羊皮紙與共用配色 =====
do
  local ns = setup()
  H.check(type(ns.Theme) == "table", "有共用 ns.Theme")
  local T = ns.Theme
  local p = ns.Panel
  H.check(type(p.parchment) == "table" and tostring(p.parchment._tex):find("QuestFrame", 1, true) ~= nil, "清單面板設了羊皮紙材質")
  H.check(type(p.parchment._texcoord) == "table", "羊皮紙有裁切座標")
  H.check(type(p.underlay) == "table" and p.underlay._ct ~= nil, "清單面板底色退路")
  H.eq(p.parchment._layer, "BACKGROUND", "羊皮紙在 BACKGROUND")
  H.eq(p.parchment._sub, 1, "羊皮紙 sublevel 1")
  H.eq(p.underlay._sub, 0, "底色 sublevel 0")
  for i = 1, 4 do H.eq(p.parchment._texcoord[i], T.TEXCOORD[i], "羊皮紙裁切座標與 Theme 相同 " .. i) end
  H.eq(p.underlay._ct[1], T.UNDER[1], "底色來自 Theme")
  -- 明細與清單同一組材質／底色
  ns.Data.desc = function() return "描述" end
  ns.Panel.Select(9900001)
  H.eq(ns.Detail.parchment._tex, p.parchment._tex, "清單與明細同一張材質")
  H.eq(ns.Detail.underlay._ct[2], p.underlay._ct[2], "清單與明細同一底色")
  -- 圖示顏色
  fake(ns, { [9950001] = { n = nm("甲"), lv = 10, prev = {}, next = {} }, [9950002] = { n = nm("乙"), lv = 11, prev = {}, next = {} } })
  ns.Status.of = function(id) return id == 9950002 and "log" or "open" end
  ns.Panel.Refresh(1429)
  ns.Panel.SetTab("all")
  H.eq(rowOf(9950001).icon:GetText(), "", "可接列不用文字「!」")
  H.check(rowOf(9950001).avail._shown, "可接列用「!」材質")
  H.check(not rowOf(9950002).avail._shown, "進行中列不顯示「!」材質")
  H.eq(rowOf(9950002).icon:GetText(), "|cff0b2f8a?|r", "「?」深藍 0b2f8a")
  -- 清單列文字色與 Detail 用同一個 Theme.darken
  local r, g, b = T.levelInk(ns.Filter.color(9950001, ns.Data.quest(9950001)))
  local tc = rowOf(9950001).title._tc
  H.check(near(tc[1], r) and near(tc[2], g) and near(tc[3], b), "列標題用加深後的等級色")
  local sc = rowOf(9950001).sub._tc
  H.check(sc and near(sc[1], T.MUTED[1]) and near(sc[2], T.MUTED[2]), "副標用灰色資訊色")
  local d1 = { T.darken(1, 0.5, 0) }
  H.check(near(d1[1], 0.6) and near(d1[2], 0.3) and near(d1[3], 0), "等級色乘 0.6")
  local w = { T.darken(1, 1, 1) }
  H.check(near(w[1], T.INK[1]) and near(w[2], T.INK[2]), "白色改用一般文字色")
  -- Panel 與 Detail 沒有各自一份配色
  H.eq(ns.Detail.Theme, nil, "Detail 沒有自己的配色表")
  -- 頁首、頁尾、分頁
  H.check(near(p.footer._tc[1], T.MUTED[1]), "頁尾灰色資訊色")
  local cur = p.TabColor(p.Tab())
  H.check(cur[1] > 0.9 and cur[2] > 0.9, "目前分頁淺字（底是深紅，0.0.4）")
  local other = p.TabColor(p.Tab() == "log" and "open" or "log")
  H.check(other[1] < 0.5 and other[2] < 0.5, "其他分頁深色")
  -- 淡化列
  ns.Filter.dim = function(id) if id == 9950001 then return { kind = "prereq", name = "x" } end end
  ns.Panel.Refresh(1429)
  H.check(near(rowOf(9950001):GetAlpha(), 0.70), "淡化列透明度 0.70")
  H.check(near(rowOf(9950002):GetAlpha(), 1), "一般列不透明")
end

-- ===== 羊皮紙色盤（難度色、品質色、勾勾、提示字）=====
do
  local ns = setup()
  local T = ns.Theme
  local function is(a, b, c, e, msg)
    local r, g, bb = T.levelInk(a, b, c)
    H.check(near(r, e[1]) and near(g, e[2]) and near(bb, e[3]), msg)
  end
  is(0.5, 0.5, 0.5, { 0.286, 0.275, 0.251 }, "灰色難度 494640")
  is(0.25, 0.75, 0.25, { 0.071, 0.322, 0.071 }, "綠色難度 125212")
  is(1, 1, 0, { 0.349, 0.255, 0.00 }, "黃色難度 594100")
  is(1, 0.5, 0.25, { 0.459, 0.196, 0.00 }, "橙色難度 753200")
  is(1, 0.1, 0.1, { 0.557, 0.039, 0.039 }, "紅色難度 8e0a0a")
  local r, g, b = T.levelInk(0.3, 0.2, 0.9)
  H.check(near(r, 0.18) and near(g, 0.12) and near(b, 0.54), "分類不了：退回 darken")
  local function q(a, b2, c, e, msg)
    local x, y, z = T.qualityInk(a, b2, c)
    H.check(near(x, e[1]) and near(y, e[2]) and near(z, e[3]), msg)
  end
  q(1, 1, 1, T.INK, "普通品質=一般文字色")
  q(0.62, 0.62, 0.62, { 0.40, 0.38, 0.35 }, "粗糙品質")
  q(0.12, 1, 0, { 0.071, 0.322, 0.071 }, "優秀品質 125212")
  q(0, 0.44, 0.87, { 0.05, 0.30, 0.65 }, "精良品質")
  q(0.64, 0.21, 0.93, { 0.45, 0.15, 0.60 }, "史詩品質")
  -- 勾勾與提示字
  local ck
  for _, f in ipairs(H.frames) do if f._kind == "Button" and f.check then ck = f.check break end end
  H.check(ck and ck._vc and near(ck._vc[1], 0.41) and near(ck._vc[2], 0.28) and near(ck._vc[3], 0), "完成勾勾頂點色 (.41,.28,0)：金色材質乘出 693b00")
  H.check(near(T.HINT[1], 0.70) and near(T.HINT[3], 0.70), "提示字淺灰")
  local hint = ns.Panel.searchHint
  H.check(hint ~= nil and hint._tc and near(hint._tc[1], 0.70) and near(hint._tc[3], 0.70), "搜尋提示字用淺灰")
end
