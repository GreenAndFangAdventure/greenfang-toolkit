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
        eq(table.concat(b.gfEdges[1]._color, ",", 1, 3), "1,0.82,0", "gold line")
        ok(b.gfFill._color[4] > 0 and b.gfFill._color[4] < 0.2, "faint gold fill, never a flat yellow block")
        eq(b.gfFill._color[1] .. "," .. b.gfFill._color[2], "1,0.82", "gold tint")
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
        eq(ns.OrdersUI.money(12345), "1g 23s 45c", "plain letters without coin art")
    end)
end
