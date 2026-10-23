--[[
╔══════════════════════════════════════════════════════════╗
║  CLIMB FOR ANIMALS EGGS v6.0                            ║
║  Compact Menu | Smart Farm | Native ESP                 ║
╚══════════════════════════════════════════════════════════╝
]]

local function try(f,...) local ok,r=pcall(f,...); return ok,r end
local function tryGet(f,...) local ok,r=pcall(f,...); if ok then return r end; return nil end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local Camera           = Workspace.CurrentCamera
local LP               = Players.LocalPlayer
local PGui             = LP:WaitForChild("PlayerGui")

local Char,Hum,Root
local function grabChar()
    Char = LP.Character or LP.CharacterAdded:Wait()
    Hum  = Char:WaitForChild("Humanoid")
    Root = Char:WaitForChild("HumanoidRootPart")
end
grabChar()
LP.CharacterAdded:Connect(function(c)
    task.wait(0.5); Char=c
    Hum=c:WaitForChild("Humanoid")
    Root=c:WaitForChild("HumanoidRootPart")
end)

-- ══════════════════════════════════════
-- STATE
-- ══════════════════════════════════════

local State = {
    Esp=false, Speed=false, SpeedVal=60,
    HighJump=false, NoClip=false,
    AutoFarm=false, InfStamina=false,
    AntiAfk=false, Fly=false,
}

-- ══════════════════════════════════════
-- RARITY
-- ══════════════════════════════════════

local RARITY = {
    common    ={d="Common",    c="~$500",  col=Color3.fromRGB(200,200,200),p=1 },
    uncommon  ={d="Uncommon",  c="~$2K",   col=Color3.fromRGB(80,200,80),  p=2 },
    rare      ={d="Rare",      c="~$15K",  col=Color3.fromRGB(80,120,255), p=3 },
    epic      ={d="Epic",      c="~$120K", col=Color3.fromRGB(160,60,220), p=5 },
    legendary ={d="Legendary", c="~$2M",   col=Color3.fromRGB(255,180,0),  p=8 },
    mythic    ={d="Mythic",    c="~$5M",   col=Color3.fromRGB(255,60,60),  p=9 },
    divine    ={d="Divine",    c="~$20M",  col=Color3.fromRGB(0,220,220),  p=10},
    celestial ={d="Celestial", c="~$200M", col=Color3.fromRGB(255,240,80), p=11},
    royal     ={d="Royal",     c="~$10B+", col=Color3.fromRGB(255,20,147), p=12},
    golden    ={d="Golden",    c="~$50K",  col=Color3.fromRGB(255,200,0),  p=5 },
    diamond   ={d="Diamond",   c="~$500K", col=Color3.fromRGB(180,230,255),p=7 },
    forest    ={d="Forest",    c="~$500",  col=Color3.fromRGB(160,220,130),p=1 },
    winter    ={d="Winter",    c="~$2K",   col=Color3.fromRGB(130,200,255),p=2 },
    ocean     ={d="Ocean",     c="~$8K",   col=Color3.fromRGB(60,120,255), p=3 },
    desert    ={d="Desert",    c="~$15K",  col=Color3.fromRGB(240,180,60), p=4 },
    crystal   ={d="Crystal",   c="~$50K",  col=Color3.fromRGB(200,150,255),p=5 },
    jungle    ={d="Jungle",    c="~$120K", col=Color3.fromRGB(40,180,80),  p=6 },
    mystic    ={d="Mystic",    c="~$500K", col=Color3.fromRGB(255,140,255),p=7 },
    prehistoric={d="Prehistoric",c="~$2M", col=Color3.fromRGB(200,120,60), p=8 },
}

local function getRD(text)
    if not text then return nil end
    local low=text:lower()
    for k,v in pairs(RARITY) do
        if low:find(k) then return v end
    end
    return nil
end

-- ══════════════════════════════════════
-- EGG DETECTION
-- ══════════════════════════════════════

local function isPlayerChar(obj)
    for _,p in ipairs(Players:GetPlayers()) do
        if p.Character and (obj==p.Character or obj:IsDescendantOf(p.Character)) then
            return true
        end
    end
    return false
end

-- Read rarity from game's own BillboardGui labels
local function readGameLabel(obj)
    for _,c in ipairs(obj:GetChildren()) do
        if (c:IsA("BillboardGui") or c:IsA("SurfaceGui")) and c.Name~="CAFE_ESP" then
            for _,lb in ipairs(c:GetDescendants()) do
                if lb:IsA("TextLabel") and lb.Text~="" then
                    local rd=getRD(lb.Text)
                    if rd then return rd end
                end
            end
        end
    end
    return nil
end

local function getEggData(obj)
    -- Method 1: read game's own label
    local rd = readGameLabel(obj)
    if rd then return rd end
    -- Check children if Model
    if obj:IsA("Model") then
        for _,c in ipairs(obj:GetChildren()) do
            rd = readGameLabel(c)
            if rd then return rd end
        end
    end
    -- Method 2: name based
    local name = obj.Name
    rd = getRD(name)
    if rd and name:lower():find("egg") then return rd end
    -- Check parent name
    if obj.Parent then
        rd = getRD(obj.Parent.Name)
        if rd and obj.Parent.Name:lower():find("egg") then return rd end
    end
    return nil
end

local function getBasePart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart end
        return obj:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- ══════════════════════════════════════
-- ESP
-- ══════════════════════════════════════

local espCache = {}

local function clearESP()
    for _,v in pairs(espCache) do
        try(function() v:Destroy() end)
    end
    espCache = {}
end

local function addESP(part, rd)
    if espCache[part] then return end
    if isPlayerChar(part) then return end

    local bb = Instance.new("BillboardGui")
    bb.Name="CAFE_ESP"; bb.Size=UDim2.new(0,140,0,46)
    bb.StudsOffset=Vector3.new(0,part.Size.Y+1.5,0)
    bb.AlwaysOnTop=true; bb.MaxDistance=1500
    bb.LightInfluence=0; bb.Parent=part

    local bg=Instance.new("Frame",bb)
    bg.Size=UDim2.new(1,0,1,0)
    bg.BackgroundColor3=Color3.fromRGB(5,5,15)
    bg.BackgroundTransparency=0.15; bg.BorderSizePixel=0
    Instance.new("UICorner",bg).CornerRadius=UDim.new(0,6)
    local s=Instance.new("UIStroke",bg); s.Color=rd.col; s.Thickness=2

    local l1=Instance.new("TextLabel",bg)
    l1.Size=UDim2.new(1,-4,0.52,0); l1.Position=UDim2.new(0,2,0,2)
    l1.BackgroundTransparency=1; l1.TextColor3=rd.col
    l1.TextSize=12; l1.Font=Enum.Font.GothamBold
    l1.Text="["..rd.d.."]  "..rd.c
    l1.TextScaled=true; l1.TextXAlignment=Enum.TextXAlignment.Center

    local l2=Instance.new("TextLabel",bg)
    l2.Size=UDim2.new(1,-4,0.45,0); l2.Position=UDim2.new(0,2,0.53,0)
    l2.BackgroundTransparency=1; l2.TextColor3=Color3.fromRGB(190,190,210)
    l2.TextSize=11; l2.Font=Enum.Font.Gotham; l2.Text="..."
    l2.TextScaled=true; l2.TextXAlignment=Enum.TextXAlignment.Center

    espCache[part]=bb

    task.spawn(function()
        while bb and bb.Parent and State.Esp do
            try(function()
                if not part.Parent then espCache[part]=nil; bb:Destroy(); return end
                if Root then
                    l2.Text=string.format("📍 %.0f st",(Root.Position-part.Position).Magnitude)
                end
            end)
            task.wait(0.5)
        end
        try(function() if bb and bb.Parent then bb:Destroy() end end)
    end)
end

local function scanESP()
    local function scan(inst)
        for _,c in ipairs(inst:GetChildren()) do
            try(function()
                if isPlayerChar(c) then return end
                local rd=getEggData(c)
                if rd then
                    local part=getBasePart(c)
                    if part then addESP(part,rd) end
                end
                scan(c)
            end)
        end
    end
    scan(Workspace)
end

Workspace.DescendantAdded:Connect(function(d)
    if not State.Esp then return end
    task.wait(0.3)
    try(function()
        local rd=getEggData(d)
        if rd then
            local part=getBasePart(d)
            if part then addESP(part,rd) end
        end
    end)
end)

Workspace.DescendantRemoving:Connect(function(d)
    if espCache[d] then espCache[d]=nil end
end)

-- ══════════════════════════════════════
-- AUTO FARM
-- ══════════════════════════════════════

local allRemotes = {}

local function collectAllRemotes()
    allRemotes={}
    local function scan(f)
        for _,c in ipairs(f:GetChildren()) do
            try(function()
                if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
                    table.insert(allRemotes,c)
                end
                scan(c)
            end)
        end
    end
    scan(ReplicatedStorage)
    try(function() scan(Workspace) end)
end

local function getAllEggs()
    local eggs={}
    local seen={}
    local function scan(inst)
        for _,c in ipairs(inst:GetChildren()) do
            try(function()
                if isPlayerChar(c) then return end
                local rd=getEggData(c)
                if rd then
                    local part=getBasePart(c)
                    if part and not seen[part] then
                        seen[part]=true
                        table.insert(eggs,{part=part,zone=rd,pos=part.Position})
                    end
                end
                scan(c)
            end)
        end
    end
    scan(Workspace)
    return eggs
end

local function getBest(eggs)
    if #eggs==0 then return nil end
    local best,bs=nil,-math.huge
    for _,e in ipairs(eggs) do
        if e.part and e.part.Parent then
            local dist=Root and (Root.Position-e.pos).Magnitude or 9999
            local score=e.zone.p*100000 - dist
            if score>bs then bs=score; best=e end
        end
    end
    return best
end

local function collectEgg(egg)
    -- Step 1: teleport on top of egg
    try(function()
        Root.CFrame=CFrame.new(egg.pos+Vector3.new(0,5,0))
    end)
    task.wait(0.2)

    -- Step 2: fire ALL remotes with egg references
    -- since we can't know which one works, fire them all
    for _,remote in ipairs(allRemotes) do
        try(function()
            if remote:IsA("RemoteEvent") then
                -- Try every possible argument combo
                remote:FireServer()
                remote:FireServer(egg.part)
                remote:FireServer(egg.part.Parent)
                remote:FireServer(egg.pos)
                remote:FireServer(egg.part, egg.zone.d)
            end
        end)
        task.wait(0.02)
    end

    -- Step 3: trigger any ProximityPrompt
    try(function()
        local pp = egg.part:FindFirstChildOfClass("ProximityPrompt",true)
            or (egg.part.Parent and egg.part.Parent:FindFirstChildOfClass("ProximityPrompt",true))
        if pp then
            fireproximityprompt(pp)
        end
    end)

    -- Step 4: ClickDetector
    try(function()
        local cd = egg.part:FindFirstChildOfClass("ClickDetector",true)
            or (egg.part.Parent and egg.part.Parent:FindFirstChildOfClass("ClickDetector",true))
        if cd then
            fireclickdetector(cd)
        end
    end)

    task.wait(0.15)
end

local function runAutoFarm()
    collectAllRemotes()
    task.spawn(function()
        while State.AutoFarm do
            try(function()
                if not Root then task.wait(1); return end
                local eggs=getAllEggs()
                if #eggs==0 then task.wait(2); return end
                local target=getBest(eggs)
                if not target then task.wait(1); return end
                collectEgg(target)
                task.wait(0.3+math.random()*0.2)
            end)
        end
    end)
end

-- ══════════════════════════════════════
-- SPEED / JUMP / NOCLIP / FLY
-- ══════════════════════════════════════

local speedConn
local function enableSpeed()
    if speedConn then speedConn:Disconnect() end
    speedConn=RunService.Heartbeat:Connect(function()
        if not State.Speed then return end
        try(function() if Hum and Hum.Parent then Hum.WalkSpeed=State.SpeedVal end end)
    end)
end
local function disableSpeed()
    if speedConn then speedConn:Disconnect(); speedConn=nil end
    try(function() if Hum then Hum.WalkSpeed=16 end end)
end

local jumpConn
local function enableJump()
    if jumpConn then jumpConn:Disconnect() end
    jumpConn=RunService.Heartbeat:Connect(function()
        if not State.HighJump then return end
        try(function() if Hum and Hum.Parent then Hum.JumpPower=120 end end)
    end)
end
local function disableJump()
    if jumpConn then jumpConn:Disconnect(); jumpConn=nil end
    try(function() if Hum then Hum.JumpPower=50 end end)
end

local noclipConn
local function enableNoclip()
    if noclipConn then noclipConn:Disconnect() end
    noclipConn=RunService.Stepped:Connect(function()
        if not State.NoClip then return end
        try(function()
            for _,p in ipairs(Char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide=false end
            end
        end)
    end)
end
local function disableNoclip()
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    try(function()
        for _,p in ipairs(Char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=true end
        end
    end)
end

local flyBV,flyBG
local function enableFly()
    try(function()
        flyBV=Instance.new("BodyVelocity"); flyBV.Velocity=Vector3.zero
        flyBV.MaxForce=Vector3.new(1e5,1e5,1e5); flyBV.Parent=Root
        flyBG=Instance.new("BodyGyro"); flyBG.MaxTorque=Vector3.new(1e5,1e5,1e5)
        flyBG.P=1e4; flyBG.Parent=Root; Hum.PlatformStand=true
        task.spawn(function()
            while State.Fly and flyBV and flyBV.Parent do
                try(function()
                    flyBV.Velocity=Camera.CFrame.LookVector*(State.SpeedVal*1.5)
                    flyBG.CFrame=Camera.CFrame
                end)
                task.wait(0.03)
            end
        end)
    end)
end
local function disableFly()
    try(function()
        if flyBV then flyBV:Destroy(); flyBV=nil end
        if flyBG then flyBG:Destroy(); flyBG=nil end
        if Hum then Hum.PlatformStand=false end
    end)
end

local function runInfStamina()
    task.spawn(function()
        while State.InfStamina do
            try(function()
                local s=LP:FindFirstChild("leaderstats") or LP:FindFirstChild("Stats")
                if s then
                    for _,v in ipairs(s:GetChildren()) do
                        if v.Name:lower():find("stamina") or v.Name:lower():find("energy") then
                            if v.Value<100 then v.Value=99999 end
                        end
                    end
                end
            end)
            task.wait(0.2)
        end
    end)
end

local function runAntiAfk()
    task.spawn(function()
        while State.AntiAfk do
            try(function()
                local fe=Instance.new("BindableEvent"); fe:Fire(); fe:Destroy()
            end)
            task.wait(55+math.random()*10)
        end
    end)
end

-- ══════════════════════════════════════
-- GUI — COMPACT FIXED POSITION
-- أصغر حجم، ثابت على يمين الشاشة
-- يمكن تحريكه بسهولة
-- ══════════════════════════════════════

local BG    =Color3.fromRGB(10,10,18)
local PANEL =Color3.fromRGB(18,20,30)
local ACCENT=Color3.fromRGB(110,60,240)
local ON_C  =Color3.fromRGB(50,220,110)
local OFF_C =Color3.fromRGB(200,55,55)
local TEXT  =Color3.fromRGB(225,225,245)
local DIM   =Color3.fromRGB(130,130,155)
local BDR   =Color3.fromRGB(55,40,90)

local oldG=PGui:FindFirstChild("CAFE_ModMenu")
if oldG then oldG:Destroy() end
try(function()
    local cg=game:GetService("CoreGui")
    local o=cg:FindFirstChild("CAFE_ModMenu")
    if o then o:Destroy() end
end)

local SGui=Instance.new("ScreenGui")
SGui.Name="CAFE_ModMenu"; SGui.ResetOnSpawn=false
SGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SGui.IgnoreGuiInset=true

try(function() SGui.Parent=game:GetService("CoreGui") end)
if not SGui.Parent then SGui.Parent=PGui end

-- ── الإطار الرئيسي ──
-- عرض ثابت 280، يبدأ من أعلى الشاشة مع هامش
local MENU_W = 280
local MENU_H = 420  -- أصغر بكثير

local Main=Instance.new("Frame",SGui)
Main.Size=UDim2.new(0,MENU_W,0,MENU_H)
-- وضعه في منتصف أعلى الشاشة
Main.Position=UDim2.new(0.5,-MENU_W/2,0,40)
Main.BackgroundColor3=BG; Main.BorderSizePixel=0
Instance.new("UICorner",Main).CornerRadius=UDim.new(0,10)
local ms=Instance.new("UIStroke",Main); ms.Color=BDR; ms.Thickness=1.5

-- ── شريط العنوان (للسحب) ──
local TBar=Instance.new("Frame",Main)
TBar.Name="TitleBar"
TBar.Size=UDim2.new(1,0,0,38); TBar.BackgroundColor3=PANEL
TBar.BorderSizePixel=0
Instance.new("UICorner",TBar).CornerRadius=UDim.new(0,10)
-- إصلاح الزوايا السفلية
local tfx=Instance.new("Frame",TBar)
tfx.Size=UDim2.new(1,0,0.5,0); tfx.Position=UDim2.new(0,0,0.5,0)
tfx.BackgroundColor3=PANEL; tfx.BorderSizePixel=0

local TL=Instance.new("TextLabel",TBar)
TL.Text="🐾 CFAE Mod Menu"
TL.Size=UDim2.new(1,-80,1,0); TL.Position=UDim2.new(0,10,0,0)
TL.BackgroundTransparency=1; TL.TextColor3=TEXT
TL.TextSize=13; TL.Font=Enum.Font.GothamBold
TL.TextXAlignment=Enum.TextXAlignment.Left

-- زر الإخفاء
local HBtn=Instance.new("TextButton",TBar)
HBtn.Size=UDim2.new(0,28,0,28); HBtn.Position=UDim2.new(1,-36,0,5)
HBtn.BackgroundColor3=ACCENT; HBtn.Text="—"; HBtn.TextColor3=TEXT
HBtn.TextSize=14; HBtn.Font=Enum.Font.GothamBold; HBtn.BorderSizePixel=0
Instance.new("UICorner",HBtn).CornerRadius=UDim.new(0,6)

-- نص السحب
local dragHint=Instance.new("TextLabel",TBar)
dragHint.Text="⠿ اسحب"
dragHint.Size=UDim2.new(0,60,1,0); dragHint.Position=UDim2.new(1,-90,0,0)
dragHint.BackgroundTransparency=1; dragHint.TextColor3=DIM
dragHint.TextSize=10; dragHint.Font=Enum.Font.Gotham

-- ── منطقة التمرير ──
local Scr=Instance.new("ScrollingFrame",Main)
Scr.Size=UDim2.new(1,-8,1,-44); Scr.Position=UDim2.new(0,4,0,40)
Scr.BackgroundTransparency=1; Scr.BorderSizePixel=0
Scr.ScrollBarThickness=3; Scr.ScrollBarImageColor3=ACCENT
Scr.CanvasSize=UDim2.new(0,0,0,0)
Scr.ScrollingDirection=Enum.ScrollingDirection.Y

local Lay=Instance.new("UIListLayout",Scr)
Lay.Padding=UDim.new(0,4)
Lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scr.CanvasSize=UDim2.new(0,0,0,Lay.AbsoluteContentSize.Y+8)
end)

local function addPad()
    local p=Instance.new("Frame",Scr)
    p.Size=UDim2.new(1,0,0,2); p.BackgroundTransparency=1
end

-- ── Section ──
local function sec(txt)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-4,0,20); f.BackgroundTransparency=1
    local ln=Instance.new("Frame",f)
    ln.Size=UDim2.new(1,0,0,1); ln.Position=UDim2.new(0,0,0.5,0)
    ln.BackgroundColor3=BDR; ln.BorderSizePixel=0
    local lb=Instance.new("TextLabel",f)
    lb.Text="  "..txt.."  "; lb.Size=UDim2.new(0,0,1,0)
    lb.AutomaticSize=Enum.AutomaticSize.X; lb.Position=UDim2.new(0,8,0,0)
    lb.BackgroundColor3=BG; lb.TextColor3=ACCENT
    lb.TextSize=10; lb.Font=Enum.Font.GothamBold
end

-- ── Toggle (مضغوط) ──
local function tog(name,onOn,onOff)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-4,0,40); f.BackgroundColor3=PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local fs=Instance.new("UIStroke",f); fs.Color=BDR; fs.Thickness=1

    local nl=Instance.new("TextLabel",f)
    nl.Text=name; nl.Size=UDim2.new(1,-80,1,0); nl.Position=UDim2.new(0,10,0,0)
    nl.BackgroundTransparency=1; nl.TextColor3=TEXT; nl.TextSize=12
    nl.Font=Enum.Font.GothamBold; nl.TextXAlignment=Enum.TextXAlignment.Left

    local btn=Instance.new("TextButton",f)
    btn.Size=UDim2.new(0,58,0,26); btn.Position=UDim2.new(1,-66,0.5,-13)
    btn.BackgroundColor3=OFF_C; btn.Text="OFF"; btn.TextColor3=Color3.fromRGB(255,255,255)
    btn.TextSize=11; btn.Font=Enum.Font.GothamBold; btn.BorderSizePixel=0
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6)

    local on=false
    btn.MouseButton1Click:Connect(function()
        on=not on
        if on then
            btn.Text="ON"
            TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=ON_C}):Play()
            try(onOn)
        else
            btn.Text="OFF"
            TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=OFF_C}):Play()
            try(onOff)
        end
    end)
    return f,btn
end

-- ── Slider (مضغوط) ──
local function sld(lbl,mn,mx,def,cb)
    local f=Instance.new("Frame",Scr)
    f.Size=UDim2.new(1,-4,0,52); f.BackgroundColor3=PANEL; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local fs=Instance.new("UIStroke",f); fs.Color=BDR; fs.Thickness=1

    local nl=Instance.new("TextLabel",f)
    nl.Text=lbl; nl.Size=UDim2.new(1,-60,0,18); nl.Position=UDim2.new(0,10,0,4)
    nl.BackgroundTransparency=1; nl.TextColor3=TEXT; nl.TextSize=12
    nl.Font=Enum.Font.GothamBold; nl.TextXAlignment=Enum.TextXAlignment.Left

    local vl=Instance.new("TextLabel",f)
    vl.Text=tostring(def); vl.Size=UDim2.new(0,48,0,18); vl.Position=UDim2.new(1,-54,0,4)
    vl.BackgroundTransparency=1; vl.TextColor3=ACCENT; vl.TextSize=12
    vl.Font=Enum.Font.GothamBold; vl.TextXAlignment=Enum.TextXAlignment.Right

    local tr=Instance.new("Frame",f)
    tr.Size=UDim2.new(1,-16,0,6); tr.Position=UDim2.new(0,8,0,32)
    tr.BackgroundColor3=BDR; tr.BorderSizePixel=0
    Instance.new("UICorner",tr).CornerRadius=UDim.new(1,0)

    local fi=Instance.new("Frame",tr)
    fi.BackgroundColor3=ACCENT; fi.BorderSizePixel=0
    fi.Size=UDim2.new((def-mn)/(mx-mn),0,1,0)
    Instance.new("UICorner",fi).CornerRadius=UDim.new(1,0)

    local kn=Instance.new("Frame",fi)
    kn.Size=UDim2.new(0,16,0,16); kn.Position=UDim2.new(1,-8,0.5,-8)
    kn.BackgroundColor3=Color3.fromRGB(255,255,255); kn.BorderSizePixel=0; kn.ZIndex=5
    Instance.new("UICorner",kn).CornerRadius=UDim.new(1,0)

    local drag=false
    local function upd(p)
        p=math.clamp(p,0,1)
        local v=math.floor(mn+(mx-mn)*p)
        fi.Size=UDim2.new(p,0,1,0); vl.Text=tostring(v); try(cb,v)
    end
    tr.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; upd((i.Position.X-tr.AbsolutePosition.X)/tr.AbsoluteSize.X)
        end
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
    function() State.Esp=true;  scanESP() end,
    function() State.Esp=false; clearESP() end
)
addPad()

sec("🏃 الحركة")
tog("سرعة مخصصة",
    function() State.Speed=true;  enableSpeed() end,
    function() State.Speed=false; disableSpeed() end
)
sld("قيمة السرعة",16,250,60,function(v) State.SpeedVal=v end)
tog("قفز عالي",
    function() State.HighJump=true;  enableJump() end,
    function() State.HighJump=false; disableJump() end
)
tog("NoClip",
    function() State.NoClip=true;  enableNoclip() end,
    function() State.NoClip=false; disableNoclip() end
)
tog("Fly",
    function() State.Fly=true;  enableFly() end,
    function() State.Fly=false; disableFly() end
)
addPad()

sec("🤖 أوتو فارم")
tog("تجميع ذكي",
    function() State.AutoFarm=true;  runAutoFarm() end,
    function() State.AutoFarm=false end
)
tog("Infinite Stamina",
    function() State.InfStamina=true;  runInfStamina() end,
    function() State.InfStamina=false end
)
addPad()

sec("⚙️ أدوات")
tog("Anti-AFK",
    function() State.AntiAfk=true;  runAntiAfk() end,
    function() State.AntiAfk=false end
)
addPad()

local pd=Instance.new("Frame",Scr)
pd.Size=UDim2.new(1,0,0,6); pd.BackgroundTransparency=1

-- ══════════════════════════════════════
-- DRAG — محسّن للموبايل
-- ══════════════════════════════════════

local dagOn,dagSt,dagFr=false,nil,nil

TBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        dagOn=true
        dagSt=Vector2.new(i.Position.X,i.Position.Y)
        dagFr=Vector2.new(Main.Position.X.Offset,Main.Position.Y.Offset)
    end
end)

UserInputService.InputChanged:Connect(function(i)
    if not dagOn then return end
    if i.UserInputType==Enum.UserInputType.MouseMovement
    or i.UserInputType==Enum.UserInputType.Touch then
        local dx=i.Position.X-dagSt.X
        local dy=i.Position.Y-dagSt.Y
        local vp=Camera.ViewportSize
        -- كلب الموضع داخل الشاشة
        local nx=math.clamp(dagFr.X+dx, 0, vp.X-MENU_W)
        local ny=math.clamp(dagFr.Y+dy, 0, vp.Y-50)
        Main.Position=UDim2.new(0,nx,0,ny)
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1
    or i.UserInputType==Enum.UserInputType.Touch then
        dagOn=false
    end
end)

-- ══════════════════════════════════════
-- HIDE BUTTON
-- ══════════════════════════════════════

local hidOn=false
HBtn.MouseButton1Click:Connect(function()
    hidOn=not hidOn
    if hidOn then
        TweenService:Create(Main,TweenInfo.new(0.25,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,MENU_W,0,38)}):Play()
        HBtn.Text="+"
    else
        TweenService:Create(Main,TweenInfo.new(0.25,Enum.EasingStyle.Quart),
            {Size=UDim2.new(0,MENU_W,0,MENU_H)}):Play()
        HBtn.Text="—"
    end
end)

-- ══════════════════════════════════════
-- TOAST
-- ══════════════════════════════════════

local toast=Instance.new("Frame",SGui)
toast.Size=UDim2.new(0,260,0,44)
toast.Position=UDim2.new(0.5,-130,1,10)
toast.BackgroundColor3=PANEL; toast.BorderSizePixel=0
Instance.new("UICorner",toast).CornerRadius=UDim.new(0,10)
local ts=Instance.new("UIStroke",toast); ts.Color=ACCENT; ts.Thickness=1.5
local tl=Instance.new("TextLabel",toast)
tl.Text="🐾 v6.0 جاهز | اسحب من شريط العنوان"
tl.Size=UDim2.new(1,0,1,0); tl.BackgroundTransparency=1
tl.TextColor3=TEXT; tl.TextSize=11; tl.Font=Enum.Font.GothamBold
tl.TextXAlignment=Enum.TextXAlignment.Center

-- Toast يظهر من الأسفل
TweenService:Create(toast,TweenInfo.new(0.5,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),
    {Position=UDim2.new(0.5,-130,1,-54)}):Play()
task.delay(3.5,function()
    TweenService:Create(toast,TweenInfo.new(0.4,Enum.EasingStyle.Quart),
        {Position=UDim2.new(0.5,-130,1,10)}):Play()
    task.delay(0.5,function() try(function() toast:Destroy() end) end)
end)
