# Changelog

每個版本一段，標題是 `## <版本>`；段內小標用 `###`。發版時 GitHub Release 與 CurseForge 的更新說明取自對應的段落。

## 0.2.0

### 節慶任務

- 節慶任務（季節性、新年慶典、仲夏）在名稱後標示「節慶」，暗月馬戲團的任務標示「暗月」；任務也有類型時兩個都標，類型在前，例如「(地下城) (節慶)」。清單、搜尋結果與明細標題都會顯示
- 新增勾選「顯示節慶任務」，預設不勾：沒勾時，還沒接的節慶任務不列在清單、不算進分頁數字、也搜尋不到（跟「顯示低等任務」一樣）。已在任務日誌裡或已完成的節慶任務照常列出。設定存在角色存檔
- 地圖標記不受篩選影響：從清單或明細連結打開的任務，一律在地圖上標出起點
- 暗月馬戲團的任務只標示，不受「顯示節慶任務」影響（其他篩選照常適用）
- 篩選勾選框改成兩欄平分面板寬，標籤過長時截斷，不會壓到旁邊的勾選框

### 任務日誌連動

- 在遊戲的任務日誌點一個任務，面板會切到那個任務：開啟明細、在地圖上標出起點，跟在清單點那一列一樣。任務不在插件資料裡就不動作；地圖沒開時先記下，打開地圖再切換。永遠開啟，沒有設定

### 修正

- 任務明細的獎勵物品有時只剩一格品質色、看不到圖示，已修正
- 任務明細的獎勵物品支援 Shift＋左鍵把物品連結貼進聊天、Ctrl＋左鍵試穿，跟背包物品一樣
- 地圖起點標記加深色底，在亮色地圖上也看得清楚
- 起點標記改畫在遊戲自己的地圖標記與覆蓋層之上（有些任務，例如知識試煉，點了起點看不到標記）
- 新增 `/qmg pins`：印出目前標記的任務、地圖與座標，回報「點了沒有標記」時使用

---

### Holiday quests

- Holiday quests (seasonal, Lunar Festival, Midsummer) get a "Holiday" tag after the name, and Darkmoon Faire quests get a "Darkmoon" tag. When a quest also has a type tag, both are shown with the type first, for example "(Dungeon) (Holiday)". The tags appear in the list, in search results and in the detail title.
- New checkbox "Show holiday quests", off by default. While it is off, holiday quests you have not accepted are left out of the list, the tab counts and search results, the same way "Show low-level quests" works. Holiday quests in your quest log or already completed are still listed. The setting is saved per character.
- The map marker is not affected by the filter: a quest opened from the list or from a link in the detail view always gets its start marked.
- Darkmoon Faire quests are only tagged and are not affected by "Show holiday quests" (the other filters still apply).
- The filter checkboxes now split the panel width into two equal columns, and long labels are cut short instead of running into the next checkbox.

### Quest log link

- Clicking a quest in the game's quest log switches the panel to that quest: the detail opens and its start is marked on the map, just like clicking the row in the list. Quests that are not in the addon's data are ignored; if the map is closed, the selection is kept and applied when the map opens. Always on, no setting.

### Fixes

- Reward items in the quest detail sometimes showed only a block of quality colour instead of the icon; fixed.
- Reward items in the quest detail now support Shift+left-click to put the item link into chat and Ctrl+left-click to try it on, the same as bag items.
- The start marker on the map now has a dark backing, so it stays readable on bright map areas.
- The start marker is now drawn above the game's own map markers and overlays (on some quests, such as the Trial of Knowledge chain, the marker was not visible).
- New `/qmg pins`: prints the marked quest, the map and the marker coordinates, for reporting a missing marker.

## 0.1.0-beta1

首次公開的測試版。永恆（1.60.1）客戶端用；資料為離線資料，實際以遊戲為準。

### 功能

- 世界地圖旁的面板，列出目前區域地圖上的任務；分頁：未接、日誌中、已完成、全部，標題顯示「可接 N／共 M」
- 每列有狀態圖示（可接、進行中、已完成）、任務等級與難度顏色、起點 NPC 與座標；清單依任務等級由低到高排序，任務名稱後標示類型（地下城、團隊、精英、PvP 等）
- 篩選：排除其他職業、其他專業、另一陣營（也會排除另一陣營種族限定的任務）；可選擇顯示已完成。前置任務未完成或同組任務已完成的任務會淡化
- 搜尋框：搜任務中文名、英文名與起點 NPC 名稱，範圍是全部任務，最多顯示 200 筆
- 點任務列：地圖上標出起點，並開啟任務明細（仿遊戲任務視窗：描述、獎勵物品、金錢、經驗值、前置與後續任務、限制）；獎勵物品滑鼠指向可看物品提示
- 起點若在別張地圖，點起點會先切換地圖再標出起點
- 在繁體中文客戶端學習 NPC 名稱，只存在本機存檔（詳見 README 的「隱私」）
- 指令：`/qmg probe` 檢查 API 是否存在、`/qmg stats` 顯示資料筆數與記憶體用量

### 可讀性

- 配色加深，文字在面板與明細上更清楚
- 清單上方的分頁改為按鈕
- 滑鼠移到任務列時整列高亮
- 起點整行可以點，前面有遊戲的黃色「!」；地圖標記與清單的可接任務也改用同一個黃色「!」
- 座標格式改為「NPC · 地圖名(x, y)」
- 面板加寬到 360，起點顯示完整

---

First public beta. For the Forever (1.60.1) client; the data is offline and the game is always the final authority.

### Features

- A panel beside the world map listing the quests on the current zone map. Tabs: open, in log, done, all; the header shows "Available N / M".
- Each row shows a status icon (available, in progress, completed), quest level with difficulty colour, the starting NPC and coordinates. The list is sorted by level, lowest first, and a quest-type tag (Dungeon, Raid, Elite, PvP, ...) follows the name.
- Filters: hide other classes, other professions and the other faction (this also hides quests limited to the other faction's races); completed quests can be shown. Quests whose prerequisite is unfinished, or whose group was already completed, are dimmed.
- Search box: matches quest names (zhTW and English) and starting NPC names across all quests, up to 200 results.
- Selecting a row marks the starting point on the map and opens the quest detail, laid out like the game's quest window: description, reward items, money, experience, prerequisites and follow-ups, restrictions. Reward items show the item tooltip on hover.
- Selecting a start on another map switches to that map first, then marks it.
- On Traditional Chinese clients the addon learns NPC names; they stay in the local save file only (see Privacy in the README).
- Commands: `/qmg probe` checks which APIs exist, `/qmg stats` prints the data size and memory use.

### Readability

- Darker colours so text is clearer on the panel and the detail view.
- The tabs above the list are now buttons.
- Hovering a quest row highlights the whole row.
- The start line is fully clickable and starts with the game's yellow "!"; the map marker and available quests in the list use the same yellow "!".
- Coordinates are written as "NPC · map(x, y)".
- The panel is wider (360) and the start line is shown in full.
