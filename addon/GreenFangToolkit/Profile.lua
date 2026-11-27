-- Profile (GF-010, spec v2.0 §5.1, §5.2): role positioning (職責定位).
--
-- Each character sets a main role (t / h / d, or nil = 未設定; never
-- defaulted to 輸出) and the roles it can also fill (可支援, a set that
-- always holds the main role). Kept on this computer by character GUID
-- (GreenFangToolkitDB.profile.chars[guid]), never by name.
--
-- Shared with the guild through GFTKS (Share.lua) as group "J" (on by
-- default, spec §14) once the character has set anything. Value: "<main>.<can>", main = t / h / d / 0 (未設定),
-- can = the letters in t, h, d order, e.g. "t.td", "0.", "h.h". Turning
-- sharing off withdraws it: a tombstone (X) that relays carry, so everyone
-- drops the record. Members with nothing received are 未知.
--
-- Only this file decides what a role record means; other modules read it
-- through Profile.roles(guid) / Profile.ticketRoles(guid) (read-only).
-- Activity roles (an adventure signup's role) are separate data and are
-- never rewritten from here. Nothing here goes to GF Sync or the website.

local _, ns = ...
local str = ns.str

local Profile = {}
ns.Profile = Profile

-- "J" (職責): GF-009's manual listings use "L", its COLLECTION "C<n>".
Profile.GROUP = "J"
Profile.ROLES = { "t", "h", "d" }
Profile.ROLE_NAME = { t = "坦克", h = "治療", d = "輸出" }
Profile.UNSET_NAME, Profile.UNKNOWN_NAME = "未設定", "未知"

-- Roles each class usually takes (spec §5.2: 職業允許職責依已驗證 Forever 資料表).
-- GF-016: there is no verified Forever table, so nothing is blocked: a role
-- outside this list is only marked 「此職業通常不擔任」 (a dimmer icon and a
-- tooltip) and may still be chosen. Forever's own interface code does the
-- same (WoWBlzCode Forever/…/Blizzard_GroupFinder_VanillaStyle/Classic/
-- Blizzard_LFGVanilla_Listing.xml: UnitGetAvailableRoles("player") gives
-- "recommended" roles, the others get a cover and CLASS_ROLE_NOT_RECOMMENDED,
-- the check box stays usable; UnitRoleDocumentation.lua also has
-- AreClassRolesSoftSuggestions). For the own character the game's answer
-- (UnitGetAvailableRoles) wins when the client has it; others use this table.
-- Source of the table: the 1.x class design (talent trees and abilities);
-- NOT verified on Forever 16001, so every row is verified = false.
Profile.CLASS_ROLES_SOURCE = "建議用（不擋）：1.x 職業設計推測；本角色優先用遊戲 UnitGetAvailableRoles；未經 Forever 16001 實機驗證"
Profile.NOT_SUGGESTED_TIP = "此職業通常不擔任"
Profile.CLASS_ROLES = {
    WARRIOR = { t = true, d = true, verified = false },
    PALADIN = { t = true, h = true, d = true, verified = false },
    DRUID = { t = true, h = true, d = true, verified = false },
    PRIEST = { h = true, d = true, verified = false },
    SHAMAN = { h = true, d = true, verified = false },
    ROGUE = { d = true, verified = false },
    MAGE = { d = true, verified = false },
    WARLOCK = { d = true, verified = false },
    HUNTER = { d = true, verified = false },
}

-- May a character of this class take role r? Any real role (GF-016: the
-- class list is a suggestion, never a block).
function Profile.allowed(classToken, r)
    return Profile.ROLE_NAME[r] ~= nil
end

-- The game's own suggestion for this character: { t, h, d } or nil when the
-- client has no UnitGetAvailableRoles (or it fails / gives no booleans).
function Profile.gameSuggestion()
    if type(UnitGetAvailableRoles) ~= "function" then return nil end
    local okC, t, h, d = pcall(UnitGetAvailableRoles, "player")
    if not okC or type(t) ~= "boolean" or type(h) ~= "boolean" or type(d) ~= "boolean" then return nil end
    return { t = t, h = h, d = d }
end

-- Does this class usually take role r? own = the own character (asks the game first).
-- An unknown class: true (nothing to suggest against).
function Profile.suggested(classToken, r, own)
    if not Profile.ROLE_NAME[r] then return false end
    if own then
        local g = Profile.gameSuggestion()
        if g then return g[r] == true end
    end
    local row = Profile.CLASS_ROLES[str(classToken)]
    if not row then return true end
    return row[r] == true
end

---------------------------------------------------------------------------
-- Codec (pure)
---------------------------------------------------------------------------

local ORDER = { t = 1, h = 2, d = 3 }

-- { main = "t" | nil, can = { t = true, ... } } -> "t.td". The main role is
-- always put in can. nil for anything else.
function Profile.encode(p)
    if type(p) ~= "table" then return nil end
    local main = p.main
    if main ~= nil and not ORDER[main] then return nil end
    local letters = {}
    for _, r in ipairs(Profile.ROLES) do
        if (type(p.can) == "table" and p.can[r]) or r == main then letters[#letters + 1] = r end
    end
    return (main or "0") .. "." .. table.concat(letters)
end

function Profile.decode(v)
    if type(v) ~= "string" then return nil end
    local main, can = v:match("^([thd0])%.([thd]*)$")
    if not main then return nil end
    local set, last = {}, 0
    for i = 1, #can do
        local r = can:sub(i, i)
        if ORDER[r] <= last then return nil end -- sorted, no repeats
        last = ORDER[r]
        set[r] = true
    end
    if main == "0" then main = nil end
    if main and not set[main] then return nil end
    return { main = main, can = set }
end

---------------------------------------------------------------------------
-- Own settings (by GUID)
---------------------------------------------------------------------------

local function db()
    local d = ns.db
    if not d then return nil end
    if type(d.profile) ~= "table" then d.profile = { v = 1 } end
    if type(d.profile.chars) ~= "table" then d.profile.chars = {} end
    return d.profile
end

-- GF-FIX-B (review high-1): one game call (ns.selfGUID), not a full Data.player().
local function selfGuid()
    local g = ns.selfGUID and ns.selfGUID()
    return type(g) == "string" and g:match("^Player%-") and g or nil
end
Profile.selfGuid = selfGuid

-- This character's own entry (created on first use). nil before the GUID is known.
function Profile.own()
    local d, guid = db(), selfGuid()
    if not (d and guid) then return nil end
    local e = d.chars[guid]
    if type(e) ~= "table" then
        e = { main = nil, can = {}, share = true }
        d.chars[guid] = e
    end
    if type(e.can) ~= "table" then e.can = {} end
    if e.share == nil then e.share = true end
    if e.main ~= nil and not ORDER[e.main] then e.main = nil end
    return e
end

function Profile.ownClass() return str(ns.Sync and ns.Sync.player().classToken) end

local listeners = {}
function Profile.onChange(fn) listeners[#listeners + 1] = fn end
-- GF-FIX-B: goes up on every change of the own settings (a cache key, with
-- Share.version and Roster.version, for roles() and census()).
Profile.version = 0
local function changed()
    Profile.version = Profile.version + 1
    for _, fn in ipairs(listeners) do pcall(fn) end
end

-- Send what changed now (a withdrawal must not wait).
local function publish(now)
    if not (ns.Share and ns.Share.store()) then return end
    if now then
        local a = ns.Share.selfAuthor()
        if not a then return end
        for _, g in ipairs(ns.Share.observeOwn()) do
            if g == Profile.GROUP then ns.Share.sendRecord(a, g, true) end
        end
    else
        ns.Share.ownChanged()
    end
end

-- Set the main role (nil = 未設定). It joins 可支援. Any role may be chosen
-- (GF-016: a role the class does not usually take is only a hint on the page).
function Profile.setMain(r)
    local e = Profile.own()
    if not e then return false, "no-guid" end
    if r ~= nil and not ORDER[r] then return false, "role" end
    if e.main == r then return true end
    e.main = r
    if r then e.can[r] = true end
    e.set, e.at = true, ns.now()
    changed()
    publish(false)
    return true
end

-- Add or remove a role from 可支援. The main role cannot be removed.
function Profile.setCan(r, on)
    local e = Profile.own()
    if not e then return false, "no-guid" end
    if not ORDER[r] then return false, "role" end
    if not on and e.main == r then return false, "main" end
    if (e.can[r] == true) == (on and true or false) then return true end
    e.can[r] = on and true or nil
    e.set, e.at = true, ns.now()
    changed()
    publish(false)
    return true
end

-- Share with the guild, or withdraw (sent at once).
function Profile.setShare(on)
    local e = Profile.own()
    if not e then return false end
    on = on and true or false
    if e.share == on then return true end
    e.share = on
    changed()
    publish(true)
    return true
end

function Profile.sharing()
    local e = Profile.own()
    return e ~= nil and e.share == true
end

-- The own value for the share group: nil = not shared (withdrawn, or never
-- set: a character that never touched its roles sends nothing and stays 未知,
-- so the guild does not get one more record per member for nothing).
-- Every chosen role is sent (GF-016: the class list never removes one).
function Profile.ownValue()
    local e = Profile.own()
    if not (e and e.share and e.set) then return nil end
    local can = {}
    for r in pairs(e.can) do if ORDER[r] then can[r] = true end end
    return Profile.encode({ main = e.main, can = can })
end

---------------------------------------------------------------------------
-- Read-only API (other modules)
---------------------------------------------------------------------------

-- Roles of a character: { main = "t"|nil, can = { t = true, ... }, state, at, relayed }
-- state: "self" (this character), "shared" (received), "unset" (shared but
-- no main role), "unknown" (nothing received, or withdrawn). Never nil.
-- GF-FIX-B (review high-1): answers are kept while Share.version,
-- Roster.version, Profile.version, the guild key and the own GUID stay the
-- same; any change of those clears them, so a new record shows at once.
-- The returned tables are shared: read them, never change them.
local rolesCache = { key = nil, by = {} }
local function cacheKey()
    local gk = ns.Sync and ns.Sync.guildKey and ns.Sync.guildKey() or ""
    return string.format("%d|%d|%d|%s|%s", ns.Share and ns.Share.version or 0,
        ns.Roster and ns.Roster.version or 0, Profile.version, str(gk), str(selfGuid()))
end
Profile.cacheKey = cacheKey
local function rolesNow(guid)
    if guid ~= "" and guid == selfGuid() then
        local e = Profile.own()
        if e then
            local can = {}
            for r in pairs(e.can) do can[r] = true end
            if e.main then can[e.main] = true end
            return { main = e.main, can = can, state = e.main and "self" or "unset", own = true, at = e.at }
        end
    end
    local S = ns.Share
    local a = guid ~= "" and S and S.authorOf(guid)
    local rec = a and S.store() and S.get(a, Profile.GROUP)
    local d = rec and S.decoded(a, Profile.GROUP)
    if not d then return { can = {}, state = "unknown" } end
    return { main = d.main, can = d.can, state = d.main and "shared" or "unset", at = rec.t,
        relayed = not rec.fromAuthor }
end
Profile.rolesComputed = 0 -- answers worked out, not taken from the cache (tests, measurements)
function Profile.roles(guid)
    guid = str(guid)
    local key = cacheKey()
    if rolesCache.key ~= key then rolesCache.key, rolesCache.by = key, {} end
    local p = rolesCache.by[guid]
    if not p then
        p = rolesNow(guid)
        Profile.rolesComputed = Profile.rolesComputed + 1
        rolesCache.by[guid] = p
    end
    return p
end

-- For a worker ticket (AdventureUI, at integration): main, alt from the
-- role settings, or nil when the character has no main role (the ticket
-- keeps its own default). The ticket may always be changed by hand.
function Profile.ticketRoles(guid)
    local p = Profile.roles(guid or selfGuid())
    if not p.main then return nil end
    for _, r in ipairs(Profile.ROLES) do
        if r ~= p.main and p.can[r] then return p.main, r end
    end
    return p.main, nil
end

-- Does a member match a role filter? filter = { t = true, h = true, d = true,
-- unknown = true } (nil = everything). Any role in 可支援 counts; unknown
-- covers both 未知 and 未設定 with nothing to support.
function Profile.matches(guid, filter)
    if not filter then return true end
    local p = Profile.roles(guid)
    local any = false
    for r in pairs(p.can) do if filter[r] then return true end any = true end
    if not any and filter.unknown then return true end
    return false
end

-- 人力盤點 (spec §5.2): main roles, roles they can fill and online, over a
-- list of roster members. Every member is counted once in total.
-- { total, online, main = { t, h, d, unset, unknown }, can = { t, h, d } }
-- GF-FIX-B (review high-1): kept for the same list while nothing changed
-- (Profile.cacheKey: Share.version, Roster.version, own settings).
local censusCache = {}
function Profile.census(members)
    local key = cacheKey()
    if censusCache.list == members and censusCache.n == #(members or {}) and censusCache.key == key and members then
        return censusCache.c
    end
    local c = { total = 0, online = 0, main = { t = 0, h = 0, d = 0, unset = 0, unknown = 0 }, can = { t = 0, h = 0, d = 0 } }
    local seen = {}
    for _, m in ipairs(members or {}) do
        local key = str(m.guid) ~= "" and m.guid or ("name:" .. str(m.name))
        if not seen[key] then
            seen[key] = true
            c.total = c.total + 1
            if m.online then c.online = c.online + 1 end
            local p = Profile.roles(m.guid)
            if p.main then c.main[p.main] = c.main[p.main] + 1
            elseif p.state == "unknown" then c.main.unknown = c.main.unknown + 1
            else c.main.unset = c.main.unset + 1 end
            for _, r in ipairs(Profile.ROLES) do if p.can[r] then c.can[r] = c.can[r] + 1 end end
        end
    end
    censusCache.list, censusCache.n, censusCache.key, censusCache.c = members, #(members or {}), key, c
    return c
end

-- 近期 / 稍早 / 過期 for a record time (server seconds); "" for none.
Profile.RECENT, Profile.EARLIER = 3 * 86400, 30 * 86400
function Profile.ageText(t)
    if type(t) ~= "number" then return "" end
    local d = (ns.Share and ns.Share.serverNow() or ns.now()) - t
    if d < Profile.RECENT then return "近期" end
    if d < Profile.EARLIER then return "稍早" end
    return "過期"
end

---------------------------------------------------------------------------
-- 我的業務 (spec §5.1): my orders and adventures, read-only, from their own
-- modules (nothing copied). Each item: { kind = "order" | "adventure",
-- id, state, stateName, title, closed, sort }.
---------------------------------------------------------------------------

-- GF-FIX-B (spec v2.0 §3): the same names as OrdersUI.STATE_NAME.
Profile.ORDER_STATE = { waiting = "待受理", making = "已接單", checking = "待交付", deal = "已成交", cancel = "已取消" }

-- GF-UI-K: adventure states that are over (listed after the open ones, greyed).
Profile.ADV_ENDED = { done = true, ended = true, unfinished = true, cancel = true, closed = true }

local function orderTitle(v)
    local name = v.recipe and ns.Recipes and ns.Recipes.name and ns.Recipes.name(v.recipe)
    if str(name) ~= "" then return name end
    if v.skill and ns.Data.skillName then return ns.Data.skillName(nil, v.skill) or "委託" end
    return "委託"
end

local function adventureTitle(v)
    local AD = ns.AdventureData
    if v.dungeon and AD and AD.byId and AD.byId[v.dungeon] then return str(AD.byId[v.dungeon].name) end
    if v.zone then return str(v.zone) end
    return "冒險"
end

local function inTicket(v, me)
    if v.leader == me then return "leader" end
    for _, list in ipairs({ v.members or {}, v.waitlist or {}, v.pending or {} }) do
        for _, row in ipairs(list) do if row.a == me then return "member" end end
    end
    return nil
end

function Profile.myBusiness()
    local out = {}
    local S = ns.Share
    local me = S and S.selfAuthor()
    if not me then return out end
    if ns.Orders and ns.Orders.rowsFor then
        local ok, received, placed = pcall(ns.Orders.rowsFor, me, selfGuid())
        if ok then
            for _, list in ipairs({ placed or {}, received or {} }) do
                for _, row in ipairs(list) do
                    local v = row.view
                    -- Only orders I am in (an open guild order I could take is not mine yet).
                    if v and (v.customer == me or v.crafter == me) then
                        local closed = v.state == "deal" or v.state == "cancel"
                        out[#out + 1] = { kind = "order", id = v.id, state = v.state,
                            stateName = Profile.ORDER_STATE[v.state] or str(v.state),
                            role = v.customer == me and "下單" or "接單",
                            title = orderTitle(v), closed = closed, sort = v.created or 0,
                            attention = row.attention ~= nil }
                    end
                end
            end
        end
    end
    local Adv = ns.Adventure
    if Adv and Adv.all then
        local ok, all = pcall(Adv.all)
        if ok and type(all) == "table" then
            for _, v in pairs(all) do
                local how = inTicket(v, me)
                if how then
                    out[#out + 1] = { kind = "adventure", id = v.id, state = v.state,
                        stateName = (Adv.STATE_NAME and Adv.STATE_NAME[v.state]) or str(v.state),
                        role = how == "leader" and "開單" or "報名",
                        title = adventureTitle(v), closed = v.closed == true or Profile.ADV_ENDED[v.state] == true,
                        sort = v.created or 0 }
                end
            end
        end
    end
    table.sort(out, function(x, y)
        if x.closed ~= y.closed then return not x.closed end
        if x.sort ~= y.sort then return x.sort > y.sort end
        return str(x.id) < str(y.id)
    end)
    return out
end

-- Open the record where it lives (GF-016): its module's page, on the right
-- tab, scrolled to the record and lit (OrdersUI / AdventureUI focus(id), by
-- the record ID). When that page no longer lists the record (cleared, past
-- the keep time) nothing moves: false, "missing", and the personnel file
-- stays where it is (ProfileUI says so in the row's tooltip).
Profile.MISSING_TIP = "找不到原紀錄"
Profile.MISSING_DETAIL = "已清除或超過保留時間"
function Profile.openBusiness(item)
    if type(item) ~= "table" then return false, "item" end
    local page, ui = nil, nil
    if item.kind == "order" then page, ui = "orders", ns.OrdersUI
    elseif item.kind == "adventure" then page, ui = "adventure", ns.AdventureUI end
    if not page or not ns.Framework.get(page) then return false, "page" end
    if ui and type(ui.locate) == "function" then
        local okL, where = pcall(ui.locate, item.id)
        if not (okL and where) then return false, "missing" end
    end
    ns.Framework.open(page)
    if ui and type(ui.focus) == "function" then
        local okF, found = pcall(ui.focus, item.id)
        if not (okF and found) then return false, "missing" end
    end
    return true
end

-- 個人需求 (spec §5.1) comes from GF-009: it registers a provider here.
-- provider = { title = "個人需求", open = function() end, count = function() return n end }
Profile.needsProvider = nil
function Profile.setNeedsProvider(p)
    Profile.needsProvider = type(p) == "table" and p or nil
    changed()
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------

function Profile.diagText()
    local e = Profile.own()
    local mine
    if not e then
        mine = "本角色：未知"
    else
        local can = {}
        for _, r in ipairs(Profile.ROLES) do if e.can[r] or e.main == r then can[#can + 1] = Profile.ROLE_NAME[r] end end
        mine = string.format("本角色：主職責 %s｜可支援 %s｜%s", e.main and Profile.ROLE_NAME[e.main] or Profile.UNSET_NAME,
            #can > 0 and table.concat(can, "、") or "無", e.share and "分享給公會" or "不分享（已撤回）")
    end
    local got, tombs = 0, 0
    local S = ns.Share
    local s = S and S.store()
    if s then
        local me = S.selfAuthor()
        for a, groups in pairs(s.rec) do if a ~= me and groups[Profile.GROUP] then got = got + 1 end end
        for a, groups in pairs(s.tomb) do if a ~= me and groups[Profile.GROUP] then tombs = tombs + 1 end end
    end
    return string.format("%s｜收到職責 %d 位、撤回 %d 位｜職業職責表：%s", mine, got, tombs, Profile.CLASS_ROLES_SOURCE)
end

-- The share group (Share.registerGroup, shared with GF-009). local = true:
-- GF Sync leaves it out of member.share (not uploaded).
ns.Share.registerGroup({
    name = "ROLES",
    ["local"] = true,
    tomb = true,
    match = function(g) return g == Profile.GROUP end,
    encode = function(_, d) return Profile.encode(d) end,
    decode = function(_, v) return Profile.decode(v) end,
    ownGroups = { Profile.GROUP },
    own = function() return Profile.ownValue() end,
})
