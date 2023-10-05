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

MODULE DSP;	(** non-portable *)	(** tb, SS96 *)
IMPORT Kernel, SYSTEM;

(**
DSP-Module : offers functions for programming the DSP of the SoundBlaster or compatible
Author : Thomas Burri, according to M. Tischer/B. Jennrich PC intern 4
Last  Update :  
Remark : Mixer available since DSP 2.01+

08.07.96 pjm - Kernel.SetTimeout replaced with Kernel.GetTimer
17.10.96 pjm - check for GETVER in DspWrite
*)

CONST
	(** res codes *)
	Done* = 0;
	Failed* = 1;
	ResetErr* = 2;

	(** HALT codes *)
	DSPIOError* = 91;
	
	(** DSP constants *)
	(** versionsnumbers *)
	DSP1XX* = 100H;
	DSP200* = 200H;
	DSP201* = 210H;	(* perhaps it's a error in the book and it should be 201H;
										change if any problems occure *)
	DSP3XX* = 300H;
	DSP4XX* = 400H;

	(** DSP commands *)
	(** DSP1.xx *)
	DIRECTDAC8* = 10H;	(** 8 bit direct sample playing *)
	DMADAC8* = 14H;	(** 8 bit single cycle DMA playing *)
	DMAADPCM8b2bSC* = 16H;	(** 8/2-bit-ADPCM single cycle DMA playing *)
	DMAADPCM8b2bSCR* = 17H;	(** 8/2-bit-ADPCM single cycle DMA playing with refbyte *)
	DIRECTADC8* = 20H;	(** 8 bit direct sample recording *)
	DMAADC8* = 24H;	(** 8 bit single cycle DMA recording *)
	DMAADPCM8b4bSC* = 74H;	(** 8/4-bit-ADPCM single cycle DMA playing *)
	DMAADPCM8b4bSCR* = 75H;	(** 8/4-bit-ADPCM single cycle DMA playing with refbyte *)
	DMAADPCM8b3bSC* = 76H;	(** 8/3-bit-ADPCM single cycle DMA playing *)
	DMAADPCM8b3bSCR* = 77H;	(** 8/3-bit-ADPCM single cycle DMA playing with refbyte *)
	DMAPAUSE* = 0D0H;	(** 8Bit DMA-Transfer pause *)
	DMACONT* = 0D4H;	(** 8Bit DMA-Transfer continue *)
	GETVER* = 0E1H;	(** get DSP-version number *)
	(** DSP2.xx*)
	DMAADPCM8b2bAI* = 1FH;	(** 8/2-bit-ADPCM autoinit DMA playing *)
	DMAADPCM8b3bAI* = 7FH;	(** 8/3-bit-ADPCM autoinit DMA playing *)
	DMAADPCM8b4bAI* = 7DH;	(** 8/4-bit-ADPCM autoinit DMA playing *)
	DMAAUTODAC8* = {4,3,2};	(** 1CH ; autoinitialize playmode *)
	DMAAUTOADC8* = {5,3,2};	(** 2CH ; auotinitialize recordmode *)
	DSPEXITAUTOINIT*  = 0DAH;	(** exit autoinitalize mode *)
	(** DSP2.01+ *)
	DSP2p8HIDMAAUTODAC* =  90H;	(** 90H; HiSpeed-Commands for DSP 2.01+ & 3.xx *)
	DSP2p8HIDMAAUTOADC* = {7,4,3};	(** 98H *)
	DSP2p8HIDMADAC* = 91H;	(** HiSpeed single cycle play *)
	DSP2p8HIDMAADC* = 99H;	(** HiSpeed single cycle record *)
	(** DSP3.xx *)
	DSP3MADC* = 0A0H;	(** set inputmode to Mono *)
	DSP3STADC* = 0A8H;	(** set inputmode to Stereo *)
	(** DSP4.xx *)
	DSP4CMDADC* = {3};	(** record *)
	DSP4CMDDAC* = {};	(** play *)
	DSP4CMDAUTOINIT* = {2};	(** bit for autoinit mode *)
	DSP4CMDFIFO* = {1};	(** 02H; for use of FIFO of the DSP *)
	DSP4PAUSE16* = 0D5H;	(** stop the DMA-transfer in 16 bit mode *)
	DSP4CONT16* = 0D6H;	(** continue DMA-transfer in 16 bit mode *)
	DSP4CMD8DMA* = {7, 6};	(** 0C0H; hi-nibbles for 8 and 16 Bit commands *)
	DSP4CMD16DMA* = {7, 5, 4};	(** 0B0H *)
	DSP4EXIT16DMA* = 0D9H;	(** end 16 bit DMA-transfer *)
	DSP4EXIT8DMA* = 0DAH;	(** end 8 bit DMA-transfer *)
	DSP4MST* = {5};	(** 20H; Stereo mode *)
	DSP4MM* = {};	(** Mono mode *)
	DSP4MSIG* =  {4};	(** 10H; singed data *)
	DSP4MUNSIG* =  {};	(** unsigned data *)

	(* DSP versions, to use with the Names-array *)
	SBNONE = 0;	(* no DSP recognized *)
	SB1XX = 1;	(* DSP-version 1.00 to 2.00 *)
	SB2XX = 2;	(* DSP-version 2.01 to 2.99 *)
	SB3XX = 3;	(* DSP-version 3.00 to 3.9 *)
	SB4XX = 4;	(* DSP-version 4.00 to 4.99 *)
	SBXXX = 5;	(* DSP-version > 4.99 *)

	(** in use with DSP3.XX SetADCCFilter3 and SetSpeaker *)
	ON* = TRUE;
	OFF* = FALSE;


	(** Mixer  constants *)
	(* CT1745 *)
	M3ADCSTATE = 0CH;	(* input-filter, lowpass-filter and DSP-inputsource *)
	M3DACSTATE = 0EH;	(* output-filter and stereo-switch *)
	M4OUTSOURCE = 3CH;	(* output sources *)
	M4ADCSOURCEL = 3DH;	(* input sources L/R *)
	M4ADCSOURCER = 3EH;
	M4IRQSOURCE* = 82H;	(** register which shows the interrupt type *)
	M4IRQ8DMA* = {0};	(** interrupt of 8-Bit DMA or Midi *)
	M4IRQ16DMA* = {1};	(** interupt of 16-Bit DMA *)
	M4IRQMPU* = {2};	(** interrupt of MPU *)
	
	(* constant for access to helparrays *)
	MASTER = 0;
	MIDI = 1;
	CD = 2;
	VOICE = 3;
	LINE = 4;
	MIC = 5;
	PCSPEAKER = 6;

TYPE
	(** SoundBlaster definintion record with portadress, irq-number and low&high DMA-number *)
	SBDef* = RECORD
		DspPort*,DspDmaB*, DspDmaW*, DspIrq*, DspVersion* : INTEGER;
		DspName* : ARRAY 64 OF CHAR
	END;

VAR
	res*: INTEGER;	(** Done, Failed, ResetErr *)
	(* DSP VAR *)
	Names : ARRAY 6, 32 OF CHAR;	(* names of the SoundBlaster cards *)
	DSPBase : SBDef;
	base, wport, rsport, rdport, resetport, mixregport, mixdatport: INTEGER;
	
	(* Mixer VAR*)
	Mix4SourceL, Mix4SourceR: SET;
	Mix3DACStereo, Mix3DACFilter, Mix3ADCFilter: BOOLEAN;
	M2VT : ARRAY 4 OF INTEGER;	(* Mixer2VolumeTable *)
	M3VT : ARRAY 6 OF INTEGER;	(* Mixer3VolumeTable *)
	M4VT : ARRAY 7 OF INTEGER;	(* Mixer4VolumeTable *)

(*----------------------------------------------------------------------------*)	
(** Mixer *)
(** MixWrite : writes data to Mixer-chip *)
PROCEDURE MixWrite*(reg: INTEGER; data: SET);
BEGIN
	SYSTEM.PORTOUT(mixregport, SYSTEM.VAL(CHAR, reg));
	SYSTEM.PORTOUT(mixdatport, SYSTEM.VAL(CHAR, data))
END MixWrite;

(** MixRead : reads data from Mixer-chip *)
PROCEDURE MixRead*(reg: INTEGER): SET;
	VAR data : SET;
BEGIN
	SYSTEM.PORTOUT(mixregport, SYSTEM.VAL(CHAR, reg));
	data:= {};
	SYSTEM.PORTIN(mixdatport, SYSTEM.VAL(CHAR, data));
	RETURN data
END MixRead;

(* InitMixer : initialize Mixer-chip of the soundcard *)
PROCEDURE InitMixer(reset: BOOLEAN);
BEGIN
	mixregport:= DSPBase.DspPort + 4H;
	mixdatport:= DSPBase.DspPort + 5H;
	IF reset THEN MixWrite(0H, {}) END
END InitMixer;

(** SetVolume2 : sets volume of this channel *)
PROCEDURE SetVolume2*(Ch, val: LONGINT);
BEGIN
	res:= Done;
	CASE Ch OF
		MASTER, MIDI, CD, VOICE:
			MixWrite(M2VT[Ch], MixRead(M2VT[Ch])*{7,6,5,4,0} + SYSTEM.VAL(SET,val*2))
	ELSE res:= Failed
	END	
END SetVolume2;

(** GetVolume2 : gets volume of this channel *)
PROCEDURE GetVolume2*(Ch: LONGINT; VAR val: LONGINT);
BEGIN
	res:= Done;
	CASE Ch OF
		MASTER, MIDI, CD, VOICE:
			val:= SYSTEM.VAL(LONGINT, MixRead(M2VT[Ch])) DIV 2
	ELSE res:= Failed
	END
END GetVolume2;

(** SetADCFilter3 : turn on/off ADC-filter ; filter is low-active ! *)
PROCEDURE SetADCFilter3*(State : BOOLEAN);
BEGIN
	IF State THEN
		MixWrite(M3ADCSTATE, MixRead(M3ADCSTATE) - {5})
	ELSE MixWrite(M3ADCSTATE, MixRead(M3ADCSTATE) + {5})
	END
END SetADCFilter3;

(** GetADCFilter : gets state of ADC-filter ; filter is low-active ! *)
PROCEDURE GetADCFilter3*(): BOOLEAN;
BEGIN
	RETURN MixRead(M3ADCSTATE)*{5} = {}
END GetADCFilter3;

(** SetDACFilter3 : turn on/off DAC-filter ; filter is low-active ! *)
PROCEDURE SetDACFilter3*(State: BOOLEAN);
BEGIN
	IF State THEN MixWrite(M3DACSTATE, MixRead(M3DACSTATE) - {5})
	ELSE MixWrite(M3DACSTATE, MixRead(M3DACSTATE) + {5})
	END
END SetDACFilter3;

(** GetDACFilter3 : gets state of DAC-filter ; filter is low-active ! *)
PROCEDURE GetDACFilter3*(): BOOLEAN;
BEGIN
	RETURN MixRead(M3DACSTATE)*{5} = {}
END GetDACFilter3;

(** SetDACStereo3 : turn on/off stereo-playing *)
PROCEDURE SetDACStereo3*(State: BOOLEAN );
BEGIN
	IF State THEN MixWrite(M3DACSTATE, MixRead(M3DACSTATE) + {1})
	ELSE MixWrite(M3DACSTATE, MixRead(M3DACSTATE) - {1})
	END
END SetDACStereo3;

(** GetDACStereo3 : gets state of stereo-playing *)
PROCEDURE GetDACStereo3*(): BOOLEAN;
BEGIN
  RETURN MixRead(M3DACSTATE)*{1} # {}
END GetDACStereo3;

(** SetLowPass3 : sets filter to 3.3Khz if State = FALSE else to 8.8Khz *)
PROCEDURE SetLowPass3*(State : BOOLEAN);
BEGIN
	IF State THEN MixWrite(M3ADCSTATE, MixRead(M3ADCSTATE) + {3})
	ELSE MixWrite(M3ADCSTATE, MixRead(M3ADCSTATE) - {3})
	END
END SetLowPass3;

(** GetLowPass3 : gets state of filterbit *)
PROCEDURE GetLowPass3*() : BOOLEAN;
BEGIN
  RETURN MixRead(M3ADCSTATE)*{3} # {};
END GetLowPass3;

(** SetSource3 : sets sample-source to SubCh; val doesn't matter,
because only one source can be set to ON at a time *)
PROCEDURE SetSource3*(SubCh: LONGINT);
BEGIN
	MixWrite(0CH, MixRead(0CH)*{7,6,5,4,3,0} + SYSTEM.VAL(SET, SubCh*2))
END SetSource3;

(** GetSource3 : gets sample-source which is ON *)
PROCEDURE GetSource3*(VAR SubCh: LONGINT);
BEGIN
	SubCh:= SYSTEM.VAL(LONGINT, MixRead(M3ADCSTATE)*{2,1}) DIV 2
END GetSource3;

(** PrepareForStereo3 : prepare Mixer for stereo playing/recording *)
PROCEDURE PrepareForStereo3*(Mode: BOOLEAN);
BEGIN
	(* backup actual Mixer-states *)
	Mix3DACStereo:= GetDACStereo3();
	Mix3DACFilter:= GetDACFilter3();
	Mix3ADCFilter:= GetADCFilter3();
	(* turn off filter and stereo-playing *)
	SetDACStereo3(Mode);
	SetDACFilter3(FALSE);
	SetADCFilter3(FALSE)
END PrepareForStereo3;

(** RestoreFromStereo3 : restore Mixer-state *)
PROCEDURE RestoreFromStereo3*;
BEGIN                    
	SetDACStereo3(Mix3DACStereo);
	SetDACFilter3(Mix3DACFilter);
	SetADCFilter3(Mix3ADCFilter);
END RestoreFromStereo3;

(** SetVolume3 : sets output volume *)
PROCEDURE SetVolume3*(Ch, left, right : LONGINT);
BEGIN
	res:= Done;
	CASE Ch OF
		MASTER, MIDI, CD, VOICE, LINE:
			MixWrite( M3VT[Ch], SYSTEM.VAL(SET, left*32)+SYSTEM.VAL(SET, right*2))
		|MIC: MixWrite(M3VT[Ch], MixRead(M3VT[Ch])*{7,6,5,4,3}+SYSTEM.VAL(SET, left*2))
	ELSE
		res:= Failed
	END
END SetVolume3;

(** GetVolume3 : gets volume *)
PROCEDURE GetVolume3*(Ch: LONGINT; VAR left, right: LONGINT);
	VAR tmp: SET;
BEGIN
	res:= Done;
	tmp:= MixRead(M3VT[Ch]);
	CASE Ch OF
		MASTER, MIDI, CD, VOICE, LINE:
			left:= SYSTEM.VAL(LONGINT, tmp*{7,6,5,4}) DIV 32;
			right:=SYSTEM.VAL(LONGINT, tmp*{3,2,1,0}) DIV 2
		|MIC: left:= SYSTEM.VAL(LONGINT, tmp*{2,1,0}) DIV 2; right:= 0
	ELSE
		res:= Failed
	END
END GetVolume3;

(** PrepareForMonoADC4 : backup Mixer-state *)
PROCEDURE PrepareForMonoADC4*;
BEGIN
	Mix4SourceL:= MixRead(M4ADCSOURCEL );
	Mix4SourceR:= MixRead(M4ADCSOURCER);
	MixWrite(M4ADCSOURCEL, Mix4SourceL + Mix4SourceR)
END PrepareForMonoADC4;

(** RestoreFromMonoADC4 : restore Mixer-state as before *)
PROCEDURE RestoreFromMonoADC4*;
BEGIN
	MixWrite(M4ADCSOURCEL, Mix4SourceL);
	MixWrite(M4ADCSOURCEL, Mix4SourceR)
END RestoreFromMonoADC4;

(** SetInSourceL4 : sets or deletes the bit SubCh of the inputsourceregister for left channel *)
PROCEDURE SetInSourceL4*(SubCh, val: LONGINT);
BEGIN
	IF val = 1 THEN MixWrite(3DH, MixRead(3DH) + {SubCh})
	ELSE MixWrite(3DH, MixRead(3DH) - {SubCh}) END
END SetInSourceL4;

(** SetInSourceR4 : sets or deletes the bit SubCh of the inputsourceregister for right channel *)
PROCEDURE SetInSourceR4*(SubCh, val: LONGINT);
BEGIN
	IF val = 1 THEN MixWrite(3EH, MixRead(3EH) + {SubCh})
	ELSE MixWrite(3EH, MixRead(3EH) - {SubCh}) END
END SetInSourceR4;

(** GetInSourceL4 : gets bit SubCh of the inputsourceregister for left channel *)
PROCEDURE GetInSourceL4*(SubCh: LONGINT; VAR val: LONGINT);
BEGIN
	IF SubCh IN MixRead(3DH) THEN val:= 1 ELSE val:= 0 END
END GetInSourceL4;

(** GetInSourceR4 : gets bit SubCh of the inputsourceregister for right channel *)
PROCEDURE GetInSourceR4*(SubCh: LONGINT; VAR val: LONGINT);
BEGIN
	IF SubCh IN MixRead(3EH) THEN val:= 1 ELSE val:= 0 END
END GetInSourceR4;

(** SetOutSource4 : sets or deletes bit SubCh of the outputsourceregister *)
PROCEDURE SetOutSource4*(SubCh, val: LONGINT);
BEGIN
	IF val = 1 THEN MixWrite(M4OUTSOURCE, MixRead(M4OUTSOURCE) + {SubCh})
	ELSE MixWrite(M4OUTSOURCE, MixRead(M4OUTSOURCE) - {SubCh}) END
END SetOutSource4;

(** GetOutSource4 : gets bit SubCh of the outputsourceregister *)
PROCEDURE GetOutSource4*(SubCh: LONGINT; VAR val: LONGINT);
BEGIN
	IF SubCh IN MixRead(M4OUTSOURCE) THEN val:= 1 ELSE val:= 0 END
END GetOutSource4;

(** SetAGC4 : turns AGC (Mic preamplifier) on or off *)
PROCEDURE SetAGC4*(val: LONGINT);	(* low-active, so I do here the inverse action *)
BEGIN
	IF val = 1 THEN MixWrite(43H, MixRead(43H) - {0})
	ELSE MixWrite(43H, MixRead(43H) + {0})
	END
END SetAGC4;

(** GetAGC4 : gets the state of AGC *)
PROCEDURE GetAGC4*(VAR val: LONGINT);
BEGIN
	IF MixRead(43H)*{0} # {} THEN val:= 0 ELSE val:= 1 END
END GetAGC4;

(** SetVolume4 : sets left & right volume of this channel *)
PROCEDURE SetVolume4*(Ch, left, right: LONGINT);
BEGIN
	res:= Done;
	CASE Ch OF
		MASTER, MIDI, CD, VOICE, LINE:
			MixWrite(M4VT[Ch], SYSTEM.VAL(SET, left*8) + MixRead(M4VT[Ch])*{2,1,0} );
			MixWrite(M4VT[Ch]+1, SYSTEM.VAL(SET, right*8) + MixRead(M4VT[Ch]+1)*{2,1,0})
		|MIC: MixWrite(M4VT[Ch], SYSTEM.VAL(SET, left*8) + MixRead(M4VT[Ch])*{2,1,0})
		|PCSPEAKER: MixWrite(M4VT[Ch], SYSTEM.VAL(SET, left*64) + MixRead(M4VT[Ch])*{5,4,3,2,1,0})
	ELSE res:= Failed
	END
END SetVolume4;

(** GetVolume4 : gets left & right volume of this channel *)
PROCEDURE GetVolume4*(Ch: LONGINT; VAR left, right: LONGINT);
BEGIN
	res:= Done;
	CASE Ch OF
		MASTER, MIDI, CD, VOICE, LINE:
			left:= SYSTEM.VAL(LONGINT, MixRead(M4VT[Ch])) DIV 8; 
			right:= SYSTEM.VAL(LONGINT, MixRead(M4VT[Ch]+1)) DIV 8
		|MIC: left:= SYSTEM.VAL(LONGINT, MixRead(M4VT[Ch])) DIV 8; right:= 0
		|PCSPEAKER: left:= SYSTEM.VAL(LONGINT, MixRead(M4VT[Ch])) DIV 64; right:= 0
	ELSE res:= Failed; left:= 0; right:= 0
	END
END GetVolume4;

(** SetTrebble4 : sets left & right of trebble values *)
PROCEDURE SetTrebble4*(TrebbleL, TrebbleR: LONGINT);
BEGIN
	MixWrite(44H, MixRead(44H)*{3,2,1,0} + SYSTEM.VAL(SET, TrebbleL*16));
	MixWrite(45H, MixRead(45H)*{3,2,1,0} + SYSTEM.VAL(SET, TrebbleR*16))
END SetTrebble4;

(** GetTrebble4 : gets left & right trebble values *)
PROCEDURE GetTrebble4*(VAR TrebbleL, TrebbleR: LONGINT);
BEGIN
	TrebbleL:= SYSTEM.VAL(LONGINT, MixRead(44H)) DIV 16;
	TrebbleR:= SYSTEM.VAL(LONGINT, MixRead(45H)) DIV 16
END GetTrebble4;

(** SetBass4 : sets left & right bass values *)
PROCEDURE SetBass4*(BassL, BassR: LONGINT);
BEGIN
	MixWrite(46H, MixRead(46H)*{3,2,1,0} + SYSTEM.VAL(SET, BassL*16));
	MixWrite(47H, MixRead(47H)*{3,2,1,0} + SYSTEM.VAL(SET, BassR*16))
END SetBass4;

(** GetBass4 : gets left & right bass values *)
PROCEDURE GetBass4*(VAR BassL, BassR: LONGINT);
BEGIN
	BassL:=SYSTEM.VAL(LONGINT, MixRead(46H)) DIV 16;
	BassR:=SYSTEM.VAL(LONGINT, MixRead(47H)) DIV 16
END GetBass4;

(** SetInGain4 : sets left & right input gain values (preamplifier) *)
PROCEDURE SetInGain4*(GainL, GainR: LONGINT);
BEGIN
	MixWrite(3FH, MixRead(3FH) * {5,4,3,2,1,0} + SYSTEM.VAL(SET, GainL*64));
	MixWrite(40H, MixRead(40H) * {5,4,3,2,1,0} + SYSTEM.VAL(SET, GainR*64))
END SetInGain4;

(** GetInGain4 : gets left & right input gain values *)
PROCEDURE GetInGain4*(VAR GainL, GainR: LONGINT);
BEGIN
	GainL:= SYSTEM.VAL(LONGINT, MixRead(3FH)) DIV 64;
	GainR:= SYSTEM.VAL(LONGINT, MixRead(40H)) DIV 64
END GetInGain4;

(** SetOutGain4 : sets left & right output gain values *)
PROCEDURE SetOutGain4*(GainL, GainR: LONGINT);
BEGIN
	MixWrite(41H, MixRead(41H) * {5,4,3,2,1,0} + SYSTEM.VAL(SET, GainL*64));
	MixWrite(42H, MixRead(42H) * {5,4,3,2,1,0} + SYSTEM.VAL(SET, GainR*64))
END SetOutGain4;

(** GetOutGain4 : gets left & right output gain values *)
PROCEDURE GetOutGain4*(VAR GainL, GainR: LONGINT);
BEGIN
	GainL:= SYSTEM.VAL(LONGINT, MixRead(41H)) DIV 64;
	GainR:= SYSTEM.VAL(LONGINT, MixRead(42H)) DIV 64
END GetOutGain4;

(** DSP *)
(** DspWrite : write data to DSP-chip *)
PROCEDURE DspWrite*(Val: INTEGER);
	VAR dat: SET; cx: LONGINT;
BEGIN
	cx:= 65000; dat:= {};
	(* read Write-status and wait until ok or counter zero *)
	SYSTEM.PORTIN(wport, SYSTEM.VAL(CHAR, dat));
	WHILE (7 IN dat)&(cx # 0) DO
		DEC(cx);
		SYSTEM.PORTIN(wport, SYSTEM.VAL(CHAR, dat))
	END;
	IF cx > 0 THEN SYSTEM.PORTOUT(wport, SYSTEM.VAL(CHAR, Val))
	ELSE IF Val#GETVER THEN HALT(DSPIOError) END
	END
END DspWrite;

(** DspRead : reads data from DSP-chip *)
PROCEDURE DspRead*(VAR Val: INTEGER);
	VAR cx: LONGINT; dat: SET;
BEGIN
	cx:= 65000; dat:= {};
	(* read Read-status and wait until ok or counter zero *)
	SYSTEM.PORTIN(rsport, SYSTEM.VAL(CHAR, dat));
	WHILE ~(7 IN dat)&(cx # 0) DO
		DEC(cx);
		SYSTEM.PORTIN(rsport, SYSTEM.VAL(CHAR, dat))
	END;
	Val:= 0;
	IF cx > 0 THEN SYSTEM.PORTIN(rdport, SYSTEM.VAL(CHAR, Val))
	ELSE HALT(DSPIOError)
	END
END DspRead;

(** DspReset : resets DSP-chip *)
PROCEDURE DspReset*;
	VAR i, Val : INTEGER; t: LONGINT;
BEGIN
	(* write first a 1, wait, and then an 0 to the reset-port *)
	SYSTEM.PORTOUT(resetport, SYSTEM.VAL(CHAR, 1));
	t := Kernel.GetTimer()+2;  REPEAT UNTIL Kernel.GetTimer() >= t;	(* assume one tick is long enough *)
	(*t := Kernel.SetTimeout(3);  REPEAT UNTIL Kernel.Expired(t);*)
	SYSTEM.PORTOUT(resetport, SYSTEM.VAL(CHAR, 0));
	DspRead(Val);
	(* i:= 0; WHILE (Val#0AAH)&(i<100) DO INC(i); DspRead(Val) END; *)
	IF Val # 0AAH THEN res:= ResetErr
	ELSE res:= Done
	END
END DspReset;

(* GetVersion : gets DSP-chip versionsnumber *)
PROCEDURE GetVersion(VAR B: SBDef);
	VAR V1, V2 : INTEGER;
BEGIN
	DspWrite(GETVER); DspRead(V1); DspRead(V2);
	B.DspVersion:= V1*256 + V2;	(* build the version-word *)
	IF (V1>=1)&(V1<=4) THEN
		IF B.DspVersion=512 THEN COPY(Names[1], B.DspName)
		ELSE COPY(Names[V1], B.DspName)
		END
	ELSE
		COPY(Names[SBNONE], B.DspName)
	END
END GetVersion;

(** Init : initialize SBDef-structure of the module *)
PROCEDURE Init*(VAR B: SBDef; reset: BOOLEAN);
BEGIN
	res:= Done;
	IF B.DspPort # -1 THEN
		base:= B.DspPort;
		wport:= base + 0CH;	(* write command/data & wirte buffer-status port (bit 7) *)
		rsport:= base + 0EH;	(* read buffer-status port (bit 7) *)
		rdport:= base + 0AH;	(* read data port *)
		resetport:= base + 6H;	(* reset port *)
		IF reset THEN DspReset END;
		IF B.DspVersion = -1 THEN GetVersion(B) END;
		IF B.DspVersion >= DSP4XX THEN
			IF B.DspDmaW = -1 THEN B.DspDmaW:= B.DspDmaB END
		END;
		DSPBase:= B;
		IF B.DspVersion >= DSP201 THEN InitMixer(TRUE) END
	ELSE res:= Failed
	END
END Init;

(** AdjustFrq : adjusts frequency to the soundcard; if recording and frequency is not supported,
then FALSE is returned, but if playing, the frequency will be ajusted *)
PROCEDURE AdjustFrq*(VAR Frq: LONGINT; recording: BOOLEAN; VAR stereo: BOOLEAN): BOOLEAN;
BEGIN
	IF recording THEN
		(* recording *)
		IF DSPBase.DspVersion >= DSP4XX THEN
			IF (Frq < 5000) OR (Frq > 44100) THEN RETURN FALSE END;
			RETURN TRUE
		ELSIF DSPBase.DspVersion >= DSP3XX THEN
			IF stereo THEN
				IF (Frq < 11025) OR (Frq > 22050) THEN RETURN FALSE END
			ELSE
				IF (Frq < 4000) OR (Frq > 44100) THEN RETURN FALSE END
			END;
			RETURN TRUE
		ELSIF DSPBase.DspVersion >= DSP201 THEN
			IF (Frq < 4000) OR (Frq > 15000) THEN RETURN FALSE END;
			RETURN TRUE
		ELSIF DSPBase.DspVersion >= DSP1XX THEN
			IF (Frq < 4000) OR (Frq > 13000) THEN RETURN FALSE END;
			RETURN TRUE
		END
	ELSE
		(* playing *)
		IF DSPBase.DspVersion >= DSP4XX THEN
			IF Frq > 44100 THEN Frq:= 44100
			ELSIF Frq < 5000 THEN Frq:= 5000
			END
		ELSIF DSPBase.DspVersion >= DSP3XX THEN
			IF stereo THEN
				IF Frq > 22050 THEN Frq:= 22050
				ELSIF Frq < 11025 THEN Frq:= 11025
				END
			ELSE
				IF Frq > 44100 THEN Frq:= 44100
				ELSIF Frq < 4000 THEN Frq:= 4000
				END
			END
		ELSIF DSPBase.DspVersion >= DSP201 THEN
			IF Frq > 44100 THEN Frq:= 44100
			ELSIF Frq < 4000 THEN Frq:= 4000
			END
		ELSIF DSPBase.DspVersion >= DSP1XX THEN
			IF Frq > 23000 THEN Frq:= 23000
			ELSIF Frq < 4000 THEN Frq:= 4000
			END
		END;
		RETURN TRUE
	END;
	RETURN FALSE		(* DSP-Version < 1.00 not supported *)
END AdjustFrq;

(** DSP4DACFrq : sets output frequency in Hertz for DSP 4.XX *)
PROCEDURE DSP4DACFrq*(Frq: LONGINT);
BEGIN
	ASSERT((5000 <= Frq) & (Frq <= 44100));
	DspWrite(41H); DspWrite(SHORT(Frq DIV 100H));
	DspWrite(SHORT(Frq MOD 100H))
END DSP4DACFrq;

(** DSP4ADCFrq : sets input frequency in Hertz for DSP 4.XX *)
PROCEDURE DSP4ADCFrq*(Frq: LONGINT);
BEGIN
	ASSERT((5000 <= Frq) & (Frq <= 44100));
	DspWrite(42H); DspWrite(SHORT(Frq DIV 100H)); DspWrite(SHORT(Frq MOD 100H))
END DSP4ADCFrq;

(** SetFrq : sets in-/output-frequency of DSP-chip; only for chips < DSP 4.XX 
Input :
Frq - holds frequency in [Hz], after call this variable states the used frequency (isn't used)
Channel - 1: Mono, 2: Stereo *)
PROCEDURE SetFrq*(VAR Frq: LONGINT; Channel: INTEGER);
VAR TC: INTEGER;
BEGIN
	(* timeconstant *)
	TC:= 256 - SHORT(ENTIER((1000000 + (Channel*Frq)/2) / (Channel*Frq)));
	Frq:= (1000000 + (256 - TC)*Channel) DIV ((256 - TC)*Channel);
	DspWrite(40H); DspWrite(TC)
END SetFrq;

(** CanStereo: is Stereo-Mode possible with this soundcard? *)
PROCEDURE CanStereo*() : BOOLEAN;
BEGIN
  RETURN (DSPBase.DspVersion >= DSP3XX)
END CanStereo;

(** CanSigned: is playing of signed data possible ? *)
PROCEDURE CanSigned*():BOOLEAN;
BEGIN
	RETURN (DSPBase.DspVersion >= DSP4XX)
END CanSigned;

(** IsHMADCFrq : is this frequency a HighSpeed one for recording? DSP-chips 2.01+ & 3.XX needs this *)
PROCEDURE IsHMADCFrq*(Frq: LONGINT): BOOLEAN;
BEGIN
	IF DSPBase.DspVersion <= DSP200 THEN RETURN FALSE
	ELSE
		IF DSPBase.DspVersion >= DSP4XX THEN RETURN FALSE
		ELSIF DSPBase.DspVersion >= DSP3XX THEN RETURN ((23001 <= Frq)&(Frq <= 44100))
		ELSIF DSPBase.DspVersion = DSP201 THEN RETURN ((13001 <= Frq)&(Frq <= 15000))
		ELSE RETURN FALSE
		END
	END
END IsHMADCFrq;

(** IsHMDACFrq : is this frequency a HighSpeed one for playing? DSP-chips 2.01+ & 3.XX needs this *)
PROCEDURE IsHMDACFrq*(Frq: LONGINT): BOOLEAN;
BEGIN
	IF DSPBase.DspVersion <= DSP200 THEN RETURN FALSE
	ELSE
		IF DSPBase.DspVersion >= DSP4XX THEN RETURN FALSE
		ELSIF DSPBase.DspVersion >= DSP201 THEN RETURN ((23001 <= Frq)&(Frq <= 44100))
		ELSE RETURN FALSE
		END	
	END
END IsHMDACFrq;

(** MaxBits : get the max samplingsize in bits for the specific DSP-chip *)
PROCEDURE MaxBits*(): INTEGER;
BEGIN
	IF DSPBase.DspVersion >= DSP4XX THEN RETURN 16
	ELSE RETURN 8
	END
END MaxBits;

(** SetSpeaker : DSP input/output on/off *)
PROCEDURE SetSpeaker*(State: BOOLEAN);
BEGIN
	IF State THEN DspWrite(0D1H) ELSE DspWrite(0D3H) END
END SetSpeaker;

(** SetTransferSize : set transfersize from/to DSP-chip *)
PROCEDURE SetTransferSize*(size: LONGINT);
BEGIN
	IF size # 0 THEN
		DEC(size);	(* DSP-chip needs transfersize -1 *)
		DspWrite(48H);
		DspWrite(SHORT(size MOD 100H));	(* first Lo-byte *)
		DspWrite(SHORT(size DIV 100H));	(* second Hi-byte *)
		res:= Done
	ELSE res:= Failed
	END
END SetTransferSize;

BEGIN
	Names[0]:="Unknown soundcard"; Names[1]:="SB1.5 or SB MVC";
	Names[2]:="SB 2.0"; Names[3]:="SB Pro or SB Pro MVC";
	Names[4]:="SB 16 or SB 16 ASP"; Names[5]:="> SB 16";
	M2VT[0]:=02H; M2VT[1]:=06H; M2VT[2]:=08H; M2VT[3]:=0AH;
	M3VT[0]:=22H; M3VT[1]:=26H; M3VT[2]:=28H; M3VT[3]:=04H; M3VT[4]:=2EH; M3VT[5]:=0AH;
	M4VT[0]:=30H; M4VT[1]:=34H; M4VT[2]:=36H; M4VT[3]:=32H; M4VT[4]:=38H; M4VT[5]:=3AH;
	M4VT[6]:=3BH
END DSP.
