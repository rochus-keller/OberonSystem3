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

(* Author Reto Strobl 
 * Summer '98
 * first beta Release: 28. Juli '98
 * Co-assistance: Jaco Geldenhuys
 * Supervisior: Pieter Muller
 *************************************)

(* beta *)

MODULE Net3Com905B;	(* Reto Strobl *)

	IMPORT SYSTEM, PCI, Kernel, Texts, Oberon, NetBase;

	CONST
	(*diverse Constanten*)
		senddebug = FALSE;
		debug = FALSE;
		IIIComVendorId = 10B7H;
		DevIDs = 4; 	(*Anzahl versch. Karten*)
		devlistdebug = FALSE;
		window0 =  800H;	
		MaxPackets = 10;
		MaxPacketSize = 1514;
		PHY = 18H; (*11000B*)
		
		DPDBuffer = 8;
	(* MII Constants *)
		MIIShiftClk = 01H;
		MIIDirWrite = 04H;
		MIIDataWrite0 = 04H;
		MIIDataWrite1 = 06H;
		MIIDataRead = 02H;
		MIIEnbIn = 0;
	
	(*Registers*)
		TxStatus = 1BH;
		UpListPtr = 38H;		
		DownListPtr = 24H;
		CommReg = 0EH;
		IntStatus = 0EH;
		PhysicalMgmt = 8;
		InternalConfig = 0;
		MacControl = 6;
		MediaOption = 8;		
		MediaStatus =  0AH;
		DmaCtr = 20H;
	(*command Register commands (without parameters) *)
	(* Falls ein LI an der Constante haengt, ist ein Typecast mit SYSTEM.VAL auf Integer notwendig! *)
		B0 = 1; B1=2; B2=4; B3=8; B4=16; B5=32; B6=64; B7=128; B8=256;
		B9=200H; B10=400H; B11=800H; B12=1000H; B13=2000H; B14=4000H; B15=8000H;
		
		RxThresh = 8800H;
		RxReset = 2800H;
		TxReset = 5800H;
		UpUnstall = 3001H;
		DnStall = 3002H;
		DnUnstall = 3003H;
		RxFilterLI = 8000H;
		SetIndicationEnable = 7800H;
		EnableDcConverter = 1000H;
		DisableDcConverter = 0D800H;
		RxEnable = 2000H;
		TxEnable = 4800H;
		AcknowledgeInterrupt = 6800H;
		SetInterruptEnable = 7000H;
		
	(*EEprom comands *)
		EEread = 80H;
		EEwrite = 40H;
		
	TYPE
		DevicePtr = POINTER TO DeviceDescc;
		DeviceDescc = RECORD
			devId, vendId, cmd, status, revId, classCode, CLS, latTimer, hdrType,
			IoBaseAdr, MemBaseAdr, CIS,
			subId, subVenId, baseAdrROM, intL, intP, minGnt, maxLat: LONGINT;
			devIdx, busNr, devNr, fktNr: LONGINT;
			memaccess: BOOLEAN;
		END;	
		
		MediaList = POINTER TO MediaItem;
		MediaItem = RECORD
			type: INTEGER;
			xcvr: SET;
			next: MediaList;
			name: ARRAY 64 OF CHAR
		END;
		
		DPD = POINTER TO DPDDesc;
		DPDDesc = RECORD
			DnNextPtr: LONGINT;
		    FrameStartHeader : LONGINT;
		    HeaderDnFragAdr, HeaderDnFragLen, 
		    DataDnFragAdr, DataDnFragLen : LONGINT;
		END;
		
		UPD = POINTER TO UPDDesc;
		UPDDesc = RECORD
			UpNextPtr : UPD;
			UpPktStatus : SET;
			DataUpFragAddr, DataUpFragLen : LONGINT;
		END;
		
		Device = POINTER TO DeviceDesc;
		DeviceDesc = RECORD(NetBase.DeviceDesc)
		END;
			
		Adr = ARRAY 6 OF CHAR;	
		
		PacketData = ARRAY MaxPacketSize OF SYSTEM.BYTE;
		PacketBuffer = ARRAY  MaxPackets OF PacketData;

		HeaderDesc = RECORD
			dst, src: Adr;		(* 0, 6 *)
			type: INTEGER; 		(* 12 *)
		END;
		
		Data = POINTER TO DataDesc;
		DataDesc = RECORD
			data: ARRAY 1500 OF SYSTEM.BYTE	(* Note: SendPacket may access data[1500] & data[1501] *)
		END;
	
	VAR
		packetbuffer : PacketBuffer;
		upd : UPD;
		dpd : ARRAY DPDBuffer OF DPD;
		curdpd: LONGINT;
		Devs: ARRAY DevIDs OF DevicePtr;
		IDs: ARRAY DevIDs OF LONGINT;
		DevNum : LONGINT;
		Ints: SET;	(* Interrupts *)
		W: Texts.Writer;
		T: Texts.Text;
		BaseAdr : LONGINT;
		dev : Device;
		sendhdr : HeaderDesc;
		intCounter: LONGINT;
		Interrupt : LONGINT;
		UpListRoot : UPD;

	PROCEDURE LogInt(i: LONGINT);
	BEGIN
		Texts.WriteInt(W, i, 1)
	END LogInt;

	PROCEDURE InitIDs;
	BEGIN
		IDs[0] := 9055H; IDs[1] := 9056H; IDs[2] := 9004H; IDs[3] := 9005H
	END InitIDs;

	PROCEDURE PCIFindSYMDevice(Dev: DevicePtr): LONGINT;
	VAR res, res1, regVal: LONGINT;
	BEGIN
		(* hole busNr, devNr und fktNr *)
		res := PCI.FindPCIDevice(Dev.devId, IIIComVendorId, Dev.devIdx, Dev.busNr, Dev.devNr, Dev.fktNr);
		IF devlistdebug THEN
			Texts.WriteString(W, "PCIFindSYMDevice"); Texts.WriteLn(W);
			Texts.WriteString(W, "   Device: "); Texts.WriteHex(W, Dev.devId); Texts.WriteLn(W);
			Texts.WriteString(W, "   Vendor: "); Texts.WriteHex(W, IIIComVendorId); Texts.WriteLn(W);
			Texts.WriteString(W, "   Index: "); LogInt(Dev.devIdx); Texts.WriteLn(W);
			Texts.WriteString(W, "   res: "); Texts.WriteHex(W, res); Texts.WriteLn(W);
			Texts.Append(T, W.buf);
		END;
		
		(* initalisiere die uebrigen Felder des Devices *)
		IF res = PCI.Done THEN
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CmdReg, regVal); ASSERT(res1 = PCI.Done, 100);
			Dev.cmd := regVal MOD 10000H; Dev.status := regVal DIV 10000H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.RevIdReg, regVal); ASSERT(res1 = PCI.Done, 101);
			Dev.revId := regVal MOD 100H; Dev.classCode := regVal DIV 100H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CLSReg, regVal); ASSERT(res1 = PCI.Done, 102);
			Dev.CLS := regVal MOD 100H; Dev.latTimer := (regVal DIV 100H) MOD 100H;
			Dev.hdrType := (regVal DIV 10000H) MOD 100H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr0Reg, Dev.IoBaseAdr); ASSERT(res1 = PCI.Done, 110);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.Adr1Reg, Dev.MemBaseAdr); ASSERT(res1 = PCI.Done, 111);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.CISReg, Dev.CIS); ASSERT(res1 = PCI.Done, 103);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.SubvReg, regVal); ASSERT(res1 = PCI.Done, 104);
			Dev.subVenId := regVal MOD 10000H; Dev.subId := regVal DIV 10000H;
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.ROMReg, Dev.baseAdrROM); ASSERT(res1 = PCI.Done, 105);
			res1 := PCI.ReadConfigDword(Dev.busNr, Dev.devNr, Dev.fktNr, PCI.IntlReg, regVal); ASSERT(res1 = PCI.Done, 106);
			Dev.intL := regVal MOD 100H; Dev.intP := (regVal DIV 100H) MOD 100H;
			Dev.minGnt := (regVal DIV 10000H) MOD 100H; Dev.maxLat := (regVal DIV 1000000H);
			Dev.memaccess := FALSE;
			INCL(Ints, Dev.intL);	(* Ints = set der Interrupts *)
			Interrupt := Dev.intL;
			
		END;
		RETURN res
	END PCIFindSYMDevice;

	(* Findet alle Devices und speichert sie im Array Devices ab *)
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
	
(* Printet alle gefundenen Devices aus inkl Details *)
	PROCEDURE ShowDeviceList(VAR Devices: ARRAY OF DevicePtr; MaxDev: LONGINT);
	VAR i: LONGINT; d: DevicePtr;
	BEGIN
		Texts.WriteLn(W); Texts.WriteString(W, "Show Device List and Details : "); Texts.WriteLn(W);
		i := 0;
		WHILE i < MaxDev DO
			d := Devices[i];
			Texts.WriteString(W, "Device "); LogInt(i); Texts.WriteLn(W);
			Texts.WriteString(W, "   busNr: "); LogInt(d.busNr); Texts.WriteLn(W);
			Texts.WriteString(W, "   devNr: "); LogInt(d.devNr); Texts.WriteLn(W);
			Texts.WriteString(W, "   fktNr: "); LogInt(d.fktNr); Texts.WriteLn(W);
			Texts.WriteString(W, "   devIdx: "); LogInt(d.devIdx); Texts.WriteLn(W);
			Texts.WriteString(W, "   vendId: "); Texts.WriteHex(W,d.vendId); Texts.WriteLn(W);
			Texts.WriteString(W, "   devId: "); Texts.WriteHex(W, d.devId); Texts.WriteLn(W);
			Texts.WriteString(W, "   cmd: "); LogInt(d.cmd); Texts.WriteLn(W);
			Texts.WriteString(W, "   status: "); LogInt(d.status); Texts.WriteLn(W);
			Texts.WriteString(W, "   revId: "); LogInt(d.revId); Texts.WriteLn(W);
			Texts.WriteString(W, "   classCode: "); LogInt(d.classCode); Texts.WriteLn(W);
			Texts.WriteString(W, "   CLS: "); LogInt(d.CLS); Texts.WriteLn(W);
			Texts.WriteString(W, "   latTimer: "); LogInt(d.latTimer); Texts.WriteLn(W);
			Texts.WriteString(W, "   hdrType: "); LogInt(d.hdrType); Texts.WriteLn(W);
			Texts.WriteString(W, "   IoBaseAdr: "); LogInt(d.IoBaseAdr); Texts.WriteLn(W);
			Texts.WriteString(W, "   MemBaseAdr: "); LogInt(d.MemBaseAdr); Texts.WriteLn(W);
			Texts.WriteString(W, "   CIS: "); LogInt(d.CIS); Texts.WriteLn(W);
			Texts.WriteString(W, "   subId: "); LogInt(d.subId); Texts.WriteLn(W);
			Texts.WriteString(W, "   subVenId: "); LogInt(d.subVenId); Texts.WriteLn(W);
			Texts.WriteString(W, "   baseAdrROM: "); LogInt(d.baseAdrROM); Texts.WriteLn(W);
			Texts.WriteString(W, "   Int Line: "); LogInt(d.intL); Texts.WriteLn(W);
			Texts.WriteString(W, "   Int Pin: "); LogInt(d.intP); Texts.WriteLn(W);
			Texts.WriteString(W, "   Min Gnt: "); LogInt(d.minGnt); Texts.WriteLn(W);
			Texts.WriteString(W, "   Max Lat: "); LogInt(d.maxLat); Texts.WriteLn(W);
			Texts.Append(T, W.buf);
			INC(i)
		END;
	END ShowDeviceList;
	
	(* Copy - Copy size bytes from source to dest.  (No overlap allowed) *)

PROCEDURE Copy(source, dest, size: LONGINT);
CODE {SYSTEM.i386}
	MOV ESI, source[EBP]
	MOV EDI, dest[EBP]
	MOV ECX, size[EBP]
	CLD
	CMP ECX, 8
	JB bytemove
	XOR EAX, EAX
	SHRD EAX, ESI, 2
	JZ copyd
	TEST EDI, 3
	JZ copyd
	SHRD EAX, EDI, 2
	SHR EAX, 28
	CMP AL, 10
	JZ mov2
	CMP AL, 5
	JZ mov3
	NOT AL
	AND AL, 5
	JNZ copyd
	MOVSB
	DEC ECX
	JMP copyd
mov3:
	MOVSB
	DEC ECX
mov2:
	MOVSW
	SUB ECX, 2
copyd:
	SHRD EAX, ECX, 2
	SHR ECX, 2
	REP MOVSD
	SHLD ECX, EAX, 2
bytemove:
	REP MOVSB
END Copy;

(* Avail - Return TRUE iff a packet is available *)

PROCEDURE Avail(dev: NetBase.Device): BOOLEAN;
BEGIN
	RETURN 15 IN UpListRoot.UpPktStatus
END Avail;

PROCEDURE SwitchToWindow(window : INTEGER);
VAR RegWindow : INTEGER;
BEGIN
	RegWindow :=  window0 + window;
	SYSTEM.PORTOUT(BaseAdr+CommReg, RegWindow);
END SwitchToWindow;


(* liest die OEM Node Adresse aus dem EEprom bei window 0 offset 0a, 0b, 0c und schreibt diese
	dann ins StationAdress Register im Window 2 offset 0, 2, 4 *)
PROCEDURE InitStationAdress();
VAR adr, i, cmreg : INTEGER; of, word : ARRAY 3 OF INTEGER; val : SET; 
BEGIN
	of[0] := 0AH; of[1] := 0BH; of[2] := 0CH;
	SwitchToWindow(0);
	FOR i := 0 TO 2 DO
		(* schreibe lesebefehl ins EEprom Comm. Reg fuer word0 *)
		adr := SYSTEM.VAL(INTEGER, EEread) + of[i];
		SYSTEM.PORTOUT(BaseAdr+0AH, SYSTEM.VAL(INTEGER,adr)); 
		(*  warte bis lesebereit *)
		val :=  {15};	(* eeprom busy *)
		WHILE (15 IN val)  DO
			SYSTEM.PORTIN(BaseAdr+0AH, cmreg); 
			val :=  SYSTEM.VAL(SET, cmreg);
		END;
		(* lese word0 aus EEprom DataReg *)
		SYSTEM.PORTIN(BaseAdr+0CH, word[i]);
	END;
	SwitchToWindow(2);
	(* schreibe wort 0, wort1, wort2 an die entsprechenden offsets *)
	(* initialisiere globale Variable sendhdr.src[.] *)
	sendhdr.src[0] := SYSTEM.VAL(CHAR, word[0] DIV 256);
	sendhdr.src[1] := SYSTEM.VAL(CHAR, word[0]);
	sendhdr.src[2] := SYSTEM.VAL(CHAR, word[1] DIV 256);
	sendhdr.src[3] := SYSTEM.VAL(CHAR, word[1]);		
	sendhdr.src[4] := SYSTEM.VAL(CHAR, word[2] DIV 256);
	sendhdr.src[5] := SYSTEM.VAL(CHAR, word[2]);
	FOR i := 0 TO 5 DO
		SYSTEM.PORTOUT(BaseAdr+i, sendhdr.src[i])
	END;
	IF debug THEN
		Texts.WriteString(W, "KartenAdresse: ");
		FOR i := 0 TO 5 DO
			Texts.WriteHex(W, ORD(sendhdr.src[i]))
		END;
		Texts.WriteLn(W);
		Texts.WriteString(W, " word0 "); Texts.WriteHex(W, word[0]); Texts.Append(T, W.buf);
		Texts.WriteString(W, " word1 "); Texts.WriteHex(W, word[1]); Texts.Append(T, W.buf);
		Texts.WriteString(W, " word2 "); Texts.WriteHex(W, word[2]); Texts.Append(T, W.buf); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END InitStationAdress;
	
PROCEDURE *Cleanup;
BEGIN
	Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+SHORT(Interrupt));
END Cleanup;

PROCEDURE InitMediaList(VAR port: MediaList);
VAR d: MediaList;
BEGIN
	port.type := 3; port.name := "10baseT"; port.xcvr := {}; NEW(port.next); d:= port.next;
	d.type:= 2; d.name:= "100baseFx"; d.xcvr := {22,20}; NEW(d.next); d:= d.next;
	d.type:= 6; d.name:= "MII"; d.xcvr := {22,21}; NEW(d.next); d:= d.next;
	d.type:= 1; d.name:= "100baseTx"; d.xcvr := {22}; NEW(d.next); d:= d.next;
	d.type:= 4; d.name:= "10base2 (coax)"; d.xcvr := {20,21}; NEW(d.next); d:= d.next;	
	d.type:= 5; d.name:= "AUI"; d.xcvr := {20}; NEW(d.next); d:= d.next;
	d.type:= 10; d.name:= "------------Kein Media Type "; d.xcvr := {23}; 
END InitMediaList;

PROCEDURE ConfigNextValidMedia(VAR tryPort: MediaList; VAR link: INTEGER);
VAR intConfig, s: SET; mediaOptions: INTEGER;
BEGIN
	SwitchToWindow(3);
	SYSTEM.PORTIN(BaseAdr+MediaOption, mediaOptions);
	tryPort := tryPort.next;
	WHILE ~(tryPort=NIL)&~(tryPort.type IN SYSTEM.VAL(SET, mediaOptions)) DO
		tryPort := tryPort.next
	END;					
	IF tryPort=NIL THEN link := 10
	ELSE
		IF debug THEN
			Texts.WriteLn(W);
			Texts.WriteString(W,"This Port not active; try next one   :  ");
			Texts.WriteString(W, tryPort.name);
			Texts.WriteLn(W)
		END;
		SwitchToWindow(3);
		SYSTEM.PORTIN(BaseAdr+InternalConfig, intConfig);
		intConfig := intConfig-{20,21,22,23};
		SYSTEM.PORTOUT(BaseAdr+InternalConfig, intConfig + tryPort.xcvr);
		SYSTEM.PORTOUT(BaseAdr + CommReg, TxReset); 
		REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s);
		SYSTEM.PORTOUT(BaseAdr + CommReg, RxReset);
		REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s)
	END
END ConfigNextValidMedia;
	
PROCEDURE TestPacket(): BOOLEAN;
BEGIN
END TestPacket;
	
PROCEDURE InitDriver;
VAR 
	res: CHAR;  
	i, link, ic0, ic1, info1, cmreg, adr, mediaStatus, mediaOptions: INTEGER; 
	s, intConfig,val : SET; 
	dummy, res1, version, lastPCIbus, hwMech, dev, t: LONGINT;
	dummyb: SYSTEM.BYTE;
	tryPort: MediaList;
	found, stillTrying: BOOLEAN;
BEGIN
	intCounter := 0;
	DevNum := 0; ASSERT(Ints = {});
	res1 := PCI.PCIPresent(version, lastPCIbus, hwMech);
	IF res1 = PCI.Done THEN
		DevNum := BuildDeviceList(Devs, DevIDs);
		IF devlistdebug THEN ShowDeviceList(Devs, DevNum) END;
		BaseAdr := Devs[0].IoBaseAdr-1; (*entferne letztes bit das nur zur identifikation des IoBaseAdr. dient *)
		IF debug THEN
			Texts.WriteString(W, "Base Address: ");
			Texts.WriteHex(W, BaseAdr);
			Texts.WriteLn(W);
			Texts.WriteString(W, "DevId: ");
			Texts.WriteHex(W, Devs[0].devId);
			Texts.WriteLn(W);
			SwitchToWindow(4);			
			SYSTEM.PORTIN(BaseAdr+0AH, s);
			Texts.WriteString(W, "MediaStatus: ");
			Texts.WriteSet(W, s);
			Texts.WriteLn(W);
			Dump;
			Texts.WriteLn(W); 
		END;
		(* First select the Media Port *)
		NEW(tryPort);
		InitMediaList(tryPort);
		SwitchToWindow(3);
		SYSTEM.PORTIN(BaseAdr+InternalConfig, intConfig);
		IF 24 IN intConfig THEN (* Autonegotiate; start with 100BaseTx IF available, else go through the medialist*)
			SYSTEM.PORTIN(BaseAdr+MediaOption, mediaOptions);
			WHILE ~(tryPort=NIL)&~(tryPort.type IN SYSTEM.VAL(SET, mediaOptions)) DO
				tryPort := tryPort.next
			END;
			(* try first this port... *)
			SYSTEM.PORTOUT(BaseAdr+InternalConfig, intConfig-{20,21,22,23}+tryPort.xcvr);
			IF debug THEN 
				Texts.WriteString(W, "Inital Media type that we try is... ");
				Texts.WriteString(W, tryPort.name);
				Texts.WriteLn(W)
			END;
			found := FALSE; 
			(* TxReset and RxReset*)
			SYSTEM.PORTOUT(BaseAdr + CommReg, TxReset); 
			REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s);
			SYSTEM.PORTOUT(BaseAdr + CommReg, RxReset);
			REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s);			
		ELSE (* use default media; selected in the BIOS ROM and automatically copied into 
					the NIC's internal Config Register. => Do nothing... *)
			found := TRUE 
		END;
		
		REPEAT
			(* set the duplexmode if required *)
			SwitchToWindow(0);
			adr := SYSTEM.VAL(INTEGER, EEread) + 0DH;
			SYSTEM.PORTOUT(BaseAdr+0AH, SYSTEM.VAL(INTEGER,adr)); 
			val :=  {15};	(* eeprom busy *)
			WHILE (15 IN val)  DO
				SYSTEM.PORTIN(BaseAdr+0AH, cmreg); 
				val :=  SYSTEM.VAL(SET, cmreg);
			END;
			SYSTEM.PORTIN(BaseAdr+0CH, info1);
			IF 15 IN SYSTEM.VAL(SET, info1) THEN
				SYSTEM.PORTOUT(BaseAdr+MacControl, B5)
			ELSE
				SYSTEM.PORTOUT(BaseAdr+MacControl, 0)
			END;
			(* TxReset and RxReset*)
			SYSTEM.PORTOUT(BaseAdr + CommReg, TxReset); 
			REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s);
			SYSTEM.PORTOUT(BaseAdr + CommReg, RxReset);
			REPEAT SYSTEM.PORTIN(BaseAdr+CommReg, s); UNTIL ~(12 IN s);
			IF debug THEN	
				SYSTEM.PORTIN(BaseAdr + DownListPtr, dummy);
				Texts.WriteString(W, "DnListPtr after TxReset and RxReste: ");
				Texts.WriteHex(W, dummy); Texts.WriteLn(W); 
			END;
			(* mit SetInterruptEnable koennen nur diese Bits gesetzt werden, welche mit Set Indication Enable 
				Enabled worden sind. Ausser interruptLatch; dies ist immer enabled *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SetIndicationEnable);	
		(*	Kernel.InstallIP(InterruptHandler, Kernel.IRQ+SHORT(Interrupt));
			Kernel.InstallTermHandler(Cleanup);	*)
			InitStationAdress();
			(* enable the 10Base2 converter if Media is 10base2 *)
			SwitchToWindow(3);
			SYSTEM.PORTIN(BaseAdr+InternalConfig, intConfig);
			IF  (20 IN intConfig) &( 21 IN intConfig) THEN 
				SYSTEM.PORTOUT(BaseAdr + CommReg, EnableDcConverter)
			END;		
			(* set Link beat enable *)
			SwitchToWindow(4);
			SYSTEM.PORTIN(BaseAdr+MediaStatus, mediaStatus);
			val := SYSTEM.VAL(SET, mediaStatus) -{3,6,7};
			val := val + {7}; (* haengt ab vom media type => noch eine tabelle aufbauen!!*)
			SYSTEM.PORTOUT(BaseAdr+MediaStatus, SYSTEM.VAL(INTEGER, val));			
			(* clear all statistics by reading *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER,B15+B13+B12)); (* StatsDisable *)
			SwitchToWindow(6);
			FOR i:=0 TO 9 DO
				SYSTEM.PORTIN(BaseAdr+i, dummyb)
			END;
			SYSTEM.PORTIN(BaseAdr+10, i);
			SYSTEM.PORTIN(BaseAdr+12, i);
			SwitchToWindow(4);
			SYSTEM.PORTIN(BaseAdr+12, dummyb);
			(* for normal use switch to window 7*)
			SwitchToWindow(7);
			 (*  Bus Maser Procedures .. *)
			 SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER, RxThresh)+1500 DIV 4);
			 SYSTEM.PORTOUT(BaseAdr+DmaCtr, SYSTEM.VAL(LONGINT, 20H)); (* upRxEarlyEnable *)
			(* Set the UpListPtr auf die UpListRoot und starte Upload Engine *)
			SYSTEM.PORTOUT(BaseAdr+UpListPtr, SYSTEM.ADR(UpListRoot^));	 
			SYSTEM.PORTOUT(BaseAdr+2FH, CHR(1536 DIV 256)); (* for older NICS... *)
			SYSTEM.PORTOUT(BaseAdr+DownListPtr, SYSTEM.VAL(LONGINT, 0)); 
			(* Set Receive filter: individual, broadcast, multicast *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER,RxFilterLI+B0+B1+B2)); 	
			SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER, B15+B13+B11)); (* enable Statistics *)
			(* TxEnable and RxEnable *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, RxEnable); (*Rx Enable*)
			SYSTEM.PORTOUT(BaseAdr+CommReg, TxEnable); (* TxEnable*)
			(* allow Statusbits to be seen *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SetIndicationEnable+7FEH (*B7+B6+B2+B1*));
			SYSTEM.PORTOUT(BaseAdr+CommReg, AcknowledgeInterrupt+B0+B5+B6+B9+B10); 
			(* war: 6868H IntLatch, TxAvailable?, Rxearly, Intreq ->see IntStatus Reg (s. 8-3)*)
			(* SetinterruptEnable legt fest, welche interruptBits einen Interrupt generieren koennen
				!Wichtig!: Sie muessen zuerst mit SetIndicationEnable enabled worden sein! *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SetInterruptEnable );
			(* Set Interrupts enable: rxComplete, intRequest*)		
			(* check if the right port was selected; if not, try another one and wait again... *)
			IF (~found) THEN
				SwitchToWindow(3);
				SYSTEM.PORTIN(BaseAdr+MediaOption, mediaOptions);
				SwitchToWindow(4); 
				IF (tryPort.name = "100baseTx") OR (tryPort.name = "10baseT") OR (tryPort.name = "100baseFx") THEN
					t := Kernel.GetTimer();
					REPEAT SYSTEM.PORTIN(BaseAdr+MediaStatus, i); 
					UNTIL (Kernel.GetTimer()-t > 2*Kernel.TimeUnit) OR (11 IN SYSTEM.VAL(SET,i));
					IF 11 IN SYSTEM.VAL(SET, i) THEN
							found := TRUE; link := tryPort.type 
					ELSE
						ConfigNextValidMedia(tryPort, link);
					END
				ELSIF (tryPort.name = "AUI") OR (tryPort.name = "10base2") THEN
					FOR i:= 1 TO 3 DO
						IF TestPacket() THEN
							found := TRUE; link := tryPort.type
						END
					END;
					IF ~found THEN 
						IF (tryPort.name = "10base2")  THEN
							SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER,DisableDcConverter)) 
						END;
						ConfigNextValidMedia(tryPort, link)
					END
				ELSE (* MII ... *)						
				END
			END;
		(*	IF (~found)&(tryPort#NIL) THEN
				Cleanup
			END *)
		UNTIL found OR (tryPort = NIL);
		IF debug THEN
			Texts.WriteLn(W);
			IF tryPort=NIL THEN Texts.WriteString(W, "keinen Port ")
			ELSE Texts.WriteString(W, tryPort.name)
			END;
			Texts.WriteString(W, " erkannt");	
			Texts.WriteLn(W)
		END;
		SYSTEM.PORTOUT(BaseAdr+CommReg, UpUnstall);
		IF debug THEN 
			SwitchToWindow(3);
			Texts.WriteLn(W);
			Texts.WriteString(W, "Internal Config ist: ");
			SYSTEM.PORTIN(BaseAdr+InternalConfig, intConfig);
			Texts.WriteSet(W, intConfig);
			Texts.Append(T, W.buf);
			SwitchToWindow(4);
			SYSTEM.PORTIN(BaseAdr+MediaStatus, i);
			Texts.WriteLn(W);
			Texts.WriteString(W, "MediaStatus  ");
			Texts.WriteHex(W,  i);
			Texts.WriteLn(W);
		END;
	END;	(* if PCI.Done ende *)
	IF debug THEN 
		Texts.Append(T, W.buf);
	END;
END InitDriver;		
	
PROCEDURE Send(dev: NetBase.Device; prno: INTEGER; VAR dest: ARRAY OF SYSTEM.BYTE; item: NetBase.Item);
VAR dummy, DnListPtr : LONGINT; s : SET; int, i : INTEGER; dummyb: SYSTEM.BYTE; txStatus: CHAR;
BEGIN
	IF (item.len < 0) OR (item.len > 1500) THEN  RETURN END;	(* packet too big *)
		
	SYSTEM.PORTOUT(BaseAdr + CommReg, SYSTEM.VAL(INTEGER,DnStall));
	REPEAT (*wait for completition of Stall*)
		SYSTEM.PORTIN(BaseAdr+IntStatus, int)	
	UNTIL ~(12 IN SYSTEM.VAL(SET, LONG(int)));
	SYSTEM.PORTIN(BaseAdr+DownListPtr, DnListPtr);
	IF DnListPtr # 0 THEN
		IF DnListPtr = SYSTEM.ADR(dpd[(curdpd + 1) MOD DPDBuffer]^) THEN	(* buffer is full *)
			SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER,DnUnstall)); (* unstall the downloadengine*)
			REPEAT
				SYSTEM.PORTIN(BaseAdr+DownListPtr, DnListPtr);
				SYSTEM.PORTIN(BaseAdr+TxStatus, txStatus);
				WHILE 7 IN SYSTEM.VAL(SET, txStatus) DO
					IF 3 IN SYSTEM.VAL(SET, txStatus) THEN
						SYSTEM.PORTOUT(BaseAdr+CommReg, TxEnable)
					END;
					SYSTEM.PORTOUT(BaseAdr+TxStatus, txStatus);
					SYSTEM.PORTIN(BaseAdr+TxStatus, txStatus)
				END
			UNTIL DnListPtr # SYSTEM.ADR(dpd[(curdpd + 1) MOD DPDBuffer]^);
			SYSTEM.PORTOUT(BaseAdr + CommReg, SYSTEM.VAL(INTEGER,DnStall));
		END;
		dpd[curdpd].DnNextPtr := SYSTEM.ADR(dpd[(curdpd + 1) MOD DPDBuffer]^);
		curdpd := (curdpd + 1) MOD DPDBuffer;
	END;
	
	(* build the sendheader (destadr, sendadr, ..*)
	SYSTEM.MOVE(SYSTEM.ADR(dest[0]), SYSTEM.ADR(sendhdr.dst[0]), 6);	(* set up sendhdr *)
	sendhdr.type := SYSTEM.ROT(prno, 8);	(* sendhdr.src remains our address *)
	(* build the DPD *)
	dpd[curdpd].DnNextPtr := 0;
	dpd[curdpd].FrameStartHeader :=  14+item.len + 80000000H; (* type 0 *)
	dpd[curdpd].HeaderDnFragAdr := SYSTEM.ADR(sendhdr);
	dpd[curdpd].DataDnFragAdr := SYSTEM.ADR(item.data[item.ofs]); (*adresse des ersten datacharacters *)
	dpd[curdpd].HeaderDnFragLen := 14 ;
	dpd[curdpd].DataDnFragLen := item.len + 80000000H; (* letztes bit muss gesetzt sein, damit download engine stoppt *)
	
   IF senddebug THEN 	
		Texts.WriteString(W, "DownListPtr direkt vor dem senden des pakets..: ");
		SYSTEM.PORTIN(BaseAdr+DownListPtr, dummy);
		Texts.WriteHex(W, dummy); Texts.WriteLn(W);
	END;

	IF DnListPtr = 0 THEN
		SYSTEM.PORTOUT(BaseAdr+DownListPtr, SYSTEM.ADR(dpd[curdpd]^)); (* send the packet*)
		IF senddebug THEN 	
			Texts.WriteString(W, "DownListPtr direkt nach senden des pakets..: ");
			SYSTEM.PORTIN(BaseAdr+DownListPtr, dummy);
			Texts.WriteHex(W, dummy); Texts.WriteLn(W);
		END;
	END;
	SYSTEM.PORTOUT(BaseAdr+CommReg, SYSTEM.VAL(INTEGER,DnUnstall)); (* unstall the downloadengine*)

END Send;

(* ReceivePacket - Remove a packet from the input buffer *)

PROCEDURE Receive(dev: NetBase.Device;  VAR prno: INTEGER; VAR src: ARRAY OF SYSTEM.BYTE; VAR item: NetBase.Item);
VAR  prno0, dlen: INTEGER;
BEGIN
	IF 15 IN UpListRoot.UpPktStatus THEN																			(* There is a uploadet Packet availible *)
		dlen := SHORT(SYSTEM.VAL(LONGINT, UpListRoot.UpPktStatus) MOD 2000H);
		SYSTEM.MOVE(UpListRoot.DataUpFragAddr+6, SYSTEM.ADR(src[0]), 6);					(* source address *)
		SYSTEM.GET(UpListRoot.DataUpFragAddr+12, prno0); 												(* get protocoll number *)
		Copy(UpListRoot.DataUpFragAddr+14, SYSTEM.ADR(item.data[0]), dlen  - 14 (*Ethernet Header*) );
		prno := SYSTEM.ROT(prno0, 8);	(* convert little to big Endian *)
		item.ofs := 0; 
		item.len := dlen-14;
		UpListRoot.UpPktStatus := {};
		UpListRoot := UpListRoot.UpNextPtr;
		SYSTEM.PORTOUT(BaseAdr+CommReg, UpUnstall);
	ELSE
		HALT(100); (*kein Packet availible *)
	END
END Receive;


(* InterruptHandler - Handle interrupts *)

PROCEDURE InterruptHandler;
VAR interStatus: INTEGER; txStatus: CHAR;
BEGIN
	INC(intCounter);
	SYSTEM.PORTIN(BaseAdr+IntStatus, interStatus);
	SYSTEM.PORTIN(BaseAdr+TxStatus, txStatus);
	SYSTEM.PORTOUT(BaseAdr+TxStatus, txStatus)
END InterruptHandler;

(* UpListRoot zeigt auf einen Ringbuffer mit MaxPackets UPD Paketen. *)
PROCEDURE InitUPDList;
VAR upd, UpListLast : UPD; i : INTEGER;
BEGIN
	UpListRoot := NIL;
	FOR i := 0 TO MaxPackets-1 DO
		NEW(upd);
		upd.UpPktStatus := {};
		upd.DataUpFragAddr := SYSTEM.ADR(packetbuffer[i][0]);
		upd.DataUpFragLen := MaxPacketSize;
		upd.UpNextPtr := NIL;
		IF UpListLast = NIL THEN
			UpListRoot := upd;
		ELSE
			UpListLast.UpNextPtr := upd;
		END;
		UpListLast := upd;
	END;
	UpListLast.UpNextPtr := UpListRoot;
END InitUPDList;

PROCEDURE InitDPD;
	VAR i: LONGINT;
BEGIN
	curdpd := 0;
	FOR i:= 0 TO DPDBuffer-1 DO	NEW(dpd[i])	END
END InitDPD;

(** InstallDevice - Command to install ethernet device.  Device name is parameter. *)

PROCEDURE InstallDevice*;	(* devname *)
VAR i: SHORTINT;
BEGIN
	InitDriver;
	NEW(dev);  dev.typ := NetBase.broadcast;  dev.state := NetBase.closed;
	dev.sndCnt := 0;  dev.recCnt := 0;
	SYSTEM.MOVE(SYSTEM.ADR(sendhdr.src[0]), SYSTEM.ADR(dev.hostAdr[0]), 6);
	FOR i := 0 TO 5 DO dev.castAdr[i] := 0FFX END;
	dev.Receive := Receive;  dev.Send := Send;  dev.Available := Avail;
	NetBase.InstallDevice(dev)
END InstallDevice;

(*====================================debug and test Procedures==========================*)

PROCEDURE TestReceive*;
VAR item : NetBase.Item; i, prno :INTEGER; from : ARRAY 6 OF CHAR;
BEGIN
	NEW(item);
	IF Avail(dev) THEN
		Receive(dev, prno, from, item);
		Texts.WriteString(W, "Packet from: ");
		FOR i := 0 TO 5 DO
			Texts.WriteHex(W, ORD(from[i]));
		END;
		Texts.WriteLn(W);
		Texts.WriteString(W, "Protokoll Number: ");
		Texts.WriteHex(W, prno);
		Texts.WriteLn(W);
		Texts.WriteString(W, "Packet Data: ");
		Texts.WriteLn(W);
		FOR i := 0 TO 9 DO
			Texts.WriteHex(W,  ORD(item.data[i]));
		END;
		Texts.WriteLn(W);		
		Texts.WriteString(W, "Laenge des Packets: ");
		Texts.WriteInt(W, item.len, 5);
		Texts.WriteLn(W);
		
	ELSE
		Texts.WriteString(W, "Kein Paket erhaeltlich! ");
		Texts.WriteLn(W);
	END;
	Texts.Append(T, W.buf)
END TestReceive;

 
PROCEDURE TestSend*;
VAR item : NetBase.Item; i, j :LONGINT; dest : ARRAY 6 OF CHAR;
BEGIN
	NEW(item);
	item.ofs := 5; item.len := 1400;
	FOR j:=0 TO 0 DO
		FOR i := 0 TO 5 DO
			dest[i] := 0FFX;
		END;
(*
		FOR i := 5 TO 64 DO
			item.data[i] := CHR(j);
		END;
*)
		(*check: previous send is over*)
		
		Send(dev, 9, dest, item);
	END;	IF debug THEN
		Texts.Append(T, W.buf);
	END;
END TestSend;

PROCEDURE TimeSend*;
VAR t, i, j: LONGINT; item : NetBase.Item; dest : ARRAY 6 OF CHAR;  
BEGIN
	NEW(item);
	item.ofs := 5; item.len := 1400;
	FOR i := 0 TO 5 DO
		dest[i] := 0FFX;
	END;
	FOR i := 5 TO 64 DO
		item.data[i] := CHR(j);
	END;
	FOR j := 0 TO 9 DO
		t := Kernel.GetTimer();
		FOR i := 0 TO 1000 DO
			Send(dev, 9, dest, item);
		END;
		Texts.WriteString(W, "Sendete 1000 Pakete. Durchschnittliche Rate: ");
		Texts.WriteReal(W, 1000*((Kernel.GetTimer()-t)*Kernel.TimeUnit),10);
		Texts.WriteString(W, " Pakete pro Sekunde");
		Texts.Append(T, W.buf);
		Texts.WriteLn(W)
	END
END TimeSend;

PROCEDURE ShowAddress*;
VAR i: LONGINT;
BEGIN
	FOR i := 0 TO 5 DO
		Texts.WriteHex(W, ORD(sendhdr.src[i]))
	END;
	Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END ShowAddress;

PROCEDURE Dump*;
VAR i: SHORTINT; j: LONGINT; s: SET;
BEGIN
	IF debug THEN
	Texts.WriteString(W, "------- WINOffsets ");
	FOR i:=0 TO 14 BY 2 DO
		Texts.WriteHex(W,i);
	END;
	Texts.WriteLn(W);
		FOR i := 0 TO 7 DO
			SwitchToWindow(i);
			Texts.WriteString(W, "------- WINDOW "); Texts.WriteInt(W, i, 0);
			SYSTEM.PORTIN(BaseAdr, j); Texts.WriteHex(W,j);
			SYSTEM.PORTIN(BaseAdr+2, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+4, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+6, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+8, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+10, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+12, j); Texts.WriteHex(W, j);
			SYSTEM.PORTIN(BaseAdr+14, j); Texts.WriteHex(W, j);
			Texts.WriteLn(W);
		END;
		Texts.WriteLn(W);  Texts.Append(T, W.buf)
	END;
END Dump; 

(*========================= end of debug and test procedures ===============================*)

BEGIN
	IF debug THEN
		NEW(T);  Texts.Open(T, "");
		Oberon.OpenText("", T, 400, 200)
	END;
	Texts.OpenWriter(W);
	intCounter := 0; 
	InitIDs;
	InitUPDList();
	InitDPD;
END Net3Com905B.

SendTest:
Net3Com905B.InitDriver
Net3Com905B.InstallDevice reto~
TestSuite.Timing 
Net3Com905B.TestSend  a nb    ~
Net3Com905B.TestReceive
Net3Com905B.TimeSend

Net3Com905B.InstallDevice default
Net3Com905B.ShowAddress
Net3Com905B.Dump

NetSystem.Stop
NetSystem.Start