-- Bundled by luabundle {"luaVersion":"5.1","version":"1.6.0"}
local __bundle_require, __bundle_loaded, __bundle_register, __bundle_modules = (function(superRequire)
	local loadingPlaceholder = {[{}] = true}

	local register
	local modules = {}

	local require
	local loaded = {}

	register = function(name, body)
		if not modules[name] then
			modules[name] = body
		end
	end

	require = function(name)
		local loadedModule = loaded[name]

		if loadedModule then
			if loadedModule == loadingPlaceholder then
				return nil
			end
		else
			if not modules[name] then
				if not superRequire then
					local identifier = type(name) == 'string' and '\"' .. name .. '\"' or tostring(name)
					error('Tried to require ' .. identifier .. ', but no such module has been registered')
				else
					return superRequire(name)
				end
			end

			loaded[name] = loadingPlaceholder
			loadedModule = modules[name](require, loaded, register, modules)
			loaded[name] = loadedModule
		end

		return loadedModule
	end

	return require, loaded, register, modules
end)(require)
__bundle_register("__root", function(require, _LOADED, __bundle_register, __bundle_modules)
if not shared then
	return warn("No shared, no script.")
end

repeat
	task.wait()
until game:IsLoaded()

local Water = require("water")

if shared.water then
	shared.water.detach()
end

shared.water = Water
shared.water.init()

end)
__bundle_register("water", function(require, _LOADED, __bundle_register, __bundle_modules)
local Water = {
	hitFromAnywhere = true,

	---@todo: Improve this feature...
	-- If in air and spiking, silent aim down through tilt

	-- Silent aim towards center
	autoGuard = true,

	---@todo: Silent unlocked camera
}

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local Logger = require("utility/logger")
local Maid = require("utility/maid")
local Hooking = require("utility/hooking")
local Gizmos = require("utility/gizmos")

local Physics = require(replicatedStorage:WaitForChild("Common"):WaitForChild("Physics"))
local Knit = require(replicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
local MockPlayer = require(replicatedStorage:WaitForChild("Tools"):WaitForChild("CharBot"):WaitForChild("MockPlayer"))

local gameController = nil

while not gameController do
	gameController = Knit.GetController("GameController")
	task.wait()
end

local oldNameCall = nil
local oldDistanceFromCharacter = nil

local waterMaid = Maid.new()

local function onGetPartsInPart(...)
	if not Water.hitFromAnywhere then
		return oldNameCall(...)
	end

	local taggedBalls = collectionService.GetTagged(collectionService, "Ball")
	if not taggedBalls or #taggedBalls == 0 then
		return oldNameCall(...)
	end

	local ballParts = {}

	for _, taggedBall in next, taggedBalls do
		local ballPart = taggedBall.FindFirstChildWhichIsA(taggedBall, "BasePart")
		if not ballPart then
			continue
		end

		table.insert(ballParts, ballPart)
	end

	return ballParts
end

local function onNameCall(...)
	if getnamecallmethod() == "GetPartsInPart" then
		return onGetPartsInPart(...)
	end

	return oldNameCall(...)
end

local function onDistanceFromCharacter(...)
	if Water.hitFromAnywhere then
		return 0.0
	end

	return oldDistanceFromCharacter(...)
end

local function onRenderStepped()
	if not Water.autoGuard then
		return
	end

	local localPlayer = players.LocalPlayer
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	local taggedBalls = collectionService:GetTagged("Ball")
	if not taggedBalls or #taggedBalls == 0 then
		return
	end

	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end

	local ballCollideOnly = map:FindFirstChild("BallCollideOnly")
	if not ballCollideOnly then
		return
	end

	local net = ballCollideOnly:FindFirstChild("Net")
	if not net then
		return
	end

	if not localPlayer.Team then
		return
	end

	for _, taggedBall in next, taggedBalls do
		local ballPart = taggedBall:FindFirstChildWhichIsA("BasePart")
		if not ballPart then
			continue
		end

		local distanceToBall = (humanoidRootPart.Position - ballPart.Position).Magnitude
		local hitType = distanceToBall <= 20 and "Set" or "Dive"
		local shouldIgnoreNetTop = false

		if gameController.IsJumping:get() then
			hitType = "Spike"
			shouldIgnoreNetTop = true
		end

		local lastHitter = replicatedStorage:GetAttribute("LastHitter")
		local lastHitTeam = replicatedStorage:GetAttribute("LastHitTeam")
		local servedByTeam = replicatedStorage:GetAttribute("ServedByTeam")

		local isOnCorrectSide = Physics.isPointOnTeamSide(localPlayer, ballPart.Position, nil)
		local isBelowNetTop = (ballPart.Position.Y <= net.Position.Y + net.Size.Y) and not shouldIgnoreNetTop
		local isTooFar = distanceToBall <= 50
		local isBallInPlay = replicatedStorage:GetAttribute("IsBallInPlay") == true
		local isLastTouchValid = lastHitTeam and lastHitTeam ~= localPlayer.Team.Name
		local isNotAerialOnServe = not (gameController.IsJumping:get() and servedByTeam ~= nil)
		local isValid = isOnCorrectSide
			and isBelowNetTop
			and isTooFar
			and isBallInPlay
			and isLastTouchValid
			and isNotAerialOnServe

		local status = {}

		local lastHitTimestamp = replicatedStorage:GetAttribute("LastHitTimestamp") or 0.0
		local lastHitPosition = replicatedStorage:GetAttribute("LastHitPosition") or Vector3.new(0.0, 0.0, 0.0)
		local teamHitStreak = replicatedStorage:GetAttribute("TeamHitStreak") or 0
		local servesInRow = replicatedStorage:GetAttribute("ServesInRow") or 0

		status[#status + 1] =
			{ ["Label"] = "Distance to ball", ["Value"] = string.format("%.2f studs", distanceToBall) }

		status[#status + 1] = {
			["Label"] = "Last team touch",
			["Value"] = string.format("%s (served by %s)", tostring(lastHitTeam or "?"), tostring(servedByTeam or "?")),
		}

		status[#status + 1] = {
			["Label"] = "Game touches",
			["Value"] = string.format("%i team hit streak (%i serves in row)", teamHitStreak, servesInRow),
		}

		status[#status + 1] = { ["Label"] = "On correct side?", ["Value"] = isOnCorrectSide and "✓" or "X" }
		status[#status + 1] =
			{ ["Label"] = "Below net top?", ["Value"] = shouldIgnoreNetTop and "I" or (isBelowNetTop and "✓" or "X") }

		status[#status + 1] = { ["Label"] = "Within range?", ["Value"] = isTooFar and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Ball in play?", ["Value"] = isBallInPlay and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Valid last touch?", ["Value"] = isLastTouchValid and "✓" or "X" }
		status[#status + 1] = { ["Label"] = "Not aerial on serve?", ["Value"] = isNotAerialOnServe and "✓" or "X" }

		local text = "Auto guard status..."

		for _, entry in ipairs(status) do
			text = text .. "\n" .. string.format("%s: %s", entry.Label, entry.Value)
		end

		Gizmos.setPosition(ballPart.Position + Vector3.new(0, 5, 0))
		Gizmos.setColor3(isValid and Color3.new(0.0, 1.0, 0.0) or Color3.new(1.0, 0.0, 0.0))
		Gizmos.drawText(text)

		if lastHitPosition then
			Gizmos.setPosition(lastHitPosition)
			Gizmos.setColor3(Color3.new(1.0, 0.0, 1.0))
			Gizmos.drawPoint()
			Gizmos.setPosition(lastHitPosition + Vector3.new(0, 5, 0))

			local info = {}

			local previousHitter = replicatedStorage:GetAttribute("PreviousHitter")
			local lastHitType = replicatedStorage:GetAttribute("LastHitType")

			info[#info + 1] = {
				["Label"] = "Hit position",
				["Value"] = string.format(
					"(%.2f, %.2f, %.2f)",
					lastHitPosition.X,
					lastHitPosition.Y,
					lastHitPosition.Z
				),
			}

			info[#info + 1] = { ["Label"] = "Last hitter", ["Value"] = tostring(lastHitter) }
			info[#info + 1] = { ["Label"] = "Previous hitter", ["Value"] = tostring(previousHitter) }
			info[#info + 1] = { ["Label"] = "Hit type", ["Value"] = tostring(lastHitType) }
			info[#info + 1] = { ["Label"] = "Hit time", ["Value"] = string.format("%.2f", lastHitTimestamp) }

			local infoText = ""

			for _, entry in ipairs(info) do
				infoText = infoText .. "\n" .. string.format("%s: %s", entry.Label, entry.Value)
			end

			Gizmos.drawText(infoText)
		end

		if not isValid then
			continue
		end

		-- Before calling, set thread identity so we don't error from requiring
		setthreadidentity(2)

		if hitType == "Set" then
			gameController:DoMove("Set")
		end

		if hitType == "Spike" then
			gameController:DoMove("Spike")
		end

		if hitType == "Dive" then
			gameController:Dive({ Target = (ballPart.Position - humanoidRootPart.Position).Unit })
		end
	end
end

function Water.init()
	oldNameCall = hookmetamethod(game, "__namecall", onNameCall)
	oldDistanceFromCharacter = Hooking.func(MockPlayer.DistanceFromCharacter, onDistanceFromCharacter)

	waterMaid:mark(runService.RenderStepped:Connect(onRenderStepped))

	Gizmos.init()

	Logger.warn("Water has initialized.")
end

function Water.detach()
	Maid.cleanAll()

	Logger.warn("Water has been detached.")
end

return Water

end)
__bundle_register("utility/gizmos", function(require, _LOADED, __bundle_register, __bundle_modules)
local Gizmos = {}

local runService = game:GetService("RunService")

local Maid = require("utility/maid")

local gizmosMaid = Maid.new()
local gizmosQueue = {}
local gizmosPosition = Vector3.new(0, 0, 0)
local gizmosColor3 = Color3.new(1, 1, 1)
local gizmosThickness = 1.0

local POINT_SCALE = 1

local classCache = {}

local function setVisible(queue, state)
	for _, instance in ipairs(queue) do
		if instance:IsA("BillboardGui") then
			instance.Enabled = state
		else
			instance.Visible = state
		end
	end
end

function Gizmos.init()
	gizmosMaid:mark(runService.RenderStepped:Connect(Gizmos.render))
end

function Gizmos.styleInstance(adornment)
	adornment.Color3 = gizmosColor3
	adornment.AlwaysOnTop = true
	adornment.Adornee = workspace.Terrain
	adornment.AdornCullingMode = Enum.AdornCullingMode.Automatic
	adornment.Visible = false
	adornment.ZIndex = 1
end

function Gizmos.createInstance(className)
	local cache = classCache[className] or { Instance.new(className, workspace) }

	if not cache then
		classCache[className] = cache
	end

	local adornment = table.remove(cache)

	table.insert(gizmosQueue, adornment)

	return gizmosMaid:mark(adornment)
end

function Gizmos.releaseInstance(instance)
	local className = instance.ClassName
	local cache = classCache[className]

	if not cache then
		classCache[className] = {}
		cache = classCache[className]
	end

	table.insert(cache, instance)
end

function Gizmos.setColor3(color3)
	gizmosColor3 = color3
end

function Gizmos.setPosition(position)
	gizmosPosition = position
end

function Gizmos.setThickness(value)
	gizmosThickness = value
end

function Gizmos.drawPoint(position)
	local adornment = Gizmos.createInstance("SphereHandleAdornment")

	Gizmos.styleInstance(adornment)

	adornment.Radius = gizmosThickness * POINT_SCALE * 0.5
	adornment.CFrame = CFrame.new(gizmosPosition + (position or Vector3.zero))
end

function Gizmos.drawText(text)
	local billboard = Gizmos.createInstance("BillboardGui")
	billboard.Adornee = workspace.Terrain
	billboard.AlwaysOnTop = true
	billboard.StudsOffsetWorldSpace = gizmosPosition
	billboard.Size = UDim2.fromOffset(200, 200)
	billboard.ClipsDescendants = false
	billboard.LightInfluence = 0
	billboard.Name = "GizmosBillboardGui"

	local label = Gizmos.createInstance("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.RobotoMono
	label.TextColor3 = gizmosColor3
	label.TextScaled = false
	label.TextSize = 14
	label.TextStrokeTransparency = 0.0
	label.Text = text
	label.Parent = billboard
	label.Name = "GizmosTextLabel"
end

function Gizmos.render()
	local oldQueue = gizmosQueue

	gizmosQueue = {}

	setVisible(oldQueue, true)

	runService.RenderStepped:Wait()

	setVisible(oldQueue, false)

	for _, instance in ipairs(oldQueue) do
		Gizmos.releaseInstance(instance)
	end
end

return Gizmos

end)
__bundle_register("utility/maid", function(require, _LOADED, __bundle_register, __bundle_modules)
local Maid = {}
Maid.__index = Maid

local maidList = {}

function Maid.new()
	local self = setmetatable({
		_tasks = {},
	}, Maid)

	table.insert(maidList, self)

	return self
end

function Maid:__index(index)
	if Maid[index] then
		return Maid[index]
	else
		return self._tasks[index]
	end
end

function Maid:__newindex(index, newTask)
	if Maid[index] ~= nil then
		return warn(("'%s' is reserved"):format(tostring(index)), 2)
	end

	local tasks = self._tasks
	local oldTask = tasks[index]

	if oldTask == newTask then
		return
	end

	tasks[index] = newTask

	if oldTask then
		if typeof(oldTask) == "thread" then
			return coroutine.status(oldTask) == "suspended" and task.cancel(oldTask) or nil
		end

		if type(oldTask) == "function" then
			oldTask()
		elseif typeof(oldTask) == "RBXScriptConnection" then
			oldTask:Disconnect()
		elseif typeof(oldTask) == "Instance" and oldTask:IsA("Tween") then
			oldTask:Pause()
			oldTask:Cancel()
			oldTask:Destroy()
		elseif oldTask.Destroy then
			oldTask:Destroy()
		elseif oldTask.detach then
			oldTask:detach()
		end
	end
end

function Maid:mark(task)
	self:add(task)
	return task
end

function Maid:add(task)
	if not task then
		return error("task cannot be false or nil", 2)
	end

	local taskId = #self._tasks + 1
	self[taskId] = task

	return taskId
end

function Maid:clean()
	local tasks = self._tasks

	for index, task in pairs(tasks) do
		if typeof(task) == "RBXScriptConnection" then
			tasks[index] = nil
			task:Disconnect()
		end
	end

	local index, _task = next(tasks)

	while _task ~= nil do
		tasks[index] = nil

		if typeof(_task) == "thread" then
			if coroutine.status(_task) == "suspended" then
				task.cancel(_task)
			end
		else
			if type(_task) == "function" then
				_task()
			elseif typeof(_task) == "RBXScriptConnection" then
				_task:Disconnect()
			elseif typeof(_task) == "Instance" and _task:IsA("Tween") then
				_task:Pause()
				_task:Cancel()
				_task:Destroy()
			elseif _task.Destroy then
				_task:Destroy()
			elseif _task.detach then
				_task:detach()
			end
		end

		index, _task = next(tasks)
	end
end

function Maid.cleanAll()
	for _, maid in next, maidList do
		maid:clean()
	end
end

return Maid

end)
__bundle_register("utility/hooking", function(require, _LOADED, __bundle_register, __bundle_modules)
local Hooking = {}

local Maid = require("utility/maid")

local hookingMaid = Maid.new()

function Hooking.metamethod(object, methodName, func)
	local old = hookmetamethod(object, methodName, func)

	hookingMaid[#hookingMaid + 1] = function()
		hookmetamethod(object, methodName, old)
	end

	return old
end

function Hooking.func(target, func)
	local old = hookfunction(target, func)

	hookingMaid[#hookingMaid + 1] = function()
		hookfunction(target, old)
	end

	return old
end

return Hooking

end)
__bundle_register("utility/logger", function(require, _LOADED, __bundle_register, __bundle_modules)
local Logger = {}

local function buildPrefixString(str)
	return string.format("[water]: %s", str)
end

function Logger.warn(str, ...)
	warn(string.format(buildPrefixString(str), ...))
end

function Logger.print(str, ...)
	print(string.format(buildPrefixString(str), ...))
end

return Logger

end)
return __bundle_require("__root")