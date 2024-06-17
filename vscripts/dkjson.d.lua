---@meta

---@alias json.state.exception.reason "reference cycle" | "custom encoder failed" | "unsupported type"
---@alias json.state.exception fun(reason: json.state.exception.reason, value: any, state: json.state, defaultmessage: string): nil | true | string, string?

---@class json.state
---@field indent boolean					# When `indent` (a boolean) is set, the created string will contain newlines and indentations. Otherwise it will be one long line.
---@field level integer						# This is the initial level of indentation used when `indent` is set. For each level two spaces are added. When absent it is set to 0.
---@field keyorder string[]					# `keyorder` is an array to specify the ordering of keys in the encoded output. If an object has keys which are not in this array they are written after the sorted keys.
---@field buffer string[]					# `buffer` is an array to store the strings for the result so they can be concatenated at once. When it isn't given, the encode function will create it temporary and will return the concatenated result.
---@field bufferlen integer					# When `bufferlen` is set, it has to be the index of the last element of `buffer`.
---@field tables table<table, true>			# `tables` is a set to detect reference cycles. It is created temporary when absent. Every table that is currently processed is used as key, the value is `true`.
---@field exception json.state.exception	# When `exception` is given, it will be called whenever the encoder cannot encode a given value. <br> The parameters are `reason`, `value`, `state` and `defaultmessage`. `reason` is either `"reference cycle"`, `"custom encoder failed"` or `"unsupported type"`. `value` is the original value that caused the exception, `state` is this state table, `defaultmessage` is the message of the error that would usually be raised. <br> You can either return `true` and add directly to the buffer or you can return the string directly. To keep raising an error return `nil` and the desired error message. An example implementation for an exception function is given in `json.encodeexception`.

-----------------------------------------------

--- Create a string representing the object. `Object` can be a table, a string, a number, a boolean, `nil`, `json.null` or any object with a function `__tojson` in its metatable. A table can only use strings and numbers as keys and its values have to be valid objects as well. It raises an error for any invalid data types or reference cycles.
---
--- When `state.buffer` was set, the return value will be `true` on success. Without `state.buffer` the return value will be a string.
---
-------------------------
--- ```
--- <metatable>.__jsonorder
--- ```
--- `__jsonorder` can overwrite the `keyorder` for a specific table.
---
-------------------------
--- ```
--- <metatable>.__jsontype
--- ````
--- `__jsontype` can be either `"array"` or `"object"`. This value is only checked for empty tables. (The default for empty tables is `"array"`).
---
-------------------------
--- ```
--- <metatable>.__tojson (self, state)
--- ```
--- You can provide your own `__tojson` function in a metatable. In this function you can either add directly to the buffer and return true, or you can return a string. On errors nil and a message should be returned.
---@param object any
---@param state? json.state
---@return string
function json.encode(object, state) end

-----------------------------------------------

--- Decode `string` starting at `position` or at 1 if `position` was omitted. <br> `null` is an optional value to be returned for null values. The default is `nil`, but you could set it to `json.null` or any other value.
---
--- The return values are the object or `nil`, the position of the next character that doesn't belong to the object, and in case of errors an error message.
---
--- Two metatables are created. Every array or object that is decoded gets a metatable with the `__jsontype` field set to either `array` or `object`. If you want to provide your own metatables use the syntax
--- ```
--- json.decode (string, position, null, objectmeta, arraymeta)
--- ```
--- To prevent the assigning of metatables pass `nil`:
--- ```
--- json.decode (string, position, null, nil)
--- ```
---@param string string
---@param position? integer
---@param null? any
---@param objectmeta? any
---@param arraymeta? any
---@return any, integer, string?
function json.decode(string, position, null, objectmeta, arraymeta) end

-----------------------------------------------

--- You can use this value for setting explicit `null` values.
---@type any
json.null = nil

-----------------------------------------------

--- Set to `"dkjson 2.5"`.
---@type string
json.version = nil

-----------------------------------------------

--- Quote a UTF-8 string and escape critical characters using JSON
--- escape sequences. This function is only necessary when you build
--- your own `__tojson` functions.
---@param string string
---@return string
function json.quotestring(string) end

-----------------------------------------------

--- When `state.indent` is set, add a newline to `state.buffer` and spaces
--- according to `state.level`.
---@param state json.state
function json.addnewline(state) end

-----------------------------------------------

--- This function can be used as value to the `exception` option. Instead of
--- raising an error this function encodes the error message as a string. This
--- can help to debug malformed input data.
---
---	x = json.encode(value, { exception = json.encodeexception })```
---@param reason json.state.exception.reason
---@param value any
---@param state json.state
---@param defaultmessage string
function json.encodeexception(reason, value, state, defaultmessage) end