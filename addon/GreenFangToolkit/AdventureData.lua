-- AdventureData (GF-002-B, spec R-4.1): the classic 1.x dungeons the
-- adventure tickets can target. Written for the toolkit (names and the usual
-- level ranges of the 1.x dungeons); no data copied from other addons.
-- id: short ASCII key used on the wire; min/max: suggested levels.

local _, ns = ...

local Data = {}
ns.AdventureData = Data

Data.DUNGEONS = {
    -- instance: the 1.x instance (map) ID GetInstanceInfo gives; 16001 not verified.
    -- Wings that share one instance (血色修道院, 黑石塔, 厄運之槌) share the ID.
    { id = "rfc", name = "怒焰裂谷", min = 13, max = 18, instance = 389 },
    { id = "wc", name = "哀嚎洞穴", min = 17, max = 24, instance = 43 },
    { id = "dm", name = "死亡礦坑", min = 17, max = 26, instance = 36 },
    { id = "sfk", name = "影牙城堡", min = 22, max = 30, instance = 33 },
    { id = "bfd", name = "黑暗深淵", min = 24, max = 32, instance = 48 },
    { id = "stk", name = "監獄", min = 24, max = 32, instance = 34 },
    { id = "gnr", name = "諾姆瑞根", min = 29, max = 38, instance = 90 },
    { id = "rfk", name = "剃刀沼澤", min = 29, max = 38, instance = 47 },
    { id = "smg", name = "血色修道院：墓地", min = 26, max = 36, instance = 189 },
    { id = "sml", name = "血色修道院：圖書館", min = 29, max = 39, instance = 189 },
    { id = "sma", name = "血色修道院：武器庫", min = 32, max = 42, instance = 189 },
    { id = "smc", name = "血色修道院：大教堂", min = 35, max = 45, instance = 189 },
    { id = "rfd", name = "剃刀高地", min = 37, max = 46, instance = 129 },
    { id = "ul", name = "奧達曼", min = 41, max = 51, instance = 70 },
    { id = "zf", name = "祖爾法拉克", min = 44, max = 54, instance = 209 },
    { id = "mar", name = "瑪拉頓", min = 46, max = 55, instance = 349 },
    { id = "st", name = "阿塔哈卡神廟", min = 50, max = 56, instance = 109 },
    { id = "brd", name = "黑石深淵", min = 52, max = 60, instance = 230 },
    { id = "lbrs", name = "黑石塔下層", min = 55, max = 60, instance = 229 },
    { id = "ubrs", name = "黑石塔上層", min = 58, max = 60, instance = 229 },
    { id = "dme", name = "厄運之槌：東", min = 55, max = 60, instance = 429 },
    { id = "dmw", name = "厄運之槌：西", min = 57, max = 60, instance = 429 },
    { id = "dmn", name = "厄運之槌：北", min = 57, max = 60, instance = 429 },
    { id = "strat", name = "斯坦索姆", min = 58, max = 60, instance = 329 },
    { id = "scholo", name = "通靈學院", min = 58, max = 60, instance = 289 },
}

Data.byId = {}
for _, d in ipairs(Data.DUNGEONS) do Data.byId[d.id] = d end

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

function Data.name(id) local d = Data.byId[id]; return d and d.name or tostring(id) end
