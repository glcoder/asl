state("Cult Of The Lamb")
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

        var LetterBox = mono.GetClass("LetterBox");
        vars.Helper["LetterBoxVisible"] = LetterBox.Make<bool>("IsPlaying");

        return true;
    });

    vars.Helper.Load();

    vars.Locations = new int[] { 7, 8, 9, 10 };
    vars.FirstEnterDungeons = new HashSet<string>();

    current.Scene = vars.Helper.Scenes.Active.Name;
}

update
{
    if (!vars.Helper.Update())
        return false;

    current.IsLoading = vars.Helper["IsLoading"].Current;
    current.IsVideoCompleted = vars.Helper["IsVideoCompleted"].Current;

    if (!current.IsLoading)
    {
        // Prevents scene splits while loading
        current.Scene = vars.Helper.Scenes.Active.Name;
    }
}

isLoading
{
    return !current.IsVideoCompleted || (current.IsLoading && current.Scene != "QuoteScreen");
}

start
{
    if (!current.IsLoading && current.Scene == "Game Biome Intro")
    {
        vars.FirstEnterDungeons.Clear();
        return true;
    }

    return false;
}

split
{
    // Title video ends
    if (settings["TitleVideo"] && !old.IsVideoCompleted && current.IsVideoCompleted)
        return true;

    // First time base visited
    if (settings["CultBase"] && current.Scene == "Base Biome 1" && old.Scene != current.Scene && !vars.Helper["DifficultyChosen"].Current)
        return true;

    // Difficulty chosen
    if (settings["Difficulty"] && vars.Helper["DifficultyChosen"].Changed)
        return true;

    // Helper method
    var IsCollectionUnlocked = (Func<bool, dynamic, int, bool>)((value, collection, index) =>
    {
        return value && !collection.Old.Contains(index) && collection.Current.Contains(index);
    });

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
            if (settings["Enter" + Name] || (settings["FirstEnter" + Name] && !vars.FirstEnterDungeons.Contains(Name)))
            {
                vars.FirstEnterDungeons.Add(Name);
                return true;
            }
        }

        // Leaving dungeon split
        if (settings["Exit" + Name] && old.Scene == Name && current.Scene != old.Scene)
            return true;
    }

    // Final boss defeated
    if (settings["TheOneWhoWaitsDefeated"] && !vars.Helper["DeathCatBeaten"].Old && vars.Helper["DeathCatBeaten"].Current)
        return true;

    if (current.Scene != old.Scene)
    {
        // Credits scene shown
        if (settings["EndCredits"] && current.Scene == "Credits")
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
    if (current.Scene == "Main Menu")
    {
        vars.FirstEnterDungeons.Clear();
        return true;
    }

    return false;
}

exit
{
    vars.Helper.Dispose();
}

shutdown
{
    vars.Helper.Dispose();
}
