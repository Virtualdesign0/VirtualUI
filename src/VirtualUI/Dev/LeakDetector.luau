--!strict

local Profiler = require(script.Parent.Profiler)

local LeakDetector = {}

export type Leak = {
	Scope: string,
	Resource: string,
	Reason: string,
}

type DiagnosticTable = { [string]: unknown }

local enabled = false
local leaks: { Leak } = {}

local function namedField(value: DiagnosticTable, field: string): string?
	local candidate = value[field]
	return if type(candidate) == "string" then candidate else nil
end

local function resourceName(resource: unknown): string
	if type(resource) == "function" then
		return "cleanup callback"
	end
	if typeof(resource) == "Instance" then
		local instance = resource :: Instance
		return `{instance.ClassName} "{instance.Name}"`
	end
	if type(resource) ~= "table" then
		return typeof(resource)
	end
	local candidate = resource :: DiagnosticTable
	return namedField(candidate, "DebugName")
		or namedField(candidate, "Kind")
		or namedField(candidate, "ClassName")
		or typeof(resource)
end

local function hasEntries(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end
	return next(value :: { [unknown]: unknown }) ~= nil
end

local function addLeak(scope: unknown, resource: unknown, reason: string)
	local scopeName = "<anonymous scope>"
	if type(scope) == "table" then
		scopeName = namedField(scope :: DiagnosticTable, "DebugName") or scopeName
	end
	table.insert(leaks, {
		Scope = scopeName,
		Resource = resourceName(resource),
		Reason = reason,
	})
	Profiler.Increment("LeaksDetected")
end

function LeakDetector.SetEnabled(value: boolean)
	enabled = value
end

function LeakDetector.IsEnabled(): boolean
	return enabled
end

function LeakDetector.InspectResource(
	scope: unknown,
	resource: unknown,
	cleanupSucceeded: boolean,
	cleanupError: unknown?
)
	if not enabled then
		return
	end
	if not cleanupSucceeded then
		addLeak(scope, resource, `cleanup failed: {tostring(cleanupError)}`)
		return
	end

	-- Roblox connections are userdata, while test hosts commonly model them as tables.
	-- Check the engine type before the table-only diagnostic probes below.
	if typeof(resource) == "RBXScriptConnection" then
		local connection = resource :: RBXScriptConnection
		if connection.Connected then
			addLeak(scope, resource, "connection remained connected after scope destruction")
		end
		return
	end

	if type(resource) ~= "table" then
		return
	end

	local candidate = resource :: DiagnosticTable
	if candidate.Connected == true then
		addLeak(scope, resource, "connection remained connected after scope destruction")
		return
	end
	if candidate._active == true then
		addLeak(scope, resource, "motion node remained scheduled after scope destruction")
		return
	end
	if hasEntries(candidate.Dependencies) or hasEntries(candidate.Dependents) then
		addLeak(scope, resource, "reactive dependencies remained attached after destruction")
		return
	end
	if candidate.Destroyed == false then
		addLeak(scope, resource, "resource remained alive after scope destruction")
	end
end

function LeakDetector.GetLeaks(): { Leak }
	local snapshot: { Leak } = {}
	for _, leak in leaks do
		table.insert(snapshot, table.clone(leak))
	end
	return snapshot
end

function LeakDetector.Reset()
	table.clear(leaks)
end

function LeakDetector.AssertNoLeaks()
	if #leaks == 0 then
		return
	end

	local lines = table.create(#leaks + 1)
	table.insert(lines, `VirtualUI detected {#leaks} leaked scoped resource(s):`)
	for _, leak in leaks do
		table.insert(lines, `- {leak.Scope} / {leak.Resource}: {leak.Reason}`)
	end
	error(table.concat(lines, "\n"), 2)
end

return LeakDetector
