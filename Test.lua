game:GetService("RunService").Heartbeat:Connect(function(deltaTime : double)
	local CurrentCamera = game:GetService("Workspace").CurrentCamera
	local Character = game:GetService("Players").LocalPlayer.Character
	if not Character then return end
	local HumanoidRootPart =  Character:FindFirstChild("Head", true)
	if not HumanoidRootPart then return end
	local Humanoid = Character:FindFirstChildWhichIsA("Humanoid", true)
	local oldVelocity = HumanoidRootPart.AssemblyLinearVelocity

	Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	HumanoidRootPart.AssemblyLinearVelocity = CurrentCamera.CFrame.LookVector * 1e6
	game:GetService("RunService").Stepped:Wait()
	HumanoidRootPart.AssemblyLinearVelocity = oldVelocity
end)