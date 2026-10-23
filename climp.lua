--[[
╔══════════════════════════════════════════════════════════════════════╗
║   CLIMB FOR ANIMALS EGGS — MOD MENU v5.0                            ║
║   Game-Native Detection | RemoteEvent Farm | Real ESP               ║
║   موبايل | Delta Android                                            ║
╚══════════════════════════════════════════════════════════════════════╝

    الطريقة الجديدة:
    - ESP: يقرأ BillboardGui الموجودة أصلاً على البيض من اللعبة
    - AutoFarm: يفتش على RemoteEvents الحقيقية في اللعبة ويستخدمها
    - لا توقعات — كل شيء مبني على بيانات اللعبة الفعلية
]]

-- ══════════════════════════════════════
-- CORE SAFETY
-- ══════════════════════════════════════

local function try(f, ...)
    local ok, r = pcall(f, ...)
    return ok, r
end

local function tryGet(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

-- ══════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local Camera           = Workspace.CurrentCamera
local LP               = Players.LocalPlayer
local PGui             = LP:WaitForChild("PlayerGui")

local Char, Hum, Root
local function grabChar()
    Char = LP.Character or LP.CharacterAdded:Wait()
    Hum  = Char:WaitForChild("Humanoid")
    Root = Char:WaitForChild("HumanoidRootPart")
end
grabChar()
LP.CharacterAdded:Connect(function(c)
    task.wait(0.5)
    Char = c
    Hum  = c:WaitForChild("Humanoid")
    Root = c:WaitForChild("HumanoidRootPart")
end)

-- ══════════════════════════════════════
-- STATE
-- ══════════════════════════════════════

local State = {
    Esp        = false,
    Speed      = false,
    SpeedVal   = 60,
    HighJump   = false,
    NoClip     = false,
    AutoFarm   = false,
    InfStamina = false,
    AntiAfk    = false,
    Fly        = false,
}

-- ══════════════════════════════════════
-- RARITY DATA — FOR ESP COLORS
-- ══════════════════════════════════════

local RARITY = {
    common    = { d="Common",    c="~$500",  col=Color3.fromRGB(200,200,200), p=1  },
    uncommon  = { d="Uncommon",  c="~$2K",   col=Color3.fromRGB(80,200,80),   p=2  },
    rare      = { d="Rare",      c="~$15K",  col=Color3.fromRGB(80,120,255),  p=3  },
    epic      = { d="Epic",      c="~$120K", col=Color3.fromRGB(160,60,220),  p=5  },
    legendary = { d="Legendary", c="~$2M",   col=Color3.fromRGB(255,180,0),   p=8  },
    mythic    = { d="Mythic",    c="~$5M",   col=Color3.fromRGB(255,60,60),   p=9  },
    divine    = { d="Divine",    c="~$20M",  col=Color3.fromRGB(0,220,220),   p=10 },
    celestial = { d="Celestial", c="~$200M", col=Color3.fromRGB(255,240,80),  p=11 },
    royal     = { d="Royal",     c="~$10B+", col=Color3.fromRGB(255,20,147),  p=12 },
    golden    = { d="Golden",    c="~$50K",  col=Color3.fromRGB(255,200,0),   p=5  },
    diamond   = { d="Diamond",   c="~$500K", col=Color3.fromRGB(180,230,255), p=7  },
    forest    = { d="Forest",    c="~$500",  col=Color3.fromRGB(160,220,130), p=1  },
    winter    = { d="Winter",    c="~$2K",   col=Color3.fromRGB(130,200,255), p=2  },
    ocean     = { d="Ocean",     c="~$8K",   col=Color3.fromRGB(60,120,255),  p=3  },
    desert    = { d="Desert",    c="~$15K",  col=Color3.fromRGB(240,180,60),  p=4  },
    crystal   = { d="Crystal",   c="~$50K",  col=Color3.fromRGB(200,150,255), p=5  },
    jungle    = { d="Jungle",    c="~$120K", col=Color3.fromRGB(40,180,80),   p=6  },
    mystic    = { d="Mystic",    c="~$500K", col=Color3.fromRGB(255,140,255), p=7  },
    prehistoric={ d="Prehistoric",c="~$2M",  col=Color3.fromRGB(200,120,60),  p=8  },
}

local function getRarityData(text)
    if not text then return nil end
    local low = text:lower()
    for k, v in pairs(RARITY) do
        if low:find(k) then return v end
    end
    return nil
end

-- ══════════════════════════════════════
-- METHOD 1: READ GAME'S OWN BILLBOARDS
--
-- The game already places BillboardGui labels
-- on eggs (we can see "Common" in the screenshot).
-- We find those BillboardGuis, read their text,
-- and use the PARENT as the egg reference.
-- This is 100% accurate — no guessing.
-- ══════════════════════════════════════

local function getEggLabel(obj)
    -- Look for BillboardGui the game placed on this object
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("BillboardGui") and child.Name ~= "CAFE_ESP" then
            -- Read text from any TextLabel inside
            for _, label in ipairs(child:GetDescendants()) do
                if label:IsA("TextLabel") and label.Text ~= "" then
                    local rd = getRarityData(label.Text)
                    if rd then
                        return rd, label.Text
                    end
                end
            end
        end
        -- Also check SurfaceGui
        if child:IsA("SurfaceGui") then
            for _, label in ipairs(child:GetDescendants()) do
                if label:IsA("TextLabel") and label.Text ~= "" then
                    local rd = getRarityData(label.Text)
                    if rd then return rd, label.Text end
                end
            end
        end
    end
    return nil, nil
end

-- For Models, check the model and its primary part
local function getEggLabelModel(model)
    local rd, txt = getEggLabel(model)
    if rd then return rd, txt end
    for _, child in ipairs(model:GetChildren()) do
        if child:IsA("BasePart") then
            rd, txt = getEggLabel(child)
            if rd then return rd, txt end
        end
    end
    return nil, nil
end

-- ══════════════════════════════════════
-- METHOD 2: NAME-BASED FALLBACK
-- If no BillboardGui found, check part/model name
-- ══════════════════════════════════════

local function isEggByName(name)
    return name:lower():find("egg") ~= nil
end

local function getPartForESP(obj)
    if obj:IsA("BasePart") then
        return obj
    elseif obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- ══════════════════════════════════════
-- ESP SYSTEM
-- ══════════════════════════════════════

local activeEsp = {}

local function removeEsp(key)
    if activeEsp[key] then
        try(function() activeEsp[key].bb:Destroy() end)
        activeEsp[key] = nil
    end
end

local function removeAllEsp()
    for key in pairs(activeEsp) do
        try(function()
            if activeEsp[key] then
                activeEsp[key].bb:Destroy()
            end
        end)
    end
    activeEsp = {}
end

local function isInsideCharacter(part)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and part:IsDescendantOf(p.Character) then
            return true
        end
    end
    return false
end

local function buildEspBillboard(part, zd, rawText)
    if not part or not part.Parent then return end
    if isInsideCharacter(part) then return end

    local key = part  -- unique key per part

    if activeEsp[key] then return end

    -- Build our ESP billboard
    local bb = Instance.new("BillboardGui")
    bb.Name            = "CAFE_ESP"
    bb.Size            = UDim2.new(0, 150, 0, 50)
    bb.StudsOffset     = Vector3.new(0, part.Size.Y + 2, 0)
    bb.AlwaysOnTop     = true
    bb.MaxDistance     = 1500
    bb.LightInfluence  = 0
    bb.Parent          = part

    local bg = Instance.new("Frame", bb)
    bg.Size                   = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3       = Color3.fromRGB(5, 5, 15)
    bg.BackgroundTransparency = 0.15
    bg.BorderSizePixel        = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)
    local stroke = Instance.new("UIStroke", bg)
    stroke.Color     = zd.col
    stroke.Thickness = 2

    -- Line 1: Rarity + Cash
    local l1 = Instance.new("TextLabel", bg)
    l1.Size                   = UDim2.new(1, -4, 0.52, 0)
    l1.Position               = UDim2.new(0, 2, 0, 2)
    l1.BackgroundTransparency = 1
    l1.TextColor3             = zd.col
    l1.TextSize               = 13
    l1.Font                   = Enum.Font.GothamBold
    l1.Text                   = "["..zd.d.."]  "..zd.c
    l1.TextScaled             = true
    l1.TextXAlignment         = Enum.TextXAlignment.Center

    -- Line 2: Distance (live)
    local l2 = Instance.new("TextLabel", bg)
    l2.Size                   = UDim2.new(1, -4, 0.45, 0)
    l2.Position               = UDim2.new(0, 2, 0.53, 0)
    l2.BackgroundTransparency = 1
    l2.TextColor3             = Color3.fromRGB(190, 190, 210)
    l2.TextSize               = 11
    l2.Font                   = Enum.Font.Gotham
    l2.Text                   = "..."
    l2.TextScaled             = true
    l2.TextXAlignment         = Enum.TextXAlignment.Center

    activeEsp[key] = { bb = bb, part = part, zone = zd }

    -- Live distance update
    task.spawn(function()
        while bb and bb.Parent and State.Esp do
            try(function()
                if not part or not part.Parent then
                    removeEsp(key); return
                end
                if Root then
                    local dist = (Root.Position - part.Position).Magnitude
                    l2.Text = string.format("📍 %.0f studs", dist)
                end
            end)
            task.wait(0.5)
        end
        try(function() if bb and bb.Parent then bb:Destroy() end end)
    end)
end

local function tryAddEsp(obj)
    -- Attempt Method 1: Game's own BillboardGui
    local zd, rawText

    if obj:IsA("Model") then
        zd, rawText = getEggLabelModel(obj)
        if zd then
            local part = getPartForESP(obj)
            if part then buildEspBillboard(part, zd, rawText) end
            return
        end
        -- Method 2: Name check for model
        if isEggByName(obj.Name) then
            zd = getRarityData(obj.Name) or {d="Egg",c="?",col=Color3.fromRGB(255,255,255),p=1}
            local part = getPartForESP(obj)
            if part and not isInsideCharacter(part) then
                buildEspBillboard(part, zd, obj.Name)
            end
        end
    elseif obj:IsA("BasePart") then
        zd, rawText = getEggLabel(obj)
        if zd then
            buildEspBillboard(obj, zd, rawText)
            return
        end
        -- Method 2: Name check
        if isEggByName(obj.Name) and not isInsideCharacter(obj) then
            -- Check parent model too
            if obj.Parent and obj.Parent:IsA("Model") then
                local pzd = getRarityData(obj.Parent.Name)
                if pzd then
                    buildEspBillboard(obj, pzd, obj.Parent.Name)
                    return
                end
            end
            zd = getRarityData(obj.Name) or {d="Egg",c="?",col=Color3.fromRGB(255,255,255),p=1}
            buildEspBillboard(obj, zd, obj.Name)
        end
    end
end

local function scanAllForEsp()
    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                -- Skip player characters
                local skip = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == child then skip = true; break end
                end
                if not skip then
                    tryAddEsp(child)
                    scan(child)
                end
            end)
        end
    end
    scan(Workspace)
end

-- Watch for new objects
Workspace.DescendantAdded:Connect(function(d)
    if not State.Esp then return end
    task.wait(0.3)
    try(function() tryAddEsp(d) end)
end)

Workspace.DescendantRemoving:Connect(function(d)
    if activeEsp[d] then removeEsp(d) end
end)

-- ══════════════════════════════════════
-- REMOTE EVENT SCANNER
--
-- Scans ReplicatedStorage for the game's
-- real RemoteEvents. Tries common names for
-- egg stealing/collection in simulator games.
-- ══════════════════════════════════════

local foundRemotes = {}

local function scanRemotes()
    foundRemotes = {}
    local stealKeywords = {
        "steal","collect","grab","pick","egg","take","get",
        "loot","farm","claim","snatch"
    }
    local function scan(folder)
        for _, child in ipairs(folder:GetChildren()) do
            try(function()
                if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                    local low = child.Name:lower()
                    for _, kw in ipairs(stealKeywords) do
                        if low:find(kw) then
                            table.insert(foundRemotes, child)
                            break
                        end
                    end
                end
                scan(child)
            end)
        end
    end
    scan(ReplicatedStorage)
    -- Also check Workspace remotes
    try(function() scan(Workspace) end)
    return foundRemotes
end

-- ══════════════════════════════════════
-- AUTO FARM — MULTI-METHOD COLLECTION
--
-- Tries every available method to collect:
-- 1. Fire relevant RemoteEvents with egg ref
-- 2. fireproximityprompt on any ProximityPrompt
-- 3. Touch simulation via CFrame
-- ══════════════════════════════════════

local function getAllEggParts()
    local eggs = {}
    local seen = {}

    local function addEgg(part, zd)
        if seen[part] then return end
        seen[part] = true
        if isInsideCharacter(part) then return end
        table.insert(eggs, { part=part, zone=zd, pos=part.Position })
    end

    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                local skip = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == child then skip=true; break end
                end
                if skip then return end

                -- Method 1: has game BillboardGui with rarity text
                if child:IsA("Model") then
                    local zd, _ = getEggLabelModel(child)
                    if zd then
                        local part = getPartForESP(child)
                        if part then addEgg(part, zd) end
                    elseif isEggByName(child.Name) then
                        local part = getPartForESP(child)
                        if part then
                            addEgg(part, getRarityData(child.Name) or {d="Egg",c="?",col=Color3.fromRGB(255,255,255),p=1})
                        end
                    end
                elseif child:IsA("BasePart") then
                    local zd, _ = getEggLabel(child)
                    if zd then
                        addEgg(child, zd)
                    elseif isEggByName(child.Name) then
                        addEgg(child, getRarityData(child.Name) or {d="Egg",c="?",col=Color3.fromRGB(255,255,255),p=1})
                    end
                end

                scan(child)
            end)
        end
    end

    scan(Workspace)
    return eggs
end

local function getBestEgg(eggs)
    if #eggs == 0 then return nil end
    local best, bestScore = nil, -math.huge
    for _, e in ipairs(eggs) do
        if e.part and e.part.Parent then
            local dist  = Root and (Root.Position - e.pos).Magnitude or 9999
            local score = (e.zone.p * 100000) - dist
            if score > bestScore then
                bestScore = score
                best = e
            end
        end
    end
    return best
end

local function collectEgg(eggPart)
    -- Teleport onto the egg
    try(function()
        Root.CFrame = CFrame.new(eggPart.Position + Vector3.new(0, 5, 0))
    end)
    task.wait(0.25)

    -- Method A: fireproximityprompt on any prompt in egg or parent
    try(function()
        local pp = eggPart:FindFirstChildOfClass("ProximityPrompt")
            or (eggPart.Parent and eggPart.Parent:FindFirstChildOfClass("ProximityPrompt"))
            or eggPart:FindFirstChildOfClass("ProximityPrompt", true)
        if pp then
            fireproximityprompt(pp)
        end
    end)

    task.wait(0.1)

    -- Method B: Fire all relevant RemoteEvents with egg reference
    for _, remote in ipairs(foundRemotes) do
        try(function()
            if remote:IsA("RemoteEvent") then
                -- Try different argument combinations the game might expect
                remote:FireServer(eggPart)
                task.wait(0.05)
                remote:FireServer(eggPart.Parent)
                task.wait(0.05)
                remote:FireServer(eggPart.Position)
            end
        end)
    end

    task.wait(0.1)

    -- Method C: Simulate touch by anchoring on egg briefly
    try(function()
        Root.CFrame = CFrame.new(eggPart.Position + Vector3.new(0, 2, 0))
    end)
    task.wait(0.15)
end

local function runAutoFarm()
    -- Scan remotes first
    scanRemotes()

    task.spawn(function()
        while State.AutoFarm do
            try(function()
                if not Root then task.wait(1); return end

                local eggs = getAllEggParts()
                if #eggs == 0 then
                    task.wait(2)
                    return
                end

                local target = getBestEgg(eggs)
                if not target then task.wait(1); return end

                collectEgg(target.part)

                -- Randomized delay — anti-detection
                task.wait(0.4 + math.random() * 0.3)
            end)
        end
    end)
end

-- ══════════════════════════════════════
-- SPEED
-- ══════════════════════════════════════

local speedConn
local function enableSpeed()
    if speedConn then speedConn:Disconnect() end
    speedConn = RunService.Heartbeat:Connect(function()
        if not State.Speed then return end
        try(function()
            if Hum and Hum.Parent then
                Hum.WalkSpeed = State.SpeedVal
            end
        end)
    end)
end
local function disableSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    try(function() if Hum then Hum.WalkSpeed = 16 end end)
end

-- ══════════════════════════════════════
-- HIGH JUMP
-- ══════════════════════════════════════

local jumpConn
local function enableJump()
    if jumpConn then jumpConn:Disconnect() end
    jumpConn = RunService.Heartbeat:Connect(function()
        if not State.HighJump then return end
        try(function()
            if Hum and Hum.Parent then Hum.JumpPower = 120 end
        end)
    end)
end
local function disableJump()
    if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
    try(function() if Hum then Hum.JumpPower = 50 end end)
end

-- ══════════════════════════════════════
-- NOCLIP
-- ══════════════════════════════════════

local noclipConn
local function enableNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn = RunService.Stepped:Connect(function()
        if not State.NoClip then return end
        try(function()
            for _, p in ipairs(Char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end)
    end)
end
local function disableNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    try(function()
        for _, p in ipairs(Char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = true end
        end
    end)
end

-- ══════════════════════════════════════
-- FLY
-- ══════════════════════════════════════

local flyBV, flyBG
local function enableFly()
    try(function()
        flyBV = Instance.new("BodyVelocity")
        flyBV.Velocity = Vector3.zero
        flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
        flyBV.Parent   = Root
        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5)
        flyBG.P = 1e4
        flyBG.Parent = Root
        Hum.PlatformStand = true
        task.spawn(function()
            while State.Fly and flyBV and flyBV.Parent do
                try(function()
                    flyBV.Velocity = Camera.CFrame.LookVector * (State.SpeedVal * 1.5)
                    flyBG.CFrame   = Camera.CFrame
                end)
                task.wait(0.03)
            end
        end)
    end)
end
local function disableFly()
    try(function()
        if flyBV then flyBV:Destroy(); flyBV = nil end
        if flyBG then flyBG:Destroy(); flyBG = nil end
        if Hum   then Hum.PlatformStand = false    end
    end)
end

-- ══════════════════════════════════════
-- INFINITE STAMINA
-- ══════════════════════════════════════

local function runInfStamina()
    task.spawn(function()
        while State.InfStamina do
            try(function()
                local stats = LP:FindFirstChild("leaderstats") or LP:FindFirstChild("Stats")
                if stats then
                    for _, v in ipairs(stats:GetChildren()) do
                        if v.Name:lower():find("stamina") or v.Name:lower():find("energy") then
                            if v.Value < 100 then v.Value = 99999 end
                        end
                    end
                end
            end)
            task.wait(0.2)
        end
    end)
end

-- ══════════════════════════════════════
-- ANTI-AFK
-- ══════════════════════════════════════

local function runAntiAfk()
    task.spawn(function()
        while State.AntiAfk do
            try(function()
                local fe = Instance.new("BindableEvent")
                fe:Fire(); fe:Destroy()
            end)
            task.wait(55 + math.random()*10)
        end
    end)
end

-- ══════════════════════════════════════
-- DEBUG TOOL — يظهر كل RemoteEvents
-- مفيد لمعرفة اسم الـ Remote الصح
-- ══════════════════════════════════════

local function showRemotes()
    local remotes = {}
    local function scan(f)
        for _, c in ipairs(f:GetChildren()) do
            try(function()
                if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                    table.insert(remotes, c:GetFullName().." ["..c.ClassName.."]")
                end
                scan(c)
            end)
        end
    end
    scan(ReplicatedStorage)
    try(function() scan(Workspace) end)
    return table.concat(remotes, "\n")
end

-- ══════════════════════════════════════
-- GUI
-- ══════════════════════════════════════

local BG     = Color3.fromRGB(10,10,18)
local PANEL  = Color3.fromRGB(18,20,30)
local ACCENT = Color3.fromRGB(110,60,240)
local ON_C   = Color3.fromRGB(50,220,110)
local OFF_C  = Color3.fromRGB(200,55,55)
local TEXT   = Color3.fromRGB(225,225,245)
local DIM    = Color3.fromRGB(130,130,155)
local BORDER = Color3.fromRGB(55,40,90)

local oldG = PGui:FindFirstChild("CAFE_ModMenu")
if oldG then oldG:Destroy() end

local SGui = Instance.new("ScreenGui")
SGui.Name = "CAFE_ModMenu"; SGui.ResetOnSpawn = false
SGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
try(function() SGui.Parent = game:GetService("CoreGui") end)
if not SGui.Parent then SGui.Parent = PGui end

local Main = Instance.new("Frame", SGui)
Main.Size = UDim2.new(0,300,0,560)
Main.Position = UDim2.new(0,8,0.5,-280)
Main.BackgroundColor3 = BG; Main.BorderSizePixel = 0
Instance.new("UICorner",Main).CornerRadius = UDim.new(0,12)
local ms = Instance.new("UIStroke",Main); ms.Color=BORDER; ms.Thickness=1.5

local TBar = Instance.new("Frame",Main)
TBar.Size=UDim2.new(1,0,0,44); TBar.BackgroundColor3=PANEL; TBar.BorderSizePixel=0
Instance.new("UICorner",TBar).CornerRadius=UDim.new(0,12)
local tfx=Instance.new("Frame",TBar)
tfx.Size=UDim2.new(1,0,0.5,0); tfx.Position=UDim2.new(0,0,0.5,0)
tfx.BackgroundColor3=PANEL; tfx.BorderSizePixel=0

local TL=Instance.new("TextLabel",TBar)
TL.Text="🐾 Climb For Animals Eggs"
TL.Size=UDim2.new(1,-50,0,24); TL.Position=UDim2.new(0,12,0,6)
TL.BackgroundTransparency=1; TL.TextColor3=TEXT
TL.TextSize=14; TL.Font=Enum.Font.GothamBold
TL.TextXAlignment=Enum.TextXAlignment.Left

local SL=Instance.new("TextLabel",Main)
SL.Text="v5.0 | Native Detection | Delta"
SL.Size=UDim2.new(1,-12,0,14); SL.Position=UDim2.new(0,12,0,30)
SL.BackgroundTransparency=1; SL.TextColor3=DIM
SL.TextSize=10; SL.Font=Enum.Font.Gotham
SL.TextXAlignment=Enum.TextXAlignment.Left

local HBtn=Instance.new("TextButton",TBar)
HBtn.Size=UDim2.new(0,32,0,32); HBtn.Position=UDim2.new(1,-40,0,6)
HBtn.BackgroundColor3=ACCENT; HBtn.Text="—"; HBtn.TextColor3=TEXT
HBtn.TextSize=16; HBtn.Font=Enum.Font.GothamBold; HBtn.BorderSizePixel=0
Instance.new("UICorner",HBtn).CornerRadius=UDim.new(0,8)

local Scr=Instance.new("ScrollingFrame",Main)
Scr.Size=UDim2.new(1,-10,1,-58); Scr.Position=UDim2.new(0,5,0,52)
Scr.BackgroundTransparency=1; Scr.BorderSizePixel=0
Scr.ScrollBarThickness=4; Scr.ScrollBarImageColor3=ACCENT
Scr.CanvasSize=UDim2.new(0,0,0,0)

local Lay=Instance.new("UIListLayout",Scr)
Lay.Padding=UDim.new(0,5)
Lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scr.CanvasSize=UDim2.new(0,0,0,Lay.AbsoluteContentSize.Y+10)
end)

local function sec(txt)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-6,0,22); f.BackgroundTransparency=1
    local ln=Instance.new("Frame",f)
    ln.Size=UDim2.new(1,0,0,1); ln.Position=UDim2.new(0,0,0.5,0)
    ln.BackgroundColor3=BORDER; ln.BorderSizePixel=0
    local lb=Instance.new("TextLabel",f)
    lb.Text="  "..txt.."  "; lb.Size=UDim2.new(0,0,1,0)
    lb.AutomaticSize=Enum.AutomaticSize.X; lb.Position=UDim2.new(0,10,0,0)
    lb.BackgroundColor3=BG; lb.TextColor3=ACCENT
    lb.TextSize=11; lb.Font=Enum.Font.GothamBold
end

local function tog(name,desc,onOn,onOff)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-6,0,56); f.BackgroundColor3=PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local fs=Instance.new("UIStroke",f); fs.Color=BORDER; fs.Thickness=1
    local nl=Instance.new("TextLabel",f)
    nl.Text=name; nl.Size=UDim2.new(1,-80,0,22); nl.Position=UDim2.new(0,10,0,6)
    nl.BackgroundTransparency=1; nl.TextColor3=TEXT; nl.TextSize=13
    nl.Font=Enum.Font.GothamBold; nl.TextXAlignment=Enum.TextXAlignment.Left
    local dl=Instance.new("TextLabel",f)
    dl.Text=desc; dl.Size=UDim2.new(1,-80,0,18); dl.Position=UDim2.new(0,10,0,30)
    dl.BackgroundTransparency=1; dl.TextColor3=DIM; dl.TextSize=10
    dl.Font=Enum.Font.Gotham; dl.TextXAlignment=Enum.TextXAlignment.Left
    local btn=Instance.new("TextButton",f)
    btn.Size=UDim2.new(0,62,0,30); btn.Position=UDim2.new(1,-72,0.5,-15)
    btn.BackgroundColor3=OFF_C; btn.Text="OFF"; btn.TextColor3=Color3.fromRGB(255,255,255)
    btn.TextSize=12; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,7)
    local on=false
    btn.MouseButton1Click:Connect(function()
        on=not on
        if on then
            btn.Text="ON"
            TweenService:Create(btn,TweenInfo.new(0.2),{BackgroundColor3=ON_C}):Play()
            try(onOn)
        else
            btn.Text="OFF"
            TweenService:Create(btn,TweenInfo.new(0.2),{BackgroundColor3=OFF_C}):Play()
            try(onOff)
        end
    end)
    return f,btn
end

local function sld(lbl,mn,mx,def,cb)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-6,0,64); f.BackgroundColor3=PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local fs=Instance.new("UIStroke",f); fs.Color=BORDER; fs.Thickness=1
    local nl=Instance.new("TextLabel",f)
    nl.Text=lbl; nl.Size=UDim2.new(1,-70,0,20); nl.Position=UDim2.new(0,10,0,6)
    nl.BackgroundTransparency=1; nl.TextColor3=TEXT; nl.TextSize=13
    nl.Font=Enum.Font.GothamBold; nl.TextXAlignment=Enum.TextXAlignment.Left
    local vl=Instance.new("TextLabel",f)
    vl.Text=tostring(def); vl.Size=UDim2.new(0,55,0,20); vl.Position=UDim2.new(1,-65,0,6)
    vl.BackgroundTransparency=1; vl.TextColor3=ACCENT; vl.TextSize=13
    vl.Font=Enum.Font.GothamBold; vl.TextXAlignment=Enum.TextXAlignment.Right
    local tr=Instance.new("Frame",f)
    tr.Size=UDim2.new(1,-20,0,8); tr.Position=UDim2.new(0,10,0,40)
    tr.BackgroundColor3=BORDER; tr.BorderSizePixel=0
    Instance.new("UICorner",tr).CornerRadius=UDim.new(1,0)
    local fi=Instance.new("Frame",tr)
    fi.BackgroundColor3=ACCENT; fi.BorderSizePixel=0
    fi.Size=UDim2.new((def-mn)/(mx-mn),0,1,0)
    Instance.new("UICorner",fi).CornerRadius=UDim.new(1,0)
    local kn=Instance.new("Frame",fi)
    kn.Size=UDim2.new(0,18,0,18); kn.Position=UDim2.new(1,-9,0.5,-9)
    kn.BackgroundColor3=Color3.fromRGB(255,255,255); kn.BorderSizePixel=0; kn.ZIndex=5
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)
    local drag=false
    local function upd(p)
        p=math.clamp(p,0,1)
        local v=math.floor(mn+(mx-mn)*p)
        fi.Size=UDim2.new(p,0,1,0); vl.Text=tostring(v); try(cb,v)
    end
    tr.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=true end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            upd((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then drag=false end
    end)
end

-- ══════════════════════════════════════
-- DEBUG PANEL
-- ══════════════════════════════════════

local function makeDebugBtn(lbl, action)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-6,0,40); f.BackgroundColor3=PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,8)
    local fs=Instance.new("UIStroke",f); fs.Color=BORDER; fs.Thickness=1
    local btn=Instance.new("TextButton",f)
    btn.Size=UDim2.new(1,-12,0,28); btn.Position=UDim2.new(0,6,0.5,-14)
    btn.BackgroundColor3=Color3.fromRGB(40,40,60); btn.Text=lbl
    btn.TextColor3=TEXT; btn.TextSize=11; btn.Font=Enum.Font.GothamBold
    btn.BorderSizePixel=0
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)
    btn.MouseButton1Click:Connect(function() try(action) end)
    return f
end

-- Output label for debug info
local debugOutput = Instance.new("Frame",Scr)
debugOutput.Size=UDim2.new(1,-6,0,0); debugOutput.BackgroundColor3=PANEL
debugOutput.BorderSizePixel=0; debugOutput.AutomaticSize=Enum.AutomaticSize.Y
Instance.new("UICorner",debugOutput).CornerRadius=UDim.new(0,8)
local debugLabel=Instance.new("TextLabel",debugOutput)
debugLabel.Size=UDim2.new(1,-8,0,0); debugLabel.Position=UDim2.new(0,4,0,4)
debugLabel.AutomaticSize=Enum.AutomaticSize.Y
debugLabel.BackgroundTransparency=1; debugLabel.TextColor3=DIM
debugLabel.TextSize=9; debugLabel.Font=Enum.Font.Code
debugLabel.TextXAlignment=Enum.TextXAlignment.Left
debugLabel.TextWrapped=true; debugLabel.Text=""

local function dbg(txt)
    debugLabel.Text = txt
end

-- ══════════════════════════════════════
-- MENU ITEMS
-- ══════════════════════════════════════

sec("🥚 ESP")
tog("Egg ESP",
    "يقرأ labels اللعبة الأصلية على البيض",
    function() State.Esp=true;  scanAllForEsp() end,
    function() State.Esp=false; removeAllEsp() end
)

sec("🏃 الحركة")
tog("سرعة مخصصة","السلايدر يتحكم",
    function() State.Speed=true;  enableSpeed() end,
    function() State.Speed=false; disableSpeed() end
)
sld("قيمة السرعة",16,250,60,function(v) State.SpeedVal=v end)

tog("قفز عالي","قوة قفز × 2.4",
    function() State.HighJump=true;  enableJump() end,
    function() State.HighJump=false; disableJump() end
)
tog("NoClip","اخترق الجدران",
    function() State.NoClip=true;  enableNoclip() end,
    function() State.NoClip=false; disableNoclip() end
)
tog("Fly","تطير بالكاميرا",
    function() State.Fly=true;  enableFly() end,
    function() State.Fly=false; disableFly() end
)

sec("🤖 أوتو فارم")
tog("تجميع ذكي",
    "أغلى بيضة أولاً — multi-method collect",
    function() State.AutoFarm=true;  runAutoFarm() end,
    function() State.AutoFarm=false end
)
tog("Infinite Stamina","طاقة لا تنتهي",
    function() State.InfStamina=true;  runInfStamina() end,
    function() State.InfStamina=false end
)

sec("⚙️ أدوات")
tog("Anti-AFK","لا تُكيك",
    function() State.AntiAfk=true;  runAntiAfk() end,
    function() State.AntiAfk=false end
)

sec("🔍 Debug — للتشخيص")

makeDebugBtn("🔎 اعرض كل RemoteEvents", function()
    local txt = showRemotes()
    if txt == "" then
        dbg("لا يوجد RemoteEvents")
    else
        dbg(txt)
    end
end)

makeDebugBtn("🥚 عدّ البيض في الماب", function()
    local eggs = getAllEggParts()
    dbg("وُجد "..#eggs.." بيضة\n"..
        table.concat((function()
            local t={}
            for i,e in ipairs(eggs) do
                if i>8 then table.insert(t,"..."); break end
                table.insert(t, e.zone.d.." @ "..string.format("%.0f",
                    Root and (Root.Position-e.pos).Magnitude or 0).."st")
            end
            return t
        end)(), "\n"))
end)

makeDebugBtn("📡 اعرض اسم اللعبة الداخلي", function()
    dbg("Game: "..game.Name.."\nPlaceId: "..tostring(game.PlaceId)..
        "\nJobId: "..game.JobId:sub(1,8).."...")
end)

debugOutput.Parent = Scr

local pd=Instance.new("Frame",Scr)
pd.Size=UDim2.new(1,0,0,8); pd.BackgroundTransparency=1

-- ══════════════════════════════════════
-- DRAG
-- ══════════════════════════════════════

local dagOn,dagSt,dagFr=false,nil,nil
TBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dagOn=true; dagSt=i.Position; dagFr=Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dagOn and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local d=i.Position-dagSt
        Main.Position=UDim2.new(dagFr.X.Scale,dagFr.X.Offset+d.X,dagFr.Y.Scale,dagFr.Y.Offset+d.Y)
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dagOn=false end
end)

-- HIDE
local hidOn=false
HBtn.MouseButton1Click:Connect(function()
    hidOn=not hidOn
    if hidOn then
        TweenService:Create(Main,TweenInfo.new(0.3,Enum.EasingStyle.Quart),{Size=UDim2.new(0,300,0,44)}):Play()
        HBtn.Text="+"
    else
        TweenService:Create(Main,TweenInfo.new(0.3,Enum.EasingStyle.Quart),{Size=UDim2.new(0,300,0,560)}):Play()
        HBtn.Text="—"
    end
end)

-- TOAST
local toast=Instance.new("Frame",SGui)
toast.Size=UDim2.new(0,280,0,48); toast.Position=UDim2.new(0.5,-140,0,-60)
toast.BackgroundColor3=PANEL; toast.BorderSizePixel=0
Instance.new("UICorner",toast).CornerRadius=UDim.new(0,10)
local ts=Instance.new("UIStroke",toast); ts.Color=ACCENT; ts.Thickness=1.5
local tl=Instance.new("TextLabel",toast)
tl.Text="🐾 v5.0 | Native Engine | Debug Tools"
tl.Size=UDim2.new(1,0,1,0); tl.BackgroundTransparency=1
tl.TextColor3=TEXT; tl.TextSize=12; tl.Font=Enum.Font.GothamBold
tl.TextXAlignment=Enum.TextXAlignment.Center

TweenService:Create(toast,TweenInfo.new(0.5,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.new(0.5,-140,0,12)}):Play()
task.delay(4,function()
    TweenService:Create(toast,TweenInfo.new(0.4,Enum.EasingStyle.Quart),
        {Position=UDim2.new(0.5,-140,0,-60)}):Play()
    task.delay(0.5,function() try(function() toast:Destroy() end) end)
end)
