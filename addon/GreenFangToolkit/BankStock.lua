-- BankStock (GF-012-B, spec v2.0 §8.1 stock and §8.2 the stock row): 臨時黑箱
-- phase 2, the stock only. Not here: requests, approvals, hand-outs, quotas,
-- reservations, mail (phase 3, owner has not decided).
--
-- The custodian's side: only an enabled custodian on the list in force, only
-- the containers ticked in 我的公產範圍 (Bank.scopeInForce: a kind the guild
-- master did not give is never read), and only after the custodian said yes
-- once (the confirm box). Every other slot is never read, kept or sent.
-- Reading uses Supply's reader (Supply.readContainers, the same bag / bank
-- events through Supply.watch; no second scan, no new event). The bags are
-- read when they change; the bank only while it is open, kept per tab with
-- the time it was seen (a tab never seen is 還沒看過, never 0). Bound items
-- are left out (they cannot be given). Nothing is done in combat.
--
-- The guild's side (GF-012-C, owner 2026-11-28: no 150-item limit): one
-- small head record KS plus one record per source, so only the source that
-- changed goes out again: KSB (the scope's bags) and KS6 .. KS14 (one per
-- bank tab in the scope). All GUILD only, local = true (GF Sync does not
-- upload them). Shown only for an enabled custodian on the list in force who
-- is in the guild roster, only the kinds the list gives, only records not
-- older than the custodian's entry (revoked, re-appointed or kinds changed:
-- the old ones are gone), and only the parts the head lists.
--
-- Wire values (format 2):
--   KS   head: 2;<bags>;<tabs>
--        bags  ""  not in scope | "1" read | "?" in scope, could not be read
--        tabs  each bank tab in the scope: one b36 digit (6..e), followed by
--              "-" when it was never seen (還沒看過, never 0)
--   KSB  bags: 2;;<more>;<items>          (seen = the record's own time)
--   KS<n> tab: 2;<b36 seen time>;<more>;<items>
--        items  b36(itemID) "." b36(qty), joined by ",", by itemID
--        more   b36 entries left out (only past Stock.MAX_ENTRIES, which is
--               more than a bag set or a tab can hold)
--   An emptied part (left the scope, sharing off, revoked): 2;;0;
-- No slot, no bag number of an item, nothing outside the scope. Format 1
-- (0.16.15, one KS of at most 150 items) is refused, never stored.
-- API evidence: C_Container fields itemID / stackCount / isBound and
-- Enum.BagIndex 0-5 / 6-14 are from the owner's 0.16.12 probe; the rest is
-- offline only (not checked in game).

local _, ns = ...

local Stock = {}
ns.BankStock = Stock

Stock.GROUP = "KS"         -- the head
Stock.BAGS_GROUP = "KSB"   -- the bags part
Stock.FORMAT = "2"
Stock.MAX_ENTRIES = 240    -- item entries per part (a full bag set is about 200 slots, a tab 98)
Stock.MAX_QTY = 99999      -- per entry (more is sent as this)
Stock.MAX_MORE = 2000      -- entries left out, as told
Stock.MAX_VALUE = 3000     -- bytes of one part; a longer value is refused before parsing
Stock.MAX_HEAD = 64        -- bytes of the head
Stock.RESTAMP = 30 * 60    -- an unchanged bank tab keeps its time this long
Stock.EMPTY = "2;;"        -- the head with nothing in scope
Stock.EMPTY_PART = "2;;0;" -- a part that is no longer shared
Stock.NOT_SEEN = "還沒看過"
Stock.CONFIRM_TEXT = "會把勾選範圍內的物品與數量分享給公會，要開始分享嗎？"
Stock.SCOPE_NOTE = "勾選的範圍會分享給公會：物品與數量"
Stock.SOURCE_NAME = { bags = "背包", bank = "銀行" }

local stats = { scans = 0, bagReads = 0, bankReads = 0, slots = 0, published = 0, confirmed = 0, resent = 0,
    combat = 0, asked = 0, ignored = 0, rejected = 0, truncated = 0, lastMs = nil, parts = 0 }
Stock.stats = stats

local function S() return ns.Share end
local function B() return ns.Bank end
local function Sup() return ns.Supply end
local b36, unb36 = ns.Share.b36, ns.Share.unb36

local TABS = {}
for _, it in ipairs(ns.Bank.SCOPE.bank) do TABS[it[1]] = true end

-- The record group of a bank tab (KS6 .. KS14) and back.
function Stock.tabGroup(tab) return "KS" .. tab end
function Stock.groupTab(g)
    local n = type(g) == "string" and tonumber(g:match("^KS(%d+)$")) or nil
    return (n and TABS[n]) and n or nil
end
-- Every part group of mine that may exist (bags and all tabs).
local function allParts()
    local out = { Stock.BAGS_GROUP }
    for _, it in ipairs(ns.Bank.SCOPE.bank) do out[#out + 1] = Stock.tabGroup(it[1]) end
    return out
end

---------------------------------------------------------------------------
-- Saved data: GreenFangToolkitDB.bank.stock[<my GUID>] =
--   { consent = true | false | nil, sent = { [group] = server time },
--     bank = { [tab] = { t = server time, n = { [itemID] = qty } } } }
-- Only tabs in my scope are kept; everything goes when sharing stops.
-- (0.16.15's sentAt is not read any more.)
---------------------------------------------------------------------------

function Stock.mine()
    local db = ns.db
    if not db or not B().scope() then return nil end
    local guid = ns.Data.player().guid
    if type(db.bank.stock) ~= "table" then db.bank.stock = {} end
    local m = db.bank.stock[guid]
    if type(m) ~= "table" then m = {}; db.bank.stock[guid] = m end
    if m.consent ~= nil and type(m.consent) ~= "boolean" then m.consent = nil end
    if type(m.bank) ~= "table" then m.bank = {} end
    for tab, e in pairs(m.bank) do
        if type(tab) ~= "number" or type(e) ~= "table" or type(e.t) ~= "number" or type(e.n) ~= "table" then m.bank[tab] = nil end
    end
    if type(m.sent) ~= "table" then m.sent = {} end
    for g, t in pairs(m.sent) do if type(g) ~= "string" or type(t) ~= "number" then m.sent[g] = nil end end
    m.sentAt = nil
    return m
end

---------------------------------------------------------------------------
-- My state: "wait" (the list is not known yet), "off" (not a custodian),
-- "noscope" (nothing ticked), "ask" (not said yes yet), "declined", "on".
---------------------------------------------------------------------------

function Stock.myState()
    local Bk = B()
    if Bk.current().state == "unknown" then return "wait" end
    local me = S().selfAuthor()
    if not me or not (Bk.isCustodian(me)) then return "off" end
    local sc = Bk.scopeInForce()
    if #sc.bags == 0 and #sc.bank == 0 then return "noscope", sc end
    local m = Stock.mine()
    if not m then return "wait" end
    if m.consent == true then return "on", sc end
    if m.consent == false then return "declined", sc end
    return "ask", sc
end

-- The containers of the scope the client really has (0-4, the reagent bag
-- only when Enum names it; bank tabs only those Supply.bankBags names).
local function bagList(sc)
    local ok = {}
    for i = 0, Sup().BAGS do ok[i] = true end
    local r = Sup().reagentBag()
    if r then ok[r] = true end
    local out = {}
    for _, i in ipairs(sc.bags) do if ok[i] then out[#out + 1] = i end end
    return out
end
local function bankAllowed()
    local set = {}
    for _, i in ipairs(Sup().bankBags()) do set[i] = true end
    return set
end

local function freeOf(counts)
    local n = {}
    for id, c in pairs(counts or {}) do if (c.free or 0) > 0 then n[id] = c.free end end
    return n
end

local function sameMap(x, y)
    for k, v in pairs(x) do if y[k] ~= v then return false end end
    for k in pairs(y) do if x[k] == nil then return false end end
    return true
end

-- Read the open bank (my scope's tabs only). A tab that shows no slots now
-- keeps what was seen before (never read as 0). Returns true when kept.
function Stock.readBank()
    if not Sup().open.bank or ns.inCombat() then return false end
    local st, sc = Stock.myState()
    if st ~= "on" or #sc.bank == 0 then return false end
    local allowed = bankAllowed()
    local m = Stock.mine()
    local now = S().serverNow()
    local seen = false
    for _, tab in ipairs(sc.bank) do
        if allowed[tab] then
            local counts, slots = Sup().readContainers(true, { tab })
            if counts and (slots or 0) > 0 then
                stats.slots = stats.slots + slots
                local n = freeOf(counts)
                local old = m.bank[tab]
                if old and sameMap(old.n, n) and now - old.t < Stock.RESTAMP then
                    -- unchanged and seen lately: the time stays (nothing new to send)
                else
                    m.bank[tab] = { t = now, n = n }
                end
                seen = true
            end
        end
    end
    if seen then stats.bankReads = stats.bankReads + 1 end
    return seen
end

---------------------------------------------------------------------------
-- The wire values
---------------------------------------------------------------------------

local function listOf(map)
    local ids = {}
    for id, q in pairs(map or {}) do if q > 0 then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end

-- The head. d = { bags = nil | "1" | "?", tabs = { { tab = n, seen = bool } } }.
function Stock.encodeHead(d)
    local tabs = {}
    for _, e in ipairs(d.tabs or {}) do tabs[#tabs + 1] = e end
    table.sort(tabs, function(x, y) return x.tab < y.tab end)
    local parts = {}
    for _, e in ipairs(tabs) do parts[#parts + 1] = b36(e.tab) .. (e.seen and "" or "-") end
    return table.concat({ Stock.FORMAT, d.bags or "", table.concat(parts) }, ";")
end

-- A part: items = { [itemID] = qty }, seen = server time or nil (bags).
-- Entries past Stock.MAX_ENTRIES (largest item IDs) are left out and counted.
function Stock.encodePart(items, seen)
    local ids = listOf(items)
    local more = math.max(0, #ids - Stock.MAX_ENTRIES)
    local parts = {}
    for i = 1, math.min(#ids, Stock.MAX_ENTRIES) do
        local id = ids[i]
        parts[#parts + 1] = b36(id) .. "." .. b36(math.min(Stock.MAX_QTY, math.floor(items[id])))
    end
    return table.concat({ Stock.FORMAT, seen and b36(seen) or "", b36(math.min(more, Stock.MAX_MORE)),
        table.concat(parts, ",") }, ";"), more
end

local function bad() stats.rejected = stats.rejected + 1; return nil end

local function decodeItems(s)
    local map, n = {}, 0
    if s == "" then return map, 0 end
    for item in (s .. ","):gmatch("([^,]*),") do
        local id, q = item:match("^([0-9a-z]+)%.([0-9a-z]+)$")
        id, q = id and unb36(id), q and unb36(q)
        if not id or not q or id <= 0 or q <= 0 or q > Stock.MAX_QTY or map[id] then return nil end
        n = n + 1
        if n > Stock.MAX_ENTRIES then return nil end
        map[id] = q
    end
    return map, n
end

-- Head value -> { bags, tabs = { [tab] = true (seen) | false (never seen) },
-- order = { tab, ... }, empty } or nil.
function Stock.decodeHead(v)
    if type(v) ~= "string" or #v > Stock.MAX_HEAD then return bad() end
    local f, bags, tabs = v:match("^(%d+);([^;]*);([^;]*)$")
    if f ~= Stock.FORMAT then return bad() end
    if bags ~= "" and bags ~= "1" and bags ~= "?" then return bad() end
    local d = { bags = bags ~= "" and bags or nil, tabs = {}, order = {} }
    local used = 0
    for ch, mark in tabs:gmatch("([0-9a-z])(%-?)") do
        local t = unb36(ch)
        if not t or not TABS[t] or d.tabs[t] ~= nil then return bad() end
        d.tabs[t] = mark == ""
        d.order[#d.order + 1] = t
        used = used + 1 + #mark
    end
    if used ~= #tabs then return bad() end -- anything else in it
    d.empty = d.bags == nil and #d.order == 0
    return d
end

-- Part value -> { seen = time or nil, more, items, n } or nil. A tab part
-- with items must say when it was seen; a bags part never does.
function Stock.decodePart(g, v)
    if type(v) ~= "string" or #v > Stock.MAX_VALUE then return bad() end
    local f, seen, more, items = v:match("^(%d+);([^;]*);([^;]*);([^;]*)$")
    if f ~= Stock.FORMAT then return bad() end
    local d = { more = unb36(more) }
    if not d.more or d.more > Stock.MAX_MORE then return bad() end
    if seen ~= "" then
        local t = unb36(seen)
        if not t or t < S().EPOCH or t > S().serverNow() + S().FUTURE then return bad() end
        if g == Stock.BAGS_GROUP then return bad() end
        d.seen = t
    end
    local map, n = decodeItems(items)
    if not map then return bad() end
    if g ~= Stock.BAGS_GROUP and n > 0 and not d.seen then return bad() end
    d.items, d.n = map, n
    d.empty = n == 0 and d.more == 0
    return d
end

function Stock.decode(g, v)
    if g == Stock.GROUP then return Stock.decodeHead(v) end
    if g == Stock.BAGS_GROUP or Stock.groupTab(g) then return Stock.decodePart(g, v) end
    return bad()
end

---------------------------------------------------------------------------
-- Scan and publish (my own snapshot)
---------------------------------------------------------------------------

-- My snapshot now: the head and the value of each part in the scope.
-- bagsOnly: a bag change (the bank tabs are not encoded again).
-- Returns head, parts = { [group] = value }, more (entries left out).
function Stock.build(sc, bagsOnly)
    local m = Stock.mine()
    local head = { tabs = {} }
    local parts, more = {}, 0
    if #sc.bags > 0 then
        local list = bagList(sc)
        local counts, slots = Sup().readContainers(true, list)
        stats.bagReads = stats.bagReads + 1
        if counts then
            stats.slots = stats.slots + (slots or 0)
            head.bags = "1"
            local v, n = Stock.encodePart(freeOf(counts))
            parts[Stock.BAGS_GROUP], more = v, more + n
        else
            head.bags = "?"
        end
    end
    for _, tab in ipairs(sc.bank) do
        local e = m and m.bank[tab]
        head.tabs[#head.tabs + 1] = { tab = tab, seen = e ~= nil }
        if not bagsOnly then
            local v, n = Stock.encodePart(e and e.n or {}, e and e.t or nil)
            parts[Stock.tabGroup(tab)], more = e and v or Stock.EMPTY_PART, more + n
        end
    end
    return Stock.encodeHead(head), parts, more
end

-- Store (and later send) one of my values when it changed; an unchanged one
-- only moves its time now and then (Supply's rule: CONFIRM_EVERY /
-- RESEND_EVERY). floor: my entry's epoch on the list; a record older than it
-- is not shown by the others, so an unchanged one gets a new time and goes
-- out at once. Each group on its own: only what changed goes out.
local function publish(g, value, floor)
    local a = S().selfAuthor()
    if not a or not S().store() then return "no-store" end
    local rec = S().get(a, g)
    local now = S().serverNow()
    local m = Stock.mine()
    if rec and rec.v == value then
        local behind = floor ~= nil and rec.t < floor
        if not behind and now - rec.t < Sup().CONFIRM_EVERY then return "same" end
        S().ownRecord(g, value)
        stats.confirmed = stats.confirmed + 1
        if m and (behind or now - (m.sent[g] or 0) >= Sup().RESEND_EVERY) then
            m.sent[g] = now
            if S().sendRecord(a, g, true) then stats.resent = stats.resent + 1 end
        end
        return "confirm"
    end
    if not rec and (value == Stock.EMPTY or value == Stock.EMPTY_PART) then return "none" end
    local r = S().ownRecord(g, value)
    if r == "stored" then
        stats.published = stats.published + 1
        if m then m.sent[g] = now end
    end
    return r
end
Stock.publish = publish

local pending = false
local lastSig

-- My entry's epoch on the list in force (nil when I am not on it).
local function myEpoch()
    local me = S().selfAuthor()
    if not me then return nil end
    local on, e = B().isCustodian(me)
    return on and e and e.epoch or nil
end

-- What decides my snapshot apart from the containers' contents.
local function sigOf(st, sc)
    local s = st .. "|" .. tostring(myEpoch())
    if not sc then return s end
    return s .. "|" .. table.concat(sc.bags, ",") .. "|" .. table.concat(sc.bank, ",")
end

-- Empty every part of mine that exists and is not in keep (a set of groups).
local function emptyOthers(keep)
    local a = S().selfAuthor()
    if not a then return end
    for _, g in ipairs(allParts()) do
        if not keep[g] and S().get(a, g) then publish(g, Stock.EMPTY_PART) end
    end
end

-- kind "bags": only the bags changed (the head and KSB are looked at).
function Stock.scan(kind)
    if ns.inCombat() then pending = true; stats.combat = stats.combat + 1; return "combat" end
    pending = false
    local st, sc = Stock.myState()
    local sig = sigOf(st, sc)
    local bagsOnly = kind == "bags" and sig == lastSig
    lastSig = sig
    if st == "wait" then return "wait" end
    local m = Stock.mine()
    if st ~= "on" then
        -- Not sharing: nothing kept, empty values so the others drop mine.
        if m then m.bank = {} end
        emptyOthers({})
        return publish(Stock.GROUP, Stock.EMPTY)
    end
    -- Tabs that left the scope: their copy goes.
    local keep = {}
    for _, t in ipairs(sc.bank) do keep[t] = true end
    for t in pairs(m.bank) do if not keep[t] then m.bank[t] = nil end end
    stats.scans = stats.scans + 1
    local t0 = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local head, parts, more = Stock.build(sc, bagsOnly)
    local floor = myEpoch()
    local n = 0
    for _, g in ipairs(allParts()) do
        if parts[g] then n = n + 1; publish(g, parts[g], floor) end
    end
    if not bagsOnly then
        local inScope = {}
        if #sc.bags > 0 then inScope[Stock.BAGS_GROUP] = true end
        for _, t in ipairs(sc.bank) do inScope[Stock.tabGroup(t)] = true end
        emptyOthers(inScope)
        stats.truncated = more
        stats.parts = n
    end
    local r = publish(Stock.GROUP, head, floor)
    if t0 then stats.lastMs = debugprofilestop() - t0 end
    if Stock.onChanged then Stock.onChanged() end
    return r
end

-- The list, the roster or the scope may have changed: scan only when my
-- state or scope did (a roster update alone reads nothing).
function Stock.check()
    if ns.inCombat() then pending = true; return "combat" end
    local st, sc = Stock.myState()
    if sigOf(st, sc) == lastSig then return "same" end
    return Stock.scan()
end
function Stock.resetScan() pending, lastSig = false, nil end
function Stock.soon() ns.coalesce("bank-stock", 0, Stock.check) end
-- GUILD_ROSTER_UPDATE: looked at only while my state waits for the roster
-- (a roster update otherwise reads nothing more; GF-FIX-C counts the rows read).
function Stock.rosterChanged()
    if lastSig and lastSig:find("^wait") then Stock.soon() end
end

-- An emptied scope asks again the next time something is ticked.
function Stock.scopeChanged()
    local sc = B().scopeInForce()
    local m = Stock.mine()
    if m and #sc.bags == 0 and #sc.bank == 0 then m.consent = nil end
    Stock.soon()
end

-- The confirm box (one per question; 確定 = yes, anything else = no).
function Stock.ask()
    local st = Stock.myState()
    if st ~= "ask" and st ~= "declined" then return false end
    if ns.inCombat() then return false end
    stats.asked = stats.asked + 1
    ns.Widgets.confirm(Stock.CONFIRM_TEXT, function() Stock.setConsent(true) end,
        function() Stock.setConsent(false) end)
    return true
end
-- Asked when the page shows or a box is ticked, never by itself at login.
function Stock.askIfNeeded()
    if Stock.myState() == "ask" then return Stock.ask() end
    return false
end

function Stock.setConsent(on)
    local m = Stock.mine()
    if not m then return nil end
    m.consent = on and true or false
    if not on then m.bank = {} end
    Stock.scan()
    if Stock.onChanged then Stock.onChanged() end
    return m.consent
end
-- The page's switch: on asks first, off stops at once.
function Stock.toggle(on)
    if on then return Stock.ask() end
    Stock.setConsent(false)
    return true
end

Sup().watch(function(kind)
    if kind == "bags" then
        -- While the bank is open the same BAG_UPDATE_DELAYED also tells
        -- "bank" (Supply.readSoon), which scans once for both.
        if Sup().open.bank then return end
        local st, sc = Stock.myState()
        if st == "on" and #sc.bags > 0 then Stock.scan("bags") end
    elseif kind == "bank" then
        if Stock.myState() == "on" then Stock.readBank(); Stock.scan() end
    elseif kind == "combat" then
        if pending then Stock.scan() end
    elseif kind == "start" then
        Stock.check()
    end
end)

---------------------------------------------------------------------------
-- Everybody's stock (read side)
---------------------------------------------------------------------------

-- Bumped when someone's stock records change (Share.onUpdate below), so the
-- page's lists are built again only then (GF-012-C: a location or recipe
-- record of somebody does not rebuild the stock).
Stock.dataVersion = 0

-- A part of author a, decoded, when it is not older than floor.
local function partOf(a, g, floor)
    local rec = S().get(a, g)
    if not rec or rec.t < floor then return nil end
    return S().decoded(a, g), rec
end

-- Per custodian: { a, member, name, own, t, bags = { [id] = q },
-- bank = { [id] = q } (all tabs added), tabs = { [tab] = { t, n } }, bankT
-- (the oldest tab seen), unseen = { tabs }, waiting = { groups announced by
-- the head but not here yet }, more, state }. state: "data" | "none" (no
-- head) | "noscope" | "unseen" (bank never seen, nothing else) | "empty".
local viewCache = {}
function Stock.invalidate() viewCache = {} end

local function viewKey()
    local cur = B().current()
    return tostring(Stock.dataVersion) .. "|" .. tostring(cur) .. "|" .. tostring(ns.Roster.version), cur
end

function Stock.holders()
    local key, cur = viewKey()
    if viewCache.key == key then return viewCache.holders, viewCache.cur end
    local holders = {}
    local me = S().selfAuthor()
    local on = {}
    if cur.state == "ok" then
        for _, e in ipairs(cur.list.entries) do
            local m = S().memberFor(e.a)
            if e.enabled and (m or e.a == me) then
                on[e.a] = true
                local h = { a = e.a, member = m, own = e.a == me, state = "none", bags = {}, bank = {}, tabs = {},
                    unseen = {}, waiting = {}, more = 0 }
                h.name = m and ns.shortName(m.name) or ns.shortName(ns.str(ns.Data.player().name))
                local head, rec = partOf(e.a, Stock.GROUP, e.epoch)
                if head then
                    local giveBags = e.kinds:find("b", 1, true) ~= nil
                    local giveBank = e.kinds:find("k", 1, true) ~= nil
                    h.t = rec.t
                    local anyScope = false
                    if giveBags and head.bags then
                        anyScope = true
                        h.bagsUnread = head.bags == "?"
                        if head.bags == "1" then
                            local p, prec = partOf(e.a, Stock.BAGS_GROUP, e.epoch)
                            if p then h.bags, h.bagsT, h.more = p.items, prec.t, h.more + p.more
                            else h.waiting[#h.waiting + 1] = Stock.BAGS_GROUP end
                        end
                    end
                    if giveBank then
                        for _, tab in ipairs(head.order) do
                            anyScope = true
                            if not head.tabs[tab] then
                                h.unseen[#h.unseen + 1] = tab
                            else
                                local p = partOf(e.a, Stock.tabGroup(tab), e.epoch)
                                if p and p.seen then
                                    h.tabs[tab] = { t = p.seen, n = p.items }
                                    h.more = h.more + p.more
                                    for id, q in pairs(p.items) do h.bank[id] = (h.bank[id] or 0) + q end
                                    if not h.bankT or p.seen < h.bankT then h.bankT = p.seen end
                                else
                                    h.waiting[#h.waiting + 1] = Stock.tabGroup(tab)
                                end
                            end
                        end
                        h.bankUnseen = #head.order > 0 and #h.unseen == #head.order
                    end
                    local seenAny = (giveBags and head.bags == "1") or next(h.tabs) ~= nil
                    if next(h.bags) or next(h.bank) then h.state = "data"
                    elseif seenAny or (giveBags and head.bags == "?") then h.state = "empty"
                    elseif #h.unseen > 0 then h.state = "unseen"
                    elseif anyScope then h.state = "empty"
                    else h.state = "noscope" end
                end
                holders[#holders + 1] = h
            end
        end
    end
    -- Records of anybody who is not an enabled custodian now: not shown.
    local ignored = 0
    for a, groups in pairs(S().store() and S().store().rec or {}) do
        if groups[Stock.GROUP] and not on[a] then ignored = ignored + 1 end
    end
    stats.ignored = ignored
    table.sort(holders, function(x, y) return x.a < y.a end)
    viewCache = { key = key, holders = holders, cur = cur, filtered = {} }
    return holders, cur
end

-- Rows: one per item { itemID, total, places = { { h, bags, bank } }, t }
-- (t = the oldest time among the places it is in). The same custodian's
-- bags and bank are two places; nobody is counted twice.
function Stock.rows()
    local holders = Stock.holders()
    if viewCache.rows then return viewCache.rows, viewCache.why end
    local byId, rows = {}, {}
    for _, h in ipairs(holders) do
        for _, src in ipairs({ "bags", "bank" }) do
            local t = src == "bags" and (h.bagsT or h.t) or h.bankT
            for id, q in pairs(h[src]) do
                local r = byId[id]
                if not r then r = { itemID = id, total = 0, places = {}, byHolder = {} }; byId[id] = r; rows[#rows + 1] = r end
                local p = r.byHolder[h.a]
                if not p then p = { h = h, bags = 0, bank = 0 }; r.byHolder[h.a] = p; r.places[#r.places + 1] = p end
                p[src] = q
                r.total = r.total + q
                if t and (not r.t or t < r.t) then r.t = t end
            end
        end
    end
    for _, r in ipairs(rows) do
        table.sort(r.places, function(x, y)
            local qx, qy = x.bags + x.bank, y.bags + y.bank
            if qx ~= qy then return qx > qy end
            return x.h.a < y.h.a
        end)
        r.byHolder = nil
    end
    table.sort(rows, function(x, y) if x.total ~= y.total then return x.total > y.total end return x.itemID < y.itemID end)
    -- Why the list is empty (the most advanced custodian decides).
    local rank = { none = 1, noscope = 2, unseen = 3, empty = 4, data = 5 }
    local best = #holders == 0 and "nobody" or "none"
    for _, h in ipairs(holders) do if rank[h.state] > (rank[best] or 0) then best = h.state end end
    viewCache.rows, viewCache.why = rows, best
    return rows, best
end

---------------------------------------------------------------------------
-- GF-012-C: filters (name, item class, custodian, online only). The result
-- is kept until the data or a filter changes.
---------------------------------------------------------------------------

-- The game's item class of an item (C_Item.GetItemInfoInstant: no server
-- request), else what the item cache knows; nil while unknown. Kept once known.
local classMemo = {}
function Stock.classOf(itemID)
    local c = classMemo[itemID]
    if c then return c end
    if type(C_Item) == "table" and type(C_Item.GetItemInfoInstant) == "function" then
        local okCall, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, itemID)
        c = okCall and tonumber(classID) or nil
    end
    if not c and ns.SupplyListings then
        local info = ns.SupplyListings.itemInfo(itemID, true)
        c = info and info.classID or nil
    end
    if c then classMemo[itemID] = c end
    return c
end
Stock.OTHER_CLASS = -1 -- items whose class is not known (yet): 其他
Stock.UNKNOWN_AGAIN = 2 -- seconds: a list with a name / class not loaded yet is built again after this

local function isOnline(h) return h.own or (h.member ~= nil and h.member.online == true) end
Stock.isOnline = isOnline

-- opts = { q = name text, class = classID or nil, holder = a or nil,
-- online = true }. Rows whose places are cut by holder / online are copies
-- with only those places (their total is those places' sum).
function Stock.filter(opts)
    opts = opts or {}
    local rows = Stock.rows()
    local q = ns.str(opts.q):lower()
    local key = q .. "|" .. tostring(opts.class) .. "|" .. tostring(opts.holder) .. "|" .. tostring(opts.online == true)
    local memo = viewCache.filtered
    local at = memo[key .. "|at"]
    if memo[key] and (not at or ns.now() - at < Stock.UNKNOWN_AGAIN) then
        stats.filterHits = (stats.filterHits or 0) + 1
        return memo[key]
    end
    stats.filterRuns = (stats.filterRuns or 0) + 1
    local out, unknown = {}, false
    for _, r in ipairs(rows) do
        local keep = true
        if opts.class then
            local c = Stock.classOf(r.itemID)
            if not c then unknown = true end
            keep = (c or Stock.OTHER_CLASS) == opts.class
        end
        if keep and q ~= "" then
            local name = Sup().itemName(r.itemID)
            if not name then unknown = true end
            keep = name ~= nil and name:lower():find(q, 1, true) ~= nil
        end
        if keep and (opts.holder or opts.online) then
            local places, total = {}, 0
            for _, p in ipairs(r.places) do
                if (not opts.holder or p.h.a == opts.holder) and (not opts.online or isOnline(p.h)) then
                    places[#places + 1] = p
                    total = total + p.bags + p.bank
                end
            end
            if #places == 0 then keep = false
            elseif #places < #r.places then
                r = { itemID = r.itemID, total = total, places = places, t = r.t, base = r }
            end
        end
        if keep then out[#out + 1] = r end
    end
    -- Cut rows count only their places: the most first again.
    if opts.holder or opts.online then
        table.sort(out, function(x, y) if x.total ~= y.total then return x.total > y.total end return x.itemID < y.itemID end)
    end
    -- An item whose name or class is not loaded yet is looked at again, at
    -- most every Stock.UNKNOWN_AGAIN seconds (a redraw in between reuses this).
    memo[key] = out
    if unknown then memo[key .. "|at"] = ns.now() end
    return out
end

-- The rows whose item name has the text (case-insensitive); "" = all.
function Stock.search(q) return Stock.filter({ q = q }) end

-- The classes of the items in stock now: { { value = classID, text } }, by name.
function Stock.classOptions()
    local rows = Stock.rows()
    local at = viewCache.classesAt
    if viewCache.classes and (not at or ns.now() - at < Stock.UNKNOWN_AGAIN) then return viewCache.classes end
    local seen, out, unknown = {}, {}, false
    local L = ns.SupplyListings
    for _, r in ipairs(rows) do
        local c = Stock.classOf(r.itemID)
        if not c then unknown = true end
        c = c or Stock.OTHER_CLASS
        if not seen[c] then
            seen[c] = true
            out[#out + 1] = { value = c, text = c == Stock.OTHER_CLASS and "其他" or (L and L.className(c)) or "其他" }
        end
    end
    table.sort(out, function(x, y) if x.text ~= y.text then return x.text < y.text end return x.value < y.value end)
    viewCache.classes, viewCache.classesAt = out, unknown and ns.now() or nil
    return out
end

---------------------------------------------------------------------------
-- Texts and 聯絡
---------------------------------------------------------------------------

-- 「阿綠 背包 5、銀行 20」
function Stock.placeText(p)
    local s = {}
    if p.bags > 0 then s[#s + 1] = "背包 " .. p.bags end
    if p.bank > 0 then s[#s + 1] = "銀行 " .. p.bank end
    return p.h.name .. " " .. table.concat(s, "、")
end
-- 「阿綠 背包 5、銀行 20｜阿牙 背包 3」
function Stock.whereText(r)
    local parts = {}
    for _, p in ipairs(r.places) do parts[#parts + 1] = Stock.placeText(p) end
    return table.concat(parts, "｜")
end
-- 「阿綠」 or 「阿綠 等 3 位」 (the first place: the most).
function Stock.whoText(r)
    local first = r.places[1]
    if not first then return "" end
    if #r.places == 1 then return first.h.name end
    return first.h.name .. " 等 " .. #r.places .. " 位"
end

-- GF-012-C: whom 聯絡 may whisper, best first: online first, then the most,
-- then by id; my own place last (shown grey, never chosen). Each: { p, qty,
-- online, own, name, entry (what Supply.contact takes) }.
function Stock.contactChoices(r)
    local out = {}
    for _, p in ipairs(r.places) do
        local h = p.h
        out[#out + 1] = { p = p, qty = p.bags + p.bank, online = isOnline(h), own = h.own, name = h.name,
            entry = { member = h.member, own = h.own, itemID = r.itemID, direction = "stock" } }
    end
    table.sort(out, function(x, y)
        if x.own ~= y.own then return y.own end
        if x.online ~= y.online then return x.online end
        if x.qty ~= y.qty then return x.qty > y.qty end
        return x.p.h.a < y.p.h.a
    end)
    return out
end
-- The default: the first one that is not me and is in the roster.
function Stock.contactEntry(r)
    for _, c in ipairs(Stock.contactChoices(r)) do
        if not c.own and c.entry.member then return c.entry, c end
    end
    return nil
end
-- How many others 聯絡 could whisper (1 = at once, more = the menu).
function Stock.contactCount(r)
    local n = 0
    for _, c in ipairs(Stock.contactChoices(r)) do if not c.own and c.entry.member then n = n + 1 end end
    return n
end

-- My own snapshot as the others see it (the 「我分享了什麼」 line).
function Stock.mineText()
    local st = Stock.myState()
    if st == "off" or st == "wait" then return "" end
    if st == "noscope" then return "還沒勾選公產範圍" end
    if st ~= "on" then return "沒有分享庫存" end
    local a = S().selfAuthor()
    local head = a and S().decoded(a, Stock.GROUP)
    if not head or head.empty then return "還沒分享" end
    local parts = {}
    local more = 0
    if head.bags == "1" then
        local p = S().decoded(a, Stock.BAGS_GROUP)
        parts[#parts + 1] = "背包 " .. (p and p.n or 0) .. " 種"
        more = more + (p and p.more or 0)
    elseif head.bags == "?" then parts[#parts + 1] = "背包讀不到" end
    local seen, nk, oldest, unseen = 0, 0, nil, 0
    for _, tab in ipairs(head.order) do
        if head.tabs[tab] then
            local p = S().decoded(a, Stock.tabGroup(tab))
            if p then
                seen = seen + 1
                nk = nk + p.n
                more = more + p.more
                if p.seen and (not oldest or p.seen < oldest) then oldest = p.seen end
            end
        else
            unseen = unseen + 1
        end
    end
    if seen > 0 then parts[#parts + 1] = "銀行 " .. nk .. " 種（" .. (oldest and ns.Recipes.agoText(oldest) or "") .. "看到）"
    elseif #head.order > 0 then parts[#parts + 1] = "銀行" .. Stock.NOT_SEEN .. "（請打開銀行）" end
    if unseen > 0 and seen > 0 then parts[#parts + 1] = unseen .. " 個分頁" .. Stock.NOT_SEEN end
    if more > 0 then parts[#parts + 1] = "還有 " .. more .. " 項沒列出" end
    return "我分享了：" .. table.concat(parts, "、")
end

---------------------------------------------------------------------------
-- Diagnostics (同步與診斷)
---------------------------------------------------------------------------

Stock.STATE_NAME = { wait = "等名單", off = "不是保管人", noscope = "未勾範圍", ask = "還沒確認", declined = "已關閉", on = "分享中" }
function Stock.diagText()
    local rows = Stock.rows()
    local holders = Stock.holders()
    local with = 0
    for _, h in ipairs(holders) do if h.state == "data" or h.state == "empty" then with = with + 1 end end
    return string.format("庫存：%d 種物品、%d 位保管人有資料（共 %d 位）｜我：%s（%d 份）｜這次登入：掃描 %d、讀銀行 %d、更新 %d、確認 %d、重送 %d、戰鬥中略過 %d、拒收 %d、非保管人的資料不顯示 %d 份%s%s",
        #rows, with, #holders, Stock.STATE_NAME[(Stock.myState())] or "?", stats.parts, stats.scans, stats.bankReads,
        stats.published, stats.confirmed, stats.resent, stats.combat, stats.rejected, stats.ignored,
        stats.truncated > 0 and string.format("、超過上限沒列出 %d 項", stats.truncated) or "",
        stats.lastMs and string.format("｜上次掃描 %.1f 毫秒", stats.lastMs) or "")
end

function Stock.resetSession()
    for k, v in pairs(stats) do if type(v) == "number" then stats[k] = 0 end end
    stats.lastMs = nil
    Stock.resetScan()
    viewCache = {}
end

---------------------------------------------------------------------------
-- The share groups (KS, KSB, KS6 .. KS14). local = true: GF Sync does not
-- upload them.
---------------------------------------------------------------------------

local function isStockGroup(g) return g == Stock.GROUP or g == Stock.BAGS_GROUP or Stock.groupTab(g) ~= nil end
Stock.isGroup = isStockGroup
local STOCK_GROUPS = { Stock.GROUP }
for _, g in ipairs(allParts()) do STOCK_GROUPS[#STOCK_GROUPS + 1] = g end
Stock.GROUPS = STOCK_GROUPS

ns.Share.registerGroup({
    name = "CUSTODY_STOCK",
    ["local"] = true,
    match = isStockGroup,
    encode = function(_, v) return type(v) == "string" and v or nil end,
    decode = Stock.decode,
})

-- Only a change of someone's stock records redraws the page.
local ksSig = {}
ns.Share.onUpdate(function(a)
    if a == nil then return end
    local parts = {}
    for _, g in ipairs(STOCK_GROUPS) do
        local rec = S().get(a, g)
        if rec then parts[#parts + 1] = g .. ":" .. tostring(rec.h) .. ":" .. tostring(rec.t) end
    end
    local sig = table.concat(parts, "|")
    if (ksSig[a] or "") == sig then return end
    ksSig[a] = sig
    Stock.dataVersion = Stock.dataVersion + 1
    if Stock.onChanged then Stock.onChanged() end
end)

-- The page (BankUI loads before this file) is drawn again only on a change.
Stock.onChanged = function()
    if ns.BankUI and ns.BankUI.stockChanged then ns.BankUI.stockChanged() end
    -- GF-012-C: 調貨看板 lists the stock too.
    if ns.SupplyUI and ns.SupplyUI.refreshSoon then ns.SupplyUI.refreshSoon() end
end
