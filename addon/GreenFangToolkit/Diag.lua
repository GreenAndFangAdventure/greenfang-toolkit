-- Diag (GF-001-D10 phase 3, D-014 point 6): the 「同步與診斷」 window.
-- Everything technical lives here so the toolkit's pages only show what
-- players use: site sync status and what waits for GF Sync, in-game sharing
-- statistics, the roster scan, versions and clock, and the roster export.
-- Opened by the small 「同步與診斷」 button on the roster page and by /gftk sync.
-- D-015: no switches; the minimap reset lives here (the settings page is gone).

local _, ns = ...
local str = ns.str

local Diag = {}
ns.Diag = Diag

Diag.WINDOW_NAME = "GreenFangToolkit_DiagWindow"
local window
local lines = {}

-- Pure text builders (offline tests).
function Diag.shareText()
    local Share = ns.Share
    local s = Share.store()
    local records, authors = 0, 0
    for _, groups in pairs(s and s.rec or {}) do
        authors = authors + 1
        for _ in pairs(groups) do records = records + 1 end
    end
    local st = Share.stats
    local text = string.format("記錄 %d / %d 筆（%d 位成員）｜佇列 %d 則｜等待補資料 %d 筆｜這次登入：送出 %d、收到 %d、轉傳 %d、被節流 %d、逾時丟棄 %d、空間不足刪除 %d 位",
        records, Share.maxRecords(), authors, Share.queued(), Share.waiting(), st.sent, st.received, st.relayed,
        st.throttled, st.dropped, st.evicted)
    -- GF-001-D19: a profession window with a filter keeps the saved recipes;
    -- this used to be a chat message at every login.
    local skipped = ns.Recipes and ns.Recipes.skippedFiltered() or {}
    if #skipped > 0 then
        text = text .. "｜專業視窗有篩選，配方沒有更新：" .. table.concat(skipped, "、")
    end
    return text
end

function Diag.rosterText()
    local s = ns.Roster.current()
    if not s then return ns.UI.unavailableText() or "尚無名冊報告" end
    return string.format("公會：%s｜伺服器：%s｜掃描時間：%s（本機）｜%d 位角色／%d 位掃描時在線",
        str(s.guild), str(s.realm), ns.Export.timestampText(s), s.total or #s.members, s.online or 0)
end

function Diag.versionText()
    local server = ns.num((ns.call(GetServerTime)))
    local skew = server and (server - ns.now()) or nil
    -- GF-001-D23: the realm the outbox gets, and where it came from.
    local realm = ns.realm()
    local from = ({ GetRealmName = "遊戲", saved = "存檔記住的", GetNormalizedRealmName = "遊戲（無空格）" })[ns.realmSource]
    local full = ns.Data.fullName(ns.str((ns.call(UnitGUID, "player"))))
    return string.format("工具箱 %s｜介面 %s｜伺服器 %s｜角色全名 %s｜伺服器時間和本機差 %s",
        ns.VERSION, tostring(ns.Data.interface()),
        realm ~= "" and string.format("「%s」（%s）", realm, from or "?") or "不明（暫停寫入上傳資料）",
        full and string.format("「%s」", full) or "未取得（名冊載入後補上）",
        skew and (skew .. " 秒") or "不明")
end

Diag.SITE_NOTE = "GF Sync 會在你下線後讀取存檔並上傳。公會網站的名冊主要由 Blizzard API 自動更新，GF Sync 只是補充來源：沒有安裝或關閉同步，網站照樣會更新。"

local SECTIONS = {
    { title = "上傳到公會網站", text = function() return ns.Sync.statusText() end },
    { title = "說明", text = function() return Diag.SITE_NOTE end },
    { title = "遊戲內分享（公會成員之間自動轉傳）", text = Diag.shareText },
    { title = "公會名冊", text = Diag.rosterText },
    { title = "版本", text = Diag.versionText },
}

function Diag.refresh()
    if not window then return end
    for i, sec in ipairs(SECTIONS) do
        local ok, value = pcall(sec.text)
        lines[i]:SetText(ok and str(value) or "讀取失敗")
    end
    window.state:SetText(ns.Sync.shortStatus())
end

local function button(parent, text, w, x, y, fn)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

local function create()
    if window then return window end
    -- GF-001-D20: opaque and above the toolkit window (was see-through).
    local f = ns.popupWindow(Diag.WINDOW_NAME, 640, 470)
    f:SetPoint("CENTER", 0, 20)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    if f.TitleText then f.TitleText:SetText("綠皮冒險工具箱｜同步與診斷") end
    if UISpecialFrames then table.insert(UISpecialFrames, Diag.WINDOW_NAME) end
    f.state = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    f.state:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -36)
    local y = -70
    for i, sec in ipairs(SECTIONS) do
        local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        head:SetPoint("TOPLEFT", f, "TOPLEFT", 20, y)
        head:SetText(sec.title)
        local body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        body:SetPoint("TOPLEFT", f, "TOPLEFT", 28, y - 20)
        body:SetWidth(590)
        body:SetJustifyH("LEFT")
        lines[i] = body
        y = y - 66
    end
    Diag.exportTSVButton = button(f, "匯出名冊 TSV", 130, 20, 16, function() ns.UI.startExport("tsv") end)
    Diag.exportJSONButton = button(f, "匯出名冊 JSON", 130, 158, 16, function() ns.UI.startExport("json") end)
    Diag.refreshButton = button(f, "重新整理", 100, 296, 16, Diag.refresh)
    Diag.minimapButton = button(f, "小地圖按鈕回到預設位置", 200, 404, 16, function()
        ns.Framework.resetMinimap()
        ns.say("小地圖按鈕已回到外圈左下方；也可以按住拖曳，沿外圈調整位置。")
    end)
    f:SetScript("OnShow", Diag.refresh)
    f:Hide()
    window = f
    return f
end

function Diag.open()
    create():Show()
    Diag.refresh()
    return window
end

function Diag.toggle()
    if window and window:IsShown() then window:Hide(); return false end
    Diag.open()
    return true
end

function Diag.isShown() return window ~= nil and window:IsShown() end
function Diag.lines() return lines end

-- The small 「同步與診斷」 button on the roster page.
local smallButtons = {}
function Diag.smallButton(parent, point, x, y)
    local b = ns.createFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(120, 22)
    b:SetPoint(point, parent, point, x, y)
    b:SetText("同步與診斷")
    b:SetScript("OnClick", Diag.toggle)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("同步與診斷")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    smallButtons[#smallButtons + 1] = b
    return b
end

local function onChange()
    if Diag.isShown() then ns.coalesce("diag", 1, function() if Diag.isShown() then Diag.refresh() end end) end
end
ns.Sync.onChange(onChange)
ns.Share.onUpdate(onChange)
