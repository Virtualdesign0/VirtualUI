--!strict

local Profiler = require(script.Parent.Parent.Dev.Profiler)
local Trace = require(script.Parent.Parent.Dev.Trace)
local Renderer = require(script.Parent.Parent.Renderer.Renderer)
local Renderable = require(script.Parent.Parent.Renderer.Renderable)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local ErrorBoundary = {}
ErrorBoundary.__index = ErrorBoundary

export type Failure = {
	Message: string,
	SourceKind: string?,
	SourceName: string?,
	SourceId: number?,
}

export type ErrorBoundaryOptions<HostInstance> = {
	Parent: HostInstance?,
	Scope: Scope.Scope?,
	DebugName: string?,
	OnError: ((failure: Failure) -> ())?,
}

export type ErrorBoundary<HostInstance> = {
	Destroyed: boolean,
	DebugName: string,
	_host: Renderer.Host<HostInstance, unknown>,
	_scope: Scope.Scope,
	_parent: HostInstance?,
	_startOrder: number?,
	_render: (scope: Scope.Scope) -> Renderer.Rendered<HostInstance>,
	_fallback: (failure: Failure, scope: Scope.Scope) -> Renderer.Rendered<HostInstance>,
	_onError: ((failure: Failure) -> ())?,
	_contentScope: Scope.Scope?,
	_fallbackScope: Scope.Scope?,
	_rendered: Renderer.Rendered<HostInstance>?,
	_failure: Failure?,
	_handlingFailure: boolean,
	GetError: (self: ErrorBoundary<HostInstance>) -> Failure?,
	GetInstance: (self: ErrorBoundary<HostInstance>) -> HostInstance?,
	GetInstances: (self: ErrorBoundary<HostInstance>) -> { HostInstance },
	Reset: (self: ErrorBoundary<HostInstance>) -> boolean,
	Destroy: (self: ErrorBoundary<HostInstance>) -> (),
	_replaceWithFallback: (
		self: ErrorBoundary<HostInstance>,
		message: unknown,
		source: unknown
	) -> boolean,
	_mountContent: (self: ErrorBoundary<HostInstance>) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function failureFrom(message: unknown, source: unknown): Failure
	local sourceKind: string? = nil
	local sourceName: string? = nil
	local sourceId: number? = nil
	if type(source) == "table" then
		local candidate = source :: { [string]: unknown }
		sourceKind = if type(candidate.Kind) == "string" then candidate.Kind else nil
		sourceName = if type(candidate.DebugName) == "string" then candidate.DebugName else nil
		sourceId = if type(candidate.Id) == "number" then candidate.Id else nil
	end
	return {
		Message = tostring(message),
		SourceKind = sourceKind,
		SourceName = sourceName,
		SourceId = sourceId,
	}
end

local function cloneFailure(failure: Failure): Failure
	return {
		Message = failure.Message,
		SourceKind = failure.SourceKind,
		SourceName = failure.SourceName,
		SourceId = failure.SourceId,
	}
end

local function destroyScope(scope: Scope.Scope?)
	if scope ~= nil and not scope.Destroyed then
		scope:Destroy()
	end
end

function ErrorBoundary._replaceWithFallback<HostInstance>(
	self: ErrorBoundary<HostInstance>,
	message: unknown,
	source: unknown
): boolean
	if self.Destroyed or self._handlingFailure then
		return false
	end

	self._handlingFailure = true
	local replaced = table.pack(xpcall(function()
		local failure = failureFrom(message, source)
		local contentScope = self._contentScope
		self._contentScope = nil
		self._rendered = nil
		destroyScope(contentScope)

		local fallbackScope = Scope.new({
			DebugName = `{self.DebugName}.Fallback`,
			Parent = self._scope,
		})
		self._fallbackScope = fallbackScope
		local rendered = self._fallback(failure, fallbackScope)
		if rendered == nil or #Renderer.GetRenderedInstances(rendered) == 0 then
			error(`ErrorBoundary "{self.DebugName}" fallback returned no rendered roots`, 2)
		end
		Renderer.OwnRendered(fallbackScope, rendered, self._host)
		self._rendered = rendered
		self._failure = failure
		if self._parent ~= nil then
			Renderer.ParentRendered(rendered, self._parent, self._host, self._startOrder)
		end

		local onError = self._onError
		if onError ~= nil then
			onError(cloneFailure(failure))
		end
		Profiler.Increment("ErrorBoundaryCaptures")
		Trace.Record("BoundaryCapture", {
			DebugName = self.DebugName,
			SourceId = failure.SourceId,
			SourceKind = failure.SourceKind,
			SourceName = failure.SourceName,
			Message = failure.Message,
		})
		return true
	end, traceback))
	self._handlingFailure = false

	if not replaced[1] then
		local fallbackScope = self._fallbackScope
		self._fallbackScope = nil
		self._rendered = nil
		destroyScope(fallbackScope)
		error(replaced[2], 2)
	end
	return replaced[2] == true
end

function ErrorBoundary._mountContent<HostInstance>(self: ErrorBoundary<HostInstance>)
	local contentScope: Scope.Scope
	contentScope = Scope.new({
		DebugName = `{self.DebugName}.Content`,
		Parent = self._scope,
		_ErrorHandler = function(message: unknown, source: unknown): boolean
			return self:_replaceWithFallback(message, source)
		end,
	})
	self._contentScope = contentScope
	local rendered = self._render(contentScope)
	if self._failure ~= nil or contentScope.Destroyed then
		-- A nested boundary can fail synchronously and route into this boundary
		-- before the parent render callback returns. The fallback is already active.
		return
	end
	if rendered == nil or #Renderer.GetRenderedInstances(rendered) == 0 then
		error(`ErrorBoundary "{self.DebugName}" content returned no rendered roots`, 2)
	end
	Renderer.OwnRendered(contentScope, rendered, self._host)
	self._rendered = rendered
	if self._parent ~= nil then
		Renderer.ParentRendered(rendered, self._parent, self._host, self._startOrder)
	end
end

local boundaryAdapter: Renderable.Adapter = {
	GetRendered = function(value: unknown): unknown
		return (value :: ErrorBoundary<unknown>)._rendered
	end,
	GetInstances = function(value: unknown): { unknown }
		local boundary = value :: ErrorBoundary<unknown>
		return if boundary._rendered == nil
			then {}
			else Renderer.GetRenderedInstances(boundary._rendered)
	end,
	GetScope = function(value: unknown): Scope.Scope
		return (value :: ErrorBoundary<unknown>)._scope
	end,
	GetErrorScope = function(value: unknown): Scope.Scope
		local boundary = value :: ErrorBoundary<unknown>
		return boundary._contentScope or boundary._fallbackScope or boundary._scope
	end,
	WillAttach = function(value: unknown, parent: unknown?, startOrder: number?)
		local boundary = value :: ErrorBoundary<unknown>
		boundary._parent = parent
		boundary._startOrder = startOrder
	end,
	DidAttach = function(_value: unknown, _parent: unknown?, _startOrder: number?) end,
	Destroy = function(value: unknown)
		ErrorBoundary.Destroy(value :: ErrorBoundary<unknown>)
	end,
}

function ErrorBoundary.new<HostInstance>(
	render: (
		scope: Scope.Scope
	) -> Renderer.Rendered<HostInstance>,
	fallback: (
		failure: Failure,
		scope: Scope.Scope
	) -> Renderer.Rendered<HostInstance>,
	options: ErrorBoundaryOptions<HostInstance>?
): ErrorBoundary<HostInstance>
	assert(type(render) == "function", "ErrorBoundary.new requires a render function")
	assert(type(fallback) == "function", "ErrorBoundary.new requires a fallback function")
	local resolvedOptions: ErrorBoundaryOptions<HostInstance> = options or {}
	local debugName = resolvedOptions.DebugName or "ErrorBoundary"
	local boundaryScope = Scope.new({
		DebugName = `{debugName}Scope`,
		Parent = resolvedOptions.Scope,
	})
	local self = (
		setmetatable({
			Destroyed = false,
			DebugName = debugName,
			_host = Renderer.GetHost(),
			_scope = boundaryScope,
			_parent = resolvedOptions.Parent,
			_startOrder = nil,
			_render = render,
			_fallback = fallback,
			_onError = resolvedOptions.OnError,
			_contentScope = nil,
			_fallbackScope = nil,
			_rendered = nil,
			_failure = nil,
			_handlingFailure = false,
		}, ErrorBoundary) :: unknown
	) :: ErrorBoundary<HostInstance>
	Renderable.Register(self, boundaryAdapter)
	boundaryScope:AddBeforeDestroy(function()
		self.Destroyed = true
		self._rendered = nil
	end)

	local mounted = table.pack(xpcall(function()
		self:_mountContent()
	end, traceback))
	if not mounted[1] then
		local handled, routedMessage = Scope.RouteError(self._contentScope, mounted[2], self)
		if not handled then
			local cleanup = table.pack(xpcall(function()
				boundaryScope:Destroy()
			end, traceback))
			if not cleanup[1] then
				routedMessage = `{routedMessage}\nBoundary cleanup also failed: {cleanup[2]}`
			end
			error(routedMessage, 3)
		end
	end

	return self
end

function ErrorBoundary.GetError<HostInstance>(self: ErrorBoundary<HostInstance>): Failure?
	if self.Destroyed then
		error("Attempted to inspect a destroyed ErrorBoundary", 2)
	end
	local failure = self._failure
	return if failure == nil then nil else cloneFailure(failure)
end

function ErrorBoundary.GetInstance<HostInstance>(self: ErrorBoundary<HostInstance>): HostInstance?
	if self.Destroyed then
		error("Attempted to inspect a destroyed ErrorBoundary", 2)
	end
	return Renderer.GetFirstRenderedInstance(self._rendered)
end

function ErrorBoundary.GetInstances<HostInstance>(self: ErrorBoundary<HostInstance>): { HostInstance }
	if self.Destroyed then
		error("Attempted to inspect a destroyed ErrorBoundary", 2)
	end
	return Renderer.GetRenderedInstances(self._rendered)
end

function ErrorBoundary.Reset<HostInstance>(self: ErrorBoundary<HostInstance>): boolean
	if self.Destroyed then
		error("Attempted to reset a destroyed ErrorBoundary", 2)
	end
	if self._failure == nil then
		return false
	end

	local fallbackScope = self._fallbackScope
	self._fallbackScope = nil
	self._failure = nil
	self._rendered = nil
	destroyScope(fallbackScope)

	local mounted = table.pack(xpcall(function()
		self:_mountContent()
	end, traceback))
	if not mounted[1] then
		local handled, routedMessage = Scope.RouteError(self._contentScope, mounted[2], self)
		if not handled then
			error(routedMessage, 2)
		end
	end
	Profiler.Increment("ErrorBoundaryResets")
	return true
end

function ErrorBoundary.Destroy<HostInstance>(self: ErrorBoundary<HostInstance>)
	if self.Destroyed then
		return
	end
	self._scope:Destroy()
end

return ErrorBoundary
