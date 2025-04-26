

			end
		end


		if siriusValues.pingProfile.pingNotificationCooldown > 0 then
			siriusValues.pingProfile.pingNotificationCooldown -= 1
		end


		-- Adaptive frame time checks
		if siriusValues.frameProfile.frameNotificationCooldown <= 0 then
			if #siriusValues.frameProfile.fpsQueue > 0 then
				local avgFPS = siriusValues.frameProfile.totalFPS / #siriusValues.frameProfile.fpsQueue


				if avgFPS < siriusValues.frameProfile.lowFPSThreshold then
					if checkSetting("Adaptive Performance Warning").current then
						queueNotification("Degraded Performance","We've noticed your client's frames per second have decreased. Consider checking for any background tasks or programs on your machine.", 4384400106)
						siriusValues.frameProfile.frameNotificationCooldown = 120	
					end
				end
			end
		end


		if siriusValues.frameProfile.frameNotificationCooldown > 0 then
			siriusValues.frameProfile.frameNotificationCooldown -= 1
		end
	end
end

