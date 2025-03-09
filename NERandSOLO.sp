#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>

#include <multicolors>

#include <tf2_stocks>

#define PLUGIN_NAME        "NER/SOLO Standalone plugin For Dodgeball"
#define PLUGIN_AUTHOR      "Mikah"
#define PLUGIN_VERSION     "1.5.3"
#define PLUGIN_URL         "-"

public Plugin myinfo =
{
	name        = PLUGIN_NAME,
	author      = PLUGIN_AUTHOR,
	description = PLUGIN_NAME,
	version     = PLUGIN_VERSION,
	url         = PLUGIN_URL
};

#define AnalogueTeam(%1) (%1^1)
#define SOUND_NER_RESPAWNED	")ambient/alarms/doomsday_lift_alarm.wav"

// NER
float g_fNERvoteTime;
bool g_bNERenabled;

int g_iOldTeam[MAXPLAYERS + 1];
int g_iBot;

// Randomizing teams for NER respawn
int g_iAllPlayers[MAXPLAYERS + 1];

// Solo
ArrayStack g_soloQueue;
bool g_bSoloEnabled[MAXPLAYERS + 1];

bool g_bRoundStarted;
float g_fLastRespawned; // for invincibility
int g_iLastDeadTeam = 2; // Red team

ConVar g_Cvar_SeeBotsAsPlayers; // For testing NER with bots

ConVar g_Cvar_NERvotingTimeout;
ConVar g_Cvar_ForceNER;
ConVar g_Cvar_ForceNERstartMap;
ConVar g_Cvar_NERenabled;
ConVar g_Cvar_SoloEnabled;
ConVar g_Cvar_SoloPriority;
ConVar g_Cvar_HornSound;
ConVar g_Cvar_RespawnProtection;

Address g_pMyWearables;

public void OnPluginStart()
{
	LoadTranslations("tfdb.phrases.txt");

	RegAdminCmd("sm_ner", CmdToggleNER, ADMFLAG_CONFIG, "Forcefully toggle NER (Never ending rounds)");
	RegConsoleCmd("sm_votener", CmdVoteNER, "Vote to toggle NER");

	RegConsoleCmd("sm_solo", CmdSolo, "Toggle solo mode");

	g_fNERvoteTime = 0.0;

	g_Cvar_NERvotingTimeout = CreateConVar("tfdb_NERvotingTimeout", "120", "Voting timeout for NER", _, true, 0.0);
	g_Cvar_ForceNER = CreateConVar("tfdb_ForceNER", "0", "Forces NER mode (when possible), can't be disabled anymore", _, true, 0.0, true, 1.0);
	g_Cvar_ForceNERstartMap = CreateConVar("tfdb_ForceNERstartMap", "0", "Enables NER mode at the start of the map", _, true, 0.0, true, 1.0);
	g_Cvar_NERenabled = CreateConVar("tfdb_NERenabled", "1", "Enables/disables NER", _, true, 0.0, true, 1.0);
	g_Cvar_SoloEnabled = CreateConVar("tfdb_SoloEnabled", "1", "Enables/disables Solo", _, true, 0.0, true, 1.0);
	g_Cvar_SoloPriority = CreateConVar("tfdb_SoloPriority", "1", "Gives solo players priority before NER players", _, true, 0.0, true, 1.0);
	g_Cvar_HornSound = CreateConVar("tfdb_HornSoundLevel", "0.5", "Volume level of the horn played when respawning players", _, true, 0.0, true, 1.0);
	g_Cvar_RespawnProtection = CreateConVar("tfdb_RespawnProtection", "2.0", "Amount of time that a player is protected for after respawning", _, true, 0.0);
	
	g_Cvar_SeeBotsAsPlayers = CreateConVar("NER_BotDebug", "0", "Makes it so that NER plugin ignores bots & view them as players.", _, true, 0.0, true, 1.0);

	g_pMyWearables = view_as<Address>(FindSendPropInfo("CTFPlayer", "m_hMyWearables"));
}

public void OnConfigsExecuted()
{
	g_soloQueue = new ArrayStack(sizeof(g_iLastDeadTeam));

	if (g_Cvar_ForceNERstartMap.BoolValue)
		g_bNERenabled = true;
	
	HookEvent("arena_round_start", OnSetupFinished, EventHookMode_PostNoCopy);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	HookEvent("teamplay_round_win", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("teamplay_round_stalemate", OnRoundEnd, EventHookMode_PostNoCopy);

	HookConVarChange(g_Cvar_NERenabled, ConVarChanged);
	HookConVarChange(g_Cvar_SoloEnabled, ConVarChanged);

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i))
			SDKHook(i, SDKHook_OnTakeDamage, OnClientTakesDamage);

	PrecacheSound(SOUND_NER_RESPAWNED, true);
}

public void OnMapEnd()
{
	g_soloQueue.Clear();
	delete g_soloQueue;

	UnhookEvent("arena_round_start", OnSetupFinished, EventHookMode_PostNoCopy);
	UnhookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	UnhookEvent("teamplay_round_win", OnRoundEnd, EventHookMode_PostNoCopy);
	UnhookEvent("teamplay_round_stalemate", OnRoundEnd, EventHookMode_PostNoCopy);

	UnhookConVarChange(g_Cvar_NERenabled, ConVarChanged);
	UnhookConVarChange(g_Cvar_SoloEnabled, ConVarChanged);
}

public void OnClientPutInServer(int iClient)
{
	g_bSoloEnabled[iClient] = false;

	if (iClient > 0 && IsClientInGame(iClient))
		SDKHook(iClient, SDKHook_OnTakeDamage, OnClientTakesDamage);
}

public void OnClientDisconnect(int iClient)
{
	g_bSoloEnabled[iClient] = false;
}

public void ConVarChanged(ConVar hConVar, const char[] strOldValue, const char[] strNewValue)
{
	// We should maybe state in chat that it was disabled by convar change
	if (!g_Cvar_NERenabled.BoolValue)
	{
		g_bNERenabled = false;
		CPrintToChatAll("%t", "Dodgeball_NER_Disabled");
	}

	if (!g_Cvar_SoloEnabled.BoolValue)
	{
		for (int iClient = 1; iClient <= MaxClients; iClient++)
		{
			if (g_bSoloEnabled[iClient])
			{
				g_bSoloEnabled[iClient] = false;
				CPrintToChat(iClient, "%t", "Dodgeball_Solo_Toggled_Off");
			}
		}
		g_soloQueue.Clear();
	}
}

public void OnRoundEnd(Event hEvent, char[] strEventName, bool bDontBroadcast)
{
	g_bRoundStarted = false;
}

public void OnSetupFinished(Event hEvent, char[] strEventName, bool bDontBroadcast)
{
	g_soloQueue.Clear();
	g_fLastRespawned = 0.0;

	g_iBot = GetBotClient();

	char buffer[512], namebuffer[64]; // Buffer to store all names of soloer's

	int iRedTeamCount = GetTeamClientCount(view_as<int>(TFTeam_Red));
	int iBlueTeamCount = GetTeamClientCount(view_as<int>(TFTeam_Blue));

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsValidClient(iClient)) continue;
		
		if (g_bSoloEnabled[iClient] && !IsSpectatorTeam(iClient))
		{
			// There are other players that are not solo'd (as of yet)
			if ((GetClientTeam(iClient) == view_as<int>(TFTeam_Red) ? --iRedTeamCount : --iBlueTeamCount) > 0)
			{
				// Avoiding trailing ", "
				if (g_soloQueue.Empty)
					Format(namebuffer, sizeof(namebuffer), "%N", iClient);
				else
					Format(namebuffer, sizeof(namebuffer), ", %N", iClient);

				StrCat(buffer, sizeof(buffer), namebuffer);
				
				g_soloQueue.Push(iClient);
				ForcePlayerSuicide(iClient);
			}
			// This person is last alive in team after all solo's, can't solo
			else
			{
				g_bSoloEnabled[iClient] = false;
				CPrintToChat(iClient, "%t", "Dodgeball_Solo_Not_Possible_No_Teammates");
			}
		}
	}

	// Announce soloers in chat
	if (!g_soloQueue.Empty)
		CPrintToChatAll("%t", "Dodgeball_Solo_Announce_All_Soloers", buffer);

	g_bRoundStarted = true;
}

public void OnPlayerDeath(Event hEvent, char[] strEventName, bool bDontBroadcast)
{
	if (!g_bRoundStarted) return; // Probably not needed, although if we do not do this then in preround you can force people on your team if it's 1v2

	if (g_Cvar_ForceNER.BoolValue)
		g_bNERenabled = true;

	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
	g_iLastDeadTeam = GetClientTeam(iClient);
	
	// If it is a 1v1 (someone left / went to spectator, disable NER)
	if (g_bNERenabled && GetTeamClientCount(g_iLastDeadTeam) <= 1 && GetTeamClientCount(AnalogueTeam(g_iLastDeadTeam)) <= 1)
	{
		CPrintToChatAll("%t", "Dodgeball_NER_Not_Enough_Players_Disabled");
		g_fNERvoteTime = 0.0;
		g_bNERenabled = false;
	}

	if (GetTeamAliveCount(g_iLastDeadTeam) == 1)
	{

		// Switch people's team until 1 player left if NER
		if (g_bNERenabled && GetTeamAliveCount(AnalogueTeam(g_iLastDeadTeam)) > 1)
		{
			// Give solo players priority before switching alive players
			if (g_Cvar_SoloPriority.BoolValue && !g_soloQueue.Empty)
			{
				int iSoloer = g_soloQueue.Pop();

				// Handles people who don't have solo enabled anymore, but are still left in queue
				while (!g_soloQueue.Empty)
				{
					if (!g_bSoloEnabled[iSoloer] || IsSpectatorTeam(iSoloer) || IsPlayerAlive(iSoloer))
						iSoloer = g_soloQueue.Pop();
					else
						break;
				}

				if (g_bSoloEnabled[iSoloer] && !IsSpectatorTeam(iSoloer) && !IsPlayerAlive(iSoloer))
				{
					// Respawn solo player
					ChangeClientTeam(iSoloer, g_iLastDeadTeam);
					TF2_RespawnPlayer(iSoloer);

					g_fLastRespawned = GetGameTime();

					EmitSoundToClient(iSoloer, SOUND_NER_RESPAWNED, _, _, _, _, g_Cvar_HornSound.FloatValue);

					return;
				}
			}

			int iRandomOpponent = GetTeamRandomAliveClient(AnalogueTeam(g_iLastDeadTeam));
			g_iOldTeam[iRandomOpponent] = AnalogueTeam(g_iLastDeadTeam);
		
			ChangeAliveClientTeam(iRandomOpponent, g_iLastDeadTeam);

			return;
		}
		// If no one can be switched (or NER not enabled) respawn solo players (who didn't have priority)
		else if (!g_soloQueue.Empty)
		{
			int iSoloer = g_soloQueue.Pop();

			// Handles people who don't have solo enabled anymore, but are still left in queue
			while (!g_soloQueue.Empty)
			{
				if (!g_bSoloEnabled[iSoloer] || IsSpectatorTeam(iSoloer) || IsPlayerAlive(iSoloer))
					iSoloer = g_soloQueue.Pop();
				else
					break;
			}
			
			if (g_bSoloEnabled[iSoloer] && !IsSpectatorTeam(iSoloer) && !IsPlayerAlive(iSoloer))
			{
				// Respawn solo player
				ChangeClientTeam(iSoloer, g_iLastDeadTeam);
				TF2_RespawnPlayer(iSoloer);

				g_fLastRespawned = GetGameTime();

				EmitSoundToClient(iSoloer, SOUND_NER_RESPAWNED, _, _, _, _, g_Cvar_HornSound.FloatValue);

				return;
			}
		}

		// Both teams had 1 player left, no soloers & no can be switched so respawn everyone
		if (g_bNERenabled && GetTeamAliveCount(AnalogueTeam(g_iLastDeadTeam)) == 1)
		{
			// Let round end if bot voted off & round didn't forcefully end
			if (g_iBot != GetBotClient())
				return;

			char buffer[512], namebuffer[64]; // keeping track of soloer names

			int iTotalPlayers = 0; // Not solo, or round loser / winner

			// For solo
			g_soloQueue.Clear();
			int iWinner = GetTeamRandomAliveClient(AnalogueTeam(g_iLastDeadTeam));
			int iMarkedSoloer = 0;

			// Add to list to be reshuffled & respawned			
			for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
			{
				if (!IsClientInGame(iPlayer) || IsSpectatorTeam(iPlayer))
					continue;

				int iLifeState = GetEntProp(iPlayer, Prop_Send, "m_lifeState");

				// Winner & loser not in here
				if (iLifeState && iPlayer != g_iBot)
					// Mark soloers to avoid round end, otherwise add to shuffle list
					if (!g_bSoloEnabled[iPlayer])
						g_iAllPlayers[iTotalPlayers++] = iPlayer;
					else
						iMarkedSoloer = iPlayer;
			}

			// No players available, remove someone from solo
			if (!iTotalPlayers)
			{
				// This client should never be 0, as our earlier check would've ended solo if 1v1
				g_iAllPlayers[iTotalPlayers++] = iMarkedSoloer;

				g_bSoloEnabled[iMarkedSoloer] = false;
				CPrintToChat(iMarkedSoloer, "%t", "Dodgeball_Solo_Not_Possible_NER_Would_End");
			}

			// If it's player v bot then respawn on 1 side, otherwise randomize
			int iNewTeam;
			if (g_iBot)
				iNewTeam = AnalogueTeam(GetClientTeam(g_iBot));
			else
				iNewTeam = g_iLastDeadTeam;

			// fisher yates shuffle & respawn, start respawning for last dead team to avoid round end
			for (int i = iTotalPlayers - 1; i >= 0; i--)
			{						
				int j = GetRandomInt(0, i);

				ChangeClientTeam(g_iAllPlayers[j], iNewTeam);
				TF2_RespawnPlayer(g_iAllPlayers[j]);
				
				if (!g_iBot)
					iNewTeam = AnalogueTeam(iNewTeam);
					
				g_iAllPlayers[j] = g_iAllPlayers[i];
			}

			// For some reason randomly some people do not get respawned, do not know if issue persists after refactoring (post 1.3.1)
			// Keeping it in, as the issue is likely not resolved yet
			for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
			{
				if (!IsValidClient(iPlayer) || IsSpectatorTeam(iPlayer) || g_bSoloEnabled[iPlayer])
					continue;
				
				if (!IsPlayerAlive(iPlayer))
				{
					ChangeClientTeam(iPlayer, iNewTeam);
					TF2_RespawnPlayer(iPlayer);

					if (!g_iBot)
						iNewTeam = AnalogueTeam(iNewTeam);
				}
			}

			// Red & blue players count changed, we do not switch the winner
			int iRedTeamCount = GetTeamClientCount(view_as<int>(TFTeam_Red)) - 1;
			int iBlueTeamCount = GetTeamClientCount(view_as<int>(TFTeam_Blue)) - 1;

			// message all solo players that they weren't respawned & push back to queue
			for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
			{
				if (!IsClientInGame(iPlayer) || IsSpectatorTeam(iPlayer))
					continue;

				if (g_bSoloEnabled[iPlayer] && iPlayer != iWinner)
				{
					if ((GetClientTeam(iPlayer) == view_as<int>(TFTeam_Red) ? iRedTeamCount-- : iBlueTeamCount--) > 0)
					{
						if (g_soloQueue.Empty)
							Format(namebuffer, sizeof(namebuffer), "%N", iPlayer);
						else
							Format(namebuffer, sizeof(namebuffer), ", %N", iPlayer);
		
						StrCat(buffer, sizeof(buffer), namebuffer);

						g_soloQueue.Push(iPlayer);
						
						if (g_Cvar_SoloPriority.BoolValue)
							CPrintToChat(iPlayer, "%t", "Dodgeball_Solo_NER_Notify_Not_Respawned_Mid_round");
						else
							CPrintToChat(iPlayer, "%t", "Dodgeball_Solo_NER_Notify_Not_Respawned");
					}
					else
					{
						g_bSoloEnabled[iPlayer] = false;
						CPrintToChat(iPlayer, "%t", "Dodgeball_Solo_Not_Possible_NER_Would_End");

						TF2_RespawnPlayer(iPlayer);
					}
				}
			}

			if (g_bSoloEnabled[iWinner])
			{
				// Winner is not only one alive in the team, so they can return to solo
				if (GetTeamAliveCount(AnalogueTeam(g_iLastDeadTeam)) > 1)
				{
					if (g_soloQueue.Empty)
						Format(namebuffer, sizeof(namebuffer), "%N", iWinner);
					else
						Format(namebuffer, sizeof(namebuffer), ", %N", iWinner);
			
					StrCat(buffer, sizeof(buffer), namebuffer);

					g_soloQueue.Push(iWinner);

					if (g_Cvar_SoloPriority.BoolValue)
						CPrintToChat(iWinner, "%t", "Dodgeball_Solo_NER_Notify_Not_Respawned_Mid_round");
					else
						CPrintToChat(iWinner, "%t", "Dodgeball_Solo_NER_Notify_Not_Respawned");

					ForcePlayerSuicide(iWinner);
				}
				// Can't solo, last in team
				else
				{
					g_bSoloEnabled[iWinner] = false;
					CPrintToChat(iWinner, "%t", "Dodgeball_Solo_Not_Possible_NER_Would_End");
					SetEntityHealth(iWinner, 175);
				}
			}
			else
				SetEntityHealth(iWinner, 175);

			// We have to respawn the last player 1 frame later, as they haven't died yet (since this is a PRE hook)
			if (g_bSoloEnabled[iClient])
				RequestFrame(RespawnPlayerCallback, 0);
			else
				RequestFrame(RespawnPlayerCallback, iClient); 

			if (!g_soloQueue.Empty)
				CPrintToChatAll("%t", "Dodgeball_Solo_Announce_All_Soloers", buffer);
		}
	}
}

void RespawnPlayerCallback(any aData)
{
	if (aData)
		TF2_RespawnPlayer(aData);

	g_fLastRespawned = GetGameTime();

	// We only notify non-solo players of being respawned
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!g_bSoloEnabled[iClient] && IsValidClient(iClient))
			EmitSoundToClient(iClient, SOUND_NER_RESPAWNED, _, _, _, _, g_Cvar_HornSound.FloatValue);
	}
}

public Action OnClientTakesDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
	if (GetGameTime() < g_fLastRespawned + g_Cvar_RespawnProtection.FloatValue && IsValidClient(victim))
	{
		damage = 0.0;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

int GetTeamAliveCount(int iTeam)
{
	int iCount;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidClient(iClient) && (GetClientTeam(iClient) == iTeam))
			iCount++;
	}

	return iCount;
}

int GetBotClient()
{
	// Shouldn't really use this 'shortcut',
	// we should probably also check if bot is not in spectator or something along those lines
	if (g_Cvar_SeeBotsAsPlayers.BoolValue)
		return 0;

	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient) && IsFakeClient(iClient))
			return iClient;
	}
	
	return 0;
}

int GetTeamRandomAliveClient(int iTeam)
{
	int[] iClients = new int[MaxClients];
	int iCount;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient)) continue;
		
		if ((GetClientTeam(iClient) == iTeam) && IsPlayerAlive(iClient))
			iClients[iCount++] = iClient;
	}
	
	return iCount == 0 ? -1 : iClients[GetRandomInt(0, iCount - 1)];
}

// "sm_solo"
public Action CmdSolo(int iClient, int iArgs)
{
	if (!iClient)
	{
		PrintToServer("Command is in game only.");

		return Plugin_Handled;
	}

	if (!g_Cvar_SoloEnabled.BoolValue)
	{
		CReplyToCommand(iClient, "%t", "Solo_Not_Allowed");

		return Plugin_Handled;
	}

	// Disable solo mode
	if (g_bSoloEnabled[iClient])
	{
		CPrintToChat(iClient, "%t", "Dodgeball_Solo_Toggled_Off");
		g_bSoloEnabled[iClient] = false;
	}
	// Last alive, we can not active solo mode in this state
	else if (IsValidClient(iClient) && GetTeamAliveCount(GetClientTeam(iClient)) == 1)
	{
		CPrintToChat(iClient, "%t", "Dodgeball_Solo_Not_Possible_Last_Alive");
	}
	// Activate solo mode
	else
	{
		// Alive, kill player & add to queue
		if (IsValidClient(iClient) && g_bRoundStarted)
		{
			g_soloQueue.Push(iClient);
			ForcePlayerSuicide(iClient);
		}

		CPrintToChat(iClient, "%t", "Dodgeball_Solo_Toggled_On");
		g_bSoloEnabled[iClient] = true;
	}

	return Plugin_Continue;
}

// "sm_ner"
public Action CmdToggleNER(int iClient, int iArgs)
{
	if (!g_Cvar_NERenabled.BoolValue)
	{
		CReplyToCommand(iClient, "%t", "NER_Not_Allowed");

		return Plugin_Handled;
	}

	ToggleNER();

	return Plugin_Handled;
}

// "sm_votener"
public Action CmdVoteNER(int iClient, int iArgs)
{
	if (!g_Cvar_NERenabled.BoolValue)
	{
		CReplyToCommand(iClient, "%t", "NER_Not_Allowed");

		return Plugin_Handled;
	}

	if (!g_fNERvoteTime && g_fNERvoteTime + g_Cvar_NERvotingTimeout.FloatValue > GetGameTime())
	{
		CReplyToCommand(iClient, "%t", "Dodgeball_NERVote_Cooldown", g_fNERvoteTime + g_Cvar_NERvotingTimeout.FloatValue - GetGameTime());

		return Plugin_Handled;
	}

	if (IsVoteInProgress())
	{
		CReplyToCommand(iClient, "%t", "Dodgeball_Vote_Conflict");
		
		return Plugin_Handled;
	}

	char strMode[16];
	strMode = g_bNERenabled ? "Disable" : "Enable";
	
	Menu hMenu = new Menu(VoteMenuHandler);
	hMenu.VoteResultCallback = VoteResultHandler;
	
	hMenu.SetTitle("%s NER mode?", strMode);
	
	hMenu.AddItem("0", "Yes");
	hMenu.AddItem("1", "No");
	
	int iTotal;
	int[] iClients = new int[MaxClients];
	
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer))
			continue;

		iClients[iTotal++] = iPlayer;
	}
	
	hMenu.DisplayVote(iClients, iTotal, 10);

	g_fNERvoteTime = GetGameTime();
	return Plugin_Handled;
}

void ToggleNER()
{
	//TFDB_DestroyRockets(); // If we include <tfdb> we can destroy all rockets

	if (!g_bNERenabled)
	{
		CPrintToChatAll("%t", "Dodgeball_NER_Enabled");

		g_bNERenabled = true;
		return;
	}

	CPrintToChatAll("%t", "Dodgeball_NER_Disabled");
	g_bNERenabled = false;
}

// ---- Voting handler ------------------------------
public int VoteMenuHandler(Menu hMenu, MenuAction iMenuActions, int iParam1, int iParam2)
{
	if (iMenuActions == MenuAction_End)
		delete hMenu;
	
	return 0;
}

public void VoteResultHandler(Menu hMenu, int iNumVotes, int iNumClients, const int[][] iClientInfo, int iNumItems, const int[][] iItemInfo)
{
	int iWinnerIndex = 0;
	
	// Equal votes so we choose a random winner (with 1 vote for enabling)
	if (iNumItems > 1 && (iItemInfo[0][VOTEINFO_ITEM_VOTES] == iItemInfo[1][VOTEINFO_ITEM_VOTES]))
		iWinnerIndex = GetRandomInt(0, 1);
	
	char strWinner[8];
	hMenu.GetItem(iItemInfo[iWinnerIndex][VOTEINFO_ITEM_INDEX], strWinner, sizeof(strWinner));
	
	// We use the same result handler, so we need to check what to enable
	if (StrEqual(strWinner, "0"))
		ToggleNER();
	else
		CPrintToChatAll("%t", "Dodgeball_NERVote_Failed");
}

bool IsValidClient(int iClient)
{
	if (iClient > 0)
		return IsClientInGame(iClient) && IsPlayerAlive(iClient);
	return false;
}

bool IsSpectatorTeam(int iClient)
{	
	return GetClientTeam(iClient) == view_as<int>(TFTeam_Spectator) || GetClientTeam(iClient) == view_as<int>(TFTeam_Unassigned);
}

void ChangeAliveClientTeam(int iClient, int iTeam)
{
	// Changing players team whilst keeping them alive
	SetEntProp(iClient, Prop_Send, "m_lifeState", 2);
	ChangeClientTeam(iClient, iTeam);
	SetEntProp(iClient, Prop_Send, "m_lifeState", 0);
	
	// Fixing colour of cosmetic(s) not changing
	int iWearable;
	int iWearablesCount = GetPlayerWearablesCount(iClient);

	Address pData = DereferencePointer(GetEntityAddress(iClient) + g_pMyWearables);
	
	for (int iIndex = 0; iIndex < iWearablesCount; iIndex++)
	{
		iWearable = LoadEntityHandleFromAddress(pData + view_as<Address>(0x04 * iIndex));
		
		SetEntProp(iWearable, Prop_Send, "m_nSkin", (iTeam == view_as<int>(TFTeam_Blue)) ? 1 : 0);
		SetEntProp(iWearable, Prop_Send, "m_iTeamNum", iTeam);
	}
}

/*
	https://github.com/nosoop/SM-TFUtils/blob/master/scripting/tf2utils.sp
	https://github.com/nosoop/stocksoup/blob/master/memory.inc
*/

int LoadEntityHandleFromAddress(Address pAddress)
{
	return EntRefToEntIndex(LoadFromAddress(pAddress, NumberType_Int32) | (1 << 31));
}

Address DereferencePointer(Address pAddress)
{
	// maybe someday we'll do 64-bit addresses
	return view_as<Address>(LoadFromAddress(pAddress, NumberType_Int32));
}

int GetPlayerWearablesCount(int iClient)
{
	return GetEntData(iClient, view_as<int>(g_pMyWearables) + 0x0C);
}