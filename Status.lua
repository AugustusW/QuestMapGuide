-- 任務狀態：ns.Status.of(questId) -> "done" | "log" | "open"
-- 完成：C_QuestLog.GetAllCompletedQuestIDs 建集合（遊戲內 /run 驗證存在，2026-11），每次重掃整組取代（每日任務重置後會清掉）；
--       of() 再用 IsQuestFlaggedCompleted 補一道（登入時清單可能還是空的）。
-- 日誌：有 C_QuestLog.IsOnQuest（Forever 內尚未驗證）就直接問它，因為被收合標題下的任務 GetInfo(i) 可能不回；
--       沒有就掃 GetNumQuestLogEntries＋GetInfo(i)（略過標題列）。
-- 事件：ACCEPTED／REMOVED／TURNED_IN 很少發生，立刻重掃（並取消排好的延後重掃）；QUEST_LOG_UPDATE 很頻繁，
--       合併成 0.5 秒內最多重掃一次，而且只更新日誌集合。完成清單何時重讀見 rescan 的註解。
-- 有變化才通知面板（ns.Panel.StatusChanged）。
local _, ns = ...

local Status = {}
ns.Status = Status

local THROTTLE = 0.5
local completed = {}     -- questId -> true；每次重掃用 API 結果整組取代（每日／每週任務重置後要能清掉）
local log = {}           -- questId -> true；只在沒有 IsOnQuest 時使用
local numQuests = 0      -- GetNumQuestLogEntries 第二個回傳值（任務總數，不受收合影響）
local token = 0          -- 每次重掃加一；延後重掃的計時器只認發出時的 token
local pending = false

local function notify()
  if ns.Panel and ns.Panel.StatusChanged then ns.Panel.StatusChanged() end
end

local function flagged(id)
  local ql = C_QuestLog
  if not ql or not ql.IsQuestFlaggedCompleted then return false end
  return ql.IsQuestFlaggedCompleted(id) == true
end

local function hasIsOnQuest()
  return C_QuestLog and type(C_QuestLog.IsOnQuest) == "function"
end

function Status.of(id)
  if completed[id] or flagged(id) then return "done" end
  if hasIsOnQuest() then
    if C_QuestLog.IsOnQuest(id) then return "log" end
  elseif log[id] then
    return "log"
  end
  return "open"
end

local function addCompleted(id)
  if not completed[id] then completed[id] = true; return true end
  return false
end

-- 重掃；回傳有沒有變。full 為真才重讀「已完成清單」（GetAllCompletedQuestIDs 回傳整張大表，很貴）；
-- 否則只更新日誌集合。完成清單只在登入、PLAYER_ENTERING_WORLD、QUEST_TURNED_IN 重讀，其餘事件最多每 60 秒一次
-- （Status.of 對單一任務還會再用 IsQuestFlaggedCompleted 補一道，所以不必每次都整張重讀）。
local COMPLETED_REFRESH = 60
local lastFull
local function rescan(full)
  token = token + 1
  pending = false
  local changed = false
  local ql = C_QuestLog
  if not ql then return false end
  if full == nil then
    full = lastFull == nil or time() - lastFull >= COMPLETED_REFRESH
  end
  if full and ql.GetAllCompletedQuestIDs then
    lastFull = time()
    local new = {}
    for _, id in ipairs(ql.GetAllCompletedQuestIDs() or {}) do
      new[id] = true
    end
    for id in pairs(new) do if not completed[id] then changed = true; break end end
    if not changed then
      for id in pairs(completed) do if not new[id] then changed = true; break end end
    end
    completed = new
  end
  if ql.GetNumQuestLogEntries then
    local count, nq = ql.GetNumQuestLogEntries()
    count = count or 0
    if (nq or 0) ~= numQuests then numQuests = nq or 0; changed = true end
    if not hasIsOnQuest() and ql.GetInfo then
      local new = {}
      for i = 1, count do
        local info = ql.GetInfo(i)
        if type(info) == "table" and not (type(info.isHeader) == "boolean" and info.isHeader)
            and type(info.questID) == "number" and not ns.Core.secret(info.questID) then
          new[info.questID] = true
        end
      end
      for id in pairs(new) do if not log[id] then changed = true; break end end
      if not changed then
        for id in pairs(log) do if not new[id] then changed = true; break end end
      end
      log = new
    end
  end
  return changed
end

local function schedule()
  if pending then return end
  pending = true
  local mine = token
  local ok = ns.Core.after(THROTTLE, function()
    if mine ~= token then return end   -- 已被立即重掃取代
    if rescan(false) then notify() end
  end)
  if not ok then
    pending = false
    if rescan(false) then notify() end
  end
end

-- 登入與進世界：完成清單一定重讀
local function immediateFull()
  rescan(true)
  notify()
end
-- 接任務／放棄任務：日誌立刻重掃；完成清單距上次超過 60 秒才順便重讀
local function immediate()
  rescan(nil)
  notify()
end

ns.Core.on("PLAYER_LOGIN", immediateFull)
ns.Core.on("PLAYER_ENTERING_WORLD", immediateFull)
-- 交任務：先重掃，再補上這個 id（API 此刻可能還沒列出它）；下一次重掃會以 API 為準
ns.Core.on("QUEST_TURNED_IN", function(questId)
  rescan(true)
  if type(questId) == "number" then addCompleted(questId) end
  notify()
end)
ns.Core.on("QUEST_ACCEPTED", immediate)
ns.Core.on("QUEST_REMOVED", immediate)
ns.Core.on("QUEST_LOG_UPDATE", schedule)
