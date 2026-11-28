-- GF-UI-P: the owner's 0.16.18 screenshots (2026-11-28): the toolkit's own icon,
-- text buttons only on the adventure rows (and one set of icon sizes), the
-- member's own status in plain words (not 已定案), list-row tooltips next to the
-- mouse (one helper), the adventure filter row, the guild bank page under its
-- buttons, 「＋」 on the add buttons, and one scroll bar for every list that
-- refills its rows. Offline only; not checked in the Forever client. Made-up data.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C = "0000-0000000A", "0000-0000000B", "0000-0000000C"
    local H = 3600

    local function readAll(path) local h = io.open(path, "rb"); if not h then return "" end local s = h:read("*a"); h:close(); return s end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    local function login()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function offer(ns, a, g, list, t)
        local v = ns.Adventure.encodeList(list)
        local r = ns.Adventure.ledger:offer(a, g, t or ns.Share.serverNow(), ns.Share.hash(v), v)
        ns.Adventure.refresh()
        return r
    end
    -- B's ticket I wait on (團長同意), C's ticket I am in (直接錄取), and my own.
    local function withTickets(ns)
        local Adv = ns.Adventure
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "c", mc = t, st = "o", sa = t } })
        offer(ns, C, "T", { { id = "accc.1", src = "g", ver = 1, cr = t, ds = "sfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        wow.advance(5)
        Adv.worker("abbb.1", "apply"); Adv.worker("accc.1", "apply")
        local mine = Adv.open({ dungeon = "rfc", leaderRole = "h" })
        wow.advance(5)
        return mine
    end
    local function rowOf(U, id)
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then return r end end
        return nil
    end
    local function lastPoint(f) return f._points and f._points[#f._points] end

    ---------------------------------------------------------------------------
    -- 1. The toolkit's own icon
    ---------------------------------------------------------------------------

    test("GF-UI-P 1 the toolkit's icon is a wrench (minimap, TOC), the engineering icon as fallback; no bag", function()
        local ns = login()
        local F = ns.Framework
        eq(F.MINIMAP_ICON, "Interface\\Icons\\INV_Misc_Wrench_01", "minimap icon")
        eq(F.MINIMAP_ICON_FALLBACK, "Interface\\Icons\\Trade_Engineering", "fallback (known in 16001: 診斷 uses it)")
        local toc = readAll(ADDON_DIR .. "/GreenFangToolkit.toc")
        ok(has(toc, "## IconTexture: Interface\\Icons\\INV_Misc_Wrench_01"), "TOC")
        ok(not has(toc, "INV_Misc_Bag"), "no bag in the TOC")
        ok(not has(readAll(ADDON_DIR .. "/Framework.lua"):match("F%.MINIMAP_ICON[^\n]*\n[^\n]*") or "", "Bag"), "no bag for the minimap")
        eq(_G.GreenFangToolkit_MinimapButton.iconPath, F.MINIMAP_ICON, "the button shows it")
    end)

    ---------------------------------------------------------------------------
    -- 2. Adventure rows: text buttons only, inside the row, never overlapping; icon sizes
    ---------------------------------------------------------------------------

    test("GF-UI-P 2 adventure rows: every button is a text button inside the row; nothing overlaps; few icon sizes", function()
        local ns = login()
        local U = ns.AdventureUI
        local mine = withTickets(ns)
        ns.Framework.open("adventure")
        U.refresh()
        local rows = { mine = rowOf(U, mine), wait = rowOf(U, "abbb.1"), member = rowOf(U, "accc.1") }
        ok(rows.mine and rows.wait and rows.member, "three ticket rows shown")
        local C = U.COL
        eq(C.delete + U.ACTION_W, U.ROW_WIDTH, "刪除 ends at the row's right edge")
        for what, r in pairs(rows) do
            local boxes = {}
            for _, b in ipairs(r.buttons) do
                if b:IsShown() then
                    ok(b.textStyle, what .. ": " .. tostring(b.tip) .. " is a text button")
                    ok(not b.tex:IsShown(), what .. ": no icon in it")
                    eq(b._h, U.ACTION_H, what .. ": one height") -- GF-UI-Q: 24 (room between the two lines)
                    local right = b.flowX + ns.OrdersUI.buttonSpan(b)
                    ok(right <= U.ROW_WIDTH, what .. ": inside the row (" .. right .. ")")
                    boxes[#boxes + 1] = { l = b.flowX, r = right, line = 2, name = b.tip }
                end
            end
            if r.delete:IsShown() then
                ok(r.delete.textStyle, what .. ": 刪除 is a text button too")
                eq(plain(r.delete.gfTextText._text), "刪除", what .. ": its word")
                boxes[#boxes + 1] = { l = C.delete, r = C.delete + U.ACTION_W, line = 1, name = "刪除" }
                -- Line 1's leader name ends before it.
                ok(C.who + C.whoW <= C.delete, what .. ": the leader's name ends before 刪除")
            end
            for i = 1, #boxes do
                for j = i + 1, #boxes do
                    local a, b = boxes[i], boxes[j]
                    ok(a.line ~= b.line or a.r + U.BUTTON_GAP <= b.l or b.r + U.BUTTON_GAP <= a.l,
                        what .. ": " .. a.name .. " × " .. b.name)
                end
            end
        end
        -- Which buttons: the leader's 編輯 / 組隊 are words; the member's 撤回 too.
        local words = {}
        for _, b in ipairs(rows.mine.buttons) do if b:IsShown() then words[#words + 1] = plain(b.gfTextText._text) end end
        ok(has(table.concat(words, ","), "編輯") and has(table.concat(words, ","), "組隊"), "編輯 and 組隊: " .. table.concat(words, ","))
        local wb = rows.wait.buttons[1]
        eq(plain(wb.gfTextText._text), "撤回", "撤回 is a word")
        -- The offline mark stays on line 1 (it reached into line 2's first button).
        local r = rows.wait
        local p = lastPoint(r.off)
        eq(p[1] .. ">" .. p[3], "BOTTOMRIGHT>BOTTOMRIGHT", "on the class icon's corner")
        ok((p[5] or 0) >= 0, "not below the class icon")
        eq(r.off._w, U.TEXT_ICON, "the text icon size")
        -- Sizes: 44 art, 28 class, 20 small marks, 18 text icons.
        eq(r.dest._w, U.DEST_ICON, "art"); eq(r.cls._w, ns.ROW_ICON, "class icon")
        eq(r.att._w, U.ROW_SMALL, "❗"); eq(r.slots[1]._w, U.ROW_SMALL, "seat"); eq(ns.Widgets.BADGE_ICON, U.ROW_SMALL, "badge icon")
        local src = readAll(ADDON_DIR .. "/AdventureUI.lua")
        local timeFn = src:match("function UI%.rowTimeText.-\nend") or ""
        ok(timeFn ~= "" and not has(timeFn, ", 16)"), "the row's time: no 16 px mark among 18s")
        -- 下一位: a text button like the others on the page (was a 32 px icon).
        eq(U.nextInvite._h, ns.BUTTON_H, "下一位 is a text button")
        ok(has(plain(U.nextInvite:GetText()), "下一位"), "its name")
    end)

    ---------------------------------------------------------------------------
    -- 3. My own status in plain words
    ---------------------------------------------------------------------------

    test("GF-UI-P 3 on someone else's ticket the badge says my status (已申請 / 已錄取), not 已定案", function()
        local ns = login()
        local U, Adv, W = ns.AdventureUI, ns.Adventure, ns.Widgets
        local mine = withTickets(ns)
        eq(Adv.myStatus(Adv.get("abbb.1"), A), "p", "I applied, the leader decides")
        eq(Adv.myStatus(Adv.get("accc.1"), A), "m", "I am in")
        eq(Adv.myStatus(Adv.get(mine), A), nil, "my own ticket: the ticket's state")
        eq(Adv.STATE_NAME.final, "已定案", "已定案 stays the ticket's word")
        for k, name in pairs(Adv.MY_STATUS_NAME) do
            ok(name ~= "已定案" and not has(name, "定案"), k .. ": never 定案")
            ok(W.chars(name) <= 3, k .. ": fits the badge")
            ok(Adv.MY_STATUS_TIP[k], k .. ": a tooltip line")
        end
        ns.Framework.open("adventure")
        U.refresh()
        eq(plain(rowOf(U, "abbb.1").badge.text._text), "已申請", "waiting")
        eq(plain(rowOf(U, "accc.1").badge.text._text), "已錄取", "in")
        eq(plain(rowOf(U, mine).badge.text._text), Adv.STATE_NAME[Adv.get(mine).state], "mine: the ticket's state")
        -- The tooltip: my status first, then the ticket's (named as the ticket's).
        local why = U.why(Adv.get("accc.1"))
        local lines = W.checklistLines(why, U.WHY_OPTS)
        ok(has(plain(lines[1].text), "你的狀態：已錄取"), "first line: " .. plain(lines[1].text))
        ok(has(plain(lines[2].text), Adv.MY_STATUS_TIP.m), "then what it means")
        ok(has(plain(lines[3].text), "冒險單：" .. why.ticketName), "then the ticket: " .. plain(lines[3].text))
        -- The notices use the same words (錄取 / 候補), never 定案 for a person.
        local src = readAll(ADDON_DIR .. "/Adventure.lua")
        ok(has(src, "錄取了你") and has(src, "（你在候補）") and has(src, "邀請你加入"), "notices: 錄取, 候補, 邀請")
        -- The leader's own row still shows the ticket's word.
        local lw = U.why(Adv.get(mine))
        eq(lw.mine, nil, "no own status on my own ticket")
    end)

    ---------------------------------------------------------------------------
    -- 4. List-row tooltips next to the mouse (one helper)
    ---------------------------------------------------------------------------

    test("GF-UI-P 4 row tooltips sit beside the row at the cursor, turn at the screen's halves; one helper everywhere", function()
        local ns = login()
        local W = ns.Widgets
        local gw, gh, gc = UIParent.GetWidth, UIParent.GetHeight, GetCursorPosition
        UIParent.GetWidth = function() return 1600 end
        UIParent.GetHeight = function() return 900 end
        local row = CreateFrame("Frame", nil, UIParent)
        local function edges(l, r, t, b)
            row.GetLeft = function() return l end; row.GetRight = function() return r end
            row.GetTop = function() return t end; row.GetBottom = function() return b end
        end
        -- Low on the screen, cursor on the right half: above the row, growing left of the cursor.
        edges(200, 1230, 300, 236)
        GetCursorPosition = function() return 1100, 260 end
        local p = W.tipPlace(row)
        eq(p.point .. ">" .. p.relPoint, "BOTTOMRIGHT>TOPLEFT", "above, to the left")
        eq(p.x, 1100 - 200 - W.TIP_CURSOR, "its right edge just left of the cursor")
        ok(p.y > 0, "above the row: never on it")
        -- High on the screen, cursor on the left half: below the row, growing right.
        edges(200, 1230, 820, 756)
        GetCursorPosition = function() return 400, 790 end
        p = W.tipPlace(row)
        eq(p.point .. ">" .. p.relPoint, "TOPLEFT>BOTTOMLEFT", "below, to the right")
        eq(p.x, 400 - 200 + W.TIP_CURSOR, "its left edge just right of the cursor")
        ok(p.y < 0, "below the row")
        -- A cursor outside the row is kept on it.
        GetCursorPosition = function() return 50, 790 end
        eq(W.tipPlace(row).x, 0 + W.TIP_CURSOR, "clamped to the row's left edge")
        -- rowTip uses it.
        W.rowTip(row)
        eq(GameTooltip._anchor, "ANCHOR_NONE", "placed by the toolkit")
        eq(GameTooltip._points[1][2], row, "on the row")
        UIParent.GetWidth, UIParent.GetHeight, GetCursorPosition = gw, gh, gc
        -- Every list row's tooltip goes through it (adventure, worker, stock, supply, profile, recipes).
        local uses = {
            { "AdventureUI.lua", 2 }, { "SupplyUI.lua", 2 }, { "ProfileUI.lua", 1 }, { "Recipes.lua", 1 },
        }
        for _, u in ipairs(uses) do
            local _, n = readAll(ADDON_DIR .. "/" .. u[1]):gsub("Widgets%.rowTip%(", "")
            ok(n >= u[2], u[1] .. ": rowTip " .. n)
        end
        ok(has(readAll(ADDON_DIR .. "/Widgets.lua"):match("function W%.itemTooltip.-\nend") or "", "W.rowTip(owner)"),
            "the stock rows' item tooltip too")
        -- The adventure page: a ticket row.
        local U = ns.AdventureUI
        withTickets(ns)
        ns.Framework.open("adventure")
        U.refresh()
        local r = rowOf(U, "abbb.1")
        r._scripts.OnEnter(r)
        eq(GameTooltip._anchor, "ANCHOR_NONE", "ticket row: placed by the toolkit")
        local want = W.tipPlace(r)
        eq(GameTooltip._points[1][1] .. ">" .. GameTooltip._points[1][3], want.point .. ">" .. want.relPoint, "ticket row: rowTip's place")
    end)

    ---------------------------------------------------------------------------
    -- 5. The adventure filter row
    ---------------------------------------------------------------------------

    test("GF-UI-P 5 filters: search (活動 / 團長), 種類, 只看有空位的, 區域 in the row; kept until data or a filter changes", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local mine = withTickets(ns)
        ns.Framework.open("adventure")
        U.refresh()
        local function ids()
            local out = {}
            for _, r in ipairs(U.pageRows()) do if r.view then out[#out + 1] = r.view.id end end
            table.sort(out)
            return table.concat(out, ",")
        end
        local all = ids()
        ok(has(all, "abbb.1") and has(all, "accc.1") and has(all, mine), "all three: " .. all)
        -- Layout: one row under the buttons, nothing overlapping, the list under it.
        local FX = U.FILTER_X
        ok(FX.search + U.SEARCH_W <= FX.kindLabel, "search box before 種類")
        ok(FX.kindLabel + ns.labelWidth("種類") <= FX.kind, "種類 before its menu")
        ok(FX.kind + U.KIND_W <= FX.zone, "種類 menu before 區域")
        ok(FX.zone + U.ZONE_W <= FX.room, "區域 before 只看有空位的")
        ok(FX.room + 28 + ns.labelWidth(U.ROOM_LABEL) <= U.ROW_WIDTH, "the check box ends inside")
        ok(U.FILTER_Y <= -40 - ns.BUTTON_H - 8, "under the top buttons")
        ok(U.LIST_Y <= U.FILTER_Y - ns.BUTTON_H - 8, "the list under the filters")
        eq(U.scrollFrame()._points[1][3], U.LIST_Y, "the list starts there")
        local zp = lastPoint(U.zoneButton)
        eq(zp[4] .. "," .. zp[5], FX.zone .. "," .. U.FILTER_Y, "區域 moved into the filter row")
        eq(lastPoint(U.activeTab)[2], U.lfgButton:IsShown() and U.lfgButton or U.calendarButton, "進行中 follows the last shown button")
        ok(U.SEARCH_DELAY <= 0.15, "typing waits at most 0.15 s")
        -- Search: by the leader's name (C is 測試丙), by the activity's name.
        U.setSearch("測試丙")
        eq(ids(), "accc.1", "by leader")
        local dest = plain(U.destText(Adv.get("abbb.1")))
        U.setSearch(dest)
        eq(ids(), "abbb.1", "by activity: " .. dest)
        U.setSearch("")
        -- 種類: 任務 hides the dungeon tickets; 地城 shows them.
        U.setKind("quest"); eq(ids(), "", "no quest tickets")
        ok(U.emptyLine._text == U.EMPTY_FILTERED or #U.pageRows() > 0, "the empty line says to change the filter")
        U.setKind("dungeon"); eq(ids(), all, "dungeons")
        U.setKind("all")
        -- 只看有空位的: a full ticket goes, an open one stays.
        local v = Adv.get("accc.1")
        U.setRoom(true)
        ok(U.ticketPass(v), "room left: shown")
        ok(not U.ticketPass(setmetatable({ full = true }, { __index = v })), "full: hidden")
        ok(not U.ticketPass(setmetatable({ state = "formed" }, { __index = v })), "formed: hidden")
        U.setRoom(false)
        -- Typing: applied only after the delay.
        U.searchBox:SetText("測試乙")
        U.searchBox._scripts.OnTextChanged(U.searchBox, true)
        eq(U.filter.search, "", "not yet")
        wow.advance(0.2)
        eq(U.filter.search, "測試乙", "after the delay")
        eq(ids(), "abbb.1", "filtered")
        -- Cache: the same data and filters: kept; a filter change or new data: built again.
        local st = U.filterStats
        local built, hits = st.built, st.hits
        U.pageRows(); U.pageRows()
        eq(st.built, built, "nothing rebuilt"); ok(st.hits >= hits + 2, "kept")
        U.setSearch("測試丙")
        eq(st.built, built + 1, "a filter change rebuilds")
        local hay = st.hay
        U.pageRows()
        eq(st.hay, hay, "search words kept per row")
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "c", mc = t, st = "o", sa = t },
            { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "sfk", qs = "", tm = "n", rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } }, t + 1)
        wow.advance(2)
        local b2 = st.built
        U.setSearch("測試乙")
        ok(st.built > b2, "new data: built again")
        ok(has(ids(), "abbb.2"), "the new ticket is found: " .. ids())
        ok(st.hay > hay, "search words made again for the new data")
        -- A jump to a ticket the filters hide turns them off.
        U.setSearch("測試丙")
        U.focus(mine)
        eq(U.filtersOn(), false, "filters off")
        eq(U.focusId, mine, "focused")
    end)

    ---------------------------------------------------------------------------
    -- 6. The guild bank page under the buttons
    ---------------------------------------------------------------------------

    test("GF-UI-P 6 公會銀行 starts under 庫存／申領…; 庫存, 申領 and 保管人 start there too", function()
        local ns = login()
        local B, GB = ns.BankUI, ns.GuildBankUI
        ns.Framework.open("bank")
        B.setView("guildbank")
        local c = GB.c
        ok(c.built and c.root, "built in its own frame")
        local p = lastPoint(c.root)
        eq(p[1] .. ">" .. p[3], "TOPLEFT>TOPLEFT", "anchored at the page's top left")
        eq(p[4] .. "," .. p[5], B.X .. "," .. B.Y.status, "from where added views start")
        local stripBottom = B.Y.views - ns.BUTTON_H
        ok(B.Y.status < stripBottom, "below the 庫存／申領… buttons (" .. B.Y.status .. " < " .. stripBottom .. ")")
        for _, k in ipairs({ "moneyLabel", "money", "seen", "sum7", "sum30", "searchLabel", "count", "more", "empty", "note" }) do
            eq(c[k]._parent, c.root, k .. " is in the view's frame")
        end
        for _, b in ipairs(c.filters) do eq(b._parent, c.root, "filter in the view's frame") end
        ok(c.rowW + ns.Widgets.SCROLL_GAP + ns.Widgets.SCROLL_W <= c.w, "rows and the bar fit the width")
        ok(B.X + c.w <= B.VIEW_W, "inside the page")
        -- The other views: their first things are under the buttons too.
        ok(B.Y.filters < stripBottom, "庫存's filters")
        ok(B.REQ_Y.todoHead < stripBottom, "申領's first heading")
        ok(B.Y.status < stripBottom and B.Y.listHead < stripBottom, "保管人's status and list")
    end)

    ---------------------------------------------------------------------------
    -- 7. 「＋」 on the add buttons
    ---------------------------------------------------------------------------

    test("GF-UI-P 7 the add buttons start with ＋: ＋刊登, ＋保管人, ＋審核幹部 (as ＋冒險單 / ＋職工單 / ＋下單)", function()
        local ns = login()
        eq(ns.SupplyUI.POST_TEXT, "＋刊登", "調貨所")
        ns.Framework.open("supply")
        ok(has(plain(ns.SupplyUI.postButton:GetText()), "＋刊登"), "the button")
        ns.Framework.open("bank")
        local c = ns.BankUI.controls
        ok(has(plain(c.appoint:GetText()), "＋保管人"), "保管人")
        ok(has(plain(c.officerAdd:GetText()), "＋審核幹部"), "審核幹部")
        ns.Framework.open("adventure")
        ok(has(plain(ns.AdventureUI.newButton:GetText()), "＋冒險單") and has(plain(ns.AdventureUI.workerButton:GetText()), "＋職工單"), "adventure")
        ns.Framework.open("orders")
        ok(has(plain(ns.OrdersUI.orderButton:GetText()), "＋下單"), "委託")
    end)

    ---------------------------------------------------------------------------
    -- 8. One scroll bar for every list
    ---------------------------------------------------------------------------

    test("GF-UI-P 8a the shared scroll bar: arrows, knob, grey within one page, moves the list, keeps to its ends", function()
        local ns = login()
        local W = ns.Widgets
        local got = {}
        local bar = W.scrollBar(UIParent, 300, function(o) got[#got + 1] = o end)
        ok(bar.up and bar.down and bar.bar, "up, down and the track")
        eq(bar.up._w, W.SCROLL_ARROW, "arrow size"); eq(bar._w, W.SCROLL_W, "bar width")
        bar.sync(0, 5, 8)
        eq(bar.scrollable, false, "fits one page"); eq(bar.up.gfEnabled, false, "up grey"); eq(bar.down.gfEnabled, false, "down grey")
        eq(bar.scrollBy(1), false, "does nothing"); eq(#got, 0, "no redraw")
        bar.sync(0, 20, 8)
        eq(bar.scrollable, true, "more than a page"); eq(bar.up.gfEnabled, false, "at the top"); eq(bar.down.gfEnabled, true, "can go down")
        eq(bar.bar._max, 12, "the knob's range")
        bar.down._scripts.OnClick(bar.down)
        eq(got[#got], 1, "down: one row")
        bar.scrollTo(100)
        eq(got[#got], 12, "kept to the end")
        bar.bar._scripts.OnValueChanged(bar.bar, 4.4)
        eq(got[#got], 4, "dragging the knob")
        bar._scripts.OnMouseWheel(bar, 1)
        eq(got[#got], 3, "the wheel over the bar")
        local n = #got
        bar.sync(3, 20, 8)
        eq(#got, n, "drawing again does not scroll again")
    end)

    test("GF-UI-P 8b every list that refills its rows has the bar, right of its rows, inside its page", function()
        local ns = login()
        local W = ns.Widgets
        local function xOf(f) local p = lastPoint(f); return p and p[4] end
        -- 臨時黑箱: 庫存, 保管人, 審核幹部, 申領 (two lists); 公會銀行.
        ns.Framework.open("bank")
        local B = ns.BankUI
        local c = B.controls
        local bars = { stock = c.stockBar, keepers = c.bar, officers = c.officerBar, todo = c.req.todo.bar, mine = c.req.mine.bar }
        for k, b in pairs(bars) do
            ok(b and b.gfScrollBar, k .. ": a bar")
            ok(xOf(b) + W.SCROLL_W <= B.VIEW_W, k .. ": inside the page")
        end
        eq(xOf(c.stockBar), B.X + B.STOCK_W + W.SCROLL_GAP, "stock: right of its rows")
        eq(xOf(c.bar), B.X + B.ROW_W + W.SCROLL_GAP, "keepers: right of the rows")
        ok(xOf(c.bar) + W.SCROLL_W <= B.RIGHT_X, "keepers: before the right column")
        B.setView("guildbank")
        local g = ns.GuildBankUI.c
        ok(g.bar and g.bar.gfScrollBar, "公會銀行")
        eq(xOf(g.bar), g.rowW + W.SCROLL_GAP, "right of its rows")
        -- 調貨所: the list (narrow and wide) and the people on the right.
        ns.Framework.open("supply")
        local S = ns.SupplyUI
        ok(S.listBar and S.listBar.gfScrollBar and S.detailBar, "調貨所: list and detail")
        local lx = xOf(S.listBar)
        eq(lx, S.LIST_X + S.listWidth() + S.BAR_GAP, "right of the list")
        ok(S.LIST_X + S.LIST_W + S.BAR_GAP + W.SCROLL_W <= S.DETAIL_X - 16, "narrow: before the divider")
        ok(S.LIST_X + S.LIST_W_WIDE + S.BAR_GAP + W.SCROLL_W <= ns.Framework.PANEL_WIDTH, "wide: inside the page")
        ok(S.DETAIL_X + S.DETAIL_W + S.BAR_GAP + W.SCROLL_W <= ns.Framework.PANEL_WIDTH, "detail: inside the page")
        -- 通知.
        local N = ns.NotifyUI
        N.open()
        local f = _G[N.LIST_NAME]
        ok(f.bar and f.bar.gfScrollBar, "通知")
        ok(xOf(f.bar) + W.SCROLL_W <= N.W, "inside the list window")
        eq(f.bar.visible, N.ROWS, "synced with the rows")
        -- The pages with the game's scroll frame keep it (業務大廳, 委託, 名冊, 配方).
        for _, file in ipairs({ "AdventureUI.lua", "OrdersUI.lua", "UI.lua", "Recipes.lua" }) do
            ok(has(readAll(ADDON_DIR .. "/" .. file), '"UIPanelScrollFrameTemplate"'), file .. ": the game's scroll frame")
        end
    end)

    ---------------------------------------------------------------------------
    -- 9. No OnUpdate, no polling
    ---------------------------------------------------------------------------

    test("GF-UI-P 9 nothing new runs every frame or on a timer", function()
        -- The number of OnUpdate / ticker mentions per changed file, as on main (0.16.18).
        local base = { ["Widgets.lua"] = 1, ["AdventureUI.lua"] = 0, ["Adventure.lua"] = 0, ["BankUI.lua"] = 0,
            ["GuildBankUI.lua"] = 0, ["NotifyUI.lua"] = 0, ["SupplyUI.lua"] = 0, ["Framework.lua"] = 3,
            ["ProfileUI.lua"] = 0, ["Recipes.lua"] = 0 }
        for file, n in pairs(base) do
            local src = readAll(ADDON_DIR .. "/" .. file)
            local _, k = src:gsub("OnUpdate", "")
            eq(k, n, file .. ": OnUpdate")
            ok(not has(src, "NewTicker"), file .. ": no ticker")
        end
        -- The bars and the tooltip helper have no OnUpdate script.
        local ns = login()
        local bar = ns.Widgets.scrollBar(UIParent, 200, function() end)
        for _, f in ipairs({ bar, bar.up, bar.down, bar.bar }) do eq(f._scripts.OnUpdate, nil, "no OnUpdate") end
    end)
end
