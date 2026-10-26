--!strict

export type Host<HostInstance, HostConnection> = {
	CreateInstance: (className: string) -> HostInstance,
	SupportsProperty: ((instance: HostInstance, propertyName: string) -> boolean)?,
	WriteProperty: (instance: HostInstance, propertyName: string, value: unknown) -> (),
	SetParent: (instance: HostInstance, parent: HostInstance?) -> (),
	ConnectEvent: (
		instance: HostInstance,
		eventName: string,
		callback: (...unknown) -> ()
	) -> HostConnection,
	DestroyInstance: (instance: HostInstance) -> (),
	SetChildOrder: ((instance: HostInstance, parent: HostInstance, index: number) -> ())?,
}

return {}
