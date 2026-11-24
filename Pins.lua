-- 地圖標記：點面板的任務列後，在大地圖上標出該任務起點 NPC／物件在「目前地圖」的位置
-- 做法：data provider 只負責在地圖切換時被呼叫 RefreshAllData；pin 是自己用 CreateFrame 建立、
-- 掛在地圖畫布（WorldMapFrame:GetCanvas()）上的 Frame，不經 AcquirePin，因此不需要 XML 樣板。
-- 遊戲內未驗證項目見 Probe.APIS 與任務報告。
local ADDON, ns = ...

local Pins = {}
ns.Pins = Pins

Pins.ICON = ns.Theme.QUEST_ICON  -- 可接任務的黃色「!」（與清單、明細起點同一張）
local LEVEL_OFFSET = 7000  -- 畫布 frame level + 7000：畫在遊戲自己的地圖標記之上。
                          -- 2026-11-25 實機 /fstack：畫布上遊戲自己的子框架層級到 2002–2920（某些不接滑鼠的覆蓋層），
                          -- +500 的標記滑鼠移過去有提示、畫面上卻被蓋住。frame level 上限 10000，留餘裕

local selected        -- 選中的 questId（換地圖保留）
local added = false   -- provider 已加入 WorldMapFrame
local pool = {}       -- 已建立的 pin frame（隱藏後重用）
local hookedCanvas  -- 已掛 OnSizeChanged 的畫布
local draw
local placed = {}     -- 目前畫出的 {m, x, y, name, frame}；x、y 為 0–1

local function canvasOf()
  local wm = _G.WorldMapFrame
  if type(wm) ~= "table" or type(wm.GetCanvas) ~= "function" then return nil end
  return wm:GetCanvas()
end

local function onEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine(self.npcName or "")
  GameTooltip:AddLine(string.format("%.1f, %.1f", self.x100 or 0, self.y100 or 0))
  GameTooltip:Show()
end
local function onLeave() GameTooltip:Hide() end

local function newPin(canvas)
  local f = CreateFrame("Frame", nil, canvas)
  local T = ns.Theme
  f:SetSize(T.PIN_SIZE, T.PIN_SIZE)
  f:SetFrameLevel(canvas:GetFrameLevel() + LEVEL_OFFSET)
  f:EnableMouse(true)
  -- 深色底（BACKGROUND）＋金邊（BORDER）在下，「!」（ARTWORK）在上：分在不同圖層，不靠同層的建立順序
  f.badge = T.box(f)
  T.boxColor(f.badge, T.PIN_BG, T.PIN_EDGE)
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetSize(T.PIN_ICON, T.PIN_ICON)
  t:SetPoint("CENTER", f, "CENTER", 0, 0)
  t:SetTexture(Pins.ICON)
  f.tex = t
  f:SetScript("OnEnter", onEnter)
  f:SetScript("OnLeave", onLeave)
  return f
end

local function acquire(canvas, i)
  local f = pool[i]
  if not f then f = newPin(canvas); pool[i] = f end
  return f
end

local function removeAll()
  for _, f in ipairs(pool) do f:Hide() end
  placed = {}
end

local function currentMap()
  local wm = _G.WorldMapFrame
  return wm and wm:GetMapID()
end

local function hookCanvas(canvas)
  if canvas == hookedCanvas or type(canvas.HookScript) ~= "function" then return end
  hookedCanvas = canvas
  -- 最大化／還原地圖、UI 縮放會改畫布尺寸，像素位移要重算
  canvas:HookScript("OnSizeChanged", function() draw() end)
end

function draw()
  removeAll()
  if not added then return end
  local c = canvasOf()
  if c then hookCanvas(c) end
  if not selected then return end
  local q = ns.Data.quest(selected)
  local mapId = currentMap()
  local canvas = canvasOf()
  if not q or not q.s or not mapId or not canvas then return end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  -- 畫布放大時 pin 會跟著變大；以 1/縮放 抵銷，圖示維持固定螢幕大小。
  -- 只在 draw（選取、換地圖、尺寸變動）時重算，單純縮放不會觸發（遊戲內需確認）。
  local scale = canvas:GetScale()
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  local pinScale = 1 / scale
  for _, key in ipairs(q.s) do
    local ent = ns.Data.entity(key)
    for x, y in ns.Data.spawns(ent, mapId) do
      local f = acquire(canvas, #placed + 1)
      f.npcName, f.x100, f.y100 = ns.Data.npcName(key), x, y
      f:ClearAllPoints()
      f:SetScale(pinScale)
      -- SetPoint 偏移以 pin 自己的縮放計，所以除以 pinScale
      f:SetPoint("CENTER", canvas, "TOPLEFT", x / 100 * w / pinScale, -y / 100 * h / pinScale)
      f:Show()
      placed[#placed + 1] = { m = mapId, x = x / 100, y = y / 100, name = f.npcName, frame = f,
        dw = w, dh = h, ds = scale }   -- 畫的當下用的畫布尺寸與縮放（/qmg pins 比對用）
    end
  end
end

-- 明確打開的任務（點清單列、明細的起點／前置／後續連結）一律標記，不看清單篩選（例如沒勾顯示節慶任務）
function Pins.Show(questId)
  selected = questId
  draw()
end

function Pins.Clear()
  selected = nil
  draw()
end

function Pins.Selected() return selected end
function Pins.Placed() return placed end

-- 供 WorldMapFrame 在地圖切換時呼叫；mixin 與 AddDataProvider 遊戲內未驗證，缺任何一個就不啟用標記
local function buildProvider()
  if type(CreateFromMixins) ~= "function" or type(MapCanvasDataProviderMixin) ~= "table" then return nil end
  local p = CreateFromMixins(MapCanvasDataProviderMixin)
  function p:RemoveAllData() removeAll() end
  function p:RefreshAllData() draw() end
  function p:OnRemoved() selected = nil; removeAll() end
  return p
end

ns.Core.on("ADDON_LOADED", function(name)
  if name ~= ADDON or added then return end
  local wm = _G.WorldMapFrame
  if type(wm) ~= "table" or type(wm.AddDataProvider) ~= "function" then return end
  local p = buildProvider()
  if not p then return end
  Pins.provider = p
  wm:AddDataProvider(p)
  added = true
end)

-- /qmg pins 的除錯取值：方法不存在、拋錯或回傳不是預期型別都回 nil（印成 ?）
local function get(obj, method, want)
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then return nil end
  local ok, v = pcall(obj[method], obj)
  if ok and type(v) == (want or "number") then return v end
  return nil
end
local function n1(v) return v and string.format("%.1f", v) or "?" end
local function n2(v) return v and string.format("%.2f", v) or "?" end

-- /qmg pins：印出目前選中的任務、地圖與畫出的標記（實機查「點了沒標記」用）。
-- 每個標記多一行，用來分辨看不到的原因：
--   canvas／drawn：畫布目前與畫的當下的尺寸、縮放（縮放或尺寸在畫之後變了 → 位置過時）
--   dx／dy：標記中心與「畫布左上＋座標百分比」預期位置的螢幕座標差（不是 0 → 錨點或縮放算錯）
--   inView：標記中心在畫布父框架（可視範圍）內
--   alpha／strata：有效透明度、標記與畫布的 strata；tex：材質（nil → 沒載入）
function Pins.debugLines()
  local out = {}
  local wm = _G.WorldMapFrame
  out[#out + 1] = string.format("selected=%s map=%s added=%s placed=%d", tostring(selected),
    tostring(wm and wm.GetMapID and wm:GetMapID()), tostring(added), #placed)
  local cv = canvasOf()
  local cw, ch, cs, ce = get(cv, "GetWidth"), get(cv, "GetHeight"), get(cv, "GetScale"), get(cv, "GetEffectiveScale")
  local cl, ct = get(cv, "GetLeft"), get(cv, "GetTop")
  local view = cv and get(cv, "GetParent", "table")
  local ve = get(view, "GetEffectiveScale")
  local vl, vr, vt, vb = get(view, "GetLeft"), get(view, "GetRight"), get(view, "GetTop"), get(view, "GetBottom")
  for i, p in ipairs(placed) do
    local f = p.frame
    out[#out + 1] = string.format("#%d %s (%.1f, %.1f) level=%s shown=%s visible=%s", i, tostring(p.name), p.x * 100, p.y * 100,
      tostring(f and f.GetFrameLevel and f:GetFrameLevel()), tostring(f and f.IsShown and f:IsShown()),
      tostring(f and f.IsVisible and f:IsVisible()))
    local fl, ft, fw, fh, fe = get(f, "GetLeft"), get(f, "GetTop"), get(f, "GetWidth"), get(f, "GetHeight"), get(f, "GetEffectiveScale")
    local dx, dy, inView = nil, nil, "?"
    if fl and ft and fw and fh and fe then
      local px, py = (fl + fw / 2) * fe, (ft - fh / 2) * fe   -- 標記中心（螢幕座標）
      if cl and ct and cw and ch and ce then
        dx, dy = px - (cl + p.x * cw) * ce, py - (ct - p.y * ch) * ce
      end
      if vl and vr and vt and vb and ve then
        inView = tostring(px >= vl * ve and px <= vr * ve and py >= vb * ve and py <= vt * ve)
      end
    end
    out[#out + 1] = string.format("  canvas w=%s h=%s scale=%s eff=%s | drawn w=%s h=%s scale=%s | dx=%s dy=%s inView=%s"
      .. " | pin scale=%s eff=%s size=%sx%s alpha=%s strata=%s/%s | tex=%s",
      n1(cw), n1(ch), n2(cs), n2(ce), n1(p.dw), n1(p.dh), n2(p.ds), n1(dx), n1(dy), inView,
      n2(get(f, "GetScale")), n2(fe), n1(fw), n1(fh), n2(get(f, "GetEffectiveAlpha")),
      tostring(get(f, "GetFrameStrata", "string") or "?"), tostring(get(cv, "GetFrameStrata", "string") or "?"),
      tostring(get(f and f.tex, "GetTexture", "string") or get(f and f.tex, "GetTexture") or "?"))
  end
  return out
end
if ns.Core and ns.Core.slash then
  ns.Core.slash.pins = function() for _, l in ipairs(Pins.debugLines()) do print(l) end end
end

