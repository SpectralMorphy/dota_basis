import './panorama_adapter'
import 'react'
import { render } from 'react-panorama'

// -----------------------------------------------

export interface LibModuleExports {
	[field: string]: any
}

export interface LibModuleEnv {
	lib: Lib
	name: string
	require: (module: string, options: LibRequireOptions) => LibModuleExports
}

export interface LibExecutableModule {
	(env: LibModuleEnv): LibModuleExports | undefined
}

export interface LibPullOptions {

}

export interface LibRequireQueue {
	(execute: () => void, modue: string): () => void
}

export interface LibRequireCallback {
	(exports: LibModuleExports): void
}

export interface LibRequireOptions extends LibPullOptions{
	callback: LibRequireCallback
	queue: LibRequireQueue
}

// ----------------------------------------------------------------------------------------------

class LibQueuedState {
}

interface LibPullingState {
}

// ----------------------------------------------------------------------------------------------

export class Lib {
	
	name: string
	sources: {[module: string]: string} = {}
	preload: {[module: string]: LibExecutableModule} = {}
	loaded:  {[module: string]: LibModuleExports} = {}
	private queued:  {[module: string]: LibQueuedState} = {}
	private pulling:  {[module: string]: LibPullingState} = {}
	
	protected constructor(name: string){
		this.name = name
	}
	
	/**
	!!!
	*/
	require(module: string, options: LibRequireOptions){
		
	}
}

// ----------------------------------------------------------------------------------------------


const libs: {[key: string]: Lib} = {}

class Basis extends Lib {

	name = 'basis'	
	
	// -----------------------------------------------
	
	lib(name: string): Lib {
		let lib = libs[name]
		if(lib){
			return lib
		}
		
		lib = new Lib(name)
		libs[name] = lib
		return lib
	}
}

// ----------------------------------------------------------------------------------------------

// const basis = new Basis()



// -----------------------------------------------


// (GameUI.CustomUIConfig() as any).basis = new Basis()
