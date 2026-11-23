-- AdventureUI (GF-002-B, spec §11, §8): the 「冒險」 page, the new-ticket
-- and worker-ticket popups, and the adventure number on the minimap button.
-- R-11.1: icons first, at most one or two buttons a row, no explanation
-- lines or time stamps; technical details only in 同步與診斷.
-- R-8.3: adventure rows start with the destination icon (orders start with
-- the item), and their state is the role-gap icons (orders use ⏳🔨📦✅❌).

local _, ns = ...
local str = ns.str

local UI = {}
ns.AdventureUI = UI

local function A() return ns.Adventure end
local function S() return ns.Share end
local Icons = ns.Icons

UI.ICON = {
    dungeon = "Interface\\Icons\\INV_Misc_Key_03",
    quest = "Interface\\Icons\\INV_Misc_Note_01",
    now = "Interface\\Icons\\Spell_Nature_TimeStop",
    t = "Interface\\Icons\\Ability_Defend",
    h = "Interface\\Icons\\Spell_Holy_Heal",
    d = "Interface\\Icons\\INV_Sword_04",
    any = "Interface\\Icons\\INV_Misc_GroupNeedMore",
    apply = "Interface\\Icons\\INV_Gauntlets_04",
    invite = "Interface\\Icons\\INV_Letter_15",
    yes = "Interface\\RaidFrame\\ReadyCheck-Ready",
    no = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    wait = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    form = "Interface\\Icons\\Ability_Warrior_BattleShout",
    reopen = "Interface\\Buttons\\UI-RefreshButton",
    attention = "Interface\\GossipFrame\\AvailableQuestIcon",
    offline = "Interface\\FriendsFrame\\StatusIcon-Offline",
    online = "Interface\\FriendsFrame\\StatusIcon-Online",
    consent = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
    direct = "Interface\\Icons\\Spell_Holy_SealOfMight",
    worker = "Interface\\Icons\\INV_Misc_Bag_10",
    tag_quest = "Interface\\Icons\\INV_Misc_Note_02", tag_farm = "Interface\\Icons\\Spell_Nature_Reincarnation",
    tag_slow = "Interface\\Icons\\Ability_Hunter_Pet_Turtle", tag_fast = "Interface\\Icons\\Ability_Rogue_Sprint",
    tag_voice = "Interface\\Icons\\Spell_Holy_Silence",
}
UI.ROLE_NAME = { t = "坦", h = "補", d = "輸出", any = "隊員" }
UI.TAG_KEYS = { "quest", "farm", "slow", "fast", "voice" }

-- GF-002-C: role, person, time and quest marks use the game's own art (GameIcons, with fallbacks).
UI.GAME = { t = "role_t", h = "role_h", d = "role_d", any = "person", now = "now", today = "today", future = "future",
    quest = "quest", dungeon = "key", worker = "worker", yes = "yes", no = "no", adventure = "adventure" }
local function tex(key, size)
    local g = UI.GAME[key]
    if g then return ns.GameIcons.markup(g, size) end
    return "|T" .. (UI.ICON[key] or key) .. ":" .. tostring(size or 14) .. "|t"
end
UI.tex = tex
local function setIcon(t, key)
    local g = UI.GAME[key]
    if g then return ns.GameIcons.set(t, g) end
    if Icons.set(t, UI.ICON[key] or key) then t:Show(); return true end
    t:Hide(); return false
end
UI.setIcon = setIcon

---------------------------------------------------------------------------
-- Pure helpers
---------------------------------------------------------------------------

-- Local "HH:MM" of a server time (R-4.2: stored as server time, shown local).
function UI.clock(t)
    if not t then return "" end
    local skew = (ns.num((ns.call(GetServerTime))) or ns.now()) - ns.now()
    return date("%H:%M", t - skew)
end
function UI.day(t)
    local skew = (ns.num((ns.call(GetServerTime))) or ns.now()) - ns.now()
    return date("%m/%d", t - skew)
end

-- "⚡" / "20:00～22:00" / "11/25 19:00～21:00"
function UI.timeText(v)
    if v.timeMode == "n" then return tex("now") end
    local s = UI.clock(v.start) .. "～" .. UI.clock(v.finish)
    if v.timeMode == "f" then return tex("future") .. " " .. UI.day(v.start) .. " " .. s end
    return tex("today") .. " " .. s
end

-- GF-002-C item 2: one entry per seat, in role order: { role, filled }.
-- Dungeon tickets: tank, healer, dps; quest tickets: one person per seat.
function UI.slotList(v)
    local out = {}
    if v.capacity.any then
        local filled = v.capacity.any - (v.seats.any or 0)
        for i = 1, v.capacity.any do out[#out + 1] = { role = "any", filled = i <= filled } end
        return out
    end
    for _, r in ipairs(A().ROLES) do
        local cap = v.capacity[r] or 0
        local filled = cap - (v.seats[r] or 0)
        for i = 1, cap do out[#out + 1] = { role = r, filled = i <= filled } end
    end
    return out
end
UI.MAX_SLOTS = 12

-- Role gaps as icons: a filled seat bright, an empty one grey (R-8.3).
function UI.roleText(v)
    local parts = {}
    if v.capacity.any then
        local filled = v.capacity.any - (v.seats.any or 0)
        parts[#parts + 1] = tex("any") .. filled .. "/" .. v.capacity.any
    else
        for _, r in ipairs(A().ROLES) do
            local cap = v.capacity[r] or 0
            if cap > 0 then parts[#parts + 1] = tex(r) .. (cap - (v.seats[r] or 0)) .. "/" .. cap end
        end
    end
    return table.concat(parts, " ")
end

function UI.tagText(tags)
    local out = {}
    for _, k in ipairs(UI.TAG_KEYS) do
        if math.floor((tags or 0) / A().TAGS[k]) % 2 == 1 then out[#out + 1] = tex("tag_" .. k) end
    end
    return table.concat(out, "")
end

-- GF-002-C items 3, 4: the short name next to the dungeon art; a quest
-- ticket shows the scroll and the number of quests (names in the tooltip).
function UI.destText(v)
    if v.dungeon then return ns.AdventureData.short(v.dungeon) end
    return "x" .. #v.quests
end

function UI.setDest(t, v)
    if v.dungeon then return ns.GameIcons.set(t, ns.GameIcons.dungeonKey(v.dungeon)) end
    return ns.GameIcons.set(t, "quest")
end

-- Tooltip lines for a ticket: the full destination, quest names, the note.
function UI.ticketTooltip(v)
    local lines = {}
    if v.dungeon then
        local d = ns.AdventureData.byId[v.dungeon]
        lines[#lines + 1] = d and (d.name .. "  " .. d.min .. "-" .. d.max) or v.dungeon
    end
    local log = A().questLog() or {}
    for _, q in ipairs(v.quests) do
        local info = log[tonumber(q) or q]
        lines[#lines + 1] = tex("quest") .. " " .. ((info and info.title) or ("#" .. tostring(q)))
    end
    if v.note and v.note ~= "" then lines[#lines + 1] = v.note end
    return lines
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local ROW_HEIGHT = 28
local panel, scroll, content, summaryLine
local rowWidgets, shownRows = {}, {}

function UI.pageRows()
    local tickets, matched = A().rowsFor()
    local out = {}
    if #tickets > 0 then
        out[#out + 1] = { header = tex("adventure", 16) .. " 冒險單" }
        for _, r in ipairs(tickets) do out[#out + 1] = r end
    end
    if #matched > 0 then
        out[#out + 1] = { header = tex("worker", 16) .. " 職工單" }
        for _, r in ipairs(matched) do r.isWorker = true; out[#out + 1] = r end
    end
    return out
end

-- The buttons a viewer gets on a ticket (R-6.3 – R-7.3, R-4.7, R-4.9).
function UI.buttonsFor(v)
    local my = S().selfAuthor()
    local out = {}
    if v.leader == my then
        if A().local_().reopen[v.id] then return { "reopen", "dismiss" } end
        if v.closed then return out end
        if #v.pending > 0 then out[#out + 1] = "approve" end
        if v.state == "departed" then out[#out + 1] = "done" else out[#out + 1] = "form" end
        out[#out + 1] = "remove"
        return out
    end
    if v.closed then return out end
    for _, i in ipairs(v.invited) do if i.a == my then return { "accept", "refuse" } end end
    for _, list in ipairs({ v.members, v.waitlist, v.pending }) do
        for _, x in ipairs(list) do if x.a == my then return { "withdraw" } end end
    end
    if v.state ~= "departed" then out[#out + 1] = "apply" end
    return out
end

UI.BUTTON = {
    apply = { icon = "apply", tip = "申請" }, withdraw = { icon = "no", tip = "撤回" },
    accept = { icon = "yes", tip = "接受" }, refuse = { icon = "no", tip = "拒絕" },
    approve = { icon = "yes", tip = "同意" }, form = { icon = "form", tip = "組隊" },
    done = { icon = "yes", tip = "完成" }, remove = { icon = "no", tip = "移除" },
    reopen = { icon = "reopen", tip = "重開" }, dismiss = { icon = "no", tip = "不要" },
    invite = { icon = "invite", tip = "邀請" },
}

-- Press a ticket button. Returns a result (tests).
function UI.press(v, button, owner)
    local Adv = A()
    local r
    if button == "apply" then
        -- R-6.3: show the ticket's time first; ✓ confirms.
        if owner then
            return ns.showMenu(owner, { { text = UI.timeText(v) .. "  " .. tex("yes"), fn = function()
                Adv.worker(v.id, "apply"); UI.refresh()
            end } }) and "confirm" or "none"
        end
        r = Adv.worker(v.id, "apply")
    elseif button == "withdraw" then r = Adv.worker(v.id, "withdraw")
    elseif button == "accept" then r = Adv.worker(v.id, "accept")
    elseif button == "refuse" then r = Adv.worker(v.id, "refuse")
    elseif button == "approve" then r = Adv.leader(v.id, "approve", v.pending[1] and v.pending[1].a)
    elseif button == "form" then r = Adv.form(v.id)
    elseif button == "done" then r = Adv.leader(v.id, "done")
    elseif button == "remove" then r = Adv.leader(v.id, "cancel", "manual")
    elseif button == "reopen" then r = Adv.reopen(v.id)
    elseif button == "dismiss" then Adv.dismissReopen(v.id); r = true
    end
    UI.refresh()
    return r
end

-- Leader's menu on their own ticket: kick, approve, the admission mode (R-4.5, R-6.6).
function UI.leaderMenu(v)
    local items = {}
    local Adv = A()
    for _, m in ipairs(v.pending) do
        local mm = Adv.member(m.a)
        items[#items + 1] = { text = tex("yes") .. " " .. (mm and ns.shortName(mm.name) or "?"), fn = function() Adv.leader(v.id, "approve", m.a); UI.refresh() end }
    end
    for _, list in ipairs({ v.members, v.waitlist }) do
        for _, m in ipairs(list) do
            local mm = Adv.member(m.a)
            items[#items + 1] = { text = tex("no") .. " " .. (mm and ns.shortName(mm.name) or "?"), fn = function() Adv.leader(v.id, "kick", m.a); UI.refresh() end }
        end
    end
    items[#items + 1] = { text = tex(v.mode == "c" and "direct" or "consent") .. " " .. (v.mode == "c" and "直接錄取" or "團長同意"),
        fn = function() Adv.leader(v.id, "mode", v.mode == "c" and "a" or "c"); UI.refresh() end }
    return items
end

local function iconButton(parent, size, key, tip, onClick, label)
    local b = ns.OrdersUI.iconButton(parent, size, UI.ICON[key] or key, tip, onClick, label)
    return b
end

local function newRow(i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(930, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints()
    row.att = row:CreateTexture(nil, "ARTWORK"); row.att:SetSize(16, 16); row.att:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.dest = row:CreateTexture(nil, "ARTWORK"); row.dest:SetSize(22, 22); row.dest:SetPoint("LEFT", row, "LEFT", 22, 0)
    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.name:SetPoint("LEFT", row, "LEFT", 50, 0); row.name:SetWidth(190); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
    row.time = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.time:SetPoint("LEFT", row, "LEFT", 244, 0); row.time:SetWidth(150); row.time:SetJustifyH("LEFT")
    row.roles = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.roles:SetPoint("LEFT", row, "LEFT", 398, 0); row.roles:SetWidth(170); row.roles:SetJustifyH("LEFT")
    -- GF-002-C item 2: one icon per seat, bright when taken, grey when open.
    row.slots = {}
    for k = 1, UI.MAX_SLOTS do
        local s = row:CreateTexture(nil, "ARTWORK")
        s:SetSize(16, 16)
        s:SetPoint("LEFT", row, "LEFT", 398 + (k - 1) * 17, 0)
        s:Hide()
        row.slots[k] = s
    end
    row.tags = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.tags:SetPoint("LEFT", row, "LEFT", 572, 0); row.tags:SetWidth(90); row.tags:SetJustifyH("LEFT")
    row.cls = row:CreateTexture(nil, "ARTWORK"); row.cls:SetSize(16, 16); row.cls:SetPoint("LEFT", row, "LEFT", 640, 0)
    row.off = row:CreateTexture(nil, "OVERLAY"); row.off:SetSize(10, 10); row.off:SetPoint("BOTTOMRIGHT", row.cls, "BOTTOMRIGHT", 3, -3)
    row.who = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.who:SetPoint("LEFT", row, "LEFT", 660, 0); row.who:SetWidth(96); row.who:SetJustifyH("LEFT"); row.who:SetWordWrap(false)
    row.buttons = {}
    for k = 1, 3 do
        local b = iconButton(row, 22, "yes", nil)
        b:SetPoint("LEFT", row, "LEFT", 760 + (k - 1) * 58, 0) -- GF-002-D: room for the names
        row.buttons[k] = b
    end
    row.head = row:CreateFontString(nil, "ARTWORK", "GameFontNormal"); row.head:SetPoint("LEFT", row, "LEFT", 6, 0)
    row:EnableMouse(true)
    if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    row:SetScript("OnMouseUp", function(self, mouse)
        local v = self.view
        if v and v.leader == S().selfAuthor() and not v.closed and mouse == "RightButton" then
            ns.showMenu(self, UI.leaderMenu(v))
        end
    end)
    row:SetScript("OnEnter", function(self)
        local v = self.view
        if not v then return end
        local lines = UI.ticketTooltip(v)
        if #lines == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rowWidgets[i] = row
    return row
end

local function fillWho(row, a)
    local m = A().member(a)
    if m and Icons.setClassIcon(row.cls, m.classToken) then row.cls:Show() else row.cls:Hide() end
    row.who:SetText(m and ns.shortName(m.name) or "?")
    local c = Icons.classColor(m and m.classToken)
    row.who:SetTextColor(c[1], c[2], c[3])
end

local function fillRow(row, data, i)
    row.bg:SetColorTexture(0.2, 0.15, 0.15, i % 2 == 0 and 0.35 or 0.09)
    local parts = { row.att, row.dest, row.name, row.time, row.roles, row.tags, row.cls, row.who }
    row.view = nil
    for _, s in ipairs(row.slots) do s:Hide() end
    if data.header then
        for _, w in ipairs(parts) do w:Hide() end
        row.off:Hide()
        for _, b in ipairs(row.buttons) do b:Hide() end
        row.head:SetText(data.header); row.head:Show()
        return
    end
    row.head:Hide()
    for _, w in ipairs(parts) do w:Show() end
    if data.attention then setIcon(row.att, "attention") else row.att:Hide() end
    if data.isWorker then
        -- A worker matching one of my tickets: invite (R-6.4).
        local w, v = data.w, data.ticket
        UI.setDest(row.dest, v)
        row.name:SetText(UI.destText(v))
        local slotText = {}
        for _, sl in ipairs(w.slots) do slotText[#slotText + 1] = sl.now and tex("now") or (UI.clock(sl.s) .. "～" .. UI.clock(sl.e)) end
        row.time:SetText(table.concat(slotText, " "))
        row.roles:SetText(tex(w.main or "d", 16) .. (w.alt and (" " .. tex(w.alt, 12)) or ""))
        row.tags:SetText("")
        fillWho(row, data.worker)
        if w.online then setIcon(row.off, "online") else setIcon(row.off, "offline") end
        for k, b in ipairs(row.buttons) do
            if k == 1 then
                Icons.set(b.tex, UI.ICON.invite); b.tip = "邀請"; b.action = "invite"
                ns.OrdersUI.setLabel(b, "邀請")
                b:SetScript("OnClick", function() A().leader(v.id, "invite", data.worker); UI.refresh() end)
                b:Show()
            else b:Hide(); b.action = nil end
        end
        return
    end
    local v = data.view
    row.view = v
    UI.setDest(row.dest, v)
    row.name:SetText(UI.destText(v))
    row.name:SetTextColor(v.closed and 0.5 or 1, v.closed and 0.5 or 1, v.closed and 0.5 or 1)
    row.time:SetText(UI.timeText(v))
    if v.closed then
        row.roles:SetText(tex(v.state == "done" and "yes" or "no"))
    else
        row.roles:SetText("")
        for k, sl in ipairs(UI.slotList(v)) do
            local s = row.slots[k]
            if not s then break end
            ns.GameIcons.set(s, UI.GAME[sl.role])
            if s.SetDesaturated then s:SetDesaturated(not sl.filled) end
            s:SetAlpha(sl.filled and 1 or 0.45)
            s.filled = sl.filled
        end
    end
    row.tags:SetText(UI.tagText(v.tags) .. (v.mode == "c" and tex("consent") or ""))
    fillWho(row, v.leader)
    -- R-4.7: the leader is offline (委託者離線中).
    if v.leaderOffline then setIcon(row.off, "offline") else row.off:Hide() end
    local list = UI.buttonsFor(v)
    for k, b in ipairs(row.buttons) do
        local name = list[k]
        if name then
            local spec = UI.BUTTON[name]
            Icons.set(b.tex, UI.ICON[spec.icon]); b.tip = spec.tip; b.action = name
            ns.OrdersUI.setLabel(b, spec.tip) -- GF-002-D: the name next to the icon
            b:SetScript("OnClick", function(self) UI.press(v, name, self) end)
            b:Show()
        else b:Hide(); b.action = nil end
    end
end

function UI.layoutRows()
    if not scroll then return end
    local offset = ns.num((scroll:GetVerticalScroll())) or 0
    local h = ns.num((scroll:GetHeight())) or 0
    if h <= 0 then h = 420 end
    local count = math.ceil(h / ROW_HEIGHT) + 1
    local first = math.max(1, math.floor(offset / ROW_HEIGHT) + 1)
    for k = 1, math.max(count, #rowWidgets) do
        local i = first + k - 1
        local data = k <= count and shownRows[i] or nil
        local row = rowWidgets[k] or (data and newRow(k)) or nil
        if row then
            if data then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
                fillRow(row, data, i)
                row:Show()
            else row:Hide(); row.view = nil end
        end
    end
end
function UI.rowFrames() return rowWidgets end
function UI.shownRows() return shownRows end

-- R-11.3: "🏰 SM 3 人想去 缺🩹".
-- GF-002-C item 9: dungeon art, the number of people, the missing role icons (no words).
function UI.summaryText()
    local s = A().summary()
    if not s then return "" end
    local lack = {}
    for _, r in ipairs(A().ROLES) do if s.lack[r] then lack[#lack + 1] = tex(r, 16) end end
    return ns.GameIcons.markup(ns.GameIcons.dungeonKey(s.dungeon), 18) .. " " .. ns.AdventureData.short(s.dungeon)
        .. "  " .. tex("any", 14) .. s.count .. (#lack > 0 and ("   " .. table.concat(lack, " ")) or "")
end

function UI.refresh()
    UI.updateBadge()
    if not panel then return end
    shownRows = UI.pageRows()
    content:SetHeight(math.max(1, #shownRows * ROW_HEIGHT))
    UI.layoutRows()
    summaryLine:SetText(UI.summaryText())
    UI.emptyLine:SetText(#shownRows == 0 and "沒有冒險單" or "") -- GF-002-D
    if #A().pendingInvites() > 0 then UI.nextInvite:Show() else UI.nextInvite:Hide() end
end

local function build(p)
    UI.newButton = ns.createFrame("Button", nil, p, "UIPanelButtonTemplate")
    UI.newButton:SetSize(124, 24); UI.newButton:SetPoint("TOPLEFT", p, "TOPLEFT", 24, -40)
    UI.newButton:SetText(tex("adventure", 16) .. " ＋冒險單") -- GF-002-D: icon + name
    UI.newButton.tooltipText = "冒險單"
    UI.newButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("冒險單"); GameTooltip:Show() end)
    UI.newButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.newButton:SetScript("OnClick", function() UI.openTicket() end)
    UI.workerButton = ns.createFrame("Button", nil, p, "UIPanelButtonTemplate")
    UI.workerButton:SetSize(124, 24); UI.workerButton:SetPoint("LEFT", UI.newButton, "RIGHT", 10, 0)
    UI.workerButton:SetText(tex("worker", 16) .. " ＋職工單")
    UI.workerButton:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("職工單"); GameTooltip:Show() end)
    UI.workerButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.workerButton:SetScript("OnClick", function() UI.openWorker() end)
    summaryLine = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    summaryLine:SetPoint("LEFT", UI.workerButton, "RIGHT", 24, 0)
    scroll = ns.createFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -76)
    scroll:SetPoint("BOTTOMRIGHT", -40, 40)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(930, 1)
    scroll:SetScrollChild(content)
    scroll:HookScript("OnVerticalScroll", function() UI.layoutRows() end)
    UI.nextInvite = iconButton(p, 24, "form", "邀請下一位", function() A().inviteNext(); UI.refresh() end, "邀請下一位")
    UI.nextInvite:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -250, 10)
    UI.nextInvite:Hide() -- only while names wait for a click (R-7.2 fallback)
    UI.emptyLine = p:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    UI.emptyLine:SetPoint("TOP", p, "TOP", 0, -180)
    ns.Diag.smallButton(p, "BOTTOMRIGHT", -24, 10)
    panel = p
end

ns.Framework.register({
    id = "adventure",
    title = "冒險",
    order = 14,
    available = function() return ns.guildState() == "target" end,
    create = build,
    show = function() A().markSeen(); UI.refresh() end,
})

---------------------------------------------------------------------------
-- New adventure ticket (R-4.1 – R-4.5, R-11.2: destination -> time -> 開單)
---------------------------------------------------------------------------

UI.TICKET_NAME = "GreenFangToolkit_AdventurePopup"
local popup, draft

function UI.newDraft()
    local _, token = ns.call(UnitClass, "player")
    local main = A().defaultRoles(token)
    return { timeMode = "n", roles = { t = 1, h = 1, d = 3 }, size = 5, tags = 0, note = "", mode = "a",
        leaderRole = main, quests = {}, start = nil, finish = nil }
end

function UI.submitTicket(d)
    d = d or draft
    if not d then return nil end
    local id, why = A().open(d)
    if id and popup then popup:Hide() end
    if not id and popup then popup.result:SetText(tex("no")) end
    UI.refresh()
    return id, why
end

-- Times every 15 minutes from now (R-4.2).
-- GF-002-D: aligned to :00 :15 :30 :45 of the clock the player sees (the
-- local clock may be off the server by a minute; 0.12.1 showed 01:14).
function UI.skew() return (ns.num((ns.call(GetServerTime))) or ns.now()) - ns.now() end
function UI.quarterTimes(from, count, step)
    step = step or 900
    local skew = UI.skew()
    local out = {}
    local t = math.ceil((from - skew) / step) * step + skew
    for i = 0, count - 1 do out[#out + 1] = t + i * step end
    return out
end
UI.DURATIONS = { 1, 2, 3 }

UI.TAG_NAME = { quest = "解任務", farm = "連刷", slow = "慢慢打", fast = "速刷", voice = "語音" }
UI.TIME_NAME = { n = "現在", t = "今天", f = "之後" }

local function drawTicket()
    if not (popup and draft) then return end
    popup.dest:SetText(draft.dungeon and (ns.GameIcons.markup(ns.GameIcons.dungeonKey(draft.dungeon), 18) .. " " .. ns.AdventureData.short(draft.dungeon))
        or (#draft.quests > 0 and (tex("quest") .. " 任務 " .. #draft.quests)) or "選擇目的地")
    for _, m in ipairs({ "n", "t", "f" }) do
        popup.timeButtons[m]:SetAlpha(draft.timeMode == m and 1 or 0.4)
        if popup.timeButtons[m].label then popup.timeButtons[m].label:SetAlpha(draft.timeMode == m and 1 or 0.5) end
    end
    popup.timeText:SetText(draft.timeMode == "n" and "" or ("～" .. UI.clock(draft.finish)))
    local timed = draft.timeMode ~= "n"
    for _, w in ipairs({ popup.startField, popup.startButton, popup.durField, popup.durButton }) do if timed then w:Show() else w:Hide() end end
    for _, w in ipairs({ popup.dayField, popup.dayButton }) do if draft.timeMode == "f" then w:Show() else w:Hide() end end
    if timed then
        popup.startButton:SetText(UI.clock(draft.start))
        popup.durButton:SetText((draft.dur or 2) .. " 小時")
        popup.dayButton:SetText(draft.start and UI.day(draft.start) or "")
    end
    local parts = {}
    if draft.dungeon then
        for _, r in ipairs(A().ROLES) do parts[#parts + 1] = tex(r) .. draft.roles[r] end
    else parts[#parts + 1] = tex("any") .. draft.size end
    popup.roleText:SetText(table.concat(parts, " "))
    popup.direct:SetAlpha(draft.mode == "c" and 0.4 or 1); popup.direct.label:SetAlpha(draft.mode == "c" and 0.5 or 1)
    popup.consent:SetAlpha(draft.mode == "c" and 1 or 0.4); popup.consent.label:SetAlpha(draft.mode == "c" and 1 or 0.5)
    for k, b in pairs(popup.tagButtons) do
        local on = math.floor(draft.tags / A().TAGS[k]) % 2 == 1
        b:SetAlpha(on and 1 or 0.35); b.label:SetAlpha(on and 1 or 0.5)
    end
end
UI.drawTicket = drawTicket

-- GF-002-D layout: a field name in front of every row; every choice has its name.
UI.TICKET_FIELDS = { "目的地", "時間", "開始", "時長", "日期", "人數", "錄取", "標籤", "備註" }
function UI.openTicket()
    draft = UI.newDraft()
    if not popup then
        local f = ns.popupWindow(UI.TICKET_NAME, 540, 370)
        f:SetPoint("CENTER", 0, 60)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if UISpecialFrames then table.insert(UISpecialFrames, UI.TICKET_NAME) end
        local X = 84
        local field = ns.OrdersUI.fieldLabel
        field(f, "目的地", 18, -40)
        f.dest = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.dest:SetSize(220, 24)
        f.dest:SetPoint("TOPLEFT", f, "TOPLEFT", X, -34)
        f.dest:SetScript("OnClick", function(self) UI.pickDestination(self) end)
        field(f, "時間", 18, -78)
        f.timeButtons = {}
        for i, m in ipairs({ "n", "t", "f" }) do
            local b = iconButton(f, 24, "now", UI.TIME_NAME[m], function(self) UI.pickTime(self, m) end, UI.TIME_NAME[m])
            ns.GameIcons.set(b.tex, m == "n" and "now" or m == "t" and "today" or "future")
            b:SetPoint("TOPLEFT", f, "TOPLEFT", X + (i - 1) * 72, -72)
            f.timeButtons[m] = b
        end
        f.timeText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); f.timeText:SetPoint("TOPLEFT", f, "TOPLEFT", X + 222, -78)
        -- 開始 / 時長 / 日期 (only for 今天 and 之後).
        f.startField = field(f, "開始", 18, -116)
        f.startButton = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.startButton:SetSize(80, 22)
        f.startButton:SetPoint("TOPLEFT", f, "TOPLEFT", X, -110)
        f.startButton:SetScript("OnClick", function(self) UI.pickStart(self) end)
        f.durField = field(f, "時長", X + 96, -116)
        f.durButton = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.durButton:SetSize(80, 22)
        f.durButton:SetPoint("TOPLEFT", f, "TOPLEFT", X + 136, -110)
        f.durButton:SetScript("OnClick", function(self) UI.pickDuration(self) end)
        f.dayField = field(f, "日期", X + 232, -116)
        f.dayButton = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.dayButton:SetSize(80, 22)
        f.dayButton:SetPoint("TOPLEFT", f, "TOPLEFT", X + 272, -110)
        f.dayButton:SetScript("OnClick", function(self) UI.pickDay(self) end)
        field(f, "人數", 18, -154)
        f.roleText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); f.roleText:SetPoint("TOPLEFT", f, "TOPLEFT", X, -154)
        f.roleButton = iconButton(f, 22, "any", "人數", function(self) UI.pickRoles(self) end, "調整")
        f.roleButton:SetPoint("TOPLEFT", f, "TOPLEFT", X + 222, -148)
        field(f, "錄取", 18, -192)
        f.direct = iconButton(f, 24, "direct", "直接錄取", function() draft.mode = "a"; drawTicket() end, "直接錄取")
        f.direct:SetPoint("TOPLEFT", f, "TOPLEFT", X, -186)
        f.consent = iconButton(f, 24, "consent", "團長同意", function() draft.mode = "c"; drawTicket() end, "團長同意")
        f.consent:SetPoint("TOPLEFT", f, "TOPLEFT", X + 110, -186)
        f.modeButton = f.direct
        field(f, "標籤", 18, -230)
        f.tagButtons = {}
        for i, k in ipairs(UI.TAG_KEYS) do
            local b = iconButton(f, 22, "tag_" .. k, UI.TAG_NAME[k], function()
                local bit = A().TAGS[k]
                if math.floor(draft.tags / bit) % 2 == 1 then draft.tags = draft.tags - bit else draft.tags = draft.tags + bit end
                drawTicket()
            end, UI.TAG_NAME[k])
            b:SetPoint("TOPLEFT", f, "TOPLEFT", X + (i - 1) * 88, -224)
            f.tagButtons[k] = b
        end
        field(f, "備註", 18, -268)
        f.note = ns.createFrame("EditBox", nil, f, "InputBoxTemplate"); f.note:SetSize(420, 22)
        f.note:SetPoint("TOPLEFT", f, "TOPLEFT", X + 4, -262)
        f.note:SetAutoFocus(false)
        if f.note.SetMaxLetters then f.note:SetMaxLetters(A().NOTE_MAX) end
        f.note:SetScript("OnTextChanged", function(self) if draft then draft.note = A().cleanNote(self:GetText()) end end)
        f.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        f.result = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight"); f.result:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18)
        f.go = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.go:SetSize(96, 24)
        f.go:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14); f.go:SetText(tex("yes", 16) .. " 開單")
        f.go:SetScript("OnClick", function() UI.submitTicket() end)
        f:Hide()
        popup = f
    end
    popup.note:SetText("")
    popup.result:SetText("")
    popup:Show()
    drawTicket()
    return draft
end
function UI.draft() return draft end

-- GF-002-C items 7, 8: every dungeon as its own art in a grid, coloured by
-- level (white fits, grey too low for me, red too high); click to pick or toggle.
UI.GRID_NAME = "GreenFangToolkit_DungeonGrid"
local grid
-- onQuest: when given, a quest scroll button closes the grid and opens the
-- quest menu instead (only one of the two is ever open; GF-002-C fix).
function UI.dungeonGrid(owner, onClick, isOn, onQuest)
    if ns.Framework.closeMenu then ns.Framework.closeMenu() end
    if not grid then
        grid = CreateFrame("Frame", UI.GRID_NAME, UIParent)
        grid:SetFrameStrata("TOOLTIP") -- GF-002-D: above the windows
        ns.makeOpaque(grid, 0)
        grid:EnableMouse(true)
        grid.buttons = {}
        if UISpecialFrames then table.insert(UISpecialFrames, UI.GRID_NAME) end
        for i, d in ipairs(ns.AdventureData.DUNGEONS) do
            local b = iconButton(grid, 30, "dungeon", d.name)
            b:SetPoint("TOPLEFT", grid, "TOPLEFT", 10 + ((i - 1) % 9) * 50, -6 - math.floor((i - 1) / 9) * 50)
            -- GF-002-D: the short name under the icon.
            b.label = grid:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            b.label:SetPoint("TOP", b, "BOTTOM", 0, -1)
            b.label:SetWidth(ns.labelWidth(d.short or d.name)); b.label:SetText(d.short or d.name)
            b.dungeon = d.id
            grid.buttons[i] = b
        end
        local n = #ns.AdventureData.DUNGEONS
        grid.quest = iconButton(grid, 30, "quest", "任務")
        grid.quest.label = grid:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        grid.quest.label:SetPoint("TOP", grid.quest, "BOTTOM", 0, -1)
        grid.quest.label:SetWidth(ns.labelWidth("任務")); grid.quest.label:SetText("任務")
        ns.GameIcons.set(grid.quest.tex, "quest")
        grid.quest:SetPoint("TOPLEFT", grid, "TOPLEFT", 10 + (n % 9) * 50, -6 - math.floor(n / 9) * 50)
        grid:SetSize(20 + 9 * 50, 12 + math.ceil((n + 1) / 9) * 50)
    end
    if onQuest then
        grid.quest:SetScript("OnClick", function(self) grid:Hide(); onQuest(self) end)
        grid.quest:Show()
    else
        grid.quest:Hide()
    end
    local level = A().myLevel()
    for _, b in ipairs(grid.buttons) do
        local d = ns.AdventureData.byId[b.dungeon]
        ns.GameIcons.set(b.tex, ns.GameIcons.dungeonKey(b.dungeon))
        local r, g, bl = ns.GameIcons.levelColor(b.dungeon, level)
        if b.tex.SetVertexColor then b.tex:SetVertexColor(r, g, bl) end
        b.levelColor = { r, g, bl }
        b.tip = d.name .. "  " .. d.min .. "-" .. d.max
        if isOn and isOn(b.dungeon) then ns.GameIcons.set(b.badge, "yes") else b.badge:Hide() end
        b:SetScript("OnClick", function(self)
            onClick(self.dungeon)
            if isOn and isOn(self.dungeon) then ns.GameIcons.set(self.badge, "yes") else self.badge:Hide() end
            if not isOn then grid:Hide() end
        end)
    end
    grid:ClearAllPoints()
    grid:SetPoint("TOPLEFT", owner or UIParent, "BOTTOMLEFT", 0, -2)
    grid:Show()
    return grid
end
function UI.grid() return grid end
ns.onExclusiveShow = function() if grid then grid:Hide() end end

-- Every menu on this page goes through here: the dungeon grid closes first.
function UI.menu(owner, items)
    if grid then grid:Hide() end
    return ns.showMenu(owner, items)
end

-- Dungeons (grid); its quest scroll opens my quest log instead (R-4.1).
function UI.pickDestination(owner)
    local hasQuests = A().questLog() ~= nil
    return UI.dungeonGrid(owner, function(id) draft.dungeon = id; draft.quests = {}; drawTicket() end, nil,
        hasQuests and function() UI.pickQuests(owner) end or nil)
end

function UI.pickQuests(owner)
    local items = {}
    local log = A().questLog()
    if log then
        local n = 0
        for id, q in pairs(log) do
            n = n + 1
            if n > 12 then break end
            items[#items + 1] = { text = tex("quest") .. " " .. str(q.title), fn = function()
                for i, x in ipairs(draft.quests) do if x == id then table.remove(draft.quests, i); drawTicket(); return end end
                if #draft.quests < A().MAX_QUESTS then draft.quests[#draft.quests + 1] = id end
                drawTicket()
            end }
        end
    end
    items[#items + 1] = { text = tex("no"), fn = function() draft.dungeon = nil; draft.quests = {}; drawTicket() end }
    return UI.menu(owner, items)
end

-- GF-002-D: 現在 / 今天 / 之後 only choose the mode; 開始, 時長 (and 日期 for
-- 之後) are their own rows, each with a small menu that starts with its name.
function UI.setFinish() if draft.start then draft.finish = draft.start + (draft.dur or 2) * 3600 end end

function UI.pickTime(owner, mode)
    draft.timeMode = mode
    draft.dur = draft.dur or 2
    if mode == "n" then draft.start, draft.finish = nil, nil
    elseif mode == "t" then
        draft.start = UI.quarterTimes(S().serverNow(), 1)[1]
    else
        draft.dayOff = draft.dayOff or 1
        draft.start = UI.dayStart(draft.dayOff) + 20 * 3600 -- 20:00 that day
    end
    UI.setFinish()
    drawTicket()
end

-- Server time of 00:00 (the player's clock) dayOff days from today.
function UI.dayStart(dayOff)
    local skew = UI.skew()
    local localNow = S().serverNow() - skew
    local d = date("*t", localNow)
    local midnight = localNow - (d.hour * 3600 + d.min * 60 + d.sec)
    return midnight + dayOff * 86400 + skew
end

local function titled(title, items)
    table.insert(items, 1, { text = "|cffffd100" .. title .. "|r", fn = function() end })
    return items
end
UI.titled = titled

function UI.pickStart(owner)
    local items = {}
    if draft.timeMode == "f" then
        local base = UI.dayStart(draft.dayOff or 1)
        for h = 8, 23 do
            local t = base + h * 3600
            items[#items + 1] = { text = UI.clock(t), fn = function() draft.start = t; UI.setFinish(); drawTicket() end }
        end
    else
        for _, t in ipairs(UI.quarterTimes(S().serverNow(), 16)) do
            items[#items + 1] = { text = UI.clock(t), fn = function() draft.start = t; UI.setFinish(); drawTicket() end }
        end
    end
    return UI.menu(owner, titled("開始", items))
end

function UI.pickDuration(owner)
    local items = {}
    for _, h in ipairs(UI.DURATIONS) do
        items[#items + 1] = { text = h .. " 小時", fn = function() draft.dur = h; UI.setFinish(); drawTicket() end }
    end
    return UI.menu(owner, titled("時長", items))
end

function UI.pickDay(owner)
    local items = {}
    for dayOff = 1, A().FUTURE_DAYS do
        items[#items + 1] = { text = UI.day(UI.dayStart(dayOff) + 43200), fn = function()
            local tod = draft.start and (draft.start - UI.dayStart(draft.dayOff or 1)) or 20 * 3600
            draft.dayOff = dayOff
            draft.start = UI.dayStart(dayOff) + tod
            UI.setFinish(); drawTicket()
        end }
    end
    return UI.menu(owner, titled("日期", items))
end

function UI.pickRoles(owner)
    local items = {}
    if draft.dungeon then
        for _, r in ipairs(A().ROLES) do
            items[#items + 1] = { text = tex(r) .. " +", fn = function() draft.roles[r] = math.min(5, draft.roles[r] + 1); drawTicket() end }
            items[#items + 1] = { text = tex(r) .. " -", fn = function() draft.roles[r] = math.max(0, draft.roles[r] - 1); drawTicket() end }
        end
    else
        for n = 2, 5 do items[#items + 1] = { text = tex("any") .. " " .. n, fn = function() draft.size = n; drawTicket() end } end
    end
    return UI.menu(owner, items)
end

---------------------------------------------------------------------------
-- Worker ticket (R-5.1 – R-5.4)
---------------------------------------------------------------------------

UI.WORKER_NAME = "GreenFangToolkit_WorkerPopup"
local wpopup, wdraft

function UI.newWorkerDraft()
    local mine = A().myWorker()
    if mine then return mine end
    local _, token = ns.call(UnitClass, "player")
    local main, alt = A().defaultRoles(token)
    return { dungeons = {}, quests = {}, allQuests = false, main = main, alt = alt, slots = { { now = true } } }
end

local function drawWorker()
    if not (wpopup and wdraft) then return end
    local marks = {}
    for _, d in ipairs(wdraft.dungeons) do marks[#marks + 1] = ns.GameIcons.markup(ns.GameIcons.dungeonKey(d), 18) end
    wpopup.dungeons:SetText(#marks > 0 and table.concat(marks, " ") or "選擇地城")
    for _, r in ipairs(A().ROLES) do
        local m, a = wpopup.mainRoles[r], wpopup.altRoles[r]
        m:SetAlpha(wdraft.main == r and 1 or 0.35); m.label:SetAlpha(wdraft.main == r and 1 or 0.5)
        a:SetAlpha(wdraft.alt == r and 1 or 0.35); a.label:SetAlpha(wdraft.alt == r and 1 or 0.5)
    end
    wpopup.quests:SetText(wdraft.allQuests and "全部任務" or (#wdraft.quests > 0 and (tex("quest") .. " 任務 " .. #wdraft.quests) or "選擇任務"))
    local slots = {}
    for _, sl in ipairs(wdraft.slots) do slots[#slots + 1] = sl.now and (tex("now") .. " 現在") or (UI.clock(sl.s) .. "～" .. UI.clock(sl.e)) end
    wpopup.slots:SetText(table.concat(slots, "  "))
end

UI.WORKER_FIELDS = { "地城", "任務", "職責", "副職責", "時段" }
function UI.openWorker()
    wdraft = UI.newWorkerDraft()
    if not wpopup then
        local f = ns.popupWindow(UI.WORKER_NAME, 500, 290)
        f:SetPoint("CENTER", 0, 60)
        f:EnableMouse(true)
        ns.exclusivePopup(f)
        if UISpecialFrames then table.insert(UISpecialFrames, UI.WORKER_NAME) end
        local X = 84
        local field = ns.OrdersUI.fieldLabel
        field(f, "地城", 18, -40)
        f.dungeons = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.dungeons:SetSize(380, 24)
        f.dungeons:SetPoint("TOPLEFT", f, "TOPLEFT", X, -34)
        f.dungeons:SetScript("OnClick", function(self) UI.pickWorkerDungeons(self) end)
        field(f, "任務", 18, -76)
        f.quests = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.quests:SetSize(160, 24)
        f.quests:SetPoint("TOPLEFT", f, "TOPLEFT", X, -70)
        f.quests:SetScript("OnClick", function(self) UI.pickWorkerQuests(self) end)
        field(f, "職責", 18, -114)
        field(f, "副職責", 18, -150)
        f.mainRoles, f.altRoles = {}, {}
        for i, r in ipairs(A().ROLES) do
            local m = iconButton(f, 24, "dungeon", UI.ROLE_NAME[r], function()
                wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end; drawWorker()
            end, UI.ROLE_NAME[r])
            ns.GameIcons.set(m.tex, UI.GAME[r])
            m:SetPoint("TOPLEFT", f, "TOPLEFT", X + (i - 1) * 80, -108)
            f.mainRoles[r] = m
            local a = iconButton(f, 20, "dungeon", UI.ROLE_NAME[r], function()
                wdraft.alt = (wdraft.alt == r or wdraft.main == r) and nil or r; drawWorker()
            end, UI.ROLE_NAME[r])
            ns.GameIcons.set(a.tex, UI.GAME[r])
            a:SetPoint("TOPLEFT", f, "TOPLEFT", X + (i - 1) * 80, -146)
            f.altRoles[r] = a
        end
        f.roles = f.mainRoles.t
        field(f, "時段", 18, -188)
        f.slots = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.slots:SetSize(380, 24)
        f.slots:SetPoint("TOPLEFT", f, "TOPLEFT", X, -182)
        f.slots:SetScript("OnClick", function(self) UI.pickWorkerSlots(self) end)
        f.remove = iconButton(f, 22, "no", "移除", function() A().removeWorker(); f:Hide(); UI.refresh() end, "移除職工單")
        f.remove:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 14)
        f.save = ns.createFrame("Button", nil, f, "UIPanelButtonTemplate"); f.save:SetSize(96, 24)
        f.save:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 14); f.save:SetText(tex("yes", 16) .. " 登記")
        f.save:SetScript("OnClick", function() UI.saveWorker() end)
        f:Hide()
        wpopup = f
    end
    wpopup:Show()
    drawWorker()
    return wdraft
end
function UI.workerDraft() return wdraft end

function UI.saveWorker(d)
    d = d or wdraft
    local ok = A().setWorker(d)
    if wpopup then wpopup:Hide() end
    UI.refresh()
    return ok
end

function UI.toggleWorkerDungeon(id)
    for i, x in ipairs(wdraft.dungeons) do if x == id then table.remove(wdraft.dungeons, i); drawWorker(); return false end end
    wdraft.dungeons[#wdraft.dungeons + 1] = id
    drawWorker()
    return true
end

function UI.pickWorkerDungeons(owner)
    return UI.dungeonGrid(owner, function(id) UI.toggleWorkerDungeon(id) end, function(id)
        for _, x in ipairs(wdraft.dungeons) do if x == id then return true end end
        return false
    end)
end

function UI.pickWorkerQuests(owner)
    local items = { { text = tex("quest") .. " *", fn = function() wdraft.allQuests = not wdraft.allQuests; drawWorker() end } }
    local log = A().questLog()
    if log then
        local n = 0
        for id, q in pairs(log) do
            n = n + 1
            if n > 12 then break end
            local on = false
            for _, x in ipairs(wdraft.quests) do if x == id then on = true end end
            items[#items + 1] = { text = (on and tex("yes") or "") .. str(q.title), fn = function()
                for i, x in ipairs(wdraft.quests) do if x == id then table.remove(wdraft.quests, i); drawWorker(); return end end
                wdraft.quests[#wdraft.quests + 1] = id
                drawWorker()
            end }
        end
    end
    return UI.menu(owner, items)
end

function UI.pickWorkerRoles(owner)
    local items = {}
    for _, r in ipairs(A().ROLES) do
        items[#items + 1] = { text = tex(r) .. " " .. UI.ROLE_NAME[r], fn = function() wdraft.main = r; if wdraft.alt == r then wdraft.alt = nil end drawWorker() end }
    end
    for _, r in ipairs(A().ROLES) do
        items[#items + 1] = { text = "(" .. tex(r) .. ")", fn = function() wdraft.alt = (wdraft.alt == r or wdraft.main == r) and nil or r; drawWorker() end }
    end
    return UI.menu(owner, items)
end

function UI.pickWorkerSlots(owner)
    local items = { { text = tex("now") .. " 現在", fn = function() wdraft.slots = { { now = true } }; drawWorker() end } }
    for _, t in ipairs(UI.quarterTimes(S().serverNow(), 12)) do
        items[#items + 1] = { text = "+ " .. UI.clock(t) .. "～" .. UI.clock(t + 7200), fn = function()
            local kept = {}
            for _, sl in ipairs(wdraft.slots) do if not sl.now then kept[#kept + 1] = sl end end
            if #kept < A().MAX_SLOTS then kept[#kept + 1] = { s = t, e = t + 7200 } end
            wdraft.slots = kept
            drawWorker()
        end }
    end
    return UI.menu(owner, UI.titled("時段", items))
end

---------------------------------------------------------------------------
-- Minimap: a second number for adventures (R-8.2), its own color and corner
---------------------------------------------------------------------------

function UI.updateBadge()
    local b = ns.Framework.minimapButton
    if not b then return end
    if not b.adventureBadge then
        b.adventureBadge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.adventureBadge:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        b.adventureBadge:SetTextColor(1, 0.35, 0.3)
    end
    local n = ns.guildState() == "target" and A().attentionCount() or 0
    b.adventureBadge:SetText(n > 0 and tostring(n) or "")
    UI.badgeCount = n
end

-- Two lines of numbers in the minimap tooltip (R-8.2).
ns.Framework.tooltipLines = ns.Framework.tooltipLines or {}
table.insert(ns.Framework.tooltipLines, function(tip)
    local a = UI.badgeCount or 0
    local o = ns.OrdersUI and ns.OrdersUI.badgeCount or 0
    if a > 0 then tip:AddLine(tex("dungeon") .. " 冒險 " .. a, 1, 0.5, 0.45) end
    if o > 0 then tip:AddLine(ns.OrdersUI.tex("making") .. " 訂單 " .. o, 1, 0.82, 0) end
end)

A().onChanged = function()
    ns.coalesce("adventure-page", 1, function()
        UI.updateBadge()
        if ns.Framework.isModuleShown("adventure") then UI.refresh() end
    end)
end
