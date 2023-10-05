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

MODULE Au;	(** non-portable *)	(** tb, SS96 *)
IMPORT SYSTEM, Sound, Files, Oberon, Objects, Gadgets, BasicGadgets, Texts, TextGadgets, Modules;

(**
Au-Module : Play and record Au-Files
Author: Thomas Burri
Last Update:  

08.07.96 pjm - Added TermHandler
*)
	CONST
		Done* = 0;
		Failed* = 1;
		READATONCE = 2;
		WRITEATONCE = 2;
		MAGIC = 2E736E64H;

	TYPE
		List = POINTER TO ListDesc;	(* Sound.DataBlock-management in use with recording *)
		ListDesc = RECORD
			next: List;
			link: Sound.DataBlock
		END;

	VAR
		res*: INTEGER;
		dd: Sound.AudioDef;
		Length, BufSize, readatonce, writeatonce, nofserving, enc: LONGINT;
		filename: ARRAY 128 OF CHAR;
		file: Files.File;
		rider: Files.Rider;
		Root, End: List;
		serving, end, paused, ulaw, recorded: BOOLEAN;
		T: Oberon.Task;
		obj: Objects.Object;
		L: Texts.Text;
		W: Texts.Writer;
		utd, dtu: ARRAY 256 OF INTEGER;

(* ConvLongInt: convertion of Little Endian to Big Endian and vice-versa *)
PROCEDURE ConvLongInt(VAR s: ARRAY OF SYSTEM.BYTE);
	VAR x: SYSTEM.BYTE;
BEGIN
	x := s[0]; s[0] := s[3]; s[3] := x;
	x := s[1]; s[1] := s[2]; s[2] := x
END ConvLongInt;

(* SetAF: according to the enc-variable sets up the AudioDef-values *)
PROCEDURE SetAF(enc: LONGINT; VAR af: Sound.AudioDef);
BEGIN
	af.blocks:= 0; af.stereo:= FALSE; af.signed:= FALSE;
	IF enc = 0 THEN af.format:= Sound.PCM; af.bits:= 8
	ELSIF enc = 1 THEN af.format := Sound.PCM; af.bits:= 8; ulaw:= TRUE
	ELSIF enc = 2 THEN af.format:= Sound.PCM; af.bits:= 8; af.signed:= TRUE
	ELSIF enc = 3 THEN af.format:= Sound.PCM; af.bits:= 16; af.signed:= TRUE
	ELSIF enc = 23 THEN af.format:= Sound.ADPCM8b4b; af.bits:= 8
	ELSE res:= Failed
	END;
END SetAF;

(* ReadHeader: reads the file-header and calculates the number of blocks *)
PROCEDURE ReadHeader(VAR head: Sound.AudioDef);
	VAR magic, hdr, enc, chan, pos: LONGINT; ch: CHAR;
BEGIN
	res:= Done;
	Files.ReadLInt(rider, magic); ConvLongInt(magic);
	Files.ReadLInt(rider, hdr); ConvLongInt(hdr);
	Files.ReadLInt(rider, Length); ConvLongInt(Length);
	Files.ReadLInt(rider, enc); ConvLongInt(enc);
	Files.ReadLInt(rider, head.freq); ConvLongInt(head.freq);
	Files.ReadLInt(rider, chan); ConvLongInt(chan);
	pos := 24;
	WHILE pos < hdr DO Files.Read(rider, ch); INC(pos) END;
	ulaw:= FALSE;
	SetAF(enc, head);
	IF res # Failed THEN
		head.stereo := (chan = 2);
		IF head.bits = 16 THEN
			IF head.stereo THEN readatonce:= 16 ELSE readatonce:= 12 END
		ELSE readatonce:= 8
		END;
		IF Files.Length(file)-hdr  < Length THEN Length:= Files.Length(file) END;
		head.blocks:= Length DIV BufSize + 1;
		IF Length MOD BufSize = 0 THEN DEC(head.blocks) END;
	END;
END ReadHeader;

(* WriteHeader: writes the file-header *)
PROCEDURE WriteHeader(VAR head: Sound.AudioDef);
	VAR magic, hdr, chan: LONGINT;
BEGIN
	res:= Done;
	magic:= MAGIC; ConvLongInt(magic); Files.WriteLInt(rider, magic);
	hdr:= 24; ConvLongInt(hdr); Files.WriteLInt(rider, hdr);
	ConvLongInt(Length); Files.WriteLInt(rider, Length);
	ConvLongInt(enc); Files.WriteLInt(rider, enc);
	ConvLongInt(head.freq); Files.WriteLInt(rider, head.freq);
	IF head.stereo THEN chan:= 2 ELSE chan:= 1 END;
	ConvLongInt(chan); Files.WriteLInt(rider, chan)
END WriteHeader;

(* Upcall: trigger-function for indicating the need of blocks or the end of running *)
PROCEDURE *Upcall(b: BOOLEAN);
BEGIN
	IF ~b THEN serving:= TRUE
	ELSE end:= TRUE; serving:= FALSE
	END
END Upcall;

(* ConvDtU: converts data from ulaw-format to DSP *)
PROCEDURE ConvUtD(VAR b: Sound.DataBlock);
	VAR i,j: LONGINT;
BEGIN
	i:= 0;
	WHILE i < b.len DO
		j:= ORD(SYSTEM.VAL(CHAR, b.data[i]));
		b.data[i]:= SYSTEM.VAL(SYSTEM.BYTE, utd[j]);
		INC(i) END
END ConvUtD;

(* ConvDtU: converts data from DSP-format to ulaw *)
PROCEDURE ConvDtU(VAR b: Sound.DataBlock);
	VAR i,j: LONGINT;
BEGIN
	i:= 0;
	WHILE i < b.len DO
		j:= ORD(SYSTEM.VAL(CHAR, b.data[i]));
		b.data[i]:= SYSTEM.VAL(SYSTEM.BYTE, dtu[j]);
		INC(i) END
END ConvDtU;

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
			IF ulaw THEN ConvUtD(newB) END;
			DEC(Length, BufSize);
			Sound.AddBlock(newB);
			INC(i)
		END;
		IF i # readatonce THEN
			IF Length > 0 THEN
				NEW(newB); newB.len:= Length;
				Files.ReadBytes(rider, newB.data, Length);
				IF ulaw THEN ConvUtD(newB) END;
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
			IF ulaw THEN ConvDtU(Root.link) END;
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
			IF ulaw THEN ConvDtU(Root.link) END;
			Files.WriteBytes(rider, Root.link.data, Root.link.len);
			INC(Length, Root.link.len);
			Root:= Root.next;
			INC(dd.blocks)
		END;
		Files.Set(rider, file, 8);
		ConvLongInt(Length);
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
		obj:= Gadgets.FindObj(Gadgets.context, "Sec");
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

(** Record: reads the values out of the Audio.Panel and starts the recording *)
PROCEDURE Record*;
	VAR newL: List; newB: Sound.DataBlock; fi: Objects.Object; S: Texts.Scanner;
BEGIN
	(*IF recorded & (file # NIL) THEN Files.Purge(file) END;*)
	file:= NIL;
	recorded:= FALSE;
	Root:= NIL;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S); COPY(S.s, filename); Texts.Scan(S); dd.freq:= S.i;
	 Texts.Scan(S); enc:= SHORT(S.i);
	SetAF(enc, dd);
	IF dd.bits = 16 THEN
		IF dd.stereo THEN writeatonce:= 8 ELSE writeatonce:= 6 END
	ELSE
		writeatonce:= 4
	END;
	fi:= Gadgets.FindObj(Gadgets.context, "FileInfo");
	IF fi # NIL THEN OutInfo(fi, dd) END;
	obj:= Gadgets.FindObj(Gadgets.context, "Sec");
	IF obj # NIL THEN obj(BasicGadgets.Integer).val:= 0; Gadgets.Update(obj) END;
	end:= FALSE;
	dd.handle:= Upcall;
	Sound.OpenAudio(dd);
	IF Sound.res = Sound.Done THEN
		file:= Files.New(filename);
		IF file # NIL THEN
			Files.Set(rider, file, 0);
			WriteHeader(dd);
			Files.Set(rider, file, 24);
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

(** Show: used in the Audio.Panel for moving the selected Au-File in the list to the TextField *)
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
	Root:= NIL; file:= NIL; filename:= "TMP.Au";
	NEW(T); T.safe:= FALSE;
	BufSize:= Sound.DBdataSize; end:= FALSE; paused:= FALSE; recorded:= FALSE; ulaw:= FALSE;
	Texts.OpenWriter(W);
	Modules.InstallTermHandler(Cleanup);

	(* convertion tables for ulaw - data *)
	utd[0]:= 0; utd[1]:= 0; utd[2]:= 0; utd[3]:= 0; utd[4]:= 0; utd[5]:= 0; utd[6]:= 0; utd[7]:= 0;
	utd[8]:= 0; utd[9]:= 0; utd[10]:= 0; utd[11]:= 0; utd[12]:= 0; utd[13]:= 0; utd[14]:= 0; utd[15]:= 0;
	utd[16]:= 0; utd[17]:= 0; utd[18]:= 0; utd[19]:= 0; utd[20]:= 0; utd[21]:= 0; utd[22]:= 0; utd[23]:= 0;
	utd[24]:= 0; utd[25]:= 0; utd[26]:= 0; utd[27]:= 0; utd[28]:= 0; utd[29]:= 0; utd[30]:= 0; utd[31]:= 2;
	utd[32]:= 5; utd[33]:= 9; utd[34]:= 13; utd[35]:= 17; utd[36]:= 21; utd[37]:= 25; utd[38]:= 29; utd[39]:= 33;
	utd[40]:= 37; utd[41]:= 41; utd[42]:= 45; utd[43]:= 49; utd[44]:= 53; utd[45]:= 57; utd[46]:= 61; utd[47]:= 65;
	utd[48]:= 68; utd[49]:= 70; utd[50]:= 72; utd[51]:= 74; utd[52]:= 76; utd[53]:= 78; utd[54]:= 80; utd[55]:= 82;
	utd[56]:= 84; utd[57]:= 86; utd[58]:= 88; utd[59]:= 90; utd[60]:= 92; utd[61]:= 94; utd[62]:= 96; utd[63]:= 98;
	utd[64]:= 100; utd[65]:= 101; utd[66]:= 102; utd[67]:= 103; utd[68]:= 104; utd[69]:= 105; utd[70]:=106 ; utd[71]:= 107;
	utd[72]:= 108; utd[73]:= 109; utd[74]:= 110; utd[75]:= 111; utd[76]:= 112; utd[77]:= 113; utd[78]:= 114; utd[79]:= 115;
	utd[80]:= 115; utd[81]:= 116; utd[82]:= 116; utd[83]:= 117; utd[84]:= 117; utd[85]:= 118; utd[86]:= 118; utd[87]:= 119;
	utd[88]:= 119; utd[89]:= 120; utd[90]:= 120; utd[91]:=121 ; utd[92]:= 121; utd[93]:= 122; utd[94]:= 122; utd[95]:= 123;
	utd[96]:= 123; utd[97]:= 123; utd[98]:= 124; utd[99]:= 124; utd[100]:= 124; utd[101]:= 124; utd[102]:= 125; utd[103]:= 125;
	utd[104]:= 125; utd[105]:= 125; utd[106]:= 126; utd[107]:= 126; utd[108]:= 126; utd[109]:= 126; utd[110]:= 127; utd[111]:= 127;
	utd[112]:= 127; utd[113]:= 127; utd[114]:= 127; utd[115]:= 127; utd[116]:= 128; utd[117]:= 128; utd[118]:= 128; utd[119]:= 128;
	utd[120]:= 128; utd[121]:= 128; utd[122]:= 128; utd[123]:= 128; utd[124]:= 128; utd[125]:= 128; utd[126]:= 128; utd[127]:= 128;
	utd[128]:= 255; utd[129]:= 255; utd[130]:= 255; utd[131]:= 255; utd[132]:= 255; utd[133]:= 255; utd[134]:= 255; utd[135]:= 255;
	utd[136]:= 255; utd[137]:= 255; utd[138]:= 255; utd[139]:= 255; utd[140]:= 255; utd[141]:= 255; utd[142]:= 255; utd[143]:= 255;
	utd[144]:= 255; utd[145]:= 255; utd[146]:= 255; utd[147]:= 255; utd[148]:= 255; utd[149]:= 255; utd[150]:= 255; utd[151]:= 255;
	utd[152]:= 255; utd[153]:= 255; utd[154]:= 255; utd[155]:= 255; utd[156]:= 255; utd[157]:= 255; utd[158]:= 255; utd[159]:= 255;
	utd[160]:= 252; utd[161]:= 248; utd[162]:= 244; utd[163]:= 240; utd[164]:= 236; utd[165]:= 232; utd[166]:= 228; utd[167]:= 224;
	utd[168]:= 220; utd[169]:= 216; utd[170]:= 212; utd[171]:= 208; utd[172]:= 204; utd[173]:= 200; utd[174]:= 196; utd[175]:= 192;
	utd[176]:= 189; utd[177]:= 187; utd[178]:= 185; utd[179]:= 183; utd[180]:= 181; utd[181]:= 179; utd[182]:= 177; utd[183]:= 175;
	utd[184]:= 173; utd[185]:= 171; utd[186]:= 169; utd[187]:= 167; utd[188]:= 165; utd[189]:= 163; utd[190]:= 161; utd[191]:= 159;
	utd[192]:= 157; utd[193]:= 156; utd[194]:= 155; utd[195]:= 154; utd[196]:= 153; utd[197]:= 152; utd[198]:= 151; utd[199]:= 150;
	utd[200]:= 149; utd[201]:= 148; utd[202]:= 147; utd[203]:= 146; utd[204]:= 145; utd[205]:= 144; utd[206]:= 143; utd[207]:= 142;
	utd[208]:= 142; utd[209]:= 141; utd[210]:= 141; utd[211]:= 140; utd[212]:= 140; utd[213]:= 139; utd[214]:= 139; utd[215]:= 138;
	utd[216]:= 138; utd[217]:= 137; utd[218]:= 137; utd[219]:= 136; utd[220]:= 136; utd[221]:= 135; utd[222]:= 135; utd[223]:= 134;
	utd[224]:= 134; utd[225]:= 134; utd[226]:= 133; utd[227]:= 133; utd[228]:= 133; utd[229]:= 133; utd[230]:= 132; utd[231]:= 132;
	utd[232]:= 132; utd[233]:= 132; utd[234]:= 131; utd[235]:= 131; utd[236]:= 131; utd[237]:= 131; utd[238]:= 130; utd[239]:= 130;
	utd[240]:= 130; utd[241]:= 130; utd[242]:= 130; utd[243]:= 130; utd[244]:= 129; utd[245]:= 129; utd[246]:= 129; utd[247]:= 129;
	utd[248]:= 129; utd[249]:= 129; utd[250]:= 129; utd[251]:= 129; utd[252]:= 128; utd[253]:= 128; utd[254]:= 128; utd[255]:= 128;

	dtu[0]:= 31; dtu[1]:= 31; dtu[2]:= 31; dtu[3]:= 32; dtu[4]:= 32; dtu[5]:= 32; dtu[6]:= 32; dtu[7]:= 33;
	dtu[8]:= 33; dtu[9]:= 33; dtu[10]:= 33; dtu[11]:= 34; dtu[12]:= 34; dtu[13]:= 34; dtu[14]:= 34; dtu[15]:= 35;
	dtu[16]:= 35; dtu[17]:= 35; dtu[18]:= 35; dtu[19]:= 36; dtu[20]:= 36; dtu[21]:= 36; dtu[22]:= 36; dtu[23]:= 37;
	dtu[24]:= 37; dtu[25]:= 37; dtu[26]:= 37; dtu[27]:= 38; dtu[28]:= 38; dtu[29]:= 38; dtu[30]:= 38; dtu[31]:= 39;
	dtu[32]:= 39; dtu[33]:= 39; dtu[34]:= 39; dtu[35]:= 40; dtu[36]:= 40; dtu[37]:= 40; dtu[38]:= 40; dtu[39]:= 41;
	dtu[40]:= 41; dtu[41]:= 41; dtu[42]:= 41; dtu[43]:= 42; dtu[44]:= 42; dtu[45]:= 42; dtu[46]:= 42; dtu[47]:= 43;
	dtu[48]:= 43; dtu[49]:= 43; dtu[50]:= 43; dtu[51]:= 44; dtu[52]:= 44; dtu[53]:= 44; dtu[54]:= 44; dtu[55]:= 45;
	dtu[56]:= 45; dtu[57]:= 45; dtu[58]:= 45; dtu[59]:= 46; dtu[60]:= 46; dtu[61]:= 46; dtu[62]:= 46; dtu[63]:= 47;
	dtu[64]:= 47; dtu[65]:= 47; dtu[66]:= 47; dtu[67]:= 48; dtu[68]:= 48; dtu[69]:= 49; dtu[70]:= 49; dtu[71]:= 50;
	dtu[72]:= 50; dtu[73]:= 51; dtu[74]:= 51; dtu[75]:= 52; dtu[76]:= 52; dtu[77]:= 53; dtu[78]:= 53; dtu[79]:= 54;
	dtu[80]:= 54; dtu[81]:= 55; dtu[82]:= 55; dtu[83]:= 56; dtu[84]:= 56; dtu[85]:= 57; dtu[86]:= 57; dtu[87]:= 58;
	dtu[88]:= 58; dtu[89]:= 59; dtu[90]:= 59; dtu[91]:= 60; dtu[92]:= 60; dtu[93]:= 61; dtu[94]:= 61; dtu[95]:= 62;
	dtu[96]:= 62; dtu[97]:= 63; dtu[98]:= 63; dtu[99]:= 64; dtu[100]:= 65; dtu[101]:= 66; dtu[102]:= 67; dtu[103]:= 68;
	dtu[104]:= 69; dtu[105]:= 70; dtu[106]:= 71; dtu[107]:= 72; dtu[108]:= 73; dtu[109]:= 74; dtu[110]:= 75; dtu[111]:= 76;
	dtu[112]:= 77; dtu[113]:= 78; dtu[114]:= 79; dtu[115]:= 81; dtu[116]:= 83; dtu[117]:= 85; dtu[118]:= 87; dtu[119]:= 89;
	dtu[120]:= 91; dtu[121]:= 93; dtu[122]:= 95; dtu[123]:= 99; dtu[124]:= 103; dtu[125]:= 107; dtu[126]:= 111; dtu[127]:= 119;
	dtu[128]:= 255; dtu[129]:= 247; dtu[130]:= 239; dtu[131]:= 235; dtu[132]:= 231; dtu[133]:= 227; dtu[134]:= 223; dtu[135]:= 221;
	dtu[136]:= 219; dtu[137]:= 217; dtu[138]:= 215; dtu[139]:= 213; dtu[140]:= 211; dtu[141]:= 209; dtu[142]:= 207; dtu[143]:= 206;
	dtu[144]:= 205; dtu[145]:= 204; dtu[146]:= 203; dtu[147]:= 202; dtu[148]:= 201; dtu[149]:= 200; dtu[150]:= 199; dtu[151]:= 198;
	dtu[152]:= 197; dtu[153]:= 196; dtu[154]:= 195; dtu[155]:= 194; dtu[156]:= 193; dtu[157]:= 192; dtu[158]:= 191; dtu[159]:= 191;
	dtu[160]:= 190; dtu[161]:= 190; dtu[162]:= 189; dtu[163]:= 189; dtu[164]:= 188; dtu[165]:= 188; dtu[166]:= 187; dtu[167]:= 187;
	dtu[168]:= 186; dtu[169]:= 186; dtu[170]:= 185; dtu[171]:= 185; dtu[172]:= 184; dtu[173]:= 184; dtu[174]:= 183; dtu[175]:= 183;
	dtu[176]:= 182; dtu[177]:= 182; dtu[178]:= 181; dtu[179]:= 181; dtu[180]:= 180; dtu[181]:= 180; dtu[182]:= 179; dtu[183]:= 179;
	dtu[184]:= 178; dtu[185]:= 178; dtu[186]:= 177; dtu[187]:= 177; dtu[188]:= 176; dtu[189]:= 176; dtu[190]:= 175; dtu[191]:= 175;
	dtu[192]:= 175; dtu[193]:= 175; dtu[194]:= 174; dtu[195]:= 174; dtu[196]:= 174; dtu[197]:= 174; dtu[198]:= 173; dtu[199]:= 173;
	dtu[200]:= 173; dtu[201]:= 173; dtu[202]:= 172; dtu[203]:= 172; dtu[204]:= 172; dtu[205]:= 172; dtu[206]:= 171; dtu[207]:= 171;
	dtu[208]:= 171; dtu[209]:= 171; dtu[210]:= 170; dtu[211]:= 170; dtu[212]:= 170; dtu[213]:= 170; dtu[214]:= 169; dtu[215]:= 169;
	dtu[216]:= 169; dtu[217]:= 169; dtu[218]:= 168; dtu[219]:= 168; dtu[220]:= 168; dtu[221]:= 168; dtu[222]:= 167; dtu[223]:= 167;
	dtu[224]:= 167; dtu[225]:= 167; dtu[226]:= 166; dtu[227]:= 166; dtu[228]:= 166; dtu[229]:= 166; dtu[230]:= 165; dtu[231]:= 165;
	dtu[232]:= 165; dtu[233]:= 165; dtu[234]:= 164; dtu[235]:= 164; dtu[236]:= 164; dtu[237]:= 164; dtu[238]:= 163; dtu[239]:= 163;
	dtu[240]:= 163; dtu[241]:= 163; dtu[242]:= 162; dtu[243]:= 162; dtu[244]:= 162; dtu[245]:= 162; dtu[246]:= 161; dtu[247]:= 161;
	dtu[248]:= 161; dtu[249]:= 161; dtu[250]:= 160; dtu[251]:= 160; dtu[252]:= 160; dtu[253]:= 160; dtu[254]:= 159; dtu[255]:= 159
END Au.

Desktops.OpenDoc Au.Panel
