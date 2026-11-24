-- 地圖標記：點清單列後在大地圖上標出任務起點（資料用 fixture）
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local wm = _G.WorldMapFrame
  local canvas = H.widget("Frame")
  canvas.GetWidth = function() return 1000 end
  canvas.GetHeight = function() return 500 end
  canvas.GetScale = function() return canvas._scale or 1 end
  canvas.GetFrameLevel = function() return 10 end
  wm.GetCanvas = function() return canvas end
  wm.providers = {}
  if not opts.noAdd then
    wm.AddDataProvider = function(self, p) wm.providers[#wm.providers + 1] = p end
  end
  _G.CreateFromMixins = function(...)
    local o = {}
    for _, m in ipairs({ ... }) do for k, v in pairs(m) do o[k] = v end end
    return o
  end
  _G.MapCanvasDataProviderMixin = {}
  H.installed.CreateFromMixins = true; H.installed.MapCanvasDataProviderMixin = true
  local tip = { lines = {} }
  tip.SetOwner = function(self, owner, anchor) self.owner = owner; self.shown = true end
  tip.AddLine = function(self, t) self.lines[#self.lines + 1] = t end
  tip.Show = function(self) self.shown = true end
  tip.Hide = function(self) self.shown = false; self.lines = {} end
  _G.GameTooltip = tip; H.installed.GameTooltip = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  return ns, wm, canvas, tip
end

local ns, wm, canvas, tip = setup()
-- 記錄 SetFrameLevel（harness 假物件不保存）
local realCF = _G.CreateFrame
_G.CreateFrame = function(...)
  local f = realCF(...)
  f.SetFrameLevel = function(self, v) self._level = v end
  f.SetScale = function(self, v) self._scale = v end
  f.SetPoint = function(self, ...) self._pt = { ... } end
  return f
end
H.eq(type(ns.Pins), "table", "Pins 存在")
H.eq(#wm.providers, 1, "載入時加入 data provider 一次")
H.fire("ADDON_LOADED", "QuestMapGuide"); H.fire("ADDON_LOADED", "Other")
H.eq(#wm.providers, 1, "再次觸發 ADDON_LOADED 不重複加入")

-- pin uses percent divided by 100：1429 上 (45.3, 60.1)
ns.Pins.Show(9900001)
local placed = ns.Pins.Placed()
H.eq(#placed, 1, "1429 上一個 pin")
H.eq(placed[1].m, 1429, "pin 在 1429")
H.check(math.abs(placed[1].x - 0.453) < 1e-9, "pin x 為百分比除以 100")
H.check(math.abs(placed[1].y - 0.601) < 1e-9, "pin y 為百分比除以 100")
H.eq(placed[1].name, "測試NPC", "pin 帶 NPC 繁中名稱")

-- 位置：相對畫布左上角
local pin = placed[1].frame
H.check(pin:IsShown(), "pin 顯示")
H.check(pin._parent == canvas, "pin 掛在地圖畫布")
H.eq(pin._pt[1], "CENTER", "以中心定位")
H.check(pin._pt[2] == canvas and pin._pt[3] == "TOPLEFT", "相對畫布左上角")
H.check(math.abs(pin._pt[4] - 453) < 1e-6 and math.abs(pin._pt[5] + 300.5) < 1e-6, "偏移 = 比例 * 畫布尺寸，y 向下為負")

-- only spawns on current map are drawn：n9901001 在 1429 與 1453 都有 spawn
H.mapId = 1453
ns.Pins.Show(9900001)
placed = ns.Pins.Placed()
H.eq(#placed, 1, "only spawns on current map are drawn")
H.eq(placed[1].m, 1453, "只畫目前地圖 1453")
H.eq(placed[1].x, 0.12, "1453 x")
H.eq(placed[1].y, 0.8, "1453 y")

-- provider added once：多次 Show 不重複加入
ns.Pins.Show(9900001); ns.Pins.Show(9900002); ns.Pins.Show(9900001)
H.eq(#wm.providers, 1, "provider added once")

-- 換任務：舊 pin 隱藏、只留新的
ns.Pins.Show(9900002)
placed = ns.Pins.Placed()
H.eq(#placed, 1, "換任務後只剩一個 pin")
H.eq(placed[1].name, "Fixture Object", "object 起點")
H.eq(placed[1].x, 0.3, "object x")

-- 切換地圖保留選中；沒有 spawn 的地圖不畫；回來又畫
local prov = wm.providers[1]
H.eq(prov, ns.Pins.provider, "provider 公開在 ns.Pins.provider")
H.mapId = 1500
prov:RefreshAllData()
H.eq(#ns.Pins.Placed(), 0, "換到沒有 spawn 的地圖不畫")
H.eq(ns.Pins.Selected(), 9900002, "切換地圖保留選中任務")
H.mapId = 1453
prov:RefreshAllData()
H.eq(#ns.Pins.Placed(), 1, "回到有 spawn 的地圖又畫")

-- Clear
ns.Pins.Clear()
H.eq(#ns.Pins.Placed(), 0, "Clear 後沒有 pin")
H.eq(ns.Pins.Selected(), nil, "Clear 後沒有選中")

-- 隱藏的 pin 會被重用，不無限建立 frame
ns.Pins.Show(9900001)
local n = #H.frames
for _ = 1, 5 do ns.Pins.Show(9900002); ns.Pins.Show(9900001) end
H.eq(#H.frames, n, "重複 Show 不建立新 frame")

-- 沒有起點資料（s 為 nil / 空）或不存在的任務：不畫、不報錯
H.check(pcall(ns.Pins.Show, 9900004), "s=nil 不報錯")
H.eq(#ns.Pins.Placed(), 0, "s=nil 不畫")
H.check(pcall(ns.Pins.Show, 9900003), "s={} 不報錯")
H.eq(#ns.Pins.Placed(), 0, "s={} 不畫")
H.check(pcall(ns.Pins.Show, 123), "未知任務不報錯")
H.eq(#ns.Pins.Placed(), 0, "未知任務不畫")

-- 提示：NPC 英文名與座標
ns.Pins.Show(9900001)
H.mapId = 1429
ns.Pins.Show(9900001)
pin = ns.Pins.Placed()[1].frame
pin._scripts.OnEnter(pin)
H.eq(tip.lines[1], "測試NPC", "提示第一行是 NPC 繁中名稱")
H.eq(tip.lines[2], "45.3, 60.1", "提示第二行是座標")
pin._scripts.OnLeave(pin)
H.check(not tip.shown, "移開後提示隱藏")

-- 圖層：高於遊戲自己的地圖圖層，且用自己的圖示
H.eq(pin._level, 7010, "frame level 為畫布 + 7000（實機遊戲標記到 2920，要在它們之上）")
local dl = ns.Pins.debugLines()
H.check(dl[1]:find("placed=", 1, true) ~= nil and #dl >= 2 and dl[2]:find("(45.3, 60.1) level=", 1, true) ~= nil, "/qmg pins 列出選中任務與每個標記的層級：" .. table.concat(dl, " | "))
H.check(type(ns.Core.slash.pins) == "function", "/qmg pins 指令已註冊")
H.check(type(ns.Pins.ICON) == "string" and ns.Pins.ICON ~= "", "有指定圖示")
H.eq(ns.Pins.ICON, ns.Theme.QUEST_ICON, "地圖標記用可接任務的黃色「!」（Theme.QUEST_ICON）")
H.eq(ns.Theme.QUEST_ICON, "Interface\\GossipFrame\\AvailableQuestIcon", "材質路徑")

-- 沒有 AddDataProvider：載入不報錯，Show 也不報錯（只是畫不出來）
local ns2 = setup({ noAdd = true })
H.check(pcall(ns2.Pins.Show, 9900001), "沒有 AddDataProvider 時 Show 不報錯")
H.eq(#ns2.Pins.Placed(), 0, "沒有 AddDataProvider 時不畫")

-- 沒有 CreateFromMixins：載入不報錯，不啟用
H.reset({ locale = "zhTW" })
dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
local ns3 = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.check(pcall(H.fire, "ADDON_LOADED", "QuestMapGuide"), "沒有 mixin 時載入不報錯")
H.check(pcall(ns3.Pins.Show, 9900001), "沒有 mixin 時 Show 不報錯")
H.eq(#ns3.Pins.Placed(), 0, "沒有 mixin 時不畫")

-- 畫布尺寸變動：OnSizeChanged 後 pin 依新尺寸重算
ns, wm, canvas = setup()
local rcf = _G.CreateFrame
_G.CreateFrame = function(...)
  local f = rcf(...)
  f.SetPoint = function(self, ...) self._pt = { ... } end
  f.SetScale = function(self, v) self._scale = v end
  return f
end
ns.Pins.Show(9900001)
pin = ns.Pins.Placed()[1].frame
H.check(math.abs(pin._pt[4] - 453) < 1e-6, "初始 x 偏移")
canvas.GetWidth = function() return 2000 end
canvas.GetHeight = function() return 1000 end
H.eq(type(canvas._scripts.OnSizeChanged), "function", "畫布掛了 OnSizeChanged")
canvas._scripts.OnSizeChanged(canvas)
pin = ns.Pins.Placed()[1].frame
H.check(math.abs(pin._pt[4] - 906) < 1e-6 and math.abs(pin._pt[5] + 601) < 1e-6, "尺寸變動後 pin 移到 比例 * 新尺寸")
-- 縮放抵銷
canvas._scale = 2
canvas._scripts.OnSizeChanged(canvas)
pin = ns.Pins.Placed()[1].frame
H.eq(pin._scale, 0.5, "畫布縮放 2 倍時 pin 縮放 0.5")
H.check(math.abs(pin._pt[4] - 1812) < 1e-6, "pin 縮放後偏移同步放大，螢幕位置不變")
-- OnRemoved 清除選中
wm.providers[1]:OnRemoved()
H.eq(ns.Pins.Selected(), nil, "OnRemoved 清掉選中")
H.eq(#ns.Pins.Placed(), 0, "OnRemoved 清掉 pin")

-- 0.2.0 節慶：明確打開的任務（點清單、明細連結）一律標記起點，不看清單篩選（協調者裁示 2026-11-25）。
-- Pins.draw 本來就不看 Filter.visible；這組測試防的是之後有人在 Pins 加上篩選（例如節慶隱藏）
do
  local n = setup()
  local real = n.Data.quest
  local hOf = { [9900001] = 1 }
  n.Data.quest = function(id) local q = real(id); if q then q.h = hOf[id] end return q end
  H.eq(n.Filter.get("showHoliday"), false, "前提：沒勾顯示節慶任務")
  n.Pins.Show(9900001)
  H.eq(#n.Pins.Placed(), 1, "節慶任務被明確選取：照樣標記（Pins 不套用節慶篩選）")
  n.Panel.SetCheck("showHoliday", false)
  H.eq(#n.Pins.Placed(), 1, "切換勾選不會收掉已選任務的標記")
  hOf[9900001] = 2
  n.Pins.Show(9900001)
  H.eq(#n.Pins.Placed(), 1, "暗月馬戲團標記")
end

-- /qmg pins 除錯欄位：分辨「畫布尺寸／縮放過時」「標記跑出可視範圍」「材質沒載入」「透明」「strata 不同」
do
  local n, _, cv = setup()
  local view = H.widget("Frame")   -- 畫布的父框架（ScrollContainer）：可視範圍
  view.GetLeft = function() return 0 end; view.GetRight = function() return 1200 end
  view.GetTop = function() return 800 end; view.GetBottom = function() return 0 end
  view.GetEffectiveScale = function() return 0.8 end
  cv.GetParent = function() return view end
  cv.GetLeft = function() return 100 end; cv.GetTop = function() return 700 end
  cv.GetEffectiveScale = function() return 0.8 end
  cv.GetFrameStrata = function() return "HIGH" end
  n.Pins.Show(9900001)
  local f = n.Pins.Placed()[1].frame
  -- 標記畫在正確位置：中心 = 畫布左上 + (45.3%, 60.1%)
  f.GetLeft = function() return 100 + 453 - 9 end; f.GetTop = function() return 700 - 300.5 + 9 end
  f.GetWidth = function() return 18 end; f.GetHeight = function() return 18 end
  f.GetEffectiveScale = function() return 0.8 end
  f.GetEffectiveAlpha = function() return 1 end
  f.GetFrameStrata = function() return "HIGH" end
  f.tex.GetTexture = function() return "Interface\\GossipFrame\\AvailableQuestIcon" end
  local all = table.concat(n.Pins.debugLines(), "\n")
  H.check(all:find("canvas w=1000.0 h=500.0 scale=1.00 eff=0.80", 1, true) ~= nil, "除錯：畫布目前尺寸與縮放：" .. all)
  H.check(all:find("drawn w=1000.0 h=500.0 scale=1.00", 1, true) ~= nil, "除錯：畫的當下用的尺寸與縮放")
  H.check(all:find("dx=0.0 dy=0.0", 1, true) ~= nil, "除錯：標記中心與預期位置的螢幕差")
  H.check(all:find("inView=true", 1, true) ~= nil, "除錯：在可視範圍內")
  H.check(all:find("alpha=1.00", 1, true) ~= nil and all:find("strata=HIGH/HIGH", 1, true) ~= nil, "除錯：有效透明度與 strata（標記／畫布）")
  H.check(all:find("tex=Interface\\GossipFrame\\AvailableQuestIcon", 1, true) ~= nil, "除錯：材質")
  -- 畫完之後畫布縮放變了（縮放沒觸發重畫）：drawn 與目前不同、標記跑出可視範圍
  cv._scale = 2
  f.GetLeft = function() return 2000 end
  all = table.concat(n.Pins.debugLines(), "\n")
  H.check(all:find("scale=2.00", 1, true) ~= nil and all:find("drawn w=1000.0 h=500.0 scale=1.00", 1, true) ~= nil, "除錯：看得出縮放在畫之後變了")
  H.check(all:find("inView=false", 1, true) ~= nil, "除錯：跑出可視範圍")
  -- 方法不存在／回傳不是數字：不報錯，印 ?
  f.GetLeft = nil; f.tex.GetTexture = nil; cv.GetParent = nil
  local ok, lines = pcall(n.Pins.debugLines)
  H.check(ok, "除錯：方法缺少時不報錯")
  all = ok and table.concat(lines, "\n") or ""
  H.check(all:find("tex=?", 1, true) ~= nil and all:find("dx=?", 1, true) ~= nil, "除錯：缺值印 ?")
end

-- 0.2.0：地圖標記加深色底（千針石林亮黃色地圖上，小小的黃色「!」看不出來）
do
  local n = setup()
  local T = n.Theme
  H.eq(T.PIN_SIZE, 22, "標記尺寸 22（原本 18）")
  H.check(type(T.PIN_ICON) == "number" and T.PIN_ICON < T.PIN_SIZE, "圖示比底小，四周留邊")
  H.check(T.PIN_BG[1] < 0.2 and T.PIN_BG[2] < 0.2 and T.PIN_BG[3] < 0.2, "底色是深色")
  H.check(math.abs(T.PIN_BG[4] - 0.75) < 1e-9, "底色透明度 0.75")
  n.Pins.Show(9900001)
  local f = n.Pins.Placed()[1].frame
  H.eq(f._width, T.PIN_SIZE, "標記框寬 = PIN_SIZE"); H.eq(f._height, T.PIN_SIZE, "標記框高 = PIN_SIZE")
  H.check(f.badge ~= nil and f.badge.bg ~= nil, "標記有深色底")
  H.eq(f.badge.bg._layer, "BACKGROUND", "深色底在 BACKGROUND")
  H.eq(f.badge.top._layer, "BORDER", "金邊在 BORDER")
  H.eq(f.tex._layer, "ARTWORK", "圖示在 ARTWORK（比底和邊高一層，不靠同層建立順序）")
  H.eq(f.badge.bg._ct[4], T.PIN_BG[4], "深色底套用 Theme.PIN_BG")
  H.eq(f.badge.top._ct[1], T.PIN_EDGE[1], "邊色套用 Theme.PIN_EDGE")
  H.eq(f.tex._tex, T.QUEST_ICON, "圖示材質不變")
  H.eq(f.tex._width, T.PIN_ICON, "圖示尺寸 = PIN_ICON")
  H.eq(f.tex._pt and f.tex._pt[1], "CENTER", "圖示置中")
end
