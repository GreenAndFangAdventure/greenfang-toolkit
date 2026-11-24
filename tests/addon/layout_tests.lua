-- GF-002-F (0.12.4): the whole-UI pass after the owner's 0.12.3 screenshots
-- (docs/research/GF-002-F_ui-review.md). Nothing overlaps (the destination
-- picker included), a click outside closes menus, 今天 reaches past
-- midnight, the future has the year, my own worker ticket is listed, and
-- the minimum text, icon and row sizes. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local B = "0000-0000000B"

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function visible(o)
        local f = o
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function fontSize(fs)
        local f = fs._font
        local obj = type(f) == "string" and rawget(_G, f) or f
        if type(obj) == "table" and obj._fontSize then return obj._fontSize end
        if tostring(f):find("Large") then return 18 end
        if tostring(f):find("Small") then return 10 end
        return 13
    end

    -- Rectangles inside a window (left, top, right, bottom; y grows downwards),
    -- from the anchors the toolkit uses. nil when an anchor is not understood.
    local function sizeOf(o)
        if o._kind == "FontString" then return wow.textWidth(o._text, o._font), fontSize(o) end
        return o._w or 0, o._h or 0
    end
    local function rectOf(o, win, depth)
        depth = depth or 0
        if depth > 4 or not o._points or not o._points[1] then return nil end
        local p = o._points[1]
        local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
        local w, h = sizeOf(o)
        if rel == win and point == "TOPLEFT" and relPoint == "TOPLEFT" then return x, -y, x + w, -y + h end
        if rel == win and point == relPoint and (point == "BOTTOMRIGHT" or point == "BOTTOMLEFT") then
            local W, H = win._w, win._h
            local bottom = H - y
            if point == "BOTTOMRIGHT" then return W + x - w, bottom - h, W + x, bottom end
            return x, bottom - h, x + w, bottom
        end
        if rel and rel ~= win and rel._points then
            local l, t, r, b = rectOf(rel, win, depth + 1)
            if not l then return nil end
            local cy = (t + b) / 2
            if point == "LEFT" and relPoint == "RIGHT" then return r + x, cy - h / 2 - y, r + x + w, cy + h / 2 - y end
            if point == "RIGHT" and relPoint == "LEFT" then return l + x - w, cy - h / 2 - y, l + x, cy + h / 2 - y end
            if point == "TOP" and relPoint == "BOTTOM" then
                local cx = (l + r) / 2
                return cx - w / 2 + x, b - y, cx + w / 2 + x, b - y + h
            end
        end
        return nil
    end
    -- Every shown widget of win that has a place: buttons, texts, edit boxes, its own textures.
    local function parts(win)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            -- GF-002-G: a button's name belongs to the button (a child FontString).
            local direct = o._parent == win
                or (o._kind == "FontString" and o._parent and o._parent._kind == "Button" and o._parent._parent == win
                    and o._parent.label == o)
            local kind = o._kind
            local wanted = (kind == "Button" or kind == "EditBox" or kind == "FontString" or kind == "CheckButton")
                or (kind == "Texture" and direct)
            if wanted and direct and visible(o) and (kind ~= "FontString" or plain(o._text) ~= "") then
                local l, t, r, b = rectOf(o, win)
                if l then out[#out + 1] = { o = o, l = l, t = t, r = r, b = b } end
            end
        end
        return out
    end
    local function name(o) return plain(o._text) ~= "" and plain(o._text) or (o.label and plain(o.label._text)) or o.tip or o._kind end
    local function overlaps(win)
        local list, out = parts(win), {}
        for i = 1, #list do
            for j = i + 1, #list do
                local a, b = list[i], list[j]
                if a.l < b.r - 1 and b.l < a.r - 1 and a.t < b.b - 1 and b.t < a.b - 1 then
                    out[#out + 1] = name(a.o) .. " × " .. name(b.o)
                end
            end
        end
        table.sort(out)
        return table.concat(out, " | "), #list
    end
    local function insideWindow(win)
        local out = {}
        for _, p in ipairs(parts(win)) do
            if p.l < 0 or p.t < 0 or p.r > win._w + 1 or p.b > win._h + 1 then out[#out + 1] = name(p.o) end
        end
        return table.concat(out, ",")
    end

    local function withData(ns)
        local t = ns.Share.serverNow()
        local w = "id=gbbb.1,cf=" .. "0000-0000000A" .. ",cr=" .. ns.Share.b36(t) .. ",rc=21w,it=27i,sk=4k,q=1,fe=0,st=o,sa=" .. ns.Share.b36(t)
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash(w), w)
        ns.Orders.place({ recipe = 2660, item = 2862, skill = 164, qty = 1 })
        local v = ns.Adventure.encodeList({ { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 31, md = "c", st = "o", sa = t } })
        ns.Adventure.ledger:offer(B, "T", t, ns.Share.hash(v), v)
        ns.Adventure.open({ dungeon = "sfk", leaderRole = "h" })
        wow.advance(30)
    end

    -- Set the local clock (UTC+8 in the mock) to hh:mm today.
    local function setClock(hh, mm)
        local now = wow.state.now
        local localNow = now + 8 * 3600
        local midnight = localNow - localNow % 86400
        wow.state.now = midnight + hh * 3600 + mm * 60 - 8 * 3600
    end

    test("GF-002-F no two parts of any window overlap, and all stay inside it", function()
        local ns = login()
        withData(ns)
        local A, O = ns.AdventureUI, ns.OrdersUI
        local checks = {}
        local function check(what, win)
            local text, n = overlaps(win)
            eq(text, "", what .. ": overlaps")
            eq(insideWindow(win), "", what .. ": inside the window")
            ok(n >= 5, what .. ": parts measured (" .. n .. ")")
        end
        A.openTicket()
        local tf = _G[A.TICKET_NAME]
        for _, m in ipairs({ "n", "t", "f" }) do A.pickTime(nil, m); check("ticket " .. m, tf) end
        A.draft().dungeon = "smg"; A.drawTicket(); check("ticket dungeon", tf)
        A.draft().dungeon = nil; A.draft().quests = { 216 }; A.drawTicket(); check("ticket quests", tf)
        local wd = A.openWorker()
        local wf = _G[A.WORKER_NAME]
        check("worker empty", wf)
        for _, id in ipairs({ "rfc", "wc", "dm", "sfk", "bfd", "stk", "smg" }) do A.toggleWorkerDungeon(id) end
        check("worker with 7 dungeons", wf)
        -- GF-002-G (owner's 22.png): 11 dungeons wrap onto a third line; 「＋地城」 and
        -- the rows below move down instead of running into 「任務」.
        for _, id in ipairs({ "gnr", "rfk", "brd", "lbrs" }) do A.toggleWorkerDungeon(id) end
        check("worker with 11 dungeons", wf)
        ok(wf.quests.flowY == nil, "任務 is placed by row, not in the chips")
        for _, id in ipairs({ "ubrs", "dme", "dmw", "dmn", "strat", "scholo", "ul", "zf", "mar", "st" }) do A.toggleWorkerDungeon(id) end
        check("worker with 21 dungeons", wf)
        O.openOrder({ recipe = 2660, skill = 164, crafters = {} }); check("order", _G[O.POPUP_NAME])
        O.editFee({ skill = 164 }); check("fee", _G[O.FEE_NAME])
        O.openPaste(); check("paste", _G[O.PASTE_NAME])
        O.openServices(); check("services", _G[O.SERVICES_NAME])
        O.openPicker()
        local pk = _G[O.PICKER_NAME]
        eq((overlaps(pk)), "", "picker: overlaps")
        -- The destination picker: the ticket window steps aside (nothing covered), cells apart.
        A.openTicket()
        local grid = A.pickDestination(tf.dest)
        ok(grid:IsShown() and not tf:IsShown(), "the ticket window steps aside while the picker is open")
        check("destination picker", grid)
        grid:Hide()
        ok(tf:IsShown(), "and comes back")
        A.openWorker()
        grid = A.pickWorkerDungeons(wf.addDungeon)
        ok(not wf:IsShown(), "the worker window steps aside too")
        check("dungeon picker (several)", grid)
        grid:Hide()
        ok(wf:IsShown(), "worker window back")
    end)

    test("GF-002-F text at least 16 px, icons 32 px (rows 28), dungeon art 48 px, rows 36 px", function()
        local ns = login()
        withData(ns)
        local A, O = ns.AdventureUI, ns.OrdersUI
        eq(fontSize({ _font = ns.LABEL_FONT }), 16, "label font")
        eq(fontSize({ _font = ns.FIELD_FONT }), 16, "field font")
        local function small(win)
            local out = {}
            for _, o in ipairs(wow.allObjects()) do
                if o._parent == win and o._kind == "FontString" and visible(o) and plain(o._text) ~= "" and fontSize(o) < 16 then
                    out[#out + 1] = plain(o._text) .. "@" .. tostring(fontSize(o))
                end
                if o._parent == win and o._kind == "Button" and visible(o) and o.gfWidth and o.tex and o.gfWidth < 32 then
                    out[#out + 1] = "icon " .. name(o) .. "@" .. o.gfWidth
                end
            end
            return table.concat(out, ",")
        end
        A.openTicket(); A.pickTime(nil, "f")
        eq(small(_G[A.TICKET_NAME]), "", "ticket window")
        A.openWorker(); A.toggleWorkerDungeon("smg")
        eq(small(_G[A.WORKER_NAME]), "", "worker window")
        O.openOrder({ recipe = 2660, skill = 164, crafters = {} }); eq(small(_G[O.POPUP_NAME]), "", "order window")
        O.openServices(); eq(small(_G[O.SERVICES_NAME]), "", "services")
        local grid = A.pickWorkerDungeons(UIParent)
        for _, b in ipairs(grid.buttons) do
            eq(b.gfWidth, 48, "dungeon art 48 px")
            ok(fontSize(b.label) >= 16 and fontSize(b.level) >= 16, "names and levels 16 px")
        end
        grid:Hide()
        ns.Framework.open("adventure")
        for _, r in ipairs(A.rowFrames()) do
            if r:IsShown() then
                ok(r._h >= 36, "adventure row 36 px")
                for _, b in ipairs(r.buttons) do ok(b.gfWidth >= 28, "row button 28 px") end
                ok(fontSize(r.name) >= 16, "row text 16 px")
            end
        end
        ns.Framework.open("orders")
        for _, r in ipairs(O.rowFrames()) do if r:IsShown() then ok(r._h >= 36, "order row 36 px"); ok(r.item.gfWidth >= 32, "item 32 px") end end
        ns.Framework.open("recipes")
        for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() then ok(r._h >= 36, "recipe row 36 px") end end
    end)

    test("GF-002-F a click outside closes menus, lists, the time menus and the destination picker", function()
        local ns = login()
        withData(ns)
        local A, O = ns.AdventureUI, ns.OrdersUI
        ns.Framework.open("adventure")
        A.openTicket()
        local tf = _G[A.TICKET_NAME]
        A.pickTime(nil, "t")
        local menu = A.pickStart(tf.startButton)
        local blocker = ns.clickBlocker()
        ok(menu:IsShown() and blocker and blocker:IsShown(), "time menu open, the click-outside layer under it")
        eq(blocker._strata, "TOOLTIP", "above the windows, under the menu (level 1)")
        wow.click(blocker)
        ok(not menu:IsShown(), "a click outside: time menu closed")
        ok(not blocker:IsShown(), "and the layer is gone")
        ok(tf:IsShown(), "the ticket window stays")
        -- The destination picker.
        local grid = A.pickDestination(tf.dest)
        ok(grid:IsShown() and blocker:IsShown(), "picker open")
        wow.click(blocker)
        ok(not grid:IsShown() and tf:IsShown(), "a click outside: picker closed, the ticket window back")
        -- A drop-down list on the recipe page and a right-click menu.
        ns.Framework.open("recipes")
        wow.click(ns.Recipes.feeChoice)
        ok(ns.Recipes.feeChoice.menu:IsShown(), "list open")
        wow.click(ns.clickBlocker())
        ok(not ns.Recipes.feeChoice.menu:IsShown(), "list closed")
        wow.click(ns.Recipes.skillChoice)
        ok(ns.Recipes.skillChoice.menu:IsShown(), "check list open")
        wow.click(ns.clickBlocker())
        ok(not ns.Recipes.skillChoice.menu:IsShown(), "check list closed")
        local m = ns.showMenu(UIParent, { { text = "測試", fn = function() end } })
        wow.click(ns.clickBlocker())
        ok(not m:IsShown(), "right-click menu closed")
        ok(ns.Framework.isShown(), "the main window stays")
    end)

    test("GF-002-F 今天 reaches past midnight (23:00 for 3 hours ends 02:00 the next day)", function()
        local ns = login()
        setClock(22, 50)
        local A = ns.AdventureUI
        local d = A.openTicket()
        d.dungeon = "smg"
        A.pickTime(nil, "t")
        local sl = d.slots[1]
        eq(A.clock(sl.start), "23:00", "the next quarter")
        -- GF-002-G: the picker has today's hours left and all of tomorrow's.
        local pk = A.pickStart(_G[A.TICKET_NAME].startButton)
        local today, tomorrow = 0, 0
        for h = 0, 23 do
            if pk.hours[1][h]:IsShown() then today = today + 1 end
            if pk.hours[2][h]:IsShown() then tomorrow = tomorrow + 1 end
        end
        eq(today, 2, "today: 22 and 23 left")
        eq(tomorrow, 24, "tomorrow: every hour (past midnight)")
        eq(pk.dayLabels[2]:GetText(), "明天", "明天")
        wow.click(pk.lens[4]) -- 3 小時
        pk:Hide()
        eq(sl.dur, 3, "3 hours")
        local finish = sl.start + sl.dur * 3600
        eq(A.clock(finish), "02:00", "ends 02:00")
        ok(plain(_G[A.TICKET_NAME].startButton:GetText()):find("23:00～02:00（隔天）", 1, true), "the chip: 23:00～02:00（隔天）")
        local id = A.submitTicket()
        ok(id, "opened")
        local v = ns.Adventure.get(id)
        ok(plain(A.timeText(v)):find("（隔天）", 1, true), "the row says it ends the next day")
        -- A start after midnight (明天 00:30), picked in the picker.
        local d2 = A.openTicket()
        d2.dungeon = "smg"
        pk = A.pickStart(_G[A.TICKET_NAME].startButton)
        wow.click(pk.hours[2][0]); wow.click(pk.minutes[3])
        eq(A.startText(d2.slots[1].start), "明天 00:30", "明天 00:30")
        local id2 = A.submitTicket()
        ok(id2, "opened with a start after midnight")
        ok(plain(A.timeText(ns.Adventure.get(id2))):find("明天 00:30", 1, true), "shown as 明天 00:30")
        -- Worker time slots: the same picker (with 長度).
        A.openWorker()
        local sp = A.pickWorkerSlots(UIParent)
        wow.click(sp.hours[2][1])
        wow.click(sp.lens[3]) -- 2 小時
        local wsl = A.workerDraft().slots[1]
        ok(not wsl.now and A.startText(wsl.start) == "明天 01:00", "worker slot 明天 01:00")
        eq(wsl.dur, 2, "2 hours")
    end)

    test("GF-002-F 之後: dates with the year, a proper icon", function()
        local ns = login()
        local A = ns.AdventureUI
        local d = A.openTicket()
        d.dungeon = "smg"
        A.pickTime(nil, "f")
        local f = _G[A.TICKET_NAME]
        ok(plain(f.startButton:GetText()):match("%d%d%d%d/%d%d/%d%d"), "date with the year: " .. plain(f.startButton:GetText()))
        local menu = A.pickDay(f.startButton)
        ok(plain(menu.items[2]:GetText()):match("^%d%d%d%d/%d%d/%d%d"), "the date menu has the year")
        menu:Hide()
        local id = A.submitTicket()
        local text = A.timeText(ns.Adventure.get(id))
        ok(plain(text):match("%d%d%d%d/%d%d/%d%d"), "the row has the year")
        ok(text:find("INV_Misc_Book_09", 1, true), "the 之後 icon is a whole icon (no calendar box)")
        eq(ns.GameIcons.ART.future[1].box, nil, "no texture box")
    end)

    test("GF-002-F my own worker ticket is listed after 登記, can be edited and removed", function()
        local ns = login()
        local A = ns.AdventureUI
        ns.Framework.open("adventure")
        local function mineRow()
            for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.mine then return r end end
        end
        eq(mineRow(), nil, "nothing before")
        local d = A.openWorker()
        A.toggleWorkerDungeon("smg"); A.toggleWorkerDungeon("sfk")
        wow.click(_G[A.WORKER_NAME].save)
        local row = mineRow()
        ok(row, "my worker ticket is on the page")
        local heads = {}
        for _, r in ipairs(A.rowFrames()) do if r:IsShown() and r.head:IsShown() then heads[#heads + 1] = plain(r.head:GetText()) end end
        ok(table.concat(heads, ","):find("我的職工單", 1, true), "under 我的職工單")
        ok(plain(row.name:GetText()):find("墓地", 1, true) and plain(row.name:GetText()):find("影牙", 1, true), "its dungeons")
        ok(plain(row.time:GetText()):find("現在", 1, true), "its time")
        eq(row.buttons[1].label._text .. "," .. row.buttons[2].label._text, "編輯,移除", "edit and remove")
        wow.click(row.buttons[1])
        local wf = _G[A.WORKER_NAME]
        ok(wf:IsShown(), "編輯 opens the worker window")
        eq(#A.workerDraft().dungeons, 2, "with what was registered")
        ok(plain(wf.TitleText._text):find("已登記", 1, true), "the title says it is registered")
        ok(plain(wf.save:GetText()):find("更新", 1, true), "and the button says 更新")
        -- The chosen dungeons are listed one by one, big, with names; a click removes one.
        local chips = {}
        for _, c in ipairs(wf.chips) do if c:IsShown() then chips[#chips + 1] = c.label._text end end
        eq(table.concat(chips, ","), "墓地,影牙", "chosen dungeons with names")
        eq(wf.chips[1].gfWidth, 32, "32 px")
        wow.click(wf.chips[1])
        eq(#A.workerDraft().dungeons, 1, "a click removes it")
        wow.click(wf.save)
        row = mineRow()
        ok(plain(row.name:GetText()):find("影牙", 1, true) and not plain(row.name:GetText()):find("墓地", 1, true), "updated on the page")
        wow.click(row.buttons[2])
        eq(mineRow(), nil, "移除: gone")
        eq(ns.Adventure.myWorker(), nil, "and removed")
    end)

    test("GF-002-F chosen and not chosen are told apart at a glance; levels on the picker", function()
        local ns = login()
        local A = ns.AdventureUI
        A.openWorker()
        local wf = _G[A.WORKER_NAME]
        local main = A.workerDraft().main
        for _, r in ipairs(ns.Adventure.ROLES) do
            local b = wf.mainRoles[r]
            eq(b.sel._shown, r == main, "glow only on the chosen role " .. r)
            eq(b.dimmed, r ~= main, "a little darker when not chosen " .. r)
        end
        local grid = A.pickWorkerDungeons(wf.addDungeon)
        local smg
        for _, b in ipairs(grid.buttons) do if b.dungeon == "smg" then smg = b end end
        eq(plain(smg.level._text), "26-36", "suggested levels under the icon")
        eq(smg.tip, nil, "no tooltip over the picker")
        wow.click(smg)
        ok(smg.sel._shown and smg.badge._shown, "chosen: gold frame and a tick")
        local other = grid.buttons[1]
        ok(not other.sel._shown, "others: no frame")
        -- Level colours on the text: white fits, red too high.
        wow.state.player.level = 10
        grid:Hide()
        grid = A.pickWorkerDungeons(wf.addDungeon)
        for _, b in ipairs(grid.buttons) do
            if b.dungeon == "smg" then eq(table.concat(b.levelColor, ","), "1,0.3,0.3", "too high: red") end
        end
    end)

    test("GF-002-F 人數: each role with its own ＋ －; one number for quests", function()
        local ns = login()
        local A = ns.AdventureUI
        local d = A.openTicket()
        local f = _G[A.TICKET_NAME]
        d.dungeon = "smg"; A.drawTicket()
        eq(plain(f.roleGroups.t.text._text) .. "," .. plain(f.roleGroups.h.text._text) .. "," .. plain(f.roleGroups.d.text._text), "坦 1,補 1,輸出 3", "per role")
        ok(not f.roleGroups.any.text:IsShown(), "no single number for a dungeon")
        wow.click(f.roleGroups.d.minus)
        eq(d.roles.d, 2, "－")
        wow.click(f.roleGroups.t.plus)
        eq(d.roles.t, 2, "＋")
        d.dungeon = nil; d.quests = { 216 }; A.drawTicket()
        ok(f.roleGroups.any.text:IsShown() and not f.roleGroups.t.text:IsShown(), "quests: one number")
        wow.click(f.roleGroups.any.minus)
        eq(d.size, 4, "quest size －")
        eq(f.roleButton, nil, "the old 調整 button is gone")
    end)

    test("GF-002-H nothing overlaps with 5 slots (ticket, worker), in the picker's 長度 row, the slot chooser and the calendar", function()
        local ns = login()
        withData(ns)
        local A = ns.AdventureUI
        local function check(what, win, min)
            local text, n = overlaps(win)
            eq(text, "", what .. ": overlaps")
            eq(insideWindow(win), "", what .. ": inside the window")
            ok(n >= (min or 5), what .. ": parts measured (" .. n .. ")")
        end
        local d = A.openTicket()
        d.dungeon = "smg"
        local tf = _G[A.TICKET_NAME]
        local t = ns.Share.serverNow()
        d.slots = { { now = true, dur = 2 } }
        for k = 1, 4 do d.slots[#d.slots + 1] = { start = A.dayStart(2 + k) + 23 * 3600, dur = 3, dayOff = 2 + k } end
        A.drawTicket()
        check("ticket with 5 slots (two lines of chips)", tf)
        d.slots = { { now = true } }; A.drawTicket(); check("ticket with 1 slot", tf)
        local pk = A.pickStart(tf.startButton)
        check("the picker with 長度", pk, 20)
        pk:Hide()
        A.openWorker()
        local wf = _G[A.WORKER_NAME]
        for _, id in ipairs({ "rfc", "wc", "dm", "sfk", "bfd", "stk", "smg", "gnr", "rfk", "brd", "lbrs" }) do A.toggleWorkerDungeon(id) end
        local wd = A.workerDraft()
        for k = 1, 4 do wd.slots[#wd.slots + 1] = { start = A.dayStart(2 + k) + 20 * 3600, dur = 2, dayOff = 2 + k } end
        A.drawWorker()
        check("worker with 11 dungeons and 5 slots", wf)
        local ch = A.slotChooser(UIParent, { title = "定案", multi = false, selected = { 2 }, counts = { [2] = { t = 1, h = 2, d = 3, total = 6 } },
            slots = { { id = 1, now = true }, { id = 2, s = A.dayStart(3) + 23 * 3600, d = 3 * 3600 }, { id = 3, s = t + 86400 },
                { id = 4, s = A.dayStart(10) + 20 * 3600 }, { id = 5, s = A.dayStart(12) + 21 * 3600, d = 5 * 3600 } },
            onDone = function() end })
        check("the slot chooser", ch, 8)
        ch:Hide()
        local f = A.openCalendar()
        check("the calendar", f, 10)
    end)
end
