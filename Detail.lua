-- 任務明細：蓋在面板上的第二個畫面（清單的分頁、搜尋、捲動位置都留在清單那邊，回清單就是把這層藏起來）。
-- ns.Detail.Open(questId) / Close() / Lines()（每列顯示文字，測試用）/ Refresh() / IsOpen() / Current()
-- 未知值（欄位 nil）顯示「資料未收錄」；已知為空（{}）顯示「無」。位置式欄位只用 [1]/[2]/[3] 取值，不用 # 或 ipairs。
local ADDON, ns = ...

local Detail = {}
ns.Detail = Detail

local MAXL = 48     -- 同時可顯示的列數（載入時建好，之後只換文字）
local LINE_GAP = 3
local PAD = 12
local TOP = 40      -- 「回清單」那一排的高度
local DEFAULT_H = 600
local BOTTOM_PAD = 8   -- 內容區底部留白（面板底部沒有其他元件，不需要更多）

local cur           -- 目前開著的 questId
local lines = {}    -- 目前內容（列模型）{kind="text"|"link"|"items"|"money", text, r, g, b, quest?, onClick?, items?}
local offset = 0    -- 捲動位移（列數）
local frame, backBtn, titleText
local buttons = {}
local ibtns = {}     -- 物品按鈕（載入時建好 MAXITEMS 個，之後只換內容）
local rows          -- 視覺列（由 lines 組成：一般列一行、物品列最多兩個物品）；build 後重算
local measure       -- 量文字高度用的 FontString（buttons[1].fs）
local pending = {}   -- build() 時還沒快取的物品 id；GET_ITEM_INFO_RECEIVED 只在命中這裡才重建
local stale = false   -- 地圖（面板）隱藏時狀態變了：先記著，顯示時才重建
local navigating = false  -- GoTo 自己切地圖時為 true，地圖變更不關明細

local build, render   -- 前向宣告（startClick 要用）

local function L(k) return ns.L(k) end

local function questName(id)
  local q = ns.Data.quest(id)
  return q and ns.Filter.name(q.n) or nil
end

local safe   -- 前向宣告（下面定義）

-- 物品：C_Item.GetItemInfo（可能回多個值或一張表）；還沒快取或回保密值就是「物品 #id」
local function itemText(id)
  local info = C_Item and C_Item.GetItemInfo
  if type(info) == "function" then
    local ok, a, b = pcall(info, id)
    if ok then
      if type(a) == "table" then
        a, b = a.itemName or a.name, a.hyperlink or a.itemLink
      end
      b, a = safe(b, "string"), safe(a, "string")
      if b then return b end   -- 連結本身帶品質顏色
      if a then return a end
    end
  end
  pending[id] = true
  return L("itemPending"):format(id)
end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAXITEMS = 12   -- 物品按鈕池（一般任務最多 6 選 1 + 4 固定）；只分配給目前看得到的物品列
local LINEW = ns.Theme.PANEL_W - PAD * 2   -- 文字列寬（物品一欄也用這個寬度，每列一個）
local ICON = 37
local PIN = 12                -- 起點連結前的可接任務「!」（Theme.QUEST_ICON，與地圖標記同一張材質）
local PIN_GAP = 3

-- 羊皮紙配色來自共用的 ns.Theme（Panel 也用同一份）
local Theme = ns.Theme
local INK, HEAD, LINK, MUTED = Theme.INK, Theme.HEAD, Theme.LINK, Theme.MUTED

-- 遊戲值在 type() 與 issecretvalue 確認前不碰；保密判斷用 ns.Core.secret（fail-closed，全插件唯一一份）
local function secret(v) return ns.Core.secret(v) end
function safe(v, ty)
  if type(v) ~= ty or secret(v) then return nil end
  if ty == "string" and v == "" then return nil end
  return v
end

-- 物品按鈕要的顯示資料：名稱（純文字）、圖示、品質色；沒有的都有退路
local function itemInfo(id)
  local name, icon, quality
  local info = C_Item and C_Item.GetItemInfo
  if type(info) == "function" then
    local ok, a, _, q, _, _, _, _, _, _, ic = pcall(info, id)
    if ok then
      if type(a) == "table" then
        name, quality, icon = safe(a.itemName or a.name, "string"), safe(a.itemQuality or a.quality, "number"), a.itemTexture or a.iconFileID
      else
        name, quality, icon = safe(a, "string"), safe(q, "number"), ic
      end
    end
  end
  local byId = C_Item and C_Item.GetItemIconByID
  if type(byId) == "function" then
    local ok, v = pcall(byId, id)
    if ok and (safe(v, "number") or safe(v, "string")) then icon = v end
  end
  if not (safe(icon, "number") or safe(icon, "string")) then icon = QUESTION end
  if quality == nil and C_Item and type(C_Item.GetItemQualityByID) == "function" then
    local ok, v = pcall(C_Item.GetItemQualityByID, id)
    if ok then quality = safe(v, "number") end
  end
  local r, g, b = 1, 1, 1
  if quality then
    local c = type(_G.ITEM_QUALITY_COLORS) == "table" and _G.ITEM_QUALITY_COLORS[quality]
    if type(c) == "table" and safe(c.r, "number") and safe(c.g, "number") and safe(c.b, "number") then
      r, g, b = c.r, c.g, c.b
    elseif C_Item and type(C_Item.GetItemQualityColor) == "function" then
      local ok, cr, cg, cb = pcall(C_Item.GetItemQualityColor, quality)
      if ok and safe(cr, "number") and safe(cg, "number") and safe(cb, "number") then r, g, b = cr, cg, cb end
    end
  end
  return name, icon, r, g, b
end

local function add(text, extra)
  local e = extra or {}
  e.text = text
  e.kind = e.kind or (e.quest and "link" or "text")
  lines[#lines + 1] = e
end

local function head(key) add(L(key), { r = HEAD[1], g = HEAD[2], b = HEAD[3], head = true }) end

local function unknown() add("  " .. L("unknown"), { r = MUTED[1], g = MUTED[2], b = MUTED[3] }) end
local function none() add("  " .. L("none"), { r = MUTED[1], g = MUTED[2], b = MUTED[3] }) end

-- 切到別張地圖但不關明細（navigating 旗標讓 MapChanged 放行）
local function switchMap(mapId)
  local wm = _G.WorldMapFrame
  if not (wm and type(wm.SetMapID) == "function") then return end
  navigating = true
  local ok, err = pcall(wm.SetMapID, wm, mapId)
  navigating = false
  if not ok then error(err, 0) end
end

-- 起點連結：同地圖直接標記；別張地圖先切到 entity 第一個 spawn 的地圖再標記，明細不關
local function startClick(e, questId)
  return function()
    local wm = _G.WorldMapFrame
    local here = wm and wm.GetMapID and wm:GetMapID()
    local first = e and type(e.sp) == "table" and e.sp[1]
    local here_has = false
    if here and e then for _ in ns.Data.spawns(e, here) do here_has = true; break end end
    if not here_has and first and first.m and first.m ~= here then
      switchMap(first.m)
      if cur == questId then build(); render() end
    end
    if ns.Pins and ns.Pins.Show then ns.Pins.Show(questId) end
  end
end

-- entity 清單（起點／交任務）。asLink：整列可點（起點用）
local function entityLines(list, mapId, asLink)
  if list == nil then unknown(); return end
  if #list == 0 then none(); return end
  for _, key in ipairs(list) do
    local e = ns.Data.entity(key)
    if e then
      local npc = ns.Data.npcName(key) or key
      local t = "  " .. npc
      if asLink then
        -- 起點：NPC · 地圖名(x, y)（目前地圖有 spawn 取那個，否則第一個 spawn；地圖名拿不到就 NPC (x, y)）。
        -- 整行一個可點區域，連結樣式（底線＋「!」圖示）在 render 畫
        local sx, sy, sm
        if mapId then for x, y in ns.Data.spawns(e, mapId) do sx, sy, sm = x, y, mapId; break end end
        local first = type(e.sp) == "table" and e.sp[1]
        if not sx and first then sx, sy, sm = first.x, first.y, first.m end
        if sx and sy then t = "  " .. ns.Data.place(npc, ns.Data.mapName(sm), sx, sy) end
        add(t, { kind = "link", pin = true, r = LINK[1], g = LINK[2], b = LINK[3], onClick = startClick(e, cur) })
      else
        -- 交任務：只列目前地圖上的座標，格式 NPC (x, y)
        if mapId then
          for x, y in ns.Data.spawns(e, mapId) do t = "  " .. ns.Data.place(npc, nil, x, y); break end
        end
        add(t)
      end
    else
      add("  " .. key)
    end
  end
end

-- 任務關係（前置／後續／同時／互斥）：在資料裡的可以點，不在的是純文字
local function relLines(titleKey, list)
  head(titleKey)
  if list == nil then unknown(); return end
  if #list == 0 then none(); return end
  for _, id in ipairs(list) do
    local nm = questName(id)
    if nm then
      add("  " .. ns.Filter.withStep(nm, id), { quest = id, r = LINK[1], g = LINK[2], b = LINK[3] })
    else
      add("  #" .. id .. " " .. L("notInData"), { r = MUTED[1], g = MUTED[2], b = MUTED[3] })
    end
  end
end

local function className(id)
  local ci = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(id)
  return ci and ci.className or ("#" .. id)
end
local function raceName(id)
  local ri = C_CreatureInfo and C_CreatureInfo.GetRaceInfo and C_CreatureInfo.GetRaceInfo(id)
  return ri and ri.raceName or ("#" .. id)
end

local function idNames(list, fn)
  local t = {}
  for _, id in ipairs(list) do t[#t + 1] = fn(id) end
  return table.concat(t, L("listSep"))
end

local builds = 0
function build()
  builds = builds + 1
  stale = false
  lines, pending, rows = {}, {}, nil
  local id = cur
  local q = id and ns.Data.quest(id)
  if not q then return end
  local mapId = _G.WorldMapFrame and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or nil
  local r, g, b = Theme.levelInk(ns.Filter.color(id))
  add(ns.Filter.titled(questName(id) or ("#" .. id), q.t, id, q.h), { r = r, g = g, b = b, title = true })

  add(L("status") .. L("colon") .. L("status" .. ({ open = "Open", log = "Log", done = "Done" })[ns.Status.of(id)]))
  if q.lv and q.lv > 0 then
    local t = L("level"):format(q.lv)
    if q.min and q.min > 0 then t = t .. L("gap") .. L("minLevel"):format(q.min) end
    add(t, { r = r, g = g, b = b })
  elseif q.lv == nil then
    local t = L("level"):gsub("%%d", L("unknown"))
    add(t)
  end

  head("startAt")
  entityLines(q.s, mapId, true)
  head("endAt")
  entityLines(q.e, mapId)
  relLines("prereq", q.prev)

  -- 描述：沒有就整段不出現
  local desc = ns.Data.desc and ns.Data.desc(id)
  if type(desc) == "string" and desc ~= "" then
    head("description")
    add(ns.Reward.text(desc), { kind = "text" })
  end

  -- 獎勵：每一段沒有資料就不出現；全部未知才顯示「資料未收錄」
  local ri = q.ri
  local xp = ns.Reward.xp(id, q)
  local moneyStr = ns.Reward.money(q.cu)
  local fixed, choose = {}, {}
  if ri then
    for _, it in ipairs(ri) do
      if it[3] then choose[#choose + 1] = it else fixed[#fixed + 1] = it end
    end
  end
  local function itemRows(list)
    for _, it in ipairs(list) do
      local t = "  " .. itemText(it[1])
      if it[2] == nil then t = t .. " " .. L("countUnknown") else t = t .. " x" .. it[2] end
      local nm, icon, r, g, b = itemInfo(it[1])
      local dr, dg, db = Theme.qualityInk(r, g, b)
      add(t, { kind = "items", items = { { it[1], it[2] } }, id = it[1], count = it[2], choice = it[3] and true or false,
        name = nm or L("itemPending"):format(it[1]), icon = icon, ir = r, ig = g, ib = b, tr = dr, tg = dg, tb = db })
    end
  end
  local hasXp = type(xp) == "number" and xp > 0
  local unkRi, unkXp = ri == nil, xp == nil
  -- 金錢：資料沒有金錢欄位（cu == nil）視為沒有金錢獎勵，不列；物品、經驗值未知才列「資料未收錄」
  if #choose > 0 or #fixed > 0 or moneyStr or hasXp or unkRi or unkXp then
    head("rewards")
    if unkRi then add("  " .. L("itemsLabel") .. L("colon") .. L("unknown"), { r = MUTED[1], g = MUTED[2], b = MUTED[3] }) end
    if #choose > 0 then add(L("chooseOne")); itemRows(choose) end
    if #fixed > 0 then add(L("receive")); itemRows(fixed) end
    if moneyStr or hasXp or unkXp then
      add(L("alsoGet"))
      if moneyStr then add("  " .. moneyStr, { kind = "money" }) end
      local lab = L("xpLabel")
      if lab:sub(-1) == ":" then lab = lab .. " " end   -- 英文半形冒號後補空白，中文全形不補
      if hasXp then add("  " .. lab .. xp)
      elseif unkXp then add("  " .. lab .. L("unknown"), { r = MUTED[1], g = MUTED[2], b = MUTED[3] }) end
    end
  end

  relLines("nextQuests", q.next)
  if q.conc and #q.conc > 0 then relLines("concurrent", q.conc) end
  if q.excl and #q.excl > 0 then relLines("exclusive", q.excl) end

  head("restrictions")
  local n = #lines
  if q.f == "A" then add("  " .. L("factionA")) elseif q.f == "H" then add("  " .. L("factionH")) end
  if type(q.cls) == "table" and #q.cls > 0 then add("  " .. L("classes"):format(idNames(q.cls, className))) end
  if type(q.race) == "table" and #q.race > 0 then add("  " .. L("races"):format(idNames(q.race, raceName))) end
  if type(q.sk) == "table" and q.sk[1] then
    if q.sk[2] then
      add("  " .. L("skill"):format(q.sk[1], q.sk[2]))
    else
      add("  " .. L("skillNoValue"):format(q.sk[1]))
    end
  end
  if #lines == n then none() end
end

local function areaHeight()
  local h = frame and frame.GetHeight and frame:GetHeight()
  if type(h) ~= "number" or h <= 0 then h = DEFAULT_H end
  return h - TOP - BOTTOM_PAD
end

local shownItems = {}

-- 視覺列：一列一行（物品一欄，每列一個按鈕；捲動以視覺列為單位）
local function getRows()
  if rows then return rows end
  rows = {}
  for i, l in ipairs(lines) do rows[i] = { l } end
  return rows
end

-- 文字列的版面：連結列單行（不換行、超出截斷，全文點下去或看明細別處），去掉縮排空白，起點讓出「!」圖示；
-- 一般文字列全寬、換行。量高度與畫都用這一份，量的和畫的寬度、文字、換行設定一致
local hasPinTex   -- 起點圖示材質存在（buildFrame 時決定）
local function layout(l)
  if l.kind == "link" then
    local x = (l.pin and hasPinTex) and (PIN + PIN_GAP) or 0
    return x, (l.text:gsub("^%s+", "")), false
  end
  return 0, l.text, true
end

local function textHeight(l)
  if l.h then return l.h end
  local x, text, wrap = layout(l)
  measure:SetWidth(LINEW - x)
  measure:SetWordWrap(wrap)
  measure:SetText(text)
  local h = measure:GetStringHeight()
  measure:SetText("")
  if type(h) ~= "number" or h < 12 then h = 12 end
  l.h = h
  return h
end

-- 從第 off 列起放得下哪些列（render 與捲動上限共用，兩邊的判斷不會分歧）。
-- 回傳 { {row, y}... }、是否一路放到最後一列。第一列一定放（避免整頁空白）。
local function place(off, room)
  local rs, out = getRows(), {}
  local y, nText, nItems = 0, 0, 0
  for i = off, #rs do
    local r = rs[i]
    local h, isItems = nil, r[1].kind == "items"
    if isItems then
      h = ICON
      if nItems + #r > MAXITEMS then return out, false end
    else
      h = textHeight(r[1])
      if nText >= MAXL then return out, false end
    end
    if i > off and y + h > room then return out, false end
    out[#out + 1] = { r, y }
    y = y + h + LINE_GAP
    if isItems then nItems = nItems + #r else nText = nText + 1 end
  end
  return out, true
end

-- 捲到底時最後一頁剛好裝滿：最小的 off 使得 off 之後的列全放得下
local function maxOffset(room)
  local o = #getRows()
  if o < 1 then return 0 end
  while o > 1 and select(2, place(o - 1, room)) do o = o - 1 end
  return o - 1
end

local function releaseTip(b)
  local tip = _G.GameTooltip
  if type(tip) ~= "table" or type(tip.GetOwner) ~= "function" then return end
  local ok, owner = pcall(tip.GetOwner, tip)
  if ok and owner == b and type(tip.Hide) == "function" then tip:Hide() end
end

local function setItem(b, l, x, y)
  if b.itemId ~= l.id then releaseTip(b) end
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  b.slot = { x, y }
  b.itemId = l.id
  b.icon:SetTexture(l.icon)
  b.nameFs:SetText(l.name)
  b.nameFs:SetTextColor(l.tr or INK[1], l.tg or INK[2], l.tb or INK[3])
  b.nameColor = { l.tr or INK[1], l.tg or INK[2], l.tb or INK[3] }
  b.border:SetColorTexture(l.ir or 1, l.ig or 1, l.ib or 1, 1)
  local c = type(l.count) == "number" and l.count > 1 and tostring(l.count) or ""
  b.countFs:SetText(c)
  b:Show()
  shownItems[#shownItems + 1] = { itemId = l.id, count = l.count, choice = l.choice, icon = l.icon }
end

-- 連結列的顏色（文字與底線同色）：懸停時亮一階
local function linkColor(b)
  local c = (b.hovering and b.isLink) and Theme.LINK_HOVER or LINK
  b.fs:SetTextColor(c[1], c[2], c[3])
  b.ul:SetColorTexture(c[1], c[2], c[3], 1)
end

-- 一般文字列與連結列共用同一組按鈕（列重用）：連結列去掉縮排空白，底線從字開始、寬度跟著文字，起點多一個「!」圖示
local function setLine(b, l, y)
  local isLink = l.kind == "link"
  local x, text, wrap = layout(l)
  local h = textHeight(l)
  b.fs:ClearAllPoints()
  b.fs:SetPoint("TOPLEFT", b, "TOPLEFT", x, 0)
  b.fs:SetWidth(LINEW - x)
  b.fs:SetWordWrap(wrap)
  b.fs:SetText(text)
  b.isLink = isLink or nil
  if isLink then
    local w = b.fs:GetStringWidth()
    if type(w) ~= "number" or w > LINEW - x then w = LINEW - x end
    b.ul:ClearAllPoints()
    b.ul:SetPoint("TOPLEFT", b, "TOPLEFT", x, -h)   -- 單行文字下方 1px（落在列與列的間隔裡）
    b.ul:SetSize(w, 1)
    b.ul:Show()
    linkColor(b)
  else
    b.ul:Hide()
    b.fs:SetTextColor(l.r or INK[1], l.g or INK[2], l.b or INK[3])
  end
  if x > 0 then b.pin:Show() else b.pin:Hide() end
  b:SetHeight(h)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP - y)
  b.quest, b.onClick = l.quest, l.onClick
  b:Show()
end

function render()
  if not frame then return end
  shownItems = {}
  local room = areaHeight()
  local maxOff = maxOffset(room)
  if offset > maxOff then offset = maxOff end
  if offset < 0 then offset = 0 end
  local placed = place(offset + 1, room)
  local nText, nItems = 0, 0
  for _, p in ipairs(placed) do
    local r, y = p[1], p[2]
    if r[1].kind == "items" then
      for _, l in ipairs(r) do
        nItems = nItems + 1
        setItem(ibtns[nItems], l, PAD, -TOP - y)
      end
    else
      nText = nText + 1
      setLine(buttons[nText], r[1], y)
    end
  end
  for i = nText + 1, MAXL do
    local b = buttons[i]
    b.quest, b.onClick, b.isLink, b.hovering = nil, nil, nil, nil
    b:Hide()
  end
  for j = nItems + 1, MAXITEMS do
    if ibtns[j] then releaseTip(ibtns[j]); ibtns[j].itemId = nil; ibtns[j]:Hide() end
  end
end

function Detail.ItemButtons() return shownItems end
function Detail.Lines()
  local t = {}
  for i, l in ipairs(lines) do t[i] = l.text end
  return t
end
function Detail.IsOpen() return cur ~= nil end
function Detail.Current() return cur end

function Detail.Open(questId)
  if not ns.Data.quest(questId) then return false end
  cur, offset = questId, 0
  build()
  if frame then frame:Show(); render() end
  return true
end

function Detail.Close()
  cur, lines, rows = nil, {}, nil
  for j = 1, MAXITEMS do if ibtns[j] then releaseTip(ibtns[j]) end end
  if frame then frame:Hide() end
end

-- 狀態、物品資料變了：開著且看得到才重建（保留捲動位置）；看不到就標記過期
function Detail.Refresh()
  if not cur then return end
  -- 看不到就不重建（背景裡的任務事件很頻繁）；顯示時 OnShow 補建
  if frame and not frame:IsVisible() then stale = true; return end
  build()
  render()
end

-- 地圖被別的方式換掉（玩家自己切地圖）：明細屬於舊地圖的脈絡，關掉回清單
function Detail.MapChanged()
  if cur and not navigating then Detail.Close() end
end

-- 前置／後續點擊：任務在別張地圖就先切地圖（切不了就只開明細），再開那個任務的明細並標記
function Detail.GoTo(questId)
  local q = ns.Data.quest(questId)
  if not q then return end
  local wm = _G.WorldMapFrame
  local here = wm and wm.GetMapID and wm:GetMapID()
  if type(q.maps) == "table" and q.maps[1] and here then
    local onHere = false
    for _, m in ipairs(q.maps) do if m == here then onHere = true end end
    if not onHere and type(wm.SetMapID) == "function" then
      switchMap(q.maps[1])
    end
  end
  Detail.Open(questId)
  if ns.Pins and ns.Pins.Show then ns.Pins.Show(questId) end
end

local function onLine(self)
  if self.onClick then self.onClick()
  elseif self.quest then Detail.GoTo(self.quest) end
end

local function buildFrame()
  local parent = ns.Panel and ns.Panel.frame
  if not parent then return end
  frame = CreateFrame("Frame", nil, parent)
  frame:SetAllPoints()
  local lvl = parent:GetFrameLevel()
  if type(lvl) == "number" then frame:SetFrameLevel(lvl + 10) end
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  -- 底色當退路（材質不存在時遊戲顯示透明），上面一層羊皮紙材質
  Detail.underlay, Detail.parchment = Theme.paint(frame)

  -- 「< 回清單」有框按鈕（Texture 拼框，與未選分頁同一組框色）；寬度依文字
  backBtn = CreateFrame("Button", nil, frame)
  backBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -8)
  backBtn.box = Theme.box(backBtn)
  Theme.boxColor(backBtn.box, Theme.BTN_BG, Theme.BTN_EDGE)
  backBtn.fs = backBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  backBtn.fs:SetPoint("CENTER", backBtn, "CENTER", 0, 0)
  backBtn.fs:SetText(L("backToList"))
  backBtn.fs:SetTextColor(HEAD[1], HEAD[2], HEAD[3])
  local bw = backBtn.fs:GetStringWidth()
  if type(bw) ~= "number" or bw <= 0 then bw = 80 end
  backBtn:SetSize(bw + 16, 22)
  backBtn:SetScript("OnClick", function() Detail.Close() end)
  Detail.backButton = backBtn

  for i = 1, MAXL do
    local b = CreateFrame("Button", nil, frame)
    b:SetWidth(LINEW)   -- 整行寬都是可點區域
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.fs:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.fs:SetWidth(LINEW)
    b.fs:SetJustifyH("LEFT")
    -- 連結底線（FontString 沒有底線：文字下方 1px Texture）與起點「!」圖示；一般文字列藏起來
    b.ul = b:CreateTexture(nil, "ARTWORK")
    b.ul:Hide()
    b.pin = b:CreateTexture(nil, "ARTWORK")
    b.pin:SetSize(PIN, PIN)
    b.pin:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    if Theme.QUEST_ICON then
      b.pin:SetTexture(Theme.QUEST_ICON)
      hasPinTex = true
    end
    b.pin:Hide()
    b:SetScript("OnClick", onLine)
    b:SetScript("OnEnter", function(self) self.hovering = true; if self.isLink then linkColor(self) end end)
    b:SetScript("OnLeave", function(self) self.hovering = nil; if self.isLink then linkColor(self) end end)
    -- 自己或上層（明細、面板、地圖）被藏起來時不一定有 OnLeave：在這裡清掉懸停，重用時不會亮著
    b:SetScript("OnHide", function(self) self.hovering = nil; if self.isLink then linkColor(self) end end)
    b:Hide()
    buttons[i] = b
  end
  -- 量文字高度用的 FontString（固定全寬；不借用列按鈕的，列按鈕的寬度會因連結縮排而變）。
  -- 量完清空文字，不會畫出東西
  measure = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  measure:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, 0)
  measure:SetWidth(LINEW)
  measure:SetJustifyH("LEFT")
  Detail.measure = measure   -- 測試用
  for i = 1, MAXITEMS do
    local b = CreateFrame("Button", nil, frame)
    b.itemBtn = true
    b:SetSize(LINEW, ICON)
    b.border = b:CreateTexture(nil, "BACKGROUND")   -- 品質色框墊在圖示底下（同層級先後不保證，實機曾整格只剩框色）
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.border:SetSize(ICON, ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetSize(ICON - 2, ICON - 2)
    b.nameFs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.nameFs:SetPoint("LEFT", b, "LEFT", ICON + 4, 0)
    b.nameFs:SetWidth(LINEW - ICON - 8)
    b.nameFs:SetJustifyH("LEFT")
    b.nameFs:SetWordWrap(false)
    b.countFs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.countFs:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT", ICON - 3, 2)
    b.countFs:SetJustifyH("RIGHT")
    b:SetScript("OnEnter", function(self)
      if not (self.itemId and GameTooltip) then return end
      if type(GameTooltip.SetItemByID) ~= "function" and type(GameTooltip.SetHyperlink) ~= "function" then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if type(GameTooltip.SetItemByID) == "function" then
        GameTooltip:SetItemByID(self.itemId)
      elseif type(GameTooltip.SetHyperlink) == "function" then
        GameTooltip:SetHyperlink("item:" .. self.itemId)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    b:SetScript("OnClick", function(self) Detail.ModifiedItemClick(self.itemId) end)
    b:Hide()
    ibtns[i] = b
  end
  frame:SetScript("OnMouseWheel", function(_, delta)
    offset = offset - delta * 2
    render()
  end)
  frame:SetScript("OnShow", function()
    if stale and cur then build(); render() end
  end)
  frame:Hide()
  Detail.frame = frame
end

ns.Core.on("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  buildFrame()
end)
-- 獎勵物品的修飾鍵點擊（跟背包物品一樣）：Shift＝把物品連結貼進聊天、Ctrl＝試穿；一般點擊不動作。
-- 有完整連結（C_Item.GetItemInfo 第 2 個回傳值）就交給遊戲的 HandleModifiedItemClick，由遊戲依修飾鍵決定；
-- 沒有 HandleModifiedItemClick 就自己分流到 ChatEdit_InsertLink／DressUpItemLink。
-- 物品還沒快取：試穿只要 id，用 "item:<id>"；聊天連結必須是完整連結，請求載入，GET_ITEM_INFO_RECEIVED 時再貼（只貼一次）。
local linkWanted   -- Shift 點了還沒快取的物品：載入後要貼進聊天的物品 id
local function itemLink(id)
  local info = C_Item and C_Item.GetItemInfo
  if type(info) ~= "function" then return nil end
  local ok, a, b = pcall(info, id)
  if not ok then return nil end
  if type(a) == "table" then b = a.hyperlink or a.itemLink end
  return safe(b, "string")
end
local function keyDown(fn) return type(fn) == "function" and fn() and true or false end

function Detail.ModifiedItemClick(id)
  if type(id) ~= "number" then return false end
  local shift, ctrl = keyDown(IsShiftKeyDown), keyDown(IsControlKeyDown)
  if not (shift or ctrl) then return false end
  local link = itemLink(id)
  if link then
    if type(HandleModifiedItemClick) == "function" then
      HandleModifiedItemClick(link)
    elseif shift and type(ChatEdit_InsertLink) == "function" then
      ChatEdit_InsertLink(link)
    elseif ctrl and type(DressUpItemLink) == "function" then
      DressUpItemLink(link)
    end
    return true
  end
  if ctrl then
    if type(DressUpItemLink) == "function" then DressUpItemLink("item:" .. id) end
  else
    linkWanted = id
    if C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then C_Item.RequestLoadItemDataByID(id) end
  end
  return true
end

ns.Core.on("GET_ITEM_INFO_RECEIVED", function(itemId)
  if linkWanted == nil or itemId ~= linkWanted then return end
  local link = itemLink(itemId)
  if not link then return end
  linkWanted = nil
  if type(ChatEdit_InsertLink) == "function" then ChatEdit_InsertLink(link) end
end)

ns.Core.on("GET_ITEM_INFO_RECEIVED", function(itemId)
  if not cur or not pending[itemId] then return end
  pending[itemId] = nil
  Detail.Refresh()
end)
function Detail.BuildCount() return builds end
function Detail.IsStale() return stale end
