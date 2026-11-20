-- Sleeping bag route helper (GF-008-A), a toolkit module.
--   RPG mode:    landmark and direction; coordinates and the full route only
--                after the player presses "顯示座標與走法".
--   Normal mode: every step with coordinates, travel and alternatives.
-- Both modes share one progress per character (settings.modules.sleepingbag
-- .characters[GUID]). Progress is confirmed by hand; no quest IDs are used yet.

local _, ns = ...
local str = ns.str

local SB = {}
ns.SleepingBag = SB
SB.ID = "sleepingbag"
SB.MODES = { rpg = "RPG 模式", normal = "一般模式" }

local panel, modeButton, progressLine, bodyText, revealButton, doneButton, backButton, resetButton
local scroll, scrollChild

---------------------------------------------------------------------------
-- State (pure; covered by offline tests)
---------------------------------------------------------------------------

function SB.route()
    local faction = ns.Data.player().faction
    return ns.SleepingBagRoutes[faction ~= "" and faction or "Horde"]
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

local function coords(step)
    if step.x and step.y then return string.format("%s（%d, %d）", step.zone, step.x, step.y) end
    return step.zone .. "（座標待實地確認）"
end

local VERIFY = "｜待實地驗證"

-- Lines describing one step for a mode. RPG hides coordinates and travel
-- details until revealed.
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
    add("位置：", coords(step))
    add("地標：", step.landmark)
    if step.object then add("目標：", step.object .. (step.objectEN and ("（" .. step.objectEN .. "）") or "")) end
    add("要做的事：", step.action)
    add("前往方式：", step.travel)
    add("轉乘點：", step.transfer)
    add("守衛與危險：", step.guards)
    add("沒有飛行點時：", step.noFlightPath)
    lines[#lines + 1] = "狀態：待實地驗證"
    return lines
end

-- Whole page text for the current state.
function SB.pageText()
    local route = SB.route()
    if not route then return "目前沒有你陣營的路線資料。" end
    local s = SB.state()
    local out = {}
    if SB.isFinished() then
        out[#out + 1] = "已完成全部 " .. #route.steps .. " 步。獎勵：" .. route.reward
        out[#out + 1] = "按「重設進度」可以從頭再走一次。"
        return table.concat(out, "\n")
    end
    local step = route.steps[s.step]
    out[#out + 1] = string.format("【第 %d 步】%s", s.step, step.zone)
    for _, line in ipairs(SB.stepLines(step, s.mode, s.revealed[step.id])) do out[#out + 1] = line end
    if s.mode == "normal" then
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
    modeButton:SetText("目前：" .. SB.MODES[s.mode] .. "（點一下切換）")
    progressLine:SetText(string.format("%s｜進度 %d / %d｜%s",
        route and route.title or "", math.min(s.step - 1, total), total,
        "每一步都待實地驗證，進度請自行確認"))
    local text = SB.pageText()
    bodyText:SetText(text)
    scrollChild:SetHeight(math.max(400, select(2, text:gsub("\n", "")) * 18 + 60))
    local step = SB.currentStep()
    revealButton:SetShown(s.mode == "rpg" and step ~= nil and not s.revealed[step.id])
    doneButton:SetEnabled(step ~= nil)
    backButton:SetEnabled(s.step > 1)
end

local function button(parent, text, w, x, y, fn)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 26)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function build(p)
    panel = p
    progressLine = p:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    progressLine:SetPoint("TOPLEFT", p, "TOPLEFT", 22, -38)
    progressLine:SetWidth(950)
    progressLine:SetJustifyH("LEFT")
    modeButton = button(p, "", 260, 20, -64, SB.toggleMode)
    doneButton = button(p, "完成這一步", 120, 290, -64, SB.complete)
    backButton = button(p, "上一步", 90, 418, -64, SB.back)
    revealButton = button(p, "顯示座標與走法", 150, 516, -64, SB.reveal)
    resetButton = button(p, "重設進度", 100, 880, -64, SB.reset)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -100)
    scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -40, 20)
    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(930, 400)
    scroll:SetScrollChild(scrollChild)
    bodyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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
    -- Only the Horde route exists so far; Alliance players do not see the entry.
    available = function() return SB.route() ~= nil and ns.Data.player().faction ~= "Alliance" end,
    create = build,
    show = SB.refresh,
})
