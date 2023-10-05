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

MODULE Graphics;	(** portable *)   (*NW 21.12.89 / 3.2.92 / JG 14.6.94 ported to System 3 / EOS 12.5.95 release 2.0*)
	IMPORT Files, Modules, Display, Fonts, Printer, Texts, Oberon;

	CONST NameLen* = 16; GraphFileId = 0F9X; LibFileId = 0FDX;

	TYPE
		Graph* = POINTER TO GraphDesc;
		Object* = POINTER TO ObjectDesc;
		Method* = POINTER TO MethodDesc;

		Line* = POINTER TO LineDesc;
		Caption* = POINTER TO CaptionDesc;
		Macro* = POINTER TO MacroDesc;

		ObjectDesc* = RECORD
				x*, y*, w*, h*, col*: INTEGER;
				selected*, marked*: BOOLEAN;
				do*: Method;
				next: Object
			END ;

		Msg* = RECORD END ;
		WidMsg* = RECORD (Msg) w*: INTEGER END ;
		ColorMsg* = RECORD (Msg) col*: INTEGER END ;
		FontMsg* = RECORD (Msg) fnt*: Fonts.Font END ;
		Name* = ARRAY NameLen OF CHAR;

		GraphDesc* = RECORD
				time*: LONGINT;
				sel*, first: Object
			END ;

		MacHead* = POINTER TO MacHeadDesc;
		MacExt* = POINTER TO MacExtDesc;
		Library* = POINTER TO LibraryDesc;

		MacHeadDesc* = RECORD
				name*: Name;
				w*, h*: INTEGER;
				ext*: MacExt;
				lib*: Library;
				first: Object;
				next: MacHead
			END ;

		LibraryDesc* = RECORD
				name*: Name;
				first: MacHead;
				next: Library
			END ;

		MacExtDesc* = RECORD END ;

		Context* = RECORD
				nofonts, noflibs, nofclasses: INTEGER;
				font: ARRAY 10 OF Fonts.Font;
				lib: ARRAY 4 OF Library;
				class: ARRAY 10 OF Modules.Command
			END;

		MethodDesc* = RECORD
				module*, allocator*: Name;
				new*: Modules.Command;
				copy*: PROCEDURE (from, to: Object);
				draw*, handle*: PROCEDURE (obj: Object; VAR msg: Msg);
				selectable*: PROCEDURE (obj: Object; x, y: INTEGER): BOOLEAN;
				read*: PROCEDURE (obj: Object; VAR R: Files.Rider; VAR C: Context);
				write*: PROCEDURE (obj: Object; cno: SHORTINT; VAR R: Files.Rider; VAR C: Context);
				print*: PROCEDURE (obj: Object; x, y: INTEGER)
			END ;

		LineDesc* = RECORD (ObjectDesc)
			END ;

		CaptionDesc* = RECORD (ObjectDesc)
				pos*, len*: INTEGER
			END ;

		MacroDesc* = RECORD (ObjectDesc)
				mac*: MacHead
			END ;

	VAR new*: Object;
		width*, res*: INTEGER;
		T*: Texts.Text;  (*captions*)
		LineMethod*, CapMethod*, MacMethod* : Method;
		scale*: INTEGER;

		FirstLib: Library;
		W, TW: Texts.Writer;

	PROCEDURE Add*(G: Graph; obj: Object);
	BEGIN obj.marked := FALSE; obj.selected := TRUE; obj.next := G.first;
		G.first := obj; G.sel := obj; G.time := Oberon.Time()
	END Add;

	PROCEDURE Draw*(G: Graph; VAR M: Msg);
		VAR obj: Object;
	BEGIN obj := G.first;
		WHILE obj # NIL DO obj.do.draw(obj, M); obj := obj.next END
	END Draw;

	PROCEDURE ThisObj*(G: Graph; x, y: INTEGER): Object;
		VAR obj: Object;
	BEGIN obj := G.first;
		WHILE (obj # NIL) & ~obj.do.selectable(obj, x ,y) DO obj := obj.next END ;
		RETURN obj
	END ThisObj;

	PROCEDURE SelectObj*(G: Graph; obj: Object);
	BEGIN
		IF obj # NIL THEN obj.selected := TRUE; G.sel := obj; G.time := Oberon.Time() END
	END SelectObj;

	PROCEDURE SelectArea*(G: Graph; x0, y0, x1, y1: INTEGER);
		VAR obj: Object; t: INTEGER;
	BEGIN obj := G.first;
		IF x1 < x0 THEN t := x0; x0 := x1; x1 := t END ;
		IF y1 < y0 THEN t := y0; y0 := y1; y1 := t END ;
		WHILE obj # NIL DO
			IF (x0 <= obj.x) & (obj.x + obj.w <= x1) & (y0 <= obj.y) & (obj.y + obj.h <= y1) THEN
				obj.selected := TRUE; G.sel := obj
			END ;
			obj := obj.next
		END ;
		IF G.sel # NIL THEN G.time := Oberon.Time() END
	END SelectArea;

	PROCEDURE Enumerate*(G: Graph; handle: PROCEDURE (obj: Object; VAR done: BOOLEAN));
		VAR obj: Object; done: BOOLEAN;
	BEGIN done := FALSE; obj := G.first;
		WHILE (obj # NIL) & ~done DO handle(obj, done); obj := obj.next END
	END Enumerate;

	(*----------------procedures operating on selection -------------------*)

	PROCEDURE Deselect*(G: Graph);
		VAR obj: Object;
	BEGIN obj := G.first; G.sel := NIL; G.time := 0;
		WHILE obj # NIL DO obj.selected := FALSE; obj := obj.next END
	END Deselect;

	PROCEDURE DrawSel*(G: Graph; VAR M: Msg);
		VAR obj: Object;
	BEGIN obj := G.first;
		WHILE obj # NIL DO
			IF obj.selected THEN obj.do.draw(obj, M) END ;
			obj := obj.next
		END
	END DrawSel;

	PROCEDURE Handle*(G: Graph; VAR M: Msg);
		VAR obj: Object;
	BEGIN obj := G.first;
		WHILE obj # NIL DO
			IF obj.selected THEN obj.do.handle(obj, M) END ;
			obj := obj.next
		END
	END Handle;

	PROCEDURE Move*(G: Graph; dx, dy: INTEGER);
		VAR obj, ob0: Object; x0, x1, y0, y1: INTEGER;
	BEGIN obj := G.first;
		WHILE obj # NIL DO
			IF obj.selected & ~(obj IS Caption) THEN
				x0 := obj.x; x1 := obj.w + x0; y0 := obj.y; y1 := obj.h + y0;
				IF dx = 0 THEN (*vertical move*)
					ob0 := G.first;
					WHILE ob0 # NIL DO
						IF ~ob0.selected & (ob0 IS Line) & (x0 <= ob0.x) & (ob0.x <= x1) & (ob0.w < ob0.h) THEN
							IF (y0 <= ob0.y) & (ob0.y <= y1) THEN
								INC(ob0.y, dy); DEC(ob0.h, dy); ob0.marked := TRUE
							ELSIF (y0 <= ob0.y + ob0.h) & (ob0.y + ob0.h <= y1) THEN
								INC(ob0.h, dy); ob0.marked := TRUE
							END
						END ;
						ob0 := ob0.next
					END
				ELSIF dy = 0 THEN (*horizontal move*)
					ob0 := G.first;
					WHILE ob0 # NIL DO
						IF ~ob0.selected & (ob0 IS Line) & (y0 <= ob0.y) & (ob0.y <= y1) & (ob0.h < ob0.w) THEN
							IF (x0 <= ob0.x) & (ob0.x <= x1) THEN
								INC(ob0.x, dx); DEC(ob0.w, dx); ob0.marked := TRUE
							ELSIF (x0 <= ob0.x + ob0.w) & (ob0.x + ob0.w <= x1) THEN
								INC(ob0.w, dx); ob0.marked := TRUE
							END
						END ;
						ob0 := ob0.next
					END
				END
			END ;
			obj := obj.next
		END ;
		obj := G.first; (*now move*)
		WHILE obj # NIL DO
			IF obj.selected THEN INC(obj.x, dx); INC(obj.y, dy) END ;
			obj.marked := FALSE; obj := obj.next
		END
	END Move;

	PROCEDURE Copy*(Gs, Gd: Graph; dx, dy: INTEGER);
		VAR obj: Object;
	BEGIN obj := Gs.first;
		WHILE obj # NIL DO
			IF obj.selected THEN
				obj.do.new; obj.do.copy(obj, new); INC(new.x, dx); INC(new.y, dy);
				obj.selected := FALSE; Add(Gd, new)
			END ;
			obj := obj.next
		END ;
		new := NIL
	END Copy;

	PROCEDURE Delete*(G: Graph);
		VAR obj, pred: Object;
	BEGIN G.sel := NIL; obj := G.first;
		WHILE (obj # NIL) & obj.selected DO obj := obj.next END ;
		G.first := obj;
		IF obj # NIL THEN
			pred := obj; obj := obj.next;
			WHILE obj # NIL DO
				IF obj.selected THEN pred.next := obj.next ELSE pred := obj END ;
				obj := obj.next
			END
		END
	END Delete;

	(* ---------------------- Storing ----------------------- *)

	PROCEDURE WMsg(s0, s1: ARRAY OF CHAR);
	BEGIN Texts.WriteString(W, s0); Texts.WriteString(W, s1);
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END WMsg;

	PROCEDURE InitContext(VAR C: Context);
	BEGIN C.nofonts := 0; C.noflibs := 0; C.nofclasses := 4;
		C.class[1] := LineMethod.new; C.class[2] := CapMethod.new; C.class[3] := MacMethod.new
	END InitContext;

	PROCEDURE FontNo*(VAR W: Files.Rider; VAR C: Context; fnt: Fonts.Font): SHORTINT;
		VAR fno: SHORTINT;
	BEGIN fno := 0;
		WHILE (fno < C.nofonts) & (C.font[fno] # fnt) DO INC(fno) END ;
		IF fno = C.nofonts THEN
			Files.Write(W, 0); Files.Write(W, 0); Files.Write(W, fno);
			Files.WriteString(W, fnt.name); C.font[fno] := fnt; INC(C.nofonts)
		END ;
		RETURN fno
	END FontNo;

	PROCEDURE StoreElems(VAR W: Files.Rider; VAR C: Context; obj: Object);
		VAR cno: INTEGER;
	BEGIN
		WHILE obj # NIL DO
			cno := 1;
			WHILE (cno < C.nofclasses) & (obj.do.new # C.class[cno]) DO INC(cno) END ;
			IF cno = C.nofclasses THEN
				Files.Write(W, 0); Files.Write(W, 2); Files.Write(W, SHORT(cno));
				Files.WriteString(W, obj.do.module); Files.WriteString(W, obj.do.allocator);
				C.class[cno] := obj.do.new; INC(C.nofclasses)
			END ;
			obj.do.write(obj, SHORT(cno), W, C); obj := obj.next
		END ;
		Files.Write(W, -1)
	END StoreElems;

	PROCEDURE Store*(G: Graph; VAR W: Files.Rider);
		VAR C: Context;
	BEGIN InitContext(C); StoreElems(W, C, G.first)
	END Store;

	PROCEDURE WriteObj*(VAR W: Files.Rider; cno: SHORTINT; obj: Object);
	BEGIN Files.Write(W, cno); Files.WriteInt(W, obj.x); Files.WriteInt(W, obj.y);
		Files.WriteInt(W, obj.w); Files.WriteInt(W, obj.h); Files.WriteInt(W, obj.col)
	END WriteObj;

	PROCEDURE WriteFile*(G: Graph; name: ARRAY OF CHAR);
		VAR F: Files.File; W: Files.Rider; C: Context;
	BEGIN F := Files.New(name); Files.Set(W, F, 0); Files.Write(W, GraphFileId);
		InitContext(C); StoreElems(W, C, G.first); Files.Register(F)
	END WriteFile;

	PROCEDURE Print*(G: Graph; x0, y0: INTEGER);
		VAR obj: Object;
	BEGIN obj := G.first;
		WHILE obj # NIL DO obj.do.print(obj, x0, y0); obj := obj.next END
	END Print;

	(* ---------------------- Loading ------------------------ *)

	PROCEDURE ThisClass*(VAR module, allocator: ARRAY OF CHAR): Modules.Command;
		VAR mod: Modules.Module; com: Modules.Command;
	BEGIN mod := Modules.ThisMod(module);
		IF mod # NIL THEN
			com := Modules.ThisCommand(mod, allocator);
			IF com = NIL THEN WMsg(allocator, " unknown") END
		ELSE WMsg(module, " not available"); com := NIL
		END ;
		RETURN com
	END ThisClass;

	PROCEDURE Font*(VAR R: Files.Rider; VAR C: Context): Fonts.Font;
		VAR fno: SHORTINT;
	BEGIN Files.Read(R, fno); RETURN C.font[fno]
	END Font;

	PROCEDURE ReadObj(VAR R: Files.Rider; obj: Object);
	BEGIN Files.ReadInt(R, obj.x); Files.ReadInt(R, obj.y);
		Files.ReadInt(R, obj.w); Files.ReadInt(R, obj.h); Files.ReadInt(R, obj.col)
	END ReadObj;

	PROCEDURE^ ThisLib*(VAR name: ARRAY OF CHAR; replace: BOOLEAN): Library;

	PROCEDURE LoadElems(VAR R: Files.Rider; VAR C: Context; VAR obj: Object);
		VAR cno, k: SHORTINT; len: INTEGER;
			name, name1: ARRAY 32 OF CHAR;
			last: Object;
	BEGIN obj := NIL; last := NIL; Files.Read(R, cno);
		WHILE ~R.eof & (cno >= 0) DO
			IF cno = 0 THEN
				Files.Read(R, cno); Files.Read(R, k); Files.ReadString(R, name);
				IF cno = 0 THEN C.font[k] := Fonts.This(name)
				ELSIF cno = 1 THEN C.lib[k] := ThisLib(name, FALSE)
				ELSE Files.ReadString(R, name1); C.class[k] := ThisClass(name, name1)
				END
			ELSIF C.class[cno] # NIL THEN
				C.class[cno]; ReadObj(R, new);
				new.selected := FALSE; new.marked := FALSE; (* new.next := obj; obj := new; *)
				IF last = NIL THEN obj := new ELSE last.next := new END;
				last := new;
				new.do.read(new, R, C)
			ELSE Files.Set(R, Files.Base(R), Files.Pos(R) + 10);
				Files.ReadInt(R, len); Files.Set(R, Files.Base(R), Files.Pos(R) + len)
			END ;
			Files.Read(R, cno)
		END ;
		new := NIL;
		IF last # NIL THEN last.next := NIL END
	END LoadElems;

	PROCEDURE Load*(G: Graph; VAR R: Files.Rider);
		VAR C: Context;
	BEGIN G.sel := NIL; InitContext(C); LoadElems(R, C, G.first)
	END Load;

	PROCEDURE Open*(G: Graph; name: ARRAY OF CHAR);
		VAR tag: CHAR;
			F: Files.File; R: Files.Rider; C: Context;
	BEGIN G.first := NIL; G.sel := NIL; G.time := 0; F := Files.Old(name);
		IF F # NIL THEN
			Files.Set(R, F, 0); Files.Read(R, tag);
			IF tag = GraphFileId THEN InitContext(C); LoadElems(R, C, G.first); res := 0 ELSE res := 1 END
		ELSE res := 2
		END
	END Open;

	(* --------------------- Macros / Libraries ----------------------- *)

	PROCEDURE ThisLib*(VAR name: ARRAY OF CHAR; replace: BOOLEAN): Library;
		VAR i, j: INTEGER; ch: CHAR;
			L: Library; mh: MacHead; obj: Object;
			F: Files.File; R: Files.Rider; C: Context;
			Lname, Fname: ARRAY 32 OF CHAR;
	BEGIN L := FirstLib; i := 0;
		WHILE name[i] >= "0" DO Lname[i] := name[i]; INC(i) END ;
		Lname[i] := 0X;
		WHILE (L # NIL) & (L.name # Lname) DO L := L.next END ;
		IF (L = NIL) OR replace THEN
			(*load library*) j := 0;
			WHILE name[j] > 0X DO Fname[j] := name[j]; INC(j) END ;
			IF i = j THEN
				Fname[j] := "."; Fname[j+1] := "L"; Fname[j+2] := "i"; Fname[j+3] := "b"; INC(j, 4)
			END ;
			Fname[j] := 0X; F := Files.Old(Fname);
			IF F # NIL THEN
				WMsg("loading ", name); Files.Set(R, F, 0); Files.Read(R, ch);
				IF ch = LibFileId THEN
					IF L = NIL THEN
						NEW(L); COPY(Lname, L.name); L.next := FirstLib; FirstLib := L
					END ;
					L.first := NIL; InitContext(C); LoadElems(R, C, obj);
					WHILE obj # NIL DO
						NEW(mh); mh.first := obj;
						Files.ReadInt(R, mh.w); Files.ReadInt(R, mh.h); Files.ReadString(R, mh.name);
						mh.lib := L; mh.next := L.first; L.first := mh; LoadElems(R, C, obj)
					END
				ELSE L := NIL; WMsg(name, " bad library")
				END
			ELSE WMsg(name, " not found")
			END
		END ;
		RETURN L
	END ThisLib;

	PROCEDURE NewLib*(VAR Lname: ARRAY OF CHAR): Library;
		VAR L: Library;
	BEGIN NEW(L); COPY(Lname, L.name); L.first := NIL;
		L.next := FirstLib; FirstLib := L; RETURN L
	END NewLib;

	PROCEDURE StoreLib*(L: Library; VAR Fname: ARRAY OF CHAR);
		VAR mh: MacHead;
			F: Files.File; W: Files.Rider;
			C: Context;
	BEGIN F := Files.New(Fname); Files.Set(W, F, 0); Files.Write(W, LibFileId);
		InitContext(C); mh := L.first;
		WHILE mh # NIL DO
			StoreElems(W, C, mh.first); Files.WriteInt(W, mh.w); Files.WriteInt(W, mh.h);
			Files.WriteString(W, mh.name); mh := mh.next
		END ;
		Files.Register(F)
	END StoreLib;

	PROCEDURE RemoveLibraries*;
	BEGIN FirstLib := NIL
	END RemoveLibraries;

	PROCEDURE ThisMac*(L: Library; VAR Mname: ARRAY OF CHAR): MacHead;
		VAR mh: MacHead;
	BEGIN mh := L.first;
		WHILE (mh # NIL) & (mh.name # Mname) DO mh := mh.next END ;
		RETURN mh
	END ThisMac;

	PROCEDURE OpenMac*(mh: MacHead; G: Graph; x, y: INTEGER);
		VAR obj: Object;
	BEGIN obj := mh.first;
		WHILE obj # NIL DO
			obj.do.new; obj.do.copy(obj, new); INC(new.x, x); INC(new.y, y); new.selected := TRUE;
			Add(G, new); obj := obj.next
		END ;
		new := NIL
	END OpenMac;

	PROCEDURE DrawMac*(mh: MacHead; VAR M: Msg);
		VAR elem: Object;
	BEGIN elem := mh.first;
		WHILE elem # NIL DO elem.do.draw(elem, M); elem := elem.next END
	END DrawMac;

	PROCEDURE MakeMac*(G: Graph; x, y, w, h: INTEGER; VAR Mname: ARRAY OF CHAR): MacHead;
		VAR obj, last: Object; mh: MacHead;
	BEGIN obj := G.first; last := NIL;
		WHILE obj # NIL DO
			IF obj.selected THEN
				obj.do.new; obj.do.copy(obj, new); new.next := last; new.selected := FALSE;
				DEC(new.x, x); DEC(new.y, y); last := new
			END ;
			obj := obj.next
		END ;
		NEW(mh); mh.w := w; mh.h := h; mh.first := last; mh.ext := NIL; COPY(Mname, mh.name);
		new := NIL; RETURN mh
	END MakeMac;

	PROCEDURE InsertMac*(mh: MacHead; L: Library; VAR new: BOOLEAN);
		VAR mh1: MacHead;
	BEGIN mh.lib := L; mh1 := L.first;
		WHILE (mh1 # NIL) & (mh1.name # mh.name) DO mh1 := mh1.next END ;
		IF mh1 = NIL THEN
			new := TRUE; mh.next := L.first; L.first := mh
		ELSE
			new := FALSE; mh1.w := mh.w; mh1.h := mh.h; mh1.first := mh.first
		END
	END InsertMac;

	(* ---------------------------- Line Methods -----------------------------*)

	PROCEDURE NewLine;
		VAR line: Line;
	BEGIN NEW(line); new := line; line.do := LineMethod
	END NewLine;

	PROCEDURE CopyLine(src, dst: Object);
	BEGIN dst.x := src.x; dst.y := src.y; dst.w := src.w; dst.h := src.h; dst.col := src.col
	END CopyLine;

	PROCEDURE HandleLine(obj: Object; VAR M: Msg);
	BEGIN
		IF M IS WidMsg THEN
			IF obj.w < obj.h THEN
				IF obj.w <= 7 THEN obj.w := M(WidMsg).w END
			ELSIF obj.h <= 7 THEN obj.h := M(WidMsg).w
			END
		ELSIF M IS ColorMsg THEN obj.col := M(ColorMsg).col
		END
	END HandleLine;

	PROCEDURE LineSelectable(obj: Object; x, y: INTEGER): BOOLEAN;
	BEGIN
		RETURN (obj.x <= x) & (x < obj.x + obj.w) & (obj.y <= y) & (y < obj.y + obj.h)
	END LineSelectable;

	PROCEDURE ReadLine(obj: Object; VAR R: Files.Rider; VAR C: Context);
	BEGIN
	END ReadLine;

	PROCEDURE WriteLine(obj: Object; cno: SHORTINT; VAR W: Files.Rider; VAR C: Context);
	BEGIN WriteObj(W, cno, obj)
	END WriteLine;

	PROCEDURE PrintLine(obj: Object; x, y: INTEGER);
		VAR w, h: INTEGER;
	BEGIN w := obj.w * scale DIV 2; h := obj.h * scale DIV 2;
		IF w < h THEN h := 2*h ELSE w := 2*w END;
		Printer.ReplConst(obj.x * scale + x, obj.y *scale + y, w, h)
	END PrintLine;

	(* ---------------------- Caption Methods ------------------------ *)

	PROCEDURE NewCaption;
		VAR cap: Caption;
	BEGIN NEW(cap); new := cap; cap.do := CapMethod
	END NewCaption;

	PROCEDURE CopyCaption(src, dst: Object);
		VAR ch: CHAR; R: Texts.Reader;
	BEGIN
		WITH src: Caption DO
			WITH dst: Caption DO
				dst.x := src.x; dst.y := src.y; dst.w := src.w; dst.h := src.h; dst.col := src.col;
				dst.pos := SHORT(T.len + 1); dst.len := src.len;
				Texts.Write(TW, 0DX); Texts.OpenReader(R, T, src.pos);
				Texts.Read(R, ch); TW.lib := R.lib;
				WHILE ch > 0DX DO Texts.Write(TW, ch); Texts.Read(R, ch) END
			END
		END ;
		Texts.Append(T, TW.buf)
	END CopyCaption;

	PROCEDURE HandleCaption(obj: Object; VAR M: Msg);
		VAR dx, x1, dy, y1, w, w1, h1, len: INTEGER;
			pos: LONGINT;
			ch: CHAR; pat: Display.Pattern; fnt: Fonts.Font;
			R: Texts.Reader;
	BEGIN
		IF M IS FontMsg THEN
			fnt := M(FontMsg).fnt; w := 0; len := 0; pos := obj(Caption).pos;
			Texts.OpenReader(R, T, pos); Texts.Read(R, ch); dy := R.lib(Fonts.Font).minY;
			WHILE ch > 0DX DO
				Fonts.GetChar(fnt, ch, dx, x1, y1, w1, h1, pat);
				INC(w, dx); INC(len); Texts.Read(R, ch)
			END ;
			INC(obj.y, fnt.minY-dy); obj.w := w; obj.h := fnt.height;
			Texts.ChangeLooks(T, pos, pos+len, {0}, fnt, 0 , 0)
		ELSIF M IS ColorMsg THEN obj.col := M(ColorMsg).col
		END
	END HandleCaption;

	PROCEDURE CaptionSelectable(obj: Object; x, y: INTEGER): BOOLEAN;
	BEGIN
		RETURN (obj.x <= x) & (x < obj.x + obj.w) & (obj.y <= y) & (y < obj.y + obj.h)
	END CaptionSelectable;

	PROCEDURE ReadCaption(obj: Object; VAR R: Files.Rider; VAR C: Context);
		VAR ch: CHAR; fno: SHORTINT; len: INTEGER;
	BEGIN obj(Caption).pos := SHORT(T.len + 1); Texts.Write(TW, 0DX);
		Files.Read(R, fno); TW.lib := C.font[fno]; len := 0; Files.Read(R, ch);
		WHILE ch > 0DX DO Texts.Write(TW, ch); INC(len); Files.Read(R, ch) END ;
		obj(Caption).len := len; Texts.Append(T, TW.buf)
	END ReadCaption;

	PROCEDURE WriteCaption(obj: Object; cno: SHORTINT; VAR W: Files.Rider; VAR C: Context);
		VAR ch: CHAR; fno: SHORTINT;
			TR: Texts.Reader;
	BEGIN
		IF obj(Caption).len > 0 THEN
			Texts.OpenReader(TR, T, obj(Caption).pos); Texts.Read(TR, ch);
			fno := FontNo(W, C, TR.lib(Fonts.Font));
			WriteObj(W, cno, obj); Files.Write(W, fno);
			WHILE ch > 0DX DO  Files.Write(W, ch); Texts.Read(TR, ch) END ;
			Files.Write(W, 0X)
		END
	END WriteCaption;

	PROCEDURE PrintCaption(obj: Object; x, y: INTEGER);
		VAR fnt: Fonts.Font;
			i: INTEGER; ch: CHAR;
			R: Texts.Reader;
			s: ARRAY 128 OF CHAR;
	BEGIN
		IF obj(Caption).len > 0 THEN
			Texts.OpenReader(R, T, obj(Caption).pos); Texts.Read(R, ch);
			fnt := R.lib(Fonts.Font); DEC(y, fnt.minY*scale); i := 0;
			WHILE ch >= " " DO s[i] := ch; INC(i); Texts.Read(R, ch) END ;
			s[i] := 0X;
			IF i > 0 THEN Printer.String(obj.x*scale + x, obj.y*scale + y, s, fnt) END
		END
	END PrintCaption;

	(* ---------------------- Macro Methods ------------------------ *)

	PROCEDURE NewMacro;
		VAR mac: Macro;
	BEGIN NEW(mac); new := mac; mac.do := MacMethod
	END NewMacro;

	PROCEDURE CopyMacro(src, dst: Object);
	BEGIN dst.x := src.x; dst.y := src.y; dst.w := src.w; dst.h := src.h;
		dst.col := src.col; dst(Macro).mac := src(Macro).mac
	END CopyMacro;

	PROCEDURE HandleMacro(obj: Object; VAR M: Msg);
	BEGIN
		IF M IS ColorMsg THEN obj.col := M(ColorMsg).col END
	END HandleMacro;

	PROCEDURE MacroSelectable(obj: Object; x, y: INTEGER): BOOLEAN;
	BEGIN
		RETURN (obj.x <= x) & (x <= obj.x + 8) & (obj.y <= y) & (y <= obj.y + 8)
	END MacroSelectable;

	PROCEDURE ReadMacro(obj: Object; VAR R: Files.Rider; VAR C: Context);
		VAR lno: SHORTINT; name: ARRAY 32 OF CHAR;
	BEGIN Files.Read(R, lno);
		Files.ReadString(R, name); obj(Macro).mac := ThisMac(C.lib[lno], name)
	END ReadMacro;

	PROCEDURE WriteMacro(obj: Object; cno: SHORTINT; VAR W1: Files.Rider; VAR C: Context);
		VAR lno: SHORTINT;
	BEGIN lno := 0;
		WITH obj: Macro DO
			WHILE (lno < C.noflibs) & (obj.mac.lib # C.lib[lno]) DO INC(lno) END ;
			IF lno = C.noflibs THEN
				Files.Write(W1, 0); Files.Write(W1, 1); Files.Write(W1, lno);
				Files.WriteString(W1, obj.mac.lib.name); C.lib[lno] := obj.mac.lib; INC(C.noflibs)
			END ;
			WriteObj(W1, cno, obj); Files.Write(W1, lno); Files.WriteString(W1, obj.mac.name)
		END
	END WriteMacro;

	PROCEDURE PrintMacro(obj: Object; x, y: INTEGER);
		VAR elem: Object; mh: MacHead;
	BEGIN mh := obj(Macro).mac;
		IF mh # NIL THEN elem := mh.first;
			WHILE elem # NIL DO elem.do.print(elem, obj.x*scale + x, obj.y*scale + y); elem := elem.next END
		END
	END PrintMacro;

BEGIN Texts.OpenWriter(W); Texts.OpenWriter(TW); width := 1;
	NEW(T); Texts.Open(T, "");
	NEW(LineMethod); LineMethod.new := NewLine; LineMethod.copy := CopyLine;
	LineMethod.selectable := LineSelectable; LineMethod.handle := HandleLine;
	LineMethod.read := ReadLine; LineMethod.write := WriteLine; LineMethod.print := PrintLine;
	NEW(CapMethod); CapMethod.new := NewCaption; CapMethod.copy := CopyCaption;
	CapMethod.selectable := CaptionSelectable; CapMethod.handle := HandleCaption;
	CapMethod.read := ReadCaption; CapMethod.write := WriteCaption; CapMethod.print := PrintCaption;
	NEW(MacMethod); MacMethod.new := NewMacro; MacMethod.copy := CopyMacro;
	MacMethod.selectable := MacroSelectable; MacMethod.handle := HandleMacro;
	MacMethod.read := ReadMacro; MacMethod.write := WriteMacro; MacMethod.print := PrintMacro;
	scale := SHORT((Display.Unit DIV Printer.Unit * 6 + 5) DIV 5)
END Graphics.

Compiler.Compile Graphics.Mod\s GraphicFrames.Mod\s 
	Rectangles.Mod\s Curves.Mod\s Splines.Mod\s Draw.Mod\s ~
System.Free Draw Splines Curves Rectangles GraphicFrames Graphics ~

Draw.Tool
Test.Graph
Draw.Print Printer@eamon *
