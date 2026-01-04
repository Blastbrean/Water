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
