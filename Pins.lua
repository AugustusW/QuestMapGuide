-- 地圖標記：點面板的任務列後，在大地圖上標出該任務起點 NPC／物件在「目前地圖」的位置
-- 做法：data provider 只負責在地圖切換時被呼叫 RefreshAllData；pin 是自己用 CreateFrame 建立、
-- 掛在地圖畫布（WorldMapFrame:GetCanvas()）上的 Frame，不經 AcquirePin，因此不需要 XML 樣板。
-- 遊戲內未驗證項目見 Probe.APIS 與任務報告。
local ADDON, ns = ...

local Pins = {}
ns.Pins = Pins

Pins.ICON = ns.Theme.QUEST_ICON  -- 可接任務的黃色「!」（與清單、明細起點同一張）
local PIN_SIZE = 18
local LEVEL_OFFSET = 1  -- 畫布 frame level + 1。假設低於遊戲自己的任務 POI，但層級順序遊戲內未驗證，必須實機確認

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
  f:SetSize(PIN_SIZE, PIN_SIZE)
  f:SetFrameLevel(canvas:GetFrameLevel() + LEVEL_OFFSET)
  f:EnableMouse(true)
  local t = f:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints()
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
      placed[#placed + 1] = { m = mapId, x = x / 100, y = y / 100, name = f.npcName, frame = f }
    end
  end
end

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
