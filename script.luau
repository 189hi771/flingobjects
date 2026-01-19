local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local plr = Players.LocalPlayer
local mouse = plr:GetMouse()
local cam = Workspace.CurrentCamera

local char = plr.Character or plr.CharacterAdded:Wait()
-- forcing first person cause it looks better for this
plr.CameraMode = Enum.CameraMode.LockFirstPerson

-- bunch of settings
local config = {
	reach = 65, -- max distance
	min_dist = 5, -- cant pull closer than this
	-- throw settings
	base_throw_power = 100,
	max_throw_power = 800,
	charge_rate = 15, -- how fast throw power goes up
	-- movement feel
	lerp_speed = 0.25, -- lower = laggy/heavy feel
	rotation_speed = 2.5, -- how fast R and T spin it
	-- wobble effect (makes it look unstable)
	wobble_amount = 0.05,
	wobble_speed = 10,

	-- color
	col_norm = Color3.fromRGB(255, 255, 255),
	col_grab = Color3.fromRGB(0, 255, 100),
	col_charge = Color3.fromRGB(255, 50, 50)
}

-- global variables
local holding = false
local target_part = nil
local current_dist = 15
local current_rot = CFrame.identity
local grab_offset = CFrame.identity -- where we grabbed the part relative to center

-- charge mechanics
local is_charging = false
local current_charge = 0

-- auto spin mode
local auto_spin = false
local spin_axis = 0

-- selection box
local highlight = Instance.new("SelectionBox")
highlight.Name = "GrabHighlight"
highlight.LineThickness = 0.05
highlight.Parent = plr:WaitForChild("PlayerGui")

-- ignore list for rays
local function get_ignored_stuff()
	local ignore = {char}
	-- add the current part if we holding one
	if target_part then
		table.insert(ignore, target_part)
	end
	return ignore
end

-- the raycaster
local function shoot_ray()
	local mouse_pos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mouse_pos.X, mouse_pos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = get_ignored_stuff()

	-- do the raycast
	local result = Workspace:Raycast(ray.Origin, ray.Direction * config.reach, params)
	return result
end

-- logic to grab the thing
local function attempt_grab()
	if holding then return end -- already got something

	local res = shoot_ray()

	if res and res.Instance then
		local hit_part = res.Instance

		if hit_part.Locked then return end -- cant touch locked stuff
		if hit_part:IsA("Terrain") then return end -- dont grab the floor

		local clone = hit_part:Clone()
		clone.Parent = Workspace
		clone.CFrame = hit_part.CFrame
		clone.Name = "ClonedPhysicsPart"

		-- delete the original
		hit_part:Destroy()

		-- setup the clone
		clone.Anchored = true
		clone.CanCollide = false
		clone.Massless = true
		clone.CastShadow = false -- unnecessary lag fix

		-- clear velocity
		clone.AssemblyLinearVelocity = Vector3.zero
		clone.AssemblyAngularVelocity = Vector3.zero

		-- save state
		holding = true
		target_part = clone
		current_dist = (cam.CFrame.Position - clone.Position).Magnitude
		current_rot = clone.CFrame.Rotation

		-- calculate offset so part doesnt snap to center
		-- this makes it so if u grab the corner, u hold the corner
		grab_offset = CFrame.lookAt(cam.CFrame.Position, clone.Position):Inverse() * clone.CFrame

		-- update visuals
		highlight.Adornee = clone
		print("grabbed " .. clone.Name)
	end
end

-- drop or throw logic
local function release_object(do_throw)
	if not holding or not target_part then return end

	local p = target_part

	-- reset properties
	p.CanCollide = true
	p.Massless = false
	p.CastShadow = true

	-- the unanchor
	p.Anchored = false

	if do_throw then
		-- delay needed for physics engine wake up
		task.spawn(function()
			RunService.Heartbeat:Wait()

			if p and p.Parent then
				local dir = cam.CFrame.LookVector

				-- calculate total power
				local final_power = config.base_throw_power + current_charge

				-- yeet
				p.AssemblyLinearVelocity = dir * final_power

				-- add spin based on power
				local rot_power = final_power / 20
				p.AssemblyAngularVelocity = Vector3.new(
					math.random(-rot_power, rot_power),
					math.random(-rot_power, rot_power),
					math.random(-rot_power, rot_power)
				)
			end
		end)
	else
		-- drop logic
		-- kill momentum so it falls straight
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end

	-- reset all variables
	holding = false
	target_part = nil
	highlight.Adornee = nil
	is_charging = false
	current_charge = 0
	auto_spin = false
end

-- input management
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- left click
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		attempt_grab()

		-- F key (charge / throw)
	elseif input.KeyCode == Enum.KeyCode.F then
		if holding then
			is_charging = true
		end

		-- R key (rotate Y)
	elseif input.KeyCode == Enum.KeyCode.R then
		if holding then
			local r = CFrame.Angles(0, math.rad(45), 0)
			current_rot = current_rot * r
		end

		-- T key (rotate X)
	elseif input.KeyCode == Enum.KeyCode.T then
		if holding then
			local r = CFrame.Angles(math.rad(45), 0, 0)
			current_rot = current_rot * r
		end

		-- Q key (toggle auto spin)
	elseif input.KeyCode == Enum.KeyCode.Q then
		if holding then
			auto_spin = not auto_spin
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- release click = drop
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		release_object(false)

		-- release F = throw
	elseif input.KeyCode == Enum.KeyCode.F then
		if holding and is_charging then
			release_object(true)
		end
		is_charging = false
	end
end)

-- mouse wheel
UserInputService.InputChanged:Connect(function(input, gp)
	if not gp and input.UserInputType == Enum.UserInputType.MouseWheel then
		if holding then
			local delta = input.Position.Z
			current_dist = current_dist - (delta * 2)

			-- clamp check
			if current_dist < config.min_dist then 
				current_dist = config.min_dist 
			end
			if current_dist > config.reach then 
				current_dist = config.reach 
			end
		end
	end
end)

-- MAIN LOOP
-- this runs every single frame
RunService.RenderStepped:Connect(function(dt)

	-- 1. IF NOT HOLDING
	if not holding then
		local r = shoot_ray()

		if r and r.Instance then
			-- check if we can grab it
			if not r.Instance.Locked and not r.Instance.Anchored then
				highlight.Adornee = r.Instance
				highlight.Color3 = config.col_norm
				mouse.Icon = "rbxasset://textures/Cursors/Gamepad/Pointer.png"
			else
				highlight.Adornee = nil
				mouse.Icon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
			end
		else
			highlight.Adornee = nil
			mouse.Icon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
		end
		return
	end

	-- safety check
	if not target_part or not target_part.Parent then
		-- part got deleted or fell into void
		holding = false
		target_part = nil
		highlight.Adornee = nil
		return
	end

	-- charge logic
	if is_charging then
		-- ramp up power
		current_charge = current_charge + config.charge_rate
		if current_charge > config.max_throw_power then
			current_charge = config.max_throw_power
		end

		-- make box red
		highlight.Color3 = config.col_charge

		-- shake cam a bit for effect
		local shake = Vector3.new(math.random()-0.5, math.random()-0.5, 0) * 0.05
		cam.CFrame = cam.CFrame * CFrame.new(shake)
	else
		highlight.Color3 = config.col_grab
	end

	-- auto spin 
	if auto_spin then
		spin_axis = spin_axis + (dt * 5)
		local spin_rot = CFrame.Angles(0, spin_axis, 0)
		-- mix it with current rotation
		current_rot = current_rot * CFrame.Angles(0, dt, 0)
	end

	-- pos calculation
	local cf = cam.CFrame

	-- where we want the part to be
	local target_pos = cf.Position + (cf.LookVector * current_dist)

	-- wall collision checks
	-- shoot ray from face to target pos
	local wall_ray_origin = cf.Position
	local wall_ray_dir = (target_pos - wall_ray_origin)

	local wall_params = RaycastParams.new()
	wall_params.FilterType = Enum.RaycastFilterType.Exclude
	wall_params.FilterDescendantsInstances = {char, target_part}

	local wall_hit = Workspace:Raycast(wall_ray_origin, wall_ray_dir, wall_params)

	if wall_hit then
		-- if hit wall, pull part closer
		target_pos = wall_hit.Position
	end

	-- wobble calculation
	-- adds noise to position so it doesnt look frozen
	local time_now = tick()
	local noise_x = math.sin(time_now * config.wobble_speed) * config.wobble_amount
	local noise_y = math.cos(time_now * config.wobble_speed) * config.wobble_amount
	local wobble_vec = Vector3.new(noise_x, noise_y, 0)

	-- apply wobble only if heavy/far (optional detail)
	target_pos = target_pos + wobble_vec

	-- final cframe
	local look_rotation = CFrame.lookAt(Vector3.zero, cf.LookVector)

	-- combine everything
	local goal_cframe = CFrame.new(target_pos) * look_rotation * current_rot

	-- part movement
	-- lerp for smooth movement
	target_part.CFrame = target_part.CFrame:Lerp(goal_cframe, config.lerp_speed)

	-- reset physics
	-- keep velocity zero so it doesnt fly away while holding
	target_part.AssemblyLinearVelocity = Vector3.zero
	target_part.AssemblyAngularVelocity = Vector3.zero
end)

-- cleanup when dying
plr.CharacterRemoving:Connect(function()
	if holding then
		release_object(false)
	end
	highlight:Destroy()
end)
