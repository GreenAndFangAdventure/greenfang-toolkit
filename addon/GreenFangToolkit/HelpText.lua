-- HelpText (GF-UI-R): every word of the 「說明」 mode in one place (H.TEXT:
-- key -> { 名稱, 一兩句白話：做什麼用 }), then each page's parts (H.register:
-- which frame, which words) and the pop-ups that have the button (H.POPUP).
-- Change a sentence here only; Help.lua draws them. Glyphs: only what the
-- game font has (no arrows or other symbols).

local _, ns = ...
local H = ns.Help
local F = ns.Framework

---------------------------------------------------------------------------
-- The words
---------------------------------------------------------------------------

H.TEXT = {
    -- The main window (every page)
    nav = { "主入口", "左邊六個主入口，按一下換到那一類業務；最下面的「事務設定」打開同步與診斷。" },
    subtabs = { "分頁", "同一個入口底下的幾頁，金色的是現在這一頁。" },
    version = { "版本", "目前裝的工具箱版本；字的顏色就是同步狀態（綠色＝正常記錄中），滑鼠移上去看說明，按一下打開「同步與診斷」。" },
    bell = { "業務通知", "別人對你的委託、冒險單或臨時黑箱申領有動作時記在這裡；旁邊的數字是還沒看的則數。" },

    -- 職工檔案
    char_who = { "角色資料", "你這隻角色的名字、等級、公會和所在地，登入後自動讀取。" },
    char_prof = { "專業技能", "你的專業和熟練度。點一下有視窗的專業會直接打開它（戰鬥中不行）。" },
    char_recipes = { "配方", "看你自己學會的配方清單，公會其他人也看得到。" },
    char_services = { "我的服務", "設定你接哪些專業的委託、工錢多少；別人下單時看得到。" },
    prof_main = { "主職責", "選你最常擔任的職責（坦克、治療、輸出），開冒險單時大家照這個找人。" },
    prof_clear = { "清除定位", "把主職責和可支援一起清空（會先問你）。" },
    prof_can = { "可支援", "除了主職責，你也能擔任的職責，可以多選。" },
    prof_share = { "分享給公會", "勾起來，公會其他人才看得到你的職責。" },
    prof_biz = { "我的業務", "你下的委託和參加的冒險單；點一列直接打開那張單。" },
    prof_needs = { "個人需求", "看你現在缺哪些物品（由物資調度算出）。" },

    -- 職工名冊
    roster_update = { "更新", "重新讀一次公會名冊。平常會自動更新，資料不對時再按。" },
    roster_search = { "搜尋", "打名字、職業或專業的字，只列出符合的會友。" },
    roster_skill = { "專業篩選", "勾選專業，只看會這些專業的人；可以複選。" },
    roster_class = { "職業篩選", "勾選職業，只看這些職業；可以複選。" },
    roster_more = { "更多篩選", "打開後可以勾在線、接單中、有裝工具箱，或填等級（只看這個等級以上），可以同時勾好幾個；按鈕上的數字是開著幾項。" },
    roster_clear = { "清除", "把上面的篩選全部清掉，回到完整名冊。" },
    roster_census = { "職責人數", "公會裡坦克、治療、輸出各有幾人；點圖示只看那個職責，再點一次取消。" },
    roster_head = { "欄位名稱", "點欄位名稱依那一欄排序，再點一次反過來排。" },
    roster_list = { "會友清單", "滑鼠移上去看詳細資料；點選或按右鍵可以密語、邀請、看配方。" },
    roster_bar = { "對選到的人", "選了一位會友後，這裡列出可以對他做的事。" },
    roster_invite = { "邀請", "邀請新人加入公會（要有公會的邀請權限）。" },
    roster_info = { "公會", "看公會訊息與公會資訊；有權限的人可以修改。" },

    -- 委託業務｜製作委託
    orders_new = { "＋下單", "請公會工匠幫你做東西：按了切到「工匠配方」，在要的配方那列按「下單」，再填數量和工錢送出。" },
    orders_services = { "我的服務", "設定你接哪些專業的委託、工錢多少。" },
    orders_prof = { "接單設定", "你會的專業：點圖示切換接單或不接，按「工錢」設定收多少。" },
    orders_list = { "委託清單", "你下的單和別人交給你的單都在這裡；每一列右邊是能做的下一步。" },
    orders_history = { "歷史", "看已經結束的委託。" },
    orders_paste = { "匯入", "貼上網站產生的匯入碼，把網站上的訂單帶進來。" },
    -- 委託業務｜工匠配方
    recipes_search = { "搜尋", "打配方或物品的名字，只列出符合的。" },
    recipes_skill = { "專業", "只看某些專業的配方，可以複選。" },
    recipes_who = { "會做的人", "依會做的人篩選，例如只看在公會裡有人會的。" },
    recipes_online = { "只看在線", "只列出現在有人在線上能做的配方。" },
    recipes_active = { "接單中", "只看有工匠開放接單的配方。" },
    recipes_fee = { "工錢", "依工錢篩選，例如只看免費的。" },
    recipes_all = { "全部", "現在只看一個人的配方；按這裡回到全部的人。" },
    recipes_list = { "配方清單", "公會裡有人會做的配方、誰會做、工錢多少；按列上的「下單」開始下單（在搜尋按 Enter＝第一列下單）。" },
    -- 下單
    form_item = { "成品", "這張單要做的東西；滑鼠移上去看物品說明。" },
    form_qty = { "數量", "要做幾份；一次做出好幾個的配方，一格就是一次的數量。" },
    form_target = { "對象", "交給整個公會（誰有空誰接），或指定一位工匠；名字後面寫「接單中」表示他現在有開接單。" },
    form_mats = { "材料", "這個配方要的材料、你背包裡有幾個、要不要自己帶去。" },
    form_matcost = { "材料費", "不是自己帶的材料大約要花多少錢；材料都沒有價格時寫「無法估價」。" },
    form_fee = { "工錢", "付給工匠的工錢，可以自己改。" },
    form_total = { "合計", "材料費加工錢的總數；前面有「＞」表示有材料沒有價格，實際會更多。" },
    form_market = { "行情", "這個成品在拍賣場大約賣多少，給你比較用。要有行情：找拍賣師打開拍賣場，按視窗右上角旁的「掃描行情」，公會裡有人掃過也會自動分享給你。" },
    form_send = { "下單", "確認後送出，工匠會收到通知。" },

    -- 物資調度｜綠皮調貨所
    supply_tabs = { "看板與刊登", "調貨看板看全公會的徵求、供應和臨時黑箱存貨；我的刊登管理你自己發的。" },
    -- GF-UI-S: what the 自動集料說明 / 手動刊登說明 cards said, the main points.
    supply_auto = { "自動集料", "打開後照任務進度和你的行囊、材料袋、銀行、信箱算出缺幾個、多幾個，只分享數量，不公開背包、不自動交易。實驗功能，預設關。" },
    supply_auto_help = { "集料項目", "列出自動集料會看哪些物品；也可以選分享的餘料要算哪裡。" },
    supply_manual = { "手動刊登", "打開後可以自己發徵求或供應，公會的人看得到；聯絡只打開密語框，不自動交易。關掉後不分享也不顯示刊登，你的刊登留著，再打開就恢復。" },
    supply_post = { "＋刊登", "自己發一筆徵求（找東西）或供應（有多的）。" },
    supply_search = { "搜尋", "打物品名或職工名，只列出符合的。" },
    supply_kind = { "種類", "只看徵求、供應或臨時黑箱存貨。" },
    supply_scope = { "範圍", "只看你缺的、你可能有多的，或和你有關的。" },
    supply_group = { "收集組", "只看某一組收集規則（例如某個任務線）要的物品。" },
    supply_list = { "物品清單", "點一列，右邊會列出誰有、誰要。" },
    supply_detail = { "誰有誰要", "選到的物品有哪些職工徵求或供應、在不在線；你自己的刊登可以在這裡修改、續期或結束。" },
    -- 物資調度｜臨時黑箱
    bank_views = { "臨時黑箱分頁", "庫存看臨時黑箱裡有什麼；申領處理領取申請；保管人與分享設定管理誰保管；公會銀行看存款與進出。" },
    bank_search = { "搜尋", "打物品名，只列出符合的。" },
    bank_class = { "分類", "只看某一類物品。" },
    bank_holder = { "保管人", "只看某一位保管人身上的東西。" },
    bank_online = { "只看在線", "只看現在在線上的保管人，比較快拿得到。" },
    bank_stock = { "庫存清單", "臨時黑箱裡的物品；每列右邊「聯絡」找保管人，「申領」填單請保管人給你。" },
    bank_todo = { "要我處理的", "別人申領你保管的東西，在這裡同意或拒絕。" },
    bank_mine = { "我的申領", "你送出的申領和目前的狀態。" },
    bank_status = { "我的身分", "你在臨時黑箱的身分（會長、保管人或一般職工）和能做的事。" },
    bank_keepers = { "保管人名單", "會長指定的保管人；臨時黑箱的存貨就是他們身上的公產。" },
    bank_appoint = { "＋保管人", "打名字後按「＋保管人」加入名單（只有會長能用）。" },
    bank_officers = { "審核幹部", "可以幫忙審核申領的人（只有會長能指定）。" },
    bank_scope = { "我的公產範圍", "勾選你背包和銀行裡哪幾格算公產，只有這些會分享出去。" },
    bank_share = { "分享", "打開後，你保管的公產存貨會分享給公會。" },
    -- 物資調度｜公會銀行
    gb_money = { "目前存款", "公會銀行的存款（最近一次有人打開公會銀行時看到的）。" },
    gb_sums = { "近期合計", "最近 7 天、30 天的存入和支出合計。" },
    gb_filter = { "全部、存入、支出", "只看存入或只看支出的紀錄。" },
    gb_search = { "角色名", "打角色名，只看這個人的紀錄。" },
    gb_list = { "進出紀錄", "公會銀行的存入與支出，最新的在上面。" },

    -- 冒險業務｜業務大廳
    adv_new = { "＋冒險單", "開一張團，找人一起打地城或做任務。" },
    adv_worker = { "＋職工單", "登記你想參加什麼、什麼時候有空，讓開團的人找得到你。" },
    adv_calendar = { "業務排程", "用週曆或月曆看大家排了哪些時段。" },
    adv_lfg = { "尋求組隊", "打開遊戲內建的尋求組隊，找現在有人在組的隊伍。" },
    adv_tabs = { "進行中、已結束", "切換看還在進行的單，或已經結束的單。" },
    adv_rules = { "規則", "冒險單的規則：怎麼錄取、什麼時候算成行或過期。" },
    adv_search = { "搜尋", "打地城、任務或人名，只列出符合的單。" },
    adv_kind = { "種類", "只看冒險單或職工單等某一種。" },
    adv_zone = { "區域", "只看某些區域的單，可以複選。" },
    adv_room = { "只看有空位的", "只列出還缺人的單。" },
    adv_list = { "單子清單", "每一列是一張單；右邊是你可以做的事（報名、撤回、錄取等）。" },
    adv_clear = { "清除", "刪掉你自己已經結束的單和紀錄（會先問你）。" },
    adv_next = { "下一位", "邀請下一位等著入隊的人。" },
    -- 開單
    ticket_dest = { "活動", "選要去的地城或要做的任務。" },
    ticket_roles = { "職責", "這團要幾個坦克、治療、輸出；人數在「更多設定」裡改。" },
    ticket_slots = { "時段", "什麼時候出發；可以加好幾個時段讓大家挑。" },
    ticket_note = { "備註", "寫給報名的人看的一句話，例如集合地點。" },
    ticket_more = { "更多設定", "打開後可以改人數、錄取方式和標籤。" },
    ticket_mode = { "錄取", "直接錄取：先報先上；團長同意：你一個一個決定。" },
    ticket_tags = { "標籤", "標出這團的性質，方便別人篩選。" },
    ticket_lfg = { "上架到尋求組隊", "同時登到遊戲內建的尋求組隊（只有「現在」出發的地城可以）。" },
    ticket_go = { "開單", "確認後把冒險單發給公會。" },
    -- 業務排程
    cal_week = { "換週", "看上一週、下一週；中間是現在看的日期。" },
    cal_legend = { "圖例", "格子裡的記號各代表什麼；滑鼠移上去看說明。" },
    cal_view = { "週、月", "切換週曆或月曆。" },
    cal_days = { "日期格", "每一格是一天，裡面是那天的單；點一天在下面列出明細。" },
    cal_list = { "當天明細", "點選那一天的所有單；點一列可以打開那張單。" },

    -- 冒險指南｜睡袋指南
    sb_progress = { "進度", "你走到整條路線的哪裡。" },
    sb_mode = { "模式", "切換路線的寫法。" },
    sb_steps = { "上一步、下一步", "照著路線一步一步走；中間是現在第幾步。" },
    sb_reveal = { "顯示座標與走法", "把這一步的座標和走法直接寫出來。" },
    sb_map = { "看地圖", "在世界地圖上標出這一步要去的地方。" },
    sb_size = { "字的大小", "把下面說明文字調大或調小。" },
    sb_reset = { "重設進度", "從第一步重新開始（會先問你）。" },
    sb_hint = { "任務進度", "依任務日誌看你做到哪一步；按旁邊的按鈕直接跳過去。" },
    sb_body = { "這一步的走法", "詳細說明；有顏色的地名可以點，會在地圖上標出來。" },

    -- 業務通知（清單）
    notify_read = { "全部已讀", "把所有通知標成已讀，數字會歸零。" },
    notify_setup = { "設定", "選哪些事要通知你、要不要在聊天框也說一聲。" },
    notify_rows = { "通知", "每一則通知；點一下打開那張單，右邊是可以直接做的事。" },

    -- 事務設定｜同步與診斷
    set_state = { "同步狀態", "工具箱資料和網站同步得順不順利。" },
    set_body = { "詳細資料", "各項資料的狀況，遇到問題時給管理員看。" },
    set_export = { "匯出", "把名冊資料匯出成表格（TSV）或 JSON 文字，可以貼到別處。" },
    set_refresh = { "更新", "重新整理這個視窗的內容。" },
    set_minimap = { "小地圖", "小地圖按鈕找不到時，按這裡放回原位。" },
    set_clear = { "清除結案", "刪掉你已經結束（成交或取消）的委託紀錄；進行中的委託不會動。按下去會先問你。" },
    set_test = { "測試", "打開測試模式，可以自己下單給自己試用；關掉時會刪掉測試單。" },
    set_location = { "分享位置", "讓公會看到你在哪個區域；關掉就不分享。" },
}

---------------------------------------------------------------------------
-- Getters
---------------------------------------------------------------------------

local function panel(id) return F.panel(id) end
local function withLabel(b) return { b, b and b.label } end
local function popup(name) return name and _G[name] end
-- Icon buttons with their names (a table of them).
local function roles(t)
    local out = {}
    for _, b in pairs(t or {}) do out[#out + 1] = withLabel(b) end
    return out
end

---------------------------------------------------------------------------
-- The main window: the same parts on every page (after the page's own)
---------------------------------------------------------------------------

H.register("frame", {
    { key = "nav", get = function() local w = _G[F.WINDOW_NAME]; return w and w.nav end },
    { key = "subtabs", get = function()
        local out = {}
        for _, b in ipairs(F.subTabButtons()) do if b:IsShown() then out[#out + 1] = b end end
        return out
    end },
    { key = "version", get = function() return F.infoButton() end },
    { key = "bell", get = function() return ns.NotifyUI and ns.NotifyUI.button() end },
})

---------------------------------------------------------------------------
-- 職工檔案
---------------------------------------------------------------------------

H.register("character", {
    { key = "char_who", area = function() return panel("character"), 18, -36, 568, 106 end },
    { key = "char_recipes", get = function() return ns.Character.recipesButton end },
    { key = "char_services", get = function() return ns.Character.servicesButton end },
    { key = "char_prof", get = function() return ns.Character.profRows end },
    { key = "prof_main", get = function() local c = ns.ProfileUI.controls; return { c.mainLabel, roles(c.main) } end },
    { key = "prof_clear", get = function() return ns.ProfileUI.controls.unset end },
    { key = "prof_can", get = function() local c = ns.ProfileUI.controls; return { c.canLabel, roles(c.can) } end },
    { key = "prof_share", get = function() return withLabel(ns.ProfileUI.controls.share) end },
    { key = "prof_biz", get = function()
        local c = ns.ProfileUI.controls
        return { c.bizHead, c.rows, c.bizEmpty }
    end },
    { key = "prof_needs", get = function() local c = ns.ProfileUI.controls; return { c.needsHead, c.needsButton } end },
})

---------------------------------------------------------------------------
-- 職工名冊
---------------------------------------------------------------------------

H.register("roster", {
    { key = "roster_update", get = function() return ns.UI.updateButton end },
    { key = "roster_search", get = function() return ns.UI.searchBox end },
    { key = "roster_skill", get = function() return ns.UI.skillChoice end },
    { key = "roster_class", get = function() return ns.UI.classChoice end },
    { key = "roster_more", get = function() return ns.UI.moreFilterButton end },
    { key = "roster_clear", get = function() return ns.UI.clearButton end },
    { key = "roster_census", get = function()
        local c = ns.UI.census
        return { roles(c.roles), withLabel(c.unknown) }
    end },
    { key = "roster_head", get = function() return ns.UI.header end },
    { key = "roster_list", get = function() return ns.UI.scrollFrame() end },
    { key = "roster_bar", get = function() return ns.UI.actionBar end },
    { key = "roster_invite", get = function() return ns.UI.inviteButton end },
    { key = "roster_info", get = function() return ns.UI.infoButton end },
})

---------------------------------------------------------------------------
-- 委託業務
---------------------------------------------------------------------------

H.register("orders", {
    { key = "orders_new", get = function() return ns.OrdersUI.orderButton end },
    { key = "orders_services", get = function() return ns.OrdersUI.servicesButton end },
    { key = "orders_prof", get = function()
        local out = { ns.OrdersUI.profField }
        for _, b in ipairs(ns.OrdersUI.profButtons()) do
            if b:IsShown() then out[#out + 1] = { b, b.label, b.feeButton, b.feeTex, b.feeText } end
        end
        return out
    end },
    { key = "orders_list", get = function() return ns.OrdersUI.scrollFrame() end },
    { key = "orders_paste", get = function() return withLabel(ns.OrdersUI.pasteButton) end },
    { key = "orders_history", get = function() return withLabel(ns.OrdersUI.historyButton) end },
})

H.register("recipes", {
    { key = "recipes_search", get = function() return ns.Recipes.searchBox end },
    { key = "recipes_skill", get = function() return ns.Recipes.skillChoice end },
    { key = "recipes_who", get = function() return ns.Recipes.whoChoice end },
    { key = "recipes_online", get = function() return withLabel(ns.Recipes.onlineCheck) end },
    { key = "recipes_active", get = function() return withLabel(ns.Recipes.activeCheck) end },
    { key = "recipes_fee", get = function() return ns.Recipes.feeChoice end },
    { key = "recipes_all", get = function() return ns.Recipes.clearFilterButton end },
    { key = "recipes_list", area = function() return panel("recipes"), 20, -118, 1040, 536 end },
})

H.POPUP[ns.OrdersUI.POPUP_NAME] = "orderform"
H.register("orderform", {
    { key = "form_item", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return withLabel(f.item) end },
    { key = "form_qty", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return { f.minus, f.qty, f.plus } end },
    { key = "form_target", get = function()
        local f = popup(ns.OrdersUI.POPUP_NAME)
        return { withLabel(f.guild), withLabel(f.named) }
    end },
    { key = "form_mats", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return { f.matHead, f.matBox } end },
    { key = "form_matcost", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return { f.matsIcon, f.matsCost } end },
    { key = "form_fee", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return { f.feeIcon, f.fee } end },
    { key = "form_total", get = function() return popup(ns.OrdersUI.POPUP_NAME).total end },
    { key = "form_market", get = function() local f = popup(ns.OrdersUI.POPUP_NAME); return { f.marketIcon, f.market } end },
    { key = "form_send", get = function() return popup(ns.OrdersUI.POPUP_NAME).send end },
})

---------------------------------------------------------------------------
-- 物資調度
---------------------------------------------------------------------------

H.register("supply", {
    { key = "supply_tabs", get = function() return ns.SupplyUI.tabs.buttons end },
    { key = "supply_auto", get = function() local c = ns.SupplyUI.autoBox; return { c.label, c.cells } end },
    { key = "supply_auto_help", get = function() return ns.SupplyUI.autoBox.help end },
    { key = "supply_post", get = function() return ns.SupplyUI.postButton end },
    { key = "supply_manual", get = function() local c = ns.SupplyUI.manualBox; return { c.label, c.cells } end },
    { key = "supply_search", get = function() return { ns.SupplyUI.searchLabel, ns.SupplyUI.searchBox } end },
    { key = "supply_kind", get = function() return { ns.SupplyUI.kindLabel, ns.SupplyUI.kindDrop } end },
    { key = "supply_scope", get = function() return { ns.SupplyUI.scopeLabel, ns.SupplyUI.scopeDrop } end },
    { key = "supply_group", get = function() return { ns.SupplyUI.groupLabel, ns.SupplyUI.groupButton } end },
    { key = "supply_list", area = function()
        local U = ns.SupplyUI
        return panel(U.ID), U.LIST_X, U.HEAD_Y, U.LIST_W, U.HEAD_Y - U.TOP + U.ROWS * U.ROW_H
    end },
    { key = "supply_detail", area = function()
        local U = ns.SupplyUI
        return panel(U.ID), U.DETAIL_X, U.HEAD_Y, U.DETAIL_W, U.HEAD_Y - U.TOP + U.ROWS * U.ROW_H
    end },
})

local function bankC() return ns.BankUI.controls end
H.register("bank", {
    { key = "bank_views", get = function() return bankC().views.buttons end },
    -- 庫存
    { key = "bank_search", get = function() local c = bankC(); return { c.searchLabel, c.search } end },
    { key = "bank_class", get = function() local c = bankC(); return { c.classLabel, c.classDrop } end },
    { key = "bank_holder", get = function() local c = bankC(); return { c.holderLabel, c.holderDrop } end },
    { key = "bank_online", get = function() return withLabel(bankC().online) end },
    { key = "bank_stock", area = function()
        local U = ns.BankUI
        return bankC().stockView, U.X, U.Y.stockHead, U.STOCK_W, U.Y.stockHead - U.Y.stockRows + U.STOCK_ROWS * U.STOCK_ROW_H
    end },
    -- 申領
    { key = "bank_todo", area = function()
        local U = ns.BankUI
        return bankC().requestsView, U.X, U.REQ_Y.todoHead, U.STOCK_W, U.REQ_Y.todoHead - U.REQ_Y.todoRows + U.REQ_ROWS * U.REQ_ROW_H
    end },
    { key = "bank_mine", area = function()
        local U = ns.BankUI
        return bankC().requestsView, U.X, U.REQ_Y.mineHead, U.STOCK_W, U.REQ_Y.mineHead - U.REQ_Y.mineRows + U.REQ_ROWS * U.REQ_ROW_H
    end },
    -- 保管人與分享設定
    { key = "bank_status", get = function() return bankC().status end },
    { key = "bank_keepers", area = function()
        local U = ns.BankUI
        return bankC().setupView, U.X, U.Y.listHead, U.ROW_W, U.Y.listHead - U.Y.rows + U.ROWS * U.ROW_H
    end },
    { key = "bank_appoint", get = function() local c = bankC(); return { c.nameLabel, c.name, c.appoint } end },
    { key = "bank_officers", get = function() local c = bankC(); return { c.officerHead, c.officerAdd, c.officerRows } end },
    { key = "bank_scope", get = function() local c = bankC(); return { c.scopeHead, c.scopeLabel, c.scope } end },
    { key = "bank_share", get = function() return withLabel(bankC().share) end },
    -- 公會銀行 (GuildBankUI's view)
    { key = "gb_money", get = function() local c = ns.GuildBankUI.c; return { c.moneyLabel, c.money } end },
    { key = "gb_sums", get = function() local c = ns.GuildBankUI.c; return { c.sum7, c.sum30 } end },
    { key = "gb_filter", get = function() return ns.GuildBankUI.c.filters end },
    { key = "gb_search", get = function() local c = ns.GuildBankUI.c; return { c.searchLabel, c.search } end },
    { key = "gb_list", get = function() local c = ns.GuildBankUI.c; return { c.heads, c.rows } end },
})

---------------------------------------------------------------------------
-- 冒險業務
---------------------------------------------------------------------------

H.register("adventure", {
    { key = "adv_new", get = function() return ns.AdventureUI.newButton end },
    { key = "adv_worker", get = function() return ns.AdventureUI.workerButton end },
    { key = "adv_calendar", get = function() return ns.AdventureUI.calendarButton end },
    { key = "adv_lfg", get = function() return ns.AdventureUI.lfgButton end },
    { key = "adv_tabs", get = function() return { ns.AdventureUI.activeTab, ns.AdventureUI.endedTab } end },
    { key = "adv_rules", get = function() return ns.AdventureUI.rulesButton end },
    { key = "adv_search", get = function() return { ns.AdventureUI.searchLabel, ns.AdventureUI.searchBox } end },
    { key = "adv_kind", get = function() return { ns.AdventureUI.kindLabel, ns.AdventureUI.kindDrop } end },
    { key = "adv_zone", get = function() return ns.AdventureUI.zoneButton end },
    { key = "adv_room", get = function() return withLabel(ns.AdventureUI.roomBox) end },
    { key = "adv_list", get = function() return ns.AdventureUI.scrollFrame() end },
    { key = "adv_clear", get = function() return ns.AdventureUI.clearButton end },
    { key = "adv_next", get = function() return ns.AdventureUI.nextInvite end },
})

H.POPUP[ns.AdventureUI.TICKET_NAME] = "ticket"
local function ticket() return popup(ns.AdventureUI.TICKET_NAME) end
H.register("ticket", {
    { key = "ticket_dest", get = function() local f = ticket(); return { f.destIcon, f.destName, f.dest, f.destQuest } end },
    { key = "ticket_roles", get = function()
        local out = {}
        for _, g in pairs(ticket().roleGroups) do out[#out + 1] = { g.icon, g.text } end
        return out
    end },
    { key = "ticket_slots", get = function() local f = ticket(); return { f.slotChips, f.addSlot } end },
    { key = "ticket_note", get = function() return ticket().note end },
    { key = "ticket_more", get = function() local f = ticket(); return { f.moreToggle, f.moreSummary } end },
    { key = "ticket_mode", get = function() local f = ticket(); return { withLabel(f.direct), withLabel(f.consent) } end },
    { key = "ticket_tags", get = function()
        local out = {}
        for _, b in ipairs(ticket().tagList) do out[#out + 1] = withLabel(b) end
        return out
    end },
    { key = "ticket_lfg", get = function() return withLabel(ticket().lfgCheck) end },
    { key = "ticket_go", get = function() return ticket().go end },
})

H.POPUP[ns.AdventureUI.CALENDAR_NAME] = "calendar"
local function cal() return popup(ns.AdventureUI.CALENDAR_NAME) end
H.register("calendar", {
    { key = "cal_week", get = function() local f = cal(); return { f.prev, f.weekLabel, f.next } end },
    { key = "cal_legend", get = function() return cal().legend end },
    { key = "cal_view", get = function() return cal().views.buttons end },
    { key = "cal_days", get = function() return cal().cells end },
    { key = "cal_list", get = function() local f = cal(); return { f.dayLabel, f.list } end },
})

---------------------------------------------------------------------------
-- 冒險指南
---------------------------------------------------------------------------

local SB = ns.SleepingBag
H.register(SB and SB.ID or "sleepingbag", {
    { key = "sb_progress", get = function() return SB.progressLine end },
    { key = "sb_mode", get = function() return SB.modeButton end },
    { key = "sb_steps", get = function() return { SB.backButton, SB.stepLabel, SB.nextButton } end },
    { key = "sb_reveal", get = function() return SB.revealButton end },
    { key = "sb_map", get = function() return SB.mapButton end },
    { key = "sb_size", get = function() return { SB.sizer.minus, SB.sizer.plus } end },
    { key = "sb_reset", get = function() return SB.resetButton end },
    { key = "sb_hint", get = function() return { SB.hintLine, SB.jumpButton } end },
    { key = "sb_body", get = function() return SB.scroll end },
})

---------------------------------------------------------------------------
-- 業務通知 (the list) and 事務設定 (同步與診斷)
---------------------------------------------------------------------------

H.register("notify", {
    { key = "notify_setup", get = function() return ns.NotifyUI.list().setup end },
    { key = "notify_read", get = function() return ns.NotifyUI.list().readAll end },
    { key = "notify_rows", get = function() local l = ns.NotifyUI.list(); return { l.rows, l.empty } end },
})

H.POPUP[ns.Diag.WINDOW_NAME] = "settings"
local function diag() return popup(ns.Diag.WINDOW_NAME) end
H.register("settings", {
    { key = "set_state", get = function() return diag().state end },
    { key = "set_location", get = function() return withLabel(ns.Diag.locationCheck) end },
    { key = "set_body", get = function() return diag().scroll end },
    { key = "set_export", get = function() return { diag().exportLabel, ns.Diag.exportTSVButton, ns.Diag.exportJSONButton } end },
    { key = "set_refresh", get = function() return ns.Diag.refreshButton end },
    { key = "set_minimap", get = function() return ns.Diag.minimapButton end },
    { key = "set_clear", get = function() return ns.Diag.clearButton end },
    { key = "set_test", get = function() return withLabel(ns.Diag.testCheck) end },
})
