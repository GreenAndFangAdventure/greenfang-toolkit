-- GF-002-C (0.12.1): the game's own art in the 冒險 and 訂單 tabs, with
-- fallbacks. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B = "0000-0000000B"
    local BS = "\\"
    local ROLES = "Interface" .. BS .. "LFGFrame" .. BS .. "UI-LFG-ICON-ROLES"
    local SM = "Interface" .. BS .. "LFGFrame" .. BS .. "LFGIcon-ScarletMonastery"
    local KEY = "Interface" .. BS .. "Icons" .. BS .. "INV_Misc_Key_03"
    local DEFEND = "Interface" .. BS .. "Icons" .. BS .. "Ability_Defend"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Adventure.resetSession()
        ns.GameIcons.reset()
        return ns
    end
    local function tex()
        local f = CreateFrame("Frame")
        return f:CreateTexture(nil, "ARTWORK")
    end
    local function ticket(id, extra)
        local e = { id = id, src = "g", ver = 1, cr = 1763000000, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "o", sa = 1763000000 }
        for k, v in pairs(extra or {}) do e[k] = v end
        return e
    end

    -- GF-002-F: the role sheet came out dark and cut in half on 16001; whole
    -- spell icons first, the sheet (with its box) is the last fallback.
    test("GF-002-C role art: whole spell icons first; the group finder sheet with its box as the last fallback", function()
        local STANCE = "Interface\\Icons\\Ability_Warrior_DefensiveStance"
        local ns = login()
        local G = ns.GameIcons
        local t = tex()
        ok(G.set(t, "role_t"), "set"); eq(t._texture, STANCE, "defensive stance")
        eq(t._texCoord[2], 1, "full icon (no box)")
        ok(G.markup("role_h", 14):find("Spell_Holy_FlashHeal", 1, true), "markup: the healer icon")
        ns = login({ missingFiles = { [STANCE] = true } })
        G = ns.GameIcons
        t = tex()
        ok(G.set(t, "role_t"), "fallback set"); eq(t._texture, DEFEND, "Ability_Defend instead")
        ns = login({ missingFiles = { [STANCE] = true, [DEFEND] = true } })
        G = ns.GameIcons
        t = tex()
        ok(G.set(t, "role_t"), "last fallback"); eq(t._texture, ROLES, "role sheet")
        eq(t._texCoord[1], 0, "tank box left"); eq(t._texCoord[2], 19 / 64, "tank box right")
    end)

    test("GF-002-C dungeon art: each dungeon its own LFGIcon; the key when missing; never a broken texture", function()
        local ns = login()
        local G = ns.GameIcons
        for _, d in ipairs(ns.AdventureData.DUNGEONS) do ok(G.ART["dungeon_" .. d.id], "art entry for " .. d.id) end
        local t = tex()
        G.set(t, G.dungeonKey("sml")); eq(t._texture, SM, "SM wing -> ScarletMonastery art")
        eq(G.dungeonKey("nope"), "key", "unknown dungeon -> key")
        ns = login({ missingFiles = { [SM] = true } })
        t = tex()
        ok(ns.GameIcons.set(t, ns.GameIcons.dungeonKey("sml")), "fallback")
        eq(t._texture, KEY, "the key")
        -- Every candidate missing: hidden, no error.
        local all = {}
        for _, c in ipairs(ns.GameIcons.ART.role_t) do all[c[1]] = true end
        ns = login({ missingFiles = all })
        t = tex()
        eq(ns.GameIcons.set(t, "role_t"), false, "nothing works -> false"); eq(t._shown, false, "hidden")
        eq(ns.GameIcons.set(t, "no-such-key"), false, "unknown key -> false")
    end)

    test("GF-002-C item 2: one icon per seat, taken ones bright, open ones grey", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        -- 1 tank, 1 healer, 3 dps; the leader is dps -> 1 + 1 + 2 seats; a tank and a dps taken.
        local v = Adv.view(ticket("t1"), B, { ["0000-0000000C"] = { { id = "t1", ac = "ap", at = 10, ro = "t", rb = "" } },
            ["0000-0000000D"] = { { id = "t1", ac = "ap", at = 11, ro = "d", rb = "" } } }, { now = 20 })
        local list = U.slotList(v)
        eq(#list, 4, "4 seats")
        local filled, byRole = 0, {}
        for _, s in ipairs(list) do
            if s.filled then filled = filled + 1 end
            byRole[s.role] = (byRole[s.role] or 0) + 1
        end
        eq(filled, 2, "2 taken"); eq(byRole.t .. byRole.h .. byRole.d, "112", "per role")
        eq(list[1].role .. tostring(list[1].filled), "ttrue", "tank taken"); eq(list[2].filled, false, "healer open")
        -- Quest ticket: a person per seat.
        local q = Adv.view(ticket("t2", { ds = "", qs = "1013", sz = 4 }), B, { ["0000-0000000C"] = { { id = "t2", ac = "ap", at = 10, ro = "d" } } }, { now = 20 })
        list = U.slotList(q)
        eq(#list, 3, "size 4 minus the leader"); eq(list[1].role, "any", "person"); ok(list[1].filled and not list[2].filled, "1 taken")
    end)

    test("GF-002-C the row draws those seats with the game's role art and no '2/3'", function()
        local ns = login()
        local t = ns.Share.serverNow()
        local v = ns.Adventure.encodeList({ ticket("t1", { cr = t }) })
        ns.Adventure.ledger:offer(B, "T", t, ns.Share.hash(v), v)
        ns.Framework.open("adventure")
        local row
        for _, r in ipairs(ns.AdventureUI.rowFrames()) do if r.view and r.view.id == "t1" then row = r end end
        ok(row, "row")
        local shown, grey = 0, 0
        for _, s in ipairs(row.slots) do
            if s._shown then shown = shown + 1; if s._alpha and s._alpha < 1 then grey = grey + 1 end; ok(tostring(s._texture):find("Interface\\Icons\\", 1, true), "role art") end
        end
        eq(shown, 4, "4 seat icons"); eq(grey, 4, "all open (grey)")
        ok(not row.roles:GetText():find("/", 1, true), "no 2/3 text")
        eq(row.name:GetText(), "墓地", "short name; full name in the tooltip")
        local lines = ns.AdventureUI.ticketTooltip(row.view)
        ok(lines[1]:find("血色修道院：墓地", 1, true), "tooltip has the full name and levels")
    end)

    test("GF-002-C time marks: now, clock for today, calendar for later", function()
        local ns = login()
        local U = ns.AdventureUI
        ok(U.timeText({ timeMode = "n" }):find("TimeStop", 1, true), "now")
        ok(U.timeText({ timeMode = "t", start = 1763000000, finish = 1763003600 }):find("PocketWatch", 1, true), "today")
        ok(U.timeText({ timeMode = "f", start = 1763000000, finish = 1763003600 }):find("INV_Misc_Book_09", 1, true), "future (GF-002-F: a book, not the calendar art)")
    end)

    test("GF-002-C item 8: dungeon colours by level (white fits, grey too low, red too high)", function()
        local ns = login()
        local G = ns.GameIcons
        eq(table.concat({ G.levelColor("smg", 30) }, ","), "1,1,1", "fits")
        eq(table.concat({ G.levelColor("smg", 60) }, ","), "0.55,0.55,0.55", "too low for me")
        eq(table.concat({ G.levelColor("smg", 10) }, ","), "1,0.3,0.3", "too high")
        local grid = ns.AdventureUI.dungeonGrid(UIParent, function() end)
        eq(#grid.buttons, #ns.AdventureData.DUNGEONS, "one icon per dungeon")
    end)

    test("GF-002-C item 7: the worker ticket picks dungeons and roles by clicking icons", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openWorker()
        U.pickWorkerDungeons(UIParent)
        local grid = U.grid()
        local sfk
        for _, b in ipairs(grid.buttons) do if b.dungeon == "sfk" then sfk = b end end
        wow.click(sfk)
        eq(d.dungeons[1], "sfk", "picked")
        ok(sfk.badge._shown, "ticked")
        wow.click(sfk)
        eq(#d.dungeons, 0, "click again: removed")
        grid:Hide() -- GF-002-F: the worker window comes back when the picker closes
        local f = _G[U.WORKER_NAME]
        wow.click(f.mainRoles.t)
        eq(d.main, "t", "main role by its icon")
        wow.click(f.altRoles.d)
        eq(d.alt, "d", "second role by its icon")
    end)

    test("GF-002-C fix: only one picker is open at a time (dungeon grid or quest menu)", function()
        local ns = login()
        local U = ns.AdventureUI
        GetNumQuestLogEntries = function() return 1 end
        GetQuestLogTitle = function() return "測試任務", 30, nil, false, false, false, nil, 1013 end
        local menuName = ns.Framework.MENU_NAME
        local function menuOpen() local m = _G[menuName]; return m ~= nil and m:IsShown() end
        local d = U.openTicket()
        U.pickDestination(UIParent)
        local grid = U.grid()
        ok(grid:IsShown(), "grid open"); ok(not menuOpen(), "no menu with it")
        ok(grid.quest:IsShown(), "quest scroll in the grid")
        wow.click(grid.quest)
        ok(menuOpen(), "quest menu open"); ok(not grid:IsShown(), "grid closed")
        U.pickDestination(UIParent)
        ok(grid:IsShown() and not menuOpen(), "grid again; the menu closed")
        U.pickTime(UIParent, "t")
        U.pickStart(UIParent) -- GF-002-D: 開始 has its own menu
        ok(menuOpen() and not grid:IsShown(), "a time menu closes the grid")
        GetNumQuestLogEntries, GetQuestLogTitle = nil, nil
        U.pickDestination(UIParent)
        ok(not grid.quest:IsShown(), "no quest log: no scroll")
        ok(d, "draft")
    end)

    test("GF-002-C orders: page arrows for the quantity, icons on the buttons and headers", function()
        local ns = login()
        local d = ns.OrdersUI.openOrder({ recipe = 2660, skill = 164, crafters = {} })
        local f = _G[ns.OrdersUI.POPUP_NAME]
        ok(f.minus.art and f.minus.art:find("PrevPage", 1, true), "previous-page arrow")
        ok(f.plus.art and f.plus.art:find("NextPage", 1, true), "next-page arrow")
        wow.click(f.plus)
        eq(d.qty, 2, "arrow adds one")
        ok(f.send:GetText():find("^|T"), "下單 has an icon")
        -- Missing arrow art: text buttons, still working.
        local prev = "Interface" .. BS .. "Buttons" .. BS .. "UI-SpellbookIcon-PrevPage-Up"
        ns = login({ missingFiles = { [prev] = true } })
        local b = ns.OrdersUI.arrowButton(UIParent, "prev", "－")
        eq(b:GetText(), "－", "text fallback")
    end)
end
