-- 明細獎勵物品按鈕的修飾鍵點擊：Shift＝把物品連結貼進聊天、Ctrl＝試穿，跟背包物品一樣；一般點擊不變
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = "zhTW" })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
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
  _G.issecretvalue = function() return false end; H.installed.issecretvalue = true
  local st = { shift = false, ctrl = false, cache = {}, handled = {}, inserted = {}, dressed = {}, requested = {} }
  _G.C_Item = {
    GetItemInfo = function(id) local n = st.cache[id]; if n then return n, "|cffffffff|Hitem:" .. id .. "|h[" .. n .. "]|h|r" end end,
    RequestLoadItemDataByID = function(id) st.requested[#st.requested + 1] = id end,
  }
  H.installed.C_Item = true
  _G.IsShiftKeyDown = function() return st.shift end; H.installed.IsShiftKeyDown = true
  _G.IsControlKeyDown = function() return st.ctrl end; H.installed.IsControlKeyDown = true
  if not opts.noHandle then
    _G.HandleModifiedItemClick = function(link) st.handled[#st.handled + 1] = link; return true end
    H.installed.HandleModifiedItemClick = true
  end
  _G.ChatEdit_InsertLink = function(link) st.inserted[#st.inserted + 1] = link; return true end; H.installed.ChatEdit_InsertLink = true
  _G.DressUpItemLink = function(link) st.dressed[#st.dressed + 1] = link; return true end; H.installed.DressUpItemLink = true
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  H.fire("ADDON_LOADED", "QuestMapGuide")
  wm:Show(); ns.Panel.frame:Show()
  ns.Panel.Refresh(1429)
  return ns, st
end
local function itemBtn(id)
  for _, f in ipairs(H.frames) do if f.itemBtn and f._shown and f.itemId == id then return f end end
end
local function click(b) b._scripts.OnClick(b, "LeftButton") end

-- 已快取：Shift／Ctrl 都交給遊戲的 HandleModifiedItemClick（遊戲依修飾鍵決定貼連結或試穿）
do
  local ns, st = setup()
  st.cache[12345] = "Fixture Sword"
  ns.Panel.Select(9900001)
  local b = itemBtn(12345)
  H.check(b ~= nil and b._scripts.OnClick ~= nil, "物品按鈕可點")
  click(b)
  H.eq(#st.handled + #st.inserted + #st.dressed, 0, "一般點擊：不貼連結、不試穿")
  H.eq(ns.Detail.Current(), 9900001, "一般點擊：明細不變")
  st.shift = true
  click(b)
  H.eq(st.handled[1], "|cffffffff|Hitem:12345|h[Fixture Sword]|h|r", "Shift：物品連結交給 HandleModifiedItemClick")
  st.shift, st.ctrl = false, true
  click(b)
  H.eq(#st.handled, 2, "Ctrl：同樣交給 HandleModifiedItemClick（遊戲處理試穿）")
end

-- 沒有 HandleModifiedItemClick：自己分流 Shift → ChatEdit_InsertLink、Ctrl → DressUpItemLink
do
  local ns, st = setup({ noHandle = true })
  st.cache[12345] = "Fixture Sword"
  ns.Panel.Select(9900001)
  local b = itemBtn(12345)
  st.shift = true; click(b)
  H.eq(st.inserted[1], "|cffffffff|Hitem:12345|h[Fixture Sword]|h|r", "Shift：貼進聊天")
  st.shift, st.ctrl = false, true; click(b)
  H.eq(st.dressed[1], "|cffffffff|Hitem:12345|h[Fixture Sword]|h|r", "Ctrl：試穿")
end

-- 物品還沒快取
do
  local ns, st = setup()
  ns.Panel.Select(9900001)
  local b = itemBtn(12345)
  -- Ctrl：試穿只要物品 id，用 "item:<id>"
  st.ctrl = true; click(b)
  H.eq(st.dressed[1], "item:12345", "未快取 Ctrl：用 item:<id> 試穿")
  H.eq(#st.handled, 0, "未快取 Ctrl：不交給 HandleModifiedItemClick（沒有連結）")
  -- Shift：聊天連結需要完整連結，請求載入，載入後才貼
  st.ctrl, st.shift = false, true; click(b)
  H.eq(#st.inserted, 0, "未快取 Shift：還沒有連結，先不貼")
  H.eq(st.requested[1], 12345, "未快取 Shift：請求載入物品資料")
  st.cache[12345] = "Fixture Sword"
  H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
  H.eq(st.inserted[1], "|cffffffff|Hitem:12345|h[Fixture Sword]|h|r", "載入後把連結貼進聊天")
  H.fire("GET_ITEM_INFO_RECEIVED", 12345, true)
  H.eq(#st.inserted, 1, "只貼一次")
  -- 別的物品載入不會觸發
  st.cache[12345] = nil
  click(b)
  H.fire("GET_ITEM_INFO_RECEIVED", 99999, true)
  H.eq(#st.inserted, 1, "別的物品載入不貼")
  -- 修飾鍵相關 API 都不存在：不報錯
  _G.IsShiftKeyDown, _G.IsControlKeyDown = nil, nil   -- 遊戲沒有這兩個函式時
  H.check(pcall(click, b), "沒有 IsShiftKeyDown／IsControlKeyDown 不報錯")
end

-- Probe.APIS 含新用到的名稱
do
  local ns = setup()
  local want = { HandleModifiedItemClick = true, ChatEdit_InsertLink = true, DressUpItemLink = true,
    IsShiftKeyDown = true, IsControlKeyDown = true, ["C_Item.RequestLoadItemDataByID"] = true }
  for _, n in ipairs(ns.Probe.APIS) do want[n] = nil end
  H.check(next(want) == nil, "Probe.APIS 含修飾鍵點擊用到的名稱（缺：" .. tostring(next(want)) .. "）")
end
