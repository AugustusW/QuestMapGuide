-- NPC 名稱學習：滑鼠指向／目標時記下繁中名稱，帳號共用（QuestMapGuideDB.npcNames），顯示時由 Data.npcName 取用。
-- 單位資訊在永恆客戶端可能是保密值：任何其他操作之前，GUID 與名稱都先確認不是保密值。
local _, ns = ...

local Learn = {}
ns.Learn = Learn

local THROTTLE = 60  -- 同一 npcId 在這個秒數內只寫一次
local lastWrite = {}  -- npcId -> 上次寫入時間（只在本次連線內有效）

local function secret(v)
  if type(issecretvalue) ~= "function" then return true end  -- 無法確認就當保密（fail-closed）
  local ok, r = pcall(issecretvalue, v)
  return (not ok) or r and true or false
end

function Learn.onUnit(unit)
  if type(GetLocale) ~= "function" or GetLocale() ~= "zhTW" then return end
  if type(UnitGUID) ~= "function" or type(UnitName) ~= "function" then return end
  local db = ns.Core.db()
  if type(db) ~= "table" then return end
  local okG, guid = pcall(UnitGUID, unit)
  local okN, name = pcall(UnitName, unit)
  if not okG or not okN then return end
  if type(guid) ~= "string" or type(name) ~= "string" then return end
  if secret(guid) or secret(name) then return end
  if name == "" then return end
  local npc = guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
  npc = tonumber(npc)
  if not npc then return end
  local now = time()
  -- 先查節流與索引，不必解碼 entity（滑鼠掃過一群怪時這條路徑很熱）
  if lastWrite[npc] and now - lastWrite[npc] < THROTTLE then return end
  if not ns.Data.hasEntity("n" .. npc) then return end
  lastWrite[npc] = now
  db.npcNames = db.npcNames or {}
  local r = db.npcNames[npc]
  local changed
  if type(r) ~= "table" then
    db.npcNames[npc] = { name = name, seen = 1, first = now, last = now }
    changed = true
  else
    changed = r.name ~= name
    if changed then
      -- 名稱改了：當成新紀錄重新計（與 AgentSpace 匯入 SP 一致）
      r.name, r.seen, r.first = name, 1, now
    else
      r.seen = (tonumber(r.seen) or 0) + 1
      r.first = r.first or now
    end
    r.last = now
  end
  if changed and ns.Panel and ns.Panel.InvalidateIndex then ns.Panel.InvalidateIndex() end
end

ns.Core.on("UPDATE_MOUSEOVER_UNIT", function() Learn.onUnit("mouseover") end)
ns.Core.on("PLAYER_TARGET_CHANGED", function() Learn.onUnit("target") end)
