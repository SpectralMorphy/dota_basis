--------------------------------------------------------
-- GitHub: !!!
--------------------------------------------------------

--------------------------------------------------------
-- fix debug.traceback with non-string message

local _debug_traceback = debug.traceback

---@overload fun(message?: any, level?: integer): string
---@param thread	thread
---@param message?	any
---@param level?	integer
---@return string	message
---@nodiscard
---@diagnostic disable-next-line:no-unknown
debug[('traceback')] = function(thread, message, level)
	if type(thread) ~= 'thread' then
		level = message		--[[@as integer?]]
		message = thread	--[[@as any?]]
		thread = (nil)		--[[@as thread]]
	end
	
	message = tostring(message)
	level = level + 1
	
	if thread == nil then
		return _debug_traceback(message, level)
	else
		return _debug_traceback(thread, message, level)
	end
end

--------------------------------------------------------
-- add __pairs metafield for 5.1

if _VERSION == 'Lua 5.1' then
	local _pairs = _G.pairs

	---@version 5.1
	---@generic T: table, K, V
	---@param t T
	---@return fun(table: table<K, V>, index?: K):K, V
	---@return T
	---@diagnostic disable-next-line:no-unknown
	_G[('pairs')] = function(t)
		local meta = getmetatable(t)
		if type(meta) == 'table' and meta.__pairs ~= nil then
			return meta.__pairs(t)
		end
		return _pairs(t)
	end
end

--------------------------------------------------------
-- unpack versions

---@diagnostic disable-next-line:deprecated
local unpack = table.unpack

if _VERSION == 'Lua 5.1' then
	---@diagnostic disable-next-line:deprecated
	unpack = _G.unpack	--[[@as function]]
end

--------------------------------------------------------

---@class basic
local basic = {}

---@alias funCheck fun( object: any ): boolean
---@alias funCheckError fun(value: any): ok: boolean, conditionName: any
---@class Array<T>: {[integer]: T}
---@class Stringlike

--------------------------------------------------------
--- Concatenates objects into string, applying 'tostring' to each
---@param ... any
---@return string
function basic.concat(...)
	local arg = {...}
	local len = #arg
	if len == 0 then
		return ''
	elseif len == 1 then
		return tostring(arg[1])
	else
		return basic.concat(tostring(arg[1]) .. tostring(arg[2]), unpack(arg, 3))
	end
end

--------------------------------------------------------
--- Contains all predefined types.
--- Type may be retreived in both lower and upper case.
---@class TYPES: {[string]: basic.Type}
local TYPES = {}
basic.TYPES = TYPES

local defType_predef = true
local metatype_type = {}
local metatype_exception = {}
local metatype_iterator = {}

--------------------------------------------------------

---@param	name	any
---@param	parent?	basic.Type
---@param	check?	funCheck
---@return basic.Type
local function createType(name, parent, check)
	
	--------------------------------------------------------
	--- Object representing custom type.
	--- Custom types may help to distinguish between groups of similar objects, not covered by in-built 'type' function
	--- There are some predefined custom types (see `TYPES`), but you may define new ones as many as needed.
	--- Custom type may be prime, or an aggregation.
	--- 
	--- Each type must have a name.
	--- Name is assumed for use in messages. For example, it's shown in 'argcheck' error message. It's better to be unique, but not necessary.
	--- Converting type to a string returns its name.
	--- 
	--- *PRIME TYPES*
	--- System of prime types is pretty similar to a hierarchy of classes in OOP.
	--- Prime types form a tree with root type 'any'.
	--- This 'any' type covers every possible value in lua.
	--- On next level lua types are located.
	--- Child types extend their parent, restricting objects belonging to them more specifically.
	--- If object belongs to some type, it also belongs to all parents of this type up to the root.\
	--- Full tree of predefined types:  
	---```
	--- ┍ any				
	--- ├─╼ nil				
	--- ├─╼ boolean			
	--- ├─┮ number			
	--- │ └─╼ int			
	--- ├─╼ string			
	--- ├─╼ function		
	--- ├─┮ table			
	--- │ ├─┮ map         -- basic k-v table without meta functions
	--- │ │ └─╼ array     -- pure lua array (each field is counted by '#' length operator)
	--- │ └─┮ complex     -- any table with meta table defined
	--- │   ├─╼ type      -- well.. the type
	--- │   ├─╼ exception -- see 'exception'
	--- │   └─╼ iterator  -- !!!
	--- ├─╼ userdata
	--- └─╼ thread
	---```
	---
	--- Prime type is defined by its check function.
	--- Check function validates if specific object belongs to the type.
	---
	--- Each prime type (except of the root type 'any') must have a parent prime type.
	--- Validated object must satisfy the parent check as well. When validating, own check is not even performed if parent's failed.
	--- Check functions of types with the same parent should not intersect (should not both return true for the same object). Otherwise 'getType' function may be inconsistent.
	--- So each new prime type should be parented (directly or over few parents) to the 'complex' or 'userdata' predefined types. Other parents may cause unintentional intersections in big or dependent projects.
	---
	--- *AGGREGATION TYPES*  
	--- Aggregations are the way to define intersecting types.
	--- May union different types into one.
	--- May serve as extra checks to any types without fear of intersections.
	---
	--- Aggregation consists of one or more conditions.
	--- Condition consists of a prime type and an optional check function
	--- Condition is satisfied when validated object belongs to the prime type and passes check function (if provided).
	--- Object belongs to an aggregation, if it satisfies any of conditions.
	---
	--- Aggregations have no parent type.
	--- 
	--- Predefined aggregations:
	---```
	--- some			-- anything which is not nil
	--- list			-- map with only natural keys !!!
	--- indexable		-- any table or userdata with __index meta field
	--- callable		-- function or other object which may be called as a function
	--- stringlike		-- may be concatenated like a string
	--- iterable		-- map or iterator
	---```
	---
	---!!!example
	---
	---@class basic.Type
	local typ = {}
	
	local meta = {
		type = metatype_type,
		children = {},
		__tostring = function(self)
			return self.name()
		end,
		__concat = basic.concat,
	}
	setmetatable(typ, meta)
	
	--- Check if an object belongs to the type
	---@param object	any
	---@return boolean
	function typ.check(object)
		if not typ.parent().check(object) then
			return false
		end
		---@cast check -nil
		if check(object) then
			return true
		end
		return false
	end
	
	--- Get the parent type
	---@return basic.Type?
	function typ.parent()
		return parent
	end
	
	--- Get name of the type
	---@return any
	function typ.name()
		return name
	end
	
	--- Is this type an aggregation (or prime)
	---@return boolean
	function typ.isAggregation()
		return false
	end
	
	---@return Array<basic.Type>
	function typ.children()
		return map(meta.children)
	end
	
	if parent then
		local parentMeta = getmetatable(parent)
		table.insert(parentMeta.children, typ)
	end
	
	return typ
end

--------------------------------------------------------
--- Define basic custom type
---@param name		any								# name of the type
---@param parent	basic.Type						# parent type
---@param check		funCheck						# check function
---@return basic.Type
function basic.defType(name, parent, check)
	if not defType_predef then
		name, parent, check = basic.args(
			{name, parent, check},
			{
				basic.TYPES.ANY,
				basic.TYPES.TYPE,
				basic.TYPES.FUNCTION,
			}
		)
	end
	
	return createType(name, parent, check)
end

--------------------------------------------------------
--- Define a new custom type aggregation
---@param name	any										# name of the type
---@param ...	{base: basic.Type, check?: funCheck}	# aggregation conditions
---@return basic.Type
function basic.defAggreg(name, ...)
	local conditions = {...}
	if not defType_predef then
		basic.args(
			{name, ...},
			{
				basic.TYPES.ANY,
				{
					multiple = true,
					name = 'condition',
					message = 'is not an aggregation condition',
					checks = function(condition)
						if not TYPES.MAP.check(condition) then
							return false
						end
						if not TYPES.TYPE.check(condition.base) then
							return false
						end
						if condition.check ~= nil and not TYPES.CALLABLE.check(condition.check) then
							return false
						end
						return true
					end,
				}
			}
		)
	end
	
	local typ = createType(name)
	
	typ.check = function(object)
		for _, condition in ipairs(conditions) do
			if condition.base.check(object) then
				if condition.check == nil or condition.check(object) then
					return true
				end
			end
		end
		return false
	end
	
	typ.isAggregation = function()
		return true
	end
	
	return typ
end

TYPES.ANY = createType('any')
TYPES.ANY.check = function()
	return true
end

TYPES.NIL = basic.defType(
	'nil',
	TYPES.ANY,
	function(object)
		return object == nil
	end
)

---@param name any
---@return basic.Type
local function defLuaType(name)
	return basic.defType(
		name,
		TYPES.ANY,
		function(object)
			return type(object) == name
		end
	)
end

TYPES.BOOLEAN  = defLuaType('boolean')
TYPES.NUMBER   = defLuaType('number')
TYPES.STRING   = defLuaType('string')
TYPES.FUNCTION = defLuaType('function')
TYPES.TABLE    = defLuaType('table')
TYPES.USERDATA = defLuaType('userdata')
TYPES.THREAD   = defLuaType('thread')

TYPES.INTEGER = basic.defType(
	'integer',
	TYPES.NUMBER,
	function(object)
		return object == math.floor(object)
	end
)
TYPES.MAP = basic.defType(
	'map',
	TYPES.TABLE,
	function(object)
		return getmetatable(object) == nil
	end
)
TYPES.ARRAY = basic.defType(
	'array',
	TYPES.MAP,
	function(object)
		---@cast object {[any]: any}
		local n = 0
		for _ in pairs(object) do
			n = n + 1
		end
		return #object == n
	end
)
TYPES.COMPLEX = basic.defType(
	'complex',
	TYPES.TABLE,
	function(object)
		return getmetatable(object) ~= nil
	end
)
TYPES.TYPE = basic.defType(
	'type',
	TYPES.COMPLEX,
	function(object)
		return getmetatable(object).type == metatype_type
	end
)
TYPES.EXCEPTION = basic.defType(
	'exception',
	TYPES.COMPLEX,
	function(object)
		return getmetatable(object).type == metatype_exception
	end
)
TYPES.ITERATOR = basic.defType(
	'iterator',
	TYPES.COMPLEX,
	function(object)
		return getmetatable(object).type == metatype_iterator
	end
)

TYPES.SOME = basic.defAggreg('some',
	{
		base = TYPES.ANY,
		check = function(object)
			return object ~= nil
		end,
	}
)

local function hasMetaField(field)
	return function(object)
		local mt = getmetatable(object)
		if type(mt) == 'table' and mt[field] ~= nil then
			return true
		end
	end
end

TYPES.INDEXABLE = basic.defAggreg('indexable',
	{
		base = TYPES.TABLE,
	},
	{
		base = TYPES.USERDATA,
		check = hasMetaField('__index'),
	}
)

---@alias basic.Callable function | table | userdata
TYPES.CALLABLE = basic.defAggreg('callable',
	{
		base = TYPES.FUNCTION,
	},
	{
		base = TYPES.TABLE,
		check = hasMetaField('__call'),
	},
	{
		base = TYPES.USERDATA,
		check = hasMetaField('__call'),
	}
)
TYPES.STRINGLIKE = basic.defAggreg('stringlike',
	{
		base = TYPES.STRING,
	},
	{
		base = TYPES.TABLE,
		check = hasMetaField('__concat'),
	},
	{
		base = TYPES.USERDATA,
		check = hasMetaField('__concat'),
	}
)

---@alias basic.Iterable table | basic.Iterator
TYPES.ITERABLE = basic.defAggreg('iterable',
	{
		base = TYPES.TABLE,
	},
	{
		base = TYPES.ITERATOR,
	}
)

defType_predef = false
for name, typ in pairs(TYPES) do
	TYPES[name:lower()] = typ
end

--------------------------------------------------------
---	Stringify object. Quotes strings to distinguish their type 
---@param object any
---@return string
function basic.stringify(object)
	if TYPES.STRING.check(object) then
		return '"' .. object .. '"'
	end
	return tostring(object)
end

--------------------------------------------------------

---@param t table<any, any>
---@return table<any, any>
local function copy(t)
	local new = {} ---@type table<any, any>
	for k, v in pairs(t) do
		new[k] = v
	end
	return new
end

--------------------------------------------------------

---@param t1? any
---@param t2? any
---@param map? table<any, table<any, table<any, any>>>
---@return table?
local function deepmerge(t1, t2, map)
	if t2 == nil then
		return t1
	elseif type(t2) ~= 'table' then
		return t2
	end
	
	---@cast t2 table<any, any>
	
	if map == nil then
		map = {}
	end
	
	local t1mapKey = t1
	if type(t1) ~= 'table' then
		t1mapKey = 1
	end
	
	local map2 = map[t1mapKey]
	if not map2 then
		map2 = {}
		map[t1mapKey] = map2
	end
	
	local mapped = map2[t2]
	if not mapped then	
		if t1mapKey == 1 then
			mapped = {}
		else
			mapped = t1
		end
		map2[t2] = mapped
		
		for k, v2 in pairs(t2) do
			mapped[k] = deepmerge(mapped[k], v2, map)
		end
	end
	
	return mapped
end

--------------------------------------------------------
---@class basic.traceback.step
---@field source      string
---@field short_src   string
---@field currentline integer
---@field name        string
---@field namewhat    string
---@field linedefined integer
---@field formated    string

--------------------------------------------------------
--- Debug info about each stack trace level
---@param level? integer
---@return Array<basic.traceback.step>
function basic.traceback(level)
	local stack = {}
	level = level or 1
	
	while true do
		level = level + 1
		local info = debug.getinfo(level, 'Sln')
		if info == nil then
			return stack
		end
		
		local src = info.short_src
		if info.currentline > 0 then
			src = src .. ':' .. info.currentline
		end
		
		local where = ''
		if info.name ~= nil then
			where = ("in function '%s'"):format(info.name)
		elseif info.linedefined > 0 then
			where = ("in function <%s:%s>"):format(info.short_src, info.linedefined)
		elseif info.what == 'main' then
			where = 'in main chunk'
		else
			where = '?'
		end
			
		local formated = ('%s: %s'):format(src, where)
			
		table.insert(stack, {
			source      = info.source,
			short_src   = info.short_src,
			currentline = info.currentline,
			name        = info.name,
			namewhat    = info.namewhat,
			linedefined = info.linedefined,
			formated    = formated,
		})
	end
end

--------------------------------------------------------

basic.EXKIND = {
	ARG = {},
}

--------------------------------------------------------
---@param message any
---@param kind? any
---@param level? integer
---@return basic.Exception
function basic.exception(message, kind, level)
	basic.argcheck('#3 (level)', {basic.TYPES.INTEGER, basic.TYPES.NIL}, level)
	local _level = level or 1
	local _trace = basic.traceback(2)
	
	--------------------------------------------------------
	--- !!!Exception
	---@class basic.Exception
	local ex = {}
	
	local function checkSelf(self)
		if self ~= ex then
			basic.throw(basic.exception('invalid self', basic.EXKIND.ARG), 3)
		end
	end
	
	setmetatable(ex, {
		__tostring = function(self)
			return self:tostring()
		end,
		__concat = function(l, r)
			return tostring(l) .. tostring(r)
		end,
		type = metatype_exception,
	})
	
	---@return any
	function ex:message()
		checkSelf(self)
		return message
	end
	
	---@return any
	function ex:kind()
		checkSelf(self)
		return kind
	end
	
	---@return integer
	function ex:level()
		checkSelf(self)
		return _level
	end
	
	---@param level integer
	function ex:setLevel(level)
		checkSelf(self)
		_level = level
	end
	
	---@return string
	function ex:tostring()
		local traceStep = _trace[self:level()]
		local message = tostring(self:message())
		if traceStep then
			local prefix = traceStep.short_src
			if traceStep.currentline > 0 then
				prefix = prefix .. ':' .. traceStep.currentline
			end
			message = prefix .. ': ' .. message
		end
		return message
	end
	
	---@param raw? false
	---@return string
	---@overload fun(self, raw: true): Array<basic.traceback.step>
	function ex:trace(raw)
		checkSelf(self)
		basic.argcheck('#2 (raw)', {basic.TYPES.BOOLEAN, basic.TYPES.NIL}, raw, 2)
		
		if raw then
			return deepmerge({}, _trace) --[[@as Array<basic.traceback.step>]]
		else
			local traceText = 'stack traceback:'
			for _, traceStep in ipairs(_trace) do
				traceText = traceText .. '\n\t' .. traceStep.formated
			end
			return traceText
		end
	end
	
	return ex
end

--------------------------------------------------------
---@alias basic.Error string | basic.Exception

local try_level = 0

--------------------------------------------------------
---!!!
---@param err basic.Error
---@param level? integer
function basic.throw(err, level)
	local isException = basic.TYPES.EXCEPTION.check(err)
	if not isException then
		basic.argcheck('#1 (err)', {basic.TYPES.STRING, basic.TYPES.EXCEPTION}, err)
	end
	if level == nil then
		level = 1
	else
		basic.argcheck('#2 (level)', {basic.TYPES.INTEGER, basic.TYPES.NIL}, level)
	end
	
	if isException then
		---@cast err basic.Exception
		if try_level == 0 then
			err = tostring(err:message())
			
		else
			if level > 0 then
				err:setLevel(level)
			end
		end
	end
	
	error(err, level + 1)
end

--------------------------------------------------------
---!!!
---@param f function
---@param handler fun(err: basic.Exception): propagate: basic.Error?
function basic.try(f, handler)
	local exception ---@type basic.Exception
	
	try_level = try_level + 1
	local ok = xpcall(
		f,
		function(err)
			if basic.TYPES.EXCEPTION.check(err) then
				exception = err
			else
				exception = basic.exception(err, nil, 2)
			end
		end
	)
	try_level = try_level - 1
	
	if not ok then
		local err = handler(exception)
		if err ~= nil then
			basic.throw(err, 0)
		end
	end
end

--------------------------------------------------------

local argerror_template = "bad argument %s to '%s' (%s)"
local argcheck_template = 'expected %s, got %s'

--------------------------------------------------------
--- Throw argument error
---@param argName any			# name of argument in error message
---@param message any			# message about what is wrong with argument
---@param level? integer		# error level (function in the stack to blame)
function basic.argerror(argName, message, level)

	if	level ~= nil
	and	not TYPES.INTEGER.check(level) then
		basic.argerror('#level', argcheck_template:format('integer', basic.stringify(level)))
	end
	
	level = (level or 2) + 1
	
	local funcInfo = debug.getinfo(level - 1, 'n')
	local funcName = funcInfo.name or '?'
	
	basic.throw(
		basic.exception(
			argerror_template:format(
				tostring(argName),
				funcName,
				tostring(message)
			),
			basic.EXKIND.ARG
		),
		level
	)
end

--------------------------------------------------------
---@alias argCheck basic.Type | funCheckError 
---@alias argChecks argCheck | Array<argCheck>

---@param checks argChecks
---@param pos? integer
---@return Array<argCheck>, string
local function check_argChecks(checks, pos)
	local argName = '#checks'
	if pos then
		argName = '#' .. pos .. ' (checks)'
	end
	if not TYPES.ARRAY.check(checks) then
		if TYPES.TYPE.check(checks)
		or TYPES.CALLABLE.check(checks) then
			---@cast checks argCheck
			return {checks}, argName
		else
			basic.argerror(argName, argcheck_template:format('array/type/function', basic.stringify(checks)), 3)
		end
	end
	---@cast checks Array<argCheck>
	return checks, argName
end

--------------------------------------------------------
--- Validate argument. Also returns error message on fail.
--- Is 'message' is passed, this message will be used.
--- Otherwise error message will be concatenated from checks.
--- If check is a function, its 2d returned (which expected to be condition name) is concatenated.
--- If check is a type, its name is concatenated.
---@param checks argChecks				# validation conditions
---@param value any						# value to validate
---@param message? any					# message about what is wrong with value. '$1' is a placeholder for the actual value
---@return boolean, string?
function basic.validate(checks, value, message)
	checks = check_argChecks(checks, 2)
	
	if #checks == 0 then
		return true
	end
	
	local typeList = {} ---@type Array<string>
	local messageList = {} ---@type Array<string>
	local rawCheck = false
	
	for icheck, check in ipairs(checks) do
		if basic.TYPES.TYPE.check(check) then
			---@cast check basic.Type
			if check.check(value) then
				return true
			end
			table.insert(typeList, check.name())
			
		elseif basic.TYPES.CALLABLE.check(check) then
			---@cast check funCheckError
			local ok, message = check(value)
			if ok then
				return true
			else
				if message ~= nil then
					table.insert(messageList, message)
				else
					rawCheck = true
				end
			end
		else
			basic.argerror('#checks[' .. icheck .. ']', argcheck_template:format('type/function', basic.stringify(check)))
		end
	end
	
	if message ~= nil then
		message = tostring(message)
				:gsub('%$%$', '<$>')
				:gsub('%$1', tostring(value))
				:gsub('<%$>', '$')
				
	else
		if #typeList > 0 then
			local typeMessage = table.concat(typeList, '/')
			table.insert(messageList, 1, typeMessage)
		end
		
		if rawCheck then
			table.insert(messageList, 'to pass validation')
		end
		
		local expected = table.concat(messageList, ' or ')
		message = argcheck_template:format(expected, basic.stringify(value))
	end
			
	return false, message
end

--------------------------------------------------------
--- Validate argument, throw error on missmatch
---@param argName any					# name of argument in error message
---@param checks argChecks				# validation conditions
---@param value any						# argument
---@param message? any					# message about what is wrong with argument. '$1' is a placeholder for the passed value
---@param level? integer				# error level (function in the stack to blame)
function basic.argcheck(argName, checks, value, message, level)
	if level == nil then
		level = 2
	end
	level = level + 1
	
	local ok, message = basic.validate(checks, value, message)
	if not ok then
		basic.argerror(argName, message, level)
	end
end

--------------------------------------------------------
---@class basic.args.params
---@field checks argChecks
---@field optional? boolean
---@field default? any
---@field multiple? boolean
---@field name? string
---@field message? string

--------------------------------------------------------
--- !!!args
---@param values Array<any>						# actual arguments
---@param signature Array<basic.args.params | argChecks>	# arguments signature
---@param level? integer						# error level (function in the stack to blame)
---@return any ...
function basic.args(values, signature, level)
	basic.argcheck('#1 (values)', basic.TYPES.MAP, values)
	basic.argcheck('#2 (params)', basic.TYPES.ARRAY, signature)
	basic.argcheck('#3 (level)', {basic.TYPES.INTEGER, basic.TYPES.NIL}, level)
	
	level = (level or 2) + 1
	
	---@class basic.args._output
	---@field ivalue integer
	---@field result Array<any>
	---@field next   basic.args._output?
	---@field prev   basic.args._output?
	
	---@type basic.args._output
	local firstOutput = {
		ivalue = 1,
		result = {},
	}
	
	local nvalues = 0
	for i in pairs(values) do
		if i > nvalues then
			nvalues = i
		end
	end
	
	local nparams = #signature
	
	-- process signature
	for iparam, params in ipairs(signature) do
		if basic.TYPES.CALLABLE.check(params)
		or basic.TYPES.TYPE.check(params)
		or basic.TYPES.ARRAY.check(params) then
			---@cast params argChecks
			params = {
				checks = params
			}
		end
		---@cast params basic.args.params
	
		-- iterate output variants (when ambigous case)
		local output = firstOutput ---@type basic.args._output
		while output do
			local multValues = {} ---@type Array<any>
			local multValueIndex = 1
			local found = false
		
			if params.multiple then
				output.result[iparam] = multValues
			end
			
			-- iterate matching values
			while true do
			
				-- new output variant, which will start matching from next param
				if params.multiple then
					if nparams ~= iparam and (found or params.optional) then
						---@type basic.args._output
						local newOutput = {
							ivalue = output.ivalue,
							result = copy(output.result),
						}
						newOutput.result[iparam] = copy(multValues)
						
						if output.prev then
							output.prev.next = newOutput
							newOutput.prev = output.prev
						else
							firstOutput = newOutput
						end
						output.prev = newOutput
						newOutput.next = output
					end
				end
			
				local value = values[output.ivalue]
				local matched = false
				local message ---@type string?
				
				-- default case
				if value == nil then
					if params.default ~= nil then
						value = params.default
						matched = true
					end
				end
				
				if not matched then
					-- match case
					matched, message = basic.validate(params.checks, value, params.message)
						
					-- missmatch case - try to skip check
					if not matched then
						-- some previous multiple values matched
						if found then
							break
						end
						
						-- argument is optional
						if params.optional then
							break
						end
					end
				end
				
				-- advance values on match
				if matched then
					if params.multiple then
						multValues[multValueIndex] = value
						multValueIndex = multValueIndex + 1
					else
						output.result[iparam] = value
					end
					
					found = true
					output.ivalue = output.ivalue + 1
					
					-- perform check again for multiple values processing
					if not params.multiple or output.ivalue > nvalues then
						break
					end
				
				-- remove output variant on missmatch
				else
					if output.next then
						output.next.prev = output.prev
					end					
					if output.prev then
						output.prev.next = output.next
					else
						firstOutput = output.next
					end
					
					-- raise error if no remaining output variants
					if firstOutput == nil then
						-- argument name in error
						local name = '#' .. output.ivalue
						if params.name ~= nil then
							name = name .. ' (' .. tostring(params.name) .. ')'
						end
						
						basic.argerror(name, message, level)
					end
					
					break
				end
			end
			
			output = output.next
		end
	end
	
	local output = firstOutput
	while output and output.next do
		output = output.next
	end
	
	---@cast output -?
	return basic.unpackFull(output.result)
end

--------------------------------------------------------
-- Works like in-built 'unpack', but considers max integer index as the last element, ignoring nil values in between.
-- Amout of returned values should not turn out too big (better below 500).
-- First index may be below 1, which appends nils to the start (idk for why).
----------------------------
-- Example 1. Difference with unpack
-- ```
-- local t = {1, nil, 3}
-- print(unpack(t))      --> 1    nil    3
-- print(unpackFull(t))  --> 1    nil    3
-- 
-- t[5] = 5
-- print(unpack(t))      --> 1
-- print(unpackFull(t))  --> 1    nil    3    nil    5
-- ```
-- 
-- Example 2. Array fix
-- ```
-- local t = {}
-- t[1] = nil
-- t[2] = nil
-- t[3] = 3
-- print(#t)                --> 0
-- t = {unpackFull(t)}
-- print(#t)                --> 3
-- ```
---@param values Array<any>
---@param first? integer
---@return any ...
function basic.unpackFull(values, first)
	basic.argcheck('#1 (values)', basic.TYPES.TABLE, values)
	if first == nil then
		first = 1
	else
		basic.argcheck('#2 (first)', basic.TYPES.INTEGER, first)
	end
	
	local max = 0
	for i in pairs(values) do
		if basic.TYPES.INTEGER.check(i) and i > max then
			max = i
		end
	end
	
	return unpack(values, first, max)
end

--------------------------------------------------------
--	$wrap( func, inputFormat, outputFormat ) -> wrapper
-- !!!

function wrap(func, inputFormat, outputFormat)
	if func == nil then
		func = function(...)
			return ...
		end
	end
	argcheck('#1', {types.CALLABLE, types.STRING}, func)
	
	
	return function(...)
		local input = {...}
		
		
		-- if input == nil and output == nil then
		-- 	return func
		-- end
		local output = {func(unpack(input))}
		
		return unpack(output)
	end
end

--------------------------------------------------------
-- $iterator
-- !!!

--------------------------------------------------------
--	$iter( func ) -> constructor
--		@func: pairs							-- pairs-like function used by iterator
--		@constructor: f( ...any ) -> iterator	-- iterator constructor
-- Convert pairs-like function to iterator constructor 
-- Calling constructor with passed arguments returns iterator (which will transfer these arguments to pairs-like function)
-- 
----------------------------
-- Example !!!

function iter(func)
	argcheck('#1 (func)', types.FUNCTION, func)
	
	return function(...)
		local arg = {...}
		
		---@class basic.Iterator
		local iterator = {}
		
		local meta = {
			type = metatype_iterator,
			__pairs = function()
				return func(unpack(arg))
			end,
		}
		setmetatable(iterator, meta)
		return iterator
	end
end

--------------------------------------------------------
--	$iarray( object, *?start, *?finish, ?step ) -> iterator
--		@object: table(array)		-- object to iterate
--		@start: int					-- index to start iteration from
--		@finish: int				-- index to finish iteration on
--		@step: int					-- advance of index on iteration step
-- Build ordered iterator over an array, including nil values
-- Start and finish indexes by default are set to the corresponding edge of the array.
-- If step is negative, iteration is performed backwards. In this case start index should be >= finish index.
-- 
----------------------------
-- Example. Difference with 'ipairs' !!!

-- iarray = iter(function(object, start, finish, step)
-- 	argcheck('#1 (object)', types.TABLE, object)
-- 	argcheck('#2 (start)', {types.NIL, types.INTEGER}, start)
-- 	argcheck('#3 (finish)', {types.NIL, types.INTEGER}, finish)
-- 	argcheck('#4 (step)', {types.NIL, types.INTEGER}, step)
-- 	if step == 0 then
-- 		argerror('#4 (step)', 'zero value')
-- 	end
	
-- 	step = step or 1
-- 	local len = #object
-- 	local positive = (step > 0)
	
-- 	if positive then
-- 		start = start or 1
-- 		finish = finish or len
-- 	else
-- 		start = start or len
-- 		finish = finish or 1
-- 	end

-- 	local i = start - step
	
-- 	return function()
-- 		i = i + step
-- 		if positive then
-- 			if i > finish then
-- 				return
-- 			end
-- 		else
-- 			if i < finish then
-- 				return
-- 			end
-- 		end		
-- 		return i, object[i]
-- 	end
-- end)

--------------------------------------------------------
--- Amount of elements in iterable
---@param iterable basic.Iterable
---@return integer
function basic.size(iterable)
	argcheck('#1 (iterable)', basic.TYPES.ITERABLE, iterable)
	local count = 0
	---@diagnostic disable-next-line: no-unknown
	for _ in pairs(iterable) do
		count = count + 1
	end
	return count
end

--------------------------------------------------------
--	$map( source, ?transform ) -> mapped
--		@source: iterable
--		@mapped: map
-- 		@transform( value, key, source ) -> newValue, ?newKey

map = {
}

local function _map(_, ...)
	local source, transform = args({
		checks		= { types.ITERABLE,	{types.FUNCTION, types.NIL},	},
		names		= { 'source',		'transform'						},
		values		= {...},
	})
	
	if not transform then
		transform = wrap()
	end
	
	local mapped = {}
	
	if types.ARRAY.check(source) then
		mapped = {unpack(source)}
		for i = 1, #source do
			local value, key = transform(source[i], i, source)
			if key == nil then
				key = i
			end
			if key ~= i then
				mapped[i] = nil
			end
			mapped[key] = value
		end
		
	else
		for key, value in pairs(source) do
			local newKey, newValue = transform(value, key, source)
			if newKey == nil then
				newKey = key
			end
			mapped[newKey] = newValue	
		end
	end
	
	return mapped
end

--------------------------------------------------------
--	$sift

sift = {
	naturalKeys = function(value, key)
		return types.NATURAL.check(key)
	end,
}

function _sift(_, source, check)
	argcheck('#2 (condition)', types.FUNCTION, check)
	argforward('#1 (source)')
	
	return map(
		source,
		function(value, ...)
			if check(value, ...) then
				return value
			end
		end
	)
end

--------------------------------------------------------
-- $filter(

filter = {
}

local function _filter(_, source)

end

setmetatable(filter, {__call = _filter})

--------------------------------------------------------
--	$fold( source,  ) -> 
--		@source: iterable
--		@add: f( currentFolded, nextValue, nextKey, source ) -> nextFolded

-- function fold(source, )
	
-- end

--------------------------------------------------------
--	$best( source, ?*worse, ?check ) -> value, key
--		@source: iterable									-- set of elements to find the best
--		@worse: f( lvalue, rvalue, lkey, rkey ) -> ok		-- comparator function, should return if left element worse (<) than right
--			@ok: any(boolean)
--		@check: f( value, key ) -> ok						-- filter function to skip inappropriate values
--			@ok: any(boolean)
-- !!!
-- By default finds max value, if 'worse' function is not passed. 
-- 
-- Have some predifined comparators:
--	$best.max			-- find max value
--	$best.min			-- find min value
--	$best.maxKey		-- find max numberic key
--	$best.minKey		-- find max numberic key
--
----------------------------
-- Example. !!!

best = {
	max = function(l, r)
		return l < r
	end,
	min = function(l, r)
		return l > r
	end,
	maxKey = function(_, _, lkey, rkey)
		return lkey < rkey
	end,
	minKey = function(_, _, lkey, rkey)
		return lkey > rkey
	end,
}

local function _best(_, source, worse, check)
	argcheck('#1 (source)', types.ITERABLE, source)
	argcheck('#2 (worse)', {types.FUNCTION, types.NIL}, worse)
	argcheck('#3 (check)', {types.FUNCTION, types.NIL}, check)
	if worse == nil then
		worse = best.max
	end
	
	local bestKey, bestValue
	for key, value in pairs(source) do
		if check == nil or check(value, key) then
			if key == nil then
				bestKey = key
				bestValue = value
			else
				if worse(bestValue, value, bestKey, key) then
					bestKey = key
					bestValue = value
				end
			end
		end
	end
	return bestValue, bestKey
end

setmetatable(best, {__call = _best})

--------------------------------------------------------
-- $maxIndex( source )
-- !!!

function maxIndex(source)
	local _, index = best(
		source,
		best.maxKey,
		sift.naturalKeys
	)
	return index
end


--------------------------------------------------------

return basic