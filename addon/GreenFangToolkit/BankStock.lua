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
-- The guild's side: one Share record group KS per custodian (GUILD only,
-- local = true: GF Sync does not upload it). Shown only for an enabled
-- custodian on the list in force who is in the guild roster, only the kinds
-- the list gives, and only a snapshot not older than the custodian's entry
-- (revoked, re-appointed or kinds changed: the old snapshot is gone).
--
-- Wire value (format 1), 7 fields joined by ";":
--   1;<bags>;<bank>;<unseen>;<more>;<bagItems>;<bankItems>
--   bags   ""  not in scope | "1" read | "?" in scope, could not be read
--   bank   ""  not in scope | "-" in scope, never seen | b36(server time seen)
--   unseen bank tabs in scope not seen yet, one b36 digit each (6..e)
--   more   b36 count of item entries left out (Stock.MAX_ITEMS)
--   items  b36(itemID) "." b36(qty), joined by ",", by itemID
-- No slot, no bag number of an item, nothing outside the scope.
-- API evidence: C_Container fields itemID / stackCount / isBound and
-- Enum.BagIndex 0-5 / 6-14 are from the owner's 0.16.12 probe; the rest is
-- offline only (not checked in game).

local _, ns = ...

local Stock = {}
ns.BankStock = Stock

Stock.GROUP = "KS"
Stock.FORMAT = "1"
Stock.MAX_ITEMS = 150      -- item entries sent at most (bags + bank)
Stock.MAX_QTY = 99999      -- per entry (more is sent as this)
Stock.MAX_MORE = 2000      -- entries left out, as told
Stock.MAX_VALUE = 2048     -- bytes; a longer value is refused before parsing
Stock.RESTAMP = 30 * 60    -- an unchanged bank tab keeps its time this long
Stock.EMPTY = "1;;;;0;;"
Stock.NOT_SEEN = "還沒看過"
Stock.CONFIRM_TEXT = "會把勾選範圍內的物品與數量分享給公會，要開始分享嗎？"
Stock.SCOPE_NOTE = "勾選的範圍會分享給公會：物品與數量"
Stock.SOURCE_NAME = { bags = "背包", bank = "銀行" }

local stats = { scans = 0, bagReads = 0, bankReads = 0, slots = 0, published = 0, confirmed = 0, resent = 0,
    combat = 0, asked = 0, ignored = 0, rejected = 0, truncated = 0, lastMs = nil }
Stock.stats = stats

local function S() return ns.Share end
local function B() return ns.Bank end
local function Sup() return ns.Supply end
local b36, unb36 = ns.Share.b36, ns.Share.unb36

---------------------------------------------------------------------------
-- Saved data: GreenFangToolkitDB.bank.stock[<my GUID>] =
--   { consent = true | false | nil, sentAt = server time,
--     bank = { [tab] = { t = server time, n = { [itemID] = qty } } } }
-- Only tabs in my scope are kept; everything goes when sharing stops.
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
-- The wire value
---------------------------------------------------------------------------

local function listOf(map)
    local ids = {}
    for id, q in pairs(map) do if q > 0 then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
end

-- d = { bags = nil | "1" | "?", bank = nil | "-" | t, unseen = { tabs },
--       bagItems = { [id] = qty }, bankItems = { [id] = qty } }.
-- Entries beyond Stock.MAX_ITEMS (by itemID, bags first) are left out and counted.
function Stock.encode(d)
    local entries = {}
    for _, src in ipairs({ "bags", "bank" }) do
        local map = d[src == "bags" and "bagItems" or "bankItems"] or {}
        for _, id in ipairs(listOf(map)) do entries[#entries + 1] = { src = src, id = id, q = map[id] } end
    end
    table.sort(entries, function(x, y) if x.id ~= y.id then return x.id < y.id end return x.src < y.src end)
    local more = math.max(0, #entries - Stock.MAX_ITEMS)
    local out = { bags = {}, bank = {} }
    for i = 1, math.min(#entries, Stock.MAX_ITEMS) do
        local e = entries[i]
        local list = out[e.src]
        list[#list + 1] = e
    end
    local function join(list)
        table.sort(list, function(x, y) return x.id < y.id end)
        local parts = {}
        for _, e in ipairs(list) do parts[#parts + 1] = b36(e.id) .. "." .. b36(math.min(Stock.MAX_QTY, math.floor(e.q))) end
        return table.concat(parts, ",")
    end
    local unseen = {}
    local tabs = {}
    for _, t in ipairs(d.unseen or {}) do tabs[#tabs + 1] = t end
    table.sort(tabs)
    for _, t in ipairs(tabs) do unseen[#unseen + 1] = b36(t) end
    local bank = d.bank == nil and "" or (d.bank == "-" and "-" or b36(d.bank))
    return table.concat({ Stock.FORMAT, d.bags or "", bank, table.concat(unseen), b36(math.min(more, Stock.MAX_MORE)),
        join(out.bags), join(out.bank) }, ";"), more
end

local TABS = {}
for _, it in ipairs(ns.Bank.SCOPE.bank) do TABS[it[1]] = true end

local function bad() stats.rejected = stats.rejected + 1; return nil end

local function decodeItems(s, room)
    local map, n = {}, 0
    if s == "" then return map, 0 end
    for item in (s .. ","):gmatch("([^,]*),") do
        local id, q = item:match("^([0-9a-z]+)%.([0-9a-z]+)$")
        id, q = id and unb36(id), q and unb36(q)
        if not id or not q or id <= 0 or q <= 0 or q > Stock.MAX_QTY or map[id] then return nil end
        n = n + 1
        if n > room then return nil end
        map[id] = q
    end
    return map, n
end

-- Value -> { bags, bank, unseen, more, bagItems, bankItems, empty } or nil.
function Stock.decode(_, v)
    if type(v) ~= "string" or #v > Stock.MAX_VALUE then return bad() end
    local f, bags, bank, unseen, more, bi, ki = v:match("^(%d+);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*)$")
    if f ~= Stock.FORMAT then return bad() end
    if bags ~= "" and bags ~= "1" and bags ~= "?" then return bad() end
    local d = { bags = bags ~= "" and bags or nil, unseen = {}, more = unb36(more) }
    if not d.more or d.more > Stock.MAX_MORE then return bad() end
    if bank == "-" then d.bank = "-"
    elseif bank ~= "" then
        local t = unb36(bank)
        if not t or t < S().EPOCH or t > S().serverNow() + S().FUTURE then return bad() end
        d.bank = t
    end
    local seenTab = {}
    for ch in unseen:gmatch(".") do
        local t = unb36(ch)
        if not t or not TABS[t] or seenTab[t] or not d.bank then return bad() end
        seenTab[t] = true
        d.unseen[#d.unseen + 1] = t
    end
    local bagItems, n1 = decodeItems(bi, Stock.MAX_ITEMS)
    if not bagItems then return bad() end
    local bankItems = decodeItems(ki, Stock.MAX_ITEMS - n1)
    if not bankItems then return bad() end
    if (d.bags ~= "1" and next(bagItems)) or (type(d.bank) ~= "number" and next(bankItems)) then return bad() end
    d.bagItems, d.bankItems = bagItems, bankItems
    d.empty = d.bags == nil and d.bank == nil
    return d
end

---------------------------------------------------------------------------
-- Scan and publish (my own snapshot)
---------------------------------------------------------------------------

-- My snapshot now (reads my scope's bags; the bank as kept).
function Stock.build(sc)
    local m = Stock.mine()
    local d = { unseen = {}, bagItems = {}, bankItems = {} }
    if #sc.bags > 0 then
        local list = bagList(sc)
        local counts, slots = Sup().readContainers(true, list)
        stats.bagReads = stats.bagReads + 1
        if counts then
            stats.slots = stats.slots + (slots or 0)
            d.bags, d.bagItems = "1", freeOf(counts)
        else
            d.bags = "?"
        end
    end
    if #sc.bank > 0 then
        local oldest
        for _, tab in ipairs(sc.bank) do
            local e = m and m.bank[tab]
            if e then
                for id, q in pairs(e.n) do d.bankItems[id] = (d.bankItems[id] or 0) + q end
                if not oldest or e.t < oldest then oldest = e.t end
            else
                d.unseen[#d.unseen + 1] = tab
            end
        end
        d.bank = oldest or "-"
    end
    return d
end

-- Store (and later send) my value when it changed; an unchanged one only
-- moves its time now and then (Supply's rule: CONFIRM_EVERY / RESEND_EVERY).
-- floor: my entry's epoch on the list; a snapshot older than it is not shown
-- by the others, so an unchanged one gets a new time and goes out at once.
local function publish(value, floor)
    local a = S().selfAuthor()
    if not a or not S().store() then return "no-store" end
    local rec = S().get(a, Stock.GROUP)
    local now = S().serverNow()
    local m = Stock.mine()
    if rec and rec.v == value then
        local behind = floor ~= nil and rec.t < floor
        if not behind and now - rec.t < Sup().CONFIRM_EVERY then return "same" end
        S().ownRecord(Stock.GROUP, value)
        stats.confirmed = stats.confirmed + 1
        if m and (behind or now - (m.sentAt or 0) >= Sup().RESEND_EVERY) then
            m.sentAt = now
            if S().sendRecord(a, Stock.GROUP, true) then stats.resent = stats.resent + 1 end
        end
        return "confirm"
    end
    if not rec and value == Stock.EMPTY then return "none" end
    local r = S().ownRecord(Stock.GROUP, value)
    if r == "stored" then
        stats.published = stats.published + 1
        if m then m.sentAt = now end
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

function Stock.scan()
    if ns.inCombat() then pending = true; stats.combat = stats.combat + 1; return "combat" end
    pending = false
    local st, sc = Stock.myState()
    lastSig = sigOf(st, sc)
    if st == "wait" then return "wait" end
    local m = Stock.mine()
    if st ~= "on" then
        -- Not sharing: nothing kept, an empty snapshot so the others drop mine.
        if m then m.bank = {} end
        return publish(Stock.EMPTY)
    end
    -- Tabs that left the scope: their copy goes.
    local keep = {}
    for _, t in ipairs(sc.bank) do keep[t] = true end
    for t in pairs(m.bank) do if not keep[t] then m.bank[t] = nil end end
    stats.scans = stats.scans + 1
    local t0 = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local value, more = Stock.encode(Stock.build(sc))
    if t0 then stats.lastMs = debugprofilestop() - t0 end
    stats.truncated = more
    local r = publish(value, myEpoch())
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
        if st == "on" and #sc.bags > 0 then Stock.scan() end
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

-- Per custodian: { a, member, name, own, rec, d, t, bags = { [id] = q },
-- bank = { [id] = q }, bankT, unseen, more, state }. state: "data" | "none"
-- (no snapshot) | "noscope" | "unseen" (bank never seen, nothing else).
local viewCache = {}
function Stock.invalidate() viewCache = {} end

function Stock.holders()
    local cur = B().current()
    local key = tostring(S().version) .. "|" .. tostring(cur)
    if viewCache.key == key then return viewCache.holders, viewCache.cur end
    local holders = {}
    local me = S().selfAuthor()
    local on = {}
    if cur.state == "ok" then
        for _, e in ipairs(cur.list.entries) do
            local m = S().memberFor(e.a)
            if e.enabled and (m or e.a == me) then
                on[e.a] = true
                local h = { a = e.a, member = m, own = e.a == me, state = "none", bags = {}, bank = {}, unseen = {}, more = 0 }
                h.name = m and ns.shortName(m.name) or ns.shortName(ns.str(ns.Data.player().name))
                local rec = S().get(e.a, Stock.GROUP)
                local d = rec and S().decoded(e.a, Stock.GROUP)
                if rec and d and rec.t >= e.epoch then
                    local giveBags = e.kinds:find("b", 1, true) ~= nil
                    local giveBank = e.kinds:find("k", 1, true) ~= nil
                    h.t = rec.t
                    h.more = d.more
                    if giveBags and d.bags == "1" then h.bags = d.bagItems end
                    h.bagsUnread = giveBags and d.bags == "?"
                    if giveBank and type(d.bank) == "number" then h.bank, h.bankT = d.bankItems, d.bank end
                    if giveBank and d.bank ~= nil then h.unseen = d.unseen; h.bankUnseen = d.bank == "-" end
                    if next(h.bags) or next(h.bank) then h.state = "data"
                    elseif (giveBags and d.bags) or (giveBank and type(d.bank) == "number") then h.state = "empty"
                    elseif giveBank and d.bank == "-" then h.state = "unseen"
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
    viewCache = { key = key, holders = holders, cur = cur }
    return holders, cur
end

-- Rows: one per item { itemID, total, holders = { { h, bags, bank } }, t }
-- (t = the oldest time among the places it is in). The same custodian's
-- bags and bank are two places; nobody is counted twice.
function Stock.rows()
    local holders = Stock.holders()
    if viewCache.rows then return viewCache.rows, viewCache.why end
    local byId, rows = {}, {}
    for _, h in ipairs(holders) do
        for _, src in ipairs({ "bags", "bank" }) do
            local t = src == "bags" and h.t or h.bankT
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

-- The rows whose item name has the text (case-insensitive); "" = all.
function Stock.search(q)
    local rows = Stock.rows()
    q = ns.str(q):lower()
    if q == "" then return rows end
    local out = {}
    for _, r in ipairs(rows) do
        local name = Sup().itemName(r.itemID)
        if name and name:lower():find(q, 1, true) then out[#out + 1] = r end
    end
    return out
end

-- 「阿綠 背包 5、銀行 20｜阿牙 背包 3」
function Stock.whereText(r)
    local parts = {}
    for _, p in ipairs(r.places) do
        local s = {}
        if p.bags > 0 then s[#s + 1] = "背包 " .. p.bags end
        if p.bank > 0 then s[#s + 1] = "銀行 " .. p.bank end
        parts[#parts + 1] = p.h.name .. " " .. table.concat(s, "、")
    end
    return table.concat(parts, "｜")
end

-- Whom 聯絡 whispers: the one holding the most who is not me (online first).
function Stock.contactEntry(r)
    local best
    for _, p in ipairs(r.places) do
        if not p.h.own and p.h.member then
            local on = p.h.member.online == true
            if not best or (on and not best.on) then best = { p = p, on = on } end
        end
    end
    if not best then return nil end
    return { member = best.p.h.member, own = false, itemID = r.itemID, direction = "stock" }
end

-- My own snapshot as the others see it (the 「我分享了什麼」 line).
function Stock.mineText()
    local st = Stock.myState()
    if st == "off" or st == "wait" then return "" end
    if st == "noscope" then return "還沒勾選公產範圍" end
    if st ~= "on" then return "沒有分享庫存" end
    local a = S().selfAuthor()
    local d = a and S().decoded(a, Stock.GROUP)
    if not d or d.empty then return "還沒分享" end
    local nb, nk = 0, 0
    for _ in pairs(d.bagItems) do nb = nb + 1 end
    for _ in pairs(d.bankItems) do nk = nk + 1 end
    local parts = {}
    if d.bags == "1" then parts[#parts + 1] = "背包 " .. nb .. " 種" elseif d.bags == "?" then parts[#parts + 1] = "背包讀不到" end
    if type(d.bank) == "number" then parts[#parts + 1] = "銀行 " .. nk .. " 種（" .. ns.Recipes.agoText(d.bank) .. "看到）"
    elseif d.bank == "-" then parts[#parts + 1] = "銀行" .. Stock.NOT_SEEN .. "（請打開銀行）" end
    if #d.unseen > 0 and d.bank ~= "-" then parts[#parts + 1] = #d.unseen .. " 個分頁" .. Stock.NOT_SEEN end
    if d.more > 0 then parts[#parts + 1] = "還有 " .. d.more .. " 項沒列出" end
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
    return string.format("庫存：%d 種物品、%d 位保管人有資料（共 %d 位）｜我：%s｜這次登入：掃描 %d、讀銀行 %d、更新 %d、確認 %d、重送 %d、戰鬥中略過 %d、拒收 %d、非保管人的資料不顯示 %d 份%s%s",
        #rows, with, #holders, Stock.STATE_NAME[(Stock.myState())] or "?", stats.scans, stats.bankReads,
        stats.published, stats.confirmed, stats.resent, stats.combat, stats.rejected, stats.ignored,
        stats.truncated > 0 and string.format("、超過上限沒列出 %d 項", stats.truncated) or "",
        stats.lastMs and string.format("｜上次掃描 %.1f 毫秒", stats.lastMs) or "")
end

function Stock.resetSession()
    for k, v in pairs(stats) do if type(v) == "number" then stats[k] = 0 end end
    stats.lastMs = nil
    pending, lastSig = false, nil
    viewCache = {}
end

---------------------------------------------------------------------------
-- The share group. local = true: GF Sync does not upload it.
---------------------------------------------------------------------------

ns.Share.registerGroup({
    name = "CUSTODY_STOCK",
    ["local"] = true,
    match = function(g) return g == Stock.GROUP end,
    encode = function(_, d) return (Stock.encode(d)) end,
    decode = Stock.decode,
})

-- Only a change of someone's KS record redraws the page.
local ksSig = {}
ns.Share.onUpdate(function(a)
    if a == nil then return end
    local rec = S().get(a, Stock.GROUP)
    local sig = rec and (tostring(rec.h) .. "|" .. tostring(rec.t)) or false
    local old = ksSig[a]
    if old == nil then old = false end
    if old == sig then return end
    ksSig[a] = sig
    if Stock.onChanged then Stock.onChanged() end
end)

-- The page (BankUI loads before this file) is drawn again only on a change.
Stock.onChanged = function() if ns.BankUI and ns.BankUI.stockChanged then ns.BankUI.stockChanged() end end
