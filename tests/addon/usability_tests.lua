-- GF-002-E (0.12.3): the owner's 0.12.2 screenshots. Bigger windows and
-- fonts, no name broken onto two lines or cut, icons that match their
-- meaning, ESC closes the top window first, the recipe page shows the fee
-- and filters by it, 下單 / ＋下單 / 我的服務 are plain buttons.
-- Made-up data only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local shareLogin, shareFrom, rMsg, leatherWindow = T.shareLogin, T.shareFrom, T.rMsg, T.leatherWindow
    local PEER, A_PEER, A_THIRD = T.PEER, T.A_PEER, T.A_THIRD
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
    local function under(o, root)
        local f = o
        while f do
            if f == root then return true end
            f = f._parent
        end
        return false
    end
    local function plain(t) return (tostring(t or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("%s", "")) end

    -- Every shown name / field name under root that is cut, could wrap, or uses the small font.
    local function badTexts(root)
        local out = {}
        for _, o in ipairs(wow.allObjects()) do
            if o._kind == "FontString" and visible(o) and under(o, root) and plain(o._text) ~= "" then
                if o:IsTruncated() then out[#out + 1] = "cut:" .. plain(o._text) end
            end
            if o._kind == "Button" and visible(o) and under(o, root) and o.label and o.label._shown and plain(o.label._text) ~= "" then
                local l = o.label
                if (l._fixedWidth or 0) > 0 then out[#out + 1] = "width:" .. plain(l._text) end
                if l._wordWrap ~= false then out[#out + 1] = "wrap:" .. plain(l._text) end
                if tostring(l._font or ""):find("Small") then out[#out + 1] = "small:" .. plain(l._text) end
            end
        end
        for _, list in ipairs({ root.fieldStrings or {} }) do
            for name, l in pairs(list) do
                if (l._fixedWidth or 0) > 0 or l._wordWrap ~= false then out[#out + 1] = "field:" .. name end
                if tostring(l._font or ""):find("Small") then out[#out + 1] = "smallfield:" .. name end
            end
        end
        table.sort(out)
        return table.concat(out, ",")
    end

    -- Buttons laid out in a row must not run into the next one's icon.
    local function overlaps(list)
        local out = {}
        for i = 2, #list do
            local a, b = list[i - 1], list[i]
            if a:IsShown() and b:IsShown() and a.flowX and b.flowX then
                local need = a.flowX + (a.gfWidth or 0) + (a.label and (4 + wow.textWidth(a.label._text, a.label._font)) or 0)
                if b.flowX < need then out[#out + 1] = plain(a.label and a.label._text) .. ">" .. plain(b.label and b.label._text) end
            end
        end
        return table.concat(out, ",")
    end

    local function withOrderAndTicket(ns)
        local t = ns.Share.serverNow()
        local w = "id=gbbb.1,cf=" .. "0000-0000000A" .. ",cr=" .. ns.Share.b36(t) .. ",rc=21w,it=27i,sk=4k,q=1,fe=0,st=o,sa=" .. ns.Share.b36(t)
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash(w), w)
        ns.Orders.place({ recipe = 2660, item = 2862, skill = 164, qty = 1 })
        local v = ns.Adventure.encodeList({ { id = "abbb.1", src = "g", ver = 1, cr = t, ds = "smg", qs = "", tm = "n",
            rt = 1, rh = 1, rd = 3, lr = "d", tg = 31, md = "c", st = "o", sa = t } })
        ns.Adventure.ledger:offer(B, "T", t, ns.Share.hash(v), v)
        ns.Adventure.open({ dungeon = "sfk", leaderRole = "h" })
    end

    -- A peer taking 製皮 orders for 5s; my own 製皮 recipes 2149, 2152.
    local function recipeLogin()
        local ns = shareLogin({ tradeSkill = leatherWindow() })
        wow.fire("TRADE_SKILL_SHOW")
        local t = wow.state.now - 600
        shareFrom(ns, PEER, (rMsg(ns, A_PEER, 165, t, { 2152, 2153 })))  -- online
        shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 165, t, { 2153, 2160 }))) -- offline
        local sv = ns.Orders.encodeServices({ active = { [165] = true }, fees = { [165] = 500 }, recipeFees = {}, recipeSkill = {} })
        ns.Orders.ledger:offer(A_PEER, "O", ns.Share.serverNow(), ns.Share.hash(sv), sv)
        return ns
    end
    local function rowOf(ns, id)
        for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() and r.data and r.data.id == id then return r end end
    end
    local function ids(ns)
        local list = {}
        for _, r in ipairs(ns.Recipes.shownRows()) do list[#list + 1] = r.id end
        table.sort(list)
        return table.concat(list, ",")
    end

    test("GF-002-E no name or field name is cut or broken onto two lines; no small font", function()
        local ns = login()
        withOrderAndTicket(ns)
        wow.advance(30)
        ns.Framework.open("orders")
        eq(badTexts(ns.Framework.panel("orders")), "", "orders page")
        ns.Framework.open("adventure")
        eq(badTexts(ns.Framework.panel("adventure")), "", "adventure page")
        ns.Framework.open("recipes")
        eq(badTexts(ns.Framework.panel("recipes")), "", "recipe page")
        local A, O = ns.AdventureUI, ns.OrdersUI
        A.openTicket()
        for _, m in ipairs({ "n", "t", "f" }) do
            A.pickTime(nil, m)
            eq(badTexts(_G[A.TICKET_NAME]), "", "ticket window, time " .. m)
        end
        A.openWorker()
        eq(badTexts(_G[A.WORKER_NAME]), "", "worker window")
        O.openOrder({ recipe = 2660, skill = 164, crafters = {} })
        eq(badTexts(_G[O.POPUP_NAME]), "", "order window")
        O.editFee({ skill = 164 })
        eq(badTexts(_G[O.FEE_NAME]), "", "fee window")
        O.openPaste()
        eq(badTexts(_G[O.PASTE_NAME]), "", "paste window")
        O.openServices()
        eq(badTexts(_G[O.SERVICES_NAME]), "", "services window")
        O.openPicker()
        eq(badTexts(_G[O.PICKER_NAME]), "", "recipe picker")
        -- The dungeon grid: every short name in full under its icon, normal font.
        A.openTicket()
        local grid = A.pickDestination(_G[A.TICKET_NAME].dest)
        eq(badTexts(grid), "", "dungeon grid")
        for i, b in ipairs(grid.buttons) do
            local d = ns.AdventureData.DUNGEONS[i]
            eq(b.label._text, d.short, "grid name " .. d.id)
            ok(wow.textWidth(d.short, b.label._font) <= A.GRID_CELL_W - 6, "fits its cell: " .. d.short)
        end
    end)

    test("GF-002-E names in a row never run into the next button; controls start after the field names", function()
        local ns = login()
        withOrderAndTicket(ns)
        wow.advance(30)
        local A, O = ns.AdventureUI, ns.OrdersUI
        A.openTicket()
        local f = _G[A.TICKET_NAME]
        -- GF-002-G: one 開始 control (the old 現在/今天/之後 buttons are gone).
        ok(f.timeButtons == nil, "no three time buttons")
        eq(overlaps({ f.direct, f.consent }), "", "錄取")
        local tags = {}
        for _, k in ipairs(A.TAG_KEYS) do tags[#tags + 1] = f.tagButtons[k] end
        eq(overlaps(tags), "", "標籤")
        ok(tags[#tags].flowX + 26 + 4 + wow.textWidth(tags[#tags].label._text, tags[#tags].label._font) < 660, "標籤 inside the window")
        -- Field names end before the controls.
        local X = O.controlX(A.TICKET_FIELDS)
        for _, name in ipairs({ "目的地", "時間", "人數", "錄取", "標籤", "備註" }) do
            ok(O.FIELD_X + wow.textWidth(name, ns.FIELD_FONT) + 8 <= X, "field " .. name .. " ends before the controls")
        end
        local w = A.openWorker()
        local wf = _G[A.WORKER_NAME]
        eq(overlaps({ wf.mainRoles.t, wf.mainRoles.h, wf.mainRoles.d }), "", "職責")
        eq(overlaps({ wf.altRoles.t, wf.altRoles.h, wf.altRoles.d }), "", "副職責")
        X = O.controlX(A.WORKER_FIELDS)
        ok(O.FIELD_X + wow.textWidth("副職責", ns.FIELD_FONT) + 8 <= X, "副職責 ends before the controls")
        -- Rows on the two pages.
        ns.Framework.open("orders")
        for _, r in ipairs(O.rowFrames()) do
            if r:IsShown() and r.view then
                eq(overlaps(r.buttons), "", "order row buttons")
                local last
                for _, b in ipairs(r.buttons) do if b:IsShown() then last = b end end
                if last then ok(last.flowX + O.buttonSpan(last) <= O.ROW_WIDTH, "order row: inside the row") end
            end
        end
        ns.Framework.open("adventure")
        local seen = 0
        for _, r in ipairs(A.rowFrames()) do
            if r:IsShown() and (r.view or r.buttons[1]:IsShown()) then
                eq(overlaps(r.buttons), "", "adventure row buttons")
                for _, b in ipairs(r.buttons) do
                    if b:IsShown() then seen = seen + 1; ok(b.flowX + O.buttonSpan(b) <= A.ROW_WIDTH, "adventure row: inside the row") end
                end
            end
        end
        ok(seen > 0, "adventure rows have buttons")
    end)

    test("GF-002-E 邀請下一位 only while someone waits for an invite", function()
        local ns = login()
        ns.Framework.open("adventure")
        eq(ns.AdventureUI.nextInvite._shown, false, "hidden with nobody to invite")
        local real = ns.Adventure.pendingInvites
        ns.Adventure.pendingInvites = function() return { "x" } end
        ns.AdventureUI.refresh()
        eq(ns.AdventureUI.nextInvite._shown, true, "shown while names wait")
        eq(ns.AdventureUI.nextInvite.label._text, "邀請下一位", "with its name")
        ns.Adventure.pendingInvites = real
        ns.AdventureUI.refresh()
        eq(ns.AdventureUI.nextInvite._shown, false, "hidden again")
    end)

    test("GF-002-E icons that match their meaning, each with a fallback (MANUAL §3z)", function()
        local ns = login()
        local G = ns.GameIcons
        local first = function(key) return G.ART[key] and G.ART[key][1][1] end
        eq(first("adventure"), "Interface\\Icons\\INV_Misc_Map_01", "冒險單: a map")
        eq(first("worker"), "Interface\\Icons\\Spell_Holy_SealOfSalvation", "職工單: a raised hand")
        eq(first("adjust"), "Interface\\Icons\\INV_Misc_GroupLooking", "調整: a person (GF-002-G social heads)")
        eq(first("group"), "Interface\\Icons\\INV_Misc_GroupNeedMore", "組隊: several heads")
        ok(first("direct") ~= first("consent"), "直接錄取 and 團長同意 look different")
        eq(first("consent"), "Interface\\GroupFrame\\UI-Group-LeaderIcon", "團長同意: the leader's crown")
        ok(first("tag_voice") ~= "Interface\\Icons\\Spell_Holy_Silence", "語音 is no longer the silence icon")
        local seen = {}
        for _, k in ipairs({ "tag_quest", "tag_farm", "tag_slow", "tag_fast", "tag_voice" }) do
            ok(first(k), k .. " has art")
            ok(not seen[first(k)], k .. ": its own icon")
            seen[first(k)] = true
            ok(#G.ART[k] >= 2, k .. ": a fallback")
        end
        -- The buttons use them; a missing file falls back.
        ns.AdventureUI.openTicket()
        local f = _G[ns.AdventureUI.TICKET_NAME]
        eq(f.consent.tex._texture, first("consent"), "團長同意 button")
        eq(f.tagButtons.voice.tex._texture, first("tag_voice"), "語音 button")
        wow.reset({ missingFiles = { [first("worker")] = true } })
        ns = wow.login(ADDON_DIR)
        ns.Framework.open("adventure")
        ok(ns.AdventureUI.workerButton._text:find(G.ART.worker[2][1], 1, true), "職工單 falls back to the scroll")
    end)

    test("GF-002-E ESC closes the top window first, then the next, then the main window", function()
        local ns = login()
        withOrderAndTicket(ns)
        wow.advance(30)
        local menus0 = wow.gameMenuCount()
        ns.Framework.open("orders")
        local names = {}
        for _, n in pairs(UISpecialFrames) do if n:find("GreenFangToolkit", 1, true) then names[#names + 1] = n end end
        eq(table.concat(names, ","), ns.ESC_NAME, "only the catcher is listed (the client hides them all at once)")
        local main = _G[ns.Framework.WINDOW_NAME]
        local O, A = ns.OrdersUI, ns.AdventureUI
        O.openOrder({ recipe = 2660, skill = 164, crafters = {} })
        local menu = ns.showMenu(UIParent, { { text = "測試", fn = function() end } })
        local order = _G[O.POPUP_NAME]
        ok(menu:IsShown() and order:IsShown() and main:IsShown(), "three open")
        ok(wow.pressEscape(), "ESC 1 taken")
        ok(not menu:IsShown() and order:IsShown() and main:IsShown(), "ESC 1: the menu")
        ok(wow.pressEscape(), "ESC 2 taken")
        ok(not order:IsShown() and main:IsShown(), "ESC 2: the order window")
        ok(wow.pressEscape(), "ESC 3 taken")
        ok(not main:IsShown(), "ESC 3: the main window")
        eq(wow.gameMenuCount(), menus0, "the game menu never opened")
        ok(not wow.pressEscape(), "ESC 4: nothing of ours is open")
        eq(wow.gameMenuCount(), menus0 + 1, "now the game menu")
        -- Adventure: the time menu, the dungeon grid and the ticket window, one by one.
        ns.Framework.open("adventure")
        A.openTicket()
        local f = _G[A.TICKET_NAME]
        A.pickTime(nil, "t")
        local grid = A.pickDestination(f.dest)
        ok(grid:IsShown(), "grid open")
        wow.pressEscape()
        ok(not grid:IsShown() and f:IsShown(), "ESC: the grid first")
        local m = A.pickStart(f.startButton)
        ok(m:IsShown(), "start menu open")
        wow.pressEscape()
        ok(not m:IsShown() and f:IsShown(), "ESC: the time menu")
        wow.pressEscape()
        ok(not f:IsShown() and main:IsShown(), "ESC: the ticket window")
        -- The worker window, the fee, paste, services and picker windows and 同步與診斷.
        for _, open in ipairs({ A.openWorker, function() O.editFee({ skill = 164 }) end, O.openPaste, O.openServices, O.openPicker,
            function() ns.Diag.toggle() end }) do
            open()
            local top = ns.escTop()
            ok(top and top ~= main, "a window above the main one")
            wow.pressEscape()
            ok(not top:IsShown() and main:IsShown(), "ESC closed only " .. tostring(top._name))
        end
        -- A choice list (the recipe page's 工錢) closes before the page's window.
        ns.Framework.open("recipes")
        wow.click(ns.Recipes.feeChoice)
        ok(ns.Recipes.feeChoice.menu:IsShown(), "list open")
        wow.pressEscape()
        ok(not ns.Recipes.feeChoice.menu:IsShown() and main:IsShown(), "ESC: the list first")
        wow.pressEscape()
        ok(not main:IsShown(), "then the window")
        eq(wow.gameMenuCount(), menus0 + 1, "no game menu while windows were open")
    end)

    test("GF-002-E recipe page: a 工錢 column (lowest quote) and the 接單中 / 工錢 filters", function()
        local ns = recipeLogin()
        ns.Orders.setRecipeFee(2149, 0, 165) -- my own recipe: free
        ns.Recipes.show(nil, 165)
        eq(ids(ns), "2149,2152,2153,2160", "all four")
        local function feeOf(id) local r = rowOf(ns, id); return r and plain(r.fee._text) end
        eq(feeOf(2153), plain(ns.OrdersUI.money(500)), "two crafters: the lowest quote (the other did not fill one in)")
        eq(feeOf(2152), plain(ns.OrdersUI.money(500)), "mine and theirs: their quote")
        eq(feeOf(2160), "沒填", "nobody filled it in")
        eq(feeOf(2149), "免費", "only mine: my own fee")
        ok(rowOf(ns, 2160).feeTex._texture ~= nil, "a coin icon with the name")
        -- 只看接單中: only the crafter taking orders.
        wow.click(ns.Recipes.activeCheck)
        eq(ids(ns), "2152,2153", "only recipes someone taking orders can make")
        for _, r in ipairs(ns.Recipes.shownRows()) do
            for _, m in ipairs(r.crafters) do ok(ns.Orders.isActive(m.guid, 165), "only active crafters listed") end
        end
        wow.click(ns.Recipes.activeCheck)
        -- 工錢 filter.
        ns.Recipes.feeChoice.choose("free")
        eq(ids(ns), "2149", "免費")
        ns.Recipes.feeChoice.choose("set")
        eq(ids(ns), "2149,2152,2153", "有填工錢")
        ns.Recipes.feeChoice.choose("max:400")
        eq(ids(ns), "2149", "under 4s")
        ns.Recipes.feeChoice.choose("max:10000")
        eq(ids(ns), "2149,2152,2153", "1 金以內")
        ns.Recipes.feeChoice.choose(nil)
        eq(ids(ns), "2149,2152,2153,2160", "工錢不限")
        eq(badTexts(ns.Framework.panel("recipes")), "", "nothing cut on the page")
    end)

    test("GF-002-E 下單 on a recipe row and ＋下單 on the orders page open the order window", function()
        local ns = recipeLogin()
        ns.Recipes.show(nil, 165)
        local O = ns.OrdersUI
        local theirs, onlyMine = rowOf(ns, 2153), rowOf(ns, 2149)
        ok(plain(theirs.order._text):find("下單", 1, true), "someone else's recipe: 下單")
        ok(plain(onlyMine.order._text):find("我的工錢", 1, true), "only mine: 我的工錢")
        wow.click(theirs.order)
        ok(_G[O.POPUP_NAME]:IsShown(), "order window open")
        eq(O.draft().recipe, 2153, "for that recipe")
        wow.click(onlyMine.order)
        ok(_G[O.FEE_NAME]:IsShown(), "我的工錢: the fee window")
        ok(not _G[O.POPUP_NAME]:IsShown(), "one window at a time")
        -- ＋下單: choose a recipe (search), then the order window.
        ns.Framework.open("orders")
        ok(plain(O.orderButton._text):find("＋下單", 1, true), "＋下單 on top of the orders page")
        wow.click(O.orderButton)
        local picker = _G[O.PICKER_NAME]
        ok(picker:IsShown(), "recipe picker open")
        local listed = {}
        for _, r in ipairs(picker.list) do listed[#listed + 1] = r.id end
        table.sort(listed)
        eq(table.concat(listed, ","), "2152,2153,2160", "only recipes someone else can make")
        picker.search:SetText(ns.Recipes.name(2160))
        picker.search._scripts.OnTextChanged(picker.search)
        eq(#picker.list, 1, "search")
        eq(picker.list[1].id, 2160, "the one found")
        wow.click(picker.rows[1])
        ok(_G[O.POPUP_NAME]:IsShown() and not picker:IsShown(), "the order window replaces the picker")
        eq(O.draft().recipe, 2160, "for the picked recipe")
        -- The right-click menu is still there.
        ok(#O.recipeMenuItems({ id = 2153, skill = 165, crafters = { { guid = "Player-" .. B, name = "測試乙" } } }) > 0, "right-click menu kept")
    end)

    test("GF-002-E 我的服務: take orders and set the fee for each profession", function()
        local ns = login()
        withOrderAndTicket(ns)
        wow.advance(30)
        local O = ns.OrdersUI
        ns.Framework.open("orders")
        ok(plain(O.servicesButton._text):find("我的服務", 1, true), "我的服務 on top of the orders page")
        wow.click(O.servicesButton)
        local f = _G[O.SERVICES_NAME]
        ok(f:IsShown(), "services window open")
        local skills = O.ownCraftSkills()
        ok(#skills > 0, "my craft professions")
        local r = f.rows[1]
        local me = ns.Data.player().guid
        eq(ns.Orders.isActive(me, r.skill), false, "not taking orders yet")
        wow.click(r.active)
        eq(ns.Orders.isActive(me, r.skill), true, "接單 ticked: taking orders")
        eq(plain(r.fee._text), "沒填", "fee not filled in")
        wow.click(r.edit)
        local fee = _G[O.FEE_NAME]
        ok(fee:IsShown() and not f:IsShown(), "the fee window (one at a time)")
        fee.boxes[1]:SetText("2")
        wow.click(fee.save)
        eq(ns.Orders.services(ns.Share.selfAuthor()).fees[r.skill], 20000, "2 gold saved")
        ok(f:IsShown(), "back in 我的服務")
        eq(plain(r.fee._text), plain(O.money(20000)), "shown at once")
        wow.click(r.edit)
        wow.click(fee.free)
        eq(ns.Orders.services(ns.Share.selfAuthor()).fees[r.skill], 0, "免費")
        eq(plain(r.fee._text), "免費", "shown as 免費")
        wow.click(r.active)
        eq(ns.Orders.isActive(me, r.skill), false, "接單 off again")
        -- 配方工錢: the recipe page on my own recipes.
        wow.click(f.recipeFees)
        ok(ns.Framework.isModuleShown("recipes"), "recipe page")
        eq(ns.Recipes.state.guid, me, "only my recipes")
    end)
end
