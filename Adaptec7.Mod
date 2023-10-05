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

MODULE Adaptec7;	(** prk  **)

(**
		driver for Adaptec 7xxx SCSI adapters. Currently only PCI adapters supported
		
		Based on the linux aic7xxx driver (Version = 5.1.0).
		
		Ported by Patrik Reali (reali@acm.org), 30.3.99
		
		Manual Driver Configuration (with kernel strings):
		-Ada7Debug:	(print debug information)
			01H: Trace Calls
			02H: Trace Interrupts
			04H: Trace Messages
			08H: Trace SCBs
			10H: Trace Sequencer
			20H: Trace Resets
			40H: Trace Configuration
			80H: Trace Period information
			100H: Trace SCSI Commands
		
		-Ada7ResetDelay:  reset delay in ms. Default = 5000
*)

(*
		Improve:
			ResetChip:	move out the config stuff (but only after implementing the VL cards)
			LoadSeeprom:	move out the config stuff
		
			* find cards on the VL/EISA and initialize all the other params, ev. detect special features
			* ensure that the class of an SCB (queue is in) correspond to the state.
			
			* what about the timer?
				-> jiffies, TimerTimeout, HZ
			
			* check for newer Linux versions:
				-> InterruptScsi, SELTO with invalid Waiting SCB. Now uses an "emergency" solution". Must be improved

Understanding the driver:

	Each host has:
		255 hwscb: scsi control block, a command to the sequencer, 255 (FFx) is NIL
		--- scb: driver infos about the command executed by the hwscb
		
	commands can be in the following states:
	* free (not in use)
	* disconnected (command send, waiting for reconnection when device has data)
	* delayed (cannot be run now)
	* waiting (to be queued, not sent to the sequencer)
	* queued
	
	the sequencer has the following queues (first element, chaining through the next field):
	* free
	* disconnected
	* waiting
	the host has also these queues, but must keep them up-to-date!
	
	* infifo: ?
	* outfifo: ?
	
	Width/Period simplification:
	* curX : current width period
	* goalX: wished period
	* needX: need to trasmit it by the next message
	* pendingX: in trasmission, awaiting response
*)

IMPORT
	SCSI, Script := Adaptec7Script, Kernel, SYSTEM, PCI;
	
CONST
		(*Debug Configuration*)
	DebugNoWrites = FALSE;	(* never write to registers *)
	
	DisconnectEnable = FALSE;
	
		(*Unimplemented Trap*)
	TimerUnimplemented = 140;
	Unimplemented = 0DAH;
	
		(*Host.chip: enumeration    *)
	AIC7770 = 1; AIC7850 = 2; AIC7860 = 3; AIC7870 = 4; AIC7880 = 5; AIC7890 = 6; 
	AIC7895 = 7; AIC7896 = 8; 

		(*Host Features   *)
	FeatUltra = 1; FeatUltra2 = 2; FeatWide = 3; FeatTwin = 4; FeatMoreSRAM = 5; FeatCmdChan = 6; 
	FeatQueueRegs = 7; FeatSGPreload = 8; FeatSpioCap = 9; 
	
		(*Host Flags  *)
	FlagPageSCB = 1; FlagNewEepromFMT = 2; FlagBiosEnabled = 3; FlagMultiChannel = 4; FlagChnlB = 5; FlagChnlC = 6; 
	FlagTermEnbA = 7; FlagTermEnbB = 8; FlagTermEnbSELow = 9; FlagTermEnbSEHigh = 10; FlagSeepromFound = 11; FlagChannelBPrimary = 12; 
	FlagExtendTransA = 13; FlagExternalSRam = 14; FlagAbortPending = 15; FlagHandlingReqInits = 16; 

	
		(*Eprom Types, the number is also the word size of the eprom*)
	C46 = 6;  C56 = 8;
	
		(* Offsets and Periods *)
	MaxOffsetUltra2 = 7FH;
	MaxOffset16Bit = 08H;
	MaxOffset8Bit = 0FH;
	HostMsg = 0FFH;
		
	Rate = 0;  RateUltra = 1;  RateUltra2 = 2;
	
		(*HSCB Control *)
	HwScbTypeMask = 03X; HwScbMsgMask = 0F6X;
	HwScbDisconnected = 3; HwScbTagEnb = 5; HwScbDiscEnable = 6; HwScbMessage = 7;
	
		(*SCB Flags  *)
	ScbFree = 8; ScbWaitingQ = 9; ScbActive = 10; ScbAbort = 12; ScbDeviceReset = 13; 
	ScbReset = 14; ScbRecovery = 15; ScbWasBusy = 16; ScbMsgSent = 17; ScbMsgWidth = 18; ScbMsgSync = 19; 
	ScbQueuedAbort = 20; ScbQueuedForDone = 21; 
	ScbMsgMask = {ScbMsgSent, ScbMsgWidth, ScbMsgSync};
	
		(*Device Flags  *)
	DevicePresent = 0; DeviceBusResetPending = 1; DeviceTimeout = 2; DevicePrintSync = 3; DevicePrintWidth = 4; DeviceSuccess = 5; 
	DeviceTaggedSuccess = 6; DeviceScanned = 7; 

		(*Msg Types*)
	MsgTypeNone = 0; MsgTypeInitiatorMsgOut = 1; MsgTypeInitiatorMsgIn = 2;
	
		(*MachScb special parameters*)
	AllTargets = -1; AllChannels = -1; AllLuns = -1;
	
		(*SetWidth / SetSyncRate special flags*)
	TransActive = 0; TransCur = 1; TransGoal = 2;
	
(*SCSI Register Block *)
	(* 00H	SCSI Sequence Control *)	SCSISEQ = 00H;
		(* Bit 0	SCSI Reset Out *)		SCSIRSTO = 0;
		(* Bit 1	Enable Auto ATN on parity *)		ENAUTOATNP = 1;
		(* Bit 4	Enable Reselection *)		ENRSELI = 4;
		(* Bit 5	Enable Selection in *)		ENSELI = 5;
		(* Bit 6	Enable Selection out *)		ENSELO = 6;
	(* 01H	SCSI Transfer Control 0 Register *)	SXFRCTL0 = 01H;
		(* Bit 3	SCSI PIO Enable *)		SPIOEN = 3;
		(* Bit 5	*)		FAST20 = 5;
		(* Bit 7	Digital Filtering On *)		DFON = 7;
	(* 02H	SCSI Transfer Control 1 Register *)	SXFRCTL1 = 02H;
		(* Bit 0	SCSI Termination Power Enable *)		STPWEN = 0;
		(* Bit 1	Active Negation Enable *)		ACTNEGEN = 1;
		(* Bit 2	Enable Selection timeout *)		ENSTIMER = 2;
		(* Bit 5	Enable Parity Check *)		ENSPCHK = 5;
	(* 03H	SCSI Control Signal *)	SCSISIG = 03H;
		(* Bit 0	Ack *)		ACK = 0;
		(* Bit 1	*)		REQ = 1;
		(* Bit 2	*)		BSY = 2;
		(* Bit 3	*)		SEL = 3;
		(* Bit 4	*)		ATN = 4;
		(* Bit 5	*)		MSG = 5;
		(* Bit 6	*)		IO = 6;
		(* Bit 7	*)		CD = 7;
	(* 04H	SCSI Rate Control *)	SCSIRATE = 04H;
		(* Bit 7	Wide Transer control *)		WIDEXFER = 7;
	(* 05H	SCSI ID *)	SCSIID = 05H;
					SCSIOFFSET = 05H;
	(* 06H	SCSI	Data Low *)	SCSIDATL = 06H;
	(* 0BH	SCSI Status 0 *)	SSTAT0 = 0BH;
	(* 0BH	Clear SCSI Interrupt 0 *)	CLRSINT0 = 0BH;
		(* Bit 1	CLRSPIORDY *)		CLRSPIORDY = 1;
		(* Bit 3	CLRSWRAP *)		CLRSWRAP = 3;
		(* Bit 4	CLRSELINGO *)		CLRSELINGO = 4;
		(* Bit 5	CLRSELDI *)		CLRSELDI = 5;
		(* Bit 6	CLRSELDO *)		CLRSELDO = 6;
	(* 0CH	SCSI Status 1 *)	SSTAT1 = 0CH;
		(* Bit 0	*)		REQINIT = 0;
		(* Bit 2	SCSI Parity Error *)		SCSIPERR = 2;
		(* Bit 3	Bus Free Flag *)		BUSFREE = 3;
		(* Bit 5	Scsi Reset *)		SCSIRSTI = 5;
		(* Bit 7	Selection Time Out *)		SELTO = 7;
	(* 0CH	Clear SCSI Interrupt 1 *)	CLRSINT1 = 0CH;
		(* Bit 0	CLRREQINIT *)		CLRREQINIT = 0;
		(* Bit 1	CLRPHASECHG *)		CLRPHASECHG = 1;
		(* Bit 2	CLRSCSIPERR *)		CLRSCSIPERR = 2;
		(* Bit 3	CLRBUSFREE *)		CLRBUSFREE = 3;
		(* Bit 5	CLRSCSIRSTI *)		CLRSCSIRSTI = 5;
		(* Bit 6	CLRATNO *)		CLRATNO = 6;
		(* Bit 7	CLRSELTIMEO *)		CLRSELTIMEO = 7;
						CLRSINT1ALL = {0..3, 5..7};
	(* 0DH	SCSI Status 2 *)	SSTAT2 = 0DH;
		(* Bit 4	SCSI Expander Active *)		EXPACTIVE = 4;
	(* 0FH	SCSI ID for Ultra2 Chips *)	SCSIIDULTRA2 = 0FH;
	(* 10H	SCSI Interrupt Mode 0 *)	SIMODE0 = 10H;
		
	(* 11H	SCSI Interrupt Mode 1 *)	SIMODE1 = 11H;
		(* Bit 1	Enable ReqInit *)		ENREQINIT = 1;
		(* Bit 2	Enable Scsi Parity Error *)		ENSCSIPERR = 2;
		(* Bit 3	Enable Bus Free *)		ENBUSFREE = 3;
		(* Bit 5	Enable Scsi Reset *)		ENSCSIRST = 5;
		(* Bit 7	Enable Time-out *)		ENSELTIMO = 7;
	(* 12H	SCSI Bus Low *)	SCSIBUSL = 12H;
	(* 1BH	Serial Port I/O Cabability register *)	SPIOCAP = 1BH;
		(* Bit 0	 Termination and cable detection *)		SSPIOCPS = 0;
	(* 1DH	Board Control *)	BRDCTL = 1DH;
		(* Bit 0	7890 only: Board Strobe *)		BRDSTBULTRA2 = 0;
		(* Bit 1	7890 only: Board Read/Write *)		BRDRWULTRA2 = 1;
		(* Bit 2	Board Read/Write *)		BRDRW = 2;
		(* Bit 3	Board Chip Select *)		BRDCS = 3;
		(* Bit 4	Board Strobe *)		BRDSTB = 4;
	(* 1EH	Serial EEPROM Control *)	SEECTL = 1EH;
		(* Bit 0	Serial EEPROM Data In *)		SEEDI = 0;
		(* Bit 1	Serial EEPROM Data Out *)		SEEDO = 1;
		(* Bit 2	Serial EEPROM Clock *)		SEECK = 2;
		(* Bit 3	Serial EEPROM Chip Select *)		SEECS = 3;
		(* Bit 4	Serial EEPROM Ready *)		SEERDY = 4;
		(* Bit 5	Serial EEPROM Mode Select *)		SEEMS = 5;
	(* 1FH	SCSI Block Control *)	SBLKCTL = 1FH;
		(* Bit 1	Select Wide *)		SELWIDE = 1;
		(* Bit 3	SELBUSB *)		SELBUSB = 3;
		(* Bit 3	LVD transceiver active *)		ENAB40 = 3;
		(* Bit 5	Auto Flush Disable *)		AUTOFLUSHDIS = 5;
		(* Bit 6	Diagnostic LED on *)		DIAGLEDON = 6;
		(* Bit 7	Diagnostic LED Enable *)		DIAGLEDEN =7;

(* Scratch RAM *)
	(* 20H	1 byte per target starting at this address for configuration values*)	TARGSCSIRATE = 20H;
	(* 30H	Bit vector of targets that have ULTRA enabled. *)	ULTRAENB = 30H;
 	(* 32H 	Bit vector of targets that have disconnection disabled*)	DISCDSB = 32H;
 	(* 34H	buffer to designate the type or message to send to a target*)	MSGOUT = 34H;
 	(* 35H	Parameters for DMA Logic*)	DMAPARAMS = 35H;
 	(* 36H	*)		SEQFLAGS = 36H;
 	(* 37H	SAVED_TCL*)	SAVEDTCL = 37H;
 	(* 38H	SG_COUNT*)
 	(* 39H	SG_NEXT*)
 	(* 3DH	LASTPHASE*)	LASTPHASE = 3DH;
 		(* Signals are declared in SCSISIG *)		PHASEMASK = {CD, MSG, IO};
 		(* Patterns*)
 		PhaseStatus = {CD, IO};
 		PhaseCommand = {CD};
 		PhaseMsgOut = {CD, MSG};
 		PhaseMsgIn = {CD, MSG, IO};
 		PhaseDataIn = {IO};
 		PhaseDataOut = {};
 		PhaseBusFree = {0};
 	(* 3EH	WAITINGSCBH*)	WAITINGSCBH = 3EH;
 	(* 3FH	DISCONNECTEDSCBH*)	DISCONNECTEDSCBH = 3FH;
 	(* 40H	head of list of SCBs that are not in use.  Used for SCB paging*)	FREESCBH = 40H;
 	(* 41H	HSCB_ADDR*)	HSCBARRAY = 41H;
 	(* 45H	SCBID_ADDR*)	SCBIDADDR = 45H;
 	(* 49H	TMODE_CMDADDR*)	TMODECMDADDR = 49H;
 	(* 4DH	KERNEL_QINPOS*)	KERNELQINPOS = 4DH;
 	(* 4EH	QINPOS*)	QINPOS = 4EH;
 	(* 4FH	QOUTPOS*)	QOUTPOS = 4FH;
 	(* 50H	TMODE_CMDADDR_NEXT*)	TMODECMDADDRNEXT = 50H;
 	(* 51H	ARG_1 / RETURN_1*)	RETURN1 = 51H;
 		(*	Phase Mismatch *)		MSGOUTPHASEMIS = {4};
 		(* 	Send Sense *)		SENDSENSE = {6};
 		(* 	Send Msg *)		SENDMSG = {7};
 	(* 52H	ARG_2 *)
 	(* 53H	LAST_MSG*)	LASTMSG = 53H;
 	(* 54H	PREFETCH_CNT*)
 	
	(* 5AH	Scsi Configuration *)	SCSICONF = 5AH;
		(* Bit 6	Reset SCSI-Bus at boot *)		RESETSCSI = 6;
		(* Bit 7	Termination Enable *)		TERMENB = 7;
	(* 60H	Sequencer Control *)	SEQCTL = 60H;
		(* Bit 0	Load Ram *)		LOADRAM = 0;
		(* Bit 1	Reset *)		SEQRESET = 1;
		(* Bit 4	Fast Mode *)		FASTMODE = 4;
		(* Bit 5	Fail disable *)		FAILDIS = 5;
		(* Bit 7	Parity Error disable *)		PERRORDIS = 7;
	(* 61H	Sequencer RAM Data *)	SEQRAM = 61H;
	(* 62H	Sequencer Address Registers *)	SEQADDR0 = 62H;
	(* 63H	*)		SEQADDR1 = 63H;
	(* 65H	*)		SINDEX = 65H;
(* Sequencer (SCSI Phase Engine)*)
	(* 70H	1 byte per target SCSI offset values for Ultra2 controllers *)	TARGOFFSET = 70H;
(* Host Registers*)
	(* 84H	Board Control*)	BCTL = 84H;
		(* Bit 0 	Enable *)		ENABLE = 0;
	(* 84H	Device Space Command*)	DSCOMMAND0 = 84H;
		(* Bit 0	*)		CIOPARCKEN = 0;
		(* bit 1	*)		USCBSIZE32 = 1;
		(* Bit 5	Memory Parity Check Enable *)		MPARCKEN = 5;
		(* Bit 6	Data Parity Check Enable *)		DPARCKEN = 6;
		(* Bit 7	Cache Threshold Enable *)		CACHETHEN = 7;
	(* 86H	DSPCI Status *)	DSPCISTATUS = 86H;
		(*	Read when 100% empty, write when 100% full *)		DFTHRSH100 = {6, 7};
	(* 87H	Host Control, Overall host control of the device*)	HCNTRL = 87H;
		(* Bit 0	Chip Reset / Chip Reset Acknowledge *)		CHIPRST = 0;
		(* Bit 1	Interrupt Enable *)		INTEN = 1;
		(* Bit 2	Pause Enable *)		PAUSE = 2;
	(* 90H	Gate one of the four SCBs into the SCBARRAY window*)	SCBPTR = 90H;
	(* 91H	Interrupt Status *)	INTSTAT = 91H;
		(* Bit 0	Sequencer Interrupt *)		SEQINT = 0H;
		(* Bit 1	Command Completed *)		CMDCMPLT = 1H;
		(* Bit 2	Scsi Interrupt *)		SCSIINT = 2H;
		(* Bit 3	Break address *)		BRKADRINT = 3H;
		(* Interrupt Pending *)		INTPEND = {0..3};
		(* Sequencer Interrupt Mask *)		SEQINTMASK = {0, 4..7};
		(* Interrupt Values*)
			DataOverrun = 0E1H; MsgInPhaseMis = 0D1H; TracePoint2 = 0C1H;
			TracePoint = 0B1H; AwaitingMsg = 0A1H; Residual = 081H;
			BadStatus = 071H; RejectMsg = 061H; AbortRequested = 051H;
			ExtendedMsg = 041H; NoMatch = 031H; NoIdent = 021H;
			SendReject = 011H; BadPhase = 01H;
	(* 92H	Write: Clear Interrupt Status *)	CLRINT = 92H;
		(* Bit 0	Clear Sequencer Interrupt *)		CLRSEQINT = 0;
		(* Bit 1	Clear Command Complete Interrupt *)		CLRCMDINT = 1;
		(* Bit 2	Clear SCSI Interrupt *)		CLRSCSIINT = 2;
		(* Bit 3	Clear Break Address Interrupt *)		CLRBRKADRINT = 3;
		(* Bit 4	Clear Parity Errors*)		CLRPARERR = 4;
	(* 92H	Read: Hard Error *)	ERROR = 92H;
		(* Bit 0	Illegal Hardware Address *)		ILLHADDR = 0;
		(* Bit 1	Illegal Software Address *)		ILLSADDR = 1;
		(* Bit 2	Illegal Opcode Error *)		ILLOPCODE = 2;
		(* Bit 3	Sequencer Parity Error *)		SQPARERR = 3;
		(* Bit 6	Pci error *)		PCIERRSTAT = 6;
		
(* SCB Definition: this field give direct access to the scb pointed by SCBPTR*)
	(* A0H	SCB Control *)	SCBCONTROL = 0A0H;
		(* Bit 3	Disconnected*)		DISCONNECTED = 3;
		(* Bit 5	Tag Enabled*)		TAGENB = 5;
		(* Bit 6	Disconnect Enabled*)		DISCENB = 6;
	(* A1H	*)		SCBTCL = 0A1H;
	(* A2H	Target Status *)	SCBTARGETSTATUS = 0A2H;
	(* A3H	SG / Count *)	SCBSGCOUNT = 0A3H;
	(* A4H	SG / Ptr *)	SCBSGPTR = 0A4H;
	(* A8H	*)		SCBRESIDSGCNT = 0A8H;
	(* A9H	*)		SCBRESIDDCNT = 0A9H;
	(* ACH	*)		SCBDATAPTR = 0ACH;
	(* B0H	*)		SCBDATACNT = 0B0H;
	(* B4H	*)		SCBCMDPTR = 0B4H;
	(* B8H	*)		SCBCMDLEN = 0B8H;
	(* B9H	*)		SCBTAG = 0B9H;
	(* BAH	*)		SCBNEXT = 0BAH;
	(* BBH	*)		SCBPREV = 0BBH;
	(* BCH	*)		SCBBUSYTARGETS = 0BCH;
		
	(* F0H	CCSCBBADDR, 7895/6/7 only *)	CCSCBBADDR = 0F0H;
	(* F4H	Host New SCB Queue Offset *)	HNSCBQOFF = 0F4H;
	(* F6H	Sequencer New SCB Queue Offset *)	SNSCBQOFF = 0F6H;
	(* F8H	Sequencer Done SCB Queue Offset *)	SDSCBQOFF = 0F8H;
	(* FAH	Queue Offset Control & Status *)	QOFFCTLSTA = 0FAH;
		(*	Queue size = 256 *)		SCBQSIZE256 = {1, 2};
	(* FBH	Data FIFO Threshold *)	DFFTHRSH = 0FFH;
		(*	Write starts when 75% full *)		WRDFFTHRSH75 = {6};
		(*	Read starts when 75% empty *)		RDDFFTHRSH75 = {2};

(*PCI Registers*)
	(* 40H	Device Configuration *)	DEVCONFIG = 40H;
		(* Bit 2	RAMPSM_ULTRA2 7895/6 only? *)		RAMPSMULTRA2 = 2;
		(* Bit 3	Byte Parity Error Enable *)		BERREN = 3;
		(* Bit 3	SCBRAMSELULTRA2??? *)		SCBRAMSELULTRA2 = 3;
		(* Bit 4	External SCB Parity Enable *)		EXTSCBPEN = 4;
		(* Bit 7	SCB RAM Select,  not 7890 *)		SCBRAMSEL = 7;
		(* Bit 9	RAM Present Mode *)		RAMPSM = 9;
		(* Bit 16	SCBSIZE32, 7895 only? *)		SCBSIZE32 = 16;
		(* Bit 31	PCI Error Generation Disable *)		PCIERRGENDIS = 31;
	
	SCAMCTL = 1AH;			(*ultra2 only*)
	
	
	MaxScb = 255;	(*DON'T FORGET TO CHANGE THE SCB MASK IN THE SEQUENCER CODE IF THIS IS MODIFIED!*)
	MaxTargets = 16;
	
	ScbNull = 0FFX;  ScbNullSet = {0..15} (*=SYSTEM.VAL(SET, ScbNull)*);
	
TYPE
		(*helper structures*)
	BigSet = ARRAY 256 DIV 32 OF SET;		(* set with 256 elements*)

	Queue = RECORD
		head, tail: ScbData;
		
		(*every scb uses the queueNext field to chain into the queue*)
		(* invariant: one scb belongs always to one and only one queue *)
		
		PROCEDURE Put(scb: ScbData);
		BEGIN
			IF head = NIL THEN  head := scb; tail := scb 
			ELSE tail.next := scb
			END;
		END Put;
		
		PROCEDURE PutFirst(scb: ScbData);
		BEGIN
			IF head = NIL THEN  tail := scb  END;
			scb.next := head;
			head := scb;
		END PutFirst;
		
		PROCEDURE Get(VAR scb: ScbData);
		BEGIN
			ASSERT(head # NIL);
			scb := head; head := scb.next;
			scb.next := NIL
		END Get;
		
		PROCEDURE Remove(scb: ScbData);
		VAR	p, q: ScbData;
		BEGIN
			IF head = scb THEN
				head := scb.next
			ELSE
				p := head; q:= p.next;
				WHILE (q # NIL) & (q # scb) DO	p := q; q := q.next	END;
				IF q # NIL THEN  p.next := q.next  END
			END;
			scb.next := NIL
		END Remove;
		
		PROCEDURE Init;
		BEGIN  head := NIL; tail := NIL;
		END Init;
	END Queue;
	
	Timer = RECORD
		lastReset, expires: LONGINT;
	END Timer;
	
		(*SCSI Command. Used to communicate with the rest of the world*)
		(* Hardware SCB. This is the format used by the host card sequencer. 
			It's used to communicate between the driver and the sequencer.
			WARNING: avoid alignment of the fields
		*)
	long = LONGINT;	(* If the long fields are not aligned use ARRAY 4 OF CHAR *)
	HwScbDesc =  RECORD	(*aic7xxx_hwscb*)
		(* 0 *) control, 
		(* 1 *) targ, 
		(* 2 *) status, 
		(* 3 *) SGcnt: CHAR;
		(* 4 *) SGptr: long;
		(* 8 *) resSGcnt: CHAR;
		(* 9 *) resDataCnt: ARRAY 3 OF CHAR;
		(* 12 *) dataPtr: long;
		(* 16 *) dataCnt: long;
		(* 20 *) cmdPtr: long;
		(* 24 *) cmdLen: CHAR;
		(* 25 *) tag,
		(* 26 *) next,
		(* 27 *) prev: CHAR;
		(* 28 *) par: long;
	END;
	
	ScbData = POINTER TO RECORD
		tag: CHAR;	(*scb tag, index for hwscb*)
		flags: SET;
		tagAction: CHAR;
		next: ScbData;	(* used for the queues *)
		cmd: RECORD target, chan, lun, status, result: SHORTINT; cmd, data, ptrToCmd: LONGINT END;(*Copy of Cmd relevant fields*)
(*
		cmd: SCSI.Command;
*)
	END (*ScbDataDesc*);
	
	
	Host = POINTER TO HostDesc;
	Put1Proc = PROCEDURE (d: Host; offset: LONGINT; val: SET);
	Get1Proc = PROCEDURE (d: Host; offset: LONGINT): SET;

	DeviceDesc = RECORD
		curOffset, curPeriod, goalOffset, goalPeriod: LONGINT;
		commandsSent, commandsActive,
		lastQueueFull, lastQueueFullCount,
		maxQueueDepth, tempQueueDepth: INTEGER;
		flags: SET;
		delayed: Queue;
		timer: Timer
	END;
	
	Msg = RECORD
		index, len, type: SHORTINT;
		buf: ARRAY 9 OF CHAR
	END;

CONST	RecordPadding =  32-16;

TYPE
	HostDesc = RECORD (SCSI.DriverDesc)
		padding: ARRAY RecordPadding OF CHAR;
		hwscb: ARRAY 256 OF HwScbDesc;		(*must be aligned to 32!*)
		
			(*hw communication*)
		Put1: Put1Proc;
		Get1: Get1Proc;
		
			(*scb informations*)
		allocated, active: INTEGER;
		wait: Queue;
		freeList: BigSet;
		scb: ARRAY 256 OF ScbData;
			(*ugly implementation of a buffer, but the sequencer takes the address of
			   untagged and __assumes__ that the in-queue is at +100H and the out-queue at +200H offset.
			   This prevents the use of an abstract data structure here!
			 *)
		untagged, out, in: ARRAY 256 OF CHAR;
		inNext, outNext: INTEGER;
		
			(*bord configuration*)
		flags, features: SET;
		adapterCtrl: SET;		(*as read from the EEPROM*)
		epromSize, epromType: SHORTINT;
		chip, irq, scsiId, scsiIdB: SHORTINT;
		iobase, membase: LONGINT;
		interruptable: BOOLEAN;
		
			(*devices configuration*)
		dev: ARRAY 16 OF DeviceDesc;
		disconnect, ultra, tagged, orderedQueue: SET;
		curWidth, goalWidth: SET;		(*clear = 8 bit, set = 16 bit. No support for 32 bit *)
		needWidthTrasm, widthPending, needSyncTrasm, syncPending: SET;
		(*needSyncTrasmCopy: SET;*)
		
			(*debug, trace*)
		intCount, spuriousInt: LONGINT;
		
		(*cache, pre-computed values*)
		pause, unpause: SET;	(*values for HCTRL*)
		nofTargets: SHORTINT;	(* 8 or 16*)
		msg: Msg;
		
		(*other*)
		maxScb: LONGINT;	(*nof scbs supported on this card*)
		lastReset: LONGINT;
		
		next: Host;
	END HostDesc;
	
	EISAHost = POINTER TO EISAHostDesc;
	EISAHostDesc = RECORD (HostDesc)
	END EISAHostDesc;
	
	VLHost = POINTER TO VLHostDesc;
	VLHostDesc = RECORD (HostDesc)
	END VLHostDesc;
	
	PCIHost = POINTER TO PCIHostDesc;
	PCIHostDesc = RECORD (HostDesc)
		busNo, devNo, slot: LONGINT;
	END PCIHostDesc;

	DNames = ARRAY 32, 32 OF CHAR;
	
VAR
	HostRoot: Host;
	
	(*Global Data*)
	SyncRate: ARRAY 14 OF RECORD  rate: ARRAY 3 OF SHORTINT; period: LONGINT  END;
	ResetDelay: LONGINT;
	
	InstalledIRQ: SET;
	(*timerTask: Oberon.Task;*)
	nofTimers: LONGINT;
	
	NoQueue: Queue;
	
	(*Debug*)
	jiffies, TimerTimeout, HZ: LONGINT;
	DFlag, DFeat, DDev, DChip: DNames;
	
	(*Tracing*)
	DebugTrace, DebugTraceInts, DebugMsg, DebugSCB, DebugSequencer,
	DebugReset, DebugConfig, DebugPeriod, DebugCmds: BOOLEAN;
	

(*Debug Functions --------------------------------------------------*)
PROCEDURE DumpChar(ch: CHAR);
CONST
	num = ORD("0");  char = ORD("A")-10;
VAR	byte: LONGINT;
BEGIN
	byte := ORD(ch);
	IF (byte DIV 16) < 10 THEN  Kernel.WriteChar(CHR(byte DIV 16+num)) ELSE Kernel.WriteChar(CHR(byte DIV 16+char)) END;
	IF (byte MOD 16) < 10 THEN  Kernel.WriteChar(CHR(byte MOD 16+num)) ELSE Kernel.WriteChar(CHR(byte MOD 16 +char)) END
END DumpChar;

PROCEDURE DumpBool(b: BOOLEAN);
BEGIN IF b THEN Kernel.WriteString("TRUE") ELSE Kernel.WriteString("FALSE") END
END DumpBool;
(*
PROCEDURE DumpFlag(i: LONGINT; s: SET; ch: CHAR);
BEGIN
	IF i IN s THEN Texts.Write(W, ch) END;
END DumpFlag;

PROCEDURE DumpByte(d: Host; name: ARRAY OF CHAR; byte: LONGINT);
CONST
	num = ORD("0");  char = ORD("A")-10;
BEGIN
	byte := SYSTEM.VAL(LONGINT, d.Get1(d, byte) * {0..7});
	Texts.WriteString(W, name);
	IF (byte DIV 16) < 10 THEN  Texts.Write(W, CHR(byte DIV 16+num)) ELSE Texts.Write(W, CHR(byte DIV 16+char)) END;
	IF (byte MOD 16) < 10 THEN  Texts.Write(W, CHR(byte MOD 16+num)) ELSE Texts.Write(W, CHR(byte MOD 16 +char)) END;
END DumpByte;

PROCEDURE DHost(d: Host);
VAR	Targets, i: LONGINT;
BEGIN
	Texts.WriteString(W, d.name); Texts.WriteLn(W);
	Texts.Write(W, 9X); Texts.WriteString(W, "Flags: "); DumpSet(d.flags, DFlag); Texts.WriteLn(W);
	Texts.Write(W, 9X); Texts.WriteString(W, "Feat: "); DumpSet(d.features, DFeat); Texts.WriteLn(W);
	IF d IS PCIHost THEN
		Texts.Write(W, 9X); Texts.WriteString(W, "PCI: ");
		Texts.WriteInt(W, d(PCIHost).busNo, 5); Texts.WriteInt(W, d(PCIHost).devNo, 5);
		Texts.WriteInt(W, d(PCIHost).slot, 5); Texts.WriteLn(W)
	END;
	
	IF FeatWide IN d.features THEN  Targets := 16  ELSE Targets := 8  END;
	FOR i := 0 TO Targets -1 DO
		IF (DevicePresent IN d.dev[i].flags) THEN
			Texts.Write(W, 9X); Texts.Write(W, 9X);
			Texts.WriteInt(W, i, 2);
			Texts.Write(W, " "); DumpSet(d.dev[i].flags, DDev); Texts.WriteLn(W);
			Texts.Write(W, 9X); Texts.Write(W, 9X);
			IF i IN d.disconnect THEN Texts.Write(W, "D")  ELSE  Texts.Write(W, " ")  END;
			IF i IN d.ultra THEN Texts.Write(W, "U")  ELSE  Texts.Write(W, " ")  END;
			Texts.Write(W, " "); 
			IF i IN d.curWidth THEN Texts.Write(W, "W")  ELSE  Texts.Write(W, "w")  END;
			IF i IN d.goalWidth THEN Texts.Write(W, "W")  ELSE  Texts.Write(W, "w")  END;
			IF i IN d.needWidthTrasm THEN Texts.Write(W, "+")  ELSE  Texts.Write(W, " ")  END;
			Texts.Write(W, " ");
			
			Texts.WriteInt(W, d.dev[i].curOffset, 2); Texts.Write(W, "/"); Texts.WriteInt(W, d.dev[i].goalOffset, 2);
			Texts.Write(W, " ");
			Texts.WriteInt(W, d.dev[i].curPeriod, 2); Texts.Write(W, "/"); Texts.WriteInt(W, d.dev[i].goalPeriod, 2);
			IF i IN d.needSyncTrasm THEN Texts.Write(W, "n")  ELSE  Texts.Write(W, " ")  END;
			IF i IN d.needSyncTrasmCopy THEN Texts.Write(W, "c")  ELSE  Texts.Write(W, " ")  END;
			IF i IN d.syncPending THEN Texts.Write(W, "c")  ELSE  Texts.Write(W, " ")  END;
			Texts.WriteLn(W)
		END;
	END;
	Texts.Append(Oberon.Log, W.buf)
END DHost;

PROCEDURE DList*;
VAR	p: Host;
BEGIN
	p := HostRoot;
	WHILE p # NIL DO  DHost(p);  p := p.next  END
END DList;

PROCEDURE DStateP*(sp: SCSI.Driver);
VAR	p: Host;
BEGIN
	p := sp(Host);
	Texts.WriteString(W, p.name); Texts.WriteLn(W);
	DumpByte(p, "SCSISEQ ", SCSISEQ); DumpByte(p, "  HCNTRL ", HCNTRL); 
	DumpByte(p, "  SEQCTL ", SEQCTL); DumpByte(p, "  SEQADDR1 ", SEQADDR1);
	DumpByte(p, "  SEQADDR0 ", SEQADDR0); Texts.WriteLn(W);
	DumpByte(p, " SSTAT0 ", SSTAT0); DumpByte(p, "  SSTAT1 ", SSTAT1);
	DumpByte(p, "  INTSTAT ", INTSTAT); Texts.WriteLn(W);
	DumpByte(p, "SCSISIG ", SCSISIG); DumpByte(p, "  QINPOS ", QINPOS); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
END DStateP;

PROCEDURE DState*;
VAR	p: Host;
BEGIN
	p := HostRoot;
	WHILE p # NIL DO  DStateP(p); p := p.next  END;
END DState;
*)

PROCEDURE -WriteDriver(d: Host);
BEGIN	Kernel.WriteString("scsi"); Kernel.WriteInt(d.number,0); Kernel.WriteChar(" ")
END WriteDriver;

PROCEDURE -WriteDevice(d: Host; target: LONGINT);
BEGIN
	Kernel.WriteString("scsi"); Kernel.WriteInt(d.number,0);
	Kernel.WriteChar("."); Kernel.WriteInt(target,0); Kernel.WriteChar(" ")
END WriteDevice;

(* ========================================================================*)
(* ============================Timer + Interrupts==============================*)
(* ========================================================================*)
(*
PROCEDURE TimerHandler(me: Oberon.Task);
BEGIN
	d := HostRoot;
	WHILE d # NIL DO
		i := 0;
		WHILE i < 16 DO
			IF d.dev[i].timer.expires = -1 THEN	(*skip*)
			ELSIF d.dev[i].timer.expires = 0 THEN 	(*expired*)
				DEC(nofTimers);
				IF nofTimers = 0 THEN  Oberon.Remove(me)  END;
				.....
			ELSE  DEC(d.dev[i].timer.expires)
			END;
			INC(i)
		END;
		d := d.next
	END;
END TimerHandler;
*)

PROCEDURE AddTimer;
BEGIN
	HALT(TimerUnimplemented);
	(*INC(nofTimers);
	IF nofTimers = 1 THEN  Oberon.Install(timerTask)  END;*)
END AddTimer;

(* ========================================================================*)
(* ============================Helper Functions===============================*)
(* ========================================================================*)

(* GetEntry - Find first entry in the list and remove it *)

PROCEDURE GetEntry(VAR set: ARRAY OF SET): LONGINT;
VAR	i, j: LONGINT;
BEGIN
	i := 0;
	WHILE (i < LEN(set)) & (set[i] = {}) DO
		INC(i)
	END;
	IF i = LEN(set) THEN
		RETURN -1
	ELSE
		j := 0;
		WHILE ~(j IN set[i]) DO  INC(j)  END;
		EXCL(set[i], j);
		RETURN i*32+j
	END
END GetEntry;

(* SetEntry - Insert entry in the list *)

PROCEDURE SetEntry(VAR s: ARRAY OF SET; x: INTEGER);
BEGIN
	ASSERT(~((x MOD 32) IN s[x DIV 32]));
	INCL(s[x DIV 32], x MOD 32)
END SetEntry;

(* ========================================================================*)
(* =================LOW LEVEL I/O FUNCTIONS, installed into the driver============*)
(* ========================================================================*)
PROCEDURE PortPut(d: Host;  off: LONGINT; val: SET);
BEGIN
	IF ~DebugNoWrites THEN
		SYSTEM.PORTOUT(d.iobase+off, SYSTEM.VAL(CHAR, val))
	END
END PortPut;

PROCEDURE MemoryPut(d: Host;  off: LONGINT; val: SET);
BEGIN
	IF ~DebugNoWrites THEN
		SYSTEM.PUT(d.membase+off, SYSTEM.VAL(CHAR, val))
	END
END MemoryPut;

PROCEDURE PortGet(d: Host; off: LONGINT): SET;
VAR	val: SET;
BEGIN	SYSTEM.PORTIN(d.iobase+off, SYSTEM.VAL(CHAR, val));  RETURN val
END PortGet;

PROCEDURE MemoryGet(d: Host; off: LONGINT): SET;
VAR	val: SET;
BEGIN	SYSTEM.GET(d.membase+off, SYSTEM.VAL(CHAR, val));  RETURN val
END MemoryGet;


PROCEDURE Put4(d: Host; off, val: LONGINT);
VAR  s: SET;
BEGIN
	s := SYSTEM.VAL(SET, val);
	d.Put1(d, off, s);
	d.Put1(d, off+1, SYSTEM.LSH(s, -8));
	d.Put1(d, off+2, SYSTEM.LSH(s, -16));
	d.Put1(d, off+3, SYSTEM.LSH(s, -24));
END Put4;


PROCEDURE Delay(ms: LONGINT);		(*wait ~t ms. Assume TimeUnit=1000*)
VAR t: Kernel.MilliTimer;
BEGIN
	Kernel.SetTimer(t, ms);
	REPEAT UNTIL Kernel.Expired(t)
END Delay;


(* Set Functions for Integers *)
PROCEDURE Merge(d: Host; low, high: LONGINT): SET;
BEGIN	RETURN
	d.Get1(d, low) +
	SYSTEM.VAL(SET, SYSTEM.ROT(SYSTEM.VAL(LONGINT,d.Get1(d, high)),8))
END Merge;

PROCEDURE -CAND(VAR a: CHAR; b: CHAR);
CODE {SYSTEM.i386}
	POP EAX
	POP EBX
	AND 0[EAX], BL
END CAND;

PROCEDURE -COR(VAR a: CHAR; b: CHAR);
CODE {SYSTEM.i386}
	POP EBX
	POP EAX
	AND 0[EAX], BL
END COR;

PROCEDURE -CCLRBIT(VAR a: CHAR; b: SHORTINT);
CODE {SYSTEM.i386}
	POP EBX
	POP EAX
	AND EBX, 7		;security
	BTR 0[EAX], EBX
END CCLRBIT;

PROCEDURE -CSETBIT(VAR a: CHAR; b: SHORTINT);
CODE {SYSTEM.i386}
	POP EBX
	POP EAX
	AND EBX, 7		;security
	BTS 0[EAX], EBX
END CSETBIT;

PROCEDURE -CBIT(a: CHAR; b: SHORTINT):BOOLEAN;
CODE {SYSTEM.i386}
	POP EBX
	POP EAX
	AND EAX, 0FFH
	BT	EAX, EBX
	SETB AL
END CBIT;

(* Rate/Period conversions *)
	(* index refers to the rate table! target is target + channel*8*)
PROCEDURE SetSyncRate(d: Host; index: LONGINT; target, channel, period, offset: LONGINT; type: SET);
	(* aic7xxx_set_syncrate *)
VAR	rate: SET;
BEGIN
	IF DebugTrace OR DebugPeriod THEN
		Kernel.WriteString("SetSyncRate "); Kernel.WriteInt(index, 4); Kernel.WriteInt(period, 4);
		Kernel.WriteInt(offset, 4); Kernel.WriteLn
	END;
	ASSERT(channel IN {0, 1}, 120);
	target := target + channel*8;
	ASSERT((index # 1) OR (period = 0) & (offset = 0), 121); (* removes IF index = -1 .... *)
	IF TransCur IN type THEN
		rate := d.Get1(d, TARGSCSIRATE + target) * {WIDEXFER};
		IF FeatUltra2 IN d.features THEN
			IF index # -1 THEN  rate := rate + SYSTEM.VAL(SET,SyncRate[index].rate[RateUltra2]) * {0..7}  END;
			IF TransActive IN type THEN
				d.Put1(d, SCSIRATE, rate);
				d.Put1(d, SCSIOFFSET, SYSTEM.VAL(SET, offset))
			END;
			d.Put1(d, TARGSCSIRATE+target, rate);
			d.Put1(d, TARGOFFSET+target, SYSTEM.VAL(SET, offset))
		ELSE
			EXCL(d.ultra, target);
			IF  index >= 5 THEN	(* in the normal range *)
				rate := rate + SYSTEM.VAL(SET, SyncRate[index].rate[Rate]) * {0..7};
			ELSIF index # -1 THEN	(* in the ultra range *)
				INCL(d.ultra, target);
				rate := rate + SYSTEM.VAL(SET, SyncRate[index].rate[RateUltra]) * {0..7};
			END;
			rate := rate + SYSTEM.VAL(SET, offset) * {0..3};
			IF TransActive IN type THEN
				d.Put1(d, SCSIRATE, rate);
				IF target IN d.ultra THEN
					d.Put1(d, SXFRCTL0, d.Get1(d, SXFRCTL0) + {FAST20})
				ELSE
					d.Put1(d, SXFRCTL0, d.Get1(d, SXFRCTL0) - {FAST20})
				END
			END;
			d.Put1(d, TARGSCSIRATE+target, rate);
			d.Put1(d, ULTRAENB, d.ultra);
			d.Put1(d, ULTRAENB+1, SYSTEM.LSH(d.ultra, -8))
		END;
		d.dev[target].curPeriod := period;
		d.dev[target].curOffset := offset;
	END;
	IF TransGoal IN type THEN
		d.dev[target].goalPeriod := period;
		d.dev[target].goalOffset := offset
	END;
END SetSyncRate;

PROCEDURE SetWidth(d: Host; target, channel, lun: LONGINT; wide: BOOLEAN; flags: SET);	(* aic7xxx_set_width *)
VAR index: LONGINT; rate: SET;
BEGIN
	index := target + channel*8;
	IF TransCur IN flags THEN
		rate := d.Get1(d, TARGSCSIRATE + index);
		IF wide THEN  INCL(rate, WIDEXFER) ELSE  EXCL(rate, WIDEXFER)  END;
		d.Put1(d, TARGSCSIRATE + index, rate);
		IF TransActive IN flags THEN  d.Put1(d, SCSIRATE, rate)  END
	END;
	IF TransGoal IN flags THEN
		IF wide THEN INCL(d.goalWidth, index)  ELSE  EXCL(d.goalWidth, index)  END
	END;
	
	IF d.dev[index].goalOffset = 0 THEN	(*skip*)
	ELSIF FeatUltra2 IN d.features THEN
		d.dev[index].goalOffset := MaxOffsetUltra2
	ELSIF wide THEN
		d.dev[index].goalOffset := MaxOffset16Bit
	ELSE	
		d.dev[index].goalOffset := MaxOffset8Bit
	END
END SetWidth;

PROCEDURE FindPeriod(IsUltra2, IsUltra: BOOLEAN;  rate: LONGINT): LONGINT;
VAR  idx, pos: LONGINT;
BEGIN
	IF (*DebugTrace OR*) DebugPeriod THEN
		Kernel.WriteString("FindPeriod "); DumpBool(IsUltra2); DumpBool(IsUltra); Kernel.WriteInt(rate, 4)
	END;
	ASSERT(~(IsUltra2 & IsUltra));
	rate := rate MOD 80H;	(*clear wide bit*)
	IF IsUltra2 THEN
		idx := RateUltra2; pos := 0
	ELSIF  IsUltra  THEN
		rate := rate DIV 10H * 10H;
		idx := RateUltra; pos := 2
	ELSE
		rate := rate DIV 10H * 10H;
		idx := Rate; pos := 5
	END;
	WHILE (SyncRate[pos].period # 0) DO
		IF rate = SyncRate[pos].rate[idx] THEN 
			IF (*DebugTrace OR*) DebugPeriod THEN
				Kernel.WriteString(" -> "); Kernel.WriteInt(SyncRate[pos].period, 4); Kernel.WriteLn
			END;
			RETURN SyncRate[pos].period
		END;
		INC(pos)
	END;
	IF (*DebugTrace OR*) DebugPeriod THEN
		Kernel.WriteString(" -> "); Kernel.WriteInt(0, 4); Kernel.WriteLn
	END;
	RETURN 0	(*async*)
END FindPeriod;

PROCEDURE FindSyncrate(IsUltra2, IsUltra: BOOLEAN; period: LONGINT): LONGINT; (* aic7xxx_find_syncrate *)
VAR  idx, pos: LONGINT;
BEGIN
	ASSERT(~(IsUltra2 & IsUltra));
	IF (*DebugTrace OR*) DebugPeriod THEN
		Kernel.WriteString("FindSyncRate "); DumpBool(IsUltra2); DumpBool(IsUltra); Kernel.WriteInt(period, 4)
	END;
	IF IsUltra2 THEN  idx := RateUltra2; pos := 0  ELSIF  IsUltra  THEN  idx := RateUltra; pos := 2  ELSE  idx := Rate; pos := 5  END;
	REPEAT
		IF period <= SyncRate[pos].period THEN
			IF (*DebugTrace OR*) DebugPeriod THEN
				Kernel.WriteString(" -> "); Kernel.WriteInt(SyncRate[pos].rate[idx], 4); Kernel.WriteLn
			END;
			RETURN pos
		END;
		INC(pos)
	UNTIL SyncRate[pos].rate[idx] = -1;
	IF (*DebugTrace OR*) DebugPeriod THEN
		Kernel.WriteString(" -> "); Kernel.WriteInt(0, 4); Kernel.WriteLn
	END;
	RETURN -1
END FindSyncrate;

PROCEDURE RunWaitingQueue(d: Host);		(* aic7xxx_run_waiting_queues *)
VAR  index, dst, sent: LONGINT; scb: ScbData;
BEGIN
	sent := 0;
	WHILE d.wait.head # NIL DO
		d.wait.Get(scb); index := ORD(scb.tag);
		dst := scb.cmd.target + scb.cmd.chan * 8;
		IF (scb.tagAction = 0X) & (dst IN d.tagged) THEN
			d.dev[dst].tempQueueDepth := 1
		END;
		IF (d.dev[dst].commandsActive >= d.dev[dst].tempQueueDepth) OR 
			(d.dev[dst].timer.lastReset >= (jiffies - 4 * HZ)) THEN
			d.dev[dst].delayed.Put(scb);
			IF (d.dev[dst].timer.expires = -1) & (d.dev[dst].commandsActive = 0) THEN
				d.dev[dst].timer.expires := TimerTimeout;
				AddTimer
			END
		ELSE
			EXCL(scb.flags, ScbWaitingQ);
			INC(d.dev[dst].commandsActive);
			IF (scb.tagAction = 0X) THEN
				d.untagged[ORD(d.hwscb[index].targ)] := CHR(index)		(*aic7xxx_busy_target*)
			END;
(*
Kernel.WriteString("SCB "); Kernel.WriteInt(ORD(scb.tag), 3);
Kernel.WriteString(" -> in @ "); Kernel.WriteInt(d.inNext, 3); Kernel.WriteLn;
*)
			IF DebugSCB THEN  Kernel.WriteString("SCB "); Kernel.WriteInt(ORD(scb.tag), 3);
				Kernel.WriteString(" -> in @ "); Kernel.WriteInt(d.inNext, 3);
				Kernel.WriteLn; (*Kernel.WriteMemory(SYSTEM.ADR(d.hwscb[ORD(scb.tag)]), 32); Kernel.WriteLn*)  END;
			d.in[d.inNext] := scb.tag; d.inNext := (d.inNext+1) MOD 256;
			INC(sent)
		END
	END;
	IF sent > 0 THEN
		IF DebugSCB THEN  Kernel.WriteString("INPOS =  "); Kernel.WriteInt(d.inNext, 3); Kernel.WriteLn  END;
		IF FeatQueueRegs IN d.features THEN
			d.Put1(d, HNSCBQOFF, SYSTEM.VAL(SET, d.inNext))
		ELSE
			Pause(d);
			d.Put1(d, KERNELQINPOS, SYSTEM.VAL(SET, d.inNext));
			Unpause(d)
		END
	END
END RunWaitingQueue;

(* ========================================================================*)
(* ==========================Sequencer======================================*)
(* ========================================================================*)
(*PROCEDURE DumpSequencer(d: Host);
VAR data: ARRAY 512 OF CHAR; i, j: LONGINT;
BEGIN
	d.Put1(d, SEQCTL, {PERRORDIS,LOADRAM,FAILDIS,FASTMODE});
	d.Put1(d, SEQADDR0, {}); d.Put1(d, SEQADDR1, {});
	FOR i := 0 TO 31 DO
		data[i] := SYSTEM.VAL(CHAR, d.Get1(d, SEQRAM));
		IF i MOD 4 = 3 THEN SYSTEM.GET(SYSTEM.ADR(data[i - 3]), j); Script.OutInstr(W, j) END;
	END;
	d.Put1(d, SEQCTL, {FASTMODE,SEQRESET});
END DumpSequencer;*)

PROCEDURE LoadSequencer(d: Host);		(*aic7xxx_loadseq, aic7xxx_download_instr*)
VAR  i: LONGINT; line: SET;
BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  LoadSequencer"); Kernel.WriteLn  END;
	(*Set the configuration for the patches*)
	Script.Init(FeatUltra2 IN d.features, FeatUltra IN d.features, FeatWide IN d.features, FeatTwin IN d.features,
				FlagPageSCB IN d.flags, FeatQueueRegs IN d.features, FeatCmdChan IN d.features);
	i := 0;
	d.Put1(d, SEQCTL, {PERRORDIS,LOADRAM,FAILDIS,FASTMODE});
	d.Put1(d, SEQADDR0, {}); d.Put1(d, SEQADDR1, {});
	WHILE Script.GetNext(line) DO
		d.Put1(d, SEQRAM, line);	(*byte 0*)
		d.Put1(d, SEQRAM, SYSTEM.LSH(line, -8));	(*byte 1*)
		d.Put1(d, SEQRAM, SYSTEM.LSH(line, -16));	(*byte 2*)
		d.Put1(d, SEQRAM, SYSTEM.LSH(line, -24));	(*byte 3*)
		INC(i)
	END;
	IF DebugSequencer THEN
		WriteDriver(d); Kernel.WriteString("Sequencer: "); Kernel.WriteInt(i, 4); 
		Kernel.WriteString(" lines loaded"); Kernel.WriteLn
	END;
	d.Put1(d, SEQCTL, {FASTMODE,SEQRESET});
END LoadSequencer;


(* ========================================================================*)
(* ==========================SEEPROM Functions==============================*)
(* ========================================================================*)
PROCEDURE AquireSeeprom(d: Host): BOOLEAN;
VAR t: Kernel.MilliTimer;
BEGIN
	Kernel.SetTimer(t, 1000);		(*max wait: 1 sec*)
	d.Put1(d, SEECTL, {SEEMS});
	REPEAT  UNTIL  (SEERDY IN d.Get1(d, SEECTL))  OR  Kernel.Expired(t);
	IF ~(SEERDY IN d.Get1(d, SEECTL)) THEN
		d.Put1(d, SEECTL, {});		(*release seeprom*)
		RETURN FALSE
	END;
	RETURN TRUE
END AquireSeeprom;

PROCEDURE LoadSeeprom(d: Host);
CONST
(*
	Eeprom configuration:

	HostFlags:*)
		(*bit 0..2	Syncronous Transfer Rate / CFXFER*)
		(*bit 3	enable synchronous transfer	*) CFSYNCH = 3;
		(*bit 4	enable disconnection	*) CFDISC = 4;
		(*bit 5	wide bus device (wide card)	*) CFWIDEB = 5;
		(*bit 6	CFSYNC is an ultra offset /	*) CFSYNCHISULTRA = 6;
		(*bit 7	unused*)
		(*bit 8	send start unit SCSI command	*) CFSTART = 8;
		(*bit 9	include in BIOS scan	*) CFINCBIOS = 9;
		(*bit10	report even if not found	*) CFRNFOUND = 10;
		(*bit11	probe mult luns in BIOS scan	*) CFMULTILUN = 11;
	(*Bios Control Bits:*)
		(*bit 0	support all removable drives	*) CFSUPREM = 0;
		(*bit 1	support removable drives for boot only	*) CFSUPREMB = 1;
		(*bit 2	BIOS enabled	*) CFBIOSEN = 2;
		(*bit 4	support more than two drives	*) CFSM2DRV = 4;
		(*bit 5	extended translation (284x cards)	*) CF284XEXTEND = 5;
		(*bit 7	extended translation enabled	*) CFEXTEND = 7;
	(*Host Adapter Control Bits:*)
		(*bit 0	Perform Auto termination	*) CFAUTOTERM = 0+16;
		(*bit 1	Ultra SCSI speed enable (Ultra cards)	*) CFULTRAEN = 1+16;
		(*bit 2	Selection timeout (284x cards)	*) CF284XSELTO = 2+16;
		(*bit 3	SCSI low byte termination	*) CFSTERM = 3+16;
		(*bit 4	SCSI high byte termination (wide card)	*) CFWSTERM = 4+16;
		(*bit 5	SCSI parity	*) CFSPARITY = 5+16;
		(*bit 6	SCSI low byte termination (284x cards)	*) CF284XSTERM = 6+16;
		(*bit 7	reset SCSI bus at boot	*) CFRESETB = 7+16;
		(*bit 8	Channel B primary on 7895 chipsets	*) CFBPRIMARY = 8+16;
		(*bit 10	aic7890 Perform SE Auto Term	*) CFSEAUTOTERM = 10+16;
		(*bit 11	aic7890 LVD Termination	*) CFLVDSTERM = 11+16;
	
TYPE
	SeepromConfig = RECORD
		Flags: ARRAY 16 OF INTEGER;
		Control: SET;
		BrTime, MaxTargets: INTEGER;
		Res1: ARRAY 11 OF INTEGER;
		Checksum: INTEGER;
	END;
	
VAR	BiosRun, Present: BOOLEAN; config: SeepromConfig;
		i, SRamRate, MaxTargets: LONGINT; s, Sync, ScsiConf: SET;  cur: Host;
		
	PROCEDURE SendBits(x, nr: LONGINT);
	VAR bit: SET;
	BEGIN
		WHILE nr > 0 DO
			DEC(nr);
			IF ODD(SYSTEM.LSH(x, -nr)) THEN  bit := {SEEDO}  ELSE bit := {}  END;
			d.Put1(d, SEECTL,  {SEEMS, SEECS} + bit );
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
			d.Put1(d, SEECTL,  {SEEMS, SEECS, SEECK} + bit);
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
		END
	END SendBits;
	
	PROCEDURE ReceiveBits(VAR x: LONGINT;  nr: LONGINT);
	VAR	s: SET;
	BEGIN
		s := {};
		WHILE nr > 0 DO
			DEC(nr);
			d.Put1(d, SEECTL,  {SEEMS, SEECS});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
			IF SEEDI IN d.Get1(d, SEECTL) THEN  INCL(s, nr)  END;
			d.Put1(d, SEECTL,  {SEEMS, SEECS, SEECK});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
		END;
		x := SYSTEM.VAL(LONGINT, s)
	END ReceiveBits;

	PROCEDURE ReadSeeprom(VAR a: SeepromConfig; len, chip: LONGINT): BOOLEAN;
	VAR	k, x, t, offset: LONGINT; checksum: INTEGER;
	BEGIN
		IF ~AquireSeeprom(d) THEN  RETURN FALSE  END;
		checksum := 0;
		IF FlagChnlB IN d.flags THEN  offset := 20H
		ELSIF FlagChnlC IN d.flags THEN  offset := 40
		ELSE  offset := 0
		END;
		FOR k := 0 TO len-1 DO
			d.Put1(d, SEECTL, {SEEMS, SEECS, SEECK});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
			SendBits(6H, 3);	(*send 110 *)
			SendBits(k+offset, chip);
			ReceiveBits(x, 17);	(*read 17 bits, first bit is a 0*)
			SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(a)+k*2, 2);
			IF k < len-1 THEN INC(checksum, SHORT(x)) END;
				(* reset *)
			d.Put1(d, SEECTL, {SEEMS});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
			d.Put1(d, SEECTL, {SEEMS, SEECK});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
			d.Put1(d, SEECTL, {SEEMS});
			REPEAT  UNTIL  SEERDY IN d.Get1(d, SEECTL);
		END;
		d.Put1(d, SEECTL, {});		(*release seeprom*)
		RETURN checksum = SHORT(x)
	END ReadSeeprom;

BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  LoadSeeprom"); Kernel.WriteLn  END;
	(*decide if the device has an eeprom*)
	IF (d.chip = AIC7770) & (d IS EISAHost) THEN
		IF TERMENB IN d.Get1(d, SCSICONF) THEN  INCL(d.flags, FlagTermEnbA)  END;
		IF (FeatTwin IN d.features) & (TERMENB IN d.Get1(d, SCSICONF+1)) THEN  INCL(d.flags, FlagTermEnbB)  END;
	ELSIF (d.chip = AIC7770) & (d IS VLHost) THEN
		HALT(99)
	ELSE
		Present := ReadSeeprom(config, d.epromSize, d.epromType);
		IF ~Present THEN
			Present := ReadSeeprom(config, d.epromSize, C56+C46-d.epromType)
		END
	END;
	IF DebugConfig & Present THEN  WriteDriver(d); Kernel.WriteString("  EEPROM found"); Kernel.WriteLn END;
	IF ~Present THEN
		BiosRun := d.Get1(d, SCSISEQ) # {};
		INCL(d.flags, FlagNewEepromFMT);
		IF ~BiosRun THEN
			EXCL(d.flags, FlagBiosEnabled);
			d.scsiId := 7;  d.scsiIdB := 7;
			d.flags := d.flags + {FlagTermEnbSELow, FlagTermEnbSEHigh};
			config.Control := config.Control + {CFSTERM, CFWSTERM, CFLVDSTERM} - {CFAUTOTERM};
		ELSIF  STPWEN IN d.Get1(d, SXFRCTL1)  THEN
			d.flags := d.flags + {FlagTermEnbSELow, FlagTermEnbSEHigh};
			config.Control :=config.Control + {CFSTERM, CFWSTERM, CFLVDSTERM} - {CFAUTOTERM};
		END
	ELSE
		INCL(d.flags, FlagSeepromFound);
		d.scsiId := SHORT(config.BrTime MOD 16);
		IF d.chip = AIC7770 THEN
			IF CF284XEXTEND IN config.Control THEN  INCL(d.flags, FlagExtendTransA)  END;
			IF CF284XSTERM IN config.Control THEN  d.flags := d.flags + {FlagTermEnbSELow, FlagTermEnbSEHigh}  END
		ELSE
			IF CFEXTEND IN config.Control THEN  INCL(d.flags, FlagExtendTransA)  END;
			IF CFBIOSEN IN config.Control THEN  INCL(d.flags, FlagBiosEnabled)
			ELSE  EXCL(d.flags, FlagBiosEnabled)  END;
			IF CFSTERM IN config.Control THEN  d.flags := d.flags + {FlagTermEnbSELow, FlagTermEnbSEHigh}  END
		END
	END;
	
	MaxTargets := config.MaxTargets MOD 100H;
	IF (MaxTargets > 16) & ({FeatTwin, FeatWide} * d.features # {}) THEN  MaxTargets:=16
	ELSIF MaxTargets > 8 THEN  MaxTargets := 8
	END;
	
	d.disconnect := {};  d.ultra := {};  Sync := {};
	
	(* Card Configuration Disconnect, Ultra, Wide, Sync *)
	IF Present THEN		(* Config from EEPROM *)
		FOR i := 0 TO MaxTargets-1 DO
			s := SYSTEM.VAL(SET, config.Flags[i]);
			IF CFDISC IN s THEN
				INCL(d.disconnect, i)
			END;
			IF CFSYNCH IN s THEN
				INCL(Sync, i)
			END;
			IF CFULTRAEN IN config.Control  THEN
				INCL(d.ultra, i)
			ELSIF (FeatUltra IN d.flags) & (CFSYNCHISULTRA IN s) THEN
				INCL(d.flags, FlagNewEepromFMT);
				INCL(d.ultra, i)
			END;
		END
	ELSIF BiosRun THEN	(* Config from ScratchRAM/BIOS *)
		d.disconnect := -Merge(d, DISCDSB, DISCDSB+1);
		d.ultra := Merge(d, ULTRAENB, ULTRAENB+1);
		FOR i := 0 TO MaxTargets-1 DO
			IF FeatUltra2 IN d.flags THEN
				IF d.Get1(d, TARGOFFSET+i) # {} THEN
					INCL(Sync, i);
				END
			ELSIF d.Get1(d, TARGSCSIRATE+i) - {WIDEXFER} # {} THEN
				INCL(Sync, i);
			END
		END
	ELSE							(* just use defaults *)
		d.disconnect := {0..MaxTargets};
		Sync := {0..MaxTargets};
		IF FeatUltra IN d.features THEN  d.ultra := {0..MaxTargets}  END;
	END;
	
	(* Device Rate, Offset *)
	FOR i := 0 TO MaxTargets-1 DO
		SRamRate := config.Flags[i] MOD 8;
			(*offset*)
		IF ~(i IN Sync) THEN	(*asynch*)
			ASSERT(~(i IN d.ultra));
			d.dev[i].goalOffset := 0;  d.dev[i].goalPeriod := 0;
			d.dev[i].curOffset := 0;  d.dev[i].curPeriod := 0
		ELSIF FeatUltra2 IN d.features THEN
			d.dev[i].goalOffset := MaxOffsetUltra2;
			d.dev[i].curOffset := SYSTEM.VAL(SHORTINT, d.Get1(d, TARGOFFSET+i));		(*from Scratch RAM*)
			IF i IN d.ultra THEN  INC(SRamRate, 18H)  ELSE INC(SRamRate, 10H) END
		ELSIF CFWIDEB IN SYSTEM.VAL(SET, config.Flags[i]) THEN
			d.dev[i].goalOffset := MaxOffset16Bit
		ELSE
			d.dev[i].goalOffset := MaxOffset8Bit
		END;
			(*period*)
		IF (i IN Sync) THEN
			d.dev[i].goalPeriod := FindPeriod(FeatUltra2 IN d.features, i IN d.ultra, SRamRate);
			d.dev[i].curPeriod := FindPeriod(FeatUltra2 IN d.features, i IN d.ultra, SYSTEM.VAL(LONGINT, d.Get1(d, TARGSCSIRATE+i)));
			INCL(d.needSyncTrasm, i)
		END;
		
		IF (FeatWide IN d.features) & (CFWIDEB IN SYSTEM.VAL(SET, config.Flags[i]))  THEN
		    INCL(d.goalWidth, i); INCL(d.needWidthTrasm, i)
		END;
		IF WIDEXFER IN d.Get1(d, TARGSCSIRATE+i)  THEN  INCL(d.curWidth, i)  END;
	END;
	
	d.Put1(d, DISCDSB, -d.disconnect);  d.Put1(d, DISCDSB+1, SYSTEM.LSH(-d.disconnect, -8));

	IF Present THEN
		d.adapterCtrl := config.Control;
		
		IF d.chip IN {AIC7895, AIC7896} THEN
			IF CFBPRIMARY IN config.Control THEN  INCL(d.flags, FlagChannelBPrimary)  END;
				(* make sure the channel B primary flag is set properly on 7895 controllers,
					We also have to catch the fact that when you disable the BIOS on the 7895 on the Intel DK440LX
					motherboard, and possibly others, it only sets the BIOS disabled bit on the A channel *)
			IF d(PCIHost).devNo # 0 THEN	(*find the a channel*)
				cur := HostRoot;
				WHILE cur # d DO
					IF (cur IS PCIHost) & (d(PCIHost).busNo = cur(PCIHost).busNo) & (d(PCIHost).slot = cur(PCIHost).slot) THEN
						ASSERT(cur(PCIHost).devNo = 0);
						IF FlagChannelBPrimary IN cur.flags THEN  INCL(d.flags, FlagChannelBPrimary)  END;
						IF FlagBiosEnabled IN cur.flags THEN  INCL(d.flags, FlagBiosEnabled)  ELSE  EXCL(d.flags, FlagBiosEnabled)  END
					END;
					cur := cur.next
				END
			END;
		END;
		ScsiConf := SYSTEM.VAL(SET, d.scsiId);
		IF (CFSPARITY IN config.Control) THEN  INCL(ScsiConf, ENSPCHK)  END;
	ELSE
		ScsiConf := {ENSPCHK, RESETSCSI}
	END;
	IF d IS PCIHost THEN
		d.Put1(d, SCSICONF, ScsiConf);  d.Put1(d, SCSICONF+1, SYSTEM.VAL(SET, d.scsiId))
	END
END LoadSeeprom;



(*Useful procedures, often used*)
PROCEDURE Pause(d: Host);
BEGIN
	IF DebugTrace THEN  Kernel.WriteString("Adaptec7.Pause")  END;
	d.Put1(d, HCNTRL, d.pause);
	WHILE ~(PAUSE IN d.Get1(d, HCNTRL)) DO  END;
END Pause;

PROCEDURE Unpause(d: Host);
BEGIN
	IF DebugTrace THEN  Kernel.WriteString("Adaptec7.Unpause")  END;
	IF ~(FlagHandlingReqInits IN d.flags) THEN
		IF DebugTrace THEN  Kernel.WriteString("*")  END;
		d.Put1(d, HCNTRL, d.unpause)
	END;
	IF DebugTrace THEN  Kernel.WriteLn  END;
END Unpause;

(* ========================================================================*)
(* ============================Board Control=================================*)
(* ========================================================================*)
PROCEDURE WriteBoardCtrl(d: Host; s: SET);	(* write_brdctl *)
VAR	x: SET;
BEGIN
	ASSERT((d.chip # AIC7895) OR (FeatUltra2 IN d.features));		(*I did a simplification: assume 7895 is never Ultra2!*)
	IF FeatUltra2 IN d.features THEN
		d.Put1(d, BRDCTL, {});  Delay(1);
		d.Put1(d, BRDCTL, s);  Delay(1);
		d.Put1(d, BRDCTL, s+{BRDSTBULTRA2});  Delay(1);
		d.Put1(d, BRDCTL, {});  Delay(1)
	ELSE
		x := {BRDSTB, BRDCS};
		IF (d.chip = AIC7895) & ~(FlagChnlB IN d.flags) THEN  x := {BRDSTB}  END;
		d.Put1(d, BRDCTL, x);  Delay(1);
		x := x + s;
		d.Put1(d, BRDCTL, x);  Delay(1);
		d.Put1(d, BRDCTL, x-{BRDSTB});  Delay(1);
		d.Put1(d, BRDCTL, x-{BRDSTB, BRDCS});  Delay(1)
	END;
END WriteBoardCtrl;

PROCEDURE ReadBoardCtrl(d: Host): SET;		(* read_brdctl *)
VAR	x: SET; t: LONGINT;
BEGIN
	ASSERT((d.chip # AIC7895) OR (FeatUltra2 IN d.features));		(*I did a simplification!*)
	IF FeatUltra2 IN d.features THEN
		d.Put1(d, BRDCTL, {BRDRWULTRA2}); Delay(1);
	ELSIF (d.chip = AIC7895) & ~(FlagChnlB IN d.flags) THEN
		d.Put1(d, BRDCTL, {BRDRW}); Delay(1);
	ELSE
		d.Put1(d, BRDCTL, {BRDRW, BRDCS}); Delay(1);
	END;
	x := d.Get1(d, BRDCTL);
	d.Put1(d, BRDCTL, {});  Delay(1);
	RETURN x
END ReadBoardCtrl;

(* ========================================================================*)
(* ======================Termination Handling=================================*)
(* ========================================================================*)
PROCEDURE ConfigureTermination(d: Host);		(* configure_termination *)

CONST
(*
	Eeprom configuration:*)
	(*Host Adapter Control Bits:*)
		(*bit 0	Perform Auto termination	*) CFAUTOTERM = 0+16;
		(*bit 3	SCSI low byte termination	*) CFSTERM = 3+16;
		(*bit 4	SCSI high byte termination (wide card)	*) CFWSTERM = 4+16;
		(*bit 10	aic7890 Perform SE Auto Term	*) CFSEAUTOTERM = 10+16;
		(*bit 11	aic7890 LVD Termination	*) CFLVDSTERM = 11+16;
VAR  SEHigh, SELow, LVDHigh, LVDLow, Int50, Int68, Ext, Wide: BOOLEAN;  xctrl1, BrdDat: SET;
	PROCEDURE Ultra2TermDetect;
	VAR	s: SET;
	BEGIN
		Int50 := FALSE; Int68 := Wide; Ext := TRUE;
		s := ReadBoardCtrl(d);
		IF  CFSEAUTOTERM IN d.adapterCtrl  THEN
			SEHigh := 6 IN s;  SELow := 5 IN s
		ELSE
			SELow := CFSTERM IN d.adapterCtrl;
			SEHigh := CFWSTERM IN d.adapterCtrl
		END;
		IF  CFAUTOTERM IN d.adapterCtrl  THEN
			LVDHigh := 4 IN s;  LVDLow := 3 IN s
		ELSE
			LVDLow := CFLVDSTERM IN d.adapterCtrl; LVDHigh := LVDLow
		END;
	END Ultra2TermDetect;
	
	PROCEDURE AIC787xCableDetect;
	VAR s: SET;
	BEGIN
		WriteBoardCtrl(d, {});  s := ReadBoardCtrl(d);
		Int50 := ~(6 IN s);
		Int68 := ~(7 IN s) & Wide;
		WriteBoardCtrl(d, {5});  s := ReadBoardCtrl(d);
		Ext := ~(6 IN s);
		IF Int50 & Int68 & Ext THEN
			Int50 := FALSE; Ext := FALSE; SEHigh := TRUE; SELow := TRUE
		END;
	END AIC787xCableDetect;
	
	PROCEDURE AIC785xCableDetect;
	VAR s: SET; t: LONGINT;
	BEGIN
		d.Put1(d, BRDCTL, {BRDRW, BRDCS});  Delay(1);
		d.Put1(d, BRDCTL, {});  Delay(1);
		s := d.Get1(d, BRDCTL);  Delay(1);
		Int50 := ~(5 IN s);
		Ext := ~(6 IN s);
	END AIC785xCableDetect;
BEGIN
	IF AquireSeeprom(d) THEN
		BrdDat := {};
		xctrl1 := d.Get1(d, SXFRCTL1);
		Wide := (FeatWide IN d.features) OR (FeatTwin IN d.features);
		d.Put1(d, SEECTL, {SEEMS, SEECS});
		EXCL(xctrl1, STPWEN);
		IF (CFAUTOTERM IN d.adapterCtrl) OR (FeatUltra2 IN d.features) THEN
			IF FeatUltra2 IN d.features THEN
				Ultra2TermDetect;
			ELSIF d.chip >= AIC7870 THEN
				AIC787xCableDetect;
			ELSE
				AIC785xCableDetect
			END;
			
			IF Wide & ( ~Ext OR ~Int68 OR SEHigh) THEN
				INCL(BrdDat, 6);
				INCL(d.flags, FlagTermEnbSEHigh)
			END;
			IF ~(Int68 OR Ext) OR ~(Int50 OR (Int68 & Ext)) THEN	(*none or only one of the flags*)
				IF FeatUltra2 IN d.features THEN  INCL(BrdDat, 5)
				ELSE INCL(xctrl1, STPWEN)
				END;
				INCL(d.flags, FlagTermEnbSELow)
			END;
			IF LVDLow THEN
				INCL(xctrl1, STPWEN);
			END;
			IF LVDHigh THEN  INCL(BrdDat, 4)  END
		ELSE
			IF (*CFSTERM*)3+16 IN d.adapterCtrl THEN
				IF FeatUltra2 IN d.features THEN   INCL(BrdDat, 5)  ELSE  INCL(xctrl1, STPWEN)  END
			END;
			IF (*CFWSTERM*)4+16 IN d.adapterCtrl THEN  INCL(BrdDat, 6)  END
		END;
		WriteBoardCtrl(d, BrdDat);
		d.Put1(d, SEECTL, {});		(*release seeprom*)
		d.Put1(d, SXFRCTL1, xctrl1)
	END
END ConfigureTermination;

(* ========================================================================*)
(* ========================Interrupt Handling=================================*)
(* ========================================================================*)
PROCEDURE ClearPCIInt(d: PCIHost);
CONST	DPR = 0;  RMA = 5;  RTA = 4;
VAR	res, dw: LONGINT;
BEGIN
	res := PCI.ReadConfigByte(d.busNo, d.devNo, d.slot, 7H, dw);
	res := PCI.WriteConfigByte(d.busNo, d.devNo, d.slot, 7H, dw);
	IF {DPR, RMA, RTA} * SYSTEM.VAL(SET, dw) # {} THEN
		d.Put1(d, CLRINT, {CLRPARERR})
	END;
END ClearPCIInt;

PROCEDURE PCIInt(d: PCIHost);
VAR  res, dw: LONGINT;
BEGIN
	res := PCI.ReadConfigByte(d.busNo, d.devNo, d.slot, PCI.DevReg+3, dw);
	res := PCI.WriteConfigByte(d.busNo, d.devNo, d.slot, PCI.DevReg+3, dw);
	IF {0, 5, 4} * SYSTEM.VAL(SET, dw) # {} THEN
		d.Put1(d, CLRINT, {CLRPARERR})
	END;
END PCIInt;

PROCEDURE ClearIntStat(d: Host);	(*aic7xxx_clear_intstat*)
BEGIN
	d.Put1(d, CLRSINT0, {CLRSELDO, CLRSELDI, CLRSELINGO});
	d.Put1(d, CLRSINT1, CLRSINT1ALL);
	d.Put1(d, CLRINT, {CLRSCSIINT, CLRSEQINT, CLRBRKADRINT, CLRPARERR})
END ClearIntStat;

PROCEDURE InterruptCmdComplete(d: Host);
VAR	index, t: LONGINT; scb: ScbData;
BEGIN
	IF DebugTraceInts THEN WriteDriver(d); Kernel.WriteString("  cmd complete-int"); Kernel.WriteLn  END;
	d.Put1(d, CLRINT, {CLRCMDINT});
	WHILE d.out[d.outNext] # ScbNull DO
		index := ORD(d.out[d.outNext]); d.out[d.outNext] := ScbNull;
		d.outNext := (d.outNext+1) MOD 256;
		scb := d.scb[index];
		IF index >= d.allocated THEN
			Kernel.WriteString("CMDCMPLT with invalid SCB index ");
			Kernel.WriteInt(index, 0); Kernel.WriteLn
		ELSIF (scb.cmd.ptrToCmd = SYSTEM.VAL(LONGINT, NIL)) THEN
			Kernel.WriteString("CMDCMPLT without command for SCB index "); Kernel.WriteInt(index, 0); Kernel.WriteLn;
		ELSIF ~(ScbActive IN scb.flags) THEN
			Kernel.WriteString("CMDCMPLT with inactive scb for SCB index "); Kernel.WriteInt(index, 0); Kernel.WriteLn;
		ELSIF (ScbQueuedAbort IN scb.flags) & (d.Get1(d, LASTPHASE) * PHASEMASK = PhaseBusFree) & 
				(SYSTEM.VAL(CHAR, d.Get1(d, SCBTAG)) = d.hwscb[index].tag) THEN
			Pause(d); Unpause(d);
		ELSE
			IF (ScbQueuedAbort IN scb.flags) THEN
				Pause(d);
				scb.flags := scb.flags - {ScbQueuedForDone, ScbReset, ScbAbort, ScbQueuedAbort};
				Unpause(d)
			ELSIF ScbAbort IN scb.flags THEN
				scb.flags := scb.flags - {ScbAbort, ScbReset}
			END;
			CASE ORD(d.hwscb[index].status) OF
			| SCSI.QueueFull, SCSI.Busy:
				d.hwscb[index].status := 0X;
				scb.cmd.result := SCSI.Good;
				scb.cmd.status := SCSI.OK
			ELSE
				IF d.hwscb[index].resSGcnt # 0X THEN
					CalculateResidual(d, scb)
				END;
				(*scb.cmd.result := scb.cmd.status;*)
				t := scb.cmd.target + scb.cmd.chan*8;
				IF scb.tagAction # 0X THEN
					d.dev[t].flags := d.dev[t].flags + {DeviceTaggedSuccess, DeviceSuccess, DevicePresent}
				ELSE
					d.dev[t].flags := d.dev[t].flags + {DeviceSuccess, DevicePresent}
				END;
				Done(d, scb)
			END
		END
	END
END InterruptCmdComplete;

PROCEDURE InterruptBrkAdr(d: Host);
VAR	errno: SET; addr: LONGINT;
BEGIN
	IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("break addr - int"); Kernel.WriteLn  END;
	errno := d.Get1(d, ERROR);
	IF PCIERRSTAT IN errno THEN  PCIInt(d(PCIHost))  END;
	IF {SQPARERR, ILLOPCODE, ILLSADDR} * errno # {} THEN
		addr := SYSTEM.VAL(LONGINT, SYSTEM.LSH(d.Get1(d, SEQADDR1),8)*{8..15} + d.Get1(d, SEQADDR0)*{0..7});
		SYSTEM.STI(); HALT(99)
	END;
	IF ILLHADDR IN errno THEN
		Kernel.WriteString("AIC7xxx.InterruptBrkAdr: BUG, driver accessed chip without pausing controller");
		Kernel.WriteLn;
	END;
	d.Put1(d, CLRINT, {CLRPARERR, CLRBRKADRINT});
	Unpause(d)
END InterruptBrkAdr;

PROCEDURE SequencerAwaitingMsg(d: Host; device: LONGINT);
	(* The SCB has MK_MESSAGE set => sequencer interrupt and wait for the message from the driver *)
VAR index: LONGINT; msg: CHAR; scb: ScbData; Ultra2: BOOLEAN;
BEGIN
	index := ORD(SYSTEM.VAL(CHAR, d.Get1(d, SEQADDR0)));
	index := index + 100*(ORD(SYSTEM.VAL(CHAR, d.Get1(d, SEQADDR1)))MOD 2);
	IF DebugTraceInts THEN  Kernel.WriteString("SequencerAwaitingMsg"); (*Kernel.WriteInt(index, 4);*) Kernel.WriteLn  END;
	index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
	msg := SYSTEM.VAL(CHAR, d.Get1(d, MSGOUT));
	scb := d.scb[index];
	d.msg.index := 0; d.msg.len := 0;
	IF ~(ScbDeviceReset IN scb.flags) & (msg = SCSI.MsgIdentifyFlag) & 
		CBIT(d.hwscb[index].control, HwScbTagEnb) THEN
		d.msg.buf[d.msg.index] := scb.tagAction;  INC(d.msg.index);
		d.msg.buf[d.msg.index] := d.hwscb[index].tag;  INC(d.msg.index);
		INC(d.msg.len, 2)
	END;
	IF ScbDeviceReset IN scb.flags THEN
		IF DebugMsg THEN WriteDevice(d, device); Kernel.WriteString(" send MsgBusDevReset"); Kernel.WriteLn  END;
		d.msg.buf[d.msg.index] := SCSI.MsgBusDevReset;  INC(d.msg.index);
		INC(d.msg.len)
	ELSIF ScbAbort IN scb.flags THEN
		IF DebugMsg THEN WriteDevice(d, device); Kernel.WriteString(" send MsgAbort"); Kernel.WriteLn  END;
		IF scb.tagAction # 0X THEN
			d.msg.buf[d.msg.index] := SCSI.MsgAbortTag;  INC(d.msg.index)
		ELSE
			d.msg.buf[d.msg.index] := SCSI.MsgAbort;  INC(d.msg.index)
		END;
		INC(d.msg.len);
	ELSIF ScbMsgWidth IN scb.flags THEN
		IF DebugMsg THEN WriteDevice(d, device); Kernel.WriteString(" SEND MsgWidth ");
			IF device IN d.goalWidth THEN Kernel.WriteString("16bit") ELSE Kernel.WriteString("8bit") END;
			Kernel.WriteLn
		END;
		d.msg.buf[d.msg.index+0] := SCSI.MsgExtended;
		d.msg.buf[d.msg.index+1] := SCSI.MsgExtWdTrLen;
		d.msg.buf[d.msg.index+2] := SCSI.MsgExtWdTr;
		IF device IN d.goalWidth THEN
			d.msg.buf[d.msg.index+3] := SCSI.MsgExtWdTr16Bit
		ELSE
			d.msg.buf[d.msg.index+3] := SCSI.MsgExtWdTr8Bit
		END;
		INC(d.msg.index, 4); INC(d.msg.len, 4)
	ELSIF ScbMsgSync IN scb.flags THEN
		d.msg.buf[d.msg.index+0] := SCSI.MsgExtended;
		d.msg.buf[d.msg.index+1] := SCSI.MsgExtSdTrLen;
		d.msg.buf[d.msg.index+2] := SCSI.MsgExtSdTr;
		d.msg.buf[d.msg.index+3] := CHR(d.dev[device].goalPeriod);
		d.msg.buf[d.msg.index+4] := CHR(d.dev[device].goalOffset);
		IF DebugMsg THEN
			WriteDevice(d, device); Kernel.WriteString(" SEND MsgSync ");
			Kernel.WriteInt(ORD(d.msg.buf[d.msg.index+3]), 3);
			Kernel.WriteChar("/"); Kernel.WriteInt(ORD(d.msg.buf[d.msg.index+4]), 3);
			Kernel.WriteLn
		END;
		INC(d.msg.index, 5); INC(d.msg.len, 5)
	ELSE
		(* awaiting an unexpected message *)
		SYSTEM.STI(); HALT(99)
	END;
	INCL(scb.flags, ScbMsgSent);
	d.msg.index := 0;
	d.msg.type := MsgTypeInitiatorMsgOut;
	INCL(d.flags, FlagHandlingReqInits);
	d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) + {ENREQINIT});
	RETURN
END SequencerAwaitingMsg;

PROCEDURE ParseMsg(d: Host; scb: ScbData): BOOLEAN;		(* aic7xxx_parse_msg *)
VAR target, chan, lun: SHORTINT; done, reply, reject, width, u, u2: BOOLEAN; index, period, offset, oldOffset, syncrate: LONGINT;
	PROCEDURE ValidateOffset(d: Host; VAR syncrate, offset: LONGINT; wide: BOOLEAN);
	BEGIN
		IF syncrate = -1 THEN
			offset := 0
		ELSIF FeatUltra2 IN d.features THEN
			IF offset > MaxOffsetUltra2 THEN offset := MaxOffsetUltra2 END
		ELSIF wide THEN
			IF offset > MaxOffset16Bit THEN offset := MaxOffset16Bit END
		ELSE
			IF offset > MaxOffset8Bit THEN offset := MaxOffset8Bit END
		END
	END ValidateOffset;
	
BEGIN
	target := scb.cmd.target; chan := scb.cmd.chan; lun := scb.cmd.lun;
	reply := FALSE; done := FALSE;
	index := target + chan*8;
	
	reject := d.msg.buf[0] # SCSI.MsgExtended;
	IF ~reject & (d.msg.len > 2) THEN
		CASE d.msg.buf[2] OF
		| SCSI.MsgExtSdTr:
			IF d.msg.buf[1] # SCSI.MsgExtSdTrLen THEN
				IF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" MsgSync rejected"); Kernel.WriteLn END;
				reject := TRUE
			ELSIF d.msg.len < ORD(SCSI.MsgExtSdTrLen)+2 THEN
				RETURN FALSE	(*message incomplete*)
			ELSE
				(*IF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" MsgSync accepted"); Kernel.WriteLn END;*)
				done := TRUE;
				period := ORD(d.msg.buf[3]);
				offset := ORD(d.msg.buf[4]); oldOffset := offset;
WriteDevice(d, index);
Kernel.WriteString(" SET Sync "); Kernel.WriteInt(period, 3); 
Kernel.WriteChar("/"); Kernel.WriteInt(offset, 3); 
Kernel.WriteLn;
				u2 := (FeatUltra2 IN d.features) & (ENAB40 IN d.Get1(d, SBLKCTL)) & ~(EXPACTIVE IN d.Get1(d, SSTAT2));
				u := (FeatUltra IN d.features) OR ~u2 & (FeatUltra2 IN d.features);
				syncrate := FindSyncrate(u2, u, period);
				ValidateOffset(d, syncrate, offset, WIDEXFER IN d.Get1(d, TARGSCSIRATE+index));
				SetSyncRate(d, syncrate, target, chan, period, offset, {TransActive, TransCur});
				IF offset = 0 THEN
					SetSyncRate(d, syncrate, target, chan, period, offset, {TransGoal});
					(*EXCL(d.needSyncTrasmCopy, index)*)
				END;
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" - sync (ParseMsg)"); Kernel.WriteLn  END;
				EXCL(d.needSyncTrasm, index);  EXCL(d.syncPending, index);
				IF (ScbMsgSent IN scb.flags) & (ScbMsgSync IN scb.flags) & (offset = oldOffset) THEN
					scb.flags := scb.flags - ScbMsgMask
				ELSE
					IF ~(DeviceScanned IN d.dev[index].flags) THEN
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" + sync + width (ParseMsg)"); Kernel.WriteLn  END;
						INCL(d.needWidthTrasm, index); INCL(d.needSyncTrasm(*Copy*), index)
					END;
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" resend sync message"); Kernel.WriteLn  END;
					scb.flags := scb.flags - ScbMsgMask + {ScbMsgSync};
					d.Put1(d, MSGOUT, SYSTEM.VAL(SET, HostMsg));
					d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN});
				END;
				done := TRUE
			END
		| SCSI.MsgExtWdTr:
			IF d.msg.buf[1] # SCSI.MsgExtWdTrLen THEN
				IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" MsgWidth rejected"); Kernel.WriteLn END;
				reject := TRUE
			ELSIF d.msg.len < ORD(SCSI.MsgExtWdTrLen)+2 THEN
				RETURN FALSE	(*message incomplete*)
			ELSE
				(*IF DebugMsg THEN Kernel.WriteString("MsgWidth accepted"); Kernel.WriteLn END;*)
				IF (ScbMsgSent IN scb.flags) & (ScbMsgWidth IN scb.flags) THEN
WriteDevice(d, index);
					IF d.msg.buf[3] = SCSI.MsgExtWdTr16Bit THEN
Kernel.WriteString(" SET Width 16 bit"); Kernel.WriteLn;
						width := TRUE;
					ELSE
Kernel.WriteString(" SET Width 8 bit"); Kernel.WriteLn;
						reject := d.msg.buf[3] # SCSI.MsgExtWdTr8Bit;
						width := FALSE;
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" - width (ParseMsg)"); Kernel.WriteLn  END;
						EXCL(d.needWidthTrasm, index)
					END;
					scb.flags := scb.flags - ScbMsgMask;
					EXCL(d.widthPending, index);
					EXCL(d.needWidthTrasm, index)
				ELSE
					scb.flags := scb.flags - ScbMsgMask + {ScbMsgWidth};
					reply := TRUE;
					IF ~(DeviceScanned IN d.dev[index].flags) THEN
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" + sync + width (ParseMsg)"); Kernel.WriteLn  END;
						INCL(d.needWidthTrasm, index); INCL(d.needSyncTrasm(*Copy*), index)
					END;
					IF (d.msg.buf[3] = SCSI.MsgExtWdTr16Bit) & (FeatWide IN d.features) & (index IN d.goalWidth) THEN
						width := TRUE
					ELSE
						width := FALSE;
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" - width (ParseMsg)"); Kernel.WriteLn  END;
						EXCL(d.needWidthTrasm, index)
					END;
					EXCL(d.widthPending, index);
					EXCL(d.needWidthTrasm, index);
					d.Put1(d, MSGOUT, SYSTEM.VAL(SET, HostMsg));
					d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
				END;
				SetWidth(d, target, chan, lun, width, {TransActive, TransCur});
				SetSyncRate(d, -1, target, chan, 0, 0, {TransActive, TransCur});
(*
				IF (index IN d.needSyncTrasmCopy) & ~(index IN d.syncPending) THEN
					INCL(d.needSyncTrasm, index);
					IF ~reject & ~reply THEN
						scb.flags := scb.flags - ScbMsgMask;
						IF d.dev[index].goalPeriod = 0 THEN
							INCL(d.syncPending, index);
							INCL(scb.flags, ScbMsgSync);
							d.Put1(d, MSGOUT, SYSTEM.VAL(SET, HostMsg));
							d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
						END
					END
				END;
*)
				done := TRUE
			END
		ELSE
			IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" Unknown Msg, reject"); Kernel.WriteLn END;
			reject := TRUE
		END
	END;
	IF reject THEN
		d.Put1(d, MSGOUT, SYSTEM.VAL(SET, SCSI.MsgMessageReject));
		d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
	END;
	RETURN done OR reject
END ParseMsg;

PROCEDURE HandleReqInit(d: Host; scb: ScbData);	(* aic7xxx_handle_reqinit *)
VAR	done, phasemis: BOOLEAN; ch: CHAR; index, target: LONGINT;
BEGIN
	target := scb.cmd.target;
	IF DebugTraceInts & (d.msg.index = 0) THEN  Kernel.WriteString("Int Scsi / Req Init ")  END;
	IF d.msg.type = MsgTypeInitiatorMsgOut THEN
		ASSERT(d.msg.len # 0, 110);
		done := d.msg.index = d.msg.len-1;
		phasemis := (d.Get1(d, SCSISIG) * PHASEMASK) # PhaseMsgOut;
		IF done THEN
			(*IF DebugMsg THEN DumpChar(d.msg.buf[d.msg.index]) END;*)
			d.Put1(d, SINDEX, SYSTEM.VAL(SET, d.msg.buf[d.msg.index]));
			d.Put1(d, RETURN1, {})
		ELSIF phasemis THEN
			IF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" msg -> PHASE MISMATCH"); Kernel.WriteLn END;
			d.Put1(d, RETURN1, MSGOUTPHASEMIS)
		ELSE
			(*IF DebugMsg THEN DumpChar(d.msg.buf[d.msg.index]); Kernel.WriteChar("-") END;*)
			d.Put1(d, CLRSINT1, {CLRREQINIT}); d.Put1(d, CLRINT, {CLRSCSIINT});
			d.Put1(d, SCSIDATL, SYSTEM.VAL(SET, d.msg.buf[d.msg.index]));
			INC(d.msg.index)
		END
	ELSIF d.msg.type = MsgTypeInitiatorMsgIn THEN
		phasemis := (d.Get1(d, SCSISIG) * PHASEMASK) # PhaseMsgIn; done := FALSE;
		IF ~phasemis THEN
			INC(d.msg.len);
			d.msg.buf[d.msg.index] := SYSTEM.VAL(CHAR, d.Get1(d, SCSIBUSL));
			(*IF DebugMsg THEN DumpChar(d.msg.buf[d.msg.index]) END;*)
			done := ParseMsg(d, scb);
			d.Put1(d, CLRSINT1, {CLRREQINIT}); d.Put1(d, CLRINT, {CLRSCSIINT});
			ch := SYSTEM.VAL(CHAR, d.Get1(d, SCSIDATL));
			INC(d.msg.index)
		ELSIF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" msg <- PHASE MISMATCH"); Kernel.WriteLn 
		END
	ELSE  Kernel.WriteString("Unknown REQINIT message type"); Kernel.WriteLn; HALT(99)
	END;
	IF phasemis OR done THEN	(*last byte sent, now terminate*)
		(*IF DebugMsg THEN Kernel.WriteLn END;*)
		d.msg.len := 0; d.msg.index := 0; d.msg.type := MsgTypeNone;
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENREQINIT});
		d.Put1(d, CLRINT, {CLRSCSIINT});
		EXCL(d.flags, FlagHandlingReqInits);
		Unpause(d)
	END
END HandleReqInit;

PROCEDURE HandleDeviceReset(d: Host; target, channel: LONGINT);		(* handle_device_reset *)
VAR index: LONGINT;
BEGIN
	IF DebugTrace THEN Kernel.WriteString("Adaptec7.HandleDeviceReset"); Kernel.WriteLn  END;
	index := target + channel*8;
	IF (d.dev[index].goalOffset#d.dev[index].curOffset)OR(d.dev[index].goalPeriod#d.dev[index].curPeriod) THEN
		INCL(d.needSyncTrasm, index);
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" + sync (DevReset)"); Kernel.WriteLn  END;
	ELSE
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" - sync (DevReset)"); Kernel.WriteLn  END;
		EXCL(d.needSyncTrasm, index)
	END;
	d.needWidthTrasm := d.needWidthTrasm-{index} + {index}*(d.curWidth/d.goalWidth);
	EXCL(d.syncPending, index);
	EXCL(d.widthPending, index);
	d.Put1(d, TARGSCSIRATE+index, {});
	IF FeatUltra2 IN d.features THEN	d.Put1(d, TARGOFFSET+index, {})	END;
	ResetDevice(d, target, channel, AllLuns, ScbNull);
	IF DebugReset THEN  Kernel.WriteString("Bus Device Reset delivered"); Kernel.WriteLn END;
	RunDoneQueue(d)
END HandleDeviceReset;

PROCEDURE InterruptSequencer(d: Host; intStatS: SET);	(* handle_seqint *)
VAR t, i, device, target, channel, lun, index, sindex, cur, last, intstat: LONGINT; (*cmd: SCSI.Command;*)
	scb, lastScb: ScbData; active, prev, next: SET; msg, ch: CHAR; Ultra2: BOOLEAN;
BEGIN
	t := SYSTEM.VAL(LONGINT, d.Get1(d, SAVEDTCL));
	target := SYSTEM.LSH(t, -4) MOD 16; device := target;
	IF (d.chip = AIC7770) & (SELBUSB IN d.Get1(d, SBLKCTL)) THEN
		channel := 1; INC(device, 8)
	ELSE
		channel := 0
	END;
	lun := t MOD 7;
	d.Put1(d, CLRINT, {CLRSEQINT});
	intstat := SYSTEM.VAL(LONGINT, intStatS * SEQINTMASK);
	
	CASE intstat OF
	| NoMatch:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / NoMatch"); Kernel.WriteLn  END;
		d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) * {ENSELI, ENRSELI, ENAUTOATNP})
	| SendReject:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / SendReject"); Kernel.WriteLn  END;
	| NoIdent:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / NoIdent"); Kernel.WriteLn  END;
		ResetChannel(d, channel, TRUE); RunDoneQueue(d)
	| BadPhase:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / BadPhase"); Kernel.WriteLn  END;
		IF d.Get1(d, LASTPHASE) = PhaseBusFree THEN
			d.Put1(d, SEQCTL, {FASTMODE, SEQRESET})
		END
	| ExtendedMsg:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / ExtendedMsg"); Kernel.WriteLn  END;
		d.msg.type := MsgTypeInitiatorMsgIn;
		d.msg.len := 0; d.msg.index := 0;
		INCL(d.flags, FlagHandlingReqInits);
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) + {ENREQINIT});
		RETURN
	| RejectMsg:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / RejectMsg"); Kernel.WriteLn  END;
		index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
		msg := SYSTEM.VAL(CHAR, d.Get1(d, LASTMSG));
		IF (msg = SCSI.MsgIdentifyFlag) & (d.scb[index].tagAction # 0X) & (ScbMsgMask * d.scb[index].flags = {}) THEN
			IF (d.scb[index].tagAction = SCSI.MsgOrderedQTag) & (DeviceTaggedSuccess IN d.dev[device].flags) THEN
				EXCL(d.orderedQueue, device);
				d.scb[index].tagAction := SCSI.MsgSimpleQTag;
				CAND(d.hwscb[index].control, HwScbMsgMask);
				COR(d.hwscb[index].control, SCSI.MsgSimpleQTag);
				d.Put1(d, SCBCONTROL, SYSTEM.VAL(SET, d.hwscb[index].control));
				d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
			ELSIF (d.scb[index].tagAction = SCSI.MsgSimpleQTag) & ~(DeviceTaggedSuccess IN d.dev[device].flags) THEN
				EXCL(d.tagged, device);
				EXCL(d.orderedQueue, device);
				d.dev[device].maxQueueDepth := 1;
				d.dev[device].tempQueueDepth := 1;
				d.scb[index].tagAction := 0X;
				CCLRBIT(d.hwscb[index].control, HwScbTagEnb);
				CAND(d.hwscb[index].control, HwScbMsgMask);
				d.Put1(d, SCBCONTROL, SYSTEM.VAL(SET, d.hwscb[index].control));
				i := 0;
				WHILE i < 256 DO
					IF (ScbActive IN d.scb[i].flags) & (i # index) THEN
						IF MatchScb(d, i, target, channel, lun, CHR(i)) THEN
							ResetDevice(d, target, channel, lun, CHR(i))
						END;
						RunDoneQueue(d)
					END;
					INC(i)
				END;
				d.untagged[ORD(d.hwscb[index].targ)] := CHR(index);
				d.Put1(d, MSGOUT, SYSTEM.VAL(SET, SCSI.MsgIdentifyFlag));
				d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
			END
		ELSIF ScbMsgWidth IN d.scb[index].flags THEN
			EXCL(d.needWidthTrasm, device);
			EXCL(d.widthPending, device);
			d.scb[index].flags := d.scb[index].flags - ScbMsgMask;
			SetWidth(d, target, channel, lun, FALSE, {TransActive, TransCur});
			SetSyncRate(d, -1, target, channel, 0, 0, {TransActive, TransCur});
(*
			IF (device IN d.needSyncTrasmCopy) & ~(device IN d.syncPending) THEN
				INCL(d.syncPending, device);
				INCL(d.scb[index].flags, ScbMsgSync);
				d.Put1(d, MSGOUT, SYSTEM.VAL(SET, HostMsg));
				d.Put1(d, SCSISIG, d.Get1(d, SCSISIG) + {ATN})
			END
*)
		ELSIF ScbMsgSync IN d.scb[index].flags THEN
IF DebugMsg THEN WriteDevice(d, device); Kernel.WriteString(" - sync (InterruptSeq/RejectMsg)"); Kernel.WriteLn  END;
			EXCL(d.needSyncTrasm, device);
			(*EXCL(d.needSyncTrasmCopy, device);*)
			EXCL(d.syncPending, device);
			EXCL(d.scb[index].flags, ScbMsgSync);
			SetSyncRate(d, -1, target, channel, 0, 0, {TransActive, TransCur})
		END
	| BadStatus:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / BadStatus")  END;
		d.Put1(d, RETURN1, {});
		index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
		(*cmd := d.scb[index].cmd;*)
		IF (ScbActive IN d.scb[index].flags)  & (d.scb[index].cmd.ptrToCmd # 0) THEN
			d.hwscb[index].status := SYSTEM.VAL(CHAR, d.Get1(d, SCBTARGETSTATUS));
			d.scb[index].cmd.status := SYSTEM.VAL(SHORTINT, d.hwscb[index].status);
			d.scb[index].cmd.result := d.scb[index].cmd.status;
			CASE d.scb[index].cmd.result OF
			| SCSI.Good:
				IF DebugTraceInts THEN  Kernel.WriteString(" / Good"); Kernel.WriteLn  END;
			| SCSI.CommandTerminated, SCSI.CheckCondition:
					IF DebugTraceInts THEN  Kernel.WriteString(" / Term or Condition"); Kernel.WriteLn  END;
					scb := d.scb[index];
					IF d.hwscb[index].resSGcnt # 0X THEN
						CalculateResidual(d, scb)
					END;
					scb.tagAction := 0X;
					d.untagged[ORD(d.hwscb[index].targ)] := CHR(index);
			| SCSI.QueueFull, SCSI.Busy:
				IF DebugTraceInts THEN  Kernel.WriteString(" / QueueFull or Busy"); Kernel.WriteLn  END;
				SearchQInFifo(d, target, channel, lun, ScbNull, {}, TRUE, d.dev[device].delayed);
				IF d.wait.head # NIL THEN
					lastScb := d.wait.tail;
					REPEAT
						d.wait.Get(scb);
						IF MatchScb(d, ORD(scb.tag), target, channel, lun, ScbNull) THEN
							d.dev[device].delayed.Put(scb)
						ELSE
							d.wait.Put(scb)
						END
					UNTIL scb = lastScb;
				END;
				active := d.Get1(d, SCBPTR);
				next := d.Get1(d, WAITINGSCBH);
				prev := ScbNullSet; sindex := ORD(ScbNull);
				WHILE SYSTEM.VAL(CHAR, next) # ScbNull DO
					d.Put1(d, SCBPTR, next);
					sindex := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
					IF sindex < d.allocated THEN
						IF MatchScb(d, sindex, target, channel, lun, ScbNull) THEN
							IF ScbWaitingQ IN d.scb[sindex].flags THEN
								INC(d.dev[device].commandsActive);
								INC(d.active);		(*c says --, but here ++ seems correct to me*)
								d.dev[device].delayed.Remove(d.scb[sindex]);
								d.wait.Remove(d.scb[sindex])
							ELSE
								HALT(99);	(*where is this scb from?*)
							END;
							d.dev[device].delayed.PutFirst(d.scb[sindex]);
							INCL(d.scb[sindex].flags, ScbWaitingQ);
							DEC(d.dev[device].commandsActive);
							DEC(d.active);
							next := d.Get1(d, SCBNEXT);
							d.Put1(d, SCBCONTROL, {});
							d.Put1(d, SCBTAG, ScbNullSet);
							FreeCurScb(d);
							IF SYSTEM.VAL(CHAR, prev) = ScbNull THEN
								d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) - {ENSELO});
								d.Put1(d, CLRSINT1, {CLRSELTIMEO});
								d.Put1(d, WAITINGSCBH, next)
							ELSE
								d.Put1(d, SCBPTR, prev);
								d.Put1(d, SCBNEXT, next)
							END
						ELSE
							prev := next;
							next := d.Get1(d, SCBNEXT)
						END
					END (*sindex < d.allocated*)
				END;
				d.Put1(d, SCBPTR, active);
				IF ScbWaitingQ IN d.scb[index].flags THEN
					INC(d.dev[device].commandsActive);
					INC(d.active);
					d.dev[device].delayed.Remove(d.scb[index]);
					d.wait.Remove(d.scb[index])
				ELSE
					HALT(99);	(*where is this scb from?*)
				END;
				d.dev[device].delayed.PutFirst(d.scb[index]);
				DEC(d.dev[device].commandsActive);
				DEC(d.active);
				d.scb[index].flags := d.scb[index].flags + {ScbWaitingQ, ScbWasBusy};
				IF d.dev[device].timer.expires = 0 THEN
					IF d.dev[device].commandsActive # 0 THEN
						d.dev[device].timer.expires := jiffies + HZ*2;
						AddTimer
					ELSE
						d.dev[device].timer.expires := jiffies + HZ DIV 2;
						AddTimer
					END
				END;
				IF scb.cmd.result = SCSI.QueueFull THEN
					d.dev[device].tempQueueDepth := d.dev[device].commandsActive;
					IF d.dev[device].lastQueueFull # d.dev[device].commandsActive THEN
						d.dev[device].lastQueueFull := d.dev[device].commandsActive;
						d.dev[device].lastQueueFullCount := 0
					ELSE
						INC(d.dev[device].lastQueueFullCount)
					END;
					IF (d.dev[device].lastQueueFullCount > 14) & (d.dev[device].commandsActive > 4) THEN
						d.dev[device].maxQueueDepth := d.dev[device].commandsActive;
						d.dev[device].lastQueueFull := 0;
						d.dev[device].lastQueueFullCount := 0
					END
				END
			ELSE (*CASE cmd.result*)
				IF scb.cmd.status # SCSI.OK THEN  scb.cmd.status := SCSI.Error  END
			END (*CASE cmd.result*)
		END
	| AwaitingMsg:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / AwaitingMsg"); Kernel.WriteLn  END;
		SequencerAwaitingMsg(d, device);
	| DataOverrun:
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString("  Int Seq / DataOverrun"); Kernel.WriteLn  END;
		index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
		scb := d.scb[index];
		scb.cmd.status := SCSI.Error
	END;
	Unpause(d)
END InterruptSequencer;

PROCEDURE InterruptScsi(d: Host);	(* handle_scsiint *)
VAR	index, target, channel, scbptr, i: LONGINT; status, lastphase: SET; tag, msg: CHAR; scb: ScbData;
BEGIN
	index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
	target := SYSTEM.VAL(LONGINT, SYSTEM.LSH(d.Get1(d, SAVEDTCL), -4) * {0..3});
	lastphase := d.Get1(d, LASTPHASE);
	status := d.Get1(d, SSTAT1);
	scb := d.scb[index];
	IF (index >= d.allocated) OR ~(ScbActive IN scb.flags) THEN
		scb := NIL
	END;
	
	IF SCSIRSTI IN status THEN
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString(" scsi-int / Reset-In"); Kernel.WriteLn  END;
		channel := 0;
		IF (d.chip =AIC7770) & (SELBUSB IN d.Get1(d, SBLKCTL)) THEN  channel := 1  END;
		IF DebugReset THEN  WriteDriver(d); Kernel.WriteString(" Someone else reset the channel"); Kernel.WriteLn  END;
		ResetChannel(d, channel, FALSE);
		RunDoneQueue(d);
		scb := NIL
	ELSIF SELTO IN status THEN
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString(" scsi-int / Selection Time-out"); Kernel.WriteLn  END;
		scbptr := SYSTEM.VAL(LONGINT, d.Get1(d, WAITINGSCBH));
		IF scbptr > d.allocated THEN
			Kernel.WriteString("Invalid WAITING_SCBH value "); Kernel.WriteInt(scbptr, 1); Kernel.WriteLn;
			scbptr := d.allocated-1;
			WHILE (scbptr > 0) & (ScbActive IN d.scb[scbptr].flags) DO  DEC(scbptr)  END;
			Kernel.WriteString("Trying with "); Kernel.WriteInt(scbptr, 1); Kernel.WriteLn;
		END;
		d.Put1(d, SCBPTR, SYSTEM.VAL(SET, scbptr));
		index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
		scb := d.scb[index];
		IF (index >= d.allocated) OR ~(ScbActive IN scb.flags) THEN
			scb := NIL
		END;
		IF scb = NIL THEN
			Kernel.WriteString("Refenced SCB not valid during SELTO "); Kernel.WriteInt(index, 2); Kernel.WriteLn;
			Kernel.WriteInt(scbptr, 3); Kernel.WriteInt(d.allocated, 3); Kernel.WriteLn;
			Kernel.WriteMemory(d.membase + SCBCONTROL, 32); Kernel.WriteLn;
			Kernel.WriteMemory(d.membase, 100H); Kernel.WriteLn;
(*
			(*Kernel.WriteString("!!!!!!!!DANGER, int not reenabled !!!!!!!! ");*)
			d.Put1(d, CLRINT, {CLRSCSIINT});
			RETURN;
*)
		ELSE
			scb.cmd.status := SCSI.CommandTerminated;
			scb.cmd.result := SCSI.TimeOut;
			d.Put1(d, SCBCONTROL, {});
			d.Put1(d, MSGOUT, SYSTEM.VAL(SET, SCSI.MsgNoop));
			d.Put1(d, WAITINGSCBH, d.Get1(d, SCBNEXT));
			FreeCurScb(d);
			IF ScbQueuedAbort IN scb.flags THEN
				scb.cmd.result := SCSI.OK;
				EXCL(scb.flags, ScbQueuedAbort);
				scb := NIL
			END
		END;
		d.Put1(d, SCSISEQ, {});
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENREQINIT, ENBUSFREE});
		EXCL(d.flags, FlagHandlingReqInits);
		d.Put1(d, CLRSINT1, {CLRSELTIMEO,CLRBUSFREE});
		d.Put1(d, CLRINT, {CLRSCSIINT});
		d.Put1(d, SEQCTL, {FASTMODE, SEQRESET});
		Unpause(d)
	ELSIF (BUSFREE IN status) THEN
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString(" scsi-int / BusFree"); Kernel.WriteLn  END;
		channel := 0;
		IF (d.chip =AIC7770) & (SELBUSB IN d.Get1(d, SBLKCTL)) THEN  channel := 1  END;
		d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) * {ENSELI, ENRSELI, ENAUTOATNP});
		IF lastphase = PhaseMsgOut THEN
			msg := SYSTEM.VAL(CHAR, d.Get1(d, SINDEX));
			IF msg = SCSI.MsgAbort THEN
				ResetDevice(d, target, channel, AllLuns, ScbNull);
				RunDoneQueue(d);
				scb := NIL
			ELSIF msg = SCSI.MsgAbortTag THEN
				ResetDevice(d, target, channel, AllLuns, d.hwscb[index].tag);
				RunDoneQueue(d);
				scb := NIL
			ELSIF msg = SCSI.MsgBusDevReset THEN
				HandleDeviceReset(d, target, channel);
				scb := NIL
			END
		END;
		IF scb # NIL THEN
			IF CBIT(d.hwscb[index].control, TAGENB) THEN
				tag := d.hwscb[index].tag
			ELSE
				tag := ScbNull
			END;
			ResetDevice(d, target, channel, AllLuns, tag);
			RunDoneQueue(d)
		ELSE
			scb := NIL
		END;
		EXCL(d.flags, FlagHandlingReqInits);
		d.Put1(d, MSGOUT, SYSTEM.VAL(SET, SCSI.MsgNoop));
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENBUSFREE, ENREQINIT});
		d.Put1(d, CLRSINT1, {CLRBUSFREE});
		d.Put1(d, CLRINT, {CLRSCSIINT});
		d.Put1(d, SEQCTL, {FASTMODE, SEQRESET});
		Unpause(d)
	ELSIF scb = NIL THEN
		WriteDriver(d); Kernel.WriteString(" scsi-int / Referenced SCB not valid! "); Kernel.WriteInt(index, 0); Kernel.WriteLn;
		d.Put1(d, CLRSINT1, status);
		d.Put1(d, CLRINT, {CLRSCSIINT});
		Unpause(d)
	ELSIF SCSIPERR IN status THEN
		IF DebugTraceInts THEN  WriteDriver(d); Kernel.WriteString(" scsi-int / Parity error"); Kernel.WriteLn  END;
		msg := SCSI.MsgNoop;
		IF lastphase = PhaseDataOut THEN
			Kernel.WriteString("Parity Error during Data-Out phase"); Kernel.WriteLn
		ELSIF lastphase = PhaseDataIn THEN
			msg := SCSI.MsgInitiatorDetErr;
			Kernel.WriteString("Parity Error during Data-In phase"); Kernel.WriteLn
		ELSIF lastphase = PhaseCommand THEN
			Kernel.WriteString("Parity Error during Command phase"); Kernel.WriteLn
		ELSIF lastphase = PhaseMsgOut THEN
			Kernel.WriteString("Parity Error during Message-Out phase"); Kernel.WriteLn
		ELSIF lastphase = PhaseStatus THEN
			msg := SCSI.MsgInitiatorDetErr;
			Kernel.WriteString("Parity Error during Status phase"); Kernel.WriteLn
		ELSIF lastphase = PhaseMsgIn THEN
			msg := SCSI.MsgParityError;
			Kernel.WriteString("Parity Error during Message_In phase"); Kernel.WriteLn
		ELSE
			Kernel.WriteString("Parity Error during unknown phase"); Kernel.WriteLn
		END;
		IF msg # SCSI.MsgNoop THEN
			d.Put1(d, MSGOUT, SYSTEM.VAL(SET, msg));  scb := NIL
		END;
		d.Put1(d, CLRSINT1, {CLRSCSIPERR});
		d.Put1(d, CLRINT, {CLRSCSIINT});
		Unpause(d)
	ELSIF (REQINIT IN status) & (FlagHandlingReqInits IN d.flags) THEN
		(*IF DebugTraceInts THEN  Kernel.WriteString("Int Scsi / Req Init"); Kernel.WriteLn  END;*)
		HandleReqInit(d, scb); RETURN
	ELSIF (1 IN status) & (FlagHandlingReqInits IN d.flags) THEN	(*phasechg*)
		IF DebugTraceInts THEN
			WriteDriver(d); Kernel.WriteString(" scsi-int / PhaseChg -- not handling"); Kernel.WriteLn
		END;
		Unpause(d);
		scb := NIL;
	ELSE
		WriteDriver(d); Kernel.WriteString(" scsi-int / Unknown"); Kernel.WriteHex(SYSTEM.VAL(LONGINT, status),0); Kernel.WriteLn;
(*
		d.Put1(d, CLRSINT1, status);
		d.Put1(d, CLRINT, {CLRSCSIINT});
*)
		Unpause(d);
		scb := NIL
	END;
	IF scb # NIL THEN Done(d, scb) END;
END InterruptScsi;

PROCEDURE InterruptHandler;	(*this is the interrupt handler for all devices*)
VAR  intNo, ebp: LONGINT; d: Host; intstat: SET;
BEGIN
	SYSTEM.GETREG(SYSTEM.EBP, ebp);  SYSTEM.GET(ebp+40, intNo); DEC(intNo, Kernel.IRQ);
		(*now look for candidates*)
	d := HostRoot;
	WHILE d # NIL DO
		intstat := d.Get1(d, INTSTAT);
		IF (d.irq = intNo) & (d.interruptable) & (INTPEND * intstat # {}) THEN
			INC(d.intCount);
			IF CMDCMPLT IN intstat THEN	InterruptCmdComplete(d)	END;
			IF BRKADRINT IN intstat THEN	InterruptBrkAdr(d)	END;
			IF SEQINT IN intstat THEN	InterruptSequencer(d, intstat)	END;
			IF SCSIINT IN intstat THEN	InterruptScsi(d)	END
		END;
		d := d.next
	END
END InterruptHandler;

(* ========================================================================*)
(* ==========================SCB Functions===================================*)
(* ========================================================================*)
PROCEDURE DetectMaxSCB(d: Host);	(*detect_maxscb*)
VAR	i: LONGINT;  quit: BOOLEAN;
BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  DetectMaxSCB"); Kernel.WriteLn  END;
	IF d.maxScb = 0 THEN
		d.Put1(d, FREESCBH, {});
		i := 0; quit := FALSE;
		WHILE (i < 255) & ~quit DO
			d.Put1(d, SCBPTR, SYSTEM.VAL(SET, i));
			d.Put1(d, SCBCONTROL, SYSTEM.VAL(SET, i));
			IF i # SYSTEM.VAL(LONGINT, d.Get1(d, SCBCONTROL)) THEN
				quit := TRUE
			ELSE
				d.Put1(d, SCBPTR, {});
				IF d.Get1(d, SCBCONTROL) # {} THEN
					quit := TRUE
				ELSE
					d.Put1(d, SCBPTR, SYSTEM.VAL(SET, i));
					d.Put1(d, SCBCONTROL, {});
					d.Put1(d, SCBNEXT, SYSTEM.VAL(SET, i+1));
					d.Put1(d, SCBPREV, SYSTEM.VAL(SET, i-1));
					d.Put1(d, SCBTAG, SYSTEM.VAL(SET, -1));
					d.Put1(d, SCBBUSYTARGETS, SYSTEM.VAL(SET, -1));
					d.Put1(d, SCBBUSYTARGETS+1, SYSTEM.VAL(SET, -1));
					d.Put1(d, SCBBUSYTARGETS+2, SYSTEM.VAL(SET, -1));
					d.Put1(d, SCBBUSYTARGETS+3, SYSTEM.VAL(SET, -1));
					INC(i)
				END
			END
		END;
		d.Put1(d, SCBPTR, SYSTEM.VAL(SET, i-1));	(*last SCB terminates the list*)
		d.Put1(d, SCBNEXT, SYSTEM.VAL(SET, -1));
		
		d.Put1(d, SCBPTR, SYSTEM.VAL(SET, 0));	(*clear first SCB control byte ????IS THIS REALLY USEFUL????*)
		d.Put1(d, SCBCONTROL, {});
		d.maxScb := i;
		IF i = 255 THEN  EXCL(d.flags, FlagPageSCB)  END;
	END;
	IF DebugConfig THEN
		WriteDriver(d); Kernel.WriteInt(d.maxScb, 4); Kernel.WriteString("  SCB detected"); Kernel.WriteLn
	END
END DetectMaxSCB;

PROCEDURE AllocateSCB(d: Host): LONGINT;
BEGIN
	ASSERT(d.allocated < 256);
	NEW(d.scb[d.allocated]); d.scb[d.allocated].tag := CHR(d.allocated);
	INC(d.allocated);
	RETURN d.allocated-1
END AllocateSCB;

PROCEDURE CalculateResidual(d: Host; scb: ScbData);	(* aic7xxx_calc_residual *)
VAR index, sum: LONGINT;
BEGIN
	index := ORD(scb.tag);
	IF ~CBIT(d.hwscb[index].control, DISCONNECTED) (*& ~(ScbSense IN scb.flags)*) THEN
		ASSERT(ORD(d.hwscb[index].resSGcnt) <= 1);
		sum := 10000H*ORD(d.hwscb[index].resDataCnt[2]) + 100H*ORD(d.hwscb[index].resDataCnt[1]) + 100H*ORD(d.hwscb[index].resDataCnt[0]);
		(*Kernel.WriteString("SG-Residual, "); Kernel.WriteInt(sum, 4); Kernel.WriteLn;*)
	END;
	d.hwscb[index].resSGcnt := 0X;
	d.hwscb[index].resDataCnt[2] := 0X;
	d.hwscb[index].resDataCnt[1] := 0X;
	d.hwscb[index].resDataCnt[0] := 0X;
END CalculateResidual;

PROCEDURE RemoveScbFromDiscList(d: Host; ptr: SET): SET;	(* aic7xxx_rem_scb_from_disc_list *)
VAR	prev, next: SET;	pc, nc: CHAR;
BEGIN
		(*check if writing to the SCB is the same as writing to thememory directly*)
	d.Put1(d, SCBPTR, ptr);
	next := d.Get1(d, SCBNEXT);
	prev := d.Get1(d, SCBPREV);
	IF prev # ScbNullSet THEN
		d.Put1(d, SCBPTR, prev); d.Put1(d, SCBNEXT, next)
		;nc := d.hwscb[SYSTEM.VAL(LONGINT, ptr)].next;
		ASSERT(nc = SYSTEM.VAL(CHAR, next));
	ELSE
		d.Put1(d, DISCONNECTEDSCBH, next)
	END;
	IF next # ScbNullSet THEN
		d.Put1(d, SCBPTR, next); d.Put1(d, SCBPREV, prev)
		;pc := d.hwscb[SYSTEM.VAL(LONGINT, ptr)].prev;
		ASSERT(pc = SYSTEM.VAL(CHAR, prev));
	END;
	RETURN next
END RemoveScbFromDiscList;

PROCEDURE FreeCurScb(d: Host);	(* aic7xxx_add_curscb_to_free_list *)
BEGIN
	d.Put1(d, SCBTAG, ScbNullSet);
	d.Put1(d, SCBCONTROL, {});
	d.Put1(d, SCBNEXT, d.Get1(d, FREESCBH));
	d.Put1(d, FREESCBH, d.Get1(d, SCBPTR))
END FreeCurScb;

PROCEDURE AbortWaitingScb(d: Host; pos, prev: SET): SET;
VAR	cur, next: SET;
BEGIN
	cur := d.Get1(d, SCBPTR); d.Put1(d, SCBPTR, pos);
	next := d.Get1(d, SCBNEXT);
	FreeCurScb(d);
	IF prev = ScbNullSet THEN
		d.Put1(d, WAITINGSCBH, next)
	ELSE
		d.Put1(d, SCBPTR, prev); d.Put1(d, SCBNEXT, next)
	END;
	d.Put1(d, SCBPTR, cur);
	RETURN next
END AbortWaitingScb;

PROCEDURE MatchScb(d: Host; index: LONGINT; target, channel, lun: LONGINT; tag: CHAR): BOOLEAN;
	(*aic7xxx_match_scb*)
VAR	targ: LONGINT;
BEGIN
	targ := ORD(d.hwscb[index].targ);
	RETURN
	(((SYSTEM.LSH(targ, -4) MOD 16) = target) OR (target = AllTargets)) &
	(((SYSTEM.LSH(targ, -3) MOD 2) = channel) OR (channel = AllChannels)) &
	(((targ MOD 8) = lun) OR (lun = AllLuns)) &
	((d.hwscb[index].targ = tag) OR (tag = ScbNull))
END MatchScb;

PROCEDURE SearchQInFifo(d: Host; target, channel, lun: LONGINT; tag: CHAR; flags: SET; requeue: BOOLEAN; VAR queue: Queue);
(* aic7xxx_search_qinfifo *)
(*Optimized: when NoQueue = ~requeue*)
VAR	tindex, found: LONGINT; scb: ScbData; qinpos, qintail: INTEGER;
BEGIN
	found := 0;
	qinpos := SYSTEM.VAL(INTEGER, d.Get1(d, QINPOS));
	qintail := d.inNext;
	d.inNext := qinpos;
	WHILE qinpos # qintail DO
		scb := d.scb[ORD(d.in[qinpos])]; INC(qinpos);
		IF MatchScb(d, ORD(scb.tag), target, channel, lun, tag) THEN
			tindex := scb.cmd.target + scb.cmd.chan*8;
			IF requeue (*& (queue # NoQueue)*) THEN
				IF ScbWaitingQ IN scb.flags THEN
					queue.Remove(scb);
					d.wait.Remove(scb);
					d.dev[tindex].delayed.Remove(scb);
					INC(d.dev[tindex].commandsActive);
					INC(d.active)
				END;
				queue.Put(scb);
				DEC(d.dev[tindex].commandsActive);
				DEC(d.active);
				INCL(scb.flags, ScbWaitingQ);
				IF ~CBIT(scb.tagAction, TAGENB) THEN
					d.untagged[ORD(d.hwscb[ORD(scb.tag)].targ)] := ScbNull
				END
			(*ELSIF requeue THEN
				d.in.Put(scb.tag)*)
			ELSE
				scb.flags := flags + scb.flags*{ScbRecovery};
				tindex := ORD(d.hwscb[ORD(scb.tag)].targ);
				IF d.untagged[tindex] = CHR(tindex) THEN
					d.untagged[tindex] := ScbNull
				END
			END;
			INC(found)
		ELSE
			d.in[d.inNext] := d.hwscb[ORD(scb.tag)].tag; d.inNext := (d.inNext+1) MOD 256;
		END
	END;
	qinpos := d.inNext;
	WHILE qinpos # qintail DO
		d.in[qinpos] := ScbNull; INC(qinpos)
	END;
	IF FeatQueueRegs IN d.features THEN
		d.Put1(d, HNSCBQOFF, SYSTEM.VAL(SET, d.inNext))
	ELSE
		d.Put1(d, KERNELQINPOS, SYSTEM.VAL(SET, d.inNext))
	END;
	(*RETURN found*)
END SearchQInFifo;

PROCEDURE ScbOnQOutFifo(d: Host; index: LONGINT): BOOLEAN;
BEGIN
	HALT(Unimplemented)
END ScbOnQOutFifo;

PROCEDURE FreeScb(d: Host; scb: ScbData);
VAR tag: INTEGER;
BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  FreeScb"); DumpChar(scb.tag); Kernel.WriteLn  END;
	scb.flags := {ScbFree};
	scb.cmd.ptrToCmd := SYSTEM.VAL(LONGINT, NIL);
	scb.tagAction := 0X;
	tag := ORD(scb.tag);
	d.hwscb[tag].control := 0X;
	d.hwscb[tag].status := 0X;
	d.hwscb[tag].targ := ScbNull;
	SetEntry(d.freeList, tag)
END FreeScb;

PROCEDURE Done(d: Host; scb: ScbData);	(* aic7xxx_done *)
VAR t, index, queueDepth: LONGINT; p: ScbData; wide, sync, error: BOOLEAN; ch: CHAR;
BEGIN
	index := scb.cmd.target + scb.cmd.chan*8;
	IF DebugTrace THEN WriteDevice(d, index); Kernel.WriteString("  Done")  END;
	
	IF ScbRecovery IN scb.flags THEN	EXCL(d.flags, FlagAbortPending)	END;
	IF (ScbReset IN scb.flags) OR (ScbAbort IN scb.flags) THEN
		scb.cmd.result := SCSI.Reset
	ELSIF ~(DeviceScanned IN d.dev[index].flags) THEN
		SYSTEM.GET(scb.cmd.cmd, ch);	(*read command*)
		IF (ch = SCSI.Inquiry) & (scb.cmd.result = SCSI.OK) THEN
			SYSTEM.GET(scb.cmd.data+7, ch);
			wide := SYSTEM.VAL(SET, ch) * {5,6} # {};
			sync := 4 IN SYSTEM.VAL(SET, ch);
			
			IF wide & (FeatWide IN d.features) THEN
				INCL(d.needWidthTrasm, index);
				SetWidth(d, scb.cmd.target, scb.cmd.chan, scb.cmd.lun, TRUE, {TransGoal});
			ELSE
				EXCL(d.needWidthTrasm, index);
				Pause(d);
				SetWidth(d, scb.cmd.target, scb.cmd.chan, scb.cmd.lun, FALSE, {TransActive, TransGoal, TransCur});
				Unpause(d)
			END;
			IF sync THEN
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" + sync (Done)"); Kernel.WriteLn  END;
				INCL(d.needSyncTrasm, index);
				(*INCL(d.needSyncTrasmCopy, index);*)
				IF (FlagSeepromFound IN d.flags) THEN
					(*keep eeprom values*)
					(*d.dev[index].goalPeriod := d.dev[index].userPeriod;*)
				ELSIF FeatUltra2 IN d.flags THEN
					d.dev[index].goalPeriod := SyncRate[0].rate[RateUltra2]
				ELSIF FeatUltra IN d.flags THEN
					d.dev[index].goalPeriod := SyncRate[2].rate[RateUltra]
				ELSE
					d.dev[index].goalPeriod := SyncRate[5].rate[Rate]
				END;
				IF FeatUltra2 IN d.flags THEN
					d.dev[index].goalOffset := MaxOffsetUltra2
				ELSIF index IN d.goalWidth THEN
					d.dev[index].goalOffset := MaxOffset16Bit
				ELSE
					d.dev[index].goalOffset := MaxOffset8Bit
				END
			ELSE
IF DebugMsg THEN WriteDevice(d, index); Kernel.WriteString(" - sync (Done)"); Kernel.WriteLn  END;
				EXCL(d.needSyncTrasm, index);
				(*EXCL(d.needSyncTrasmCopy, index);*)
				d.dev[index].goalPeriod := 0;
				d.dev[index].goalOffset := 0
			END;
		END;
		INCL(d.dev[index].flags, DeviceScanned)
	ELSIF scb.flags * {ScbMsgWidth, ScbMsgSync} # {} THEN
		IF ScbMsgWidth IN scb.flags THEN
			EXCL(d.widthPending, index);
		END;
		IF  ScbMsgSync IN scb.flags THEN
			EXCL(d.syncPending, index);
		END
	END;
	queueDepth := d.dev[index].tempQueueDepth;
	IF (queueDepth >= d.dev[index].commandsActive) & (d.dev[index].delayed.head # NIL) THEN
		d.dev[index].delayed.Get(p);
		IF queueDepth = 1 THEN
			d.wait.PutFirst(p)
		ELSE
			d.wait.Put(p)
		END;
		IF (queueDepth > d.dev[index].commandsActive) & (d.dev[index].delayed.head # NIL) THEN
			d.dev[index].delayed.Get(p);
			d.wait.Put(p)
		END
	END;
	IF (scb.tagAction # 0X) & (index IN d.tagged) THEN
		d.dev[index].tempQueueDepth := d.dev[index].maxQueueDepth
	END;
	DEC(d.dev[index].commandsActive);
	DEC(d.active);
	IF d.untagged[ORD(d.hwscb[index].targ)] = d.hwscb[index].tag THEN
		d.untagged[ORD(d.hwscb[index].targ)] := ScbNull
	END;
	(* XXX here make statistics, now skipped *)
	t := scb.cmd.ptrToCmd;
	SYSTEM.PUT(t + 0, scb.cmd.status);		(*pass status/result to the command*)
	SYSTEM.PUT(t + 1, scb.cmd.result);
	IF DebugTrace THEN Kernel.WriteInt(scb.cmd.status, 4); Kernel.WriteInt(scb.cmd.result, 4); Kernel.WriteLn  END;
	FreeScb(d, scb);
	SYSTEM.PUT(t + 2, TRUE);
END Done;

PROCEDURE RunDoneQueue(d: Host);		(* aic7xxx_run_done_queue *)
VAR	i: LONGINT; scb: ScbData;
BEGIN
	IF DebugTrace THEN Kernel.WriteString("Adaptec7.RunDoneQueue"); Kernel.WriteLn  END;
	FOR i := 0 TO d.allocated DO
		scb := d.scb[i];
		IF ScbQueuedForDone IN scb.flags THEN
			Done(d, scb)
		END
	END;
END RunDoneQueue;
(* ========================================================================*)
(* ========================Reset/Init Functions================================*)
(* ========================================================================*)
PROCEDURE ResetChip(d: Host);
VAR	s: SET; t: Kernel.MilliTimer; msg: ARRAY 64 OF CHAR;
BEGIN
	IF DebugTrace THEN  Kernel.WriteString("Adaptec7.ResetChip"); Kernel.WriteLn  END;
	d.Put1(d, HCNTRL, {PAUSE, CHIPRST});
	Kernel.SetTimer(t, 1000);	(*1 sec*)
	WHILE ~Kernel.Expired(t) & ~(CHIPRST IN d.Get1(d, HCNTRL)) DO  END;	(*wait 1 sec or till bit set*)
	Pause(d);	(*pause, clear rst bit*)
	
	s := d.Get1(d, SBLKCTL) * {SELWIDE, SELBUSB};
	IF d IS PCIHost THEN  EXCL(s, SELBUSB)  END;
	
	IF s = {} THEN	(*normal card*)
	ELSIF  {SELWIDE} = s  THEN  INCL(d.features, FeatWide);			(*Wide card*)
	ELSIF  {SELBUSB} = s  THEN  INCL(d.features, FeatTwin);  INCL(d.flags, FlagMultiChannel)			(*Twin card*)
	ELSE
		msg := "SELWIDE and SELBUSB set! Unknown card";
		HALT(99)
	END
END ResetChip;

PROCEDURE ResetHost(d: Host);
VAR  i: LONGINT;
BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  ResetHost"); Kernel.WriteLn  END;
	FOR i := 0 TO d.nofTargets-1 DO
		d.Put1(d, TARGSCSIRATE+i, {});
		IF FeatUltra2 IN d.features THEN  d.Put1(d, TARGOFFSET+i, {})  END;
		d.dev[i].curOffset := 0;
		d.dev[i].curPeriod := 0;
	END;
	d.curWidth := {};
	d.ultra := {};
	d.Put1(d, ULTRAENB, {});
	d.Put1(d, ULTRAENB+1, {})
END ResetHost;

PROCEDURE ResetDevice(d: Host; target, channel, lun: LONGINT; tag: CHAR);
VAR	min, max, dummy, j, index, tcl: LONGINT; scb: ScbData; prev, next, active: SET; initLists: BOOLEAN;

	PROCEDURE TraverseQueue(VAR queue: Queue);
	VAR	p, q: ScbData; j: LONGINT;
	BEGIN
		j := 0; p := NIL; q := queue.head;
		WHILE (q # NIL) & (j < d.allocated) DO
			INC(j);
			IF MatchScb(d, ORD(q.tag), target, channel, lun, tag) THEN
				IF p = NIL THEN  queue.head := q.next  ELSE  p.next := q.next  END;
				IF ScbWaitingQ IN q.flags THEN
					INC(d.dev[min].commandsActive);
					INC(d.active)
				END;
				q.flags := q.flags - {ScbActive, ScbWaitingQ} + {ScbReset, ScbQueuedForDone};
				q := q.next
			ELSE
				p := q; q := q.next
			END
		END;
		IF j > d.allocated THEN
			queue.Init;
			HALT(99);		(*where to with the scbs in delayed?*)
		END;
	END TraverseQueue;
	
BEGIN
	IF DebugTrace THEN WriteDevice(d, target); Kernel.WriteString("  ResetDevice"); Kernel.WriteLn  END;
	active := d.Get1(d, SCBPTR);
	IF target = AllTargets THEN
		IF channel = 0 THEN
			min := 0;
			IF FeatWide IN d.features THEN max := 15 ELSE max := 7 END
		ELSIF channel = 1 THEN
			min := 8; max := 15
		ELSE
			min := 0;
			IF {FeatWide, FeatTwin} * d.features # {} THEN max := 15 ELSE max := 7 END
		END
	ELSE
		min := target;
		ASSERT(channel IN {0, 1});
		IF channel = 1 THEN  INC(min, 8)  END;		(*Bug? Here linux ORs the channel in the min!*)
		max := min
	END;
	WHILE min <= max DO
		IF ~(DeviceTaggedSuccess IN d.dev[min].flags) & (d.dev[min].commandsActive # 0) & (min IN d.tagged) THEN
			d.dev[min].maxQueueDepth := 1;  d.dev[min].tempQueueDepth := 1;
			EXCL(d.tagged, min);  EXCL(d.orderedQueue, min)
		END;
		EXCL(d.dev[min].flags, DeviceBusResetPending);
		IF tag = ScbNull THEN
			(*d.dev[min].flags := d.dev[min].flags + {DevicePrintWdTr, DevicePrintSdTr};*)
			d.dev[min].timer.lastReset := jiffies;
			d.dev[min].lastQueueFullCount := 0;
			d.dev[min].lastQueueFull := 0;
			d.dev[min].tempQueueDepth := d.dev[min].maxQueueDepth;
			IF d.dev[min].timer.expires # 0 THEN
				Kernel.WriteString("Timer unimplemented in ResetDevice"); Kernel.WriteLn;
			END;
			j := 0; WHILE j < 8 DO
				ASSERT(channel IN {0, 1}, 130);
				IF channel=1 THEN
					tcl := (min MOD 8) * 16 + 8 + j
				ELSE
					tcl := min * 16 + j
				END;
				IF (d.untagged[tcl] = tag) OR (tag = ScbNull) THEN
					d.untagged[tcl] := ScbNull
				END;
				INC(j)
			END;
			TraverseQueue(d.dev[min].delayed);
			IF (d.dev[min].delayed.head = NIL) & (d.dev[min].timer.expires # 0) THEN
				HALT(TimerUnimplemented)
			END
		END;
		INC(min)
	END;
	
	SearchQInFifo(d, target, channel, lun, tag, {ScbReset, ScbQueuedForDone}, FALSE, NoQueue);
	TraverseQueue(d.wait);
	
	j := 0;
	prev := ScbNullSet;
	next := d.Get1(d, WAITINGSCBH);
	WHILE (next # ScbNullSet) & (j < d.allocated) DO
		INC(j);
		d.Put1(d, SCBPTR, next);
		index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
		IF index >= d.allocated THEN
			Kernel.WriteString("AIC7xxx: Wait List inconsistency!!"); Kernel.WriteLn;
			next := d.Get1(d, SCBNEXT);
			FreeCurScb(d)
		ELSE
			ASSERT(index = SYSTEM.VAL(LONGINT, next));
			scb := d.scb[index];
			IF MatchScb(d, ORD(scb.tag), target, channel, lun, tag) THEN
				next := AbortWaitingScb(d, next, prev);
				IF ScbWaitingQ IN scb.flags THEN
					INC(d.dev[scb.cmd.target + scb.cmd.chan*8].commandsActive);
					INC(d.active)
				END;
				scb.flags := scb.flags - {ScbActive, ScbWaitingQ} + {ScbReset, ScbQueuedForDone};
				IF prev = ScbNullSet THEN
					d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) - {ENSELO});
					d.Put1(d, CLRSINT1, {CLRSELTIMEO})
				END
			ELSE
				prev := next; next := d.Get1(d, SCBNEXT)
			END
		END
	END;
	IF j > d.allocated THEN
		Kernel.WriteString("AIC7xxx: There is a loop in the wait list!!"); Kernel.WriteLn;
		initLists := TRUE
	END;
	
	IF FlagPageSCB IN d.features THEN
		j := 0;
		next := d.Get1(d, DISCONNECTEDSCBH);
		WHILE (next # ScbNullSet) & (j < d.allocated) DO
			INC(j);
			d.Put1(d, SCBPTR, next);
			index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
			IF index >= d.allocated THEN
				Kernel.WriteString("AIC7xxx: Disconnected List inconsistency!!"); Kernel.WriteLn;
				next := RemoveScbFromDiscList(d, next)
			ELSE
				scb := d.scb[index];
				IF MatchScb(d, ORD(scb.tag), target, channel, lun, tag) THEN
					next := RemoveScbFromDiscList(d, next);
					IF ScbWaitingQ IN scb.flags THEN
						INC(d.dev[scb.cmd.target + scb.cmd.chan*8].commandsActive);
						INC(d.active)
					END;
					scb.flags := scb.flags - {ScbActive, ScbWaitingQ} + {ScbReset, ScbQueuedForDone};
					d.hwscb[index].control := 0X;
				ELSE
					next := d.Get1(d, SCBNEXT)
				END
			END
		END;
		IF j > d.allocated THEN
			Kernel.WriteString("AIC7xxx: There is a loop in the Disconnected list!!"); Kernel.WriteLn;
			initLists := TRUE
		END;
		
		j := 0;
		next := d.Get1(d, FREESCBH);
		IF (SYSTEM.VAL(LONGINT, next) >= d.allocated) & (next # ScbNullSet) THEN
			Kernel.WriteString("AIC7xxx: Bogus Free SCBH!!"); Kernel.WriteLn;
			initLists := TRUE;
			next := ScbNullSet
		END;
		WHILE (next # ScbNullSet) & (j < d.allocated) DO
			INC(j);
			d.Put1(d, SCBPTR, next);
			IF SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG)) >= d.allocated THEN
				Kernel.WriteString("AIC7xxx: FREE-SCBH List inconsistency!!"); Kernel.WriteLn;
				initLists := TRUE;
				next := ScbNullSet
			ELSE
				d.Put1(d, SCBTAG, ScbNullSet);
				d.Put1(d, SCBCONTROL, {});
				next := d.Get1(d, SCBNEXT)
			END
		END;
		IF j > d.allocated THEN
			Kernel.WriteString("AIC7xxx: There is a loop in the Free list!!"); Kernel.WriteLn;
			initLists := TRUE
		END	
	END;
	
	IF initLists THEN
		d.Put1(d, FREESCBH, ScbNullSet);
		d.Put1(d, WAITINGSCBH, ScbNullSet);
		d.Put1(d, DISCONNECTEDSCBH, ScbNullSet)
	END;
	
	FOR j := 0 TO 255 DO	(* linux goes 255..0 here*)
		d.Put1(d, SCBPTR, SYSTEM.VAL(SET, j));
		IF initLists THEN
			d.Put1(d, SCBTAG, ScbNullSet);
			d.Put1(d, SCBNEXT, ScbNullSet);
			d.Put1(d, SCBPREV, ScbNullSet);
			d.Put1(d, SCBCONTROL, {})
		ELSE
			index := SYSTEM.VAL(LONGINT, d.Get1(d, SCBTAG));
			ASSERT(index = j);	(* I'm just wondering.... this could be simplified*)
			IF index < d.allocated THEN
				IF MatchScb(d, index, target, channel, lun, tag) THEN
					d.Put1(d, SCBCONTROL, {});
					d.Put1(d, SCBTAG, ScbNullSet);
					FreeCurScb(d)
				END
			END
		END
	END;
	
	FOR j := 0 TO 255 DO
		scb := d.scb[j];
		IF (ScbActive IN scb.flags) & MatchScb(d, index, target, channel, lun, tag) & ~ScbOnQOutFifo(d, index) THEN
			IF ScbWaitingQ IN scb.flags THEN
				d.wait.Remove(scb);
				d.dev[scb.cmd.target + scb.cmd.chan*8].delayed.Remove(scb);
				INC(d.dev[scb.cmd.target + scb.cmd.chan*8].commandsActive);
				INC(d.active)
			END;
			scb.flags := scb.flags - {ScbActive, ScbWaitingQ} + {ScbReset, ScbQueuedForDone}
		END
	END;
	
	d.Put1(d, SCBPTR, active)
END ResetDevice;

PROCEDURE ResetBus(d: Host);		(* aic7xxx_reset_current_bus *)
BEGIN
	IF DebugTrace THEN  WriteDriver(d); Kernel.WriteString("  ResetBus"); Kernel.WriteLn  END;
	d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENSCSIRST});
	d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) + {SCSIRSTO});
	WHILE ~(SCSIRSTO IN d.Get1(d, SCSISEQ)) DO  Delay(5)  END;
	Delay(10);
	d.Put1(d, SCSISEQ, {});
	Delay(5);
	ClearIntStat(d);
	d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) + {ENSCSIRST})
END ResetBus;

PROCEDURE ResetChannel(d: Host; channel: LONGINT; reset: BOOLEAN);	(* aic7xxx_reset_channel *)
VAR  min, max: LONGINT; sblkctl: SET; curChan: LONGINT;
BEGIN
	IF DebugTrace THEN WriteDriver(d); Kernel.WriteString("  ResetChannel"); Kernel.WriteLn  END;
	IF channel = 1 THEN
		(*d.needSyncTrasm := d.needSyncTrasmCopy * {8..15};*)
		d.syncPending := d.syncPending * {0..7};
		min := 8; max := 16
	ELSIF FeatWide IN d.features THEN
		(*d.needSyncTrasm := d.needSyncTrasmCopy;*)
		d.needWidthTrasm := d.curWidth / d.goalWidth(*d.needWidthTrasmCopy*);
		d.syncPending := {};
		d.widthPending := {};
		min := 0; max := 16
	ELSE (* Channel A *)
		(*d.needSyncTrasm := d.needSyncTrasmCopy * {0..7};*)
		d.syncPending := d.syncPending * {8..15};
		min := 0; max := 8
	END;
IF DebugMsg THEN WriteDriver(d); Kernel.WriteString(" +/- sync? (ResetChannel)"); Kernel.WriteLn  END;
	d.needSyncTrasm := d.needSyncTrasm - {min..max-1};
	WHILE min < max DO
		IF (d.dev[min].goalPeriod # d.dev[min].curPeriod) OR (d.dev[min].goalOffset # d.dev[min].curOffset) THEN
			INCL(d.needSyncTrasm, min)
		END;
		d.Put1(d, TARGSCSIRATE+ min, {});
		IF FeatUltra2 IN d.features THEN  d.Put1(d, TARGOFFSET + min, {})  END;
		INC(min)
	END;
	sblkctl := d.Get1(d, SBLKCTL);
	IF (d.chip = AIC7770) & (SELBUSB IN sblkctl) THEN  curChan := 1  ELSE curChan := 0  END;
	IF (curChan # channel) & (FeatTwin IN d.features) THEN
			(* Command for another bus is active *)
		d.Put1(d, SBLKCTL, sblkctl / {SELBUSB});
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENBUSFREE});
		IF reset THEN  ResetBus(d)  END;
		d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) * {ENSELI, ENRSELI, ENAUTOATNP});
		ClearIntStat(d);
		d.Put1(d, SBLKCTL, sblkctl)
	ELSE
			(* A command from this bus is active or we're idle *)
		d.Put1(d, SIMODE1, d.Get1(d, SIMODE1) - {ENBUSFREE, ENREQINIT});
		EXCL(d.flags, FlagHandlingReqInits);
		d.msg.type := MsgTypeNone;
		d.msg.len := 0;
		IF reset THEN  ResetBus(d)  END;
		d.Put1(d, SCSISEQ, d.Get1(d, SCSISEQ) * {ENSELI, ENRSELI, ENAUTOATNP});
		ClearIntStat(d);
	END;
	ResetDevice(d, AllTargets, channel, AllLuns, ScbNull);
	d.lastReset := jiffies;
	IF ~(FeatTwin IN d.features) THEN  d.Put1(d, SEQCTL, {FASTMODE, SEQRESET})  END
END ResetChannel;

PROCEDURE ConfigureChannels(d: PCIHost);
BEGIN
	(*special setups for multichannel boards*)
	IF  FlagMultiChannel IN d.flags THEN
		CASE d.chip OF
		| AIC7870, AIC7880:
			IF d.slot = 5 THEN  INCL(d.flags, FlagChnlB)			(*3940, 3940Ultra*)
			ELSIF d.slot = 8 THEN INCL(d.flags, FlagChnlB)			(*3985, 3985Ultra*)
			ELSIF d.slot = 12 THEN INCL(d.flags, FlagChnlC)			(*3985, 3985Ultra*)
			END
		| AIC7895, AIC7896:
			IF d.devNo # 0 THEN  INCL(d.flags, FlagChnlB) END;
		END;
	END;
	(*set of DEVCONFIG.SCBSIZE32 for 7895 done in InitPCIHost*)
	
	(*load seeprom*)
	CASE d.chip OF
	| AIC7890, AIC7896:
		d.Put1(d, SCAMCTL, {});
		d.Put1(d, DSCOMMAND0, d.Get1(d, DSCOMMAND0)
			+ {CACHETHEN, MPARCKEN, USCBSIZE32, CIOPARCKEN} - {DPARCKEN})
	| AIC7850, AIC7860:
		d.Put1(d, DSCOMMAND0, d.Get1(d, DSCOMMAND0)+ {CACHETHEN, MPARCKEN}- {DPARCKEN})
	ELSE
	END;
END ConfigureChannels;



PROCEDURE InitHost(d: Host);
VAR   t: SET; i: LONGINT;
BEGIN
	IF DebugTrace THEN Kernel.WriteString("Adaptec7.InitHost"); Kernel.WriteLn  END;
	IF {FeatTwin, FeatWide} * d.features # {} THEN
		d.nofTargets := 8
	ELSE
		d.nofTargets := 16
	END;
	
	(* Implements aic7xxx_alloc and aic7xxx_register *)
	(* aic7xxx_alloc*)
	i := 0;  WHILE i < 256 DO
		d.hwscb[i].control := 0X;
		d.hwscb[i].tag := CHR(i);
		d.untagged[i] := ScbNull;
		d.out[i] := ScbNull;
		d.in[i] := ScbNull;
		INC(i)
	END;
	INCL(d.freeList[0], 0);	(*allocate first SCB*)
	d.allocated := 0;  i := AllocateSCB(d);
	ASSERT(i = 0);
	
	d.tagged := {}; d.orderedQueue := {};
	
		(* aic7xxx_register *)
	d.intCount := 0;
	
	d.inNext := 0; d.outNext := 0; d.wait.Init;
	
	i := 0; WHILE i < 16 DO
		d.dev[i].delayed.Init;
		d.dev[i].flags := {};
		d.dev[i].commandsSent := 0;
		d.dev[i].commandsActive :=0;
		d.dev[i].lastQueueFull := 0;
		d.dev[i].lastQueueFullCount := 0;
		d.dev[i].tempQueueDepth := 1;
		d.dev[i].timer.expires := -1;
		INC(i)
	END;
	d.goalWidth := {};
	
	d.Put1(d, SEQFLAGS, {});
	DetectMaxSCB(d);
	IF FlagSeepromFound IN d.flags THEN
		IF (FeatSpioCap IN d.features) & (SSPIOCPS IN d.Get1(d, SPIOCAP)) OR (d.chip >= AIC7870) THEN
			ConfigureTermination(d)
		END
	END;
	LoadSequencer(d);
	
	IF d.chip = AIC7770 THEN  d.Put1(d, BCTL, {ENABLE})  END;
	d.Put1(d, SBLKCTL, d.Get1(d, SBLKCTL) - {AUTOFLUSHDIS});
	ClearIntStat(d);
	
	(*Set SCSI ID, XCtrl0 XCtrl1, SIMODE1*)
	IF FeatTwin IN d.features THEN	(*Channel B*)
		d.Put1(d, SBLKCTL, d.Get1(d, SBLKCTL) + {SELBUSB});
		d.Put1(d, SCSIID, SYSTEM.VAL(SET, d.scsiIdB));
		t := d.Get1(d, SCSICONF+1)*{ENSPCHK} + {ENSTIMER, ACTNEGEN};
		IF  FlagTermEnbB IN d.flags  THEN  INCL(t, STPWEN)  END;
		d.Put1(d, SXFRCTL0, {DFON, SPIOEN});
		d.Put1(d, SXFRCTL1, t);
		d.Put1(d, SIMODE0, {});
		d.Put1(d, SIMODE1, {ENSELTIMO, ENSCSIRST, ENSCSIPERR});
		d.Put1(d, SCSIRATE, {});
		d.Put1(d, SBLKCTL, d.Get1(d, SBLKCTL) - {SELBUSB});
	END;
	IF FeatUltra2 IN d.flags THEN
		d.Put1(d, SCSIIDULTRA2, SYSTEM.VAL(SET, d.scsiId))
	ELSE
		d.Put1(d, SCSIID, SYSTEM.VAL(SET, d.scsiId))
	END;
	t := d.Get1(d, SCSICONF)*{ENSPCHK} + {ENSTIMER, ACTNEGEN};
	IF FlagTermEnbSELow IN d.flags THEN  INCL(t, STPWEN)  END;
	d.Put1(d, SXFRCTL0, {DFON, SPIOEN});
	d.Put1(d, SXFRCTL1, t);
	d.Put1(d, SIMODE0, {});
	d.Put1(d, SIMODE1, {ENSELTIMO, ENSCSIRST, ENSCSIPERR});
	d.Put1(d, SCSIRATE, {});
	
	ResetHost(d);
	ASSERT(SYSTEM.ADR(d.hwscb[0]) MOD 32 = 0, 110);
	Put4(d, HSCBARRAY, SYSTEM.ADR(d.hwscb[0]));
	Put4(d, SCBIDADDR, SYSTEM.ADR(d.untagged[0]));
	d.Put1(d, QINPOS, {});
	d.Put1(d, KERNELQINPOS, {});
	d.Put1(d, QOUTPOS, {});
	
	IF FeatQueueRegs IN d.features THEN
		d.Put1(d, QOFFCTLSTA, SCBQSIZE256);
		d.Put1(d, SDSCBQOFF, {});
		d.Put1(d, SNSCBQOFF, {});
		d.Put1(d, HNSCBQOFF, {})
	END;
	
	d.Put1(d, WAITINGSCBH, ScbNullSet);
	d.Put1(d, DISCONNECTEDSCBH, ScbNullSet);
	
	d.Put1(d, MSGOUT, SYSTEM.VAL(SET, SCSI.MsgNoop));
	d.Put1(d, LASTMSG, SYSTEM.VAL(SET, SCSI.MsgNoop));
	
	Put4(d, TMODECMDADDR, 0);
	d.Put1(d, TMODECMDADDRNEXT, {});

	ClearIntStat(d);
	
		(*reset*)
	IF FeatTwin IN d.features THEN
		d.Put1(d, SBLKCTL, d.Get1(d, SBLKCTL) + {SELBUSB});
		ResetBus(d);
		d.Put1(d, SBLKCTL, d.Get1(d, SBLKCTL) - {SELBUSB});
	END;
	IF FeatUltra2 IN d.features THEN  Delay(250)  END;
	ResetBus(d);
	(*Delay(5000);  moved to detect, done just once*) 
	
	d.interruptable := TRUE;
	IF ~(d.irq IN InstalledIRQ) THEN
		(*Kernel.WriteString("AIC: install IRQ "); Kernel.WriteInt(d.irq, 0); Kernel.WriteLn;*)
		IF InstalledIRQ = {} THEN  Kernel.InstallTermHandler(Cleanup)  END;
		INCL(InstalledIRQ, d.irq);
		Kernel.InstallIP(InterruptHandler, Kernel.IRQ+d.irq)
	END;
	Unpause(d)
END InitHost;



PROCEDURE InitPCIHost(d: PCIHost);
VAR	res, dw, bus, dev, slot: LONGINT;
BEGIN
	bus:=d.busNo; dev:=d.devNo; slot:=d.slot;
	res:=PCI.ReadConfigByte(bus, dev, slot, PCI.IntlReg, dw);  d.irq := SHORT(SHORT(dw MOD 100H));
	res:=PCI.ReadConfigDword(bus, dev, slot, PCI.Adr0Reg, dw);  d.iobase := dw - 1;
	res:=PCI.ReadConfigDword(bus, dev, slot, PCI.Adr1Reg, dw);
	IF dw # 0 THEN
		dw := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, dw) * {3..31});	(* clear io, 64 bits*)
		Kernel.MapPhysical(dw, 4*1024, d.membase);
(*Kernel.WriteString("Mem: "); Kernel.WriteHex(d.membase, 0); Kernel.WriteLn;*)
		d.Put1 := MemoryPut;  d.Get1 := MemoryGet
	ELSE
		d.Put1 := PortPut;  d.Get1 := PortGet
	END;
	
	res:=PCI.ReadConfigWord(bus, dev, slot, PCI.CmdReg, dw);	(*COMMAND*)
	dw := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, dw) + {8, 6, 4, 2, 1, 0});	(*Serren, Perren, Mwricen, Master, MSpace, ISpace*)
	res:=PCI.WriteConfigWord(bus, dev, slot, PCI.CmdReg, dw);
	
	res:=PCI.ReadConfigDword(bus, dev, slot, DEVCONFIG, dw);
	dw := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, dw) + {PCIERRGENDIS} - {BERREN});
	IF d.chip = AIC7895 THEN
		dw := SYSTEM.VAL(LONGINT, SYSTEM.VAL(SET, dw) + {SCBSIZE32});
	END;
	res:=PCI.WriteConfigDword(bus, dev, slot, DEVCONFIG, dw);
	
	Pause(d);
	ClearPCIInt(d);
END InitPCIHost;


PROCEDURE Detect;
VAR  res, dummy, dw, idx, bus, dev, slot, DevID, VenID, i: LONGINT;  host: Host;  flags, s, conf: SET;

	PROCEDURE Set(chip: SHORTINT; flags, features: SET; name: ARRAY OF CHAR; EpromSize, EpromType: SHORTINT);
	VAR pcidev: PCIHost;
	BEGIN
(*Kernel.WriteString("AIC7xxx: found "); Kernel.WriteString(name); Kernel.WriteLn;*)
		NEW(pcidev);
		pcidev.flags := flags;  pcidev.features := features;
		COPY(name, pcidev.name);  pcidev.submit := Execute;
		pcidev.chip := chip;
		pcidev.pause := {INTEN, PAUSE}; pcidev.unpause := {INTEN};
		pcidev.epromSize := EpromSize;  pcidev.epromType := EpromType;
		pcidev.busNo := bus;  pcidev.devNo := dev;  pcidev.slot := slot;
		pcidev.interruptable := FALSE;
		pcidev.next := HostRoot;  HostRoot := pcidev;
		host := pcidev;
	END Set;
	
BEGIN
	IF DebugTrace THEN Kernel.WriteString("Adaptec7.Detect"); Kernel.WriteLn  END;
	IF PCI.Done = PCI.PCIPresent(dummy, dummy, dummy) THEN
		idx := 0;
		WHILE PCI.Done = PCI.FindPCIClassCode(010000H (*scsi card*), idx, bus, dev, slot) DO
			res := PCI.ReadConfigWord(bus, dev, slot, PCI.DevReg, VenID);
			res := PCI.ReadConfigWord(bus, dev, slot, PCI.DevReg+2, DevID);
			host := NIL;
			IF (VenID = 9004H) & (DevID MOD 100H = 78H) THEN	(* Adaptec, DevID = xx78H *)
				CASE DevID DIV 100H OF
				|  50H:  Set(AIC7850, {}, {FeatSpioCap}, "Adaptec AIC-7850", 32, C46);
				
				|  55H:  Set(AIC7850, {FlagPageSCB}, {FeatSpioCap}, "Adaptec AIC-7855", 32, C46);
				
				|  60H:  Set(AIC7860, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled}, {FeatUltra, FeatSpioCap}, 
									"Adaptec AIC-7860 Ultra", 32, C46);
									
				|  61H:  Set(AIC7860, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled}, {FeatUltra, FeatSpioCap},
									"Adaptec AHA-2940A Ultra", 32, C46);
									
				|  70H:  Set(AIC7870, {FlagPageSCB, FlagBiosEnabled}, {}, "Adaptec AIC-7870", 32, C46);
									
				|  71H:  Set(AIC7870, {FlagPageSCB, FlagBiosEnabled}, {}, "Adaptec AHA-294X", 32, C46);
									
				|  72H:  Set(AIC7870, {FlagPageSCB, FlagBiosEnabled, FlagMultiChannel}, {}, "Adaptec AHA-394X", 32, C56);
									
				|  73H:  Set(AIC7870, {FlagPageSCB, FlagBiosEnabled, FlagMultiChannel}, {}, "Adaptec AHA-398X", 32, C56);
									
				|  74H:  Set(AIC7870, {FlagPageSCB, FlagBiosEnabled}, {}, "Adaptec AHA-2944", 32, C46);
									
				|  80H:  Set(AIC7880, {FlagPageSCB, FlagBiosEnabled}, {FeatUltra}, "Adaptec AIC-7880 Ultra", 32, C46);
									
				|  81H:  Set(AIC7880, {FlagPageSCB, FlagBiosEnabled}, {FeatUltra}, "Adaptec AHA-294X Ultra", 32, C46);
									
				|  82H:  Set(AIC7880, {FlagPageSCB, FlagBiosEnabled, FlagMultiChannel}, {FeatUltra},
							"Adaptec AHA-394X Ultra", 32, C56);
									
				|  83H:  Set(AIC7880, {FlagPageSCB, FlagBiosEnabled, FlagMultiChannel}, {FeatUltra},
							"Adaptec AHA-398X Ultra", 32, C56);
									
				|  84H:  Set(AIC7880, {FlagPageSCB, FlagBiosEnabled}, {FeatUltra},"Adaptec AHA-2944 Ultra", 32, C46);
				ELSE
				END;
			ELSIF (VenID = 9004H) & (DevID = 7895H) THEN
				Set(AIC7895, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled, FlagMultiChannel},
									{FeatMoreSRAM, FeatUltra, FeatCmdChan}, "Adaptec AIC-7895 Ultra", 32, C56);
			ELSIF (VenID = 9005H) THEN	(* Adaptec2 *)
				CASE DevID OF
				|  001FH:  Set(AIC7890, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled},
									{FeatMoreSRAM, FeatUltra2, FeatCmdChan, FeatQueueRegs, FeatSGPreload},
									"Adaptec AIC-7890/1 Ultra2", 32, C46);
									
				|  0010H:  Set(AIC7890, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled},
									{FeatMoreSRAM, FeatUltra2, FeatCmdChan, FeatQueueRegs, FeatSGPreload},
									"Adaptec AHA-294X Ultra2", 32, C46);
									
				|  005FH:  Set(AIC7896, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled, FlagMultiChannel},
									{FeatMoreSRAM, FeatUltra2, FeatCmdChan, FeatQueueRegs, FeatSGPreload},
									"Adaptec AIC-7896/7 Ultra2", 32, C56);
									
				|  0050H:  Set(AIC7896, {FlagPageSCB, FlagNewEepromFMT, FlagBiosEnabled, FlagMultiChannel},
									{FeatMoreSRAM, FeatUltra2, FeatCmdChan, FeatQueueRegs, FeatSGPreload},
									"Adaptec AHA-394X Ultra2", 32, C56);
				ELSE
				END;
			END;
			IF host # NIL THEN
				InitPCIHost(host(PCIHost));
				ResetChip(host);
				ConfigureChannels(host(PCIHost));
				LoadSeeprom(host);
	
				IF host.chip IN {AIC7895, AIC7896} THEN
					res := PCI.ReadConfigDword(bus, slot, dev, DEVCONFIG, dw);
					conf := SYSTEM.VAL(SET, dw);
					IF FeatUltra2 IN host.features THEN
						s := host.Get1(host, DSCOMMAND0);
						IF RAMPSMULTRA2 IN s THEN
							host.Put1(host, DSCOMMAND0, s - {SCBRAMSELULTRA2});
							INCL(host.flags, FlagExternalSRam);
							INCL(conf, EXTSCBPEN)
						END
					ELSIF RAMPSM IN conf THEN
						conf := conf + {SCBRAMSEL} - {EXTSCBPEN};
						INCL(host.flags, FlagExternalSRam)
					END;
					res := PCI.WriteConfigDword(bus, slot, dev, DEVCONFIG, SYSTEM.VAL(LONGINT, conf));
					IF host.flags * {FlagExternalSRam, FlagChnlB} # {} THEN  host.Put1(host, CCSCBBADDR, {0})  END
				END;
				
				host.Put1(host, SBLKCTL, host.Get1(host, SBLKCTL) - {DIAGLEDEN, DIAGLEDON});
				IF FeatUltra2 IN host.features THEN
					host.Put1(host, DFFTHRSH, WRDFFTHRSH75 + RDDFFTHRSH75)
				ELSE
					host.Put1(host, DSPCISTATUS, DFTHRSH100)
				END
			END;
			INC(idx)
		END;	(* FindClassCode *)
	ELSE  Kernel.WriteString("Adaptec7.Detect: no PCI found"); Kernel.WriteLn;
	END;
	
	(*DState;*)
	
	(* Now Linux sorts the hosts. I won't do it, unless I find a good reason for it *)
	host := HostRoot;
	WHILE host # NIL DO
		IF DebugConfig THEN
			WriteDriver(host);
			Kernel.WriteString("  "); Kernel.WriteString(DChip[host.chip]);
			Kernel.WriteString("  "); Kernel.WriteString(host.name); Kernel.WriteLn;
			WriteDriver(host);
			FOR i := FeatUltra TO FeatSpioCap DO
				IF i IN host.features THEN Kernel.WriteString("  "); Kernel.WriteString(DFeat[i])  END
			END; Kernel.WriteLn;
			WriteDriver(host);
			FOR i := FlagPageSCB TO FlagExternalSRam DO
				IF i IN host.flags THEN  Kernel.WriteString("  "); Kernel.WriteString(DFlag[i])  END
			END; Kernel.WriteLn;
		END;
		InitHost(host); host := host.next
	END;
	Delay(ResetDelay);
	host := HostRoot;
	WHILE host # NIL DO
		host.wide := FeatWide IN host.features;
		SCSI.RegisterDriver(host); host := host.next
	END;
END Detect;

(* Execute - schedule a scsi command for execution *)

PROCEDURE Execute*(sd: SCSI.Driver; VAR c: SCSI.CommandDesc);	(* linux: aic7xxx_queue *)
VAR
	index: LONGINT; target: SHORTINT; scb: ScbData; d: Host; i: LONGINT; ch: CHAR;
BEGIN
	d := sd(Host);
	target := c.target;
	IF DebugTrace OR DebugCmds THEN
		WriteDevice(d, target); Kernel.WriteString("  -> Execute  ");
		i := 0;
		WHILE i < c.clen DO  SYSTEM.GET(c.cmd+i, ch); DumpChar(ch); Kernel.WriteChar(" "); INC(i)  END;
		Kernel.WriteLn;
	END;
	index := GetEntry(d.freeList);
	IF index = -1 THEN	index := AllocateSCB(d)	END;
	scb := d.scb[index];
		(*link tag to command*)
	c.done := FALSE; c.status := SCSI.Good; c.result := SCSI.OK;
	scb.cmd.target := target; scb.cmd.lun := c.lun; scb.cmd.status := c.status;
	scb.cmd.result := c.result; scb.cmd.cmd := c.cmd; scb.cmd.data := c.data;
	scb.cmd.ptrToCmd := SYSTEM.ADR(c);
		(*build hwscb*)
	d.hwscb[index].control := 0X;
	scb.flags := {};
	scb.tagAction := 0X;
	IF DisconnectEnable & (target IN d.disconnect) THEN
		CSETBIT(d.hwscb[index].control, HwScbDiscEnable);
		IF target IN d.tagged THEN
			c.tag := d.hwscb[index].tag;
			INC(d.dev[target].commandsSent);
			IF d.dev[target].commandsSent<200 THEN
				COR(d.hwscb[index].control, SCSI.MsgSimpleQTag);
				scb.tagAction := SCSI.MsgSimpleQTag
			ELSE
				IF target IN d.orderedQueue THEN
					COR(d.hwscb[index].control, SCSI.MsgOrderedQTag);
					scb.tagAction := SCSI.MsgOrderedQTag
				ELSE
					COR(d.hwscb[index].control, SCSI.MsgSimpleQTag);
					scb.tagAction := SCSI.MsgSimpleQTag
				END;
				d.dev[target].commandsSent:=0
			END
		END
	END;
	IF (DeviceScanned IN d.dev[target].flags) & (c.lun = 0) & ~(target IN (d.widthPending+d.syncPending)) THEN
		IF (target IN d.needWidthTrasm) THEN
			IF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" schedule width handling"); Kernel.WriteLn  END;
			INCL(d.widthPending, target); INCL(scb.flags, ScbMsgWidth); scb.tagAction := 0X;
			d.hwscb[index].control := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, d.hwscb[index].control) * {HwScbDiscEnable} + {HwScbMessage});
		ELSIF (target IN d.needSyncTrasm) THEN
			IF DebugMsg THEN WriteDevice(d, target); Kernel.WriteString(" schedule sync handling"); Kernel.WriteLn  END;
			INCL(d.syncPending, target); INCL(scb.flags, ScbMsgSync); scb.tagAction := 0X;
			d.hwscb[index].control := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, d.hwscb[index].control) * {HwScbDiscEnable} + {HwScbMessage});
		END
	END;
	d.hwscb[index].targ := CHR(SYSTEM.LSH(target MOD 16, 4)+SYSTEM.LSH(c.chan MOD 2, 3)+c.lun MOD 8);
	d.hwscb[index].cmdLen := CHR(c.clen);
	d.hwscb[index].cmdPtr := c.cmd;
	
	(* do not use scatter-gather list now, simplify*)
	d.hwscb[index].resSGcnt := 0X;
	IF c.dlen # 0 THEN
		d.hwscb[index].SGcnt := 1X;
		d.hwscb[index].SGptr := SYSTEM.ADR(c.data);
		d.hwscb[index].dataPtr := c.data;
		d.hwscb[index].dataCnt := c.dlen;
	ELSE
		d.hwscb[index].SGcnt := 0X;
		d.hwscb[index].SGptr := 0;
		d.hwscb[index].dataPtr := 0;
		d.hwscb[index].dataCnt := 0
	END;
	scb.flags := scb.flags + {ScbActive, ScbWaitingQ};
	SYSTEM.CLI();
	d.wait.Put(scb);
	RunWaitingQueue(d);
	SYSTEM.STI();
	WHILE ~c.done DO END;
	IF DebugTrace OR DebugCmds THEN
		WriteDevice(d, target); Kernel.WriteString("  <- Execute  "); SYSTEM.GET(c.cmd, ch); DumpChar(ch);
		Kernel.WriteString("  with result "); Kernel.WriteInt(c.status, 2);
		Kernel.WriteLn;
	END;
END Execute;

(* Cleanup - Remove driver *)

PROCEDURE Cleanup*;
VAR i: SHORTINT; p: Host;
BEGIN
	p := HostRoot;
	WHILE p # NIL DO
		SCSI.RemoveDriver(p);
		p := p.next
	END;
	i := 0;
	WHILE i < 32 DO
		IF i IN InstalledIRQ THEN
			Kernel.RemoveIP(InterruptHandler, Kernel.IRQ+i)
		END;
		INC(i)
	END;
	InstalledIRQ := {};
END Cleanup;

(** Install the Disk upcalls. *)

PROCEDURE Install*;
BEGIN	SCSI.Install
END Install;

(* StrToInt - Convert a string to an integer *)

PROCEDURE StrToInt(s: ARRAY OF CHAR): LONGINT;
VAR i, j: SHORTINT;  v, sgn, m: LONGINT;
BEGIN
	j := 0;  WHILE s[j] # 0X DO INC(j) END;
	IF (j > 0) & (CAP(s[j-1]) = "H") THEN m := 16; DEC(j) ELSE m := 10 END;
	v := 0;  i := 0;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	WHILE i < j DO
		IF (s[i] >= "0") & (s[i] <= "9") THEN v := v*m + (ORD(s[i])-ORD("0"))
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN v := v*m + (ORD(CAP(s[i]))-ORD("A")+10)
		ELSE sgn := 0;  j := i
		END;
		INC(i)
	END;
	RETURN sgn*v
END StrToInt;

(* Init - Initialize module, read kernel configuration *)

PROCEDURE Init;
VAR str: ARRAY 32 OF CHAR; i: SET;
	PROCEDURE SetRate(i: LONGINT; r, r1, r2, p: SHORTINT);
	BEGIN
		SyncRate[i].rate[Rate] := r;  SyncRate[i].rate[RateUltra] := r1;
		SyncRate[i].rate[RateUltra2] := r2;  SyncRate[i].period := p;
	END SetRate;
BEGIN
	Kernel.GetConfig("Ada7Debug", str); i := SYSTEM.VAL(SET, StrToInt(str));
	DebugTrace := 0 IN i;  DebugTraceInts := 1 IN i;  DebugMsg := 2 IN i;  DebugSCB := 3 IN i;
	DebugSequencer := 4 IN i;  DebugReset := 5 IN i;  DebugConfig := 6 IN i;  DebugPeriod := 7 IN i;
	DebugCmds := 8 IN i;
	IF i # {} THEN
		Kernel.WriteString("Adaptec7: Ada7Debug = "); Kernel.WriteHex(SYSTEM.VAL(LONGINT, i),0); Kernel.WriteLn
	END;
	
	Kernel.GetConfig("Ada7ResetDelay", str); ResetDelay := StrToInt(str);
	IF ResetDelay = 0 THEN  ResetDelay := 1000  END;
	Kernel.WriteString("Adaptec7: Ada7ResetDelay = "); Kernel.WriteInt(ResetDelay, 0); Kernel.WriteLn;
	
	SetRate(00, -01, -01, 13H, 10);
	SetRate(01, -01, -01, 14H, 11);
	SetRate(02, -01, 00H, 15H, 12);
	SetRate(03, -01, 10H, 16H, 15);
	SetRate(04, -01, 20H, 17H, 18);
	SetRate(05, 00H, 00H, 18H, 25);
	SetRate(06, 10H, 10H, 19H, 31);
	SetRate(07, 20H, 20H, 1AH, 37);
	SetRate(08, 30H, 30H, 1BH, 43);
	SetRate(09, 40H, 40H, 1CH, 50);
	SetRate(10, 50H, 50H, -01, 56);
	SetRate(11, 60H, 60H, -01, 62);
	SetRate(12, 70H, 70H, -01, 68);
	SetRate(13, -01, -01, -01, 0);
END Init;

BEGIN
	Kernel.WriteString("Adaptec7 / 0.9.4"); Kernel.WriteLn;
	InstalledIRQ := {};
	HostRoot := NIL;
	(*NEW(timerTask);  timerTask.handler := TimerHandler;  nofTimers := 0;*)
	Init;
	(*debug trace*)
	(* ProgTools.DebugList DFlag ^ *)
	DFlag[FlagPageSCB] := "PageSCB";
	DFlag[FlagNewEepromFMT] := "NewEepromFMT";
	DFlag[FlagBiosEnabled] := "BiosEnabled";
	DFlag[FlagMultiChannel] := "MultiChannel";
	DFlag[FlagChnlB] := "ChnlB";
	DFlag[FlagChnlC] := "ChnlC";
	DFlag[FlagTermEnbA] := "TermEnbA";
	DFlag[FlagTermEnbB] := "TermEnbB";
	DFlag[FlagTermEnbSELow] := "TermEnbSELow";
	DFlag[FlagTermEnbSEHigh] := "TermEnbSEHigh";
	DFlag[FlagSeepromFound] := "SeepromFound";
	DFlag[FlagChannelBPrimary] := "ChannelBPrimary";
	DFlag[FlagExtendTransA] := "ExtendTransA";
	DFlag[FlagExternalSRam] := "ExternalSRam";
	DFlag[FlagHandlingReqInits] := "HandlingReqInits";
	
	(* ProgTools.DebugList DFeat ^ *)
	DFeat[FeatUltra] := "Ultra";
	DFeat[FeatUltra2] := "Ultra2";
	DFeat[FeatWide] := "Wide";
	DFeat[FeatTwin] := "Twin";
	DFeat[FeatMoreSRAM] := "MoreSRAM";
	DFeat[FeatCmdChan] := "CmdChan";
	DFeat[FeatQueueRegs] := "QueueRegs";
	DFeat[FeatSGPreload] := "SGPreload";
	DFeat[FeatSpioCap] := "SpioCap";
	
	(* ProgTools.DebugList DDev ^ *)
	DDev[DevicePresent] := "DevicePresent";
	DDev[DeviceBusResetPending] := "DeviceBusResetPending";
	DDev[DeviceTimeout] := "DeviceTimeout";
	DDev[DevicePrintSync] := "DevicePrintSync";
	DDev[DevicePrintWidth] := "DevicePrintWidth";
	DDev[DeviceSuccess] := "DeviceSuccess";
	DDev[DeviceTaggedSuccess] := "DeviceTaggedSuccess";
	DDev[DeviceScanned] := "DeviceScanned";

	(* ProgTools.DebugList DChip ^ *)
	DChip[AIC7770] := "AIC7770";
	DChip[AIC7850] := "AIC7850";
	DChip[AIC7860] := "AIC7860";
	DChip[AIC7870] := "AIC7870";
	DChip[AIC7880] := "AIC7880";
	DChip[AIC7890] := "AIC7890";
	DChip[AIC7895] := "AIC7895";
	DChip[AIC7896] := "AIC7896";

	(* Debug, avoid timers*)
	jiffies := MAX(LONGINT);
	
	ASSERT((SIZE(SCSI.DriverDesc) + RecordPadding) MOD 32 = 0, 110);
	
	Detect;
	Install
END Adaptec7.


AIC7xxx.Invariant

-- init
AIC7xxx.Detect

-- debug
AIC7xxx.DList		Dump the device list
AIC7xxx.DState

AIC7xxx.Cleanup

System.Free AIC7xxx AIC7xxxScript ~