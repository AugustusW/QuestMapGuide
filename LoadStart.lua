-- 載入起點（toc 中緊接在 Data/Forever/Quests.lua 之前，只量資料檔）：記下計時與記憶體基準，LoadEnd.lua 在資料檔之後取差值。
-- 存在 addon 私有的 ns 上，不新增全域。計時 API 不存在時留 nil，量測就略過。
local _, ns = ...
ns.loadStart = {
  clock = debugprofilestop and debugprofilestop() or nil,
  kb = collectgarbage and collectgarbage("count") or nil,
}
