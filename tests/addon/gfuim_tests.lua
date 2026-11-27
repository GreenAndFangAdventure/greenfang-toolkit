-- GF-UI-M: the owner's 0.16.10 screenshots — 調貨看板's notes in full on the
-- right, the roster's bottom bar (a long name ran under 密語, the last list
-- line was cut in half) and the personnel file's own portrait.
-- Offline only (a small fake game below); not checked in the Forever client.
-- Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_B, A_C, A_D = "0000-0000000B", "0000-0000000C", "0000-0000000D"
    local PEER_B = "測試乙-測試伺服器"
    local CLOTH = 9102
    local LONG_NOTE = "一組二十個可以分批交貨，晚上九點後在奧格瑪銀行前面等，請先密語確認數量謝謝"

    local function installGame()
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
        GetItemInfo = function(id)
            if id ~= CLOTH then return nil end
            return "測試布", "|cffffffff|Hitem:" .. id .. "::::::::|h[測試布]|h|r", 1, 1, 1, "商品", "布料", 20, "", 134939,
                0, 7, 5, 0
        end
        C_Item = {
            GetItemIconByID = function(id) return id == CLOTH and 134939 or nil end,
            GetItemNameByID = function(id) return id == CLOTH and "測試布" or nil end,
            RequestLoadItemDataByID = function() end,
            IsItemDataCachedByID = function(id) return id == CLOTH end,
        }
        ChatFrame_SendTellWithMessage = function() end
    end
    local function removeGame()
        C_QuestLog, C_Container, GetItemInfo, C_Item, ChatFrame_SendTellWithMessage = nil, nil, nil, nil, nil
    end
    local function done(fn) return function() local okRun, err = pcall(fn); removeGame(); if not okRun then error(err, 0) end end end

    local function login(opts)
        opts = opts or {}
        wow.reset(opts)
        installGame()
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
        ns.SupplyCatalogData = nil
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.fire("PLAYER_LOGIN")
        wow.fire("PLAYER_ENTERING_WORLD")
        wow.advance(70)
        wow.state.sent = {}
        return ns
    end
    local function T0() return math.floor(wow.state.now) end
    local function vMsg(ns, a, g, t, v)
        return "S1~V~" .. a .. "~" .. g .. "~" .. ns.Share.b36(t) .. "~" .. ns.Share.hash(v) .. "~" .. v
    end
    local function from(ns, text) return ns.Share.onMessage("GFTKS", text, "GUILD", PEER_B) end
    local function listing(id, note, t)
        return { id = id, direction = "offer", category = "material", itemID = CLOTH, quantity = 2,
            createdAt = t, expiresAt = t + 7 * 86400, rev = 1, note = note or "" }
    end
    -- B: a long note and a price; C: no note, 免費; D: a short note, no terms (an old AddOn).
    local function threeOffers(ns)
        local L = ns.SupplyListings
        local t = T0() - 60
        local b, c, d = listing(1, LONG_NOTE, t), listing(1, "", t), listing(1, "送新人", t)
        b.terms, b.price, c.terms = "price", 12345, "free"
        from(ns, vMsg(ns, A_B, "L", t, L.encode({ b })))
        from(ns, vMsg(ns, A_B, "M", t, L.encodeTerms({ b })))
        from(ns, vMsg(ns, A_C, "L", t, L.encode({ c })))
        from(ns, vMsg(ns, A_C, "M", t, L.encodeTerms({ c })))
        from(ns, vMsg(ns, A_D, "L", t, L.encode({ d })))
        ns.Supply.invalidate()
    end
    local function openBoard(ns)
        local UI = ns.SupplyUI
        ns.Framework.open("supply")
        UI.setTab("guild")
        local idx
        for i, it in ipairs(UI.state.items) do if it.itemID == CLOTH then idx = i end end
        ok(idx, "cloth on 調貨看板")
        UI.select(idx)
        return UI
    end
    local function shownRows(UI)
        local out = {}
        for _, r in ipairs(UI.detailRowList()) do if r:IsShown() then out[#out + 1] = r end end
        table.sort(out, function(a, b) return a.gfTop > b.gfTop end)
        return out
    end
    local function byName(rows, name)
        for _, r in ipairs(rows) do if r.name._text == name then return r end end
    end

    ---------------------------------------------------------------------------
    -- 1. 調貨看板: the notes in full on the right
    ---------------------------------------------------------------------------

    test("GF-UI-M 1 調貨看板: three people, a long note in full under its row, no note takes no room, rows never overlap", done(function()
        local ns = login()
        threeOffers(ns)
        local UI = openBoard(ns)
        local rows = shownRows(UI)
        eq(#rows, 3, "three people")
        local b, c, d = byName(rows, "測試乙"), byName(rows, "測試丙"), byName(rows, "測試丁")
        ok(b and c and d, "B, C and D")
        -- B: the note in full, wrapping, after the note icon; the terms in the 條件 cell.
        eq(b.note._text, "備註：" .. LONG_NOTE, "B's note, every character")
        ok(b.note:IsShown() and b.note._wordWrap == true, "shown and wraps (not cut)")
        eq(b.note._fixedWidth, UI.NOTE_W, "the detail's width")
        ok(b.noteIcon:IsShown(), "the note icon in front of it")
        ok(b.gfHeight >= UI.MAIN_H + b.gfNoteH, "the row grew for the note")
        ok(b.gfNoteH >= 2 * UI.NOTE_LINE_H, "a long note: two lines or more")
        eq(b.src._text, "1金23銀45銅", "B's price")
        eq(b.src._wordWrap, true, "條件 may take two lines")
        -- C: no note: nothing under the row, 40 px.
        ok(not c.note:IsShown() and not c.noteIcon:IsShown(), "C: no note line, no icon")
        eq(c.gfHeight, UI.MAIN_H, "C keeps 40 px")
        eq(c.src._text, "免費", "C: 免費")
        -- D: a short note, 未標示.
        eq(d.note._text, "備註：送新人", "D's note"); eq(d.src._text, "未標示", "D: 未標示")
        -- Stacked: each row starts under the one before (its own height), all above the bottom.
        for i = 2, #rows do
            ok(rows[i].gfTop <= rows[i - 1].gfTop - rows[i - 1].gfHeight - UI.ROW_GAP + 0.01,
                "row " .. i .. " under row " .. (i - 1))
        end
        local last = rows[#rows]
        ok(last.gfTop - last.gfHeight >= UI.DETAIL_BOTTOM, "inside the page")
        ok(not UI.detail.more:IsShown(), "everyone fits: no 「還有」")
        -- The tooltip still names the person in full and has the note.
        b:GetScript("OnEnter")(b)
        eq(GameTooltip._lines[1].text, "測試乙", "the name first")
        local all = {}
        for _, ln in ipairs(GameTooltip._lines) do all[#all + 1] = ln.text end
        ok(table.concat(all, "\n"):find(LONG_NOTE, 1, true), "the note in the tooltip too")
    end))

    test("GF-UI-M 1 調貨看板: when the rows do not fit, 「還有 N 位」 and the wheel brings them up; the same pooled rows", done(function()
        local ns = login()
        threeOffers(ns)
        local UI = openBoard(ns)
        local pool = #UI.detailRowList()
        local oldBottom = UI.DETAIL_BOTTOM
        local okRun, err = pcall(function()
            -- Room for about two rows only.
            UI.DETAIL_BOTTOM = UI.DETAIL_TOP - 2 * UI.MAIN_H - UI.MORE_H - 20
            UI.drawDetail()
            local first = shownRows(UI)
            ok(#first >= 1 and #first < 3, "not all three: " .. #first)
            ok(UI.detail.more:IsShown(), "「還有」 shown")
            ok(UI.detail.more._text:find("還有 " .. (3 - #first) .. " 位", 1, true), UI.detail.more._text)
            local topName = first[1].name._text
            UI.scrollDetail(-1)
            eq(UI.state.detailOffset, 1, "one down")
            local after = shownRows(UI)
            ok(after[1].name._text ~= topName, "the next person on top")
            -- To the end; then no further.
            UI.scrollDetail(-1); UI.scrollDetail(-1); UI.scrollDetail(-1)
            local endOffset = UI.state.detailOffset
            ok(endOffset <= 2, "stops at the last person")
            ok(not UI.detail.more:IsShown(), "the last one in view: no 「還有」")
            UI.scrollDetail(5)
            eq(UI.state.detailOffset, 0, "back to the top")
            ok(#UI.detailRowList() <= math.max(pool, UI.DETAIL_ROWS), "no new rows per scroll")
            -- A new item starts at the top.
            UI.scrollDetail(-1)
            UI.select(UI.state.selected)
            eq(UI.state.detailOffset, 0, "select: top again")
        end)
        UI.DETAIL_BOTTOM = oldBottom
        if not okRun then error(err, 0) end
    end))

    test("GF-UI-M 1 我的刊登: my own long note wraps in full right of 備註; no note: only 交易條件", done(function()
        local ns = login()
        local L, UI = ns.SupplyListings, ns.SupplyUI
        ns.Framework.open("supply")
        local l = L.create({ direction = "offer", itemID = CLOTH, quantity = 3, days = 7, terms = "negotiable", note = LONG_NOTE })
        ok(l, "my listing")
        UI.setTab("mine")
        UI.select(1)
        local rows = shownRows(UI)
        eq(#rows, 2, "交易條件 and 備註")
        eq(rows[1].name._text, "交易條件"); eq(rows[1].what._text, "面議")
        eq(rows[2].name._text, "備註")
        eq(rows[2].note._text, LONG_NOTE, "the note in full")
        ok(rows[2].note._wordWrap and rows[2].note:IsShown(), "wraps")
        eq(rows[2].note._points[1][4], UI.LISTING_VALUE_X, "right of its label")
        ok(rows[2].gfTop <= rows[1].gfTop - rows[1].gfHeight - UI.ROW_GAP + 0.01, "under 交易條件")
        -- Edited to no note: the 備註 line goes.
        L.update(l.id, { direction = "offer", itemID = CLOTH, quantity = 3, days = 7, terms = "negotiable", note = "" })
        UI.refresh()
        UI.select(1)
        eq(#shownRows(UI), 1, "only 交易條件")
    end))

    ---------------------------------------------------------------------------
    -- 2. 職工名冊: the bottom bar and the list's last row
    ---------------------------------------------------------------------------

    test("GF-UI-M 2 名冊: a long name stays left of 密語 (cut with 「…」), the list shows whole rows above the bar", function()
        local roster = wow.defaultRoster()
        roster[4].name = "很長很長的牛頭人德魯伊名-測試伺服器"
        roster[5] = { name = "非常非常非常非常長的名字測試-測試伺服器", rank = "會員", level = 20, class = "戰士",
            classToken = "WARRIOR", zone = "奧格瑪", online = true, guid = "Player-0000-0000000E" }
        wow.reset({ roster = roster })
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        local UI = ns.UI
        local bar = UI.actionBar
        for _, name in ipairs({ roster[4].name, roster[5].name }) do
            local row
            for _, r in ipairs(UI.rows()) do if r:IsShown() and r.memberName == name then row = r end end
            ok(row, "row " .. name)
            row._scripts.OnMouseUp(row, "LeftButton")
            eq(bar.name._text, ns.shortName(name), "the bar names the member")
            eq(bar.name._fixedWidth, UI.BAR_NAME_W, "the name has its own width")
            local first
            for _, b in ipairs(bar.buttons) do if b:IsShown() and (not first or b.flowX < first.flowX) then first = b end end
            ok(first, "buttons shown")
            ok(10 + bar.name:GetStringWidth() + 8 <= first.flowX, "the name ends before " .. tostring(first._text))
        end
        ok(bar.name:IsTruncated(), "a name longer than 12 characters ends in 「…」")
        ok(UI.BAR_NAME_W >= ns.labelWidth("很長很長的牛頭人德魯伊名") - 6, "12 characters fit")
        -- Whole rows: the list's height is a multiple of the row height; the bar is under it.
        local h = ns.Framework.PANEL_HEIGHT + UI.LIST_TOP - UI.LIST_BOTTOM
        eq(h % ns.PAGE_ROW, 0, "whole rows: " .. h)
        eq(h / ns.PAGE_ROW, UI.LIST_ROWS, "12 rows")
        ok(UI.LIST_BOTTOM - 6 <= UI.LIST_BOTTOM and UI.LIST_BOTTOM - 6 - 44 >= UI.BOTTOM_Y + ns.BUTTON_H,
            "the bar between the list and the bottom row")
    end)

    ---------------------------------------------------------------------------
    -- 3. 職工檔案: the character's own portrait
    ---------------------------------------------------------------------------

    test("GF-UI-M 3 職工檔案: the own portrait (SetPortraitTexture); without it or on an error, the race head / class icon", function()
        local ns = login()
        local Ch = ns.Character
        local calls = {}
        local oldSet, oldExists = rawget(_G, "SetPortraitTexture"), rawget(_G, "UnitExists")
        local fail = false
        local okRun, err = pcall(function()
            SetPortraitTexture = function(tex, unit)
                if fail then error("no portrait") end
                calls[#calls + 1] = unit; tex._portrait = unit
            end
            SlashCmdList.GREENFANGTOOLKIT("character")
            local tex = Ch.portraitTexture
            eq(Ch.portrait, "unit", "the own portrait")
            eq(tex._portrait, "player", "of the player"); eq(calls[#calls], "player", "asked for player")
            ok(tex:IsShown(), "shown")
            -- An error: the GF-UI-K fallback (no atlas here: the class icon).
            fail = true
            Ch.refresh()
            eq(Ch.portrait, "class", "error: class icon")
            fail = false
            -- No unit yet: the fallback too.
            UnitExists = function() return false end
            Ch.refresh()
            eq(Ch.portrait, "class", "no unit: class icon")
            UnitExists = function() return true end
            Ch.refresh()
            eq(Ch.portrait, "unit", "back to the own portrait")
            -- No API at all.
            SetPortraitTexture = nil
            Ch.refresh()
            eq(Ch.portrait, "class", "no API: class icon")
            local pr = ns.Probe.portraits()
            eq(pr.unitPortrait, "no", "probe: no API"); eq(pr.shown, "class", "probe: what the page shows")
        end)
        SetPortraitTexture, UnitExists = oldSet, oldExists
        if not okRun then error(err, 0) end
    end)

    test("GF-UI-M 3 職工檔案: UNIT_PORTRAIT_UPDATE for the player redraws, only while the page is shown and out of combat", function()
        local ns = login()
        local Ch = ns.Character
        local oldSet = rawget(_G, "SetPortraitTexture")
        local n = 0
        local okRun, err = pcall(function()
            SetPortraitTexture = function() n = n + 1 end
            SlashCmdList.GREENFANGTOOLKIT("character")
            local base, redraws = n, Ch.portraitRedraws
            wow.fire("UNIT_PORTRAIT_UPDATE", "player")
            eq(n, base + 1, "player: drawn again"); eq(Ch.portraitRedraws, redraws + 1, "counted")
            wow.fire("UNIT_PORTRAIT_UPDATE", "target")
            eq(n, base + 1, "another unit: nothing")
            wow.fire("PORTRAITS_UPDATED")
            eq(n, base + 2, "all portraits: drawn again")
            wow.setCombat(true)
            wow.fire("UNIT_PORTRAIT_UPDATE", "player")
            eq(n, base + 2, "in combat: nothing")
            wow.setCombat(false)
            ns.Framework.open("roster")
            wow.fire("UNIT_PORTRAIT_UPDATE", "player")
            eq(n, base + 2, "page not shown: nothing")
            local pr = ns.Probe.portraits()
            eq(pr.unitPortrait, "yes", "probe: the API is there"); eq(pr.shown, "unit", "probe: the own portrait")
        end)
        SetPortraitTexture = oldSet
        if not okRun then error(err, 0) end
    end)
end
