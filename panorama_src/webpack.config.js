const path = require('path')
const { PanoramaTargetPlugin } = require('webpack-panorama')
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin')
const CustomModuleIdsPlugin = require('custom-module-ids-webpack-plugin');

// ========================================================================

function isSubdir(parent, child){
	let relative = path.relative(parent, child)
	return relative && !relative.startsWith('..') && !path.isAbsolute(relative) ? true : false
}

// ========================================================================

module.exports = {
	context: path.resolve('src'),
	entry: {
		// test: './test.tsx',
		core: './core.tsx',
	},

	mode: 'production',
	// mode: 'development',
	output: {
		chunkFormat: 'array-push',
		path: path.resolve('../panorama'),
		// publicPath: "file://{resources}/layout/custom_game/",
	},
	
	optimization: {
		moduleIds: false,
		concatenateModules: false,
		mangleExports: false,
	},

	resolve: {
		extensions: [".ts", ".tsx", "..."],
		symlinks: false,
	},
	
	module: {
		rules: [
			{
				test: /\.tsx?$/,
				exclude: '/node_modules/',
				loader: 'ts-loader',
				options: { transpileOnly: true },
			},
		]
	},
	
	plugins: [
		new PanoramaTargetPlugin(),
		new ForkTsCheckerWebpackPlugin({
			typescript: {
				configFile: path.resolve('tsconfig.json'),
			},
		}),
		new CustomModuleIdsPlugin({
			idFunction: require('./compiler/module_name').moduleName,
		}),
	],
}