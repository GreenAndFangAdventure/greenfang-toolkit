-- SupplyRules (GF-009-02, v2.0 附錄 A §3): collection rules as data. A new
-- collection only adds a rule here; the calculation (Supply.lua), the GFTKS
-- group and the page work from the data. Logic always uses ItemIDs; names
-- and icons come from the client when the page draws.
--
-- state: "experimental" (candidate data, not checked in the Forever client:
-- only used after the player turns on 試用) / "enabled" (checked in game) /
-- "disabled". Only the owner's in-game check may turn the first rule into
-- "enabled" (附錄 A §12.1).

local _, ns = ...

local Rules = {}
ns.SupplyRules = Rules

-- Bumped when the rule data changes in a way older clients cannot read.
Rules.LIBRARY_VERSION = 1

local function pageItem(page) return 2724 + page end

Rules.list = {
    {
        collectionID = "green_hills_pages",
        num = 1,                -- the GFTKS group is "C" .. num
        rulesVersion = 1,
        state = "experimental", -- classic data; Forever not checked (附錄 A §3)
        title = "荊棘谷書頁",
        parentQuestID = 338,
        perItemRequired = 1,
        -- Tradeable is the classic data; to be checked in the Forever client.
        candidateTradeable = true,
        -- How a chapter counts as done: the chapter quest is flagged completed
        -- (C_QuestLog.IsQuestFlaggedCompleted). In the log = collecting it.
        chapters = {
            { questID = 339, title = "第一章", pages = { 1, 4, 6, 8 } },
            { questID = 340, title = "第二章", pages = { 10, 11, 14, 16 } },
            { questID = 341, title = "第三章", pages = { 18, 20, 21, 24 } },
            { questID = 342, title = "第四章", pages = { 25, 26, 27 } },
        },
        itemIDFor = pageItem,   -- expanded below into chapter.items
        itemLabel = function(page) return string.format("第%d頁", page) end,
        -- Not on any of its quests: keep this many of each page (附錄 A §3.2).
        reserveWhenIdle = 1,
    },
}

-- Expand the data once: chapter.items = { { itemID, page, need } },
-- rule.items = { [itemID] = { chapter = i, page = p, need = n } }.
local function expand(rule)
    rule.items, rule.order = {}, {}
    for ci, ch in ipairs(rule.chapters) do
        ch.items = {}
        for _, page in ipairs(ch.pages) do
            local id = rule.itemIDFor(page)
            local it = { itemID = id, page = page, need = rule.perItemRequired or 1, chapter = ci,
                label = rule.itemLabel and rule.itemLabel(page) or nil }
            ch.items[#ch.items + 1] = it
            rule.items[id] = it
            rule.order[#rule.order + 1] = id
        end
    end
end

-- Check the library: required fields, ItemIDs positive, no ItemID in two
-- usable rules (MVP: the second one is turned off, 附錄 A §4.2). Returns
-- the problems found (diagnostics only).
function Rules.validate(list)
    list = list or Rules.list
    local problems, owner, nums = {}, {}, {}
    for _, rule in ipairs(list) do
        local okRule = type(rule.collectionID) == "string" and type(rule.num) == "number"
            and type(rule.rulesVersion) == "number" and type(rule.chapters) == "table" and #rule.chapters > 0
        if okRule and nums[rule.num] then okRule = false end
        if okRule then
            local ok2 = pcall(expand, rule)
            okRule = ok2
        end
        if okRule then
            for id in pairs(rule.items) do
                if type(id) ~= "number" or id <= 0 or id ~= math.floor(id) then okRule = false end
            end
        end
        if not okRule then
            rule.usable = false
            problems[#problems + 1] = string.format("規則 %s 資料不完整，已停用", tostring(rule.collectionID))
        elseif rule.state == "disabled" then
            rule.usable = false
        else
            local clash
            for id in pairs(rule.items) do
                if owner[id] then clash = owner[id] end
            end
            if clash then
                rule.usable = false
                problems[#problems + 1] = string.format("規則 %s 和 %s 有相同物品，已停用後者", clash, rule.collectionID)
            else
                rule.usable = true
                nums[rule.num] = rule
                for id in pairs(rule.items) do owner[id] = rule.collectionID end
            end
        end
    end
    Rules.problems = problems
    return problems
end

function Rules.byNum(n)
    for _, r in ipairs(Rules.list) do
        if r.usable and r.num == n then return r end
    end
    return nil
end

function Rules.byID(id)
    for _, r in ipairs(Rules.list) do
        if r.collectionID == id then return r end
    end
    return nil
end

-- Usable rules; experimental ones only when allowed.
function Rules.active(allowExperimental)
    local out = {}
    for _, r in ipairs(Rules.list) do
        if r.usable and (r.state == "enabled" or (r.state == "experimental" and allowExperimental)) then
            out[#out + 1] = r
        end
    end
    return out
end

function Rules.groupOf(rule) return "C" .. rule.num end
function Rules.numOfGroup(g)
    local n = type(g) == "string" and g:match("^C(%d+)$")
    return n and tonumber(n) or nil
end

Rules.validate()
