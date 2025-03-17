local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
if getgenv().Yunite["Key"] ~= "Wass" then
    LocalPlayer:Kick("Invalid key!")
    return
end
