-- GF-UI-G: the 冒險業務 sample page — the palette (GF-UI-J: warm charcoal) in Theme.lua,
-- the module and toolbar icons, and the time slot editor inside the 冒險單 /
-- 職工單 forms (a drop-down 日期, one HH:MM 開始時間 list, 預計長度) that
-- writes the form's draft only. Offline only (MANUAL §3uig has the in-game
-- screenshot steps). Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A = "0000-0000000A"
    local H = 3600

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    -- The game's local clock as the mock has it (tests/addon/mock.lua: date() is
    -- fixed to UTC+8), never the machine's zone (GF-UI-G2: CI runs in UTC).
    local function gameDate(f, t) return os.date("!" .. f, t + 8 * 3600) end
    -- A login at the game's local hh:mm today.
    local function loginAt(hh, mm)
        local base = 1763370000
        local d = gameDate("*t", base)
        local mid = base - (d.hour * 3600 + d.min * 60 + d.sec)
        return login({ now = mid + hh * 3600 + mm * 60 })
    end
    local function hhmm(t) return gameDate("%H:%M", t) end
    local function ticket(ns) return _G[ns.AdventureUI.TICKET_NAME] end
    local function worker(ns) return _G[ns.AdventureUI.WORKER_NAME] end
    local function texts(items)
        local out = {}
        for _, it in ipairs(items) do out[#out + 1] = it.text end
        return out
    end

    ---------------------------------------------------------------------------
    -- Palette and icons
    ---------------------------------------------------------------------------

    test("GF-UI-G palette: every colour in Theme.lua, opaque forms and lists", function()
        local ns = login()
        local C = ns.Theme.C
        local function is(c, hex, what)
            local want = ns.Theme.rgb(hex)
            for k = 1, 3 do ok(math.abs(c[k] - want[k]) < 0.002, what .. " " .. hex) end
        end
        is(C.bg, "232323", "windows"); is(C.main, "232323", "main window"); ok(C.main[4] > C.bg[4], "the main window is more opaque")
        is(C.side, "292724", "module list"); is(C.rowA, "282624", "row 1"); is(C.rowB, "302D29", "row 2")
        is(C.form, "302C28", "forms and lists"); eq(C.form[4], 1, "the form colour is opaque")
        is(C.selFill, "3A332A", "chosen fill"); is(C.selLine, "B9925F", "chosen frame")
        is(C.title, "CFB77E", "titles"); is(C.text, "E8DFD2", "text"); is(C.sub, "BEB4A4", "secondary text")
        is(C.line, "4A4540", "lines")
        local U = ns.AdventureUI
        U.openTicket()
        local f = ticket(ns)
        ok(f.gfForm and f.gfOpaque._color[4] == 1, "the 冒險單 form is opaque")
        U.openWorker()
        ok(worker(ns).gfForm and worker(ns).gfOpaque._color[4] == 1, "the 職工單 form is opaque")
        -- A chosen theme button: the olive fill and the brass frame.
        local b = ns.Theme.button(UIParent, "x", 80)
        ns.Theme.setSelected(b, true)
        is(b.gfFill._color, "3A332A", "chosen fill on a button"); is(b.gfEdges.c, "B9925F", "chosen frame on a button")
        -- The module list is the side colour.
        ns.Framework.open()
        is(_G[ns.Framework.WINDOW_NAME].nav.bg._color, "292724", "the module list fill")
        eq(ns.Framework.NAV_ICON, 22, "module icons 22 px")
        eq(_G[ns.Framework.WINDOW_NAME].gfOpaque._color[4], C.main[4], "the main window uses the more opaque fill")
    end)

    test("GF-UI-G icons: module list, toolbar, one clock for 現在 and a set time, three different art", function()
        local ns = login()
        local F, G = ns.Framework, ns.GameIcons
        eq(F.ENTRY_ICON.profile[1], "Interface\\Icons\\INV_Misc_Head_Orc_01", "職工檔案: one portrait (GF-UI-J: the orc)")
        eq(F.ENTRY_ICON.directory[1], "Interface\\Icons\\INV_BannerPVP_01", "職工名冊: the Horde standard (GF-UI-J)")
        eq(F.ENTRY_ICON.logistics[1], "Interface\\Icons\\INV_Box_01", "物資調度: a box")
        eq(F.ENTRY_ICON.adventure[1], "Interface\\Icons\\INV_Misc_Map_01", "冒險業務: a map")
        eq(F.ENTRY_ICON.handbook[1], "Interface\\Icons\\INV_Misc_Book_11", "冒險指南: a book")
        eq(F.ENTRY_ICON.settings[1], "Interface\\Icons\\INV_Misc_Gear_01", "事務設定: a gear")
        local cal = G.pick("calendar")[1]
        ok(cal ~= F.ENTRY_ICON.handbook[1] and cal ~= F.ENTRY_ICON.directory[1], "行事曆 is neither the book nor the group")
        ok(not cal:find("Book", 1, true), "行事曆 is no book")
        eq(G.pick("rules")[1], "Interface\\FriendsFrame\\InformationIcon", "規則: the small i")
        eq(G.pick("worker")[1], "Interface\\Icons\\INV_Scroll_05", "＋職工單 / 我的職工單: the notice scroll (GF-UI-J)")
        local U = ns.AdventureUI
        local now = plain(U.slotText({ now = true })):gsub("%s", "")
        ok(U.slotText({ now = true }):find("PocketWatch_01", 1, true), "現在: the clock")
        ok(U.slotText({ s = ns.Share.serverNow() + 26 * H }):find("PocketWatch_01", 1, true), "a set time: the same clock")
        ok(U.slotText({ s = ns.Share.serverNow() + 5 * 86400 }):find("PocketWatch_01", 1, true), "a later day: the same clock")
        eq(now, "現在", "現在 keeps its word")
        -- The toolbar uses those keys (20 px).
        ns.Framework.open(); ns.Framework.select("adventure")
        ok(U.workerButton:GetText():find("INV_Scroll_05", 1, true), "＋職工單 icon")
        ok(U.calendarButton:GetText():find("UI-Calendar-Button", 1, true), "行事曆 icon")
        ok(U.rulesButton:GetText():find("InformationIcon", 1, true), "規則 icon")
        ok(U.newButton:GetText():find("INV_Misc_Map_01", 1, true), "＋冒險單: the map")
    end)

    ---------------------------------------------------------------------------
    -- The drop-down widget
    ---------------------------------------------------------------------------

    test("GF-UI-G drop-down: opaque list, scrolls, disabled items stay, opens upwards near the bottom", function()
        local ns = login()
        local W = ns.Widgets
        local picked
        local dd = W.dropdown(UIParent, 100, function(v) picked = v end)
        local items = {}
        for i = 1, 20 do items[#items + 1] = { value = i, text = "第" .. i, disabled = i == 3 or nil } end
        dd.setItems(items); dd.setValue(12)
        eq(dd:GetText(), "第12", "the button shows the value")
        dd.open()
        ok(dd.isOpen(), "open")
        ok(dd.list.gfForm and dd.list.gfOpaque._color[4] == 1, "the list is the opaque form colour")
        eq(#dd.shownTexts(), W.DROP_ROWS, "at most DROP_ROWS lines")
        local seen = false
        for _, t in ipairs(dd.shownTexts()) do if t == "第12" then seen = true end end
        ok(seen, "the chosen item is in view")
        ok(dd.list.up:IsShown() and dd.list.down:IsShown(), "▲ ▼ on a long list")
        dd.scroll(-100); eq(dd.shownTexts()[1], "第1", "scrolled to the top")
        eq(dd.choose(3), false, "a disabled item cannot be picked")
        ok(dd.isOpen() and picked == nil, "nothing changed")
        ok(dd.choose(4), "a pick"); eq(picked, 4, "onChoose"); ok(not dd.isOpen(), "closes after a pick")
        -- ESC closes it.
        dd.open(); ns.escape(); ok(not dd.isOpen(), "ESC closes the list")
        -- A click outside: the blocker closes it.
        dd.open(); ok(ns.clickBlocker():IsShown(), "click-outside blocker up"); wow.click(ns.clickBlocker())
        ok(not dd.isOpen(), "a click outside closes the list")
        -- Near the bottom of the screen it opens upwards.
        dd.GetBottom = function() return 40 end
        dd.GetTop = function() return 70 end
        UIParent.GetTop = function() return 768 end
        dd.open()
        ok(dd.openUp, "opens upwards near the bottom")
        local p = dd.list._points[1]
        eq(p[1], "BOTTOMLEFT", "anchored above the button")
        dd.close()
        dd.GetBottom = function() return 500 end
        dd.GetTop = function() return 530 end
        dd.open(); ok(not dd.openUp, "below when there is room"); dd.close()
        UIParent.GetTop = nil
    end)

    ---------------------------------------------------------------------------
    -- The slot editor
    ---------------------------------------------------------------------------

    test("GF-UI-G slot editor: a chip opens it inside the form, 現在 folds 日期 and 時間, one at a time", function()
        local ns = loginAt(14, 7)
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = ticket(ns)
        local y3 = f.rowY[3]
        ok(not (f.slotEdit and f.slotEdit:IsShown()), "folded at first")
        wow.click(f.slotChips[1])
        local e = f.slotEdit
        ok(e and e:IsShown(), "the chip opens the editor in the form")
        eq(e._parent, f, "inside the form")
        ok(f.rowY[3] < y3, "the rows below make room")
        ok(e.nowButton.gfSelected and not e.atButton.gfSelected, "現在 chosen")
        ok(not e.day:IsShown() and not e.time:IsShown(), "現在: no 日期, no 時間")
        ok(e.len:IsShown(), "長度 stays")
        ok(f.slotChips[1].gfSelected, "the chip being edited is chosen")
        ok(not U.picker() or not U.picker():IsShown(), "no separate picker window")
        wow.click(e.atButton)
        ok(e.day:IsShown() and e.time:IsShown(), "指定時間: 日期 and 時間")
        eq(d.slots[1].now, false, "the draft slot has a time")
        eq(e.day.value, 0, "today")
        eq(e.time:GetText(), "14:15", "the next quarter")
        -- A second click on the same chip folds it.
        wow.click(f.slotChips[1])
        ok(not e:IsShown(), "folded again"); eq(f.rowY[3], y3, "the rows move back")
        ok(plain(f.slotChips[1]:GetText()):find("14:15", 1, true), "the chip shows the time")
    end)

    test("GF-UI-G slot editor: today lists only the times still ahead, one HH:MM list every 15 minutes", function()
        local ns = loginAt(14, 7)
        local U = ns.AdventureUI
        local today = texts(U.slotTimeOptions(0))
        eq(today[1], "14:15", "today starts at the next quarter")
        eq(today[#today], "23:45", "until 23:45")
        eq(#today, 39, "14:15 .. 23:45")
        local tomorrow = texts(U.slotTimeOptions(1))
        eq(#tomorrow, 96, "tomorrow: the whole day")
        eq(tomorrow[1], "00:00", "from 00:00"); eq(tomorrow[2], "00:15", "15 minutes apart"); eq(tomorrow[96], "23:45", "to 23:45")
        local days = U.slotDayOptions()
        ok(days[1].text:find("^今天 %d+/%d+$"), "今天 with the date: " .. days[1].text)
        ok(days[2].text:find("^明天 %d+/%d+$"), "明天 with the date: " .. days[2].text)
        ok(days[3].text:find("（.-）$"), "later days with the weekday")
        eq(#days, ns.Adventure.FUTURE_DAYS + 1, "today to FUTURE_DAYS")
        local tm = gameDate("*t", ns.Share.serverNow() + 86400)
        eq(days[2].text, "明天 " .. tm.month .. "/" .. tm.day, "明天 is the real next day")
        ok(not days[1].disabled, "today is open at 14:07")
    end)

    test("GF-UI-G slot editor: 23:50 — today is closed, tomorrow from 00:00, a length past midnight", function()
        local ns = loginAt(23, 50)
        local U = ns.AdventureUI
        local days = U.slotDayOptions()
        ok(days[1].disabled, "no quarter left today: 今天 cannot be picked")
        eq(#U.slotTimeOptions(0), 0, "no time today")
        local d = U.openTicket()
        local f = ticket(ns)
        U.openSlotEditor(f, 1)
        local e = f.slotEdit
        wow.click(e.atButton)
        eq(e.day.value, 1, "the next quarter is tomorrow")
        eq(e.time:GetText(), "00:00", "00:00")
        eq(e.day.choose(0), false, "today stays closed")
        -- 23:00 tomorrow for 2 hours: the chip says 隔天.
        e.time.choose(23 * 60)
        e.len.choose(2)
        local chip = plain(f.slotChips[1]:GetText())
        ok(chip:find("明天", 1, true) and chip:find("23:00～01:00（隔天）", 1, true), "past midnight: " .. chip)
        eq(d.slots[1].dur, 2, "two hours")
    end)

    test("GF-UI-G slot editor: 日期, 時間 and the chip read one slot value (no 今天 next to 明天)", function()
        local ns = loginAt(10, 0)
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = ticket(ns)
        U.openSlotEditor(f, 1)
        local e = f.slotEdit
        wow.click(e.atButton)
        e.time.choose(20 * 60)
        e.day.choose(1)
        local sl = d.slots[1]
        eq(hhmm(sl.start), "20:00", "the time kept when the day changes")
        eq(U.dayOffset(sl.start), 1, "tomorrow")
        eq(e.day.value, 1, "日期 field = the slot")
        ok(e.day:GetText():find("^明天"), "the field says 明天")
        eq(e.time:GetText(), "20:00", "時間 field = the slot")
        local chip = plain(f.slotChips[1]:GetText())
        ok(chip:find("明天 20:00", 1, true), "the chip says 明天 20:00: " .. chip)
        -- Back to today: the time is still ahead, so it stays.
        e.day.choose(0)
        eq(U.dayOffset(d.slots[1].start), 0, "today")
        ok(e.day:GetText():find("^今天"), "field 今天")
        ok(plain(f.slotChips[1]:GetText()):find("20:00", 1, true) and not plain(f.slotChips[1]:GetText()):find("明天", 1, true),
            "the chip follows (today: no 明天)")
        -- A time that has passed today moves to the next quarter (never into the past).
        U.slotSetMinute(d.slots[1], 8 * 60); f.slotRedraw()
        eq(hhmm(d.slots[1].start), "10:15", "past times clamp to the next quarter")
        eq(e.time:GetText(), "10:15", "the field shows the same")
    end)

    test("GF-UI-G slot editor: edit the second slot, add up to 5, remove, length optional", function()
        local ns = loginAt(9, 0)
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = ticket(ns)
        wow.click(f.addSlot)
        eq(#d.slots, 2, "＋時段 adds a slot")
        eq(f.slotEditIndex, 2, "and opens its editor")
        ok(f.slotChips[2].gfSelected and not f.slotChips[1].gfSelected, "the second chip is the chosen one")
        local e = f.slotEdit
        ok(e.remove:IsShown(), "移除 with two slots")
        eq(e.day.value, 1, "the new slot: tomorrow (as before)")
        eq(e.time:GetText(), "20:00", "20:00")
        e.time.choose(21 * 60 + 30)
        eq(hhmm(d.slots[2].start), "21:30", "the second slot changed")
        ok(d.slots[1].now, "the first slot untouched")
        -- Length: 不填 by default, then 3 h, then 不填 again.
        eq(e.len:GetText(), "不填", "length optional")
        e.len.choose(3); eq(d.slots[2].dur, 3, "3 hours")
        e.len.choose(0); eq(d.slots[2].dur, nil, "不填 again")
        -- Click chip 1: the editor moves there (one at a time).
        wow.click(f.slotChips[1])
        eq(f.slotEditIndex, 1, "one slot at a time")
        ok(e.nowButton.gfSelected, "slot 1 is 現在")
        for _ = 3, 5 do wow.click(f.addSlot) end
        eq(#d.slots, 5, "five"); ok(not f.addSlot:IsShown(), "no ＋時段 at 5")
        U.openSlotEditor(f, 3)
        wow.click(e.remove)
        eq(#d.slots, 4, "removed"); ok(not e:IsShown(), "the editor folds"); ok(f.addSlot:IsShown(), "＋時段 again")
        -- The last one cannot be removed.
        while #d.slots > 1 do U.openSlotEditor(f, #d.slots); wow.click(e.remove) end
        U.openSlotEditor(f, 1)
        ok(not e.remove:IsShown(), "no 移除 on the only slot")
    end)

    test("GF-UI-G slot editor: the draft only — 開單 / 儲存 saves, upload-api v1.6 times[] unchanged", function()
        local ns = loginAt(9, 0)
        local U, Adv = ns.AdventureUI, ns.Adventure
        local d = U.openTicket()
        d.dungeon = "smg"
        local f = ticket(ns)
        wow.click(f.addSlot)
        f.slotEdit.time.choose(20 * 60)
        f.slotEdit.len.choose(2)
        eq(#Adv.listOf(A, "T"), 0, "editing saves nothing")
        local id = U.submitTicket()
        ok(id, "開單 saves")
        local v = Adv.get(id)
        eq(#v.slots, 2, "two slots"); ok(v.slots[1].now, "現在 first")
        eq(hhmm(v.slots[2].s), "20:00", "20:00"); eq(v.slots[2].d, 2 * H, "2 hours")
        local entry = Adv.listOf(A, "T")[1]
        local up = Adv.ticketUpload(entry, v)
        eq(#up.times, 2, "times[]")
        local t2 = up.times[2]
        eq(t2.mode, "at", "mode"); eq(t2.from, v.slots[2].s, "from"); eq(t2.length, 2 * H, "length"); eq(t2.to, t2.from + 2 * H, "to")
        ok(t2.id ~= nil and up.times[1].mode == "now", "ids and 現在")
        local keys = {}
        for k in pairs(t2) do keys[#keys + 1] = k end
        table.sort(keys)
        eq(table.concat(keys, ","), "from,id,length,mode,to", "the same five fields")
        -- Editing: change the draft, nothing is stored until 儲存.
        local d2 = U.openTicket(v)
        U.openSlotEditor(f, 2)
        f.slotEdit.time.choose(22 * 60)
        eq(hhmm(Adv.get(id).slots[2].s), "20:00", "the stored ticket is unchanged while editing")
        U.submitTicket(d2)
        eq(hhmm(Adv.get(id).slots[2].s), "22:00", "儲存 stores it")
        eq(Adv.get(id).slots[2].id, v.slots[2].id, "the slot keeps its id")
    end)

    test("GF-UI-G slot editor: an older slot fills the fields back (time off the quarter, 2 days ahead)", function()
        local ns = loginAt(9, 0)
        local U, Adv = ns.AdventureUI, ns.Adventure
        local t0 = U.dayStart(2) + 20 * H + 10 * 60 -- the day after tomorrow 20:10, 90 minutes
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", tags = 0, note = "", mode = "a",
            quests = {}, slots = { { now = true }, { s = t0, d = 90 * 60 } } })
        ok(id, "an older ticket")
        U.openTicket(Adv.get(id))
        local f = ticket(ns)
        U.openSlotEditor(f, 2)
        local e = f.slotEdit
        eq(e.day.value, 2, "日期: the day after tomorrow")
        local md = gameDate("*t", t0)
        ok(e.day:GetText():find("^" .. md.month .. "/" .. md.day .. "（"), "日期 text: " .. e.day:GetText())
        eq(e.time:GetText(), "20:10", "時間 keeps 20:10 (listed although off the quarter)")
        eq(e.len:GetText(), "2 小時", "90 minutes rounds to 2 hours (as before)")
        ok(plain(f.slotChips[2]:GetText()):find("20:10", 1, true), "the chip shows 20:10 too")
    end)

    test("GF-UI-G slot editor: the 職工單 form uses the same editor; 登記 saves", function()
        local ns = loginAt(9, 0)
        local U, Adv = ns.AdventureUI, ns.Adventure
        local wd = U.openWorker()
        wd.dungeons = { "smg" }
        local f = worker(ns)
        wow.click(f.slotChips[1])
        local e = f.slotEdit
        ok(e and e:IsShown(), "the editor in the 職工單 form")
        ok(e.day.gfWidget == "dropdown" and e.time.gfWidget == "dropdown" and e.nowButton and e.atButton, "the shared slot editor")
        wow.click(e.atButton)
        e.day.choose(1); e.time.choose(19 * 60 + 45); e.len.choose(1)
        eq(Adv.myWorker(), nil, "nothing stored before 登記")
        U.saveWorker()
        local w = Adv.myWorker()
        ok(w and #w.slots == 1, "登記 stores it")
        eq(hhmm(w.slots[1].s), "19:45", "19:45"); eq(w.slots[1].d, H, "1 hour")
        eq(U.dayOffset(w.slots[1].s), 1, "tomorrow")
    end)

    test("GF-UI-G rows: warm stripes, a light hover, the chosen frame, 密語 / 申請 as one-width text buttons", function()
        local ns = login()
        local U = ns.AdventureUI
        local th = ns.Theme
        local tex = UIParent:CreateTexture()
        th.stripe(tex, 1); eq(tex._color[1], th.C.rowA[1], "row 1 colour")
        th.stripe(tex, 2); eq(tex._color[1], th.C.rowB[1], "row 2 colour")
        local b = U.iconButton(UIParent, ns.ROW_ICON, "apply", "申請", function() end, "申請")
        b.tip = "申請"
        U.textStyle(b, true)
        ok(not b.tex:IsShown(), "no icon"); eq(b.gfTextText:GetText(), "申請", "the word in the frame")
        eq(b.gfWidth, U.ACTION_W, "one width"); ok(b.gfTextEdges[1]:IsShown(), "a thin frame")
        U.textStyle(b, false)
        eq(b.gfWidth, ns.ROW_ICON, "back to an icon")
        ok(U.TEXT_ACTIONS.whisper and U.TEXT_ACTIONS.apply and U.TEXT_ACTIONS.lfgApply, "密語, 申請 (both kinds)")
    end)
end
