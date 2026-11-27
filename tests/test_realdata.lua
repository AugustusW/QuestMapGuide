-- 正式資料（Data/Forever/Quests.lua）冒煙測試：其他測試都用 fixture，壞掉的正式檔只有這裡抓得到
local function load(locale)
  H.reset({ locale = locale })
  QMG_Data, QMG_Meta = nil, nil
  local wm = H.widget("Frame")
  wm.GetMapID = function() return 1429 end
  wm.OnMapChanged = function() end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3 } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  local ns
  local ok, err = pcall(function()
    ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc", true))
    H.fire("ADDON_LOADED", "QuestMapGuide")
  end)
  H.check(ok, "載入含正式資料的 toc 不出錯：" .. tostring(err))
  return ns
end

local function count(t) local c = 0 for _ in pairs(t) do c = c + 1 end return c end

for _, locale in ipairs({ "zhTW", "enUS" }) do
  local ns = load(locale)
  H.eq(QMG_Meta.env, "prod", locale .. " 正式資料來自 prod")
  H.eq(QMG_Meta.schema, 5, locale .. " schema 5（V298）")
  local D = ns.Data
  H.eq(#D.questIds(), QMG_Meta.quests, locale .. " Meta.quests 與實際任務數一致")
  H.eq(#D.entityKeys(), QMG_Meta.entities, locale .. " Meta.entities 與實際數一致")
  -- 2026-11-27 V298 匯出（prod，含關聯副本、使用者確認的候選清單）；重新匯出後有意更新
  H.eq(QMG_Meta.quests, 6885, locale .. " 任務數（綁 2026-11-27 V298 匯出）")
  -- V298 副本：52 個副本；1014 除掉阿魯高 在影牙城堡
  H.eq(#D.dungeons(), 52, locale .. " 副本數")
  H.eq(D.dungeon(33).n, "影牙城堡", locale .. " 副本 33 名稱")
  local hit = false
  for _, id in ipairs(D.byDungeon(33)) do if id == 1014 then hit = true end end
  H.check(hit, locale .. " 影牙城堡含 1014")
  H.check(#D.byMap(1429) > 0, locale .. " ByMap 非空")
  -- 每一筆都能解出來，且 s／e 引用的 entity 解得出（壞掉的打包只有這裡抓得到）
  local bad = 0
  for _, id in ipairs(D.questIds()) do
    local q = D.quest(id)
    if type(q) ~= "table" or type(q.n) ~= "table" then bad = bad + 1 end
  end
  for _, key in ipairs(D.entityKeys()) do
    local e = D.entity(key)
    if type(e) ~= "table" or type(e.n) ~= "string" or type(e.sp) ~= "table" then bad = bad + 1 end
  end
  H.eq(bad, 0, locale .. " 所有任務與 entity 都能解碼")
  -- 任務 1：獎勵 159，count 是 null → nil（未知不是 1）
  H.eq(D.quest(1).ri[1][1], 159, locale .. " 任務 1 獎勵物品 id")
  H.eq(D.quest(1).ri[1][2], nil, locale .. " null count 保持 nil")
  H.eq(type(D.quest(1).ri[1][3]), "boolean", locale .. " choice 是布林")

  -- 實機回報（2026-11-27 達拉然城 9 首領）：首領區只放得下 5 行（約 15px 一行、區高 88），多了會壓到分頁
  local over, many = {}, nil
  for _, d in ipairs(D.dungeons()) do
    ns.Panel.PickDungeon(d.id)
    if #ns.Panel.BossLines() > 5 then over[#over + 1] = d.n end
    if not many and d.b and #d.b > 5 then many = d end
  end
  H.eq(table.concat(over, ","), "", locale .. " 每個副本的首領區都不超過 5 行")
  ns.Panel.PickDungeon(many.id)
  local bl = ns.Panel.BossLines()
  H.check(bl[1]:find(tostring(#many.b), 1, true) ~= nil, locale .. " 首領多時第一行是標題含總數")
  H.eq(bl[#bl], "4. " .. many.b[4], locale .. " 標題之後列 4 個首領")
  ns.Panel.PickDungeon(nil)

  ns.Panel.Refresh(1429)
  local rows = ns.Panel.Rows()
  H.check(#rows > 0, locale .. " 艾爾文森林有任務列")
  local blank = 0
  for _, r in ipairs(rows) do
    if type(r.name) ~= "string" or r.name == "" then blank = blank + 1 end
  end
  H.eq(blank, 0, locale .. " 沒有空白任務名")
end

-- 關聯清單（prev/next/conc/excl）必須是純 questId 數字；匯出是 {source, questId} 物件，建置要轉換（0.0.2 漏轉：開明細就丟錯、前置淡化失效）
for _, locale in ipairs({ "zhTW", "enUS" }) do
  local ns = load(locale)
  local D = ns.Data
  local nonNumber, withPrev = 0, nil
  for _, id in ipairs(D.questIds()) do
    local q = D.quest(id)
    for _, f in ipairs({ "prev", "next", "conc", "excl" }) do
      if q[f] then for _, v in ipairs(q[f]) do if type(v) ~= "number" then nonNumber = nonNumber + 1 end end end
    end
    if not withPrev and q.prev and #q.prev > 0 and D.quest(q.prev[1]) then withPrev = id end
  end
  H.eq(nonNumber, 0, locale .. " 所有關聯清單元素都是數字")
  H.check(withPrev ~= nil, locale .. " 正式資料有前置任務可測")
  local q = D.quest(withPrev)
  local prereq = D.quest(q.prev[1])
  local pname = ns.Filter.name(prereq.n)
  -- 明細不出錯，且前置任務標題與名稱出現
  _G.WorldMapFrame:Show(); if ns.Panel.frame then ns.Panel.frame:Show() end
  local ok, err = pcall(function() return ns.Detail.Open(withPrev) end)
  H.check(ok, locale .. " 開有前置的任務明細不出錯：" .. tostring(err))
  local text = table.concat(ns.Detail.Lines(), "\n")
  H.check(text:find(ns.L("prereq"), 1, true) ~= nil, locale .. " 明細有前置任務標題")
  H.check(text:find(pname, 1, true) ~= nil, locale .. " 明細列出前置任務名稱 " .. pname)
  -- 前置未完成 → 淡化並帶前置名稱
  local d = ns.Filter.dim(withPrev)
  H.eq(d and d.kind, "prereq", locale .. " 前置未完成的任務被淡化")
  H.eq(d and d.name, pname, locale .. " 淡化帶前置名稱")
end

-- 0.2.0 節慶：正式資料帶 h。數字綁 2026-11-24 的匯出（QMG_Meta.exportedAt 2026-11-24T16:45:31，build/export_cat.json）：
-- 季節性 80＋新年慶典 61＋仲夏 16＝157；暗月馬戲團 70。重建 Data/Forever/Quests.lua 時要跟著更新這兩個數字
do
  local ns = load("zhTW")
  local c = { 0, 0 }
  for _, id in ipairs(ns.Data.questIds()) do
    local h = ns.Data.quest(id).h
    if h then c[h] = c[h] + 1 end
  end
  H.eq(c[1], 157, "正式資料節慶任務數")
  H.eq(c[2], 70, "正式資料暗月馬戲團任務數")
  H.eq(ns.Filter.titled("x", nil, nil, ns.Data.quest(6961).h), "x (節慶)", "冬天爺爺任務（6961）標節慶")
end
