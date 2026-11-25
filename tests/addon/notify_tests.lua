-- GF-014 (spec v2.0 §3 業務通知, §7.3, §11): the notification center, its bell
-- on the main window, and the local radar (GF-009-09). Offline only: the bag
-- and item functions are a small fake game below; nothing here was checked in
-- the Forever client. Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_B, A_C = "0000-0000000B", "0000-0000000C"
    local PEER_B, PEER_C = "測試乙-測試伺服器", "測試丙-測試伺服器"
    local SCROLL, BOP, CLOTH, MYSTERY = 9001, 9002, 9003, 9004

    -- bag = { { itemID, count, bound, locked } } (bag 0); items[id] = { name, bindType, classID }.
    local G
    local chatSent
    local function installGame(opts)
        opts = opts or {}
        G = { bag = opts.bag or {}, items = opts.items or {
            [SCROLL] = { name = "配方：測試藥水", classID = 9, bindType = 0 },
            [BOP] = { name = "測試護符", classID = 4, bindType = 1 },
            [CLOTH] = { name = "測試布料", classID = 7, bindType = 0 },
        } }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = it[4] == true, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939,
                0, it.classID or 15, 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function() end,
        }
        chatSent = {}
        SendChatMessage = function(...) chatSent[#chatSent + 1] = { ... } end
        ChatFrame_SendTellWithMessage = function(name, text) chatSent[#chatSent + 1] = { name, text } end
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item, SendChatMessage, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil, nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        ns.Notify.resetSession(); ns.SupplyRadar.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(30)
        wow.advance(45) -- the radar starts 50 s after login, its first check 3 s later
        wow.state.sent = {}
        return ns
    end
    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    -- B (or another author) publishes listings: list of { direction, itemID, qty }.
    local function listings(ns, a, sender, list, t)
        t = t or (T0() - 60)
        local out = {}
        for i, l in ipairs(list) do
            out[i] = { id = i, direction = l[1], category = "other", itemID = l[2], quantity = l[3] or 1,
                createdAt = t, expiresAt = t + 7 * 86400, rev = 1, note = "" }
        end
        return from(ns, sender, vMsg(ns, a, "L", t, ns.SupplyListings.encode(out)))
    end
    local function notices(ns, module)
        local out = {}
        for _, e in ipairs(ns.Notify.list()) do if not module or e.module == module then out[#out + 1] = e end end
        return out
    end
    local function bagEvent(ns) wow.fire("BAG_UPDATE_DELAYED"); wow.advance(4) end
    local function chatLines(text)
        local n = 0
        for _, line in ipairs(wow.printed()) do if tostring(line):find(text, 1, true) then n = n + 1 end end
        return n
    end

    ---------------------------------------------------------------------------
    -- The notification center
    ---------------------------------------------------------------------------

    test("GF-014 push: the same key is one notice (newest text, count), unread once", done(function()
        local ns = login()
        local N = ns.Notify
        eq(N.push({ module = "supply", key = "a", text = "第一次", target = { page = "supply" } }), "stored", "stored")
        eq(N.push({ module = "supply", key = "a", text = "第二次", target = { page = "supply" } }), "merged", "merged")
        local list = notices(ns, "supply")
        eq(#list, 1, "one notice"); eq(list[1].text, "第二次", "newest text"); eq(list[1].count, 2, "count")
        eq(N.unread(), 1, "unread once")
        eq(N.push({ module = "supply", key = "b", text = "別的" }), "stored", "another key")
        eq(N.unread(), 2, "two")
        eq(N.push({ module = "supply", text = "沒有 key" }), "bad", "no key")
        eq(N.push({ module = "", key = "x", text = "沒有模組" }), "bad", "no module")
        eq(N.push({ module = "supply", key = "x", text = "" }), "bad", "no text")
    end))

    test("GF-014 throttle: a read notice that comes back soon stays read; later it is new again; chat at most once a minute", done(function()
        local ns = login()
        local N = ns.Notify
        wow.clearPrinted()
        N.push({ module = "supply", key = "a", text = "一" })
        N.markRead(N.find("supply", "a"))
        eq(N.push({ module = "supply", key = "a", text = "二" }), "quiet", "within the throttle: quiet")
        eq(N.unread(), 0, "still read")
        wow.advance(N.THROTTLE + 1)
        eq(N.push({ module = "supply", key = "a", text = "三" }), "merged", "after the throttle")
        eq(N.unread(), 1, "new again")
        wow.clearPrinted()
        for i = 1, 8 do N.push({ module = "supply", key = "k" .. i, text = "第" .. i .. "則" }); wow.advance(5) end
        wow.advance(N.ALERT_GAP + 2)
        local lines = chatLines("業務通知")
        ok(lines >= 1 and lines <= 2, "8 notices in 40 s: one or two chat lines, got " .. lines)
        N.setChat(false)
        wow.clearPrinted()
        N.push({ module = "supply", key = "quiet", text = "不出聲" })
        wow.advance(N.ALERT_GAP + 2)
        eq(chatLines("業務通知"), 0, "chat line switched off")
    end))

    test("GF-014 burst: at most N.BURST new notices of one module a minute, the rest counted", done(function()
        local ns = login()
        local N = ns.Notify
        local stored = 0
        for i = 1, N.BURST + 5 do
            if N.push({ module = "supply", key = "burst" .. i, text = "x" .. i }) == "stored" then stored = stored + 1 end
        end
        eq(stored, N.BURST, "capped")
        eq(N.stats.burst, 5, "the rest counted")
        eq(N.push({ module = "radar", key = 1, text = "其他模組照常" }), "stored", "other modules unaffected")
    end))

    test("GF-014 combat: a push only waits (merged by key); after combat it is handled", done(function()
        local ns = login()
        local N = ns.Notify
        wow.enterCombat()
        eq(N.push({ module = "supply", key = "c", text = "戰鬥中一" }), "queued", "queued")
        eq(N.push({ module = "supply", key = "c", text = "戰鬥中二" }), "queued", "queued again")
        eq(N.push({ module = "supply", key = "d", text = "戰鬥中三" }), "queued", "another key")
        eq(#notices(ns), 0, "nothing stored in combat")
        eq(N.queued(), 2, "two keys waiting")
        wow.clearPrinted()
        wow.advance(120)
        eq(chatLines("業務通知"), 0, "no chat line in combat")
        wow.leaveCombat()
        wow.advance(1)
        local list = notices(ns, "supply")
        eq(#list, 2, "both handled after combat")
        eq(N.find("supply", "c").text, "戰鬥中二", "the newest text of the merged key")
        eq(N.queued(), 0, "queue empty")
    end))

    test("GF-014 switches: a module switched off adds nothing and its notices hide; settings only", done(function()
        local ns = login()
        local N = ns.Notify
        N.push({ module = "radar", key = 5, text = "雷達一" })
        N.setEnabled("radar", false)
        eq(N.enabled("radar"), false, "off")
        eq(N.push({ module = "radar", key = 6, text = "雷達二" }), "off", "dropped")
        eq(#notices(ns, "radar"), 0, "hidden")
        eq(N.unread(), 0, "not counted")
        eq(N.push({ module = "supply", key = 1, text = "配對" }), "stored", "the other module still on")
        ok(GreenFangToolkitDB.settings.modules.notify.off.radar == true, "kept in the settings")
        N.setEnabled("radar", true)
        eq(#notices(ns, "radar"), 1, "the kept one is back")
        -- switched off in combat: what waits for it is dropped
        wow.enterCombat()
        N.push({ module = "radar", key = 7, text = "排隊" })
        N.setEnabled("radar", false)
        wow.leaveCombat(); wow.advance(1)
        N.setEnabled("radar", true)
        eq(N.find("radar", 7), nil, "not stored after combat")
    end))

    test("GF-014 keep: at most N.MAX_KEEP, each until its time; per character; long text cut", done(function()
        local ns = login()
        local N = ns.Notify
        N.BURST = 1000
        for i = 1, 70 do N.push({ module = "supply", key = "keep" .. i, text = "第" .. i .. "則" }) end
        N.BURST = 10
        eq(#N.store().list, N.MAX_KEEP, "capped")
        ok(N.find("supply", "keep70") and not N.find("supply", "keep1"), "the oldest went")
        N.push({ module = "supply", key = "short", text = "一小時", ttl = 3600 })
        wow.advance(3601)
        eq(N.find("supply", "short"), nil, "past its ttl")
        wow.advance(N.TTL)
        eq(#N.list(), 0, "all past their time")
        local long = string.rep("長", 80)
        N.push({ module = "supply", key = "long", text = long })
        ok(#N.find("supply", "long").text <= N.TEXT_MAX + 3, "cut")
        ok(N.find("supply", "long").text:sub(-3) == "...", "marked as cut")
        ok(GreenFangToolkitDB.notify.chars["Player-0000-0000000A"], "kept per character (GUID)")
    end))

    test("GF-014 click: the page opens and the module's focus finds the record; no focus: the page only", done(function()
        local ns = login()
        local N = ns.Notify
        local got
        ns.Framework.register({ id = "gf014test", title = "測試頁", entry = "settings", create = function() end,
            focus = function(id, target) got = { id, target.tab }; return true end })
        N.push({ module = "supply", key = "f", text = "有定位", target = { page = "gf014test", id = 42, tab = "x" } })
        local e = N.find("supply", "f")
        eq(N.open(e), "focused", "focused")
        eq(got[1], 42, "focus(id)"); eq(got[2], "x", "with the target")
        eq(ns.Framework.current(), "gf014test", "the page is shown")
        eq(e.unread, false, "read")
        N.push({ module = "supply", key = "g", text = "沒定位", target = { page = "roster", id = 1 } })
        eq(N.open(N.find("supply", "g")), "page", "page only")
        eq(ns.Framework.current(), "roster", "roster shown")
        N.push({ module = "supply", key = "h", text = "不存在", target = { page = "nope" } })
        eq(N.open(N.find("supply", "h")), "none", "unknown page: nothing")
    end))

    ---------------------------------------------------------------------------
    -- The bell (NotifyUI)
    ---------------------------------------------------------------------------

    test("GF-014 bell: game icon + 業務通知 + unread count on the main window; the list closes by X, ESC, outside", done(function()
        local ns = login()
        local N, UI = ns.Notify, ns.NotifyUI
        ns.Framework.open("roster")
        local b = UI.button()
        ok(b and b:IsShown(), "the bell is on the main window")
        eq(b._parent, _G[ns.Framework.WINDOW_NAME], "child of the main window")
        eq(b.text:GetText(), "業務通知", "short name")
        ok(b.icon.gfPath and b.icon.gfPath:find("^Interface\\Icons\\"), "a game icon")
        ok(not b.count:IsShown(), "no count without unread")
        N.push({ module = "supply", key = "u1", text = "一則", target = { page = "supply" } })
        N.push({ module = "radar", key = SCROLL, text = "雷達", actions = ns.SupplyRadar.ACTIONS, target = { page = "supply", tab = "guild", id = SCROLL } })
        eq(b.count:GetText(), "2", "unread count")
        wow.click(b)
        local list = UI.list()
        ok(list and list:IsShown(), "list open")
        ok(list.rows[1]:IsShown() and list.rows[2]:IsShown(), "two rows")
        ok(list.rows[1].actions[1]:IsShown() and list.rows[1].actions[1]:GetText() == "查看需求", "radar actions on its row")
        ok(not list.rows[2].actions[1]:IsShown(), "no buttons on a plain notice")
        ok(not list.readAll.disabled, "全部已讀 can be pressed")
        wow.click(list.readAll)
        eq(N.unread(), 0, "all read")
        ok(list.readAll.disabled, "全部已讀 cannot be pressed now (does not light)")
        ok(not b.count:IsShown(), "count gone")
        wow.pressEscape()
        ok(not list:IsShown(), "ESC closes it")
        ok(ns.Framework.isShown(), "the main window stays")
        wow.click(b)
        local blocker = ns.clickBlocker()
        ok(blocker and blocker:IsShown(), "click-outside blocker")
        blocker._scripts.OnClick(blocker)
        ok(not list:IsShown(), "a click outside closes it")
        wow.click(b)
        list.close._scripts.OnClick(list.close)
        ok(not list:IsShown(), "X closes it")
        -- the switches inside the list
        wow.click(b)
        wow.click(list.setup)
        ok(list.settings:IsShown(), "設定")
        local radarBox
        for _, c in ipairs(list.settings.boxes) do if c.key == "radar" then radarBox = c end end
        ok(radarBox and radarBox.gfOn == true, "需求雷達 on")
        radarBox:SetChecked(false); radarBox._scripts.OnClick(radarBox)
        eq(N.enabled("radar"), false, "switched off from the list")
    end))

    test("GF-014 bell: text is 16 px or more, no glyphs outside the game font", done(function()
        local ns = login()
        ns.Framework.open("roster")
        local UI = ns.NotifyUI
        ns.Notify.push({ module = "supply", key = 1, text = "一則" })
        UI.open()
        local f = UI.list()
        for _, fs in ipairs({ UI.button().text, f.title, f.rows[1].text, f.rows[1].tag, f.rows[1].when }) do
            ok(fs._font == ns.LABEL_FONT or fs._font == ns.FIELD_FONT, "the toolkit's 16 px fonts: " .. tostring(fs._font))
        end
        eq(UI.ago(T0()), "剛剛", "just now")
        eq(UI.ago(T0() - 3 * 3600), "3 小時前", "hours")
    end))

    ---------------------------------------------------------------------------
    -- Supply matches (module "supply")
    ---------------------------------------------------------------------------

    test("GF-014 match: B publishes a supply for my need, one notice; the same packet again adds nothing; C too merges", done(function()
        local ns = login()
        local N = ns.Notify
        ok(ns.SupplyListings.create({ direction = "need", itemID = SCROLL, quantity = 1, days = 14, note = "", category = "recipe" }), "my need")
        wow.advance(5)
        eq(#notices(ns, "supply"), 0, "no match yet")
        listings(ns, A_B, PEER_B, { { "offer", SCROLL, 1 } })
        wow.advance(4)
        local list = notices(ns, "supply")
        eq(#list, 1, "one notice")
        eq(list[1].key, "need:" .. SCROLL, "by item and direction")
        ok(list[1].text:find("配方：測試藥水", 1, true) and list[1].text:find("1 位", 1, true), "names the item: " .. list[1].text)
        eq(list[1].target.page, "supply", "goes to the page"); eq(list[1].target.id, SCROLL, "and the item")
        N.markRead(list[1])
        listings(ns, A_B, PEER_C, { { "offer", SCROLL, 1 } }) -- the same, relayed
        wow.advance(4)
        eq(N.unread(), 0, "nothing new")
        listings(ns, A_C, PEER_C, { { "offer", SCROLL, 2 } })
        wow.advance(4)
        list = notices(ns, "supply")
        eq(#list, 1, "still one notice")
        ok(list[1].text:find("2 位", 1, true), "two people now: " .. list[1].text)
        -- clicking finds the item on the page
        eq(N.open(list[1]), "focused", "focused")
        eq(ns.SupplyUI.state.tab, "need", "我缺的")
        eq(ns.SupplyUI.state.items[ns.SupplyUI.state.selected].itemID, SCROLL, "the item is chosen")
    end))

    test("GF-014 match: the one who needs hears nothing until the holder publishes a supply", done(function()
        local ns = login({ bag = { { SCROLL, 1 } } })
        -- We hold the item B needs: the radar tells us; B is told nothing (nothing is sent).
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        wow.advance(4)
        eq(#notices(ns, "radar"), 1, "the radar hit is ours only")
        eq(#notices(ns, "supply"), 0, "no match: we have no published offer")
        local l = ns.Share.get(ns.Share.selfAuthor(), "L")
        ok(not l or l.v == "", "no listing of ours was made")
        -- Our need, and B offers: our notice comes from B's published listing only.
        ns.SupplyListings.create({ direction = "need", itemID = CLOTH, quantity = 1, days = 14, note = "", category = "material" })
        wow.advance(4)
        eq(#notices(ns, "supply"), 0, "B has not offered")
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 }, { "offer", CLOTH, 3 } }, T0() - 30)
        wow.advance(4)
        eq(#notices(ns, "supply"), 1, "after B published the offer")
    end))

    test("GF-014 match: switched off, no notice; many items, one summary past N per check", done(function()
        local ns = login()
        local N, R = ns.Notify, ns.SupplyRadar
        N.setEnabled("supply", false)
        ns.SupplyListings.create({ direction = "need", itemID = SCROLL, quantity = 1, days = 14, note = "", category = "recipe" })
        listings(ns, A_B, PEER_B, { { "offer", SCROLL, 1 } })
        wow.advance(4)
        eq(#notices(ns, "supply"), 0, "off")
        N.setEnabled("supply", true)
        -- 8 items I need, B offers them all
        local offers = {}
        for i = 1, 8 do
            local id = 20000 + i
            G.items[id] = { name = "測試物品" .. i, classID = 7, bindType = 0 }
            ns.SupplyListings.create({ direction = "need", itemID = id, quantity = 1, days = 14, note = "", category = "material" })
            offers[#offers + 1] = { "offer", id, 1 }
        end
        listings(ns, A_C, PEER_C, offers)
        wow.advance(4)
        local list = notices(ns, "supply")
        eq(#list, R.PER_RUN + 1, "PER_RUN notices and one summary")
        -- 9 items: the 8 and the SCROLL match from while it was off (now new to the player)
        ok(N.find("supply", "need:more").text:find("另有 4 項", 1, true), "summary: " .. N.find("supply", "need:more").text)
    end))

    ---------------------------------------------------------------------------
    -- The local radar (module "radar")
    ---------------------------------------------------------------------------

    test("GF-014 radar: a guild need in my bag is a local notice with 查看需求 / 忽略 / 刊登; nothing is sent", done(function()
        local ns = login({ bag = { { SCROLL, 2 } } })
        local N, R, S = ns.Notify, ns.SupplyRadar, ns.Share
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        listings(ns, A_C, PEER_C, { { "need", SCROLL, 1 } })
        local sentBefore, chatBefore = #wow.state.sent, #chatSent
        local own, calls = S.ownRecord, 0
        S.ownRecord = function(...) calls = calls + 1; return own(...) end
        local selfRecs = 0
        for _ in pairs(S.store().rec[S.selfAuthor()] or {}) do selfRecs = selfRecs + 1 end
        R.checkNow()
        S.ownRecord = own
        eq(#wow.state.sent, sentBefore, "no addon message")
        eq(#chatSent, chatBefore, "no chat, no whisper")
        eq(calls, 0, "no record of ours written")
        local after = 0
        for _ in pairs(S.store().rec[S.selfAuthor()] or {}) do after = after + 1 end
        eq(after, selfRecs, "our records unchanged")
        local list = notices(ns, "radar")
        eq(#list, 1, "one hit")
        ok(list[1].text:find("x2", 1, true) and list[1].text:find("2 位職工", 1, true), "how many I have, how many need it: " .. list[1].text)
        eq(#list[1].actions, 3, "three buttons")
        eq(list[1].actions[1].text, "查看需求", "查看需求"); eq(list[1].actions[2].text, "忽略", "忽略"); eq(list[1].actions[3].text, "刊登", "刊登")
        -- across a logout nothing of the radar reaches GF Sync's outbox
        local saved = wow.logout()
        local text = wow.serializeSV("GreenFangToolkitDB", saved.GreenFangToolkitDB.sync or {})
        ok(not text:find("配方：測試藥水", 1, true) and not text:find("背包", 1, true), "nothing in the outbox")
    end))

    test("GF-014 radar: bound, locked, bind-on-pickup and unknown items are not a hit; only received guild needs count", done(function()
        local ns = login({ bag = { { SCROLL, 1, true }, { CLOTH, 1, false, true }, { BOP, 1 }, { MYSTERY, 1 }, { 30001, 5 } } })
        local R = ns.SupplyRadar
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 }, { "need", CLOTH, 1 }, { "need", BOP, 1 }, { "need", MYSTERY, 1 } })
        local hits = R.checkBags()
        eq(next(hits), nil, "no hit: " .. tostring(next(hits)))
        eq(#notices(ns, "radar"), 0, "no notice")
        ok(R.stats.skippedBound >= 3, "bound / locked / bind on pickup counted")
        ok(R.stats.skippedUnknown >= 1, "unknown counted")
        local want = R.wanted()
        eq(want[30001], nil, "a bag item nobody asked for is not even looked at")
        -- the same check with nothing wanted reads no bag at all
        local reads = R.stats.bagReads
        listings(ns, A_B, PEER_B, {}, T0() - 10)
        R.checkBags()
        eq(R.stats.bagReads, reads, "no guild need: the bag is not read")
    end))

    test("GF-014 radar: my own need, an item I already offer, and an expired need are not hits", done(function()
        local ns = login({ bag = { { SCROLL, 1 }, { CLOTH, 4 } } })
        local R = ns.SupplyRadar
        ns.SupplyListings.create({ direction = "need", itemID = SCROLL, quantity = 1, days = 14, note = "", category = "recipe" })
        ns.SupplyListings.create({ direction = "offer", itemID = CLOTH, quantity = 4, days = 14, note = "", category = "material" })
        listings(ns, A_B, PEER_B, { { "need", CLOTH, 1 } })
        eq(next(R.checkBags()), nil, "own need is not a guild need; CLOTH is offered already")
        local t = T0() - 8 * 86400
        listings(ns, A_C, PEER_C, { { "need", SCROLL, 1 } }, t) -- expired (7 days)
        eq(next(R.checkBags()), nil, "an expired need does not count")
    end))

    test("GF-014 radar: bag events debounce 3 s, combat only marks dirty, one check after combat", done(function()
        local ns = login({ bag = {} })
        local R = ns.SupplyRadar
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        wow.advance(4)
        local checks = R.stats.checks
        for _ = 1, 5 do wow.fire("BAG_UPDATE_DELAYED"); wow.advance(1) end
        eq(R.stats.checks, checks, "not yet: 3 s after the last event")
        wow.advance(3)
        eq(R.stats.checks, checks + 1, "one check")
        wow.enterCombat()
        G.bag = { { SCROLL, 1 } }
        for _ = 1, 10 do wow.fire("BAG_UPDATE_DELAYED"); wow.advance(2) end
        wow.advance(30)
        eq(R.stats.checks, checks + 1, "no check in combat")
        ok(R.dirty, "dirty")
        eq(#notices(ns, "radar"), 0, "nothing yet")
        wow.leaveCombat()
        wow.advance(4)
        eq(R.stats.checks, checks + 2, "one check after combat")
        eq(#notices(ns, "radar"), 1, "the hit")
        -- the item leaves the bag: the notice goes
        G.bag = {}
        bagEvent(ns)
        eq(#notices(ns, "radar"), 0, "gone with the item")
    end))

    test("GF-014 radar: 忽略 keeps it quiet; 刊登 opens the form (供應, the item) and sends nothing; 查看需求 finds it", done(function()
        local ns = login({ bag = { { SCROLL, 1 } } })
        local N, R = ns.Notify, ns.SupplyRadar
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        wow.advance(4)
        local e = notices(ns, "radar")[1]
        ok(e, "hit")
        eq(N.action(e, "view"), "focused", "查看需求")
        eq(ns.SupplyUI.state.tab, "guild", "公會供需")
        eq(ns.SupplyUI.state.items[ns.SupplyUI.state.selected].itemID, SCROLL, "the item chosen")
        local sentBefore = #wow.state.sent
        eq(N.action(e, "post"), "post", "刊登")
        local f = ns.SupplyUI.form()
        ok(f and f:IsShown(), "the form")
        eq(ns.SupplyUI.formState.direction, "offer", "供應")
        eq(ns.SupplyUI.formState.itemID, SCROLL, "the item")
        wow.advance(1)
        eq(#wow.state.sent, sentBefore, "nothing sent before the player saves")
        eq(#ns.SupplyListings.ownActive(), 0, "no listing made by itself")
        f.CloseButton._scripts.OnClick(f.CloseButton)
        N.action(e, "ignore")
        eq(#notices(ns, "radar"), 0, "忽略: gone")
        G.bag = { { SCROLL, 2 } }
        bagEvent(ns)
        eq(#notices(ns, "radar"), 0, "ignored stays quiet")
        wow.advance(R.IGNORE_TTL + 1)
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } }, T0() - 10)
        bagEvent(ns)
        eq(#notices(ns, "radar"), 1, "after the ignore time it may come back")
    end))

    test("GF-014 radar: switched off, the radar adds nothing; the same hit twice is one notice", done(function()
        local ns = login({ bag = { { SCROLL, 1 } } })
        local N = ns.Notify
        N.setEnabled("radar", false)
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        wow.advance(4)
        eq(#ns.Notify.store().list, 0, "nothing stored")
        N.setEnabled("radar", true)
        bagEvent(ns)
        eq(#notices(ns, "radar"), 1, "on again")
        N.markRead(notices(ns, "radar")[1])
        bagEvent(ns); bagEvent(ns)
        eq(#notices(ns, "radar"), 1, "one notice"); eq(N.unread(), 0, "no new unread for the same hit")
    end))

    test("GF-014 diagnostics: a section for 業務通知 and the radar; no GUID or account", done(function()
        local ns = login({ bag = { { SCROLL, 1 } } })
        listings(ns, A_B, PEER_B, { { "need", SCROLL, 1 } })
        wow.advance(4)
        local text = ns.Notify.diagText() .. ns.SupplyRadar.diagText()
        ok(text:find("業務通知", 1, true) and text:find("需求雷達", 1, true), text)
        ok(not text:find("Player%-") and not text:find("0000%-"), "no GUID")
        ok(not text:find("配方：測試藥水", 1, true), "no item of the bag")
    end))

    ---------------------------------------------------------------------------
    -- Synthetic load (spec v2.0 §7.5, §12.2)
    ---------------------------------------------------------------------------

    test("GF-014 100 / 300 / 1000 members: one radar + match check stays bounded, one bag read, nothing sent", done(function()
        for _, n in ipairs({ 100, 300, 1000 }) do
            local roster = wow.defaultRoster()
            for i = 1, n do
                roster[#roster + 1] = { name = "合成" .. i .. "-測試伺服器", rank = "會員", level = 30, class = "戰士", classToken = "WARRIOR",
                    zone = "奧格瑪", online = i % 3 == 0, guid = string.format("Player-0000-%08X", 4096 + i) }
            end
            local bag = {}
            for k = 1, 20 do bag[k] = { 40000 + k, 1 } end
            local items = {}
            for k = 1, 60 do items[40000 + k] = { name = "合成物品" .. k, classID = 7, bindType = 0 } end
            local ns = login({ roster = roster, bag = bag, items = items })
            for k = 1, 5 do ns.SupplyListings.create({ direction = "need", itemID = 40040 + k, quantity = 1, days = 14, note = "", category = "material" }) end
            local S = ns.Share
            local t = T0() - 120
            for i = 1, n do
                local a = string.format("0000-%08X", 4096 + i)
                local list = {
                    { id = 1, direction = "need", category = "material", itemID = 40001 + (i % 30), quantity = 1, createdAt = t, expiresAt = t + 86400 * 7, rev = 1, note = "" },
                    { id = 2, direction = "offer", category = "material", itemID = 40041 + (i % 10), quantity = 2, createdAt = t, expiresAt = t + 86400 * 7, rev = 1, note = "" },
                }
                local v = ns.SupplyListings.encode(list)
                S.offer(a, "L", t, S.hash(v), v, true, a)
            end
            ns.Supply.invalidate()
            local R = ns.SupplyRadar
            local reads, sentBefore = R.stats.bagReads, #wow.state.sent
            local c0 = os.clock()
            R.checkNow()
            local ms = (os.clock() - c0) * 1000
            eq(R.stats.bagReads, reads + 1, "one bag read")
            eq(#wow.state.sent, sentBefore, "nothing sent")
            ok(#notices(ns, "radar") >= 1 and #notices(ns, "radar") <= R.PER_RUN, "bounded radar notices")
            ok(#notices(ns, "supply") >= 1 and #notices(ns, "supply") <= R.PER_RUN + 2, "bounded match notices")
            ok(#ns.Notify.store().list <= ns.Notify.MAX_KEEP, "store capped")
            ok(ms < 2000, n .. " members in " .. ms .. " ms")
            -- a second check with nothing new: no new notices
            local unread = ns.Notify.unread()
            R.checkNow()
            eq(ns.Notify.unread(), unread, "nothing new the second time")
            T.realPrint(string.format("     PERF GF-014: %d members, radar + match check %.0f ms", n, ms))
            removeGame()
        end
    end))
end
