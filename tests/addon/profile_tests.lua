-- GF-010 (spec v2.0 §5.1, §5.2): role positioning, the personnel file and
-- the roster's role column, filter and 人力盤點. Made-up names and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A_SELF, A_PEER, A_THIRD = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local SELF_GUID, PEER_GUID, THIRD_GUID = "Player-" .. A_SELF, "Player-" .. A_PEER, "Player-" .. A_THIRD
    local PEER, THIRD = "測試乙-測試伺服器", "測試丙-測試伺服器"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function player(over)
        local p = wow.defaultPlayer()
        for k, v in pairs(over or {}) do p[k] = v end
        return p
    end
    -- "S1~V~..." for a role value, as its author (or a relayer) sends it.
    local function vMsg(ns, a, t, v)
        return "S1~V~" .. a .. "~J~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function sentWith(sub)
        local list = {}
        for _, s in ipairs(wow.state.sent) do
            if s.prefix == "GFTKS" and s.msg:find(sub, 1, true) then list[#list + 1] = s.msg end
        end
        return list
    end
    local function rowFor(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end
    local function keysOf(set)
        local out = {}
        for _, r in ipairs({ "t", "h", "d" }) do if set[r] then out[#out + 1] = r end end
        return table.concat(out)
    end

    test("GF-010 codec: main.can round-trips; the main role is always in can; bad values are refused", function()
        local ns = login()
        local P = ns.Profile
        eq(P.encode({ main = "t", can = { d = true } }), "t.td", "main joins can, t h d order")
        eq(P.encode({ main = nil, can = {} }), "0.", "未設定")
        eq(P.encode({ main = nil, can = { h = true } }), "0.h", "no main, can heal")
        local d = P.decode("h.hd")
        eq(d.main, "h", "main"); eq(keysOf(d.can), "hd", "can")
        eq(P.decode("0.").main, nil, "unset decodes to no main (never 輸出)")
        for _, bad in ipairs({ "x.t", "t.d", "t.tt", "t.dt", "t", "", "t.tq", "0.dd" }) do
            eq(P.decode(bad), nil, "refused: " .. bad)
        end
        -- Share refuses a malformed role record (decode fails = invalid).
        eq(ns.Share.offer(A_PEER, "J", ns.Share.serverNow(), ns.Share.hash("t.d"), "t.d", true, A_PEER), "invalid", "malformed")
        ok(ns.Share.isLocalGroup("J"), "J is never uploaded by GF Sync (local)")
        eq(ns.Share.offer(A_PEER, "Jx", ns.Share.serverNow(), ns.Share.hash("t.t"), "t.t", true, A_PEER), "invalid", "unknown group")
    end)

    test("GF-010 own roles: unset by default (not 輸出), main in 可支援, main cannot be removed, by GUID", function()
        local ns = login()
        local P = ns.Profile
        local p = P.roles(SELF_GUID)
        eq(p.main, nil, "no default main role"); eq(keysOf(p.can), "", "nothing to support")
        eq(P.ticketRoles(), nil, "no ticket prefill while unset")
        ok(P.setMain("h"), "set 治療")
        eq(keysOf(P.roles(SELF_GUID).can), "h", "main joins 可支援")
        local okRemove, why = P.setCan("h", false)
        eq(okRemove, false, "the main role stays"); eq(why, "main", "reason")
        ok(P.setCan("t", true), "add 坦克")
        eq(keysOf(P.roles(SELF_GUID).can), "th", "can")
        eq(select(1, P.ticketRoles()), "h", "ticket main"); eq(select(2, P.ticketRoles()), "t", "ticket alt")
        ok(P.setMain("t"), "switch main to 坦克")
        eq(keysOf(P.roles(SELF_GUID).can), "th", "the old main stays as 可支援")
        ok(P.setMain(nil), "back to 未設定")
        eq(P.roles(SELF_GUID).main, nil, "unset")
        -- Saved under the GUID, never a name.
        local chars = GreenFangToolkitDB.profile.chars
        ok(chars[SELF_GUID], "keyed by GUID")
        for k, v in pairs(chars) do
            ok(k:match("^Player%-"), "key is a GUID: " .. tostring(k))
            for field, x in pairs(v) do ok(type(x) ~= "string" or not x:find("測試"), "no names: " .. field) end
        end
        -- Survives a reload.
        P.setMain("d")
        local saved = wow.logout()
        wow.reset()
        local ns2 = wow.login(ADDON_DIR, saved)
        eq(ns2.Profile.roles(SELF_GUID).main, "d", "kept after login")
    end)

    test("GF-010 class table: a mage cannot tank or heal; the page greys those and they never light", function()
        local ns = login({ player = player({ class = "法師", classToken = "MAGE" }) })
        local P = ns.Profile
        eq(P.allowed("MAGE", "t"), false, "mage tank"); eq(P.allowed("MAGE", "d"), true, "mage dps")
        eq(P.allowed("PALADIN", "t"), true, "paladin tank"); eq(P.allowed("NEWCLASS", "h"), true, "unknown class: not blocked")
        for token, row in pairs(P.CLASS_ROLES) do eq(row.verified, false, token .. " marked unverified") end
        ok(P.CLASS_ROLES_SOURCE:find("未經", 1, true), "source names it unverified")
        local okSet, why = P.setMain("t")
        eq(okSet, false, "refused"); eq(why, "class", "reason")
        eq(select(2, P.setCan("h", true)), "class", "可支援 refused too")
        ns.Framework.open("character")
        local c = ns.ProfileUI.controls
        eq(c.main.t.gfEnabled, false, "坦克 disabled"); eq(c.main.d.gfEnabled, true, "輸出 enabled")
        ok(not c.main.t.sel:IsShown(), "a disabled role does not light")
        wow.click(c.main.t)
        eq(P.roles(SELF_GUID).main, nil, "clicking a disabled role does nothing")
        wow.click(c.main.d)
        eq(P.roles(SELF_GUID).main, "d", "輸出 chosen")
        ok(c.main.d.sel:IsShown(), "chosen lights")
        ok(c.can.d.selected, "可支援 shows the main role on")
        eq(c.can.d.gfEnabled, false, "and it is not a switch")
    end)

    test("GF-010 sharing: nothing until set; then one L record goes out after the change delay", function()
        local ns = login()
        ok(not ns.Share.get(A_SELF, "J"), "never set: no record (stays 未知 for others)")
        wow.state.sent = {}
        ns.Profile.setMain("h")
        ns.Profile.setCan("d", true)
        eq(#sentWith("~J~"), 0, "not at once (clicks are gathered)")
        wow.advance(35)
        local v = sentWith("S1~V~" .. A_SELF .. "~J~")
        eq(#v, 1, "one value message")
        ok(v[1]:find("~h.hd$"), "value h.hd: " .. v[1])
        eq(ns.Share.get(A_SELF, "J").v, "h.hd", "in our own store (index, relays)")
    end)

    test("GF-010 withdraw: unticking 分享 sends a tombstone at once; others drop it; old copies cannot return", function()
        local ns = login()
        ns.Profile.setMain("t")
        wow.advance(35)
        wow.state.sent = {}
        ns.Profile.setShare(false)
        wow.advance(2)
        eq(#sentWith("S1~X~" .. A_SELF .. "~J~"), 1, "X sent at once")
        ok(not ns.Share.get(A_SELF, "J"), "own record gone")
        eq(ns.Profile.roles(SELF_GUID).main, "t", "the setting itself is kept on this computer")
        wow.advance(40)
        eq(#sentWith("S1~V~" .. A_SELF .. "~J~"), 0, "nothing shared while withdrawn")
        -- Sharing again: a newer value than the tombstone.
        ns.Profile.setShare(true)
        wow.advance(2)
        local rec = ns.Share.get(A_SELF, "J")
        ok(rec and rec.v == "t.t", "shared again")
        ok(rec.t > ns.Share.store().tomb[A_SELF].J, "newer than the withdrawal")
    end)

    test("GF-010 receiving: shared roles show; nothing received = 未知; a relayed withdrawal clears; no revival", function()
        local ns = login()
        local P, S = ns.Profile, ns.Share
        eq(P.roles(THIRD_GUID).state, "unknown", "nothing received: 未知")
        local t = S.serverNow() - 100
        from(ns, PEER, vMsg(ns, A_PEER, t, "h.hd"))
        local p = P.roles(PEER_GUID)
        eq(p.main, "h", "main"); eq(keysOf(p.can), "hd", "can"); eq(p.state, "shared", "state")
        -- Unset shared: 未設定, not 未知.
        from(ns, PEER, vMsg(ns, A_THIRD, t, "0."))
        eq(P.roles(THIRD_GUID).state, "unset", "未設定")
        -- The author withdraws; a third member relays the X.
        eq(from(ns, THIRD, "S1~X~" .. A_PEER .. "~J~" .. S.b36(t + 10)), "tomb", "withdrawal applied")
        eq(P.roles(PEER_GUID).state, "unknown", "gone: 未知")
        -- Someone still holding the old copy sends it: refused.
        from(ns, THIRD, vMsg(ns, A_PEER, t, "h.hd"))
        eq(P.roles(PEER_GUID).state, "unknown", "the old copy does not come back")
        -- A tombstone is only for withdrawable groups: B (level) cannot be withdrawn.
        eq(S.applyTomb(A_PEER, "B", t + 20), false, "B has no withdrawal")
    end)

    test("GF-010 roster: 職責 column icons, 未知 / 未設定, click opens the read-only card (✕, ESC)", function()
        local ns = login()
        local S = ns.Share
        from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 50, "t.td"))
        from(ns, PEER, vMsg(ns, A_THIRD, S.serverNow() - 50, "0."))
        ns.Framework.open("roster")
        local peer = rowFor(ns, PEER)
        ok(peer.roleMain:IsShown(), "main role icon")
        ok(tostring(peer.roleMain._texture):find("LFG"), "the group finder art: " .. tostring(peer.roleMain._texture))
        eq(peer.roleMain._w, 24, "24 px main")
        ok(peer.roleCan[1]:IsShown() and not peer.roleCan[2]:IsShown(), "one more role (輸出) at 16 px")
        eq(peer.roleCan[1]._w, 16, "16 px")
        eq(peer.cell.roles:GetText(), "", "no text next to icons")
        eq(rowFor(ns, THIRD).cell.roles:GetText(), "未設定", "unset")
        eq(rowFor(ns, "測試丁-測試伺服器").cell.roles:GetText(), "未知", "nothing received")
        ok(rowFor(ns, "測試丁-測試伺服器").cell.roles:GetText() ~= "輸出", "never 輸出 by default")
        -- Tooltip line.
        ns.UI.showRowTooltip(peer, nil)
        local tip = {}
        for _, l in ipairs(GameTooltip._lines) do tip[#tip + 1] = l.text end
        ok(table.concat(tip, "\n"):find("主職責 坦克", 1, true), "tooltip: " .. table.concat(tip, " / "))
        -- Click on the 職責 cell: the card; elsewhere: select (unchanged).
        local col = ns.UI.columns[ns.UI.CELL.roles]
        eq(ns.UI.rowClick(peer, "LeftButton", nil, col.x + 5), "profile", "card")
        local card = ns.ProfileUI.card
        ok(card:IsShown(), "card shown")
        eq(card.mainText:GetText(), "坦克", "main role")
        ok(card.mainIcon:IsShown(), "with its icon")
        eq(ns.UI.rowClick(peer, "LeftButton", nil, 10), "select", "the name still selects")
        -- Read-only: no role buttons on the card, only 關閉 (and the window's ✕).
        local buttons = 0
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "Button" and o._parent == card and o ~= card.close and o._shown ~= false then buttons = buttons + 1 end
        end
        ok(buttons <= 1, "only the window's ✕ besides 關閉 (" .. buttons .. ")")
        wow.pressEscape()
        ok(not card:IsShown(), "ESC closes the card")
    end)

    test("GF-010 人力盤點: main, can and online counted apart; each member once; a role click filters", function()
        local ns = login()
        local S, P = ns.Share, ns.Profile
        P.setMain("h"); P.setCan("t", true) -- self: 德魯伊, online
        from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 50, "t.td")) -- online
        from(ns, PEER, vMsg(ns, A_THIRD, S.serverNow() - 50, "0.")) -- offline, unset
        ns.Framework.open("roster")
        local n = ns.UI.censusCounts
        eq(n.total, 4, "four members")
        eq(n.online, 2, "two online")
        eq(n.main.t, 1, "main tank"); eq(n.main.h, 1, "main heal"); eq(n.main.d, 0, "main dps")
        eq(n.can.t, 2, "can tank (self + peer)"); eq(n.can.d, 1, "can dps"); eq(n.can.h, 1, "can heal")
        eq(n.main.unset, 1, "未設定"); eq(n.main.unknown, 1, "未知")
        eq(n.main.t + n.main.h + n.main.d + n.main.unset + n.main.unknown, n.total, "main counts add up to the total")
        local m = ns.Roster.current().members
        eq(P.census({ m[1], m[1], m[2] }).total, 2, "a member listed twice counts once")
        eq(ns.UI.census.roles.t.label:GetText(), "主1 可2", "icon label")
        -- Filter: who can tank.
        wow.click(ns.UI.census.roles.t)
        eq(ns.UI.countText:GetText(), "2/4", "self and peer")
        ok(ns.UI.census.roles.t.selected, "the filter lights")
        wow.click(ns.UI.census.unknown)
        eq(ns.UI.countText:GetText(), "4/4", "+ 未知 / 未設定")
        ns.UI.clearFilters()
        eq(ns.UI.filters.roles, nil, "清除 resets it")
        ok(not ns.UI.census.roles.t.selected, "not lit")
        -- Sort by 職責: 坦克, 治療, then the rest.
        ns.UI.sortKey, ns.UI.sortAscending = "roles", true
        ns.UI.refresh(true)
        eq(ns.UI.rows()[1].memberName, PEER, "坦克 first")
    end)

    test("GF-010 roster with 1000 members: pooled rows only; census over all", function()
        local roster = {}
        for i = 1, 1000 do
            roster[i] = { name = string.format("職工%04d-測試伺服器", i), rank = "會員", level = 30, class = "戰士",
                classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0, guid = string.format("Player-0000-1%07d", i) }
        end
        roster[1] = wow.defaultRoster()[1] -- self
        local ns = login({ roster = roster })
        local S = ns.Share
        local t = S.serverNow() - 10
        for i = 2, 1000 do
            local a = string.format("0000-1%07d", i)
            S.offer(a, "J", t, S.hash(i % 2 == 0 and "t.td" or "d.d"), i % 2 == 0 and "t.td" or "d.d", true, a)
        end
        ns.Framework.open("roster")
        ok(#ns.UI.rows() <= ns.UI.visibleRowCount() + 1, "rows " .. #ns.UI.rows())
        local n = ns.UI.censusCounts
        eq(n.total, 1000, "total")
        eq(n.main.t, 500, "tanks"); eq(n.main.d, 499, "dps"); eq(n.can.d, 999, "can dps")
        ns.UI.toggleRoleFilter("t")
        eq(ns.UI.countText:GetText(), "500/1000", "filtered")
        ok(#ns.UI.rows() <= ns.UI.visibleRowCount() + 1, "still pooled")
    end)

    test("GF-010 personnel file: 我的業務 lists my order and adventure (read-only) and opens their pages", function()
        local ns = login()
        ns.Framework.open("character")
        eq(#ns.Profile.myBusiness(), 0, "nothing yet")
        ok(ns.ProfileUI.controls.bizEmpty:IsShown(), "沒有")
        local orderId = ns.Orders.place({ recipe = 2660, item = 2862, skill = 164, qty = 1 })
        ok(orderId, "an order")
        local advId = ns.Adventure.open({ dungeon = "smg", leaderRole = "d" })
        ok(advId, "a ticket")
        ns.Adventure.refresh()
        local items = ns.Profile.myBusiness()
        local kinds = {}
        for _, it in ipairs(items) do kinds[it.kind] = it end
        ok(kinds.order and kinds.order.id == orderId, "the order")
        eq(kinds.order.role, "下單", "I placed it")
        ok(kinds.adventure and kinds.adventure.id == advId, "the ticket")
        eq(kinds.adventure.role, "開單", "I lead it")
        -- Nothing copied: the profile store has no orders or tickets.
        for k in pairs(GreenFangToolkitDB.profile.chars[SELF_GUID]) do
            ok(k ~= "orders" and k ~= "adventures", "no copy: " .. k)
        end
        ns.Character.refresh()
        local row = ns.ProfileUI.controls.rows[1]
        ok(row:IsShown() and row.item, "a row")
        wow.click(row)
        eq(ns.Framework.current(), row.item.kind == "order" and "orders" or "adventure", "its page opens")
    end)

    test("GF-010 personnel file: 個人需求 hidden until GF-009 registers; 配方 / 我的服務 reuse the editors", function()
        local ns = login()
        ns.Framework.open("character")
        local c = ns.ProfileUI.controls
        ok(not c.needsHead:IsShown() and not c.needsButton:IsShown(), "hidden")
        local opened = false
        ns.Profile.setNeedsProvider({ open = function() opened = true end })
        ns.Character.refresh()
        ok(c.needsHead:IsShown() and c.needsButton:IsShown(), "shown with a provider")
        wow.click(c.needsButton)
        ok(opened, "opens GF-009's page")
        ok(ns.Character.recipesButton:IsShown(), "配方")
        ok(ns.Character.servicesButton:IsShown(), "我的服務")
        wow.click(ns.Character.servicesButton)
        ok(ns.OrdersUI.servicesPopup and ns.OrdersUI.servicesPopup:IsShown(), "the existing 我的服務 window")
    end)

    test("GF-010 privacy: roles never reach the outbox or the website payload; diag has a line", function()
        local ns = login()
        ns.Profile.setMain("t")
        local S = ns.Share
        from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 50, "h.h"))
        wow.advance(35)
        ok(ns.Profile.diagText():find("主職責 坦克", 1, true), "diag: " .. ns.Profile.diagText())
        ok(ns.Profile.diagText():find("收到職責 1 位", 1, true), "diag counts received: " .. ns.Profile.diagText())
        local saved = wow.logout()
        local function walk(t, path)
            for k, v in pairs(t) do
                ok(k ~= "roles" and k ~= "J" and k ~= "main" and k ~= "can", "outbox key " .. path .. "." .. tostring(k))
                if type(v) == "table" then walk(v, path .. "." .. tostring(k)) end
            end
        end
        walk(saved.GreenFangToolkitDB and saved.GreenFangToolkitDB.sync.outbox or GreenFangToolkitDB.sync.outbox, "outbox")
    end)

    test("GF-010 page text is 16 px or more on the personnel file and the card", function()
        local ns = login()
        local function fontSize(fs)
            local f = fs._font
            local obj = type(f) == "string" and rawget(_G, f) or f
            if type(obj) == "table" and obj._fontSize then return obj._fontSize end
            if tostring(f):find("Large") then return 18 end
            if tostring(f):find("Small") then return 10 end
            return 13
        end
        local function visibleUnder(o, root)
            local f, inside = o, false
            while f do
                if f._shown == false then return false end
                if f == root then inside = true end
                f = f._parent
            end
            return inside
        end
        local function small(root)
            local out = {}
            for _, o in ipairs(wow.allObjects()) do
                if o._kind == "FontString" and visibleUnder(o, root) then
                    local text = tostring(o._text or ""):gsub("|T.-|t", "")
                    if text ~= "" and fontSize(o) < 16 then out[#out + 1] = text .. "@" .. fontSize(o) end
                end
            end
            return table.concat(out, ",")
        end
        ns.Profile.setMain("h")
        ns.Framework.open("character")
        eq(small(ns.Framework.panel("character")), "", "page")
        ns.Framework.open("roster")
        eq(small(ns.Framework.panel("roster")), "", "roster with the census")
        ns.ProfileUI.openCard(ns.Roster.current().members[2])
        eq(small(ns.ProfileUI.card), "", "card")
    end)
end
