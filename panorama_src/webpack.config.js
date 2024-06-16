const path = require('path')
const { PanoramaTargetPlugin } = require('webpack-panorama')
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin')

// ========================================================================

function isSubdir(parent, child){
	let relative = path.relative(parent, child)
	return relative && !relative.startsWith('..') && !path.isAbsolute(relative) ? true : false
}

// ========================================================================

const coreModules = [
	'node_modules/react',
	'node_modules/react-panorama',
]

module.exports = {
	experiments: {
		layers: true,
	},

	context: path.resolve('src'),
	entry: {
		// test: './test.tsx',
		core: { 
			import: './core.tsx',
			layer: 'core',
		},
	},

	mode: 'development',
	// context: path.resolve('src'),
	output: {
		chunkFormat: 'array-push',
		path: path.resolve('../panorama'),
		// publicPath: "file://{resources}/layout/custom_game/",
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
			{
				test: /\.jsx?$/,
				include: file => coreModules.some(module => isSubdir(path.resolve(module), file)),
				issuerLayer: layer => (layer != 'core'),
				loader: path.resolve('basis_core_loader.js')
			}
		]
	},
	
	plugins: [
		new PanoramaTargetPlugin(),
		new ForkTsCheckerWebpackPlugin({
			typescript: {
				configFile: path.resolve('tsconfig.json'),
			},
		}),
	],
}