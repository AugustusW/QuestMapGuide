-- ns.Data 讀取 API（資料用 fixture，不用正式 Data）
local function setup()
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  return H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
end

local ns = setup()
local D = ns.Data
H.eq(type(D), "table", "ns.Data 存在")
for _, fn in ipairs({ "quest", "entity", "byMap", "spawns", "questIds", "entityKeys" }) do
  H.eq(type(D[fn]), "function", "Data." .. fn)
end

-- quest：內容與舊格式一致
local q = D.quest(9900001)
H.eq(q.n.zh, "測試任務一", "n.zh")
H.eq(q.n.en, "Test Quest One", "n.en")
H.eq(q.lv, 7, "lv"); H.eq(q.min, 5, "min"); H.eq(q.f, "A", "f")
H.eq(q.cls[2], 2, "cls"); H.eq(#q.race, 2, "race")
H.eq(q.sk[1], 164, "sk[1]"); H.eq(q.sk[2], 25, "sk[2]")
H.eq(q.maps[2], 1453, "maps"); H.eq(q.s[1], "n9901001", "s"); H.eq(q.e[1], "o9901001", "e")
H.eq(#q.prev, 0, "prev={} 已知為空"); H.eq(q.next[1], 9900002, "next")
H.eq(q.ri[2][1], 12346, "ri[2][1]"); H.eq(q.ri[2][3], true, "ri choice")
H.eq(q.xp, 450, "xp"); H.eq(q.cu, 1200, "cu"); H.eq(q.t, 0, "t")
H.eq(q.conc, nil, "沒有的欄位是 nil（未知）")

-- null 語意：缺欄位 = nil、{} = 已知為空、位置式 nil 保留
local u = D.quest(9900004)
H.eq(u.s, nil, "s 缺＝未知"); H.eq(u.ri, nil, "ri 缺＝未知"); H.eq(u.xp, nil, "xp 缺＝未知")
H.eq(type(D.quest(9900003).s), "table", "s={} 是表")
H.eq(next(D.quest(9900003).s), nil, "s={} 是空表")
local nul = D.quest(9900005)
H.eq(nul.sk[1], 171, "sk[1]"); H.eq(nul.sk[2], nil, "sk[2] nil 保留")
H.eq(nul.ri[1][1], 159, "ri[1][1]"); H.eq(nul.ri[1][2], nil, "ri[1][2] nil 保留"); H.eq(nul.ri[1][3], true, "ri[1][3]")
H.eq(nul.ri[2][2], 3, "ri[2][2]"); H.eq(nul.ri[2][3], false, "ri[2][3] false 不是 nil")

-- 描述組 d：desc(id) 回原字串；沒描述 nil；任務記錄不含描述
H.eq(type(D.desc), "function", "Data.desc")
H.eq(D.desc(9900001), '甲\n他說：「"快來"」\n乙\\丙', "desc 含換行、雙引號、反斜線")
H.eq(D.desc(9900002), "Plain English description.", "desc 英文")
H.eq(D.desc(9900003), nil, "description null → nil")
H.eq(D.desc(9900004), nil, "缺描述 → nil")
H.eq(D.desc(1), nil, "沒有的任務 desc nil"); H.eq(D.desc(nil), nil, "nil id 不爆")
H.eq(D.quest(9900001).description, nil, "任務記錄沒有 description")
H.eq(D.quest(9900001).d, nil, "任務記錄沒有 d")

-- 搜尋不碰描述：用同一份資料跑一次搜尋，描述解碼計數仍為 0
do
  local nsS = setup()
  H.eq(type(nsS.Data.DescDecodes), "function", "Data.DescDecodes 測試用計數器存在")
  H.eq(nsS.Data.DescDecodes(), 0, "載入後 0")
  for _, id in ipairs(nsS.Data.questIds()) do
    local rec = nsS.Data.quest(id)
    nsS.Filter.visible(id, {}, rec)
  end
  H.eq(nsS.Data.DescDecodes(), 0, "搜尋與讀任務記錄不解碼描述")
  nsS.Data.desc(9900001); nsS.Data.desc(9900001); nsS.Data.desc(9900004)
  H.eq(nsS.Data.DescDecodes(), 2, "只在 desc 時解碼，缺的不算")
end

-- 不存在
H.eq(D.quest(1), nil, "沒有的 quest 回 nil")
H.eq(D.quest("9900001"), nil, "字串 id 不算")
H.eq(D.quest(nil), nil, "nil id 不爆")
H.eq(D.entity("n1"), nil, "沒有的 entity 回 nil")
H.eq(D.entity(9901001), nil, "entity 鍵要有 n／o 前綴")

-- entity
local e = D.entity("n9901001")
H.eq(e.n, "Fixture \"Quoter\" NPC", "entity 名稱（含引號）")
H.eq(#e.sp, 2, "兩個 spawn")
H.eq(e.sp[1].m, 1429, "sp.m"); H.eq(e.sp[1].x, 45.3, "sp.x"); H.eq(e.sp[1].y, 60.1, "sp.y")
H.eq(e.sp[2].x, 12, "整數 x"); H.eq(D.entity("o9901001").n, "Fixture Object", "object 與 npc 同 id 不撞")

-- byMap：每次回新表，改它不影響資料
local b = D.byMap(1453)
H.eq(#b, 2, "1453 兩筆"); H.eq(b[1], 9900001, "byMap[1]"); H.eq(b[2], 9900002, "byMap[2]")
b[1] = 0
H.eq(D.byMap(1453)[1], 9900001, "byMap 回傳可改，不影響資料")
H.eq(#D.byMap(1500), 0, "沒收錄的地圖回空表")
H.eq(#D.byMap(nil), 0, "nil 地圖回空表")

-- spawns：只回指定地圖上的 x, y
local pts = {}
for x, y in D.spawns("n9901001", 1453) do pts[#pts + 1] = x .. "," .. y end
H.eq(table.concat(pts, ";"), "12,80", "spawns 只有該地圖")
pts = {}
for x, y in D.spawns("n9901001", 1429) do pts[#pts + 1] = x .. "," .. y end
H.eq(table.concat(pts, ";"), "45.3,60.1", "spawns 1429")
pts = {}
for x, y in D.spawns("n9901001") do pts[#pts + 1] = x .. "," .. y end
H.eq(#pts, 2, "不指定地圖回全部")
pts = {}
for x, y in D.spawns("n9901001", 9999) do pts[#pts + 1] = 1 end
H.eq(#pts, 0, "該地圖沒有就不迭代")
for _ in D.spawns("n404", 1429) do H.check(false, "沒有的 entity 不迭代") end

-- 列舉
local ids = D.questIds()
H.eq(#ids, 5, "五個任務"); H.eq(ids[1], 9900001, "遞增"); H.eq(ids[5], 9900005, "遞增 5")
H.eq(#D.entityKeys(), 2, "兩個 entity")

-- 沒有資料時（例如只載入程式碼）：全部回空，不爆
H.reset({ locale = "zhTW" })
QMG_Data = nil
local ns2 = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(ns2.Data.quest(9900001), nil, "沒資料 quest nil")
H.eq(#ns2.Data.byMap(1429), 0, "沒資料 byMap 空")
H.eq(#ns2.Data.questIds(), 0, "沒資料 questIds 空")

-- 格式版本不符：當作沒資料，不誤讀
H.reset({ locale = "zhTW" })
dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
QMG_Data.fmt = 999
local ns3 = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(ns3.Data.quest(9900001), nil, "fmt 不符回 nil")
QMG_Data = nil

-- entity 每次回傳新表：呼叫端改了不影響下一次（Task 5 review 留下的共用快取問題）
local e1 = D.entity("n9901001")
e1.n = "被改過"; e1.sp[1].x = -1
local e2 = D.entity("n9901001")
H.eq(e2.n, "Fixture \"Quoter\" NPC", "entity 改動不影響下次讀取")
H.eq(e2.sp[1].x, 45.3, "entity 內層表改動不影響下次讀取")
H.check(D.entity("n9901001") ~= D.entity("n9901001"), "entity 每次回新表")
-- spawns 也接受 entity 表（呼叫端已解出 entity 時不重複解碼）
local pts2 = {}
for x, y in D.spawns(D.entity("n9901001"), 1453) do pts2[#pts2 + 1] = x .. "," .. y end
H.eq(table.concat(pts2, ";"), "12,80", "spawns 接受 entity 表")

-- 索引長度與資料字串不符：視為壞資料、回空（不讀出錯位的記錄）
QMG_Data = { fmt = 1, q = { ix = "1:5,2:5", s = "{n={}}" }, e = { ix = "", s = "" }, m = { ix = "", s = "" } }
local nsBad = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(nsBad.Data.quest(1), nil, "索引長度與資料不符時回 nil")
H.eq(#nsBad.Data.questIds(), 0, "索引長度與資料不符時沒有任何 id")
