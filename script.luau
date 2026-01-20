local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

-- OOP setup
local PhysicsGrabber = {}
PhysicsGrabber.__index = PhysicsGrabber

function PhysicsGrabber.new()
	local self = setmetatable({}, PhysicsGrabber)

	-- getting player stuff
	self.plr = Players.LocalPlayer
	self.mouse = self.plr:GetMouse()
	self.cam = Workspace.CurrentCamera
	self.char = self.plr.Character or self.plr.CharacterAdded:Wait()

	-- forcing first person cause looks better for this
	self.plr.CameraMode = Enum.CameraMode.LockFirstPerson

	-- bunch of settings
	self.config = {
		reach_dist = 65, -- how far u can grab
		min_dist = 5, -- stop it from clipping inside u

		-- throw stuff
		start_throw_pwr = 100,
		max_yeet_pwr = 800,
		charge_speed = 15, -- speeds up the power bar

		-- movement feels
		smoothness = 0.25, -- lower = feels heavy/laggy
		spin_speed = 2.5, -- for R and T keys

		-- wobble (makes it look shaky/unstable)
		wobble_amt = 0.05,
		wobble_fast = 10,

		-- colors
		col_normal = Color3.fromRGB(255, 255, 255),
		col_grabbed = Color3.fromRGB(0, 255, 100),
		col_angry = Color3.fromRGB(255, 50, 50) -- charging color
	}

	-- state variables (tracking whats happening)
	self.is_holding = false
	self.target_part = nil
	self.hold_dist = 15
	self.current_rot = CFrame.identity
	self.grab_offset = CFrame.identity -- needed so part dont snap to center

	-- charge mechanics
	self.charging = false
	self.charge_lvl = 0

	-- spinny mode
	self.auto_spin = false
	self.spin_val = 0

	-- the glowing box thing
	self.box = Instance.new("SelectionBox")
	self.box.Name = "GrabHighlight"
	self.box.LineThickness = 0.05
	self.box.Parent = self.plr:WaitForChild("PlayerGui")

	-- bind inputs immediately
	self:SetupControls()
	self:StartLoop()

	return self
end

-- prevent ray from hitting us or the thing we holding
function PhysicsGrabber:GetIgnoreList()
	local ignore = {self.char}

	-- if we got a part, ignore it too so we dont grab inside it
	if self.target_part then
		table.insert(ignore, self.target_part)
	end
	return ignore
end

-- laser pointer logic
function PhysicsGrabber:CastRay()
	local m_pos = UserInputService:GetMouseLocation()
	local ray = self.cam:ViewportPointToRay(m_pos.X, m_pos.Y)

	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = self:GetIgnoreList()

	-- shoot the ray
	local res = Workspace:Raycast(ray.Origin, ray.Direction * self.config.reach_dist, p)
	return res
end

-- try to pick something up
function PhysicsGrabber:TryGrab()
	if self.is_holding then return end -- already holding something

	local hit = self:CastRay()

	if hit and hit.Instance then
		local part = hit.Instance

		if part.Locked then return end -- cant grab locked parts
		if part:IsA("Terrain") then return end -- dont grab the ground

		-- making a clone cause its safer for physics
		local fake_part = part:Clone()
		fake_part.Parent = Workspace
		fake_part.CFrame = part.CFrame
		fake_part.Name = "PhysicsProp"

		-- delete old one
		part:Destroy()

		-- setup the physics
		fake_part.Anchored = true
		fake_part.CanCollide = false
		fake_part.Massless = true
		fake_part.CastShadow = false -- unnecessary lag fix

		-- stop it from moving
		fake_part.AssemblyLinearVelocity = Vector3.zero
		fake_part.AssemblyAngularVelocity = Vector3.zero

		-- save the data
		self.is_holding = true
		self.target_part = fake_part
		self.hold_dist = (self.cam.CFrame.Position - fake_part.Position).Magnitude
		self.current_rot = fake_part.CFrame.Rotation

		-- math to make sure we grab it at the point we clicked
		-- basicly calculates offset from center
		self.grab_offset = CFrame.lookAt(self.cam.CFrame.Position, fake_part.Position):Inverse() * fake_part.CFrame

		-- make it glow
		self.box.Adornee = fake_part
		print("yoinked " .. fake_part.Name)
	end
end

-- drop or yeet the object
function PhysicsGrabber:LetGo(do_yeet)
	if not self.is_holding or not self.target_part then return end

	local p = self.target_part

	-- fix properties back to normal
	p.CanCollide = true
	p.Massless = false
	p.CastShadow = true

	-- unfreeze it
	p.Anchored = false

	if do_yeet then
		-- weird delay hack to wake up physics engine
		task.spawn(function()
			RunService.Heartbeat:Wait()

			if p and p.Parent then
				local dir = self.cam.CFrame.LookVector

				-- calc full power
				local boom = self.config.start_throw_pwr + self.charge_lvl

				-- send it
				p.AssemblyLinearVelocity = dir * boom

				-- make it spin chaoticly if thrown hard
				local spin = boom / 20
				p.AssemblyAngularVelocity = Vector3.new(
					math.random(-spin, spin),
					math.random(-spin, spin),
					math.random(-spin, spin)
				)
			end
		end)
	else
		-- kill speed so it falls straight down
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.zero
	end

	-- reset everything
	self.is_holding = false
	self.target_part = nil
	self.box.Adornee = nil
	self.charging = false
	self.charge_lvl = 0
	self.auto_spin = false
end

-- handle buttons and scroll
function PhysicsGrabber:SetupControls()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end

		-- click to grab
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:TryGrab()

			-- F to charge up
		elseif input.KeyCode == Enum.KeyCode.F then
			if self.is_holding then
				self.charging = true
			end

			-- R rotates it sideways
		elseif input.KeyCode == Enum.KeyCode.R then
			if self.is_holding then
				local r = CFrame.Angles(0, math.rad(45), 0)
				self.current_rot = self.current_rot * r
			end

			-- T rotates it up/down
		elseif input.KeyCode == Enum.KeyCode.T then
			if self.is_holding then
				local r = CFrame.Angles(math.rad(45), 0, 0)
				self.current_rot = self.current_rot * r
			end

			-- Q to make it spin infinite
		elseif input.KeyCode == Enum.KeyCode.Q then
			if self.is_holding then
				self.auto_spin = not self.auto_spin
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		-- release click = drop
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:LetGo(false)

			-- release F = throw
		elseif input.KeyCode == Enum.KeyCode.F then
			if self.is_holding and self.charging then
				self:LetGo(true)
			end
			self.charging = false
		end
	end)

	-- scroll wheel for distance
	UserInputService.InputChanged:Connect(function(input, gp)
		if not gp and input.UserInputType == Enum.UserInputType.MouseWheel then
			if self.is_holding then
				local delta = input.Position.Z
				self.hold_dist = self.hold_dist - (delta * 2)

				-- dont let it go too close or too far
				if self.hold_dist < self.config.min_dist then 
					self.hold_dist = self.config.min_dist 
				end
				if self.hold_dist > self.config.reach_dist then 
					self.hold_dist = self.config.reach_dist 
				end
			end
		end
	end)
end

-- the big loop that runs every frame
function PhysicsGrabber:StartLoop()
	RunService.RenderStepped:Connect(function(dt)

		-- if we aint holding nothing
		if not self.is_holding then
			local r = self:CastRay()

			if r and r.Instance then
				-- check if grabable
				if not r.Instance.Locked and not r.Instance.Anchored then
					self.box.Adornee = r.Instance
					self.box.Color3 = self.config.col_normal
					self.mouse.Icon = "rbxasset://textures/Cursors/Gamepad/Pointer.png"
				else
					self.box.Adornee = nil
					self.mouse.Icon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
				end
			else
				self.box.Adornee = nil
				self.mouse.Icon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
			end
			return
		end

		-- safety check incase part fell in void
		if not self.target_part or not self.target_part.Parent then
			self.is_holding = false
			self.target_part = nil
			self.box.Adornee = nil
			return
		end

		-- charge logic
		if self.charging then
			-- power goes UP
			self.charge_lvl = self.charge_lvl + self.config.charge_speed
			if self.charge_lvl > self.config.max_yeet_pwr then
				self.charge_lvl = self.config.max_yeet_pwr
			end

			-- make box red
			self.box.Color3 = self.config.col_angry

			-- shake cam cause it looks cool
			local shake = Vector3.new(math.random()-0.5, math.random()-0.5, 0) * 0.05
			self.cam.CFrame = self.cam.CFrame * CFrame.new(shake)
		else
			self.box.Color3 = self.config.col_grabbed
		end

		-- spin logic
		if self.auto_spin then
			self.spin_val = self.spin_val + (dt * 5)
			-- mix it with current rotation
			self.current_rot = self.current_rot * CFrame.Angles(0, dt, 0)
		end

		-- calculating where part should go
		local cf = self.cam.CFrame
		local target_pos = cf.Position + (cf.LookVector * self.hold_dist)

		-- collision check
		-- ray from face to target pos
		local wall_ray_start = cf.Position
		local wall_ray_dir = (target_pos - wall_ray_start)

		local wall_p = RaycastParams.new()
		wall_p.FilterType = Enum.RaycastFilterType.Exclude
		wall_p.FilterDescendantsInstances = {self.char, self.target_part}

		local wall_hit = Workspace:Raycast(wall_ray_start, wall_ray_dir, wall_p)

		if wall_hit then
			-- hit a wall, pull it closer
			target_pos = wall_hit.Position
		end

		-- wobble math
		-- adds noise so it doesnt look frozen in air
		local time_now = tick()
		local n_x = math.sin(time_now * self.config.wobble_fast) * self.config.wobble_amt
		local n_y = math.cos(time_now * self.config.wobble_fast) * self.config.wobble_amt
		local wobble = Vector3.new(n_x, n_y, 0)

		target_pos = target_pos + wobble

		-- calculate final rotation
		local look_rot = CFrame.lookAt(Vector3.zero, cf.LookVector)

		-- mash it all together
		local goal_cf = CFrame.new(target_pos) * look_rot * self.current_rot

		-- actually move the part
		-- using lerp so its smooth
		self.target_part.CFrame = self.target_part.CFrame:Lerp(goal_cf, self.config.smoothness)

		-- force velocity to 0 so physics don't fight us
		self.target_part.AssemblyLinearVelocity = Vector3.zero
		self.target_part.AssemblyAngularVelocity = Vector3.zero
	end)
end

-- start the system
local main_grabber = PhysicsGrabber.new()

-- cleanup if u die
main_grabber.plr.CharacterRemoving:Connect(function()
	if main_grabber.is_holding then
		main_grabber:LetGo(false)
	end
	if main_grabber.box then
		main_grabber.box:Destroy()
	end
end)
