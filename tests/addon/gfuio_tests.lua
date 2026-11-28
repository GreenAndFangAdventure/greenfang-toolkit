-- GF-UI-O: the 冒險單 form like the game's 建立隊伍 screen (owner 2026-11-28:
-- 「冒險單的功能太複雜了，按鈕有點多」). First look: 活動 職責 時段 說明, then
-- 上架到尋求組隊 and 開單; 更多設定 folds 人數's ＋ －, 錄取 and 標籤 with a
-- one-line summary. Offline only; not checked in the Forever client. Made-up data.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local function readAll(path) local h = io.open(path, "rb"); if not h then return "" end local s = h:read("*a"); h:close(); return s end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local function visible(o)
        local f = o
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end
    local function login()
        wow.reset()
        local ns = wow.login(ADDON_DIR)
        if ns.Orders.resetSession then ns.Orders.resetSession() end
        if ns.Adventure.resetSession then ns.Adventure.resetSession() end
        return ns
    end
    local function form(ns) return _G[ns.AdventureUI.TICKET_NAME] end

    -- Rectangles inside the window from the anchors the form uses (as adventure_fixes_tests).
    local function fontSize(fs)
        local f = fs._font
        local obj = type(f) == "string" and rawget(_G, f) or f
        if type(obj) == "table" and obj._fontSize then return obj._fontSize end
        return 16
    end
    local function sizeOf(o)
        if o._kind == "FontString" then
            local w = wow.textWidth(o._text, o._font)
            if o._fixedWidth and o._fixedWidth > 0 and o._fixedWidth < w then w = o._fixedWidth end -- a fixed width cuts it
            return w, fontSize(o)
        end
        return o._w or 0, o._h or 0
    end
    local function rectOf(o, win, depth)
        depth = depth or 0
        if depth > 4 or not o._points or not o._points[1] then return nil end
        local p = o._points[1]
        local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4] or 0, p[5] or 0
        local w, h = sizeOf(o)
        if rel == win and point == "TOPLEFT" and relPoint == "TOPLEFT" then return x, -y, x + w, -y + h end
        if rel and rel ~= win and rel._points then
            local l, t, r, b = rectOf(rel, win, depth + 1)
            if not l then return nil end
            local cy = (t + b) / 2
            if point == "LEFT" and relPoint == "RIGHT" then return r + x, cy - h / 2 - y, r + x + w, cy + h / 2 - y end
            if point == "RIGHT" and relPoint == "LEFT" then return l + x - w, cy - h / 2 - y, l + x, cy + h / 2 - y end
        end
        return nil
    end
    local function parts(win)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            local direct = o._parent == win
                or (o._kind == "FontString" and o._parent and o._parent._kind == "Button" and o._parent._parent == win
                    and o._parent.label == o)
            local kind = o._kind
            local wanted = (kind == "Button" or kind == "EditBox" or kind == "FontString" or kind == "CheckButton" or kind == "Frame")
                or (kind == "Texture" and direct)
            if wanted and direct and visible(o) and (kind ~= "FontString" or plain(o._text) ~= "") then
                local l, t, r, b = rectOf(o, win)
                if l then out[#out + 1] = { o = o, l = l, t = t, r = r, b = b } end
            end
        end
        return out
    end
    local function name(o) return plain(o._text) ~= "" and plain(o._text) or (o.label and plain(o.label._text)) or o.tip or o.fieldNamed or o._kind end
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
    local function outside(win)
        local out = {}
        for _, p in ipairs(parts(win)) do
            if p.l < 0 or p.t < 0 or p.r > win._w + 1 or p.b > win._h + 1 then out[#out + 1] = name(p.o) end
        end
        return table.concat(out, ",")
    end
    local function leftX(o) local p = o._points and o._points[1]; return p and p[4] end
    local function lfgOn(ns) ns.NativeLFG.canList = function() return true end end

    ---------------------------------------------------------------------------

    test("GF-UI-O first look: 活動 職責 時段 說明, 更多設定 folded, 上架到尋求組隊 and 開單; the rest hidden", function()
        local ns = login()
        local U = ns.AdventureUI
        lfgOn(ns)
        local d = U.openTicket()
        local f = form(ns)
        ok(f.moreOpen == false, "更多設定 starts folded")
        eq(table.concat(U.TICKET_MAIN, ","), "活動,職責,時段,說明", "the four first rows")
        for _, n in ipairs(U.TICKET_MAIN) do ok(f.fieldStrings[n]:IsShown(), n .. " shown") end
        for _, n in ipairs(U.TICKET_MORE) do ok(not f.fieldStrings[n]:IsShown(), n .. " folded away") end
        ok(f.dest:IsShown() and f.destQuest:IsShown(), "地城 / 任務")
        eq(f.dest.gfWidth, f.destQuest.gfWidth, "地城 and 任務 are one size")
        eq(f.pickDungeon, nil, "no 40 px 地城 icon button"); eq(f.pickQuest, nil, "no 40 px 任務 icon button")
        ok(plain(f.destName:GetText()):find("還沒選", 1, true), "nothing chosen yet says so")
        d.dungeon = "smg"; U.drawTicket()
        ok(f.destIcon:IsShown() and plain(f.destName:GetText()):find("血色修道院：墓地", 1, true), "the chosen dungeon in the field")
        eq(f.fieldStrings["職責"]:GetText(), "職責", "職責 for a dungeon")
        for _, r in ipairs({ "t", "h", "d" }) do
            local g = f.roleGroups[r]
            ok(g.icon:IsShown() and g.text:IsShown(), r .. ": icon + number")
            ok(not g.plus:IsShown() and not g.minus:IsShown(), r .. ": no ＋ － on the first look")
        end
        eq(plain(f.roleGroups.t.text._text) .. "," .. plain(f.roleGroups.h.text._text) .. "," .. plain(f.roleGroups.d.text._text), "1,1,3", "the dungeon's own numbers")
        ok(f.startButton:IsShown() and plain(f.startButton:GetText()):find("現在", 1, true), "時段: 現在")
        ok(f.addSlot:IsShown(), "＋時段")
        ok(f.note:IsShown(), "說明")
        ok(f.moreToggle:IsShown() and plain(f.moreToggle:GetText()):find("更多設定", 1, true), "更多設定")
        ok(f.moreSummary:IsShown(), "its one line")
        ok(f.lfgCheck:IsShown() and plain(f.lfgCheck.label._text):find("上架到尋求組隊", 1, true), "上架到尋求組隊")
        ok(f.go:IsShown() and plain(f.go:GetText()):find("開單", 1, true), "開單")
        ok(not f.direct:IsShown() and not f.consent:IsShown(), "錄取 folded")
        for _, b in ipairs(f.tagList) do ok(not b:IsShown(), "tag folded: " .. b.tip) end
        -- Shown buttons on the first look (the theme's X counts too).
        local n = 0
        for _, o in ipairs(wow.allObjects()) do
            if (o._kind == "Button" or o._kind == "CheckButton") and o._parent == f and visible(o) then n = n + 1 end
        end
        ok(n <= 8, "few buttons on the first look: " .. n)
        -- Quests: one 人數.
        d.dungeon = nil; d.quests = { 216 }; U.drawTicket()
        eq(f.fieldStrings["職責"]:GetText(), "人數", "quests: 人數")
        ok(f.roleGroups.any.text:IsShown() and not f.roleGroups.t.icon:IsShown(), "one number")
        ok(not f.roleGroups.any.plus:IsShown(), "its ＋ － in 更多設定")
    end)

    test("GF-UI-O one left line, one row step, one icon size, one button height; nothing overlaps folded or open", function()
        local ns = login()
        local U, O = ns.AdventureUI, ns.OrdersUI
        lfgOn(ns)
        local d = U.openTicket()
        local f = form(ns)
        d.dungeon = "smg"; d.lfg = true; U.drawTicket()
        local X = f.controlX
        local function check(tag)
            local text, n = overlaps(f)
            eq(text, "", tag .. ": no overlaps"); ok(n >= 12, tag .. ": parts " .. n)
            eq(outside(f), "", tag .. ": inside the window")
        end
        check("folded")
        local hFolded = f._h
        ok(hFolded <= 470 - 100, "folded: clearly lower than the old 470 (" .. hFolded .. ")")
        U.setTicketMore(true)
        check("open")
        eq(f._h, hFolded + 3 * O.ROW_STEP, "open: three rows more")
        -- One left line for the controls.
        for _, w in ipairs({ f.destIcon, f.roleGroups.t.icon, f.startButton, f.moreToggle, f.lfgCheck,
            f.roleGroups.t.moreIcon, f.direct, f.tagList[1] }) do
            eq(leftX(w), X, "on the control line: " .. tostring(w.tip or w.fieldNamed or w._kind))
        end
        for n, fs in pairs(f.fieldStrings) do eq(leftX(fs), O.FIELD_X, "field name on one line: " .. n) end
        -- One row step from 說明 down.
        for i = 5, 9 do eq(f.rowY[i - 1] - f.rowY[i], O.ROW_STEP, "row " .. i) end
        eq(f.rowY[1] - f.rowY[2], O.ROW_STEP, "活動 → 職責"); eq(f.rowY[2] - f.rowY[3], O.ROW_STEP, "職責 → 時段")
        -- One icon size, one text button height.
        for _, t in ipairs({ f.destIcon, f.roleGroups.t.icon, f.roleGroups.d.moreIcon, f.direct, f.consent, f.tagList[1], f.tagList[5] }) do
            eq(t._w .. "x" .. t._h, ns.ICON .. "x" .. ns.ICON, "icon size ns.ICON")
        end
        for _, b in ipairs({ f.dest, f.destQuest, f.startButton, f.addSlot, f.moreToggle, f.go, f.roleGroups.t.plus, f.roleGroups.t.minus }) do
            eq(b._h, ns.BUTTON_H, "button height: " .. plain(b._text))
        end
        -- Quests, five slots with the editor open, a long name: still no overlaps.
        d.dungeon = nil; d.quests = { 216 }; U.drawTicket(); check("quests open")
        U.setTicketMore(false); check("quests folded")
        d.dungeon = "smg"; d.quests = {}
        for _ = 2, 5 do U.addSlot(d.slots, function() end) end
        U.openSlotEditor(f, 3)
        check("five slots + editor folded")
        U.setTicketMore(true); check("five slots + editor open")
        f.destName:SetText(string.rep("很長的地城名字", 12)); check("a long name is cut")
    end)

    test("GF-UI-O 更多設定's line: 直接錄取｜無標籤 in grey; other values in the normal colour", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = form(ns)
        d.dungeon = "smg"; U.drawTicket()
        eq(f.moreSummary._text, "直接錄取｜無標籤", "the defaults")
        eq(table.concat(f.moreSummary._color, ","), "0.6,0.6,0.6", "grey")
        d.mode = "c"; U.drawTicket()
        eq(f.moreSummary._text, "團長同意｜無標籤", "團長同意")
        eq(table.concat(f.moreSummary._color, ","), "1,1,1", "the normal colour")
        d.mode = "a"; d.tags = ns.Adventure.TAGS.quest + ns.Adventure.TAGS.voice; U.drawTicket()
        eq(f.moreSummary._text, "直接錄取｜解任務、語音", "tags by name")
        d.tags = 0; d.roles.d = 2; U.drawTicket()
        eq(f.moreSummary._text, "直接錄取｜無標籤｜人數已調整", "other numbers")
        eq(table.concat(f.moreSummary._color, ","), "1,1,1", "not the default")
        d.roles.d = 3; U.drawTicket()
        eq(table.concat(f.moreSummary._color, ","), "0.6,0.6,0.6", "back to the defaults: grey")
        d.dungeon = nil; d.quests = { 216 }; d.size = 4; U.drawTicket()
        eq(f.moreSummary._text, "直接錄取｜無標籤｜人數已調整", "quests: 人數 other than 5")
        U.setTicketMore(true)
        ok(not f.moreSummary:IsShown(), "open: the line steps aside")
        ok(plain(f.moreToggle:GetText()):find("－ 更多設定", 1, true), "the toggle says it folds")
    end)

    test("GF-UI-O open: every setting works (人數 ＋ －, 錄取, 標籤, 說明) and is saved", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local d = U.openTicket()
        local f = form(ns)
        U.setDraftDungeon(d, "smg"); U.drawTicket()
        wow.click(f.moreToggle)
        ok(f.moreOpen, "the toggle opens it")
        wow.click(f.roleGroups.d.minus); eq(d.roles.d, 2, "－")
        wow.click(f.roleGroups.t.plus); eq(d.roles.t, 2, "＋")
        eq(plain(f.roleGroups.t.text._text), "2", "職責 shows the new number"); eq(plain(f.roleGroups.t.moreText._text), "2", "and 更多設定 too")
        wow.click(f.consent); eq(d.mode, "c", "團長同意")
        wow.click(f.tagButtons.farm); eq(d.tags, Adv.TAGS.farm, "連刷")
        f.note:SetText("一起去"); f.note:GetScript("OnTextChanged")(f.note); eq(d.note, "一起去", "說明 is the note")
        wow.click(f.moreToggle)
        ok(not f.moreOpen and not f.consent:IsShown(), "folded again; the values stay")
        eq(d.mode .. "," .. d.tags, "c," .. Adv.TAGS.farm, "kept")
        local id = U.submitTicket()
        ok(id, "開單")
        local v = Adv.get(id)
        eq(v.mode .. "," .. v.tags .. "," .. v.roles.t .. v.roles.h .. v.roles.d .. "," .. v.note,
            "c," .. Adv.TAGS.farm .. ",212,一起去", "saved as before")
    end)

    test("GF-UI-O editing a ticket with other values opens 更多設定 by itself; defaults stay folded", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        local plainId = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "h", note = "" })
        U.openTicket(Adv.get(plainId))
        ok(form(ns).moreOpen == false, "defaults: folded")
        form(ns):Hide(); U.dropDraft("ticket")
        local id = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "h", note = "", mode = "c" })
        U.openTicket(Adv.get(id))
        local f = form(ns)
        ok(f.moreOpen and f.consent:IsShown() and f.consent.selected, "團長同意: open, chosen")
        f:Hide(); U.dropDraft("ticket")
        local id2 = Adv.open({ dungeon = "smg", roles = { t = 1, h = 1, d = 3 }, leaderRole = "h", note = "", tags = Adv.TAGS.slow })
        U.openTicket(Adv.get(id2)); ok(form(ns).moreOpen, "a tag: open")
        form(ns):Hide(); U.dropDraft("ticket")
        local id3 = Adv.open({ dungeon = "smg", roles = { t = 1, h = 2, d = 2 }, leaderRole = "h", note = "" })
        U.openTicket(Adv.get(id3)); ok(form(ns).moreOpen, "other numbers: open")
        form(ns):Hide(); U.dropDraft("ticket")
        U.openTicket(); ok(form(ns).moreOpen == false, "a new ticket: folded")
    end)

    test("GF-UI-O folding makes no frames and adds no events, timers or OnUpdate", function()
        local ns = login()
        local U = ns.AdventureUI
        local d = U.openTicket()
        local f = form(ns)
        d.dungeon = "smg"; U.drawTicket()
        U.setTicketMore(true); U.setTicketMore(false) -- every part made once
        local before = #wow.allObjects()
        for _ = 1, 10 do U.setTicketMore(true); U.setTicketMore(false); U.setTicketMore() end
        eq(#wow.allObjects(), before, "no new frames, textures or texts")
        eq(f._scripts.OnUpdate, nil, "no OnUpdate on the form")
        local src = readAll(ADDON_DIR .. "/AdventureUI.lua")
        local a = src:find("GF-UI-O (owner 2026-11-28", 1, true)
        local b = src:find("function UI.draft() return draft end", 1, true)
        ok(a and b and b > a, "the form's code found")
        local part = src:sub(a, b)
        for _, bad in ipairs({ "RegisterEvent", "C_Timer", "OnUpdate", "CreateFrame" }) do
            ok(not part:find(bad, 1, true), "no " .. bad .. " in the form's code")
        end
    end)

    test("GF-UI-O drafts, 重開 and the red field work as before", function()
        local ns = login()
        local U, Adv = ns.AdventureUI, ns.Adventure
        -- A draft comes back, with 更多設定 open when it holds other values.
        local d = U.openTicket()
        local f = form(ns)
        U.setDraftDungeon(d, "smg"); d.mode = "c"
        f.note:SetText("草稿說明"); f.note:GetScript("OnTextChanged")(f.note)
        f:Hide()
        local d2 = U.openTicket()
        ok(d2 == d, "the same draft")
        eq(f.note:GetText(), "草稿說明", "說明 back in its box")
        ok(f.moreOpen, "團長同意 in the draft: 更多設定 open")
        -- The red 活動.
        d2.dungeon = nil; U.drawTicket()
        local _, why = U.submitTicket()
        eq(why, "no-destination", "nothing chosen")
        eq(table.concat(f.fieldStrings["活動"]._color, ","), "1,0.3,0.3", "活動 red")
        ok(f.fieldMark:IsShown(), "✗")
        d2.dungeon = "smg"; U.drawTicket()
        eq(table.concat(f.fieldStrings["活動"]._color, ","), "1,0.82,0", "fixed: gold")
        local id = U.submitTicket()
        ok(id, "saved")
        -- 重開: the same contents, a new 現在, 更多設定 open for 團長同意.
        local v = Adv.get(id)
        local r = U.openTicket(v, "reopen")
        eq(r.reopenOf, id, "重開 of it"); eq(r.editId, nil, "a new one")
        ok(r.slots[1].now and #r.slots == 1, "現在")
        eq(r.note, "草稿說明", "same 說明")
        ok(f.moreOpen, "團長同意: open")
    end)
end
