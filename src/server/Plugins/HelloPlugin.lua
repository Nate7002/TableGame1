local HelloPlugin = {}

function HelloPlugin.Run(context)
	print("[HelloPlugin] Running for player: " .. (context.player and context.player.Name or "Unknown"))
	
	task.wait(0.5) -- Simulate work
	
	return {
		ok = true,
		data = {
			message = "Hello from the plugin system!",
			timestamp = os.time()
		}
	}
end

return HelloPlugin

