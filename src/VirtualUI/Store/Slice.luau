--!strict

local Slice = {}

function Slice.Create(options: any)
	assert(type(options.Name) == "string", "Slice requires a Name")
	assert(type(options.Reducers) == "table", "Slice requires Reducers")

	local actions = {}
	local handlers = {}

	for name, reducer in options.Reducers do
		local actionType = `{options.Name}/{name}`
		handlers[actionType] = reducer
		actions[name] = function(payload: any)
			return {
				Type = actionType,
				Payload = payload,
			}
		end
	end

	local function reducer(state: any, action: any): any
		local current = if state == nil then options.InitialState else state
		local handler = handlers[action.Type]
		if handler == nil then
			return current
		end
		return handler(current, action)
	end

	return {
		Name = options.Name,
		Actions = actions,
		Reducer = reducer,
	}
end

return Slice
