--!strict

local Profiler = {}

local enabled = false
local counters: { [string]: number } = {}

function Profiler.SetEnabled(value: boolean)
	enabled = value
end

function Profiler.IsEnabled(): boolean
	return enabled
end

function Profiler.Increment(name: string, amount: number?)
	if not enabled then
		return
	end

	counters[name] = (counters[name] or 0) + (amount or 1)
end

function Profiler.Start(): number?
	return if enabled then os.clock() else nil
end

function Profiler.Finish(name: string, started: number?): number
	if not enabled or started == nil then
		return 0
	end

	local elapsedMilliseconds = (os.clock() - started) * 1000
	counters[name] = (counters[name] or 0) + elapsedMilliseconds
	local maximumName = `{name}Max`
	counters[maximumName] = math.max(counters[maximumName] or 0, elapsedMilliseconds)
	return elapsedMilliseconds
end

function Profiler.GetMetrics(): { [string]: number }
	return table.clone(counters)
end

function Profiler.Reset()
	table.clear(counters)
end

return Profiler
