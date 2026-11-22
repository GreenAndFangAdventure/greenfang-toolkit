-- Roster: scan the guild roster into a display snapshot (same rules as v0.3.1).
-- The display snapshot keeps zone/online for the in-game window; Sync strips
-- them before anything goes into the outbox.

local _, ns = ...
local str, keyName, shortName = ns.str, ns.keyName, ns.shortName

local Roster = {}
ns.Roster = Roster
Roster.queuedAfterCombat = false

-- Do not match a truncated name if more than one realm has the same name.
local function guildClubIndex()
    local byGUID, byExactName, byShortName = {}, {}, {}
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetClubMembers
        and C_Club.GetMemberInfo) then return byGUID, byExactName, byShortName end
    local okID, clubID = pcall(C_Club.GetGuildClubId)
    if not okID or not clubID then return byGUID, byExactName, byShortName end
    local okList, ids = pcall(C_Club.GetClubMembers, clubID)
    if not okList or type(ids) ~= "table" then return byGUID, byExactName, byShortName end
    for _, memberID in ipairs(ids) do
        local ok, info = pcall(C_Club.GetMemberInfo, clubID, memberID)
        if ok and type(info) == "table" then
            local guid, name = str(info.guid), str(info.name)
            if guid ~= "" then byGUID[guid] = info end
            if name ~= "" then
                byExactName[keyName(name)] = info
                local short = keyName(shortName(name))
                if byShortName[short] == nil then
                    byShortName[short] = info
                elseif byShortName[short] ~= info then
                    byShortName[short] = false
                end
            end
        end
    end
    return byGUID, byExactName, byShortName
end

local function clubInfoFor(guid, name, byGUID, byExact, byShort)
    local found = (guid and byGUID[guid]) or byExact[keyName(name)]
    if found then return found end
    found = byShort[keyName(shortName(name))]
    if found then return found end
    return nil
end

function Roster.snapshotFor(realm, guild)
    local db = ns.db
    if not db then return nil end
    return db.roster.snapshots[ns.guildKey(realm, guild)]
end

-- The roster window serves ns.Config.guild only (GF-001-D5): a character in
-- another guild, in no guild, or with guild info still loading gets no
-- snapshot, and no stored snapshot of any other guild is ever shown.
function Roster.available()
    return ns.guildState() == "target"
end

-- Snapshot shown in the window: the target guild's, when this character is in it.
function Roster.current()
    if not ns.db or not Roster.available() then return nil end
    local guild = str((ns.call(GetGuildInfo, "player")))
    local realm = ns.realm()
    local s = Roster.snapshotFor(realm, guild)
    if type(s) == "table" and type(s.members) == "table" and #s.members > 0 then return s end
    return nil
end

local function olderMembers(realm, guild)
    local previous = { byGUID = {}, byName = {} }
    local existing = Roster.snapshotFor(realm, guild)
    if type(existing) ~= "table" then return previous end
    for _, m in ipairs(existing.members or {}) do
        if type(m) == "table" then
            if type(m.guid) == "string" and m.guid ~= "" then previous.byGUID[m.guid] = m end
            if type(m.name) == "string" then previous.byName[keyName(m.name)] = m end
        end
    end
    return previous
end

local function oldFor(previous, guid, name)
    return (guid and previous.byGUID[guid]) or previous.byName[keyName(name)]
end

-- Returns ok, countOrReason, snapshot.
function Roster.collect()
    if not ns.db then return false, "插件尚未初始化" end
    local guildState = ns.guildState()
    if guildState == "loading" then return false, "公會資料讀取中" end
    if guildState == "none" then return false, "目前角色不在公會內" end
    if guildState ~= "target" then
        return false, string.format("目前角色不在%s", ns.targetGuildName())
    end
    if ns.inCombat() then
        Roster.queuedAfterCombat = true
        return false, "戰鬥中，結束後再更新"
    end
    if type(GetNumGuildMembers) ~= "function" or type(GetGuildRosterInfo) ~= "function" then
        return false, "公會 API 尚未就緒"
    end
    local okCounts, total, online = pcall(GetNumGuildMembers)
    total, online = ns.num(total), ns.num(online)
    if not okCounts or not total or total < 1 then
        return false, "公會名單尚未載入"
    end
    local guild = GetGuildInfo and str(GetGuildInfo("player")) or ""
    if guild == "" then return false, "尚未取得公會名稱" end
    local realm = ns.realm()
    local previous = olderMembers(realm, guild)
    local clubGUID, clubExact, clubShort = guildClubIndex()
    local ownGUID = ns.Data.player().guid
    local ownName = str((ns.call(UnitName, "player")))
    local ownProf = ns.Data.ownProfessionNames()
    local ownRace, _, ownRaceID = nil, nil, nil
    ownRace, _, ownRaceID = ns.call(UnitRace, "player")
    ownRace, ownRaceID = str(ownRace), ns.num(ownRaceID)
    local members = {}
    for i = 1, total do
        -- Return order is the Mainline one (not documented for 16001; checked in-game
        -- in GF-001-B). Every value is re-checked so a shifted or secret value
        -- becomes empty instead of breaking the scan.
        local ok, name, rank, rankIndex, level, className, zone, _, _, isOnline,
            _, classToken, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
        name, rank, className, zone = str(name), str(rank), str(className), str(zone)
        level = ns.num(level)
        rankIndex = ns.num(rankIndex)
        classToken = str(classToken)
        if not classToken:match("^[A-Z]+$") then classToken = "" end
        guid = str(guid)
        guid = guid:match("^Player%-") and guid or nil
        isOnline = isOnline == true or isOnline == 1
        if ok and name ~= "" then
            local info = clubInfoFor(guid, name, clubGUID, clubExact, clubShort)
            local previousMember = oldFor(previous, guid, name)
            local prof, profSource = ns.Data.professionsFromClub(info), "guild"
            local raceID = info and ns.num(info.race) or nil
            local race = ns.Data.raceFromID(raceID)
            local raceSource = race and "guild" or "missing"
            -- Roster names carry "-Realm"; UnitName does not.
            local isSelf = (ownGUID ~= nil and ownGUID == guid)
                or (ownName ~= "" and (name == ownName or name == ownName .. "-" .. realm
                    or name == ownName .. "-" .. realm:gsub("%s", "")))
            if #prof == 0 then
                if isSelf and #ownProf > 0 then
                    prof, profSource = ownProf, "self"
                elseif previousMember and type(previousMember.professions) == "table"
                    and #previousMember.professions > 0 then
                    prof, profSource = ns.copy(previousMember.professions), "cached"
                else
                    prof, profSource = {}, "missing"
                end
            end
            if not race and isSelf and type(ownRace) == "string" and ownRace ~= "" then
                race, raceID, raceSource = ownRace, ownRaceID, "self"
            end
            if not race and type(guid) == "string" and GetPlayerInfoByGUID then
                local okRace, _, _, localizedRace = pcall(GetPlayerInfoByGUID, guid)
                localizedRace = str(localizedRace)
                if okRace and localizedRace ~= "" then
                    race, raceSource = localizedRace, "guid"
                end
            end
            if not race and previousMember and type(previousMember.race) == "string"
                and previousMember.race ~= "" then
                race = previousMember.race
                raceID = previousMember.raceID
                raceSource = "cached"
            end
            members[#members + 1] = {
                name = name,
                race = race or "",
                raceID = type(raceID) == "number" and raceID or nil,
                raceSource = raceSource,
                class = str(className) ~= "" and className or (str(classToken) ~= "" and classToken or "未知"),
                classToken = str(classToken),
                professions = prof,
                professionSource = profSource,
                level = type(level) == "number" and level or 0,
                zone = str(zone),
                online = isOnline and true or false,
                guildRank = str(rank),
                rankIndex = rankIndex,
                guid = type(guid) == "string" and guid or nil,
            }
        end
    end
    -- A partial refresh must never replace a complete snapshot.
    if #members ~= total then return false, "名冊仍在載入，已保留上一份報告" end
    table.sort(members, function(a, b) return a.name < b.name end)
    local capturedAt = ns.now()
    local snapshot = {
        guild = guild,
        realm = realm,
        faction = UnitFactionGroup and str((UnitFactionGroup("player"))) or "",
        capturedAt = capturedAt, -- Unix timestamp, NOT a local date string
        capturedAtUTC = ns.utcTime(capturedAt),
        capturedAtLocal = ns.localTime(capturedAt),
        total = #members,
        online = type(online) == "number" and online or 0,
        members = members,
    }
    local key = ns.guildKey(realm, guild)
    ns.db.roster.snapshots[key] = snapshot
    ns.db.roster.lastKey = key
    if ns.Sync then
        -- The scan proves the guild (and our own rank) for this session.
        for _, m in ipairs(members) do
            if ownGUID and m.guid == ownGUID then
                ns.Sync.rememberGuild(ownGUID, guild, m.guildRank)
                ns.Data.rememberFullName(ownGUID, m.name) -- GF-001-D24
            end
        end
        ns.Sync.rememberGuild(ownGUID, guild, nil)
        ns.Sync.recordRoster(snapshot)
    end
    return true, #members, snapshot
end

function Roster.request()
    if not Roster.available() then return false end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
        return true
    elseif GuildRoster then
        GuildRoster()
        return true
    end
    return false
end
