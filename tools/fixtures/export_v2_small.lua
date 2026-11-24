-- 由 tools/build_data.py 產生，請勿手改。資料來源與授權見 NOTICE。
-- 打包格式（說明見 tools/build_data.py 開頭）：程式不直接讀 QMG_Data，一律走 Data.lua 的 ns.Data。
-- 欄位 nil = 未知，空表 = 已知為空。位置式欄位（解碼後）：
--   sk = {skillId, value}；ri = {{itemId, count, isChoice}, ...}
--   sk[2] 與 ri[*][2] 可能是 nil（未知，不是 0 或 1）：只能用 [1]/[2]/[3] 取值，禁止對這些表用 # 或 ipairs
--   s / e = entity 鍵（"n<id>" npc、"o<id>" object）
QMG_Meta = {schema=3,sourceVersion="fixture-1",officialExportDate="2026-11-01",wagoBuild="1.15.0.99999",exportedAt="2026-11-23T00:00:00+00:00",env="prod",quests=5,entities=2}
QMG_Data = {fmt=1}
QMG_Data.q = {
ix="9900001:236,9900002:158,9900003:113,9900004:50,9900005:149",
s="{n={zh=s15:測試任務一,en=s14:Test Quest One},lv=7,min=5,f=s1:A,cls={1,2},race={1,4},sk={164,25},maps={1429,1453},s={s8:n9901001},e={s8:o9901001},prev={},next={9900002},excl={9900003},ri={{12345,2,F},{12346,1,T}},xp=450,cu=1200,t=0}{n={en=s17:Only English Name},lv=8,min=6,f=s1:H,maps={1453},s={s8:o9901001},e={s8:n9901001},prev={9900001},next={},conc={9900004,9900005},ri={},xp=0,cu=0,t=1}{n={zh=s15:無地圖任務,en=s12:No Map Quest},lv=1,min=1,cls={},race={},maps={},s={},e={},ri={},xp=10,cu=5,t=0}{n={en=s18:Unknown Everything},lv=3,min=2,maps={}}{n={en=s10:Null Slots},lv=4,min=3,cls={},race={},sk={171,~},maps={},s={},e={},prev={},next={},conc={},excl={},ri={{159,~,T},{118,3,F}},xp=1,cu=2,t=0}"}
QMG_Data.e = {
ix="n9901001:91,o9901001:48",
s="{n=s20:Fixture \"Quoter\" NPC,sp={{m=1429,x=45.3,y=60.1},{m=1453,x=12,y=80}},zh=s9:測試NPC}{n=s14:Fixture Object,sp={{m=1453,x=30,y=31.5}}}"}
QMG_Data.m = {
ix="1429:9,1453:17",
s="{9900001}{9900001,9900002}"}
QMG_Data.d = {
ix="9900001:39,9900002:30",
s="s35:甲\n他說：「\"快來\"」\n乙\\丙s26:Plain English description."}
