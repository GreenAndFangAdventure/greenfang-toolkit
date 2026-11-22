-- Data: game lookups (races, professions, the player's own character).
-- Every game API call is guarded so a missing function never breaks loading.

local _, ns = ...

local Data = {}
ns.Data = Data

Data.professionNamesZH = {
    [164] = "鍛造", [165] = "製皮", [171] = "鍊金術", [182] = "草藥學",
    [186] = "採礦", [197] = "裁縫", [202] = "工程學", [333] = "附魔", [393] = "剝皮",
    [129] = "急救", [185] = "烹飪", [356] = "釣魚", [755] = "珠寶設計", [773] = "銘文學",
}
Data.professionNamesEN = {
    [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
    [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
    [393] = "Skinning", [129] = "First Aid", [185] = "Cooking", [356] = "Fishing",
    [755] = "Jewelcrafting", [773] = "Inscription",
}
Data.raceNamesZH = {
    [1] = "人類", [2] = "獸人", [3] = "矮人", [4] = "夜精靈", [5] = "不死族",
    [6] = "牛頭人", [7] = "地精", [8] = "食人妖", [9] = "哥布林",
    [10] = "血精靈", [11] = "德萊尼", [22] = "狼人",
}
Data.raceNamesEN = {
    [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "Night Elf", [5] = "Undead",
    [6] = "Tauren", [7] = "Gnome", [8] = "Troll", [9] = "Goblin",
    [10] = "Blood Elf", [11] = "Draenei", [22] = "Worgen",
}

local function isZH() return GetLocale and GetLocale() == "zhTW" end

function Data.skillName(givenName, skillID)
    if type(givenName) == "string" and givenName ~= "" then return givenName end
    if type(skillID) ~= "number" or skillID < 1 then return nil end
    if C_TradeSkillUI and type(C_TradeSkillUI.GetTradeSkillDisplayName) == "function" then
        local ok, found = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, skillID)
        if ok and type(found) == "string" and found ~= "" then return found end
    end
    if isZH() then return Data.professionNamesZH[skillID] end
    return Data.professionNamesEN[skillID]
end

function Data.raceFromID(raceID)
    if type(raceID) ~= "number" or raceID < 1 then return nil end
    if C_CreatureInfo and type(C_CreatureInfo.GetRaceInfo) == "function" then
        local ok, info = pcall(C_CreatureInfo.GetRaceInfo, raceID)
        if ok and type(info) == "table" and type(info.raceName) == "string"
            and info.raceName ~= "" then
            return info.raceName
        end
    end
    if isZH() then return Data.raceNamesZH[raceID] end
    return Data.raceNamesEN[raceID]
end

function Data.professionsFromClub(info)
    local result = {}
    if type(info) ~= "table" then return result end
    local first = Data.skillName(ns.str(info.profession1Name), ns.num(info.profession1ID))
    local second = Data.skillName(ns.str(info.profession2Name), ns.num(info.profession2ID))
    if first then result[#result + 1] = first end
    if second and second ~= first then result[#result + 1] = second end
    return result
end

local skillLineByName
local function skillLineIDFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not skillLineByName then
        skillLineByName = {}
        for id, n in pairs(Data.professionNamesZH) do skillLineByName[n] = id end
        for id, n in pairs(Data.professionNamesEN) do skillLineByName[n:lower()] = id end
    end
    return skillLineByName[name] or skillLineByName[ns.str(name):lower()]
end

-- Detailed professions of the logged-in character:
-- { { name, skillLineID, rank, max }, ... }
-- 1. GetProfessions/GetProfessionInfo (present on 16001 per ForeverAPI; it
--    returned 7 values there, so every returned index is read).
-- 2. C_SkillInfo skill list (16001 replacement of GetSkillLineInfo; returns a table).
-- 3. Old global GetNumSkillLines/GetSkillLineInfo (classic clients).
-- Any value that cannot be read becomes nil; nothing here raises an error.
-- icon is only for the in-game window (Icons.lua); Sync never uploads it.
local function profession(name, skillLine, rank, maxRank, icon)
    name = ns.str(name)
    if name == "" then return nil end
    if ns.isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = nil end
    return {
        name = name,
        skillLineID = ns.num(skillLine) or skillLineIDFor(name),
        rank = ns.num(rank),
        max = ns.num(maxRank),
        icon = icon,
    }
end
Data.skillLineIDFor = skillLineIDFor

-- Professions the client listed but whose name could not be read (secret
-- or empty) on the last read (GF-001-D23): then an empty list is not "no
-- professions" and must not be uploaded as such.
Data.unreadableProfessions = 0

local function fromProfessionsAPI()
    if type(GetProfessions) ~= "function" or type(GetProfessionInfo) ~= "function" then return nil end
    local packed = { pcall(GetProfessions) }
    if not packed[1] then return nil end
    Data.unreadableProfessions = 0
    local result, seen = {}, {}
    for i = 2, table.maxn(packed) do
        local index = ns.num(packed[i])
        if index and not seen[index] then
            seen[index] = true
            local ok, name, icon, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, index)
            local p = ok and profession(name, skillLine, rank, maxRank, icon)
            if p then
                result[#result + 1] = p
            else
                Data.unreadableProfessions = Data.unreadableProfessions + 1
            end
        end
    end
    return result
end

local function fromSkillList(count, info)
    local result = {}
    for i = 1, count do
        local name, isHeader, rank, maxRank, skillID = info(i)
        if name and not isHeader then
            local id = ns.num(skillID)
            if not (id and Data.professionNamesEN[id]) then id = skillLineIDFor(ns.str(name)) end
            if id then
                local p = profession(name, id, rank, maxRank)
                if p then result[#result + 1] = p end
            end
        end
    end
    return result
end

local function fromCSkillInfo()
    if not (C_SkillInfo and type(C_SkillInfo.GetNumSkillLines) == "function"
        and type(C_SkillInfo.GetSkillLineInfo) == "function") then return nil end
    local count = ns.num((ns.call(C_SkillInfo.GetNumSkillLines)))
    if not count then return nil end
    return fromSkillList(count, function(i)
        local t = ns.call(C_SkillInfo.GetSkillLineInfo, i)
        if type(t) ~= "table" then return nil end
        return t.name, t.isHeader, t.rank, t.maxRank, t.skillID
    end)
end

local function fromGlobalSkillLines()
    if type(GetNumSkillLines) ~= "function" or type(GetSkillLineInfo) ~= "function" then return nil end
    local count = ns.num((ns.call(GetNumSkillLines)))
    if not count then return nil end
    return fromSkillList(count, function(i)
        local name, isHeader, _, rank, _, _, maxRank = ns.call(GetSkillLineInfo, i)
        return name, isHeader, rank, maxRank, nil
    end)
end

function Data.ownProfessionsDetailed()
    local r = fromProfessionsAPI()
    if r and #r > 0 then return r, "GetProfessions" end
    local r2 = fromCSkillInfo()
    if r2 and #r2 > 0 then return r2, "C_SkillInfo" end
    local r3 = fromGlobalSkillLines()
    if r3 and #r3 > 0 then return r3, "GetSkillLineInfo" end
    if r then return r, "GetProfessions" end
    return {}, "missing"
end

-- Only the two primary professions, by name (roster column style).
function Data.ownProfessionNames()
    local names = {}
    local primary = { [164] = true, [165] = true, [171] = true, [182] = true, [186] = true,
        [197] = true, [202] = true, [333] = true, [393] = true, [755] = true, [773] = true }
    for _, p in ipairs((Data.ownProfessionsDetailed())) do
        if (not p.skillLineID or primary[p.skillLineID]) and #names < 2 then
            names[#names + 1] = p.name
        end
    end
    return names
end

-- GF-001-D24: full name "名字 姓氏" as the guild roster shows it. The site's
-- roster (Blizzard API) has full names; UnitName gives only the first part,
-- so the site could not find the uploader (character_not_in_roster).
-- Only ever found by GUID in the roster, never guessed. Remembered per
-- character in settings.fullNames (GF Sync never reads settings).
function Data.cleanFullName(v)
    local s = ns.str(v)
    -- A normal space U+0020 between the parts (no-break and ideographic
    -- spaces become one); nothing else in the name is changed.
    s = s:gsub("\194\160", " "):gsub("\227\128\128", " ")
    s = s:match("^([^-]+)") or s -- no "-Realm"
    return s:match("^%s*(.-)%s*$") or ""
end

local function fullNameStore()
    local s = ns.db and ns.db.settings
    if type(s) ~= "table" then return nil end
    if type(s.fullNames) ~= "table" then s.fullNames = {} end
    return s.fullNames
end

function Data.rememberFullName(guid, name)
    name = Data.cleanFullName(name)
    local store = fullNameStore()
    if store and type(guid) == "string" and guid ~= "" and name ~= "" then store[guid] = name end
end

-- GUID -> full name from the last roster scan, rebuilt when the scan changes.
local index, indexOf, indexAt = nil, nil, nil
function Data.rosterFullNames()
    local r = ns.db and ns.db.roster
    local snap = type(r) == "table" and type(r.snapshots) == "table" and r.lastKey and r.snapshots[r.lastKey]
    if type(snap) ~= "table" then return {} end
    if snap ~= indexOf or snap.capturedAt ~= indexAt then
        index = {}
        for _, m in ipairs(type(snap.members) == "table" and snap.members or {}) do
            if type(m) == "table" and type(m.guid) == "string" and m.guid ~= "" then
                local n = Data.cleanFullName(m.name)
                if n ~= "" then index[m.guid] = n end
            end
        end
        indexOf, indexAt = snap, snap.capturedAt
    end
    return index
end

-- A guild member's full name by GUID, or nil.
function Data.memberFullName(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    return Data.rosterFullNames()[guid]
end

-- The logged-in character's full name, or nil while the roster is not known.
function Data.fullName(guid)
    if type(guid) ~= "string" or guid == "" then return nil end
    local store = fullNameStore()
    local n = store and ns.str(store[guid]) or ""
    if n ~= "" then return n end
    -- From the last roster scan only (Roster.collect also remembers it):
    -- reading the live roster here would scan outside the target guild.
    n = Data.memberFullName(guid)
    if n then Data.rememberFullName(guid, n) end
    return n
end

-- Facts about the logged-in character used by both outbox kinds.
-- Every call is guarded: a missing function or secret value becomes nil.
local function optional(v) v = ns.str(v); if v == "" then return nil end; return v end

function Data.player()
    local p = {}
    local guid = ns.str((ns.call(UnitGUID, "player")))
    p.guid = guid ~= "" and guid or nil
    p.name = ns.str((ns.call(UnitName, "player")))
    p.fullName = Data.fullName(p.guid) -- GF-001-D24: nil until the roster is known
    p.realm = ns.realm() -- GF-001-D23: never "" when the realm can be known
    p.faction = ns.str((ns.call(UnitFactionGroup, "player")))
    p.level = ns.num((ns.call(UnitLevel, "player")))
    local className, classToken = ns.call(UnitClass, "player")
    p.class, p.classToken = ns.str(className), ns.str(classToken)
    local raceName, _, raceID = ns.call(UnitRace, "player")
    p.race, p.raceID = ns.str(raceName), ns.num(raceID)
    if ns.isInGuild() then
        local guildName, rankName = ns.call(GetGuildInfo, "player")
        p.guild, p.guildRank = optional(guildName), optional(rankName)
    end
    return p
end

-- Where the character is right now (D-009): { zone, subZone } or nil.
-- GetZoneText/GetSubZoneText are not in the ForeverAPI dump (it lists only
-- functions Blizzard's own docs leave out), so C_Map is the fallback for zone.
function Data.location()
    local zone = ns.str((ns.call(GetZoneText)))
    if zone == "" then zone = ns.str((ns.call(GetRealZoneText))) end
    if zone == "" and C_Map and type(C_Map.GetBestMapForUnit) == "function"
        and type(C_Map.GetMapInfo) == "function" then
        local mapID = ns.num((ns.call(C_Map.GetBestMapForUnit, "player")))
        local info = mapID and ns.call(C_Map.GetMapInfo, mapID)
        if type(info) == "table" then zone = ns.str(info.name) end
    end
    if zone == "" then return nil end
    local subZone = ns.str((ns.call(GetSubZoneText)))
    return { zone = zone, subZone = (subZone ~= "" and subZone ~= zone) and subZone or nil }
end

function Data.interface()
    if GetBuildInfo then
        local ok, _, _, _, tocVersion = pcall(GetBuildInfo)
        if ok and type(tocVersion) == "number" then return tocVersion end
    end
    return ns.DEFAULT_INTERFACE
end
