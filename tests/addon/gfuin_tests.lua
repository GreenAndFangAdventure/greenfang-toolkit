-- GF-UI-N: the owner's second batch of 0.16.12 screenshots — the adventure list
-- rows (編輯's icon, one column line for the leader and the buttons, 刪除 / 移除
-- in one place, every slot on the row), the quest picker's two columns, the
-- short 自動集料 card, unread / read notices, the dev notice preview in the
-- toolkit's own words.
-- Offline only; not checked in the Forever client. Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local ROOT = ADDON_DIR:gsub("/addon/GreenFangToolkit$", "")
    local DEV_DIR = ROOT .. "/addon/GreenFangToolkit_Dev"
    local H = 3600

    local function readAll(path) local h = io.open(path, "rb"); if not h then return "" end local s = h:read("*a"); h:close(); return s end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function login()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        ns.Share.rand = function(a) return a end
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        wow.advance(25)
        return ns
    end
    local function pointX(f)
        local p = f._points and f._points[#f._points]
        return p and p[4]
    end

    ---------------------------------------------------------------------------
    -- 1a. 編輯's icon
    ---------------------------------------------------------------------------

    test("GF-UI-N 1a 編輯 is the game's pencil-and-note (not the quill); a reused text button gets its icon back", function()
        local ns = login()
        local U = ns.AdventureUI
        ok(not readAll(ADDON_DIR .. "/AdventureUI.lua"):find("INV_Feather_05", 1, true), "the quill is gone")
        eq(U.GAME.edit, "edit", "編輯 goes through GameIcons")
        eq(ns.GameIcons.ART.edit[1][1], "Interface\\FriendsFrame\\UI-FriendsFrame-Note", "the friends list's note pencil first")
        ok(has(U.tex("edit"), "UI-FriendsFrame-Note"), "inline 編輯 uses it")
        eq(U.BUTTON.edit.icon, "edit", "the row button too")
        -- A row button that was 密語 (a text button: icon hidden) and is reused for 編輯.
        local b = U.iconButton(UIParent, ns.ROW_ICON, "edit", "編輯")
        U.textStyle(b, true)
        ok(not b.tex:IsShown(), "a text button hides its icon")
        U.textStyle(b, false)
        ok(b.tex:IsShown(), "back to an icon button: the icon shows again")
    end)

    ---------------------------------------------------------------------------
    -- 1b. One column line; 刪除 and 移除 in one place
    ---------------------------------------------------------------------------

    test("GF-UI-N 1b the leader's icon and line 2's first button start on one line; 移除 and 刪除 share the far right", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local C = U.COL
        eq(C.buttons, C.cls, "line 2's buttons start where the class icon does")
        eq(C.who, C.cls + ns.ROW_ICON + 4, "the leader's name starts where the first button's name does")
        ok(C.who + C.whoW <= C.delete, "the name ends before 刪除")
        -- My worker ticket and my adventure ticket on the page.
        ns.Framework.open("adventure")
        local d = U.openWorker()
        U.toggleWorkerDungeon("smg")
        wow.click(_G[U.WORKER_NAME].save)
        local t = ns.Share.serverNow()
        local id = Adv.open({ dungeon = "sfk", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = { { s = t + 3 * H, d = 2 * H } } })
        ok(id, "ticket opened")
        U.refresh()
        local wRow, tRow
        for _, r in ipairs(U.rowFrames()) do
            if r:IsShown() and r.mine then wRow = r end
            if r:IsShown() and r.view and r.view.id == id then tRow = r end
        end
        ok(wRow and tRow, "both rows shown")
        ok(wRow.delete:IsShown() and tRow.delete:IsShown(), "both have the far-right button")
        -- GF-UI-P: text buttons (the word inside the frame).
        eq(wRow.delete.gfTextText._text .. "," .. tRow.delete.gfTextText._text, "移除,刪除", "移除 (worker ticket), 刪除 (ticket)")
        eq(pointX(wRow.delete), pointX(tRow.delete), "at the same x")
        eq(wRow.buttons[1].flowX, C.buttons, "worker row: 編輯 starts on the line")
        eq(tRow.buttons[1].flowX, C.buttons, "ticket row: its first button starts on the line")
        eq(pointX(wRow.cls), C.cls, "class icon on the line")
        eq(wRow.cls._w, ns.ROW_ICON, "the class icon is a button icon's size")
        for _, r in ipairs({ wRow, tRow }) do
            for _, b in ipairs(r.buttons) do if b:IsShown() then ok(b.tex:IsShown() or b.textStyle, "every icon button shows its icon") end end
        end
        -- 移除 still removes my worker ticket.
        wow.click(wRow.delete)
        ok(not Adv.myWorker() or Adv.myWorker().removed, "移除 removed the worker ticket")
    end)

    ---------------------------------------------------------------------------
    -- 1c. Every slot on the row
    ---------------------------------------------------------------------------

    test("GF-UI-N 1c a ticket with several slots names every one on its row; too many: the first ones and 等 N 個; 定案 marked", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local t = ns.Share.serverNow()
        local slots = { { s = t + 26 * H, d = 2 * H }, { s = t + 28 * H }, { s = t + 50 * H, d = 3 * H } }
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "d", slots = slots })
        ns.Framework.open("adventure")
        U.refresh()
        local row
        for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then row = r end end
        ok(row, "the row")
        local text = plain(row.time:GetText())
        ok(has(text, U.clock(slots[1].s)), "the row names the first slot: " .. text)
        ok(not has(text, "+"), "no +N: " .. text)
        local shown = 0
        for _, sl in ipairs(slots) do if has(text, U.clock(sl.s)) then shown = shown + 1 end end
        ok(shown >= 2, "more than one slot on the row: " .. text)
        if shown < 3 then ok(has(text, "等 3 個"), "the rest counted: " .. text) end
        ok(row.measureTime(row.time:GetText()) <= U.COL.seats - U.COL.time - 8, "fits the column")
        -- With room for all: all three.
        local all = plain(U.rowTimeText(Adv.get(id), 1000))
        for _, sl in ipairs(slots) do ok(has(all, U.clock(sl.s)), "all fit: " .. U.clock(sl.s)) end
        row.time:SetText(U.rowTimeText(Adv.get(id), nil, row.measureTime))
        -- The tooltip lists each in full.
        local tip = table.concat(U.ticketTooltip(Adv.get(id)), "\n")
        ok(has(plain(tip), "時段 3 個"), "tooltip: how many")
        for _, sl in ipairs(slots) do ok(has(plain(tip), U.clock(sl.s)), "tooltip names " .. U.clock(sl.s)) end
        -- Five slots on five days: the first ones, 「等 5 個」, within the column.
        local five = { slots = {} }
        for i = 1, 5 do five.slots[i] = { id = i, s = t + (24 * i + 2) * H } end
        local w = U.COL.seats - U.COL.time - 8
        local t5 = U.rowTimeText(five)
        ok(has(t5, "等 5 個"), "等 5 個: " .. plain(t5))
        ok(ns.labelWidth(t5) <= w or not t5:find("、", 1, true), "within the column (or a single slot)")
        ok(has(plain(t5), U.clock(five.slots[1].s)), "the first slot shown")
        -- 定案 the last one: it is shown (first) in gold with the 定案 scroll.
        five.final = 5
        local f5 = U.rowTimeText(five)
        ok(has(f5, U.FINAL_COLOR .. U.slotShort(five.slots[5])), "the 定案 slot in gold, first: " .. f5)
        ok(has(f5, "INV_Scroll_04"), "with the 定案 scroll")
        five.final = nil
        -- One slot: the same as before (its end time too).
        local one = { slots = { { id = 1, s = t + 3 * H, d = 2 * H } } }
        one.slot = one.slots[1]
        eq(U.rowTimeText(one), U.timeText(one), "one slot: unchanged")
        -- Same day: the day word once.
        local same = { slots = { { id = 1, s = t + 26 * H }, { id = 2, s = t + 27 * H } } }
        local day = U.dayWord(same.slots[1].s)
        local _, n = plain(U.rowTimeText(same)):gsub(day, "")
        eq(n, 1, "the day word once for one day")
    end)

    ---------------------------------------------------------------------------
    -- 2. The quest picker's two columns
    ---------------------------------------------------------------------------

    test("GF-UI-N 2 quest picker: 全區 ends before the next column; a long zone name is cut, never under 全區", function()
        local ns = login()
        local U = ns.AdventureUI
        local LONG = "希爾斯布萊德丘陵與更遠的一大片荒野"
        local rows = {}
        for z = 1, 14 do
            rows[#rows + 1] = { isHeader = true, title = z == 1 and LONG or ("測試區域" .. z) }
            rows[#rows + 1] = { questID = 5000 + z, title = "測試任務 " .. z, level = 20 }
        end
        C_QuestLog = { GetNumQuestLogEntries = function() return #rows, 0 end, GetInfo = function(i) return rows[i] end }
        local okRun, err = pcall(function()
            ns.Framework.open("adventure")
            U.openWorker()
            local qp = U.pickWorkerQuests(UIParent)
            local colW, gap = U.QP_COL_W, U.QP_GAP
            local labelEnd = U.QP_ZONE_WHOLE_X + 24 + 4 + ns.labelWidth("全區")
            ok(labelEnd <= colW - gap + 4, "全區 ends before the next column: " .. labelEnd .. " / " .. colW)
            local nameW, eliteX, countX = U.qpZoneCols(true)
            ok(34 + nameW <= eliteX, "the name stops before the elite mark")
            ok(countX + U.QP_COUNT_W <= U.QP_ZONE_WHOLE_X, "the count stops before 全區")
            local cols, long = {}, nil
            for _, z in ipairs(qp.zoneRows) do
                if z:IsShown() then
                    cols[pointX(z)] = true
                    if z.zone == LONG then long = z end
                    eq(z.name._fixedWidth, nameW, "zone name width " .. z.zone)
                    ok(z._w <= U.QP_ZONE_WHOLE_X - 10, "the row stops before its check")
                end
            end
            local n = 0
            for _ in pairs(cols) do n = n + 1 end
            eq(n, 2, "two columns")
            ok(long and ns.labelWidth(LONG) > long.name._fixedWidth, "the long name is wider than its cell (cut with …)")
            for _, b in ipairs(qp.wholes) do
                if b:IsShown() then
                    local x = pointX(b)
                    local inCol = (x - 16) % colW
                    eq(inCol, U.QP_ZONE_WHOLE_X, "全區 check at its place in the column")
                end
            end
            -- A zone opened: its header stops before its 全區 too.
            for _, z in ipairs(qp.zoneRows) do if z:IsShown() and z.zone == LONG then wow.click(z) end end
            for _, h in ipairs(qp.heads) do
                if h:IsShown() then ok(h._fixedWidth and h._fixedWidth <= U.QP_ZONE_WHOLE_X - 8, "header width " .. tostring(h._fixedWidth)) end
            end
            qp:Hide()
        end)
        C_QuestLog = nil
        if not okRun then error(err, 0) end
    end)

    ---------------------------------------------------------------------------
    -- 3. The 自動集料 card
    ---------------------------------------------------------------------------

    test("GF-UI-N 3 自動集料 card: five short lines in the player's words; the items named by their page", function()
        local ns = login()
        local UI = ns.SupplyUI
        -- GF-UI-S: no sentences on the card (集料項目); the 說明 mode has them, in the player's words.
        eq(#UI.cardLines("auto"), 0, "no card lines")
        local l = ns.Help.TEXT.supply_auto[2]
        for _, word in ipairs({ "白名單", "四處", "StorageSource", "GFTKS" }) do ok(not has(l, word), "no inside word " .. word) end
        -- The item rows: the page label is the name.
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        local okRun, err = pcall(function()
            ns.Framework.open("supply")
            UI.autoBox.help._scripts.OnClick(UI.autoBox.help)
            local f = UI.card("auto")
            local first = f.itemRows[1]
            ok(first and first:IsShown(), "item rows")
            local label = ns.SupplyRules.list[1].chapters[1].items[1].label
            eq(first.name._text, label, "named by its page: " .. tostring(label))
            ok(not first.count:IsShown(), "no second copy of the label")
        end)
        C_QuestLog = nil
        if not okRun then error(err, 0) end
    end)

    ---------------------------------------------------------------------------
    -- 4. Unread and read notices
    ---------------------------------------------------------------------------

    test("GF-UI-N 4 notices: unread has the light, the fill and gold words; read has none and dim words", function()
        local ns = login()
        local N, UI = ns.Notify, ns.NotifyUI
        N.push({ module = "supply", key = "gfuin:1", text = "測試通知 一" })
        N.push({ module = "radar", key = "gfuin:2", text = "測試通知 二" })
        local read
        for _, e in ipairs(N.list()) do if e.key == "gfuin:1" then read = e end end
        N.markRead(read)
        ns.Framework.open("adventure")
        UI.open()
        local rows = {}
        for _, r in ipairs(UI.list().rows) do if r:IsShown() and r.entry then rows[r.entry.key] = r end end
        local u, r = rows["gfuin:2"], rows["gfuin:1"]
        ok(u and r, "both rows")
        ok(u.mark:IsShown() and u.unreadFill:IsShown(), "unread: the light and the fill")
        ok(not r.mark:IsShown() and not r.unreadFill:IsShown(), "read: neither")
        ok(u.mark.gfPath ~= nil, "the light is a game file: " .. tostring(u.mark.gfPath))
        local lu, lr = UI.rowLook(true), UI.rowLook(false)
        eq(lu.text[1] .. "," .. lu.text[2], ns.Theme.C.gold[1] .. "," .. ns.Theme.C.gold[2], "unread words gold")
        ok(lr.text[4] < 1 and lr.tag[4] < 1, "read words dim")
        eq(u.text._color[1], ns.Theme.C.gold[1], "drawn gold")
        eq(r.text._color[1], ns.Theme.C.muted[1], "drawn muted")
        ok(not readAll(ADDON_DIR .. "/NotifyUI.lua"):find("SetScript%(\"OnUpdate\""), "no OnUpdate")
    end)

    ---------------------------------------------------------------------------
    -- 5. The dev notice preview in the toolkit's own words
    ---------------------------------------------------------------------------

    local function tocFiles()
        local out = {}
        for line in readAll(DEV_DIR .. "/GreenFangToolkit_Dev.toc"):gmatch("[^\r\n]+") do
            if line:match("^[%w_]+%.lua$") then out[#out + 1] = line end
        end
        return out
    end
    local function startDev()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        for _, id in ipairs({ "orders", "adventure", "supply", "roster", "bank" }) do pcall(ns.Framework.open, id) end
        ns.NotifyUI.open(); ns.NotifyUI.list():Hide()
        wow.advance(3)
        C_AddOns.IsAddOnLoaded = function(name) return name == "GreenFangToolkit_Dev" end
        local D = {}
        for _, file in ipairs(tocFiles()) do assert(loadfile(DEV_DIR .. "/" .. file))("GreenFangToolkit_Dev", D) end
        wow.fire("ADDON_LOADED", "GreenFangToolkit_Dev")
        return ns, D.Preview
    end

    test("GF-UI-N 5 preview notify: every kind in the real words, every reminder variant, half unread", function()
        local ns, P = startDev()
        local okRun, err = pcall(function()
            SlashCmdList.GFTKDEV("preview notify")
            local N = ns.Notify
            local list = N.list()
            local by, unread = {}, 0
            for _, e in ipairs(list) do
                by[e.module] = by[e.module] or {}
                table.insert(by[e.module], e.text)
                if e.unread then unread = unread + 1 end
                ok(not has(e.text, "還沒有對應的文字"), "real words for " .. e.module .. ": " .. e.text)
            end
            for _, m in ipairs(N.MODULES) do ok(by[m.key], "a notice of " .. m.key) end
            ok(math.abs(unread - (#list - unread)) <= 1, "half unread: " .. unread .. " / " .. #list)
            -- The ❗ reminders: every variant.
            local function any(module, word)
                for _, s in ipairs(by[module] or {}) do if has(s, word) then return true end end
                return false
            end
            ok(any("adv_remind", "15 分鐘") and any("adv_remind", "60 分鐘"), "開打提醒 60 and 15 minutes")
            ok(any("adv_leader", "還沒定案") and any("adv_leader", "遞補") and any("adv_leader", "職工單過期"), "待處理: 待定案, 遞補, 職工單過期")
            ok(any("order_remind", "沒有人接單") and any("order_remind", "製作中") and any("order_remind", "可以結案"), "委託逾期／可結案")
            -- The same functions as the real notices.
            local O = ns.Orders
            local v = { id = "x", item = P.ITEM.potion, qty = 5 }
            ok(any("order_status", plain(O.notifyText(v, { code = "taken", who = "pv:c" })):gsub("^.- ", "")), "Orders.notifyText's words")
            ok(any("radar", "位職工正在徵求"), "radar")
            ok(any("recipe", ns.RecipeLink.learnedText("亞麻斗篷")), "RecipeLink.learnedText")
            -- Real code uses those helpers; the two copies match their files word for word.
            ok(has(readAll(ADDON_DIR .. "/RecipeLink.lua"), "text = RL.learnedText(t.name)"), "RecipeLink pushes learnedText")
            ok(has(readAll(ADDON_DIR .. "/SupplyRadar.lua"), "text = R.radarText("), "SupplyRadar pushes radarText")
            local bank, adv = readAll(ADDON_DIR .. "/Bank.lua"), readAll(ADDON_DIR .. "/Adventure.lua")
            for _, s in pairs(P.BANK_TEXT) do ok(has(bank, s), "Bank.lua says: " .. s) end
            ok(has(adv, '" 報名了你的冒險單 "') and has(adv, '"' .. P.SIGNUP_WAIT .. '"'), "Adventure.lua's 報名 words")
            -- Unread and read rows look different in the preview too.
            local f = ns.NotifyUI.list()
            local lit, dim = 0, 0
            for _, r in ipairs(f.rows) do
                if r:IsShown() and r.entry then if r.mark:IsShown() then lit = lit + 1 else dim = dim + 1 end end
            end
            ok(lit > 0 and dim > 0, "lit and dim rows on the first page: " .. lit .. " / " .. dim)
            SlashCmdList.GFTKDEV("preview off")
        end)
        GreenFangToolkitDevDB = nil
        if C_AddOns then C_AddOns.IsAddOnLoaded = nil end
        if not okRun then error(err, 0) end
    end)
end
