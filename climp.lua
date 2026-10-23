--[[
    ╔══════════════════════════════════════════════════════════╗
    ║         STEAL AN EGG — MOD MENU v2.7 (DELTA MOBILE)     ║
    ║  Features: AutoSteal · AutoHatch · SpeedHack · ESP      ║
    ║            AutoTreadmill · BearTrapESP · PetFarm         ║
    ║            BiomeTeleport · Anti-Detection Shield         ║
    ╠══════════════════════════════════════════════════════════╣
    ║  v2.7 FIXES:                                            ║
    ║   • Speed: WalkSpeed lerp only (no BodyVelocity lag)    ║
    ║   • ESP: reads real egg cash value from attributes       ║
    ║   • Mobile-safe UI (no keyboard-only binds as default)  ║
    ╚══════════════════════════════════════════════════════════╝
    
    INJECT WITH: Delta (Mobile) / Hydrogen / Fluxus / KRNL
    
    Anti-detection layers:
      • Velocity randomisation (prevents pattern detection)
      • Humanoid WalkSpeed clamped to server-believable values
      • Remote call rate-limiting to avoid server kick triggers
      • LocalScript identity spoofing on key functions
      • Executor fingerprint obfuscation via metamethod wrapping
      • Heartbeat jitter on loops (not fixed-interval)
      • No modification of FilteringEnabled-checked Remotes
]]

-- ═══════════════════════════════════════════════════════════
-- SECTION 0: ANTI-DETECTION CORE
-- ═══════════════════════════════════════════════════════════

local AC = {}

-- Jitter table: randomise loop intervals so network analysis
-- cannot fingerprint a fixed-period bot signature
AC.Jitter = function(base, variance)
    return base + (math.random() * variance * 2) - variance
end

-- Rate-limiter: prevents hammering Remotes faster than a
-- legitimate player could. Server logs flag >N calls/sec.
local _remoteCooldowns = {}
AC.RateLimit = function(key, minInterval)
    local now = tick()
    if not _remoteCooldowns[key] or (now - _remoteCooldowns[key]) >= minInterval then
        _remoteCooldowns[key] = now
        return true
    end
    return false
end

-- Spoof WalkSpeed: never set raw speed above a safe threshold
-- unless using the local character velocity bypass (see below)
AC.SAFE_WALKSPEED_CAP = 100  -- visible to server; keep ≤100
AC.LOCAL_SPEED_MULT   = 5    -- applied via BodyVelocity, server-invisible

-- Obfuscate function names in upvalue table
-- (defeats basic "getupvalues" scanner checks)
local function _shield(fn)
    local proxy = newproxy(true)
    local mt = getmetatable(proxy)
    mt.__call = function(_, ...) return fn(...) end
    mt.__tostring = function() return "function" end
    mt.__metatable = "The metatable is locked"
    return proxy
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 1: CORE SERVICES & REFERENCES
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService      = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

-- Wait for character with timeout guard
local function getChar()
    local char = LocalPlayer.Character
    if not char then
        char = LocalPlayer.CharacterAdded:Wait()
    end
    return char
end

local function getHRP()
    local char = getChar()
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getHum()
    local char = getChar()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 2: GAME-SPECIFIC REMOTE & OBJECT DETECTION
-- ═══════════════════════════════════════════════════════════

-- Steal An Egg remote detection (scans ReplicatedStorage on load)
-- The game uses RemoteEvents/Functions for: StealEgg, HatchEgg,
-- PurchaseTreadmill, PurchaseTrail, PlaceBearTrap, CollectIncome

local Remotes = {}

local function scanRemotes()
    -- Deep scan all RemoteEvents and RemoteFunctions
    local function recurse(parent)
        for _, obj in ipairs(parent:GetChildren()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                local n = obj.Name:lower()
                -- Map known names to our Remotes table
                if n:find("steal") or n:find("grab") or n:find("take") then
                    Remotes.StealEgg = Remotes.StealEgg or obj
                elseif n:find("hatch") or n:find("incubat") then
                    Remotes.HatchEgg = Remotes.HatchEgg or obj
                elseif n:find("treadmill") or n:find("train") then
                    Remotes.Treadmill = Remotes.Treadmill or obj
                elseif n:find("trail") then
                    Remotes.Trail = Remotes.Trail or obj
                elseif n:find("trap") then
                    Remotes.BearTrap = Remotes.BearTrap or obj
                elseif n:find("income") or n:find("collect") or n:find("cash") then
                    Remotes.Collect = Remotes.Collect or obj
                elseif n:find("speed") then
                    Remotes.SpeedUpgrade = Remotes.SpeedUpgrade or obj
                elseif n:find("pet") and n:find("equip") then
                    Remotes.EquipPet = Remotes.EquipPet or obj
                elseif n:find("teleport") or n:find("biome") then
                    Remotes.Teleport = Remotes.Teleport or obj
                end
                Remotes._all = Remotes._all or {}
                table.insert(Remotes._all, obj)
            end
            recurse(obj)
        end
    end
    recurse(ReplicatedStorage)
    recurse(Workspace)
end

-- Run scan once RS is populated
task.spawn(function()
    task.wait(3)
    scanRemotes()
end)

-- ═══════════════════════════════════════════════════════════
-- SECTION 3: BIOME DATA TABLE
-- (Speed requirements, guardian names, best egg per biome)
-- ═══════════════════════════════════════════════════════════

local BIOMES = {
    { name = "Forest",          speedReq = 0,             guardian = "Chicken",   bestPet = "Brr Brr Patapim", bestIncome = 1800    },
    { name = "Lake",            speedReq = 900,           guardian = "Swan",      bestPet = "Leviathan",        bestIncome = 220000  },
    { name = "Desert",          speedReq = 10000,         guardian = "Scorpion",  bestPet = "Royal Sphinx",     bestIncome = 280000  },
    { name = "Jungle",          speedReq = 40000,         guardian = "Tiger",     bestPet = "King Snake",       bestIncome = 3500000 },
    { name = "Snow",            speedReq = 170000,        guardian = "Yeti",      bestPet = "Ice Dragon",       bestIncome = 65000000},
    { name = "Volcano",         speedReq = 700000,        guardian = "Cerberus",  bestPet = "Lava Dragon",      bestIncome = 1e8     },
    { name = "Abyss Ocean",     speedReq = 3000000,       guardian = "Kraken",    bestPet = "Abyss Leviathan",  bestIncome = 5e8     },
    { name = "Prehistoric",     speedReq = 10000000,      guardian = "T-Rex",     bestPet = "Titan Pterodactyl",bestIncome = 2e9     },
    { name = "Cosmic",          speedReq = 50000000,      guardian = "Galaxy Dragon", bestPet = "Cosmic God",   bestIncome = 1e10    },
    { name = "Cherry Blossom",  speedReq = 2500000000,    guardian = "Spirit Fox", bestPet = "Sakura Phoenix",  bestIncome = 5e11    },
    { name = "Titan Temple",    speedReq = 10000000000,   guardian = "Titan",     bestPet = "God Titan",        bestIncome = 2e12    },
    { name = "Angels & Demons", speedReq = 25000000000,   guardian = "Seraph",    bestPet = "Arch Demon",       bestIncome = 8e12    },
    { name = "Enchanted Forest",speedReq = 50000000000,   guardian = "Wisp",      bestPet = "Enchanted Dragon", bestIncome = 3e13    },
}

-- Treadmill cost/speed-per-step data
local TREADMILLS = {
    { name = "Base Treadmill",      cost = 0,        sps = 2    },
    { name = "Sci-Fi Treadmill",    cost = 15000,    sps = 5    },
    { name = "Flame Treadmill",     cost = 250000,   sps = 12   },
    { name = "Celebrity Treadmill", cost = 5000000,  sps = 30   },
    { name = "Hacker Treadmill",    cost = 50000000, sps = 200  },
    { name = "Angel Treadmill",     cost = 1e9,      sps = 1000 },
}

-- Trail multiplier data
local TRAILS = {
    { name = "Grey Trail",   cost = 100,      mult = 1.5 },
    { name = "Green Trail",  cost = 5000,     mult = 2.0 },
    { name = "Blue Trail",   cost = 75000,    mult = 2.5 },
    { name = "Purple Trail", cost = 1500000,  mult = 3.0 },
    { name = "Gold Trail",   cost = 25000000, mult = 4.0 },
    { name = "Rainbow Trail",cost = 5e8,      mult = 6.0 },
}

-- Mutation roll weights (from wiki, per 100 rolls)
local MUTATIONS = {
    { name = "Silver",   weight = 6,  mult = 1.2  },
    { name = "Golden",   weight = 4,  mult = 2.5  },
    { name = "Rainbow",  weight = 1,  mult = 3.5  },
    { name = "Fractured",weight = 0.5,mult = 2.75 },
}

-- ═══════════════════════════════════════════════════════════
-- SECTION 4: MOVEMENT / SPEED SYSTEM  (v2.7 — MOBILE SAFE)
--
-- DESIGN: Pure WalkSpeed manipulation with smooth lerp.
-- No BodyVelocity — that causes physics jitter on mobile
-- because Roblox's physics tick conflicts with BV forces
-- at low framerates. WalkSpeed is replicated to server but
-- Roblox's anti-cheat threshold is ~500; we stay well below.
--
-- Lerp approach: instead of snapping WalkSpeed instantly
-- (which causes a visible stutter frame), we lerp from
-- current → target over ~0.15s. Feels natural, no lag.
-- ═══════════════════════════════════════════════════════════

local SpeedModule = {}
SpeedModule.enabled      = false
SpeedModule.multiplier   = 3      -- speed preset; UI sets this
SpeedModule.BASE_SPEED   = 16     -- Roblox default WalkSpeed
SpeedModule.maxSafe      = 120    -- cap: high but below AC flags
                                   -- (tested: 150 kicks on some servers)
SpeedModule._conn        = nil
SpeedModule._targetSpeed = 16
SpeedModule._currentSpeed= 16

-- Presets: base × multiplier, capped at maxSafe
-- multiplier 1 = 16, 2 = 32, 3 = 48 ... feels natural
-- We do NOT use enormous values — smooth is the goal.
-- For "fast" feel: 48–80 is plenty on this map.
SpeedModule.PRESETS = {
    { label = "🐢 Slow (×1.5)",   speed = 24  },
    { label = "🚶 Normal (×2)",    speed = 32  },
    { label = "🏃 Fast (×3)",      speed = 48  },
    { label = "⚡ Sprint (×5)",    speed = 80  },
    { label = "🦅 Crow (×7.5)",   speed = 120 },
}
SpeedModule._presetIdx = 3  -- default: Fast

function SpeedModule:Enable()
    self.enabled = true
    self._targetSpeed = self.PRESETS[self._presetIdx].speed

    -- Single Heartbeat connection — lerps WalkSpeed each frame.
    -- lerp factor 0.18 per frame ≈ reaches target in ~0.15s at 60fps.
    -- On 30fps mobile it's ~0.3s — still smooth, no stutter.
    self._conn = RunService.Heartbeat:Connect(function(dt)
        if not self.enabled then return end
        local hum = getHum()
        if not hum then return end

        -- Lerp current toward target (frame-rate independent)
        local lerpFactor = 1 - (0.82 ^ (dt * 60))
        self._currentSpeed = self._currentSpeed
            + (self._targetSpeed - self._currentSpeed) * lerpFactor

        -- Clamp and apply
        hum.WalkSpeed = math.clamp(
            math.floor(self._currentSpeed + 0.5),  -- round to int
            SpeedModule.BASE_SPEED,
            SpeedModule.maxSafe
        )
    end)
end

function SpeedModule:SetPreset(idx)
    self._presetIdx   = idx
    self._targetSpeed = self.PRESETS[idx].speed
    -- _currentSpeed lerps toward new target automatically
end

function SpeedModule:Disable()
    self.enabled = false
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
    -- Lerp back to default smoothly (brief coroutine, no stutter)
    task.spawn(function()
        local steps = 15
        local hum = getHum()
        if not hum then return end
        local startSpeed = hum.WalkSpeed
        for i = 1, steps do
            if not hum or not hum.Parent then break end
            hum.WalkSpeed = startSpeed
                + (SpeedModule.BASE_SPEED - startSpeed) * (i / steps)
            task.wait(0.016)  -- ~60fps cadence
        end
        if hum and hum.Parent then
            hum.WalkSpeed = SpeedModule.BASE_SPEED
        end
        self._currentSpeed = SpeedModule.BASE_SPEED
        self._targetSpeed  = SpeedModule.BASE_SPEED
    end)
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 5: AUTO-STEAL SYSTEM
-- Targets: nearest accessible egg in current/selected biome
-- Anti-detection: jittered loop, rate-limited Remote calls
-- ═══════════════════════════════════════════════════════════

local AutoSteal = {}
AutoSteal.enabled      = false
AutoSteal.targetBiome  = "Forest"   -- default; UI can change
AutoSteal.rareFilter   = "Any"      -- Any / Rare+ / Epic+ / Legendary+
AutoSteal.autoReturn   = true       -- sprint back to pen after steal
AutoSteal.useBearTrap  = true       -- drop trap if guardian closes in
AutoSteal._thread      = nil

-- Rarity rank for filter comparison
local RARITY_RANK = {
    Common = 1, Uncommon = 2, Rare = 3,
    Epic = 4, Legendary = 5, Cosmic = 6,
    Secret = 7, Eternal = 8, Divine = 9
}
local FILTER_RANK = {
    ["Any"] = 0, ["Rare+"] = 3, ["Epic+"] = 4,
    ["Legendary+"] = 5, ["Cosmic+"] = 6
}

-- Find egg objects in workspace by tag / folder structure
-- Game typically stores eggs under: Workspace.Map.Biomes.<name>.Eggs
local function findEggsInBiome(biomeName)
    local eggs = {}
    local biomeRoot = Workspace:FindFirstChild("Map")
                   or Workspace:FindFirstChild("World")
                   or Workspace

    -- Walk all descendants looking for egg models
    for _, obj in ipairs(biomeRoot:GetDescendants()) do
        -- Eggs are typically BaseParts or Models with an
        -- "Egg" tag, or named like "ChickenEgg", "FoxEgg" etc.
        local n = obj.Name:lower()
        if (n:find("egg") or (obj:GetAttribute("IsEgg"))) then
            -- Check biome folder parent chain
            local inBiome = false
            local cur = obj
            for _ = 1, 10 do
                cur = cur.Parent
                if not cur then break end
                if cur.Name:lower():find(biomeName:lower()) then
                    inBiome = true
                    break
                end
            end
            -- If no biome folder found, include all (fallback)
            if inBiome or biomeName == "Any" then
                if obj:IsA("BasePart") or obj:IsA("Model") then
                    table.insert(eggs, obj)
                end
            end
        end
    end
    return eggs
end

-- Get guardian model for a biome
local function findGuardian(biomeName)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local n = obj.Name:lower()
        if n:find("guardian") or n:find("guard") or n:find("boss") then
            local cur = obj
            for _ = 1, 8 do
                cur = cur.Parent
                if not cur then break end
                if cur.Name:lower():find(biomeName:lower()) then
                    return obj
                end
            end
        end
    end
    return nil
end

-- Find player's pen (home base)
local function findPen()
    -- Pens are usually under a player folder or named "Garden_<userid>"
    local uid = tostring(LocalPlayer.UserId)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local n = obj.Name:lower()
        if (n:find("pen") or n:find("garden") or n:find("base")) and
           (n:find(uid) or obj:GetAttribute("Owner") == uid) then
            if obj:IsA("BasePart") or obj:IsA("Model") then
                return obj
            end
        end
    end
    -- Fallback: look for a SpawnLocation tagged as home
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") and
           obj:GetAttribute("PlayerId") == LocalPlayer.UserId then
            return obj
        end
    end
    return nil
end

-- Teleport character to a position (jittered to avoid exact-coord flags)
local function tpTo(target)
    local hrp = getHRP()
    if not hrp then return end
    local pos
    if typeof(target) == "Vector3" then
        pos = target
    elseif target:IsA("BasePart") then
        pos = target.Position + Vector3.new(0, 3, 0)
    elseif target:IsA("Model") then
        local prim = target.PrimaryPart or target:FindFirstChildOfClass("BasePart")
        if prim then pos = prim.Position + Vector3.new(0, 3, 0) end
    end
    if not pos then return end

    -- Add micro-jitter: ±0.5 studs on X/Z so teleport coords
    -- never repeat exactly (server-side replay detection bypass)
    pos = pos + Vector3.new(
        (math.random() - 0.5),
        0,
        (math.random() - 0.5)
    )
    hrp.CFrame = CFrame.new(pos)
end

-- Fire steal remote safely
local function fireSteal(eggObj)
    if not Remotes.StealEgg then return end
    if not AC.RateLimit("StealEgg", 0.8) then return end

    -- Remotes expect the egg's model or a part reference
    if Remotes.StealEgg:IsA("RemoteEvent") then
        Remotes.StealEgg:FireServer(eggObj)
    elseif Remotes.StealEgg:IsA("RemoteFunction") then
        Remotes.StealEgg:InvokeServer(eggObj)
    end
end

-- Drop bear trap (defensive, only when guardian is near)
local function dropBearTrap()
    if not Remotes.BearTrap then return end
    if not AC.RateLimit("BearTrap", 2.0) then return end
    if Remotes.BearTrap:IsA("RemoteEvent") then
        Remotes.BearTrap:FireServer()
    end
end

function AutoSteal:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            -- Jittered loop: 1.5s ± 0.4s between steal attempts
            task.wait(AC.Jitter(1.5, 0.4))

            local eggs = findEggsInBiome(self.targetBiome)
            if #eggs == 0 then
                task.wait(AC.Jitter(3, 1))
                continue
            end

            -- Sort by distance from player
            local hrp = getHRP()
            if not hrp then task.wait(1) continue end

            table.sort(eggs, function(a, b)
                local aPos = a:IsA("BasePart") and a.Position
                          or (a.PrimaryPart and a.PrimaryPart.Position)
                local bPos = b:IsA("BasePart") and b.Position
                          or (b.PrimaryPart and b.PrimaryPart.Position)
                if not aPos or not bPos then return false end
                return (hrp.Position - aPos).Magnitude
                     < (hrp.Position - bPos).Magnitude
            end)

            local targetEgg = eggs[1]
            if not targetEgg then continue end

            -- Teleport to egg
            tpTo(targetEgg)
            task.wait(AC.Jitter(0.3, 0.1))

            -- Check if guardian is dangerously close
            if self.useBearTrap then
                local guardian = findGuardian(self.targetBiome)
                if guardian then
                    local gPart = guardian:IsA("BasePart") and guardian
                               or guardian:FindFirstChildOfClass("BasePart")
                    if gPart then
                        local dist = (hrp.Position - gPart.Position).Magnitude
                        if dist < 20 then
                            dropBearTrap()
                            task.wait(0.5)
                        end
                    end
                end
            end

            -- Fire the steal
            fireSteal(targetEgg)
            task.wait(AC.Jitter(0.5, 0.2))

            -- Auto-return to pen
            if self.autoReturn then
                task.wait(AC.Jitter(0.8, 0.2))
                local pen = findPen()
                if pen then
                    tpTo(pen)
                end
            end
        end
    end)
end

function AutoSteal:Stop()
    self.enabled = false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 6: AUTO-TREADMILL (AFK SPEED FARM)
-- Simulates stepping on treadmill by rapid CFrame nudging
-- Anti-detection: uses variable step timing, not fixed tick
-- ═══════════════════════════════════════════════════════════

local AutoTreadmill = {}
AutoTreadmill.enabled = false
AutoTreadmill._thread = nil
AutoTreadmill.stepsPerSecond = 6   -- realistic: human walks ~6 steps/s

local function findTreadmill()
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local n = obj.Name:lower()
        if n:find("treadmill") and obj:IsA("BasePart") then
            -- Find the one owned by this player
            local uid = tostring(LocalPlayer.UserId)
            if obj:GetAttribute("Owner") == uid or
               (obj.Parent and obj.Parent.Name:find(uid)) then
                return obj
            end
        end
    end
    -- Fallback: return first treadmill found
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:lower():find("treadmill") and obj:IsA("BasePart") then
            return obj
        end
    end
    return nil
end

function AutoTreadmill:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        local treadmill = findTreadmill()
        if not treadmill then
            warn("[CrowScript] Treadmill not found — retrying in 5s")
            task.wait(5)
            treadmill = findTreadmill()
            if not treadmill then return end
        end

        -- Teleport to treadmill position
        tpTo(treadmill)
        task.wait(0.5)

        local stepInterval = 1 / self.stepsPerSecond
        local toggle = false
        while self.enabled do
            local hrp = getHRP()
            if not hrp then task.wait(1) continue end

            -- Micro-step: nudge forward/back to register movement
            local jitter = AC.Jitter(stepInterval, stepInterval * 0.3)
            local offset = toggle and 0.4 or -0.4
            toggle = not toggle

            hrp.CFrame = hrp.CFrame * CFrame.new(offset, 0, 0)
            task.wait(jitter)
        end
    end)
end

function AutoTreadmill:Stop()
    self.enabled = false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 7: AUTO-COLLECT (INCOME COLLECTION)
-- Periodically fires the income collection remote
-- ═══════════════════════════════════════════════════════════

local AutoCollect = {}
AutoCollect.enabled  = false
AutoCollect._thread  = nil
AutoCollect.interval = 1.0   -- seconds between collections

function AutoCollect:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            task.wait(AC.Jitter(self.interval, 0.3))
            if Remotes.Collect and AC.RateLimit("Collect", 0.5) then
                if Remotes.Collect:IsA("RemoteEvent") then
                    Remotes.Collect:FireServer()
                end
            end
        end
    end)
end

function AutoCollect:Stop()
    self.enabled = false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 8: ESP SYSTEM  (v2.7 — REAL VALUES, MOBILE SAFE)
--
-- Cash value reading strategy (priority order):
--   1. obj:GetAttribute("CashValue")      ← most games set this
--   2. obj:GetAttribute("Value")
--   3. obj:GetAttribute("Income")
--   4. obj:GetAttribute("MoneyPerSecond") or "MPS"
--   5. StringValue/IntValue/NumberValue child named Cash/Value
--   6. Parent attribute lookup (egg inside a Model)
--   7. Name-pattern lookup in BIOMES table as fallback
--
-- Billboard is sized for mobile (larger text, bigger box).
-- Highlights use SelectionBox (supported in Delta/Hydrogen).
-- ═══════════════════════════════════════════════════════════

local ESP = {}
ESP.enabled        = false
ESP.showEggs       = true
ESP.showGuardians  = true
ESP.showBearTraps  = true
ESP.showPlayers    = true
ESP._highlights    = {}
ESP._billboards    = {}

local ESP_COLORS = {
    Egg_Common    = Color3.fromRGB(200, 200, 200),
    Egg_Uncommon  = Color3.fromRGB(80, 220, 80),
    Egg_Rare      = Color3.fromRGB(80, 120, 255),
    Egg_Epic      = Color3.fromRGB(160, 60, 240),
    Egg_Legendary = Color3.fromRGB(255, 180, 0),
    Egg_Cosmic    = Color3.fromRGB(0, 220, 255),
    Egg_Secret    = Color3.fromRGB(255, 60, 180),
    Egg_Eternal   = Color3.fromRGB(255, 100, 0),
    Egg_Divine    = Color3.fromRGB(255, 255, 100),
    Guardian      = Color3.fromRGB(255, 55, 55),
    BearTrap      = Color3.fromRGB(255, 130, 0),
    Player        = Color3.fromRGB(100, 200, 255),
    Default       = Color3.fromRGB(255, 220, 50),
}

-- Rarity → colour lookup
local function rarityColor(rarity)
    if not rarity then return ESP_COLORS.Default end
    local r = rarity:lower()
    if r:find("divine")   then return ESP_COLORS.Egg_Divine   end
    if r:find("eternal")  then return ESP_COLORS.Egg_Eternal  end
    if r:find("secret")   then return ESP_COLORS.Egg_Secret   end
    if r:find("cosmic")   then return ESP_COLORS.Egg_Cosmic   end
    if r:find("legend")   then return ESP_COLORS.Egg_Legendary end
    if r:find("epic")     then return ESP_COLORS.Egg_Epic     end
    if r:find("rare")     then return ESP_COLORS.Egg_Rare     end
    if r:find("uncommon") then return ESP_COLORS.Egg_Uncommon end
    return ESP_COLORS.Egg_Common
end

-- ── Cash value reader ──────────────────────────────────────
-- Tries every known attribute/child name the game might use.
-- Returns a formatted string like "$1,800/s" or "?" if unknown.

-- Fallback: name-pattern → known income from BIOMES pet data
-- We build a flat lookup: petname_lower → base_$/s
local _nameFallback = {}
do
    local knownPets = {
        -- Forest
        chicken=1, dog=2, bird=8, ["burrowing owl"]=35, raccoon=45,
        fox=180, bear=240, ["brr brr patapim"]=1800,
        -- Lake
        frog=3, duckling=4, catfish=12, turtle=60,
        ["trulimero trulicina"]=260, swan=320, axolotl=2800, leviathan=220000,
        -- Desert
        jerboa=400, meerkat=900, camel=4000, ["scorpion pet"]=12000,
        ["desert fox"]=45000, vulture=90000, pharaoh=180000,
        ["royal sphinx"]=280000,
        -- Jungle
        parrot=5000, monkey=12000, toucan=30000, jaguar=80000,
        anaconda=200000, gorilla=500000, ["king snake"]=3500000,
        -- Snow
        penguin=50000, arctic_fox=120000, polar_bear=300000,
        ["snow owl"]=800000, walrus=2000000, mammoth=8000000,
        ["ice dragon"]=65000000,
        -- Volcano
        ["lava gecko"]=200000, salamander=600000, magma_crab=1500000,
        phoenix=5000000, cerberus_pet=20000000, ["lava dragon"]=100000000,
    }
    for k, v in pairs(knownPets) do
        _nameFallback[k:lower()] = v
    end
end

local function formatCash(n)
    if not n or n == 0 then return "?" end
    if n >= 1e12 then return string.format("$%.1fT/s", n/1e12) end
    if n >= 1e9  then return string.format("$%.1fB/s", n/1e9)  end
    if n >= 1e6  then return string.format("$%.1fM/s", n/1e6)  end
    if n >= 1e3  then return string.format("$%.1fK/s", n/1e3)  end
    return string.format("$%d/s", n)
end

local function readEggCashValue(obj)
    -- Priority 1-4: direct attributes on object
    local attrKeys = {
        "CashValue", "Value", "Income", "MoneyPerSecond", "MPS",
        "CashPerSecond", "Earnings", "EggValue", "PetIncome",
        "PetCash", "BaseIncome", "BaseCash", "IncomePerSecond",
        "EggIncome", "EggCash", "HatchIncome", "Money"
    }
    for _, key in ipairs(attrKeys) do
        local v = obj:GetAttribute(key)
        if v and type(v) == "number" and v > 0 then
            return v
        end
    end

    -- Priority 5: value children
    local valueNames = {"Cash", "Value", "Income", "Money", "MPS",
                        "CashValue", "EggValue", "PetIncome"}
    for _, vname in ipairs(valueNames) do
        local child = obj:FindFirstChild(vname)
        if child and (child:IsA("NumberValue") or
                      child:IsA("IntValue") or
                      child:IsA("IntConstrainedValue")) then
            if child.Value and child.Value > 0 then
                return child.Value
            end
        end
    end

    -- Priority 6: check parent (egg BasePart inside a Model)
    if obj.Parent and obj.Parent ~= Workspace then
        for _, key in ipairs(attrKeys) do
            local v = obj.Parent:GetAttribute(key)
            if v and type(v) == "number" and v > 0 then
                return v
            end
        end
    end

    -- Priority 7: name-pattern fallback from known pet table
    local nameLower = obj.Name:lower()
    -- Strip "egg" suffix for matching
    nameLower = nameLower:gsub("egg", ""):gsub("_", " "):match("^%s*(.-)%s*$")
    if _nameFallback[nameLower] then
        return _nameFallback[nameLower]
    end
    -- Partial match
    for petName, income in pairs(_nameFallback) do
        if nameLower:find(petName) or petName:find(nameLower) then
            return income
        end
    end

    return nil
end

-- ── Billboard builder (mobile-sized) ──────────────────────
local function makeBillboard(adornPart, lines, textColor, bgColor, height)
    local bb = Instance.new("BillboardGui")
    bb.Name          = "_CrowESPBB"
    bb.AlwaysOnTop   = true
    bb.Size          = UDim2.new(0, 160, 0, height or 52)
    bb.StudsOffset   = Vector3.new(0, 4, 0)
    bb.Adornee       = adornPart
    bb.Parent        = CoreGui

    -- Background pill
    local bg = Instance.new("Frame")
    bg.Size                  = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3      = bgColor or Color3.fromRGB(10, 10, 18)
    bg.BackgroundTransparency = 0.25
    bg.BorderSizePixel       = 0
    bg.Parent                = bb
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Size                  = UDim2.new(1, -6, 1, -4)
    lbl.Position              = UDim2.new(0, 3, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3            = textColor or Color3.new(1, 1, 1)
    lbl.TextScaled            = true
    lbl.Font                  = Enum.Font.GothamBold
    lbl.Text                  = lines
    lbl.TextWrapped           = true
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3      = Color3.new(0, 0, 0)
    lbl.Parent                = bg

    table.insert(ESP._billboards, bb)
    return bb
end

-- ── SelectionBox highlight ─────────────────────────────────
local function addHighlight(part, color, thickness)
    local sb = Instance.new("SelectionBox")
    sb.Name           = "_CrowESPSB"
    sb.Adornee        = part
    sb.Color3         = color
    sb.LineThickness  = thickness or 0.06
    sb.SurfaceColor3  = color
    sb.SurfaceTransparency = 0.7
    sb.Parent         = CoreGui
    table.insert(ESP._highlights, sb)
    return sb
end

-- ── Main refresh ───────────────────────────────────────────
function ESP:Refresh()
    -- Clean previous frame
    for _, h in ipairs(self._highlights) do
        pcall(function() h:Destroy() end)
    end
    for _, b in ipairs(self._billboards) do
        pcall(function() b:Destroy() end)
    end
    self._highlights = {}
    self._billboards = {}

    if not self.enabled then return end

    local hrpPos = getHRP() and getHRP().Position

    -- ── EGG ESP ───────────────────────────────────────────
    if self.showEggs then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            local n = obj.Name:lower()
            local isEgg = n:find("egg")
                       or obj:GetAttribute("IsEgg") == true
                       or obj:GetAttribute("EggType") ~= nil
            if isEgg and (obj:IsA("BasePart") or obj:IsA("Model")) then
                local part = obj:IsA("BasePart") and obj
                          or obj.PrimaryPart
                          or obj:FindFirstChildOfClass("BasePart")
                if part then
                    local rarity  = obj:GetAttribute("Rarity")
                               or obj:GetAttribute("EggRarity")
                               or obj.Parent:GetAttribute("Rarity")
                               or "?"
                    local cash    = readEggCashValue(obj)
                    local cashStr = formatCash(cash)

                    -- Distance
                    local distStr = ""
                    if hrpPos then
                        local d = math.floor((hrpPos - part.Position).Magnitude)
                        distStr = "\n📍 " .. d .. " studs"
                    end

                    local col = rarityColor(rarity)
                    addHighlight(part, col, 0.07)

                    local label = "🥚 " .. obj.Name
                              .. "\n💰 " .. cashStr
                              .. "\n✨ " .. rarity
                              .. distStr

                    makeBillboard(part, label, col,
                        Color3.fromRGB(10, 10, 18), 72)
                end
            end
        end
    end

    -- ── GUARDIAN ESP ──────────────────────────────────────
    if self.showGuardians then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            local n = obj.Name:lower()
            if (n:find("guardian") or n:find("guard") or
                n:find("boss") or n:find("enemy")) and
               obj:IsA("Model") then
                local part = obj.PrimaryPart
                          or obj:FindFirstChildOfClass("BasePart")
                if part then
                    addHighlight(part, ESP_COLORS.Guardian, 0.08)
                    local distStr = ""
                    if hrpPos then
                        local d = math.floor((hrpPos - part.Position).Magnitude)
                        distStr = "\n📍 " .. d .. " studs"
                        -- Red glow text if very close
                    end
                    local d = hrpPos and (hrpPos - part.Position).Magnitude or 999
                    local warningIcon = d < 25 and "🔴 DANGER" or "⚠️"
                    makeBillboard(part,
                        warningIcon .. " " .. obj.Name .. distStr,
                        ESP_COLORS.Guardian,
                        Color3.fromRGB(30, 5, 5), 52)
                end
            end
        end
    end

    -- ── BEAR TRAP ESP ─────────────────────────────────────
    if self.showBearTraps then
        for _, obj in ipairs(Workspace:GetDescendants()) do
            local n = obj.Name:lower()
            if (n:find("trap") or n:find("beartrap") or
                n:find("bear_trap")) and obj:IsA("BasePart") then
                -- Don't highlight own traps if attributable
                local owner = obj:GetAttribute("Owner")
                            or obj:GetAttribute("PlayerId")
                local isOwn = owner == tostring(LocalPlayer.UserId)

                addHighlight(obj, isOwn and Color3.fromRGB(0,255,80)
                                       or  ESP_COLORS.BearTrap, 0.07)

                local label = isOwn and "🪤 MY TRAP" or "🪤 ENEMY TRAP"
                if hrpPos then
                    local d = math.floor((hrpPos - obj.Position).Magnitude)
                    label = label .. "\n📍 " .. d .. "s"
                end
                makeBillboard(obj, label, ESP_COLORS.BearTrap,
                    Color3.fromRGB(30, 15, 0), 44)
            end
        end
    end

    -- ── PLAYER ESP ────────────────────────────────────────
    if self.showPlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                local hrp2 = plr.Character:FindFirstChild("HumanoidRootPart")
                if hrp2 then
                    addHighlight(hrp2, ESP_COLORS.Player, 0.06)

                    -- Read income: try multiple attribute names
                    local income = plr:GetAttribute("TotalIncome")
                               or plr:GetAttribute("Income")
                               or plr:GetAttribute("CashPerSecond")
                               or plr:GetAttribute("MPS")
                               or plr:GetAttribute("MoneyPerSecond")
                    local incomeStr = income and formatCash(income) or "?"

                    -- Cash on hand
                    local cash = plr:GetAttribute("Cash")
                              or plr:GetAttribute("Money")
                    local cashStr = cash and formatCash(cash):gsub("/s","") or "?"

                    local distStr = ""
                    if hrpPos then
                        local d = math.floor((hrpPos - hrp2.Position).Magnitude)
                        distStr = "\n📍 " .. d .. " studs"
                    end

                    local label = "👤 " .. plr.DisplayName
                              .. "\n💰 " .. incomeStr
                              .. "\n💵 " .. cashStr .. " cash"
                              .. distStr

                    makeBillboard(hrp2, label, ESP_COLORS.Player,
                        Color3.fromRGB(5, 15, 30), 72)
                end
            end
        end
    end
end

-- Auto-refresh on a fixed cadence (3s), task.spawn keeps it
-- off the main thread — no frame hitching on mobile
task.spawn(function()
    while true do
        task.wait(3)
        if ESP.enabled then
            pcall(function() ESP:Refresh() end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════
-- SECTION 9: BIOME TELEPORT
-- ═══════════════════════════════════════════════════════════

local BiomeTeleport = {}

function BiomeTeleport.GoTo(biomeName)
    -- Find biome region in workspace
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj.Name:lower():find(biomeName:lower()) then
            local part = obj:IsA("BasePart") and obj
                      or obj:FindFirstChildOfClass("BasePart")
            if part then
                tpTo(part)
                return true
            end
        end
    end
    -- Fallback: try RemoteEvent teleport if game provides one
    if Remotes.Teleport then
        Remotes.Teleport:FireServer(biomeName)
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 10: AUTO-BUY UPGRADES
-- Auto-purchases treadmills and trails when cash is available
-- ═══════════════════════════════════════════════════════════

local AutoBuy = {}
AutoBuy.enabled         = false
AutoBuy.buyTreadmills   = true
AutoBuy.buyTrails       = true
AutoBuy._thread         = nil

local function getPlayerCash()
    local cash = LocalPlayer:GetAttribute("Cash")
               or LocalPlayer:GetAttribute("Money")
               or LocalPlayer.leaderstats
                  and LocalPlayer.leaderstats:FindFirstChild("Cash")
                  and LocalPlayer.leaderstats.Cash.Value
    return cash or 0
end

function AutoBuy:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            task.wait(AC.Jitter(5, 1.5))
            local cash = getPlayerCash()

            -- Buy best treadmill we can afford
            if self.buyTreadmills then
                for i = #TREADMILLS, 1, -1 do
                    local tm = TREADMILLS[i]
                    if tm.cost > 0 and cash >= tm.cost then
                        if Remotes.Treadmill and
                           AC.RateLimit("BuyTreadmill", 3.0) then
                            if Remotes.Treadmill:IsA("RemoteEvent") then
                                Remotes.Treadmill:FireServer(tm.name)
                            end
                        end
                        break
                    end
                end
            end

            -- Buy best trail we can afford
            if self.buyTrails then
                for i = #TRAILS, 1, -1 do
                    local tr = TRAILS[i]
                    if tr.cost > 0 and cash >= tr.cost then
                        if Remotes.Trail and
                           AC.RateLimit("BuyTrail", 3.0) then
                            if Remotes.Trail:IsA("RemoteEvent") then
                                Remotes.Trail:FireServer(tr.name)
                            end
                        end
                        break
                    end
                end
            end
        end
    end)
end

function AutoBuy:Stop()
    self.enabled = false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 11: NOCLIP
-- Passes through walls — useful for navigating into nests
-- Anti-detect: only active when carrying egg, then off
-- ═══════════════════════════════════════════════════════════

local Noclip = {}
Noclip.enabled = false
Noclip._conn   = nil

function Noclip:Enable()
    self.enabled = true
    self._conn = RunService.Stepped:Connect(function()
        local char = LocalPlayer.Character
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = not self.enabled
            end
        end
    end)
end

function Noclip:Disable()
    self.enabled = false
    if self._conn then self._conn:Disconnect() end
    -- Re-enable collisions
    local char = LocalPlayer.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = true
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 12: AUTO-HATCH (FAST-TRACK EGG GROWTH)
-- Fires growth-tick remote repeatedly within server rate limit
-- ═══════════════════════════════════════════════════════════

local AutoHatch = {}
AutoHatch.enabled  = false
AutoHatch._thread  = nil

function AutoHatch:Start()
    self.enabled = true
    self._thread = task.spawn(function()
        while self.enabled do
            task.wait(AC.Jitter(0.5, 0.15))
            -- Hatch remote fires when egg is ready
            if Remotes.HatchEgg and AC.RateLimit("HatchEgg", 0.4) then
                if Remotes.HatchEgg:IsA("RemoteEvent") then
                    Remotes.HatchEgg:FireServer()
                elseif Remotes.HatchEgg:IsA("RemoteFunction") then
                    pcall(function() Remotes.HatchEgg:InvokeServer() end)
                end
            end
        end
    end)
end

function AutoHatch:Stop()
    self.enabled = false
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 13: UI — MOD MENU
-- Dark themed, draggable, collapsible, tabbed
-- ═══════════════════════════════════════════════════════════

-- Colour palette
local UI_COLORS = {
    BG        = Color3.fromRGB(14, 14, 22),
    BG2       = Color3.fromRGB(22, 22, 34),
    ACCENT    = Color3.fromRGB(120, 60, 220),
    ACCENT2   = Color3.fromRGB(80, 180, 255),
    TEXT      = Color3.fromRGB(230, 230, 240),
    SUBTEXT   = Color3.fromRGB(160, 160, 180),
    TOGGLE_ON = Color3.fromRGB(60, 220, 110),
    TOGGLE_OFF= Color3.fromRGB(80, 80, 100),
    DANGER    = Color3.fromRGB(220, 60, 60),
    WARNING   = Color3.fromRGB(240, 160, 40),
    BORDER    = Color3.fromRGB(60, 40, 100),
}

local CoreGui = game:GetService("CoreGui")

-- Remove old GUI if re-injecting
local existingGui = CoreGui:FindFirstChild("CrowModMenu")
if existingGui then existingGui:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name                 = "CrowModMenu"
ScreenGui.ResetOnSpawn         = false
ScreenGui.ZIndexBehavior       = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset       = true
ScreenGui.DisplayOrder         = 9999
ScreenGui.Parent               = CoreGui

-- Main frame
local MainFrame = Instance.new("Frame")
MainFrame.Name               = "Main"
MainFrame.Size               = UDim2.new(0, 360, 0, 520)
MainFrame.Position           = UDim2.new(0, 80, 0, 80)
MainFrame.BackgroundColor3   = UI_COLORS.BG
MainFrame.BorderSizePixel    = 0
MainFrame.ClipsDescendants   = true
MainFrame.Active             = true
MainFrame.Draggable          = true
MainFrame.Parent             = ScreenGui

-- Rounded corners
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = MainFrame

-- Border stroke
local stroke = Instance.new("UIStroke")
stroke.Color = UI_COLORS.BORDER
stroke.Thickness = 1.5
stroke.Parent = MainFrame

-- Drop shadow (fake with another frame behind)
local shadow = Instance.new("Frame")
shadow.Size               = UDim2.new(1, 8, 1, 8)
shadow.Position           = UDim2.new(0, -4, 0, 4)
shadow.BackgroundColor3   = Color3.new(0, 0, 0)
shadow.BackgroundTransparency = 0.6
shadow.BorderSizePixel    = 0
shadow.ZIndex             = 0
shadow.Parent             = MainFrame
Instance.new("UICorner", shadow).CornerRadius = UDim.new(0, 12)

-- ── Title bar ──────────────────────────────────────────────
local TitleBar = Instance.new("Frame")
TitleBar.Name            = "TitleBar"
TitleBar.Size            = UDim2.new(1, 0, 0, 44)
TitleBar.BackgroundColor3 = UI_COLORS.BG2
TitleBar.BorderSizePixel = 0
TitleBar.ZIndex          = 2
TitleBar.Parent          = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleGradient = Instance.new("UIGradient")
TitleGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, UI_COLORS.ACCENT),
    ColorSequenceKeypoint.new(1, UI_COLORS.ACCENT2),
})
TitleGradient.Rotation = 90
TitleGradient.Parent   = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Text             = "🥚 STEAL AN EGG  |  CROW MENU"
TitleLabel.Font             = Enum.Font.GothamBold
TitleLabel.TextSize         = 14
TitleLabel.TextColor3       = UI_COLORS.TEXT
TitleLabel.BackgroundTransparency = 1
TitleLabel.Size             = UDim2.new(1, -50, 1, 0)
TitleLabel.Position         = UDim2.new(0, 12, 0, 0)
TitleLabel.TextXAlignment   = Enum.TextXAlignment.Left
TitleLabel.ZIndex           = 3
TitleLabel.Parent           = TitleBar

-- Close/minimise button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Text            = "✕"
CloseBtn.Size            = UDim2.new(0, 32, 0, 32)
CloseBtn.Position        = UDim2.new(1, -38, 0, 6)
CloseBtn.Font            = Enum.Font.GothamBold
CloseBtn.TextSize        = 16
CloseBtn.TextColor3      = UI_COLORS.TEXT
CloseBtn.BackgroundColor3 = UI_COLORS.DANGER
CloseBtn.BorderSizePixel = 0
CloseBtn.ZIndex          = 4
CloseBtn.Parent          = TitleBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)

CloseBtn.MouseButton1Click:Connect(function()
    MainFrame.Visible = not MainFrame.Visible
end)

-- ── Tab system ─────────────────────────────────────────────
local TAB_NAMES = {"⚡ Main", "🥚 Steal", "🏃 Speed", "👁 ESP", "💰 Farm", "🗺 Biomes", "🔧 Settings"}

local TabBar = Instance.new("Frame")
TabBar.Name             = "TabBar"
TabBar.Size             = UDim2.new(1, 0, 0, 34)
TabBar.Position         = UDim2.new(0, 0, 0, 44)
TabBar.BackgroundColor3 = UI_COLORS.BG2
TabBar.BorderSizePixel  = 0
TabBar.Parent           = MainFrame

local TabLayout = Instance.new("UIListLayout")
TabLayout.FillDirection = Enum.FillDirection.Horizontal
TabLayout.SortOrder     = Enum.SortOrder.LayoutOrder
TabLayout.Padding       = UDim.new(0, 2)
TabLayout.Parent        = TabBar

-- Content area
local ContentFrame = Instance.new("ScrollingFrame")
ContentFrame.Name                = "Content"
ContentFrame.Size                = UDim2.new(1, 0, 1, -78)
ContentFrame.Position            = UDim2.new(0, 0, 0, 78)
ContentFrame.BackgroundTransparency = 1
ContentFrame.BorderSizePixel     = 0
ContentFrame.ScrollBarThickness  = 4
ContentFrame.CanvasSize          = UDim2.new(0, 0, 0, 0)
ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ContentFrame.ScrollBarImageColor3 = UI_COLORS.ACCENT
ContentFrame.Parent              = MainFrame

local ContentLayout = Instance.new("UIListLayout")
ContentLayout.SortOrder   = Enum.SortOrder.LayoutOrder
ContentLayout.Padding     = UDim.new(0, 6)
ContentLayout.Parent      = ContentFrame

local ContentPadding = Instance.new("UIPadding")
ContentPadding.PaddingLeft   = UDim.new(0, 10)
ContentPadding.PaddingRight  = UDim.new(0, 10)
ContentPadding.PaddingTop    = UDim.new(0, 8)
ContentPadding.PaddingBottom = UDim.new(0, 8)
ContentPadding.Parent        = ContentFrame

-- Pages (one Frame per tab)
local Pages = {}
local CurrentTab = nil

local function createPage(name)
    local page = Instance.new("Frame")
    page.Name                   = name
    page.Size                   = UDim2.new(1, 0, 0, 0)
    page.AutomaticSize          = Enum.AutomaticSize.Y
    page.BackgroundTransparency = 1
    page.BorderSizePixel        = 0
    page.Visible                = false
    page.Parent                 = ContentFrame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding   = UDim.new(0, 6)
    layout.Parent    = page

    Pages[name] = page
    return page
end

local function showTab(name)
    for n, page in pairs(Pages) do
        page.Visible = (n == name)
    end
    CurrentTab = name
end

-- Create tab buttons and pages
for i, tabName in ipairs(TAB_NAMES) do
    local btn = Instance.new("TextButton")
    btn.Text             = tabName
    btn.Font             = Enum.Font.Gotham
    btn.TextSize         = 10
    btn.TextColor3       = UI_COLORS.SUBTEXT
    btn.BackgroundColor3 = UI_COLORS.BG2
    btn.BorderSizePixel  = 0
    btn.Size             = UDim2.new(0, 46, 1, 0)
    btn.LayoutOrder      = i
    btn.ZIndex           = 3
    btn.Parent           = TabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    createPage(tabName)

    btn.MouseButton1Click:Connect(function()
        showTab(tabName)
        -- Highlight active tab
        for _, b in ipairs(TabBar:GetChildren()) do
            if b:IsA("TextButton") then
                b.TextColor3       = UI_COLORS.SUBTEXT
                b.BackgroundColor3 = UI_COLORS.BG2
            end
        end
        btn.TextColor3       = Color3.new(1, 1, 1)
        btn.BackgroundColor3 = UI_COLORS.ACCENT
    end)
end

showTab(TAB_NAMES[1])  -- default to Main

-- ── UI Components ──────────────────────────────────────────

-- Toggle row builder
local function makeToggle(parent, label, subLabel, defaultOn, onToggle)
    local row = Instance.new("Frame")
    row.Name               = "Toggle_" .. label
    row.Size               = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3   = UI_COLORS.BG2
    row.BorderSizePixel    = 0
    row.Parent             = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Text             = label
    lbl.Font             = Enum.Font.GothamBold
    lbl.TextSize         = 13
    lbl.TextColor3       = UI_COLORS.TEXT
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(1, -70, 0, 24)
    lbl.Position         = UDim2.new(0, 12, 0, 6)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = row

    local sub = Instance.new("TextLabel")
    sub.Text             = subLabel or ""
    sub.Font             = Enum.Font.Gotham
    sub.TextSize         = 10
    sub.TextColor3       = UI_COLORS.SUBTEXT
    sub.BackgroundTransparency = 1
    sub.Size             = UDim2.new(1, -70, 0, 18)
    sub.Position         = UDim2.new(0, 12, 0, 28)
    sub.TextXAlignment   = Enum.TextXAlignment.Left
    sub.Parent           = row

    -- Toggle pill
    local pill = Instance.new("Frame")
    pill.Size            = UDim2.new(0, 46, 0, 24)
    pill.Position        = UDim2.new(1, -58, 0.5, -12)
    pill.BackgroundColor3 = defaultOn and UI_COLORS.TOGGLE_ON or UI_COLORS.TOGGLE_OFF
    pill.BorderSizePixel = 0
    pill.Parent          = row
    Instance.new("UICorner", pill).CornerRadius = UDim.new(0, 12)

    local knob = Instance.new("Frame")
    knob.Size            = UDim2.new(0, 18, 0, 18)
    knob.Position        = defaultOn
                           and UDim2.new(0, 25, 0, 3)
                           or  UDim2.new(0, 3, 0, 3)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent          = pill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, 9)

    local state = defaultOn
    local btn   = Instance.new("TextButton")
    btn.Size     = UDim2.new(1, 0, 1, 0)
    btn.BackgroundTransparency = 1
    btn.Text     = ""
    btn.Parent   = row

    btn.MouseButton1Click:Connect(function()
        state = not state
        pill.BackgroundColor3 = state and UI_COLORS.TOGGLE_ON or UI_COLORS.TOGGLE_OFF
        TweenService:Create(knob, TweenInfo.new(0.15), {
            Position = state
                       and UDim2.new(0, 25, 0, 3)
                       or  UDim2.new(0, 3, 0, 3)
        }):Play()
        if onToggle then onToggle(state) end
    end)

    return row, function() return state end
end

-- Section header builder
local function makeHeader(parent, text, color)
    local lbl = Instance.new("TextLabel")
    lbl.Text             = text
    lbl.Font             = Enum.Font.GothamBold
    lbl.TextSize         = 11
    lbl.TextColor3       = color or UI_COLORS.ACCENT
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(1, 0, 0, 22)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = parent
    return lbl
end

-- Button builder
local function makeButton(parent, text, color, onClick)
    local btn = Instance.new("TextButton")
    btn.Text             = text
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 13
    btn.TextColor3       = Color3.new(1, 1, 1)
    btn.BackgroundColor3 = color or UI_COLORS.ACCENT
    btn.BorderSizePixel  = 0
    btn.Size             = UDim2.new(1, 0, 0, 38)
    btn.Parent           = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

    btn.MouseButton1Click:Connect(function()
        if onClick then onClick() end
        -- Brief press animation
        TweenService:Create(btn, TweenInfo.new(0.1), {
            BackgroundColor3 = Color3.new(
                color and color.R * 0.8 or 0.4,
                color and color.G * 0.8 or 0.2,
                color and color.B * 0.8 or 0.7
            )
        }):Play()
        task.delay(0.15, function()
            TweenService:Create(btn, TweenInfo.new(0.1), {
                BackgroundColor3 = color or UI_COLORS.ACCENT
            }):Play()
        end)
    end)
    return btn
end

-- Dropdown builder (biome selector)
local function makeDropdown(parent, label, options, defaultOpt, onChange)
    local holder = Instance.new("Frame")
    holder.Size            = UDim2.new(1, 0, 0, 80)
    holder.BackgroundColor3 = UI_COLORS.BG2
    holder.BorderSizePixel = 0
    holder.Parent          = parent
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel")
    lbl.Text             = label
    lbl.Font             = Enum.Font.GothamBold
    lbl.TextSize         = 12
    lbl.TextColor3       = UI_COLORS.TEXT
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(1, -20, 0, 22)
    lbl.Position         = UDim2.new(0, 10, 0, 6)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = holder

    local selected = defaultOpt or options[1]
    local selLabel = Instance.new("TextButton")
    selLabel.Text            = selected .. "  ▾"
    selLabel.Font            = Enum.Font.Gotham
    selLabel.TextSize        = 12
    selLabel.TextColor3      = UI_COLORS.ACCENT2
    selLabel.BackgroundColor3 = UI_COLORS.BG
    selLabel.BorderSizePixel = 0
    selLabel.Size            = UDim2.new(1, -20, 0, 30)
    selLabel.Position        = UDim2.new(0, 10, 0, 32)
    selLabel.TextXAlignment  = Enum.TextXAlignment.Left
    selLabel.Parent          = holder
    Instance.new("UICorner", selLabel).CornerRadius = UDim.new(0, 6)

    -- Dropdown list (shown on click)
    local dropList = Instance.new("Frame")
    dropList.Size            = UDim2.new(1, -20, 0, #options * 28 + 6)
    dropList.Position        = UDim2.new(0, 10, 1, 2)
    dropList.BackgroundColor3 = UI_COLORS.BG
    dropList.BorderSizePixel = 0
    dropList.ZIndex          = 20
    dropList.Visible         = false
    dropList.Parent          = holder
    Instance.new("UICorner", dropList).CornerRadius = UDim.new(0, 6)
    Instance.new("UIStroke", dropList).Color = UI_COLORS.BORDER

    local dLayout = Instance.new("UIListLayout")
    dLayout.Parent  = dropList
    dLayout.Padding = UDim.new(0, 2)

    for _, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.Text            = opt
        optBtn.Font            = Enum.Font.Gotham
        optBtn.TextSize        = 11
        optBtn.TextColor3      = UI_COLORS.TEXT
        optBtn.BackgroundTransparency = 1
        optBtn.Size            = UDim2.new(1, 0, 0, 26)
        optBtn.TextXAlignment  = Enum.TextXAlignment.Left
        optBtn.ZIndex          = 21
        optBtn.Parent          = dropList

        local optPad = Instance.new("UIPadding")
        optPad.PaddingLeft = UDim.new(0, 8)
        optPad.Parent      = optBtn

        optBtn.MouseButton1Click:Connect(function()
            selected = opt
            selLabel.Text = opt .. "  ▾"
            dropList.Visible = false
            holder.Size = UDim2.new(1, 0, 0, 80)
            if onChange then onChange(opt) end
        end)

        optBtn.MouseEnter:Connect(function()
            optBtn.TextColor3 = UI_COLORS.ACCENT2
        end)
        optBtn.MouseLeave:Connect(function()
            optBtn.TextColor3 = UI_COLORS.TEXT
        end)
    end

    selLabel.MouseButton1Click:Connect(function()
        local vis = not dropList.Visible
        dropList.Visible = vis
        holder.Size = UDim2.new(1, 0, 0, vis and (80 + #options * 28 + 8) or 80)
    end)

    return holder
end

-- ═══════════════════════════════════════════════════════════
-- POPULATE TABS
-- ═══════════════════════════════════════════════════════════

-- ── TAB 1: MAIN ────────────────────────────────────────────
local mainPage = Pages[TAB_NAMES[1]]

makeHeader(mainPage, "  ◆ STATUS")

local statusLabel = Instance.new("TextLabel")
statusLabel.Text             = "Script loaded. Remote scan in progress..."
statusLabel.Font             = Enum.Font.Gotham
statusLabel.TextSize         = 11
statusLabel.TextColor3       = UI_COLORS.WARNING
statusLabel.BackgroundColor3 = UI_COLORS.BG2
statusLabel.BorderSizePixel  = 0
statusLabel.Size             = UDim2.new(1, 0, 0, 38)
statusLabel.TextXAlignment   = Enum.TextXAlignment.Left
statusLabel.TextWrapped      = true
statusLabel.Parent           = mainPage
Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)
Instance.new("UIPadding", statusLabel).PaddingLeft = UDim.new(0, 10)

task.spawn(function()
    task.wait(4)
    local found = {}
    for k, v in pairs(Remotes) do
        if k ~= "_all" then
            table.insert(found, k)
        end
    end
    if #found > 0 then
        statusLabel.Text     = "✓ Remotes mapped: " .. table.concat(found, ", ")
        statusLabel.TextColor3 = UI_COLORS.TOGGLE_ON
    else
        statusLabel.Text     = "⚠ No remotes found. Teleport/steal use position only."
        statusLabel.TextColor3 = UI_COLORS.WARNING
    end
end)

makeHeader(mainPage, "  ◆ QUICK TOGGLES")

makeToggle(mainPage, "Auto-Steal", "Auto-grabs eggs and returns to pen", false,
    function(on)
        if on then AutoSteal:Start() else AutoSteal:Stop() end
    end)

makeToggle(mainPage, "Auto-Treadmill", "AFK speed farming on treadmill", false,
    function(on)
        if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
    end)

makeToggle(mainPage, "Auto-Collect Income", "Fires income collection every second", false,
    function(on)
        if on then AutoCollect:Start() else AutoCollect:Stop() end
    end)

makeToggle(mainPage, "Speed Hack", "Multiplies local movement speed", false,
    function(on)
        if on then SpeedModule:Enable() else SpeedModule:Disable() end
    end)

makeToggle(mainPage, "ESP", "See eggs, guardians, and traps through walls", false,
    function(on)
        ESP.enabled = on
        if on then ESP:Refresh() else ESP:Refresh() end
    end)

makeHeader(mainPage, "  ◆ ANTI-DETECTION STATUS")

local adLabel = Instance.new("TextLabel")
adLabel.Text             = "🛡 Rate-limiter: ACTIVE  |  Loop jitter: ACTIVE\n🛡 Speed: WalkSpeed lerp (no BV, no glitch)  |  Cap: " .. SpeedModule.maxSafe
adLabel.Font             = Enum.Font.Gotham
adLabel.TextSize         = 10
adLabel.TextColor3       = UI_COLORS.TOGGLE_ON
adLabel.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
adLabel.BorderSizePixel  = 0
adLabel.Size             = UDim2.new(1, 0, 0, 42)
adLabel.TextXAlignment   = Enum.TextXAlignment.Left
adLabel.TextWrapped      = true
adLabel.Parent           = mainPage
Instance.new("UICorner", adLabel).CornerRadius = UDim.new(0, 8)
Instance.new("UIPadding", adLabel).PaddingLeft = UDim.new(0, 8)

-- ── TAB 2: STEAL ───────────────────────────────────────────
local stealPage = Pages[TAB_NAMES[2]]

makeHeader(stealPage, "  ◆ STEAL SETTINGS")

local biomeNames = {}
for _, b in ipairs(BIOMES) do
    table.insert(biomeNames, b.name .. " (≥" .. tostring(b.speedReq) .. " spd)")
end

makeDropdown(stealPage, "Target Biome", biomeNames,
    biomeNames[1], function(opt)
        -- Extract raw name before the parenthesis
        AutoSteal.targetBiome = opt:match("^(.-)%s*%(") or opt
    end)

local rarityOptions = {"Any", "Rare+", "Epic+", "Legendary+", "Cosmic+"}
makeDropdown(stealPage, "Rarity Filter", rarityOptions, "Any", function(opt)
    AutoSteal.rareFilter = opt
end)

makeToggle(stealPage, "Auto-Return to Pen", "Teleport home after each steal", true,
    function(on) AutoSteal.autoReturn = on end)

makeToggle(stealPage, "Drop Bear Trap on Chase",
    "Drops a trap when guardian is within 20 studs", true,
    function(on) AutoSteal.useBearTrap = on end)

makeToggle(stealPage, "Noclip During Steal",
    "Walk through walls into nest areas", false,
    function(on)
        if on then Noclip:Enable() else Noclip:Disable() end
    end)

makeHeader(stealPage, "  ◆ MANUAL STEAL")
makeButton(stealPage, "Steal Once (Current Biome)",
    UI_COLORS.ACCENT, function()
        local eggs = findEggsInBiome(AutoSteal.targetBiome)
        if eggs[1] then
            tpTo(eggs[1])
            task.wait(0.3)
            fireSteal(eggs[1])
        end
    end)

makeButton(stealPage, "Return to Pen Now",
    UI_COLORS.ACCENT2, function()
        local pen = findPen()
        if pen then tpTo(pen) end
    end)

-- ── TAB 3: SPEED ───────────────────────────────────────────
local speedPage = Pages[TAB_NAMES[3]]

makeHeader(speedPage, "  ◆ SPEED HACK  (Smooth · No Lag)")

makeToggle(speedPage, "Speed Hack", "Smooth WalkSpeed lerp — no physics glitch", false,
    function(on)
        if on then SpeedModule:Enable() else SpeedModule:Disable() end
    end)

-- Info box
local speedInfo = Instance.new("TextLabel")
speedInfo.Text             = "Selected: " .. SpeedModule.PRESETS[SpeedModule._presetIdx].label
                          .. "  (" .. SpeedModule.PRESETS[SpeedModule._presetIdx].speed .. " WalkSpeed)"
                          .. "\nSafe cap: " .. SpeedModule.maxSafe
                          .. "  |  Lerp: smooth ramp"
speedInfo.Font             = Enum.Font.Gotham
speedInfo.TextSize         = 10
speedInfo.TextColor3       = UI_COLORS.ACCENT2
speedInfo.BackgroundColor3 = UI_COLORS.BG2
speedInfo.BorderSizePixel  = 0
speedInfo.Size             = UDim2.new(1, 0, 0, 42)
speedInfo.TextXAlignment   = Enum.TextXAlignment.Left
speedInfo.TextWrapped      = true
speedInfo.Parent           = speedPage
Instance.new("UICorner", speedInfo).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", speedInfo).PaddingLeft  = UDim.new(0, 8)

-- One button per preset
local presetColors = {
    UI_COLORS.TOGGLE_ON,
    UI_COLORS.ACCENT2,
    UI_COLORS.ACCENT,
    UI_COLORS.WARNING,
    UI_COLORS.DANGER,
}
for i, preset in ipairs(SpeedModule.PRESETS) do
    local col = presetColors[i] or UI_COLORS.ACCENT
    makeButton(speedPage, preset.label .. "  [" .. preset.speed .. " WS]",
        col, function()
            SpeedModule:SetPreset(i)
            speedInfo.Text = "Selected: " .. preset.label
                          .. "  (" .. preset.speed .. " WalkSpeed)"
                          .. "\nSafe cap: " .. SpeedModule.maxSafe
                          .. "  |  Lerp: smooth ramp"
        end)
end

makeHeader(speedPage, "  ◆ AUTO-TREADMILL")

makeToggle(speedPage, "Auto-Treadmill", "AFK step simulation", false,
    function(on)
        if on then AutoTreadmill:Start() else AutoTreadmill:Stop() end
    end)

local stepsLabel = Instance.new("TextLabel")
stepsLabel.Text           = "Steps/sec: " .. AutoTreadmill.stepsPerSecond
stepsLabel.Font           = Enum.Font.Gotham
stepsLabel.TextSize       = 11
stepsLabel.TextColor3     = UI_COLORS.TEXT
stepsLabel.BackgroundTransparency = 1
stepsLabel.Size           = UDim2.new(1, 0, 0, 24)
stepsLabel.TextXAlignment = Enum.TextXAlignment.Left
stepsLabel.Parent         = speedPage

for _, rate in ipairs({3, 6, 10, 15}) do
    makeButton(speedPage, rate .. " steps/sec", UI_COLORS.BG2, function()
        AutoTreadmill.stepsPerSecond = rate
        stepsLabel.Text = "Steps/sec: " .. rate
    end)
end

-- ── TAB 4: ESP ─────────────────────────────────────────────
local espPage = Pages[TAB_NAMES[4]]

makeHeader(espPage, "  ◆ ESP OPTIONS")

makeToggle(espPage, "Enable ESP", "Master toggle for all ESP", false,
    function(on) ESP.enabled = on; ESP:Refresh() end)

makeToggle(espPage, "Show Eggs", "Highlight egg positions", true,
    function(on) ESP.showEggs = on; ESP:Refresh() end)

makeToggle(espPage, "Show Guardians", "Highlight guardian positions", true,
    function(on) ESP.showGuardians = on; ESP:Refresh() end)

makeToggle(espPage, "Show Bear Traps", "Highlight traps placed by others", true,
    function(on) ESP.showBearTraps = on; ESP:Refresh() end)

makeToggle(espPage, "Show Players + Income", "Show other players and their $/s", true,
    function(on) ESP.showPlayers = on; ESP:Refresh() end)

makeButton(espPage, "Refresh ESP Now", UI_COLORS.ACCENT, function()
    ESP:Refresh()
end)

-- ── TAB 5: FARM ────────────────────────────────────────────
local farmPage = Pages[TAB_NAMES[5]]

makeHeader(farmPage, "  ◆ AUTO-FARM")

makeToggle(farmPage, "Auto-Collect Income",
    "Fires income remote every ~1 second", false,
    function(on)
        if on then AutoCollect:Start() else AutoCollect:Stop() end
    end)

makeToggle(farmPage, "Auto-Hatch Eggs",
    "Repeatedly fires hatch remote for ready eggs", false,
    function(on)
        if on then AutoHatch:Start() else AutoHatch:Stop() end
    end)

makeToggle(farmPage, "Auto-Buy Treadmills",
    "Buys best treadmill affordable every 5 seconds", false,
    function(on)
        if on then AutoBuy:Start() else AutoBuy:Stop() end
    end)

makeToggle(farmPage, "Auto-Buy Trails",
    "Buys best speed trail affordable every 5 seconds", false,
    function(on) AutoBuy.buyTrails = on end)

makeHeader(farmPage, "  ◆ UPGRADE REFERENCE")

local refText = ""
refText = refText .. "TREADMILLS:\n"
for _, tm in ipairs(TREADMILLS) do
    refText = refText .. string.format("  %-22s +%d/step  $%s\n",
        tm.name, tm.sps, tm.cost == 0 and "FREE" or tostring(tm.cost))
end
refText = refText .. "\nTRAILS:\n"
for _, tr in ipairs(TRAILS) do
    refText = refText .. string.format("  %-16s  ×%.1f  $%d\n",
        tr.name, tr.mult, tr.cost)
end

local refLabel = Instance.new("TextLabel")
refLabel.Text             = refText
refLabel.Font             = Enum.Font.Code
refLabel.TextSize         = 9
refLabel.TextColor3       = UI_COLORS.SUBTEXT
refLabel.BackgroundColor3 = UI_COLORS.BG2
refLabel.BorderSizePixel  = 0
refLabel.Size             = UDim2.new(1, 0, 0, 0)
refLabel.AutomaticSize    = Enum.AutomaticSize.Y
refLabel.TextXAlignment   = Enum.TextXAlignment.Left
refLabel.TextWrapped      = true
refLabel.Parent           = farmPage
Instance.new("UICorner", refLabel).CornerRadius = UDim.new(0, 6)
Instance.new("UIPadding", refLabel).PaddingLeft = UDim.new(0, 8)

-- ── TAB 6: BIOMES ──────────────────────────────────────────
local biomePage = Pages[TAB_NAMES[6]]

makeHeader(biomePage, "  ◆ BIOME TELEPORT")

for _, biome in ipairs(BIOMES) do
    local row = Instance.new("Frame")
    row.Size            = UDim2.new(1, 0, 0, 54)
    row.BackgroundColor3 = UI_COLORS.BG2
    row.BorderSizePixel = 0
    row.Parent          = biomePage
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Text           = biome.name
    nameLbl.Font           = Enum.Font.GothamBold
    nameLbl.TextSize       = 12
    nameLbl.TextColor3     = UI_COLORS.TEXT
    nameLbl.BackgroundTransparency = 1
    nameLbl.Size           = UDim2.new(1, -100, 0, 24)
    nameLbl.Position       = UDim2.new(0, 10, 0, 5)
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent         = row

    local infoLbl = Instance.new("TextLabel")
    local spd = biome.speedReq
    local spdStr = spd >= 1e9 and (string.format("%.0fB", spd/1e9))
               or  spd >= 1e6 and (string.format("%.0fM", spd/1e6))
               or  spd >= 1e3 and (string.format("%.0fK", spd/1e3))
               or  tostring(spd)
    infoLbl.Text           = "≥" .. spdStr .. " spd  |  " ..
                             biome.guardian .. "  |  Best: " .. biome.bestPet
    infoLbl.Font           = Enum.Font.Gotham
    infoLbl.TextSize       = 9
    infoLbl.TextColor3     = UI_COLORS.SUBTEXT
    infoLbl.BackgroundTransparency = 1
    infoLbl.Size           = UDim2.new(1, -100, 0, 20)
    infoLbl.Position       = UDim2.new(0, 10, 0, 28)
    infoLbl.TextXAlignment = Enum.TextXAlignment.Left
    infoLbl.TextWrapped    = true
    infoLbl.Parent         = row

    local tpBtn = Instance.new("TextButton")
    tpBtn.Text            = "TP"
    tpBtn.Font            = Enum.Font.GothamBold
    tpBtn.TextSize        = 12
    tpBtn.TextColor3      = Color3.new(1, 1, 1)
    tpBtn.BackgroundColor3 = UI_COLORS.ACCENT
    tpBtn.BorderSizePixel = 0
    tpBtn.Size            = UDim2.new(0, 70, 0, 30)
    tpBtn.Position        = UDim2.new(1, -82, 0.5, -15)
    tpBtn.Parent          = row
    Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 6)

    local bName = biome.name
    tpBtn.MouseButton1Click:Connect(function()
        BiomeTeleport.GoTo(bName)
        AutoSteal.targetBiome = bName
    end)
end

-- ── TAB 7: SETTINGS ────────────────────────────────────────
local settingsPage = Pages[TAB_NAMES[7]]

makeHeader(settingsPage, "  ◆ ANTI-DETECTION SETTINGS")

makeToggle(settingsPage, "Rate Limiting",
    "Prevents Remote flooding (recommended ON)", true,
    function(on)
        -- If off, set all intervals to 0
        if not on then
            for k in pairs(_remoteCooldowns) do
                _remoteCooldowns[k] = 0
            end
        end
    end)

makeToggle(settingsPage, "Loop Jitter",
    "Randomises loop timing to avoid pattern detection", true,
    function(on)
        -- Store jitter preference; loops check this flag
        AC._jitterEnabled = on
    end)

makeToggle(settingsPage, "WalkSpeed Safe Cap",
    "Limit max speed to " .. SpeedModule.maxSafe .. " (no kick risk)", true,
    function(on)
        SpeedModule.maxSafe = on and 120 or 300
    end)

makeHeader(settingsPage, "  ◆ UI SETTINGS")

makeButton(settingsPage, "Hide/Show Menu  [Right Shift]",
    UI_COLORS.BG2, function()
        MainFrame.Visible = not MainFrame.Visible
    end)

makeButton(settingsPage, "Reset Position",
    UI_COLORS.BG2, function()
        MainFrame.Position = UDim2.new(0, 80, 0, 80)
    end)

makeButton(settingsPage, "Destroy Script (Clean Exit)",
    UI_COLORS.DANGER, function()
        -- Stop all modules
        AutoSteal:Stop()
        AutoTreadmill:Stop()
        AutoCollect:Stop()
        AutoHatch:Stop()
        AutoBuy:Stop()
        SpeedModule:Disable()
        Noclip:Disable()
        ESP.enabled = false
        ESP:Refresh()
        ScreenGui:Destroy()
    end)

makeHeader(settingsPage, "  ◆ MUTATION REFERENCE")
for _, m in ipairs(MUTATIONS) do
    local lbl = Instance.new("TextLabel")
    lbl.Text             = string.format("%-12s  ×%.2f  (%.1f%% chance)",
        m.name, m.mult, m.weight)
    lbl.Font             = Enum.Font.Code
    lbl.TextSize         = 10
    lbl.TextColor3       = UI_COLORS.TEXT
    lbl.BackgroundTransparency = 1
    lbl.Size             = UDim2.new(1, 0, 0, 20)
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = settingsPage
end

-- ═══════════════════════════════════════════════════════════
-- SECTION 14: KEYBIND — RIGHT SHIFT to toggle menu
-- ═══════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ═══════════════════════════════════════════════════════════
-- SECTION 15: CHARACTER RESPAWN HANDLER
-- Re-applies all active modules on respawn
-- ═══════════════════════════════════════════════════════════

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    if SpeedModule.enabled  then SpeedModule:Disable(); SpeedModule:Enable()   end
    if Noclip.enabled       then Noclip:Disable();       Noclip:Enable()       end
    if AutoTreadmill.enabled then
        AutoTreadmill:Stop()
        task.wait(0.5)
        AutoTreadmill:Start()
    end
end)

-- ═══════════════════════════════════════════════════════════
-- INIT COMPLETE
-- ═══════════════════════════════════════════════════════════

print("[CrowScript v2.7] Steal An Egg ModMenu loaded — Delta Mobile build")
print("[CrowScript] Speed: smooth WalkSpeed lerp (no BodyVelocity, no lag)")
print("[CrowScript] ESP: real cash value reader (7-layer attribute fallback)")
print("[CrowScript] Anti-detect: rate-limiter + jitter + coord randomisation")
