--!strict

local Binding = require(script.Parent.Binding)
local PropertyResolver = require(script.Parent.Parent.Resolve.PropertyResolver)
local PseudoPropertyBinding = require(script.Parent.PseudoPropertyBinding)
local Registry = require(script.Parent.Parent.Resolve.PseudoPropertyRegistry)
local HostTypes = require(script.Parent.Host)
local Scope = require(script.Parent.Parent.Lifetime.Scope)

local PseudoPropertyRenderer = {}

local function writeStatic<HostInstance, HostConnection>(
	instance: HostInstance,
	descriptor: Registry.Descriptor,
	value: unknown,
	host: HostTypes.Host<
		HostInstance,
		HostConnection
	>
)
	local properties = Registry.Resolve(descriptor, value)
	for _, propertyName in descriptor.Properties do
		local propertyValue = properties[propertyName]
		local resolved = PropertyResolver.Resolve(descriptor.ClassName, propertyName, propertyValue)
		host.WriteProperty(instance, propertyName, resolved)
	end
end

function PseudoPropertyRenderer.Apply<HostInstance, HostConnection>(
	owner: HostInstance,
	name: string,
	value: unknown,
	host: HostTypes.Host<
		HostInstance,
		HostConnection
	>,
	scope: Scope.Scope
): HostInstance
	local descriptor = Registry.Get(name)
	if descriptor == nil then
		error(`Unknown pseudo-property {name}`, 2)
	end

	local instance = host.CreateInstance(descriptor.ClassName)
	scope:Own(instance, function(owned: HostInstance)
		host.DestroyInstance(owned)
	end)
	host.WriteProperty(instance, "Name", `__VirtualUI_{name}`)
	host.SetParent(instance, owner)

	if Binding.Is(value) then
		PseudoPropertyBinding.new(
			instance,
			name,
			(value :: unknown) :: Binding.Binding<unknown>,
			descriptor,
			host,
			PropertyResolver,
			scope
		)
	else
		writeStatic(instance, descriptor, value, host)
	end
	return instance
end

return PseudoPropertyRenderer
