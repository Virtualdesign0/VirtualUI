--!strict

local Fragment = {}
Fragment.__index = Fragment
local Renderable = require(script.Parent.Parent.Renderer.Renderable)

export type Fragment<HostInstance> = {
	GetInstances: (self: Fragment<HostInstance>) -> { HostInstance },
}

export type Child<HostInstance> =
	HostInstance
	| Fragment<HostInstance>
	| Renderable.Value<HostInstance>

local contents: { [{}]: { unknown } } = (
	setmetatable({}, { __mode = "k" }) :: unknown
) :: { [{}]: { unknown } }

function Fragment.Is(value: unknown): boolean
	return type(value) == "table" and contents[value :: {}] ~= nil
end

function Fragment.GetInstances<HostInstance>(self: Fragment<HostInstance>): { HostInstance }
	local instances = contents[self]
	if instances == nil then
		error("Invalid Fragment value", 2)
	end

	local result = {} :: { HostInstance }
	local seen: { [unknown]: boolean } = {}
	for _, value in instances do
		local adapter = Renderable.GetAdapter(value)
		local roots: { unknown } = if adapter == nil then { value } else adapter.GetInstances(value)
		for _, root in roots do
			if seen[root] then
				error("Fragment resolves the same host Instance more than once", 2)
			end
			seen[root] = true
			table.insert(result, root :: HostInstance)
		end
	end
	return result
end

function Fragment.Expand<HostInstance>(rendered: Child<HostInstance>): { Child<HostInstance> }
	if Fragment.Is(rendered) then
		local fragment = (rendered :: unknown) :: {}
		return (table.clone(contents[fragment]) :: unknown) :: { Child<HostInstance> }
	end
	return { rendered }
end

function Fragment.new<HostInstance>(children: { Child<HostInstance> }): Fragment<HostInstance>
	if type(children) ~= "table" then
		error("UI.Fragment requires an array of rendered children", 2)
	end

	local instances: { Child<HostInstance> } = {}
	local seen: { [unknown]: boolean } = {}
	local function append(rendered: Child<HostInstance>)
		for _, instance in Fragment.Expand(rendered) do
			if instance == nil then
				error("UI.Fragment children cannot be nil", 3)
			end
			if seen[instance] then
				error("UI.Fragment cannot contain the same host Instance more than once", 3)
			end
			seen[instance] = true
			table.insert(instances, instance)
		end
	end

	for _, child in children do
		append(child)
	end

	local fragment = (setmetatable({}, Fragment) :: unknown) :: Fragment<HostInstance>
	contents[fragment] = table.freeze(instances) :: { unknown }
	return table.freeze(fragment)
end

return Fragment
