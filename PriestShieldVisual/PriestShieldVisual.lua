local _, playerClass = UnitClass("player")
if playerClass ~= "PRIEST" then return end

local ADDON_NAME = ...
local DB_NAME = ADDON_NAME .. "DB"
local db
local PWS_BASE_ABSORB = {
    [17] = 48, [592] = 92, [600] = 162, [3747] = 233,
    [6065] = 303, [6066] = 381, [10898] = 499, [10899] = 608,
    [10900] = 769, [10901] = 950,
}
local SEGMENT_COUNT = 20
local PWS_DURATION = 30
local BASE_WIDTH = 28
local BASE_HEIGHT = 11.25
local SEGMENT_SPACING = 9
local BASE_RADIUS = 8
local STACK_HEIGHT = 190
local INTRO_DURATION = 0.35
local OUTRO_DURATION = 0.35
local SEGMENT_FADE = 0.14
local DAMAGE_FADE_FRACTION = 0.2
local state = { active = false, max = 1, expires = 0, visibleSegments = SEGMENT_COUNT }
local animationSerial = 0
local UpdateAbsorb

local defaults = {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -140,
    scale = 0.75,
    transparency = 0,
    curvature = 1,
    meterColor = { 1.0, 0.91, 0.43 },
    locked = false,
    hideText = false,
    textFont = "default",
}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function CopyDefaults()
    db = _G[DB_NAME] or {}
    _G[DB_NAME] = db
    for key, value in pairs(defaults) do
        if db[key] == nil then db[key] = value end
    end
end

local LayoutSegments

local root = CreateFrame("Frame", "PriestShieldVisualFrame", UIParent, "BackdropTemplate")
root:SetSize(160, 280)
root:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
root:SetClampedToScreen(true)
root:SetMovable(true)
root:EnableMouse(true)
root:RegisterForDrag("LeftButton")
root:SetScript("OnDragStart", function(self)
    if db and not db.locked then self:StartMoving() end
end)
local function SaveRootPosition()
    root:StopMovingOrSizing()
    local point, _, relativePoint, x, y = root:GetPoint(1)
    db.point, db.relativePoint = point, relativePoint
    db.x, db.y = x, y
end
root:SetScript("OnDragStop", SaveRootPosition)

-- One native status bar accepts protected combat absorb values. Its fill texture
-- reveals a clipped stack of ordinary textures, avoiding 20 independent ranges.
local gate = CreateFrame("StatusBar", nil, root)
gate:SetSize(120, STACK_HEIGHT)
gate:SetPoint("CENTER", root, "CENTER", 0, 0)
gate:SetOrientation("VERTICAL")
gate:SetReverseFill(true)
gate:SetMinMaxValues(0, 1)
gate:SetValue(0)
gate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
gate:SetStatusBarColor(1, 1, 1, 1)
local gateTexture = gate:GetStatusBarTexture()
gateTexture:SetAlpha(0)

local content = CreateFrame("Frame", nil, gate)
content:SetClipsChildren(true)
content:SetFrameLevel(root:GetFrameLevel() + 2)
content:SetAllPoints(gate)

local segments, segmentBars = {}, {}
for i = 1, SEGMENT_COUNT do
    local bar = CreateFrame("StatusBar", nil, content)
    bar:SetSize(BASE_WIDTH, BASE_HEIGHT)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar:SetStatusBarTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Segment.tga")
    bar:SetStatusBarColor(1.0, 0.91, 0.43, 1)
    local texture = bar:GetStatusBarTexture()
    texture:SetAlpha(0)
    segments[i] = texture
    segmentBars[i] = bar
end

-- This native bar clips the label at zero without Lua testing a protected
-- combat value. Absorb values are whole points, so any positive value fills it.
local valueGate = CreateFrame("StatusBar", nil, root)
valueGate:SetSize(100, 20)
valueGate:SetPoint("TOP", segmentBars[1], "BOTTOM", -3, 0)
valueGate:SetMinMaxValues(0, 1)
valueGate:SetValue(0)
valueGate:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
local valueGateTexture = valueGate:GetStatusBarTexture()
valueGateTexture:SetAlpha(0)

local valueClip = CreateFrame("Frame", nil, valueGate)
valueClip:SetClipsChildren(true)
valueClip:SetPoint("TOPLEFT", valueGateTexture, "TOPLEFT")
valueClip:SetPoint("BOTTOMLEFT", valueGateTexture, "BOTTOMLEFT")
valueClip:SetPoint("TOPRIGHT", valueGateTexture, "TOPRIGHT")
valueClip:SetPoint("BOTTOMRIGHT", valueGateTexture, "BOTTOMRIGHT")

local valueText = valueClip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
valueText:SetPoint("CENTER", valueClip, "CENTER", 1, 0)
valueText:SetTextColor(1, 0.96, 0.73, 1)
valueText:Hide()

-- The default font option keeps the original GameFontNormal appearance.
local defaultFontPath, defaultFontSize, defaultFontFlags = GameFontNormal:GetFont()
local textFontOptions = {
    default = { label = "Default (current)", fontObject = GameFontNormal },
    friz = { label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    arial = { label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    morpheus = { label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    skurri = { label = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local editHint = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
editHint:SetPoint("BOTTOM", segmentBars[SEGMENT_COUNT], "TOP", 0, 7)
editHint:SetText("Priest Shield Visual · drag to move")
editHint:Hide()

local bottomHint = CreateFrame("Button", "PriestShieldVisualDragHint", root)
bottomHint:SetSize(160, 18)
bottomHint:SetPoint("TOP", valueGate, "BOTTOM", 0, -4)
bottomHint:EnableMouse(true)
bottomHint:RegisterForDrag("LeftButton")
bottomHint:SetScript("OnDragStart", function()
    if db and not db.locked then root:StartMoving() end
end)
bottomHint:SetScript("OnDragStop", SaveRootPosition)
local bottomHintText = bottomHint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bottomHintText:SetPoint("CENTER")
bottomHintText:SetText("type /psv for menu/lock")
bottomHint:Hide()

local config = CreateFrame("Frame", "PriestShieldVisualConfig", UIParent, "BackdropTemplate")
config:SetSize(290, 380)
config:SetPoint("CENTER")
config:SetFrameStrata("DIALOG")
config:SetMovable(true)
config:EnableMouse(true)
config:RegisterForDrag("LeftButton")
config:SetScript("OnDragStart", config.StartMoving)
config:SetScript("OnDragStop", config.StopMovingOrSizing)
config:Hide()
config:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
config:SetBackdropColor(0.04, 0.04, 0.06, 0.96)

local heading = config:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
heading:SetPoint("TOPLEFT", 16, -14)
heading:SetText("Priest Shield Visual")

local close = CreateFrame("Button", nil, config, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -3, -3)

local lock = CreateFrame("CheckButton", "PriestShieldVisualLockCheck", config, "UICheckButtonTemplate")
lock:SetPoint("TOPLEFT", 12, -42)
_G[lock:GetName() .. "Text"]:SetText("Lock meter position")
lock:SetScript("OnClick", function(self)
    db.locked = self:GetChecked()
    local unlocked = not db.locked
    root:EnableMouse(unlocked)
    editHint:SetShown(unlocked)
    bottomHint:SetShown(unlocked)
end)

local scaleLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLabel:SetPoint("TOPLEFT", 18, -91)
scaleLabel:SetText("Scale")

local scaleSlider = CreateFrame("Slider", "PriestShieldVisualScaleSlider", config, "OptionsSliderTemplate")
scaleSlider:SetPoint("TOPLEFT", config, "TOPLEFT", 112, -84)
scaleSlider:SetWidth(150)
scaleSlider:SetMinMaxValues(0.1, 2.0)
scaleSlider:SetValueStep(0.05)
scaleSlider:SetObeyStepOnDrag(true)
_G[scaleSlider:GetName() .. "Low"]:SetText("0.1")
_G[scaleSlider:GetName() .. "High"]:SetText("2.0")
_G[scaleSlider:GetName() .. "Text"]:SetText("")
scaleSlider:SetScript("OnValueChanged", function(_, value)
    if not db then return end
    value = math.floor(value * 100 + 0.5) / 100
    db.scale = value
    root:SetScale(value)
end)

local transparencyLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
transparencyLabel:SetPoint("TOPLEFT", 18, -137)
transparencyLabel:SetText("Transparency")

local transparencySlider = CreateFrame("Slider", "PriestShieldVisualTransparencySlider", config, "OptionsSliderTemplate")
transparencySlider:SetPoint("TOPLEFT", config, "TOPLEFT", 112, -130)
transparencySlider:SetWidth(150)
transparencySlider:SetMinMaxValues(0, 95)
transparencySlider:SetValueStep(5)
transparencySlider:SetObeyStepOnDrag(true)
_G[transparencySlider:GetName() .. "Low"]:SetText("Transparent")
_G[transparencySlider:GetName() .. "High"]:SetText("Solid")
_G[transparencySlider:GetName() .. "Text"]:SetText("")
transparencySlider:SetScript("OnValueChanged", function(_, value)
    if not db then return end
    value = math.floor(value / 5 + 0.5) * 5
    local transparency = 95 - value
    db.transparency = transparency
    root:SetAlpha(1 - transparency / 100)
end)

local curvatureLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
curvatureLabel:SetPoint("TOPLEFT", 18, -183)
curvatureLabel:SetText("Curvature")

local curvatureSlider = CreateFrame("Slider", "PriestShieldVisualCurvatureSlider", config, "OptionsSliderTemplate")
curvatureSlider:SetPoint("TOPLEFT", config, "TOPLEFT", 112, -176)
curvatureSlider:SetWidth(150)
curvatureSlider:SetMinMaxValues(0, 2)
curvatureSlider:SetValueStep(0.05)
curvatureSlider:SetObeyStepOnDrag(true)
_G[curvatureSlider:GetName() .. "Low"]:SetText("Straight")
_G[curvatureSlider:GetName() .. "High"]:SetText("More")
_G[curvatureSlider:GetName() .. "Text"]:SetText("")
curvatureSlider:SetScript("OnValueChanged", function(_, value)
    if not db then return end
    value = math.floor(value * 100 + 0.5) / 100
    db.curvature = value
    LayoutSegments()
end)

local meterColorLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
meterColorLabel:SetPoint("TOPLEFT", 18, -225)
meterColorLabel:SetText("Meter color")

local meterColorButton = CreateFrame("Button", "PriestShieldVisualMeterColorButton", config, "UIPanelButtonTemplate")
meterColorButton:SetSize(28, 24)
meterColorButton:SetPoint("TOPLEFT", config, "TOPLEFT", 112, -218)
meterColorButton:SetText("")
local meterColorSwatch = meterColorButton:CreateTexture(nil, "OVERLAY")
meterColorSwatch:SetSize(14, 14)
meterColorSwatch:SetPoint("CENTER", meterColorButton, "CENTER")
meterColorSwatch:SetTexture("Interface\\ChatFrame\\ChatFrameColorSwatch")

local function ApplyMeterColor()
    if not db then return end
    local color = db.meterColor or defaults.meterColor
    for i = 1, SEGMENT_COUNT do
        segmentBars[i]:SetStatusBarColor(color[1], color[2], color[3], 1)
    end
    valueText:SetTextColor(color[1], color[2], color[3], 1)
    meterColorSwatch:SetVertexColor(color[1], color[2], color[3])
end

local function SetMeterColor(r, g, b)
    db.meterColor = { r, g, b }
    ApplyMeterColor()
end

meterColorButton:SetScript("OnClick", function()
    local color = db.meterColor or defaults.meterColor
    local previous = { color[1], color[2], color[3] }
    local picker = ColorPickerFrame
    local function apply(r, g, b) SetMeterColor(r, g, b) end
    local function cancel()
        SetMeterColor(previous[1], previous[2], previous[3])
    end
    if picker.SetupColorPickerAndShow then
        picker:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3], hasOpacity = false,
            swatchFunc = function() local r, g, b = picker:GetColorRGB(); apply(r, g, b) end,
            cancelFunc = cancel,
        })
    else
        picker.hasOpacity = false
        picker.func = function() local r, g, b = picker:GetColorRGB(); apply(r, g, b) end
        picker.cancelFunc = cancel
        picker:SetColorRGB(color[1], color[2], color[3])
        picker:Show()
    end
end)

local hideText = CreateFrame("CheckButton", "PriestShieldVisualHideTextCheck", config, "UICheckButtonTemplate")
hideText:SetPoint("TOPLEFT", 12, -332)
_G[hideText:GetName() .. "Text"]:SetText("Hide text")
hideText:SetScript("OnClick", function(self)
    db.hideText = self:GetChecked()
    if db.hideText then
        valueText:Hide()
    elseif state.active then
        UpdateAbsorb()
    else
        valueText:Hide()
    end
end)

local function ApplyTextFont()
    if not db then return end
    local option = textFontOptions[db.textFont] or textFontOptions.default
    local size = db.textFontSize or defaultFontSize
    if option.fontObject and size == defaultFontSize then
        valueText:SetFontObject(option.fontObject)
    else
        valueText:SetFont(option.path or defaultFontPath, size, defaultFontFlags)
    end
end

local fontLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontLabel:SetPoint("TOPLEFT", 18, -258)
fontLabel:SetText("Text font")

local fontDropdown = CreateFrame("Frame", "PriestShieldVisualFontDropdown", config, "UIDropDownMenuTemplate")
fontDropdown:SetPoint("TOP", config, "TOP", 42, -247)
UIDropDownMenu_SetWidth(fontDropdown, 155)
UIDropDownMenu_Initialize(fontDropdown, function(self, level)
    for key, option in pairs(textFontOptions) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = option.label
        info.checked = db and db.textFont == key
        info.func = function()
            db.textFont = key
            UIDropDownMenu_SetSelectedValue(fontDropdown, key)
            UIDropDownMenu_SetText(fontDropdown, option.label)
            ApplyTextFont()
        end
        UIDropDownMenu_AddButton(info, level)
    end
end)

local fontSizeLabel = config:CreateFontString(nil, "OVERLAY", "GameFontNormal")
fontSizeLabel:SetPoint("TOPLEFT", 18, -300)
fontSizeLabel:SetText("Text size")

local fontSizeInput = CreateFrame("EditBox", "PriestShieldVisualFontSizeInput", config, "InputBoxTemplate")
fontSizeInput:SetSize(48, 22)
fontSizeInput:SetPoint("TOPLEFT", 112, -294)
fontSizeInput:SetAutoFocus(false)
fontSizeInput:SetNumeric(true)
fontSizeInput:SetMaxLetters(2)
fontSizeInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
fontSizeInput:SetScript("OnEscapePressed", function(self)
    self:SetText(tostring(db.textFontSize or defaultFontSize))
    self:ClearFocus()
end)
fontSizeInput:SetScript("OnEditFocusLost", function(self)
    if not db then return end
    local size = tonumber(self:GetText())
    if not size then size = db.textFontSize or defaultFontSize end
    size = math.max(6, math.min(48, math.floor(size + 0.5)))
    db.textFontSize = size
    self:SetText(tostring(size))
    ApplyTextFont()
end)

local function RefreshTextFontControls()
    local key = textFontOptions[db.textFont] and db.textFont or "default"
    db.textFont = key
    local size = tonumber(db.textFontSize) or defaultFontSize
    db.textFontSize = math.max(6, math.min(48, math.floor(size + 0.5)))
    UIDropDownMenu_SetSelectedValue(fontDropdown, key)
    UIDropDownMenu_SetText(fontDropdown, textFontOptions[key].label)
    fontSizeInput:SetText(tostring(db.textFontSize))
    ApplyTextFont()
end

local resetDefaults = CreateFrame("Button", "PriestShieldVisualResetDefaultsButton", config, "UIPanelButtonTemplate")
resetDefaults:SetSize(132, 24)
resetDefaults:SetPoint("RIGHT", config, "RIGHT", -14, 0)
resetDefaults:SetPoint("TOP", hideText, "TOP", 0, 0)
resetDefaults:SetText("Reset to defaults")
resetDefaults:SetScript("OnClick", function()
    for key in pairs(db) do db[key] = nil end
    CopyDefaults()
    lock:SetChecked(db.locked)
    root:EnableMouse(not db.locked)
    hideText:SetChecked(db.hideText)
    scaleSlider:SetValue(db.scale)
    transparencySlider:SetValue(95 - db.transparency)
    curvatureSlider:SetValue(db.curvature)
    ApplyMeterColor()
    RefreshTextFontControls()
    editHint:SetShown(not db.locked)
    bottomHint:SetShown(not db.locked)
    LayoutSegments()
    if state.active and not db.hideText then
        UpdateAbsorb()
    else
        valueText:Hide()
    end
end)

LayoutSegments = function()
    local scale = db and db.scale or 1
    root:SetScale(scale)
    local transparency = db and db.transparency or 0
    local curvature = db and db.curvature or defaults.curvature
    root:SetAlpha(1 - transparency / 100)
    root:ClearAllPoints()
    local settings = db or defaults
    root:SetPoint(settings.point or defaults.point, UIParent, settings.relativePoint or defaults.relativePoint, settings.x or 0, settings.y or -140)
    for i = 1, SEGMENT_COUNT do
        local t = (i - 1) / (SEGMENT_COUNT - 1)
        -- Pixel-align every instance so identical textures do not alternate
        -- between different rasterization phases along the stack.
        local x = math.floor(math.sin(math.pi * t) * BASE_RADIUS * 2 * curvature + 0.5)
        local y = -STACK_HEIGHT / 2 + SEGMENT_SPACING / 2 + (i - 1) * SEGMENT_SPACING
        local bar = segmentBars[i]
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", root, "CENTER", x, y)
    end
end

local function IsPWS(spellID)
    return type(spellID) == "number" and not IsSecret(spellID) and PWS_BASE_ABSORB[spellID] ~= nil
end

local function SetGateValue(value, rangeMax)
    -- Explicitly pass the cast-time range for protected values; otherwise use
    -- the numeric range captured while the amount is readable.
    local max = state.max or 1
    if IsSecret(rangeMax) then
        max = rangeMax
    elseif type(rangeMax) == "number" then
        max = rangeMax
    end
    if not IsSecret(max) then max = math.max(1, max) end
    pcall(gate.SetMinMaxValues, gate, 0, max)
    pcall(gate.SetValue, gate, value)
end

local function StopAnimations()
    animationSerial = animationSerial + 1
    for i = 1, SEGMENT_COUNT do
        local group = segments[i]._priestMeterAnimation
        if group then group:Stop() end
    end
    return animationSerial
end

local function FadeSegment(index, fromAlpha, toAlpha, duration, serial)
    local texture = segments[index]
    texture:SetAlpha(fromAlpha)
    local group = texture._priestMeterAnimation
    if not group then
        group = texture:CreateAnimationGroup()
        local alpha = group:CreateAnimation("Alpha")
        alpha:SetSmoothing("IN_OUT")
        group._alpha = alpha
        texture._priestMeterAnimation = group
    end
    group:Stop()
    group._alpha:SetFromAlpha(fromAlpha)
    group._alpha:SetToAlpha(toAlpha)
    group._alpha:SetDuration(duration)
    group:SetScript("OnFinished", function()
        if animationSerial == serial then
            texture:SetAlpha(toAlpha)
        end
    end)
    group:Play()
end

local function UpdateVisibleSegments(amount)
    if IsSecret(amount) or type(amount) ~= "number" then return end

    local maxAmount = state.max or 1
    if maxAmount <= 0 then return end

    -- Count only fully lost 5% chunks. A burst of damage can therefore fade
    -- several bars during this one update, while partial chunks leave bars whole.
    local lost = math.floor(((maxAmount - amount) / maxAmount) * SEGMENT_COUNT + 0.000001)
    local desired = math.max(0, math.min(SEGMENT_COUNT, SEGMENT_COUNT - lost))
    local previous = state.visibleSegments or SEGMENT_COUNT
    if desired < previous then
        local serial = animationSerial
        for index = previous, desired + 1, -1 do
            local currentAlpha = segments[index]:GetAlpha()
            if currentAlpha > 0 then
                FadeSegment(index, currentAlpha, 0, SEGMENT_FADE, serial)
            end
        end
    elseif desired > previous then
        -- A shield refresh may increase its value without a new cast event.
        local serial = animationSerial
        for index = previous + 1, desired do
            FadeSegment(index, segments[index]:GetAlpha(), 1, SEGMENT_FADE, serial)
        end
    end
    state.visibleSegments = desired
end

local function ApplySecretAbsorb(amount)
    local segmentValue = math.max(1, (state.max or 1) / SEGMENT_COUNT)
    local fadeBand = math.max(0.1, segmentValue * DAMAGE_FADE_FRACTION)
    for i = 1, SEGMENT_COUNT do
        local threshold = (i - 1) * segmentValue
        local bar = segmentBars[i]
        bar:SetMinMaxValues(threshold, threshold + fadeBand)
        if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut then
            pcall(bar.SetValue, bar, amount, Enum.StatusBarInterpolation.ExponentialEaseOut)
        else
            pcall(bar.SetValue, bar, amount)
        end
    end
    SetGateValue(1, 1)
end

local function AnimateIn()
    local serial = StopAnimations()
    for i = 1, SEGMENT_COUNT do
        local delay = (i - 1) * (INTRO_DURATION - SEGMENT_FADE) / (SEGMENT_COUNT - 1)
        C_Timer.After(delay, function()
            if animationSerial == serial and state.active and i <= (state.visibleSegments or SEGMENT_COUNT) then
                FadeSegment(i, 0, 1, SEGMENT_FADE, serial)
            end
        end)
    end
end

local function AnimateOut(onComplete)
    local serial = StopAnimations()
    for i = 1, SEGMENT_COUNT do
        local index = SEGMENT_COUNT - i + 1
        local delay = (i - 1) * (OUTRO_DURATION - SEGMENT_FADE) / (SEGMENT_COUNT - 1)
        C_Timer.After(delay, function()
            if animationSerial == serial then
                FadeSegment(index, segments[index]:GetAlpha(), 0, SEGMENT_FADE, serial)
            end
        end)
    end
    C_Timer.After(OUTRO_DURATION, function()
        if animationSerial == serial and onComplete then onComplete() end
    end)
end

local function ClearSegments()
    StopAnimations()
    for i = 1, SEGMENT_COUNT do segments[i]:SetAlpha(0) end
    state.visibleSegments = 0
    SetGateValue(0)
    valueGate:SetValue(0)
end

local function ExpireTracking()
    if not state.active or state.expiring then return end
    state.expiring = true
    valueText:Hide()
    valueGate:SetValue(0)
    AnimateOut(function()
        state.active = false
        state.expiring = nil
        state.auraInstanceID = nil
        state.justCast = nil
        state.max = 1
        ClearSegments()
        valueText:Hide()
    end)
end

UpdateAbsorb = function()
    if not state.active or not UnitGetTotalAbsorbs then return end
    local amount = UnitGetTotalAbsorbs("player")
    if not IsSecret(amount) and amount == nil then
        ExpireTracking()
        return
    end

    pcall(valueGate.SetValue, valueGate, amount)
    pcall(valueText.SetFormattedText, valueText, "%d", amount)
    if db and db.hideText then
        valueText:Hide()
    else
        valueText:Show()
    end

    -- A few client builds expose the rendered digits even when the amount
    -- returned by UnitGetTotalAbsorbs is protected. Read those digits only
    -- after checking for a secret string; otherwise keep the native fallback.
    local visibleAmount
    if not IsSecret(amount) and type(amount) == "number" then
        visibleAmount = amount
    else
        local ok, renderedText = pcall(valueText.GetText, valueText)
        if ok and not IsSecret(renderedText) and type(renderedText) == "string" then
            visibleAmount = tonumber(renderedText)
        end
    end

    if visibleAmount == nil then
        if IsSecret(amount) then
            ApplySecretAbsorb(amount)
        else
            for i = 1, SEGMENT_COUNT do
                segmentBars[i]:SetMinMaxValues(0, 1)
                segmentBars[i]:SetValue(1)
            end
            SetGateValue(1, 1)
        end
        return
    end

    if state.justCast and visibleAmount > 0 then
        -- Capture the actual displayed capacity before measuring damage.
        state.max = visibleAmount
        state.justCast = nil
    end
    for i = 1, SEGMENT_COUNT do
        segmentBars[i]:SetMinMaxValues(0, 1)
        segmentBars[i]:SetValue(1)
    end
    SetGateValue(1, 1)
    UpdateVisibleSegments(visibleAmount)

    if visibleAmount <= 0 then
        valueText:Hide()
        if GetTime() - (state.startedAt or 0) >= 1 then ExpireTracking() end
    end
end

local function BeginTracking(spellID)
    if not IsPWS(spellID) then return end
    state.active = true
    state.expiring = nil
    state.spellID = spellID
    state.max = PWS_BASE_ABSORB[spellID]
    state.justCast = true
    state.visibleSegments = SEGMENT_COUNT
    state.startedAt = GetTime()
    state.expires = GetTime() + PWS_DURATION
    StopAnimations()
    for i = 1, SEGMENT_COUNT do
        segments[i]:SetAlpha(0)
        segmentBars[i]:SetMinMaxValues(0, 1)
        segmentBars[i]:SetValue(1)
    end
    SetGateValue(1, 1)
    AnimateIn()
    UpdateAbsorb()
    local expectedExpiry = state.expires
    C_Timer.After(PWS_DURATION, function()
        if state.active and state.expires == expectedExpiry then
            ExpireTracking()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_AURA")
events:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "ADDON_LOADED" then
        local loadedName = unit
        if loadedName ~= ADDON_NAME then return end
        CopyDefaults()
        lock:SetChecked(db.locked)
        root:EnableMouse(not db.locked)
        hideText:SetChecked(db.hideText)
        scaleSlider:SetValue(db.scale)
        transparencySlider:SetValue(95 - db.transparency)
        curvatureSlider:SetValue(db.curvature)
        ApplyMeterColor()
        RefreshTextFontControls()
        -- A UI reload recreates the frames; explicitly clear their visual
        -- state so stale status bar values can never appear as an active shield.
        for i = 1, SEGMENT_COUNT do
            segments[i]:SetAlpha(0)
            segmentBars[i]:SetMinMaxValues(0, 1)
            segmentBars[i]:SetValue(1)
        end
        state.active = false
        state.expiring = nil
        state.visibleSegments = 0
        SetGateValue(0, 1)
        valueGate:SetValue(0)
        valueText:Hide()
        editHint:SetShown(not db.locked)
        bottomHint:SetShown(not db.locked)
        LayoutSegments()
        UpdateAbsorb()
    elseif event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        if unit == "player" then UpdateAbsorb() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local castGUID, spellID = ...
        if unit == "player" and not IsSecret(spellID) then BeginTracking(spellID) end
    elseif event == "UNIT_AURA" then
        local updateInfo = ...
        if unit == "player" and state.active and type(updateInfo) == "table" and not IsSecret(updateInfo) then
            local removed = updateInfo.removedAuraInstanceIDs
            if type(removed) == "table" and not IsSecret(removed) and state.auraInstanceID then
                for _, auraInstanceID in ipairs(removed) do
                    if not IsSecret(auraInstanceID) and auraInstanceID == state.auraInstanceID then
                        ExpireTracking()
                        break
                    end
                end
            end
            local added = updateInfo.addedAuras
            if type(added) == "table" and not IsSecret(added) then
                for _, aura in ipairs(added) do
                    if type(aura) == "table" and not IsSecret(aura) then
                        local spellID, auraInstanceID = aura.spellId, aura.auraInstanceID
                        if IsPWS(spellID) and not IsSecret(auraInstanceID) then
                            state.auraInstanceID = auraInstanceID
                        end
                    end
                end
            end
        end
        if unit == "player" then UpdateAbsorb() end
    else
        LayoutSegments()
        UpdateAbsorb()
    end
end)

SLASH_PRIESTSHIELDVISUAL1 = "/psv"
SlashCmdList.PRIESTSHIELDVISUAL = function()
    if config:IsShown() then
        config:Hide()
    else
        lock:SetChecked(db.locked)
        hideText:SetChecked(db.hideText)
        scaleSlider:SetValue(db.scale)
        transparencySlider:SetValue(95 - db.transparency)
        curvatureSlider:SetValue(db.curvature)
        ApplyMeterColor()
        RefreshTextFontControls()
        config:Show()
    end
end
