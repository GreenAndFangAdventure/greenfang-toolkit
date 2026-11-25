-- GF-UI-D (0.15.0): the theme. Only the game's own art and fonts; no red
-- UIPanelButton (or any other framed Blizzard template) outside Theme.lua;
-- every page's buttons, check boxes, edit boxes and windows come from the
-- theme. Made-up names only.

return function(T)
    local test, eq, ok, wow, ADDON_DIR = T.test, T.eq, T.ok, T.wow, T.ADDON_DIR
    local RECIPE, SKILL = 2660, 164

    local function login(opts)
        wow.reset(opts)
        local ns = wow.login(ADDON_DIR)
        ns.Orders.resetSession(); ns.Adventure.resetSession()
        return ns
    end
    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end
    -- The files the client loads, from the TOC.
    local function tocFiles()
        local list = {}
        for line in read(ADDON_DIR .. "/GreenFangToolkit.toc"):gmatch("[^\r\n]+") do
            if not line:find("^##") and line:find("%S") then list[#list + 1] = (line:gsub("%s+$", "")) end
        end
        return list
    end
    -- Code without its comments (a comment may name what is no longer used).
    local function code(path)
        local s = read(path):gsub("%-%-%[%[.-%]%]", "")
        local out = {}
        for line in (s .. "\n"):gmatch("(.-)\r?\n") do out[#out + 1] = (line:gsub("%-%-.*$", "")) end
        return table.concat(out, "\n")
    end

    -- The red button and the other framed templates the theme replaces.
    local BANNED = { "UIPanelButtonTemplate", "UIPanelButtonGrayTemplate", "UIPanelCloseButton", "UICheckButtonTemplate",
        "InputBoxTemplate", "BasicFrameTemplate", "GameMenuButtonTemplate", "OptionsButtonTemplate", "UIRadioButtonTemplate",
        "UI-Panel-Button", "UI-Panel-MinimizeButton", "UI-DialogBox-Button", "UIPanelButton" }

    test("GF-UI-D no file uses UIPanelButtonTemplate, the red button look or a framed template outside Theme.lua", function()
        local files = tocFiles()
        ok(#files >= 30, "the TOC lists the files: " .. #files)
        local seenTheme = false
        for _, name in ipairs(files) do
            if name == "Theme.lua" then seenTheme = true
            else
                local src = code(ADDON_DIR .. "/" .. name)
                for _, b in ipairs(BANNED) do
                    ok(not src:find(b, 1, true), name .. " uses " .. b)
                end
            end
        end
        ok(seenTheme, "Theme.lua is loaded")
        eq(files[1] .. "," .. files[2] .. "," .. files[3], "Config.lua,Core.lua,Theme.lua", "the theme right after Core")
    end)

    test("GF-UI-D game art only: every texture path is the game's (Interface\\...), the TOC loads only Lua", function()
        for _, name in ipairs(tocFiles()) do
            ok(name:find("%.lua$"), "only Lua files in the TOC: " .. name)
            local src = read(ADDON_DIR .. "/" .. name)
            ok(not src:lower():find("interface\\\\addons\\\\", 1, true), name .. ": no texture from an AddOn folder")
            for lit in src:gmatch('"([^"\n]*%.[TtBbPp][GgLlNn][AaPpGg])"') do
                ok(false, name .. ": an image file of our own: " .. lit)
            end
            for path in src:gmatch('"(Interface\\\\[^"]+)"') do
                ok(not path:find("/", 1, true), name .. ": a game path uses backslashes: " .. path)
            end
        end
        -- The theme's own textures are all Blizzard paths.
        local ns = login()
        local Th = ns.Theme
        for k, v in pairs(Th.TEX) do
            if type(v) == "string" then ok(v:find("^Interface\\"), "TEX." .. k .. " " .. v) end
        end
        for k, v in pairs(Th.TEX.coin) do ok(v:find("^Interface\\MoneyFrame\\"), "coin " .. k) end
    end)

    test("GF-UI-D fonts: every theme font copies a game font at 16 px or more", function()
        local ns = login()
        for k, name in pairs(ns.Theme.FONT) do
            local fo = rawget(_G, name)
            ok(fo, "font object " .. k)
            if fo._fontSize then ok(fo._fontSize >= 16, k .. ": " .. tostring(fo._fontSize)) end
        end
    end)

    test("GF-UI-D the button: outlined, hover in the HIGHLIGHT layer, chosen = gold line + faint gold fill", function()
        local ns = login()
        local Th = ns.Theme
        local b = Th.button(UIParent, "測試", 80)
        eq(b.gfTheme, "button", "theme button")
        eq(b._template, nil, "no template")
        eq(b._h, ns.BUTTON_H, "30 px")
        eq(#b.gfEdges, 4, "a 1 px line on four sides")
        eq(b.gfEdges[1]._h, 1, "1 px")
        eq(b.gfHover._layer, "HIGHLIGHT", "hover drawn by the client under the mouse")
        ok(b.gfFill._color[4] < 0.1, "see-through fill")
        Th.setSelected(b, true)
        -- GF-UI-G: chosen = the olive fill #3B4630 and the brass line #B49B63 (never a flat yellow block).
        eq(table.concat(b.gfEdges[1]._color, ",", 1, 3), table.concat(Th.C.selLine, ",", 1, 3), "brass line")
        eq(table.concat(b.gfFill._color, ",", 1, 3), table.concat(Th.C.selFill, ",", 1, 3), "olive fill")
        ok(b.gfFill._color[1] < 0.3 and b.gfFill._color[2] < 0.3, "dark, not yellow")
        Th.setSelected(b, false)
        eq(b.gfEdges[1]._color[1], Th.C.line[1], "grey again")
        -- Pages that lock the highlight of a chosen tab get the chosen look.
        b:LockHighlight(); ok(b.gfSelected, "LockHighlight = chosen")
        b:UnlockHighlight(); ok(not b.gfSelected, "UnlockHighlight = not chosen")
        -- The X: the game font's letter, no red art, top right.
        local f = Th.window("GFThemeTestWindow", UIParent, 300, 200)
        eq(f.CloseButton.gfTheme, "close", "the theme's X")
        eq(f.CloseButton._texture, nil, "no texture on the X")
        eq(f.CloseButton._points[1][1], "TOPRIGHT", "top right")
        ok(f.gfOpaque and f.gfOpaque._color[4] >= 0.95, "near-black, not see-through")
        wow.click(f.CloseButton)
        ok(not f:IsShown(), "the X closes the window")
    end)

    test("GF-UI-D every page and popup: buttons, boxes and windows come from the theme", function()
        local ns = login({ guildPerms = { invite = true, viewOfficer = true, motd = true, info = true }, myRankIndex = 0 })
        local U = ns.AdventureUI
        ns.Framework.open("roster")
        ns.Framework.open("recipes")
        ns.Framework.open("orders")
        ns.Framework.open("adventure")
        ns.Framework.open("character")
        ns.Diag.open()
        ns.OrdersUI.openOrder({ recipe = RECIPE, skill = SKILL, crafters = {} })
        ns.OrdersUI.editFee({ skill = SKILL })
        ns.UI.openGuildInfo()
        U.openTicket()
        U.openWorker()
        U.openCalendar()
        U.openRules()
        ns.Widgets.confirm("刪除", function() end)
        local n = { button = 0, check = 0, edit = 0, window = 0 }
        for _, o in ipairs(wow.allObjects()) do
            local t = o._template
            for _, b in ipairs(BANNED) do ok(not (t and t:find(b, 1, true)), "a " .. tostring(t) .. " " .. tostring(o._text)) end
            if o._kind == "CheckButton" then eq(o.gfTheme, "check", "check box from the theme"); n.check = n.check + 1 end
            if o._kind == "EditBox" then
                eq(o.gfTheme, "edit", "edit box from the theme")
                n.edit = n.edit + 1
            end
            if o._kind == "Button" and o.gfTheme == "button" then n.button = n.button + 1 end
            if o.gfTheme == "window" then n.window = n.window + 1 end
        end
        ok(n.button >= 40, "theme buttons: " .. n.button)
        ok(n.check >= 2, "check boxes: " .. n.check)
        ok(n.edit >= 4, "edit boxes: " .. n.edit)
        ok(n.window >= 5, "theme windows: " .. n.window)
        -- The main window and the module list: the open module is the chosen (gold) one.
        local win = _G[ns.Framework.WINDOW_NAME]
        eq(win.gfTheme, "window", "main window")
        for _, b in ipairs(ns.Framework.navButtons()) do
            if b:IsShown() then eq(b.gfSelected, b.moduleId == ns.Framework.current(), "chosen module: " .. b.moduleId) end
        end
        -- ESC still closes the top window first.
        local top = ns.escTop()
        ok(top, "something open")
        wow.pressEscape()
        ok(not top:IsShown(), "ESC closed the top one")
    end)

    test("GF-UI-D the grid tabs and the roster header use the theme's chosen look and header bar", function()
        local ns = login()
        local U = ns.AdventureUI
        U.openTicket()
        local grid = U.pickDestination(_G[U.TICKET_NAME].dest)
        local chosen = 0
        for _, b in ipairs(grid.tabs) do
            if b:IsShown() then
                eq(b.gfSelected, b.selected, "tab " .. tostring(b.category))
                if b.gfSelected then chosen = chosen + 1 end
            end
        end
        eq(chosen, 1, "one chosen tab")
        ns.Framework.open("roster")
        ok(ns.UI.header.gfHeadFill and ns.UI.header.gfHeadLine, "roster header: fill and line")
        eq(ns.UI.header.gfHeadLine._h, 1, "1 px line under the header")
    end)

    test("GF-UI-D coins: numbers in gold / silver / copper with the game's coin icons", function()
        local ns = login()
        local s = ns.Theme.coinText(12345)
        ok(s:find("|cffffd100" .. "1|r|TInterface\\MoneyFrame\\UI-GoldIcon", 1, true), "gold: " .. s)
        ok(s:find("23|r|TInterface\\MoneyFrame\\UI-SilverIcon", 1, true), "silver")
        ok(s:find("45|r|TInterface\\MoneyFrame\\UI-CopperIcon", 1, true), "copper")
        ok(ns.Theme.coinText(0):find("0|r|TInterface\\MoneyFrame\\UI-CopperIcon", 1, true), "zero = 0 copper")
        -- Where the client has coin art, UI.money uses it.
        GetCoinTextureString = function(c) return tostring(c) end
        eq(ns.OrdersUI.money(12345), s, "UI.money")
        GetCoinTextureString = nil
        -- GF-UI-H (owner: 金額一律用金／銀／銅圖示): the icons without it too, never "1g 23s 45c".
        eq(ns.OrdersUI.money(12345), s, "coin icons without GetCoinTextureString")
    end)

    ---------------------------------------------------------------------------
    -- GF-UI-D2 (0.15.1, owner: 「不能互動的圖示就不要再可以亮」「訂單的取消，取消後還會亮」)
    ---------------------------------------------------------------------------

    -- Mouse over b: its OnEnter runs (as in the client); true when its hover art shows.
    local function hover(b)
        local fn = b:GetScript("OnEnter")
        if fn then fn(b) end
        local lit = b.gfHoverOn == true
        -- The hover art follows: faded out (alpha 0) when it may not light.
        for _, t in ipairs({ b.gfHover, b.gfHl, (b.gfHoverEdges or {})[1] }) do
            if t then eq(t._alpha, lit and 1 or 0, "hover art alpha") end
        end
        if b:GetScript("OnLeave") then b:GetScript("OnLeave")(b) end
        return lit
    end

    test("GF-UI-D2 only what can be pressed lights up: disabled, tooltip-only and click-less controls stay dark", function()
        local ns = login()
        local Th, W = ns.Theme, ns.Widgets
        local b = ns.OrdersUI.textButton(UIParent, "測試", function() end)
        ok(hover(b), "an enabled button lights up")
        b:Disable(); ok(not hover(b), "Disable: dark")
        b:Enable(); ok(hover(b), "Enable: lit again")
        b:SetEnabled(false); ok(not hover(b), "SetEnabled(false): dark")
        eq(b.gfEdges[1]._color[4], 0.55, "and its line dimmed")
        b:SetEnabled(true)
        W.setEnabled(b, false); ok(not hover(b), "Widgets.setEnabled: dark")
        W.setEnabled(b, true); ok(hover(b), "and back")
        -- A handler set later still checks first.
        b:SetScript("OnEnter", function() end)
        b:Disable(); ok(not hover(b), "a later OnEnter handler: still dark")
        -- Nothing to click: no light.
        ok(not hover(Th.button(UIParent, "無", 60)), "a button without OnClick")
        -- Icons: a tooltip-only one never lights; a clickable one does.
        local icon = ns.OrdersUI.iconButton(UIParent, 28, "deal", "說明")
        ok(not hover(icon), "an icon with only a tooltip")
        icon:SetScript("OnClick", function() end)
        ok(hover(icon), "the same icon once it can be pressed")
        Th.infoOnly(icon); ok(not hover(icon), "marked tooltip-only")
        -- The X and a check box light up (they can be pressed).
        local f = Th.window("GFThemeHoverWindow", UIParent, 200, 120)
        ok(hover(f.CloseButton), "the X")
        local c = ns.checkBox(UIParent, "測試", 0, 0, function() end)
        ok(hover(c), "a check box")
        c:Disable(); ok(not hover(c), "a disabled check box")
        -- The adventure state badge and the right-click menu's header line.
        local badge = W.statusBadge(UIParent)
        ok(not Th.hoverable(badge), "the state badge only shows its checklist")
        local menu = ns.showMenu(UIParent, { { text = "會階 3", header = true }, { text = "密語", fn = function() end } })
        ok(not hover(menu.items[1]), "the menu header line stays dark")
        ok(hover(menu.items[2]), "a menu item lights")
        ns.closeMenus()
    end)

    test("GF-UI-D2 a cancelled order: 取消 lights while it can be undone, then nothing on the row lights", function()
        local ns = login()
        local O, U, Th = ns.Orders, ns.OrdersUI, ns.Theme
        O.setTestMode(true)
        local me = ns.Share.selfAuthor()
        local d = U.openOrder({ recipe = RECIPE, skill = SKILL,
            crafters = { { name = "測試甲-測試伺服器", guid = ns.Data.player().guid, online = true, self = true } } })
        eq(d.crafter, me, "the test order to myself")
        local id = U.submit(d)
        ns.Framework.open("orders")
        local function row()
            for _, r in ipairs(U.rowFrames()) do if r:IsShown() and r.view and r.view.id == id then return r end end
        end
        local r = row()
        local cancel = r.buttons[2]
        eq(cancel.label._text, "取消", "取消")
        ok(hover(cancel), "取消 lights (it can be pressed)")
        wow.click(cancel)
        r = row()
        eq(r.buttons[2].tip, "復原", "for 5 s it is 復原")
        ok(hover(r.buttons[2]), "復原 lights (it can be pressed)")
        wow.advance(5.5)
        eq(O.get(id).state, "cancel", "cancelled")
        r = row()
        ok(r, "the row is still listed")
        for _, b in ipairs(r.buttons) do ok(not b:IsShown(), "no action button on a closed order") end
        eq(r.state.label._text, "取消", "the state says 取消")
        ok(not hover(r.state), "the 取消 state icon does not light")
        ok(not Th.hoverable(r.item), "nor the item icon (tooltip only)")
        for _, o in ipairs(wow.allObjects()) do
            local p, inside = o, false
            while p do if p == r then inside = true end p = p._parent end
            if inside and o._kind == "Button" and o._shown then ok(not Th.hoverable(o), "nothing on the row lights: " .. tostring(o.tip)) end
        end
        -- Undone in time: back to 取消, lit.
        local d2 = U.openOrder({ recipe = RECIPE, skill = SKILL,
            crafters = { { name = "測試甲-測試伺服器", guid = ns.Data.player().guid, online = true, self = true } } })
        local id2 = U.submit(d2)
        id = id2
        r = row()
        wow.click(r.buttons[2]); r = row()
        wow.click(r.buttons[2]); r = row() -- 復原
        wow.advance(5.5)
        eq(O.get(id2).state, "waiting", "undone: still waiting")
        eq(r.buttons[2].tip, "取消", "取消 again")
        ok(hover(r.buttons[2]), "and it lights")
    end)
end
