scriptId = 'com.gauthamchandra.myo.spotify'

--Commands:
---Volume up/down : hold fist and rotate right/left respectively
---Play/Pause : Spread fingers outward
---Prev/Next Track : Wave Left/Right
---Seek Forward/Backward : Wave Left/Right and HOLD for 1/2 second



-- Some constants
UNLOCKED_TIMEOUT = 3000 --Time since last activity before we lock
ROTATE_TIME_THRESHOLD = 500 --Time before the rotate gesture is recognized (to prevent accidental gestures)
SEEK_THRESHOLD = 500 --Time before a next/prev track gesture becomes a seek forward/back gesture
ROLL_MOTION_THRESHOLD = 7 --The number of degrees that must be turned for the volume up/down gesture to activate

function changeVolume(direction)
	local modifier = ""

	if platform == "MacOS" then
		modifier = "command"
	elseif platform == "Windows" then
		modifier = "control"
	end

	if direction == "up" then
		myo.keyboard("up_arrow", "press", modifier)
	elseif direction == "down" then
		myo.keyboard("down_arrow", "press", modifier)
	end

end

function togglePlay()
	myo.keyboard("space", "press")
end

function changeTrack(type)
	local modifier = ""

	-- Check the platform and use the right hotkey
	if platform == "MacOS" then
		modifier = "command"
	elseif platform == "Windows" then
		modifier = "control"
	end

	if type == "next" then
		myo.keyboard("right_arrow", "press", modifier)
	else
		myo.keyboard("left_arrow", "press", modifier)
	end
end

-- Seeks forward/backward. The endOfSeek parameter is a flag that tells it whether to stop 
-- pressing the button combination or press it
function seek(type)
	-- Platform doesn't matter for seek as its the same in OSX and Windows
	if type == "forward" then
		myo.keyboard("right_arrow", "press", "shift")
	elseif type == "backward" then
		myo.keyboard("left_arrow", "press", "shift")
	end
end
-- The function to call to unlock Myo (with thumb-pinky gesture) so that the user can
-- control app
function unlockMyo()
	unlocked = true
	resetUnlockTimeout()
end

function resetUnlockTimeout()
	unlockedSince = myo.getTimeMilliseconds()
end

-- Done specifically to figure out what arm it is and what direction the user is waving
-- so we know what action to do. 
-- This is for the "next" and "prev" actions for music playing
function getWaveDirection(pose)
	if myo.getArm() == "left" then
		if pose == "waveIn" then
			return "right"
		elseif pose == "waveOut" then
			return "left"
		end
	elseif myo.getArm() == "right" then
		if pose == "waveIn" then
			return "left"
		elseif pose == "waveOut" then
			return "right"
		end
	end
	return "unknown"
end

-- A function called every 10 millisec by Myo Script manager to allow
-- The script to run certain timed functions like timeout before relocking Myo (to prevent
-- accidental gestures)
function onPeriodic()
	local now = myo.getTimeMilliseconds()

	--Lock if we are already past the inactivity timeout period to prevent accidental gestures
	if unlocked then
		if now - unlockedSince > UNLOCKED_TIMEOUT then
			unlocked = false
		end

		--if there is a rotate gesture active and the rotate threshold is met
		--Then call up/down volume change
		if fistRotationGesture and now - rotateSince > ROTATE_TIME_THRESHOLD then
			local rollInDegs = math.deg(myo.getRoll())
			local degDelta = fistRollReferencePoint - rollInDegs

			if math.abs(degDelta) > ROLL_MOTION_THRESHOLD then
				if degDelta < 0 then
					changeVolume("down")
				else
					changeVolume("up")
				end
			end
			

			--As long as the fist is tightened, extend the unlock timeout
			resetUnlockTimeout()
		end

		--If the they are doing a wave gesture and its past the seek threshold,
		--Then seek
		if seekGesture and now - seekSince >= SEEK_THRESHOLD then
			if seekGesture == "right" then
				seek("forward")
				resetUnlockTimeout()
			elseif seekGesture == "left" then
				seek("backward")
				resetUnlockTimeout()
			end
		end
	end

	--If we have a seek timeout in effect then we must be 
end

-- A function that is called when the user does a gesture
-- Edge = on means the start of a gesture. Edge = off is the end
function onPoseEdge(pose, edge)
	
	-- If its the unlock gesture
	if pose == "thumbToPinky" then
		if edge == "off" then
			-- User finished the unlock gesture so unlock
			unlockMyo()
			resetUnlockTimeout()
		elseif edge == "on" and not unlocked then
			-- Vibrate twice for user feedback to tell the user that they can let
			-- go and finish the gesture to unlock
			myo.vibrate("short")
			myo.vibrate("short")
		end
	elseif pose == "fingersSpread" then
		-- Want to make sure we pause/play at the end of the gesture
		if unlocked and edge == "off" then
			togglePlay()
			resetUnlockTimeout()
		end
	elseif pose == "fist" then
		if unlocked and edge == "on" then
			fistRotationGesture = true
			fistRollReferencePoint = math.deg(myo.getRoll())
			rotateSince = myo.getTimeMilliseconds()
			resetUnlockTimeout()
		elseif unlocked and edge == "off" then
			fistRotationGesture = false
			resetUnlockTimeout()
		end

	elseif pose == "waveIn" or pose == "waveOut" then
		local now = myo.getTimeMilliseconds()
		
		if unlocked and edge == "on" then
			-- Start setting the seek variables as it could be a prolonged wave in/out
			-- gesture meant to seek forward/back
			seekSince = now
			seekGesture = getWaveDirection(pose)

			resetUnlockTimeout()
		end

		-- If its unlocked and the user started gesture, then normalize pose for wave in/out
		-- and do the next/prev track changes
		if unlocked and edge == "off" then
			local direction = getWaveDirection(pose)
			local successfulGesture = false

			--Just in case, this was the end of the seek gesture, set it to false
			seekGesture = nil

			--If they did the wave gesture for only a small amount of time,
			--then it was a next/prev track gesture.
			if now - seekSince < SEEK_THRESHOLD then
				if direction == "right" then
					changeTrack("next")

					successfulGesture = true
				elseif direction == "left" then
					changeTrack("prev")

					successfulGesture = true
				else
					myo.debug("If we are here, then the user is waving but we don't know which arm so ignoring")
				end

				-- There is a possibility that the arm is unknown and thus had no successful
				-- gesture so only do the following if everything was known and went well
				if successfulGesture then
					-- Vibrate to tell user he did something
					myo.vibrate("short")

					-- Reset timeout since user just did something
					resetUnlockTimeout()
				end
			end
			
		end

		-- If we are no longer holding the wave in/out gesture, they must have either
		-- not done the seek gesture or just ended it.
		if edge == "off" then
			seekTimeout = nil
		end
	end
end

-- Decide if this is Spotify
function onForegroundWindowChange(app, title)
	local wantActive = false
	activeApp = ""
	
	if platform == "MacOS" then
		if app == "com.spotify.client" then
			wantActive = true
			activeApp = "Spotify"
		end
	elseif platform == "Windows" then
		wantActive = string.match(title, " %- Spotify$") or
					 string.match(title, " %- spotify$")
		activeApp = "Spotify"
	end
	return wantActive
end

-- Get App Name that was set in onForegroundWindowChange()
function getActiveAppName()
	return activeApp
end

-- When Script becomes active, set the unlocked flag
function onActiveChange(isActive)
	if not isActive then
		unlocked = false
	end
end
