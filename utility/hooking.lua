local Hooking = {}

local Maid = require("utility/maid")

local hookingMaid = Maid.new()

function Hooking.metamethod(object, methodName, func)
	local old = hookmetamethod(object, methodName, func)

	hookingMaid:add(function()
		hookmetamethod(object, methodName, old)
	end)

	return old
end

function Hooking.func(target, func)
	local old = hookfunction(target, func)

	hookingMaid:add(function()
		hookfunction(target, old)
	end)

	return old
end

return Hooking
