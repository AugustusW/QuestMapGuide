-- 載入流程、存檔預設值、slash 指令、語系
H.reset()
local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.fire("ADDON_LOADED", "QuestMapGuide")
H.eq(ns.Core.db().version, 1, "存檔版本 1")
H.eq(type(ns.Core.charDb()), "table", "角色存檔為表")
H.eq(SLASH_QUESTMAPGUIDE1, "/qmg", "slash 指令")

-- 繁中
H.reset({ locale = "zhTW" })
ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(ns.L("panelTitle"), "任務地圖指南", "zhTW 標題")

-- 英文
H.reset({ locale = "enUS" })
ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
H.eq(ns.L("panelTitle"), "QuestMapGuide", "enUS 標題")

-- 其他 addon 的 ADDON_LOADED 不初始化
H.reset()
ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc")); H.fire("ADDON_LOADED", "OtherAddon")
H.eq(QuestMapGuideDB, nil, "別的 addon 載入時不建存檔")

-- 收納按鈕函式必須存在
H.reset()
ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc")); H.fire("ADDON_LOADED", "QuestMapGuide")
H.eq(type(QuestMapGuide_OnAddonCompartmentClick), "function", "Compartment click")
H.eq(type(QuestMapGuide_OnAddonCompartmentEnter), "function", "Compartment enter")
H.eq(type(QuestMapGuide_OnAddonCompartmentLeave), "function", "Compartment leave")
QuestMapGuide_OnAddonCompartmentClick()

-- 缺 WorldMapFrame：載入不報錯；handler 之間互不影響
H.reset({ missing = { WorldMapFrame = true } })
local okMissing, errMissing = pcall(function()
  ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc")); H.fire("ADDON_LOADED", "QuestMapGuide")
end)
H.check(okMissing, "缺 WorldMapFrame 載入不報錯：" .. tostring(errMissing))
H.eq(ns.Panel.frame, nil, "缺 WorldMapFrame 時不建面板")
local ran, printed = {}, {}
local origPrint = _G.print
_G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
ns.Core.on("QMG_TEST_EVENT", function() error("boom") end)
ns.Core.on("QMG_TEST_EVENT", function() ran[#ran + 1] = "second" end)
H.fire("QMG_TEST_EVENT")
H.fire("QMG_TEST_EVENT")
_G.print = origPrint
H.eq(ran[1], "second", "前一個 handler 出錯，後一個照跑")
H.eq(#printed, 1, "同一則錯誤只印一次")

-- 不同錯誤最多印 50 則，之後不再印
H.reset()
ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc")); H.fire("ADDON_LOADED", "QuestMapGuide")
local capped = {}
local origPrint2 = _G.print
_G.print = function(...) capped[#capped + 1] = table.concat({ ... }, " ") end
local n = 0
ns.Core.on("QMG_CAP_EVENT", function() n = n + 1; error("err" .. n) end)
for _ = 1, 80 do H.fire("QMG_CAP_EVENT") end
_G.print = origPrint2
H.eq(#capped, 50, "不同錯誤最多印 50 則")
