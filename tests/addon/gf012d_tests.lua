-- GF-012-D: 臨時黑箱 phase 3, owner 2026-11-28: 申領 → 核准／拒絕 → 已交付 →
-- 已收到. Who writes what (KR requester, KD approver, KA custodian), who may
-- decide (會長, the custodian asked, 審核幹部 KO), 10 in stock and two ask
-- for 8, cancel / 7-day expiry release, duplicates never deduct twice, no
-- right = not used, revoked lists never come back, the delivered snapshot,
-- the page (addView, 申領 lists, the form, the badge), combat, notices.
-- Offline only (made-up names, GUIDs and item IDs); nothing checked in game.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local A, B, C, D, E, F = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D", "0000-0000000E", "0000-0000000F"
    local PEER_B = "測試乙-測試伺服器"
    local ITEM = 5001
    local DAY = 86400

    -- ranks = { A = "會長", B = "會員" } to make me the guild master.
    local function roster(ranks)
        local r = wow.defaultRoster()
        r[#r + 1] = { name = "測試戊-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
            zone = "奧格瑪", online = true, guid = "Player-" .. E }
        r[#r + 1] = { name = "測試己-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
            zone = "奧格瑪", online = true, guid = "Player-" .. F }
        local key = { A = 1, B = 2, C = 3, D = 4 }
        for who, rank in pairs(ranks or {}) do r[key[who]].rank = rank end
        return r
    end

    local G
    local function installGame()
        G = { bags = {}, slots = { [0] = 20, [1] = 12, [2] = 10, [3] = 10, [4] = 5, [5] = 8 }, bankOpen = false }
        for tab = 6, 14 do G.slots[tab] = 98 end
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag >= 6 and not G.bankOpen then return 0 end
                return G.slots[bag] or 0
            end,
            GetContainerItemInfo = function(bag, slot)
                local it = G.bags[bag] and G.bags[bag][slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = false, isLocked = false, iconFileID = 134939,
                    hyperlink = "|cffffffff|Hitem:" .. it[1] .. "::::::::|h[物品]|h|r" }
            end,
        }
        G.enum = Enum
        Enum = {}
        for k, v in pairs(G.enum or {}) do Enum[k] = v end
        Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, AccountBankTab_1 = 15 }
        for i = 1, 9 do Enum.BagIndex["CharacterBankTab_" .. i] = 5 + i end
        C_Item = {
            GetItemIconByID = function() return 134939 end,
            GetItemNameByID = function(id) return "物品" .. id end,
            RequestLoadItemDataByID = function() end,
            GetItemInfoInstant = function(id) return id, "類別", "子類別", "", 134939, 5, 0 end,
        }
        ChatFrame_SendTellWithMessage = function() end
    end
    local function removeGame()
        C_Container, C_Item, ChatFrame_SendTellWithMessage, IsGuildLeader = nil, nil, nil, nil
        if G then Enum = G.enum end
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function T0() return math.floor(wow.state.now) end
    local function later(s) wow.state.now = wow.state.now + s end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function offer(ns, a, g, v, t)
        local r = ns.Share.offer(a, g, t or T0(), ns.Share.hash(v), v, true, a)
        wow.advance(0.01)
        return r
    end
    local function setList(ns, entries, t)
        t = t or T0()
        local d = { epoch = t, leader = B, entries = {} }
        for _, e in ipairs(entries) do d.entries[#d.entries + 1] = { a = e[1], kinds = e[2], enabled = e[3] ~= false, epoch = e[4] or t } end
        from(ns, PEER_B, vMsg(ns, B, "K", t, assert(ns.Bank.encode(d))))
        wow.advance(0.01)
        return t
    end
    local function setOfficers(ns, entries, t, epoch)
        t = t or T0()
        local d = { epoch = epoch or t, leader = B, entries = {} }
        for _, e in ipairs(entries) do d.entries[#d.entries + 1] = { a = e[1], enabled = e[2] ~= false, epoch = e[3] or epoch or t } end
        from(ns, PEER_B, vMsg(ns, B, "KO", t, assert(ns.Bank.encodeOfficers(d))))
        wow.advance(0.01)
        return t
    end
    local function offerStock(ns, a, bags, t)
        return offer(ns, a, "KSB", (ns.BankStock.encodePart(bags)), t) and
            offer(ns, a, "KS", ns.BankStock.encodeHead({ bags = "1", tabs = {} }), t)
    end
    -- Somebody's requests: list = { { id, keeper, qty, state ("o"), created, st, note } }.
    local function requests(ns, a, list, t)
        local m = {}
        for _, x in ipairs(list) do
            m[x[1]] = { keeper = x[2], itemID = x.item or ITEM, qty = x[3], purpose = x.purpose or "d", created = x.created or T0(),
                state = x.state or "o", st = x.st or x.created or T0(), note = x.note or "" }
        end
        return offer(ns, a, "KR", ns.BankRequests.encode("KR", m), t)
    end
    -- Somebody's decisions: list = { { requester, id, "a" | "r", t, reason } }.
    local function decisions(ns, a, list, t)
        local m = {}
        for _, x in ipairs(list) do
            m[x[1] .. ":" .. ns.Share.b36(x[2])] = { req = x[1], id = x[2], d = x[3], t = x[4] or T0(), reason = x[5] or "" }
        end
        return offer(ns, a, "KD", ns.BankRequests.encode("KD", m), t)
    end
    -- A custodian's allocations: list = { { requester, id, state, qty, t, rt, by, snapT } }.
    local function allocations(ns, a, list, t)
        local m = {}
        for _, x in ipairs(list) do
            m[x[1] .. ":" .. ns.Share.b36(x[2])] = { req = x[1], id = x[2], state = x[3], itemID = x.item or ITEM, qty = x[4],
                t = x[5] or T0(), rt = x[6] or x[5] or T0(), by = x[7] or B, snapT = x[8] or 0 }
        end
        return offer(ns, a, "KA", ns.BankRequests.encode("KA", m), t)
    end

    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = roster(opts.ranks) })
        installGame()
        if opts.leader then IsGuildLeader = function() return true end end
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        wow.advance(40)
        wow.state.sent = {}
        ns.Bank.invalidate()
        return ns
    end
    -- I am a custodian with ITEM x qty in my bag 0 (shared).
    local function custodian(qty, entries)
        local ns = login()
        setList(ns, entries or { { A, "bk" }, { C, "bk" } })
        G.bags[0] = { { ITEM, qty or 10 } }
        ns.Bank.setScope("bags", 0, true)
        ns.BankStock.setConsent(true)
        wow.advance(0.01)
        return ns
    end
    local function key(ns, a, id) return a .. ":" .. ns.Share.b36(id) end
    local function state(ns, a, id) local v = ns.BankRequests.get(key(ns, a, id)); return v and v.state end
    local function notices(ns, text)
        local n = 0
        for _, e in ipairs(ns.Notify.list()) do if e.module == "bank_request" and (not text or e.text:find(text, 1, true)) then n = n + 1 end end
        return n
    end
    local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

    ---------------------------------------------------------------------------
    -- 1. The whole flow (I ask; the guild master approves; the custodian reserves, hands over)
    ---------------------------------------------------------------------------

    test("GF-012-D flow: 申領 → 已核准 (預留) → 已交付 → 已收到 = 完成; 可申領 and the snapshot agree", done(function()
        local ns = login()
        local R = ns.BankRequests
        setList(ns, { { C, "bk" }, { E, "bk" } })
        offerStock(ns, C, { [ITEM] = 10 })
        eq(R.available(C, ITEM), 10, "nothing reserved yet")
        -- Bad forms first.
        eq(R.create({ keeper = C, itemID = ITEM, qty = 3 }), "purpose", "用途 must be chosen")
        eq(R.create({ keeper = C, itemID = ITEM, qty = 11, purpose = "p" }), "more", "not past 可申領")
        eq(R.create({ keeper = C, itemID = ITEM, qty = 0, purpose = "p" }), "qty", "at least 1")
        eq(R.create({ keeper = D, itemID = ITEM, qty = 1, purpose = "p" }), "keeper", "D is no custodian")
        local r, k = R.create({ keeper = C, itemID = ITEM, qty = 3, purpose = "p", note = "練裁縫用|cff" })
        eq(r, "ok", "sent")
        eq(k, key(ns, A, 1), "my first request")
        eq(state(ns, A, 1), "pending", "等待核准")
        eq(R.available(C, ITEM), 10, "waiting reserves nothing")
        local mine = ns.Share.decoded(A, "KR")
        eq(#mine, 1, "my KR record has it"); eq(mine[1].note, "練裁縫用cff", "the note is cleaned")
        ok(has(R.actions(R.get(k)), "cancel") and not has(R.actions(R.get(k)), "approve"), "I may cancel, not approve my own")
        -- The guild master approves (B): approved, counted until the custodian's computer reserves it.
        later(60)
        decisions(ns, B, { { A, 1, "a" } })
        eq(state(ns, A, 1), "approved", "已核准")
        ok(R.get(k).provisional, "not reserved by the custodian yet")
        eq(R.available(C, ITEM), 7, "10 − 3")
        eq(notices(ns, "已核准"), 1, "told: approved")
        -- The custodian's computer reserves it.
        later(60)
        allocations(ns, C, { { A, 1, "r", 3, T0(), T0(), B } })
        ok(R.get(k).reserved, "reserved")
        eq(R.available(C, ITEM), 7, "still 7: the same 3, not 6")
        eq(notices(ns, "已核准"), 1, "approved told once")
        -- Handed over: KA d with the snapshot time; my copy of C's stock is older → still counted.
        later(120)
        local snap = T0()
        allocations(ns, C, { { A, 1, "d", 3, snap, snap - 120, B, snap } })
        eq(state(ns, A, 1), "delivered", "已交付")
        eq(R.available(C, ITEM), 7, "the old snapshot still has 10: 3 still taken off")
        eq(notices(ns, "已交付"), 1, "told: delivered")
        ok(has(R.actions(R.get(k)), "received") and not has(R.actions(R.get(k)), "cancel"), "已收到, no 取消 after 已交付")
        eq(R.cancel(k), "state", "cancel refused after 已交付")
        -- C's new snapshot (7 left) arrives: the reservation is no longer taken off (never 4).
        offerStock(ns, C, { [ITEM] = 7 }, snap)
        eq(R.available(C, ITEM), 7, "7 in the snapshot, nothing reserved: never both")
        eq(R.received(k), "received", "已收到")
        eq(state(ns, A, 1), "done", "完成")
        eq(#R.actions(R.get(k)), 0, "no buttons")
    end))

    ---------------------------------------------------------------------------
    -- 2. 10 in stock, two ask for 8
    ---------------------------------------------------------------------------

    test("GF-012-D 10 in stock, two ask for 8, two approvers at once: the custodian reserves one, the other 數量不足", done(function()
        local ns = custodian(10)
        local R = ns.BankRequests
        setOfficers(ns, { { D } })
        eq(R.shared(A, ITEM), 10, "my stock is shared")
        requests(ns, E, { { 1, A, 8 } })
        requests(ns, F, { { 1, A, 8 } })
        eq(R.todoCount(), 2, "two wait for me (the custodian asked)")
        eq(notices(ns, "等你核准"), 2, "told twice")
        -- The guild master and the reviewer approve at the same time, while I am away.
        later(10)
        local t = T0()
        ns.Share.offer(B, "KD", t, ns.Share.hash(R.encode("KD", { [key(ns, E, 1)] = { req = E, id = 1, d = "a", t = t, reason = "" } })),
            R.encode("KD", { [key(ns, E, 1)] = { req = E, id = 1, d = "a", t = t, reason = "" } }), true, B)
        ns.Share.offer(D, "KD", t + 1, ns.Share.hash(R.encode("KD", { [key(ns, F, 1)] = { req = F, id = 1, d = "a", t = t + 1, reason = "" } })),
            R.encode("KD", { [key(ns, F, 1)] = { req = F, id = 1, d = "a", t = t + 1, reason = "" } }), true, D)
        wow.advance(0.01)
        eq(state(ns, E, 1), "approved", "the earlier approval is reserved")
        ok(R.get(key(ns, E, 1)).reserved, "reserved by me")
        eq(state(ns, F, 1), "short", "the other: 數量不足，請重新申領")
        eq(R.available(A, ITEM), 2, "10 − 8, never 10 − 16")
        local ka = ns.Share.decoded(A, "KA")
        eq(#ka, 2, "my KA: one reservation, one short")
        eq(notices(ns, "等你交付"), 1, "told: one to hand over")
        eq(R.todoCount(), 1, "only E's waits for me now (to hand over)")
    end))

    test("GF-012-D 10 in stock, two ask for 8: the guild master can approve only one (可申領 checked)", done(function()
        local ns = login({ ranks = { A = "會長", B = "會員" }, leader = true })
        local R = ns.BankRequests
        eq(ns.Bank.appoint({ guid = "Player-" .. C }, "bk"), "ok", "C is a custodian")
        wow.advance(0.01)
        offerStock(ns, C, { [ITEM] = 10 })
        requests(ns, E, { { 1, C, 8 } })
        requests(ns, F, { { 1, C, 8 } })
        eq(R.todoCount(), 2, "both wait for me (guild master)")
        eq(R.approve(key(ns, E, 1)), "approved", "the first")
        eq(R.approve(key(ns, F, 1)), "short", "the second: 可申領 is 2")
        eq(state(ns, F, 1), "pending", "still waiting (may be rejected)")
        eq(R.reject(key(ns, F, 1), "數量不夠，下週再補"), "rejected", "rejected with a reason")
        eq(state(ns, F, 1), "rejected", "已拒絕")
        eq(R.get(key(ns, F, 1)).decision.reason, "數量不夠，下週再補", "the reason")
        eq(R.available(C, ITEM), 2, "8 counted for E until C's computer answers")
    end))

    ---------------------------------------------------------------------------
    -- 3. Cancel and the 7 days release the reservation
    ---------------------------------------------------------------------------

    test("GF-012-D 取消 and 7 days (waiting or approved) release the reservation; reservations by me count once", done(function()
        local ns = custodian(10)
        local R = ns.BankRequests
        requests(ns, E, { { 1, A, 8 } })
        eq(R.approve(key(ns, E, 1)), "approved", "I (the custodian) approve: reserved at once")
        ok(R.get(key(ns, E, 1)).reserved, "reserved")
        eq(R.available(A, ITEM), 2, "2 left")
        later(30)
        requests(ns, E, { { 1, A, 8, state = "c", created = T0() - 30, st = T0() } })
        eq(state(ns, E, 1), "cancelled", "the requester cancelled")
        eq(R.available(A, ITEM), 10, "released")
        eq(#R.actions(R.get(key(ns, E, 1))), 0, "nothing to press")
        -- Waiting 7 days: 過期.
        requests(ns, E, { { 1, A, 8, state = "c", created = T0() - 30, st = T0() }, { 2, A, 4 } })
        eq(state(ns, E, 2), "pending", "a new one waits")
        later(7 * DAY)
        eq(state(ns, E, 2), "expired", "7 days without a decision")
        eq(R.approve(key(ns, E, 2)), "state", "an expired one cannot be approved")
        -- Approved 7 days without 已交付: 過期 and released.
        requests(ns, F, { { 1, A, 6 } })
        eq(R.approve(key(ns, F, 1)), "approved", "approved")
        eq(R.available(A, ITEM), 4, "6 reserved")
        later(7 * DAY - 60)
        eq(state(ns, F, 1), "approved", "not yet")
        later(61)
        eq(state(ns, F, 1), "expired", "7 days without 已交付")
        eq(R.available(A, ITEM), 10, "released")
        eq(R.deliver(key(ns, F, 1)), "state", "no 已交付 after it expired")
    end))

    ---------------------------------------------------------------------------
    -- 4. Resent / duplicate messages, two approvals of one request
    ---------------------------------------------------------------------------

    test("GF-012-D the same message twice, two approvals of one request, settle again: reserved once", done(function()
        local ns = custodian(10)
        local R = ns.BankRequests
        setOfficers(ns, { { D } })
        local t = T0()
        local kr = R.encode("KR", { [1] = { keeper = A, itemID = ITEM, qty = 8, purpose = "q", created = t, state = "o", st = t, note = "" } })
        from(ns, "測試戊-測試伺服器", vMsg(ns, E, "KR", t, kr))
        from(ns, "測試戊-測試伺服器", vMsg(ns, E, "KR", t, kr)) -- the same again
        wow.advance(0.01)
        later(5)
        local kd = R.encode("KD", { [key(ns, E, 1)] = { req = E, id = 1, d = "a", t = T0(), reason = "" } })
        from(ns, PEER_B, vMsg(ns, B, "KD", T0(), kd))
        from(ns, PEER_B, vMsg(ns, B, "KD", T0(), kd)) -- resent
        decisions(ns, D, { { E, 1, "a", T0() + 1 } }) -- the reviewer too
        wow.advance(0.01)
        eq(state(ns, E, 1), "approved", "approved")
        eq(#ns.Share.decoded(A, "KA"), 1, "one allocation")
        eq(R.available(A, ITEM), 2, "8 taken off once")
        eq(R.settle(), 0, "settling again writes nothing")
        from(ns, PEER_B, vMsg(ns, B, "KD", T0(), kd)); wow.advance(0.01)
        eq(R.available(A, ITEM), 2, "still once")
        -- I hand it over: the trade first (my bag now 2), then 已交付.
        G.bags[0][1][2] = 2
        wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01)
        eq(R.available(A, ITEM), 0, "between the trade and 已交付: shown low (never too high)")
        later(5)
        local okConfirm = R.deliver(key(ns, E, 1))
        eq(okConfirm, "delivered", "已交付")
        eq(R.available(A, ITEM), 2, "after 已交付: the snapshot only (2), the 8 not again")
        eq(R.get(key(ns, E, 1)).alloc.snapT, math.floor(ns.Share.get(A, "KSB").t), "snapT = my bags snapshot")
    end))

    ---------------------------------------------------------------------------
    -- 5. No right: not used
    ---------------------------------------------------------------------------

    test("GF-012-D decisions or allocations from someone without the right are not used", done(function()
        local ns = login()
        local R = ns.BankRequests
        setList(ns, { { C, "bk" } })
        offerStock(ns, C, { [ITEM] = 10 })
        requests(ns, F, { { 1, C, 5 } })
        later(5)
        decisions(ns, E, { { F, 1, "a" } }) -- E is nobody
        eq(state(ns, F, 1), "pending", "E's approval is not used")
        allocations(ns, E, { { F, 1, "r", 5 } }) -- E is not the custodian asked
        eq(state(ns, F, 1), "pending", "E's reservation is not used")
        eq(R.available(C, ITEM), 10, "nothing taken off")
        ok(R.stats.ignored > 0, "counted for 同步與診斷")
        -- A reviewer list from someone who is not the guild master: E is no reviewer.
        offer(ns, E, "KO", ns.Bank.encodeOfficers({ epoch = T0(), leader = E, entries = { { a = E, enabled = true, epoch = T0() } } }))
        eq((ns.Bank.isOfficer(E)), false, "not from the guild master")
        decisions(ns, E, { { F, 1, "r", T0() } })
        eq(state(ns, F, 1), "pending", "still nothing")
        -- I am a member: no buttons but 取消 on my own.
        eq(#R.actions(R.get(key(ns, F, 1))), 0, "I may do nothing with F's")
        eq(R.approve(key(ns, F, 1)), "no-right", "refused")
        -- Bad values are refused, never stored.
        local n = R.stats.rejected
        eq(ns.Share.offer(D, "KR", T0(), ns.Share.hash("1;x,y"), "1;x,y", true, D), "invalid", "a bad KR")
        eq(ns.Share.offer(D, "KD", T0(), ns.Share.hash("2;"), "2;", true, D), "invalid", "another format")
        ok(R.stats.rejected > n, "counted")
    end))

    ---------------------------------------------------------------------------
    -- 6. Revoked reviewer / custodian: the old decisions do not come back
    ---------------------------------------------------------------------------

    test("GF-012-D revoked reviewer or custodian: old decisions and reservations stay gone, also after a new appointment", done(function()
        local ns = login()
        local R = ns.BankRequests
        local t0 = setList(ns, { { C, "bk" } })
        setOfficers(ns, { { D } })
        offerStock(ns, C, { [ITEM] = 10 })
        later(10)
        requests(ns, E, { { 1, C, 4 } })
        later(10)
        decisions(ns, D, { { E, 1, "a" } })
        eq(state(ns, E, 1), "approved", "D's approval counts")
        later(10)
        setOfficers(ns, { { D, false } })
        eq(state(ns, E, 1), "pending", "D revoked: the approval is gone")
        later(10)
        setOfficers(ns, { { D } })
        eq((ns.Bank.isOfficer(D)), true, "D again")
        eq(state(ns, E, 1), "pending", "the old approval (before D's new entry) does not come back")
        -- An old reviewer list (lower epoch, newer time) is not taken.
        later(10)
        setOfficers(ns, { { D } }, T0(), t0)
        eq(ns.Bank.officers().state, "old", "an older epoch is refused")
        -- The custodian: reserved, then revoked, then appointed again.
        later(10)
        setOfficers(ns, { { D } })
        decisions(ns, D, { { E, 1, "a" } })
        allocations(ns, C, { { E, 1, "r", 4 } })
        ok(R.get(key(ns, E, 1)).reserved, "reserved by C")
        eq(R.available(C, ITEM), 6, "4 taken off")
        later(10)
        setList(ns, { { C, "bk", false } })
        eq(state(ns, E, 1), "void", "C revoked: 保管人已撤銷，申領失效")
        later(10)
        setList(ns, { { C, "bk" } })
        offerStock(ns, C, { [ITEM] = 10 })
        eq(state(ns, E, 1), "void", "appointed again: the old request does not come back")
        eq(R.available(C, ITEM), 10, "and its reservation is not taken off")
    end))

    ---------------------------------------------------------------------------
    -- 7. Records: sizes, kept 60 days
    ---------------------------------------------------------------------------

    test("GF-012-D records: the largest values fit (measured); closed requests kept 60 days, then dropped", done(function()
        local ns = login()
        local R = ns.BankRequests
        local t = T0()
        local note = string.rep("備", 15) -- 45 bytes
        local kr, kd, ka = {}, {}, {}
        local reqA = "1234-0ABCDEF0"
        for i = 1, R.MAX_ENTRIES.KR do
            kr[i] = { keeper = reqA, itemID = 2147483000, qty = 9999, purpose = "o", created = t, state = "o", st = t, note = note }
        end
        for i = 1, R.MAX_ENTRIES.KD do
            kd[reqA .. ":" .. ns.Share.b36(i)] = { req = reqA, id = i, d = "r", t = t, reason = note }
        end
        for i = 1, R.MAX_ENTRIES.KA do
            ka[reqA .. ":" .. ns.Share.b36(i)] = { req = reqA, id = i, state = "d", itemID = 2147483000, qty = 9999, t = t, rt = t, by = reqA, snapT = t }
        end
        local per = ns.Share.MAX_BYTES - 40
        for g, m in pairs({ KR = kr, KD = kd, KA = ka }) do
            local v = R.encode(g, m)
            ok(#v <= R.MAX_VALUE[g], g .. " fits: " .. #v)
            ok(R.decode(g, v), g .. " decodes")
            realPrint(string.format("     [GF-012-D measure] %s worst: %d entries, %d bytes (limit %d) = about %d messages", g,
                R.MAX_ENTRIES[g], #v, R.MAX_VALUE[g], 1 + math.ceil(#v / per)))
        end
        local one = R.encode("KR", { [1] = kr[1] })
        realPrint(string.format("     [GF-012-D measure] one usual request (15-character note): %d bytes = 1 message", #one))
        -- One entry too many is refused.
        kr[R.MAX_ENTRIES.KR + 1] = kr[1]
        eq(R.decode("KR", R.encode("KR", kr)), nil, "too many entries refused")
        -- Kept 60 days after it closed.
        setList(ns, { { C, "bk" } })
        offerStock(ns, C, { [ITEM] = 10 })
        eq((R.create({ keeper = C, itemID = ITEM, qty = 1, purpose = "o" })), "ok", "made")
        eq(R.cancel(key(ns, A, 1)), "cancelled", "closed")
        later(59 * DAY)
        eq(R.prune(), 0, "59 days: kept")
        ok(ns.Share.decoded(A, "KR")[1], "still in my record")
        later(DAY + 1)
        eq(R.prune(), 1, "60 days: dropped")
        eq(#ns.Share.decoded(A, "KR"), 0, "my record says so (the others drop it too)")
    end))

    ---------------------------------------------------------------------------
    -- 8. The page
    ---------------------------------------------------------------------------

    test("GF-012-D addView: another file's page has a button, builds once, draws when shown", done(function()
        local ns = login()
        local UI = ns.BankUI
        local built, drawn, parent = 0, 0, nil
        ok(UI.addView({ key = "testview", text = "測試頁", order = 45,
            build = function(p) built = built + 1; parent = p; p.mark = p:CreateFontString(nil, "ARTWORK") end,
            draw = function() drawn = drawn + 1 end }), "added")
        eq(UI.addView({ key = "testview", text = "again" }), false, "a key only once")
        ns.Framework.open("bank")
        local c = UI.controls
        eq(#c.views.buttons, 5, "five buttons (GF-017 adds 公會銀行)")
        eq(c.views.buttons[4]:GetText(), "公會銀行", "GF-017's page by order"); eq(c.views.buttons[5]:GetText(), "測試頁", "by order")
        eq(built, 0, "not built before it is shown")
        wow.click(c.views.buttons[5])
        eq(c.view, "testview", "shown")
        eq(built, 1, "built once"); ok(drawn >= 1, "drawn")
        ok(parent:IsShown() and not c.stockView:IsShown(), "only that page")
        eq(UI.VIEW_W, ns.Framework.PANEL_WIDTH, "page width"); eq(UI.VIEW_H, ns.Framework.PANEL_HEIGHT, "page height")
        local d1 = drawn
        UI.setView("stock"); UI.setView("testview")
        eq(built, 1, "still built once"); ok(drawn > d1, "drawn again")
        ok(UI.refreshView("testview"), "refreshView draws when shown")
        eq(UI.refreshView("stock"), false, "not when another is shown")
        -- Added after the page was built: a new button too.
        ok(UI.addView({ key = "late", text = "後加", order = 50 }), "late")
        eq(#c.views.buttons, 6, "six buttons")
        UI.setView("late")
        eq(c.view, "late", "shows")
    end))

    test("GF-012-D page: 要我處理的 / 我的申領, only the buttons I may press, the badge, redraws make no frames", done(function()
        local ns = login({ ranks = { A = "會長", B = "會員" }, leader = true })
        local R, UI = ns.BankRequests, ns.BankUI
        ns.Bank.appoint({ guid = "Player-" .. C }, "bk"); wow.advance(0.01)
        ns.Bank.appoint({ guid = "Player-" .. E }, "bk"); wow.advance(0.01)
        later(5) -- the stock must not be older than the custodians' entries
        offerStock(ns, C, { [ITEM] = 10 })
        offerStock(ns, E, { [ITEM + 1] = 3 })
        for i = 1, 7 do requests(ns, "0000-000001" .. i, {}) end -- nobody's records (not in the roster)
        requests(ns, F, { { 1, C, 2, note = "打副本用" }, { 2, C, 1 }, { 3, C, 1 }, { 4, C, 1 }, { 5, C, 1 }, { 6, C, 1 } })
        eq((R.create({ keeper = E, itemID = ITEM + 1, qty = 2, purpose = "d" })), "ok", "my own request (I am the guild master)")
        ns.Framework.open("bank")
        local c = UI.controls
        eq(c.views.buttons[2]:GetText(), "申領（6）", "the badge: 6 wait for me")
        UI.setView("requests")
        local top, bottom = c.req.todo, c.req.mine
        ok(top.rows[1]:IsShown() and top.rows[UI.REQ_ROWS]:IsShown(), "rows")
        ok(top.more:GetText():find("還有 1 筆", 1, true), "more: " .. top.more:GetText())
        local row = top.rows[1]
        ok(row.b1:IsShown() and row.b2:IsShown(), "two buttons")
        eq(row.b1:GetText(), "核准"); eq(row.b2:GetText(), "拒絕")
        ok(row.who:GetText():find("申請人", 1, true), "who: " .. row.who:GetText())
        eq(row.state:GetText(), "等待核准")
        local mrow = bottom.rows[1]
        ok(mrow:IsShown(), "my request listed")
        ok(not mrow.b1:IsShown() and mrow.b2:IsShown() and mrow.b2:GetText() == "取消", "only 取消 on mine")
        ok(mrow.who:GetText():find("保管人", 1, true), "mine names the custodian")
        -- No overlap in a row: the name ends before the first column; columns and buttons in order.
        local C2 = UI.REQ_COL
        ok(C2.who - 134 > C2.purpose and C2.purpose - 84 > C2.state and C2.state - 186 > C2.ago
            and C2.ago - 72 > C2.b1 + UI.REQ_BUTTON_W and C2.b1 > C2.b2 + UI.REQ_BUTTON_W, "columns do not overlap")
        -- Approve from the row.
        local before = #wow.allObjects()
        local target = row.req
        wow.click(row.b1)
        eq(R.get(target.key).state, "approved", "approved from the row")
        eq(c.views.buttons[2]:GetText(), "申領（5）", "the badge follows")
        UI.scrollRequests("todo", -1); UI.refresh(); UI.setView("stock"); UI.setView("requests")
        eq(#wow.allObjects(), before, "no new frames on redraw, scroll, switch")
        -- Reject asks for a reason.
        wow.click(top.rows[1].b2)
        ok(UI.reason and UI.reason:IsShown(), "the reason box")
        UI.reason.box:SetText("先給別人")
        wow.click(UI.reason.yes)
        ok(#R.minelist() == 1, "mine still one")
        local rejected = 0
        for _, v in ipairs(R.view().list) do if v.state == "rejected" then rejected = rejected + 1 end end
        eq(rejected, 1, "rejected with the reason")
    end))

    test("GF-012-D stock row: 申領 next to 聯絡, 可申領 N under the name, the form (custodian choice, max, 用途 required); 調貨看板 shows 可申領", done(function()
        local ns = login()
        local R, UI = ns.BankRequests, ns.BankUI
        setList(ns, { { C, "bk" }, { E, "bk" } })
        offerStock(ns, C, { [ITEM] = 4 })
        offerStock(ns, E, { [ITEM] = 6 })
        requests(ns, F, { { 1, E, 5 } })
        later(5)
        decisions(ns, B, { { F, 1, "a" } })
        ns.Framework.open("bank")
        local c = UI.controls
        local r = c.stockRows[1]
        ok(r.ask:IsShown() and r.ask:GetText() == "申領", "申領 button")
        ok(r.sub:IsShown() and r.sub:GetText() == "可申領 5", "可申領 = 10 − 5: " .. tostring(r.sub:GetText()))
        local SC = UI.STOCK_COL
        ok(SC.ask >= 6 + 72 + 4 and SC.ago - 130 > SC.ask + 72 and SC.who - 240 > SC.ago, "申領 left of 聯絡, columns apart (no overlap)")
        -- The form: C first (E online but only 1 left? E has 6 − 5 = 1, C 4: online first → E is online)
        wow.click(r.ask)
        local f = UI.form
        ok(f and f:IsShown(), "the form")
        local ch = f.choices[f.keeperDrop.value]
        eq(ch.a, E, "online first (E online, C offline)")
        eq(f.max:GetText(), "最多 1", "max of E")
        f.keeperDrop.choose(2)
        eq(f.choices[f.keeperDrop.value].a, C, "C chosen")
        eq(f.max:GetText(), "最多 4", "max of C")
        f.qty:SetText("5")
        f.purposeDrop.choose("p")
        eq(UI.submitRequest(), "more", "past 可申領")
        ok(f.result:GetText():find("最多 4", 1, true), "says the max: " .. f.result:GetText())
        f.qty:SetText("2")
        f.purposeDrop.choose("")
        eq(UI.submitRequest(), "purpose", "用途 required")
        f.purposeDrop.choose("q")
        f.note:SetText("解任務")
        eq(UI.submitRequest(), "ok", "sent")
        ok(not f:IsShown(), "closed")
        eq(c.view, "requests", "the 申領 page")
        eq(R.minelist()[1].keeper, C, "to C")
        -- 調貨看板's 黑箱 line.
        ns.Framework.open("supply")
        local SUI = ns.SupplyUI
        local found
        for _, e in ipairs(SUI.stockEntries()) do if e.itemID == ITEM then found = e end end
        ok(found, "a stock entry")
        ok(ns.BankRequests.itemAvailable(found.stock) == 5, "可申領 for the board: 10 − 5")
    end))

    test("GF-012-D performance: 60 requesters x 10 requests, 2 custodians; rebuild, draw, cached redraw (measured)", done(function()
        local ns = login({ ranks = { A = "會長", B = "會員" }, leader = true })
        local R, UI = ns.BankRequests, ns.BankUI
        ns.Bank.appoint({ guid = "Player-" .. C }, "bk"); ns.Bank.appoint({ guid = "Player-" .. E }, "bk")
        later(5)
        local bags = {}
        for i = 1, 100 do bags[ITEM + i] = 50 end
        offerStock(ns, C, bags); offerStock(ns, E, bags)
        local r = roster({ A = "會長", B = "會員" })
        for i = 1, 60 do
            r[#r + 1] = { name = "會友" .. i .. "-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
                zone = "奧格瑪", online = true, guid = string.format("Player-0000-1%07d", i) }
        end
        wow.state.roster = r
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
        for i = 1, 60 do
            local list = {}
            for j = 1, 10 do list[j] = { j, (j % 2 == 0) and C or E, 1, item = ITEM + j } end
            requests(ns, string.format("0000-1%07d", i), list)
        end
        ns.Framework.open("bank")
        UI.setView("requests")
        local clock = os and os.clock
        R.invalidate(); R.version = R.version + 1
        local t0 = clock()
        UI.refresh()
        local full = (clock() - t0) * 1000
        t0 = clock()
        UI.refresh()
        local cached = (clock() - t0) * 1000
        eq(#R.view().list, 600, "600 requests")
        eq(R.todoCount(), 600, "all wait for me")
        realPrint(string.format("     [GF-012-D measure] 600 requests: work out + draw %.2f ms; redraw with nothing changed %.2f ms", full, cached))
        ok(cached < 50, "a redraw is cheap")
    end))

    ---------------------------------------------------------------------------
    -- 9. Combat
    ---------------------------------------------------------------------------

    test("GF-012-D in combat nothing is done: settle and notices wait, buttons refuse; after combat it runs", done(function()
        local ns = custodian(10)
        local R = ns.BankRequests
        requests(ns, E, { { 1, A, 3 } })
        local told = notices(ns)
        wow.enterCombat()
        later(5)
        decisions(ns, B, { { E, 1, "a" } })
        wow.advance(0.01)
        eq(ns.Share.get(A, "KA"), nil, "no reservation written in combat")
        ok(R.get(key(ns, E, 1)).provisional, "approved, waiting for me")
        eq(R.approve(key(ns, E, 1)), "combat", "buttons refuse")
        eq(R.create({ keeper = A, itemID = ITEM, qty = 1, purpose = "p" }), "combat", "the form too")
        eq(notices(ns), told, "no notice in combat")
        wow.leaveCombat()
        wow.advance(0.01)
        ok(ns.Share.get(A, "KA"), "written after combat")
        ok(R.get(key(ns, E, 1)).reserved, "reserved")
        ok(notices(ns, "等你交付") >= 1, "told after combat")
    end))

    ---------------------------------------------------------------------------
    -- 10. 審核幹部 list
    ---------------------------------------------------------------------------

    test("GF-012-D 審核幹部: only the guild master appoints / revokes; K unchanged; left the guild only marked", done(function()
        local ns = login({ ranks = { A = "會長", B = "會員" }, leader = true })
        local Bk = ns.Bank
        eq(Bk.appoint({ guid = "Player-" .. C }, "bk"), "ok", "a custodian")
        local kBefore = ns.Share.get(A, "K").v
        eq(Bk.appointOfficer({ guid = "Player-" .. D }), "ok", "D is a reviewer")
        eq(Bk.appointOfficer({ guid = "Player-" .. D }), "same", "again: same")
        eq(ns.Share.get(A, "K").v, kBefore, "the custodian list K is not touched")
        ok(Bk.decode(nil, ns.Share.get(A, "K").v), "K decodes as 0.16.16 does")
        eq((Bk.isOfficer(D)), true, "in force")
        eq(Bk.myRole(), "leader", "I am the guild master")
        ns.Framework.open("bank")
        local UI = ns.BankUI
        UI.setView("setup")
        local c = UI.controls
        ok(c.officerRows[1]:IsShown(), "listed")
        ok(c.officerRows[1].name:GetText():find("測試丁", 1, true), "D's name")
        ok(not c.officerAdd.disabled, "指定審核幹部 for the guild master")
        -- The picker in officer mode.
        wow.click(c.officerAdd)
        ok(UI.picker:IsShown() and UI.picker.mode == "officer", "the picker for 審核幹部")
        UI.picker:Hide()
        -- D leaves the guild: only marked.
        local r = roster({ A = "會長", B = "會員" })
        table.remove(r, 4)
        wow.state.roster = r
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
        UI.refresh()
        ok(c.officerRows[1].state:GetText():find("已不在公會", 1, true), "marked: " .. c.officerRows[1].state:GetText())
        eq(Bk.revokeOfficer(D), "ok", "revoked")
        eq((Bk.isOfficer(D)), false, "not in force")
        -- Not the guild master: refused.
        IsGuildLeader = function() return false end
        wow.state.roster = roster({})
        Bk.invalidate()
        eq(Bk.appointOfficer({ guid = "Player-" .. E }), "no-authority", "a member cannot")
    end))
end
