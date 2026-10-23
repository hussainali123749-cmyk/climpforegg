--[[
╔══════════════════════════════════════════════════════════════════════╗
║   CLIMB FOR ANIMALS EGGS — MOD MENU v3.0                            ║
║   Mobile/Android | Delta | Fixed ESP + Smart Auto Farm              ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ══════════════════════════════════════
-- SECTION 0: SAFETY
-- ══════════════════════════════════════

local function try(f, ...)
    local ok, r = pcall(f, ...)
    return ok, r
end

-- ══════════════════════════════════════
-- SECTION 1: SERVICES
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
    Char = c
    Hum  = c:WaitForChild("Humanoid")
    Root = c:WaitForChild("HumanoidRootPart")
end)

-- ══════════════════════════════════════
-- SECTION 2: STATE
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
-- SECTION 3: EGG DETECTION SYSTEM (FIXED)
--
-- Problem: old code matched ANY part with "egg" in name
-- even decorations, UI parts, pets named "egg", etc.
--
-- Fix: strict validation rules
--   1. Part must be a BasePart (not Model/GUI)
--   2. Minimum size threshold (real eggs are larger)
--   3. Must be in Workspace descendants, not inside
--      player characters or UI
--   4. Name must match exact egg patterns used by this game
--   5. Zone detection by PARENT name, not part name
-- ══════════════════════════════════════

-- Egg rarity data — value used for smart auto-farm priority
-- Higher value = higher priority
local EGG_ZONES = {
    -- key = pattern to search in Model/Part name (lowercase)
    -- val = { display, cash string, color, priority score }
    forest        = { d="Forest",        c="~$500",    col=Color3.fromRGB(160,220,130), p=1   },
    winter        = { d="Winter",        c="~$2K",     col=Color3.fromRGB(130,200,255), p=2   },
    ocean         = { d="Ocean",         c="~$8K",     col=Color3.fromRGB(60,120,255),  p=3   },
    desert        = { d="Desert",        c="~$15K",    col=Color3.fromRGB(240,180,60),  p=4   },
    crystal       = { d="Crystal",       c="~$50K",    col=Color3.fromRGB(160,60,220),  p=5   },
    jungle        = { d="Jungle",        c="~$120K",   col=Color3.fromRGB(40,180,80),   p=6   },
    mystic        = { d="Mystic",        c="~$500K",   col=Color3.fromRGB(255,140,255), p=7   },
    prehistoric   = { d="Prehistoric",   c="~$2M",     col=Color3.fromRGB(200,120,60),  p=8   },
    divine        = { d="Divine",        c="~$20M",    col=Color3.fromRGB(0,220,220),   p=9   },
    celestial     = { d="Celestial",     c="~$200M",   col=Color3.fromRGB(255,240,80),  p=10  },
    realm         = { d="Realm/Royal",   c="~$10B+",   col=Color3.fromRGB(255,20,147),  p=11  },
    -- rarity keywords as fallback
    common        = { d="Common",        c="~$500",    col=Color3.fromRGB(200,200,200), p=1   },
    uncommon      = { d="Uncommon",      c="~$2K",     col=Color3.fromRGB(80,200,80),   p=2   },
    rare          = { d="Rare",          c="~$15K",    col=Color3.fromRGB(80,120,255),  p=3   },
    epic          = { d="Epic",          c="~$120K",   col=Color3.fromRGB(160,60,220),  p=5   },
    legendary     = { d="Legendary",     c="~$2M",     col=Color3.fromRGB(255,180,0),   p=8   },
    mythic        = { d="Mythic",        c="~$5M",     col=Color3.fromRGB(255,60,60),   p=9   },
    royal         = { d="Royal",         c="~$10B+",   col=Color3.fromRGB(255,20,147),  p=11  },
    diamond       = { d="Diamond",       c="~$1K",     col=Color3.fromRGB(180,230,255), p=2   },
    golden        = { d="Golden",        c="~$50K",    col=Color3.fromRGB(255,200,0),   p=5   },
}

local MIN_EGG_SIZE = 1.0  -- studs — real eggs are at least 1 stud

-- Check if a name string references a zone or rarity
local function classifyByName(name)
    local low = name:lower()
    for key, data in pairs(EGG_ZONES) do
        if low:find(key) then
            return data
        end
    end
    return nil
end

-- STRICT egg validation
-- Returns zone data if valid egg, nil if not
local function validateEgg(part)
    -- Must be BasePart
    if not part:IsA("BasePart") then return nil end

    -- Must not be inside a player character
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and part:IsDescendantOf(p.Character) then
            return nil
        end
    end

    -- Must not be inside PlayerGui or any GUI
    if part:IsDescendantOf(PGui) then return nil end

    -- Size check — real eggs are not tiny decorative parts
    local sz = part.Size
    local minDim = math.min(sz.X, sz.Y, sz.Z)
    if minDim < MIN_EGG_SIZE then return nil end

    -- Try to identify by part name first
    local partName = part.Name:lower()
    if partName:find("egg") then
        -- Look at parent Model name for zone info
        local parent = part.Parent
        if parent and parent:IsA("Model") then
            local zoneData = classifyByName(parent.Name)
            if zoneData then return zoneData end
        end
        -- Fallback: classify by part name itself
        local zoneData = classifyByName(part.Name)
        if zoneData then return zoneData end
        -- It has "egg" in name but no known zone — show as generic
        return { d="Egg", c="?", col=Color3.fromRGB(255,255,255), p=1 }
    end

    -- Parent Model has "egg" in name
    local parent = part.Parent
    if parent and parent:IsA("Model") and parent.Name:lower():find("egg") then
        -- Part is primary part or first part of egg model
        if parent.PrimaryPart == part or part == parent:FindFirstChildWhichIsA("BasePart") then
            local zoneData = classifyByName(parent.Name)
            if zoneData then return zoneData end
            return { d="Egg", c="?", col=Color3.fromRGB(255,255,255), p=1 }
        end
    end

    return nil  -- Not a real egg
end

-- ══════════════════════════════════════
-- SECTION 4: ESP SYSTEM (BILLBOARD)
-- ══════════════════════════════════════

local activeEsp = {}  -- part -> BillboardGui

local function removeEsp(part)
    if activeEsp[part] then
        try(function() activeEsp[part]:Destroy() end)
        activeEsp[part] = nil
    end
end

local function removeAllEsp()
    for part, _ in pairs(activeEsp) do
        removeEsp(part)
    end
    activeEsp = {}
end

local function addEsp(part, zoneData)
    if activeEsp[part] then return end  -- already tagged

    local bb = Instance.new("BillboardGui")
    bb.Name           = "CAFE_ESP"
    bb.Size           = UDim2.new(0, 130, 0, 52)
    bb.StudsOffset    = Vector3.new(0, part.Size.Y/2 + 2, 0)
    bb.AlwaysOnTop    = true
    bb.MaxDistance    = 1200
    bb.LightInfluence = 0
    bb.ClipsDescendants = false
    bb.Parent         = part

    local bg = Instance.new("Frame")
    bg.Size           = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(8, 8, 16)
    bg.BackgroundTransparency = 0.25
    bg.BorderSizePixel = 0
    bg.Parent         = bb

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius  = UDim.new(0, 6)
    bgc.Parent        = bg

    local bgs = Instance.new("UIStroke")
    bgs.Color         = zoneData.col
    bgs.Thickness     = 1.5
    bgs.Parent        = bg

    -- Zone + Cash line
    local line1 = Instance.new("TextLabel")
    line1.Size        = UDim2.new(1, -6, 0.5, 0)
    line1.Position    = UDim2.new(0, 3, 0, 2)
    line1.BackgroundTransparency = 1
    line1.TextColor3  = zoneData.col
    line1.TextSize    = 12
    line1.Font        = Enum.Font.GothamBold
    line1.Text        = "["..zoneData.d.."] "..zoneData.c
    line1.TextScaled  = true
    line1.TextXAlignment = Enum.TextXAlignment.Center
    line1.Parent      = bg

    -- Distance line (updates live)
    local line2 = Instance.new("TextLabel")
    line2.Size        = UDim2.new(1, -6, 0.5, -2)
    line2.Position    = UDim2.new(0, 3, 0.5, 0)
    line2.BackgroundTransparency = 1
    line2.TextColor3  = Color3.fromRGB(200, 200, 200)
    line2.TextSize    = 11
    line2.Font        = Enum.Font.Gotham
    line2.Text        = "..."
    line2.TextScaled  = true
    line2.TextXAlignment = Enum.TextXAlignment.Center
    line2.Parent      = bg

    activeEsp[part] = bb

    -- Live distance updater — runs until ESP disabled or part gone
    task.spawn(function()
        while bb and bb.Parent and State.Esp do
            try(function()
                if not part or not part.Parent then
                    removeEsp(part)
                    return
                end
                if Root then
                    local dist   = (Root.Position - part.Position).Magnitude
                    local sz     = part.Size
                    local realSz = string.format("%.1fx%.1fx%.1f", sz.X, sz.Y, sz.Z)
                    line2.Text   = string.format("📏 %s | 📍 %.0fst", realSz, dist)
                end
            end)
            task.wait(0.4)
        end
    end)
end

local function scanAllEggs()
    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                local zd = validateEgg(child)
                if zd then
                    addEsp(child, zd)
                end
                -- Don't scan inside player characters (performance + accuracy)
                local isChar = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == child then isChar = true; break end
                end
                if not isChar then
                    scan(child)
                end
            end)
        end
    end
    scan(Workspace)
end

-- Watch for new eggs spawning
Workspace.DescendantAdded:Connect(function(d)
    if not State.Esp then return end
    task.wait(0.15)  -- let it fully load
    try(function()
        local zd = validateEgg(d)
        if zd then addEsp(d, zd) end
    end)
end)

Workspace.DescendantRemoving:Connect(function(d)
    if activeEsp[d] then
        try(function() activeEsp[d]:Destroy() end)
        activeEsp[d] = nil
    end
end)

-- ══════════════════════════════════════
-- SECTION 5: SMART AUTO FARM
-- Priority = highest p value (rarest egg)
-- Smooth movement, no lag, pcall protected
-- ══════════════════════════════════════

-- Find best egg by priority score (not just distance)
local function findBestEgg()
    local best      = nil
    local bestScore = -1

    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                local zd = validateEgg(child)
                if zd then
                    -- Score = priority * 1000 - distance * 0.1
                    -- Strongly prefer rarity, distance is tiebreaker
                    local dist  = Root and (Root.Position - child.Position).Magnitude or 0
                    local score = (zd.p * 1000) - (dist * 0.1)
                    if score > bestScore then
                        bestScore = score
                        best      = { part=child, zone=zd, dist=dist }
                    end
                end
                local isChar = false
                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character == child then isChar = true; break end
                end
                if not isChar then scan(child) end
            end)
        end
    end

    scan(Workspace)
    return best
end

-- Smooth teleport: lerp in steps, not instant jump
-- Looks natural, avoids server-side velocity spike detection
local function smoothMove(targetPos)
    if not Root then return end
    local steps    = 10
    local startCF  = Root.CFrame
    local endCF    = CFrame.new(targetPos + Vector3.new(0, 4, 0))

    for i = 1, steps do
        if not State.AutoFarm then return end  -- abort if turned off
        try(function()
            Root.CFrame = startCF:Lerp(endCF, i / steps)
        end)
        task.wait(0.025)  -- 10 steps * 0.025s = 0.25s total — fast but smooth
    end
end

-- Find base/spawn area
local function getBasePosition()
    local pos = Vector3.new(0, 5, 0)
    try(function()
        -- Try to find spawn or base pad
        local candidates = {
            "SpawnLocation", "Base", "HatchPad", "BasePad",
            "PlayerBase", "Spawn", "Plot"
        }
        for _, name in ipairs(candidates) do
            local found = Workspace:FindFirstChild(name, true)
            if found and found:IsA("BasePart") then
                pos = found.Position + Vector3.new(0, 4, 0)
                return
            end
        end
        -- Fallback: use character spawn
        local sp = Workspace:FindFirstChildWhichIsA("SpawnLocation")
        if sp then pos = sp.Position + Vector3.new(0, 4, 0) end
    end)
    return pos
end

local function runAutoFarm()
    task.spawn(function()
        while State.AutoFarm do
            try(function()
                if not Root then task.wait(1); return end

                local target = findBestEgg()

                if target then
                    -- Move to best egg
                    smoothMove(target.part.Position)

                    -- Brief pause at egg (simulates interaction)
                    task.wait(0.6 + math.random() * 0.3)

                    -- Only go back to base if we're far from it
                    local basePOS = getBasePosition()
                    local distToBase = (Root.Position - basePOS).Magnitude

                    if distToBase > 50 then
                        smoothMove(basePOS)
                        task.wait(0.8 + math.random() * 0.4)
                    else
                        task.wait(0.3)
                    end
                else
                    -- No eggs found, wait and retry
                    task.wait(2 + math.random())
                end
            end)
        end
    end)
end

-- ══════════════════════════════════════
-- SECTION 6: SPEED (ANTI-DETECT)
-- ══════════════════════════════════════

local speedConn
local function enableSpeed()
    if speedConn then speedConn:Disconnect() end
    speedConn = RunService.Heartbeat:Connect(function()
        if not State.Speed then return end
        try(function()
            if Hum and Hum.Parent then
                if Hum.WalkSpeed ~= State.SpeedVal then
                    Hum.WalkSpeed = State.SpeedVal
                end
            end
        end)
    end)
end
local function disableSpeed()
    if speedConn then speedConn:Disconnect(); speedConn = nil end
    try(function() if Hum then Hum.WalkSpeed = 16 end end)
end

-- ══════════════════════════════════════
-- SECTION 7: HIGH JUMP
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
-- SECTION 8: NOCLIP
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
-- SECTION 9: FLY
-- ══════════════════════════════════════

local flyBV, flyBG
local function enableFly()
    try(function()
        flyBV          = Instance.new("BodyVelocity")
        flyBV.Velocity = Vector3.zero
        flyBV.MaxForce = Vector3.new(1e5,1e5,1e5)
        flyBV.Parent   = Root

        flyBG             = Instance.new("BodyGyro")
        flyBG.MaxTorque   = Vector3.new(1e5,1e5,1e5)
        flyBG.P           = 1e4
        flyBG.Parent      = Root

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
-- SECTION 10: INFINITE STAMINA
-- ══════════════════════════════════════

local function runInfStamina()
    task.spawn(function()
        while State.InfStamina do
            try(function()
                -- Method 1: leaderstats
                local stats = LP:FindFirstChild("leaderstats") or LP:FindFirstChild("Stats")
                if stats then
                    local st = stats:FindFirstChild("Stamina")
                    if st and st.Value < 100 then st.Value = 9999 end
                end
                -- Method 2: find stamina bar frame and read value object
                local sg = LP.PlayerGui:FindFirstChild("StaminaGui", true)
                    or LP.PlayerGui:FindFirstChild("Stamina", true)
                if sg then
                    local val = sg:FindFirstChildWhichIsA("IntValue")
                           or  sg:FindFirstChildWhichIsA("NumberValue")
                    if val and val.Value < 50 then val.Value = 9999 end
                end
            end)
            task.wait(0.15)
        end
    end)
end

-- ══════════════════════════════════════
-- SECTION 11: ANTI-AFK
-- ══════════════════════════════════════

local function runAntiAfk()
    task.spawn(function()
        while State.AntiAfk do
            try(function()
                local fe = Instance.new("BindableEvent")
                fe:Fire(); fe:Destroy()
            end)
            task.wait(50 + math.random() * 10)
        end
    end)
end

-- ══════════════════════════════════════
-- SECTION 12: GUI COLORS
-- ══════════════════════════════════════

local BG      = Color3.fromRGB(10,  10,  18)
local PANEL   = Color3.fromRGB(18,  20,  30)
local ACCENT  = Color3.fromRGB(110, 60,  240)
local ON_C    = Color3.fromRGB(50,  220, 110)
local OFF_C   = Color3.fromRGB(200, 55,  55)
local TEXT    = Color3.fromRGB(225, 225, 245)
local DIM     = Color3.fromRGB(130, 130, 155)
local BORDER  = Color3.fromRGB(55,  40,  90)

-- ══════════════════════════════════════
-- SECTION 13: GUI BUILD
-- ══════════════════════════════════════

local old = PGui:FindFirstChild("CAFE_ModMenu")
if old then old:Destroy() end

local SGui = Instance.new("ScreenGui")
SGui.Name           = "CAFE_ModMenu"
SGui.ResetOnSpawn   = false
SGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local ok = try(function() SGui.Parent = game:GetService("CoreGui") end)
if not ok or not SGui.Parent then SGui.Parent = PGui end

-- Main Frame
local Main = Instance.new("Frame")
Main.Size             = UDim2.new(0, 300, 0, 510)
Main.Position         = UDim2.new(0, 8, 0.5, -255)
Main.BackgroundColor3 = BG
Main.BorderSizePixel  = 0
Main.Parent           = SGui

local mc = Instance.new("UICorner"); mc.CornerRadius = UDim.new(0,12); mc.Parent = Main
local ms = Instance.new("UIStroke"); ms.Color = BORDER; ms.Thickness = 1.5; ms.Parent = Main

-- Title bar
local TBar = Instance.new("Frame")
TBar.Size             = UDim2.new(1, 0, 0, 44)
TBar.BackgroundColor3 = PANEL
TBar.BorderSizePixel  = 0
TBar.Parent           = Main

local tc  = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0,12); tc.Parent = TBar
local tfx = Instance.new("Frame")
tfx.Size = UDim2.new(1,0,0.5,0); tfx.Position = UDim2.new(0,0,0.5,0)
tfx.BackgroundColor3 = PANEL; tfx.BorderSizePixel = 0; tfx.Parent = TBar

local TL = Instance.new("TextLabel")
TL.Text = "🐾 Climb For Animals Eggs"
TL.Size = UDim2.new(1,-50,0,24); TL.Position = UDim2.new(0,12,0,6)
TL.BackgroundTransparency = 1; TL.TextColor3 = TEXT
TL.TextSize = 14; TL.Font = Enum.Font.GothamBold
TL.TextXAlignment = Enum.TextXAlignment.Left; TL.Parent = TBar

local SL = Instance.new("TextLabel")
SL.Text = "v3.0 Mobile | Delta"
SL.Size = UDim2.new(1,-12,0,14); SL.Position = UDim2.new(0,12,0,30)
SL.BackgroundTransparency = 1; SL.TextColor3 = DIM
SL.TextSize = 10; SL.Font = Enum.Font.Gotham
SL.TextXAlignment = Enum.TextXAlignment.Left; SL.Parent = Main

-- Hide btn
local HBtn = Instance.new("TextButton")
HBtn.Size = UDim2.new(0,32,0,32); HBtn.Position = UDim2.new(1,-40,0,6)
HBtn.BackgroundColor3 = ACCENT; HBtn.Text = "—"
HBtn.TextColor3 = TEXT; HBtn.TextSize = 16
HBtn.Font = Enum.Font.GothamBold; HBtn.BorderSizePixel = 0; HBtn.Parent = TBar
local hbc = Instance.new("UICorner"); hbc.CornerRadius = UDim.new(0,8); hbc.Parent = HBtn

-- Scroll
local Scr = Instance.new("ScrollingFrame")
Scr.Size = UDim2.new(1,-10,1,-58); Scr.Position = UDim2.new(0,5,0,52)
Scr.BackgroundTransparency = 1; Scr.BorderSizePixel = 0
Scr.ScrollBarThickness = 4; Scr.ScrollBarImageColor3 = ACCENT
Scr.CanvasSize = UDim2.new(0,0,0,0); Scr.Parent = Main

local Lay = Instance.new("UIListLayout")
Lay.Padding = UDim.new(0,5); Lay.Parent = Scr
Lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scr.CanvasSize = UDim2.new(0,0,0,Lay.AbsoluteContentSize.Y + 10)
end)

-- ── Section header ─────────────────────

local function sec(txt)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-6,0,22); f.BackgroundTransparency = 1; f.Parent = Scr
    local ln = Instance.new("Frame")
    ln.Size = UDim2.new(1,0,0,1); ln.Position = UDim2.new(0,0,0.5,0)
    ln.BackgroundColor3 = BORDER; ln.BorderSizePixel = 0; ln.Parent = f
    local lb = Instance.new("TextLabel")
    lb.Text = "  "..txt.."  "; lb.Size = UDim2.new(0,0,1,0)
    lb.AutomaticSize = Enum.AutomaticSize.X; lb.Position = UDim2.new(0,10,0,0)
    lb.BackgroundColor3 = BG; lb.TextColor3 = ACCENT
    lb.TextSize = 11; lb.Font = Enum.Font.GothamBold; lb.Parent = f
    return f
end

-- ── Toggle ────────────────────────────

local function tog(name, desc, onOn, onOff)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-6,0,56); f.BackgroundColor3 = PANEL
    f.BorderSizePixel = 0; f.Parent = Scr
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,8); fc.Parent = f
    local fs = Instance.new("UIStroke"); fs.Color = BORDER; fs.Thickness = 1; fs.Parent = f

    local nl = Instance.new("TextLabel")
    nl.Text = name; nl.Size = UDim2.new(1,-80,0,22); nl.Position = UDim2.new(0,10,0,6)
    nl.BackgroundTransparency = 1; nl.TextColor3 = TEXT
    nl.TextSize = 13; nl.Font = Enum.Font.GothamBold
    nl.TextXAlignment = Enum.TextXAlignment.Left; nl.Parent = f

    local dl = Instance.new("TextLabel")
    dl.Text = desc; dl.Size = UDim2.new(1,-80,0,18); dl.Position = UDim2.new(0,10,0,30)
    dl.BackgroundTransparency = 1; dl.TextColor3 = DIM
    dl.TextSize = 10; dl.Font = Enum.Font.Gotham
    dl.TextXAlignment = Enum.TextXAlignment.Left; dl.Parent = f

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0,62,0,30); btn.Position = UDim2.new(1,-72,0.5,-15)
    btn.BackgroundColor3 = OFF_C; btn.Text = "OFF"
    btn.TextColor3 = Color3.fromRGB(255,255,255); btn.TextSize = 12
    btn.Font = Enum.Font.GothamBold; btn.BorderSizePixel = 0; btn.Parent = f
    local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0,7); bc.Parent = btn

    local on = false
    btn.MouseButton1Click:Connect(function()
        on = not on
        if on then
            btn.Text = "ON"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = ON_C}):Play()
            try(onOn)
        else
            btn.Text = "OFF"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = OFF_C}):Play()
            try(onOff)
        end
    end)
    return f, btn
end

-- ── Slider ────────────────────────────

local function sld(lbl, mn, mx, def, cb)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,-6,0,64); f.BackgroundColor3 = PANEL
    f.BorderSizePixel = 0; f.Parent = Scr
    local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(0,8); fc.Parent = f
    local fs = Instance.new("UIStroke"); fs.Color = BORDER; fs.Thickness = 1; fs.Parent = f

    local nl = Instance.new("TextLabel")
    nl.Text = lbl; nl.Size = UDim2.new(1,-70,0,20); nl.Position = UDim2.new(0,10,0,6)
    nl.BackgroundTransparency = 1; nl.TextColor3 = TEXT
    nl.TextSize = 13; nl.Font = Enum.Font.GothamBold
    nl.TextXAlignment = Enum.TextXAlignment.Left; nl.Parent = f

    local vl = Instance.new("TextLabel")
    vl.Text = tostring(def); vl.Size = UDim2.new(0,55,0,20)
    vl.Position = UDim2.new(1,-65,0,6)
    vl.BackgroundTransparency = 1; vl.TextColor3 = ACCENT
    vl.TextSize = 13; vl.Font = Enum.Font.GothamBold
    vl.TextXAlignment = Enum.TextXAlignment.Right; vl.Parent = f

    local tr = Instance.new("Frame")
    tr.Size = UDim2.new(1,-20,0,8); tr.Position = UDim2.new(0,10,0,40)
    tr.BackgroundColor3 = BORDER; tr.BorderSizePixel = 0; tr.Parent = f
    local trc = Instance.new("UICorner"); trc.CornerRadius = UDim.new(1,0); trc.Parent = tr

    local pct0 = (def-mn)/(mx-mn)
    local fi = Instance.new("Frame")
    fi.BackgroundColor3 = ACCENT; fi.BorderSizePixel = 0
    fi.Size = UDim2.new(pct0,0,1,0); fi.Parent = tr
    local fic = Instance.new("UICorner"); fic.CornerRadius = UDim.new(1,0); fic.Parent = fi

    local kn = Instance.new("Frame")
    kn.Size = UDim2.new(0,18,0,18); kn.Position = UDim2.new(1,-9,0.5,-9)
    kn.BackgroundColor3 = Color3.fromRGB(255,255,255)
    kn.BorderSizePixel = 0; kn.ZIndex = 5; kn.Parent = fi
    local knc = Instance.new("UICorner"); knc.CornerRadius = UDim.new(1,0); knc.Parent = kn

    local drag = false
    local function upd(p)
        p = math.clamp(p,0,1)
        local v = math.floor(mn+(mx-mn)*p)
        fi.Size = UDim2.new(p,0,1,0)
        vl.Text = tostring(v)
        try(cb, v)
    end

    tr.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then drag = true end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
            upd((i.Position.X - tr.AbsolutePosition.X) / tr.AbsoluteSize.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then drag = false end
    end)
    return f
end

-- ══════════════════════════════════════
-- SECTION 14: MENU ITEMS
-- ══════════════════════════════════════

sec("🥚 ESP — البيض")

tog("Egg ESP",
    "يكشف البيض الحقيقية فقط — رتبة + كاش + حجم + مسافة",
    function()
        State.Esp = true
        scanAllEggs()
    end,
    function()
        State.Esp = false
        removeAllEsp()
    end
)

sec("🏃 الحركة")

tog("سرعة مخصصة", "تحكم في سرعتك — السلايدر أدناه",
    function() State.Speed = true;  enableSpeed() end,
    function() State.Speed = false; disableSpeed() end
)

sld("قيمة السرعة", 16, 250, 60, function(v)
    State.SpeedVal = v
end)

tog("قفز عالي", "قوة قفز × 2.4 — وصول للمناطق العليا",
    function() State.HighJump = true;  enableJump() end,
    function() State.HighJump = false; disableJump() end
)

tog("NoClip", "اخترق الجدران والعوائق",
    function() State.NoClip = true;  enableNoclip() end,
    function() State.NoClip = false; disableNoclip() end
)

tog("Fly — كاميرا", "تطير بالكاميرا",
    function() State.Fly = true;  enableFly() end,
    function() State.Fly = false; disableFly() end
)

sec("🤖 أوتو فارم")

tog("تجميع ذكي",
    "يذهب لأغلى بيضة في الماب — أولوية السعر",
    function() State.AutoFarm = true;  runAutoFarm() end,
    function() State.AutoFarm = false end
)

tog("Infinite Stamina", "طاقة لا تنتهي",
    function() State.InfStamina = true;  runInfStamina() end,
    function() State.InfStamina = false end
)

sec("⚙️ أدوات")

tog("Anti-AFK", "لا تُكيك",
    function() State.AntiAfk = true;  runAntiAfk() end,
    function() State.AntiAfk = false end
)

-- Padding
local pd = Instance.new("Frame")
pd.Size = UDim2.new(1,0,0,8); pd.BackgroundTransparency = 1; pd.Parent = Scr

-- ══════════════════════════════════════
-- SECTION 15: DRAG
-- ══════════════════════════════════════

local dagOn, dagSt, dagFr = false, nil, nil
TBar.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then
        dagOn = true; dagSt = i.Position; dagFr = Main.Position
    end
end)
UserInputService.InputChanged:Connect(function(i)
    if dagOn and (i.UserInputType == Enum.UserInputType.MouseMovement
    or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dagSt
        Main.Position = UDim2.new(
            dagFr.X.Scale, dagFr.X.Offset + d.X,
            dagFr.Y.Scale, dagFr.Y.Offset + d.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
    or i.UserInputType == Enum.UserInputType.Touch then dagOn = false end
end)

-- ══════════════════════════════════════
-- SECTION 16: HIDE BUTTON
-- ══════════════════════════════════════

local hidOn = false
HBtn.MouseButton1Click:Connect(function()
    hidOn = not hidOn
    if hidOn then
        TweenService:Create(Main, TweenInfo.new(0.3,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,300,0,44)}):Play()
        HBtn.Text = "+"
    else
        TweenService:Create(Main, TweenInfo.new(0.3,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,300,0,510)}):Play()
        HBtn.Text = "—"
    end
end)

-- ══════════════════════════════════════
-- SECTION 17: TOAST NOTIFICATION
-- ══════════════════════════════════════

local toast = Instance.new("Frame")
toast.Size = UDim2.new(0,270,0,50); toast.Position = UDim2.new(0.5,-135,0,-65)
toast.BackgroundColor3 = PANEL; toast.BorderSizePixel = 0; toast.Parent = SGui
local tc2 = Instance.new("UICorner"); tc2.CornerRadius = UDim.new(0,10); tc2.Parent = toast
local ts2 = Instance.new("UIStroke"); ts2.Color = ACCENT; ts2.Thickness = 1.5; ts2.Parent = toast
local tl2 = Instance.new("TextLabel")
tl2.Text = "🐾 v3.0 جاهز | ESP محسّن | فارم ذكي"
tl2.Size = UDim2.new(1,0,1,0); tl2.BackgroundTransparency = 1
tl2.TextColor3 = TEXT; tl2.TextSize = 12; tl2.Font = Enum.Font.GothamBold
tl2.TextXAlignment = Enum.TextXAlignment.Center; tl2.Parent = toast

TweenService:Create(toast, TweenInfo.new(0.5,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.new(0.5,-135,0,12)}):Play()
task.delay(3.5, function()
    TweenService:Create(toast, TweenInfo.new(0.4,Enum.EasingStyle.Quart),
        {Position=UDim2.new(0.5,-135,0,-65)}):Play()
    task.delay(0.5, function() try(function() toast:Destroy() end) end)
end)
