-- Comm: in-game sharing between guild members who have the toolkit (D-011).
--
-- Each player broadcasts only THEIR OWN character on the GUILD channel. A
-- received message is about its sender, the name the game server puts in
-- CHAT_MSG_ADDON, and nobody else: messages carry no subject name, a message
-- that tries to name someone is dropped, and nothing received is ever sent on.
--
-- 16001 (docs/research/forever-api-16001.md): C_ChatInfo.RegisterAddonMessagePrefix,
-- C_ChatInfo.SendAddonMessage and CHAT_MSG_ADDON are verified in ForeverAPI;
-- the old globals are gone. Without C_ChatInfo the feature is simply off.
--
-- Wire format v1 (one addon message, at most 255 bytes):
--   "1~<msgID>~<part>~<parts>~<chunk>"
-- The chunks joined in order form the body: ";"-separated key=value pairs,
--   L=<level>  C=<classToken>  T=<capturedAt>
--   P=<id>,<rank>,<max>,<name>/<id>,<rank>,<max>,<name>/...
--   Z=<zone>  S=<subZone>          (whenever the client knows it, D-015)
-- Values are %XX-escaped for % ; = , / ~ | and control characters.
-- An unknown version is ignored; unknown keys are ignored.

local _, ns = ...
local str, keyName = ns.str, ns.keyName

local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "GFTK"
Comm.VERSION = "1"
Comm.MAX_BYTES = 255
Comm.THROTTLE = 300 -- seconds between broadcasts of the same character
Comm.MAX_PARTS = 8
Comm.PART_TIMEOUT = 60
-- Keys that would name another character. A message with any of them is
-- dropped whole: data is only ever about the sender.
Comm.FORBIDDEN_KEYS = { N = true, U = true, G = true, R = true, W = true }

local registered = false
local lastSentAt, lastSig, pendingTimer = nil, nil, false
local partials = {} -- [sender .. "~" .. msgID] = { parts, total, at }
local msgCounter = 0

---------------------------------------------------------------------------
-- Encoding (pure; covered by offline tests)
---------------------------------------------------------------------------

local function esc(v)
    return (str(v):gsub("[%%;=,/~|%c]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function unesc(v)
    return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function Comm.encodeBody(d)
    local fields = {}
    local function add(k, v) if v ~= nil and v ~= "" then fields[#fields + 1] = k .. "=" .. v end end
    add("L", d.level and tostring(d.level))
    add("C", d.classToken and esc(d.classToken))
    add("T", d.capturedAt and tostring(d.capturedAt))
    local profs = {}
    for _, p in ipairs(d.professions or {}) do
        profs[#profs + 1] = table.concat({ tostring(p.skillLineID or ""), tostring(p.rank or ""),
            tostring(p.max or ""), esc(p.name) }, ",")
    end
    add("P", table.concat(profs, "/"))
    if type(d.location) == "table" then
        add("Z", esc(d.location.zone))
        add("S", d.location.subZone and esc(d.location.subZone))
    end
    return table.concat(fields, ";")
end

-- Returns the data table, or nil, reason.
function Comm.decodeBody(body)
    local d = { professions = {} }
    for field in str(body):gmatch("[^;]+") do
        local k, v = field:match("^(%w+)=(.*)$")
        if not k then return nil, "malformed" end
        if Comm.FORBIDDEN_KEYS[k] then return nil, "third-party" end
        if k == "L" then d.level = tonumber(v)
        elseif k == "C" then d.classToken = unesc(v)
        elseif k == "T" then d.capturedAt = tonumber(v)
        elseif k == "P" then
            for item in v:gmatch("[^/]+") do
                local id, rank, max, name = item:match("^(%d*),(%d*),(%d*),(.*)$")
                if id and name ~= "" then
                    d.professions[#d.professions + 1] = { name = unesc(name), skillLineID = tonumber(id),
                        rank = tonumber(rank), max = tonumber(max) }
                end
            end
        -- GF-FIX-A (review 中-3): no | escapes, control characters or huge names.
        elseif k == "Z" then d.zone = ns.cleanText(unesc(v), 64)
        elseif k == "S" then d.subZone = ns.cleanText(unesc(v), 64)
        end
    end
    if type(d.capturedAt) ~= "number" then return nil, "no-time" end
    if d.classToken and (#d.classToken > 16 or not d.classToken:match("^[A-Z]+$")) then d.classToken = nil end
    if d.zone and d.zone ~= "" then
        d.location = { zone = d.zone, subZone = (d.subZone ~= "" and d.subZone) or nil }
    end
    d.zone, d.subZone = nil, nil
    return d
end

-- Cut a body into chunks so that every full message fits MAX_BYTES, never
-- splitting a UTF-8 character.
function Comm.split(body, msgID)
    local room = Comm.MAX_BYTES - #string.format("%s~%s~%d~%d~", Comm.VERSION, msgID, Comm.MAX_PARTS, Comm.MAX_PARTS)
    local chunks, i = {}, 1
    while i <= #body do
        local j = math.min(#body, i + room - 1)
        while j < #body and j > i do
            local b = body:byte(j + 1)
            if b < 0x80 or b >= 0xC0 then break end -- next byte starts a character
            j = j - 1
        end
        chunks[#chunks + 1] = body:sub(i, j)
        i = j + 1
    end
    if #chunks == 0 then chunks[1] = "" end
    local out = {}
    for n, c in ipairs(chunks) do
        out[n] = string.format("%s~%s~%d~%d~%s", Comm.VERSION, msgID, n, #chunks, c)
    end
    return out
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

function Comm.available()
    return C_ChatInfo ~= nil and type(C_ChatInfo.SendAddonMessage) == "function"
end

function Comm.register()
    if registered or not (C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function") then
        return registered
    end
    registered = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX) and true or false
    return registered
end

-- GF-001-D10: GuildForge found that on Forever AreOutgoingAddonChatMessagesRestricted()
-- answers true nearly all the time while messages still arrive, so 0.8.x may
-- never have sent anything. Only trust these checks inside instances (combat
-- is handled by the caller).
local function restricted()
    if ns.call(IsInInstance) ~= true then return false end
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
        local r = ns.call(C_ChatInfo.InChatMessagingLockdown)
        if r == true then return true end
    end
    if C_ChatInfo and type(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted) == "function" then
        local r = ns.call(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
        if r == true then return true end
    end
    return false
end

-- What this character would broadcast (all professions, including cooking,
-- fishing and first aid). Location only while the player shares it.
function Comm.ownData()
    local p = ns.Sync.player()
    local profs = {}
    for i, prof in ipairs((ns.Data.ownProfessionsDetailed())) do
        profs[i] = { name = prof.name, skillLineID = prof.skillLineID, rank = prof.rank, max = prof.max }
    end
    return {
        level = p.level, classToken = p.classToken ~= "" and p.classToken or nil,
        capturedAt = ns.now(), professions = profs,
        -- D-019 (GF-FIX-A): not when the player turned location sharing off.
        location = ns.Sync.shareLocation() and ns.Data.location() or nil,
    }
end

-- Returns true, parts or false, reason. force skips the throttle.
function Comm.broadcast(force)
    if ns.guildState() ~= "target" then return false, "other-guild" end
    if not Comm.available() then return false, "no-api" end
    if ns.inCombat() then Comm.queueBroadcast(); return false, "combat" end
    if restricted() then return false, "restricted" end
    local now = ns.now()
    if not force and lastSentAt and now - lastSentAt < Comm.THROTTLE then
        Comm.queueBroadcast(Comm.THROTTLE - (now - lastSentAt) + 1)
        return false, "throttled"
    end
    local data = Comm.ownData()
    -- Only re-send when level, class or professions changed (location alone
    -- does not trigger a broadcast; it rides along with the next one).
    local sig = Comm.encodeBody({ level = data.level, classToken = data.classToken,
        capturedAt = 0, professions = data.professions })
    if not force and sig == lastSig then return false, "unchanged" end
    Comm.register()
    msgCounter = msgCounter + 1
    local msgID = string.format("%x%x", math.floor(now) % 0x100000, msgCounter % 0x100)
    local parts = Comm.split(Comm.encodeBody(data), msgID)
    for _, m in ipairs(parts) do
        ns.call(C_ChatInfo.SendAddonMessage, Comm.PREFIX, m, "GUILD")
    end
    lastSentAt, lastSig = now, sig
    return true, #parts
end

-- One delayed broadcast (after the throttle window or after combat).
function Comm.queueBroadcast(delay)
    if pendingTimer then return end
    pendingTimer = true
    ns.after(delay or 5, function()
        pendingTimer = false
        Comm.broadcast(false)
    end)
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------

local function realmNoSpace() return (ns.realm():gsub("%s", "")) end

-- "Name-Realm" for a sender that may come without a realm.
local function fullName(sender)
    sender = str(sender)
    if sender:find("-", 1, true) then return sender end
    return sender .. "-" .. realmNoSpace()
end

local function isSelf(sender)
    local own = str((ns.call(UnitName, "player")))
    if own == "" then return false end
    local s = keyName(fullName(sender))
    return s == keyName(own .. "-" .. realmNoSpace())
        or s == keyName(own .. "-" .. ns.realm())
end

-- The roster member the sender is, or nil (not in the target guild's roster).
-- Name -> member, rebuilt only when the roster snapshot changes (GF-001-D14:
-- a scan per message cost about 1.7 ms at 1,000 members).
local byNameFor, byName
local function rosterMember(sender)
    local snap = ns.Roster.current()
    if not snap then return nil end
    if byNameFor ~= snap then
        byName = {}
        for _, m in ipairs(snap.members) do
            local n = keyName(m.name)
            if byName[n] == nil then byName[n] = m end
            local compact = keyName((m.name:gsub("%s", "")))
            if byName[compact] == nil then byName[compact] = m end
        end
        byNameFor = snap
    end
    return byName[keyName(fullName(sender))]
end

Comm.memberFor = rosterMember

local function peerTable()
    local db = ns.db
    if not db then return nil end
    if type(db.peers) ~= "table" then db.peers = {} end
    return db.peers
end

-- Latest data from a guild member, by roster name ("Name-Realm"), or nil.
function Comm.peerFor(name)
    local peers = peerTable()
    return peers and peers[keyName(name)] or nil
end

-- Since GF-001-D10 the records live in ns.Share (which rebuilds peers; the
-- site gets them as member.share at logout, GF-001-D14).
local function accept(sender, member, d)
    if d.capturedAt > ns.now() + 600 then return false, "future" end
    if d.level and (d.level < 1 or d.level > 200) then d.level = nil end
    local stored, why = ns.Share.fromV1(member, d)
    if not stored then return false, why end
    return true -- the roster page redraws through Share.onUpdate (coalesced)
end

-- Handle one CHAT_MSG_ADDON. Returns true when data was stored, else false, reason.
function Comm.onMessage(prefix, text, channel, sender)
    if prefix ~= Comm.PREFIX then return false, "prefix" end
    if channel ~= "GUILD" then return false, "channel" end
    if isSelf(sender) then return false, "self" end
    if ns.guildState() ~= "target" then return false, "other-guild" end
    local version, msgID, part, total, chunk = str(text):match("^([^~]+)~([^~]+)~(%d+)~(%d+)~(.*)$")
    if not version then return false, "malformed" end
    if version ~= Comm.VERSION then return false, "version" end
    part, total = tonumber(part), tonumber(total)
    if total < 1 or total > Comm.MAX_PARTS or part < 1 or part > total then return false, "malformed" end
    local member = rosterMember(sender)
    if not member then return false, "not-in-roster" end
    local body = chunk
    if total > 1 then
        local key = keyName(fullName(sender)) .. "~" .. msgID
        local now = ns.now()
        for k, p in pairs(partials) do
            if now - p.at > Comm.PART_TIMEOUT then partials[k] = nil end
        end
        local p = partials[key] or { parts = {}, total = total, at = now }
        partials[key] = p
        p.parts[part] = chunk
        for i = 1, total do if not p.parts[i] then return false, "partial" end end
        partials[key] = nil
        body = table.concat(p.parts, "", 1, total)
    end
    local d, why = Comm.decodeBody(body)
    if not d then return false, why end
    return accept(sender, member, d)
end
