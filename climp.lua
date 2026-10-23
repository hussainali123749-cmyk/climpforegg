--[[
╔══════════════════════════════════════════════════════════════════════╗
║   CLIMB FOR ANIMALS EGGS — MOD MENU v4.0                            ║
║   ProximityPrompt-Based ESP | Real Collection | No Lag              ║
║   Mobile/Android | Delta                                            ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ══════════════════════════════════════
-- SAFETY
-- ══════════════════════════════════════

local function try(f, ...)
    local ok, r = pcall(f, ...)
    return ok, r
end

-- ══════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
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
-- EGG DATA — ZONE PRIORITY + COLORS
-- ══════════════════════════════════════

local ZONES = {
    forest      = { d="Forest",      c="~$500",  col=Color3.fromRGB(160,220,130), p=1  },
    winter      = { d="Winter",      c="~$2K",   col=Color3.fromRGB(130,200,255), p=2  },
    ocean       = { d="Ocean",       c="~$8K",   col=Color3.fromRGB(60,120,255),  p=3  },
    desert      = { d="Desert",      c="~$15K",  col=Color3.fromRGB(240,180,60),  p=4  },
    crystal     = { d="Crystal",     c="~$50K",  col=Color3.fromRGB(160,60,220),  p=5  },
    jungle      = { d="Jungle",      c="~$120K", col=Color3.fromRGB(40,180,80),   p=6  },
    mystic      = { d="Mystic",      c="~$500K", col=Color3.fromRGB(255,140,255), p=7  },
    prehistoric = { d="Prehistoric", c="~$2M",   col=Color3.fromRGB(200,120,60),  p=8  },
    divine      = { d="Divine",      c="~$20M",  col=Color3.fromRGB(0,220,220),   p=9  },
    celestial   = { d="Celestial",   c="~$200M", col=Color3.fromRGB(255,240,80),  p=10 },
    realm       = { d="Royal",       c="~$10B+", col=Color3.fromRGB(255,20,147),  p=11 },
    royal       = { d="Royal",       c="~$10B+", col=Color3.fromRGB(255,20,147),  p=11 },
    mythic      = { d="Mythic",      c="~$5M",   col=Color3.fromRGB(255,60,60),   p=9  },
    legendary   = { d="Legendary",   c="~$2M",   col=Color3.fromRGB(255,180,0),   p=8  },
    epic        = { d="Epic",        c="~$120K", col=Color3.fromRGB(160,60,220),  p=5  },
    rare        = { d="Rare",        c="~$15K",  col=Color3.fromRGB(80,120,255),  p=3  },
    uncommon    = { d="Uncommon",    c="~$2K",   col=Color3.fromRGB(80,200,80),   p=2  },
    common      = { d="Common",      c="~$500",  col=Color3.fromRGB(200,200,200), p=1  },
    diamond     = { d="Diamond",     c="~$1K",   col=Color3.fromRGB(180,230,255), p=2  },
    golden      = { d="Golden",      c="~$50K",  col=Color3.fromRGB(255,200,0),   p=5  },
    ice         = { d="Ice",         c="~$500K", col=Color3.fromRGB(180,230,255), p=7  },
}

local function classifyName(name)
    local low = name:lower()
    for k, v in pairs(ZONES) do
        if low:find(k) then return v end
    end
    return nil
end

-- ══════════════════════════════════════
-- ESP CORE — ProximityPrompt METHOD
--
-- WHY THIS WORKS:
-- Every collectible egg in Roblox simulators has a
-- ProximityPrompt attached so the player can interact.
-- Decorative parts, floors, walls — NONE of them have
-- ProximityPrompts. This is the perfect filter.
--
-- We look for ProximityPrompt inside the object's tree.
-- If it has one → it's interactive → it's a real egg.
-- ══════════════════════════════════════

local activeEsp = {}   -- part -> { bb=BillboardGui, prompt=ProximityPrompt }

local function getPromptFromPart(part)
    -- Check part itself
    local pp = part:FindFirstChildOfClass("ProximityPrompt")
    if pp then return pp end
    -- Check parent model
    if part.Parent and part.Parent:IsA("Model") then
        pp = part.Parent:FindFirstChildOfClass("ProximityPrompt")
        if pp then return pp end
        -- Deep search inside model
        pp = part.Parent:FindFirstChildOfClass("ProximityPrompt", true)
        if pp then return pp end
    end
    return nil
end

-- Get zone data from part + its model hierarchy
local function getZoneData(part)
    -- Try part name
    local zd = classifyName(part.Name)
    if zd then return zd end
    -- Try parent model name
    if part.Parent then
        zd = classifyName(part.Parent.Name)
        if zd then return zd end
    end
    -- Try grandparent
    if part.Parent and part.Parent.Parent then
        zd = classifyName(part.Parent.Parent.Name)
        if zd then return zd end
    end
    return { d="Egg", c="?", col=Color3.fromRGB(255,255,255), p=1 }
end

-- Check if part is inside a player character
local function isInCharacter(part)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and part:IsDescendantOf(p.Character) then
            return true
        end
    end
    return false
end

local function removeEsp(part)
    if activeEsp[part] then
        try(function() activeEsp[part].bb:Destroy() end)
        activeEsp[part] = nil
    end
end

local function removeAllEsp()
    for part in pairs(activeEsp) do
        try(function()
            if activeEsp[part] then
                activeEsp[part].bb:Destroy()
            end
        end)
    end
    activeEsp = {}
end

local function addEsp(part)
    if activeEsp[part] then return end
    if isInCharacter(part) then return end
    if part:IsDescendantOf(PGui) then return end

    local prompt = getPromptFromPart(part)
    if not prompt then return end  -- NO PROMPT = NOT A REAL EGG

    local zd = getZoneData(part)

    -- Build billboard
    local bb = Instance.new("BillboardGui")
    bb.Name             = "CAFE_ESP"
    bb.Size             = UDim2.new(0, 140, 0, 54)
    bb.StudsOffset      = Vector3.new(0, part.Size.Y + 1.5, 0)
    bb.AlwaysOnTop      = true
    bb.MaxDistance      = 1200
    bb.LightInfluence   = 0
    bb.Parent           = part

    local bg = Instance.new("Frame")
    bg.Size                  = UDim2.new(1,0,1,0)
    bg.BackgroundColor3      = Color3.fromRGB(8,8,16)
    bg.BackgroundTransparency = 0.2
    bg.BorderSizePixel       = 0
    bg.Parent                = bb

    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,6)

    local stroke = Instance.new("UIStroke", bg)
    stroke.Color    = zd.col
    stroke.Thickness = 1.5

    local l1 = Instance.new("TextLabel", bg)
    l1.Size                  = UDim2.new(1,-4,0.5,0)
    l1.Position              = UDim2.new(0,2,0,2)
    l1.BackgroundTransparency = 1
    l1.TextColor3            = zd.col
    l1.TextSize              = 12
    l1.Font                  = Enum.Font.GothamBold
    l1.Text                  = "["..zd.d.."]  "..zd.c
    l1.TextScaled            = true
    l1.TextXAlignment        = Enum.TextXAlignment.Center

    local l2 = Instance.new("TextLabel", bg)
    l2.Size                  = UDim2.new(1,-4,0.5,-2)
    l2.Position              = UDim2.new(0,2,0.5,0)
    l2.BackgroundTransparency = 1
    l2.TextColor3            = Color3.fromRGB(190,190,210)
    l2.TextSize              = 11
    l2.Font                  = Enum.Font.Gotham
    l2.Text                  = "..."
    l2.TextScaled            = true
    l2.TextXAlignment        = Enum.TextXAlignment.Center

    activeEsp[part] = { bb=bb, prompt=prompt, zone=zd }

    -- Distance updater — no RunService connection, uses task loop
    task.spawn(function()
        while bb and bb.Parent and State.Esp do
            try(function()
                if not part or not part.Parent then
                    removeEsp(part); return
                end
                if Root then
                    local dist = (Root.Position - part.Position).Magnitude
                    l2.Text = string.format("📍 %.0f studs", dist)
                end
            end)
            task.wait(0.5)
        end
    end)
end

-- Scan entire Workspace for ProximityPrompts
-- Find parent BasePart → that's the egg
local function scanAllEggs()
    -- Method: find ALL ProximityPrompts in Workspace
    -- Each one's parent (or parent's parent) is the egg part
    local function processPrompt(prompt)
        if not prompt:IsA("ProximityPrompt") then return end

        local parent = prompt.Parent
        if not parent then return end

        -- Find the BasePart that owns this prompt
        local eggPart = nil
        if parent:IsA("BasePart") then
            -- Check name contains egg OR parent model does
            local nameLow = parent.Name:lower()
            if nameLow:find("egg") or (parent.Parent and parent.Parent.Name:lower():find("egg")) then
                eggPart = parent
            end
        elseif parent:IsA("Model") then
            local nameLow = parent.Name:lower()
            if nameLow:find("egg") then
                eggPart = parent.PrimaryPart
                if not eggPart then
                    eggPart = parent:FindFirstChildWhichIsA("BasePart")
                end
            end
        end

        if eggPart then
            addEsp(eggPart)
        end
    end

    -- Get all descendants with ProximityPrompt
    local function deepScan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                if child:IsA("ProximityPrompt") then
                    processPrompt(child)
                end
                -- Skip player characters
                if not isInCharacter(child) then
                    deepScan(child)
                end
            end)
        end
    end

    deepScan(Workspace)
end

-- Watch for new eggs
Workspace.DescendantAdded:Connect(function(d)
    if not State.Esp then return end
    if not d:IsA("ProximityPrompt") then return end
    task.wait(0.2)
    try(function()
        local parent = d.Parent
        if not parent then return end
        local eggPart = nil
        if parent:IsA("BasePart") and parent.Name:lower():find("egg") then
            eggPart = parent
        elseif parent:IsA("Model") and parent.Name:lower():find("egg") then
            eggPart = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
        end
        if eggPart then addEsp(eggPart) end
    end)
end)

Workspace.DescendantRemoving:Connect(function(d)
    if activeEsp[d] then removeEsp(d) end
end)

-- ══════════════════════════════════════
-- AUTO FARM — REAL COLLECTION
--
-- Uses fireproximityprompt() — the correct
-- way to trigger egg collection on the server.
-- Delta supports this natively on Android.
--
-- Flow:
-- 1. Find best egg by priority score
-- 2. Teleport directly (no lerp = no lag)
-- 3. Fire the ProximityPrompt = server collects egg
-- 4. Wait cooldown, then next egg
-- ══════════════════════════════════════

-- Collect ALL eggs with ProximityPrompts in Workspace
local function getAllEggs()
    local eggs = {}
    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                if child:IsA("ProximityPrompt") then
                    local parent = child.Parent
                    if parent then
                        local eggPart = nil
                        if parent:IsA("BasePart") and parent.Name:lower():find("egg") then
                            eggPart = parent
                        elseif parent:IsA("Model") and parent.Name:lower():find("egg") then
                            eggPart = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
                        end
                        if eggPart and not isInCharacter(eggPart) then
                            local zd = getZoneData(eggPart)
                            table.insert(eggs, {
                                part   = eggPart,
                                prompt = child,
                                zone   = zd,
                                pos    = eggPart.Position,
                            })
                        end
                    end
                end
                if not isInCharacter(child) then scan(child) end
            end)
        end
    end
    scan(Workspace)
    return eggs
end

-- Find best egg by priority (rarest = highest priority)
local function getBestEgg(eggs)
    if #eggs == 0 then return nil end
    local best, bestScore = nil, -math.huge
    for _, e in ipairs(eggs) do
        if e.part and e.part.Parent then
            local dist  = Root and (Root.Position - e.pos).Magnitude or 0
            -- Priority heavily weighted, distance minor tiebreaker
            local score = (e.zone.p * 10000) - dist
            if score > bestScore then
                bestScore = score
                best      = e
            end
        end
    end
    return best
end

-- Instant teleport — no lerp, no lag
local function tpTo(pos)
    try(function()
        if Root then
            Root.CFrame = CFrame.new(pos + Vector3.new(0, 5, 0))
        end
    end)
end

-- Fire proximity prompt — actual collection
local function collect(prompt)
    try(function()
        -- Method 1: fireproximityprompt (Delta's built-in)
        fireproximityprompt(prompt)
    end)
    -- Method 2 fallback: simulate trigger events
    try(function()
        prompt:InputHoldBegin()
    end)
    try(function()
        task.wait(0.1)
        prompt:InputHoldEnd()
    end)
end

local function runAutoFarm()
    task.spawn(function()
        while State.AutoFarm do
            try(function()
                if not Root then task.wait(1); return end

                local eggs = getAllEggs()
                if #eggs == 0 then task.wait(2); return end

                local target = getBestEgg(eggs)
                if not target then task.wait(1); return end

                -- Teleport to egg
                tpTo(target.pos)
                task.wait(0.3)  -- brief land time

                -- Actually collect the egg
                collect(target.prompt)
                task.wait(0.2)

                -- Short delay before next egg
                task.wait(0.5 + math.random() * 0.3)
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
            if Hum and Hum.Parent and Hum.WalkSpeed ~= State.SpeedVal then
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
                    local st = stats:FindFirstChild("Stamina")
                    if st then st.Value = 99999 end
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
            task.wait(55 + math.random() * 10)
        end
    end)
end

-- ══════════════════════════════════════
-- GUI COLORS
-- ══════════════════════════════════════

local BG     = Color3.fromRGB(10, 10, 18)
local PANEL  = Color3.fromRGB(18, 20, 30)
local ACCENT = Color3.fromRGB(110,60,240)
local ON_C   = Color3.fromRGB(50, 220,110)
local OFF_C  = Color3.fromRGB(200,55, 55)
local TEXT   = Color3.fromRGB(225,225,245)
local DIM    = Color3.fromRGB(130,130,155)
local BORDER = Color3.fromRGB(55, 40, 90)

-- ══════════════════════════════════════
-- GUI BUILD
-- ══════════════════════════════════════

local oldG = PGui:FindFirstChild("CAFE_ModMenu")
if oldG then oldG:Destroy() end

local SGui = Instance.new("ScreenGui")
SGui.Name           = "CAFE_ModMenu"
SGui.ResetOnSpawn   = false
SGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

try(function() SGui.Parent = game:GetService("CoreGui") end)
if not SGui.Parent then SGui.Parent = PGui end

local Main = Instance.new("Frame")
Main.Size             = UDim2.new(0,300,0,510)
Main.Position         = UDim2.new(0,8,0.5,-255)
Main.BackgroundColor3 = BG
Main.BorderSizePixel  = 0
Main.Parent           = SGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0,12)
local ms = Instance.new("UIStroke", Main)
ms.Color = BORDER; ms.Thickness = 1.5

local TBar = Instance.new("Frame")
TBar.Size = UDim2.new(1,0,0,44); TBar.BackgroundColor3 = PANEL
TBar.BorderSizePixel = 0; TBar.Parent = Main
Instance.new("UICorner", TBar).CornerRadius = UDim.new(0,12)
local tfx = Instance.new("Frame", TBar)
tfx.Size = UDim2.new(1,0,0.5,0); tfx.Position = UDim2.new(0,0,0.5,0)
tfx.BackgroundColor3 = PANEL; tfx.BorderSizePixel = 0

local TL = Instance.new("TextLabel", TBar)
TL.Text = "🐾 Climb For Animals Eggs"
TL.Size = UDim2.new(1,-50,0,24); TL.Position = UDim2.new(0,12,0,6)
TL.BackgroundTransparency = 1; TL.TextColor3 = TEXT
TL.TextSize = 14; TL.Font = Enum.Font.GothamBold
TL.TextXAlignment = Enum.TextXAlignment.Left

local SL = Instance.new("TextLabel", Main)
SL.Text = "v4.0 | ProximityPrompt Engine | Delta"
SL.Size = UDim2.new(1,-12,0,14); SL.Position = UDim2.new(0,12,0,30)
SL.BackgroundTransparency = 1; SL.TextColor3 = DIM
SL.TextSize = 10; SL.Font = Enum.Font.Gotham
SL.TextXAlignment = Enum.TextXAlignment.Left

local HBtn = Instance.new("TextButton", TBar)
HBtn.Size = UDim2.new(0,32,0,32); HBtn.Position = UDim2.new(1,-40,0,6)
HBtn.BackgroundColor3 = ACCENT; HBtn.Text = "—"
HBtn.TextColor3 = TEXT; HBtn.TextSize = 16
HBtn.Font = Enum.Font.GothamBold; HBtn.BorderSizePixel = 0
Instance.new("UICorner", HBtn).CornerRadius = UDim.new(0,8)

local Scr = Instance.new("ScrollingFrame", Main)
Scr.Size = UDim2.new(1,-10,1,-58); Scr.Position = UDim2.new(0,5,0,52)
Scr.BackgroundTransparency = 1; Scr.BorderSizePixel = 0
Scr.ScrollBarThickness = 4; Scr.ScrollBarImageColor3 = ACCENT
Scr.CanvasSize = UDim2.new(0,0,0,0)

local Lay = Instance.new("UIListLayout", Scr)
Lay.Padding = UDim.new(0,5)
Lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scr.CanvasSize = UDim2.new(0,0,0,Lay.AbsoluteContentSize.Y+10)
end)

-- Section
local function sec(txt)
    local f = Instance.new("Frame", Scr)
    f.Size = UDim2.new(1,-6,0,22); f.BackgroundTransparency = 1
    local ln = Instance.new("Frame", f)
    ln.Size = UDim2.new(1,0,0,1); ln.Position = UDim2.new(0,0,0.5,0)
    ln.BackgroundColor3 = BORDER; ln.BorderSizePixel = 0
    local lb = Instance.new("TextLabel", f)
    lb.Text = "  "..txt.."  "; lb.Size = UDim2.new(0,0,1,0)
    lb.AutomaticSize = Enum.AutomaticSize.X; lb.Position = UDim2.new(0,10,0,0)
    lb.BackgroundColor3 = BG; lb.TextColor3 = ACCENT
    lb.TextSize = 11; lb.Font = Enum.Font.GothamBold
end

-- Toggle
local function tog(name, desc, onOn, onOff)
    local f = Instance.new("Frame", Scr)
    f.Size = UDim2.new(1,-6,0,56); f.BackgroundColor3 = PANEL; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local fs = Instance.new("UIStroke", f); fs.Color = BORDER; fs.Thickness = 1

    local nl = Instance.new("TextLabel", f)
    nl.Text = name; nl.Size = UDim2.new(1,-80,0,22); nl.Position = UDim2.new(0,10,0,6)
    nl.BackgroundTransparency = 1; nl.TextColor3 = TEXT
    nl.TextSize = 13; nl.Font = Enum.Font.GothamBold; nl.TextXAlignment = Enum.TextXAlignment.Left

    local dl = Instance.new("TextLabel", f)
    dl.Text = desc; dl.Size = UDim2.new(1,-80,0,18); dl.Position = UDim2.new(0,10,0,30)
    dl.BackgroundTransparency = 1; dl.TextColor3 = DIM
    dl.TextSize = 10; dl.Font = Enum.Font.Gotham; dl.TextXAlignment = Enum.TextXAlignment.Left

    local btn = Instance.new("TextButton", f)
    btn.Size = UDim2.new(0,62,0,30); btn.Position = UDim2.new(1,-72,0.5,-15)
    btn.BackgroundColor3 = OFF_C; btn.Text = "OFF"
    btn.TextColor3 = Color3.fromRGB(255,255,255); btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold; btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,7)

    local on = false
    btn.MouseButton1Click:Connect(function()
        on = not on
        if on then
            btn.Text = "ON"
            TweenService:Create(btn,TweenInfo.new(0.2),{BackgroundColor3=ON_C}):Play()
            try(onOn)
        else
            btn.Text = "OFF"
            TweenService:Create(btn,TweenInfo.new(0.2),{BackgroundColor3=OFF_C}):Play()
            try(onOff)
        end
    end)
    return f, btn
end

-- Slider
local function sld(lbl, mn, mx, def, cb)
    local f = Instance.new("Frame", Scr)
    f.Size = UDim2.new(1,-6,0,64); f.BackgroundColor3 = PANEL; f.BorderSizePixel = 0
    Instance.new("UICorner", f).CornerRadius = UDim.new(0,8)
    local fs = Instance.new("UIStroke", f); fs.Color = BORDER; fs.Thickness = 1

    local nl = Instance.new("TextLabel", f)
    nl.Text = lbl; nl.Size = UDim2.new(1,-70,0,20); nl.Position = UDim2.new(0,10,0,6)
    nl.BackgroundTransparency = 1; nl.TextColor3 = TEXT
    nl.TextSize = 13; nl.Font = Enum.Font.GothamBold; nl.TextXAlignment = Enum.TextXAlignment.Left

    local vl = Instance.new("TextLabel", f)
    vl.Text = tostring(def); vl.Size = UDim2.new(0,55,0,20); vl.Position = UDim2.new(1,-65,0,6)
    vl.BackgroundTransparency = 1; vl.TextColor3 = ACCENT
    vl.TextSize = 13; vl.Font = Enum.Font.GothamBold; vl.TextXAlignment = Enum.TextXAlignment.Right

    local tr = Instance.new("Frame", f)
    tr.Size = UDim2.new(1,-20,0,8); tr.Position = UDim2.new(0,10,0,40)
    tr.BackgroundColor3 = BORDER; tr.BorderSizePixel = 0
    Instance.new("UICorner", tr).CornerRadius = UDim.new(1,0)

    local fi = Instance.new("Frame", tr)
    fi.BackgroundColor3 = ACCENT; fi.BorderSizePixel = 0
    fi.Size = UDim2.new((def-mn)/(mx-mn),0,1,0)
    Instance.new("UICorner", fi).CornerRadius = UDim.new(1,0)

    local kn = Instance.new("Frame", fi)
    kn.Size = UDim2.new(0,18,0,18); kn.Position = UDim2.new(1,-9,0.5,-9)
    kn.BackgroundColor3 = Color3.fromRGB(255,255,255); kn.BorderSizePixel = 0; kn.ZIndex = 5
    Instance.new("UICorner", kn).CornerRadius = UDim.new(1,0)

    local drag = false
    local function upd(p)
        p = math.clamp(p,0,1)
        local v = math.floor(mn+(mx-mn)*p)
        fi.Size = UDim2.new(p,0,1,0); vl.Text = tostring(v)
        try(cb,v)
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
-- MENU ITEMS
-- ══════════════════════════════════════

sec("🥚 ESP")
tog("Egg ESP",
    "ProximityPrompt فقط — بيض حقيقية 100%",
    function() State.Esp=true;  scanAllEggs() end,
    function() State.Esp=false; removeAllEsp() end
)

sec("🏃 الحركة")
tog("سرعة مخصصة","السلايدر يتحكم بالسرعة",
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
    "يجمع أغلى بيضة — fireproximityprompt",
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

local pd = Instance.new("Frame",Scr)
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

-- ══════════════════════════════════════
-- HIDE BUTTON
-- ══════════════════════════════════════

local hidOn=false
HBtn.MouseButton1Click:Connect(function()
    hidOn=not hidOn
    if hidOn then
        TweenService:Create(Main,TweenInfo.new(0.3,Enum.EasingStyle.Quart),{Size=UDim2.new(0,300,0,44)}):Play()
        HBtn.Text="+"
    else
        TweenService:Create(Main,TweenInfo.new(0.3,Enum.EasingStyle.Quart),{Size=UDim2.new(0,300,0,510)}):Play()
        HBtn.Text="—"
    end
end)

-- ══════════════════════════════════════
-- TOAST
-- ══════════════════════════════════════

local toast=Instance.new("Frame",SGui)
toast.Size=UDim2.new(0,280,0,48); toast.Position=UDim2.new(0.5,-140,0,-60)
toast.BackgroundColor3=PANEL; toast.BorderSizePixel=0
Instance.new("UICorner",toast).CornerRadius=UDim.new(0,10)
local ts=Instance.new("UIStroke",toast); ts.Color=ACCENT; ts.Thickness=1.5
local tl=Instance.new("TextLabel",toast)
tl.Text="🐾 v4.0 | ESP محسّن + جمع حقيقي"
tl.Size=UDim2.new(1,0,1,0); tl.BackgroundTransparency=1
tl.TextColor3=TEXT; tl.TextSize=12; tl.Font=Enum.Font.GothamBold
tl.TextXAlignment=Enum.TextXAlignment.Center

TweenService:Create(toast,TweenInfo.new(0.5,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.new(0.5,-140,0,12)}):Play()
task.delay(3.5,function()
    TweenService:Create(toast,TweenInfo.new(0.4,Enum.EasingStyle.Quart),
        {Position=UDim2.new(0.5,-140,0,-60)}):Play()
    task.delay(0.5,function() try(function() toast:Destroy() end) end)
end)
