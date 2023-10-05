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

MODULE Documents;	(** portable *) (** jm 18.1.95 *)

(** The Documents module forms the basis of the Gadgets document model.
*)
(*
	6.4.94 - VERY SPECIAL DOCUMENT WITH DSC HAVING THE SAME COORDINATES AS THE DOCUMENT
	Old version can be found in DocumentsOld.Mod.
	This important change allows the contents of the document to experience its change in coordinates, so
	that it can optimize updates occordingly. This feature is especially used in TextGadgets0.ModifyFrame
	
	6.4.94 - Introduced a default document type
	2.5.94 - Added copy over on selection
	2.5.94 - Added deep copy support
	30.5.94 - added handling of Documents.This load errors
	9.6.94 - default documents are open larger
	7.11.94 - removed lib from standard types
	3.1.95 - Documents.This renamed to Documents.Open
		- added check to ensure invariant from 6.4.94. I am not sure if this fix is correct or not, at least
		it allows text documents to flow inside a text
		- added "DocumentName" attribute
	4.12.95 - fixed name overflow in TitleToFilename
	15.12.95 - added historyHook
	7.3.96 - removed TitleToFilename
	30.12.96 - removed MapName
*)

IMPORT Texts, Objects, Display, Attributes, Links, Gadgets, Modules, Files, Display3, Effects, Oberon, Fonts, Strings, Out;
	
CONST
	MaxDocTypes = 48;

TYPE
	Document* = POINTER TO DocumentDesc;
	DocumentDesc* = RECORD (Gadgets.FrameDesc)
		name*: ARRAY 128 OF CHAR;	(** Document name. *)
		Load*: PROCEDURE (D: Document);	(** Load document contents from disk. *)
		Store*: PROCEDURE (D: Document);	(** Store document contents to disk. *)
		time: LONGINT;
	END;
	
	(** Find out what document is located at X, Y on the display. *)
	LocateMsg* = RECORD (Display.FrameMsg)
		doc*: Document;	(** Result, NIL if no document found. *)
		X*, Y*: INTEGER;
	END;
	
VAR
	Id*: INTEGER;	(** 07F7H little-endian magic number/flag identifying document files. *)
	historyHook*: PROCEDURE (VAR D: Document); (** Called for each document opened. *)
	reg: INTEGER;
	DocExt: ARRAY MaxDocTypes, 32 OF CHAR;
	DocNewProc: ARRAY MaxDocTypes, 64 OF CHAR;
	DocService: ARRAY MaxDocTypes OF BOOLEAN;

	errMsg*: ARRAY 256 OF CHAR;

(* ================ Loading/storing of Document Attachments ================= *)

(* The attachment format is as follows:

	tag document-header F7X 08X Len4 Attributes Library Links
	
	Len4 is the length from after Len4 to the end of Links.
*)

PROCEDURE LoadAttachments*(VAR R: Files.Rider; VAR attr: Attributes.Attr; VAR link: Links.Link);
VAR len: LONGINT; F: Files.File; ch: CHAR; lib: Objects.Library;
BEGIN
	F := Files.Base(R);
	Files.Read(R, ch); ASSERT(ch = 08X);
	Files.ReadLInt(R, len);
	Attributes.LoadAttributes(R, attr);
	NEW(lib); Objects.OpenLibrary(lib);
	Files.Read(R, ch); ASSERT(ch = Objects.LibBlockId);
	Objects.LoadLibrary(lib, F, Files.Pos(R), len);
	Files.Set(R, F, Files.Pos(R) + len);
	Links.LoadLinks(R, lib, link)
END LoadAttachments;

PROCEDURE StoreAttachments*(VAR R: Files.Rider; attr: Attributes.Attr; VAR link: Links.Link);
VAR r: Files.Rider; F: Files.File; patch, len: LONGINT; lib: Objects.Library; M: Objects.BindMsg;
BEGIN
	F := Files.Base(R);
	
	Files.Write(R, 0F7X); Files.Write(R, 08X);
	patch := Files.Pos(R);
	Files.WriteLInt(R, 0); (* patch *)
	Attributes.StoreAttributes(R, attr);
	NEW(lib); Objects.OpenLibrary(lib);
	M.lib := lib; Links.BindLinks(link, M);
	Objects.StoreLibrary(lib, F, Files.Pos(R), len);
	Files.Set(R, F, Files.Pos(R) + len);
	Links.StoreLinks(R, lib, link);
	len := Files.Pos(R) - patch - 4;
	Files.Set(r, F, patch);
	Files.WriteLInt(r, len);
END StoreAttachments;

(* How to skip attachments:

	PROCEDURE SkipAttachments(VAR R: Files.Rider);
	VAR F: Files.File; len: LONGINT;
	BEGIN
		F := Files.Base(R);
		Files.Read(R, ch); ASSERT(ch = 08X);
		Files.ReadLInt(R, len);
		Files.Set(R, F, Files.Pos(R) + len)
	END SkipAttachments;
	
*)
(* ================ Loading of Document types ================= *)

PROCEDURE SplitName (VAR name, MName, PName: ARRAY OF CHAR);
VAR i, j: INTEGER;
BEGIN i := 0;
	WHILE name[i] # "." DO MName[i] := name[i]; INC(i) END;
	MName[i] := 0X; INC(i); j := 0;
	WHILE name[i] # 0X DO PName[j] := name[i]; INC(i); INC(j) END;
	PName[j] := 0X
END SplitName;
	
(* Try to load generic document *)

PROCEDURE generic(name, newproc: ARRAY OF CHAR; VAR loaderror: BOOLEAN): Document;
	VAR
		D: Document;
		MName, PName: ARRAY 64 OF CHAR;
		Mod: Modules.Module; Cmd: Modules.Command;
BEGIN
	SplitName(newproc, MName, PName);
	Mod := Modules.ThisMod(MName);
	IF Modules.res = 0 THEN
		Cmd := Modules.ThisCommand(Mod, PName);
		IF Modules.res = 0 THEN Objects.NewObj := NIL; Cmd;
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Document) THEN
				D := Objects.NewObj(Document); COPY(name, D.name); D.Load(D)
			ELSE loaderror := TRUE
			END
		ELSE loaderror := TRUE
		END
	ELSE loaderror := TRUE
	END;
	RETURN D
END generic;

PROCEDURE Generic(name: ARRAY OF CHAR; VAR loaderror: BOOLEAN): Document;
VAR D: Document; newproc: ARRAY 64 OF CHAR;
	F: Files.File; R: Files.Rider; tag: INTEGER;
BEGIN
	D := NIL; loaderror := FALSE;
	F := Files.Old(name);
	IF F # NIL THEN
		Files.Set(R, F, 0);
		Files.ReadInt(R, tag);
		IF (tag = Id) OR (tag = 0727H) THEN
			Files.ReadString(R, newproc);
			D := generic(name, newproc, loaderror)
		END
	END;
	RETURN D
END Generic;

PROCEDURE Cap(ch: CHAR): CHAR;
BEGIN
	IF (ch >= "a") & (ch <= "z") THEN RETURN CAP(ch)
	ELSE RETURN ch
	END
END Cap;

(** Open the give document with name name. NIL is returned on failure. Unknown document types are opened as text documents. *)
PROCEDURE Open*(name: ARRAY OF CHAR): Document;
VAR i, j, colonpos: INTEGER; ext: ARRAY 64 OF CHAR; D: Document;
	loaderror: BOOLEAN;
BEGIN
	COPY(name, errMsg); Strings.AppendCh(errMsg, " ");
	D := Generic(name, loaderror);
	IF (D = NIL) & ~loaderror THEN (* not found *)
		i := 0; j := -1; colonpos := -1;
		WHILE name[i] # 0X DO (* find last period *)
			IF name[i] = "." THEN j := i
			ELSIF name[i] = ":" THEN
				IF colonpos = -1 THEN colonpos := i END;
			END;
			INC(i)
		END;
		IF colonpos > 1 THEN (* jm *)
			i := 0; j := 0;
			WHILE i < colonpos DO
				IF name[i] > " " THEN ext[j] := Cap(name[i]); INC(j) END;
				INC(i)
			END;
			ext[j] := 0X;
			i := 0; WHILE (i # reg) & (~DocService[i] OR (DocExt[i] # ext)) DO INC(i) END;
			IF i = reg THEN (* unknown type *)
				colonpos := -1	(* ignore colon and try with extension *)
			END
		END;
(*
			IF i = reg THEN (* unknown type *)
				Strings.Append(errMsg, ext); Strings.Append(errMsg, " unknown document service");
				RETURN NIL
			END
		ELSIF j >= 0 THEN
*)
		IF colonpos <= 1 THEN
			IF (j >= 0) THEN
				i := 0; INC(j); WHILE (name[j] # 0X) & (i # 31) DO ext[i] := Cap(name[j]); INC(i); INC(j) END; (* copy extension *)
				ext[i] := 0X; i := 0;
				WHILE (i # reg) & (DocService[i] OR (DocExt[i] # ext)) DO INC(i) END
			ELSE i := reg (* no period *)
			END
		END; 
		IF i = reg THEN (* nothing, use the default *) COPY("TextDocs.NewDoc", DocNewProc[i]) END;
		D := generic(name, DocNewProc[i], loaderror)
	END;
	Objects.NewObj := NIL; (* for GC *)
	IF (D # NIL) & (D.dsc # NIL) THEN
		IF historyHook # NIL THEN historyHook(D) END;
		RETURN D
	ELSE
		IF loaderror THEN
			Strings.Append(errMsg, Modules.resMsg)
		ELSE
			Strings.Append(errMsg, " loading document failed")
		END;
		RETURN NIL
	END
END Open;

PROCEDURE Register(ext, newproc: ARRAY OF CHAR; service: BOOLEAN);
VAR i: INTEGER;
BEGIN
	i := 0; WHILE ext[i] # 0X DO ext[i] := Cap(ext[i]); INC(i) END;
	i := 0;
	WHILE (i # reg) & ((ext # DocExt[i]) OR (service # DocService[i])) DO INC(i) END;
	IF i = reg THEN COPY(ext, DocExt[reg]); COPY(newproc, DocNewProc[reg]); DocService[reg] := service; INC(reg)
	ELSE COPY(newproc, DocNewProc[i]);
	END
END Register;

PROCEDURE RegisterStandardTypes(section: ARRAY OF CHAR;  service: BOOLEAN);
VAR S: Texts.Scanner; ext, newproc: ARRAY 32 OF CHAR;  err: BOOLEAN;
BEGIN
	Oberon.OpenScanner(S, section);
	IF S.class = Texts.Inval THEN
		Out.String("Oberon.Text - ");  Out.String(section);  Out.String(" not found");  Out.Ln
	ELSE
		err := FALSE;
		WHILE (S.class IN {Texts.Name, Texts.String}) & ~err DO
			COPY(S.s, ext);  Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "=") THEN
				Texts.Scan(S);
				IF S.class IN {Texts.Name, Texts.String} THEN
					COPY(S.s, newproc);  Texts.Scan(S);
					Register(ext, newproc, service)
				ELSE err := TRUE
				END
			ELSE err := TRUE
			END
		END;
		err := err OR (S.class # Texts.Char) OR (S.c # "}");
		IF err THEN
			Out.String("Error in ");  Out.String(section);  Out.Ln
		END
	END
END RegisterStandardTypes;

(* ===================== default handler for document frames ================ *)

PROCEDURE SetMask(F: Display.Frame; M: Display3.Mask);
VAR O: Display3.OverlapMsg;
BEGIN O.M := M; O.x := 0; O.y := 0; O.F := F; O.dlink := NIL; O.res := -1; F.handle(F, O);
END SetMask;

PROCEDURE SetMainMask(F: Document);
VAR R: Display3.Mask;
BEGIN
	IF F.dsc # NIL THEN
		IF F.mask = NIL THEN SetMask(F.dsc, NIL)
		ELSE
			Display3.Copy(F.mask, R); R.x := 0; R.y := 0;
			(*
			Display3.Intersect(R, F.dsc.X,  F.dsc.Y, F.dsc.W,  F.dsc.H);
			R.x := -F.dsc.X; R.y := -(F.dsc.Y + F.dsc.H - 1); Display3.Shift(R);
			*)
			SetMask(F.dsc, R)
		END
	END
END SetMainMask;

PROCEDURE ToMain(F: Document; ox, oy: INTEGER; VAR M: Display.FrameMsg);
VAR Mdlink, Fdlink: Objects.Object; tx, ty: INTEGER;
BEGIN
	IF F.dsc # NIL THEN
		tx := M.x; ty := M.y; M.x := ox; M.y := oy;
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F; F.dsc.handle(F.dsc, M);
		F.dlink := Fdlink; M.dlink := Mdlink;
		M.x := tx; M.y := ty
	END
END ToMain;

PROCEDURE Absolute(dlink: Objects.Object): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	IF (dlink # NIL) & (dlink.handle # NIL) THEN (* NIL test because of Script *)
		A.id := Objects.get; A.name := "Absolute"; A.res := -1; dlink.handle(dlink, A);
		RETURN (A.res >= 0) & (A.class = Objects.Bool) & A.b
	ELSE RETURN FALSE
	END
END Absolute;

(* new *)
PROCEDURE AdjustDocument(F: Document; VAR M: Display.ModifyMsg);
VAR A: Display.ModifyMsg; old, x, y, w, h: INTEGER; R: Display3.Mask;
BEGIN
	IF Absolute(M.dlink) (*TRUE (* 31 IN F.state *) *) THEN (* in viewer system, may optimize *)
		old := M.mode; M.mode := Display.state; Gadgets.framehandle(F, M); M.mode := old;
	
		IF F.dsc # NIL THEN
			(* Adjust main *)
			A.id := Display.extend; A.F := F.dsc; A.mode := M.mode;
			A.X := M.X; A.Y := M.Y; A.W := M.W; A.H := M.H;
			A.dX := M.dX; A.dY := M.dY; A.dW := M.dW; A.dH := M.dH;
			A.dlink := M.dlink;
			A.res := -1; Objects.Stamp(A);
			ToMain(F, M.x, M.y, A);
			IF (Gadgets.selected IN F.state) & (M.mode = Display.display) THEN
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
				Gadgets.MakeMask(F, x, y, M.dlink, R);
				Display3.FillPattern(R, Display3.blue, Display3.selectpat, 0, 0, x, y, w, h, Display.paint);
			END;
		END
	ELSE (* unoptimized *)
		IF (F.dsc # NIL) & (M.stamp # F.stamp) THEN F.stamp := M.stamp;
			(* Adjust main *)
			A.id := Display.extend; A.F := F.dsc; A.mode := Display.state;
			A.X := M.X; A.Y := M.Y; A.W := M.W; A.H := M.H;
			A.dX := M.dX; A.dY := M.dY; A.dW := M.dW; A.dH := M.dH;
			A.dlink := M.dlink;
			A.res := -1; Objects.Stamp(A);
			ToMain(F, M.x, M.y, A)
		END;
		Gadgets.framehandle(F, M)
	END
END AdjustDocument;

(* -- docviewer main frame changed; have to adjust docviewer size *)
PROCEDURE AdjustChildDocument(F: Document; VAR M: Display.ModifyMsg);
VAR A: Display.ModifyMsg;
BEGIN
	IF M.stamp # F.stamp THEN F.stamp := M.stamp;
		A.id := Display.extend; A.F := F; A.mode := Display.display;
		A.X := M.X; A.Y := M.Y; A.W := M.W; A.H := M.H;
		A.dX := M.dX; A.dY := M.dY; A.dW := M.dW; A.dH := M.dH;
		Display.Broadcast(A)
	END
END AdjustChildDocument;

PROCEDURE check(F: Document);
BEGIN
	IF F.dsc # NIL THEN
		IF (F.X # F.dsc.X) OR (F.Y # F.dsc.Y) OR (F.W # F.dsc.W) OR (F.H # F.dsc.H) THEN
			F.dsc.X := F.X; F.dsc.Y := F.Y; F.dsc.W := F.W; F.dsc.H := F.H;
		END
	END
END check;

PROCEDURE RestoreDocument(F: Document; R: Display3.Mask; ox, oy, x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR D: Display.DisplayMsg;

	PROCEDURE ClipAgainst(VAR x, y, w, h: INTEGER; x1, y1, w1, h1: INTEGER);
	VAR r, t, r1, t1: INTEGER;
	BEGIN
		r := x + w - 1; r1 := x1 + w1 - 1; t := y + h - 1; t1 := y1 + h1 - 1;
		IF x < x1 THEN x := x1 END;
		IF y < y1 THEN y := y1 END;
		IF r > r1 THEN r := r1 END;
		IF t > t1 THEN t := t1 END;
		w := r - x + 1; h := t - y + 1;
	END ClipAgainst;
	
BEGIN check(F);
	Oberon.RemoveMarks(x, y, w, h);
	IF M.id = Display.area THEN
		IF F.dsc # NIL THEN
			(* display main frame *)
			D.device := Display.screen; D.id := Display.area; D.F := F.dsc; D.u := M.u;
			D.v :=  M.v; D.w := M.w; D.h := M.h;
			ClipAgainst(D.u, D.v, D.w, D.h, 0, -F.dsc.H +1, F.dsc.W, F.dsc.H);
			D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMain(F, ox, oy, D);
		ELSE
			Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x, y, w, h, 1, Display.replace);
			Display3.String(R, Display3.FG,  x + 5, y + h - 20, Fonts.Default, "Document not found", Display.paint);
		END;
	ELSE
		IF F.dsc # NIL THEN
			D.device := Display.screen; D.id := Display.full; D.F := F.dsc; D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMain(F, ox, oy, D)
		ELSE
			Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x, y, w, h, 1, Display.replace);
			Display3.String(R, Display3.FG,  x + 5, y + h -  20, Fonts.Default, "Document not found", Display.paint);
		END;
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.blue, Display3.selectpat, 0, 0, x, y, w, h, Display.paint);
	END
END RestoreDocument;

PROCEDURE Copy*(VAR M: Objects.CopyMsg; from, to: Document);
VAR C: Objects.CopyMsg;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	
	IF from.dsc # NIL THEN
		C.id := M.id; Objects.Stamp(C); from.dsc.handle(from.dsc, C);
		to.dsc := C.obj(Gadgets.Frame)
	ELSE to.dsc := NIL
	END;
	
	to.Load := from.Load;
	to.Store := from.Store;
	COPY(from.name, to.name);
END Copy;

PROCEDURE DocumentAttr(F: Document; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN HALT(99)
		ELSIF M.name = "DocumentName" THEN
			M.class := Objects.String; COPY(F.name, M.s); M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "DocumentName" THEN
			IF M.class = Objects.String THEN COPY(M.s, F.name); M.res := 0 END;
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("DocumentName"); Gadgets.framehandle(F, M)
	END
END DocumentAttr;

PROCEDURE Neutralize(F: Document);
VAR main: Gadgets.Frame; S: Display.SelectMsg;
BEGIN
	IF F.dsc # NIL THEN
		main := F.dsc(Gadgets.Frame);
		IF Gadgets.selected IN main.state THEN
			S.F := main; S.res := -1; S.x := 0; S.y := 0;
			S.id := Display.reset; F.time := 0;
			ToMain(F, 0, 0, S);
			Gadgets.Update(main)
		END
	END
END Neutralize;

PROCEDURE HandleSelect(F: Document; VAR M: Oberon.InputMsg);
VAR main: Gadgets.Frame; S: Display.SelectMsg; N: Oberon.ControlMsg; keysum: SET; C: Objects.CopyMsg;
BEGIN
	IF F.dsc = NIL THEN RETURN END;
	main := F.dsc(Gadgets.Frame);
	S.F := main; S.res := -1; S.x := 0; S.y := 0;
	IF Gadgets.selected IN main.state THEN (* do nothing if already selected *)
		(* S.id := Display.reset; F.time := 0; *) 
	ELSE
		N.id := Oberon.neutralize; N.F := NIL; N.res := -1; ToMain(F, 0, 0, N);

		S.id := Display.set; F.time := Oberon.Time();
		ToMain(F, M.x, M.y, S);
		Gadgets.Update(main); keysum := M.keys;
		REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {};
		M.res := 0;
		IF keysum = {0, 2} THEN (* RL delete selection *)
			(* nothing *)
		ELSIF keysum = {0, 1} THEN  (* RM copy to focus *)
			C.id := Objects.shallow; C.obj := NIL; Objects.Stamp(C); F.dsc.handle(F.dsc, C);
			IF C.obj # NIL THEN
				(*
				C.obj(Gadgets.Frame).state := C.obj(Gadgets.Frame).state - {Gadgets.noselect, Gadgets.nodelete, Gadgets.noresize, Gadgets.nomove};
				*)
				Gadgets.Integrate(C.obj)
			END
		END
	END;
END HandleSelect;

PROCEDURE Handler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: Document; R: Display3.Mask;
	N: Oberon.ControlMsg; tmp: SET; tM: Display.DisplayMsg;
	obj: Objects.Object;
BEGIN
	WITH F: Document DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreDocument(F, R, M.x, M.y, x, y, w, h, M)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreDocument(F, R, M.x, M.y, x, y, w, h, M)
								END
							ELSIF M.device = Display.printer THEN ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) THEN
								IF ~Gadgets.InActiveArea(F, M) THEN
									IF M.keys = {0} THEN HandleSelect(F, M) 
									ELSE Gadgets.framehandle(F, M)
									END
								ELSE
									ToMain(F, M.x, M.y, M);
									IF (M.res < 0) & (M.keys = {0}) THEN HandleSelect(F, M) END;
									IF (M.res < 0) & ~Gadgets.InActiveArea(F, M) THEN Gadgets.framehandle(F, M) END
								END
							ELSIF ~(Gadgets.selected IN F.state) THEN ToMain(F, M.x, M.y, M)
							ELSE  Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						IF M.F = F THEN AdjustDocument(F, M(Display.ModifyMsg));
						ELSE Gadgets.framehandle(F, M)
						END
					ELSIF M IS LocateMsg THEN
						WITH M: LocateMsg DO
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							IF Effects.Inside(M.X, M.Y, x, y, w, h) & Display3.Visible(R, M.X, M.Y, 1, 1) THEN
								M.doc := F;
								ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								ToMain(F, M.x, M.y, M);
								IF M.loc = NIL THEN M.loc := F; M.u := M.X - x; M.v := M.Y - (y + h - 1); M.res := 0 END;
							END
						END
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF M.id = Display.set THEN
								Neutralize(F);
								N.id := Oberon.neutralize; N.F := NIL; N.res := -1; ToMain(F, M.x, M.y, N)
							ELSIF M.id = Display.reset THEN
							ELSIF M.id = Display.get THEN
								IF (F.time > M.time) & (Gadgets.selected IN F.dsc(Gadgets.Frame).state) THEN
									M.time := F.time; M.sel := F; M.obj := F.dsc
								END
							END;
							IF M.F # NIL THEN Gadgets.framehandle(F, M) 
							ELSE ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							ToMain(F, M.x, M.y, M);
							IF M.id = Oberon.neutralize THEN Neutralize(F) END
						END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
							SetMainMask(F);
							M.res := 0;
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO
							F.mask := M.M; SetMainMask(F);
						END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF F.mask = NIL THEN Gadgets.MakeMask(F, x, y, M.dlink, R) END;
							SetMainMask(F)
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = F.dsc THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								tM.device := Display.screen; tM.id := Display.full; tM.dlink := M.dlink;
								RestoreDocument(F, R, M.x, M.y, x, y, w, h, tM);
								IF Gadgets.lockedsize IN F.dsc(Gadgets.Frame).state THEN INCL(F.state, Gadgets.lockedsize)
								ELSE EXCL(F.state, Gadgets.lockedsize)
								END
							ELSE ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M.F # NIL THEN Gadgets.framehandle(F, M) 
					ELSE ToMain(F, M.x, M.y, M)
					END
				ELSE (* not for this frame but perhaps for a child *)	
					IF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF M.F = F.dsc THEN
								IF F.mask = NIL THEN Gadgets.MakeMask(F, M.x + F.X, M.y + F.Y, M.dlink, R) END;
								SetMainMask(F)
							ELSE ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF FALSE & ~(30 IN F.state) & (M.obj IS Document) THEN (* prevent consumption *)
							ELSE ToMain(F, M.x, M.y, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						IF M.F = F.dsc THEN AdjustChildDocument(F, M(Display.ModifyMsg))
						ELSE ToMain(F, M.x, M.y, M)
						END
					ELSE ToMain(F, M.x, M.y, M)
					END
				END
			END
			
		(* Object messages *)
		ELSIF M IS Objects.AttrMsg THEN DocumentAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "Model") THEN
					M.obj := F.dsc; M.res := 0
				ELSE Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN (* store private data here *)
					IF F.lib.name = "" THEN (* private library *)
						Files.WriteInt(M.R, 1);
						Files.WriteString(M.R, F.name);
						Files.WriteSet(M.R, {});
						Gadgets.framehandle(F, M)
					ELSE (* public library *)
						Files.WriteInt(M.R, 2);
						Files.WriteString(M.R, F.name);
						Gadgets.WriteRef(M.R, F.lib, F.dsc);
						Gadgets.framehandle(F, M)
					END
				ELSIF M.id = Objects.load THEN (* load private data here *)
					Files.ReadInt(M.R, x);
					IF x = 1 THEN (* private library *)
						Files.ReadString(M.R, F.name);
						Files.ReadSet(M.R, tmp);
						Gadgets.framehandle(F, M);
						F.Load(F)
					ELSIF x = 2 THEN (* public library *)
						Files.ReadString(M.R, F.name);
						Gadgets.ReadRef(M.R, F.lib, obj);
						Gadgets.framehandle(F, M);
						IF (obj # NIL) & (obj IS Gadgets.Frame) THEN F.dsc := obj(Display.Frame)
						ELSE F.Load(F)
						END;
					END
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			WITH M: Objects.BindMsg DO
				Gadgets.framehandle(F, M);
				IF (M.lib.name # "") & (F.dsc # NIL) THEN (* public library, bind document contents *)
					F.dsc.handle(F.dsc, M);
				END;
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; Copy(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.FindMsg THEN
			WITH M: Objects.FindMsg DO
				Gadgets.framehandle(F, M);
				IF (F.dsc # NIL) & (M.obj = NIL) THEN
					F.dsc.handle(F.dsc, M)
				END
			END
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END Handler;

PROCEDURE New*;
VAR F: Document;
BEGIN NEW(F); F.handle := Handler; F.W := 250; F.H := 200; Objects.NewObj := F;
END New;

(** Initialize document D with main as contents. *)
PROCEDURE Init*(D: Document; main: Gadgets.Frame);
	VAR f: Files.File; M: Display.ModifyMsg;
BEGIN
	D.dsc := main;
	IF main # NIL THEN
		IF (main.lib # NIL) & (main.lib.name # "") THEN (* public object ! *)
			D.X := main.X; D.Y := main.Y; D.W := main.W; D.H := main.H
		ELSE
			M.X := D.X; M.Y := D.Y; M.W := D.W; M.H := D.H; M.x := 0; M.y := 0;
			M.dX := M.X - main.X; M.dY := M.Y - main.Y; M.dW := M.W - main.W; M.dH := M.H - main.H;
			M.F := main; M.id := Display.extend; M.mode := Display.state; M.res := -1; Objects.Stamp(M);
			main.handle(main, M);
			main.X := D.X; main.Y := D.Y; main.W := D.W; main.H := D.H
		END;
		INCL(D.state, Gadgets.lockedcontents);
		IF Gadgets.lockedsize IN main.state THEN INCL(D.state, Gadgets.lockedsize) END
	END;
	f := Files.Old(D.name);
	IF f # NIL THEN Files.GetName(f, D.name) END
END Init;

(** Returns the marked document (with F1). NIL is returned when no document is marked. The visibility of the Oberon pointer is ignored. *)
PROCEDURE MarkedDoc*(): Document;
VAR M: LocateMsg; V: Display.Frame;
BEGIN
	IF TRUE (* Oberon.Pointer.on *) THEN
		M.X := Oberon.Pointer.X; M.Y := Oberon.Pointer.Y;
		M.F := NIL; M.doc := NIL; 
		V := Oberon.MarkedViewer();
		IF V # NIL THEN
			M.res := -1; M.x := 0; M.y := 0;
			V.handle(V, M)
		ELSE
			Display.Broadcast(M)
		END;
		RETURN M.doc
	ELSE RETURN NIL
	END
END MarkedDoc;

PROCEDURE InitM;
BEGIN
	reg := 0;
	Register("Text", "TextDocs.NewDoc", FALSE);
	Register("Tool", "TextDocs.NewDoc", FALSE);
	Register("Mod", "TextDocs.NewDoc", FALSE);
	Register("Panel", "PanelDocs.NewDoc", FALSE);
	Register("Pict", "RembrandtDocs.NewDoc", FALSE);
	RegisterStandardTypes("Gadgets.Documents", FALSE);
	RegisterStandardTypes("Gadgets.DocumentServices", TRUE)
END InitM;

BEGIN Id := 07F7H; InitM
END Documents.

(** Remarks:

1. Documents
Documents are nothing more than collections of objects, saved together in the same file. Such object collections require additional functionality that are not provided by the objects in the collection themselves. This additional functionality are provided by the document gadgets. Document gadgets act as a wrapper for a object/gadget collection, giving it a filename, icon, menu bar and printing capability. They are a type of container having a single child called the document main frame. The main frame of a document gadget is remembered in the dsc field of a document. The document gadget has exactly the same size as its main frame. The Documents.Init procedure "merges" the document with its main frame.
	Each document class has a generator procedure. Just as the generator procedures of other gadgets, calling the generator of a document creates an "empty" instance of that document class. By filling in the name record field of a document, and calling its Load method, the document will "fill" its contents from the file with that name. Correspondingly, calling the Store method stores the document under that name to disk.

2. Document Format
All documents are provided with a standard header on disk so that they can be recreated or opened when just the filename is known. The header has the following format:

	Tag DocumentGeneratorProcedure X Y W H.
	Tag = 0F7X 07X.
	DocumentGeneratorProcedure = {alpha} 0X.		(* Generator name *)
	X, Y, W, H = INTEGER.				(* Prefered document position and size. *)
	
The document header is followed by the byte stream content of the document. DocumentGeneratorProcedure is called by Documents.Open to create an empty instance of the document gadget, which is then filled by a call to the Load method (as described above). To provide compatibility with the non-Oberon world that does not use such an identification header, an internal table of the Documents module pairs file extensions with document generator procedures. Should no document header be present, the file extension is used to file the (hopefully) correct document generator. The Load method of this document must then load the headerless file. It is allowed (but not recommended) to store a document without a header, should the extension table be set up correctly. The extension table can be extended by adding an entry to the Documents section of the Oberon registry. Eeach entry is a "Extension=Generator" pair.

3. Menus
Each document requires a menu bar with commands associated with the document type when opened with Desktops.OpenDoc. This menubar is gathered from the links "SystemMenu", "UserMenu" and "DeskMenu" provided by the document when the Desktops.OpenDoc command is executed. The menu can be constructed with the procedure Dekstops.NewMenu or can be taken from a public library. The string given as parameter to procedure NewMenu must contain a sequence of Oberon commands. By immediately following a menu command with a word in square brackets, that word will be used as the menu bar button caption. A typical menu string might look as follows:

	"MyDoc.Search[Search] MyDoc.Save[Store]"
	
Note that the Desktops module automatically adds additional buttons like [Close], [Grow], [Min] and [Copy].
For more flexibility, documents may also defined their own menu bars by "exporting" them as public objects from a public library. The public library should contain three menubars for the Desktop, System track and User track respectively. These menus should have the names "DeskMenu", "SystemMenu" and "UserMenu" respectively. For example, the text documents have such a library (called "TextDocs.Lib"). When the library is missing the default menubars are used. Programmers must add support for this feature in their Document handlers. The desktop uses the LinkMsg to request the document to return its menu bar. You should always return a DEEP COPY of the menu-bar from the library. Best is to lock the menubars and to set the Border of the Panel to 0. Note that the menu bar can have any height and content. 

For example (copied from PanelDocs.Mod):

	IF M IS Objects.LinkMsg THEN
		WITH M: Objects.LinkMsg DO
			IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
				M.obj := Gadgets.CopyPublicObject("PanelDocs.DeskMenu", TRUE);
				IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
				M.res := 0
			ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
				M.obj := Gadgets.CopyPublicObject("PanelDocs.SystemMenu", TRUE);
				IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
				M.res := 0
			ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
				M.obj := Gadgets.CopyPublicObject("PanelDocs.UserMenu", TRUE);
				IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
				M.res := 0
			ELSE Documents.Handler(D, M)
			END
		END
	ELSE ...

4. Icon
A document can indicate through its "Icon" attribute what public object should be regarded as its pictorial icon representation. The document should return a string attribute in the form "L.O", where L identifies the public library, and O the object in that library. The gadget identified this way is then packed by the desktop inside an icon gadget when Desktops.MakeIcon is executed.

5. Load failure
A document can indicate a failure to load by setting D.dsc to NIL before returning from the Load method.

6. Example Code
Examples of how documents are programmed can be found in the files DocumentSkeleton.Mod, OpenDemo.Mod and OpenDemo2.Mod.

7. Uniform Resource Locator (URL) notation
URL are unique references to documents located on the network. An URL is identified as a protocol specifier followed by a document location and name:

	"protocol://location/name"
	
Typical protocols are http, mailto, ftp and so forth. The Documents module handles documents with URL-like names in a special way. Should the Open procedure be requested to open a document name with a protocol name followed by a ":", the protocol name is looked up in extension table instead of the filename extension. That is, protocols have precedence over filename extensions. 
*)