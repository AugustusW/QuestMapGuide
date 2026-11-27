-- 0.0.4 可讀性改版：加深色盤、分頁按鈕、清單列分隔線與懸停、起點整行連結（底線＋地圖針）、座標格式、回清單按鈕、顯示已完成只在全部分頁可用
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local mapId = 1429
  local wm = H.widget("Frame")
  wm.GetMapID = function() return mapId end
  wm.OnMapChanged = function() end
  wm.SetMapID = function(self, id) mapId = id; self.OnMapChanged(self) end
  _G.WorldMapFrame = wm; H.installed.WorldMapFrame = true
  local names = opts.names or { [1429] = "艾爾文森林", [1453] = "暴風城" }
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3, name = names[id] } end }; H.installed.C_Map = true
  _G.hooksecurefunc = function(t, name, fn)
    local old = t[name]
    t[name] = function(...) if old then old(...) end fn(...) end
  end
  H.installed.hooksecurefunc = true
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  _G.GameTooltip = { SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end }
  H.installed.GameTooltip = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  if opts.charDb then QuestMapGuideCharDB = opts.charDb end   -- 角色存檔（載入前就存在，模擬上次登出存的設定）
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  return ns, wm
end
local function near(a, b) return math.abs(a - b) < 0.006 end
local function joined(ns) return table.concat(ns.Detail.Lines(), "\n") end
local function has(s, sub) return s:find(sub, 1, true) ~= nil end
local function rowOf(id)
  for _, f in ipairs(H.frames) do
    if f.title and f.questId == id and f._shown then return f end
  end
end
local function rowButtons()
  local t = {}
  for _, f in ipairs(H.frames) do if f._kind == "Button" and f.sub then t[#t + 1] = f end end
  return t
end
-- 明細目前顯示的文字列按鈕（依顯示文字或條件找）
local function lineButton(ns, text)
  for _, f in ipairs(H.frames) do
    if f._kind == "Button" and f.fs and f._shown and f ~= ns.Detail.backButton then
      if (type(text) == "function" and text(f)) or f.fs:GetText() == text then return f end
    end
  end
end
local function sameColor(c, hex, T, msg)
  H.eq(c and T.hex(c) or "nil", "|cff" .. hex, msg)
end

-- ===== 1. 色盤（使用者選 A）=====
do
  local ns = setup()
  local T = ns.Theme
  local function lv(r, g, b, hex, msg) H.eq(T.hex({ T.levelInk(r, g, b) }), "|cff" .. hex, msg) end
  lv(1, 1, 0, "594100", "黃色難度 594100")
  lv(0.25, 0.75, 0.25, "125212", "綠色難度 125212")
  lv(1, 0.5, 0.25, "753200", "橘色難度 753200")
  lv(1, 0.1, 0.1, "8e0a0a", "紅色難度 8e0a0a")
  lv(0.5, 0.5, 0.5, "494640", "灰色難度 494640")
  H.eq(T.hex({ T.qualityInk(0.12, 1, 0) }), "|cff125212", "綠色物品名與綠色難度同色 125212")
  sameColor(T.MUTED, "4f4439", T, "副標／未選分頁文字 4f4439")
  sameColor(T.LINK, "0b2f8a", T, "連結 0b2f8a")
  sameColor(T.TAB_ON_BG, "7a1a10", T, "選中分頁底 7a1a10")
  sameColor(T.TAB_ON_TEXT, "f6ebcc", T, "選中分頁字 f6ebcc")
  sameColor(T.TAB_OFF_EDGE, "6b4a2a", T, "未選分頁框 6b4a2a")
  sameColor(T.TAB_OFF_BG, "fff6dc", T, "未選分頁底 fff6dc")
  H.check(near(T.TAB_OFF_BG[4], 0.28), "未選分頁底透明度 .28")
  sameColor(T.DISABLED, "85775f", T, "停用標籤 85775f")
  -- 勾勾：材質本身金色 (1, .82, 0)，乘上頂點色後是 693b00
  local ck
  for _, f in ipairs(H.frames) do if f._kind == "Button" and f.check then ck = f.check break end end
  local vc = ck and ck._vc
  H.check(vc ~= nil, "勾勾有頂點色")
  if vc then
    H.eq(T.hex({ vc[1] * 1, vc[2] * 0.82, vc[3] * 0 }), "|cff693b00", "勾勾畫面色 693b00（材質金色 × 頂點色）")
  end
  -- 清單「!」與「?」
  ns.Panel.Refresh(1429)
  ns.Panel.SetTab("all")
  -- 可接：遊戲的黃色「!」材質（與地圖標記同一張），不再用文字
  local r1 = rowOf(9900001)
  H.eq(r1.icon:GetText(), "", "可接列不用文字「!」")
  H.check(r1.avail ~= nil and r1.avail._shown, "可接列顯示「!」材質")
  H.eq(r1.avail._tex, T.QUEST_ICON, "可接列材質是 Theme.QUEST_ICON")
  ns.Status.of = function(id) return id == 9900001 and "log" or "open" end
  ns.Panel.Refresh(1429)
  local r2 = rowOf(9900001)
  H.check(not r2.avail._shown, "列重用：變成進行中後藏起「!」材質")
  H.eq(r2.icon:GetText(), "|cff0b2f8a?|r", "進行中維持文字「?」")
  ns.Status.of = function(id) return id == 9900001 and "done" or "open" end
  ns.Panel.SetCheck("showDone", true)   -- 全部分頁要勾顯示已完成才列已完成
  local r3 = rowOf(9900001)
  H.check(r3 and not r3.avail._shown and r3.check._shown, "已完成維持勾勾、不顯示「!」")
end

-- ===== 2. 分頁按鈕外觀 =====
do
  local ns = setup()
  local T = ns.Theme
  local P = ns.Panel
  P.Refresh(1429)
  P.SetTab("log")
  local on, off = P.TabButton("log"), P.TabButton("open")
  H.check(on ~= nil and on.box ~= nil, "分頁有 Texture 拼的外框")
  sameColor(on.box.bg._ct, "7a1a10", T, "選中分頁底深紅")
  sameColor(on.label._tc, "f6ebcc", T, "選中分頁淺字")
  sameColor(off.box.bg._ct, "fff6dc", T, "未選分頁淺底")
  H.check(near(off.box.bg._ct[4], 0.28), "未選分頁底半透明")
  sameColor(off.box.top._ct, "6b4a2a", T, "未選分頁褐框（上）")
  sameColor(off.box.left._ct, "6b4a2a", T, "未選分頁褐框（左）")
  sameColor(off.label._tc, "4f4439", T, "未選分頁字 4f4439")
  -- 切分頁：外觀跟著換
  P.SetTab("open")
  sameColor(P.TabButton("open").box.bg._ct, "7a1a10", T, "切換後新分頁變深紅")
  sameColor(P.TabButton("log").box.bg._ct, "fff6dc", T, "切換後舊分頁變淺底")
  sameColor(P.TabButton("log").label._tc, "4f4439", T, "切換後舊分頁字變回 4f4439")
  -- 沒有用內建深色分頁模板
  for _, f in ipairs(H.frames) do
    H.check(not (f._kind == "Button" and f.tab and f._template), "分頁沒有用模板")
  end
end

-- ===== 3. 清單列分隔線與懸停反白（列重用時清掉）=====
do
  local ns = setup()
  local T = ns.Theme
  local P = ns.Panel
  P.Refresh(1429)
  P.SetTab("all")
  local bs = rowButtons()
  local b = rowOf(9900001)
  H.check(b.sep ~= nil and b.sep._ct ~= nil, "列底部有分隔線")
  sameColor(b.sep._ct, "5a3714", T, "分隔線色 5a3714")
  H.check(near(b.sep._ct[4], 0.28), "分隔線透明度 .28")
  H.eq(b.sep._height, 1, "分隔線 1px")
  H.check(not b.hl._shown and not b.bar._shown, "未懸停不反白")
  b._scripts.OnEnter(b)
  H.check(b.hl._shown, "懸停：整列反白")
  sameColor(b.hl._ct, "46230a", T, "反白色 46230a")
  H.check(near(b.hl._ct[4], 0.24), "反白透明度 .24")
  H.check(b.bar._shown, "懸停：左緣色條")
  sameColor(b.bar._ct, "7a1a10", T, "色條深紅")
  H.eq(b.bar._width, 3, "色條 3px")
  b._scripts.OnLeave(b)
  H.check(not b.hl._shown and not b.bar._shown, "OnLeave 清掉反白")
  -- 重用：懸停中的列被清空（換到沒任務的分頁），反白要收掉
  b._scripts.OnEnter(b)
  P.SetTab("done")
  H.check(not b.hl._shown and not b.bar._shown, "列被藏起來時清掉反白")
  -- 空列不反白
  local empty = bs[#bs]
  empty._scripts.OnEnter(empty)
  H.check(not empty.hl._shown, "沒有任務的列不反白")
end

-- ===== 4/5. 座標格式：清單第二行 =====
do
  local ns = setup()
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9900001).sub:GetText(), "測試NPC · 艾爾文森林(45.3, 60.1)", "清單副標：NPC · 地圖名(x, y)")
  ns = setup({ names = {} })
  ns.Panel.Refresh(1429)
  H.eq(rowOf(9900001).sub:GetText(), "測試NPC (45.3, 60.1)", "清單副標沒有地圖名：NPC (x, y)")
  H.eq(ns.Data.place("甲", "乙", 1, 2.26), "甲 · 乙(1.0, 2.3)", "place：有地圖名")
  H.eq(ns.Data.place("甲", nil, 1, 2), "甲 (1.0, 2.0)", "place：沒有地圖名")
  H.eq(ns.Data.place(nil, "乙", 1, 2), "乙(1.0, 2.0)", "place：沒有 NPC")
end

-- ===== 4/5. 明細起點整行連結：底線、地圖針、懸停變亮 =====
do
  local ns = setup()
  local T = ns.Theme
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  local s = joined(ns)
  H.check(has(s, "  測試NPC · 艾爾文森林(45.3, 60.1)"), "明細起點：NPC · 地圖名(x, y)")
  local b = lineButton(ns, "測試NPC · 艾爾文森林(45.3, 60.1)")
  H.check(b ~= nil, "起點行顯示文字不含縮排空白（底線從字開始）")
  if b then
    sameColor(b.fs._tc, "0b2f8a", T, "起點行連結色")
    H.check(b.ul._shown, "起點行有底線")
    sameColor(b.ul._ct, "0b2f8a", T, "底線同連結色")
    H.eq(b.ul._height, 1, "底線 1px")
    H.eq(b.ul._width, b.fs:GetStringWidth(), "底線寬度＝文字寬")
    -- 文字比可用寬度長：底線不超出（截在 文字區寬）
    local long = lineButton(ns, function(f) return f.ul and f.ul._shown end)
    H.check(long.ul._width <= 336 - (long.pin._shown and 15 or 0), "底線不超過文字區寬")
    H.check(b.pin ~= nil and b.pin._shown, "起點行有地圖針")
    H.eq(b.pin._tex, ns.Pins.ICON, "地圖針與地圖上的標記同一張材質")
    H.eq(b.pin._tex, T.QUEST_ICON, "起點連結圖示是可接任務「!」")
    H.eq(b.pin._texcoord, nil, "「!」材質不裁切（裁切是給物品圖示外框的）")
    H.check(b.onClick ~= nil, "整行一個可點區域")
    b._scripts.OnEnter(b)
    sameColor(b.fs._tc, T.hex(T.LINK_HOVER):sub(5), T, "懸停：文字變亮")
    H.check(T.LINK_HOVER[3] > T.LINK[3], "懸停色比連結色亮")
    sameColor(b.ul._ct, T.hex(T.LINK_HOVER):sub(5), T, "懸停：底線跟著變亮")
    b._scripts.OnLeave(b)
    sameColor(b.fs._tc, "0b2f8a", T, "離開：回連結色")
  end
  -- 前置任務連結：同樣式、沒有地圖針
  ns.Panel.Refresh(1453)
  ns.Panel.Select(9900002)
  H.check(has(joined(ns), "  Fixture Object · 暴風城(30.0, 31.5)"), "起點只在別張地圖：NPC · 地圖名(x, y)")
  local p = lineButton(ns, function(f) return f.quest == 9900001 end)
  if p then
    H.check(p.ul._shown, "前置任務有底線")
    H.eq(p.ul._width, p.fs:GetStringWidth(), "前置底線寬度＝文字寬")
    H.check(not p.pin._shown, "前置任務沒有地圖針")
  end
  H.check(p ~= nil and p.fs:GetText():sub(1, 1) ~= " ", "前置任務顯示文字不含縮排")
  -- 交任務行（9900002 交給 n9901001，目前地圖 1429 有座標）：NPC (x, y)，不是連結
  H.check(has(joined(ns), "  測試NPC (45.3, 60.1)"), "交任務行：NPC (x, y)")
  local e = lineButton(ns, "  測試NPC (45.3, 60.1)")
  H.check(e ~= nil and not e.ul._shown and not e.pin._shown, "一般文字沒有底線與地圖針")
  if e then
    e._scripts.OnEnter(e)
    H.check(e.fs._tc == nil or T.hex(e.fs._tc) ~= T.hex(T.LINK_HOVER), "一般文字懸停不變色")
  end
  -- 文字換了底線寬度跟著換（列重用）
  local w1 = p and p.ul._width
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  local same = lineButton(ns, "測試NPC · 艾爾文森林(45.3, 60.1)")
  H.check(same ~= nil and same.ul._width == same.fs:GetStringWidth() and same.ul._width ~= w1, "重用列：底線寬度依新文字")
end

-- 同一顆按鈕文字變了，底線寬度跟著更新
do
  local ns = setup()
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  local b = lineButton(ns, "測試NPC · 艾爾文森林(45.3, 60.1)")
  local w1 = b and b.ul._width
  _G.C_Map = { GetMapInfo = function(id) return { mapID = id, mapType = 3, name = "乙地" } end }
  ns.Detail.Refresh()
  H.eq(b.fs:GetText(), "測試NPC · 乙地(45.3, 60.1)", "同一顆按鈕換成新文字")
  H.check(b.ul._width == b.fs:GetStringWidth() and b.ul._width ~= w1, "同一顆按鈕：底線寬度依新文字更新")
end

-- 明細：地圖名取不到時 NPC (x, y)
do
  local ns = setup({ names = {} })
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  H.check(has(joined(ns), "  測試NPC (45.3, 60.1)"), "明細起點沒有地圖名：NPC (x, y)")
end

-- ===== 6. 回清單按鈕 =====
do
  local ns = setup()
  local T = ns.Theme
  local bb = ns.Detail.backButton
  H.eq(bb.fs:GetText(), "< 回清單", "回清單前加 <")
  H.eq(ns.L("backToList"), "< 回清單", "zhTW 前綴在語系字串")
  H.check(bb.box ~= nil, "回清單有框")
  sameColor(bb.box.top._ct, "6b4a2a", T, "回清單框色")
  H.check(bb._width >= bb.fs:GetStringWidth() + 12, "按鈕寬度包住文字")
end

-- ===== 7. 顯示已完成：每個分頁都能勾（2026-11-28 使用者選 A；原本非全部分頁灰掉，實機回報像壞掉） =====
-- 在其他分頁勾下去 → 設定打開並切到全部分頁；取消勾 → 設定關掉、留在原分頁
do
  local ns = setup()
  local T = ns.Theme
  local P = ns.Panel
  P.Refresh(1429)
  P.SetTab("open")
  local c = P.CheckButton("showDone")
  H.eq(c:IsEnabled(), true, "未接分頁：顯示已完成可以勾")
  sameColor(c.label._tc, "2e1f0f", T, "標籤一般文字色（不灰）")
  c:SetChecked(true); c._scripts.OnClick(c)
  H.eq(ns.Filter.get("showDone"), true, "勾下去：設定打開")
  H.eq(P.Tab(), "all", "勾下去：切到全部分頁")
  P.SetTab("log")
  H.eq(c:GetChecked(), true, "其他分頁顯示目前設定")
  c:SetChecked(false); c._scripts.OnClick(c)
  H.eq(ns.Filter.get("showDone"), false, "取消勾：設定關掉")
  H.eq(P.Tab(), "log", "取消勾：留在原分頁")
  H.eq(P.CheckButton("exclClass"):IsEnabled(), true, "其他勾選框不受影響")
end

-- ===== 審查修正 =====

-- 1. 連結列單行：量高度與畫的寬度、文字一致；長英文起點不換行，按鈕高＝文字高，底線不超過文字寬
do
  local ns = setup({ locale = "enUS" })
  local long = "Very Long English Quest Giver Name With Many Words"
  ns.Data.npcName = function(key) return key == "n9901001" and long or "Fixture Object" end
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  local b = lineButton(ns, function(f) return f.isLink and f.pin._shown end)
  H.check(b ~= nil, "長英文起點：連結列有畫出來")
  if b then
    H.eq(b.fs._wrap, false, "連結列不換行（截斷）")
    H.eq(b._height, b.fs:GetStringHeight(), "按鈕高＝畫出來的文字高")
    H.eq(b._height, 14, "長起點仍是單行高")
    H.check(b.ul._width <= b.fs._width, "底線寬不超過文字區寬")
    H.eq(b.fs._width, 336 - 15, "有地圖針時文字區讓出針的寬度")
  end
  -- 一般文字列仍然換行（描述）
  local plain = lineButton(ns, function(f) return not f.isLink and f.fs._wrap ~= nil end)
  H.check(plain ~= nil and plain.fs._wrap == true, "一般文字列恢復換行")
end

-- 2. 明細連結懸停中被藏起來（地圖關掉，OnLeave 不一定會來），再打開不應維持亮色
do
  local ns, wm = setup()
  local T = ns.Theme
  ns.Panel.Refresh(1429)
  ns.Panel.Select(9900001)
  local b = lineButton(ns, "測試NPC · 艾爾文森林(45.3, 60.1)")
  b._scripts.OnEnter(b)
  sameColor(b.fs._tc, T.hex(T.LINK_HOVER):sub(5), T, "懸停中亮色")
  wm:Hide()
  wm:Show()
  H.check(not b.hovering, "藏起來後清掉懸停狀態")
  sameColor(b.fs._tc, "0b2f8a", T, "藏起來就回連結色")
  ns.Detail.Refresh()
  sameColor(b.fs._tc, "0b2f8a", T, "重新顯示、重畫後不是亮色")
end

-- 3. 清單列懸停中面板被藏起來，再顯示不殘留反白
do
  local ns, wm = setup()
  ns.Panel.Refresh(1429)
  local b = rowOf(9900001)
  b._scripts.OnEnter(b)
  H.check(b.hl._shown, "懸停中反白")
  wm:Hide()
  wm:Show()
  ns.Panel.Refresh(1429)
  H.check(not b.hovering and not b.hl._shown and not b.bar._shown, "面板藏起來再顯示：沒有殘留反白")
end

-- 4. 英文分頁文字：寬度限制在分頁內、不換行
do
  local ns = setup({ locale = "enUS" })
  ns.Panel.Refresh(1429)
  for _, tab in ipairs({ "open", "log", "done", "all" }) do
    local tb = ns.Panel.TabButton(tab)
    H.check(tb.label._width ~= nil and tb.label._width <= tb._width - 4, "enUS 分頁 " .. tab .. "：文字寬度限制在分頁內")
    H.eq(tb.label._wrap, false, "enUS 分頁 " .. tab .. "：不換行")
  end
  H.check(ns.Panel.TabText("log"):find("^In log") ~= nil, "enUS 分頁文字")
end

-- 5. 「< 」前綴在語系字串裡
do
  local ns = setup({ locale = "enUS" })
  H.eq(ns.Detail.backButton.fs:GetText(), "< Back to list", "enUS 回清單")
  H.eq(ns.L("backToList"), "< Back to list", "前綴在語系字串")
end

-- 8. 載入時就還原存檔的分頁與勾選狀態；任何分頁都可勾
do
  local ns = setup({ charDb = { filter = { tab = "log", showDone = true } } })
  local c = ns.Panel.CheckButton("showDone")
  H.eq(ns.Panel.Tab(), "log", "還原存檔分頁")
  H.eq(c:IsEnabled(), true, "載入時非全部分頁也可勾")
  H.eq(c:GetChecked(), true, "載入時勾選狀態照存檔")
end
