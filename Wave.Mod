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

MODULE Wave;	(** non-portable *)	(** tb, SS96 *)
IMPORT Sound, Files, Oberon, Objects, Gadgets, BasicGadgets, Texts, TextGadgets, Modules;

(**
Wave-Module : Play and record WAV-Files
Author: Thomas Burri
Last Update:  

08.07.96 pjm - Added TermHandler
*)
	CONST
		Done* = 0;
		Failed* = 1;
		READATONCE = 2;
		WRITEATONCE = 2;
		HEADERLENGTH = 44;

	TYPE
		List = POINTER TO ListDesc;	(* Sound.DataBlock-management in use with recording *)
		ListDesc = RECORD
			next: List;
			link: Sound.DataBlock
		END;

	VAR
		res*: INTEGER;
		dd: Sound.AudioDef;
		Length, BufSize, readatonce, writeatonce, nofserving: LONGINT;
		filename: ARRAY 128 OF CHAR;
		file: Files.File;
		rider: Files.Rider;
		Root, End: List;
		serving, end, paused, recorded: BOOLEAN;
		T: Oberon.Task;
		obj: Objects.Object;
		L: Texts.Text;
		W: Texts.Writer;

(* ReadHeader: reads the file-header and calculates the number of blocks *)
PROCEDURE ReadHeader(VAR head: Sound.AudioDef);
	VAR s: ARRAY 5 OF CHAR; filelen, l, len: LONGINT; i: INTEGER; c: CHAR;
BEGIN
	res:= Done;
	Files.ReadBytes(rider, s, 4); s[4]:= 0X;
	IF s = "RIFF" THEN
		Files.ReadLInt(rider, filelen); 
		(* adjust the filelen *)
		len:= Files.Length(Files.Base(rider));
		IF len>filelen THEN filelen:= len END;
		Files.ReadBytes(rider, s, 4); s[4]:= 0X;
		IF s = "WAVE" THEN
			Files.ReadBytes(rider, s, 4); s[4]:= 0X;
			IF s = "fmt " THEN
				Files.ReadLInt(rider, l); Files.ReadInt(rider, i);
				IF i = 1 THEN head.format:= Sound.PCM
				ELSE res:= Failed; HALT(99)
				END;
				Files.ReadInt(rider, i);
				head.stereo:= (i = 2);
				Files.ReadLInt(rider, head.freq); Files.ReadLInt(rider, l); Files.ReadInt(rider, i);
				Files.ReadInt(rider, head.bits);
				IF head.bits = 16 THEN
					head.signed:= TRUE;
					IF head.stereo THEN readatonce:= 16
					ELSE readatonce:= 12
					END
				ELSE
					head.signed:= FALSE;
					IF head.stereo THEN readatonce:= 8
					ELSE readatonce:= 4
					END
				END;
				Files.Read(rider, c);
				IF c = "I" THEN (* assume it is INFO *)
					Files.Read(rider, c);  Files.Read(rider, c);  Files.Read(rider, c);
					Files.ReadLInt(rider, len);
					Files.Set(rider, file, Files.Pos(rider)+len);
					Files.Read(rider, c)
				END;
				i:= 0;
				WHILE (c # "d")&(i<50) DO Files.Read(rider, c); INC(i) END;
				IF c # "d" THEN res:= Failed
				ELSE
					(* read data length; if greater than the file-length, this will be the messure *)
					Files.ReadBytes(rider, s, 3); Files.ReadLInt(rider, Length);
					IF filelen-Files.Pos(rider) < Length THEN Length:= filelen-Files.Pos(rider) END;
					head.blocks:= Length DIV BufSize + 1;
					IF Length MOD BufSize = 0 THEN DEC(head.blocks) END;
				END
			ELSE res:= Failed
			END
		ELSE res:= Failed
		END
	ELSE res:= Failed
	END
END ReadHeader;

(* WriteHeader: writes the file-header *)
PROCEDURE WriteHeader(VAR fd: Sound.AudioDef);
	VAR s: ARRAY 5 OF CHAR; i: INTEGER;
BEGIN
	res:= Done;
	COPY("RIFF", s); Files.WriteBytes(rider, s, 4);
	Files.WriteLInt(rider, 0);
	COPY("WAVE", s); Files.WriteBytes(rider, s, 4);
	COPY("fmt ", s); Files.WriteBytes(rider, s, 4);
	Files.WriteLInt(rider, 16); Files.WriteInt(rider, 1);
	IF fd.stereo THEN i:= 2 ELSE i:= 1 END;
	Files.WriteInt(rider, i);
	Files.WriteLInt(rider, fd.freq);
	Files.WriteLInt(rider, fd.freq*i*(fd.bits DIV 8));	(* average number of bytes per sec *)
	Files.WriteInt(rider, (fd.bits DIV 8)*i);
	Files.WriteInt(rider, fd.bits);
	COPY("data", s); Files.WriteBytes(rider, s, 4);
	Files.WriteLInt(rider, Length)
END WriteHeader;

(* Upcall: trigger-function for indicating the need of blocks or the end of running *)
PROCEDURE *Upcall(b: BOOLEAN);
BEGIN
	IF ~b THEN serving:= TRUE
	ELSE end:= TRUE; serving:= FALSE
	END
END Upcall;

(* ReadHandler: Task during playing, reads the data from file into blocks and pushs them to the
	Sound-queue, time-counting and updating of LCD is done hear *)
PROCEDURE *ReadHandler(me: Oberon.Task);
	VAR newB: Sound.DataBlock; i, msec: LONGINT;
BEGIN
	IF serving THEN
		serving:= FALSE;
		i:= 0;
		WHILE ~rider.eof&(Length > BufSize)&(i < readatonce) DO
			NEW(newB); newB.len:= BufSize;
			Files.ReadBytes(rider, newB.data, BufSize);
			DEC(Length, BufSize);
			Sound.AddBlock(newB);
			INC(i)
		END;
		IF i # readatonce THEN
			IF ~rider.eof & (Length > 0) THEN
				NEW(newB); newB.len:= Length;
				Files.ReadBytes(rider, newB.data, Length);
				Length:= 0;
				Sound.AddBlock(newB)
			END;
			Files.Close(file)
		END
	END;
	IF end THEN
		end:= FALSE;
		Oberon.Remove(T);
		Files.Close(file);
		Sound.CloseAudio()
	ELSIF obj # NIL THEN
		WITH obj:BasicGadgets.Integer DO
			Sound.GetAudioPos(msec);
			IF Sound.res = Sound.Done THEN
				msec:= msec DIV 1000;
				IF msec > obj.val THEN
					obj.val:= msec;
					Gadgets.Update(obj)
				END
			END
		END
	END
END ReadHandler;

(* WriteHandler: Task during recording, pushes empty blocks to the Sound-queue if necessary and
	beginns to write the full blocks to the file, when stopped, the whole data is written to the file,
	time-counting and updating of LCD is done hear *)
PROCEDURE *WriteHandler(me: Oberon.Task);
	VAR newL: List; newB: Sound.DataBlock; i, msec: LONGINT;
BEGIN
	IF serving THEN
		serving:= FALSE;
		INC(nofserving);
		i:= 0;
		WHILE i < writeatonce DO
			NEW(newL); NEW(newB);
			newL.link:= newB; End.next:= newL; End:= newL; newB.len:= 0;
			Sound.AddBlock(newB);
			INC(i)
		END;
		IF (nofserving > 3)&(Root.link.len # 0) THEN
			nofserving:= 0;
			Files.WriteBytes(rider, Root.link.data, Root.link.len);
			INC(Length, Root.link.len);
			INC(dd.blocks);
			Root:= Root.next
		END
	END;
	IF end THEN
		end:= FALSE;
		Oberon.Remove(T);
		Sound.CloseAudio();
		(* write sample-data to file *)
		WHILE (Root # NIL)&(Root.link.len # 0) DO
			Files.WriteBytes(rider, Root.link.data, Root.link.len);
			INC(Length, Root.link.len);
			Root:= Root.next;
			INC(dd.blocks)
		END;
		Files.Set(rider, file, 4);
		Files.WriteLInt(rider, Length+HEADERLENGTH);
		Files.Set(rider, file, 40);
		Files.WriteLInt(rider, Length);
		Files.Close(file);
		Root:= NIL;
		recorded:= TRUE
	ELSIF obj # NIL THEN
		WITH obj:BasicGadgets.Integer DO
			Sound.GetAudioPos(msec);
			IF Sound.res = Sound.Done THEN
				msec:= msec DIV 1000;
				IF msec > obj.val THEN
					obj.val:= msec;
					Gadgets.Update(obj)
				END
			END
		END
	END
END WriteHandler;

(* OutInfo: shows the AudioDef-values of the current file in the FileInfo - TextGadget *)
PROCEDURE OutInfo(obj: Objects.Object; VAR ad: Sound.AudioDef);
BEGIN
	L:= obj(TextGadgets.Frame).text;
	Texts.Delete(L,0,L.len);
	Texts.WriteString(W, "Frequency: "); Texts.WriteInt(W, ad.freq, 0); Texts.WriteLn(W);
	Texts.WriteString(W, "Bits: "); Texts.WriteInt(W, ad.bits, 0); Texts.WriteLn(W);
	IF ad.stereo THEN Texts.WriteString(W, "stereo")ELSE Texts.WriteString(W, "mono") END;
	Texts.WriteLn(W);
	IF ad.signed THEN Texts.WriteString(W, "signed") ELSE Texts.WriteString(W, "unsigned") END;
	Texts.WriteLn(W);
	Texts.WriteString(W, "blocks: "); Texts.WriteInt(W, ad.blocks, 0);
	Texts.WriteLn(W);
	Texts.Append(L, W.buf)
END OutInfo;

(** Play: plays the file in the TextField or the last recorded one before it is stored *)
PROCEDURE Play*;
	VAR fi: Objects.Object; S: Texts.Scanner;
BEGIN
	IF ~recorded OR (file = NIL) THEN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
		COPY(S.s, filename);
		file:= Files.Old(filename)
	END;
	IF file # NIL THEN
		obj:= Gadgets.FindObj(Gadgets.context, "WaveSec");
		IF obj # NIL THEN obj(BasicGadgets.Integer).val:= 0; Gadgets.Update(obj) END;
		Files.Set(rider, file, 0);
		ReadHeader(dd);
		IF res = Done THEN
			fi:= Gadgets.FindObj(Gadgets.context, "FileInfo");
			IF fi # NIL THEN OutInfo(fi, dd) END;
			dd.handle:= Upcall;
			Sound.OpenAudio(dd);
			IF Sound.res = Sound.Done THEN
				serving:= TRUE; ReadHandler(T);
				T.handle:= ReadHandler; Oberon.Install(T);
				readatonce:= READATONCE;
				Sound.PlayAudio();
				IF Sound.res = Sound.Done THEN
					res:= Done
				ELSE
					Oberon.Remove(T);
					Sound.CloseAudio();
					res:= Failed
				END
			ELSE
				res:= Failed
			END
		END;
		IF res = Failed THEN Files.Close(file) END
	ELSE
		res:= Failed
	END
END Play;

(** Record: reads the values out of the Wave.Panel and starts the recording *)
PROCEDURE Record*;
	VAR newL: List; newB: Sound.DataBlock; Frq, St: INTEGER; fi: Objects.Object; S: Texts.Scanner;
BEGIN
	(*IF recorded & (file # NIL) THEN Files.Purge(file) END;*)
	file:= NIL;
	recorded:= FALSE;
	Root:= NIL;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); COPY(S.s, filename);
	Texts.Scan(S); dd.bits:= SHORT(S.i); Texts.Scan(S); Frq:= SHORT(S.i);
	Texts.Scan(S); St:= SHORT(S.i);
	(* In.Open; In.String(filename); In.Int(dd.bits); In.Int(Frq); In.Int(St); *)
	dd.freq:= LONG(Frq)*11025; dd.stereo:= (St = 2); dd.blocks:= 0;
	IF dd.bits = 16 THEN dd.signed:= TRUE;
		IF dd.stereo THEN writeatonce:= 10 ELSE writeatonce:= 8 END
	ELSE dd.signed:= FALSE;
		IF dd.stereo THEN writeatonce:= 6 ELSE writeatonce:= 4 END
	END;
	fi:= Gadgets.FindObj(Gadgets.context, "FileInfo");
	IF fi # NIL THEN OutInfo(fi, dd) END;
	obj:= Gadgets.FindObj(Gadgets.context, "WaveSec");
	IF obj # NIL THEN obj(BasicGadgets.Integer).val:= 0; Gadgets.Update(obj) END;
	end:= FALSE;
	dd.handle:= Upcall;
	Sound.OpenAudio(dd);
	IF Sound.res = Sound.Done THEN
		file:= Files.New(filename);
		IF file # NIL THEN
			Files.Set(rider, file, 0);
			WriteHeader(dd);
			Files.Set(rider, file, HEADERLENGTH);
			NEW(newL); Root:= newL; End:= newL; NEW(newB);
			newL.link:= newB;
			Sound.AddBlock(newB);
			serving:= TRUE; WriteHandler(T);
			nofserving:= 0;
			T.handle:= WriteHandler; Oberon.Install(T);
			writeatonce:= WRITEATONCE;
			Length:= 0; dd.blocks:= 0;
			Sound.RecordAudio();
			IF Sound.res = Sound.Done THEN
				res:= Done
			ELSE
				Oberon.Remove(T);
				Sound.CloseAudio();
				Files.Close(file);
				res:= Failed
			END
		ELSE
			res:= Failed
		END
	ELSE
		res:= Failed
	END
END Record;

(** Stop: stops the running; if the Pause-Button is pushed, it releases it *)
PROCEDURE Stop*;
	VAR obj: Objects.Object; A: Objects.AttrMsg;
BEGIN
	res:= Done;
	Sound.StopAudio();
	IF Sound.res # Sound.Done THEN res:= Failed END;
	IF paused THEN
		obj:= Gadgets.FindObj(Gadgets.context, "Pause");
		IF obj # NIL THEN
			A.id:= Objects.set; A.name:= "Value"; A.b:= FALSE; A.class:= Objects.Bool;
			obj.handle(obj, A);
			Gadgets.Update(obj)
		END;
		paused:= FALSE
	END
END Stop;

(** Pause: for the fist call it breaks the running, with the second call it continues the running *)
PROCEDURE Pause*;
BEGIN
	res:= Done;
	IF Sound.opened IN Sound.GetAudioState() THEN
		IF ~paused THEN
			Sound.PauseAudio; paused:= TRUE
		ELSE
			serving:= TRUE; ReadHandler(T);
			Sound.ResumeAudio; paused:= FALSE
		END
	END;
	IF Sound.res # Sound.Done THEN res:= Failed END
END Pause;

(** Store: register the recorded file in the directory, an existing one will be renamed to *.Bak *)
PROCEDURE Store*;
	VAR name: ARRAY 32 OF CHAR; r: INTEGER;
	
	PROCEDURE Concat(VAR str: ARRAY OF CHAR; suf: ARRAY OF CHAR);
		VAR i, j: INTEGER;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		j := 0;
		WHILE suf[j] # 0X DO
			str[i] := suf[j];
			INC(i);
			INC(j)
		END;
		str[i] := 0X
	END Concat;

BEGIN
	res:= Done;
	IF recorded & (file # NIL) THEN
		COPY(filename, name); Concat(name, ".Bak");
		Files.Rename(filename, name, r);
		Files.Register(file);
		recorded:= FALSE;
		file:= NIL;
		Texts.WriteString(W, "stored"); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	ELSE
		res:= Failed
	END
END Store;

(** Show: used in the Wave.Panel for moving the selected Wave-File in the list to the TextField *)
PROCEDURE Show*;
	VAR gobj: Objects.Object; A: Objects.AttrMsg; S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	COPY(S.s, A.s);
	A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.String;
	gobj:= Gadgets.FindObj(Gadgets.context, "FName");
	IF gobj # NIL THEN
		gobj.handle(gobj, A);
		Gadgets.Update(gobj);
		(*IF recorded & (file # NIL) THEN Files.Purge(file) END;*)
		file:= NIL; recorded:= FALSE
	END
END Show;

PROCEDURE Cleanup;
BEGIN
	Oberon.Remove(T)
END Cleanup;

BEGIN
	Root:= NIL; file:= NIL; filename:= "TMP.Wav";
	NEW(T); T.safe:= FALSE;
	BufSize:= Sound.DBdataSize; end:= FALSE; paused:= FALSE; recorded:= FALSE;
	Texts.OpenWriter(W);
	Modules.InstallTermHandler(Cleanup)
END Wave.

Desktops.OpenDoc Wave.Panel
