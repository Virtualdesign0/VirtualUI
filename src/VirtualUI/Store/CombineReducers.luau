--!strict

local function CombineReducers(reducers: { [string]: (any, any) -> any })
	return function(state: any, action: any): any
		local previous = state or {}
		local nextState = previous
		local changed = false

		for key, reducer in reducers do
			local previousSlice = previous[key]
			local nextSlice = reducer(previousSlice, action)

			if nextSlice == nil then
				error(`Reducer "{key}" returned nil for action {tostring(action.Type)}`, 2)
			end

			if nextSlice ~= previousSlice then
				if not changed then
					nextState = table.clone(previous)
					changed = true
				end
				nextState[key] = nextSlice
			end
		end

		return nextState
	end
end

return CombineReducers
