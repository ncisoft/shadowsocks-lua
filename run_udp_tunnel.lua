#!/usr/bin/env lua

require "socket_tunnel"
require("socket")
require("alt_getopt")

local trans_table = require("encrypt_table")
local listen_ip, listen_port, remote_ip, remote_port, upstream_ip, upstream_port, mode

local function print_usage_then_exit()
	print("Usage: run_udp_tunnel [OPTION]...\n")
	print("  -l,  --local_ip=IP             local listen ipv4 address, default: 0.0.0.0 (OPTIONAL)")
	print("  -L,  --local_port=port         local listen port")
	print("  -r,  --remote_ip=IP            remote listen ipv4 address")
	print("  -R,  --remote_port=port        remote listen port")
	print("  -u,  --upstream_ip=IP          upstream listen ipv4 address")
	print("  -U,  --upstream_port=port      upstream listen port")
	print("  -m,  --mode=MODE               mode = local | remote")
	print("                                 local mode: local_port remote_ip remote_port is mandatory")
	print("                                 remote mode: remote_port upstream_ip upstream_port is mandatory")
	print("  -h,  --help                    display this help")
	print("")
	print("Examples:  run_udp_tunnel.lua --local_port 1194 --remote_ip 50.19.48.202 --remote_port 7070 --mode=local")
	print("           run_udp_tunnel.lua --remote_port 7070 --upstream_ip 10.117.54.127 --upstream_port 1194 --mode=remote")
	os.exit(1)
end

local function init_opts()
	local long_opts = {
		help			= "h",
		local_ip		= "l",
		local_port  	= "L",
		remote_ip   	= "r",
		remote_port 	= "R",
		upstream_ip 	= "u",
		upstream_port	= "U",
		mode        	= "m"
	}
	local optarg, optbind = alt_getopt.get_opts(arg, "ho:l:L:r:R:u:U:m:", long_opts)

	for k,v in pairs(optarg) do
		if k == "h" then
			print_usage_then_exit()
		elseif k == "l" then
			local_ip = v
		elseif k == "L" then
			local_port = v
		elseif k == "r" then
			remote_ip = v
		elseif k == "R" then
			remote_port = v
		elseif k == "u" then
			upstream_ip = v
		elseif k == "U" then
			upstream_port = v
		elseif k == "m" then
			if "local" == v or "remote" == v then
				mode = v
			end
		end
	end
	if "local" ~= mode and "remote" ~= mode then
		print_usage_then_exit()
	end
	if "local" == mode and (local_port == nil or remote_ip == nil or remote_port == nil) then
		print_usage_then_exit()
	end
	if "remote" == mode and (remote_port == nil or upstream_ip == nil or upstream_port == nil) then
		print_usage_then_exit()
	end
end

init_opts()


if "local" == mode then
	local_ip = local_ip or "*"
	socket_tunnel.new_udp_tunnel(local_ip, local_port, remote_ip, remote_port)
	-- socket_tunnel.new_udp_tunnel("*", 1194, "50.19.48.202", 7070)
	socket_tunnel.loop_udp_tunnel(trans_table.local_outgoing, trans_table.local_incoming)
else -- remote
	remote_ip = remote_ip or "*"
	socket_tunnel.new_udp_tunnel(remote_ip, remote_port, upstream_ip, upstream_port)
	-- socket_tunnel.new_udp_tunnel("*", 1194, "50.19.48.202", 7070)
	socket_tunnel.loop_udp_tunnel(trans_table.remote_outgoing, trans_table.remote_incoming)
end
