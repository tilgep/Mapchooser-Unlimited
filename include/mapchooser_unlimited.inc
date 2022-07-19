#if defined _mapchooser_included_
 #endinput
#endif
#define _mapchooser_included_

enum NominationMode
{
    NominationMode_Limited = 0,
    NominationMode_Infinite = 1,
};

enum NominateResult
{
    Nominate_Added,             /* A client successfully nominated a map */
    Nominate_Replaced,          /* A client successfully replaced their nomination */
    Nominate_Inserted,          /* An admin successfully inserted a map */
    Nominate_InvalidMap,        /* The nominated map was not valid */
    Nominate_AlreadyNominated,  /* The map is already nominated (Limited mode only) */
    Nominate_AlreadyAdded,      /* The nominated map was already inserted */
    Nominate_VoteFull,          /* Nomlist is full */
};

enum CanNominateResult
{
    CanNominate_VoteFull,
    CanNominate_VoteInProgress,
    CanNominate_VoteComplete,
    CanNominate_Yes,
};

enum MapChange
{
	MapChange_Instant,      /** Change map as soon as the voting results have come in */
	MapChange_RoundEnd,     /** Change map at the end of the round */
	MapChange_MapEnd,       /** Change the sm_nextmap cvar */
};

/**
 *  Reason for why a nomination is being removed
 */
enum NominateRemoved
{
    Removed_UnNominated,        /** The client chose to remove their nomination */
    Removed_VoteEnded,          /** The nextmap vote ended, unlock nominating again and wipe old noms */
    Removed_Replaced,           /** Nomination got removed when a client changed their nom */
    Removed_ClientDisconnect,   /** When a client with a nomination disconnects */
    Removed_AdminClear,         /** When an admin removes a nomination */
    Removed_Inserted,           /** Map got inserted so all noms were removed */
    Removed_Overwritten,        /** Map was removed because the nomlist was full and a map was inserted */
    Removed_NotEnoughPlayers,   /** Not enough players are on the server */
    Removed_TooManyPlayers,     /** Too many players are on the server */
    Removed_Time,               /** The current time is no longer valid */
    Removed_Ignore,             /** Ignore the reason */
};

enum CooldownMode
{
    Cooldown_Config,            /** Cooldown value in config */
    Cooldown_ConfigGreater,     /** Cooldown value in config if greater than current cooldown */
    Cooldown_Value,             /** Value given in cooldown arg */
    Cooldown_ValueGreater,      /** Value given in cooldown arg if greater than current cooldown */
};

/* CanClientNominate flags, used with CanMapBeNominated */
#define CanClientNom_Yes                (1<<0)  // Map can be nominated
#define CanClientNom_CurrentMap         (1<<1)  // Map is currently being played
#define CanClientNom_CurrentNom         (1<<2)  // The client has already nominated this map
#define CanClientNom_Cooldown           (1<<3)  // Map is currently on cooldown
#define CanClientNom_NotEnoughPlayers   (1<<4)  // Not enough players are on the server
#define CanClientNom_TooManyPlayers     (1<<5)  // Too many players are on the server
#define CanClientNom_Time               (1<<6)  // The current time is not within the bounds set
#define CanClientNom_AdminOnly          (1<<7)  // This map is an admin only nomination
#define CanClientNom_Inserted           (1<<8)  // An admin has already inserted this map so no need to nominate
#define CanClientNom_Nominated          (1<<9)  // Nomlist size is limited and someone has nominated this map already
#define CanClientNom_GroupMax           (1<<10) // Nomlist size is limited and nominating this map would violate a group max

/**
 * Does MapChooser perform an end of map vote
 * 
 * @return     True if vote happens, false otherwise
 */
native bool EndOfMapVoteEnabled();

/**
 * Gets the current method of nomination
 * 
 * @return     A NominationMode value
 */
native NominationMode GetNominationMode();

/**
 * Returns if a map vote can be started.
 * 
 * @return     Can a map vote be started
 */
native bool CanMapChooserStartVote();

/**
 * Returns if the map vote is currently in progress
 * 
 * @return     True if vote is in progress, false otherwise
 */
native bool IsMapVoteInProgress();

/**
 * Returns if the end of map vote has ended and set a next map
 * 
 * @return     True if vote has ended, false otherwise
 */
native bool HasEndOfMapVoteFinished();

/**
 * Returns the number of extends used on the current map
 * 
 * @return     Number of extends used
 */
native int GetExtendsUsed();

/**
 * Starts a mapchooser end of map vote.
 * @note If no input array is specified mapchooser will use its internal list. This includes
 * any nominations and excluded maps (as per mapchoosers convars).
 * 
 * @param when          MapChange consant of when the resulting mapchange should occur.
 * @param inputList     ADT array list of maps to add to the vote.
 */
native void InitiateMapChooserVote(MapChange when, ArrayList inputList = null);

/**
 * Attempt to add a map to the next mapchooser vote.
 *
 * @param client        Client nominating (0 for server, ignored if force==true)
 * @param map           Map being nominated
 * @param force         Is the map being inserted by an admin
 * @return              Nominate Result of the outcome
 */
native NominateResult NominateMap(int client, const char[] map, bool force);

/**
 * Is nominate allowed?
 * 
 * @return     A CanNominateResult corresponding to whether a client is allowed to nominate or not
 */
native CanNominateResult CanNominate(int client);

/**
 * Gets whether a given client can nominate a given map by checking restrictions
 * 
 * @param client     Client index
 * @param map        Name of map
 * @return           A bitstring of CanClientNominate flags
 */
native int CanMapBeNominated(int client, const char[] map);

/**
 * Gets the current list of nominated maps.
 *
 * @note Must check if this returns 0 before using the stringmap
 * @param maparray      An ADT Trie handle to add the map strings and number of votes to. Key:map Value:votes
 * @return              Number of unique maps nominated (-1 if error)
 */
native int GetNominatedMapList(StringMap maparray);

/**
 * Get the number of nominate votes for a specified map.
 * 
 * @param map     Name of map
 * @return        Number of votes (-1 if not nominated)
 */
native int GetMapVotes(const char[] map);

/**
 * Checks if a map has been inserted to the nomlist by an admin
 * 
 * @param map     Name of map
 * @return        True if inserted, false otherwise
 */
native bool IsMapInserted(const char[] map);

/**
 * Gets a list of maps that have been inserted by an admin
 * 
 * @note Must check if this returns 0 before using the array
 * @param maparray     An ADT Array handle to store the maps
 * @return             Number of unique maps inserted (-1 if error)
 */
native int GetInsertedMapList(ArrayList maparray);

/**
 * Checks if a map has been nominated
 * 
 * @param map     Name of map
 * @return        True if nominated, false otherwise
 */
native bool IsMapNominated(const char[] map);

/**
 * Removes a given client's nominations
 * 
 * @param client     Client to find (0 is ignored since it can have multiple noms)
 * @param reason     NominateRemoved reason to use
 * @return           True if nom was found and removed, false if not found/not removed
 */
native bool RemoveNominationByOwner(int client, NominateRemoved reason);

/**
 * Removes all votes for a given map
 * 
 * @param map        Name of map
 * @param reason     NominateRemoved reason to use
 * @return           Number of client votes removed (Not including admin forced votes)
 */
native int RemoveNominationsByMap(const char[] map, NominateRemoved reason);

/**
 * Removes a map which has been inserted by an admin
 * 
 * @param client     Client removing
 * @param map        Name of map
 * @return           True if map was removed, false if not found/not removed
 */
native bool RemoveInsertedMap(int client, const char[] map);

/**
 * Gets a given clients nomination
 * 
 * @param client     Client index
 * @param map        Buffer to store map name in
 * @param maxlen     Maximum length of buffer
 * @return           True on nomination found, false otherwise
 */
native bool GetClientNomination(int client, char[] map, int maxlen);

/**
 * Gets the client indexes who have nominated a given map
 * 
 * @param map         Name of map
 * @param clients     Array to store client indexes in
 * @param maxlen      Maximum size of the array
 * @return            Number of clients who have nominated the map
 */
native int GetMapNominators(const char[] map, int[] clients, int maxlen);

/**
 * Put a given map on cooldown.
 * 
 * @param map          Name of map
 * @param mode         0 = Use value from config/default
 *                     1 = Cooldown value in config if greater than current cooldown
 *                     2 = Value given in cooldown arg
 *                     3 = Value given in cooldown arg if greater than current cooldown
 * @param cooldown     Cooldown to set if mode > 1
 * @return             True if cooldown changed, false if not changed
 */
native bool ExcludeMap(const char[] map, int mode = 0, int cooldown = 0);

/**
 * Gets a given map's current cooldown
 * 
 * @param map     Name of map
 * @return        Cooldown value, 0 = not on cooldown
 */
native int GetMapCooldown(const char[] map);

/**
 * Gets a given map's current player restriction status
 * 
 * @param map     Name of map
 * @return        Restriction status
 *                <0 Less than MinPlayers (Number of players needed to join)
 *                =0 Okay
 *                >0 More than MaxPlayers (Number of players needed to leave)
 */
native int GetMapPlayerRestriction(const char[] map);

/**
 * Gets a given map's minimum necessary players
 * 
 * @param map     Name of map
 * @return        Value of MinPlayers (0 if not found)
 */
native int GetMapMinPlayers(const char[] map);

/**
 * Gets a given map's maximum players
 * 
 * @param map     Name of map
 * @return        Value of MaxPlayers (0 if not found)
 */
native int GetMapMaxPlayers(const char[] map);

/**
 * Gets how many minutes until a map's time restriction is lifted
 * 
 * @param map     Name of map
 * @return        0 = okay, >0 = Minutes until ok
 */
native int GetMapTimeRestriction(const char[] map);

/**
 * Gets a given map's earliest playable time
 * 
 * @param map     Name of map
 * @return        Value of MinTime (0 if not found)
 */
native int GetMapMinTime(const char[] map);

/**
 * Gets a given map's latest playable time
 * 
 * @param map     Name of map
 * @return        Value of MaxTime (0 if not found)
 */
native int GetMapMaxTime(const char[] map);

/**
 * Gets whether a given map can only be initally nominated by admins
 * 
 * @param map     Name of map
 * @return        True if admin only, false otherwise
 */
native bool IsMapAdminOnly(const char[] map);

/**
 * Gets whether a map can only appear in votes from nominations
 * 
 * @param map     Name of map
 * @return        True if nominate only, false otherwise
 */
native bool IsMapNominateOnly(const char[] map);

/**
 * Gets the description set for a map
 * 
 * @param map        Name of map
 * @param buffer     Buffer to store the description in
 * @param maxlen     Maximum length of the buffer
 * @return           Number of characters written (0 if no description)
 */
native int GetMapDescription(const char[] map, char[] buffer, int maxlen);

/**
 * Gets the group restriction for a map, use to check if a map can be nominated
 * @note If nomination mode is currently infinite, it will always return 0
 * 
 * @param map     Name of map
 * @return        >0 = Group max is reached, 0 if no restriction
 */
native int GetMapGroupRestriction(const char[] map);

/**
 * Gets the maximum number of extends for a given map
 * 
 * @param map     Name of map
 * @return        Maximum of number of extends (-1 if invalid map)
 */
native int GetMapMaxExtends(const char[] map);

/**
 * Called when a nomination is removed (MapStart won't trigger this)
 * 
 * @param reason     A NominateRemoved reason why it was removed
 * @param map        Name of map
 * @param client     Client index who nominated (0 if admin forced)
 */
forward void OnNominationRemoved(NominateRemoved reason, const char[] map, int client);

/**
 * Called when the map vote is starting.
 * 
 */
forward void OnMapVoteWarningStart();

/**
 * Called when the warning timer ticks
 * 
 * @param time     Number of seconds left
 */
forward void OnMapVoteWarningTick(int time);

/**
 * Called when a runoff vote is starting.
 * 
 */
forward void OnRunoffVoteWarningStart();

/**
 * Called when a mapvote has started
 * 
 * @param runoff     Is this vote a runoff vote
 *
 */
forward void OnMapVoteStarted(bool runoff);

/**
 * Called when the map vote has ended.
 * 
 * @param map       Name of the chosen next map
 *                  EXTEND if extended
 *                  DONTCHANGE if not changing
 *                  If random chosen, name of the randomly chosen map
 *
 */
forward void OnMapVoteEnd(const char[] map);

/**
 * Called when a map is added from the nominations list to the vote
 * 
 * @param map       Name of map
 * @param votes     Number of votes it had
 * @param inserted  Was the map inserted by an admin
 *
 */
forward void OnMapAddedToVote(const char[] map, int votes, bool inserted);

/**
 * Called when a map is nominated 
 * @note Not called by admin insertion. See: OnMapInserted
 * 
 * @param client     Index of client
 * @param map        Name of map
 * @param votes      Number of votes the map has now
 * @param replaced   Did the client replace their nom or was it new
 *
 */
forward void OnMapNominated(int client, const char[] map, int votes, bool replaced);

/**
 * Called when a map has been inserted by an admin to the nomlist
 * This map will appear in the next map vote
 * 
 * @param admin   Client index of admin who inserted
 * @param map     Name of map
 *
 */
forward void OnMapInserted(int admin, const char[] map);

/**
 * Called when the maplist was reloaded successfully by a command
 * @note Not called on map start, or if the maplist fails to reload
 */
forward void OnMapListReloaded();