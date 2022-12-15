#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <clientprefs>
#include <mapchooser_unlimited>
#include <csgocolors_fix>

#define PLUGIN_VERSION "1.2.2"

public Plugin myinfo =
{
    name = "Nominations Unlimited",
    author = "tilgep (Based on plugin by Powerlord and AlliedModders LLC)",
    description = "Nominations allowing votes for everyone.",
    version = PLUGIN_VERSION,
    url = "https://www.github.com/tilgep/"
};

bool g_bLateLoad = false;

Cookie g_cookie_Nomban;         //Format("length:timeIssued")
Cookie g_cookie_NombanAdmin;    //Admin who gave the nomban

#define NOMBAN_NOTBANNED -1
#define NOMBAN_PERMANENT 0
int g_iNomBanLength[MAXPLAYERS+1];
int g_iNomBanStart[MAXPLAYERS+1];
char g_sNomBanAdmin[MAXPLAYERS+1][PLATFORM_MAX_PATH];

ArrayList g_MapList;

ConVar g_cv_Enabled;
ConVar g_cv_NominationDelay;
ConVar g_cv_ClientNomDelay;
ConVar g_cv_NomAnnounceInterval;
ConVar g_cv_AnnounceToClient;
ConVar g_cv_RemoveNomOnNomban;
ConVar g_cv_ShowNomInConsole;
ConVar g_cv_ShowCooldown;

bool g_bEnabled = true;         //Is nominating allowed

int g_iSerial;
int g_iNominationDelay;              //Inital time to start allowing noms
int g_iClientNomDelay[MAXPLAYERS+1]; //Last time a client nominated

public void OnPluginStart()
{
    if(GetEngineVersion() != Engine_CSGO)
    {
        LogMessage("This plugin is only tested and supported on CSGO! Beware of bugs!");
        PrintToServer("This plugin is only tested and supported on CSGO! Beware of bugs!");
    }

    LoadTranslations("common.phrases"); //For nomban FindTarget
    LoadTranslations("mapchooser_unlimited.phrases");
    LoadTranslations("nominations_unlimited.phrases");

    /* Client commands */
    RegConsoleCmd("sm_nominate", Command_Nominate, "Nominate a map.");
    RegConsoleCmd("sm_nom", Command_Nominate, "Nominate a map.");

    RegConsoleCmd("sm_unnominate", Command_UnNominate, "Removes your nomination");
    RegConsoleCmd("sm_unominate", Command_UnNominate, "Removes your nomination");
    RegConsoleCmd("sm_unnom", Command_UnNominate, "Removes your nomination");
    RegConsoleCmd("sm_unom", Command_UnNominate, "Removes your nomination");

    RegConsoleCmd("sm_nomlist", Command_Nomlist, "Shows a list of currently nominated maps");
    RegConsoleCmd("sm_noms", Command_Nomlist, "Shows a list of currently nominated maps");

    RegConsoleCmd("sm_nomstatus", Command_NomStatus, "Shows your current nomban status.");

    /* Admin commands */
    RegAdminCmd("sm_nomenable", Command_Enable, ADMFLAG_BAN, "Enables nominating.", "nom_enable");
    RegAdminCmd("sm_enablenom", Command_Enable, ADMFLAG_BAN, "Enables nominating.", "nom_enable");

    RegAdminCmd("sm_nomdisable", Command_Disable, ADMFLAG_BAN, "Disables nominating.", "nom_disable");
    RegAdminCmd("sm_disablenom", Command_Disable, ADMFLAG_BAN, "Disables nominating.", "nom_disable");

    RegAdminCmd("sm_adminnom", Command_Insert, ADMFLAG_BAN, "Insert a map into the nomlist.",                   "nom_admin");
    RegAdminCmd("sm_adminom", Command_Insert, ADMFLAG_BAN, "Insert a map into the nomlist.",                    "nom_admin");
    RegAdminCmd("sm_nominate_addmap", Command_Insert, ADMFLAG_BAN, "Insert a map into the nomlist.",            "nom_admin");
    RegAdminCmd("sm_adminom", Command_Insert, ADMFLAG_BAN, "Insert a map into the nomlist.",                    "nom_admin");
    RegAdminCmd("sm_insertmap", Command_Insert, ADMFLAG_BAN, "Insert a map into the nomlist.",                  "nom_admin");

    RegAdminCmd("sm_adminunnom", Command_UnInsert, ADMFLAG_BAN, "Removes an inserted map from the nomlist.",    "nom_admin");
    RegAdminCmd("sm_uninsert", Command_UnInsert, ADMFLAG_BAN, "Removes an inserted map from the nomlist.",      "nom_admin");

    RegAdminCmd("sm_removenom", Command_RemoveNom, ADMFLAG_BAN, "Removes a given clients nomination.");

    RegAdminCmd("sm_nomban", Command_Nomban, ADMFLAG_BAN, "Ban a client from nominating.",              "nomban");
    RegAdminCmd("sm_nombanlist", Command_NombanList, ADMFLAG_BAN, "View a list of nombanned clients.",  "nomban");
    RegAdminCmd("sm_unnomban", Command_UnNomban, ADMFLAG_BAN, "Unban a client from nominating.",        "nomban");
    RegAdminCmd("sm_nomunban", Command_UnNomban, ADMFLAG_BAN, "Unban a client from nominating.",        "nomban");
    RegAdminCmd("sm_unomban", Command_UnNomban, ADMFLAG_BAN, "Unban a client from nominating.",         "nomban");

    RegAdminCmd("sm_addmapvotes", Command_AddMapVotes, ADMFLAG_ROOT, "Set's a map's votes (Used for testing)");

    g_cv_Enabled = CreateConVar("nominate_enabled", "1", "Is nominating enabled.", _, true, 0.0, true, 1.0);
    g_cv_NominationDelay = CreateConVar("nominate_initialdelay", "60.0", "Time in seconds before first Nomination can be made.", _, true, 0.0);
    g_cv_ClientNomDelay = CreateConVar("nominate_clientdelay", "10", "Number of seconds a client must wait before making another nomination.", _, true, 0.0);
    g_cv_NomAnnounceInterval = CreateConVar("nominate_announce_interval", "1", "When a map gets nominated in infinite mode, it will announce to all only if the number of votes can be divided by this value, it will always announce first vote. (0 = only announce first vote, -1 = never announce to all)", _, true, -1.0);
    g_cv_AnnounceToClient = CreateConVar("nominate_clientannounce", "1", "Should the client receive a message about their nomination if it doesnt print to all.", _, true, 0.0, true, 1.0);
    g_cv_ShowNomInConsole = CreateConVar("nominate_console", "1", "Should every nomination be printed into client consoles", _, true, 0.0, true, 1.0);
    g_cv_RemoveNomOnNomban = CreateConVar("nominate_banclear", "1", "Should a client's nomination be removed when they get nombanned.", _,true, 0.0, true, 1.0);
    g_cv_ShowCooldown = CreateConVar("nominate_showcooldown", "1", "Whether the current cooldown for maps should be shown in the nominate menu (1=enabled, 0=disabled)", _, true, 0.0, true, 1.0);

    AutoExecConfig(true, "nominations_unlimited");

    g_cookie_Nomban = RegClientCookie("nomban_status", "Client's nomban info", CookieAccess_Private);
    g_cookie_NombanAdmin = RegClientCookie("nomban_admin", "Admin who nombanned", CookieAccess_Private);

    if(g_bLateLoad)
    {
        for(int i = 1; i <= MaxClients; i++)
        {
            if(IsClientInGame(i) && !IsFakeClient(i) && AreClientCookiesCached(i))
            {
                OnClientCookiesCached(i);
            }
        }
    }

    g_MapList = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(LibraryExists("nominations"))
    {
        strcopy(error, err_max, "Nominations already loaded! Aborting.");
        return APLRes_Failure;
    }
    RegPluginLibrary("nominations");
    g_bLateLoad = late;
    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    if(!LibraryExists("mapchooser"))
    {
        SetFailState("Mapchooser not found! It is required for this plugin to work!");
    }
}

public void OnConfigsExecuted()
{
    LoadMaplist();
    g_iNominationDelay = GetTime() + g_cv_NominationDelay.IntValue;
    g_bEnabled = g_cv_Enabled.BoolValue;
}

public void OnMapListReloaded()
{
    LoadMaplist();
}

bool LoadMaplist()
{
    if(ReadMapList(g_MapList, g_iSerial, "mapchooser", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) != INVALID_HANDLE)
    {
        if(g_iSerial == -1)
        {
            LogError("Unable to create a valid map list.");
            return false;
        }
        return true;
    }
    return false;
}

public void OnClientPutInServer(int client)
{
    if(!AreClientCookiesCached(client))
    {
        g_iNomBanLength[client] = NOMBAN_NOTBANNED;
        g_iNomBanStart[client] = NOMBAN_NOTBANNED;
    }
}

public void OnClientDisconnect(int client)
{
    SaveClientNombanStatus(client);
}

public void OnClientCookiesCached(int client)
{
    char sCookie[128];
    GetClientCookie(client, g_cookie_Nomban, sCookie, sizeof(sCookie));

    if(StrEqual(sCookie, ""))
    {
        g_iNomBanStart[client] = NOMBAN_NOTBANNED;
        g_iNomBanLength[client] = NOMBAN_NOTBANNED;
        return;
    }

    char sBuffer[2][64];
    ExplodeString(sCookie, ":", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]), true);
    g_iNomBanLength[client] = StringToInt(sBuffer[0]);
    g_iNomBanStart[client] = StringToInt(sBuffer[1]);

    if(IsClientNomBanned(client))
    {
        RemoveNominationByOwner(client, Removed_Ignore);
    }
}

/* ====================================================== */
/* ====================================================== */

/*                    Command Callbacks                   */

/* ====================================================== */
/* ====================================================== */

public Action Command_Nominate(int client, int args)
{
    if(!CanClientNominate(client))
    {
        return Plugin_Handled;
    }

    CanNominateResult canNom = CanNominate(client);
    if(canNom != CanNominate_Yes)
    {
        switch(canNom)
        {
            case CanNominate_VoteComplete:
            {
                CReplyToCommand(client, "%t %t", "NPrefix", "Cannot Nominate - Vote Complete");
            }
            case CanNominate_VoteInProgress:
            {
                CReplyToCommand(client, "%t %t", "NPrefix", "Cannot Nominate - Vote In Progress");
            }
            case CanNominate_VoteFull:
            {
                CReplyToCommand(client, "%t %t", "NPrefix", "Cannot Nominate - Vote Full");
            }
        }
        return Plugin_Handled;
    }

    if(args == 0)
    {
        AttemptNominate(client);
        return Plugin_Handled;
    }

    if(g_iClientNomDelay[client] > GetTime())
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Wait to nominate", g_iClientNomDelay[client] - GetTime());
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArgString(map, sizeof(map));
    ReplaceString(map, sizeof(map), " ", "_", false);
    StripQuotes(map);

    if(StrEqual(map, "_random"))
    {
        Format(map, sizeof(map), "%s", GetRandomMap(client));
    }

    if(FindStringInArray(g_MapList, map) == -1 || !IsMapValid(map))
    {
        //Check if only 1 map matches pattern before saying not found
        if(!AttemptNominate(client, map)) 
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Map was not found", map);
            return Plugin_Handled;
        }
    }

    int status = CanMapBeNominated(client, map);

    if((status & CanClientNom_Yes) == CanClientNom_Yes)
    {
        NominateResult result = NominateMap(client, map, false);
        
        //Successful nomination prints in OnMapNominated
        if(result == Nominate_InvalidMap)
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Map was not found", map);
            LogMessage("Map not found %s", map);
        }
        else if(result == Nominate_VoteFull)
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Cannot Nominate - Vote Full");
        }

        return Plugin_Handled;
    }

    /* Map cannot be nominated - Lets tell the client why */

    if((status & CanClientNom_CurrentMap) == CanClientNom_CurrentMap)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Current map");
        return Plugin_Handled;
    }

    if((status & CanClientNom_CurrentNom) == CanClientNom_CurrentNom)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Current nomination", map);
        return Plugin_Handled;
    }

    if((status & CanClientNom_Inserted) == CanClientNom_Inserted)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Already Inserted", map);
        return Plugin_Handled;
    }

    if((status & CanClientNom_Nominated) == CanClientNom_Nominated)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Already Nominated", map);
        return Plugin_Handled;
    }

    if((status & CanClientNom_AdminOnly) == CanClientNom_AdminOnly)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Admin Only Nominating", map);
        return Plugin_Handled;
    }

    if((status & CanClientNom_Cooldown) == CanClientNom_Cooldown)
    {
        if(g_cv_ShowCooldown.BoolValue)
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Map is on cooldown", map, GetMapCooldown(map));
        }
        else
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Map is on cooldown - No Value", map);
        }
        return Plugin_Handled;
    }

    if((status & CanClientNom_NotEnoughPlayers) == CanClientNom_NotEnoughPlayers)
    {
        int players = GetMapPlayerRestriction(map) * -1;
        CReplyToCommand(client, "%t %t", "NPrefix", "Map needs more players", map, players);
        return Plugin_Handled;
    }

    if((status & CanClientNom_TooManyPlayers) == CanClientNom_TooManyPlayers)
    {
        int players = GetMapPlayerRestriction(map) * -1;
        CReplyToCommand(client, "%t %t", "NPrefix", "Map needs fewer players", map, players);
        return Plugin_Handled;
    }

    if((status & CanClientNom_Time) == CanClientNom_Time)
    {
        
        int minutes = GetMapTimeRestriction(map);
        if(minutes >= 60)
        {
            int hours = minutes / 60;
            minutes = minutes % 60;
            CReplyToCommand(client, "%t %t", "NPrefix", "Nominate Time Restriction - Hours", map, hours, minutes);
        }
        else
        {
            CReplyToCommand(client, "%t %t", "NPrefix", "Nominate Time Restriction - Minutes", map, minutes);
        }
        
        return Plugin_Handled;
    }

    CReplyToCommand(client, "%t %t", "NPrefix", "Error Nominating", map);

    return Plugin_Handled;
}

public Action Command_UnNominate(int client, int args)
{
    if(args > 0 && CheckCommandAccess(client, "sm_adminnom", ADMFLAG_BAN))
    {
        char sTarget[64];
        GetCmdArg(1, sTarget, sizeof(sTarget));

        int target = FindTarget(client, sTarget);

        if(target > 0)
        {
            if(!RemoveNominationByOwner(client, Removed_AdminClear))
            {
                CReplyToCommand(client, "%t %t", "NPrefix", "Unable To Unnominate Admin", target);
            }
        }
        return Plugin_Handled;
    }

    if(!RemoveNominationByOwner(client, Removed_UnNominated))
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Unable To Unnominate");
    }
    //OnNominationRemoved will print to all if it gets removed

    return Plugin_Handled;
}

public Action Command_Nomlist(int client, int args)
{
    if(client == 0)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Can only use command in game");
        return Plugin_Handled;
    }

    PrepareNomlistMenu(client);

    return Plugin_Handled;
}

public Action Command_NomStatus(int client, int args)
{
    if(client == 0)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Can only use command in game");
        return Plugin_Handled;
    }

    int target = client;

    if(args > 0)
    {
        char targ[64];
        GetCmdArg(1, targ, sizeof(targ));
        target = FindTarget(client, targ);
    }

    if(!AreClientCookiesCached(target))
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Cookies are not cached");
        return Plugin_Handled;
    }

    PrepareNomStatusMenu(client, target);

    return Plugin_Handled;
}

public Action Command_Enable(int client, int args)
{
    if(g_bEnabled)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Nominating already enabled");
        return Plugin_Handled;
    }

    g_bEnabled = true;

    LogAction(client, -1, "%L enabled nominating.", client);
    CPrintToChatAll("%t %t", "NPrefix", "Nominating Enabled");
    return Plugin_Handled;
}

public Action Command_Disable(int client, int args)
{
    if(!g_bEnabled)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Nominating already disabled");
        return Plugin_Handled;
    }

    g_bEnabled = false;

    LogAction(client, -1, "%L disabled nominating.", client);
    CPrintToChatAll("%t %t", "NPrefix", "Nominating Disabled");
    return Plugin_Handled;
}

public Action Command_Insert(int client, int args)
{
    CanNominateResult result = CanNominate(client);
    if(result == CanNominate_VoteInProgress)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Cannot insert - Vote in progress");
        return Plugin_Handled;
    }

    if(args == 0)
    {
        AttemptInsert(client);
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(FindStringInArray(g_MapList, map) == -1)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Map was not found", map);
        AttemptInsert(client, map);
        return Plugin_Handled;
    }

    int status = CanMapBeNominated(client, map);

    if((status & CanClientNom_Inserted) == CanClientNom_Inserted)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Already Inserted", map);
        return Plugin_Handled;
    }

    NominateMap(client, map, true);
    /* OnMapInserted handles printing to chat */

    return Plugin_Handled;
}

public Action Command_UnInsert(int client, int args)
{
    if(args < 1)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "UnInsert Usage");
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(FindStringInArray(g_MapList, map) == -1)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Map was not found", map);
        return Plugin_Handled;
    }

    if(!IsMapInserted(map))
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Map is not inserted", map);
        return Plugin_Handled;
    }

    if(RemoveInsertedMap(client, map))
    {
        CPrintToChatAll("%t %t", "NPrefix", "Map Uninserted", client, map);
    }
    else
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Failed to uninsert", map);
    }

    return Plugin_Handled;
}

public Action Command_RemoveNom(int client, int args)
{
    if(args == 0)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "RemoveNom Usage");
        return Plugin_Handled;
    }

    char buffer[64];
    GetCmdArg(1, buffer, sizeof(buffer));

    int target = FindTarget(client, buffer);
    if(target == -1) return Plugin_Handled;

    RemoveNominationByOwner(target, Removed_AdminClear);

    return Plugin_Handled;
}

public Action Command_Nomban(int client, int args)
{
    if(GetCmdArgs() != 2)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Nomban usage");
        return Plugin_Handled;
    }
    
    char target_argument[64];
    GetCmdArg(1, target_argument, sizeof(target_argument));
    
    int target = -1;
    if((target = FindTarget(client, target_argument, true)) == -1)
    {
        return Plugin_Handled;
    }

    if(IsClientNomBanned(target))
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Already nombanned", target);
        return Plugin_Handled;
    }
    
    char sLen[64];
    GetCmdArg(2, sLen, sizeof(sLen));
    int length = StringToInt(sLen);
    
    if(length >= NOMBAN_PERMANENT)
    {
        NomBanClient(target, length*60, client);
    }
    else
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Nomban usage");
    }
        
    return Plugin_Handled;
}

public Action Command_UnNomban(int client, int args)
{
    if(GetCmdArgs() < 1)
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "UnNomban usage");
        return Plugin_Handled;
    }
    
    char target_argument[64];
    GetCmdArg(1, target_argument, sizeof(target_argument));
    
    int target = -1;
    if((target = FindTarget(client, target_argument, true)) == -1)
    {
        return Plugin_Handled;
    }

    if(!IsClientNomBanned(target))
    {
        CReplyToCommand(client, "%t %t", "NPrefix", "Already not nombanned", target);
        return Plugin_Handled;
    }
    
    UnNomBanClient(target, client);
        
    return Plugin_Handled;
}

public Action Command_NombanList(int client, int args)
{
    if(client == 0)
    {
        PrintToServer("--------------------");
        PrintToServer("Nomban List");
        PrintToServer("--------------------");

        for(int i = 1; i <= MaxClients; i++)
        {
            if(!IsClientNomBanned(i)) continue;

            int uid = GetClientUserId(i);

            PrintToServer("[#%d] %N", uid, i);
        }
        PrintToServer("--------------------");
    }
    else
    {
        PrepareNombanListMenu(client);
    }

    return Plugin_Handled;
}

public Action Command_AddMapVotes(int client, int args)
{
    if(args == 0) 
    {
        CPrintToChat(client, "%t Usage: sm_addmapvotes <map> [votes] (dont specify votes to add 1)", "NPrefix");
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(FindStringInArray(g_MapList, map) == -1)
    {
        CPrintToChat(client, "%t %t", "NPrefix", "Map was not found", map);
        return Plugin_Handled;
    }

    int add = 1;
    if(args > 1)
    {
        char buf[16];
        GetCmdArg(2, buf, sizeof(buf));
        int temp = StringToInt(buf);
        if(temp > 1) add = temp;
    }

    for(int i = 0; i < add; i++)
    {
        NominateMap(0, map, false);
    }
    
    int votes = GetMapVotes(map);

    if(votes > 0) CPrintToChatAll("%t Admin added %d votes for map '%s' [%d votes]", "NPrefix", add, map, votes);

    return Plugin_Handled;
}

public void OnNominationRemoved(NominateRemoved reason, const char[] map, int client)
{
    switch(reason)
    {
        case Removed_UnNominated:
        {
            //TODO: Implement same printing logic as nomination
            CPrintToChat(client, "%t %t", "NPrefix", "Nomination Removed - UnNominated", map);
        }
        case Removed_AdminClear:
        {
            CPrintToChat(client, "%t %t", "NPrefix", "Nomination Removed - Admin Removed", map);
        }
        case Removed_NotEnoughPlayers:
        {
            CPrintToChat(client, "%t %t", "NPrefix", "Nomination Removed - Not Enough Players", map);
        }
        case Removed_TooManyPlayers:
        {
            CPrintToChat(client, "%t %t", "NPrefix", "Nomination Removed - Too Many Players", map);
        }
        case Removed_Time:
        {
            CPrintToChat(client, "%t %t", "NPrefix", "Nomination Removed - Time", map);
        }
    }
}

/* ====================================================== */
/* ====================================================== */
/*                         Nominate                       */
/* ====================================================== */
/* ====================================================== */

bool AttemptNominate(int client, char[] filter = "")
{
    Menu menu = CreateMenu(Handler_MapSelectMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
    bool single = BuildMapMenu(menu, filter);

    if(single) return true;
    SetMenuTitle(menu, "%T", "Nominate Menu Title", client);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
    return false;
}

public void OnMapNominated(int client, const char[] map, int votes, bool replaced)
{
    if(client == 0) return;

    g_iClientNomDelay[client] = GetTime() + g_cv_ClientNomDelay.IntValue;

    if(g_cv_ShowNomInConsole.BoolValue)
    {
        char buffer[256];
        if(GetNominationMode() == NominationMode_Limited)
        {
            if(replaced)
            {
                Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated Replaced", client, map);
            }
            else
            {
                Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated", client, map);
            }
        }
        else //Infinite noms
        {
            if(replaced)
            {
                if(votes == 1) Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated Single Replaced", client, map);
                else Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated Multiple Replaced", client, map, votes);
            }
            else
            {
                if(votes == 1) Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated Single", client, map);
                else Format(buffer, sizeof(buffer), "%t %t", "NPrefix", "Player Nominated Multiple", client, map, votes);
            }
        }

        CRemoveTags(buffer, sizeof(buffer));
        PrintToConsoleAll(buffer);
    }

    if(GetNominationMode() == NominationMode_Limited)
    {
        if(replaced)
        {
            CPrintToChatAll("%t %t", "NPrefix", "Player Nominated Replaced", client, map);
        }
        else
        {
            CPrintToChatAll("%t %t", "NPrefix", "Player Nominated", client, map);
        }
        
        return;
    }
    
    if(g_cv_NomAnnounceInterval.IntValue == -1)
    {
        if(g_cv_AnnounceToClient.IntValue == 0) return;

        if(votes==1)
        {
            if(replaced) CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Single Replaced", map);
            else CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Single", map);
            return;
        }

        if(replaced) CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple Replaced", map, votes);
        else CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple", map, votes);
        return;
    }

    if(votes == 1)
    {
        if(replaced) CPrintToChatAll("%t %t", "NPrefix", "Player Nominated Single Replaced", client, map);
        else CPrintToChatAll("%t %t", "NPrefix", "Player Nominated Single", client, map);
        return;
    }

    if(g_cv_NomAnnounceInterval.IntValue == 0)
    {
        if(g_cv_AnnounceToClient.IntValue == 0) return;

        if(replaced) CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple Replaced", map, votes);
        else CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple", map, votes);
        return;
    }

    if(votes % g_cv_NomAnnounceInterval.IntValue == 0)
    {
        if(replaced) CPrintToChatAll("%t %t", "NPrefix", "Player Nominated Multiple Replaced", client, map, votes);
        else CPrintToChatAll("%t %t", "NPrefix", "Player Nominated Multiple", client, map, votes);
        return;
    }

    if(g_cv_AnnounceToClient.IntValue == 0) return;

    if(replaced) CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple Replaced", map, votes);
    else CPrintToChat(client, "%t %t", "NPrefix", "Client Nominated Multiple", map, votes);
}

/* ====================================================== */
/* ====================================================== */
/*                         Nom Menu                       */
/* ====================================================== */
/* ====================================================== */

bool BuildMapMenu(Menu menu, char[] filter)
{
    static char map[PLATFORM_MAX_PATH];
    int count;
    char first[PLATFORM_MAX_PATH];

    for(int i = 0; i < GetArraySize(g_MapList); i++)
    {
        GetArrayString(g_MapList, i, map, sizeof(map));

        if(!filter[0] || StrContains(map, filter, false) != -1)
        {
            AddMenuItem(menu, map, map);
            if(count==0) Format(first,sizeof(first), "%s", map);
            count++;
        }
    }
    
    SetMenuExitButton(menu, true);

    if(count == 1)
    {
        Format(filter, PLATFORM_MAX_PATH, "%s", first);
        return true;
    }
    return false;
}

public int Handler_MapSelectMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            static char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            if(!CanClientNominate(param1)) return 0;

            if(g_iClientNomDelay[param1] > GetTime())
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Wait to nominate", g_iClientNomDelay[param1] - GetTime());
                return 0;
            }

            CanNominateResult canNom = CanNominate(param1);
            if(canNom != CanNominate_Yes)
            {
                switch(canNom)
                {
                    case CanNominate_VoteComplete:
                    {
                        CPrintToChat(param1, "%t %t", "NPrefix", "Cannot Nominate - Vote Complete");
                    }
                    case CanNominate_VoteInProgress:
                    {
                        CPrintToChat(param1, "%t %t", "NPrefix", "Cannot Nominate - Vote In Progress");
                    }
                    case CanNominate_VoteFull:
                    {
                        CPrintToChat(param1, "%t %t", "NPrefix", "Cannot Nominate - Vote Full");
                    }
                }
                return 0;
            }

            int status = CanMapBeNominated(param1, map);

            if((status & CanClientNom_Yes) == CanClientNom_Yes)
            {
                NominateResult result = NominateMap(param1, map, false);
        
                //Successful nomination prints in OnMapNominated
                if(result == Nominate_InvalidMap)
                {
                    CPrintToChat(param1, "%t %t", "NPrefix", "Map was not found", map);
                }
                else if(result == Nominate_VoteFull)
                {
                    CPrintToChat(param1, "%t %t", "NPrefix", "Vote Full");
                }

                return 0;
            }

            /* 
                Map cannot be nominated - Lets tell the client why 
                These should VERY rarely be seen since items are disabled on menu creation
            */

            if((status & CanClientNom_CurrentMap) == CanClientNom_CurrentMap)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Current map");
                return 0;
            }

            if((status & CanClientNom_CurrentNom) == CanClientNom_CurrentNom)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Current nomination", map);
                return 0;
            }

            if((status & CanClientNom_Inserted) == CanClientNom_Inserted)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Already Inserted", map);
                return 0;
            }

            if((status & CanClientNom_Nominated) == CanClientNom_Nominated)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Already Nominated", map);
                return 0;
            }

            if((status & CanClientNom_AdminOnly) == CanClientNom_AdminOnly)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Admin Only Nominating", map);
                return 0;
            }

            if((status & CanClientNom_Cooldown) == CanClientNom_Cooldown)
            {
                if(g_cv_ShowCooldown.BoolValue)
                {
                    CPrintToChat(param1, "%t %t", "NPrefix", "Map is on cooldown", map, GetMapCooldown(map));
                }
                else
                {
                    CPrintToChat(param1, "%t %t", "NPrefix", "Map is on cooldown - No Value", map);
                }
                return 0;
            }

            if((status & CanClientNom_NotEnoughPlayers) == CanClientNom_NotEnoughPlayers)
            {
                int players = GetMapPlayerRestriction(map) * -1;
                CPrintToChat(param1, "%t %t", "NPrefix", "Map needs more players", map, players);
                return 0;
            }

            if((status & CanClientNom_TooManyPlayers) == CanClientNom_TooManyPlayers)
            {
                int players = GetMapPlayerRestriction(map) * -1;
                CPrintToChat(param1, "%t %t", "NPrefix", "Map needs more players", map, players);
                return 0;
            }

            if((status & CanClientNom_Time) == CanClientNom_Time)
            {

                int minutes = GetMapTimeRestriction(map);
                if(minutes >= 60)
                {
                    int hours = minutes / 60;
                    minutes = minutes % 60;
                    CPrintToChat(param1, "%t %t", "NPrefix", "Nominate Time Restriction - Hours", map, hours, minutes);
                }
                else
                {
                    CPrintToChat(param1, "%t %t", "NPrefix", "Nominate Time Restriction - Minutes", map, minutes);
                }
        
                return 0;
            }

            CPrintToChat(param1, "%t %t", "NPrefix", "Error Nominating", map);

            return 0;
        }
        case MenuAction_DrawItem:
        {
            static char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            int status = CanMapBeNominated(param1, map);

            if((status & CanClientNom_Yes) == CanClientNom_Yes)
            {
                return ITEMDRAW_DEFAULT;
            }

            return ITEMDRAW_DISABLED;
        }
        case MenuAction_DisplayItem:
        {
            static char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            int status = CanMapBeNominated(param1, map);

            char display[PLATFORM_MAX_PATH];

            if((status & CanClientNom_CurrentMap) == CanClientNom_CurrentMap)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Current Map", param1);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_CurrentNom) == CanClientNom_CurrentNom)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Current Nom", param1);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_Nominated) == CanClientNom_Nominated)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Nominated", param1);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_Inserted) == CanClientNom_Inserted)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Inserted", param1);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_Cooldown) == CanClientNom_Cooldown)
            {
                if(g_cv_ShowCooldown.BoolValue)
                {
                    Format(display, sizeof(display), "%s %T", map, "Menu Cooldown", param1, GetMapCooldown(map));
                }
                else
                {
                    Format(display, sizeof(display), "%s %T", map, "Menu Cooldown - No Value", param1);
                }
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_NotEnoughPlayers) == CanClientNom_NotEnoughPlayers)
            {
                int players = GetMapPlayerRestriction(map) * -1;
                Format(display, sizeof(display), "%s %T", map, "Menu Not Enough Players", param1, players);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_TooManyPlayers) == CanClientNom_TooManyPlayers)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Too Many Players", param1, GetMapPlayerRestriction(map));
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_Time) == CanClientNom_Time)
            {
                int minutes = GetMapTimeRestriction(map);
                int hours = 0;
                if(minutes >= 60) 
                {
                    hours = minutes / 60;
                    minutes = minutes % 60;
                }
                Format(display, sizeof(display), "%s %T", map, "Menu Time", param1, hours, minutes);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_AdminOnly) == CanClientNom_AdminOnly)
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Admin Only", param1);
                return RedrawMenuItem(display);
            }

            if((status & CanClientNom_GroupMax) == CanClientNom_GroupMax)
            {
                int max = GetMapGroupRestriction(map);
                if(max > 0)
                {
                    Format(display, sizeof(display), "%s %T", map, "Menu Group Max", param1, max);
                    return RedrawMenuItem(display);
                }
            }

            char desc[128];
            if(GetMapDescription(map, desc, sizeof(desc)))
            {
                Format(display, sizeof(display), "%s [%s]", map, desc);
                return RedrawMenuItem(display);
            }
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public bool CanClientNominate(int client)
{
    if(client == 0)
    {
        CPrintToChat(client, "%t %t", "NPrefix", "Can only use command in game");
        return false;
    }

    if(!g_bEnabled || !g_cv_Enabled.BoolValue)
    {
        CPrintToChat(client, "%t %t", "NPrefix", "Nominating Disabled");
        return false;
    }

    if(IsClientNomBanned(client))
    {
        CPrintToChat(client, "%t %t", "NPrefix", "Cannot nominate - Nombanned");
        return false;
    }

    if(g_iNominationDelay > GetTime())
    {
        CPrintToChat(client, "%t %t", "NPrefix", "Nominating not unlocked", g_iNominationDelay - GetTime());
        return false;
    }

    return true;
}

/* ====================================================== */
/* ====================================================== */
/*                         Inserting                      */
/* ====================================================== */
/* ====================================================== */

void AttemptInsert(int client, char[] filter = "")
{
    Menu menu = CreateMenu(Handler_MapInsertMenu, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
    BuildMapMenu(menu, filter);

    SetMenuTitle(menu, "%T", "Insert Menu Title", client);

    DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public void OnMapInserted(int admin, const char[] map)
{
    CPrintToChatAll("%t %t", "NPrefix", "Map inserted", admin, map);
}

/* ====================================================== */
/* ====================================================== */
/*                       Insert Menu                      */
/* ====================================================== */
/* ====================================================== */

public int Handler_MapInsertMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            static char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            if(IsMapVoteInProgress())
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Cannot insert - Vote in progress");
                return 0;
            }

            /* Map cannot be inserted - Lets tell the client why */
            if(IsMapInserted(map))
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "Already Inserted", map);
                return 0;
            }

            if(NominateMap(param1, map, true) == Nominate_Inserted)
            {
                return 0;
            }

            CPrintToChat(param1, "%t %t", "NPrefix", "Error Inserting", map);

            return 0;
        }
        case MenuAction_DrawItem:
        {
            static char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            if(IsMapInserted(map))
            {
                return ITEMDRAW_DISABLED;
            }

            return ITEMDRAW_DEFAULT;
        }
        case MenuAction_DisplayItem:
        {
            static char map[PLATFORM_MAX_PATH];
            char display[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));

            if(IsMapInserted(map))
            {
                Format(display, sizeof(display), "%s %T", map, "Menu Inserted", param1);
                return RedrawMenuItem(display);
            }

            char desc[128];
            if(GetMapDescription(map, desc, sizeof(desc)))
            {
                Format(display, sizeof(display), "%s [%s]", map, desc);
                return RedrawMenuItem(display);
            }
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

/* ====================================================== */
/* ====================================================== */
/*                         Nomlist                        */
/* ====================================================== */
/* ====================================================== */

public void PrepareNomlistMenu(int client)
{
    StringMap noms = CreateTrie();
    int nomCount = GetNominatedMapList(noms);

    ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    int insertions = GetInsertedMapList(maps);

    Menu menu = CreateMenu(Nomlist_Handler);
    menu.SetTitle("%t", "Nomlist Menu Title");

    char map[PLATFORM_MAX_PATH];
    char buffer[PLATFORM_MAX_PATH];

    if(nomCount <= 0 && insertions <= 0)
    {
        Format(buffer, sizeof(buffer), "%T", "Nomlist Menu No Maps", client);
        menu.AddItem("ez", buffer, ITEMDRAW_DISABLED);
        menu.Display(client, MENU_TIME_FOREVER);
        return;
    }

    for(int i = 0; i < insertions; i++)
    {
        GetArrayString(maps, i, buffer, sizeof(buffer));
        Format(buffer, sizeof(buffer), "%T", "Nomlist Menu Inserted", client, buffer);
        menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);
    }
    delete maps;

    // Sorted nomlist by votes could have better runtime but for some reason
    // SortCustom2D doesn't like being passed an array of strings so im doing it this slow way
    
    int[] mapVotes = new int[nomCount];
    int nominators[MAXPLAYERS+1];
    StringMapSnapshot nomSnap = noms.Snapshot();

    for(int i = 0; i < nomCount; i++)
    {
        nomSnap.GetKey(i, map, sizeof(map));

        if(GetNominationMode() == NominationMode_Limited)
        {
            GetMapNominators(map, nominators, sizeof(nominators));
            //Only 1 nominator in limited mode
            Format(buffer, sizeof(buffer), "%T", "Nomlist Menu Owner", client, map, nominators[0]);
            menu.AddItem(map, buffer, ITEMDRAW_DISABLED);
            continue;
        }
        
        int votes = 0;
        GetTrieValue(noms, map, votes);

        mapVotes[i] = votes;
    }

    if(GetNominationMode() == NominationMode_Limited)
    {
        delete nomSnap;
        delete noms;
        menu.Display(client, MENU_TIME_FOREVER);
        return;
    }

    SortIntegers(mapVotes, nomCount, Sort_Descending);

    for(int i = 0; i < nomCount; i++)
    {
        for(int j = nomSnap.Length - 1; j >= 0; j--)
        {
            nomSnap.GetKey(j, map, sizeof(map));
            int votes = 0;
            if(!GetTrieValue(noms, map, votes))
            {
                continue;
            }
            if(votes != mapVotes[i])
            {
                continue;
            }

            if(votes == 1)
            {
                Format(buffer, sizeof(buffer), "%T", "Nomlist Menu Single Vote", client, map);
            }
            else
            {
                Format(buffer, sizeof(buffer), "%T", "Nomlist Menu Multiple Votes", client, map, votes);
            }
            menu.AddItem(map, buffer);
            noms.Remove(map);
            break;
        }
    }
    delete nomSnap;
    delete noms;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Nomlist_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char map[PLATFORM_MAX_PATH];
            GetMenuItem(menu, param2, map, sizeof(map));
            PrepareNominatorsMenu(param1, map);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void PrepareNominatorsMenu(int client, const char[] map)
{
    Menu menu = CreateMenu(NominatorsMenu_Handler);
    menu.SetTitle("%T", "Nominators Menu Title", client, map);
    menu.ExitBackButton = true;

    char buffer[PLATFORM_MAX_PATH];
    int[] clients = new int[MAXPLAYERS+1];
    int count = GetMapNominators(map, clients, MAXPLAYERS+1);
    
    GetClientNomination(client, buffer, sizeof(buffer));
    bool nominator = StrEqual(buffer, map, false);
    if (nominator)
    {
        Format(buffer, sizeof(buffer), "%T", "Unnominate", client);
        menu.AddItem(map, buffer);
    }
    else
    {
        Format(buffer, sizeof(buffer), "%T", "Nominate", client);
        menu.AddItem(map, buffer);
    }
    
    for(int i = 0; i < count; i++)
    {
        Format(buffer, sizeof(buffer), "%N [#%d]", clients[i], GetClientUserId(clients[i]));
        menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);
    }

    menu.Display(client, MENU_TIME_FOREVER);
}

public int NominatorsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            if (param2 == 0)
            {
                char buffer[PLATFORM_MAX_PATH], map[PLATFORM_MAX_PATH];
                GetMenuItem(menu, param2, map, sizeof(map));
                GetClientNomination(param1, buffer, sizeof(buffer));
                bool nominator = StrEqual(buffer, map);
                if (!nominator)
                {
                    if (!CanClientNominate(param1)) return 0;
                    CanNominateResult canNom = CanNominate(param1);
                    if (canNom != CanNominate_Yes)
                    {
                        switch (canNom)
                        {
                            case CanNominate_VoteInProgress:
                            {
                                CPrintToChat(param1, "%t %t", "NPrefix", "Cannot Nominate - Vote In Progress");
                            }
                        }
                        return 0;
                    }
                    int status = CanMapBeNominated(param1, map);
                    if ((status & CanClientNom_Yes) == CanClientNom_Yes)
                    {
                        NominateMap(param1, map, false);
                        return 0;
                    }
                }
                else
                {
                    if (!RemoveNominationByOwner(param1, Removed_UnNominated))
                    {
                        CReplyToCommand(param1, "%t %t", "NPrefix", "Unable To Unnominate");
                        return 0;
                    }
                }
            }
        }
        case MenuAction_Cancel: 
        {
            if(param2==MenuCancel_ExitBack) PrepareNomlistMenu(param1);
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

/* ====================================================== */
/* ====================================================== */
/*                         NomStatus                      */
/* ====================================================== */
/* ====================================================== */

/**
 * Shows the nomban status of the target to the client
 * 
 * @param client     Client to show the information to
 * @param target     Target
 */
public void PrepareNomStatusMenu(int client, int target)
{
    Menu menu = CreateMenu(NomStatusMenu_Handler);
    menu.SetTitle("%T", "NomStatus Menu Title", client, target);

    char buffer[PLATFORM_MAX_PATH];
    if(!IsClientNomBanned(target))
    {
        Format(buffer, sizeof(buffer), "%T", "Menu - Not Nombanned", client);
        menu.AddItem("b", buffer, ITEMDRAW_DISABLED);
        menu.Display(client, MENU_TIME_FOREVER);
        return;
    }

    if(g_iNomBanLength[target] == NOMBAN_PERMANENT)
    {
        Format(buffer, sizeof(buffer), "%T", "Menu - Nomban Duration", client, "Permanent");
        menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);
    }
    else
    {
        int seconds = g_iNomBanLength[target];
        int minutes = seconds / 60;
        int hours = minutes / 60;
        int days = hours / 24;

        char time[64];

        if(days > 0) Format(time, sizeof(time), "%d days, %d hours, %d minutes", days, hours%24, minutes%60);
        else if(hours > 0) Format(time, sizeof(time), "%d hours %d minutes", hours, minutes%60);
        else if(minutes > 0) Format(time, sizeof(time), "%d minutes", minutes);
        else Format(time, sizeof(time), "%d seconds", seconds);

        Format(buffer, sizeof(buffer), "%t", "Menu - Nomban Duration", time);
        menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);

        menu.AddItem(" ", " ", ITEMDRAW_SPACER);

        int end = g_iNomBanStart[target] + g_iNomBanLength[target];
        FormatTime(time, sizeof(time), "%c", end);
        Format(buffer, sizeof(buffer), "%T", "Menu - Nomban end", client, time);
        menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);

        int timeleftS = end - GetTime();
        int timeleftM = timeleftS / 60;
        int timeleftH = timeleftM / 60;
        int timeleftD = timeleftH / 24;

        if(timeleftD > 0) Format(time, sizeof(time), "%d days, %d hours, %d minutes", timeleftD, timeleftH%24, timeleftM%60);
        else if(timeleftH > 0) Format(time, sizeof(time), "%d hours, %d minutes, %d seconds", timeleftH, timeleftM%60, timeleftS%60);
        else if(timeleftM > 0) Format(time, sizeof(time), "%d minutes, %d seconds", timeleftM, timeleftS%60);
        else Format(time, sizeof(time), "%d seconds", timeleftS);

        Format(buffer, sizeof(buffer), "%T", "Menu - Nomban timeleft", client, time);
        menu.AddItem("timeleft", buffer, ITEMDRAW_DISABLED);

        menu.AddItem(" ", " ", ITEMDRAW_SPACER);
    }

    Format(buffer, sizeof(buffer), "%T", "Menu - Nomban Admin", client, g_sNomBanAdmin[client]);
    menu.AddItem(buffer, buffer, ITEMDRAW_DISABLED);

    menu.Display(client, MENU_TIME_FOREVER);
}

public int NomStatusMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void PrepareNombanListMenu(int client)
{
    Menu menu = CreateMenu(Nombanlist_Handler);

    char info[64];
    char display[64];

    int total = 0;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(!IsClientNomBanned(i)) continue;

        int uid = GetClientUserId(i);

        Format(info, sizeof(info), "%d", uid);
        Format(display, sizeof(display), "[#%d] %N", uid, i);
        menu.AddItem(info, display);

        total++;
    }

    if(total == 0)
    {
        Format(display, sizeof(display), "%T", "No clients nombanned", client);
        menu.AddItem("nothing", display, ITEMDRAW_DISABLED);
    }
    
    menu.Display(client, MENU_TIME_FOREVER);
}

public int Nombanlist_Handler(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            char buffer[64];
            GetMenuItem(menu, param2, buffer, sizeof(buffer));
            
            int uid = StringToInt(buffer);
            int client = GetClientOfUserId(uid);

            if(client == 0)
            {
                CPrintToChat(param1, "%t %t", "NPrefix", "NombanList Client Not valid");
                PrepareNombanListMenu(param1);
            }
            else
            {
                PrepareNomStatusMenu(param1, client);
            }
        }
        case MenuAction_End: delete menu;
    }

    return 0;
}

/* ====================================================== */
/* ====================================================== */
/* NomBan */
/* ====================================================== */
/* ====================================================== */

public void NomBanClient(int target, int duration, int admin)
{
    char buffer[64];

    if(admin == 0)
    {
        Format(g_sNomBanAdmin[target], sizeof(g_sNomBanAdmin[]), "[Console]");
    }
    else
    {
        GetClientAuthId(admin, AuthId_Steam2, buffer, sizeof(buffer));
        Format(g_sNomBanAdmin[target], sizeof(g_sNomBanAdmin[]), "%N (%s)", admin, buffer);
    }

    // length:timeIssued
    int issued = GetTime();

    g_iNomBanLength[target] = duration;
    g_iNomBanStart[target] = issued;

    //Store to cookies
    SaveClientNombanStatus(target);
    
    if(g_cv_RemoveNomOnNomban.BoolValue)
    {
        if(RemoveNominationByOwner(target, Removed_Ignore))
        {
            CPrintToChat(target, "%t %t", "NPrefix", "Nomination removed on nomban");
        }
    }

    char tag[64];
    Format(tag, sizeof(tag), "%t ", "NPrefix");

    if(duration == NOMBAN_PERMANENT)
    {
        CShowActivity2(admin, tag, "%t", "Nombanned permanent", target);
        LogAction(admin, target, "%L nombanned %L permanently.", admin, target);
        return;
    }

    CShowActivity2(admin, tag, "%t", "Nombanned", target, duration/60);
    LogAction(admin, target, "%L nombanned %L for %d minutes.", admin, target, duration/60);
}

public void UnNomBanClient(int client, int admin)
{
    g_iNomBanLength[client] = NOMBAN_NOTBANNED;
    g_iNomBanStart[client] = NOMBAN_NOTBANNED;
    g_sNomBanAdmin[client] = "";
    
    SaveClientNombanStatus(client);

    char tag[64];
    Format(tag, sizeof(tag), "%t ", "NPrefix");

    CShowActivity2(admin, tag, "%t", "UnNombanned", client);
    LogAction(admin, client, "%L unnombanned %L", admin, client);

    Menu menu = CreateMenu(NomStatusMenu_Handler);
    menu.SetTitle("%T", "NomStatus Menu Title", client, client);
    menu.AddItem("s", " ", ITEMDRAW_SPACER);

    Format(tag, sizeof(tag), "%T", "Menu Got UnNombanned", client);
    menu.AddItem("b", tag, ITEMDRAW_DISABLED);

    menu.Display(client, 15);
}

/**
 * Saves a clients current nomban information into cookies
 * 
 * @param client     Client to save for
 */
public void SaveClientNombanStatus(int client)
{
    if(g_iNomBanLength[client] != NOMBAN_NOTBANNED)
    {
        char buffer[PLATFORM_MAX_PATH];
        Format(buffer, sizeof(buffer), "%d:%d", g_iNomBanLength[client], g_iNomBanStart[client]);
        SetClientCookie(client, g_cookie_Nomban, buffer);
    }
    else
    {
        SetClientCookie(client, g_cookie_Nomban, "");
    }

    SetClientCookie(client, g_cookie_NombanAdmin, g_sNomBanAdmin[client]);
}

/* ====================================================== */
/* ====================================================== */
/* Various Stocks */
/* ====================================================== */
/* ====================================================== */

public bool IsClientNomBanned(int client)
{
    if(!IsClientInGame(client)) return false;
    if(!AreClientCookiesCached(client)) return false;

    if(g_iNomBanLength[client] == NOMBAN_NOTBANNED)
    {
        return false;
    }

    if(g_iNomBanLength[client] == NOMBAN_PERMANENT)
    {
        return true;
    }

    if(GetTime() < g_iNomBanStart[client] + g_iNomBanLength[client])
    {
        return true;
    }

    g_iNomBanStart[client] = NOMBAN_NOTBANNED;
    g_iNomBanLength[client] = NOMBAN_NOTBANNED;

    return false;
}

stock char[] GetRandomMap(int client)
{
    char map[PLATFORM_MAX_PATH];
    ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

    for(int i = 0; i < g_MapList.Length; i++)
    {
        GetArrayString(g_MapList, i, map, sizeof(map));

        if(GetMapCooldown(map) > 0) continue;
        if(GetMapPlayerRestriction(map) != 0) continue;
        if(GetMapTimeRestriction(map) != 0) continue;
        if(IsMapInserted(map)) continue;
        if(GetMapVotes(map) > 0) continue;
        if(IsMapAdminOnly(map) && !CheckCommandAccess(client, "sm_adminnom", ADMFLAG_BAN)) continue;
        //if(IsMapNominateOnly(map)) continue;
        if(GetMapGroupRestriction(map) > 0) continue;

        maps.PushString(map);
    }

    int rand = GetRandomInt(0, GetArraySize(maps)-1);
    GetArrayString(maps, rand, map, sizeof(map));

    delete maps;
    return map;
}