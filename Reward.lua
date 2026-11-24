-- 明細文字工具：ns.Reward.money(cu) 金錢字串、ns.Reward.xp(questId, q) 經驗值、ns.Reward.text(s) 描述代入。
-- 遊戲回傳的值在證實安全前只用 type() 與 issecretvalue 碰；保密或型別不對就退回資料值／原佔位文字。
local _, ns = ...

local Reward = {}
ns.Reward = Reward

-- 保密判斷統一用 ns.Core.secret（fail-closed）
local function secret(v) return ns.Core.secret(v) end

local function safeNumber(v)
  return type(v) == "number" and not secret(v)
end

-- 金錢：有 GetMoneyString 用它；沒有就用貨幣材質字串自組，0 的單位省略；全 0 或不是正數 -> nil
local ICON = "%d|TInterface\\MoneyFrame\\UI-%sIcon:0:0:2:0|t"
function Reward.money(cu)
  if type(cu) ~= "number" or cu <= 0 then return nil end
  if type(GetMoneyString) == "function" then
    local ok, s = pcall(GetMoneyString, cu)
    if ok and type(s) == "string" and not secret(s) and s ~= "" then return s end   -- 先確認非保密再比較
  end
  local g, s, c = math.floor(cu / 10000), math.floor(cu / 100) % 100, cu % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = ICON:format(g, "Gold") end
  if s > 0 then parts[#parts + 1] = ICON:format(s, "Silver") end
  if c > 0 then parts[#parts + 1] = ICON:format(c, "Copper") end
  return table.concat(parts, " ")
end

-- 經驗值（A1）：任務在日誌中，且 GetLogIndexForQuestID、GetQuestLogRewardXP 都在，
-- 又能在非戰鬥中安全選取該任務（SetSelectedQuest 與 GetSelectedQuest 都存在）才問遊戲；
-- 全程 pcall、取完還原原選取；任一條件不成立或結果不是正數就退回資料 xp。
local function dataXp(q)
  local v = type(q) == "table" and q.xp or nil
  if type(v) == "number" then return v end
  return nil
end

local function gameXp(questId)
  local ql = C_QuestLog
  if type(ql) ~= "table" then return nil end
  if type(ql.GetLogIndexForQuestID) ~= "function" or type(GetQuestLogRewardXP) ~= "function" then return nil end
  if type(ql.SetSelectedQuest) ~= "function" or type(ql.GetSelectedQuest) ~= "function" then return nil end
  if type(InCombatLockdown) ~= "function" or InCombatLockdown() then return nil end
  local okI, idx = pcall(ql.GetLogIndexForQuestID, questId)
  if not okI or not safeNumber(idx) or idx <= 0 then return nil end
  local okS, orig = pcall(ql.GetSelectedQuest)
  if not okS or not safeNumber(orig) then return nil end
  local okSet = pcall(ql.SetSelectedQuest, questId)
  local okX, xp
  if okSet then okX, xp = pcall(GetQuestLogRewardXP, questId) end
  pcall(ql.SetSelectedQuest, orig)   -- 不論成敗都還原（SetSelectedQuest 拋錯前可能已改到）
  if okSet and okX and safeNumber(xp) and xp > 0 then return xp end
  return nil
end

function Reward.xp(questId, q)
  if ns.Status and ns.Status.of and ns.Status.of(questId) == "log" then
    local v = gameXp(questId)
    if v then return v end
  end
  return dataXp(q)
end

-- 描述代入：{name}／{race}／{class}／$g甲:乙;；取不到安全字串就保留原佔位文字
local function unitText(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  -- 順序不可換：保密字串不能拿去比較（會拋錯），先 type、再 secret、最後才比對空字串
  if ok and type(v) == "string" and not secret(v) and v ~= "" then return v end
  return nil
end

local function isFemale()
  if type(UnitSex) ~= "function" then return false end
  local ok, v = pcall(UnitSex, "player")
  return ok and type(v) == "number" and not secret(v) and v == 3
end

function Reward.text(s)
  if type(s) ~= "string" then return "" end
  local vals = {
    name = function() return unitText(UnitName, "player") end,
    race = function() return unitText(UnitRace, "player") end,
    class = function() return unitText(UnitClass, "player") end,
  }
  -- 先處理 $g 再代入單位文字：玩家名稱若含 $g甲:乙; 不會被再解讀一次
  s = s:gsub("%$g([^:;]*):([^;]*);", function(a, b) return isFemale() and b or a end)
  s = s:gsub("{(%a+)}", function(key)
    local f = vals[key]
    return f and f() or nil   -- nil＝保留原文；回傳值不是樣式，不會被解讀 %
  end)
  return s
end
