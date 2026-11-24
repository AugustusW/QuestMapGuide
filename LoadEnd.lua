-- 載入終點：與 LoadStart.lua 的差值就是內建資料的解析時間與記憶體（不含後續檔案）
local _, ns = ...
local s = ns.loadStart or {}
local clockNow = debugprofilestop and debugprofilestop() or nil
local kbNow = collectgarbage and collectgarbage("count") or nil
ns.Stats = {
  parseMs = (clockNow and s.clock) and (clockNow - s.clock) or nil,
  -- 窗口內若剛好 GC 差值會變負，夾到 0
  memKB = (kbNow and s.kb) and math.max(0, kbNow - s.kb) or nil,
  quests = QMG_Meta and QMG_Meta.quests or 0,
}
ns.loadStart = nil
