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
