const path = require('path')
const { PanoramaTargetPlugin } = require('webpack-panorama')
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin')

module.exports = {

	mode: 'development',
	context: path.resolve('src'),
	output: {
		path: path.resolve('../panorama'),
		// publicPath: "file://{resources}/layout/custom_game/",
	},

	resolve: {
		extensions: [".ts", ".tsx", "..."],
		// modules: [path.resolve('./src')],
		symlinks: false
	},
	
	module: {
		rules: [
			{ test: /\.tsx?$/, loader: 'ts-loader', options: { transpileOnly: true } },
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