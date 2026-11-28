-- GF-009-15: 綠皮調貨所 — the 「開｜關」 switch cells, and where 自動集料
-- counts from: 行囊 + 材料袋 (live), 銀行 and 信箱（未收） (only while open,
-- kept per character as last seen). Missing counts all four; the shared
-- surplus counts Supply.SHARE_SOURCES. Offline only; made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local function page(n) return 2724 + n end
    -- Chapter I (quest 339): pages 1, 4, 6, 8.
    local P1, P4, P6, P8 = page(1), page(4), page(6), page(8)
    local BANK, TAB1, TAB2, ACCOUNT, REAGENT = -1, 6, 7, 12, 5

    local G
    local function installGame(opts)
        opts = opts or {}
        G = { quests = opts.quests or {}, bags = opts.bags or {}, slots = opts.slots or {}, bankOpen = false,
            inbox = opts.inbox or {}, info = 0, header = 0, mailItem = 0 }
        C_QuestLog = {
            IsQuestFlaggedCompleted = function(id) return G.quests[id] == "done" end,
            IsOnQuest = function(id) return G.quests[id] == "active" end,
        }
        local bankBag = { [BANK] = true, [TAB1] = true, [TAB2] = true, [ACCOUNT] = true }
        C_Container = {
            GetContainerNumSlots = function(bag)
                if bankBag[bag] and not G.bankOpen then return 0 end
                return G.slots[bag] or (bag == 0 and 20 or 0)
            end,
            GetContainerItemInfo = function(bag, slot)
                G.info = G.info + 1
                local it = G.bags[bag] and G.bags[bag][slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        if not opts.noMailAPI then
            GetInboxNumItems = function() return #G.inbox, #G.inbox end
            GetInboxHeaderInfo = function(i)
                G.header = G.header + 1
                local m = G.inbox[i]
                if not m then return nil end
                local n = 0
                for _ in pairs(m.items) do n = n + 1 end
                return nil, nil, "寄件人", "主旨", 0, 0, 3, n > 0 and n or nil, false, false
            end
            GetInboxItem = function(i, j)
                G.mailItem = G.mailItem + 1
                local a = G.inbox[i] and G.inbox[i].items[j]
                if a then return "物品", a[1], 134939, a[2], 1, true end
            end
        end
        local base = Enum
        Enum = {}
        for k, v in pairs(base or {}) do Enum[k] = v end
        if not opts.noBagIndex then
            Enum.BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = REAGENT,
                Bank = BANK, CharacterBankTab_1 = TAB1, CharacterBankTab_2 = TAB2, AccountBankTab_1 = ACCOUNT }
            if opts.noBankIndex then
                Enum.BagIndex.Bank, Enum.BagIndex.CharacterBankTab_1, Enum.BagIndex.CharacterBankTab_2 = nil, nil, nil
            end
        else
            Enum.BagIndex = nil
        end
        GetItemInfo = function(id) return "測試頁" .. id, "|cffffffff|Hitem:" .. id .. "::::::::|h[頁]|h|r", 1, 1, 1, "", "", 20, "", 134939, 0, 15, 0, 0 end
        C_Item = {
            GetItemIconByID = function() return 134939 end,
            GetItemNameByID = function(id) return "測試頁" .. id end,
            RequestLoadItemDataByID = function() end,
        }
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item = nil, nil, nil, nil
        GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem = nil, nil, nil
    end
    local function done(fn)
        return function()
            local enumBefore = Enum
            local okRun, err = pcall(fn)
            removeGame()
            Enum = enumBefore
            if not okRun then error(err, 0) end
        end
    end

    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        if opts.auto ~= false then ns.Supply.setAuto(true) end
        wow.advance(40)
        wow.state.sent = {}
        return ns
    end
    local function rule(ns) return ns.SupplyRules.list[1] end
    local function snap(ns) return ns.Supply.last.snaps[rule(ns).collectionID] end
    local function openBank(ns) G.bankOpen = true; wow.fire("BANKFRAME_OPENED"); wow.advance(0.01) end
    local function closeBank() wow.fire("BANKFRAME_CLOSED"); G.bankOpen = false end
    local function openMail() wow.fire("MAIL_SHOW"); wow.fire("MAIL_INBOX_UPDATE"); wow.advance(0.01) end
    local function closeMail() wow.fire("MAIL_CLOSED") end

    ---------------------------------------------------------------------------
    -- 1. Where it counts from
    ---------------------------------------------------------------------------

    test("GF-009-15 sources: 行囊 and 材料袋 now; 銀行／信箱 還沒看過 until opened (no error)", done(function()
        local ns = login({ quests = { [339] = "active" },
            bags = { [0] = { { P1, 1 } }, [REAGENT] = { { P4, 1 } } }, slots = { [REAGENT] = 4 } })
        local S = ns.Supply
        eq(S.scanNow(), "ok", "scan")
        local s = snap(ns)
        eq(s.missing[P1], nil, "page 1 in 行囊"); eq(s.missing[P4], nil, "page 4 in 材料袋")
        eq(s.missing[P6], 1, "page 6 missing"); eq(s.missing[P8], 1, "page 8 missing")
        local lines = table.concat(S.whereLines(P4), "|")
        eq(lines, "行囊：0|材料袋：1|銀行：還沒看過|信箱（未收）：還沒看過", "where page 4 is")
        eq(S.seenOf("bank"), nil, "bank never read"); eq(S.seenOf("mail"), nil, "mail never read")
        ok(S.diagText():find("銀行 還沒看過", 1, true), "同步與診斷 says it")
    end))

    test("GF-009-15 bank: read when opened and on changes while open; kept with its time; closed = no read", done(function()
        local ns = login({ quests = { [339] = "active" }, bags = { [BANK] = { { P6, 1 } }, [TAB1] = { { P8, 2 } },
            [ACCOUNT] = { { P1, 5 } } }, slots = { [BANK] = 28, [TAB1] = 98, [TAB2] = 98, [ACCOUNT] = 98 } })
        local S = ns.Supply
        S.scanNow()
        eq(snap(ns).missing[P6], 1, "before the bank: missing")
        openBank(ns)
        eq(S.sourceReads.bank, 1, "one read on the next frame")
        local e = S.seenOf("bank")
        ok(e and e.t > 0, "time kept")
        eq(e.n[P6], 1, "page 6 in the bank"); eq(e.n[P8], 2, "page 8 in tab 1")
        eq(e.n[P1], nil, "the account bank is not this character's bank")
        wow.advance(4)
        eq(snap(ns).missing[P6], nil, "the scan counts the bank"); eq(snap(ns).missing[P8], nil, "and tab 1")
        -- Several changes in one frame: one read.
        G.bags[TAB1][1] = { P8, 1 }
        wow.fire("PLAYERBANKSLOTS_CHANGED", 1); wow.fire("BAG_UPDATE_DELAYED"); wow.fire("PLAYERBANKSLOTS_CHANGED", 2)
        wow.advance(0.01)
        eq(S.sourceReads.bank, 2, "one more read for the burst")
        eq(S.seenOf("bank").n[P8], 1, "the change is kept")
        closeBank()
        G.bags[TAB1][1] = nil
        wow.fire("BAG_UPDATE_DELAYED"); wow.fire("PLAYERBANKSLOTS_CHANGED", 1); wow.advance(0.01)
        eq(S.sourceReads.bank, 2, "closed: no read")
        eq(S.seenOf("bank").n[P8], 1, "the last seen copy stays")
        local where = table.concat(S.whereLines(P8), "|")
        ok(where:find("銀行：1（上次看到 ", 1, true), "where shows the time: " .. where)
    end))

    test("GF-009-15 bank: a client without bank names reads nothing and says 還沒看過; 0 slots keeps the copy", done(function()
        local ns = login({ quests = { [339] = "active" }, noBankIndex = true, bags = { [BANK] = { { P6, 1 } } } })
        local S = ns.Supply
        openBank(ns)
        eq(S.readSource("bank"), "no-bank-index", "no names, no guess")
        eq(S.seenOf("bank"), nil, "還沒看過")
        ok(table.concat(S.whereLines(P6), "|"):find("銀行：還沒看過", 1, true), "shown as 還沒看過")
        -- A bank that shows 0 slots (not really open) never wipes the copy.
        local ns2 = login({ quests = { [339] = "active" }, bags = { [BANK] = { { P6, 1 } } }, slots = { [BANK] = 28 } })
        openBank(ns2)
        eq(ns2.Supply.seenOf("bank").n[P6], 1, "seen")
        G.bankOpen = false -- the client still says open, the bank reads empty
        eq(ns2.Supply.readSource("bank"), "bank-empty", "nothing seen")
        eq(ns2.Supply.seenOf("bank").n[P6], 1, "copy kept")
        -- No Enum.BagIndex at all: no bank, no reagent bag, no error.
        local ns3 = login({ quests = { [339] = "active" }, noBagIndex = true })
        openBank(ns3)
        eq(ns3.Supply.seenOf("bank"), nil, "no bank read")
        eq(ns3.Supply.scanNow(), "ok", "the scan still works")
        eq(#ns3.Supply.locations(P1), 3, "行囊, 銀行, 信箱 (no 材料袋 line)")
    end))

    test("GF-009-15 mail: attachments not taken yet count as 信箱（未收）; only mails with items are read", done(function()
        local inbox = { { items = {} }, { items = { [1] = { P6, 1 }, [3] = { 99999, 4 } } }, { items = {} } }
        local ns = login({ quests = { [339] = "active" }, inbox = inbox })
        local S = ns.Supply
        wow.fire("MAIL_INBOX_UPDATE"); wow.advance(0.01)
        eq(S.sourceReads.mail, 0, "not open: not read")
        openMail()
        eq(S.sourceReads.mail, 1, "read once")
        eq(G.mailItem, S.MAIL_SLOTS, "only the mail with items had its slots read")
        local e = S.seenOf("mail")
        eq(e.n[P6], 1, "page 6 waiting in the mailbox"); eq(e.n[99999], nil, "not a whitelist item: not kept")
        wow.advance(4)
        eq(snap(ns).missing[P6], nil, "missing counts the mailbox")
        ok(table.concat(S.whereLines(P6), "|"):find("信箱（未收）：1（上次看到 ", 1, true), "where")
        -- Taken: the mailbox has none, the bag has it.
        inbox[2].items[1] = nil
        G.bags[0] = { { P6, 1 } }
        wow.fire("MAIL_INBOX_UPDATE"); wow.fire("BAG_UPDATE_DELAYED"); wow.advance(0.01)
        eq(S.seenOf("mail").n[P6], nil, "gone from the mailbox")
        wow.advance(4)
        eq(snap(ns).missing[P6], nil, "still not missing (in the bag now)")
        closeMail()
        wow.fire("MAIL_INBOX_UPDATE"); wow.advance(0.01)
        eq(S.sourceReads.mail, 2, "closed: no read")
    end))

    test("GF-009-15 mail: a client without the inbox functions stays 還沒看過, no error", done(function()
        local ns = login({ quests = { [339] = "active" }, noMailAPI = true })
        openMail()
        eq(ns.Supply.seenOf("mail"), nil, "not seen")
        eq(ns.Supply.scanNow(), "ok", "scan fine")
    end))

    test("GF-009-15 no reads: collection off, in combat; no OnUpdate, only next-frame reads", done(function()
        local ns = login({ quests = { [339] = "active" }, auto = false, bags = { [BANK] = { { P6, 1 } } }, slots = { [BANK] = 28 } })
        local S = ns.Supply
        openBank(ns)
        eq(S.sourceReads.bank, 0, "collection off: the bank is not read")
        S.setAuto(true)
        wow.enterCombat()
        eq(S.readSource("bank"), "skip", "in combat: nothing")
        wow.leaveCombat()
        eq(S.readSource("bank"), "ok", "after combat")
        local src = io.open(ADDON_DIR .. "/Supply.lua"):read("*a")
        ok(not src:find("OnUpdate\"", 1, true) and not src:find("NewTicker", 1, true), "Supply.lua: no OnUpdate, no ticker")
    end))

    ---------------------------------------------------------------------------
    -- 2. What is shared (wire unchanged; SHARE_SOURCES)
    ---------------------------------------------------------------------------

    local function shareSetup(saved)
        -- Not on chapter I (idle: keep 1 of each); 2 of page 1 in the bag, 3 of page 4 in the bank, 2 of page 6 in the mailbox.
        local ns = login({ quests = { [339] = "idle" }, bags = { [0] = { { P1, 2 } }, [TAB1] = { { P4, 3 } } },
            slots = { [TAB1] = 98 }, inbox = { { items = { [1] = { P6, 2 } } } }, saved = saved })
        local S = ns.Supply
        openBank(ns); openMail()
        S.scanNow()
        return ns, S
    end
    local function wire(ns) return ns.Share.get(ns.Share.selfAuthor(), ns.SupplyRules.groupOf(rule(ns))) end

    test("GF-009-15 share (default 全部, owner 2026-11-27): the surplus counts all four places; wire unchanged", done(function()
        local ns, S = shareSetup()
        eq(S.db().shareAll, nil, "nothing saved: the default")
        eq(S.shareAllOn(), true, "全部")
        local s = snap(ns)
        eq(s.surplus[P1], 1, "bag: 2 - keep 1"); eq(s.surplus[P4], 2, "bank: 3 - keep 1"); eq(s.surplus[P6], 1, "mail: 2 - keep 1")
        ok(wire(ns).v:match("^1//[0-9a-z.,]+$"), "wire: same format, no places")
        eq(S.shareSourcesText(), "行囊、材料袋、銀行和信箱（未收）", "card text")
    end))

    test("GF-009-15 share 只算身上: switching re-scans at once and sends only when the snapshot changed; saved", done(function()
        local ns, S = shareSetup()
        local before = wire(ns).v
        S.setShareAll(false)
        eq(S.db().shareAll, false, "saved")
        local s = snap(ns)
        eq(s.surplus[P1], 1, "bag"); eq(s.surplus[P4], nil, "bank not shared"); eq(s.surplus[P6], nil, "mail not shared")
        eq(wire(ns).v, "1//" .. ns.Share.b36(P1) .. "." .. ns.Share.b36(1), "the new snapshot is stored at once")
        ok(wire(ns).v ~= before, "changed")
        eq(S.shareSourcesText(), "行囊和材料袋", "card text follows")
        -- The same setting again: same snapshot, nothing new published.
        local published = S.stats.published
        S.setShareAll(false)
        eq(S.stats.published, published, "unchanged: not sent again")
        -- From the card: the 全部 cell turns it back.
        ns.Framework.open("supply")
        local f = ns.SupplyUI.openCard("auto")
        eq(f.shareLabel._text, "分享的餘料", "the setting's name")
        eq(f.share.cells.on.text._text, "全部", "全部"); eq(f.share.cells.off.text._text, "只算身上", "只算身上")
        eq(f.share.cells.off.gfLit, true, "只算身上 lit"); eq(f.share.cells.on.gfLit, false, "全部 grey")
        f.share.cells.on._scripts.OnClick(f.share.cells.on)
        eq(S.shareAllOn(), true, "全部 again"); eq(f.share.cells.on.gfLit, true, "lit")
        eq(snap(ns).surplus[P4], 2, "bank back in the surplus")
        -- After a reload the choice stays.
        S.setShareAll(false)
        local saved = wow.logout()
        local ns2 = login({ quests = { [339] = "idle" }, saved = saved })
        eq(ns2.Supply.shareAllOn(), false, "kept after a reload")
    end))

    test("GF-009-15 missing counts all four; a page in the bank is not missing and not offered", done(function()
        local ns = login({ quests = { [339] = "active" }, bags = { [0] = { { P1, 1 } }, [REAGENT] = { { P4, 1 } },
            [TAB1] = { { P6, 1 } } }, slots = { [REAGENT] = 4, [TAB1] = 98 }, inbox = { { items = { [2] = { P8, 1 } } } } })
        local S = ns.Supply
        openBank(ns); openMail()
        S.scanNow()
        local s = snap(ns)
        eq(next(s.missing), nil, "nothing missing: bag, reagent bag, bank, mailbox")
        eq(next(s.surplus), nil, "nothing extra (each needed once)")
    end))

    ---------------------------------------------------------------------------
    -- 3. Saved per character
    ---------------------------------------------------------------------------

    test("GF-009-15 saved: the last seen bank and mailbox survive a reload; only whitelist counts and the time", done(function()
        local ns = login({ quests = { [339] = "active" }, bags = { [TAB1] = { { P6, 1 }, { 99999, 9 } } }, slots = { [TAB1] = 98 },
            inbox = { { items = { [1] = { P8, 1 } } } } })
        openBank(ns); openMail()
        local saved = wow.logout()
        local db = saved.GreenFangToolkitDB.supply.seen
        local key = ns.Supply.charKey()
        ok(db[key] and db[key].bank and db[key].mail, "kept under this character")
        local keys = {}
        for k in pairs(db[key].bank) do keys[#keys + 1] = k end
        table.sort(keys)
        eq(table.concat(keys, ","), "e,n,t", "only counts and the time")
        eq(db[key].bank.n[99999], nil, "no other items")
        local ns2 = login({ quests = { [339] = "active" }, saved = saved })
        eq(ns2.Supply.seenOf("bank").n[P6], 1, "bank after reload"); eq(ns2.Supply.seenOf("mail").n[P8], 1, "mail after reload")
        ns2.Supply.scanNow()
        eq(snap(ns2).missing[P6], nil, "counted without opening again")
        -- Another character's copy is not mine.
        saved.GreenFangToolkitDB.supply.seen = { ["Player-0000-000000FF"] = db[key] }
        local ns3 = login({ quests = { [339] = "active" }, saved = saved })
        eq(ns3.Supply.seenOf("bank"), nil, "other character: 還沒看過")
    end))

    ---------------------------------------------------------------------------
    -- 4. The page
    ---------------------------------------------------------------------------

    test("GF-009-15 switch: 「開｜關」 side by side; the current one lit gold, the other grey; a click sets that state", done(function()
        local ns = login({ auto = false })
        local UI, S, Th = ns.SupplyUI, ns.Supply, ns.Theme
        ns.Framework.open("supply")
        for _, c in ipairs({ UI.autoBox, UI.manualBox }) do
            local on, off = c.cells.on, c.cells.off
            eq(on.text._text, "開", "left cell"); eq(off.text._text, "關", "right cell")
            eq(on._points[1][4], 0, "開 first"); eq(off._points[1][4], UI.SWITCH_CELL_W, "關 right next to it")
            ok(c._points[1][4] > UI.SWITCH_X.name + ns.labelWidth(c.label._text), "the name on the left")
            ok(UI.SWITCH_X.button + UI.SWITCH_W + 8 <= UI.SWITCH_X.line, "the line after the pair")
        end
        local a = UI.autoBox
        eq(a.cells.off.gfLit, true, "off: 關 lit"); eq(a.cells.on.gfLit, false, "開 grey")
        local gold = Th.C.gold
        eq(a.cells.off.text._color[1], gold[1], "lit text is gold")
        eq(a.cells.on.text._color[1], Th.C.muted[1], "the other grey")
        -- A click on the lit cell does nothing; on the other sets it.
        local calls = 0
        local real = S.setAuto
        S.setAuto = function(on) calls = calls + 1; real(on) end
        a.cells.off._scripts.OnClick(a.cells.off)
        eq(calls, 0, "lit cell: nothing")
        a.cells.on._scripts.OnClick(a.cells.on)
        eq(calls, 1, "the other: set"); eq(S.autoOn(), true, "on")
        eq(a.cells.on.gfLit, true, "開 lit"); eq(a.cells.off.gfLit, false, "關 grey")
        S.setAuto = real
        ok(a.help and a.help._text == UI.SWITCH_HELP.auto.text, "說明 kept")
        ok(a.line._text == UI.SWITCH_LINE.auto.on, "one line kept")
    end))

    test("GF-009-15 my page: each item says where it is and how many; bank and mailbox with their time", done(function()
        local ns = login({ quests = { [339] = "idle" }, bags = { [0] = { { P1, 3 } }, [TAB1] = { { P1, 2 } } }, slots = { [TAB1] = 98 } })
        local UI, S = ns.SupplyUI, ns.Supply
        openBank(ns)
        S.scanNow()
        ns.Framework.open("supply")
        UI.setTab("offer")
        local row
        for _, d in ipairs(UI.state.items) do if d.itemID == P1 then row = d end end
        ok(row, "page 1 offered")
        local tip = table.concat(row.tip, "|")
        ok(tip:find("我的存放位置：", 1, true), "where heading")
        ok(tip:find("行囊：3", 1, true), "行囊 3: " .. tip)
        ok(tip:find("銀行：2（上次看到 ", 1, true), "銀行 2 with its time")
        ok(tip:find("信箱（未收）：還沒看過", 1, true), "信箱 還沒看過")
        ok(row.where:match("^行囊 3｜銀行 2（%d%d%-%d%d %d%d:%d%d）$"), "short line, 0 places left out: " .. row.where)
        eq(S.snapshots()[1] and S.snapshots()[1].surplus[P1], 4, "shared (全部): 3 + 2 - keep 1")
        -- On the row itself: a second line under the cells; the tooltip has the full list.
        local shownRow
        for _, o in ipairs(wow.allObjects()) do
            if o.where and o.itemID == P1 and o.IsShown and o:IsShown() then shownRow = o end
        end
        ok(shownRow, "the row is drawn")
        eq(shownRow.where._text, row.mineText .. "｜" .. row.where, "the row shows where (GF-009-16: after 「我可能多 N」)")
        ok(shownRow.where:IsShown(), "second line shown")
        ok(shownRow.name._points[1][5] > 0 and shownRow.where._points[1][5] < 0, "name up, where under it")
        -- Need rows: a second line only when something is held (one of each page is needed, so here none).
        UI.setTab("need")
        for _, o in ipairs(wow.allObjects()) do
            if o.where and o.IsShown and o:IsShown() and o.itemID then
                ok(not o.where:IsShown() or o.where._text ~= "", "no empty second line")
            end
        end
    end))

    test("GF-009-15 自動集料 card: no longer says 不讀銀行; says where from, that places are not shared; joke kept", done(function()
        local ns = login({})
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        local f = UI.openCard("auto", UI.autoBox.help)
        local all = {}
        for _, fs in ipairs(f.lines) do all[#all + 1] = fs._text end
        all = table.concat(all, "\n")
        ok(not all:find("不讀銀行", 1, true), "no 不讀銀行")
        -- GF-UI-N (owner: 「說明頁過度複雜」): five short lines; 全部／只算身上 is the switch's own tooltip.
        for _, w in ipairs({ "材料袋", "銀行", "信箱", "不分享東西放在哪裡", "上次打開時看到的" }) do
            ok(all:find(w, 1, true), "says: " .. w)
        end
        eq(f.sub._text, UI.CARD_SUB.auto, "the joke stays on the card")
        ok(UI.SHARE_TIP:find("只算身上＝行囊和材料袋", 1, true), "全部／只算身上 explained on the switch")
        ok(not UI.SWITCH_TIP.auto:find("不讀銀行", 1, true), "tooltip too")
    end))

    ---------------------------------------------------------------------------
    -- 5. Measure: the scan after a bag event (game calls)
    ---------------------------------------------------------------------------

    test("GF-009-15 measure: one scan after BAG_UPDATE_DELAYED (bag reads; bank and mail never read in a scan)", done(function()
        local ns = login({ quests = { [339] = "active" }, slots = { [0] = 20, [1] = 20, [2] = 20, [3] = 20, [4] = 20,
            [REAGENT] = 36, [TAB1] = 98 }, inbox = { { items = { [1] = { P6, 1 } } } } })
        local S = ns.Supply
        openBank(ns); openMail()
        closeBank(); closeMail()
        G.info, G.mailItem, G.header = 0, 0, 0
        local scans = S.stats.scans
        wow.fire("BAG_UPDATE_DELAYED")
        local t0 = os.clock()
        wow.advance(4)
        local ms = (os.clock() - t0) * 1000
        eq(S.stats.scans, scans + 1, "one scan")
        eq(G.info, 100 + 36, "bags 0-4 (100 slots) + reagent bag (36)")
        eq(G.mailItem + G.header, 0, "mailbox not read by a scan")
        realPrint(string.format("     [GF-009-15 measure] one scan after BAG_UPDATE_DELAYED: %d GetContainerItemInfo (bags 0-4: 100, 材料袋: 36; before GF-009-15: 100), 0 bank / 0 mail reads, %.1f ms",
            G.info, ms))
    end))
end
