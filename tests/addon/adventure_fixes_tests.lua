-- GF-002-J (0.14.1): the owner's in-game fixes for the adventure page (LOG #210)
-- and spec GF-002 v1.2b §17.7: 已結束 tab, 刪除 and 清除, round role icons, an X
-- on every picker, the date steps, quest pages, the column grid, cropped icons,
-- zone-first quest tickets, zone matching and the 區域 filter. Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local A, B, C, D = "0000-0000000A", "0000-0000000B", "0000-0000000C", "0000-0000000D"
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
    local acts, lastAt = {}, {}
    local function apply(ns, author, id, t, role)
        if acts.ns ~= ns then acts, lastAt = { ns = ns }, {} end
        local list = acts[author] or {}
        acts[author] = list
        list[#list + 1] = { id = id, ac = "ap", at = t, ap = t, ak = "ap", ro = role, rb = "" }
        local at = math.max(t, (lastAt[author] or 0) + 1)
        lastAt[author] = at
        return offer(ns, author, "A", list, at)
    end
    local function eachRow(U, fn)
        local sc = U.scrollFrame()
        local seen = {}
        for k = 0, #U.shownRows() do
            sc:SetVerticalScroll(k * U.ROW_HEIGHT)
            for _, r in ipairs(U.rowFrames()) do
                if r:IsShown() then
                    local key = (r.view and r.view.id) or (r.mine and "mine") or r.worker or (r.head:IsShown() and r.head:GetText()) or tostring(r)
                    if not seen[key] then seen[key] = true; fn(r) end
                end
            end
        end
        sc:SetVerticalScroll(0)
    end
    local function rowOf(U, id)
        local found
        eachRow(U, function(r) if r.view and r.view.id == id then found = { view = r.view, badge = plain(r.badge.text._text),
            delete = r.delete:IsShown(), deleteX = r.delete._points[1][4], buttons = r.buttons } end end)
        return found
    end
    -- A quest log: { zone, { id, title, level, group } ... } lists, C_QuestLog-shaped.
    local function questLog(zones, tags)
        local rows = {}
        for _, z in ipairs(zones) do
            rows[#rows + 1] = { isHeader = true, title = z[1] }
            for i = 2, #z do
                local q = z[i]
                rows[#rows + 1] = { questID = q[1], title = q[2], level = q[3] or 20, suggestedGroup = q[4] }
            end
        end
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
        return rows
    end
    local H = 3600

    ---------------------------------------------------------------------------
    -- R-17.23: 進行中 / 已結束; 刪除; 清除
    ---------------------------------------------------------------------------

    test("GF-002-J R-17.23 ended tickets and my closed worker ticket move to 已結束; 進行中 has only the live ones", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        local live = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local past = Adv.open({ dungeon = "dm", leaderRole = "d", slots = { { s = t + 60 } } })
        local done = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, done, t + 1, "t")
        wow.advance(60)
        Adv.leader(done, "done")
        local gone = Adv.open({ dungeon = "wc", leaderRole = "d" })
        Adv.leader(gone, "cancel", "manual")
        Adv.setWorker({ dungeons = { "smg" }, main = "h", slots = { { s = t + 30 * 60, d = H } } })
        wow.state.now = wow.state.now + 2 * H; Adv.refresh(); Adv.maintain()
        ns.Framework.open("adventure")
        U.setTab("active")
        local ids = {}
        local function collect()
            ids = {}
            eachRow(U, function(r) if r.view then ids[#ids + 1] = r.view.id end; if r.mine then ids[#ids + 1] = "mine" end end)
            table.sort(ids)
            return table.concat(ids, ",")
        end
        eq(collect(), live, "進行中: only the live ticket")
        ok(not U.clearButton:IsShown(), "no 清除 here")
        ok(U.activeTab.selected and not U.endedTab.selected, "進行中 chosen")
        wow.click(U.endedTab)
        local want = { past, done, gone, "mine" }
        table.sort(want)
        eq(collect(), table.concat(want, ","), "已結束: 過期, 成行, 取消 and my closed worker ticket")
        ok(U.clearButton:IsShown() and plain(U.clearButton:GetText()):find("清除", 1, true), "清除 on 已結束")
        eq(rowOf(U, done).badge, "成行", "成行 is there"); eq(rowOf(U, past).badge, "過期", "過期 too")
        wow.click(U.activeTab)
        eq(U.tab, "active", "back")
    end)

    test("GF-002-J 刪除 my own ticket: far right, confirmed first; with people on it they see it cancelled", function()
        local ns = login()
        local Adv, U, W = ns.Adventure, ns.AdventureUI, ns.Widgets
        local t = ns.Share.serverNow()
        local empty = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local joined = Adv.open({ dungeon = "sfk", leaderRole = "d" })
        apply(ns, B, joined, t + 1, "t")
        offer(ns, B, "T", { { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "dm", qs = "", tm = "n", rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t } })
        ns.Framework.open("adventure")
        local r = rowOf(U, empty)
        ok(r.delete, "刪除 on my ticket"); eq(r.deleteX, U.COL.delete, "at the far right")
        ok(U.COL.delete + ns.ROW_ICON + 4 + ns.labelWidth("刪除") <= U.ROW_WIDTH, "inside the row")
        ok(U.COL.who + U.COL.whoW <= U.COL.delete, "after the leader's name")
        eq(rowOf(U, "abbb.1").delete, false, "not on someone else's")
        -- The confirmation: 取消 keeps it, 確定 deletes it.
        local f = U.askDelete(Adv.get(empty))
        ok(f:IsShown() and plain(f.text._text):find("刪除", 1, true) and plain(f.text._text):find("血色修道院", 1, true), "asks: " .. plain(f.text._text))
        ok(f.gfClose and f.gfClose:IsShown(), "with an X")
        wow.click(f.no)
        ok(Adv.get(empty), "取消: still there")
        U.askDelete(Adv.get(empty)); ns.escape()
        ok(Adv.get(empty) and not f:IsShown(), "ESC: still there")
        U.askDelete(Adv.get(empty)); wow.click(f.yes)
        eq(Adv.get(empty), nil, "確定: gone from my record (nobody had joined)")
        -- With B on it: cancelled (B sees 取消), hidden from my page.
        U.askDelete(Adv.get(joined)); wow.click(f.yes)
        local v = Adv.get(joined)
        eq(v and v.state, "cancel", "others see it cancelled"); ok(Adv.local_().deleted[joined], "hidden here")
        U.setTab("ended")
        eq(rowOf(U, joined), nil, "not on my 已結束 either")
        -- Ended ones go at once too, and their log record with them.
        local id3 = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, C, id3, ns.Share.serverNow(), "t")
        wow.advance(60)
        Adv.leader(id3, "done")
        eq(#Adv.myLog(), 1, "logged")
        ok(Adv.deleteTicket(id3), "deleted")
        eq(Adv.get(id3), nil, "gone"); eq(#Adv.myLog(), 0, "its log record too")
    end)

    test("GF-002-J 清除: my ended tickets and completion log are gone, also from the next upload", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        local live = Adv.open({ dungeon = "smg", leaderRole = "d" })
        local done = Adv.open({ dungeon = "rfk", roles = { t = 1, h = 0, d = 1 }, leaderRole = "d" })
        apply(ns, B, done, t + 1, "t")
        wow.advance(60)
        Adv.leader(done, "done")
        local gone = Adv.open({ dungeon = "wc", leaderRole = "d" })
        Adv.leader(gone, "cancel", "manual")
        local up = Adv.uploadFor(A)
        ok(up.tickets.value[done] and up.log and up.log.value[done], "uploaded before: the ticket and its log record")
        ns.Framework.open("adventure")
        U.setTab("ended")
        local f = U.askClear()
        ok(f:IsShown() and plain(f.text._text):find("清除", 1, true), "asks first")
        wow.click(f.yes)
        eq(Adv.get(done), nil, "成行 gone"); eq(Adv.get(gone), nil, "取消 gone"); ok(Adv.get(live), "the live one stays")
        eq(#Adv.myLog(), 0, "the log is empty")
        up = Adv.uploadFor(A)
        eq(up.tickets.value[done], nil, "not in the next upload"); eq(up.tickets.value[gone], nil, "nor that one")
        eq(up.log, nil, "no log records uploaded")
        ok(up.tickets.value[live], "the live ticket still goes up")
    end)

    ---------------------------------------------------------------------------
    -- Role icons, the X, crops, the date steps, the quest pages, the grid
    ---------------------------------------------------------------------------

    test("GF-002-J role icons without names (owner exception); square icons cropped; button icons ≤ button height - 8", function()
        local ns = login()
        local U, G = ns.AdventureUI, ns.GameIcons
        local text = U.rolesName("t", "h")
        ok(text:find("|T", 1, true), "icons")
        for _, name in ipairs({ "坦", "補", "輸出" }) do ok(not plain(text):find(name, 1, true), "no " .. name) end
        U.openWorker()
        local wf = _G[U.WORKER_NAME]
        for _, r in ipairs({ "t", "h", "d" }) do
            local b = wf.mainRoles[r]
            ok(not (b.label and b.label:IsShown() and plain(b.label._text) ~= ""), "no name next to the role icon")
            eq(b.tip, U.ROLE_NAME[r], "its name in the tooltip")
        end
        U.openTicket()
        local tf = _G[U.TICKET_NAME]
        U.draft().dungeon = "smg"; U.drawTicket()
        eq(plain(tf.roleGroups.t.text._text), "1", "a number by the round icon")
        -- Square spell / item icons are cropped (no black square), in text and on textures.
        ok(U.tex("today", 18):find(":5:59:5:59|t", 1, true), "the clock in 今天 23:00: cropped")
        ok(G.markup("final", 18):find(":5:59:5:59|t", 1, true), "GameIcons markup: cropped")
        ok(not G.markup("yes", 18):find(":5:59", 1, true), "ReadyCheck art: whole")
        local t = tf:CreateTexture()
        G.set(t, "final") -- GF-UI-G: 行事曆 is now the calendar page (not a square icon)
        eq(t._texCoord[1] .. "," .. t._texCoord[4], "0.08,0.92", "a texture: cropped")
        -- Inline icons in text buttons are at most the button height - 8.
        eq(U.BUTTON_ICON <= ns.BUTTON_H - 8, true, "the limit")
        local src = assert(io.open(ADDON_DIR .. "/AdventureUI.lua", "rb")):read("*a")
        for size in src:gmatch('textButton%([^\n]-tex%("[%w_]+", (%d+)%)') do
            ok(tonumber(size) <= ns.BUTTON_H - 8, "a text button icon of " .. size)
        end
    end)

    test("GF-002-J every sub-window and picker has an X (with ESC and a click outside)", function()
        local ns = login()
        local U, W = ns.AdventureUI, ns.Widgets
        local frames = {}
        U.openTicket()
        frames.ticket = _G[U.TICKET_NAME]
        frames.time = U.pickStart(frames.ticket.startButton)
        frames.grid = U.pickDestination(frames.ticket.dest)
        frames.grid:Hide()
        frames.quests = (U.openWorker() and U.pickWorkerQuests(UIParent))
        frames.chooser = U.slotChooser(UIParent, { title = "定案", multi = false, selected = { 1 }, slots = { { id = 1, now = true } }, onDone = function() end })
        frames.rules = U.openRules()
        frames.confirm = W.confirm("刪除", function() end)
        frames.calendar = U.openCalendar()
        for name, f in pairs(frames) do
            local x = f.gfClose or f.CloseButton
            ok(x, name .. ": an X")
            if f.gfClose then
                local p = f.gfClose._points[1]
                eq(p[1] .. ">" .. p[3], "TOPRIGHT>TOPRIGHT", name .. ": top right")
            end
        end
        frames.rules:Show()
        wow.click(frames.rules.gfClose)
        ok(not frames.rules:IsShown(), "the X closes it")
        U.openWorker(); U.pickWorkerQuests(UIParent)
        wow.click(U.questPickerFrame().gfClose)
        ok(not U.questPickerFrame():IsShown(), "the quest picker too")
    end)

    test("GF-002-J the date steps ▲ ▼ inside the time picker (today to 14 days), nothing opens below it", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openTicket()
        local tf = _G[U.TICKET_NAME]
        local pk = U.pickStart(tf.startButton)
        local h0 = pk._h
        ok(pk.dayUp.disabled and not pk.dayDown.disabled, "today: only ▼")
        for _ = 1, 20 do wow.click(pk.dayDown) end
        ok(pk:IsShown(), "still the picker")
        ok(pk.dayDown.disabled, "14 days: ▼ greyed out")
        eq(plain(pk.dayLabels[1]._text), U.day(U.dayStart(14) + 43200), "the 14th day's hours")
        ok(pk._h <= h0, "no taller than before: nothing below it")
        wow.click(pk.hours[1][20])
        eq(U.dayOffset(d.slots[1].start), 14, "the slot on that day"); eq(d.slots[1].dayOff, 14, "remembered")
        for _ = 1, 20 do wow.click(pk.dayUp) end
        ok(pk.dayUp.disabled and pk.dayLabels[2]:IsShown(), "back to today and tomorrow")
        eq(_G[ns.Framework.MENU_NAME] and _G[ns.Framework.MENU_NAME]:IsShown() or false, false, "no list menu")
    end)

    test("GF-002-J a long quest log: pages (◀ 1/N ▶) inside the screen; group / elite quests first, the others dimmer", function()
        local ns = login()
        local U = ns.AdventureUI
        local z1, z2 = { "貧瘠之地" }, { "灰谷" }
        for i = 1, 30 do z1[#z1 + 1] = { 3000 + i, "測試任務 甲" .. i, 20, i == 25 and 3 or nil } end
        for i = 1, 30 do z2[#z2 + 1] = { 4000 + i, "測試任務 乙" .. i, 22 } end
        questLog({ z1, z2 })
        local qp = (U.openWorker() and U.pickWorkerQuests(UIParent))
        ok(qp.pages >= 2, "pages: " .. qp.pages)
        ok(qp._h <= U.QP_MAX_Y + 60, "the height stays: " .. qp._h)
        ok(qp.prev:IsShown() and qp.next:IsShown() and qp.pageText._text == "1/" .. qp.pages, "◀ 1/N ▶")
        ok(qp.prev.disabled, "the first page: ◀ greyed out")
        -- The group quest (suggested 3) leads its zone, marked; the others dimmer.
        local first
        for _, r in ipairs(qp.rows) do if r:IsShown() and not first then first = r end end
        eq(first.questId, 3025, "group / elite first"); ok(first.elite:IsShown(), "marked")
        local other
        for _, r in ipairs(qp.rows) do if r:IsShown() and r.questId == 3001 then other = r end end
        ok(other and not other.elite:IsShown() and other.name._color[1] < 1, "the others dimmer")
        -- Every row of a page inside the frame.
        local seen = {}
        for page = 1, qp.pages do
            for _, r in ipairs(qp.rows) do
                if r:IsShown() then
                    local p = r._points[1]
                    ok(p[4] >= 0 and p[4] + r._w <= qp._w and -p[5] + r._h <= qp._h - 50, "inside: " .. r.questId)
                    seen[r.questId] = true
                end
            end
            wow.click(qp.next)
        end
        local n = 0
        for _ in pairs(seen) do n = n + 1 end
        eq(n, 60, "every quest on some page")
        ok(qp.next.disabled, "the last page: ▶ greyed out")
        C_QuestLog = nil
    end)

    test("GF-002-J 冒險單: 人數, 錄取 and 標籤 on one column grid; nothing overlaps; inside the window", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = _G[U.TICKET_NAME]
        d.dungeon = "smg"; U.drawTicket()
        local X, C = f.controlX, U.OPTION_COL
        eq(f.direct.flowX, X, "直接錄取: column 1"); eq(f.consent.flowX, X + C, "團長同意: column 2")
        for k, b in ipairs(f.tagList) do eq(b.flowX, X + (k - 1) * C, "tag " .. k .. ": column " .. k) end
        eq(f.roleGroups.t.x, X, "坦: column 1"); eq(f.roleGroups.h.x, X + C, "補: column 2"); eq(f.roleGroups.d.x, X + 2 * C, "輸出: column 3")
        -- Each option fits its column.
        for _, b in ipairs({ f.direct, f.consent, unpack(f.tagList) }) do
            ok(ns.OrdersUI.buttonSpan(b) < C, "fits its column: " .. tostring(b.tip))
        end
        local g = f.roleGroups.t
        ok(g.bx + 38 + 34 - g.x < C, "a role group fits its column")
        local text, n = overlaps(f)
        eq(text, "", "no overlaps"); eq(insideWindow(f), "", "inside"); ok(n >= 15, "parts: " .. n)
        -- The time picker with its steps, the paged quest picker, the confirmation: no overlaps either.
        local pk = U.pickStart(f.startButton)
        eq((overlaps(pk)), "", "time picker"); eq(insideWindow(pk), "", "time picker inside")
        pk:Hide()
        questLog({ { "貧瘠之地", { 3001, "測試任務 甲", 20, 3 }, { 3002, "測試任務 乙", 20 } } })
        local qp = U.pickQuests(f.pickQuest)
        eq((overlaps(qp)), "", "quest picker: zones"); eq(insideWindow(qp), "", "inside")
        for _, z in ipairs(qp.zoneRows) do if z:IsShown() and z.zone == "貧瘠之地" then wow.click(z) end end
        eq((overlaps(qp)), "", "quest picker: quests"); eq(insideWindow(qp), "", "inside")
        local wq = (U.openWorker() and U.pickWorkerQuests(UIParent))
        eq((overlaps(wq)), "", "worker quest picker with 全區"); eq(insideWindow(wq), "", "inside")
        local cf = ns.Widgets.confirm("刪除：血色修道院：墓地", function() end)
        eq((overlaps(cf)), "", "confirmation"); eq(insideWindow(cf), "", "inside")
        C_QuestLog = nil
    end)

    ---------------------------------------------------------------------------
    -- R-17.20 - R-17.22: zones
    ---------------------------------------------------------------------------

    test("GF-002-J R-17.20 a quest ticket picks its zone first; the zone leads the row; group quests marked", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        questLog({ { "貧瘠之地", { 3001, "測試任務 甲", 20 }, { 3002, "測試任務 精英", 22, 3 } }, { "灰谷", { 4001, "測試任務 乙", 22 } } })
        local d = U.openTicket()
        local f = _G[U.TICKET_NAME]
        wow.click(f.pickQuest)
        local qp = U.questPickerFrame()
        local zones = {}
        for _, z in ipairs(qp.zoneRows) do if z:IsShown() then zones[#zones + 1] = z.zone end end
        eq(table.concat(zones, ","), "雷霆崖,貧瘠之地,灰谷", "where I am first, then the log's zones")
        ok(not qp.rows[1] or not qp.rows[1]:IsShown(), "no quests before a zone")
        for _, z in ipairs(qp.zoneRows) do if z.zone == "貧瘠之地" then ok(z.elite:IsShown(), "a zone with a group quest is marked"); wow.click(z) end end
        eq(d.zone, "貧瘠之地", "the zone chosen")
        local shown = {}
        for _, r in ipairs(qp.rows) do if r:IsShown() then shown[#shown + 1] = r.questId end end
        eq(table.concat(shown, ","), "3002,3001", "that zone's quests, the group one first")
        wow.click(qp.rows[1])
        ok(qp.back:IsShown(), "區域: back to the zones")
        local id = U.submitTicket()
        local v = Adv.get(id)
        eq(v.zone, "貧瘠之地", "zn"); ok(v.groupQuests[3002], "qe: the group quest")
        eq(plain(U.destText(v)), "貧瘠之地", "the zone leads the row")
        ok(U.detailText(v):find(ns.GameIcons.pick("elite")[1], 1, true), "the group quest marked on line 2")
        -- A zone alone (where I am, no quests) is a destination too.
        local d2 = U.openTicket()
        U.pickQuests(f.pickQuest)
        for _, z in ipairs(qp.zoneRows) do if z.zone == "雷霆崖" then wow.click(z) end end
        local id2 = U.submitTicket()
        ok(id2, "opened with the zone only"); eq(Adv.get(id2).zone, "雷霆崖", "its zone")
        -- Upload: never the zone names.
        for _, tk in pairs(Adv.uploadFor(A).tickets.value) do
            for k, val in pairs(tk) do ok(type(val) ~= "string" or not val:find("雷霆崖", 1, true), "no zone uploaded: " .. k) end
        end
        C_QuestLog = nil
    end)

    test("GF-002-J R-17.21/R-17.22 a worker takes a whole zone; same zone matches; shared quests rank higher, group ones highest", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        questLog({ { "貧瘠之地", { 3001, "測試任務 甲", 20 }, { 3002, "測試任務 精英", 22, 3 } } })
        -- My worker ticket: the whole 貧瘠之地.
        U.openWorker()
        local qp = (U.openWorker() and U.pickWorkerQuests(UIParent))
        local whole
        for _, b in ipairs(qp.wholes) do if b:IsShown() and b.zone == "貧瘠之地" then whole = b end end
        ok(whole and whole.label._text == "全區", "全區 by the zone")
        wow.click(whole)
        ok(whole.selected, "chosen")
        qp:Hide()
        U.saveWorker()
        local mine = Adv.myWorker()
        eq(table.concat(mine.zones, ","), "貧瘠之地", "zs")
        ok(plain(U.workerQuests(mine)):find("貧瘠之地 全區", 1, true), "the row: the zone, 全區")
        -- B's tickets: a zone only, a shared quest, a shared group quest.
        local t = ns.Share.serverNow()
        offer(ns, B, "T", {
            { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "", qs = "", zn = "貧瘠之地", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.2", src = "g", ver = 1, cr = t + 1, ds = "", qs = "3001", zn = "貧瘠之地", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.3", src = "g", ver = 1, cr = t + 2, ds = "", qs = "3002", qe = "3002", zn = "貧瘠之地", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.4", src = "g", ver = 1, cr = t + 3, ds = "", qs = "", zn = "灰谷", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
        })
        local w = Adv.workers()[A]
        local log = Adv.questLog()
        eq(Adv.matchScore(Adv.get("abbb.1"), w, log), 1, "the same zone")
        eq(Adv.matchScore(Adv.get("abbb.2"), w, log), 2, "a shared quest (the whole zone holds it)")
        eq(Adv.matchScore(Adv.get("abbb.3"), w, log), 3, "a shared group quest")
        eq(Adv.matchScore(Adv.get("abbb.4"), w, log), 0, "another zone")
        ok(Adv.matches(Adv.get("abbb.1"), w, 30, log), "the zone matches")
        ok(not Adv.matches(Adv.get("abbb.4"), w, 30, log), "灰谷 does not")
        local tickets = Adv.rowsFor()
        local order = {}
        for _, r in ipairs(tickets) do order[#order + 1] = r.view.id end
        eq(table.concat(order, ","), "abbb.3,abbb.2,abbb.1,abbb.4", "ranked: group quest, quest, zone, the rest")
        -- On the leader's side (0.14.0 ticket: no zone): a worker with the quest still matches.
        offer(ns, C, "W", { { id = "w", cr = t, ds = "", qs = "3001", qz = "貧瘠之地", rm = "d", ra = "",
            sv = Adv.encodeTimes({ { id = 1, now = true, s = t } }), ex = t + 86400, st = "o", sa = t } })
        local wc = Adv.workers()[C]
        ok(wc.zones["貧瘠之地"], "qz: the zones of the quests")
        local old = Adv.view({ id = "abbb.9", src = "g", cr = t, ds = "", qs = "3001", tm = "n", sz = 4, lr = "d", st = "o", sa = t }, B, {}, { now = t })
        eq(Adv.matchScore(old, wc, nil), 2, "a 0.14.0 ticket without a zone: the shared quest")
        C_QuestLog = nil
    end)

    test("GF-002-J R-17.22 the 區域 filter: a drop-down with check boxes; rows of the chosen zones only", function()
        local ns = login()
        local Adv, U = ns.Adventure, ns.AdventureUI
        local t = ns.Share.serverNow()
        offer(ns, B, "T", {
            { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "", qs = "", zn = "貧瘠之地", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.2", src = "g", ver = 1, cr = t, ds = "", qs = "", zn = "灰谷", tm = "n", sz = 4, lr = "d", tg = 0, md = "a", st = "o", sa = t },
            { id = "abbb.3", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n", rt = 1, rh = 1, rd = 3, lr = "d", tg = 0, md = "a", st = "o", sa = t },
        })
        ns.Framework.open("adventure")
        local zb = U.zoneButton
        eq(plain(zb:GetText()), "區域", "every zone")
        local opts = {}
        for _, o in ipairs(U.zoneOptions()) do opts[#opts + 1] = o.text end
        eq(table.concat(opts, ","), "灰谷,血色修道院,貧瘠之地", "zones and dungeons on the page")
        local function shown()
            local ids = {}
            eachRow(U, function(r) if r.view then ids[#ids + 1] = r.view.id end end)
            table.sort(ids)
            return table.concat(ids, ",")
        end
        eq(shown(), "abbb.1,abbb.2,abbb.3", "all")
        zb.setOnly("貧瘠之地")
        eq(shown(), "abbb.1", "貧瘠之地 only"); eq(plain(zb:GetText()), "區域 1", "one chosen")
        zb.toggle("血色修道院")
        eq(shown(), "abbb.1,abbb.3", "and the dungeon (by its name)")
        zb.selectAll()
        eq(shown(), "abbb.1,abbb.2,abbb.3", "all again")
        -- On the toolbar, apart from the other buttons.
        local text, n = overlaps(ns.Framework.panel("adventure"))
        eq(text, "", "the page toolbar: no overlaps")
    end)
end
