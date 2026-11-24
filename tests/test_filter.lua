-- 篩選、等級顏色、前置／同組淡化、分頁與搜尋。資料用 fixture：
--   9900001 lv7 min5 f=A cls{1,2} sk{164,25} excl{9900003}（1429、1453）
--   9900002 lv8 min6 f=H prev{9900001}（1453）
--   9900003 lv1 min1 無地圖
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 日誌 questId 要過保密檢查（fail-closed）
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local S = { completed = opts.completed or {}, log = {}, level = opts.level or 10 }
  _G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return S.completed[id] == true end,
    GetNumQuestLogEntries = function() return #S.log, #S.log end,
    GetInfo = function(i) return S.log[i] end,
    GetAllCompletedQuestIDs = function()
      local t = {}
      for id in pairs(S.completed) do t[#t + 1] = id end
      return t
    end,
  }
  S.timers = {}
  _G.C_Timer = { After = function(d, fn) S.timers[#S.timers + 1] = { d = d, fn = fn } end }
  function S.flush() local t = S.timers; S.timers = {}; for _, x in ipairs(t) do x.fn() end end
  if not opts.noPlayer then
    S.faction = opts.faction or "Alliance"
    S.classId = opts.classId or 1
    S.raceId = opts.raceId or 1
    _G.UnitRace = function() return "x", "X", S.raceId end
    S.profs = opts.profs or { { 164, 100 } }   -- { skillLine, rank }
    _G.UnitLevel = function() return S.level end
    _G.UnitFactionGroup = function() return S.faction, S.faction end
    _G.UnitClass = function() return "x", "X", S.classId end
    _G.GetProfessions = function() local t = {}; for i = 1, #S.profs do t[i] = i end; return unpack(t) end
    _G.GetProfessionInfo = function(i)
      local p = S.profs[i]
      return "name" .. i, "icon", p[2], 300, 0, 0, p[1]
    end
    _G.GetQuestDifficultyColor = function(lv) return { r = 0.1, g = 0.9, b = lv / 100 } end
  end
  for _, k in ipairs({ "C_QuestLog", "C_Timer", "UnitLevel", "UnitFactionGroup", "UnitClass", "GetProfessions",
    "GetProfessionInfo", "GetQuestDifficultyColor", "UnitRace" }) do H.installed[k] = true end
  local wm = H.widget("Frame")
  wm.GetMapID = function() return opts.map or 1453 end
  wm:Show()
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = opts.mapType or 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  H.fire("PLAYER_LOGIN")
  return ns, S
end
local function ids(rows) local t = {} for i, r in ipairs(rows) do t[i] = r.questId end return t end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local ns, S = setup()
local F = ns.Filter
H.eq(type(F), "table", "ns.Filter 存在")

-- 陣營：預設排除另一陣營，取消勾選後出現
local ok, why = F.visible(9900002)
H.eq(ok, false, "另一陣營預設不出現")
H.eq(why, "faction", "原因是 faction")
H.eq((F.visible(9900001)), true, "同陣營出現")
H.eq((F.visible(9900002, { exclFaction = false })), true, "opts 取消排除後出現")
ns.Panel.Refresh(1453)
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "面板預設不列另一陣營任務")
F.set("exclFaction", false)
ns.Panel.Refresh(1453)
H.check(same(ids(ns.Panel.Rows()), { 9900001, 9900002 }), "取消勾選後面板列出")
H.eq(QuestMapGuideCharDB.filter.exclFaction, false, "勾選狀態存在角色存檔")
H.eq(F.get("exclClass"), true, "預設三個排除全勾")
H.eq(F.get("exclProf"), true, "專業預設勾")
H.eq(F.get("showDone"), false, "顯示已完成預設不勾")

-- 職業
ns, S = setup({ classId = 5 }); F = ns.Filter
ok, why = F.visible(9900001)
H.eq(ok, false, "其他職業預設不出現"); H.eq(why, "class", "原因 class")
H.eq((F.visible(9900003)), true, "cls 為空＝所有職業")
H.eq((F.visible(9900004)), true, "cls 缺＝未知，不檢查")
H.eq((F.visible(9900001, { exclClass = false })), true, "取消排除其他職業")

-- 專業：沒有該專業排除；有但點數不足列出並標
ns, S = setup({ profs = {} }); F = ns.Filter
ok, why = F.visible(9900001)
H.eq(ok, false, "沒有該專業預設不出現"); H.eq(why, "profession", "原因 profession")
H.eq((F.visible(9900001, { exclProf = false })), true, "取消排除其他專業")
ns, S = setup({ profs = { { 164, 10 } } }); F = ns.Filter
H.eq((F.visible(9900001)), true, "有專業但點數不足仍列出")
H.eq(F.profLow(9900001), true, "標記專業不足")
ns.Panel.Refresh(1429)
H.eq(ns.Panel.Rows()[1].profLow, true, "列帶 profLow")
ns, S = setup({ profs = { { 164, 25 } } }); F = ns.Filter
H.eq(F.profLow(9900001), false, "點數剛好足夠不標")
ns, S = setup({ profs = { { 171, 50 } } }); F = ns.Filter
H.eq(F.profLow(9900005), false, "要求點數未知（nil）不標")
-- GetProfessionInfo 沒回 skillLine：不確定就不排除
ns, S = setup(); F = ns.Filter
_G.GetProfessionInfo = function() return "n", "i", 5 end
ns.Panel.Refresh(1429)
H.eq((F.visible(9900001)), true, "取不到 skillLine 時不排除")

-- 取不到玩家資訊（API 缺）：什麼都不排除
ns, S = setup({ noPlayer = true }); F = ns.Filter
H.eq((F.visible(9900002)), true, "沒有 UnitFactionGroup 不排除")
H.eq((F.visible(9900001)), true, "沒有 UnitClass 不排除")
local r, g = F.color(9900001)
H.eq(type(r), "number", "沒有 GetQuestDifficultyColor 仍回顏色")

-- 等級顏色
ns, S = setup({ level = 3 }); F = ns.Filter
r, g = F.color(9900001)
H.eq(r, 1, "未達可接等級紅色 r"); H.check(g < 0.2, "未達可接等級紅色 g")
ns, S = setup({ level = 10 }); F = ns.Filter
local _, g2, b2 = F.color(9900001)
H.eq(g2, 0.9, "達到等級用 GetQuestDifficultyColor（g）")
H.eq(b2, 0.07, "用 questLevel 查顏色（b = lv/100）")
ns.Panel.Refresh(1429)
local row = ns.Panel.Rows()[1]
H.eq(row.r, 0.1, "列帶顏色 r"); H.eq(row.lv, 7, "列帶等級")

-- 前置：未完成淡化並帶名稱
ns, S = setup(); F = ns.Filter
local d = F.dim(9900002)
H.eq(d and d.kind, "prereq", "前置未完成淡化"); H.eq(d and d.name, "測試任務一", "帶前置名稱（zhTW）")
H.eq(F.dim(9900001), nil, "沒有前置不淡化")
S.completed[9900001] = true; H.fire("PLAYER_ENTERING_WORLD")
H.eq(F.dim(9900002), nil, "前置完成後不淡化")
ns, S = setup({ locale = "enUS" }); F = ns.Filter
H.eq(F.dim(9900002).name, "Test Quest One", "enUS 用英文名")
H.eq(ns.L("needPrereq"), "Need to complete first: %s", "enUS 文案")
-- 前置不在資料裡：不檢查
local realQuest = ns.Data.quest
ns.Data.quest = function(id)
  local q = realQuest(id)
  if id == 9900002 then q.prev = { 777 } end
  return q
end
H.eq(F.dim(9900002), nil, "前置不在資料裡不檢查")
-- 淡化只對可接的；進行中的不淡化
ns, S = setup(); F = ns.Filter
S.log = { { questID = 9900002 } }; H.fire("QUEST_ACCEPTED", 1, 9900002)
H.eq(F.dim(9900002), nil, "進行中不淡化")

-- 同組擇一：已完成其中一個，其他淡化
ns, S = setup({ completed = { [9900003] = true } }); F = ns.Filter
d = F.dim(9900001)
H.eq(d and d.kind, "group", "同組已完成其中一個 → 淡化"); H.eq(d and d.name, "無地圖任務", "帶同組任務名稱")
H.eq(ns.L("doneGroup"), "已完成同組任務：%s", "zhTW 文案")
H.eq(ns.L("needPrereq"), "需先完成：%s", "zhTW 前置文案")
H.eq(ns.L("profLow"), "專業不足", "zhTW 專業不足")

-- 淡化的不算「可接 N」
ns, S = setup(); F = ns.Filter
F.set("exclFaction", false)
ns.Panel.Refresh(1453)
local c = ns.Panel.Counts()
H.eq(c.open, 1, "可接 N 不含淡化的（9900002 被前置淡化）")
H.eq(c.openAll, 2, "未接分頁數字含淡化的")
H.eq(c.all, 2, "全部 2")
H.eq(ns.Panel.Rows()[2].dim.kind, "prereq", "列帶 dim")
H.eq(ns.Panel.Rows()[2].dimText, "需先完成：測試任務一", "列帶淡化文字")

-- 分頁與計數
ns, S = setup(); F = ns.Filter
F.set("exclFaction", false)
S.log = { { questID = 9900001 } }; H.fire("QUEST_ACCEPTED", 1, 9900001)
S.completed[9900002] = true; H.fire("QUEST_TURNED_IN", 9900002)
ns.Panel.Refresh(1453)
c = ns.Panel.Counts()
H.eq(c.log, 1, "日誌 1"); H.eq(c.done, 1, "完成 1"); H.eq(c.open, 0, "可接 0")
H.eq(ns.Panel.Tab(), "open", "預設分頁未接")
H.eq(#ns.Panel.Rows(), 0, "未接分頁：進行中與已完成都不在")
ns.Panel.SetTab("all")
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "全部分頁預設不含已完成")
ns.Panel.SetTab("done")
H.check(same(ids(ns.Panel.Rows()), { 9900002 }), "已完成分頁列已完成")
H.eq(QuestMapGuideCharDB.filter.tab, "done", "分頁存在角色存檔")
ns.Panel.SetTab("log")
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "日誌中分頁")
ns.Panel.SetTab("open")
H.eq(#ns.Panel.Rows(), 0, "未接分頁空")
H.eq(ns.Panel.Message(), "這張地圖沒有未完成的任務", "空分頁有訊息")
ns.Panel.SetTab("all")
F.set("showDone", true)
ns.Panel.Refresh(1453)
H.check(same(ids(ns.Panel.Rows()), { 9900001, 9900002 }), "顯示已完成勾選後全部分頁含已完成")
ns.Panel.SetTab("bogus")
H.eq(ns.Panel.Tab(), "open", "不認得的分頁退回未接")

-- 搜尋：任務名稱（中英）與 NPC 名稱
ns, S = setup(); F = ns.Filter
F.set("exclFaction", false)
ns.Panel.Refresh(1453)
ns.Panel.SetSearch("quoter")
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "搜尋 NPC 名稱（不分大小寫）")
ns.Panel.SetSearch("Only English")
H.check(same(ids(ns.Panel.Rows()), { 9900002 }), "搜尋任務英文名")
ns.Panel.SetSearch("測試")
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "搜尋任務中文名")
ns.Panel.SetSearch("zzz")
H.eq(#ns.Panel.Rows(), 0, "搜尋無結果")
H.eq(ns.Panel.Counts().all, 2, "搜尋不影響計數")
ns.Panel.SetSearch("")
H.eq(#ns.Panel.Rows(), 2, "清空搜尋還原")
ns.Panel.SetSearch("%")
H.check(pcall(ns.Panel.Refresh, 1453), "搜尋字串含 pattern 字元不報錯")

-- 介面：frame 只在 ADDON_LOADED 建立；換分頁、勾選都不新增
ns, S = setup(); F = ns.Filter
local n0 = #H.frames
ns.Panel.SetTab("log"); ns.Panel.SetSearch("x"); F.set("exclClass", false); ns.Panel.Refresh(1453)
H.eq(#H.frames, n0, "操作不建立新 frame")
H.check(n0 > 13, "面板有搜尋框、勾選框、分頁按鈕")

-- 回歸：大陸／世界地圖仍顯示放大提示
ns, S = setup({ map = 1414, mapType = 2 })
ns.Panel.Refresh(1414)
H.eq(ns.Panel.Message(), "放大到區域地圖查看任務", "大陸地圖提示不變")
H.eq(#ns.Panel.Rows(), 0, "大陸地圖不列任務")

-- 控制項：勾選框、分頁按鈕、搜尋框的 script 真的接到 Panel
ns, S = setup()
ns.Panel.Refresh(1453)
local checks, tabs, edit = {}, {}, nil
for _, f in ipairs(H.frames) do
  if f._kind == "CheckButton" then checks[#checks + 1] = f
  elseif f._kind == "Button" and f.tab then tabs[#tabs + 1] = f
  elseif f._kind == "EditBox" then edit = f end
end
H.eq(#checks, 5, "五個勾選框"); H.eq(#tabs, 4, "四個分頁按鈕"); H.check(edit ~= nil, "有搜尋框")
for _, c in ipairs(checks) do if c.key == "exclFaction" then c._scripts.OnClick(c) end end
H.eq(type(QuestMapGuideCharDB.filter.exclFaction), "boolean", "點勾選框寫進角色存檔")
tabs[2]._scripts.OnClick(tabs[2])
H.eq(ns.Panel.Tab(), "log", "點分頁切換")
edit:SetText("quoter"); edit._scripts.OnTextChanged(edit)
S.flush()
H.eq(#ns.Panel.Rows(), 0, "搜尋框輸入後套用（日誌中分頁沒有符合的）")

-- 種族（跟陣營排除同一個勾選）：race 非空且不含玩家種族才排除；race={} 與缺都不排除
ns, S = setup({ raceId = 2 }); F = ns.Filter
ok, why = F.visible(9900001)
H.eq(ok, false, "種族不符預設不出現"); H.eq(why, "faction", "種族原因算 faction 排除")
H.eq((F.visible(9900001, { exclFaction = false })), true, "取消勾選後出現")
H.eq((F.visible(9900003)), true, "race={} 不限種族")
H.eq((F.visible(9900004)), true, "race 缺＝未知，不檢查")
ns, S = setup({ raceId = 4 }); F = ns.Filter
H.eq((F.visible(9900001)), true, "種族在清單內出現")
ns, S = setup({ noPlayer = true }); F = ns.Filter
H.eq((F.visible(9900001)), true, "沒有 UnitRace 不排除")
H.eq(ns.L("exclFaction"), "排除另一陣營", "zhTW 勾選標籤（2026-11-25 縮短，行為仍含種族限定）")
ns = setup({ locale = "enUS" })
H.eq(ns.L("exclFaction"), "Hide other faction", "enUS 勾選標籤")

-- 專業排除只管專業／副專業的 skillLine；其他技能 id（騎術、武器…）不排除
ns, S = setup({ profs = {} }); F = ns.Filter
local realQ = ns.Data.quest
ns.Data.quest = function(id)
  local q = realQ(id)
  if id == 9900001 then q.sk = { 762, 75 } end   -- 騎術
  return q
end
H.eq((F.visible(9900001)), true, "非專業技能 id 不因沒有該技能而排除")
H.eq(F.profLow(9900001), false, "非專業技能不標專業不足")
for _, line in ipairs({ 171, 164, 333, 202, 182, 165, 186, 197, 393, 185, 129, 356 }) do
  ns.Data.quest = function(id) local q = realQ(id); if id == 9900001 then q.sk = { line, 1 } end; return q end
  H.eq((F.visible(9900001)), false, "專業 " .. line .. " 沒有就排除")
end

-- 空狀態文字依分頁
ns, S = setup(); F = ns.Filter
ns.Panel.Refresh(1429)
ns.Panel.SetTab("log")
H.eq(ns.Panel.Message(), "任務日誌裡沒有這張地圖的任務", "日誌中分頁空")
ns.Panel.SetTab("done")
H.eq(ns.Panel.Message(), "這張地圖還沒有完成的任務", "已完成分頁空")
ns.Panel.SetTab("all"); ns.Panel.SetCheck("exclClass", true)
S.completed[9900001] = true; H.fire("PLAYER_ENTERING_WORLD")
ns.Panel.Refresh(1429)
ns.Panel.SetTab("all")
H.eq(ns.Panel.Message(), "這張地圖沒有收錄的任務", "全部分頁空用 panelEmpty")
ns.Panel.SetTab("open")
H.eq(ns.Panel.Message(), "這張地圖沒有未完成的任務", "未接分頁空且有已完成")
ns = setup({ locale = "enUS" })
H.eq(ns.L("panelNoLog"), "No quests from this map in the quest log", "enUS 日誌中空")
H.eq(ns.L("panelNoDone"), "No completed quests on this map yet", "enUS 已完成空")

-- 搜尋跨全部任務：不在這張地圖（甚至沒有地圖）的任務也找得到
ns, S = setup({ map = 1429 }); F = ns.Filter
F.set("tab", "all"); F.set("exclFaction", false); F.set("exclClass", false)
ns.Panel.Refresh(1429)
H.check(same(ids(ns.Panel.Rows()), { 9900001 }), "沒搜尋時只列這張地圖")
ns.Panel.SetSearch("No Map Quest")
H.check(same(ids(ns.Panel.Rows()), { 9900003 }), "搜尋找到沒有地圖的任務")
H.eq(ns.Panel.Rows()[1].offMap, true, "標記不在這張地圖")
ns.Panel.SetSearch("Only English")
H.check(same(ids(ns.Panel.Rows()), { 9900002 }), "搜尋找到別張地圖的任務")
H.eq(ns.Panel.Rows()[1].mapName, nil, "地圖名稱未知時為 nil（面板顯示位置未知）")
H.eq(ns.L("mapUnknown"), "位置未知", "zhTW 位置未知")
_G.C_Map.GetMapInfo = function(id) return { mapID = id, mapType = 3, name = "測試地圖" .. id } end
_G.issecretvalue = function() return false end; H.installed.issecretvalue = true   -- 地圖名要過保密檢查（fail-closed）
ns.Panel.SetSearch("Only English")
H.eq(ns.Panel.Rows()[1].mapName, "測試地圖1453", "已知地圖名稱帶入")
ns.Panel.SetSearch("test quest")
H.eq(ns.Panel.Rows()[1].questId, 9900001, "這張地圖的先列")
-- 搜尋仍套用勾選篩選
F.set("exclFaction", true)
ns.Panel.SetSearch("Only English")
H.eq(#ns.Panel.Rows(), 0, "搜尋結果仍受排除勾選限制")
H.eq(ns.Panel.Message(), "沒有符合的任務", "搜尋無結果文字")
-- 上限 200：造 300 個假任務
ns, S = setup({ map = 1429 }); F = ns.Filter
F.set("tab", "all")
local fakeIds = {}
for i = 1, 300 do fakeIds[i] = 8000000 + i end
ns.Data.questIds = function() return fakeIds end
ns.Data.quest = function(id)
  if id >= 8000000 then return { n = { en = "Bulk " .. id }, lv = 1, min = 1 } end
  return realQ(id)
end
ns.Panel.Refresh(1429)
ns.Panel.SetSearch("bulk")
H.eq(#ns.Panel.Rows(), 200, "搜尋結果上限 200 筆")
H.eq(ns.Panel.Capped(), true, "標記被截斷")
ns.Panel.SetSearch("bulk 8000001")
H.eq(ns.Panel.Capped(), false, "未達上限不標截斷")
H.eq(ns.L("searchCap"):format(200), "搜尋結果只顯示前 200 筆", "zhTW 截斷說明")

-- 升級事件帶的新等級優先（UnitLevel 此刻可能還是舊值）
ns, S = setup({ level = 4 }); F = ns.Filter
r, g = F.color(9900001)   -- min 5：等級 4 → 紅
H.eq(g < 0.2, true, "升級前紅色")
H.fire("PLAYER_LEVEL_UP", 5)   -- UnitLevel 仍回 4
r, g = F.color(9900001)
H.eq(g, 0.9, "升級事件的等級先用（不再紅）")

-- 沒有 GetQuestDifficultyColor：用經典規則（questLevel 7）
local function classicColor(level, lv)
  ns, S = setup({ level = level }); F = ns.Filter
  _G.GetQuestDifficultyColor = nil
  local q0 = ns.Data.quest
  ns.Data.quest = function(id) local q = q0(id); if id == 9900001 then q.lv = lv; q.min = 1 end; return q end
  return F.color(9900001)
end
local cr, cg = classicColor(10, 15)
H.check(cr == 1 and cg < 0.2, "經典規則：高 5 級以上紅")
cr, cg = classicColor(10, 13)
H.check(cr == 1 and cg == 0.5, "經典規則：高 3～4 級橘")
cr, cg = classicColor(10, 10)
H.check(cr == 1 and cg == 1, "經典規則：±2 黃")
cr, cg = classicColor(10, 5)
H.check(cr < 0.5 and cg == 0.75, "經典規則：低 3 級以上綠")
cr, cg = classicColor(30, 5)
H.check(cr == 0.5 and cg == 0.5, "經典規則：低很多灰")

-- 搜尋防抖：連續輸入只跑最後一次；清空立即套用
ns, S = setup({ map = 1429 }); F = ns.Filter
F.set("tab", "all"); F.set("exclFaction", false)
ns.Panel.Refresh(1453)
local runs = 0
local realSet = ns.Panel.SetSearch
ns.Panel.SetSearch = function(t) runs = runs + 1; return realSet(t) end
S.timers = {}
for _, t in ipairs({ "o", "on", "onl", "only" }) do ns.Panel.QueueSearch(t) end
H.eq(runs, 0, "輸入當下不搜尋")
H.eq(S.timers[1].d, 0.3, "防抖 0.3 秒")
S.flush()
H.eq(runs, 1, "連續輸入只搜尋一次（最新的）")
H.check(same(ids(ns.Panel.Rows()), { 9900002 }), "套用的是最後一次輸入")
ns.Panel.QueueSearch("")
H.eq(runs, 2, "清空立即套用，不等計時")
H.eq(#ns.Panel.Rows(), 2, "清空後還原清單")
S.flush()
H.eq(runs, 2, "清空後舊計時器不再執行")

-- 搜尋索引：整個 session 只建一次，結果與不用索引時一致
ns, S = setup({ map = 1429 }); F = ns.Filter
F.set("tab", "all"); F.set("exclFaction", false); F.set("exclClass", false)
ns.Panel.Refresh(1429)
H.eq(ns.Panel.IndexBuilds(), 0, "沒搜尋就不建索引")
local qCalls = 0
local realQuest2 = ns.Data.quest
ns.Panel.SetSearch("No Map Quest")
H.eq(ns.Panel.IndexBuilds(), 1, "第一次搜尋建索引")
ns.Data.quest = function(id) qCalls = qCalls + 1; return realQuest2(id) end
ns.Panel.SetSearch("Only English")
ns.Panel.SetSearch("quoter")
ns.Panel.SetSearch("無地圖")
H.eq(ns.Panel.IndexBuilds(), 1, "後續搜尋不重建")
H.check(same(ids(ns.Panel.Rows()), { 9900003 }), "中文名命中（索引）")
qCalls = 0
ns.Panel.SetSearch("zzz")
H.eq(qCalls, 0, "沒有命中就不解碼任何任務")
ns.Panel.SetSearch("fixture object")
H.check(same(ids(ns.Panel.Rows()), { 9900002 }), "NPC 名稱命中（索引，起點是 o9901001）")
