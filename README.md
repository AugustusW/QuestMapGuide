# QuestMapGuide（任務地圖指南）

World of Warcraft 永恆用的任務地圖插件：世界地圖旁的面板，列出地圖上的任務與起點。
A quest map companion for WoW Classic-era "Forever" clients: a panel beside the world map that lists the quests on the current map and their starting points.

開發中（0.1.0-beta1）。資料為離線資料，實際以遊戲為準。授權 GPL v3，見 LICENSE 與 NOTICE。
Work in progress (0.1.0-beta1). The data is offline; the game is always the final authority. Licensed GPL v3, see LICENSE and NOTICE.

## 安裝 Install

1. 把整個 `QuestMapGuide` 資料夾複製到遊戲的 `Interface/AddOns/`。
2. 全部關閉遊戲後重新啟動。新增插件需要完整重啟，`/reload` 不會載入新插件。
3. 角色選擇畫面左下角「插件」確認 QuestMapGuide 已勾選。

1. Copy the whole `QuestMapGuide` folder into the game's `Interface/AddOns/`.
2. Quit the game completely and start it again. A new addon needs a full restart; `/reload` does not pick it up.
3. On the character select screen, open "AddOns" and confirm QuestMapGuide is enabled.

## 功能 Features (0.0.3)

- 世界地圖旁的面板，列出目前區域地圖上的任務；分頁：未接、日誌中、已完成、全部，標題顯示「可接 N／共 M」。
- 每列有狀態圖示（可接、進行中、已完成）、任務等級與難度顏色、起點 NPC 與座標；每列只佔一行，過長的文字會截斷，滑鼠指向列可看全文。
- 清單依任務等級由低到高排序（沒有等級的排最後，同等級依名稱）；搜尋結果先排序，再取前 200 筆。
- 任務名稱後會標示類型（例如地下城、團隊、精英、PvP），資料中沒有對應類型的不標示。
- 篩選：排除其他職業、其他專業、另一陣營或種族（預設全勾）；可選擇顯示已完成。前置任務未完成或同組任務已完成的任務會淡化。
- 搜尋框：搜任務中文名、英文名與起點 NPC 名稱，範圍是全部任務（不限這張地圖），最多顯示 200 筆。搜尋時標題改顯示搜尋結果筆數。
- 點任務列：地圖上標出起點，並開啟任務明細。明細仿遊戲任務視窗的版面：任務描述（會代入角色名稱、種族、職業與性別用詞，內容過長時可捲動）、獎勵、經驗值、前置與後續任務、限制。
- 獎勵物品顯示成圖示按鈕（含品質顏色與數量），滑鼠指向會顯示物品提示；物品資料尚未載入時先顯示問號與「物品 #編號」，載入後自動更新。
- 金錢以金、銀、銅圖示顯示；數值為 0 的單位不顯示，全為 0 則整行不出現。
- 經驗值：任務在日誌中時，若遊戲提供查詢就顯示遊戲回報的數值，否則顯示資料中的數值；兩者都沒有就不顯示。
- 起點列顯示「NPC · 座標」並附地圖名稱；點起點若在別張地圖，會先切換地圖再標出起點，明細維持開啟。
- 學習繁中 NPC 名稱（只在 zhTW 客戶端，見下方「隱私」）。

- A panel beside the world map listing the quests on the current zone map. Tabs: open, in log, done, all; the header shows "Available N / M".
- Each row shows a status icon (available, in progress, completed), quest level with difficulty colour, the starting NPC and coordinates. Rows are one line high; long text is truncated and the row tooltip shows the full text.
- The list is sorted by quest level, lowest first (quests without a level last, ties by name). Search results are sorted first, then cut to the first 200.
- A quest-type tag follows the name (for example Dungeon, Raid, Elite, PvP); quests whose type is not in the data get no tag.
- Filters: hide other classes, other professions, the other faction or race (all on by default); completed quests can be shown. Quests whose prerequisite is unfinished, or whose group was already completed, are dimmed.
- Search box: matches quest names (zhTW and English) and starting NPC names across all quests, not only this map, up to 200 results. While a search is active the header shows the result count instead.
- Selecting a row marks the starting point on the map and opens the quest detail, laid out like the game's quest window: description (with player name, race, class and gender wording filled in; scrolls when long), rewards, experience, prerequisites and follow-ups, restrictions.
- Reward items are icon buttons (quality colour, count) with the item tooltip on hover; until item data has loaded a question-mark icon and "Item #id" are shown, then updated.
- Money is shown with gold, silver and copper icons; zero units are left out, and the line is omitted when all are zero.
- Experience: for a quest in the quest log, the value the game reports is shown when the game provides the lookup, otherwise the value from the data; nothing is shown when neither exists.
- The start line shows "NPC · coordinates" with the map name; selecting a start on another map switches to that map first, then marks it, and the detail stays open.
- Learns Traditional Chinese NPC names (zhTW clients only; see Privacy below).

## 指令 Commands

- `/qmg probe`：確認插件用到的 API、widget 方法與範本在這個客戶端是否存在（包含事件註冊失敗的名單），結果寫入存檔。
- `/qmg stats`：顯示內建資料的任務筆數、解析時間與記憶體用量。解析超過 150 ms 或記憶體超過 20 MB 會多一行提示。

- `/qmg probe`: checks which APIs, widget methods and templates the addon uses exist on this client (including any events that failed to register), and saves the result.
- `/qmg stats`: prints the quest count, parse time and memory use of the bundled data. A second line appears when parsing exceeds 150 ms or memory exceeds 20 MB.

## 隱私 Privacy

在繁體中文（zhTW）客戶端，滑鼠指向或選為目標的 NPC，插件會把該 NPC 的 ID 與遊戲內顯示的繁體中文名稱記進存檔（`QuestMapGuideDB.npcNames`：名稱、看到的次數、第一次與最近一次的時間）。只記資料裡有的 NPC，同一個 NPC 每 60 秒最多記一次；玩家、寵物與載具不記。其他語系的客戶端不記錄。這些名稱只存在本機的存檔，插件不會自行傳送；只有在玩家自己選擇上傳存檔、用來補充共用資料時才會被使用。記下的名稱會在 zhTW 客戶端優先顯示在面板、明細與地圖標記。

On Traditional Chinese (zhTW) clients, when the player points at or targets an NPC, the addon saves that NPC's ID and the Traditional Chinese name shown by the game into the save file (`QuestMapGuideDB.npcNames`: name, times seen, first and last time). Only NPCs that exist in the bundled data are recorded, at most once per 60 seconds per NPC; players, pets and vehicles are not recorded. Clients in other languages record nothing. The names stay in the local save file and the addon sends nothing on its own; they are used only when the player chooses to upload the save file to improve the shared data. Learned names are shown first on zhTW clients in the panel, the quest detail and the map markers.

## 存檔位置 SavedVariables

`/qmg probe` 的結果與學到的 NPC 名稱在 `/reload` 或登出後寫入：

`World of Warcraft/<版本資料夾>/WTF/Account/<帳號>/SavedVariables/QuestMapGuide.lua`

回報測試結果時，請把這個檔案一併提供。

The `/qmg probe` result and the learned NPC names are written after `/reload` or logout to the file above (`<version folder>` is the client folder, `<account>` is the account folder). Please include this file when reporting test results.

## 資料來源 Data

| 欄位 Field | 值 Value |
|---|---|
| sourceVersion | 13e933726f386399d9820138fbd1123e7cda86c8 |
| officialExportDate | 2026-11-24T16:45:29.253479+00:00 |
| wagoBuild | 1.60.1.71091 |
| exportedAt | 2026-11-24T16:45:31.550713+00:00 |
| quests | 6874 |
| entities | 1847 |

以上取自 `Data/Forever/Quests.lua` 的 `QMG_Meta`。資料來源與授權聲明見 NOTICE。
Values come from `QMG_Meta` in `Data/Forever/Quests.lua`. Data sources and licence notes are in NOTICE.

實際以遊戲為準。任務資料與遊戲內不一致時，以遊戲內為準。
The game is the final authority. When the data and the game disagree, trust the game.
