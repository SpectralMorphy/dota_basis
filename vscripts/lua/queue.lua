local _ = {}

---@class basis.queue.constructor
---@operator call: basis.queue		# new queue
local constructor = {}

---@class basis.queue
---@operator call: basis.queue.job	# new job
local queue = {}

---@class basis.queue.job
---@operator call: basis.queue.job	# invoke this job
local job = {}

---@alias basis.queue.callback fun(queue: basis.queue)
---@alias basis.queue.job.callback fun(job: basis.queue.job, ...): ...: any
---@alias basis.queue.setup fun(queue: basis.queue)

----------------------------------------------------------------------------------------------
-- queue
----------------------------------------------------------------------------------------------

function queue:constructor()
	self.jobs = {}			---@type basis.queue.job[]	# `read-only` <br> Jobs in this queue
	self.current = 1		---@type integer			# `read-only` <br> Index of job which is currently executing or pending to be executed
	self.closed = false		---@type boolean			# `read-only` <br> Is this queue closed
	self.ended = false		---@type boolean			# `read-only` <br> Queue is closed and all jobs are completed
	self.parent = nil		---@type basis.queue.job?	# `read-only` <br> Job this queue is parented to (as 'before' or 'after')
	self._overCallbacks = {}	---@type basis.queue.callback[]
	self._endCallbacks = {}		---@type basis.queue.callback[]
end

-----------------------------------------------

--- Add new job to the queue
---@param index integer							# order of the job
---@param callback? basis.queue.job.callback	# action to execute
---@return basis.queue.job
---@overload fun(self: basis.queue, callback?: basis.queue.job.callback): basis.queue.job
function queue:job(index, callback)

	if self.closed then
		error('Cannot add jobs to closed queue', 2)
	end

	---@type basis.queue.job
	local _job = setmetatable({}, {
		__index = job,
		__call = job.invoke
	})
	
	------------------------
	-- put in queue
	
	if type(index) ~= 'number' then
		callback = index --[[@as basis.queue.job.callback]]
		index = #self.jobs + 1
	end
	
	local oldJob = self.jobs[index]
	if oldJob and oldJob.started then
		error('Cannot insert new job before the executed job', 2)
	end
	
	table.insert(self.jobs, index, _job)
	
	------------------------
	-- init job
	
	_job:constructor(self, callback)

	return _job
end

-----------------------------------------------

--- Start queue by invoking its first job
---@param ... any
---@return basis.queue
function queue:start(...)
	local job = self.jobs[1]
	if not job then
		error('Cannot start queue without jobs', 2)
	end
	if job.invoked then
		error('Cannot start queue: first job is already invoked', 2)
	end
	job:invoke(...)
	return self
end

-----------------------------------------------

--- Was this queue started
---@return boolean
function queue:isStarted()
	local job = self.jobs[1]
	if job and not job.started then
		return true
	end
	return false
end

-----------------------------------------------

--- Close queue
---@return basis.queue
function queue:close()
	self.closed = true
	_.tryEnd(self)
	return self
end

-----------------------------------------------

--- Callback when queue ends
---@param callback basis.queue.callback
---@return basis.queue
function queue:onEnd(callback)
	if self.ended then
		callback(self)
	else
		table.insert(self._endCallbacks, callback)
	end
	return self
end

-----------------------------------------------

--- Is this queue empty? (no any jobs were added)
---@return boolean
function queue:isEmpty()
	return self.jobs[1] == nil
end

-----------------------------------------------

--- If all jobs in queue are completed (and queue is not empty)
---@return boolean
function queue:isOver()
	if self:isEmpty() then
		return false
	end
	return self:getLast().done
end

-----------------------------------------------

--- Callback when queue is over
---@param callback basis.queue.callback
function queue:onOver(callback)
	if self:isOver() then
		callback(self)
	else
		table.insert(self._overCallbacks, callback)
	end
end

-----------------------------------------------

---@param self basis.queue
function _.tryEnd(self)
	
	--- over callbacks
	if self:isOver() then
		for _, callback in ipairs(self._overCallbacks) do
			callback(self)
		end
		self._overCallbacks = {}
	end

	--- end checks
	if not self.closed then
		return
	end
	if self.current <= #self.jobs then
		return
	end
	
	--- end callbacks
	for _, callback in ipairs(self._endCallbacks) do
		callback(self)
	end
	
	self._endCallbacks = {}
	self.ended = true
end

-----------------------------------------------

--- Get order of the job in queue. <br>
--- Will return -1, if job does not belong to this queue
---@param job basis.queue.job
---@return integer
function queue:getIndex(job)
	for i, job2 in ipairs(self.jobs) do
		if job2 == job then
			return i
		end
	end
	return -1
end

-----------------------------------------------

--- Last job in queue
---@return basis.queue.job?
function queue:getLast()
	return self.jobs[#self.jobs]
end

-----------------------------------------------

--- Get job which is currently executing or pending to be executed
---@return basis.queue.job?
function queue:getCurrent()
	return self.jobs[self.current]
end

-----------------------------------------------

--- Return of last completed job's callback
---@return any ...
function queue:getLastResult()
	local job = self:getCurrent()
	if job then
		if not job.callbacked then
			job = self.jobs[self.current - 1]
		end
		if job then
			return job:getResult()
		end
	end
end

----------------------------------------------------------------------------------------------
-- job
----------------------------------------------------------------------------------------------

---@class basis.queue.job._split
---@field queue basis.queue
---@field key table

---@param queue basis.queue
---@param callback? basis.queue.job.callback 
function job:constructor(queue, callback)
	self.queue = queue			--- `read-only` <br> Queue this job belongs to
	self.callback = callback	--- Main callback
	self.invoked = false		---@type boolean	# `read-only` <br> Was this job invoked?
	self.started = false		---@type boolean	# `read-only` <br> Was this job started?
	self.callbacked = false		---@type boolean	# `read-only` <br> Was callback of this job executed?
	self.running = false		---@type boolean	# `read-only` <br> Is this job currently executing?
	self.done = false			---@type boolean	# `read-only` <br> Is this job completed?
	self._args = {}				---@type any[]
	self._result = {}			---@type any[]
	self._split = {}			---@type basis.queue.job._split[]
	self._merge = {}			---@type basis.queue[]
	self._before = nil			---@type basis.queue?
	self._arter = nil			---@type basis.queue?
end

-----------------------------------------------

---@param self basis.queue.job
local function child(self)
	local _queue = constructor.new()
	_queue.parent = self
	_queue:job()
	return _queue
end

-----------------------------------------------

--- Mark this job ready to start. <br.
--- Taken parameters will be transfered to the callback
---@param ... any
---@return basis.queue.job
function job:invoke(...)
	if self.invoked then
		error('Cannot invoke job, which already invoked', 2)
	end
	self.invoked = true
	self.args = {...}
	_.tryStart(self)
	return self
end

-----------------------------------------------

--- Queue to be started with job, before the callback. No need to close.
---@return basis.queue
function job:before()
	if not self._before then
		self._before = child(self)
	end
	return self._before
end

-----------------------------------------------

--- Queue to be started with job, after the callback. No need to close.
---@return basis.queue
function job:after()
	if not self._after then
		self._after = child(self)
	end
	return self._after
end

-----------------------------------------------

--- Wait passed queue to end (don't forget to close it), before this job can be started.
--- May take a setup-function as parameter. In this case new queue will be created and passed to the setup-function
---@param queue basis.queue | basis.queue.setup
---@return basis.queue.job
function job:merge(queue)
	
	if self.started then
		error('Cannot merge to job, which is already started', 2)
	end
	
	if type(queue) == 'function' then
		local setup = queue
		queue = constructor.new()
		setup(queue)
	end
	
	if not queue.ended then
		table.insert(self._merge, queue)
		
		queue:onEnd(function()
			_.tryStart(self)
		end)
	end
	
	return self
end

-----------------------------------------------

--- Start passed queue after this job is completed. <br>
--- May take a setup-function as parameter. In this case new queue will be created and passed to the setup-function
---@param queue basis.queue | basis.queue.setup
---@return basis.queue.job
function job:split(queue)
	
	if type(queue) == 'function' then
		local setup = queue
		queue = constructor.new()
		queue:job()
		setup(queue)
	else
		if queue:isStarted() then
			error('Cannot split to queue, which is already started', 2)
		end
		queue:job(1)
	end
	
	if self.done then
		queue:start()
	else
		
		-- prevent manual start of splited queue
		local launchKey = {}
		local job1 = queue.jobs[1]
		function job1:invoke(key)
			if key ~= launchKey then
				error('Cannot start splited queue', 2)
			end
			return job.invoke(self)
		end
	
		---@type basis.queue.job._split
		local entry = {
			queue = queue,
			key = launchKey,
		}
		table.insert(self._split, entry)
	end

	return self
end

-----------------------------------------------

--- Get job's return from callback (if it was called)
---@return any ...
function job:getResult()
	return unpack(self._result)
end

---@param self basis.queue.job
function _.setResult(self, ...)
	self._result = {...}
	self.callbacked = true
end

-----------------------------------------------

--- Synchronously wait this job to complete and get its result
---@return any ...
function job:await()
	if not coroutine.running() then
		error('Cannot await job in main thread', 2)
	end
	while not self.done do
		coroutine.yield()
	end
	return self:getResult()
end

-----------------------------------------------

---@param self basis.queue.job
function _.tryStart(self)
	
	if not self.invoked then
		return
	end
	
	if self.started then
		return
	end
	
	local prevJob = self.queue.jobs[self.queue:getIndex(self) - 1]
	if prevJob and not prevJob.done then
		return
	end
	
	------------------------
	-- check merged queues
	
	for _, queue in ipairs(self._merge) do
		if not queue.ended then
			return
		end
	end
	
	------------------------
	-- running state
	
	self.started = true
	self.running = true
	
	------------------------
	-- start job
	
	local function start()
		
		if self.callback then
			self:callback(unpack(self.args))
			self.callbacked = true
		end
		
		------------------------
		-- complete job
	
		local function complete()
		
			self.running = false
			self.done = true
			
			------------------------
			-- next job
			
			self.queue.current = self.queue.current + 1
			local nextJob = self.queue:getCurrent()
			if nextJob then
				_.tryStart(nextJob)
			else
				_.tryEnd(self.queue)
			end
			
			------------------------
			-- start splitted queues
			
			for _, split in ipairs(self._split) do
				split.queue:start(split.key)
			end
			
		end
		
		------------------------
		-- after queue
		
		if self._after then
			self._after:onOver(complete)
			self._after:start()
		else
			complete()
		end
		
	end
		
	------------------------
	-- before queue
	
	if self._before then
		self._before:onOver(start)
		self._before:start()
	else
		start()
	end
	
end

----------------------------------------------------------------------------------------------
-- constructor
----------------------------------------------------------------------------------------------

--- Create new queue
---@return basis.queue
function constructor.new()
	
	---@type basis.queue
	local _queue = setmetatable({}, {
		__index = queue,
		__call = queue.job
	})
	
	_queue:constructor()
	
	return _queue
end

-----------------------------------------------

setmetatable(constructor, {
	__call = function()
		return constructor.new()
	end
})

-----------------------------------------------

return {
	Queue = constructor
}