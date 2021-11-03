state("ZingangGame-Win64-Shipping", "Steam")
{
    // 0x7E69170 - GWorldProxy -> UWorld
    // 0x118 - AGameMode
    // 0x180 - UGameInstance

    //uint GameModeType: 0x7E69170, 0x118, 0x10, 0x18;
    ulong PawnAddress: 0x7E69170, 0x180, 0x38, 0x0, 0x30, 0x250;

    // InGameTime = LastSavedGameTime + RealTime - LastSavedRealTime
    float RealTime: 0x7E69170, 0x5A0;
    /*
    float LastSavedRealTime: 0x7E69170, 0x180, 0x4C4;
    float LastSavedGameTime: 0x7E69170, 0x180, 0x4C0;
    float LoadingDelta: 0x7E69170, 0x180, 0x448, 0x320;

    int SkillRecover: 0x7E69170, 0x180, 0x3A8, 0x2C8, 0x00;
    int SkillBlocking: 0x7E69170, 0x180, 0x3A8, 0x2C8, 0x08;
    int SkillMissile: 0x7E69170, 0x180, 0x3A8, 0x2C8, 0x10;
    int SkillPuppet: 0x7E69170, 0x180, 0x3A8, 0x2C8, 0x18;
    */
}

init
{
    vars.ProgressFlagManagerPtr = new DeepPointer(0x7E69170, 0x180, 0x358, 0x50);
    vars.ActiveAbilityNameSetPtr = new DeepPointer(0x7E69170, 0x180, 0x3A0, 0xC8);
    vars.ActiveComboDefinitionsPtr = new DeepPointer(0x7E69170, 0x180, 0x3A0, 0x118);

    Action<IntPtr, int, Action<IntPtr>> ReadArray = (IntPtr ArrayPtr, int ElementSize, Action<IntPtr> Callback) => {
        IntPtr ArrayData = memory.ReadPointer(IntPtr.Add(ArrayPtr, 0x0));
        int ArrayNum = memory.ReadValue<int>(IntPtr.Add(ArrayPtr, 0x8));
        for (int Index = 0; Index < ArrayNum; ++Index)
        {
            Callback(IntPtr.Add(ArrayData, Index * ElementSize));
        }
    };

    Action UpdateProgress = () => {
        vars.ProgressOld.Clear();
        foreach (var ProgressEntry in vars.ProgressCurrent)
        {
            vars.ProgressOld.Add(ProgressEntry.Key, ProgressEntry.Value);
        }
        vars.ProgressCurrent.Clear();

        // Game Progress Flags
        IntPtr ProgressFlagManagerPtr = IntPtr.Zero;
        if (vars.ProgressFlagManagerPtr.DerefOffsets(game, out ProgressFlagManagerPtr))
        {
            ReadArray(ProgressFlagManagerPtr, 0x14, (IntPtr ArrayElement) => {
                int TagName = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x0));
                int Progress = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x8));
                vars.ProgressCurrent.Add(TagName, Progress);
            });
        }
    };

    vars.UpdateProgress = UpdateProgress;

    Action UpdateUnlocks = () => {
        vars.UnlocksOld.Clear();
        foreach (var UnlockName in vars.UnlocksCurrent)
        {
            vars.UnlocksOld.Add(UnlockName);
        }
        vars.UnlocksCurrent.Clear();

        // Unlockable Abilities
        IntPtr ActiveAbilityNameSetPtr = IntPtr.Zero;
        if (vars.ActiveAbilityNameSetPtr.DerefOffsets(game, out ActiveAbilityNameSetPtr))
        {
            ReadArray(ActiveAbilityNameSetPtr, 0x18, (IntPtr ArrayElement) => {
                IntPtr AbilityNamePtr = memory.ReadPointer(IntPtr.Add(ArrayElement, 0x0));
                int AbilityNameLength = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x8));
                string AbilityName = memory.ReadString(AbilityNamePtr, ReadStringType.UTF16, AbilityNameLength * 2);
                vars.UnlocksCurrent.Add(AbilityName);
            });
        }

        /*
        // Weapons Combos
        IntPtr ActiveComboDefinitionsPtr = IntPtr.Zero;
        if (vars.ActiveComboDefinitionsPtr.DerefOffsets(game, out ActiveComboDefinitionsPtr))
        {
            ReadArray(ActiveComboDefinitionsPtr, 0x60, (IntPtr ArrayElement) => {
                string WeaponName = "Unknown";
                switch (memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x0))) {
                    case 1: WeaponName = "Fist";  break;
                    case 2: WeaponName = "Drill"; break;
                    case 3: WeaponName = "Chain"; break;
                };
                ReadArray(IntPtr.Add(ArrayElement, 0x8), 0x18, (IntPtr ComboArrayElement) => {
                    IntPtr ComboNamePtr = memory.ReadPointer(IntPtr.Add(ComboArrayElement, 0x0));
                    int ComboNameLength = memory.ReadValue<int>(IntPtr.Add(ComboArrayElement, 0x8));
                    string ComboName = memory.ReadString(ComboNamePtr, ReadStringType.UTF16, ComboNameLength * 2);
                    vars.UnlocksCurrent.Add(WeaponName + "_" + ComboName);
                });
            });
        }
        */
    };

    vars.UpdateUnlocks = UpdateUnlocks;
}

startup
{
    // Reduce CPU usage by reducing memory read operations
    refreshRate = 30;

    vars.GameTime = 0.0;

    vars.ProgressOld = new Dictionary<int, int>();
    vars.ProgressCurrent = new Dictionary<int, int>();

    vars.UnlocksOld = new HashSet<string>();
    vars.UnlocksCurrent = new HashSet<string>();

    settings.Add("Abilities", true, "Abilities");
    settings.Add("Progress", true, "Game Progress");

    settings.CurrentDefaultParent = "Abilities";
    settings.Add("EXECUTION", false, "Execution");
    settings.Add("WALLSLIDING", true, "Wall Jump");
    settings.Add("FISTCHARGE", false, "Power Punch");
    settings.Add("MULTIJUMP", true, "Double Jump");
    settings.Add("EXECUTIONBONUS", false, "Execution+");
    settings.Add("FISTWAZAA", false, "Rising Punch");
    settings.Add("GLIDING", false, "GLIDING");
    settings.Add("PARRY", false, "Parry");
    settings.Add("FISTWAZAB", false, "FISTWAZAB");
    settings.Add("DASH", true, "Omni-Dash");
    settings.Add("CHAINTRICK", false, "CHAINTRICK");
    settings.Add("SCUBA", false, "SCUBA");
    settings.Add("WATERDRILLING", false, "WATERDRILLING");
    settings.Add("DASHTHROUGH", true, "Omni-Dash+");
    settings.Add("BLENDERWAZAA", false, "BLENDERWAZAA");
    settings.Add("BLENDERWAZAB", false, "Screw Driver");
    settings.Add("FISTCHARGESUPER", false, "FISTCHARGESUPER");
    settings.Add("FISTWAZAASUPER", false, "FISTWAZAASUPER");
    settings.Add("FISTWAZABSUPER", false, "FISTWAZABSUPER");
    settings.Add("BLENDERWAZABSUPER", false, "BLENDERWAZABSUPER");
    settings.Add("BLENDERWAZAASUPER", false, "BLENDERWAZAASUPER");
    settings.Add("BERSERK", false, "BERSERK");

    settings.CurrentDefaultParent = "Progress";
    settings.Add("3407947:0:1", false, "Get Fist");
    settings.Add("3407940:0:1", true, "Get Drill");
    settings.Add("3407933:0:1", false, "Get Chain");
    settings.Add("3387461:1100:1101", false, "Ancient Complex door open");
    settings.Add("3387461:0:1202", false, "Yokozuna encounter");
    settings.Add("3400612:0:1", false, "Carrot Whiskey");
    settings.Add("3385619:0:1", false, "Zapper mini-boss");
    settings.Add("3383730:0:1", false, "Mechanical Core encounter");
    settings.Add("3403190:0:1", false, "Lower Torch Tower");
    settings.Add("3402729:0:1", false, "First Cicero encounter");
    settings.Add("3393781:0:1", true, "Enter prison");
    settings.Add("3393781:1:3", false, "Prison cutscenes end");
    settings.Add("3393781:3:4", false, "Voltage encounter");
    settings.Add("3393781:4:5", true, "Prison escape");
    settings.Add("3393808:0:1", true, "Get missile launcher");
    settings.Add("3393795:0:1", false, "Get weapons back");
    settings.Add("3386783:0:1", false, "Get Prison Key");
    settings.Add("3380565:0:1", false, "Tower Duke talk");
    settings.Add("3407626:0:1", true, "Water problem talk");
    settings.Add("3407682:0:1", false, "Start valve quest");
    settings.Add("3407682:1:3", false, "Get valve");
    settings.Add("3407682:3:4", false, "Valve quest end");
    settings.Add("3407597:0:1", true, "Flood eliminated");
    settings.Add("3386946:0:1", true, "Get Spark Key");
    settings.Add("3386946:1:-2", true, "Use Spark Key");
    settings.Add("3395657:0:1", true, "Stone worm escaped");
    settings.Add("3397081:0:1", true, "Coastal Fortress enter");
    settings.Add("3397067:0:1", false, "Yokozuna on the horizon");
    settings.Add("3396604:0:1", true, "Yokozuna defeated");
    settings.Add("3404611:0:1", false, "Junior Cicero encounter");
    settings.Add("3404348:0:1", true, "Junior Cicero defeated");
    settings.Add("3404547:0:1", false, "After Junior Cicero flee");
    settings.Add("3404566:0:1", false, "Elevator left lock");
    settings.Add("3404582:0:2", false, "Elevator right lock");
    settings.Add("3404383:0:1", false, "Elevator activated");
    settings.Add("3404383:1:2", false, "Elevator lockdown");
    settings.Add("3404383:2:3", true, "Elevator unlocked");
    settings.Add("3404383:3:4", false, "Eleavtor on top");
    settings.Add("3404312:0:2", false, "Elevator battle end");
    settings.Add("3404505:0:1", false, "Super Cicero encounter");
    settings.Add("3404505:1:2", true, "Super Cicero defeated");
}

start
{
    // BP_FISTGameMode_C index 0x002E5B77
    //if (old.GameModeType != current.GameModeType && current.GameModeType == 0x002E5B77)

    // [3387387] MainQuest
    if (vars.ProgressCurrent.ContainsKey(3387387) && vars.ProgressCurrent[3387387] == 1)
    {
        vars.GameTime = 0.0;
        vars.ProgressCurrent.Clear();
        vars.UnlocksCurrent.Clear();
        return true;
    }

    return false;
}

update
{
    vars.UpdateProgress();
    vars.UpdateUnlocks();

    vars.GameTime += (current.RealTime > old.RealTime)
        ? current.RealTime - old.RealTime
        : 0.0;

    /*
    // Debug Section
    StringBuilder OutputBuffer = new StringBuilder();
    foreach (var ProgressEntry in vars.ProgressCurrent)
    {
        int OldValue = -1;
        if (!vars.ProgressOld.TryGetValue(ProgressEntry.Key, out OldValue) || OldValue != ProgressEntry.Value)
        {
            OutputBuffer.AppendLine(ProgressEntry.Key.ToString() + " : " + OldValue.ToString() + " -> " + ProgressEntry.Value.ToString());
        }
    }
    foreach (var UnlockName in vars.UnlocksCurrent)
    {
        if (!vars.UnlocksOld.Contains(UnlockName))
            OutputBuffer.AppendLine(UnlockName);
    }
    if (OutputBuffer.Length > 0)
    {
        print(OutputBuffer.ToString());
    }
    */
}

/*
gameTime
{
    return TimeSpan.FromSeconds(vars.GameTime);
}
*/

isLoading
{
    // Still not found a good way to detect Loading Screen
    return /* current.GameModeType != 0x002E5B77 || */ current.PawnAddress == 0;
}

split
{
    // Prevents triggering after loading from Main Menu
    if (!vars.ProgressOld.ContainsKey(3387387) || vars.ProgressOld[3387387] == 0)
        return false;

    /*
    if (old.SkillRecover == 0 && current.SkillRecover != 0) // Carrot Whiskey
        return true;

    if (old.SkillMissile == 0 && current.SkillMissile != 0) // Rocket Launcher
        return true;
    */

    foreach (var UnlockName in vars.UnlocksCurrent)
    {
        if (!vars.UnlocksOld.Contains(UnlockName) && settings.ContainsKey(UnlockName) && settings[UnlockName])
        {
            print("Unlock Split: " + UnlockName);
            return true;
        }
    }

    foreach (var ProgressEntry in vars.ProgressCurrent)
    {
        int OldValue = 0;
        if (!vars.ProgressOld.TryGetValue(ProgressEntry.Key, out OldValue) || OldValue != ProgressEntry.Value)
        {
            var ProgressName = ProgressEntry.Key.ToString() + ":" + OldValue.ToString() + ":" + ProgressEntry.Value.ToString();
            if (settings.ContainsKey(ProgressName) && settings[ProgressName])
            {
                print("Progress Split: " + ProgressName);
                return true;
            }
        }
    }

    return false;
}
