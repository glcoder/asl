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

    settings.Add("Bosses", true, "Bosses Splits");

    settings.Add("Leshy", true, "Leshy", "Bosses");
    settings.Add("Heket", true, "Heket", "Bosses");
    settings.Add("Kallamar", true, "Kallamar", "Bosses");
    settings.Add("Shamura", true, "Shamura", "Bosses");
    settings.Add("TheOneWhoWaits", true, "The One Who Waits", "Bosses");

    settings.Add("Dungeons", false, "Dungeons Splits");

    settings.Add("Darkwood", false, "Darkwood", "Dungeons");
    settings.Add("EnterDungeon1", false, "Enter", "Darkwood");
    settings.Add("ExitDungeon1", false, "Exit", "Darkwood");

    settings.Add("Anura", false, "Anura", "Dungeons");
    settings.Add("EnterDungeon2", false, "Enter", "Anura");
    settings.Add("ExitDungeon2", false, "Exit", "Anura");

    settings.Add("Anchordeep", false, "Anchordeep", "Dungeons");
    settings.Add("EnterDungeon3", false, "Enter", "Anchordeep");
    settings.Add("ExitDungeon3", false, "Exit", "Anchordeep");

    settings.Add("SilkCradle", false, "Silk Cradle", "Dungeons");
    settings.Add("EnterDungeon4", false, "Enter", "SilkCradle");
    settings.Add("ExitDungeon4", false, "Exit", "SilkCradle");

    settings.Add("TheGateway", false, "The Gateway", "Dungeons");
    settings.Add("EnterDungeonFinal", false, "Enter", "TheGateway");
    settings.Add("ExitDungeonFinal", false, "Exit", "TheGateway");

    settings.Add("Fleeces", false, "Unlocked Fleeces Splits");

    settings.Add("Fleece1", false, "Golden Fleece", "Fleeces");
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
        var DataManager = mono.GetClass("DataManager");
        vars.Helper["BossesCompleted"] = DataManager.MakeList<int>("instance", "BossesCompleted");
        vars.Helper["UnlockedFleeces"] = DataManager.MakeList<int>("instance", "UnlockedFleeces");
        vars.Helper["DeathCatBeaten"] = DataManager.Make<bool>("instance", "DeathCatBeaten");
        vars.Helper["PlayerFleece"] = DataManager.Make<int>("instance", "PlayerFleece");

        var MMTransition = mono.GetClass("MMTools.MMTransition");
        vars.Helper["IsPlaying"] = MMTransition.Make<bool>("IsPlaying");

        return true;
    });

    vars.Helper.Load();

    vars.CurrentScene = vars.Helper.Scenes.Active.Name;
}

update
{
    if (!vars.Helper.Update())
		return false;

    vars.OldScene = vars.CurrentScene;
    vars.CurrentScene = vars.Helper.Scenes.Active.Name;
}

isLoading
{
    return (vars.Helper["IsPlaying"].Current && vars.CurrentScene != "QuoteScreen")
        || string.IsNullOrEmpty(vars.CurrentScene)
        || vars.CurrentScene == "BufferScene";
}

start
{
    return vars.CurrentScene == "Game Biome Intro";
}

split
{
    if (vars.CurrentScene == "Main Menu")
        return false;

    if (vars.OldScene != vars.CurrentScene)
    {
        // The One Who Waits kneeled
        if (settings["TheOneWhoWaits"] && vars.CurrentScene == "Credits")
            return true;

        // Final dungeon
        if ((settings["EnterDungeonFinal"] && vars.CurrentScene == "Dungeon Final") || (settings["ExitDungeonFinal"] && vars.OldScene == "Dungeon Final"))
            return true;

        // Dungeons
        for (int DungeonIndex = 1; DungeonIndex <= 4; ++DungeonIndex)
        {
            var DungeonName = "Dungeon" + DungeonIndex;
            if ((settings["Enter" + DungeonName] && vars.CurrentScene == DungeonName) || (settings["Exit" + DungeonName] && vars.OldScene == DungeonName))
                return true;
        }
    }

    // Fleeces
    for (int FleeceIndex = 1; FleeceIndex <= 5; ++FleeceIndex)
    {
        if (settings["Fleece" + FleeceIndex] && !vars.Helper["UnlockedFleeces"].Old.Contains(FleeceIndex) && vars.Helper["UnlockedFleeces"].Current.Contains(FleeceIndex))
            return true;
    }

    // Bosses defeated
    return (settings["TheOneWhoWaits"] && !vars.Helper["DeathCatBeaten"].Old && vars.Helper["DeathCatBeaten"].Current)
        || (settings["Leshy"] && !vars.Helper["BossesCompleted"].Old.Contains(7) && vars.Helper["BossesCompleted"].Current.Contains(7))
        || (settings["Heket"] && !vars.Helper["BossesCompleted"].Old.Contains(8) && vars.Helper["BossesCompleted"].Current.Contains(8))
        || (settings["Kallamar"] && !vars.Helper["BossesCompleted"].Old.Contains(9) && vars.Helper["BossesCompleted"].Current.Contains(9))
        || (settings["Shamura"] && !vars.Helper["BossesCompleted"].Old.Contains(10) && vars.Helper["BossesCompleted"].Current.Contains(10));
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
