--!strict

local Config = {}

export type Options = {
	Strict: boolean?,
	FreezeStoreState: boolean?,
	HistoryLimit: number?,
	MaxFlushIterations: number?,
	OnError: ((message: string, context: string?) -> ())?,
}

local values: {
	Strict: boolean,
	FreezeStoreState: boolean,
	HistoryLimit: number,
	MaxFlushIterations: number,
	OnError: ((message: string, context: string?) -> ())?,
} =
	{
		Strict = true,
		FreezeStoreState = false,
		HistoryLimit = 0,
		MaxFlushIterations = 100,
		OnError = nil :: ((message: string, context: string?) -> ())?,
	}

function Config.Configure(options: Options)
	if options.Strict ~= nil then
		values.Strict = options.Strict
	end
	if options.FreezeStoreState ~= nil then
		values.FreezeStoreState = options.FreezeStoreState
	end
	if options.HistoryLimit ~= nil then
		values.HistoryLimit = options.HistoryLimit
	end
	if options.MaxFlushIterations ~= nil then
		values.MaxFlushIterations = options.MaxFlushIterations
	end
	if options.OnError ~= nil then
		values.OnError = options.OnError
	end
end

function Config.GetHistoryLimit(): number
	return values.HistoryLimit
end

function Config.GetFreezeStoreState(): boolean
	return values.FreezeStoreState
end

function Config.GetMaxFlushIterations(): number
	return values.MaxFlushIterations
end

function Config.ReportError(message: unknown, context: string?)
	local rendered = tostring(message)
	local handler = values.OnError

	if handler ~= nil then
		handler(rendered, context)
		return
	end

	if values.Strict then
		error(if context then `{context}: {rendered}` else rendered, 3)
	end

	warn(if context then `{context}: {rendered}` else rendered)
end

return Config
