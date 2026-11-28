-- GF-UI-Q: the owner's 0.16.19 screenshots of the adventure page (2026-11-28):
-- room between a row's leader and the 撤回 button below it, the 規則 card in
-- plain sentences (as Adventure.lua does it, numbers from it, scrolling), 週｜月
-- in 業務排程 (remembered, cells reused), and three different legend marks
-- (the same on the day's icons) with a line on hover. Offline only; made-up data.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B = "0000-0000000B"
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
    local function rowOf(U, id)
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then return r end end
    end

    ---------------------------------------------------------------------------
    -- A. 撤回 below the leader's name: room between them
    ---------------------------------------------------------------------------

    test("GF-UI-Q A row buttons: 24 high, 4 px below the leader's class icon, 8 px below 刪除, inside the row", function()
        local ns = login()
        local U = ns.AdventureUI
        local t = ns.Share.serverNow()
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3,
            lr = "d", tg = 0, md = "c", mc = t, st = "o", sa = t } })
        wow.advance(5)
        ns.Adventure.worker("abbb.1", "apply")
        ns.Framework.open("adventure")
        U.refresh()
        local r = rowOf(U, "abbb.1")
        ok(r, "B's row")
        local b = r.buttons[1]
        eq(plain(b.gfTextText._text), "撤回", "撤回 shown")
        eq(b._h, U.ACTION_H, "24 high")
        eq(b._points[1][5], U.ACTION_Y2, "line 2, 2 px lower")
        local half = U.ROW_HEIGHT / 2
        local clsBottom = U.LINE1 - ns.ROW_ICON / 2
        local btnTop, btnBottom = U.ACTION_Y2 + U.ACTION_H / 2, U.ACTION_Y2 - U.ACTION_H / 2
        ok(clsBottom - btnTop >= 4, "4 px between the class icon and the button: " .. (clsBottom - btnTop))
        ok(btnBottom >= -half, "inside the row's bottom")
        local delBottom = U.ACTION_Y1 - U.ACTION_H / 2
        ok(delBottom - btnTop >= 8, "8 px between 刪除 and a button below it")
        ok(U.ACTION_Y1 + U.ACTION_H / 2 <= half, "刪除 inside the row's top")
        eq(r.delete._points[1][5], U.ACTION_Y1, "刪除 on line 1, 2 px higher")
        -- Still one after another inside the row (GF-UI-P).
        ok(b.flowX + U.ACTION_W <= U.ROW_WIDTH, "inside the row")
    end)

    ---------------------------------------------------------------------------
    -- B. 規則: plain sentences, as the code does it
    ---------------------------------------------------------------------------

    test("GF-UI-Q B 規則: headings and sentences, every number from Adventure, nothing cut, page font", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local list = U.rulesText()
        local heads, all = {}, {}
        for _, e in ipairs(list) do
            if e.head then heads[#heads + 1] = e.head end
            all[#all + 1] = plain(e.head or e.text or table.concat(e.cols or {}, " "))
        end
        local text = table.concat(all, "\n")
        for _, h in ipairs({ "一張冒險單怎麼走", "什麼時候算已定案", "什麼時候算成團", "什麼時候算成行", "過期、未成行、取消", "退回與重開", "隊伍要幾個人" }) do
            ok(has(table.concat(heads, ","), h), "heading " .. h)
        end
        -- The states by their names in the code.
        for _, st in ipairs({ "open", "final", "formed", "done", "ended", "unfinished", "cancel" }) do
            ok(has(text, Adv.STATE_NAME[st]), "names " .. Adv.STATE_NAME[st])
        end
        -- The rules the code has (and the ones the old picture left out).
        for _, s in ipairs({ "錄取第一個人，就自動定案", "按「定案」", "名額全部錄取滿了", "按「完成」", "交了單上的任務",
            "進到目的地地城", "也一起算成團", "不能從", "按「重開」", "團長也算", "最少 2 人" }) do
            ok(has(text, s), "says: " .. s)
        end
        -- Numbers from Adventure.lua.
        local first = list[2].text
        eq(select(2, first:gsub("|T", "")), 3, "the order line: three inline arrows (the font has no →)")
        ok(has(first, "ChatFrameExpandArrow"), "the game's arrow")
        ok(has(text, "60 分鐘"), "AUTO_BEFORE"); ok(has(text, "4 小時"), "AUTO_NO_LENGTH"); ok(has(text, "30 分鐘"), "SLACK")
        ok(has(text, "24 小時"), "UNFINISHED_AFTER"); ok(has(text, "15 分鐘"), "OFFLINE_CLOSE"); ok(has(text, "60%"), "AUTO_SHARE")
        local old = Adv.OFFLINE_CLOSE
        Adv.OFFLINE_CLOSE = 20 * 60
        ok(has(table.concat((function() local o = {} for _, e in ipairs(U.rulesText()) do o[#o + 1] = plain(e.text or "") end return o end)(), "\n"),
            "20 分鐘"), "a changed number shows")
        Adv.OFFLINE_CLOSE = old
        -- The table: sizes -> people, from autoNeeded.
        local sizes, needs
        for _, e in ipairs(list) do if e.cols then if not sizes then sizes = e.cols else needs = e.cols end end end
        eq(table.concat(sizes, " "), "單子人數 3 4 5 10 20 40", "the sizes")
        local want = { "隊伍至少" }
        for _, n in ipairs(U.RULE_SIZES) do want[#want + 1] = tostring(Adv.autoNeeded({ size = n })) end
        eq(table.concat(needs, " "), table.concat(want, " "), "from autoNeeded")
        eq(table.concat(needs, " "), "隊伍至少 2 3 3 6 12 24", "the numbers")
        -- On the card: one line each, none cut; the page's body font (16) or the heading font.
        ns.Framework.open("adventure")
        local f = U.openRules(U.rulesButton)
        local seen = 0
        for _, kind in ipairs({ "ruleTexts", "ruleHeads", "ruleCols" }) do
            for _, fs in ipairs(f[kind]) do
                if fs:IsShown() then
                    seen = seen + 1
                    ok(not fs:IsTruncated(), "not cut: " .. plain(fs._text))
                    ok(fs._font == ns.LABEL_FONT or fs._font == ns.FIELD_FONT, "page font: " .. plain(fs._text))
                end
            end
        end
        ok(seen >= 12, "lines shown: " .. seen)
        -- Never an old picture's arrow texture.
        for _, o in ipairs(wow.allObjects()) do
            if o._parent == f and o._kind == "Texture" and o._shown then ok(not has(o._texture, "Arrow"), "no arrow picture") end
        end
    end)

    test("GF-UI-Q B 規則 scrolls by lines to the last one (bar, wheel); ESC closes", function()
        local ns = login()
        local U = ns.AdventureUI
        ns.Framework.open("adventure")
        local f = U.openRules(U.rulesButton)
        local list = U.rulesText()
        local maxOff = U.rulesMaxOffset(list)
        ok(maxOff > 0, "longer than the card")
        ok(f.bar:IsShown() and f.bar.scrollable, "a scroll bar")
        eq(f.offset, 0, "from the top")
        f.bar.scrollTo(999)
        eq(f.offset, maxOff, "down to the end")
        local last = plain(list[#list].cols and list[#list].cols[1] or list[#list].text)
        local found = false
        for _, fs in ipairs(f.ruleCols) do if fs:IsShown() and plain(fs._text) == last then found = true end end
        ok(found, "the last line shows")
        f._scripts.OnMouseWheel(f, 1)
        ok(f.offset < maxOff, "the wheel scrolls up")
        -- Every shown line inside the card above its bottom.
        for _, fs in ipairs(f.ruleTexts) do
            if fs:IsShown() then ok(-fs._points[1][5] + 16 <= f._h, "inside: " .. plain(fs._text)) end
        end
        ns.escape()
        ok(not f:IsShown(), "ESC")
        U.openRules()
        eq(f.offset, 0, "opens at the top again")
    end)

    ---------------------------------------------------------------------------
    -- C. 業務排程: 週｜月
    ---------------------------------------------------------------------------

    local function dayAt(ns, k, hh) return ns.AdventureUI.dayStart(k) + (hh or 20) * H end

    test("GF-UI-Q C 週｜月: a month grid, ◀ ▶ a month, the day's tickets, the choice kept", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = dayAt(ns, 1) } } })
        Adv.open({ dungeon = "rfc", leaderRole = "d", slots = { { s = dayAt(ns, 1, 22) } } })
        local f = U.openCalendar()
        eq(U.calendarView(), "week", "week first")
        eq(f.views.key, "week", "週 chosen")
        ok(f.cells[1]:IsShown() and not f.monthCells, "the week's cells; no month yet")
        wow.click(f.views.button("month"))
        eq(U.calendarView(), "month", "month")
        eq(ns.settings().calendarView, "month", "kept in the settings")
        eq(#f.monthCells, 42, "6 rows of 7")
        for _, c in ipairs(f.cells) do ok(not c:IsShown(), "week cells hidden") end
        local d = date("*t", U.dayStart(0) + 12 * H - U.skew())
        ok(has(f.weekLabel._text, d.year .. " 年 " .. d.month .. " 月"), "the month: " .. f.weekLabel._text)
        -- The 1st of the month sits under its weekday (日 first).
        local first = U.monthStart(0)
        local d1 = date("*t", U.dayStart(first) + 12 * H - U.skew())
        local c1 = f.monthCells[d1.wday]
        eq(c1.dayOff, first, "the 1st under " .. U.WEEKDAY[d1.wday])
        eq(c1.head._text, "1", "its number")
        for i = 1, 7 do eq(f.weekdays[i]._text, U.WEEKDAY[i], "weekday heads") ; ok(f.weekdays[i]:IsShown(), "shown") end
        -- Tomorrow: two tickets, a count and two icons.
        local tom
        for _, c in ipairs(f.monthCells) do if c.dayOff == 1 then tom = c end end
        ok(tom and tom.enabled, "tomorrow can be chosen")
        eq(tom.more._text, "2 張", "how many")
        local icons = 0
        for _, ic in ipairs(tom.icons) do if ic:IsShown() then icons = icons + 1; eq(ic.kind, "mine", "my mark") end end
        eq(icons, 2, "two icons")
        wow.click(tom)
        eq(f.day, 1, "chosen")
        local rows = 0
        for _, r in ipairs(f.list) do if r:IsShown() then rows = rows + 1 end end
        eq(rows, 2, "its tickets below")
        -- Out of range days are dim and not chosen.
        local past
        for _, c in ipairs(f.monthCells) do if c.dayOff < 0 then past = c end end
        if past then
            ok(not past.enabled, "a past day cannot be chosen")
            wow.click(past); eq(f.day, 1, "unchanged")
        end
        -- ◀ ▶: a month; greyed at the ends.
        ok(f.prev.disabled, "this month: ◀ greyed")
        eq(f.prev.tip, "上個月", "◀ says month")
        local pages = U.monthPages()
        if pages > 1 then
            ok(not f.next.disabled, "▶ to next month (day 14 is in it)")
            wow.click(f.next)
            eq(f.page, 1, "next month")
            eq(f.monthCells[1].dayOff + (date("*t", U.dayStart((U.monthStart(1))) + 12 * H - U.skew()).wday - 1), U.monthStart(1), "its 1st")
        end
        ok(f.next.disabled, "no further than day 14")
        -- Kept: closed and opened again in month.
        f:Hide()
        U.openCalendar()
        eq(U.calendarView(), "month", "remembered")
        eq(f.views.key, "month", "月 shown chosen")
        ok(f.monthCells[1]:IsShown(), "month cells")
        -- Back to the week: as before.
        wow.click(f.views.button("week"))
        eq(U.calendarView(), "week", "week")
        ok(f.cells[1]:IsShown() and not f.monthCells[1]:IsShown(), "week cells again")
        eq(f.prev.tip, "上一週", "◀ says week")
        f.day = 0
        wow.click(f.cells[2]); eq(f.day, 1, "a week day")
    end)

    test("GF-UI-Q C cells and icons are reused: flipping makes no new frames; the day list scrolls", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        for k = 1, 12 do Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = dayAt(ns, 2, 8 + k) } } }) end
        local f = U.openCalendar()
        U.setCalendarView("month")
        wow.click(f.next); wow.click(f.prev)
        local n = #wow.allObjects()
        for _ = 1, 5 do wow.click(f.next); wow.click(f.prev) end
        U.setCalendarView("week"); U.setCalendarView("month")
        U.drawCalendar(); U.drawCalendar()
        eq(#wow.allObjects(), n, "no new frames when flipping or switching")
        -- Day 2 has up to 12 (Adv.MAX_TICKETS might stop some): the list scrolls.
        local items = U.calendarItems(2)
        ok(#items > U.calendarListRows("month"), "more than fit: " .. #items)
        for _, c in ipairs(f.monthCells) do if c.dayOff == 2 then wow.click(c) end end
        ok(f.listBar:IsShown() and f.listBar.scrollable, "a scroll bar")
        local shown = 0
        for _, r in ipairs(f.list) do if r:IsShown() then shown = shown + 1 end end
        eq(shown, U.calendarListRows("month"), "the rows that fit")
        f.listBar.scrollTo(999)
        eq(f.listOffset, #items - shown, "to the last")
        local lastRow
        for _, r in ipairs(f.list) do if r:IsShown() then lastRow = r end end
        eq(lastRow.item, items[#items], "the last ticket shows")
        -- Every list row ends above the window's bottom and left of the bar.
        for _, r in ipairs(f.list) do
            if r:IsShown() then ok(-r._points[1][5] + ns.PAGE_ROW <= U.CAL_WIN_H, "inside the window") end
        end
        ok(20 + U.CAL_LIST_W <= f.listBar._points[1][4], "the bar beside the rows")
        -- Clicking a new day starts its list at the top.
        for _, c in ipairs(f.monthCells) do if c.dayOff == 1 then wow.click(c) end end
        eq(f.listOffset, 0, "from the top")
    end)

    ---------------------------------------------------------------------------
    -- D. the legend: three different marks, the same on the icons, a line on hover
    ---------------------------------------------------------------------------

    test("GF-UI-Q D legend: three different marks (not three keys), the same as on the icons, explained on hover", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local t = ns.Share.serverNow()
        Adv.open({ dungeon = "smg", leaderRole = "d", slots = { { s = dayAt(ns, 1) } } })
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "rfk", qs = "", tm = "f",
            ts = Adv.encodeTimes({ { id = 1, s = dayAt(ns, 1, 21) } }), fx = 1, fa = t,
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        Adv.worker("abbb.1", "apply")
        local f = U.openCalendar()
        eq(#f.legend, 3, "three entries")
        local arts, names = {}, {}
        for _, e in ipairs(f.legend) do
            ok(not has(e.icon._texture, "Key"), "no key: " .. tostring(e.icon._texture))
            arts[e.icon._texture] = true
            names[#names + 1] = e.label._text
            ok(e.gfTip and #e.gfTip > 0, "a line for " .. e.label._text)
            e._scripts.OnEnter(e)
            eq(GameTooltip:GetOwner(), e, "hover: the tooltip")
            eq(GameTooltip._lines[1].text, e.gfTip, "says it")
            e._scripts.OnLeave(e)
        end
        local n = 0
        for _ in pairs(arts) do n = n + 1 end
        eq(n, 3, "three different pictures")
        eq(table.concat(names, ","), "我開的,我報名,已定案", "the words")
        eq(f.legend[1].label._color[1] .. "," .. f.legend[2].label._color[1], U.CAL_MINE[1] .. "," .. U.CAL_SIGNED[1], "word colours = frame colours")
        -- The day's icons carry the same corner pictures.
        local cell = f.cells[2]
        local mineIc, signedIc
        for _, ic in ipairs(cell.icons) do
            if ic:IsShown() and ic.kind == "mine" then mineIc = ic end
            if ic:IsShown() and ic.kind == "signed" then signedIc = ic end
        end
        ok(mineIc and signedIc, "both on day 1")
        eq(mineIc.who._texture, f.legend[1].icon._texture, "我開的: the same picture")
        ok(mineIc.who:IsShown() and not mineIc.fin:IsShown(), "mine: not finalized")
        eq(signedIc.who._texture, f.legend[2].icon._texture, "我報名: the same picture")
        ok(signedIc.fin:IsShown(), "finalized: the scroll")
        eq(signedIc.fin._texture, f.legend[3].icon._texture, "已定案: the same picture")
        ok(signedIc.shine:IsShown() and signedIc.glow:IsShown(), "and the shine and the frame, as before")
        -- The day's list rows too.
        wow.click(cell)
        local kinds = {}
        for _, r in ipairs(f.list) do
            if r:IsShown() then kinds[r.kind] = r.mark.who._texture end
        end
        eq(kinds.mine, f.legend[1].icon._texture, "list: mine")
        eq(kinds.signed, f.legend[2].icon._texture, "list: signed")
    end)

    ---------------------------------------------------------------------------
    -- Nothing runs every frame; nothing overlaps in the calendar's month view
    ---------------------------------------------------------------------------

    test("GF-UI-Q no OnUpdate, ticker, timer or event added; the windows fit", function()
        local src = readAll(ADDON_DIR .. "/AdventureUI.lua")
        local _, k = src:gsub("OnUpdate", "")
        eq(k, 0, "AdventureUI: no OnUpdate")
        ok(not has(src, "NewTicker") and not has(src, "C_Timer"), "no timer")
        local a = src:find("GF-UI-Q (owner 0.16.19: 「上面的鑰匙", 1, true)
        local b = src:find("function UI.rules() return rules end", 1, true)
        ok(a and b, "the new parts")
        ok(not has(src:sub(a, b), "RegisterEvent"), "no event")
        local ns = login()
        local U = ns.AdventureUI
        local f = U.openCalendar()
        U.setCalendarView("month")
        -- The month cells and the list stay inside the window, one under another.
        local lastCell = f.monthCells[42]
        local cellBottom = -lastCell._points[1][5] + U.CAL_MONTH_H
        ok(cellBottom + 8 <= -U.calendarListTop("month"), "the day label below the cells")
        ok(-U.calendarListTop("month") + 32 + U.calendarListRows("month") * ns.PAGE_ROW <= U.CAL_WIN_H, "the list inside")
        ok(lastCell._points[1][4] + U.CAL_CELL_W <= f._w, "inside on the right")
        -- The 週｜月 buttons right of the legend, left of the X.
        local legendEnd = f.legend[3]._points[1][4] + f.legend[3]._w
        ok(legendEnd < f.views.x, "legend then 週｜月")
        ok(f.views.x + 2 * 72 + 8 <= f._w - ns.Widgets.CLOSE_SIZE, "before the X")
    end)
end
