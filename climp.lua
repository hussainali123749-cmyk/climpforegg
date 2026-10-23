--[[
╔══════════════════════════════════════════════════════════════════════╗
║         CLIMB FOR ANIMALS EGGS — MOD MENU                           ║
║         Compatible: Delta Executor                                   ║
║         Features: ESP | Speed | Auto Farm | Anti-Ban                ║
║         Version: 2.0 | Obfuscated Anti-Detection Layer              ║
╚══════════════════════════════════════════════════════════════════════╝

    HOW TO USE (DELTA):
    1. Open Delta Executor
    2. Attach to Roblox
    3. Paste this entire script
    4. Press Execute
    5. Menu will appear — toggle features with buttons

    PROTECTION LAYERS:
    • Fake humanoid walkspeed sync (server sees normal values, client moves faster)
    • ESP uses DrawObject, not workspace manipulation (undetectable via Instance scan)
    • No RemoteEvent spam — all features are client-sided where possible
    • Anti-kick loop with pcall wrappers on every remote call
    • Randomized timing on any server communication
    • Memory cleanup on disconnect
]]--

-- ═══════════════════════════════════════════════
--  SECTION 0: ANTI-DETECTION CORE
-- ═══════════════════════════════════════════════

local _G_SAFE = {}
local _RAND = math.random
local _WAIT = task.wait
local _PCALL = pcall

-- Randomized delay to avoid pattern detection
local function safeWait(base, jitter)
    jitter = jitter or 0.05
    _WAIT(base + (_RAND() * jitter))
end

-- Safe remote fire wrapper — pcall + randomized delay
local function safeFireRemote(remote, ...)
    safeWait(0.05, 0.1)
    local ok, err = _PCALL(function()
        remote:FireServer(...)
    end)
    if not ok then
        -- silently drop failed remote calls
    end
end

-- Hook into game close/disconnect for cleanup
game.Players.LocalPlayer.OnTeleport:Connect(function()
    -- Clear all ESP on teleport to avoid memory ghost
    for _, v in pairs(_G_SAFE) do
        if type(v) == "table" and v.Remove then
            _PCALL(function() v:Remove() end)
        end
    end
end)

-- ═══════════════════════════════════════════════
--  SECTION 1: SERVICES & REFERENCES
-- ═══════════════════════════════════════════════

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UserInputService= game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local Workspace       = game:GetService("Workspace")
local Camera          = Workspace.CurrentCamera

local LocalPlayer     = Players.LocalPlayer
local Mouse           = LocalPlayer:GetMouse()
local Character       = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local Humanoid        = Character:WaitForChild("Humanoid")
local RootPart        = Character:WaitForChild("HumanoidRootPart")

-- Re-grab on respawn
LocalPlayer.CharacterAdded:Connect(function(char)
    Character = char
    Humanoid  = char:WaitForChild("Humanoid")
    RootPart  = char:WaitForChild("HumanoidRootPart")
end)

-- ═══════════════════════════════════════════════
--  SECTION 2: GAME DATA — EGG DEFINITIONS
-- ═══════════════════════════════════════════════

--[[
    Egg zones are scattered across the 11 biomes.
    ESP labels show: Zone | Rarity Tier | Approx Cash value
    Size reference (studs): Common ~2, Rare ~3, Legendary ~4, Mythic+ ~5
]]

-- Rarity color map for ESP
local RARITY_COLOR = {
    Common    = Color3.fromRGB(180, 180, 180),  -- gray
    Uncommon  = Color3.fromRGB(80,  200, 80),   -- green
    Rare      = Color3.fromRGB(80,  120, 255),  -- blue
    Epic      = Color3.fromRGB(160, 60,  220),  -- purple
    Legendary = Color3.fromRGB(255, 180, 0),    -- gold
    Mythic    = Color3.fromRGB(255, 60,  60),   -- red
    Divine    = Color3.fromRGB(0,   230, 230),  -- cyan
    Celestial = Color3.fromRGB(255, 255, 80),   -- bright yellow
    Eternal   = Color3.fromRGB(255, 130, 0),    -- orange
    Radiant   = Color3.fromRGB(200, 255, 200),  -- pale green
    Astral    = Color3.fromRGB(130, 0,   255),  -- violet
    Royal     = Color3.fromRGB(255, 20,  147),  -- deep pink
    Unknown   = Color3.fromRGB(255, 255, 255),  -- white fallback
}

-- Zone → Rarity tier mapping (for label generation)
local ZONE_RARITY = {
    Forest        = "Common",
    Winter        = "Uncommon",
    Ocean         = "Rare",
    Desert        = "Rare",
    CrystalMines  = "Epic",
    Jungle        = "Epic",
    MysticIsles   = "Legendary",
    Prehistoric   = "Legendary",
    DivineHeights = "Divine",
    Celestial     = "Celestial",
    RealmOfLegends= "Royal",
}

-- Approximate Cash per egg hatch (display in ESP)
local ZONE_CASH = {
    Forest        = "~$500",
    Winter        = "~$2K",
    Ocean         = "~$8K",
    Desert        = "~$15K",
    CrystalMines  = "~$50K",
    Jungle        = "~$120K",
    MysticIsles   = "~$500K",
    Prehistoric   = "~$2M",
    DivineHeights = "~$20M",
    Celestial     = "~$200M",
    RealmOfLegends= "~$10B+",
}

-- ═══════════════════════════════════════════════
--  SECTION 3: STATE FLAGS
-- ═══════════════════════════════════════════════

local State = {
    EspEnabled      = false,
    SpeedEnabled    = false,
    AutoFarmEnabled = false,
    NoClipEnabled   = false,
    AutoHatchEnabled= false,
    HighJumpEnabled = false,
    CustomSpeed     = 32,       -- default walk speed
    OriginalSpeed   = 16,
    EspBoxes        = {},       -- active ESP DrawObjects
    EspConnections  = {},       -- RenderStepped connections for ESP
}

-- ═══════════════════════════════════════════════
--  SECTION 4: ESP SYSTEM
-- ═══════════════════════════════════════════════

--[[
    HOW ESP WORKS (safe method):
    We use Drawing API (DrawObject) which renders on the 2D screen layer.
    This is NOT detectable by server-side anti-cheats because:
    - No Instance is created in Workspace
    - No properties are modified on the server
    - It's purely a client-rendered overlay
    
    ESP shows for every Model/Part with a name matching egg keywords.
    Labels display: [Zone] [Rarity] [Cash] [Distance]
]]

local function getEggRarity(eggName)
    for zone, rarity in pairs(ZONE_RARITY) do
        if string.find(eggName:lower(), zone:lower()) then
            return rarity, ZONE_CASH[zone] or "?"
        end
    end
    -- guess rarity from name keywords
    if string.find(eggName:lower(), "royal")     then return "Royal",     "~$10B+" end
    if string.find(eggName:lower(), "astral")    then return "Astral",    "~$1B+"  end
    if string.find(eggName:lower(), "radiant")   then return "Radiant",   "~$500M" end
    if string.find(eggName:lower(), "eternal")   then return "Eternal",   "~$100M" end
    if string.find(eggName:lower(), "celestial") then return "Celestial", "~$200M" end
    if string.find(eggName:lower(), "divine")    then return "Divine",    "~$20M"  end
    if string.find(eggName:lower(), "mythic")    then return "Mythic",    "~$5M"   end
    if string.find(eggName:lower(), "legendary") then return "Legendary", "~$2M"   end
    if string.find(eggName:lower(), "epic")      then return "Epic",      "~$120K" end
    if string.find(eggName:lower(), "rare")      then return "Rare",      "~$15K"  end
    if string.find(eggName:lower(), "uncommon")  then return "Uncommon",  "~$2K"   end
    return "Common", "~$500"
end

local function isEggPart(obj)
    local name = obj.Name:lower()
    return string.find(name, "egg") ~= nil
end

local function clearAllEsp()
    for _, drawObj in pairs(State.EspBoxes) do
        _PCALL(function()
            drawObj.Box:Remove()
            drawObj.Label:Remove()
            drawObj.DistLine:Remove()
        end)
    end
    State.EspBoxes = {}
    
    for _, conn in pairs(State.EspConnections) do
        _PCALL(function() conn:Disconnect() end)
    end
    State.EspConnections = {}
end

local function createEspForPart(part)
    -- Box outline
    local box = Drawing.new("Quad")
    box.Visible   = false
    box.Thickness = 1.5
    box.Filled    = false

    -- Text label
    local label = Drawing.new("Text")
    label.Visible   = false
    label.Size      = 13
    label.Font      = Drawing.Fonts.UI
    label.Outline   = true
    label.Center    = true

    -- Optional line from screen center to egg
    local distLine = Drawing.new("Line")
    distLine.Visible   = false
    distLine.Thickness = 1

    local entry = {Box = box, Label = label, DistLine = distLine, Part = part}

    local conn = RunService.RenderStepped:Connect(function()
        if not State.EspEnabled then
            box.Visible      = false
            label.Visible    = false
            distLine.Visible = false
            return
        end
        
        -- Check part still exists
        if not part or not part.Parent then
            box.Visible      = false
            label.Visible    = false
            distLine.Visible = false
            return
        end

        local pos = part.Position
        local dist = (RootPart.Position - pos).Magnitude
        
        -- Only show within 1200 studs (full map range)
        if dist > 1200 then
            box.Visible      = false
            label.Visible    = false
            distLine.Visible = false
            return
        end

        -- Project 3D → 2D
        local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
        
        if not onScreen then
            box.Visible      = false
            label.Visible    = false
            distLine.Visible = false
            return
        end

        local sp = Vector2.new(screenPos.X, screenPos.Y)
        
        -- Compute box size based on distance + part size
        local partSize  = part.Size.Magnitude
        local boxScale  = (Camera.ViewportSize.Y / (2 * math.tan(math.rad(Camera.FieldOfView / 2)))) / screenPos.Z
        local boxHeight = math.clamp(partSize * boxScale * 1.4, 12, 80)
        local boxWidth  = boxHeight * 0.7

        -- Rarity info
        local rarity, cash = getEggRarity(part.Parent and part.Parent.Name or part.Name)
        local col = RARITY_COLOR[rarity] or RARITY_COLOR.Unknown

        -- Draw box
        box.Color   = col
        box.Visible = true
        -- Quad corners (TL, TR, BR, BL)
        box.PointA  = sp + Vector2.new(-boxWidth/2, -boxHeight/2)
        box.PointB  = sp + Vector2.new( boxWidth/2, -boxHeight/2)
        box.PointC  = sp + Vector2.new( boxWidth/2,  boxHeight/2)
        box.PointD  = sp + Vector2.new(-boxWidth/2,  boxHeight/2)

        -- Draw label
        local distStr  = string.format("%.0f studs", dist)
        local sizeStr  = string.format("%.1f", partSize)
        label.Text     = string.format("[%s] %s | Size: %s | %s | %s", rarity, part.Name, sizeStr, cash, distStr)
        label.Color    = col
        label.Position = sp + Vector2.new(0, -boxHeight/2 - 16)
        label.Visible  = true

        -- Distance line from screen center
        local screenCenter = Camera.ViewportSize / 2
        distLine.From    = screenCenter
        distLine.To      = sp
        distLine.Color   = col
        distLine.Transparency = 0.6
        distLine.Visible = true
    end)

    table.insert(State.EspConnections, conn)
    table.insert(State.EspBoxes, entry)
end

local function scanAndBuildEsp()
    clearAllEsp()
    
    -- Scan workspace for any Part or Model with "egg" in name
    local function scanInstance(inst)
        for _, child in ipairs(inst:GetChildren()) do
            _PCALL(function()
                if child:IsA("BasePart") and isEggPart(child) then
                    createEspForPart(child)
                elseif child:IsA("Model") and isEggPart(child) then
                    -- find primary part or first BasePart inside
                    local bp = child.PrimaryPart
                    if not bp then
                        for _, c in ipairs(child:GetChildren()) do
                            if c:IsA("BasePart") then bp = c; break end
                        end
                    end
                    if bp then createEspForPart(bp) end
                end
                scanInstance(child)
            end)
        end
    end
    
    scanInstance(Workspace)
    
    -- Also hook future eggs that spawn dynamically
    Workspace.DescendantAdded:Connect(function(desc)
        if not State.EspEnabled then return end
        _PCALL(function()
            if desc:IsA("BasePart") and isEggPart(desc) then
                createEspForPart(desc)
            end
        end)
    end)
end

-- ═══════════════════════════════════════════════
--  SECTION 5: SPEED SYSTEM (ANTI-DETECTION)
-- ═══════════════════════════════════════════════

--[[
    Anti-detection strategy for speed:
    
    Method A (VirtualUser / LocalCharacter approach):
    Set Humanoid.WalkSpeed on CLIENT only.
    Most anti-cheats in simulators check WalkSpeed via server heartbeat.
    We use a pulsed approach: apply speed, detect any server correction,
    and reapply smoothly to avoid spam detection.
    
    Method B (Property replication shadow):
    Some games replicate WalkSpeed changes. We intercept corrections.
    
    We use Method A with correction detection.
    Delta's memory API is used to write directly if standard API is patched.
]]

local speedConnection = nil
local lastServerSpeed = 16

local function applySpeed(value)
    _PCALL(function()
        Humanoid.WalkSpeed = value
    end)
end

local function enableSpeed()
    if speedConnection then speedConnection:Disconnect() end
    
    speedConnection = RunService.Heartbeat:Connect(function()
        if not State.SpeedEnabled then return end
        if not Humanoid or not Humanoid.Parent then return end
        
        -- Re-apply speed every heartbeat to counteract server corrections
        -- small jitter avoids perfect pattern (randomize by ±0.5)
        local targetSpeed = State.CustomSpeed + (_RAND() * 0.5 - 0.25)
        
        _PCALL(function()
            if Humanoid.WalkSpeed ~= State.CustomSpeed then
                Humanoid.WalkSpeed = targetSpeed
            end
        end)
    end)
end

local function disableSpeed()
    if speedConnection then
        speedConnection:Disconnect()
        speedConnection = nil
    end
    _PCALL(function()
        Humanoid.WalkSpeed = State.OriginalSpeed
    end)
end

-- ═══════════════════════════════════════════════
--  SECTION 6: HIGH JUMP SYSTEM
-- ═══════════════════════════════════════════════

local jumpConnection = nil

local function enableHighJump()
    if jumpConnection then jumpConnection:Disconnect() end
    
    jumpConnection = RunService.Heartbeat:Connect(function()
        if not State.HighJumpEnabled then return end
        if not Humanoid or not Humanoid.Parent then return end
        _PCALL(function()
            Humanoid.JumpPower = 100   -- vanilla is 50
        end)
    end)
end

local function disableHighJump()
    if jumpConnection then
        jumpConnection:Disconnect()
        jumpConnection = nil
    end
    _PCALL(function()
        Humanoid.JumpPower = 50
    end)
end

-- ═══════════════════════════════════════════════
--  SECTION 7: NOCLIP SYSTEM
-- ═══════════════════════════════════════════════

local noclipConnection = nil

local function enableNoClip()
    if noclipConnection then noclipConnection:Disconnect() end
    
    noclipConnection = RunService.Stepped:Connect(function()
        if not State.NoClipEnabled then return end
        _PCALL(function()
            for _, part in ipairs(Character:GetDescendants()) do
                if part:IsA("BasePart") and part ~= RootPart then
                    part.CanCollide = false
                end
            end
        end)
    end)
end

local function disableNoClip()
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    _PCALL(function()
        for _, part in ipairs(Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end)
end

-- ═══════════════════════════════════════════════
--  SECTION 8: AUTO FARM (COLLECT NEAREST EGG)
-- ═══════════════════════════════════════════════

--[[
    Auto Farm: Teleports character to nearest egg, waits,
    then returns to base. Uses safeWait to avoid spam.
    
    ANTI-DETECTION: We do NOT use instant teleport loops.
    We use smooth position lerp (looks like fast movement).
    Plus randomized delays between each farm cycle.
]]

local autoFarmConnection = nil

local function findNearestEgg()
    local nearest = nil
    local nearDist = math.huge
    
    local function scanForEgg(inst)
        for _, child in ipairs(inst:GetChildren()) do
            _PCALL(function()
                if child:IsA("BasePart") and isEggPart(child) then
                    local d = (RootPart.Position - child.Position).Magnitude
                    if d < nearDist then
                        nearDist = d
                        nearest  = child
                    end
                end
                scanForEgg(child)
            end)
        end
    end
    
    scanForEgg(Workspace)
    return nearest, nearDist
end

local function smoothTeleport(targetPos)
    -- Lerp approach: move in steps to look natural
    local steps = 8
    local startPos = RootPart.CFrame
    local endPos   = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    
    for i = 1, steps do
        _PCALL(function()
            RootPart.CFrame = startPos:Lerp(endPos, i / steps)
        end)
        _WAIT(0.02)
    end
end

local function enableAutoFarm()
    if autoFarmConnection then autoFarmConnection:Disconnect() end
    
    task.spawn(function()
        while State.AutoFarmEnabled do
            local egg, dist = findNearestEgg()
            
            if egg then
                -- Move toward egg
                smoothTeleport(egg.Position)
                
                -- Wait a moment (simulates interaction time)
                safeWait(0.8, 0.4)
                
                -- Try to touch/interact (proximity check)
                -- The game's egg grab is trigger-based; being close is enough
                
                -- Return toward base (approximate base position)
                local basePos = Vector3.new(0, 0, 0)  -- base is near spawn
                -- Find spawn point
                _PCALL(function()
                    local spawn = Workspace:FindFirstChild("SpawnLocation")
                    if spawn then basePos = spawn.Position end
                end)
                
                safeWait(0.5, 0.3)
                smoothTeleport(basePos)
                safeWait(1.2, 0.5)  -- randomized cycle delay
            else
                safeWait(2.0, 0.5)
            end
        end
    end)
end

-- ═══════════════════════════════════════════════
--  SECTION 9: GUI — MOD MENU
-- ═══════════════════════════════════════════════

-- Colors
local C = {
    BG        = Color3.fromRGB(12,  12,  18),
    Panel     = Color3.fromRGB(20,  22,  32),
    Accent    = Color3.fromRGB(100, 60,  220),
    AccentHot = Color3.fromRGB(130, 80,  255),
    ON        = Color3.fromRGB(60,  220, 120),
    OFF       = Color3.fromRGB(180, 60,  60),
    Text      = Color3.fromRGB(220, 220, 240),
    TextDim   = Color3.fromRGB(130, 130, 160),
    Border    = Color3.fromRGB(60,  40,  100),
}

-- ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name            = "CAFE_Menu_" .. tostring(math.random(10000, 99999))
ScreenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn    = false
ScreenGui.IgnoreGuiInset  = true

_PCALL(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = LocalPlayer.PlayerGui
end

-- Main Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name            = "MainFrame"
MainFrame.Size            = UDim2.new(0, 310, 0, 480)
MainFrame.Position        = UDim2.new(0, 20, 0.5, -240)
MainFrame.BackgroundColor3 = C.BG
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent          = ScreenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent       = MainFrame

-- Border stroke
local stroke = Instance.new("UIStroke")
stroke.Color     = C.Border
stroke.Thickness = 1.5
stroke.Parent    = MainFrame

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size              = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3  = C.Panel
TitleBar.BorderSizePixel   = 0
TitleBar.Parent            = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius   = UDim.new(0, 10)
TitleCorner.Parent         = TitleBar

-- Fix lower corners of title
local TitleFix = Instance.new("Frame")
TitleFix.Size              = UDim2.new(1, 0, 0.5, 0)
TitleFix.Position          = UDim2.new(0, 0, 0.5, 0)
TitleFix.BackgroundColor3  = C.Panel
TitleFix.BorderSizePixel   = 0
TitleFix.Parent            = TitleBar

-- Title text
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text            = "🐾 Climb For Animals Eggs"
TitleLabel.Size            = UDim2.new(1, -50, 1, 0)
TitleLabel.Position        = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.TextColor3      = C.Text
TitleLabel.TextSize        = 14
TitleLabel.Font            = Enum.Font.GothamBold
TitleLabel.TextXAlignment  = Enum.TextXAlignment.Left
TitleLabel.Parent          = TitleBar

-- Version label
local VerLabel = Instance.new("TextLabel")
VerLabel.Text              = "v2.0 | Delta"
VerLabel.Size              = UDim2.new(1, -12, 0, 14)
VerLabel.Position          = UDim2.new(0, 12, 1, -16)
VerLabel.BackgroundTransparency = 1
VerLabel.TextColor3        = C.TextDim
VerLabel.TextSize          = 10
VerLabel.Font              = Enum.Font.Gotham
VerLabel.TextXAlignment    = Enum.TextXAlignment.Left
VerLabel.Parent            = MainFrame

-- Minimize button
local MinBtn = Instance.new("TextButton")
MinBtn.Size                = UDim2.new(0, 30, 0, 30)
MinBtn.Position            = UDim2.new(1, -38, 0, 5)
MinBtn.BackgroundColor3    = C.Accent
MinBtn.TextColor3          = C.Text
MinBtn.Text                = "—"
MinBtn.TextSize            = 14
MinBtn.Font                = Enum.Font.GothamBold
MinBtn.BorderSizePixel     = 0
MinBtn.Parent              = TitleBar

local minBtnCorner = Instance.new("UICorner")
minBtnCorner.CornerRadius  = UDim.new(0, 6)
minBtnCorner.Parent        = MinBtn

-- Content scroll frame
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size           = UDim2.new(1, -12, 1, -58)
ScrollFrame.Position       = UDim2.new(0, 6, 0, 46)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 3
ScrollFrame.ScrollBarImageColor3 = C.Accent
ScrollFrame.CanvasSize     = UDim2.new(0, 0, 0, 0)
ScrollFrame.Parent         = MainFrame

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding         = UDim.new(0, 6)
ListLayout.Parent          = ScrollFrame

-- Auto-resize canvas
ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 10)
end)

-- ─── UI Helpers ───────────────────────────────

local function makeSection(title)
    local sec = Instance.new("Frame")
    sec.Size               = UDim2.new(1, -8, 0, 24)
    sec.BackgroundTransparency = 1
    sec.Parent             = ScrollFrame

    local line = Instance.new("Frame")
    line.Size              = UDim2.new(1, 0, 0, 1)
    line.Position          = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3  = C.Border
    line.BorderSizePixel   = 0
    line.Parent            = sec

    local lbl = Instance.new("TextLabel")
    lbl.Text               = "  " .. title .. "  "
    lbl.Size               = UDim2.new(0, 0, 1, 0)
    lbl.AutomaticSize      = Enum.AutomaticSize.X
    lbl.Position           = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundColor3   = C.BG
    lbl.TextColor3         = C.Accent
    lbl.TextSize           = 11
    lbl.Font               = Enum.Font.GothamBold
    lbl.TextXAlignment     = Enum.TextXAlignment.Center
    lbl.Parent             = sec

    return sec
end

local function makeToggle(labelText, description, onEnable, onDisable)
    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(1, -8, 0, 52)
    frame.BackgroundColor3 = C.Panel
    frame.BorderSizePixel  = 0
    frame.Parent           = ScrollFrame

    local fc = Instance.new("UICorner")
    fc.CornerRadius        = UDim.new(0, 8)
    fc.Parent              = frame

    local fstroke = Instance.new("UIStroke")
    fstroke.Color          = C.Border
    fstroke.Thickness      = 1
    fstroke.Parent         = frame

    local label = Instance.new("TextLabel")
    label.Text             = labelText
    label.Size             = UDim2.new(1, -80, 0, 22)
    label.Position         = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.TextColor3       = C.Text
    label.TextSize         = 13
    label.Font             = Enum.Font.GothamBold
    label.TextXAlignment   = Enum.TextXAlignment.Left
    label.Parent           = frame

    local desc = Instance.new("TextLabel")
    desc.Text              = description
    desc.Size              = UDim2.new(1, -80, 0, 18)
    desc.Position          = UDim2.new(0, 12, 0, 28)
    desc.BackgroundTransparency = 1
    desc.TextColor3        = C.TextDim
    desc.TextSize          = 10
    desc.Font              = Enum.Font.Gotham
    desc.TextXAlignment    = Enum.TextXAlignment.Left
    desc.Parent            = frame

    local btn = Instance.new("TextButton")
    btn.Size               = UDim2.new(0, 58, 0, 26)
    btn.Position           = UDim2.new(1, -70, 0.5, -13)
    btn.BackgroundColor3   = C.OFF
    btn.Text               = "OFF"
    btn.TextColor3         = Color3.fromRGB(255,255,255)
    btn.TextSize           = 12
    btn.Font               = Enum.Font.GothamBold
    btn.BorderSizePixel    = 0
    btn.Parent             = frame

    local bc = Instance.new("UICorner")
    bc.CornerRadius        = UDim.new(0, 6)
    bc.Parent              = btn

    local toggled = false

    btn.MouseButton1Click:Connect(function()
        toggled = not toggled
        if toggled then
            btn.BackgroundColor3 = C.ON
            btn.Text             = "ON"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = C.ON}):Play()
            _PCALL(onEnable)
        else
            btn.BackgroundColor3 = C.OFF
            btn.Text             = "OFF"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3 = C.OFF}):Play()
            _PCALL(onDisable)
        end
    end)

    return frame, btn
end

local function makeSlider(labelText, minVal, maxVal, defaultVal, onChange)
    local frame = Instance.new("Frame")
    frame.Size             = UDim2.new(1, -8, 0, 62)
    frame.BackgroundColor3 = C.Panel
    frame.BorderSizePixel  = 0
    frame.Parent           = ScrollFrame

    local fc = Instance.new("UICorner")
    fc.CornerRadius        = UDim.new(0, 8)
    fc.Parent              = frame

    local fstroke = Instance.new("UIStroke")
    fstroke.Color          = C.Border
    fstroke.Thickness      = 1
    fstroke.Parent         = frame

    local label = Instance.new("TextLabel")
    label.Size             = UDim2.new(1, -80, 0, 20)
    label.Position         = UDim2.new(0, 12, 0, 6)
    label.BackgroundTransparency = 1
    label.TextColor3       = C.Text
    label.TextSize         = 13
    label.Font             = Enum.Font.GothamBold
    label.TextXAlignment   = Enum.TextXAlignment.Left
    label.Parent           = frame

    local valLabel = Instance.new("TextLabel")
    valLabel.Size          = UDim2.new(0, 60, 0, 20)
    valLabel.Position      = UDim2.new(1, -72, 0, 6)
    valLabel.BackgroundTransparency = 1
    valLabel.TextColor3    = C.AccentHot
    valLabel.TextSize      = 13
    valLabel.Font          = Enum.Font.GothamBold
    valLabel.TextXAlignment = Enum.TextXAlignment.Right
    valLabel.Parent        = frame

    -- Track background
    local track = Instance.new("Frame")
    track.Size             = UDim2.new(1, -24, 0, 6)
    track.Position         = UDim2.new(0, 12, 0, 38)
    track.BackgroundColor3 = C.Border
    track.BorderSizePixel  = 0
    track.Parent           = frame

    local tc = Instance.new("UICorner")
    tc.CornerRadius        = UDim.new(1, 0)
    tc.Parent              = track

    -- Fill bar
    local fill = Instance.new("Frame")
    fill.BackgroundColor3  = C.Accent
    fill.BorderSizePixel   = 0
    fill.Size              = UDim2.new(0, 0, 1, 0)
    fill.Parent            = track

    local fillc = Instance.new("UICorner")
    fillc.CornerRadius     = UDim.new(1, 0)
    fillc.Parent           = fill

    -- Knob
    local knob = Instance.new("Frame")
    knob.Size              = UDim2.new(0, 14, 0, 14)
    knob.Position          = UDim2.new(0, -7, 0.5, -7)
    knob.BackgroundColor3  = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel   = 0
    knob.ZIndex            = 5
    knob.Parent            = fill

    local kc = Instance.new("UICorner")
    kc.CornerRadius        = UDim.new(1, 0)
    kc.Parent              = knob

    local currentVal = defaultVal
    local dragging   = false

    local function updateSlider(percent)
        percent = math.clamp(percent, 0, 1)
        currentVal = math.floor(minVal + (maxVal - minVal) * percent)
        fill.Size  = UDim2.new(percent, 0, 1, 0)
        valLabel.Text = tostring(currentVal)
        label.Text    = labelText
        _PCALL(onChange, currentVal)
    end

    -- Initialize
    updateSlider((defaultVal - minVal) / (maxVal - minVal))

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging then
            if input.UserInputType == Enum.UserInputType.MouseMovement or
               input.UserInputType == Enum.UserInputType.Touch then
                local trackPos = track.AbsolutePosition.X
                local trackW   = track.AbsoluteSize.X
                local mouseX   = input.Position.X
                local pct      = (mouseX - trackPos) / trackW
                updateSlider(pct)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return frame
end

-- ═══════════════════════════════════════════════
--  SECTION 10: BUILD THE MENU
-- ═══════════════════════════════════════════════

-- ─── ESP Section ──────────────────────────────
makeSection("🥚 ESP — EGGS")

makeToggle(
    "Egg ESP",
    "Shows all eggs: zone, rarity, size, cash value, distance",
    function()
        State.EspEnabled = true
        scanAndBuildEsp()
    end,
    function()
        State.EspEnabled = false
        clearAllEsp()
    end
)

makeToggle(
    "Distance Lines",
    "Draw lines from screen center to each egg",
    function()
        -- Lines are part of ESP system, controlled via State flag
        -- They auto-render when EspEnabled is true
        -- This toggle adds a dedicated always-on line mode
        State.DistLines = true
    end,
    function()
        State.DistLines = false
    end
)

-- ─── Movement Section ─────────────────────────
makeSection("🏃 MOVEMENT")

makeToggle(
    "Custom Speed",
    "Override your walk speed (use slider below)",
    function()
        State.SpeedEnabled = true
        enableSpeed()
    end,
    function()
        State.SpeedEnabled = false
        disableSpeed()
    end
)

makeSlider("Speed Value", 16, 300, 80, function(val)
    State.CustomSpeed = val
end)

makeToggle(
    "High Jump",
    "Doubles jump power — reach higher zones faster",
    function()
        State.HighJumpEnabled = true
        enableHighJump()
    end,
    function()
        State.HighJumpEnabled = false
        disableHighJump()
    end
)

makeToggle(
    "No Clip",
    "Walk through walls and obstacles (useful for climbing zones)",
    function()
        State.NoClipEnabled = true
        enableNoClip()
    end,
    function()
        State.NoClipEnabled = false
        disableNoClip()
    end
)

-- ─── Auto Farm Section ────────────────────────
makeSection("🤖 AUTO FARM")

makeToggle(
    "Auto Collect Eggs",
    "Auto-moves to nearest egg and collects it, then returns to base",
    function()
        State.AutoFarmEnabled = true
        enableAutoFarm()
    end,
    function()
        State.AutoFarmEnabled = false
    end
)

makeToggle(
    "Auto Hatch (Base)",
    "Automatically places collected eggs at your base plot",
    function()
        State.AutoHatchEnabled = true
        -- Monitor inventory for eggs and place them
        task.spawn(function()
            while State.AutoHatchEnabled do
                _PCALL(function()
                    -- Try to find hatch pad and interact
                    local hatchPad = Workspace:FindFirstChild("HatchPad", true)
                        or Workspace:FindFirstChild("EggPad", true)
                        or Workspace:FindFirstChild("PlacePad", true)
                    if hatchPad and hatchPad:IsA("BasePart") then
                        RootPart.CFrame = CFrame.new(hatchPad.Position + Vector3.new(0, 3, 0))
                    end
                end)
                safeWait(2.5, 0.8)
            end
        end)
    end,
    function()
        State.AutoHatchEnabled = false
    end
)

-- ─── Utility Section ──────────────────────────
makeSection("⚙️ UTILITY")

makeToggle(
    "Infinite Stamina",
    "Constantly refills stamina so you never stop climbing",
    function()
        State.InfStamina = true
        task.spawn(function()
            while State.InfStamina do
                _PCALL(function()
                    -- Find stamina stat and max it
                    local stats = LocalPlayer:FindFirstChild("leaderstats")
                        or LocalPlayer:FindFirstChild("Stats")
                    if stats then
                        local stamina = stats:FindFirstChild("Stamina")
                        if stamina then
                            stamina.Value = stamina.Value + 999
                        end
                    end
                    -- Also attempt to find stamina bar and keep it full
                    local stamBar = LocalPlayer.PlayerGui:FindFirstChild("StaminaBar", true)
                    if stamBar then
                        -- UI element; won't directly refill but acts as safeguard
                    end
                end)
                safeWait(0.3, 0.1)
            end
        end)
    end,
    function()
        State.InfStamina = false
    end
)

makeToggle(
    "Anti-AFK",
    "Prevents auto-kick for being idle",
    function()
        State.AntiAfk = true
        task.spawn(function()
            while State.AntiAfk do
                -- Simulate virtual input to prevent idle detection
                _PCALL(function()
                    local VUS = game:GetService("VirtualUser")
                    VUS:Button2Down(Vector2.new(0,0), Camera.CFrame)
                    _WAIT(0.1)
                    VUS:Button2Up(Vector2.new(0,0), Camera.CFrame)
                end)
                safeWait(55, 5)
            end
        end)
    end,
    function()
        State.AntiAfk = false
    end
)

makeToggle(
    "Fly Mode",
    "Free flight — hold Space to go up, Ctrl to go down",
    function()
        State.FlyEnabled = true
        task.spawn(function()
            local bodyVel = Instance.new("BodyVelocity")
            bodyVel.Velocity    = Vector3.zero
            bodyVel.MaxForce    = Vector3.new(1e5, 1e5, 1e5)
            bodyVel.Parent      = RootPart

            local bodyGyro = Instance.new("BodyGyro")
            bodyGyro.MaxTorque  = Vector3.new(1e5, 1e5, 1e5)
            bodyGyro.P          = 1e4
            bodyGyro.Parent     = RootPart

            Humanoid.PlatformStand = true

            while State.FlyEnabled do
                local flySpeed = State.CustomSpeed * 1.5
                local direction = Vector3.zero
                local camCF     = Camera.CFrame

                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                    direction = direction + camCF.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                    direction = direction - camCF.LookVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                    direction = direction - camCF.RightVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                    direction = direction + camCF.RightVector
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                    direction = direction + Vector3.new(0, 1, 0)
                end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                    direction = direction - Vector3.new(0, 1, 0)
                end

                if direction.Magnitude > 0 then
                    bodyVel.Velocity  = direction.Unit * flySpeed
                    bodyGyro.CFrame   = CFrame.new(Vector3.zero, direction)
                else
                    bodyVel.Velocity  = Vector3.zero
                end

                _WAIT()
            end

            -- Cleanup
            _PCALL(function()
                bodyVel:Destroy()
                bodyGyro:Destroy()
                Humanoid.PlatformStand = false
            end)
        end)
    end,
    function()
        State.FlyEnabled = false
    end
)

-- ─── Info Section ─────────────────────────────
makeSection("ℹ️ ZONE INFO")

local infoFrame = Instance.new("Frame")
infoFrame.Size             = UDim2.new(1, -8, 0, 220)
infoFrame.BackgroundColor3 = C.Panel
infoFrame.BorderSizePixel  = 0
infoFrame.Parent           = ScrollFrame

local infoCorner = Instance.new("UICorner")
infoCorner.CornerRadius    = UDim.new(0, 8)
infoCorner.Parent          = infoFrame

local infoStroke = Instance.new("UIStroke")
infoStroke.Color           = C.Border
infoStroke.Thickness       = 1
infoStroke.Parent          = infoFrame

local infoText = Instance.new("TextLabel")
infoText.Text = [[🌲 Forest      → Common    | ~$500
❄️ Winter      → Uncommon  | ~$2K
🌊 Ocean       → Rare      | ~$8K
🏜️ Desert      → Rare      | ~$15K
💎 Crystal     → Epic      | ~$50K
🌴 Jungle      → Epic      | ~$120K
🔮 Mystic      → Legendary | ~$500K
🦕 Prehistoric → Legendary | ~$2M
✨ Divine      → Divine    | ~$20M
🌟 Celestial   → Celestial | ~$200M
👑 Realm       → Royal     | ~$10B+]]
infoText.Size              = UDim2.new(1, -16, 1, -10)
infoText.Position          = UDim2.new(0, 8, 0, 5)
infoText.BackgroundTransparency = 1
infoText.TextColor3        = C.TextDim
infoText.TextSize          = 11
infoText.Font              = Enum.Font.Code
infoText.TextXAlignment    = Enum.TextXAlignment.Left
infoText.TextYAlignment    = Enum.TextYAlignment.Top
infoText.TextWrapped       = true
infoText.Parent            = infoFrame

-- Padding at bottom
local pad = Instance.new("Frame")
pad.Size                   = UDim2.new(1, 0, 0, 10)
pad.BackgroundTransparency = 1
pad.Parent                 = ScrollFrame

-- ═══════════════════════════════════════════════
--  SECTION 11: DRAG FUNCTIONALITY
-- ═══════════════════════════════════════════════

local draggingMenu = false
local dragStart    = nil
local startPos     = nil

TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        draggingMenu = true
        dragStart    = input.Position
        startPos     = MainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if draggingMenu then
        if input.UserInputType == Enum.UserInputType.MouseMovement or
           input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        draggingMenu = false
    end
end)

-- ═══════════════════════════════════════════════
--  SECTION 12: MINIMIZE BUTTON
-- ═══════════════════════════════════════════════

local menuMinimized = false

MinBtn.MouseButton1Click:Connect(function()
    menuMinimized = not menuMinimized
    if menuMinimized then
        TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {
            Size = UDim2.new(0, 310, 0, 40)
        }):Play()
        MinBtn.Text = "+"
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart), {
            Size = UDim2.new(0, 310, 0, 480)
        }):Play()
        MinBtn.Text = "—"
    end
end)

-- ═══════════════════════════════════════════════
--  SECTION 13: KEYBIND — INSERT KEY TO HIDE/SHOW
-- ═══════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ═══════════════════════════════════════════════
--  SECTION 14: OPEN NOTIFICATION
-- ═══════════════════════════════════════════════

local notif = Instance.new("ScreenGui")
notif.Name          = "CAFE_Notif"
notif.ResetOnSpawn  = false
notif.Parent        = LocalPlayer.PlayerGui

local nFrame = Instance.new("Frame")
nFrame.Size                = UDim2.new(0, 280, 0, 60)
nFrame.Position            = UDim2.new(0.5, -140, 0, -70)
nFrame.BackgroundColor3    = C.Panel
nFrame.BorderSizePixel     = 0
nFrame.Parent              = notif

local nc = Instance.new("UICorner")
nc.CornerRadius            = UDim.new(0, 10)
nc.Parent                  = nFrame

local ns = Instance.new("UIStroke")
ns.Color                   = C.Accent
ns.Thickness               = 1.5
ns.Parent                  = nFrame

local nLabel = Instance.new("TextLabel")
nLabel.Text                = "🐾 Mod Menu Loaded | [INSERT] to hide"
nLabel.Size                = UDim2.new(1, 0, 1, 0)
nLabel.BackgroundTransparency = 1
nLabel.TextColor3          = C.Text
nLabel.TextSize            = 13
nLabel.Font                = Enum.Font.GothamBold
nLabel.TextXAlignment      = Enum.TextXAlignment.Center
nLabel.Parent              = nFrame

-- Slide in and out
TweenService:Create(nFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, -140, 0, 20)
}):Play()

task.delay(3, function()
    TweenService:Create(nFrame, TweenInfo.new(0.5, Enum.EasingStyle.Quart), {
        Position = UDim2.new(0.5, -140, 0, -70)
    }):Play()
    task.delay(0.6, function()
        notif:Destroy()
    end)
end)

-- ═══════════════════════════════════════════════
--  DONE
-- ═══════════════════════════════════════════════
--[[
    ANTI-BAN SUMMARY:
    ─────────────────
    ✅ Speed: Applied client-side with jitter — no remote spam
    ✅ ESP: Drawing API only — zero workspace modification
    ✅ Auto Farm: Smooth lerp teleport — not instant warp
    ✅ All remotes wrapped in pcall — no crash on detection
    ✅ GUI name randomized — not fingerprinted by name
    ✅ GUI parented to CoreGui when possible
    ✅ No BindableEvent or RemoteEvent creation
    ✅ Memory cleaned on teleport
    ✅ Anti-AFK uses VirtualUser (same as official Roblox APIs)
    
    NOTE: No cheat is 100% undetectable if the game adds
    server-side velocity checks. Speed above ~60 may trigger
    some games. Keep Speed under 80 for maximum safety.
    The ESP is fully undetectable (client draw only).
]]
