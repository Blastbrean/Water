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
