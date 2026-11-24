-- 由 tools/build_data.py 產生，請勿手改。資料來源與授權見 NOTICE。
-- 欄位 nil = 未知，空表 = 已知為空。位置式欄位：
--   sk = {skillId, value}；ri = {{itemId, count, isChoice}, ...}
--   sk[2] 與 ri[*][2] 可能是 nil（未知，不是 0 或 1）：只能用 [1]/[2]/[3] 取值，禁止對這些表用 # 或 ipairs
--   s / e = QMG_Entities 的鍵（"n<id>" npc、"o<id>" object）
QMG_Quests = {}
QMG_Entities = {}
QMG_ByMap = {}
QMG_Meta = {schema=3,sourceVersion="fixture-1",officialExportDate="2026-11-01",wagoBuild="1.15.0.99999",exportedAt="2026-11-23T00:00:00+00:00",env="prod",quests=5,entities=2};
(function(Q)
Q[9900001]={n={zh="測試任務一",en="Test Quest One"},lv=7,min=5,f="A",cls={1,2},race={1,4},sk={164,25},maps={1429,1453},s={"n9901001"},e={"o9901001"},prev={},next={9900002},excl={9900003},ri={{12345,2,false},{12346,1,true}},xp=450,cu=1200,t=0}
Q[9900002]={n={en="Only English Name"},lv=8,min=6,f="H",maps={1453},s={"o9901001"},e={"n9901001"},prev={9900001},next={},conc={},ri={},xp=0,cu=0,t=1}
Q[9900003]={n={zh="無地圖任務",en="No Map Quest"},lv=1,min=1,cls={},race={},maps={},s={},e={},ri={},xp=10,cu=5,t=0}
Q[9900004]={n={en="Unknown Everything"},lv=3,min=2,maps={}}
Q[9900005]={n={en="Null Slots"},lv=4,min=3,cls={},race={},sk={171,nil},maps={},s={},e={},prev={},next={},conc={},excl={},ri={{159,nil,true},{118,3,false}},xp=1,cu=2,t=0}
end)(QMG_Quests);
(function(E)
E["n9901001"]={n="Fixture \"Quoter\" NPC",sp={{m=1429,x=45.3,y=60.1},{m=1453,x=12,y=80}},zh="測試NPC"}
E["o9901001"]={n="Fixture Object",sp={{m=1453,x=30,y=31.5}}}
end)(QMG_Entities);
(function(B)
B[1429]={9900001}
B[1453]={9900001,9900002}
end)(QMG_ByMap);
