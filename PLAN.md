# omoba Godot 前端計畫

日期：2026-11-05
來源：`D:\omoba`（主 repo `1b835740`、`omb` `a70e443`、protocol：presentation 14／selective 18／bridge CABI 36）
目標位置：`C:\nobu\omoba-gd\`（新 repo，`D:\omoba` 全程唯讀）

## 0. 目前進度（2026-11-06）

| 項目 | 狀態 | 證據或說明 |
|---|---|---|
| S0 環境 | 通過 | Godot 4.7.2、ffmpeg 8.1；媒體只走 Grok CLI（forge 記錄額度呼叫，0 美元） |
| S1 bridge | 通過 | `om_godot`（gdext 0.5.5，`api-4-7`）載入 `om_bridge`，ABI 45；另提供 `take_casts()`（技能施放事件） |
| S2 美術 | 英雄通過 | 10 位英雄各有 idle／move／attack／cast／death，另有正面、背面行走（往畫面上下方移動時切換），逐段看過審核圖才接受；`tests/hero_lineup.gd` 全員同框。HUD 有頭像、技能圖示（31 張原作＋13 張 Grok 補畫）、頭頂名字。小兵 12 個動作只成功 6 個，其餘用程序動畫 |
| 呈現 | 進行中 | 2.5D 鏡頭、戰爭迷霧、HUD、小地圖、施法／死亡動作、10 位英雄八方向走路（正、斜前、側、斜後、背，左右鏡像）、mipmap＋柔邊、地圖外延伸地面、鏡頭不出界、動作結束交叉淡出、受擊閃紅、腳下接地陰影、近距離名牌錯開、浮動傷害數字、投射物暫用發光光點、英雄攻擊命中特效（槍火彈道／箭影／法術光球／斬擊光，程式繪製）；技能特效、投射物專屬美術、商店未做 |
| S3 地圖 | 部分通過 | `three_lane_training` 對齊良好；`nobu`（305 阻擋區、1564 棵樹）未測 |
| P1 後端基準 | 通過 | 正式配方 `moba_role_match`（10 Bot、`three_lane_training`）無畫面打完一局：tick 78471（約 21.8 分鐘），team 2 勝，重播全部 tick，observer 0 mismatch。`moba-headless` 不帶配方的預設配置仍會目標停滯（tick 91482 起），未查原因，也未與上游比對 |
| P3 灰盒 | 大致完成 | 真實 10 人局 150 秒維持 60 FPS；尚未看到打完一局 |
| P4 操作 | 進行中 | 移動、技能經權威確認；升級未驗證（無技能點）；攻擊目標、攻擊移動、回城已接線但未驗證 |

計畫修正：
- `erps` 不能排除（`omb` 依賴 `erps-proto`）。
- forge 的 sprite set 不經過 `export_engine.py`，改用自己的 `art-pipeline/import_sprite_set.py`；forge 的錨點落在後腳，匯入時修正到兩腳中間。
- 英雄美術流程：`briefs/make_heroes.py` → `master_still.py`（每位 3 張挑 1）→ `run_hero_sets.sh`（`hero_motion.py` 改寫武器專屬的攻擊／施法動作、攻擊與施法縮小留頭頂空間、只打包 PNG）→ 人工審核 → `import_heroes.sh`。Grok 影片常見失敗與對策：行走不循環 → `loop_window.py` 找循環區段；武器舉過頭出畫面 → 縮小或改低舉；箭／閃光脫離身體 → `drop_detached.py`；去背殘色 → 匯入時重畫。forge 的 `sprite_set.py` 有兩處標了 `omoba-gd` 的小改。
- `omb` 的埠在腳本 DLL 載入完成前就開放，太早加入會被 `SCRIPT_MODULES_HASH_MISMATCH` 拒絕。這在上游也存在，`run_moba_role_gd.lua` 已等待載入完成來避開，後端未改。

## 1. 目標與範圍

複製 omoba 的 Rust 權威後端，用 Godot 4 做一個新的 2D 前端，美術由 agent-sprite-forge 產生。第一個完整目標是：**本機 1 位真人＋9 個 Bot，用 `moba_single_player` 配方打完一場正式 MOBA 並看到結算。**（內容資料有 `three_lane_training` 與 `nobu` 兩張地圖，配方實際用哪張在 P1 確認。）

不在這次範圍：TD 模式、真雙機 LAN、觀戰／回放、改動玩法規則與平衡、維護 `omfx`。

## 2. 現況盤點（已查證）

| 項目 | 查到的事實 | 對計畫的影響 |
|---|---|---|
| 程序架構 | `omobab` ←KCP→ `omoba-client-runtime` ←loopback TCP→ renderer | Godot 只需取代最右邊的 renderer，後端不用改 |
| IPC 格式 | 4-byte BE 長度＋protobuf `RendererIpcEnvelope`，magic `0x4f4d5254`，版本 14，單幀上限 8 MiB；runtime 綁 port，renderer 連入後先送 `RendererReady`（player／team 不符會被拒） | 版本以 `omoba-core/src/renderer_protocol.rs` 為準；`docs/protocol/renderer-presentation-ipc.md` 寫的版本 1 已過期 |
| 實體資料 | `PresentationComponent.safe_payload` 是自訂二進位，schema 約 25 種以上（`0x464f4701`～`0x464f4730`） | 用 GDScript 重寫解碼器成本高又容易出錯 |
| Unreal bridge | `omfue/bridge`（crate `om_bridge`）是純 Rust，沒有 UE 依賴，crate-type 含 `rlib`。對外 23 個 C 函式：`om_runtime_*`、`om_acquire_latest_frame`、`om_submit_input`、`om_acquire_runtime_catalog`、`om_poll_session_status` 等 | **可直接重用**，這是本計畫最省工的一點 |
| 後端耦合 | `omb`、`omoba-core`、`omoba-client-runtime`、`omoba-template-ids`、`omoba-content-model`、`omoba-sim`、`script-abi`、`base_content` 的 Cargo／build.rs 都沒有引用 `omfue` | 後端可乾淨複製 |
| 啟動流程 | `scripts/moba_role_launch.lua`（55 KB）與 UE 綁得很深（約 34 處） | 需要新增 Godot 分支，核心 server／runtime 流程可重用 |
| 啟動防呆 | 比對 server、runtime、bridge 內嵌的 `OM_CONTENT_CATALOG_DATA_HASH`；有機器鎖 `live_match` | 新 bridge 要納入比對 |
| UE 前端規模 | `OmRuntime` 453 個 C++ 檔、14 MB | 不逐一移植，按玩家可見功能分階段重做 |
| 技能呈現 | 1095 個 cue：effect 391、aura 285、sound 271、projectile 78、impact 32、gesture 27、其他 11；其中 178 個本來就用通用佔位 | 特效必須資料驅動＋通用 fallback，不可能逐一手做 |
| 動畫槽位 | `idle`、`idle_2`、`idle_3`、`move`、`attack`、`critical`、`cast`、`hit`、`death`、`recall`、`respawn`、`emote`，另有英雄專屬 state slot（如 `sniper_mode`） | 成為 sprite 目錄的標準欄位 |
| 複製注意 | `omb/log` 有一個 3.2 GB 的 log；主 repo 有大量未追蹤檔；`omb` 工作區有未提交內容；其他 session 正在使用這個 repo | 只匯出**已提交**內容，不用檔案總管直接複製 |
| 本機工具 | 有 cargo、Python 3.12、Grok CLI；**沒有 Godot、ffmpeg、Codex CLI**；環境變數裡沒看到 OpenAI／Gemini／xAI／fal／ARK 金鑰（forge 自己的 `config.json` 尚未檢查） | P0 要先補齊，影片路線目前走不通 |

### agent-sprite-forge（v0.4，MIT）

- 流程：核准一張 master still → 每個動作生成一段圖生影片 → 去背、對位、循環 → 打包成 `animation.json`（含事件與錨點）＋ PNG atlas。
- 匯出：Godot `SpriteFrames .tres`＋`AnimatedSprite2D .tscn`、AnimatedSprite3D、TileMapLayer（4.3+）。
- 影片路線需要 `XAI_API_KEY`、`ARK_API_KEY`、`FAL_KEY` 其一，或 Grok CLI ACP 模式（無法固定結尾幀），或自備影片；另需 ffmpeg 5.1+。
- **三個會影響計畫的限制：**
  1. Godot 匯出只做過解析層驗證，**作者聲明沒有在 Godot 編輯器開過**，部分屬性名是憑記憶寫的。
  2. **多方向要分別生成。** `sprite_set.py plan --views side,front,back --view-master` 支援多視角（原本寫「沒有多方向系統」是看漏了），每個視角一張 master、每個動作一段影片。
  3. 預設沒有花費上限；OpenAI 圖片模型沒有價格資料，`--budget-usd` 會拒絕它。

## 3. 架構決策

### D1：Godot 透過 Rust GDExtension 包 `om_bridge`，不重寫協定（建議）

```text
omobab（權威 ECS、base_content.dll、Bot）
   │ KCP selective lockstep
omoba-client-runtime（隊伍 filtered replica）
   │ loopback TCP / RendererIpcEnvelope
om_bridge（既有 Rust：解碼、驗證、catalog、輸入關聯）
   │ Rust 直接呼叫
om_godot（新 GDExtension，gdext）
   │ Godot signals／Packed*Array
GDScript 呈現層（單位、地圖、霧、特效、HUD）
```

| 方案 | 優點 | 缺點 | 結論 |
|---|---|---|---|
| **GDExtension＋`om_bridge`** | 解碼、fail-closed、catalog 直接沿用；協定升版只改一處 | 要處理 gdext 與 Rust 1.95 的相容性 | **採用** |
| 純 GDScript／C# protobuf | 不用編 Rust | 要重寫 25+ 種 schema 與所有驗證規則 | 不採用 |
| `omb-ws-bridge` | 已存在 | 它連的是 KCP 權威端，繞過 filtered replica，不符合正式架構 | 不採用 |

### D2：2.5D（3D 場景＋billboard 角色）（2026-11-05 依你的要求由純 2D 改為此方案）

場景用 `Node3D`：地面是生成的俯視貼圖，牆與建築是真 3D 幾何，透視相機傾斜俯視，有即時光影與景深；角色、特效用 `AnimatedSprite3D` billboard。深度由引擎處理，不需要 y-sort；滑鼠選點改為射線對地面。後端座標是 Q10（`raw / 1024`），世界單位以 `x / 100`、`-y / 100` 對到 Godot 的 x、z，由單一 `WorldXform` 換算，全專案不得自行換算。原型：`omgd/game/tests/hd25_preview.gd`。

### D3：方向分階段

| 階段 | 做法 | 每位英雄的影片數（6 個動作） |
|---|---|---|
| M1 | 只做側面，左右翻轉 | 6 |
| M2（英雄） | 正／背／側 3 個 master，左右翻轉 | 最多 18（`hit`、`death` 可共用，約 14） |
| 小兵、野怪 | 維持側面翻轉 | 依兵種 |

朝向來自 `0x464f4707` facing component。若 3 方向的一致性做不好，備案是把現有 3D 英雄模型算圖成多方向序列，再交給 forge 的 finish 流程。

### D4：複製方式是「快照＋上游紀錄」

不用 submodule，全部進同一個新 repo，來源 commit 記在 `UPSTREAM.md`。代價是後端會與 `D:\omoba` 分岔，所以另外提供 `scripts/upstream_diff.lua` 列出上游變更，由人決定是否合併。

### D5：美術與玩法資料分離

Godot 呈現資料放 `omgd/presentation/`，**不進** `scripts/lua_data`，換圖不會改變 content hash，也就不必重編後端。

### 不可破壞的規則（沿用自 omoba）

- Renderer 不跑模擬、不載入 script DLL、不連 KCP，只連 loopback。
- 單位身分是 `(render_id, disclosure_epoch)`，不是 entity ID；`view_epoch` 變動時清空視圖。
- Remembered ghost 只能顯示，不可選取；不可自行推算隱藏資訊。
- 欄位缺席代表「不可用」，不可當成 0 或完整視野。
- 快照 latest-wins；critical result 依序處理；未知版本或過長 frame 一律 fail closed。
- 施法預覽不代表權威接受，HUD 數值以後端為準。

## 4. 目錄結構

```text
C:\nobu\omoba-gd\
├─ UPSTREAM.md、AGENTS.md、README.md、rust-toolchain.toml（1.95.0）
├─ run_gd.bat                     薄 wrapper，只呼叫 Lua
├─ omb/ omoba-core/ omoba-sim/ omoba-template-ids/ omoba-content-model/
├─ omoba-client-runtime/ omoba-netem-proxy/ specs/ log4rs/ proto/ tools/ scripts/
├─ docs/{protocol,selective-lockstep,character_pipeline}/
├─ omgd/                          與 omfue 同深度，bridge 的 ../../ 相對路徑不用改
│  ├─ bridge/                     複製自 omfue/bridge
│  ├─ codegen/                    複製自 omfue/codegen，移除 UE 輸出
│  ├─ om_godot/                   新 GDExtension crate
│  ├─ game/                       Godot 專案
│  │  ├─ project.godot、om_godot.gdextension
│  │  ├─ core/   world/   units/   fx/   hud/   screens/   tests/
│  │  └─ art/                     匯入後的 sprite、地圖
│  └─ presentation/               sprites.json、cues.json、maps.json
└─ art-pipeline/
   ├─ forge/                      固定版本的 agent-sprite-forge
   ├─ briefs/                     每個角色的 prompt 與風格設定
   ├─ work/                       中間產物（不進版控）
   └─ .forge/ledger.jsonl         花費紀錄
```

**先排除、build 報缺才補：** `omfx`、`eui`、`map_editor`、`mqtt_log_viewer`、`erps`、`omfue` 的其餘部分、`ref`、`third_party`、`.ai-collab`、`handoff.md`、所有 `target/`、log、exe。

## 5. 階段計畫

工時是一人搭配 agent 的粗估，P0 結束後會修正。

### P0：可行性驗證（3–4 天）

這四項任一失敗都會改變後面的設計，所以先做，而且全部是拋棄式程式。

| 驗證 | 做法 | 通過條件 | 失敗時 |
|---|---|---|---|
| S0 環境 | 裝 Godot 4.7.2、ffmpeg；跑 forge 的 `forge_doctor.py`；設定一條影片路線 | doctor 回報可用路線 | 改用自備影片或 Grok 圖片序列 |
| S1 bridge | gdext 空專案載入 `om_bridge`，對 `omoba-renderer-fixture` 收幀 | Godot 印出實體數與 tick | 改為 C++ GDExtension 連 `om_bridge.dll` 的 C ABI |
| S2 美術 | 1 位英雄產出 idle／move／attack，匯入 Godot 播放 | 腳底不飄、沒有閃爍、攻擊事件時間可讀 | 寫自己的 `animation.json` 匯入器 |
| S3 地圖 | 把目標地圖的 `MobaMapConst` 匯出成 layout 圖，交給 `generate2dmap` | 生成圖與牆體、路線的誤差在 1 個單位碰撞半徑內 | 改用 TileMap 程序繪製＋生成素材貼圖 |

同時完成：風格比較（HD 與 pixel 各做一隻）、記錄單位影片成本，算出全英雄預算。

### P1：後端複製與驗證（1–2 天）

1. 用 `git archive` 匯出主 repo 與 `omb`、`specs`、`log4rs` 指定 commit，寫 `UPSTREAM.md`。
2. 清掉硬編碼路徑（如 `run_2player_ue.bat` 內的 `D:\code\omoba`）。
3. `git init`，首次提交。

**完成條件：** `omb`、`omoba-core`、`omoba-client-runtime`、`scripts`、`omoba-template-ids` 的測試數量與失敗數跟來源一致；`run_moba_headless.lua` 能自然打完一場。

### P2：`om_godot` 與 bridge 重用（4–5 天）

1. 複製 `bridge`、`codegen` 到 `omgd/`，移除 UE 專用生成物但保留 catalog。
2. 以 cbindgen header 為準，整理 frame 結構與 Godot 類型的對照表。
3. 實作 `OmSession`（`RefCounted`）：`start(config)`、`stop()`、`poll_frame()`、`submit_*()`、`get_catalog()`、`poll_status()`、`last_error()`。
4. 大量資料用 `PackedFloat32Array`／`PackedInt64Array`，避免每個實體一個 Dictionary。
5. 測試：Rust 層跑既有 `tests/runtime_driver_smoke.rs`；Godot 層以 headless 連 fixture。

**完成條件：** fixture 情境全過；版本不符、斷線、wrong-team 都會明確報錯而不是靜默運作。

### P3：灰盒可看（3–4 天）

1. `run_moba_role_gd.lua`：重用 server／runtime 啟動、機器鎖、content hash 比對，把 UE 啟動換成 Godot（`--om-player`、`--om-team`、`--om-presentation` 等參數）。
2. `UnitLayer`：以色塊、血條、名牌顯示所有實體，依 entity kind 分色；處理 `removed_render_ids` 與 Hide／Forget／ResetView。
3. 快照間內插；追蹤延遲、幀時間的 debug overlay。
4. 地圖 debug 層：畫出 terrain、brushes、lanes、塔、基地。

**完成條件：** `run_gd.bat` 一鍵開局，能看 10 位 Bot 自動對戰直到結算，畫面與 headless 結果一致。

### P4：操作（4–5 天）——**第一個可玩里程碑**

- 相機：跟隨、邊緣捲動、鎖定、小地圖點擊，範圍用 `world_bounds`。
- 指令：移動、攻擊、攻擊移動、停止、原地、回城、排隊（對應 `RendererInput` 的 intent；預設按鍵比照 omfue）。
- 技能：omfue 現有的三種施法模式與改鍵；單位、圓形、走廊、陣形、扇形預覽；升級技能。
- 選取：點選優先序、不可選 ghost、自身與目標資訊卡。
- 從第一天起讓 autopilot 走真實輸入管線，供後面驗收。

**完成條件：** 用色塊可以手動操作一位英雄，放完所有技能、打塔、死亡重生、贏得一局；回放輸入紀錄 0 mismatch。

### P5：角色美術與動畫（5–7 天做流程，內容量另計）

1. 美術規範：鏡頭角度、光向、調色、角色高度、腳底錨點。第一隻核准後當所有角色的 `--style-ref`。
2. `art-pipeline/build_character.py`：brief → master → sprite set → 人工 review → 匯出 → 更新 `sprites.json`；可續跑，強制帶 `--budget-usd`／`--max-calls`。
3. `sprites.json`：`content_id → 動畫槽位（幀、fps、循環、impact 事件）、錨點、縮放、方向數`。
4. `UnitView` 狀態機：依 `0x464f4712`（attack）、`0x464f4716`（channel）、facing、移動速度選動畫；攻擊動畫依 `attack_interval` 調速，impact 對齊事件。
5. 缺圖走共用人形 fallback，並在 log 記一次。
6. 每位英雄一張 atlas，上限 4096，在載入畫面用背景執行緒載入。

**內容順序：** 共用人形 → 小兵 4 種（近戰、遠程、砲車、超級兵）→ 塔／兵營／基地 → 第一位英雄 → 其餘陣容。

**完成條件：** 10 英雄＋100 小兵維持 60 FPS（固定硬體）；連續檢視 10 分鐘沒有腳滑、朝向錯誤、動作卡死。

### P6：地圖（4–6 天）

1. Lua 工具輸出 layout 圖（路線、牆、河、草、基地）作為生成參考。
2. 底圖分區塊生成，避免單張過大；樹、草、建築做成 prop pack，`fallen_trees` 控制樹倒下。（待確認：proto 註解說索引指向 `MobaMapConst::trees`，但我讀到的 struct 欄位沒有 `trees`，P2 要查清楚樹的實際資料來源。）
3. 草叢半透明、遮擋與 y-sort。
4. CI 檢查：疊合 debug 層截圖，避免視覺與碰撞不一致。

**完成條件：** 美術圖上看得到的牆與實際碰撞一致；走過全部路線與野區沒有穿牆或走不到的地方。

### P7：霧與視野（2–3 天）

`fog_grid`（未見／探索／可見，最多 4096 格）轉成低解析貼圖，用 shader 平滑＋時間淡入；`vision_circles` 與 occluder 做邊緣細節；ghost 用灰階半透明。`fog_grid` 缺席時顯示「不可用」，不得視為全開。

**完成條件：** 雙隊 `run_2player` 對照，不同隊看到的單位集合符合權威結果，沒有洩漏。

### P8：技能特效與音效（5–8 天做流程，內容量另計）

1. `cues.json`：`cue_id → fx_id、音效、掛點、縮放、色調`。
2. 通用特效庫，按 cue kind 做，用色調表現英雄屬性；用 forge sheet 模式產生。
3. 優先度：projectile → impact → area／link → aura → effect。未對應的 cue 走 `generic`，不報錯。
4. `ground_zones`、`links`、投射物（render kind 5）專用節點，物件池化。
5. 傷害／MISS／CRIT 文字、護盾、buff 視覺。
6. 音效先用通用組，音量分軌與字幕之後補。

**完成條件：** 1095 個 cue 全部可解析（專屬或 fallback），不會有無反應的技能；提供覆蓋率報表。

### P9：HUD（6–8 天）

| 優先 | 內容 |
|---|---|
| 必要 | 血魔條、技能欄（冷卻、充能、法力不足、升級）、金錢、道具欄、召喚師、重生／回城倒數、結算 |
| 必要 | 商店：道具目錄（README 記載 19 項，以編譯後 catalog 為準）、合成、買／賣／撤銷，含收據與 pending 狀態 |
| 高 | 計分板、小地圖、隊友卡、目標資訊卡（含射程與距離）、公告 |
| 中 | 聊天、ping、改鍵、音量、DPI 縮放 |

沿用既有文字與圖示資料（`nobu-icons.md`、HUD 圖示來源），只需轉 PNG。主題統一用 Godot Theme。

**完成條件：** 所有欄位直接來自 `MobaHudPresentation` 等權威資料；「缺席」與「0」顯示不同。

### P10：完整流程（3–4 天）

選角（透過 `moba-config` 的既有 plan／lock 流程）→ 載入畫面 → 對局 → 結算 → 再來一局；斷線重連（`RECONNECTING`）、伺服器終止、版本不符都有明確畫面。雙人本機（`moba_two_player`）。

### P11：內容擴充、打包與驗收（5 天＋內容量）

1. 依預算產出其餘英雄。
2. 打包：Godot export＋`omobab`、`omoba-client-runtime`、`base_content.dll`、`om_godot.dll`，從乾淨目錄可以啟動。
3. 重用驗收：`check_hero_live_acceptance.lua` 的逐招檢查（改接 Godot autopilot）、netem 80±20 ms＋1% 掉包、10 秒斷線恢復、30 秒以上重新加入。
4. 長時間穩定性與記憶體量測。

### 里程碑

| 里程碑 | 階段 | 累計粗估 | 看得到的成果 |
|---|---|---|---|
| A 可行性 | P0 | 第 1 週 | 一隻 sprite 英雄跑在 Godot 裡、收得到 fixture 幀 |
| B 灰盒可玩 | P1–P4 | 第 3–4 週 | 色塊版可以完整打完一局 |
| C 像遊戲 | P5–P7 | 第 6–7 週 | 有角色、地圖、霧 |
| D 完整對局 | P8–P10 | 第 9–10 週 | 特效、HUD、選角到結算 |
| E 發佈 | P11 | 第 11–12 週以上 | 打包版＋全陣容（視美術預算） |

## 6. 測試策略

| 層級 | 工具 | 檢查內容 |
|---|---|---|
| 協定 | `omoba-renderer-fixture`＋Godot headless | 版本、斷線、順序、lifecycle |
| 同步 | 既有 replica parity、輸入紀錄 | 0 mismatch |
| 視覺 | Godot 截圖＋debug 層疊合 | 地圖對齊、動畫槽位缺漏 |
| 內容 | Lua／Python 覆蓋率報表 | sprite 與 cue 對應率、缺圖清單 |
| 實機 | autopilot、netem proxy | 完整對局、延遲、掉包 |
| 美術 | forge `validate_animation.py`＋人工 review | forge 明講數字抓不到身分與朝向問題，一定要人看 |

沿用 omoba 的規則：驗收必須留下可重現證據，單機合成資料不能當成真連線結果。

## 7. 風險

| 風險 | 機率 | 影響 | 對策 |
|---|---|---|---|
| Forge 的 Godot 匯出不能用（作者未驗證） | 高 | 中 | P0 S2 驗證；自己寫 `animation.json` 匯入器當備案 |
| 多方向角色不一致 | 高 | 高 | 先做側面翻轉；英雄 3 方向另做 pilot；備案用 3D 算圖 |
| 美術費用失控（預設無上限） | 中 | 高 | 強制帶預算參數；先算單位成本；分批核准 |
| 生成角色不一致 | 中 | 中 | `--style-ref`、共用 scale profile、人工核准 |
| AI 地圖與碰撞對不上 | 中 | 高 | layout 引導＋CI 疊圖；備案用 TileMap |
| `om_bridge` 含 UE 假設 | 中 | 中 | P0 S1 先驗證；Godot 只用需要的函式 |
| gdext 與 Godot 4.7／Rust 1.95 不相容 | 低～中 | 中 | S1 驗證；備案 C++ GDExtension 走 C ABI |
| 上游後端持續改動造成分岔 | 高 | 中 | 記錄來源 commit；只在里程碑間評估合併 |
| 素材版權 | 中 | 高 | `history_nobu` 的 cue 對應到原作資產，**不把這些素材或其參考圖**放進生成或成品；forge 的 MIT 不涵蓋生成圖，需依各供應商條款 |
| 效能（大量 sprite、特效） | 低～中 | 中 | 小兵必要時用 MultiMesh；物件池；P5 就量測 |

## 8. 需要你決定的事

1. **美術風格：** 預設 HD 手繪感（1 位英雄對照 pixel 後定案）。
2. **影片生成路線與預算：** 目前沒有可用的金鑰，要選 xAI、BytePlus Seedance 或 fal.ai，並定一個總上限。Grok CLI 雖然有裝，但無法固定結尾幀，循環動作品質可能較差。
3. **首發陣容：** 預設先做 README 記載已通過實機逐招驗收的 8 位（H01–H06、玉子、村上義清），全陣容視預算。一場 10 人局缺的位置先用共用人形 fallback。
4. **後端同步政策：** 預設快照後只在里程碑間評估合併，也可以改成持續追上游。

## 9. 第一步（P0 清單）

1. 檢查並補齊 Godot 4.7.2、ffmpeg。
2. 把 forge 裝到 `art-pipeline/forge/`，跑 `forge_doctor.py`。
3. 匯出後端快照到 `C:\nobu\omoba-gd\`，跑 headless 對局確認基準。
4. 建 `om_godot` 空殼，連上 `omoba-renderer-fixture`。
5. 做第一位英雄的 pilot 與地圖 layout 驗證。
6. 回報 P0 結果：可行性、單位成本、修正後的時程。
