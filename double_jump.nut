if (!Entities.FindByName(null, "doublejump_timer")) {
    SpawnEntityFromTable("logic_timer", {
        targetname = "doublejump_timer",
        RefireTime = 0.05, 
        OnTimer = "!self,RunScriptCode,RespireDoubleJump.Think()"
    });
}

if (!Entities.FindByName(null, "doublejump_cleanup_timer")) {
    SpawnEntityFromTable("logic_timer", {
        targetname = "doublejump_cleanup_timer",
        RefireTime = 30.0, 
        OnTimer = "!self,RunScriptCode,RespireDoubleJump.PeriodicCleanup()"
    });
}

::RespireDoubleJump <- {
    DOUBLEJUMP_SOUND = "player/jumplanding_zombie.wav",
    DOUBLEJUMP_FORCE = 270,
    DEBUG_MODE = false,
    IN_JUMP = 2,
    JUMP_DELAY = 0.05,
    MIN_HEALTH = 15,
    INVALID_GROUND_ENTITY = -1,
    CLEANUP_INTERVAL = 30.0,

    PLAYER_STATE = {},
    AIRBORNE_PLAYERS = {},

    function Log(message, level = "DEBUG") {
        if (this.DEBUG_MODE || level != "DEBUG") {
            printl("[Double Jump " + level + "] " + message);
        }
    },

    
    function OnGameEvent_player_jump(params) {
        this.HandlePlayerJump(params.userid);
    },

    function OnGameEvent_player_falldamage(params) {
        this.HandlePlayerLand(params.userid);
    },

    function OnGameEvent_player_spawn(params) {
        local player = GetPlayerFromUserID(params.userid);
        if (player && player.IsSurvivor()) {
            this.InitPlayerState(params.userid);
        }
    },

    function OnGameEvent_player_death(params) {
        if ("userid" in params) {
            local userID = params.userid;
            local player = GetPlayerFromUserID(userID);
            
            if (player && player.IsSurvivor()) {
                this.CleanupPlayerState(userID);
                this.Log("Cleaned up state for dead survivor: " + userID);
            }
        }
    },


    function InitPlayerState(userID) {
        this.PLAYER_STATE[userID] <- {
            canDoubleJump = true,
            hasDoubleJumped = false,
            initialJumpTime = 0,
            lastJumpButtonState = false,
            currentJumpButtonState = false,
            loggedGroundStatus = false,
            lastActivityTime = Time()
        };
        this.Log("UserID's State Initialized: " + userID);
    },

    function CleanupPlayerState(userID) {
        if (userID in this.PLAYER_STATE) {
            delete this.PLAYER_STATE[userID];
        }
        if (userID in this.AIRBORNE_PLAYERS) {
            delete this.AIRBORNE_PLAYERS[userID];
        }
        this.Log("Player state cleaned up: " + userID);
    },

    function ResetPlayerState(userID) {
        local player = GetPlayerFromUserID(userID);
        if (this.IsValidPlayer(player)) {
            this.PLAYER_STATE[userID] = {
                canDoubleJump = true,
                hasDoubleJumped = false,
                initialJumpTime = 0,
                lastJumpButtonState = false,
                currentJumpButtonState = false,
                loggedGroundStatus = true,
                lastActivityTime = Time()
            };
            this.Log("Reset state for inactive player: " + userID);
        } else {
            this.CleanupPlayerState(userID);
        }
    },


    function HandlePlayerJump(userID) {
        local player = GetPlayerFromUserID(userID);
        if (!player || !player.IsSurvivor()) {
            this.Log("Invalid player or not a survivor in [HandlePlayerJump] for userID: " + userID, "WARNING");
            return;
        }
    
        if (!(userID in this.PLAYER_STATE)) {
            this.InitPlayerState(userID);
        }
        
        local state = this.PLAYER_STATE[userID];
        state.initialJumpTime = Time();
        state.canDoubleJump = player.GetHealth() > this.MIN_HEALTH;
        state.hasDoubleJumped = false;
        state.loggedGroundStatus = false;
        state.lastActivityTime = Time();
        this.AIRBORNE_PLAYERS[userID] <- true;
        this.Log("Player jumped, set state to airborne: " + userID);
    },

    function HandlePlayerLand(userID) {
        local player = GetPlayerFromUserID(userID);
        if (!this.IsValidPlayer(player)) {
            this.Log("Invalid player in [HandlePlayerLand] for userID: " + userID, "WARNING");
            this.CleanupPlayerState(userID);
            return;
        }

        if (userID in this.AIRBORNE_PLAYERS) {
            delete this.AIRBORNE_PLAYERS[userID];
            if (userID in this.PLAYER_STATE) {
                this.PLAYER_STATE[userID].lastActivityTime = Time();
                this.PLAYER_STATE[userID].canDoubleJump = true;
                this.PLAYER_STATE[userID].hasDoubleJumped = false;
            }
            this.Log("Player landed, removed state for airborne: " + userID);
        }
    },

    function HandleDoubleJump(player) {
        local velocity = player.GetVelocity();
        velocity.z = this.DOUBLEJUMP_FORCE;
        player.SetVelocity(velocity);
        NetProps.SetPropFloat(player, "localdata.m_Local.m_flFallVelocity", 0.0);
        EmitSoundOn(this.DOUBLEJUMP_SOUND, player);
        this.Log("Double Jump executed by player: " + player.GetPlayerName());
    },


    function IsPlayerMidair(player) {
        return NetProps.GetPropInt(player, "m_hGroundEntity") == this.INVALID_GROUND_ENTITY;
    },

    function Think() {
        local currentTime = Time();
        local playersToRemove = [];
    
        foreach (userID, _ in this.AIRBORNE_PLAYERS) {
            if (!(userID in this.PLAYER_STATE)) {
                this.Log("UserID " + userID + " not found in [PLAYER_STATE]. Skipping.", "WARNING");
                playersToRemove.append(userID);
                continue;
            }
    
            local player = GetPlayerFromUserID(userID);
            if (!this.IsValidPlayer(player)) {
                this.Log("Invalid player for userID: " + userID + ". Cleaning up state.", "WARNING");
                playersToRemove.append(userID);
                continue;
            }
    
            local state = this.PLAYER_STATE[userID];
            local buttons = player.GetButtonMask();
            state.currentJumpButtonState = (buttons & this.IN_JUMP) != 0;
            local onGround = !this.IsPlayerMidair(player);
    
            if (onGround) {
                if (!state.loggedGroundStatus) {
                    state.canDoubleJump = player.GetHealth() > this.MIN_HEALTH;
                    state.hasDoubleJumped = false;
                    this.Log("Player is on ground, double jump resets: " + userID);
                    state.loggedGroundStatus = true;
                }
                playersToRemove.append(userID);
            } else {
                state.loggedGroundStatus = false;
                if (this.CheckDoubleJumpConditions(state, currentTime)) {
                    this.HandleDoubleJump(player);
                    state.hasDoubleJumped = true;
                    this.Log("Player has double jumped: " + userID);
                }
            }
    
            state.lastJumpButtonState = state.currentJumpButtonState;
            state.lastActivityTime = currentTime;
        }
    
        foreach (userID, state in this.PLAYER_STATE) {
            if (!(userID in this.AIRBORNE_PLAYERS)) {
                local player = GetPlayerFromUserID(userID);
                if (this.IsValidPlayer(player) && this.IsPlayerMidair(player)) {
                    this.AIRBORNE_PLAYERS[userID] <- true;
                    state.canDoubleJump = player.GetHealth() > this.MIN_HEALTH;
                    state.hasDoubleJumped = false;
                    state.initialJumpTime = currentTime;
                    this.Log("Player detected midair, enabling double jump: " + userID);
                }
            }
        }
    
        foreach (userID in playersToRemove) {
            delete this.AIRBORNE_PLAYERS[userID];
        }
    },

    function CheckDoubleJumpConditions(state, currentTime) {
        if (currentTime - state.initialJumpTime <= this.JUMP_DELAY) return false;
        return state.canDoubleJump && 
               !state.hasDoubleJumped &&
               state.currentJumpButtonState && 
               !state.lastJumpButtonState;
    },


    function IsValidPlayer(player) {
        return player && 
               player.IsValid() && 
               player.IsSurvivor() && 
               player.GetHealth() > 0 && 
               !player.IsDead() && 
               !player.IsDying() &&
               !player.IsIncapacitated();
    },

    function PeriodicCleanup() {
        local currentTime = Time();
        local playersToReset = [];
    
        foreach (userID, state in this.PLAYER_STATE) {
            local player = GetPlayerFromUserID(userID);
            if (!this.IsValidPlayer(player)) {
                this.CleanupPlayerState(userID);
                this.Log("Removed state for invalid player: " + userID);
            } else if (currentTime - state.lastActivityTime > this.CLEANUP_INTERVAL) {
                if (!(userID in this.AIRBORNE_PLAYERS)) {
                    playersToReset.append(userID);
                }
            }
        }
    
        foreach (userID in playersToReset) {
            this.ResetPlayerState(userID);
        }
    
        this.Log("Periodic cleanup completed. Reset " + playersToReset.len() + " inactive players.");
    },


    // Compatibility for my Dashing script. If you see this, this is yet to release.
    function DashingConnection(userID) {
        if (!(userID in this.PLAYER_STATE)) {
            this.InitPlayerState(userID);
        }
        
        local state = this.PLAYER_STATE[userID];
        state.initialJumpTime = Time();
        state.lastActivityTime = Time();
        this.AIRBORNE_PLAYERS[userID] <- true;
        this.Log("Player dashed, updated activity time: " + userID);
    },
}

RespireDoubleJump.Init <- function () {
    PrecacheSound(this.DOUBLEJUMP_SOUND);
    __CollectEventCallbacks(this, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
    this.Log("Respire's Double Jump Loaded", "INFO");
}

RespireDoubleJump.Init();