local config = {
    usePrediction      = true,
    keybind            = Enum.KeyCode.E,
    resolver           = false,
    smoothness         = 1,
    hitPart            = "HumanoidRootPart",
    universal          = true,
    aimbotMode         = "toggle",
    aimbotEnabled      = false,
    predictionMul      = 0.13,
    fovVisible         = true,   -- FOV circle visibility
    fovSize            = 50,     -- FOV circle radius in pixels
    fovColor           = Color3.new(1, 1, 1),
    tracerEnabled      = true,   -- (default; now controlled via master toggle)
    tracerColor        = Color3.new(1, 1, 1)  -- default white
}

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local currentCamera    = workspace.CurrentCamera

local localPlayer      = Players.LocalPlayer
local mouse            = localPlayer:GetMouse()

local victim           = nil
local velocity         = Vector3.new(0, 0, 0)
local oldPos           = nil

local aimbotConnection    = nil
local velocityConnection  = nil

local lockActive       = false

local orbitConnection  = nil
local orbitAngle       = 0

local camera = currentCamera  -- alias for clarity

local ESP_SETTINGS = {
    BoxOutlineColor = Color3.new(0, 0, 0),
    BoxColor = Color3.new(1, 1, 1),
    FilledBoxColor = Color3.new(1, 1, 1),
    NameColor = Color3.new(1, 1, 1),
    HealthOutlineColor = Color3.new(0, 0, 0),
    HealthHighColor = Color3.new(0, 1, 0),
    HealthLowColor = Color3.new(1, 0, 0),
    HealthColor = Color3.new(1, 1, 1),
    AnimatedHealthBars = false,
    DistanceColor = Color3.new(1, 1, 1),
    HealthBasedColor = false,
    CharSize = Vector2.new(4, 6),
    Teamcheck = false,
    WallCheck = false,
    Enabled = false,       -- enable via GUI
    ShowFilledBox = false,
    ShowBox = false,
    BoxType = "Normal",    -- "Normal" or "Corner"
    ShowName = false,
    ShowHealth = false,
    ShowDistance = false,
    ShowTracer = false,    -- Master toggle for tracer drawing
    TracerThickness = 1,
    TracerPosition = "Bottom",  -- "Top", "Middle", or "Bottom"
    TracerColor = Color3.new(1, 1, 1)
}

local cache = {}  -- cache for each player's ESP drawings

local bones = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "LowerTorso"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"}
}

local function create(class, properties)
    local drawing = Drawing.new(class)
    for property, value in pairs(properties) do
        drawing[property] = value
    end
    return drawing
end

local function createEsp(player)
    local esp = {
        tracer = create("Line", {
            Thickness = ESP_SETTINGS.TracerThickness,
            Color = ESP_SETTINGS.TracerColor,
            Transparency = 1,
            Visible = false
        }),
        boxOutline = create("Square", {
            Color = ESP_SETTINGS.BoxOutlineColor,
            Thickness = 3,
            Filled = false,
            Visible = false
        }),
        box = create("Square", {
            Color = ESP_SETTINGS.BoxColor,
            Thickness = 1,
            Filled = false,
            Visible = false
        }),
        filledBox = create("Square", {
            Color = ESP_SETTINGS.FilledBoxColor,
            Thickness = 1,
            Transparency = 0.3,
            Filled = true,
            Visible = false
        }),
        name = create("Text", {
            Color = ESP_SETTINGS.NameColor,
            Outline = true,
            Center = true,
            Size = 13,
            Visible = false
        }),
        healthOutline = create("Line", {
            Thickness = 3,
            Color = ESP_SETTINGS.HealthOutlineColor,
            Visible = false
        }),
        health = create("Line", {
            Thickness = 1,
            Visible = false
        }),
        distance = create("Text", {
            Color = Color3.new(1, 1, 1),
            Size = 12,
            Outline = true,
            Center = true,
            Visible = false
        }),
        boxLines = {},
    }
    cache[player] = esp
end

local function isPlayerBehindWall(player)
    local character = player.Character
    if not character then return false end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local ray = Ray.new(camera.CFrame.Position, (rootPart.Position - camera.CFrame.Position).Unit * (rootPart.Position - camera.CFrame.Position).Magnitude)
    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {localPlayer.Character, character})
    
    return hit and hit:IsA("Part")
end

local function removeEsp(player)
    local esp = cache[player]
    if not esp then return end

    for _, drawing in pairs(esp) do
        if type(drawing) == "table" and drawing.Remove then
            drawing:Remove()
        end
    end
    cache[player] = nil
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function updateEsp()
    for player, esp in pairs(cache) do
        local character = player.Character
        local team = player.Team
        if character and (not ESP_SETTINGS.Teamcheck or (team and team ~= localPlayer.Team)) then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")
            local humanoid = character:FindFirstChild("Humanoid")
            local isBehindWall = ESP_SETTINGS.WallCheck and isPlayerBehindWall(player)
            local shouldShow = ESP_SETTINGS.Enabled and (not isBehindWall)
            if rootPart and head and humanoid and shouldShow then
                local position, onScreen = camera:WorldToViewportPoint(rootPart.Position)
                if onScreen then
                    local hrp2D = camera:WorldToViewportPoint(rootPart.Position)
                    local charSize = (camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0)).Y - camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2.6, 0)).Y) / 2
                    local boxSize = Vector2.new(math.floor(charSize * 1.4), math.floor(charSize * 1.9))
                    local boxPosition = Vector2.new(math.floor(hrp2D.X - charSize * 1.4 / 2), math.floor(hrp2D.Y - charSize * 1.6 / 2))

                    -- Name
                    if ESP_SETTINGS.ShowName then
                        esp.name.Visible = true
                        esp.name.Text = string.lower(player.Name)
                        esp.name.Position = Vector2.new(boxSize.X / 2 + boxPosition.X, boxPosition.Y - 16)
                        esp.name.Color = ESP_SETTINGS.NameColor
                    else
                        esp.name.Visible = false
                    end

                    -- Filled Box
                    if ESP_SETTINGS.ShowFilledBox then
                        esp.filledBox.Position = boxPosition
                        esp.filledBox.Size = boxSize
                        esp.filledBox.Color = ESP_SETTINGS.FilledBoxColor
                        esp.filledBox.Visible = true
                    else
                        esp.filledBox.Visible = false
                    end

                    -- Box (Normal or Corner)
                    if ESP_SETTINGS.ShowBox then
                        if ESP_SETTINGS.BoxType == "Normal" then
                            esp.boxOutline.Size = boxSize
                            esp.boxOutline.Position = boxPosition
                            esp.box.Size = boxSize
                            esp.box.Position = boxPosition
                            esp.box.Color = ESP_SETTINGS.BoxColor
                            esp.box.Visible = true
                            esp.boxOutline.Visible = true
                            for _, line in ipairs(esp.boxLines) do
                                line:Remove()
                            end
                            esp.boxLines = {}
                        elseif ESP_SETTINGS.BoxType == "Corner" then
                            local lineW = (boxSize.X / 3)
                            local lineH = (boxSize.Y / 3)
                        
                            if #esp.boxLines == 0 then
                                for i = 1, 16 do
                                    local boxLine = create("Line", {
                                        Thickness = 1,
                                        Color = ESP_SETTINGS.BoxColor,
                                        Transparency = 1,
                                        Visible = true
                                    })
                                    table.insert(esp.boxLines, boxLine)
                                end
                            end
                        
                            local boxLines = esp.boxLines
                        
                            -- Outline lines
                            for i = 1, 8 do
                                boxLines[i].Thickness = 2
                                boxLines[i].Color = ESP_SETTINGS.BoxOutlineColor
                                boxLines[i].Transparency = 1
                            end
                        
                            boxLines[1].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[1].To = Vector2.new(boxPosition.X, boxPosition.Y + lineH)
                        
                            boxLines[2].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[2].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y)
                        
                            boxLines[3].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y)
                            boxLines[3].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
                        
                            boxLines[4].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
                            boxLines[4].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + lineH)
                        
                            boxLines[5].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[5].To = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
                        
                            boxLines[6].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
                            boxLines[6].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y + boxSize.Y)
                        
                            boxLines[7].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y + boxSize.Y)
                            boxLines[7].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
                        
                            boxLines[8].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[8].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
                        
                            -- Inline lines (using same positions)
                            for i = 9, 16 do
                                boxLines[i].From = boxLines[i - 8].From
                                boxLines[i].To = boxLines[i - 8].To
                                boxLines[i].Color = ESP_SETTINGS.BoxColor
                            end
                        
                            for _, line in ipairs(boxLines) do
                                line.Visible = true
                            end
                            esp.box.Visible = false
                            esp.boxOutline.Visible = false
                        end
                    else
                        esp.box.Visible = false
                        esp.boxOutline.Visible = false
                        for _, line in ipairs(esp.boxLines) do
                            line:Remove()
                        end
                        esp.boxLines = {}
                    end

                    -- Health Bar
                    if ESP_SETTINGS.ShowHealth then
                        esp.healthOutline.Visible = true
                        esp.health.Visible = true
                        local health = humanoid.Health
                        if ESP_SETTINGS.AnimatedHealthBars then
                            health = lerp(health, humanoid.Health, 0.3)
                        end
                        local healthPercentage = health / humanoid.MaxHealth
                        local healthBarHeight = healthPercentage * boxSize.Y
                        esp.healthOutline.From = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y + 1)
                        esp.healthOutline.To = Vector2.new(boxPosition.X - 6, boxPosition.Y - 1)
                        esp.health.From = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y)
                        esp.health.To = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y - healthBarHeight)
                        if ESP_SETTINGS.HealthBasedColor then
                            esp.health.Color = ESP_SETTINGS.HealthLowColor:Lerp(ESP_SETTINGS.HealthHighColor, healthPercentage)
                        else
                            esp.health.Color = ESP_SETTINGS.HealthColor
                        end
                    else
                        esp.healthOutline.Visible = false
                        esp.health.Visible = false
                    end

                    -- Distance Text
                    if ESP_SETTINGS.ShowDistance then
                        local distance = (localPlayer.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
                        esp.distance.Text = string.format("%.1f studs", distance)
                        esp.distance.Position = Vector2.new(boxPosition.X + boxSize.X / 2, boxPosition.Y + boxSize.Y + 5)
                        esp.distance.Color = ESP_SETTINGS.DistanceColor
                        esp.distance.Visible = true
                    else
                        esp.distance.Visible = false
                    end

                    -- (The ESP module’s built-in tracer drawing is independent and not used for our new tracer modes.)
                    if ESP_SETTINGS.ShowTracer then
                        local hrp2D = camera:WorldToViewportPoint(rootPart.Position)
                        local tracerY
                        if ESP_SETTINGS.TracerPosition == "Top" then
                            tracerY = 0
                        elseif ESP_SETTINGS.TracerPosition == "Middle" then
                            tracerY = camera.ViewportSize.Y / 2
                        else
                            tracerY = camera.ViewportSize.Y
                        end
                        if ESP_SETTINGS.Teamcheck and (player.TeamColor == localPlayer.TeamColor) then
                            esp.tracer.Visible = false
                        else
                            esp.tracer.Visible = true
                            esp.tracer.From = Vector2.new(camera.ViewportSize.X / 2, tracerY)
                            esp.tracer.To = Vector2.new(hrp2D.X, hrp2D.Y)
                            esp.tracer.Color = ESP_SETTINGS.TracerColor
                            esp.tracer.Thickness = ESP_SETTINGS.TracerThickness
                        end
                    else
                        esp.tracer.Visible = false
                    end

                else
                    for _, drawing in pairs(esp) do
                        if drawing.Visible ~= nil then
                            drawing.Visible = false
                        end
                    end
                    for _, line in ipairs(esp.boxLines) do
                        line:Remove()
                    end
                    esp.boxLines = {}
                end
            else
                for _, drawing in pairs(esp) do
                    if drawing.Visible ~= nil then
                        drawing.Visible = false
                    end
                end
                for _, line in ipairs(esp.boxLines) do
                    line:Remove()
                end
                esp.boxLines = {}
            end
        else
            for _, drawing in pairs(esp) do
                if drawing.Visible ~= nil then
                    drawing.Visible = false
                end
            end
            for _, line in ipairs(esp.boxLines) do
                line:Remove()
            end
            esp.boxLines = {}
        end
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= localPlayer then
        createEsp(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        createEsp(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeEsp(player)
end)

RunService.RenderStepped:Connect(updateEsp)

local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness    = 1
FOVCircle.NumSides     = 100
FOVCircle.Radius       = config.fovSize
FOVCircle.Color        = config.fovColor
FOVCircle.Filled       = false
FOVCircle.Transparency = 0.5
FOVCircle.ZIndex       = 3
FOVCircle.Visible      = config.fovVisible

local mouseTracer = Drawing.new("Line")
mouseTracer.Thickness    = 1
mouseTracer.Transparency = 1
mouseTracer.Color        = config.tracerColor
mouseTracer.ZIndex       = 3
mouseTracer.Visible      = false

local allTracers = {}

local tracerMode = "Mouse"  

local function getNearestTorso()
    local bestTarget = nil
    local shortestDistance = math.huge
    local bestScreenPos = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local torso = player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso")
            if torso then
                local pos, onScreen = currentCamera:WorldToViewportPoint(torso.Position)
                if onScreen then
                    local screenPos = Vector2.new(pos.X, pos.Y)
                    local distance = (UserInputService:GetMouseLocation() - screenPos).Magnitude
                    if distance < shortestDistance then
                        shortestDistance = distance
                        bestTarget = torso
                        bestScreenPos = screenPos
                    end
                end
            end
        end
    end

    return bestTarget, bestScreenPos
end

RunService.RenderStepped:Connect(function()
    local mousePos = UserInputService:GetMouseLocation()
    
    -- Update FOV circle
    if FOVCircle then
        FOVCircle.Position = mousePos
        FOVCircle.Radius   = config.fovSize
        FOVCircle.Color    = config.fovColor
        FOVCircle.Visible  = config.fovVisible
    end

    if not ESP_SETTINGS.ShowTracer then
        mouseTracer.Visible = false
        for player, tracer in pairs(allTracers) do
            if tracer then tracer.Visible = false end
        end
        return  -- Exit early
    end

    if tracerMode == "Mouse" then
        for player, tracer in pairs(allTracers) do
            if tracer then tracer.Visible = false end
        end
        local target, targetScreenPos = getNearestTorso()
        if target and targetScreenPos then
            mouseTracer.From  = targetScreenPos
            mouseTracer.To    = mousePos
            mouseTracer.Color = config.tracerColor
            mouseTracer.Visible = true
        else
            mouseTracer.Visible = false
        end

    elseif tracerMode == "Enemy" then
        mouseTracer.Visible = false
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                local torso = player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso")
                if torso then
                    local pos, onScreen = currentCamera:WorldToViewportPoint(torso.Position)
                    if onScreen then
                        if not allTracers[player] then
                            allTracers[player] = Drawing.new("Line")
                            allTracers[player].Thickness = 1
                            allTracers[player].Transparency = 1
                            allTracers[player].Color = config.tracerColor
                            allTracers[player].ZIndex = 3
                        end
                        local tracer = allTracers[player]
                        local origin = Vector2.new(currentCamera.ViewportSize.X/2, currentCamera.ViewportSize.Y)
                        tracer.From = origin
                        tracer.To = Vector2.new(pos.X, pos.Y)
                        tracer.Color = config.tracerColor
                        tracer.Visible = true
                    else
                        if allTracers[player] then
                            allTracers[player].Visible = false
                        end
                    end
                end
            end
        end
    end
end)

local function isValidTarget(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        local hitPart = model:FindFirstChild(config.hitPart)
        if hitPart then
            local screenPoint, onScreen = currentCamera:WorldToViewportPoint(hitPart.Position)
            if onScreen then
                return hitPart, Vector2.new(screenPoint.X, screenPoint.Y)
            end
        end
    end
    return nil, nil
end

local function target()
    local bestTarget = nil
    local shortestDistance = math.huge
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and model ~= localPlayer.Character then
            local hitPart, screenPos = isValidTarget(model)
            if hitPart then
                local distance = (UserInputService:GetMouseLocation() - screenPos).Magnitude
                if distance < shortestDistance then
                    bestTarget = hitPart
                    shortestDistance = distance
                end
            end
        end
    end
    return bestTarget
end
-------------------- CONFIGURATION --------------------
local config = {
    usePrediction      = true,
    keybind            = Enum.KeyCode.E,
    resolver           = false,
    smoothness         = 1,
    hitPart            = "HumanoidRootPart",
    universal          = true,
    aimbotMode         = "toggle",
    aimbotEnabled      = false,
    predictionMul      = 0.13,
    fovVisible         = true,   -- FOV circle visibility
    fovSize            = 50,     -- FOV circle radius in pixels
    fovColor           = Color3.new(1, 1, 1),
    tracerEnabled      = true,   -- (default; now controlled via master toggle)
    tracerColor        = Color3.new(1, 1, 1)  -- default white
}

-------------------- SERVICES & VARIABLES --------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local currentCamera    = workspace.CurrentCamera

local localPlayer      = Players.LocalPlayer
local mouse            = localPlayer:GetMouse()

local victim           = nil
local velocity         = Vector3.new(0, 0, 0)
local oldPos           = nil

local aimbotConnection    = nil
local velocityConnection  = nil

local lockActive       = false

local orbitConnection  = nil
local orbitAngle       = 0

local camera = currentCamera  -- alias for clarity

-------------------- ESP SETTINGS & CACHE --------------------
local ESP_SETTINGS = {
    BoxOutlineColor = Color3.new(0, 0, 0),
    BoxColor = Color3.new(1, 1, 1),
    FilledBoxColor = Color3.new(1, 1, 1),
    NameColor = Color3.new(1, 1, 1),
    HealthOutlineColor = Color3.new(0, 0, 0),
    HealthHighColor = Color3.new(0, 1, 0),
    HealthLowColor = Color3.new(1, 0, 0),
    HealthColor = Color3.new(1, 1, 1),
    AnimatedHealthBars = false,
    DistanceColor = Color3.new(1, 1, 1),
    HealthBasedColor = false,
    CharSize = Vector2.new(4, 6),
    Teamcheck = false,
    WallCheck = false,
    Enabled = false,       -- enable via GUI
    ShowFilledBox = false,
    ShowBox = false,
    BoxType = "Normal",    -- "Normal" or "Corner"
    ShowName = false,
    ShowHealth = false,
    ShowDistance = false,
    ShowTracer = false,    -- Master toggle for tracer drawing
    TracerThickness = 1,
    TracerPosition = "Bottom",  -- "Top", "Middle", or "Bottom"
    TracerColor = Color3.new(1, 1, 1)
}

local cache = {}  -- cache for each player's ESP drawings

local bones = {
    {"Head", "UpperTorso"},
    {"UpperTorso", "RightUpperArm"},
    {"RightUpperArm", "RightLowerArm"},
    {"RightLowerArm", "RightHand"},
    {"UpperTorso", "LeftUpperArm"},
    {"LeftUpperArm", "LeftLowerArm"},
    {"LeftLowerArm", "LeftHand"},
    {"UpperTorso", "LowerTorso"},
    {"LowerTorso", "LeftUpperLeg"},
    {"LeftUpperLeg", "LeftLowerLeg"},
    {"LeftLowerLeg", "LeftFoot"},
    {"LowerTorso", "RightUpperLeg"},
    {"RightUpperLeg", "RightLowerLeg"},
    {"RightLowerLeg", "RightFoot"}
}

-------------------- DRAWING CREATION FUNCTION --------------------
local function create(class, properties)
    local drawing = Drawing.new(class)
    for property, value in pairs(properties) do
        drawing[property] = value
    end
    return drawing
end

-------------------- ESP CREATION & UPDATE --------------------
local function createEsp(player)
    local esp = {
        tracer = create("Line", {
            Thickness = ESP_SETTINGS.TracerThickness,
            Color = ESP_SETTINGS.TracerColor,
            Transparency = 1,
            Visible = false
        }),
        boxOutline = create("Square", {
            Color = ESP_SETTINGS.BoxOutlineColor,
            Thickness = 3,
            Filled = false,
            Visible = false
        }),
        box = create("Square", {
            Color = ESP_SETTINGS.BoxColor,
            Thickness = 1,
            Filled = false,
            Visible = false
        }),
        filledBox = create("Square", {
            Color = ESP_SETTINGS.FilledBoxColor,
            Thickness = 1,
            Transparency = 0.3,
            Filled = true,
            Visible = false
        }),
        name = create("Text", {
            Color = ESP_SETTINGS.NameColor,
            Outline = true,
            Center = true,
            Size = 13,
            Visible = false
        }),
        healthOutline = create("Line", {
            Thickness = 3,
            Color = ESP_SETTINGS.HealthOutlineColor,
            Visible = false
        }),
        health = create("Line", {
            Thickness = 1,
            Visible = false
        }),
        distance = create("Text", {
            Color = Color3.new(1, 1, 1),
            Size = 12,
            Outline = true,
            Center = true,
            Visible = false
        }),
        boxLines = {},
    }
    cache[player] = esp
end

local function isPlayerBehindWall(player)
    local character = player.Character
    if not character then return false end
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not rootPart then return false end

    local ray = Ray.new(camera.CFrame.Position, (rootPart.Position - camera.CFrame.Position).Unit * (rootPart.Position - camera.CFrame.Position).Magnitude)
    local hit = workspace:FindPartOnRayWithIgnoreList(ray, {localPlayer.Character, character})
    
    return hit and hit:IsA("Part")
end

local function removeEsp(player)
    local esp = cache[player]
    if not esp then return end

    for _, drawing in pairs(esp) do
        if type(drawing) == "table" and drawing.Remove then
            drawing:Remove()
        end
    end
    cache[player] = nil
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function updateEsp()
    for player, esp in pairs(cache) do
        local character = player.Character
        local team = player.Team
        if character and (not ESP_SETTINGS.Teamcheck or (team and team ~= localPlayer.Team)) then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local head = character:FindFirstChild("Head")
            local humanoid = character:FindFirstChild("Humanoid")
            local isBehindWall = ESP_SETTINGS.WallCheck and isPlayerBehindWall(player)
            local shouldShow = ESP_SETTINGS.Enabled and (not isBehindWall)
            if rootPart and head and humanoid and shouldShow then
                local position, onScreen = camera:WorldToViewportPoint(rootPart.Position)
                if onScreen then
                    local hrp2D = camera:WorldToViewportPoint(rootPart.Position)
                    local charSize = (camera:WorldToViewportPoint(rootPart.Position - Vector3.new(0, 3, 0)).Y - camera:WorldToViewportPoint(rootPart.Position + Vector3.new(0, 2.6, 0)).Y) / 2
                    local boxSize = Vector2.new(math.floor(charSize * 1.4), math.floor(charSize * 1.9))
                    local boxPosition = Vector2.new(math.floor(hrp2D.X - charSize * 1.4 / 2), math.floor(hrp2D.Y - charSize * 1.6 / 2))

                    -- Name
                    if ESP_SETTINGS.ShowName then
                        esp.name.Visible = true
                        esp.name.Text = string.lower(player.Name)
                        esp.name.Position = Vector2.new(boxSize.X / 2 + boxPosition.X, boxPosition.Y - 16)
                        esp.name.Color = ESP_SETTINGS.NameColor
                    else
                        esp.name.Visible = false
                    end

                    -- Filled Box
                    if ESP_SETTINGS.ShowFilledBox then
                        esp.filledBox.Position = boxPosition
                        esp.filledBox.Size = boxSize
                        esp.filledBox.Color = ESP_SETTINGS.FilledBoxColor
                        esp.filledBox.Visible = true
                    else
                        esp.filledBox.Visible = false
                    end

                    -- Box (Normal or Corner)
                    if ESP_SETTINGS.ShowBox then
                        if ESP_SETTINGS.BoxType == "Normal" then
                            esp.boxOutline.Size = boxSize
                            esp.boxOutline.Position = boxPosition
                            esp.box.Size = boxSize
                            esp.box.Position = boxPosition
                            esp.box.Color = ESP_SETTINGS.BoxColor
                            esp.box.Visible = true
                            esp.boxOutline.Visible = true
                            for _, line in ipairs(esp.boxLines) do
                                line:Remove()
                            end
                            esp.boxLines = {}
                        elseif ESP_SETTINGS.BoxType == "Corner" then
                            local lineW = (boxSize.X / 3)
                            local lineH = (boxSize.Y / 3)
                        
                            if #esp.boxLines == 0 then
                                for i = 1, 16 do
                                    local boxLine = create("Line", {
                                        Thickness = 1,
                                        Color = ESP_SETTINGS.BoxColor,
                                        Transparency = 1,
                                        Visible = true
                                    })
                                    table.insert(esp.boxLines, boxLine)
                                end
                            end
                        
                            local boxLines = esp.boxLines
                        
                            -- Outline lines
                            for i = 1, 8 do
                                boxLines[i].Thickness = 2
                                boxLines[i].Color = ESP_SETTINGS.BoxOutlineColor
                                boxLines[i].Transparency = 1
                            end
                        
                            boxLines[1].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[1].To = Vector2.new(boxPosition.X, boxPosition.Y + lineH)
                        
                            boxLines[2].From = Vector2.new(boxPosition.X, boxPosition.Y)
                            boxLines[2].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y)
                        
                            boxLines[3].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y)
                            boxLines[3].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
                        
                            boxLines[4].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y)
                            boxLines[4].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + lineH)
                        
                            boxLines[5].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[5].To = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
                        
                            boxLines[6].From = Vector2.new(boxPosition.X, boxPosition.Y + boxSize.Y)
                            boxLines[6].To = Vector2.new(boxPosition.X + lineW, boxPosition.Y + boxSize.Y)
                        
                            boxLines[7].From = Vector2.new(boxPosition.X + boxSize.X - lineW, boxPosition.Y + boxSize.Y)
                            boxLines[7].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
                        
                            boxLines[8].From = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y - lineH)
                            boxLines[8].To = Vector2.new(boxPosition.X + boxSize.X, boxPosition.Y + boxSize.Y)
                        
                            -- Inline lines (using same positions)
                            for i = 9, 16 do
                                boxLines[i].From = boxLines[i - 8].From
                                boxLines[i].To = boxLines[i - 8].To
                                boxLines[i].Color = ESP_SETTINGS.BoxColor
                            end
                        
                            for _, line in ipairs(boxLines) do
                                line.Visible = true
                            end
                            esp.box.Visible = false
                            esp.boxOutline.Visible = false
                        end
                    else
                        esp.box.Visible = false
                        esp.boxOutline.Visible = false
                        for _, line in ipairs(esp.boxLines) do
                            line:Remove()
                        end
                        esp.boxLines = {}
                    end

                    -- Health Bar
                    if ESP_SETTINGS.ShowHealth then
                        esp.healthOutline.Visible = true
                        esp.health.Visible = true
                        local health = humanoid.Health
                        if ESP_SETTINGS.AnimatedHealthBars then
                            health = lerp(health, humanoid.Health, 0.3)
                        end
                        local healthPercentage = health / humanoid.MaxHealth
                        local healthBarHeight = healthPercentage * boxSize.Y
                        esp.healthOutline.From = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y + 1)
                        esp.healthOutline.To = Vector2.new(boxPosition.X - 6, boxPosition.Y - 1)
                        esp.health.From = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y)
                        esp.health.To = Vector2.new(boxPosition.X - 6, boxPosition.Y + boxSize.Y - healthBarHeight)
                        if ESP_SETTINGS.HealthBasedColor then
                            esp.health.Color = ESP_SETTINGS.HealthLowColor:Lerp(ESP_SETTINGS.HealthHighColor, healthPercentage)
                        else
                            esp.health.Color = ESP_SETTINGS.HealthColor
                        end
                    else
                        esp.healthOutline.Visible = false
                        esp.health.Visible = false
                    end

                    -- Distance Text
                    if ESP_SETTINGS.ShowDistance then
                        local distance = (localPlayer.Character.HumanoidRootPart.Position - rootPart.Position).Magnitude
                        esp.distance.Text = string.format("%.1f studs", distance)
                        esp.distance.Position = Vector2.new(boxPosition.X + boxSize.X / 2, boxPosition.Y + boxSize.Y + 5)
                        esp.distance.Color = ESP_SETTINGS.DistanceColor
                        esp.distance.Visible = true
                    else
                        esp.distance.Visible = false
                    end

                    -- Note: The built-in tracer drawing in this ESP module is independent
                    -- and is not used for our new master-controlled tracer modes.
                else
                    for _, drawing in pairs(esp) do
                        if drawing.Visible ~= nil then
                            drawing.Visible = false
                        end
                    end
                    for _, line in ipairs(esp.boxLines) do
                        line:Remove()
                    end
                    esp.boxLines = {}
                end
            else
                for _, drawing in pairs(esp) do
                    if drawing.Visible ~= nil then
                        drawing.Visible = false
                    end
                end
                for _, line in ipairs(esp.boxLines) do
                    line:Remove()
                end
                esp.boxLines = {}
            end
        else
            for _, drawing in pairs(esp) do
                if drawing.Visible ~= nil then
                    drawing.Visible = false
                end
            end
            for _, line in ipairs(esp.boxLines) do
                line:Remove()
            end
            esp.boxLines = {}
        end
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= localPlayer then
        createEsp(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    if player ~= localPlayer then
        createEsp(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    removeEsp(player)
end)

RunService.RenderStepped:Connect(updateEsp)

-------------------- FOV CIRCLE & TRACER SETUP --------------------
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness    = 1
FOVCircle.NumSides     = 100
FOVCircle.Radius       = config.fovSize
FOVCircle.Color        = config.fovColor
FOVCircle.Filled       = false
FOVCircle.Transparency = 0.5
FOVCircle.ZIndex       = 3
FOVCircle.Visible      = config.fovVisible

local mouseTracer = Drawing.new("Line")
mouseTracer.Thickness    = 1
mouseTracer.Transparency = 1
mouseTracer.Color        = config.tracerColor
mouseTracer.ZIndex       = 3
mouseTracer.Visible      = false

local allTracers = {}

-- Tracer mode: "Mouse" or "Enemy"
local tracerMode = "Mouse"  

local function getNearestTorso()
    local bestTarget = nil
    local shortestDistance = math.huge
    local bestScreenPos = nil

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local torso = player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso")
            if torso then
                local pos, onScreen = currentCamera:WorldToViewportPoint(torso.Position)
                if onScreen then
                    local screenPos = Vector2.new(pos.X, pos.Y)
                    local distance = (UserInputService:GetMouseLocation() - screenPos).Magnitude
                    if distance < shortestDistance then
                        shortestDistance = distance
                        bestTarget = torso
                        bestScreenPos = screenPos
                    end
                end
            end
        end
    end

    return bestTarget, bestScreenPos
end

-------------------- TRACER UPDATE (Master Toggle + Mode Selection) --------------------
RunService.RenderStepped:Connect(function()
    local mousePos = UserInputService:GetMouseLocation()
    
    -- Update FOV circle (if used)
    if FOVCircle then
        FOVCircle.Position = mousePos
        FOVCircle.Radius   = config.fovSize
        FOVCircle.Color    = config.fovColor
        FOVCircle.Visible  = config.fovVisible
    end

    -- Master toggle: if ShowTracer is off, hide all tracers and exit
    if not ESP_SETTINGS.ShowTracer then
        mouseTracer.Visible = false
        for _, tracer in pairs(allTracers) do
            tracer.Visible = false
        end
        return
    end

    -- Update tracers based on the currently selected mode
    if tracerMode == "Mouse" then
        -- Hide enemy tracers
        for _, tracer in pairs(allTracers) do
            tracer.Visible = false
        end

        -- Update the mouse tracer
        local target, targetScreenPos = getNearestTorso()
        if target and targetScreenPos then
            mouseTracer.From  = targetScreenPos
            mouseTracer.To    = mousePos
            mouseTracer.Color = config.tracerColor
            mouseTracer.Visible = true
        else
            mouseTracer.Visible = false
        end

    elseif tracerMode == "Enemy" then
        -- Hide mouse tracer
        mouseTracer.Visible = false

        -- Update enemy tracers for each player
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                local torso = player.Character:FindFirstChild("Torso") or player.Character:FindFirstChild("UpperTorso")
                if torso then
                    local pos, onScreen = currentCamera:WorldToViewportPoint(torso.Position)
                    if onScreen then
                        if not allTracers[player] then
                            allTracers[player] = Drawing.new("Line")
                            allTracers[player].Thickness = 1
                            allTracers[player].Transparency = 1
                            allTracers[player].Color = config.tracerColor
                            allTracers[player].ZIndex = 3
                        end
                        local tracer = allTracers[player]
                        local origin = Vector2.new(currentCamera.ViewportSize.X/2, currentCamera.ViewportSize.Y)
                        tracer.From = origin
                        tracer.To = Vector2.new(pos.X, pos.Y)
                        tracer.Color = config.tracerColor
                        tracer.Visible = true
                    else
                        if allTracers[player] then
                            allTracers[player].Visible = false
                        end
                    end
                end
            end
        end
    end
end)

-------------------- TARGET SELECTION --------------------
local function isValidTarget(model)
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        local hitPart = model:FindFirstChild(config.hitPart)
        if hitPart then
            local screenPoint, onScreen = currentCamera:WorldToViewportPoint(hitPart.Position)
            if onScreen then
                return hitPart, Vector2.new(screenPoint.X, screenPoint.Y)
            end
        end
    end
    return nil, nil
end

local function target()
    local bestTarget = nil
    local shortestDistance = math.huge
    for _, model in ipairs(workspace:GetDescendants()) do
        if model:IsA("Model") and model ~= localPlayer.Character then
            local hitPart, screenPos = isValidTarget(model)
            if hitPart then
                local distance = (UserInputService:GetMouseLocation() - screenPos).Magnitude
                if distance < shortestDistance then
                    bestTarget = hitPart
                    shortestDistance = distance
                end
            end
        end
    end
    return bestTarget
end

-------------------- AIMBOT FUNCTIONS --------------------
local function enableAimbot()
    if aimbotConnection then return end
    victim = target()
    if victim then
        oldPos = victim.Position
    end
    aimbotConnection = RunService.RenderStepped:Connect(function()
        if victim and victim.Parent then
            local humanoid = victim.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                local pos = victim.Position
                if config.usePrediction then
                    local currentVel = victim.Velocity
                    local predictedVel = Vector3.new(
                        currentVel.X,
                        config.antiGroundShots and (currentVel.Y * config.groundShotsValue) or currentVel.Y,
                        currentVel.Z
                    )
                    pos = pos + (predictedVel * config.predictionMul)
                end
                currentCamera.CFrame = currentCamera.CFrame:Lerp(
                    CFrame.new(currentCamera.CFrame.Position, pos),
                    config.smoothness
                )
            else
                victim = target()
                if victim then
                    oldPos = victim.Position
                end
            end
        else
            victim = target()
            if victim then
                oldPos = victim.Position
            end
        end
    end)
end

local function disableAimbot()
    if aimbotConnection then
        aimbotConnection:Disconnect()
        aimbotConnection = nil
    end
    victim = nil
end

local function enableVelocityUpdate()
    if velocityConnection then return end
    velocityConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if victim and victim.Parent and oldPos then
            local currentPos = victim.Position
            local displacement = currentPos - oldPos
            velocity = velocity:Lerp(displacement / deltaTime, 0.4)
            oldPos = currentPos
        end
    end)
end

local function disableVelocityUpdate()
    if velocityConnection then
        velocityConnection:Disconnect()
        velocityConnection = nil
    end
end

local function updateAimbotConnections()
    if lockActive then
        enableAimbot()
        enableVelocityUpdate()
    else
        disableAimbot()
        disableVelocityUpdate()
    end
end

-------------------- ORBIT FUNCTIONS --------------------
local function enableOrbit()
    if orbitConnection then return end
    orbitConnection = RunService.RenderStepped:Connect(function(deltaTime)
        if victim and victim.Parent and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local targetPos = victim.Position
            orbitAngle = orbitAngle + (config.orbitSpeed * deltaTime)
            local offset = Vector3.new(
                math.cos(orbitAngle) * config.orbitDistance,
                config.orbitHeight,
                math.sin(orbitAngle) * config.orbitDistance
            )
            localPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(targetPos + offset)
        end
    end)
end

local function disableOrbit()
    if orbitConnection then
        orbitConnection:Disconnect()
        orbitConnection = nil
    end
end

-------------------- USER INPUT --------------------
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == config.keybind then
        if not config.aimbotEnabled then
            print("Aimbot is disabled via GUI; keybind ignored.")
            return
        end

        if config.aimbotMode == "toggle" then
            lockActive = not lockActive
            updateAimbotConnections()
        elseif config.aimbotMode == "hold" then
            lockActive = true
            updateAimbotConnections()
        end
    elseif input.KeyCode == config.toggleGuiKeybind then
        if library and library.ToggleUI then
            library:ToggleUI()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input, processed)
    if processed then return end

    if config.aimbotMode == "hold" and input.KeyCode == config.keybind then
        lockActive = false
        updateAimbotConnections()
    end
end)

-------------------- UI LIBRARY & GUI --------------------
local library = loadstring(game:HttpGet("https://raw.githubusercontent.com/FwedsW/Sources/main/UISource"))()
LoadUi('opium<font color="#9932cc">.percocet</font>', 'RightShift', Color3.fromRGB(153, 50, 204))

local aimbotTab    = library:addTab("Aiming")
local visualTab    = library:addTab("Visuals")
local movementTab  = library:addTab("Movement")

local aimbotConfig    = aimbotTab:createGroup('left', 'Camlock')
local resolverConfig  = aimbotTab:createGroup('right', 'Resolver')
local orbitConfig     = aimbotTab:createGroup('left', 'Orbit')
local fovConfig       = visualTab:createGroup('right', 'Circle')
local espConfig       = visualTab:createGroup('left', 'ESP')

local cframeGroup = movementTab:createGroup("right", "CFrame Movement")

cframeGroup:addToggle({
    text = "CFrame Speed Enabled",
    flag = "rage_cframe_speed_enabled",
    callback = function(v)
         library.flags["rage_cframe_speed_enabled"] = v
    end
})

cframeGroup:addKeybind({
    text = "CFrame Speed Keybind",
    flag = "rage_cframe_speed_keybind",
    callback = function(v)
         library.flags["rage_cframe_speed_keybind"] = v
    end
})

cframeGroup:addSlider({
    text = "CFrame Speed Amount",
    flag = "rage_cframe_speed_amount",
    min = 1,
    max = 50,
    value = 10,
    decimals = 1,
    callback = function(v)
         library.flags["rage_cframe_speed_amount"] = v
    end
}, "/50")

cframeGroup:addToggle({
    text = "CFrame Fly Enabled",
    flag = "rage_cframe_fly_enabled",
    callback = function(v)
         library.flags["rage_cframe_fly_enabled"] = v
    end
})

cframeGroup:addKeybind({
    text = "CFrame Fly Keybind",
    flag = "rage_cframe_fly_keybind",
    callback = function(v)
         library.flags["rage_cframe_fly_keybind"] = v
    end
})

cframeGroup:addSlider({
    text = "CFrame Fly Amount",
    flag = "rage_cframe_fly_amount",
    min = 1,
    max = 50,
    value = 10,
    decimals = 1,
    callback = function(v)
         library.flags["rage_cframe_fly_amount"] = v
    end
}, "/50")

cframeGroup:addToggle({
    text = "No Jump Cooldown",
    flag = "rage_misc_movement_no_jump_cooldown",
    callback = function(v)
         library.flags["rage_misc_movement_no_jump_cooldown"] = v
    end
})

-------------------- AIMBOT GUI --------------------
aimbotConfig:addToggle({
    text = "Enabled",
    flag = "AimbotEnabled",
    callback = function(v)
        config.aimbotEnabled = v
        if not v then
            lockActive = false
        end
        updateAimbotConnections()
    end
})

aimbotConfig:addKeybind({
    text = "Keybind",
    flag = "Key",
    callback = function(v)
        config.keybind = v
    end
})

aimbotConfig:addSlider({
    text = "Smoothness",
    flag = "Smoothing",
    min = 0,
    max = 1,
    value = 0.5,
    decimals = 2,
    callback = function(v)
        config.smoothness = v
    end
}, '/1')

aimbotConfig:addSlider({
    text = "Prediction Factor",
    flag = "PredictionMul",
    min = 0,
    max = 0.5,
    value = 0.13,
    decimals = 3,
    callback = function(v)
        config.predictionMul = v
    end
}, '/0.5')

aimbotConfig:addList({
    text = "Hit Part",
    flag = "HitPart",
    values = {"HumanoidRootPart", "Head", "UpperTorso", "Torso", "LowerTorso"},
    multiselect = false,
    skipflag = false,
    callback = function(v)
         config.hitPart = v
    end
})

-------------------- RESOLVER GUI --------------------
resolverConfig:addToggle({
    text = "Enabled",
    flag = "ResolverEnabled",
    callback = function(v)
        config.resolver = v
    end
})
resolverConfig:addList({
    text = "Method",
    flag = "ResolverMethod",
    values = {"Recalculate", "Delta", "Built"},
    multiselect = false,
    skipflag = false,
    callback = function(v)
        config.resolverMethod = v
    end
})
resolverConfig:addTextbox({
    text = "History",
    flag = "ResolverHistory",
    callback = function(v)
        config.resolverHistory = v
    end
})
resolverConfig:addMultiTextbox({
    text = "Detection",
    flag = "ResolverDetection",
    callback = function(v)
        config.resolverDetection = v  -- v is a table of strings
    end
})

-------------------- ORBIT GUI --------------------
orbitConfig:addToggle({
    text = "Enabled",
    flag = "OrbitEnabled",
    callback = function(v)
         config.orbitEnabled = v
         if v then
             enableOrbit()
         else
             disableOrbit()
         end
    end
})

orbitConfig:addSlider({
    text = "Speed",
    flag = "OrbitSpeed",
    min = 0,
    max = 10,
    value = 1,
    decimals = 1,
    callback = function(v)
         config.orbitSpeed = v
    end
}, '/10')

orbitConfig:addSlider({
    text = "Distance",
    flag = "OrbitDistance",
    min = 0,
    max = 50,
    value = 5,
    decimals = 1,
    callback = function(v)
         config.orbitDistance = v
    end
}, '/50')

orbitConfig:addSlider({
    text = "Height Offset",
    flag = "OrbitHeight",
    min = -50,
    max = 50,
    value = 0,
    decimals = 1,
    callback = function(v)
         config.orbitHeight = v
    end
}, '/50')

-------------------- FOV GUI --------------------
fovConfig:addToggle({
    text = "Visible",
    flag = "FovVisible",
    callback = function(v)
        config.fovVisible = v
    end
})

fovConfig:addSlider({
    text = "Radius",
    flag = "FovSize",
    min = 5,
    max = 500,
    value = 50,
    decimals = 0,
    callback = function(v)
        config.fovSize = v
    end
}, '/500')

fovConfig:addColorpicker({
    text = "Color",
    ontop = true,
    flag = "FovColor",
    color = config.fovColor,
    callback = function(v)
        config.fovColor = v
    end
})

-------------------- ESP GUI (INCLUDING TRACER CONTROLS) --------------------
espConfig:addToggle({
    text = "ESP Enabled",
    flag = "ESPEnabled",
    value = false,
    callback = function(v)
         ESP_SETTINGS.Enabled = v
    end
})
espConfig:addToggle({
    text = "Show Box",
    flag = "ShowBox",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowBox = v
    end
})
espConfig:addToggle({
    text = "Show Filled Box",
    flag = "ShowFilledBox",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowFilledBox = v
    end
})
espConfig:addToggle({
    text = "Show Name",
    flag = "ShowName",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowName = v
    end
})
espConfig:addToggle({
    text = "Show Health",
    flag = "ShowHealth",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowHealth = v
    end
})
espConfig:addToggle({
    text = "Show Distance",
    flag = "ShowDistance",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowDistance = v
    end
})
-- MASTER Toggle for tracers:
espConfig:addToggle({
    text = "Show Tracers",
    flag = "ShowTracer",
    value = false,
    callback = function(v)
         ESP_SETTINGS.ShowTracer = v
         if not v then
             mouseTracer.Visible = false
             for _, tracer in pairs(allTracers) do
                 tracer.Visible = false
             end
         end
    end
})
-- Dropdown to choose tracer mode.
espConfig:addList({
    text = "Tracer Mode",
    flag = "TracerMode",
    values = {"Mouse Tracer", "Enemy Tracer"},
    multiselect = false,
    callback = function(v)
         if v == "Mouse Tracer" then
             tracerMode = "Mouse"
             for _, tracer in pairs(allTracers) do
                 tracer.Visible = false
             end
         elseif v == "Enemy Tracer" then
             tracerMode = "Enemy"
             mouseTracer.Visible = false
         end
    end
})
espConfig:addColorpicker({
    text = "Box Color",
    flag = "BoxColor",
    color = ESP_SETTINGS.BoxColor,
    callback = function(v)
         ESP_SETTINGS.BoxColor = v
    end
})
espConfig:addColorpicker({
    text = "Filled Box Color",
    flag = "FilledBoxColor",
    color = ESP_SETTINGS.FilledBoxColor,
    callback = function(v)
         ESP_SETTINGS.FilledBoxColor = v
    end
})
espConfig:addColorpicker({
    text = "Name Color",
    flag = "NameColor",
    color = ESP_SETTINGS.NameColor,
    callback = function(v)
         ESP_SETTINGS.NameColor = v
    end
})
espConfig:addColorpicker({
    text = "Tracer Color",
    flag = "TracerColor",
    color = ESP_SETTINGS.TracerColor,
    callback = function(v)
         ESP_SETTINGS.TracerColor = v
         mouseTracer.Color = v
         for _, tracer in pairs(allTracers) do
             if tracer then tracer.Color = v end
         end
    end
})

-------------------- MOVEMENT FEATURES (CFrame Speed, Fly, etc.) --------------------
do
    flags = flags or library.flags or {}
    utility = utility or {}
    if not utility.has_character then
        function utility.has_character(player)
            return player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        end
    end
    if not utility.new_connection then
        function utility.new_connection(connection, func)
            return connection:Connect(func)
        end
    end

    local cframeSpeedToggle = false
    local cframeFlyToggle = false

    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == library.flags["rage_cframe_speed_keybind"] then
            cframeSpeedToggle = not cframeSpeedToggle
        end
        if input.KeyCode == library.flags["rage_cframe_fly_keybind"] then
            cframeFlyToggle = not cframeFlyToggle
        end
    end)

    utility.new_connection(RunService.Heartbeat, function(deltaTime)
        local cframe_speed_enabled = flags["rage_cframe_speed_enabled"]
        local no_jump_cooldown = flags["rage_misc_movement_no_jump_cooldown"]
        local cframe_fly_enabled = flags["rage_cframe_fly_enabled"]
        local cframe_fly_speed = flags["rage_cframe_fly_amount"]

        if cframe_speed_enabled and cframeSpeedToggle and utility.has_character(localPlayer) then
            local speed = flags["rage_cframe_speed_amount"]
            local root_part = localPlayer.Character.HumanoidRootPart
            local humanoid = localPlayer.Character.Humanoid

            root_part.CFrame = root_part.CFrame + humanoid.MoveDirection * speed
        end

        if cframe_fly_enabled and cframeFlyToggle and utility.has_character(localPlayer) then
            local move_direction = localPlayer.Character.Humanoid.MoveDirection
            local hrp = localPlayer.Character.HumanoidRootPart

            local add = Vector3.new(0, (UserInputService:IsKeyDown(Enum.KeyCode.Space) and cframe_fly_speed / 8 or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and -cframe_fly_speed / 8) or 0, 0)

            hrp.CFrame = hrp.CFrame + (move_direction * deltaTime) * cframe_fly_speed * 10
            hrp.CFrame = hrp.CFrame + add
            hrp.Velocity = (hrp.Velocity * Vector3.new(1, 0, 1)) + Vector3.new(0, 1.9, 0)
        end

        if flags["rage_misc_movement_no_jump_cooldown"] and utility.has_character(localPlayer) then
            localPlayer.Character.Humanoid.UseJumpPower = false
        end
    end)
end
