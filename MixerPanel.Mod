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

MODULE MixerPanel;	(** non-portable *)	(** tb, SS96 *)
IMPORT Objects, Sound, Gadgets, BasicGadgets, Documents, Desktops, Texts, Oberon, Out;

(**
MixerPanel-Module : Interface for MixerPanels
Author: Thomas Burri
Last Update:  
*)

CONST
	Done* = 0;
	Failed* = 1;

VAR
	d: Documents.Document;
	nofch, res: LONGINT;
	libname: ARRAY 64 OF CHAR;

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

(* Init : only once called from the modulestatementsequence; initialize 'libname' according to
the used mixer *)
PROCEDURE Init;
	VAR name: ARRAY 64 OF CHAR;
BEGIN
	nofch:= Sound.GetNofChannels();
	res:= Done;
	IF nofch = 15 THEN COPY("MixerSB16.", libname)
	ELSIF nofch = 10 THEN COPY("MixerSBPro.", libname)
	ELSIF nofch = 4 THEN COPY("MixerSB.", libname)
	ELSE Out.String("No mixer available on this soundcard !"); Out.Ln
	END;
	COPY(libname, name); Concat(name, "Lib");
	Objects.FreeLibrary(name)
END Init;

(* InitLib : will be called if any object in the appropriate library isn't found *)
PROCEDURE InitLib;
	VAR
		lib: Objects.Library;
		lobj, gobj1,gobj2, gobj3, gobj4, gobj5, gobj6: Objects.Object;
		objname: ARRAY 64 OF CHAR;
		c, sc: LONGINT;
		ch: Sound.Channel; subch: Sound.SubChannel;
		B: Objects.BindMsg; A: Objects.AttrMsg; L: Objects.LinkMsg;

	PROCEDURE InitObj;
		VAR
			val: LONGINT;
			lobj, gobj1, gobj2: Objects.Object;
			name: ARRAY 64 OF CHAR;
	BEGIN
		COPY(libname, name); Concat(name, objname);
		IF subch.maxval = 0 THEN
			lobj:= Gadgets.CreateObject("BasicGadgets.NewBoolean")
		ELSE
			lobj:= Gadgets.CreateObject("BasicGadgets.NewInteger")
		END;
		lobj.lib := NIL; lobj.ref := -1; B.lib := lib; lobj.handle(lobj, B);
		Objects.PutName(lib.dict, lobj.ref, objname);
		Gadgets.NameObj(lobj, objname);
		Sound.GetValue(subch.Ch, subch.SubCh, val);
		A.id:= Objects.set; A.name:= "Value";
		IF subch.maxval = 0 THEN A.class:= Objects.Bool; A.b:= val = 1
		ELSE A.class:= Objects.Int; A.i:= val
		END;
		lobj.handle(lobj, A);
		A.id:= Objects.set; A.name:= "Value";
		IF subch.maxval = 0 THEN A.class:= Objects.Bool; A.b:= (val = 1)
		ELSE A.class:= Objects.Int; A.i:= val
		END;
		gobj1:= Gadgets.FindObj(d.dsc, objname);
		IF gobj1 = NIL THEN Out.String("error mixerpanel: obj not found"); Out.Ln; HALT(99) END;
		gobj1.handle(gobj1, A);
		gobj2:= Gadgets.FindObj(Gadgets.context, objname);
		IF gobj2 = NIL THEN Out.String("error mixerpanel: obj not found"); Out.Ln; HALT(99) END;
		L.id:= Objects.set; L.name:= "Model"; L.obj:= lobj;
		gobj1.handle(gobj1, L); gobj2.handle(gobj2, L)
	END InitObj;

BEGIN
	res:= Done;
	nofch:= Sound.GetNofChannels();
	d:= NIL;
	IF nofch = 15 THEN d:= Documents.Open("MixerSB16.Panel"); COPY("MixerSB16.", libname)
	ELSIF nofch = 10 THEN d:= Documents.Open("MixerSBPro.Panel"); COPY("MixerSBPro.", libname)
	ELSIF nofch = 4 THEN d:= Documents.Open("MixerSB.Panel"); COPY("MixerSB.", libname)
	ELSE Out.String("No mixer available on this soundcard !"); Out.Ln
	END;
	IF d # NIL THEN
		COPY(libname, objname); Concat(objname, "Lib");
		lib:= Objects.ThisLibrary(objname);
		ch.Ch:= 0;
		WHILE ch.Ch < nofch DO
			Sound.GetChCapas(ch);
			subch.SubCh:= 0; subch.Ch:= ch.Ch;
			IF (nofch = 10)&(subch.Ch = 9) THEN
				lobj:= Gadgets.CreateObject("BasicGadgets.NewInteger");
				lobj.lib:= NIL; lobj.ref:= -1; B.lib:= lib; lobj.handle(lobj, B);
				Objects.PutName(lib.dict, lobj.ref, "Source");
				Gadgets.NameObj(lobj, "Source");
				A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.Int; A.i:= 0;
				lobj.handle(lobj, A);
				gobj1:= Gadgets.FindObj(d.dsc, "SourceMic");
				gobj2:= Gadgets.FindObj(Gadgets.context, "SourceMic");
				gobj3:= Gadgets.FindObj(Gadgets.context, "SourceCD");
				gobj4:= Gadgets.FindObj(d.dsc, "SourceCD");
				gobj5:= Gadgets.FindObj(d.dsc, "SourceLine");
				gobj6:= Gadgets.FindObj(Gadgets.context, "SourceLine");
				L.id:= Objects.set; L.name:= "Model"; L.obj:= lobj;
				gobj1.handle(gobj1, L); gobj2.handle(gobj2, L); gobj3.handle(gobj3, L);
				gobj4.handle(gobj4, L); gobj5.handle(gobj5, L); gobj6.handle(gobj6, L);
				A.id:= Objects.get; A.name:= "Value"; A.class:= Objects.Int;
				lobj.handle(lobj, A);
				IF A.res >= 0 THEN Sound.SetValue(subch.Ch, A.i, 0) END;
				Gadgets.Update(Gadgets.context)
			ELSE
				WHILE subch.SubCh < ch.nofSubCh DO
					Sound.GetSubChCapas(subch);
					COPY(ch.name, objname); Concat(objname, subch.name);
					InitObj;
					INC(subch.SubCh)
				END
			END;
			INC(ch.Ch)
		END;
		lib.Store(lib);
		d.Store(d)
	ELSE res:= Failed
	END
END InitLib;

(** Open : opens the mixerpanel, which belongs to the used soundcard; it is possible
to open the panels directly and they will be set to the values of the appropriate library *)
PROCEDURE Open*;
BEGIN
	res:= Done;
	d:= NIL;
	IF nofch = 15 THEN d:= Documents.Open("MixerSB16.Panel")
	ELSIF nofch = 10 THEN d:= Documents.Open("MixerSBPro.Panel")
	ELSIF nofch = 4 THEN d:= Documents.Open("MixerSB.Panel")
	ELSE Out.String("No mixer available on this soundcard !"); Out.Ln
	END;
	IF d # NIL THEN Desktops.ShowDoc(d)
	ELSE res:= Failed
	END;
END Open;

(** SetBox : changes the value of an checkbox in the library and sets the registerbit of the soudcard *)
PROCEDURE SetBox*;
	VAR
		S: Texts.Scanner;
		name: ARRAY 64 OF CHAR;
		lobj: Objects.Object;
		A: Objects.AttrMsg;
		ch: Sound.Channel; subch: Sound.SubChannel;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN
		subch.Ch:= S.i; ch.Ch:= S.i; Texts.Scan(S);
		IF S.class = Texts.Int THEN
			subch.SubCh:= S.i;
			Sound.GetChCapas(ch); Sound.GetSubChCapas(subch);
			COPY(libname, name); Concat(name, ch.name);
			IF (nofch#10) OR (subch.Ch # 9) THEN Concat(name, subch.name) END;
			lobj:= Gadgets.FindPublicObj(name);
			IF lobj = NIL THEN InitLib; lobj:= Gadgets.FindPublicObj(name) END;
			A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.Bool;
			Texts.Scan(S);
			IF S.class = Texts.Name THEN
				A.b:= TRUE;
				Sound.SetValue(subch.Ch, subch.SubCh, 1)
			ELSE
				A.b:= FALSE;
				Sound.SetValue(subch.Ch, subch.SubCh, 0)
			END;
			lobj.handle(lobj, A)
		END
	END
END SetBox;

(** LockVolume : left and right volume will be set to same value if called when button is pushed to red *)
PROCEDURE LockVolume*;
	VAR
		S: Texts.Scanner;
		ch: Sound.Channel;
		lobjleft, lobjright: Objects.Object;
		namel, namer: ARRAY 64 OF CHAR;
		val1, val2: LONGINT;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN
		ch.Ch:= S.i; Sound.GetChCapas(ch);
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			COPY(libname, namel); Concat(namel, ch.name); COPY(namel, namer);
			Concat(namel, "Left"); Concat(namer, "Right");
			lobjleft:= Gadgets.FindPublicObj(namel);
			IF lobjleft = NIL THEN InitLib; lobjleft:= Gadgets.FindPublicObj(namel) END;
			lobjright:= Gadgets.FindPublicObj(namer);
			IF lobjright = NIL THEN InitLib; lobjright:= Gadgets.FindPublicObj(namer) END;
			val1:= lobjleft(BasicGadgets.Integer).val;
			val2:= lobjright(BasicGadgets.Integer).val;
			IF val1 > val2 THEN
				lobjright(BasicGadgets.Integer).val:= val1;
				Gadgets.Update(lobjright);
				Sound.SetValue(ch.Ch, 1, val1)
			ELSIF val1 < val2 THEN
				lobjleft(BasicGadgets.Integer).val:= val2;
				Gadgets.Update(lobjleft);
				Sound.SetValue(ch.Ch, 0, val2)
			END
		END
	END
END LockVolume;

(** SetVolume : change volume of one channel; if it is a stereo channel and 'LR' is pushed, 
the partner channel will be set to same value *)
PROCEDURE SetVolume*;
	VAR
		S: Texts.Scanner;
		sc, val: LONGINT;
		lobj: Objects.Object;
		A: Objects.AttrMsg;
		name: ARRAY 64 OF CHAR;
		lock: BOOLEAN;
		ch: Sound.Channel; subch: Sound.SubChannel;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	IF S.class = Texts.Int THEN
		subch.Ch:= S.i; ch.Ch:= S.i; Texts.Scan(S);
		IF S.class = Texts.Int THEN
			subch.SubCh:= S.i; Texts.Scan(S);
			IF S.class = Texts.Int THEN
				val:= S.i; Texts.Scan(S);
				lock:= S.class = Texts.Name;
				sc:= subch.SubCh;
				Sound.GetChCapas(ch);
				IF lock THEN
					subch.SubCh:= 1-subch.SubCh;
					Sound.GetSubChCapas(subch);
					COPY(libname, name); Concat(name, ch.name); Concat(name, subch.name);
					lobj:= Gadgets.FindPublicObj(name);
					IF lobj = NIL THEN InitLib; lobj:= Gadgets.FindPublicObj(name) END;
					Sound.SetValue(subch.Ch, subch.SubCh, val);
					A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.Int; A.i:= val;
					lobj.handle(lobj, A);
					Gadgets.Update(lobj)
				END;
				subch.SubCh:= sc;
				Sound.GetSubChCapas(subch);
				COPY(libname, name); Concat(name, ch.name); Concat(name, subch.name);
				lobj:= Gadgets.FindPublicObj(name);
				IF lobj = NIL THEN InitLib; lobj:= Gadgets.FindPublicObj(name) END;
				Sound.SetValue(subch.Ch, subch.SubCh, val);
				A.id:= Objects.set; A.name:= "Value"; A.class:= Objects.Int; A.i:= val;
				lobj.handle(lobj, A);
				Gadgets.Update(lobj)
			END
		END
	END				
END SetVolume;

BEGIN
	Init
END MixerPanel.

(** Remarks:
	1. For the first time, you open the panel and change anything, the library to this
		panel will be generated, if it doesn't exists already.
 *) 

