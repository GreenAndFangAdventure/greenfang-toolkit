-- Sleeping bag route helper (GF-008-A), a toolkit module.
--   RPG mode:    landmark and direction; coordinates and the full route only
--                after the player presses "顯示座標與走法".
--   Normal mode: the current step with its place, what to do, one reminder (GF-008-E).
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
-- GF-008-E (owner 2026-11-28: 步驟太多太囉嗦、改用上一步／下一步): five steps,
-- each with a place; the page shows only the current step, with 上一步 /
-- 下一步 (完成 on the last) and 第 N／M 步. The step is saved per character
-- (settings.modules.sleepingbag.characters[GUID].step, layout = 2; a step
-- saved by the nine-step layout is moved over once). There is no automatic
-- step from quest progress (no quest IDs yet), so only the buttons move it.

local _, ns = ...
local str = ns.str

local SB = {}
ns.SleepingBag = SB
SB.ID = "sleepingbag"
SB.MODES = { rpg = "RPG 模式", normal = "一般模式" }
SB.RPG_ON = false -- GF-008-B: true shows the RPG / normal switch again

local panel, modeButton, progressLine, bodyText, revealButton, nextButton, backButton, resetButton, mapButton, stepLabel
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
    -- GF-008-E: a step saved by the nine-step layout, moved over once.
    if route and route.layout and s.layout ~= route.layout then
        if s.layout == nil and route.fromLayout1 then s.step = route.fromLayout1[s.step] or s.step end
        s.layout = route.layout
    end
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

-- 下一步 (完成 on the last step): the current step is done.
function SB.complete()
    local s, step = SB.state(), SB.currentStep()
    if not step then return false end
    s.completedAt[step.id] = ns.now()
    s.step = s.step + 1
    SB.refresh()
    return true
end

SB.nextStep = SB.complete -- GF-008-E: the button's name

-- GF-008-E: what the step row shows: 第 N／M 步, 上一步 lit, 下一步 or 完成 lit.
function SB.nav()
    local route, s = SB.route(), SB.state()
    local total = route and #route.steps or 0
    local done = s.step > total
    return {
        index = math.min(s.step, total), total = total, finished = done,
        label = done and ("全部完成（共 " .. total .. " 步）") or string.format("第 %d／%d 步", s.step, total),
        prev = s.step > 1,
        next = not done,
        nextText = (done or s.step == total) and "完成" or "下一步",
    }
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
    -- GF-008-E: where, what, one reminder; nothing else.
    add("位置：", coords(step, true))
    add("要做的事：", step.action)
    add("提醒：", step.tip)
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
    out[#out + 1] = string.format("【第 %d／%d 步】%s", s.step, #route.steps, step.zone)
    for _, line in ipairs(SB.stepLines(step, mode, s.revealed[step.id])) do out[#out + 1] = line end
    if mode == "normal" then
        -- GF-008-D: what the map colours mean (the text says 大約 too).
        -- GF-008-E: only the current step; no list of every step.
        if ns.SleepingBagMap and ns.SleepingBagMap.LEGEND then out[#out + 1] = ns.SleepingBagMap.LEGEND end
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
    local nav = SB.nav()
    progressLine:SetText(string.format("%s｜共 %d 步｜%s", route and route.title or "", total,
        "每一步都待實地驗證，走到哪一步請自己按"))
    local text = SB.pageText()
    bodyText:SetText(text)
    scrollChild:SetHeight(math.max(400, select(2, text:gsub("\n", "")) * 18 + 60))
    local step = SB.currentStep()
    if mode == "rpg" and step ~= nil and not s.revealed[step.id] then revealButton:Show() else revealButton:Hide() end
    -- GF-008-E: 上一步 dim on the first step; 下一步 says 完成 on the last, dim when finished.
    stepLabel:SetText(nav.label)
    nextButton:SetText(nav.nextText)
    nextButton:SetEnabled(nav.next)
    backButton:SetEnabled(nav.prev)
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
    -- GF-008-E: 上一步｜第 N／M 步｜下一步, then 看地圖.
    backButton = button(p, "上一步", 90, x0, -64, SB.back)
    stepLabel = p:CreateFontString(nil, "ARTWORK", ns.FIELD_FONT)
    stepLabel:SetPoint("TOPLEFT", p, "TOPLEFT", x0 + 98, -70)
    stepLabel:SetWidth(170)
    stepLabel:SetJustifyH("CENTER")
    SB.stepLabel = stepLabel
    nextButton = button(p, "下一步", 90, x0 + 276, -64, SB.complete)
    SB.backButton, SB.nextButton = backButton, nextButton
    revealButton = button(p, "顯示座標與走法", 150, x0 + 374, -64, SB.reveal)
    mapButton = button(p, "看地圖", 100, x0 + 374 + (SB.RPG_ON and 158 or 0), -64, function() SB.showMap() end)
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
