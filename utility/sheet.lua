local Sheet = {}
Sheet.__index = Sheet

function Sheet:build()
	local text = ""

	for _, entry in ipairs(self.data) do
		local representation = nil

		if typeof(entry.value) == "boolean" then
			representation = entry.value and "✓" or "X"
		else
			representation = tostring(entry.value)
		end

		text = text .. "\n" .. entry.label .. ": " .. representation
	end

	return text
end

function Sheet:append(label, value)
	self.data[#self.data + 1] = { label = label, value = value }
end

function Sheet.new()
	return setmetatable({ data = {} }, Sheet)
end

return Sheet
