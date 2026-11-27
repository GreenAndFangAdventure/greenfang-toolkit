-- GF-UI-I: the owner's 0.16.2 in-game report — 調貨所 list width, divider
-- and ＋刊登; 臨時黑箱 under the sub-tab row and page switching; the roster
-- member card in three sections with fixed columns; the 刊登 item box takes a
-- link or an ItemID with a preview that waits for item data.
-- Offline only (a small fake game below); not checked in the Forever client.
-- Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR

    local A_B = "0000-0000000B"
    local PEER_B = "測試乙-測試伺服器"
    local PATTERN, ROBE, CLOTH, LATE, NONE = 9201, 9202, 9203, 9204, 9205
    local G
    local function installGame(opts)
        G = { bag = opts.bag or {}, asked = {}, exists = {}, items = {
            [PATTERN] = { name = "圖樣：測試長袍", classID = 9, sub = 2 },
            [ROBE] = { name = "測試長袍", classID = 4, sub = 1 },
            [CLOTH] = { name = "測試布", classID = 7, sub = 5 },
        } }
        C_QuestLog = { IsQuestFlaggedCompleted = function() return false end, IsOnQuest = function() return false end }
        C_Container = {
            GetContainerNumSlots = function(bag) return bag == 0 and 20 or 0 end,
            GetContainerItemInfo = function(bag, slot)
                local it = bag == 0 and G.bag[slot]
                if not it then return nil end
                return { itemID = it[1], stackCount = it[2], isBound = it[3] == true, isLocked = false, iconFileID = 134939 }
            end,
        }
        GetItemInfo = function(id)
            local it = G.items[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1, "", "", 20, "", 134939,
                0, it.classID, it.sub or 0, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return G.items[id] and 134939 or nil end,
            GetItemNameByID = function(id) return G.items[id] and G.items[id].name or nil end,
            RequestLoadItemDataByID = function(id) G.asked[id] = true end,
            DoesItemExistByID = function(id) if G.exists[id] == false then return false end return true end,
            IsItemDataCachedByID = function(id) return G.items[id] ~= nil end, -- GF-009-13
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
        installGame(opts)
        local ns = wow.loadAddon(ADDON_DIR, opts.saved)
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
    local function from(ns, sender, text) return ns.Share.onMessage("GFTKS", text, "GUILD", sender) end
    local function visible(o)
        local f = o
        while f do
            if f._shown == false then return false end
            f = f._parent
        end
        return true
    end

    ---------------------------------------------------------------------------
    -- 1. 調貨所: the list takes the room when the right side has nothing
    ---------------------------------------------------------------------------

    test("GF-UI-I 調貨所: nothing on the right = the list is wide and the divider is gone; 刊登 at the list's left edge (GF-UI-K)", done(function()
        local ns = login({})
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        local F = ns.Framework
        UI.setTab("need")
        eq(#UI.state.items, 0, "nothing listed")
        ok(UI.state.wide, "wide")
        eq(UI.header._fixedWidth, UI.LIST_W_WIDE, "header across the page")
        eq(UI.statePanel._fixedWidth, UI.LIST_W_WIDE, "state panel across the page")
        ok(not UI.divider:IsShown(), "no divider")
        eq(UI.LIST_X + UI.LIST_W_WIDE, F.PANEL_WIDTH - UI.LIST_X, "the same margin left and right")
        local pt = UI.postButton._points[1]
        -- GF-UI-K (owner): 「刊登」 with no ＋, at the list's left edge over the header.
        eq(pt[4], UI.LIST_X, "刊登 starts at the list's left edge")
        eq(pt[5], UI.TOOL_Y, "on the tool row, over the column header")
        eq(UI.postButton._text, "刊登", "its name")
        -- The 時效 header cell moves to the right end; 物品 gets the room.
        local fresh = UI.header.cells[4]._points[1]
        eq(fresh[4] + UI.COL.fresh.w, UI.LIST_W_WIDE - (UI.LIST_W - UI.COL.fresh.x - UI.COL.fresh.w), "時效 at the right end")
        eq(UI.header.cells[1]._fixedWidth, UI.COL.name.x + UI.COL.name.w - UI.COL.icon.x + UI.LIST_W_WIDE - UI.LIST_W, "物品 wider")
    end))

    test("GF-UI-I 調貨所: a row with matches = list and detail side by side; the divider stays inside the page", done(function()
        local ns = login({ bag = { { CLOTH, 3 } } })
        local L = ns.SupplyListings
        ok(L.create({ direction = "need", itemID = PATTERN, quantity = 1, days = 14, note = "" }), "my need")
        local t = T0() - 60
        from(ns, PEER_B, vMsg(ns, A_B, "L", t, L.encode({ { id = 1, direction = "offer", category = "recipe", itemID = PATTERN,
            quantity = 1, createdAt = t, expiresAt = t + 86400, rev = 1, note = "" } })))
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.setTab("need")
        ok(UI.state.items[1] and UI.hasDetail(UI.state.items[1]), "a row with a provider")
        ok(not UI.state.wide, "narrow: the detail is used")
        ok(UI.divider:IsShown(), "divider between them")
        local pt = UI.divider._points[1]
        eq(#UI.divider._points, 1, "one anchor (no bottom anchor past the page)")
        eq(pt[1] .. ">" .. pt[3], "TOPLEFT>TOPLEFT", "top-left anchored")
        ok(-pt[5] + UI.divider._h <= ns.Framework.PANEL_HEIGHT, "ends inside the page: " .. (-pt[5] + UI.divider._h))
        eq(-pt[5] + UI.divider._h, -(UI.TOP - UI.ROWS * UI.ROW_H), "ends at the list's bottom")
        local bp = UI.postButton._points[1]
        eq(bp[4], UI.LIST_X, "GF-UI-K: 刊登 stays at the list's left edge")
        ok(ns.Framework.panel("supply") and UI.detail and UI.detailHeader:IsShown(), "detail header shown")
        -- 我的刊登: a listing always has its buttons on the right.
        UI.setTab("mine")
        ok(not UI.state.wide, "my listing: narrow")
        ok(UI.detail.edit:IsShown(), "修改 shown")
    end))

    test("GF-UI-I 調貨所: 手動刊登 is a sharing switch, not a source filter (so not renamed)", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        eq(UI.manualBox.label._text, "手動刊登", "name kept")
        local l = L.create({ direction = "need", itemID = PATTERN, quantity = 1, days = 14, note = "" })
        ok(l, "listed")
        -- GF-009-15: the 「關」 cell of the 「開｜關」 pair.
        UI.manualBox.cells.off._scripts.OnClick(UI.manualBox.cells.off)
        eq(ns.Supply.manualOn(), false, "off")
        -- Off: my listings are no longer published (an empty snapshot), the 刊登 button is off.
        local rec = ns.Share.get(ns.Share.selfAuthor(), L.GROUP)
        eq(rec and rec.v, "", "published snapshot emptied")
        eq(UI.postButton.disabled, true, "刊登 cannot be pressed")
    end))

    ---------------------------------------------------------------------------
    -- 2. 臨時黑箱: under the sub-tab row; switching pages hides the other page
    ---------------------------------------------------------------------------

    test("GF-UI-I 臨時黑箱: the title and the text beside it start below the sub-tab row; switching pages hides the other", done(function()
        local ns = login({})
        local F = ns.Framework
        F.open("bank")
        local p = F.panel("bank")
        local line = -(F.SUBTAB_Y - ns.BUTTON_H - 4) - F.SUBTAB_H -- the sub-tab line, from the page top
        local c = ns.BankUI.controls
        for _, k in ipairs({ "title", "role", "status", "listHead", "scopeHead" }) do
            local pt = c[k]._points[1]
            ok(-pt[5] >= line + 8, k .. " below the sub-tab line with a gap (" .. -pt[5] .. " vs " .. line .. ")")
        end
        local pt = c.stock._points[1]
        ok(-pt[5] + c.stock._h <= F.PANEL_HEIGHT, "庫存 inside the page")
        -- Switch 臨時黑箱 -> 調貨所 -> 臨時黑箱.
        F.open("supply")
        ok(not p:IsShown(), "黑箱 page hidden")
        local leaks = {}
        for _, o in ipairs(wow.allObjects()) do
            local f = o
            while f and f ~= p do f = f._parent end
            if f == p and visible(o) then leaks[#leaks + 1] = tostring(o._text or o._kind) end
        end
        eq(table.concat(leaks, ","), "", "nothing of 黑箱 still visible")
        ok(F.panel("supply"):IsShown(), "調貨所 shown")
        F.open("bank")
        ok(p:IsShown() and not F.panel("supply"):IsShown(), "and back")
    end))

    ---------------------------------------------------------------------------
    -- 3. The roster member card
    ---------------------------------------------------------------------------

    local LONG_NAME = "超長名字的綠皮獠牙職工甲"
    local LONG_RANK = "綠皮獠牙冒險事務所資深外勤顧問兼物資總管"
    local function cardRow(ns, profs)
        local row = CreateFrame("Frame", nil, UIParent)
        row:SetSize(800, 36)
        row:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -300)
        row.member = { name = LONG_NAME .. "-測試伺服器", classToken = "WARRIOR", class = "戰士", level = 60,
            guildRank = LONG_RANK, guid = "Player-0000-0000000B", raceID = 2 }
        row.memberName = LONG_NAME
        row.memberGuid = "Player-0000-0000000B"
        row.detail = { professions = profs }
        return row
    end
    local FIVE = {
        { name = "鍛造", skillLineID = 164, rank = 300, max = 300 },
        { name = "採礦", skillLineID = 186, rank = 75, max = 150 },
        { name = "烹飪", skillLineID = 185, rank = 1, max = 75 },
        { name = "急救", skillLineID = 129, rank = 225, max = 300 },
        { name = "釣魚", skillLineID = 356, rank = 150, max = 225 },
    }

    test("GF-UI-I roster card: 角色 / 職責 / 專業; long name and rank shown in full; five professions in fixed columns", function()
        wow.reset({})
        local ns = wow.login(ADDON_DIR)
        local row = cardRow(ns, FIVE)
        local card = ns.UI.showRowTooltip(row, nil)
        ok(card == ns.UI.rosterCard() and card:IsShown(), "the card")
        eq(card.head.char._text .. card.head.role._text .. card.head.prof._text, "角色職責專業", "three sections")
        eq(card.name._text, LONG_NAME, "name")
        local cc = ns.Icons.classColor("WARRIOR")
        ok(card.name._color and card.name._color[1] == cc[1] and card.name._color[3] == cc[3], "class colour")
        eq(card.rank._text, "階級　" .. LONG_RANK, "the whole rank")
        local inner = card._fixedWidth - 2 * ns.UI.CARD.pad
        ok(wow.textWidth(card.name._text, ns.TITLE_FONT) <= inner, "name fits the card")
        ok(card.rank._wordWrap ~= false, "the rank wraps instead of being cut")
        ok(wow.textWidth(card.rank._text, ns.LABEL_FONT) <= inner * 2, "rank: at most two lines")
        -- 職責: the 主職責 line is there (unknown member: words, no icon).
        ok(card.mainText._text:find("^主職責 "), "主職責 line: " .. card.mainText._text)
        -- 專業: five rows; columns never overlap; numbers right-aligned in their columns.
        local shown = 0
        local C = ns.UI.CARD
        local lastY
        for i, r in ipairs(card.rows) do
            if r.name:IsShown() then
                shown = shown + 1
                local n, s, rc = r.name._points[1], r.skill._points[1], r.recipes._points[1]
                eq(n[5], s[5], "row " .. i .. ": same line")
                eq(s[5], rc[5], "row " .. i .. ": same line")
                ok(n[4] + r.name._fixedWidth <= s[4], "row " .. i .. ": name before 技能")
                ok(wow.textWidth(r.name._text, ns.LABEL_FONT) <= r.name._fixedWidth, "row " .. i .. ": name not cut")
                ok(s[4] + C.skillW <= rc[4], "row " .. i .. ": 技能 before 配方")
                ok(rc[4] + C.recipeW <= card._fixedWidth - C.pad, "row " .. i .. ": inside the card")
                eq(r.skill.gfAlign, "RIGHT", "技能 right-aligned")
                eq(r.recipes.gfAlign, "RIGHT", "配方 right-aligned")
                if i == 1 then eq(s[4], card.skillHead._points[1][4], "under 技能") end
                if lastY then ok(n[5] < lastY, "rows go down") end
                lastY = n[5]
                -- Every row's columns start at the same x.
                eq(s[4], card.rows[1].skill._points[1][4], "技能 column fixed")
                eq(rc[4], card.rows[1].recipes._points[1][4], "配方 column fixed")
            end
        end
        eq(shown, 5, "five professions")
        ok(-lastY + C.line <= card._h, "the card is tall enough")
        local text = ns.UI.rosterCardText()
        ok(text:find("鍛造 300 / 300", 1, true) and text:find("釣魚 150 / 225", 1, true), text)
    end)

    test("GF-UI-I roster card: one tooltip at a time (card, icon tooltip, leaving the row)", function()
        wow.reset({})
        local ns = wow.login(ADDON_DIR)
        ns.Framework.open("roster")
        local row
        for _, o in ipairs(wow.allObjects()) do
            if o.profSlots and o.memberName == PEER_B and visible(o) then row = o end
        end
        ok(row, "the roster row of 測試乙")
        local slot
        for _, s in ipairs(row.profSlots) do if s.entry then slot = s; break end end
        ok(slot, "a profession icon")
        ns.UI.showRowTooltip(row, nil)
        ok(ns.UI.rosterCard():IsShown() and not GameTooltip._shown, "card only")
        ns.UI.showRowTooltip(row, slot)
        ok(GameTooltip._shown and not ns.UI.rosterCard():IsShown(), "icon tooltip only")
        ns.UI.showRowTooltip(row, nil)
        ok(ns.UI.rosterCard():IsShown() and not GameTooltip._shown, "card again, icon tooltip gone")
        row._scripts.OnLeave(row)
        ok(not ns.UI.rosterCard():IsShown() and not GameTooltip._shown, "leaving: none")
    end)

    ---------------------------------------------------------------------------
    -- 4. The item box: a link or an ItemID, with a preview
    ---------------------------------------------------------------------------

    test("GF-UI-I item box: links, item:123 and typed ItemIDs are read; other text is not guessed", done(function()
        local ns = login({})
        local L = ns.SupplyListings
        local function p(t) local id, k = L.parseItemInput(t); return tostring(id) .. "/" .. tostring(k) end
        eq(p("|cffffffff|Hitem:9201::::::::|h[圖樣：測試長袍]|h|r"), "9201/link", "a chat link")
        eq(p("item:9201"), "9201/link", "item:123")
        eq(p(" 9201 "), "9201/id", "digits")
        eq(p("#9201"), "9201/id", "#digits")
        eq(p(""), "nil/empty", "empty")
        eq(p("圖樣"), "nil/bad", "a name is not guessed here")
        eq(p("0"), "nil/bad", "zero")
        eq(p("99999999999"), "nil/bad", "too large")
        eq(L.itemFromText("9201"), nil, "itemFromText stays strict (chat, notes)")
    end))

    test("GF-UI-I item box: preview ready / loading (then filled when the data arrives) / missing; a pattern lists itself", done(function()
        local ns = login({})
        ns.Framework.open("supply")
        local UI = ns.SupplyUI
        UI.openForm()
        local f = UI.form()
        -- Ready: a pattern by its ItemID: the pattern, not what it makes.
        UI.formFromText(tostring(PATTERN))
        eq(UI.formState.itemID, PATTERN, "the pattern's own ID")
        eq(UI.formState.preview, "ready", "ready")
        eq(f.itemName._text, "圖樣：測試長袍", "its name")
        eq(UI.formState.category, "recipe", "類型 from classID 9")
        -- Loading: not in the cache yet.
        UI.formFromText(tostring(LATE))
        eq(UI.formState.preview, "loading", "loading")
        ok(G.asked[LATE], "asked the server")
        eq(f.msg._text, "物品資料載入中，請稍後再試", "says so")
        G.items[LATE] = { name = "測試晚到的布", classID = 7, sub = 5 }
        wow.fire("GET_ITEM_INFO_RECEIVED", LATE, true)
        eq(UI.formState.preview, "ready", "filled in when the data arrived")
        eq(f.itemName._text, "測試晚到的布", "name")
        eq(f.msg._text, "", "message cleared")
        -- No answer in time: GF-009-13 calls it a timeout (it was "missing").
        UI.formFromText(tostring(NONE))
        eq(UI.formState.preview, "loading", "waiting")
        wow.advance(ns.SupplyListings.LOAD_WAIT + 1)
        eq(UI.formState.preview, "timeout", "no answer: timeout")
        eq(f.msg._text, UI.PREVIEW_TEXT.timeout, "物品資料逾時")
        -- The client says it does not exist: missing at once.
        G.exists[NONE + 1] = false
        UI.formFromText(tostring(NONE + 1))
        eq(UI.formState.preview, "missing", "missing at once")
        -- Text that is neither a link nor an ID.
        UI.formFromText("測試")
        eq(f.msg._text, UI.PREVIEW_TEXT.bad, "asks for a link or an ID")
        -- List the pattern by ID: 徵求, itemID = the pattern.
        UI.formFromText(tostring(PATTERN))
        local l = UI.submitForm()
        ok(l and l.itemID == PATTERN and l.direction == "need" and l.category == "recipe", "徵求 of the pattern itself")
    end))
end
