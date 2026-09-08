--!strict

local Binding = require(script.Parent.Binding)
local Node = require(script.Parent.Parent.Reactive.Node)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local Registry = require(script.Parent.Parent.Resolve.PseudoPropertyRegistry)
local Trace = require(script.Parent.Parent.Dev.Trace)
local HostTypes = require(script.Parent.Host)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local PseudoPropertyBinding = {}
PseudoPropertyBinding.__index = PseudoPropertyBinding

type PropertyResolver = {
	Resolve: (className: string, propertyName: string, value: unknown) -> unknown,
}

export type PseudoPropertyBinding<Input, HostInstance, HostConnection> = {
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
	_name: string,
	_binding: Binding.Binding<Input>,
	_descriptor: Registry.Descriptor,
	_host: HostTypes.Host<HostInstance, HostConnection>,
	_propertyResolver: PropertyResolver,
	_hasValue: boolean,
	_previousValue: Input?,
	_apply: (self: PseudoPropertyBinding<Input, HostInstance, HostConnection>) -> (),
	_invalidate: (
		self: PseudoPropertyBinding<Input, HostInstance, HostConnection>,
		source: Node.GraphNode
	) -> (),
	Destroy: (self: PseudoPropertyBinding<Input, HostInstance, HostConnection>) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function writeProperties<Input, HostInstance, HostConnection>(
	self: PseudoPropertyBinding<
		Input,
		HostInstance,
		HostConnection
	>,
	rawValue: Input
)
	local properties = Registry.Resolve(self._descriptor, rawValue)
	local tracing = Trace.IsEnabled()
	for _, propertyName in self._descriptor.Properties do
		local value = properties[propertyName]
		local resolved =
			self._propertyResolver.Resolve(self._descriptor.ClassName, propertyName, value)
		self._host.WriteProperty(self._instance, propertyName, resolved)
		if tracing then
			Trace.Record("PropertyWrite", {
				NodeId = self.Id,
				NodeKind = self.Kind,
				DebugName = self.DebugName,
				Property = `{self._descriptor.ClassName}.{propertyName}`,
				Next = Trace.Value(resolved),
			})
		end
		Profiler.Increment("PseudoPropertyWrites")
	end
end

function PseudoPropertyBinding.new<Input, HostInstance, HostConnection>(
	instance: HostInstance,
	name: string,
	binding: Binding.Binding<Input>,
	descriptor: Registry.Descriptor,
	host: HostTypes.Host<
		HostInstance,
		HostConnection
	>,
	propertyResolver: PropertyResolver,
	scope: Scope.Scope
): PseudoPropertyBinding<
	Input,
	HostInstance,
	HostConnection
>
	local self = (
		setmetatable(
			Node.New("Binding", {
				DebugName = binding.DebugName or `Pseudo.{name}`,
				Scope = scope,
			}),
			PseudoPropertyBinding
		) :: unknown
	) :: PseudoPropertyBinding<Input, HostInstance, HostConnection>
	self.Dirty = true
	self._instance = instance
	self._name = name
	self._binding = binding
	self._descriptor = descriptor
	self._host = host
	self._propertyResolver = propertyResolver
	self._hasValue = false
	self._previousValue = nil
	scope:Own(self)
	self:_apply()
	return self
end

function PseudoPropertyBinding._apply<Input, HostInstance, HostConnection>(
	self: PseudoPropertyBinding<
		Input,
		HostInstance,
		HostConnection
	>
)
	if self.Destroyed or not self.Dirty then
		return
	end

	Node.BeginTracking(self)
	local read = table.pack(xpcall(function()
		return Binding.Read(self._binding)
	end, traceback))
	Node.EndTracking(self)
	self.Dirty = false
	if not read[1] then
		self._errorSource = next(self.Dependencies)
		error(read[2], 2)
	end

	local rawValue = (read[2] :: unknown) :: Input
	if
		self._hasValue
		and self._binding.Equals((self._previousValue :: unknown) :: Input, rawValue)
	then
		Profiler.Increment("PseudoPropertyWriteSkips")
		return
	end
	writeProperties(self, rawValue)
	self._previousValue = rawValue
	self._hasValue = true
	self.Version += 1
end

function PseudoPropertyBinding._invalidate<Input, HostInstance, HostConnection>(
	self: PseudoPropertyBinding<
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

function PseudoPropertyBinding.Destroy<Input, HostInstance, HostConnection>(
	self: PseudoPropertyBinding<
		Input,
		HostInstance,
		HostConnection
	>
)
	Node.Destroy(self)
end

return PseudoPropertyBinding
