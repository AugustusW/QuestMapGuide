-- /qmg probe：API 存在性、build、當下地圖
local KEYS = { "C_QuestLog", "WorldMapFrame", "C_Map", "debugprofilestop" }
local function clear() for _, k in ipairs(KEYS) do _G[k] = nil end end

H.reset()
_G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 日誌 questId 要過保密檢查（fail-closed）
local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.fire("ADDON_LOADED", "QuestMapGuide")
H.eq(type(ns.Core.slash.probe), "function", "probe 子指令存在")

-- 假 API 有函式
_G.C_QuestLog = { IsQuestFlaggedCompleted = function() return false end }
_G.WorldMapFrame = { GetMapID = function() return 1415 end }
_G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }
SlashCmdList.QUESTMAPGUIDE("probe")
local m = QuestMapGuideDB.manifest
H.eq(m.apis["C_QuestLog.IsQuestFlaggedCompleted"], true, "有該函式為 true")
H.eq(m.apis["C_QuestLog.GetInfo"], false, "沒有的函式為 false")
H.eq(m.apis["WorldMapFrame.GetMapID"], true, "WorldMapFrame.GetMapID 為 true")
H.eq(m.apis["WorldMapFrame.AddDataProvider"], false, "WorldMapFrame.AddDataProvider 為 false")
H.eq(m.apis["debugprofilestop"], false, "全域缺少為 false")
H.eq(m.build, "70399", "manifest.build 等於 GetBuildInfo 第 2 個回傳值")
H.eq(QuestMapGuideDB.probe.mapId, 1415, "記錄地圖 ID")
H.eq(QuestMapGuideDB.probe.mapType, 3, "記錄地圖類型")
H.check(QuestMapGuideDB.probe.build:find("1.60.1", 1, true) ~= nil, "probe.build 含版本字串")

-- 拿掉函式
_G.C_QuestLog = {}
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.manifest.apis["C_QuestLog.IsQuestFlaggedCompleted"], false, "拿掉後為 false")

-- 沒有地圖 API 時不報錯
clear()
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.mapId, nil, "無 WorldMapFrame 時 mapId 為 nil")

-- 必含的探測項目
local need = { "C_QuestLog.IsQuestFlaggedCompleted", "GetQuestsCompleted", "GetNumQuestLogEntries", "GetQuestLogTitle",
  "C_QuestLog.GetInfo", "C_QuestLog.GetNumQuestLogEntries", "GetQuestDifficultyColor", "UnitFactionGroup", "UnitRace",
  "UnitClass", "UnitLevel", "GetProfessions", "GetProfessionInfo", "WorldMapFrame", "WorldMapFrame.GetMapID",
  "WorldMapFrame.AddDataProvider", "WorldMapFrame.RemoveDataProvider", "MapCanvasDataProviderMixin",
  "MapCanvasPinMixin", "CreateFromMixins", "C_Map.GetMapInfo", "GetItemInfo", "C_Item.GetItemInfo",
  "debugprofilestop", "collectgarbage", "GetLocale", "GetBuildInfo", "InCombatLockdown", "hooksecurefunc", "C_Timer.After" }
local have = {}
for _, n in ipairs(ns.Probe.APIS) do have[n] = true end
for _, n in ipairs(need) do H.check(have[n], "APIS 含 " .. n) end
clear()

-- 單位探測：保密值不得被碰觸，只記 "secret"
local function trap() error("touched secret") end
local SECRET = setmetatable({}, { __index = trap, __newindex = trap, __eq = trap, __lt = trap, __le = trap,
  __len = trap, __concat = trap, __call = trap, __tostring = trap })
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
_G.UnitGUID = function(u)
  if u == "mouseover" then return "Creature-0-4379-1-12-1234-0000ABCDEF" end
  if u == "target" then return SECRET end
end
_G.UnitName = function(u)
  if u == "mouseover" then return "Bob" end
  if u == "target" then return SECRET end
end
_G.C_QuestLog = { GetInfo = function(i)
  if i == 1 then return { title = "h", isHeader = true } end
  return { title = "t", questID = 1 }
end }
_G.GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 1 } end
SlashCmdList.QUESTMAPGUIDE("probe")
local u = QuestMapGuideDB.probe.unit
H.eq(u.issecretvalueExists, true, "記錄 issecretvalue 存在")
H.eq(u.mouseover.guidSecret, false, "mouseover guid 非保密")
H.eq(u.mouseover.guidPrefix, "Creature", "guidPrefix")
H.eq(u.mouseover.npcId, 1234, "npcId 解析")
H.eq(u.mouseover.guidShape, "Creature-N-NNNN-N-NN-NNNN-NNNNHHHHHH", "guid 遮罩形狀")
H.eq(u.mouseover.nameLen, 3, "nameLen")
H.eq(u.target.guidSecret, true, "target guid 保密")
H.eq(u.target.nameSecret, true, "target name 保密")
H.eq(u.target.npcId, nil, "保密時不解析 npcId")
H.eq(u.target.guidPrefix, nil, "保密時不記 prefix")
H.eq(u.questInfoKeys, "questID,title", "略過標題列，取第一個任務的鍵名排序")
H.eq(u.target.guidShape, nil, "保密時不記形狀")
H.eq(u.difficultyColorType, "table", "GetQuestDifficultyColor 型別")

-- 沒有單位 / 沒有 issecretvalue
_G.issecretvalue = nil
_G.UnitGUID = function() return nil end
_G.UnitName = function() return nil end
_G.C_QuestLog = nil
_G.GetQuestDifficultyColor = nil
SlashCmdList.QUESTMAPGUIDE("probe")
u = QuestMapGuideDB.probe.unit
H.eq(u.issecretvalueExists, false, "無 issecretvalue 記 false")
H.eq(u.mouseover, "none", "無 mouseover 記 none")
H.eq(u.target, "none", "無 target 記 none")
H.eq(u.questInfoKeys, "none", "無 GetInfo")
_G.C_QuestLog = { GetInfo = function() return nil end }
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.unit.questInfoKeys, "empty", "API 在但沒有任務為 empty")
H.eq(u.difficultyColorType, "nil", "無 GetQuestDifficultyColor")
-- issecretvalue 不存在但值存在（值其實是保密的）：只記 type，不碰值
_G.UnitGUID = function() return SECRET end
_G.UnitName = function() return SECRET end
SlashCmdList.QUESTMAPGUIDE("probe")
u = QuestMapGuideDB.probe.unit
H.eq(u.mouseover.guidTypeOnly, "table", "無 issecretvalue 只記 guidTypeOnly")
H.eq(u.mouseover.guidPrefix, nil, "無 issecretvalue 不解析 prefix")
H.eq(u.mouseover.npcId, nil, "無 issecretvalue 不解析 npcId")
H.eq(u.mouseover.nameLen, nil, "無 issecretvalue 不記 nameLen")
-- 保密值路徑只能用 type()/issecretvalue()：原始碼不得有 guid/name 的 ==、~=、..（# 只允許出現在 isSecret 為 false 之後）
local f = io.open(H.dir .. "/Probe.lua"); local src = f:read("*a"); f:close()
for _, pat in ipairs({ "guid%s*[=~]=", "name%s*[=~]=", "%.%.%s*guid", "%.%.%s*name",
  "tostring%(%s*guid", "tostring%(%s*name" }) do
  H.check(not src:find(pat), "Probe.lua 不含保密值危險運算 " .. pat)
end
for _, k in ipairs({ "issecretvalue", "UnitGUID", "UnitName", "GetQuestDifficultyColor" }) do _G[k] = nil end
clear()

-- 0.0.3 新鍵：APIS 含新增 API 名稱
local need3 = { "GetQuestLogRewardXP", "C_QuestLog.GetLogIndexForQuestID", "C_QuestLog.SetSelectedQuest",
  "C_QuestLog.GetSelectedQuest", "UnitSex", "C_Item.GetItemIconByID", "C_Item.GetItemQualityByID",
  "C_Item.GetItemQualityColor", "ITEM_QUALITY_COLORS", "GameTooltip.SetItemByID", "GetCoinTextureString" }
have = {}
for _, n in ipairs(ns.Probe.APIS) do have[n] = true end
for _, n in ipairs(need3) do H.check(have[n], "APIS 含 " .. n) end

-- 新鍵存在性：有函式為 true、沒有為 false
_G.UnitSex = function() return 2 end
_G.ITEM_QUALITY_COLORS = {}
_G.C_Item = { GetItemIconByID = function() return 1 end }
SlashCmdList.QUESTMAPGUIDE("probe")
m = QuestMapGuideDB.manifest
H.eq(m.apis["UnitSex"], true, "UnitSex 為 true")
H.eq(m.apis["ITEM_QUALITY_COLORS"], true, "ITEM_QUALITY_COLORS 為 true")
H.eq(m.apis["C_Item.GetItemIconByID"], true, "GetItemIconByID 為 true")
H.eq(m.apis["C_Item.GetItemQualityByID"], false, "GetItemQualityByID 缺少為 false")
H.eq(m.apis["GetQuestLogRewardXP"], false, "GetQuestLogRewardXP 缺少為 false")

-- GetMoneyString 回傳型別、GetQuestLogRewardXP 結果型別
local pr = QuestMapGuideDB.probe
H.eq(pr.moneyStringType, "nil", "無 GetMoneyString 記 nil")
H.eq(pr.rewardXPType, "none", "無 GetQuestLogRewardXP 記 none")
_G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 日誌 questId 要過保密檢查（fail-closed）
local calls = {}
_G.GetMoneyString = function(n) calls[#calls + 1] = n; return "1g 23s 45c" end
_G.GetQuestLogRewardXP = function(id) calls[#calls + 1] = id; return 250 end
_G.C_QuestLog = { GetNumQuestLogEntries = function() return 2 end,
  GetInfo = function(i)
    if i == 1 then return { title = "h", isHeader = true } end
    return { title = "t", questID = 777 }
  end }
SlashCmdList.QUESTMAPGUIDE("probe")
pr = QuestMapGuideDB.probe
H.eq(pr.moneyStringType, "string", "GetMoneyString(12345) 型別")
H.eq(calls[1], 12345, "GetMoneyString 以 12345 呼叫")
H.eq(pr.rewardXPType, "number", "日誌任務 questId 呼叫回數字")
H.eq(calls[2], 777, "以日誌中任務的 questId 呼叫")
-- 保密／錯誤：只記型別
_G.GetQuestLogRewardXP = function() error("boom") end
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.rewardXPType, "error", "呼叫出錯記 error")
_G.GetQuestLogRewardXP = function() return nil end
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.rewardXPType, "nil", "回 nil 記 nil")
-- 日誌 questId／數量是保密值：當作沒有任務，不呼叫
local secretId = 778
_G.issecretvalue = function(v) return v == secretId end
local called = nil
_G.GetQuestLogRewardXP = function() called = true; return 1 end
_G.C_QuestLog = { GetNumQuestLogEntries = function() return 1 end, GetInfo = function() return { questID = secretId } end }
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.rewardXPType, "noQuest", "questId 是保密值記 noQuest")
H.eq(called, nil, "保密 questId 不呼叫 GetQuestLogRewardXP")
_G.C_QuestLog = { GetNumQuestLogEntries = function() return secretId end, GetInfo = function() return { questID = 5 } end }
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.rewardXPType, "noQuest", "日誌數量是保密值記 noQuest")
_G.issecretvalue = function() return false end
-- 日誌沒有任務：不呼叫
called = false
_G.GetQuestLogRewardXP = function() called = true; return 1 end
_G.C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, GetInfo = function() return nil end }
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.rewardXPType, "noQuest", "日誌空記 noQuest")
H.eq(called, false, "日誌空不呼叫 GetQuestLogRewardXP")

-- 任務日誌獎勵（2026-11-27 實機回報：日誌裡的任務有物品獎勵、插件沒有）：
-- 對日誌裡每個任務選取後讀 GetNumQuestLogChoices／Rewards 與 GetQuestLogItemLink，記物品 ID 與數量；取完還原原選取
H.check((function() local h = {} for _, n in ipairs(ns.Probe.APIS) do h[n] = true end
  return h.GetNumQuestLogChoices and h.GetNumQuestLogRewards and h.GetQuestLogItemLink and h.GetQuestLogChoiceInfo
    and h.GetQuestLogRewardInfo and h.GetQuestLogSelection end)(), "APIS 含任務日誌獎勵 API")
_G.issecretvalue = function() return false end
-- 永恆 1.60 沒有 SelectQuestLogEntry／GetQuestLogSelection（2026-11-27 探測存檔）：用 C_QuestLog 以 questId 選取
local sel = 4242
local BYQ = { [96988] = { c = { 21001, 21002 }, r = { 21003 } }, [777] = { c = {}, r = {} } }
local LOG = { [2] = { q = 96988 }, [3] = { q = 777 } }
setmetatable(LOG, { __index = function() return nil end })
local function cur() return BYQ[sel] end
_G.C_QuestLog = { GetNumQuestLogEntries = function() return 3 end,
  GetInfo = function(i) if i == 1 then return { isHeader = true } end return LOG[i] and { questID = LOG[i].q } end,
  GetSelectedQuest = function() return sel end, SetSelectedQuest = function(q) sel = q end }
_G.GetNumQuestLogChoices = function() return cur() and #cur().c or 0 end
_G.GetNumQuestLogRewards = function() return cur() and #cur().r or 0 end
_G.GetQuestLogItemLink = function(kind, i)
  local id = cur() and cur()[kind == "choice" and "c" or "r"][i]
  return id and ("|cff1eff00|Hitem:" .. id .. "::::::::33:::::|h[x]|h|r") or nil
end
_G.GetQuestLogChoiceInfo = function(i) return "名", 1, 1, 2, true end
_G.GetQuestLogRewardInfo = function(i) return "名", 1, 5, 2, true end
_G.InCombatLockdown = function() return false end
SlashCmdList.QUESTMAPGUIDE("probe")
local lr = QuestMapGuideDB.probe.logRewards
H.eq(type(lr), "table", "記錄日誌獎勵")
H.eq(lr[1].q, 96988, "第一個任務")
H.eq(lr[1].nc, 2, "可選獎勵數")
H.eq(lr[1].c[1] .. "," .. lr[1].c[2], "21001,21002", "可選獎勵物品 ID")
H.eq(lr[1].r[1], 21003, "固定獎勵物品 ID")
H.eq(lr[1].rn[1], 5, "固定獎勵數量")
H.eq(lr[2].q, 777, "第二個任務")
H.eq(lr[2].nc, 0, "沒有獎勵記 0")
H.eq(sel, 4242, "取完還原原選取")
-- 戰鬥中不選取（避免動到保護狀態）
_G.InCombatLockdown = function() return true end
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.logRewards, "combat", "戰鬥中記 combat 不讀")
-- 函式不存在
_G.InCombatLockdown = function() return false end
_G.GetNumQuestLogChoices = nil
SlashCmdList.QUESTMAPGUIDE("probe")
H.eq(QuestMapGuideDB.probe.logRewards, "none", "函式不存在記 none")
-- 呼叫出錯：該任務記 err，不中斷
_G.GetNumQuestLogChoices = function() error("boom") end
SlashCmdList.QUESTMAPGUIDE("probe")
H.check(QuestMapGuideDB.probe.logRewards[1].err ~= nil, "呼叫出錯記 err")
H.eq(sel, 4242, "出錯也還原原選取")
for _, k in ipairs({ "GetQuestLogSelection", "SelectQuestLogEntry", "GetNumQuestLogChoices", "GetNumQuestLogRewards",
  "GetQuestLogItemLink", "GetQuestLogChoiceInfo", "GetQuestLogRewardInfo", "InCombatLockdown" }) do _G[k] = nil end
for _, k in ipairs({ "UnitSex", "ITEM_QUALITY_COLORS", "C_Item", "GetMoneyString", "GetQuestLogRewardXP", "C_QuestLog" }) do _G[k] = nil end
