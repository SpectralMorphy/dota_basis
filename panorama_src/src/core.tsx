import './panorama_adapter'
import * as React from 'react'
import * as react_panorama from 'react-panorama'

//-----------------------------------------------

export interface LibModuleExports {
	[field: string]: any
}

export interface LibModuleObject {
	exports: LibModuleExports
}

export interface LibModuleEnv {
	lib: Lib
	name: string
	require: (module: string, options: LibRequireOptions) => LibModuleExports
}

export interface LibExecutableModule {
	(this: LibModuleEnv): LibModuleExports | undefined | void
}

export interface LibPullCallback{
	(source: string): void
}

export interface LibPullOptions {
	callback?: LibPullCallback
}

export interface LibRequireQueue {
	(execute: () => void, module: string): () => void
}

export interface LibRequireCallback {
	(exports: LibModuleExports): void
}

export interface LibRequireOptions extends Omit<LibPullOptions, 'callback'>{
	callback?: LibRequireCallback
	async?: boolean
	queue?: LibRequireQueue
}

//-----------------------------------------------

const onInitList: (() => void)[] = []
function onInit(callback: () => void){
	onInitList.push(callback)
}

//----------------------------------------------------------------------------------------------
// Lib base class
//----------------------------------------------------------------------------------------------

class LibQueuedState {
	
	lib: Lib
	module: string
	awaiting: number = 0
	callbacks: LibRequireCallback[] = []
	invokers: (() => void)[] = []
	#actualExports?: LibModuleExports
	exports: LibModuleExports
	resolution: Promise<void>
	ready: boolean = false
	#resolve!: () => void
	
	constructor(lib: Lib, module: string){
		this.lib = lib
		this.module = module
		
		this.exports = new Proxy(this, {
			get(self: LibQueuedState, name: string) {
				return self.#actualExports?.[name]
			},
			set(self: LibQueuedState, name: string, value: any) {
				if(self.#actualExports){
					self.#actualExports[name] = value
					return true
				}
				return false
			},
		})
		
		this.resolution = new Promise((resolve) => {
			this.#resolve = resolve
		})
	}
	
	addCallback(callback: LibRequireCallback){
		this.callbacks.push(callback)
	}
	
	addQueue(queue: LibRequireQueue){
		let called = false
		this.awaiting++
		
		this.invokers.push(
			queue(
				() => {
					if(called) return
					called = true
					this.awaiting--
					this.try()
				},
				this.module
			)
		)
	}
	
	pull() {
		
		//------------------------
		// executor is already loaded
			
		if(this.lib.preload[this.module]){
			this.onPulled(this.lib.preload[this.module])
			return
		}
	
		//----------------------
		// remote load
			
		this.lib.pull(this.module, {
			callback: (source) => {
				this.onPulled(
					new Function(`
						const module = {
							exports: {},
						};
						${source};
						return module.exports;
					`) as LibExecutableModule
				)
			}
		})
	}
	
	onPulled(executor: LibExecutableModule){
		this.lib.preload[this.module] = executor
		this.invokers.forEach(invoker => invoker())
		this.try()
	}
	
	try(){
	
		// not yet processed
		if(this.ready) return
		
		// executor is loaded
		const executor = this.lib.preload[this.module]
		if(!executor) return
		
		// queue ready
		if(this.awaiting) return
		
		//------------------------
		// execute module
		
		const env: LibModuleEnv = {
			lib: this.lib,
			name: this.module,
			require: (module, options) => this.lib.require(module, options),
		}
		
		const exports = executor.call(env)
		if(exports != undefined && typeof exports != 'object'){
			throw new Error(`Invalid return from module ${this.lib.getDebugModuleName(this.module)} (object or undefined expected, got ${exports})`)
		}
		
		//------------------------
		// execute overriden preload
		
		if(exports == undefined && this.lib.preload[this.module] != executor && this.lib.preload[this.module] != undefined){
			this.try()
			return
		}
		
		//------------------------
		// link exports
		
		if(exports){
			this.#actualExports = exports
		}
		
		this.lib.loaded[this.module] = this.exports
		this.ready = true
		
		//------------------------
		// call callbacks
		
		for(let callback of this.callbacks){
			callback(this.exports)
		}
		
		this.#resolve()
	}
}

//-----------------------------------------------

interface LoadRequestData {
	lib: string
	module: string
}

interface LoadResponseData {
	lib: string
	module: string
	source: string
}

//-----------------------------------------------

class LibPullingState {
	
	lib: Lib
	module: string
	callbacks: LibPullCallback[] = []
	resolution: Promise<void>
	ready: boolean = false
	#resolve!: () => void
	
	constructor(lib: Lib, module: string){
		this.lib = lib
		this.module = module
		
		this.resolution = new Promise((resolve) => {
			this.#resolve = resolve
		})
	}
	
	addCallback(callback: LibPullCallback){
		this.callbacks.push(callback)
	}
	
	start(){
		basis.sendReliable<LoadRequestData>('basis.load', {
			lib: this.lib.name,
			module: this.module,
		})
		
		const listener = basis.subscribeProtected<LoadResponseData>('basis.load', data => {
			if(data.lib == this.lib.name && data.module == this.module){
				GameEvents.Unsubscribe(listener)
				this.finish(data.source)
			}
		})
	}
	
	finish(source: string){
		this.ready = true
		this.lib.sources[this.module] = source
		
		this.callbacks.forEach(callback => callback(source))
		
		this.#resolve()
	}
}

//-----------------------------------------------

export interface LibConstructor {
	new (): Lib
}

export class Lib {
	
	name: string = ''
	sources: {[module: string]: string} = {}
	preload: {[module: string]: LibExecutableModule} = {}
	loaded:  {[module: string]: LibModuleExports} = {}
	private queued:  {[module: string]: LibQueuedState} = {}
	private pulling:  {[module: string]: LibPullingState} = {}
	
	//-----------------------------------------------
	/**
	 */
	isJS(module: string): boolean{
		return this.parseModuleName(module).endsWith('.js')
	}
	
	//-----------------------------------------------
	/**
	 */
	parseModuleName(module: string): string{
		if(!module.match(/\./)){
			module += '.js'
		}
		if(!module.startsWith('./')){
			module = './' + module;
		}
		return module
	}
	
	//-----------------------------------------------
	/**
	 */
	getDebugModuleName(module: string): string {
		return `${this.name}:${this.parseModuleName(module)}`
	}
	
	//-----------------------------------------------
	
	private getRequireState(module: string){
		let state = this.queued[module]
		if(!state){
			state = new LibQueuedState(this, module)
			this.queued[module] = state
			state.pull()
		}
		return state
	}
	
	/**
	!!!
	 */
	async require(module: string, options?: LibRequireOptions): Promise<LibModuleExports> {
		
		module = this.parseModuleName(module)
		options = Object.assign(options ?? {}) as LibRequireOptions
		options.async = options.async ?? false
		
		if(!this.isJS(module)){
			throw new Error(`Cannot require non-js module "${module}"`)
		}
		
		//------------------------
		// already required
		
		if(this.loaded[module]){
			options.callback?.(this.loaded[module])
			return this.loaded[module]
		}
		
		const state = this.getRequireState(module)
		
		//------------------------
		// callback register
	
		if(options.callback){
			state.addCallback(options.callback)
		}
	
		//------------------------
		// queue processing
		
		if(options.queue){
			state.addQueue(options.queue)
		}
		
		//------------------------
		// sync return
		
		if(!options.async){
			await state.resolution
		}		
		return state.exports
	}
	
	//-----------------------------------------------
	
	private getPullState(module: string){
		let state = this.pulling[module]
		if(!state){
			state = new LibPullingState(this, module)
			this.pulling[module] = state
			state.start()
		}
		return state
	}
	
	/**
	*/
	async pull(module: string, options?: LibPullOptions): Promise<string | void> {
		
		module = this.parseModuleName(module)
		options = Object.assign(options ?? {}) as LibPullOptions
		
		//------------------------
		// already pulled
		
		if(this.sources[module]){
			options.callback?.(this.sources[module])
			return this.sources[module]
		}
		
		const state = this.getPullState(module)
		
		//------------------------
		// callback register
		
		if(options.callback){
			state.addCallback(options.callback)
		}
		
		//------------------------
		// sync return
		
		await state.resolution
		return this.sources[module]
	}
}

//----------------------------------------------------------------------------------------------
// Overlay
//----------------------------------------------------------------------------------------------

interface Overlay extends Panel {
	children: {[uniqueID: string]: Panel}
	addPanel(uniqueID: string, panel: Panel): void
}

function getOverlay(): Overlay{
	
	let parent: Panel | null | undefined = $.GetContextPanel()
	while(parent && parent.id != 'CustomUIRoot'){
		parent = parent.GetParent()
	}
	
	if(!parent){
		throw new Error(`CustomUIRoot not found`)
	}
	
	let old = parent.FindChild('BasisOverlay')
	if(old){
		return old as Overlay
	}

	const overlay: Overlay = Object.assign(
		$.CreatePanel('Panel', parent, 'BasisOverlay'),
		{
			children: {},
			addPanel(this: Overlay, uniqueID: Exclude<string, ''>, panel: Panel){
				this.children[uniqueID]?.DeleteAsync(0)
				this.children[uniqueID] = panel
				panel.SetParent(this)
			}
		}
	)
	
	overlay.hittest = false
	overlay.style.width = '100%'
	overlay.style.height = '100%'
	overlay.style.zIndex = 10
	
	return overlay
}

onInit(()=>{
	basis.overlay = getOverlay()
})

//----------------------------------------------------------------------------------------------
// Log
//----------------------------------------------------------------------------------------------

function Shet(){
	
	let [x, setX] = React.useState(0)
	
	function move(){
		setX(x+100)
	}
	
	const style = {x: `${x}px`, transitionProperty: 'position', transitionDuration: '0.3s',
		backgroundColor: '#3379'
	}
	
	return <Button style={style} onactivate={move}><Label text="Hello"/></Button>
}

export class Log{

	panel: Panel
	
	constructor(parent: Panel = $.GetContextPanel()){
		const JSX = this.JSX.bind(this)
		react_panorama.render(<JSX />, parent)
		this.panel = basis.lastChild(parent)!
	}
	
	private JSX(){
		$.Msg(this && this.hide)
		return <Panel style={{width: '200px', height: '200px', backgroundColor: 'red'}}/>
	}
	
	hide(){
	
	}
	
	show(){
		
	}
}

onInit(()=>{
	basis.log = new Log()
	basis.overlay.addPanel('basis.log', basis.log.panel)
})

//----------------------------------------------------------------------------------------------
// Basis class
//----------------------------------------------------------------------------------------------

interface ProtectedEventData {
	key: string,
	data: any
}

interface EventSignature {
	event: string
	data: any
}

//-----------------------------------------------
	
const libs: {[key: string]: Lib} = {}

let serverReady = false
let releableEvents: EventSignature[] = []

class Basis extends Lib {

	Lib = Lib
	Log = Log
	log!: Log
	overlay!: Overlay
	
	constructor(){
		super()
		this.name = 'basis'		
	}
	
	//-----------------------------------------------
	
	lib(name: string, type: LibConstructor = Lib): Lib {
		let lib = libs[name]
		if(lib && type == lib.constructor){
			return lib
		}
		
		lib = new type()
		lib.name = name
		libs[name] = lib
		return lib
	}
	
	
	
	//-----------------------------------------------
	//** !!! */
	
	#protectedKey?: string
	#protKeyBase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'
	
	get protectedKey(): string{
		if(!this.#protectedKey){
			this.#protectedKey = Array.from({length: 32}, () => this.#protKeyBase[Math.floor(this.#protKeyBase.length * Math.random())]).join('')
		}
		return this.#protectedKey
	}
	
	/**
	 * Send reliable event to server
	 */
	sendReliable<T extends string | object>(
		event: (T extends string ? T : string) | keyof CustomGameEventDeclarations,
		data: GameEvents.InferCustomGameEventType<T, never>,
	): void {
		if(serverReady){
			GameEvents.SendCustomGameEventToServer(event, data)
		}
		else {
			releableEvents.push({
				event: event,
				data: data,
			})
		}
	}
	
	/**
	 * Subscribe to protected event
	 */
	subscribeProtected<T extends string | object>(
		event: (T extends string ? T : string) | keyof CustomGameEventDeclarations | keyof GameEventDeclarations,
		handler: (data: NetworkedData<GameEvents.InferGameEventType<T, object>>) => void,
	): GameEventListenerID {
		return GameEvents.Subscribe<ProtectedEventData>(event, (data) => {
			if(data.key == this.protectedKey){
				handler(data.data)
			}
		})
	}
	
	
	//-----------------------------------------------
	// utils
	
	/**
	 */
	lastChild(panel: Panel): Panel | null {
		return panel.GetChild(panel.GetChildCount()-1)
	}
}

//----------------------------------------------------------------------------------------------

const basis = new Basis()
;(GameUI.CustomUIConfig() as any).basis = basis

//-----------------------------------------------
// export react-panorama

basis.loaded['react-panorama'] = react_panorama

//-----------------------------------------------
// Send protected key to server

interface ProtectedKeyResponseData {
	key: string
	force: boolean
}

function sendProtectedKey(force: boolean){
	GameEvents.SendCustomGameEventToServer<ProtectedKeyResponseData>('basis.protected_key', {
		key: basis.protectedKey,
		force: force,
	})
}

GameEvents.Subscribe('basis.protected_key', () => {
	sendProtectedKey(false)
})
sendProtectedKey(true)

//-----------------------------------------------
// Send releable events

basis.subscribeProtected('basis.connect', () => {
	for(const re of releableEvents){
		GameEvents.SendCustomGameEventToServer<typeof re.data>(re.event, re.data)
	}
	releableEvents = []
	serverReady = true
})

//-----------------------------------------------

onInitList.forEach(f => f())