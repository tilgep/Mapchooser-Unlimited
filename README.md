# Mapchooser Unlimited
Another Mapchooser alternative with changes to nominating and other QoL features  
  
- Changes based on a private version for GFL:ZE ([Vauff](https://github.com/Vauff/) and/or [Snowy](https://github.com/SnowyGFL))
- Based on [mapchooser_extended](https://forums.alliedmods.net/showthread.php?t=156974) by Powerlord and Alliedmodders
  
 **Thanks to [Detroid](https://github.com/DetroidZE) and [Koen](https://github.com/notkoen) for testing**

## Important
- This has only been tested for CSGO Zombie Escape and there are no plans to support anything else  
Feature requests are welcome though  
- **Please translate if you can and make a pull request or send to `tilgep#6294`**
- For RTV to work, you must change RTV to use the `mapchooser_unlimited` include file (Any natives used *should* work)

## Features
### Mapchooser
- Allows multiple nominations for every map  
Change to traditional nominating with the cvar (`mcu_nominate_mode`)
- Chooses the most voted nominations to be in the vote  
Change how the maps are picked with the cvar (`mcu_vote_mode`)  
- Per-client vote menu randomization
- Configure restrictions for each map `(see example config below)`
- Create groups of maps to have a shared cooldown or maximum in the vote  
- Easily see config information about a map `!showmapconfig <map>`
- Reload the config file with a command `!reloadmapconfig`  
- Reload the maplist with a command `!reloadmaplist`  
- Admins can insert maps so they will be in the vote with `!adminnom`  
- AdminOnly maps with 1 vote or more can be nominated by any players  
Only an admin can make the first vote though  
- Set a random next map with `!setnextmap _random`  
- See who nominated the map which won the vote  

### Nominations
- See the list of players who have voted for a map with `!nomlist`  
- Admins can enable or disable nominating
- Admins can ban players from nominating with `!nomban`  
- Configure how often nominating messages are shown
- Command groups for easy permission overrides

### Other
- Easily configure any message using translation files with documentation of format parameters  
- Extensive documentation of all natives and forwards  
- Singular include and translation files for easy navigation  
- Logging of all actions for easy administration    

### Sounds
- Simplified/updated version of [this plugin](https://github.com/powerlord/sourcemod-mapchooser-extended/blob/master/addons/sourcemod/scripting/mapchooser_extended_sounds.sp)
- Plays sounds when vote events happen (see example config)
- Automatically adds sounds to downloads table

## Example Config
Here is an example config with all the options you can use  
`configs/mapchooser_unlimited.cfg`  
**Note:** Replacing `_unlimited` with `_extended` is supported  

- Some options have default values found in the cvars  
- Not all of the options need to be filled for every map, only the ones you need


```
"mapchooser_unlimited"
{
    "Groups" // Start of groups - Don't change this
    {
        "Group name" // Can be changed (visible in !showmapconfig)
        {
            "Cooldown"    "10"  // All maps in the group will be put on 10 cooldown when any of them is played
            "Max"         "2"   // Only 2 of these maps will appear in the map vote
            "de_dust2"  {}      // Note the {} on the end, these are necessary
            "de_mirage" {}
            "de_cache"  {}
        }
    }
    
    // Individual map configs
    
    "de_dust2"  // Name of map
    {
        "Extends"       "3"             // Maximum number of times this map can be extended from the map vote
        "Cooldown"      "20"            // When this map is played it will be put on a 20 map cooldown
        "MinPlayers"    "9"             // This map needs more than 9 players to appear in the map vote or be nominated
        "MaxPlayers"    "12"            // This map needs less than 12 players to appear in the map vote or be nominated
        "MinTime"       "0900"          // Can only appear in the vote or be nominated after 09:00 server time (0000 - 2359)
        "MaxTime"       "1530"          // Can only appear in the vote or be nominated before 15:30 server time (0000 - 2359)
        "AdminOnly"     "1"             // Can only be nominated by admins (0/1) (Default: ADMFLAG_BAN, override nom_admin to change)
        "NominateOnly"  "0"             // Can appear randomly in the vote (0/1)
        "Description"   "Classic map"   // This description will appear on the nominating menu and vote menu
    }
}
```
