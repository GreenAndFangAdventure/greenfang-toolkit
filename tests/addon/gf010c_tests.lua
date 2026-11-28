-- GF-010-C: 職工檔案 「清除定位」 (main role and 可支援 cleared together, after a
-- confirm box) and the roster's wrench for members whose toolkit data this
-- computer holds, with its filter. Made-up names and GUIDs only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A_PEER, A_THIRD = "0000-0000000B", "0000-0000000C"
    local PEER_GUID = "Player-" .. A_PEER
    local PEER, THIRD, FOURTH = "測試乙-測試伺服器", "測試丙-測試伺服器", "測試丁-測試伺服器"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function vMsg(ns, a, t, v)
        return "S1~V~" .. a .. "~J~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function rowFor(ns, name)
        for _, r in ipairs(ns.UI.rows()) do if r:IsShown() and r.memberName == name then return r end end
    end
    local function selfName(ns)
        local own = ns.selfGUID()
        for _, m in ipairs(ns.Roster.current().members) do if m.guid == own then return m.name end end
    end

    test("GF-010-C 清除定位: the button is an action (never gold), asks first, then clears both rows", function()
        local ns = login()
        local P, UI = ns.Profile, ns.ProfileUI
        SlashCmdList.GREENFANGTOOLKIT("character")
        local c = UI.controls
        local label = c.unset.label or c.unset.text or c.unset
        local text = label.GetText and label:GetText() or c.unset:GetText()
        eq(text, "清除定位", "renamed")
        -- Nothing set: greyed, not the chosen look.
        P.setMain(nil); UI.refresh()
        ok(not c.unset.gfSelected, "never drawn as chosen")
        eq(c.unset.gfEnabled, false, "nothing to clear: greyed")
        P.setMain("t"); P.setCan("d", true); UI.refresh()
        ok(not c.unset.gfSelected, "not chosen with roles set either")
        eq(c.unset.gfEnabled, true, "something to clear: usable")
        -- A click only asks.
        wow.click(c.unset)
        local box = ns.Widgets.confirmFrame()
        ok(box and box:IsShown(), "the confirm box")
        eq(P.own().main, "t", "nothing cleared before 確定")
        -- 取消 keeps everything.
        wow.click(box.no)
        eq(P.own().main, "t", "取消 keeps the main role"); ok(P.own().can.d, "and 可支援")
        -- 確定 clears both.
        wow.click(c.unset)
        wow.click(ns.Widgets.confirmFrame().yes)
        local own = P.own()
        eq(own.main, nil, "main role cleared")
        eq(next(own.can), nil, "可支援 cleared")
        for _, r in ipairs(P.ROLES) do
            ok(not c.main[r].gfSelected, "main " .. r .. " off")
            ok(not c.can[r].gfSelected, "can " .. r .. " off")
        end
        eq(c.unset.gfEnabled, false, "greyed again")
        -- What the guild gets: no main role, nothing to support.
        eq(P.ownValue(), "0.", "shared as 未設定")
        local mainName, canName = UI.rolesText(P.roles(ns.selfGUID()))
        eq(mainName, "未設定", "shown as not set"); eq(canName, "無", "nothing to support")
    end)

    test("GF-010-C clearRoles: nothing to clear sends nothing; a cleared character publishes 0.", function()
        local ns = login()
        local P = ns.Profile
        local v0 = P.version
        local okC, why = P.clearRoles()
        ok(okC, "fine"); eq(why, "same", "nothing to clear")
        eq(P.version, v0, "no change")
        eq(P.ownValue(), nil, "a character that never set anything stays unshared")
        P.setMain("h")
        wow.advance(5)
        ok(P.clearRoles(), "cleared")
        wow.advance(ns.Share.CHANGE_DELAY + 5)
        local rec = ns.Share.get(ns.Share.selfAuthor(), "J")
        ok(rec and rec.v == "0.", "the share record follows: " .. tostring(rec and rec.v))
    end)

    test("GF-010-C roster wrench: own row and members with received data; nobody else; tooltip says when", function()
        local ns = login()
        local S = ns.Share
        local t = S.serverNow() - 3600
        from(ns, PEER, vMsg(ns, A_PEER, t, "t.td"))
        -- A relayed record still comes from the member's own toolkit.
        from(ns, PEER, vMsg(ns, A_THIRD, S.serverNow() - 40 * 86400, "0."))
        ns.Framework.open("roster")
        local me = rowFor(ns, selfName(ns))
        ok(me.tkIcon:IsShown(), "own row")
        eq(me.tkIcon._w, 16, "16 px")
        ok(tostring(me.tkIcon._texture):find("Wrench"), "the toolkit's wrench: " .. tostring(me.tkIcon._texture))
        local peer = rowFor(ns, PEER)
        ok(peer.tkIcon:IsShown(), "a member we received from")
        local third = rowFor(ns, THIRD)
        ok(third.tkIcon:IsShown(), "relayed data counts")
        eq(third.tkIcon._alpha, ns.UI.TOOLKIT_OLD_ALPHA, "older than 30 days: dimmer")
        ok(not rowFor(ns, FOURTH).tkIcon:IsShown(), "nothing received: no mark (not 'no toolkit')")
        -- Tooltips.
        local mine = table.concat(ns.UI.toolkitLines(ns.Roster.toolkit(ns.selfGUID())), "|")
        ok(mine:find("有裝綠皮冒險工具箱", 1, true), mine)
        ok(mine:find("版本 " .. ns.VERSION, 1, true), "own version: " .. mine)
        local theirs = table.concat(ns.UI.toolkitLines(ns.Roster.toolkit(PEER_GUID)), "|")
        ok(theirs:find("有裝綠皮冒險工具箱", 1, true), theirs)
        ok(theirs:find("最後一次收到對方資料", 1, true) and theirs:find("近期", 1, true), theirs)
        ok(not theirs:find("版本", 1, true), "no version is known for others")
        ok(not theirs:find("沒裝", 1, true), "never 沒裝")
        eq(#ns.UI.toolkitLines(nil), 0, "nothing for no data")
        -- Hover over the wrench: that tooltip, not the member card.
        local slot = ns.UI.toolkitAt(peer, peer.tkSlot.x0 + 2)
        ok(slot and slot.toolkit, "the wrench is found under the cursor")
        eq(ns.UI.toolkitAt(peer, 10), nil, "not elsewhere on the name")
        local tip = ns.UI.showRowTooltip(peer, slot)
        eq(tip, GameTooltip, "a GameTooltip")
    end)

    test("GF-010-C filter 工具箱: only members with the mark; 清除 resets; cached until data changes", function()
        local ns = login()
        local S, R = ns.Share, ns.Roster
        ns.Framework.open("roster")
        local total = #R.current().members
        wow.click(ns.UI.moreFilterButton) -- GF-UI-S: 工具箱 is in 更多篩選
        wow.click(ns.UI.toolkitCheck)
        ok(ns.UI.filters.toolkit, "on")
        eq(ns.UI.countText:GetText(), "1/" .. total, "only the own character so far")
        -- New data shows at once (Share.version changes the cache key).
        from(ns, PEER, vMsg(ns, A_PEER, S.serverNow() - 60, "h.h"))
        ns.UI.refresh(false)
        eq(ns.UI.countText:GetText(), "2/" .. total, "the member we just heard from")
        -- Cached: a redraw with no new data works nothing out again.
        local n0 = R.toolkitComputed
        ns.UI.refresh(false); ns.UI.refresh(false)
        eq(R.toolkitComputed, n0, "no recompute without a change")
        ns.UI.clearFilters()
        eq(ns.UI.filters.toolkit, false, "清除 resets it")
        ok(not ns.UI.toolkitCheck.checked, "box unticked")
        eq(ns.UI.countText:GetText(), total .. "/" .. total, "everyone again")
    end)

    test("GF-010-C the filter box fits on the tool bar before the member count", function()
        local ns = login()
        ns.Framework.open("roster")
        local right = ns.UI.ROW_WIDTH + 20 - ns.measure(ns.UI.countText) - 24
        ok(ns.UI.toolbarRight <= right, string.format("tool bar ends at %d, count starts at %d", ns.UI.toolbarRight, right))
    end)
end
