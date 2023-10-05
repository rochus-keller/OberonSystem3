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

MODULE AHA1520;	(** non-portable *)	(* Native driver for Adaptec 152x - Contributed by W. Ibl to the System 3 project 15.02.96 *)

IMPORT SYSTEM,Kernel;

(*
	This driver works on AHA-1520 to AIC-6360 Single Chip PC-AT to SCSI
	host adapters.
	This driver is based on aha152x.c - AHA-152x driver,
	which is Copyright 1993, 1994 Juergen E. Fischer

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

	I would like to thank Mr. Aaron J. Dailey for giving me the Information
	needed to make it work on the AVA boards.
*)

CONST
	(* SCSI port addresses, relative offset from PORTBASE *)
	SCSISEQ = 00H;	(* SCSI sequence control *)
	SXFRCTL0 = 01H;	(* SCSI transfer control 0 *)
	SXFRCTL1 = 02H;	(* SCSI transfer control 1 *)
	SCSISIG = 03H;	(* SCSI signal in/out *)
	SCSIRATE = 04H;	(* SCSI rate control *)
	SELID = 05H;	(* selection/reselection ID *)
	SCSIID = SELID;	(* SCSI ID *)
	SCSIDAT = 06H;	(* SCSI latched data *)
	SCSIBUS = 07H;	(* SCSI data bus *)
	STCNT0 = 08H;	(* SCSI transfer count 0 *)
	STCNT1 = 09H;	(* SCSI transfer count 1 *)
	STCNT2 = 0AH;	(* SCSI transfer count 2 *)
	SSTAT0 = 0BH;	(* SCSI interrupt status 0 *)
	SSTAT1 = 0CH;	(* SCSI interrupt status 1 *)
	SSTAT2 = 0DH;	(* SCSI interrupt status 2 *)
	SCSITEST = 0EH;	(* SCSI test control *)
	SSTAT4 = 0FH;	(* SCSI status 4 *)
	SIMODE0 = 10H;	(* SCSI interrupt mode 0 *)
	SIMODE1 = 11H;	(* SCSI interrupt mode 1 *)
	DMACNTRL0 = 12H;	(* DMA control 0 *)
	DMACNTRL1 = 13H;	(* DMA control 1 *)
	DMASTAT = 14H;	(* DMA status *)
	FIFOSTAT = 15H;	(* FIFO status *)
	DATAPORT = 16H;	(* DATA port *)
	BRSTCNTRL = 18H;	(* burst control *)
	PORTA = 1AH;	(* PORT A *)
	PORTB = 1BH;	(* PORT B *)
	REV = 1CH;	(* revision *)
	STACK = 1DH;	(* stack *)
	TEST = 1EH;	(* test register *)

	FIFODEPTH = 128;	(* FIFO depth in bytes *)
	IDENTIFYBASE = {7};	(* 80H *)

	(* SCSI sequence control bitmasks *)
	TEMODEO = {7};	(* 80H *)
	ENSELO = {6};		(* 40H *)
	ENSELI = {5};	(* 20H *)
	ENRESELI = {4};	(* 10H *)
	ENAUTOATNO= {3};	(* 08H *)
	ENAUTOATNI = {2};	(* 04H *)
	ENAUTOATNP = {1};	(* 02H *)
	SCSIRSTO = {0};	(* 01H *)

	(* SCSI transfer control 0 bitmasks *)
	SCSIEN = {7};	(* 80H *)
	DMAEN = {6};	(* 40H *)
	CH1 = {5};	(* 20H *)
	CLRSTCNT = {4};	(* 10H *)
	SPIOEN = {3};	(* 08H *)
	CLRCH1 = {1};	(* 02H *)

	(* SCSI transfer control 1 bitmasks *)
	BITBUCKET = 80H;
	SWRAPEN = 40H;
	ENSPCHK = 20H;
	STIMESEL = 18H;	(* mask *)
	STIMESEL0 = 03H;
	ENSTIMER = 04H;
	BYTEALIGN = 02H;

	(* SCSI signal IN bitmasks *)
	CDI = {7};	(* 80H *)
	IOI = {6};	(* 40H *)
	MSGI = {5};	(* 20H *)
	ATNI = {4};	(* 10H *)
	SELI = {3};	(* 08H *)
	BSYI = {2};	(* 04H *)
	REQI = {1};	(* 02H *)
	ACKI = {0};	(* 01H *)

	(* SCSI Phases *)
	PMASK = MSGI+CDI+IOI;	(* 0E0H *)
	PDATAO = {};	(* 00H *)
	PDATAI = IOI;
	PCMD = CDI;
	PSTATUS = CDI+IOI;	(* 0C0H *)
	PMSGO = MSGI+CDI;	(* 0A0H *)
	PMSGI = MSGI+CDI+IOI;	(* 0E0H *)

	(* additional Phases *)
	PBUSFREE = {0};	(* 01H - BUS FREE phase detected *)
	PPARITY = {1};	(* 02H - parity error in DATA phase *)

	(* SCSI signal out *)
	CDO = {7};	(* 80H *)
	IOO = {6};	(* 40H *)
	MSGO = {5};	(* 20H *)
	ATNO = {4};	(* 10H *)
	SELO = {3};	(* 08H *)
	BSYO = {2};	(* 04H *)
	REQO = {1};	(* 02H *)
	ACKO = {0};	(* 01H *)

	(* SCSI rate control *)
	SXFR = 70H;	(* mask *)
	SXFR0 = 4;
	SOFS = 0FH;	(* mask *)

	(* SCSI ID *)
	OID = 70H;
	OID0 = 4;
	TID = 07H;

	(* SCSI interrupt status *)
	TARGET = {7};	(* 80H *)
	SELDO = {6};	(* 40H *)
	SELDI = {5};	(* 20H *)
	SELINGO = {4};	(* 10H *)
	SWRAP = {3};	(* 08H *)
	SDONE = {2};	(* 04H *)
	SPIORDY = {1};	(* 02H *)
	DMADONE = {0};	(* 01H *)

	SETSDONE = 80H;
	CLRSELDO = 40H;
	CLRSELDI = 20H;
	CLRSELINGO = 10H;
	CLRSWRAP = 08H;
	CLRSDONE = 04H;
	CLRSPIORDY = 02H;
	CLRDMADONE = 01H;

	(* SCSI status 1 *)
	SELTO = {7};	(* 80H *)
	ATNTARG = {6};	(* 40H *)
	SCSIRSTI = {5};	(* 20H *)
	PHASEMIS = {4};	(* 10H *)
	BUSFREE = {3};	(* 08H *)
	SCSIPERR = {2};	(* 04H *)
	PHASECHG = {1};	(* 02H *)
	REQINIT = {0};	(* 01H *)

	CLRSELTIMO = 80H;
	CLRATNO = 40H;
	CLRSCSIRSTI = 20H;
	CLRBUSFREE = 08H;
	CLRSCSIPERR = 04H;
	CLRPHASECHG = 02H;
	CLRREQINIT = 01H;

	(* SCSI status 2 *)
	SOFFSET = {5};	(* 20H *)
	SEMPTY = {4};	(* 10H *)
	SFULL = {3};	(* 08H *)
	SFCNT = {0,1,2};	(* 07H mask *)

	(* SCSI status 3 *)
	SCSICNT = 0F0H;	(* mask *)
	SCSICNT0 = 4;
	OFFCNT = 0FH;	(* mask *)

	(* SCSI TEST control *)
	SCTESTU = 08H;
	SCTESTD = 04H;
	STCTEST = 01H;

	(* SCSI status 4 *)
	SYNCERR = 04H;
	FWERR = 02H;
	FRERR = 01H;

	CLRSYNCERR = 04H;
	CLRFWERR = 02H;
	CLRFRERR = 01H;

	(* SCSI interrupt mode 0 *)
	ENSELDO = {6};	(* 40H *)
	ENSELDI = {5};	(* 20H *)
	ENSELINGO = {4};	(* 10H *)
	ENSWRAP = {3};	(* 08H *)
	ENSDONE = {2};	(* 04H *)
	ENSPIORDY = {1};	(* 02H *)
	ENDMADONE = {0};	(* 01H *)

	(* SCSI interrupt mode 1 *)
	ENSELTIMO = {7};	(* 80H *)
	ENATNTARG = {6};	(* 40H *)
	ENSCSIRST = {5};	(* 20H *)
	ENPHASEMIS = {4};	(* 10H *)
	ENBUSFREE = {3};	(* 08H *)
	ENSCSIPERR = {2};	(* 04H *)
	ENPHASECHG = {1};	(* 02H *)
	ENREQINIT = {0};	(* 01H *)

	(* DMA control 0 *)
	ENDMA = {7};	(* 80H *)
	P8BIT = {6};	(* 40H *)
	DMA = {5};	(* 20H *)
	DWORDPIO = {4};	(* 10H *)
	WRITEREAD = {3};	(* 08H *)
	INTEN = {2};	(* 04H *)
	RSTFIFO = {1};	(* 02H *)
	SWINT = {0};	(* 01H *)

	(* DMA control 1 *)
	PWRDWN = 80H;
	STK = 07H;	(* mask *)

	(* DMA status *)
	ATDONE = {7};	(* 80H *)
	WORDRDY = {6};	(* 40H *)
	INTSTAT = {5};	(* 20H *)
	DFIFOFULL = {4};	(* 10H *)
	DFIFOEMP = {3};	(* 08H *)

	(* BURST control *)
	BON = 0F0H;
	BOFF = 0FH;

	(* TEST REGISTER *)
	BOFFTMR = 40H;
	BONTMR = 20H;
	STCNTH = 10H;
	STCNTM = 08H;
	STCNTL = 04H;
	SCSIBLK = 02H;
	DMABLK = 01H;

	(* Message Masks *)
	SABORT = {1,2};	(* 06H *)
	SMESSAGEREJECT = {0..2};	(* 07H *)

	(* Message Codes *)
	CommandComplete = 00H;
	ExtMessage = 01H;
		ExtModifyDataPointer = 00H;
		ExtSDTR = 01H;
		ExtExtendedIdentify = 02H;	(* SCSI-I only *)
		ExtWDTR = 03H;
	SavePointers = 02H;
	RestorePointers = 03H;
	Disconnect = 04H;
	InitiatorError = 05H;
	Abort = 06H;
	MessageReject = 07H;
	Nop = 08H;
	MsgParityError = 09H;
	LinkedCmdComplete = 0AH;
	LinkedFlgCmdComplete = 0BH;
	BusDeviceReset = 0CH;
	InitiateRecovery = 0FH;	(* SCSI-II only *)
	ReleaseRecovery = 10H;	(* SCSI-II only *)
	SimpleQueueTag = 20H;
	HeadOfQueueTag = 21H;
	OrderedQueueTag = 22H;

	(* Command phases *)
	NotIssued = 0;
	InSelection = 1;
	Disconnected = 2;
	Aborted = 3;
	SentIdent = 4;
	InOther = 5;

	(* Command Control *)
	SentCommand = 0;
	Finished = 1;
	FatalError = 2;

	(* Common Stati *)
	Good* = 0;	(* 00H *)

	(* Command Stati *)
	cmdCheckCondition* = 2;	(* 02H *)
	cmdConditionMet* = 4;	(* 04H *)
	cmdBusy* = 8;	(* 08H *)
	cmdIntermediate* = 16;	(* 10H *)
	cmdIntermediateCondMet* = 20;	(* 14H *)
	cmdReservationConflict* = 24;	(* 18H *)
	cmdCommandTerminated* = 34;	(* 22H *)
	cmdQueueFull* = 40;	(* 28H *)
	cmdAbortError* = 100;	(* 64H *)
	cmdAborted* = 126;	(* 7DH *)
	DriverError* = 127;	(* 7FH *)

	(* Driver Stati *)
	drvInquiry* = 1;	(* no inquiry available *)
	drvTarget* = 2;	(* Target is unknown *)
	drvReselect* = 3;	(* Reselection failed *)
	drvIdentify* = 4;	(* no Identification *)
	drvLun* = 5;	(* unknown LUN *)
	drvCommand* = 6; (* no command *)
	drvSelect* = 7;	(* no Timeout or Selection *)
	drvMessage* = 8;	(* unable to send Message *)
	drvPhase* = 9;	(* unexpected Phase change *)
	drvNoConnect* = 10;	(* Couldn't connect before timeout period *)
	drvDisconnect* = 10;	(* not allowed to disconnect *)
	drvInbound* = 11;	(* unsupported inbound Message *)
	drvFifo* = 12;	(* Fifo not empty *)
	drvBusBusy* = 13; (* BUS stayed busy through time out period *)

	(* SCSI Constants *)
	Targets* = 8;	(* Adressable targets per Host Adapter *)
	Units* = 8;	(* Adressable logical units per Target *)

TYPE
	Command* = POINTER TO CommandDesc;
	CommandDesc* = RECORD
		target*,lun*,clen*: SHORTINT;
		cmd*,dlen*,data*,ofs: LONGINT;
		phase,ctrl: SET;
		status*: SHORTINT;
		done*: BOOLEAN;
		next: Command;
	END;
VAR
	hostid*,status*: SHORTINT;	(* Id of host adapter *)
	portbase*: INTEGER;	(* start of adapter ports *)
	bios*: LONGINT;	(* host adapter BIOS address *)
	signature*: Kernel.Name;
	CanDoParity,CanDisconnect: BOOLEAN;	(* Parity Checking, Disconnection/Reconnection Support *)
	irq: SHORTINT;
	issued,current,discon: Command;
	aborting: BOOLEAN;

PROCEDURE AppScsiCmd(VAR qu: Command; cmd: Command);
	(* append a command to the inquiry queue *)
VAR
	c: Command;
BEGIN
	IF (qu = NIL) THEN
		qu:= cmd;
	ELSE
		c:= qu; WHILE (c.next # NIL) DO c:= c.next; END;
		c.next:= cmd; cmd.next:= NIL;
	END;
END AppScsiCmd;

PROCEDURE RemScsiCmd(VAR qu: Command; tgt,lun: SHORTINT): Command;
	(* get first command from the inquiry queue *)
VAR
	c1,c2: Command;
BEGIN
	c1:= qu; c2:= NIL;
	IF (tgt >= 0) & (lun >= 0) THEN
		WHILE (c1 # NIL) & (c1.target # tgt) & (c1.lun # lun) DO
			c2:= c1; c1:= c1.next;
		END;
	END;
	IF (c1 # NIL) THEN
		IF (c2 = NIL) THEN qu:= c1.next; ELSE c2.next:= c1.next; END;
	END;
	RETURN(c1);
END RemScsiCmd;

PROCEDURE RepInDouble(data,len: LONGINT);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,BRSTCNTRL
	MOV EDI,data[EBP]
	MOV ECX,len[EBP]
	CLD
	REP INSD
END RepInDouble;

PROCEDURE RepInByte(data,len: LONGINT);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,DATAPORT
	MOV EDI,data[EBP]
	MOV ECX,len[EBP]
	CLD
	REP INSB
END RepInByte;

PROCEDURE RepOutDouble(data,len: LONGINT);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,BRSTCNTRL
	MOV ESI,data[EBP]
	MOV ECX,len[EBP]
	CLD
	REP OUTSD
END RepOutDouble;

PROCEDURE RepOutWord(data,len: LONGINT);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,DATAPORT
	MOV ESI,data[EBP]
	MOV ECX,len[EBP]
	CLD
	REP OUTSW
END RepOutWord;

PROCEDURE RepOutByte(data,len: LONGINT);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,DATAPORT
	MOV ESI,data[EBP]
	MOV ECX,len[EBP]
	CLD
	REP OUTSB
END RepOutByte;

PROCEDURE SetBits(port: INTEGER; bits: SET);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,port[EBP]
	IN AL,DX
	OR EAX,bits[EBP]
	OUT DX,AL
END SetBits;

PROCEDURE ClrBits(port: INTEGER; bits: SET);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,port[EBP]
	MOV EBX,bits[EBP]
	NOT EBX
	IN AL,DX
	AND EAX,EBX
	OUT DX,AL
END ClrBits;

PROCEDURE ClrSetBits(port: INTEGER; clr,set: SET);
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,port[EBP]
	MOV EBX,clr[EBP]
	NOT EBX
	IN AL,DX
	AND EAX,EBX
	OR EAX,set[EBP]
	OUT DX,AL
END ClrSetBits;

PROCEDURE TestHi(port: INTEGER; bits: SET): BOOLEAN;
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,port[EBP]
	MOV EBX,bits[EBP]
	IN AL,DX
	AND EAX,EBX
	CMP AL,BL
	SETE AL
END TestHi;

PROCEDURE TestLo(port: INTEGER; bits: SET): BOOLEAN;
CODE {SYSTEM.i386}
	MOV DX,portbase
	ADD DX,port[EBP]
	MOV EBX,bits[EBP]
	IN AL,DX
	AND AL, BL
	SETE AL
END TestLo;

PROCEDURE LowerACK();
	(* read inbound byte and wait for ACK to get low *)
VAR
	portdata: CHAR;
BEGIN
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+SPIOEN));
	SYSTEM.PORTIN(portbase+SCSIDAT,SYSTEM.VAL(CHAR,portdata));
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1));
	REPEAT UNTIL ~TestHi(SCSISIG,ACKI);
END LowerACK;

PROCEDURE ScsiPhase(): SET;
	(* detect current phase, additional errorcodes PBUSFREE and PPARITY *)
VAR
	phase: SET;
BEGIN
	LOOP
		REPEAT
			REPEAT
				phase:= {}; SYSTEM.PORTIN(portbase+SSTAT1,SYSTEM.VAL(CHAR,phase));
			UNTIL (phase * (BUSFREE+SCSIRSTI+REQINIT) # {});
			IF (phase * BUSFREE # {}) THEN
				RETURN(PBUSFREE);
			ELSIF (phase * SCSIRSTI # {}) THEN
				(* IBM drive responds RSTI to RSTO *)
				SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,SCSIRSTI));
			END;
    	UNTIL TestLo(SCSISIG,ACKI) & TestHi(SSTAT1,REQINIT);

		SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,CLRSCSIPERR));
		phase:= {}; SYSTEM.PORTIN(portbase+SCSISIG,SYSTEM.VAL(CHAR,phase));
		phase:= phase * PMASK;

		IF TestHi(SSTAT1,SCSIPERR) THEN            (* DATA phase *)
			IF (phase * (CDO + MSGO) = {}) THEN RETURN(PPARITY); END;
			LowerACK();
		ELSE
			RETURN(phase);
		END;
	END;
END ScsiPhase;

PROCEDURE ScsiDone;
	(* current request has terminated *)
VAR
	cmd: Command;
BEGIN
	IF (current # NIL) THEN
		cmd:= current; current:= NIL;
		IF (issued = NIL) THEN
			SYSTEM.PORTOUT(portbase+PORTA,SYSTEM.VAL(CHAR,0));	(* LED off *)
		END;
		IF (discon # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
		END;
		IF (issued # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
		END;
		WHILE TestLo(SSTAT1,BUSFREE) DO END;	(* BUS FREE loop *)
		IF (status # Good) THEN cmd.status:= DriverError; END;
		cmd.done:= TRUE;
	ELSE
		status:= drvInquiry;
	END;
END ScsiDone;

PROCEDURE ScsiReconnect;
	(* disconnected target tries to reconnect *)
VAR
	target,lun: SHORTINT;
	selid: SET;
BEGIN
	IF (current # NIL) THEN
		AppScsiCmd(issued,current); current:= NIL;
	END;

	(* disable sequences *)
	SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SSTAT0,SYSTEM.VAL(CHAR,CLRSELDI));
	SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,CLRBUSFREE));

	selid:= {}; SYSTEM.PORTIN(portbase+SELID,SYSTEM.VAL(CHAR,selid));
	selid:= selid * (-{hostid});
	IF (selid = {}) THEN
		status:= drvTarget; RETURN;
	END;
	
	target:= 0; WHILE ~(target IN selid) DO INC(target); END;

	selid:= SYSTEM.VAL(SET,SYSTEM.LSH(hostid,OID0));
	selid:= selid + (SYSTEM.VAL(SET,target) * {0..2});
	SYSTEM.PORTOUT(portbase+SCSIID,SYSTEM.VAL(CHAR,selid));

	SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,ENRESELI));

	IF TestLo(SSTAT0,SELDI) THEN
		status:= drvReselect; RETURN;
	END;

    SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI));

    IF (ScsiPhase() # PMSGI) THEN
		status:= drvIdentify; RETURN;
	END;

    SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,0));
    SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1));
	selid:= {}; SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,selid));

	IF (selid * IDENTIFYBASE = {}) THEN
		status:= drvLun; RETURN;
	END;

    LowerACK(); selid:= ScsiPhase();
	lun:= SYSTEM.VAL(SHORTINT,selid * {0..5});

    current:= RemScsiCmd(discon,target,lun);
	IF (current = NIL) THEN
		status:= drvCommand; RETURN;
	END;
	EXCL(current.phase,Disconnected);

	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENBUSFREE));
	SetBits(DMACNTRL0,INTEN);
END ScsiReconnect;

PROCEDURE ScsiIssue;
	(* issue a queued command *)
VAR
	id: SET;
BEGIN
	current:= RemScsiCmd(issued,-1,-1);
	INCL(current.phase,InSelection);

	id:= SYSTEM.VAL(SET,SYSTEM.LSH(hostid,OID0));
	id:= id + (SYSTEM.VAL(SET,current.target) * {0..2});
	SYSTEM.PORTOUT(portbase+SCSIID,SYSTEM.VAL(CHAR,id));

	(* Enable int SELECTION OUT DONE and SELECTION OUT INITIATED *)
	IF CanDoParity THEN
		SYSTEM.PORTOUT(portbase+SXFRCTL1,SYSTEM.VAL(CHAR,ENSPCHK+ENSTIMER));
	ELSE
		SYSTEM.PORTOUT(portbase+SXFRCTL1,SYSTEM.VAL(CHAR,ENSTIMER));
	END;

	(* enable int for SELECTION OUT DONE and SELECTION TIME OUT *)
	IF (discon # NIL) THEN
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDO+ENSELDI));
	ELSE
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDO));
	END;

	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENSELTIMO));

	(* Enable SELECTION OUT sequence *)
	SetBits(SCSISEQ,ENSELO+ENAUTOATNO);
	SetBits(DMACNTRL0,INTEN);
END ScsiIssue;

PROCEDURE ScsiSelect(): BOOLEAN;
	(* waiting for the result of a selection attempt *)
BEGIN
	IF TestLo(SSTAT1,SELTO) THEN					(* no timeout *)
		IF TestHi(SSTAT0,SELDO) THEN

			(* clear BUS FREE interrupt *)
 	       SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,CLRBUSFREE));

	        (* Disable SELECTION OUT sequence *)
 	       ClrBits(SCSISEQ,ENSELO + ENAUTOATNO);

	        (* Disable SELECTION OUT DONE interrupt *)
 	       ClrBits(SIMODE0,ENSELDO); ClrBits(SIMODE1,ENSELTIMO);

	        IF TestLo(SSTAT0,SELDO) THEN
				SetBits(DMACNTRL0,INTEN);
				IF (Aborted IN current.phase) THEN
					current.status:= cmdAbortError;
					aborting:= FALSE;
				ELSE
					current.status:= DriverError; status:= drvNoConnect;
				END;
				RETURN(FALSE);
			END;

			(* selection was done *)
			SYSTEM.PORTOUT(portbase+SSTAT0,SYSTEM.VAL(CHAR,CLRSELDO));
			EXCL(current.phase,InSelection); INCL(current.phase,InOther);

			SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGO));
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENREQINIT+ENBUSFREE));
			SetBits(DMACNTRL0,INTEN);
			RETURN(TRUE);
		ELSE
			status:= drvSelect; RETURN(FALSE);
		END;
	ELSE
		(* end selection attempt (= timeout) *)
		ClrBits(SCSISEQ,ENSELO+ENAUTOATNO);
		SYSTEM.PORTOUT(portbase+SSTAT1,CLRSELTIMO);

		IF (discon # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
		END;

		IF (issued # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
		END;

		SetBits(DMACNTRL0,INTEN);

		IF (Aborted IN current.phase) THEN
			current.status:= cmdAbortError; aborting:= FALSE;
		END;

		IF TestLo(SSTAT0,SELINGO) THEN
			current.status:= DriverError; status:= drvBusBusy;
		ELSE
			current.status:= DriverError; status:= drvNoConnect;
		END;
		RETURN(FALSE);
	END;
END ScsiSelect;

PROCEDURE ScsiPhaseMSGO(): BOOLEAN;
	(* MESSAGE OUT *)
VAR
	exit: BOOLEAN;
	msg,phase: SET;
BEGIN
	exit:= FALSE; msg:= {};
	IF (Aborted IN current.phase) THEN
		msg:= SABORT;
	ELSE
		IF ~(SentIdent IN current.phase) THEN
			IF CanDisconnect THEN
				msg:= IDENTIFYBASE + {6} + (SYSTEM.VAL(SET,current.lun) * {0..2});
			ELSE
				msg:= IDENTIFYBASE + (SYSTEM.VAL(SET,current.lun) * {0..2});
			END;
			INCL(current.phase,SentIdent);
		ELSE
			msg:= SMESSAGEREJECT;
		END;
	END;

	ClrBits(SXFRCTL0,ENDMA);
	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENREQINIT+ENBUSFREE));

	(* wait for data latch to become ready or a phase change *)
	WHILE TestLo(DMASTAT,INTSTAT) DO END;

	IF (TestHi(SSTAT1,PHASEMIS)) THEN
		status:= drvMessage; RETURN(FALSE);
	END;

	(* Leave MESSAGE OUT after transfer *)
	SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,CLRATNO));
	SYSTEM.PORTOUT(portbase+SCSIDAT,SYSTEM.VAL(CHAR,msg));

	LowerACK; phase:= ScsiPhase();

	IF (msg = SABORT) THEN
		(* revive abort; abort enables interrupts *)
		current.phase:= current.phase * (-SYSTEM.LSH(PMASK,16));
		aborting:= FALSE;

		(* exit *)
		SetBits(DMACNTRL0,INTEN);
		exit:= TRUE;
	END;
	RETURN(exit);
END ScsiPhaseMSGO;

PROCEDURE ScsiPhaseCMD(): BOOLEAN;
	(* COMMAND phase *)
BEGIN
	IF ~(SentCommand IN current.ctrl) THEN

		(* reset fifo and enable writes *)
		SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,WRITEREAD+RSTFIFO));
		SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,ENDMA+WRITEREAD));

		(* clear transfer count and scsi fifo *)
		SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+CLRSTCNT+CLRCH1));
		SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,SCSIEN+DMAEN+CH1));

		(* missing phase raises INTSTAT *)
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
		SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENBUSFREE));

		(* wait for FIFO to get empty *)
		WHILE TestLo(DMASTAT,DFIFOEMP+INTSTAT) DO END;

		IF TestHi(SSTAT1,PHASEMIS) THEN
			status:= drvPhase; RETURN(FALSE);
		END;

		(* write command (6, 10 or 12 bytes) *)
		RepOutWord(current.cmd,current.clen DIV 2);

		(* wait for SCSI FIFO to get empty *)
		WHILE TestLo(SSTAT2,SEMPTY) DO END;

		ClrBits(SXFRCTL0,SCSIEN+DMAEN);
		(* transfer can be considered ended, when SCSIEN reads back zero *)
		WHILE TestHi(SXFRCTL0,SCSIEN) DO END;

		ClrBits(DMACNTRL0,ENDMA);
	ELSE
		status:= drvCommand; RETURN(FALSE);
	END;
	RETURN(FALSE);
END ScsiPhaseCMD;

PROCEDURE ScsiPhaseMSGI(): BOOLEAN;
	(* MESSAGE IN phase *)
VAR
	exit: BOOLEAN;
	phase: SET;
	msg,code,cnt: INTEGER;
BEGIN
	phase:= PMSGI; exit:= FALSE;

	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1));
	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));

	WHILE (phase = PMSGI) DO
		msg:= 0; SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,msg));
		CASE msg OF
		| Disconnect:
			msg:= 0;
			INCL(current.phase,Disconnected);
			IF ~CanDisconnect THEN
				status:= drvDisconnect; RETURN(FALSE);
			END;
		| CommandComplete:
			INCL(current.ctrl,Finished);
		| MessageReject:
		| SavePointers:
		| ExtMessage:
			LowerACK();
			IF (ScsiPhase() = PMSGI) THEN
				cnt:= 0; SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,cnt));
				LowerACK();
				IF (ScsiPhase() = PMSGI) THEN
					code:= 0; SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,code));
					CASE code OF
					| ExtModifyDataPointer:
						SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI+ATNO));
					| ExtSDTR:
						SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI+ATNO));
					| ExtExtendedIdentify:
					| ExtWDTR:
						SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI+ATNO));
					ELSE
						SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI+ATNO));
					END;

					WHILE (cnt > 0) DO
						LowerACK();
						IF (ScsiPhase() # PMSGI) THEN
							cnt:= 0;
						ELSE
							code:= 0; SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,code));
							DEC(cnt);
						END;
					END;
					SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,PMSGI+ATNO));
				END;
			END;
		ELSE
			status:= drvInbound; RETURN(FALSE);
		END;

		LowerACK(); phase:= ScsiPhase();
	END;

    (* clear SCSI fifo on BUSFREE *)
	IF (phase = PBUSFREE) THEN
		SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+CLRCH1));
	END;

	IF (Disconnected IN current.phase) THEN
		AppScsiCmd(discon,current); current:= NIL; exit:= TRUE;
		SetBits(SCSISEQ,ENRESELI);
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
		SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
		SetBits(DMACNTRL0,INTEN);
	END;
	RETURN(exit);
END ScsiPhaseMSGI;

PROCEDURE ScsiPhaseSTATUS(): BOOLEAN;
	(* STATUS IN phase *)
VAR
	msg: SET;
BEGIN
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1));
	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENREQINIT+ENBUSFREE));

	SYSTEM.PORTIN(portbase+SCSIBUS,SYSTEM.VAL(CHAR,current.status));
	LowerACK();
	msg:= ScsiPhase();
	RETURN(FALSE);
END ScsiPhaseSTATUS;

PROCEDURE ScsiPhaseDATAI(): BOOLEAN;
	(* DATA IN phase *)
VAR
	done: BOOLEAN;
	fifodata: INTEGER;
	cnt: LONGINT;
BEGIN
	(* reset host fifo *)
	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,RSTFIFO));
	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,RSTFIFO+ENDMA));

	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+SCSIEN+DMAEN));

	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENBUSFREE));

    (* done is set when the FIFO is empty after the target left DATA IN *)
	done:= FALSE; fifodata:= 0; current.dlen:= 0;

	(* while the target stays in DATA to transfer data *)
	WHILE ~done DO
		(* wait for PHASEMIS or full FIFO *)
		WHILE TestLo(DMASTAT,DFIFOFULL+INTSTAT) DO END;

		IF TestHi(DMASTAT,DFIFOFULL) THEN
			SYSTEM.PORTIN(portbase+FIFOSTAT,SYSTEM.VAL(CHAR,fifodata));
		ELSE
			(* wait for SCSI fifo to get empty *)
			WHILE TestLo(SSTAT2,SEMPTY) DO END;

			(* rest of data in FIFO *)
			SYSTEM.PORTIN(portbase+FIFOSTAT,SYSTEM.VAL(CHAR,fifodata));
			done:= TRUE;
		END;

		cnt:= fifodata DIV 4;
		IF (cnt > 0) THEN	(* enable double word input *)
			ClrBits(DMACNTRL0,P8BIT); SetBits(DMACNTRL0,DWORDPIO);
			RepInDouble(current.data+current.dlen,cnt);
			INC(current.dlen,cnt*4);
		END;

		cnt:= fifodata MOD 4;
		IF (cnt > 0) THEN	(* read rest in byte steps *)
			SetBits(DMACNTRL0,P8BIT);
			RepInByte(current.data+current.dlen,cnt);
			INC(current.dlen,cnt);
		END;
	END;

	(* transfer can be considered ended, when SCSIEN reads back zero *)
	ClrBits(SXFRCTL0,SCSIEN+DMAEN);
	WHILE TestHi(SXFRCTL0,SCSIEN) DO END;
	ClrBits(DMACNTRL0,ENDMA);
	RETURN(FALSE);
END ScsiPhaseDATAI;

PROCEDURE ScsiPhaseDATAO(): BOOLEAN;
	(* DATA OUT phase *)
VAR
	fifostat: SET;
	res,cnt: LONGINT;
BEGIN
	fifostat:= {}; SYSTEM.PORTIN(portbase+FIFOSTAT,SYSTEM.VAL(CHAR,fifostat));
	IF (fifostat # {}) THEN
		fifostat:= {}; SYSTEM.PORTIN(portbase+SSTAT2,SYSTEM.VAL(CHAR,fifostat));
		IF (fifostat*SFULL*SFCNT # {}) THEN
			status:= drvFifo; RETURN(FALSE);
		END;
	END;
  
	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,WRITEREAD+RSTFIFO));
	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,ENDMA+WRITEREAD));

	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+CLRSTCNT+CLRCH1));
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,SCSIEN+DMAEN+CH1));

	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENBUSFREE));

	WHILE TestLo(SSTAT1,PHASEMIS) & (current.ofs < current.dlen) DO
		res:= current.dlen - current.ofs;
		IF (res > FIFODEPTH) THEN res:= FIFODEPTH; END;

		cnt:= res DIV 4;
		IF (cnt > 0) THEN	(* enable double word output *)
			ClrBits(DMACNTRL0,P8BIT); SetBits(DMACNTRL0,DWORDPIO);
			RepOutDouble(current.data+current.ofs,cnt);
			INC(current.ofs,cnt*4);
		END;

		cnt:= res MOD 4;
		IF (cnt > 0) THEN	(* write rest in bytes *)
			SetBits(DMACNTRL0,P8BIT);
			RepOutByte(current.data+current.ofs,cnt);
			INC(current.ofs,cnt);
		END;

		(* wait for FIFO to get empty *)
		WHILE TestLo(DMASTAT,DFIFOEMP+INTSTAT) DO END;
	END;

	(* target leaves DATAO for another phase (perhaps disconnect) *)
	IF (current.ofs < current.dlen) THEN
		cnt:= 0; res:= 0;
		(* data in fifos has to be resend *)
		SYSTEM.PORTIN(portbase+SSTAT2,SYSTEM.VAL(CHAR,cnt));
		SYSTEM.PORTIN(portbase+FIFOSTAT,SYSTEM.VAL(CHAR,res));

		cnt:= SYSTEM.VAL(LONGINT,SYSTEM.VAL(SET,cnt) * (SFULL+SFCNT));
		DEC(current.ofs,res+cnt);

		SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,WRITEREAD+RSTFIFO));
		SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,SCSIEN+DMAEN));
		ClrBits(DMACNTRL0,ENDMA);
	ELSE
		(* wait for SCSI fifo to get empty *)
		WHILE TestLo(SSTAT2,SEMPTY) DO END;
		ClrBits(SXFRCTL0,SCSIEN+DMAEN);

		(* transfer can be considered ended, when SCSIEN reads back zero *)
    	WHILE TestHi(SXFRCTL0,SCSIEN) DO END;
		ClrBits(DMACNTRL0,ENDMA);
	END;
	RETURN(FALSE);
END ScsiPhaseDATAO;

PROCEDURE InterruptHandler;
	(* main routine of the driver *)
VAR
	phase: SET;
BEGIN
	ClrBits(DMACNTRL0,INTEN);

	IF TestHi(SSTAT0,SELDI) & (discon # NIL) &
		((current = NIL) OR (InSelection IN current.phase)) THEN
		ScsiReconnect(); RETURN;
	END;

	IF (current = NIL) THEN		(* Check, if not busy with a command *)
		IF TestHi(SSTAT1,BUSFREE) & (issued # NIL) THEN
		(* bus is free to issue a queued command *)
			ScsiIssue(); RETURN;
		END;

		(* No command we are busy with and no new to issue *)
		RETURN;
	END;

	(* waiting for the result of a selection attempt *)
	IF (InSelection IN current.phase) THEN
		IF ~ScsiSelect() THEN ScsiDone(); RETURN; END;
	END;

	(* enable interrupt, when target leaves current phase *)
	phase:= ScsiPhase();

	(* "real" phase *)
	IF ((phase * (-PMASK)) = {}) THEN
		SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,phase));
	END;

	SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,CLRPHASECHG));
	phase:= (phase * (-(PMASK*{1}))) + phase;

	(* information transfer phase *)
	IF (phase = PMSGO) THEN	(* MESSAGE OUT *)
		IF ScsiPhaseMSGO() THEN RETURN; END;
	ELSIF (phase = PCMD) THEN	(* COMMAND *)
		IF ScsiPhaseCMD() THEN RETURN; END;
	ELSIF (phase = PMSGI) THEN	(* MESSAGE IN *)
		IF ScsiPhaseMSGI() THEN RETURN; END;
	ELSIF (phase = PSTATUS) THEN	(* STATUS IN*)
		IF ScsiPhaseSTATUS() THEN RETURN; END;
	ELSIF (phase = PDATAI) THEN	(* DATA IN phase *)
		IF ScsiPhaseDATAI() THEN RETURN; END;
	ELSIF (phase = PDATAO) THEN	(* DATA OUT phase *)
		IF ScsiPhaseDATAO() THEN RETURN; END;
	ELSIF (phase = PBUSFREE) THEN	(* BUSFREE *)
		phase:= SYSTEM.VAL(SET,SYSTEM.LSH(PMASK,16));
    	current.phase:= current.phase * (-phase);
		INCL(current.ctrl,Finished);
		RETURN;
	ELSIF (phase = PPARITY) THEN	(* parity error in DATA phase *)
		phase:= SYSTEM.VAL(SET,SYSTEM.LSH(PMASK,16));
    	current.phase:= current.phase * (-phase);
		SetBits(DMACNTRL0,INTEN);
		INCL(current.ctrl,Finished);
		RETURN;
	ELSE
		status:= drvPhase;
	END;

	IF (Finished IN current.ctrl) OR (status # Good) THEN
		IF (discon # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
		END;

		IF (issued # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
		END;

		IF (discon # NIL) THEN
			SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,ENRESELI));
		ELSE
			SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,0));
		END;
		SetBits(DMACNTRL0,INTEN);
		ScsiDone();
    	RETURN;
	END;

	IF (current # NIL) THEN
		current.phase:= current.phase + {16};
	END;

	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENPHASEMIS+ENBUSFREE));
	SetBits(DMACNTRL0,INTEN);
	RETURN;
END InterruptHandler;

PROCEDURE ResetPorts;
	(* reset all ports of the controller *)
BEGIN
	(* disable interrupts *)
	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,RSTFIFO));

	SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,0));

	SYSTEM.PORTOUT(portbase+SXFRCTL1,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SCSISIG,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SCSIRATE,SYSTEM.VAL(CHAR,0));

	(* clear all interrupt conditions *)
	SYSTEM.PORTOUT(portbase+SSTAT0,SYSTEM.VAL(CHAR,{0..6}));
	SYSTEM.PORTOUT(portbase+SSTAT1,SYSTEM.VAL(CHAR,{0..3,5..7}));

	SYSTEM.PORTOUT(portbase+SSTAT4,SYSTEM.VAL(CHAR,SYNCERR+FWERR+FRERR));

	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+DMACNTRL1,SYSTEM.VAL(CHAR,0));

	SYSTEM.PORTOUT(portbase+BRSTCNTRL,SYSTEM.VAL(CHAR,{0,4..7}));

	(* clear SCSI fifo and transfer count *)
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1+CLRCH1+CLRSTCNT));
	SYSTEM.PORTOUT(portbase+SXFRCTL0,SYSTEM.VAL(CHAR,CH1));

	(* enable interrupts *)
	IF (discon # NIL) THEN
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
	ELSE
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	END;

	IF (issued # NIL) THEN
		SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
	ELSE
		SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
	END;
END ResetPorts;

PROCEDURE Reset*;
	(* Reset controller and driver *)
VAR
	t: LONGINT;
BEGIN
	ResetPorts();

	IF TestLo(SSTAT1,BUSFREE) THEN	(* Reset, if bus hangs *)
		ClrBits(DMACNTRL0,INTEN);

		(* RESET OUT *)
		SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,SCSIRSTO));
		t:= Kernel.GetTimer(); REPEAT UNTIL Kernel.GetTimer() - t > 90;
		SYSTEM.PORTOUT(portbase+SCSISEQ,SYSTEM.VAL(CHAR,0));
		t:= Kernel.GetTimer(); REPEAT UNTIL Kernel.GetTimer() - t > 180;

		IF (discon # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
    	END;

		IF (issued # NIL) THEN
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
		ELSE
			SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
		END;
	END;

	SYSTEM.PORTOUT(portbase+DMACNTRL0,SYSTEM.VAL(CHAR,INTEN));
END Reset;

PROCEDURE Init;
	(* Initialize driver and controller, install the interrupt handler *)
VAR
	t: LONGINT;
BEGIN
	SetBits(SCSIID,SYSTEM.VAL(SET,SYSTEM.LSH(hostid,4)));
	SetBits(SCSISEQ,SCSIRSTO);
	t:= Kernel.GetTimer(); REPEAT UNTIL Kernel.GetTimer() - t > 90;
	ClrBits(SCSISEQ,SCSIRSTO);
	t:= Kernel.GetTimer(); REPEAT UNTIL Kernel.GetTimer() - t > 180;
	Reset();

	t:= 0;
	REPEAT
		SYSTEM.GET(bios+0CH+t,signature[t]); INC(t);
	UNTIL (t = LEN(signature)) OR (signature[t-1] = 0X);

	SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,0));
	SetBits(DMACNTRL0,INTEN);
	Kernel.InstallIP(InterruptHandler,Kernel.IRQ+irq);
END Init;

PROCEDURE Initiate*(cmd: Command);
	(* queue up a SCSI command request *)
BEGIN
	status:= Good;
	cmd.phase:= {NotIssued}; cmd.ctrl:= {};
	cmd.ofs:= 0; cmd.done:= FALSE; cmd.status:= Good;

	SYSTEM.CLI();
	IF (issued = NIL) THEN
		SYSTEM.PORTOUT(portbase+PORTA,SYSTEM.VAL(CHAR,1));
	END;
	AppScsiCmd(issued,cmd);
	IF (discon # NIL) THEN
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
	ELSE
		SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
	END;
	SYSTEM.PORTOUT(portbase+SIMODE1,SYSTEM.VAL(CHAR,ENBUSFREE));
	SYSTEM.STI();
END Initiate;

PROCEDURE Terminate*(cmd: Command);
	(* abort a queued SCSI command request *)
VAR
	c1,c2: Command;
	selid: SET;
BEGIN
	SYSTEM.CLI(); status:= Good;

	(* look for command in issue queue *)
	c1:= issued; c2:= NIL;
	WHILE (c1 # NIL) & (c1 # cmd) DO c2:= c1; c1:= c1.next; END;
	IF (c1 # NIL) THEN	(* dequeue *)
		IF (c2 = NIL) THEN issued:= c1.next; ELSE c2.next:= c1.next; END;
		cmd.status:= cmdAborted;
	ELSIF TestLo(SSTAT1,BUSFREE) OR (current # cmd) THEN
		(* fail abortion, if bus is busy *)
		cmd.status:= DriverError; status:= drvBusBusy;
	ELSIF (current # NIL) THEN
		(* target entered bus free before COMMAND COMPLETE *)
		current:= NIL; cmd.status:= cmdAborted;
	ELSE
		(* look for command in disconnected queue *)
		c1:= discon; c2:= NIL;
		WHILE (c1 # NIL) & (c1 # cmd) DO c2:= c1; c1:= c1.next; END;
		IF (c1 # NIL) THEN
			IF aborting THEN
				cmd.status:= DriverError; status:= drvBusBusy;
			ELSE
				(* dequeue *)
				IF (c2 = NIL) THEN discon:= c1.next; ELSE c2.next:= c1.next; END;
				(* set command current and initiate selection for abortion *)
				current:= cmd; cmd.phase:= {InSelection,Aborted};

				selid:= SYSTEM.VAL(SET,SYSTEM.LSH(hostid,OID0));
				selid:= selid + (SYSTEM.VAL(SET,hostid) * {0..2});
				SYSTEM.PORTOUT(portbase+SCSIID,SYSTEM.VAL(CHAR,selid));

				(* enable interrupts for SELECTION OUT DONE and SELECTION TIME OUT *)
				IF (discon # NIL) THEN
					SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,ENSELDI));
				ELSE
					SYSTEM.PORTOUT(portbase+SIMODE0,SYSTEM.VAL(CHAR,0));
				END;
				SYSTEM.PORTOUT(portbase+SIMODE1,ENSELTIMO);

				(* Enable SELECTION OUT sequence *)
				SetBits(SCSISEQ,ENSELO+ENAUTOATNO);
				SetBits(DMACNTRL0,INTEN);
				aborting:= TRUE;

				(* sleep until the abortion is complete *)
				SYSTEM.STI();
				WHILE aborting DO END;
			END;
		END;
	END;
END Terminate;

(* StrToInt - Convert a string to an integer *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

(* Config - Read config string.

	Syntax for "AHA1520" config string (no spaces allowed, hex values have "H" suffix):
	
	AHA1520 = irq ["," portbase ["," hostid ["," bios ["," parity ["," discon]]]]].
	irq = 11 | 9 | 10 | 12 | ... .
	portbase = 340H | 140H | ... .
	hostid = 7 | 0 | 1 | 2 | 3 | 4 | 5 | 6 .
	bios = 0DC000H | 0C8000H | 0CC000H | 0D8000H | ... .
	parity = 0 | 1 .
	discon = 0 | 1 .
	
	The default value is: "11,340H,7,0DC000H,0,0" (factory defaults)
	If a parameter (and all following parameters) are left out, they take on default values.
*)
	
PROCEDURE Config;
VAR s: ARRAY 40 OF CHAR;  p, parity, discon: LONGINT;
BEGIN
	Kernel.GetConfig("AHA1520", s);
	portbase := 0;  hostid := 0;  bios := 0;  parity := 0;  discon := 0;	(* nil/default values *)
	p := 0;  irq := SHORT(SHORT(StrToInt(p, s)));
	IF s[p] = "," THEN
		INC(p);  portbase := SHORT(StrToInt(p, s));
		IF s[p] = "," THEN
			INC(p);  hostid := SHORT(SHORT(StrToInt(p, s)));
			IF s[p] = "," THEN
				INC(p);  bios := StrToInt(p, s);
				IF s[p] = "," THEN
					INC(p);  parity := StrToInt(p, s);
					IF s[p] = "," THEN
						INC(p);  discon := StrToInt(p, s)
					END
				END
			END
		END
	END;
	IF irq = 0 THEN irq := 11 END;
	IF portbase = 0 THEN portbase := 340H END;
	IF hostid = 0 THEN hostid := 7 END;
	IF bios = 0 THEN bios :=  0DC000H END;
	CanDoParity := parity # 0;
	CanDisconnect := discon # 0;
	Kernel.WriteString("AHA1520: ");  Kernel.WriteInt(irq, 1);  Kernel.WriteHex(portbase, 9);  Kernel.WriteInt(hostid, 2);  
	Kernel.WriteHex(bios, 9);  Kernel.WriteInt(parity, 2);  Kernel.WriteInt(discon, 2);  Kernel.WriteLn
END Config;

BEGIN
	Config;
	status:= Good; aborting:= FALSE; issued:= NIL; current:= NIL; discon:= NIL;
	Init
END AHA1520.
