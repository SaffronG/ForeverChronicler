-- Forever Chronicaller: options page (Options -> AddOns -> Forever Chronicaller)
-- Built with the retail Settings API (vertical layout). Settings are stored in
-- FC.db.settings, so they're saved for each character with the rest of the data.

local ADDON, FC = ...

local TOGGLES = {
    { key = "level",       name = "Level ups",            tip = "Write an entry each time you gain a level." },
    { key = "zone",        name = "New zones",            tip = "Write an entry the first time you enter a zone." },
    { key = "quest",       name = "Quest turn-ins",       tip = "Write an entry for every quest you complete." },
    { key = "death",       name = "Deaths",               tip = "Write an entry when you die. The death counter is kept either way." },
    { key = "achievement", name = "Achievements",         tip = "Write an entry when you earn an achievement." },
    { key = "goal",        name = "Goals achieved",       tip = "Write an entry when you complete a goal." },
    { key = "profession",  name = "Profession milestones", tip = "Write an entry when you learn a profession and every 25 skill points." },
    { key = "recipe",      name = "Recipes learned",      tip = "Write an entry when you learn a recipe (a trainer visit is summed up in one line)." },
    { key = "craft",       name = "Crafting",             tip = "Write an entry the first time you craft each item, and at crafting milestones." },
}

local category

-- Tell the rest of the addon when a setting changes, so it can update live.
local function watch(variable, setting)
    local notify = function() FC:Fire("SETTINGS_CHANGED", variable) end
    if setting and setting.SetValueChangedCallback then
        setting:SetValueChangedCallback(notify)
    elseif Settings.SetOnValueChangedCallback then
        Settings.SetOnValueChangedCallback(variable, notify)
    end
end

local function register()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
        return -- Settings API missing; /chron config will say so
    end

    category = Settings.RegisterVerticalLayoutCategory("Forever Chronicaller")
    local createCheckbox = Settings.CreateCheckbox or Settings.CreateCheckBox -- renamed in 11.0

    local chronicle = FC.db.settings.chronicle
    for _, t in ipairs(TOGGLES) do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_Log_" .. t.key, t.key,
            chronicle, Settings.VarType.Boolean, t.name, true)
        createCheckbox(category, setting, t.tip)
    end

    local cap = Settings.RegisterAddOnSetting(category, ADDON .. "_MaxEntries", "maxEntries",
        FC.db.settings, Settings.VarType.Number, "Chronicle size limit", 0)
    local options = Settings.CreateSliderOptions(0, 5000, 100)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return value == 0 and "Unlimited" or tostring(value)
    end)
    Settings.CreateSlider(category, cap, options,
        "Maximum number of chronicle entries to keep. When a new entry pushes the chronicle over the limit, " ..
        "the oldest entries are permanently deleted. 0 = unlimited.")

    local arrival = Settings.RegisterAddOnSetting(category, ADDON .. "_ArrivalYards", "arrivalYards",
        FC.db.settings, Settings.VarType.Number, "Location goal arrival distance", 20)
    local arrivalOptions = Settings.CreateSliderOptions(5, 100, 5)
    arrivalOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return tostring(value) .. " yd"
    end)
    Settings.CreateSlider(category, arrival, arrivalOptions,
        "How close (in yards) you need to get to a location goal for it to complete.")

    local trackerVar = ADDON .. "_ShowTracker"
    local tracker = Settings.RegisterAddOnSetting(category, trackerVar, "showTracker",
        FC.db.settings, Settings.VarType.Boolean, "Show goal tracker", true)
    createCheckbox(category, tracker, "Show your open goals in a small box on screen (drag its title to move it).")
    watch(trackerVar, tracker)

    local shares = Settings.RegisterAddOnSetting(category, ADDON .. "_AcceptShares", "acceptShares",
        FC.db.settings, Settings.VarType.Boolean, "Allow shared goals", true)
    createCheckbox(category, shares, "Show a popup when someone shares a goal with you. Turn off to ignore all shared goals.")

    if FC.FEATURES.diagnostics then
        local diag = Settings.RegisterAddOnSetting(category, ADDON .. "_Diagnostics", "diagnostics",
            FC.db.settings, Settings.VarType.Boolean, "Performance diagnostics (opt-in)", false)
        createCheckbox(category, diag, "Time the addon's internal handlers and keep the results on this computer. " ..
            "They're only sent anywhere if you also turn on telemetry in the companion app. Never includes your data. See PRIVACY.md.")
    end

    Settings.RegisterAddOnCategory(category)
end

FC:On("READY", register)

function FC:OpenSettings()
    if not category then
        self:Print("The options page isn't available on this client.")
        return
    end
    if InCombatLockdown() then
        self:Print("Can't open options during combat.")
        return
    end
    Settings.OpenToCategory(category:GetID())
end

FC:Command({ "config", "options" }, "/chron config - open the options page", function() FC:OpenSettings() end, 90)
