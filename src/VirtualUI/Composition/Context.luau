--!strict

local Scope = require(script.Parent.Parent.Lifetime.Scope)
local State = require(script.Parent.Parent.Reactive.State)

local ContextImpl = {}
ContextImpl.__index = ContextImpl

local ProviderImpl = {}
ProviderImpl.__index = ProviderImpl

export type ContextOptions = {
	DebugName: string?,
}

export type Provider<T> = {
	Destroyed: boolean,
	_context: Context<T>,
	_scope: Scope.Scope,
	_value: State.State<T>,
	Get: (self: Provider<T>) -> T,
	Set: (self: Provider<T>, value: T) -> boolean,
	Destroy: (self: Provider<T>) -> (),
}

export type Context<T> = {
	DebugName: string?,
	DefaultValue: T,
	_providers: { [Scope.Scope]: Provider<T> },
	_revision: State.State<number>,
	Provide: (self: Context<T>, scope: Scope.Scope, value: T) -> Provider<T>,
	Use: (self: Context<T>, scope: Scope.Scope) -> T,
}

function ContextImpl.new<T>(defaultValue: T, options: ContextOptions?): Context<T>
	local resolvedOptions: ContextOptions = options or {}
	return (
		setmetatable({
			DebugName = resolvedOptions.DebugName,
			DefaultValue = defaultValue,
			_providers = setmetatable({} :: { [Scope.Scope]: Provider<T> }, { __mode = "k" }),
			_revision = State.new(0),
		}, ContextImpl) :: unknown
	) :: Context<T>
end

function ContextImpl.Provide<T>(self: Context<T>, scope: Scope.Scope, value: T): Provider<T>
	if scope.Destroyed then
		error("Cannot provide Context from a destroyed Scope", 2)
	end
	local existing = self._providers[scope]
	if existing ~= nil and not existing.Destroyed then
		error(`Context "{self.DebugName or "Context"}" already has a provider in this Scope`, 2)
	end

	local provider = (
		setmetatable({
			Destroyed = false,
			_context = self,
			_scope = scope,
			_value = State.new(value),
		}, ProviderImpl) :: unknown
	) :: Provider<T>
	self._providers[scope] = provider
	scope:Own(provider)
	self._revision:Update(function(revision: number): number
		return revision + 1
	end)
	return provider
end

function ContextImpl.Use<T>(self: Context<T>, scope: Scope.Scope): T
	self._revision:Get()

	local current: Scope.Scope? = scope
	while current ~= nil do
		local provider = self._providers[current]
		if provider ~= nil and not provider.Destroyed then
			return provider:Get()
		end
		current = current._parent
	end
	return self.DefaultValue
end

function ProviderImpl.Get<T>(self: Provider<T>): T
	if self.Destroyed then
		error("Attempted to access a destroyed Context provider", 2)
	end
	return self._value:Get()
end

function ProviderImpl.Set<T>(self: Provider<T>, value: T): boolean
	if self.Destroyed then
		error("Attempted to update a destroyed Context provider", 2)
	end
	return self._value:Set(value)
end

function ProviderImpl.Destroy<T>(self: Provider<T>)
	if self.Destroyed then
		return
	end
	self.Destroyed = true

	local context = self._context
	if context._providers[self._scope] == self then
		context._providers[self._scope] = nil
	end
	self._value:Destroy()
	context._revision:Update(function(revision: number): number
		return revision + 1
	end)
end

return ContextImpl
