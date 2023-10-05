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

MODULE NetBase;	(** non-portable *)	(* 12.09.96 mg *)

IMPORT SYSTEM, Kernel;
	
CONST
	closed* = 0; open* = 1; pending* = 2;

	MaxDevices* = 2; MaxProtocols = 4; MaxTimers = 2;

	AdrLen* = 6;
	MaxDataLen* = 1514;

	(* broadcast capability *)
	nobroadcast* = 0; broadcast* = 1;
	
	Trace = FALSE;
	
	DebugQueues = TRUE;	(* warning: can influence performance *)
	
TYPE
	Item* = POINTER TO ItemDesc;	(** basic network data item *)

	ItemDesc* = RECORD
		data*: ARRAY MaxDataLen OF SYSTEM.BYTE;
		padding: CHAR;	(* temporary until UDP/TCP chksum fixed *)
		ofs*, len*: INTEGER;	(** item.data[ofs..ofs+len-1] is current item data *)
		next: Item
	END ;

	Queue* = RECORD	(** Queue of items *)
		len*: INTEGER;
		first, last: Item
	END;

	Device* = POINTER TO DeviceDesc;
	DeviceDesc* = RECORD
		typ*, state*, num*: INTEGER;	(* broadcast/nobroadcast, close/open, index *)
		sndCnt*, recCnt*: LONGINT;	(* send/receive counters *)
		hostAdr*, castAdr*: ARRAY AdrLen OF SYSTEM.BYTE;
		Receive*: PROCEDURE (dev: Device; VAR prno: INTEGER; VAR src: ARRAY OF SYSTEM.BYTE; VAR item: Item);
		Send*: PROCEDURE (dev: Device; prno: INTEGER; VAR dest: ARRAY OF SYSTEM.BYTE; item: Item);
		Available*: PROCEDURE (dev: Device): BOOLEAN
	END;

	ProtocolProc* = PROCEDURE(item: Item);
	
	TaskProc* = PROCEDURE(time: LONGINT);

	Entry = RECORD
		prno: INTEGER;
		proc: ProtocolProc
	END;

VAR
	anyadr*: ARRAY AdrLen OF SYSTEM.BYTE;

	device: ARRAY MaxDevices OF Device;
	protocols: ARRAY MaxProtocols OF Entry;
	tasks: ARRAY MaxTimers OF TaskProc;
	nofProtocols, nofDevices, nofTasks: SHORTINT;

	freeList: Queue;

PROCEDURE CheckSum* (VAR data: ARRAY OF SYSTEM.BYTE; len: INTEGER; base: LONGINT): LONGINT;
CODE {SYSTEM.i386}
	MOV EAX, base[EBP]
	MOV EBX, data[EBP]
	MOV CX, len[EBP]
	SAR CX, 1
csloop:
	MOVZX EDX, WORD 0[EBX]
	ADD EAX, EDX
	ADD EBX, 2
	DEC CX
	JNZ csloop
	MOV EBX, EAX
	SAR EBX, 16
	AND EAX, 0FFFFH
	ADD EAX, EBX
	MOV EBX, EAX
	SAR EBX, 16
	ADD EAX, EBX
	NOT EAX
	AND EAX, 0FFFFH
END CheckSum;

PROCEDURE ByteSum* (VAR data: ARRAY OF SYSTEM.BYTE; len: INTEGER): LONGINT;
CODE {SYSTEM.i386}
	XOR EAX, EAX
	MOV EBX, data[EBP]
	MOV CX, len[EBP]
	SAR CX, 1
sloop:
	MOVZX EDX, WORD 0[EBX]
	ADD EAX, EDX
	ADD EBX, 2
	DEC CX
	JNZ sloop
END ByteSum;

PROCEDURE NetToHost* (VAR i: INTEGER);
BEGIN i := SYSTEM.ROT(i, 8)
END NetToHost;

PROCEDURE HostToNet* (VAR i: INTEGER);
BEGIN i := SYSTEM.ROT(i, 8)
END HostToNet;

PROCEDURE NetLToHost* (VAR l: ARRAY OF SYSTEM.BYTE);
VAR
	b: SYSTEM.BYTE;
BEGIN b := l[3]; l[3] := l[0]; l[0] := b; b := l[2]; l[2] := l[1]; l[1] := b
END NetLToHost;

PROCEDURE HostLToNet* (VAR l: ARRAY OF SYSTEM.BYTE);
VAR
	b: SYSTEM.BYTE;
BEGIN b := l[3]; l[3] := l[0]; l[0] := b; b := l[2]; l[2] := l[1]; l[1] := b
END HostLToNet;

PROCEDURE Equal* (VAR a, b: ARRAY OF SYSTEM.BYTE; len: INTEGER): BOOLEAN;
VAR i: LONGINT;
BEGIN
	i := 0; WHILE (i < len) & (a[i] = b[i]) DO INC(i) END;
	RETURN i = len
END Equal;

PROCEDURE Copy* (VAR src, dst: ARRAY OF SYSTEM.BYTE; len: INTEGER);
BEGIN SYSTEM.MOVE(SYSTEM.ADR(src[0]), SYSTEM.ADR(dst[0]), len)
END Copy;

(* FastCopy - Copy size bytes from source to dest.  (No overlap allowed) *)

PROCEDURE FastCopy*(source, dest, size: LONGINT);
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
END FastCopy;

PROCEDURE ^ GetItem* (VAR Q: Queue; VAR item: Item);

(** NewItem - Allocate a new item.  item.ofs is set to the maximum allowable offset.
item.len is set to 0. *)

PROCEDURE NewItem* (VAR item: Item);
BEGIN
	IF freeList.len = 0 THEN NEW(item)
	ELSE GetItem(freeList, item)
	END;
	item.padding := 0X;	(* temporary *)
	item.ofs := MaxDataLen; item.len := 0
END NewItem;

(** GetItem - Take an item from the front of a queue *)

PROCEDURE GetItem* (VAR Q: Queue; VAR item: Item);
BEGIN
	IF Q.len <= 0 THEN HALT(100) END;
	item := Q.first; Q.first := Q.first.next; DEC(Q.len);
	IF Q.first = NIL THEN Q.last := NIL END;
	(*item.len := 0*)
END GetItem;

(** PutItem - Put an item at the end of a queue *)

PROCEDURE PutItem* (VAR Q: Queue; item: Item);
VAR p: Item;
BEGIN
	IF DebugQueues THEN
		p := Q.first;
		WHILE p # NIL DO
			IF p = item THEN
				HALT(MAX(INTEGER))	(* error: item already in list *)
			END;
			p := p.next
		END
	END;
    IF Q.last # NIL THEN Q.last.next := item ELSE Q.first := item END;
    Q.last := item; item.next := NIL; INC(Q.len);
END PutItem;

(** RecycleItem - Recycle an item that is no longer used *)

PROCEDURE RecycleItem* (item: Item);
BEGIN
	PutItem(freeList, item)
END RecycleItem;

(** Reset - Initialise a queue *)

PROCEDURE Reset* (VAR Q: Queue);
BEGIN
	Q.len := 0; Q.first := NIL; Q.last := NIL
END Reset;

(** FindDevice - Find the device with the specified number (0..).  Returns NIL if no such device. *)

PROCEDURE FindDevice* (num: LONGINT): Device;
VAR dev: Device;
BEGIN
	IF (num >= 0) & (num < nofDevices) THEN dev := device[num] ELSE dev := NIL END;
	RETURN dev
END FindDevice;

(** InstallDevice - Install a new device.  Devices are numbered 0, 1, ... in installation order. *)

PROCEDURE InstallDevice*(dev: Device);
BEGIN
	dev.state := closed;  dev.sndCnt := 0;  dev.recCnt := 0;  dev.num := nofDevices;
	device[nofDevices] := dev;  INC(nofDevices)
END InstallDevice;

(** Poll - Poll all installed devices for packets and deliver them upstream. *)

PROCEDURE Poll*;
VAR item: Item;  src: ARRAY AdrLen OF SYSTEM.BYTE;  prno: INTEGER;  i, j: SHORTINT;
BEGIN
	FOR i := 0 TO nofDevices-1 DO
		IF device[i].state = open THEN
			WHILE device[i].Available(device[i]) DO
				NewItem(item);  item.ofs := 0;
				device[i].Receive(device[i], prno, src, item); j := 0;
				WHILE (j < nofProtocols) & (protocols[j].prno # prno) DO INC(j) END;
				IF j < nofProtocols THEN
					IF Trace THEN
						Kernel.WriteString("Recv:");  Kernel.WriteHex(prno, 9);  Kernel.WriteLn;
						(*Kernel.WriteMemory(SYSTEM.ADR(item.data[item.ofs-14]), 14);*)	(* peek into ethernet header *)
						Kernel.WriteMemory(SYSTEM.ADR(item.data[item.ofs]), item.len)
					END;
					protocols[j].proc(item)
				ELSE
					IF Trace THEN Kernel.WriteString("Drop: "); Kernel.WriteHex(prno, 8); Kernel.WriteLn END;
					PutItem(freeList, item)
				END;
				INC(device[i].recCnt)
			END
		END
	END;
	FOR i := 0 TO nofTasks-1 DO tasks[i](Kernel.GetTimer()) END
END Poll;

(** InstallProtocol - Install a handler for the specified protocol *)

PROCEDURE InstallProtocol* (P: ProtocolProc; prno: INTEGER);
VAR i: INTEGER;
BEGIN
	i := 0; WHILE (i # nofProtocols) & (protocols[i].prno # prno) DO INC(i) END;
	IF i = nofProtocols THEN
(*Kernel.WriteString("InstallProtocol ");  Kernel.WriteHex(prno, 8);  Kernel.WriteLn;*)
		protocols[nofProtocols].prno := prno; protocols[nofProtocols].proc := P;
		INC(nofProtocols)
	END
END InstallProtocol;

(** InstallTimer - Install a polling task. *)

PROCEDURE InstallTask*(p: TaskProc);
BEGIN
	tasks[nofTasks] := p;  INC(nofTasks)
END InstallTask;

(** Start - Initialise the polling task *)

PROCEDURE Start*;
VAR i: SHORTINT;
BEGIN
	Reset(freeList);
	FOR i := 0 TO nofDevices-1 DO
		IF device[i].state = closed THEN device[i].state := open END
	END
END Start;

(** Stop - Stop the polling task *)

PROCEDURE Stop*;
BEGIN
	Reset(freeList);
	nofDevices := 0; nofProtocols := 0; nofTasks := 0
END Stop;

BEGIN
	nofDevices := 0; nofProtocols := 0; nofTasks := 0;
	anyadr[0] := 0X; anyadr[1] := 0X; anyadr[2] := 0X;
	anyadr[3] := 0X; anyadr[4] := 0X; anyadr[5] := 0X
END NetBase.
