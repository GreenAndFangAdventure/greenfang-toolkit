-- GF-006-D: the owner's 0.16.19 screenshots of 委託業務 → ＋下單: the recipe
-- picker filters and scrolls; every material of the order can be brought in
-- part (自帶 count); every icon explains itself by the mouse; 材料費 / 行情
-- say what they are missing instead of a bare 「＞」 or an empty coin.
-- Offline only; not checked in the Forever client. Made-up data.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local shareLogin, shareFrom, rMsg, leatherWindow = T.shareLogin, T.shareFrom, T.rMsg, T.leatherWindow
    local PEER, A_PEER, A_THIRD = T.PEER, T.A_PEER, T.A_THIRD
    local A, B = "0000-0000000A", "0000-0000000B"
    local RECIPE, ITEM, SKILL = 2660, 2862, 164
    local ORE, STONE, CLOTH = 2770, 2835, 2589

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Prices.resetSession(); ns.Delivery.resetSession()
        return ns
    end
    local function lines()
        local out = {}
        for _, l in ipairs(GameTooltip._lines or {}) do out[#out + 1] = tostring(l.text) end
        return table.concat(out, "\n")
    end
    local function has(s, sub) return tostring(s):find(sub, 1, true) ~= nil end
    local function hover(f) f._scripts.OnEnter(f); return lines() end
    local function items(ns, bag, names)
        C_Item = {
            GetItemCount = function(id) return (bag or {})[id] or 0 end,
            GetItemNameByID = function(id) return (names or {})[id] end,
        }
    end
    local NAMES = { [ITEM] = "測試銅錘", [ORE] = "測試銅錠", [STONE] = "測試石頭", [CLOTH] = "測試亞麻布" }

    -- The picker over a peer taking 製皮 orders (2152, 2153), a third member (offline,
    -- 2153, 2160) and 30 more 鍛造 recipes from the third member (a long list).
    local function pickerLogin()
        local ns = shareLogin({ tradeSkill = leatherWindow() })
        wow.fire("TRADE_SKILL_SHOW")
        local t = wow.state.now - 600
        shareFrom(ns, PEER, (rMsg(ns, A_PEER, 165, t, { 2152, 2153 })))
        local many = {}
        shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 165, t, { 2153, 2160 })))
        for i = 1, 30 do many[i] = 3000 + i end
        shareFrom(ns, PEER, (rMsg(ns, A_THIRD, 164, t, many)))
        local sv = ns.Orders.encodeServices({ active = { [165] = true }, fees = { [165] = 500 }, recipeFees = {}, recipeSkill = {} })
        ns.Orders.ledger:offer(A_PEER, "O", ns.Share.serverNow(), ns.Share.hash(sv), sv)
        return ns
    end
    local function ids(list)
        local out = {}
        for _, r in ipairs(list) do out[#out + 1] = r.id end
        table.sort(out)
        return table.concat(out, ",")
    end

    ---------------------------------------------------------------------------
    -- A. The recipe picker: filters, scrolling, cache
    ---------------------------------------------------------------------------

    -- GF-UI-S (owner 2026-11-28): the 選配方 window is gone; ＋下單 goes to 工匠配方,
    -- whose filters (搜尋, 專業, 會做的人, 只看在線, 接單中, 工錢) and scrolling are
    -- tested with that page (run.lua D19 / D22, gffixc_tests.lua, gfuis_tests.lua 6).
    -- A1-A5 tested the window itself and were removed.

    ---------------------------------------------------------------------------
    -- B. 自帶 counts per material
    ---------------------------------------------------------------------------

    local function withRecipe(ns, bag)
        items(ns, bag, NAMES)
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 3 }, { id = STONE, n = 2 } } })
        ns.Prices.db().vendor[STONE] = ns.Share.b36(40) .. ".1"
        ns.Prices.db().vendor[ORE] = ns.Share.b36(100) .. ".1"
    end

    test("GF-006-D B1 the form: one row per material (name, 需要, 背包, 自帶, cost); default = as before", function()
        local ns = login()
        withRecipe(ns, { [ORE] = 5 })
        local U = ns.OrdersUI
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        eq(d.mats[ORE], true, "enough ore in the bags: all brought (as before)"); eq(d.mats[STONE], nil, "stone not")
        local r1, r2 = f.matRows[1], f.matRows[2]
        eq(r1.name._text, "測試銅錠", "the item's name"); eq(r1.needText._text, "x3", "needed"); eq(r1.haveText._text, "5", "in the bags")
        eq(r1.box._text, "3", "自帶 3"); eq(r1.cost._text, U.TEXT.bringAll, "nothing to pay")
        eq(r2.box._text, "0", "自帶 0"); ok(has(r2.cost._text, "80"), "2 x 40")
        ok(not (f.matRows[3] and f.matRows[3]:IsShown()), "two rows only")
        eq(f.matsCost._text, U.money(80), "材料費 = the stone only")
        -- Bring one stone: only the other one is charged.
        r2.box:SetText("1"); r2.box._scripts.OnTextChanged(r2.box, true)
        eq(d.mats[STONE], 1, "1 stone")
        eq(f.matsCost._text, U.money(40), "材料費 = one stone")
        -- More than needed is cut to the need (all).
        r2.box:SetText("9"); r2.box._scripts.OnTextChanged(r2.box, true)
        eq(r2.box._text, "2", "cut to 2"); eq(d.mats[STONE], true, "all")
        -- The icon still switches all / none.
        wow.click(r1.icon)
        eq(d.mats[ORE], nil, "ore: none"); eq(f.matsCost._text, U.money(300), "3 ore")
        wow.click(r1.icon)
        eq(d.mats[ORE], true, "ore: all again")
        C_Item = nil
    end)

    test("GF-006-D B2 the count follows the quantity; the order stores itemID -> count (the contract's mats)", function()
        local ns = login()
        withRecipe(ns, {})
        local U = ns.OrdersUI
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = { { name = "測試乙", guid = "Player-" .. B, online = true } } })
        U.setBring(d, ORE, 2, 3)
        U.setBring(d, STONE, 2, 2)
        wow.click(_G[U.POPUP_NAME].plus) -- qty 2: ore 6, stone 4
        local est = U.estimateOf(d)
        eq(est.mats[1].own, 2, "2 ore brought of 6"); eq(est.mats[1].buy, 4, "4 bought")
        eq(est.mats[2].own, 4, "all stones follow the quantity")
        eq(est.total, 400, "4 ore x 100")
        local id = U.submit(d)
        local v = ns.Orders.get(id)
        eq(v.mats[ORE], 2, "ore: 2"); eq(v.mats[STONE], 4, "stone: all 4")
        eq(ns.Orders.decodeList(ns.Orders.ledger:get(A, "W").v)[1].m, "2770*2+2835*4", "the same m field, a part count")
        local up = ns.Orders.craftingFor(A).orders[id].w
        eq(up.mats[tostring(ORE)], 2, "upload: the same mats map, a smaller count")
        eq(up.quote, 400, "quote = the bought part")
        C_Item = nil
    end)

    test("GF-006-D B3 an old order (no part counts: the whole need) shows ✓ as before; the crafter sees it", function()
        local ns = login()
        withRecipe(ns, {})
        local t = ns.Share.serverNow()
        -- Written by an older version: m has the whole need of ore, no stone.
        local w = ns.Orders.encodeList({ { id = "gbbb.1", src = "g", ver = 1, cr = t, rc = RECIPE, it = ITEM, sk = SKILL, q = 1,
            cf = A, m = "2770*3", fe = 0, st = "o", sa = t } })
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash(w), w)
        ns.Framework.open("orders")
        local row
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r:IsShown() and r.view and r.view.id == "gbbb.1" then row = r end end
        ok(row, "the row")
        local ore, stone = row.mats[1], row.mats[2]
        ok(ore.badge._shown, "ore: ✓ (all brought)")
        ok(not (ore.countText and ore.countText._shown), "no number")
        ok(not stone.badge._shown, "stone: no mark (the crafter provides it)")
        ok(has(hover(ore), "全部自帶"), "the tooltip says all brought")
        ok(has(hover(stone), "工匠準備"), "the tooltip says the crafter provides it")
        C_Item = nil
    end)

    test("GF-006-D B4 a new order with a part count: the crafter sees the number; an old reader still decodes it", function()
        local ns = login()
        withRecipe(ns, {})
        local t = ns.Share.serverNow()
        local w = ns.Orders.encodeList({ { id = "gbbb.2", src = "g", ver = 1, cr = t, rc = RECIPE, it = ITEM, sk = SKILL, q = 2,
            cf = A, m = "2770*2+2835*4", fe = 0, st = "o", sa = t } })
        ns.Orders.ledger:offer(B, "W", t, ns.Share.hash(w), w)
        ns.Framework.open("orders")
        local row
        for _, r in ipairs(ns.OrdersUI.rowFrames()) do if r:IsShown() and r.view and r.view.id == "gbbb.2" then row = r end end
        local ore, stone = row.mats[1], row.mats[2]
        ok(not ore.badge._shown, "ore: not all")
        eq(ore.countText._text, "2", "ore: 2 brought"); ok(ore.countText._shown, "shown")
        ok(stone.badge._shown, "stone: all (✓)")
        local text = hover(ore)
        ok(has(text, "自帶 2 個") and has(text, "工匠準備 4 個"), "the tooltip: " .. text)
        -- What an old version does with it: the same decoder (decodeMats) reads every pair;
        -- it only looks at "is there a count" (✓), so it shows ✓ for the part too (no error).
        local m = ns.Orders.decodeMats("2770*2+2835*4")
        eq(m[ORE], 2, "decoded"); eq(m[STONE], 4, "decoded")
        local old = {}
        for id in pairs(m) do old[#old + 1] = id end
        eq(#old, 2, "an old reader lists both as brought (no error)")
        C_Item = nil
    end)

    test("GF-006-D B5 many materials: the material rows scroll (4 in view, the same frames)", function()
        local ns = login()
        local list = {}
        for i = 1, 7 do list[i] = { id = 5000 + i, n = 1 } end
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = list })
        local U = ns.OrdersUI
        U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        eq(#f.matRows, U.MAT_ROWS, "4 row frames")
        ok(f.matBar._shown ~= false and f.matBar.scrollable, "a scroll bar")
        f.matBar.scrollTo(3)
        eq(f.matRows[U.MAT_ROWS].id, 5007, "the last material in the last row")
        eq(#f.matRows, U.MAT_ROWS, "no new rows")
    end)

    ---------------------------------------------------------------------------
    -- C. Hints on every icon; the product's name; the chosen 對象
    ---------------------------------------------------------------------------

    test("GF-006-D C1 the product shows its name (C_Item), the recipe's name before the item is known", function()
        local ns = login()
        withRecipe(ns, {})
        local U = ns.OrdersUI
        U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        eq(f.item.label._text, "測試銅錘", "the item's name, not 成品")
        -- Not known yet: loading, and the name arrives later.
        items(ns, {}, {})
        U.drawPopup()
        eq(f.item.label._text, U.TEXT.productLoading, "loading")
        items(ns, {}, NAMES)
        ns.Widgets.itemAnswer(ITEM, true)
        eq(f.item.label._text, "測試銅錘", "filled in when the client answers")
        -- No reagent list (asked the guild): the recipe's name.
        U.openOrder({ recipe = 99999, skill = SKILL, crafters = {} })
        eq(f.item.label._text, ns.Recipes.name(99999), "the recipe's name")
        C_Item = nil
    end)

    test("GF-006-D C2 every icon on the form has a hint by the mouse", function()
        local ns = login()
        withRecipe(ns, {})
        local U = ns.OrdersUI
        U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        local list = { item = f.item, guild = f.guild, named = f.named, minus = f.minus, plus = f.plus,
            matsIcon = f.matsIcon, feeIcon = f.feeIcon, marketIcon = f.marketIcon,
            matIcon = f.matRows[1].icon, matBox = f.matRows[1].box }
        for name, b in pairs(list) do
            local text = hover(b)
            ok(text ~= "" and GameTooltip:GetOwner() == b, name .. ": a hint")
            ok(b.tipPoint ~= nil, name .. ": by the mouse (rowTip)")
        end
        ok(has(hover(f.named), "小錘子"), "the hammer badge explained")
        ok(has(hover(f.feeIcon), "紅色問號"), "the red ? explained")
        ok(has(hover(f.matRows[1].icon), "自帶"), "the material icon explains 自帶")
        C_Item = nil
    end)

    test("GF-006-D C3 對象: the chosen one glows, the other is dimmed; the named crafter's name is shown", function()
        local ns = login()
        withRecipe(ns, {})
        local U = ns.OrdersUI
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        ok(f.guild.selected and not f.named.selected, "公會單 chosen")
        ok(has(hover(f.guild), "目前選的是這個"), "the hint says so")
        d.crafter = ns.Share.authorOf("Player-" .. B) or B
        U.drawPopup()
        ok(f.named.selected and not f.guild.selected, "指定工匠 chosen")
        ok(has(f.named.label._text, "指定工匠"), "the label")
        C_Item = nil
    end)

    ---------------------------------------------------------------------------
    -- D. 材料費 and 行情
    ---------------------------------------------------------------------------

    test("GF-006-D D1 材料費: 「＞」 names the materials without a price; nothing made up", function()
        local ns = login()
        items(ns, {}, NAMES)
        ns.Prices.storeReagents(RECIPE, { output = ITEM, yield = 1, list = { { id = ORE, n = 1 }, { id = STONE, n = 2 }, { id = CLOTH, n = 1 } } })
        ns.Prices.db().vendor[STONE] = ns.Share.b36(15) .. ".1"
        local U = ns.OrdersUI
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        local s = f.matsCost._text
        ok(has(s, "＞") and has(s, "30"), "a lower bound: " .. s)
        ok(has(s, "測試銅錠") and has(s, "測試亞麻布"), "names the two without a price")
        ok(not has(s, "測試石頭"), "not the one with a price")
        eq(f.matRows[1].cost._text, U.TEXT.noPrice, "the row says 沒有價格")
        ok(has(f.total._text, "＞"), "合計 too")
        -- Bring the unpriced ones: the cost is exact, no 「＞」.
        U.setBring(d, ORE, 1, 1); U.setBring(d, CLOTH, 1, 1); U.drawPopup()
        eq(f.matsCost._text, U.money(30), "exact")
        ok(not has(f.total._text, "＞"), "合計 exact")
        C_Item = nil
    end)

    test("GF-006-D D2 行情: words when there is no data; the price when there is; a single report marked", function()
        local ns = login()
        withRecipe(ns, {})
        local U = ns.OrdersUI
        U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        eq(f.market._text, U.TEXT.noMarket, "no data: says so, and how to get it")
        eq(f.marketSource, "none", "none")
        ns.Prices.marketOf = function() return { price = 12345, source = "addon" } end
        U.drawPopup()
        eq(f.market._text, U.money(12345), "the price"); eq(f.marketSource, "addon", "from an addon")
        ns.Prices.marketOf = function() return nil end
        ns.Prices.reference = function() return { price = 500, single = true, newestDay = 1 } end
        U.drawPopup()
        ok(has(f.market._text, U.TEXT.marketSingle), "a single report is marked: " .. f.market._text)
        C_Item = nil
    end)

    test("GF-006-D D3 no reagent list yet: says it was asked; the answer fills the open form", function()
        local ns = login()
        items(ns, {}, NAMES)
        local U = ns.OrdersUI
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        eq(f.matsCost._text, U.TEXT.noList, "材料費 says the list is asked for")
        eq(f.matEmpty._text, U.TEXT.noList, "and the material area")
        ok(has(f.total._text, "＞"), "合計 is a lower bound")
        -- A member answers.
        ns.Orders.onCustom("S", { ns.Share.b36(RECIPE), "2862.1.2770*3+2835*2" }, nil, "GUILD")
        ok(d.reagents and #d.reagents.list == 2, "the draft has the list")
        eq(f.matRows[1].name._text, "測試銅錠", "the rows are filled")
        eq(f.item.label._text, "測試銅錘", "and the product")
        eq(f.matEmpty._text, "", "no more waiting text")
        C_Item = nil
    end)

    test("GF-006-D D4 Prices.estimate: true = all, a count = part, the rest charged; missing listed", function()
        local ns = login()
        local P = ns.Prices
        local r = { output = ITEM, yield = 1, list = { { id = ORE, n = 3 }, { id = STONE, n = 2 } } }
        local price = { [ORE] = { price = 10 } }
        local e = P.estimate(r, 2, { [ORE] = 4, [STONE] = true }, function(id) return price[id] end)
        eq(e.mats[1].need, 6, "6 ore"); eq(e.mats[1].own, 4, "4 brought"); eq(e.total, 20, "2 x 10")
        eq(e.mats[2].own, 4, "all stones"); eq(e.unknown, false, "nothing unknown (the stone is not bought)")
        e = P.estimate(r, 1, { [ORE] = 1 }, function(id) return price[id] end)
        eq(e.total, 20, "2 ore bought"); eq(e.unknown, true, "stone has no price")
        eq(table.concat(e.missing, ","), tostring(STONE), "missing: the stone")
        e = P.estimate(r, 1, { [ORE] = 99 }, function(id) return price[id] end)
        eq(e.mats[1].own, 3, "a count over the need is the need")
    end)

    ---------------------------------------------------------------------------
    -- E. Performance and no polling
    ---------------------------------------------------------------------------

    test("GF-006-D E1 no OnUpdate in OrdersUI; the order window makes its material rows once", function()
        local ns = login()
        withRecipe(ns, {})
        local h = io.open(ADDON_DIR .. "/OrdersUI.lua", "rb"); local src = h:read("*a"); h:close()
        ok(not src:find("OnUpdate", 1, true), "no OnUpdate")
        ok(not src:find("NewTicker", 1, true), "no ticker")
        local U = ns.OrdersUI
        U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        local f = _G[U.POPUP_NAME]
        local first = f.matRows[1]
        for _ = 1, 20 do U.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} }) end
        ok(f.matRows[1] == first, "the same row frame")
        C_Item = nil
    end)
end
