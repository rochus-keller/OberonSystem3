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

MODULE PCI;	(** non-portable *)	(* P. Ryser *)

	IMPORT SYSTEM, Kernel;
	
	CONST
		(* PCI Configuration Registers *)
		DevReg* = 0H; CmdReg* = 4H; RevIdReg* = 8H; CLSReg* = 0CH;
		Adr0Reg* = 10H; Adr1Reg* = 14H; Adr2Reg* = 18H;
		Adr3Reg* = 1CH; Adr4Reg* = 20H; Adr5Reg* = 24H;
		CISReg* = 28H; SubvReg* = 2CH; ROMReg* = 30H; IntlReg* = 3CH;
		
		debug = FALSE;
		
		Done* = 0;	NoPCI* = -1;  NoBios32* = -1;
		
		FuncNotSupported* = 81H; BadVendorId* = 83H; DeviceNotFound* = 86H;
		BadRegisterNumber* = 87H; SetFailed* = 88H; BufferTooSmall* = 89H;
		PCIServiceId = 49435024H;	(* "$PCI" *)
		PCIString = 20494350H;	(* " PCI" *)
		
		PCIFunctionId = 0B1H*256;
		PCIBiosPresent = 1H; findPCIDevice = 2H; findPCIClassCode = 3H; generateSpecialCycle = 6H;
		readConfigByte = 8H; readConfigWord = 9H; readConfigDword = 0AH;
		writeConfigByte = 0BH; writeConfigWord = 0CH; writeConfigDword = 0DH;
		getIrqRoutingOptions = 0EH; setPCIIrq = 0FH;
		
	TYPE
		RouteTable* = POINTER TO RouteTableDesc;
		RouteTableDesc* = RECORD
			busNr*, devNr*, slotNr*: LONGINT;
			linkValIntA*, linkValIntB*, linkValIntC*, linkValIntD*: CHAR;
			IrqBitmapA*, IrqBitmapB*, IrqBitmapC*, IrqBitmapD*: SET;
			next*: RouteTable
		END;
			
		RouteBuffer = RECORD
			BufferSize, SegSelector: INTEGER;
			DataBufferAdr: LONGINT
		END;
		
	VAR
		Bios32Def: RECORD
			sig: ARRAY 4 OF CHAR;
			entry: LONGINT;
			rev, len, chksum: CHAR;
			res: ARRAY 5 OF CHAR;
		END;

		bios32: BOOLEAN;
			
		pci: BOOLEAN;
		pciEntry: LONGINT;

	PROCEDURE -BiosServiceDirectory(sadr, sid, fs: LONGINT; VAR badr, len, entry: LONGINT): CHAR;
	CODE {SYSTEM.i386}
		DB 55H	(* push ebp *)
		DB 8BH, 0ECH	(* mov ebp, esp *)
		DB 66H, 8CH, 0C8H	(* mov ax, cs *)
		DB 50H	(* push eax *)
		DB 8BH, 45H, 14H	(* mov eax, [ebp+20] *)
		DB 8BH, 5DH, 10H	(* mov ebx, [ebp+16] *)
		DB 8BH, 55H, 18H	(* mov edx, [ebp+24] *)
		DB 0FFH, 0D2H	(* call edx *)
(*		DB 0FFH, 55H, 18H	(* call [dword ebp+24] *)  *)
		DB 8BH, 75H, 0CH	(* mov esi, [ebp+12] *)
		DB 89H, 1EH	(* mov [esi], ebx *)
		DB 8BH, 75H, 08H	(* mov esi, [ebp+8] *)
		DB 89H, 0EH	(* mov [esi], ecx *)
		DB 8BH, 75H, 04H	(* mov esi, [ebp+4] *)
		DB 89H, 16H	(* mov [esi], edx *)
		DB 5DH	(*  pop ebp *)
		DB 081H, 0C4H, 018H, 0H, 0H, 0H		(* add esp, 24 *)
	END BiosServiceDirectory;

	PROCEDURE FindBios32Service*(serviceId, serviceFkt: LONGINT; VAR serviceAdr, serviceLen, entryOffset: LONGINT): LONGINT;
	VAR ch: CHAR; res: LONGINT;
	BEGIN
		IF bios32 THEN
			ch := BiosServiceDirectory(Bios32Def.entry, serviceId, serviceFkt, serviceAdr, serviceLen, entryOffset);
			res := ORD(ch);
		ELSE
			res := NoBios32
		END;
		RETURN res
	END FindBios32Service;

	PROCEDURE DetectBios32;
	VAR adr, chksum, i: LONGINT; s: ARRAY 16 OF CHAR;
	BEGIN
		adr := 0E0000H; chksum := 0FFH; 
		REPEAT
			SYSTEM.MOVE(adr, SYSTEM.ADR(s[0]), 16);
			IF (s[0] = "_") & (s[1] = "3") & (s[2] = "2") & (s[3] = "_") THEN
				chksum := 0; i := 0;
				WHILE i < 16 DO
					chksum := chksum + ORD(s[i]);
					IF FALSE & debug THEN Kernel.WriteInt(ORD(s[i]), 1); Kernel.WriteChar(" ") END;
					INC(i)
				END;
				chksum := chksum MOD 256;
			END;
			INC(adr, 16)
		UNTIL (chksum = 0) OR (adr = 0100000H);
		bios32 := chksum = 0;
		IF bios32 THEN
			SYSTEM.MOVE(SYSTEM.ADR(s[0]), SYSTEM.ADR(Bios32Def), 16);
			Kernel.WriteString("PCI Bios32:"); Kernel.WriteHex(adr-16, 9); Kernel.WriteLn;
			IF FALSE THEN
				Kernel.WriteString("  Sig: ");
				Kernel.WriteChar(Bios32Def.sig[0]); Kernel.WriteChar(Bios32Def.sig[1]);
				Kernel.WriteChar(Bios32Def.sig[2]); Kernel.WriteChar(Bios32Def.sig[3]);
				Kernel.WriteString(", Entry: "); Kernel.WriteHex(Bios32Def.entry, 8);
				Kernel.WriteString(", Revision: "); Kernel.WriteInt(ORD(Bios32Def.rev), 1);
				Kernel.WriteString(", Length: "); Kernel.WriteInt(ORD(Bios32Def.len)*16, 1);
				Kernel.WriteString(", Checksum: "); Kernel.WriteInt(ORD(Bios32Def.chksum), 1);
				Kernel.WriteLn
			END
		END
	END DetectBios32;

		PROCEDURE -pcicall(entry:LONGINT; VAR eax,ebx,ecx,edx,esi,edi:LONGINT; VAR eflags: SET);
		CODE {SYSTEM.i386}
			DB 55H				 (* push ebp *)
			DB 8BH, 0ECH				 (* mov ebp, esp *)
			DB 8CH, 0C8H				 (* mov eax, cs *)
			DB 50H				 (* push eax *)
			DB 8BH, 45H, 08H			(* mov eax, [ebp+8] *)
			DB 8BH, 38H				 (* mov edi, [eax] *)
			DB 8BH, 45H, 0CH			(* mov eax, [ebp+12] *)
			DB 8BH, 30H				(* mov esi, [eax] *)
			DB 8BH, 45H, 10H			(* mov eax, [ebp+16] *)
			DB 8BH, 10H				 (* mov edx, [eax] *)
			DB 8BH, 45H, 14H			(* mov eax, [ebp+20] *)
			DB 8BH, 08H				 (* mov ecx, [eax] *)
			DB 8BH, 45H, 18H			(* mov eax, [ebp+24] *)
			DB 8BH, 18H				 (* mov ebx, [eax] *)
			DB 8BH, 45H, 1CH			(* mov eax, [ebp+28] *)
			DB 8BH, 00H				 (* mov eax, [eax] *)
			DB 0FFH, 55H, 20H			(* call [dword ebp+32] *)
			DB 9CH				 (* pushfd *)
			DB 50H				 (* push eax *)
			DB 8BH, 45H, 08H			(* mov eax, [ebp+8] *)
			DB 89H, 38H				 (* mov [eax], edi *)
			DB 8BH, 45H, 0CH			(* mov eax, [ebp+12] *)
			DB 89H, 30H				 (* mov [eax], esi *)
			DB 8BH, 45H, 10H			(* mov eax, [ebp+16] *)
			DB 89H, 10H				 (* mov [eax], edx *)
			DB 8BH, 45H, 14H			(* mov eax, [ebp+20] *)
			DB 89H, 08H				 (* mov [eax], ecx *)
			DB 8BH, 45H, 18H			(* mov eax, [ebp+24] *)
			DB 89H, 18H				 (* mov [eax], ebx *)
			DB 5BH				 (* pop ebx *)
			DB 8BH, 45H, 1CH			(* mov eax, [ebp+28] *)
			DB 89H, 18H				 (* mov [eax], ebx *)
			DB 5BH				 (* pop ebx *)
			DB 8BH, 45H, 04H			(* mov eax, [ebp+4] *)
			DB 89H, 18H				 (* mov [eax], ebx *)
			DB 5DH				 (* pop ebp *)
			DB 081H, 0C4H, 020H, 0H, 0H, 0H				 (* add esp, 32 *)
		END pcicall;

	PROCEDURE OutRegs(eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET);
	BEGIN
		IF debug THEN
			Kernel.WriteString("   eax: "); Kernel.WriteHex(eax, 8); Kernel.WriteLn;
			Kernel.WriteString("   ebx: "); Kernel.WriteHex(ebx, 8); Kernel.WriteLn;
			Kernel.WriteString("   ecx: "); Kernel.WriteHex(ecx, 8); Kernel.WriteLn;
			Kernel.WriteString("   edx: "); Kernel.WriteHex(edx, 8); Kernel.WriteLn;
			Kernel.WriteString("   esi: "); Kernel.WriteHex(esi, 8); Kernel.WriteLn;
			Kernel.WriteString("   edi: "); Kernel.WriteHex(edi, 8); Kernel.WriteLn;
			Kernel.WriteString("   eflags: "); Kernel.WriteHex(SYSTEM.VAL(LONGINT, eflags), 8); Kernel.WriteLn
		END
	END OutRegs;

	PROCEDURE PCIPresent*(VAR version, lastPCIbus, hwMech: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + PCIBiosPresent;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;
			IF (edx = PCIString) & ~(0 IN eflags) & (res = Done) THEN
				version := ebx MOD 10000H;
				lastPCIbus := ecx MOD 100H;
				hwMech := eax MOD 100H
			ELSIF res = 0 THEN res := NoPCI (* ; pci := FALSE (* <- hmm, not sure about that *) *)
			END;
			IF debug THEN
				Kernel.WriteString("PCIPresent:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END PCIPresent;
	
	PROCEDURE FindPCIDevice*(devId, vendId, idx: LONGINT; VAR busNr, devNr, fktNr: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + findPCIDevice;
			ecx := devId; edx := vendId; esi := idx;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF ~(0 IN eflags) & (res = Done) THEN
				busNr := (ebx DIV 100H) MOD 100H;
				devNr := (ebx DIV 8) MOD 20H;
				fktNr := ebx MOD 8
			END;
			IF debug THEN
				Kernel.WriteString("FindPCIDevice:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END FindPCIDevice;

	PROCEDURE FindPCIClassCode*(classCode, idx: LONGINT; VAR busNr, devNr, fktNr: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + findPCIClassCode;
			ecx := classCode; esi := idx;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF ~(0 IN eflags) & (res = Done) THEN
				busNr := (ebx DIV 100H) MOD 100H;
				devNr := (ebx DIV 8) MOD 20H;
				fktNr := ebx MOD 8
			END;
			IF debug THEN
				Kernel.WriteString("FindPCIClassCode:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END FindPCIClassCode;
	
	PROCEDURE GenerateSpecialCycle*(busNr, specCycleData: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + generateSpecialCycle;
			ebx := busNr*100H; edx := specCycleData;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF debug THEN
				Kernel.WriteString("GenerateSpecialCycle:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END GenerateSpecialCycle;
	
	PROCEDURE GetIrqRoutingOptions*(VAR rt: RouteTable; VAR IrqBitmap: SET): LONGINT;
	CONST dbN = 16*8;
	VAR
		res, eax, ebx, ecx, edx, esi, edi, i: LONGINT; eflags: SET;
		rb: RouteBuffer; db: ARRAY dbN OF CHAR;
		last: RouteTable;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + getIrqRoutingOptions;
			rb.BufferSize := dbN; rb.SegSelector := 0; rb.DataBufferAdr := SYSTEM.ADR(db[0]);
			ebx := 0H; edi := SYSTEM.ADR(rb);
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0)));
			ASSERT(res # BufferTooSmall); (* Increase dbN on Trap *)
			IF ~(0 IN eflags) & (res = Done)  THEN
				IrqBitmap := SYSTEM.VAL(SET, ebx);
				NEW(rt); rt.next := NIL; last := rt; i := 0;
				WHILE i < rb.BufferSize DO
					NEW(last.next); last := last.next; last.next := NIL;
					last.busNr := ORD(db[i]); INC(i);
					last.devNr := ORD(db[i]) DIV 8; INC(i);
					last.linkValIntA := db[i]; INC(i);
					last.IrqBitmapA := SYSTEM.VAL(SET, ORD(db[i])+ORD(db[i+1])*100H); INC(i, 2);
					last.linkValIntB := db[i]; INC(i);
					last.IrqBitmapB := SYSTEM.VAL(SET, ORD(db[i])+ORD(db[i+1])*100H); INC(i, 2);
					last.linkValIntC:= db[i]; INC(i);
					last.IrqBitmapC := SYSTEM.VAL(SET, ORD(db[i])+ORD(db[i+1])*100H); INC(i, 2);
					last.linkValIntD := db[i]; INC(i);
					last.IrqBitmapD := SYSTEM.VAL(SET, ORD(db[i])+ORD(db[i+1])*100H); INC(i, 2);
					last.slotNr := ORD(db[i]); INC(i);
					INC(i)	(* reserved byte *)
				END;
				rt := rt.next
			END;
			IF debug THEN
				Kernel.WriteString("GetIrqRoutingOptions:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END GetIrqRoutingOptions;
	
	PROCEDURE SetPCIIrq*(IntPin, IrqNum, busNr, devNr, fktNr: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + setPCIIrq;
			ecx := IrqNum*100H + IntPin; ebx := busNr*100H+devNr*8+fktNr;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF debug THEN
				Kernel.WriteString("SetPCIHwInt:"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END SetPCIIrq;

	PROCEDURE ReadConfig(fkt, busNr, devNr, fktNr, regNr: LONGINT; mask: SET; VAR regVal: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + fkt;
			ebx := busNr*100H+devNr*8+fktNr; edi := regNr;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF ~(0 IN eflags) & (res = Done) THEN
				regVal := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, ecx)*mask)
			END;
			IF debug THEN
				Kernel.WriteString("ReadConfig ("); Kernel.WriteInt(fkt, 1); Kernel.WriteString("):"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END ReadConfig;
	
	PROCEDURE ReadConfigByte*(busNr, devNr, fktNr, regNr: LONGINT; VAR regVal: LONGINT): LONGINT;
	BEGIN
		RETURN ReadConfig(readConfigByte, busNr, devNr, fktNr, regNr, {0..7}, regVal)
	END ReadConfigByte;
	
	PROCEDURE ReadConfigWord*(busNr, devNr, fktNr, regNr: LONGINT; VAR regVal: LONGINT): LONGINT;
	BEGIN
		ASSERT(regNr MOD 2 = 0);
		RETURN ReadConfig(readConfigWord, busNr, devNr, fktNr, regNr, {0..15}, regVal)
	END ReadConfigWord;

	PROCEDURE ReadConfigDword*(busNr, devNr, fktNr, regNr: LONGINT; VAR regVal: LONGINT): LONGINT;
	BEGIN
		ASSERT(regNr MOD 4 = 0);
		RETURN ReadConfig(readConfigDword, busNr, devNr, fktNr, regNr, {0..31}, regVal)
	END ReadConfigDword;
	
	PROCEDURE WriteConfig(fkt, busNr, devNr, fktNr, regNr, regVal: LONGINT): LONGINT;
	VAR res, eax, ebx, ecx, edx, esi, edi: LONGINT; eflags: SET;
	BEGIN
		IF pci THEN
			eax := PCIFunctionId + fkt;
			ebx := busNr*100H+devNr*8+fktNr; ecx := regVal; edi := regNr;
			pcicall(pciEntry, eax, ebx, ecx, edx, esi, edi, eflags);
			res := (eax DIV 100H) MOD 100H;  ASSERT(~((0 IN eflags) & (res=0))); 
			IF debug THEN
				Kernel.WriteString("WriteConfig ("); Kernel.WriteInt(fkt, 1); Kernel.WriteString("):"); Kernel.WriteLn;
				OutRegs(eax, ebx, ecx, edx, esi, edi, eflags)
			END
		ELSE
			res := NoPCI
		END;
		RETURN res
	END WriteConfig;

	PROCEDURE WriteConfigByte*(busNr, devNr, fktNr, regNr, regVal: LONGINT): LONGINT;
	BEGIN
		RETURN WriteConfig(writeConfigByte, busNr, devNr, fktNr, regNr, regVal)
	END WriteConfigByte;
	
	PROCEDURE WriteConfigWord*(busNr, devNr, fktNr, regNr, regVal: LONGINT): LONGINT;
	BEGIN
		ASSERT(regNr MOD 2 = 0);
		RETURN WriteConfig(writeConfigWord, busNr, devNr, fktNr, regNr, regVal)
	END WriteConfigWord;
	
	PROCEDURE WriteConfigDword*(busNr, devNr, fktNr, regNr, regVal: LONGINT): LONGINT;
	BEGIN
		ASSERT(regNr MOD 4 = 0);
		RETURN WriteConfig(writeConfigDword, busNr, devNr, fktNr, regNr, regVal)
	END WriteConfigDword;
	
	PROCEDURE DetectPCI;
	VAR res, adr, len, entry: LONGINT;
	BEGIN
		res := FindBios32Service(PCIServiceId, 0, adr, len, entry);
		pci := res = Done;
		IF pci THEN
			pciEntry := adr+entry
		END
	END DetectPCI;

	PROCEDURE Init;
	BEGIN
		DetectPCI
	END Init;
	
BEGIN
	DetectBios32;
	Init
END PCI.

System.Free PCI ~
