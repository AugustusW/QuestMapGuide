-- 核心：存檔、事件分派、/qmg 子指令
local ADDON, ns = ...

local Core = { slash = {} }
ns.Core = Core

local DB_VERSION = 1
local handlers = {}
local reported, reportedCount = {}, 0
local REPORT_MAX = 50  -- 不同錯誤訊息最多印這麼多則，之後不再印（避免洗版與記憶體增長）
local frame = CreateFrame("Frame")

Core.badEvents = {}   -- RegisterEvent 失敗的事件名（客戶端不認得）；ADDON_LOADED 後寫進 db.probe.badEvents

function Core.on(event, fn)
  if not handlers[event] then
    -- 不認得的事件名會讓 RegisterEvent 丟錯；包 pcall，記下來，其他事件照常運作
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then
      Core.badEvents[#Core.badEvents + 1] = event
      local db = QuestMapGuideDB
      if type(db) == "table" then Core.recordBadEvents() end
      return false
    end
    handlers[event] = {}
  end
  table.insert(handlers[event], fn)
  return true
end

-- 錯誤只印一次（同一則訊息），且最多 REPORT_MAX 則
local function report(label, err)
  if reportedCount < REPORT_MAX and not reported[tostring(err)] then
    reported[tostring(err)] = true
    reportedCount = reportedCount + 1
    print(ns.L("coreHandlerError"):format(label, tostring(err)))
  end
end
Core.report = report

-- C_Timer.After 包 pcall：回呼出錯走同一條回報路徑。沒有 C_Timer 回傳 false（呼叫端自己處理）
function Core.after(delay, fn)
  if not (C_Timer and C_Timer.After) then return false end
  C_Timer.After(delay, function()
    local ok, err = pcall(fn)
    if not ok then report("C_Timer", err) end
  end)
  return true
end

function Core.recordBadEvents()
  local db = QuestMapGuideDB
  if type(db) ~= "table" or #Core.badEvents == 0 then return end
  db.probe = db.probe or {}
  db.probe.badEvents = { unpack(Core.badEvents) }
end

frame:SetScript("OnEvent", function(_, event, ...)
  -- 每個 handler 獨立 pcall：一個失敗不擋後面的；同一則錯誤只印一次
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then report(event, err) end
  end
end)

-- 保密值判斷（fail-closed）；Detail／Reward 共用這一份（Learn.lua 仍有自己的版本）：沒有 issecretvalue、呼叫拋錯、回傳不是 false 都當保密
function Core.secret(v)
  if type(issecretvalue) ~= "function" then return true end
  local ok, r = pcall(issecretvalue, v)
  return (not ok) or r ~= false
end

-- 帳號存檔
function Core.db()
  return QuestMapGuideDB
end

-- 角色存檔
function Core.charDb()
  return QuestMapGuideCharDB
end

Core.on("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  QuestMapGuideDB = QuestMapGuideDB or {}
  QuestMapGuideCharDB = QuestMapGuideCharDB or {}
  QuestMapGuideDB.version = QuestMapGuideDB.version or DB_VERSION
  QuestMapGuideDB.npcNames = QuestMapGuideDB.npcNames or {}  -- 學到的繁中 NPC 名稱（Learn.lua）
  Core.recordBadEvents()
end)

SLASH_QUESTMAPGUIDE1 = "/qmg"
SlashCmdList.QUESTMAPGUIDE = function(msg)
  local sub, args = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  local fn = Core.slash[sub]
  if fn then fn(args) else print("|cffc9a24a" .. ns.L("panelTitle") .. "|r /qmg") end
end

-- /qmg stats：內建資料的解析時間與記憶體（LoadStart／LoadEnd 量測）
local STATS_MAX_MS, STATS_MAX_MB = 150, 20
function Core.slash.stats()
  local s = ns.Stats
  if not s or not s.parseMs or not s.memKB then
    print(ns.L("statsNA"):format(s and s.quests or 0))
    return
  end
  -- 顯示與比較用同一個四捨五入後的數字（印 150.0 就不會再說超過）
  local ms = tonumber(("%.1f"):format(s.parseMs))
  local mb = tonumber(("%.1f"):format(s.memKB / 1024))
  print(ns.L("statsLine"):format(s.quests, ("%.1f"):format(ms), ("%.1f"):format(mb)))
  if ms > STATS_MAX_MS or mb > STATS_MAX_MB then
    print(ns.L("statsOver"):format(STATS_MAX_MS, STATS_MAX_MB))
  end
end

-- 收納按鈕（TOC AddonCompartmentFunc，小地圖右上角的插件選單）：點了開關世界地圖（面板在地圖旁邊）。
-- 2026-11-28 實機回報：原本只印 /qmg 用法，點了像沒反應。ToggleWorldMap 未探測：有就用（包 pcall），
-- 沒有或出錯就直接開關 WorldMapFrame
function QuestMapGuide_OnAddonCompartmentClick()
  if type(ToggleWorldMap) == "function" and pcall(ToggleWorldMap) then return end   -- 出錯就退回直接開關
  local wm = _G.WorldMapFrame
  if type(wm) ~= "table" or type(wm.IsShown) ~= "function" then return end
  if wm:IsShown() then wm:Hide() else wm:Show() end
end
function QuestMapGuide_OnAddonCompartmentEnter(_, button)
  local tip = _G.GameTooltip
  if type(tip) ~= "table" or type(tip.AddLine) ~= "function" then return end
  if type(tip.SetOwner) == "function" then pcall(tip.SetOwner, tip, button or _G.UIParent, "ANCHOR_LEFT") end
  tip:AddLine(ns.L("panelTitle"))
  tip:AddLine(ns.L("compartmentHint"))
  tip:Show()
end
function QuestMapGuide_OnAddonCompartmentLeave()
  local tip = _G.GameTooltip
  if type(tip) == "table" and type(tip.Hide) == "function" then tip:Hide() end
end
