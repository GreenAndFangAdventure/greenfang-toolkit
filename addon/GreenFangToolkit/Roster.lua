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

-- GF-FIX-H: a damaged snapshot (not a table, members not a table) is no data.
function Roster.snapshotFor(realm, guild)
    local db = ns.db
    if not db then return nil end
    local r = db.roster
    local snaps = type(r) == "table" and r.snapshots
    local s = type(snaps) == "table" and snaps[ns.guildKey(realm, guild)]
    if type(s) ~= "table" or type(s.members) ~= "table" then return nil end
    return s
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

-- GF-FIX-C (review high-2): a scan whose content did not change keeps the
-- snapshot object, writes nothing to the outbox and tells nobody. Every row
-- still reads the client (GetGuildRosterInfo, Club info) on every
-- GUILD_ROSTER_UPDATE, as before: what changed shows as fast as it did.
-- Rows that did not change keep their member table. Roster.version goes up
-- only when the content changed; downstream caches (Recipes.index, ...) key
-- on it instead of the snapshot object.
Roster.version = 0
Roster.scans, Roster.rebuilds, Roster.outboxWrites = 0, 0, 0 -- diagnostics, tests
-- [guild key] = { snap, sigs = { row sig... }, rows = { member... } } in
-- GetGuildRosterInfo order; this session only.
local seen = {}
local pubOf = setmetatable({}, { __mode = "k" }) -- member -> its public fields as one string
local recordedAt = {} -- [guild key] = capturedAt of the last roster.snapshot written

-- Members of a snapshot by GUID and name (the "cached" fallbacks below);
-- built only when a row needs it, once per snapshot object.
local olderFor, olderIndex = nil, nil
local function olderMembers(realm, guild)
    local existing = Roster.snapshotFor(realm, guild)
    if olderIndex and olderFor == existing then return olderIndex end
    local previous = { byGUID = {}, byName = {} }
    olderFor, olderIndex = existing, previous
    if type(existing) ~= "table" then return previous end
    for _, m in ipairs(existing.members or {}) do
        if type(m) == "table" then
            if type(m.guid) == "string" and m.guid ~= "" then previous.byGUID[m.guid] = m end
            if type(m.name) == "string" then previous.byName[keyName(m.name)] = m end
        end
    end
    return previous
end

local function oldFor(realm, guild, guid, name)
    local previous = olderMembers(realm, guild)
    return (guid and previous.byGUID[guid]) or previous.byName[keyName(name)]
end

-- The fields Sync puts in roster.snapshot, as one string.
local function publicSig(m)
    local s = pubOf[m]
    if s then return s end
    local parts = {}
    for i, f in ipairs(ns.Sync and ns.Sync.ROSTER_MEMBER_FIELDS or {}) do
        local v = m[f]
        parts[i] = type(v) == "table" and table.concat(v, "\2") or tostring(v)
    end
    s = table.concat(parts, "\1")
    pubOf[m] = s
    return s
end

local function stamp(snapshot, capturedAt)
    snapshot.capturedAt = capturedAt -- Unix timestamp, NOT a local date string
    snapshot.capturedAtUTC = ns.utcTime(capturedAt)
    snapshot.capturedAtLocal = ns.localTime(capturedAt)
end

local function rememberOwn(ownGUID, guild, own)
    if not ns.Sync then return end
    -- The scan proves the guild (and our own rank) for this session.
    if own then
        ns.Sync.rememberGuild(ownGUID, guild, own.guildRank)
        ns.Data.rememberFullName(ownGUID, own.name) -- GF-001-D24
    end
    ns.Sync.rememberGuild(ownGUID, guild, nil)
end

local function writeOutbox(key, snapshot)
    if not ns.Sync then return end
    local entry = ns.Sync.recordRoster(snapshot)
    if entry then
        recordedAt[key] = snapshot.capturedAt
        Roster.outboxWrites = Roster.outboxWrites + 1
    else
        recordedAt[key] = nil -- not written (combat, sync off...): the next scan tries again
    end
end

-- Returns ok, countOrReason, snapshot, changed (false: the same content as
-- the last scan; the snapshot object, the outbox and Roster.version stay).
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
    local key = ns.guildKey(realm, guild)
    local faction = UnitFactionGroup and str((UnitFactionGroup("player"))) or ""
    online = type(online) == "number" and online or 0
    Roster.scans = Roster.scans + 1
    local last = seen[key]
    if last and ns.db.roster.snapshots[key] ~= last.snap then last = nil end -- replaced elsewhere
    local lastSigs, lastRows = last and last.sigs or {}, last and last.rows or {}
    local lastBySig, taken -- built on the first row that moved or changed
    local clubGUID, clubExact, clubShort = guildClubIndex()
    local ownGUID = ns.Data.player().guid
    local ownName = str((ns.call(UnitName, "player")))
    local ownProf = ns.Data.ownProfessionNames()
    local ownProfText = table.concat(ownProf, "\2")
    local ownRace, _, ownRaceID = nil, nil, nil
    ownRace, _, ownRaceID = ns.call(UnitRace, "player")
    ownRace, ownRaceID = str(ownRace), ns.num(ownRaceID)
    local sigs, rows, reused, own = {}, {}, 0, nil
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
            local prof, profSource = ns.Data.professionsFromClub(info), "guild"
            local raceID = info and ns.num(info.race) or nil
            local race = ns.Data.raceFromID(raceID)
            local raceSource = race and "guild" or "missing"
            -- Roster names carry "-Realm"; UnitName does not.
            local isSelf = (ownGUID ~= nil and ownGUID == guid)
                or (ownName ~= "" and (name == ownName or name == ownName .. "-" .. realm
                    or name == ownName .. "-" .. realm:gsub("%s", "")))
            local cached = false -- the professions come from the last snapshot
            if #prof == 0 then
                if isSelf and #ownProf > 0 then
                    prof, profSource = ownProf, "self"
                else
                    local previousMember = oldFor(realm, guild, guid, name)
                    if previousMember and type(previousMember.professions) == "table"
                        and #previousMember.professions > 0 then
                        prof, profSource, cached = previousMember.professions, "cached", true
                    else
                        prof, profSource = {}, "missing"
                    end
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
            if not race then
                local previousMember = oldFor(realm, guild, guid, name)
                if previousMember and type(previousMember.race) == "string" and previousMember.race ~= "" then
                    race = previousMember.race
                    raceID = previousMember.raceID
                    raceSource = "cached"
                end
            end
            local class = className ~= "" and className or (classToken ~= "" and classToken or "未知")
            raceID = type(raceID) == "number" and raceID or nil
            level = type(level) == "number" and level or 0
            -- Everything the member table holds, as one string.
            local profText = profSource == "self" and ownProfText or table.concat(prof, "\2")
            local sig = name .. "\1" .. (race or "") .. "\1" .. tostring(raceID) .. "\1" .. raceSource
                .. "\1" .. class .. "\1" .. classToken .. "\1" .. profText .. "\1" .. profSource .. "\1" .. level
                .. "\1" .. zone .. "\1" .. (isOnline and "1" or "0") .. "\1" .. rank .. "\1" .. tostring(rankIndex)
                .. "\1" .. (guid or "")
            local k = #rows + 1
            local m
            if lastSigs[k] == sig and not (taken and taken[lastRows[k]]) then
                m = lastRows[k] -- the same row at the same place: the usual case
            else
                if not lastBySig then
                    lastBySig, taken = {}, {}
                    for j, s in ipairs(lastSigs) do lastBySig[s] = lastRows[j] end
                    for j = 1, k - 1 do taken[rows[j]] = true end
                end
                m = lastBySig[sig]
                if m and taken[m] then m = nil end
            end
            if m then
                reused = reused + 1
                if taken then taken[m] = true end
            else
                m = {
                    name = name,
                    race = race or "",
                    raceID = raceID,
                    raceSource = raceSource,
                    class = class,
                    classToken = classToken,
                    professions = cached and ns.copy(prof) or prof,
                    professionSource = profSource,
                    level = level,
                    zone = zone,
                    online = isOnline and true or false,
                    guildRank = rank,
                    rankIndex = rankIndex,
                    guid = guid,
                }
            end
            sigs[k], rows[k] = sig, m
            if ownGUID and guid == ownGUID then own = m end
        end
    end
    -- A partial refresh must never replace a complete snapshot.
    if #rows ~= total then return false, "名冊仍在載入，已保留上一份報告" end
    local capturedAt = ns.now()
    local snapshot = last and last.snap
    if snapshot and reused == #rows and #lastRows == #rows
        and snapshot.online == online and snapshot.faction == faction and snapshot.guild == guild then
        -- Same content: only the time of the scan moves (GF Sync gets it at logout, Roster.flush).
        stamp(snapshot, capturedAt)
        ns.db.roster.lastKey = key
        rememberOwn(ownGUID, guild, own)
        if not recordedAt[key] then writeOutbox(key, snapshot) end -- the last write did not go through
        return true, #rows, snapshot, false
    end
    -- Did what roster.snapshot carries change? A row kept as it was did not.
    local pubChanged = not snapshot or #lastRows ~= #rows
    if not pubChanged and reused < #rows then
        local lastByName = {}
        for _, m in ipairs(lastRows) do lastByName[m.name] = m end
        for _, m in ipairs(rows) do
            local before = lastByName[m.name]
            if before ~= m and not (before and publicSig(before) == publicSig(m)) then pubChanged = true; break end
        end
    end
    local members = {}
    for k, m in ipairs(rows) do members[k] = m end
    table.sort(members, function(a, b) return a.name < b.name end)
    snapshot = {
        guild = guild,
        realm = realm,
        faction = faction,
        total = #members,
        online = online,
        members = members,
    }
    stamp(snapshot, capturedAt)
    ns.db.roster.snapshots[key] = snapshot
    ns.db.roster.lastKey = key
    seen[key] = { snap = snapshot, sigs = sigs, rows = rows }
    Roster.version = Roster.version + 1
    Roster.rebuilds = Roster.rebuilds + 1
    rememberOwn(ownGUID, guild, own)
    -- roster.snapshot carries no zone or online: written when what it carries changed.
    if pubChanged or not recordedAt[key] then writeOutbox(key, snapshot) end
    return true, #members, snapshot, true
end

-- Logout (Init): GF Sync still gets the time of the last scan, as before,
-- when the scans since the last roster.snapshot found nothing new for it.
function Roster.flush()
    if not ns.db or type(ns.db.roster) ~= "table" then return nil end
    local key = ns.db.roster.lastKey
    local snapshot = key and seen[key] and seen[key].snap
    if not snapshot or ns.db.roster.snapshots[key] ~= snapshot then return nil end
    if recordedAt[key] == snapshot.capturedAt then return false end
    writeOutbox(key, snapshot)
    return recordedAt[key] ~= nil
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
