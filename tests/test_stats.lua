-- 載入量測與 /qmg stats：LoadStart／LoadEnd 取差值，超過門檻多印一行
local function run(clock, kb, locale)
  H.reset({ locale = locale })
  local i = 0
  _G.debugprofilestop = function() i = i + 1; return clock[i] end
  local k = 0
  local realGc = collectgarbage
  _G.collectgarbage = function(what, ...)
    if what == "count" then k = k + 1; return kb[k] end
    return realGc(what, ...)
  end
  QMG_Meta = { quests = 6878 }
  local lines, ns = {}, nil
  local ok, err = pcall(function()
    ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
    H.fire("ADDON_LOADED", "QuestMapGuide")
    _G.collectgarbage = realGc
    _G.print = function(...) lines[#lines + 1] = table.concat({ ... }, " ") end
    SlashCmdList.QUESTMAPGUIDE("stats")
  end)
  _G.collectgarbage = realGc
  _G.print = function() end
  _G.debugprofilestop = nil
  H.check(ok, "run 不出錯：" .. tostring(err))
  return ns, lines
end

-- 160 ms：超過 150 門檻
local ns, lines = run({ 100, 260 }, { 1000, 3000 }, "zhTW")
H.eq(ns.Stats.parseMs, 160, "parseMs 為兩次取值之差")
H.eq(ns.Stats.memKB, 2000, "memKB 為兩次取值之差")
H.eq(#lines, 2, "超過門檻時印兩行")
H.check(lines[1]:find("6878", 1, true) and lines[1]:find("160", 1, true), "第一行含任務數與毫秒")
H.check(lines[1]:find("記憶體", 1, true), "zhTW 第一行含「記憶體」")
H.check(lines[2] and lines[2]:find("超過門檻", 1, true), "超過 150 ms 印「超過門檻」")

-- 80 ms 且 2 MB：不超過
ns, lines = run({ 100, 180 }, { 1000, 3000 }, "zhTW")
H.eq(#lines, 1, "未超過門檻只印一行")
H.check(not lines[1]:find("超過門檻", 1, true), "未超過不含「超過門檻」")

-- 記憶體超過 20 MB
ns, lines = run({ 100, 120 }, { 0, 21 * 1024 }, "zhTW")
H.check(lines[2] and lines[2]:find("超過門檻", 1, true), "超過 20 MB 印「超過門檻」")

-- 邊界：剛好等於門檻不算超過
ns, lines = run({ 100, 250 }, { 1000, 2024 }, "zhTW")
H.eq(#lines, 1, "剛好 150 ms 不印超過門檻")
ns, lines = run({ 100, 110 }, { 0, 20480 }, "zhTW")
H.eq(#lines, 1, "剛好 20 MB 不印超過門檻")
ns, lines = run({ 100, 250.04 }, { 0, 1024 }, "zhTW")
H.eq(#lines, 1, "顯示為 150.0 ms 時不印超過門檻")
ns, lines = run({ 100, 250.2 }, { 0, 1024 }, "zhTW")
H.eq(#lines, 2, "150.2 ms 超過")
-- GC 讓差值變負：夾到 0
ns, lines = run({ 100, 110 }, { 5000, 4000 }, "zhTW")
H.eq(ns.Stats.memKB, 0, "memKB 不為負")

-- 英文
ns, lines = run({ 100, 260 }, { 1000, 3000 }, "enUS")
H.check(lines[1]:find("quests", 1, true) and lines[1]:find("memory", 1, true), "enUS 第一行為英文")
H.check(lines[2] and lines[2]:find("threshold", 1, true), "enUS 超過門檻行為英文")

-- 沒有 debugprofilestop：不報錯、不亂報門檻
H.reset({ locale = "zhTW" })
_G.debugprofilestop = nil
local ns2 = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(ns2.Stats.parseMs, nil, "沒有計時 API 時 parseMs 為 nil")
local out = {}
_G.print = function(...) out[#out + 1] = table.concat({ ... }, " ") end
local ok = pcall(SlashCmdList.QUESTMAPGUIDE, "stats")
_G.print = function() end
H.check(ok, "沒有計時 API 時 /qmg stats 不報錯")
H.eq(#out, 1, "沒有計時 API 時只印一行")
QMG_Meta = nil
