--!strict

local FontRegistry = require(script.FontRegistry)

export type FontReference = FontRegistry.FontReference
export type FontSource = FontRegistry.FontSource
export type FontOptions = FontRegistry.FontOptions

type FontMethods = {
	Resolve: (source: FontSource, options: FontOptions?) -> Font,
	Register: (name: string, source: FontSource, options: FontOptions?) -> (),
	Unregister: (name: string) -> boolean,
	IsRegistered: (name: string) -> boolean,
	Ref: (name: string) -> FontReference,
}

type FontMetatable = {
	__call: (self: unknown, source: FontSource, options: FontOptions?) -> Font,
	-- Dynamic registry names cannot be represented as statically known keys.
	__index: (self: unknown, name: string) -> any,
}

export type FontAPI = typeof(setmetatable({} :: FontMethods, {} :: FontMetatable))

local methods: FontMethods = {
	Resolve = FontRegistry.Resolve,
	Register = FontRegistry.Register,
	Unregister = FontRegistry.Unregister,
	IsRegistered = FontRegistry.IsRegistered,
	Ref = FontRegistry.Ref,
}

local metatable: FontMetatable = {
	__call = function(_self: unknown, source: FontSource, options: FontOptions?): Font
		return FontRegistry.Resolve(source, options)
	end,
	__index = function(_self: unknown, name: string): Font?
		if FontRegistry.IsRegistered(name) then
			return FontRegistry.Resolve(name)
		end
		return nil
	end,
}

local FontAPI: FontAPI = setmetatable(methods, metatable)
return FontAPI
