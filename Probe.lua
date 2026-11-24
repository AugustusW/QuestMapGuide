-- /qmg probe：在永恆客戶端確認插件會用到的 API、widget 方法、template 是否存在。
-- 結果寫進 db.manifest（tools/gen_manifest.py 讀這裡），並記錄當下地圖 ID 與地圖類型。
local _, ns = ...

local Probe = {}
ns.Probe = Probe

Probe.APIS = {
  "C_QuestLog.IsQuestFlaggedCompleted", "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.IsOnQuest", "C_QuestLog.GetLogIndexForQuestID", "GetQuestsCompleted", "GetNumQuestLogEntries", "GetQuestLogTitle",
  "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries", "GetQuestDifficultyColor", "UnitFactionGroup",
  "UnitRace", "UnitClass", "UnitLevel", "GetProfessions", "GetProfessionInfo", "WorldMapFrame",
  "WorldMapFrame.GetMapID", "WorldMapFrame.OnMapChanged", "WorldMapFrame.AddDataProvider", "WorldMapFrame.RemoveDataProvider",
  "MapCanvasDataProviderMixin", "MapCanvasPinMixin", "CreateFromMixins", "C_Map.GetMapInfo", "GetItemInfo",
  "C_Item.GetItemInfo", "debugprofilestop", "collectgarbage", "GetLocale", "GetBuildInfo", "InCombatLockdown",
  "hooksecurefunc", "C_Timer.After", "CreateFrame", "WorldMapFrame.GetCanvas", "GameTooltip", "GameTooltip.SetOwner",
  "GameTooltip.AddLine", "GameTooltip.Show", "GameTooltip.Hide", "GameFontNormal", "GameFontNormalLarge",
  "GameFontHighlight", "GameFontDisableSmall", "MapCanvasDataProviderMixin.OnMapChanged",
  "MapCanvasDataProviderMixin.RefreshAllData", "UnitGUID", "UnitName", "issecretvalue",
  "GetCoinTextureString", "WorldMapFrame.SetMapID",
  -- 0.0.3：明細（獎勵物品、經驗值、描述代入）用到的 API
  "GetQuestLogRewardXP", "C_QuestLog.SetSelectedQuest", "C_QuestLog.GetSelectedQuest", "UnitSex",
  "C_Item.GetItemIconByID", "C_Item.GetItemQualityByID", "C_Item.GetItemQualityColor", "ITEM_QUALITY_COLORS",
  "GameTooltip.SetItemByID", "C_CreatureInfo.GetClassInfo", "C_CreatureInfo.GetRaceInfo",
}
Probe.TEMPLATES = {
  "BasicFrameTemplateWithInset", "UIPanelButtonTemplate", "UICheckButtonTemplate", "UIPanelScrollFrameTemplate",
  "WowStyle1DropdownTemplate", "InputBoxTemplate",
}
Probe.WIDGETS = { "Frame", "Button", "EditBox", "ScrollFrame", "CheckButton" }

local function resolve(path)
  local cur = _G
  for part in path:gmatch("[^%.]+") do
    if type(cur) ~= "table" then return nil end
    local ok, v = pcall(function() return cur[part] end)
    if not ok then return nil end
    cur = v
  end
  return cur
end
Probe.resolve = resolve

function Probe.manifest()
  local m = { methods = {}, templates = {}, globals = {}, apis = {} }
  for _, kind in ipairs(Probe.WIDGETS) do
    local ok, f = pcall(CreateFrame, kind)
    local list = {}
    if ok and f then
      if f.SetAutoFocus then f:SetAutoFocus(false) end
      if f.ClearFocus then f:ClearFocus() end
      if f.Hide then f:Hide() end
      local mt = getmetatable(f)
      local idx = mt and mt.__index
      if type(idx) == "table" then
        for k, v in pairs(idx) do if type(v) == "function" then list[#list + 1] = k end end
        table.sort(list)
      end
    end
    m.methods[kind] = list
  end
  for _, t in ipairs(Probe.TEMPLATES) do
    m.templates[t] = (pcall(CreateFrame, "Frame", nil, nil, t)) and true or false
  end
  for _, name in ipairs(Probe.APIS) do
    local ok, v = pcall(resolve, name)
    local has = ok and v ~= nil
    m.globals[name] = has
    m.apis[name] = has  -- 完整路徑的存在與否（globals 同內容；gen_manifest 只取第一段）
  end
  m.build = select(2, GetBuildInfo())
  return m
end

-- 當下地圖：驗證「地圖類型 3 ＝ 區域」
function Probe.mapInfo()
  local id, mapType
  local wm = _G.WorldMapFrame
  if type(wm) == "table" and wm.GetMapID then
    local ok, v = pcall(wm.GetMapID, wm)
    if ok then id = v end
  end
  if id and C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and type(info) == "table" then mapType = info.mapType end
  end
  return id, mapType
end

-- 單位探測：永恆客戶端有「保密值」，碰到保密字串（比較、索引、串接）會報錯。
-- 只有 issecretvalue 確認為 false 才動值；沒有 issecretvalue 時一切包 pcall 並標記。
local function isSecret(v)
  if type(issecretvalue) ~= "function" then return nil end
  local ok, r = pcall(issecretvalue, v)
  if not ok then return nil end
  return r and true or false
end

function Probe.unit(unit)
  if type(UnitGUID) ~= "function" then return "none" end
  local okG, guid = pcall(UnitGUID, unit)
  local okN, name = pcall(UnitName, unit)
  if not okG or type(guid) == "nil" then return "none" end
  local r = {}
  local gs = isSecret(guid)
  r.guidSecret = gs
  if gs == false then
    local ok, prefix, npc = pcall(function()
      return type(guid) == "string" and guid:match("^([^%-]+)") or nil,
        type(guid) == "string" and guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or nil
    end)
    if ok then r.guidPrefix, r.npcId = prefix, tonumber(npc) end
    local okS, shape = pcall(function()
      if type(guid) ~= "string" then return nil end
      local head = guid:match("^[^%-]*") or ""
      local rest = guid:sub(#head + 1):gsub("%d", "N"):gsub("%x", "H")
      return head .. rest
    end)
    if okS then r.guidShape = shape end
  elseif gs == nil then
    r.guidTypeOnly = type(guid)
  end
  if okN then
    local ns_ = isSecret(name)
    r.nameSecret = ns_
    if ns_ == false and type(name) == "string" then r.nameLen = #name end
  end
  return r
end

function Probe.questInfo()
  local qlog = _G.C_QuestLog
  if type(qlog) ~= "table" or type(qlog.GetInfo) ~= "function" then return "none" end
  local n = 40
  if type(qlog.GetNumQuestLogEntries) == "function" then
    local okN, num = pcall(qlog.GetNumQuestLogEntries)
    if okN and type(num) == "number" then n = num end
  end
  for i = 1, n do
    local ok, info = pcall(qlog.GetInfo, i)
    if ok and type(info) == "table" and not (type(info.isHeader) == "boolean" and info.isHeader) then
      local keys = {}
      for k in pairs(info) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      return table.concat(keys, ",")
    end
  end
  return "empty"
end

function Probe.difficultyType()
  if type(GetQuestDifficultyColor) ~= "function" then return "nil" end
  local ok, v = pcall(GetQuestDifficultyColor, 10)
  if not ok then return "error" end
  return type(v)
end

-- GetMoneyString(12345) 的回傳型別（常數引數，回傳只記型別）
function Probe.moneyStringType()
  if type(GetMoneyString) ~= "function" then return "nil" end
  local ok, v = pcall(GetMoneyString, 12345)
  if not ok then return "error" end
  return type(v)
end

-- 日誌中第一個任務的 questId（略過標題列）；沒有則回 nil
local function firstLogQuestId()
  local ql = _G.C_QuestLog
  if type(ql) ~= "table" or type(ql.GetInfo) ~= "function" then return nil end
  local n = 40
  if type(ql.GetNumQuestLogEntries) == "function" then
    local okN, num = pcall(ql.GetNumQuestLogEntries)
    if okN and type(num) == "number" then
      if ns.Core.secret(num) then return nil end   -- 保密的數量：當作沒有任務
      n = num
    end
  end
  for i = 1, n do
    local ok, info = pcall(ql.GetInfo, i)
    if ok and type(info) == "table" and not (type(info.isHeader) == "boolean" and info.isHeader)
        and type(info.questID) == "number" and not ns.Core.secret(info.questID) then
      return info.questID
    end
  end
  return nil
end

-- GetQuestLogRewardXP(日誌中某任務 questId)：只記結果型別（number 代表接受 questId 參數）。
-- none＝函式不存在、noQuest＝日誌沒有任務可測、error＝呼叫出錯；值本身不記。
function Probe.rewardXPType()
  if type(GetQuestLogRewardXP) ~= "function" then return "none" end
  local id = firstLogQuestId()
  if not id then return "noQuest" end
  local ok, v = pcall(GetQuestLogRewardXP, id)
  if not ok then return "error" end
  return type(v)
end

ns.Core.slash.probe = function()
  local db = ns.Core.db()
  db.manifest = Probe.manifest()
  db.probe = db.probe or {}
  db.probe.build = table.concat({ GetBuildInfo() }, " ")
  db.probe.unit = {
    issecretvalueExists = type(issecretvalue) == "function",
    mouseover = Probe.unit("mouseover"),
    target = Probe.unit("target"),
    questInfoKeys = Probe.questInfo(),
    difficultyColorType = Probe.difficultyType(),
  }
  local id, mapType = Probe.mapInfo()
  db.probe.mapId, db.probe.mapType = id, mapType
  db.probe.moneyStringType = Probe.moneyStringType()
  db.probe.rewardXPType = Probe.rewardXPType()
  print("|cffc9a24a" .. ns.L("panelTitle") .. "|r " ..
    string.format(ns.L("probeDone"), db.probe.build, tostring(id), tostring(mapType)))
end
