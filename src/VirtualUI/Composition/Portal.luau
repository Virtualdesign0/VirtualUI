--!strict

local Renderer = require(script.Parent.Parent.Renderer.Renderer)
local Scope = require(script.Parent.Parent.Lifetime.Scope)
local Profiler = require(script.Parent.Parent.Dev.Profiler)

local Portal = {}
Portal.__index = Portal

export type PortalOptions = {
	Scope: Scope.Scope?,
	DebugName: string?,
}

export type Portal<HostInstance> = {
	Destroyed: boolean,
	DebugName: string?,
	_host: Renderer.Host<HostInstance, unknown>,
	_target: HostInstance,
	_rendered: Renderer.Rendered<HostInstance>,
	_scope: Scope.Scope,
	GetInstance: (self: Portal<HostInstance>) -> HostInstance,
	GetInstances: (self: Portal<HostInstance>) -> { HostInstance },
	GetTarget: (self: Portal<HostInstance>) -> HostInstance,
	SetTarget: (self: Portal<HostInstance>, target: HostInstance) -> (),
	Destroy: (self: Portal<HostInstance>) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

function Portal.new<HostInstance>(
	target: HostInstance,
	render: (scope: Scope.Scope) -> Renderer.Rendered<HostInstance>,
	options: PortalOptions?
): Portal<HostInstance>
	assert(target ~= nil, "Portal.new requires a target")
	assert(type(render) == "function", "Portal.new requires a render function")
	local resolvedOptions: PortalOptions = options or {}
	local host = Renderer.GetHost()
	local portalScope = Scope.new({
		DebugName = resolvedOptions.DebugName or "Portal",
		Parent = resolvedOptions.Scope,
	})
	local rendered = table.pack(xpcall(function()
		local renderedValue = render(portalScope)
		if renderedValue == nil then
			error("Portal render returned nil", 2)
		end
		if #Renderer.GetRenderedInstances(renderedValue) == 0 then
			error("Portal render returned an empty Fragment", 2)
		end
		Renderer.OwnRendered(portalScope, renderedValue, host)
		Renderer.ParentRendered(renderedValue, target, host)
		return renderedValue
	end, traceback))

	if not rendered[1] then
		local cleanupOk, cleanupMessage = pcall(function()
			portalScope:Destroy()
		end)
		local message: unknown = rendered[2]
		if not cleanupOk then
			message = `{message}\nPortal cleanup also failed: {cleanupMessage}`
		end
		error(message, 2)
	end

	local renderedValue = (rendered[2] :: unknown) :: Renderer.Rendered<HostInstance>

	local self = (
		setmetatable({
			Destroyed = false,
			DebugName = resolvedOptions.DebugName,
			_host = host,
			_target = target,
			_rendered = renderedValue,
			_scope = portalScope,
		}, Portal) :: unknown
	) :: Portal<HostInstance>

	if resolvedOptions.Scope ~= nil then
		resolvedOptions.Scope:Own(self)
	end
	Profiler.Increment("PortalMounts")
	return self
end

function Portal.GetInstance<HostInstance>(self: Portal<HostInstance>): HostInstance
	if self.Destroyed then
		error("Attempted to access a destroyed Portal", 2)
	end
	local instance = Renderer.GetFirstRenderedInstance(self._rendered)
	assert(instance ~= nil, "Portal must retain at least one rendered root")
	return instance
end

function Portal.GetInstances<HostInstance>(self: Portal<HostInstance>): { HostInstance }
	if self.Destroyed then
		error("Attempted to access a destroyed Portal", 2)
	end
	return Renderer.GetRenderedInstances(self._rendered)
end

function Portal.GetTarget<HostInstance>(self: Portal<HostInstance>): HostInstance
	if self.Destroyed then
		error("Attempted to access a destroyed Portal", 2)
	end
	return self._target
end

function Portal.SetTarget<HostInstance>(self: Portal<HostInstance>, target: HostInstance)
	if self.Destroyed then
		error("Attempted to retarget a destroyed Portal", 2)
	end
	if target == nil then
		error("Portal target cannot be nil", 2)
	end
	self._target = target
	Renderer.ParentRendered(self._rendered, target, self._host)
	Profiler.Increment("PortalRetargets")
end

function Portal.Destroy<HostInstance>(self: Portal<HostInstance>)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	self._scope:Destroy()
	Profiler.Increment("PortalUnmounts")
end

return Portal
