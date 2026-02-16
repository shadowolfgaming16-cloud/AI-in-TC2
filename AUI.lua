--[=[ 
    PROJECT: 'SENTINEL' - DEEP NEURO-EVOLUTIONARY AGENT (v5.7.1 - SURVIVAL TUNING)
    GAME: TYPICAL COLORS 2 (ROBLOX) 
     
    CHANGELOG:
    - TUNED: Massive penalty for dying after leaving spawn (-350).
    - TUNED: Logic prevents "Suicide Runs" from being registered as positive fitness.
    - Integrated 'Dead' BoolValue detection.
    - Implemented 'TimeAlive' timer checking.
    - Added Sliding Door detection.
]=]

local Services = {
	Players = game:GetService("Players"),
	RunService = game:GetService("RunService"),
	UIS = game:GetService("UserInputService"),
	VIM = game:GetService("VirtualInputManager"),
	Http = game:GetService("HttpService"),
	Tween = game:GetService("TweenService"),
	Workspace = game:GetService("Workspace"),
	CoreGui = game:GetService("CoreGui"),
}

local LocalPlayer = Services.Players.LocalPlayer
local Camera = Services.Workspace.CurrentCamera
local Mouse = LocalPlayer:GetMouse()

local NumberMap = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
	[7] = Enum.KeyCode.Seven,
	[8] = Enum.KeyCode.Eight,
	[9] = Enum.KeyCode.Nine,
	[0] = Enum.KeyCode.Zero,
}

local ClassIDMap = {
	["Scout"] = 0.1,
	["Trooper"] = 0.2,
	["Arsonist"] = 0.3,
	["Annihilator"] = 0.4,
	["Brute"] = 0.5,
	["Mechanic"] = 0.6,
	["Doctor"] = 0.7,
	["Marksman"] = 0.8,
	["Agent"] = 0.9,
}

local Config = {
	-- Input Layer: 54 inputs
	Topology = { 54, 60, 45, 30, 12 },

	Learning = {
		MutationRate = 0.2,
		MutationStrength = 0.6,
		MemoryFile = "sentinel_v5_7_tc2.json",
	},

	Hyperparameters = {
		VisionRange = 300,
		FieldOfView = 90,
		SmoothingSpeed = 8.0,
		ScanInterval = 0.15,
		BoredomThreshold = 25,
	},
}
local Math = {}
function Math.Sigmoid(x)
	return 1 / (1 + math.exp(-x))
end
function Math.Tanh(x)
	return math.tanh(x)
end
function Math.Relu(x)
	return math.max(0, x)
end
function Math.InverseLerp(a, b, v)
	return math.clamp((v - a) / (b - a), 0, 1)
end
function Math.Lerp(a, b, t)
	return a + (b - a) * t
end
local Brain = {}
Brain.__index = Brain

function Brain.new(topology)
	local self = setmetatable({}, Brain)
	self.Layers = {}
	self.Fitness = 0
	self.Generation = 1

	for i = 1, #topology - 1 do
		local layer = { Weights = {}, Biases = {} }
		local inCount = topology[i]
		local outCount = topology[i + 1]

		for n = 1, outCount do
			layer.Biases[n] = (math.random() * 2) - 1
			layer.Weights[n] = {}
			for k = 1, inCount do
				layer.Weights[n][k] = (math.random() * 2) - 1
			end
		end
		table.insert(self.Layers, layer)
	end
	return self
end

function Brain:ForwardPropagate(inputs)
	local currentValues = inputs
	for _, layer in ipairs(self.Layers) do
		local nextValues = {}
		for n = 1, #layer.Biases do
			local sum = layer.Biases[n]
			for k = 1, #currentValues do
				local val = currentValues[k] or 0
				sum = sum + (val * (layer.Weights[n][k] or 0))
			end
			nextValues[n] = Math.Tanh(sum)
		end
		currentValues = nextValues
	end
	return currentValues
end

function Brain:Mutate()
	for _, layer in ipairs(self.Layers) do
		for n = 1, #layer.Biases do
			if math.random() < Config.Learning.MutationRate then
				layer.Biases[n] = layer.Biases[n] + ((math.random() * 2 - 1) * Config.Learning.MutationStrength)
			end
			for k = 1, #layer.Weights[n] do
				if math.random() < Config.Learning.MutationRate then
					layer.Weights[n][k] = layer.Weights[n][k]
						+ ((math.random() * 2 - 1) * Config.Learning.MutationStrength)
				end
			end
		end
	end
end

--// PERCEPTION SYSTEM //--
local Perception = {
	CachedEnemy = nil,
	CachedDist = 999,
	CachedDanger = 0,
	CachedDangerDir = Vector3.zero,
	LastScanTime = 0,

	WeaponTimers = {},
	CurrentDetectedWeapon = "None",

	NearSlidingDoor = false,
	DoorIsOpen = false,
	DoorPosition = nil,
	DoorWaitTime = 0,
	LastDoorPos = nil,
}
local function GetPlayerStatus(plr, key)
	if plr:FindFirstChild("Status") and plr.Status:FindFirstChild(key) then
		return plr.Status[key].Value
	end
	return nil
end

local function IsEnemy(plr)
	if not plr or plr == LocalPlayer then
		return false
	end
	local myTeam = GetPlayerStatus(LocalPlayer, "Team")
	local theirTeam = GetPlayerStatus(plr, "Team")
	if myTeam and theirTeam then
		return myTeam ~= theirTeam
	end
	if plr.Team ~= nil and LocalPlayer.Team ~= nil then
		return plr.Team ~= LocalPlayer.Team
	end
	return true
end

function Perception.RunScans()
	if tick() - Perception.LastScanTime < Config.Hyperparameters.ScanInterval then
		return
	end
	Perception.LastScanTime = tick()

	local nearestEnemy = nil
	local nearestDist = Config.Hyperparameters.VisionRange
	local char = LocalPlayer.Character
	if char and char:FindFirstChild("HumanoidRootPart") then
		local myRoot = char.HumanoidRootPart
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { char, Services.Workspace:FindFirstChild("Ray_Ignore") }

		for _, p in ipairs(Services.Players:GetPlayers()) do
			if p ~= LocalPlayer and IsEnemy(p) then
				local isAlive = GetPlayerStatus(p, "Alive")
				if isAlive == false then
					continue
				end

				if p.Character then
					local eRoot = p.Character:FindFirstChild("HumanoidRootPart")
					local eHum = p.Character:FindFirstChildOfClass("Humanoid")
					if eRoot and eHum and eHum.Health > 0 then
						local dir = eRoot.Position - myRoot.Position
						if dir.Magnitude < nearestDist then
							local res = Services.Workspace:Raycast(myRoot.Position, dir.Unit * dir.Magnitude, rayParams)
							if not res or res.Instance:IsDescendantOf(p.Character) then
								nearestDist = dir.Magnitude
								nearestEnemy = eRoot
							end
						end
					end
				end
			end
		end
	end
	Perception.CachedEnemy = nearestEnemy
	Perception.CachedDist = nearestDist

	local dangerLevel = 0
	local dangerDir = Vector3.zero
	local ignoreFolder = Services.Workspace:FindFirstChild("Ray_Ignore")
	if ignoreFolder and char and char:FindFirstChild("HumanoidRootPart") then
		local myPos = char.HumanoidRootPart.Position
		for _, obj in ipairs(ignoreFolder:GetChildren()) do
			if obj:IsA("BasePart") then
				local dist = (obj.Position - myPos).Magnitude
				if dist < 20 then
					dangerLevel = 1
					dangerDir = (obj.Position - myPos).Unit
				end
			end
		end
	end
	Perception.CachedDanger = dangerLevel
	Perception.CachedDangerDir = dangerDir
end

function Perception.ScanSlidingDoors()
	Perception.NearSlidingDoor = false
	Perception.DoorIsOpen = false
	Perception.DoorPosition = nil

	local char = LocalPlayer.Character
	if not char then
		return -1
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return -1
	end

	local map = Services.Workspace:FindFirstChild("Map")
	if not map then
		return -1
	end
	local geo = map:FindFirstChild("Geometry")
	if not geo then
		return -1
	end
	local doors = geo:FindFirstChild("Doors")
	if not doors then
		return -1
	end

	for _, d in ipairs(doors:GetChildren()) do
		if d.Name:find("DoorM") or d.Name:find("Door") then
			local refObject = nil
			if d:IsA("BasePart") then
				refObject = d
			else
				refObject = d:FindFirstChild("Door")
					or d:FindFirstChild("Primary")
					or d:FindFirstChildWhichIsA("BasePart")
			end

			if refObject and refObject:IsA("BasePart") then
				local targetPos = refObject.Position
				local dist = (targetPos - root.Position).Magnitude

				if dist < 15 then
					Perception.DoorPosition = targetPos
					local lookDir = root.CFrame.LookVector
					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					rayParams.FilterDescendantsInstances = { char }
					local rayResult =
						Services.Workspace:Raycast(root.Position + Vector3.new(0, 0, 0), lookDir * 20, rayParams)

					local doorBlocking = false
					if rayResult then
						local hitModel = rayResult.Instance:FindFirstAncestorOfClass("Model")
						if hitModel and (hitModel.Name:find("Door") or rayResult.Instance.Name:find("Door")) then
							doorBlocking = true
						elseif rayResult.Instance:IsDescendantOf(d) then
							doorBlocking = true
						end
					end

					if doorBlocking then
						Perception.NearSlidingDoor = true
						Perception.DoorIsOpen = false
						if Perception.LastDoorPos and (Perception.LastDoorPos - targetPos).Magnitude < 5 then
							Perception.DoorWaitTime = (Perception.DoorWaitTime or 0) + 0.03
						else
							Perception.DoorWaitTime = 0
						end
						Perception.LastDoorPos = targetPos
						return 1
					else
						Perception.NearSlidingDoor = true
						Perception.DoorIsOpen = true
						Perception.DoorWaitTime = 0
						return 0
					end
				end
			end
		end
	end
	Perception.DoorWaitTime = 0
	Perception.LastDoorPos = nil
	return -1
end

function Perception.IdentifyClassAndWeapon()
	local char = LocalPlayer.Character
	local currentClass = "Civilian"
	local classVal = 0
	local weaponVal = 0

	local classStr = GetPlayerStatus(LocalPlayer, "Class")
	if classStr then
		currentClass = classStr
		for name, val in pairs(ClassIDMap) do
			if string.match(classStr, name) then
				classVal = val
				break
			end
		end
	end

	local activeWeapon = "None"
	local playerModel = Services.Workspace:FindFirstChild(LocalPlayer.Name)
	if playerModel then
		local gunObj = playerModel:FindFirstChild("Gun")
		if gunObj and gunObj:IsA("ObjectValue") then
			local boop = gunObj:FindFirstChild("Boop")
			if boop and boop:IsA("StringValue") then
				activeWeapon = boop.Value
				weaponVal = 1
			end
		end
	end
	Perception.CurrentDetectedWeapon = activeWeapon
	return currentClass, activeWeapon, classVal, weaponVal
end

function Perception.SetupWeaponWatcher()
	local playerModel = Services.Workspace:FindFirstChild(LocalPlayer.Name)
	if not playerModel then
		return
	end

	playerModel.ChildAdded:Connect(function(child)
		if child.Name == "Gun" and child:IsA("ObjectValue") then
			local boop = child:FindFirstChild("Boop")
			if boop and boop:IsA("StringValue") then
				Perception.CurrentDetectedWeapon = boop.Value
			end
			child.ChildAdded:Connect(function(subChild)
				if subChild.Name == "Boop" and subChild:IsA("StringValue") then
					Perception.CurrentDetectedWeapon = subChild.Value
					subChild:GetPropertyChangedSignal("Value"):Connect(function()
						Perception.CurrentDetectedWeapon = subChild.Value
					end)
				end
			end)
		end
	end)
	local existingGun = playerModel:FindFirstChild("Gun")
	if existingGun and existingGun:IsA("ObjectValue") then
		local boop = existingGun:FindFirstChild("Boop")
		if boop and boop:IsA("StringValue") then
			Perception.CurrentDetectedWeapon = boop.Value
			boop:GetPropertyChangedSignal("Value"):Connect(function()
				Perception.CurrentDetectedWeapon = boop.Value
			end)
		end
		existingGun.ChildAdded:Connect(function(child)
			if child.Name == "Boop" and child:IsA("StringValue") then
				Perception.CurrentDetectedWeapon = child.Value
				child:GetPropertyChangedSignal("Value"):Connect(function()
					Perception.CurrentDetectedWeapon = child.Value
				end)
			end
		end)
	end
end

function Perception.IsInSpawnZone()
	local char = LocalPlayer.Character
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local map = Services.Workspace:FindFirstChild("Map")
	if not map then
		return false
	end
	local ignore = map:FindFirstChild("Ignore")
	if not ignore then
		return false
	end

	local myPos = root.Position
	local function checkZone(z)
		local zone = ignore:FindFirstChild(z)
		if zone then
			for _, part in ipairs(zone:GetChildren()) do
				if part:IsA("BasePart") then
					local localPos = part.CFrame:PointToObjectSpace(myPos)
					if
						math.abs(localPos.X) <= part.Size.X / 2
						and math.abs(localPos.Y) <= part.Size.Y / 2
						and math.abs(localPos.Z) <= part.Size.Z / 2
					then
						return true
					end
				end
			end
		end
		return false
	end

	if checkZone("GreenSpawnZone") then
		return true, "Green"
	end
	if checkZone("RedSpawnZone") then
		return true, "Red"
	end
	return false, nil
end

function Perception.IsInRespawnZone()
	-- Used to verify correct respawn using TRCSpawns/TGCSpawns
	local char = LocalPlayer.Character
	if not char then
		return false
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local map = Services.Workspace:FindFirstChild("Map")
	if not map then
		return false
	end

	local myPos = root.Position

	-- Check TRC Spawns (Red Team)
	local trcSpawns = map:FindFirstChild("TRCSpawns")
	if trcSpawns then
		for _, part in ipairs(trcSpawns:GetChildren()) do
			if part:IsA("BasePart") then
				local localPos = part.CFrame:PointToObjectSpace(myPos)
				if
					math.abs(localPos.X) <= part.Size.X / 2
					and math.abs(localPos.Y) <= part.Size.Y / 2
					and math.abs(localPos.Z) <= part.Size.Z / 2
				then
					return true, "Red"
				end
			end
		end
	end

	-- Check TGC Spawns (Green Team)
	local tgcSpawns = map:FindFirstChild("TGCSpawns")
	if tgcSpawns then
		for _, part in ipairs(tgcSpawns:GetChildren()) do
			if part:IsA("BasePart") then
				local localPos = part.CFrame:PointToObjectSpace(myPos)
				if
					math.abs(localPos.X) <= part.Size.X / 2
					and math.abs(localPos.Y) <= part.Size.Y / 2
					and math.abs(localPos.Z) <= part.Size.Z / 2
				then
					return true, "Green"
				end
			end
		end
	end

	return false, nil
end

function Perception.FindNearestSpawnZone()
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	local map = Services.Workspace:FindFirstChild("Map")
	if not map then
		return nil
	end

	local root = char.HumanoidRootPart
	local myPos = root.Position
	local nearestPart = nil
	local nearestDist = math.huge
	local spawnTeam = nil

	-- Check TRC Spawns first
	local trcSpawns = map:FindFirstChild("TRCSpawns")
	if trcSpawns then
		for _, part in ipairs(trcSpawns:GetChildren()) do
			if part:IsA("BasePart") then
				local dist = (part.Position - myPos).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestPart = part
					spawnTeam = "Red"
				end
			end
		end
	end

	-- Check TGC Spawns
	local tgcSpawns = map:FindFirstChild("TGCSpawns")
	if tgcSpawns then
		for _, part in ipairs(tgcSpawns:GetChildren()) do
			if part:IsA("BasePart") then
				local dist = (part.Position - myPos).Magnitude
				if dist < nearestDist then
					nearestDist = dist
					nearestPart = part
					spawnTeam = "Green"
				end
			end
		end
	end

	return nearestPart, spawnTeam
end

function Perception.GetInputs(agent)
	local inputs = {}

	local menuOpen = 0
	local pGui = LocalPlayer:FindFirstChild("PlayerGui")
	if pGui and pGui:FindFirstChild("Menu") and pGui.Menu:FindFirstChild("MenuMain") then
		if pGui.Menu.MenuMain.Visible then
			menuOpen = 1
		end
	end
	table.insert(inputs, menuOpen)

	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("Humanoid") then
		for i = 2, Config.Topology[1] do
			table.insert(inputs, 0)
		end
		return inputs
	end
	Perception.RunScans()
	local root = char.HumanoidRootPart
	local hum = char.Humanoid
	table.insert(inputs, Math.InverseLerp(0, hum.MaxHealth, hum.Health))
	table.insert(inputs, hum.WalkSpeed / 30)
	table.insert(inputs, math.clamp(root.Position.Y / 100, -1, 1))
	local angles = { -60, -45, -30, -15, 0, 15, 30, 45, 60 }
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char, Services.Workspace:FindFirstChild("Ray_Ignore") }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	for _, angle in ipairs(angles) do
		local dir = (root.CFrame * CFrame.Angles(0, math.rad(angle), 0)).LookVector * 60
		local result = Services.Workspace:Raycast(root.Position, dir, rayParams)
		table.insert(inputs, result and (result.Distance / 60) or 1)
	end
	if Perception.CachedEnemy then
		local relative = root.CFrame:PointToObjectSpace(Perception.CachedEnemy.Position)
		local unit = relative.Unit
		table.insert(inputs, unit.X)
		table.insert(inputs, unit.Y)
		table.insert(inputs, unit.Z)
		table.insert(inputs, Math.InverseLerp(0, 300, Perception.CachedDist))
		table.insert(inputs, 1)
	else
		table.insert(inputs, 0)
		table.insert(inputs, 0)
		table.insert(inputs, 0)
		table.insert(inputs, 1)
		table.insert(inputs, -1)
	end
	table.insert(inputs, Perception.CachedDanger)
	table.insert(inputs, Perception.CachedDangerDir.X)
	table.insert(inputs, Perception.CachedDangerDir.Y)
	table.insert(inputs, Perception.ScanSlidingDoors())
	table.insert(inputs, (hum.FloorMaterial == Enum.Material.Air) and 1 or -1)
	local cName, wName, cVal, wVal = Perception.IdentifyClassAndWeapon()
	table.insert(inputs, cVal)
	table.insert(inputs, wVal)

	-- Memory Recurrence
	if agent.SmoothedOutputs then
		for i = 1, 12 do
			table.insert(inputs, agent.SmoothedOutputs[i] or 0)
		end
	else
		for i = 1, 12 do
			table.insert(inputs, 0)
		end
	end

	local inSpawn, teamZone = Perception.IsInSpawnZone()
	table.insert(inputs, inSpawn and 1 or -1)
	table.insert(inputs, math.min(agent.BoredomLevel / Config.Hyperparameters.BoredomThreshold, 1))

	while #inputs < Config.Topology[1] do
		table.insert(inputs, 0)
	end

	return inputs
end

local Agent = {
	CurrentBrain = nil,
	IsActive = true,
	LastShot = 0,
	State = "Idle",
	CurrentRunFitness = 0,

	SmoothedOutputs = {},
	PreviousHealth = 100,
	LastDamageTime = 0,
	LastEnemyDist = 999,

	LastPosition = Vector3.zero,
	LastPos = Vector3.zero,
	BoredomLevel = 0,
	LastActionTime = 0,

	SpawnTimer = 0,
	IsDead = false,
	WasOutside = false,

	LastCameraYaw = 0,
	LastCameraPitch = 0,

	-- Improved targeting
	TargetingYaw = 0,
	TargetingPitch = 0,
	AimConfidence = 0,
	EnemyVelocity = Vector3.zero,

	-- Respawn handling
	RespawnBufferTime = 0,
	LastDeadTime = 0,

	-- Tracking for fitness
	PreviousKills = 0,
	PreviousDamage = 0,
	LastAimTime = 0,
}

function Agent.CheckDeadStatus()
	local playerModel = Services.Workspace:FindFirstChild(LocalPlayer.Name)
	if playerModel then
		local deadVal = playerModel:FindFirstChild("Dead")
		if deadVal and deadVal:IsA("BoolValue") then
			return deadVal.Value
		end
	end
	return false
end

function Agent.CheckGameState()
	local isDead = Agent.CheckDeadStatus()
	if isDead then
		Agent.IsDead = true
		if math.random() < 0.05 then
			Services.VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
			task.wait(0.1)
			Services.VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
		end
		return
	else
		Agent.IsDead = false
	end

	local pGui = LocalPlayer:FindFirstChild("PlayerGui")
	local statusTeam = GetPlayerStatus(LocalPlayer, "Team")

	if pGui and pGui:FindFirstChild("Menu") then
		local menuMain = pGui.Menu:FindFirstChild("MenuMain")
		if
			(not statusTeam or statusTeam == "" or statusTeam == "Neutral") and (not menuMain or not menuMain.Visible)
		then
			Services.VIM:SendKeyEvent(true, Enum.KeyCode.M, false, game)
			task.wait(0.1)
			Services.VIM:SendKeyEvent(false, Enum.KeyCode.M, false, game)
			return
		end

		if menuMain and menuMain.Visible then
			Agent.SpawnTimer = Agent.SpawnTimer + 1
			if Agent.SpawnTimer > 20 then
				Agent.SpawnTimer = 0
				if not statusTeam or statusTeam == "" or statusTeam == "Neutral" then
					local teamWidget = menuMain:FindFirstChild("TeamWidget")
					if teamWidget then
						local holder = teamWidget:FindFirstChild("Teams") and teamWidget.Teams:FindFirstChild("Holder")
						if holder then
							local btnName = (math.random() > 0.5) and "ButtonTGC" or "ButtonTRC"
							local btn = holder:FindFirstChild(btnName)
							if btn then
								local x, y = btn.AbsolutePosition.X, btn.AbsolutePosition.Y
								Services.VIM:SendMouseButtonEvent(x + 10, y + 10, 0, true, game, 1)
								task.wait(0.1)
								Services.VIM:SendMouseButtonEvent(x + 10, y + 10, 0, false, game, 1)
							end
						end
					end
				else
					local key = NumberMap[math.random(1, 9)]
					if key then
						Services.VIM:SendKeyEvent(true, key, false, game)
						task.wait(0.1)
						Services.VIM:SendKeyEvent(false, key, false, game)
					end
				end
			end
		end
	end
end

function Agent.Execute(rawOutputs, dt)
	if not Agent.IsActive or Agent.IsDead then
		return
	end
	local char = LocalPlayer.Character
	if not char or not char:FindFirstChild("Humanoid") then
		return
	end

	-- Respawn buffer: don't move for 1.5 seconds after respawning
	if Agent.RespawnBufferTime > 0 then
		Agent.RespawnBufferTime = Agent.RespawnBufferTime - dt
		-- Release all movement keys during respawn
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.S, false, game)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.A, false, game)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.D, false, game)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.LeftControl, false, game)
		return
	end

	local doorState = Perception.ScanSlidingDoors()
	local doorStuck = (Perception.DoorWaitTime or 0) > 3.0

	if Perception.NearSlidingDoor and not Perception.DoorIsOpen then
		Services.VIM:SendKeyEvent(true, Enum.KeyCode.W, false, game)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.S, false, game)

		if doorStuck then
			local stuckPhase = math.floor(tick() * 2) % 2
			if stuckPhase == 0 then
				Services.VIM:SendKeyEvent(true, Enum.KeyCode.S, false, game)
				Services.VIM:SendKeyEvent(false, Enum.KeyCode.W, false, game)
			end
		end
		rawOutputs[1] = 1
	end

	if #Agent.SmoothedOutputs == 0 then
		for i = 1, #rawOutputs do
			Agent.SmoothedOutputs[i] = 0
		end
	end

	local smoothFactor = math.clamp(dt * Config.Hyperparameters.SmoothingSpeed, 0, 1)
	for i = 1, #rawOutputs do
		Agent.SmoothedOutputs[i] = Math.Lerp(Agent.SmoothedOutputs[i], rawOutputs[i], smoothFactor)
	end
	local out = Agent.SmoothedOutputs

	Services.VIM:SendKeyEvent(out[1] > 0.1, Enum.KeyCode.W, false, game)
	Services.VIM:SendKeyEvent(out[1] < -0.1, Enum.KeyCode.S, false, game)
	Services.VIM:SendKeyEvent(out[2] < -0.1, Enum.KeyCode.A, false, game)
	Services.VIM:SendKeyEvent(out[2] > 0.1, Enum.KeyCode.D, false, game)

	if out[3] > 0.6 then
		char.Humanoid.Jump = true
	end
	Services.VIM:SendKeyEvent(out[12] > 0.5, Enum.KeyCode.LeftControl, false, game)

	-- Improved: Smart targeting system (used for fitness reward, not camera control)
	local hasTarget = false

	if Perception.CachedEnemy then
		hasTarget = true
		local myRoot = char.HumanoidRootPart
		local enemyPos = Perception.CachedEnemy.Position
		local dirToEnemy = (enemyPos - myRoot.Position)
		local distToEnemy = dirToEnemy.Magnitude

		-- Predictive aiming: account for enemy movement
		if Agent.EnemyVelocity then
			local predictionTime = distToEnemy / 100 -- Estimated projectile travel time
			local predictedPos = enemyPos + (Agent.EnemyVelocity * predictionTime * 0.3)
			dirToEnemy = (predictedPos - myRoot.Position)
		end

		dirToEnemy = dirToEnemy.Unit
		local myLook = myRoot.CFrame.LookVector

		-- Calculate aiming confidence (for fitness tracking, not camera control)
		local lookDot = myLook:Dot(dirToEnemy)
		Agent.AimConfidence = math.clamp((lookDot - 0.5) * 2, 0, 1)
	end

	-- Shooting control based on neural network
	if Perception.CachedEnemy and out[6] > 0.3 and tick() - Agent.LastShot > 0.15 then
		Agent.LastShot = tick()
		local mLoc = Services.UIS:GetMouseLocation()
		Services.VIM:SendMouseButtonEvent(mLoc.X, mLoc.Y, 0, true, game, 1)
		task.delay(0.08, function()
			Services.VIM:SendMouseButtonEvent(mLoc.X, mLoc.Y, 0, false, game, 1)
		end)

		Agent.BoredomLevel = math.max(0, Agent.BoredomLevel - 2.0)
	end

	if out[7] > 0.7 then
		local mLoc = Services.UIS:GetMouseLocation()
		Services.VIM:SendMouseButtonEvent(mLoc.X, mLoc.Y, 1, true, game, 1)
		task.delay(0.05, function()
			Services.VIM:SendMouseButtonEvent(mLoc.X, mLoc.Y, 1, false, game, 1)
		end)
	end
end

function Agent.ProcessBoredom(dt)
	if Agent.IsDead then
		return
	end
	if not LocalPlayer.Character then
		return
	end
	local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if not Agent.LastPos then
		Agent.LastPos = root.Position
	end

	local distMoved = (root.Position - Agent.LastPosition).Magnitude
	local movedForward = 0
	local posDelta = root.Position - Agent.LastPos
	if posDelta.Magnitude > 0.001 then
		local lookVector = root.CFrame.LookVector
		movedForward = posDelta:Dot(lookVector)
	end

	Agent.LastPosition = root.Position
	Agent.LastPos = root.Position
	local doorStuck = (Perception.DoorWaitTime or 0) > 3.0

	if movedForward > 0.5 then
		Agent.BoredomLevel = math.max(0, Agent.BoredomLevel - (dt * 5))
	elseif distMoved >= 0.5 then
		Agent.BoredomLevel = math.max(0, Agent.BoredomLevel - (dt * 2))
	else
		if not Perception.NearSlidingDoor and not doorStuck then
			Agent.BoredomLevel = Agent.BoredomLevel + (dt * 2)
		end
	end

	if Agent.BoredomLevel > Config.Hyperparameters.BoredomThreshold then
		Agent.CurrentRunFitness = Agent.CurrentRunFitness - 20
		Services.VIM:SendKeyEvent(true, Enum.KeyCode.Quote, false, game)
		task.wait(0.3)
		Services.VIM:SendKeyEvent(false, Enum.KeyCode.Quote, false, game)
		local char = LocalPlayer.Character
		if char and char:FindFirstChild("Humanoid") then
			char.Humanoid.Health = 0
		end
		Agent.BoredomLevel = 0
	end
end

function Agent.UpdateFitness(dt)
	if Agent.IsDead then
		return
	end
	if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then
		return
	end

	local hum = LocalPlayer.Character.Humanoid
	local root = LocalPlayer.Character.HumanoidRootPart
	local dist = Perception.CachedDist
	local enemy = Perception.CachedEnemy

	if not Agent.LastPos then
		Agent.LastPos = root.Position
	end

	if hum.Health > 0 then
		Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.02 * dt)
	end

	local inSpawn, teamZone = Perception.IsInSpawnZone()
	local pos = root.Position

	if inSpawn then
		Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.01 * dt)
		Agent.WasOutside = false
	else
		Agent.CurrentRunFitness = Agent.CurrentRunFitness + (5.0 * dt)
		Agent.BoredomLevel = 0
		Agent.WasOutside = true

		if Perception.DoorPosition then
			local distFromDoor = (pos - Perception.DoorPosition).Magnitude
			if distFromDoor > 20 then
				Agent.CurrentRunFitness = Agent.CurrentRunFitness + (distFromDoor * 0.1 * dt)
			end
		end
	end

	if Perception.NearSlidingDoor and not Perception.DoorIsOpen then
		local distToDoor = Perception.DoorPosition and (root.Position - Perception.DoorPosition).Magnitude or 999
		if distToDoor < 10 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (2.0 * dt)
		end
	end

	local moved = (pos - Agent.LastPosition).Magnitude
	if moved > 0.1 then
		Agent.CurrentRunFitness = Agent.CurrentRunFitness + (moved * 0.5)
	end

	if enemy then
		-- Track enemy velocity for predictive aiming
		local newVelocity = (enemy.Position - Agent.LastPos)
		Agent.EnemyVelocity = Math.Lerp(Agent.EnemyVelocity or Vector3.zero, newVelocity, 0.3)

		local distDelta = Agent.LastEnemyDist - dist
		if distDelta > 0 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (distDelta * 0.3)
		end
		local look = root.CFrame.LookVector
		local dirToEnemy = (enemy.Position - root.Position).Unit
		local facing = look:Dot(dirToEnemy)

		-- Reward good aim and aiming confidence
		if Agent.AimConfidence > 0.7 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.5 * dt)
		elseif Agent.AimConfidence > 0.5 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.2 * dt)
		end

		if facing > 0.8 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.4 * dt)
		end
		if facing > 0.6 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.15 * dt)
		end
		-- Reward getting closer to enemies
		if dist < 50 then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + (0.5 * dt)
		end

		Agent.LastEnemyDist = dist
	else
		Agent.CurrentRunFitness = Agent.CurrentRunFitness - (0.05 * dt)
		Agent.AimConfidence = 0
	end

	-- Track kills and damage from CurrentLifeStats
	local stats = LocalPlayer:FindFirstChild("CurrentLifeStats")
	if stats then
		local killsVal = stats:FindFirstChild("Kills")
		local damageVal = stats:FindFirstChild("Damage")

		if killsVal and killsVal:IsA("NumberValue") then
			local currentKills = killsVal.Value
			if currentKills > Agent.PreviousKills then
				local killDelta = currentKills - Agent.PreviousKills
				Agent.CurrentRunFitness = Agent.CurrentRunFitness + (killDelta * 50) -- Major reward for each kill
			end
			Agent.PreviousKills = currentKills
		end

		if damageVal and damageVal:IsA("NumberValue") then
			local currentDamage = damageVal.Value
			if currentDamage > Agent.PreviousDamage then
				local damageDelta = currentDamage - Agent.PreviousDamage
				Agent.CurrentRunFitness = Agent.CurrentRunFitness + (damageDelta * 0.5) -- Smaller reward for damage
			end
			Agent.PreviousDamage = currentDamage
		end
	end

	if hum.Health < Agent.PreviousHealth then
		Agent.CurrentRunFitness = Agent.CurrentRunFitness - 3
	end
	Agent.PreviousHealth = hum.Health
	Agent.LastPos = root.Position
end

local UI = {}

function UI.Init()
	if LocalPlayer.PlayerGui:FindFirstChild("SentinelAI") then
		LocalPlayer.PlayerGui.SentinelAI:Destroy()
	end
	local sg = Instance.new("ScreenGui")
	sg.Name = "SentinelAI"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 10
	sg.Parent = (Services.CoreGui:FindFirstChild("RobloxGui") and Services.CoreGui) or LocalPlayer.PlayerGui

	-- MAIN LEFT PANEL
	local main = Instance.new("Frame", sg)
	main.Name = "MainFrame"
	main.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	main.Position = UDim2.new(0.02, 0, 0.5, 0)
	main.Size = UDim2.new(0, 260, 0, 0)
	main.AutomaticSize = Enum.AutomaticSize.Y
	main.BorderSizePixel = 0

	local dragging, dragStart, startPos
	main.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = main.Position
		end
	end)
	main.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			main.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)
	Services.UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	local pad = Instance.new("UIPadding", main)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	local layout = Instance.new("UIListLayout", main)
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder

	local function AddLabel(text, color, order)
		local l = Instance.new("TextLabel", main)
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 18)
		l.Font = Enum.Font.RobotoMono
		l.Text = text
		l.TextColor3 = color or Color3.new(1, 1, 1)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = order
		l.RichText = true
		return l
	end

	AddLabel("<b>:: SENTINEL AI v5.7.1 ::</b>", Color3.fromRGB(0, 255, 200), 1)
	UI.Status = AddLabel("STATUS: INITIALIZING", Color3.fromRGB(255, 255, 255), 2)
	UI.Generation = AddLabel("GEN: 1", Color3.fromRGB(200, 200, 200), 3)
	UI.Fitness = AddLabel("FITNESS: 0", Color3.fromRGB(255, 200, 0), 4)
	UI.Action = AddLabel("ACT: Idle", Color3.fromRGB(150, 150, 255), 5)

	AddLabel("-----------------------", Color3.new(0.4, 0.4, 0.4), 6)
	UI.TeamInfo = AddLabel("TEAM: checking...", Color3.fromRGB(200, 255, 200), 7)
	UI.ClassInfo = AddLabel("CLASS: Unknown", Color3.fromRGB(255, 100, 100), 8)
	UI.WeaponInfo = AddLabel("HELD: None", Color3.fromRGB(255, 100, 100), 9)

	local btn = Instance.new("TextButton", main)
	btn.Size = UDim2.new(1, 0, 0, 25)
	btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	btn.Text = "UNLOAD SCRIPT"
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.SourceSansBold
	btn.LayoutOrder = 10
	Instance.new("UICorner", btn)
	btn.MouseButton1Click:Connect(function()
		Agent.IsActive = false
		Agent.SaveBrain()
		sg:Destroy()
		script:Destroy()
	end)

	-- DEBUG RIGHT PANEL
	local debugPanel = Instance.new("Frame", sg)
	debugPanel.Name = "DebugPanel"
	debugPanel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	debugPanel.Position = UDim2.new(0.98, 0, 0.5, 0)
	debugPanel.Size = UDim2.new(0, 320, 0, 0)
	debugPanel.AutomaticSize = Enum.AutomaticSize.Y
	debugPanel.BorderSizePixel = 0
	debugPanel.AnchorPoint = Vector2.new(1, 0)

	local debugPad = Instance.new("UIPadding", debugPanel)
	debugPad.PaddingTop = UDim.new(0, 10)
	debugPad.PaddingBottom = UDim.new(0, 10)
	debugPad.PaddingLeft = UDim.new(0, 10)
	debugPad.PaddingRight = UDim.new(0, 10)
	local debugLayout = Instance.new("UIListLayout", debugPanel)
	debugLayout.Padding = UDim.new(0, 2)
	debugLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function AddDebugLabel(text, color, order)
		local l = Instance.new("TextLabel", debugPanel)
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 14)
		l.Font = Enum.Font.RobotoMono
		l.Text = text
		l.TextColor3 = color or Color3.new(0.8, 0.8, 0.8)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.LayoutOrder = order
		l.RichText = true
		l.TextSize = 11
		return l
	end

	AddDebugLabel("<b>== DEBUG INFO ==</b>", Color3.fromRGB(100, 200, 255), 0)
	UI.DebugDead = AddDebugLabel("Dead: false", Color3.fromRGB(100, 255, 100), 1)
	UI.DebugRespawnBuffer = AddDebugLabel("RespawnBuf: 0.0s", Color3.fromRGB(255, 200, 100), 2)
	UI.DebugPosition = AddDebugLabel("Pos: (0, 0, 0)", Color3.fromRGB(150, 200, 255), 3)
	UI.DebugInSpawn = AddDebugLabel("InSpawn: false", Color3.fromRGB(100, 255, 100), 4)
	UI.DebugCharExists = AddDebugLabel("Char: ✗", Color3.fromRGB(255, 100, 100), 5)
	UI.DebugEnemy = AddDebugLabel("Enemy: None", Color3.fromRGB(255, 150, 150), 6)
	UI.DebugDist = AddDebugLabel("Dist: 999", Color3.fromRGB(200, 200, 100), 7)
	UI.DebugAim = AddDebugLabel("AimConf: 0.00", Color3.fromRGB(150, 255, 150), 8)
	UI.DebugBoredom = AddDebugLabel("Boredom: 0.00", Color3.fromRGB(255, 150, 150), 9)
	UI.DebugFitness = AddDebugLabel("RunFit: 0", Color3.fromRGB(255, 200, 100), 10)

	-- NEURAL NETWORK VISUALIZATION BUTTON (TOP CENTER)
	local brainButton = Instance.new("TextButton", sg)
	brainButton.Name = "BrainButton"
	brainButton.Size = UDim2.new(0, 120, 0, 30)
	brainButton.Position = UDim2.new(0.5, 0, 0.02, 0)
	brainButton.AnchorPoint = Vector2.new(0.5, 0)
	brainButton.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
	brainButton.TextColor3 = Color3.new(1, 1, 1)
	brainButton.Text = "BRAIN NEURAL MAP"
	brainButton.Font = Enum.Font.GothamBold
	brainButton.TextSize = 11
	Instance.new("UICorner", brainButton).CornerRadius = UDim.new(0, 5)

	UI.BrainVisualActive = false
	brainButton.MouseButton1Click:Connect(function()
		UI.BrainVisualActive = not UI.BrainVisualActive
		brainButton.BackgroundColor3 = UI.BrainVisualActive and Color3.fromRGB(100, 200, 50)
			or Color3.fromRGB(50, 100, 200)
		-- Immediately update canvas visibility
		if UI.BrainVisualActive then
			UI.DrawNeuralNetwork(Agent)
		else
			UI.BrainCanvas.Visible = false
		end
	end)

	-- NEURAL NETWORK CANVAS
	local brainCanvas = Instance.new("Frame", sg)
	brainCanvas.Name = "BrainCanvas"
	brainCanvas.Size = UDim2.new(0, 600, 0, 400)
	brainCanvas.Position = UDim2.new(0.5, 0, 0.08, 0)
	brainCanvas.AnchorPoint = Vector2.new(0.5, 0)
	brainCanvas.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	brainCanvas.BorderColor3 = Color3.fromRGB(100, 200, 255)
	brainCanvas.BorderSizePixel = 2
	brainCanvas.Visible = false
	brainCanvas.ZIndex = 100

	local closeCanvasBtn = Instance.new("TextButton", brainCanvas)
	closeCanvasBtn.Name = "CloseBtn"
	closeCanvasBtn.Size = UDim2.new(0, 30, 0, 30)
	closeCanvasBtn.Position = UDim2.new(1, -35, 0, 5)
	closeCanvasBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeCanvasBtn.Text = "✕"
	closeCanvasBtn.Font = Enum.Font.GothamBold
	closeCanvasBtn.TextColor3 = Color3.new(1, 1, 1)
	closeCanvasBtn.MouseButton1Click:Connect(function()
		brainCanvas.Visible = false
		UI.BrainVisualActive = false
		brainButton.BackgroundColor3 = Color3.fromRGB(50, 100, 200)
	end)

	UI.BrainCanvas = brainCanvas
	UI.BrainButton = brainButton
end

function UI.UpdateDebug(agent)
	if not UI.DebugDead then
		return
	end

	local char = LocalPlayer.Character
	local charExists = char ~= nil
	local inSpawn, zone = Perception.IsInSpawnZone()
	local pos = charExists and char:FindFirstChild("HumanoidRootPart") and char.HumanoidRootPart.Position
		or Vector3.zero

	UI.DebugDead.Text = "Dead: "
		.. (
			Agent.IsDead and "<b><font color='rgb(255,100,100)'>TRUE</font></b>"
			or "<b><font color='rgb(100,255,100)'>false</font></b>"
		)
	UI.DebugRespawnBuffer.Text = string.format("RespawnBuf: %.2fs", Agent.RespawnBufferTime)
	UI.DebugPosition.Text = string.format("Pos: (%.0f, %.0f, %.0f)", pos.X, pos.Y, pos.Z)
	UI.DebugInSpawn.Text = "InSpawn: "
		.. (
			inSpawn and "<b><font color='rgb(100,255,100)'>YES</font></b> (" .. (zone or "?") .. ")"
			or "<b><font color='rgb(255,100,100)'>NO</font></b>"
		)
	UI.DebugCharExists.Text = "Char: " .. (charExists and "✓" or "✗")

	local enemyStatus = Perception.CachedEnemy and "DETECTED" or "None"
	UI.DebugEnemy.Text = "Enemy: " .. enemyStatus
	UI.DebugDist.Text = string.format("Dist: %.1f", Perception.CachedDist)
	UI.DebugAim.Text = string.format("AimConf: %.2f", Agent.AimConfidence)
	UI.DebugBoredom.Text = string.format("Boredom: %.2f", Agent.BoredomLevel)
	UI.DebugFitness.Text = string.format("RunFit: %.0f", Agent.CurrentRunFitness)
end

function UI.DrawNeuralNetwork(agent)
	if not agent or not agent.CurrentBrain then
		return
	end

	local canvas = UI.BrainCanvas

	-- Only show if active
	if not UI.BrainVisualActive then
		canvas.Visible = false
		return
	end

	canvas.Visible = true

	-- Clear previous drawings (preserve close button)
	for _, child in ipairs(canvas:GetChildren()) do
		if child.Name ~= "CloseBtn" then
			child:Destroy()
		end
	end

	local topology = Config.Topology
	local padding = 50
	local canvasWidth = canvas.Size.X.Offset
	local canvasHeight = canvas.Size.Y.Offset - 50
	local layerSpacing = (canvasWidth - 2 * padding) / (#topology - 1)
	local maxNeurons = math.max(unpack(topology))

	-- Draw title
	local titleLabel = Instance.new("TextLabel", canvas)
	titleLabel.Size = UDim2.new(1, 0, 0, 30)
	titleLabel.Position = UDim2.new(0, 0, 0, 5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Neural Network Architecture (Gen " .. agent.CurrentBrain.Generation .. ")"
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
	titleLabel.TextSize = 14

	-- Draw layers and neurons
	local neuronPositions = {}

	for layerIdx, neuronCount in ipairs(topology) do
		neuronPositions[layerIdx] = {}

		local x = padding + (layerIdx - 1) * layerSpacing
		local verticalSpacing = (canvasHeight - 20) / (neuronCount + 1)

		-- Layer label
		local layerLabel = Instance.new("TextLabel", canvas)
		layerLabel.Size = UDim2.new(0, 80, 0, 20)
		layerLabel.Position = UDim2.new(0, x - 40, 1, -25)
		layerLabel.BackgroundTransparency = 1
		layerLabel.Text = "L" .. layerIdx .. "(" .. neuronCount .. ")"
		layerLabel.Font = Enum.Font.RobotoMono
		layerLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
		layerLabel.TextSize = 9

		for neuronIdx = 1, neuronCount do
			local y = 40 + (neuronIdx - 0.5) * (canvasHeight - 60) / neuronCount

			-- Draw neuron circle
			local neuron = Instance.new("Frame", canvas)
			neuron.Size = UDim2.new(0, 12, 0, 12)
			neuron.Position = UDim2.new(0, x - 6, 0, y - 6)
			neuron.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
			neuron.BorderSizePixel = 1
			neuron.BorderColor3 = Color3.fromRGB(200, 220, 255)
			Instance.new("UICorner", neuron).CornerRadius = UDim.new(1, 0)

			neuronPositions[layerIdx][neuronIdx] = { x = x, y = y }
		end

		-- Draw connections to next layer
		if layerIdx < #topology then
			local nextLayerIdx = layerIdx + 1
			local nextNeuronCount = topology[nextLayerIdx]

			for neuronIdx = 1, neuronCount do
				local fromX = neuronPositions[layerIdx][neuronIdx].x
				local fromY = neuronPositions[layerIdx][neuronIdx].y

				for nextNeuronIdx = 1, math.min(nextNeuronCount, 3) do
					local toX = padding + layerIdx * layerSpacing
					local toY = 40 + (nextNeuronIdx - 0.5) * (canvasHeight - 60) / nextNeuronCount

					local line = Instance.new("Frame", canvas)
					local dx = toX - fromX
					local dy = toY - fromY
					local dist = math.sqrt(dx * dx + dy * dy)
					local angle = math.atan2(dy, dx)

					line.Size = UDim2.new(0, dist, 0, 1)
					line.Position = UDim2.new(0, fromX, 0, fromY)
					line.BackgroundColor3 = Color3.fromRGB(80, 120, 180)
					line.BorderSizePixel = 0
					line.Rotation = math.deg(angle)
					line.AnchorPoint = Vector2.new(0, 0.5)
				end
			end
		end
	end
end

function Agent.SaveBrain()
	if not Agent.CurrentBrain then
		return
	end
	local data = {
		Gen = Agent.CurrentBrain.Generation,
		Layers = Agent.CurrentBrain.Layers,
		BestFitness = Agent.CurrentBrain.Fitness,
	}
	pcall(function()
		writefile(Config.Learning.MemoryFile, Services.Http:JSONEncode(data))
	end)
end

function Agent.LoadBrain()
	if isfile(Config.Learning.MemoryFile) then
		local s, data = pcall(function()
			return Services.Http:JSONDecode(readfile(Config.Learning.MemoryFile))
		end)
		if s and data then
			Agent.CurrentBrain.Layers = data.Layers
			Agent.CurrentBrain.Generation = data.Gen
			Agent.CurrentBrain.Fitness = data.BestFitness or 0
			UI.Status.Text = "STATUS: MEMORY LOADED"
			UI.Generation.Text = "GEN: " .. data.Gen
		end
	else
		UI.Status.Text = "STATUS: NEW BRAIN CREATED"
	end
end

function Agent.Init()
	Agent.CurrentBrain = Brain.new(Config.Topology)
	UI.Init()
	Agent.LoadBrain()
	Perception.SetupWeaponWatcher()

	local startScore = 0
	local startTime = 0
	local activeRun = false

	local function GetGameScore()
		local stats = LocalPlayer:FindFirstChild("CurrentLifeStats")
		if stats then
			local shot = stats:FindFirstChild("Shot") and stats.Shot.Value or 0
			local timeAlive = stats:FindFirstChild("TimeAlive") and stats.TimeAlive.Value or 0
			return (shot * 10) + timeAlive
		end
		local ls = LocalPlayer:FindFirstChild("leaderstats")
		if ls then
			local k = ls:FindFirstChild("Kills") and ls.Kills.Value or 0
			local a = ls:FindFirstChild("Assists") and ls.Assists.Value or 0
			return (k * 100) + (a * 50)
		end
		return 0
	end

	local function StartRun()
		activeRun = true
		startTime = tick()
		startScore = GetGameScore()
		Agent.CurrentRunFitness = 0
		Agent.SmoothedOutputs = {}
		Agent.PreviousHealth = 100
		Agent.BoredomLevel = 0
		UI.Status.Text = "STATUS: ACTIVE"
		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			Agent.LastPosition = LocalPlayer.Character.HumanoidRootPart.Position
		end
	end

	local function EndRun()
		if not activeRun then
			return
		end
		activeRun = false

		-- TUNED: Massive penalty for running outside then dying immediately
		if Agent.WasOutside and Agent.IsDead then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness - 350
		elseif Agent.WasOutside then
			Agent.CurrentRunFitness = Agent.CurrentRunFitness + 150
		end

		local duration = tick() - startTime
		local scoreDiff = math.max(0, GetGameScore() - startScore)
		local roundFitness = Agent.CurrentRunFitness + (scoreDiff * 2) + (duration * 0.2)

		Agent.CurrentBrain.Generation = Agent.CurrentBrain.Generation + 1

		if roundFitness > Agent.CurrentBrain.Fitness then
			Agent.CurrentBrain.Fitness = roundFitness
			Agent.SaveBrain()
			UI.Status.Text = "STATUS: EVOLVED (Saved)"
		else
			Agent.CurrentBrain:Mutate()
			UI.Status.Text = "STATUS: MUTATED (Failed)"
		end

		UI.Generation.Text = "GEN: " .. Agent.CurrentBrain.Generation
		UI.Fitness.Text = "LAST: " .. math.floor(roundFitness) .. " | BEST: " .. math.floor(Agent.CurrentBrain.Fitness)
		Agent.SaveBrain()
		Agent.WasOutside = false
	end

	Services.RunService.Heartbeat:Connect(function()
		if not Agent.IsActive then
			return
		end
		local isDead = Agent.CheckDeadStatus()

		-- Detect respawn: was dead, now alive
		if Agent.IsDead and not isDead then
			Agent.RespawnBufferTime = 1.5 -- 1.5 second buffer
			-- Reset all state on respawn
			Agent.SmoothedOutputs = {}
			Agent.TargetingYaw = 0
			Agent.TargetingPitch = 0
			Agent.AimConfidence = 0
			Agent.BoredomLevel = 0
			Agent.PreviousHealth = 100
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
				Agent.LastPosition = LocalPlayer.Character.HumanoidRootPart.Position
				Agent.LastPos = LocalPlayer.Character.HumanoidRootPart.Position
			end
		end

		Agent.IsDead = isDead

		if isDead and activeRun then
			EndRun()
		elseif not isDead and not activeRun and LocalPlayer.Character then
			StartRun()
		end
	end)

	if not Agent.CheckDeadStatus() and LocalPlayer.Character then
		StartRun()
	end

	LogicLoop = Services.RunService.Heartbeat:Connect(function(dt)
		if not Agent.IsActive then
			return
		end

		-- Check death status FIRST
		local isDead = Agent.CheckDeadStatus()

		-- If dead, do NOTHING - let the game handle respawn naturally
		if isDead then
			return
		end

		-- If we just respawned (was dead, now alive)
		if Agent.RespawnBufferTime > 0 then
			Agent.RespawnBufferTime = Agent.RespawnBufferTime - dt

			-- During respawn buffer, try to position player on spawn zone and reduce velocity
			local char = LocalPlayer.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local root = char.HumanoidRootPart
				
				-- On first respawn frame (>1.4s left), verify and position at spawn zone
				if Agent.RespawnBufferTime > 1.4 then
					-- Check if player is in correct respawn zone
					local inRespawnZone, respawnTeam = Perception.IsInRespawnZone()
					if not inRespawnZone then
						-- If not in spawn zone, find nearest and position there
						local spawnPart, spawnTeam = Perception.FindNearestSpawnZone()
						if spawnPart then
							local spawnPos = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0)
							root.CFrame = CFrame.new(spawnPos)
						end
					end
				end
				
				-- Clamp velocity to prevent flinging
				root.AssemblyLinearVelocity = root.AssemblyLinearVelocity * 0.5
			end
			return
		end

		-- Now it's safe to run game logic
		Agent.CheckGameState()

		if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			return
		end

		local inputs = Perception.GetInputs(Agent)
		local outputs = Agent.CurrentBrain:ForwardPropagate(inputs)

		Agent.Execute(outputs, dt)
		Agent.UpdateFitness(dt)
		Agent.ProcessBoredom(dt)

		if tick() % 0.2 < 0.05 then
			local cName, wName = Perception.IdentifyClassAndWeapon()
			UI.ClassInfo.Text = "CLASS: " .. cName
			UI.WeaponInfo.Text = "HELD: " .. wName
			local tm = GetPlayerStatus(LocalPlayer, "Team") or LocalPlayer.Team
			UI.TeamInfo.Text = "TEAM: " .. tostring(tm)
			local inSpawn, zone = Perception.IsInSpawnZone()
			if Perception.NearSlidingDoor then
				UI.Action.Text = "ACT: WAITING FOR DOOR"
			elseif inSpawn then
				UI.Action.Text = string.format(
					"IN SPAWN (%s) [%d%%]",
					zone or "?",
					(Agent.BoredomLevel / Config.Hyperparameters.BoredomThreshold) * 100
				)
			else
				UI.Action.Text = string.format(
					"OUTSIDE ✓ [%d%%]",
					(Agent.BoredomLevel / Config.Hyperparameters.BoredomThreshold) * 100
				)
			end

			-- Update debug UI
			UI.UpdateDebug(Agent)
			UI.DrawNeuralNetwork(Agent)
		end
	end)
end

Services.UIS.InputBegan:Connect(function(input, gp)
	if not gp then
		if input.KeyCode == Enum.KeyCode.G and Services.UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
			Agent.IsActive = false
			Agent.SaveBrain()
			if LocalPlayer.PlayerGui:FindFirstChild("SentinelAI") then
				LocalPlayer.PlayerGui.SentinelAI:Destroy()
			end
		end
	end
end)

Agent.Init()
