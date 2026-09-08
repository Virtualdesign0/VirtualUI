--!strict

local Binding = require(script.Parent.Binding)
local Node = require(script.Parent.Parent.Reactive.Node)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Dev.Trace)
local HostTypes = require(script.Parent.Host)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local PropertyBinding = {}
PropertyBinding.__index = PropertyBinding

type Resolver = {
	Resolve: (className: string, propertyName: string, value: unknown) -> unknown,
}

export type PropertyBinding<Input, HostInstance, HostConnection> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_errorSource: Node.GraphNode?,
	_instance: HostInstance,
	_className: string,
	_propertyName: string,
	_binding: Binding.Binding<Input>,
	_host: HostTypes.Host<HostInstance, HostConnection>,
	_resolver: Resolver,
	_hasValue: boolean,
	_previousRawValue: Input?,
	_previousValue: unknown,
	_apply: (self: PropertyBinding<Input, HostInstance, HostConnection>) -> (),
	_invalidate: (
		self: PropertyBinding<Input, HostInstance, HostConnection>,
		source: Node.GraphNode
	) -> (),
	Destroy: (self: PropertyBinding<Input, HostInstance, HostConnection>) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function PropertyBinding.new<Input, HostInstance, HostConnection>(
	instance: HostInstance,
	className: string,
	propertyName: string,
	binding: Binding.Binding<Input>,
	host: HostTypes.Host<
		HostInstance,
		HostConnection
	>,
	resolver: Resolver,
	scope: Scope.Scope
): PropertyBinding<
	Input,
	HostInstance,
	HostConnection
>
	local self = (
		setmetatable(
			Node.New("Binding", {
				DebugName = binding.DebugName or `{className}.{propertyName}`,
				Scope = scope,
			}),
			PropertyBinding
		) :: unknown
	) :: PropertyBinding<Input, HostInstance, HostConnection>

	self.Dirty = true
	self._instance = instance
	self._className = className
	self._propertyName = propertyName
	self._binding = binding
	self._host = host
	self._resolver = resolver
	self._hasValue = false
	self._previousRawValue = nil
	self._previousValue = nil

	scope:Own(self)
	self:_apply()
	return self
end

function PropertyBinding._apply<Input, HostInstance, HostConnection>(self: PropertyBinding<
	Input,
	HostInstance,
	HostConnection
>)
	if self.Destroyed or not self.Dirty then
		return
	end

	Node.BeginTracking(self)
	local result = table.pack(xpcall(function()
		return Binding.Read(self._binding)
	end, traceback))
	Node.EndTracking(self)
	self.Dirty = false
	Profiler.Increment("BindingEvaluations")

	if not result[1] then
		self._errorSource = next(self.Dependencies)
		error(result[2], 2)
	end

	local rawValue = (result[2] :: unknown) :: Input
	if
		self._hasValue
		and self._binding.Equals((self._previousRawValue :: unknown) :: Input, rawValue)
	then
		Profiler.Increment("PropertyWriteSkips")
		return
	end

	local value = self._resolver.Resolve(self._className, self._propertyName, rawValue)
	self._host.WriteProperty(self._instance, self._propertyName, value)
	if Trace.IsEnabled() then
		Trace.Record("PropertyWrite", {
			NodeId = self.Id,
			NodeKind = self.Kind,
			DebugName = self.DebugName,
			Property = `{self._className}.{self._propertyName}`,
			Previous = if self._hasValue then Trace.Value(self._previousValue) else nil,
			Next = Trace.Value(value),
		})
	end
	self._previousRawValue = rawValue
	self._previousValue = value
	self._hasValue = true
	self.Version += 1
	Profiler.Increment("PropertyWrites")
	if self._propertyName == "LayoutOrder" then
		Profiler.Increment("LayoutOrderWrites")
	end
end

function PropertyBinding._invalidate<Input, HostInstance, HostConnection>(
	self: PropertyBinding<
		Input,
		HostInstance,
		HostConnection
	>,
	_source: Node.GraphNode
)
	if self.Destroyed or self.Dirty then
		return
	end

	self.Dirty = true
	Scheduler.EnqueueBinding(self)
end

function PropertyBinding.Destroy<Input, HostInstance, HostConnection>(self: PropertyBinding<
	Input,
	HostInstance,
	HostConnection
>)
	Node.Destroy(self)
end

return PropertyBinding
