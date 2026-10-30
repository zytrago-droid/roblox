-- azerty098890
-- FlyGuiV8 — Xeno-compatible
-- Toggle fly: P or the Fly button. Move: W/A/S/D (camera-relative), Q/E down/up.
-- Speed: ^ = +10, $ = -10. CF button switches body-mover <-> cframe mode. Ctrl+wheel resizes the GUI.

if _G.FlyGuiV8Loaded then return end
_G.FlyGuiV8Loaded = true

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local player = Players.LocalPlayer
if not player.Character then player.CharacterAdded:Wait() end
local character = player.Character
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")

--// Config
local CONFIG = {
    TOGGLE_KEY        = Enum.KeyCode.P,
    MIN_SPEED         = 1,
    MAX_SPEED         = 500,
    DEFAULT_SPEED     = 50,
    SPEED_STEP        = 10,
    DEFAULT_TRANSP    = 0.75,
    USE_CFRAME        = true,
    PITCH_LOCK        = false,  -- cframe mode only. false = follow camera rotation, true = upright yaw only.
    BODY_FACE_CAMERA  = false,  -- body-mover mode only. false = body keeps its orientation, camera stays free.
                                --                                true = body rotates with camera (old behavior).
    UI_SCALE_MIN      = 0.5,
    UI_SCALE_MAX      = 2.0,
    UI_SCALE_STEP     = 0.1,
}

local SPEED_UP_KEY   = Enum.KeyCode.Six
local SPEED_DOWN_KEY = Enum.KeyCode.Four

local flySpeed        = CONFIG.DEFAULT_SPEED
local flyTransparency = CONFIG.DEFAULT_TRANSP
local useCFrameFly    = CONFIG.USE_CFRAME
local FLYING          = false
local isFlyToggledOn  = false
local flyGen          = 0
local flyConn, noclipConn, bodyLoopConn
local currentGyro, currentVel
local headWasAnchored = false

local CONTROL = {F = 0, B = 0, L = 0, R = 0, Q = 0, E = 0}

local function resetControls()
    CONTROL.F, CONTROL.B, CONTROL.L, CONTROL.R, CONTROL.Q, CONTROL.E = 0, 0, 0, 0, 0, 0
end

--// GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "azerty098890"
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local uiScale = Instance.new("UIScale", screenGui)
uiScale.Scale = 1

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 250, 0, 170)
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
titleLabel.Size = UDim2.new(1, -110, 1, 0)
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

local cframeToggle = Instance.new("TextButton", headerFrame)
cframeToggle.Size = UDim2.new(0, 56, 0, 22)
cframeToggle.Position = UDim2.new(1, -102, 0.5, -11)
cframeToggle.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
cframeToggle.Font = Enum.Font.GothamBold
cframeToggle.Text = "CF: OFF"
cframeToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
cframeToggle.TextSize = 12
Instance.new("UICorner", cframeToggle).CornerRadius = UDim.new(0, 4)
local cframeStroke = Instance.new("UIStroke", cframeToggle)
cframeStroke.Color = Color3.fromRGB(20, 20, 20)

local function paintCFButton()
    if useCFrameFly then
        cframeToggle.Text = "CF: ON"
        cframeToggle.TextColor3 = Color3.fromRGB(88, 101, 242)
        cframeStroke.Color = Color3.fromRGB(88, 101, 242)
        cframeToggle.BackgroundColor3 = Color3.fromRGB(60, 70, 110)
    else
        cframeToggle.Text = "CF: OFF"
        cframeToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
        cframeStroke.Color = Color3.fromRGB(20, 20, 20)
        cframeToggle.BackgroundColor3 = Color3.fromRGB(44, 46, 51)
    end
end
paintCFButton()

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

local speedSliderLabel = Instance.new("TextLabel", bodyFrame)
speedSliderLabel.Size = UDim2.new(1, -20, 0, 20)
speedSliderLabel.Position = UDim2.new(0, 10, 0, 55)
speedSliderLabel.BackgroundTransparency = 1
speedSliderLabel.Font = Enum.Font.Gotham
speedSliderLabel.Text = "Speed: " .. CONFIG.DEFAULT_SPEED
speedSliderLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
speedSliderLabel.TextSize = 14
speedSliderLabel.TextXAlignment = Enum.TextXAlignment.Left

local speedSlider = Instance.new("Frame", bodyFrame)
speedSlider.Size = UDim2.new(1, -20, 0, 6)
speedSlider.Position = UDim2.new(0, 10, 0, 80)
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
transparencyLabel.Size = UDim2.new(0.5, -15, 0, 30)
transparencyLabel.Position = UDim2.new(0, 10, 0, 95)
transparencyLabel.BackgroundTransparency = 1
transparencyLabel.Font = Enum.Font.Gotham
transparencyLabel.Text = "Transparency:"
transparencyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
transparencyLabel.TextSize = 14
transparencyLabel.TextXAlignment = Enum.TextXAlignment.Left

local transparencyBox = Instance.new("TextBox", bodyFrame)
transparencyBox.Size = UDim2.new(0.5, -15, 0, 30)
transparencyBox.Position = UDim2.new(0.5, 5, 0, 95)
transparencyBox.BackgroundColor3 = Color3.fromRGB(20, 22, 25)
transparencyBox.Font = Enum.Font.Gotham
transparencyBox.Text = tostring(CONFIG.DEFAULT_TRANSP)
transparencyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
transparencyBox.TextSize = 14
transparencyBox.ClearTextOnFocus = false
Instance.new("UICorner", transparencyBox).CornerRadius = UDim.new(0, 4)

--// Drag
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
            local delta = input.Position - dragStart
            guiObject.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end
makeDraggable(mainFrame, headerFrame)

--// Speed slider
local function paintSpeedSlider()
    local range = CONFIG.MAX_SPEED - CONFIG.MIN_SPEED
    local p = range > 0 and (flySpeed - CONFIG.MIN_SPEED) / range or 0
    sliderBar.Size = UDim2.new(p, 0, 1, 0)
    sliderHandle.Position = UDim2.new(p, -9, 0.5, -9)
    speedSliderLabel.Text = string.format("Speed: %.0f", flySpeed)
end

local function setSpeed(v)
    flySpeed = math.clamp(v, CONFIG.MIN_SPEED, CONFIG.MAX_SPEED)
    paintSpeedSlider()
end

local function updateSlider(input)
    local width = speedSlider.AbsoluteSize.X
    if width <= 0 then return end
    local x = math.clamp(input.Position.X - speedSlider.AbsolutePosition.X, 0, width)
    local p = x / width
    setSpeed(CONFIG.MIN_SPEED + p * (CONFIG.MAX_SPEED - CONFIG.MIN_SPEED))
end

paintSpeedSlider()

--// Noclip
local function NoclipLoop()
    if not character then return end
    for _, child in ipairs(character:GetDescendants()) do
        if child:IsA("BasePart") and child.CanCollide then
            child.CanCollide = false
        end
    end
end

--// Move vector
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

--// Destroy leftover body movers
local function destroyBodyMovers()
    if currentGyro then
        pcall(function() currentGyro:Destroy() end)
        currentGyro = nil
    end
    if currentVel then
        pcall(function() currentVel:Destroy() end)
        currentVel = nil
    end
end

--// CFrame mover
local function startCFrameFlyLoop()
    local char = character
    local head = char and char:FindFirstChild("Head")
    if FLYING or not head then return end
    FLYING = true
    flyGen += 1
    local gen = flyGen

    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = false end
    end
    if humanoid then humanoid.PlatformStand = true end
    headWasAnchored = head.Anchored
    head.Anchored = true

    flyConn = RunService.Heartbeat:Connect(function(dt)
        if gen ~= flyGen or not FLYING then
            if flyConn then flyConn:Disconnect(); flyConn = nil end
            return
        end
        local h = char and char:FindFirstChild("Head")
        local cam = workspace.CurrentCamera
        if not h or not h.Parent or not cam then
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

--// BodyMover mover
local function startBodyMoverFlyLoop()
    local rp, hum = rootPart, humanoid
    if FLYING or not rp or not hum then return end
    FLYING = true
    flyGen += 1
    local gen = flyGen

    destroyBodyMovers()
    noclipConn = RunService.Heartbeat:Connect(NoclipLoop)

    -- FIX: capture the body's orientation at fly start. In BODY_FACE_CAMERA=false mode
    -- we hold this rotation for the whole flight so the camera never gets dragged.
    local lockedRot = (rp.CFrame - rp.CFrame.Position).Rotation

    local gyro = Instance.new("BodyGyro")
    gyro.P = 9e4
    gyro.D = 500
    gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
    gyro.CFrame = rp.CFrame
    gyro.Parent = rp
    currentGyro = gyro

    local vel = Instance.new("BodyVelocity")
    vel.Velocity = Vector3.new(0, 0, 0)
    vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
    vel.Parent = rp
    currentVel = vel

    hum.PlatformStand = true

    bodyLoopConn = RunService.Heartbeat:Connect(function()
        if gen ~= flyGen or not FLYING then
            if bodyLoopConn then bodyLoopConn:Disconnect(); bodyLoopConn = nil end
            destroyBodyMovers()
            if hum and hum.Parent then
                hum.PlatformStand = false
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            end
            resetControls()
            return
        end
        local cam = workspace.CurrentCamera
        if not rp.Parent then return end
        vel.Velocity = getMoveVector() * flySpeed

        if CONFIG.BODY_FACE_CAMERA and cam then
            -- old behavior: body rotates with the camera (can drag camera in follow/shiftlock games)
            if CONFIG.PITCH_LOCK then
                local look = cam.CFrame.LookVector
                local flat = Vector3.new(look.X, 0, look.Z)
                if flat.Magnitude > 0.05 then
                    gyro.CFrame = CFrame.lookAt(rp.Position, rp.Position + flat.Unit)
                end
            else
                gyro.CFrame = cam.CFrame
            end
        else
            -- new default: body keeps its orientation, camera stays free
            gyro.CFrame = CFrame.new(rp.Position) * lockedRot
        end
    end)
end

--// Weak-keys state table
local savedState = setmetatable({}, {__mode = "k"})

local function captureAndApplyFlyVisual(state)
    if not character then return end
    if state then
        savedState = setmetatable({}, {__mode = "k"})
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                savedState[part] = {
                    transparency = part.Transparency,
                    canCollide   = part.CanCollide,
                }
                if part.Name ~= "HumanoidRootPart" then
                    part.Transparency = flyTransparency
                end
                part.CanCollide = false
            end
        end
    else
        for part, s in pairs(savedState) do
            if part and part.Parent then
                part.Transparency = s.transparency
                part.CanCollide   = s.canCollide
            end
        end
        savedState = setmetatable({}, {__mode = "k"})
    end
end

local function applyTransparencyLive()
    if not FLYING or not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            part.Transparency = flyTransparency
        end
    end
end

--// Stop
local function stopFly()
    if not FLYING then return end
    FLYING = false
    flyGen += 1
    if flyConn then flyConn:Disconnect(); flyConn = nil end
    if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    if bodyLoopConn then bodyLoopConn:Disconnect(); bodyLoopConn = nil end
    destroyBodyMovers()
    resetControls()
    if character then
        local head = character:FindFirstChild("Head")
        if head then head.Anchored = headWasAnchored end
    end
    headWasAnchored = false
    if humanoid and humanoid.Parent then
        humanoid.PlatformStand = false
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    captureAndApplyFlyVisual(false)
end

--// Toggle
local function setFlying(state)
    isFlyToggledOn = state
    flyButton.TextColor3 = state and Color3.fromRGB(88, 101, 242) or Color3.fromRGB(255, 255, 255)
    flyStroke.Color = state and Color3.fromRGB(88, 101, 242) or Color3.fromRGB(20, 20, 20)
    if not character or not character.Parent then return end
    if state then
        if FLYING then return end
        resetControls()
        captureAndApplyFlyVisual(true)
        if useCFrameFly then startCFrameFlyLoop() else startBodyMoverFlyLoop() end
    else
        stopFly()
    end
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

local function speedDeltaFor(input)
    local kc = input.KeyCode
    if kc == SPEED_UP_KEY then return CONFIG.SPEED_STEP end
    if kc == SPEED_DOWN_KEY then return -CONFIG.SPEED_STEP end
    local ok, s = pcall(function() return UserInputService:GetStringForKeyCode(kc) end)
    if ok and s then
        if s == "^" then return CONFIG.SPEED_STEP end
        if s == "$" then return -CONFIG.SPEED_STEP end
    end
    return nil
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == CONFIG.TOGGLE_KEY then
        setFlying(not isFlyToggledOn)
        return
    end
    local d = speedDeltaFor(input)
    if d then setSpeed(flySpeed + d); return end
    local k = keyMap[input.KeyCode]
    if k then CONTROL[k] = valueMap[input.KeyCode] end
end)
UserInputService.InputEnded:Connect(function(input)
    local k = keyMap[input.KeyCode]
    if k then CONTROL[k] = 0 end
end)

-- Ctrl+wheel resizes the GUI
UserInputService.InputChanged:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
    if not UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
        and not UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then return end
    local nextScale = uiScale.Scale + input.Position.Z * CONFIG.UI_SCALE_STEP
    uiScale.Scale = math.clamp(nextScale, CONFIG.UI_SCALE_MIN, CONFIG.UI_SCALE_MAX)
end)

--// Died + Respawn
local function bindHumanoidSignals(h)
    if not h then return end
    h.Died:Connect(function()
        if FLYING then stopFly() end
    end)
end
bindHumanoidSignals(humanoid)

player.CharacterAdded:Connect(function(newChar)
    if FLYING then stopFly() end
    character = newChar
    humanoid = newChar:WaitForChild("Humanoid")
    rootPart = newChar:WaitForChild("HumanoidRootPart")
    bindHumanoidSignals(humanoid)
    if humanoid then
        humanoid.PlatformStand = false
        pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
    if isFlyToggledOn then
        task.wait(0.1)
        if isFlyToggledOn and character == newChar then
            setFlying(true)
        end
    end
end)

--// GUI events
closeButton.MouseButton1Click:Connect(function()
    setFlying(false)
    _G.FlyGuiV8Loaded = false
    screenGui:Destroy()
end)

flyButton.MouseButton1Click:Connect(function()
    setFlying(not isFlyToggledOn)
end)

cframeToggle.MouseButton1Click:Connect(function()
    useCFrameFly = not useCFrameFly
    paintCFButton()
    if isFlyToggledOn and FLYING then
        stopFly()
        task.wait()
        if isFlyToggledOn and character and character.Parent then
            captureAndApplyFlyVisual(true)
            if useCFrameFly then startCFrameFlyLoop() else startBodyMoverFlyLoop() end
        end
    end
end)

local isMinimized = false
minimizeButton.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    bodyFrame.Visible = not isMinimized
    local target = isMinimized and UDim2.new(0, 250, 0, 40) or UDim2.new(0, 250, 0, 170)
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
