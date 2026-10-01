local ScriptURL = "https://raw.githubusercontent.com/larpsent/6larping7-hub/refs/heads/main/cu.lua"

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local RS     = game:GetService("ReplicatedStorage")
local RunS   = game:GetService("RunService")
local player = game.Players.LocalPlayer

local ClickEvent        = RS.Events.Click
local RebirthEvent      = RS.Events.Rebirth
local HatchEvent        = RS.Events.Hatch
local HatchDone         = RS.Events.HatchDone
local SetAutoRebirthEv  = RS.Events.SetAutoRebirth  -- native auto rebirth

-- ─── Load rebirth tiers live from the game's own module ───────────────────────
-- RebirthTiers module returns a table of { [rebirthCount] = tapCost }
-- or similar — we read it and build our dropdown from it dynamically
local RawTiers = {}
local TierNames = {}
local RebirthTierValues = {}

local function LoadTiers()
    TierNames = {}
    RebirthTierValues = {}

    -- try requiring the module directly
    local ok, TierModule = pcall(require, RS.Modules.RebirthTiers)
    if ok and type(TierModule) == "table" then
        -- collect all numeric keys (rebirth counts)
        local counts = {}
        for k, _ in pairs(TierModule) do
            if type(k) == "number" then
                table.insert(counts, k)
            end
        end
        table.sort(counts)

        for _, count in ipairs(counts) do
            local name = count >= 1e6 and string.format("%.0fM Rebirths", count/1e6)
                or count >= 1e3 and string.format("%.0fK Rebirths", count/1e3)
                or count .. " Rebirth" .. (count == 1 and "" or "s")
            table.insert(TierNames, name)
            RebirthTierValues[name] = count
        end

        RawTiers = TierModule
        return true
    end

    -- fallback: parse the rebirth UI TextLabels directly
    -- "X Rebirths For" labels in PlayerGui.Rebirth.Holder.Holder.RebirthFrame
    local ok2, frame = pcall(function()
        return player.PlayerGui.Rebirth.Holder.Holder.RebirthFrame
    end)
    if ok2 and frame then
        local seen = {}
        for _, child in ipairs(frame:GetDescendants()) do
            if child:IsA("TextLabel") then
                local t = child.Text or ""
                -- match "X Rebirths For" or "X Rebirth For"
                local num, suffix = t:match("^([%d%.]+)([KMB]?)[%s]*[Rr]ebirth")
                if num and not seen[num .. suffix] then
                    seen[num .. suffix] = true
                    local val = tonumber(num) or 0
                    if suffix == "K" then val = val * 1e3
                    elseif suffix == "M" then val = val * 1e6
                    elseif suffix == "B" then val = val * 1e9 end
                    val = math.floor(val)
                    if val > 0 then
                        local name = t:match("^(.-)%s+[Ff]or") or tostring(val)
                        name = name:gsub("%s+", " ")
                        table.insert(TierNames, name)
                        RebirthTierValues[name] = val
                    end
                end
            end
        end
        -- sort by value
        table.sort(TierNames, function(a, b)
            return (RebirthTierValues[a] or 0) < (RebirthTierValues[b] or 0)
        end)
        if #TierNames > 0 then return true end
    end

    -- hard fallback if both fail
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
    return false
end

LoadTiers()

-- ─── State ────────────────────────────────────────────────────────────────────
local AutoClick       = false
local AutoRebirth     = false
local AutoHatch       = false
local FastHatch       = false
local AutoFarm        = false
local UseNativeAR     = true   -- use SetAutoRebirth remote vs our own loop
local SelectedEgg     = "Atlantean Egg"
local HatchMode       = "Triple"
local RebirthAt       = 1
local ClickDelay      = 0
local SelectedTier    = TierNames[1] or "1 Rebirth"

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

-- ─── Egg list ─────────────────────────────────────────────────────────────────
local function GetEggList()
    local eggs = {}
    local ok, holders = pcall(function() return workspace.Scripted.EggHolders end)
    if ok and holders then
        for _, egg in ipairs(holders:GetChildren()) do
            table.insert(eggs, egg.Name)
        end
    end
    if #eggs == 0 then eggs = {"Atlantean Egg"} end
    return eggs
end
local eggList = GetEggList()

-- ─── Stats ────────────────────────────────────────────────────────────────────
local function getStat(name)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return nil end
    local s = ls:FindFirstChild(name)
    return s and s.Value or nil
end
local function getRebirths()
    return ParseNumber(getStat("🌀 Rebirths")) or 0
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

MainTab:CreateSection("Auto Farm")
MainTab:CreateToggle({
    Name = "Auto Farm  (Click + Rebirth)",
    CurrentValue = false, Flag = "AutoFarm",
    Callback = function(v)
        AutoFarm = v; AutoClick = v; AutoRebirth = v
        -- also toggle native auto rebirth
        if UseNativeAR then
            pcall(function() SetAutoRebirthEv:FireServer(v, RebirthAt) end)
        end
    end,
})

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

MainTab:CreateSection("Auto Rebirth")
MainTab:CreateToggle({
    Name = "Use Native Auto Rebirth (recommended)",
    CurrentValue = true, Flag = "UseNativeAR",
    Callback = function(v)
        UseNativeAR = v
        if not v then
            -- turn off native when switching to our loop
            pcall(function() SetAutoRebirthEv:FireServer(false, RebirthAt) end)
        end
    end,
})
MainTab:CreateToggle({
    Name = "Auto Rebirth", CurrentValue = false, Flag = "AutoRebirth",
    Callback = function(v)
        AutoRebirth = v
        if UseNativeAR then
            pcall(function() SetAutoRebirthEv:FireServer(v, RebirthAt) end)
        end
    end,
})
MainTab:CreateDropdown({
    Name = "Rebirth At",
    Options = TierNames,
    CurrentOption = {TierNames[1]},
    Flag = "RebirthTier",
    Callback = function(v)
        SelectedTier = type(v) == "table" and v[1] or v
        RebirthAt    = RebirthTierValues[SelectedTier] or 1
        -- update native auto rebirth threshold live
        if UseNativeAR and AutoRebirth then
            pcall(function() SetAutoRebirthEv:FireServer(true, RebirthAt) end)
        end
    end,
})
MainTab:CreateButton({
    Name = "Rebirth Now",
    Callback = function()
        pcall(function() RebirthEvent:FireServer(RebirthAt) end)
        Rayfield:Notify({Title="Rebirth",Content="Fired at "..RebirthAt,Duration=2})
    end,
})
MainTab:CreateButton({
    Name = "Reload Tier List from Game",
    Callback = function()
        local ok = LoadTiers()
        Rayfield:Notify({
            Title   = "Tier List",
            Content = ok and ("Loaded " .. #TierNames .. " tiers from game module")
                         or ("Parsed " .. #TierNames .. " tiers from UI"),
            Duration = 3,
        })
    end,
})

MainTab:CreateSection("Stats")
local RebirthLabel = MainTab:CreateLabel("🌀 Rebirths: loading...")
local ClicksLabel  = MainTab:CreateLabel("👆 Clicks: loading...")
local EggsLabel    = MainTab:CreateLabel("🥚 Eggs: loading...")

MainTab:CreateSection("Anti AFK")
MainTab:CreateToggle({
    Name = "Anti AFK", CurrentValue = true, Flag = "AntiAFK",
    Callback = function(_) end,
})

MainTab:CreateSection("Script")
MainTab:CreateButton({
    Name = "Reinject / Reload",
    Callback = function()
        AutoClick = false; AutoRebirth = false
        AutoHatch = false; AutoFarm    = false
        pcall(function() SetAutoRebirthEv:FireServer(false, 1) end)
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
    Name = "Hatch Mode", Options = {"Single","Triple"},
    CurrentOption = {"Triple"}, Flag = "HatchMode",
    Callback = function(v) HatchMode = type(v)=="table" and v[1] or v end,
})
HatchTab:CreateButton({
    Name = "Hatch Now",
    Callback = function()
        pcall(function()
            if FastHatch then HatchDone:FireServer() end
            HatchEvent:FireServer(SelectedEgg, HatchMode)
        end)
        Rayfield:Notify({Title="Hatch",Content=SelectedEgg.." ("..HatchMode..")",Duration=2})
    end,
})
HatchTab:CreateButton({
    Name = "Refresh Egg List",
    Callback = function()
        eggList = GetEggList()
        Rayfield:Notify({Title="Eggs",Content="Found "..#eggList.." eggs",Duration=3})
    end,
})

-- ─── Threads ──────────────────────────────────────────────────────────────────
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

-- fallback rebirth loop — only fires when UseNativeAR is off
task.spawn(function()
    while true do
        if AutoRebirth and not UseNativeAR then
            pcall(function()
                if getRebirths() >= RebirthAt then
                    RebirthEvent:FireServer(RebirthAt)
                end
            end)
            task.wait(0.1)
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    while true do
        if AutoHatch then
            pcall(function()
                if FastHatch then HatchDone:FireServer() end
                HatchEvent:FireServer(SelectedEgg, HatchMode)
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
            RebirthLabel:Set("🌀 Rebirths: " .. tostring(getStat("🌀 Rebirths") or "?"))
            ClicksLabel:Set("👆 Clicks: "   .. tostring(getStat("👆 Clicks")    or "?"))
            EggsLabel:Set("🥚 Eggs: "       .. tostring(getStat("🥚 Eggs")      or "?"))
        end)
    end
end)

task.wait(1)
Rayfield:Notify({
    Title   = "6larping7 Hub",
    Content = "Loaded — " .. #TierNames .. " rebirth tiers — Left Control to toggle",
    Duration = 4,
})

Rayfield:LoadConfiguration()