local ffi = require("ffi")
local TST_WILDCARD = "*"
local TST_SEPARATOR = "/"
local TST_START_CAPACITY = 256
local TST_GROW_FACTOR = 2
local TST_MAX_KEY_LEN = 512
local TST_DUMP_SIZE = 40
local TST_FILE_HEADER = "TSTDB"

ffi.cdef[[
	typedef struct { uint8_t splitchar; uint8_t flag; uint32_t high; uint32_t low; uint32_t equal; } TSTNode;
]]

local function TSTDB(filename)

	local self = {}
	
	-- private variables
	
	local file, err, byte, key_count
	local node_count, size_of_node, wildcard_byte
	local buffer_pool, node_capacity, nodes, separator_byte

	-- private methods
	
	local function get_line_no(file, pos)
		file:seek("set", 0)
		local line_no = 1
		for line in file:lines() do
			if pos < file:seek() then
				break
			end
			line_no = line_no + 1
		end
		return line_no
	end


	local function get_segment(buffer, buf_len, callback, segment)
		local count, start = 1, 1
		for i = 1, buf_len - 1 do
			if buffer[i] == separator_byte then
				if count == segment then 
					callback(ffi.string(buffer + start, i - start)) 
					return
				end
				count = count + 1
				start = i + 1
			end
		end
		if count == segment then
			callback(ffi.string(buffer + start, buf_len - start))
		end
	end
	
	
	local function fetch_buffer()
		local buffer = buffer_pool[#buffer_pool]
		if not buffer then 
			return ffi.new("uint8_t[?]", TST_MAX_KEY_LEN) 
		end
		buffer_pool[#buffer_pool] = nil
		return buffer
	end
	
	
	local function release_buffer(buffer)
		buffer_pool[#buffer_pool + 1] = buffer
	end
	
		
	local function load_db(filename, tst)
		local file, err = io.open(filename, "r+")
		if not file then 
			-- file doesn't exist: create a new one
			file, err = io.open(filename, "w+")
			if not file then
				return nil, err
			end
			-- write header
			file:write(TST_FILE_HEADER, "\n")
			file:flush()	
		else 
			-- file exist: check header
			if file:read() ~= TST_FILE_HEADER then 	 
				file:close()
				return nil, "file '" .. filename .. "' is not a database file: header expected"
			end
			-- read file
			local key = TST_FILE_HEADER
			local pos = file:seek()
			local key_len, tab = file:read("*n", 1)
			while key_len and tab == "\t" do
				if key_len < 0 then
					key = file:read(-key_len)
					if not key or -key_len ~= #key then break end
					tst.remove(key)
				else
					key = file:read(key_len)
					if not key or key_len ~= #key then break end
					tst.put(key)
				end
				pos = file:seek()
				key_len, tab = file:read("*n", 1)
			end
			local cur_pos, end_pos = file:seek(), file:seek("end")
			if key_len or cur_pos ~= end_pos then 
				-- file is corrupt
				if cur_pos == end_pos and end_pos - pos < TST_MAX_KEY_LEN then
					-- only the last entry is damaged: clear and rewind to the last correct position
					file:seek("set", pos)
					file:write("\n", string.rep(" ", end_pos - pos - 2), "\n")
					file:flush()
					file:seek("set", pos + 1)
				else
					-- abort with a useful error message
					local line_no = get_line_no(file, cur_pos)
					file:close()
					local msg = "database file '" .. filename .. "' is corrupt at line " .. line_no
					if key then
						if byte(key, #key) == 10 then 
							key = string.sub(key, 1, #key - 1) 
						end 
						msg = msg .. " near '" .. string.sub(key, 1, 40) .. "'"
					end
					if key_len and tab ~= "\t" then
						msg = msg .. ": horizontal tab after key length expected"
					end
					return nil, msg 	 				
				end
			elseif pos == end_pos then
				file:write("\n")
			end
		end
		return file
	end
	
	
	local function init()
		byte = string.byte
		wildcard_byte = byte(TST_WILDCARD)
		separator_byte = byte(TST_SEPARATOR)
		buffer_pool = {}
		node_count, key_count = 1, 0
		node_capacity = TST_START_CAPACITY
		nodes = ffi.new("TSTNode[?]", node_capacity)
		size_of_node = ffi.sizeof("TSTNode")
		if filename then
			file, err = load_db(filename, self)
			if not file then return nil, err end
		end
		return self
	end
	
	
	local function grow()
		node_capacity = node_capacity * TST_GROW_FACTOR
		local tmp = ffi.new("TSTNode[?]", node_capacity)
		ffi.copy(tmp, nodes, node_count	* size_of_node)
		nodes = tmp	
	end
	
	
	local function traverse_desc(node, buffer, buf_index, callback)
		if node == nodes[0] then return end
		traverse_desc(nodes[node.high], buffer, buf_index, callback)
		buffer[buf_index] = node.splitchar
		traverse_desc(nodes[node.equal], buffer, buf_index + 1, callback)
		if node.flag == 1 then 
			callback(ffi.string(buffer, buf_index + 1)) 
		end
		traverse_desc(nodes[node.low], buffer, buf_index, callback)
	end


	local function traverse_wc(node, key, key_index, buffer, buf_index, callback, segment)
		if node == nodes[0] then return end
		local key_char = byte(key, key_index)
		local diff = key_char - node.splitchar
		local wildcard = key_char == wildcard_byte
		
		if diff < 0 or wildcard then
			traverse_wc(nodes[node.low], key, key_index, buffer, buf_index, callback, segment)
		end
		if diff == 0 or wildcard then	
			buffer[buf_index] = node.splitchar		
			if key_index < #key then
				traverse_wc(nodes[node.equal], key, key_index + 1, buffer, buf_index + 1, callback, segment)
			elseif node.flag == 1 then
				if callback == self.remove then
					node.flag = 0				
				elseif segment then
					get_segment(buffer, buf_index + 1, callback, segment)
				else	
					callback(ffi.string(buffer, buf_index + 1))
				end
			end
			if wildcard then
				traverse_wc(nodes[node.equal], key, key_index, buffer, buf_index + 1, callback, segment)
			end
		end
		if diff > 0 or wildcard then
			traverse_wc(nodes[node.high], key, key_index, buffer, buf_index, callback, segment)
		end		
	end
					
	-- public methods

	function self.get(key)
		local key_index, key_len, key_char = 1, #key, byte(key, 1)
		local node, root_node = nodes[1], nodes[0]			
		if not key_char then return false end

		repeat
			local diff = key_char - node.splitchar
			if diff > 0 then
				node = nodes[node.high]
			elseif diff < 0 then
				node = nodes[node.low]
			elseif key_index == key_len then
				if node.flag == 1 then return true end
				return false
			else
				node = nodes[node.equal]
				key_index = key_index + 1
				key_char = byte(key, key_index)
			end
		until node == root_node
		
		return false
	end

	
	function self.put(key, clear)
		local key_index, key_len, key_char = 1, #key, byte(key, 1)
		local node, root_node, prev_node, diff = nodes[1], nodes[0]		
		if not key_char or key_len > TST_MAX_KEY_LEN then return false end
		
		repeat
			prev_node = node
			diff = key_char - node.splitchar
			if diff > 0 then
				node = nodes[node.high]
			elseif diff < 0 then
				node = nodes[node.low]
			elseif key_index == key_len then
				if clear then
					if node.flag == 1 then 
						node.flag = 0
						key_count = key_count - 1 
						if file then
							file:write(-#key, "\t", key, "\n")	
							file:flush()	
						end
						return true						
					end
				elseif node.flag == 0 then 
					node.flag = 1
					key_count = key_count + 1 
					if file then
						file:write(#key, "\t", key, "\n")	
						file:flush()	
					end
					return true					
				end
				return false		
			else
				node = nodes[node.equal]
				key_index = key_index + 1
				key_char = byte(key, key_index)
			end
		until node == root_node
		
		if clear then return false end
		
		if diff > 0 then
			prev_node.high = node_count
		elseif diff < 0 then
			prev_node.low = node_count
		else 
			prev_node.equal = node_count
		end
		
		repeat
			if node_count == node_capacity then grow() end
			node = nodes[node_count]
			node.splitchar = byte(key, key_index)
			node.flag = 0
			node.high = 0
			node.low = 0
			node_count = node_count + 1
			node.equal = node_count
			key_index = key_index + 1
		until key_index > key_len
		
		node.flag = 1
		node.equal = 0
		key_count = key_count + 1
		if file then
			file:write(#key, "\t", key, "\n")	
			file:flush()	
		end
		return true
	end
	
	
	function self.remove(key)
		self.put(key, true)
	end
	
	
	function self.search(key, callback, segment)
		if #key > 0 then
			local buffer = fetch_buffer()
			traverse_wc(nodes[1], key, 1, buffer, 0, callback, segment)
			release_buffer(buffer)
		end
	end


	function self.keys(callback, desc)	
		if desc then
			local buffer = fetch_buffer()
			traverse_desc(nodes[1], buffer, 0, callback)	
			release_buffer(buffer)
		else
			self.search(TST_WILDCARD, callback)
		end	
	end
	
	
	function self.clear()
		ffi.fill(nodes, size_of_node * 2) 
		node_count = 1
		key_count = 0
		if file then
			file:close()
			assert(os.remove(filename))
			file = assert(load(filename, self))
		end
	end	
	
	
	function self.key_count()
		return key_count
	end	


	function self.node_count()
		return node_count - 1
	end	


	function self.node_capacity()
		return node_capacity
	end	


	function self.optimize()
		math.randomseed(os.time())
		local random = math.random
		local keys = {}
		self.keys(function(key) keys[#keys + 1] = key end)
		local len = #keys
		-- Fisher–Yates shuffle
		for i = 1, len - 1 do
			local tmp = keys[i]
			local j = random(i, len)
			keys[i] = keys[j]
			keys[j] = tmp
		end
		if file then
			file:close()
			file = nil
			assert(os.rename(filename, filename .. ".tmp"))
			self.clear()			
			file = assert(load(filename, self))
		else
			self.clear()
		end
		for i = 1, #keys do
			self.put(keys[i])
		end
		if file then
			os.remove(filename .. ".tmp")
		end
	end


	function self.dump()
		local write, char = io.write, string.char
		local count, splitchar = 0
		write("node\tchar\tlow\tequal\thigh\tflag\n")
		
		for i = 1, node_count - 1 do
			local node = nodes[i]
			splitchar = node.splitchar
			if splitchar > 31 and splitchar < 127 then 
				splitchar = "'" .. char(splitchar) .. "'"
			end
			write(i, "\t", splitchar, "\t", node.low, "\t", node.equal, "\t", node.high, "\t", node.flag, "\n")
			count = count + 1
			if count == TST_DUMP_SIZE then
				write("more? ")
				local b = byte(io.read(), 1)
				if b and b ~= 121 then break end
				count = 0 
			end
		end	
	end
	

	function self.state()
		if node_count == 0 then return 1 end
		local low, low_offset = 0, 0
		local high, high_offset = 0, 0
		for i = 1, node_count - 1 do
			local node = nodes[i]
			if node.low ~= 0 then 
				low = low + 1 
				low_offset = low_offset + node.low
			end
			if node.high ~= 0 then
				high = high + 1 
				high_offset = high_offset + node.high
			end			
		end
		local balance = 1 - (math.abs(low - high) / (low + high))
		local balance_offset = 1 - (math.abs(low_offset - high_offset) / (low_offset + high_offset))
		return (balance + balance_offset) / 2
	end
	
	
	function self.separator(new_separator)
		if new_separator then 
			separator_byte = byte(new_separator)
		end
		return string.char(separator_byte)
	end
		
		
	return init()
	
end

return TSTDB
