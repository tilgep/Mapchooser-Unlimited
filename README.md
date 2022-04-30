# Mapchooser Unlimited
Another Mapchooser alternative with changes to nominating and other QoL features

## Important
- This has only been tested on CSGO and there are no plans to support anything else  
- To allow per-client vote menu shuffling, you must compile with **Sourcemod 1.11 or later**  
And any servers you use this on must use **1.11 or later.**  

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
- Reload the maplist with a command `!reloadmaplist`
- Admins can insert maps so they will be in the vote with `!adminnom`
- AdminOnly maps with 1 vote or more can be nominated by any players  
Only an admin can make the first vote though
- Set a random next map with `!setnextmap _random`

### Nominations
- See the list of players who have voted for a map with `!nomlist`  
- Admins can enable or disable nominating
- Admins can ban players from nominating with `!nomban`  
- Configure how often nominating messages are shown

### Other
- Easily configure any message using translation files with documentation of format parameters  
- Extensive documentation of all natives and forwards  
- Singular include and translation files for easy navigation  
- Logging of all actions for easy administration  
- The included `rockthevote_unlimited.sp` supports `!unrtv`  

## Example Config
Here is an example config with all the options you can use  
`configs/mapchooser_unlimited.cfg`  
**Note:** Replacing `_unlimited` with `_extended` is supported


```
"mapchooser_unlimited"
{
    "Groups" // Start of groups
    {
        "Group name"
        {
            "Cooldown"    "10"  // All maps in the group will be put on 10 cooldown when any of them is played
            "Max"         "2"   // Only 2 of these maps will appear in the map vote
            "de_dust2"  {}      // Note the {} on the end, these are necessary
            "de_mirage" {}
            "de_cache"  {}
        }
    }
    
    "de_dust2"  // Name of map
    {
        "Extends"       "3"             // Maximum number of extends which will appear in the vote
        "Cooldown"      "20"            // When this map is played it will be put on a 20 map cooldown
        "MinPlayers"    "9"             // This map needs more than 9 players to appear in the map vote or be nominated
        "MaxPlayers"    "12"            // This map needs less than 12 players to appear in the map vote or be nominated
        "MinTime"       "0900"          // This map can only appear in the vote or be nominated after 09:00 server time
        "MaxTime"       "1530"          // This map can only appear in the vote or be nominated before 15:30 server time
        "AdminOnly"     "1"             // This map can only be nominated by admins
        "NominateOnly"  "0"             // This map can appear randomly in the vote
        "Description"   "Classic map"   // This description will appear on the nominating menu and vote menu
    }
}
```
