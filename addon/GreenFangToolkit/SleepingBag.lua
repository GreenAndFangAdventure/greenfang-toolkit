-- Sleeping bag route helper (GF-008-A), a toolkit module.
--   RPG mode:    landmark and direction; coordinates and the full route only
--                after the player presses "顯示座標與走法".
--   Normal mode: every step with coordinates, travel and alternatives.
-- Both modes share one progress per character (settings.modules.sleepingbag
-- .characters[GUID]). Progress is confirmed by hand; no quest IDs are used yet.
--
-- GF-008-B (owner 2026-11-26: 「睡袋指南先只有一般模式就好」): only normal
-- mode is shown. The RPG code and the saved mode stay (SB.RPG_ON brings the
-- switch back); a character saved in "rpg" keeps its mode and its step and
-- simply sees normal mode. 看地圖 opens the world map on the step's zone with
-- a pin (SleepingBagMap.lua). GF-008-C (owner: 「每一步都應該要有地圖處」):
-- every step has a map; a step without x / y opens its map without a pin.
-- GF-008-D: a short guide (位置 first, one action, one tip), the map colour
-- legend, and the route chosen by its faction field.

local _, ns = ...
local str = ns.str

local SB = {}
ns.SleepingBag = SB
SB.ID = "sleepingbag"
SB.MODES = { rpg = "RPG 模式", normal = "一般模式" }
SB.RPG_ON = false -- GF-008-B: true shows the RPG / normal switch again

local panel, modeButton, progressLine, bodyText, revealButton, doneButton, backButton, resetButton, mapButton
local scroll, scrollChild

---------------------------------------------------------------------------
-- State (pure; covered by offline tests)
---------------------------------------------------------------------------

-- GF-008-D: the route whose `faction` field is the player's (Horde when the
-- faction is not known yet). An Alliance route is only data (SleepingBagData).
function SB.route(faction)
    faction = faction or ns.Data.player().faction
    if faction == nil or faction == "" then faction = "Horde" end
    for _, route in pairs(ns.SleepingBagRoutes or {}) do
        if type(route) == "table" and route.faction == faction then return route end
    end
    return nil
end

function SB.state()
    local s = ns.Framework.charState(SB.ID)
    local route = SB.route()
    local count = route and #route.steps or 0
    if type(s.step) ~= "number" or s.step < 1 then s.step = 1 end
    if s.step > count + 1 then s.step = count + 1 end -- count + 1 = finished
    if not SB.MODES[s.mode] then s.mode = "rpg" end
    if type(s.revealed) ~= "table" then s.revealed = {} end
    if type(s.completedAt) ~= "table" then s.completedAt = {} end
    return s
end

function SB.isFinished()
    local route = SB.route()
    return route ~= nil and SB.state().step > #route.steps
end

function SB.currentStep()
    local route = SB.route()
    if not route then return nil end
    return route.steps[SB.state().step]
end

-- GF-008-B: the mode the page shows (normal while the RPG switch is off).
function SB.viewMode()
    if SB.RPG_ON then return SB.state().mode end
    return "normal"
end

function SB.setMode(mode)
    if not SB.MODES[mode] then return end
    SB.state().mode = mode
    SB.refresh()
end

function SB.toggleMode()
    SB.setMode(SB.state().mode == "rpg" and "normal" or "rpg")
end

-- Manual confirmation of the current step.
function SB.complete()
    local s, step = SB.state(), SB.currentStep()
    if not step then return false end
    s.completedAt[step.id] = ns.now()
    s.step = s.step + 1
    SB.refresh()
    return true
end

function SB.back()
    local s = SB.state()
    if s.step <= 1 then return false end
    s.step = s.step - 1
    SB.refresh()
    return true
end

function SB.reset()
    local s = SB.state()
    s.step, s.revealed, s.completedAt = 1, {}, {}
    SB.refresh()
end

function SB.reveal()
    local step = SB.currentStep()
    if not step then return end
    SB.state().revealed[step.id] = true
    SB.refresh()
end

-- GF-008-C / D: the step's position line, always first. Integers on the page
-- (as the guides write them); the map's zone (a continent, a point on another
-- map), how sure the numbers are, or why the map has no point.
local function int(v) return math.floor(v) end
local CONF = { multi = "多來源一致", single = "單一來源" }
local function pointText(st, p)
    local zone = p.zone or st.mapZone or st.zone
    local t = string.format("%s（%d, %d）", zone, int(p.x), int(p.y))
    if p.conf == "approx" then return t .. "（大約：" .. str(p.approx or p.label) .. "）" end
    return t .. "（" .. (CONF[p.conf] or "單一來源") .. "）"
end
local function coords(step, all)
    local pts = step.points or {}
    if #pts > 0 then
        local out = {}
        for i, p in ipairs(pts) do
            if i == 1 or all then out[#out + 1] = pointText(step, p) .. (all and p.label and ("：" .. p.label) or "") end
        end
        return table.concat(out, "；")
    end
    local zone = step.mapZone or step.zone
    if step.noPin then return zone .. "（地圖不標位置：" .. step.noPin .. "）" end
    return step.zone .. "（座標待實地確認）"
end
SB.coords = coords

local VERIFY = "｜待實地驗證"

-- Lines describing one step for a mode. RPG hides coordinates and travel
-- details until revealed. GF-008-D: normal mode is short and fixed: 位置 first,
-- one line to do, one tip, then how to get there.
function SB.stepLines(step, mode, revealed)
    local lines = {}
    local function add(label, value) if value and value ~= "" then lines[#lines + 1] = label .. value end end
    if mode == "rpg" and not revealed then
        add("地區：", step.zone)
        add("地標：", step.landmark)
        add("方向：", step.rpgHint)
        if step.object then add("目標：", step.object) end
        lines[#lines + 1] = "（座標與詳細走法已隱藏，按「顯示座標與走法」揭示）" .. VERIFY
        return lines
    end
    add("位置：", coords(step, true))
    add("要做的事：", step.action)
    add("提示：", step.tip)
    add("前往方式：", step.travel)
    if step.object then add("目標：", step.object .. (step.objectEN and ("（" .. step.objectEN .. "）") or "")) end
    add("守衛與危險：", step.guards)
    add("沒有飛行點時：", step.noFlightPath)
    lines[#lines + 1] = "狀態：待實地驗證"
    return lines
end

-- Whole page text for the current state (mode: the one to draw; default the shown one).
function SB.pageText(mode)
    local route = SB.route()
    if not route then return "目前沒有你陣營的路線資料。" end
    local s = SB.state()
    mode = mode or SB.viewMode()
    local out = {}
    if SB.isFinished() then
        out[#out + 1] = "已完成全部 " .. #route.steps .. " 步。獎勵：" .. route.reward
        out[#out + 1] = "按「重設進度」可以從頭再走一次。"
        return table.concat(out, "\n")
    end
    local step = route.steps[s.step]
    out[#out + 1] = string.format("【第 %d 步】%s", s.step, step.zone)
    for _, line in ipairs(SB.stepLines(step, mode, s.revealed[step.id])) do out[#out + 1] = line end
    if mode == "normal" then
        -- GF-008-D: what the map colours mean (the text says 大約 too).
        if ns.SleepingBagMap and ns.SleepingBagMap.LEGEND then out[#out + 1] = ns.SleepingBagMap.LEGEND end
        out[#out + 1] = ""
        out[#out + 1] = "【全部步驟】"
        for i, st in ipairs(route.steps) do
            -- Only glyphs the zhTW game font has (GF-000-D): no check marks or arrows.
            local mark = (i < s.step and "完成 ") or (i == s.step and "＞ ") or "　　 "
            out[#out + 1] = string.format("%s%d. %s｜%s", mark, i, coords(st), str(st.object or st.landmark))
        end
    end
    out[#out + 1] = ""
    out[#out + 1] = route.note .. "需要 " .. route.minLevel .. " 級以上。資料來源：" .. route.source
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------

function SB.refresh()
    if not panel then return end
    local route, s = SB.route(), SB.state()
    local total = route and #route.steps or 0
    local mode = SB.viewMode()
    modeButton:SetText("目前：" .. SB.MODES[mode])
    if SB.RPG_ON then modeButton:Show() else modeButton:Hide() end -- GF-008-B
    progressLine:SetText(string.format("%s｜進度 %d / %d｜%s",
        route and route.title or "", math.min(s.step - 1, total), total,
        "每一步都待實地驗證，進度請自行確認"))
    local text = SB.pageText()
    bodyText:SetText(text)
    scrollChild:SetHeight(math.max(400, select(2, text:gsub("\n", "")) * 18 + 60))
    local step = SB.currentStep()
    if mode == "rpg" and step ~= nil and not s.revealed[step.id] then revealButton:Show() else revealButton:Hide() end
    doneButton:SetEnabled(step ~= nil)
    backButton:SetEnabled(s.step > 1)
    -- GF-008-B / C: 看地圖 for a step whose map this client can show (every step has one);
    -- not lit in combat (the world map cannot be opened then).
    local Map = ns.SleepingBagMap
    local can = Map and step and Map.canShow(step)
    if can then mapButton:Show() else mapButton:Hide() end
    mapButton:SetEnabled(can and not ns.inCombat() or false)
    if Map then Map.update(step, s.step) end
end

-- GF-008-B: 看地圖 for the current step.
function SB.showMap()
    local step, Map = SB.currentStep(), ns.SleepingBagMap
    if not (step and Map) then return false end
    return Map.show(step, SB.state().step)
end

local function button(parent, text, w, x, y, fn)
    local b = ns.Theme.button(parent, nil, w, ns.BUTTON_H) -- GF-UI-D: the theme's button
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function build(p)
    panel = p
    progressLine = p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    progressLine:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -38)
    progressLine:SetWidth(950)
    progressLine:SetJustifyH("LEFT")
    modeButton = button(p, "", 260, 20, -64, SB.toggleMode)
    -- GF-008-B: without the mode switch the row starts at the left edge.
    local x0 = SB.RPG_ON and 290 or 20
    doneButton = button(p, "完成這一步", 120, x0, -64, SB.complete)
    backButton = button(p, "上一步", 90, x0 + 128, -64, SB.back)
    revealButton = button(p, "顯示座標與走法", 150, x0 + 226, -64, SB.reveal)
    mapButton = button(p, "看地圖", 100, x0 + 226 + (SB.RPG_ON and 158 or 0), -64, function() SB.showMap() end)
    mapButton.tip = "在世界地圖上標出這一步的位置"
    SB.mapButton = mapButton
    resetButton = button(p, "重設進度", 100, 880, -64, SB.reset)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -100)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -40, 20)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(930, 400)
    scroll:SetScrollChild(scrollChild)
    bodyText = scrollChild:CreateFontString(nil, "ARTWORK", ns.LABEL_FONT)
    bodyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -4)
    bodyText:SetWidth(920)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")
    if bodyText.SetSpacing then bodyText:SetSpacing(4) end
end

ns.Framework.register({
    id = SB.ID,
    title = "睡袋路線",
    order = 20,
    -- Only the Horde route exists so far; Alliance players do not see the entry
    -- (GF-008-D: SB.route() finds no route with faction = "Alliance").
    available = function() return SB.route() ~= nil end,
    create = build,
    show = SB.refresh,
})
