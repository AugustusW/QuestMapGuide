-- 大地圖右側面板：清單、語系名稱、空狀態、換地圖更新（資料用 fixture，不用正式 Data）
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local mapId, mapType = opts.map or 1429, opts.mapType or 3
  local wm = H.widget("Frame")
  local hooks = {}
  wm.GetMapID = function() return mapId end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = mapType } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  return ns, wm, function(id, t) mapId = id; if t then mapType = t end; wm.OnMapChanged(wm) end
end

local function ids(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.questId end return t end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- 面板在 ADDON_LOADED 建立，掛在 WorldMapFrame 右側
local ns, wm, change = setup()
H.eq(type(ns.Panel), "table", "Panel 存在")
H.check(ns.Panel.frame ~= nil, "面板 frame 在 ADDON_LOADED 就建立")
local n0 = #H.frames
change(1429)
H.eq(#H.frames, n0, "換地圖不建立新 frame")

-- rows list quests of the shown map
ns.Panel.Refresh(1429)
H.check(same(ids(ns.Panel.Rows()), ns.Data.byMap(1429)), "rows list quests of the shown map")
local r = ns.Panel.Rows()[1]
H.eq(r.name, "測試任務一", "zhTW 用中文名")
H.eq(r.npc, "測試NPC", "起點 NPC（zhTW 內建繁中名稱）")
H.eq(r.x, 45.3, "座標 x 取該地圖第一個 spawn")
H.eq(r.y, 60.1, "座標 y")

-- 起點取「這張地圖」的 spawn，不是第一個 spawn
ns.Panel.Refresh(1453)
r = ns.Panel.Rows()[1]
H.eq(r.x, 12, "1453 取該圖的 spawn x")
H.eq(r.y, 80, "1453 取該圖的 spawn y")

-- zhTW falls back to english name
r = ns.Panel.Rows()[2]
H.eq(r.questId, 9900002, "第二筆是只有英文名的任務")
H.eq(r.name, "Only English Name", "zhTW falls back to english name")
H.eq(r.npc, "Fixture Object", "object 起點也能顯示")

-- 英文語系用 en；缺 en 時退回 zh
ns = setup({ locale = "enUS" })
ns.Panel.Refresh(1429)
H.eq(ns.Panel.Rows()[1].name, "Test Quest One", "enUS 用英文名")
-- 資料是唯讀的打包字串；改資料要在 API 層替身
local realQuest = ns.Data.quest
ns.Data.quest = function(id)
  local q = realQuest(id)
  if id == 9900001 then q.n.en = nil end
  return q
end
ns.Panel.Refresh(1429)
H.eq(ns.Panel.Rows()[1].name, "測試任務一", "enUS 缺英文名退回中文")

-- 沒有起點資料（s 為 nil 或空）的任務：只有名稱
ns = setup()
ns.Data.byMap = function() return { 9900001, 9900003, 9900004 } end
ns.Panel.Refresh(1429)
local rows = ns.Panel.Rows()
-- 依等級排序：9900003（lv1）、9900004（lv3）、9900001（lv7）
H.eq(rows[1].npc, nil, "s={} 沒有 NPC")
H.eq(rows[2].npc, nil, "s=nil 沒有 NPC")
H.eq(rows[2].name, "Unknown Everything", "只有英文名")

-- empty zone shows empty text
ns = setup({ map = 1500 })
ns.Panel.Refresh(1500)
H.eq(#ns.Panel.Rows(), 0, "empty zone has no rows")
H.eq(ns.Panel.Message(), "這張地圖沒有收錄的任務", "empty zone shows empty text")
ns = setup({ map = 1500, locale = "enUS" })
ns.Panel.Refresh(1500)
H.eq(ns.Panel.Message(), "No quests recorded for this map", "empty zone text en")

-- continent shows zoom hint
ns = setup({ map = 1414, mapType = 2 })
ns.Panel.Refresh(1414)
H.eq(#ns.Panel.Rows(), 0, "continent has no rows")
H.eq(ns.Panel.Message(), "放大到區域地圖查看任務", "continent shows zoom hint")
ns = setup({ map = 1414, mapType = 2, locale = "enUS" })
ns.Panel.Refresh(1414)
H.eq(ns.Panel.Message(), "Zoom in to a zone map to see quests", "zoom hint en")
-- 大陸地圖即使 ByMap 有資料也不列
ns = setup({ map = 1429, mapType = 2 })
ns.Panel.Refresh(1429)
H.eq(#ns.Panel.Rows(), 0, "非區域地圖不列任務")

-- GetMapInfo 回 nil 不爆
ns = setup()
_G.C_Map.GetMapInfo = function() return nil end
ns.Panel.Refresh(1429)
H.eq(#ns.Panel.Rows(), 0, "GetMapInfo 為 nil 時不列")
H.eq(ns.Panel.Message(), "放大到區域地圖查看任務", "GetMapInfo 為 nil 顯示放大提示")

-- footer
ns = setup()
H.eq(ns.L("panelFooter"), "資料：Blizzard、CMaNGOS；以遊戲為準", "頁尾 zhTW（縮短到一行放得下，完整來源見 NOTICE）")
ns = setup({ locale = "enUS" })
H.eq(ns.L("panelFooter"), "Data: Blizzard, CMaNGOS; the game is authoritative", "頁尾 enUS")

-- map change refreshes（走 hooksecurefunc 的 OnMapChanged）
ns, wm, change = setup({ map = 1429 })
ns.Panel.Refresh(1429)
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "起始 1429 一筆")
change(1453)
H.check(same(ids(ns.Panel.Rows()), { 9900001, 9900002 }), "map change refreshes")
change(1500)
H.eq(#ns.Panel.Rows(), 0, "換到空地圖後清單清空")
change(1414, 2)
H.eq(ns.Panel.Message(), "放大到區域地圖查看任務", "換到大陸顯示提示")

-- 面板跟著 WorldMapFrame：父框架是 WorldMapFrame
ns, wm = setup()
H.check(ns.Panel.frame._parent == wm, "面板是 WorldMapFrame 的子框架")

-- Select：沒有 Pins 不報錯；有 Pins 就呼叫
ns = setup()
ns.Panel.Select(9900001)
local shown
ns.Pins = { Show = function(q) shown = q end }
ns.Panel.Select(9900001)
H.eq(shown, 9900001, "Select 呼叫 ns.Pins.Show")

-- 超過一頁：捲動位移，列表仍是全部任務（Rows 回傳全部）
ns = setup()
local many = {}
for i = 1, 60 do many[i] = 9900001 end
local realByMap = ns.Data.byMap
ns.Data.byMap = function(m) if m == 1429 then return many end return realByMap(m) end
ns.Panel.Refresh(1429)
H.eq(#ns.Panel.Rows(), 60, "Rows 回傳全部")

-- OnMapChanged 不存在：載入不報錯，地圖切換靠 OnUpdate 輪詢仍會更新
H.reset()
dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
local wm2 = _G.WorldMapFrame
wm2.OnMapChanged = nil
local ns2 = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.check(pcall(H.fire, "ADDON_LOADED", "QuestMapGuide"), "沒有 OnMapChanged 時載入不報錯")
local upd = ns2.Panel.frame._scripts.OnUpdate
H.eq(type(upd), "function", "退而求其次用 OnUpdate 輪詢")
H.mapId = 1453
upd(ns2.Panel.frame, 0.05)
H.eq(#ns2.Panel.Rows(), 1, "未滿 0.2 秒不更新（仍是 1429 的一筆）")
upd(ns2.Panel.frame, 0.2)
H.check(same(ids(ns2.Panel.Rows()), { 9900001, 9900002 }), "輪詢偵測到換地圖並更新")
H.mapId = 1500
upd(ns2.Panel.frame, 0.3)
H.eq(#ns2.Panel.Rows(), 0, "再換地圖再更新")

-- hooksecurefunc 對不存在的函式要報錯（跟遊戲一致）
H.reset()
H.check(not pcall(hooksecurefunc, {}, "Nope", function() end), "harness hooksecurefunc 對 nil 函式報錯")

-- 列重用與捲動
ns = setup()
local sixty = {}
for i = 1, 60 do sixty[i] = 9900001 end
local realByMap = ns.Data.byMap
ns.Data.byMap = function(m) if m == 1429 then return sixty end return realByMap(m) end
ns.Panel.Refresh(1429)
local btns = {}
for _, f in ipairs(H.frames) do if f._kind == "Button" and f.sub then btns[#btns + 1] = f end end
H.eq(#btns, 12, "建立 12 個列按鈕（上限）")
H.eq(ns.Panel.VisibleRows(), 11, "預設高度 600 放得下 11 列（頁尾不壓到列）")
H.check(btns[11]:IsShown(), "60 筆時最後一個可見列顯示")
H.check(not btns[12]:IsShown(), "放不下的第 12 列隱藏")
local wheel = ns.Panel.frame._scripts.OnMouseWheel
wheel(ns.Panel.frame, -1)
H.eq(btns[1].questId, 9900001, "捲動後仍有內容")
-- 捲到底：位移不超過 #rows - 12
for _ = 1, 100 do wheel(ns.Panel.frame, -1) end
H.eq(ns.Panel.Offset(), 49, "往下捲夾在 #rows - 可見列數")
for _ = 1, 100 do wheel(ns.Panel.frame, 1) end
H.eq(ns.Panel.Offset(), 0, "往上捲夾在 0")
for _ = 1, 5 do wheel(ns.Panel.frame, -1) end
H.eq(ns.Panel.Offset(), 15, "一格滾輪 3 列")

-- 頁尾不壓到列：單行不換行，最後一個可見列的底緣在頁尾頂緣之上（預設高度與其他高度）
do
  local f = ns.Panel.frame
  H.eq(ns.Panel.footer._wrap, false, "頁尾單行（不換行）")
  local fp = ns.Panel.footer._pt
  local margin = fp[5]                       -- BOTTOMLEFT 的 y 位移＝頁尾底緣距面板底
  local function check(h, label)
    f:SetHeight(h)
    f._scripts.OnSizeChanged(f, 300, h)
    local n = ns.Panel.VisibleRows()
    local last = btns[n]
    H.check(last:IsShown(), label .. " 最後一個可見列顯示")
    if btns[n + 1] then H.check(not btns[n + 1]:IsShown(), label .. " 放不下的列隱藏") end
    local lastBottom = -last._pt[5] + 36      -- 距面板頂的底緣
    local footerTop = h - margin - 14         -- 單行高（GetStringHeight 模擬 14）
    H.check(lastBottom <= footerTop, label .. " 最後列底緣 " .. lastBottom .. " 在頁尾頂緣 " .. footerTop .. " 之上")
  end
  check(600, "高度 600")
  check(520, "高度 520")
  check(700, "高度 700")
  H.eq(ns.Panel.VisibleRows(), 12, "高度 700 用滿 12 列上限")
  f:SetHeight(0); f._scripts.OnSizeChanged(f, 300, 0)
  H.eq(ns.Panel.VisibleRows(), 11, "取不到高度時用預設 600")
  for _ = 1, 100 do wheel(f, 1) end
end
-- 切到 2 筆的地圖：位移歸零、第 3 列起隱藏
ns.Panel.Refresh(1453)
H.eq(ns.Panel.Offset(), 0, "Refresh 後位移歸 0")
H.check(btns[1]:IsShown() and btns[2]:IsShown(), "前兩列顯示")
local hidden = true
for i = 3, 12 do if btns[i]:IsShown() then hidden = false end end
H.check(hidden, "60 筆換 2 筆後第 3 列起全部隱藏")
H.eq(btns[3].questId, nil, "隱藏列清掉 questId")
-- 筆數少於一頁時滾輪不位移
wheel(ns.Panel.frame, -1)
H.eq(ns.Panel.Offset(), 0, "不足一頁時滾輪不位移")

-- 清單依等級排序：低到高、nil 最後；同等級依名稱，再依 questId
do
  ns = setup()
  local lvs = { [9910001] = 12, [9910002] = false, [9910003] = 5, [9910004] = 5, [9910005] = 5 }
  local names = { [9910001] = "M", [9910002] = "A", [9910003] = "Zeta", [9910004] = "Alpha", [9910005] = "Alpha" }
  ns.Data.quest = function(id)
    return { n = { en = names[id] }, lv = lvs[id] or nil, min = 1 }
  end
  ns.Data.byMap = function() return { 9910001, 9910002, 9910003, 9910004, 9910005 } end
  ns.Filter.set("tab", "all")
  ns.Panel.Refresh(1429)
  H.check(same(ids(ns.Panel.Rows()), { 9910004, 9910005, 9910003, 9910001, 9910002 }), "rows sorted by level")

  -- 搜尋命中 250 筆：排序後截 200，留下的是等級最低的 200 筆
  local fake = {}
  for i = 1, 250 do fake[i] = 8000000 + i end
  ns.Data.questIds = function() return fake end
  ns.Data.quest = function(id)
    if id >= 8000000 then return { n = { en = "Bulk " .. id }, lv = 251 - (id - 8000000), min = 1 } end
    return nil
  end
  ns.Panel.InvalidateIndex()
  ns.Panel.SetSearch("bulk")
  local rs = ns.Panel.Rows()
  H.eq(#rs, 200, "搜尋 250 筆只列 200")
  H.eq(ns.Panel.Capped(), true, "標記截斷")
  H.eq(rs[1].lv, 1, "第一筆是最低等級")
  H.eq(rs[200].lv, 200, "最後一筆是第 200 低的等級（等級 201–250 被截掉）")

  -- 截斷前不建完整項目：只對留下的 200 筆建（Filter.dim 每建一筆項目呼叫一次）
  local dimCalls, origDim = 0, ns.Filter.dim
  ns.Filter.dim = function(...) dimCalls = dimCalls + 1; return origDim(...) end
  ns.Panel.SetSearch("bulkx")
  ns.Panel.SetSearch("bulk")
  ns.Filter.dim = origDim
  H.check(dimCalls <= 200, "搜尋 250 筆只建 200 筆項目（實際 " .. dimCalls .. "）")
  rs = ns.Panel.Rows()
  H.eq(rs[1].lv, 1, "延後建項目後第一筆仍是最低等級")
  H.eq(rs[200].lv, 200, "延後建項目後最後一筆仍是第 200 低")
  H.eq(rs[1].offMap, true, "留下的項目照常建好（offMap）")
end

-- 列單行不折行；OnEnter tooltip 顯示完整標題與副標
do
  ns = setup()
  local tip = { lines = {} }
  tip.SetOwner = function(self, owner) self.owner = owner end
  tip.AddLine = function(self, t) self.lines[#self.lines + 1] = t end
  tip.Show = function(self) self.shown = true end
  tip.Hide = function(self) self.shown = false; self.lines = {} end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  ns.Panel.Refresh(1429)
  local bs = {}
  for _, f in ipairs(H.frames) do if f._kind == "Button" and f.sub then bs[#bs + 1] = f end end
  H.eq(bs[1].title._wrap, false, "列 title 不折行")
  H.eq(bs[1].sub._wrap, false, "列 sub 不折行")
  bs[1]._scripts.OnEnter(bs[1])
  H.eq(tip.owner, bs[1], "tooltip 掛在列上")
  H.eq(tip.lines[1], "[7] 測試任務一", "tooltip 含完整標題")
  H.eq(tip.lines[2], "測試NPC (45.3, 60.1)", "tooltip 含副標（NPC (x, y)，這組測試的地圖沒有名稱）")
  H.eq(tip.shown, true, "tooltip 顯示")
  bs[1]._scripts.OnLeave(bs[1])
  H.eq(tip.shown, false, "離開隱藏 tooltip")
  bs[12]._scripts.OnEnter(bs[12])
  H.eq(#tip.lines, 0, "空列不顯示 tooltip 內容")
end

-- 任務類型標示：名稱後面加 (類型)；排序與搜尋不受影響
do
  local function typed(opts, tmap)
    local n = setup(opts)
    local prev = n.Data.quest
    n.Data.quest = function(id)
      local q = prev(id)
      if q and tmap and tmap[id] ~= nil then q.t = tmap[id] end
      if q and tmap and tmap[id] == "nil" then q.t = nil end
      return q
    end
    return n
  end
  local function rowBtn(i)
    local bs = {}
    for _, f in ipairs(H.frames) do if f._kind == "Button" and f.sub then bs[#bs + 1] = f end end
    return bs[i]
  end
  local n = typed(nil, { [9900001] = 81 })
  n.Panel.Refresh(1429)
  H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一 (地下城)", "t=81 標題加 (地下城)")
  H.eq(n.Panel.Rows()[1].name, "測試任務一", "排序用的 name 不含類型")
  local tip = { lines = {} }
  tip.SetOwner = function() end
  tip.AddLine = function(self, t) self.lines[#self.lines + 1] = t end
  tip.Show = function() end
  tip.Hide = function() end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  rowBtn(1)._scripts.OnEnter(rowBtn(1))
  H.eq(tip.lines[1], "[7] 測試任務一 (地下城)", "tooltip 全文含類型")
  for t, label in pairs({ [1] = "精英", [62] = "團隊", [41] = "PvP", [83] = "傳說" }) do
    n = typed(nil, { [9900001] = t }); n.Panel.Refresh(1429)
    H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一 (" .. label .. ")", "t=" .. t .. " 標示 " .. label)
  end
  n = typed(nil, { [9900001] = 0 }); n.Panel.Refresh(1429)
  H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一", "t=0 無括號")
  n = typed(nil, { [9900001] = 999 }); n.Panel.Refresh(1429)
  H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一", "t=999 無括號")
  n = typed(nil, { [9900001] = "nil" }); n.Panel.Refresh(1429)
  H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一", "t=nil 無括號")
  n = typed({ locale = "enUS" }, { [9900001] = 81 }); n.Panel.Refresh(1429)
  H.eq(rowBtn(1).title:GetText(), "[7] Test Quest One (Dungeon)", "enUS t=81 (Dungeon)")

  -- 搜尋結果列也標；搜尋不比對類型
  n = typed(nil, { [9900001] = 81 }); n.Panel.Refresh(1429)
  n.Panel.SetSearch("測試任務一")
  H.eq(rowBtn(1).title:GetText(), "[7] 測試任務一 (地下城)", "搜尋結果列標示類型")
  n.Panel.SetSearch("地下城")
  H.eq(#n.Panel.Rows(), 0, "搜尋不比對類型")

  -- 排序：同等級 乙(t=81) 與 甲(t=nil)，甲在前
  n = typed(nil, { [9900001] = 81, [9900002] = "nil" })
  local prev = n.Data.quest
  n.Data.quest = function(id)
    local q = prev(id)
    if q and id == 9900001 then q.n = { zh = "甲" }; q.lv = 5 end
    if q and id == 9900002 then q.n = { zh = "甲" }; q.lv = 5 end
    return q
  end
  n.Panel.Refresh(1453)
  local out = {}
  for _, r in ipairs(n.Panel.Rows()) do out[#out + 1] = r.name end
  local ids2 = {}
  for _, r in ipairs(n.Panel.Rows()) do ids2[#ids2 + 1] = r.questId end
  H.eq(out[1], "甲", "同名同等級：排序用不含類型的名稱")
  H.eq(ids2[1], 9900001, "同名時依 questId（類型 t=81 的在前，不因標題較長而後移）")
end
