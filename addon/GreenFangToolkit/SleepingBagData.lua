-- Route data for the sleeping bag helper (GF-008-A): Horde route of the
-- "Cozy Sleeping Bag" quest chain on WoW Forever.
--
-- Written in our own words from the facts in
-- https://www.warcrafttavern.com/forever/guides/cozy-sleeping-bag/ (read 2026-11-17)
-- plus general map knowledge. NOTHING here is field-tested yet: every step has
-- verified = false and the UI shows "待實地驗證". Quest IDs are intentionally
-- not used until they are confirmed on the Forever client.
--
-- Step fields:
--   id, zone, zoneEN        map area
--   x, y                    map coordinates (nil = not known yet)
--   landmark                what you will see there
--   object, objectEN        thing to interact with (Chinese name not confirmed)
--   action                  what to do
--   travel                  how to get there from the previous step
--   transfer                transfer point(s) on the way
--   guards                  danger / guard notes
--   noFlightPath            alternative if the flight path is not unlocked
--   rpgHint                 direction-only hint for RPG mode
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
    note = "整條路線不需要戰鬥，但中段會穿過等級較高的區域和聯盟地盤。",
    source = "https://www.warcrafttavern.com/forever/guides/cozy-sleeping-bag/",
    steps = {
        {
            id = "barrens",
            zone = "貧瘠之地", zoneEN = "The Barrens",
            x = 46, y = 74,
            landmark = "南貧瘠之地路邊一座燒毀的塔樓廢墟",
            object = "燒毀的殘骸", objectEN = "Burned-Out Remains",
            action = "點擊廢墟裡的殘骸，接下整條任務線的第一個任務。",
            travel = "從十字路口沿著往南的大路走，過了陶拉祖營地方向的岔路後留意路西側的廢墟。",
            transfer = "十字路口（飛行點）",
            guards = "附近只有低等野生動物，14 級以上可以安全通過。",
            noFlightPath = "沒有十字路口飛行點時，從奧格瑪出南門經杜洛塔，往西過橋進入貧瘠之地，再沿大路南下。",
            rpgHint = "往十字路口以南走，找路邊那座被燒成焦黑的塔。",
            round = 1,
            verified = false,
        },
        {
            id = "to-stranglethorn",
            zone = "荊棘谷", zoneEN = "Stranglethorn Vale",
            landmark = "格羅姆高營地，或南端的藏寶海灣",
            action = "這一步只是移動：選一條路線前往荊棘谷。",
            travel = "路線一：奧格瑪外的飛艇塔搭往格羅姆高營地的飛艇，離西部荒野比較近。"
                .. "路線二：在棘齒城搭船到藏寶海灣，離貧瘠之地比較近，但之後要在荊棘谷走比較長的路。",
            transfer = "奧格瑪飛艇塔＞格羅姆高營地；或 棘齒城碼頭＞藏寶海灣",
            guards = "荊棘谷的怪物等級比你高很多，盡量走大路、不要進叢林。藏寶海灣是中立城鎮，不要攻擊那裡的守衛。",
            noFlightPath = "飛艇和船都不需要飛行點。",
            rpgHint = "往大海的另一邊去：飛艇或船都能到南方的叢林。",
            round = 1,
            verified = false,
        },
        {
            id = "westfall",
            zone = "西部荒野", zoneEN = "Westfall",
            x = 37, y = 50,
            landmark = "西部荒野東側的亞歷斯頓農場（Alexston Farmstead）",
            object = "釘住的木板", objectEN = "Nailed Plank",
            action = "點擊農場裡釘著的木板，交出貧瘠之地的任務並接下一步。獎勵是兩瓶藥水。",
            travel = "從荊棘谷沿大路一路往北，經暮色森林西側進入西部荒野，再往農場走。",
            transfer = "格羅姆高營地（若走路線一）",
            guards = "西部荒野與暮色森林是聯盟地區。避開哨兵嶺和夜色鎮的聯盟守衛，不要在路上停留。",
            noFlightPath = "格羅姆高營地沒有飛行點也能走：出營地接上往北的大路即可。",
            rpgHint = "往北穿過暗色的森林，進入一片開闊農地，找東邊那座荒廢農舍。",
            round = 1,
            verified = false,
        },
        {
            id = "to-kalimdor",
            zone = "返回卡林多", zoneEN = "Back to Kalimdor",
            landmark = "奧格瑪或貧瘠之地",
            action = "這一步只是移動：回到卡林多。",
            travel = "用爐石最快；也可以原路搭飛艇或船回去。",
            transfer = "爐石點，或格羅姆高營地／藏寶海灣",
            guards = "原路返回時同樣要避開聯盟守衛。",
            noFlightPath = "爐石或原路返回都不需要飛行點。",
            rpgHint = "回到故鄉的大陸。",
            round = 1,
            verified = false,
        },
        {
            id = "stonetalon-litter",
            zone = "石爪山脈", zoneEN = "Stonetalon Mountains",
            landmark = "烈日石居附近山坡小路通往的一處小營地",
            object = "口袋裡的雜物", objectEN = "Pocket Litter",
            action = "點擊營地裡的雜物交任務，會拿到打火石、木柴和一把工具。"
                .. "旁邊的營火可以用打火石和木柴點燃（選擇性的小任務）。",
            travel = "從貧瘠之地西北的路進入石爪山脈，往烈日石居方向走；也可以從灰谷或莫高雷進入。",
            transfer = "烈日石居（飛行點）",
            guards = "沿路有中等級的野怪，走山路時注意不要拉到怪。",
            noFlightPath = "沒有烈日石居飛行點時，從十字路口往西北步行進入石爪山脈。",
            rpgHint = "到石爪山脈的烈日石居一帶，找山坡上的小路，沿路走到有營火的地方。",
            round = 1,
            verified = false,
        },
        {
            id = "stonetalon-mound",
            zone = "石爪山脈", zoneEN = "Stonetalon Mountains",
            landmark = "營地往東不遠處山坡上的土堆",
            object = "一堆泥土", objectEN = "Mound of Dirt",
            action = "點擊土堆交任務，拿到弓箭／槍械類的獎勵，並接下前往東部王國的任務。",
            travel = "從上一步的營地往東走一小段。",
            guards = "與上一步相同。",
            noFlightPath = "步行即可。",
            rpgHint = "從營火往東，留意山坡上翻過的土。",
            round = 1,
            verified = false,
        },
        {
            id = "to-loch-modan",
            zone = "前往洛克莫丹", zoneEN = "To Loch Modan",
            landmark = "幽暗城＞銀松森林＞希爾斯布萊德丘陵＞阿拉希高地＞濕地＞洛克莫丹",
            action = "這一步只是移動，也是部落路線最危險的一段。",
            travel = "在奧格瑪外搭飛艇到幽暗城，往南穿過銀松森林，往東南進入希爾斯布萊德丘陵，"
                .. "再往東進入阿拉希高地。從阿拉希南邊的橋進入濕地，沿大路往南到洛克莫丹。",
            transfer = "幽暗城飛艇塔；塔倫米爾（飛行點）",
            guards = "濕地與洛克莫丹有等級較高的怪物（約 30～40 級）和聯盟守衛，"
                .. "尤其是米奈希爾港和塞爾薩瑪一帶。盡量貼著大路走，不要停下來打怪。",
            noFlightPath = "沒有塔倫米爾飛行點時全程步行，路線相同。",
            rpgHint = "先往北方的亡者之城，再一路往東南穿過高地與沼澤，直到矮人的湖區。",
            verified = false,
        },
        {
            id = "loch-modan",
            zone = "洛克莫丹", zoneEN = "Loch Modan",
            x = 49, y = 12,
            landmark = "洛克莫丹北邊的石壁水壩（Stonewrought Dam）",
            object = "雕刻的小雕像", objectEN = "Carved Figurine",
            action = "從水壩上跳到下方的平台，點擊小雕像交任務，再接最後一個任務。",
            travel = "從濕地沿大路南下進入洛克莫丹後，往北走到水壩。",
            guards = "水壩附近有聯盟守衛巡邏，跳下平台前先確認周圍。",
            noFlightPath = "步行即可。",
            rpgHint = "找湖北邊那道巨大的水壩，雕像在水壩的一處平台上。",
            verified = false,
        },
        {
            id = "thoradin-wall",
            zone = "希爾斯布萊德丘陵", zoneEN = "Hillsbrad Foothills",
            landmark = "希爾斯布萊德與阿拉希高地交界的索拉丁之牆",
            object = "信差的包包、匆忙捲起的背包", objectEN = "Messenger Bag / Hastily Rolled-Up Satchel",
            action = "爬上牆頂走到平台，先點信差的包包交任務，再點下方的背包完成最後一個任務，拿到舒適睡袋。",
            travel = "從洛克莫丹往北回到濕地與阿拉希高地，走到索拉丁之牆。"
                .. "在牆北段缺口旁找一輛靠著牆的推車，跳上推車再沿著牆頂走到平台。",
            transfer = "阿拉希高地的落錘鎮（飛行點）",
            guards = "牆附近的阿拉希高地有中高等級的怪物，跳上牆後就比較安全。",
            noFlightPath = "沒有落錘鎮飛行點時，從濕地北上沿大路步行。",
            rpgHint = "到分隔丘陵與高地的古老石牆，找能爬上牆頂的地方。",
            verified = false,
        },
    },
}
