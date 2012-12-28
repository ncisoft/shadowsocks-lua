local socket = require("socket")
local string = require("string")
local table = require("table")
local os = os
local ipairs = ipairs
local assert = assert
local print = print
local type = type
local tostring = tostring
local base = _G
local ffi = (package.loaded.jit ~= nil and package.loaded.bit ~= nil and require("ffi")) or nil
local mdm = package.loaded.mdm

if ffi ~= nil then			-- smart load ffi
	ffi.cdef[[
	typedef unsigned char uchar_t;
	]]
end

module("socket_tunnel")

local metat = { __index = {}, listen_ip = nil, listen_port = nil, remote_ip = nil, remote_port = nil }

MTU_SIZE = 20480

local listen_sock
local remote_sock
local accept_fds = {}
local connect_fds = {}
local read_sock_set =  {}
local write_sock_set = {}
local pair_fd_map = {}		-- "local_port:remote_ip:remote_port" --> fd_info object
local self_fd_map = {}		-- socket object --> fd_info object
							-- fd_info object = { sock, local_port, accepted_ip?, accepted_port?, last_timestamp, queued_data[] }

local function __trans2args(str, i, n, trans_table)
	if (i==n) then return trans_table[ str:byte(i) + 1 ] end
	return trans_table[ str:byte(i) + 1 ], __trans2args(str, i+1, n, trans_table)
end

local function __translate_lua(str, trans_table)
	if (str == nil) then return nil end
	if (str:len() == 0) then return str end
	return string.char( __trans2args(str, 1, str:len(), trans_table ) )
end

local function __translate_jit(str, trans_table)
	local n = str:len()
	local buf = ffi.new("unsigned char[?]", n)
	local buflen = ffi.new("size_t[1]", n)
	for i=1, n do
		buf[i-1] = trans_table[ string.byte(str,i) + 1]
	end
	return ffi.string(buf, buflen[0])
end

local __trans_map = {}

local function __translate_dll(str, tbl)
	local trans = __trans_map[ tbl ]
	if (trans == nil) then
		trans = ""
		for _,v in ipairs(tbl) do
			trans = trans .. string.char(v)
		end
		__trans_map[ tbl ] = trans
	end
	mdm.str_translate(str, trans)
end

__translate_funcs = { lua = __translate_lua, jit = __translate_jit, dll = __translate_dll }

-- loading order: (1) ffi; (2) dll; (3) pure lua
__translate = (ffi ~= nil and __translate_jit) or (mdm ~= nil and __translate_dll) or __translate_lua

local function new_remote_udp_sock(remote_ip, remote_port)
	local remote_sock = socket.udp()
	assert( remote_sock:setsockname("*", 0) )
	assert( remote_sock:setpeername(remote_ip, remote_port) )
	assert( remote_sock:settimeout(0) )
	return remote_sock;
end

local function new_accepted_udp_sock(listen_sock, remote_ip, remote_port)
	local sock = socket.udp()
	local listen_ip, listen_port = listen_sock:getsockname()
	print("listen_ip="..listen_ip..", listen_port="..listen_port)
	assert( sock:setsockname( listen_ip, listen_port ) )
	assert( sock:setpeername( remote_ip, remote_port ) )
	assert( sock:settimeout(0) )
	return sock
end

local function gen_key(local_port, remote_ip, remote_port)
	return local_port..':'..remote_ip..':'..remote_port
end

function new_udp_tunnel(listen_ip, listen_port, remote_ip, remote_port)
	metat.listen_ip = listen_ip
	metat.listen_port = listen_port
	metat.remote_ip = remote_ip
	metat.remote_port = remote_port

	local listen_sock = socket.udp()
	assert( listen_sock:setsockname(listen_ip, listen_port) )
	assert( listen_sock:settimeout(0) )

	local fd = {}
	fd.sock = listen_sock
	fd.local_port = assert( listen_port )
	fd.last_timestamp = os.time
	fd.is_listen = true
	fd.queued_data = {}
	self_fd_map[ listen_sock ] = fd

	table.insert(read_sock_set, listen_sock)
	table.insert(write_sock_set, listen_sock)
end

function loop_udp_tunnel(outgoing_trans_table, incoming_trans_table)

	while true do
		local is_active = false
		local rsocks, wsocks, _ = socket.select(read_sock_set, write_sock_set, 0.5)

		-- step(1): do read file descriptions, read fdset = { listen_sock, connected_sock... }
		for i, cur_sock in ipairs(rsocks) do
			local cur_fd = self_fd_map[ cur_sock ]
			local data, from_ip, from_port

			if (cur_fd.is_listen) then
				data, from_ip, from_port = cur_sock:receivefrom( MTU_SIZE )
			else
				data = cur_sock:receive( MTU_SIZE )
				from_ip, from_port = cur_sock:getpeername()
			end

			if (data) then
				local key = gen_key(cur_fd.local_port, from_ip, from_port)
				local pair_fd = pair_fd_map[ key ]
				is_active = true
				if (pair_fd == nil) then
					-- create connected_socket to upstream
					local fd = {}
					local sock = new_remote_udp_sock(metat.remote_ip, metat.remote_port)
					fd.sock = sock
					_, fd.local_port = sock:getsockname()
					fd.last_timestamp = os.time
					fd.queued_data = {}
					-- append to fdset.read and fdset.write both
					table.insert(read_sock_set, sock)
					table.insert(write_sock_set, sock)
					pair_fd_map[ key ] = fd 
					self_fd_map[ sock ] = fd			-- used to: lookup(accepted_sock) to connected_sock
					pair_fd = fd
					-- reversed bind acccepted sock
					fd = {}
					fd.sock = cur_sock
					_, fd.local_port = sock:getsockname()
					fd.from_ip = from_ip
					fd.from_port = from_port
					fd.last_timestamp = os.time
					fd.queued_data = {}
					key = gen_key(fd.local_port, metat.remote_ip, metat.remote_port)
					pair_fd_map[ key ] = fd			-- used to: lookup(connected_sock) to accepted_sock
				end
				print(cur_sock)
				print("\tremote_ip="..from_ip..", remote_port="..from_port..", queued_data.getn="..#cur_fd.queued_data)
				if (pair_fd.from_ip == nil) then
					-- pair is connected_sock, current is accepted_sock, direction is [outgoing]
					table.insert(pair_fd.queued_data, __translate(data, outgoing_trans_table))
					print("\t[accepted_sock.recv] will relay to remote, " ..data:len() .." bytes")
				else
					-- pair is fake listened_sock, current is connected_sock, direction is [incoming]
					local fd = self_fd_map[ pair_fd.sock ]
					table.insert(fd.queued_data, { from_ip = pair_fd.from_ip, from_port = pair_fd.from_port, data=__translate(data, incoming_trans_table) })
					print("\t[connected_sock.recv] will relay to local client, " ..data:len() .." bytes")
				end
			end
		end 

		-- step(2): do write file descriptions, write fdset = { connected_sock..., accepted_sock... }
		for i,cur_sock in ipairs(wsocks) do
			local self_fd = self_fd_map[ cur_sock ]
			if (self_fd ~= nil and #self_fd.queued_data > 0) then
				local data = self_fd.queued_data[1]
				print("\t####\t"..tostring(cur_sock))
				if (type(data) == "table") then
					-- it's listen_sock, direction is [incoming]
					print("\tsendto_ip="..data.from_ip..", sendto_port="..data.from_port..", #queued_data="..#self_fd.queued_data)
					print("\t[listen_sock.send] reply to local client, " ..data.data:len() .." bytes")
					if (cur_sock:sendto(data.data, data.from_ip, data.from_port) ~= nil) then
						table.remove(self_fd.queued_data, 1)
					end
				else
					-- it's connected_sock, direction is [outgoing]
					if (cur_sock:send(data) ~= nil) then
						table.remove(self_fd.queued_data, 1)
					end
					print("\tsend.." ..data:len() .." bytes")
					print("\t[connected_sock.sent] relay to remote")
				end
				self_fd.last_timestamp = os.time
				is_active = true
			end
		end

		-- step(3): cleanup
		if (not is_active) then socket.sleep(0.01) end
	end
end
