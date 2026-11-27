-- Route data for the sleeping bag helper (GF-008-A): Horde route of the
-- "Cozy Sleeping Bag" quest chain on WoW Forever.
--
-- GF-008-D (owner: 「請再多去蒐集資料做精簡的攻略…針對部落解法做」): rewritten
-- in our own words from several public guides cross-checked step by step
-- (GreenFang_Toolkit docs/research/GF-008-D_guide.md lists the URLs):
--   warcraft.wiki.gg quest pages (Forever + SoD values), method.gg (Forever),
--   kotaku.com (Forever), warcrafttavern.com (Forever), dotesports (SoD).
-- NOTHING here is field-tested yet: every step has verified = false and the UI
-- shows "待實地驗證". Quest IDs are intentionally not used until they are
-- confirmed on the Forever client.
--
-- One route per faction: ns.SleepingBagRoutes[<key>] = { faction = "Horde" |
-- "Alliance", ... }. SleepingBag.lua picks the route whose `faction` matches
-- the player; an Alliance route can be added here later without code changes.
--
-- Step fields:
--   id, zone, zoneEN        map area
--   mapID                   the step's uiMapID (classic IDs, unconfirmed on
--                           Forever; the map code checks the name and falls
--                           back to a search by name)
--   mapZone, mapZoneEN      the map's name when it is not the step's zone
--   points                  GF-008-D: the step's map points, in order:
--                             x, y      precise coordinates (0-100)
--                             kind      "start" 接任務 / "turnin" 交任務並接下一個 /
--                                       "route" 路線點 (cart, zeppelin tower, flight point)
--                             label     what is there
--                             conf      "multi" 多來源一致 / "single" 單一來源 /
--                                       "approx" 大約 (map knowledge, no reliable source)
--                             approx    the landmark the approximate point sits on
--                             src       where the numbers come from
--                             mapID, zone, zoneEN  when the point is on another map
--   x, y, approx            filled below from the first point on the step's own
--                           map (older code and tests read these)
--   noPin                   why this step opens its map without a point
--   landmark                what you will see there
--   object, objectEN        thing to interact with (Chinese name not confirmed)
--   action                  one line: what to do
--   tip                     one line: the usual stuck point
--   travel                  one line: how to get there
--   transfer, guards, noFlightPath, rpgHint   short extra lines
--   round                   1 = part of the first field-test round (spec §3)
--   verified                false until checked in the game

local _, ns = ...

ns.SleepingBagRoutes = ns.SleepingBagRoutes or {}

ns.SleepingBagRoutes.Horde = {
    id = "cozy-sleeping-bag-horde",
    title = "舒適睡袋（部落路線）",
    faction = "Horde",
    minLevel = 14,
    reward = "舒適睡袋（Cozy Sleeping Bag）",
    note = "不必打怪，但中段會穿過高等區域與聯盟地盤；攻略建議 30 級以上再走第 7～9 步。",
    source = "warcraft.wiki.gg、method.gg、kotaku.com、warcrafttavern.com（詳見研究筆記）",
    steps = {
        {
            id = "barrens",
            zone = "貧瘠之地", zoneEN = "The Barrens",
            mapID = 1413,
            points = {
                { x = 46.1, y = 74.3, kind = "start", label = "燒毀的殘骸", conf = "multi",
                  src = "Method 46.12, 74.32；wiki 46.4, 73.9；Kotaku、Tavern 46, 74" },
            },
            landmark = "南貧瘠之地：陶拉祖營地正南、大路旁燒黑的瞭望塔",
            object = "燒毀的殘骸", objectEN = "Burned-Out Remains",
            action = "點塔裡的殘骸，接「...and that note you found」。",
            tip = "紙條只說去「雙胞胎之地」，答案是西部荒野。",
            travel = "十字路口飛行點沿大路往南。",
            transfer = "十字路口（飛行點）",
            guards = "低等野怪，14 級可通過。",
            noFlightPath = "從奧格瑪經杜洛塔過橋進貧瘠之地，沿大路南下。",
            rpgHint = "往十字路口以南走，找路邊那座被燒成焦黑的塔。",
            round = 1,
            verified = false,
        },
        {
            id = "to-stranglethorn",
            zone = "荊棘谷", zoneEN = "Stranglethorn Vale",
            mapID = 1434,
            points = {
                { x = 32, y = 29, kind = "route", label = "格羅姆高營地飛艇塔", conf = "approx",
                  approx = "格羅姆高營地的飛艇塔", src = "地圖知識，沒有攻略給座標" },
            },
            landmark = "格羅姆高營地",
            action = "奧格瑪外飛艇塔搭往格羅姆高營地的飛艇。",
            tip = "下飛艇往西到海邊，沿海岸往北游到西部荒野南岸（Method 的走法）。",
            travel = "飛艇不需要飛行點；水裡有敵對納迦，貼著岸游。",
            transfer = "奧格瑪飛艇塔＞格羅姆高營地",
            guards = "荊棘谷怪物等級高，別進叢林。",
            noFlightPath = "飛艇不需要飛行點。",
            rpgHint = "往大海的另一邊去：飛艇能到南方的叢林。",
            round = 1,
            verified = false,
        },
        {
            id = "westfall",
            zone = "西部荒野", zoneEN = "Westfall",
            mapID = 1436,
            points = {
                { x = 37.1, y = 50.1, kind = "turnin", label = "燒毀的推車旁的殘骸", conf = "multi",
                  src = "Method 37.14, 50.13；Kotaku、Tavern 37, 50；wiki 37.5, 50.7" },
            },
            landmark = "亞歷斯頓農場（Alexston Farmstead）燒毀的推車",
            object = "燒毀的殘骸／釘住的木板", objectEN = "Burned-Out Remains / Nailed Plank",
            action = "點推車旁的殘骸交任務，接「Stepping Stones」。",
            tip = "物件名稱各攻略說法不一（殘骸或木板），找燒毀的推車就對了；獎勵兩瓶藥水。",
            travel = "從南岸上岸後往北走到農場。",
            transfer = "無",
            guards = "聯盟地區：避開哨兵嶺，別在路上停。",
            noFlightPath = "游泳與步行即可。",
            rpgHint = "穿過開闊農地，找一輛燒焦的推車。",
            round = 1,
            verified = false,
        },
        {
            id = "to-kalimdor",
            zone = "返回卡林多", zoneEN = "Back to Kalimdor",
            mapID = 1414, mapZone = "卡林多", mapZoneEN = "Kalimdor",
            noPin = "這一步是搭飛艇移動，沒有固定地點",
            landmark = "格羅姆高營地＞奧格瑪＞十字路口",
            action = "游回格羅姆高營地，搭飛艇回奧格瑪，再飛十字路口。",
            tip = "這趟先別用爐石：第 7 步要用爐石回奧格瑪。",
            travel = "從十字路口往西北走進石爪山脈。",
            transfer = "格羅姆高營地飛艇塔；十字路口（飛行點）",
            guards = "游回去時同樣避開納迦。",
            noFlightPath = "沒有十字路口飛行點就從奧格瑪步行。",
            rpgHint = "回到故鄉的大陸。",
            round = 1,
            verified = false,
        },
        {
            id = "stonetalon-litter",
            zone = "石爪山脈", zoneEN = "Stonetalon Mountains",
            mapID = 1442,
            points = {
                { x = 40.8, y = 52.5, kind = "turnin", label = "口袋裡的雜物（營地箱子上）", conf = "multi",
                  src = "wiki 40.8, 52.5；另一份攻略摘要 40.6, 52.4（Method 寫 54.6, 52.4，不一致）" },
                { x = 47, y = 61, kind = "route", label = "烈日石居（飛行點）", conf = "approx",
                  approx = "烈日石居", src = "地圖知識" },
            },
            landmark = "烈日石居往北山路盡頭的小營地，有營火",
            object = "口袋裡的雜物", objectEN = "Pocket Litter",
            action = "點營地箱子上的雜物交任務，接「Scramble」。",
            tip = "獎勵有 12 格的工具箱；營火的「Rekindle」可略過（有人回報會壞）。",
            travel = "從烈日石居往北走山路上去。",
            transfer = "烈日石居（飛行點）",
            guards = "中等級野怪，走山路別拉怪。",
            noFlightPath = "從十字路口往西北步行進石爪山脈。",
            rpgHint = "到烈日石居一帶，沿山坡小路走到有營火的地方。",
            round = 1,
            verified = false,
        },
        {
            id = "stonetalon-mound",
            zone = "石爪山脈", zoneEN = "Stonetalon Mountains",
            mapID = 1442,
            points = {
                { x = 39.6, y = 49.9, kind = "turnin", label = "一堆泥土", conf = "multi",
                  src = "wiki 39.6, 49.9；Method 39.61, 49.88；Dot Esports 39.62, 49.86" },
            },
            landmark = "營地往北上坡的土堆",
            object = "一堆泥土", objectEN = "Mound of Dirt",
            action = "往北上坡點土堆交任務，接「Wet Job」；獎勵選一把遠程武器。",
            tip = "坡邊是懸崖，摔下去要繞一大圈。",
            travel = "從上一步營地往北走一小段。",
            guards = "與上一步相同。",
            noFlightPath = "步行即可。",
            rpgHint = "從營火往北上坡，留意翻過的土。",
            round = 1,
            verified = false,
        },
        {
            id = "to-loch-modan",
            zone = "前往洛克莫丹", zoneEN = "To Loch Modan",
            mapID = 1415, mapZone = "東部王國", mapZoneEN = "Eastern Kingdoms",
            noPin = "這一步是跨好幾區的長途移動，看大陸地圖找路線",
            landmark = "幽暗城＞銀松森林＞希爾斯布萊德丘陵＞阿拉希高地＞濕地＞洛克莫丹",
            action = "爐石回奧格瑪，搭飛艇到幽暗城，一路往東南走到洛克莫丹。",
            tip = "最危險的一段：沒坐騎約 40 分鐘，路上怪到 60 級；沿路開飛行點。",
            travel = "幽暗城＞銀松森林＞希爾斯布萊德＞阿拉希＞濕地＞洛克莫丹。",
            transfer = "幽暗城飛艇塔；塔倫米爾（飛行點）",
            guards = "濕地米奈希爾港、塞爾薩瑪一帶有聯盟守衛，貼大路走。",
            noFlightPath = "全程步行，路線相同。",
            rpgHint = "先往北方的亡者之城，再一路往東南穿過高地與沼澤，直到矮人的湖區。",
            verified = false,
        },
        {
            id = "loch-modan",
            zone = "洛克莫丹", zoneEN = "Loch Modan",
            mapID = 1432,
            points = {
                { x = 49.5, y = 12.9, kind = "turnin", label = "雕刻的小雕像（水壩平台）", conf = "multi",
                  src = "wiki 49.5, 12.8；Method 49.45, 12.91；Tavern 49, 12" },
            },
            landmark = "北邊的石壁水壩（Stonewrought Dam）",
            object = "雕刻的小雕像", objectEN = "Carved Figurine",
            action = "從水壩中段往北側跳到下方平台，點雕像交任務，接「Eagle's Fist」。",
            tip = "水壩有高等聯盟守衛巡邏，可能會死；跑屍回來再跳。",
            travel = "從濕地進洛克莫丹後往北走到水壩。",
            guards = "跳下前先看守衛走到哪。",
            noFlightPath = "步行即可。",
            rpgHint = "找湖北邊那道巨大的水壩，雕像在水壩的一處平台上。",
            verified = false,
        },
        {
            id = "thoradin-wall",
            zone = "希爾斯布萊德丘陵", zoneEN = "Hillsbrad Foothills",
            mapID = 1424,
            points = {
                { x = 87.4, y = 49.6, kind = "route", label = "牆缺口的推車（爬牆起點）", conf = "multi",
                  src = "Method 87.36, 49.62；另一份攻略摘要 87.3, 49.6" },
                { x = 22.5, y = 24.2, kind = "turnin", label = "信差的包包＋匆忙捲起的背包", conf = "single",
                  mapID = 1417, zone = "阿拉希高地", zoneEN = "Arathi Highlands",
                  src = "wiki 22.5, 24.2（在阿拉希高地地圖上）" },
            },
            landmark = "希爾斯布萊德與阿拉希高地交界的索拉丁之牆",
            object = "信差的包包、匆忙捲起的背包", objectEN = "Messenger Bag / Hastily Rolled-Up Satchel",
            action = "推車爬上牆頂走到營地；先點包包交任務，再點背包拿舒適睡袋。",
            tip = "爬法：圓桶＞突出的木板＞推車頂＞牆頂；點完包包別離開牆上。",
            travel = "從洛克莫丹往北經濕地、阿拉希高地走到牆的西側缺口。",
            transfer = "阿拉希高地的落錘鎮（飛行點）",
            guards = "牆附近有中高等級怪，上了牆就比較安全。",
            noFlightPath = "從濕地北上沿大路步行。",
            rpgHint = "到分隔丘陵與高地的古老石牆，找能爬上牆頂的地方。",
            verified = false,
        },
    },
}

-- x / y / approx on each step from its first point on the step's own map.
for _, route in pairs(ns.SleepingBagRoutes) do
    for _, st in ipairs(route.steps or {}) do
        for _, p in ipairs(st.points or {}) do
            if not p.mapID or p.mapID == st.mapID then
                st.x, st.y = p.x, p.y
                st.approx = p.conf == "approx" and p.approx or nil
                break
            end
        end
    end
end
