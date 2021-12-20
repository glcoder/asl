state("ZingangGame-Win64-Shipping", "Steam")
{
}

init
{
    vars.Initialized = false;

    Func<string, int, IntPtr> OffsetSignatureScan = (string Signature, int OffsetPosition) => {
        var Scanner = new SignatureScanner(game, modules.First().BaseAddress, modules.First().ModuleMemorySize);
        IntPtr Pointer = Scanner.Scan(new SigScanTarget(Signature));
        if (Pointer != IntPtr.Zero)
        {
            var Offset = memory.ReadValue<int>(Pointer + OffsetPosition);
            Pointer = Pointer + Offset + OffsetPosition + sizeof(int);
        }
        return Pointer;
    };

    IntPtr GNames = OffsetSignatureScan("48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? C6 05 ?? ?? ?? ?? 01 0F 10 03 4C 8D 44 24 20 48 8B C8", 3);
    print("GNames = " + GNames.ToString("X16"));

    IntPtr GEngine = OffsetSignatureScan("48 8B 3D ?? ?? ?? ?? 48 89 6C 24 ?? 48 85 FF 74 ?? 48 8B 87 ?? ?? ?? ?? 48 85 C0 75 ?? 48 8B CF", 3);
    print("GEngine = " + GEngine.ToString("X16"));

    vars.PlayerPawn = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x38, 0x0, 0x30, 0x250);
    vars.RealTime = new MemoryWatcher<float>(new DeepPointer(GEngine, 0x780, 0x78, 0x5A0));

    var ProgressFlagManager = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x360, 0x50);
    var ActiveAbilityNameSet = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x3A8, 0xC8);
    var ActiveComboDefinitions = new DeepPointer(GEngine, 0x780, 0x78, 0x180, 0x3A8, 0x118);

    Action<IntPtr, int, Action<IntPtr>> ReadArray = (IntPtr ArrayPtr, int ElementSize, Action<IntPtr> Callback) => {
        IntPtr ArrayData = memory.ReadPointer(ArrayPtr);
        int ArrayNum = memory.ReadValue<int>(ArrayPtr + 0x8);
        for (int Index = 0; Index < ArrayNum; ++Index)
        {
            Callback(ArrayData + Index * ElementSize);
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
                int TagId = memory.ReadValue<int>(ArrayElement);
                string TagName;
                if (vars.Names.TryGetValue(TagId, out TagName))
                {
                    int TagProgress = memory.ReadValue<int>(ArrayElement + 0x8);
                    vars.ProgressCurrent.Add(TagName, TagProgress);
                }
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
                IntPtr AbilityNamePtr = memory.ReadPointer(ArrayElement);
                int AbilityNameLength = memory.ReadValue<int>(ArrayElement + 0x8);
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
                switch (memory.ReadValue<int>(ArrayElement)) {
                    case 1: WeaponName = "Fist";  break;
                    case 2: WeaponName = "Drill"; break;
                    case 3: WeaponName = "Chain"; break;
                };
                ReadArray(ArrayElement + 0x8, 0x18, (IntPtr ComboArrayElement) => {
                    IntPtr ComboNamePtr = memory.ReadPointer(ComboArrayElement);
                    int ComboNameLength = memory.ReadValue<int>(ComboArrayElement + 0x8);
                    string ComboName = memory.ReadString(ComboNamePtr, ReadStringType.UTF16, ComboNameLength * 2);
                    vars.UnlocksCurrent.Add(WeaponName + "_" + ComboName);
                });
            });
        }
    };

    vars.UpdateUnlocks = UpdateUnlocks;

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

        var CurrentBlock = memory.ReadValue<int>(GNames + 0x8);
        var CurrentByteCursor = memory.ReadValue<int>(GNames + 0xC);

        for (int BlockIndex = 0; BlockIndex < CurrentBlock; ++BlockIndex)
        {
            DumpBlock(BlockIndex, FNameBlockSize);
        }

        DumpBlock(CurrentBlock, CurrentByteCursor);

        return Names;
    };

    vars.DumpNames = DumpNames;
}

startup
{
    // Reduce CPU usage by reducing memory read operations
    refreshRate = 30;

    vars.Initialized = false;
    vars.Names = new Dictionary<int, string>();

    vars.GameTime = 0.0;
    vars.RealTimeOld = 0.0;
    vars.RealTimeCurrent = 0.0;

    vars.ProgressOld = new Dictionary<string, int>();
    vars.ProgressCurrent = new Dictionary<string, int>();
    vars.UnlocksOld = new HashSet<string>();
    vars.UnlocksCurrent = new HashSet<string>();

    settings.Add("Abilities", true, "Abilities");
    settings.Add("Combos", false, "Combos");
    settings.Add("Progress", true, "Game Progress");
    settings.Add("Training", false, "Wu Training");

    settings.CurrentDefaultParent = "Abilities";
    settings.Add("EXECUTION", false, "EXECUTION");
    settings.Add("WALLSLIDING", true, "Wall Jump");
    settings.Add("FISTCHARGE", false, "FISTCHARGE");
    settings.Add("MULTIJUMP", true, "Double Jump");
    settings.Add("EXECUTIONBONUS", false, "EXECUTIONBONUS");
    settings.Add("FISTWAZAA", false, "FISTWAZAA");
    settings.Add("GLIDING", false, "GLIDING");
    settings.Add("PARRY", false, "PARRY");
    settings.Add("FISTWAZAB", false, "FISTWAZAB");
    settings.Add("DASH", true, "Omni-Dash");
    settings.Add("CHAINTRICK", false, "CHAINTRICK");
    settings.Add("SCUBA", false, "SCUBA");
    settings.Add("WATERDRILLING", false, "WATERDRILLING");
    settings.Add("DASHTHROUGH", true, "Omni-Dash+");
    settings.Add("BLENDERWAZAA", false, "BLENDERWAZAA");
    settings.Add("BLENDERWAZAB", false, "BLENDERWAZAB");
    settings.Add("FISTCHARGESUPER", false, "FISTCHARGESUPER");
    settings.Add("FISTWAZAASUPER", false, "FISTWAZAASUPER");
    settings.Add("FISTWAZABSUPER", false, "FISTWAZABSUPER");
    settings.Add("BLENDERWAZABSUPER", false, "BLENDERWAZABSUPER");
    settings.Add("BLENDERWAZAASUPER", false, "BLENDERWAZAASUPER");
    settings.Add("BERSERK", false, "BERSERK");

    settings.CurrentDefaultParent = "Combos";
    settings.Add("Fist_ComboAttackX", false, "Fist_ComboAttackX");
    settings.Add("Fist_ComboAttackXX", false, "Fist_ComboAttackXX");
    settings.Add("Fist_ComboAttackXXX", false, "Fist_ComboAttackXXX");
    settings.Add("Fist_ComboAirAttackX", false, "Fist_ComboAirAttackX");
    settings.Add("Fist_ComboAirAttackXX", false, "Fist_ComboAirAttackXX");
    settings.Add("Fist_ComboAirAttackXXX", false, "Fist_ComboAirAttackXXX");
    settings.Add("Fist_ComboAttackY1", false, "Fist_ComboAttackY1");
    settings.Add("Fist_ComboAttackY2", false, "Fist_ComboAttackY2");
    settings.Add("Fist_ComboAirAttackY", false, "Fist_ComboAirAttackY");
    settings.Add("Fist_Feedback", false, "Fist_Feedback");
    settings.Add("Fist_ComboMinorWazaA", false, "Fist_ComboMinorWazaA");
    settings.Add("Fist_ComboMinorWazaAInAir", false, "Fist_ComboMinorWazaAInAir");
    settings.Add("Fist_ComboAttackXXY", false, "Fist_ComboAttackXXY");
    settings.Add("Fist_ComboAttackXXXY", false, "Fist_ComboAttackXXXY");
    settings.Add("Fist_ComboMinorWazaB", false, "Fist_ComboMinorWazaB");
    settings.Add("Fist_ComboAttackXY", false, "Fist_ComboAttackXY");
    settings.Add("Fist_ComboAttackXYY", false, "Fist_ComboAttackXYY");
    settings.Add("Fist_ComboAttackXXYY", false, "Fist_ComboAttackXXYY");
    settings.Add("Fist_ComboAttackXXXYY", false, "Fist_ComboAttackXXXYY");
    settings.Add("Fist_ComboAttackXXXYX", false, "Fist_ComboAttackXXXYX");
    settings.Add("Drill_ComboAttackX1", false, "Drill_ComboAttackX1");
    settings.Add("Drill_ComboAttackX2", false, "Drill_ComboAttackX2");
    settings.Add("Drill_ComboAttackX2X1", false, "Drill_ComboAttackX2X1");
    settings.Add("Drill_ComboAttackX2X2", false, "Drill_ComboAttackX2X2");
    settings.Add("Drill_ComboAttackX2X2X1", false, "Drill_ComboAttackX2X2X1");
    settings.Add("Drill_ComboAirAttackX1", false, "Drill_ComboAirAttackX1");
    settings.Add("Drill_ComboAttackB1", false, "Drill_ComboAttackB1");
    settings.Add("Drill_ComboAttackB2", false, "Drill_ComboAttackB2");
    settings.Add("Drill_ComboAttackY1", false, "Drill_ComboAttackY1");
    settings.Add("Drill_ComboAttackY2", false, "Drill_ComboAttackY2");
    settings.Add("Drill_ComboAirAttackY1", false, "Drill_ComboAirAttackY1");
    settings.Add("Drill_ComboAirAttackY2", false, "Drill_ComboAirAttackY2");
    settings.Add("Drill_ComboWaterAttackY", false, "Drill_ComboWaterAttackY");
    settings.Add("Drill_ComboAttackX2Y2", false, "Drill_ComboAttackX2Y2");
    settings.Add("Drill_ComboChargeX", false, "Drill_ComboChargeX");
    settings.Add("Drill_ComboAttackX2X2Y1", false, "Drill_ComboAttackX2X2Y1");
    settings.Add("Drill_ComboAttackX2Y2Y1", false, "Drill_ComboAttackX2Y2Y1");
    settings.Add("Drill_ComboSuperChargeX", false, "Drill_ComboSuperChargeX");
    settings.Add("Chain_ComboAttackX", false, "Chain_ComboAttackX");
    settings.Add("Chain_ComboAttackY_Lv1", false, "Chain_ComboAttackY_Lv1");
    settings.Add("Chain_ComboAirAttackY_Lv1", false, "Chain_ComboAirAttackY_Lv1");
    settings.Add("Chain_ComboAttackY_Lv2", false, "Chain_ComboAttackY_Lv2");
    settings.Add("Chain_ComboChainShield", false, "Chain_ComboChainShield");
    settings.Add("Chain_ComboAttackY_Lv3", false, "Chain_ComboAttackY_Lv3");
    settings.Add("Chain_ComboWazaB", false, "Chain_ComboWazaB");
    settings.Add("Chain_ComboWazaA", false, "Chain_ComboWazaA");
    settings.Add("Chain_ComboSuperWazaB", false, "Chain_ComboSuperWazaB");
    settings.Add("Chain_ComboSuperWazaA", false, "Chain_ComboSuperWazaA");
    settings.Add("Chain_ComboSuperChainShield", false, "Chain_ComboSuperChainShield");

    settings.CurrentDefaultParent = "Progress";
    settings.Add("MainQuest:0:1", false, "Intro cutscene");
    settings.Add("FirstMovie:0:99", false, "Intro cutscene ended");
    settings.Add("CBD.DlgEvent.Bear.01:0:1", false, "Urso cutscene");
    settings.Add("CBD.DlgEvent.Bear.01:1:99", false, "Chuan cutscene");
    settings.Add("MainQuest:1:2", false, "Game started");
    settings.Add("Weapon.Fist:0:1", false, "Fist acquired");
    settings.Add("Item.Quest.Pad:0:1", false, "Communicator acquired");
    settings.Add("Slum.PlayerDialogue1:0:99", false, "Monologue");
    settings.Add("Slum.Quest.FaceDog:0:1", false, "Firts Iron Dogs encounter");
    settings.Add("Slum.Quest.FaceDog2:0:1", false, "Second Iron Dogs encounter");
    settings.Add("Slum.Quest.FaceDog3:0:1", false, "Iron Dogs guarding Transformer");
    settings.Add("Slum.Quest.FaceDog3:1:2", false, "Iron Dogs defeated");
    settings.Add("Slum.Quest.LearnMechine1:0:1", false, "Monologue about Transformer");
    settings.Add("Slum.Quest.BearCall1:0:1", false, "Wall Jump acquired");
    settings.Add("Slum.Quest.BearCall1:1:2", false, "Calling Urso");
    settings.Add("Slum.PlayerDialogue2:0:99", false, "Monolgue about patrols");
    settings.Add("Slum.Quest.MapGot:0:1", false, "Mappo dialogue");
    settings.Add("Slum.Quest.MapGot:1:3", false, "Map acquired");
    settings.Add("Slum.Quest.TowerSoldier:0:1", false, "Torch Tower passage guard defeated");
    settings.Add("Slum.Quest.TowerSoldier:1:2", false, "Passage opened");
    settings.Add("Slum.Quest.01:0:1", false, "Torch Tower quest started");
    settings.Add("Slum.Quest.BearCall2:0:2", false, "Monologue about Transformer Drill");
    settings.Add("Slum.Quest.01.Door:0:1", false, "Wang in trouble");
    settings.Add("Slum.Quest.01:1:2", false, "Torch Tower quest advance");
    settings.Add("Slum.Quest.01.Door:1:2", false, "Wang defended");
    settings.Add("Slum.Quest.01:2:3", false, "Torch Tower quest advance");
    settings.Add("Slum.Quest.01.Door:2:3", false, "Secret door opened");
    settings.Add("Slum.Quest.BloodBottle:0:1", false, "Carrot Whiskey presented");
    settings.Add("Slum.Quest.BloodBottle:1:2", false, "Carrot Whiskey acquired");
    settings.Add("Slum.Quest.BattleRoom01:0:1", false, "Iron Dogs encounter");
    settings.Add("Slum.Quest.BattleRoom01:1:2", false, "Iron Dogs defeated");
    settings.Add("Slum.Quest.DogOut:0:1", false, "Iron Dogs fly outside");
    settings.Add("Slum.Quest.DogOut:1:99", false, "Iron Dogs ass kicked by Master Wu");
    settings.Add("Slum.Quest.FistCharge:0:1", false, "Fist Charge training started");
    settings.Add("Train.0:0:-1", false, "Master Wu training complete");
    settings.Add("Slum.Quest.FistCharge.Accomplished:0:1", false, "Master Wu dialogue");
    settings.Add("Slum.Quest.FistCharge:1:4", false, "Fist Charge acquired");
    settings.Add("Slum.Quest.FistCharge.Tutorial:0:1", false, "Fist Charge tutorial");
    settings.Add("Slum.PlayerDialogue3:0:99", false, "Monologue about Data Disk");
    settings.Add("Slum.Quest.FistCharge.Accomplished:1:2", false, "Fist Charge tutorial ended");
    settings.Add("Slum.CBT.Boss:0:1", false, "Dboule Jump acquired");
    settings.Add("Slum.CBT.Boss:1:2", false, "Feral Boss");
    settings.Add("Slum.BattleDialogue1:0:1", false, "Rayton makes jokes");
    settings.Add("Slum.CBT.Boss:2:3", false, "Feral Boss defeated");
    settings.Add("Slum.BattleDialogue1:1:2", false, "Last Feral dialogue");
    settings.Add("Slum.PlayerDialogue4:0:99", false, "Monologue about tough Feral");
    settings.Add("Slum.Quest.Shop:0:1", false, "Shop opened");
    settings.Add("Slum.Quest.WazaA:0:1", false, "Rising Punch quest started");
    settings.Add("Slum.Quest.WazaA:1:2", false, "Rising Punch acquired");
    settings.Add("Slum.Quest.WazaA:2:3", false, "Master Wu dialogue ended");
    settings.Add("MainQuest:2:3", false, "Power Station");
    settings.Add("Slum.Quest.WazaA:3:4", false, "Power Station entered");
    settings.Add("IndustryLD.Quest.FirstToChangeQuest:0:1", false, "Power Station quest started");
    settings.Add("IndustryLD.Quest.FirstIn:0:1", false, "Lady Q cutscene ended");
    settings.Add("IndustryLD.PlayerDialogue1:0:99", false, "Monologue about Lady Q");
    settings.Add("Slum.Quest.WazaA:4:5", false, "Power Station gears room");
    settings.Add("IndustryLD.Quest.ValveChat:0:1", false, "Iron Dogs valve dialogue");
    settings.Add("IndustryLD.Quest.ValveChat:1:2", false, "Dialogue ended");
    settings.Add("IndustryLD.Cutscene.01Valve:0:1", false, "Valve cutscene");
    settings.Add("IndustryLD.Quest.PowerOn:0:1", false, "Power Station activated");
    settings.Add("IndustryLD.Quest.ValveChat:2:3", false, "Last valve cutscene part");
    settings.Add("IndustryLD.Quest.BattleRoom03:0:1", false, "Green Dog fight");
    settings.Add("IndustryLD.Quest.AxeBattle:0:1", false, "Green Dog defeated");
    settings.Add("IndustryLD.Quest.BattleRoom03:1:2", false, "Iron Dogs fight");
    settings.Add("IndustryLD.Quest.PowerOn:1:2", false, "Gears room cutscene ended");
    settings.Add("IndustryLD.Quest.SmallBoss:0:1", false, "Zapper Boss");
    settings.Add("IndustryLD.Quest.SmallBoss:1:2", false, "Zapper Boss defeated");
    settings.Add("IndustryLD.Quest.BattleRoom04:0:1", false, "Pre Mechanical Core room fight");
    settings.Add("IndustryLD.Quest.BattleRoom04:1:2", false, "Fight over");
    settings.Add("IndustryLD.Cutscene.BossRoomLight:0:1", false, "Boss is near");
    settings.Add("IndustryLD.Cutscene.BossRoomLight:1:2", false, "Boss room activated");
    settings.Add("IndustryLD.Cutscene.05Core:0:1", false, "Mechanical Core");
    settings.Add("IndustryLD.Cutscene.BossRoomLight:2:3", false, "Boss room deactivated");
    settings.Add("IndustryLD.BossDead:0:1", false, "Mechanical Core defeated");
    settings.Add("MainQuest:3:4", false, "Drill");
    settings.Add("Slum.Quest.01:3:4", false, "Torch Tower quest advance");
    settings.Add("IndustryLD.Quest.DrillGot:0:1", false, "Drill acquired quest");
    settings.Add("Weapon.Drill:0:1", true, "Drill acquired");
    settings.Add("IndustryLD.AbilityTreasure.01:0:1", false, "Data Disk acquired");
    settings.Add("IndustryLD.Quest.MouseInBox:0:1", false, "Flip found");
    settings.Add("IndustryLD.Quest.MouseInBox:1:2", false, "Flip dialogue");
    settings.Add("Quest.KeyMouse:0:1", false, "Flip gives Skeleton Key ");
    settings.Add("Item.Key.1:0:1", false, "Skeleton Key acquired");
    settings.Add("IndustryLD.Fan.02:0:1", false, "Fans Well approach");
    settings.Add("IndustryLD.PlayerDialogue2:0:99", false, "Monologue");
    settings.Add("IndustryLD.Fan.02:1:0", false, "Fans Well leave");
    settings.Add("IndustryLD.Quest.GetBackUp:0:1", false, "Iron Dogs using Teleport");
    settings.Add("IndustryLD.Quest.TeleportMachine:0:1", false, "Teleport fight");
    settings.Add("IndustryLD.Quest.TeleportMachine:1:2", false, "Teleport fight over");
    settings.Add("IndustryLD.Quest.ParryStick:0:1", false, "Sock Batons acquired");
    settings.Add("Item.Key.1:1:2", false, "Skeleton Key used");
    settings.Add("IndustryLD.KeyBox.01:0:1", false, "Skeleton Box opened");
    settings.Add("Slum.Quest.WazaA:5:6", false, "Rising Punch quest ended");
    settings.Add("Slum.Quest.TowerSoldier2:0:2", false, "Torch Tower passage opened");
    settings.Add("Tower.Quest.FirstArrival:0:1", false, "Torch Tower approach");
    settings.Add("Tower.PlayerDialogue1:0:99", false, "Torch Tower monologue");
    settings.Add("Tower.Quest.MeetCicero:0:1", false, "Cicero encounter cutscene");
    settings.Add("Tower.Quest.MeetCicero:1:2", false, "Cutscene ended");
    settings.Add("Tower.Quest.EntranceBattle:0:1", false, "Iron Dogs encounter");
    settings.Add("Tower.Quest.EntranceBattle:1:2", false, "Iron Dogs defeated");
    settings.Add("Tower.Battleroom.Lower:0:1", false, "Trap Miniboss defeated");
    settings.Add("Tower.Battleroom.Lower.Cicero:0:1", false, "Cicero fight custscene");
    settings.Add("Tower.Battleroom.Lower.Cicero:1:2", false, "Rayton defeated");
    settings.Add("Prison.Quest.FirstInPrison:0:1", true, "Enter prison cutscene");
    settings.Add("MainQuest:4:5", false, "Prison");
    settings.Add("Prison.Quest.FirstInPrison:1:3", false, "Prison cutscene ended");
    settings.Add("Prison.PlayerDialogue.1:0:99", false, "Monolgue about prison");
    settings.Add("Prison.Quest.ElevatorCutscene:0:1", false, "Voltage elevator cutscene");
    settings.Add("Prison.Quest.GetLauncer:0:1", true, "Missile Launcher acquired");
    settings.Add("Prison.PlayerDialogue.2:0:99", false, "Monolgue about Missile Launcher");
    settings.Add("Prison.Quest.ActiveElevator:0:1", false, "Prison elevator activated");
    settings.Add("Prison.Quest.GetArmBack:0:1", false, "Weapons returned");
    settings.Add("Prison.PlayerDialogue.4:0:1", false, "Weapons monolgue");
    settings.Add("Prison.PlayerDialogue.4:1:99", false, "Monologue about weapons");
    settings.Add("Prison.Quest.FirstInPrison:3:4", false, "Voltage encounter");
    settings.Add("Prison.Quest.AmbushBattle:0:1", false, "Voltage fight begin");
    settings.Add("Item.Quest.PrisonKeys:0:1", false, "Prison Key acquired");
    settings.Add("Prison.Quest.AmbushBattle:1:2", false, "Voltage defeated");
    settings.Add("Prison.PlayerDialogue.3:0:99", false, "Monolgue about prison exit");
    settings.Add("Prison.Quest.FirstInPrison:4:5", true, "Prison break");
    settings.Add("Prison.PrisonStationCall1:0:1", false, "Urso call ended");
    settings.Add("Prison.Quest.Asi:0:1", false, "Buzz dialogue ended");
    settings.Add("MainQuest:5:6", false, "Duke");
    settings.Add("Prison.Quest.Mr_Du:0:1", false, "Duke quest started");
    settings.Add("CBD.Quest.DoorMouse:0:1", false, "Duke office access");
    settings.Add("Prison.PrisonStationCall2:0:1", false, "Duke dialogue ended");
    settings.Add("CBD.Quest.BearFirstTalk:0:1", false, "Urso workshop dialogue");
    settings.Add("CBD.NPC.Bear:0:1", false, "Urso encounter");
    settings.Add("Slum.Quest.Shop:1:2", false, "Shop accessed");
    settings.Add("Merchant.AbilityShard1:0:1", false, "Data Disk bought");
    settings.Add("CBD.Quest.OpenIndustryPortal:0:1", false, "Duke dialogue ended");
    settings.Add("Prison.Quest.Asi:1:2", false, "Duke left behind");
    settings.Add("CBD.SelfDialogue1:0:99", false, "Monologue about goals");

    settings.Add("CBD.Quest.OpenIndustryPortal:1:2", false, "CBD.Quest.OpenIndustryPortal");
    settings.Add("Portal.Industry:0:1", false, "Portal.Industry");
    settings.Add("Prison.Quest.Asi.FirstTalk:0:1", false, "Prison.Quest.Asi.FirstTalk");
    settings.Add("Metro.FakeSewer:0:1", false, "Metro.FakeSewer");
    settings.Add("Metro.Prison:0:1", false, "Metro.Prison");
    settings.Add("Metro.FakeSewer.Disappear:0:99", false, "Metro.FakeSewer.Disappear");
    settings.Add("WaterStation.NPC.MouseA.D1:0:1", true, "WaterStation.NPC.MouseA.D1");
    settings.Add("WaterStation.NPC.MouseA.D1:1:2", false, "WaterStation.NPC.MouseA.D1");
    settings.Add("WaterStation.Quest.waterstation2:0:1", false, "WaterStation.Quest.waterstation2");
    settings.Add("WaterStation.Flow.ValveBattle:0:1", false, "WaterStation.Flow.ValveBattle");
    settings.Add("WaterStation.Flow.ValveOn:0:1", false, "WaterStation.Flow.ValveOn");
    settings.Add("WaterStation.Quest.waterstation2:1:2", false, "WaterStation.Quest.waterstation2");
    settings.Add("WaterStation.Flow.EndBattle:0:1", false, "WaterStation.Flow.EndBattle");
    settings.Add("WaterStation.NPC.MouseA.D1:2:3", false, "WaterStation.NPC.MouseA.D1");
    settings.Add("WaterStation.Quest.waterstation2:2:3", false, "WaterStation.Quest.waterstation2");
    settings.Add("Item.Quest.WaterStation.Valve:0:1", false, "Item.Quest.WaterStation.Valve");
    settings.Add("WaterStation.Flow.BackdoorOpen:0:1", false, "WaterStation.Flow.BackdoorOpen");
    settings.Add("WaterStation.NPC.MouseA.D1:3:5", false, "WaterStation.NPC.MouseA.D1");
    settings.Add("WaterStation.Quest.waterstation2:3:4", false, "WaterStation.Quest.waterstation2");
    settings.Add("Item.Quest.WaterStation.Valve:1:-2", false, "Item.Quest.WaterStation.Valve");
    settings.Add("WaterStation.Flow.WaterExpelled:0:1", true, "WaterStation.Flow.WaterExpelled");
    settings.Add("Metro.Sewer:0:1", false, "Metro.Sewer");
    settings.Add("Metro.WaterStation:0:1", false, "Metro.WaterStation");
    settings.Add("Sewer.Quest.FirstIn:0:1", false, "Sewer.Quest.FirstIn");
    settings.Add("Sewer.Cutscene.FrogIntro:0:1", false, "Sewer.Cutscene.FrogIntro");
    settings.Add("Sewer.Flow.2jumpbattle:0:1", false, "Sewer.Flow.2jumpbattle");
    settings.Add("Sewer.Quest.Boss:0:1", false, "Sewer.Quest.Boss");
    settings.Add("Sewer.Quest.Boss:1:2", false, "Sewer.Quest.Boss");
    settings.Add("Item.Quest.Du.02:0:1", false, "Item.Quest.Du.02");
    settings.Add("Sewer.BearCall1:0:1", false, "Sewer.BearCall1");
    settings.Add("Sewer.StationManager:0:1", false, "Sewer.StationManager");
    settings.Add("NavFortLD.Quest.FirstIcon:0:1", false, "NavFortLD.Quest.FirstIcon");
    settings.Add("NavFortLD.WKey.Progress.01:0:1", false, "NavFortLD.WKey.Progress.01");
    settings.Add("NavFortLD.Music:0:1", false, "NavFortLD.Music");
    settings.Add("NavFortLD.BattleRoom.EntranceGuard:0:1", false, "NavFortLD.BattleRoom.EntranceGuard");
    settings.Add("SeasideLD.Quest.FirstIn:0:1", true, "Coastal Fortress enter");
    settings.Add("NavFortLD.Quest.FirstIn:0:1", false, "NavFortLD.Quest.FirstIn");
    settings.Add("NavFortLD.Collection.A01:0:1", false, "NavFortLD.Collection.A01");
    settings.Add("NavFortLD.Progress:0:1", false, "NavFortLD.Progress");
    settings.Add("NavFortLD.BattleRoom.01:0:1", false, "NavFortLD.BattleRoom.01");
    settings.Add("NavFortLD.Icon.BossPlatform:0:1", false, "NavFortLD.Icon.BossPlatform");
    settings.Add("NavFortLD.Progress:1:2", false, "NavFortLD.Progress");
    settings.Add("NavFortLD.Icon.BossPlatform:1:0", false, "NavFortLD.Icon.BossPlatform");
    settings.Add("NavFortLD.Progress:2:3", false, "NavFortLD.Progress");
    settings.Add("NavFortLD.Quest.OfficialDog:0:1", false, "NavFortLD.Quest.OfficialDog");
    settings.Add("NavFortLD.Quest.OfficialDog:1:2", false, "NavFortLD.Quest.OfficialDog");
    settings.Add("Item.Quest.Du.01:0:1", false, "Item.Quest.Du.01");
    settings.Add("NavFortLD.BearCall1:0:1", false, "NavFortLD.BearCall1");
    settings.Add("MainQuest:6:7", false, "MainQuest");
    settings.Add("WestMountain.Quest.MrDu:0:1", false, "WestMountain.Quest.MrDu");
    settings.Add("CBD.Quest.MrDu1:0:1", false, "CBD.Quest.MrDu1");
    settings.Add("CBD.NPC.Bear:1:5", false, "CBD.NPC.Bear");
    settings.Add("CBD.BearCall1:0:99", false, "CBD.BearCall1");
    settings.Add("MineCar.PathOfPainR.FirstArrive:0:1", false, "MineCar.PathOfPainR.FirstArrive");
    settings.Add("CBD.CollectorIcon.01:0:1", false, "CBD.CollectorIcon.01");
    settings.Add("PathOfPain.Quest.CableStationBattle:0:1", false, "PathOfPain.Quest.CableStationBattle");
    settings.Add("PathOfPain.PlayerDialogue.01:0:1", false, "PathOfPain.PlayerDialogue.01");
    settings.Add("PathOfPain.Quest.CableStationBattle:1:2", false, "PathOfPain.Quest.CableStationBattle");
    settings.Add("PathOfPain.Quest.CableStationBattle:2:3", false, "PathOfPain.Quest.CableStationBattle");
    settings.Add("MineCar.WestMountain.FirstArrive:0:1", false, "MineCar.WestMountain.FirstArrive");
    settings.Add("WestMountain.Quest.FirstIn:0:1", false, "WestMountain.Quest.FirstIn");
    settings.Add("WestMountain.Quest.AskFor:0:1", false, "WestMountain.Quest.AskFor");
    settings.Add("WestMountain.Quest.AskFor:1:2", false, "WestMountain.Quest.AskFor");
    settings.Add("Item.Quest.CaveKey:0:1", false, "Item.Quest.CaveKey");
    settings.Add("Item.Quest.CaveKey:1:-2", false, "Item.Quest.CaveKey");
    settings.Add("Cave.Quest.BattleRoom03:0:0", false, "Cave.Quest.BattleRoom03");
    settings.Add("Cave.Quest.FirstIn:0:1", false, "Cave.Quest.FirstIn");
    settings.Add("Cave.Quest.PunchIntro:0:1", false, "Cave.Quest.PunchIntro");
    settings.Add("Cave.Quest.PunchIntro:1:2", false, "Cave.Quest.PunchIntro");
    settings.Add("Cave.Quest.PunchIntro:2:3", false, "Cave.Quest.PunchIntro");
    settings.Add("Cave.Quest.RockBoss:0:1", false, "Cave.Quest.RockBoss");
    settings.Add("Cave.Quest.RockBoss:1:2", false, "Cave.Quest.RockBoss");
    settings.Add("Cave.Quest.Finish:0:1", false, "Cave.Quest.Finish");
    settings.Add("Cave.Quest.RockMovie:0:2", false, "Cave.Quest.RockMovie");
    settings.Add("Item.Tinder.1:0:1", false, "Item.Tinder.1");
    settings.Add("Cave.Quest.GotChain:0:1", false, "Cave.Quest.GotChain");
    settings.Add("Weapon.Chain:0:1", false, "Weapon.Chain");
    settings.Add("WestMountain.Quest.CaveBackDoorOpened:0:1", false, "WestMountain.Quest.CaveBackDoorOpened");
    settings.Add("UI.ArmCombo.Chain.0:0:1", false, "UI.ArmCombo.Chain.0");
    settings.Add("WestMountain.Quest.BullSequence:0:1", false, "WestMountain.Quest.BullSequence");
    settings.Add("WestMountain.Quest.Invasion:0:1", false, "WestMountain.Quest.Invasion");
    settings.Add("WestMountain.Music:0:1", false, "WestMountain.Music");
    settings.Add("WestMountain.Quest.BullSequence:1:2", false, "WestMountain.Quest.BullSequence");
    settings.Add("WestMountain.Battle.BeforeBridge:0:1", false, "WestMountain.Battle.BeforeBridge");
    settings.Add("WestMountain.Battle.Bridge:0:1", false, "WestMountain.Battle.Bridge");
    settings.Add("WestMountain.SelfDialogue.01:0:1", false, "WestMountain.SelfDialogue.01");
    settings.Add("WestMountain.Battle.Treasure:0:1", false, "WestMountain.Battle.Treasure");
    settings.Add("WestMountain.Battle.Treasure:1:2", false, "WestMountain.Battle.Treasure");
    settings.Add("WestMountain.Collection.A01:0:1", false, "WestMountain.Collection.A01");
    settings.Add("WestMountain.SelfDialogue.02:0:1", false, "WestMountain.SelfDialogue.02");
    settings.Add("WestMountain.SelfDialogue.01:1:2", false, "WestMountain.SelfDialogue.01");
    settings.Add("WestMountain.Quest.ToCableStation:0:1", false, "WestMountain.Quest.ToCableStation");
    settings.Add("WestMountain.Battle.CableCar:0:1", false, "WestMountain.Battle.CableCar");
    settings.Add("WestMountain.Quest.CableOn:0:1", false, "WestMountain.Quest.CableOn");
    settings.Add("WestMountain.Quest.BossMusic:0:1", false, "WestMountain.Quest.BossMusic");
    settings.Add("WestMountain.Music:1:0", false, "WestMountain.Music");
    settings.Add("WestMountain.Battle.CableCar:1:2", false, "WestMountain.Battle.CableCar");
    settings.Add("MainQuest:7:8", false, "MainQuest");
    settings.Add("WestMountain.Quest.MrDu:1:2", false, "WestMountain.Quest.MrDu");
    settings.Add("Cave.Quest.Finish:1:2", false, "Cave.Quest.Finish");
    settings.Add("WestMountain.Quest.Invasion:1:2", false, "WestMountain.Quest.Invasion");
    settings.Add("CBD.Quest.MeetCat:0:99", false, "CBD.Quest.MeetCat");
    settings.Add("Item.Tinder.1:1:-2", false, "Item.Tinder.1");
    settings.Add("CBD.ToFightMrDu:0:1", false, "CBD.ToFightMrDu");
    settings.Add("CBD.Quest.DuDeath:0:1", false, "CBD.Quest.DuDeath");
    settings.Add("CBD.Quest.DuDeath.Mech:0:1", false, "CBD.Quest.DuDeath.Mech");
    settings.Add("MainQuest:8:9", false, "MainQuest");
    settings.Add("CBD.ToFightMrDu:1:2", false, "CBD.ToFightMrDu");
    settings.Add("CBD.Quest.DuDeath:1:2", false, "CBD.Quest.DuDeath");
    settings.Add("CBD.Quest.DuDeath:2:3", false, "CBD.Quest.DuDeath");
    settings.Add("CBD.Quest.BearCatRabbit:0:1", false, "CBD.Quest.BearCatRabbit");
    settings.Add("CBD.Quest.DuDeath:3:4", false, "CBD.Quest.DuDeath");
    settings.Add("Portal.WestMountain:0:1", false, "Portal.WestMountain");
    settings.Add("Prison.Quest.Asi.SecondTalk:0:1", false, "Prison.Quest.Asi.SecondTalk");
    settings.Add("WaterBase.Quest.BearCall3:0:1", false, "WaterBase.Quest.BearCall3");
    settings.Add("WaterBase.Quest.BattleRoom02:0:1", false, "WaterBase.Quest.BattleRoom02");
    settings.Add("WaterBase.Quest.BattleRoom02:1:2", false, "WaterBase.Quest.BattleRoom02");
    settings.Add("WaterBase.Quest.In:0:1", false, "WaterBase.Quest.In");
    settings.Add("WaterBase.Quest.OctSequence:0:1", false, "WaterBase.Quest.OctSequence");
    settings.Add("WaterBase.Quest.BearCall1:0:1", false, "WaterBase.Quest.BearCall1");
    settings.Add("WaterBase.Quest.BattleRoom1:0:1", false, "WaterBase.Quest.BattleRoom1");
    settings.Add("WaterBase.Quest.BattleRoom1:1:2", false, "WaterBase.Quest.BattleRoom1");
    settings.Add("WaterBase.Quest.Laser1:0:1", false, "WaterBase.Quest.Laser1");
    settings.Add("WaterBase.Quest.BossBattle:0:1", false, "WaterBase.Quest.BossBattle");
    settings.Add("WaterBase.Quest.SharkLaserAttack:0:1", false, "WaterBase.Quest.SharkLaserAttack");
    settings.Add("WaterBase.Quest.SharkLaserAttack:1:2", false, "WaterBase.Quest.SharkLaserAttack");
    settings.Add("WaterBase.Quest.BossBattle:1:2", false, "WaterBase.Quest.BossBattle");
    settings.Add("WaterBase.Quest.Scuba:0:1", false, "WaterBase.Quest.Scuba");
    settings.Add("WaterBase.Quest.BearCall2:0:1", false, "WaterBase.Quest.BearCall2");
    settings.Add("MainQuest:9:10", false, "MainQuest");
    settings.Add("WaterBase.Quest.Scuba:1:2", false, "WaterBase.Quest.Scuba");
    settings.Add("WaterBase.Quest.BearCall2:1:2", false, "WaterBase.Quest.BearCall2");
    settings.Add("DeepWater.Quest.FirstIn:0:1", false, "DeepWater.Quest.FirstIn");
    settings.Add("DeepWater.Guild:0:1", false, "DeepWater.Guild");
    settings.Add("DeepWater.Quest.BattleRoom1:0:1", false, "DeepWater.Quest.BattleRoom1");
    settings.Add("DeepWater.Quest.BattleRoom1:1:2", false, "DeepWater.Quest.BattleRoom1");
    settings.Add("DeepWater.WATERDRILLING:0:1", false, "DeepWater.WATERDRILLING");
    settings.Add("DeepWater.Guild:1:2", false, "DeepWater.Guild");
    settings.Add("DeepWater.WATERDRILLING:1:2", false, "DeepWater.WATERDRILLING");
    settings.Add("DeepWater.Guild:2:3", false, "DeepWater.Guild");
    settings.Add("DeepWater.Quest.FourGuys2:0:1", false, "DeepWater.Quest.FourGuys2");
    settings.Add("DeepWater.Quest.FourGuys2:1:2", false, "DeepWater.Quest.FourGuys2");
    settings.Add("DeepWater.Quest.BossSnake:0:1", false, "DeepWater.Quest.BossSnake");
    settings.Add("DeepWater.Quest.BossSnake:1:2", false, "DeepWater.Quest.BossSnake");
    settings.Add("MainQuest:10:11", false, "MainQuest");
    settings.Add("DeepWater.Guild:3:4", false, "DeepWater.Guild");
    settings.Add("DeepWater.Quest.GetTinderBase:0:1", false, "DeepWater.Quest.GetTinderBase");
    settings.Add("Item.Tinder.2:0:1", true, "Get Spark Key");
    settings.Add("DeepWater.Quest.CloseWave:0:1", false, "DeepWater.Quest.CloseWave");
    settings.Add("RelicLD.Quest.ToReliicGuide:0:1", false, "RelicLD.Quest.ToReliicGuide");
    settings.Add("RelicLD.CutScene.FrontDoorDogs:0:1", false, "RelicLD.CutScene.FrontDoorDogs");
    settings.Add("RelicLD.CutScene.FrontDoorDogs:1:2", false, "RelicLD.CutScene.FrontDoorDogs");
    settings.Add("Item.Tinder.2:1:-2", true, "Use Spark Key");
    settings.Add("RelicLD.Boss.GiantHand:0:1", false, "RelicLD.Boss.GiantHand");
    settings.Add("RelicLD.Quest.BearCall2:0:1", false, "RelicLD.Quest.BearCall2");
    settings.Add("RelicLD.Quest.TinderBack:0:1", false, "RelicLD.Quest.TinderBack");
    settings.Add("RelicLD.Quest.EscapeFromSnake:0:1", true, "Stone worm escaped");
    settings.Add("MainQuest:11:12", false, "MainQuest");
    settings.Add("RelicLD.Quest.BearCall:0:1", false, "RelicLD.Quest.BearCall");
    settings.Add("SeasideLD.Quest.ToFort:0:1", false, "SeasideLD.Quest.ToFort");
    settings.Add("SeasideLD.Battle.Roof:0:1", false, "SeasideLD.Battle.Roof");
    settings.Add("SeasideLD.Quest.BearCall1:0:1", false, "SeasideLD.Quest.BearCall1");
    settings.Add("SeasideLD.Cutscene.EliteFrog:0:1", false, "SeasideLD.Cutscene.EliteFrog");
    settings.Add("SeasideLD.Quest.BearCall2:0:1", false, "SeasideLD.Quest.BearCall2");
    settings.Add("SeasideLD.Battle.4F:0:1", false, "SeasideLD.Battle.4F");
    settings.Add("SeasideLD.Quest.BearCall3:0:1", false, "SeasideLD.Quest.BearCall3");
    settings.Add("SeasideLD.Boss.Death:0:1", true, "Yokozuna defeated");
    settings.Add("MainQuest:12:13", false, "MainQuest");
    settings.Add("UpperTower.Quest.FirstIn:0:1", false, "UpperTower.Quest.FirstIn");
    settings.Add("UpperTower.Quest.JuniorCiceroCutscene:0:1", false, "UpperTower.Quest.JuniorCiceroCutscene");
    settings.Add("UpperTower.Progress.JuniorCicero:0:1", true, "Junior Cicero defeated");
    settings.Add("UpperTower.Progress.MainProgress:0:1", false, "UpperTower.Progress.MainProgress");
    settings.Add("UpperTower.Quest.JuniorCiceroCutscene:1:3", false, "UpperTower.Quest.JuniorCiceroCutscene");
    settings.Add("UpperTower.Quest.BearCallAfterJunior:0:1", false, "UpperTower.Quest.BearCallAfterJunior");
    settings.Add("UpperTower.Progress.MainProgress:1:2", false, "UpperTower.Progress.MainProgress");
    settings.Add("UpperTower.Quest.ElevatorLeft:0:1", false, "UpperTower.Quest.ElevatorLeft");
    settings.Add("UpperTower.Progress.RotatingTube:0:1", false, "UpperTower.Progress.RotatingTube");
    settings.Add("UpperTower.Progress.RotatingTube:1:2", false, "UpperTower.Progress.RotatingTube");
    settings.Add("UpperTower.Progress.RotatingTube:2:3", false, "UpperTower.Progress.RotatingTube");
    settings.Add("UpperTower.Quest.ElevatorRight:0:2", false, "UpperTower.Quest.ElevatorRight");
    settings.Add("UpperTower.Progress.MainProgress:2:3", true, "Elevator unlocked");
    settings.Add("UpperTower.Progress.RotatingTube:3:4", false, "UpperTower.Progress.RotatingTube");
    settings.Add("UpperTower.Progress.ElevatorBattle:0:2", false, "UpperTower.Progress.ElevatorBattle");
    settings.Add("UpperTower.Progress.MainProgress:3:4", false, "UpperTower.Progress.MainProgress");
    settings.Add("UpperTower.Progress.SuperCicero:0:0", false, "UpperTower.Progress.SuperCicero");
    settings.Add("UpperTower.Progress.SuperCicero:0:1", false, "UpperTower.Progress.SuperCicero");
    settings.Add("UpperTower.Progress.SuperCicero:1:2", true, "Super Cicero defeated");

    settings.CurrentDefaultParent = "Training";
    settings.Add("Portal.Deepwater:0:1", false, "Portal.Deepwater");
    settings.Add("Portal.TowerTop:0:1", false, "Portal.TowerTop");
    settings.Add("CBD.NPC.Training:0:3", false, "CBD.NPC.Training");
    settings.Add("Train.1:0:-1", false, "Train.1");
    settings.Add("Train.1:-1:1", false, "Train.1");
    settings.Add("Train.2:0:-1", false, "Train.2");
    settings.Add("Train.2:-1:1", false, "Train.2");
    settings.Add("Train.3:0:-1", false, "Train.3");
    settings.Add("Train.3:-1:1", false, "Train.3");
    settings.Add("UI.ArmCombo.Fist.2:0:1", false, "UI.ArmCombo.Fist.2");
    settings.Add("UI.ArmCombo.Chain.1:0:1", false, "UI.ArmCombo.Chain.1");
    settings.Add("UI.ArmCombo.Drill.1:0:1", false, "UI.ArmCombo.Drill.1");
    settings.Add("Train.4:0:-1", false, "Train.4");
    settings.Add("Train.4:-1:1", false, "Train.4");
    settings.Add("Train.5:0:-1", false, "Train.5");
    settings.Add("Train.5:-1:1", false, "Train.5");
    settings.Add("Train.6:0:-1", false, "Train.6");
    settings.Add("Train.6:-1:1", false, "Train.6");
    settings.Add("Train.7:0:-1", false, "Train.7");
    settings.Add("Train.7:-1:1", false, "Train.7");
    settings.Add("Item.Berserk.2:0:1", false, "Item.Berserk.2");
    settings.Add("CBD.NPC.RabbitBoy.BerserkStage:0:1", false, "CBD.NPC.RabbitBoy.BerserkStage");
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
    if (!vars.Initialized && vars.PlayerPawn.Deref<IntPtr>(game) != IntPtr.Zero)
    {
        vars.Initialized = true;
        vars.Names = vars.DumpNames();
        print("Names.Count = " + vars.Names.Count.ToString());
    }

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
