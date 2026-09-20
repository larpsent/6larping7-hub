local ScriptURL = "https://raw.githubusercontent.com/larpsent/6larping7-hub/refs/heads/main/cu.lua"

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local RS     = game:GetService("ReplicatedStorage")
local RunS   = game:GetService("RunService")
local player = game.Players.LocalPlayer

local ClickEvent   = RS.Events.Click
local RebirthEvent = RS.Events.Rebirth
local HatchEvent   = RS.Events.Hatch
local HatchDone    = RS.Events.HatchDone

-- ─── State ───────────────────────────────────────────────────────────────────
local AutoClick   = false
local AutoRebirth = false
local AutoHatch   = false
local FastHatch   = false
local SelectedEgg = "Atlantean Egg"
local HatchMode   = "Triple"
local RebirthAt   = 1

-- ─── Rebirth tiers ────────────────────────────────────────────────────────────
local RebirthTiers = {
    ["1 Rebirth"]     = 1,
    ["5 Rebirths"]    = 5,
    ["10 Rebirths"]   = 10,
    ["25 Rebirths"]   = 25,
    ["50 Rebirths"]   = 50,
    ["75 Rebirths"]   = 75,
    ["100 Rebirths"]  = 100,
    ["250 Rebirths"]  = 250,
    ["500 Rebirths"]  = 500,
    ["750 Rebirths"]  = 750,
    ["1K Rebirths"]   = 1000,
    ["2.5K Rebirths"] = 2500,
    ["5K Rebirths"]   = 5000,
    ["7.5K Rebirths"] = 7500,
    ["10K Rebirths"]  = 10000,
    ["25K Rebirths"]  = 25000,
    ["50K Rebirths"]  = 50000,
    ["75K Rebirths"]  = 75000,
    ["100K Rebirths"] = 100000,
}

local TierNames = {
    "1 Rebirth", "5 Rebirths", "10 Rebirths", "25 Rebirths",
    "50 Rebirths", "75 Rebirths", "100 Rebirths", "250 Rebirths",
    "500 Rebirths", "750 Rebirths", "1K Rebirths", "2.5K Rebirths",
    "5K Rebirths", "7.5K Rebirths", "10K Rebirths", "25K Rebirths",
    "50K Rebirths", "75K Rebirths", "100K Rebirths",
}

-- ─── Number parser ────────────────────────────────────────────────────────────
local suffixes = {
    K = 1e3, M = 1e6, B = 1e9, T = 1e12,
    Qd = 1e15, Qn = 1e18, Sx = 1e21, Sp = 1e24,
}
local function ParseNumber(str)
    if not str then return 0 end
    str = tostring(str):gsub(",",""):gsub(" ","")
    local plain = tonumber(str)
    if plain then return plain end
    for suffix, mult in pairs(suffixes) do
        local num = str:match("^([%d%.]+)" .. suffix .. "$")
        if num then return tonumber(num) * mult end
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

-- ─── Window ───────────────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name = "6larping7 Hub",
    LoadingTitle = "6larping7 Hub",
    LoadingSubtitle = "by apple sauce",
    Theme = "Default",
    DisableRayfieldPrompts = true,
    DisableBuildWarnings = true,
})

-- ─── Main Tab ─────────────────────────────────────────────────────────────────
local MainTab = Window:CreateTab("Main", 4483362458)

MainTab:CreateSection("Auto Clicker")
MainTab:CreateToggle({
    Name = "Auto Click",
    CurrentValue = false,
    Flag = "AutoClick",
    Callback = function(v) AutoClick = v end,
})

MainTab:CreateSection("Auto Rebirth")
MainTab:CreateToggle({
    Name = "Auto Rebirth",
    CurrentValue = false,
    Flag = "AutoRebirth",
    Callback = function(v) AutoRebirth = v end,
})
MainTab:CreateDropdown({
    Name = "Rebirth Tier",
    Options = TierNames,
    CurrentOption = {"1 Rebirth"},
    Flag = "RebirthTier",
    Callback = function(v)
        local tier = type(v) == "table" and v[1] or v
        RebirthAt = RebirthTiers[tier] or 1
    end,
})
MainTab:CreateButton({
    Name = "Rebirth Now",
    Callback = function()
        pcall(function() RebirthEvent:FireServer(RebirthAt) end)
    end,
})

MainTab:CreateSection("Info")
local RebirthLabel = MainTab:CreateLabel("Rebirths: loading...")

MainTab:CreateSection("Script")
MainTab:CreateButton({
    Name = "Reinject / Reload",
    Callback = function()
        AutoClick   = false
        AutoRebirth = false
        AutoHatch   = false
        task.wait(0.2)
        Rayfield:Destroy()
        task.wait(0.3)
        loadstring(game:HttpGet(ScriptURL, true))()
    end,
})

MainTab:CreateSection("Anti AFK")
MainTab:CreateToggle({
    Name = "Anti AFK",
    CurrentValue = true, -- on by default
    Flag = "AntiAFK",
    Callback = function(v)
        -- toggling handled in the thread below
    end,
})

-- ─── Hatch Tab ────────────────────────────────────────────────────────────────
local HatchTab = Window:CreateTab("Hatch", 4483362458)

HatchTab:CreateSection("Auto Hatch")
HatchTab:CreateToggle({
    Name = "Auto Hatch",
    CurrentValue = false,
    Flag = "AutoHatch",
    Callback = function(v) AutoHatch = v end,
})
HatchTab:CreateToggle({
    Name = "Fast Hatch",
    CurrentValue = false,
    Flag = "FastHatch",
    Callback = function(v) FastHatch = v end,
})
HatchTab:CreateDropdown({
    Name = "Select Egg",
    Options = eggList,
    CurrentOption = {eggList[1]},
    Flag = "EggPicker",
    Callback = function(v)
        SelectedEgg = type(v) == "table" and v[1] or v
    end,
})
HatchTab:CreateDropdown({
    Name = "Hatch Mode",
    Options = {"Single", "Triple"},
    CurrentOption = {"Triple"},
    Flag = "HatchMode",
    Callback = function(v)
        HatchMode = type(v) == "table" and v[1] or v
    end,
})
HatchTab:CreateButton({
    Name = "Hatch Now",
    Callback = function()
        pcall(function()
            if FastHatch then HatchDone:FireServer() end
            HatchEvent:FireServer(SelectedEgg, HatchMode)
        end)
    end,
})
HatchTab:CreateButton({
    Name = "Refresh Egg List",
    Callback = function()
        eggList = GetEggList()
        Rayfield:Notify({
            Title = "Egg List",
            Content = "Found " .. #eggList .. " eggs",
            Duration = 3,
        })
    end,
})

-- ─── Threads ──────────────────────────────────────────────────────────────────
task.spawn(function()
    while true do
        if AutoClick then
            pcall(function() ClickEvent:FireServer() end)
        end
        task.wait()
    end
end)

task.spawn(function()
    while true do
        if AutoRebirth then
            pcall(function() RebirthEvent:FireServer(RebirthAt) end)
        end
        task.wait()
    end
end)

task.spawn(function()
    while true do
        if AutoHatch then
            pcall(function()
                if FastHatch then
                    HatchDone:FireServer()
                end
                HatchEvent:FireServer(SelectedEgg, HatchMode)
            end)
            if FastHatch then
                task.wait(0) -- skip anim, minimal cooldown
            else
                task.wait(2.7) -- matches game's exact 2.7s hatch speed
            end
        else
            task.wait(0.5)
        end
    end
end)

task.spawn(function()
    local VirtualUser = game:GetService("VirtualUser")
    game:GetService("Players").LocalPlayer.Idled:Connect(function()
        if Toggles and Toggles.AntiAFK and not Toggles.AntiAFK.Value then return end
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end)

task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            local ls = player:FindFirstChild("leaderstats")
            if ls then
                local stat = ls:FindFirstChild("🌀 Rebirths")
                if stat then
                    RebirthLabel:Set("Current Rebirths: " .. tostring(stat.Value))
                end
            end
        end)
    end
end)

Rayfield:LoadConfiguration()