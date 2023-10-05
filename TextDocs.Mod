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

MODULE TextDocs; (** portable *) (** jm 1.2.95 / tk 1.6.95 *)

(** Implementations of text and Oberon log documents. *)

(*
	24.3.94 - Added Recall. Edit.Recall works too.
	5.4.94 - Added special menu support
	27.5.94 - Added Search "string" option
	18.2.95 - Made Locate text viewer independant
	9.5.95 - fixed ChangeFont
	1.6.95 - tk  SearchDiff new supports WhiteSpaces
	26.10.95 - Fixed Locate
	1.11.95 - Converted to attachments
	15.12.95 - Support for short menubars/SearchCol
	7.3.96 - Removed Title to filename
	6.1.97 - SearchDiff now support objects in text
	12.8.96 pjm - Invalid title check
	17.4.97 - fixed bug in AdjustStyles
*)

IMPORT
	Files, Objects, Display, Oberon, Gadgets, Texts, TextGadgets0, TextGadgets, Documents, Desktops, Attributes, Links,
	Fonts, Printer;
	
CONST
	MaxPatLen = 128;
	UserMenu = "Desktops.Copy[Copy] TextDocs.Search[Search] TextDocs.Replace[Rep] TextDocs.ReplaceAll[RepAll] Desktops.StoreDoc[Store]";
	Menu = "Desktops.Copy[Copy] TextDocs.Search[Search] TextDocs.Replace[Rep] Desktops.StoreDoc[Store]";
	LogMenu = "Desktops.Copy[Copy] TextDocs.Locate[Locate] System.Clear[Clear]";
	
TYPE
	(* this text has been stored *)
	StoreMsg = RECORD (Display.FrameMsg)
		text: Texts.Text;
	END;
	
VAR
	sPat: ARRAY MaxPatLen OF CHAR;	(* search pattern [read only] *)
	sDv: ARRAY MaxPatLen + 1 OF INTEGER;	(* displacement vector for search pattern *)
	sPatLen: INTEGER;	(* number of valid characters in sPat [read only] *)
	lTime: LONGINT;	(* most recent time for sPat and/or rBuf *)
	rBuf: Texts.Buffer;	(* replace buffer [read only] *)
	InitW, InitH, InitLogW, InitLogH: INTEGER;
	sCol: INTEGER;
	W: Texts.Writer;
	FixedDocs: BOOLEAN;
	
PROCEDURE open(D: Documents.Document; T: Texts.Text; name: ARRAY OF CHAR; VAR w, h: INTEGER);
VAR F: Files.File; R: Files.Rider; tag: INTEGER; ch: CHAR; s: ARRAY 64 OF CHAR; len: LONGINT;
	x, y: INTEGER; CM: Gadgets.CmdMsg;
BEGIN
	w := InitW; h := InitH;
	F := Files.Old(name);
	IF F = NIL THEN
		Texts.Open(T, "")
	ELSE
		Files.Set(R, F, 0);
		Files.ReadInt(R, tag);
		IF (tag = Documents.Id) OR (tag = 0727H) THEN
			Files.ReadString(R, s);
			Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, w); Files.ReadInt(R, h);
			Files.Read(R, ch);
			
			IF (ch = 0F7X) THEN (* attachments *)
				Documents.LoadAttachments(R, D.attr, D.link);
				IF D.link # NIL THEN
					CM.cmd := "PREPARE"; CM.res := -1; CM.dlink := D; Objects.Stamp(CM);
					Links.Broadcast(D.link, CM)
				END;
				Files.Read(R, ch)
			END;
			
			IF (ch = Texts.TextBlockId) OR (ch = 01X) THEN
				Texts.Load(T, F, Files.Pos(R), len);
			ELSE Texts.Open(T, "")
			END
		ELSE
			Texts.Open(T, name)
		END;
		IF FixedDocs THEN
			h := InitH	(* ps - 29.1.97 *)
		END;
		IF (w <= 0) THEN w := InitW END;
		IF (h <= 0) THEN h := InitH END;
	END
END open;

PROCEDURE LoadTextDocument(D: Documents.Document);
VAR w, h: INTEGER; T: Texts.Text; main: TextGadgets.Frame;
BEGIN
	NEW(T); open(D, T, D.name, w, h);
	NEW(main); TextGadgets.Init(main, T, FALSE);
	D.W := w; D.H := h;
	Documents.Init(D, main);
END LoadTextDocument;

PROCEDURE StoreTextDocument(D: Documents.Document);
VAR new: ARRAY 128 OF CHAR; i: INTEGER; f: Files.File; len: LONGINT; F: Display.Frame; R: Files.Rider;
	M: StoreMsg;
BEGIN
	F := D.dsc;
	WITH F: TextGadgets.Frame DO
		Texts.WriteString(W, "Store "); Texts.Append(Oberon.Log, W.buf);
		IF D.name # "" THEN
			f := Files.New(D.name);
			IF f # NIL THEN
				COPY(D.name, new); i := 0; WHILE new[i] # 0X DO INC(i) END;
				new[i] := "."; new[i+1] := "B"; new[i+2] := "a"; new[i+3] := "k"; new[i+4] := 0X;
				Files.Rename(D.name, new, i);
	
				Files.Set(R, f, 0); Files.WriteInt(R, Documents.Id); Files.WriteString(R, "TextDocs.NewDoc");
				Files.WriteInt(R, 0); Files.WriteInt(R, 0); Files.WriteInt(R, F.W); Files.WriteInt(R, F.H);
				
				IF (D.attr # NIL) OR (D.link # NIL) THEN (* attachments *)
					Documents.StoreAttachments(R, D.attr, D.link)
				END;
				
				Texts.Store(F.text, f, Files.Pos(R), len); Files.Register(f); Files.Close(f);
				
				Texts.Write(W, 22X); Texts.WriteString(W, D.name); Texts.Write(W, 22X);
				M.F := NIL; M.text := F.text; Display.Broadcast(M)
			ELSE Texts.WriteString(W, "[Invalid title]");
			END
		ELSE Texts.WriteString(W, "[Untitled document]");
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END
END StoreTextDocument;

PROCEDURE ChangeCheck0(D: Documents.Document; VAR M: Display.FrameMsg);
VAR menu, f: Display.Frame; A: Objects.AttrMsg;
BEGIN
	IF 16 IN D.state THEN
		menu := Desktops.CurMenu(M.dlink);
		IF menu # NIL THEN
			f := menu.dsc;
			WHILE f # NIL DO
				A.id := Objects.get; A.name := "Caption"; A.res := -1; A.s := ""; f.handle(f, A);
				IF A.s = "Store" THEN
					A.id := Objects.set; A.name := "Caption"; A.res := -1; A.class := Objects.String; A.s := "Store!"; f.handle(f, A);
					Gadgets.Update(f);
					f := NIL;
				ELSE f := f.next
				END
			END
		END
	END
END ChangeCheck0;

PROCEDURE ChangeCheck(D: Documents.Document; VAR M: Texts.UpdateMsg);
VAR F: TextGadgets.Frame;
BEGIN
	F := D.dsc(TextGadgets.Frame);
	IF (M.text = F.text) & ~(16 IN D.state) THEN
		INCL(D.state, 16); ChangeCheck0(D, M)
	END
END ChangeCheck;

PROCEDURE HandleStoreMsg(D: Documents.Document; T: Texts.Text; dlink: Objects.Object);
VAR F: TextGadgets.Frame; menu, f: Display.Frame; A: Objects.AttrMsg;
BEGIN
	F := D.dsc(TextGadgets.Frame);
	IF (T = F.text) & (16 IN D.state) THEN
		EXCL(D.state, 16);
		menu := Desktops.CurMenu(dlink);
		IF menu # NIL THEN
			f := menu.dsc;
			WHILE f # NIL DO
				A.id := Objects.get; A.name := "Caption"; A.res := -1; A.s := ""; f.handle(f, A);
				IF A.s = "Store!" THEN
					A.id := Objects.set; A.name := "Caption"; A.res := -1; A.class := Objects.String; A.s := "Store"; f.handle(f, A);
					Gadgets.Update(f);
					f := NIL;
				ELSE f := f.next
				END
			END
		END
	END
END HandleStoreMsg;

PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj: Display.Frame;
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "TextDocs.NewDoc"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := TRUE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Text"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Texts.UpdateMsg THEN
			ChangeCheck(D, M(Texts.UpdateMsg));
			Documents.Handler(D, M)
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.DeskMenuS", TRUE)	
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.DeskMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.SystemMenuS", TRUE)	
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.SystemMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(Menu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.UserMenuS", TRUE)	
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.UserMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(UserMenu) END;
					M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS StoreMsg THEN
			WITH M: StoreMsg DO
				HandleStoreMsg(D, M.text, M.dlink);
				Documents.Handler(D, M)
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
					obj := D.dsc; TextGadgets0.PrintText(obj(TextGadgets0.Frame), D.name)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.ControlMsg THEN
			WITH M: Display.ControlMsg DO
				IF ((M.F = D) OR (M.F = NIL)) & (M.id = Display.restore) THEN
					ChangeCheck0(D, M)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandler;

(** Normal text document *)
PROCEDURE InitDoc*(D: Documents.Document);
BEGIN D.Load := LoadTextDocument; D.Store := StoreTextDocument; D.handle := DocHandler;
	D.W := InitW; D.H := InitH;
	D.Load(D);
END InitDoc;

(** Normal text document generator *)
PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN NEW(D); InitDoc(D); Objects.NewObj := D
END NewDoc;

(* ------------- Oberon Log ---------------- *)

PROCEDURE LogHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj: Display.Frame;
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "TextDocs.NewLog"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := TRUE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Text"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
			WITH M: Objects.LinkMsg DO
				IF (M.id = Objects.get) & (M.name = "DeskMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.LogDeskMenuS", TRUE)
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.LogDeskMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(LogMenu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "SystemMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.LogSystemMenuS", TRUE)
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.LogSystemMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(LogMenu) END;
					M.res := 0
				ELSIF (M.id = Objects.get) & (M.name = "UserMenu") THEN
					IF Display.Width < 1000 THEN M.obj := Gadgets.CopyPublicObject("TextDocs.LogUserMenuS", TRUE)
					ELSE M.obj := Gadgets.CopyPublicObject("TextDocs.LogUserMenu", TRUE) END;
					IF M.obj = NIL THEN M.obj := Desktops.NewMenu(LogMenu) END;
					M.res := 0
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
					obj := D.dsc; TextGadgets0.PrintText(obj(TextGadgets0.Frame), D.name)
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END LogHandler;

PROCEDURE LoadLog(D: Documents.Document);
VAR f: Files.File; R: Files.Rider; name: ARRAY 64 OF CHAR; x, y, w, h, id: INTEGER; main: TextGadgets.Frame;
	CM: Gadgets.CmdMsg; ch: CHAR;
BEGIN
	w := InitLogW; h := InitLogH;
	f := Files.Old(D.name);
	IF f # NIL THEN
		Files.Set(R, f, 0);
		Files.ReadInt(R, id);
		IF (id = Documents.Id) OR (id = 0727H) THEN
			Files.ReadString(R, name);
			Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, w); Files.ReadInt(R, h);
			Files.Read(R, ch);
			IF (ch = 0F7X) THEN (* attachments *)
				Documents.LoadAttachments(R, D.attr, D.link);
				IF D.link # NIL THEN
					CM.cmd := "PREPARE"; CM.res := -1; CM.dlink := D; Objects.Stamp(CM);
					Links.Broadcast(D.link, CM)
				END;
				Files.Read(R, ch)
			END;
			IF FixedDocs THEN
				h := InitLogH	(* ps - 29.1.97 *)
			END;
			IF w <= 0 THEN w := InitLogW END;
			IF h <= 0 THEN h := InitLogH END
		END
	END;
	IF D.name = "" THEN D.name := "System.Log" END;
	NEW(main); TextGadgets.Init(main, Oberon.Log, FALSE);
	D.W := w; D.H := h; INCL(main.state0, TextGadgets0.autoscroll);
	Documents.Init(D, main)
END LoadLog;

PROCEDURE StoreLog(D: Documents.Document);
VAR F: Files.File; R: Files.Rider; main: Gadgets.Frame;
BEGIN
	main := D.dsc(Gadgets.Frame);
	Texts.WriteString(W, "Store Log "); Texts.Append(Oberon.Log, W.buf);
	IF D.name # "" THEN
		F := Files.New(D.name);
		IF F = NIL THEN HALT(99) END;
		Files.Set(R, F, 0);
		Files.WriteInt(R, Documents.Id); Files.WriteString(R, "TextDocs.NewLog");
		Files.WriteInt(R, 0); Files.WriteInt(R, 0); Files.WriteInt(R, main.W); Files.WriteInt(R, main.H);
		IF (D.attr # NIL) OR (D.link # NIL) THEN (* attachments *)
			Documents.StoreAttachments(R, D.attr, D.link)
		END;
		Files.Register(F);
		
		Texts.Write(W, 22X); Texts.WriteString(W, D.name); Texts.Write(W, 22X)
	ELSE Texts.WriteString(W, "[Untitled document]");
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END StoreLog;

(** Oberon log document *)
PROCEDURE InitLog*(D: Documents.Document);
BEGIN D.Load := LoadLog; D.Store := StoreLog; D.name := "System.Log"; D.handle := LogHandler;
	D.W := InitLogW; D.H := InitLogH;
	D.Load(D)
END InitLog;

(** Generator for Oberon log document *)
PROCEDURE NewLog*;
VAR D: Documents.Document;
BEGIN NEW(D); InitLog(D); Objects.NewObj := D
END NewLog;

(** Get the marked text *)
PROCEDURE GetText*(VAR par: Display.Frame): Texts.Text;
BEGIN
	par := Oberon.MarkedFrame();
	RETURN Oberon.MarkedText()
END GetText;

(** Set the caret at the indicated position in the indicated frame. The text has to correspond. *)
PROCEDURE SetCaret*(F: Display.Frame; T: Texts.Text; pos: LONGINT);
VAR M: Oberon.CaretMsg;
BEGIN
	M.id := Oberon.set; M.F := F; M.car := F; M.text := T; M.pos := pos; Display.Broadcast(M)
END SetCaret;

(** Open a text in a TextDoc. W, H is used to determine the original size of the document. *)
PROCEDURE ShowText*(title: ARRAY OF CHAR; T: Texts.Text; W, H: INTEGER);
VAR D: Documents.Document; f: TextGadgets.Frame; i: INTEGER;  log: BOOLEAN;
BEGIN
	i := 0;  WHILE (title[i] # 0X) & (title[i] # "|") DO INC(i) END;  title[i] := 0X;
	WHILE (i > 0) & ((title[i] = " ") OR (title[i] = 0X)) DO DEC(i) END;
	log := (i > 3) & (title[i-3] = ".") & (title[i-2] = "L") & (title[i-1] = "o") & (title[i] = "g");
	NEW(D);
	NEW(f); TextGadgets.Init(f, T, FALSE);	(* create content *)
	IF T = Oberon.Log THEN
		InitLog(D)
	ELSE
		InitDoc(D)
	END;	(* make document wrapper *)
	IF log OR (T = Oberon.Log) THEN INCL(f.state0, TextGadgets0.autoscroll) END;
	COPY(title, D.name);
	Documents.Init(D, f); (* and merge together *)
	D.W := W; D.H := H;
	Desktops.ShowDoc(D)
END ShowText;

(** Same function as Edit.Locate *)
PROCEDURE Locate*;
VAR T, text: Texts.Text; S: Texts.Scanner; beg, end, time: LONGINT; F: Display.Frame;
BEGIN
	text := GetText(F);
	IF text # NIL THEN
		Oberon.GetSelection(T, beg, end, time);
		IF time >= 0 THEN
			Texts.OpenScanner(S, T, beg);
			REPEAT Texts.Scan(S) UNTIL S.eot OR (S.class >= Texts.Int); (*skip names*)
			IF (S.class = Texts.Int) THEN
				IF S.i < 0 THEN S.i := 0
				ELSIF S.i > text.len THEN S.i := text.len
				END;
				SetCaret(F, text, S.i)
			END
		END
	END
END Locate;

PROCEDURE controls(F: TextGadgets.Frame);
BEGIN
	IF TextGadgets.nocontrol IN F.control THEN EXCL(F.control, TextGadgets.nocontrol)
	ELSE INCL(F.control, TextGadgets.nocontrol) END;
	F.trailer := NIL; F.car := FALSE; F.sel := FALSE;
	Gadgets.Update(F)
END controls;

(** Used in the forms:
	TextDocs.Controls *		(* toggles showing the control objects in the marked text document *)
	TextDocs.Controls 		(* toggles showing the control objects in the selected text documents *)
*)
PROCEDURE Controls*;
VAR S: Attributes.Scanner; doc: Documents.Document; F: TextGadgets.Frame; M: Display.SelectMsg; obj: Objects.Object;
	f: Display.Frame;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S); F := NIL;
	IF (S.class = Attributes.Char) & (S.c = "*") THEN
		IF (* Oberon.Pointer.on *) TRUE THEN f := Oberon.MarkedFrame()
		ELSE f := NIL
		END;
		IF (f # NIL) & (f IS TextGadgets.Frame) THEN F := f(TextGadgets.Frame)
		ELSE
			doc := Documents.MarkedDoc();
			IF (doc # NIL) & (doc.dsc IS TextGadgets.Frame) THEN F := doc.dsc(TextGadgets.Frame) END
		END;
		IF F # NIL THEN controls(F) END
	ELSE (* try on the selection *)
		M.id := Display.get; M.F := NIL; M.obj := NIL; M.sel := NIL; M.time := -1; Display.Broadcast(M);
		IF (M.time > 0) THEN
			obj := M.obj;
			WHILE obj # NIL DO
				IF obj IS TextGadgets.Frame THEN F := obj(TextGadgets.Frame); controls(F) END;
				obj := obj.slink
			END
		END
	END;
	IF F = NIL THEN
		doc := Desktops.CurDoc(Gadgets.context);
		IF (doc # NIL) & (doc.dsc IS TextGadgets.Frame) THEN
			F := doc.dsc(TextGadgets.Frame); controls(F)
		END
	END
END Controls;

(* -- search engine by uh *)

	PROCEDURE MarkPatPos(tF: TextGadgets0.Frame; pos: LONGINT);
	BEGIN
		Oberon.Defocus;
		TextGadgets0.Locate(tF, pos);
		TextGadgets0.SetSelection(tF, pos - sPatLen, pos); lTime := tF.time;
	END MarkPatPos;

	PROCEDURE CalcDispVec(time: LONGINT);
		VAR i, j, d: INTEGER;
	BEGIN
		lTime := time;
		i := 1; d := 1;	(* calculate displacement vector *)
		WHILE i <= sPatLen DO
			j := 0; WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO INC(j) END;
			WHILE i <= j + d DO sDv[i] := d; INC(i) END;
			INC(d)
		END
	END CalcDispVec;
	
	PROCEDURE SPatFound(text: Texts.Text; VAR pos:LONGINT): BOOLEAN;
	(* searches the next position for the search pattern sPat begining at position pos *)
	(* in the text text; resturns result accordingly *) 
		VAR R: Texts.Reader;	l: LONGINT;	i: INTEGER;	ch: CHAR;
	BEGIN
		IF sPatLen > 0 THEN
			Texts.OpenReader(R, text, pos); Texts.Read(R, ch); INC(pos);
			l := text.len; i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i); IF i < sPatLen THEN Texts.Read(R, ch); INC(pos) END
				ELSIF i = 0 THEN Texts.Read(R, ch); INC(pos)
				ELSE DEC(i, sDv[i])
				END
			END;
		ELSE i := -1
		END;
		RETURN i = sPatLen	(* pattern found *)
	END SPatFound;
	
	PROCEDURE search(tF: TextGadgets.Frame);
		VAR
			R: Texts.Reader;	text: Texts.Text; S: Attributes.Scanner;
			pos, beg, end, time: LONGINT; 	i: INTEGER;
	BEGIN
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF S.class = Attributes.String THEN
			COPY(S.s, sPat); sPatLen := S.len; CalcDispVec(Oberon.Time())	(* calculate displacement vector *)
		ELSE
			text := NIL; Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time - lTime > 0) THEN	(* set search pattern *)
				Texts.OpenReader(R, text, beg);
				i := 0; pos := beg;
				REPEAT Texts.Read(R, sPat[i]); INC(i); INC(pos) UNTIL (i = MaxPatLen) OR (pos = end);
				sPatLen := i; CalcDispVec(time)	(* calculate displacement vector *)
			END
		END;
		IF tF.car THEN pos := tF.carpos.pos ELSE pos := 0 END;
		IF SPatFound(tF.text, pos) THEN MarkPatPos(tF, pos)
		ELSE TextGadgets0.RemoveSelection(tF); TextGadgets0.RemoveCaret(tF)
		END
	END search;

	(** Same as Edit.Search. Also can be used in the form: TextDocs.Search "string" to search for the specified string
	in the current document *)
	PROCEDURE Search*; (* [ "string" ] *)
		VAR tF: TextGadgets.Frame; doc: Documents.Document;
	BEGIN
		doc := Desktops.CurDoc(Gadgets.context);
		IF (doc # NIL) & (doc.dsc IS TextGadgets.Frame) THEN
			tF := doc.dsc(TextGadgets.Frame);
			search(tF)
		END
	END Search;
	
	PROCEDURE replace(all: BOOLEAN);
	VAR tF: TextGadgets.Frame; R: Texts.Reader; tBuf: Texts.Buffer; T, text: Texts.Text;
		pos, beg, end, time, p, len: LONGINT;  i: INTEGER;  ch: CHAR;  M: Oberon.CaretMsg;
	BEGIN
		tF := NIL;
		M.id := Oberon.get; M.F := NIL; M.car := NIL; M.text := NIL; M.pos := -1; Display.Broadcast(M);
		IF (M.car # NIL) & (M.car IS TextGadgets.Frame) THEN tF := M.car(TextGadgets.Frame) END;
		IF tF # NIL THEN
			T := tF.text;
			text := NIL; Oberon.GetSelection(text, beg, end, time);
			IF (text # NIL) & (time - lTime > 0) THEN	(* set replace buffer *)
				lTime := time; NEW(rBuf); Texts.OpenBuf(rBuf); Texts.Save(text, beg, end, rBuf)
			END;
			IF ~tF.car OR ~(sPatLen > 0) OR (rBuf = NIL) THEN RETURN END;	(* ###*)
			pos := tF.carpos.pos; p := pos - sPatLen;
			IF p < 0 THEN RETURN END;	(* ###*)
			LOOP
				Texts.OpenReader(R, T, p); Texts.Read(R, ch); i := 0;
				WHILE (ch = sPat[i]) & (i < sPatLen) DO Texts.Read(R, ch); INC(i) END;
				IF i = sPatLen THEN
					Texts.Delete(T, p, pos); pos := p;
					NEW(tBuf); Texts.OpenBuf(tBuf);
					Texts.Copy(rBuf, tBuf); len := tBuf.len;
					Texts.Insert(T, pos, tBuf); pos := pos + len
				END;
				IF SPatFound(tF.text, pos) THEN
					IF all THEN p := pos-sPatLen ELSE MarkPatPos(tF, pos); RETURN END
				ELSIF all THEN
					i := sPatLen; sPatLen := SHORT(len);
					MarkPatPos(tF, p+sPatLen);
					sPatLen := i; RETURN
				ELSE TextGadgets0.RemoveSelection(tF); TextGadgets0.RemoveCaret(tF); RETURN
				END
			END
		END
	END replace;

	(** Replace the last searched for string with the current selection *)
	PROCEDURE Replace*;
	BEGIN
		replace(FALSE)
	END Replace;
	
	(** Replace all occurances of the last searched for string with the current selection *)
	PROCEDURE ReplaceAll*;
	BEGIN
		replace(TRUE)
	END ReplaceAll;

	(** Recalls last deleted text stretch *)
	PROCEDURE Recall*;
	VAR M: Oberon.RecallMsg;
	BEGIN M.F := NIL; Display.Broadcast(M)
	END Recall;

(** Used in the form: TextDocs.Show M.P
	Shows the module M at the position where P occurs for the first time *)
PROCEDURE Show*;
VAR S: Attributes.Scanner; name: ARRAY 35 OF CHAR; i, j, M: INTEGER; pos: LONGINT; D: Documents.Document;
	F: TextGadgets0.Frame;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class = Attributes.Name THEN
		i := -1; j := 0;
		WHILE S.s[j] # 0X DO
			IF S.s[j] = "." THEN i := j END;
			name[j] := S.s[j]; INC(j)
		END;
		IF i = -1 THEN
			IF name[j-1] = ":" THEN DEC(j) END;
			name[j] := ".";  i := j
		END;
		name[i+1] := "M"; name[i+2] := "o"; name[i+3] := "d"; name[i+4] := 0X;
		D := Documents.Open(name);
		IF (D # NIL) & (D.dsc # NIL) & (D.dsc IS TextGadgets0.Frame) THEN
			F := D.dsc(TextGadgets0.Frame);
			j := i+1; M := 0;
			WHILE (M # MaxPatLen) & (S.s[j] # 0X) DO sPat[M] := S.s[j]; INC(j); INC(M) END;
			sPatLen := M;  CalcDispVec(Oberon.Time());	(* calculate displacement vector *)
			
			Desktops.ShowDoc(D);
			pos := 0;
			IF ~SPatFound(F.text, pos) THEN pos := 0 END;
			IF pos > 0 THEN MarkPatPos(F, pos) END
		END
	END
END Show;

(** Used in the form: TextDocs.ChangeFont <fontname>
	Changes the font of the selection. *)
PROCEDURE ChangeFont*;
VAR par: Oberon.ParList; S: Attributes.Scanner; T: Texts.Text; beg, end, time: LONGINT;
	F: Fonts.Font;
BEGIN
	Oberon.GetSelection(T, beg, end, time);
	IF time >= 0 THEN par := Oberon.Par;
		Attributes.OpenScanner(S, par.text, par.pos); Attributes.Scan(S);
		IF S.class IN {Attributes.Name, Attributes.String} THEN
			F := Fonts.This(S.s);
			IF F # NIL THEN 
				Texts.ChangeLooks(T, beg, end, {0}, F, 0, 0)
			ELSE
				Texts.WriteString(W, "  font not found"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END ChangeFont;

(** Used in the form: TextDocs.ChangeColor <col-no>
	Changes the color of the selection. *)
PROCEDURE ChangeColor*;
VAR par: Oberon.ParList; S: Attributes.Scanner; T: Texts.Text;
	col: SHORTINT; beg, end, time: LONGINT;
BEGIN par := Oberon.Par;
	Attributes.OpenScanner(S, par.text, par.pos); Attributes.Scan(S);
	IF S.class # Texts.Int THEN col := Display.FG ELSE col := SHORT(SHORT(S.i)) END;
	Oberon.GetSelection(T, beg, end, time);
	IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {1}, NIL, col, 0) END
END ChangeColor;

(** Used in the form: TextDocs.ChangeOffset <offset>
	Changes the offset of the selection. Offset is measured in pixels, and may be negative. *)
PROCEDURE ChangeOffset*;
VAR par: Oberon.ParList; S: Attributes.Scanner; T: Texts.Text;
	off: SHORTINT; beg, end, time: LONGINT;
BEGIN par := Oberon.Par;
	Attributes.OpenScanner(S, par.text, par.pos); Attributes.Scan(S);
	IF S.class # Texts.Int THEN off := 0 ELSE off := SHORT(SHORT(S.i)) END;
	Oberon.GetSelection(T, beg, end, time);
	IF time >= 0 THEN Texts.ChangeLooks(T, beg, end, {2}, NIL, 0, off) END
END ChangeOffset;

(** Starts searching for textual differences starting at the selection positions of the last two selected texts
		Call: TextDocs.SearchDiff			exact comparison 
				TextDocs.SearchDiff \w	  compare with 'white spaces'	
*)
PROCEDURE SearchDiff*;
VAR F1, F2: Display.Frame; T1, T2: Texts.Text; S: Texts.Scanner; pos1, pos2: LONGINT;
	R1, R2: Texts.Reader; ch1, ch2: CHAR; gen1, gen2: ARRAY 64 OF CHAR; obj: Objects.Object;
	whiteSp: BOOLEAN;

	PROCEDURE GetSelFrame(VAR F: Display.Frame; VAR T: Texts.Text; VAR pos: LONGINT);
	VAR M: Oberon.SelectMsg;
	BEGIN
		M.id := Oberon.get; M.F := NIL; M.time := -1; M.text := NIL; M.sel := NIL; Display.Broadcast(M);
		IF (M.time > 0) & (M.text # NIL) & (M.sel # NIL) THEN
			F := M.sel; T := M.text; pos := M.beg
		ELSE F := NIL
		END
	END GetSelFrame;
	
	PROCEDURE RemoveMarks(F: Display.Frame; T: Texts.Text);
	VAR M: Oberon.SelectMsg;
	BEGIN M.F := F; M.id := Oberon.reset; M.sel := F; M.text := T; Display.Broadcast(M)
	END RemoveMarks;
	
	PROCEDURE SetSelection(F: Display.Frame; T: Texts.Text; beg, end: LONGINT);
	VAR M: Oberon.SelectMsg;
	BEGIN
		M.id := Oberon.set; M.F := F; M.sel := F; M.text := T; M.beg := beg; M.end := end; Display.Broadcast(M)
	END SetSelection;
	
	PROCEDURE ReadNonWhiteSp(VAR R: Texts.Reader; VAR ch: CHAR; VAR pos: LONGINT);
	BEGIN
		REPEAT Texts.Read(R, ch); INC(pos); UNTIL R.eot OR ((ch > " ") & (R.lib IS Fonts.Font))
	END ReadNonWhiteSp;

BEGIN
	whiteSp := TRUE;
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF (S.line = 0) & (S.class = Texts.Char) & ((S.c = Oberon.OptionChar) OR (S.c = "%")) THEN Texts.Scan(S);
		IF (S.class = Texts.Name) & (CAP(S.s[0]) = "W") THEN whiteSp := FALSE END;
	END;
	GetSelFrame(F1, T1, pos1);
	IF F1 # NIL THEN RemoveMarks(F1, T1) END;
	GetSelFrame(F2, T2, pos2);
	IF F2 # NIL THEN RemoveMarks(F2, T1) END;
	IF (F1 # NIL) & (F2 # NIL) & (T1 # T2) THEN
		Texts.OpenReader(R1, T1, pos1); 
		Texts.OpenReader(R2, T2, pos2); 
		IF whiteSp THEN
			gen1 := ""; gen2 := "";
			REPEAT 
				Texts.Read(R1, ch1); INC(pos1); 
				Texts.Read(R2, ch2); INC(pos2);
				IF ~R1.eot & ~R2.eot THEN
					IF ~(R1.lib IS Fonts.Font) THEN
						R1.lib.GetObj(R1.lib, ORD(ch1), obj);
						Attributes.GetString(obj, "Gen", gen1)
					END;
					IF ~(R2.lib IS Fonts.Font) THEN
						R2.lib.GetObj(R2.lib, ORD(ch2), obj);
						Attributes.GetString(obj, "Gen", gen2)
					END;
					IF ((R1.lib IS Fonts.Font) # (R2.lib IS Fonts.Font)) OR (gen1 # gen2) THEN
						ch1 := 0X; ch2 := 1X
					ELSIF ~(R1.lib IS Fonts.Font) THEN	(* same object *)
						ch1 := 1X; ch2 := ch1
					END
				END
			UNTIL (ch1 # ch2) OR (ch1 = 0X);
		ELSE
			REPEAT
				ReadNonWhiteSp(R1, ch1, pos1);
				ReadNonWhiteSp(R2, ch2, pos2);
			UNTIL (ch1 # ch2) OR (ch1 = 0X)
		END;
		DEC(pos1); SetCaret(F1, T1, pos1); SetSelection(F1, T1, pos1, pos1 + 1);
		DEC(pos2); SetCaret(F2, T2, pos2); SetSelection(F2, T2, pos2, pos2 + 1)
	END
END SearchDiff;

(** Searches for a colored text in the document containing the caret. ColorNumber is
implicitely passed by the text color of the selected text. *)
PROCEDURE SearchColor*;
	VAR tF: TextGadgets.Frame; R: Texts.Reader; text: Texts.Text; 
		pos, beg, end, time: LONGINT; ch: CHAR; C: Oberon.CaretMsg;
BEGIN
	C.F := NIL; C.id := Oberon.get; C.car := NIL; Display.Broadcast(C);
	IF (C.res = 0) & (C.car # NIL) & (C.car IS TextGadgets.Frame) THEN
		tF := C.car(TextGadgets.Frame);
		text := NIL; Oberon.GetSelection(text, beg, end, time);
		IF  text # NIL THEN	(* set search pattern *)
			Texts.OpenReader(R, text, beg); Texts.Read(R, ch); sCol := R.col;
		END;
		pos := tF.carpos.pos;
		Texts.OpenReader(R, tF.text, pos); Texts.Read(R, ch);
		WHILE ~R.eot & (R.col # sCol) DO Texts.Read(R, ch); INC(pos) END;
		IF ~R.eot THEN
			beg := pos;
			WHILE ~R.eot & (R.col = sCol) DO Texts.Read(R, ch); INC(beg) END;
			Oberon.Defocus;
			TextGadgets0.Locate(tF, beg);
			TextGadgets0.SetSelection(tF, pos, beg)
		ELSE TextGadgets0.RemoveSelection(tF); TextGadgets0.RemoveCaret(tF)
		END
	END
END SearchColor;

(** Set all styles to paper width *)

PROCEDURE AdjustStyles*;
	VAR D: Documents.Document; F: TextGadgets.Frame; obj: Objects.Object;
			f: Texts.Finder; W: INTEGER; A: Display.ModifyMsg;
BEGIN
	D := Documents.MarkedDoc();
	IF (D # NIL) &  (D.dsc # NIL) & (D.dsc IS TextGadgets.Frame) THEN
		W := SHORT(Printer.Unit * Printer.FrameW DIV Display.Unit);
		F := D.dsc(TextGadgets.Frame);
		Texts.OpenFinder(f, F.text, 0);
		Texts.FindObj(f, obj);
		WHILE ~f.eot DO
			IF obj IS TextGadgets.Style THEN
				WITH obj: TextGadgets.Style DO
					IF TextGadgets.span IN obj.mode THEN
						obj.width := W - obj.leftM;
						A.id := Display.move; A.mode := Display.display; A.F := obj;
						A.X := obj.X; A.Y := obj.Y; A.W := W; A.H := obj.H; A.dX := 0; A.dY := 0; A.dW := A.W - obj.W; A.dH := 0;
						Display.Broadcast(A)
					END
				END
			END;
			Texts.FindObj(f, obj)
		END
	END
END AdjustStyles;

(** Used in the form: TextDocs.PrintSetup [ ( \hoff | \hon ) ] [ ( \poff | \pon) ]
	Sets printing of document name headers and page numbers. *)

PROCEDURE PrintSetup*;
	VAR S: Texts.Scanner;
BEGIN
	Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(S);
	WHILE ~S.eot & (S.class = Texts.Char) & (S.c = Oberon.OptionChar) DO
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			IF CAP(S.s[0]) = "H" THEN (* header, doc name *)
				IF CAP(S.s[2]) = "F" THEN
					EXCL(TextGadgets0.printOpts, 1)
				ELSE
					INCL(TextGadgets0.printOpts, 1)
				END
			ELSIF CAP(S.s[0]) = "P" THEN (* header, page numbers *)
				IF CAP(S.s[2]) = "F" THEN
					EXCL(TextGadgets0.printOpts, 0)
				ELSE
					INCL(TextGadgets0.printOpts, 0)
				END
			ELSE
			END;
			Texts.Scan(S)
		END
	END;
	Texts.WriteString(W, "header ");
	IF 1 IN TextGadgets0.printOpts THEN
		Texts.WriteString(W, "on")
	ELSE
		Texts.WriteString(W, "off")
	END;
	Texts.WriteLn(W);
	Texts.WriteString(W, "page numbering ");
	IF 0 IN TextGadgets0.printOpts THEN
		Texts.WriteString(W, "on")
	ELSE
		Texts.WriteString(W, "off")
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END PrintSetup;

(** Replace the default system editor with a textdoc. *)

PROCEDURE ReplaceSystemEditor*;
BEGIN
	Oberon.OpenText := ShowText
END ReplaceSystemEditor;

PROCEDURE Init;
VAR s: Texts.Scanner;
BEGIN
	IF Oberon.OpenText = NIL THEN
		Oberon.OpenText := ShowText
	END;
	Oberon.OpenScanner(s, "Gadgets.FixedDocs");
	FixedDocs := ~(s.class IN {Texts.Name, Texts.String}) OR (CAP(s.s[0]) # "N");
	InitW := Display.Width*5 DIV 8;
	InitLogW := Display.Width*3 DIV 8;
	IF FixedDocs THEN
		InitH := Display.Height-Desktops.menuH;
		InitLogH := InitH
	ELSE
		InitH := Display.Height*7 DIV 8;
		InitLogH := Display.Height DIV 3
	END
END Init;

BEGIN Texts.OpenWriter(W); Init
END TextDocs.

TextDocs.PrintSetup \Hon \Pon

TextDocs.PrintSetup \Hoff \Poff

