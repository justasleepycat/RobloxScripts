for i,v in pairs(game:GetService("Players"):GetChildren()) do
	pcall(function()
		print(v.Character.Humanoid.WalkSpeed)
	end)
end