-- GF-009-10 (spec v2.0 §6, §7.2, §7.4 圖紙連動): 「尋找圖紙」 on the 配方 page
-- (only with a recipe item the catalog and the client can vouch for, only for
-- a recipe this character has not learned, never while its data is missing),
-- the 調貨所 form it fills in (徵求, the recipe item, 1; never sent), the 徵求
-- it reuses, 「教：…」 on recipe listings, and the notice after learning it
-- (never an automatic end). A small fake game and catalog; made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local realPrint = T.realPrint or print

    local PEER_GUID = "Player-0000-0000000B"
    -- Recipes (spell IDs) and their names.
    local LEATHER, DUPE, TRAINER, BOUND, SOUP, OWN = 7001, 7002, 7003, 7004, 7005, 7100
    local NAMES = { [LEATHER] = "測試皮甲", [DUPE] = "重名皮帶", [TRAINER] = "訓練師皮靴", [BOUND] = "綁定皮盔",
        [SOUP] = "測試魚湯", [OWN] = "自己的皮護腕" }
    -- Recipe items (ClassID 9) and the crafted item.
    local P_LEATHER, P_DUPE1, P_DUPE2, P_SOUP, P_BOUND, CRAFTED, CLOTH = 5001, 5002, 5003, 5004, 5005, 6001, 6002

    local function catalog(extra)
        local nine = {
            P_LEATHER .. "\t1\t0\t圖樣：測試皮甲",
            P_DUPE1 .. "\t1\t0\t圖樣：重名皮帶",
            P_DUPE2 .. "\t1\t0\t圖樣：重名皮帶",
            P_SOUP .. "\t5\t0\t食譜：測試魚湯",
            P_BOUND .. "\t1\t0\t圖樣：綁定皮盔",
        }
        for _, line in ipairs(extra or {}) do nine[#nine + 1] = line end
        return { v = 2, build = "test", locale = "zhTW", n = #nine + 2, groups = {
            [9] = table.concat(nine, "\n") .. "\n",
            [4] = CRAFTED .. "\t8\t0\t測試皮甲\n",
            [7] = CLOTH .. "\t5\t0\t測試布\n",
        } }
    end

    local ITEMS
    local function installGame()
        ITEMS = {
            [P_LEATHER] = { name = "圖樣：測試皮甲", classID = 9, sub = 1 },
            [P_BOUND] = { name = "圖樣：綁定皮盔", classID = 9, sub = 1, bindType = 1 }, -- the client says 拾取綁定
            [CRAFTED] = { name = "測試皮甲", classID = 4, sub = 8 },
            [CLOTH] = { name = "測試布", classID = 7, sub = 5 },
        }
        GetItemInfo = function(id)
            local it = ITEMS[id]
            if not it then return nil end
            return it.name, "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. it.name .. "]|h|r", 1, 1, 1,
                it.classID == 9 and "配方" or "物品", "", 20, "", 134939, 0, it.classID, it.sub, it.bindType or 0
        end
        C_Item = {
            GetItemIconByID = function(id) return ITEMS[id] and 134939 or nil end,
            GetItemNameByID = function(id) return ITEMS[id] and ITEMS[id].name or nil end,
            RequestLoadItemDataByID = function() end,
            IsItemDataCachedByID = function(id) return ITEMS[id] ~= nil end,
            DoesItemExistByID = function() return true end,
        }
        -- The crafted item of every recipe: never taken for the recipe item.
        C_TradeSkillUI = { GetRecipeSchematic = function() return { outputItemID = CRAFTED } end }
        local base = C_Spell and C_Spell.GetSpellName
        C_Spell = C_Spell or {}
        C_Spell.GetSpellName = function(id)
            if NAMES[id] then return NAMES[id] end
            if base then return base(id) end
            return nil
        end
    end
    local function removeGame() GetItemInfo, C_Item, C_TradeSkillUI = nil, nil, nil end
    local function done(fn)
        return function()
            local okRun, err = pcall(fn)
            removeGame()
            if wow.state and wow.state.combat then wow.leaveCombat() end
            if not okRun then error(err, 0) end
        end
    end

    local function offer(ns, a, g, ids, t)
        local v = ns.Share.encodeValue(g, ids)
        return ns.Share.offer(a, g, t or (wow.state.now - 60), ns.Share.hash(v), v, true, a)
    end
    local function setOwn(ns, skill, ids) return ns.Share.ownRecord("R" .. skill, ns.Share.encodeValue("R" .. skill, ids)) end

    -- opts.peer: the peer's R165 list; opts.own: my R165 list (nil = never read);
    -- opts.ownSoup: my R185 list; opts.catalog: extra ClassID 9 lines.
    local function login(opts)
        opts = opts or {}
        wow.reset({ player = opts.player })
        local ns = wow.login(ADDON_DIR)
        installGame()
        ns.SupplyCatalogData = catalog(opts.catalog)
        ns.SupplyCatalog.resetSession()
        ns.RecipeLink.resetSession()
        ns.Share.rand = function(a) return a end
        ns.Supply.rand = function(a) return a end
        ns.Supply.resetSession(); ns.SupplyListings.resetSession()
        wow.advance(130)
        local peer = ns.Share.authorOf(PEER_GUID)
        offer(ns, peer, "R165", opts.peer or { LEATHER, DUPE, TRAINER, BOUND })
        offer(ns, peer, "R185", { SOUP })
        if opts.own ~= false then setOwn(ns, 165, opts.own or { OWN }) end
        if opts.ownSoup then setOwn(ns, 185, opts.ownSoup) end
        return ns
    end
    local function openRecipes(ns)
        ns.Framework.open("recipes")
        wow.advance(1)
        ns.Recipes.refresh()
    end
    -- The row frame of a recipe, scrolled into view first (only rows in view have frames).
    local function rowFor(ns, id)
        for i, d in ipairs(ns.Recipes.shownRows()) do
            if d.id == id then
                local content = ns.Recipes.rowFrames()[1]._parent
                content._parent:SetVerticalScroll((i - 1) * ns.PAGE_ROW)
                break
            end
        end
        for _, r in ipairs(ns.Recipes.rowFrames()) do
            if r:IsShown() and r.data and r.data.id == id then return r end
        end
        return nil
    end
    local function buttonShown(ns, id)
        local r = rowFor(ns, id)
        assert(r, "row for recipe " .. id)
        return r.pattern:IsShown(), r.pattern.itemID
    end
    local function press(ns, id)
        local r = rowFor(ns, id)
        return ns.RecipeLink.find(r.data)
    end

    test("GF-009-10 button only with one tradeable recipe item for the recipe", done(function()
        local ns = login()
        openRecipes(ns)
        local shown, item = buttonShown(ns, LEATHER)
        ok(shown, "測試皮甲: one tradeable 圖樣 in the catalog")
        eq(item, P_LEATHER, "the recipe item's ID")
        local RL = ns.RecipeLink
        eq(RL.patternFor(LEATHER, 165), P_LEATHER, "patternFor")
        eq(buttonShown(ns, DUPE), false, "two items with the same name: no button")
        eq(select(2, RL.patternFor(DUPE, 165)), "ambiguous", "why: ambiguous")
        eq(buttonShown(ns, TRAINER), false, "trainer recipe (no item): no button")
        eq(select(2, RL.patternFor(TRAINER, 165)), "none", "why: none")
        eq(buttonShown(ns, BOUND), false, "the client says 拾取綁定: no button")
        eq(select(2, RL.patternFor(BOUND, 165)), "untradeable", "why: untradeable")
        eq(select(2, RL.patternFor(LEATHER, 197)), "none", "another profession's subclass is not looked at")
        -- The right-click menu has it too (only on the row with the button).
        local items = {}
        local orig = ns.showMenu
        ns.showMenu = function(_, list) items = list; return true end
        ns.Recipes.click(rowFor(ns, LEATHER), "RightButton")
        local found = false
        for _, it in ipairs(items) do if it.text == RL.LABEL then found = true end end
        ok(found, "menu: 尋找圖紙")
        ns.Recipes.click(rowFor(ns, DUPE), "RightButton")
        for _, it in ipairs(items) do ok(it.text ~= RL.LABEL, "no 尋找圖紙 for the ambiguous one") end
        ns.showMenu = orig
    end))

    test("GF-009-10 learned or not loaded: no button", done(function()
        -- Learned (my own list has it).
        local ns = login({ own = { OWN, LEATHER } })
        openRecipes(ns)
        eq(buttonShown(ns, LEATHER), false, "learned: no button")
        eq(ns.RecipeLink.ownState(LEATHER, 165), "learned", "state learned")
        eq(buttonShown(ns, OWN), false, "my own recipe: no button")
        -- My recipe list of that profession was never read (window not opened).
        ns = login({ own = false })
        openRecipes(ns)
        eq(buttonShown(ns, LEATHER), false, "no own list yet: no button")
        eq(ns.RecipeLink.ownState(LEATHER, 165), "unknown", "unknown, not 沒學")
        -- 烹飪: I have the profession, no list of it yet.
        eq(buttonShown(ns, SOUP), false, "cooking list never read: no button")
        -- Profession data missing (GetProfessions gives nothing yet).
        local p = wow.defaultPlayer()
        p.professionIndexes = {}
        ns = login({ player = p })
        openRecipes(ns)
        eq(buttonShown(ns, LEATHER), false, "no profession data: no button")
        eq(ns.RecipeLink.ownState(LEATHER, 165), "unknown", "unknown")
        -- With the cooking list read, the catalog-only 食譜 shows (client has no data of it).
        ns = login({ ownSoup = { 99999 } })
        openRecipes(ns)
        local shown, item = buttonShown(ns, SOUP)
        ok(shown and item == P_SOUP, "食譜 from the catalog (tradeable by its DB2 data)")
    end))

    test("GF-009-10 no profession of my own: no button; crafted item ID never used", done(function()
        local ns = login({ peer = { LEATHER } })
        local RL = ns.RecipeLink
        eq(RL.ownState(LEATHER, 197), "noprof", "裁縫: not my profession")
        ok(RL.patternFor(LEATHER, 165) ~= CRAFTED, "not the crafted item")
        eq(RL.patternFor(LEATHER, 165), P_LEATHER, "the recipe item")
        eq(RL.teachOf(CRAFTED), nil, "the crafted item teaches nothing")
        eq(RL.teachOf(CLOTH), nil, "cloth teaches nothing")
        eq(RL.teachOf(LEATHER), nil, "a recipe (spell) ID is not an item")
        -- A client name that no longer matches: no link.
        ITEMS[P_LEATHER].name = "圖樣：改名的皮甲"
        eq(select(2, RL.patternFor(LEATHER, 165)), "client-name", "client disagrees: no link")
        ITEMS[P_LEATHER].name = "圖樣：測試皮甲"
        ITEMS[P_LEATHER].classID = 15
        eq(select(2, RL.patternFor(LEATHER, 165)), "client-class", "not ClassID 9 in the client: no link")
    end))

    test("GF-009-10 press: the form filled in (徵求, recipe item, 圖紙, 1), nothing sent", done(function()
        local ns = login()
        openRecipes(ns)
        local L, UI = ns.SupplyListings, ns.SupplyUI
        local before = #L.ownActive()
        local sentBefore = #(wow.state.sent or {})
        local r = rowFor(ns, LEATHER)
        r.pattern._scripts.OnClick(r.pattern)
        ok(ns.Framework.isModuleShown("supply"), "綠皮調貨所 opened")
        local f = UI.form()
        ok(f and f:IsShown(), "the form is open")
        local s = UI.formState
        eq(s.direction, "need", "方向 徵求")
        eq(s.itemID, P_LEATHER, "物品 = the recipe item")
        eq(s.category, "recipe", "分類 圖紙")
        eq(f.qty:GetText(), "1", "數量 1")
        eq(s.days, L.DEFAULT_DAYS, "有效期 default")
        eq(s.terms, L.DEFAULT_TERMS, "交易條件 default")
        eq(s.editing, nil, "a new listing")
        eq(#L.ownActive(), before, "not created")
        eq(#(wow.state.sent or {}), sentBefore, "nothing sent")
        eq(UI.formDirty(), false, "closing asks nothing")
        -- In combat: nothing opens.
        UI.closeForm(true)
        wow.enterCombat()
        local res, why = press(ns, LEATHER)
        eq(res, nil, "combat: no form"); eq(why, "combat", "why")
        wow.leaveCombat()
        -- An open form with unsaved changes is kept.
        UI.openForm()
        f.note:SetText("我的草稿")
        res, why = press(ns, LEATHER)
        eq(why, "busy", "unsaved form kept")
        eq(f.note:GetText(), "我的草稿", "the draft is still there")
        UI.closeForm(true)
        -- 手動刊登 off: nothing.
        ns.Supply.setManual(false)
        res, why = press(ns, LEATHER)
        eq(why, "off", "manual off")
        ns.Supply.setManual(true)
        -- Saving it makes the 徵求 of the recipe item, category 圖紙.
        eq(press(ns, LEATHER), "new", "new again")
        local l = UI.submitForm()
        ok(l, "saved by the player")
        eq(l.direction, "need", "徵求"); eq(l.itemID, P_LEATHER, "item"); eq(l.category, "recipe", "圖紙"); eq(l.quantity, 1, "1")
    end))

    test("GF-009-10 an active 徵求 of the recipe item: that one opens, no second one", done(function()
        local ns = login()
        local L, UI = ns.SupplyListings, ns.SupplyUI
        local l = assert(L.create({ direction = "need", itemID = P_LEATHER, quantity = 2, days = 14, note = "舊的" }))
        openRecipes(ns)
        local res, dup = press(ns, LEATHER)
        eq(res, "existing", "the existing one")
        eq(dup.id, l.id, "that listing")
        eq(UI.formState.editing and UI.formState.editing.id, l.id, "the form edits it")
        eq(UI.form().note:GetText(), "舊的", "its note")
        eq(#L.ownActive(), 1, "still one")
        -- A 供應 of the same item is not a 徵求: a new 徵求 form.
        UI.closeForm(true)
        L.finish(l.id, "closed")
        assert(L.create({ direction = "offer", itemID = P_LEATHER, quantity = 1, days = 14, note = "" }))
        eq(press(ns, LEATHER), "new", "a 供應 does not count")
    end))

    test("GF-009-10 調貨所: a recipe listing says what it teaches", done(function()
        local ns = login()
        openRecipes(ns) -- the guild's recipes are indexed
        local L, UI = ns.SupplyListings, ns.SupplyUI
        assert(L.create({ direction = "need", itemID = P_LEATHER, quantity = 1, days = 14, note = "" }))
        assert(L.create({ direction = "need", itemID = CLOTH, quantity = 3, days = 14, note = "" }))
        local prof = ns.Data.skillName(nil, 165)
        local want = "教：測試皮甲｜" .. prof
        eq(ns.RecipeLink.teachText(P_LEATHER), want, "teach text")
        local rows = UI.listFor("mine")
        local seen = {}
        for _, d in ipairs(rows) do seen[d.itemID] = d end
        eq(seen[P_LEATHER].teach, want, "list line")
        eq(seen[P_LEATHER].tip[1], want, "tooltip first line")
        eq(seen[CLOTH].teach, nil, "cloth: nothing")
        -- The page draws it on the row's second line.
        ns.Framework.open("supply")
        UI.setTab("mine")
        local drawn = false
        for _, t in ipairs(wow.allTexts()) do if t == want then drawn = true end end
        ok(drawn, "shown on the row")
        -- A recipe item nobody's list has by ID: nothing (not guessed from the name).
        eq(ns.RecipeLink.teachText(P_DUPE1), nil, "ambiguous: no label")
        eq(ns.RecipeLink.teachText(P_SOUP + 1000), nil, "unknown item: no label")
    end))

    test("GF-009-10 調貨所 rows of other items do not open the catalog", done(function()
        local ns = login()
        C_Item.GetItemInfoInstant = function(id)
            local it = ITEMS[id]
            if not it then return nil end
            return id, "", "", "", 134939, it.classID, it.sub
        end
        local L, UI = ns.SupplyListings, ns.SupplyUI
        assert(L.create({ direction = "need", itemID = CLOTH, quantity = 3, days = 14, note = "" }))
        UI.listFor("mine")
        eq(ns.SupplyCatalog.loaded(), false, "cloth: the catalog stays closed")
        eq(ns.RecipeLink.teachText(CLOTH), nil, "nothing for cloth")
    end))

    test("GF-009-10 learned later: a notice only, the 徵求 stays until the player ends it", done(function()
        local ns = login()
        local L, N = ns.SupplyListings, ns.Notify
        local l = assert(L.create({ direction = "need", itemID = P_LEATHER, quantity = 1, days = 14, note = "" }))
        local function mine()
            local out = {}
            for _, e in ipairs(N.list()) do if e.module == ns.RecipeLink.NOTIFY_MODULE then out[#out + 1] = e end end
            return out
        end
        eq(#mine(), 0, "no notice before")
        setOwn(ns, 165, { OWN, LEATHER }) -- the profession window read: now learned
        local list = mine()
        eq(#list, 1, "one notice")
        ok(list[1].text:find("測試皮甲", 1, true) ~= nil, "names the recipe")
        eq(list[1].key, "learned:" .. l.id, "about that listing")
        eq(L.mine().list[l.id].status, "active", "the listing is NOT ended")
        -- Learning something else later: no second notice for it.
        setOwn(ns, 165, { OWN, LEATHER, 7200 })
        eq(#mine(), 1, "still one")
        -- The player's click ends it.
        eq(N.action(list[1], "end"), "ended", "結束徵求")
        eq(L.mine().list[l.id].status, "closed", "ended by the click")
        eq(#mine(), 0, "notice gone")
    end))

    test("GF-009-10 performance: 1,000 recipes with recipe items, open and scroll reuse the rows", done(function()
        local ids, extra = {}, {}
        for i = 1, 1000 do
            local id = 30000 + i
            ids[i] = id
            NAMES[id] = string.format("量產皮件%04d", i)
            extra[i] = (40000 + i) .. "\t1\t0\t圖樣：" .. NAMES[id]
        end
        local ns = login({ peer = ids, catalog = extra })
        local clock = os.clock
        local t0 = clock()
        openRecipes(ns)
        local openMs = (clock() - t0) * 1000
        local rows = ns.Recipes.shownRows()
        ok(#rows >= 1000, "every recipe listed: " .. #rows)
        local frames = #ns.Recipes.rowFrames()
        ok(frames <= 20, "rows only for the view: " .. frames)
        -- The page's scroll frame: the parent of the row content.
        local content = ns.Recipes.rowFrames()[1]._parent
        local scroll = content and content._parent
        assert(scroll and scroll.SetVerticalScroll, "scroll frame")
        local H = ns.PAGE_ROW
        local t1 = clock()
        local steps = 0
        for i = 0, #rows - 10, 7 do
            scroll:SetVerticalScroll(i * H)
            steps = steps + 1
        end
        local scrollMs = (clock() - t1) * 1000
        eq(#ns.Recipes.rowFrames(), frames, "no new frames while scrolling")
        local withButton = 0
        for _, r in ipairs(ns.Recipes.rowFrames()) do if r:IsShown() and r.pattern:IsShown() then withButton = withButton + 1 end end
        ok(withButton > 0, "the rows in view have the button: " .. withButton)
        eq(ns.RecipeLink.stats.mapBuilds, 1, "catalog map built once")
        realPrint(string.format("     GF-009-10 perf: open %.1f ms, %d scroll steps %.1f ms (%.2f ms each), %d row frames",
            openMs, steps, scrollMs, scrollMs / math.max(1, steps), frames))
        ok(scrollMs / math.max(1, steps) < 20, "a scroll step is cheap")
        -- The shipped catalog: how long the one-time map takes and what it covers.
        local real = {}
        assert(loadfile(ADDON_DIR .. "/SupplyCatalogData.lua"))("GreenFangToolkit", real)
        ns.SupplyCatalogData = real.SupplyCatalogData
        ns.SupplyCatalog.resetSession(); ns.RecipeLink.resetSession()
        local t2 = clock()
        local m = ns.RecipeLink.patternMap()
        local mapMs = (clock() - t2) * 1000
        ok(m and m.n > 500, "shipped catalog: recipe items linked by name: " .. tostring(m and m.n))
        local per = {}
        for skill, t in pairs(m.bySkill) do
            local n = 0
            for _, v in pairs(t) do if v then n = n + 1 end end
            per[#per + 1] = skill .. "=" .. n
        end
        table.sort(per)
        realPrint(string.format("     GF-009-10 shipped catalog: decode+map %.1f ms, %d linkable, %d names on 2+ items; %s",
            mapMs, m.n, m.dup, table.concat(per, " ")))
    end))
end
