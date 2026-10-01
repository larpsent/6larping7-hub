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
local AutoClick    = false
local AutoRebirth  = false
local AutoHatch    = false
local FastHatch    = false
local AutoFarm     = false  -- clicks + rebirths in one toggle
local SelectedEgg  = "Atlantean Egg"
local HatchMode    = "Triple"
local RebirthAt    = 1
local ClickDelay   = 0      -- task.wait() arg for click loop
local RebirthDelay = 0      -- task.wait() arg for rebirth loop

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

-- ─── Stats helper ─────────────────────────────────────────────────────────────
local function getStat(name)
    local ls = player:FindFirstChild("leaderstats")
    if not ls then return nil end
    local s = ls:FindFirstChild(name)
    return s and s.Value or nil
end

local function getRebirths()
    return getStat("🌀 Rebirths") or 0
end

-- ─── Window ───────────────────────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name             = "6larping7 Hub",
    LoadingTitle     = "6larping7 Hub",
    LoadingSubtitle  = "by apple sauce",
    Theme            = "Default",
    KeySystem        = false,   -- no key, just sets keybind below
    KeySettings      = {
        Title    = "6larping7 Hub",
        Subtitle = "Keybind",
        Note     = "Press Left Control to toggle UI",
        Key      = {"LeftControl"},
    },
    DisableRayfieldPrompts  = true,
    DisableBuildWarnings    = true,
})

-- override keybind explicitly after window creation
-- Rayfield reads this from KeySettings.Key but setting it again is belt+suspenders
pcall(function()
    Rayfield.Keybind = Enum.KeyCode.LeftControl
end)

-- ─── Main Tab ─────────────────────────────────────────────────────────────────
local MainTab = Window:CreateTab("Main", 4483362458)

-- ── Auto Farm (click + rebirth combined) ──────────────────────────────────────
MainTab:CreateSection("Auto Farm")
MainTab:CreateToggle({
    Name         = "Auto Farm  (Click + Rebirth)",
    CurrentValue = false,
    Flag         = "AutoFarm",
    Callback     = function(v)
        AutoFarm    = v
        AutoClick   = v
        AutoRebirth = v
    end,
})

-- ── Auto Clicker ──────────────────────────────────────────────────────────────
MainTab:CreateSection("Auto Clicker")
MainTab:CreateToggle({
    Name         = "Auto Click",
    CurrentValue = false,
    Flag         = "AutoClick",
    Callback     = function(v)
        AutoClick = v
    end,
})
MainTab:CreateSlider({
    Name         = "Click Delay (lower = faster)",
    Range        = {0, 0.1},
    Increment    = 0.01,
    Suffix       = "s",
    CurrentValue = 0,
    Flag         = "ClickDelay",
    Callback     = function(v) ClickDelay = v end,
})

-- ── Auto Rebirth ──────────────────────────────────────────────────────────────
MainTab:CreateSection("Auto Rebirth")
MainTab:CreateToggle({
    Name         = "Auto Rebirth",
    CurrentValue = false,
    Flag         = "AutoRebirth",
    Callback     = function(v) AutoRebirth = v end,
})
MainTab:CreateDropdown({
    Name          = "Rebirth At",
    Options       = TierNames,
    CurrentOption = {"1 Rebirth"},
    Flag          = "RebirthTier",
    Callback      = function(v)
        local tier = type(v) == "table" and v[1] or v
        RebirthAt  = RebirthTiers[tier] or 1
    end,
})
MainTab:CreateButton({
    Name     = "Rebirth Now",
    Callback = function()
        pcall(function() RebirthEvent:FireServer(RebirthAt) end)
        Rayfield:Notify({
            Title    = "Rebirth",
            Content  = "Fired rebirth at " .. RebirthAt,
            Duration = 2,
        })
    end,
})

-- ── Stats ─────────────────────────────────────────────────────────────────────
MainTab:CreateSection("Stats")
local RebirthLabel = MainTab:CreateLabel("Rebirths: loading...")
local ClicksLabel  = MainTab:CreateLabel("Clicks: loading...")

-- ── Anti AFK ──────────────────────────────────────────────────────────────────
MainTab:CreateSection("Anti AFK")
MainTab:CreateToggle({
    Name         = "Anti AFK",
    CurrentValue = true,
    Flag         = "AntiAFK",
    Callback     = function(_) end,
})

-- ── Script ────────────────────────────────────────────────────────────────────
MainTab:CreateSection("Script")
MainTab:CreateButton({
    Name     = "Reinject / Reload",
    Callback = function()
        AutoClick   = false
        AutoRebirth = false
        AutoHatch   = false
        AutoFarm    = false
        task.wait(0.2)
        Rayfield:Destroy()
        task.wait(0.3)
        loadstring(game:HttpGet(ScriptURL, true))()
    end,
})

-- ─── Hatch Tab ────────────────────────────────────────────────────────────────
local HatchTab = Window:CreateTab("Hatch", 4483362458)

HatchTab:CreateSection("Auto Hatch")
HatchTab:CreateToggle({
    Name         = "Auto Hatch",
    CurrentValue = false,
    Flag         = "AutoHatch",
    Callback     = function(v) AutoHatch = v end,
})
HatchTab:CreateToggle({
    Name         = "Fast Hatch",
    CurrentValue = false,
    Flag         = "FastHatch",
    Callback     = function(v) FastHatch = v end,
})
HatchTab:CreateDropdown({
    Name          = "Select Egg",
    Options       = eggList,
    CurrentOption = {eggList[1]},
    Flag          = "EggPicker",
    Callback      = function(v)
        SelectedEgg = type(v) == "table" and v[1] or v
    end,
})
HatchTab:CreateDropdown({
    Name          = "Hatch Mode",
    Options       = {"Single", "Triple"},
    CurrentOption = {"Triple"},
    Flag          = "HatchMode",
    Callback      = function(v)
        HatchMode = type(v) == "table" and v[1] or v
    end,
})
HatchTab:CreateButton({
    Name     = "Hatch Now",
    Callback = function()
        pcall(function()
            if FastHatch then HatchDone:FireServer() end
            HatchEvent:FireServer(SelectedEgg, HatchMode)
        end)
        Rayfield:Notify({
            Title    = "Hatch",
            Content  = "Hatching " .. SelectedEgg .. " (" .. HatchMode .. ")",
            Duration = 2,
        })
    end,
})
HatchTab:CreateButton({
    Name     = "Refresh Egg List",
    Callback = function()
        eggList = GetEggList()
        Rayfield:Notify({
            Title    = "Egg List",
            Content  = "Found " .. #eggList .. " eggs",
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
            task.wait(ClickDelay)
        else
            task.wait(0)
        end
    end
end)

-- rebirth loop — checks current rebirths against threshold
task.spawn(function()
    while true do
        if AutoRebirth then
            pcall(function()
                local current = getRebirths()
                if current >= RebirthAt then
                    RebirthEvent:FireServer(RebirthAt)
                end
            end)
        end
        task.wait(0.1) -- check every 100ms, not every frame
    end
end)

-- hatch loop
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
    local VirtualUser = game:GetService("VirtualUser")
    player.Idled:Connect(function()
        if Toggles and Toggles.AntiAFK and not Toggles.AntiAFK.Value then return end
        VirtualUser:Button2Down(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0,0), workspace.CurrentCamera.CFrame)
    end)
end)

-- stats label updater
task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local rebirths = getRebirths()
            RebirthLabel:Set("🌀 Rebirths: " .. tostring(rebirths))

            -- try common click stat names
            local clicks = getStat("💎 Clicks") or getStat("Clicks") or getStat("💰 Coins") or "?"
            ClicksLabel:Set("💎 Clicks: " .. tostring(clicks))
        end)
    end
end)

-- notify on load
task.wait(1)
Rayfield:Notify({
    Title    = "6larping7 Hub",
    Content  = "Loaded — Left Control to toggle UI",
    Duration = 4,
})

Rayfield:LoadConfiguration()