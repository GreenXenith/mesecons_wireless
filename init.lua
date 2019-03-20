--[[

	The MIT License (MIT)

	Copyright (C) 2019 GreenXenith/GreenDimond

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to
	deal in the Software without restriction, including without limitation the
	rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
	sell copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
	IN THE SOFTWARE.

]]--

local storage = minetest.get_mod_storage()
local range_max = 20
local connection_max = 100
local rules = {
	{x = 1, y = 0, z = 0},
	{x =-1, y = 0, z = 0},
	{x = 0, y = 1, z = 0},
	{x = 0, y =-1, z = 0},
	{x = 0, y = 0, z = 1},
	{x = 0, y = 0, z =-1},
}

local function hash(pos)
	return minetest.hash_node_position(pos)
end

local function dehash(hash)
	return minetest.get_position_from_hash(hash)
end

-- Run function on each position in channel
local function do_for_each(owner, channel, origin, func)
	-- Put data in table
	local data = minetest.deserialize(storage:get_string(owner..":"..channel))
	if not data then
		return
	end
	-- Get range
	local range = minetest.get_meta(origin):get_int("range")
	for pos in pairs(data) do
		pos = dehash(pos)
		if pos ~= origin then
			local dist = vector.distance(origin, pos)
			if dist <= range then
				func(pos, dist)
			end
		end
	end
end

-- Modify storage as table
local function storage_table(owner, channel, func)
	local t = minetest.deserialize(storage:get_string(owner..":"..channel)) or {}
	local set = func(t)
	if type(set) == "table" then
		set = minetest.serialize(set)
	end
	storage:set_string(owner..":"..channel, set)
end

-- Limit digiline actions to 20 per second
local function overheat(pos)
	local actions = minetest.get_meta(pos):get_int("actions")
	if actions >= 20 then
		local node = minetest.get_node(pos)
		-- Burnout
		if node.param2 ~= 192 then
			minetest.swap_node(pos, {name = node.name, param2 = 192})
		end
		return true, actions
	end
	return false, actions
end

-- Signal Transmitter
mesecon.register_node("mesecons_wireless:transmitter", {
	description = "Wireless Mesecon Transmitter",
	overlay_tiles = {
		"",
		"",
		{name = "mesecons_wireless_transmitter_signal.png"},
	},
	paramtype2 = "color",
	palette = "mesecons_wireless_signal_palette.png",
	sounds = default.node_sound_metal_defaults(),
	digiline = {
		effector = {
			action = function(pos, node, dchannel, msg)
				local meta = minetest.get_meta(pos)
				local owner = meta:get_string("owner")
				local channel = meta:get_string("channel")
				local overheated, actions = overheat(pos)
				if overheated then
					return
				end
				-- Signal indicator
				if node.param2 ~= 128 then
					minetest.swap_node(pos, {name = node.name, param2 = 128})
				end
				-- Increase action count
				meta:set_int("actions", actions + 1)
				do_for_each(owner, channel, pos, function(each)
					-- Relay signal
					digiline:receptor_send(each, digiline.rules.default, dchannel, msg)
					local enode = minetest.get_node(each)
					minetest.swap_node(each, {name = enode.name, param2 = 128})
				end)
			end
		}
	},
	on_timer = function(pos)
		-- Cooldown
		minetest.get_meta(pos):set_int("actions", 0)
		local node = minetest.get_node(pos)
		if node.param2 ~= minetest.registered_nodes[node.name].place_param2 then
			minetest.swap_node(pos, {name = node.name, param2 = minetest.registered_nodes[node.name].place_param2})
		end
		minetest.get_node_timer(pos):set(1, 0)
	end,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_int("range", 15)
		meta:set_string("formspec", "field[channel;Channel;${channel}]field[range;Range (1-"..range_max..");${range}")
		minetest.get_node_timer(pos):set(1, 0)
	end,
	on_destruct = function(pos)
		local meta = minetest.get_meta(pos)
		local owner = meta:get_string("owner")
		local channel = meta:get_string("channel")
		if channel and channel ~= "" then
			do_for_each(owner, channel, pos, function(each)
				minetest.swap_node(each, {name = "mesecons_wireless:receiver_off", param2 = 0})
				mesecon.receptor_off(each, rules)
			end)
		end
	end,
	after_place_node = function(pos, placer)
		minetest.get_meta(pos):set_string("owner", placer:get_player_name())
	end,
	on_receive_fields = function(pos, _, fields, player)
		local meta = minetest.get_meta(pos)
		local setter = player:get_player_name()
		local owner = meta:get_string("owner")
		local channel = meta:get_string("channel")

		-- Only owner can set
		if setter == owner then
			if fields.channel then
				meta:set_string("channel", fields.channel)
			end
			-- Make sure range is valid
			local newrange
			if fields.range then
				newrange = tonumber(fields.range)
			end
			if newrange and newrange >= 1 and newrange <= range_max then
				local current = meta:get_int("range")
				if minetest.get_node(pos).name ~= "mesecons_wireless:transmitter_on" then
					meta:set_int("range", newrange)
					return
				end
				-- Turn off receivers outside smaller range
				if current and current ~= 0 then
					if current > newrange then
						do_for_each(owner, channel, pos, function(each, dist)
							if dist > newrange then
								minetest.swap_node(each, {name = "mesecons_wireless:receiver_off", param2 = 0})
								mesecon.receptor_off(each, rules)
							end
						end)
					end
				end
				meta:set_int("range", newrange)
				-- Turn on new receivers
				do_for_each(owner, channel, pos, function(each)
					local name = minetest.get_node(each).name
					if name == "mesecons_wireless:receiver_on" then
						return
					end
					minetest.swap_node(each, {name = "mesecons_wireless:receiver_on", param2 = 64})
					mesecon.receptor_on(each, rules)
				end)
			end
		end
	end,
	},
	{
		tiles = {
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_transmitter_off.png", color = "white"}
		},
		color = 0,
		place_param2 = 0,
		groups = {cracky=1},
		mesecons = {
			effector = {
				action_on = function(pos)
					local overheated, actions = overheat(pos)
					if overheated then
						return
					end
					minetest.swap_node(pos, {name = "mesecons_wireless:transmitter_on", param2 = 64})
					local meta = minetest.get_meta(pos)
					local owner = meta:get_string("owner")
					local channel = meta:get_string("channel")
					-- Higher action value
					meta:set_int("actions", actions + 5)
					do_for_each(owner, channel, pos, function(each)
						minetest.swap_node(each, {name = "mesecons_wireless:receiver_on", param2 = 64})
						mesecon.receptor_on(each, rules)
					end)
				end
			},
		},
	},
	{
		tiles = {
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_transmitter_on.png", color = "white"}
		},
		color = 64,
		place_param2 = 64,
		paramtype = "light",
		light_source = 2,
		groups = {cracky=1, not_in_creative_inventory=1},
		mesecons = {
			effector = {
				action_off = function(pos)
					minetest.swap_node(pos, {name = "mesecons_wireless:transmitter_off", param2 = 0})
					local meta = minetest.get_meta(pos)
					local owner = meta:get_string("owner")
					local channel = meta:get_string("channel")
					do_for_each(owner, channel, pos, function(each)
						minetest.swap_node(each, {name = "mesecons_wireless:receiver_off", param2 = 0})
						mesecon.receptor_off(each, rules)
					end)
				end
			},
		},
	}
)

mesecon.register_node("mesecons_wireless:receiver", {
	description = "Wireless Mesecon Receiver",
	overlay_tiles = {
		"",
		"",
		{name = "mesecons_wireless_receiver_signal.png"},
	},
	paramtype2 = "color",
	palette = "mesecons_wireless_signal_palette.png",
	sounds = default.node_sound_metal_defaults(),
	digiline = {
		receptor = {},
	},
	on_timer = function(pos)
		-- Handle signal indicator
		local node = minetest.get_node(pos)
		if node.param2 ~= minetest.registered_nodes[node.name].place_param2 then
			minetest.swap_node(pos, {name = node.name, param2 = minetest.registered_nodes[node.name].place_param2})
		end
		minetest.get_node_timer(pos):set(1, 0)
	end,
	on_construct = function(pos)
		minetest.get_meta(pos):set_string("formspec", "field[channel;Channel;${channel}]")
		minetest.get_node_timer(pos):set(1, 0)
	end,
	on_destruct = function(pos)
		local meta = minetest.get_meta(pos)
		local owner = meta:get_string("owner")
		local channel = meta:get_string("channel")
		if channel and channel ~= "" then
			storage_table(owner, channel, function(data)
				data[hash(pos)] = nil
				if not next(data) then
					return ""
				end
				return data
			end)
		end
	end,
	after_place_node = function(pos, placer)
		minetest.get_meta(pos):set_string("owner", placer:get_player_name())
	end,
	on_receive_fields = function(pos, _, fields, player)
		local meta = minetest.get_meta(pos)
		local setter = player:get_player_name()
		local owner = meta:get_string("owner")

		if setter == owner then
			if not fields.channel then
				return
			end
			-- Add to network if network < 100
			local t = minetest.deserialize(storage:get_string(owner..":"..fields.channel))
			if t then
				local connections = 0
				for c in pairs(t) do
					connections = connections + 1
				end
				if connections >= connection_max then
					return
				end
			end
			local current = meta:get_string("channel")
			if current and current ~= "" and current ~= fields.channel then
				storage_table(owner, current, function(data)
					data[hash(pos)] = nil
					if not next(data) then
						return ""
					end
					return data
				end)
			end
			meta:set_string("channel", fields.channel)
			if fields.channel == "" then
				return
			end
			storage_table(owner, fields.channel, function(data)
				data[hash(pos)] = 0
				return data
			end)
		end
	end,
	},
	{
		tiles = {
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_receiver_off.png", color = "white"},
		},
		color = 0,
		place_param2 = 0,
		groups = {cracky=1},
		mesecons = {
			receptor = {
				state = mesecon.state.off,
				rules = rules
			}
		},
	},
	{
		tiles = {
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_metal.png", color = "white"},
			{name = "mesecons_wireless_receiver_on.png", color = "white"},
		},
		color = 64,
		place_param2 = 64,
		paramtype = "light",
		light_source = 2,
		groups = {cracky=1, not_in_creative_inventory=1},
		mesecons = {
			receptor = {
				state = mesecon.state.on,
				rules = rules
			}
		},
	}
)

-- Start timers
minetest.register_lbm({
	label = "Refresh Wireless Transmitters",
	name = "mesecons_wireless:clear_actions",
	nodenames = {
		"mesecons_wireless:transmitter_on",
		"mesecons_wireless:transmitter_off",
		"mesecons_wireless:receiver_on",
		"mesecons_wireless:receiver_off",
	},
	run_at_every_load = true,
	action = function(pos)
		minetest.get_node_timer(pos):set(1, 0)
	end,
})

-- Crafting
minetest.register_craftitem("mesecons_wireless:antenna", {
	description = "Antenna",
	inventory_image = "mesecons_wireless_antenna.png",
})

minetest.register_craftitem("mesecons_wireless:dish", {
	description = "Radio Dish",
	inventory_image = "mesecons_wireless_dish.png",
})

minetest.register_craft({
	output = "mesecons_wireless:antenna",
	recipe = {
		{"default:steel_ingot"},
		{"default:steel_ingot"},
		{"mesecons_materials:fiber"}
	}
})

minetest.register_craft({
	output = "mesecons_wireless:dish",
	recipe = {
		{"", "", "default:steel_ingot"},
		{"", "default:steel_ingot", "default:steel_ingot"},
		{"default:steel_ingot", "default:steel_ingot", "mesecons_materials:fiber"}
	}
})

minetest.register_craft({
	output = "mesecons_wireless:dish",
	recipe = {
		{"default:steel_ingot", "", ""},
		{"default:steel_ingot", "default:steel_ingot", ""},
		{"mesecons_materials:fiber", "default:steel_ingot", "default:steel_ingot"}
	}
})

local wire = "mesecons:wire_00000000_off"
if minetest.get_modpath("digilines") then
	wire = "digilines:wire_std_00000000"
end

minetest.register_craft({
	output = "mesecons_wireless:transmitter_off",
	recipe = {
		{"", "mesecons_wireless:antenna", ""},
		{"default:steel_ingot", "default:diamond", "default:steel_ingot"},
		{"mesecons:wire_00000000_off", "mesecons_luacontroller:luacontroller0000", wire}
	}
})

minetest.register_craft({
	output = "mesecons_wireless:receiver_off",
	recipe = {
		{"", "mesecons_wireless:dish", ""},
		{"default:steel_ingot", "default:diamond", "default:steel_ingot"},
		{"mesecons:wire_00000000_off", "mesecons_luacontroller:luacontroller0000", wire}
	}
})
