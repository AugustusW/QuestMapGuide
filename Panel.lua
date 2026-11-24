-- 大地圖右側面板：列出正在看的地圖的任務，每列有狀態圖示（可接／進行中／已完成）；已完成預設不列。
-- 篩選勾選、分頁、搜尋：設定在 ns.Filter（角色存檔）；Refresh 算出 entries（通過勾選篩選的全部任務）與計數，
-- 分頁與搜尋只決定 rows（SetTab／SetSearch 重新取用 entries，不重算）。
local ADDON, ns = ...

local Panel = {}
ns.Panel = Panel

local ZONE_MAP_TYPE = 3   -- Enum.UIMapType.Zone；遊戲內由 /qmg probe 記錄驗證
local VISIBLE = 12        -- 列按鈕數量上限（載入時建立，之後只換文字）；實際顯示幾列看面板高度（visibleRows）
local ROW_H = 36
local ROW_TOP = 168       -- 第一列距面板頂端
local FOOTER_H = 12       -- 頁尾單行高度（SetWordWrap(false)，不換行）
local FOOTER_MARGIN = 10  -- 頁尾距面板底端
local FOOTER_GAP = 6      -- 最後一列與頁尾之間的空隙
local DEFAULT_H = 600     -- 取不到面板高度時的預設（跟著地圖視窗，約 600）
local WIDTH   -- = Theme.PANEL_W（Theme 宣告之後才指定）

local entries = {} -- 目前地圖通過勾選篩選的全部任務（不分分頁、不看搜尋）
local rows = {}      -- entries 依分頁與搜尋取出的清單 {questId, name, lv, r, g, b, npc, x, y, status, dim, dimText, profLow}
-- open＝可接 N（不含被前置／同組淡化的）；openAll＝未接分頁數字（含淡化的）；all＝全部分頁數字
local counts = { open = 0, openAll = 0, log = 0, done = 0, all = 0 }
local search = ""   -- 小寫；不存檔
local capped = false  -- 搜尋結果被截在 SEARCH_CAP 筆
local SEARCH_CAP = 200
local index         -- 搜尋索引：第一次搜尋時建一次，整個 session 保留
local indexBuilds = 0
local zoom = false  -- 目前不是區域地圖（只顯示放大提示）
local curMap        -- 最近一次 Refresh 的地圖
local stale = false -- 面板隱藏時狀態變了，顯示時要補畫
local message        -- 空狀態文字（有清單時為 nil）
local offset = 0     -- 捲動位移（列數）
local buttons = {}
local msgText, footer, countText
local tabButtons, checkButtons, searchBox, searchHint = {}, {}, nil, nil
local TABS = { "open", "log", "done", "all" }
local TAB_KEY = { open = "tabOpen", log = "tabLog", done = "tabDone", all = "tabAll" }
local CHECKS = { "exclClass", "exclProf", "exclFaction", "showDone", "showLow", "showHoliday" }

local Filter = ns.Filter
local questName = Filter.name

-- 起點：s 的第一個 entity 在這張地圖上的第一個 spawn。
-- 回傳 npc 名稱, x, y, 第一個有 entity 的起點 spawn 的地圖 id（搜尋結果的地圖名用；沒有 spawn 就 nil）
local function startOn(q, uiMapId)
  local s = q.s
  if not s then return nil end
  local firstMap
  for _, key in ipairs(s) do
    local e = ns.Data.entity(key)   -- 每列只解一次，spawns 直接用這張表
    if e then
      if not firstMap and type(e.sp) == "table" and e.sp[1] then firstMap = e.sp[1].m end
      for x, y in ns.Data.spawns(e, uiMapId) do
        return (ns.Data.npcName(key, e)), x, y, firstMap
      end
    end
  end
  return nil, nil, nil, firstMap
end

-- 狀態圖示：可接＝遊戲的黃色「!」材質（Theme.QUEST_ICON，與地圖標記同一張）、進行中＝深藍文字「?」、
-- 已完成＝勾選材質（✔ 字元在內建字型可能缺字，所以完成用材質）
local Theme = ns.Theme
WIDTH = Theme.PANEL_W
local ICON_TEXT = { log = Theme.hex(Theme.LOG) .. "?|r" }
local CHECK_TEX = "Interface\\Buttons\\UI-CheckBox-Check"
local function setIcon(b, status)
  local t = ICON_TEXT[status]
  b.icon:SetText(t or "")
  if status == "done" then b.check:Show() else b.check:Hide() end
  if status == "open" then b.avail:Show() else b.avail:Hide() end
end

-- 一筆清單項目；uiMapId 是目前地圖，offMap 表示這筆是搜尋帶出來的、不在這張地圖
local function buildEntry(id, q, uiMapId, offMap)
  local npc, x, y, startMap = startOn(q, offMap and nil or uiMapId)
  local st = ns.Status.of(id)
  local dim = Filter.dim(id, q, st)
  local r, g, b = Filter.color(id, q)
  local dimText
  if dim then dimText = ns.L(dim.kind == "group" and "doneGroup" or "needPrereq"):format(dim.name) end
  local mapName
  if offMap and C_Map and C_Map.GetMapInfo then
    -- 搜尋帶出來的任務顯示它起點所在的地圖；起點沒有座標資料才退回任務的第一張地圖
    local mapId = startMap or (type(q.maps) == "table" and q.maps[1]) or nil
    mapName = ns.Data.mapName(mapId)
  end
  return { questId = id, name = questName(q.n), typeId = q.t, h = q.h, n = q.n, starts = q.s, lv = q.lv,
    r = r, g = g, b = b, npc = npc, x = x, y = y, status = st, dim = dim, dimText = dimText,
    startMap = startMap, profLow = Filter.profLow(id, q) or nil, offMap = offMap or nil, mapName = mapName }
end

-- 清單與搜尋共用的排序：等級由低到高（沒有等級的排最後），同等級依顯示名稱，再依 questId
local function sortRows(list)
  table.sort(list, function(a, b)
    local la, lb = a.lv, b.lv
    if la ~= lb then
      if la == nil then return false end
      if lb == nil then return true end
      return la < lb
    end
    local na, nb = tostring(a.name or ""), tostring(b.name or "")
    if na ~= nb then return na < nb end
    return a.questId < b.questId
  end)
  return list
end

-- 分頁標籤與頁首共用的計數來源
local function tabCount(tab)
  return ((tab == "open") and counts.openAll or counts[tab]) or 0
end

local function tabLabel(tab)
  -- 搜尋中：分頁數字是這張地圖的計數，與搜尋結果（跨地圖）對不上，所以不顯示數字
  if search ~= "" then return ns.L(TAB_KEY[tab]) end
  return string.format("%s (%d)", ns.L(TAB_KEY[tab]), tabCount(tab))
end

-- 分頁文字色：目前分頁（深紅底）用淺字，其他（淺底褐框）用副標色
function Panel.TabColor(tab)
  if tab == Panel.Tab() then return Theme.TAB_ON_TEXT end
  return Theme.TAB_OFF_TEXT
end

-- 標題列、分頁文字與勾選狀態（面板還沒建就略過）
local function updateChrome()
  if not Panel.frame then return end
  local cur = Panel.Tab()
  if search ~= "" and not zoom then
    -- 搜尋中：標題改成搜尋結果筆數（被截斷時多一個 +）
    countText:SetText(ns.L("searchCount"):format(#rows) .. (capped and "+" or ""))
  else
    countText:SetText(ns.L("headerTab"):format(ns.L(TAB_KEY[cur]), tabCount(cur)))
  end
  for _, tab in ipairs(TABS) do
    local tb = tabButtons[tab]
    tb.label:SetText(tabLabel(tab))
    local c = Panel.TabColor(tab)
    tb.label:SetTextColor(c[1], c[2], c[3])
    if tab == cur then
      Theme.boxColor(tb.box, Theme.TAB_ON_BG, Theme.TAB_ON_EDGE)
    else
      Theme.boxColor(tb.box, Theme.TAB_OFF_BG, Theme.TAB_OFF_EDGE)
    end
  end
  for _, key in ipairs(CHECKS) do checkButtons[key]:SetChecked(Filter.get(key)) end
  -- 「顯示已完成」只在全部分頁有作用（inTab）：其他分頁停用並灰掉標籤，勾選狀態與設定不動
  local sd = checkButtons.showDone
  local ink = (cur == "all") and Theme.INK or Theme.DISABLED
  if cur == "all" then sd:Enable() else sd:Disable() end
  sd.label:SetTextColor(ink[1], ink[2], ink[3])
end

-- 面板高度扣掉上方區域與頁尾後放得下幾列（至少 1、至多 VISIBLE）
local function visibleRows()
  local h = Panel.frame and Panel.frame.GetHeight and Panel.frame:GetHeight()
  if type(h) ~= "number" or h <= 0 then h = DEFAULT_H end
  local n = math.floor((h - ROW_TOP - FOOTER_MARGIN - FOOTER_H - FOOTER_GAP) / ROW_H)
  return math.max(1, math.min(VISIBLE, n))
end
Panel.VisibleRows = visibleRows

-- 列懸停反白（整列半透明底＋左緣色條）；hovering 記滑鼠是否在列上，列換內容時照它重畫、列藏起來時清掉
local function setHover(b, on)
  b.hovering = on or nil
  local show = on and b.questId ~= nil
  if show then b.hl:Show(); b.bar:Show() else b.hl:Hide(); b.bar:Hide() end
end

local function render()
  if not Panel.frame then return end
  local hereName = ns.Data.mapName(curMap)   -- 清單第二行座標的地圖名（這張地圖）
  local vis = visibleRows()
  local maxOffset = math.max(0, #rows - vis)
  if offset > maxOffset then offset = maxOffset end
  if offset < 0 then offset = 0 end
  for i, b in ipairs(buttons) do
    local r = i <= vis and rows[offset + i] or nil
    if r then
      b.questId = r.questId
      local title = Filter.titled(r.name, r.typeId, r.questId, r.h)
      if r.lv and r.lv > 0 then title = string.format("[%d] %s", r.lv, title) end
      if r.profLow then title = title .. "  " .. ns.L("profLow") end
      b.title:SetText(title)
      b.fullTitle = title
      if r.status == "done" then
        b.title:SetTextColor(Theme.MUTED[1], Theme.MUTED[2], Theme.MUTED[3])   -- 已完成：名稱灰色
      else
        b.title:SetTextColor(Theme.levelInk(r.r or 1, r.g or 1, r.b or 1))   -- 難度色對照羊皮紙色盤（與明細同一個函式）
      end
      b:SetAlpha(r.dim and Theme.DIM_ALPHA or 1)
      setIcon(b, r.status)
      local sub = ""
      if r.dimText then
        sub = r.dimText
      elseif r.offMap then
        sub = r.mapName or ns.L("mapUnknown")   -- 搜尋結果裡不在這張地圖的任務
        if r.status == "done" then sub = ns.L("statusDone") .. " · " .. sub end
      elseif r.status == "done" then
        sub = ns.L("statusDone")   -- 已完成：副標取代 NPC 座標
      elseif r.x and r.y then
        sub = ns.Data.place(r.npc, hereName, r.x, r.y)   -- NPC · 地圖名(x, y)
      else
        -- 起點不在這張地圖、或沒有座標：補上起點所在地圖，連地圖名都沒有就標示未收錄
        local startName = ns.Data.mapName(r.startMap)
        sub = startName and ns.L("startOn"):format(startName) or ns.L("startUnknown")
      end
      b.sub:SetText(sub)
      b.fullSub = sub
      setHover(b, b.hovering)
      b:Show()
    else
      b.questId = nil
      b.fullTitle, b.fullSub = nil, nil
      setHover(b, false)   -- 列重用：藏起來時不會收到 OnLeave，反白在這裡清
      b:Hide()
    end
  end
  msgText:SetText(message or "")
  if message then msgText:Show() else msgText:Hide() end
  footer:SetText(capped and ns.L("searchCap"):format(SEARCH_CAP) or ns.L("panelFooter"))
  updateChrome()
end

local function matches(e)
  if search == "" then return true end
  local n = e.n
  if n and ((n.zh and n.zh:lower():find(search, 1, true)) or (n.en and n.en:lower():find(search, 1, true))) then return true end
  for _, key in ipairs(e.starts or {}) do
    local nm, _, en = ns.Data.npcName(key)
    if nm and nm:lower():find(search, 1, true) then return true end
    if en and en:lower():find(search, 1, true) then return true end
  end
  return false
end

local function inTab(e, tab)
  if tab == "all" then return e.status ~= "done" or Filter.get("showDone") end
  return e.status == tab
end

-- 搜尋索引：每筆任務一組小寫的 中文名／英文名／起點 NPC 名稱（平行陣列），建的時候每筆只解碼一次。
local function searchIndex()
  if index then return index end
  indexBuilds = indexBuilds + 1
  local ix = { ids = ns.Data.questIds(), zh = {}, en = {}, st = {}, lv = {}, nm = {} }
  local npcCache = {}
  for i, id in ipairs(ix.ids) do
    local q = ns.Data.quest(id)
    local n = q and q.n or {}
    ix.lv[i] = q and q.lv or nil   -- 搜尋排序用的等級與顯示名稱：排序截上限前不必再解碼每一筆
    ix.nm[i] = q and questName(q.n) or ""
    ix.zh[i] = (n.zh or ""):lower()
    ix.en[i] = (n.en or ""):lower()
    local names = {}
    for _, key in ipairs(q and q.s or {}) do
      local nm = npcCache[key]
      if nm == nil then
        local shown, _, en = ns.Data.npcName(key)
        nm = shown and (shown:lower() .. (en and en ~= shown and ("\n" .. en:lower()) or "")) or false
        npcCache[key] = nm
      end
      if nm then names[#names + 1] = nm end
    end
    ix.st[i] = table.concat(names, "\n")
  end
  index = ix
  return ix
end
function Panel.IndexBuilds() return indexBuilds end
-- 學到新名稱後呼叫：下次搜尋重建索引
function Panel.InvalidateIndex() index = nil; Filter.ResetSteps() end

-- 空狀態文字：依分頁
local function emptyMessage(tab)
  if search ~= "" then return ns.L("panelNoMatch") end
  if tab == "log" then return ns.L("panelNoLog") end
  if tab == "done" then return ns.L("panelNoDone") end
  if tab == "open" and counts.done > 0 then return ns.L("panelAllDone") end
  return ns.L("panelEmpty")
end

-- 搜尋框有字：搜全部任務（不限這張地圖），依等級由低到高（與清單同一個排序）；最多 SEARCH_CAP 筆。
-- 候選只收索引裡的 questId、等級、名稱，先用同一個 sortRows 排好；再由低到高逐筆解碼、檢查可見與分頁、
-- 湊滿 SEARCH_CAP + 1 筆就停（多出的那一筆只用來判斷是否截斷）；完整項目（狀態、顏色、地圖名）只對留下的筆數建。
local function searchAll(tab)
  local cands, onMap = {}, {}
  for _, e in ipairs(entries) do
    onMap[e.questId] = true
    if inTab(e, tab) and matches(e) then cands[#cands + 1] = { questId = e.questId, lv = e.lv, name = e.name, entry = e } end
  end
  local ix = searchIndex()
  for i, id in ipairs(ix.ids) do
    if not onMap[id] and (ix.zh[i]:find(search, 1, true) or ix.en[i]:find(search, 1, true) or ix.st[i]:find(search, 1, true)) then
      cands[#cands + 1] = { questId = id, lv = ix.lv[i], name = ix.nm[i] }
    end
  end
  sortRows(cands)
  local out = {}
  for _, c in ipairs(cands) do
    if c.entry then
      out[#out + 1] = c
    else
      local q = ns.Data.quest(c.questId)   -- 只解碼排在前面的命中
      local st = ns.Status.of(c.questId)
      if q and Filter.visible(c.questId, nil, q, st) and inTab({ status = st }, tab) then
        c.q = q
        out[#out + 1] = c
      end
    end
    if #out > SEARCH_CAP then break end
  end
  -- 超過上限才算截斷（剛好 SEARCH_CAP 筆不算）；被截掉的是等級最高的
  if #out > SEARCH_CAP then
    capped = true
    out[#out] = nil
  end
  for i, c in ipairs(out) do out[i] = c.entry or buildEntry(c.questId, c.q, curMap, true) end   -- 完整項目只建留下的
  return out
end

-- entries -> rows（分頁＋搜尋）與空狀態文字
local function applyView(keepOffset)
  local tab = Panel.Tab()
  rows, message, capped = {}, nil, false
  if not keepOffset then offset = 0 end
  if search ~= "" then
    rows = searchAll(tab)
  else
    for _, e in ipairs(entries) do
      if inTab(e, tab) then rows[#rows + 1] = e end
    end
    sortRows(rows)
  end
  if #rows == 0 then message = emptyMessage(tab) end
  render()
end

function Panel.Tab()
  local t = Filter.get("tab")
  for _, x in ipairs(TABS) do if x == t then return t end end
  return "open"
end

function Panel.SetTab(tab)
  local ok = false
  for _, x in ipairs(TABS) do if x == tab then ok = true end end
  Filter.set("tab", ok and tab or "open")
  if zoom then updateChrome() else applyView() end
end

function Panel.SetSearch(text)
  search = (text or ""):lower()
  if not zoom then applyView() end
end

-- 搜尋框輸入用：防抖 0.3 秒，只有最新一次輸入會執行；清空立即套用
local DEBOUNCE = 0.3
local searchToken = 0
function Panel.QueueSearch(text)
  searchToken = searchToken + 1
  if (text or "") == "" then Panel.SetSearch(text); return end
  local mine = searchToken
  local ok = ns.Core.after(DEBOUNCE, function()
    if mine == searchToken then Panel.SetSearch(text) end
  end)
  if not ok then Panel.SetSearch(text) end
end

-- 勾選框改變：存檔後重算
function Panel.SetCheck(key, value)
  Filter.set(key, value and true or false)
  if curMap then Panel.Refresh(curMap) else updateChrome() end
end

function Panel.Refresh(uiMapId, keepOffset)
  local keep = keepOffset and offset or 0
  entries, rows, message, offset = {}, {}, nil, keep
  counts = { open = 0, openAll = 0, log = 0, done = 0, all = 0 }
  if curMap ~= nil and uiMapId ~= curMap and ns.Detail and ns.Detail.MapChanged then ns.Detail.MapChanged() end
  curMap, stale = uiMapId, false
  zoom = false
  Filter.reload()
  local info = uiMapId and C_Map.GetMapInfo(uiMapId)
  if not info or info.mapType ~= ZONE_MAP_TYPE then
    zoom = true
    message = ns.L("panelZoom")
    render()
    return
  end
  local showDone = Filter.get("showDone")
  for _, id in ipairs(ns.Data.byMap(uiMapId)) do
    local q = ns.Data.quest(id)
    if q and Filter.visible(id, nil, q, ns.Status.of(id)) then
      local e = buildEntry(id, q, uiMapId, false)
      local st = e.status
      if st ~= "open" then counts[st] = counts[st] + 1 end
      if st == "open" then
        counts.openAll = counts.openAll + 1
        if not e.dim then counts.open = counts.open + 1 end
      end
      if st ~= "done" or showDone then counts.all = counts.all + 1 end
      entries[#entries + 1] = e
    end
  end
  applyView(true)
end

-- 狀態變了（Status 通知）：面板顯示中就重畫（保留捲動位置），隱藏中等顯示時補畫
function Panel.StatusChanged()
  if ns.Detail and ns.Detail.Refresh then ns.Detail.Refresh() end
  if not Panel.frame or not curMap then return end
  if Panel.frame:IsVisible() then Panel.Refresh(curMap, true) else stale = true end
end

function Panel.Rows() return rows end
function Panel.Header() return countText and countText:GetText() or nil end   -- 測試用
function Panel.TabText(tab) return tabButtons[tab] and tabButtons[tab].label:GetText() or nil end   -- 測試用
function Panel.TabButton(tab) return tabButtons[tab] end   -- 測試用
function Panel.CheckButton(key) return checkButtons[key] end   -- 測試用
function Panel.Counts() return counts end
function Panel.Capped() return capped end
function Panel.Message() return message end
function Panel.Offset() return offset end

function Panel.Select(questId)
  if ns.Pins and ns.Pins.Show then ns.Pins.Show(questId) end
  if ns.Detail and ns.Detail.Open then ns.Detail.Open(questId) end
end

local function build()
  local f = CreateFrame("Frame", nil, WorldMapFrame)
  f:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT")
  f:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMRIGHT")
  f:SetWidth(WIDTH)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:EnableMouseWheel(true)
  -- 羊皮紙背景（與明細同一組材質與底色）
  Panel.underlay, Panel.parchment = Theme.paint(f)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
  title:SetText(ns.L("panelTitle"))
  title:SetTextColor(Theme.HEAD[1], Theme.HEAD[2], Theme.HEAD[3])

  countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  countText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -32)
  countText:SetJustifyH("LEFT")
  countText:SetTextColor(Theme.INK[1], Theme.INK[2], Theme.INK[3])

  -- 搜尋框（任務名稱或 NPC 名稱）；提示字在沒有內容時顯示
  searchBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  searchBox:SetSize(WIDTH - 36, 20)
  searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -48)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(40)
  searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  searchHint:SetPoint("LEFT", searchBox, "LEFT", 2, 0)
  searchHint:SetText(ns.L("searchHint"))
  searchHint:SetTextColor(Theme.HINT[1], Theme.HINT[2], Theme.HINT[3])
  Panel.searchHint = searchHint   -- 測試用
  searchBox:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    if t == "" then searchHint:Show() else searchHint:Hide() end
    Panel.QueueSearch(t)
  end)
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  -- 六個勾選框（兩欄三列）：三個「排除」＋顯示已完成＋顯示低等任務＋顯示節慶任務。
  -- 兩欄平分面板寬；標籤限寬、不換行（太長截斷），左欄標籤不會壓到右欄的勾選框
  local CHECK_X, CHECK = 8, 22
  local colW = (WIDTH - CHECK_X * 2) / 2
  for i, key in ipairs(CHECKS) do
    local c = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    c:SetSize(CHECK, CHECK)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    c:SetPoint("TOPLEFT", f, "TOPLEFT", CHECK_X + col * colW, -72 - row * 22)
    local lbl = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", c, "RIGHT", 0, 1)
    lbl:SetWidth(colW - CHECK - 4)
    lbl:SetWordWrap(false)
    lbl:SetJustifyH("LEFT")
    lbl:SetText(ns.L(key))
    lbl:SetTextColor(Theme.INK[1], Theme.INK[2], Theme.INK[3])
    c.label = lbl
    c.key = key
    c:SetScript("OnClick", function(self) Panel.SetCheck(self.key, self:GetChecked()) end)
    checkButtons[key] = c
  end

  -- 分頁：未接／日誌中／已完成／全部，文字附數字。按鈕外觀用 Texture 拼（選中深紅底淺字、未選淺底褐框），
  -- 不用內建分頁模板（深色，羊皮紙上不搭）；底下一條褐線當分頁列的底
  local TAB_GAP = 2
  local tabW = (WIDTH - 24 - TAB_GAP * (#TABS - 1)) / #TABS
  for i, tab in ipairs(TABS) do
    local tb = CreateFrame("Button", nil, f)
    tb:SetSize(tabW, 20)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 12 + (i - 1) * (tabW + TAB_GAP), -142)
    tb.box = Theme.box(tb)
    tb.label = tb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tb.label:SetPoint("CENTER", tb, "CENTER", 0, 0)
    tb.label:SetWidth(tabW - 6)    -- 文字（含數字）限制在分頁內，太長截斷（英文 "In log (123)"）
    tb.label:SetWordWrap(false)
    tb.tab = tab
    tb:SetScript("OnClick", function(self) Panel.SetTab(self.tab) end)
    tabButtons[tab] = tb
  end

  local tabLine = f:CreateTexture(nil, "BORDER")
  tabLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -162)
  tabLine:SetSize(WIDTH, 1)
  tabLine:SetColorTexture(Theme.TAB_OFF_EDGE[1], Theme.TAB_OFF_EDGE[2], Theme.TAB_OFF_EDGE[3], 1)

  msgText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  msgText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -172)
  msgText:SetWidth(WIDTH - 24)
  msgText:SetJustifyH("LEFT")
  msgText:SetTextColor(Theme.INK[1], Theme.INK[2], Theme.INK[3])

  for i = 1, VISIBLE do
    local b = CreateFrame("Button", nil, f)
    b:SetHeight(ROW_H)
    b:SetWidth(WIDTH - 24)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -ROW_TOP - (i - 1) * ROW_H)
    -- 底部 1px 分隔線；懸停反白（整列）＋左緣 3px 色條，預設藏起來
    b.sep = b:CreateTexture(nil, "BORDER")
    b.sep:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.sep:SetSize(WIDTH - 24, 1)
    b.sep:SetColorTexture(Theme.ROW_SEP[1], Theme.ROW_SEP[2], Theme.ROW_SEP[3], Theme.ROW_SEP[4])
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(Theme.ROW_HOVER[1], Theme.ROW_HOVER[2], Theme.ROW_HOVER[3], Theme.ROW_HOVER[4])
    b.hl:Hide()
    b.bar = b:CreateTexture(nil, "BORDER")
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.bar:SetSize(3, ROW_H)
    b.bar:SetColorTexture(Theme.ROW_BAR[1], Theme.ROW_BAR[2], Theme.ROW_BAR[3], Theme.ROW_BAR[4])
    b.bar:Hide()
    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.icon = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2)
    b.icon:SetWidth(16)
    b.icon:SetJustifyH("CENTER")
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetTexture(CHECK_TEX)
    b.check:SetSize(16, 16)
    b.check:SetVertexColor(Theme.CHECK[1], Theme.CHECK[2], Theme.CHECK[3])
    b.check:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2)
    b.check:Hide()
    b.avail = b:CreateTexture(nil, "ARTWORK")
    b.avail:SetTexture(Theme.QUEST_ICON)
    b.avail:SetSize(16, 16)
    b.avail:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -2)
    b.avail:Hide()
    b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 20, 0)
    b.title:SetWidth(WIDTH - 44)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)   -- 單行：超出寬度截斷，全文看 tooltip
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("TOPLEFT", b, "TOPLEFT", 20, -16)
    b.sub:SetWidth(WIDTH - 44)
    b.sub:SetJustifyH("LEFT")
    b.sub:SetTextColor(Theme.MUTED[1], Theme.MUTED[2], Theme.MUTED[3])
    b.sub:SetWordWrap(false)
    b:SetScript("OnEnter", function(self)
      setHover(self, true)
      if not self.fullTitle then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.fullTitle)
      if self.fullSub and self.fullSub ~= "" then GameTooltip:AddLine(self.fullSub) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) setHover(self, false); GameTooltip:Hide() end)
    -- 面板或地圖被藏起來時不一定有 OnLeave：清掉懸停，再顯示時不殘留反白
    b:SetScript("OnHide", function(self) setHover(self, false) end)
    b:SetScript("OnClick", function(self) if self.questId then Panel.Select(self.questId) end end)
    b:Hide()
    buttons[i] = b
  end

  f:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 3
    render()
  end)

  footer = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, FOOTER_MARGIN)
  footer:SetWidth(WIDTH - 24)
  footer:SetWordWrap(false)   -- 單行；過長就截斷，不往上長高壓到最後一列
  footer:SetJustifyH("LEFT")
  footer:SetTextColor(Theme.MUTED[1], Theme.MUTED[2], Theme.MUTED[3])
  footer:SetText(ns.L("panelFooter"))

  f:SetScript("OnSizeChanged", function() render() end)   -- 面板高度改變：重算列數
  Panel.frame = f
  Panel.footer = footer
end

-- 等級、專業點數變了：顯示中就重畫，隱藏時等顯示補畫
ns.Core.on("PLAYER_LEVEL_UP", function(level)
  Filter.levelUp(level)   -- UnitLevel 在事件當下可能還是舊值，用事件帶的新等級
  Panel.StatusChanged()
end)
ns.Core.on("SKILL_LINES_CHANGED", function() Panel.StatusChanged() end)

ns.Core.on("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  if type(WorldMapFrame) ~= "table" then return end
  build()
  local function refreshNow() Panel.Refresh(WorldMapFrame:GetMapID()) end
  if type(WorldMapFrame.OnMapChanged) == "function" then
    hooksecurefunc(WorldMapFrame, "OnMapChanged", refreshNow)
  else
    -- OnMapChanged 不存在（遊戲內未驗證）：面板是 WorldMapFrame 的子框架，只在地圖開著時才跑 OnUpdate，
    -- 每 0.2 秒比對一次地圖 ID，變了才更新
    local last, acc = nil, 0
    Panel.frame:SetScript("OnShow", function() last = nil; acc = 0.2 end)
    Panel.frame:SetScript("OnUpdate", function(_, elapsed)
      acc = acc + elapsed
      if acc < 0.2 then return end
      acc = 0
      local id = WorldMapFrame:GetMapID()
      if id ~= last then last = id; Panel.Refresh(id) end
    end)
  end
  -- 隱藏時錯過的狀態變化，顯示時補畫（HookScript 不蓋掉上面輪詢用的 OnShow）
  Panel.frame:HookScript("OnShow", function()
    if stale and curMap then Panel.Refresh(curMap, true) end
  end)
  refreshNow()
end)
