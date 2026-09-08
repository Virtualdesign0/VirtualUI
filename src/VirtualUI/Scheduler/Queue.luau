--!strict

local Queue = {}
Queue.__index = Queue

export type Queue = {
	_items: { {} },
	_present: { [{}]: boolean },
	Push: (self: Queue, item: {}) -> (),
	IsEmpty: (self: Queue) -> boolean,
	Drain: (self: Queue) -> { {} },
}

function Queue.new(): Queue
	local self: Queue = {
		_items = {},
		_present = {},
		Push = Queue.Push,
		IsEmpty = Queue.IsEmpty,
		Drain = Queue.Drain,
	}
	return (setmetatable(self, Queue) :: unknown) :: Queue
end

function Queue.Push(self: Queue, item: {})
	if self._present[item] then
		return
	end

	self._present[item] = true
	table.insert(self._items, item)
end

function Queue.IsEmpty(self: Queue): boolean
	return #self._items == 0
end

function Queue.Drain(self: Queue): { {} }
	local items = self._items
	self._items = {}
	self._present = {}
	return items
end

return Queue
