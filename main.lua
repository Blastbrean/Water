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
