--!strict

local LeakDetector = require(script.Parent.Parent.Dev.LeakDetector)

local Scope = {}
Scope.__index = Scope

export type ScopeOptions = {
	DebugName: string?,
	Parent: Scope?,
	_ErrorHandler: ErrorHandler?,
}

export type ErrorHandler = (message: unknown, source: unknown) -> boolean
export type ErrorRoute = { ErrorHandler }

type OwnedResource = {
	resource: unknown,
	cleanup: () -> (),
}

local emptyErrorRoute = table.freeze({})

export type Scope = {
	DebugName: string?,
	Destroyed: boolean,
	_parent: Scope?,
	_errorHandler: ErrorHandler?,
	_children: { [Scope]: boolean },
	_resources: { OwnedResource },
	_beforeDestroy: { () -> () },

	CreateChild: (self: Scope, options: ScopeOptions?) -> Scope,
	Own: (self: Scope, resource: unknown, cleanup: unknown?) -> unknown,
	AddCleanup: (self: Scope, callback: () -> ()) -> (),
	AddBeforeDestroy: (self: Scope, callback: () -> ()) -> (),
	Contains: (self: Scope, descendant: Scope) -> boolean,
	Destroy: (self: Scope) -> (),
	_adopt: (self: Scope, child: Scope) -> (),
}

local function traceback(message: unknown): string
	return debug.traceback(tostring(message), 2)
end

local function inferCleanup(resource: unknown): () -> ()
	if type(resource) == "function" then
		return resource :: () -> ()
	end
	if typeof(resource) == "RBXScriptConnection" then
		local connection = resource :: RBXScriptConnection
		return function()
			connection:Disconnect()
		end
	end
	if typeof(resource) == "Instance" then
		local instance = resource :: Instance
		return function()
			instance:Destroy()
		end
	end

	return function()
		if type(resource) ~= "table" then
			error("Scope cannot infer cleanup for owned resource", 2)
		end
		local candidate = resource :: { [string]: unknown }
		local destroy = candidate.Destroy
		if type(destroy) == "function" then
			(destroy :: (unknown) -> ())(resource)
			return
		end

		local disconnect = candidate.Disconnect
		if type(disconnect) == "function" then
			(disconnect :: (unknown) -> ())(resource)
			return
		end

		error("Scope cannot infer cleanup for owned resource", 2)
	end
end

function Scope.new(options: ScopeOptions?): Scope
	local resolvedOptions: ScopeOptions = options or {}
	local self = (
		setmetatable({
			DebugName = resolvedOptions.DebugName,
			Destroyed = false,
			_parent = nil,
			_errorHandler = resolvedOptions._ErrorHandler,
			_children = {} :: { [Scope]: boolean },
			_resources = {} :: { OwnedResource },
			_beforeDestroy = {} :: { () -> () },
		}, Scope) :: unknown
	) :: Scope

	if resolvedOptions.Parent ~= nil then
		resolvedOptions.Parent:_adopt(self)
	end

	return self
end

function Scope._adopt(self: Scope, child: Scope)
	if self.Destroyed then
		child:Destroy()
		return
	end
	if child == self then
		error("A Scope cannot own itself", 2)
	end

	local ancestor: Scope? = self
	while ancestor ~= nil do
		if ancestor == child then
			error("Scope ownership cycle detected", 2)
		end
		ancestor = ancestor._parent
	end

	if child._parent ~= nil then
		child._parent._children[child] = nil
	end

	child._parent = self
	self._children[child] = true
end

function Scope.CreateChild(self: Scope, options: ScopeOptions?): Scope
	local resolvedOptions: ScopeOptions = {
		DebugName = if options == nil then nil else options.DebugName,
		Parent = self,
		_ErrorHandler = if options == nil then nil else options._ErrorHandler,
	}
	return Scope.new(resolvedOptions)
end

function Scope.CaptureErrorRoute(origin: Scope?): ErrorRoute
	local route: ErrorRoute? = nil
	local current = origin
	while current ~= nil do
		local handler = current._errorHandler
		if handler ~= nil then
			if route == nil then
				local createdRoute: ErrorRoute = { handler }
				route = createdRoute
			else
				table.insert(route, handler)
			end
		end
		current = current._parent
	end
	return if route == nil then emptyErrorRoute :: ErrorRoute else route
end

function Scope.RouteCapturedError(
	route: ErrorRoute,
	message: unknown,
	source: unknown
): (boolean, unknown)
	local routedMessage = message
	for _, handler in route do
		local handled = table.pack(xpcall(function()
			return handler(routedMessage, source)
		end, traceback))
		if handled[1] and handled[2] == true then
			return true, routedMessage
		end
		if not handled[1] then
			routedMessage = handled[2]
		end
	end
	return false, routedMessage
end

function Scope.RouteError(origin: Scope?, message: unknown, source: unknown): (boolean, unknown)
	return Scope.RouteCapturedError(Scope.CaptureErrorRoute(origin), message, source)
end

function Scope.Own(self: Scope, resource: unknown, cleanup: unknown?): unknown
	local cleanupCallback: () -> ()
	if cleanup ~= nil then
		if type(cleanup) ~= "function" then
			error("Scope cleanup must be a function", 2)
		end
		cleanupCallback = function()
			(cleanup :: (unknown) -> ())(resource)
		end
	else
		cleanupCallback = inferCleanup(resource)
	end

	if self.Destroyed then
		cleanupCallback()
		return resource
	end

	table.insert(self._resources, {
		resource = resource,
		cleanup = cleanupCallback,
	})
	return resource
end

function Scope.AddCleanup(self: Scope, callback: () -> ())
	self:Own(callback)
end

function Scope.Contains(self: Scope, descendant: Scope): boolean
	local current: Scope? = (descendant :: unknown) :: Scope
	while current ~= nil do
		if current == self then
			return true
		end
		current = current._parent
	end
	return false
end

function Scope.AddBeforeDestroy(self: Scope, callback: () -> ())
	if self.Destroyed then
		callback()
		return
	end
	table.insert(self._beforeDestroy, callback)
end

function Scope.Destroy(self: Scope)
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	local firstError: unknown = nil
	local function attempt(callback: () -> ()): (boolean, unknown)
		local result = table.pack(xpcall(callback, function(errorMessage)
			return debug.traceback(tostring(errorMessage), 2)
		end))
		local ok = result[1]
		local message = result[2]
		if not ok and firstError == nil then
			firstError = message
		end
		return ok, message
	end

	for index = #self._beforeDestroy, 1, -1 do
		attempt(self._beforeDestroy[index])
	end
	table.clear(self._beforeDestroy)

	local children: { Scope } = {}
	for child in self._children do
		table.insert(children, child)
	end
	for index = #children, 1, -1 do
		attempt(function()
			children[index]:Destroy()
		end)
	end
	table.clear(self._children)

	for index = #self._resources, 1, -1 do
		local owned = self._resources[index]
		local ok, message = attempt(owned.cleanup)
		LeakDetector.InspectResource(self, owned.resource, ok, message)
	end
	table.clear(self._resources)

	if self._parent ~= nil then
		local parent = self._parent
		parent._children[self] = nil
		self._parent = nil
	end

	if firstError ~= nil then
		error(firstError, 2)
	end
end

return Scope
