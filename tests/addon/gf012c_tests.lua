-- GF-012-C: 臨時黑箱 stock, owner 2026-11-28. (1) No 150-item limit: a head
-- record KS plus one part per source (KSB, KS6 .. KS14); only the part that
-- changed is stored and sent again; revoked / sharing off / a tab out of the
-- scope clears the others' copy; a tab never seen stays 還沒看過; bad values
-- are refused (0.16.15's format 1 too). (2) 聯絡 picks the custodian (a menu
-- when several have it; online first, the most first; me grey). (3) The page:
-- 庫存 / 保管人與分享設定, many reused rows, filters (name, class, custodian,
-- online), cached. (4) 調貨看板 lists the stock, marked 黑箱, with its filter.
-- Offline only (made-up names, GUIDs and item IDs); nothing checked in game.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local A, B, C, D, E, F = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D", "0000-0000000E", "0000-0000000F"
    local PEER_B = "測試乙-測試伺服器"

    local function roster()
        local r = wow.defaultRoster()
        r[#r + 1] = { name = "測試戊-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
            zone = "奧格瑪", online = true, guid = "Player-" .. E }
        r[#r + 1] = { name = "測試己-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
            zone = "奧格瑪", online = true, guid = "Player-" .. F }
        return r
    end

    -- The fake client: bags 0-5 always, bank tabs 6-14 only while open.
    -- Item classes: 5 (材料) for IDs ending in 0-4, 0 (消耗品) for the rest.
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
        G.classCalls = 0
        C_Item = {
            GetItemIconByID = function() return 134939 end,
            GetItemNameByID = function(id) return "物品" .. id end,
            RequestLoadItemDataByID = function() end,
            GetItemInfoInstant = function(id)
                G.classCalls = G.classCalls + 1
                return id, "類別", "子類別", "", 134939, (id % 10) < 5 and 5 or 0, 0
            end,
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
    local function setList(ns, entries)
        local t = T0()
        from(ns, PEER_B, vMsg(ns, B, "K", t, list(ns, t, entries)))
        return t
    end
    local function offer(ns, a, g, v, t)
        return ns.Share.offer(a, g, t or T0(), ns.Share.hash(v), v, true, a)
    end
    -- Somebody's whole stock: bags = { [id] = q } or nil, tabs = { [tab] = { [id] = q } | false (never seen) }.
    local function offerStock(ns, a, bags, tabs, t)
        local K = ns.BankStock
        t = t or T0()
        local head = { bags = bags and "1" or nil, tabs = {} }
        if bags then offer(ns, a, "KSB", (K.encodePart(bags)), t) end
        for tab, items in pairs(tabs or {}) do
            head.tabs[#head.tabs + 1] = { tab = tab, seen = items ~= false }
            if items then offer(ns, a, K.tabGroup(tab), (K.encodePart(items, t)), t) end
        end
        return offer(ns, a, "KS", K.encodeHead(head), t)
    end

    local function login(opts)
        opts = opts or {}
        wow.reset({ roster = opts.roster or roster() })
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
    local function custodian(opts)
        opts = opts or {}
        local ns = login(opts)
        setList(ns, opts.entries or { { A, "bk" }, { C, "bk" }, { E, "bk" }, { F, "bk" } })
        for _, b in ipairs(opts.bags or { 0 }) do ns.Bank.setScope("bags", b, true) end
        for _, t in ipairs(opts.bank or {}) do ns.Bank.setScope("bank", t, true) end
        if opts.consent ~= false then ns.BankStock.setConsent(true) end
        return ns
    end
    local function bagsChanged() wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01) end
    local function openBank() G.bankOpen = true; wow.fire("BANKFRAME_OPENED"); wow.advance(0.01) end
    local function closeBank() wow.fire("BANKFRAME_CLOSED"); G.bankOpen = false end
    -- Groups of mine that went out (V or B messages) since the last reset.
    local function sentGroups()
        local out = {}
        for _, m in ipairs(wow.state.sent) do
            local g = m.msg:match("^S1~[VB]~" .. A:gsub("%-", "%%-") .. "~(KS%w*)~")
            if g then out[g] = (out[g] or 0) + 1 end
        end
        return out
    end
    local function rowFor(ns, id)
        for _, r in ipairs(ns.BankStock.rows()) do if r.itemID == id then return r end end
        return nil
    end
    local function fill(bag, first, n, q)
        G.bags[bag] = {}
        for slot = 1, n do G.bags[bag][slot] = { first + slot, q or 1 } end
    end
    local function countKeys(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end

    ---------------------------------------------------------------------------
    -- 1. No limit: parts, sizes, only the changed part goes out
    ---------------------------------------------------------------------------

    test("GF-012-C more than 150 kinds: every one is listed (bags + 3 tabs, 359 kinds)", done(function()
        local ns = custodian({ bags = { 0, 1, 2, 3, 4, 5 }, bank = { 6, 7, 8 } })
        local id = 400000
        for bag = 0, 5 do fill(bag, id, G.slots[bag]); id = id + 1000 end
        for tab = 6, 8 do fill(tab, id, 98); id = id + 1000 end
        openBank(); closeBank()
        local rows = ns.BankStock.rows()
        eq(#rows, 65 + 3 * 98, "every kind is a row")
        ok(#rows > 150, "past the old 150")
        local d = ns.Share.decoded(A, "KS")
        eq(d.bags, "1", "head: bags read"); eq(#d.order, 3, "head: three tabs")
        for _, tab in ipairs({ 6, 7, 8 }) do eq(d.tabs[tab], true, "tab " .. tab .. " seen") end
        eq(ns.Share.decoded(A, "KSB").n, 65, "bags part: 65 kinds")
        eq(ns.Share.decoded(A, "KS7").n, 98, "tab part: 98 kinds")
        eq(ns.BankStock.stats.truncated, 0, "nothing left out")
        ok(not ns.BankStock.mineText():find("沒列出", 1, true), "mine: " .. ns.BankStock.mineText())
        ok(ns.BankStock.mineText():find("背包 65 種", 1, true) and ns.BankStock.mineText():find("銀行 294 種", 1, true), "mine counts")
    end))

    test("GF-012-C sizes: worst and usual part, the head, the messages (measured)", done(function()
        local ns = login()
        local K = ns.BankStock
        -- Worst: MAX_ENTRIES entries, the largest item IDs a Lua number keeps as an integer ID (2^31-1 range), 99999 each.
        local worst = {}
        for i = 1, K.MAX_ENTRIES do worst[2147483647 - i] = 99999 end
        local v, more = K.encodePart(worst, T0())
        eq(more, 0, "all fit")
        ok(#v <= K.MAX_VALUE, "worst part within the limit: " .. #v)
        ok(K.decodePart("KS6", v), "decodes")
        -- One over: left out and counted, never an error.
        worst[1] = 5
        local v2, more2 = K.encodePart(worst, T0())
        eq(more2, 1, "one left out"); ok(#v2 <= K.MAX_VALUE, "still fits")
        eq(K.decodePart("KS6", v2).more, 1, "told")
        -- Usual: a full tab of 6-digit IDs and stacks up to 200; the bags of the probe (65 slots).
        local tab, bags = {}, {}
        for i = 1, 98 do tab[200000 + i * 37] = 1 + (i * 13) % 200 end
        for i = 1, 65 do bags[150000 + i * 11] = 1 + i % 20 end
        local vt, vb = K.encodePart(tab, T0()), K.encodePart(bags)
        local allTabs = {}
        for t = 6, 14 do allTabs[#allTabs + 1] = { tab = t, seen = true } end
        local head = K.encodeHead({ bags = "1", tabs = allTabs })
        ok(#head <= K.MAX_HEAD, "head within its limit: " .. #head)
        -- Share's messages: one V when it fits, else B + D pieces (the header is about 40 bytes).
        local per = ns.Share.MAX_BYTES - #("S1~D~" .. A .. "~KS14~" .. ns.Share.b36(T0()) .. "~zz~")
        local function msgs(value)
            local single = #("S1~V~" .. A .. "~KS14~" .. ns.Share.b36(T0()) .. "~" .. ns.Share.hash(value) .. "~" .. value)
            if single <= ns.Share.MAX_BYTES then return 1 end
            return 1 + math.ceil(#value / per)
        end
        local all = msgs(head) + msgs(vb) + 9 * msgs(vt)
        local allWorst = msgs(head) + 10 * msgs(v)
        realPrint(string.format("     [GF-012-C measure] part worst %d bytes = %d messages (limit %d bytes, %d entries); usual full tab (98 kinds) %d bytes = %d messages; bags 65 kinds %d bytes = %d messages; head %d bytes = %d message",
            #v, msgs(v), K.MAX_VALUE, K.MAX_ENTRIES, #vt, msgs(vt), #vb, msgs(vb), #head, msgs(head)))
        realPrint(string.format("     [GF-012-C measure] everything at once (bags + 9 full tabs, first share / 6 h resend of each): usual %d messages (~%d s at %.1f/s after a burst of %d), worst %d messages; a bag change: %d",
            all, math.ceil(math.max(0, all - ns.Share.ALLOWANCE) / ns.Share.REFILL), ns.Share.REFILL, ns.Share.ALLOWANCE, allWorst, msgs(head) * 0 + msgs(vb)))
        ok(msgs(v) <= 64, "Share takes it (64 pieces at most)")
    end))

    test("GF-012-C only the part that changed is stored and sent again", done(function()
        local ns = custodian({ bags = { 0 }, bank = { 6, 7 } })
        fill(0, 1000, 5); fill(6, 2000, 5); fill(7, 3000, 5)
        openBank(); closeBank()
        wow.advance(40)
        local sent = sentGroups()
        ok(sent.KS and sent.KSB and sent.KS6 and sent.KS7, "first share: head and three parts: " .. (function()
            local o = {}
            for _, m in ipairs(wow.state.sent) do o[#o + 1] = m.msg:sub(1, 40) end
            return table.concat(o, " | ")
        end)())
        local ksbT, ks6T, ks7T, headT = ns.Share.get(A, "KSB").h, ns.Share.get(A, "KS6").h, ns.Share.get(A, "KS7").h, ns.Share.get(A, "KS").h
        -- A bag change: only KSB.
        wow.state.sent = {}
        G.bags[0][1][2] = 9
        bagsChanged(); wow.advance(40)
        sent = sentGroups()
        eq(sent.KSB, 1, "bags part sent")
        eq(sent.KS6, nil, "tab 6 not sent"); eq(sent.KS7, nil, "tab 7 not sent"); eq(sent.KS, nil, "head not sent")
        ok(ns.Share.get(A, "KSB").h ~= ksbT, "bags part changed")
        eq(ns.Share.get(A, "KS6").h, ks6T, "tab 6 same"); eq(ns.Share.get(A, "KS").h, headT, "head same")
        -- A change in tab 7 (bank open): only KS7.
        wow.state.sent = {}
        G.bags[7][2][2] = 50
        openBank(); closeBank(); wow.advance(40)
        sent = sentGroups()
        eq(sent.KS7, 1, "tab 7 sent"); eq(sent.KS6, nil, "tab 6 not"); eq(sent.KSB, nil, "bags not"); eq(sent.KS, nil, "head not")
        ok(ns.Share.get(A, "KS7").h ~= ks7T, "tab 7 changed")
        -- Nothing changed: nothing at all.
        wow.state.sent = {}
        bagsChanged(); openBank(); closeBank(); wow.advance(40)
        eq(next(sentGroups()), nil, "nothing sent again")
    end))

    test("GF-012-C a tab out of the scope, sharing off, revoked: emptied for the others; never seen stays 還沒看過", done(function()
        local ns = custodian({ bags = { 0 }, bank = { 6, 7, 8 } })
        fill(0, 1000, 3); fill(6, 2000, 3); fill(7, 3000, 3)
        G.slots[8] = 0 -- not bought: never seen
        openBank(); closeBank()
        local head = ns.Share.decoded(A, "KS")
        eq(head.tabs[8], false, "tab 8 never seen (not 0)")
        eq(ns.Share.get(A, "KS8"), nil, "no part for it")
        ok(rowFor(ns, 2001) and rowFor(ns, 3001), "both tabs listed")
        ok(ns.BankStock.mineText():find("1 個分頁還沒看過", 1, true), "mine says it: " .. ns.BankStock.mineText())
        -- Tab 7 out of the scope.
        ns.Bank.setScope("bank", 7, false); wow.advance(0.01)
        eq(ns.Share.get(A, "KS7").v, ns.BankStock.EMPTY_PART, "tab 7 emptied")
        eq(ns.Share.decoded(A, "KS").tabs[7], nil, "head without it")
        eq(rowFor(ns, 3001), nil, "gone from the list"); ok(rowFor(ns, 2001), "tab 6 still")
        eq(ns.BankStock.mine().bank[7], nil, "my copy gone")
        -- Sharing off: every part empty, the head empty.
        ns.BankStock.toggle(false)
        eq(ns.Share.get(A, "KS").v, ns.BankStock.EMPTY, "head empty")
        eq(ns.Share.get(A, "KSB").v, ns.BankStock.EMPTY_PART, "bags emptied")
        eq(ns.Share.get(A, "KS6").v, ns.BankStock.EMPTY_PART, "tab 6 emptied")
        eq(#ns.BankStock.rows(), 0, "nothing listed")
        -- Somebody else revoked: the others see nothing of them (the epoch rule), even parts sent later with old times.
        local t = T0()
        offerStock(ns, C, { [5001] = 4 }, { [6] = { [5002] = 7 }, [9] = false }, t)
        ok(rowFor(ns, 5001) and rowFor(ns, 5002), "C listed")
        local h
        for _, x in ipairs(ns.BankStock.holders()) do if x.a == C then h = x end end
        eq(h.unseen[1], 9, "C's tab 9 never seen"); eq(h.state, "data", "C has data")
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "bk", false } })
        eq(rowFor(ns, 5001), nil, "revoked: gone"); eq(rowFor(ns, 5002), nil, "bank too")
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "bk" } })
        offer(ns, C, "KS6", (ns.BankStock.encodePart({ [5002] = 7 }, t)), t)
        eq(rowFor(ns, 5002), nil, "re-appointed: the old parts do not come back")
    end))

    test("GF-012-C a part announced but not here yet is not a 0; a part the head does not list is not shown", done(function()
        local ns = custodian()
        local K = ns.BankStock
        local t = T0()
        offer(ns, C, "KS", K.encodeHead({ bags = "1", tabs = { { tab = 6, seen = true } } }), t)
        local h
        for _, x in ipairs(K.holders()) do if x.a == C then h = x end end
        eq(#h.waiting, 2, "bags and tab 6 waiting")
        eq(next(h.bags), nil, "no count yet")
        offer(ns, C, "KS7", (K.encodePart({ [7777] = 3 }, t)), t)
        eq(rowFor(ns, 7777), nil, "tab 7 not in the head: not shown")
        offer(ns, C, "KSB", (K.encodePart({ [6666] = 2 })), t)
        eq(rowFor(ns, 6666).total, 2, "bags arrived")
    end))

    test("GF-012-C bad values are refused, never stored (0.16.15's format 1 too)", done(function()
        local ns = custodian()
        local K = ns.BankStock
        local t = T0()
        local badHeads = {
            "1;1;;;0;1.1;",       -- 0.16.15's format 1
            "1;;;;0;;",           -- its empty value
            "3;1;",               -- unknown format
            "2;x;",               -- bags flag
            "2;1;5",              -- tab 5 is a bag
            "2;1;66",             -- the same tab twice
            "2;1;6--",            -- two marks
            "2;1;6A",             -- not b36
            "2;1",                -- two fields
            "2;1;" .. string.rep("6", 80), -- too long
        }
        for i, v in ipairs(badHeads) do
            eq(K.decode("KS", v), nil, "head refused #" .. i)
            eq(offer(ns, C, "KS", v, t + i), "invalid", "head not stored #" .. i)
        end
        local badParts = {
            { "KSB", "1;;0;1.1" },               -- format 1
            { "KSB", "2;" .. ns.Share.b36(t) .. ";0;1.1" }, -- the bags part has no seen time
            { "KS6", "2;;0;1.1" },               -- a tab with items must say when
            { "KS6", "2;zzzzzz;0;1.1" },         -- seen in the future
            { "KS6", "2;" .. ns.Share.b36(t) .. ";0;1.1,1.2" }, -- the same item twice
            { "KS6", "2;" .. ns.Share.b36(t) .. ";0;1.0" },     -- 0
            { "KS6", "2;" .. ns.Share.b36(t) .. ";0;1.255s" },  -- over MAX_QTY
            { "KS6", "2;" .. ns.Share.b36(t) .. ";1jl;" },      -- more over the limit
            { "KS6", "2;" .. ns.Share.b36(t) .. ";0" },         -- three fields
            { "KS6", "2;" .. ns.Share.b36(t) .. ";0;" .. string.rep("1.1,", 800) .. "1.1" }, -- too long
        }
        for i, p in ipairs(badParts) do
            eq(K.decode(p[1], p[2]), nil, "part refused #" .. i)
            eq(offer(ns, C, p[1], p[2], t + i), "invalid", "part not stored #" .. i)
        end
        local many = {}
        for i = 1, K.MAX_ENTRIES + 1 do many[#many + 1] = ns.Share.b36(i) .. ".1" end
        eq(K.decode("KS6", "2;" .. ns.Share.b36(t) .. ";0;" .. table.concat(many, ",")), nil, "MAX_ENTRIES + 1 refused")
        eq(K.decode("KS15", K.EMPTY_PART), nil, "KS15 (the account bank) is no group of ours")
        eq(ns.Share.codecFor("KS15"), nil, "and not taken by Share")
        eq(ns.Share.get(C, "KS"), nil, "nothing of C stored")
        eq(K.decode("KS", K.EMPTY).empty, true, "the empty head is fine")
        eq(K.decode("KS6", K.EMPTY_PART).empty, true, "the empty part is fine")
        eq(ns.Share.isLocalGroup("KSB") and ns.Share.isLocalGroup("KS14") and ns.Share.isLocalGroup("KS"), true, "GF Sync leaves them out")
        -- Old saves: 0.16.15's own KS record and sentAt do no harm.
        local saved = { GreenFangToolkitDB = { bank = { v = 1, guilds = {}, scope = {}, stock = { ["Player-" .. A] = { consent = true, sentAt = 5, bank = {} } } } } }
        ns = login({ saved = saved })
        eq(ns.BankStock.mine().sentAt, nil, "old sentAt dropped"); eq(type(ns.BankStock.mine().sent), "table", "sent table")
    end))

    ---------------------------------------------------------------------------
    -- 2. 聯絡 picks the custodian
    ---------------------------------------------------------------------------

    test("GF-012-C 聯絡: one custodian whispers at once; several open a menu, online first then the most, me grey", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1001, 2 } }
        bagsChanged()
        local t = T0()
        offerStock(ns, C, { [1001] = 90 }, nil, t)  -- offline, the most
        offerStock(ns, E, { [1001] = 5 }, nil, t)   -- online
        offerStock(ns, F, { [1001] = 30, [1002] = 1 }, nil, t)  -- online, more than E
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        local r = rowFor(ns, 1001)
        local choices = ns.BankStock.contactChoices(r)
        eq(choices[1].name, "測試己", "online and the most first")
        eq(choices[2].name, "測試戊", "online next")
        eq(choices[3].name, "測試丙", "offline after")
        eq(choices[4].own, true, "me last")
        local row
        for _, x in ipairs(c.stockRows) do if x.itemID == 1001 then row = x end end
        ok(row and not row.contact.disabled, "聯絡 on")
        wow.click(row.contact)
        local menu = UI.contactMenu()
        ok(menu.isOpen(), "the menu opened")
        eq(#G.whispers, 0, "nothing whispered yet")
        local texts = menu.shownTexts()
        eq(#texts, 4, "four lines")
        ok(texts[1]:find("測試己", 1, true) and texts[1]:find("30 個", 1, true) and texts[1]:find("在線", 1, true) and texts[1]:find(UI.CONTACT_BEST, 1, true), "first marked: " .. texts[1])
        ok(texts[3]:find("離線", 1, true), "offline said: " .. texts[3])
        ok(texts[4]:find(UI.CONTACT_SELF, 1, true), "me: " .. texts[4])
        eq(menu.value, 1, "the default chosen")
        eq(menu.items[4].disabled, true, "me grey, not choosable")
        eq(menu.choose(4), false, "picking me does nothing")
        ok(menu.choose(3), "pick 測試丙")
        eq(#G.whispers, 1, "whispered"); eq(G.whispers[1].name, "測試丙-測試伺服器", "to the one picked")
        ok(not menu.isOpen(), "closed")
        -- One other custodian: at once.
        local one
        for _, x in ipairs(c.stockRows) do if x.itemID == 1002 then one = x end end
        wow.click(one.contact)
        eq(#G.whispers, 2, "whispered at once"); eq(G.whispers[2].name, "測試己-測試伺服器", "to F")
        ok(not menu.isOpen(), "no menu")
        -- Only mine: off.
        offerStock(ns, C, { [1001] = 90 }, nil, t) -- unchanged
        local mineOnly
        G.bags[0] = { { 1001, 2 }, { 1003, 1 } }; bagsChanged()
        for _, x in ipairs(c.stockRows) do if x.itemID == 1003 then mineOnly = x end end
        ok(mineOnly and mineOnly.contact.disabled, "my own item: 聯絡 off")
        -- The menu is one frame for every row and every open.
        local before = #wow.allObjects()
        for _ = 1, 5 do wow.click(row.contact); menu.close() end
        eq(#wow.allObjects(), before, "no new frames for the menu")
    end))

    ---------------------------------------------------------------------------
    -- 3. The page
    ---------------------------------------------------------------------------

    test("GF-012-C page: 庫存 first with 10+ rows; 保管人與分享設定 holds the list (8 rows), the scope, the switch", done(function()
        local ns = custodian({ bags = { 0 } })
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        eq(c.view, "stock", "庫存 first")
        -- GF-012-D: 申領 is the second button now.
        eq(c.views.buttons[1]:GetText(), "庫存", "button 1"); eq(c.views.buttons[3]:GetText(), "保管人與分享設定", "button 3")
        ok(c.stockView:IsShown() and not c.setupView:IsShown(), "only the stock view")
        ok(UI.STOCK_ROWS >= 10, "at least 10 rows: " .. UI.STOCK_ROWS)
        eq(#c.stockRows, UI.STOCK_ROWS, "pooled")
        local last = c.stockRows[UI.STOCK_ROWS]._points[1]
        ok(-last[5] + UI.STOCK_ROW_H <= ns.Framework.PANEL_HEIGHT - UI.STOCK_MORE_H, "the rows fit the page")
        eq(UI.ROWS, 8, "the list has 8 rows again")
        wow.click(c.views.buttons[3])
        eq(c.view, "setup", "switched")
        ok(c.setupView:IsShown() and not c.stockView:IsShown(), "only the setup view")
        ok(c.share:IsShown() and c.scope.bags[1]:IsShown() and c.rows[1]:IsShown(), "switch, scope, list there")
        ok(c.mine:GetText():find("我分享了", 1, true), "what I share there")
        wow.click(c.views.buttons[1])
        ok(c.stockView:IsShown(), "back")
    end))

    test("GF-012-C page: filters (name with ≤0.15 s, class, custodian, online), cached; 沒有符合篩選的物品", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1000, 2 }, { 1005, 3 } }
        bagsChanged()
        local t = T0()
        offerStock(ns, C, { [1000] = 7, [2001] = 1, [2006] = 1 }, nil, t) -- offline
        offerStock(ns, E, { [1005] = 4, [3002] = 1 }, nil, t)             -- online
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        local function ids()
            local out = {}
            for _, r in ipairs(c.stockRows) do if r:IsShown() then out[#out + 1] = r.itemID end end
            table.sort(out)
            return table.concat(out, ",")
        end
        eq(ids(), "1000,1005,2001,2006,3002", "all")
        -- Class: only the classes in stock, by the game's class names.
        local texts = {}
        for _, it in ipairs(c.classDrop.items) do texts[#texts + 1] = it.text end
        eq(#c.classDrop.items, 3, "全部 + two classes: " .. table.concat(texts, ","))
        eq(c.classDrop.items[1].text, UI.CLASS_ALL, "全部 first")
        c.classDrop.choose(5)
        eq(ids(), "1000,2001,3002", "class 5 (IDs ending 0-4)")
        -- Custodian.
        c.holderDrop.choose(C)
        eq(ids(), "1000,2001", "C's of class 5")
        eq(c.stockRows[1].count:GetText(), "7", "C's count only (not mine too)")
        c.classDrop.choose("all")
        eq(ids(), "1000,2001,2006", "C's all")
        -- Online only: C is offline.
        wow.click(c.online)
        eq(ids(), "", "C offline: nothing")
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.filter[1], "沒有符合篩選的物品")
        c.holderDrop.choose("all")
        eq(ids(), "1000,1005,3002", "online: mine and E's")
        eq(c.stockRows[1].itemID, 1005, "E 4 + mine 3 first")
        wow.click(c.online)
        -- Name: the first key at once, then at most 0.15 s later.
        c.search:SetText("物品100"); c.search:GetScript("OnTextChanged")(c.search)
        eq(ids(), "1000,1005", "at once")
        c.search:SetText("物品1005"); c.search:GetScript("OnTextChanged")(c.search)
        eq(ids(), "1000,1005", "within the gap: not yet")
        wow.advance(UI.SEARCH_DELAY)
        eq(ids(), "1005", "after 0.15 s")
        ok(UI.SEARCH_DELAY <= 0.15, "≤ 0.15 s")
        c.search:SetText("沒有"); c.search:GetScript("OnTextChanged")(c.search); wow.advance(1)
        eq(c.stock.text:GetText(), UI.STOCK_EMPTY.search[1], "the name only: the old words")
        c.search:SetText(""); c.search:GetScript("OnTextChanged")(c.search); wow.advance(1)
        -- Cached: redraws without a change do not filter again or read classes.
        local K = ns.BankStock
        c.classDrop.choose(0)
        local runs, calls = K.stats.filterRuns, G.classCalls
        for _ = 1, 5 do UI.refresh() end
        eq(K.stats.filterRuns, runs, "no new filtering"); eq(G.classCalls, calls, "classes read once")
        -- New data: filtered again.
        wow.advance(1)
        offerStock(ns, E, { [1005] = 4, [3002] = 1, [3007] = 2 })
        ok(K.stats.filterRuns > runs, "filtered again on new data")
        ok(ids():find("3007", 1, true), "new item shown: " .. ids())
        -- A custodian gone from the list: the choice goes back to 全部.
        c.holderDrop.choose(E)
        wow.advance(5)
        setList(ns, { { A, "bk" }, { C, "bk" } })
        eq(c.filters.holder, "all", "back to 全部")
    end))

    test("GF-012-C page: wheel and 「還有 N 項」 over many rows; redraws make no frames; tooltip has every custodian", done(function()
        local ns = custodian({ bags = { 0 } })
        local items = {}
        for i = 1, 40 do items[5000 + i] = 100 - i end
        offerStock(ns, C, items, { [6] = { [5001] = 3 } })
        offerStock(ns, E, { [5001] = 1 })
        ns.Framework.open("bank")
        local UI, c = ns.BankUI, ns.BankUI.controls
        eq(c.stockMore:GetText(), string.format(UI.STOCK_MORE, 40 - UI.STOCK_ROWS), "the more line")
        eq(c.stockCount:GetText(), "共 40 項", "count")
        eq(c.stockRows[1].itemID, 5001, "the most first")
        eq(c.stockRows[1].who:GetText(), "測試丙 等 2 位", "first + 等 N 位")
        eq(c.stockRows[1].count:GetText(), "103", "99 + 3 + 1")
        local lines = UI.tipLines(c.stockRows[1].stockItem)
        eq(#lines, 2, "two custodians in the tooltip")
        ok(lines[1]:find("測試丙 背包 99、銀行 3", 1, true) and lines[1]:find("離線", 1, true), "C: " .. lines[1])
        ok(lines[2]:find("測試戊 背包 1", 1, true) and lines[2]:find("在線", 1, true), "E: " .. lines[2])
        for _ = 1, 100 do UI.scrollStock(-1) end
        eq(c.stockOffset, 40 - UI.STOCK_ROWS, "stops at the end"); eq(c.stockMore:GetText(), "", "no line at the end")
        local before = #wow.allObjects()
        for _ = 1, 5 do UI.refresh(); UI.scrollStock(1); UI.setFilter("online", true); UI.setFilter("online", false) end
        UI.setView("setup"); UI.setView("stock")
        eq(#wow.allObjects(), before, "no new frames on redraw, scroll, filter, view")
    end))

    test("GF-012-C performance: 10 custodians x 10 parts x 98 kinds; rebuild, filter, cached redraw (measured)", done(function()
        local r = roster()
        local ids = {}
        for i = 1, 10 do
            local a = string.format("0000-%08X", 0x3000 + i)
            ids[i] = a
            r[#r + 1] = { name = "保管" .. i .. "-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
                zone = "杜洛塔", online = i % 2 == 0, guid = "Player-" .. a }
        end
        local ns = login({ roster = r })
        local entries = {}
        for i = 1, 10 do entries[i] = { ids[i], "bk" } end
        setList(ns, entries)
        local t = T0()
        for i = 1, 10 do
            local bags, tabs = {}, {}
            for k = 1, 65 do bags[100000 + (i * 7 + k) % 900] = k end
            for tab = 6, 14 do
                tabs[tab] = {}
                for k = 1, 98 do tabs[tab][200000 + (i * 13 + tab * 101 + k) % 3000] = k end
            end
            offerStock(ns, ids[i], bags, tabs, t)
        end
        ns.Framework.open("bank")
        local UI, K = ns.BankUI, ns.BankStock
        local rows = K.rows()
        local t0 = os.clock()
        local n = 5
        for _ = 1, n do K.invalidate(); UI.refresh() end
        local rebuild = (os.clock() - t0) * 1000 / n
        local t1 = os.clock()
        for _ = 1, n do UI.setFilter("online", true); UI.setFilter("online", false) end
        local filt = (os.clock() - t1) * 1000 / (2 * n)
        local t2 = os.clock()
        for _ = 1, 20 do UI.refresh() end
        local cached = (os.clock() - t2) * 1000 / 20
        local total = 0
        for _, x in ipairs(rows) do total = total + #x.places end
        realPrint(string.format("     [GF-012-C measure] 10 custodians x (65 bag + 9 x 98 tab kinds) = %d places, %d rows: rebuild + draw %.2f ms, a filter change %.2f ms (first time each, then kept), redraw with nothing changed %.2f ms",
            total, #rows, rebuild, filt, cached))
        ok(#rows > 1000, "many rows: " .. #rows)
        eq(#ns.BankUI.controls.stockRows, UI.STOCK_ROWS, "still the pooled rows only")
    end))

    ---------------------------------------------------------------------------
    -- 4. 調貨看板
    ---------------------------------------------------------------------------

    test("GF-012-C 調貨看板: 黑箱 rows marked (icon, word, colour), filter 全部／只看黑箱／不看黑箱, 聯絡 picks", done(function()
        local ns = custodian({ bags = { 0 } })
        G.bags[0] = { { 1001, 2 } }
        bagsChanged()
        local t = T0()
        offerStock(ns, C, { [1001] = 9, [4001] = 1 }, nil, t)
        offerStock(ns, E, { [1001] = 3 }, nil, t)
        offerStock(ns, D, { [4444] = 1 }, nil, t) -- D is no custodian: never on the board
        -- A member's manual offer of another item (a normal row).
        ns.Supply.setManual(true)
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.setTab("guild")
        local function find(id)
            for i, d in ipairs(UI.state.items) do if d.itemID == id then return d, i end end
            return nil
        end
        local d = find(1001)
        ok(d, "黑箱 item on the board")
        -- GF-009-16: my own custody (2) is counted and said; 黑箱 has a column of its own.
        ok(d.stockLine and d.stockLine:find("|T" .. UI.STOCK_ICON, 1, true) and d.stockLine:find("黑箱 14 個（3 位保管人，含我）", 1, true), "the mark: " .. tostring(d.stockLine))
        eq(d.cells[3], "14 個", "the 黑箱 column"); eq(d.cells[1] .. d.cells[2], "", "no 徵求／供應")
        ok(find(4001), "C's other item"); eq(find(4444), nil, "not a custodian: not shown")
        -- The list row shows the mark in its own colour.
        local _, idx = find(1001)
        UI.state.offset = math.max(0, idx - 1); UI.drawList()
        local row
        for _, f in ipairs(wow.allObjects()) do if f.index == idx and f.where then row = f end end
        ok(row and row.where:GetText():find("黑箱", 1, true), "row second line")
        local col = row.where._textColor or row.where._color
        if col then eq(col[1], UI.STOCK_COLOR[1], "its colour") end
        -- Detail: one 黑箱 line, 聯絡 opens the custodian menu.
        UI.select(idx)
        local dr = UI.detailRowList()[1]
        eq(dr.name:GetText(), UI.STOCK_NAME, "detail line")
        ok(dr.src:GetText():find("黑箱", 1, true), "條件 says 黑箱")
        wow.click(dr.contact)
        local menu = ns.BankUI.contactMenu()
        ok(menu.isOpen(), "the menu")
        local texts = menu.shownTexts()
        ok(texts[1]:find("測試戊", 1, true), "online first: " .. texts[1])
        eq(#texts, 2, "the two others (my own place is its own line, GF-009-16)")
        menu.choose(1)
        eq(G.whispers[#G.whispers].name, "測試戊-測試伺服器", "whispered")
        ok(G.whispers[#G.whispers].text:find("臨時黑箱", 1, true), "the 黑箱 words")
        -- GF-009-16: my custody is the next line, 聯絡 grey.
        eq(UI.detailRowList()[2].name:GetText(), UI.STOCK_OWN_NAME, "my own custody line")
        eq(UI.detailRowList()[2].contact.disabled, true, "聯絡 grey")
        -- Filter (GF-009-16: 種類 黑箱 in the filter row; was the 黑箱 drop-down).
        ok(UI.kindDrop:IsShown(), "filter on 調貨看板")
        UI.kindDrop.choose("stock")
        ok(find(1001) and find(4001), "只看黑箱")
        for _, x in ipairs(UI.state.items) do ok(UI.stockQty(x.item) > 0, "only 黑箱 rows") end
        UI.kindDrop.choose("all")
        ok(find(1001), "全部")
        UI.showTab("mine")
        eq(#UI.kindDrop.items, 3, "no 黑箱 on 我的刊登")
        -- Revoked: off the board too (BankStock.holders' rules).
        UI.setTab("guild")
        wow.advance(5)
        local keep = {}
        for _, e in ipairs(ns.Bank.current().list.entries) do keep[e.a] = e.epoch end
        setList(ns, { { A, "bk", true, keep[A] }, { C, "bk", false }, { E, "bk", true, keep[E] } })
        UI.refresh()
        eq(find(4001), nil, "revoked C: gone from the board")
        ok(find(1001), "E still")
    end))
end
