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

MODULE SCSI;	(** prk  **)
(*
	Common Interface for SCSI Drivers
	
	History:
		26.01.99
			SCSI Commands
		21.1.99
			Some SCSI Messages
			Command definition
*)

IMPORT SYSTEM, Disk, Kernel;

CONST
(** SCSI Commands*)	(*taken from scsi.h -> "http://lxr.linux.no/source/include/scsi/scsi.h" *)
	TestUnitReady* = 0X;
	RezeroUnit* = 1X;
	RequestSense* = 3X;
	Format* = 4X;
	ReadBlockLimits* = 5X;
	ReassignBlocks* = 7X;
	Read6* = 8X;
	Write6* = 0AX;
	Seek6* = 0BX;
	ReadReverse* = 0FX;
	WriteFilemarks* = 10X;
	Space* = 11X;
	Inquiry* = 12X;
	RecoverBufferedData* = 14X;
	ModeSelect* = 15X;
	Reserve* = 16X;
	Release* = 17X;
	Copy* = 18X;
	Erase* = 19X;
	ModeSense* = 1AX;
	StartStop* = 1BX;
	ReceiveDiagnostic* = 1CX;
	SendDiagnostic* = 1DX;
	AllowMediumRemoval* = 1EX;
	SetWindow* = 24X;
	ReadCapacity* = 25X;
	Read10* = 28X;
	Write10* = 2AX;
	Seek10* = 2BX;
	WriteVerify* = 2EX;
	Verify* = 2FX;
	SearchHigh* = 30X;
	SearchEqual* = 31X;
	SearchLow* = 32X;
	SetLilmits* = 33X;
	PreFetch* = 34X;
	ReadPosition* = 34X;
	SynchronizeCache* = 35X;
	LockUnlockCache* = 36X;
	ReadDefectData* = 37X;
	MediumScan* = 38X;
	Compare* = 39X;
	CopyVerify* = 3AX;
	WriteBuffer* = 3BX;
	ReadBuffer* = 3CX;
	UpdateBlock* = 3DX;
	ReadLong* = 3EX;
	WriteLong* = 3FX;
	ChangeDefinition* = 40X;
	WriteSame* = 41X;
	ReadToc* = 43X;
	LogSelect* = 4CX;
	LogSense* = 4DX;
	ModeSelect10* = 55X;
	ModeSense10* = 05AX;
	Read12* = 0A8X;
	Write12* = 0AAX;
	WriteVerify12* = 0AEX;
	SearchHigh12* = 0B0X;
	SearchEqual12* = 0B1X;
	SearchLow12* = 0B2X;
	ReadElementStatus* = 0B8X;
	SendVolumeTag* = 0B6X;
	WriteLong2* = 0EAX;

(** SCSI Messages / 1 Byte *)
	MsgCmdComplete* = 00X;
	MsgExtended* = 01X;
	MsgSaveDataPointer* = 02X;
	MsgRestorePointers* = 03X;
	MsgDisconnect* = 04X;
	MsgInitiatorDetErr* = 05X;
	MsgAbort* = 06X;
	MsgMessageReject* = 07X;
	MsgNoop* = 08X;
	MsgParityError* = 09X;
	MsgLinkCmdComplete* = 0AX;
	MsgLinkCmdCompleteF* = 0BX;
	MsgBusDevReset* = 0CX;
	MsgAbortTag* = 0DX;
	MsgClearQueue* = 0EX;
	MsgInitRecovery* = 0FX;
	MsgRelRecovery* = 10X;
	MsgTermIOProc* = 11X;
	
(**SCSI Messages / 2 Bytes*)
	MsgSimpleQTag* = 20X;
	MsgHeadOfQTag* = 21X;
	MsgOrderedQTag* = 22X;
	MsgIgnoreWideResidue* = 23X;
	
	MsgIdentifyFlag* = 80X;
		
(**SCSI Messages / Extended*)
	MsgExtSdTr* = 01X;  MsgExtSdTrLen* = 03X;
	MsgExtWdTr* = 03X;  MsgExtWdTrLen* = 02X; MsgExtWdTr8Bit* = 0X; MsgExtWdTr16Bit* = 1X;

(**SCSI Sense Keys*)
	NoSense* = 0;  RecoveredError* = 1;  NotReady* = 2;  MediumError* = 3;  HardwareError* = 4;
	IllegalRequest* = 5;  UnitAttention* = 6;  DataProtect* = 7;
	
TYPE
(** SCSI Command, all driver must accept this structure *)
	(*Command* = POINTER TO CommandDesc;*)
	CommandDesc* = RECORD
		status*, result*: SHORTINT; done*: BOOLEAN;			(* !!! These fields must be the first ones !!! *)
		target*, chan*, lun*: SHORTINT;	(**destination*)
		cmd*: LONGINT; clen*: SHORTINT;	(**command*)
		data*,dlen*: LONGINT;	(**data*)
		tag*: CHAR;	(*SCSI-II queued command tag*)
	END;

(** SCSI Structures for the common commands *)
	InquiryData* = RECORD
		deviceClass*, ISO*, ECMA*, ANSI*: SHORTINT;
		w32*, w16*, sync*, link*, que*, rmb*: BOOLEAN;
		manufacturer*, product*, rev*: ARRAY 32 OF CHAR;
	END;
	
CONST
(** SCSI.Command, status *)
	Good* = 0H;
	CheckCondition* = 2H;
	ConditionMet* = 4H;
	Busy* = 8H;
	Intermediate* = 0AH;
	IntermediateConditionMet* = 0DH;
	ReservationConflict* = 12H;
	CommandTerminated* = 16H;
	QueueFull* = 1CH;
	
	NotGood* = -1;
	
(** SCSI.Command, result *)
	OK* = 0H;
	NoConnect* = 01H;
	BusBusy* = 02H;
	TimeOut* = 03H;
	BadTarget* = 04H;
	Abort* = 05H;
	Parity* = 06H;
	Error* = 07H;
	Reset* = 08H;
	BadIntr* = 09H;
	PassThrough* = 0AH;
	SoftError* = 0BH;

TYPE
(** SCSI Driver *)
	Driver* = POINTER TO DriverDesc;
	SubmitProc* = PROCEDURE(d: Driver; VAR c: CommandDesc);
	EnumProc* = PROCEDURE(d: Driver; VAR stop: BOOLEAN);
	
	DriverDesc* = RECORD
		number*: LONGINT;
		
		wide*: BOOLEAN;
		name*: ARRAY 64 OF CHAR;
		submit*: SubmitProc;
		next: Driver;
		
		(*debug*: LONGINT;*)
	END DriverDesc;
	
(** SCSI Device *)
	Device* = POINTER TO DeviceDesc;
	DeviceDesc* = RECORD
		driver*: Driver;  target*: SHORTINT;
		name*: ARRAY 32 OF CHAR;
		class: SHORTINT;
		inquiry*: InquiryData;
		started: BOOLEAN;
		bs*, cyls*, hds*, spt*: LONGINT;	(**drive geometry*)
		next*: Device;
	END DeviceDesc;

CONST
(** SCSI Device class*)
	DirectAccess* = 0;  SequentialAccess* = 1; Printer* = 2; Processor* = 3; WriteOnce* = 4; CDRom* = 5;
	Scanner* = 6; Optical* = 7; MediumChanger* = 8; Communication* = 9; Unknown* = 1FH;
	
	
VAR
	DriverList: Driver;
	DriverCount: LONGINT;
	
	DeviceList*: Device;
	DeviceCache: ARRAY 4 OF Device;  DeviceCount: LONGINT;
	
(* Debug *)
PROCEDURE DumpCmdStatus(stat, res: SHORTINT);
BEGIN
	CASE stat OF
	| Good: Kernel.WriteString("Good ")
	| CheckCondition: Kernel.WriteString("CheckCondition ")
	| ConditionMet: Kernel.WriteString("ConditionMet ")
	| Busy: Kernel.WriteString("Busy ")
	| Intermediate: Kernel.WriteString("Intermediate ")
	| IntermediateConditionMet: Kernel.WriteString("IntermediateConditionMet ")
	| ReservationConflict: Kernel.WriteString("ReservationConflict ")
	| CommandTerminated: Kernel.WriteString("CommandTerminated ")
	| QueueFull: Kernel.WriteString("QueueFull ")
	ELSE Kernel.WriteString("unk"); Kernel.WriteInt(stat, 0)
	END;
	CASE res OF
	| OK: Kernel.WriteString("OK")
	| NoConnect: Kernel.WriteString("NoConnect")
	| BusBusy: Kernel.WriteString("BusBusy")
	| TimeOut: Kernel.WriteString("TimeOut")
	| BadTarget: Kernel.WriteString("BadTarget")
	| Abort: Kernel.WriteString("Abort")
	| Parity: Kernel.WriteString("Parity")
	| Error: Kernel.WriteString("Error")
	| Reset: Kernel.WriteString("Reset")
	| BadIntr: Kernel.WriteString("BadIntr")
	| PassThrough: Kernel.WriteString("PassThrough")
	| SoftError: Kernel.WriteString("SoftError")
	ELSE Kernel.WriteString("unk"); Kernel.WriteInt(res, 0)
	END;
	Kernel.WriteLn;
END DumpCmdStatus;

PROCEDURE WriteDriver(d: Driver);
BEGIN  Kernel.WriteString("scsi"); Kernel.WriteInt(d.number, 0); Kernel.WriteString(" ")
END WriteDriver;

PROCEDURE WriteDevice(d: Device);
BEGIN
	Kernel.WriteString("scsi"); Kernel.WriteInt(d.driver.number, 0); 
	Kernel.WriteChar("."); Kernel.WriteInt(d.target, 0); Kernel.WriteString(" ")
END WriteDevice;

PROCEDURE WriteDevice2(d: Driver; target: LONGINT);
BEGIN
	Kernel.WriteString("scsi"); Kernel.WriteInt(d.number, 0); 
	Kernel.WriteChar("."); Kernel.WriteInt(target, 0); Kernel.WriteString(" ")
END WriteDevice2;

PROCEDURE WriteConfig(d: Device; VAR c: InquiryData);
BEGIN
	WriteDevice(d); Kernel.WriteString("Inquiry: ");Kernel.WriteString("SCSI-");
	IF c.ANSI = 0 THEN Kernel.WriteChar("1")
	ELSIF c.ANSI = 1 THEN Kernel.WriteString("SCC")
	ELSE Kernel.WriteInt(c.ANSI, 0)
	END;
	IF c.rmb THEN Kernel.WriteString(" Removable")  END;
	IF c.w32 THEN Kernel.WriteString(" Wide-32") END;
	IF c.w16 THEN Kernel.WriteString(" Wide-16") END;
	IF c.sync THEN Kernel.WriteString(" Sync") END;
	Kernel.WriteLn
END WriteConfig;

(** Common SCSI Commands *)
PROCEDURE NewCmd(VAR c: CommandDesc; t, l: SHORTINT; ca, cl, da, dl: LONGINT);
BEGIN
	c.cmd := ca; c.clen := SHORT(SHORT(cl)); c.data := da; c.dlen := dl; c.target := t; c.lun := l;
	c.chan := 0;
END NewCmd;

PROCEDURE DoSense*(d: Driver; target, lun: SHORTINT; VAR key, code, res: LONGINT);
VAR Cmd: CommandDesc; cmd: ARRAY 6 OF CHAR; data: ARRAY 36 OF CHAR;
BEGIN
	cmd[0] := RequestSense; cmd[1]:= CHR(lun*32); cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 24X; cmd[5]:= 00X;
	NewCmd(Cmd, target, 0, SYSTEM.ADR(cmd), 6, SYSTEM.ADR(data), 36);
	d.submit(d, Cmd);  WHILE ~Cmd.done DO END;
	key := ORD(data[2]) MOD 16; code := 100H*ORD(data[12]) + ORD(data[13]);
	(*WriteDevice2(d, target); Kernel.WriteString(" sense "); Kernel.WriteInt(key, 3);
	Kernel.WriteString(" / "); Kernel.WriteHex(code, 0); Kernel.WriteLn;*)
	res := Cmd.status
END DoSense;

PROCEDURE SubmitAndSense*(d: Device; VAR cmd: CommandDesc; maxtry: LONGINT; msg: ARRAY OF CHAR; VAR res: LONGINT);
VAR key, code: LONGINT; dummy: BOOLEAN;
BEGIN
	REPEAT
		d.driver.submit(d.driver, cmd);  WHILE ~cmd.done DO END;
		IF cmd.status =  CheckCondition THEN
			WriteDevice(d); Kernel.WriteString("  "); Kernel.WriteString(msg);
			Kernel.WriteString(" returned CheckCondition"); Kernel.WriteLn;
			DoSense(d.driver, d.target, 0, key, code, res);
			IF (key#0) OR (code#0) THEN
				Kernel.WriteString("   sense -> "); Kernel.WriteInt(key, 3); Kernel.WriteHex(code, 0); Kernel.WriteLn;
				res := NotGood;
				RETURN
			END
		ELSIF cmd.status # Good THEN
			WriteDevice(d); Kernel.WriteString(": "); Kernel.WriteString(msg); 
			Kernel.WriteString(" returned with "); DumpCmdStatus(cmd.status, cmd.result);
		END;
		DEC(maxtry);
	UNTIL (cmd.status = Good) OR (maxtry < 0);
	res := cmd.status
END SubmitAndSense;

PROCEDURE DoTestUnitReady*(d: Driver; target, lun: SHORTINT; VAR res: LONGINT);
VAR Cmd: CommandDesc; cmd: ARRAY 6 OF CHAR;
BEGIN
	cmd[0]:= TestUnitReady; cmd[1]:= CHR(lun*32); cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 00X; cmd[5]:= 00X;
	NewCmd(Cmd, target, lun, SYSTEM.ADR(cmd), 6, 0, 0);
	d.submit(d, Cmd);  WHILE ~Cmd.done DO END;
	res := Cmd.status
END DoTestUnitReady;

PROCEDURE DoInquiryDrive*(d: Driver; target: SHORTINT; VAR inq: InquiryData; VAR res: LONGINT);
VAR Cmd: CommandDesc; cmd: ARRAY 6 OF CHAR; data: ARRAY 36 OF CHAR; i: LONGINT;
BEGIN
	cmd[0]:= Inquiry; cmd[1]:= 00X; cmd[2]:= 00X;
	cmd[3]:= 00X; cmd[4]:= 24X; cmd[5]:= 00X;
	NewCmd(Cmd, target, 0, SYSTEM.ADR(cmd), 6, SYSTEM.ADR(data), 36);
	d.submit(d, Cmd);  WHILE ~Cmd.done DO END;
	res := Cmd.status;
	IF res = Good THEN
		inq.deviceClass := SHORT(ORD(data[0]) MOD 32);
		inq.rmb := 7 IN SYSTEM.VAL(SET, data[1]);
		inq.ANSI := SHORT(ORD(data[2]) MOD 8);
		inq.ECMA := SHORT(SYSTEM.LSH(ORD(data[2]), -3) MOD 8);
		inq.ISO  := SHORT(SYSTEM.LSH(ORD(data[2]), -6) MOD 4);
		inq.w32 := 6 IN SYSTEM.VAL(SET, data[7]);
		inq.w16 := 5 IN SYSTEM.VAL(SET, data[7]);
		inq.sync := 4 IN SYSTEM.VAL(SET, data[7]);
		inq.link := 3 IN SYSTEM.VAL(SET, data[7]);
		inq.que := 1 IN SYSTEM.VAL(SET, data[7]);
		SYSTEM.MOVE(SYSTEM.ADR(data[8]), SYSTEM.ADR(inq.manufacturer), 8); 
		i := 7;  WHILE (i >= 0) & (inq.manufacturer[i] = 20X) DO  DEC(i)  END; inq.manufacturer[i+1]:= 0X;
		SYSTEM.MOVE(SYSTEM.ADR(data[16]), SYSTEM.ADR(inq.product), 16);
		i := 15;  WHILE (i >= 0) & (inq.product[i] = 20X) DO  DEC(i)  END; inq.product[i+1]:= 0X;
		SYSTEM.MOVE(SYSTEM.ADR(data[32]), SYSTEM.ADR(inq.rev), 4);
		i := 3;  WHILE (i >= 0) & (inq.rev[i] = 20X) DO  DEC(i)  END; inq.rev[i+1]:= 0X;
	END
END DoInquiryDrive;

PROCEDURE DoStartStopUnit*(d: Device; start: BOOLEAN; VAR res: LONGINT);
VAR	Cmd: CommandDesc; cmd: ARRAY 10 OF CHAR; data: ARRAY 16 OF CHAR;
BEGIN
	NewCmd(Cmd, d.target, 0, SYSTEM.ADR(cmd), 6, SYSTEM.ADR(data), 0);
	cmd[0]:= StartStop; cmd[1]:= 0X; cmd[2]:= 0X;
	cmd[3]:= 0X; cmd[5]:= 0X; 
	IF start THEN cmd[4]:= 1X ELSE cmd[4]:= 0X END;
	d.driver.submit(d.driver, Cmd);  WHILE ~Cmd.done DO END;
	res := Cmd.status
END DoStartStopUnit;

(** Disk oriented commands *)

PROCEDURE GetGeometry*(d: Device; VAR bs, cyls, hds, spt: LONGINT);
VAR
	requ: CommandDesc;
	cmd: ARRAY 10 OF CHAR; data: ARRAY 128 OF CHAR;
	capacity, i, temp, res: LONGINT; 
	code, qual: LONGINT;
BEGIN
	bs := 0; cyls := 0;  hds := 0;  spt := 0;
	IF (d # NIL) & ~d.inquiry.rmb THEN
			(*read capacity*)
		NewCmd(requ, d.target, 0, SYSTEM.ADR(cmd), 10, SYSTEM.ADR(data), 16);
		cmd[0]:= ReadCapacity; cmd[1]:= 0X; cmd[2]:= 0X;
		cmd[3]:= 0X; cmd[4]:= 0X; cmd[5]:= 0X;
		cmd[6]:= 0X; cmd[7]:= 0X; cmd[8]:= 0X; cmd[9]:= 0X;
		SubmitAndSense(d, requ, 2, "GetGeometry/ReadCapacity", res);
		IF res # Good THEN  RETURN   END;
		capacity:=0; (*bs:=0;*)
		FOR i := 0 TO 3 DO
			capacity:=capacity*100H + ORD(data[i]);
			bs:=bs*100H + ORD(data[4+i])
		END;
			(*get heads and cylinders*)
		cmd[0]:= ModeSense; cmd[1]:= 0X; cmd[2]:= 04X; cmd[3]:= 0X; cmd[4]:= 80X; cmd[5]:= 0X;
		requ.clen:= 6; requ.dlen:= 80H;
		SubmitAndSense(d, requ, 2, "GetGeometry/ModeSense", res);
		IF res # Good THEN  RETURN   END;
		i := 4 + ORD(data[3]);
		WHILE (ORD(data[i]) MOD 64 # 4) & (data[i+1] # 0X) & (i < 80H) DO  i := i + ORD(data[i+1])  END;	(*search for page 04X *)
		IF (ORD(data[i]) MOD 64 # 4) THEN  RETURN  END;
		cyls:= SYSTEM.LSH(LONG(ORD(data[i+2])),16) + SYSTEM.LSH(ORD(data[i+3]),8) + ORD(data[i+4]);
		hds:= ORD(data[i+5]);
			(*set size*)
		temp := cyls*hds;
		spt := capacity DIV temp;
		IF capacity MOD temp # 0 THEN
			temp := spt * hds;
			cyls := capacity DIV temp;
			IF capacity MOD temp # 0 THEN
				temp := cyls * spt;
				hds := capacity DIV temp
			END
		END
	END
END GetGeometry;

PROCEDURE GetBlocks*(d: Device; start, num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT; VAR res: LONGINT);
VAR Cmd: CommandDesc; cmd: ARRAY 10 OF CHAR; dummy: BOOLEAN;
BEGIN
	ASSERT(num < 10000H);
		(*use Read10*)
	cmd[0] := Read10; cmd[1] := 0X;
	cmd[2] := CHR(SYSTEM.LSH(start, -24));
	cmd[3] := CHR(SYSTEM.LSH(start, -16));
	cmd[4] := CHR(SYSTEM.LSH(start, -8));
	cmd[5] := CHR(start);
	cmd[6] := 0X;
	cmd[7] := CHR(SYSTEM.LSH(num, -8));
	cmd[8] := CHR(num);
	cmd[9] := 0X;
	NewCmd(Cmd, d.target, 0, SYSTEM.ADR(cmd), 10, SYSTEM.ADR(buf[0])+ofs, num*512);
	SubmitAndSense(d, Cmd, 10, "GetBlocks", res);
END GetBlocks;

PROCEDURE PutBlocks*(d: Device; start, num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT; VAR res: LONGINT);
VAR Cmd: CommandDesc; cmd: ARRAY 10 OF CHAR;
BEGIN
	ASSERT(num < 10000H);
		(*use Read10*)
	cmd[0] := Write10; cmd[1] := 0X;
	cmd[2] := CHR(SYSTEM.LSH(start, -24));
	cmd[3] := CHR(SYSTEM.LSH(start, -16));
	cmd[4] := CHR(SYSTEM.LSH(start, -8));
	cmd[5] := CHR(start);
	cmd[6] := 0X;
	cmd[7] := CHR(SYSTEM.LSH(num, -8));
	cmd[8] := CHR(num);
	cmd[9] := 0X;
	NewCmd(Cmd, d.target, 0, SYSTEM.ADR(cmd), 10, SYSTEM.ADR(buf[0])+ofs, num*512);
	SubmitAndSense(d, Cmd, 10, "PutBlocks", res);
END PutBlocks;

PROCEDURE DiskGet*(drive, start, num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR res: LONGINT;
BEGIN
	GetBlocks(DeviceCache[drive], start, num, buf, ofs, res);
END DiskGet;

PROCEDURE DiskPut*(drive, start, num: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE; ofs: LONGINT);
VAR res: LONGINT;
BEGIN
	PutBlocks(DeviceCache[drive], start, num, buf, ofs, res);
END DiskPut;

PROCEDURE DiskParams*(drive: LONGINT; VAR cyls, hds, spt: LONGINT);
BEGIN
	IF (DeviceCache[drive] # NIL) & (DeviceCache[drive].bs = 512) THEN
		cyls := DeviceCache[drive].cyls;
		hds := DeviceCache[drive].hds;
		spt := DeviceCache[drive].spt
	ELSE
		cyls := 0; hds := 0; spt := 0
	END
END DiskParams;

(** Device Functions *)
PROCEDURE IsDeviceReady(device: Device): BOOLEAN;
VAR res, res2, key, code, cnt, t: LONGINT; d: Driver; i: SHORTINT;
BEGIN
	d := device.driver; i := device.target;
	REPEAT
		DoTestUnitReady(d, i, 0, res);
		IF res # Good THEN  DoSense(d, i, 0, key, code, res2)  END;
	UNTIL (res = Good) OR (key # UnitAttention) OR (code DIV 100H # 29H) (*PowerOn*);
	
	IF device.class # DirectAccess THEN
		(*skip*)
	ELSIF (res # Good) & (key = NotReady) & (code = 0400H) THEN
		DoStartStopUnit(device, TRUE, res);
		IF res # Good THEN
			DoSense(d, i, 0, key, code, res);
			WriteDevice(device); Kernel.WriteString(" not ready, not starting, with sense ");
			Kernel.WriteInt(key, 3); Kernel.WriteHex(code, 0); Kernel.WriteLn;
			RETURN FALSE
		ELSE
			device.started := TRUE
		END;
		cnt := 0;
		REPEAT
			t := Kernel.GetTimer();
			WHILE Kernel.GetTimer() - t < 300 DO  END;
			INC(cnt);
			DoTestUnitReady(d, i, 0, res);
			IF res # Good THEN  DoSense(d, i, 0, key, code, res2) END;
		UNTIL (res = Good) OR (cnt = 10);
		IF res # Good THEN
			WriteDevice(device); Kernel.WriteString(" starting, not ready, with sense ");
			Kernel.WriteInt(key, 3); Kernel.WriteHex(code, 0); Kernel.WriteLn;
			RETURN FALSE
		END;
	END;
	RETURN res = Good
END IsDeviceReady;

PROCEDURE NewDevice(d: Driver);
VAR	i: SHORTINT;  key, code, j, k: LONGINT; data: InquiryData; device: Device; res, res2: LONGINT;
BEGIN
	i := 0;
	WHILE (i<8) OR (i<16)&d.wide DO
		DoInquiryDrive(d, i, data, res);
		IF res = Good THEN
			NEW(device); device.driver := d; device.target := i; device.inquiry := data;
			device.class := data.deviceClass;
			j := 0;
			WHILE data.manufacturer[j] # 0X DO  device.name[j] := data.manufacturer[j]; INC(j)  END;
			device.name[j] := "/"; INC(j);
			k := 0;
			WHILE data.product[k] # 0X DO device.name[j] := data.product[k]; INC(j); INC(k) END;
			device.name[j] := 0X;
			device.next := DeviceList; DeviceList := device;
WriteDevice(device); Kernel.WriteString(device.name); Kernel.WriteLn; 
WriteConfig(device, device.inquiry);
			IF IsDeviceReady(device) & (data.deviceClass = DirectAccess) & ~data.rmb THEN
				GetGeometry(device, device.bs, device.cyls, device.hds, device.spt)
			END;
IF ~data.rmb  & (device.bs # 0) THEN
	WriteDevice(device); Kernel.WriteString("Geometry: "); Kernel.WriteInt(device.bs, 0); Kernel.WriteString(" / "); Kernel.WriteInt(device.cyls, 0);
	Kernel.WriteString(" / "); Kernel.WriteInt(device.hds, 0); Kernel.WriteString(" / "); Kernel.WriteInt(device.spt, 0); Kernel.WriteLn
END;
			IF (DeviceCount < 4) & ~data.rmb & (device.class = DirectAccess) & (device.bs=512) THEN
				DeviceCache[DeviceCount] := device; INC(DeviceCount)
			END
		END;
		INC(i)
	END;
END NewDevice;

PROCEDURE TerminateDevice(dev: Device);
VAR  res: LONGINT;
BEGIN
	IF dev.started THEN
		DoStartStopUnit(dev, FALSE, res);
	END
END TerminateDevice;

(** Driver Functions *)
PROCEDURE RegisterDriver*(d: Driver);
BEGIN
	d.number := DriverCount; INC(DriverCount);
	WriteDriver(d); Kernel.WriteString(d.name); Kernel.WriteLn;
	d.next := DriverList; DriverList := d; NewDevice(d)
END RegisterDriver;

PROCEDURE RemoveDriver*(d: Driver);
VAR p, q: Driver; s, t: Device; i: LONGINT;
BEGIN
		(*remove driver from list*)
	IF DriverList = d THEN
		DriverList := d.next
	ELSE
		q := DriverList; p := q.next;
		WHILE (p#NIL) & (p#d) DO  q := p; p := p.next  END;
		IF p#NIL  THEN q.next := p.next  END
	END;
		(*invalidate devices*)
	WHILE (DeviceList # NIL) & (DeviceList.driver = d) DO
		TerminateDevice(DeviceList); DeviceList := DeviceList.next
	END;
	IF DeviceList # NIL THEN
		s := DeviceList; t := s.next;
		WHILE t # NIL DO
			IF t.driver = d THEN  TerminateDevice(t); t := t.next; s.next := t
			ELSE s := t; t := t.next
			END
		END
	END;
	FOR i := 0 TO DeviceCount-1 DO
		IF (DeviceCache[i] # NIL) & (DeviceCache[i].driver = d) THEN  DeviceCache[i] := NIL  END
	END
END RemoveDriver;

PROCEDURE FindDriver*(name: ARRAY OF CHAR): Driver;
VAR p: Driver;
BEGIN
	p := DriverList;
	WHILE (p # NIL) & (p.name # name) DO  p := p.next  END;
	RETURN p
END FindDriver;

PROCEDURE EnumerateDrivers*(proc: EnumProc);
VAR p: Driver; stop: BOOLEAN;
BEGIN
	stop := FALSE; p := DriverList;
	WHILE ~stop & (p#NIL) DO
		proc(p, stop);
		p := p.next
	END
END EnumerateDrivers;

(* Install the Disk upcalls. *)

PROCEDURE Install*;
BEGIN
	Disk.GetBlocks := DiskGet;
	Disk.PutBlocks := DiskPut;
	Disk.GetParams := DiskParams
END Install;

BEGIN
	Kernel.WriteString("SCSI / 0.9.2"); Kernel.WriteLn;
	(*NEW(Cmd);*)
	DeviceCount := 0; DriverCount := 0;
	DeviceCache[0] := NIL; DeviceCache[1] := NIL; DeviceCache[2] := NIL; DeviceCache[3] := NIL
END SCSI.
