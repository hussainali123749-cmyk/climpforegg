--[[
╔═══════════════════════════════════════════════════════════╗
║      STEAL AN EGG — CROW MENU v3.0 (DELTA MOBILE)       ║
║  Full rebuild — ProximityPrompt + TouchPart detection    ║
║  No Remote guessing. No folder name assumptions.         ║
║  Works by reading what actually exists in Workspace.     ║
╚═══════════════════════════════════════════════════════════╝
--]]

-- ════════════════════════════════════════════════════════════
-- [0] SERVICES
-- ════════════════════════════════════════════════════════════
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")
local ContextActionService = game:GetService("ContextActionService")
local CoreGui          = game:GetService("CoreGui")
local WS               = game:GetService("Workspace")
local RS               = game:GetService("ReplicatedStorage")

local LP   = Players.LocalPlayer
local Cam  = WS.CurrentCamera

-- ════════════════════════════════════════════════════════════
-- [1] UTILITY
-- ════════════════════════════════════════════════════════════
local function getChar()
    return LP.Character or LP.CharacterAdded:Wait()
end
local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- Safe teleport with micro-jitter (anti-repeated-coord flag)
local function safeTeleport(pos)
    local hrp = getHRP()
    if not hrp then return end
    local jitter = Vector3.new(
        (math.random()-0.5)*0.6,
        0,
        (math.random()-0.5)*0.6
    )
    hrp.CFrame = CFrame.new(pos + Vector3.new(0,3,0) + jitter)
end

-- Jittered wait
local function jwait(base, variance)
    variance = variance or base * 0.25
    task.wait(base + (math.random()-0.5)*2*variance)
end

-- Format large numbers
local function fmtNum(n)
    if not n or n==0 then return "?" end
    if n>=1e12 then return ("%.1fT"):format(n/1e12) end
    if n>=1e9  then return ("%.1fB"):format(n/1e9)  end
    if n>=1e6  then return ("%.1fM"):format(n/1e6)  end
    if n>=1e3  then return ("%.1fK"):format(n/1e3)  end
    return tostring(math.floor(n))
end
local function fmtCash(n)
    return n and "$"..fmtNum(n).."/s" or "$?"
end

-- ════════════════════════════════════════════════════════════
-- [2] GAME SCANNER
-- Reads the actual Workspace structure to find:
--   • ProximityPrompts on eggs (steal action)
--   • Treadmill TouchParts
--   • Guardian NPCs
--   • Player pen / garden parts
--   • Bear trap parts
-- No hardcoded folder names — scans everything.
-- ════════════════════════════════════════════════════════════
local Scanner = {}
Scanner.eggs      = {}  -- {part, prompt, cashValue, rarity, name}
Scanner.treadmill = nil -- BasePart to stand on
Scanner.guardians = {}  -- {model, hrp}
Scanner.pen       = nil -- BasePart: player's home/garden
Scanner.bearTraps = {}  -- BasePart list

-- Known pet income (fallback when attribute missing)
local PET_INCOME = {
    chicken=1,dog=2,bird=8,["burrowing owl"]=35,raccoon=45,
    fox=180,bear=240,["brr brr patapim"]=1800,
    frog=3,duckling=4,catfish=12,turtle=60,
    ["trulimero trulicina"]=260,swan=320,axolotl=2800,
    leviathan=220000,jerboa=400,camel=4000,vulture=90000,
    ["royal sphinx"]=280000,parrot=5000,monkey=12000,
    jaguar=80000,anaconda=200000,["king snake"]=3500000,
    penguin=50000,["polar bear"]=300000,mammoth=8000000,
    ["ice dragon"]=65000000,phoenix=5000000,
    ["lava dragon"]=1e8,
}

local ATTR_KEYS = {
    "CashValue","Value","Income","MoneyPerSecond","MPS",
    "CashPerSecond","Earnings","EggValue","PetIncome",
    "PetCash","BaseIncome","BaseCash","IncomePerSecond",
    "EggIncome","EggCash","HatchIncome","Money","Cash",
    "EggMoney","PetValue","PetEarnings","SellValue",
}

local function readIncome(obj)
    for _, k in ipairs(ATTR_KEYS) do
        local v = obj:GetAttribute(k)
        if type(v)=="number" and v>0 then return v end
    end
    -- check parent
    if obj.Parent and obj.Parent ~= WS then
        for _, k in ipairs(ATTR_KEYS) do
            local v = obj.Parent:GetAttribute(k)
            if type(v)=="number" and v>0 then return v end
        end
    end
    -- value children
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("NumberValue") or child:IsA("IntValue") then
            if child.Value and child.Value>0 then return child.Value end
        end
    end
    -- name fallback
    local nl = obj.Name:lower():gsub("egg",""):match("^%s*(.-)%s*$")
    for pname, inc in pairs(PET_INCOME) do
        if nl:find(pname,1,true) or pname:find(nl,1,true) then
            return inc
        end
    end
    return nil
end

local function readRarity(obj)
    local keys = {"Rarity","EggRarity","Type","Tier","Grade"}
    for _, k in ipairs(keys) do
        local v = obj:GetAttribute(k)
            or (obj.Parent and obj.Parent:GetAttribute(k))
        if v then return tostring(v) end
    end
    -- infer from name
    local n = obj.Name:lower()
    if n:find("divine")   then return "Divine"   end
    if n:find("eternal")  then return "Eternal"  end
    if n:find("secret")   then return "Secret"   end
    if n:find("cosmic")   then return "Cosmic"   end
    if n:find("legendary") or n:find("legend") then return "Legendary" end
    if n:find("epic")     then return "Epic"     end
    if n:find("rare")     then return "Rare"     end
    if n:find("uncommon") then return "Uncommon" end
    return "Common"
end

function Scanner:Scan()
    self.eggs      = {}
    self.guardians = {}
    self.bearTraps = {}
    self.treadmill = nil
    self.pen       = nil

    local uid = tostring(LP.UserId)

    for _, obj in ipairs(WS:GetDescendants()) do
        local nl = obj.Name:lower()

        -- ── EGGS: find ProximityPrompts whose ActionText is "Steal"
        if obj:IsA("ProximityPrompt") then
            local at = obj.ActionText:lower()
            local ot = obj.ObjectText:lower()
            if at:find("steal") or at:find("grab") or at:find("take")
            or ot:find("egg") then
                local part = obj.Parent
                if part and part:IsA("BasePart") then
                    table.insert(self.eggs, {
                        part   = part,
                        prompt = obj,
                        income = readIncome(part),
                        rarity = readRarity(part),
                        name   = part.Name,
                    })
                end
            end
            -- Also catch prompts on Model parents
            if obj.Parent and obj.Parent:IsA("Model") then
                local at2 = obj.ActionText:lower()
                if at2:find("steal") or at2:find("egg") then
                    local m   = obj.Parent
                    local pp  = m.PrimaryPart or m:FindFirstChildOfClass("BasePart")
                    if pp then
                        table.insert(self.eggs, {
                            part   = pp,
                            prompt = obj,
                            income = readIncome(m),
                            rarity = readRarity(m),
                            name   = m.Name,
                        })
                    end
                end
            end
        end

        -- ── TREADMILL: part you stand on to gain speed
        if obj:IsA("BasePart") then
            if nl:find("treadmill") or nl:find("tread") then
                -- prefer the one owned by this player
                local owner = obj:GetAttribute("Owner")
                           or obj:GetAttribute("PlayerId")
                           or obj:GetAttribute("UserId")
                if owner == uid or owner == LP.UserId then
                    self.treadmill = obj
                elseif not self.treadmill then
                    self.treadmill = obj
                end
            end

            -- ── BEAR TRAPS
            if nl:find("trap") or nl:find("beartrap") then
                table.insert(self.bearTraps, obj)
            end

            -- ── PEN / GARDEN / HOME BASE
            if (nl:find("pen") or nl:find("garden") or
                nl:find("home") or nl:find("base") or
                nl:find("hatch") or nl:find("nest")) then
                local owner = obj:GetAttribute("Owner")
                           or obj:GetAttribute("PlayerId")
                           or obj:GetAttribute("UserId")
                if owner == uid or owner == LP.UserId then
                    self.pen = obj
                elseif not self.pen and
                       (nl:find("hatch") or nl:find("garden")) then
                    self.pen = obj
                end
            end
        end

        -- ── GUARDIANS: NPCs / Models with Humanoid
        if obj:IsA("Humanoid") and obj.Parent ~= LP.Character then
            local model = obj.Parent
            local hrp2  = model:FindFirstChild("HumanoidRootPart")
            if hrp2 then
                local mn = model.Name:lower()
                -- Exclude players
                local isPlayer = false
                for _, plr in ipairs(Players:GetPlayers()) do
                    if plr.Character == model then
                        isPlayer = true; break
                    end
                end
                if not isPlayer then
                    table.insert(self.guardians, {model=model, hrp=hrp2})
                end
            end
        end
    end

    -- Fallback pen: player SpawnLocation
    if not self.pen then
        for _, obj in ipairs(WS:GetDescendants()) do
            if obj:IsA("SpawnLocation") then
                local attr = obj:GetAttribute("PlayerId")
                          or obj:GetAttribute("UserId")
                if attr == LP.UserId or attr == uid then
                    self.pen = obj; break
                end
            end
        end
    end

    -- Treadmill fallback: any part named treadmill in player's area
    -- Use SpawnLocation position to find nearest if needed
    if not self.treadmill and self.pen then
        local penPos = self.pen.Position
        local closest, closestDist = nil, math.huge
        for _, obj in ipairs(WS:GetDescendants()) do
            local on = obj.Name:lower()
            if obj:IsA("BasePart") and
               (on:find("treadmill") or on:find("tread") or on:find("mill")) then
                local d = (obj.Position - penPos).Magnitude
                if d < closestDist then
                    closestDist = d
                    closest     = obj
                end
            end
        end
        self.treadmill = closest
    end
end

-- Run initial scan after a short wait for workspace to populate
task.spawn(function()
    task.wait(4)
    Scanner:Scan()
end)

-- ════════════════════════════════════════════════════════════
-- [3] AUTO-STEAL
-- Uses ProximityPrompt:TriggerPrompt() — the only correct way.
-- Teleports to egg, fires prompt, teleports home.
-- ════════════════════════════════════════════════════════════
local AutoSteal = {
    enabled     = false,
    targetBiome = "Any",
    rareFilter  = "Any",
    autoReturn  = true,
    _thread     = nil,
}

local RARITY_RANK = {
    Common=1, Uncommon=2, Rare=3, Epic=4,
    Legendary=5, Cosmic=6, Secret=7, Eternal=8, Divine=9
}

local function rarityRank(r)
    return RARITY_RANK[r] or 1
end

local FILTER_MIN = {
    ["Any"]=0, ["Rare+"]=3, ["Epic+"]=4, ["Legendary+"]=5, ["Cosmic+"]=6
}

function AutoSteal:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            jwait(1.4, 0.5)

            if #Scanner.eggs == 0 then
                Scanner:Scan()
                jwait(2, 0.5)
                if #Scanner.eggs == 0 then continue end
            end

            local hrp = getHRP()
            if not hrp then jwait(1) continue end

            -- Filter by rarity
            local minRank = FILTER_MIN[self.rareFilter] or 0
            local candidates = {}
            for _, egg in ipairs(Scanner.eggs) do
                if rarityRank(egg.rarity) >= minRank then
                    table.insert(candidates, egg)
                end
            end
            if #candidates == 0 then continue end

            -- Sort: highest income first, then by distance
            table.sort(candidates, function(a, b)
                local ai = a.income or 0
                local bi = b.income or 0
                if math.abs(ai - bi) > 10 then return ai > bi end
                local ap = a.part.Position
                local bp = b.part.Position
                local hp = hrp.Position
                return (hp-ap).Magnitude < (hp-bp).Magnitude
            end)

            local target = candidates[1]
            if not target then continue end

            -- Check prompt is still valid
            if not target.prompt or not target.prompt.Parent then
                Scanner:Scan()
                continue
            end

            -- Teleport to egg
            safeTeleport(target.part.Position)
            jwait(0.25, 0.08)

            -- Fire the ProximityPrompt
            -- TriggerPrompt works in most executors incl Delta
            local ok = pcall(function()
                fireproximityprompt(target.prompt)
            end)
            if not ok then
                -- Fallback: TriggerPrompt method
                pcall(function()
                    target.prompt:TriggerPrompt()
                end)
            end

            jwait(0.35, 0.1)

            -- Return to pen
            if self.autoReturn and Scanner.pen then
                safeTeleport(Scanner.pen.Position)
            end
        end
    end)
end

function AutoSteal:Stop()
    self.enabled = false
end

-- ════════════════════════════════════════════════════════════
-- [4] AUTO-TREADMILL
-- Stands on the treadmill part. The game detects touch via
-- Touched event or a server-side proximity check.
-- We keep the character's HRP exactly on the part center,
-- with tiny random nudges to simulate real steps.
-- ════════════════════════════════════════════════════════════
local AutoTreadmill = {
    enabled = false,
    _thread = nil,
}

function AutoTreadmill:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        -- Re-scan to make sure we have the treadmill
        if not Scanner.treadmill then
            Scanner:Scan()
            task.wait(1)
        end

        if not Scanner.treadmill then
            warn("[Crow] Treadmill not found after scan")
            self.enabled = false
            return
        end

        -- Teleport onto treadmill first
        safeTeleport(Scanner.treadmill.Position)
        task.wait(0.5)

        local stepDir = 1
        while self.enabled do
            local tm = Scanner.treadmill
            if not tm or not tm.Parent then
                Scanner:Scan()
                task.wait(2)
                tm = Scanner.treadmill
                if not tm then break end
            end

            local hrp = getHRP()
            if not hrp then task.wait(0.5) continue end

            -- Keep character centered on treadmill + nudge
            -- Nudge simulates actual stepping (required for
            -- games that use Touched to register steps)
            local base = tm.CFrame.Position
                       + Vector3.new(0, tm.Size.Y/2 + 3, 0)
            local nudge = Vector3.new(
                (math.random()-0.5) * 0.8 * stepDir,
                0,
                (math.random()-0.5) * 0.3
            )
            stepDir = -stepDir  -- alternate direction

            hrp.CFrame = CFrame.new(base + nudge)

            -- Also fire VirtualUser click to simulate mobile tap
            -- (some treadmills need a click/touch event)
            pcall(function()
                VirtualUser:ClickButton2(Vector2.new(
                    math.random(700, 800),
                    math.random(400, 500)
                ))
            end)

            jwait(0.18, 0.06)  -- ~5-6 steps/sec with jitter
        end
    end)
end

function AutoTreadmill:Stop()
    self.enabled = false
end

-- ════════════════════════════════════════════════════════════
-- [5] SPEED MODULE (smooth WalkSpeed lerp, no BodyVelocity)
-- ════════════════════════════════════════════════════════════
local SpeedModule = {
    enabled      = false,
    _conn        = nil,
    _current     = 16,
    _target      = 48,
    PRESETS = {
        {label="🐢 Slow   (×1.5)",  speed=24 },
        {label="🚶 Normal (×2)",    speed=32 },
        {label="🏃 Fast   (×3)",    speed=48 },
        {label="⚡ Sprint (×5)",    speed=80 },
        {label="🦅 Crow   (×7)",    speed=112},
    },
    _presetIdx = 3,
}

function SpeedModule:Enable()
    self.enabled = true
    self._target = self.PRESETS[self._presetIdx].speed
    if self._conn then self._conn:Disconnect() end

    self._conn = RunService.Heartbeat:Connect(function(dt)
        local hum = getHum()
        if not hum then return end
        local f = 1-(0.80^(dt*60))
        self._current = self._current + (self._target - self._current)*f
        hum.WalkSpeed = math.clamp(math.floor(self._current+0.5), 16, 120)
    end)
end

function SpeedModule:SetPreset(i)
    self._presetIdx = i
    self._target    = self.PRESETS[i].speed
end

function SpeedModule:Disable()
    self.enabled = false
    if self._conn then self._conn:Disconnect(); self._conn=nil end
    task.spawn(function()
        for i=1,20 do
            local hum = getHum()
            if not hum then break end
            hum.WalkSpeed = math.max(16, hum.WalkSpeed - (hum.WalkSpeed-16)/6)
            task.wait(0.016)
        end
        local hum = getHum()
        if hum then hum.WalkSpeed=16 end
        self._current=16; self._target=16
    end)
end

-- ════════════════════════════════════════════════════════════
-- [6] AUTO-COLLECT / AUTO-HATCH
-- Fires ProximityPrompts on hatch pads and income collectors
-- ════════════════════════════════════════════════════════════
local AutoFarm = {
    enabled  = false,
    _thread  = nil,
}

function AutoFarm:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            jwait(1.0, 0.3)
            -- Find and fire all "Collect", "Hatch", "Claim" prompts
            for _, obj in ipairs(WS:GetDescendants()) do
                if obj:IsA("ProximityPrompt") then
                    local at = obj.ActionText:lower()
                    if at:find("collect") or at:find("hatch") or
                       at:find("claim")   or at:find("income") or
                       at:find("cash")    or at:find("money")  or
                       at:find("earn")    or at:find("pick")   then
                        local part = obj.Parent
                        if part and part:IsA("BasePart") then
                            local hrp = getHRP()
                            if hrp then
                                safeTeleport(part.Position)
                                task.wait(0.2)
                            end
                        end
                        pcall(function() fireproximityprompt(obj) end)
                        pcall(function() obj:TriggerPrompt() end)
                        jwait(0.3, 0.1)
                    end
                end
            end
            -- Also try all Remotes for income collection
            for _, obj in ipairs(RS:GetDescendants()) do
                if obj:IsA("RemoteEvent") then
                    local n = obj.Name:lower()
                    if n:find("collect") or n:find("income") or
                       n:find("cash")    or n:find("earn")   then
                        pcall(function() obj:FireServer() end)
                    end
                end
            end
        end
    end)
end

function AutoFarm:Stop()
    self.enabled = false
end

-- ════════════════════════════════════════════════════════════
-- [7] ESP — SelectionBox + BillboardGui with real values
-- ════════════════════════════════════════════════════════════
local ESP = {
    enabled       = false,
    showEggs      = true,
    showGuardians = true,
    showTraps     = true,
    showPlayers   = true,
    _objects      = {},  -- list of instances to destroy on clear
}

local RARITY_COLORS = {
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

local function rCol(r) return RARITY_COLORS[r] or Color3.fromRGB(255,220,50) end

local function mkBB(adornPart, text, textColor, bgAlpha)
    bgAlpha = bgAlpha or 0.25
    local bb = Instance.new("BillboardGui")
    bb.AlwaysOnTop = true
    bb.Size        = UDim2.new(0,180,0,64)
    bb.StudsOffset = Vector3.new(0,5,0)
    bb.Adornee     = adornPart
    bb.Parent      = CoreGui

    local bg = Instance.new("Frame")
    bg.Size                  = UDim2.new(1,0,1,0)
    bg.BackgroundColor3      = Color3.fromRGB(8,8,15)
    bg.BackgroundTransparency= bgAlpha
    bg.BorderSizePixel       = 0
    bg.Parent                = bb
    Instance.new("UICorner",bg).CornerRadius = UDim.new(0,8)

    local lbl = Instance.new("TextLabel")
    lbl.Size              = UDim2.new(1,-8,1,-4)
    lbl.Position          = UDim2.new(0,4,0,2)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3        = textColor or Color3.new(1,1,1)
    lbl.TextScaled        = true
    lbl.Font              = Enum.Font.GothamBold
    lbl.Text              = text
    lbl.TextWrapped       = true
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3  = Color3.new(0,0,0)
    lbl.Parent            = bg

    table.insert(ESP._objects, bb)
    return bb
end

local function mkSB(part, color, thick)
    local sb = Instance.new("SelectionBox")
    sb.Adornee          = part
    sb.Color3           = color
    sb.LineThickness    = thick or 0.07
    sb.SurfaceColor3    = color
    sb.SurfaceTransparency = 0.75
    sb.Parent           = CoreGui
    table.insert(ESP._objects, sb)
    return sb
end

local function mkHL(part, color)
    -- Highlight (supported in most executors)
    local ok, hl = pcall(function()
        local h = Instance.new("Highlight")
        h.Adornee         = part
        h.FillColor       = color
        h.OutlineColor    = color
        h.FillTransparency   = 0.6
        h.OutlineTransparency= 0.0
        h.DepthMode       = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent          = CoreGui
        return h
    end)
    if ok then table.insert(ESP._objects, hl) end
end

function ESP:Clear()
    for _, obj in ipairs(self._objects) do
        pcall(function() obj:Destroy() end)
    end
    self._objects = {}
end

function ESP:Refresh()
    self:Clear()
    if not self.enabled then return end

    local hrp = getHRP()
    local myPos = hrp and hrp.Position

    -- ── EGGS ──────────────────────────────────────────────
    if self.showEggs then
        for _, egg in ipairs(Scanner.eggs) do
            local part = egg.part
            if not part or not part.Parent then continue end

            local income  = egg.income
            local rarity  = egg.rarity or "?"
            local col     = rCol(rarity)
            local cashStr = income and ("$"..fmtNum(income).."/s") or "?"
            local dist    = myPos and ("%ds"):format(
                math.floor((myPos-part.Position).Magnitude)) or "?"

            mkSB(part, col, 0.08)
            mkHL(part, col)
            mkBB(part,
                "🥚 "..egg.name.."\n"..
                "💰 "..cashStr.."  ✨ "..rarity.."\n"..
                "📍 "..dist,
                col, 0.20)
        end
    end

    -- ── GUARDIANS ─────────────────────────────────────────
    if self.showGuardians then
        for _, g in ipairs(Scanner.guardians) do
            if not g.hrp or not g.hrp.Parent then continue end
            local dist = myPos and ("%ds"):format(
                math.floor((myPos-g.hrp.Position).Magnitude)) or "?"
            local col  = Color3.fromRGB(255,50,50)
            local d    = myPos and (myPos-g.hrp.Position).Magnitude or 999
            local warn = d<25 and "🔴 DANGER!" or "⚠️ GUARD"
            mkSB(g.hrp, col, 0.09)
            mkHL(g.hrp, col)
            mkBB(g.hrp, warn.."\n"..g.model.Name.."\n📍 "..dist, col, 0.15)
        end
    end

    -- ── BEAR TRAPS ────────────────────────────────────────
    if self.showTraps then
        for _, trap in ipairs(Scanner.bearTraps) do
            if not trap.Parent then continue end
            local col = Color3.fromRGB(255,130,0)
            local dist= myPos and ("%ds"):format(
                math.floor((myPos-trap.Position).Magnitude)) or "?"
            local own = trap:GetAttribute("Owner") or
                        trap:GetAttribute("PlayerId")
            local lbl = (own==tostring(LP.UserId)) and "🪤 MY TRAP" or "🪤 TRAP"
            mkSB(trap, col, 0.07)
            mkBB(trap, lbl.."\n📍 "..dist, col, 0.20)
        end
    end

    -- ── PLAYERS ───────────────────────────────────────────
    if self.showPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr==LP or not plr.Character then continue end
            local phrp = plr.Character:FindFirstChild("HumanoidRootPart")
            if not phrp then continue end
            local col  = Color3.fromRGB(100,200,255)
            local dist = myPos and ("%ds"):format(
                math.floor((myPos-phrp.Position).Magnitude)) or "?"
            local inc  = plr:GetAttribute("TotalIncome")
                      or plr:GetAttribute("Income")
                      or plr:GetAttribute("MPS")
            local incStr = inc and fmtCash(inc) or "?"
            mkHL(phrp, col)
            mkBB(phrp,
                "👤 "..plr.DisplayName.."\n💰 "..incStr.."\n📍 "..dist,
                col, 0.20)
        end
    end
end

-- ESP auto-refresh every 2.5 seconds
task.spawn(function()
    while true do
        task.wait(2.5)
        if ESP.enabled then
            pcall(function() ESP:Refresh() end)
        end
    end
end)

-- ════════════════════════════════════════════════════════════
-- [8] BIOME TELEPORT
-- Scans for biome-related parts by name patterns
-- ════════════════════════════════════════════════════════════
local BIOME_KEYWORDS = {
    "Forest","Lake","Desert","Jungle","Snow","Volcano",
    "Abyss","Prehistoric","Cosmic","Cherry","Titan",
    "Angel","Demon","Enchanted"
}

local function teleportToBiome(keyword)
    local kl = keyword:lower()
    local best, bestSize = nil, 0
    for _, obj in ipairs(WS:GetDescendants()) do
        local nl = obj.Name:lower()
        if nl:find(kl) then
            if obj:IsA("BasePart") and obj.Size.Magnitude > bestSize then
                best     = obj
                bestSize = obj.Size.Magnitude
            elseif obj:IsA("Model") then
                local pp = obj.PrimaryPart or
                           obj:FindFirstChildOfClass("BasePart")
                if pp then best=pp; bestSize=999 end
            elseif obj:IsA("Folder") then
                local child = obj:FindFirstChildOfClass("BasePart")
                if child then best=child; bestSize=999 end
            end
        end
    end
    if best then
        safeTeleport(best.Position)
        return true
    end
    return false
end

-- ════════════════════════════════════════════════════════════
-- [9] NOCLIP
-- ════════════════════════════════════════════════════════════
local Noclip = {enabled=false, _conn=nil}

function Noclip:Enable()
    self.enabled = true
    self._conn = RunService.Stepped:Connect(function()
        local c = LP.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
    end)
end

function Noclip:Disable()
    self.enabled = false
    if self._conn then self._conn:Disconnect(); self._conn=nil end
    local c = LP.Character
    if c then
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=true end
        end
    end
end

-- ════════════════════════════════════════════════════════════
-- [10] UI
-- ════════════════════════════════════════════════════════════
-- Clean up old GUI
local old = CoreGui:FindFirstChild("CrowSAE")
if old then old:Destroy() end

local SG = Instance.new("ScreenGui")
SG.Name              = "CrowSAE"
SG.ResetOnSpawn      = false
SG.ZIndexBehavior    = Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset    = true
SG.DisplayOrder      = 9999
SG.Parent            = CoreGui

-- ── COLOURS ───────────────────────────────────────────────
local C = {
    BG    = Color3.fromRGB(12,12,20),
    BG2   = Color3.fromRGB(20,20,32),
    BG3   = Color3.fromRGB(28,28,42),
    ACC   = Color3.fromRGB(110,55,210),
    ACC2  = Color3.fromRGB(70,170,255),
    ON    = Color3.fromRGB(55,210,100),
    OFF   = Color3.fromRGB(70,70,95),
    RED   = Color3.fromRGB(220,55,55),
    WARN  = Color3.fromRGB(240,160,40),
    TXT   = Color3.fromRGB(230,230,240),
    SUB   = Color3.fromRGB(155,155,175),
    BOR   = Color3.fromRGB(55,35,95),
}

-- ── MAIN FRAME ────────────────────────────────────────────
local MF = Instance.new("Frame")
MF.Name               = "MF"
MF.Size               = UDim2.new(0,355,0,500)
MF.Position           = UDim2.new(0,10,0.15,0)
MF.BackgroundColor3   = C.BG
MF.BorderSizePixel    = 0
MF.Active             = true
MF.Draggable          = true
MF.ClipsDescendants   = true
MF.Parent             = SG
Instance.new("UICorner",MF).CornerRadius = UDim.new(0,12)
local _s=Instance.new("UIStroke",MF)
_s.Color=C.BOR; _s.Thickness=1.5

-- ── TITLE BAR ─────────────────────────────────────────────
local TB = Instance.new("Frame")
TB.Name            = "TB"
TB.Size            = UDim2.new(1,0,0,46)
TB.BackgroundColor3 = C.BG2
TB.BorderSizePixel = 0
TB.ZIndex          = 2
TB.Parent          = MF
Instance.new("UICorner",TB).CornerRadius = UDim.new(0,12)

local TG = Instance.new("UIGradient",TB)
TG.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,C.ACC),
    ColorSequenceKeypoint.new(1,C.ACC2),
})
TG.Rotation = 90

local TL = Instance.new("TextLabel",TB)
TL.Text="🥚 STEAL AN EGG  |  CROW v3.0"
TL.Font=Enum.Font.GothamBold
TL.TextSize=13
TL.TextColor3=C.TXT
TL.BackgroundTransparency=1
TL.Size=UDim2.new(1,-50,1,0)
TL.Position=UDim2.new(0,12,0,0)
TL.TextXAlignment=Enum.TextXAlignment.Left
TL.ZIndex=3

-- Close button: HIDES frame, does NOT destroy
local XB = Instance.new("TextButton",TB)
XB.Text="✕"
XB.Font=Enum.Font.GothamBold
XB.TextSize=15
XB.TextColor3=C.TXT
XB.BackgroundColor3=C.RED
XB.BorderSizePixel=0
XB.Size=UDim2.new(0,30,0,30)
XB.Position=UDim2.new(1,-38,0,8)
XB.ZIndex=4
Instance.new("UICorner",XB).CornerRadius=UDim.new(0,6)
XB.MouseButton1Click:Connect(function() MF.Visible=false end)

-- Mini toggle button (always visible, reopens menu)
local MinBtn = Instance.new("TextButton")
MinBtn.Text             = "🥚"
MinBtn.Font             = Enum.Font.GothamBold
MinBtn.TextSize         = 20
MinBtn.TextColor3       = Color3.new(1,1,1)
MinBtn.BackgroundColor3 = C.ACC
MinBtn.BorderSizePixel  = 0
MinBtn.Size             = UDim2.new(0,48,0,48)
MinBtn.Position         = UDim2.new(0,10,0.15,0)
MinBtn.ZIndex           = 100
MinBtn.Visible          = false
MinBtn.Active           = true
MinBtn.Draggable        = true
MinBtn.Parent           = SG
Instance.new("UICorner",MinBtn).CornerRadius=UDim.new(1,0)

XB.MouseButton1Click:Connect(function()
    MF.Visible   = false
    MinBtn.Visible = true
end)
MinBtn.MouseButton1Click:Connect(function()
    MF.Visible     = true
    MinBtn.Visible = false
end)

-- ── TAB SYSTEM ────────────────────────────────────────────
local TABS = {"⚡Main","🥚Steal","🏃Speed","👁ESP","💰Farm","🗺Biomes","⚙️More"}
local Pages  = {}
local TabBtns= {}

local TabBar = Instance.new("Frame",MF)
TabBar.Size            = UDim2.new(1,0,0,36)
TabBar.Position        = UDim2.new(0,0,0,46)
TabBar.BackgroundColor3= C.BG2
TabBar.BorderSizePixel = 0

local TBL = Instance.new("UIListLayout",TabBar)
TBL.FillDirection = Enum.FillDirection.Horizontal
TBL.SortOrder     = Enum.SortOrder.LayoutOrder
TBL.Padding       = UDim.new(0,2)

local CF = Instance.new("ScrollingFrame",MF)
CF.Size                  = UDim2.new(1,0,1,-82)
CF.Position              = UDim2.new(0,0,0,82)
CF.BackgroundTransparency= 1
CF.BorderSizePixel       = 0
CF.ScrollBarThickness    = 3
CF.CanvasSize            = UDim2.new(0,0,0,0)
CF.AutomaticCanvasSize   = Enum.AutomaticSize.Y
CF.ScrollBarImageColor3  = C.ACC

local CFL = Instance.new("UIListLayout",CF)
CFL.SortOrder  = Enum.SortOrder.LayoutOrder
CFL.Padding    = UDim.new(0,6)
local CFP = Instance.new("UIPadding",CF)
CFP.PaddingLeft=UDim.new(0,8)
CFP.PaddingRight=UDim.new(0,8)
CFP.PaddingTop=UDim.new(0,6)
CFP.PaddingBottom=UDim.new(0,6)

local function mkPage(name)
    local p = Instance.new("Frame",CF)
    p.Name=name; p.Visible=false
    p.Size=UDim2.new(1,0,0,0)
    p.AutomaticSize=Enum.AutomaticSize.Y
    p.BackgroundTransparency=1
    p.BorderSizePixel=0
    local l=Instance.new("UIListLayout",p)
    l.SortOrder=Enum.SortOrder.LayoutOrder
    l.Padding=UDim.new(0,5)
    Pages[name]=p; return p
end

local currentTab=nil
local function showTab(name)
    for n,pg in pairs(Pages) do pg.Visible=(n==name) end
    for _,b in ipairs(TabBtns) do
        b.TextColor3       = C.SUB
        b.BackgroundColor3 = C.BG2
    end
    local idx=0
    for i,t in ipairs(TABS) do if t==name then idx=i end end
    if TabBtns[idx] then
        TabBtns[idx].TextColor3       = Color3.new(1,1,1)
        TabBtns[idx].BackgroundColor3 = C.ACC
    end
    currentTab=name
end

for i,tname in ipairs(TABS) do
    mkPage(tname)
    local btn=Instance.new("TextButton",TabBar)
    btn.Text             = tname
    btn.Font             = Enum.Font.Gotham
    btn.TextSize         = 9
    btn.TextColor3       = C.SUB
    btn.BackgroundColor3 = C.BG2
    btn.BorderSizePixel  = 0
    btn.Size             = UDim2.new(0,44,1,0)
    btn.LayoutOrder      = i
    Instance.new("UICorner",btn).CornerRadius=UDim.new(0,4)
    TabBtns[i]=btn
    btn.MouseButton1Click:Connect(function() showTab(tname) end)
end

-- ── UI HELPERS ────────────────────────────────────────────
local function mkHdr(parent, text, col)
    local l=Instance.new("TextLabel",parent)
    l.Text=text; l.Font=Enum.Font.GothamBold
    l.TextSize=10; l.TextColor3=col or C.ACC
    l.BackgroundTransparency=1
    l.Size=UDim2.new(1,0,0,20)
    l.TextXAlignment=Enum.TextXAlignment.Left
    return l
end

local function mkInfo(parent, text)
    local f=Instance.new("Frame",parent)
    f.Size=UDim2.new(1,0,0,0)
    f.AutomaticSize=Enum.AutomaticSize.Y
    f.BackgroundColor3=C.BG2
    f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local p=Instance.new("UIPadding",f)
    p.PaddingLeft=UDim.new(0,8); p.PaddingTop=UDim.new(0,5)
    p.PaddingRight=UDim.new(0,8); p.PaddingBottom=UDim.new(0,5)
    local l=Instance.new("TextLabel",f)
    l.Text=text; l.Font=Enum.Font.Gotham
    l.TextSize=10; l.TextColor3=C.SUB
    l.BackgroundTransparency=1
    l.Size=UDim2.new(1,0,0,0)
    l.AutomaticSize=Enum.AutomaticSize.Y
    l.TextXAlignment=Enum.TextXAlignment.Left
    l.TextWrapped=true
    return f, l
end

local function mkToggle(parent, label, sub, default, cb)
    local row=Instance.new("Frame",parent)
    row.Size=UDim2.new(1,0,0,54)
    row.BackgroundColor3=C.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,8)

    local n=Instance.new("TextLabel",row)
    n.Text=label; n.Font=Enum.Font.GothamBold
    n.TextSize=12; n.TextColor3=C.TXT
    n.BackgroundTransparency=1
    n.Size=UDim2.new(1,-62,0,26)
    n.Position=UDim2.new(0,10,0,6)
    n.TextXAlignment=Enum.TextXAlignment.Left

    local s=Instance.new("TextLabel",row)
    s.Text=sub or ""; s.Font=Enum.Font.Gotham
    s.TextSize=9; s.TextColor3=C.SUB
    s.BackgroundTransparency=1
    s.Size=UDim2.new(1,-62,0,18)
    s.Position=UDim2.new(0,10,0,30)
    s.TextXAlignment=Enum.TextXAlignment.Left
    s.TextWrapped=true

    local pill=Instance.new("Frame",row)
    pill.Size=UDim2.new(0,46,0,24)
    pill.Position=UDim2.new(1,-56,0.5,-12)
    pill.BackgroundColor3=default and C.ON or C.OFF
    pill.BorderSizePixel=0
    Instance.new("UICorner",pill).CornerRadius=UDim.new(0,12)

    local knob=Instance.new("Frame",pill)
    knob.Size=UDim2.new(0,18,0,18)
    knob.Position=default and UDim2.new(0,25,0,3) or UDim2.new(0,3,0,3)
    knob.BackgroundColor3=Color3.new(1,1,1)
    knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(0,9)

    local state=default
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

    local function getState() return state end
    return row, getState
end

local function mkBtn(parent, text, col, cb)
    local b=Instance.new("TextButton",parent)
    b.Text=text; b.Font=Enum.Font.GothamBold
    b.TextSize=12; b.TextColor3=Color3.new(1,1,1)
    b.BackgroundColor3=col or C.ACC
    b.BorderSizePixel=0
    b.Size=UDim2.new(1,0,0,38)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseButton1Click:Connect(function()
        if cb then cb() end
        TweenService:Create(b,TweenInfo.new(0.08),{
            BackgroundTransparency=0.4
        }):Play()
        task.delay(0.15,function()
            TweenService:Create(b,TweenInfo.new(0.08),{
                BackgroundTransparency=0
            }):Play()
        end)
    end)
    return b
end

local function mkDrop(parent, label, opts, default, cb)
    local holder=Instance.new("Frame",parent)
    holder.Size=UDim2.new(1,0,0,72)
    holder.BackgroundColor3=C.BG2
    holder.BorderSizePixel=0
    Instance.new("UICorner",holder).CornerRadius=UDim.new(0,8)
    holder.ClipsDescendants=false

    local lbl=Instance.new("TextLabel",holder)
    lbl.Text=label; lbl.Font=Enum.Font.GothamBold
    lbl.TextSize=11; lbl.TextColor3=C.TXT
    lbl.BackgroundTransparency=1
    lbl.Size=UDim2.new(1,-20,0,22)
    lbl.Position=UDim2.new(0,10,0,5)
    lbl.TextXAlignment=Enum.TextXAlignment.Left

    local sel=default or opts[1]
    local selBtn=Instance.new("TextButton",holder)
    selBtn.Text=sel.."  ▾"
    selBtn.Font=Enum.Font.Gotham; selBtn.TextSize=11
    selBtn.TextColor3=C.ACC2
    selBtn.BackgroundColor3=C.BG3
    selBtn.BorderSizePixel=0
    selBtn.Size=UDim2.new(1,-20,0,28)
    selBtn.Position=UDim2.new(0,10,0,30)
    selBtn.TextXAlignment=Enum.TextXAlignment.Left
    Instance.new("UICorner",selBtn).CornerRadius=UDim.new(0,6)

    local dList=Instance.new("Frame",holder)
    dList.Size=UDim2.new(1,-20,0,#opts*26+4)
    dList.Position=UDim2.new(0,10,1,2)
    dList.BackgroundColor3=C.BG3
    dList.BorderSizePixel=0
    dList.ZIndex=50; dList.Visible=false
    Instance.new("UICorner",dList).CornerRadius=UDim.new(0,6)
    Instance.new("UIStroke",dList).Color=C.BOR
    local dl=Instance.new("UIListLayout",dList)
    dl.SortOrder=Enum.SortOrder.LayoutOrder

    for _,opt in ipairs(opts) do
        local ob=Instance.new("TextButton",dList)
        ob.Text=opt; ob.Font=Enum.Font.Gotham; ob.TextSize=10
        ob.TextColor3=C.TXT; ob.BackgroundTransparency=1
        ob.Size=UDim2.new(1,0,0,24)
        ob.TextXAlignment=Enum.TextXAlignment.Left
        ob.ZIndex=51
        local op=Instance.new("UIPadding",ob)
        op.PaddingLeft=UDim.new(0,8)
        ob.MouseButton1Click:Connect(function()
            sel=opt; selBtn.Text=opt.."  ▾"
            dList.Visible=false
            holder.Size=UDim2.new(1,0,0,72)
            if cb then cb(opt) end
        end)
        ob.MouseEnter:Connect(function() ob.TextColor3=C.ACC2 end)
        ob.MouseLeave:Connect(function() ob.TextColor3=C.TXT end)
    end

    selBtn.MouseButton1Click:Connect(function()
        local v=not dList.Visible
        dList.Visible=v
        holder.Size=UDim2.new(1,0,0,v and (72+#opts*26+6) or 72)
    end)
    return holder
end

-- ════════════════════════════════════════════════════════════
-- POPULATE TABS
-- ════════════════════════════════════════════════════════════

-- ── TAB: ⚡Main ───────────────────────────────────────────
local pg = Pages["⚡Main"]
mkHdr(pg,"  ◆ STATUS")
local _, statusLbl = mkInfo(pg,"Scanning workspace...")
task.spawn(function()
    task.wait(5)
    local eggCount = #Scanner.eggs
    local tmFound  = Scanner.treadmill ~= nil
    local penFound = Scanner.pen ~= nil
    statusLbl.Text = ("✅ Eggs found: %d\n%s Treadmill: %s\n%s Pen: %s"):format(
        eggCount,
        tmFound  and "✅" or "⚠️", tmFound  and Scanner.treadmill.Name or "Not found",
        penFound and "✅" or "⚠️", penFound and Scanner.pen.Name      or "Not found"
    )
    statusLbl.TextColor3 = eggCount>0 and C.ON or C.WARN
end)

mkHdr(pg,"  ◆ QUICK TOGGLES")
mkToggle(pg,"Auto-Steal","Finds eggs → steals → returns to pen",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkToggle(pg,"Auto-Treadmill","Stand on treadmill to gain speed",false,function(on)
    if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
end)
mkToggle(pg,"Auto-Farm","Collect income & hatch eggs",false,function(on)
    if on then AutoFarm:Start() else AutoFarm:Stop() end
end)
mkToggle(pg,"Speed Hack","Smooth WalkSpeed boost",false,function(on)
    if on then SpeedModule:Enable() else SpeedModule:Disable() end
end)
mkToggle(pg,"ESP","Show eggs, guardians, players",false,function(on)
    ESP.enabled=on; ESP:Refresh()
end)

mkHdr(pg,"  ◆ CONTROLS")
mkInfo(pg,"Close (✕) → hides menu, 🥚 button reopens it\nAll features survive menu close")

mkBtn(pg,"🔄 Rescan Workspace",C.ACC2,function()
    Scanner:Scan()
    task.wait(0.5)
    local eggCount=#Scanner.eggs
    statusLbl.Text=("✅ Eggs: %d  |  TM: %s  |  Pen: %s"):format(
        eggCount,
        Scanner.treadmill and "✅"..Scanner.treadmill.Name or "❌",
        Scanner.pen        and "✅"..Scanner.pen.Name       or "❌"
    )
    statusLbl.TextColor3=eggCount>0 and C.ON or C.WARN
end)

-- ── TAB: 🥚Steal ─────────────────────────────────────────
pg = Pages["🥚Steal"]
mkHdr(pg,"  ◆ AUTO-STEAL SETTINGS")
mkToggle(pg,"Auto-Steal","ProximityPrompt trigger — real steal method",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkToggle(pg,"Auto-Return to Pen","Teleport home after each steal",true,function(on)
    AutoSteal.autoReturn=on
end)
mkToggle(pg,"Noclip","Pass through walls to reach nests",false,function(on)
    if on then Noclip:Enable() else Noclip:Disable() end
end)

local rarityOpts={"Any","Rare+","Epic+","Legendary+","Cosmic+"}
mkDrop(pg,"Rarity Filter",rarityOpts,"Any",function(v) AutoSteal.rareFilter=v end)

mkHdr(pg,"  ◆ MANUAL ACTIONS")
mkBtn(pg,"Steal Once (Best Available)",C.ACC,function()
    if #Scanner.eggs==0 then Scanner:Scan() end
    if #Scanner.eggs>0 then
        local egg=Scanner.eggs[1]
        safeTeleport(egg.part.Position)
        task.wait(0.25)
        pcall(function() fireproximityprompt(egg.prompt) end)
        pcall(function() egg.prompt:TriggerPrompt() end)
    end
end)
mkBtn(pg,"Return to Pen",C.ACC2,function()
    if Scanner.pen then safeTeleport(Scanner.pen.Position) end
end)
mkBtn(pg,"Rescan Eggs",C.BG3,function() Scanner:Scan() end)

-- ── TAB: 🏃Speed ─────────────────────────────────────────
pg = Pages["🏃Speed"]
mkHdr(pg,"  ◆ SPEED HACK")
mkToggle(pg,"Speed Hack","Smooth lerp WalkSpeed — no lag/glitch",false,function(on)
    if on then SpeedModule:Enable() else SpeedModule:Disable() end
end)
local spPresetColors={C.ON,C.ACC2,C.ACC,C.WARN,C.RED}
mkHdr(pg,"  ◆ SELECT PRESET")
for i,pr in ipairs(SpeedModule.PRESETS) do
    mkBtn(pg,pr.label.."  ["..pr.speed.." WS]",spPresetColors[i],function()
        SpeedModule:SetPreset(i)
    end)
end

mkHdr(pg,"  ◆ AUTO-TREADMILL")
mkToggle(pg,"Auto-Treadmill","Simulates steps on your treadmill",false,function(on)
    if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
end)
mkBtn(pg,"TP to Treadmill",C.BG3,function()
    if Scanner.treadmill then
        safeTeleport(Scanner.treadmill.Position)
    else
        Scanner:Scan()
    end
end)

-- ── TAB: 👁ESP ────────────────────────────────────────────
pg = Pages["👁ESP"]
mkHdr(pg,"  ◆ ESP OPTIONS")
mkToggle(pg,"Enable ESP","Master toggle",false,function(on)
    ESP.enabled=on; ESP:Refresh()
end)
mkToggle(pg,"Show Eggs","Egg positions + real $/s value",true,function(on)
    ESP.showEggs=on; if ESP.enabled then ESP:Refresh() end
end)
mkToggle(pg,"Show Guardians","NPC enemies — warns when close",true,function(on)
    ESP.showGuardians=on; if ESP.enabled then ESP:Refresh() end
end)
mkToggle(pg,"Show Bear Traps","Enemy traps highlighted",true,function(on)
    ESP.showTraps=on; if ESP.enabled then ESP:Refresh() end
end)
mkToggle(pg,"Show Players","Other players + income",true,function(on)
    ESP.showPlayers=on; if ESP.enabled then ESP:Refresh() end
end)
mkBtn(pg,"🔄 Refresh ESP Now",C.ACC2,function()
    Scanner:Scan()
    ESP:Refresh()
end)
mkInfo(pg,"ESP refreshes every 2.5s automatically.\nRarities: Common=grey Uncommon=green Rare=blue Epic=purple Legendary=gold Cosmic=cyan Secret=pink")

-- ── TAB: 💰Farm ───────────────────────────────────────────
pg = Pages["💰Farm"]
mkHdr(pg,"  ◆ AUTO-FARM")
mkToggle(pg,"Auto-Collect / Auto-Hatch","Fires all Collect & Hatch prompts",false,function(on)
    if on then AutoFarm:Start() else AutoFarm:Stop() end
end)
mkToggle(pg,"Auto-Steal","Full steal loop (also on Steal tab)",false,function(on)
    if on then AutoSteal:Start() else AutoSteal:Stop() end
end)
mkToggle(pg,"Auto-Treadmill","AFK speed farming",false,function(on)
    if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
end)

mkHdr(pg,"  ◆ BIOME INCOME REFERENCE")
local ref="BIOME          BEST PET              $/s\n"
        .."Forest         Brr Brr Patapim       $1.8K\n"
        .."Lake           Leviathan             $220K\n"
        .."Desert         Royal Sphinx           $280K\n"
        .."Jungle         King Snake            $3.5M\n"
        .."Snow           Ice Dragon            $65M\n"
        .."Volcano        Lava Dragon           $100M\n"
        .."Abyss Ocean    Abyss Leviathan       $500M\n"
        .."Prehistoric    Titan Pterodactyl     $2B\n"
        .."Cosmic         Cosmic God            $10B"
local _,rl=mkInfo(pg,ref)
rl.Font=Enum.Font.Code; rl.TextSize=9

-- ── TAB: 🗺Biomes ─────────────────────────────────────────
pg = Pages["🗺Biomes"]
mkHdr(pg,"  ◆ BIOME TELEPORT")
mkInfo(pg,"Scans Workspace for biome parts by name. If teleport fails, rescan first.")

local biomeData={
    {name="Forest",       spd="0"},
    {name="Lake",         spd="900"},
    {name="Desert",       spd="10K"},
    {name="Jungle",       spd="40K"},
    {name="Snow",         spd="170K"},
    {name="Volcano",      spd="700K"},
    {name="Abyss",        spd="3M"},
    {name="Prehistoric",  spd="10M"},
    {name="Cosmic",       spd="50M"},
    {name="Cherry",       spd="2.5B"},
    {name="Titan",        spd="10B"},
    {name="Angels",       spd="25B"},
    {name="Enchanted",    spd="50B"},
}

for _, bd in ipairs(biomeData) do
    local row=Instance.new("Frame",pg)
    row.Size=UDim2.new(1,0,0,44)
    row.BackgroundColor3=C.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)

    local nl=Instance.new("TextLabel",row)
    nl.Text=bd.name; nl.Font=Enum.Font.GothamBold
    nl.TextSize=12; nl.TextColor3=C.TXT
    nl.BackgroundTransparency=1
    nl.Size=UDim2.new(1,-100,0,22)
    nl.Position=UDim2.new(0,10,0,4)
    nl.TextXAlignment=Enum.TextXAlignment.Left

    local sl=Instance.new("TextLabel",row)
    sl.Text="≥"..bd.spd.." spd"
    sl.Font=Enum.Font.Gotham; sl.TextSize=9
    sl.TextColor3=C.SUB; sl.BackgroundTransparency=1
    sl.Size=UDim2.new(1,-100,0,16)
    sl.Position=UDim2.new(0,10,0,24)
    sl.TextXAlignment=Enum.TextXAlignment.Left

    local tb2=Instance.new("TextButton",row)
    tb2.Text="TP →"; tb2.Font=Enum.Font.GothamBold
    tb2.TextSize=11; tb2.TextColor3=Color3.new(1,1,1)
    tb2.BackgroundColor3=C.ACC
    tb2.BorderSizePixel=0
    tb2.Size=UDim2.new(0,70,0,28)
    tb2.Position=UDim2.new(1,-80,0.5,-14)
    Instance.new("UICorner",tb2).CornerRadius=UDim.new(0,6)

    local bname=bd.name
    tb2.MouseButton1Click:Connect(function()
        if not teleportToBiome(bname) then
            Scanner:Scan()
            teleportToBiome(bname)
        end
        AutoSteal.targetBiome=bname
    end)
end

-- ── TAB: ⚙️More ────────────────────────────────────────────
pg = Pages["⚙️More"]
mkHdr(pg,"  ◆ TOOLS")
mkToggle(pg,"Noclip","Walk through all walls",false,function(on)
    if on then Noclip:Enable() else Noclip:Disable() end
end)
mkBtn(pg,"🔄 Full Rescan",C.ACC2,function() Scanner:Scan() end)
mkBtn(pg,"📦 Print Scan Results (Console)",C.BG3,function()
    print("[Crow] Eggs found:",#Scanner.eggs)
    print("[Crow] Treadmill:",Scanner.treadmill and Scanner.treadmill:GetFullName() or "nil")
    print("[Crow] Pen:",Scanner.pen and Scanner.pen:GetFullName() or "nil")
    print("[Crow] Guardians:",#Scanner.guardians)
    for i,e in ipairs(Scanner.eggs) do
        print(("  Egg %d: %s | %s | %s"):format(
            i, e.name, e.rarity, fmtCash(e.income)
        ))
    end
end)

mkHdr(pg,"  ◆ ANTI-DETECTION")
mkInfo(pg,"✅ ProximityPrompt (real steal method)\n✅ Jittered loop intervals\n✅ Random teleport offset\n✅ Smooth WalkSpeed lerp\n✅ Rate-limited remote calls\n✅ No hardcoded Remote names")

mkHdr(pg,"  ◆ MENU")
mkBtn(pg,"Hide Menu (🥚 to reopen)",C.BG3,function()
    MF.Visible=false; MinBtn.Visible=true
end)
mkBtn(pg,"❌ Destroy Script",C.RED,function()
    AutoSteal:Stop(); AutoTreadmill:Stop(); AutoFarm:Stop()
    SpeedModule:Disable(); Noclip:Disable()
    ESP:Clear(); SG:Destroy()
end)

-- ════════════════════════════════════════════════════════════
-- [11] CHARACTER RESPAWN HANDLER
-- ════════════════════════════════════════════════════════════
LP.CharacterAdded:Connect(function()
    task.wait(1.5)
    Scanner:Scan()
    if SpeedModule.enabled then SpeedModule:Disable(); SpeedModule:Enable() end
    if Noclip.enabled      then Noclip:Disable(); Noclip:Enable() end
    if AutoTreadmill.enabled then
        AutoTreadmill:Stop(); task.wait(0.5); AutoTreadmill:Start()
    end
end)

-- ════════════════════════════════════════════════════════════
-- INIT
-- ════════════════════════════════════════════════════════════
showTab("⚡Main")
print("[Crow v3.0] Loaded. ProximityPrompt engine active.")
print("[Crow v3.0] Scanner will complete in ~4 seconds.")
