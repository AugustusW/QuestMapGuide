-- 羊皮紙配色：清單面板（Panel）與明細（Detail）共用，只在這裡定義一份。
-- 材質不存在時遊戲顯示透明，所以底下墊一層同色系實色。
local ADDON, ns = ...

local Theme = {}
ns.Theme = Theme

Theme.TEX = "Interface\\QuestFrame\\QuestBG"
-- 面板寬（清單與明細共用）。使用者 2026-11-25：往右加寬，讓起點「NPC · 地圖(x, y)」顯示完整
Theme.PANEL_W = 360
Theme.TEXCOORD = { 0, 0.5859, 0, 0.6641 }   -- QuestBG 是 512x512 貼圖集，羊皮紙在左上角約 300x340
Theme.UNDER = { 0.80, 0.69, 0.50, 1 }

-- 0.0.4 起色值直接寫 RGB hex（與 mockup 色票逐字對照）；a 是透明度（Texture 底色用）
function Theme.rgb(hex, a)
  local function c(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
  return { c(1), c(3), c(5), a }
end
local rgb = Theme.rgb

Theme.INK = { 0.18, 0.12, 0.06 }        -- 一般文字：深褐（2e1f0f）
Theme.HEAD = { 0.30, 0.16, 0.03 }       -- 標題、分段標題：深褐
Theme.LINK = rgb("0b2f8a")              -- 連結：深藍
Theme.LINK_HOVER = rgb("2456c8")        -- 連結懸停：亮一階的藍（mockup 沒定，取同色相提高亮度）
Theme.MUTED = rgb("4f4439")             -- 副標、未選分頁文字、灰色資訊
Theme.DISABLED = rgb("85775f")          -- 停用的勾選框標籤
-- 可接任務圖示：遊戲 NPC 頭上／對話框裡的黃色「!」。清單可接列、明細起點連結、地圖標記共用這一張
-- （使用者選 A：原本的藏寶圖物品圖示在地圖上像錯誤標記）。材質路徑無法用 API 探測，需實機確認
Theme.QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
Theme.LOG = Theme.LINK                  -- 進行中「?」：連結藍
Theme.DIM_ALPHA = 0.70                  -- 淡化列：羊皮紙底上 0.55 仍太淡，改 0.70
Theme.HINT = { 0.70, 0.70, 0.70 }       -- 搜尋框提示字：框是遊戲的深色輸入框，用淺灰
-- 已完成勾勾：材質 UI-CheckBox-Check 本身是金色 (1, .82, 0)，SetVertexColor 是相乘，
-- 要畫面上呈現 693b00（.412, .231, 0），頂點色取 (.412/1, .231/.82, 0)
Theme.CHECK_SHOWN = rgb("693b00")
Theme.CHECK = { Theme.CHECK_SHOWN[1] / 1, Theme.CHECK_SHOWN[2] / 0.82, 0 }

-- 分頁按鈕（Texture 拼的框，不用內建深色分頁模板）
Theme.TAB_ON_BG = rgb("7a1a10", 1)      -- 選中：深紅底
Theme.TAB_ON_EDGE = rgb("4d0f08", 1)
Theme.TAB_ON_TEXT = rgb("f6ebcc")       -- 選中：淺字
Theme.TAB_OFF_BG = rgb("fff6dc", 0.28)  -- 未選：半透明淺底
Theme.TAB_OFF_EDGE = rgb("6b4a2a", 1)   -- 未選：褐框
Theme.TAB_OFF_TEXT = Theme.MUTED
Theme.BTN_BG = rgb("fff6dc", 0.30)      -- 「回清單」按鈕底
Theme.BTN_EDGE = Theme.TAB_OFF_EDGE

-- 清單列
Theme.ROW_SEP = rgb("5a3714", 0.28)     -- 每列底部 1px 分隔線
Theme.ROW_HOVER = rgb("46230a", 0.24)   -- 懸停整列反白
Theme.ROW_BAR = rgb("7a1a10", 1)        -- 懸停左緣 3px 色條

-- 明亮色（難度色、品質色）在羊皮紙上太淡：乘 0.6 加深；白色（普通品質）直接用一般文字色
function Theme.darken(r, g, b)
  if r >= 0.95 and g >= 0.95 and b >= 0.95 then return Theme.INK[1], Theme.INK[2], Theme.INK[3] end
  return r * 0.6, g * 0.6, b * 0.6
end

-- 依遊戲顏色分類，對照羊皮紙上讀得出來的色值；分不出來的回傳 nil（呼叫端退回 darken）
local function nearest(r, g, b, refs)
  for _, e in ipairs(refs) do
    local c = e[1]
    if math.abs(r - c[1]) < 0.08 and math.abs(g - c[2]) < 0.08 and math.abs(b - c[3]) < 0.08 then return e[2] end
  end
end
-- 難度色（Filter.color 回傳的遊戲色：紅 1,.1,.1／橙 1,.5,.25／黃 1,1,0／綠 .25,.75,.25／灰 .5,.5,.5）
-- 0.0.4：整組加深到對羊皮紙中間色 cdb07f 對比 4.5:1 以上（使用者選 A）
local LEVEL_REF = {
  { { 1, 0.1, 0.1 }, rgb("8e0a0a") },
  { { 1, 0.5, 0.25 }, rgb("753200") },
  { { 1, 1, 0 }, rgb("594100") },
  { { 0.25, 0.75, 0.25 }, rgb("125212") },
  { { 0.5, 0.5, 0.5 }, rgb("494640") },
}
-- 物品品質色：灰（poor）／白（common）／綠／藍／紫
local QUALITY_REF = {
  { { 0.62, 0.62, 0.62 }, { 0.40, 0.38, 0.35 } },
  { { 0.12, 1, 0 }, rgb("125212") },   -- 綠色物品名與綠色難度同色（mockup 明細）
  { { 0, 0.44, 0.87 }, { 0.05, 0.30, 0.65 } },
  { { 0.64, 0.21, 0.93 }, { 0.45, 0.15, 0.60 } },
}
function Theme.levelInk(r, g, b)
  local c = nearest(r, g, b, LEVEL_REF)
  if c then return c[1], c[2], c[3] end
  return Theme.darken(r, g, b)
end
function Theme.qualityInk(r, g, b)
  if r >= 0.95 and g >= 0.95 and b >= 0.95 then return Theme.INK[1], Theme.INK[2], Theme.INK[3] end
  local c = nearest(r, g, b, QUALITY_REF)
  if c then return c[1], c[2], c[3] end
  return Theme.darken(r, g, b)
end

-- 0..1 的顏色表 -> |cffRRGGBB（文字內嵌色碼用）
function Theme.hex(c)
  local function h(v) return string.format("%02x", math.floor(v * 255 + 0.5)) end
  return "|cff" .. h(c[1]) .. h(c[2]) .. h(c[3])
end

-- 在 frame 上畫羊皮紙背景（BACKGROUND sublevel 0 底色、1 材質）；回傳 底色, 材質
function Theme.paint(frame)
  local under = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
  under:SetAllPoints()
  under:SetColorTexture(Theme.UNDER[1], Theme.UNDER[2], Theme.UNDER[3], Theme.UNDER[4])
  local parch = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  parch:SetAllPoints()
  parch:SetTexture(Theme.TEX)
  parch:SetTexCoord(Theme.TEXCOORD[1], Theme.TEXCOORD[2], Theme.TEXCOORD[3], Theme.TEXCOORD[4])
  return under, parch
end

-- 用 Texture 拼一個有框的方塊（分頁、回清單按鈕）：底色一層＋四邊 1px。
-- 每邊兩個錨點決定長度，SetSize 只負責 1px 粗細（Texture 探測清單沒有 SetWidth／SetHeight，用 SetSize）。回傳 { bg, top, bottom, left, right }
function Theme.box(frame)
  local b = { bg = frame:CreateTexture(nil, "BACKGROUND") }
  b.bg:SetAllPoints()
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do b[side] = frame:CreateTexture(nil, "BORDER") end
  b.top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); b.top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); b.top:SetSize(1, 1)
  b.bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); b.bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); b.bottom:SetSize(1, 1)
  b.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); b.left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); b.left:SetSize(1, 1)
  b.right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); b.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); b.right:SetSize(1, 1)
  return b
end

-- 方塊上色：fill 底色、edge 框色（含透明度）
function Theme.boxColor(b, fill, edge)
  b.bg:SetColorTexture(fill[1], fill[2], fill[3], fill[4] or 1)
  for _, side in ipairs({ "top", "bottom", "left", "right" }) do
    b[side]:SetColorTexture(edge[1], edge[2], edge[3], edge[4] or 1)
  end
end
