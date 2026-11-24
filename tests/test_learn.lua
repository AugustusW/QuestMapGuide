-- NPC 名稱學習：滑鼠指向／目標時記下繁中名稱（帳號共用），顯示優先序 內建繁中 → 學到 → 英文
local NPC = 9901001  -- fixture 內的 npc（n9901001）
local GUID = "Creature-0-4379-1-12-" .. NPC .. "-0000ABCDEF"

local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  H.now = 1000
  if not opts.keepZh then
    -- fixture 的 n9901001 帶內建繁中名稱；學習測試要用「沒有內建繁中」的 NPC，所以預設拿掉 zh
    local orig = ns.Data.entity
    ns.Data.entity = function(k) local e = orig(k); if e then e.zh = nil end return e end
  end
  _G.time = function() return H.now end; H.installed.time = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true  -- 預設：有 API 且不保密
  return ns
end
local function unit(guid, name)
  _G.UnitGUID = function() return guid end
  _G.UnitName = function() return name end
  H.installed.UnitGUID = true; H.installed.UnitName = true
end
local function trap() error("touched secret") end
local SECRET = setmetatable({}, { __index = trap, __newindex = trap, __eq = trap, __lt = trap, __le = trap,
  __len = trap, __concat = trap, __call = trap, __tostring = trap })
local function secretApi() _G.issecretvalue = function(v) return rawequal(v, SECRET) end; H.installed.issecretvalue = true end

-- 基本記錄
local ns = setup()
H.eq(type(ns.Learn.onUnit), "function", "Learn.onUnit 存在")
H.eq(type(QuestMapGuideDB.npcNames), "table", "存檔預設有 npcNames")
unit(GUID, "測試村長")
ns.Learn.onUnit("mouseover")
local r = QuestMapGuideDB.npcNames[NPC]
H.check(r ~= nil, "記下名稱")
H.eq(r and r.name, "測試村長", "name")
H.eq(r and r.seen, 1, "seen=1")
H.eq(r and r.first, 1000, "first")
H.eq(r and r.last, 1000, "last")
local keys = 0
for _ in pairs(r) do keys = keys + 1 end
H.eq(keys, 4, "只有 name/seen/first/last 四個欄位")

-- 節流：60 秒內不再寫
H.now = 1030
ns.Learn.onUnit("target")
H.eq(QuestMapGuideDB.npcNames[NPC].seen, 1, "60 秒內 seen 不增加")
H.eq(QuestMapGuideDB.npcNames[NPC].last, 1000, "60 秒內 last 不變")
H.now = 1061
ns.Learn.onUnit("target")
H.eq(QuestMapGuideDB.npcNames[NPC].seen, 2, "過節流窗 seen=2")
H.eq(QuestMapGuideDB.npcNames[NPC].last, 1061, "last 更新")
H.eq(QuestMapGuideDB.npcNames[NPC].first, 1000, "first 不變")

-- 名稱改變：覆蓋
H.now = 1200
unit(GUID, "新村長")
ns.Learn.onUnit("mouseover")
H.eq(QuestMapGuideDB.npcNames[NPC].name, "新村長", "名稱改變時覆蓋")

-- 事件接線
ns = setup()
unit(GUID, "事件村長")
H.fire("UPDATE_MOUSEOVER_UNIT")
H.eq(QuestMapGuideDB.npcNames[NPC] and QuestMapGuideDB.npcNames[NPC].name, "事件村長", "UPDATE_MOUSEOVER_UNIT 觸發記錄")
ns = setup()
unit(GUID, "目標村長")
H.fire("PLAYER_TARGET_CHANGED")
H.eq(QuestMapGuideDB.npcNames[NPC] and QuestMapGuideDB.npcNames[NPC].name, "目標村長", "PLAYER_TARGET_CHANGED 觸發記錄")

-- 非 zhTW 不寫
ns = setup({ locale = "enUS" })
unit(GUID, "Mayor")
ns.Learn.onUnit("mouseover")
H.eq(next(QuestMapGuideDB.npcNames), nil, "enUS 客戶端不寫")

-- 非 Creature
for _, g in ipairs({ "Vehicle-0-4379-1-12-" .. NPC .. "-0000ABCDEF", "Pet-0-4379-1-12-" .. NPC .. "-0000ABCDEF",
  "Player-4379-0000ABCD", "Creature-0-4379-1-12-" .. NPC, "garbage" }) do
  ns = setup()
  unit(g, "X")
  ns.Learn.onUnit("mouseover")
  H.eq(next(QuestMapGuideDB.npcNames), nil, "非 Creature／格式不符不寫：" .. g)
end

-- 資料裡沒有的 npc
ns = setup()
unit("Creature-0-4379-1-12-8888888-0000ABCDEF", "路人")
ns.Learn.onUnit("mouseover")
H.eq(next(QuestMapGuideDB.npcNames), nil, "資料沒有的 npc 不寫")

-- 空名稱／非字串
ns = setup()
unit(GUID, "")
ns.Learn.onUnit("mouseover")
unit(GUID, nil)
ns.Learn.onUnit("mouseover")
H.eq(next(QuestMapGuideDB.npcNames), nil, "空名稱不寫")

-- 保密值：guid 或 name 任一保密都不寫、不碰、不報錯
for _, case in ipairs({ { SECRET, "名字" }, { GUID, SECRET }, { SECRET, SECRET } }) do
  ns = setup()
  secretApi()
  unit(case[1], case[2])
  local ok, err = pcall(ns.Learn.onUnit, "mouseover")
  H.check(ok, "保密值不報錯：" .. tostring(err))
  H.eq(next(QuestMapGuideDB.npcNames), nil, "保密值不寫入")
  H.fire("UPDATE_MOUSEOVER_UNIT")  -- 經事件也不報錯（H.printed 掃 handler 錯誤）
end
-- 沒有 issecretvalue：無法確認就不寫
ns = setup()
_G.issecretvalue = nil
unit(GUID, "無保密 API")
ns.Learn.onUnit("target")
H.eq(next(QuestMapGuideDB.npcNames), nil, "沒有 issecretvalue 時不記錄（fail-closed）")

-- 沒有 UnitGUID／存檔未建立不報錯
ns = setup()
_G.UnitGUID, _G.UnitName = nil, nil
H.check(pcall(ns.Learn.onUnit, "mouseover"), "沒有 UnitGUID 不報錯")
unit(GUID, "X")
local saved = QuestMapGuideDB; QuestMapGuideDB = nil
H.check(pcall(ns.Learn.onUnit, "mouseover"), "存檔未建立不報錯")
QuestMapGuideDB = saved

-- 顯示優先序
ns = setup()
secretApi()
local key = "n" .. NPC
local en, lang = ns.Data.npcName(key)
H.eq(lang, "en", "沒學到：英文")
H.eq(en, ns.Data.entity(key).n, "沒學到：回英文名")
unit(GUID, "學到的名")
ns.Learn.onUnit("mouseover")
local nm, l2 = ns.Data.npcName(key)
H.eq(nm, "學到的名", "學到後回學到的名")
H.eq(l2, "learned", "lang=learned")
-- 內建繁中優先（資料日後帶 zh）
local ent = ns.Data.entity(key)
local orig = ns.Data.entity
ns.Data.entity = function(k) local e = orig(k); if e and k == key then return setmetatable({ zh = "內建名" }, { __index = e }) end return e end
local nm3, l3 = ns.Data.npcName(key)
H.eq(nm3, "內建名", "內建繁中優先")
H.eq(l3, "zh", "lang=zh")
ns.Data.entity = orig
H.eq(select(1, ns.Data.npcName("n1")), nil, "不存在的 entity 回 nil")

-- 搜尋：顯示名稱與英文名都要能搜到；學到新名稱後索引更新
local function found(P, q)
  P.SetSearch(q)
  for _, r in ipairs(P.Rows()) do if r.questId == 9900001 then return true end end
  return false
end
for _, mapId in ipairs({ 1429, 1500 }) do  -- 1429：這張地圖上的任務；1500：走全域搜尋索引
  ns = setup()
  local P = ns.Panel
  P.Refresh(mapId)
  H.check(found(P, "quoter"), "學到前搜英文名 map " .. mapId)
  H.check(not found(P, "新村民"), "學到前搜中文名找不到 map " .. mapId)
  unit(GUID, "新村民")
  ns.Learn.onUnit("mouseover")  -- 索引已建好後學到新名稱
  H.check(found(P, "新村民"), "學到後搜中文名找得到（索引已更新）map " .. mapId)
  H.check(found(P, "quoter"), "學到後搜英文名仍找得到 map " .. mapId)
  H.now = 2000
  unit(GUID, "改名村民")
  ns.Learn.onUnit("mouseover")
  H.check(found(P, "改名村民"), "名稱改變後搜新名稱 map " .. mapId)
  H.check(not found(P, "新村民"), "名稱改變後舊名稱找不到 map " .. mapId)
end
-- seen 增加但名稱沒變：不重建索引
ns = setup()
ns.Panel.Refresh(1500); ns.Panel.SetSearch("quoter")
unit(GUID, "村民"); ns.Learn.onUnit("mouseover")
local b = ns.Panel.IndexBuilds()
ns.Panel.SetSearch("村民"); ns.Panel.SetSearch("quoter")
H.eq(ns.Panel.IndexBuilds(), b + 1, "學到新名稱後索引重建一次")
H.now = 3000; ns.Learn.onUnit("mouseover")
ns.Panel.SetSearch("村民")
H.eq(ns.Panel.IndexBuilds(), b + 1, "名稱沒變時不重建索引")

-- I1：內建繁中名稱只在 zhTW 客戶端使用；學到的名稱同樣只在 zhTW 顯示
ns = setup({ keepZh = true })
local nmz, lz = ns.Data.npcName("n9901001")
H.eq(nmz, "測試NPC", "zhTW：內建繁中名稱")
H.eq(lz, "zh", "zhTW：lang=zh")
H.eq(select(3, ns.Data.npcName("n9901001")), "Fixture \"Quoter\" NPC", "第三個回傳值是英文名")
local pre = ns.Data.entity("n9901001")
H.eq(select(1, ns.Data.npcName("n9901001", pre)), "測試NPC", "傳入已解碼的 entity 表")
H.eq(select(1, ns.Data.npcName(pre)), "測試NPC", "第一個參數直接是 entity 表")
ns = setup({ locale = "enUS", keepZh = true })
local nme, le = ns.Data.npcName("n9901001")
H.eq(nme, "Fixture \"Quoter\" NPC", "enUS：英文名（不用內建繁中）")
H.eq(le, "en", "enUS：lang=en")
-- enUS 客戶端即使存檔裡有學到的名稱也不顯示
ns = setup({ locale = "enUS" })
QuestMapGuideDB.npcNames[NPC] = { name = "學到的名", seen = 1, first = 1, last = 1 }
H.eq(ns.Data.npcName("n9901001"), "Fixture \"Quoter\" NPC", "enUS：學到的名稱不顯示")
ns = setup()
QuestMapGuideDB.npcNames[NPC] = { name = "學到的名", seen = 1, first = 1, last = 1 }
H.eq(ns.Data.npcName("n9901001"), "學到的名", "zhTW：同一份存檔顯示學到的名稱")

-- M4：改名後當成新紀錄（seen=1、first=now）
ns = setup()
unit(GUID, "舊名"); ns.Learn.onUnit("mouseover")
H.now = 1061; ns.Learn.onUnit("mouseover")
H.eq(QuestMapGuideDB.npcNames[NPC].seen, 2, "改名前 seen=2")
H.now = 1200; unit(GUID, "新名"); ns.Learn.onUnit("mouseover")
local rr = QuestMapGuideDB.npcNames[NPC]
H.eq(rr.name, "新名", "改名：name")
H.eq(rr.seen, 1, "改名：seen 重設為 1")
H.eq(rr.first, 1200, "改名：first = now")
H.eq(rr.last, 1200, "改名：last = now")

-- M3：節流命中、索引裡沒有時都不解碼 entity
ns = setup()
local decodes = 0
local origEnt = ns.Data.entity
ns.Data.entity = function(k) decodes = decodes + 1; return origEnt(k) end
unit(GUID, "村長"); ns.Learn.onUnit("mouseover")
H.eq(decodes, 0, "學習路徑不解碼 entity（只查索引）")
H.now = 1010; ns.Learn.onUnit("mouseover"); ns.Learn.onUnit("target")
H.eq(decodes, 0, "節流命中不解碼")
unit("Creature-0-4379-1-12-8888888-0000ABCDEF", "路人"); ns.Learn.onUnit("mouseover")
H.eq(decodes, 0, "索引沒有的 npc 不解碼")
H.check(ns.Data.hasEntity("n9901001") and not ns.Data.hasEntity("n8888888") and not ns.Data.hasEntity(nil), "hasEntity 只查索引")
