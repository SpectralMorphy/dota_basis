local _ = {}

---@class basis.lib
local lib = {}

---@class basis: basis.lib
local basis

---@alias basis.lib.load.callback fun(source: string, response: basis.lib.request.response)
---@alias basis.lib.require.callback fun(exports: table)
---@alias basis.lib.require.queue fun(execute: fun(), module: string): fun()

---@class basis.lib.load.options
---@field async? boolean						# Async load (for http loading)
---@field fromServer? boolean					# Client only. Send http request from server
---@field callback? basis.lib.load.callback		# Perform callback on finish

---@class basis.lib.require.options: basis.lib.load.options
---@field callback? basis.lib.require.callback 		# Perform callback on finish
---@field queue? basis.lib.require.queue			# Control order of modules execution. Call 'execute' function to execute the module. Should return invoker function, which will be called by the lib, when module is loaded and ready to be executed.

---@class basis.lib.request.data: table<any, any>
---@field method string
---@field url string

---@class basis.lib.request.response
---@field code integer
---@field body string

---@class basis.lib._queuedState
---@field awaiting	integer
---@field callbacks basis.lib.require.callback[]
---@field invokers  fun()[]
---@field exports	table
---@field load		fun()
---@field onLoaded	fun(fmodule: fun(): table?)
---@field try		fun()
---@field fmodule?	fun(): table?

---@class basis.lib._loadingState
---@field callbacks basis.lib.load.callback[]
---@field ready boolean
---@field source? string
---@field response? basis.lib.request.response

---@class basis.lib.load._eventRequest
---@field name string
---@field root string
---@field module string

---@class basis.lib.load._eventResponse
---@field name string
---@field module string
---@field source string
---@field response basis.lib.request.response

-----------------------------------------------

local REMOTE = '' --!!!
local INIT_STATE = 2 -- DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP (not defined on client)

-----------------------------------------------

---@param name string
---@param root string
local function newLib(name, root)
	
	---@type basis.lib
	local _lib = {}
	
	for k, v in pairs(lib) do
		_lib[k] = v
	end
	
	_lib:constructor(name, root)
	
	return _lib
end

-----------------------------------------------

---@param path string
---@return string, ...
local function replaceDots(path)
	return path:gsub('%.', '/')
end

-----------------------------------------------

---@param storage table<any, basis.listener>
---@param event any
---@param callback? fun(...)
---@param cleanup? boolean
local function genericListener(storage, event, callback, cleanup)
		
	---@class basis.listener
	local listener = {
		callback = callback		---@type fun(...)?
	}
	
	local null = false
	
	------------------------
	
	local eventListeners = storage[event]
	if not eventListeners then
		eventListeners = {}
		storage[event] = eventListeners
	end
	
	table.insert(eventListeners, 1, listener)
	
	------------------------
	
	function listener:IsNull()
		return null
	end
	
	------------------------
	
	function listener:Destroy()
		if null then
			return
		end
		null = true
		
		for i, listener2 in ipairs(eventListeners) do
			if listener2 == listener then
				table.remove(eventListeners, i)
				break
			end
		end
		
		if cleanup ~= false then
			if #eventListeners == 0 then
				storage[event] = nil
			end
		end
	end
	
	------------------------
	
	return listener
end

------------------------

---@param storage table<any, basis.listener>
---@param event any
local function triggerListeners(storage, event, ...)

	local eventListeners = storage[event]
	if not eventListeners then
		return
	end
	
	for i = #eventListeners, 1, -1 do
		local listener = eventListeners[i]
		if listener.callback then
			listener.callback(...)
		end
	end
end

-----------------------------------------------

local listeners = {}

---@param event string
---@param callback fun(data: table)
local function addListener(event, callback)

	if not listeners[event] then
		ListenToGameEvent(event, function(data)
			triggerListeners(listeners, event, data)
		end, nil)
	end
	
	---@class basis._stateListener: basis.listener
	local listener = genericListener(listeners, event, nil, false)
	listener.callback = callback
	
	return listener
end

-----------------------------------------------

---@return boolean
local function isValidState()
	return GameRules and GameRules.State_Get and GameRules:State_Get() >= INIT_STATE
end

---@param callback fun()
local function onValidState(callback)
	if isValidState() then
		callback()
	else
		local listener listener = addListener(
			'game_rules_state_change',
			function()
				if isValidState() then
					listener:Destroy()
					callback()
				end
			end
		)
	end
end

----------------------------------------------------------------------------------------------
--- lib
----------------------------------------------------------------------------------------------

---@param name string
---@param root string
function lib:constructor(name, root)
	self.name = name		--- `read-only` <br> Unique name of the lib
	self.root = root		--- `read-only` <br> Root path of lib modules
	self.remote	= false	---@type boolean	# `read-only` <br> Is this a remote lib (modules are loaded through http) ?
	self.source = {}	---@type table<string, string>	# Source code of loaded modules
	self.required = {}	---@type table<string, table>	# Executed lua modules
	self._queued = {}	---@type table<string, basis.lib._queuedState>
	self._loading = {}	---@type table<string, basis.lib._loadingState>
	
	self:setRoot(root)
end

-----------------------------------------------

--- Change root of the lib and its remote state
---@param root string
function lib:setRoot(root)
	self.root = root
	self.remote = (self.root:match('^http') ~= nil)
	if not self.remote then
		self.root = replaceDots(self.root)
	end
	self.root = self.root:gsub('/$', ''):gsub('\\$', '')
end

-----------------------------------------------

--- Load and execute lua module
--- Every module should return table of exports or nil. No other types supported (because they are incompatible with async loading)
---@param module string
---@param options basis.lib.require.options?
---@return table
function lib:require(module, options)

	if options == nil then
		options = {}
	end
	local async = options.async
	local queue = options.queue
	local callback = options.callback
	local formServer = options.fromServer
	
	module = replaceDots(module)

	------------------------
	-- already required
	
	if self.required[module] then
		if callback then
			callback(self.required[module])
		end
		if not async then
			return self.required[module]
		end
	end
	
	------------------------
	-- queued state
	
	local state = self._queued[module]
	
	if not state then
		state = {
			awaiting = 0,
			callbacks = {},
			invokers = {},
			exports = {},
			
			------------------------
			-- load code
			
			load = function()
		
				------------------------
				-- remote load
				
				if self.remote then
				
					self:load(module, {
						async = async,
						fromServer = formServer,
						callback = function(source)
							state.onLoaded(assert(loadstring(source, self.name .. ':' .. module)))
						end
					})
				
				------------------------
				-- local load
			
				else
					
					state.onLoaded(assert(loadfile(self:getPath(module))))
					
				end
			end,
			
			------------------------
			-- when source code is loaded
			
			onLoaded = function(fmodule)
				state.fmodule = fmodule
				
				for _, invoker in ipairs(state.invokers) do
					invoker()
				end
				
				state.try()
			end,
			
			------------------------
			-- try to execute, if ready
			
			try = function()
			
				-- cancel: already executed, or lib was refreshed
				if self._queued[module] ~= state then
					return
				end
				
				-- code is loaded
				if state.fmodule == nil then
					return
				end
				
				-- all executors were called
				if state.awaiting > 0 then
					return
				end
				
				self._queued[module] = nil
				
				------------------------
				-- execute in async thread
				
				basis:thread(function()
				
					------------------------
					-- execute module and copy exports
				
					local exports = state.fmodule()
					if exports then
						for k, v in pairs(exports) do
							state.exports[k] = v
						end
					end
					
					------------------------
					-- store required
					
					self.required[module] = state.exports
					
					------------------------
					-- call callbacks
					
					for _, callback in ipairs(state.callbacks) do
						callback(state.exports)
					end
					
				end)
			end
		}
		
		self._queued[module] = state
	
		------------------------
		-- start loading
		
		state.load()
		
	end
	
	------------------------
	-- callback register
	
	if callback then
		table.insert(state.callbacks, callback)
	end
	
	------------------------
	-- queue processing
	
	if queue then
		
		local executed = false
		state.awaiting = state.awaiting + 1
		
		local invoker = queue(
			function()
				if executed then
					return
				end
				
				executed = true
				state.awaiting = state.awaiting - 1
				
				state.try()
			end,
			module
		)
		
		table.insert(state.invokers, invoker)
		
		--- sync queue
		if not async then
			if coroutine.running() == nil then
				error('Sync queued require in main thread is impossible', 0)
			end
			while self.required[module] == nil do
				coroutine.yield()
			end
		end
	end
	
	------------------------
	
	return state.exports
end

-----------------------------------------------

--- Load source code from remote
---@param module string
---@param options basis.lib.load.options?
---@return string?, basis.lib.request.response?
function lib:load(module, options)
	if not self.remote then
		error('Lib is not remote', 0)
	end
	
	------------------------
	-- parse options
	
	if options == nil then
		options = {}
	end
	local async = options.async
	local callback = options.callback
	local formServer = options.fromServer
	
	if not async and coroutine.running() == nil then
		error('Sync loading in main thread is impossible', 0)
	end
	
	------------------------
	-- await game state
	
	if not isValidState() then
	
		-- async delay
		if async then
		
			-- mute options
			local options2 = {}		
			for k, v in pairs(options) do
				options2[k] = v
			end
			
			-- recall on state change
			local cb = function()
				self:load(module, options2)
			end
			onValidState(cb)
			return
			
		-- sync delay
		else
			while not isValidState() do
				coroutine.yield()
			end
		end
	end
	
	------------------------
	-- already loaded
	
	---@type basis.lib._loadingState
	local state = self._loading[module]
	
	if self.source[module] then
		if callback then
			callback(self.source[module], state.response)
		end
		if not async then
			return self.source[module], state.response
		end
	end
	
	------------------------
	-- first loading
		
	if not state then
		state = {
			callbacks = {},
			ready = false,
			source = nil,
			response = nil,
			
			------------------------
			-- then code is loaded
			
			---@param source string
			---@param response basis.lib.request.response
			onLoaded = function(source, response)
				state.ready = true
				state.source = source
				state.response = response
				
				self.source[module] = state.source
				
				for _, callback in ipairs(state.callbacks) do
					callback(state.source, state.response)
				end
			end,
		}
		
		self._loading[module] = state
		
		------------------------
		-- request from server
		
		if formServer and IsClient() then
		
			local listener listener = basis:clientListener(
				'basis.load',
				
				---@param data basis.lib.load._eventResponse
				function(data)
					if data.name == self.name and data.module == module then
						listener:Destroy()
						state.onLoaded(data.source, data.response)
					end
				end
			)
		
			---@type basis.lib.load._eventRequest
			local data = {
				name = self.name,
				root = self.root,
				module = module,
			}
			basis:consoleEvent('basis.load', data)
		
		------------------------
		-- make request
		
		else
			local req, data = self:request(module)
			
			-- response parser
			req:Send(
				function(res)
					if res.StatusCode >= 200 and res.StatusCode < 300 then
						state.onLoaded(res.Body, {
							body = res.Body,
							code = res.StatusCode
						})
					else
						state.ready = true
						self._loading[module] = nil
						
						error('Got status code ' .. res.StatusCode .. ' from ' .. data.url, 0)
					end
				end
			)
		end
	end
	
	------------------------
	-- register callback
	
	if callback then
		table.insert(state.callbacks, callback)
	end
	
	------------------------
	-- sync return
	
	if not async then
		while not state.ready do
			coroutine.yield()
		end
		return state.source, state.response
	end
end

-----------------------------------------------

--- Clear all loaded modules
function lib:refresh()
	self.source = {}
	self._loading = {}
	self.required = {}
	self._queued = {}
end

-----------------------------------------------

--- Get root path of the lib
---@return string
function lib:getRootPath()
	return self.root
end

-----------------------------------------------

--- Is this module a lua script? <br>
--- Lua module names may have no extension and may use dots as path separator <br>
--- Non-lua module names must have extension and must contain at least one slash. May start with `./`
function lib:isLua(module)
	if module:match('%.lua$') then
		return true
	end
	if not module:match('[/\\]') then
		return true
	end
	if not module:match('%.') then
		return true
	end
	return false
end

-----------------------------------------------

--- Get relative path to the module
---@param module string
---@return string
function lib:getRelativePath(module)
	local slashes = module:match('[/\\]')
	local path = module
	
	if not slashes then
		path = replaceDots(module)
	end
	
	if self.remote then
		if not path:match('%.') then
			path = path .. '.lua'
		end
	else
		if slashes then
			path = path:gsub('%.lua$', '')
		end
	end
	
	return path
end

-----------------------------------------------

--- Get full path to source code of the module
---@param module string
---@return string
function lib:getPath(module)
	return self:getRootPath() .. '/' .. self:getRelativePath(module)
end

-----------------------------------------------

--- Prepare request to load remote module
---@param module string
---@return CScriptHTTPRequest, basis.lib.request.data
function lib:request(module)

	---@type basis.lib.request.data
	local data = {
		method = self:getRequestMethod(module),
		url = self:getPath(module),
	}
	
	local req  = CreateHTTPRequestScriptVM(data.method, data.url)
	
	self:ajustRequest(req, module, data)
	
	return req, data
end

-----------------------------------------------

--- Override load request method
---@param module string
---@return string
function lib:getRequestMethod(module)
	return 'GET'
end

-----------------------------------------------

--- Override this function to perform additional setup on module load request
---@param request CScriptHTTPRequest
---@param module string
---@param data basis.lib.request.data
function lib:ajustRequest(request, module, data)
	
end

----------------------------------------------------------------------------------------------
--- basis core
----------------------------------------------------------------------------------------------

---@class basis
basis = newLib('basis', REMOTE)

basis.baseLib = lib		--- Base lib descriptor

local libs = {}			---@type table<string, basis.lib>
libs[REMOTE] = basis

-----------------------------------------------

--- Get relative path to the module
---@param module string
---@return string
function basis:getRelativePath(module)
	local path = lib.getRelativePath(self, module)
	if self:isLua(module) then
		path = 'vscripts/' .. path
	end
	return path
end

-----------------------------------------------

--- Get or create a lib by its name
---@param name string	# lib name
---@param root? string	# Root of lib modules - folder or url
---@return basis.lib
function basis:lib(name, root)

	local lib = libs[root]
	
	-- update root
	if lib then
		if root then
			libs[root]:setRoot(root)
		end
	
	-- create new lib for new name
	else
		if not root then
			error('Cannot create new lib without root', 2)
		end
	
		lib = newLib(name, root)
		libs[root] = lib
	end
	
	return libs[root]
end

----------------------------------------------------------------------------------------------
-- threading
----------------------------------------------------------------------------------------------

---@alias basis.thread.catch fun(thread: thread, error: string): string?

---@class basis.thread._entry
---@field thread thread
---@field resume fun(self: basis.thread._entry)
---@field error? string

local threads = {}		---@type basis.thread._entry[]

-----------------------------------------------
-- threads manager loop

local function threadsLoop()
	onValidState(function()
		local e = Entities:First()
		local ctx = 'basis.threads'
		e:StopThink(ctx)
		e:SetContextThink(
			ctx,
			function()
				for i = #threads, 1, -1 do
					local entry = threads[i]
					
					if entry.error == nil and coroutine.status(entry.thread) == 'suspended' then
						entry:resume()
					end
					
					if coroutine.status(entry.thread) == 'dead' then
						table.remove(threads, i)
					end
					
					if entry.error then
						threadsLoop()
						error(debug.traceback(entry.thread, entry.error), 0)
					end
				end
				return 0
			end,
			0
		)
	end)
end
threadsLoop()

-----------------------------------------------

--- Create new coroutine resumed each game tick
---@param f function
---@param catch? basis.thread.catch
function basis:thread(f, catch)
	
	local thread = coroutine.create(f)
	
	---@type basis.thread._entry
	local entry = {
		thread = thread,
		
		resume = function(self)
			local ok, err = coroutine.resume(thread)
			if not ok then
				---@cast err string
				if catch then
					catch(thread, err)
				else
					self.error = err
				end
			end
		end
	}
	
	entry:resume()
	
	table.insert(threads, entry)
end

----------------------------------------------------------------------------------------------
-- console pipe
----------------------------------------------------------------------------------------------

local base = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-'

-----------------------------------------------
-- server console receiver

if IsServer() then

	-----------------------------------------------
	-- base decoder
	
	local reBase = {}
	for i = 1, 64 do
		reBase[ base:sub(i, i) ] = i-1
	end
	
	---@param line string
	---@return string
	local function decode(line)
		
		local bin = line:gsub('.', function(c)
			local x = reBase[c] or 0
			local bi = ''
			for b = 1, 6 do
				bi = (x % 2 == 0 and '0' or '1') .. bi
				x = math.floor(x / 2)
			end
			return bi
		end)
		
		bin = bin:sub(1, math.floor(bin:len() / 7) * 7)
		
		local s = bin:gsub('.......', function(bi)
			local pow = 2^6
			local x = 0
			for b = 1, 7 do
				if bi:sub(b,b) == '1' then
					x = x + pow
				end
				pow = pow / 2
			end
			return string.char(x)
		end)
		return s
	end
	
	-----------------------------------------------
	-- listener register
	
	local listeners = {}	---@type table<string, basis.console.listener[]>
	
	--- `server-side` <br>
	--- Listen to console event, fired by client
	---@param event string
	---@param callback fun(pid: PlayerID, data: any)
	function basis:consoleListener(event, callback)
		
		---@class basis.console.listener: basis.listener
		local listener = genericListener(listeners, event, callback)
		listener.callback = callback
		return listener
	end
	
	------------------------
	-- trigger function
	
	---@param event string
	---@param pid PlayerID
	---@param data any
	local function triggerConsoleListeners(event, pid, data)
		
		if not listeners[event] then
			return
		end
		
		local data2 = {}
		for k, v in pairs(data) do
			data2[k] = v
		end
		
		triggerListeners(listeners, event, pid, data2)
	end
	
	-----------------------------------------------
	-- pipe api
	
	local pipe = {
		data = {},
	}
	
	------------------------
	
	---@param pid PlayerID
	---@param event string
	---@param index integer
	function pipe.get(pid, event, index)
	
		local pipePid = pipe.data[pid]
		if not pipePid then
			pipePid = {}
			pipe.data[pid] = pipePid
		end
		
		local pipeEvent = pipePid[event]
		if not pipeEvent then
			pipeEvent = {}
			pipePid[event] = pipeEvent
		end
		
		local stream = pipeEvent[index]
		if not stream then
			stream = {
				line = '',
			}
			pipeEvent[index] = stream
		end
		
		return stream
	end
	
	------------------------
	
	---@param pid PlayerID
	---@param event string
	---@param index integer
	---@param line string
	function pipe.stream(pid, event, index, line)
		
		local stream = pipe.get(pid, event, index)
		
		stream.line = stream.line .. line
		
	end
	
	------------------------
	
	---@param pid PlayerID
	---@param event string
	---@param index integer
	function pipe.close(pid, event, index)
	
		local pipePid = pipe.data[pid]
		if not pipePid then
			return
		end
		
		local pipeEvent = pipePid[event]
		if not pipeEvent then
			return
		end
		
		local stream = pipeEvent[index]
		if not stream then
			return
		end
		
		------------------------
		-- clean up
	
		pipeEvent[index] = nil
		if next(pipeEvent) == nil then
			pipePid[event] = nil
			if next(pipePid) == nil then
				pipe.data[pid] = nil
			end
		end
		
		------------------------
		-- trigger listeners
		
		local ok, data = pcall(json.decode, decode(stream.line))
		
		if ok then
			triggerConsoleListeners(event, pid, data)
		end
		
	end
	
	-----------------------------------------------
	-- console listener
	
	Convars:RegisterCommand(
		'basis.client_pipe',
		
		---@param event string
		---@param line string
		function(_, event, index, line)
			
			local pawn = Convars:GetCommandClient() --[[@as CBasePlayerPawn ]]
			local pid = pawn:GetController():GetPlayerID()
			
			if line == '.' then
				pipe.close(pid, event, index)
			else
				pipe.stream(pid, event, index, line)
			end
		end,
		
		'',
		FCVAR_HIDDEN
	)
	
-----------------------------------------------
-- client console sender
	
else

	local MAX_COMAND_LENGTH = 200
	local MAX_COMANDS = 100
	
	-----------------------------------------------
	-- base encoder
	
	---@param line string
	---@return string
	local function encode(line)
		local bin = line:gsub('.', function(c)
			local x = string.byte(c)
			local bi = ''
			for b = 1, 7 do
				bi = (x % 2 == 0 and '0' or '1') .. bi
				x = math.floor(x / 2)
			end
			return bi
		end)
		
		bin = bin .. '00000'
		bin = bin:sub(1, math.floor(bin:len() / 6) * 6)
		
		local s = bin:gsub('......', function(bi)
			local pow = 2^5
			local x = 0
			for b = 1, 6 do
				if bi:sub(b,b) == '1' then
					x = x + pow
				end
				pow = pow / 2
			end
			return base:sub(x+1, x+1)
		end)
		return s
	end
	
	-----------------------------------------------
	-- sender loop
	
	---@class basis.console._chunk
	---@field event string
	---@field index integer
	---@field line string
	
	local chunks = {}	---@type basis.console._chunk[]
	local events = {}	---@type table<string, integer>
	
	onValidState(function()
		Entities:First():SetContextThink(
			'basis.consolePipe',
			
			function()
				local sent = 0
				
				for _, chunk in ipairs(chunks) do
					SendToConsole('basis.client_pipe ' .. chunk.event .. ' ' .. chunk.index .. ' ' .. chunk.line)
					sent = sent + 1
					if sent >= MAX_COMANDS then
						break
					end
				end
				
				local newChunks = {}
				for i = sent + 1, #chunks do
					table.insert(newChunks, chunks[i])
				end
				chunks = newChunks
				
				return 0
			end,
			0
		)
	end)
	
	-----------------------------------------------
	
	--- `client-side` <br>
	--- Send console event to server
	---@param event string
	---@param data any
	function basis:consoleEvent(event, data)
		
		local line = encode(json.encode(data))
		
		local index = events[event] or 0
		events[event] = index + 1
		
		table.insert(chunks, {
			event = event,
			index = index,
			line = '.'
		})
		
		local left = 1
		local len = line:len()
		while left <= len do
			table.insert(chunks, {
				event = event,
				index = index,
				line = line:sub(left, left + MAX_COMAND_LENGTH - 1),
			})
			left = left + MAX_COMAND_LENGTH
		end
		
		table.insert(chunks, {
			event = event,
			index = index,
			line = '.'
		})
	
	end
	
end

----------------------------------------------------------------------------------------------
-- server-to-client events
----------------------------------------------------------------------------------------------

---@class basis.client._event
---@field pid PlayerID
---@field event string
---@field data string

-----------------------------------------------
-- server events sender

if IsServer() then
	
	--- `server-side` <br>
	--- Send event to lua client
	---@param pid PlayerID
	---@param event string
	---@param data any
	function basis:clientEvent(pid, event, data)
		
		 ---@type basis.client._event
		local t = {
			pid = pid,
			event = event,
			data = json.encode(data),
		}
		FireGameEvent('basis.client_event', t)
	end

-----------------------------------------------
-- client events listener

else

	local listeners = {}
	
	--- `client-side` <br>
	--- Listen to events sent by server
	---@param event string
	---@param callback fun(data: any)
	function basis:clientListener(event, callback)
		
		---@class basis.client.listener: basis.listener
		local listener = genericListener(listeners, event)
		listener.callback = callback
		return listener
	end
	
	------------------------

	ListenToGameEvent(
		'basis.client_event',
		
		---@param t basis.client._event
		function(t)
			if t.pid ~= GetLocalPlayerID() then
				return
			end
			triggerListeners(listeners, t.event, json.decode(t.data))
		end,
		nil
	)

end

----------------------------------------------------------------------------------------------
-- game setup
----------------------------------------------------------------------------------------------

local setup = false		---@type boolean

function basis:startSetup()
	if IsServer() then
		onValidState(function()
			GameRules:EnableCustomGameSetupAutoLaunch(false)
			GameRules:SetCustomGameSetupTimeout(-1)
		end)
	
		
	else
	end
	
	
end

----------------------------------------------------------------------------------------------
-- core listeners
----------------------------------------------------------------------------------------------

-----------------------------------------------
-- load from server to lua client

if IsServer() then

	basis:consoleListener(
		'basis.load',
		
		---@param data basis.lib.load._eventRequest
		function(pid, data)
			local lib = basis:lib(data.name, data.root)
			lib:load(data.module, {
				async = true,
				callback = function(source, response)
					---@type basis.lib.load._eventResponse
					local res = {
						name = data.name,
						module = data.module,
						source = source,
						response = response,
					}
					basis:clientEvent(pid, 'basis.load', res)
				end
			})
		end
	)
end

----------------------------------------------------------------------------------------------
-- script loading
----------------------------------------------------------------------------------------------

-- on reload
package.preload['basis.core'] = function()

	-- refresh libs
	for _, lib in pairs(libs) do
		lib:refresh()
	end
	
	return basis
end

-----------------------------------------------

return basis