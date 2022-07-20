#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <mapchooser_unlimited>

#define VERSION "1.2.0"

public Plugin myinfo = 
{
    name = "Mapchooser Unlimited Sounds",
    author = "tilgep (original by Powerlord)", //Simplified and updated for new-style syntax
    description = "Sound support for Mapchooser Unlimited",
    version = VERSION,
    url = "https://github.com/tilgep/Mapchooser-Unlimited"
    // https://forums.alliedmods.net/showthread.php?t=156974
};

#define CONFIG_DIRECTORY "configs/mapchooser_unlimited/sounds"

#define VOTE_START "vote start"
#define VOTE_END "vote end"
#define VOTE_WARNING "vote warning"
#define RUNOFF_WARNING "runoff warning"
#define COUNTER "counter"

#define COUNTER_MAX 60

bool g_bLate;

ConVar g_cv_Enabled;
ConVar g_cv_EnableCounterSounds;
ConVar g_cv_SoundFile;

StringMap g_Sounds;

public void OnPluginStart()
{
    g_cv_Enabled = CreateConVar("mcu_sounds_enablesounds", "1", "Enable this plugin.  Sounds will still be downloaded.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cv_EnableCounterSounds = CreateConVar("mcu_sounds_enablewarningcountersounds", "1", "Enable sounds to be played during warning counter.  If this is disabled, map vote warning, start, and stop sounds still play.", FCVAR_NONE, true, 0.0, true, 1.0);
    g_cv_SoundFile = CreateConVar("mcu_sounds_soundfile", "csgo", "Config file to load from sourcemod/configs/mapchooser_unlimited/sounds/ (file extension is not needed)", FCVAR_NONE);
    
    AutoExecConfig(true, "mapchooser_unlimited_sounds");

    g_Sounds = CreateTrie();

    if(g_bLate) 
    {
        LoadSounds();
    }
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] err, int max)
{
    g_bLate = late;
    return APLRes_Success;
}

public void OnConfigsExecuted()
{
    LoadSounds();
}

// Reads the config file
public void LoadSounds()
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "%s", CONFIG_DIRECTORY);

    if(g_cv_Enabled.BoolValue && !DirExists(path))
    {
        SetFailState("Sounds directory not found at '%s'", path);
    }

    char filename[64];
    g_cv_SoundFile.GetString(filename, sizeof(filename));
    Format(path, sizeof(path), "%s/%s.cfg", path, filename);

    if(g_cv_Enabled.BoolValue && !FileExists(path))
    {
        SetFailState("Sounds file not found at '%s'", path);
    }

    KeyValues kv = new KeyValues("MapchooserSoundsList");
    if(g_cv_Enabled.BoolValue && !kv.ImportFromFile(path))
    {
        delete kv;
        SetFailState("Failed to import KeyValues successfully. Check your file '%s'", path);
    }

    char buffer[PLATFORM_MAX_PATH];

    if(kv.JumpToKey(VOTE_START))
    {
        kv.GetString("sound", buffer, sizeof(buffer));
        if(!StrEqual(buffer, ""))
        {
            g_Sounds.SetString(VOTE_START, buffer);
        }
        kv.GoBack();
    }

    if(kv.JumpToKey(VOTE_END))
    {
        kv.GetString("sound", buffer, sizeof(buffer));
        if(!StrEqual(buffer, ""))
        {
            g_Sounds.SetString(VOTE_END, buffer);
        }
        kv.GoBack();
    }

    if(kv.JumpToKey(VOTE_WARNING))
    {
        kv.GetString("sound", buffer, sizeof(buffer));
        if(!StrEqual(buffer, ""))
        {
            g_Sounds.SetString(VOTE_WARNING, buffer);
        }
        kv.GoBack();
    }

    if(kv.JumpToKey(RUNOFF_WARNING))
    {
        kv.GetString("sound", buffer, sizeof(buffer));
        if(!StrEqual(buffer, ""))
        {
            g_Sounds.SetString(RUNOFF_WARNING, buffer);
        }
        kv.GoBack();
    }

    if(!kv.JumpToKey(COUNTER))
    {
        delete kv;
        return;
    }

    char sNum[4];
    for(int i = 1; i <= COUNTER_MAX; i++)
    {
        Format(sNum, sizeof(sNum), "%d", i);
        
        if(!kv.JumpToKey(sNum)) continue;

        kv.GetString("sound", buffer, sizeof(buffer));
        if(!StrEqual(buffer, ""))
        {
            g_Sounds.SetString(sNum, buffer);
        }
        kv.GoBack();
    }

    delete kv;

    InitSounds();
}

// Precaches and adds to download table
public void InitSounds()
{
    if(!g_cv_Enabled.BoolValue || g_Sounds.Size == 0) return;

    StringMapSnapshot snap = g_Sounds.Snapshot();
    char filename[PLATFORM_MAX_PATH];
    char buffer[32];

    for(int i = 0; i < g_Sounds.Size; i++)
    {
        snap.GetKey(i, buffer, sizeof(buffer));
        g_Sounds.GetString(buffer, filename, sizeof(filename));
        
        if(PrecacheSound(filename, true))
        {
            Format(filename, sizeof(filename), "sound/%s", filename);
            AddFileToDownloadsTable(filename);
        }
    }
    delete snap;
}

/* MCU Forwards */

public void OnMapVoteStarted()
{
    if(!g_cv_Enabled.BoolValue) return;

    char sound[PLATFORM_MAX_PATH];
    if(g_Sounds.GetString(VOTE_START, sound, sizeof(sound)))
    {
        EmitSoundToAll(sound);
    }
}

public void OnMapVoteEnd(const char[] map)
{
    if(!g_cv_Enabled.BoolValue) return;

    char sound[PLATFORM_MAX_PATH];
    if(g_Sounds.GetString(VOTE_END, sound, sizeof(sound)))
    {
        EmitSoundToAll(sound);
    }
}

public void OnMapVoteWarningStart()
{
    if(!g_cv_Enabled.BoolValue) return;

    char sound[PLATFORM_MAX_PATH];
    if(g_Sounds.GetString(VOTE_WARNING, sound, sizeof(sound)))
    {
        EmitSoundToAll(sound);
    }
}

public void OnRunoffVoteWarningStart()
{
    if(!g_cv_Enabled.BoolValue) return;

    char sound[PLATFORM_MAX_PATH];
    if(g_Sounds.GetString(RUNOFF_WARNING, sound, sizeof(sound)))
    {
        EmitSoundToAll(sound);
    }
}

public void OnMapVoteWarningTick(int time)
{
    if(!g_cv_Enabled.BoolValue) return;
    if(!g_cv_EnableCounterSounds.BoolValue) return;

    char sNum[4];
    Format(sNum, sizeof(sNum), "%d", time);

    char sound[PLATFORM_MAX_PATH];
    if(g_Sounds.GetString(sNum, sound, sizeof(sound)))
    {
        EmitSoundToAll(sound);
    }
}
