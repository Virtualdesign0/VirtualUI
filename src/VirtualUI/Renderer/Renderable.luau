--!strict

local Scope = require(script.Parent.Parent.Lifetime.Scope)

local Renderable = {}

export type Adapter = {
	GetRendered: (value: unknown) -> unknown,
	GetInstances: (value: unknown) -> { unknown },
	GetScope: (value: unknown) -> Scope.Scope?,
	GetErrorScope: ((value: unknown) -> Scope.Scope?)?,
	WillAttach: ((value: unknown, parent: unknown?, startOrder: number?) -> ())?,
	DidAttach: (value: unknown, parent: unknown?, startOrder: number?) -> (),
	Destroy: (value: unknown) -> (),
}

export type Value<HostInstance> = {
	GetRendered: (self: Value<HostInstance>) -> unknown,
	GetInstances: (self: Value<HostInstance>) -> { HostInstance },
	Destroy: (self: Value<HostInstance>) -> (),
}

local adapters = setmetatable({} :: { [{}]: Adapter }, { __mode = "k" })

function Renderable.Register(value: {}, adapter: Adapter)
	if adapters[value] ~= nil then
		error("Renderable value must be non-nil and registered exactly once", 2)
	end
	adapters[value] = adapter
end

function Renderable.GetAdapter(value: unknown): Adapter?
	if type(value) ~= "table" then
		return nil
	end
	return adapters[value :: {}]
end

function Renderable.Is(value: unknown): boolean
	return Renderable.GetAdapter(value) ~= nil
end

return Renderable
