--!strict

local Binding = require(script.Parent.Parent.Renderer.Binding)
local Node = require(script.Parent.Parent.Reactive.Node)
local Renderer = require(script.Parent.Parent.Renderer.Renderer)
local Scheduler = require(script.Parent.Parent.Scheduler.Scheduler)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local State = require(script.Parent.Parent.Reactive.State)
local Profiler = require(script.Parent.Parent.Dev.Profiler)

local Conditional = {}
Conditional.__index = Conditional

export type ConditionalOptions<T, HostInstance> = {
	Parent: HostInstance,
	When: ((T) -> boolean)?,
	Scope: Scope.Scope?,
	DebugName: string?,
}

export type Conditional<T, HostInstance> = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Destroyed: boolean,
	Dirty: boolean,
	Version: number,
	Dependencies: { [Node.GraphNode]: boolean },
	Dependents: { [Node.GraphNode]: boolean },
	_binding: Binding.Binding<T>,
	_render: (value: State.State<T>, scope: Scope.Scope) -> Renderer.Rendered<HostInstance>?,
	_when: ((T) -> boolean)?,
	_parent: HostInstance,
	_ownerScope: Scope.Scope?,
	_host: Renderer.Host<HostInstance, unknown>,
	_branchScope: Scope.Scope?,
	_valueState: State.State<T>?,
	_rendered: Renderer.Rendered<HostInstance>?,
	GetInstance: (self: Conditional<T, HostInstance>) -> HostInstance?,
	GetInstances: (self: Conditional<T, HostInstance>) -> { HostInstance },
	Destroy: (self: Conditional<T, HostInstance>) -> (),
	_read: (self: Conditional<T, HostInstance>) -> (boolean, T),
	_mount: (self: Conditional<T, HostInstance>, value: T) -> (),
	_unmount: (self: Conditional<T, HostInstance>) -> (),
	_apply: (self: Conditional<T, HostInstance>) -> (),
	_invalidate: (self: Conditional<T, HostInstance>, source: Node.GraphNode) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function Conditional.new<T, HostInstance>(
	source: Binding.Source<T>,
	render: (
		value: State.State<T>,
		scope: Scope.Scope
	) -> Renderer.Rendered<HostInstance>?,
	options: ConditionalOptions<T, HostInstance>
): Conditional<T, HostInstance>
	assert(type(render) == "function", "Conditional.new requires a render function")
	assert(type(options) == "table", "Conditional.new requires options")

	local self = (
		setmetatable(Node.New("Conditional", options), Conditional) :: unknown
	) :: Conditional<T, HostInstance>
	self.Dirty = true
	self._binding = Binding.new(source)
	self._render = render
	self._when = options.When
	self._parent = options.Parent
	self._ownerScope = options.Scope
	self._host = Renderer.GetHost()
	self._branchScope = nil
	self._valueState = nil
	self._rendered = nil

	if options.Scope ~= nil then
		options.Scope:Own(self)
	end

	local construction = table.pack(xpcall(function()
		self:_apply()
	end, traceback))
	local ok = construction[1]
	local message = construction[2]
	if not ok then
		self:Destroy()
		error(message, 2)
	end

	return self
end

function Conditional.GetInstance<T, HostInstance>(self: Conditional<T, HostInstance>): HostInstance?
	return Renderer.GetFirstRenderedInstance(self._rendered)
end

function Conditional.GetInstances<T, HostInstance>(self: Conditional<T, HostInstance>): { HostInstance }
	local rendered = self._rendered
	return if rendered == nil then {} else Renderer.GetRenderedInstances(rendered)
end

function Conditional._read<T, HostInstance>(self: Conditional<T, HostInstance>): (boolean, T)
	Node.BeginTracking(self)
	local result = table.pack(xpcall(function()
		return Binding.Read(self._binding)
	end, traceback))
	Node.EndTracking(self)

	if not result[1] then
		error(result[2], 2)
	end

	local value = (result[2] :: unknown) :: T
	local when = self._when
	return if when == nil then value ~= false and value ~= nil else when(value), value
end

function Conditional._mount<T, HostInstance>(self: Conditional<T, HostInstance>, value: T)
	local branchScope = Scope.new({
		DebugName = `{self.DebugName or self.Id}.Branch`,
		Parent = self._ownerScope,
	})
	local valueState = State.new(value, { Scope = branchScope })
	local mounted = table.pack(xpcall(function()
		local rendered = self._render(valueState, branchScope)
		if rendered ~= nil then
			Renderer.OwnRendered(branchScope, rendered, self._host)
			Renderer.ParentRendered(rendered, self._parent, self._host)
		end
		return rendered
	end, traceback))
	local ok = mounted[1]
	local rendered: unknown = mounted[2]

	if not ok then
		local cleanupOk, cleanupMessage = pcall(function()
			branchScope:Destroy()
		end)
		if not cleanupOk then
			rendered = `{rendered}\nBranch cleanup also failed: {cleanupMessage}`
		end
		error(rendered, 2)
	end

	self._branchScope = branchScope
	self._valueState = valueState
	self._rendered = rendered :: Renderer.Rendered<HostInstance>?
	Profiler.Increment("StructuralMounts")
end

function Conditional._unmount<T, HostInstance>(self: Conditional<T, HostInstance>)
	local branchScope = self._branchScope
	self._branchScope = nil
	self._valueState = nil
	self._rendered = nil
	if branchScope ~= nil then
		branchScope:Destroy()
		Profiler.Increment("StructuralUnmounts")
	end
end

function Conditional._apply<T, HostInstance>(self: Conditional<T, HostInstance>)
	if self.Destroyed or not self.Dirty then
		return
	end

	self.Dirty = false
	local shouldMount, value = self:_read()
	local mounted = self._branchScope ~= nil
	if shouldMount and not mounted then
		self:_mount(value)
	elseif shouldMount then
		local valueState = self._valueState
		assert(valueState ~= nil, "Mounted Conditional must retain its value state")
		valueState:Set(value)
	elseif not shouldMount and mounted then
		self:_unmount()
	end

	self.Version = (self.Version :: number) + 1
	Profiler.Increment("StructuralEvaluations")
end

function Conditional._invalidate<T, HostInstance>(self: Conditional<T, HostInstance>, _source: Node.GraphNode)
	if self.Destroyed or self.Dirty then
		return
	end
	self.Dirty = true
	Scheduler.EnqueueStructure(self)
end

function Conditional.Destroy<T, HostInstance>(self: Conditional<T, HostInstance>)
	if self.Destroyed then
		return
	end
	self:_unmount()
	Node.Destroy(self)
end

return Conditional
