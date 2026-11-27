-- GF-FIX-B (review GF-REVIEW-01 batch B: high-1 roster part, mid-5 ~ mid-9
-- roster part, low-7 ~ low-11) and three owner decisions after GF-UI-K: the
-- tab row stays for one-page entries, windows fit 4:3 screens, the order
-- states use the spec v2.0 §3 names. Owner rule: what changed shows as fast
-- as before. Made-up names and GUIDs only; offline only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function roster(n)
        local list = wow.defaultRoster()
        for i = #list + 1, n do
            list[i] = { name = string.format("成員%04d-測試伺服器", i), rank = "會員", level = 60,
                class = "戰士", classToken = "WARRIOR", zone = "奧格瑪", online = i % 3 == 0,
                guid = string.format("Player-0000-%08X", 0x100 + i),
                club = { race = 2, profession1ID = 164, profession2ID = 186 } }
        end
        return list
    end

    local function login(n)
        wow.reset({ roster = roster(n or 4) })
        local ns = wow.login(ADDON_DIR)
        wow.advance(130)
        return ns
    end

    local function count(tbl, key)
        local orig = tbl[key]
        local n = { calls = 0 }
        tbl[key] = function(...) n.calls = n.calls + 1; return orig(...) end
        return n, function() tbl[key] = orig end
    end

    -- Roles for every other member: t.td, d.d, h.h, none.
    local function shareRoles(ns, n)
        local S = ns.Share
        local t = S.serverNow() - 10
        local values = { "t.td", "d.d", "h.h" }
        for i, m in ipairs(ns.Roster.current().members) do
            local v = values[i % 4]
            local a = S.authorOf(m.guid)
            if v and a and i <= n then S.offer(a, ns.Profile.GROUP, t, S.hash(v), v, true, a) end
        end
    end

    local function names(list)
        local out = {}
        for _, m in ipairs(list) do out[#out + 1] = m.name end
        return out
    end

    test("GF-FIX-B high-1 sort by 職責: each member's roles once per sort; same order as before", function()
        local ns = login(1000)
        shareRoles(ns, 1000)
        ns.Framework.open("roster")
        local UI, P = ns.UI, ns.Profile
        local members = {}
        for i, m in ipairs(ns.Roster.current().members) do members[i] = m end
        local before = P.rolesComputed
        local calls, restore = count(P, "roles")
        UI.sortMembers(members, "roles", true)
        restore()
        ok(calls.calls <= 1000, "at most one Profile.roles per member (was ~2 per comparison): " .. calls.calls)
        eq(P.rolesComputed - before, 0, "already known: nothing worked out again")
        -- The order: 坦克, 治療, 輸出, then 未設定 / 未知; by name within each.
        local rank = { t = 1, h = 2, d = 3 }
        local last, lastName = 0, ""
        for _, m in ipairs(members) do
            local r = rank[P.roles(m.guid).main or ""] or 4
            ok(r >= last, "role order")
            if r == last then ok(ns.keyName(m.name) >= lastName, "name order within a role") end
            last, lastName = r, ns.keyName(m.name)
        end
        -- A new record shows at once (the cache follows Share.version).
        local m
        for i = #members, 1, -1 do
            if members[i].guid ~= P.selfGuid() then m = members[i]; break end
        end
        local S = ns.Share
        local a = S.authorOf(m.guid)
        local res = S.offer(a, P.GROUP, S.serverNow() - 1, S.hash("t.t"), "t.t", true, a)
        eq(P.roles(m.guid).main, "t", "the new main role, with no wait (" .. tostring(res) .. ")")
        UI.sortMembers(members, "roles", true)
        eq(P.roles(members[1].guid).main, "t", "sorted with it")
    end)

    test("GF-FIX-B high-1 census and roles: kept while nothing changed, new at once on any change", function()
        local ns = login(40)
        shareRoles(ns, 40)
        local P = ns.Profile
        local list = ns.Roster.current().members
        local c1 = P.census(list)
        local before = P.rolesComputed
        ok(P.census(list) == c1, "same list, nothing changed: the same counts, no work")
        eq(P.rolesComputed, before, "no roles worked out")
        -- Own settings: Profile.version.
        local self = P.selfGuid()
        ok(self, "own GUID from ns.selfGUID")
        P.setMain("h")
        eq(P.roles(self).main, "h", "own main role shown at once")
        ok(P.census(list) ~= c1, "counted again after the own change")
        -- Another member's record: Share.version.
        local c2 = P.census(list)
        local m = list[3]
        local S = ns.Share
        S.offer(S.authorOf(m.guid), P.GROUP, S.serverNow() - 1, S.hash("d.d"), "d.d", true, S.authorOf(m.guid))
        local c3 = P.census(list)
        ok(c3 ~= c2, "counted again after a record came in")
        -- Roles go through ns.selfGUID, never Data.player.
        local dp, restore = count(ns.Data, "player")
        S.recount()
        for _, x in ipairs(list) do P.roles(x.guid) end
        P.census(list)
        restore()
        eq(dp.calls, 0, "no Data.player() for roles / census")
    end)

    test("GF-FIX-B mid-6 search box: first key at once, a burst one more redraw at most 0.15 s later", function()
        local ns = login(200)
        ns.Framework.open("roster")
        local UI = ns.UI
        eq(UI.SEARCH_DELAY <= 0.15, true, "delay")
        local box = UI.searchBox
        local refresh, restore = count(UI, "refresh")
        box:SetText("成"); box._scripts.OnTextChanged(box, true)
        eq(refresh.calls, 1, "the first key redraws at once")
        eq(UI.countText:GetText(), "196/200", "and the list follows it (the 196 成員)")
        box:SetText("成員"); box._scripts.OnTextChanged(box, true)
        wow.advance(0.05)
        box:SetText("成員01"); box._scripts.OnTextChanged(box, true)
        eq(refresh.calls, 1, "keys within 0.15 s wait")
        wow.advance(0.11)
        eq(refresh.calls, 2, "one more redraw at 0.15 s")
        eq(UI.countText:GetText(), "100/200", "with the latest text (成員0100 ~ 0199)")
        wow.advance(1)
        eq(refresh.calls, 2, "nothing more without keys")
        -- The level box: the same rule.
        local lv = UI.levelBox
        lv:SetText("6"); lv._scripts.OnTextChanged(lv)
        eq(refresh.calls, 3, "level: first key at once")
        lv:SetText("60"); lv._scripts.OnTextChanged(lv)
        eq(refresh.calls, 3, "level: the next key waits")
        wow.advance(0.16)
        eq(refresh.calls, 4, "level: one more redraw")
        eq(UI.filters.minLevel, 60, "the filter has the latest value")
        restore()
    end)

    test("GF-FIX-B mid-6 search text and sort keys kept per roster version; a changed member at once", function()
        local ns = login(300)
        ns.Framework.open("roster")
        local UI = ns.UI
        UI.refresh(true)
        local box = UI.searchBox
        box:SetText("奧格"); box._scripts.OnTextChanged(box, true)
        wow.advance(1)
        local work = UI.memoWork
        box:SetText("奧格瑪"); box._scripts.OnTextChanged(box, true)
        eq(UI.memoWork, work, "no member's search text or sort key worked out again")
        -- A member changes zone: the next scan shows it, the search finds it.
        local m = wow.state.roster[7]
        m.zone = "測試秘境"
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        box:SetText("秘境"); box._scripts.OnTextChanged(box, true)
        wow.advance(1)
        eq(UI.countText:GetText(), "1/300", "the changed zone is searched at once")
        ok(UI.memoWork > work, "worked out again for the new roster version")
    end)

    test("GF-FIX-B mid-5 automatic scan: the list keeps its place; the change shows at once", function()
        local ns = login(300)
        ns.Framework.open("roster")
        local UI = ns.UI
        local sf = UI.scrollFrame()
        sf:SetVerticalScroll(36 * 20)
        UI.layoutRows()
        local m = wow.state.roster[26] -- 成員0026: row 22 by name, in view (rows 21 ~ 25)
        m.online = not m.online
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(0.8)
        eq(sf:GetVerticalScroll(), 36 * 20, "scroll place kept")
        local shown
        for _, r in ipairs(UI.rows()) do if r:IsShown() and r.memberName == m.name then shown = r end end
        ok(shown, "the member's row is still in view")
        eq(shown.cell.online:GetText(), m.online and "在線" or "離線", "its new state is on the row at once")
        -- A scan that changed nothing redraws nothing.
        local refresh, restore = count(UI, "refresh")
        wow.fire("GUILD_ROSTER_UPDATE"); wow.advance(1)
        restore()
        eq(refresh.calls, 0, "no redraw for an unchanged roster")
        -- 更新 (by hand) still goes to the top, as before.
    end)

    test("GF-FIX-B mid-7 own professions read once per pass, not per row or per member", function()
        local ns = login(300)
        ns.Framework.open("roster")
        local UI = ns.UI
        local reads = UI.ownReads
        local opts = UI.professionOptions()
        ok(#opts > 0, "options")
        ok(UI.ownReads - reads <= 1, "professionOptions: at most one own read")
        reads = UI.ownReads
        UI.skillChoice.setOnly(164)
        -- Passes: the button text, the 全選 check, the filter, the rows (was one read per member).
        ok(UI.ownReads - reads <= 4, "one own read per pass: " .. (UI.ownReads - reads))
        local dp, restore = count(ns.Sync, "player")
        UI.refresh(true)
        restore()
        eq(dp.calls, 0, "no Sync.player() per member any more")
    end)

    test("GF-FIX-B mid-8 multi-select: one options() read while the list is open", function()
        local ns = login(300)
        ns.Framework.open("roster")
        local b = ns.UI.skillChoice
        local reads = b.optionReads
        wow.click(b)
        ok(b.menu:IsShown(), "open")
        eq(b.optionReads - reads, 1, "one read to open")
        local items = {}
        for _, it in ipairs(b.menu.items) do if it:IsShown() and it.isOption then items[#items + 1] = it end end
        ok(#items >= 2, "options listed")
        wow.click(items[1]); wow.click(items[2]); wow.click(items[1])
        eq(b.optionReads - reads, 1, "three ticks: no more reads")
        ok(b.selected ~= nil, "ticks still work")
        b.menu:Hide()
        b.count()
        eq(b.optionReads - reads, 2, "closed: read live again")
    end)

    test("GF-FIX-B mid-9 scroll: the same first row refills nothing; a new first row refills at once", function()
        local ns = login(300)
        ns.Framework.open("roster")
        local UI = ns.UI
        local sf = UI.scrollFrame()
        local fills = UI.rowFills
        sf:SetVerticalScroll(10)
        sf._scripts.OnVerticalScroll(sf, 10)
        eq(UI.rowFills, fills, "within the first row: nothing refilled")
        sf:SetVerticalScroll(36 * 3)
        sf._scripts.OnVerticalScroll(sf, 36 * 3)
        eq(UI.rowFills, fills + 1, "a new first row: refilled")
        local first
        for _, r in ipairs(UI.rows()) do if r:IsShown() and (not first or r.index < first.index) then first = r end end
        eq(first.index, 4, "row 4 is the first in view")
        -- Rows keep the scripts made in newRow.
        local fn = UI.rows()[1]._scripts.OnEnter
        sf:SetVerticalScroll(36 * 9); sf._scripts.OnVerticalScroll(sf, 36 * 9)
        ok(UI.rows()[1]._scripts.OnEnter == fn, "no new closure when scrolling")
    end)

    test("GF-FIX-B low-8 清除: one redraw", function()
        local ns = login(40)
        ns.Framework.open("roster")
        local UI = ns.UI
        UI.levelBox:SetText("50")
        UI.searchBox:SetText("成")
        wow.advance(1)
        -- The client runs OnTextChanged on SetText: do it here too.
        local setText = UI.searchBox.SetText
        local function firing(box)
            box.SetText = function(self, t) setText(self, t); if self._scripts.OnTextChanged then self._scripts.OnTextChanged(self) end end
        end
        firing(UI.searchBox); firing(UI.levelBox)
        local refresh, restore = count(UI, "refresh")
        wow.click(UI.clearButton)
        restore()
        eq(refresh.calls, 1, "one redraw for 清除")
        eq(UI.countText:GetText(), "40/40", "everything shown")
        eq(UI.filters.minLevel, nil, "level cleared")
    end)

    test("GF-FIX-B low-7 an art file the client lacks is not tried again on every row", function()
        local ns = login(4)
        local G = ns.GameIcons
        G.ART.gffixb_test = { { "Interface\\Missing\\Nope" }, { "Interface\\Icons\\INV_Misc_QuestionMark" } }
        local tex = UIParent:CreateTexture()
        local tried = {}
        local orig = ns.Icons.set
        ns.Icons.set = function(t, file)
            tried[#tried + 1] = file
            if file == "Interface\\Missing\\Nope" then return false end
            return orig(t, file)
        end
        G.set(tex, "gffixb_test"); G.set(tex, "gffixb_test"); G.set(tex, "gffixb_test")
        ns.Icons.set = orig
        local missing = 0
        for _, f in ipairs(tried) do if f == "Interface\\Missing\\Nope" then missing = missing + 1 end end
        eq(missing, 1, "the missing file tried once")
        ok(tex:IsShown(), "the next candidate is shown")
        G.ART.gffixb_test = nil
    end)

    test("GF-FIX-B low-9 notices dropped in combat free their queue places", function()
        local ns = login(4)
        local N = ns.Notify
        N.register("gffixb", {})
        wow.setCombat(true)
        for i = 1, N.QUEUE_MAX do N.push({ module = "gffixb", key = "k" .. i, text = "x" }) end
        eq(N.queued(), N.QUEUE_MAX, "queue full")
        N.clear("gffixb")
        eq(N.queued(), 0, "cleared: no place taken")
        eq(N.push({ module = "gffixb", key = "new", text = "y" }), "queued", "a new notice is not refused as a burst")
        N.setEnabled("gffixb", false)
        eq(N.queued(), 0, "switched off: no place taken")
        wow.setCombat(false)
    end)

    test("GF-FIX-B low-10 after combat on another page, back on the roster: own buttons placed", function()
        local ns = login(4)
        ns.Framework.open("orders")
        wow.enterCombat(); wow.leaveCombat()
        local placed, restore = count(ns.UI, "placeOwnButtons")
        ns.Framework.select("roster")
        restore()
        ok(placed.calls >= 1, "placeOwnButtons when the roster page is shown again")
    end)

    test("GF-FIX-B low-11 charKey: the GUID, never a name", function()
        local ns = login(4)
        local F = ns.Framework
        ok(tostring(F.charKey()):find("^Player%-"), "GUID")
        local orig = _G.UnitGUID
        _G.UnitGUID = function() return nil end
        eq(F.charKey(), nil, "no GUID: no key (nothing stored by name)")
        eq(next(F.charState("roster")), nil, "charState: an empty, unsaved table")
        _G.UnitGUID = orig
    end)

    test("GF-FIX-B tab row stays for one-page entries, styled like the others", function()
        local ns = login(4)
        local F = ns.Framework
        local function tabs()
            local out = {}
            for _, b in ipairs(F.subTabButtons()) do if b:IsShown() then out[#out + 1] = b end end
            return out
        end
        local expect = { character = "角色資料", roster = "在籍職工", adventure = "業務大廳", sleepingbag = "睡袋指南" }
        local multi
        F.open("recipes")
        multi = tabs()
        ok(#multi >= 2, "委託業務: several tabs")
        local style = { h = multi[1]._h, x = multi[1]._points[1][4] }
        for id, name in pairs(expect) do
            if F.get(id) then
                F.open(id)
                local t = tabs()
                eq(#t, 1, id .. ": one tab")
                eq(t[1]:GetText(), name, id .. ": the page's name")
                ok(t[1].gfSelected, id .. ": chosen (gold)")
                eq(t[1]._h, style.h, id .. ": same height as on a multi-page entry")
                eq(t[1]._points[1][4], style.x, id .. ": same left x")
            end
        end
    end)

    test("GF-FIX-B 4:3: the main window scales down to fit, 1 with room; events refit", function()
        local ns = login(4)
        local F, Th = ns.Framework, ns.Theme
        local W, H = 1024, 768
        UIParent.GetWidth = function() return W end
        UIParent.GetHeight = function() return H end
        F.open("roster")
        local win = _G[F.WINDOW_NAME]
        local scales = {}
        win.SetScale = function(self, s) scales[#scales + 1] = s; self._scale = s end
        win.gfFitScale = nil
        Th.fit(win)
        local want = (1024 - 2 * Th.FIT_MARGIN) / (F.NAV_WIDTH + F.PANEL_WIDTH + 10)
        ok(math.abs(win._scale - want) < 1e-6, string.format("1024x768: %.4f (want %.4f)", win._scale, want))
        ok(1270 * win._scale <= 1024 - 2 * Th.FIT_MARGIN + 1e-6, "fits the width with the margin")
        ok(720 * win._scale <= 768, "and the height")
        -- 1920x1080: full size.
        W, H = 1920, 1080
        wow.fire("DISPLAY_SIZE_CHANGED")
        eq(win._scale, 1, "room enough: 1")
        -- A big UI scale (UIParent 1280x720): the height decides.
        W, H = 1280, 720
        wow.fire("UI_SCALE_CHANGED")
        local hWant = (720 - 2 * Th.FIT_MARGIN) / (F.PANEL_HEIGHT + F.SUBTAB_H)
        ok(math.abs(win._scale - math.min(hWant, (1280 - 40) / 1270)) < 1e-6, "the tighter side decides: " .. win._scale)
        -- Nothing changed: SetScale is not called again.
        local n = #scales
        wow.fire("UI_SCALE_CHANGED")
        eq(#scales, n, "same screen: no SetScale")
        -- Opening the window fits it too.
        W, H = 1024, 768
        win:Hide(); F.open("roster")
        ok(math.abs(win._scale - want) < 1e-6, "fitted when it opens")
        -- In combat a protected window is left alone, and fitted after.
        win.IsProtected = function() return true end
        W, H = 1920, 1080
        wow.enterCombat()
        wow.fire("DISPLAY_SIZE_CHANGED")
        ok(math.abs(win._scale - want) < 1e-6, "combat: unchanged")
        wow.leaveCombat()
        eq(win._scale, 1, "after combat: fitted")
        win.IsProtected = nil
    end)

    test("GF-FIX-B 4:3: separate windows: fit at 1 when they can, else the main window's ratio", function()
        local ns = login(4)
        local F, Th = ns.Framework, ns.Theme
        local W, H = 1024, 768
        UIParent.GetWidth = function() return W end
        UIParent.GetHeight = function() return H end
        F.open("roster")
        local win = _G[F.WINDOW_NAME]
        win.gfFitScale = nil
        local mainScale = Th.fit(win)
        local function popup(name, w, h)
            local f = ns.popupWindow(name, w, h)
            f.SetScale = function(self, s) self._scale = s end
            f:Hide(); f:Show()
            return f
        end
        -- The sizes there are (export 920x560, ticket 820x470, calendar ~640 high, form ...).
        local export = popup("GFFIXB_Export", 920, 560)
        eq(export._scale, 1, "920x560 fits 1024x768 at 1")
        local cal = popup("GFFIXB_Cal", 40 + 7 * 104, 640)
        eq(cal._scale, 1, "the time picker fits at 1")
        -- A smaller screen (UIParent 800x600): those that do not fit take the ratio.
        W, H = 800, 600
        wow.fire("DISPLAY_SIZE_CHANGED")
        mainScale = Th.mainScale
        ok(mainScale < 1, "main scaled")
        ok(export._scale <= mainScale + 1e-6, "an open window that no longer fits: the same ratio (or less)")
        ok(920 * export._scale <= 800 - 2 * Th.FIT_MARGIN + 1e-6, "and it fits")
        local small = popup("GFFIXB_Small", 480, 200)
        eq(small._scale, 1, "a small window stays at 1")
        -- Every separate window is made by Theme.window, so each is in the list.
        local inList = false
        for _, f in ipairs(Th.fitFrames) do if f == export then inList = true end end
        ok(inList, "registered")
    end)

    test("GF-FIX-B order states: 待受理／已接單／待交付／已成交, 已取消 apart; keys unchanged", function()
        local ns = login(4)
        local S, P = ns.OrdersUI.STATE_NAME, ns.Profile.ORDER_STATE
        local want = { waiting = "待受理", making = "已接單", checking = "待交付", deal = "已成交", cancel = "已取消" }
        for k, v in pairs(want) do
            eq(S[k], v, "OrdersUI " .. k)
            eq(P[k], v, "Profile " .. k)
        end
        local n = 0
        for _ in pairs(S) do n = n + 1 end
        eq(n, 5, "the same five state keys")
        ok(S.cancel ~= S.deal, "cancel and success differ")
    end)
end
