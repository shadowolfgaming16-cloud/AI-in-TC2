-- Gameplay Recorder (LocalScript)
-- Records optimized gameplay frames to timestamped JSON files.
local Services = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    UIS = game:GetService("UserInputService"),
    Http = game:GetService("HttpService"),
    Workspace = game:GetService("Workspace"),
    CoreGui = game:GetService("CoreGui"),
}

local LocalPlayer = Services.Players.LocalPlayer
local Camera = Services.Workspace.CurrentCamera

-- Config
local Recorder = {}
Recorder.SampleInterval = 0.1 -- seconds between recorded frames (default 10 Hz)
Recorder.MaxFrames = 20000 -- safety limit to avoid unbounded memory
Recorder.angles = { -60, -45, -30, -15, 0, 15, 30, 45, 60 }

local recording = false
local frames = {}
local lastSample = 0
local pressedKeys = {}

-- UI
local function CreateUI()
    if LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("GameplayRecorder") then
        LocalPlayer.PlayerGui.GameplayRecorder:Destroy()
    end
    local sg = Instance.new("ScreenGui")
    sg.Name = "GameplayRecorder"
    sg.ResetOnSpawn = false
    sg.DisplayOrder = 30
    sg.Parent = LocalPlayer.PlayerGui

    local frame = Instance.new("Frame", sg)
    frame.Size = UDim2.new(0, 220, 0, 110)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(20,20,25)
    frame.BorderSizePixel = 0

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1, -10, 0, 20)
    title.Position = UDim2.new(0, 5, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "Gameplay Recorder"
    title.TextColor3 = Color3.fromRGB(160, 220, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 14

    local status = Instance.new("TextLabel", frame)
    status.Size = UDim2.new(1, -10, 0, 18)
    status.Position = UDim2.new(0, 5, 0, 30)
    status.BackgroundTransparency = 1
    status.Text = "Status: Idle"
    status.TextColor3 = Color3.fromRGB(200,200,200)
    status.Font = Enum.Font.RobotoMono
    status.TextSize = 12

    local startBtn = Instance.new("TextButton", frame)
    startBtn.Size = UDim2.new(0.5, -10, 0, 28)
    startBtn.Position = UDim2.new(0, 5, 1, -38)
    startBtn.Text = "Start"
    startBtn.Font = Enum.Font.SourceSansBold
    startBtn.TextSize = 14
    startBtn.BackgroundColor3 = Color3.fromRGB(80,200,100)

    local stopBtn = Instance.new("TextButton", frame)
    stopBtn.Size = UDim2.new(0.5, -10, 0, 28)
    stopBtn.Position = UDim2.new(0.5, 5, 1, -38)
    stopBtn.Text = "Stop & Save"
    stopBtn.Font = Enum.Font.SourceSansBold
    stopBtn.TextSize = 14
    stopBtn.BackgroundColor3 = Color3.fromRGB(200,80,80)

    local rateLabel = Instance.new("TextLabel", frame)
    rateLabel.Size = UDim2.new(1, -10, 0, 16)
    rateLabel.Position = UDim2.new(0, 5, 0, 52)
    rateLabel.BackgroundTransparency = 1
    rateLabel.Text = string.format("Interval: %.2fs", Recorder.SampleInterval)
    rateLabel.Font = Enum.Font.RobotoMono
    rateLabel.TextSize = 12
    rateLabel.TextColor3 = Color3.fromRGB(200,200,200)

    startBtn.MouseButton1Click:Connect(function()
        if recording then return end
        recording = true
        frames = {}
        lastSample = tick()
        status.Text = "Status: Recording"
        rateLabel.Text = string.format("Interval: %.2fs", Recorder.SampleInterval)
    end)

    stopBtn.MouseButton1Click:Connect(function()
        if not recording then return end
        recording = false
        status.Text = "Status: Saving..."
        task.spawn(function()
            local prefix = "gameplay_"
            local fname = prefix .. tostring(os.time()) .. ".json"
            local data = {
                meta = {
                    created = os.time(),
                    interval = Recorder.SampleInterval,
                    frameCount = #frames,
                },
                frames = frames,
            }
            local ok, encoded = pcall(function() return Services.Http:JSONEncode(data) end)
            if ok then
                pcall(function() writefile(fname, encoded) end)
                status.Text = "Status: Saved to " .. fname
            else
                status.Text = "Status: Save failed"
            end
            task.wait(2)
            status.Text = "Status: Idle"
        end)
    end)

    return sg
end

local gui = CreateUI()

-- Key tracking
Services.UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        pressedKeys[input.KeyCode.Name] = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        pressedKeys["Mouse1"] = true
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        pressedKeys["Mouse2"] = true
    end
end)
Services.UIS.InputEnded:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        pressedKeys[input.KeyCode.Name] = nil
    elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
        pressedKeys["Mouse1"] = nil
    elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
        pressedKeys["Mouse2"] = nil
    end
end)

-- Raycast helper
local function rayDistances(rootPos)
    local results = {}
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character, Services.Workspace:FindFirstChild("Ray_Ignore") }
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    for _, angle in ipairs(Recorder.angles) do
        local dir = (CFrame.new(Vector3.new(), Vector3.FromNormalId(Enum.NormalId.Front)) * CFrame.Angles(0, math.rad(angle), 0)).LookVector
        if Camera and Camera.CFrame then
            dir = (Camera.CFrame * CFrame.Angles(0, math.rad(angle), 0)).LookVector * 60
        end
        local ray = Services.Workspace:Raycast(rootPos, dir, rayParams)
        table.insert(results, ray and ray.Distance or 60)
    end
    return results
end

-- Sampling loop
Services.RunService.Heartbeat:Connect(function(dt)
    if not recording then return end
    if tick() - lastSample < Recorder.SampleInterval then return end
    lastSample = tick()

    if #frames >= Recorder.MaxFrames then
        recording = false
        return
    end

    local frame = { timestamp = tick() }
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    frame.menuOpen = (LocalPlayer.PlayerGui and LocalPlayer.PlayerGui:FindFirstChild("Menu") and LocalPlayer.PlayerGui.Menu:FindFirstChild("MenuMain") and LocalPlayer.PlayerGui.Menu.MenuMain.Visible) and true or false
    frame.position = root and { x = root.Position.X, y = root.Position.Y, z = root.Position.Z } or nil
    frame.velocity = root and { x = root.Velocity.X, y = root.Velocity.Y, z = root.Velocity.Z } or nil
    frame.health = hum and hum.Health or 0
    frame.maxHealth = hum and hum.MaxHealth or 100
    frame.walkSpeed = hum and hum.WalkSpeed or 0
    frame.isAir = hum and (hum.FloorMaterial == Enum.Material.Air)
    frame.camera = Camera and { cframe = tostring(Camera.CFrame) } or nil
    frame.mouse = { x = Services.UIS:GetMouseLocation().X, y = Services.UIS:GetMouseLocation().Y }

    -- Ray distances
    if root then
        frame.rays = rayDistances(root.Position)
    else
        frame.rays = {}
    end

    -- Team/Class/Weapon
    local status = LocalPlayer:FindFirstChild("Status")
    frame.team = status and status:FindFirstChild("Team") and status.Team.Value or nil
    frame.class = status and status:FindFirstChild("Class") and status.Class.Value or nil
    local playerModel = Services.Workspace:FindFirstChild(LocalPlayer.Name)
    frame.weapon = nil
    if playerModel then
        local g = playerModel:FindFirstChild("Gun")
        if g and g:IsA("ObjectValue") then
            local boop = g:FindFirstChild("Boop")
            if boop and boop:IsA("StringValue") then frame.weapon = boop.Value end
        end
    end

    -- Current life stats
    local stats = LocalPlayer:FindFirstChild("CurrentLifeStats")
    if stats then
        frame.kills = stats:FindFirstChild("Kills") and stats.Kills.Value or 0
        frame.damage = stats:FindFirstChild("Damage") and stats.Damage.Value or 0
        frame.timeAlive = stats:FindFirstChild("TimeAlive") and stats.TimeAlive.Value or 0
    end

    -- Dead flag
    frame.dead = playerModel and playerModel:FindFirstChild("Dead") and playerModel.Dead.Value or false

    -- Keys pressed snapshot
    local keys = {}
    for k, _ in pairs(pressedKeys) do table.insert(keys, k) end
    frame.keys = keys

    table.insert(frames, frame)
end)

print("GameplayRecorder initialized. Open the GUI to start recording.")
