local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local plr = Players.LocalPlayer
local mouse = plr:GetMouse()
local cam = Workspace.CurrentCamera

local char = plr.Character or plr.CharacterAdded:Wait()
-- force first person mode
plr.CameraMode = Enum.CameraMode.LockFirstPerson

local settings = {
	range = 60,
	throw_power = 300, 
	smoothness = 0.2, 
	color_idle = Color3.fromRGB(255, 255, 255),
	color_active = Color3.fromRGB(85, 255, 127)
}

local Controller = {}
Controller.__index = Controller

function Controller.new()
	local self = setmetatable({}, Controller)

	self.IsActive = false
	self.TargetPart = nil
	self.Distance = 15
	self.Rotation = CFrame.identity

	-- highlight box
	self.Selection = Instance.new("SelectionBox")
	self.Selection.LineThickness = 0.05
	self.Selection.Parent = plr:WaitForChild("PlayerGui")

	self:SetupInputs()
	return self
end

function Controller:CastRay()
	local pos = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {plr.Character}

	-- ignore the part we holding so ray goes thru it
	if self.TargetPart then table.insert(ignore, self.TargetPart) end
	params.FilterDescendantsInstances = ignore

	return Workspace:Raycast(ray.Origin, ray.Direction * settings.range, params)
end

function Controller:AttemptGrab()
	if self.IsActive then return end

	local result = self:CastRay()
	if result and result.Instance then
		local originalPart = result.Instance

		if originalPart.Locked then return end

		-- we delete server part locally and make a clone we own
		-- so physics actually works

		local myPart = originalPart:Clone()
		myPart.Parent = Workspace
		myPart.CFrame = originalPart.CFrame 

		-- destroy old one (locally)
		originalPart:Destroy() 

		self.IsActive = true
		self.TargetPart = myPart 

		-- fix highlight here :
		-- update the box to look at the NEW part
		self.Selection.Adornee = myPart

		-- setup physics
		myPart.Anchored = true 
		myPart.CanCollide = false 
		myPart.Massless = true 
		myPart.AssemblyLinearVelocity = Vector3.new()
		myPart.AssemblyAngularVelocity = Vector3.new()

		self.Distance = (cam.CFrame.Position - myPart.Position).Magnitude
		self.Rotation = myPart.CFrame.Rotation
	end
end

function Controller:Release(throw)
	if not self.IsActive then return end

	local p = self.TargetPart

	if p then
		p.CanCollide = true
		p.Massless = false
		p.Anchored = false -- unanchor clone

		if throw then
			task.spawn(function()
				RunService.Heartbeat:Wait()
				if not p then return end

				local dir = cam.CFrame.LookVector
				p.AssemblyLinearVelocity = dir * settings.throw_power
				p.AssemblyAngularVelocity = Vector3.new(math.random(-20,20), math.random(-20,20), math.random(-20,20))
			end)
		else
			p.AssemblyLinearVelocity = Vector3.new(0,0,0)
			p.AssemblyAngularVelocity = Vector3.new(0,0,0)
		end
	end

	self.IsActive = false
	self.TargetPart = nil

	-- clear highlight
	self.Selection.Adornee = nil
end

function Controller:SetupInputs()
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:AttemptGrab()
		elseif input.KeyCode == Enum.KeyCode.F then
			self:Release(true) 
		elseif input.KeyCode == Enum.KeyCode.R then
			self:Rotate("Y")
		elseif input.KeyCode == Enum.KeyCode.T then
			self:Rotate("X")
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:Release(false) 
		end
	end)

	UserInputService.InputChanged:Connect(function(input, gp)
		if not gp and input.UserInputType == Enum.UserInputType.MouseWheel then
			self:Scroll(input.Position.Z)
		end
	end)
end

function Controller:Scroll(delta)
	if self.IsActive then
		self.Distance = math.clamp(self.Distance - (delta * 2), 5, settings.range)
	end
end

function Controller:Rotate(axis)
	if self.IsActive then
		local rot = CFrame.identity
		if axis == "X" then rot = CFrame.Angles(math.rad(45), 0, 0) end
		if axis == "Y" then rot = CFrame.Angles(0, math.rad(45), 0) end
		self.Rotation = self.Rotation * rot
	end
end

function Controller:Step(dt)
	-- idle state ( not holding )
	if not self.IsActive then
		local res = self:CastRay()
		if res and res.Instance then
			self.Selection.Adornee = res.Instance
			self.Selection.Color3 = settings.color_idle
			mouse.Icon = "rbxasset://textures/Cursors/Gamepad/Pointer.png"
		else
			-- if looking at sky, turn off highlight
			self.Selection.Adornee = nil
			mouse.Icon = "rbxasset://textures/Cursors/KeyboardMouse/ArrowCursor.png"
		end
		return
	end

	-- holding state
	if not self.TargetPart or not self.TargetPart.Parent then
		self:Release(false)
		return
	end

	-- force highlight to stay on the grabbed part
	self.Selection.Adornee = self.TargetPart
	self.Selection.Color3 = settings.color_active

	local cf = cam.CFrame
	local goal_pos = cf.Position + (cf.LookVector * self.Distance)

	local ray_origin = cf.Position
	local ray_dir = (goal_pos - ray_origin)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {plr.Character, self.TargetPart} 
	local hit_result = Workspace:Raycast(ray_origin, ray_dir, params)

	if hit_result then goal_pos = hit_result.Position end

	local look_rot = CFrame.lookAt(Vector3.zero, cf.LookVector)
	local goal_cframe = CFrame.new(goal_pos) * look_rot * self.Rotation

	self.TargetPart.CFrame = self.TargetPart.CFrame:Lerp(goal_cframe, settings.smoothness)
	self.TargetPart.AssemblyLinearVelocity = Vector3.new()
end

-- initalize
local main = Controller.new()

RunService.RenderStepped:Connect(function(dt)
	main:Step(dt)
end)

-- release object when player resets or leaves
plr.CharacterRemoving:Connect(function()
	main:Release(false)
end)
