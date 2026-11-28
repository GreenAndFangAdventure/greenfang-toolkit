-- Route data for the sleeping bag helper (GF-008-A): Horde route of the
-- "Cozy Sleeping Bag" quest chain on WoW Forever.
--
-- GF-008-D: rewritten in our own words from several public guides
-- (docs/research/GF-008-D_guide.md). GF-008-E (owner 2026-11-28: 步驟太多太囉嗦、
-- 沒有地點的步驟要併進有地點的步驟): nine steps became five; every step has a
-- place on its own map; one line to do, at most one line to watch out for.
-- Sources cross-checked again for GF-008-E: wow.gg (zh-cn), conquestcapped,
-- skycoach, leprestore, kami-labs, gfinity, plus the GF-008-D set.
-- NOTHING here is field-tested yet: every step has verified = false. Quest IDs
-- are intentionally not used until they are confirmed on the Forever client.
--
-- One route per faction: ns.SleepingBagRoutes[<key>] = { faction = "Horde" |
-- "Alliance", ... }. SleepingBag.lua picks the route whose `faction` matches.
--
-- Step fields:
--   id, zone, zoneEN        map area (the step's own map)
--   mapID                   the step's uiMapID (classic IDs, checked by name)
--   points                  the step's map points, in order; AT LEAST ONE on the
--                           step's own map (GF-008-E, ns.SleepingBagCheck):
--                             x, y      coordinates (0-100)
--                             kind      "start" 接任務 / "turnin" 交任務並接下一個 /
--                                       "route" 路線點 (cart, zeppelin tower, path)
--                             label     what is there
--                             conf      "multi" 多來源一致 / "single" 單一來源 /
--                                       "approx" 大約 (map knowledge)
--                             approx    the landmark an approximate point sits on
--                             src       where the numbers come from
--                             mapID, zone, zoneEN  when the point is on another map
--   x, y, approx            filled below from the first point on the step's own map
--   action                  ONE sentence: where to go, what to do
--   tip                     at most one sentence: what to bring / level / danger
--   landmark, rpgHint, object, objectEN   for the RPG text (switched off)
--   verified                false until checked in the game
--   GF-008-F:
--   points[i].words         places in `action` that are this point (each a
--                           link on the page that opens the map on the point);
--                           only points with coordinates have words
--   doneWhen                the quest log says the step is behind the player:
--                             completed = { questID, ... }  any flagged completed
--                             onQuest   = { questID, ... }  any in the quest log
--                           (route.questChain: the chain's IDs, see below)

local _, ns = ...

ns.SleepingBagRoutes = ns.SleepingBagRoutes or {}

ns.SleepingBagRoutes.Horde = {
    id = "cozy-sleeping-bag-horde",
    title = "舒適睡袋（部落路線）",
    faction = "Horde",
    minLevel = 14,
    layout = 2, -- GF-008-E: the five-step layout (a saved step of the nine-step one is moved over)
    -- GF-008-E: the nine-step layout's saved step (1-10, 10 = finished) -> this layout's.
    fromLayout1 = { 1, 2, 2, 3, 3, 3, 4, 4, 5, 6 },
    reward = "舒適睡袋（Cozy Sleeping Bag）",
    -- GF-008-F: the chain's quest IDs, in order. warcraft.wiki.gg (each quest's
    -- page) and wowhead classic (each quest page and its series list) agree
    -- (read 2026-11-28): 79007 ...and that note you found (Horde), 79192 Stepping
    -- Stones, 79980 Scramble, 79974 Wet Job, 79975 Eagle's Fist, 79976 This Must
    -- Be The Place (reward: item 211527). These are the Season of Discovery IDs;
    -- NOT yet checked on the Forever client (/gftk probe sleepingbag prints them).
    questChain = { 79007, 79192, 79980, 79974, 79975, 79976 },
    questSource = "warcraft.wiki.gg、wowhead classic（兩者一致；永恆服待確認）",
    note = "不必打怪，但第 4、5 步要穿過聯盟地盤和高等區域。",
    source = "wow.gg、warcraft.wiki.gg、method.gg、kotaku.com、conquestcapped.com、skycoach.gg 等攻略交叉比對",
    steps = {
        {
            id = "barrens",
            zone = "貧瘠之地", zoneEN = "The Barrens",
            mapID = 1413,
            points = {
                { x = 46.1, y = 74.3, kind = "start", label = "燒毀的殘骸（黑塔裡）", conf = "multi", words = { "燒黑的瞭望塔" },
                  src = "Method 46.12, 74.32；wiki 46.4, 73.9；wow.gg、Kotaku、Tavern、skycoach 46, 74" },
            },
            action = "到陶拉祖營地正南、大路旁燒黑的瞭望塔，點塔裡燒毀的殘骸接第一個任務。",
            tip = "14 級就能接；從十字路口飛行點沿大路往南走。",
            landmark = "南貧瘠之地：陶拉祖營地正南、大路旁燒黑的瞭望塔",
            rpgHint = "往十字路口以南走，找路邊那座被燒成焦黑的塔。",
            object = "燒毀的殘骸", objectEN = "Burned-Out Remains",
            doneWhen = { onQuest = { 79007 }, completed = { 79007 } }, -- GF-008-F: the first quest taken
            verified = false,
        },
        {
            id = "westfall",
            zone = "西部荒野", zoneEN = "Westfall",
            mapID = 1436,
            points = {
                { x = 37.1, y = 50.1, kind = "turnin", label = "燒毀推車旁的殘骸", conf = "multi", words = { "亞歷斯頓農場" },
                  src = "Method 37.14, 50.13；wiki 37.5, 50.7；wow.gg、Kotaku、Tavern、skycoach 37, 50" },
                { x = 32, y = 29, kind = "route", label = "格羅姆高營地飛艇塔", conf = "approx", words = { "格羅姆高營地" },
                  approx = "格羅姆高營地的飛艇塔", src = "地圖知識，沒有攻略給座標",
                  mapID = 1434, zone = "荊棘谷", zoneEN = "Stranglethorn Vale" },
            },
            action = "奧格瑪搭飛艇到荊棘谷格羅姆高營地，下海往北沿岸游到西部荒野，點亞歷斯頓農場燒毀推車旁的殘骸。",
            tip = "聯盟地區，交完就走；海裡有納迦，貼著岸游。",
            landmark = "亞歷斯頓農場燒毀的推車",
            rpgHint = "坐飛艇到南方叢林，再沿海岸往北到開闊農地，找燒焦的推車。",
            object = "燒毀的殘骸（也有攻略寫釘住的木板）", objectEN = "Burned-Out Remains / Nailed Plank",
            doneWhen = { completed = { 79007 } }, -- GF-008-F: turned in at the Westfall remains
            verified = false,
        },
        {
            id = "stonetalon",
            zone = "石爪山脈", zoneEN = "Stonetalon Mountains",
            mapID = 1442,
            points = {
                { x = 40.6, y = 52.4, kind = "turnin", label = "口袋裡的雜物（營地箱子上）", conf = "multi", words = { "箱子上的雜物" },
                  src = "wow.gg、conquestcapped、搜尋摘要 40.6, 52.4；wiki 40.8, 52.5（Method 寫 54.6, 52.4，不採用）" },
                { x = 39.6, y = 49.9, kind = "turnin", label = "一堆泥土（營地北邊坡上）", conf = "multi", words = { "土堆" },
                  src = "wiki 39.6, 49.9；Method 39.61, 49.88；Dot Esports 39.62, 49.86；wow.gg 39.6, 49.8" },
                { x = 50.9, y = 52.3, kind = "route", label = "烈日石居往北的山路口", conf = "single", words = { "北邊山路" },
                  src = "conquestcapped 50.9, 52.3" },
            },
            action = "游回格羅姆高搭飛艇回奧格瑪，到石爪山脈烈日石居，沿北邊山路到營地點箱子上的雜物，再往北上坡點土堆。",
            tip = "回程先別用爐石（下一步要用）；坡邊是懸崖，別摔下去。",
            landmark = "烈日石居往北山路盡頭、有營火的小營地",
            rpgHint = "到烈日石居一帶，沿山坡小路走到有營火的地方，再往北上坡找翻過的土。",
            object = "口袋裡的雜物、一堆泥土", objectEN = "Pocket Litter / Mound of Dirt",
            doneWhen = { completed = { 79980 }, onQuest = { 79974 } }, -- GF-008-F: the mound of dirt done
            verified = false,
        },
        {
            id = "loch-modan",
            zone = "洛克莫丹", zoneEN = "Loch Modan",
            mapID = 1432,
            points = {
                { x = 49.5, y = 12.9, kind = "turnin", label = "雕刻的小雕像（水壩下方平台）", conf = "multi", words = { "北邊的水壩" },
                  src = "wiki 49.5, 12.8；Method 49.45, 12.91；wow.gg、conquestcapped 49.4, 12.9；Tavern 49, 12" },
            },
            action = "爐石回奧格瑪，搭飛艇到幽暗城，一路往東南走到洛克莫丹北邊的水壩，從水壩中段跳到下方平台點雕像。",
            tip = "最危險的一段：路上有高等怪、水壩有聯盟守衛，死了就跑屍回來再跳。",
            landmark = "洛克莫丹北邊的石壁水壩",
            rpgHint = "先往北方的亡者之城，再一路往東南到矮人的湖區，找湖北邊的大水壩。",
            object = "雕刻的小雕像", objectEN = "Carved Figurine",
            doneWhen = { completed = { 79974 } }, -- GF-008-F: turned in at the figurine
            verified = false,
        },
        {
            id = "thoradin-wall",
            zone = "希爾斯布萊德丘陵", zoneEN = "Hillsbrad Foothills",
            mapID = 1424,
            points = {
                { x = 87.3, y = 49.6, kind = "route", label = "牆邊壞掉的推車（爬牆起點）", conf = "multi", words = { "推車" },
                  src = "Method 87.36, 49.62；wow.gg、conquestcapped、skycoach、kami-labs、leprestore 87.3, 49.6" },
                { x = 22.5, y = 24.2, kind = "turnin", label = "信差的包包＋下面的背包", conf = "single", words = { "信差的包包" },
                  mapID = 1417, zone = "阿拉希高地", zoneEN = "Arathi Highlands",
                  src = "wiki 22.5, 24.2（阿拉希高地地圖）；其他攻略只說和推車同一處" },
            },
            action = "從洛克莫丹往北經濕地、阿拉希高地，走到索拉丁之牆靠丘陵那側，踩推車爬上牆，先點信差的包包，再點下面的背包拿睡袋。",
            tip = "爬法：圓桶＞突出的木板＞推車頂＞牆頂；點完包包別離開牆上。",
            landmark = "希爾斯布萊德丘陵與阿拉希高地交界的索拉丁之牆",
            rpgHint = "到分隔丘陵與高地的古老石牆，找能爬上牆頂的壞推車。",
            object = "信差的包包、匆忙捲起的背包", objectEN = "Messenger Bag / Hastily Rolled-Up Satchel",
            doneWhen = { completed = { 79976 } }, -- GF-008-F: the satchel (the bag) taken
            verified = false,
        },
    },
}

-- GF-008-E: problems of a route's data (empty = fine): every step needs a point
-- on its own map, an action and an id. Tests check every route; a later
-- Alliance route is held to the same rule.
function ns.SleepingBagCheck(route)
    local bad = {}
    for i, st in ipairs(type(route) == "table" and route.steps or {}) do
        local own = false
        for _, p in ipairs(type(st.points) == "table" and st.points or {}) do
            if (not p.mapID or p.mapID == st.mapID) and type(p.x) == "number" and type(p.y) == "number" then own = true end
        end
        if not own then bad[#bad + 1] = "第 " .. i .. " 步沒有地點" end
        if type(st.action) ~= "string" or st.action == "" then bad[#bad + 1] = "第 " .. i .. " 步沒有要做的事" end
        if type(st.id) ~= "string" or st.id == "" then bad[#bad + 1] = "第 " .. i .. " 步沒有 id" end
    end
    return bad
end

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
