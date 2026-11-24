-- 遊戲任務日誌點任務 → 面板切到那個任務（開明細＋標記起點），等同在清單點那一列。
-- 只用 hooksecurefunc 掛在遊戲函式之後（post-hook，不取代、不碰受保護框架，戰鬥中也不會 taint）。
-- 掛哪些（各自存在才掛；永恆客戶端哪幾個存在由 /qmg probe 回報，遊戲內未驗證）：
--   QuestMapFrame_ShowQuestDetails(questID)  地圖右側的現代式任務日誌
--   QuestLog_SetSelection(index)             經典 QuestLogFrame
--   SelectQuestLogEntry(index)               經典的選取 API（QuestLog_SetSelection 內部也會呼叫它）
-- index → questID：C_QuestLog.GetInfo(index).questID，沒有就退回 GetQuestLogTitle(index) 第 8 個回傳值；標題列不理。
-- 同一次點擊可能觸發兩三個 hook：同一個 questID 且明細已經開著就不重做。
-- 面板沒建或看不到（地圖沒開）：記下 questID，面板顯示時才切（只用一次）。
local ADDON, ns = ...

local LogSelect = {}
ns.LogSelect = LogSelect

LogSelect.BY_ID = { "QuestMapFrame_ShowQuestDetails" }
LogSelect.BY_INDEX = { "QuestLog_SetSelection", "SelectQuestLogEntry" }

local hooked = {}
local pending        -- 面板看不到時點的任務
local last           -- 上一次處理的 questID（去重）
local shownHooked = false

local function questIdOf(v)
  if type(v) ~= "number" or ns.Core.secret(v) or v <= 0 then return nil end
  return v
end

-- 日誌第 index 列的 questID；標題列、查不到、保密值都回 nil
local function idAt(index)
  if type(index) ~= "number" then return nil end
  local ql = _G.C_QuestLog
  if type(ql) == "table" and type(ql.GetInfo) == "function" then
    local ok, info = pcall(ql.GetInfo, index)
    if ok and type(info) == "table" then
      if type(info.isHeader) == "boolean" and info.isHeader then return nil end
      return questIdOf(info.questID)
    end
    if ok then return nil end
  end
  local title = _G.GetQuestLogTitle
  if type(title) == "function" then
    local ok, _, _, _, isHeader, _, _, _, id = pcall(title, index)
    if ok and not (type(isHeader) == "boolean" and isHeader) then return questIdOf(id) end
  end
  return nil
end

local function panelVisible()
  local f = ns.Panel and ns.Panel.frame
  return f ~= nil and f:IsVisible()
end

function LogSelect.Select(questId)
  local id = questIdOf(questId)
  if not id or not ns.Data.quest(id) then return end
  if not panelVisible() then pending = id; return end
  pending = nil
  if id == last and ns.Detail and ns.Detail.Current() == id then return end   -- 同一次點擊的其他 hook
  last = id
  ns.Panel.Select(id)
end

local function byId(questId) LogSelect.Select(questId) end
local function byIndex(index) LogSelect.Select(idAt(index)) end

local function hookAll()
  for _, list in ipairs({ { LogSelect.BY_ID, byId }, { LogSelect.BY_INDEX, byIndex } }) do
    for _, name in ipairs(list[1]) do
      if not hooked[name] and type(_G[name]) == "function" then
        hooksecurefunc(_G, name, list[2])
        hooked[name] = true
      end
    end
  end
  local f = ns.Panel and ns.Panel.frame
  if f and not shownHooked then
    shownHooked = true
    f:HookScript("OnShow", function()
      local id = pending
      pending = nil
      if id then LogSelect.Select(id) end
    end)
  end
end

function LogSelect.Hooked() return hooked end

-- 自己載入時掛一次；之後每個插件載入（遊戲的按需載入介面）再補掛還沒掛到的
ns.Core.on("ADDON_LOADED", function() hookAll() end)
