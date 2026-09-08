--!strict

local Binding = require(script.Parent.Binding)
local Config = require(script.Parent.Parent.Runtime.Config)
local DefaultHost = require(script.Parent.DefaultHost)
local HostTypes = require(script.Parent.Host)
local PropertyBinding = require(script.Parent.PropertyBinding)
local PseudoPropertyRegistry = require(script.Parent.Parent.Resolve.PseudoPropertyRegistry)
local PseudoPropertyRenderer = require(script.Parent.PseudoPropertyRenderer)
local EventResolver = require(script.Parent.Parent.Resolve.EventResolver)
local Fragment = require(script.Parent.Parent.Structural.Fragment)
local Renderable = require(script.Parent.Renderable)
local PropertyResolver = require(script.Parent.Parent.Resolve.PropertyResolver)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local Trace = require(script.Parent.Parent.Dev.Trace)

local Renderer = {}

export type Host<HostInstance, HostConnection> = HostTypes.Host<HostInstance, HostConnection>
export type Rendered<HostInstance> =
	HostInstance
	| Fragment.Fragment<HostInstance>
	| Renderable.Value<HostInstance>

local activeHost: HostTypes.Host<any, unknown> = DefaultHost
local instanceScopes: { [unknown]: Scope.Scope } = (
	setmetatable({}, { __mode = "k" }) :: unknown
) :: { [unknown]: Scope.Scope }

function Renderer.GetRenderedInstances<HostInstance>(rendered: Rendered<HostInstance>): { HostInstance }
	local instances: { HostInstance } = {}
	local seen: { [unknown]: boolean } = {}
	local visiting: { [unknown]: boolean } = {}
	local function append(value: unknown)
		if Fragment.Is(value) then
			local fragment = (value :: unknown) :: Fragment.Child<unknown>
			for _, child in Fragment.Expand(fragment) do
				append(child)
			end
			return
		end

		local adapter = Renderable.GetAdapter(value)
		if adapter ~= nil then
			if visiting[value] then
				error("Renderable composition cycle detected", 3)
			end
			visiting[value] = true
			append(adapter.GetRendered(value))
			visiting[value] = nil
			return
		end

		if value == nil then
			error("Rendered values cannot contain nil", 3)
		end
		if seen[value] then
			error("Rendered value resolves the same host Instance more than once", 3)
		end
		seen[value] = true
		table.insert(instances, value :: HostInstance)
	end

	append(rendered)
	return instances
end

function Renderer.GetFirstRenderedInstance<HostInstance>(rendered: Rendered<HostInstance>?): HostInstance?
	if rendered == nil then
		return nil
	end
	return Renderer.GetRenderedInstances(rendered)[1]
end

function Renderer.OwnRendered<HostInstance, HostConnection>(
	scope: Scope.Scope,
	rendered: Rendered<HostInstance>,
	host: Host<HostInstance, HostConnection>
)
	if Fragment.Is(rendered) then
		local fragment = (rendered :: unknown) :: Fragment.Child<HostInstance>
		for _, child in Fragment.Expand(fragment) do
			Renderer.OwnRendered(scope, child, host)
		end
		return
	end

	local adapter = Renderable.GetAdapter(rendered)
	if adapter ~= nil then
		local renderableScope = adapter.GetScope(rendered)
		if renderableScope ~= nil then
			if not scope:Contains(renderableScope) then
				scope:_adopt(renderableScope)
			end
		else
			scope:Own(rendered, adapter.Destroy)
		end
		return
	end

	local hostInstance = rendered :: HostInstance
	local instanceScope = instanceScopes[hostInstance]
	if instanceScope ~= nil then
		if not scope:Contains(instanceScope) then
			scope:_adopt(instanceScope)
		end
	else
		scope:Own(hostInstance, function(value: HostInstance)
			host.DestroyInstance(value)
		end)
	end
end

function Renderer.ParentRendered<HostInstance, HostConnection>(
	rendered: Rendered<HostInstance>,
	parent: HostInstance,
	host: Host<
		HostInstance,
		HostConnection
	>,
	startOrder: number?
): number
	local setChildOrder = host.SetChildOrder
	local nextOrder = startOrder or 1
	local visiting: { [unknown]: boolean } = {}
	local function attach(value: unknown)
		if Fragment.Is(value) then
			local fragment = (value :: unknown) :: Fragment.Child<unknown>
			for _, child in Fragment.Expand(fragment) do
				attach(child)
			end
			return
		end

		local adapter = Renderable.GetAdapter(value)
		if adapter ~= nil then
			if visiting[value] then
				error("Renderable composition cycle detected", 3)
			end
			visiting[value] = true
			local adapterStartOrder = nextOrder
			local errorScope = if adapter.GetErrorScope == nil
				then adapter.GetScope(value)
				else adapter.GetErrorScope(value)
			local errorRoute = Scope.CaptureErrorRoute(errorScope)
			local function performAttach()
				if adapter.WillAttach ~= nil then
					adapter.WillAttach(
						value,
						parent,
						if startOrder == nil then nil else adapterStartOrder
					)
				end
				attach(adapter.GetRendered(value))
				adapter.DidAttach(
					value,
					parent,
					if startOrder == nil then nil else adapterStartOrder
				)
			end
			if #errorRoute == 0 and not Trace.IsEnabled() then
				performAttach()
			else
				local attached = table.pack(xpcall(performAttach, function(errorMessage)
					return debug.traceback(tostring(errorMessage), 2)
				end))
				if not attached[1] then
					local renderableName = tostring(value)
					if type(value) == "table" then
						local candidate = value :: { [string]: unknown }
						if type(candidate.DebugName) == "string" then
							renderableName = candidate.DebugName
						elseif type(candidate.Name) == "string" then
							renderableName = candidate.Name
						end
					end
					Trace.Record("Error", {
						Phase = "Attach",
						NodeKind = "Renderable",
						DebugName = renderableName,
						Message = tostring(attached[2]),
					})
					local handled, routedMessage =
						Scope.RouteCapturedError(errorRoute, attached[2], value)
					if not handled then
						error(routedMessage, 3)
					end
				end
			end
			visiting[value] = nil
			local countSucceeded, countResult = pcall(function(): number
				return #adapter.GetInstances(value)
			end)
			local currentCount = if countSucceeded and type(countResult) == "number"
				then countResult
				else 0
			nextOrder = adapterStartOrder + currentCount
			return
		end

		local hostInstance = value :: HostInstance
		host.SetParent(hostInstance, parent)
		if startOrder ~= nil and setChildOrder ~= nil then
			setChildOrder(hostInstance, parent, nextOrder)
		end
		nextOrder += 1
	end

	attach(rendered)
	return nextOrder - (startOrder or 1)
end

function Renderer.OrderRendered<HostInstance, HostConnection>(
	rendered: Rendered<HostInstance>,
	parent: HostInstance,
	host: Host<
		HostInstance,
		HostConnection
	>,
	startOrder: number
): number
	local instances = Renderer.GetRenderedInstances(rendered)
	local setChildOrder = host.SetChildOrder
	if setChildOrder ~= nil then
		for offset, instance in instances do
			setChildOrder(instance, parent, startOrder + offset - 1)
		end
	end
	return #instances
end

local function applyChildren<HostInstance, HostConnection>(
	instance: HostInstance,
	children: { Rendered<HostInstance> }?,
	host: Host<HostInstance, HostConnection>,
	parentScope: Scope.Scope
)
	if children == nil then
		return
	end

	local childOrder = 1
	for _, child in children do
		if child == nil then
			continue
		end
		Renderer.OwnRendered(parentScope, child, host)
		childOrder += Renderer.ParentRendered(child, instance, host, childOrder)
	end
end

function Renderer.SetHost<HostInstance, HostConnection>(host: Host<HostInstance, HostConnection>)
	assert(type(host) == "table", "Renderer host must be a table")
	assert(type(host.CreateInstance) == "function", "Renderer host requires CreateInstance")
	assert(type(host.WriteProperty) == "function", "Renderer host requires WriteProperty")
	assert(type(host.SetParent) == "function", "Renderer host requires SetParent")
	assert(type(host.ConnectEvent) == "function", "Renderer host requires ConnectEvent")
	assert(type(host.DestroyInstance) == "function", "Renderer host requires DestroyInstance")
	activeHost = host
end

function Renderer.GetHost(): typeof(activeHost)
	return activeHost
end

function Renderer.Create<Properties>(className: string, properties: Properties?, parentScope: Scope.Scope?): any
	if properties ~= nil and type(properties) ~= "table" then
		error("Renderer properties must be a table", 2)
	end
	local props: { [string]: unknown } = if properties == nil
		then {}
		else (properties :: unknown) :: { [string]: unknown }
	local host = activeHost
	local scope: Scope.Scope = if parentScope ~= nil
		then parentScope:CreateChild({ DebugName = `{className}Scope` })
		else Scope.new({ DebugName = `{className}Scope` })
	local instance = host.CreateInstance(className)

	instanceScopes[instance] = scope
	scope:Own(instance, function(value: unknown)
		instanceScopes[value] = nil
		host.DestroyInstance(value)
	end)

	local result = table.pack(xpcall(function()
		for propertyName, value in props do
			if propertyName == "Children" or propertyName == "Parent" then
				continue
			end

			if PseudoPropertyRegistry.IsRegistered(propertyName) then
				PseudoPropertyRenderer.Apply(instance, propertyName, value, host, scope)
				continue
			end

			local eventName = EventResolver.Resolve(propertyName)
			if eventName ~= nil then
				if type(value) ~= "function" then
					error(`Event handler {propertyName} must be a function`, 2)
				end
				local eventHandler = value :: (...unknown) -> ()
				local eventSource = {
					Kind = "Event",
					DebugName = `{className}.{eventName}`,
				}
				local connection = host.ConnectEvent(instance, eventName, function(...: unknown)
					local eventErrorRoute = Scope.CaptureErrorRoute(scope)
					if #eventErrorRoute == 0 and not Trace.IsEnabled() then
						eventHandler(...)
						return
					end
					local arguments = table.pack(...)
					local emitted = table.pack(xpcall(function()
						eventHandler(table.unpack(arguments, 1, arguments.n))
					end, function(errorMessage)
						return debug.traceback(tostring(errorMessage), 2)
					end))
					if not emitted[1] then
						Trace.Record("Error", {
							Phase = "Event",
							NodeKind = eventSource.Kind,
							DebugName = eventSource.DebugName,
							Message = tostring(emitted[2]),
						})
						local handled, routedMessage =
							Scope.RouteCapturedError(eventErrorRoute, emitted[2], eventSource)
						if not handled then
							Config.ReportError(routedMessage, `[UI Event {className}.{eventName}]`)
						end
					end
				end)
				scope:Own(connection)
			elseif Binding.Is(value) then
				PropertyBinding.new(
					instance,
					className,
					propertyName,
					(value :: unknown) :: Binding.Binding<unknown>,
					host,
					PropertyResolver,
					scope
				)
			else
				local resolved = PropertyResolver.Resolve(className, propertyName, value)
				host.WriteProperty(instance, propertyName, resolved)
			end
		end

		local children = props.Children
		if children ~= nil then
			if type(children) ~= "table" then
				error("Children must be an array of rendered values", 2)
			end
			applyChildren(instance, (children :: unknown) :: { Rendered<unknown> }, host, scope)
		end
		if props.Parent ~= nil then
			host.SetParent(instance, props.Parent)
		end
	end, function(errorMessage)
		return debug.traceback(tostring(errorMessage), 2)
	end))
	local ok = result[1]
	local message: unknown = result[2]

	if not ok then
		local cleanupOk, cleanupMessage = pcall(function()
			scope:Destroy()
		end)
		if not cleanupOk then
			message = `{message}\nCleanup also failed: {cleanupMessage}`
		end
		error(message, 2)
	end

	return instance
end

function Renderer.Mount<HostInstance>(
	rendered: Rendered<HostInstance>,
	parent: HostInstance
): Rendered<HostInstance>
	Renderer.ParentRendered(rendered, parent, activeHost)
	return rendered
end

function Renderer.Unmount<HostInstance>(rendered: Rendered<HostInstance>)
	if Fragment.Is(rendered) then
		local fragment = (rendered :: unknown) :: Fragment.Child<HostInstance>
		for _, child in Fragment.Expand(fragment) do
			Renderer.Unmount(child)
		end
		return
	end
	local adapter = Renderable.GetAdapter(rendered)
	if adapter ~= nil then
		adapter.Destroy(rendered)
		return
	end

	local instanceScope = instanceScopes[rendered]
	if instanceScope ~= nil then
		instanceScope:Destroy()
	else
		activeHost.DestroyInstance(rendered)
	end
end

function Renderer.GetScope(instance: unknown): Scope.Scope?
	local adapter = Renderable.GetAdapter(instance)
	if adapter ~= nil then
		return adapter.GetScope(instance)
	end
	return instanceScopes[instance]
end

return Renderer
