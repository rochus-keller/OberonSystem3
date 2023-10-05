(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich. e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract. The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE ASPI;	(** non-portable *)	(* Contributed by P. Ryser to the System 3 project *)

	IMPORT SYSTEM, PCI, NCRScript, Kernel;

	CONST
		debug = FALSE; intdebug = FALSE; msgdebug = FALSE; devlistdebug = FALSE; fifodebug = FALSE;
		ManagerId = "ASPI for Oberon";

		(* Exported ASPI Constants *)
		SSComp* = 0X;	SSFailedInit* = 1X;	SSInvalidHa* = 2X;	SSNoDevice* = 3X;
		SSPending* = 4X;	SSAborted* = 5X;	SSAbortFail* = 6X;	SSErr* = 7X;
		SSInvalidSRB* = 8X;	SSInvalidPathId* = 9X;	SSBufferToBig* = 10X;	SSBufferAlign* = 11X;
		SSSecurityViolation* = 12X;
		
		FlagsDirIn* = 0;	FlagsDirOut* = 1;	FlagsEventNotify* = 2;
		FlagsPosting* = 3;	FlagsEnResCount* = 4;
		
		HaStatOk* = 0X;	HaStatTimeout* = 1X;	HaStatCommandTimeout* = 2X;
		HaStatSelectionTimeout* = 3X;	HaStatMessageReject* = 4X;	HaStatBusReset* = 5X;
		HaStatParityError* = 6X;	HaStatReqSenseFailed* = 7X;	HaStatDoDu* = 8X;
		HaStatBusFree* = 9X;	HaStatPhaseErr* = 10X;

		StatusGood* = 0X;	StatusChkCond* = 2X;	StatusBusy* = 8X;	StatusResConf* = 18X;
		StatMask = {1..5};
		
		DiskNotInt13* = 3X;	DiskInt13AndDos* = 2X;	DiskInt13* = 1X;
		
		(* NCR Device & Version Id's *)
		NCRVendorId = 1000H;
		DevIDs = 7;
		C810DevId = 1H; C810VerId = 0H; C810AVerId = 10H; C810ALVVerId = 20H;
		C810APDevId = 5H;
		C815DevId = 4H;
		C820DevId = 2H;
		C825DevId = 3H; C825VerId = 0H; C825AVerId = 10H;
		C860DevId = 6H; C860VerId = 0H; C860LVVerId = 10H;
		C875DevId = 0FH;
		
		(* NCR  53C810 Registers *)
		SCNTL0 = 00H; SCNTL1 = 01H; SCNTL2 = 02H; SCNTL3 = 03H;
		SCID = 04H; SXFER = 05H; SDID = 06H; GPREG = 07H;
		SFBR = 08H; SOCL = 09H; SSID = 0AH; SBCL = 0BH;
		DSTAT = 0CH; SSTAT0 = 0DH; SSTAT1 = 0EH; SSTAT2 = 0FH;
		DSA = 10H; ISTAT = 14H; CTEST0 = 18H; CTEST1 = 19H;
		CTEST2 = 1AH; CTEST3 = 1BH; TEMP = 1CH; DFIFO = 20H;
		CTEST4 = 21H; CTEST5 = 22H; CTEST6 = 23H; DBC = 24H;
		DCMD = 27H; DNAD = 28H; DSP = 2CH; DSPS = 30H;
		SCRATCHA = 34H; SCRATCHA0 = 34H; SCRATCHA1 = 35H; SCRATCHA2 = 36H; SCRATCHA3 = 37H;
		DMODE = 38H; DIEN = 39H; SBR = 3AH; DCNTL = 3BH;
		ADDER = 3CH; SIEN0 = 40H; SIEN1 = 41H;
		SIST0 = 42H; SIST1 = 43H; SLPAR = 44H; SWIDE = 45H;
		MACNTL = 46H; GPCNTL = 47H; STIME0 = 48H; STIME1 = 49H;
		RESPID0 = 4AH; RESPID1 = 4BH; STEST0 = 4CH; STEST1 = 4DH;
		STEST2 = 4EH; STEST3 = 4FH; SIDL = 50H; SODL = 54H;
		SODL1 = 55H; SBDL = 58H;
		SCRATCHB = 5CH; SCRATCHB0 = 5CH; SCRATCHB1 = 5DH; SCRATCHB2 = 5EH; SCRATCHB3 = 5FH;
		SCRATCHC = 60H; SCRATCHC0 = 60H; SCRATCHC1 = 61H; SCRATCHC2 = 62H; SCRATCHC3 = 63H;
		SCRATCHD = 64H; SCRATCHD0 = 64H; SCRATCHD1 = 65H; SCRATCHD2 = 66H; SCRATCHD3 = 67H;
		SCRATCHE = 68H; SCRATCHE0 = 68H; SCRATCHE1 = 69H; SCRATCHE2 = 6AH; SCRATCHE3 = 6BH;
		SCRATCHF = 6CH; SCRATCHF0 = 6CH; SCRATCHF1 = 6DH; SCRATCHF2 = 6EH; SCRATCHF3 = 6FH;
		SCRATCHG = 70H; SCRATCHG0 = 70H; SCRATCHG1 = 71H; SCRATCHG2 = 72H; SCRATCHG3 = 73H;
		SCRATCHH = 74H; SCRATCHH0 = 74H; SCRATCHH1 = 75H; SCRATCHH2 = 76H; SCRATCHH3 = 77H;
		SCRATCHI = 78H; SCRATCHI0 = 78H; SCRATCHI1 = 79H; SCRATCHI2 = 7AH; SCRATCHI3 = 7BH;
		SCRATCHJ = 7CH; SCRATCHJ0 = 7CH; SCRATCHJ1 = 7DH; SCRATCHJ2 = 7EH; SCRATCHJ3 = 7FH;
		
		DidBadTarget = 4H; DidParity = 6H; DidError = 7H; DidGross = 8H;
		DidPhaseMismatch = 100H; DidSCSIInterrupt = 101H; DidDMAInterrupt = 102H;
		DisconnectIdent = 0H;	(* use 40H for disconnection enabled *)

		MaxTarget = 7;	(* target id's from 0 to 6 allowed; id 7 for NCR-Chip *)
		MaxLun = 8;		(* lun id's from 0 to 7 allowed *)
		
		(* Constants for testing and measuring *)
		read* = 0; write* = 1; seek* = 2;
		
	TYPE
		Time* = RECORD
			high*, low*: LONGINT
		END;

		(* Data structure for measuring *)
		Measure* = POINTER TO MeasureDesc;
		MeasureDesc* = RECORD
			started*: LONGINT;
			IssueTime*, DeadLineTime*: Time;
			EnterTime*, LeaveTime*, ReenterTime*: Time
		END;

		(* ASPI Command Structures *)
		SRB* = POINTER TO SRBDesc;
		SRBDesc* = RECORD
			Status*, HaId*: CHAR;
			Flags*: SET
		END;
	
		HaInquirySRB* = POINTER TO HaInquirySRBDesc;
		HaInquirySRBDesc* = RECORD (SRBDesc)
			HaCount*, HaScsiId*: CHAR;
			HaManagerId*, HaIdentifier*, HaUnique*: ARRAY 16 OF CHAR
		END;
		
		GetDevTypeSRB* = POINTER TO GetDevTypeSRBDesc;
		GetDevTypeSRBDesc* = RECORD (SRBDesc)
			Target*, Lun*, DevType*: CHAR
		END;
		
		ExecIOCmdSRB* = POINTER TO ExecIOCmdSRBDesc;
		ExecIOCmdSRBDesc* = RECORD (SRBDesc)
			Target*, Lun*, SenseLen*, CDBLen*, HaStat*, TargStat*: CHAR;
			BufLen*, BufPointer*: LONGINT;
			CDB*: ARRAY 16 OF CHAR;
			SenseArea*: ARRAY 257 OF CHAR;
			next: ExecIOCmdSRB;
			(* fields for measuring *)
			meas*: Measure;	(* # NIL => measure.  pentium only. *)
		END;

		AbortCmdSRB* = POINTER TO AbortCmdSRBDesc;
		AbortCmdSRBDesc* = RECORD (SRBDesc)
			ToAbort: ExecIOCmdSRB
		END;
		
		ResetDevCmdSRB* = POINTER TO ResetDevCmdSRBDesc;
		ResetDevCmdSRBDesc* = RECORD (SRBDesc)
			Target*, Lun*, HaStat*, TargStat*: CHAR
		END;
		
		GetDiskInfoCmdSRB* = POINTER TO GetDiskInfoCmdSRBDesc;
		GetDiskInfoCmdSRBDesc* = RECORD (SRBDesc)
			Target*, Lun*, DriveFlags*, Int13HDriveInfo*, Heads*, Sectors*: CHAR
		END;
	
		(* Lun structure *)
		LunDesc = RECORD
			DevType: CHAR
		END;
	
		(* Target structure *)
		TargetPtr = POINTER TO TargetDescc;
		TargetDescc = RECORD
			first, last: ExecIOCmdSRB;
			id: LONGINT;	(* target id *)
			luns: LONGINT;	(* available LUN's for this target *)
			lun: ARRAY MaxLun OF LunDesc;
			bufTab: NCRScript.BufferTable
		END;
		
		(* Host Adapter Structure *)
		DevicePtr = POINTER TO DeviceDescc;
		DeviceDescc = RECORD
			devId, vendId, cmd, status, revId, classCode, CLS, latTimer, hdrType,
			baseAdr0, baseAdr1, baseAdr2, baseAdr3, baseAdr4, baseAdr5,
			CIS, subId, subVenId, baseAdrROM, intL, intP, minGnt, maxLat: LONGINT;
			devIdx, busNr, devNr, fktNr: LONGINT;
			ioport, memadr: LONGINT;
			memaccess: BOOLEAN;
			(* SCSI target support *)
			targetReady: SET;
			dnad, dbc, dfifo, sstat0, sstat1, sstat2, ctest2, msgInPtr, identLen, targetNum: LONGINT;
			msgIn, msgOut: CHAR;
			target: ARRAY MaxTarget OF TargetPtr;
			curTarget: TargetPtr;
			msgInBuf: ARRAY 64 OF CHAR;
			identify: ARRAY 7 OF CHAR;
		END;
		
	VAR	
		IDs: ARRAY DevIDs OF LONGINT;
		DevNum, Initres: LONGINT;
		Devs: ARRAY DevIDs OF DevicePtr;
		Ints: SET;
		
		disconnected: LONGINT;

	PROCEDURE -rdtsc;	(* pentium only *)
	CODE {SYSTEM.Pentium, SYSTEM.Privileged}
		;DB 0FH, 31H
		RDTSC
	END rdtsc;
	
	PROCEDURE GetTime(VAR time: Time);
	BEGIN
		rdtsc;
		SYSTEM.GETREG(2, time.high);
		SYSTEM.GETREG(0, time.low)
	END GetTime;
	
	PROCEDURE LogInt(i: LONGINT);
	BEGIN
		Kernel.WriteInt(i, 1)
	END LogInt;
	
	PROCEDURE LogHex(i: LONGINT);
	BEGIN
		Kernel.WriteHex(i, 8)
	END LogHex;
	
	PROCEDURE CheckAlign(target: TargetPtr);
	VAR adr: LONGINT;
	BEGIN
		adr := SYSTEM.ADR(target.bufTab[0].count);
		ASSERT((adr DIV 4) * 4 = adr, 100)
	END CheckAlign;

	PROCEDURE Wait(t: LONGINT);
	BEGIN
		t := t*100000;
		WHILE t > 0 DO DEC(t) END
	END Wait;
	
	
	PROCEDURE Read8(Dev: DevicePtr; adr: LONGINT; VAR val: CHAR);
	BEGIN
		IF Dev.memaccess THEN	(* Memory mapped access *)
			adr := adr + Dev.memadr;
			SYSTEM.GET(adr, val)
		ELSE	(* IO based access *)
		(*	adr := adr + Dev.ioport; *)
			SYSTEM.PORTIN(adr + Dev.ioport, val)
		END
	END Read8;
	
	PROCEDURE Read32(Dev: DevicePtr; adr: LONGINT; VAR val: LONGINT);
	BEGIN
		IF Dev.memaccess THEN	(* Memory mapped access *)
		(*	adr := adr + Dev.memadr; *)
			SYSTEM.GET(adr + Dev.memadr, val)
		ELSE	(* IO based access *)
		(*	adr := adr + Dev.ioport; *)
			SYSTEM.PORTIN(adr + Dev.ioport, val)
		END
	END Read32;
	
	PROCEDURE Write8(Dev: DevicePtr; adr: LONGINT; val: CHAR);
	BEGIN
		IF Dev.memaccess THEN	(* Memory mapped access *)
			adr := adr + Dev.memadr;
			SYSTEM.PUT(adr, val)
		ELSE	(* IO based access *)
		(*	adr := adr + Dev.ioport; *)
			SYSTEM.PORTOUT(adr + Dev.ioport, val)
		END
	END Write8;
	
	PROCEDURE Write32(Dev: DevicePtr; adr, val: LONGINT);
	BEGIN
		IF Dev.memaccess THEN	(* Memory mapped access *)
			adr := adr + Dev.memadr;
			SYSTEM.PUT(adr, val)
		ELSE	(* IO based access *)
		(*	adr := adr + Dev.ioport; *)
			SYSTEM.PORTOUT(adr + Dev.ioport, val)
		END
	END Write32;
	
	PROCEDURE InitIDs;
	BEGIN
		IDs[0] := C810DevId; IDs[1] := C810APDevId; IDs[2] := C815DevId; IDs[3] := C820DevId;
		IDs[4] := C825DevId; IDs[5] := C860DevId; IDs[6] := C875DevId;
	END InitIDs;

	PROCEDURE PCIFindSYMDevice(Dev: DevicePtr): LONGINT;
	VAR res, res1, regVal: LONGINT;
	BEGIN
		res := PCI.FindPCIDevice(Dev.devId, NCRVendorId, Dev.devIdx, Dev.busNr, Dev.devNr, Dev.fktNr);
		Kernel.WriteString("PCIFindSYMDevice"); Kernel.WriteLn;
		Kernel.WriteString("   Device: "); LogInt(Dev.devId); Kernel.WriteLn;
		Kernel.WriteString("   Vendor: "); LogInt(NCRVendorId); Kernel.WriteLn;
		Kernel.WriteString("   Index: "); LogInt(Dev.devIdx); Kernel.WriteLn;
		Kernel.WriteString("   res: "); LogInt(res); Kernel.WriteLn;
		IF res = PCI.Done THEN
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CmdReg, regVal); ASSERT(res1 = PCI.Done, 100);
			Dev.cmd := regVal MOD 10000H; Dev.status := regVal DIV 10000H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.RevIdReg, regVal); ASSERT(res1 = PCI.Done, 101);
			Dev.revId := regVal MOD 100H; Dev.classCode := regVal DIV 100H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CLSReg, regVal); ASSERT(res1 = PCI.Done, 102);
			Dev.CLS := regVal MOD 100H; Dev.latTimer := (regVal DIV 100H) MOD 100H;
			Dev.hdrType := (regVal DIV 10000H) MOD 100H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr0Reg, Dev.baseAdr0); ASSERT(res1 = PCI.Done, 110);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr1Reg, Dev.baseAdr1); ASSERT(res1 = PCI.Done, 111);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr2Reg, Dev.baseAdr2); ASSERT(res1 = PCI.Done, 112);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr3Reg, Dev.baseAdr3); ASSERT(res1 = PCI.Done, 113);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr4Reg, Dev.baseAdr4); ASSERT(res1 = PCI.Done, 114);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr5Reg, Dev.baseAdr5); ASSERT(res1 = PCI.Done, 115);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CISReg, Dev.CIS); ASSERT(res1 = PCI.Done, 103);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.SubvReg, regVal); ASSERT(res1 = PCI.Done, 104);
			Dev.subVenId := regVal MOD 10000H; Dev.subId := regVal DIV 10000H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.ROMReg, Dev.baseAdrROM); ASSERT(res1 = PCI.Done, 105);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.IntlReg, regVal); ASSERT(res1 = PCI.Done, 106);
			Dev.intL := regVal MOD 100H; Dev.intP := (regVal DIV 100H) MOD 100H;
			Dev.minGnt := (regVal DIV 10000H) MOD 100H; Dev.maxLat := (regVal DIV 1000000H);
			Dev.ioport := (Dev.baseAdr0 - 1) MOD 10000H; Dev.memadr := Dev.baseAdr1;
			Dev.memaccess := FALSE;
			INCL(Ints, Dev.intL);
			
			(* initialize SCSI options for this host adapter *)
			Dev.msgInPtr := 0; Dev.dbc := 0; Dev.dnad := 0;
			Dev.dfifo := 0; Dev.sstat0 := 0; Dev.sstat1 := 0; Dev.sstat2 := 0; Dev.ctest2 := 0;
			Dev.targetReady := {}; Dev.targetNum := 0;
			Dev.identify[0] := 0X; Dev.identify[1] := 1X; Dev.identify[2] := 3X;
			Dev.identify[3] := 1X; Dev.identify[4] := 19X; Dev.identify[5] := 8X; 
		END;
		RETURN res
	END PCIFindSYMDevice;

	PROCEDURE BuildDeviceList(VAR Devices: ARRAY OF DevicePtr; MaxDev: LONGINT): LONGINT;
	VAR i, NumDev: LONGINT;
	BEGIN
		i := 0; NumDev := 0; NEW(Devices[0]);
		WHILE i < DevIDs DO
			Devices[NumDev].devId := IDs[i];
			Devices[NumDev].devIdx := 0;
			WHILE (i < DevIDs) & (PCIFindSYMDevice(Devices[NumDev]) # PCI.DeviceNotFound) DO
				INC(NumDev); NEW(Devices[NumDev]);
				Devices[NumDev].devIdx := Devices[NumDev-1].devIdx+1;
				Devices[NumDev].devId := Devices[NumDev-1].devId
			END;
			INC(i)
		END;
		RETURN NumDev
	END BuildDeviceList;
	
	PROCEDURE ShowDeviceList(VAR Devices: ARRAY OF DevicePtr; MaxDev: LONGINT);
	VAR i: LONGINT; d: DevicePtr;
	BEGIN
		i := 0;
		WHILE i < MaxDev DO
			d := Devices[i];
			Kernel.WriteString("Device "); LogInt(i); Kernel.WriteLn;
			Kernel.WriteString("   busNr: "); LogInt(d.busNr); Kernel.WriteLn;
			Kernel.WriteString("   devNr: "); LogInt(d.devNr); Kernel.WriteLn;
			Kernel.WriteString("   fktNr: "); LogInt(d.fktNr); Kernel.WriteLn;
			Kernel.WriteString("   devIdx: "); LogInt(d.devIdx); Kernel.WriteLn;
			Kernel.WriteString("   vendId: "); LogInt(d.vendId); Kernel.WriteLn;
			Kernel.WriteString("   devId: "); LogInt(d.devId); Kernel.WriteLn;
			Kernel.WriteString("   cmd: "); LogInt(d.cmd); Kernel.WriteLn;
			Kernel.WriteString("   status: "); LogInt(d.status); Kernel.WriteLn;
			Kernel.WriteString("   revId: "); LogInt(d.revId); Kernel.WriteLn;
			Kernel.WriteString("   classCode: "); LogInt(d.classCode); Kernel.WriteLn;
			Kernel.WriteString("   CLS: "); LogInt(d.CLS); Kernel.WriteLn;
			Kernel.WriteString("   latTimer: "); LogInt(d.latTimer); Kernel.WriteLn;
			Kernel.WriteString("   hdrType: "); LogInt(d.hdrType); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 0: "); LogInt(d.baseAdr0); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 1: "); LogInt(d.baseAdr1); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 2: "); LogInt(d.baseAdr2); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 3: "); LogInt(d.baseAdr3); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 4: "); LogInt(d.baseAdr4); Kernel.WriteLn;
			Kernel.WriteString("   baseAdr 5: "); LogInt(d.baseAdr5); Kernel.WriteLn;
			Kernel.WriteString("   CIS: "); LogInt(d.CIS); Kernel.WriteLn;
			Kernel.WriteString("   subId: "); LogInt(d.subId); Kernel.WriteLn;
			Kernel.WriteString("   subVenId: "); LogInt(d.subVenId); Kernel.WriteLn;
			Kernel.WriteString("   baseAdrROM: "); LogInt(d.baseAdrROM); Kernel.WriteLn;
			Kernel.WriteString("   Int Line: "); LogInt(d.intL); Kernel.WriteLn;
			Kernel.WriteString("   Int Pin: "); LogInt(d.intP); Kernel.WriteLn;
			Kernel.WriteString("   Min Gnt: "); LogInt(d.minGnt); Kernel.WriteLn;
			Kernel.WriteString("   Max Lat: "); LogInt(d.maxLat); Kernel.WriteLn; 
			INC(i)
		END;
	END ShowDeviceList;

	PROCEDURE dsaEntryOut(Dev: DevicePtr; i: LONGINT);
	VAR adr, nr: LONGINT; val: CHAR;
	BEGIN
		nr := Dev.curTarget.bufTab[i].count;
		adr := Dev.curTarget.bufTab[i].address;
		IF nr > 20 THEN nr := 20 END;
		WHILE nr > 0 DO
			SYSTEM.GET(adr, val);
			LogInt(ORD(val)); Kernel.WriteChar(" ");
			INC(adr); DEC(nr)
		END;
		Kernel.WriteLn
	END dsaEntryOut;
	
	PROCEDURE dsaStrucOut(Dev: DevicePtr);
	BEGIN
		Kernel.WriteString("DSA Structure"); Kernel.WriteLn;
		Kernel.WriteString("   dsaSelect: "); LogHex(Dev.curTarget.bufTab[NCRScript.dsaSelect].count); Kernel.WriteLn;
		Kernel.WriteString("   dsaMsgOut: "); dsaEntryOut(Dev, NCRScript.dsaMsgOut);
		Kernel.WriteString("   dsaCmd: "); dsaEntryOut(Dev, NCRScript.dsaCmd);
		Kernel.WriteString("   dsaStatus: "); dsaEntryOut(Dev, NCRScript.dsaStatus);
		Kernel.WriteString("   dsaData("); LogInt(Dev.curTarget.bufTab[NCRScript.dsaData].count); Kernel.WriteString(", ");
			LogInt(Dev.curTarget.bufTab[NCRScript.dsaData].address); Kernel.WriteString("): "); dsaEntryOut(Dev, NCRScript.dsaData);
		Kernel.WriteString("   dsaMsgIn: "); dsaEntryOut(Dev, NCRScript.dsaMsgIn)
	END dsaStrucOut;

	PROCEDURE InitSiop(Dev: DevicePtr);
	VAR val: CHAR;
	BEGIN
		(* Reset SCSI Bus *)
(*		Read8(dev, SCNTL1, val); val := CHR((ORD(val) DIV 16)*16 + ORD(val) MOD 4 + 8);
		Write8(dev, SCNTL1, val); Wait(10); val := CHR((ORD(val) DIV 16)*16 + ORD(val) MOD 4);
		Write8(dev, SCNTL1, val); Wait(10); *)
		(* Reset & Init 53C810 *)
		Write8(Dev, ISTAT, 40X); Write8(Dev, ISTAT, 0X);	(* Reset *)
		Read8(Dev, DMODE, val);
		val := CHR((ORD(val) DIV 2)*2); Write8(Dev, DMODE, val);	(* enable automatic script start *)
		Write8(Dev, SCID, 47X);	(* SCSI Id 7; respond to Selection (* & Reselection +40X *)*)
		Write8(Dev, RESPID0, 80X);	(* set response mask for id 7 *)
		Write8(Dev, STIME0, 0FX);
		Write8(Dev, DIEN, 7DX);	(* enable DMA interrupts *)
		Write8(Dev, SIEN0, 8FX);	(* enable SCSI interrupts *)
		Write8(Dev, SIEN1, 5X);	(* ?? *)
		Write8(Dev, STEST3, 80X);	(* enable active negotiation *)
		Read8(Dev, STEST1, val); Kernel.WriteString("STEST1: "); LogInt(ORD(val)); Kernel.WriteLn;
		Write32(Dev, DSP, NCRScript.ScriptsAddress + NCRScript.EntWaitReselect)
	END InitSiop;

	PROCEDURE ReadIntRegs(Dev: DevicePtr; istats: SET; VAR dstats, sist0s, sist1s: SET);
	VAR ch: CHAR;
	BEGIN
		IF 0 IN istats THEN
			Read8(Dev, DSTAT, ch);
			dstats := SYSTEM.VAL(SET, ch);
			IF intdebug THEN Kernel.WriteString("DSTAT: "); LogHex(ORD(ch)); Kernel.WriteLn END;
		END;
		IF 1 IN istats THEN
			(* Wait(2); *) Read8(Dev, SIST0, ch);
			sist0s := SYSTEM.VAL(SET, ch);
			IF intdebug THEN Kernel.WriteString("SIST0: "); LogHex(ORD(ch)); Kernel.WriteLn; END;
			(* Wait(2); *) Read8(Dev, SIST1, ch);
			sist1s := SYSTEM.VAL(SET, ch);
			IF intdebug THEN Kernel.WriteString("SIST1: "); LogHex(ORD(ch)); Kernel.WriteLn END;
		END
	END ReadIntRegs;
	

	PROCEDURE SetSynchParameters(Dev: DevicePtr; tp, offs: CHAR);
	VAR xferp: LONGINT;
	BEGIN
		ASSERT(tp >= 19X, 100);
		ASSERT(offs <= 8X, 101);
		xferp := ((16*ORD(tp) - 1) DIV 100) - 3;	(* transfer period *)
		xferp := xferp*16+ORD(offs);
		Dev.curTarget.bufTab[NCRScript.dsaSelect].count :=
			(Dev.curTarget.bufTab[NCRScript.dsaSelect].count DIV 10000H)*10000H+xferp*100H;
		Write8(Dev, SXFER, CHR(xferp));
		IF intdebug THEN Kernel.WriteString("SXFER: "); LogInt(xferp); Kernel.WriteLn END;
	END SetSynchParameters;

(* --- Interrupt Handler --- *)
	PROCEDURE StartNextCommand(Dev: DevicePtr; VAR nextdsp: LONGINT);
	VAR targ: LONGINT; srb: ExecIOCmdSRB; val: CHAR; vals: SET;
	BEGIN
		Read8(Dev, ISTAT, val);
		vals := SYSTEM.VAL(SET, val); EXCL(vals, 5); val := SYSTEM.VAL(CHAR, vals);
		Write8(Dev, ISTAT, val);		(* ClearSIGP *)
		IF Dev.targetReady # {} THEN
			REPEAT
				Dev.targetNum := (Dev.targetNum+1) MOD MaxTarget;
			UNTIL Dev.targetNum IN Dev.targetReady;
			targ := Dev.targetNum; Dev.curTarget := Dev.target[targ];
			EXCL(Dev.targetReady, targ);
			srb := Dev.curTarget.first;
			srb.TargStat := 0FFX;
			Dev.identify[0] := CHR(DisconnectIdent + 80H + ORD(srb.Lun));
			Dev.curTarget.bufTab[NCRScript.dsaMsgOut].count := Dev.identLen;
			Dev.curTarget.bufTab[NCRScript.dsaMsgOut].address := SYSTEM.ADR(Dev.identify[0]);
			Dev.curTarget.bufTab[NCRScript.dsaCmd].count := ORD(srb.CDBLen);
			Dev.curTarget.bufTab[NCRScript.dsaCmd].address := SYSTEM.ADR(srb.CDB[0]);
			Dev.curTarget.bufTab[NCRScript.dsaData].count := srb.BufLen;
			Dev.curTarget.bufTab[NCRScript.dsaData].address := srb.BufPointer;
			Dev.curTarget.bufTab[NCRScript.dsaStatus].count := 1;
			Dev.curTarget.bufTab[NCRScript.dsaStatus].address := SYSTEM.ADR(srb.TargStat);
			Dev.curTarget.bufTab[NCRScript.dsaMsgIn].count := 1;
			Dev.curTarget.bufTab[NCRScript.dsaMsgIn].address := SYSTEM.ADR(Dev.msgIn);
			Write32(Dev, DSA, SYSTEM.ADR(Dev.curTarget.bufTab[0].count));
			Dev.dnad := srb.BufPointer; Dev.dbc := srb.BufLen;		(* if save pointer messages arrives before sending/receiving data *)
			nextdsp := NCRScript.EntSelection;
			IF srb.meas # NIL THEN GetTime(srb.meas.EnterTime); INC(srb.meas.started) END;
		ELSE nextdsp := NCRScript.EntWaitReselect
		END
	END StartNextCommand;
	
	PROCEDURE FinishCommand(Dev: DevicePtr; VAR nextdsp: LONGINT);
	VAR status: CHAR; srb: ExecIOCmdSRB;
	BEGIN
		srb := Dev.curTarget.first; Dev.curTarget.first := srb.next;
		IF srb.next = NIL THEN Dev.curTarget.last := NIL
		ELSE INCL(Dev.targetReady, Dev.curTarget.id)
		END;
		IF srb.TargStat = StatusGood THEN srb.Status := SSComp
		ELSE srb.Status := SSErr
		END;
		StartNextCommand(Dev, nextdsp)
	END FinishCommand;
	
	PROCEDURE ReloadDSA(Dev: DevicePtr);
	VAR val, xferp: CHAR; targ: LONGINT;
	BEGIN
		Read8(Dev, SFBR, val);
		targ := ORD(val); ASSERT(targ DIV 80H = 1, 100);
		targ := targ MOD 80H;	ASSERT(targ < MaxTarget, 101);
		Dev.curTarget := Dev.target[targ];
		xferp := CHR(Dev.curTarget.bufTab[NCRScript.dsaSelect].count DIV 100H);
		Write8(Dev, SXFER, xferp);
		Write32(Dev, DSA, SYSTEM.ADR(Dev.curTarget.bufTab[0].count))
	END ReloadDSA;

	PROCEDURE abnormFinished(Dev: DevicePtr; code: LONGINT; VAR nextdsp: LONGINT);
	BEGIN
		IF TRUE (* intdebug *) THEN
			Kernel.WriteString("Abnormal Finished: ");
			LogInt(Dev.devIdx); Kernel.WriteChar(" ");
			LogInt(Dev.curTarget.id); Kernel.WriteChar(" ");
			LogInt(ORD(Dev.curTarget.first.Lun)); Kernel.WriteChar(" ");
			LogHex(code); Kernel.WriteLn
		END;
		FinishCommand(Dev, nextdsp);
	END abnormFinished;

	PROCEDURE PhaseMismatch(Dev: DevicePtr; istats, dstats, sist0s, sist1s: SET; VAR nextdsp: LONGINT);
	VAR sbcl: CHAR; sbcls, sstat0s: SET; val: CHAR; dfifo: LONGINT;
	BEGIN
		Read8(Dev, SBCL, sbcl);
		sbcls := SYSTEM.VAL(SET, sbcl);
		Read32(Dev, DBC, Dev.dbc); Dev.dbc := Dev.dbc MOD 1000000H;
		Read32(Dev, DNAD, Dev.dnad);
		Read8(Dev, DFIFO, val); Dev.dfifo := ORD(val);
		Read8(Dev, SSTAT0, val); Dev.sstat0 := ORD(val);	sstat0s := SYSTEM.VAL(SET, Dev.sstat0);
		Read8(Dev, SSTAT1, val); Dev.sstat1 := ORD(val);
		Read8(Dev, SSTAT2, val); Dev.sstat2 := ORD(val);
		Read8(Dev, CTEST2, val); Dev.ctest2 := ORD(val);
		dfifo := Dev.dfifo - (Dev.dbc MOD 100H) MOD 80H;
		IF 5 IN sstat0s THEN INC(dfifo) END;
		IF 6 IN sstat0s THEN INC(dfifo) END;
		IF intdebug OR fifodebug THEN
			Kernel.WriteString("SBCL: "); LogHex(ORD(sbcl)); Kernel.WriteLn;
			Kernel.WriteString("DBC: "); LogInt(Dev.dbc); Kernel.WriteLn;
			Kernel.WriteString("DNAD: "); LogInt(Dev.dnad); Kernel.WriteLn;
			Kernel.WriteString("DFIFO: "); LogInt(Dev.dfifo); Kernel.WriteLn;
			Kernel.WriteString("SSTAT0: "); LogHex(Dev.sstat0); Kernel.WriteLn;
			Kernel.WriteString("SSTAT1: "); LogHex(Dev.sstat1); Kernel.WriteLn;
			Kernel.WriteString("SSTAT2: "); LogHex(Dev.sstat2); Kernel.WriteLn;
			Kernel.WriteString("CTEST2: "); LogHex(Dev.ctest2); Kernel.WriteLn;
			Kernel.WriteString("Bytes in FIFO: "); LogHex(dfifo); Kernel.WriteLn;
			IF (Dev.dfifo - (Dev.dbc MOD 100H)) MOD 80H # 0 THEN Kernel.WriteString("!!! DMA FIFO not empty !!!"); Kernel.WriteLn END;
		END;
		INC(Dev.dbc, dfifo); DEC(Dev.dnad, dfifo);
		IF {0,1,2}*sbcls = {0,1} THEN (* status phase *)
			IF intdebug OR fifodebug THEN dsaStrucOut(Dev); Kernel.WriteString("Jumping to command complete"); Kernel.WriteLn; END;
			nextdsp := NCRScript.EntResumeStatusPhase
		ELSIF {0,1,2}*sbcls = {0,1,2} THEN (* msg in *)
			IF intdebug OR fifodebug THEN dsaStrucOut(Dev); Kernel.WriteString("Jumping to message in"); Kernel.WriteLn END;
			nextdsp := NCRScript.EntResumeMsgInPhase
		ELSE abnormFinished(Dev, DidPhaseMismatch, nextdsp)	(* interrupt not handled; abort command *)
		END
	END PhaseMismatch;

	PROCEDURE SCSIInterrupt(Dev: DevicePtr; istats, dstats, sist0s, sist1s: SET; VAR nextdsp: LONGINT);
	VAR fatal: BOOLEAN; ch: CHAR;
	BEGIN
		fatal := FALSE;
		IF 2 IN sist1s THEN (* selection/reselection timeout *)
			fatal := TRUE;
			abnormFinished(Dev, DidBadTarget, nextdsp)
		END;
		IF 2 IN sist0s THEN (* unexpected Disconnect *)
			fatal := TRUE;
			abnormFinished(Dev, DidError, nextdsp);
		END;
		IF 1 IN sist0s THEN (* Parity Error *)
			fatal := TRUE;
			abnormFinished(Dev, DidParity, nextdsp);
		(*	nextdsp := NCRScripts.EntInitiatorAbort *)
		END;
		IF 3 IN sist0s THEN (* Gross Error *)
			fatal := TRUE;
			abnormFinished(Dev, DidGross, nextdsp);
		(*	nextdsp := NCRScripts.EntInitiatorAbort *)
		END;
		IF 7 IN sist0s THEN (* Phase mismatch *)
			fatal := TRUE;
			PhaseMismatch(Dev, istats, dstats, sist0s, sist1s, nextdsp)
		END;
		
		IF fatal THEN (* empty DMA & SCSI FIFO *)
			IF ~(0 IN istats) THEN ReadIntRegs(Dev, {0}, dstats, sist0s, sist1s) END; (* force reading of dstat reg *)
			IF ~(7 IN dstats) THEN
				IF intdebug OR fifodebug THEN Kernel.WriteString("DMA FIFO not empty"); Kernel.WriteLn; END;
				Write8(Dev, CTEST3, 4X);
				REPEAT Read8(Dev, CTEST3, ch) UNTIL ~(2 IN SYSTEM.VAL(SET, ch))
			END;
			Write8(Dev, STEST3, 2X);
			REPEAT Read8(Dev, STEST3, ch) UNTIL ~(1 IN SYSTEM.VAL(SET, ch))
		ELSE
			abnormFinished(Dev, DidSCSIInterrupt, nextdsp)	(* did not handle interrupt condition *)
		END;
	END SCSIInterrupt;
	
	PROCEDURE DMAInterrupt(Dev: DevicePtr; istats, dstats, sist0s, sist1s: SET; VAR nextdsp: LONGINT);
	VAR i, interrupt: LONGINT; ch: CHAR;
	BEGIN
		IF 2 IN dstats THEN (* Scripts interrupt instruction *)
			Read32(Dev, DSPS, interrupt);
			IF intdebug THEN
				Kernel.WriteString("Scripts interrupt: "); LogHex(interrupt); Kernel.WriteLn;
				IF interrupt DIV 10H # 3 THEN
					Kernel.WriteString("DBC: "); LogInt(Dev.dbc); Kernel.WriteLn;
					Kernel.WriteString("DNAD: "); LogInt(Dev.dnad); Kernel.WriteLn;
					dsaStrucOut(Dev)
				END
			END;
			CASE interrupt OF
				NCRScript.AIntErrUnexpectedPhase:
					IF intdebug THEN Kernel.WriteString("!!! Fatal Error !!!"); Kernel.WriteLn END;
					Wait(2); Read8(Dev, SBCL, ch);
					IF intdebug THEN Kernel.WriteString("SBCL: "); LogHex(ORD(ch)); Kernel.WriteLn; END
			| NCRScript.AIntErrSelectFailed: (* reselection during selection *)
					INCL(Dev.targetReady, Dev.curTarget.id);
					nextdsp := NCRScript.EntWaitReselect;
					IF intdebug THEN Kernel.WriteString("Reselection during selection: next interrupt must be AIntReselected"); Kernel.WriteLn END
			| NCRScript.AIntHandleMsgIn:
					Dev.msgInBuf[Dev.msgInPtr] := Dev.msgIn; INC(Dev.msgInPtr);
					IF intdebug THEN
						Kernel.WriteString("msgInBuf: ");
						FOR i := 0 TO Dev.msgInPtr-1 DO LogInt(ORD(Dev.msgInBuf[i])); Kernel.WriteChar(" ") END;
						Kernel.WriteLn
					END;
					CASE Dev.msgInPtr OF
						1:
							CASE Dev.msgInBuf[0] OF
								0X: (* command complete message *)
									Dev.msgInPtr := 0;
									nextdsp := NCRScript.EntCommandComplete
							|	1X: (* extended message *)
									nextdsp := NCRScript.EntCompleteMsgInPhase
							|	2X: (* save data pointer *)
									ASSERT(Dev.dnad = Dev.curTarget.bufTab[NCRScript.dsaData].count -
										Dev.dbc + Dev.curTarget.bufTab[NCRScript.dsaData].address, 100);
									Dev.msgInPtr := 0;
									Dev.curTarget.bufTab[NCRScript.dsaData].count := Dev.dbc;
									Dev.curTarget.bufTab[NCRScript.dsaData].address := Dev.dnad;
									nextdsp := NCRScript.EntCompleteMsgInPhase
							|	3X: (* restore data pointer *)
									Dev.msgInPtr := 0;
									nextdsp := NCRScript.EntCompleteMsgInPhase
							|	4X: (* disconnect *)
									INC(disconnected);
									Dev.msgInPtr := 0;
									nextdsp := NCRScript.EntDisconnected
							|	7X: (* message reject *) (* hopefully only for synch transfer req *)
									Dev.msgInPtr := 0;
									Read8(Dev, SOCL, ch); ch := CHR((ORD(ch) DIV 16) * 16  + ORD(ch) MOD 8);	(* Reset atn bit -> finish msg out phase *)
									Write8(Dev, SOCL, ch);
									nextdsp := NCRScript.EntCompleteMsgInPhase
							|	80X..87X: (* Identify *)
									Dev.msgInPtr := 0;
									nextdsp := NCRScript.EntCompleteMsgInPhase
							ELSE (* other message: reject *)
									Dev.msgInPtr := 0; Dev.msgOut := 7X;
									Dev.curTarget.bufTab[NCRScript.dsaMsgOut].address := SYSTEM.ADR(Dev.msgOut);
									Dev.curTarget.bufTab[NCRScript.dsaMsgOut].count := 1;
									nextdsp := NCRScript.EntRejectMsg
							END
					| 2, 3:
							CASE Dev.msgInBuf[1] OF
								2X, 3X: (* 2 byte extended message *)
									nextdsp := NCRScript.EntCompleteMsgInPhase
							ELSE (* some msg bytes more *)
								Dev.msgInPtr := 0; Dev.msgOut := 7X;
								Dev.curTarget.bufTab[NCRScript.dsaMsgOut].address := SYSTEM.ADR(Dev.msgOut);
								Dev.curTarget.bufTab[NCRScript.dsaMsgOut].count := 1;
								nextdsp := NCRScript.EntRejectMsg
							END
					| 4:
							IF Dev.msgInBuf[1] = 2X THEN Dev.msgInPtr := 0 END;
							nextdsp := NCRScript.EntCompleteMsgInPhase
					| 5:
							ASSERT(Dev.msgInBuf[1] = 3X, 101);
							Dev.msgInPtr := 0;
							nextdsp := NCRScript.EntCompleteMsgInPhase;
							IF Dev.msgInBuf[2] = 1X THEN SetSynchParameters(Dev, Dev.msgInBuf[3], Dev.msgInBuf[4]) END
					END
			| NCRScript.AIntNormDisc: StartNextCommand(Dev, nextdsp)
			| NCRScript.AIntGotSIGP: StartNextCommand(Dev, nextdsp)
			| NCRScript.AIntReselected: ReloadDSA(Dev); nextdsp := NCRScript.EntResumeMsgInPhase
			| NCRScript.AIntMsgOutPhase: nextdsp := NCRScript.EntResumeMsgOutPhase
			| NCRScript.AIntCmdPhase: nextdsp := NCRScript.EntResumeCmdPhase
			| NCRScript.AIntDataInPhase: nextdsp := NCRScript.EntResumeDataInPhase
			| NCRScript.AIntDataOutPhase: nextdsp := NCRScript.EntResumeDataOutPhase
			| NCRScript.AIntStatusPhase: nextdsp := NCRScript.EntResumeStatusPhase
			| NCRScript.AIntMsgInPhase: nextdsp := NCRScript.EntResumeMsgInPhase
			| NCRScript.AIntNormCommandComplete: FinishCommand(Dev, nextdsp)  (* start of next command included *)
			ELSE HALT(102)
			END
		ELSE
			abnormFinished(Dev, DidDMAInterrupt, nextdsp)	(* did not handle interrupt condition *)
		END;
	END DMAInterrupt;

	PROCEDURE InterruptHandler;
	VAR istat: CHAR; nextdsp, dspval, nr, dev: LONGINT; istats, dstats, sist0s, sist1s: SET; cursrb: ExecIOCmdSRB; Dev: DevicePtr;
	BEGIN
		IF intdebug THEN Kernel.WriteString("Entering InterruptHandler"); Kernel.WriteLn; END;
		nr := 0; dev := 0;
		WHILE dev < DevNum DO
			Dev := Devs[dev];
			IF intdebug THEN Kernel.WriteString("Device nr: "); LogInt(dev); Kernel.WriteLn; END;
			REPEAT
				nextdsp := -1;
				Read8(Dev, ISTAT, istat);
				istats := SYSTEM.VAL(SET, istat);
				IF intdebug THEN LogInt(nr); Kernel.WriteString(" ISTAT: "); LogHex(ORD(istat)); Kernel.WriteLn; END;
				IF 2 IN istats THEN (* INTFLY *)
					IF intdebug THEN
						Kernel.WriteString("Scripts INTFLY"); Kernel.WriteLn;
					END;
					cursrb := Dev.curTarget.first;
					IF (cursrb # NIL) & (cursrb.meas # NIL) THEN GetTime(cursrb.meas.ReenterTime) END;
					Write8(Dev, ISTAT, istat);
				END;
				IF (0 IN istats) OR (1 IN istats) THEN
					ReadIntRegs(Dev, istats, dstats, sist0s, sist1s);
					Read32(Dev, DSP, dspval);
					IF intdebug THEN LogInt(nr); Kernel.WriteString(" DSP: "); LogInt(dspval); Kernel.WriteLn END;
					IF 1 IN istats THEN SCSIInterrupt(Dev, istats, dstats, sist0s, sist1s, nextdsp) END;
					IF 0 IN istats THEN DMAInterrupt(Dev, istats, dstats, sist0s, sist1s, nextdsp) END;
					IF nextdsp # -1 THEN
						IF intdebug THEN Kernel.WriteString("Restarting SCSI Proc"); Kernel.WriteLn; END;
						Write32(Dev, DSP, NCRScript.ScriptsAddress + nextdsp)
					END
				END;
				INC(nr)
			UNTIL istats*{0..2} = {};
			INC(dev)
		END;
		IF intdebug THEN Kernel.WriteString("Leaving InterruptHandler"); Kernel.WriteLn; END;
	END InterruptHandler;

(* --- End of Interrupt Handler --- *)
	
	PROCEDURE HaInquiry(srb: HaInquirySRB);
	VAR i: LONGINT;
	BEGIN
		srb.HaCount := CHR(DevNum);
		srb.HaManagerId := ManagerId;
		IF (srb.HaId = 0X) & (DevNum = 0) THEN srb.Status := SSComp
		ELSIF srb.HaId < CHR(DevNum) THEN
			srb.HaScsiId := 7X;	(* is fix, at least for the moment (I assume, that will be a LONG moment) *)
			srb.Status := SSComp;
			CASE Devs[ORD(srb.HaId)].devId OF
				C810DevId: srb.HaIdentifier := "53C810"
			| C810APDevId: srb.HaIdentifier := "53C810AP"
			| C815DevId: srb.HaIdentifier := "53C815"
			| C820DevId: srb.HaIdentifier := "53C820"
			| C825DevId: srb.HaIdentifier := "53C825"
			| C860DevId: srb.HaIdentifier := "53C860"
			| C875DevId: srb.HaIdentifier := "53C875"
			END;
			FOR i := 8 TO 15 DO srb.HaUnique[i] := 0X END;
			srb.HaUnique[0] := 3X; srb.HaUnique[1] := 0X; srb.HaUnique[2] := 0X; srb.HaUnique[3] := 8X;
			srb.HaUnique[4] := 0FFX; srb.HaUnique[5] := 0FFX; srb.HaUnique[6] := 0FFX; srb.HaUnique[7] := 0X;
		ELSE srb.Status := SSInvalidHa
		END;
	END HaInquiry;

	PROCEDURE GetDevType(srb: GetDevTypeSRB);
	VAR dev, targ, lun: LONGINT;
	BEGIN
		dev := ORD(srb.HaId); targ := ORD(srb.Target); lun := ORD(srb.Lun);
		IF dev >= DevNum THEN srb.Status := SSInvalidHa
		ELSIF (targ >= MaxTarget) OR (lun >= MaxLun) THEN srb.Status := SSNoDevice
		ELSE
			IF lun >= Devs[dev].target[targ].luns THEN
				srb.Status := SSNoDevice;
				srb.DevType := 1FX
			ELSE
				srb.Status := SSComp;
				srb.DevType := Devs[dev].target[targ].lun[lun].DevType
			END
		END
	END GetDevType;
	
	PROCEDURE Insert(srb: ExecIOCmdSRB; dev, targ, lun: LONGINT);
	VAR val: CHAR; vals: SET;
	BEGIN
		SYSTEM.CLI();
		srb.Status := SSPending; srb.TargStat := 0FFX; srb.next := NIL;
		IF Devs[dev].target[targ].first = NIL THEN
			Devs[dev].target[targ].first := srb; Devs[dev].target[targ].last := srb;
			INCL(Devs[dev].targetReady, targ);
			Read8(Devs[dev], ISTAT, val);
			vals := SYSTEM.VAL(SET, val); INCL(vals, 5); val := SYSTEM.VAL(CHAR, vals);
			Write8(Devs[dev], ISTAT, val)		(* SetSIGP *)
		ELSE
			Devs[dev].target[targ].last.next := srb; Devs[dev].target[targ].last := srb
		END;
		SYSTEM.STI()
	END Insert;
	
	PROCEDURE ExecIOCmd(srb: ExecIOCmdSRB);
	VAR dev, targ, lun: LONGINT;
	BEGIN
		dev := ORD(srb.HaId); targ := ORD(srb.Target); lun := ORD(srb.Lun);
		IF (dev >= DevNum) OR (targ >= MaxTarget) OR (lun >= MaxLun) THEN srb.Status := SSInvalidSRB
		ELSE Insert(srb, dev, targ, lun)
		END
	END ExecIOCmd;
	
	PROCEDURE AbortCmd(srb: AbortCmdSRB);
	BEGIN
		Kernel.WriteString("not implemented"); Kernel.WriteLn;
		srb.Status := SSAbortFail
	END AbortCmd;
	
	PROCEDURE ResetDevCmd(srb: ResetDevCmdSRB);
	BEGIN
		Kernel.WriteString("not implemented"); Kernel.WriteLn;
		srb.Status := SSErr
	END ResetDevCmd;
	
	PROCEDURE GetDiskInfo(srb: GetDiskInfoCmdSRB);
	BEGIN
		Kernel.WriteString("not implemented"); Kernel.WriteLn;
		srb.Status := SSErr
	END GetDiskInfo;
	
	PROCEDURE SendASPICommand*(srb: SRB);
	BEGIN
		IF srb IS HaInquirySRB THEN HaInquiry(srb(HaInquirySRB))
		ELSIF srb IS GetDevTypeSRB THEN GetDevType(srb(GetDevTypeSRB))
		ELSIF srb IS ExecIOCmdSRB THEN ExecIOCmd(srb(ExecIOCmdSRB))
		ELSIF srb IS AbortCmdSRB THEN AbortCmd(srb(AbortCmdSRB))
		ELSIF srb IS ResetDevCmdSRB THEN ResetDevCmd(srb(ResetDevCmdSRB))
		ELSIF srb IS GetDiskInfoCmdSRB THEN GetDiskInfo(srb(GetDiskInfoCmdSRB))
		ELSE HALT(100) (* unknown ASPI-Function, shouldn't happen *)
		END;
	END SendASPICommand;

	PROCEDURE InitTargets(Dev: DevicePtr);
	VAR
		targ, lun: LONGINT;
		srb: ExecIOCmdSRB;
		data: ARRAY 0FFH OF CHAR;
	BEGIN
		NEW(srb);
		srb.HaId := CHR(Dev.devIdx); srb.Flags := {};
		srb.BufLen := 0FFH; srb.BufPointer := SYSTEM.ADR(data); srb.SenseLen := 0X;
		srb.CDBLen := 6X;
		srb.CDB[0] := 12X; srb.CDB[1] := 0X; srb.CDB[2] := 0X; srb.CDB[3] := 0X; srb.CDB[4] := 0FFX; srb.CDB[5] := 0X;
		srb.meas := NIL;
		targ := 0;
		WHILE targ < MaxTarget DO
			NEW(Dev.target[targ]); Dev.curTarget := Dev.target[targ]; CheckAlign(Dev.curTarget);
			Dev.target[targ].first := NIL; Dev.target[targ].last := NIL; Dev.target[targ].luns := 0;
			Dev.target[targ].bufTab[NCRScript.dsaSelect].count := 11H*1000000H + targ*10000H;
			Dev.target[targ].id := targ;
			Dev.identLen := 6;	(* try synchronous negotiation on lun 0 *)
			srb.Target := CHR(targ);
			lun := 0;
			WHILE (lun < MaxLun) & (lun = Dev.target[targ].luns) DO
				srb.Lun := CHR(lun);
				Dev.identify[0] := CHR(DisconnectIdent + 80H + lun);
				srb.CDB[1] := CHR(SYSTEM.LSH(lun, 5));
				SendASPICommand(srb);
				WHILE srb.Status = SSPending DO END;
				IF (srb.Status = SSComp) & (data[0] # 7FX) THEN
					Dev.target[targ].lun[Dev.target[targ].luns].DevType := data[0];
					LogInt(Dev.devIdx); Kernel.WriteChar(" "); LogInt(targ); Kernel.WriteChar(" "); LogInt(lun); Kernel.WriteChar(" "); LogInt(ORD(data[0])); Kernel.WriteLn;
					INC(Dev.target[targ].luns)
				END;
				Dev.identLen := 1;
				INC(lun)
			END;
			INC(targ)
		END
	END InitTargets;
	
	PROCEDURE InitASPI;
	VAR res: CHAR; res1, version, lastPCIbus, hwMech, dev: LONGINT; i: INTEGER;
	BEGIN
		res := SSFailedInit; DevNum := 0; ASSERT(Ints = {}, 100);
		res1 := PCI.PCIPresent(version, lastPCIbus, hwMech);
		IF res1 = PCI.Done THEN
			DevNum := BuildDeviceList(Devs, DevIDs);
			IF devlistdebug THEN ShowDeviceList(Devs, DevNum) END;
			res := SSComp;
			FOR i := 0 TO 31 DO
				IF i IN Ints THEN Kernel.InstallIP(InterruptHandler, Kernel.IRQ+i) END;
			END;
			dev := 0;
			WHILE dev < DevNum DO
				InitSiop(Devs[dev]);
				InitTargets(Devs[dev]);
				INC(dev)
			END
		END;
		Initres := ORD(res)
	END InitASPI;
	
	PROCEDURE GetASPISupportInfo*(): LONGINT;
	BEGIN
		RETURN SYSTEM.LSH(Initres, 8) + DevNum
	END GetASPISupportInfo;
	
	PROCEDURE Stop*;
	VAR i: INTEGER;
	BEGIN
		FOR i := 0 TO 31 DO
			IF i IN Ints THEN Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+i) END
		END;
		Ints := {};
	END Stop;

	PROCEDURE ResetAll*;
	BEGIN
		disconnected := 0;
		Stop;
		InitASPI
	END ResetAll;
	
BEGIN
	Ints := {};
	Kernel.InstallTermHandler(Stop);
	InitIDs;
	ResetAll
END ASPI.
