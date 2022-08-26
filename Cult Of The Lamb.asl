state("Cult Of The Lamb")
{
}

state("Cult Of The Lamb", "Demo")
{
}

startup
{
    var bytes = File.ReadAllBytes(@"Components\LiveSplit.ASLHelper.bin");
    var type = Assembly.Load(bytes).GetType("ASLHelper.Unity");

    vars.Helper = Activator.CreateInstance(type, timer, this);
    vars.Helper.GameName = "Cult Of The Lamb";
    vars.Helper.LoadSceneManager = true;

    settings.Add("General", true, "General game splits");
    settings.Add("TitleVideo", false, "Title video ends", "General");
    settings.Add("CultBase", true, "Entering Base for the first time", "General");
    settings.Add("Difficulty", false, "Game difficulty chosen", "General");
    settings.Add("EndCredits", true, "End credits begins", "General");

    settings.Add("Demo", false, "Demo version splits");
    settings.Add("BeatMiniBoss", false, "First Darkwood mini boss defeated", "Demo");
    settings.Add("DemoOver", false, "Demo complete screen shown up", "Demo");

    var DungeonNames = new string[] { "Darkwood", "Anura", "Anchordeep", "Silk Cradle" };
    var BossNames = new string[] { "Leshy", "Heket", "Kallamar", "Shamura" };

    for (int Index = 0; Index < 4; ++Index)
    {
        var Name = "Dungeon" + (Index + 1);
        settings.Add(Name, true, DungeonNames[Index] + " splits");
        settings.Add("Unlocked" + Name, false, DungeonNames[Index] + " entrance opened", Name);
        settings.Add("Completed" + Name, false, BossNames[Index] + "'s room entrance opened", Name);
        settings.Add("BossEncountered" + Name, false, "Begin " + BossNames[Index] + " battle for the first time", Name);
        settings.Add("BossDefeated" + Name, true, BossNames[Index] + " defeated for the first time", Name);
        settings.Add("FirstEnter" + Name, false, "First time entering " + DungeonNames[Index], Name);
        settings.Add("Enter" + Name, false, "Each time entering " + DungeonNames[Index], Name);
        settings.Add("Exit" + Name, false, "Each time leaving " + DungeonNames[Index], Name);
    }

    settings.Add("TheGateway", false, "The Gateway splits");
    settings.Add("TheOneWhoWaitsDefeated", false, "The One Who Waits defeated for the first time", "TheGateway");
    settings.Add("FirstEnterDungeonFinal", false, "First time entering The Gateway", "TheGateway");
    settings.Add("EnterDungeonFinal", false, "Each time entering The Gateway", "TheGateway");
    settings.Add("ExitDungeonFinal", false, "Each time leaving The Gateway", "TheGateway");

    settings.Add("Fleeces", false, "Fleece unlock splits");
    settings.Add("Fleece1", false, "Golden Fleece", "Fleeces");
    settings.Add("Fleece2", false, "Fleece of the Glass Cannon", "Fleeces");
    settings.Add("Fleece3", false, "Fleece of the Diseased Heart", "Fleeces");
    settings.Add("Fleece4", false, "Fleece of the Fates", "Fleeces");
    settings.Add("Fleece5", false, "Fleece of the Fragile Fortitude", "Fleeces");

    vars.Helper.AlertLoadless("Cult Of The Lamb");
}

init
{
    vars.Helper.TryOnLoad = (Func<dynamic, bool>)(mono =>
    {
        var CheatConsole = mono.GetClass("CheatConsole");
        vars.Helper["InDemo"] = CheatConsole.Make<bool>("_inDemo");

        // 0x10 - offset of m_CachedPtr field
        // 0x39 - offset of active flag in native object
        var MMTransition = mono.GetClass("MMTools.MMTransition");
        vars.Helper["IsInTransition"] = MMTransition.Make<bool>("IsPlaying");
        vars.Helper["IsLoadingIconActive"] = MMTransition.Make<byte>("mmTransition", "loadingIcon", 0x10, 0x39);

        var MMVideoPlayer = mono.GetClass("MMTools.MMVideoPlayer");
        vars.Helper["IsVideoCompleted"] = MMVideoPlayer.Make<bool>("mmVideoPlayer", "completed");

        var DataManager = mono.GetClass("DataManager");
        vars.Helper["IsDifficultyChosen"] = DataManager.Make<bool>("instance", "DifficultyChosen");
        vars.Helper["UnlockedBossTempleDoor"] = DataManager.MakeList<int>("instance", "UnlockedBossTempleDoor");
        vars.Helper["UnlockedDungeonDoor"] = DataManager.MakeList<int>("instance", "UnlockedDungeonDoor");
        vars.Helper["BossesCompleted"] = DataManager.MakeList<int>("instance", "BossesCompleted");
        vars.Helper["BossesEncountered"] = DataManager.MakeList<int>("instance", "BossesEncountered");
        vars.Helper["IsDeathCatBeaten"] = DataManager.Make<bool>("instance", "DeathCatBeaten");
        vars.Helper["PlayerFleece"] = DataManager.Make<int>("instance", "PlayerFleece");
        vars.Helper["UnlockedFleeces"] = DataManager.MakeList<int>("instance", "UnlockedFleeces");
        vars.Helper["OnboardingPhase"] = DataManager.Make<int>("instance", "CurrentOnboardingPhase");
        vars.Helper["IsFirstMiniBossBeaten"] = DataManager.Make<bool>("instance", "BeatenFirstMiniBoss");

        return true;
    });

    vars.Helper.Load();

    if (vars.Helper.Loaded && vars.Helper["InDemo"].Current)
        version = "Demo";

    vars.Locations = new int[] { 7, 8, 9, 10 };
    vars.CompletedSplits = new HashSet<string>();

    current.Scene = vars.Helper.Scenes.Active.Name;
    current.IsVideoPlaying = false;
    current.IsLoading = true;
}

update
{
    if (!vars.Helper.Loaded || !vars.Helper.Update())
        return false;

    current.Scene = vars.Helper.Scenes.Active.Name;
    current.IsVideoPlaying = !vars.Helper["IsVideoCompleted"].Current;
    current.IsLoading = current.IsVideoPlaying
        || vars.Helper["IsLoadingIconActive"].Current > 0
        || current.Scene == "BufferScene"
        || current.Scene == "QuoteScreen"
        || String.IsNullOrEmpty(current.Scene);
}

isLoading
{
    return current.IsLoading;
}

start
{
    return !current.IsLoading && current.Scene == "Game Biome Intro";
}

onStart
{
	timer.IsGameTimePaused = true;
	vars.CompletedSplits.Clear();
}

split
{
    // Title video ends
    if (settings["TitleVideo"] && old.IsVideoPlaying && !current.IsVideoPlaying)
        return true;

    // First time base visited
    if (settings["CultBase"] && vars.Helper["OnboardingPhase"].Current == 1 && vars.Helper["OnboardingPhase"].Old != 1)
        return true;

    // Difficulty chosen
    if (settings["Difficulty"] && vars.Helper["IsDifficultyChosen"].Changed)
        return true;

    // Helper method
    Func<bool, dynamic, int, bool> IsCollectionUnlocked = (value, collection, index) =>
    {
        return value && !collection.Old.Contains(index) && collection.Current.Contains(index);
    };

    // Dungeons splits
    for (var Index = 0; Index < 4; ++Index)
    {
        var Name = "Dungeon" + (Index + 1);
        var Location = vars.Locations[Index];

        // Dungeon entrance opened
        if (IsCollectionUnlocked(settings["Unlocked" + Name], vars.Helper["UnlockedDungeonDoor"], Location))
            return true;

        // Dungeon boss room entrance opened
        if (IsCollectionUnlocked(settings["Completed" + Name], vars.Helper["UnlockedBossTempleDoor"], Location))
            return true;

        // Begin dungeon boss battle for the first time
        if (IsCollectionUnlocked(settings["BossEncountered" + Name], vars.Helper["BossesEncountered"], Location))
            return true;

        // Dungeon boss defeated for the first time
        if (IsCollectionUnlocked(settings["BossDefeated" + Name], vars.Helper["BossesCompleted"], Location))
            return true;

        // Entering dungeon split
        if (current.Scene == Name && current.Scene != old.Scene)
        {
            if (settings["Enter" + Name] || (settings["FirstEnter" + Name] && !vars.CompletedSplits.Contains(Name)))
            {
                vars.CompletedSplits.Add(Name);
                return true;
            }
        }

        // Leaving dungeon split
        if (settings["Exit" + Name] && old.Scene == Name && current.Scene != old.Scene)
            return true;
    }

    // First mini boss defeated
    if (settings["BeatMiniBoss"] && vars.Helper["IsFirstMiniBossBeaten"].Changed)
        return true;

    // Final boss defeated
    if (settings["TheOneWhoWaitsDefeated"] && vars.Helper["IsDeathCatBeaten"].Changed)
        return true;

    if (current.Scene != old.Scene)
    {
        // Credits scene shown
        if (settings["EndCredits"] && current.Scene == "Credits")
            return true;

        if (settings["DemoOver"] && current.Scene == "DemoOver")
            return true;

        // Final dungeon enter
        if (settings["EnterDungeonFinal"] && current.Scene == "Dungeon Final")
            return true;

        // Final dungeon exit
        if (settings["ExitDungeonFinal"] && old.Scene == "Dungeon Final")
            return true;
    }

    // Fleeces
    for (var Index = 1; Index <= 5; ++Index)
    {
        if (IsCollectionUnlocked(settings["Fleece" + Index], vars.Helper["UnlockedFleeces"], Index))
            return true;
    }

    return false;
}

reset
{
    return current.Scene == "Main Menu";
}

exit
{
    vars.Helper.Dispose();
}

shutdown
{
    vars.Helper.Dispose();
}
