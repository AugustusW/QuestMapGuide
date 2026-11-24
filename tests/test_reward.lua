-- 明細文字工具 ns.Reward：金錢、經驗值（A1）、描述代入。API 都是每個測試各自 stub。
local function setup(opts)
  opts = opts or {}
  H.reset({ locale = opts.locale or "zhTW", missing = opts.missing })
  QMG_Data, QMG_Meta = nil, nil
  dofile(H.dir .. "/tools/fixtures/export_v2_small.lua")
  local function g(k, v) _G[k] = v; H.installed[k] = true end
  local S = { sel = 0, setCalls = 0, rewardCalls = 0, onLog = {}, combat = false }
  if opts.status ~= false then
    g("C_QuestLog", {
      IsOnQuest = function(id) return S.onLog[id] == true end,
      IsQuestFlaggedCompleted = function() return false end,
      GetNumQuestLogEntries = function() return 0, 0 end,
      GetInfo = function() return nil end,
      GetLogIndexForQuestID = (not opts.noIndex) and function(id) return S.onLog[id] and 3 or nil end or nil,
      GetSelectedQuest = (not opts.noGet) and function() return S.sel end or nil,
      SetSelectedQuest = (not opts.noSet) and function(id)
        S.setCalls = S.setCalls + 1
        if opts.setErr then S.sel = id; error("boom") end
        S.sel = id
      end or nil,
    })
  end
  g("InCombatLockdown", function() return S.combat end)
  if not opts.noXpApi then
    g("GetQuestLogRewardXP", function(id)
      S.rewardCalls = S.rewardCalls + 1
      if S.sel ~= id then return 0 end   -- 像遊戲：只回「目前選取任務」的值
      return opts.xpValue or 900
    end)
  end
  if not opts.noSecretApi then
    g("issecretvalue", function(v) return opts.secretXp and v == (opts.xpValue or 900) or false end)
  end
  local ns = H.load(H.tocFiles("QuestMapGuide_Forever.toc"))
  return ns, S, g
end

-- 金錢
local ns = setup()
local R = ns.Reward
H.eq(type(R), "table", "ns.Reward 存在")
local m = R.money(12345)
H.check(m:find("1|TInterface\\MoneyFrame\\UI%-GoldIcon", 1) ~= nil, "12345 含 1 金圖示：" .. tostring(m))
H.check(m:find("23|TInterface\\MoneyFrame\\UI%-SilverIcon") ~= nil, "含 23 銀圖示")
H.check(m:find("45|TInterface\\MoneyFrame\\UI%-CopperIcon") ~= nil, "含 45 銅圖示")
m = R.money(10000)
H.check(m:find("GoldIcon") ~= nil and not m:find("SilverIcon") and not m:find("CopperIcon"), "10000 只含金")
H.eq(R.money(0), nil, "money(0) nil")
H.eq(R.money(nil), nil, "money(nil) nil")
H.eq(R.money("x"), nil, "money(非數字) nil")
local ns2, _, g2 = setup()
g2("GetMoneyString", function(cu) return "STUB" .. cu end)
H.eq(ns2.Reward.money(12345), "STUB12345", "有 GetMoneyString 用它")
H.eq(ns2.Reward.money(0), nil, "有 GetMoneyString 時 0 仍是 nil")
g2("GetMoneyString", function() return nil end)
H.check(ns2.Reward.money(5):find("CopperIcon") ~= nil, "GetMoneyString 回非字串退回自組")
g2("GetMoneyString", function() error("x") end)
H.check(ns2.Reward.money(5):find("CopperIcon") ~= nil, "GetMoneyString 拋錯退回自組")

-- 經驗值
local ns3, S3 = setup()
S3.onLog[100] = true
H.eq(ns3.Reward.xp(100, { xp = 50 }), 900, "日誌中且 API 回 900 -> 900")
H.eq(S3.sel, 0, "原選取已還原")
H.eq(ns3.Reward.xp(101, { xp = 50 }), 50, "不在日誌 -> 資料值")
H.eq(ns3.Reward.xp(101, {}), nil, "不在日誌且無資料 -> nil")
H.eq(ns3.Reward.xp(100, nil), 900, "q 為 nil 仍可取遊戲值")
H.eq(ns3.Reward.xp(101, nil), nil, "兩者皆無 nil")

local n, S = setup({ noXpApi = true }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "API 不存在 -> 資料值")
n, S = setup({ noIndex = true }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "GetLogIndexForQuestID 不存在 -> 資料值")
n, S = setup({ secretXp = true }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "API 回保密值 -> 資料值")
H.eq(S.sel, 0, "保密值路徑原選取已還原")
n, S = setup(); S.onLog[100] = true; S.combat = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "戰鬥中 -> 資料值")
H.eq(S.setCalls, 0, "戰鬥中不呼叫 SetSelectedQuest")
n, S = setup({ noGet = true }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "缺 GetSelectedQuest -> 資料值")
H.eq(S.setCalls, 0, "缺 GetSelectedQuest 不呼叫 SetSelectedQuest")
n, S = setup({ noSet = true }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "缺 SetSelectedQuest -> 資料值")
n, S = setup({ setErr = true }); S.sel = 7; S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "SetSelectedQuest 拋錯 -> 資料值")
H.eq(S.sel, 7, "拋錯後原選取已還原")
n, S = setup({ xpValue = 0 }); S.onLog[100] = true
H.eq(n.Reward.xp(100, { xp = 50 }), 50, "API 回 0 視為沒有 -> 資料值")

-- 描述代入
local function unit(g, t)
  g("UnitName", function() return t.name end)
  g("UnitRace", function() return t.race end)
  g("UnitClass", function() return t.class end)
  if t.sex then g("UnitSex", function() return t.sex end) end
end
local nn, _, gg = setup()
unit(gg, { name = "阿古", race = "人類", class = "戰士" })
H.eq(nn.Reward.text("你好{name}，{race}{class}"), "你好阿古，人類戰士", "三個佔位代入")
H.eq(nn.Reward.text("{name}和{name}"), "阿古和阿古", "同佔位多次")
H.eq(nn.Reward.text("$g小子:姑娘;"), "小子", "UnitSex 缺 -> 甲")
gg("UnitSex", function() return 2 end)
H.eq(nn.Reward.text("$g小子:姑娘;"), "小子", "UnitSex 2 -> 甲")
gg("UnitSex", function() return 3 end)
H.eq(nn.Reward.text("你好，$g小子:姑娘;！$g他:她;"), "你好，姑娘！她", "UnitSex 3 -> 乙")
gg("UnitName", function() return nil end)
H.eq(nn.Reward.text("{name}來了"), "{name}來了", "UnitName 回 nil 保留佔位")
gg("UnitName", function() return 5 end)
H.eq(nn.Reward.text("{name}來了"), "{name}來了", "UnitName 非字串保留佔位")
gg("UnitName", function() error("x") end)
H.eq(nn.Reward.text("{name}來了"), "{name}來了", "UnitName 拋錯保留佔位")
gg("UnitName", function() return "秘" end)
gg("issecretvalue", function(v) return v == "秘" end)
H.eq(nn.Reward.text("{name}來了"), "{name}來了", "UnitName 保密值保留佔位")
H.eq(nn.Reward.text("x%1y"), "x%1y", "百分號原樣")
H.eq(nn.Reward.text(nil), "", "nil -> 空字串")
-- 值含 % 不可被當成取代樣式
gg("issecretvalue", function() return false end)
gg("UnitName", function() return "a%1b" end)
H.eq(nn.Reward.text("{name}"), "a%1b", "名稱含百分號原樣")
-- 名稱含 $g 不可被再解讀
gg("UnitName", function() return "$g甲:乙;" end)
gg("UnitSex", function() return 3 end)
H.eq(nn.Reward.text("{name}"), "$g甲:乙;", "名稱含 $g 原樣")
-- 保密性別：當成甲
gg("UnitSex", function() return 3 end)
gg("issecretvalue", function(v) return v == 3 end)
H.eq(nn.Reward.text("$g小子:姑娘;"), "小子", "UnitSex 保密 -> 甲")
-- 保密字串不被使用（比較前先確認；Lua 字串無法帶會拋錯的 metamethod，這裡驗結果）
gg("UnitName", function() return "秘" end)
gg("issecretvalue", function(v) return v == "秘" end)
H.eq(nn.Reward.text("{name}"), "{name}", "保密字串保留佔位")
-- 沒有 issecretvalue：fail-closed
local nf, Sf, gf = setup({ noSecretApi = true }); Sf.onLog[100] = true
unit(gf, { name = "阿古", race = "人類", class = "戰士" })
H.eq(nf.Reward.text("{name}{race}"), "{name}{race}", "無 issecretvalue 保留佔位")
H.eq(nf.Reward.xp(100, { xp = 50 }), 50, "無 issecretvalue 不用遊戲經驗值")
H.eq(Sf.setCalls, 0, "無 issecretvalue 不選取任務")
gf("GetMoneyString", function() return "STUB" end)
H.check(nf.Reward.money(5):find("CopperIcon") ~= nil, "無 issecretvalue 時 GetMoneyString 結果不採用")
