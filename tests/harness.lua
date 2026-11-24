-- 用假的 WoW API 跑 QuestMapGuide 的純邏輯與載入流程（不驗畫面；範本來源：GatheringGuide）
-- 用法：luajit tests/harness.lua <addon 資料夾> <測試檔...>
-- 與 BigFontTuner 的萬用 stub 不同：假物件只回應白名單裡的方法，其他一律是 nil，
-- 呼叫不存在的方法會像遊戲一樣報「attempt to call a nil value」（記憶 2023）。
-- 白名單來源：tests/api_manifest.lua（遊戲內 /qmg probe 傾印；探測前是暫定清單）。
H = { dir = arg[1] or ".", failed = 0, passed = 0 }
local out = io.write

function H.check(c, msg)
  if c then H.passed = H.passed + 1 else H.failed = H.failed + 1; out("FAIL ", msg, "\n") end
end
function H.eq(a, b, msg)
  H.check(a == b, msg .. "（期望 " .. tostring(b) .. "，得到 " .. tostring(a) .. "）")
end

local DEFAULT_MANIFEST = dofile(H.dir .. "/tests/api_manifest.lua")
local manifest = DEFAULT_MANIFEST
H.manifest = manifest

-- 依白名單建立假 widget：只有清單內的方法存在
local function widget(kind)
  local w = { _kind = kind, _scripts = {}, _events = {}, _shown = false, _text = "" }
  local impl = {
    SetScript = function(self, ev, fn) self._scripts[ev] = fn end,
    GetScript = function(self, ev) return self._scripts[ev] end,
    HookScript = function(self, ev, fn) local old = self._scripts[ev]
      self._scripts[ev] = function(...) if old then old(...) end fn(...) end end,
    RegisterEvent = function(self, ev)
      -- 測試設了 H.eventWhitelist 時，不認得的事件名丟錯（像遊戲：Frame:RegisterEvent 對未知事件報錯）
      if H.eventWhitelist and not H.eventWhitelist[ev] then error("Frame:RegisterEvent(): Unknown event: " .. tostring(ev)) end
      self._events[ev] = true
    end,
    UnregisterEvent = function(self, ev) self._events[ev] = nil end,
    Show = function(self)
      local was = self._shown
      self._shown = true
      -- 模擬遊戲：由隱藏變顯示時觸發 OnShow；子物件（自己已設為顯示的）也跟著觸發
      if not was then
        if self._scripts.OnShow then self._scripts.OnShow(self) end
        for _, child in ipairs(self._children or {}) do
          if child._shown and child._scripts.OnShow then child._scripts.OnShow(child) end
        end
      end
    end,
    Hide = function(self)
      local was = self._shown
      self._shown = false
      if was and self._scripts.OnHide then self._scripts.OnHide(self) end
      for _, child in ipairs(self._children or {}) do
        if child._scripts.OnHide then child._scripts.OnHide(child) end
      end
    end,
    SetWordWrap = function(self, v) self._wrap = v end,
    -- 啟用狀態（CheckButton:Disable／Enable），測試用
    Disable = function(self) self._disabled = true end,
    Enable = function(self) self._disabled = false end,
    IsEnabled = function(self) return not self._disabled end,
    SetShown = function(self, v) if v then self:Show() else self:Hide() end end,
    SetChecked = function(self, v) self._checked = v and true or false end,
    GetChecked = function(self) return self._checked or false end,
    -- 記錄設定值，測試用（顏色、材質）
    SetTextColor = function(self, r, g, b) self._tc = { r, g, b } end,
    SetTexture = function(self, t) self._tex = t end,
    SetVertexColor = function(self, r, g, b) self._vc = { r, g, b } end,
    SetTexCoord = function(self, ...) self._texcoord = { ... } end,
    SetColorTexture = function(self, r, g, b, a) self._ct = { r, g, b, a } end,
    SetAlpha = function(self, a) self._alpha = a end,
    GetAlpha = function(self) return self._alpha or 1 end,
    SetWidth = function(self, v) self._width = v end,
    SetHeight = function(self, v) self._height = v end,
    SetSize = function(self, w, h) self._width, self._height = w, h end,
    GetHeight = function(self) return self._height or 0 end,
    SetPoint = function(self, a, b, c, x, y) self._pt = { a, b, c, x, y } end,
    ClearAllPoints = function(self) self._pt = nil end,
    SetFocus = function(self) H.focus = self end,
    ClearFocus = function(self) if H.focus == self then H.focus = nil end end,
    HasFocus = function(self) return H.focus == self end,
    IsShown = function(self) return self._shown end,
    IsVisible = function(self)
      if not self._shown then return false end
      return self._parent == nil or self._parent:IsVisible()
    end,
    SetText = function(self, t) self._text = t end,
    SetVerticalScroll = function(self, v) self._scroll = v end,
    GetVerticalScroll = function(self) return self._scroll or 0 end,
    GetText = function(self) return self._text end,
    GetStringWidth = function(self) return #self._text * 6 end,
    -- 粗略模擬換行：每行 14 高；\n 另算一行。設了寬度時每 width/6 位元組一行（與 GetStringWidth 的每位元組 6 一致），
    -- 沒設寬度每 60 位元組一行；SetWordWrap(false) 不換行（遊戲：超出寬度截斷）
    GetStringHeight = function(self)
      local per = self._width and math.max(1, math.floor(self._width / 6)) or 60
      local lines = 0
      for seg in (self._text .. "\n"):gmatch("(.-)\n") do
        lines = lines + ((self._wrap == false) and 1 or math.max(1, math.ceil(#seg / per)))
      end
      return lines * 14
    end,
    CreateFontString = function(self) return widget("FontString") end,
    CreateTexture = function(self, _, layer, _, sub)
      local t = widget("Texture"); t._layer, t._sub = layer, sub; return t
    end,
  }
  local allowed = manifest.methods[kind] or manifest.methods.Frame
  return setmetatable(w, { __index = function(t, k)
    if not allowed[k] then return nil end
    return impl[k] or function(self) return self end
  end })
end
H.widget = widget

-- 探測傾印沒有列到、但遊戲內確認存在的全域（ErrProbe 2026-11-10，兩個版本）
local NOT_IN_MANIFEST = { print = true, date = true, time = true, seterrorhandler = true, geterrorhandler = true,
  debugstack = true, GetTime = true, StaticPopup_Show = true, StaticPopupDialogs = true }

-- print 預設記錄起來：Core 把 handler 錯誤用 print 回報（不再讓測試失敗），
-- 這裡在每次 reset 與每個測試檔結束時掃描，出現 handler 錯誤文字就算失敗。
H.printed = {}
local HANDLER_ERR = { "處理失敗：", " handler failed: " }
function H.checkPrinted(label)
  for _, line in ipairs(H.printed) do
    for _, pat in ipairs(HANDLER_ERR) do
      if line:find(pat, 1, true) then H.check(false, label .. " 有 handler 錯誤被印出：" .. line) end
    end
  end
  H.printed = {}
end

H.frames = {}
function H.reset(opts)
  opts = opts or {}
  H.checkPrinted("reset 前")
  -- 正式版用 tests/api_manifest_retail.lua；不指定時回到永恆白名單
  manifest = opts.manifest and dofile(H.dir .. "/tests/" .. opts.manifest) or DEFAULT_MANIFEST
  H.manifest = manifest
  H.frames = {}
  H.eventWhitelist = nil
  H.focus = nil
  H.mapId = 1429
  H.mapTypes = { [1429] = 3, [1453] = 3, [1500] = 3, [1414] = 2 }  -- 沒列到的地圖 GetMapInfo 回 nil
  QuestMapGuideDB, QuestMapGuideCharDB = nil, nil
  for k in pairs(_G) do if type(k) == "string" and k:sub(1, 6) == "SLASH_" then _G[k] = nil end end
  for k in pairs(H.installed or {}) do _G[k] = nil end
  H.installed = {}
  local api = {
    CreateFrame = function(kind, name, parent, template)
      if template and not manifest.templates[template] then error("Couldn't find inherited node \"" .. template .. "\"") end
      local f = widget(kind); f._name = name; table.insert(H.frames, f)
      -- 遊戲預設：EditBox 建立時 autoFocus 為 true，建立當下（可見時）就取得鍵盤焦點
      if kind == "EditBox" then H.focus = f end
      -- 子物件掛到最上層父物件，讓 Hide 能通知（模擬遊戲：父框架隱藏時子物件也觸發 OnHide）
      local top = parent
      while top and top._parent do top = top._parent end
      if parent then f._parent = parent; top._children = top._children or {}; table.insert(top._children, f) end
      if name then _G[name] = f end
      return f
    end,
    GetLocale = function() return opts.locale or "zhTW" end,
    GetBuildInfo = function() return "1.60.1", "70399", "Nov 1 2026", 16001 end,
    UIParent = widget("Frame"),
    UISpecialFrames = {},
    SlashCmdList = {},
    hash_SlashCmdList = {},
    C_AddOns = { GetAddOnMetadata = function(_, key) return ({ Version = "0.0.1", ["X-Build"] = "test" })[key] end },
    -- 大地圖：假的 WorldMapFrame 只有 GetMapID 與可被 hook 的 OnMapChanged（測試用 H.mapId 切換）
    WorldMapFrame = (function()
      local wm = widget("Frame")
      wm.GetMapID = function() return H.mapId end
      wm.OnMapChanged = function() end
      return wm
    end)(),
    C_Map = { GetMapInfo = function(id)
      local mt = H.mapTypes[id]
      if mt == nil then return nil end
      return { mapID = id, mapType = mt }
    end },
    hooksecurefunc = function(t, name, fn)
      local old = t[name]
      if type(old) ~= "function" then error("Attempt to hook a non-existing function: " .. tostring(name)) end
      t[name] = function(...) if old then old(...) end fn(...) end
    end,
    print = function(...)
      local t = {}
      for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
      H.printed[#H.printed + 1] = table.concat(t, " ")
    end,
    date = os.date,
    tinsert = table.insert,
    time = os.time,
  }
  if opts.projectId then api.WOW_PROJECT_ID = opts.projectId end
  for k, v in pairs(opts.extra or {}) do api[k] = v end
  for k, v in pairs(api) do
    if (manifest.globals[k] or NOT_IN_MANIFEST[k]) and not (opts.missing or {})[k] then
      _G[k] = v; H.installed[k] = true
    end
  end
  for k in pairs(opts.slashTaken or {}) do _G.hash_SlashCmdList[k] = true end
end

-- 讀 toc 的檔案清單（QuestMapGuide_Forever.toc）。
-- Data/ 底下的正式資料預設不載入：測試自己 dofile tools/fixtures/export_v2_small.lua；
-- 要驗正式資料時傳 withData = true。
function H.tocFiles(name, withData)
  local files = {}
  for line in io.lines(H.dir .. "/" .. name) do
    line = line:gsub("\r", "")
    if line ~= "" and not line:match("^#") and (withData or not line:match("^Data/")) then files[#files + 1] = line end
  end
  return files
end

-- 依 toc 順序載入 addon 檔案，回傳共用 ns
function H.load(files)
  local ns = {}
  for _, f in ipairs(files) do assert(loadfile(H.dir .. "/" .. f))("QuestMapGuide", ns) end
  return ns
end

function H.fire(ev, ...)
  for _, f in ipairs(H.frames) do
    local fn = f._scripts.OnEvent
    if fn and f._events[ev] then fn(f, ev, ...) end
  end
end

for i = 2, #arg do dofile(arg[i]); H.checkPrinted(arg[i]) end
out(string.format("%d passed, %d failed\n", H.passed, H.failed))
os.exit(H.failed == 0 and 0 or 1)
