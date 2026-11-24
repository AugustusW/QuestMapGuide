# Changelog

每個版本一段，標題是 `## <版本>`；段內小標用 `###`。發版時 GitHub Release 與 CurseForge 的更新說明取自對應的段落。

## 0.1.0-beta1

首次公開的測試版。永恆（1.60.1）客戶端用；資料為離線資料，實際以遊戲為準。

### 功能

- 世界地圖旁的面板，列出目前區域地圖上的任務；分頁：未接、日誌中、已完成、全部，標題顯示「可接 N／共 M」
- 每列有狀態圖示（可接、進行中、已完成）、任務等級與難度顏色、起點 NPC 與座標；清單依任務等級由低到高排序，任務名稱後標示類型（地下城、團隊、精英、PvP 等）
- 篩選：排除其他職業、其他專業、另一陣營或種族；可選擇顯示已完成。前置任務未完成或同組任務已完成的任務會淡化
- 搜尋框：搜任務中文名、英文名與起點 NPC 名稱，範圍是全部任務，最多顯示 200 筆
- 點任務列：地圖上標出起點，並開啟任務明細（仿遊戲任務視窗：描述、獎勵物品、金錢、經驗值、前置與後續任務、限制）；獎勵物品滑鼠指向可看物品提示
- 起點若在別張地圖，點起點會先切換地圖再標出起點
- 在繁體中文客戶端學習 NPC 名稱，只存在本機存檔（詳見 README 的「隱私」）
- 指令：`/qmg probe` 檢查 API 是否存在、`/qmg stats` 顯示資料筆數與記憶體用量

### 可讀性

- 配色加深，文字在面板與明細上更清楚
- 清單上方的分頁改為按鈕
- 滑鼠移到任務列時整列高亮
- 起點整行可以點，前面有地圖圖釘圖示
- 座標格式改為「NPC · 地圖名(x, y)」
- 面板加寬到 360，起點顯示完整

---

First public beta. For the Forever (1.60.1) client; the data is offline and the game is always the final authority.

### Features

- A panel beside the world map listing the quests on the current zone map. Tabs: open, in log, done, all; the header shows "Available N / M".
- Each row shows a status icon (available, in progress, completed), quest level with difficulty colour, the starting NPC and coordinates. The list is sorted by level, lowest first, and a quest-type tag (Dungeon, Raid, Elite, PvP, ...) follows the name.
- Filters: hide other classes, other professions, the other faction or race; completed quests can be shown. Quests whose prerequisite is unfinished, or whose group was already completed, are dimmed.
- Search box: matches quest names (zhTW and English) and starting NPC names across all quests, up to 200 results.
- Selecting a row marks the starting point on the map and opens the quest detail, laid out like the game's quest window: description, reward items, money, experience, prerequisites and follow-ups, restrictions. Reward items show the item tooltip on hover.
- Selecting a start on another map switches to that map first, then marks it.
- On Traditional Chinese clients the addon learns NPC names; they stay in the local save file only (see Privacy in the README).
- Commands: `/qmg probe` checks which APIs exist, `/qmg stats` prints the data size and memory use.

### Readability

- Darker colours so text is clearer on the panel and the detail view.
- The tabs above the list are now buttons.
- Hovering a quest row highlights the whole row.
- The start line is fully clickable and has a map pin icon in front.
- Coordinates are written as "NPC · map(x, y)".
- The panel is wider (360) and the start line is shown in full.
