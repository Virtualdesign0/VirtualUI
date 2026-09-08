--!strict

local HostTypes = require(script.Parent.Host)

local DefaultHost = {}

type DynamicInstance = { [string]: unknown }

function DefaultHost.CreateInstance(className: string): Instance
	if Instance == nil then
		error("The default renderer host requires the Roblox Instance API", 2)
	end
	return Instance.new(className)
end

function DefaultHost.WriteProperty(instance: Instance, propertyName: string, value: unknown)
	local dynamic = (instance :: unknown) :: DynamicInstance
	dynamic[propertyName] = value
end

function DefaultHost.SetParent(instance: Instance, parent: Instance?)
	instance.Parent = parent
end

function DefaultHost.ConnectEvent(
	instance: Instance,
	eventName: string,
	callback: (...unknown) -> ()
): RBXScriptConnection
	local dynamic = (instance :: unknown) :: DynamicInstance
	local signal = dynamic[eventName]
	if typeof(signal) ~= "RBXScriptSignal" then
		error(`{instance.ClassName}.{eventName} is not a connectable event`, 2)
	end
	return (signal :: RBXScriptSignal):Connect(callback)
end

function DefaultHost.DestroyInstance(instance: Instance)
	instance:Destroy()
end

function DefaultHost.SetChildOrder(instance: Instance, _parent: Instance, index: number)
	if instance:IsA("GuiObject") then
		instance.LayoutOrder = index
	end
end

return (DefaultHost :: unknown) :: HostTypes.Host<Instance, RBXScriptConnection>
