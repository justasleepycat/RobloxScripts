local getfenvSucceeded, err = pcall(function()
	print(getfenv(2).script)
end)

if getfenvSucceeded then
	print("Success")
end