#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <mapchooser_unlimited>
#include <csgocolors_fix>

#define PLUGIN_VERSION "1.2.0"

//Rewritten from scratch, but influenced by mapchooser_extended
public Plugin myinfo =
{
    name = "Mapchooser Unlimited",
    author = "tilgep (Based on plugin by Powerlord and AlliedModders LLC)",
                   // Inspiration from a (private)version by GFL (Vauff and/or Snowy)
    description = "Allows players to choose the next map (Now with votes for everyone)",
    version = PLUGIN_VERSION,
    url = "https://www.github.com/tilgep/Mapchooser-Unlimited"
};

#define VOTE_EXTEND "EXTEND"
#define VOTE_DONTCHANGE "DONTCHANGE"
#define VOTE_RANDOM "RANDOM"

#define VOTE_RETRY_INTERVAL 5.0

#define MAX_DESCRIPTION_LENGTH 256

enum WarningType
{
    WarningType_Vote,
    WarningType_Revote,
};

enum TimerLocation
{
    TimerLocation_Hint = 0,
    TimerLocation_Center = 1,
    TimerLocation_Chat = 2,
};

enum NominationChooseMode
{
    NominationMode_Top = 0,
    NominationMode_Random = 1,
    NominationMode_Weighted = 2,
};

Menu g_VoteMenu;         //Vote menu
Handle g_VoteTimer;      //Timer to begin the mapvote
Handle g_WarningTimer;   //Timer to show warning countdown
Handle g_RetryTimer;

ArrayList g_MapList;    //Maplist found in the map list file specified in maplists.cfg
int g_iSerial = -1;     //Used to check the status of maplist loading

bool g_bConfig = false; //Is config loaded
KeyValues g_kvConfig;   //Config
int g_iGroups;          //Number of groups in the config (to help optimise)

StringMap g_Nominations; //Maps nominated with number of votes
char g_sNominations[MAXPLAYERS+1][PLATFORM_MAX_PATH]; //Nominations made by each client
char g_sRandomMap[PLATFORM_MAX_PATH]; //Current random map

ArrayList g_InsertedMaps; //Maps inserted by admin (these always get added to the vote)

StringMap g_RecentMaps; //Maps on cooldown

MapChange g_ChangeTime;
NominationMode g_NominationMode;

bool g_bWaitingForVote = false;
bool g_bChangeMapAtRoundEnd = false;
bool g_bMapChangeInProgress = false;    //Is the map currently changing
bool g_bWarningInProgress = false;      //Is the warning timer currently showing
bool g_bVoteEnded = false;              //Has the end of map vote ended
bool g_bVoteInProgress = false;         //Is the map vote in progress
bool g_bCooldownsStepped = false;
bool g_bRestored = false;

int g_iExtends = 0;                     //Total extends done this map
int g_iRunoffCount = 0;                 //Number of runoff votes done

ConVar g_cv_Enabled;
ConVar g_cv_Mode;
ConVar g_cv_ExtendedLogging;
ConVar g_cv_CooldownFile;
ConVar g_cv_CooldownMode;
ConVar g_cv_VoteStartTime;
ConVar g_cv_TimerLocation;
ConVar g_cv_HideWarningTimer;
ConVar g_cv_WarningTime;
ConVar g_cv_RunOffWarningTime;
ConVar g_cv_RunOffCount;
ConVar g_cv_RunOffPercent;
ConVar g_cv_VoteDuration;
ConVar g_cv_Extends;
ConVar g_cv_ExtendPosition;
ConVar g_cv_ExtendTime;
ConVar g_cv_NoVoteOption;
ConVar g_cv_NomChooseMode;
ConVar g_cv_RandomVote;
ConVar g_cv_ChooseRandom;
ConVar g_cv_Cooldown;
ConVar g_cv_RandomMap;
ConVar g_cv_Include;
ConVar g_cv_TotalVoteOptions;
ConVar g_cv_ShowNominators;

GlobalForward g_fwdNominationRemoved;
GlobalForward g_fwdMapVoteStarted;
GlobalForward g_fwdWarningTick;
GlobalForward g_fwdRunoffVoteStarted;
GlobalForward g_fwdVoteStarted;
GlobalForward g_fwdMapVoteEnded;
GlobalForward g_fwdMapAddedToVote;
GlobalForward g_fwdMapNominated;
GlobalForward g_fwdMapInserted;
GlobalForward g_fwdMapListReloaded;

public void OnPluginStart()
{
    if(GetEngineVersion() != Engine_CSGO)
    {
        LogMessage("This plugin is only tested and supported on CSGO! Beware of bugs!");
        PrintToServer("This plugin is only tested and supported on CSGO! Beware of bugs!");
    }

    LoadTranslations("common.phrases");
    LoadTranslations("mapchooser_unlimited.phrases");
    
    RegAdminCmd("sm_mapvote", Command_Mapvote, ADMFLAG_BAN, "Starts a new mapvote.");
    RegAdminCmd("sm_setnextmap", Command_Setnextmap, ADMFLAG_BAN, "Change the current next map.");
    RegAdminCmd("sm_reloadmapconfig", Command_ReloadConfig, ADMFLAG_BAN, "Reload mapchooser config.");
    RegAdminCmd("sm_reloadmaplist", Command_ReloadMaplist, ADMFLAG_BAN, "Reloads the list of maps that can be in the mapvote.");
    RegAdminCmd("sm_excludemap", Command_Exclude, ADMFLAG_BAN, "Put a map on cooldown");
    RegAdminCmd("sm_clearcd", Command_ClearCd, ADMFLAG_BAN, "Take a map off cooldown.");
    
    RegConsoleCmd("sm_extendsleft", Command_ExtendsLeft, "Shows how many more times the map can be extended.");
    RegConsoleCmd("sm_showmapconfig", Command_ShowConfig, "Shows all config information about the current map.");
    RegConsoleCmd("sm_mcversion", Command_Version, "Mapchooser version");

    g_cv_Enabled = CreateConVar("mcu_enabled", "1", "Should mapchooser perform an end of map vote?", _, true, 0.0, true, 1.0);
    g_cv_Mode = CreateConVar("mcu_nominate_mode", "1", "Nomination mode (1=allow multiple votes for maps, 0=only one vote per map and only allow 'mcu_include' nominations)", _, true, 0.0, true, 1.0);
    g_cv_ExtendedLogging = CreateConVar("mcu_logging", "0", "Should the plugin create extended logs of actions, e.g. Restored cooldowns, maps added to vote menu, does not affect logging command usage. (1=yes, 0=no)", _, true, 0.0, true, 1.0);
    g_cv_CooldownFile = CreateConVar("mcu_cooldownfile", "configs/mapchooser_unlimited/cooldowns.cfg", "File location to store maps currently on cooldown, relative to sourcemod directory.");
    g_cv_CooldownMode = CreateConVar("mcu_cooldownmode", "0", "When should cooldowns be saved (0=mapstart, 1=mapend) Map end means a server crash wont put the current map on cooldown", _, true, 0.0, true, 1.0);
    g_cv_VoteStartTime = CreateConVar("mcu_votestart", "4.0", "Timeleft to start the vote", _, true, 1.0);
    g_cv_TimerLocation = CreateConVar("mcu_timer_location", "0", "Location to show the warning timer (0 = hint text, 1 = center text, 2 = chat)", _, true, 0.0, true, 2.0);
    g_cv_HideWarningTimer = CreateConVar("mcu_warning_timer", "1", "Is the warning timer shown (1=enabled, 0=disabled)", _, true, 0.0, true, 1.0);
    g_cv_WarningTime = CreateConVar("mcu_warningtime", "15", "Warning timer duration before vote is shown. (0 - disabled)", _, true, 0.0, true, 60.0);
    g_cv_RunOffWarningTime = CreateConVar("mcu_revote_warningtime", "10", "Warning timer duration for runoff votes.", _, true, 0.0, true, 30.0);
    g_cv_RunOffCount = CreateConVar("mcu_runoff_count", "1", "Maximum number of runoff votes that can happen for each map vote, 0=disabled", _, true, 0.0);
    g_cv_RunOffPercent = CreateConVar("mcu_runoff_percent", "60", "If winning choice has less than this percent of votes, hold a runoff.", _, true, 0.0, true, 100.0);
    g_cv_VoteDuration = CreateConVar("mcu_voteduration", "20", "Duration to keep the map vote available for.", _, true, 5.0);
    g_cv_Extends = CreateConVar("mcu_extends", "3", "Default maximum number of extends that will be allowed in end-of-map votes.", _, true, 0.0);
    g_cv_ExtendPosition = CreateConVar("mcu_extendpos", "1", "Position of 'Extend map' or 'Don't Change' option (0=random, 1=start)", _, true, 0.0, true, 1.0);
    g_cv_ExtendTime = CreateConVar("mcu_extendtime", "20", "Number of minutes to extend the map for if extend is chosen.");
    g_cv_NoVoteOption = CreateConVar("mcu_novote", "1", "Should a 'No vote' option be given. (1=yes, 0=no)", _,true, 0.0, true, 1.0);
    g_cv_NomChooseMode = CreateConVar("mcu_vote_mode", "0", "Mode to add nominations to the vote (0=Add top X voted map, 1=Add X random maps, 2=Weight voted maps and choose X random maps)", _, true, 0.0, true, 2.0);
    g_cv_RandomVote = CreateConVar("mcu_randomize", "1", "How should the vote menu be randomized (1=random for each client (requires sourcemod 1.11 or later), 0=same option order for all)", _, true, 0.0, true, 1.0);
    g_cv_ChooseRandom = CreateConVar("mcu_novotes_mode", "1", "Should MapChooser choose a random option if no votes are received.", _, true, 0.0, true, 1.0);
    g_cv_Cooldown = CreateConVar("mcu_cooldown", "50", "Default number of maps that must be played before a map can be nominated again.", _, true, 0.0);
    g_cv_RandomMap = CreateConVar("mcu_randommap", "1", "Should the map vote have a 'Random map' option (0=disabled, 1=enabled)", _, true, 0.0, true, 1.0);
    g_cv_Include = CreateConVar("mcu_include", "5", "Maximum number of nominated maps to include in the vote.", _, true, 0.0);
    g_cv_TotalVoteOptions = CreateConVar("mcu_total_options", "9", "Number of options that should appear in the vote (including extend, random, noms, no vote)", _, true, 0.0);
    g_cv_ShowNominators = CreateConVar("mcu_show_nominators", "1", "Whether or not to show who nominated the chosen map when the vote ends. (0=disabled, 1=enabled)", _, true, 0.0, true, 1.0);
    
    AutoExecConfig(true, "mapchooser_unlimited");

    HookEvent("round_end", Event_RoundEnd);

    g_fwdNominationRemoved = CreateGlobalForward("OnNominationRemoved", ET_Ignore, Param_Cell, Param_String, Param_Cell);
    g_fwdMapVoteStarted = CreateGlobalForward("OnMapVoteWarningStart", ET_Ignore);
    g_fwdWarningTick = CreateGlobalForward("OnMapVoteWarningTick", ET_Ignore, Param_Cell);
    g_fwdRunoffVoteStarted = CreateGlobalForward("OnRunoffVoteWarningStart", ET_Ignore);
    g_fwdVoteStarted = CreateGlobalForward("OnMapVoteStarted", ET_Ignore, Param_Cell);
    g_fwdMapVoteEnded = CreateGlobalForward("OnMapVoteEnd", ET_Ignore, Param_String);
    g_fwdMapAddedToVote = CreateGlobalForward("OnMapAddedToVote", ET_Ignore, Param_String, Param_Cell, Param_Cell);
    g_fwdMapNominated = CreateGlobalForward("OnMapNominated", ET_Ignore, Param_Cell, Param_String, Param_Cell, Param_Cell);
    g_fwdMapInserted = CreateGlobalForward("OnMapInserted", ET_Ignore, Param_Cell, Param_String);
    g_fwdMapListReloaded = CreateGlobalForward("OnMapListReloaded", ET_Ignore);

    int arraySize = ByteCountToCells(PLATFORM_MAX_PATH);
    g_Nominations = CreateTrie();
    g_RecentMaps = CreateTrie();
    g_InsertedMaps = CreateArray(arraySize);
    g_MapList = CreateArray(arraySize);

    LoadConfig();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if(LibraryExists("mapchooser"))
    {
        strcopy(error, err_max, "Mapchooser already loaded! Aborting.");
        return APLRes_Failure;
    }

    RegPluginLibrary("mapchooser");

    CreateNative("EndOfMapVoteEnabled", Native_EndOfMapVoteEnabled);
    CreateNative("GetNominationMode", Native_GetNominationMode);
    CreateNative("CanMapChooserStartVote", Native_CanVoteStart);
    CreateNative("IsMapVoteInProgress", Native_IsMapVoteInProgress);
    CreateNative("HasEndOfMapVoteFinished", Native_HasVoteFinished);
    CreateNative("GetExtendsUsed", Native_GetExtendsUsed);
    CreateNative("InitiateMapChooserVote", Native_InitiateVote);
    CreateNative("NominateMap", Native_NominateMap);
    CreateNative("CanNominate", Native_CanNominate);
    CreateNative("CanMapBeNominated", Native_CanMapBeNominated);
    CreateNative("GetNominatedMapList", Native_GetNominatedMapList);
    CreateNative("GetMapVotes", Native_GetMapVotes);
    CreateNative("IsMapInserted", Native_IsMapInserted);
    CreateNative("GetInsertedMapList", Native_GetInsertedMapList);
    CreateNative("RemoveNominationByOwner", Native_RemoveNomByOwner);
    CreateNative("RemoveNominationsByMap", Native_RemoveNomByMap);
    CreateNative("RemoveInsertedMap", Native_RemoveInsertedMap);
    CreateNative("GetClientNomination", Native_GetClientNomination);
    CreateNative("GetMapNominators", Native_GetMapNominators);
    CreateNative("ExcludeMap", Native_ExcludeMap);
    CreateNative("GetMapCooldown", Native_GetMapCooldown);
    CreateNative("GetMapPlayerRestriction", Native_GetMapPlayerRestriction);
    CreateNative("GetMapMinPlayers", Native_GetMapMinPlayers);
    CreateNative("GetMapMaxPlayers", Native_GetMapMaxPlayers);
    CreateNative("GetMapTimeRestriction", Native_GetMapTimeRestriction);
    CreateNative("GetMapMinTime", Native_GetMapMinTime);
    CreateNative("GetMapMaxTime", Native_GetMapMaxTime);
    CreateNative("IsMapAdminOnly", Native_IsMapAdminOnly);
    CreateNative("IsMapNominateOnly", Native_IsMapNominateOnly);
    CreateNative("GetMapDescription", Native_GetMapDescription);
    CreateNative("GetMapGroupRestriction", Native_GetMapGroupRestriction);
    CreateNative("GetMapMaxExtends", Native_GetMapMaxExtends);

    return APLRes_Success;
}

public void OnConfigsExecuted()
{
    if(!g_bRestored) 
    {
        RestoreCooldowns();
        g_bRestored = true;
    }
    LoadMaplist();
    WipeAllNominations(Removed_Ignore);
    WipeInsertedMaps();

    SetupTimeleftTimer();

    g_bMapChangeInProgress = false;
    g_bVoteInProgress = false;
    g_bVoteEnded = false;
    g_iExtends = 0;
    g_iRunoffCount = 0;
    g_bCooldownsStepped = false;

    LoadNominationMode();

    if(g_cv_CooldownMode.IntValue == 0)
    {
        StepCooldowns();
        g_bCooldownsStepped = true;
    }
}

public void OnMapEnd()
{
    if(g_cv_CooldownMode.IntValue == 1 && !g_bCooldownsStepped)
    {
        StepCooldowns();
    }
    
    if(g_VoteTimer != null)
    {
        KillTimer(g_VoteTimer);
        g_VoteTimer = null;
    }

    if(g_WarningTimer != null)
    {
        KillTimer(g_WarningTimer);
        g_WarningTimer = null;
    }
}

public void OnClientPutInServer(int client)
{
    CheckNomRestrictions(true, true);
}

public void OnClientDisconnect(int client)
{
    InternalRemoveNomByOwner(client, Removed_ClientDisconnect);
    CheckNomRestrictions(true, true);
}

public void LoadNominationMode()
{
    g_NominationMode = view_as<NominationMode>(g_cv_Mode.IntValue);
}

/**
 * Loads the list of maps which can be put into a mapvote
 * 
 * @return      Was the load successful
 */
bool LoadMaplist(bool command = false)
{
    if(ReadMapList(g_MapList, g_iSerial, "mapchooser", MAPLIST_FLAG_CLEARARRAY|MAPLIST_FLAG_MAPSFOLDER) != INVALID_HANDLE)
    {
        if(g_iSerial == -1)
        {
            LogError("Unable to create a valid map list.");
            return false;
        }

        if(command)
        {
            Call_StartForward(g_fwdMapListReloaded);
            Call_Finish();
        }
        return true;
    }
    return false;
}

/**
 * Wipes the current nominations list
 * 
 * @param reason        NominateRemoved reason for removal
 * @return              Number of client nominations cleared
 */
public int WipeAllNominations(NominateRemoved reason)
{
    int count = 0;
    for(int i = 1; i <= MaxClients; i++)
    {
        //Call this for the OnNominationRemoved forward as well
        InternalRemoveNomByOwner(i, reason);
        count++;
    }
    g_Nominations.Clear();
    return count;
}

public void WipeInsertedMaps()
{
    g_InsertedMaps.Clear();
}

/**
 * Loads cooldowns from the cooldown file into a stringmap
 */
public void RestoreCooldowns()
{
    char sCooldownFile[PLATFORM_MAX_PATH];

    g_cv_CooldownFile.GetString(sCooldownFile, sizeof(sCooldownFile));
    BuildPath(Path_SM, sCooldownFile, sizeof(sCooldownFile), "%s", sCooldownFile);

    if(!FileExists(sCooldownFile))
    {
        LogMessage("Couldn't find cooldown file at: \"%s\". Attempting to create it...", sCooldownFile);

        File f = OpenFile(sCooldownFile, "a");
        delete f;
        if(FileExists(sCooldownFile))
        {
            LogMessage("Cooldown file successfully created at \"%s\"", sCooldownFile);
        }
        else
        {
            ReplaceString(sCooldownFile, PLATFORM_MAX_PATH, "\\", "/");

            int last = FindCharInString(sCooldownFile, '/', true);
            if(last != -1)
            {
                char sCooldownDir[PLATFORM_MAX_PATH];
                strcopy(sCooldownDir, last+1, sCooldownFile);
                if(!DirExists(sCooldownDir))
                {
                    LogMessage("Creating cooldown directory: \"%s\"", sCooldownDir);
                    CreateDirectory(sCooldownDir, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC|FPERM_G_EXEC|FPERM_O_EXEC);
                }
                File f2 = OpenFile(sCooldownFile, "a");
                delete f2;
                if(FileExists(sCooldownFile))
                {
                    LogMessage("Cooldown file successfully created at \"%s\"", sCooldownFile);
                }
                else
                {
                    LogError("Could not find or create cooldown file: \"%s\". If this keeps happening create an empty file in the directory.", sCooldownFile);
                }
            }
        }
        
        return;
    }

    KeyValues kv = new KeyValues("mapchooser");
    if(!kv.ImportFromFile(sCooldownFile))
    {
        LogMessage("Unable to load cooldown keyvalues from file: \"%s\"", sCooldownFile);
        delete kv;
        return;
    }

    if(!kv.GotoFirstSubKey())
    {
        LogMessage("Unable to go to first sub-key in cooldown file: \"%s\"", sCooldownFile);
        delete kv;
        return;
    }

    int total = 0;
    int cooldown;
    char sMap[PLATFORM_MAX_PATH];

    do
    {
        kv.GetSectionName(sMap, sizeof(sMap));
        cooldown = kv.GetNum("cooldown", -1);
        if(cooldown > 0)
        {
            g_RecentMaps.SetValue(sMap, cooldown);
            if(g_cv_ExtendedLogging.IntValue==1)
            {
                LogMessage("Cooldown restored. Map:\"%s\" -> %d", sMap, cooldown);
            }
            total++;
        }
    }
    while(kv.GotoNextKey());
    delete kv;
    LogMessage("Cooldowns restored for %d maps.", total);
}

/**
 * Saves all cooldowns found in the stringmap to the cooldown file
 */
public void StoreCooldowns()
{
    char sCooldownFile[PLATFORM_MAX_PATH];
    g_cv_CooldownFile.GetString(sCooldownFile, sizeof(sCooldownFile));
    BuildPath(Path_SM, sCooldownFile, sizeof(sCooldownFile), "%s", sCooldownFile);

    if(!FileExists(sCooldownFile))
    {
        File file = OpenFile(sCooldownFile, "a");
        if(file==null)
        {
            LogError("Could not find or create cooldown file: \"%s\". If this keeps happening create an empty file in the directory.", sCooldownFile);
            return;
        }
        delete file;
    }

    KeyValues kv = new KeyValues("mapchooser");
    int cooldown;
    char map[PLATFORM_MAX_PATH];
    int total = 0;

    StringMapSnapshot snap = g_RecentMaps.Snapshot();
    for(int i = 0; i < snap.Length; i++)
    {
        snap.GetKey(i, map, sizeof(map));
        g_RecentMaps.GetValue(map, cooldown);
        if(cooldown <= 0) continue;
        kv.JumpToKey(map, true);
        kv.SetNum("cooldown", cooldown);
        kv.Rewind();
        total++;
    }
    delete snap;

    if(!kv.ExportToFile(sCooldownFile))
    {
        LogMessage("Unable to export cooldowns to file: \"%s\"", sCooldownFile);
    }
    delete kv;
    LogMessage("Saved cooldowns for %d maps.", total);
}

/**
 * Decreases all current cooldowns by 1 and sets the current map + groups on cooldown
 */
public void StepCooldowns()
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    InternalSetMapCooldown(map, Cooldown_ConfigGreater);

    SetMapGroupsCooldown(map);

    int cd;
    StringMapSnapshot snap = g_RecentMaps.Snapshot();
    for(int i = 0; i < snap.Length; i++)
    {
        GetTrieSnapshotKey(snap, i, map, sizeof(map));
        GetTrieValue(g_RecentMaps, map, cd);
        cd--;
        SetCooldown(map, cd); //SetCooldown handles removing
    }
    delete snap;

    StoreCooldowns();
}

public void Event_RoundEnd(Event event, const char[] name, bool db)
{
    if(g_bChangeMapAtRoundEnd)
    {
        g_bChangeMapAtRoundEnd = false;
        CreateTimer(2.0, Timer_ChangeMap, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
        g_bMapChangeInProgress = true;
    }
}

public Action Command_Mapvote(int client, int args)
{
    char tag[64];
    Format(tag, sizeof(tag), "%t ", "Prefix");
    CShowActivity2(client, tag, "%t", "Initiated Map Vote");
    LogAction(client, -1, "%L initiated a map vote.", client);

    SetupWarningTimer(WarningType_Vote, MapChange_MapEnd, INVALID_HANDLE, true);

    return Plugin_Handled;
}

public Action Command_Setnextmap(int client, int args)
{
    if(args < 1)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Setnextmap Usage");
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(StrEqual(map, "_random", false))
    {
        map = GetRandomMap();
    }

    SetNextMap(map);

    char tag[64];
    Format(tag, sizeof(tag), "%t ", "Prefix");

    CShowActivity2(client, tag, "%t", "Changed Next Map", map);
    LogAction(client, -1, "\"%L\" changed nextmap to \"%s\"", client, map);

    g_bVoteEnded = true;

    return Plugin_Handled;
}

public Action Command_ReloadConfig(int client, int args)
{
    if(LoadConfig())
    {
        CPrintToChat(client, "%t %t", "Prefix", "Config reload successful");
        LogAction(client, -1, "%L reloaded the mapchooser config successfully.", client);
    }
    else
    {
        CPrintToChat(client, "%t %t", "Prefix", "Config reload unsuccessful");
        LogAction(client, -1, "%L reloaded the mapchooser config unsuccessfully.", client);
    }
    return Plugin_Handled;
}

public Action Command_ReloadMaplist(int client, int args)
{
    if(LoadMaplist(true))
    {
        CPrintToChat(client, "%t %t", "Prefix", "Maplist reload successful");
        LogAction(client, -1, "%L reloaded the maplist successfully.", client);
    }
    else
    {
        CPrintToChat(client, "%t %t", "Prefix", "Maplist reload unsuccessful");
        LogAction(client, -1, "%L reloaded the maplist unsuccessfully.", client);
    }
    return Plugin_Handled;
}

public Action Command_Exclude(int client, int args)
{
    if(args < 1)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Exclude Map Usage");
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(FindStringInArray(g_MapList, map) == -1)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Map was not found", map);
        return Plugin_Handled;
    }
    
    if(args == 1)
    {
        int cd = GetMapBaseCooldown(map);
        InternalSetMapCooldown(map, Cooldown_Config);

        CReplyToCommand(client, "%t %t", "Prefix", "Exclude Map Set", map, cd);
        LogAction(client, -1, "%L set cooldown for map %s to %d", client, map, cd);
        return Plugin_Handled;
    }

    char buf[8];
    GetCmdArg(2, buf, sizeof(buf));
    int cd = StringToInt(buf);
    
    if(cd <= 0)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Exclude Map Value Error");
        return Plugin_Handled;
    }

    InternalSetMapCooldown(map, Cooldown_Value, cd);

    CReplyToCommand(client, "%t %t", "Prefix", "Exclude Map Set", map, cd);
    LogAction(client, -1, "%L set cooldown for map %s to %d", client, map, cd);

    return Plugin_Handled;
}

public Action Command_ClearCd(int client, int args)
{
    if(args < 1)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Clear cooldown usage");
        return Plugin_Handled;
    }

    char map[PLATFORM_MAX_PATH];
    GetCmdArg(1, map, sizeof(map));

    if(FindStringInArray(g_MapList, map) == -1)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Map was not found", map);
        return Plugin_Handled;
    }

    if(InternalGetMapCurrentCooldown(map) == 0)
    {
        CReplyToCommand(client, "%t %t", "Prefix", "Map not on cooldown", map);
        return Plugin_Handled;
    }

    InternalSetMapCooldown(map, Cooldown_Value, 0);
    
    LogAction(client, -1, "%L cleared the cooldown for map %s", client, map);
    CPrintToChat(client, "%t %t", "Prefix", "Map cooldown cleared", map);

    return Plugin_Handled;
}

public Action Command_ShowConfig(int client, int args)
{
    char map[PLATFORM_MAX_PATH];

    if(args==0) GetCurrentMap(map, sizeof(map));
    else
    {
        GetCmdArg(1, map, sizeof(map));
        if(FindStringInArray(g_MapList, map) == -1)
        {
            CReplyToCommand(client, "%t %t", "Prefix", "Map was not found", map);
            return Plugin_Handled;
        }
    }

    int extends = InternalGetMapMaxExtends(map);
    int cooldown = GetMapBaseCooldown(map);
    int minplayer = InternalGetMapMinPlayers(map);
    int maxplayer = InternalGetMapMaxPlayers(map);
    int mintime = InternalGetMapMinTime(map);
    int maxtime = InternalGetMapMaxTime(map);
    bool adminonly = InternalIsMapAdminOnly(map);
    bool nomonly = InternalIsMapNominateOnly(map);
    char desc[MAX_DESCRIPTION_LENGTH];
    bool descr = InternalGetMapDescription(map, desc, sizeof(desc));

    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
    {
        CPrintToChat(client, "%t %t", "Prefix", "See console for output");
    }
    
    PrintToConsole(client, "-----------------------------------------");
    PrintToConsole(client, "Showing config info for: %s", map);
    PrintToConsole(client, "-----------------------------------------");
    PrintToConsole(client, "%-15s %5d", "Extends: ", extends);
    PrintToConsole(client, "%-15s %5d", "Cooldown: ", cooldown);
    PrintToConsole(client, "%-15s %5d", "MinPlayers: ", minplayer);
    PrintToConsole(client, "%-15s %5d", "MaxPlayers: ", maxplayer);
    PrintToConsole(client, "%-15s %5d", "MinTime: ", mintime);
    PrintToConsole(client, "%-15s %5d", "MaxTime: ", maxtime);
    PrintToConsole(client, "%-15s %5b", "AdminOnly: ", adminonly);
    PrintToConsole(client, "%-15s %5b", "NominateOnly: ", nomonly);
    PrintToConsole(client, "%-15s %5s %s", "Description: ", descr?"Yes:":"No", desc);
    PrintToConsole(client, "-----------------------------------------");
    ShowMapGroups(client, map);
    return Plugin_Handled;
}

public Action Command_ExtendsLeft(int client, int args)
{
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    int max = InternalGetMapMaxExtends(map);

    int left = max - g_iExtends;
    CReplyToCommand(client, "%t %t", "Prefix", "Extends Left", g_iExtends, max, left);

    return Plugin_Handled;
}

public Action Command_Version(int client, int args)
{
    CPrintToChat(client, "%t Version %s", "Prefix", PLUGIN_VERSION);
    return Plugin_Handled;
}

void SetupTimeleftTimer()
{
    int time;
    if(GetMapTimeLeft(time) && time > 0)
    {
        int startTime;
        startTime = g_cv_VoteStartTime.IntValue * 60;

        if(time - startTime < 0 && !g_bVoteEnded && !g_bVoteInProgress)
        {
            SetupWarningTimer(WarningType_Vote);
        }
        else
        {
            if(g_WarningTimer == null)
            {
                delete g_VoteTimer;

                g_VoteTimer = CreateTimer(float(time - startTime), Timer_StartWarningTimer);
            }
        }
    }
}

public void OnMapTimeLeftChanged()
{
    if(GetArraySize(g_MapList))
        SetupTimeleftTimer();
}

public Action Timer_StartWarningTimer(Handle timer)
{
    g_VoteTimer = null;

    if(!g_bWarningInProgress || g_WarningTimer == null)
        SetupWarningTimer(WarningType_Vote);

    return Plugin_Stop;
}

/**
 * Starts the warning timer for the map vote
 * Essentially this should be called to start a new map vote
 * 
 * @param type        Type of warning to show
 * @param when        When the mapchange will occur
 * @param mapList     Optional list of maps to pass (dont pass nomlist)
 * @param force       Whether to force a vote now
 */
stock void SetupWarningTimer(WarningType type, MapChange when=MapChange_MapEnd, Handle mapList=INVALID_HANDLE, bool force=false)
{
    if(!GetArraySize(g_MapList))
    {
        LogMessage("Failed to start map vote because maplist does not exist.");
        return;
    }
    if(g_bMapChangeInProgress)
    {
        LogMessage("Failed to start map vote because a map change is in progress.");
        return;
    }
    if(g_bVoteInProgress && mapList == INVALID_HANDLE)
    {
        LogMessage("Failed to start map vote because a vote is already in progress.");
        return;
    }
    if(!force)
    {
        if(when == MapChange_MapEnd)
        {
            if(g_cv_Enabled.IntValue == 0)
            {
                LogMessage("Mapvote not starting because of convar.");
                return;
            }
        }
        if(g_bVoteEnded)
        {
            LogMessage("Failed to start map vote because a vote has already happened and ended.");
            return;
        }
    }
    
    bool interrupted = false;
    if(g_bWarningInProgress && g_WarningTimer != null)
    {
        interrupted = true;
        KillTimer(g_WarningTimer);
        g_WarningTimer = null;
    }

    g_bWarningInProgress = true;

    Handle forwardVote;
    ConVar cvarTime;
    static char translationKey[64];

    switch(type)
    {
        case WarningType_Vote:
        {
            forwardVote = g_fwdMapVoteStarted;
            cvarTime = g_cv_WarningTime;
            strcopy(translationKey, sizeof(translationKey), "Vote Warning");
        }

        case WarningType_Revote:
        {
            forwardVote = g_fwdRunoffVoteStarted;
            cvarTime = g_cv_RunOffWarningTime;
            strcopy(translationKey, sizeof(translationKey), "Revote Warning");
        }
    }

    if(!interrupted)
    {
        Call_StartForward(forwardVote);
        Call_Finish();
    }

    Handle data;
    g_WarningTimer = CreateDataTimer(1.0, Timer_StartMapVote, data, TIMER_REPEAT);
    WritePackCell(data, force);
    WritePackCell(data, cvarTime.IntValue);
    WritePackString(data, translationKey);
    WritePackCell(data, view_as<int>(when));
    WritePackCell(data, view_as<int>(mapList));
    ResetPack(data);
}

public Action Timer_StartMapVote(Handle timer, Handle data)
{
    static int timePassed = 0;
    ResetPack(data);
    bool force = ReadPackCell(data);

    bool stop = false;

    if(!GetArraySize(g_MapList)) stop = true;
    if(!stop && g_cv_Enabled.IntValue == 0) stop = true;
    if(!stop && !force)
    {
        if(g_bVoteEnded) stop = true;
    }

    if(stop)
    {
        g_WarningTimer = null;
        return Plugin_Stop;
    }
    
    int warningMaxTime = ReadPackCell(data);
    int warningTimeRemaining = warningMaxTime - timePassed;
    
    Call_StartForward(g_fwdWarningTick);
    Call_PushCell(warningTimeRemaining);
    Call_Finish();

    char warningPhrase[32];
    ReadPackString(data, warningPhrase, sizeof(warningPhrase));

    if(timePassed >= 0 || !g_cv_HideWarningTimer.BoolValue)
    {
        TimerLocation timerLocation = view_as<TimerLocation>(g_cv_TimerLocation.IntValue);

        switch(timerLocation)
        {
            case TimerLocation_Center:
            {
                PrintCenterTextAll("%t", warningPhrase, warningTimeRemaining);
            }

            case TimerLocation_Chat:
            {
                PrintToChatAll("%t", warningPhrase, warningTimeRemaining);
            }

            default:
            {
                PrintHintTextToAll("%t", warningPhrase, warningTimeRemaining);
            }
        }
    }
    timePassed++;
    if(timePassed > warningMaxTime)
    {
        if(timer == g_RetryTimer)
        {
            g_bWaitingForVote = false;
            g_RetryTimer = null;
        }
        else
            g_WarningTimer = null;

        timePassed = 0;
        MapChange mapChange = view_as<MapChange>(ReadPackCell(data));
        Handle hndl = view_as<Handle>(ReadPackCell(data));

        StartVote(mapChange, hndl);

        return Plugin_Stop;
    }

    return Plugin_Continue;
}

/**
 * Builds and starts the nextmap vote menu
 * 
 * @param when          When should the map change once the vote is complete
 * @param inputList     List of options to use, if none given use random maps and nominations
 */
void StartVote(MapChange when, Handle inputList = INVALID_HANDLE)
{
    g_bWaitingForVote = true;
    g_bWarningInProgress = false;

    CheckNomRestrictions(true, true);

    if(IsVoteInProgress())
    {
        Handle info;
        WritePackCell(info, view_as<int>(when));
        WritePackCell(info, view_as<int>(inputList));
        ResetPack(info);
        CreateTimer(VOTE_RETRY_INTERVAL, Timer_VoteRetry, info, TIMER_FLAG_NO_MAPCHANGE);
        CPrintToChatAll("%t %t", "Prefix", "Retrying vote", VOTE_RETRY_INTERVAL);
        return;
    }

    g_bWaitingForVote = false;
    g_ChangeTime = when;

    /* Starting a runoff */
    if(inputList != INVALID_HANDLE)
    {
        StartRunoffVote(when, inputList);
        return;
    }

    if(g_bVoteInProgress)
    {
        LogMessage("Aborting vote start because a map vote is already in progress.");
        return;
    }

    g_VoteMenu = CreateMenu(Handler_VoteMenu, MENU_ACTIONS_ALL);
    SetVoteResultCallback(g_VoteMenu, VoteHandler_VoteMenu);
    SetMenuTitle(g_VoteMenu, "Vote for the Next Map");

    int itemsToAdd = g_cv_TotalVoteOptions.IntValue;
    int nomsAdded = 0;
    int inserted = 0;

    /* Set 'No Vote' option */
    if(g_cv_NoVoteOption.BoolValue)
    {
        g_VoteMenu.NoVoteButton = true;
        itemsToAdd--;
    }
    else
    {
        g_VoteMenu.NoVoteButton = false;
    }
    
    ArrayList voteList = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    bool extendAdded = false; //So we can shuffle correctly
    char map[PLATFORM_MAX_PATH];
    GetCurrentMap(map, sizeof(map));

    /* Add Extend/Dont change option */
    if(when == MapChange_MapEnd)
    {
        if(g_iExtends < InternalGetMapMaxExtends(map))
        {
            voteList.PushString(VOTE_EXTEND);
            extendAdded = true;
            itemsToAdd--;

            if(g_cv_ExtendedLogging.BoolValue)
            {
                LogMessage("Added %s to vote.", VOTE_EXTEND);
            }
        }
    }
    else
    {
        voteList.PushString(VOTE_DONTCHANGE);
        extendAdded = true;
        itemsToAdd--;

        if(g_cv_ExtendedLogging.BoolValue)
        {
            LogMessage("Added %s to vote.", VOTE_DONTCHANGE);
        }
    }
    

    /* Add 'random map' */
    if(g_cv_RandomMap.BoolValue)
    {
        voteList.PushString(VOTE_RANDOM);
        itemsToAdd--;

        if(g_cv_ExtendedLogging.BoolValue)
        {
            LogMessage("Added %s to vote.", VOTE_RANDOM);
        }
    }

    /* Add admin inserted maps */
    if(g_InsertedMaps.Length > 0)
    {
        inserted = InsertInsertedMaps(voteList, itemsToAdd);
        itemsToAdd -= inserted;
    }

    /* Add nominated maps */
    if(g_Nominations.Size > 0 && itemsToAdd > 0)
    {
        nomsAdded = InsertNominatedMaps(voteList, g_cv_Include.IntValue < itemsToAdd ? g_cv_Include.IntValue : itemsToAdd);
    }

    /* Add random non-nominated maps (also sets the 'Random map' option) */
    itemsToAdd -= nomsAdded;
    InsertRandomMaps(voteList, itemsToAdd < 0 ? 0 : itemsToAdd);

    /* Shuffle for all */
    for(int j = GetArraySize(voteList) - 1; j >= 1; j--)
    {
        int k = GetRandomInt(g_cv_ExtendPosition.IntValue, j);
        SwapArrayItems(voteList, j, k);
    }

    /* Insert to the menu */
    for(int i = 0; i < GetArraySize(voteList); i++)
    {
        GetArrayString(voteList, i, map, sizeof(map));
        if(StrEqual(map, VOTE_EXTEND))
        {
            AddMenuItem(g_VoteMenu, VOTE_EXTEND, "Extend Map");
        }
        else if(StrEqual(map, VOTE_DONTCHANGE))
        {
            AddMenuItem(g_VoteMenu, VOTE_DONTCHANGE, "Don't Change");
        }
        else if(StrEqual(map, VOTE_RANDOM))
        {
            AddMenuItem(g_VoteMenu, VOTE_RANDOM, "Random Map");
        }
        else AddMenuItem(g_VoteMenu, map, map);
    }

    /* Allow options on 9 and 0 if we can */
    if(voteList.Length <= GetMaxPageItems(GetMenuStyle(g_VoteMenu)))
    {
        SetMenuPagination(g_VoteMenu, MENU_NO_PAGINATION);
    }

    delete voteList;

    /* Shuffle options */
    if(g_cv_RandomVote.BoolValue)
    {
        if(extendAdded) MenuShufflePerClient(g_VoteMenu, g_cv_ExtendPosition.IntValue);
        else MenuShufflePerClient(g_VoteMenu);
    }

    VoteMenuToAll(g_VoteMenu, g_cv_VoteDuration.IntValue);
    CPrintToChatAll("%t %t", "Prefix", "Vote started");
    LogAction(-1, -1, "Map vote started.");

    g_bVoteInProgress = true;

    Call_StartForward(g_fwdVoteStarted);
    Call_PushCell(false);
    Call_Finish();
}

public void StartRunoffVote(MapChange when, Handle inputList)
{
    g_VoteMenu = CreateMenu(Handler_VoteMenu, MENU_ACTIONS_ALL);
    SetVoteResultCallback(g_VoteMenu, VoteHandler_VoteMenu);
    SetMenuTitle(g_VoteMenu, "Vote for the Next Map");

    /* Set 'No Vote' option */
    if(g_cv_NoVoteOption.BoolValue)
    {
        g_VoteMenu.NoVoteButton = true;
    }
    else
    {
        g_VoteMenu.NoVoteButton = false;
    }
    
    int size = GetArraySize(inputList);

    if(size <= GetMaxPageItems(GetMenuStyle(g_VoteMenu)))
    {
        SetMenuPagination(g_VoteMenu, MENU_NO_PAGINATION);
    }

    char map[PLATFORM_MAX_PATH];
    char desc[MAX_DESCRIPTION_LENGTH];
    for(int i = 0; i < size; i++)
    {
        GetArrayString(inputList, i, map, sizeof(map));
        if(StrEqual(map, VOTE_EXTEND))
        {
            AddMenuItem(g_VoteMenu, VOTE_EXTEND, "Extend Map");
        }
        else if(StrEqual(map, VOTE_DONTCHANGE))
        {
            AddMenuItem(g_VoteMenu, VOTE_DONTCHANGE, "Don't Change");
        }
        else if(StrEqual(map, VOTE_RANDOM))
        {
            AddMenuItem(g_VoteMenu, VOTE_RANDOM, "Random Map");
        }
        else
        {
            if(InternalGetMapDescription(map, desc, sizeof(desc)))
            {
                Format(desc, sizeof(desc), "%s [%s]", map, desc);
                AddMenuItem(g_VoteMenu, map, desc);
            }
            else
            {
                AddMenuItem(g_VoteMenu, map, map);
            }
        }
    }
    delete inputList;

    if(g_cv_RandomVote.BoolValue)
    {
        MenuShufflePerClient(g_VoteMenu);
    }

    VoteMenuToAll(g_VoteMenu, g_cv_VoteDuration.IntValue);
    CPrintToChatAll("%t %t", "Prefix", "Runoff Vote started");
    LogAction(-1, -1, "Runoff Map vote started.");

    Call_StartForward(g_fwdVoteStarted);
    Call_PushCell(true);
    Call_Finish();
}

public int Handler_VoteMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Display:
        {
            static char buffer[PLATFORM_MAX_PATH];
            Format(buffer, sizeof(buffer), "%T", "Menu - Vote Nextmap", param1);
            Handle panel = view_as<Handle>(param2);
            SetPanelTitle(panel, buffer);
        }
        case MenuAction_DisplayItem:
        {
            char map[PLATFORM_MAX_PATH];
            char buffer[PLATFORM_MAX_PATH];

            GetMenuItem(menu, param2, map, PLATFORM_MAX_PATH, _, _, _, param1);

            if(StrEqual(map, VOTE_EXTEND, false))
            {
                Format(buffer, sizeof(buffer), "%T", "Extend Map", param1);
            }
            else if(StrEqual(map, VOTE_DONTCHANGE, false))
            {
                Format(buffer, sizeof(buffer), "%T", "Dont Change", param1);
            }
            else if(StrEqual(map, VOTE_RANDOM, false))
            {
                Format(buffer, sizeof(buffer),"%T", "Random Map", param1);
            }
            else if(InternalGetMapDescription(map, buffer, sizeof(buffer)))
            {
                Format(buffer, sizeof(buffer), "%s [%s]", map, buffer);
            }

            if(buffer[0] != '\0')
            {
                return RedrawMenuItem(buffer);
            }
        }
        case MenuAction_VoteCancel:
        {
            /* Choose a random option if we should */
            if(param1 == VoteCancel_NoVotes && g_cv_ChooseRandom.BoolValue)
            {
                int count = GetMenuItemCount(menu);

                int item;
                char map[PLATFORM_MAX_PATH];
                bool valid;

                do
                {
                    valid = true;
                    item = GetRandomInt(0, count - 1);
                    GetMenuItem(menu, item, map, sizeof(map), _, _, _, -1);
                    
                    if(StrEqual(map, VOTE_EXTEND)) valid = false;
                    else if(StrEqual(map, VOTE_DONTCHANGE)) valid = false;
                }
                while(!valid);

                if(strcmp(map, VOTE_RANDOM, false) == 0)
                {
                    Format(map, sizeof(map), "%t", "Random Map");
                    SetNextMap(g_sRandomMap);
                }
                else
                {
                    SetNextMap(map);
                }

                CPrintToChatAll("%t %t", "Prefix", "Vote End - No Votes", map);
                LogAction(-1, -1, "Map voting finished. No votes received.");

                ShowNominators();

                g_bVoteEnded = true;
                WipeAllNominations(Removed_VoteEnded);
                WipeInsertedMaps();
            }
            g_bVoteInProgress = false;
        }
        case MenuAction_End: delete menu;
    }
    return 0;
}

public void VoteHandler_VoteMenu(Menu menu, 
                                int num_votes,              //Total number of votes
                                int num_clients,            //Number of clients who could vote
                                const int[][] client_info,  //Array of clients.  Use VOTEINFO_CLIENT_ defines.
                                int num_items,              //Number of unique items that were selected.
                                const int[][] item_info)    //Array of items, sorted by count.  Use VOTEINFO_ITEM defines
{
    char map[PLATFORM_MAX_PATH];

    /* Check if we need to make a runoff */
    if(g_cv_RunOffCount.IntValue > 0 && num_items > 1 && g_iRunoffCount < g_cv_RunOffCount.IntValue)
    {
        g_iRunoffCount++;
        int highest_votes = item_info[0][VOTEINFO_ITEM_VOTES];
        int required_percent = g_cv_RunOffPercent.IntValue;
        int required_votes = RoundToCeil(float(num_votes) * float(required_percent) / 100);

        if(highest_votes == item_info[1][VOTEINFO_ITEM_VOTES])
        {
            Handle maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
            
            for(int i = 0; i < num_items; i++)
            {
                if(item_info[i][VOTEINFO_ITEM_VOTES] == highest_votes)
                {
                    GetMenuItem(menu, item_info[i][VOTEINFO_ITEM_INDEX], map, sizeof(map),_,_,_, -1);
                    PushArrayString(maps, map);
                }
                else
                    break;
            }

            CPrintToChatAll("%t %t", "Prefix", "Tie Vote", GetArraySize(maps));
            SetupWarningTimer(WarningType_Revote, view_as<MapChange>(g_ChangeTime), maps);
            return;
        }
        else if(highest_votes < required_votes)
        {
            Handle maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

            GetMenuItem(menu, item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map),_,_,_,-1);
            PushArrayString(maps, map);

            for(int i = 1; i < num_items; i++)
            {
                if(GetArraySize(maps) < 2 || item_info[i][VOTEINFO_ITEM_VOTES] == item_info[i - 1][VOTEINFO_ITEM_VOTES])
                {
                    GetMenuItem(menu, item_info[i][VOTEINFO_ITEM_INDEX], map, sizeof(map),_,_,_,-1);
                    PushArrayString(maps, map);
                }
                else
                    break;
            }

            CPrintToChatAll("%t %t", "Prefix", "Revote is needed", required_percent);
            SetupWarningTimer(WarningType_Revote, view_as<MapChange>(g_ChangeTime), maps);
            return;
        }
    }

    //Standard vote end (no runoff)
    GetMenuItem(menu, item_info[0][VOTEINFO_ITEM_INDEX], map, sizeof(map),_,_,_,-1);

    if(StrEqual(map, VOTE_EXTEND, false))
    {
        g_iExtends++;

        int time;
        if(GetMapTimeLimit(time))
        {
            if(time > 0)
            {
                ExtendMapTimeLimit(g_cv_ExtendTime.IntValue * 60);
            }
        }

        CPrintToChatAll("%t %t", "Prefix", "Current Map Extended", (float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
        LogAction(-1, -1, "Voting for next map has finished. The current map has been extended.");

        g_iRunoffCount = 0;
        SetupTimeleftTimer();
    }
    else if(StrEqual(map, VOTE_DONTCHANGE, false))
    {
        CPrintToChatAll("%t %t", "Prefix", "Current Map Stays", (float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
        LogAction(-1, -1, "Voting for next map has finished. 'No Change' was the winner");

        g_iRunoffCount = 0;
        SetupTimeleftTimer();
    }
    else
    {
        if(g_ChangeTime == MapChange_MapEnd)
        {
            if(StrEqual(map, VOTE_RANDOM))
            {
                map = g_sRandomMap;
            }
            SetNextMap(map);
        }
        else if(g_ChangeTime == MapChange_Instant)
        {
            if(StrEqual(map, VOTE_RANDOM))
            {
                map = g_sRandomMap;
            }
            Handle data;
            CreateDataTimer(4.0, Timer_ChangeMap, data);
            WritePackString(data, map);
            g_bMapChangeInProgress = true;
        }
        else //MapChange_RoundEnd
        {
            if(StrEqual(map, VOTE_RANDOM))
            {
                map = g_sRandomMap;
            }
            SetNextMap(map);
            g_bChangeMapAtRoundEnd = true;
        }

        g_bVoteEnded = true;

        CPrintToChatAll("%t %t", "Prefix", "Nextmap Voting Finished", map, (float(item_info[0][VOTEINFO_ITEM_VOTES])/float(num_votes)*100), num_votes);
        LogAction(-1, -1, "Voting for next map has finished. Nextmap: %s.", map);

        ShowNominators();
    }

    g_bVoteInProgress = false;
    g_sRandomMap = "";

    Call_StartForward(g_fwdMapVoteEnded);
    Call_PushString(map);
    Call_Finish();

    WipeAllNominations(Removed_VoteEnded);
    WipeInsertedMaps();
}

public Action Timer_VoteRetry(Handle timer, Handle info)
{
    MapChange when = view_as<MapChange>(ReadPackCell(info));
    StartVote(when);
    return Plugin_Stop;
}

public Action Timer_ChangeMap(Handle timer, Handle pack)
{
    g_bMapChangeInProgress = false;

    char map[PLATFORM_MAX_PATH];

    if(pack == INVALID_HANDLE)
    {
        if(!GetNextMap(map, sizeof(map)))
        {
            return Plugin_Stop;
        }
    }
    else
    {
        ResetPack(pack);
        ReadPackString(pack, map, sizeof(map));
    }

    ForceChangeLevel(map, "Map Vote");

    return Plugin_Stop;
}

/**
 * Inserts all maps that were inserted to the nomlist by admins into the map vote
 *
 * @note Only called if there are actually inserted maps
 * @note Removes maps from nomlist if they have votes
 * 
 * @param       voteList    List to add to
 * @param       max         Maximum that can be added
 * @return                  Number of maps that got added
 */
public int InsertInsertedMaps(ArrayList voteList, int max)
{
    int added = 0;
    int left = g_InsertedMaps.Length;

    while(left > 0 && added <= max)
    {
        int index = GetRandomInt(0, left-1);

        char map[PLATFORM_MAX_PATH];
        g_InsertedMaps.GetString(index, map, sizeof(map));
        g_InsertedMaps.Erase(index);
        left--;

        int votes = 0;
        bool nom = g_Nominations.GetValue(map, votes);

        voteList.PushString(map);
        added++;

        if(g_cv_ExtendedLogging.BoolValue)
        {
            LogMessage("Added %s to vote.", map);
        }

        /* Call OnMapAddedToVote(map, votes, inserted) */
        Call_StartForward(g_fwdMapAddedToVote);
        Call_PushString(map);
        Call_PushCell(votes);
        Call_PushCell(true);
        Call_Finish();

        if(nom)
        {
            InternalRemoveNomsByMap(map, Removed_Ignore);
        }
    }

    return added;
}

/**
 * Inserts nominated maps to the map vote menu depending on the mode
 * Is not called if 0 maps are nominated
 *
 * @param       toAdd   Maximum number of maps that can be added
 * @return              Number of maps that got added
 */
public int InsertNominatedMaps(ArrayList voteList, int toAdd)
{
    if(g_NominationMode == NominationMode_Limited)
    {
        return InsertNominatedMapsLimited(voteList, toAdd);
    }

    int added = 0;
    NominationChooseMode mode = view_as<NominationChooseMode>(g_cv_NomChooseMode.IntValue);
    int noms = g_Nominations.Size;
    char map[PLATFORM_MAX_PATH];
    
    /* Copy the nominations so we can remove them cleanly */
    StringMap nomCopy = g_Nominations.Clone();
    StringMapSnapshot snap = g_Nominations.Snapshot();

    switch(mode)
    {
        case NominationMode_Top: // Add top X maps
        {
            /* Create array of votes sorted by descending */
            int[] orderedVotes = new int[noms];
            for(int i = 0; i < noms; i++)
            {
                int votes = 0;
                snap.GetKey(i, map, sizeof(map));
                nomCopy.GetValue(map, votes);
                orderedVotes[i] = votes;
            }
            SortIntegers(orderedVotes, noms, Sort_Descending);

            int first = 0; //first index with number of votes
            int last = 0;  //first index where votes are different (allows for 'last - first' for number of maps with x votes)
            while(toAdd > 0 && first < noms)
            {
                while(last < noms && orderedVotes[first] == orderedVotes[last])
                {
                    last++;
                }

                int count = last - first;
                if(count <= toAdd) //Add all the maps with X votes since there is enough room in the vote
                {
                    StringMapSnapshot snap2 = nomCopy.Snapshot(); //Need another snapshot if nomCopy gets reduced
                    for(int i = 0; i < snap2.Length; i++)
                    {
                        int votes = 0;
                        snap2.GetKey(i, map, sizeof(map));

                        if(CheckGroupMax(map, voteList, false) != 0)
                        {
                            nomCopy.Remove(map);
                            continue;
                        }

                        nomCopy.GetValue(map, votes);
                        if(votes == orderedVotes[first])
                        {
                            voteList.PushString(map);
                            added++;
                            toAdd--;
                            nomCopy.Remove(map);

                            if(g_cv_ExtendedLogging.BoolValue)
                            {
                                LogMessage("Added %s to vote.", map);
                            }

                            Call_StartForward(g_fwdMapAddedToVote);
                            Call_PushString(map);
                            Call_PushCell(votes);
                            Call_PushCell(false);
                            Call_Finish();
                        }
                    }
                    delete snap2;
                }
                else //Add toAdd noms with X votes but random
                {
                    //Add maps with X votes to array
                    ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

                    StringMapSnapshot snap2 = nomCopy.Snapshot(); //Need another snapshot if nomCopy gets reduced
                    for(int i = 0; i < snap2.Length; i++)
                    {
                        int votes = 0;
                        snap2.GetKey(i, map, sizeof(map));
                        nomCopy.GetValue(map, votes);
                        if(votes == orderedVotes[first])
                        {
                            maps.PushString(map);
                            nomCopy.Remove(map);
                        }
                    }
                    delete snap2;

                    while(toAdd > 0)
                    {
                        int rand = GetRandomInt(0, maps.Length-1);
                        GetArrayString(maps, rand, map, sizeof(map));

                        if(CheckGroupMax(map, voteList, false) != 0)
                        {
                            nomCopy.Remove(map);
                            continue;
                        }

                        int votes = 0;
                        nomCopy.GetValue(map, votes);

                        voteList.PushString(map);
                        added++;
                        toAdd--;
                        maps.Erase(rand);
                        nomCopy.Remove(map);

                        if(g_cv_ExtendedLogging.BoolValue)
                        {
                            LogMessage("Added %s to vote.", map);
                        }

                        Call_StartForward(g_fwdMapAddedToVote);
                        Call_PushString(map);
                        Call_PushCell(votes);
                        Call_PushCell(false);
                        Call_Finish();
                    }
                    delete maps;
                }
                
                first = last;
                last++;
            }
        }
        case NominationMode_Random: // Add X random maps (simplest)
        {
            while(toAdd > 0 || nomCopy.Size > 0)
            {
                int votes;
                snap.GetKey(GetRandomInt(0, nomCopy.Size-1), map, sizeof(map));

                if(CheckGroupMax(map, voteList, false) != 0)
                {
                    nomCopy.Remove(map);
                    continue;
                }

                nomCopy.GetValue(map, votes);
                if(votes > 0)
                {
                    voteList.PushString(map);
                    toAdd--;
                    added++;

                    if(g_cv_ExtendedLogging.BoolValue)
                    {
                        LogMessage("Added %s to vote.", map);
                    }
                }
                nomCopy.Remove(map);

                /* Call OnMapAddedToVote(map, votes, inserted) */
                Call_StartForward(g_fwdMapAddedToVote);
                Call_PushString(map);
                Call_PushCell(votes);
                Call_PushCell(false);
                Call_Finish();
            }
        }
        case NominationMode_Weighted: // Weight maps and pick X randomly
        {
            ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

            for(int i = 0; i < noms; i++)
            {
                int votes = 0;
                snap.GetKey(i, map, sizeof(map));

                if(CheckGroupMax(map, voteList, false) != 0)
                {
                    nomCopy.Remove(map);
                    continue;
                }

                nomCopy.GetValue(map, votes);

                for(int j = votes; j > 0; j--)
                {
                    maps.PushString(map);
                }
            }

            while(toAdd > 0 && maps.Length > 0)
            {
                int rand = GetRandomInt(0, maps.Length-1);
                int votes = 0;
                GetArrayString(maps, rand, map, sizeof(map));

                if(CheckGroupMax(map, voteList, false) != 0)
                {
                    nomCopy.Remove(map);
                    int index = FindStringInArray(maps, map);
                    while(index != -1)
                    {
                        maps.Erase(index);
                        index = FindStringInArray(maps, map);
                    }
                    continue;
                }

                nomCopy.GetValue(map, votes);

                voteList.PushString(map);
                added++;
                toAdd--;

                if(g_cv_ExtendedLogging.BoolValue)
                {
                    LogMessage("Added %s to vote.", map);
                }

                Call_StartForward(g_fwdMapAddedToVote);
                Call_PushString(map);
                Call_PushCell(votes);
                Call_PushCell(false);
                Call_Finish();

                int index = FindStringInArray(maps, map);
                while(index != -1)
                {
                    maps.Erase(index);
                    index = FindStringInArray(maps, map);
                }

                nomCopy.Remove(map);
            }

            delete maps;
        }
    }

    delete snap;
    delete nomCopy;

    return added;
}

/**
 * Inserts nominated maps to the map vote menu
 * This is only called if NominateMode is limited
 * 
 * @param toAdd        Maximum number of maps that can be added
 * @return             Number of maps that got added
 */
public int InsertNominatedMapsLimited(ArrayList voteList, int toAdd)
{
    int added = 0;
    char map[PLATFORM_MAX_PATH];
    int votes;
    int noms = g_Nominations.Size;

    StringMapSnapshot snap = g_Nominations.Snapshot();
    if(toAdd <= noms) //We can add all the noms
    {
        for(int i = 0; i < noms; i++)
        {
            snap.GetKey(i, map, sizeof(map));
            g_Nominations.GetValue(map, votes);
            voteList.PushString(map);
            added++;
            toAdd--;

            if(g_cv_ExtendedLogging.BoolValue)
            {
                LogMessage("Added %s to vote.", map);
            }

            Call_StartForward(g_fwdMapAddedToVote);
            Call_PushString(map);
            Call_PushCell(votes);
            Call_PushCell(false);
            Call_Finish();
        }
    }
    else //Need to choose randomly
    {
        StringMap nomCopy = CreateTrie();
        for(int i = 0; i < noms; i++)
        {
            snap.GetKey(i, map, sizeof(map));
            g_Nominations.GetValue(map, votes);
            nomCopy.SetValue(map, votes);
        }
        votes = -1;
        while(toAdd > 0 || nomCopy.Size > 0)
        {
            snap.GetKey(GetRandomInt(0, nomCopy.Size-1), map, sizeof(map));

            if(CheckGroupMax(map, voteList, false) != 0)
            {
                nomCopy.Remove(map);
                continue;
            }

            nomCopy.GetValue(map, votes);
            if(votes > 0)
            {
                voteList.PushString(map);
                toAdd--;
                added++;

                if(g_cv_ExtendedLogging.BoolValue)
                {
                    LogMessage("Added %s to vote.", map);
                }
            }
            nomCopy.Remove(map);

            /* Call OnMapAddedToVote(map, votes, inserted) */
            Call_StartForward(g_fwdMapAddedToVote);
            Call_PushString(map);
            Call_PushCell(votes);
            Call_PushCell(false);
            Call_Finish();
        }
        delete nomCopy;
    }

    delete snap;
    return added;
}

/**
 * Inserts non-nominated maps to the map vote menu
 * Only adds maps that fit the current player/time/cooldown/group restrictions
 *
 * @param       toAdd   Maximum number of maps that can be added
 * @return              Number of maps that got added
 */
public int InsertRandomMaps(ArrayList voteList, int toAdd)
{
    int added = 0;

    ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    char map[PLATFORM_MAX_PATH];

    //Add all valid map to a list
    for(int i = 0; i < g_MapList.Length; i++)
    {
        GetArrayString(g_MapList, i, map, sizeof(map));

        if(InternalGetMapCurrentCooldown(map) > 0) continue;
        if(InternalGetMapPlayerRestriction(map) != 0) continue;
        if(InternalGetMapTimeRestriction(map) != 0) continue;
        if(InternalIsMapInserted(map)) continue;
        if(InternalGetMapVotes(map) > 0) continue;
        if(InternalIsMapAdminOnly(map)) continue;
        if(InternalIsMapNominateOnly(map)) continue;
        if(CheckGroupMax(map, voteList, false) != 0) continue;
        if(FindStringInArray(voteList, map) != -1) continue;
        
        maps.PushString(map);
    }

    int rand;

    /* Set the 'Random Map' option here */
    if(g_cv_RandomMap.BoolValue)
    {
        rand = GetRandomInt(0, maps.Length-1);
        GetArrayString(maps, rand, map, sizeof(map));
        strcopy(g_sRandomMap, sizeof(g_sRandomMap), map);
        maps.Erase(rand);
   }

    /* Add as many random maps as we can */
    while(toAdd > 0 && maps.Length > 0)
    {
        rand = GetRandomInt(0, maps.Length-1);
        GetArrayString(maps, rand, map, sizeof(map));

        if(CheckGroupMax(map, voteList) != 0)
        {
            maps.Erase(rand);
            continue;
        }

        voteList.PushString(map);
        added++;
        toAdd--;

        if(g_cv_ExtendedLogging.BoolValue)
        {
            LogMessage("Added %s to vote.", map);
        }

        maps.Erase(rand);
    }

    delete maps;
    return added;
}

/**
 * Checks all nominated map restrictions
 * 
 * @param players     Should player restriction be checked
 * @param time        Should time restriction be checked
 *
 */
void CheckNomRestrictions(bool players = false, bool time = false)
{
    if(!players && !time) return;

    StringMapSnapshot snap = g_Nominations.Snapshot();
    if(snap.Length == 0) return;

    for(int i = 0; i < snap.Length; i++)
    {
        bool remove = false;
        char map[PLATFORM_MAX_PATH];
        GetTrieSnapshotKey(snap, i, map, sizeof(map));
        
        if(players)
        {
            int playerLimit = InternalGetMapPlayerRestriction(map);
            if(playerLimit < 0)
            {
                remove = true;
                InternalRemoveNomsByMap(map, Removed_NotEnoughPlayers);
            }
            else if(playerLimit > 0)
            {
                remove = true;
                InternalRemoveNomsByMap(map, Removed_TooManyPlayers);
            }
        }

        if(time && !remove)
        {
            int timeLimit = InternalGetMapTimeRestriction(map);
            if(timeLimit != 0)
            {
                remove = true;
                InternalRemoveNomsByMap(map, Removed_Time);
            }
        }
    }
    delete snap;
}

public void ShowNominators()
{
    char nextmap[PLATFORM_MAX_PATH];
    if(!GetNextMap(nextmap, sizeof(nextmap))) return;

    char lognames[512];
    char names[512];
    int count;
    for(int i = 1; i <= MaxClients; i++)
    {
        if(!StrEqual(g_sNominations[i], nextmap)) continue;
        if(!IsClientInGame(i)) continue;

        Format(lognames, sizeof(lognames), "%s %L", lognames, i);
        Format(names, sizeof(names), "%s%s%N", names, count>0 ? ", " : " ", i);
        count++;
    }
    
    if(count == 0)
    {
        Format(names, sizeof(names), "%s", "Noone");
        Format(lognames, sizeof(lognames), "%s", "Noone");

        if(g_cv_ShowNominators.BoolValue) CPrintToChatAll("%t %t %t", "Prefix", "Nominated by", names);
        LogMessage("Winning map nominated by: %s", lognames);

        return;
    }

    if(g_cv_ShowNominators.BoolValue) CPrintToChatAll("%t %t %s", "Prefix", "Nominated by", names);
    LogMessage("Winning map nominated by:%s", lognames);
}

/* *********************************************************************** */
/* *************************                 ***************************** */
/* *************************     NATIVES     ***************************** */
/* *************************                 ***************************** */
/* *********************************************************************** */ 

public int Native_EndOfMapVoteEnabled(Handle plugin, int numParams)
{
    return g_cv_Enabled.BoolValue;
}

public int Native_GetNominationMode(Handle plugin, int numParams)
{
    return view_as<int>(g_NominationMode);
}

/* bool CanMapVoteStart() */
public int Native_CanVoteStart(Handle plugin, int numParams)
{
    if(g_bWaitingForVote || g_bVoteInProgress)
        return false;
    
    return true;
}

public int Native_IsMapVoteInProgress(Handle plugin, int numParams)
{
    return g_bVoteInProgress;
}

public int Native_HasVoteFinished(Handle plugin, int numParams)
{
    return g_bVoteEnded;
}

public int Native_GetExtendsUsed(Handle plugin, int numParams)
{
    return g_iExtends;
}

public int Native_InitiateVote(Handle plugin, int numParams)
{
    MapChange when = view_as<MapChange>(GetNativeCell(1));
    Handle inputarray = view_as<Handle>(GetNativeCell(2));

    char pluginname[64];
    GetPluginFilename(plugin, pluginname, sizeof(pluginname));
    
    LogMessage("Starting map vote because of plugin (%s)", pluginname);

    SetupWarningTimer(WarningType_Vote, when, inputarray);
    return 0;
}

/* NominateResult NominateMap(int client, const char[] map, bool force); */
public int Native_NominateMap(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(2, map, len);

    int client = GetNativeCell(1);
    bool force = GetNativeCell(3);
    return view_as<int>(InternalNominateMap(client, map, force));
}

/**
 * Attempt to add a nomination to the nomlist
 * 
 * @param client     Client nominating (0 for server, ignored if force==true)
 * @param map        Map being nominated
 * @param force      Is the map being inserted
 * @return           Nominate result
 */
NominateResult InternalNominateMap(int client, const char[] map, bool force)
{
    /* Check if map has already been inserted by an admin */
    if(InternalIsMapInserted(map))
    {
        return Nominate_AlreadyAdded;
    }

    /* Map is being inserted */
    if(force)
    {
        g_InsertedMaps.PushString(map);

        InternalRemoveNomsByMap(map, Removed_Inserted);

        /* Call OnMapInserted(admin, map) */
        Call_StartForward(g_fwdMapInserted);
        Call_PushCell(client);
        Call_PushString(map);
        Call_Finish();

        LogAction(client, -1, "%L inserted %s into nomlist.", client, map);

        return Nominate_Inserted;
    }

    if(g_NominationMode == NominationMode_Limited)
    {
        if(InternalIsMapNominated(map))
        {
            return Nominate_AlreadyNominated;
        }
    }
    
    bool replaced = false;
    int votes = InternalGetMapVotes(map);
    
    if(votes == -1) votes = 0;
    votes++;

    if(ClientHasNomination(client))
    {
        replaced = true;
    }

    if(client != 0)
    {
        InternalRemoveNomByOwner(client, Removed_Replaced);
        strcopy(g_sNominations[client], sizeof(g_sNominations[]), map);
    }

    g_Nominations.SetValue(map, votes);

    LogAction(client, -1, "%L nominated %s [%d votes]", client, map, votes);

    /* Call OnMapNominated(client, map, votes, replaced) */
    Call_StartForward(g_fwdMapNominated);
    Call_PushCell(client);
    Call_PushString(map);
    Call_PushCell(votes);
    Call_PushCell(replaced);
    Call_Finish();

    if(replaced)
    {
        return Nominate_Replaced;
    }
    
    return Nominate_Added;
}

/* CanNominateResult CanNominate(int client) */
public int Native_CanNominate(Handle plugin, int numParams)
{
    if(g_bVoteEnded)
    {
        return view_as<int>(CanNominate_VoteComplete);
    }

    if(g_bVoteInProgress)
    {
        return view_as<int>(CanNominate_VoteInProgress);
    }

    if(g_NominationMode == NominationMode_Limited)
    {
        if(g_Nominations.Size >= g_cv_Include.IntValue)
        {
            if(ClientHasNomination(GetNativeCell(1)))
            {
                return view_as<int>(CanNominate_VoteFull);
            }
        }
    }

    return view_as<int>(CanNominate_Yes);
}

/* CanClientNominateResult CanMapBeNominated(int client, const char[] map) */
public int Native_CanMapBeNominated(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(2, map, len);

    int client = GetNativeCell(1);

    bool ok = true;
    int flags = 0;

    /* Check current map */
    char curMap[PLATFORM_MAX_PATH];
    GetCurrentMap(curMap, sizeof(curMap));
    if(StrEqual(map, curMap))
    {
        flags = flags | CanClientNom_CurrentMap;
        ok = false;
    }

    /* Check current nomination */
    if(StrEqual(map, g_sNominations[client]))
    {
        flags = flags | CanClientNom_CurrentNom;
        ok = false;
    }

    /* Check cooldown */
    if(InternalGetMapCurrentCooldown(map) > 0)
    {
        flags = flags | CanClientNom_Cooldown;
        ok = false;
    }

    /* Check player limits */
    int state = InternalGetMapPlayerRestriction(map);
    if(state < 0)
    {
        flags = flags | CanClientNom_NotEnoughPlayers;
        ok = false;
    }
    else if(state > 0)
    {
        flags = flags | CanClientNom_TooManyPlayers;
        ok = false;
    }

    /* Check time */
    state = InternalGetMapTimeRestriction(map);
    if(state != 0)
    {
        flags = flags | CanClientNom_Time;
        ok = false;
    }

    /* Check admin only (allow admin only maps that have more than 1 vote) */
    if(IsMapAdminOnly(map))
    {
        flags = flags | CanClientNom_AdminOnly;
        int votes = 0;
        g_Nominations.GetValue(map, votes);
        if(votes <= 0 && !CheckCommandAccess(client, "sm_adminnom", ADMFLAG_BAN))
        {
            ok = false;
        }
    }

    /* Check insertions */
    if(InternalIsMapInserted(map))
    {
        flags = flags | CanClientNom_Inserted;
        ok = false;
    }

    if(g_NominationMode == NominationMode_Limited)
    {
        if(InternalIsMapNominated(map))
        {
            flags = flags | CanClientNom_Nominated;
            ok = false;
        }
        if(InternalGetMapGroupRestriction(map) != 0)
        {
            flags = flags | CanClientNom_GroupMax;
            ok = false;
        }
    }

    if(ok) flags = flags | CanClientNom_Yes;

    return flags;
}

/* int GetNominatedMapList(StringMap maparray) */
public int Native_GetNominatedMapList(Handle plugin, int numParams)
{
    if(g_Nominations.Size == 0) return 0;

    StringMap maps = view_as<StringMap>(GetNativeCell(1));
    
    if(maps == INVALID_HANDLE) return -1;
    
    StringMapSnapshot snap = g_Nominations.Snapshot();
    for(int i = 0; i < snap.Length; i++)
    {
        char map[PLATFORM_MAX_PATH];
        int votes;
        snap.GetKey(i, map, sizeof(map));
        g_Nominations.GetValue(map, votes);
        
        maps.SetValue(map, votes);
    }
    delete snap;
    
    return g_Nominations.Size;
}

/* int GetMapVotes(const char[] map) */
public int Native_GetMapVotes(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapVotes(map);
}

/**
 * Gets the number of votes a given map has.
 * 
 * @param map     Map to get votes for
 * @return        Number of votes (-1 if not nominated)
 */
public int InternalGetMapVotes(const char[] map)
{
    int votes = 0;
    if(!g_Nominations.GetValue(map, votes)) return -1;
    return votes;
}

/* bool IsMapInserted(const char[] map) */
public int Native_IsMapInserted(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalIsMapInserted(map);
}

/**
 * Checks if a map has been inserted to the nomlist by an admin
 * 
 * @param map     Name of map
 * @return        True if inserted, false otherwise
 */
public bool InternalIsMapInserted(const char[] map)
{
    if(g_InsertedMaps.FindString(map) != -1) return true;

    return false;
}

/* int GetInsertedMapList(ArrayList maparray) */
public int Native_GetInsertedMapList(Handle plugin, int numParams)
{
    if(g_InsertedMaps.Length == 0) return 0;

    ArrayList maps = view_as<ArrayList>(GetNativeCell(1));

    if(maps == INVALID_HANDLE) return -1;

    for(int i = 0; i < g_InsertedMaps.Length; i++)
    {
        char map[PLATFORM_MAX_PATH];
        GetArrayString(g_InsertedMaps, i, map, sizeof(map));
        PushArrayString(maps, map);
    }
    
    return g_InsertedMaps.Length;
}

/* bool IsMapNominated(const char[] map) */
public int Native_IsMapNominated(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalIsMapNominated(map);
}

public bool InternalIsMapNominated(const char[] map)
{
    int votes;
    if(g_Nominations.GetValue(map, votes))
    {
        return (votes > 0);
    }
    return false;
}

/* bool RemoveNominationByOwner(int client, NominateRemoved reason) */
public int Native_RemoveNomByOwner(Handle plugin, int numParams)
{
    NominateRemoved reason = view_as<NominateRemoved>(GetNativeCell(2));
    return view_as<int>(InternalRemoveNomByOwner(GetNativeCell(1), reason));
}

/**
 * Removes a given client's nomination
 * 
 * @param client     Client (0 is ignored since it can have multiple noms)
 * @param reason     NominateRemoved reason for removal
 * @return           True=nomination was found and removed, false=nomination was not found.
 */
public bool InternalRemoveNomByOwner(int client, NominateRemoved reason)
{
    if(client <= 0 || client > MaxClients) return false;

    if(!ClientHasNomination(client)) return false;

    int votes = 0;
    if(!g_Nominations.GetValue(g_sNominations[client], votes))
    {
        //This is a bad place to be, should never happen
        g_sNominations[client] = "";
        return false;
    }
    
    votes--;
    if(votes <= 0)
    {
        g_Nominations.Remove(g_sNominations[client]);
    }
    else
    {
        g_Nominations.SetValue(g_sNominations[client], votes);
    }
    
    Call_StartForward(g_fwdNominationRemoved);
    Call_PushCell(reason);
    Call_PushString(g_sNominations[client]);
    Call_PushCell(client);
    Call_Finish();

    g_sNominations[client] = "";
    return true;
}

/* int RemovedNominationsByMap(const char[] map, NominateRemoved reason) */
public int Native_RemoveNomByMap(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    NominateRemoved reason = view_as<NominateRemoved>(GetNativeCell(2));

    return InternalRemoveNomsByMap(map, reason);
}

/**
 * Removes all votes for a given map
 * 
 * @param map        Name of map
 * @param reason     NominateRemoved reason for removal
 * @return           Number of client votes removed (Not including admin forced votes)
 */
public int InternalRemoveNomsByMap(const char[] map, NominateRemoved reason)
{
    int votes = 0;
    if(!g_Nominations.GetValue(map, votes)) return 0;

    int count = 0;
    for(int client = 1; client <= MaxClients; client++)
    {
        if(StrEqual(g_sNominations[client], map))
        {
            InternalRemoveNomByOwner(client, reason);
            count++;
        }
    }
    if(!g_Nominations.GetValue(map, votes)) return count;

    g_Nominations.Remove(map);
    
    return count;
}

/* bool RemoveInsertedMap(int client, const char[] map) */
public int Native_RemoveInsertedMap(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(2, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(2, map, len);

    return InternalRemoveInsertedMap(GetNativeCell(1), map);
}

public bool InternalRemoveInsertedMap(int client, const char[] map)
{
    int index = FindStringInArray(g_InsertedMaps, map);
    if(index == -1) return false;

    g_InsertedMaps.Erase(index);
    
    LogAction(client, -1, "%L uninserted the map %s", client, map);

    return true;
}

/* bool GetClientNomination(int client, char[] map, int maxlen) */
public int Native_GetClientNomination(Handle plugin, int numParams)
{
    int client = GetNativeCell(1);
    if(!ClientHasNomination(client)) return false;

    int len = GetNativeCell(3);
    SetNativeString(2, g_sNominations[client], len);

    return true;
}

/* int GetMapNominators(const char[] map, int[] clients, int maxlen) */
public int Native_GetMapNominators(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    int votes;
    if(!g_Nominations.GetValue(map, votes)) return 0;

    int maxlen = GetNativeCell(3);
    int[] clients = new int[maxlen+1];
    int index = InternalGetMapNominators(map, clients, maxlen);

    SetNativeArray(2, clients, maxlen);
    return index;
}

/**
 * Gets the client indexes which nominated a given map
 * 
 * @param map         Name of map
 * @param clients     Array to store client indexes in
 * @param max         Maximum number of clients
 * @return            Number of clients who nominated
 */
public int InternalGetMapNominators(const char[] map, int[] clients, int max)
{
    int count = 0;

    for(int i = 1; i <= MaxClients; i++)
    {
        if(count >= max) return count;
        if(StrEqual(g_sNominations[i], map))
        {
            clients[count] = i;
            count++;
        }
    }
    return count;
}

/* bool ExcludeMap(const char[] map, CooldownMode mode, int cooldown = 0) */
public int Native_ExcludeMap(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    CooldownMode mode = view_as<CooldownMode>(GetNativeCell(2));
    if(mode == Cooldown_Value || mode == Cooldown_ValueGreater)
    {
        int cooldown = GetNativeCell(3);
        return InternalSetMapCooldown(map, mode, cooldown);
    }
    return InternalSetMapCooldown(map, mode);
}

/**
 * Sets a given map's current cooldown
 * 
 * @param map          Name of map
 * @param mode         CooldownMode to use
 * @param cooldown     Cooldown to set if mode>1
 * @return             True on cooldown changed
 */
bool InternalSetMapCooldown(const char[] map, CooldownMode mode, int cooldown = 0)
{
    if(mode == Cooldown_Config || mode == Cooldown_ConfigGreater)
    {
        int cd = GetMapBaseCooldown(map);
        if(mode == Cooldown_Config)
        {
            SetCooldown(map, cd);
            return true;
        }
        
        if(cd > InternalGetMapCurrentCooldown(map))
        {
            SetCooldown(map, cd);
            return true;
        }
        return false;
    }

    if(mode == Cooldown_Value)
    {
        SetCooldown(map, cooldown);
        return true;
    }

    if(cooldown > InternalGetMapCurrentCooldown(map))
    {
        SetCooldown(map, cooldown);
        return true;
    }
    return false;
}

/* int GetMapCooldown(const char[] map) */
public int Native_GetMapCooldown(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapCurrentCooldown(map);
}

/**
 * Gets a given map's current cooldown value
 * 
 * @param map     Name of map
 * @return        Cooldown value, 0=Not on cooldown
 */
public int InternalGetMapCurrentCooldown(const char[] map)
{
    int cd = 0;
    if(g_RecentMaps.GetValue(map, cd))
    {
        return cd;
    }
    return 0;
}

/* int GetMapPlayerRestriction(const char[] map) */
public int Native_GetMapPlayerRestriction(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapPlayerRestriction(map);
}

/**
 * Gets a given map's current player restriction status
 * 
 * @param map     Name of map
 * @return        Restriction status
 *                <0 Less than MinPlayers (Number of players needed to join)
 *                =0 Okay
 *                >0 More than MaxPlayers (Number of players needed to leave)
 */
public int InternalGetMapPlayerRestriction(const char[] map)
{
    int players = GetClientCount();

    int check = InternalGetMapMinPlayers(map);
    if(check != 0 && players < check) return players - check;

    check = InternalGetMapMaxPlayers(map);
    if(check != 0 && players > check) return players - check;

    return 0;
}

public int Native_GetMapMinPlayers(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapMinPlayers(map);
}

public int InternalGetMapMinPlayers(const char[] map)
{
    if(!g_bConfig) return 0;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return 0;

    return g_kvConfig.GetNum("MinPlayers");
}

public int Native_GetMapMaxPlayers(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapMaxPlayers(map);
}

public int InternalGetMapMaxPlayers(const char[] map)
{
    if(!g_bConfig) return 0;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return 0;
    
    return g_kvConfig.GetNum("MaxPlayers");
}

/* int GetMapTimeRestriction(const char[] map) */
public int Native_GetMapTimeRestriction(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapTimeRestriction(map);
}

/**
 * Gets how many minutes until a map's time restriction is lifted
 * 
 * @param map     Name of map
 * @return        0 = okay, >0 = Minutes until ok
 */
public int InternalGetMapTimeRestriction(const char[] map)
{
    char sTime[8];
    FormatTime(sTime, sizeof(sTime), "%H%M");

    int CurTime = StringToInt(sTime);
    int MinTime = InternalGetMapMinTime(map);
    int MaxTime = InternalGetMapMaxTime(map);

    //Wrap around.
    CurTime = (CurTime <= MinTime) ? CurTime + 2400 : CurTime;
    MaxTime = (MaxTime <= MinTime) ? MaxTime + 2400 : MaxTime;

    if (!(MinTime <= CurTime <= MaxTime))
    {
        //Wrap around.
        MinTime = (MinTime <= CurTime) ? MinTime + 2400 : MinTime;
        MinTime = (MinTime <= MaxTime) ? MinTime + 2400 : MinTime;

        // Convert our 'time' to minutes.
        CurTime = (RoundToFloor(float(CurTime / 100)) * 60) + (CurTime % 100);
        MinTime = (RoundToFloor(float(MinTime / 100)) * 60) + (MinTime % 100);
        MaxTime = (RoundToFloor(float(MaxTime / 100)) * 60) + (MaxTime % 100);

        return MinTime - CurTime;
    }

    return 0;
}

public int Native_GetMapMinTime(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapMinTime(map);
}

public int InternalGetMapMinTime(const char[] map)
{
    if(!g_bConfig) return 0;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return 0;

    return g_kvConfig.GetNum("MinTime");
}

public int Native_GetMapMaxTime(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapMaxTime(map);
}

public int InternalGetMapMaxTime(const char[] map)
{
    if(!g_bConfig) return 0;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return 0;
    
    return g_kvConfig.GetNum("MaxTime");
}

/* bool IsMapAdminOnly(const char[] map) */
public int Native_IsMapAdminOnly(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalIsMapAdminOnly(map);
}

/**
 * Gets whether a given map can only be initally nominated by admins
 * 
 * @param map     Name of map
 * @return        True if admin only, false otherwise
 */
public bool InternalIsMapAdminOnly(const char[] map)
{
    if(!g_bConfig) return false;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return false;

    return (g_kvConfig.GetNum("AdminOnly") == 1);
}

/* bool IsMapNominateOnly(const char[] map) */
public int Native_IsMapNominateOnly(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalIsMapNominateOnly(map);
}

/**
 * Gets whether a map can only appear in votes from nominations
 * 
 * @param map     Name of map
 * @return        True if nominate only, false otherwise
 */
public bool InternalIsMapNominateOnly(const char[] map)
{
    if(!g_bConfig) return false;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return false;

    return (g_kvConfig.GetNum("NominateOnly") == 1);
}

/* int GetMapDescription(const char[] map, char[] buffer, int maxlen) */
public int Native_GetMapDescription(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    int maxlen = GetNativeCell(3);
    char[] buffer = new char[maxlen];

    InternalGetMapDescription(map, buffer, maxlen);
    SetNativeString(2, buffer, maxlen);

    return strlen(buffer);
}

/**
 * Gets the description for a map
 * 
 * @param map        Name of map
 * @param buffer     Buffer to store the description in
 * @param maxlen     Maximum length of the buffer
 * @return           True if a description was found, false otherwise
 */
public bool InternalGetMapDescription(const char[] map, char[] buffer, int maxlen)
{
    if(!g_bConfig) return false;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return false;

    g_kvConfig.GetString("Description", buffer, maxlen);
    if(StrEqual(buffer, "")) return false;

    return true;
}

/* int GetMapGroupRestriction(const char[] map) */
public int Native_GetMapGroupRestriction(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapGroupRestriction(map);
}

/**
 * Gets the group restriction for a map, use to check if a map can be nominated
 * @note If nomination mode is currently infinite, it will always return 0
 * 
 * @param map     Name of map
 * @return        >0 = Group max is reached(Value of max), 0 if no restriction
 */
public int InternalGetMapGroupRestriction(const char[] map)
{
    if(g_NominationMode == NominationMode_Infinite) return 0;

    ArrayList nomList = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));
    StringMapSnapshot snap = g_Nominations.Snapshot();
    char temp[PLATFORM_MAX_PATH];

    for(int i = 0; i < snap.Length; i++)
    {
        GetTrieSnapshotKey(snap, i, temp, sizeof(temp));
        nomList.PushString(temp);
    }
    delete snap;
    int val = CheckGroupMax(map, nomList, false);
    delete nomList;
    return val;
}

public int Native_GetMapMaxExtends(Handle plugin, int numParams)
{
    int len;
    GetNativeStringLength(1, len);
    if(len <= 0) return -1;
    len+=1;
    char[] map = new char[len];
    GetNativeString(1, map, len);

    return InternalGetMapMaxExtends(map);
}

public int InternalGetMapMaxExtends(const char[] map)
{
    int extends = g_cv_Extends.IntValue;
    if(!g_bConfig) return extends;

    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return extends;

    return g_kvConfig.GetNum("Extends", extends);
}

/**
 * Gets a given map's cooldown from the config, or from the cvar if not found in config
 * 
 * @param map     Name of map
 * @return        Cooldown value
 */
stock int GetMapBaseCooldown(const char[] map)
{
    int cd = g_cv_Cooldown.IntValue;
    if(!g_bConfig) return cd;

    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey(map)) return cd;
    
    return g_kvConfig.GetNum("Cooldown", cd);
}

/**
 * Checks if a given client has a nomination (passing 0 always returns false)
 * 
 * @param client     Client to check
 * @return           True=Client has a nomination, false = no nomination
 */
stock bool ClientHasNomination(int client)
{
    if(client > 0 && client <= MaxClients)
    {
        return !(StrEqual(g_sNominations[client], ""));
    }
    return false;
}

public void SetCooldown(const char[] map, int cooldown)
{
    if(cooldown > 0)
    {
        g_RecentMaps.SetValue(map, cooldown);
    }
    else
    {
        g_RecentMaps.Remove(map);
    }
}

public bool LoadConfig()
{
    if(g_bConfig)
    {
        delete g_kvConfig;
        g_bConfig = false;
    }
    g_iGroups = 0;

    char sConfigFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/mapchooser_unlimited.cfg");
    if(!FileExists(sConfigFile))
    {
        char backupConfig[PLATFORM_MAX_PATH];
        BuildPath(Path_SM, backupConfig, sizeof(backupConfig), "configs/mapchooser_extended.cfg");
        if(!FileExists(backupConfig))
        {
            LogMessage("Could not find config: \"%s\"", sConfigFile);
            return false;
        }
        strcopy(sConfigFile, sizeof(sConfigFile), backupConfig);
    }
    
    LogMessage("Found config: \"%s\"", sConfigFile);

    g_kvConfig = new KeyValues("mapchooser_unlimited");
    if(!g_kvConfig.ImportFromFile(sConfigFile))
    {
        delete g_kvConfig;
        LogMessage("ImportFromFile() failed!");
        return false;
    }
    g_kvConfig.Rewind();
    g_bConfig = true;

    g_iGroups = CountGroups();
    if(g_cv_ExtendedLogging.BoolValue) LogMessage("Found %d groups in the config.", g_iGroups);

    return true;
}

stock int CountGroups()
{
    int count = 0;

    if(!g_kvConfig.JumpToKey("Groups")) return count;
    if(!g_kvConfig.GotoFirstSubKey()) return count;
    
    count++;

    while(g_kvConfig.GotoNextKey()) count++;

    return count;
}

stock char[] GetRandomMap()
{
    char map[PLATFORM_MAX_PATH];
    ArrayList maps = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

    for(int i = 0; i < g_MapList.Length; i++)
    {
        GetArrayString(g_MapList, i, map, sizeof(map));

        if(InternalGetMapCurrentCooldown(map) > 0) continue;
        if(InternalGetMapPlayerRestriction(map) != 0) continue;
        if(InternalGetMapTimeRestriction(map) != 0) continue;
        //if(InternalIsMapInserted(map)) continue;
        //if(InternalGetMapVotes(map) > 0) continue;
        if(InternalIsMapAdminOnly(map)) continue;
        if(InternalIsMapNominateOnly(map)) continue;

        maps.PushString(map);
    }

    int rand = GetRandomInt(0, GetArraySize(maps)-1);
    GetArrayString(maps, rand, map, sizeof(map));

    delete maps;
    return map;
}

/**
 * Sets all the maps in groups with the provided map on the group cooldown value
 * 
 * @param map     Name of map
 */
public void SetMapGroupsCooldown(const char[] map)
{
    if(!g_bConfig) return;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey("Groups")) return;

    if(!g_kvConfig.GotoFirstSubKey(false)) return;

    int cd;
    do
    {
        cd = g_kvConfig.GetNum("Cooldown");
        if(cd == 0) continue;

        if(g_kvConfig.JumpToKey(map))
        {
            g_kvConfig.GoBack();
            char groupName[64];
            g_kvConfig.GetSectionName(groupName, sizeof(groupName));

            SetGroupCooldown(map, groupName, cd);
            
            g_kvConfig.Rewind();
            g_kvConfig.JumpToKey("Groups");
            g_kvConfig.JumpToKey(groupName);
        }
    }
    while(g_kvConfig.GotoNextKey());
}

/**
 * Sets all maps in a given group on cooldown
 * 
 * @param map           Map to ignore
 * @param groupName     Group to set
 * @param cooldown      Cooldown value to set
 */
public void SetGroupCooldown(const char[] map, const char[] groupName, int cooldown)
{
    if(!g_bConfig) return;
    g_kvConfig.Rewind();
    if(!g_kvConfig.JumpToKey("Groups")) return;
    if(!g_kvConfig.JumpToKey(groupName)) return;

    if(!g_kvConfig.GotoFirstSubKey()) return;
    char buf[PLATFORM_MAX_PATH];

    do
    {
        KvGetSectionName(g_kvConfig, buf, sizeof(buf));
        if(StrEqual(buf, map)) continue;

        InternalSetMapCooldown(buf, Cooldown_ValueGreater, cooldown);
    }
    while(g_kvConfig.GotoNextKey());
}

/**
 * Checks if a given map will violate group max if added to a given list
 * 
 * @param map     Map to check
 * @param list    List of maps to check in
 * @return        0 if it can be added, Value of Max if it can't
 */
int CheckGroupMax(const char[] map, ArrayList list, bool checkRandomMap = true)
{
    if(!g_bConfig) return 0;
    g_kvConfig.Rewind();
    
    //Enter groups
    if(!g_kvConfig.JumpToKey("Groups")) return 0;
    //Enter first group
    if(!g_kvConfig.GotoFirstSubKey()) return 0;

    char buf[PLATFORM_MAX_PATH];
    int max;

    for(int i = 0; i < g_iGroups; i++)
    {
        //If map-to-find isnt in this group go to next one
        if(!g_kvConfig.JumpToKey(map)) continue;
        g_kvConfig.GoBack();

        //If this group doesnt have a max, go to next group
        max = g_kvConfig.GetNum("Max", -1);
        if(max == -1) continue;

        int count = 0; //Number of maps in group and list

        //Check if the Random Map option is in this group
        if(checkRandomMap && (g_cv_RandomMap.BoolValue && g_kvConfig.JumpToKey(g_sRandomMap)))
        {
            count++;
            g_kvConfig.GoBack();
        }

        //Check all maps in list, if a map is in the group and list increase count
        for(int j = 0; j < list.Length; j++)
        {
            list.GetString(j, buf, sizeof(buf));

            if(StrEqual(map, buf)) continue;            //Don't count map we are checking
            if(!g_kvConfig.JumpToKey(buf)) continue;    //Check if this list-map is in the group

            count++;
            if(count >= max) return max;

            g_kvConfig.GoBack();
        }

        if(count >= max) 
        {
            return max;
        }

        if(!g_kvConfig.GotoNextKey()) break;
    }

    return 0;
}

/**
 * Prints info about a given maps groups to a client's console
 * 
 * @param client     Client to print to
 * @param map        Name of map
 */
public void ShowMapGroups(int client, const char[] map)
{
    if(!g_bConfig) 
    {
        PrintToConsole(client, "Config is not loaded, no group information.");
        return;
    }
    g_kvConfig.Rewind();
    PrintToConsole(client, "-----------------------------------------");
    PrintToConsole(client, "Group information");
    PrintToConsole(client, "-----------------------------------------");
    if(!g_kvConfig.JumpToKey("Groups"))
    {
        PrintToConsole(client, "No groups in the config.");
        return;
    }

    if(!g_kvConfig.GotoFirstSubKey())
    {
        PrintToConsole(client, "No groups in the config.");
        return;
    }

    char groupName[PLATFORM_MAX_PATH];
    int count = 0;
    
    do
    {
        if(!g_kvConfig.JumpToKey(map)) continue;
        g_kvConfig.GoBack();
        
        count++;
        g_kvConfig.GetSectionName(groupName, sizeof(groupName));
        PrintToConsole(client, "[%03d] Group Name: \"%s\"", count, groupName);

        int max = g_kvConfig.GetNum("Max", -1);
        int cd = g_kvConfig.GetNum("Cooldown", -1);

        if(max > 0)
        {
            PrintToConsole(client, "[%03d] Group Max: %d", count, max);
        }
        if(cd > 0)
        {
            PrintToConsole(client, "[%03d] Group Cooldown: %d", count, cd);
        }
        PrintToConsole(client, "-----------------------------------");
    }
    while(g_kvConfig.GotoNextKey());

    PrintToConsole(client, "%s is in %d groups", map, count);
    PrintToConsole(client, "-----------------------------------------");
}