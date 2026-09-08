--!strict

local StoreClass = require(script.Store)
local CombineReducers = require(script.CombineReducers)
local Slice = require(script.Slice)

export type Action = StoreClass.Action
export type Store<State, ActionType> = StoreClass.Store<State, ActionType>
export type StoreOptions<State, ActionType> = StoreClass.StoreOptions<State, ActionType>
export type StoreSnapshot<State> = StoreClass.StoreSnapshot<State>
export type HistoryEntry<State, ActionType> = StoreClass.HistoryEntry<State, ActionType>
export type HistoryTransition = StoreClass.HistoryTransition
export type HistoryDiagnostics = StoreClass.HistoryDiagnostics
export type Middleware<State, ActionType> = StoreClass.Middleware<State, ActionType>
export type Selector<T> = StoreClass.Selector<T>
export type SelectorOptions<T> = StoreClass.SelectorOptions<T>

return {
	new = StoreClass.new,
	CombineReducers = CombineReducers,
	CreateSlice = Slice.Create,
}
