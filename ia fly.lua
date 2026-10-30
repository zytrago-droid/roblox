-- azerty098890 — fly + noclip (optimized, M fixed for AZERTY)
-- P = fly toggle. M (AZERTY physical M) = switch engine. ^ = +10, $ = -10.
-- Ctrl+wheel = GUI scale. Toggles: Noclip ON/OFF, Pitch LOCK/FREE.
--
-- AZERTY mapping (Roblox uses physical QWERTY positions):
--   AZERTY M  -> Enum.KeyCode.Semicolon  (QWERTY ; position)  <-- engine switch
--   AZERTY ^  -> Enum.KeyCode.LeftBracket (QWERTY [ position)
--   AZERTY $  -> Enum.KeyCode.RightBracket (QWERTY ] position)
--
-- Fix vs previous build: isEngineKey no longer uses GetStringForKeyCode
-- (unreliable on Xeno), it matches the physical KeyCode directly.

if _G.azerty098890Loaded then return end
_G.azerty098890Loaded = true

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end
local character = player.Character
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")

--// CONFIG
local CONFIG = {
    FLY_KEY       = Enum.KeyCode.P,
    MIN_SPEED     = 1,
    MAX_SPEED     = 500,
    DEFAULT_SPEED = 50,
    SPEED_STEP    = 10,
    DEFAULT_TRANSP = 0.75,
    PITCH_LOCK    = true,
    NOCLIP_SWEEP_HZ = 15,
    NOCLIP_WATCHDOG_HZ = 4,
    NOCLIP_REAFFIRM_NET_HZ = 2,
    UI_SCALE_MIN  = 0.5,
    UI_SCALE_MAX  = 2.0,
    UI_SCALE_STEP = 0.1,
    ENGINE_DEBOUNCE = 0.2,
    MAX_FORCE     = 9e9,
    ALIGN_MAX_VELOCITY = 500,
    ALIGN_RESPONSIVENESS = 40,
}

local SPEED_UP_KEYS   = {Enum.KeyCode.Six,  Enum.KeyCode.LeftBracket}
local SPEED_DOWN_KEYS = {Enum.KeyCode.Four, Enum.KeyCode.RightBracket}

local ENGINES = {"VELOCITY", "ALIGN", "BODY", "CFRAME"}

local engineIdx       = 1
local flySpeed        = CONFIG.DEFAULT_SPEED
local flyTransparency = CONFIG.DEFAULT_TRANSP
local FLYING          = false
local isFlyToggledOn  = false
local flyGen          = 0
local engineCooldown  = false

local flyConn
local flyDescAddedConn = nil
local flyHumanoidDiedConn = nil
local lvVel, aoOrient, attach
local ap
local bvVel, bgGyro
local savedParts = setmetatable({}, {__mode = "k"})

-- noclip state
local NOCLIP_ALIVE     = true
local NOCLIP_ENABLED   = true
local noclipProcessed  = setmetatable({}, {__mode = "k"})
local noclipSavedCollide = setmetatable({}, {__mode = "k"})
local noclipPartConns  = {}
local noclipGlobalConns = {}
local noclipDescAddedConn = nil
local noclipSweepAccum = 0

local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

local function resetControls()
    CONTROL.F, CONTROL.B, CONTROL.L, CONTROL.R, CONTROL.Q, CONTROL.E = 0, 0, 0, 0, 0, 0
end

local function currentEngine() return ENGINES[engineIdx] end

--// ============================================================
--// NOCLIP (optimized)
--// ============================================================

local function lockPart(part)
    if not NOCLIP_ENABLED then return end
    if not part:IsA("BasePart") then return end
    if noclipProcessed[part] then
        if part.CanCollide then
            part.CanCollide = false
        end
        return
    end
    noclipProcessed[part] = true
    noclipSavedCollide[part] = part.CanCollide
    part.CanCollide = false
    local ok, sig = pcall(function()
        return part:GetPropertyChangedSignal("CanCollide"):Connect(function()
            if NOCLIP_ENABLED and part.CanCollide then
                part.CanCollide = false
            end
        end)
    end)
    if ok and sig then table.insert(noclipPartConns, sig) end
end

local function scanCharacterNoclip(char)
    if not NOCLIP_ENABLED or not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        lockPart(d)
    end
end

local function enforceNoclipSweep()
    if not NOCLIP_ENABLED then return end
    local c = character
    if not c or not c.Parent then return end
    local queue = {c}
    local i = 1
    while i <= #queue do
        local parent = queue[i]
        i = i + 1
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("BasePart") then
                if child.CanCollide then
                    child.CanCollide = false
                end
            elseif child:IsA("Model") or child:IsA("Folder") or child:IsA("Accessory") then
                queue[#queue + 1] = child
            end
        end
    end
end

local function reaffirmOwnership()
    if not (NOCLIP_ENABLED or FLYING) then return end
    local c = character
    if not c or not c.Parent then return end
    local rp = c:FindFirstChild("HumanoidRootPart")
    if rp and rp:IsA("BasePart") and not rp.Anchored then
        pcall(function() rp:SetNetworkOwner(player) end)
    end
end

local function hookCharacterNoclip(newChar)
    if not newChar then return end
    if noclipDescAddedConn then
        pcall(function() noclipDescAddedConn:Disconnect() end)
        noclipDescAddedConn = nil
    end
    local ok, conn = pcall(function()
        return newChar.DescendantAdded:Connect(function(d)
            if NOCLIP_ENABLED and d:IsA("BasePart") then lockPart(d) end
        end)
    end)
    if ok and conn then noclipDescAddedConn = conn end
end

local function disconnectNoclipPartConns()
    for _, conn in ipairs(noclipPartConns) do
        pcall(function() conn:Disconnect() end)
    end
    noclipPartConns = {}
end

local function restoreNoclipCollide()
    for part, origCollide in pairs(noclipSavedCollide) do
        if part and part.Parent then
            pcall(function() part.CanCollide = origCollide end)
        end
    end
    noclipSavedCollide = setmetatable({}, {__mode = "k"})
end

local function startNativeNoclip()
    if not NOCLIP_ENABLED then return end
    scanCharacterNoclip(character)
    hookCharacterNoclip(character)
    reaffirmOwnership()

    noclipSweepAccum = 0
    table.insert(noclipGlobalConns, RunService.Stepped:Connect(function(_, dt)
        if not NOCLIP_ENABLED then return end
        noclipSweepAccum = noclipSweepAccum + dt
        if noclipSweepAccum < 1 / CONFIG.NOCLIP_SWEEP_HZ then return end
        noclipSweepAccum = 0
        enforceNoclipSweep()
    end))

    task.spawn(function()
        local netAccum = 0
        while NOCLIP_ALIVE do
            task.wait(1 / CONFIG.NOCLIP_WATCHDOG_HZ)
            if not NOCLIP_ALIVE then break end
            local c = character
            if c and c.Parent then
                if NOCLIP_ENABLED then
                    scanCharacterNoclip(c)
                    enforceNoclipSweep()
                end
                if NOCLIP_ENABLED or FLYING then
                    netAccum = netAccum + (1 / CONFIG.NOCLIP_WATCHDOG_HZ)
                    if netAccum >= 1 / CONFIG.NOCLIP_REAFFIRM_NET_HZ then
                        netAccum = 0
                        reaffirmOwnership()
                    end
                else
                    netAccum = 0
                end
            end
        end
    end)
end

local function rebindNoclipToCharacter(newChar)
    if not NOCLIP_ALIVE or not NOCLIP_ENABLED then return end
    disconnectNoclipPartConns()
    noclipProcessed = setmetatable({}, {__mode = "k"})
    character = newChar
    scanCharacterNoclip(newChar)
    hookCharacterNoclip(newChar)
    reaffirmOwnership()
end

local function destroyNoclip()
    NOCLIP_ALIVE = false
    disconnectNoclipPartConns()
    if noclipDescAddedConn then
        pcall(function() noclipDescAddedConn:Disconnect() end)
        noclipDescAddedConn = nil
    end
    for _, conn in ipairs(noclipGlobalConns) do
        pcall(function() conn:Disconnect() end)
    end
    noclipGlobalConns = {}
    restoreNoclipCollide()
    noclipProcessed = setmetatable({}, {__mode = "k"})
end

local function setNoclipEnabled(state)
    NOCLIP_ENABLED = state
    if state then
        scanCharacterNoclip(character)
        enforceNoclipSweep()
        reaffirmOwnership()
    else
        disconnectNoclipPartConns()
        restoreNoclipCollide()
        noclipProcessed = setmetatable({}, {__mode = "k"})
    end
end

--// ============================================================
--// GUI
--// ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "azerty098890"
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local uiScale = Instance.new("UIScale", screenGui)
uiScale.Scale = 1

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 250, 0, 220)
mainFrame.Position = UDim2.new(0.5, -125, 0.2, 0)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 32, 35)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)
local uiStroke = Instance.new("UIStroke", mainFrame)
uiStroke.Thickness = 2
uiStroke.Color = Color3.fromRGB(0, 0, 0)

local headerFrame = Instance.new("Frame", mainFrame)
headerFrame.Size = UDim2.new(1, 0, 0, 40)
headerFrame.BackgroundTransparency = 1

local titleLabel = Instance.new("TextLabel", headerFrame)
titleLabel.Size = UDim2.new(1, -115, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "azerty098890"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 18
titleLabel.TextXAlignment = Enum.TextXAlignment.Center

local closeButton = Instance.new("TextButton", headerFrame)
closeButton.Size = UDim2.new(0, 12, 0, 12)
closeButton.Position = UDim2.new(1, -22, 0.5, -6)
closeButton.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
closeButton.Text = ""
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(1, 0)

local minimizeButton = Instance.new("TextButton", headerFrame)
minimizeButton.Size = UDim2.new(0, 12, 0, 12)
minimizeButton.Position = UDim2.new(1, -40, 0.5, -6)
minimizeButton.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
minimizeButton.Text = ""
Instance.new("UICorner", minimizeButton).CornerRadius = UDim.new(1, 0)

local engineButton = Instance.new("TextButton", headerFrame)
engineButton.Size = UDim2.new(0, 66, 0, 22)
engineButton.Position = UDim2.new(1, -112, 0.5, -11)
engineButton.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
engineButton.Font = Enum.Font.GothamBold
engineButton.Text = currentEngine()
engineButton.TextColor3 = Color3.fromRGB(88, 101, 242)
engineButton.TextSize = 10
Instance.new("UICorner", engineButton).CornerRadius = UDim.new(0, 4)
local engineStroke = Instance.new("UIStroke", engineButton)
engineStroke.Color = Color3.fromRGB(88, 101, 242)

local bodyFrame = Instance.new("Frame", mainFrame)
bodyFrame.Size = UDim2.new(1, 0, 1, -40)
bodyFrame.Position = UDim2.new(0, 0, 0, 40)
bodyFrame.BackgroundTransparency = 1

local flyButton = Instance.new("TextButton", bodyFrame)
flyButton.Size = UDim2.new(1, -20, 0, 35)
flyButton.Position = UDim2.new(0, 10, 0, 10)
flyButton.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
flyButton.Font = Enum.Font.Gotham
flyButton.Text = "Fly"
flyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
flyButton.TextSize = 16
Instance.new("UICorner", flyButton).CornerRadius = UDim.new(0, 6)
local flyStroke = Instance.new("UIStroke", flyButton)
flyStroke.Color = Color3.fromRGB(20, 20, 20)

local speedLabel = Instance.new("TextLabel", bodyFrame)
speedLabel.Size = UDim2.new(1, -20, 0, 18)
speedLabel.Position = UDim2.new(0, 10, 0, 52)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.Gotham
speedLabel.Text = "Speed: " .. CONFIG.DEFAULT_SPEED
speedLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedLabel.TextSize = 14
speedLabel.TextXAlignment = Enum.TextXAlignment.Left

local speedSlider = Instance.new("Frame", bodyFrame)
speedSlider.Size = UDim2.new(1, -20, 0, 6)
speedSlider.Position = UDim2.new(0, 10, 0, 76)
speedSlider.BackgroundColor3 = Color3.fromRGB(20, 22, 25)
Instance.new("UICorner", speedSlider).CornerRadius = UDim.new(0, 3)

local sliderBar = Instance.new("Frame", speedSlider)
sliderBar.Size = UDim2.new(0, 0, 1, 0)
sliderBar.BackgroundColor3 = Color3.fromRGB(114, 137, 218)
Instance.new("UICorner", sliderBar).CornerRadius = UDim.new(0, 3)

local sliderHandle = Instance.new("TextButton", speedSlider)
sliderHandle.Size = UDim2.new(0, 18, 0, 18)
sliderHandle.Position = UDim2.new(0, -9, 0.5, -9)
sliderHandle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
sliderHandle.Text = ""
Instance.new("UICorner", sliderHandle).CornerRadius = UDim.new(1, 0)

local transparencyLabel = Instance.new("TextLabel", bodyFrame)
transparencyLabel.Size = UDim2.new(0.5, -15, 0, 28)
transparencyLabel.Position = UDim2.new(0, 10, 0, 92)
transparencyLabel.BackgroundTransparency = 1
transparencyLabel.Font = Enum.Font.Gotham
transparencyLabel.Text = "Transparency:"
transparencyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
transparencyLabel.TextSize = 14
transparencyLabel.TextXAlignment = Enum.TextXAlignment.Left

local transparencyBox = Instance.new("TextBox", bodyFrame)
transparencyBox.Size = UDim2.new(0.5, -15, 0, 28)
transparencyBox.Position = UDim2.new(0.5, 5, 0, 92)
transparencyBox.BackgroundColor3 = Color3.fromRGB(20, 22, 25)
transparencyBox.Font = Enum.Font.Gotham
transparencyBox.Text = tostring(flyTransparency)
transparencyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
transparencyBox.TextSize = 14
transparencyBox.ClearTextOnFocus = false
Instance.new("UICorner", transparencyBox).CornerRadius = UDim.new(0, 4)

local toggleRow = Instance.new("Frame", bodyFrame)
toggleRow.Size = UDim2.new(1, -20, 0, 26)
toggleRow.Position = UDim2.new(0, 10, 0, 128)
toggleRow.BackgroundTransparency = 1

local noclipButton = Instance.new("TextButton", toggleRow)
noclipButton.Size = UDim2.new(0.5, -4, 1, 0)
noclipButton.Position = UDim2.new(0, 0, 0, 0)
noclipButton.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
noclipButton.Font = Enum.Font.GothamBold
noclipButton.Text = "Noclip: ON"
noclipButton.TextColor3 = Color3.fromRGB(88, 200, 120)
noclipButton.TextSize = 11
Instance.new("UICorner", noclipButton).CornerRadius = UDim.new(0, 4)
local noclipStroke = Instance.new("UIStroke", noclipButton)
noclipStroke.Color = Color3.fromRGB(88, 200, 120)

local pitchButton = Instance.new("TextButton", toggleRow)
pitchButton.Size = UDim2.new(0.5, -4, 1, 0)
pitchButton.Position = UDim2.new(0.5, 4, 0, 0)
pitchButton.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
pitchButton.Font = Enum.Font.GothamBold
pitchButton.Text = "Pitch: LOCK"
pitchButton.TextColor3 = Color3.fromRGB(88, 101, 242)
pitchButton.TextSize = 11
Instance.new("UICorner", pitchButton).CornerRadius = UDim.new(0, 4)
local pitchStroke = Instance.new("UIStroke", pitchButton)
pitchStroke.Color = Color3.fromRGB(88, 101, 242)

local statusLabel = Instance.new("TextLabel", bodyFrame)
statusLabel.Size = UDim2.new(1, -20, 0, 16)
statusLabel.Position = UDim2.new(0, 10, 0, 160)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "engine: " .. currentEngine()
statusLabel.TextColor3 = Color3.fromRGB(88, 200, 120)
statusLabel.TextSize = 10
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local function paintEngine()
    engineButton.Text = currentEngine()
    statusLabel.Text = "engine: " .. currentEngine()
end

local function paintPitch()
    if CONFIG.PITCH_LOCK then
        pitchButton.Text = "Pitch: LOCK"
        pitchButton.TextColor3 = Color3.fromRGB(88, 101, 242)
        pitchStroke.Color = Color3.fromRGB(88, 101, 242)
    else
        pitchButton.Text = "Pitch: FREE"
        pitchButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        pitchStroke.Color = Color3.fromRGB(20, 20, 20)
    end
end

local function paintNoclipUI()
    if NOCLIP_ENABLED then
        noclipButton.Text = "Noclip: ON"
        noclipButton.TextColor3 = Color3.fromRGB(88, 200, 120)
        noclipStroke.Color = Color3.fromRGB(88, 200, 120)
    else
        noclipButton.Text = "Noclip: OFF"
        noclipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        noclipStroke.Color = Color3.fromRGB(20, 20, 20)
    end
end

local function paintSpeed()
    local range = CONFIG.MAX_SPEED - CONFIG.MIN_SPEED
    local p = range > 0 and (flySpeed - CONFIG.MIN_SPEED) / range or 0
    sliderBar.Size = UDim2.new(p, 0, 1, 0)
    sliderHandle.Position = UDim2.new(p, -9, 0.5, -9)
    speedLabel.Text = string.format("Speed: %.0f", flySpeed)
end

local function setSpeed(v)
    flySpeed = math.clamp(v, CONFIG.MIN_SPEED, CONFIG.MAX_SPEED)
    paintSpeed()
end

local function updateSlider(input)
    local w = speedSlider.AbsoluteSize.X
    if w <= 0 then return end
    local x = math.clamp(input.Position.X - speedSlider.AbsolutePosition.X, 0, w)
    setSpeed(CONFIG.MIN_SPEED + (x / w) * (CONFIG.MAX_SPEED - CONFIG.MIN_SPEED))
end

paintSpeed()
paintEngine()
paintPitch()
paintNoclipUI()

local function makeDraggable(guiObject, dragHandle)
    local dragging, dragStart, startPos
    dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = guiObject.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            guiObject.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
end
makeDraggable(mainFrame, headerFrame)

local function getMoveVector()
    local cam = workspace.CurrentCamera
    if not cam then return Vector3.new(0, 0, 0) end
    local cf = cam.CFrame
    local move = cf.LookVector * (CONTROL.F + CONTROL.B)
        + cf.RightVector * (CONTROL.L + CONTROL.R)
        + Vector3.new(0, CONTROL.Q + CONTROL.E, 0)
    if move.Magnitude > 1 then move = move.Unit end
    return move
end

local function saveAndApplyFlyVisual()
    savedParts = setmetatable({}, {__mode = "k"})
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            savedParts[part] = { transparency = part.Transparency }
            if part.Name ~= "HumanoidRootPart" then
                pcall(function() part.Transparency = flyTransparency end)
            end
        end
    end
end

local function restoreFlyVisual()
    for part, s in pairs(savedParts) do
        if part and part.Parent then
            pcall(function() part.Transparency = s.transparency end)
        end
    end
    savedParts = setmetatable({}, {__mode = "k"})
end

local function applyTransparencyLive()
    if not FLYING or not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            pcall(function() part.Transparency = flyTransparency end)
        end
    end
end

local function hookFlyVisual(char)
    if not char then return end
    if flyDescAddedConn then
        pcall(function() flyDescAddedConn:Disconnect() end)
        flyDescAddedConn = nil
    end
    local ok, conn = pcall(function()
        return char.DescendantAdded:Connect(function(d)
            if FLYING and d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
                if savedParts[d] == nil then
                    savedParts[d] = { transparency = d.Transparency }
                    pcall(function() d.Transparency = flyTransparency end)
                end
            end
        end)
    end)
    if ok and conn then flyDescAddedConn = conn end
end

local function getMoverParent()
    if character then
        local head = character:FindFirstChild("Head")
        if head and head:IsA("BasePart") then return head end
    end
    return rootPart
end

--// Engine 1: LinearVelocity + AlignOrientation
local function startVelocityEngine(gen)
    local parent = getMoverParent()
    if not parent then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    attach = Instance.new("Attachment")
    attach.Parent = parent

    lvVel = Instance.new("LinearVelocity")
    lvVel.Attachment0 = attach
    lvVel.MaxForce = CONFIG.MAX_FORCE
    lvVel.VectorVelocity = Vector3.new(0, 0, 0)
    lvVel.Parent = parent

    aoOrient = Instance.new("AlignOrientation")
    aoOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
    aoOrient.Attachment0 = attach
    aoOrient.MaxTorque = CONFIG.MAX_FORCE
    aoOrient.Responsiveness = CONFIG.ALIGN_RESPONSIVENESS
    aoOrient.CFrame = parent.CFrame
    aoOrient.Parent = parent

    if humanoid and humanoid.Parent then
        pcall(function() humanoid.PlatformStand = true end)
    end

    local lockedRot = (parent.CFrame - parent.CFrame.Position).Rotation

    flyConn = RunService.Stepped:Connect(function(_, dt)
        if gen ~= flyGen or not FLYING then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            if lvVel then pcall(function() lvVel:Destroy() end); lvVel = nil end
            if aoOrient then pcall(function() aoOrient:Destroy() end); aoOrient = nil end
            if attach then pcall(function() attach:Destroy() end); attach = nil end
            return
        end
        if not lvVel or not lvVel.Parent or not aoOrient or not aoOrient.Parent then return end
        local p = getMoverParent()
        if not p or not p.Parent then return end
        lvVel.VectorVelocity = getMoveVector() * flySpeed

        if CONFIG.PITCH_LOCK then
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                aoOrient.CFrame = CFrame.lookAt(p.Position, p.Position + flat.Unit)
            else
                aoOrient.CFrame = CFrame.new(p.Position) * lockedRot
            end
        else
            aoOrient.CFrame = cam.CFrame
        end
    end)
end

--// Engine 2: AlignPosition + AlignOrientation
local function startAlignEngine(gen)
    local parent = getMoverParent()
    if not parent then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    attach = Instance.new("Attachment")
    attach.Parent = parent

    ap = Instance.new("AlignPosition")
    ap.Mode = Enum.PositionAlignmentMode.OneAttachment
    ap.Attachment0 = attach
    ap.MaxForce = CONFIG.MAX_FORCE
    ap.MaxVelocity = CONFIG.ALIGN_MAX_VELOCITY
    ap.Responsiveness = CONFIG.ALIGN_RESPONSIVENESS
    ap.RigidityEnabled = false
    ap.Position = parent.Position
    ap.Parent = parent

    aoOrient = Instance.new("AlignOrientation")
    aoOrient.Mode = Enum.OrientationAlignmentMode.OneAttachment
    aoOrient.Attachment0 = attach
    aoOrient.MaxTorque = CONFIG.MAX_FORCE
    aoOrient.Responsiveness = CONFIG.ALIGN_RESPONSIVENESS
    aoOrient.CFrame = parent.CFrame
    aoOrient.Parent = parent

    if humanoid and humanoid.Parent then
        pcall(function() humanoid.PlatformStand = true end)
    end

    local lockedRot = (parent.CFrame - parent.CFrame.Position).Rotation
    local targetPos = parent.Position

    flyConn = RunService.Stepped:Connect(function(_, dt)
        if gen ~= flyGen or not FLYING then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            if ap then pcall(function() ap:Destroy() end); ap = nil end
            if aoOrient then pcall(function() aoOrient:Destroy() end); aoOrient = nil end
            if attach then pcall(function() attach:Destroy() end); attach = nil end
            return
        end
        if not ap or not ap.Parent or not aoOrient or not aoOrient.Parent then return end
        local p = getMoverParent()
        if not p or not p.Parent then return end
        targetPos = targetPos + getMoveVector() * flySpeed * dt
        ap.Position = targetPos

        if CONFIG.PITCH_LOCK then
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                aoOrient.CFrame = CFrame.lookAt(targetPos, targetPos + flat.Unit)
            else
                aoOrient.CFrame = CFrame.new(targetPos) * lockedRot
            end
        else
            aoOrient.CFrame = cam.CFrame
        end
    end)
end

--// Engine 3: BodyVelocity + BodyGyro
local function startBodyEngine(gen)
    local parent = getMoverParent()
    if not parent then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    bgGyro = Instance.new("BodyGyro")
    bgGyro.P = 9e4
    bgGyro.D = 500
    bgGyro.MaxTorque = Vector3.new(CONFIG.MAX_FORCE, CONFIG.MAX_FORCE, CONFIG.MAX_FORCE)
    bgGyro.CFrame = parent.CFrame
    bgGyro.Parent = parent

    bvVel = Instance.new("BodyVelocity")
    bvVel.Velocity = Vector3.new(0, 0, 0)
    bvVel.MaxForce = Vector3.new(CONFIG.MAX_FORCE, CONFIG.MAX_FORCE, CONFIG.MAX_FORCE)
    bvVel.Parent = parent

    if humanoid and humanoid.Parent then
        pcall(function() humanoid.PlatformStand = true end)
    end

    local lockedRot = (parent.CFrame - parent.CFrame.Position).Rotation

    flyConn = RunService.Stepped:Connect(function(_, dt)
        if gen ~= flyGen or not FLYING then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            if bvVel then pcall(function() bvVel:Destroy() end); bvVel = nil end
            if bgGyro then pcall(function() bgGyro:Destroy() end); bgGyro = nil end
            return
        end
        if not bvVel or not bvVel.Parent or not bgGyro or not bgGyro.Parent then return end
        local p = getMoverParent()
        if not p or not p.Parent then return end
        bvVel.Velocity = getMoveVector() * flySpeed

        if CONFIG.PITCH_LOCK then
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                bgGyro.CFrame = CFrame.lookAt(p.Position, p.Position + flat.Unit)
            else
                bgGyro.CFrame = CFrame.new(p.Position) * lockedRot
            end
        else
            bgGyro.CFrame = cam.CFrame
        end
    end)
end

--// Engine 4: CFrame direct on Head
local function startCFrameEngine(gen)
    local head = character and character:FindFirstChild("Head")
    if not head then return end
    local cam = workspace.CurrentCamera
    if not cam then return end

    if humanoid and humanoid.Parent then
        pcall(function() humanoid.PlatformStand = true end)
    end
    pcall(function() head.Anchored = true end)
    local lockedRot = (head.CFrame - head.CFrame.Position).Rotation

    flyConn = RunService.Stepped:Connect(function(_, dt)
        if gen ~= flyGen or not FLYING then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            return
        end
        local h = character and character:FindFirstChild("Head")
        if not h or not h.Parent then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            return
        end
        local pos = h.Position + getMoveVector() * flySpeed * dt

        if CONFIG.PITCH_LOCK then
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.05 then
                h.CFrame = CFrame.lookAt(pos, pos + flat.Unit)
            else
                h.CFrame = CFrame.new(pos)
            end
        else
            h.CFrame = CFrame.new(pos) * cam.CFrame.Rotation
        end
    end)
end

local function stopFlyInternal(preserveToggle)
    if not preserveToggle then isFlyToggledOn = false end
    flyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    flyStroke.Color = Color3.fromRGB(20, 20, 20)
    if not FLYING then return end

    FLYING = false
    flyGen += 1

    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if flyDescAddedConn then
        pcall(function() flyDescAddedConn:Disconnect() end)
        flyDescAddedConn = nil
    end
    if lvVel then pcall(function() lvVel:Destroy() end); lvVel = nil end
    if aoOrient then pcall(function() aoOrient:Destroy() end); aoOrient = nil end
    if attach then pcall(function() attach:Destroy() end); attach = nil end
    if ap then pcall(function() ap:Destroy() end); ap = nil end
    if bvVel then pcall(function() bvVel:Destroy() end); bvVel = nil end
    if bgGyro then pcall(function() bgGyro:Destroy() end); bgGyro = nil end

    if character and character.Parent then
        local head = character:FindFirstChild("Head")
        if head then pcall(function() head.Anchored = false end) end
    end

    if humanoid and humanoid.Parent then
        pcall(function() humanoid.PlatformStand = false end)
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end

    restoreFlyVisual()
    resetControls()
end

local function startFlyInternal(preserveToggle)
    if FLYING then
        if not preserveToggle then isFlyToggledOn = true end
        return
    end
    if not character or not character.Parent then return end
    if humanoid and humanoid.Health <= 0 then return end
    if humanoid and not humanoid.Parent then return end
    if not preserveToggle then isFlyToggledOn = true end

    FLYING = true
    flyGen += 1
    local gen = flyGen

    saveAndApplyFlyVisual()
    hookFlyVisual(character)

    local eng = currentEngine()
    if eng == "VELOCITY" then startVelocityEngine(gen)
    elseif eng == "ALIGN" then startAlignEngine(gen)
    elseif eng == "BODY" then startBodyEngine(gen)
    else startCFrameEngine(gen) end

    flyButton.TextColor3 = Color3.fromRGB(88, 101, 242)
    flyStroke.Color = Color3.fromRGB(88, 101, 242)
end

local function toggleFly()
    if isFlyToggledOn then stopFlyInternal(false) else startFlyInternal(false) end
end

local function nextEngine()
    if engineCooldown then return end
    engineCooldown = true
    engineIdx = (engineIdx % #ENGINES) + 1
    paintEngine()
    if FLYING then
        stopFlyInternal(true)
        startFlyInternal(true)
    end
    task.wait(CONFIG.ENGINE_DEBOUNCE)
    engineCooldown = false
end

--// Keybinds
local keyMap = {
    [Enum.KeyCode.W] = "F", [Enum.KeyCode.S] = "B",
    [Enum.KeyCode.A] = "L", [Enum.KeyCode.D] = "R",
    [Enum.KeyCode.Q] = "Q", [Enum.KeyCode.E] = "E",
}
local valueMap = {
    [Enum.KeyCode.W] =  1, [Enum.KeyCode.S] = -1,
    [Enum.KeyCode.A] = -1, [Enum.KeyCode.D] =  1,
    [Enum.KeyCode.Q] = -1, [Enum.KeyCode.E] =  1,
}

local function isSpeedUp(kc)
    for _, k in ipairs(SPEED_UP_KEYS) do if kc == k then return true end end
    local ok, s = pcall(function() return UserInputService:GetStringForKeyCode(kc) end)
    return ok and s == "^"
end
local function isSpeedDown(kc)
    for _, k in ipairs(SPEED_DOWN_KEYS) do if kc == k then return true end end
    local ok, s = pcall(function() return UserInputService:GetStringForKeyCode(kc) end)
    return ok and s == "$"
end

-- FIX: engine key matched by physical KeyCode, no GetStringForKeyCode.
-- AZERTY physical M = Enum.KeyCode.Semicolon (QWERTY ; position).
-- QWERTY physical M = Enum.KeyCode.M.
local function isEngineKey(kc)
    return kc == Enum.KeyCode.Semicolon or kc == Enum.KeyCode.M
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == CONFIG.FLY_KEY then toggleFly(); return end
    if isEngineKey(input.KeyCode) then nextEngine(); return end
    if isSpeedUp(input.KeyCode)   then setSpeed(flySpeed + CONFIG.SPEED_STEP); return end
    if isSpeedDown(input.KeyCode) then setSpeed(flySpeed - CONFIG.SPEED_STEP); return end
    local k = keyMap[input.KeyCode]
    if k then CONTROL[k] = valueMap[input.KeyCode] end
end)
UserInputService.InputEnded:Connect(function(input)
    local k = keyMap[input.KeyCode]
    if k then CONTROL[k] = 0 end
end)

UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then return end
    local s = uiScale.Scale + input.Position.Z * CONFIG.UI_SCALE_STEP
    uiScale.Scale = math.clamp(s, CONFIG.UI_SCALE_MIN, CONFIG.UI_SCALE_MAX)
end)

local function bindHumanoid(h)
    if not h then return end
    if flyHumanoidDiedConn then
        pcall(function() flyHumanoidDiedConn:Disconnect() end)
        flyHumanoidDiedConn = nil
    end
    flyHumanoidDiedConn = h.Died:Connect(function()
        if FLYING then stopFlyInternal(true) end
    end)
end
bindHumanoid(humanoid)

player.CharacterAdded:Connect(function(newChar)
    if FLYING then stopFlyInternal(true) end
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    rootPart = newChar:WaitForChild("HumanoidRootPart")
    bindHumanoid(humanoid)
    if humanoid then
        pcall(function() humanoid.PlatformStand = false end)
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end

    if NOCLIP_ALIVE then
        rebindNoclipToCharacter(newChar)
    end

    if isFlyToggledOn then
        task.wait(0.1)
        if isFlyToggledOn and character == newChar then
            startFlyInternal(true)
        end
    end
end)

closeButton.MouseButton1Click:Connect(function()
    stopFlyInternal(false)
    destroyNoclip()
    _G.azerty098890Loaded = false
    screenGui:Destroy()
end)

flyButton.MouseButton1Click:Connect(toggleFly)
engineButton.MouseButton1Click:Connect(nextEngine)

noclipButton.MouseButton1Click:Connect(function()
    setNoclipEnabled(not NOCLIP_ENABLED)
    paintNoclipUI()
end)

pitchButton.MouseButton1Click:Connect(function()
    CONFIG.PITCH_LOCK = not CONFIG.PITCH_LOCK
    paintPitch()
end)

local isMinimized = false
minimizeButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    bodyFrame.Visible = not isMinimized
    local target = isMinimized and UDim2.new(0, 250, 0, 40) or UDim2.new(0, 250, 0, 220)
    TweenService:Create(mainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Size = target}):Play()
end)

transparencyBox.FocusLost:Connect(function()
    local num = tonumber(transparencyBox.Text)
    if num and num >= 0 and num <= 1 then
        flyTransparency = num
        applyTransparencyLive()
    else
        transparencyBox.Text = tostring(flyTransparency)
    end
end)

local isDraggingSlider = false
sliderHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSlider = true
        updateSlider(input)
    end
end)
speedSlider.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSlider = true
        updateSlider(input)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingSlider = false
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if isDraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        updateSlider(input)
    end
end)

startNativeNoclip()
