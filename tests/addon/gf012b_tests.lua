-- GF-012-B: 臨時黑箱 phase 2, the stock (BankStock.lua): only the custodian's
-- ticked scope is read, private slots never leave, a bank never seen is not
-- 0, bound items are left out, two custodians add up and one is never
-- counted twice, revoked / kinds off / left the guild = gone, other people's
-- data is not shown, limits, the confirm box, old saves, combat, no resend
-- of an unchanged snapshot, the page (search, wheel, 聯絡), the diagnostics
-- window (opaque) and the dropped PLAYERREAGENTBANKSLOTS_CHANGED.
-- Offline only (made-up names, GUIDs and item IDs); nothing checked in game.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local PEER_B = "測試乙-測試伺服器"

    -- The fake client: bags 0-5 always, bank tabs 6-14 only while open.
    -- G.bags[bag][slot] = { itemID, count, bound }. G.reads[bag] = item reads.
    local G
    local function installGame()
        G = { bags = {}, slots = { [0] = 20, [1] = 12, [2] = 10, [3] = 10, [4] = 5, [5] = 8 }, bankOpen = false, reads = {}, whispers = {} }
        for tab = 6, 14 do G.slots[tab] = 98 end
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bag >= 6 and not G.bankOpen then return 0 end
                return G.slots[bag] or 0
            end,
            GetContainerItemInfo = function(bag, slot)
                G.reads[bag] = (G.reads[bag] or 0) + 1
                local it = G.bags[bag] and G.bags[bag][slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939,
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
        }
        ChatFrame_SendTellWithMessage = function(name, text) G.whispers[#G.whispers + 1] = { name = name, text = text } end
    end
    local function removeGame()
        C_Container, C_Item, ChatFrame_SendTellWithMessage, IsGuildLeader = nil, nil, nil, nil
        if G then Enum = G.enum end
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function list(ns, epoch, entries)
        local d = { epoch = epoch, leader = B, entries = {} }
        for _, e in ipairs(entries) do d.entries[#d.entries + 1] = { a = e[1], kinds = e[2], enabled = e[3] ~= false, epoch = e[4] or epoch } end
        return assert(ns.Bank.encode(d))
    end
    -- The guild master B publishes a list.
    local function setList(ns, entries)
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, "K", t, list(ns, t, entries)))
        return t
    end
    -- GF-012-C: the stock is a head (KS) and parts (KSB, KS6 .. KS14) now.
    -- encodeOld(ns, d) turns the old one-record shape { bags, bagItems, bank =
    -- t | "-", bankItems, unseen } into those values (bank items in tab 6, or
    -- the first tab not unseen); a plain string is the head alone.
    local function encodeOld(ns, d)
        local K = ns.BankStock
        local out = {}
        local head = { bags = d.bags, tabs = {} }
        local unseen = {}
        for _, t in ipairs(d.unseen or {}) do unseen[t] = true; head.tabs[#head.tabs + 1] = { tab = t, seen = false } end
        if d.bags == "1" then out[#out + 1] = { g = "KSB", v = (K.encodePart(d.bagItems or {})) } end
        if type(d.bank) == "number" then
            local tab = 6
            while unseen[tab] do tab = tab + 1 end
            head.tabs[#head.tabs + 1] = { tab = tab, seen = true }
            out[#out + 1] = { g = K.tabGroup(tab), v = (K.encodePart(d.bankItems or {}, d.bank)) }
        elseif d.bank == "-" and #head.tabs == 0 then
            head.tabs[1] = { tab = 6, seen = false }
        end
        out[#out + 1] = { g = "KS", v = K.encodeHead(head) }
        return out
    end
    -- Another member's stock records as if relayed (a bundle or a head value).
    local function offerKS(ns, a, v, t)
        if type(v) == "string" then return ns.Share.offer(a, "KS", t or T0(), ns.Share.hash(v), v, true, a) end
        local r
        for _, p in ipairs(v) do r = ns.Share.offer(a, p.g, t or T0(), ns.Share.hash(p.v), p.v, true, a) end
        return r
    end
    -- The old shape back from the records (no epoch rule; tests only).
    local function snapshot(ns, a)
        local K = ns.BankStock
        local head = ns.Share.decoded(a, "KS")
        if not head then return nil end
        local d = { bags = head.bags, unseen = {}, bagItems = {}, bankItems = {}, more = 0, empty = head.empty }
        if head.bags == "1" then
            local p = ns.Share.decoded(a, "KSB")
            if p then d.bagItems = p.items; d.more = d.more + p.more end
        end
        local oldest
        for _, tab in ipairs(head.order) do
            if head.tabs[tab] then
                local p = ns.Share.decoded(a, K.tabGroup(tab))
                if p then
                    for id, q in pairs(p.items) do d.bankItems[id] = (d.bankItems[id] or 0) + q end
                    d.more = d.more + p.more
                    if p.seen and (not oldest or p.seen < oldest) then oldest = p.seen end
                end
            else
                d.unseen[#d.unseen + 1] = tab
            end
        end
        if #head.order > 0 then d.bank = oldest or "-" end
        return d
    end

    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = opts.roster })
        installGame()
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
    -- I (A) am a custodian of both kinds (C too), consent given, scope set.
    local function custodian(opts)
        opts = opts or {}
        local ns = login(opts)
        setList(ns, opts.entries or { { A, "bk" }, { C, "bk" } })
        for _, b in ipairs(opts.bags or { 0 }) do ns.Bank.setScope("bags", b, true) end
        for _, t in ipairs(opts.bank or {}) do ns.Bank.setScope("bank", t, true) end
        if opts.consent ~= false then ns.BankStock.setConsent(true) end
        return ns
    end
    local function bagsChanged() wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01) end
    local function openBank() G.bankOpen = true; wow.fire("BANKFRAME_OPENED"); wow.advance(0.01) end
    local function closeBank() wow.fire("BANKFRAME_CLOSED"); G.bankOpen = false end
    local function mine(ns) return snapshot(ns, A) end
    local function sentText()
        local out = {}
        for _, m in ipairs(wow.state.sent) do out[#out + 1] = m.msg end
        return table.concat(out, "\n")
    end
    local function rowFor(ns, id)
        for _, r in ipairs(ns.BankStock.rows()) do if r.itemID == id then return r end end
        return nil
    end
    local function reads(bag) return G.reads[bag] or 0 end

    ---------------------------------------------------------------------------
    -- 1. The custodian's side
    ---------------------------------------------------------------------------

    test("GF-012-B only the ticked scope is read; private bags and tabs never read, kept or sent", done(function()
        local ns = login()
        G.bags[0] = { { 1001, 5 }, { 1002, 3 } }
        G.bags[1] = { { 9001, 7 } }             -- private bag
        G.bags[6] = { { 2001, 20 } }            -- ticked tab
        G.bags[7] = { { 9002, 40 } }            -- private tab
        G.bags[15] = { { 9003, 1 } }            -- the account bank
        setList(ns, { { A, "bk" } })
        ns.Bank.setScope("bags", 0, true); ns.Bank.setScope("bank", 6, true)
        ns.BankStock.setConsent(true)
        openBank(); closeBank()
        eq(reads(1), 0, "private bag not read"); eq(reads(7), 0, "private tab not read"); eq(reads(15), 0, "account bank not read")
        ok(reads(0) > 0 and reads(6) > 0, "scope read")
        local d = mine(ns)
        eq(d.bagItems[1001], 5, "bag item"); eq(d.bankItems[2001], 20, "bank item")
        eq(d.bagItems[9001], nil, "private bag item not in the snapshot")
        wow.advance(40)
        local sent = sentText()
        ok(sent:find("S1~V~" .. A .. "~KS~", 1, true), "sent to the guild")
        for _, id in ipairs({ 9001, 9002, 9003 }) do
            ok(not sent:find(ns.Share.b36(id) .. ".", 1, true), "private item " .. id .. " never sent")
        end
        local saved = wow.serializeSV("GreenFangToolkitDB", GreenFangToolkitDB)
        ok(saved:find("[2001]", 1, true), "the scope tab is kept")
        ok(not saved:find("[9002]", 1, true) and not saved:find("[9001]", 1, true), "private items never saved")
        eq(ns.Share.isLocalGroup("KS"), true, "GF Sync leaves it out")
        for _, m in ipairs(wow.state.sent) do ok(m.chatType == "GUILD" or m.chatType == "WHISPER", "guild message only") end
        -- The slot numbers are not in the value.
        ok(not ns.Share.get(A, "KS").v:find("6:", 1, true), "no slot / bag position")
    end))

    test("GF-012-B nothing is read before the yes, by a member, or for a kind the master did not give", done(function()
        local ns = login()
        G.bags[0] = { { 1001, 5 } }
        bagsChanged()
        eq(reads(0), 0, "not a custodian: nothing read")
        setList(ns, { { A, "b" } })
        ns.Bank.setScope("bags", 0, true)
        eq(ns.Bank.setScope("bank", 6, true), "not-custodian", "bank not given")
        bagsChanged()
        eq(reads(0), 0, "no yes yet: nothing read")
        eq(ns.Share.get(A, "KS"), nil, "nothing stored")
        ns.BankStock.setConsent(true)
        ok(reads(0) > 0, "read after the yes")
        openBank()
        eq(reads(6), 0, "bank not given: never read")
    end))

    test("GF-012-B a bank never seen is 還沒看過, not 0; the time it was seen is kept", done(function()
        local ns = custodian({ bags = { 0 }, bank = { 6, 7 } })
        G.bags[0] = { { 1001, 5 } }
        G.bags[6] = { { 2001, 20 } }
        bagsChanged()
        local d = mine(ns)
        eq(d.bank, "-", "bank never seen"); eq(#d.unseen, 2, "both tabs unseen")
        eq(d.bankItems[2001], nil, "no bank count at all (not 0)")
        local r = rowFor(ns, 1001); ok(r, "bags shown")
        eq(rowFor(ns, 2001), nil, "the bank item is not listed as anything")
        ok(ns.BankStock.mineText():find("銀行還沒看過", 1, true), "my line says it: " .. ns.BankStock.mineText())
        local h = ns.BankStock.holders()[1]
        eq(h.bankUnseen, true, "others see 還沒看過")
        -- Tab 7 has no slots now (not bought): still unseen after the bank opened.
        G.slots[7] = 0
        local t1 = T0()
        openBank(); closeBank()
        d = mine(ns)
        eq(d.bank, t1, "seen time"); eq(d.unseen[1], 7, "tab 7 still unseen"); eq(#d.unseen, 1, "one")
        eq(rowFor(ns, 2001).total, 20, "bank item now")
        -- Later, bank closed: the old count with its old time (never as new).
        wow.advance(3600)
        G.bags[0][2] = { 1003, 1 }
        bagsChanged()
        d = mine(ns)
        eq(d.bank, t1, "the bank time did not move"); eq(d.bankItems[2001], 20, "kept")
        ok(ns.Recipes.agoText(d.bank):find("小時前", 1, true), "shown as an hour ago")
    end))

    test("GF-012-B bound items are not listed", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1001, 5, true }, { 1002, 2 }, { 1001, 3 } }
        bagsChanged()
        local d = mine(ns)
        eq(d.bagItems[1001], 3, "only the unbound stack"); eq(d.bagItems[1002], 2, "unbound")
        G.bags[0] = { { 1004, 1, true } }
        bagsChanged()
        eq(next(mine(ns).bagItems), nil, "all bound: nothing")
        eq(select(2, ns.BankStock.rows()), "empty", "why: nothing tradeable")
    end))

    test("GF-012-B an unchanged snapshot is not computed into a new record or sent again; combat waits", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1001, 5 } }
        bagsChanged()
        wow.advance(40)
        local before = ns.BankStock.stats.published
        wow.state.sent = {}
        for _ = 1, 5 do bagsChanged() end
        wow.advance(40)
        eq(ns.BankStock.stats.published, before, "nothing new stored")
        ok(not sentText():find("~KS~", 1, true), "nothing sent again")
        -- A roster update alone reads nothing.
        local r0 = reads(0)
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.01)
        eq(reads(0), r0, "no read on a roster update")
        -- In combat: nothing, then one scan after.
        wow.enterCombat()
        G.bags[0][1] = { 1001, 6 }
        bagsChanged()
        eq(reads(0), r0, "nothing read in combat")
        eq(mine(ns).bagItems[1001], 5, "old value in combat")
        wow.leaveCombat(); wow.advance(0.01)
        eq(mine(ns).bagItems[1001], 6, "read after combat")
    end))

    test("GF-012-B a full scope: slots read and time of one scan (measured)", done(function()
        local ns = custodian({ bags = { 0, 1, 2, 3, 4, 5 }, bank = { 6, 7, 8, 9, 10, 11, 12, 13, 14 } })
        local id = 100000
        for bag = 0, 14 do
            G.bags[bag] = {}
            for slot = 1, G.slots[bag] do id = id + 1; G.bags[bag][slot] = { id, 1 + slot % 20 } end
        end
        openBank()
        G.reads = {}
        local t0 = os.clock()
        local n = 20
        for _ = 1, n do G.bags[0][1][2] = G.bags[0][1][2] + 1; ns.BankStock.readBank(); ns.BankStock.scan() end
        local ms = (os.clock() - t0) * 1000 / n
        local total = 0
        for _, v in pairs(G.reads) do total = total + v end
        local per = total / n
        eq(per, 65 + 9 * 98, "every slot of the scope once per bank scan (bags 65 + bank 882)")
        -- GF-012-C: no 150 limit any more; every kind is listed (one part per source).
        local d = mine(ns)
        eq(d.more, 0, "nothing left out")
        local kinds = 0
        for _ in pairs(d.bagItems) do kinds = kinds + 1 end
        for _ in pairs(d.bankItems) do kinds = kinds + 1 end
        eq(kinds, 65 + 882, "every kind listed")
        realPrint(string.format("     [GF-012-B measure] full scope (bags 0-5 = 65 slots, bank tabs 6-14 = 882 slots): %d item reads per bank-open scan, %.2f ms; all %d kinds listed",
            per, ms, kinds))
        -- A bag change alone reads only the bags (bank closed).
        closeBank()
        G.reads = {}
        bagsChanged()
        local bagReads = 0
        for bag, v in pairs(G.reads) do if bag <= 5 then bagReads = bagReads + v else ok(false, "bank read on a bag change while closed? " .. bag) end end
        ok(bagReads == 65, "bags only: " .. bagReads)
    end))

    -- GF-012-C: the 150-item limit is gone (tests/addon/gf012c_tests.lua has the part limits).

    ---------------------------------------------------------------------------
    -- 2. The guild's side
    ---------------------------------------------------------------------------

    test("GF-012-B two custodians add up; one custodian is never counted twice", done(function()
        local ns = custodian({ bags = { 0 }, bank = { 6 } })
        G.bags[0] = { { 1001, 3 } }
        G.bags[6] = { { 1001, 2 } }
        openBank(); closeBank()
        local t = T0()
        local v = encodeOld(ns, { bags = "1", bagItems = { [1001] = 5, [1005] = 1 } })
        eq(offerKS(ns, C, v, t), "new", "C's snapshot")
        local r = rowFor(ns, 1001)
        eq(r.total, 10, "3 + 2 (mine, two places) + 5 (C)")
        eq(#r.places, 2, "two custodians")
        eq(ns.BankStock.whereText(r), "測試甲 背包 3、銀行 2｜測試丙 背包 5", "where (most first, then by id)")
        -- The same record relayed again, and a newer one with the same items: no double count.
        offerKS(ns, C, v, t)
        for _, p in ipairs(v) do from(ns, PEER_B, vMsg(ns, C, p.g, t + 5, p.v)) end
        eq(rowFor(ns, 1001).total, 10, "still 10")
        eq(rowFor(ns, 1005).total, 1, "C's other item")
    end))

    test("GF-012-B revoked, kinds taken away, left the guild: their stock is gone", done(function()
        local ns = custodian({ bags = { 0 } })
        local t = T0()
        offerKS(ns, C, encodeOld(ns, { bags = "1", bagItems = { [1005] = 4 }, bank = t, bankItems = { [1006] = 9 } }), t)
        ok(rowFor(ns, 1005) and rowFor(ns, 1006), "shown")
        -- The master takes the bank away from C: the old snapshot (older than the change) goes.
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "b" } })
        eq(rowFor(ns, 1006), nil, "bank gone"); eq(rowFor(ns, 1005), nil, "the snapshot is older than the change")
        wow.advance(5)
        offerKS(ns, C, (encodeOld(ns, { bags = "1", bagItems = { [1005] = 4 }, bank = t, bankItems = { [1006] = 9 } })))
        ok(rowFor(ns, 1005), "a newer snapshot: bags back"); eq(rowFor(ns, 1006), nil, "bank still not given")
        -- Revoked.
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "b", false } })
        eq(rowFor(ns, 1005), nil, "revoked: gone")
        -- Appointed again: the old snapshot does not come back.
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "b" } })
        eq(rowFor(ns, 1005), nil, "re-appointed: old snapshot not shown")
        wow.advance(5)
        offerKS(ns, C, (encodeOld(ns, { bags = "1", bagItems = { [1005] = 4 } })))
        ok(rowFor(ns, 1005), "fresh one shown")
        -- Left the guild roster.
        table.remove(wow.state.roster, 3)
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(5)
        eq(rowFor(ns, 1005), nil, "not in the roster: gone")
    end))

    test("GF-012-B my own revocation / scope off sends an empty snapshot; my kept bank copy goes", done(function()
        local ns = custodian({ bags = { 0 }, bank = { 6 } })
        G.bags[0] = { { 1001, 3 } }; G.bags[6] = { { 2001, 2 } }
        openBank(); closeBank()
        local m = ns.BankStock.mine()
        ok(m.bank[6], "bank kept")
        ns.Bank.setScope("bank", 6, false); wow.advance(0.01)
        eq(m.bank[6], nil, "a tab out of the scope: its copy is gone")
        eq(mine(ns).bank, nil, "no bank in the snapshot")
        ns.BankStock.toggle(false)
        eq(ns.Share.get(A, "KS").v, ns.BankStock.EMPTY, "sharing off: empty snapshot")
        ns.BankStock.setConsent(true)
        wow.advance(5)
        setList(ns, { { A, "bk", false } }); wow.advance(0.01)
        eq(ns.Share.get(A, "KS").v, ns.BankStock.EMPTY, "revoked: empty snapshot")
        eq(next(ns.BankStock.mine().bank), nil, "nothing kept")
    end))

    test("GF-012-B data from a non-custodian is not shown; malformed or too big is refused", done(function()
        local ns = custodian({ bags = { 0 } })
        local t = T0()
        eq(offerKS(ns, D, encodeOld(ns, { bags = "1", bagItems = { [7001] = 1 } }), t), "new", "stored (it may be relayed)")
        eq(rowFor(ns, 7001), nil, "D is not a custodian: not shown")
        ns.BankStock.diagText()
        ok(ns.BankStock.stats.ignored >= 1, "counted as not shown")
        local bad = {
            "2;1;;;0;1.1;",                 -- unknown format
            "1;1;;;0;1.1",                  -- six fields
            "1;x;;;0;;",                    -- bags flag
            "1;;;;0;1.1;",                  -- bag items without bags
            "1;1;;;0;;1.1",                 -- bank items without bank
            "1;1;-;z;0;;",                  -- tab z
            "1;1;-;66;0;;",                 -- the same tab twice
            "1;1;;;0;1.1,1.2;",             -- the same item twice
            "1;1;;;0;1.0;",                 -- 0
            "1;1;;;0;1.255s;",              -- over MAX_QTY
            "1;1;;;1jl;;",                  -- more over the limit (2001)
            "1;1;zzzzzz;;0;;",              -- a bank time in the future
            "1;1;;;0;" .. string.rep("1.1,", 600) .. "1.1;", -- too long
        }
        for i, v in ipairs(bad) do
            eq(ns.BankStock.decode("KS", v), nil, "refused #" .. i)
            eq(offerKS(ns, C, v, t + i), "invalid", "not stored #" .. i)
        end
        local many = {}
        for i = 1, 151 do many[#many + 1] = ns.Share.b36(i) .. ".1" end
        eq(ns.BankStock.decode("KS", "1;1;;;0;" .. table.concat(many, ",") .. ";"), nil, "151 entries refused")
        eq(ns.Share.get(C, "KS"), nil, "nothing of C stored")
        eq(ns.BankStock.decode("KS", ns.BankStock.EMPTY).empty, true, "the empty value is fine")
    end))

    ---------------------------------------------------------------------------
    -- 3. The confirm box and old saves
    ---------------------------------------------------------------------------

    test("GF-012-B the confirm box: asked once, 確定 starts, 取消 stops, the switch asks again", done(function()
        local ns = login()
        G.bags[0] = { { 1001, 5 } }
        setList(ns, { { A, "bk" } })
        ns.Framework.open("bank")
        local c = ns.BankUI.controls
        ns.BankUI.setView("setup") -- GF-012-C: the scope has its own view
        local f = ns.Widgets.confirmFrame()
        ok(not (f and f:IsShown()), "no scope: not asked on the page")
        wow.click(c.scope.bags[1]) -- 行囊
        f = ns.Widgets.confirmFrame()
        ok(f and f:IsShown(), "asked at the first tick")
        eq(f.text:GetText(), ns.BankStock.CONFIRM_TEXT, "the words")
        ok(f.text:GetText():find("物品與數量分享給公會", 1, true), "says what is shared")
        eq(reads(0), 0, "nothing read while asking")
        wow.click(f.no)
        eq(ns.BankStock.mine().consent, false, "取消 = no")
        bagsChanged()
        eq(reads(0), 0, "no: nothing read"); eq(ns.Share.get(A, "KS"), nil, "nothing sent")
        ns.BankUI.refresh()
        ok(c.share:IsShown() and not c.share.checked and not c.share.disabled, "the switch is there, off, usable")
        ns.Framework.open("supply"); ns.Framework.open("bank")
        ok(not f:IsShown(), "declined: not asked again on the page")
        wow.click(c.share)
        ok(f:IsShown(), "the switch asks")
        wow.click(f.yes)
        eq(ns.BankStock.mine().consent, true, "確定 = yes")
        ok(reads(0) > 0, "read now"); eq(mine(ns).bagItems[1001], 5, "shared")
        eq(c.share.checked, true, "switch on")
        ok(c.mine:GetText():find("我分享了：背包 1 種", 1, true), "what I share: " .. c.mine:GetText())
        ok(c.scopeNote:GetText():find("物品與數量", 1, true), "the short line by the scope")
        -- ESC / the X counts as no as well.
        wow.click(c.share) -- off
        eq(ns.BankStock.mine().consent, false, "off")
        wow.click(c.share)
        f:Hide()
        eq(ns.BankStock.mine().consent, false, "closed without 確定 = no")
        -- All unticked, then ticked again: asked again.
        ns.BankStock.setConsent(true)
        wow.click(c.scope.bags[1]) -- off: the scope is empty
        eq(ns.BankStock.mine().consent, nil, "an empty scope forgets the yes")
        wow.click(c.scope.bags[1])
        ok(f:IsShown(), "asked again")
    end))

    test("GF-012-B old saves load: a phase-1 scope asks before anything; broken stock data is dropped", done(function()
        local saved = { GreenFangToolkitDB = { bank = { v = 1, guilds = {}, scope = { ["Player-" .. A] = { bags = { [0] = true }, bank = { [6] = true } } } } } }
        local ns = login({ saved = saved })
        G.bags[0] = { { 1001, 5 } }
        setList(ns, { { A, "bk" } })
        bagsChanged()
        eq(reads(0), 0, "phase-1 scope: nothing read without the yes")
        eq(ns.BankStock.myState(), "ask", "asks")
        eq(ns.Share.get(A, "KS"), nil, "nothing sent")
        -- Broken stock fields.
        saved = { GreenFangToolkitDB = { bank = { v = 1, guilds = {}, scope = {}, stock = { ["Player-" .. A] = { consent = "yes", bank = { [6] = "x", [7] = { t = 1 } } } } } } }
        ns = login({ saved = saved })
        local m = ns.BankStock.mine()
        eq(m.consent, nil, "a strange consent is not a yes")
        eq(next(m.bank), nil, "broken bank copies dropped")
        saved = { GreenFangToolkitDB = { bank = { v = 1, guilds = {}, scope = {}, stock = "x" } } }
        ns = login({ saved = saved })
        ok(ns.BankStock.mine(), "a broken stock table is replaced")
        ok(ns.Bank.diagText():find("庫存：", 1, true), "diagnostics still work")
    end))

    ---------------------------------------------------------------------------
    -- 4. The page
    ---------------------------------------------------------------------------

    test("GF-012-B page: rows, search, wheel with 「還有 N 項」, 聯絡 whispers the custodian, empty states", done(function()
        local ns = login()
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.list[1], "no list yet")
        setList(ns, {})
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.nobody[1], "nobody appointed")
        setList(ns, { { C, "bk" } })
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.none[1], "C has not shared")
        wow.advance(1)
        offerKS(ns, C, ns.BankStock.EMPTY)
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.noscope[1], "C has no scope")
        wow.advance(1)
        offerKS(ns, C, "2;;6-")
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.unseen[1], "C has not opened the bank")
        wow.advance(1)
        local items = {}
        for i = 1, UI.STOCK_ROWS + 4 do items[5000 + i] = 100 - i end -- GF-012-C: the page holds more rows
        offerKS(ns, C, (encodeOld(ns, { bags = "1", bagItems = items })))
        eq(c.stock.kind, nil, "rows shown")
        eq(#c.stockRows, UI.STOCK_ROWS, "6 pooled rows")
        eq(c.stockRows[1].itemID, 5001, "most first")
        eq(c.stockRows[1].count:GetText(), "99", "total")
        eq(c.stockRows[1].who:GetText(), "測試丙", "who (GF-012-C: the places are in the tooltip)")
        eq(c.stockRows[1].ago:GetText(), "剛剛", "how long ago")
        eq(c.stockMore:GetText(), "還有 4 項，用滑鼠滾輪往下看", "the more line")
        c.stockRows[1]:GetScript("OnMouseWheel")(c.stockRows[1], -1)
        eq(c.stockRows[1].itemID, 5002, "one down")
        eq(c.stockMore:GetText(), "還有 3 項，用滑鼠滾輪往下看", "three more")
        for _ = 1, 10 do UI.scrollStock(-1) end
        eq(c.stockOffset, 4, "stops"); eq(c.stockMore:GetText(), "", "no line at the end")
        -- Search.
        c.search:SetText("5003"); c.search:GetScript("OnTextChanged")(c.search); wow.advance(1)
        eq(c.stockRows[1].itemID, 5003, "found"); ok(not c.stockRows[2]:IsShown(), "only one")
        c.search:SetText("沒有這個"); c.search:GetScript("OnTextChanged")(c.search); wow.advance(1)
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.search[1], "no match")
        c.search:SetText(""); c.search:GetScript("OnTextChanged")(c.search); wow.advance(1)
        -- 聯絡: the same whisper box as 調貨所 (Supply.contact).
        ok(not c.stockRows[1].contact.disabled, "聯絡 on")
        wow.click(c.stockRows[1].contact)
        eq(#G.whispers, 1, "whisper box opened")
        eq(G.whispers[1].name, "測試丙-測試伺服器", "to the custodian")
        ok(G.whispers[1].text:find("臨時黑箱", 1, true), "the text: " .. G.whispers[1].text)
        -- No frames created by redraws.
        local before = #wow.allObjects()
        for _ = 1, 5 do UI.refresh() end
        eq(#wow.allObjects(), before, "no new frames on redraw")
    end))

    test("GF-012-B page: my own rows show what I share, 聯絡 off for me; 10 custodians x 100 items draw time", done(function()
        local roster = wow.defaultRoster()
        for i = 5, 14 do
            roster[i] = { name = "保管" .. i .. "-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
                zone = "杜洛塔", online = true, guid = string.format("Player-0000-%08X", 0x2000 + i) }
        end
        local ns = custodian({ roster = roster, bags = { 0 } })
        G.bags[0] = { { 1001, 2 } }
        bagsChanged()
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        eq(c.stockRows[1].itemID, 1001, "my item"); ok(c.stockRows[1].contact.disabled, "聯絡 off for my own")
        -- The list holds 10 enabled custodians at most: the 10 others (I step down).
        local entries = { { A, "bk", false } }
        for i = 5, 14 do entries[#entries + 1] = { string.format("0000-%08X", 0x2000 + i), "bk" } end
        setList(ns, entries)
        wow.advance(1)
        bagsChanged() -- my snapshot after the new list
        for i = 5, 14 do
            local items = {}
            for k = 1, 100 do items[10000 + (i * 37 + k) % 300] = k end
            offerKS(ns, string.format("0000-%08X", 0x2000 + i), (encodeOld(ns, { bags = "1", bagItems = items, bank = T0(), bankItems = { [20000 + i] = 1 } })))
        end
        local t0 = os.clock()
        local n = 10
        for _ = 1, n do ns.BankStock.invalidate(); UI.refresh() end
        local ms = (os.clock() - t0) * 1000 / n
        local rows = ns.BankStock.rows()
        ok(#rows > 100, "many items: " .. #rows)
        eq(#c.stockRows, UI.STOCK_ROWS, "still 6 rows")
        local t1 = os.clock()
        for _ = 1, n do UI.refresh() end
        local cached = (os.clock() - t1) * 1000 / n
        realPrint(string.format("     [GF-012-B measure] 10 custodians x 100 items (%d rows): page draw %.2f ms with the list rebuilt, %.2f ms when nothing changed",
            #rows, ms, cached))
        local total = 0
        for _, r in ipairs(rows) do total = total + r.total end
        local expect = 10 -- one bank item each (mine is gone: I am not on the list now)
        for i = 5, 14 do for k = 1, 100 do expect = expect + k end end
        eq(total, expect, "every unit counted once")
    end))

    ---------------------------------------------------------------------------
    -- 5. Diagnostics and the dropped event
    ---------------------------------------------------------------------------

    test("GF-012-B 同步與診斷: opaque window, the stock line, no PLAYERREAGENTBANKSLOTS_CHANGED", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1001, 2 } }
        bagsChanged()
        local w = ns.Diag.open()
        eq(w.gfForm, true, "the form colour (opaque)")
        local col = w.gfOpaque._color or (w.gfOpaque._vertex)
        if col and col[4] then eq(col[4], 1, "alpha 1") end
        local text = ns.Bank.diagText()
        ok(not text:find("尚未開放", 1, true), "the old line is gone")
        ok(text:find("庫存：1 種物品、1 位保管人有資料", 1, true), "the new line: " .. text)
        ok(text:find("我：分享中", 1, true), "my sharing")
        ok(not text:find("0000-", 1, true) and not text:find("Player-", 1, true), "no GUID")
        for _, e in ipairs(ns.Supply.SOURCE_EVENTS) do ok(e ~= "PLAYERREAGENTBANKSLOTS_CHANGED", "not asked for") end
        ok(not ns.Supply.diagText():find("PLAYERREAGENTBANKSLOTS_CHANGED", 1, true), "not in the diagnostics")
        local registered = false
        for _, f in ipairs(wow.state.frames) do if f._events and f._events.PLAYERREAGENTBANKSLOTS_CHANGED then registered = true end end
        eq(registered, false, "registered nowhere")
        ok(ns.Supply.SOURCE_EVENTS[1] == "BANKFRAME_OPENED" and #ns.Supply.SOURCE_EVENTS == 7, "the other events are kept")
    end))
end
