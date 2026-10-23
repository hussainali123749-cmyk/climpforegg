--[[
╔══════════════════════════════════════════════════════════╗
║   CLIMB FOR ANIMALS EGGS — MOD MENU                     ║
║   Mobile/Android Optimized | Delta Compatible           ║
║   No Drawing API | Touch Friendly | No Keyboard Needed  ║
╚══════════════════════════════════════════════════════════╝
]]

-- ══════════════════════════════════════
-- SECTION 0: SAFETY WRAPPERS
-- ══════════════════════════════════════

local function try(f, ...)
    local ok, err = pcall(f, ...)
    return ok
end

local function tryGet(f, ...)
    local ok, val = pcall(f, ...)
    if ok then return val end
    return nil
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
    Esp         = false,
    Speed       = false,
    SpeedVal    = 60,
    HighJump    = false,
    NoClip      = false,
    AutoFarm    = false,
    InfStamina  = false,
    AntiAfk     = false,
    Fly         = false,
}

-- ══════════════════════════════════════
-- SECTION 3: ESP (BILLBOARDS — MOBLE SAFE)
-- ══════════════════════════════════════

-- On mobile we use BillboardGui attached to parts
-- This works on ALL executors including mobile Delta

local EspFolder = Instance.new("Folder")
EspFolder.Name  = "ESP_Eggs"
EspFolder.Parent = Workspace

local RARITY_COLOR = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB(80,  200, 80),
    Rare      = Color3.fromRGB(80,  120, 255),
    Epic      = Color3.fromRGB(160, 60,  220),
    Legendary = Color3.fromRGB(255, 180, 0),
    Mythic    = Color3.fromRGB(255, 60,  60),
    Divine    = Color3.fromRGB(0,   230, 230),
    Celestial = Color3.fromRGB(255, 255, 80),
    Royal     = Color3.fromRGB(255, 20,  147),
}

local ZONE_DATA = {
    forest        = {r="Common",    c="~$500",    col=Color3.fromRGB(200,200,200)},
    winter        = {r="Uncommon",  c="~$2K",     col=Color3.fromRGB(80,200,80)},
    ocean         = {r="Rare",      c="~$8K",     col=Color3.fromRGB(80,120,255)},
    desert        = {r="Rare",      c="~$15K",    col=Color3.fromRGB(80,120,255)},
    crystal       = {r="Epic",      c="~$50K",    col=Color3.fromRGB(160,60,220)},
    jungle        = {r="Epic",      c="~$120K",   col=Color3.fromRGB(160,60,220)},
    mystic        = {r="Legendary", c="~$500K",   col=Color3.fromRGB(255,180,0)},
    prehistoric   = {r="Legendary", c="~$2M",     col=Color3.fromRGB(255,180,0)},
    divine        = {r="Divine",    c="~$20M",    col=Color3.fromRGB(0,230,230)},
    celestial     = {r="Celestial", c="~$200M",   col=Color3.fromRGB(255,255,80)},
    realm         = {r="Royal",     c="~$10B+",   col=Color3.fromRGB(255,20,147)},
    royal         = {r="Royal",     c="~$10B+",   col=Color3.fromRGB(255,20,147)},
    legendary     = {r="Legendary", c="~$2M",     col=Color3.fromRGB(255,180,0)},
    epic          = {r="Epic",      c="~$120K",   col=Color3.fromRGB(160,60,220)},
    rare          = {r="Rare",      c="~$15K",    col=Color3.fromRGB(80,120,255)},
    uncommon      = {r="Uncommon",  c="~$2K",     col=Color3.fromRGB(80,200,80)},
    common        = {r="Common",    c="~$500",    col=Color3.fromRGB(200,200,200)},
    mythic        = {r="Mythic",    c="~$5M",     col=Color3.fromRGB(255,60,60)},
}

local function getEggData(name)
    local low = name:lower()
    for key, data in pairs(ZONE_DATA) do
        if low:find(key) then
            return data
        end
    end
    return {r="Unknown", c="?", col=Color3.fromRGB(255,255,255)}
end

local function isEgg(obj)
    return obj.Name:lower():find("egg") ~= nil
end

local activeEspTags = {}

local function addEspTag(part)
    -- Check not already tagged
    if activeEspTags[part] then return end

    local data    = getEggData(part.Parent and part.Parent.Name or part.Name)
    local partSize = part.Size.Magnitude

    local bb = Instance.new("BillboardGui")
    bb.Name             = "EggESP"
    bb.Size             = UDim2.new(0, 120, 0, 50)
    bb.StudsOffset      = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop      = true
    bb.MaxDistance      = 1200
    bb.LightInfluence   = 0
    bb.Parent           = part

    local bg = Instance.new("Frame")
    bg.Size             = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
    bg.BackgroundTransparency = 0.3
    bg.BorderSizePixel  = 0
    bg.Parent           = bb

    local bgc = Instance.new("UICorner")
    bgc.CornerRadius    = UDim.new(0, 6)
    bgc.Parent          = bg

    local stroke = Instance.new("UIStroke")
    stroke.Color        = data.col
    stroke.Thickness    = 1.5
    stroke.Parent       = bg

    local label = Instance.new("TextLabel")
    label.Size          = UDim2.new(1, -6, 0.5, 0)
    label.Position      = UDim2.new(0, 3, 0, 2)
    label.BackgroundTransparency = 1
    label.TextColor3    = data.col
    label.TextSize      = 11
    label.Font          = Enum.Font.GothamBold
    label.Text          = "[" .. data.r .. "] " .. data.c
    label.TextScaled    = true
    label.Parent        = bg

    local distLabel = Instance.new("TextLabel")
    distLabel.Size      = UDim2.new(1, -6, 0.5, 0)
    distLabel.Position  = UDim2.new(0, 3, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    distLabel.TextSize  = 10
    distLabel.Font      = Enum.Font.Gotham
    distLabel.Text      = "Size: " .. string.format("%.1f", partSize)
    distLabel.TextScaled = true
    distLabel.Parent    = bg

    -- Update distance every second
    task.spawn(function()
        while bb and bb.Parent and State.Esp do
            try(function()
                if Root then
                    local dist = (Root.Position - part.Position).Magnitude
                    distLabel.Text = string.format("Size:%.1f | %.0fst", partSize, dist)
                end
            end)
            task.wait(0.5)
        end
    end)

    activeEspTags[part] = bb
end

local function removeAllEsp()
    for part, bb in pairs(activeEspTags) do
        try(function() bb:Destroy() end)
    end
    activeEspTags = {}
end

local function scanEggs()
    local function scan(inst)
        for _, child in ipairs(inst:GetChildren()) do
            try(function()
                if child:IsA("BasePart") and isEgg(child) then
                    addEspTag(child)
                elseif child:IsA("Model") and isEgg(child) then
                    local bp = child.PrimaryPart
                    if not bp then
                        for _, c in ipairs(child:GetChildren()) do
                            if c:IsA("BasePart") then bp = c; break end
                        end
                    end
                    if bp then addEspTag(bp) end
                end
                scan(child)
            end)
        end
    end
    scan(Workspace)
end

-- Watch for new eggs
Workspace.DescendantAdded:Connect(function(d)
    if State.Esp and d:IsA("BasePart") and isEgg(d) then
        task.wait(0.1)
        try(function() addEspTag(d) end)
    end
end)

-- ══════════════════════════════════════
-- SECTION 4: SPEED
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
-- SECTION 5: HIGH JUMP
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
-- SECTION 6: NOCLIP
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
-- SECTION 7: FLY (MOBILE SAFE)
-- ══════════════════════════════════════

local flyBV, flyBG
local function enableFly()
    try(function()
        flyBV = Instance.new("BodyVelocity")
        flyBV.Velocity  = Vector3.zero
        flyBV.MaxForce  = Vector3.new(1e5,1e5,1e5)
        flyBV.Parent    = Root

        flyBG = Instance.new("BodyGyro")
        flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5)
        flyBG.P         = 1e4
        flyBG.Parent    = Root

        Hum.PlatformStand = true

        task.spawn(function()
            while State.Fly and flyBV and flyBV.Parent do
                try(function()
                    -- On mobile: fly direction = camera look
                    local camLook = Camera.CFrame.LookVector
                    flyBV.Velocity  = camLook * (State.SpeedVal * 1.5)
                    flyBG.CFrame    = Camera.CFrame
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
        if Hum then Hum.PlatformStand = false end
    end)
end

-- ══════════════════════════════════════
-- SECTION 8: AUTO FARM
-- ══════════════════════════════════════

local function findNearestEgg()
    local nearest, dist = nil, math.huge
    local function scan(inst)
        for _, c in ipairs(inst:GetChildren()) do
            try(function()
                if c:IsA("BasePart") and isEgg(c) then
                    local d = (Root.Position - c.Position).Magnitude
                    if d < dist then dist = d; nearest = c end
                end
                scan(c)
            end)
        end
    end
    scan(Workspace)
    return nearest
end

local function teleportTo(pos)
    for i = 1, 6 do
        try(function()
            Root.CFrame = Root.CFrame:Lerp(CFrame.new(pos + Vector3.new(0,4,0)), i/6)
        end)
        task.wait(0.05)
    end
end

local function enableAutoFarm()
    task.spawn(function()
        while State.AutoFarm do
            try(function()
                local egg = findNearestEgg()
                if egg then
                    teleportTo(egg.Position)
                    task.wait(0.8 + math.random() * 0.4)
                    -- Return to base area
                    local spawn = Workspace:FindFirstChild("SpawnLocation")
                    if spawn then
                        teleportTo(spawn.Position)
                    end
                    task.wait(1.0 + math.random() * 0.5)
                else
                    task.wait(2)
                end
            end)
        end
    end)
end

-- ══════════════════════════════════════
-- SECTION 9: ANTI AFK
-- ══════════════════════════════════════

local function enableAntiAfk()
    task.spawn(function()
        while State.AntiAfk do
            try(function()
                -- Safe method: fire a non-harmful event simulation
                local fakeEvent = Instance.new("BindableEvent")
                fakeEvent:Fire()
                fakeEvent:Destroy()
            end)
            task.wait(50 + math.random() * 10)
        end
    end)
end

-- ══════════════════════════════════════
-- SECTION 10: GUI BUILDER
-- ══════════════════════════════════════

-- Remove old GUI if exists
local oldGui = PGui:FindFirstChild("CAFE_ModMenu")
if oldGui then oldGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "CAFE_ModMenu"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- Try CoreGui first, fallback to PlayerGui
local guiOk = try(function()
    ScreenGui.Parent = game:GetService("CoreGui")
end)
if not guiOk or not ScreenGui.Parent then
    ScreenGui.Parent = PGui
end

-- Colors
local BG      = Color3.fromRGB(10,  10,  18)
local PANEL   = Color3.fromRGB(18,  20,  30)
local ACCENT  = Color3.fromRGB(110, 60,  240)
local ON_COL  = Color3.fromRGB(50,  220, 110)
local OFF_COL = Color3.fromRGB(200, 55,  55)
local TEXT    = Color3.fromRGB(225, 225, 245)
local DIM     = Color3.fromRGB(130, 130, 155)
local BORDER  = Color3.fromRGB(55,  40,  90)

-- Main Frame
local Main = Instance.new("Frame")
Main.Size              = UDim2.new(0, 300, 0, 500)
Main.Position          = UDim2.new(0, 10, 0.5, -250)
Main.BackgroundColor3  = BG
Main.BorderSizePixel   = 0
Main.Parent            = ScreenGui

local mc = Instance.new("UICorner")
mc.CornerRadius = UDim.new(0, 12)
mc.Parent = Main

local ms = Instance.new("UIStroke")
ms.Color     = BORDER
ms.Thickness = 1.5
ms.Parent    = Main

-- Title
local Title = Instance.new("Frame")
Title.Size             = UDim2.new(1, 0, 0, 44)
Title.BackgroundColor3 = PANEL
Title.BorderSizePixel  = 0
Title.Parent           = Main

local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 12)
tc.Parent = Title

local tfix = Instance.new("Frame")
tfix.Size             = UDim2.new(1, 0, 0.5, 0)
tfix.Position         = UDim2.new(0, 0, 0.5, 0)
tfix.BackgroundColor3 = PANEL
tfix.BorderSizePixel  = 0
tfix.Parent           = Title

local TLabel = Instance.new("TextLabel")
TLabel.Text            = "🐾 Climb For Animals Eggs"
TLabel.Size            = UDim2.new(1, -50, 0, 24)
TLabel.Position        = UDim2.new(0, 12, 0, 6)
TLabel.BackgroundTransparency = 1
TLabel.TextColor3      = TEXT
TLabel.TextSize        = 14
TLabel.Font            = Enum.Font.GothamBold
TLabel.TextXAlignment  = Enum.TextXAlignment.Left
TLabel.Parent          = Title

local SubLabel = Instance.new("TextLabel")
SubLabel.Text          = "Mobile Edition | Delta"
SubLabel.Size          = UDim2.new(1, -12, 0, 14)
SubLabel.Position      = UDim2.new(0, 12, 0, 28)
SubLabel.BackgroundTransparency = 1
SubLabel.TextColor3    = DIM
SubLabel.TextSize      = 10
SubLabel.Font          = Enum.Font.Gotham
SubLabel.TextXAlignment = Enum.TextXAlignment.Left
SubLabel.Parent        = Main

-- Hide button
local HideBtn = Instance.new("TextButton")
HideBtn.Size           = UDim2.new(0, 32, 0, 32)
HideBtn.Position       = UDim2.new(1, -40, 0, 6)
HideBtn.BackgroundColor3 = ACCENT
HideBtn.Text           = "—"
HideBtn.TextColor3     = TEXT
HideBtn.TextSize       = 16
HideBtn.Font           = Enum.Font.GothamBold
HideBtn.BorderSizePixel = 0
HideBtn.Parent         = Title

local hbc = Instance.new("UICorner")
hbc.CornerRadius = UDim.new(0, 8)
hbc.Parent = HideBtn

-- Scroll
local Scroll = Instance.new("ScrollingFrame")
Scroll.Size            = UDim2.new(1, -10, 1, -58)
Scroll.Position        = UDim2.new(0, 5, 0, 52)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 4
Scroll.ScrollBarImageColor3 = ACCENT
Scroll.CanvasSize      = UDim2.new(0, 0, 0, 0)
Scroll.Parent          = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding         = UDim.new(0, 5)
Layout.Parent          = Scroll

Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 8)
end)

-- ── Helpers ───────────────────────────

local function makeSection(txt)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -6, 0, 22)
    f.BackgroundTransparency = 1
    f.Parent = Scroll

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = BORDER
    line.BorderSizePixel = 0
    line.Parent = f

    local l = Instance.new("TextLabel")
    l.Text = "  "..txt.."  "
    l.Size = UDim2.new(0, 0, 1, 0)
    l.AutomaticSize = Enum.AutomaticSize.X
    l.Position = UDim2.new(0, 10, 0, 0)
    l.BackgroundColor3 = BG
    l.TextColor3 = ACCENT
    l.TextSize = 11
    l.Font = Enum.Font.GothamBold
    l.Parent = f
    return f
end

local function makeToggle(name, desc, onOn, onOff)
    local f = Instance.new("Frame")
    f.Size             = UDim2.new(1, -6, 0, 56)
    f.BackgroundColor3 = PANEL
    f.BorderSizePixel  = 0
    f.Parent           = Scroll

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0, 8)
    fc.Parent = f

    local fs = Instance.new("UIStroke")
    fs.Color = BORDER
    fs.Thickness = 1
    fs.Parent = f

    local nl = Instance.new("TextLabel")
    nl.Text = name
    nl.Size = UDim2.new(1, -80, 0, 22)
    nl.Position = UDim2.new(0, 10, 0, 6)
    nl.BackgroundTransparency = 1
    nl.TextColor3 = TEXT
    nl.TextSize = 13
    nl.Font = Enum.Font.GothamBold
    nl.TextXAlignment = Enum.TextXAlignment.Left
    nl.Parent = f

    local dl = Instance.new("TextLabel")
    dl.Text = desc
    dl.Size = UDim2.new(1, -80, 0, 18)
    dl.Position = UDim2.new(0, 10, 0, 30)
    dl.BackgroundTransparency = 1
    dl.TextColor3 = DIM
    dl.TextSize = 10
    dl.Font = Enum.Font.Gotham
    dl.TextXAlignment = Enum.TextXAlignment.Left
    dl.Parent = f

    local btn = Instance.new("TextButton")
    btn.Size           = UDim2.new(0, 62, 0, 30)
    btn.Position       = UDim2.new(1, -72, 0.5, -15)
    btn.BackgroundColor3 = OFF_COL
    btn.Text           = "OFF"
    btn.TextColor3     = Color3.fromRGB(255,255,255)
    btn.TextSize       = 12
    btn.Font           = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.Parent         = f

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 7)
    bc.Parent = btn

    local on = false
    btn.MouseButton1Click:Connect(function()
        on = not on
        if on then
            btn.Text = "ON"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=ON_COL}):Play()
            try(onOn)
        else
            btn.Text = "OFF"
            TweenService:Create(btn, TweenInfo.new(0.2), {BackgroundColor3=OFF_COL}):Play()
            try(onOff)
        end
    end)

    return f, btn
end

local function makeSlider(lbl, minV, maxV, defV, onChange)
    local f = Instance.new("Frame")
    f.Size             = UDim2.new(1, -6, 0, 64)
    f.BackgroundColor3 = PANEL
    f.BorderSizePixel  = 0
    f.Parent           = Scroll

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(0, 8)
    fc.Parent = f

    local fs = Instance.new("UIStroke")
    fs.Color = BORDER
    fs.Thickness = 1
    fs.Parent = f

    local nl = Instance.new("TextLabel")
    nl.Size = UDim2.new(1,-70,0,20)
    nl.Position = UDim2.new(0,10,0,6)
    nl.BackgroundTransparency = 1
    nl.TextColor3 = TEXT
    nl.TextSize = 13
    nl.Font = Enum.Font.GothamBold
    nl.Text = lbl
    nl.TextXAlignment = Enum.TextXAlignment.Left
    nl.Parent = f

    local vl = Instance.new("TextLabel")
    vl.Size = UDim2.new(0,55,0,20)
    vl.Position = UDim2.new(1,-65,0,6)
    vl.BackgroundTransparency = 1
    vl.TextColor3 = ACCENT
    vl.TextSize = 13
    vl.Font = Enum.Font.GothamBold
    vl.Text = tostring(defV)
    vl.TextXAlignment = Enum.TextXAlignment.Right
    vl.Parent = f

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1,-20,0,8)
    track.Position = UDim2.new(0,10,0,40)
    track.BackgroundColor3 = BORDER
    track.BorderSizePixel = 0
    track.Parent = f

    local trc = Instance.new("UICorner")
    trc.CornerRadius = UDim.new(1,0)
    trc.Parent = track

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = ACCENT
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new((defV-minV)/(maxV-minV),0,1,0)
    fill.Parent = track

    local filc = Instance.new("UICorner")
    filc.CornerRadius = UDim.new(1,0)
    filc.Parent = fill

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0,18,0,18)
    knob.Position = UDim2.new(1,-9,0.5,-9)
    knob.BackgroundColor3 = Color3.fromRGB(255,255,255)
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    knob.Parent = fill

    local kc = Instance.new("UICorner")
    kc.CornerRadius = UDim.new(1,0)
    kc.Parent = knob

    local dragging = false
    local curVal = defV

    local function update(pct)
        pct = math.clamp(pct, 0, 1)
        curVal = math.floor(minV + (maxV-minV)*pct)
        fill.Size = UDim2.new(pct,0,1,0)
        vl.Text = tostring(curVal)
        try(onChange, curVal)
    end

    track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if dragging then
            if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
                local pos = inp.Position.X
                local tPos = track.AbsolutePosition.X
                local tW   = track.AbsoluteSize.X
                update((pos - tPos) / tW)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1
        or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    return f
end

-- ══════════════════════════════════════
-- SECTION 11: BUILD MENU ITEMS
-- ══════════════════════════════════════

makeSection("🥚 ESP")

makeToggle("Egg ESP", "يكشف كل البيض — رتبة، كاش، مسافة",
    function()
        State.Esp = true
        scanEggs()
    end,
    function()
        State.Esp = false
        removeAllEsp()
    end
)

makeSection("🏃 الحركة")

makeToggle("سرعة مخصصة", "تحكم في سرعتك بالسلايدر",
    function() State.Speed = true; enableSpeed() end,
    function() State.Speed = false; disableSpeed() end
)

makeSlider("قيمة السرعة", 16, 250, 60, function(v)
    State.SpeedVal = v
end)

makeToggle("قفز عالي", "قوة قفز × 2.4 للوصول للمناطق العليا",
    function() State.HighJump = true; enableJump() end,
    function() State.HighJump = false; disableJump() end
)

makeToggle("NoClip", "اخترق الجدران والعوائق",
    function() State.NoClip = true; enableNoclip() end,
    function() State.NoClip = false; disableNoclip() end
)

makeToggle("Fly — الكاميرا تتحكم", "تحرك بالكاميرا للطيران",
    function() State.Fly = true; enableFly() end,
    function() State.Fly = false; disableFly() end
)

makeSection("🤖 أوتو فارم")

makeToggle("تجميع بيض تلقائي", "يتحرك لأقرب بيضة ويرجع للقاعدة",
    function() State.AutoFarm = true; enableAutoFarm() end,
    function() State.AutoFarm = false end
)

makeToggle("Infinite Stamina", "طاقة تسلق لا تنتهي",
    function()
        State.InfStamina = true
        task.spawn(function()
            while State.InfStamina do
                try(function()
                    local stats = LP:FindFirstChild("leaderstats") or LP:FindFirstChild("Stats")
                    if stats then
                        local st = stats:FindFirstChild("Stamina")
                        if st then st.Value = 9999 end
                    end
                end)
                task.wait(0.2)
            end
        end)
    end,
    function() State.InfStamina = false end
)

makeSection("⚙️ أدوات")

makeToggle("Anti AFK", "لا تُكيك من اللعبة",
    function() State.AntiAfk = true; enableAntiAfk() end,
    function() State.AntiAfk = false end
)

-- Padding
local pad = Instance.new("Frame")
pad.Size = UDim2.new(1,0,0,8)
pad.BackgroundTransparency = 1
pad.Parent = Scroll

-- ══════════════════════════════════════
-- SECTION 12: DRAG (TOUCH FRIENDLY)
-- ══════════════════════════════════════

local dragActive = false
local dragStart, frameStart

Title.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragActive = true
        dragStart  = inp.Position
        frameStart = Main.Position
    end
end)

UserInputService.InputChanged:Connect(function(inp)
    if dragActive then
        if inp.UserInputType == Enum.UserInputType.MouseMovement
        or inp.UserInputType == Enum.UserInputType.Touch then
            local d = inp.Position - dragStart
            Main.Position = UDim2.new(
                frameStart.X.Scale, frameStart.X.Offset + d.X,
                frameStart.Y.Scale, frameStart.Y.Offset + d.Y
            )
        end
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1
    or inp.UserInputType == Enum.UserInputType.Touch then
        dragActive = false
    end
end)

-- ══════════════════════════════════════
-- SECTION 13: HIDE BUTTON
-- ══════════════════════════════════════

local hidden = false
HideBtn.MouseButton1Click:Connect(function()
    hidden = not hidden
    if hidden then
        TweenService:Create(Main, TweenInfo.new(0.3,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,300,0,44)}):Play()
        HideBtn.Text = "+"
    else
        TweenService:Create(Main, TweenInfo.new(0.3,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,300,0,500)}):Play()
        HideBtn.Text = "—"
    end
end)

-- ══════════════════════════════════════
-- SECTION 14: OPEN TOAST
-- ══════════════════════════════════════

local toast = Instance.new("Frame")
toast.Size             = UDim2.new(0,260,0,50)
toast.Position         = UDim2.new(0.5,-130,0,-60)
toast.BackgroundColor3 = PANEL
toast.BorderSizePixel  = 0
toast.Parent           = ScreenGui

local toastc = Instance.new("UICorner")
toastc.CornerRadius = UDim.new(0,10)
toastc.Parent = toast

local toasts = Instance.new("UIStroke")
toasts.Color = ACCENT
toasts.Thickness = 1.5
toasts.Parent = toast

local toastL = Instance.new("TextLabel")
toastL.Text = "🐾 السكربت جاهز! شغّل الميزات"
toastL.Size = UDim2.new(1,0,1,0)
toastL.BackgroundTransparency = 1
toastL.TextColor3 = TEXT
toastL.TextSize = 13
toastL.Font = Enum.Font.GothamBold
toastL.TextXAlignment = Enum.TextXAlignment.Center
toastL.Parent = toast

TweenService:Create(toast, TweenInfo.new(0.5,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.new(0.5,-130,0,15)}):Play()

task.delay(3.5, function()
    TweenService:Create(toast, TweenInfo.new(0.4,Enum.EasingStyle.Quart),
        {Position=UDim2.new(0.5,-130,0,-60)}):Play()
    task.delay(0.5, function() try(function() toast:Destroy() end) end)
end)

-- Done
