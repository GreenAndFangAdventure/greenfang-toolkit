-- AdventureData (GF-002-B, spec R-4.1): the classic 1.x dungeons the
-- adventure tickets can target. Written for the toolkit (names and the usual
-- level ranges of the 1.x dungeons); no data copied from other addons.
-- id: short ASCII key used on the wire; min/max: suggested levels.
--
-- GF-002-I (R-17.14 - R-17.16): the list drives everything (the picker, the
-- row art, the instance check, the default roles): a new dungeon or raid is
-- one more line here. category = "dungeon" | "raid"; size = the group size
-- (5 / 10 / 20 / 40); icon = the group finder art LFGIcon-<icon> (GameIcons
-- adds a fallback). The 團本 tab appears once a "raid" line exists.

local _, ns = ...

local Data = {}
ns.AdventureData = Data

Data.CATEGORIES = { "dungeon", "raid" }
Data.CATEGORY_NAME = { dungeon = "地城", raid = "團本" }
-- R-17.16: the roles a ticket starts with, by group size (raid rules come later).
Data.SIZE_ROLES = {
    [5] = { t = 1, h = 1, d = 3 }, [10] = { t = 2, h = 3, d = 5 },
    [20] = { t = 3, h = 5, d = 12 }, [40] = { t = 5, h = 10, d = 25 },
}

Data.DUNGEONS = {
    -- instance: the 1.x instance (map) ID GetInstanceInfo gives; 16001 not verified.
    -- Wings that share one instance (血色修道院, 黑石塔, 厄運之槌) share the ID.
    { id = "rfc", short = "怒焰", name = "怒焰裂谷", min = 13, max = 18, instance = 389, icon = "RagefireChasm" },
    { id = "wc", short = "哀嚎", name = "哀嚎洞穴", min = 17, max = 24, instance = 43, icon = "WailingCaverns" },
    { id = "dm", short = "死礦", name = "死亡礦坑", min = 17, max = 26, instance = 36, icon = "Deadmines" },
    { id = "sfk", short = "影牙", name = "影牙城堡", min = 22, max = 30, instance = 33, icon = "ShadowFangKeep" },
    { id = "bfd", short = "黑暗淵", name = "黑暗深淵", min = 24, max = 32, instance = 48, icon = "BlackfathomDeeps" },
    { id = "stk", short = "監獄", name = "監獄", min = 24, max = 32, instance = 34, icon = "StormwindStockades" },
    { id = "gnr", short = "諾姆", name = "諾姆瑞根", min = 29, max = 38, instance = 90, icon = "Gnomeregan" },
    { id = "rfk", short = "剃刀沼", name = "剃刀沼澤", min = 29, max = 38, instance = 47, icon = "RazorfenKraul" },
    { id = "smg", short = "墓地", name = "血色修道院：墓地", min = 26, max = 36, instance = 189, icon = "ScarletMonastery" },
    { id = "sml", short = "圖書館", name = "血色修道院：圖書館", min = 29, max = 39, instance = 189, icon = "ScarletMonastery" },
    { id = "sma", short = "武器庫", name = "血色修道院：武器庫", min = 32, max = 42, instance = 189, icon = "ScarletMonastery" },
    { id = "smc", short = "大教堂", name = "血色修道院：大教堂", min = 35, max = 45, instance = 189, icon = "ScarletMonastery" },
    { id = "rfd", short = "剃刀高", name = "剃刀高地", min = 37, max = 46, instance = 129, icon = "RazorfenDowns" },
    { id = "ul", short = "奧達曼", name = "奧達曼", min = 41, max = 51, instance = 70, icon = "Uldaman" },
    { id = "zf", short = "祖爾", name = "祖爾法拉克", min = 44, max = 54, instance = 209, icon = "ZulFarak" },
    { id = "mar", short = "瑪拉頓", name = "瑪拉頓", min = 46, max = 55, instance = 349, icon = "Maraudon" },
    { id = "st", short = "神廟", name = "阿塔哈卡神廟", min = 50, max = 56, instance = 109, icon = "SunkenTemple" },
    { id = "brd", short = "黑石深", name = "黑石深淵", min = 52, max = 60, instance = 230, icon = "BlackrockDepths" },
    { id = "lbrs", short = "黑石下", name = "黑石塔下層", min = 55, max = 60, instance = 229, icon = "BlackrockSpire" },
    { id = "ubrs", short = "黑石上", name = "黑石塔上層", min = 58, max = 60, instance = 229, icon = "BlackrockSpire" },
    { id = "dme", short = "厄運東", name = "厄運之槌：東", min = 55, max = 60, instance = 429, icon = "DireMaul" },
    { id = "dmw", short = "厄運西", name = "厄運之槌：西", min = 57, max = 60, instance = 429, icon = "DireMaul" },
    { id = "dmn", short = "厄運北", name = "厄運之槌：北", min = 57, max = 60, instance = 429, icon = "DireMaul" },
    { id = "strat", short = "斯坦", name = "斯坦索姆", min = 58, max = 60, instance = 329, icon = "Stratholme" },
    { id = "scholo", short = "通靈", name = "通靈學院", min = 58, max = 60, instance = 289, icon = "Scholomance" },
}

-- Fill the defaults and the index. Call again after adding lines (Data.add).
function Data.rebuild()
    Data.byId = {}
    for i, d in ipairs(Data.DUNGEONS) do
        d.category = d.category or "dungeon"
        d.size = d.size or (d.category == "raid" and 40 or 5)
        d.order = i
        Data.byId[d.id] = d
    end
    if ns.GameIcons and ns.GameIcons.registerDungeons then ns.GameIcons.registerDungeons(Data.DUNGEONS) end
end

-- One more destination (a raid later on); returns false for a bad or known id.
function Data.add(d)
    if type(d) ~= "table" or type(d.id) ~= "string" or not d.id:match("^[0-9a-z]+$") or (Data.byId or {})[d.id] then return false end
    if type(d.min) ~= "number" or type(d.max) ~= "number" or type(d.name) ~= "string" then return false end
    Data.DUNGEONS[#Data.DUNGEONS + 1] = d
    Data.rebuild()
    return true
end

-- Remove one (tests).
function Data.remove(id)
    for i = #Data.DUNGEONS, 1, -1 do if Data.DUNGEONS[i].id == id then table.remove(Data.DUNGEONS, i) end end
    Data.rebuild()
end

-- R-6.1 "等級合適": a few levels below the range still fit (a strong group can carry).
Data.LEVEL_SLACK = 3

function Data.fits(id, level)
    local d = Data.byId[id]
    if not d or type(level) ~= "number" then return d ~= nil end
    return level >= d.min - Data.LEVEL_SLACK and level <= d.max + Data.LEVEL_SLACK
end

-- Dungeons for a level (R-4.1: filtered by the player's level), in list order.
function Data.forLevel(level)
    local out = {}
    for _, d in ipairs(Data.DUNGEONS) do
        if type(level) ~= "number" or Data.fits(d.id, level) then out[#out + 1] = d end
    end
    return out
end

-- R-17.15: the lines of one category.
function Data.list(category)
    local out = {}
    for _, d in ipairs(Data.DUNGEONS) do if d.category == (category or "dungeon") then out[#out + 1] = d end end
    return out
end
function Data.has(category) return #Data.list(category) > 0 end

-- R-17.15: sorted by my level (the nearest range first, the list order on a tie);
-- onlyFit = 適合我.
function Data.sorted(category, level, onlyFit)
    local out = {}
    for _, d in ipairs(Data.list(category)) do
        if not onlyFit or Data.fits(d.id, level) then out[#out + 1] = d end
    end
    if type(level) == "number" then
        local function dist(d)
            if level < d.min then return d.min - level end
            if level > d.max then return level - d.max end
            return 0
        end
        table.sort(out, function(x, y)
            local a, b = dist(x), dist(y)
            if a ~= b then return a < b end
            return x.order < y.order
        end)
    end
    return out
end

-- R-17.16: the roles a new ticket for this destination starts with.
function Data.defaultRoles(id)
    local d = Data.byId[id]
    local r = Data.SIZE_ROLES[d and d.size or 5] or Data.SIZE_ROLES[5]
    return { t = r.t, h = r.h, d = r.d }
end
function Data.size(id) local d = Data.byId[id]; return d and d.size or 5 end
function Data.category(id) local d = Data.byId[id]; return d and d.category or "dungeon" end

function Data.name(id) local d = Data.byId[id]; return d and d.name or tostring(id) end
-- GF-002-C: the short name on a row (the full name is in the tooltip).
function Data.short(id) local d = Data.byId[id]; return d and (d.short or d.name) or tostring(id) end

Data.rebuild()
