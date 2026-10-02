local ScriptURL = "https://raw.githubusercontent.com/larpsent/6larping7-hub/refs/heads/main/cs.lua"

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local RS     = game:GetService("ReplicatedStorage")
local player = game.Players.LocalPlayer

-- ─── Remotes ──────────────────────────────────────────────────────────────────
local ClickEvent   = RS.Events.Click
local HatchFunc    = RS.Functions.Hatch   -- RemoteFunction, InvokeServer

-- ─── State ────────────────────────────────────────────────────────────────────
local AutoClick   = false
local AutoRebirth = false
local AutoHatch   = false
local FastHatch   = false
local AutoFarm    = false
local SelectedEgg = "Farm"
local HatchMode   = 3          -- numeric, not string
local RebirthAt   = 1
local ClickDelay  = 0
local SelectedTier = "1 Rebirth"

-- ─── Number parser ────────────────────────────────────────────────────────────
local suffixMap = {K=1e3,M=1e6,B=1e9,T=1e12,Qd=1e15,Qn=1e18,Sx=1e21,Sp=1e24}
local function ParseNumber(str)
    if not str then return 0 end
    str = tostring(str):gsub(",",""):gsub(" ","")
    local plain = tonumber(str)
    if plain then return plain end
    for s, m in pairs(suffixMap) do
        local n = str:match("^([%d%.]+)"..s.."$")
        if n then return tonumber(n)*m end
    end
    return 0
end

-- ─── Rebirth tier loader ──────────────────────────────────────────────────────
-- tries three sources in order:
-- 1. RS.Modules.RebirthTiers module
-- 2. RS.Modules.RebirthCost module
-- 3. PlayerGui rebirth UI TextLabels
-- 4. hard fallback
local TierNames         = {}
local RebirthTierValues = {}

local function LoadTiers()
    TierNames         = {}
    RebirthTierValues = {}

    -- source 1 + 2: try known module names
    local moduleNames = {"RebirthTiers", "RebirthCost", "Rebirths", "RebirthConfig"}
    for _, modName in ipairs(moduleNames) do
        local ok, mod = pcall(function()
            return require(RS.Modules:FindFirstChild(modName))
        end)
        if ok and type(mod) == "table" then
            local counts = {}
            for k, _ in pairs(mod) do
                if type(k) == "number" and k > 0 then
                    table.insert(counts, k)
                end
            end
            if #counts > 0 then
                table.sort(counts)
                for _, count in ipairs(counts) do
                    local name
                    if count >= 1e6 then
                        name = string.format("%.0fM Rebirths", count/1e6)
                    elseif count >= 1e3 then
                        name = string.format("%.0fK Rebirths", count/1e3)
                    else
                        name = count .. (count == 1 and " Rebirth" or " Rebirths")
                    end
                    table.insert(TierNames, name)
                    RebirthTierValues[name] = count
                end
                return true, modName
            end
        end
    end

    -- source 3: scrape PlayerGui rebirth UI
    local ok2, frame = pcall(function()
        -- try common paths
        local gui = player.PlayerGui
        return gui:FindFirstChild("Rebirth", true)
            or gui:FindFirstChild("Rebirths", true)
            or gui:FindFirstChild("RebirthGui", true)
    end)
    if ok2 and frame then
        local seen = {}
        for _, child in ipairs(frame:GetDescendants()) do
            if child:IsA("TextLabel") then
                local t = child.Text or ""
                local num, suf = t:match("^([%d%.]+)([KMBkm]?)%s*[Rr]ebirth")
                if num and not seen[num..suf] then
                    seen[num..suf] = true
                    local val = tonumber(num) or 0
                    suf = suf:upper()
                    if suf == "K" then val = val * 1e3
                    elseif suf == "M" then val = val * 1e6
                    elseif suf == "B" then val = val * 1e9 end
                    val = math.floor(val)
                    if val > 0 then
                        local name = val >= 1e6 and string.format("%.0fM Rebirths", val/1e6)
                            or val >= 1e3 and string.format("%.0fK Rebirths", val/1e3)
                            or val .. (val == 1 and " Rebirth" or " Rebirths")
                        if not RebirthTierValues[name] then
                            table.insert(TierNames, name)
                            RebirthTierValues[name] = val
                        end
                    end
                end
            end
        end
        table.sort(TierNames, function(a,b)
            return (RebirthTierValues[a] or 0) < (RebirthTierValues[b] or 0)
        end)
        if #TierNames > 0 then return true, "UI scrape" end
    end

    -- source 4: hard fallback
    local fallback = {
        {1,"1 Rebirth"},{5,"5 Rebirths"},{10,"10 Rebirths"},
        {25,"25 Rebirths"},{50,"50 Rebirths"},{75,"75 Rebirths"},
        {100,"100 Rebirths"},{250,"250 Rebirths"},{500,"500 Rebirths"},
        {750,"750 Rebirths"},{1000,"1K Rebirths"},{2500,"2.5K Rebirths"},
        {5000,"5K Rebirths"},{7500,"7.5K Rebirths"},{10000,"10K Rebirths"},
        {25000,"25K Rebirths"},{50000,"50K Rebirths"},{75000,"75K Rebirths"},
        {100000,"100K Rebirths"},{250000,"250K Rebirths"},{500000,"500K Rebirths"},
    }
    for _, pair in ipairs(fallback) do
        table.insert(TierNames, pair[2])
        RebirthTierValues[pair[2]] = pair[1]
    end
    return false, "fallback"
end

local tierOk, tierSource = LoadTiers()
SelectedTier = TierNames[1] or "1 Rebirth"
RebirthAt    = RebirthTierValues[SelectedTier] or 1

-- ─── Rebirth remote finder ────────────────────────────────────────────────────
-- scans RS for a Rebirth remote since we don't know the exact path yet
local RebirthEvent = nil
local RebirthFunc  = nil

local function FindRebirthRemote()
    -- common paths to check
    local paths = {
        {"Events", "Rebirth"},
        {"Events", "Rebirths"},
        {"Remotes", "Rebirth"},
        {"Functions", "Rebirth"},
    }
    for _, path in ipairs(paths) do
        local ok, remote = pcall(function()
            local folder = RS:FindFirstChild(path[1])
            return folder and folder:FindFirstChild(path[2])
        end)
        if ok and remote then
            if remote:IsA("RemoteEvent") then
                RebirthEvent = remote
                return "RemoteEvent", remote:GetFullName()
            elseif remote:IsA("RemoteFunction") then
                RebirthFunc = remote
                return "RemoteFunction", remote:GetFullName()
            end
        end
    end
    -- deep scan as last resort
    for _, desc in ipairs(RS:GetDescendants()) do
        if desc.Name:lower():find("rebirth") then
            if desc:IsA("RemoteEvent") then
                RebirthEvent = desc
                return "RemoteEvent", desc:GetFullName()
            elseif desc:IsA("RemoteFunction") then
                RebirthFunc = desc
                return "RemoteFunction", desc:GetFullName()
            end
        end
    end
    return nil, "not found"
end

local rebirthRemoteType, rebirthRemotePath = FindRebirthRemote()

local function FireRebirth(amount)
    if RebirthEvent then
        pcall(function() RebirthEvent:FireServer(amount) end)
    elseif RebirthFunc then
        pcall(function() RebirthFunc:InvokeServer(amount) end)
    end
end

-- ─── Egg list ─────────────────────────────────────────────────────────────────
local function GetEggList()
    local eggs = {}
    local ok, holders = pcall(function() return workspace.Scripted.EggHolders end)
    if ok and holders then
        for _, egg in ipairs(holders:GetChildren()) do
            table.insert(eggs, egg.Name)
        end
    end
    if #eggs == 0 then eggs = {"Farm"} end
    return eggs
end
local eggList = GetEggList()

-- default SelectedEgg to first real egg
SelectedEgg = eggList[1] or "Farm"

-- ─── Stats ────────────────────────────────────────────────────────────────────
local function getStat(name)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return nil end
    local s = ls:FindFirstChild(name)
    return s and tostring(s.Value) or nil
end

local function getRebirths()
    -- try common leaderstats names
    local names = {"🌀 Rebirths","Rebirths","Rebirth","💫 Rebirths"}
    for _, n in ipairs(names) do
        local v = getStat(n)
        if v then return ParseNumber(v) end
    end
    return 0
end

local function getLeaderstatDisplay()
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return {} end
    local out = {}
    for _, v in ipairs(ls:GetChildren()) do
        table.insert(out, {name=v.Name, value=tostring(v.Value)})
    end
    return out
end

-- ─── Window ───────────────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name            = "6larping7 Hub",
    LoadingTitle    = "6larping7 Hub",
    LoadingSubtitle = "by apple sauce",
    Theme           = "Default",
    KeySystem       = true,
    KeySettings     = {
        Title    = "6larping7 Hub",
        Subtitle = "Keybind",
        Note     = "Left Control to toggle UI",
        Key      = {"LeftControl"},
    },
    DisableRayfieldPrompts = true,
    DisableBuildWarnings   = true,
})

pcall(function() Rayfield.Keybind = Enum.KeyCode.LeftControl end)

-- ─── Main Tab ─────────────────────────────────────────────────────────────────
local MainTab = Window:CreateTab("Main", 4483362458)

-- Auto Farm
MainTab:CreateSection("Auto Farm")
MainTab:CreateToggle({
    Name = "Auto Farm  (Click + Rebirth)",
    CurrentValue = false, Flag = "AutoFarm",
    Callback = function(v)
        AutoFarm = v; AutoClick = v; AutoRebirth = v
    end,
})

-- Auto Clicker
MainTab:CreateSection("Auto Clicker")
MainTab:CreateToggle({
    Name = "Auto Click", CurrentValue = false, Flag = "AutoClick",
    Callback = function(v) AutoClick = v end,
})
MainTab:CreateSlider({
    Name = "Click Delay", Range = {0, 0.1}, Increment = 0.005,
    Suffix = "s", CurrentValue = 0, Flag = "ClickDelay",
    Callback = function(v) ClickDelay = v end,
})

-- Auto Rebirth
MainTab:CreateSection("Auto Rebirth")
MainTab:CreateToggle({
    Name = "Auto Rebirth", CurrentValue = false, Flag = "AutoRebirth",
    Callback = function(v) AutoRebirth = v end,
})
MainTab:CreateDropdown({
    Name          = "Rebirth At",
    Options       = TierNames,
    CurrentOption = {TierNames[1]},
    Flag          = "RebirthTier",
    Callback      = function(v)
        SelectedTier = type(v) == "table" and v[1] or v
        RebirthAt    = RebirthTierValues[SelectedTier] or 1
    end,
})
MainTab:CreateButton({
    Name = "Rebirth Now",
    Callback = function()
        FireRebirth(RebirthAt)
        Rayfield:Notify({Title="Rebirth",Content="Fired at "..RebirthAt,Duration=2})
    end,
})
MainTab:CreateButton({
    Name = "Reload Tier List",
    Callback = function()
        local ok, src = LoadTiers()
        Rayfield:Notify({
            Title   = "Tier List",
            Content = #TierNames .. " tiers loaded (" .. src .. ")",
            Duration = 3,
        })
    end,
})

-- Stats
MainTab:CreateSection("Stats")
local statLabels = {}
-- build one label per leaderstats entry on load
task.spawn(function()
    task.wait(2)
    local stats = getLeaderstatDisplay()
    for _, entry in ipairs(stats) do
        statLabels[entry.name] = MainTab:CreateLabel(entry.name .. ": " .. entry.value)
    end
    if not next(statLabels) then
        statLabels["_fallback"] = MainTab:CreateLabel("Stats loading...")
    end
end)

-- Debug info
MainTab:CreateSection("Debug")
MainTab:CreateLabel("Rebirth remote: " .. (rebirthRemotePath or "not found"))
MainTab:CreateLabel("Tiers source: " .. tierSource)
MainTab:CreateLabel("Tiers loaded: " .. #TierNames)

-- Anti AFK
MainTab:CreateSection("Anti AFK")
MainTab:CreateToggle({
    Name = "Anti AFK", CurrentValue = true, Flag = "AntiAFK",
    Callback = function(_) end,
})

-- Script
MainTab:CreateSection("Script")
MainTab:CreateButton({
    Name = "Reinject / Reload",
    Callback = function()
        AutoClick = false; AutoRebirth = false
        AutoHatch = false; AutoFarm    = false
        task.wait(0.2); Rayfield:Destroy()
        task.wait(0.3)
        loadstring(game:HttpGet(ScriptURL, true))()
    end,
})

-- ─── Hatch Tab ────────────────────────────────────────────────────────────────
local HatchTab = Window:CreateTab("Hatch", 4483362458)

HatchTab:CreateSection("Auto Hatch")
HatchTab:CreateToggle({
    Name = "Auto Hatch", CurrentValue = false, Flag = "AutoHatch",
    Callback = function(v) AutoHatch = v end,
})
HatchTab:CreateToggle({
    Name = "Fast Hatch", CurrentValue = false, Flag = "FastHatch",
    Callback = function(v) FastHatch = v end,
})
HatchTab:CreateDropdown({
    Name = "Select Egg", Options = eggList,
    CurrentOption = {eggList[1]}, Flag = "EggPicker",
    Callback = function(v) SelectedEgg = type(v)=="table" and v[1] or v end,
})
HatchTab:CreateDropdown({
    Name = "Hatch Count",
    Options = {"1", "3"},
    CurrentOption = {"3"},
    Flag = "HatchMode",
    Callback = function(v)
        local raw = type(v) == "table" and v[1] or v
        HatchMode = tonumber(raw) or 3
    end,
})
HatchTab:CreateButton({
    Name = "Hatch Now",
    Callback = function()
        pcall(function()
            HatchFunc:InvokeServer(SelectedEgg, HatchMode)
        end)
        Rayfield:Notify({
            Title   = "Hatch",
            Content = SelectedEgg .. " x" .. HatchMode,
            Duration = 2,
        })
    end,
})
HatchTab:CreateButton({
    Name = "Refresh Egg List",
    Callback = function()
        eggList = GetEggList()
        Rayfield:Notify({
            Title   = "Eggs",
            Content = "Found " .. #eggList .. " eggs",
            Duration = 3,
        })
    end,
})

-- ─── Threads ──────────────────────────────────────────────────────────────────

-- click loop
task.spawn(function()
    while true do
        if AutoClick then
            pcall(function() ClickEvent:FireServer() end)
            if ClickDelay > 0 then task.wait(ClickDelay) else task.wait() end
        else
            task.wait()
        end
    end
end)

-- rebirth loop
task.spawn(function()
    while true do
        if AutoRebirth then
            pcall(function()
                if getRebirths() >= RebirthAt then
                    FireRebirth(RebirthAt)
                end
            end)
            task.wait(0.1)
        else
            task.wait(0.5)
        end
    end
end)

-- hatch loop — InvokeServer not FireServer
task.spawn(function()
    while true do
        if AutoHatch then
            pcall(function()
                HatchFunc:InvokeServer(SelectedEgg, HatchMode)
            end)
            task.wait(FastHatch and 0 or 2.7)
        else
            task.wait(0.5)
        end
    end
end)

-- anti afk
task.spawn(function()
    local VU = game:GetService("VirtualUser")
    player.Idled:Connect(function()
        if Toggles and Toggles.AntiAFK and not Toggles.AntiAFK.Value then return end
        VU:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VU:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end)

-- stats updater
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local stats = getLeaderstatDisplay()
            for _, entry in ipairs(stats) do
                if statLabels[entry.name] then
                    statLabels[entry.name]:Set(entry.name .. ": " .. entry.value)
                end
            end
        end)
    end
end)

task.wait(1)
Rayfield:Notify({
    Title   = "6larping7 Hub",
    Content = #TierNames .. " rebirth tiers — Left Control to toggle",
    Duration = 4,
})

Rayfield:LoadConfiguration()