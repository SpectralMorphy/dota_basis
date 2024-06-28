import type * as webpack from 'webpack'

type LibIdent = null | string

interface ModuleData {
	id: string | false
	own: boolean
}

function isNormal(module: webpack.Module): module is webpack.NormalModule {
	return 'rawRequest' in module
}

function privateId(id: string): string{
	return `_/${id}`
}

const modules: Map<webpack.Module, ModuleData> = new Map()

function removeExtention(path: string): string{
	return path.replace(/(?<=[^/]+)(?:\.\w+)+/, '')
}

function ownId(path: string): string{
	return removeExtention(path.replace(/^\.\//, ''))
}

function getModuleData(module: webpack.Module): ModuleData{
	let data = modules.get(module)
	if(!data){
		if(isNormal(module)){
			if(module.issuer){
				if(module.rawRequest.startsWith('./')){
					const issuerData = getModuleData(module.issuer)
					data = {
						id: issuerData.own ? ownId(module.rawRequest) : false,
						own: issuerData.own,
					}
				}
				else {
					data = {
						id: removeExtention(module.rawRequest),
						own: false,
					}
				}
			}
			else{
				data = {
					id: ownId(module.rawRequest),
					own: true,
				}
			}
		}
		else{
			data = {
				id: false,
				own: module.issuer != undefined,
			}
		}
		modules.set(module, data)
	}
	return data
}

function publicId(id: string, module: webpack.Module): string {
	return getModuleData(module).id || privateId(id)
}

export function moduleName(id: LibIdent, module: webpack.Module): LibIdent | undefined{
	if(!id) return
	const name = publicId(id, module)
	console.log(name)
	return name
}