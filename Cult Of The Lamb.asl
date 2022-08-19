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

    settings.Add("Any%", true);
    settings.Add("Leshy", true, "Leshy", "Any%");
    settings.Add("Heket", true, "Heket", "Any%");
    settings.Add("Kallamar", true, "Kallamar", "Any%");
    settings.Add("Shamura", true, "Shamura", "Any%");
    settings.Add("TheOne", true, "The One Who Waits", "Any%");
}

init
{
    vars.Helper.TryOnLoad = (Func<dynamic, bool>)(mono =>
    {
        var DataManager = mono.GetClass("DataManager");
        vars.Helper["BossesCompleted"] = DataManager.MakeList<int>("instance", "BossesCompleted");
        vars.Helper["DeathCatBeaten"] = DataManager.Make<bool>("instance", "DeathCatBeaten");
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
    return string.IsNullOrEmpty(vars.CurrentScene) || vars.CurrentScene == "BufferScene";
}

start
{
    return vars.CurrentScene == "QuoteScreen";
}

split
{
    if (vars.CurrentScene == "Main Menu")
        return false;

    return (settings["TheOne"] && vars.OldScene != "Credits" && vars.CurrentScene == "Credits")
        || (settings["TheOne"] && !vars.Helper["DeathCatBeaten"].Old && vars.Helper["DeathCatBeaten"].Current)
        || (settings["Leshy"] && !vars.Helper["BossesCompleted"].Old.Contains(7)  && vars.Helper["BossesCompleted"].Current.Contains(7))
        || (settings["Heket"] && !vars.Helper["BossesCompleted"].Old.Contains(8)  && vars.Helper["BossesCompleted"].Current.Contains(8))
        || (settings["Kallamar"] && !vars.Helper["BossesCompleted"].Old.Contains(9)  && vars.Helper["BossesCompleted"].Current.Contains(9))
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
