--!strict

local ComputedModule = require(script.Parent.Parent.Reactive.Computed)
local EffectModule = require(script.Parent.Parent.Reactive.Effect)
local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Renderer = require(script.Parent.Parent.Renderer.Renderer)
local Renderable = require(script.Parent.Parent.Renderer.Renderable)
local ScopeModule = require(script.Parent.Parent.Lifetime.Scope)
local StateModule = require(script.Parent.Parent.Reactive.State)

local Component = {}

export type ComponentOptions<HostInstance> = {
	Parent: HostInstance?,
	Scope: ScopeModule.Scope?,
	DebugName: string?,
}

export type ComponentInstance<Props, HostInstance> = {
	props: Props,
	Scope: ScopeModule.Scope,
	Name: string,
	DebugName: string,
	Destroyed: boolean,
	State: <T>(
		self: ComponentInstance<Props, HostInstance>,
		initialValue: T,
		options: StateModule.StateOptions<T>?
	) -> StateModule.State<T>,
	Computed: <T>(
		self: ComponentInstance<Props, HostInstance>,
		compute: () -> T,
		options: ComputedModule.ComputedOptions<T>?
	) -> ComputedModule.Computed<T>,
	Effect: (
		self: ComponentInstance<Props, HostInstance>,
		callback: EffectModule.EffectCallback,
		options: EffectModule.EffectOptions?
	) -> EffectModule.Effect,
	GetRendered: (self: ComponentInstance<Props, HostInstance>) -> Renderer.Rendered<HostInstance>,
	GetInstance: (self: ComponentInstance<Props, HostInstance>) -> HostInstance?,
	GetInstances: (self: ComponentInstance<Props, HostInstance>) -> { HostInstance },
	Destroy: (self: ComponentInstance<Props, HostInstance>) -> (),
	[string]: any,
}

export type ComponentClass<Props> = {
	Name: string,
	new: <HostInstance>(
		props: Props,
		options: ComponentOptions<HostInstance>?
	) -> ComponentInstance<Props, HostInstance>,
	init: ((self: any) -> ())?,
	render: ((self: any) -> any)?,
	didMount: ((self: any) -> ())?,
	willUnmount: ((self: any) -> ())?,
	[string]: any,
}

export type ComponentAPI = {
	extend: <Props>(self: any, name: string) -> ComponentClass<Props>,
}

type RuntimeClass = {
	Name: string,
	[string]: unknown,
}

type InternalComponent = {
	props: unknown,
	Scope: ScopeModule.Scope,
	Name: string,
	DebugName: string,
	Destroyed: boolean,
	_mounted: boolean,
	_unmounting: boolean,
	_rendered: unknown?,
	init: unknown?,
	render: unknown?,
	didMount: unknown?,
	willUnmount: unknown?,
	[string]: unknown,
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function assertAlive(self: InternalComponent)
	if self.Destroyed then
		error(`Attempted to use destroyed Component "{self.DebugName}"`, 3)
	end
end

local function assertCanOwn(self: InternalComponent)
	assertAlive(self)
	if self.Scope.Destroyed then
		error(`Component "{self.DebugName}" cannot create resources while unmounting`, 3)
	end
end

function Component.State<T>(
	self: InternalComponent,
	initialValue: T,
	options: StateModule.StateOptions<T>?
): StateModule.State<T>
	assertCanOwn(self)
	local resolvedOptions: StateModule.StateOptions<T> = {
		Equals = if options == nil then nil else options.Equals,
		DebugName = if options == nil then nil else options.DebugName,
		Scope = self.Scope,
	}
	return StateModule.new(initialValue, resolvedOptions)
end

function Component.Computed<T>(
	self: InternalComponent,
	compute: () -> T,
	options: ComputedModule.ComputedOptions<T>?
): ComputedModule.Computed<T>
	assertCanOwn(self)
	local resolvedOptions: ComputedModule.ComputedOptions<T> = {
		Equals = if options == nil then nil else options.Equals,
		DebugName = if options == nil then nil else options.DebugName,
		Scope = self.Scope,
	}
	return ComputedModule.new(compute, resolvedOptions)
end

function Component.Effect(
	self: InternalComponent,
	callback: EffectModule.EffectCallback,
	options: EffectModule.EffectOptions?
): EffectModule.Effect
	assertCanOwn(self)
	local resolvedOptions: EffectModule.EffectOptions = {
		DebugName = if options == nil then nil else options.DebugName,
		Scope = self.Scope,
	}
	return EffectModule.new(callback, resolvedOptions)
end

function Component.GetRendered(self: InternalComponent): unknown
	assertAlive(self)
	return self._rendered
end

function Component.GetInstance(self: InternalComponent): unknown?
	assertAlive(self)
	return Renderer.GetFirstRenderedInstance(self._rendered)
end

function Component.GetInstances(self: InternalComponent): { unknown }
	assertAlive(self)
	return Renderer.GetRenderedInstances(self._rendered)
end

local function finalize(instance: InternalComponent)
	if instance.Destroyed or instance._unmounting then
		return
	end

	instance._unmounting = true
	local lifecycleError: unknown = nil
	if instance._mounted then
		local willUnmount = instance.willUnmount
		if type(willUnmount) == "function" then
			local result = table.pack(xpcall(function()
				(willUnmount :: (InternalComponent) -> ())(instance)
			end, traceback))
			if not result[1] then
				lifecycleError = result[2]
			end
		end
		Profiler.Increment("ComponentUnmounts")
	end

	instance._mounted = false
	instance._rendered = nil
	instance.Destroyed = true
	instance._unmounting = false
	if lifecycleError ~= nil then
		error(lifecycleError, 2)
	end
end

function Component.Destroy(self: InternalComponent)
	if self.Destroyed then
		return
	end
	self.Scope:Destroy()
end

local function activate(instance: InternalComponent)
	assertAlive(instance)
	if instance._mounted then
		return
	end

	instance._mounted = true
	Profiler.Increment("ComponentMounts")
	local didMount = instance.didMount
	if type(didMount) ~= "function" then
		return
	end

	local mounted = table.pack(xpcall(function()
		(didMount :: (InternalComponent) -> ())(instance)
	end, traceback))
	if mounted[1] then
		return
	end

	local message: unknown = mounted[2]
	local cleanup = table.pack(xpcall(function()
		instance.Scope:Destroy()
	end, traceback))
	if not cleanup[1] then
		message = `{message}\nComponent cleanup also failed: {cleanup[2]}`
	end
	error(message, 3)
end

local componentAdapter: Renderable.Adapter = {
	GetRendered = function(value: unknown): unknown
		return (value :: InternalComponent)._rendered
	end,
	GetInstances = function(value: unknown): { unknown }
		return Renderer.GetRenderedInstances((value :: InternalComponent)._rendered)
	end,
	GetScope = function(value: unknown): ScopeModule.Scope
		return (value :: InternalComponent).Scope
	end,
	DidAttach = function(value: unknown, _parent: unknown?, _startOrder: number?)
		activate(value :: InternalComponent)
	end,
	Destroy = function(value: unknown)
		Component.Destroy(value :: InternalComponent)
	end,
}

local function instantiate(
	class: RuntimeClass,
	props: unknown,
	options: unknown?
): InternalComponent
	if options ~= nil and type(options) ~= "table" then
		error("Component options must be a table", 3)
	end
	local resolvedOptions: ComponentOptions<unknown> = if options == nil
		then {}
		else options :: ComponentOptions<unknown>
	if props ~= nil and type(props) ~= "table" then
		error("Component props must be a table", 3)
	end
	local rawProps = if props == nil then {} else props :: { [string]: unknown }

	local propsSnapshot = table.clone(rawProps)
	table.freeze(propsSnapshot)
	local componentName = class.Name
	local debugName = resolvedOptions.DebugName or componentName
	local host = Renderer.GetHost()
	local scopeOptions: ScopeModule.ScopeOptions = {
		DebugName = `{debugName}Scope`,
		Parent = resolvedOptions.Scope,
	}
	local scope = ScopeModule.new(scopeOptions)
	local instance = (
		setmetatable({
			props = propsSnapshot,
			Scope = scope,
			Name = componentName,
			DebugName = debugName,
			Destroyed = false,
			_mounted = false,
			_unmounting = false,
			_rendered = nil,
		}, class) :: unknown
	) :: InternalComponent
	scope:AddBeforeDestroy(function()
		finalize(instance)
	end)

	local mountStarted = Profiler.Start()
	local construction = table.pack(xpcall(function()
		local init = instance.init
		if type(init) == "function" then
			local callInit = init :: (InternalComponent) -> ()
			callInit(instance)
		end

		local render = instance.render
		if type(render) ~= "function" then
			error(`Component "{componentName}" must define render()`, 2)
		end
		local callRender = render :: (InternalComponent) -> unknown
		local rendered = callRender(instance)
		Profiler.Increment("ComponentRenders")
		if rendered == nil then
			error(`Component "{componentName}" render() returned nil`, 2)
		end

		local renderedValue = (rendered :: unknown) :: Renderer.Rendered<unknown>
		instance._rendered = renderedValue
		Renderable.Register(instance, componentAdapter)
		Renderer.OwnRendered(scope, renderedValue, host)
		if resolvedOptions.Parent ~= nil then
			Renderer.ParentRendered(
				(instance :: unknown) :: Renderable.Value<unknown>,
				resolvedOptions.Parent,
				host
			)
		end
	end, traceback))
	Profiler.Finish("ComponentMountMs", mountStarted)

	if not construction[1] then
		local message: unknown = construction[2]
		local cleanup = table.pack(xpcall(function()
			scope:Destroy()
		end, traceback))
		if not cleanup[1] then
			message = `{message}\nComponent cleanup also failed: {cleanup[2]}`
		end
		error(message, 3)
	end

	return instance
end

function Component.extend(self: unknown, name: string): unknown
	if self ~= Component then
		error("Component types cannot be extended; prefer composition", 2)
	end
	if type(name) ~= "string" or name == "" then
		error("Component:extend requires a non-empty name", 2)
	end

	local class: RuntimeClass = {
		Name = name,
	}
	class.__index = class
	class.new = function(props: unknown, options: unknown?): InternalComponent
		return instantiate(class, props, options)
	end
	setmetatable(class, { __index = Component })
	return class
end

return (Component :: unknown) :: ComponentAPI
