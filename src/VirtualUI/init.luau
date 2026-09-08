--!strict

local Binding = require(script.Renderer.Binding)
local Benchmark = require(script.Dev.Benchmark)
local Computed = require(script.Reactive.Computed)
local Conditional = require(script.Structural.Conditional)
local Component = require(script.Composition.Component)
local Context = require(script.Composition.Context)
local Config = require(script.Runtime.Config)
local Effect = require(script.Reactive.Effect)
local ErrorBoundary = require(script.Composition.ErrorBoundary)
local Equality = require(script.Reactive.Equality)
local FontSystem = require(script.Font)
local GraphInspector = require(script.Dev.GraphInspector)
local LeakDetector = require(script.Dev.LeakDetector)
local Fragment = require(script.Structural.Fragment)
local Profiler = require(script.Dev.Profiler)
local PseudoProperty = require(script.Resolve.PseudoPropertyRegistry)
local Renderer = require(script.Renderer.Renderer)
local Scheduler = require(script.Scheduler.Scheduler)
local Scope = require(script.Lifetime.Scope)
local State = require(script.Reactive.State)
local Store = require(script.Store)
local Trace = require(script.Dev.Trace)
local KeyedCollection = require(script.Structural.KeyedCollection)
local Motion = require(script.Motion)
local Portal = require(script.Composition.Portal)

export type State<T> = State.State<T>
export type Computed<T> = Computed.Computed<T>
export type Binding<T> = Binding.Binding<T>
export type Scope = Scope.Scope
export type Host<HostInstance, HostConnection> = Renderer.Host<HostInstance, HostConnection>
export type Rendered<HostInstance> = Renderer.Rendered<HostInstance>
export type Store<StateType, ActionType> = Store.Store<StateType, ActionType>
export type StoreOptions<StateType, ActionType> = Store.StoreOptions<StateType, ActionType>
export type Selector<T> = Store.Selector<T>
export type HistoryTransition = Store.HistoryTransition
export type HistoryDiagnostics = Store.HistoryDiagnostics
export type Conditional<T, HostInstance> = Conditional.Conditional<T, HostInstance>
export type KeyedCollection<Item, Key, HostInstance> = KeyedCollection.KeyedCollection<
	Item,
	Key,
	HostInstance
>
export type KeyedCollectionOptions<HostInstance> = KeyedCollection.KeyedCollectionOptions<
	HostInstance
>
export type Context<T> = Context.Context<T>
export type ContextProvider<T> = Context.Provider<T>
export type Portal<HostInstance> = Portal.Portal<HostInstance>
export type MotionNode<T> = Motion.MotionNode<T>
export type Spring<T> = Motion.Spring<T>
export type Tween<T> = Motion.Tween<T>
export type PseudoPropertyDescriptor = PseudoProperty.Descriptor
export type FontSource = FontSystem.FontSource
export type FontOptions = FontSystem.FontOptions
export type FontReference = FontSystem.FontReference
export type Fragment<HostInstance> = Fragment.Fragment<HostInstance>
export type ComponentOptions<HostInstance> = Component.ComponentOptions<HostInstance>
export type ComponentInstance<Props, HostInstance> = Component.ComponentInstance<
	Props,
	HostInstance
>
export type ComponentClass<Props> = Component.ComponentClass<Props>
export type ErrorBoundaryFailure = ErrorBoundary.Failure
export type ErrorBoundary<HostInstance> = ErrorBoundary.ErrorBoundary<HostInstance>
export type ErrorBoundaryOptions<HostInstance> = ErrorBoundary.ErrorBoundaryOptions<HostInstance>
export type BenchmarkOptions = Benchmark.Options
export type BenchmarkResult = Benchmark.Result
export type TraceEvent = Trace.Event

local UI = {
	State = State,
	Computed = Computed,
	Effect = Effect,
	ErrorBoundary = ErrorBoundary,
	Binding = Binding,
	Conditional = Conditional,
	Component = Component,
	KeyedCollection = KeyedCollection,
	Context = Context,
	Portal = Portal,
	Motion = Motion,
	Spring = Motion.Spring,
	Tween = Motion.Tween,
	PseudoProperty = PseudoProperty,
	Scope = Scope,
	Store = Store,
	Equality = Equality,
	Font = FontSystem,
	Fragment = Fragment.new,

	Create = Renderer.Create,
	Mount = Renderer.Mount,
	Unmount = Renderer.Unmount,
	GetScope = Renderer.GetScope,

	Batch = Scheduler.Batch,
	Flush = Scheduler.Flush,

	Debug = {
		Benchmark = Benchmark,
		InspectGraph = GraphInspector.Inspect,
		GetMetrics = Profiler.GetMetrics,
		ResetMetrics = Profiler.Reset,
		GetLeaks = LeakDetector.GetLeaks,
		ResetLeaks = LeakDetector.Reset,
		AssertNoLeaks = LeakDetector.AssertNoLeaks,
		GetTraceEvents = Trace.GetEvents,
		GetDroppedTraceEventCount = Trace.GetDroppedCount,
		ResetTrace = Trace.Reset,
		FormatTrace = Trace.Format,
	},
}

function UI.Configure(options: any)
	if options.Host ~= nil then
		Renderer.SetHost(options.Host)
	end
	if options.Profiling ~= nil then
		Profiler.SetEnabled(options.Profiling)
	end
	if options.LeakDetection ~= nil then
		LeakDetector.SetEnabled(options.LeakDetection)
	end
	if options.Tracing ~= nil then
		Trace.SetEnabled(options.Tracing)
	end
	if options.TraceCapacity ~= nil then
		Trace.SetCapacity(options.TraceCapacity)
	end
	Config.Configure(options)
end

return UI
