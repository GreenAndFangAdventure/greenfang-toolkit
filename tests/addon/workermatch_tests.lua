-- GF-014-02: 職工單配對 — my worker ticket against other members' adventure
-- tickets, one 業務通知 per ticket (key match|<id>), cleared when it no longer
-- fits, per-character switches in 業務通知 → 設定. Nothing is sent: the
-- player presses 申請. Offline only (MANUAL §GF-014-02). Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B, C = "0000-0000000B", "0000-0000000C"
    local H = 3600

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local r = ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    -- B's adventure ticket (墓地, a slot from now for 2 hours unless given).
    local function ticket(ns, a, over)
        local t = ns.Share.serverNow()
        local e = { id = "a" .. a:sub(-3) .. ".1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } }),
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t }
        for k, v in pairs(over or {}) do e[k] = v end
        offer(ns, a, "T", { e })
        return e.id
    end
    local function myWorker(ns, over)
        local o = { dungeons = { "smg" }, quests = {}, main = "t", alt = "h", slots = { { now = true } } }
        for k, v in pairs(over or {}) do o[k] = v end
        ok(ns.Adventure.setWorker(o), "my worker ticket")
    end
    local function notices(ns)
        local out = {}
        for _, e in ipairs(ns.Notify.list()) do if e.module == "adventure" then out[#out + 1] = e end end
        return out
    end

    test("GF-014-02 a fitting ticket: one notice, its target, the text; I apply myself", function()
        local ns = login()
        local M, N = ns.WorkerMatch, ns.Notify
        myWorker(ns)
        local id = ticket(ns, B)
        local sentBefore = #(GreenFangToolkitDB.sync and GreenFangToolkitDB.sync.outbox or {})
        local list = M.scan()
        eq(#list, 1, "one match")
        local e = notices(ns)[1]
        ok(e, "a notice")
        eq(e.key, "match|" .. id, "key match|<id>")
        eq(e.target.page, "adventure", "target page"); eq(e.target.id, id, "target id")
        ok(e.text:find("職工單配對", 1, true) and e.text:find("墓地", 1, true) and e.text:find("缺坦", 1, true), "text: " .. e.text)
        ok(not e.text:find("|T", 1, true), "plain text")
        -- No application was made, nothing new was queued to upload.
        local v = ns.Adventure.get(id)
        eq(#v.pending + #v.waitlist + #v.members, 0, "nobody applied")
        eq(#(GreenFangToolkitDB.sync and GreenFangToolkitDB.sync.outbox or {}), sentBefore, "nothing new in the outbox")
        -- The click: 冒險業務 at that ticket.
        eq(N.open(e), "focused", "the notice opens the ticket")
        eq(ns.AdventureUI.focusId, id, "UI.focus on it")
    end)

    test("GF-014-02 one notice per ticket: rescans do not repeat it; a changed ticket merges into it", function()
        local ns = login()
        local M, N = ns.WorkerMatch, ns.Notify
        myWorker(ns)
        local id = ticket(ns, B)
        M.scan()
        local e = notices(ns)[1]
        N.markRead(e)
        for _ = 1, 3 do M.scan() end
        eq(#notices(ns), 1, "still one")
        eq(e.unread, false, "read stays read")
        eq(e.count, 1, "not pushed again")
        -- The leader edits the ticket (a new edit time): the same notice, newer.
        wow.advance(3600)
        ticket(ns, B, { ed = ns.Share.serverNow(), ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = ns.Share.serverNow(), d = 3 * H } }) })
        M.scan()
        eq(#notices(ns), 1, "merged, not a second one")
        eq(notices(ns)[1].count, 2, "merged once")
        eq(notices(ns)[1].key, "match|" .. id, "same key")
    end)

    test("GF-014-02 ranking: shared quests first, then the place; quest-only matches follow the switch", function()
        local ns = login()
        local M, Adv = ns.WorkerMatch, ns.Adventure
        myWorker(ns, { quests = { 850, 851 } })
        local placeOnly = ticket(ns, B)
        local t = ns.Share.serverNow()
        offer(ns, C, "T", { { id = "accc.1", src = "g", ver = 1, cr = t, ds = "", qs = "850.851", tm = "n",
            ts = Adv.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } }), ra = 4,
            rt = 0, rh = 0, rd = 0, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        local list = M.candidates()
        eq(#list, 2, "both fit")
        eq(list[1].view.id, "accc.1", "the shared quests first")
        eq(list[1].shared, 2, "two shared quests"); eq(list[2].view.id, placeOnly, "then the dungeon")
        M.set("quests", false)
        list = M.candidates()
        eq(#list, 1, "quest-only does not count when switched off")
        eq(list[1].view.id, placeOnly, "the dungeon still does")
        eq(#notices(ns), 1, "its notice went with the switch")
    end)

    test("GF-014-02 cleared: ticket cancelled, no seat for my role (main only), I applied, my worker ticket gone", function()
        local ns = login()
        local M, Adv = ns.WorkerMatch, ns.Adventure
        myWorker(ns)
        local id = ticket(ns, B)
        M.scan(); eq(#notices(ns), 1, "matched")
        -- Only a healer seat left: my support role (補) still fits ...
        ticket(ns, B, { rt = 0, rh = 1, rd = 3 })
        M.scan(); eq(#notices(ns), 1, "my support role fits")
        -- ... until 副職責也算 is off.
        M.set("alt", false)
        eq(#notices(ns), 0, "main only: cleared")
        M.set("alt", true)
        eq(#notices(ns), 1, "back")
        -- I apply (the player's own click): I am in it now.
        Adv.worker(id, "apply")
        Adv.refresh()
        M.scan(); eq(#notices(ns), 0, "applied: cleared")
        Adv.worker(id, "withdraw"); Adv.refresh(); M.scan()
        eq(#notices(ns), 1, "withdrawn: fits again")
        -- The leader cancels.
        ticket(ns, B, { st = "x", sa = ns.Share.serverNow() })
        M.scan(); eq(#notices(ns), 0, "cancelled: cleared")
        -- A new one, then my worker ticket goes.
        ticket(ns, C)
        M.scan(); eq(#notices(ns), 1, "another one")
        Adv.removeWorker(); Adv.refresh()
        M.scan(); eq(#notices(ns), 0, "my worker ticket gone: cleared")
    end)

    test("GF-014-02 the ttl: the end of the ticket's last slot or my worker ticket, whichever is first", function()
        local ns = login()
        local M = ns.WorkerMatch
        myWorker(ns, { slots = { { now = true } } })
        local t = ns.Share.serverNow()
        ticket(ns, B, { ts = ns.Adventure.encodeTimes({ { id = 1, now = true, s = t, d = 2 * H } }) })
        M.scan()
        local e = notices(ns)[1]
        ok(math.abs(e.expires - (t + 2 * H)) <= 2, "ends with the slot: " .. (e.expires - t))
        -- My worker ticket ends first (1 hour).
        ns.Notify.clear("adventure"); ns.Notify.memory("adventure").sent = {}
        myWorker(ns, { hours = 1 })
        M.scan()
        e = notices(ns)[1]
        ok(math.abs(e.expires - (t + H)) <= 2, "ends with my worker ticket: " .. (e.expires - t))
        wow.advance(H + 5)
        ns.Notify.prune()
        eq(#notices(ns), 0, "gone at its ttl")
    end)

    test("GF-014-02 switches: per character, in 業務通知 → 設定; off clears and stops; chat line only when asked", function()
        local ns = login()
        local M, N = ns.WorkerMatch, ns.Notify
        eq(M.get("on"), true, "on by default"); eq(M.get("alt"), true, "support role by default")
        eq(M.get("quests"), true, "quests by default"); eq(M.get("chat"), false, "no extra chat line by default")
        -- The rows under 設定.
        local parent = CreateFrame("Frame", nil, UIParent)
        local boxes = ns.NotifyUI.buildSettings(parent, 12, -40)
        local byKey = {}
        for _, c in ipairs(boxes) do byKey[c.key] = c end
        ok(byKey["adventure.on"] and byKey["adventure.alt"] and byKey["adventure.quests"] and byKey["adventure.chat"], "four rows")
        ok(byKey["adventure.alt"].sub and not byKey["adventure.on"].sub, "sub-options indented")
        ok(byKey.supply and byKey.radar and byKey["\1chat"], "the other switches stay")
        myWorker(ns)
        ticket(ns, B)
        M.scan(); eq(#notices(ns), 1, "on")
        byKey["adventure.on"]:SetChecked(false); byKey["adventure.on"]._scripts.OnClick(byKey["adventure.on"])
        eq(M.get("on"), false, "the box turns it off")
        eq(#notices(ns), 0, "off: cleared")
        M.scan(); eq(#notices(ns), 0, "off: nothing new")
        -- Stored for this character only.
        local key = ns.Framework.charKey()
        eq(GreenFangToolkitDB.settings.modules.notify.characters[key].workerMatch.on, false, "per character")
        M.set("on", true)
        -- The chat line.
        wow.state.printed = {}
        ns.Notify.clear("adventure"); ns.Notify.memory("adventure").sent = {}
        M.scan()
        local said = 0
        for _, l in ipairs(wow.state.printed) do if l:find("職工單配對", 1, true) then said = said + 1 end end
        eq(said, 0, "no chat line by default")
        M.set("chat", true)
        ns.Notify.clear("adventure"); ns.Notify.memory("adventure").sent = {}
        M.scan()
        ticket(ns, C); M.scan()
        said = 0
        for _, l in ipairs(wow.state.printed) do if l:find("職工單配對", 1, true) then said = said + 1 end end
        eq(said, 1, "one line, at most one a minute")
    end)

    test("GF-014-02 combat: the notice waits; a ledger change scans by itself after a moment", function()
        local ns = login()
        local M = ns.WorkerMatch
        myWorker(ns)
        wow.advance(5)
        wow.enterCombat()
        ticket(ns, B)
        wow.advance(M.DEBOUNCE + 1)
        eq(#notices(ns), 0, "nothing shown in combat")
        eq(ns.Notify.queued(), 1, "waiting")
        wow.leaveCombat()
        wow.advance(1)
        eq(#notices(ns), 1, "shown after combat")
        -- WorkerMatch writes nothing to share: no ledger group, no message, no upload.
        local src = assert(io.open(ADDON_DIR .. "/WorkerMatch.lua", "r")):read("*a")
        for _, bad in ipairs({ ":offer(", "SendAddonMessage", "outbox", "Comm.", "Sync.", "setWorker", "Adventure().worker(" }) do
            ok(not src:find(bad, 1, true), "WorkerMatch never uses " .. bad)
        end
    end)
end
