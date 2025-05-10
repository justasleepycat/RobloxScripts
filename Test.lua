for i,v in pairs(getgc(true)) do
    pcall(function()
        if rawget(v,"Recoil") then
            v.Recoil = 0
        end
        if rawget(v,"Accuracy") then
            v.Accuracy = 2
        end
    end)
end