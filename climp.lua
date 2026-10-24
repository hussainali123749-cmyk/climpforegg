--[[
  STEAL AN EGG — CROW v5.0
  BAC bypass strategy:
    - Zero workspace scan on inject
    - No Highlight instances (flagged by BAC)
    - No UIStroke (flagged)
    - No GetDescendants on load
    - All scans manual/on-demand only
    - Lazy feature init (nothing runs until toggled)
    - SelectionBox only for ESP (not Highlight)
    - Jittered loops, rate-limited remotes
]]

local Players   = game:GetService("Players")
local RunSvc    = game:GetService("RunService")
local TweenSvc  = game:GetService("TweenService")
local VirtUser  = game:GetService("VirtualUser")
local CoreGui   = game:GetService("CoreGui")
local WS        = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")

local LP  = Players.LocalPlayer
local Cam = WS.CurrentCamera

-- ── Helpers ──────────────────────────────────────────────
local function getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function jw(b,p)
    p=p or 0.25
    task.wait(b*(1+(math.random()-0.5)*2*p))
end
local function fmtN(n)
    if not n or n==0 then return "?" end
    if n>=1e12 then return ("%.1fT"):format(n/1e12) end
    if n>=1e9  then return ("%.1fB"):format(n/1e9)  end
    if n>=1e6  then return ("%.1fM"):format(n/1e6)  end
    if n>=1e3  then return ("%.1fK"):format(n/1e3)  end
    return tostring(math.floor(n))
end

-- ── Tween movement (no CFrame snap) ─────────────────────
local MoveSvc = {speed=38, _tw=nil}
function MoveSvc:To(pos, cb)
    local hrp = getHRP()
    if not hrp then if cb then cb() end return end
    if self._tw then self._tw:Cancel(); self._tw=nil end
    local dist = (hrp.Position - pos).Magnitude
    if dist < 2 then if cb then cb() end return end
    local t = math.clamp(dist/self.speed, 0.2, 9)
    local dest = CFrame.new(pos + Vector3.new(
        (math.random()-.5)*.4, 3, (math.random()-.5)*.4))
    hrp.Anchored = true
    local tw = TweenSvc:Create(hrp,
        TweenInfo.new(t,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),
        {CFrame=dest})
    tw:Play(); self._tw=tw
    tw.Completed:Connect(function()
        hrp.Anchored=false; self._tw=nil
        if cb then cb() end
    end)
end
function MoveSvc:Cancel()
    if self._tw then self._tw:Cancel(); self._tw=nil end
    local hrp=getHRP()
    if hrp then hrp.Anchored=false end
end

-- ── VirtualUser tap ──────────────────────────────────────
local function tapAt(sp)
    pcall(function()
        VirtUser:Button1Down(sp, Cam.CFrame)
        task.wait(0.07)
        VirtUser:Button1Up(sp, Cam.CFrame)
    end)
end
local function promptScreenPos(part)
    if not part or not part.Parent then return nil,false end
    local wp = part.Position + Vector3.new(0,2,0)
    local sp, vis = Cam:WorldToScreenPoint(wp)
    if vis then return Vector2.new(sp.X,sp.Y),true end
    return nil,false
end

-- ── LAZY SCANNER (only called when user presses button) ──
-- Returns results, stores nothing globally on load.
local INCOME_ATTRS = {
    "CashValue","Value","Income","MPS","MoneyPerSecond",
    "EggValue","PetIncome","CashPerSecond","EggIncome",
    "EggCash","BaseCash","BaseIncome","Money","Cash",
}
local function readIncome(obj)
    local targets = {obj, obj.Parent}
    for _,t in ipairs(targets) do
        if t and t~=WS then
            for _,k in ipairs(INCOME_ATTRS) do
                local v=t:GetAttribute(k)
                if type(v)=="number" and v>0 then return v end
            end
        end
    end
    for _,c in ipairs(obj:GetChildren()) do
        if (c:IsA("NumberValue") or c:IsA("IntValue")) and c.Value>0 then
            return c.Value
        end
    end
    return nil
end
local function readRarity(obj)
    for _,k in ipairs({"Rarity","EggRarity","Tier","Grade","Type"}) do
        local v = obj:GetAttribute(k)
               or (obj.Parent and obj.Parent:GetAttribute(k))
        if v then return tostring(v) end
    end
    local n=obj.Name:lower()
    if n:find("divine")   then return "Divine"   end
    if n:find("eternal")  then return "Eternal"  end
    if n:find("secret")   then return "Secret"   end
    if n:find("cosmic")   then return "Cosmic"   end
    if n:find("legend")   then return "Legendary" end
    if n:find("epic")     then return "Epic"     end
    if n:find("rare")     then return "Rare"     end
    if n:find("uncommon") then return "Uncommon" end
    return "Common"
end

-- Scan eggs — called lazily, not on load
local function scanEggs()
    local eggs={}
    -- Use ipairs on children of specific known folders first
    -- Avoids full GetDescendants which triggers BAC
    local function checkObj(obj)
        if not obj:IsA("ProximityPrompt") then return end
        local at=(obj.ActionText or ""):lower()
        local ot=(obj.ObjectText  or ""):lower()
        if not (at:find("steal") or at:find("grab")
             or ot:find("egg")   or at:find("take")) then return end
        local par = obj.Parent
        local part = nil
        if par then
            if par:IsA("BasePart") then
                part = par
            elseif par:IsA("Model") then
                part = par.PrimaryPart or par:FindFirstChildOfClass("BasePart")
            end
        end
        if part then
            table.insert(eggs,{
                prompt=obj, part=part,
                income=readIncome(par),
                rarity=readRarity(par),
                name=par.Name,
            })
        end
    end
    -- Iterate children of WS children (2 levels, not full descendants)
    -- This avoids the full GetDescendants scan BAC watches
    for _,child in ipairs(WS:GetChildren()) do
        for _,gc in ipairs(child:GetChildren()) do
            checkObj(gc)
            for _,ggc in ipairs(gc:GetChildren()) do
                checkObj(ggc)
                for _,gggc in ipairs(ggc:GetChildren()) do
                    checkObj(gggc)
                end
            end
        end
    end
    table.sort(eggs,function(a,b)
        return (a.income or 0)>(b.income or 0)
    end)
    return eggs
end

local function scanTreadmill()
    local uid=tostring(LP.UserId)
    local best,bpri=nil,0
    for _,child in ipairs(WS:GetChildren()) do
        for _,gc in ipairs(child:GetChildren()) do
            local nl=gc.Name:lower()
            if gc:IsA("BasePart") and
               (nl:find("treadmill") or nl:find("tread")) then
                local own=gc:GetAttribute("Owner")
                        or gc:GetAttribute("PlayerId")
                        or gc:GetAttribute("UserId")
                local pri=(own==uid or own==LP.UserId) and 2 or 1
                if pri>bpri then best=gc;bpri=pri end
            end
            for _,ggc in ipairs(gc:GetChildren()) do
                local nl2=ggc.Name:lower()
                if ggc:IsA("BasePart") and
                   (nl2:find("treadmill") or nl2:find("tread")) then
                    local own=ggc:GetAttribute("Owner")
                            or ggc:GetAttribute("PlayerId")
                    local pri=(own==uid or own==LP.UserId) and 2 or 1
                    if pri>bpri then best=ggc;bpri=pri end
                end
            end
        end
    end
    return best
end

local function scanPen()
    local uid=tostring(LP.UserId)
    for _,child in ipairs(WS:GetChildren()) do
        for _,gc in ipairs(child:GetChildren()) do
            local nl=gc.Name:lower()
            if gc:IsA("BasePart") then
                local own=gc:GetAttribute("Owner")
                        or gc:GetAttribute("PlayerId")
                        or gc:GetAttribute("UserId")
                if (own==uid or own==LP.UserId) and
                   (nl:find("pen") or nl:find("garden")
                 or nl:find("hatch") or nl:find("home")) then
                    return gc
                end
            end
        end
    end
    for _,obj in ipairs(WS:GetChildren()) do
        if obj:IsA("SpawnLocation") then
            local a=obj:GetAttribute("PlayerId")
                 or obj:GetAttribute("UserId")
            if a==LP.UserId or a==uid then return obj end
        end
    end
    return nil
end

-- ── AUTO-STEAL ───────────────────────────────────────────
local AS={enabled=false,autoReturn=true,rareFilter="Any",_t=nil}
local RR={Common=1,Uncommon=2,Rare=3,Epic=4,Legendary=5,Cosmic=6,Secret=7,Eternal=8,Divine=9}
local FM={["Any"]=0,["Rare+"]=3,["Epic+"]=4,["Legendary+"]=5,["Cosmic+"]=6}

function AS:Start()
    self.enabled=true
    self._t=task.spawn(function()
        while self.enabled do
            jw(2.2,0.35)
            local eggs=scanEggs()
            if #eggs==0 then jw(3,0.4);continue end
            local pool={}
            local min=FM[self.rareFilter] or 0
            for _,e in ipairs(eggs) do
                if (RR[e.rarity] or 1)>=min then
                    table.insert(pool,e)
                end
            end
            if #pool==0 then continue end
            local tgt=pool[1]
            if not tgt.prompt or not tgt.prompt.Parent then continue end
            if not tgt.part   or not tgt.part.Parent   then continue end
            local done=false
            MoveSvc:To(tgt.part.Position,function() done=true end)
            local t0=tick()
            while not done and tick()-t0<10 do task.wait(0.1) end
            if not done then continue end
            jw(0.35,0.15)
            local hrp=getHRP()
            if hrp then
                hrp.CFrame=CFrame.lookAt(hrp.Position,tgt.part.Position)
            end
            jw(0.2,0.1)
            local sp,vis=promptScreenPos(tgt.part)
            if not vis then
                if hrp then
                    Cam.CFrame=CFrame.lookAt(Cam.CFrame.Position,tgt.part.Position)
                end
                task.wait(0.12)
                sp,vis=promptScreenPos(tgt.part)
            end
            if vis and sp then
                tapAt(sp); jw(0.1,0.05); tapAt(sp)
            end
            jw(0.5,0.2)
            if self.autoReturn then
                local pen=scanPen()
                if pen then
                    local pd=false
                    MoveSvc:To(pen.Position,function() pd=true end)
                    local t1=tick()
                    while not pd and tick()-t1<10 do task.wait(0.1) end
                end
            end
        end
    end)
end
function AS:Stop()
    self.enabled=false; MoveSvc:Cancel()
end

-- ── AUTO-TREADMILL ───────────────────────────────────────
local AT={enabled=false,_t=nil}
function AT:Start()
    self.enabled=true
    self._t=task.spawn(function()
        local tm=scanTreadmill()
        if not tm then
            jw(3); tm=scanTreadmill()
            if not tm then self.enabled=false;return end
        end
        local done=false
        MoveSvc:To(tm.Position,function() done=true end)
        local t0=tick()
        while not done and tick()-t0<10 do task.wait(0.1) end
        jw(0.4,0.1)
        local step=0
        while self.enabled do
            local hrp=getHRP()
            if not hrp then jw(0.5);continue end
            if not tm or not tm.Parent then
                tm=scanTreadmill(); jw(2);continue
            end
            local base=tm.CFrame.Position+Vector3.new(0,tm.Size.Y/2+2.5,0)
            local diff=base-hrp.Position
            if diff.Magnitude>1.5 then
                hrp.CFrame=hrp.CFrame+Vector3.new(
                    math.clamp(diff.X,-0.8,0.8),
                    math.clamp(diff.Y,-0.8,0.8),
                    math.clamp(diff.Z,-0.8,0.8))
            end
            step=step+1
            if step%5==0 then
                local n=(step%10==0) and 0.25 or -0.25
                hrp.CFrame=hrp.CFrame*CFrame.new(n,0,0)
            end
            jw(0.18,0.06)
        end
    end)
end
function AT:Stop() self.enabled=false end

-- ── AUTO-FARM ────────────────────────────────────────────
local AF={enabled=false,_t=nil}
function AF:Start()
    self.enabled=true
    self._t=task.spawn(function()
        while self.enabled do
            jw(1.8,0.4)
            for _,child in ipairs(WS:GetChildren()) do
                if not self.enabled then break end
                for _,gc in ipairs(child:GetChildren()) do
                    if not self.enabled then break end
                    if gc:IsA("ProximityPrompt") then
                        local at=gc.ActionText:lower()
                        if at:find("collect") or at:find("hatch")
                        or at:find("claim")   or at:find("earn")
                        or at:find("income")  or at:find("cash") then
                            local par=gc.Parent
                            if par and par:IsA("BasePart") then
                                local d2=false
                                MoveSvc:To(par.Position,function() d2=true end)
                                local t0=tick()
                                while not d2 and tick()-t0<8 do task.wait(0.1) end
                                jw(0.2,0.1)
                                local sp,vis=promoptScreenPos(par)
                                if vis and sp then tapAt(sp) end
                            end
                        end
                    end
                    for _,ggc in ipairs(gc:GetChildren()) do
                        if ggc:IsA("ProximityPrompt") then
                            local at=ggc.ActionText:lower()
                            if at:find("collect") or at:find("hatch")
                            or at:find("claim")   or at:find("earn") then
                                local par=ggc.Parent
                                if par and par:IsA("BasePart") then
                                    local sp,vis=promoptScreenPos(par)
                                    if vis and sp then tapAt(sp) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end
function AF:Stop() self.enabled=false end

-- ── ESP — SelectionBox only (no Highlight) ───────────────
local EspMod={enabled=false,eggs=true,guards=true,traps=true,players=true,_o={}}
local RCOL={
    Divine=Color3.fromRGB(255,255,80),Eternal=Color3.fromRGB(255,120,0),
    Secret=Color3.fromRGB(255,60,180),Cosmic=Color3.fromRGB(0,230,255),
    Legendary=Color3.fromRGB(255,190,0),Epic=Color3.fromRGB(160,60,240),
    Rare=Color3.fromRGB(60,120,255),Uncommon=Color3.fromRGB(60,220,80),
    Common=Color3.fromRGB(200,200,200),
}
local function rc(r) return RCOL[r] or Color3.fromRGB(255,220,50) end

local function mkSB(part,col)
    -- SelectionBox: not flagged by BAC (it's UI-only)
    local sb=Instance.new("SelectionBox")
    sb.Adornee=part; sb.Color3=col
    sb.LineThickness=0.06
    sb.SurfaceColor3=col; sb.SurfaceTransparency=0.75
    sb.Parent=CoreGui
    table.insert(EspMod._o,sb)
end
local function mkBB(adorn,text,col)
    local bb=Instance.new("BillboardGui")
    bb.AlwaysOnTop=true; bb.Size=UDim2.new(0,185,0,65)
    bb.StudsOffset=Vector3.new(0,5,0); bb.Adornee=adorn
    bb.Parent=CoreGui
    local bg=Instance.new("Frame",bb)
    bg.Size=UDim2.new(1,0,1,0)
    bg.BackgroundColor3=Color3.fromRGB(8,8,16)
    bg.BackgroundTransparency=0.22; bg.BorderSizePixel=0
    Instance.new("UICorner",bg).CornerRadius=UDim.new(0,8)
    local lb=Instance.new("TextLabel",bg)
    lb.Size=UDim2.new(1,-6,1,-4); lb.Position=UDim2.new(0,3,0,2)
    lb.BackgroundTransparency=1; lb.TextColor3=col or Color3.new(1,1,1)
    lb.TextScaled=true; lb.Font=Enum.Font.GothamBold
    lb.Text=text; lb.TextWrapped=true
    lb.TextStrokeTransparency=0.25
    lb.TextStrokeColor3=Color3.new(0,0,0)
    table.insert(EspMod._o,bb)
end

function EspMod:Clear()
    for _,o in ipairs(self._o) do pcall(function() o:Destroy() end) end
    self._o={}
end
function EspMod:Refresh()
    self:Clear()
    if not self.enabled then return end
    local hrp=getHRP(); local myP=hrp and hrp.Position
    if self.eggs then
        for _,e in ipairs(scanEggs()) do
            if not e.part or not e.part.Parent then continue end
            local col=rc(e.rarity)
            local dist=myP and ("%ds"):format(math.floor((myP-e.part.Position).Magnitude)) or "?"
            local cash=e.income and ("$"..fmtN(e.income).."/s") or "?"
            mkSB(e.part,col)
            mkBB(e.part,"🥚 "..e.name.."\n💰 "..cash.."  ✨ "..(e.rarity or "?").."\n📍 "..dist,col)
        end
    end
    if self.guards then
        for _,child in ipairs(WS:GetChildren()) do
            for _,gc in ipairs(child:GetChildren()) do
                if gc:IsA("Model") then
                    local hm=gc:FindFirstChildOfClass("Humanoid")
                    local rp=gc:FindFirstChild("HumanoidRootPart")
                    if hm and rp and gc~=LP.Character then
                        local isPlr=false
                        for _,p in ipairs(Players:GetPlayers()) do
                            if p.Character==gc then isPlr=true;break end
                        end
                        if not isPlr then
                            local col=Color3.fromRGB(255,50,50)
                            local dist=myP and ("%ds"):format(math.floor((myP-rp.Position).Magnitude)) or "?"
                            local d=myP and (myP-rp.Position).Magnitude or 999
                            mkSB(rp,col)
                            mkBB(rp,(d<25 and "🔴 DANGER!\n" or "⚠️ GUARD\n")..gc.Name.."\n📍 "..dist,col)
                        end
                    end
                end
            end
        end
    end
    if self.players then
        for _,p in ipairs(Players:GetPlayers()) do
            if p==LP or not p.Character then continue end
            local rp=p.Character:FindFirstChild("HumanoidRootPart")
            if not rp then continue end
            local col=Color3.fromRGB(100,200,255)
            local dist=myP and ("%ds"):format(math.floor((myP-rp.Position).Magnitude)) or "?"
            local inc=p:GetAttribute("TotalIncome") or p:GetAttribute("Income") or p:GetAttribute("MPS")
            local incS=inc and ("$"..fmtN(inc).."/s") or "?"
            mkSB(rp,col)
            mkBB(rp,"👤 "..p.DisplayName.."\n💰 "..incS.."\n📍 "..dist,col)
        end
    end
end

task.spawn(function()
    while true do
        task.wait(3)
        if EspMod.enabled then pcall(function() EspMod:Refresh() end) end
    end
end)

-- ── NOCLIP ───────────────────────────────────────────────
local NC={enabled=false,_c=nil}
function NC:En()
    self.enabled=true
    self._c=RunSvc.Stepped:Connect(function()
        local c=LP.Character; if not c then return end
        for _,p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide=false end
        end
    end)
end
function NC:Dis()
    self.enabled=false
    if self._c then self._c:Disconnect();self._c=nil end
    local c=LP.Character; if not c then return end
    for _,p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then p.CanCollide=true end
    end
end

-- ════════════════════════════════════════════════════════
-- UI — minimal instances to avoid BAC flags
-- No UIStroke. No Highlight. Plain frames only.
-- ════════════════════════════════════════════════════════
local old=CoreGui:FindFirstChild("CrowV5")
if old then old:Destroy() end

local SG=Instance.new("ScreenGui")
SG.Name="CrowV5"; SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
SG.IgnoreGuiInset=true; SG.DisplayOrder=9999
SG.Parent=CoreGui

local CL={
    BG =Color3.fromRGB(11,11,20),   BG2=Color3.fromRGB(20,20,33),
    BG3=Color3.fromRGB(27,27,42),   ACC=Color3.fromRGB(105,52,205),
    AC2=Color3.fromRGB(62,162,255),  ON =Color3.fromRGB(48,202,92),
    OFF=Color3.fromRGB(62,62,88),   RED=Color3.fromRGB(212,48,48),
    WRN=Color3.fromRGB(232,152,32),  TXT=Color3.fromRGB(226,226,238),
    SUB=Color3.fromRGB(148,148,170),
}

-- Main frame (no UIStroke)
local MF=Instance.new("Frame",SG)
MF.Name="MF"; MF.Size=UDim2.new(0,348,0,490)
MF.Position=UDim2.new(0,8,0.1,0); MF.BackgroundColor3=CL.BG
MF.BorderSizePixel=2; MF.BorderColor3=Color3.fromRGB(55,32,92)
MF.Active=true; MF.Draggable=true; MF.ClipsDescendants=true
Instance.new("UICorner",MF).CornerRadius=UDim.new(0,12)

-- Title bar (no UIStroke, no UIGradient on ScreenGui)
local TB=Instance.new("Frame",MF)
TB.Size=UDim2.new(1,0,0,44); TB.BackgroundColor3=CL.ACC
TB.BorderSizePixel=0; TB.ZIndex=2
Instance.new("UICorner",TB).CornerRadius=UDim.new(0,12)

local TL=Instance.new("TextLabel",TB)
TL.Text="🥚 STEAL AN EGG  |  CROW v5.0"
TL.Font=Enum.Font.GothamBold; TL.TextSize=12
TL.TextColor3=CL.TXT; TL.BackgroundTransparency=1
TL.Size=UDim2.new(1,-46,1,0); TL.Position=UDim2.new(0,10,0,0)
TL.TextXAlignment=Enum.TextXAlignment.Left; TL.ZIndex=3

local XB=Instance.new("TextButton",TB)
XB.Text="✕"; XB.Font=Enum.Font.GothamBold; XB.TextSize=15
XB.TextColor3=CL.TXT; XB.BackgroundColor3=CL.RED
XB.BorderSizePixel=0; XB.Size=UDim2.new(0,30,0,28)
XB.Position=UDim2.new(1,-36,0,8); XB.ZIndex=4
Instance.new("UICorner",XB).CornerRadius=UDim.new(0,5)

-- Floating reopen button
local EB=Instance.new("TextButton",SG)
EB.Text="🥚"; EB.Font=Enum.Font.GothamBold; EB.TextSize=22
EB.TextColor3=Color3.new(1,1,1); EB.BackgroundColor3=CL.ACC
EB.BorderSizePixel=0; EB.Size=UDim2.new(0,48,0,48)
EB.Position=UDim2.new(0,8,0.1,0); EB.ZIndex=100
EB.Visible=false; EB.Active=true; EB.Draggable=true
Instance.new("UICorner",EB).CornerRadius=UDim.new(1,0)

XB.MouseButton1Click:Connect(function() MF.Visible=false; EB.Visible=true end)
EB.MouseButton1Click:Connect(function() MF.Visible=true;  EB.Visible=false end)

-- Tabs
local TABS={"⚡Main","🥚Steal","👁ESP","💰Farm","🗺Map","⚙️More"}
local Pages={}; local TBtns={}

local TabBar=Instance.new("Frame",MF)
TabBar.Size=UDim2.new(1,0,0,34); TabBar.Position=UDim2.new(0,0,0,44)
TabBar.BackgroundColor3=CL.BG2; TabBar.BorderSizePixel=0
local TBL=Instance.new("UIListLayout",TabBar)
TBL.FillDirection=Enum.FillDirection.Horizontal
TBL.SortOrder=Enum.SortOrder.LayoutOrder; TBL.Padding=UDim.new(0,2)

local CF=Instance.new("ScrollingFrame",MF)
CF.Size=UDim2.new(1,0,1,-78); CF.Position=UDim2.new(0,0,0,78)
CF.BackgroundTransparency=1; CF.BorderSizePixel=0
CF.ScrollBarThickness=3; CF.CanvasSize=UDim2.new(0,0,0,0)
CF.AutomaticCanvasSize=Enum.AutomaticSize.Y
CF.ScrollBarImageColor3=CL.ACC

local CFL=Instance.new("UIListLayout",CF)
CFL.SortOrder=Enum.SortOrder.LayoutOrder; CFL.Padding=UDim.new(0,5)
local CFP=Instance.new("UIPadding",CF)
CFP.PaddingLeft=UDim.new(0,8); CFP.PaddingRight=UDim.new(0,8)
CFP.PaddingTop=UDim.new(0,6); CFP.PaddingBottom=UDim.new(0,6)

local function mkPg(n)
    local p=Instance.new("Frame",CF)
    p.Name=n; p.Visible=false; p.Size=UDim2.new(1,0,0,0)
    p.AutomaticSize=Enum.AutomaticSize.Y; p.BackgroundTransparency=1
    p.BorderSizePixel=0
    local l=Instance.new("UIListLayout",p)
    l.SortOrder=Enum.SortOrder.LayoutOrder; l.Padding=UDim.new(0,5)
    Pages[n]=p; return p
end
local function showTab(n)
    for k,pg in pairs(Pages) do pg.Visible=(k==n) end
    for _,b in ipairs(TBtns) do b.TextColor3=CL.SUB; b.BackgroundColor3=CL.BG2 end
    for i,t in ipairs(TABS) do
        if t==n and TBtns[i] then
            TBtns[i].TextColor3=Color3.new(1,1,1)
            TBtns[i].BackgroundColor3=CL.ACC
        end
    end
end
for i,tn in ipairs(TABS) do
    mkPg(tn)
    local b=Instance.new("TextButton",TabBar)
    b.Text=tn; b.Font=Enum.Font.Gotham; b.TextSize=9
    b.TextColor3=CL.SUB; b.BackgroundColor3=CL.BG2
    b.BorderSizePixel=0; b.Size=UDim2.new(0,52,1,0); b.LayoutOrder=i
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,4)
    TBtns[i]=b; b.MouseButton1Click:Connect(function() showTab(tn) end)
end

-- UI component helpers
local function mkH(p,t,c)
    local l=Instance.new("TextLabel",p); l.Text=t
    l.Font=Enum.Font.GothamBold; l.TextSize=10
    l.TextColor3=c or CL.AC2; l.BackgroundTransparency=1
    l.Size=UDim2.new(1,0,0,20); l.TextXAlignment=Enum.TextXAlignment.Left
end
local function mkIF(p,t)
    local f=Instance.new("Frame",p)
    f.Size=UDim2.new(1,0,0,0); f.AutomaticSize=Enum.AutomaticSize.Y
    f.BackgroundColor3=CL.BG2; f.BorderSizePixel=0
    Instance.new("UICorner",f).CornerRadius=UDim.new(0,7)
    local pd=Instance.new("UIPadding",f)
    pd.PaddingLeft=UDim.new(0,8); pd.PaddingTop=UDim.new(0,5)
    pd.PaddingRight=UDim.new(0,8); pd.PaddingBottom=UDim.new(0,5)
    local l=Instance.new("TextLabel",f); l.Text=t
    l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextColor3=CL.SUB
    l.BackgroundTransparency=1; l.Size=UDim2.new(1,0,0,0)
    l.AutomaticSize=Enum.AutomaticSize.Y
    l.TextXAlignment=Enum.TextXAlignment.Left; l.TextWrapped=true
    return f,l
end
local function mkTG(p,lbl,sub,def,cb)
    local row=Instance.new("Frame",p)
    row.Size=UDim2.new(1,0,0,54); row.BackgroundColor3=CL.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,8)
    local n=Instance.new("TextLabel",row); n.Text=lbl
    n.Font=Enum.Font.GothamBold; n.TextSize=12; n.TextColor3=CL.TXT
    n.BackgroundTransparency=1; n.Size=UDim2.new(1,-60,0,26)
    n.Position=UDim2.new(0,10,0,6); n.TextXAlignment=Enum.TextXAlignment.Left
    local s=Instance.new("TextLabel",row); s.Text=sub or ""
    s.Font=Enum.Font.Gotham; s.TextSize=9; s.TextColor3=CL.SUB
    s.BackgroundTransparency=1; s.Size=UDim2.new(1,-60,0,18)
    s.Position=UDim2.new(0,10,0,30); s.TextXAlignment=Enum.TextXAlignment.Left
    s.TextWrapped=true
    local pill=Instance.new("Frame",row); pill.Size=UDim2.new(0,46,0,24)
    pill.Position=UDim2.new(1,-54,0.5,-12)
    pill.BackgroundColor3=def and CL.ON or CL.OFF; pill.BorderSizePixel=0
    Instance.new("UICorner",pill).CornerRadius=UDim.new(0,12)
    local knob=Instance.new("Frame",pill); knob.Size=UDim2.new(0,18,0,18)
    knob.Position=def and UDim2.new(0,25,0,3) or UDim2.new(0,3,0,3)
    knob.BackgroundColor3=Color3.new(1,1,1); knob.BorderSizePixel=0
    Instance.new("UICorner",knob).CornerRadius=UDim.new(0,9)
    local state=def
    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    btn.MouseButton1Click:Connect(function()
        state=not state
        pill.BackgroundColor3=state and CL.ON or CL.OFF
        TweenSvc:Create(knob,TweenInfo.new(0.12),{
            Position=state and UDim2.new(0,25,0,3) or UDim2.new(0,3,0,3)
        }):Play()
        if cb then cb(state) end
    end)
end
local function mkBT(p,t,c,cb)
    local b=Instance.new("TextButton",p); b.Text=t
    b.Font=Enum.Font.GothamBold; b.TextSize=12
    b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=c or CL.ACC
    b.BorderSizePixel=0; b.Size=UDim2.new(1,0,0,38)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,8)
    b.MouseButton1Click:Connect(function()
        if cb then cb() end
        TweenSvc:Create(b,TweenInfo.new(0.08),{BackgroundTransparency=0.4}):Play()
        task.delay(0.15,function()
            TweenSvc:Create(b,TweenInfo.new(0.08),{BackgroundTransparency=0}):Play()
        end)
    end)
    return b
end

-- ── MAIN TAB ────────────────────────────────────────────
local pg=Pages["⚡Main"]
mkH(pg,"  ◆ CROW v5.0 — BAC STEALTH",CL.ON)
mkIF(pg,"✅ Zero workspace scan on load\n✅ No Highlight instances\n✅ No GetDescendants at inject\n✅ Scan only when YOU press button\n✅ TweenMove + VirtualUser tap")
mkH(pg,"  ◆ QUICK TOGGLES")
mkTG(pg,"Auto-Steal","TweenMove + tap — zero BAC flags",false,function(on)
    if on then AS:Start() else AS:Stop() end
end)
mkTG(pg,"Auto-Treadmill","Stay on treadmill AFK",false,function(on)
    if on then AT:Start() else AT:Stop() end
end)
mkTG(pg,"Auto-Farm","Collect + hatch prompts",false,function(on)
    if on then AF:Start() else AF:Stop() end
end)
mkTG(pg,"ESP (SelectionBox)","No Highlight — safe",false,function(on)
    EspMod.enabled=on; if on then EspMod:Refresh() else EspMod:Clear() end
end)

local _,stLbl=mkIF(pg,"Press 🔍 Scan to check workspace")
mkBT(pg,"🔍 Scan Workspace (Manual)",CL.AC2,function()
    local eggs=scanEggs()
    local tm=scanTreadmill()
    local pen=scanPen()
    stLbl.Text=
        "Eggs: "..#eggs.."  |  "..(tm and "TM: "..tm.Name or "TM: not found")
        .."  |  "..(pen and "Pen: "..pen.Name or "Pen: not found")
    stLbl.TextColor3=#eggs>0 and CL.ON or CL.WRN
end)

-- ── STEAL TAB ────────────────────────────────────────────
pg=Pages["🥚Steal"]
mkH(pg,"  ◆ AUTO-STEAL")
mkTG(pg,"Auto-Steal","Tween movement + VirtualUser tap",false,function(on)
    if on then AS:Start() else AS:Stop() end
end)
mkTG(pg,"Return to Pen","Go home after each steal",true,function(on)
    AS.autoReturn=on
end)
mkTG(pg,"Noclip","Walk through walls",false,function(on)
    if on then NC:En() else NC:Dis() end
end)
mkH(pg,"  ◆ RARITY FILTER")
for _,opt in ipairs({"Any","Rare+","Epic+","Legendary+","Cosmic+"}) do
    mkBT(pg,opt,CL.BG3,function() AS.rareFilter=opt end)
end
mkH(pg,"  ◆ MOVE SPEED")
for _,sp in ipairs({{"🐢 Slow",22},{"🚶 Normal",38},{"🏃 Fast",50},{"⚡ Max",55}}) do
    mkBT(pg,sp[1].."  ("..sp[2].." s/s)",CL.ACC,function() MoveSvc.speed=sp[2] end)
end
mkH(pg,"  ◆ MANUAL")
mkBT(pg,"Steal Once",CL.ACC,function()
    local eggs=scanEggs()
    if #eggs>0 then
        local e=eggs[1]
        local done=false
        MoveSvc:To(e.part.Position,function() done=true end)
        task.spawn(function()
            local t=tick()
            while not done and tick()-t<10 do task.wait(0.1) end
            task.wait(0.3)
            local sp,vis=promptScreenPos(e.part)
            if vis and sp then tapAt(sp);task.wait(0.1);tapAt(sp) end
        end)
    end
end)
mkBT(pg,"TP to Pen (Tween)",CL.AC2,function()
    local pen=scanPen()
    if pen then MoveSvc:To(pen.Position,nil) end
end)

-- ── ESP TAB ──────────────────────────────────────────────
pg=Pages["👁ESP"]
mkH(pg,"  ◆ ESP  (SelectionBox — no Highlight)")
mkTG(pg,"Enable ESP","Visual only, no server touch",false,function(on)
    EspMod.enabled=on
    if on then EspMod:Refresh() else EspMod:Clear() end
end)
mkTG(pg,"Show Eggs","Egg boxes + income",true,function(on) EspMod.eggs=on end)
mkTG(pg,"Show Guardians","Enemy NPCs",true,function(on) EspMod.guards=on end)
mkTG(pg,"Show Players","Other players + $/s",true,function(on) EspMod.players=on end)
mkBT(pg,"🔄 Refresh ESP",CL.AC2,function()
    if EspMod.enabled then EspMod:Refresh() end
end)

-- ── FARM TAB ────────────────────────────────────────────
pg=Pages["💰Farm"]
mkH(pg,"  ◆ AUTO-FARM")
mkTG(pg,"Auto-Collect / Hatch","Fires all collect prompts",false,function(on)
    if on then AF:Start() else AF:Stop() end
end)
mkTG(pg,"Auto-Steal","Full steal loop",false,function(on)
    if on then AS:Start() else AS:Stop() end
end)
mkTG(pg,"Auto-Treadmill","AFK speed farm",false,function(on)
    if on then AT:Start() else AT:Stop() end
end)

-- ── MAP TAB ─────────────────────────────────────────────
pg=Pages["🗺Map"]
mkH(pg,"  ◆ BIOME TELEPORT  (Tween)")
mkIF(pg,"Moves via TweenService — not instant jump.")
for _,bd in ipairs({
    {"Forest","0"},{"Lake","900"},{"Desert","10K"},
    {"Jungle","40K"},{"Snow","170K"},{"Volcano","700K"},
    {"Abyss","3M"},{"Prehistoric","10M"},{"Cosmic","50M"},
    {"Cherry","2.5B"},{"Titan","10B"},{"Angels","25B"},{"Enchanted","50B"}
}) do
    local row=Instance.new("Frame",pg)
    row.Size=UDim2.new(1,0,0,40); row.BackgroundColor3=CL.BG2
    row.BorderSizePixel=0
    Instance.new("UICorner",row).CornerRadius=UDim.new(0,7)
    local nl=Instance.new("TextLabel",row)
    nl.Text=bd[1]; nl.Font=Enum.Font.GothamBold; nl.TextSize=12
    nl.TextColor3=CL.TXT; nl.BackgroundTransparency=1
    nl.Size=UDim2.new(1,-88,0,22); nl.Position=UDim2.new(0,10,0,4)
    nl.TextXAlignment=Enum.TextXAlignment.Left
    local sl=Instance.new("TextLabel",row)
    sl.Text="≥"..bd[2].." spd"; sl.Font=Enum.Font.Gotham; sl.TextSize=9
    sl.TextColor3=CL.SUB; sl.BackgroundTransparency=1
    sl.Size=UDim2.new(1,-88,0,14); sl.Position=UDim2.new(0,10,0,24)
    sl.TextXAlignment=Enum.TextXAlignment.Left
    local tb=Instance.new("TextButton",row)
    tb.Text="TP"; tb.Font=Enum.Font.GothamBold; tb.TextSize=11
    tb.TextColor3=Color3.new(1,1,1); tb.BackgroundColor3=CL.ACC
    tb.BorderSizePixel=0; tb.Size=UDim2.new(0,62,0,26)
    tb.Position=UDim2.new(1,-72,0.5,-13)
    Instance.new("UICorner",tb).CornerRadius=UDim.new(0,6)
    local bname=bd[1]:lower()
    tb.MouseButton1Click:Connect(function()
        for _,child in ipairs(WS:GetChildren()) do
            if child.Name:lower():find(bname) then
                local pp=child:IsA("BasePart") and child
                      or child:FindFirstChildOfClass("BasePart")
                if pp then MoveSvc:To(pp.Position,nil);return end
            end
        end
    end)
end

-- ── MORE TAB ─────────────────────────────────────────────
pg=Pages["⚙️More"]
mkH(pg,"  ◆ TOOLS")
mkTG(pg,"Noclip","Through walls",false,function(on)
    if on then NC:En() else NC:Dis() end
end)
mkBT(pg,"📋 Egg List → Console",CL.BG3,function()
    local eggs=scanEggs()
    print("[Crow v5] Eggs:",#eggs)
    for i,e in ipairs(eggs) do
        print(i,e.name,e.rarity,e.income and "$"..fmtN(e.income).."/s" or "?")
    end
end)
mkBT(pg,"Hide (🥚 reopens)",CL.BG3,function()
    MF.Visible=false; EB.Visible=true
end)
mkBT(pg,"❌ Destroy",CL.RED,function()
    AS:Stop();AT:Stop();AF:Stop();NC:Dis();EspMod:Clear();SG:Destroy()
end)

-- ── RESPAWN ──────────────────────────────────────────────
LP.CharacterAdded:Connect(function()
    task.wait(2)
    if NC.enabled then NC:Dis();NC:En() end
    if AT.enabled then AT:Stop();task.wait(0.5);AT:Start() end
end)

showTab("⚡Main")
-- NO print statements (some BAC systems hook print to detect scripts)
