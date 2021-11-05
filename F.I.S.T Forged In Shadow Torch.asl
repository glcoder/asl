state("ZingangGame-Win64-Shipping", "Steam")
{
}

init
{
    Func<string, int, IntPtr> FindSignaturePointer = (string Signature, int OffsetPosition) => {
        var Scanner = new SignatureScanner(game, modules.First().BaseAddress, modules.First().ModuleMemorySize);
        IntPtr Pointer = Scanner.Scan(new SigScanTarget(Signature));
        if (Pointer != IntPtr.Zero)
        {
            var Offset = memory.ReadValue<int>(IntPtr.Add(Pointer, OffsetPosition));
            Pointer = IntPtr.Add(Pointer, Offset + OffsetPosition + sizeof(int));
        }
        return Pointer;
    };

    IntPtr GNames = FindSignaturePointer("48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? C6 05 ?? ?? ?? ?? 01 0F 10 03 4C 8D 44 24 20 48 8B C8", 3);
    print("GNames = " + GNames.ToString("X16"));

    IntPtr GEngine = FindSignaturePointer("48 8B 3D ?? ?? ?? ?? 48 89 6C 24 ?? 48 85 FF 74 ?? 48 8B 87 ?? ?? ?? ?? 48 85 C0 75 ?? 48 8B CF", 3);
    print("GEngine = " + memory.ReadPointer(GEngine).ToString("X16"));

    Func<Dictionary<int, string>> DumpNames = () => {
        int FNameStride = 2;
        int FNameDataOffset = 2;
        int FNameMaxBlockBits = 13;
        int FNameBlockOffsetBits = 16;
        int FNameMaxBlocks = 1 << FNameMaxBlockBits;
        int FNameBlockOffsets = 1 << FNameBlockOffsetBits;
        int FNameBlockSize = FNameStride * FNameBlockOffsets;

        var Names = new Dictionary<int, string>();

        Action<int,int> DumpBlock = (int BlockIndex, int BlockSize) => {
            IntPtr BlockPtr = memory.ReadPointer(GNames + 16 + BlockIndex * 8);
            var BlockEnd = BlockPtr.ToInt64() + BlockSize - FNameDataOffset;
            int Offset = 0;

            while (BlockPtr.ToInt64() < BlockEnd)
            {
                var Header = memory.ReadValue<short>(BlockPtr);
                var IsWide = (Header & 1) == 1;
                var Length = (Header >> 6);
                if (Length == 0)
                    break;

                var NameSize = Length * (IsWide ? 2 : 1);
                var Value = memory.ReadString(BlockPtr + FNameDataOffset, IsWide ? ReadStringType.UTF16 : ReadStringType.UTF8, NameSize);

                var EntrySize = (FNameDataOffset + NameSize + FNameStride - 1) & ~(FNameStride - 1);
                BlockPtr = BlockPtr + EntrySize;

                var Handle = BlockIndex << FNameBlockOffsetBits | Offset;
                Offset += EntrySize / FNameStride;

                Names.Add(Handle, Value);
            }
        };

        var CurrentBlock = memory.ReadValue<int>(IntPtr.Add(GNames, 0x8));
        var CurrentByteCursor = memory.ReadValue<int>(IntPtr.Add(GNames, 0xC));

        for (int BlockIndex = 0; BlockIndex < CurrentBlock; ++BlockIndex)
        {
            DumpBlock(BlockIndex, FNameBlockSize);
        }
        DumpBlock(CurrentBlock, CurrentByteCursor);

        return Names;
    };

    vars.Names = DumpNames();
    print("Names.Count = " + vars.Names.Count.ToString());

    vars.PlayerPawn = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x38, 0x0, 0x30, 0x250);
    vars.RealTime = new MemoryWatcher<float>(new DeepPointer(GEngine, 0x780, 0x78, 0x5A0));

    var ProgressFlagManager = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x358, 0x50);
    var ActiveAbilityNameSet = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x3A0, 0xC8);
    var ActiveComboDefinitions = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x3A0, 0x118);

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
        if (ProgressFlagManager.DerefOffsets(game, out ProgressFlagManagerPtr))
        {
            ReadArray(ProgressFlagManagerPtr, 0x14, (IntPtr ArrayElement) => {
                int TagHandle = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x0));
                int Progress = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x8));
                vars.ProgressCurrent.Add(vars.Names[TagHandle], Progress);
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
        if (ActiveAbilityNameSet.DerefOffsets(game, out ActiveAbilityNameSetPtr))
        {
            ReadArray(ActiveAbilityNameSetPtr, 0x18, (IntPtr ArrayElement) => {
                IntPtr AbilityNamePtr = memory.ReadPointer(IntPtr.Add(ArrayElement, 0x0));
                int AbilityNameLength = memory.ReadValue<int>(IntPtr.Add(ArrayElement, 0x8));
                string AbilityName = memory.ReadString(AbilityNamePtr, ReadStringType.UTF16, AbilityNameLength * 2);
                vars.UnlocksCurrent.Add(AbilityName);
            });
        }

        // Weapons Combos
        IntPtr ActiveComboDefinitionsPtr = IntPtr.Zero;
        if (ActiveComboDefinitions.DerefOffsets(game, out ActiveComboDefinitionsPtr))
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
    };

    vars.UpdateUnlocks = UpdateUnlocks;
}

startup
{
    // Reduce CPU usage by reducing memory read operations
    refreshRate = 30;

    vars.GameTime = 0.0;
    vars.RealTimeOld = 0.0;
    vars.RealTimeCurrent = 0.0;

    vars.ProgressOld = new Dictionary<string, int>();
    vars.ProgressCurrent = new Dictionary<string, int>();

    vars.UnlocksOld = new HashSet<string>();
    vars.UnlocksCurrent = new HashSet<string>();

    settings.Add("Abilities", true, "Abilities");
    settings.Add("Progress", true, "Game Progress");

    settings.CurrentDefaultParent = "Abilities";
    settings.Add("WALLSLIDING", true, "Wall Jump");
    settings.Add("MULTIJUMP", true, "Double Jump");
    settings.Add("DASH", true, "Omni-Dash");
    settings.Add("DASHTHROUGH", true, "Omni-Dash+");

    settings.CurrentDefaultParent = "Progress";
    settings.Add("Weapon.Drill:0:1", true, "Get Drill");
    settings.Add("Prison.Quest.FirstInPrison:0:1", true, "Enter prison");
    settings.Add("Prison.Quest.FirstInPrison:4:5", true, "Prison escape");
    settings.Add("Prison.Quest.GetLauncer:0:1", true, "Get missile launcher");
    settings.Add("WaterStation.NPC.MouseA.D1:0:1", true, "Water problem talk");
    settings.Add("WaterStation.Flow.WaterExpelled:0:1", true, "Flood eliminated");
    settings.Add("Item.Tinder.2:0:1", true, "Get Spark Key");
    settings.Add("Item.Tinder.2:1:-2", true, "Use Spark Key");
    settings.Add("RelicLD.Quest.EscapeFromSnake:0:1", true, "Stone worm escaped");
    settings.Add("SeasideLD.Quest.FirstIn:0:1", true, "Coastal Fortress enter");
    settings.Add("SeasideLD.Boss.Death:0:1", true, "Yokozuna defeated");
    settings.Add("UpperTower.Progress.JuniorCicero:0:1", true, "Junior Cicero defeated");
    settings.Add("UpperTower.Progress.MainProgress:2:3", true, "Elevator unlocked");
    settings.Add("UpperTower.Progress.SuperCicero:1:2", true, "Super Cicero defeated");
}

start
{
    if (vars.ProgressCurrent.ContainsKey("MainQuest") && vars.ProgressCurrent["MainQuest"] == 1)
    {
        vars.GameTime = 0.0;
        vars.RealTimeCurrent = 0.0;
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

    vars.RealTime.Update(game);
    vars.GameTime += (vars.RealTime.Current > vars.RealTime.Old)
        ? vars.RealTime.Current - vars.RealTime.Old
        : 0.0;

    // Debug Section
    StringBuilder OutputBuffer = new StringBuilder();
    foreach (var ProgressEntry in vars.ProgressCurrent)
    {
        int OldValue = -1;
        if (!vars.ProgressOld.TryGetValue(ProgressEntry.Key, out OldValue) || OldValue != ProgressEntry.Value)
        {
            OutputBuffer.AppendLine(ProgressEntry.Key + " : " + OldValue.ToString() + " -> " + ProgressEntry.Value.ToString());
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
    return vars.PlayerPawn.Deref<IntPtr>(game) == IntPtr.Zero;
}

split
{
    // Prevents triggering after loading from Main Menu
    if (!vars.ProgressOld.ContainsKey("MainQuest") || vars.ProgressOld["MainQuest"] == 0)
        return false;

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
            var ProgressName = ProgressEntry.Key + ":" + OldValue.ToString() + ":" + ProgressEntry.Value.ToString();
            if (settings.ContainsKey(ProgressName) && settings[ProgressName])
            {
                print("Progress Split: " + ProgressName);
                return true;
            }
        }
    }

    return false;
}
