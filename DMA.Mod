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

MODULE DMA;	(** non-portable *)	(** tb, SS96 *)
IMPORT SYSTEM, Kernel, Modules;

(**
DMA-Module : Offers functions to program the two DMA-Controllers with their channels 0-7. 
Autor : Thomas Burri, according to M. Tischer/B. Jennrich PC intern 4
letzter Update:  
*)

CONST
	BufSize* = 65536;	(** buffersize is max. 64kB *)	(* also change Sound.DBdataSize *)

	(** bits of statusregisters *)
	SREQ3* = {7};	(** is bit set: the DMA-channel received DMA-request *)
	SREQ2* = {6}; 
	SREQ1* = {5};
	SREQ0* = {4};
	STC3* = {3};	(** is bit set: since last reading of statusregister, a DMA-transfer *)
	STC2* = {2};	(** was finished => terminal count arised *)
	STC1* = {1};
	STC0* = {0};

	(** bits of commandregisters *)
	CMDDACKLEVEL* = {7};	(** bit 7: DMA Acknowledge level ; default: 0 = low active *)
	CMDDREQLEVEL* = {6};	(** bit 6: REQ Acknowledge level; default: 0 = high active *)
	CMDEXTWRITE* = {5};	(** bit 5, 0: exteneded write, 1: late write; default: 0 = late write *)
	CMDFIXEDPRI* = {4};	(** bit 4: prioritybuilding; default: 0 = static prio, channel 0 has highest *)
	CMDCOMPRESS* = {3};	(** bit 3 : compressed access; default: 0 = normal access *)
	CMDINACTIVE* = {2};	(** bit 2 : controllerstatus; default: 0 = controller active *)
	CMDADH0* = {1};		(** bit 1 : always 0, because used with mem-to-mem *)
	CMDMEM2MEM*  = {0};	(** bit 0 : always 0, because mem-to-mem not supported *)

	(* bits of requestregisters *)
	REQRESERVED = {7,6,5,4,3};	(* reserved bits set always to 0 *)
	REQSET = {2};	(* set DMA request *)
	REQCLR = {};	(* delete DMA-request *)
	REQMSK = {0,1};	(* this two bits select the channel *)

	(* bits of channelmaskingsregisters *)
	CHRESERVED = {7,6,5,4,3};	(* reserved bits set always to 0 *)
	CHSET = {2};	(* mask/block DMA-channel *)
	CHCLR = {};	(* free DMA-channel *)
	CHMSK = {0,1};	(* this two bits select the channel *)

	(** bits of moderegisters *)
	MDEMAND* = {};	(** transfer on demand  *)
	MSINGLE* = {6};	(** transfer single value *)
	MBLOCK* = {7};	(** blocktransfer *)
	MCASCADE* = {7,6};	(** cascading transfer *)
	MDEC* = {5};	(** decrementing address *)
	MAUTOINIT* = {4};	(** autoinitialisation after reach the endaddress *)
	MVERIFY* = {};	(** verify *)
	MWRITE* = {2};	(** write to memory *)
	MREAD* = {3};	(** read from memory *)
	MINVALID* = {3,2};	(** invalid *)
	MCHMSK* = {0,1};	(** this two bits select the channel *)

VAR
	TransBufAdr*: LONGINT;	(** address of transferbuffer *)
	dadr, dcnt, dpge: ARRAY 8 OF INTEGER;	(* dadr: dma_adress, dcnt: dma_count, dpge: dma_page *)
	done: BOOLEAN;	(* done = TRUE means, buffer is allocated *)
	(* register-offsets for master and slave controller *)
	dstat, dcmd, dreq, dchmask, dmode,	(* status, command, request, channelmask, mode *)
	dff, dmclr, dtemp, dmaskclr, dmask: ARRAY 2 OF INTEGER;	(* flipflop, masterclr, temporary, maskclr, mask *)

(** Masterclear : reset the controller of the chosen channel *)
PROCEDURE MasterClear*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dmclr[Chan DIV 4], SYSTEM.VAL(CHAR,0));
END MasterClear;

(** SetRequest : release transfer on the chosen channel *)
PROCEDURE SetRequest*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dreq[Chan DIV 4], SYSTEM.VAL(CHAR, REQSET+(SYSTEM.VAL(SET, Chan)*CHMSK)));
END SetRequest;

(** ClrRequest : stop transfer on the chosen channel *)
PROCEDURE ClrRequest*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dreq[Chan DIV 4], SYSTEM.VAL(CHAR, REQCLR+(SYSTEM.VAL(SET, Chan)*CHMSK)));
END ClrRequest;

(** SetMask : mask/block chosen channel *)
PROCEDURE SetMask*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dchmask[Chan DIV 4], SYSTEM.VAL(CHAR, CHSET+(SYSTEM.VAL(SET, Chan)*CHMSK)));
END SetMask;

(** ClrMask : free chosen channel *)
PROCEDURE ClrMask*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dchmask[Chan DIV 4],SYSTEM.VAL(CHAR, CHCLR+(SYSTEM.VAL(SET, Chan)*CHMSK)));
END ClrMask;

(** ReadStatus : read statusregister of the controller of the chosen channel *)
PROCEDURE ReadStatus*(Chan : INTEGER) : SYSTEM.BYTE;
	VAR val: SYSTEM.BYTE;
BEGIN
	SYSTEM.PORTIN(dstat[Chan DIV 4], val);
	RETURN val;
END ReadStatus;

(** ClrFlipFlop : reset flipflop of the controller of the chosen channel; the flipflop will be used
to differ between the Lo- and the Hi-byte transferaddress or the transfercounter *)
PROCEDURE ClrFlipFlop*(Chan : INTEGER);
BEGIN
	SYSTEM.PORTOUT(dff[Chan DIV 4], SYSTEM.VAL(CHAR, 0));
END ClrFlipFlop;

(** ReadCount : read transfercounter of the chosen channel; value is between 0 and 65535 *)
PROCEDURE ReadCount*(Chan : INTEGER) : LONGINT;
	VAR l, h : LONGINT;
BEGIN
	l:= 0; h:= 0;
	ClrFlipFlop(Chan);
	SYSTEM.PORTIN(dcnt[Chan], SYSTEM.VAL(CHAR, l));
	SYSTEM.PORTIN(dcnt[Chan], SYSTEM.VAL(CHAR, h));
	RETURN h * 256 + l;
END ReadCount;

(** SetCommand: set commandregister of chosen controller; Info: it isn't possible to read out 
the register, so the standard values for the bits have to be assumed *)
PROCEDURE SetCommand*(controller: INTEGER; cmd: SET);
BEGIN
	SYSTEM.PORTOUT(dcmd[controller], SYSTEM.VAL(CHAR, cmd))
END SetCommand;

(** SetChannel : Prepare DMA-channel for transfer *)
PROCEDURE SetChannel*(Chan : INTEGER; MemAdr, Size : LONGINT; Mode : SET);
	VAR  Adress : LONGINT; Page : INTEGER;
BEGIN
	SetMask(Chan);	(* block channel *)
	(* DMA transferes 1 byte more than given! Size should be at least 1 byte *)
	IF Size # 0 THEN DEC(Size) END;

	(* -create linear 20-bit address -------------------------------- *)
	IF Chan <= 3 THEN	(* 8 bit DMA *)
		Adress := MemAdr MOD 10000H;	(* address = low 16 bit of the 20-bit address *)
		Page := SHORT(MemAdr DIV 10000H);	(* page = high 4 bit of the 20-bit address *)
	ELSE	(* 16 bit DMA *)
		Adress := (MemAdr DIV 2) MOD 10000H;	(* address = low 16 Bit of the 20-bit address *)
		Page:= SHORT(((MemAdr DIV 20000H)*2) MOD 100H);	(* page = high 4 bit of the 20-bit address *)
		Size:= Size DIV 2	(* 2 bytes by sample will be counted ! *)
	END;

	SYSTEM.PORTOUT(dmode[Chan DIV 4], SYSTEM.VAL(CHAR, Mode + (SYSTEM.VAL(SET,Chan)*MCHMSK)));

	ClrFlipFlop(Chan);	(* clear address-/counterflipflop and... *)
									(* transfer address to DMA-controller (Lo/Hi-byte) *)
	SYSTEM.PORTOUT(dadr[Chan], SYSTEM.VAL(CHAR, Adress MOD 100H));	(* Lo-byte *)
	SYSTEM.PORTOUT(dadr[Chan], SYSTEM.VAL(CHAR, Adress DIV 100H));	(* Hi-byte *)
	SYSTEM.PORTOUT(dpge[Chan], SYSTEM.VAL(CHAR, Page));	(* set mem-page *)
	ClrFlipFlop(Chan);	(* clear address-/counterflipflop and ... *)
									(* transfer counter to DMA-controller (Lo/Hi-byte) *)
	SYSTEM.PORTOUT(dcnt[Chan], SYSTEM.VAL(CHAR, Size MOD 100H));	(* Lo-byte *)
	SYSTEM.PORTOUT(dcnt[Chan], SYSTEM.VAL(CHAR, Size DIV 100H));	(* Hi-byte *)
	ClrMask(Chan);	(* free DMA-channel *)
END SetChannel;

(** Init : Allocation of DMA-available memory. It is be exported as 'TransBufAdr'. *)

PROCEDURE Init*;
VAR p: LONGINT;
BEGIN
	IF ~done THEN
		Kernel.NewDMA(BufSize, TransBufAdr, p);
		ASSERT(p = TransBufAdr);	(* assume virtual and physical address the same *)
		done := TRUE
	END
END Init;

PROCEDURE Cleanup;
BEGIN
	IF done THEN
		done := FALSE;
		Kernel.DisposeDMA(BufSize, TransBufAdr)
	END
END Cleanup;

BEGIN
	(* initialisation of helparrays *)
	dadr[0]:=0;dadr[1]:=2;dadr[2]:=4;dadr[3]:=6;dadr[4]:=0C0H;dadr[5]:=0C4H;
	dadr[6]:=0C8H;dadr[7]:=0CCH;dcnt[0]:=1;dcnt[1]:=3;dcnt[2]:=5;dcnt[3]:=7;
	dcnt[4]:=0C2H;dcnt[5]:=0C6H;dcnt[6]:=0CAH;dcnt[7]:=0CEH;dpge[0]:=087H;
	dpge[1]:=083H;dpge[2]:=081H;dpge[3]:=082H;dpge[4]:=088H;dpge[5]:=08BH;
	dpge[6]:=089H;dpge[7]:=08AH;
	dstat[0]:=8;dstat[1]:=0D0H;dcmd[0]:=8;dcmd[1]:=0D0H;dreq[0]:=9;dreq[1]:=0D2H;
	dchmask[0]:=0AH;dchmask[1]:=0D4H;dmode[0]:=0BH;dmode[1]:=0D6H;dff[0]:=0CH;
	dff[1]:=0D8H;dmclr[0]:=0DH;dmclr[1]:=0DAH;dtemp[0]:=0DH;dtemp[1]:=0DAH;
	dmaskclr[0]:=0EH;dmaskclr[1]:=0DCH;dmask[0]:=0FH;dmask[1]:=0DEH;
	done:= FALSE; TransBufAdr:= -1;
	Modules.InstallTermHandler(Cleanup)
END DMA.
