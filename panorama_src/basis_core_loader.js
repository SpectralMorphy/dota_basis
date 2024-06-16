const path = require('path')

module.exports = function(source){
	let module = path.relative(path.resolve('node_modules'), this.resourcePath).split(path.sep)[0]
	return `module.exports = GameUI.CustomUIConfig().basis.require("${module}")`
}