-- Delivery (GF-006-B, spec §7): did the crafter really hand over the goods?
--
-- R-7.1: only with TWO pieces of evidence does an order close by itself —
-- the game says the trade completed (or the mail item was taken), AND the
-- bags really changed by that amount. One piece only: back to 待驗收 with a
-- reminder for the customer. No evidence: nothing happens. Better one more
-- click by the customer than a wrong 成交.
--
-- Every judgement is logged (last 20, R-7.6) with a reason code, shown only
-- in 同步與診斷. Functions not verified on 16001 have a fallback (R-7.5): the
-- part that cannot work turns manual, the rest keeps working.

local _, ns = ...
local str = ns.str

local Delivery = {}
ns.Delivery = Delivery

Delivery.TRADE_SLOTS = 6          -- slot 7 ("will not be traded", enchanting) never counts (R-7.2)
Delivery.SEND_SLOTS = 12
Delivery.RECEIVE_SLOTS = 16
Delivery.SNAPSHOT_KEEP = 600      -- R-7.2: a snapshot after both accepted, kept 10 minutes
Delivery.CLOSE_WAIT = 2           -- seconds to wait for "trade complete" after TRADE_CLOSED
Delivery.BAG_WAIT = 3             -- seconds to wait for the bags after "complete"
Delivery.LOG_MAX = 20

local function O() return ns.Orders end
local function S() return ns.Share end

---------------------------------------------------------------------------
-- Pure core (offline tests)
---------------------------------------------------------------------------

function Delivery.itemIDOf(link)
    if type(link) == "number" then return link end
    local id = str(link):match("item:(%d+)")
    return id and tonumber(id) or nil
end

-- Sum of item counts in a slot list { { id, n } } -> { [id] = n }.
function Delivery.sum(slots)
    local out = {}
    for _, s in ipairs(slots or {}) do
        if s.id and (s.n or 0) > 0 then out[s.id] = (out[s.id] or 0) + s.n end
    end
    return out
end

-- Give `count` of one item to the open orders for it (oldest first, R-7.2):
-- fill one before the next. orders = views (oldest first), done(v) = how
-- many already arrived. Returns { { view, n } }, leftover.
function Delivery.allocate(orders, itemID, count, done)
    local out = {}
    for _, v in ipairs(orders) do
        if count <= 0 then break end
        if v.item == itemID and v.skill ~= O().ENCHANTING then
            local room = v.qty - (done(v) or 0)
            if room > 0 then
                local n = math.min(room, count)
                out[#out + 1] = { view = v, n = n }
                count = count - n
            end
        end
    end
    return out, count
end

-- Judge one finished trade. t = { complete = bool, given = { [id] = n } (my
-- side), received = { [id] = n } (their side), before = { [id] = count },
-- after = { [id] = count } }. Returns a code:
--   "cancelled"  no "trade complete" (cancelled, too far, combat, ...)
--   "ok"         complete and every involved bag count changed by exactly that much
--   "bag-delta"  complete, but some count does not match (bags full, loot, mail at the same time)
--   "no-bags"    complete, but the bag counts could not be read
function Delivery.judgeTrade(t)
    if not t.complete then return "cancelled" end
    if not (t.before and t.after) then return "no-bags" end
    for id, n in pairs(t.received or {}) do
        if t.before[id] == nil or t.after[id] == nil then return "no-bags" end
        if t.after[id] - t.before[id] ~= n then return "bag-delta" end
    end
    for id, n in pairs(t.given or {}) do
        if t.before[id] == nil or t.after[id] == nil then return "no-bags" end
        if t.before[id] - t.after[id] ~= n then return "bag-delta" end
    end
    return "ok"
end

-- Judge taking a mail attachment. m = { sender (author or nil), returned,
-- id, n (count in the attachment), before, after }. "ok", "bag-delta",
-- "not-loaded" (sender or item unknown yet: wait, never guess), "returned".
function Delivery.judgeMail(m)
    if not m.sender or not m.id or not m.n then return "not-loaded" end
    if m.returned then return "returned" end
    if m.before == nil or m.after == nil then return "no-bags" end
    if m.after - m.before ~= m.n then return "bag-delta" end
    return "ok"
end

---------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------

function Delivery.log(kind, code, detail)
    local o = O().local_()
    table.insert(o.trades, 1, { at = ns.now(), kind = kind, code = code, detail = detail })
    while #o.trades > Delivery.LOG_MAX do table.remove(o.trades) end
end

---------------------------------------------------------------------------
-- Features (R-7.5): what works on this client
---------------------------------------------------------------------------

local function fn(x) return type(x) == "function" end
local function countOf(id)
    local C = C_Item
    if C and fn(C.GetItemCount) then return ns.num((ns.call(C.GetItemCount, id))) end
    if fn(GetItemCount) then return ns.num((ns.call(GetItemCount, id))) end
    return nil
end
Delivery.countOf = countOf

-- Review 2-2 / R-7.5: "可用" only after this client really produced the
-- evidence once (a trade-complete message matched, a mail sent with items, a
-- take judged by the bags). Until then: "未確認"; missing functions: "改成手動".
function Delivery.verified() local o = O().local_(); if type(o.verified) ~= "table" then o.verified = {} end; return o.verified end
function Delivery.markVerified(kind) Delivery.verified()[kind] = ns.now() end
function Delivery.status(kind)
    if not Delivery.features()[kind] then return "manual" end
    return Delivery.verified()[kind] and "ok" or "unconfirmed"
end

function Delivery.features()
    local f = {}
    f.trade = fn(GetTradePlayerItemLink) and fn(GetTradeTargetItemLink) and fn(GetTradePlayerItemInfo)
        and fn(GetTradeTargetItemInfo) and type(ERR_TRADE_COMPLETE) == "string"
        and (fn(UnitName)) and countOf(0) ~= nil
    f.mailSend = fn(hooksecurefunc) and fn(SendMail) and fn(GetSendMailItem)
    f.mailTake = fn(hooksecurefunc) and fn(GetInboxHeaderInfo) and fn(GetInboxItem)
        and (fn(TakeInboxItem) or fn(AutoLootMailItem)) and countOf(0) ~= nil
    return f
end

---------------------------------------------------------------------------
-- Applying a result to my half
---------------------------------------------------------------------------

local function me() return S().selfAuthor() end

-- Items moved between me and author other: received from them, given to them.
-- how = "trade" or "mail". sure = both pieces of evidence (R-7.1).
function Delivery.apply(other, received, given, how, sure)
    local my = me()
    local orders = O().between(my, other)
    if #orders == 0 then return 0 end
    local touched = 0
    -- I am the customer: what I received.
    local mine = {}
    for _, v in ipairs(orders) do if v.customer == my then mine[#mine + 1] = v end end
    for id, n in pairs(received or {}) do
        local allocs = Delivery.allocate(mine, id, n, function(v) return v.got end)
        for _, a in ipairs(allocs) do
            touched = touched + 1
            if sure then
                O().customer(a.view.id, "got", a.n)
                if a.view.got + a.n >= a.view.qty then O().customer(a.view.id, "deal", how) end
            else
                O().customer(a.view.id, "unsure")
            end
        end
    end
    -- I am the crafter: what I gave.
    local jobs = {}
    for _, v in ipairs(orders) do if v.crafter == my then jobs[#jobs + 1] = v end end
    for id, n in pairs(given or {}) do
        local allocs = Delivery.allocate(jobs, id, n, function(v) return v.gave end)
        for _, a in ipairs(allocs) do
            touched = touched + 1
            if sure then
                O().crafter(a.view, "gave", a.n)
                if a.view.gave + a.n >= a.view.qty then
                    O().crafter(a.view, how == "mail" and "mailed" or "delivered", how)
                end
            else
                O().local_().unsure[a.view.id] = ns.now()
            end
        end
    end
    -- Materials from the customer, money (display only).
    return touched
end

---------------------------------------------------------------------------
-- Trade (R-7.2)
---------------------------------------------------------------------------

local trade -- current trade: { other, member, snap = { mine = {}, theirs = {} }, money }

local function partner()
    local name, realm = ns.call(UnitName, "NPC")
    name = str(name)
    if name == "" then return nil end
    local full = (str(realm) ~= "" and (name .. "-" .. realm)) or name
    local m = ns.Comm.memberFor(full) or ns.Comm.memberFor(name)
    local a = m and S().authorOf(m.guid)
    return a, m
end

local function readSlots(getLink, getInfo)
    local list = {}
    for i = 1, Delivery.TRADE_SLOTS do
        local link = ns.call(getLink, i)
        local id = Delivery.itemIDOf(link)
        if id then
            local _, _, n = ns.call(getInfo, i)
            list[#list + 1] = { id = id, n = ns.num(n) or 1 }
        end
    end
    return list
end

function Delivery.snapshot()
    if not trade then return end
    trade.snap = {
        mine = readSlots(GetTradePlayerItemLink, GetTradePlayerItemInfo),
        theirs = readSlots(GetTradeTargetItemLink, GetTradeTargetItemInfo),
        money = fn(GetTargetTradeMoney) and ns.num((ns.call(GetTargetTradeMoney))) or 0,
    }
    -- Review 2-2: do not depend on TRADE_ACCEPT_UPDATE(1,1) arriving; the bags
    -- before the trade are read every time the contents change.
    local before = {}
    for _, s in ipairs(trade.snap.mine) do before[s.id] = countOf(s.id) end
    for _, s in ipairs(trade.snap.theirs) do before[s.id] = countOf(s.id) end
    if #trade.snap.mine + #trade.snap.theirs > 0 then
        trade.final = { mine = trade.snap.mine, theirs = trade.snap.theirs, before = before }
    else
        trade.final = nil
    end
    if ns.OrdersUI and ns.OrdersUI.tradeChanged then ns.OrdersUI.tradeChanged() end
end

function Delivery.current() return trade end

function Delivery.onTradeShow()
    trade = nil
    if not Delivery.features().trade then return end
    local a, m = partner()
    if not a then return end
    if #O().between(me(), a) == 0 then return end
    trade = { other = a, member = m, snap = { mine = {}, theirs = {}, money = 0 } }
    Delivery.snapshot()
end

function Delivery.onAccept(playerAccepted, targetAccepted)
    if not trade then return end
    Delivery.snapshot()
    if trade.final and (ns.num(playerAccepted) == 1 or ns.num(targetAccepted) == 1) then
        -- Survives a disconnect or /reload (R-7.2): turned into reminders at login.
        O().local_().pendingTrade = { at = ns.now(), other = trade.other,
            mine = trade.snap.mine, theirs = trade.snap.theirs }
    end
end

local function finish(complete)
    local t = trade
    trade = nil
    O().local_().pendingTrade = nil
    if not (t and t.final) then
        if t then Delivery.log("trade", "cancelled") end
        return "cancelled"
    end
    local given, received = Delivery.sum(t.final.mine), Delivery.sum(t.final.theirs)
    local after = {}
    for id in pairs(t.final.before) do after[id] = countOf(id) end
    local code = Delivery.judgeTrade({ complete = complete, given = given, received = received,
        before = t.final.before, after = after })
    if code == "cancelled" then
        Delivery.log("trade", code)
        return code
    end
    local touched = Delivery.apply(t.other, received, given, "trade", code == "ok")
    if (t.snap.money or 0) > 0 then
        for _, v in ipairs(O().between(me(), t.other)) do
            if v.customer == t.other and v.crafter == me() and t.snap.money >= (v.fee or 0) then
                O().crafter(v, "paid")
                break
            end
        end
    end
    Delivery.log("trade", touched > 0 and code or "no-order", t.other)
    return code
end
Delivery.finish = finish

local completeAt
function Delivery.onInfoMessage(a1, a2)
    if not trade then return end
    -- Review 2-2 B: newer clients pass (messageType, message), older ones just the message.
    local complete = type(ERR_TRADE_COMPLETE) == "string" and (a1 == ERR_TRADE_COMPLETE or a2 == ERR_TRADE_COMPLETE)
    local cancelled = type(ERR_TRADE_CANCELLED) == "string" and (a1 == ERR_TRADE_CANCELLED or a2 == ERR_TRADE_CANCELLED)
    if complete then
        Delivery.markVerified("trade")
        completeAt = ns.now()
        trade.complete = true
        -- Wait for the bags (BAG_UPDATE_DELAYED or a few seconds).
        trade.bagTimer = true
        ns.after(Delivery.BAG_WAIT, function()
            if trade and trade.complete then finish(true) end
        end)
    elseif cancelled then
        finish(false)
    end
end

function Delivery.onBagsSettled()
    if trade and trade.complete then finish(true) end
end

function Delivery.onTradeClosed()
    if not trade then return end
    if trade.complete then return end -- the bag wait finishes it
    local t = trade
    ns.after(Delivery.CLOSE_WAIT, function()
        if trade == t and not t.complete then finish(false) end
    end)
end

-- Login: a trade both accepted but never finished (disconnect, /reload).
-- Never closed by itself; both sides get a reminder (R-7.2).
function Delivery.checkPending()
    local o = O().local_()
    local p = o.pendingTrade
    o.pendingTrade = nil
    if type(p) ~= "table" then return "none" end
    if ns.now() - (p.at or 0) > Delivery.SNAPSHOT_KEEP then
        Delivery.log("trade", "stale-snapshot")
        return "stale"
    end
    Delivery.apply(p.other, Delivery.sum(p.theirs), Delivery.sum(p.mine), "trade", false)
    Delivery.log("trade", "interrupted", p.other)
    return "reminded"
end

---------------------------------------------------------------------------
-- Mail (R-7.3)
---------------------------------------------------------------------------

local sending -- { to = author, items = { [id] = n } }

local function authorByName(name)
    name = str(name)
    if name == "" then return nil end
    local m = ns.Comm.memberFor(name)
    if not m and not name:find("-", 1, true) then m = ns.Comm.memberFor(name .. "-" .. ns.realm()) end
    return m and S().authorOf(m.guid) or nil
end
Delivery.authorByName = authorByName

function Delivery.onSendMail(recipient)
    sending = nil
    local to = authorByName(recipient)
    if not to then return end
    local slots = {}
    for i = 1, Delivery.SEND_SLOTS do
        local _, itemID, _, count = ns.call(GetSendMailItem, i)
        local id = ns.num(itemID)
        if not id and fn(GetSendMailItemLink) then id = Delivery.itemIDOf(ns.call(GetSendMailItemLink, i)) end
        if id then slots[#slots + 1] = { id = id, n = ns.num(count) or 1 } end
    end
    if #slots == 0 then return end
    sending = { to = to, items = Delivery.sum(slots) }
end

function Delivery.onMailSent()
    local s = sending
    sending = nil
    if not s then return end
    -- Only "sent" counts: the mail left (R-7.3). Not sure it arrives, so
    -- this is the crafter's half only; the customer's side checks on taking it.
    Delivery.markVerified("mailSend")
    local touched = Delivery.apply(s.to, nil, s.items, "mail", true)
    Delivery.log("mail", touched > 0 and "sent" or "no-order", s.to)
end

function Delivery.onMailFailed()
    if sending then Delivery.log("mail", "failed", sending.to) end
    sending = nil
end

-- What a take is about to move: { sender, returned, items = { { id, n, before } } }.
-- Review 2-4: several takes within a few seconds are judged together (one
-- list, the bags compared once per item against the count before the first).
-- Review 2-5: the hook runs after the client's call; if the attachment is
-- already gone, the copy read at MAIL_INBOX_UPDATE is used.
local takings, lastTakeAt = {}, 0
local inboxCache = {}

local function attachment(index, attach)
    local _, itemID, _, count = ns.call(GetInboxItem, index, attach)
    local id = ns.num(itemID)
    if not id and fn(GetInboxItemLink) then id = Delivery.itemIDOf(ns.call(GetInboxItemLink, index, attach)) end
    return id, ns.num(count)
end

-- GF-FIX-E (review M-22): the header says whether a mail has attachments
-- (hasItem: a count on retail, nil when none). nil only counts as "none" once
-- this client has shown the field at least once; until then every slot is read.
local headerHasItem = false
local function readHeader(index)
    local _, _, sender, _, _, cod, _, hasItem, _, wasReturned = ns.call(GetInboxHeaderInfo, index)
    if hasItem ~= nil then headerHasItem = true end
    return { sender = str(sender), cod = ns.num(cod) or 0, returned = wasReturned == true or wasReturned == 1,
        items = {}, hasItem = hasItem }
end
local function readSlots(index, m)
    if m.read then return m end
    local h = m.hasItem
    m.hasItem, m.read = nil, true
    if h == false or h == 0 or (h == nil and headerHasItem) then return m end
    for j = 1, Delivery.RECEIVE_SLOTS do
        local id, n = attachment(index, j)
        if id and n then m.items[j] = { id = id, n = n } end
    end
    return m
end
local function readMail(index) return readSlots(index, readHeader(index)) end

-- Open orders of mine (customer or crafter) exist.
local function anyOpenOrder()
    local my = me()
    if not my then return false end
    for _, v in pairs(O().all()) do
        if v.state ~= "deal" and v.state ~= "cancel" and (v.customer == my or v.crafter == my) then return true end
    end
    return false
end
Delivery.anyOpenOrder = anyOpenOrder
Delivery.inboxReads = 0 -- tests: mails read by the last MAIL_INBOX_UPDATE

local lastTakeKey, lastTakeClock
function Delivery.onInboxUpdate()
    -- The inbox changed: a mail at the same index is another mail now (review M-23).
    lastTakeKey, lastTakeClock = nil, nil
    inboxCache = {}
    Delivery.inboxReads = 0
    if not fn(GetInboxHeaderInfo) then return end
    -- Review M-22: no open order = nothing a mail could settle; the take itself
    -- still reads the mail live (evidence for 可用 is never lost).
    if not anyOpenOrder() then return end
    local n = fn(GetInboxNumItems) and ns.num((ns.call(GetInboxNumItems))) or 50
    -- Headers first (learns whether hasItem exists), then slots of mails with items.
    local heads = {}
    for i = 1, math.min(n, 100) do
        local m = readHeader(i)
        if m.sender == "" and m.hasItem == nil and not fn(GetInboxNumItems) then
            -- No count from the client: an empty header may still have slots; read them to decide.
            readSlots(i, m)
            if not next(m.items) then break end
        end
        heads[#heads + 1] = { i = i, m = m }
    end
    for _, x in ipairs(heads) do
        local m = readSlots(x.i, x.m)
        Delivery.inboxReads = Delivery.inboxReads + 1
        if not (m.sender == "" and not next(m.items)) then inboxCache[x.i] = m end
    end
end

-- The client's frame time: two hooks of one call see the same value; two takes
-- never do (each waits for the server).
local function takeClock()
    if fn(GetTime) then local t = ns.num((ns.call(GetTime))); if t then return "f" .. t end end
    return "s" .. tostring(ns.now())
end

function Delivery.onTake(index, attach)
    local live = readMail(index)
    local cached = inboxCache[index]
    local m = (live.sender ~= "" and next(live.items)) and live or cached
    if not m or m.sender == "" then
        Delivery.log("mail", "not-loaded")
        return "not-loaded"
    end
    local items = {}
    for j, it in pairs(m.items) do
        if not attach or j == attach then items[#items + 1] = { id = it.id, n = it.n } end
    end
    if #items == 0 then Delivery.log("mail", "not-loaded"); return "not-loaded" end
    -- GF-FIX-E (review M-23): the same take reported twice (a second hook) counts
    -- once: same slot, same mail (sender and items), same frame, no inbox change
    -- in between. The next mail moving into slot 1 within the same second is
    -- another mail (MAIL_INBOX_UPDATE came between, or other sender or items).
    table.sort(items, function(x, y) if x.id ~= y.id then return x.id < y.id end return x.n < y.n end)
    local parts = { tostring(index), tostring(attach), m.sender }
    for _, it in ipairs(items) do parts[#parts + 1] = it.id .. "x" .. it.n end
    local key, clock = table.concat(parts, ":"), takeClock()
    if key == lastTakeKey and clock == lastTakeClock then return "duplicate" end
    lastTakeKey, lastTakeClock = key, clock
    if cached and attach then cached.items[attach] = nil elseif cached then cached.items = {} end
    takings[#takings + 1] = { sender = authorByName(m.sender), returned = m.returned, items = items,
        cod = m.cod, at = ns.now() }
    -- The bag count before THIS take (the first take of an item keeps its own).
    for _, it in ipairs(items) do it.before = countOf(it.id) end
    lastTakeAt = ns.now()
    ns.after(Delivery.BAG_WAIT, function()
        if ns.now() - lastTakeAt >= Delivery.BAG_WAIT - 0.01 then Delivery.onBagsSettledMail() end
    end)
    return "waiting"
end

function Delivery.onBagsSettledMail()
    local list = takings
    takings = {}
    if #list == 0 then return end
    -- One bag check per item over every take in the window.
    local byItem = {}
    for _, t in ipairs(list) do
        for _, it in ipairs(t.items) do
            local b = byItem[it.id]
            if not b then byItem[it.id] = { before = it.before, n = it.n } else b.n = b.n + it.n end
        end
    end
    local okItem = {}
    for id, b in pairs(byItem) do okItem[id] = b.before ~= nil and countOf(id) ~= nil and countOf(id) - b.before == b.n end
    for _, t in ipairs(list) do Delivery.settleOne(t, okItem) end
end

function Delivery.settleOne(t, okItem)
    if not t.sender then Delivery.log("mail", "not-member"); return end
    local merged, order = {}, {}
    for _, it in ipairs(t.items) do
        local m = merged[it.id]
        if not m then m = { id = it.id, n = 0 }; merged[it.id] = m; order[#order + 1] = m end
        m.n = m.n + it.n
    end
    local received, sureAll = {}, true
    for _, it in ipairs(order) do
        local code = Delivery.judgeMail({ sender = t.sender, returned = t.returned, id = it.id, n = it.n,
            before = 0, after = okItem[it.id] and it.n or -1 })
        if code == "ok" then Delivery.markVerified("mailTake") end
        if code == "returned" then
            -- A returned mail back at the crafter: take the count back (R-7.3).
            for _, v in ipairs(O().between(me(), t.sender)) do
                if v.crafter == me() and v.item == it.id then
                    O().crafter(v, "gave", -math.min(it.n, v.gave))
                    O().crafter(v, "undeliver")
                    break
                end
            end
            Delivery.log("mail", "returned", t.sender)
        else
            if code ~= "ok" then sureAll = false end
            received[it.id] = (received[it.id] or 0) + it.n
        end
    end
    if next(received) then
        -- Cash on delivery: taking the item means it was paid (R-7.3). Marked
        -- before the order may close (closed orders cannot change).
        if t.cod > 0 then
            for _, v in ipairs(O().between(me(), t.sender)) do
                if v.customer == me() and received[v.item] then O().customer(v.id, "paid"); break end
            end
        end
        local touched = Delivery.apply(t.sender, received, nil, "mail", sureAll)
        Delivery.log("mail", touched > 0 and (sureAll and "ok" or "bag-delta") or "no-order", t.sender)
    end
end

function Delivery.install()
    if Delivery.installed then return end
    Delivery.installed = true
    if not fn(hooksecurefunc) then return end
    if fn(SendMail) then pcall(hooksecurefunc, "SendMail", function(recipient) Delivery.onSendMail(recipient) end) end
    if fn(TakeInboxItem) then pcall(hooksecurefunc, "TakeInboxItem", function(i, j) Delivery.onTake(i, j) end) end
    if fn(AutoLootMailItem) then pcall(hooksecurefunc, "AutoLootMailItem", function(i) Delivery.onTake(i) end) end
end

function Delivery.resetSession()
    trade, sending, completeAt = nil, nil, nil; takings, inboxCache, lastTakeAt = {}, {}, 0
    lastTakeKey, lastTakeClock, headerHasItem = nil, nil, false
end
