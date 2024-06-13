

-- ---@class basis.queue
-- local queue = {}

-- ---@class basis.queue.job
-- ---@operator call(...): basis.queue.job	# invoke
-- local job = {}

-- ---@class basis.queue.constructor
-- ---@operator call: basis.queue	# new queue
-- local Queue = {}

-- ---@alias basis.queue.job.callback fun(job: basis.queue.job, ...): ...: any
-- ---@alias basis.queue.setup fun(queue: basis.queue)

-- ----------------------------------------------------------------------------------------------
-- --- queue
-- ----------------------------------------------------------------------------------------------

-- function queue:constructor()
-- 	self.jobs = {}		---@type basis.queue.job[]	# Sequence of jobs
-- 	self.current = 1	---@type integer	# Index of current job to do
-- 	self.stash = {}		---@type table<any, any>	# Free-usage table to transfer data between jobs
-- 	self.parent = nil	---@type basis.queue.job?	# `read-only` <br> Job to which this queue is parented to
-- 	self._parenting = nil ---@type ('before' | 'after')?
-- 	self._pause = 0 	---@type integer
	
-- 	--- `self-bound` <br> add new job and get its invoker
-- 	---@param callback basis.queue.job.callback?
-- 	self.newInvoker = function(callback)
-- 		return self:job(callback)
-- 	end
-- end

-- -----------------------------------------------

-- --- Queue a new job
-- ---@param callback basis.queue.job.callback?
-- ---@param order integer?
-- ---@return basis.queue.job
-- function queue:job(callback, order)

-- 	---@type basis.queue.job
-- 	local _job = {}
	
-- 	for k, v in pairs(job) do
-- 		_job[k] = v
-- 	end
	
-- 	setmetatable(_job, {
-- 		__call = function(self, ...)
-- 			return self:invoke(...)
-- 		end
-- 	})
	
-- 	-- add to queue
-- 	if order then
-- 		if order ~= 1 and self.jobs[order-1] == nil then
-- 			error('Invalid job order ' .. order .. ' (no preceding jobs)', 2)
-- 		end
		
-- 		if self.jobs[order] and self.jobs[order]:wasStarted() then
-- 			error('Job on order ' .. order .. ' was already started', 2)
-- 		end		
		
-- 		table.insert(self.jobs, order, _job)
		
-- 	else
-- 		table.insert(self.jobs, _job)
-- 	end
	
-- 	_job:constructor(self, callback)
	
-- 	return _job
-- end

-- -----------------------------------------------

-- --- Pause the flow of the queue. Doesn't pause current job, but prevent remaining ones from starting. <br>
-- --- Be careful with multiple usage. Queue should be unpaused same amount of times it was paused.
-- ---@param paused boolean
-- function queue:pause(paused)
-- 	self._pause = self._pause + (paused and 1 or -1)
	
-- 	if self._pause < 0 then
-- 		error('Queue unpaused more times than paused!', 2)
-- 	end
	
-- 	if not self:isEmpty() then
-- 		self:getCurrent():_tryStart()
-- 	end
-- end

-- -----------------------------------------------

-- --- Is queue paused?
-- ---@return boolean
-- function queue:isPaused()
-- 	return self._pause ~= 0
-- end

-- -----------------------------------------------

-- --- Get order of job in this queue
-- ---@param job basis.queue.job
-- ---@return integer?
-- function queue:getIndex(job)
-- 	for index, jobOwn in ipairs(self.jobs) do
-- 		if jobOwn == job then
-- 			return index
-- 		end
-- 	end
-- end

-- -----------------------------------------------

-- --- First job in queue
-- ---@return basis.queue.job?
-- function queue:getFirst()
-- 	return self.jobs[ 1 ]
-- end

-- -----------------------------------------------

-- --- Last job in queue
-- ---@return basis.queue.job?
-- function queue:getLast()
-- 	return self.jobs[ #self.jobs ]
-- end

-- -----------------------------------------------

-- --- Current job in queue. So it is currently running. Or should be started next, but wasn't yet invoked.
-- ---@return basis.queue.job?
-- function queue:getCurrent()
-- 	return self.jobs[ self.current ]
-- end

-- -----------------------------------------------

-- --- No jobs were added to this queue
-- ---@return boolean
-- function queue:isEmpty()
-- 	return self.jobs[1] == nil
-- end

-- -----------------------------------------------

-- --- Are all jobs in queue completed? (should not be empty)
-- ---@return boolean
-- function queue:isFinished()
-- 	return not self:isEmpty() and self:getLast().done
-- end

-- -----------------------------------------------

-- --- Was first job in queue started?
-- ---@return boolean
-- function queue:isStarted()
-- 	return not self:isEmpty() and self:getFirst().invoked
-- end

-- -----------------------------------------------

-- --- Start the first job, meaning start the whole queue
-- function queue:start(...)
-- 	if not self:isEmpty() then
-- 		self:getFirst():invoke(...)
-- 	end
-- end

-- ----------------------------------------------------------------------------------------------
-- --- job
-- ----------------------------------------------------------------------------------------------

-- ---@param queue2 basis.queue | basis.queue.setup
-- ---@param addStarter boolean
-- ---@return basis.queue
-- local function optionalSetupNewQueue(queue2, addStarter)
-- 	if type(queue2) == 'function' then
-- 		local setup = queue2
-- 		queue2 = Queue.new()
-- 		if addStarter then
-- 			queue2:job()
-- 		end
-- 		setup(queue2)
-- 	else
-- 		if addStarter then
-- 			queue2:job(nil, 1)
-- 		end
-- 	end
-- 	return queue2
-- end

-- -----------------------------------------------

-- ---@param queue basis.queue
-- ---@param callback basis.queue.job.callback?
-- function job:constructor(queue, callback)
-- 	self.queue = queue			--- `read-only` <br> Queue of this job
-- 	self.callback = callback	--- Job's callback
-- 	self.invoked = false		---@type boolean	# `read-only` <br> Was this job invoked?
-- 	self.running = false		---@type boolean	# `read-only` <br> Is this job currently running?
-- 	self.done = false			---@type boolean	# `read-only` <br> Is this job completed?
-- 	self._result = {}			---@type any[]
-- 	self._args = {}				---@type table<integer, any>
-- 	self._awaiting = {}			---@type basis.queue[]
-- 	self._launching = {}		---@type basis.queue[]
-- 	self._before = nil			---@type basis.queue?
-- 	self._after = nil			---@type basis.queue?
-- end

-- -----------------------------------------------

-- ---@return boolean
-- function job:wasStarted()
-- 	return self.running or self.done
-- end

-- -----------------------------------------------

-- --- Returns of job's callback
-- ---@return any ...
-- function job:getResult()
-- 	return unpack(self._result)
-- end

-- -----------------------------------------------

-- --- Synchronously await job to be completed
-- ---@return any ...
-- function job:await()
-- 	while not self.done do
-- 		if coroutine.running() then
-- 			coroutine.yield()
-- 		end
-- 	end
-- 	return self:getResult()
-- end

-- -----------------------------------------------

-- --- Force job to await passed queue to be finished (before own execution)
-- ---@param queue2 basis.queue | basis.queue.setup	# Queue to await. <br> May be passed a setup-function, in this case new queue will be created and passed to this function instantly
-- ---@return basis.queue.job
-- function job:linkBefore(queue2)
-- 	if self.invoked then
-- 		error('Job is already invoked!', 2)
-- 	end
	
-- 	queue2 = optionalSetupNewQueue(queue2, false)
	
-- 	table.insert(self._awaiting, queue2)
	
-- 	return self
-- end

-- -----------------------------------------------

-- --- Start new queue after job is finished
-- ---@param queue2 basis.queue | basis.queue.setup	# Queue to start. <br> May be passed a setup-function, in this case new queue will be created and passed to this function instantly
-- ---@return basis.queue.job
-- function job:linkAfter(queue2, ...)
-- 	queue2 = optionalSetupNewQueue(queue2, true)
	
-- 	if queue2:isStarted() then
-- 		error('Queue is already started!', 2)
-- 	end
	
-- 	if self.done then
-- 		queue2:start()
-- 	else
-- 		table.insert(self._launching, queue2)
-- 	end
	
-- 	return self
-- end

-- -----------------------------------------------

-- --- Setup preceding child queue. This queue will be started with a job, callback will be called after queue is finished.
-- ---@param setup basis.queue.setup
-- ---@return basis.queue.job
-- function job:before(setup)
-- 	if self.done then
-- 		error('Job is already invoked!', 2)
-- 	end
	
-- 	if not self._before then
-- 		self._before = Queue.new()
-- 		self._before:job()
-- 		self._before.parent = self
-- 		self._before._parenting = 'before'
-- 	end
	
-- 	setup(self._before)
	
-- 	if self._before:isStarted() then
-- 		error('Child queue was started in setup function!', 2)
-- 	end

-- 	return self
-- end

-- -----------------------------------------------

-- --- Setup subsequent child queue. This queue will be started after callback, and should be finished to complete the job.
-- ---@param setup basis.queue.setup
-- ---@return basis.queue.job
-- function job:after(setup)
-- 	if self.done then
-- 		error('Job is already invoked!', 2)
-- 	end
	
-- 	if not self._after then
-- 		self._after = Queue.new()
-- 		self._after:job()
-- 		self._after.parent = self
-- 		self._after._parenting = 'after'
-- 	end
	
-- 	setup(self._after)

-- 	if self._after:isStarted() then
-- 		error('Child queue was started in setup function!', 2)
-- 	end
	
-- 	return self
-- end

-- -----------------------------------------------

-- --- Invoke the job, marking it as ready to start. <br>
-- --- Waits for previous jobs in queue to finish, then starts this job. If this is first job in queue, it will be started immedeatly. <br>
-- --- Passed arguments will be transfered to the callback.
-- ---@return basis.queue.job
-- function job:invoke(...)
-- 	if self.invoked then
-- 		error('Job is already invoked!', 2)
-- 	end
	
-- 	self.invoked = true
-- 	self._args = {...}
-- 	self:_tryStart()
	
-- 	return self
-- end

-- -----------------------------------------------

-- function job:_tryStart()
	
-- 	------------------------
-- 	-- ready check
	
-- 	if not self.invoked then
-- 		return
-- 	end
	
-- 	if self.running or self.done then
-- 		return
-- 	end
	
-- 	if self.queue:isPaused() then
-- 		return
-- 	end
	
-- 	if self.queue:getCurrent() ~= self then
-- 		return
-- 	end
	
-- 	------------------------
-- 	-- await linked queues
	
-- 	for _, await in ipairs(self._awaiting) do
-- 		if not await:isFinished() then
-- 			return
-- 		end
-- 	end
	
-- 	------------------------
-- 	-- started state
	
-- 	self.running = true
	
-- 	------------------------
-- 	-- on callback
	
-- 	local function callback()
		
-- 		------------------------
-- 		-- call callback
		
-- 		if self.callback then
-- 			self._result = { self:callback(unpack(self._args)) }
-- 		end
		
-- 		------------------------
-- 		-- on complete
		
-- 		local function complete()
		
-- 			------------------------
-- 			-- completed state
			
-- 			self.done = true
-- 			self.running = false
-- 			self.queue.current = self.queue.current + 1
			
-- 			------------------------
-- 			-- start next job
		
-- 			local next = self.queue:getCurrent()
-- 			if next then
-- 				next:_tryStart()
-- 			end
			
-- 			------------------------
-- 			-- launch linked queues
			
-- 			for _, launch in ipairs(self._launching) do
-- 				launch:start()
-- 			end
-- 		end
		
-- 		------------------------
-- 		-- subsequent queue
		
-- 		if self._after then
-- 			self._after:job(complete):invoke()
-- 			self._after:start()
-- 		else
-- 			complete()
-- 		end
		
-- 	end
	
-- 	------------------------
-- 	-- preceding queue
	
-- 	if self._before then
-- 		self._before:job(callback):invoke()
-- 		self._before:start()
-- 	else
-- 		callback()
-- 	end	
	
-- end

-- ----------------------------------------------------------------------------------------------
-- -- module
-- ----------------------------------------------------------------------------------------------

-- ---@return basis.queue
-- function Queue.new()
	
-- 	---@type basis.queue
-- 	local _queue = {}
	
-- 	for k, v in pairs(queue) do
-- 		_queue[k] = v
-- 	end
	
-- 	_queue:constructor()
	
-- 	return _queue
-- end

-- -----------------------------------------------

-- return Queue