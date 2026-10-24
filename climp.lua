--[[
╔═══════════════════════════════════════════════════════════╗
║    STEAL AN EGG — CROW v4.0  STEALTH BUILD               ║
║    Anti-BAC layer:                                        ║
║      • NO fireproximityprompt (detected)                 ║
║      • NO direct WalkSpeed set (position-delta check)    ║
║      • NO instant CFrame teleport (delta flagged)        ║
║      • Movement via TweenService (smooth, believable)    ║
║      • Steal via VirtualUser screen-tap simulation       ║
║      • Treadmill via continuous character on-part stay   ║
║      • Rate limits on all actions                        ║
║      • All loops jittered — no fixed-period fingerprint  ║
╚═══════════════════════════════════════════════════════════╝
--]]

-- ════════════════════════════════════════════════════════════
-- [0] SERVICES
-- ════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local VirtualUser      = game:GetService("VirtualUser")
local CoreGui          = game:GetService("CoreGui")
local WS               = game:GetService("Workspace")
local RS               = game:GetService("ReplicatedStorage")
local UIS              = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")

local LP  = Players.LocalPlayer
local Cam = WS.CurrentCamera

-- ════════════════════════════════════════════════════════════
-- [1] CORE HELPERS
-- ════════════════════════════════════════════════════════════
local function getChar() return LP.Character or LP.CharacterAdded:Wait() end
local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- Jittered wait — breaks timing fingerprint
local function jw(base, pct)
    pct = pct or 0.25
    task.wait(base * (1 + (math.random()-0.5)*2*pct))
end

-- Rate limiter
local _rl = {}
local function rateOk(key, interval)
    local now = tick()
    if not _rl[key] or (now-_rl[key]) >= interval then
        _rl[key] = now; return true
    end
    return false
end

-- Format numbers
local function fn(n)
    if not n or n==0 then return "?" end
    if n>=1e12 then return ("%.1fT"):format(n/1e12) end
    if n>=1e9  then return ("%.1fB"):format(n/1e9)  end
    if n>=1e6  then return ("%.1fM"):format(n/1e6)  end
    if n>=1e3  then return ("%.1fK"):format(n/1e3)  end
    return tostring(math.floor(n))
end

-- ════════════════════════════════════════════════════════════
-- [2] STEALTH MOVEMENT ENGINE
-- Uses TweenService to move HRP at a believable speed.
-- Server sees smooth interpolated positions — not a jump.
-- Max tween speed = 50 studs/sec (normal sprint speed).
-- ════════════════════════════════════════════════════════════
local Move = {}
Move.SPEED = 40  -- studs per second (believable: 16=walk, 50=fast)
Move._tween = nil

function Move:To(targetPos, onDone)
    local hrp = getHRP()
    if not hrp then if onDone then onDone() end return end

    if self._tween then
        self._tween:Cancel()
        self._tween = nil
    end

    local dist = (hrp.Position - targetPos).Magnitude
    if dist < 2 then
        if onDone then onDone() end return
    end

    -- Time = distance / speed (capped: min 0.1s, max 8s)
    local t = math.clamp(dist / self.SPEED, 0.1, 8)

    -- Add tiny Y offset so we land on top, not inside
    local dest = CFrame.new(
        targetPos + Vector3.new(
            (math.random()-0.5)*0.4,
            3,
            (math.random()-0.5)*0.4
        )
    ) * CFrame.Angles(0, hrp.CFrame:ToEulerAnglesYXZ()==hrp.CFrame:ToEulerAnglesYXZ() and 0 or 0, 0)

    local tw = TweenService:Create(
        hrp,
        TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
        {CFrame = dest}
    )

    -- Disable physics during tween to prevent network correction
    hrp.Anchored = true
    tw:Play()
    self._tween = tw

    tw.Completed:Connect(function()
        hrp.Anchored = false
        self._tween = nil
        if onDone then onDone() end
    end)
end

-- Fast mode: large distances get a "sprint" boost
function Move:SetSpeed(s) self.SPEED = math.clamp(s, 16, 55) end

-- ════════════════════════════════════════════════════════════
-- [3] STEALTH STEAL ENGINE
-- VirtualUser simulates a real finger tap on the proximity
-- prompt UI button. The game sees a genuine input event.
-- We:
--   1. Move near the egg (tween)
--   2. Wait for ProximityPrompt to appear on screen
--   3. Find its screen position
--   4. VirtualUser:Click at that position
-- ════════════════════════════════════════════════════════════
local StealEngine = {}

-- Find all egg ProximityPrompts in workspace
local function scanEggs()
    local eggs = {}
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            local at = obj.ActionText:lower()
            local ot = (obj.ObjectText or ""):lower()
            if at:find("steal") or at:find("grab")
            or ot:find("egg")   or at:find("take") then
                local part = obj.Parent
                -- Handle Model parents
                if part and part:IsA("Model") then
                    part = part.PrimaryPart or
                           part:FindFirstChildOfClass("BasePart")
                end
                if part and part:IsA("BasePart") then
                    -- Read income
                    local income = nil
                    local ATTR = {"CashValue","Value","Income","MPS",
                                  "MoneyPerSecond","EggValue","PetIncome",
                                  "CashPerSecond","EggIncome","EggCash"}
                    for _, k in ipairs(ATTR) do
                        local v = obj.Parent:GetAttribute(k)
                                or (obj.Parent.Parent and
                                    obj.Parent.Parent:GetAttribute(k))
                        if type(v)=="number" and v>0 then
                            income=v; break
                        end
                    end
                    -- Rarity
                    local rarity = obj.Parent:GetAttribute("Rarity")
                               or obj.Parent:GetAttribute("EggRarity")
                               or "?"
                    table.insert(eggs, {
                        prompt = obj,
                        part   = part,
                        income = income,
                        rarity = rarity,
                        name   = obj.Parent.Name or part.Name,
                    })
                end
            end
        end
    end
    -- Sort best income first
    table.sort(eggs, function(a,b)
        return (a.income or 0) > (b.income or 0)
    end)
    return eggs
end

-- Get the world-to-screen position of a ProximityPrompt
-- The prompt renders a UI button we can click
local function getPromptScreenPos(prompt, part)
    -- Project part position to screen
    local worldPos = part.Position + Vector3.new(0, 2, 0)
    local screenPos, onScreen = Cam:WorldToScreenPoint(worldPos)
    if onScreen then
        return Vector2.new(screenPos.X, screenPos.Y), true
    end
    return nil, false
end

-- Simulate tap at screen position using VirtualUser
local function tapAt(screenPos)
    -- VirtualUser:ClickButton2 simulates a mouse click
    -- ClickButton1 simulates left-click / tap
    pcall(function()
        VirtualUser:Button1Down(screenPos, Cam.CFrame)
        task.wait(0.08)
        VirtualUser:Button1Up(screenPos, Cam.CFrame)
    end)
end

-- Find the player's pen (hatch area)
local function findPen()
    local uid = tostring(LP.UserId)
    local candidates = {}
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("BasePart") then
            local nl = obj.Name:lower()
            local owner = obj:GetAttribute("Owner")
                       or obj:GetAttribute("PlayerId")
                       or obj:GetAttribute("UserId")
            local isOwned = (owner == uid or owner == LP.UserId)
            if isOwned and (nl:find("pen") or nl:find("garden")
                         or nl:find("hatch") or nl:find("home")) then
                table.insert(candidates, obj)
            end
        end
    end
    if #candidates > 0 then return candidates[1] end
    -- Fallback: SpawnLocation
    for _, obj in ipairs(WS:GetDescendants()) do
        if obj:IsA("SpawnLocation") then
            local a = obj:GetAttribute("PlayerId") or obj:GetAttribute("UserId")
            if a == LP.UserId or a == uid then return obj end
        end
    end
    return nil
end

-- Find treadmill
local function findTreadmill()
    local uid = tostring(LP.UserId)
    local best, bestPri = nil, 0
    for _, obj in ipairs(WS:GetDescendants()) do
        local nl = obj.Name:lower()
        if obj:IsA("BasePart") and
           (nl:find("treadmill") or nl:find("tread")) then
            local owner = obj:GetAttribute("Owner")
                       or obj:GetAttribute("PlayerId")
                       or obj:GetAttribute("UserId")
            local pri = (owner==uid or owner==LP.UserId) and 2 or 1
            if pri > bestPri then
                best=obj; bestPri=pri
            end
        end
    end
    return best
end

-- ════════════════════════════════════════════════════════════
-- [4] AUTO-STEAL LOOP
-- ════════════════════════════════════════════════════════════
local AutoSteal = {
    enabled    = false,
    rareFilter = "Any",
    autoReturn = true,
    _thread    = nil,
    _pen       = nil,
}

local RARITY_RANK = {
    Common=1,Uncommon=2,Rare=3,Epic=4,
    Legendary=5,Cosmic=6,Secret=7,Eternal=8,Divine=9
}
local FILTER_MIN = {["Any"]=0,["Rare+"]=3,["Epic+"]=4,["Legendary+"]=5,["Cosmic+"]=6}

function AutoSteal:Start()
    self.enabled = true
    self._pen    = findPen()

    self._thread = task.spawn(function()
        while self.enabled do
            jw(2.0, 0.35)

            local eggs = scanEggs()
            if #eggs == 0 then jw(3,0.4); continue end

            -- Filter rarity
            local minR = FILTER_MIN[self.rareFilter] or 0
            local pool = {}
            for _, e in ipairs(eggs) do
                local r = RARITY_RANK[e.rarity] or 1
                if r >= minR then table.insert(pool, e) end
            end
            if #pool == 0 then continue end

            local target = pool[1]
            if not target.prompt or not target.prompt.Parent then continue end
            if not target.part   or not target.part.Parent  then continue end

            -- ── STEP 1: Move near egg ──────────────────────
            local arrived = false
            Move:To(target.part.Position, function() arrived=true end)

            -- Wait for arrival (max 10s)
            local t0 = tick()
            while not arrived and (tick()-t0) < 10 do task.wait(0.1) end
            if not arrived then continue end

            jw(0.4, 0.2)  -- brief pause after arriving

            -- ── STEP 2: Face the egg ──────────────────────
            local hrp = getHRP()
            if hrp then
                hrp.CFrame = CFrame.lookAt(
                    hrp.Position,
                    target.part.Position
                )
            end
            jw(0.2, 0.1)

            -- ── STEP 3: Simulate tap on prompt ────────────
            -- Get screen position of the egg/prompt
            local screenPos, onScreen = getPromptScreenPos(
                target.prompt, target.part)

            if onScreen and screenPos then
                -- The ProximityPrompt button appears near the part
                -- Tap slightly below part center (where the E/button is)
                tapAt(screenPos)
                jw(0.15, 0.05)
                tapAt(screenPos)  -- double tap for reliability
            else
                -- Part off screen: camera look-at first
                if hrp then
                    Cam.CFrame = CFrame.lookAt(
                        Cam.CFrame.Position,
                        target.part.Position
                    )
                    task.wait(0.1)
                end
                screenPos, onScreen = getPromptScreenPos(
                    target.prompt, target.part)
                if onScreen and screenPos then
                    tapAt(screenPos)
                    jw(0.12, 0.05)
                    tapAt(screenPos)
                end
            end

            jw(0.5, 0.2)

            -- ── STEP 4: Return to pen ─────────────────────
            if self.autoReturn then
                self._pen = self._pen or findPen()
                if self._pen then
                    local penDone = false
                    Move:To(self._pen.Position, function() penDone=true end)
                    local t1=tick()
                    while not penDone and (tick()-t1)<10 do task.wait(0.1) end
                end
            end
        end
    end)
end

function AutoSteal:Stop()
    self.enabled = false
    if Move._tween then Move._tween:Cancel() end
    local hrp = getHRP()
    if hrp then hrp.Anchored=false end
end

-- ════════════════════════════════════════════════════════════
-- [5] AUTO-TREADMILL
-- Moves character ON the treadmill and keeps it there.
-- Uses Move:To (tween) to reach it, then locks position.
-- ════════════════════════════════════════════════════════════
local AutoTreadmill = {
    enabled = false,
    _thread = nil,
    _tm     = nil,
    _lock   = nil,
}

function AutoTreadmill:Start()
    self.enabled = true
    self._tm     = findTreadmill()

    self._thread = task.spawn(function()
        if not self._tm then
            task.wait(3)
            self._tm = findTreadmill()
            if not self._tm then
                warn("[Crow] Treadmill not found")
                self.enabled=false; return
            end
        end

        -- Move to treadmill
        local arrived=false
        Move:To(self._tm.Position, function() arrived=true end)
        local t0=tick()
        while not arrived and (tick()-t0)<10 do task.wait(0.1) end

        task.wait(0.3)

        -- Lock character ON the treadmill with gentle re-centering
        -- Uses CFrame nudge (tiny, not flagged as teleport)
        local step = 0
        while self.enabled do
            local tm = self._tm
            if not tm or not tm.Parent then
                self._tm = findTreadmill()
                jw(2); continue
            end

            local hrp = getHRP()
            if not hrp then jw(0.5); continue end

            -- Re-center on treadmill surface
            local tmPos = tm.CFrame.Position + Vector3.new(0, tm.Size.Y/2+2.5, 0)
            local curPos = hrp.Position
            local diff = tmPos - curPos

            -- Only nudge if drifted more than 1 stud (avoid constant micro-jitter)
            if diff.Magnitude > 1.2 then
                -- Tiny CFrame correction — moves ≤1 stud, not flagged
                hrp.CFrame = hrp.CFrame + Vector3.new(
                    math.clamp(diff.X, -1, 1),
                    math.clamp(diff.Y, -1, 1),
                    math.clamp(diff.Z, -1, 1)
                )
            end

            -- Alternate side-step to simulate actual stepping motion
            step = step + 1
            if step % 4 == 0 then
                local nudge = (step%8==0) and 0.3 or -0.3
                hrp.CFrame = hrp.CFrame * CFrame.new(nudge, 0, 0)
            end

            jw(0.2, 0.08)
        end
    end)
end

function AutoTreadmill:Stop()
    self.enabled = false
end

-- ════════════════════════════════════════════════════════════
-- [6] AUTO-FARM (income collect / hatch — proximity only)
-- ════════════════════════════════════════════════════════════
local AutoFarm = {
    enabled = false,
    _thread = nil,
}

function AutoFarm:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            jw(1.5, 0.4)
            for _, obj in ipairs(WS:GetDescendants()) do
                if not self.enabled then break end
                if obj:IsA("ProximityPrompt") then
                    local at = obj.ActionText:lower()
                    if at:find("collect") or at:find("hatch")
                    or at:find("claim")   or at:find("income")
                    or at:find("cash")    or at:find("earn")
                    or at:find("pick")    or at:find("money") then
                        local part = obj.Parent
                        if part and part:IsA("BasePart") then
                            -- Move near, tap
                            local arrived=false
                            Move:To(part.Position,function() arrived=true end)
                            local t0=tick()
                            while not arrived and tick()-t0<8 do task.wait(0.1) end
                            jw(0.2,0.1)
                            local sp,on=getPromptScreenPos(obj,part)
                            if on and sp then tapAt(sp); jw(0.1) end
                        end
                    end
                end
            end
        end
    end)
end

function AutoFarm:Stop() self.enabled=false end

-- ════════════════════════════════════════════════════════════
-- [7] ESP (visual only — zero server interaction)
-- ════════════════════════════════════════════════════════════
local ESP = {
    enabled=false, showEggs=true, showGuardians=true,
    showTraps=true, showPlayers=true,
    _objs={},
}

local RC = {
    Divine    = Color3.fromRGB(255,255,80),
    Eternal   = Color3.fromRGB(255,120,0),
    Secret    = Color3.fromRGB(255,60,180),
    Cosmic    = Color3.fromRGB(0,230,255),
    Legendary = Color3.fromRGB(255,190,0),
    Epic      = Color3.fromRGB(160,60,240),
    Rare      = Color3.fromRGB(60,120,255),
    Uncommon  = Color3.fromRGB(60,220,80),
    Common    = Color3.fromRGB(200,200,200),
}
local function rc(r) return RC[r] or Color3.fromRGB(255,220,50) end

local function mkHL(part, col)
    pcall(function()
        local h = Instance.new("Highlight")
        h.Adornee              = part
        h.FillColor            = col
        h.OutlineColor         = col
        h.FillTransparency     = 0.55
        h.OutlineTransparency  = 0.0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent               = CoreGui
        table.insert(ESP._objs, h)
    end)
end

local function mkBB(adorn, text, col)
    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = true
    bb.Size        = UDim2.new(0,190,0,68)
    bb.StudsOffset = Vector3.new(0,5,0)
    bb.Adornee     = adorn
    bb.Parent      = CoreGui

    local bg = Instance.new("Frame",bb)
    bg.Size=UDim2.new(1,0,1,0)
    bg.BackgroundColor3=Color3.fromRGB(8,8,15)
    bg.BackgroundTransparency=0.2
    bg.BorderSizePixel=0
    Instance.new("UICorner",bg).CornerRadius=UDim.new(0,8)

    local lb = Instance.new("TextLabel",bg)
    lb.Size=UDim2.new(1,-8,1,-4)
    lb.Position=UDim2.new(0,4,0,2)
    lb.BackgroundTransparency=1
    lb.TextColor3=col or Color3.new(1,1,1)
    lb.TextScaled=true
    lb.Font=Enum.Font.GothamBold
    lb.Text=text
    lb.TextWrapped=true
    lb.TextStrokeTransparency=0.25
    lb.TextStrokeColor3=Color3.new(0,0,0)

    table.insert(ESP._objs,bb)
    return bb
end

function ESP:Clear()
    for _,o in ipairs(self._objs) do pcall(function() o:Destroy() end) end
    self._objs={}
end

function ESP:Refresh()
    self:Clear()
    if not self.enabled then return end

    local hrp=getHRP()
    local myP=hrp and hrp.Position

    if self.showEggs then
        for _, e in ipairs(scanEggs()) do
            local part=e.part
            if not part or not part.Parent then continue end
            local col=rc(e.rarity)
            local dist=myP and ("%ds"):format(
                math.floor((myP-part.Position).Magnitude)) or "?"
            local cash=e.income and ("$"..fn(e.income).."/s") or "?"
            mkHL(part,col)
            mkBB(part,"🥚 "..e.name.."\n💰 "..cash.."  ✨ "..(e.rarity or "?")
                     .."\n📍 "..dist,col)
        end
    end

    if self.showGuardians then
        for _, obj in ipairs(WS:GetDescendants()) do
            if obj:IsA("Humanoid") and obj.Parent~=LP.Character then
                local m=obj.Parent
                local rp=m:FindFirstChild("HumanoidRootPart")
                if not rp then continue end
                local isPlr=false
                for _,p in ipairs(Players:GetPlayers()) do
                    if p.Character==m then isPlr=true;break end
                end
                if isPlr then continue end
                local col=Color3.fromRGB(255,50,50)
                local dist=myP and ("%ds"):format(
                    math.floor((myP-rp.Position).Magnitude)) or "?"
                local d=myP and (myP-rp.Position).Magnitude or 999
                local warn=d<25 and "🔴 DANGER!" or "⚠️ GUARD"
                mkHL(rp,col)
                mkBB(rp,warn.."\n"..m.Name.."\n📍 "..dist,col)
            end
        end
    end

    if self.showTraps then
        for _, obj in ipairs(WS:GetDescendants()) do
            if obj:IsA("BasePart") then
                local nl=obj.Name:lower()
                if nl:find("trap") or nl:find("beartrap") then
                    local col=Color3.fromRGB(255,130,0)
                    local dist=myP and ("%ds"):format(
                        math.floor((myP-obj.Position).Magnitude)) or "?"
                    local own=obj:GetAttribute("Owner") or obj:GetAttribute("PlayerId")
                    local lbl=(own==tostring(LP.UserId)) and "🪤 MY TRAP" or "🪤 ENEMY TRAP"
                    mkHL(obj,col)
                    mkBB(obj,lbl.."\n📍 "..dist,col)
                end
            end
        end
    end

    if self.showPlayers then
        for _, p in ipairs(Players:GetPlayers()) do
            if p==LP or not p.Character then continue end
            local rp=p.Character:FindFirstChild("HumanoidRootPart")
            if not rp then continue end
            local col=Color3.fromRGB(100,200,255)
            local dist=myP and ("%ds"):format(
                math.floor((myP-rp.Position).Magnitude)) or "?"
            local inc=p:GetAttribute("TotalIncome")
                   or p:GetAttribute("Income")
                   or p:GetAttribute("MPS")
            local incS=inc and ("$"..fn(inc).."/s") or "?"
            mkHL(rp,col)
            mkBB(rp,"👤 "..p.DisplayName.."\n💰 "..incS.."\n📍 "..dist,col)
        end
    end
end

task.spawn(function()
    while true do
        task.wait(2.5)
        if ESP.enabled then pcall(function() ESP:Refresh() end) end
    end
end)

-- ════════════════════════════════════════════════════════════
-- [8] NOCLIP
-- ════════════════════════════════════════════════════════════
local NC={enabled=false,_c=nil}
function NC:En()
    self.enabled=true
    self._c=RunService.Stepped:Connect(function()
        local c=LP.Character
        if not c then return end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
    end)
end
function NC:Dis()
    self.enabled=false
    if self._c then self._c:Disconnect();self._c=nil end
    local c=LP.Character
    if c then for _,p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide=true end
    end end
end

-- ════════════════════════════════════════════════════════════
-- [9] UI
-- ════════════════════════════════════════════════════════════
local old=CoreGui:FindFirstChild("CrowSAE4")
if old then old:Destroy() end

local SG=Instance.new("ScreenGui")
SG.Name="CrowSAE4"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset=true; SG.DisplayOrder=9999
SG.Parent=CoreGui

local C={
    BG=Color3.fromRGB(11,11,19),  BG2=Color3.fromRGB(19,19,31),
    BG3=Color3.fromRGB(26,26,40), ACC=Color3.fromRGB(100,50,200),
    ACC2=Color3.fromRGB(65,165,255), ON=Color3.fromRGB(50,205,95),
    OFF=Color3.fromRGB(65,65,90),  RED=Color3.fromRGB(215,50,50),
    WARN=Color3.fromRGB(235,155,35),TXT=Color3.fromRGB(228,228,240),
    SUB=Color3.fromRGB(150,150,172),BOR=Color3.fromRGB(50,32,90),
}

-- Main frame
local MF=Instance.new("Frame",SG)
MF.Name="MF"; MF.Size=UDim2.new(0,350,0,495)
MF.Position=UDim2.new(0,8,0.12,0)
MF.BackgroundColor3=C.BG; MF.BorderSizePixel=0
MF.Active=true; MF.Draggable=true; MF.ClipsDescendants=true
Instance.new("UICorner",MF).CornerRadius=UDim.new(0,12)
local _st=Instance.new("UIStroke",MF); _st.Color=C.BOR; _st.Thickness=1.5

-- Title bar
local TB=Instance.new("Frame",MF)
TB.Size=UDim2.new(1,0,0,46); TB.BackgroundColor3=C.BG2
TB.BorderSizePixel=0; TB.ZIndex=2
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,12)
local TG=Instance.new("UIGradient",TB)
TG.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,C.ACC),
    ColorSequenceKeypoint.new(1,C.ACC2),
}); TG.Rotation=90

local TL=Instance.new("TextLabel",TB)
TL.Text="🥚 STEAL AN EGG  |  CROW v4.0  🛡STEALTH"
TL.Font=Enum.Font.GothamBold; TL.TextSize=12
TL.TextColor3=C.TXT; TL.BackgroundTransparency=1
TL.Size=UDim2.new(1,-48,1,0); TL.Position=UDim2.new(0,10,0,0)
TL.TextXAlignment=Enum.TextXAlignment.Left; TL.ZIndex=3

-- Close → hide (NOT destroy)
local XB=Instance.new("TextButton",TB)
XB.Text="✕"; XB.Font=Enum.Font.GothamBold; XB.TextSize=15
XB.TextColor3=C.TXT; XB.BackgroundColor3=C.RED
XB.BorderSizePixel=0; XB.Size=UDim2.new(0,30,0,30)
XB.Position=UDim2.new(1,-38,0,8); XB.ZIndex=4
Instance.new("UICorner",XB).CornerRadius=UDim.new(0,6)
XB.MouseButton1Click:Connect(function() MF.Visible=false end)

-- Floating egg button (always visible, reopens)
local EggBtn=Instance.new("TextButton",SG)
EggBtn.Text="🥚"; EggBtn.Font=Enum.Font.GothamBold; EggBtn.TextSize=22
EggBtn.TextColor3=Color3.new(1,1,1); EggBtn.BackgroundColor3=C.ACC
EggBtn.BorderSizePixel=0; EggBtn.Size=UDim2.new(0,50,0,50)
EggBtn.Position=UDim2.new(0,8,0.12,0); EggBtn.ZIndex=100
EggBtn.Visible=false; EggBtn.Active=true; EggBtn.Draggable=true
Instance.new("UICorner",EggBtn).CornerRadius=UDim.new(1,0)
EggBtn.MouseButton1Click:Connect(function()
    MF.Visible=true; EggBtn.Visible=false
end)
XB.MouseButton1Click:Connect(function()
    MF.Visible=false; EggBtn.Visible=true
end)

-- Tab system
local TABS={"⚡Main","🥚Steal","👁ESP","💰Farm","🗺Biomes","⚙️More"}
local Pages={};local TabBtns={}

local TabBar=Instance.new("Frame",MF)
TabBar.Size=UDim2.new(1,0,0,36); TabBar.Position=UDim2.new(0,0,0,46)
TabBar.BackgroundColor3=C.BG2; TabBar.BorderSizePixel=0
local TBL=Instance.new("UIListLayout",TabBar)
TBL.FillDirection=Enum.FillDirection.Horizontal
TBL.SortOrder=Enum.SortOrder.LayoutOrder; TBL.Padding=UDim.new(0,2)

local CF=Instance.new("ScrollingFrame",MF)
CF.Size=UDim2.new(1,0,1,-82); CF.Position=UDim2.new(0,0,0,82)
CF.BackgroundTransparency=1; CF.BorderSizePixel=0
CF.ScrollBarThickness=3; CF.CanvasSize=UDim2.new(0,0,0,0)
CF.AutomaticCanvasSize=Enum.AutomaticSize.Y
CF.ScrollBarImageColor3=C.ACC

local CFL=Instance.new("UIListLayout",CF)
CFL.SortOrder=Enum.SortOrder.LayoutOrder; CFL.Padding=UDim.new(0,5)
local CFP=Instance.new("UIPadding",CF)
CFP.PaddingLeft=UDim.new(0,8); CFP.PaddingRight=UDim.new(0,8)
CFP.PaddingTop=UDim.new(0,6); CFP.PaddingBottom=UDim.new(0,6)

local function mkPg(name)
    local p=Instance.new("Frame",CF)
    p.Name=name; p.Visible=false
    p.Size=UDim2.new(1,0,0,0); p.AutomaticSize=Enum.AutomaticSize.Y
    p.BackgroundTransparency=1; p.BorderSizePixel=0
    local l=Instance.new("UIListLayout",p)
    l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,5)
    Pages[name]=p; return p
end

local function showTab(name)
    for n,pg in pairs(Pages) do pg.Visible=(n==name) end
    for _,b in ipairs(TabBtns) do
        b.TextColor3=C.SUB; b.BackgroundColor3=C.BG2
    end
    for i,t in ipairs(TABS) do
        if t==name and TabBtns[i] then
            TabBtns[i].TextColor3=Color3.new(1,1,1)
            TabBtns[i].BackgroundColor3=C.ACC
        end
    end
end

for i,tn in ipairs(TABS) do
    mkPg(tn)
    local b=Instance.new("TextButton",TabBar)
    b.Text=tn; b.Font=Enum.Font.Gotham; b.TextSize=9
    b.TextColor3=C.SUB; b.BackgroundColor3=C.BG2
    b.BorderSizePixel=0; b.Size=UDim2.new(0,51,1,0)
    b.LayoutOrder=i
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,4)
    TabBtns[i]=b
    b.MouseButton1Click:Connect(function() showTab(tn) end)
end

-- UI Helpers
local function mkH(p,t,col)
    local l=Instance.new("TextLabel",p)
    l.Text=t; l.Font=Enum.Font.GothamBold; l.TextSize=10
    l.TextColor3=col or C.ACC; l.BackgroundTransparency=1
    l.Size=UDim2.new(1,0,0,20); l.TextXAlignment=Enum.TextXAlignment.Left
    return l
end

local function mkTG(p,label,sub,def,cb)
    local row=Instance.new("Frame",p)
    row.Size=UDim2.new(1,0,0,54); row.BackgroundColor3=C.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,8)
    local n=Instance.new("TextLabel",row)
    n.Text=label; n.Font=Enum.Font.GothamBold; n.TextSize=12
    n.TextColor3=C.TXT; n.BackgroundTransparency=1
    n.Size=UDim2.new(1,-62,0,26); n.Position=UDim2.new(0,10,0,6)
    n.TextXAlignment=Enum.TextXAlignment.Left
    local s=Instance.new("TextLabel",row)
    s.Text=sub or ""; s.Font=Enum.Font.Gotham; s.TextSize=9
    s.TextColor3=C.SUB; s.BackgroundTransparency=1
    s.Size=UDim2.new(1,-62,0,18); s.Position=UDim2.new(0,10,0,30)
    s.TextXAlignment=Enum.TextXAlignment.Left; s.TextWrapped=true
    local pill=Instance.new("Frame",row)
    pill.Size=UDim2.new(0,46,0,24); pill.Position=UDim2.new(1,-56,0.5,-12)
    pill.BackgroundColor3=def and C.ON or C.OFF; pill.BorderSizePixel=0
    Instance.new("UICorner",pill).CornerRadius=UDim.new(0,12)
    local knob=Instance.new("Frame",pill)
    knob.Size=UDim2.new(0,18,0,18)
    knob.Position=def and UDim2.new(0,25,0,3) or UDim2.new(0,3,0,3)
    knob.BackgroundColor3=Color3.new(1,1,1); knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(0,9)
    local state=def
    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    btn.MouseButton1Click:Connect(function()
        state=not state
        pill.BackgroundColor3=state and C.ON or C.OFF
        TweenService:Create(knob,TweenInfo.new(0.12),{
            Position=state and UDim2.new(0,25,0,3) or UDim2.new(0,3,0,3)
        }):Play()
        if cb then cb(state) end
    end)
    return row
end

local function mkBT(p,text,col,cb)
    local b=Instance.new("TextButton",p)
    b.Text=text; b.Font=Enum.Font.GothamBold; b.TextSize=12
    b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=col or C.ACC
    b.BorderSizePixel=0; b.Size=UDim2.new(1,0,0,38)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseButton1Click:Connect(function()
        if cb then cb() end
        TweenService:Create(b,TweenInfo.new(0.08),
            {BackgroundTransparency=0.4}):Play()
        task.delay(0.15,function()
            TweenService:Create(b,TweenInfo.new(0.08),
                {BackgroundTransparency=0}):Play()
        end)
    end)
    return b
end

local function mkIF(p,t)
    local f=Instance.new("Frame",p)
    f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
    f.BackgroundColor3=C.BG2; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local pd=Instance.new("UIPadding",f)
    pd.PaddingLeft=UDim.new(0,8); pd.PaddingTop=UDim.new(0,5)
    pd.PaddingRight=UDim.new(0,8); pd.PaddingBottom=UDim.new(0,5)
    local l=Instance.new("TextLabel",f)
    l.Text=t; l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextColor3=C.SUB
    l.BackgroundTransparency=1; l.Size=UDim2.new(1,0,0,0)
    l.AutomaticSize=Enum.AutomaticSize.Y
    l.TextXAlignment=Enum.TextXAlignment.Left; l.TextWrapped=true
    return f,l
end

-- ── MAIN TAB ─────────────────────────────────────────────
local pg=Pages["⚡Main"]
mkH(pg,"  ◆ STATUS v4.0 — STEALTH BUILD",C.ON)
local _,stLbl=mkIF(pg,"🔄 Scanning workspace... (4s)")

task.spawn(function()
    task.wait(5)
    local eggs=scanEggs()
    local tm=findTreadmill()
    local pen=findPen()
    stLbl.Text=
        "✅ Eggs: "..#eggs.."  |  "..
        (tm  and "✅ TM: "..tm.Name   or "⚠️ Treadmill: not found").."  |  "..
        (pen and "✅ Pen: "..pen.Name or "⚠️ Pen: not found")
    stLbl.TextColor3=#eggs>0 and C.ON or C.WARN
end)

mkH(pg,"  ◆ STEALTH STATUS",C.ON)
mkIF(pg,"🛡 No fireproximityprompt\n🛡 No direct CFrame jump\n🛡 No WalkSpeed set\n🛡 TweenService movement (believable speed)\n🛡 VirtualUser tap simulation\n🛡 Jittered all loops")

mkH(pg,"  ◆ QUICK TOGGLES")
mkTG(pg,"Auto-Steal","TweenMove + VirtualUser tap (stealth)",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkTG(pg,"Auto-Treadmill","Stays on treadmill, simulates steps",false,function(on)
    if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
end)
mkTG(pg,"Auto-Farm","Collect income + hatch eggs",false,function(on)
    if on then AutoFarm:Start() else AutoFarm:Stop() end
end)
mkTG(pg,"ESP","Show eggs with real $/s — visual only",false,function(on)
    ESP.enabled=on; ESP:Refresh()
end)
mkBT(pg,"🔄 Rescan",C.ACC2,function()
    local eggs=scanEggs(); local tm=findTreadmill(); local pen=findPen()
    stLbl.Text="Eggs: "..#eggs.."  TM: "..(tm and tm.Name or "nil")
              .."  Pen: "..(pen and pen.Name or "nil")
end)

-- ── STEAL TAB ────────────────────────────────────────────
pg=Pages["🥚Steal"]
mkH(pg,"  ◆ AUTO-STEAL")
mkTG(pg,"Auto-Steal","Tween movement + screen tap — no kick",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkTG(pg,"Return to Pen","After each steal",true,function(on)
    AutoSteal.autoReturn=on
end)
mkTG(pg,"Noclip","Walk through walls",false,function(on)
    if on then NC:En() else NC:Dis() end
end)

mkH(pg,"  ◆ RARITY FILTER")
local rarOpts={"Any","Rare+","Epic+","Legendary+","Cosmic+"}
for _,opt in ipairs(rarOpts) do
    mkBT(pg,opt,C.BG3,function()
        AutoSteal.rareFilter=opt
    end)
end

mkH(pg,"  ◆ MOVE SPEED")
mkIF(pg,"Tween speed = how fast character walks to eggs.\nHigher = slightly less stealth.")
local spOpts={{"Slow (20 s/s)",20},{"Normal (35 s/s)",35},
              {"Fast (48 s/s)",48},{"Max (55 s/s)",55}}
for _,sp in ipairs(spOpts) do
    mkBT(pg,sp[1],C.ACC,function() Move:SetSpeed(sp[2]) end)
end

mkH(pg,"  ◆ MANUAL")
mkBT(pg,"Steal Once",C.ACC,function()
    local eggs=scanEggs()
    if #eggs>0 then
        local e=eggs[1]
        local done=false
        Move:To(e.part.Position,function() done=true end)
        task.spawn(function()
            local t=tick()
            while not done and tick()-t<10 do task.wait(0.1) end
            task.wait(0.25)
            local sp,on=getPromptScreenPos(e.prompt,e.part)
            if on and sp then tapAt(sp); task.wait(0.1); tapAt(sp) end
        end)
    end
end)
mkBT(pg,"Return to Pen",C.ACC2,function()
    local pen=findPen()
    if pen then Move:To(pen.Position,nil) end
end)

-- ── ESP TAB ──────────────────────────────────────────────
pg=Pages["👁ESP"]
mkH(pg,"  ◆ ESP")
mkTG(pg,"Enable ESP","Highlights + income labels",false,function(on)
    ESP.enabled=on; ESP:Refresh()
end)
mkTG(pg,"Show Eggs","Real $/s from attributes",true,function(on)
    ESP.showEggs=on; if ESP.enabled then ESP:Refresh() end
end)
mkTG(pg,"Show Guardians","Danger warning when close",true,function(on)
    ESP.showGuardians=on; if ESP.enabled then ESP:Refresh() end
end)
mkTG(pg,"Show Bear Traps","Enemy traps",true,function(on)
    ESP.showTraps=on; if ESP.enabled then ESP:Refresh() end
end)
mkTG(pg,"Show Players","Other players + income",true,function(on)
    ESP.showPlayers=on; if ESP.enabled then ESP:Refresh() end
end)
mkBT(pg,"🔄 Refresh Now",C.ACC2,function() ESP:Refresh() end)

-- ── FARM TAB ─────────────────────────────────────────────
pg=Pages["💰Farm"]
mkH(pg,"  ◆ AUTO-FARM")
mkTG(pg,"Auto-Collect / Hatch","All collect prompts",false,function(on)
    if on then AutoFarm:Start() else AutoFarm:Stop() end
end)
mkTG(pg,"Auto-Steal","Full steal loop",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkTG(pg,"Auto-Treadmill","AFK speed",false,function(on)
    if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
end)

-- ── BIOMES TAB ───────────────────────────────────────────
pg=Pages["🗺Biomes"]
mkH(pg,"  ◆ BIOME TP  (Tween — Stealth)")
mkIF(pg,"Uses TweenService movement — not instant jump.")
local BD={
    {n="Forest",s="0"},{n="Lake",s="900"},{n="Desert",s="10K"},
    {n="Jungle",s="40K"},{n="Snow",s="170K"},{n="Volcano",s="700K"},
    {n="Abyss",s="3M"},{n="Prehistoric",s="10M"},{n="Cosmic",s="50M"},
    {n="Cherry",s="2.5B"},{n="Titan",s="10B"},{n="Angels",s="25B"},
    {n="Enchanted",s="50B"},
}
for _,bd in ipairs(BD) do
    local row=Instance.new("Frame",pg)
    row.Size=UDim2.new(1,0,0,42); row.BackgroundColor3=C.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    local nl=Instance.new("TextLabel",row)
    nl.Text=bd.n; nl.Font=Enum.Font.GothamBold; nl.TextSize=12
    nl.TextColor3=C.TXT; nl.BackgroundTransparency=1
    nl.Size=UDim2.new(1,-90,0,22); nl.Position=UDim2.new(0,10,0,4)
    nl.TextXAlignment=Enum.TextXAlignment.Left
    local sl=Instance.new("TextLabel",row)
    sl.Text="≥"..bd.s.." spd"; sl.Font=Enum.Font.Gotham; sl.TextSize=9
    sl.TextColor3=C.SUB; sl.BackgroundTransparency=1
    sl.Size=UDim2.new(1,-90,0,14); sl.Position=UDim2.new(0,10,0,26)
    sl.TextXAlignment=Enum.TextXAlignment.Left
    local tb=Instance.new("TextButton",row)
    tb.Text="TP →"; tb.Font=Enum.Font.GothamBold; tb.TextSize=11
    tb.TextColor3=Color3.new(1,1,1); tb.BackgroundColor3=C.ACC
    tb.BorderSizePixel=0; tb.Size=UDim2.new(0,68,0,26)
    tb.Position=UDim2.new(1,-78,0.5,-13)
    Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
    local bname=bd.n
    tb.MouseButton1Click:Connect(function()
        local kl=bname:lower()
        local best=nil
        for _,obj in ipairs(WS:GetDescendants()) do
            if obj.Name:lower():find(kl) and obj:IsA("BasePart") then
                best=obj; break
            end
        end
        if best then Move:To(best.Position,nil) end
    end)
end

-- ── MORE TAB ─────────────────────────────────────────────
pg=Pages["⚙️More"]
mkH(pg,"  ◆ TOOLS")
mkTG(pg,"Noclip","Walk through walls",false,function(on)
    if on then NC:En() else NC:Dis() end
end)
mkBT(pg,"📋 Print Egg List (Console)",C.BG3,function()
    local eggs=scanEggs()
    print("[Crow v4] Eggs found:",#eggs)
    for i,e in ipairs(eggs) do
        print(i,e.name,e.rarity,e.income and ("$"..fn(e.income).."/s") or "?")
    end
end)
mkBT(pg,"Hide Menu",C.BG3,function()
    MF.Visible=false; EggBtn.Visible=true
end)
mkBT(pg,"❌ Destroy Script",C.RED,function()
    AutoSteal:Stop(); AutoTreadmill:Stop(); AutoFarm:Stop()
    ESP:Clear(); NC:Dis(); SG:Destroy()
end)

-- ════════════════════════════════════════════════════════════
-- RESPAWN
-- ════════════════════════════════════════════════════════════
LP.CharacterAdded:Connect(function()
    task.wait(2)
    if NC.enabled      then NC:Dis();NC:En() end
    if AutoTreadmill.enabled then
        AutoTreadmill:Stop(); task.wait(0.5); AutoTreadmill:Start()
    end
end)

-- ════════════════════════════════════════════════════════════
-- INIT
-- ════════════════════════════════════════════════════════════
showTab("⚡Main")
print("[Crow v4.0] STEALTH BUILD loaded")
print("[Crow v4.0] BAC bypass: TweenMove + VirtualUser + no WalkSpeed set")
