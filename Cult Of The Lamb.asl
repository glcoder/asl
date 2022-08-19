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

    return (!vars.Helper["DeathCatBeaten"].Old && vars.Helper["DeathCatBeaten"].Current)
        || (vars.OldScene != "Credits" && vars.CurrentScene == "Credits")
        || (!vars.Helper["BossesCompleted"].Old.Contains(7)  && vars.Helper["BossesCompleted"].Current.Contains(7))
        || (!vars.Helper["BossesCompleted"].Old.Contains(8)  && vars.Helper["BossesCompleted"].Current.Contains(8))
        || (!vars.Helper["BossesCompleted"].Old.Contains(9)  && vars.Helper["BossesCompleted"].Current.Contains(9))
        || (!vars.Helper["BossesCompleted"].Old.Contains(10) && vars.Helper["BossesCompleted"].Current.Contains(10));
}

exit
{
	vars.Helper.Dispose();
}

shutdown
{
	vars.Helper.Dispose();
}
