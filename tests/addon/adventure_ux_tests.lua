-- GF-002-G (0.12.6): the owner's 0.12.4 notes on the adventure page and the
-- worker ticket: two lines a row, social heads, editing a ticket, a glow for
-- what is chosen, one 開始 control, no full-width buttons, and the game's
-- group finder (尋求組隊) where the client allows it. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B, C, D = "0000-0000000B", "0000-0000000C", "0000-0000000D"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

    -- Someone applies to ticket id at time t as role.
    local function apply(ns, author, id, t, role)
        local v = ns.Adventure.encodeList({ { id = id, ac = "ap", at = t, ap = t, ak = "ap", ro = role, rb = "" } })
        ns.Adventure.ledger:offer(author, "A", t, ns.Share.hash(v), v)
        ns.Adventure.refresh()
    end
    local function names(list)
        local out = {}
        for _, x in ipairs(list) do out[#out + 1] = x.a end
        return table.concat(out, ",")
    end

    test("GF-002-G rows: two lines; the full name, the leader in full, tags with names and the note on line 2", function()
        local ns = login()
        local A = ns.AdventureUI
        local d = A.openTicket()
        d.dungeon = "smc"; d.tags = 1 + 4; d.note = "需要坦，慢慢打"
        A.submitTicket()
        ns.Framework.open("adventure")
        local row
        for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.view then row = r end end
        ok(row, "row")
        eq(row._h, A.ROW_HEIGHT, "row height")
        ok(A.ROW_HEIGHT >= 60, "two lines")
        eq(row.name:GetText(), "血色修道院：大教堂", "the full dungeon name")
        ok(not row.name:IsTruncated(), "not cut")
        ok(row.dest._w >= 40, "40 px+ destination art")
        local detail = plain(row.detail:GetText())
        ok(detail:find("解任務", 1, true) and detail:find("慢慢打", 1, true), "tags with their names: " .. detail)
        ok(detail:find("需要坦，慢慢打", 1, true), "the note")
        eq(row.detail._points[1][5], A.LINE2, "details on line 2")
        eq(row.name._points[1][5], A.LINE1, "name on line 1")
        for _, b in ipairs(row.buttons) do if b:IsShown() then eq(b._points[1][5], A.LINE2, "buttons on line 2") end end
        ok(row.who._fixedWidth >= 150, "room for the leader's name")
        ok(not row.who:IsTruncated(), "leader not cut")
        -- My worker ticket uses the same two lines.
        A.openWorker()
        for _, id in ipairs({ "dm", "sfk", "bfd", "gnr", "rfk" }) do A.toggleWorkerDungeon(id) end
        A.saveWorker()
        local mine
        for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.mine then mine = r end end
        ok(mine, "my worker row")
        ok(plain(mine.name:GetText()):find("+2", 1, true), "three names and +2 on line 1")
        ok(plain(mine.detail:GetText()):find("諾姆", 1, true), "the rest on line 2")
    end)

    test("GF-002-G social heads for people and forming a group", function()
        local ns = login()
        local G = ns.GameIcons
        eq(G.ART.person[1][1], "Interface\\FriendsFrame\\UI-Toast-FriendOnlineIcon", "a person: the friends list head")
        eq(G.ART.group[1][1], "Interface\\Icons\\INV_Misc_GroupNeedMore", "a group: several heads")
        ok(#G.ART.person >= 2 and #G.ART.group >= 2, "fallbacks")
        eq(ns.AdventureUI.BUTTON.form.icon, "group", "組隊 uses the group heads")
        eq(ns.AdventureUI.GAME.any, "person", "人數 uses the person head")
    end)

    test("GF-002-G my ticket can be edited; fewer seats make the latest ones wait, and they are told", function()
        local ns = login()
        local A, Adv = ns.AdventureUI, ns.Adventure
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "h", note = "舊備註" })
        local t = ns.Share.serverNow()
        apply(ns, B, id, t - 300, "d")
        apply(ns, C, id, t - 200, "d")
        apply(ns, D, id, t - 100, "d")
        local v = Adv.get(id)
        eq(#v.members, 3, "three dps admitted")
        ns.Framework.open("adventure")
        local row
        for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then row = r end end
        local edit
        for _, b in ipairs(row.buttons) do if b:IsShown() and b.action == "edit" then edit = b end end
        ok(edit, "編輯 on my own ticket")
        wow.advance(60)
        wow.click(edit)
        local f = _G[A.TICKET_NAME]
        ok(f:IsShown(), "the same window")
        eq(plain(f.TitleText._text), "編輯冒險單", "titled for editing")
        ok(plain(f.go:GetText()):find("儲存", 1, true), "儲存")
        local d = A.draft()
        eq(d.editId, id, "editing that ticket")
        eq(d.dungeon .. "," .. d.roles.d .. "," .. d.note, "smg,3,舊備註", "starts from what it was")
        wow.click(f.roleGroups.d.minus); wow.click(f.roleGroups.d.minus) -- 3 → 1 dps seat
        d.note = "新備註"
        wow.click(f.go)
        v = Adv.get(id)
        eq(names(v.members), B, "the first applicant stays")
        eq(names(v.waitlist), C .. "," .. D, "the later ones wait, in application order")
        eq(v.note, "新備註", "the note changed")
        ok(v.edited, "edit time kept")
        local att = Adv.attention(v, C, ns.Share.serverNow())
        eq(att and att.code, "edited", "a waiting worker gets ❗")
        att = Adv.attention(v, B, ns.Share.serverNow())
        eq(att and att.code, "edited", "an admitted worker too")
        eq(Adv.editTicket("nope", { dungeon = "smg" }), false, "only my own tickets")
    end)

    test("GF-002-G time: one 開始 control (現在 / today / tomorrow / 其他日期) and a length for 現在 too", function()
        local ns = login()
        local A = ns.AdventureUI
        local d = A.openTicket()
        local f = _G[A.TICKET_NAME]
        d.dungeon = "smg"
        A.drawTicket()
        eq(f.timeButtons, nil, "no 現在 / 今天 / 之後 buttons")
        ok(plain(f.startButton:GetText()):find("現在", 1, true), "the slot: 現在 first")
        local pk = A.pickStart(f.startButton)
        ok(pk.now:IsShown() and pk.other:IsShown(), "現在 and 其他日期 in the picker")
        ok(pk.lenLabel:IsShown(), "長度 with 現在 (GF-002-H)")
        eq(pk.remove:IsShown(), false, "one slot: no 移除")
        eq(pk.dayLabels[1]:GetText() .. pk.dayLabels[2]:GetText(), "今天明天", "today and tomorrow")
        eq(#pk.minutes, 4, "quarters")
        wow.click(pk.other)
        local menu = _G[ns.Framework.MENU_NAME]
        ok(menu:IsShown(), "the date list")
        wow.click(menu.items[2]) -- the day after tomorrow
        ok(plain(f.startButton:GetText()):match("%d%d%d%d/%d%d/%d%d"), "the date with the year")
        local id = A.submitTicket()
        eq(ns.Adventure.get(id).timeMode, "f", "a later day")
        -- 現在 with 3 hours keeps an end.
        d = A.openTicket()
        d.dungeon = "sfk"
        pk = A.pickStart(f.startButton)
        wow.click(pk.lens[4])
        ok(pk:IsShown(), "the picker stays open to choose both")
        pk:Hide()
        local id2 = A.submitTicket()
        local v = ns.Adventure.get(id2)
        eq(v.timeMode, "n", "現在")
        ok(v.finish and math.abs(v.finish - ns.Share.serverNow() - 3 * 3600) < 120, "ends in about 3 hours")
        ok(plain(A.timeText(v)):find("現在～", 1, true), "shown as 現在～HH:MM")
    end)

    test("GF-002-G no full-width buttons: every button sized to its content", function()
        local ns = login()
        local A = ns.AdventureUI
        A.openTicket()
        local function widest(win)
            local w, name = 0, ""
            for _, o in ipairs(wow.allObjects()) do
                if o._kind == "Button" and o._parent == win and o._shown and (o.gfWidth or 0) > w then w, name = o.gfWidth, plain(o._text) end
            end
            return w, name
        end
        local tf = _G[A.TICKET_NAME]
        local w, name = widest(tf)
        ok(w <= 200, "ticket window: widest button " .. w .. " (" .. name .. ")")
        ok(tf.pickDungeon:IsShown() and tf.pickQuest:IsShown(), "GF-002-H: 地城 / 任務 first (icon buttons, not long ones)")
        A.draft().dungeon = "smg"; A.drawTicket()
        eq(plain(tf.dest:GetText()), " 地城", "then the art + name + a small 地城 (change)")
        ok(not tf.pickDungeon:IsShown(), "the big buttons step aside")
        ok(tf.destIcon:IsShown() and plain(tf.destName:GetText()):find("血色修道院：墓地", 1, true), "the chosen dungeon")
        A.openWorker()
        local wf = _G[A.WORKER_NAME]
        w, name = widest(wf)
        ok(w <= 200, "worker window: widest button " .. w .. " (" .. name .. ")")
    end)

    test("GF-002-G chosen icons glow (the action bar ring, ADD); others only a little darker", function()
        local ns = login()
        local A, O = ns.AdventureUI, ns.OrdersUI
        A.openWorker()
        local wf = _G[A.WORKER_NAME]
        local main = A.workerDraft().main
        for _, r in ipairs(ns.Adventure.ROLES) do
            local b = wf.mainRoles[r]
            if r == main then
                ok(b.sel._shown and b.shine._shown, "glow on the chosen one")
                eq(b.sel._texture, O.GLOW, "the action button border")
                eq(b.sel._blend, "ADD", "additive")
                eq(b.sel._color, nil, "not a flat yellow block")
                ok(b.sel._w > b._w, "a ring around the icon")
            else
                ok(not b.sel._shown, "no glow")
                eq(b.tex._vertex[1], O.DIM, "a little darker")
                ok(O.DIM >= 0.55, "still clear")
                ok(not b.tex._desaturated, "never grey")
            end
        end
    end)

    test("GF-002-G the game's group finder: hidden without C_LFGList; with it, results, suggestions and listing", function()
        local ns = login()
        local A, L = ns.AdventureUI, ns.NativeLFG
        ns.Framework.open("adventure")
        eq(L.available(), false, "no C_LFGList in this client")
        eq(A.lfgButton._shown, false, "no 搜尋尋求組隊")
        local d = A.openTicket()
        d.dungeon = "smg"; A.drawTicket()
        eq(_G[A.TICKET_NAME].lfgCheck._shown, false, "no 尋求組隊 check box")
        -- A client with the group finder (made-up results).
        local calls = {}
        local results = {
            [11] = { activityIDs = { 501 }, leaderName = "測試戊-測試伺服器", numMembers = 3, comment = "缺坦", name = "" },
            [12] = { activityIDs = { 502 }, leaderName = "測試己-測試伺服器", numMembers = 2, comment = "", name = "影牙速刷" },
            [13] = { activityIDs = { 999 }, leaderName = "測試庚-測試伺服器", numMembers = 4, comment = "", name = "" },
        }
        C_LFGList = {
            GetAvailableActivities = function() return { 501, 502, 999 } end,
            GetActivityInfoTable = function(id)
                if id == 501 then return { mapID = 189, fullName = "x" } end -- 血色修道院
                if id == 502 then return { mapID = 33, fullName = "y" } end  -- 影牙城堡
                return { mapID = 1, fullName = "其他" }
            end,
            Search = function(cat) calls[#calls + 1] = "search:" .. tostring(cat) end,
            GetSearchResults = function() return 3, { 11, 12, 13 } end,
            GetSearchResultInfo = function(id) return results[id] end,
            GetSearchResultMemberCounts = function(id) return { TANK_REMAINING = id == 11 and 1 or 0, HEALER_REMAINING = 0, DAMAGER_REMAINING = 1 } end,
            CreateListing = function(data) calls[#calls + 1] = "list:" .. tostring(data.activityIDs[1]) .. ":" .. tostring(data.comment); return true end,
            ApplyToGroup = function(id, t, h, dd) calls[#calls + 1] = "apply:" .. id .. ":" .. tostring(t) .. tostring(h) .. tostring(dd) end,
        }
        L.reset()
        ok(L.available() and L.canSearch() and L.canList(), "available")
        A.refresh()
        ok(A.lfgButton._shown, "搜尋尋求組隊 shown")
        wow.click(A.lfgButton)
        eq(calls[1], "search:2", "a click searches the dungeon category")
        wow.fire("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        wow.advance(2)
        eq(#L.results, 2, "two results for our dungeons (the third is not ours)")
        local counts = L.counts()
        eq(counts.smg, 1, "墓地: 1 group"); eq(counts.sfk, 1, "影牙: 1 group")
        -- Suggestions in the destination picker for 現在.
        local grid = A.pickDestination(_G[A.TICKET_NAME].dest)
        local smg
        for _, b in ipairs(grid.buttons) do if b.dungeon == "smg" then smg = b end end
        eq(smg.lfgCount:GetText(), "現在 1 隊", "people are looking for it now")
        grid:Hide()
        -- The page lists the groups for my dungeons (my worker ticket: 墓地).
        A.openWorker(); A.toggleWorkerDungeon("smg"); A.saveWorker()
        ns.Framework.open("adventure")
        local row
        for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.lfg then row = r end end
        ok(row, "a 尋求組隊 row")
        eq(row.lfg.dungeon, "smg", "only my dungeon")
        ok(plain(row.roles:GetText()):find("坦", 1, true), "what they need")
        ok(plain(row.who:GetText()):find("測試戊", 1, true), "the leader")
        local apply
        for _, b in ipairs(row.buttons) do if b:IsShown() and b.action == "lfgApply" then apply = b end end
        wow.click(apply)
        ok(calls[#calls]:find("^apply:11:"), "申請 applies to that group")
        -- Listing a 現在 ticket, from the 開單 click.
        d = A.openTicket()
        d.dungeon = "smg"; d.note = "一起去"
        A.drawTicket()
        local f = _G[A.TICKET_NAME]
        ok(f.lfgCheck._shown, "the check box for 現在 + a dungeon")
        wow.click(f.lfgCheck)
        local _, _, lfgNote = A.submitTicket()
        eq(lfgNote, "lfg-ok", "listed")
        eq(calls[#calls], "list:501:一起去", "CreateListing with the dungeon's activity and the note")
        ok(ns.NativeLFG.diagText():find("C_LFGList", 1, true), "同步與診斷 line")
        C_LFGList = nil
        L.reset()
    end)
end
