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

MODULE Sound;	(** non-portable *)	(** tb, SS96 *)
IMPORT Kernel, DMA, DSP, CD, SYSTEM, Texts, Oberon, Out;

(**
Sound-Module : Interface for Sound-Devices (Mixer, Audio, CD-ROM)
Author: Thomas Burri ; CD-Interface by Emil Zeller (ejz)
Last Update: 
*)
(*
08.07.96 pjm - new Kernel.RemoveIP, DBdataSize
*)

	CONST
		Trace = FALSE;
		DBdataSize* = 32768;	(* should be half of DMA.BufSize *)

		(** result codes *)
		Done* = 0;	(** call succeded *)
		Failed* = 1;	(** call failed *)
		NotOpened* = 2;	(** device isn't opened *)
		NotRunning* = 3;	(** device is Not Running (playing or recording *)
		NSStereo* = 6;	(** stereo mode is Not Supported with this soundcard *)
		NS16bit* = 7;	(** 16 bit is Not Supported with this soundcard *)
		NSFreq* = 8;	(** frequency is Not Supported with this soundcard *)
		NSSignedData* = 9;	(** signed data is Not Supported with this soundcard *)
		
		(** format *)
		PCM* = 0;
		ADPCM8b2b* = 1;
		ADPCM8b3b* = 2;
		ADPCM8b4b* = 3;

		(** devState bits of Audio and CD *)
		opened* = 0;
		playing* = 1;
		recording* = 2;
		paused* = 3;
		stopped* = 4;
		mediapresent* = 5;	(** only in use with CD *)

		sig = 0H;
		unsig8bit = 7F7F7F7FH;
		unsig16bit = 7FFF7FFFH;

	TYPE
		Trigger* = PROCEDURE (end: BOOLEAN);
		(** end = FALSE : add new block / end = TRUE : play or recording finished *)
		AudioDef* = RECORD	(** defines how to play or record the audio file *)
			format*: INTEGER;	(** PCM, ADPCMxbxb *)
			stereo*, signed* : BOOLEAN;
			bits* : INTEGER;	(** 8 / 16 bits *)
			freq* : LONGINT;
			blocks*: LONGINT;	(** number of transferblocks needed for the audio file to play *)
			handle*: Trigger
		END;
		
		Channel* = RECORD	(** Mixer-Channel capabilities & desciption*)
			name*: ARRAY 32 OF CHAR;
			Ch*, nofSubCh*: LONGINT;
		END;
		SubChannel* = RECORD	(** Mixer-SubChannel capabilities & desciption *)
			name*: ARRAY 32 OF CHAR;
			Ch*, SubCh*, maxval*: LONGINT;	(** maxval = 0: use a checkbox, else a slider *)
			(** minval explicit 0 *)
		END;
		
		DataBlock* = POINTER TO DataBlockDesc;
		DataBlockDesc* = RECORD
			data*: ARRAY DBdataSize OF SYSTEM.BYTE;
			len*: LONGINT;
			next: DataBlock
		END;
		
	VAR
		res*, cdDevID, Divisor: INTEGER;
		base: DSP.SBDef;
		bufcnt, nofbuf, halfbufsize, time, oldOT, lastIrq, stoptime, fillpat: LONGINT;
		cmd, Mode, audioState, cdState: SET;
		curAF: AudioDef;
		lastDB, actDB, curDB, endDB: DataBlock;
		irq, single, irqinstalled, highspeed: BOOLEAN;
		W: Texts.Writer;

(* Soundcard *)
(* Init: Reads in the Port-Address, the DMA-Channel(s), the IRQ-Nummber and a compatibleflag
	out of Oberon.Text and initiates the soundcard. *)
PROCEDURE Init;
	VAR S: Texts.Scanner; error: BOOLEAN;
BEGIN
	base.DspPort:= -1; base.DspVersion:= -1; base.DspDmaB:= -1; base.DspDmaW:= -1;
	base.DspIrq:= -1; error:= FALSE;
	Oberon.OpenScanner(S, "Sound.Audio.Port");
	IF S.class = Texts.Int THEN base.DspPort:= SHORT(S.i) ELSE error:= TRUE END;
	Oberon.OpenScanner(S, "Sound.Audio.IRQ");
	IF S.class = Texts.Int THEN base.DspIrq:= SHORT(S.i) ELSE error:= TRUE END;
	Oberon.OpenScanner(S, "Sound.Audio.LowDMA");
	IF S.class = Texts.Int THEN base.DspDmaB:= SHORT(S.i) ELSE error:= TRUE END;
	Oberon.OpenScanner(S, "Sound.Audio.HighDMA");
	IF S.class = Texts.Int THEN base.DspDmaW:= SHORT(S.i) ELSE error:= TRUE END;
	Oberon.OpenScanner(S, "Sound.Audio.compatible");
	IF S.class = Texts.Int THEN base.DspVersion:= SHORT(S.i) ELSE error:= TRUE END;
	IF error THEN
		Texts.WriteString(W, "Sound.Audio not configured in Oberon.Text");
		Texts.WriteLn(W)
	ELSE
		IF base.DspVersion # -1 THEN
			CASE base.DspVersion OF
				0: base.DspVersion:= DSP.DSP1XX; base.DspName:= "SB1.5 compatible"
				|1: base.DspVersion:= DSP.DSP201; base.DspName:= "SB2.0 compatible"
				|2: base.DspVersion:= DSP.DSP3XX; base.DspName:= "SBpro compatible"
				|3: base.DspVersion:= DSP.DSP4XX; base.DspName:= "SB16 compatible"
			ELSE
				Texts.WriteString(W, "Wrong 'compatible number' in Oberon.Text");
				Texts.WriteLn(W);
				error:= TRUE
			END
		END;
		IF ~error THEN
			DMA.Init;
			DSP.Init(base, TRUE);
			IF DSP.res = DSP.Failed THEN Texts.WriteString(W, "Sound setting failed")
			ELSE
				Texts.WriteString(W, "Sound setting ok : "); Texts.WriteString(W, base.DspName);
				Texts.WriteLn(W); Texts.WriteString(W, "DspVersion: ");
				Texts.WriteInt(W, base.DspVersion DIV 256, 0); Texts.Write(W , ".");
				Texts.WriteInt(W, base.DspVersion MOD 256, 0)
			END
		END
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Init;

(** Mixer *)
(** GetNofChannels : returns number of usable Mixer-Channels with your Mixer-chip *)
PROCEDURE GetNofChannels*(): LONGINT;
BEGIN
	IF base.DspVersion >= DSP.DSP4XX THEN
		RETURN 15
	ELSIF base.DspVersion >= DSP.DSP3XX THEN
		RETURN 10
	ELSIF base.DspVersion >= DSP.DSP201 THEN
		RETURN 4
	ELSE
		res:= Failed;
		RETURN 0
	END
END GetNofChannels;

(** GetChCapas : returns capabilities & description of a Mixer-Channel *)
PROCEDURE GetChCapas*(VAR c: Channel);
BEGIN
	res:= Done;
	CASE c.Ch OF
		0: COPY("Master", c.name);
		|1: COPY("MIDI", c.name);
		|2: COPY("CD", c.name);
		|3: COPY("Voice", c.name)
		ELSE (* skip *)
	END;
	IF base.DspVersion >= DSP.DSP4XX THEN
		CASE c.Ch OF
			0,1,2,3: c.nofSubCh:= 2
			|4: COPY("Line", c.name); c.nofSubCh:= 2
			|5: COPY("Mic", c.name); c.nofSubCh:= 1
			|6: COPY("PCSpeaker", c.name); c.nofSubCh:= 1
			|7: COPY("Trebble", c.name); c.nofSubCh:= 2
			|8: COPY("Bass", c.name); c.nofSubCh:= 2
			|9: COPY("InAmp", c.name); c.nofSubCh:= 2
			|10: COPY("OutAmp", c.name); c.nofSubCh:= 2
			|11: COPY("OutSource", c.name); c.nofSubCh:= 5
			|12: COPY("InSourceLeft", c.name); c.nofSubCh:= 7
			|13: COPY("InSourceRight", c.name); c.nofSubCh:= 7
			|14: COPY("AGC", c.name); c.nofSubCh:= 1
		ELSE
			res:= Failed
		END
	ELSIF base.DspVersion >= DSP.DSP3XX THEN
		CASE c.Ch OF
			0,1,2,3: c.nofSubCh:= 2
			|4: COPY("Line", c.name); c.nofSubCh:= 2
			|5: COPY("Mic", c.name); c.nofSubCh:= 1
			|6: COPY("InFilter", c.name); c.nofSubCh:= 1
			|7: COPY("OutFilter", c.name); c.nofSubCh:= 1
			|8: COPY("FilterFrq", c.name); c.nofSubCh:= 1
			|9: COPY("Source", c.name); c.nofSubCh:= 4
		ELSE
			res:= Failed
		END
	ELSIF base.DspVersion >= DSP.DSP201 THEN
		IF (0 <= c.Ch)&(c.Ch <= 4) THEN c.nofSubCh:= 1
		ELSE res:= Failed
		END
	ELSE res:= Failed
	END
END GetChCapas;

(** GetSubChCapas : returns  capabilities & descprition of a Mixer-SubChannel *)
PROCEDURE GetSubChCapas*(VAR sc: SubChannel);
BEGIN
	res:= Done;
	sc.maxval:= 0;
	IF base.DspVersion >= DSP.DSP4XX THEN
		CASE sc.Ch OF 0,1,2,3,4,7,8,9,10:
			IF sc.SubCh = 0 THEN COPY("Left", sc.name)
			ELSE COPY("Right", sc.name) END
		ELSE (* skip *)
		END;
		CASE sc.Ch OF
			0,1,2,3,4: sc.maxval:= 31
			|5: COPY("Mono",sc.name); sc.maxval:= 31
			|6: COPY("Mono",sc.name); sc.maxval:= 3
			|7,8: sc.maxval:= 15
			|9,10: sc.maxval:= 3
			|11,12,13:
				CASE sc.SubCh OF
					0: COPY("Mic", sc.name)
					|1: COPY("CDRight", sc.name)
					|2: COPY("CDLeft", sc.name)
					|3: COPY("LineRight", sc.name)
					|4: COPY("LineLeft", sc.name)
					|5: COPY("MIDIRight", sc.name)
					|6: COPY("MIDILeft", sc.name)
				ELSE res:= Failed
				END
			|14: CASE sc.SubCh OF
				0: COPY("off/on", sc.name)
				ELSE res:= Failed
				END
		ELSE res:= Failed
		END
	ELSIF base.DspVersion >= DSP.DSP3XX THEN
		IF (0 <= sc.Ch)&(sc.Ch <= 4) THEN
			IF sc.SubCh = 0 THEN COPY("Left", sc.name); sc.maxval:= 7
			ELSIF sc.SubCh = 1 THEN COPY("Right", sc.name); sc.maxval:= 7
			ELSE res:= Failed
			END;
		ELSIF (sc.Ch = 5)&(sc.SubCh = 0) THEN COPY("Mono", sc.name); sc.maxval:= 3
		ELSE
			CASE sc.Ch OF
				6, 7: IF sc.SubCh = 0 THEN COPY("off/on", sc.name)
					ELSE res:= Failed
					END
				|8: IF sc.SubCh = 0 THEN COPY("low/high", sc.name)
					ELSE res:= Failed
					END
				|9:
					CASE sc.SubCh OF
						0, 2: COPY("Mic", sc.name)
						|1: COPY("CD", sc.name)
						|3: COPY("Line", sc.name)
					ELSE res:= Failed
					END
			ELSE res:= Failed
			END
		END
	ELSIF base.DspVersion >= DSP.DSP201 THEN
		IF (0 <= sc.Ch)&(sc.Ch <= 3) THEN
			IF sc.SubCh = 0 THEN COPY("Mono", sc.name); sc.maxval:= 7
			ELSE res:= Failed
			END
		ELSE res:= Failed
		END
	ELSE
		res:= Failed
	END
END GetSubChCapas;

(** GetValue : gets value of this SubChannel *)
PROCEDURE GetValue*(c, sc: LONGINT; VAR val: LONGINT);
	VAR left, right: LONGINT;
BEGIN
	res:= Done; left:= 0; right:= 0; val:= 0;
	IF base.DspVersion >= DSP.DSP4XX THEN
		IF (0<=c)&(c<=6) THEN DSP.GetVolume4(c, left, right)
		ELSIF c = 7 THEN DSP.GetTrebble4(left, right)
		ELSIF c = 8 THEN DSP.GetBass4(left, right)
		ELSIF c = 9 THEN DSP.GetInGain4(left, right)
		ELSIF c = 10 THEN DSP.GetOutGain4(left, right)
		ELSE
			CASE c OF
				11: CASE sc OF
						0,1,2,3,4: DSP.GetOutSource4(sc, val)
						ELSE res:= Failed END
				|12: CASE sc OF
						0,1,2,3,4,5,6: DSP.GetInSourceL4(sc, val)
						ELSE res:= Failed END
				|13: CASE sc OF
						0,1,2,3,4,5,6: DSP.GetInSourceR4(sc, val)
						ELSE res:= Failed END
				|14: IF sc = 0 THEN DSP.GetAGC4(val)
						ELSE res:= Failed
						END
			ELSE res:= Failed
			END
		END;
		IF  (0<=c)&(c<=10) THEN
			IF sc = 0 THEN val:= left ELSE val:= right END
		END
	ELSIF base.DspVersion >= DSP.DSP3XX THEN
		IF (0<=c)&(c<=5) THEN DSP.GetVolume3(c, left, right);
		ELSE
			CASE c OF
				6: val:= 0;
					IF sc=0 THEN
						IF DSP.GetADCFilter3() THEN val:= 1 END
					ELSE res:= Failed END
				|7: val:= 0;
					IF sc=0 THEN
						IF DSP.GetDACFilter3() THEN val:= 1 END
					ELSE res:= Failed END
				|8: val:= 0;
					IF sc=0 THEN
						IF DSP.GetLowPass3() THEN val:= 1 END
					ELSE res:= Failed END
				|9: DSP.GetSource3(val); IF val = sc THEN val:=1 ELSE val:= 0 END
			ELSE res:= Failed
			END
		END;
		IF (0<=c)&(c<=5) THEN
			IF sc = 0 THEN val:= left ELSE val:= right END
		END
	ELSIF base.DspVersion >= DSP.DSP201 THEN
		IF (0<=c)&(c<=3) THEN DSP.GetVolume2(c, val)
		ELSE res:= Failed
		END
	ELSE res:= Failed; val:= 0
	END
END GetValue;

(** SetValue : sets SubChannel to val *)
PROCEDURE SetValue*(c, sc, val: LONGINT);
	VAR left, right: LONGINT;
BEGIN
	res:= Done; left:= 0; right:= 0;
	IF base.DspVersion >= DSP.DSP4XX THEN
		IF (0<=c)&(c<=6) THEN
			DSP.GetVolume4(c, left, right);
			IF sc = 0 THEN DSP.SetVolume4(c, val, right) ELSE DSP.SetVolume4(c, left, val) END
		ELSIF c = 7 THEN
			DSP.GetTrebble4(left, right);
			IF sc = 0 THEN DSP.SetTrebble4(val, right) ELSE DSP.SetTrebble4(left, val) END
		ELSIF c = 8 THEN
			DSP.GetBass4(left, right);
			IF sc = 0 THEN DSP.SetBass4(val, right) ELSE DSP.SetBass4(left, val) END
		ELSIF c = 9 THEN
			DSP.GetInGain4(left, right);
			IF sc = 0 THEN DSP.SetInGain4(val, right) ELSE DSP.SetInGain4(left, val) END
		ELSIF c = 10 THEN
			DSP.GetOutGain4(left, right);
			IF sc = 0 THEN DSP.SetOutGain4(val, right) ELSE DSP.SetOutGain4(left, val) END
		ELSE
			CASE c OF
				11: CASE sc OF 0,1,2,3,4: DSP.SetOutSource4(sc, val) ELSE res:= Failed END
				|12: CASE sc OF 0,1,2,3,4,5,6: DSP.SetInSourceL4(sc, val) ELSE res:= Failed END
				|13: CASE sc OF 0,1,2,3,4,5,6: DSP.SetInSourceR4(sc, val) ELSE res:= Failed END
				|14: IF sc = 0 THEN DSP.SetAGC4(val)
						ELSE res:= Failed
						END
			ELSE res:= Failed
			END
		END
	ELSIF base.DspVersion >= DSP.DSP3XX THEN
		IF (0<=c)&(c<=5) THEN
			DSP.GetVolume3(c, left, right);
			IF sc = 0 THEN DSP.SetVolume3(c, val, right) ELSE DSP.SetVolume3(c, left, val) END
		ELSE
			CASE c OF
				6: IF sc=0 THEN
						IF val=1 THEN DSP.SetADCFilter3(DSP.ON)
						ELSE DSP.SetADCFilter3(DSP.OFF) END
					ELSE res:= Failed
					END
				|7: IF sc=0 THEN
						IF val=1 THEN DSP.SetDACFilter3(DSP.ON)
						ELSE DSP.SetDACFilter3(DSP.OFF) END
					ELSE res:= Failed
					END
				|8: IF sc=0 THEN
						IF val=1 THEN DSP.SetLowPass3(DSP.ON)
						ELSE DSP.SetLowPass3(DSP.OFF) END
					ELSE res:= Failed
					END
				|9: IF (0 <= sc)&(sc <= 3) THEN DSP.SetSource3(sc)
					ELSE res:= Failed
					END
			ELSE res:= Failed
			END
		END
	ELSE res:= Failed
	END
END SetValue;

(** Audio*)
(* ClearTransBuf : clears buffer *)
PROCEDURE ClearBuffer(BufAdr, Size, fillpat: LONGINT);
	VAR i: LONGINT;
BEGIN
	i:= 0; WHILE i < Size DO SYSTEM.PUT(BufAdr+i, fillpat); INC(i,4) END;
END ClearBuffer;

PROCEDURE ^ PauseAudio*;

(* RestoreIrqHandler: removes the interrupthandler *)
PROCEDURE RestoreIrqHandler;
BEGIN
	IF irqinstalled THEN
		Kernel.RemoveIP(NIL, Kernel.IRQ+base.DspIrq);
		irqinstalled:= FALSE
	END
END RestoreIrqHandler;

(* RecSpecEnd: copies the data in the DMA-transferbufferafter stopping the recording into a block *)
PROCEDURE RecSpecEnd;
	VAR faq: INTEGER;
BEGIN
	faq:= 1;
	IF curAF.stereo THEN faq:= 2 END;
	IF curAF.bits = 16 THEN faq:= faq*2 END;
	curDB.len:= ENTIER(1.15*curAF.freq*stoptime*faq) DIV Kernel.TimeUnit;
	IF (curDB.len < 0) OR (curDB.len > halfbufsize) THEN curDB.len:= halfbufsize END;
	IF bufcnt MOD 2 = 0 THEN
		SYSTEM.MOVE(DMA.TransBufAdr, SYSTEM.ADR(curDB.data), curDB.len)
	ELSE
		SYSTEM.MOVE(DMA.TransBufAdr+halfbufsize, SYSTEM.ADR(curDB.data), curDB.len)
	END;
	INC(bufcnt); DEC(nofbuf);
	lastDB:= curDB; curDB:= curDB.next;
END RecSpecEnd;

(* EndOfRecPlay: is called for stopping the playing or the recording in Highspeed-Mode or when
StopAudio was called *)
PROCEDURE EndOfRecPlay;
	VAR tmp: LONGINT;
BEGIN
	tmp:= Oberon.Time();
	stoptime:= tmp - lastIrq;
	INC(time, stoptime);
	oldOT:= tmp;
	IF highspeed THEN
		RestoreIrqHandler;
		(* HiSpeed-commands can only be interrupted by reset *)
		DSP.DspReset;
		IF DSP.res = DSP.Failed THEN HALT(99) END;
		IF (recording IN audioState)&(curDB # NIL) THEN RecSpecEnd END;
		IF curAF.stereo THEN DSP.RestoreFromStereo3; DSP.DspWrite(DSP.DSP3MADC) END;
		audioState:= {opened, stopped};
		curAF.handle(TRUE)
	ELSE
		IF (base.DspVersion >= DSP.DSP4XX) & (recording IN audioState) & ~curAF.stereo THEN
			DSP.RestoreFromMonoADC4
		END;
		IF (cmd*{7,6,5,4}) = DSP.DSP4CMD16DMA THEN
			DSP.DspWrite(DSP.DSP4EXIT16DMA);
			DSP.DspWrite(DSP.DSP4PAUSE16)
		ELSE
			DSP.DspWrite(DSP.DSPEXITAUTOINIT);
			DSP.DspWrite(DSP.DMAPAUSE)
		END;
	END
END EndOfRecPlay;

(* IrqPlayHandler: interrupthandler for playing *)
PROCEDURE IrqPlayHandler;
	VAR who: SET; ch: CHAR; port, tmp: LONGINT;
BEGIN
	(* SYSTEM.CLI(); *)
	irq:= TRUE;
	IF base.DspVersion >= DSP.DSP4XX THEN	(* DSP-version >= 4.00 *)
		who:= DSP.MixRead(DSP.M4IRQSOURCE);
		(* -- 8-Bit DMA ----------------------------------------------- *)
		IF who*DSP.M4IRQ8DMA # {} THEN
			port:= base.DspPort+0EH;
			SYSTEM.PORTIN(port, ch)
		(* -- 16-Bit DMA ---------------------------------------------- *)
		ELSIF who*DSP.M4IRQ16DMA # {} THEN
			port:= base.DspPort+0FH;
			SYSTEM.PORTIN(port, ch)
		END
	ELSE	(* DSP-version <= 3.XX *)
		port:= base.DspPort+0EH;
		SYSTEM.PORTIN(port, ch);
	END;
	tmp:= Oberon.Time();
	INC(time, tmp-oldOT);
	oldOT:= tmp;
	lastIrq:= tmp;
	IF base.DspVersion < DSP.DSP200 THEN
		IF bufcnt <= curAF.blocks THEN
			actDB:= actDB.next;
			IF bufcnt MOD 2 = 1 THEN
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, actDB.len, DMA.MSINGLE+DMA.MREAD);
			ELSE
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr+halfbufsize, actDB.len, DMA.MSINGLE+DMA.MREAD);
			END;
			DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd));
			DSP.DspWrite(SHORT(actDB.len -1) MOD 100H);
			DSP.DspWrite(SHORT(actDB.len -1) DIV 100H);
			IF bufcnt = curAF.blocks THEN INC(bufcnt) END
		END
	END;
	IF nofbuf > 0 THEN
		IF bufcnt MOD 2 = 0 THEN
			ClearBuffer(DMA.TransBufAdr, halfbufsize, fillpat);
			SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr, curDB.len)
		ELSE
			ClearBuffer(DMA.TransBufAdr+halfbufsize, halfbufsize, fillpat);
			SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr+halfbufsize, curDB.len)
		END;
		lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf)
	END;
	IF curAF.blocks - bufcnt > nofbuf THEN	(* not enough buffers in queue *)
		curAF.handle(FALSE);
		IF nofbuf < 1 THEN	(* there should be at least 1 buffers in the queue else pause *)
			PauseAudio()
		END
	ELSIF curAF.blocks+2 = bufcnt THEN	(* finished, release IrqHandler *)
		IF highspeed THEN EndOfRecPlay
		ELSE
			RestoreIrqHandler;
			IF base.DspVersion <= DSP.DSP3XX THEN DSP.SetSpeaker(DSP.OFF) END;
			audioState:= {opened, stopped};
			curAF.handle(TRUE)
		END;
		res:= Done
	ELSIF (curAF.blocks = bufcnt)&(base.DspVersion >= DSP.DSP200) THEN	(* moved last block to buffer *)
		IF (base.DspVersion >= DSP.DSP4XX)&(curAF.format = PCM) THEN
			DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd - {2}));
			DSP.DspWrite(SYSTEM.VAL(INTEGER, Mode));
			DSP.DspWrite(SHORT(endDB.len DIV Divisor -1) MOD 100H);
			DSP.DspWrite(SHORT(endDB.len DIV Divisor -1) DIV 100H)
		ELSIF ~highspeed THEN
			DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd));
			DSP.DspWrite(SHORT(endDB.len -1) MOD 100H);
			DSP.DspWrite(SHORT(endDB.len -1) DIV 100H);
		END;
		INC(bufcnt)
	ELSIF curAF.blocks+1 = bufcnt THEN	(* playing now the last block *)
		INC(bufcnt)
	END;
	(* SYSTEM.STI() *)
END IrqPlayHandler;

(* IrqRecHandler: interruphandler for recording *)
PROCEDURE IrqRecHandler;
	VAR who: SET; ch: CHAR; port: INTEGER; tmp: LONGINT;
BEGIN
	(* SYSTEM.CLI(); *)
	irq:= TRUE;
	IF base.DspVersion >= DSP.DSP4XX THEN	(* DSP-version >= 4.00 *)
		who:= DSP.MixRead(DSP.M4IRQSOURCE);
		(* -- 8-Bit DMA ----------------------------------------------- *)
		IF who*DSP.M4IRQ8DMA # {} THEN
			port:= base.DspPort+0EH;
			SYSTEM.PORTIN(port, ch)
		(* -- 16-Bit DMA ---------------------------------------------- *)
		ELSIF who*DSP.M4IRQ16DMA # {} THEN
			port:= base.DspPort+0FH;
			SYSTEM.PORTIN(port, ch)
		END
	ELSE	(* DSP-Version <= 3.XX *)
		port:= base.DspPort+0EH;
		SYSTEM.PORTIN(port, ch);
	END;
	tmp:= Oberon.Time();
	INC(time, tmp-oldOT);
	oldOT:= tmp;
	lastIrq:= tmp;
	IF base.DspVersion < DSP.DSP200 THEN
		DSP.DspWrite(DSP.DMAADC8);
		DSP.DspWrite(SHORT(halfbufsize -1) MOD 100H);
		DSP.DspWrite(SHORT(halfbufsize -1) DIV 100H)
	END;
	IF nofbuf > 0 THEN
		IF bufcnt MOD 2 = 0 THEN
			SYSTEM.MOVE(DMA.TransBufAdr, SYSTEM.ADR(curDB.data), halfbufsize);
			ClearBuffer(DMA.TransBufAdr, halfbufsize, fillpat)
		ELSE
			SYSTEM.MOVE(DMA.TransBufAdr+halfbufsize, SYSTEM.ADR(curDB.data), halfbufsize);
			ClearBuffer(DMA.TransBufAdr+halfbufsize, halfbufsize, fillpat)
		END;
		curDB.len:= halfbufsize;
		lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf)
	END;
	IF nofbuf < 4 THEN
		curAF.handle(FALSE);
		IF nofbuf < 1 THEN
			PauseAudio()
		END
	END;
	(* SYSTEM.STI() *)
END IrqRecHandler;

(* IrqStHandler: interruphandler for stereomode-switching with SB Pro *)
PROCEDURE IrqStHandler;
	VAR ch: CHAR; port: INTEGER;
BEGIN
	irq:= TRUE;
	port:= base.DspPort+0EH;
	SYSTEM.PORTIN(port, ch)
END IrqStHandler;

(* InitIrqHandler: installs the appropriate interrupthandler *)
PROCEDURE InitIrqHandler(play: BOOLEAN);
BEGIN
	IF ~irqinstalled THEN
		irqinstalled:= TRUE;
		IF play THEN
			Kernel.InstallIP(IrqPlayHandler, Kernel.IRQ+base.DspIrq)
		ELSE
			Kernel.InstallIP(IrqRecHandler, Kernel.IRQ+base.DspIrq)
		END
	END
END InitIrqHandler;

PROCEDURE StopAudio*();
BEGIN
	res:= Done;
	IF opened IN audioState THEN
		IF ~(stopped IN audioState) OR (paused IN audioState) THEN
			irq:= FALSE;
			EndOfRecPlay;
			IF ~highspeed THEN 
				RestoreIrqHandler;
				IF (recording IN audioState)&(curDB # NIL) THEN RecSpecEnd END;
				audioState:= {opened, stopped};
				curAF.handle(TRUE);
				(* IF base.DspVersion < DSP.DSP4XX THEN DSP.DspReset END; *)
				DSP.DspReset
			END
		ELSE
			res:= NotRunning
		END
	ELSE res:= NotOpened
	END;
END StopAudio;

PROCEDURE CloseAudio*();
BEGIN
	res:= Done;
	IF opened IN audioState THEN
		IF ~(stopped IN audioState) THEN StopAudio() END;
		audioState:= {};
		nofbuf:= 0;
		curDB:= NIL; endDB:= NIL; lastDB:= NIL; actDB:= NIL
	END
END CloseAudio;

PROCEDURE OpenAudio*(VAR d: AudioDef);
BEGIN
	res:= Done;
	IF opened IN audioState THEN res:= Failed
	ELSE
		time:= 0;
		curAF:= d;
		IF curAF.stereo & ~DSP.CanStereo() THEN res:= NSStereo
		ELSIF (curAF.bits = 16)&(DSP.MaxBits() # 16) THEN res:= NS16bit
		ELSIF curAF.signed & ~DSP.CanSigned() THEN res:= NSSignedData
		ELSE
			IF curAF.signed  THEN fillpat:= sig
			ELSIF curAF.bits = 8 THEN fillpat:= unsig8bit
			ELSE fillpat:= unsig16bit
			END;
			audioState:= {opened, stopped};
			bufcnt:= 0; nofbuf:= 0; curDB:= NIL; endDB:= NIL; lastDB:= NIL; actDB:= NIL
		END
	END
END OpenAudio;

PROCEDURE PlayPCM;
	VAR m: SET; BackUp: CHAR; dopause: BOOLEAN; len, i: LONGINT;
BEGIN
	IF Trace THEN Out.String("Sound do PlayPCM"); Out.Ln END;
	Mode:= {}; dopause:= FALSE; Divisor:= 1; single:= FALSE; len:= 0; highspeed:= FALSE;
	IF DSP.AdjustFrq(curAF.freq, FALSE, curAF.stereo) THEN
		IF Trace THEN Out.String("Sound Frq adjusted"); Out.Ln END;
		ClearBuffer(DMA.TransBufAdr, DMA.BufSize, fillpat);
		IF nofbuf # 0 THEN
			ASSERT(curDB # NIL);
			SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr, curDB.len);
			lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf);
			IF Trace THEN Out.String("Sound 1st move"); Out.Ln END;
			IF nofbuf # 0 THEN
				ASSERT(curDB # NIL);
				IF Trace THEN Out.String("Sound 2nd move"); Out.Ln END;
				SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr+halfbufsize, curDB.len);
				lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf);
				IF base.DspVersion < DSP.DSP200 THEN
					IF Trace THEN Out.String("Sound single cycle play"); Out.Ln END;
					single:= TRUE
				END
			ELSIF curAF.blocks = bufcnt THEN
				IF Trace THEN Out.String("Sound single cycle play"); Out.Ln END;
				single:= TRUE
			ELSE
				IF Trace THEN Out.String("Sound only few blocks in queue"); Out.Ln END;
				curAF.handle(FALSE)
			END
		ELSE
			IF Trace THEN Out.String("Sound no blocks in queue"); Out.Ln END;
			curAF.handle(FALSE);
			dopause:= TRUE
		END;
		(*- DSP3xx and smaller ------------ *)
		IF base.DspVersion < DSP.DSP4XX THEN
			IF Trace THEN Out.String("Sound Init DSP3 or smaller"); Out.Ln END;
			(* do put DSP3 recordingmode always to MONO, if you wanna play *)
			IF base.DspVersion >= DSP.DSP3XX THEN DSP.DspWrite(DSP.DSP3MADC) END;
			DSP.SetSpeaker(DSP.ON);	(* DSP-speaker on *)
			IF curAF.stereo THEN	(* Stereo-playing *)
				IF Trace THEN Out.String("Sound DSP3 Stereo"); Out.Ln END;
				DSP.PrepareForStereo3(TRUE);
				Kernel.InstallIP(IrqStHandler, Kernel.IRQ+base.DspIrq);
				(* if Stereo-playing, first send  80H over DMA to the DSP *)
				(* put 80H at first byte position in DMA transferbuffer *)
				SYSTEM.GET(DMA.TransBufAdr, BackUp);	(* backup value at this position *)
				SYSTEM.PUT(DMA.TransBufAdr, 80X);
				(* set DMA-channel for output of one byte *)
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, 1, DMA.MSINGLE+DMA.MREAD);
				irq:= FALSE;
				DSP.DspWrite(DSP.DMADAC8);	(* send one byte the to DSP *)
				DSP.DspWrite(0);
				DSP.DspWrite(0);
				(* wait to the end of the DMA-transfer; signaled over interrupt *)
				i:= Kernel.GetTimer();
				REPEAT UNTIL irq OR (Kernel.GetTimer()-i > 2*Kernel.TimeUnit);
				IF ~irq THEN
					Out.String("Error in Sound with setting to stereo mode"); Out.Ln; HALT(99)
				END;
				Kernel.RemoveIP(NIL, Kernel.IRQ+base.DspIrq);
				SYSTEM.PUT(DMA.TransBufAdr, BackUp);	(* restore DMA-Buffer *)
				DSP.SetFrq(curAF.freq, 2);	(* set Sample-frequency *)
				highspeed:= TRUE	(* Stereo-playing always in HiSpeed-mode *)
			ELSE		(* Mono-playing *)
				IF DSP.IsHMDACFrq(curAF.freq) THEN highspeed:= TRUE;
					IF Trace THEN Out.String("Sound DSP2XX HiSpeed used"); Out.Ln END
				ELSE cmd:= DSP.DMAAUTODAC8
				END;
				DSP.SetFrq(curAF.freq, 1)
			END;
			InitIrqHandler(TRUE);
			IF highspeed THEN
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, DMA.MSINGLE+DMA.MAUTOINIT+DMA.MREAD);
				DSP.SetTransferSize(actDB.len);
				IF DSP.res = DSP.Done THEN DSP.DspWrite(DSP.DSP2p8HIDMAAUTODAC)
				ELSE Out.String("error: setting transfersize"); Out.Ln; HALT(99)
				END;
				IF (curAF.blocks = 1) OR (curAF.blocks = 2) THEN bufcnt:= 3 END
			ELSIF single THEN
				IF Trace THEN Out.String("Sound single"); Out.Ln END;
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, actDB.len, DMA.MSINGLE+DMA.MREAD);
				DSP.DspWrite(DSP.DMADAC8); cmd:= SYSTEM.VAL(SET, DSP.DMADAC8);
				DSP.DspWrite(SHORT(actDB.len -1) MOD 100H);
				DSP.DspWrite(SHORT(actDB.len -1) DIV 100H);
				IF curAF.blocks=1 THEN bufcnt:= 3 END
			ELSE
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, DMA.MSINGLE+DMA.MAUTOINIT+DMA.MREAD);
				DSP.SetTransferSize(halfbufsize);
				IF DSP.res = DSP.Done THEN DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd))
				ELSE Out.String("Error in Sound with setting transfersize"); Out.Ln; HALT(99)
				END;
				cmd:= SYSTEM.VAL(SET, DSP.DMADAC8);
				IF curAF.blocks = 2 THEN
					DSP.DspWrite( SYSTEM.VAL(INTEGER, cmd));
					DSP.DspWrite(SHORT(endDB.len -1) MOD 100H);
					DSP.DspWrite(SHORT(endDB.len -1) DIV 100H);
					bufcnt:= 3
				END;
			END
		ELSE
			IF Trace THEN Out.String("DSP Init DSP4"); Out.Ln END;
			(* - DSP 4.XX ------------------------------------------------------- *)
			InitIrqHandler(TRUE);
			cmd:= DSP.DSP4CMDDAC + DSP.DSP4CMDFIFO;
			IF curAF.signed THEN Mode:= DSP.DSP4MSIG
			ELSE Mode:= DSP.DSP4MUNSIG END;
			IF curAF.stereo THEN Mode:= Mode + DSP.DSP4MST
			ELSE Mode:= Mode + DSP.DSP4MM END;
			m:= DMA.MSINGLE + DMA.MREAD;
			IF single THEN
				len:= endDB.len;
				bufcnt:= 3
			ELSE
				len:= DMA.BufSize;
				m:= m + DMA.MAUTOINIT;
				cmd:= cmd + DSP.DSP4CMDAUTOINIT
			END;
			IF curAF.bits = 16 THEN
				DMA.SetChannel(base.DspDmaW, DMA.TransBufAdr, len, m);
				cmd:= cmd + DSP.DSP4CMD16DMA;
				Divisor:= 2
			ELSE
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, len, m);
				cmd:= cmd + DSP.DSP4CMD8DMA
			END;
			DSP.DSP4DACFrq(curAF.freq);
			DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd));
			DSP.DspWrite(SYSTEM.VAL(INTEGER, Mode));
			DSP.DspWrite(SHORT((actDB.len DIV Divisor) -1) MOD 100H);
			DSP.DspWrite(SHORT((actDB.len DIV Divisor) -1) DIV 100H);
			IF curAF.blocks = 2 THEN
				DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd - {2}));
				DSP.DspWrite(SYSTEM.VAL(INTEGER, Mode));
				DSP.DspWrite(SHORT((endDB.len DIV Divisor) -1) MOD 100H);
				DSP.DspWrite(SHORT((endDB.len DIV Divisor) -1) DIV 100H);
				bufcnt:= 3
			END
		END;
		oldOT:= Oberon.Time();
		lastIrq:= oldOT;
		INCL(audioState, playing);
		EXCL(audioState, stopped);
		IF dopause THEN
			IF Trace THEN Out.String("Sound PlayPCM do pause"); Out.Ln END;
			PauseAudio()
		END
	ELSE
		res:= NSFreq
	END;
	IF Trace THEN Out.String("Sound PlayPCM End"); Out.Ln END
END PlayPCM;

PROCEDURE PlayADPCM;
	VAR Cmd: INTEGER; dopause: BOOLEAN;
BEGIN
	IF Trace THEN Out.String("Sound do PlayADPCM"); Out.Ln END;
	dopause:= FALSE; single:= FALSE;
	IF curAF.stereo OR (curAF.bits = 16) OR DSP.IsHMDACFrq(curAF.freq) THEN res:= Failed
	ELSIF DSP.AdjustFrq(curAF.freq, FALSE, curAF.stereo) THEN
		IF Trace THEN Out.String("Sound Frq adjusted"); Out.Ln END;
		InitIrqHandler(TRUE);
		ClearBuffer(DMA.TransBufAdr, DMA.BufSize, fillpat);
		IF nofbuf # 0 THEN
			ASSERT(curDB # NIL);
			SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr, curDB.len);
			lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf);
			IF Trace THEN Out.String("Sound 1st move"); Out.Ln END;
			IF (nofbuf # 0) THEN
				ASSERT(curDB # NIL);
				IF Trace THEN Out.String("Sound 2nd move"); Out.Ln END;
				SYSTEM.MOVE(SYSTEM.ADR(curDB.data), DMA.TransBufAdr+halfbufsize, curDB.len);
				lastDB:= curDB; curDB:= curDB.next; INC(bufcnt); DEC(nofbuf);
				IF base.DspVersion < DSP.DSP200 THEN
					IF Trace THEN Out.String("Sound single cycle play"); Out.Ln END;
					single:= TRUE
				END
			ELSIF curAF.blocks = bufcnt THEN
				IF Trace THEN Out.String("Sound single cycle play"); Out.Ln END;
				single:= TRUE
			ELSE
				IF Trace THEN Out.String("Sound only few blocks in queue"); Out.Ln END;
				curAF.handle(FALSE)
			END
		ELSE
			IF Trace THEN Out.String("Sound no blocks in queue"); Out.Ln END;
			curAF.handle(FALSE);
			dopause:= TRUE
		END;
		IF Trace THEN Out.String("Sound moved"); Out.Ln END;
		IF (DSP.DSP3XX<= base.DspVersion)&(base.DspVersion < DSP.DSP4XX) THEN
			DSP.DspWrite(DSP.DSP3MADC)
		END;
		IF base.DspVersion < DSP.DSP4XX THEN DSP.SetSpeaker(DSP.ON) END;
		IF base.DspVersion = DSP.DSP4XX THEN DSP.DSP4DACFrq(curAF.freq)
		ELSE DSP.SetFrq(curAF.freq, 1)
		END;
		IF single THEN
			IF Trace THEN Out.String("Sound single"); Out.Ln END;
			IF curAF.format = ADPCM8b2b THEN Cmd:= DSP.DMAADPCM8b2bSCR
			ELSIF curAF.format = ADPCM8b3b THEN Cmd:= DSP.DMAADPCM8b3bSCR
			ELSIF curAF.format = ADPCM8b4b THEN Cmd:= DSP.DMAADPCM8b4bSCR
			END;
			DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, actDB.len, DMA.MSINGLE+DMA.MREAD);
			DSP.DspWrite(Cmd);
			DSP.DspWrite(SHORT(actDB.len -1) MOD 100H);
			DSP.DspWrite(SHORT(actDB.len -1) DIV 100H);
			IF curAF.blocks = 1 THEN bufcnt:= 2 + bufcnt END
		ELSE
			IF curAF.format = ADPCM8b2b THEN Cmd:= DSP.DMAADPCM8b2bAI
			ELSIF curAF.format = ADPCM8b3b THEN Cmd:= DSP.DMAADPCM8b3bAI
			ELSIF curAF.format = ADPCM8b4b THEN Cmd:= DSP.DMAADPCM8b4bAI
			END;
			DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, DMA.MSINGLE+DMA.MAUTOINIT+DMA.MREAD);
			DSP.SetTransferSize(halfbufsize);
			IF DSP.res = DSP.Done THEN DSP.DspWrite(Cmd);
			ELSE Out.String("Error in Sound with setting transfersize"); Out.Ln; HALT(99)
			END;
			IF curAF.blocks = 2 THEN
				bufcnt:= 3;
				IF curAF.format = ADPCM8b2b THEN Cmd:= DSP.DMAADPCM8b2bSC
				ELSIF curAF.format = ADPCM8b3b THEN Cmd:= DSP.DMAADPCM8b3bSC
				ELSIF curAF.format = ADPCM8b4b THEN Cmd:= DSP.DMAADPCM8b4bSC
				END;
				DSP.DspWrite(Cmd);
				DSP.DspWrite(SHORT(endDB.len -1) MOD 100H);
				DSP.DspWrite(SHORT(endDB.len -1) DIV 100H);
			END
		END;
		cmd:= SYSTEM.VAL(SET, Cmd);
		oldOT:= Oberon.Time();
		INCL(audioState, playing);
		EXCL(audioState, stopped);
		IF dopause THEN
			IF Trace THEN Out.String("Sound PlayPCM do pause"); Out.Ln END;
			PauseAudio()
		END
	ELSE
		res:= NSFreq
	END;
	IF Trace THEN Out.String("Sound PlayPCM End"); Out.Ln END
END PlayADPCM;

PROCEDURE PlayAudio*();
BEGIN
	res:= Done;
	IF ~(opened IN audioState) THEN
		res:= NotOpened
	ELSIF stopped IN audioState THEN
		IF curAF.format = PCM THEN PlayPCM
		ELSIF curAF.format<4 THEN PlayADPCM
		ELSE res:= Failed
		END
	ELSE
		res:= Failed
	END
END PlayAudio;

PROCEDURE RecPCM;
	VAR Mode, m: SET; Divisor: INTEGER; dopause: BOOLEAN;
BEGIN
	IF Trace THEN Out.String("Sound do Record"); Out.Ln END;
	res:= Done;
	Mode:= {}; dopause:= FALSE; Divisor:= 2;
	IF DSP.AdjustFrq(curAF.freq, TRUE, curAF.stereo) THEN
		InitIrqHandler(FALSE);
		ClearBuffer(DMA.TransBufAdr, DMA.BufSize, fillpat);
		IF nofbuf = 0 THEN
			curAF.handle(FALSE); dopause:= TRUE;
			IF Trace THEN Out.String("Sound nofbuf = 0"); Out.Ln END
		END;
		highspeed:= FALSE;
		IF base.DspVersion < DSP.DSP200 THEN
			(*- DSP1xx ------------ *)
			DSP.SetSpeaker(DSP.OFF);
			DSP.SetFrq(curAF.freq, 1);
			DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, DMA.MSINGLE+DMA.MAUTOINIT+DMA.MWRITE);
			DSP.DspWrite(DSP.DMAADC8);
			DSP.DspWrite(SHORT(halfbufsize -1) MOD 100H);
			DSP.DspWrite(SHORT(halfbufsize -1) DIV 100H)
		ELSIF base.DspVersion < DSP.DSP4XX THEN
			(*- from DSP200 to DSP3xx ------------ *)
			IF Trace THEN Out.String("Sound Rec with DSP2xx or DSP3xx "); Out.Ln END;
			DSP.SetSpeaker(DSP.OFF);	(* if recording, always turn off the DSP-speaker *)
			IF curAF.stereo THEN	(* Stereo-recording, only with DSP3XX possible *)
				DSP.PrepareForStereo3(FALSE);
				DSP.DspWrite(DSP.DSP3STADC);
				DSP.SetFrq(curAF.freq, 2);
				cmd:= DSP.DSP2p8HIDMAAUTOADC;	(* Stereo always with HiSpeed-mode *)
				highspeed:= TRUE
			ELSE	(* Mono-recording *)
				IF base.DspVersion >= DSP.DSP3XX THEN DSP.DspWrite(DSP.DSP3MADC) END;
				IF DSP.IsHMADCFrq(curAF.freq) THEN cmd:= DSP.DSP2p8HIDMAAUTOADC;	
					highspeed:= TRUE;
					IF Trace THEN Out.String("Sound DSP201 HiSpeed used"); Out.Ln END
				ELSE cmd:= DSP.DMAAUTOADC8
				END;
				DSP.SetFrq(curAF.freq, 1)
			END;
			DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, DMA.MSINGLE+DMA.MAUTOINIT+DMA.MWRITE);
			DSP.SetTransferSize(halfbufsize);
			IF DSP.res = DSP.Done THEN DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd))
			ELSE Out.String("error: transfersize setting"); Out.Ln; HALT(99)
			END
		ELSE
			IF Trace THEN Out.String("DSP Rec with DSP4"); Out.Ln END;
			(* - DSP 4.XX ------------------------------------------------------- *)
			cmd:= DSP.DSP4CMDADC + DSP.DSP4CMDAUTOINIT + DSP.DSP4CMDFIFO;
			m:= DMA.MSINGLE + DMA.MAUTOINIT + DMA.MWRITE;
			IF curAF.bits = 16 THEN
				DMA.SetChannel(base.DspDmaW, DMA.TransBufAdr, DMA.BufSize, m);
				cmd:= cmd + DSP.DSP4CMD16DMA;
				Divisor:= Divisor*2
			ELSE
				DMA.SetChannel(base.DspDmaB, DMA.TransBufAdr, DMA.BufSize, m);
				cmd:= cmd + DSP.DSP4CMD8DMA
			END;
			IF curAF.signed THEN Mode:= DSP.DSP4MSIG
			ELSE Mode:= DSP.DSP4MUNSIG
			END;
			DSP.DSP4ADCFrq(curAF.freq);
			IF ~curAF.stereo THEN DSP.PrepareForMonoADC4; Mode:= Mode + DSP.DSP4MM
			ELSE Mode:= Mode + DSP.DSP4MST
			END;
			DSP.DspWrite(SYSTEM.VAL(INTEGER, cmd));
			DSP.DspWrite(SYSTEM.VAL(INTEGER, Mode));
			DSP.DspWrite(SHORT((DMA.BufSize DIV Divisor)-1) MOD 100H);
			DSP.DspWrite(SHORT((DMA.BufSize DIV Divisor)-1) DIV 100H)
		END;
		oldOT:= Oberon.Time();
		lastIrq:= oldOT;
		INCL(audioState, recording);
		EXCL(audioState, stopped);
		IF dopause THEN
			IF Trace THEN Out.String("Sound RecPCM do pause"); Out.Ln END;
			PauseAudio()
		END
	ELSE
		res:= NSFreq
	END;
	IF Trace THEN Out.String("Sound RecPCM End"); Out.Ln END
END RecPCM;

PROCEDURE RecordAudio*();
BEGIN
	IF ~(opened IN audioState) THEN
		res:= NotOpened
	ELSIF stopped IN audioState THEN
		IF curAF.format = PCM THEN RecPCM
		ELSE res:= Failed
		END
	ELSE
		res:= Failed
	END
END RecordAudio;

PROCEDURE PauseAudio*();
	VAR tmp: LONGINT;
BEGIN
	IF ~(opened IN audioState) THEN
		res:= NotOpened
	ELSIF paused IN audioState THEN
		res:= Failed
	ELSIF ~(stopped IN audioState) THEN
		IF Trace THEN Out.String("Sound do Pause"); Out.Ln END;
		INCL(audioState, paused);
		tmp:= Oberon.Time();
		INC(time, tmp- oldOT);
		IF highspeed THEN
			RestoreIrqHandler;
			DSP.DspReset;
			IF DSP.res = DSP.Failed THEN Out.String("Error in Sound with reset"); Out.Ln; HALT(90) END;
			IF curAF.stereo THEN DSP.RestoreFromStereo3; DSP.DspWrite(DSP.DSP3MADC) END;
			IF recording IN audioState THEN RecSpecEnd
			ELSE DEC(bufcnt); curDB:= lastDB; INC(nofbuf); DEC(curAF.blocks, bufcnt)
			END;
			bufcnt:= 0
		ELSE
			IF curAF.bits = 8 THEN DSP.DspWrite(DSP.DMAPAUSE)
			ELSE DSP.DspWrite(DSP.DSP4PAUSE16)
			END
		END;
		res:= Done
	ELSE
		res:= NotRunning
	END
END PauseAudio;

PROCEDURE ResumeAudio*();
BEGIN
	IF ~(opened IN audioState) THEN
		res:= NotOpened
	ELSIF paused IN audioState THEN
		IF Trace THEN Out.String("Sound do Resume"); Out.Ln END;
		IF highspeed THEN
			IF playing IN audioState THEN
				audioState:= {opened, stopped};
				PlayAudio()
			ELSIF recording IN audioState THEN
				audioState:= {opened, stopped};
				RecordAudio()
			END
		ELSE
			IF curAF.bits = 8 THEN DSP.DspWrite(DSP.DMACONT)
			ELSE DSP.DspWrite(DSP.DSP4CONT16)
			END;
			oldOT:= Oberon.Time();
			EXCL(audioState, paused)
		END;
		res:= Done
	ELSE
		res:= Failed
	END
END ResumeAudio;

PROCEDURE AddBlock*(buf: DataBlock);
BEGIN
	ASSERT(buf # NIL);
	IF Trace THEN Out.String("Sound AddBlock") END;
	IF nofbuf = 0 THEN
		IF Trace THEN Out.String(" = 0"); Out.Ln END;
		IF endDB = NIL THEN (* first call of AddBlock *) actDB:= buf; endDB:= buf
		ELSE endDB.next:= buf; endDB:= buf
		END;
		curDB:= buf; lastDB:= buf
	ELSE
		IF Trace THEN Out.String("  # 0"); Out.Ln END;
		endDB.next:= buf; endDB:= buf
	END;
	IF paused IN audioState THEN
		IF curAF.format < 4 THEN ResumeAudio() (* number in accordence to max. PCM constants *)
		ELSE (* skip now; later e.x. for fm-synthesis insert ResumeFM here *)
		END
	END;
	INC(nofbuf)
END AddBlock;

PROCEDURE GetAudioPos*(VAR msec: LONGINT);
	VAR tmp: LONGINT;
BEGIN
	res:= Done;
	IF opened IN audioState THEN
		IF (paused IN audioState) OR (stopped IN audioState) THEN msec:= time*1000 DIV Kernel.TimeUnit
		ELSIF ~(stopped IN audioState) THEN
			tmp:= Oberon.Time();
			INC(time, tmp-oldOT);
			oldOT:= tmp;
			msec:= time*1000  DIV Kernel.TimeUnit
		ELSE
			msec:= 0
		END
	ELSE
		res:= NotOpened
	END
END GetAudioPos;

PROCEDURE GetAudioState*(): SET;
BEGIN
	res:= Done;
	RETURN audioState
END GetAudioState;

(** CD *)
PROCEDURE CloseCD*();
BEGIN
	res := Done;
	IF cdDevID # -1 THEN
		CD.Stop();
		cdState := {};
		cdDevID := -1
	END
END CloseCD;

PROCEDURE OpenCD*();
BEGIN
	res := Done;
	IF cdDevID = -1 THEN
		cdDevID := CD.devID;
		IF (cdDevID < 0) THEN
			res := Failed
		ELSE
			cdState := {opened}
		END;
		IF res # Done THEN
			HALT(99)
		END
	END
END OpenCD;

PROCEDURE NrOfCDTracks*(): INTEGER;
	VAR last, first: INTEGER;
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSE
		CD.ReadTocHdr(first, last);
		IF first <= last THEN
			RETURN 1+ last - first
		END
	END;
	RETURN 0
END NrOfCDTracks;

PROCEDURE CDTrackInfo*(track: INTEGER; VAR min, sec: INTEGER);
	VAR first, last, min0, sec0, frame0, min1, sec1, frame1: INTEGER;
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSE
		CD.ReadTocEntry(track, min0, sec0, frame0);	(* get the start address of this track *)
		CD.ReadTocHdr(first, last);
		IF track < last THEN
			CD.ReadTocEntry(track+1, min1, sec1, frame1)
		ELSE
			CD.ReadTocEntry(0AAH, min1, sec1, frame1)
		END;
		min := min1 - min0;
		sec := sec1 - sec0;
		IF sec < 0 THEN
			sec := sec + 60;
			DEC(min)
		END
	END;
	IF res # Done THEN
		min := 0;
		sec := 0
	END
END CDTrackInfo;

PROCEDURE StopCD*();
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSE
		CD.Stop();
		EXCL(cdState, playing);
		EXCL(cdState, paused)
	END
END StopCD;

PROCEDURE CloseDoor*();
BEGIN
	CD.Load()
END CloseDoor;

PROCEDURE OpenDoor*();
BEGIN
	CD.Eject()
END OpenDoor;

PROCEDURE CDPaused(): BOOLEAN;
	VAR asc, ascq: CHAR;
BEGIN
	CD.Sense(asc, ascq);
	IF (asc = 0X) & (ascq = 12X) THEN
		INCL(cdState, paused)
	ELSE
		EXCL(cdState, paused)
	END;
	RETURN paused IN cdState
END CDPaused;

PROCEDURE PlayCD*(track0, min0, sec0, track1, min1, sec1: INTEGER);
	VAR frame0, frame1, min, sec: INTEGER;
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSE
		min := min1;
		sec := sec1;
		CD.ReadTocEntry(track0, min0, sec0, frame0);
		CD.ReadTocEntry(track1, min1, sec1, frame1);
		min1 := min1 + min;
		sec1 := sec1 + sec;
		IF sec1 >= 60 THEN
			INC(min1);
			sec1 := sec1 - 60
		END;
		CD.Play(min0, sec0, frame0, min1, sec1, frame1);
		res := Done
	END;
	IF res = Done THEN
		INCL(cdState, playing);
		EXCL(cdState, paused)
	END
END PlayCD;

PROCEDURE PauseCD*();
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSIF (playing IN cdState) & ~CDPaused() THEN
		CD.Pause();
		IF res = Done THEN
			EXCL(cdState, playing);
			INCL(cdState, paused)
		END
	ELSE
		res := NotRunning
	END
END PauseCD;

PROCEDURE ResumeCD*();
BEGIN
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSIF (paused IN cdState) OR CDPaused() THEN
		CD.Resume();
		INCL(cdState, playing);
		EXCL(cdState, paused)
	ELSE
		res := Failed
	END
END ResumeCD;

PROCEDURE GetCDState*(): SET;
	VAR medtyp: CHAR;
BEGIN
	res:= Done;
	IF cdDevID = -1 THEN
		res:= NotOpened;
		RETURN {}
	ELSE
		CD.MediumType(medtyp);
		IF medtyp # 71X THEN INCL(cdState, mediapresent)
		ELSE EXCL(cdState, mediapresent)
		END;
		RETURN cdState
	END
END GetCDState;

PROCEDURE GetCDPos*(VAR track, min, sec: INTEGER);
BEGIN
	res:= Done;
	IF cdDevID = -1 THEN
		res := NotOpened
	ELSIF ~(playing IN cdState) & ~(paused IN cdState) THEN
		track := 1;
		min := 0;
		sec := 0
	ELSE
		CD.GetPosition(track, min, sec);
		IF (track < 1) & (mediapresent IN GetCDState()) THEN
			track := 1;
			min := 0;
			sec := 0
		END
	END
END GetCDPos;

BEGIN
	Texts.OpenWriter(W);
	Init;
	irqinstalled:= FALSE; highspeed:= FALSE; irq:= FALSE; single:= FALSE; stoptime:= 0;
	curDB:= NIL; endDB:= NIL; nofbuf:= 0; halfbufsize:= DMA.BufSize DIV 2;
	cdDevID := -1;
	cdState := {};
	Kernel.InstallTermHandler(CloseAudio)
END Sound.


(** Remarks :
	1. If you have a SoundBlaster Pro then you should notice that you can use only one
		source-channel at a time. That means the choice of one source-channel is exclusive,
		and so the checkboxes for the selection of the needed source should be initialized
		with the same model. This way they behave like the known RadioButtons
		in the Windows environment (only one can be selected at a time).
*)
