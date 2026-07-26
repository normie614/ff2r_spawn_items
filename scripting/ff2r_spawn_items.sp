/*
	"special_spawn_items"
	{
		"item_respawn_period"			"20.0"	// Time between spawns.
		"item_on_kill_spawn_chance"		"30.0"	// % chance to drop an item at a victim's position on kill.
        "max_items"                     "2"     // Max items alive at once (ignored for on-kill drops).

		"item1" // This gets added to the ItemsToSpawn arraylist.
		{
			"vtm"					"freak_fortress_2/doom/item_berserk.vmt" // Sprite material (no "materials/" prefix). Leave empty if using model.
            "model"					""                                      // Leave empty if using "vtm". Set a .mdl path to spawn a 3D model instead.
			"pickup_sound"			"freak_fortress_2/doom/item_pickup.wav" // Self explanatory, required.
            "pickup_sound"			"freak_fortress_2/doom/item_pickup.wav" // No sound is played if not defined.
			"grab_flags"			""   // Missing or 1 = Boss | 2 = Minions | 4 = Enemy | add values together (3 = Boss + Minions).
			"do slot after low"		"5" // Example: Create a 'rage_new_weapon' somewhere with the slot "5", it will use it on touch.
			"do slot after high"	"" // Optional slot range end. Empty = same as low.
		}
		"item2"
		{
			"vtm"					"freak_fortress_2/doom/item_shotgun.vmt"
            "model"					"models/weapons/c_models/c_scattergun.mdl"
			"pickup_sound"			"freak_fortress_2/doom/item_weaponpickup.wav"
            "pickup_sound"			"freak_fortress_2/doom/item_pickup.wav"
			"grab_flags"            ""
			"do slot after low"		""
			"do slot after high"	""
		}
        "plugin_name" "ff2r_spawn_items"
	}

    "glow_items" // Makes the items glow (except the ones dropped by killing).
	{
		"slot" "0"

		"plugin_name"	"ff2r_spawn_items"
	}
*/

#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <tf2>
#include <tf2utils>
#include <cfgmap>
#include <ff2r>
#include <freak_fortress_2/formula_parser.sp>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name = "ff2r_spawn_items",
	author = "Latte",
	description = "Simple item spawn ability for FF2R",
	version = "1.0.0",
	url = "https://github.com/normie614/ff2r_spawn_items"
};

enum struct BossItem
{
    char vmt[PLATFORM_MAX_PATH];
    char model[PLATFORM_MAX_PATH];
    char spawnSound[PLATFORM_MAX_PATH];
    char pickupSound[PLATFORM_MAX_PATH];

    int slotLow;
    int slotHigh;

    int grabFlags;

    bool usesModel;
}

enum struct SpawnedItem
{
    int entityRef;
    int itemIndex;
}

enum
{
    Grab_Boss = (1 << 0),
    Grab_Minions = (1 << 1),
    Grab_Enemy = (1 << 2)
};

ArrayList g_BossItems[MAXPLAYERS + 1];
ArrayList g_BossEntities[MAXPLAYERS + 1];

ArrayList BossTimers[MAXPLAYERS + 1];

enum struct ItemSpawn
{
    float origin[3];
    float angles[3];

    int entityRef;
}
ItemSpawn g_ItemSpawns[128];

int g_ItemSpawnCount;
int g_MaxItems[MAXPLAYERS + 1];
int g_OnDeathItemProbability;
bool g_UsesItems;

public void OnPluginStart()
{
	HookEvent("teamplay_round_win", OnRoundEnd);
    HookEvent("player_death", OnPlayerDeath);
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			BossData cfg = FF2R_GetBossData(client);
			if (cfg)
			{
				FF2R_OnBossCreated(client, cfg, false);
			}
		}
	}
}

public void OnMapStart()
{
	ItemCacheSpawnLocations();
}

public void OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	// Otherwise, not enabled.
	if (FF2R_GetGamemodeType() != 2)
	{
		return;
	}
}

public void OnClientDisconnect(int client)
{
    if (BossTimers[client] != null)
    {
        delete BossTimers[client];
        BossTimers[client] = null;
    }
}

public void FF2R_OnBossCreated(int client, BossData cfg, bool setup)
{
	if (!setup || FF2R_GetGamemodeType() != 2)
	{
		AbilityData ability = cfg.GetAbility("special_spawn_items");
		if (!ability || !ability.IsMyPlugin())
			return;

        g_UsesItems = true;
		char section[16];

		g_BossItems[client] = new ArrayList(sizeof(BossItem));
		g_BossEntities[client] = new ArrayList(sizeof(SpawnedItem));

		for (int i = 1;; i++)
		{
			Format(section, sizeof(section), "item%d", i);

			ConfigData itemCfg = ability.GetSection(section);
			if (!itemCfg)
				break;

			BossItem item;

			itemCfg.GetString("vtm", item.vmt, sizeof(item.vmt));
            itemCfg.GetString("model", item.model, sizeof(item.model));

            item.usesModel = (item.vmt[0] == '\0' && item.model[0] != '\0');

            itemCfg.GetString("spawn_sound", item.spawnSound, sizeof(item.spawnSound));
			itemCfg.GetString("pickup_sound", item.pickupSound, sizeof(item.pickupSound));

            item.grabFlags = Grab_Boss;

            char buffer[16];

            itemCfg.GetString("grab_flags", buffer, sizeof(buffer), "");
            if (buffer[0] != '\0')
            {
                item.grabFlags = StringToInt(buffer);
            }

            itemCfg.GetString("do slot after low", buffer, sizeof(buffer), "");
            item.slotLow = (buffer[0] == '\0') ? -1 : StringToInt(buffer);

            itemCfg.GetString("do slot after high", buffer, sizeof(buffer), "");
            item.slotHigh = (buffer[0] == '\0') ? -1 : StringToInt(buffer);

			if (item.vmt[0] != '\0')
            {
                PrecacheModel(item.vmt, true);
            }

            if (item.model[0] != '\0')
            {
                PrecacheModel(item.model, true);
            }

            if (item.spawnSound[0] != '\0')
            {
                PrecacheSound(item.spawnSound, true);
            }

            if (item.pickupSound[0] != '\0')
            {
                PrecacheSound(item.pickupSound, true);
            }

			g_BossItems[client].PushArray(item);
		}
		float respawn = ability.GetFloat("item_respawn_period", 20.0);
        g_OnDeathItemProbability = ability.GetInt("item_on_kill_spawn_chance", 30);
        g_MaxItems[client] = ability.GetInt("max_items", 2);

		Handle timer = CreateTimer(respawn, Timer_SpawnItem, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

		if (BossTimers[client] == null)
		{
			BossTimers[client] = new ArrayList();
		}

		BossTimers[client].Push(timer);
	}
}

public void FF2R_OnAbility(int client, const char[] ability, AbilityData cfg)
{
    if(!StrContains(ability, "glow_items", false))
    {
        Boss_GlowAllSpawnedItems();
    }
}

public void FF2R_OnBossRemoved(int client)
{
    if (BossTimers[client] == null)
	{
        return;
    }
	int length = BossTimers[client].Length;
	for (int i; i < length; i++)
	{
		Handle timer = BossTimers[client].Get(i);
		delete timer;
	}
	delete BossTimers[client];

	if (g_BossEntities[client] != null)
	{
		int itemCount = g_BossEntities[client].Length;
		for (int i = 0; i < itemCount; i++)
		{
			SpawnedItem spawned;
			g_BossEntities[client].GetArray(i, spawned);

			int entity = EntRefToEntIndex(spawned.entityRef);
			if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
			{
				RemoveEntity(entity);
			}
		}
	}

	delete g_BossItems[client];
	delete g_BossEntities[client];
}

public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
    if (!g_UsesItems)
        return;
    
    int victim = GetClientOfUserId(GetEventInt(event, "userid"));
    int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

    if (!IsClientInGame(victim) || !IsClientInGame(attacker) || victim == attacker)
        return;

    if (GetRandomInt(1, 100) > g_OnDeathItemProbability)
        return;

    // if (g_BossEntities[attacker].Length >= g_MaxItems[attacker]) // Ignore max items and spawn anyways
    //     return;

    int itemIndex = GetRandomInt(0, g_BossItems[attacker].Length - 1);

    float origin[3];
    GetClientAbsOrigin(victim, origin);

    BossItem item;
    g_BossItems[attacker].GetArray(itemIndex, item);

    if (item.usesModel)
    {
        SpawnBossItem3DAtPosition(attacker, itemIndex, origin);
    }
    else
    {
        SpawnBossItemAtPosition(attacker, itemIndex, origin);
    }
}

void ItemCacheSpawnLocations()
{
    g_ItemSpawnCount = 0;

    static const char classNames[][] =
    {
        "item_ammopack_small",
        "item_ammopack_medium",
        "item_ammopack_full",
        "item_healthkit_small",
        "item_healthkit_medium",
        "item_healthkit_full"
    };

    for (int i = 0; i < sizeof(classNames); i++)
    {
        int ent = MaxClients + 1;

        while ((ent = FindEntityByClassname(ent, classNames[i])) != -1)
        {
            int id = g_ItemSpawnCount++;

            GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_ItemSpawns[id].origin);
            GetEntPropVector(ent, Prop_Data, "m_angRotation", g_ItemSpawns[id].angles);

            g_ItemSpawns[id].entityRef = INVALID_ENT_REFERENCE;

            RemoveEntity(ent);
        }
    }
}

stock void SpawnBossItem(int boss, int itemIndex)
{
    if (g_ItemSpawnCount <= 0)
        return;

    int spawn = -1;

    for (int attempts = 0; attempts < 20; attempts++)
    {
        int test = GetRandomInt(0, g_ItemSpawnCount - 1);

        if (EntRefToEntIndex(g_ItemSpawns[test].entityRef) == INVALID_ENT_REFERENCE)
        {
            spawn = test;
            break;
        }
    }

    if (spawn == -1)
        return;

    BossItem item;
    g_BossItems[boss].GetArray(itemIndex, item);

    float origin[3];
	float angles[3];

    origin = g_ItemSpawns[spawn].origin;
    angles = g_ItemSpawns[spawn].angles;

	angles[0] += 0.0;
    origin[2] += 30.0;

    int ent = CreateEntityByName("prop_physics_override");
    if (ent == -1)
        return;

    DispatchKeyValueVector(ent, "origin", origin);

    DispatchKeyValue(ent, "solid", "6");
    DispatchKeyValue(ent, "model", "models/props_gameplay/ball001.mdl");
    DispatchKeyValue(ent, "disableshadows", "1");
    DispatchKeyValue(ent, "spawnflags", "8192");

    DispatchSpawn(ent);
    ActivateEntity(ent);

    AcceptEntityInput(ent, "DisableMotion");

    SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);
    SetEntProp(ent, Prop_Send, "m_usSolidFlags", 8);
    SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
    SetEntityRenderColor(ent, 255, 255, 255, 1);
    //SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 0.001);

    SDKHook(ent, SDKHook_StartTouch, SpawnItem_OnStartTouch);

    int sprite = CreateEntityByName("env_sprite");
    if (sprite != -1)
    {
        DispatchKeyValueVector(sprite, "origin", origin);

        DispatchKeyValue(sprite, "model", item.vmt);

        DispatchKeyValue(sprite, "disablereceiveshadows", "1");
        DispatchKeyValue(sprite, "framerate", "3.0");
        DispatchKeyValueFloat(sprite, "GlowProxySize", 10.0);
        DispatchKeyValueFloat(sprite, "HDRColorScale", 1.0);

        DispatchKeyValue(sprite, "maxdxlevel", "0");
        DispatchKeyValue(sprite, "mindxlevel", "0");

        DispatchKeyValue(sprite, "renderamt", "255");
        DispatchKeyValue(sprite, "rendercolor", "255 255 255 255");
        DispatchKeyValue(sprite, "renderfx", "0");
        DispatchKeyValue(sprite, "rendermode", "4");
        DispatchKeyValue(sprite, "scale", "1.0");

        DispatchSpawn(sprite);
        ActivateEntity(sprite);

        SetVariantString("!activator");
        AcceptEntityInput(sprite, "SetParent", ent);
    }

    int ref = EntIndexToEntRef(ent);

    g_ItemSpawns[spawn].entityRef = ref;

    SpawnedItem spawned;
    spawned.entityRef = ref;
    spawned.itemIndex = itemIndex;

    g_BossEntities[boss].PushArray(spawned);
}

stock void SpawnBossItem3D(int boss, int itemIndex)
{
    if (g_ItemSpawnCount <= 0)
        return;

    int spawn = -1;

    for (int attempts = 0; attempts < 20; attempts++)
    {
        int test = GetRandomInt(0, g_ItemSpawnCount - 1);

        if (EntRefToEntIndex(g_ItemSpawns[test].entityRef) == INVALID_ENT_REFERENCE)
        {
            spawn = test;
            break;
        }
    }

    if (spawn == -1)
        return;

    BossItem item;
    g_BossItems[boss].GetArray(itemIndex, item);

    float origin[3];
    float angles[3];

    origin = g_ItemSpawns[spawn].origin;
    angles = g_ItemSpawns[spawn].angles;

    angles[0] += 0.0;
    origin[2] += 30.0;

    int ent = CreateEntityByName("prop_physics_override");
    if (ent == -1)
        return;

    DispatchKeyValueVector(ent, "origin", origin);

    DispatchKeyValue(ent, "solid", "6");
    DispatchKeyValue(ent, "model", item.model);
    DispatchKeyValue(ent, "disableshadows", "1");
    DispatchKeyValue(ent, "spawnflags", "8192");

    DispatchSpawn(ent);
    ActivateEntity(ent);

    AcceptEntityInput(ent, "DisableMotion");

    SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);
    SetEntProp(ent, Prop_Send, "m_usSolidFlags", 8);
    SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
    SetEntityRenderColor(ent, 255, 255, 255, 255);

    SDKHook(ent, SDKHook_StartTouch, SpawnItem_OnStartTouch);

    int ref = EntIndexToEntRef(ent);

    g_ItemSpawns[spawn].entityRef = ref;

    SpawnedItem spawned;
    spawned.entityRef = ref;
    spawned.itemIndex = itemIndex;

    g_BossEntities[boss].PushArray(spawned);
    CreateTimer(0.1, Timer_WeaponSpin, EntIndexToEntRef(ent), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

stock void SpawnBossItem3DAtPosition(int boss, int itemIndex, const float origin[3])
{
    BossItem item;
    g_BossItems[boss].GetArray(itemIndex, item);

    float pos[3];
    pos = origin;
    pos[2] += 30.0;

    int ent = CreateEntityByName("prop_physics_override");
    if (ent == -1)
        return;

    DispatchKeyValueVector(ent, "origin", pos);

    DispatchKeyValue(ent, "solid", "6");
    DispatchKeyValue(ent, "model", item.model);
    DispatchKeyValue(ent, "disableshadows", "1");
    DispatchKeyValue(ent, "spawnflags", "8192");

    DispatchSpawn(ent);
    ActivateEntity(ent);

    AcceptEntityInput(ent, "DisableMotion");

    SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);
    SetEntProp(ent, Prop_Send, "m_usSolidFlags", 8);
    SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
    SetEntityRenderColor(ent, 255, 255, 255, 255);

    SDKHook(ent, SDKHook_StartTouch, SpawnItem_OnStartTouch);

    int ref = EntIndexToEntRef(ent);

    SpawnedItem spawned;
    spawned.entityRef = ref;
    spawned.itemIndex = itemIndex;

    g_BossEntities[boss].PushArray(spawned);

    CreateTimer(0.1, Timer_WeaponSpin, ref, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

stock void SpawnBossItemAtPosition(int boss, int itemIndex, const float origin[3])
{
    BossItem item;
    g_BossItems[boss].GetArray(itemIndex, item);

    float pos[3];
    pos = origin;
    pos[2] += 30.0;

    int ent = CreateEntityByName("prop_physics_override");
    if (ent == -1)
        return;

    DispatchKeyValueVector(ent, "origin", pos);

    DispatchKeyValue(ent, "solid", "6");
    DispatchKeyValue(ent, "model", "models/items/medkit_large.mdl");
    DispatchKeyValue(ent, "disableshadows", "1");
    DispatchKeyValue(ent, "spawnflags", "8192");

    DispatchSpawn(ent);
    ActivateEntity(ent);

    AcceptEntityInput(ent, "DisableMotion");

    SetEntProp(ent, Prop_Send, "m_CollisionGroup", 1);
    SetEntProp(ent, Prop_Send, "m_usSolidFlags", 8);
    SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 0.001);

    SDKHook(ent, SDKHook_StartTouch, SpawnItem_OnStartTouch);

    int sprite = CreateEntityByName("env_sprite");
    if (sprite != -1)
    {
        DispatchKeyValueVector(sprite, "origin", pos);
        DispatchKeyValue(sprite, "model", item.vmt);
        DispatchKeyValue(sprite, "disablereceiveshadows", "1");
        DispatchKeyValue(sprite, "framerate", "3.0");
        DispatchKeyValueFloat(sprite, "GlowProxySize", 10.0);
        DispatchKeyValueFloat(sprite, "HDRColorScale", 1.0);
        DispatchKeyValue(sprite, "maxdxlevel", "0");
        DispatchKeyValue(sprite, "mindxlevel", "0");
        DispatchKeyValue(sprite, "renderamt", "255");
        DispatchKeyValue(sprite, "rendercolor", "255 255 255 255");
        DispatchKeyValue(sprite, "renderfx", "0");
        DispatchKeyValue(sprite, "rendermode", "4");
        DispatchKeyValue(sprite, "scale", "1.0");

        DispatchSpawn(sprite);
        ActivateEntity(sprite);

        SetVariantString("!activator");
        AcceptEntityInput(sprite, "SetParent", ent);
    }

    int ref = EntIndexToEntRef(ent);

    SpawnedItem spawned;
    spawned.entityRef = ref;
    spawned.itemIndex = itemIndex;

    g_BossEntities[boss].PushArray(spawned);
}

public Action Timer_SpawnItem(Handle timer, any userid)
{
	int boss = GetClientOfUserId(userid);

    if (!boss)
        return Plugin_Stop;
	
    if (!IsClientInGame(boss))
        return Plugin_Stop;

    // if (g_BossItems[boss] == null || !g_BossItems[boss].Length)
    //     return Plugin_Continue;
    if (g_BossEntities[boss].Length >= g_MaxItems[boss])
        return Plugin_Continue;

    int itemIndex = GetRandomInt(0, g_BossItems[boss].Length - 1);

    BossItem item;
    g_BossItems[boss].GetArray(itemIndex, item);

    if (item.usesModel)
    {
        SpawnBossItem3D(boss, itemIndex);
    }
    else
    {
        SpawnBossItem(boss, itemIndex);
    }
    
    if (item.spawnSound[0] != '\0')
    {
        EmitSoundToClient(boss, item.spawnSound);
    }

    return Plugin_Continue;
}

public Action Timer_WeaponSpin(Handle timer, int ref)
{
    int entity = EntRefToEntIndex(ref);
	if (IsValidEntity(entity))
	{
		float ang[3];
		GetEntPropVector(entity, Prop_Data, "m_angRotation", ang);
		ang[1] += 12.0;
		TeleportEntity(entity, NULL_VECTOR, ang, NULL_VECTOR);
		
		return Plugin_Continue;
	}
	return Plugin_Stop;
}

public Action SpawnItem_OnStartTouch(int entity, int client)
{
    if (!IsValidClient(client) || !IsClientInGame(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int boss;
    SpawnedItem spawned;

    if (!Boss_FindSpawnedItem(entity, boss, spawned))
        return Plugin_Continue;

    BossItem item;
    g_BossItems[boss].GetArray(spawned.itemIndex, item);

    bool isBoss = (client == boss);
    bool isMinion = (FF2R_GetClientMinion(client) != 0);
    bool isEnemy = !isBoss && !isMinion;

    bool allowed = (isBoss && (item.grabFlags & Grab_Boss))
                || (isMinion && (item.grabFlags & Grab_Minions))
                || (isEnemy && (item.grabFlags & Grab_Enemy));

    if (!allowed)
        return Plugin_Continue;

    EmitSoundToClient(client, item.pickupSound);

    if (item.slotLow != -1)
    {
        int high = (item.slotHigh == -1) ? item.slotLow : item.slotHigh;
        FF2R_DoBossSlot(boss, item.slotLow, high);
    }

    RemoveEntity(entity);

    // Remove from active list
    for (int i = 0; i < g_BossEntities[boss].Length; i++)
    {
        SpawnedItem temp;
        g_BossEntities[boss].GetArray(i, temp);

        if (temp.entityRef == spawned.entityRef)
        {
            g_BossEntities[boss].Erase(i);
            break;
        }
    }

    return Plugin_Handled;
}

stock void Boss_GlowAllSpawnedItems(TFTeam team = TFTeam_Unassigned, int rgba[4] = {255, 255, 255, 255})
{
    for (int boss = 1; boss <= MaxClients; boss++)
    {
        if (g_BossEntities[boss] == null)
            continue;

        int length = g_BossEntities[boss].Length;

        for (int i = 0; i < length; i++)
        {
            SpawnedItem temp;
            g_BossEntities[boss].GetArray(i, temp);

            int entity = EntRefToEntIndex(temp.entityRef);

            if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
                continue;

            TF2_AttachColoredGlow(entity, team, rgba);
        }
    }
}

bool Boss_FindSpawnedItem(int entity, int &boss, SpawnedItem spawned)
{
    int ref = EntIndexToEntRef(entity);

    for (boss = 1; boss <= MaxClients; boss++)
    {
        if (g_BossEntities[boss] == null)
            continue;

        SpawnedItem temp;

        int length = g_BossEntities[boss].Length;
        for (int i = 0; i < length; i++)
        {
            g_BossEntities[boss].GetArray(i, temp);

            if (temp.entityRef == ref)
            {
                spawned = temp;
                return true;
            }
        }
    }

    return false;
}

stock int TF2_AttachColoredGlow(int entity, TFTeam team = TFTeam_Unassigned, int rgba[4] = {255,255,255,255})
{
    int glow = CreateEntityByName("tf_glow");
    
    if (IsValidEntity(glow))
    {
        char glowTarget[PLATFORM_MAX_PATH]; // Stores the original name.
        GetEntPropString(entity, Prop_Data, "m_iName", glowTarget, sizeof(glowTarget));
        char tempName[32];
        Format(tempName, sizeof(tempName), "glow_%d", EntIndexToEntRef(entity));

        SetEntPropString(entity, Prop_Data, "m_iName", tempName); // Applies temp name
        DispatchKeyValue(glow, "target", tempName);
        
        DispatchSpawn(glow);

        switch(team)
        {
            case TFTeam_Red:
            {
                rgba = {184, 56, 59, 255};
            }
            case TFTeam_Blue:
            {
                rgba = {88, 133, 162, 255};
            }
        }
        
        SetVariantColor(rgba);
        AcceptEntityInput(glow, "SetGlowColor");

        SetEntPropString(entity, Prop_Data, "m_iName", glowTarget); // Restores the original name.
    }
    return glow;
}

stock bool IsValidClient(int client, bool replaycheck = true)
{
	if (client < 1 || client > MaxClients)
		return false;
	
	if (!IsClientInGame(client))
		return false;
	
	if (GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;
	
	if (replaycheck)
	{
		if (IsClientSourceTV(client) || IsClientReplay(client))
			return false;
	}
	return true;
}