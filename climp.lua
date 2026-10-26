--[[
    REAL MAP SCANNER v3.0
    يتصل بالماب فعلياً ويمسح كل شيء
    AI حقيقي يبني منطقه من النتائج
]]

-- ══════════════════════════════════════
-- انتظر اكتمال التحميل الحقيقي
-- ══════════════════════════════════════
print("[SCANNER] جاري الانتظار حتى يكتمل تحميل الماب...")

repeat
    wait(1)
until game:IsLoaded()
    and workspace ~= nil
    and game.Name ~= "Ugc"
    and game.Name ~= ""
    and #workspace:GetChildren() > 3

wait(4) -- buffer إضافي للـ scripts تشتغل

print("[SCANNER] الماب جاهز: " .. game.Name .. " | بدأ المسح الحقيقي...")

-- ══════════════════════════════════════
-- SERVICES الحقيقية
-- ══════════════════════════════════════
local HttpService        = game:GetService("HttpService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local StarterGui         = game:GetService("StarterGui")
local CoreGui            = game:GetService("CoreGui")

local LP   = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()

-- ══════════════════════════════════════
-- DATA STORE — كل ما يجمعه السكربت
-- ══════════════════════════════════════
local SCAN = {
    game_name      = game.Name,
    place_id       = game.PlaceId,
    scan_time      = os.time(),
    
    -- نتائج المسح الحقيقي
    all_remotes    = {},   -- كل RemoteEvent
    all_functions  = {},   -- كل RemoteFunction
    all_scripts    = {},   -- كل Script/LocalScript
    all_guis       = {},   -- كل ScreenGui/BillboardGui
    workspace_tree = {},   -- هيكل workspace الكامل
    rs_tree        = {},   -- هيكل ReplicatedStorage
    player_stats   = {},   -- leaderstats وكل بيانات اللاعب
    
    -- نتائج AI
    ai = {
        egg_remotes     = {},
        shop_remotes    = {},
        checkpoint_list = {},
        currency_name   = "غير معروف",
        anticheat_found = {},
        pet_objects     = {},
        egg_objects     = {},
        map_type        = "غير محدد",
        purchase_flow   = "غير محدد",
        notes           = {}
    },
    
    -- إحصائيات
    stats = {
        total_instances   = 0,
        total_remotes     = 0,
        total_scripts     = 0,
        total_guis        = 0,
        scan_depth_reached= 0
    }
}

-- ══════════════════════════════════════
-- REAL SCANNER — يمشي على كل instance
-- ══════════════════════════════════════
local function realScan(parent, depth, treePath)
    if depth > 8 then
        if depth > SCAN.stats.scan_depth_reached then
            SCAN.stats.scan_depth_reached = depth
        end
        return
    end

    local ok, children = pcall(function()
        return parent:GetChildren()
    end)
    if not ok or not children then return end

    for _, obj in ipairs(children) do
        SCAN.stats.total_instances += 1
        
        local name  = tostring(obj.Name)
        local class = tostring(obj.ClassName)
        local path  = treePath .. "/" .. name
        local nameLow = name:lower()

        -- ── RemoteEvent ──────────────────────
        if class == "RemoteEvent" then
            SCAN.stats.total_remotes += 1
            local entry = {name=name, path=obj:GetFullName()}
            table.insert(SCAN.all_remotes, entry)

            -- AI: تصنيف فوري
            if nameLow:find("egg") or nameLow:find("hatch") or nameLow:find("collect") then
                table.insert(SCAN.ai.egg_remotes, entry)
            end
            if nameLow:find("buy") or nameLow:find("shop") or nameLow:find("purchase") or nameLow:find("store") then
                table.insert(SCAN.ai.shop_remotes, entry)
            end
            if nameLow:find("anti") or nameLow:find("kick") or nameLow:find("detect") or nameLow:find("ban") then
                table.insert(SCAN.ai.anticheat_found, entry)
            end

            -- استمع للـ traffic الحقيقي من السيرفر
            pcall(function()
                obj.OnClientEvent:Connect(function(...)
                    local args = {...}
                    local argStr = ""
                    for _, a in ipairs(args) do
                        pcall(function()
                            if typeof(a) == "Instance" then
                                argStr = argStr .. "Instance(" .. a:GetFullName() .. ") "
                            else
                                argStr = argStr .. tostring(a) .. " "
                            end
                        end)
                    end
                    -- سجل traffic حقيقي
                    for _, r in ipairs(SCAN.all_remotes) do
                        if r.name == name then
                            r.traffic = r.traffic or {}
                            table.insert(r.traffic, {
                                time = os.time(),
                                args = argStr
                            })
                            break
                        end
                    end
                end)
            end)

        -- ── RemoteFunction ────────────────────
        elseif class == "RemoteFunction" then
            SCAN.stats.total_remotes += 1
            local entry = {name=name, path=obj:GetFullName()}
            table.insert(SCAN.all_functions, entry)
            if nameLow:find("buy") or nameLow:find("shop") or nameLow:find("purchase") then
                table.insert(SCAN.ai.shop_remotes, entry)
            end

        -- ── Scripts ──────────────────────────
        elseif class == "LocalScript" or class == "Script" or class == "ModuleScript" then
            SCAN.stats.total_scripts += 1
            table.insert(SCAN.all_scripts, {
                name  = name,
                class = class,
                path  = obj:GetFullName(),
                parent= tostring(obj.Parent and obj.Parent.Name or "?"),
                disabled = (pcall(function() return obj.Disabled end) and obj.Disabled) or false
            })

        -- ── GUIs ─────────────────────────────
        elseif class == "ScreenGui" or class == "BillboardGui" or class == "SurfaceGui" then
            SCAN.stats.total_guis += 1
            local visible = false
            pcall(function()
                if obj:IsA("BaseGui") then visible = obj.Enabled end
            end)
            local entry = {name=name, class=class, path=obj:GetFullName(), visible=visible}
            table.insert(SCAN.all_guis, entry)
            if nameLow:find("shop") or nameLow:find("store") or nameLow:find("buy") then
                table.insert(SCAN.ai.shop_remotes, {name=name.."[GUI]", path=obj:GetFullName()})
            end

        -- ── Egg / Pet Objects ─────────────────
        elseif (nameLow:find("egg") or nameLow:find("hatch")) and
               (class == "Model" or class == "Part" or class == "MeshPart") then
            local pos = "?"
            pcall(function()
                if obj:IsA("BasePart") then
                    pos = tostring(math.floor(obj.Position.X)) .. "," ..
                          tostring(math.floor(obj.Position.Y)) .. "," ..
                          tostring(math.floor(obj.Position.Z))
                elseif obj:IsA("Model") and obj.PrimaryPart then
                    pos = tostring(math.floor(obj.PrimaryPart.Position.X)) .. "," ..
                          tostring(math.floor(obj.PrimaryPart.Position.Y)) .. "," ..
                          tostring(math.floor(obj.PrimaryPart.Position.Z))
                end
            end)
            table.insert(SCAN.ai.egg_objects, {name=name, class=class, path=obj:GetFullName(), pos=pos})

        elseif nameLow:find("pet") and (class == "Model" or class == "Folder") then
            table.insert(SCAN.ai.pet_objects, {name=name, class=class, path=obj:GetFullName()})

        -- ── Checkpoints ───────────────────────
        elseif (nameLow:find("checkpoint") or nameLow:find("spawn") or nameLow:find("stage"))
               and obj:IsA("BasePart") then
            local pos = "?"
            pcall(function()
                pos = tostring(math.floor(obj.Position.X)) .. "," ..
                      tostring(math.floor(obj.Position.Y)) .. "," ..
                      tostring(math.floor(obj.Position.Z))
            end)
            table.insert(SCAN.ai.checkpoint_list, {name=name, path=obj:GetFullName(), pos=pos})
        end

        -- تسجيل workspace tree (أول مستويين فقط)
        if depth <= 2 and treePath:find("^Workspace") then
            local treeEntry = {
                name     = name,
                class    = class,
                children = 0,
                scripts  = 0
            }
            pcall(function()
                treeEntry.children = #obj:GetChildren()
                for _, d in ipairs(obj:GetDescendants()) do
                    if d:IsA("Script") or d:IsA("LocalScript") then
                        treeEntry.scripts += 1
                    end
                end
            end)
            table.insert(SCAN.workspace_tree, treeEntry)
        end

        -- تعمق
        wait() -- yield حقيقي كل instance
        realScan(obj, depth + 1, path)
    end
end

-- ══════════════════════════════════════
-- مسح بيانات اللاعب الحقيقية
-- ══════════════════════════════════════
local function scanPlayerData()
    -- Leaderstats
    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            local val = "?"
            pcall(function() val = tostring(v.Value) end)
            table.insert(SCAN.player_stats, {
                source = "leaderstats",
                name   = v.Name,
                class  = v.ClassName,
                value  = val
            })
            -- AI: أول قيمة رقمية = عملة
            if (v.ClassName == "IntValue" or v.ClassName == "NumberValue") and
               SCAN.ai.currency_name == "غير معروف" then
                SCAN.ai.currency_name = v.Name
            end
        end
    end

    -- كل children اللاعب
    for _, child in ipairs(LP:GetChildren()) do
        if child.Name ~= "leaderstats" then
            local vals = {}
            pcall(function()
                for _, v in ipairs(child:GetChildren()) do
                    local val = "?"
                    pcall(function() val = tostring(v.Value) end)
                    table.insert(vals, {name=v.Name, value=val})
                end
            end)
            if #vals > 0 then
                table.insert(SCAN.player_stats, {
                    source = child.Name,
                    class  = child.ClassName,
                    values = vals
                })
            end
        end
    end
end

-- ══════════════════════════════════════
-- AI BRAIN — يحلل النتائج الحقيقية
-- ══════════════════════════════════════
local function runAI()
    local ai = SCAN.ai

    -- نوع الماب
    local wsNames = ""
    for _, t in ipairs(SCAN.workspace_tree) do
        wsNames = wsNames .. t.name:lower() .. " "
    end
    if wsNames:find("climb") or wsNames:find("obby") or wsNames:find("tower") then
        ai.map_type = "obby/climbing"
    elseif wsNames:find("tycoon") then
        ai.map_type = "tycoon"
    elseif wsNames:find("simulator") or wsNames:find("sim") then
        ai.map_type = "simulator"
    else
        ai.map_type = "unknown - يحتاج مزيد من البيانات"
    end

    -- تحليل نظام الشراء
    if #ai.shop_remotes > 0 then
        ai.purchase_flow = "remotes موجودة: "
        for _, r in ipairs(ai.shop_remotes) do
            ai.purchase_flow = ai.purchase_flow .. r.name .. " | "
        end
    else
        ai.purchase_flow = "لا توجد shop remotes واضحة — قد يكون الشراء عبر MarketplaceService مباشرة"
    end

    -- ملاحظات AI
    if #ai.anticheat_found > 0 then
        table.insert(ai.notes, "⚠️ AntiCheat مكتشف: " .. #ai.anticheat_found .. " objects")
    else
        table.insert(ai.notes, "✅ لم يُكتشف AntiCheat واضح")
    end

    if #ai.egg_objects > 0 then
        table.insert(ai.notes, "🥚 بيضات حقيقية في الماب: " .. #ai.egg_objects)
    end

    if #ai.checkpoint_list > 0 then
        table.insert(ai.notes, "🏁 Checkpoints: " .. #ai.checkpoint_list)
    end

    if SCAN.stats.total_remotes == 0 then
        table.insert(ai.notes, "⚠️ صفر remotes — السكربت ربما شغل مبكراً أو الماب يستخدم BindableEvents")
    end

    table.insert(ai.notes, "📊 إجمالي instances: " .. SCAN.stats.total_instances)
    table.insert(ai.notes, "📡 إجمالي remotes: " .. SCAN.stats.total_remotes)
    table.insert(ai.notes, "📜 إجمالي scripts: " .. SCAN.stats.total_scripts)
end

-- ══════════════════════════════════════
-- حفظ النتيجة
-- ══════════════════════════════════════
local function saveResult()
    local ok, json = pcall(function()
        return HttpService:JSONEncode(SCAN)
    end)
    if not ok then
        json = '{"error":"JSON encode failed","game":"' .. SCAN.game_name .. '","remotes":' .. #SCAN.all_remotes .. '}'
    end

    local filename = "SCAN_" .. game.PlaceId .. "_" .. os.time() .. ".json"
    local saved = false

    if writefile then
        pcall(function() writefile(filename, json); saved = true end)
    end

    -- إذا فشل writefile — اطبع في console
    if not saved then
        print("[SCANNER] writefile غير متاح — النتيجة في console:")
        print(json:sub(1, 2000))
    end

    return saved, filename
end

-- ══════════════════════════════════════
-- MAIN EXECUTION
-- ══════════════════════════════════════

print("[SCANNER] ══ بدأ المسح الحقيقي ══")
print("[SCANNER] مسح ReplicatedStorage...")
realScan(ReplicatedStorage, 0, "ReplicatedStorage")

print("[SCANNER] مسح Workspace...")
realScan(workspace, 0, "Workspace")

print("[SCANNER] مسح PlayerGui...")
pcall(function()
    realScan(LP:WaitForChild("PlayerGui", 5), 0, "PlayerGui")
end)

print("[SCANNER] مسح بيانات اللاعب...")
scanPlayerData()

-- انتظر traffic حقيقي من السيرفر
print("[SCANNER] استماع للـ traffic لمدة 20 ثانية...")
wait(20)

print("[SCANNER] تشغيل AI...")
runAI()

-- حفظ
print("[SCANNER] حفظ النتيجة...")
local saved, fname = saveResult()

-- ══ النتيجة النهائية ══
print("")
print("╔══════════════════════════════════╗")
print("║       اكتمل المسح ✅              ║")
print("╠══════════════════════════════════╣")
print("║ الماب:    " .. SCAN.game_name)
print("║ PlaceId:  " .. SCAN.place_id)
print("║ Remotes:  " .. #SCAN.all_remotes)
print("║ Scripts:  " .. #SCAN.all_scripts)
print("║ Eggs:     " .. #SCAN.ai.egg_objects)
print("║ Shop:     " .. #SCAN.ai.shop_remotes)
print("║ AntiAC:   " .. #SCAN.ai.anticheat_found)
print("║ Currency: " .. SCAN.ai.currency_name)
print("║ MapType:  " .. SCAN.ai.map_type)
print("╠══════════════════════════════════╣")
for _, note in ipairs(SCAN.ai.notes) do
    print("║ " .. note)
end
print("╠══════════════════════════════════╣")
if saved then
    print("║ 💾 الملف: " .. fname)
else
    print("║ ⚠️ لم يُحفظ — انسخ من console")
end
print("╚══════════════════════════════════╝")

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title    = "اكتمل المسح ✅",
        Text     = SCAN.game_name .. " | " .. #SCAN.all_remotes .. " remotes",
        Duration = 10
    })
end)