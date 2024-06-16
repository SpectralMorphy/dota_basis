let proto = Function.prototype
Function = function(...constrArgs){
	let body = constrArgs.pop() ?? ''
	return function(...callArgs){
		callArgs._this = this
		globalThis.__basis_args = callArgs
		$.GetContextPanel().RunScriptInPanelContext(`
			(() => {
				let callArgs = globalThis.__basis_args;
				delete globalThis.__basis_args;
				callArgs._return = (function(${constrArgs.join(',')}){
					${body}
				}).call(callArgs._this, ...callArgs);
			})();
		`)
		return callArgs._return
	}
}
Function.prototype = proto