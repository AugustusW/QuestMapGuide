-- 遊戲紀錄（Observe.lua 記錄 → Data.lua 疊加 → 明細標「遊戲紀錄」）
-- fixture：9900005 起點／交任務已知為空（s={}、e={}）、9900001 有內建起點 n9901001 與獎勵、9900004 起點未知
local NPC_GUID = "Creature-0-30277-1-2029810-2986-2A6113A810"   -- 不在 fixture 的 NPC
local KNOWN_GUID = "Creature-0-30277-1-2029810-9901001-2A6113A810" -- fixture 有、帶座標

local function setup()
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local mapId = 1429
  local wm = H.widget("Frame")
  wm.GetMapID = function() return mapId end
  wm.OnMapChanged = function() end
  wm.SetMapID = function(self, id) mapId = id; self.OnMapChanged(self) end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  _G.C_Item = { GetItemInfo = function() end }; H.installed.C_Item = true
  H.now = 1000
  _G.time = function() return H.now end; H.installed.time = true
  -- 任務視窗的遊戲狀態（測試逐步改）
  H.qw = { qid = 9900005, title = "遊戲任務", guid = NPC_GUID, name = "多恩", map = 1500, x = 0.5389, y = 0.4159,
    xp = 3142, money = 0, rewards = {}, choices = {}, level = 30 }
  local qw = H.qw
  local api = {
    GetQuestID = function() return qw.qid end,
    GetTitleText = function() return qw.title end,
    GetObjectiveText = function() return "目標" end,
    GetRewardXP = function() return qw.xp end,
    GetRewardMoney = function() return qw.money end,
    GetNumQuestRewards = function() return #qw.rewards end,
    GetNumQuestChoices = function() return #qw.choices end,
    GetQuestItemLink = function(kind, i)
      local it = (kind == "reward" and qw.rewards or qw.choices)[i]
      return it and ("|cffffffff|Hitem:" .. it[1] .. "::|h[x]|h|r")
    end,
    GetQuestItemInfo = function(kind, i)
      local it = (kind == "reward" and qw.rewards or qw.choices)[i]
      return "x", 1, it and it[2]
    end,
    UnitGUID = function(u) if u == "npc" or u == "questnpc" then return qw.guid end end,
    UnitName = function(u) if u == "npc" or u == "questnpc" then return qw.name end end,
    UnitLevel = function() return qw.level end,
    C_Map = {
      GetMapInfo = function(id) return { mapID = id, mapType = 3, name = "地圖" .. id } end,
      GetBestMapForUnit = function() return qw.map end,
      GetPlayerMapPosition = function() return { GetXY = function() return qw.x, qw.y end } end,
    },
  }
  for k, v in pairs(api) do _G[k] = v; H.installed[k] = true end
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); if ns.Panel.frame then ns.Panel.frame:Show() end
  return ns, wm
end

local function joined(ns) return table.concat(ns.Detail.Lines(), "\n") end
local function has(s, sub) return s:find(sub, 1, true) ~= nil end

-- 1. 記錄：說明視窗記起點與獎勵，交任務視窗記交付
local ns = setup()
H.qw.rewards = { { 6414, 1 } }
H.qw.choices = { { 111, 2 }, { 112, 1 } }
H.fire("QUEST_DETAIL")
H.fire("QUEST_COMPLETE")
local o = QuestMapGuideDB.obs.quests[9900005]
H.check(o ~= nil, "記下任務")
H.eq(QuestMapGuideDB.obs.v, 1, "格式版本 1")
H.eq(o.title, "遊戲任務", "任務名稱")
H.eq(o.starts.c2986.map, 1500, "起點地圖")
H.eq(o.starts.c2986.x, 0.5389, "起點 x")
H.eq(o.starts.c2986.name, "多恩", "起點 NPC 名稱")
H.eq(o.ends.c2986.n, 1, "交任務 1 次")
H.eq(o.rewards.items[6414], 1, "固定獎勵物品")
H.eq(o.rewards.choices[111], 2, "可選獎勵數量")
H.eq(o.rewards.xpLevel, 30, "經驗連同等級")

-- 位置只記第一次
H.qw.x = 0.9
H.fire("QUEST_DETAIL")
H.eq(o.starts.c2986.x, 0.5389, "第二次不覆蓋位置")
H.eq(o.starts.c2986.n, 2, "次數累加")

-- 2. 疊加：內建已知為空的起點／交任務用遊戲紀錄補，明細標「遊戲紀錄」
local q = ns.Data.quest(9900005)
H.eq(q.s and q.s[1], "xc2986@9900005@s", "起點用合成鍵（NPC 不在內建資料）")
H.check(q.obs and q.obs.s and q.obs.e, "標記起點、交任務來自遊戲紀錄")
local e = ns.Data.entity(q.s[1])
H.eq(e and e.n, "多恩", "合成 entity 名稱")
H.eq(e and e.sp[1].m, 1500, "合成 entity 地圖")
H.check(e and math.abs(e.sp[1].x - 53.89) < 1e-9, "座標換成 0–100")
local ids = ns.Data.byMap(1500)
local onMap = false
for _, id in ipairs(ids) do if id == 9900005 then onMap = true end end
H.check(onMap, "遊戲紀錄起點的地圖清單有這個任務")
ns.Detail.Open(9900005)
local txt = joined(ns)
H.check(has(txt, "多恩"), "明細起點顯示 NPC")
H.check(has(txt, "（遊戲紀錄）"), "明細標遊戲紀錄")

-- 3. 內建有值就不動：9900001 起點 n9901001、獎勵物品都在內建
QuestMapGuideDB.obs.quests[9900001] = { title = "x", starts = { c2986 = { kind = "c", id = 2986, name = "多恩", map = 1500, x = 0.1, y = 0.1, n = 1 } },
  rewards = { items = { [999] = 1 } }, nexts = { [9900003] = 1, [9900002] = 1 } }
local q1 = ns.Data.quest(9900001)
H.eq(q1.s[1], "n9901001", "內建起點不被遊戲紀錄蓋過")
H.eq(#q1.s, 1, "內建起點不加遊戲紀錄的 NPC")
H.check(not (q1.obs and q1.obs.ri), "內建獎勵物品不被蓋過")
H.check(q1.obs and q1.obs.next and q1.obs.next[9900003] and not q1.obs.next[9900002], "後續取聯集，只標新增的")
H.eq(q1.n.zh, "測試任務一", "內建名稱不變")

-- 4. 起點 NPC 在內建資料且有座標：用內建鍵
QuestMapGuideDB.obs.quests[9900004] = { title = "y", starts = { c9901001 = { kind = "c", id = 9901001, name = "村長", map = 1429, x = 0.2, y = 0.2, n = 1 } } }
H.eq(ns.Data.quest(9900004).s[1], "n9901001", "內建有座標的 NPC 用內建鍵")

-- 5. 內建沒有的任務：由紀錄合成，搜尋清單看得到
QuestMapGuideDB.obs.quests[77777] = { title = "新任務", starts = { c2986 = { kind = "c", id = 2986, name = "多恩", map = 1500, x = 0.3, y = 0.3, n = 1 } } }
local q7 = ns.Data.quest(77777)
H.check(q7 and q7.obsOnly, "內建沒有的任務由紀錄合成")
H.eq(q7 and q7.n.zh, "新任務", "合成任務名稱")
local found = false
for _, id in ipairs(ns.Data.questIds()) do if id == 77777 then found = true end end
H.check(found, "questIds 含紀錄任務")
H.check(ns.Data.quest(88888) == nil, "內建與紀錄都沒有回 nil")

-- 6. 後續：交任務後 5 秒內同一 NPC 打開的說明
ns = setup()
H.qw.qid = 1151; H.fire("QUEST_DETAIL"); H.fire("QUEST_COMPLETE"); H.fire("QUEST_TURNED_IN", 1151, 3141, 0)
H.qw.qid = 1152; H.fire("QUEST_DETAIL")
H.eq(QuestMapGuideDB.obs.quests[1151].nexts[1152], 1, "同 NPC 立刻出現的任務算後續")
H.now = H.now + 100
H.qw.qid = 1151; H.fire("QUEST_TURNED_IN", 1151, 0, 0)
H.now = H.now + 6
H.qw.qid = 1153; H.fire("QUEST_DETAIL")
H.check(QuestMapGuideDB.obs.quests[1151].nexts[1153] == nil, "超過 5 秒不算後續")
H.qw.qid = 1151; H.fire("QUEST_TURNED_IN", 1151, 0, 0)
H.qw.guid = KNOWN_GUID; H.qw.qid = 1154; H.fire("QUEST_DETAIL")
H.check(QuestMapGuideDB.obs.quests[1151].nexts[1154] == nil, "不同 NPC 不算後續")

-- 7. 保密值：任何一個是保密值就不記那一項，也不出錯
ns = setup()
local function trap() error("touched secret") end
local SECRET = setmetatable({}, { __index = trap, __newindex = trap, __eq = trap, __lt = trap, __le = trap,
  __len = trap, __concat = trap, __call = trap, __tostring = trap })
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
H.qw.guid = SECRET; H.qw.map = SECRET
H.fire("QUEST_DETAIL")
local s7 = QuestMapGuideDB.obs.quests[9900005]
H.check(s7 ~= nil and s7.title == "遊戲任務", "保密 NPC／地圖時仍記任務")
H.check(s7.starts == nil, "保密 NPC 不記起點")
H.qw.qid = SECRET
H.fire("QUEST_DETAIL")
H.check(true, "保密 questId 不出錯")
H.printed = {}
