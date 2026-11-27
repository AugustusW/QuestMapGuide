-- 任務明細：未快取物品、GET_ITEM_INFO_RECEIVED 更新、前置別張地圖切換、未知值不顯示 0、回清單保留清單狀態
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local mapId = opts.map or 1429
  local wm = H.widget("Frame")
  wm.GetMapID = function() return mapId end
  wm.OnMapChanged = function() end
  if not opts.noSetMapID then
    wm.SetMapID = function(self, id) mapId = id; self.setCalls = (self.setCalls or 0) + 1; self.OnMapChanged(self) end
  end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  local cache = {}
  _G.C_Item = { GetItemInfo = function(id) local n = cache[id]; if n then return n, "|cffffffff|Hitem:" .. id .. "|h[" .. n .. "]|h|r" end end }
  H.installed.C_Item = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  -- 地圖與面板開著（Detail 在看不到時不重建，見 M7 測試）
  wm:Show(); if ns.Panel.frame then ns.Panel.frame:Show() end
  return ns, wm, cache
end

local function joined(ns) return table.concat(ns.Detail.Lines(), "\n") end
local function has(s, sub) return s:find(sub, 1, true) ~= nil end

-- 基本內容與物品快取
local ns, wm, cache = setup()
H.check(ns.Detail.frame ~= nil, "Detail frame 在 ADDON_LOADED 建立")
H.check(ns.Panel.Select ~= nil, "Panel.Select 存在")
ns.Panel.Refresh(1429)
ns.Panel.Select(9900001)
H.eq(ns.Detail.Current(), 9900001, "選清單列開明細")
H.check(ns.Detail.frame:IsShown(), "明細顯示")
H.eq(ns.Pins.Selected(), 9900001, "選清單列仍標記")
local s = joined(ns)
H.check(has(s, "測試任務一"), "明細有名稱")
H.check(has(s, "等級 7"), "等級")
H.check(has(s, "物品 #12345"), "物品未快取顯示「物品 #id」")
H.check(has(s, "x2"), "物品數量")
H.check(not has(s, "在地圖標記"), "沒有獨立的「在地圖標記」列")
H.check(has(s, "測試NPC"), "起點 NPC（zhTW 用內建繁中名稱）")
H.check(has(s, "45.3, 60.1"), "起點座標取目前地圖")
H.check(has(s, "1 銀") or has(s, "12") , "金錢有顯示")
cache[12345] = "Fixture Sword"
H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
s = joined(ns)
H.check(has(s, "Fixture Sword"), "GET_ITEM_INFO_RECEIVED 後顯示物品名稱")
H.check(not has(s, "物品 #12345"), "更新後不再顯示「物品 #id」")
H.check(has(s, "物品 #12346"), "另一個仍未快取的維持「物品 #id」")

-- 金錢文字（沒有 GetCoinTextureString）
H.check(has(s, "12|TInterface\\MoneyFrame\\UI-SilverIcon"), "1200 銅 = 12 銀（Reward.money 後備）")
_G.issecretvalue = function() return false end; H.installed.issecretvalue = true
_G.GetMoneyString = function(c) return "COIN" .. c end; H.installed.GetMoneyString = true
ns.Detail.Refresh()
H.check(has(joined(ns), "COIN1200"), "有 GetMoneyString 就用它")
_G.GetMoneyString = nil

-- 未知數量不是 0
local realQuest = ns.Data.quest
ns.Data.quest = function(id)
  local q = realQuest(id)
  if id == 9900001 and q then q.ri = { { 12345, nil, false } }; q.cu = nil; q.xp = nil end
  return q
end
ns.Detail.Open(9900001)
s = joined(ns)
H.check(has(s, "數量未收錄"), "未知數量顯示「數量未收錄」")
H.check(not has(s, "x0") and not has(s, "x nil"), "未知數量不是 0")
H.check(has(s, "物品：資料未收錄") == false and has(s, "數量未收錄"), "ri 已知時不列物品未知")
H.check(not has(s, "金錢") and has(s, "經驗值：資料未收錄"), "ri 已知、cu／xp nil：金錢不列、經驗值「資料未收錄」")
ns.Data.quest = realQuest

-- 前置在別張地圖：切換地圖並開該任務明細；後續（9900002 的前置是 9900001，在 1429 與 1453）
ns, wm = setup({ map = 1429 })
ns.Panel.Refresh(1429)
ns.Detail.Open(9900002)
s = joined(ns)
H.check(has(s, "測試任務一"), "9900002 列出前置任務")
-- 9900002 只在 1453；前置 9900001 同時在 1453，所以不切換
wm.GetMapID = function() return 1500 end   -- 假裝目前在沒有任何任務的地圖
ns.Detail.GoTo(9900001)
H.eq(wm.setCalls, 1, "前置在別張地圖時切換地圖")
H.eq(ns.Detail.Current(), 9900001, "切換後開前置任務明細")
H.eq(ns.Pins.Selected(), 9900001, "切換後標記該任務")
-- 沒有 SetMapID：只開明細
ns, wm = setup({ map = 1500, noSetMapID = true })
ns.Detail.GoTo(9900001)
H.eq(ns.Detail.Current(), 9900001, "沒有 SetMapID 時仍開明細")
-- 同一張地圖上不切換
ns, wm = setup({ map = 1429 })
ns.Detail.GoTo(9900001)
H.check(wm.setCalls == nil, "目標任務在這張地圖時不切換")

-- 點前置那一列走 OnClick（實際按鈕）
ns, wm = setup({ map = 1500 })
ns.Detail.Open(9900002)
local found
local frame = ns.Detail.frame
for _, f in ipairs(H.frames) do
  if f._parent == frame and f.fs and f.quest == 9900001 then found = f end
end
H.check(found ~= nil, "前置那一列是可點的按鈕")
if found then found._scripts.OnClick(found) end
H.eq(ns.Detail.Current(), 9900001, "點前置列開該任務明細")
H.eq(wm.setCalls, 1, "點前置列切換地圖")

-- 不在資料裡的任務是純文字
ns = setup()
local rq = ns.Data.quest
ns.Data.quest = function(id) local q = rq(id); if id == 9900002 and q then q.prev = { 8888888 } end return q end
ns.Detail.Open(9900002)
s = joined(ns)
H.check(has(s, "（未收錄）"), "不在資料裡的前置顯示（未收錄）")
local clickable = false
for _, f in ipairs(H.frames) do if f._parent == ns.Detail.frame and f.quest == 8888888 then clickable = true end end
H.check(not clickable, "未收錄任務不可點")
H.eq(ns.Detail.Open(8888888), false, "Open 不存在的任務回傳 false")

-- 未知清單與空清單
ns.Data.quest = function(id) local q = rq(id); if id == 9900002 and q then q.prev = nil; q.next = {}; q.s = nil end return q end
ns.Detail.Open(9900002)
local L = ns.Detail.Lines()
local function idx(t) for i, v in ipairs(L) do if v == t then return i end end end
local ip, inx = idx("前置任務"), idx("後續任務")
H.eq(L[ip + 1], "  資料未收錄", "前置 nil 顯示資料未收錄")
H.eq(L[inx + 1], "  無", "後續 {} 顯示無")
H.check(not has(joined(ns), "在地圖標記"), "沒有「在地圖標記」列")

-- 回清單：關掉明細，清單的分頁、搜尋、捲動不動
ns = setup()
ns.Panel.Refresh(1429)
ns.Panel.SetTab("all")
ns.Panel.SetSearch("quest")
local tab, nrows, off = ns.Panel.Tab(), #ns.Panel.Rows(), ns.Panel.Offset()
ns.Panel.Select(9900001)
ns.Detail.backButton._scripts.OnClick(ns.Detail.backButton)
H.check(not ns.Detail.frame:IsShown(), "回清單隱藏明細")
H.eq(ns.Detail.Current(), nil, "回清單後沒有目前任務")
H.eq(ns.Panel.Tab(), tab, "回清單保留分頁")
H.eq(#ns.Panel.Rows(), nrows, "回清單保留搜尋結果")
H.eq(ns.Panel.Offset(), off, "回清單保留捲動")

-- 英文語系
ns = setup({ locale = "enUS" })
ns.Detail.Open(9900001)
s = joined(ns)
H.check(has(s, "Test Quest One") and has(s, "Item #12345") and not has(s, "Mark on map"), "英文語系")
H.check(has(s, "12|TInterface"), "英文金錢（貨幣圖示）")

-- GET_ITEM_INFO_RECEIVED 只在命中待載入物品時重建
ns, wm, cache = setup()
H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
H.eq(ns.Detail.BuildCount(), 0, "明細關著時忽略物品事件")
ns.Detail.Open(9900001)
local b0 = ns.Detail.BuildCount()
H.fire("GET_ITEM_INFO_RECEIVED", 777, true)
H.eq(ns.Detail.BuildCount(), b0, "無關的 itemID 不重建")
cache[12345] = "Fixture Sword"
H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
H.eq(ns.Detail.BuildCount(), b0 + 1, "待載入的 itemID 重建一次")
H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
H.eq(ns.Detail.BuildCount(), b0 + 1, "同一個 itemID 已處理，不再重建")
cache[12346] = "Fixture Shield"
H.fire("GET_ITEM_INFO_RECEIVED", 12346, true)
H.eq(ns.Detail.BuildCount(), b0 + 2, "另一個待載入的 itemID 也會重建")

-- 玩家自己切地圖：關掉明細；GoTo 自己切地圖：不關
ns, wm = setup({ map = 1429 })
ns.Panel.Refresh(1429)
ns.Detail.Open(9900001)
wm.SetMapID(wm, 1453)
H.check(not ns.Detail.IsOpen(), "地圖被別的方式換掉時關閉明細")
H.check(not ns.Detail.frame:IsShown(), "明細框也隱藏")
ns.Panel.Refresh(1453)
ns.Detail.Open(9900001)
ns.Panel.Refresh(1453)
H.check(ns.Detail.IsOpen(), "同一張地圖重畫不關明細")
wm.GetMapID = function() return 1500 end
ns.Detail.GoTo(9900002)
H.eq(ns.Detail.Current(), 9900002, "GoTo 切地圖後明細仍開著")

-- 狀態變化在 curMap 還沒有時也更新明細
ns = setup()
ns.Detail.Open(9900001)
local before = ns.Detail.BuildCount()
ns.Panel.StatusChanged()
H.check(ns.Detail.BuildCount() > before, "StatusChanged 重建明細")

-- xp=0／cu=0：不列經驗與金錢（已知為 0，不是未知）
ns = setup()
local rq0 = ns.Data.quest
ns.Data.quest = function(id) local q = rq0(id); if id == 9900002 and q then q.xp = 0; q.cu = 0 end return q end
ns.Detail.Open(9900002)
s = joined(ns)
H.check(not has(s, "經驗") and not has(s, "金錢"), "xp=0／cu=0 不列行")
H.check(not has(s, "資料未收錄：") and not has(s, "經驗：資料未收錄"), "xp=0／cu=0 不是未知")

-- 高的換行文字不畫出底部
ns = setup()
ns.Detail.Open(9900001)
local tall = 0
for _, f in ipairs(H.frames) do
  if f._parent == ns.Detail.frame and f.fs then f.fs.GetStringHeight = function() return 300 end end
end
ns.Detail.measure.GetStringHeight = function() return 300 end   -- 量高度用的 FontString（0.0.4 起獨立一個）
ns.Detail.frame.GetHeight = function() return 400 end
ns.Detail.Refresh()
local shown = 0
for _, f in ipairs(H.frames) do
  if f._parent == ns.Detail.frame and f.fs and f._shown then shown = shown + 1 end
end
H.eq(shown, 1 + 0, "每列 300 高、可用高度不足兩列時只畫一列（第一列保底）")

-- 底部留白只有 BOTTOM_PAD（8）：剛好放得下的最後一列要畫出來，不為多留 28 而被丟掉
do
  local n2 = setup()
  n2.Detail.Open(9900001)
  local function textButtons()
    local t = {}
    for _, f in ipairs(H.frames) do
      if f._parent == n2.Detail.frame and f.fs and f._shown then t[#t + 1] = f end
    end
    return t
  end
  local function bottomOf(bs)   -- 已畫出的文字列中，最低那一列的底緣（距面板頂）
    local m = 0
    for _, b in ipairs(bs) do m = math.max(m, -b._pt[5] + b._height) end
    return m
  end
  n2.Detail.frame.GetHeight = function() return 3000 end
  n2.Detail.Refresh()
  local all = textButtons()
  local bottom = bottomOf(all)
  H.check(#all >= 5, "足夠高時畫出所有文字列")
  n2.Detail.frame.GetHeight = function() return bottom + 8 end
  n2.Detail.Refresh()
  H.eq(#textButtons(), #all, "底緣 + 8 留白剛好放得下：全部列都畫出")
  n2.Detail.frame.GetHeight = function() return bottom + 7 end
  n2.Detail.Refresh()
  H.check(#textButtons() < #all, "少 1 px 就放不下最後一列")
end

-- Task 5a：版面順序、描述、獎勵分段、起點連結
local function order(lines, keys)
  local last = 0
  for _, k in ipairs(keys) do
    local at
    for i, v in ipairs(lines) do if i > last and v:find(k, 1, true) then at = i; break end end
    if not at then return false, k end
    last = at
  end
  return true
end
ns = setup({ map = 1429 })
local rq5 = ns.Data.quest
ns.Data.quest = function(id)
  local q = rq5(id)
  if id == 9900001 and q then
    q.ri = { { 12345, 1, true }, { 12346, 1, true }, { 12347, 1, true }, { 12348, 2, false } }
    q.xp = 6200; q.cu = 12500
  end
  return q
end
ns.Data.desc = function(id) if id == 9900001 then return "你好 {name}，請幫忙。" end end
_G.issecretvalue = function() return false end; H.installed.issecretvalue = true
_G.UnitName = function() return "阿爾" end; H.installed.UnitName = true
ns.Detail.Open(9900001)
local ok, miss = order(ns.Detail.Lines(), { "測試任務一", "狀態", "等級 7", "起點", "測試NPC", "交任務", "前置任務", "描述", "你好 阿爾，請幫忙。",
  "獎勵", "你可以從這些獎勵中選擇一個：", "物品 #12345", "物品 #12346", "物品 #12347", "你將得到：", "物品 #12348 x2",
  "你還會得到：", "1|TInterface", "經驗值：6200", "後續任務" })
H.check(ok, "版面順序 " .. tostring(miss))
H.check(not has(joined(ns), "在地圖標記"), "Lines 不含「在地圖標記」")
-- 無描述的任務沒有「描述」標題
ns.Detail.Open(9900002)
local hasDescHead = false
for _, l in ipairs(ns.Detail.Lines()) do if l == "描述" then hasDescHead = true end end
H.check(not hasDescHead, "無描述的任務沒有「描述」標題")

-- 起點連結：同地圖 → Pins.Show；別地圖 → 先 SetMapID 且明細仍開（起點列有「!」圖示；標題列也可點〔Shift 貼連結〕，要分開）
local function startRow(ns)
  for _, f in ipairs(H.frames) do
    if f._parent == ns.Detail.frame and f.fs and f._shown and f.onClick and f.pin and f.pin._shown then return f end
  end
end
ns, wm = setup({ map = 1429 })
ns.Data.desc = function() return nil end
ns.Detail.Open(9900001)
local shows = {}
local realShow = ns.Pins.Show
ns.Pins.Show = function(id) shows[#shows + 1] = id end
local row = startRow(ns)
H.check(row ~= nil, "起點列是整列可點的按鈕")
row._scripts.OnClick(row)
H.eq(shows[1], 9900001, "同地圖點起點 → Pins.Show(cur)")
H.check(wm.setCalls == nil, "同地圖不切地圖")
-- 別張地圖：目前在 1500
ns, wm = setup({ map = 1500 })
ns.Detail.Open(9900001)
shows = {}
ns.Pins.Show = function(id) shows[#shows + 1] = id end
row = startRow(ns)
row._scripts.OnClick(row)
H.eq(wm.setCalls, 1, "別張地圖點起點先切地圖")
H.eq(wm.GetMapID(), 1429, "切到 entity 第一個 spawn 的地圖")
H.check(ns.Detail.IsOpen() and ns.Detail.Current() == 9900001, "切地圖後明細仍開著")
H.eq(shows[1], 9900001, "切地圖後 Pins.Show(cur)")

-- 獎勵未知欄位：每個 nil 欄位都要有「資料未收錄」，只有三項都已知為空才省略整段
local function rewardCase(ri, cu, xp)
  local n = setup()
  local rqc = n.Data.quest
  n.Data.quest = function(id) local q = rqc(id); if id == 9900001 and q then q.ri, q.cu, q.xp = ri, cu, xp end return q end
  n.Data.desc = function() return nil end
  n.Detail.Open(9900001)
  return joined(n)
end
local c1 = rewardCase({ { 12345, 1, false } }, nil, nil)
H.check(has(c1, "獎勵") and has(c1, "物品 #12345") and not has(c1, "金錢") and has(c1, "經驗值：資料未收錄"), "ri 已知、cu／xp nil：金錢不列")
local c2 = rewardCase(nil, 1200, 450)
H.check(has(c2, "物品：資料未收錄") and has(c2, "經驗值：450") and has(c2, "12|TInterface"), "ri nil、cu／xp 已知：物品列資料未收錄")
local c3 = rewardCase(nil, 0, nil)
H.check(has(c3, "獎勵") and has(c3, "物品：資料未收錄") and has(c3, "經驗值：資料未收錄") and not has(c3, "金錢：資料未收錄"), "ri nil、cu=0、xp nil：整段不消失，cu=0 不列")
local c4 = rewardCase({}, 0, 0)
H.check(not has(c4, "獎勵") and not has(c4, "資料未收錄：") and not has(c4, "經驗值") and not has(c4, "金錢"), "三項皆已知為空：省略整段")

-- 5b：物品按鈕與 tooltip
local function itemSetup(ri, apis)
  local n, w, c = setup()
  local rq = n.Data.quest
  n.Data.quest = function(id) local q = rq(id); if id == 9900001 and q then q.ri, q.cu, q.xp = ri, 0, 0 end return q end
  n.Data.desc = function() return nil end
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  for k, v in pairs(apis or {}) do _G.C_Item[k] = v end
  n.Detail.Open(9900001)
  return n, c
end
local function itemBtns()
  local t = {}
  for _, f in ipairs(H.frames) do if f.itemBtn and f._shown then t[#t + 1] = f end end
  return t
end
do
  local n, c = itemSetup({ { 6087, 1, true }, { 6088, 1, true }, { 6089, 1, true }, { 12348, 5, false } })
  local ib = n.Detail.ItemButtons()
  H.eq(#ib, 4, "ItemButtons 4 個")
  H.eq(ib[1].itemId, 6087, "第 1 個 id")
  H.eq(ib[1].choice, true, "選擇獎勵 choice=true")
  H.eq(ib[4].choice, false, "固定獎勵 choice=false")
  H.eq(ib[1].icon, "Interface\\Icons\\INV_Misc_QuestionMark", "未快取：問號圖示")
  local bs = itemBtns()
  H.eq(#bs, 4, "四個按鈕顯示")
  H.eq(bs[1].nameFs:GetText(), "物品 #6087", "未快取名稱")
  -- 品質色框在圖示底下：同一層級的兩張材質遊戲不保證先後（實機看到整格只有框色、圖示被蓋住）
  local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }
  H.check(LAYER[bs[1].border._layer or "ARTWORK"] < LAYER[bs[1].icon._layer or "ARTWORK"], "品質框的繪製層低於圖示")
  H.eq(bs[1].countFs:GetText(), "", "count=1 不顯示數量")
  H.eq(bs[4].countFs:GetText(), "5", "count=5 顯示 5")
  -- 一欄：x 相同、y 由上往下
  H.check(bs[1].slot[1] == bs[2].slot[1] and bs[2].slot[2] < bs[1].slot[2] and bs[3].slot[2] < bs[2].slot[2], "一欄排列")
  -- 快取後更新
  c[6087] = "銅劍"
  _G.C_Item.GetItemIconByID = function() return 135274 end
  H.fire("GET_ITEM_INFO_RECEIVED", 6087, true)
  bs = itemBtns()
  H.eq(bs[1].nameFs:GetText(), "銅劍", "快取後名稱更新")
  H.eq(n.Detail.ItemButtons()[1].icon, 135274, "快取後圖示更新")
  H.check(has(joined(n), "銅劍"), "Lines 仍有物品名")
  -- tooltip：沒有 SetItemByID → SetHyperlink
  local tip = { calls = {} }
  tip.SetOwner = function(self, o) self.owner = o end
  tip.SetHyperlink = function(self, l) self.link = l end
  tip.Show = function(self) self.shown = true end
  tip.Hide = function(self) self.shown = false end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  bs[1]._scripts.OnEnter(bs[1])
  H.eq(tip.link, "item:6087", "沒有 SetItemByID 時用 SetHyperlink")
  H.eq(tip.shown, true, "tooltip 顯示")
  bs[1]._scripts.OnLeave(bs[1])
  H.eq(tip.shown, false, "離開隱藏")
  tip.SetItemByID = function(self, id) self.byId = id end
  bs[2]._scripts.OnEnter(bs[2])
  H.eq(tip.byId, 6088, "有 SetItemByID 就用")
end
do
  -- 品質色與保密值
  local n, c = itemSetup({ { 6087, 1, false } }, {
    GetItemQualityByID = function() return 4 end,
    GetItemIconByID = function() return 135274 end })
  _G.ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93 } }; H.installed.ITEM_QUALITY_COLORS = true
  n.Detail.Refresh()
  local b = itemBtns()[1]
  H.check(math.abs(b.nameColor[1] - 0.45) < 0.001, "史詩品質色 r（羊皮紙色盤 0.45）")
  _G.issecretvalue = function(v) return v == 135274 end
  n.Detail.Refresh()
  H.eq(n.Detail.ItemButtons()[1].icon, "Interface\\Icons\\INV_Misc_QuestionMark", "保密圖示退回問號")
end
do
  -- 物品池 12 個：超過時只畫放得下的，捲動後後面的物品出現（按鈕分配給目前看得到的列）
  local ri = {}
  for i = 1, 14 do ri[i] = { 7000 + i, 1, false } end
  local n = itemSetup(ri)
  n.Detail.frame.GetHeight = function() return 1400 end   -- 夠高，物品列一欄放得下 12 個
  n.Detail.Open(9900001)
  H.eq(#n.Detail.ItemButtons(), 12, "池滿 12 個")
  H.eq(#itemBtns(), 12, "12 個按鈕")
  local before = n.Detail.ItemButtons()[1].itemId
  for _ = 1, 20 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1) end
  local ids = {}
  for _, b in ipairs(n.Detail.ItemButtons()) do ids[b.itemId] = true end
  H.check(ids[7014] and ids[7013], "捲到底後最後兩個物品看得到（池按可見列分配）")
  H.check(n.Detail.ItemButtons()[1].itemId ~= before, "頂端物品已捲走")
end

-- 5c：捲動與底部裁切
local function longSetup(nDesc, nItems)
  local ri = {}
  for i = 1, nItems do ri[i] = { 8000 + i, 1, i % 2 == 0 } end
  local n, c = itemSetup(ri)
  local parts = {}
  for i = 1, nDesc do parts[i] = "描述第" .. i .. "行" end
  n.Data.desc = function() return table.concat(parts, "\n") end
  n.Detail.frame.GetHeight = function() return 400 end
  n.Detail.Open(9900001)
  return n, c
end
local function textShown(n)
  local t = {}
  for _, f in ipairs(H.frames) do
    if f._parent == n.Detail.frame and f.fs and f._shown then t[#t + 1] = f end
  end
  return t
end
do
  local n = longSetup(40, 8)
  local room = 400 - 40 - 8   -- TOP 40、BOTTOM_PAD 8
  local function inBounds(tag)
    for _, f in ipairs(textShown(n)) do
      H.check(-f._pt[5] - 40 + (f._height or 12) <= room + 0.001, tag .. " 文字列不超出底部")
    end
    for _, b in ipairs(itemBtns()) do
      H.check(-b.slot[2] - 40 + 37 <= room + 0.001, tag .. " 物品按鈕不超出底部")
    end
  end
  inBounds("初始")
  local top = n.Detail.Lines()[1]
  local first = textShown(n)[1].fs:GetText()
  H.check(#textShown(n) < 45, "40 行描述不會全部顯示")
  for _ = 1, 3 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1) end
  inBounds("向下捲")
  H.check(textShown(n)[1].fs:GetText() ~= first, "滾輪向下後頂端列換了（原頂端隱藏）")
  -- 捲到底再滾不越界，且最後一列看得到
  for _ = 1, 100 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1) end
  inBounds("到底")
  local atEnd = textShown(n)[1].fs:GetText()
  for _ = 1, 10 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1) end
  H.eq(textShown(n)[1].fs:GetText(), atEnd, "到底再滾位置不變")
  local lastText = n.Detail.Lines()[#n.Detail.Lines()]
  local seen = false
  for _, f in ipairs(textShown(n)) do if f.fs:GetText() == lastText then seen = true end end
  H.check(seen, "到底時最後一列可見")
  -- 往上捲回頂
  for _ = 1, 200 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, 1) end
  H.eq(textShown(n)[1].fs:GetText(), first, "往上捲回頂端")
end
do
  -- 物品列整列一起顯示或隱藏：奇數個物品、在列邊界
  for k = 0, 30 do
    local n = longSetup(k, 5)
    local function check(tag)
      local bs = itemBtns()
      H.check(#bs == #n.Detail.ItemButtons(), tag .. " 顯示數與 ItemButtons 一致")
    end
    check("k=" .. k)
    for _ = 1, 4 do n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1); check("k=" .. k .. " 捲") end
  end
  -- 4 個物品（一欄、每列一個）：任何捲動位置，每個 y 只有一顆
  local n = longSetup(30, 4)
  for step = 1, 40 do
    local bs = itemBtns()
    local byY = {}
    for _, b in ipairs(bs) do byY[b.slot[2]] = (byY[b.slot[2]] or 0) + 1 end
    for _, cnt in pairs(byY) do H.eq(cnt, 1, "物品列一欄一個（step " .. step .. "）") end
    n.Detail.frame._scripts.OnMouseWheel(n.Detail.frame, -1)
  end
end
do
  -- 5b 補測：保密名稱／品質退回；tooltip 擁有者隱藏時收掉；沒有 tooltip 方法不 Show
  local n = itemSetup({ { 6087, 1, false } }, {
    GetItemQualityByID = function() return 4 end })
  _G.C_Item.GetItemInfo = function() return "SECRETNAME", "|Hitem:6087|h[SECRETNAME]|h", 4 end
  _G.ITEM_QUALITY_COLORS = { [4] = { r = 0.64, g = 0.21, b = 0.93 } }; H.installed.ITEM_QUALITY_COLORS = true
  _G.issecretvalue = function(v) return v == "SECRETNAME" or v == "|Hitem:6087|h[SECRETNAME]|h" end
  n.Detail.Refresh()
  H.eq(itemBtns()[1].nameFs:GetText(), "物品 #6087", "保密名稱退回「物品 #id」")
  H.check(not has(joined(n), "SECRETNAME"), "保密名稱不進 Lines")
  _G.issecretvalue = function(v) return v == 4 end
  _G.C_Item.GetItemInfo = function() return "Sword", "|Hitem:6087|h[Sword]|h", 4 end
  n.Detail.Refresh()
  local b = itemBtns()[1]
  H.eq(b.nameFs:GetText() ~= nil, true, "名稱仍顯示")
  H.eq(b.nameColor[1], 0.18, "保密品質退回白色（羊皮紙上用一般文字色）r")
  H.eq(b.nameColor[2], 0.12, "保密品質退回白色（羊皮紙上用一般文字色）g")
  -- 沒有 issecretvalue：一律當保密（fail-closed）
  _G.issecretvalue = nil; H.installed.issecretvalue = false
  n.Detail.Refresh()
  H.eq(itemBtns()[1].nameFs:GetText(), "物品 #6087", "沒有 issecretvalue 時退回待載入名稱")
end
do
  local n = itemSetup({ { 6087, 1, false }, { 6088, 1, false } })
  local tip = { shown = false }
  tip.SetOwner = function(self, o) self.owner = o end
  tip.GetOwner = function(self) return self.owner end
  tip.SetHyperlink = function() end
  tip.Show = function(self) self.shown = true end
  tip.Hide = function(self) self.shown = false; self.owner = nil end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  local bs = itemBtns()
  bs[2]._scripts.OnEnter(bs[2])
  H.eq(tip.shown, true, "tooltip 開著")
  n.Detail.Open(9900001)   -- 內容不變、按鈕重用：不收
  H.eq(tip.shown, true, "同物品重繪不收 tooltip")
  local prevQ = n.Data.quest
  n.Data.quest = function(id) local q = prevQ(id); if id == 9900001 and q then q.ri = { { 6087, 1, false } } end return q end
  n.Detail.Refresh()       -- 第二顆被隱藏
  H.eq(tip.shown, false, "擁有 tooltip 的按鈕被隱藏時收掉 tooltip")
  -- 沒有 GetOwner 也不報錯
  tip.GetOwner = nil
  n.Detail.Refresh()
  -- 沒有任何 tooltip 方法：不 Show
  local tip2 = { shown = false, SetOwner = function() end, Show = function(self) self.shown = true end, Hide = function() end }
  _G.GameTooltip = tip2
  bs = itemBtns()
  bs[1]._scripts.OnEnter(bs[1])
  H.eq(tip2.shown, false, "沒有 SetItemByID／SetHyperlink 不呼叫 Show")
end

-- 任務類型標示與起點列地圖名稱、Close 收 tooltip
do
  local function mapNames(tbl) _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3, name = tbl[id] } end } end
  local function withT(n, t)
    local prev = n.Data.quest
    n.Data.quest = function(id) local q = prev(id); if q and id == 9900001 then q.t = t end return q end
  end
  local n = setup()
  withT(n, 81)
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  H.eq(n.Detail.Lines()[1], "測試任務一 (地下城)", "明細標題含類型")

  -- 起點列：目前地圖有 spawn
  n = setup(); mapNames({ [1429] = "艾爾文森林", [1453] = "暴風城" })
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  H.check(has(joined(n), "  測試NPC · 艾爾文森林(45.3, 60.1)"), "起點列：NPC · 目前地圖名(x, y)")
  -- 只在別張地圖
  n = setup(); mapNames({ [1429] = "艾爾文森林", [1453] = "暴風城" })
  n.Panel.Refresh(1429); n.Panel.Select(9900002)
  H.check(has(joined(n), "Fixture Object · 暴風城(30.0, 31.5)"), "起點列：只在別張地圖也標地圖名")
  -- 地圖名取不到
  n = setup(); mapNames({})
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  H.check(has(joined(n), "  測試NPC (45.3, 60.1)\n"), "地圖名取不到：NPC (x, y)")
  -- 地圖名是保密值
  n = setup(); mapNames({ [1429] = "祕密" })
  _G.issecretvalue = function(v) return v == "祕密" end; H.installed.issecretvalue = true
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  H.check(not has(joined(n), "祕密"), "保密的地圖名不顯示")
  H.check(has(joined(n), "  測試NPC (45.3, 60.1)\n"), "保密地圖名：NPC (x, y)")
  _G.issecretvalue = nil
  -- 保密檢查要在任何比較之前：空字串（比較分支會先短路）也必須先問過 issecretvalue
  n = setup(); mapNames({ [1429] = "" })
  local asked = 0
  _G.issecretvalue = function(v) asked = asked + 1; return false end; H.installed.issecretvalue = true
  H.eq(n.Data.mapName(1429), nil, "空字串地圖名回 nil")
  H.check(asked >= 1, "mapName 在比較前先做保密檢查（issecretvalue 被問了 " .. asked .. " 次）")
  _G.issecretvalue = nil
  -- 沒有 spawn：只有 NPC 名
  n = setup(); mapNames({ [1429] = "艾爾文森林" })
  local prevE = n.Data.entity
  n.Data.entity = function(k) local e = prevE(k); if e and k == "n9901001" then e.sp = nil end return e end
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  H.check(has(joined(n), "  測試NPC\n"), "無 spawn 只有 NPC 名")
  H.check(not has(joined(n), "艾爾文森林"), "無 spawn 不標地圖名")

  -- Close 收物品按鈕的 tooltip
  n = setup()
  n.Panel.Refresh(1429); n.Panel.Select(9900001)
  local tip = { shown = false }
  tip.SetOwner = function(self, o) self.owner = o end
  tip.GetOwner = function(self) return self.owner end
  tip.SetHyperlink = function() end
  tip.Show = function(self) self.shown = true end
  tip.Hide = function(self) self.shown = false; self.owner = nil end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  local ib
  for _, f in ipairs(H.frames) do if f.nameFs and f:IsShown() then ib = f; break end end
  H.check(ib ~= nil, "有顯示中的物品按鈕")
  ib._scripts.OnEnter(ib)
  H.eq(tip.shown, true, "tooltip 開著")
  n.Detail.Close()
  H.eq(tip.shown, false, "Close 收掉物品按鈕的 tooltip")
end
