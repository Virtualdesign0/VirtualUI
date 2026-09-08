--!strict

local Observer = {}

export type Node = {
	Id: number,
	Kind: string,
	DebugName: string?,
	Version: number,
	Dirty: boolean,
	Destroyed: boolean,
	Dependencies: { [Node]: boolean },
	Dependents: { [Node]: boolean },
	_invalidate: unknown,
}

local stack: { Node } = {}

function Observer.Push(observer: Node)
	table.insert(stack, observer)
end

function Observer.Pop(expected: Node)
	local current = table.remove(stack)
	if current ~= expected then
		error("Reactive observer stack corruption", 2)
	end
end

function Observer.GetCurrent(): Node?
	return stack[#stack]
end

function Observer.FormatCycle(target: Node): string
	local chain = table.create(#stack + 1) :: { string }

	for _, node in stack do
		table.insert(chain, node.DebugName or `{node.Kind}[{node.Id}]`)
	end

	table.insert(chain, target.DebugName or `{target.Kind}[{target.Id}]`)
	return "Reactive dependency cycle detected:\n" .. table.concat(chain, " -> ")
end

return Observer
