--[[
    ╔══════════════════════════════════════════════════════╗
    ║  STEALTH MAP ANALYZER v2.0                          ║
    ║  Delta Mobile | Pure Analysis | Anti-Detection      ║
    ║  يحلل فقط — لا يعدل، لا يشتري، لا يكشف نفسه      ║
    ╚══════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════
-- STEALTH LAYER — يجب أن يكون أول شيء
-- ═══════════════════════════════════════════

local StealthMode = {}

-- إخفاء السكربت من قائمة السكربتات
pcall(function()
    local syn = syn or {}
    if syn.protect_gui then
        -- لا شيء نحميه هنا بعد
    end
end)

-- منع الـ remote logging من كشفنا
-- نحن نستمع فقط — لا نرسل أي شيء للسيرفر
StealthMode.FireServerBlocked = false -- نحن لا نحظر، فقط نراقب

-- Randomize script identity
local SCRIPT_ID = tostring(math.random(100000, 999999))

-- تأخير عشوائي قبل البدء (يخفي توقيت التنفيذ)
local function stealthWait(min, max)
    wait(min + math.random() * (max - min))
end

stealthWait(0.5, 1.5)

-- ═══════════════════════════════════════════
-- SERVICES — بشكل طبيعي جداً
-- ═══════════════════════════════════════════

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local RunService         = game:GetService("RunService")
local CoreGui            = game:GetService("CoreGui")
local StarterGui         = game:GetService("StarterGui")
local HttpService        = game:GetService("HttpService")

local LP   = Players.LocalPlayer
local Char = LP.Character or LP.CharacterAdded:Wait()

-- ═══════════════════════════════════════════
-- PASSIVE REMOTE LISTENER
-- يستمع للريموتس دون إرسال أي شيء
-- ═══════════════════════════════════════════

local RemoteTraffic = {}
RemoteTraffic.Log = {}
RemoteTraffic.Connections = {}

-- Hook incoming events passively
-- نستخدم OnClientEvent فقط — لا FireServer
function RemoteTraffic:ListenToRemote(remoteObj)
    local conn = remoteObj.OnClientEvent:Connect(function(...)
        local args = {...}
        local entry = {
            Remote    = remoteObj:GetFullName(),
            Name      = remoteObj.Name,
            Args      = {},
            Timestamp = tick()
        }
        -- تحويل الـ args لـ strings بشكل آمن
        for i, arg in ipairs(args) do
            local ok, str = pcall(function()
                if type(arg) == "table" then
                    return HttpService:JSONEncode(arg)
                elseif typeof(arg) == "Instance" then
                    return "Instance:" .. arg:GetFullName()
                elseif typeof(arg) == "Vector3" then
                    return "V3:" .. tostring(arg)
                elseif typeof(arg) == "CFrame" then
                    return "CF:" .. tostring(arg)
                else
                    return tostring(arg)
                end
            end)
            entry.Args[i] = ok and str or "unparseable"
        end
        table.insert(RemoteTraffic.Log, entry)
    end)
    table.insert(RemoteTraffic.Connections, conn)
end

-- ═══════════════════════════════════════════
-- MAIN ANALYZER
-- ═══════════════════════════════════════════

local Analyzer = {}
Analyzer.Data = {
    meta           = {},
    game_info      = {},
    map_structure  = {},
    remote_events  = {},
    remote_functions = {},
    egg_system     = {},
    pet_system     = {},
    shop_system    = {},
    currency_system= {},
    checkpoints    = {},
    gui_elements   = {},
    player_data    = {},
    anticheat      = {},
    lighting_fx    = {},
    remote_traffic = {},
    raw_instance_tree = {}
}

-- Pattern banks
local PATTERNS = {
    egg        = {"egg","Egg","EGG","hatch","Hatch","HATCH","incubate"},
    pet        = {"pet","Pet","PET","animal","Animal","creature"},
    shop       = {"shop","Shop","store","Store","buy","Buy","market","Market","purchase","Purchase"},
    currency   = {"coin","Coin","gem","Gem","token","Token","cash","Cash","robux","bucks","Buck"},
    checkpoint = {"checkpoint","Checkpoint","CheckPoint","cp","CP","stage","Stage","section","Section","spawn","Spawn","respawn"},
    rebirth    = {"rebirth","Rebirth","prestige","Prestige","ascend","Ascend"},
    anticheat  = {"anticheat","AntiCheat","Anti_Cheat","anti_cheat","security","Security","kick","Kick","detect","Detect","cheat","Cheat","ban","Ban"},
    teleport   = {"teleport","Teleport","tp","warp","Warp"},
    data       = {"data","Data","save","Save","load","Load","profile","Profile"},
    event      = {"event","Event","trigger","Trigger","activate","Activate"}
}

function Analyzer:Match(name, category)
    local pats = PATTERNS[category] or {}
    for _, p in ipairs(pats) do
        if string.find(tostring(name), p, 1, true) then
            return true
        end
    end
    return false
end

function Analyzer:Log(msg)
    -- Silent log — لا يظهر في output لتجنب الكشف
    -- نخزن فقط
end

-- ───────────────────────────────────────────
-- GAME INFO
-- ───────────────────────────────────────────
function Analyzer:CollectGameInfo()
    Analyzer.Data.game_info = {
        name          = game.Name,
        place_id      = game.PlaceId,
        universe_id   = game.GameId,
        creator_id    = game.CreatorId,
        creator_type  = tostring(game.CreatorType),
        job_id        = game.JobId,
        private_server= game.PrivateServerId ~= "",
        players_in_server = #Players:GetPlayers(),
        max_players   = LP.ParentEnabled and "N/A" or "N/A",
        roblox_version= version(),
        client_os     = tostring(UserSettings().GameSettings.SavedQualityLevel)
    }
end

-- ───────────────────────────────────────────
-- DEEP INSTANCE SCANNER
-- يمسح كل شيء بشكل سلبي
-- ───────────────────────────────────────────
function Analyzer:DeepScan(parent, depth, path)
    if depth > 7 then return end

    local ok, children = pcall(function() return parent:GetChildren() end)
    if not ok then return end

    for _, child in ipairs(children) do
        local name  = child.Name
        local class = child.ClassName
        local cpath = (path or "") .. "/" .. name

        -- Remotes
        if class == "RemoteEvent" then
            local entry = {
                name     = name,
                path     = child:GetFullName(),
                categories = {},
                depth    = depth
            }
            for cat, _ in pairs(PATTERNS) do
                if Analyzer:Match(name, cat) then
                    table.insert(entry.categories, cat)
                end
            end
            table.insert(Analyzer.Data.remote_events, entry)

            -- Passive listening — فقط نستمع
            stealthWait(0, 0.05)
            RemoteTraffic:ListenToRemote(child)

        elseif class == "RemoteFunction" then
            local entry = {
                name       = name,
                path       = child:GetFullName(),
                categories = {},
                depth      = depth
            }
            for cat, _ in pairs(PATTERNS) do
                if Analyzer:Match(name, cat) then
                    table.insert(entry.categories, cat)
                end
            end
            table.insert(Analyzer.Data.remote_functions, entry)

        -- Egg objects
        elseif Analyzer:Match(name, "egg") then
            local pos = "N/A"
            pcall(function()
                if child:IsA("BasePart") then
                    pos = tostring(child.Position)
                elseif child:IsA("Model") then
                    local p = child:GetPrimaryPartCFrame()
                    pos = tostring(p.Position)
                end
            end)
            table.insert(Analyzer.Data.egg_system, {
                name     = name,
                class    = class,
                path     = child:GetFullName(),
                position = pos,
                depth    = depth,
                children = #child:GetChildren()
            })

        -- Pet objects
        elseif Analyzer:Match(name, "pet") then
            table.insert(Analyzer.Data.pet_system, {
                name  = name,
                class = class,
                path  = child:GetFullName(),
                depth = depth
            })

        -- Shop/GUI elements
        elseif Analyzer:Match(name, "shop") or class == "ScreenGui" or class == "BillboardGui" then
            local entry = {
                name  = name,
                class = class,
                path  = child:GetFullName(),
                depth = depth,
                visible = nil
            }
            pcall(function()
                if child:IsA("BaseGui") then
                    entry.visible = child.Enabled
                end
            end)
            table.insert(Analyzer.Data.gui_elements, entry)

        -- Checkpoints
        elseif Analyzer:Match(name, "checkpoint") and child:IsA("BasePart") then
            local pos = "N/A"
            pcall(function() pos = tostring(child.Position) end)
            table.insert(Analyzer.Data.checkpoints, {
                name     = name,
                path     = child:GetFullName(),
                position = pos,
                size     = tostring(child.Size),
                depth    = depth
            })

        -- AntiCheat detection
        elseif Analyzer:Match(name, "anticheat") then
            local entry = {
                name  = name,
                class = class,
                path  = child:GetFullName(),
                depth = depth,
                scripts_inside = 0
            }
            pcall(function()
                for _, v in ipairs(child:GetDescendants()) do
                    if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("ModuleScript") then
                        entry.scripts_inside = entry.scripts_inside + 1
                    end
                end
            end)
            table.insert(Analyzer.Data.anticheat, entry)
        end

        -- Recurse
        stealthWait(0, 0.02)
        Analyzer:DeepScan(child, depth + 1, cpath)
    end
end

-- ───────────────────────────────────────────
-- PLAYER DATA SCAN
-- ───────────────────────────────────────────
function Analyzer:ScanPlayerData()
    -- Leaderstats
    local ls = LP:FindFirstChild("leaderstats")
    if ls then
        local stats = {}
        for _, v in ipairs(ls:GetChildren()) do
            local val = "N/A"
            pcall(function() val = tostring(v.Value) end)
            table.insert(stats, {name = v.Name, class = v.ClassName, value = val})
        end
        Analyzer.Data.currency_system.leaderstats = stats
    end

    -- All player children
    local playerChildren = {}
    for _, child in ipairs(LP:GetChildren()) do
        local entry = {
            name  = child.Name,
            class = child.ClassName,
            children_count = 0
        }
        pcall(function() entry.children_count = #child:GetChildren() end)

        -- Data folders
        if Analyzer:Match(child.Name, "data") or Analyzer:Match(child.Name, "currency") then
            entry.values = {}
            pcall(function()
                for _, v in ipairs(child:GetChildren()) do
                    local val = "N/A"
                    pcall(function() val = tostring(v.Value) end)
                    table.insert(entry.values, {name = v.Name, class = v.ClassName, value = val})
                end
            end)
        end

        table.insert(playerChildren, entry)
    end
    Analyzer.Data.player_data.all_folders = playerChildren
end

-- ───────────────────────────────────────────
-- MAP STRUCTURE SCAN
-- ───────────────────────────────────────────
function Analyzer:ScanMapStructure()
    -- Workspace top-level map
    local structure = {}
    local ok, wsChildren = pcall(function() return Workspace:GetChildren() end)
    if not ok then return end

    for _, child in ipairs(wsChildren) do
        local entry = {
            name           = child.Name,
            class          = child.ClassName,
            children_count = 0,
            scripts_inside = 0,
            has_remote     = false
        }

        pcall(function()
            entry.children_count = #child:GetChildren()
            local desc = child:GetDescendants()
            for _, d in ipairs(desc) do
                if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") then
                    entry.scripts_inside = entry.scripts_inside + 1
                end
                if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                    entry.has_remote = true
                end
            end
        end)

        table.insert(structure, entry)
    end

    Analyzer.Data.map_structure.workspace_top = structure

    -- ReplicatedStorage top-level
    local rsStructure = {}
    local ok2, rsChildren = pcall(function() return ReplicatedStorage:GetChildren() end)
    if ok2 then
        for _, child in ipairs(rsChildren) do
            table.insert(rsStructure, {
                name           = child.Name,
                class          = child.ClassName,
                children_count = pcall(function() return #child:GetChildren() end) and #child:GetChildren() or 0
            })
        end
    end
    Analyzer.Data.map_structure.replicated_storage_top = rsStructure
end

-- ───────────────────────────────────────────
-- TRAFFIC CAPTURE (30 seconds passive)
-- ───────────────────────────────────────────
function Analyzer:CaptureTraffic(duration)
    -- ننتظر بشكل سلبي ونجمع traffic
    local startTime = tick()
    while tick() - startTime < duration do
        wait(1)
        -- نضيف progress للـ GUI
        if Analyzer.ProgressCallback then
            local elapsed = tick() - startTime
            Analyzer.ProgressCallback(elapsed, duration)
        end
    end
    Analyzer.Data.remote_traffic = RemoteTraffic.Log
end

-- ═══════════════════════════════════════════
-- SAVE TO FILE
-- ═══════════════════════════════════════════

function Analyzer:SaveToFile()
    -- Prepare final data
    Analyzer.Data.meta = {
        analyzer_version = "2.0_stealth",
        timestamp        = os.time(),
        game_name        = game.Name,
        place_id         = game.PlaceId,
        analysis_notes   = {
            "هذا ملف تحليل فقط — لا يحتوي على bypass",
            "الـ remote traffic مجمع من server->client فقط",
            "أرسل هذا الملف لبناء السكربت النهائي"
        }
    }

    -- Summary
    Analyzer.Data.summary = {
        total_remote_events   = #Analyzer.Data.remote_events,
        total_remote_functions= #Analyzer.Data.remote_functions,
        total_eggs_found      = #Analyzer.Data.egg_system,
        total_pets_found      = #Analyzer.Data.pet_system,
        total_shop_guis       = #Analyzer.Data.gui_elements,
        total_checkpoints     = #Analyzer.Data.checkpoints,
        anticheat_detected    = #Analyzer.Data.anticheat > 0,
        anticheat_count       = #Analyzer.Data.anticheat,
        traffic_entries       = #Analyzer.Data.remote_traffic,
        currency_detected     = Analyzer.Data.currency_system.leaderstats ~= nil
    }

    -- Convert to JSON
    local ok, jsonStr = pcall(function()
        return HttpService:JSONEncode(Analyzer.Data)
    end)

    if not ok then
        -- Fallback: simple format
        jsonStr = "JSON encode failed. Raw data:\n"
        jsonStr = jsonStr .. "Game: " .. game.Name .. "\n"
        jsonStr = jsonStr .. "Remotes: " .. #Analyzer.Data.remote_events .. "\n"
        jsonStr = jsonStr .. "Eggs: " .. #Analyzer.Data.egg_system .. "\n"
    end

    -- File name with timestamp
    local filename = "map_analysis_" .. game.PlaceId .. "_" .. os.time() .. ".json"

    -- Save using writefile (Delta/Synapse/Fluxus compatible)
    local saved = false

    -- Method 1: writefile (most executors)
    if writefile then
        pcall(function()
            writefile(filename, jsonStr)
            saved = true
        end)
    end

    -- Method 2: saveinstance fallback
    if not saved and syn and syn.write_file then
        pcall(function()
            syn.write_file(filename, jsonStr)
            saved = true
        end)
    end

    return saved, filename, jsonStr
end

-- ═══════════════════════════════════════════
-- MINIMAL STEALTH GUI
-- صغيرة وغير لافتة
-- ═══════════════════════════════════════════

local function buildGUI()
    pcall(function()
        if CoreGui:FindFirstChild("SA_" .. SCRIPT_ID) then
            CoreGui:FindFirstChild("SA_" .. SCRIPT_ID):Destroy()
        end
    end)

    local screen = Instance.new("ScreenGui")
    screen.Name = "SA_" .. SCRIPT_ID
    screen.ResetOnSpawn = false
    screen.DisplayOrder = 999
    screen.Parent = CoreGui

    -- نافذة صغيرة في الركن
    local main = Instance.new("Frame")
    main.Size = UDim2.new(0, 200, 0, 280)
    main.Position = UDim2.new(0, 8, 0.6, 0)
    main.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
    main.BackgroundTransparency = 0.2
    main.BorderSizePixel = 0
    main.Parent = screen
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

    -- بار صغير للسحب
    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 24)
    bar.BackgroundColor3 = Color3.fromRGB(20, 80, 180)
    bar.BorderSizePixel = 0
    bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 6)

    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(1, -30, 1, 0)
    titleLbl.Position = UDim2.new(0, 6, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = "🔍 Analyzer"
    titleLbl.TextColor3 = Color3.new(1,1,1)
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.TextScaled = true
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = bar

    -- زر إغلاق
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 24, 0, 24)
    closeBtn.Position = UDim2.new(1, -24, 0, 0)
    closeBtn.BackgroundTransparency = 1
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.new(1,1,1)
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextScaled = true
    closeBtn.Parent = bar
    closeBtn.MouseButton1Click:Connect(function() screen:Destroy() end)

    -- Status labels
    local labels = {}
    local function addStatus(text, color)
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -8, 0, 18)
        lbl.Position = UDim2.new(0, 4, 0, 28 + #labels * 20)
        lbl.BackgroundTransparency = 1
        lbl.Text = text
        lbl.TextColor3 = color or Color3.fromRGB(200, 200, 200)
        lbl.Font = Enum.Font.Gotham
        lbl.TextScaled = true
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = main
        table.insert(labels, lbl)
        return lbl
    end

    local statusMain  = addStatus("⏳ جاري المسح...", Color3.fromRGB(255, 220, 50))
    local statusRemote= addStatus("📡 Remotes: -", Color3.fromRGB(150, 200, 255))
    local statusEgg   = addStatus("🥚 Eggs: -", Color3.fromRGB(255, 200, 100))
    local statusCp    = addStatus("🏁 Checkpoints: -", Color3.fromRGB(100, 255, 150))
    local statusAC    = addStatus("🛡️ AntiCheat: -", Color3.fromRGB(255, 150, 100))
    local statusTraffic = addStatus("📶 Traffic: 0 entries", Color3.fromRGB(200, 150, 255))
    local statusTimer = addStatus("⏱️ Traffic: 30s", Color3.fromRGB(150, 150, 255))

    -- Progress bar
    local progressBG = Instance.new("Frame")
    progressBG.Size = UDim2.new(1, -8, 0, 8)
    progressBG.Position = UDim2.new(0, 4, 0, 222)
    progressBG.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    progressBG.BorderSizePixel = 0
    progressBG.Parent = main
    Instance.new("UICorner", progressBG).CornerRadius = UDim.new(0, 4)

    local progressBar = Instance.new("Frame")
    progressBar.Size = UDim2.new(0, 0, 1, 0)
    progressBar.BackgroundColor3 = Color3.fromRGB(20, 150, 255)
    progressBar.BorderSizePixel = 0
    progressBar.Parent = progressBG
    Instance.new("UICorner", progressBar).CornerRadius = UDim.new(0, 4)

    -- Save button
    local saveBtn = Instance.new("TextButton")
    saveBtn.Size = UDim2.new(1, -8, 0, 30)
    saveBtn.Position = UDim2.new(0, 4, 0, 238)
    saveBtn.BackgroundColor3 = Color3.fromRGB(20, 140, 60)
    saveBtn.Text = "💾 حفظ الملف"
    saveBtn.TextColor3 = Color3.new(1,1,1)
    saveBtn.Font = Enum.Font.GothamBold
    saveBtn.TextScaled = true
    saveBtn.BorderSizePixel = 0
    saveBtn.Active = false
    saveBtn.Parent = main
    Instance.new("UICorner", saveBtn).CornerRadius = UDim.new(0, 6)

    -- Draggable
    local dragging, dragStart, startPos = false
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = i.Position
            startPos  = main.Position
        end
    end)
    game:GetService("UserInputService").InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.Touch then
            local d = i.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                      startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    game:GetService("UserInputService").InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)

    -- Update callbacks
    Analyzer.ProgressCallback = function(elapsed, total)
        local pct = math.min(elapsed / total, 1)
        progressBar.Size = UDim2.new(pct, 0, 1, 0)
        statusTimer.Text = "⏱️ Traffic: " .. math.floor(total - elapsed) .. "s"
        statusTraffic.Text = "📶 Traffic: " .. #RemoteTraffic.Log .. " entries"
    end

    Analyzer.UpdateStats = function()
        statusRemote.Text  = "📡 Remotes: " .. #Analyzer.Data.remote_events
        statusEgg.Text     = "🥚 Eggs: " .. #Analyzer.Data.egg_system
        statusCp.Text      = "🏁 Checkpoints: " .. #Analyzer.Data.checkpoints
        statusAC.Text      = "🛡️ AntiCheat: " .. (#Analyzer.Data.anticheat > 0 and "⚠️ " .. #Analyzer.Data.anticheat or "✅ None")
        statusMain.Text    = "✅ مسح اكتمل"
        statusMain.TextColor3 = Color3.fromRGB(100, 255, 150)
        saveBtn.Active = true
        saveBtn.BackgroundColor3 = Color3.fromRGB(20, 200, 80)
    end

    saveBtn.MouseButton1Click:Connect(function()
        saveBtn.Text = "⏳ جاري الحفظ..."
        saveBtn.BackgroundColor3 = Color3.fromRGB(180, 120, 0)

        local saved, filename, _ = Analyzer:SaveToFile()

        if saved then
            saveBtn.Text = "✅ " .. filename
            saveBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 60)
            saveBtn.TextScaled = true

            pcall(function()
                StarterGui:SetCore("SendNotification", {
                    Title    = "تم الحفظ ✅",
                    Text     = "الملف: " .. filename,
                    Duration = 8
                })
            end)
        else
            saveBtn.Text = "❌ فشل الحفظ"
            saveBtn.BackgroundColor3 = Color3.fromRGB(180, 30, 30)
        end
    end)
end

-- ═══════════════════════════════════════════
-- MAIN RUN — STEALTH SEQUENCE
-- ═══════════════════════════════════════════

coroutine.wrap(function()
    -- بناء الـ GUI أولاً
    buildGUI()

    -- تأخير قصير قبل المسح
    stealthWait(1, 2)

    -- المسح
    Analyzer:CollectGameInfo()
    Analyzer:ScanMapStructure()

    -- المسح العميق بشكل سلبي — بخطوات صغيرة
    Analyzer:DeepScan(ReplicatedStorage, 0, "ReplicatedStorage")
    stealthWait(0.3, 0.7)
    Analyzer:DeepScan(Workspace, 0, "Workspace")
    stealthWait(0.3, 0.5)

    -- فحص غير مباشر لـ PlayerGui
    pcall(function()
        Analyzer:DeepScan(LP:WaitForChild("PlayerGui", 5), 0, "PlayerGui")
    end)

    Analyzer:ScanPlayerData()

    -- تحديث الـ GUI
    if Analyzer.UpdateStats then
        Analyzer.UpdateStats()
    end

    -- جمع traffic لمدة 45 ثانية
    Analyzer:CaptureTraffic(45)

    -- حفظ تلقائي بعد الانتهاء
    local saved, filename, _ = Analyzer:SaveToFile()

    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = saved and "✅ تحليل اكتمل" or "⚠️ اكتمل",
            Text     = saved and ("الملف: " .. filename) or "افتح الـ GUI واحفظ يدوياً",
            Duration = 10
        })
    end)
end)()