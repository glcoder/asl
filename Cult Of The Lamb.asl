state("Cult Of The Lamb", "Steam")
{
}

startup
{
    var bytes = File.ReadAllBytes(@"Components\LiveSplit.ASLHelper.bin");
    var type = Assembly.Load(bytes).GetType("ASLHelper.Unity");

    vars.Helper = Activator.CreateInstance(type, timer, this);
    vars.Helper.GameName = "Cult Of The Lamb";
    vars.Helper.LoadSceneManager = true;

    vars.OldScene = "";
    vars.CurrentScene = "";

    settings.Add("Intro", true, "Intro Splits");
    settings.Add("TitleVideo", true, "Title video ends", "Intro");
    settings.Add("Base", false, "First time on base", "Intro");
    settings.Add("Difficulty", false, "Difficulty chosen", "Intro");

    settings.Add("Darkwood", true, "Darkwood");
    settings.Add("UnlockedDungeon1", false, "Darkwood unlocked", "Darkwood");
    settings.Add("CompletedDungeon1", false, "Darkwood completed", "Darkwood");
    settings.Add("BossEncounteredDungeon1", false, "Leshy encountered", "Darkwood");
    settings.Add("BossDefeatedDungeon1", true, "Leshy defeated", "Darkwood");
    settings.Add("EnterDungeon1", false, "Enter Darkwood", "Darkwood");
    settings.Add("ExitDungeon1", false, "Exit Darkwood", "Darkwood");

    settings.Add("Anura", true, "Anura");
    settings.Add("UnlockedDungeon2", false, "Anura unlocked", "Anura");
    settings.Add("CompletedDungeon2", false, "Anura completed", "Anura");
    settings.Add("BossEncounteredDungeon2", false, "Heket encountered", "Anura");
    settings.Add("BossDefeatedDungeon2", true, "Heket defeated", "Anura");
    settings.Add("EnterDungeon2", false, "Enter Anura", "Anura");
    settings.Add("ExitDungeon2", false, "Exit Anura", "Anura");

    settings.Add("Anchordeep", true, "Anchordeep");
    settings.Add("UnlockedDungeon3", false, "Anchordeep unlocked", "Anchordeep");
    settings.Add("CompletedDungeon3", false, "Anchordeep completed", "Anchordeep");
    settings.Add("BossEncounteredDungeon3", false, "Kallamar encountered", "Anchordeep");
    settings.Add("BossDefeatedDungeon3", true, "Kallamar defeated", "Anchordeep");
    settings.Add("EnterDungeon3", false, "Enter Anchordeep", "Anchordeep");
    settings.Add("ExitDungeon3", false, "Exit Anchordeep", "Anchordeep");

    settings.Add("SilkCradle", true, "Silk Cradle");
    settings.Add("UnlockedDungeon4", false, "Silk Cradle unlocked", "SilkCradle");
    settings.Add("CompletedDungeon4", false, "Silk Cradle completed", "SilkCradle");
    settings.Add("BossEncounteredDungeon4", false, "Shamura encountered", "SilkCradle");
    settings.Add("BossDefeatedDungeon4", true, "Shamura defeated", "SilkCradle");
    settings.Add("EnterDungeon4", false, "Enter Silk Cradle", "SilkCradle");
    settings.Add("ExitDungeon4", false, "Exit Silk Cradle", "SilkCradle");

    settings.Add("TheGateway", true, "The Gateway");
    settings.Add("CrownReturned", true, "Crown returned", "TheGateway");
    settings.Add("TheOneWhoWaitsDefeated", false, "The One Who Waits defeated", "TheGateway");
    settings.Add("EnterDungeonFinal", false, "Enter The Gateway", "TheGateway");
    settings.Add("ExitDungeonFinal", false, "Exit The Gateway", "TheGateway");

    settings.Add("Fleeces", true, "Unlocked Fleeces Splits");

    settings.Add("Fleece1", true, "Golden Fleece", "Fleeces");
    settings.Add("Fleece2", false, "Fleece of the Glass Cannon", "Fleeces");
    settings.Add("Fleece3", false, "Fleece of the Diseased Heart", "Fleeces");
    settings.Add("Fleece4", false, "Fleece of the Fates", "Fleeces");
    settings.Add("Fleece5", false, "Fleece of the Fragile Fortitude", "Fleeces");

    vars.Helper.AlertGameTime("Cult Of The Lamb");
}

init
{
    vars.Helper.TryOnLoad = (Func<dynamic, bool>)(mono =>
    {
        var MMTransition = mono.GetClass("MMTools.MMTransition");
        vars.Helper["IsLoading"] = MMTransition.Make<bool>("IsPlaying");

        var MMVideoPlayer = mono.GetClass("MMTools.MMVideoPlayer");
        vars.Helper["IsVideoCompleted"] = MMVideoPlayer.Make<bool>("mmVideoPlayer", "completed");

        var DataManager = mono.GetClass("DataManager");
        vars.Helper["DifficultyChosen"] = DataManager.Make<bool>("instance", "DifficultyChosen");
        vars.Helper["UnlockedBossTempleDoor"] = DataManager.MakeList<int>("instance", "UnlockedBossTempleDoor");
        vars.Helper["UnlockedDungeonDoor"] = DataManager.MakeList<int>("instance", "UnlockedDungeonDoor");
        vars.Helper["BossesCompleted"] = DataManager.MakeList<int>("instance", "BossesCompleted");
        vars.Helper["BossesEncountered"] = DataManager.MakeList<int>("instance", "BossesEncountered");
        vars.Helper["DeathCatBeaten"] = DataManager.Make<bool>("instance", "DeathCatBeaten");
        vars.Helper["PlayerFleece"] = DataManager.Make<int>("instance", "PlayerFleece");
        vars.Helper["UnlockedFleeces"] = DataManager.MakeList<int>("instance", "UnlockedFleeces");

        return true;
    });

    vars.Helper.Load();

    vars.CurrentScene = vars.Helper.Scenes.Active.Name;
    vars.Locations = new Dictionary<int, int>{ { 1, 7 }, { 2, 8 }, { 3, 9 }, { 4, 10 } };
}

update
{
    if (!vars.Helper.Update())
		return false;

    // Prevents scene splits while loading
    if (!vars.Helper["IsLoading"].Current)
    {
        vars.OldScene = vars.CurrentScene;
        vars.CurrentScene = vars.Helper.Scenes.Active.Name;
    }
}

isLoading
{
    return !vars.Helper["IsVideoCompleted"].Current || (vars.Helper["IsLoading"].Current && vars.CurrentScene != "QuoteScreen");
}

start
{
    return !vars.Helper["IsLoading"].Current && vars.CurrentScene == "Game Biome Intro";
}

split
{
    if (vars.CurrentScene == "Main Menu")
        return false;

    // Title video ends
    if (settings["TitleVideo"] && !vars.Helper["IsVideoCompleted"].Old && vars.Helper["IsVideoCompleted"].Current)
        return true;

    // First time base visited
    if (settings["Base"] && vars.CurrentScene == "Base Biome 1" && vars.OldScene != vars.CurrentScene && !vars.Helper["DifficultyChosen"].Current)
        return true;

    // Difficulty chosen
    if (settings["Difficulty"] && !vars.Helper["DifficultyChosen"].Old && vars.Helper["DifficultyChosen"].Current)
        return true;

    // Dungeons splits
    for (var DungeonIndex = 1; DungeonIndex <= 4; ++DungeonIndex)
    {
        var DungeonName = "Dungeon" + DungeonIndex;
        var Location = vars.Locations[DungeonIndex];

        // Dungeon unlocked
        if (settings["Unlocked" + DungeonName] && !vars.Helper["UnlockedDungeonDoor"].Old.Contains(Location) && vars.Helper["UnlockedDungeonDoor"].Current.Contains(Location))
            return true;

        // Dungeon completed
        if (settings["Completed" + DungeonName] && !vars.Helper["UnlockedBossTempleDoor"].Old.Contains(Location) && vars.Helper["UnlockedBossTempleDoor"].Current.Contains(Location))
            return true;

        // Dungeon boss encountered
        if (settings["BossEncountered" + DungeonName] && !vars.Helper["BossesEncountered"].Old.Contains(Location) && vars.Helper["BossesEncountered"].Current.Contains(Location))
            return true;

        // Dungeon boss defeated
        if (settings["BossDefeated" + DungeonName] && !vars.Helper["BossesCompleted"].Old.Contains(Location) && vars.Helper["BossesCompleted"].Current.Contains(Location))
            return true;

        // Dungeon enter
        if (settings["Enter" + DungeonName] && vars.CurrentScene == DungeonName && vars.OldScene != vars.CurrentScene)
            return true;

        // Dungeon exit
        if (settings["Exit" + DungeonName] && vars.OldScene == DungeonName && vars.OldScene != vars.CurrentScene)
            return true;
    }

    // Kneeled before fial boss
    if (settings["CrownReturned"] && vars.CurrentScene == "Credits" && vars.OldScene != vars.CurrentScene)
        return true;

    // Final boss defeated
    if (settings["TheOneWhoWaitsDefeated"] && !vars.Helper["DeathCatBeaten"].Old && vars.Helper["DeathCatBeaten"].Current)
        return true;

    // Final dungeon enter
    if (settings["EnterDungeonFinal"] && vars.CurrentScene == "Dungeon Final" && vars.OldScene != vars.CurrentScene)
        return true;

    // Final dungeon exit
    if (settings["ExitDungeonFinal"] && vars.OldScene == "Dungeon Final" && vars.OldScene != vars.CurrentScene)
        return true;

    // Fleeces
    for (var FleeceIndex = 1; FleeceIndex <= 5; ++FleeceIndex)
    {
        if (settings["Fleece" + FleeceIndex] && !vars.Helper["UnlockedFleeces"].Old.Contains(FleeceIndex) && vars.Helper["UnlockedFleeces"].Current.Contains(FleeceIndex))
            return true;
    }

    return false;
}

reset
{
    return vars.CurrentScene == "Main Menu";
}

exit
{
	vars.Helper.Dispose();
}

shutdown
{
	vars.Helper.Dispose();
}
