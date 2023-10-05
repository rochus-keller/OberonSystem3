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

MODULE BookDocs;	(** portable *)
	IMPORT BooksHelp, Books, Books0, Oberon, Files, Texts, Fonts, Display, Display3, Objects, BasicGadgets, TextFields, Gadgets,
		TextGadgets, TextGadgets0, TextDocs, Panels, Strings, Desktops, Documents, Printer, Effects;
	
	CONST
		(* size of document *)
		W* = 8*Books.buttonW-2; H* = 400;
		(* menu of document *)
		Menu = "BookDocs.Search[Search] Desktops.StoreDoc[Store]";
		(* default icon *)
		defaultIcon = "Icons.Note";
		(* constants for printing *)
		all = 0; cont = 1;
		(* constants for searching *)
		text = 0; color = 1; object = 2;
		MaxPatLen = 128;
		
(* prepare print id for Display.DisplayMsg, to be replaced by Display.prepare *)
(* see also the PrintDoc command *)
		prepare = Display.contents+1;
		
	TYPE
		FrameList = POINTER TO FrameListDesc;
		DocList = POINTER TO DocListDesc;
		
		(* list of Books0.Frame for printing *)
		FrameListDesc = RECORD
			frame: Books0.Frame;
			page, pos: LONGINT;
			next: FrameList
		END;
		
		(* list of documents for deepsearch *)
		DocListDesc = RECORD
			doc: Documents.Document;
			cur: Books0.TextList;
			pos: LONGINT;
			next: DocList
		END;
		
		(* is the tutorial F still visible *)
		VisibleMsg = RECORD (Display.FrameMsg)
			visible: BOOLEAN
		END;
		
		(* does a (valid) tutorial "name" exist *) 
		ExistMsg = RECORD (Display.FrameMsg)
			name: ARRAY 64 OF CHAR
		END;
		
		(* does a (valid) import-list for the tutorial "name" exist *)
		ExistImpMsg = RECORD (Display.FrameMsg)
			name: ARRAY 64 OF CHAR;
			il: Books0.ImpList
		END;
		
		(* all opened tutorials "name" are invalid *)
		InValMsg* = RECORD (Display.FrameMsg)
			name*: ARRAY 64 OF CHAR
		END;
		
	VAR
		Wr: Texts.Writer;
		B: Texts.Buffer;
		tmpT: Texts.Text;
		(* printer coordinates (here for A4) *)
		printerTop, printerRight, printerWMiddle, printerPageW, printerTab: INTEGER;
		(* default fonts *)
		titleFont*, textFont*, noteFont*, linkFont*, callFont*: Fonts.Font;
		sectionFonts*: ARRAY Books.maxSect OF Fonts.Font;
		(* list of Books0.Frame to print *)
		printFrames, index: FrameList;
		(* variables used for printing *)
		Tcont, T, Tindex, Tnotes: TextGadgets.Frame;
		pageNr, maxWi, maxWc: LONGINT;
		oldW: INTEGER;
		prMode: SET;
		(* global variables for searching *)
		sPat: ARRAY MaxPatLen OF CHAR;
		sDv: ARRAY MaxPatLen + 1 OF INTEGER;
		sPatLen: INTEGER;
		lTime: LONGINT;
		lastDoc: Documents.Document;
		lastDeep, docList: DocList;

(* initialize DefaultFonts *)
	PROCEDURE GetFonts();
		VAR i: INTEGER;
		PROCEDURE Font(name: ARRAY OF CHAR): Fonts.Font;
			VAR fnt: Fonts.Font;
		BEGIN
			fnt := Fonts.This(name);
			IF fnt = NIL THEN
				fnt := Fonts.Default
			END;
			RETURN fnt
		END Font;
	BEGIN
		titleFont := Font("Default20b.Scn.Fnt");
		sectionFonts[0] := Font("Default16b.Scn.Fnt");
		sectionFonts[1] := Font("Default14b.Scn.Fnt");
		sectionFonts[2] := Font("Default12b.Scn.Fnt");
		i := 3;
		WHILE i < Books.maxSect DO
			sectionFonts[i] := Font("Default12i.Scn.Fnt");
			INC(i)
		END;
		textFont := Font("Default12.Scn.Fnt");
		linkFont := textFont;
		callFont := textFont;
		noteFont := textFont
	END GetFonts;
	
(* load/store of tutorial-documents *)

	(* create a new BasicGadgets.Button *)
	PROCEDURE Button(X, Y: INTEGER; cmdStr, caption, name: ARRAY OF CHAR): Objects.Object;
		VAR
			obj: Objects.Object;
			A: Objects.AttrMsg;
	BEGIN
		BasicGadgets.NewButton();
		obj := Objects.NewObj;
		WITH obj: BasicGadgets.Button DO
			Gadgets.NameObj(obj, name);
			obj.X := X; obj.Y := Y;
			obj.W := Books.buttonW; obj.H := Books.buttonH;
			COPY(caption, obj.caption);
			obj.popout := TRUE;
			obj.val := FALSE;
			A.id := Objects.set;
			A.name := "Cmd";
			COPY(cmdStr, A.s);
			A.class := Objects.String;
			A.res := -1;
			obj.handle(obj, A);
			obj.slink := NIL
		END;
		RETURN obj
	END Button;

	(* create the Button-Bar used by tutorials *)
	PROCEDURE MakeButtonBar(twoRow: BOOLEAN): Objects.Object;
		VAR obj, old: Objects.Object;
	BEGIN
		obj := Button(0*Books.buttonW, -Books.buttonH, "BookDocs.Prev", "Prev", "prev");
		BooksHelp.SetTutorial(obj, "Tutorials.Book Prev");
		old := obj;
		obj := Button(1*Books.buttonW, -Books.buttonH, "BookDocs.Next", "Next", "next");
		BooksHelp.SetTutorial(obj, "Tutorials.Book Next");
		obj.slink := old; old := obj;
		obj := Button(2*Books.buttonW, -Books.buttonH, "BookDocs.Contents", "Contents", "cont");
		BooksHelp.SetTutorial(obj, "Tutorials.Book ContentsB");
		obj.slink := old; old := obj;
		obj := Button(3*Books.buttonW, -Books.buttonH, "BookDocs.Index", "Index", "ind");
		BooksHelp.SetTutorial(obj, "Tutorials.Book IndexB");
		obj.slink := old; old := obj;
		IF twoRow THEN
			obj := Button(0*Books.buttonW, -2*Books.buttonH, "BookDocs.Pop", "Back", "old");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Back");
			obj.slink := old; old := obj;
			obj := Button(1*Books.buttonW, -2*Books.buttonH, "BookDocs.History", "History", "hist");
			BooksHelp.SetTutorial(obj, "Tutorials.Book History");
			obj.slink := old; old := obj;
			obj := Button(2*Books.buttonW, -2*Books.buttonH, "Books.ChapDown", "Down", "down");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Down");
			obj.slink := old; old := obj;
			obj := Button(3*Books.buttonW, -2*Books.buttonH, "Books.ChapUp", "Up", "up");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Up")
		ELSE
			obj := Button(4*Books.buttonW, -Books.buttonH, "BookDocs.Pop", "Back", "old");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Back");
			obj.slink := old; old := obj;
			obj := Button(5*Books.buttonW, -Books.buttonH, "BookDocs.History", "History", "hist");
			BooksHelp.SetTutorial(obj, "Tutorials.Book History");
			obj.slink := old; old := obj;
			obj := Button(6*Books.buttonW, -Books.buttonH, "Books.ChapDown", "Down", "down");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Down");
			obj.slink := old; old := obj;
			obj := Button(7*Books.buttonW, -Books.buttonH, "Books.ChapUp", "Up", "up");
			BooksHelp.SetTutorial(obj, "Tutorials.Book Up")
		END;
		obj.slink := old;
		RETURN obj
	END MakeButtonBar;

	(* create the main-text *)
	PROCEDURE MakeText(P: Books.Panel; h: INTEGER): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		Books.NewText(P);
		obj := Objects.NewObj;
		WITH obj: TextGadgets.Frame DO
			Gadgets.NameObj(obj, "Text");
			obj.X := 0; obj.Y := 0;
			obj.W := P.W-Books.borderL-Books.borderR+1;
			obj.H := h;
			obj.slink := NIL
		END;
		BooksHelp.SetTutorial(obj, "Tutorials.Book textC");
		RETURN obj
	END MakeText;

	(* create the footnotes-text *)
	PROCEDURE MakeNote(P: Books.Panel; h: INTEGER): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		Books.NewText(P);
		obj := Objects.NewObj;
		WITH obj: TextGadgets.Frame DO
			Gadgets.NameObj(obj, "Note");
			obj.X := 0; obj.Y := 0;
			obj.W := P.W-Books.borderL-Books.borderR+1;
			obj.H := h;
			obj.slink := NIL
		END;
		BooksHelp.SetTutorial(obj, "Tutorials.Book NotesText");
		RETURN obj
	END MakeNote;
	
	(* mouse-tracking to change the text-heigths *)
	PROCEDURE TrackBarMouse(F: Books0.Bar; M: Oberon.InputMsg);
		VAR
			P: Books.Panel;
			R: Display3.Mask;
			x1, w, y1, y2, lastY: INTEGER;
			msg: Display.ModifyMsg;
	BEGIN
		IF (M.dlink # NIL) & (M.dlink IS Books.Panel) THEN
			Books0.ColorBar(F, Display3.red);
			P := M.dlink(Books.Panel);
			Gadgets.MakeMask(P, M.x, M.y(*+P.Y*) - P.H, P.dlink, R);
			x1 := M.x+Books.borderL-1;
			w := P.W-Books.borderL-Books.borderR;
			IF Books.twoRow IN P.options THEN
				y1 := M.y(*+P.Y*) - P.H+Books.borderB+2*Books.buttonH+Books.barH+5
			ELSE
				y1 := M.y(*+P.Y*) - P.H+Books.borderB+Books.buttonH+Books.barH+5
			END;
			y2 := M.y(*+P.Y*)- P.H +P.H-Books.borderT-Books.barH-10;
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(R, Display3.invertC, x1, M.Y, w, 1, Display3.invert);
			Display3.ReplConst(R, Display3.invertC, x1, M.Y+Books.barH, w, 1, Display3.invert);
			lastY := M.Y;
			REPEAT
				Effects.TrackMouse(M.keys, M.X, M.Y, Effects.PointHand);
				IF (lastY # M.Y) & (M.Y > y1) & (M.Y < y2) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					Display3.ReplConst(R, Display3.invertC, x1, lastY, w, 1, Display3.invert);
					Display3.ReplConst(R, Display3.invertC, x1, lastY+Books.barH, w, 1, Display3.invert);
					Display3.ReplConst(R, Display3.invertC, x1, M.Y, w, 1, Display3.invert);
					Display3.ReplConst(R, Display3.invertC, x1, M.Y+Books.barH, w, 1, Display3.invert);
					lastY := M.Y
				END
			UNTIL M.keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(R, Display3.invertC, x1, lastY, w, 1, Display3.invert);
			Display3.ReplConst(R, Display3.invertC, x1, lastY+Books.barH, w, 1, Display3.invert);
			P.noteH := lastY-y1+ Books.barH + Books.barH DIV 2;
			Books0.ColorBar(F, Display3.black);
			msg.id := Display.restore;
			msg.dX := 0; msg.dY := 0;
			msg.W := P.W; msg.H := P.H;
			msg.dW := 0; msg.dH := 0;
			msg.X := P.X; msg.Y := P.Y;
			msg.F := P;
			msg.res := -1;
			msg.x := 0; msg.y := 0;
			msg.dlink := M.dlink;
			Books.ReDisplay(msg, Display.display, TRUE)
		END
	END TrackBarMouse;
	
	PROCEDURE *BarHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
		WITH F: Books0.Bar DO
			IF M IS Oberon.InputMsg THEN
				WITH M: Oberon.InputMsg DO
					IF ((M.F = NIL) OR (M.F = F)) & (M.id = Oberon.track) & (M.keys # {}) THEN
						TrackBarMouse(F, M);
						M.res := 0
					ELSE Books0.BarFrameHandler(F, M)
					END
				END
			ELSE Books0.BarFrameHandler(F, M)
			END
		END
	END BarHandler;
	
	(* create a new Books0.Bar *)
	PROCEDURE Bar(P: Books.Panel; Y, H: INTEGER; name: ARRAY OF CHAR): Objects.Object;
		VAR obj: Objects.Object;
	BEGIN
		Books0.NewBar();
		obj := Objects.NewObj;
		WITH obj: Books0.Bar DO
			Gadgets.NameObj(obj, name);
			obj.X := 0; obj.Y := Y;
			obj.W := P.W-Books.borderL-Books.borderR;
			obj.H := H;
			obj.slink := NIL
		END;
		RETURN obj
	END Bar;
	
	(* the black bars used by tutorials *)
	PROCEDURE MakeBars(P: Books.Panel; hT: INTEGER): Objects.Object;
		VAR obj, old: Objects.Object;
	BEGIN
		obj := Bar(P, Books.barH+P.noteH+Books.barH+hT, Books.barH, "bar0");
		old := obj;
		obj := Bar(P, Books.barH+P.noteH, Books.barH, "bar1");
		BooksHelp.SetTutorial(obj, "Tutorials.Book MoveBar");
		obj.handle := BarHandler;
		obj.slink := old; old := obj;
		obj := Bar(P, 0, Books.barH, "bar2");
		obj.slink := old;
		RETURN obj
	END MakeBars;
	
	(* drop all Gadgets on the doc.dsc-panel *)
	PROCEDURE BuildInterface(P: Books.Panel);
		VAR
			C: Display.ConsumeMsg;
			hT, hN, buttonH: INTEGER;
	BEGIN
		BooksHelp.SetTutorial(P, "Tutorials.Book Open");
		IF P.W < (8*Books.buttonW-2) THEN
			INCL(P.options, Books.twoRow)
		ELSE
			EXCL(P.options, Books.twoRow)
		END;
		IF Books.twoRow IN P.options THEN
			buttonH := 2*Books.buttonH
		ELSE
			buttonH := Books.buttonH
		END;
		C.F := P;
		C.id := Display.drop;
		C.x := 0; C.y := 0;
		C.dlink := NIL;
		hT := P.H-Books.borderB-buttonH-Books.barH-P.noteH-Books.barH-Books.barH+1;
		hN := P.noteH;
		C.obj := MakeText(P, hT);
		C.u := Books.borderL-1;
		C.v := -P.H+Books.borderB+buttonH+Books.barH+hN+Books.barH;
		C.res := -1;
		P.handle(P, C);
		C.obj := MakeNote(P, hN);
		C.u := Books.borderL-1;
		C.v := -P.H+Books.borderB+buttonH+Books.barH;
		C.res := -1;
		P.handle(P, C);
		C.obj := MakeButtonBar(Books.twoRow IN P.options);
		C.u := Books.borderL-2;
		C.v := -P.H+Books.borderB;
		C.res := -1;
		P.handle(P, C);
		C.obj := MakeBars(P, hT);
		C.u := Books.borderL;
		C.v := -P.H+Books.borderB+Books.buttonH;
		C.res := -1;
		P.handle(P, C);
		
		P.state := P.state + {Gadgets.lockedcontents, Gadgets.lockedsize};
		P.state0 := P.state0 + {Panels.noselect, Panels.noinsert, Panels.frozen};
		(*!!
		Panels.Freeze(P, TRUE);
		*)
		IF Books.resize IN P.options THEN
			EXCL(P.state, Gadgets.lockedsize)
		ELSE
			INCL(P.state, Gadgets.lockedsize)
		END;
		Gadgets.Update(P);
		Books.GotoText(P, Books.newInd, Books.newPos, FALSE)
	END BuildInterface;
	
	(* write a tutorial-document-file-header *)
	PROCEDURE WriteHeader*(VAR R: Files.Rider; x, y, w, h: INTEGER; ind, pos: LONGINT; options: SET; iconStr: ARRAY OF CHAR);
	BEGIN
		Files.WriteInt(R, Documents.Id);
		Files.WriteString(R, "BookDocs.NewDoc");
		Files.WriteInt(R, x); Files.WriteInt(R, y);
		Files.WriteInt(R, w); Files.WriteInt(R, h);
		Files.WriteLInt(R, ind); Files.WriteLInt(R, pos);
		Files.WriteSet(R, options);
		IF Books.icon IN options THEN
			Files.WriteString(R, iconStr)
		ELSE
			Files.WriteString(R, defaultIcon)
		END
	END WriteHeader;
	
	PROCEDURE WriteHeaderP(VAR R: Files.Rider; P: Books.Panel);
		VAR
			T: Books.TGFrame;
			D: Documents.Document;
	BEGIN
		D := P.doc;
		Books.GetText(P, T);
		WriteHeader(R, D.X, D.Y, D.W, D.H, Books.GetInd(P, P.cur), T.org, P.options, P.iconStr)
	END WriteHeaderP;
	
	(* skip over a tutorial-document-file-header *)
	PROCEDURE SkipHeader*(VAR R: Files.Rider): BOOLEAN;
		VAR
			i: INTEGER;
			li: LONGINT;
			name: ARRAY 2*Books0.nameLen OF CHAR;
			s: SET;
	BEGIN
		Files.ReadInt(R, i);
		IF i # Documents.Id THEN
			RETURN FALSE
		END;
		Files.ReadString(R, name);
		IF name # "BookDocs.NewDoc" THEN
			RETURN FALSE
		END;
		Files.ReadInt(R, i); Files.ReadInt(R, i);
		Files.ReadInt(R, i); Files.ReadInt(R, i);
		Files.ReadLInt(R, li); Files.ReadLInt(R, li);
		Files.ReadSet(R, s);
		Files.ReadString(R, name);
		RETURN TRUE
	END SkipHeader;
		
	(* create an import list for il.name *)
	PROCEDURE Import*(il: Books0.ImpList; new: BOOLEAN): BOOLEAN;
		VAR
			F: Files.File;
			R: Files.Rider;
			fix1, fix2, pos, len: LONGINT;
			mode: SHORTINT;
			el: Books0.ExtLabel;
			E: ExistImpMsg;
	BEGIN
		IF ~new THEN
			E.F := NIL;
			COPY(il.name, E.name);
			E.il := NIL;
			E.res := -1;
			Display.Broadcast(E);
			IF E.il # NIL THEN
				il.extLabels := E.il.extLabels;
				Books.CopyText(E.il.notes, il.notes);
				RETURN TRUE
			END
		END;
		F := Files.Old(il.name);
		IF F = NIL THEN
			RETURN FALSE
		END;
		Files.Set(R, F, 0);
		IF ~SkipHeader(R) THEN
			RETURN FALSE
		END;
		Files.ReadLInt(R, fix1);
		Files.ReadLInt(R, fix2);
		Files.ReadLInt(R, len);
		Files.Set(R, F, fix1);
		Files.Read(R, mode);
		WHILE mode > Books0.none DO
			NEW(el);
			el.frame := NIL;
			el.mode := mode;
			el.book := il;
			Files.ReadLInt(R, el.pos1);
			Files.ReadLInt(R, el.pos2);
			Files.ReadString(R, el.name);
			el.next := il.extLabels;
			il.extLabels := el;
			Files.Read(R, mode)
		END;
		NEW(il.notes); Texts.Open(il.notes, "");
		Files.Set(R, F, fix2);
		Files.ReadLInt(R, len);
		IF len > 0 THEN
			pos := Files.Pos(R)+1;
			Texts.Load(il.notes, F, pos, len)
		END;
		RETURN TRUE
	END Import;

	(* look for an additional argument to Desktops.OpenDoc *)
	PROCEDURE GetOpenLabel(VAR open: ARRAY OF CHAR);
		VAR S: Texts.Scanner;
	BEGIN
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			COPY(S.s, open)
		ELSE
			COPY("", open)
		END
	END GetOpenLabel;
	
	(* get values for label open *)
	PROCEDURE GetLInts(D: Documents.Document; open: ARRAY OF CHAR);
		VAR
			il: Books0.ImpList;
			el: Books0.ExtLabel;
	BEGIN
		IF open # "" THEN
			NEW(il);
			il.next := NIL;
			il.extLabels := NIL;
			COPY(D.name, il.name);
			IF ~Import(il, FALSE) THEN
				HALT(99)
			END;
			el := il.extLabels;
			WHILE (el # NIL) & (el.name # open) DO
				el := el.next
			END;
			IF (el # NIL) & (el.mode = Books.link) THEN
				Books.newInd := el.pos1;
				Books.newPos := el.pos2
			END
		END
	END GetLInts;
	
	(* load the document: D.name; TRUE: success; FALSE: error *)
	PROCEDURE LoadDoc(D: Documents.Document): BOOLEAN;
		VAR
			P: Books.Panel;
			tag, x, y, w, h: INTEGER;
			F: Files.File;
			R: Files.Rider;
			name: ARRAY 2*Books0.nameLen OF CHAR;
			open: ARRAY Books0.identLen OF CHAR;
			len, ind, pos: LONGINT;
			t: Books0.TextList;
			il, oldL: Books0.ImpList;
			T: Books.TGFrame;
	BEGIN
		oldL := Books0.loading;
		GetOpenLabel(open);
		Books0.error := FALSE;
		Books.NewPanel();
		P := Objects.NewObj(Books.Panel);
		P.doc := D;
		F := Files.Old(D.name);
		IF F = NIL THEN RETURN FALSE END;
		Files.Set(R, F, 0);
		Files.ReadInt(R, tag);
		IF tag = Documents.Id THEN
			Files.ReadString(R, name);
			Files.ReadInt(R, x); Files.ReadInt(R, y); 
			Files.ReadInt(R, w); Files.ReadInt(R, h)
		ELSE
			RETURN FALSE
		END;
		IF (Books.newInd < 0) OR (Books.newPos < 0) THEN
			Files.ReadLInt(R, Books.newInd); Files.ReadLInt(R, Books.newPos)
		ELSE
			Files.ReadLInt(R, len); Files.ReadLInt(R, len)
		END;
		Files.ReadSet(R, P.options);
		Files.ReadString(R, P.iconStr);
		IF Gadgets.FindPublicObj(P.iconStr) = NIL THEN
			COPY(defaultIcon, P.iconStr)
		END;
		Files.ReadLInt(R, len);
		Files.ReadLInt(R, len);
		Files.ReadLInt(R, len);
		P.X := x; P.Y := y; P.W := w; P.H := h;
		ind := 0;
		Files.ReadString(R, name);
		WHILE name # "" DO
			NEW(il);
			il.next := P.imps;
			P.imps := il;
			il.extLabels := NIL;
			il.ind := ind;
			INC(ind);
			COPY(name, il.name);
			IF ~Import(il, FALSE) THEN
				Texts.WriteString(Wr, "requires: ");
				Texts.WriteString(Wr, name);
				Texts.WriteLn(Wr);
				Texts.Append(Oberon.Log, Wr.buf);	
				RETURN FALSE
			END;
			Files.ReadString(R, name)
		END;
		NEW(il);
		il.next := P.imps;
		P.imps := il;
		il.extLabels := NIL;
		il.ind := ind;
		INC(ind);
		COPY(D.name, il.name);
		IF ~Import(il, FALSE) THEN
			HALT(99)
		END;
		Books0.loading := P.imps;
		Files.ReadLInt(R, len);
		WHILE len >= 0 DO
			NEW(t); NEW(t.text);
			Texts.Open(t.text, "");
			t.prev := P.cur; t.next := NIL;
			IF P.cur = NIL THEN
				P.texts := t
			ELSE
				P.cur.next := t
			END;
			P.cur := t;
			IF len > 0 THEN
				pos := Files.Pos(R)+1;
				Texts.Load(t.text, F, pos, len);
				IF Books0.error THEN
					Texts.WriteString(Wr, "error with fixup");
					Texts.WriteLn(Wr);
					Texts.Append(Oberon.Log, Wr.buf);	
					RETURN FALSE
				END;
				Files.Set(R, F, pos+len)
			END;
			Files.ReadLInt(R, len)
		END;
		P.notes := t.text;
		P.cmds := t.prev.text;
		t.prev.prev.next := NIL;
		t.prev.prev := NIL;
		t.prev.next := NIL;
		t.prev := NIL;
		t.next := NIL;
		GetLInts(D, open);
		BuildInterface(P);
		P.useStack := NIL;
		IF (w # W) & (Books.resize IN P.options) THEN
			Books.GetText(P, T);
			Books.ResizeControls(P, T, w-Books.borderL-Books.borderR-Books.scrollBW)
		END;
		D.X := x; D.Y := y; D.W := w; D.H := h;
		Documents.Init(D, P);
		IF Books.newInd > 0 THEN
			Books.GotoText(P, Books.newInd, Books.newPos, FALSE)
		END;
		Books.newInd := -1; Books.newPos := -1;
		Books0.loading := oldL;
		RETURN TRUE
	END LoadDoc;

	(* load the document: D.name; re-use data of already loaded tutorials, otherwise load it from file *)
	PROCEDURE *Load(D: Documents.Document);
		VAR
			obj: Objects.Object;
			M: ExistMsg;
			C: Objects.CopyMsg;
			P: Books.Panel;
			open: ARRAY Books0.identLen OF CHAR;
			T: Books.TGFrame;
	BEGIN
		M.F := NIL;
		COPY(D.name, M.name);
		M.res := -1;
		Display.Broadcast(M);
		IF (M.res >= 0) & (M.F # NIL) THEN
			C.id := Objects.deep;
			Objects.Stamp(C);
			C.obj := NIL;
			P := M.F(Documents.Document).dsc(Books.Panel);
			P.handle(P, C);
			P := C.obj(Books.Panel);
			P.doc := D;
			GetOpenLabel(open);
			IF (open = "") & (Books.newInd < 0) THEN
				open := "Open"
			END;
			GetLInts(D, open);
			D.W := M.F.W;
			D.H := M.F.H;
			Documents.Init(D, P);
			Books.GotoText(P, Books.newInd, Books.newPos, FALSE);
			IF Books.newPos >= 0 THEN
				Books.GetText(P, T);
				T.org := TextGadgets0.LinesUp(T.text, Books.newPos, 0);
				TextGadgets0.ScrollTo(T, TextGadgets0.LinesUp(T.text, Books.newPos, 0))
			END;
			Books.newInd := -1; Books.newPos := -1
		ELSIF ~LoadDoc(D) THEN
			TextDocs.NewDoc();
			obj := Objects.NewObj;
			D.handle := obj.handle;
			obj := Gadgets.CreateObject("TextGadgets.New");
			Texts.WriteString(Wr, "Can not load ");
			Texts.WriteString(Wr, D.name);
			Texts.WriteLn(Wr);
			Texts.Append(obj(TextGadgets.Frame).text, Wr.buf);
			Documents.Init(D, obj(Gadgets.Frame))
		END
	END Load;
	
	(* store D.name *)
	PROCEDURE *Store(D: Documents.Document);
		VAR
			F: Files.File;
			R: Files.Rider;
			P: Books.Panel;
	BEGIN
		IF ~(D.dsc IS Books.Panel) THEN
			RETURN
		END;
		F := Files.Old(D.name);
		IF F = NIL THEN
			Texts.WriteString(Wr, D.name);
			Texts.WriteString(Wr, " old file not found");
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf);
			RETURN
		END;
		Files.Set(R, F, 0);
		P := D.dsc(Books.Panel);
		WriteHeaderP(R, P)
	END Store;
	
(* printing of tutorial-documents *)

	(* look for f in printFrames *)
	PROCEDURE SearchFrame(f: Books0.Frame): FrameList;
		VAR l: FrameList;
	BEGIN
		l := printFrames;
		WHILE (l # NIL) & (l.frame # f) DO
			l := l.next
		END;
		RETURN l
	END SearchFrame;

	(* print number at (X, Y) *)
	PROCEDURE PrintInt(nr: LONGINT; X, Y: INTEGER);
		VAR
			str: ARRAY 8 OF CHAR;
	BEGIN
		Strings.IntToStr(nr, str);
		Printer.String(X, Y, str, Fonts.Default)
	END PrintInt;

	(* overridden PrintLine-"method" for TextGadgets.Frame; translates Books0.Frame to page numbers *)
	PROCEDURE *PrintLine(F: TextGadgets0.Frame; M: Display3.Mask; x, y: INTEGER; org: LONGINT; L: TextGadgets0.Line; dlink: Objects.Object);
		VAR
			Fi: Texts.Finder;
			obj: Objects.Object;
			l: FrameList;
			pos: LONGINT;
	BEGIN
		Texts.OpenFinder(Fi, F.text, org);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj);
		WHILE ~Fi.eot & ~(obj IS Books0.LocFrame) & (pos <= (org+L.len)) DO
			pos := Fi.pos;
			Texts.FindObj(Fi, obj)
		END;
		TextGadgets.methods.Print(F, M, x, y, org, L, dlink);
		IF (pos <= (org+L.len)) & (obj # NIL) & (obj IS Books0.LocFrame) THEN
			WITH obj: Books0.LocFrame DO
				l := SearchFrame(obj);
				IF l = NIL THEN RETURN END;
				IF obj.mode = Books.link THEN
					PrintInt(l.page, TextGadgets0.PrinterleftX+printerTab+(Printer.Width DIV 10), L.base)
				END
			END
		END
	END PrintLine;
	
	(* calculate an absolute position for the ind & pos pair; used for page number fixup *)
	PROCEDURE AbsPos(P: Books.Panel; ind, pos: LONGINT): LONGINT;
		VAR
			t: Books0.TextList;
			apos: LONGINT;
	BEGIN
		apos := pos;
		t := P.texts.next;
		WHILE ind > 1 DO
			apos := apos+t.text.len;
			DEC(ind);
			t := t.next
		END;
		RETURN apos
	END AbsPos;

	(* fixup all frames with absolute position >= beg to page number pageNr *)
	PROCEDURE Fixup(beg, pageNr: LONGINT);
		VAR lF: FrameList;
	BEGIN
		lF := printFrames;
		WHILE lF # NIL DO
			IF lF.pos >= beg THEN
				lF.page := pageNr
			END;
			lF := lF.next
		END
	END Fixup;

	(* PrintText similar to TextGadgets0.PrintText; calculates page numbers, maximal width *)
	PROCEDURE PrintText(T: TextGadgets.Frame; print, fix: BOOLEAN; VAR pageNr, maxW: LONGINT);
		VAR
			org, oldOrg: LONGINT;
			L: TextGadgets0.Line;
			Y: INTEGER;
			output: BOOLEAN;
			R: Display3.Mask;
			break: BOOLEAN;
	BEGIN
		R := NIL;
		org := 0; oldOrg := 0; maxW := 0;
		Y := TextGadgets0.PrintertopY;
		NEW(L); output := FALSE;
		LOOP
			IF L.eot THEN EXIT END;
			T.do.PrintFormat(T, org, L, break);
			IF (L.w > maxW) & (L.w < Printer.Width) THEN
				maxW := L.w
			END;
			IF Y - L.h < TextGadgets0.PrinterbotY THEN
				IF fix THEN
					Fixup(oldOrg, pageNr)
				END;
				oldOrg := org;
				IF print THEN
					PrintInt(pageNr, printerRight, printerTop);
					Printer.Page(1)
				END;
				INC(pageNr);
				Y := TextGadgets0.PrintertopY;
				output := FALSE
			END;
			DEC(Y, L.asr); L.base := Y;
			IF print THEN
				T.do.Print(T, R, TextGadgets0.PrinterleftX(*!! 0 *), 0, org, L, NIL)
			END;
			output := TRUE; DEC(Y, L.dsr); INC(org,  L.len);
		END;
		IF output THEN
			IF fix THEN
				Fixup(oldOrg, pageNr)
			END;
			IF print THEN
				PrintInt(pageNr, printerRight, printerTop);
				Printer.Page(1)
			END;
			INC(pageNr)
		END;
	END PrintText;

	(* replaces footnote references by numbers *)
	PROCEDURE BuildNotesPrintList(t: Texts.Text);
		VAR
			lF, lF2, lastF: FrameList;
			Fi: Texts.Finder;
			obj: Objects.Object;
			pos, nr: LONGINT;
		PROCEDURE SearchSame(f: Books0.Frame): FrameList;
			VAR
				lF: FrameList;
				a, b: Books0.LocFrame;
				c, d: Books0.ExtFrame;
		BEGIN
			lF := printFrames;
			LOOP
				IF lF = NIL THEN EXIT END;
				IF ABS(lF.frame.mode) = f.mode THEN
					IF (f IS Books0.LocFrame) & (lF.frame IS Books0.LocFrame) THEN
						a := f(Books0.LocFrame); b := lF.frame(Books0.LocFrame);
						IF (a.pos1 = b.pos1) & (a.pos2 = b.pos2) THEN
							EXIT
						END
					ELSIF  (f IS Books0.ExtFrame) & (lF.frame IS Books0.ExtFrame) THEN
						c := f(Books0.ExtFrame); d := lF.frame(Books0.ExtFrame);
						IF c.imp = d.imp THEN
							EXIT
						END
					END
				END;
				lF := lF.next
			END;
			RETURN lF
		END SearchSame;
	BEGIN
		lastF := NIL;
		lF := printFrames;
		WHILE lF # NIL DO
			lastF := lF;
			lF := lF.next
		END;
		nr := 1;
		Texts.OpenFinder(Fi, t, 0);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj);
		WHILE ~Fi.eot DO
			IF (obj IS Books0.Frame) & (ABS(obj(Books0.Frame).mode) = Books.note) THEN
				NEW(lF);
				lF.frame := obj(Books0.Frame);
				IF lF.frame.mode < 0 THEN
					lF2 := SearchFrame(lF.frame);
					lF.pos := lF2.pos
				ELSE
					lF2 := SearchSame(lF.frame);
					lF.frame.mode := -lF.frame.mode;
					IF lF2 # NIL THEN
						lF.pos := lF2.pos
					ELSE
						lF.pos := nr;
						INC(nr)
					END
				END;
				lF.next := NIL;
				lastF.next := lF;
				lastF := lF;
				Texts.Write(Wr, "[");
				Texts.WriteInt(Wr, lF.pos, 0);
				Texts.Write(Wr, "]");
				Texts.Insert(t, pos+1, Wr.buf);
				Texts.OpenFinder(Fi, t, pos+4)
			END;
			pos := Fi.pos;
			Texts.FindObj(Fi, obj)
		END
	END BuildNotesPrintList;
	
	(* copy footnote-numbers of popups to t; used for notes appendix *)
	PROCEDURE CopyNotes(t, popups: Texts.Text);
		VAR
			lF: FrameList;
			f: Books0.Frame;
			style: TextGadgets.Style;
			nr: LONGINT;
	BEGIN
		Texts.WriteString(Wr, "Appendix: Notes");
		Texts.WriteLn(Wr); Texts.WriteLn(Wr);
		Texts.Append(t, Wr.buf);
		Texts.ChangeLooks(t, 0, t.len, {Books.looksLib}, sectionFonts[0], 0, 0);
		style := TextGadgets.newStyle();
		style.width := printerPageW;
		Books0.AppendFrame(t, style);
		lF := printFrames; nr := 0;
		WHILE lF # NIL DO
			f := lF.frame;
			IF ABS(f.mode) = Books.note THEN
				IF (f.mode < 0) & (lF.pos > nr) THEN
					INC(nr);
					Texts.Write(Wr, "[");
					Texts.WriteInt(Wr, lF.pos, 0);
					Texts.Write(Wr, "]");
					Texts.Write(Wr, Books.Tab);
					Texts.Append(t, Wr.buf);
					IF f IS Books0.LocFrame THEN
						Texts.Save(popups, f(Books0.LocFrame).pos1, f(Books0.LocFrame).pos2, B)
					ELSIF f IS Books0.ExtFrame THEN
						Texts.Save(f(Books0.ExtFrame).imp.book.notes, f(Books0.ExtFrame).imp.pos1, f(Books0.ExtFrame).imp.pos2, B)	
					END;
					Texts.Append(t, B);
					Texts.WriteLn(Wr);
					Texts.WriteLn(Wr);
					Texts.WriteLn(Wr);
					Texts.Append(t, Wr.buf)
				END;
				f.mode := Books.note
			END;
			lF := lF.next
		END
	END CopyNotes;
	
	(* count tabs beginning at beg *)
	PROCEDURE CountTabs(t: Texts.Text; beg: LONGINT): INTEGER;
		VAR
			R: Texts.Reader;
			ch: CHAR;
			i: INTEGER;
	BEGIN
		i := 0;
		Texts.OpenReader(R, t, beg);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.lib IS Fonts.Font) & (ch = Books.Tab) DO
			INC(i);
			Texts.Read(R, ch)
		END;
		RETURN i
	END CountTabs;

	(* add nTabs tabs to each line beginning in the text stretch (beg, end) in t *)
	PROCEDURE AddTabs(t: Texts.Text; beg, end: LONGINT; nTabs: INTEGER);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			i: INTEGER;
	BEGIN
		Texts.OpenReader(R, t, beg);
		Texts.Read(R, ch);
		WHILE ~R.eot & (Texts.Pos(R) < end) DO
			i := nTabs;
			WHILE i > 0 DO
				Texts.Write(Wr, Books.Tab);
				DEC(i)
			END;
			end := end+nTabs;
			Texts.Insert(t, Texts.Pos(R), Wr.buf);
			Texts.OpenReader(R, t, Texts.Pos(R)+nTabs);
			Texts.Read(R, ch);
			WHILE ~R.eot & ~((R.lib IS Fonts.Font) & (ch = Books.EOL)) DO
				Texts.Read(R, ch)
			END;
			IF ~R.eot THEN
				Texts.Read(R, ch)
			END
		END
	END AddTabs;
	
	(* get the value of checkbox name *)
	PROCEDURE CheckBox(name: ARRAY OF CHAR): BOOLEAN;
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.FindObj(Gadgets.context, name);
		IF (obj # NIL) & (obj IS BasicGadgets.CheckBox) THEN
			RETURN obj(BasicGadgets.CheckBox).val
		ELSE
			RETURN FALSE
		END
	END CheckBox;

	(* print D.dsc, options: /all, /cur *)
	PROCEDURE GetPrintMode(D: Documents.Document);
		VAR
			S: Texts.Scanner;
			P: Books.Panel;
	BEGIN
		prMode := {all};
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		REPEAT
			Texts.Scan(S)
		UNTIL S.eot OR ((S.class = Texts.Char) & (S.c = Oberon.OptionChar));
		P := D.dsc(Books.Panel);
		IF (S.class = Texts.Char) & (S.c = Oberon.OptionChar) THEN
			Texts.Scan(S);
			IF ~((S.class = Texts.Name) & (CAP(S.s[0]) = "C")) THEN
				INCL(prMode, all)
			ELSE
				EXCL(prMode, all)
			END
		END;
		IF Gadgets.context # NIL THEN
			Gadgets.context := Gadgets.context.dlink;
			IF CheckBox("Current") THEN
				prMode := {}
			END
		END;
		IF (prMode = {}) & (P.cur.prev = NIL) THEN
			INCL(prMode, cont)
		END
	END GetPrintMode;
			
	(* prepare printing of D *)
	PROCEDURE PreparePrintDoc(D: Documents.Document);
		VAR
			P: Books.Panel;
			Tf: Books.TGFrame;
			nTabs: INTEGER;
			Fi, Fi2: Texts.Finder;
			lF: FrameList;
			tl: Books0.TextList;
			obj, obj2: Objects.Object;
			beg, end, oldPageNr, maxW: LONGINT;
			wr: BOOLEAN;
			R: Texts.Reader;
			ch: CHAR;
	BEGIN
		P := D.dsc(Books.Panel);
		Books.GetText(P, Tf);
		oldW := Tf.W;
		Books.ResizeControls(P, NIL, printerPageW);
		printFrames := NIL; index := NIL;
		Tcont := NIL; T := NIL; Tindex := NIL; Tnotes := NIL;
		pageNr := 0; maxW := 0; maxWi := 0; maxWc := 0;
		printerTab := printerWMiddle;
		Texts.OpenFinder(Fi, P.texts.text, 0);
		Texts.FindObj(Fi,obj);
		WHILE ~Fi.eot DO
			IF obj IS Books0.LocFrame THEN
				NEW(lF); lF.page := -1;
				lF.pos := AbsPos(P, obj(Books0.LocFrame).pos1, obj(Books0.LocFrame).pos2);
				lF.frame := obj(Books0.LocFrame);
				lF.next := printFrames;
				printFrames := lF
			END;
			Texts.FindObj(Fi, obj)
		END;
		tl := Books.GetIndex(P);
		Texts.OpenFinder(Fi, tl.text, 0);
		Texts.FindObj(Fi,obj);
		WHILE ~Fi.eot DO
			IF (obj IS Books0.LocFrame) & (obj(Books0.LocFrame).mode = Books.link) THEN
				NEW(lF); lF.page := -1;
				lF.pos := AbsPos(P, obj(Books0.LocFrame).pos1, obj(Books0.LocFrame).pos2);
				lF.frame := obj(Books0.LocFrame);
				lF.next := printFrames;
				printFrames := lF
			END;
			Texts.FindObj(Fi, obj)
		END;
		
		Texts.WriteString(Wr, "contents ");
		Texts.Append(Oberon.Log, Wr.buf);
		TextGadgets.New();
		Tcont := Objects.NewObj(TextGadgets.Frame);
		Texts.OpenFinder(Fi, P.texts.text, 0);
		beg := Fi.pos;
		Texts.FindObj(Fi, obj);
		WHILE ~Fi.eot & ~(obj IS Books0.ContElem) DO
			beg := Fi.pos;
			Texts.FindObj(Fi, obj)
		END;
		end := Fi.pos;
		Texts.FindObj(Fi, obj2);
		WHILE ~Fi.eot & ~(obj2 IS Books0.ContElem) DO
			end := Fi.pos;
			Texts.FindObj(Fi, obj2)
		END;	
		Texts.Save(P.texts.text, beg+1, end, B);
		Texts.Append(Tcont.text, B);
		Texts.Save(P.texts.text, obj(Books0.ContElem).beg, obj(Books0.ContElem).end, B);
		Texts.Append(Tcont.text, B);
		Texts.OpenFinder(Fi, Tcont.text, 0);
		beg := Fi.pos;
		Texts.FindObj(Fi, obj);
		WHILE ~Fi.eot DO
			IF obj IS Books0.ContElem THEN
				Texts.Delete(Tcont.text, beg, beg+1);
				IF obj(Books0.ContElem).mode = Books0.node THEN
					Texts.OpenFinder(Fi, Tcont.text, beg+1);
					nTabs := CountTabs(Tcont.text, beg);
					Texts.Save(P.texts.text, obj(Books0.ContElem).beg, obj(Books0.ContElem).end, B);
					Texts.OpenFinder(Fi2, Tcont.text, beg+1);
					beg := Fi2.pos;
					Texts.Insert(Tcont.text, beg+2, B);
					AddTabs(Tcont.text, beg+2, beg+2+obj(Books0.ContElem).end-obj(Books0.ContElem).beg, nTabs+1)
				ELSE
					Texts.OpenFinder(Fi, Tcont.text, beg+1)
				END
			ELSIF obj IS Books0.LocFrame THEN
				index := SearchFrame(obj(Books0.LocFrame))
			END;
			beg := Fi.pos;
			Texts.FindObj(Fi, obj);
		END;
		(* why?
		TextGadgets0.FormatFrame(Tcont);
		*)
		pageNr := 0;
		IF cont IN prMode THEN
			RETURN
		END;
		PrintText(Tcont, FALSE, FALSE, pageNr, maxWc);
		
		Texts.WriteString(Wr, "texts ");
		Texts.Append(Oberon.Log, Wr.buf);
		TextGadgets.New();
		T := Objects.NewObj(TextGadgets.Frame);
		
		tl := P.texts.next;
		WHILE tl.next # NIL DO
			Texts.Save(tl.text, 0, tl.text.len, B);
			Texts.Append(T.text, B);
			tl := tl.next
		END;
		
		IF Books.usesnotes IN P.options THEN
			BuildNotesPrintList(T.text)
		END;
		(*TextGadgets0.FormatFrame(T);  This should not be here ! why ? *)
		PrintText(T, FALSE, TRUE, pageNr, maxW);
		
		Texts.WriteString(Wr, "index ");
		Texts.Append(Oberon.Log, Wr.buf);
		TextGadgets.New();
		Tindex := Objects.NewObj(TextGadgets.Frame);
		tl := Books.GetIndex(P);
		Texts.OpenReader(R, tl.text, 0);
		beg := 0; end := 0;
		Texts.Read(R, ch);
		WHILE ~R.eot DO
			wr := FALSE;
			IF ~(R.lib IS Fonts.Font) THEN
				Texts.OpenFinder(Fi, tl.text, Texts.Pos(R)-1);
				Texts.FindObj(Fi, obj);
				IF (obj # NIL) & (obj IS Books0.LocFrame) & (obj(Books0.LocFrame).mode = Books.note) THEN
					oldPageNr := 0
				ELSE
					oldPageNr := -1
				END
			ELSIF (R.lib IS Fonts.Font) & (ch = Books.Tab) THEN
				end := Texts.Pos(R);
				Texts.Save(tl.text, beg, end-1, B);
				Texts.Append(Tindex.text, B);
				Texts.Read(R, ch);
				Texts.Write(Wr, Books.Tab);
				WHILE ~((R.lib IS Fonts.Font) & (ch = Books.EOL)) DO
					WHILE R.lib IS Fonts.Font DO
						Texts.Read(R, ch)
					END;
					Texts.OpenFinder(Fi, tl.text, Texts.Pos(R)-1);
					Texts.FindObj(Fi, obj);
					IF (oldPageNr < 0) & (obj # NIL) & (obj IS Books0.LocFrame) & (obj(Books0.LocFrame).mode = Books.link) THEN
						lF := SearchFrame(obj(Books0.Frame));
						oldPageNr := lF.page;
						Texts.FindObj(Fi, obj)
					END;
					IF (obj # NIL) & (obj IS Books0.LocFrame) & (obj(Books0.LocFrame).mode = Books.link) THEN
						lF := SearchFrame(obj(Books0.Frame));
						IF  lF.page # oldPageNr THEN
							IF wr THEN
								Texts.WriteString(Wr, ", ")
							END;
							wr := TRUE;
							Texts.WriteInt(Wr, lF.page, 0);
							oldPageNr := lF.page
						END
					END;
					Texts.Read(R, ch)
				END;
				Texts.WriteLn(Wr);
				IF (oldPageNr >= 0) & wr THEN
					Texts.Append(Tindex.text, Wr.buf)
				ELSE
					Texts.OpenWriter(Wr)
				END;
				beg := Texts.Pos(R)
			END;
			Texts.Read(R, ch)
		END;
		end := tl.text.len;
		Texts.Save(tl.text, beg, end, B);
		Texts.Append(Tindex.text, B);
		(* why?
		TextGadgets0.FormatFrame(Tindex);
		*)
		oldPageNr := pageNr;
		PrintText(Tindex, FALSE, FALSE, pageNr, maxWi);
		index.page := oldPageNr;
		
		IF Books.usesnotes IN P.options THEN
			Texts.WriteString(Wr, "notes");
			Texts.Append(Oberon.Log, Wr.buf);
			TextGadgets.New();
			Tnotes := Objects.NewObj(TextGadgets.Frame);
			CopyNotes(Tnotes.text, P.notes);
			(* why ?
			TextGadgets0.FormatFrame(Tnotes);
			*)
			beg := Tcont.text.len;
			Texts.WriteLn(Wr); Texts.Write(Wr, Books.Tab);
			Texts.WriteString(Wr, "Appendix: Notes");
			Texts.Append(Tcont.text, Wr.buf);
			Texts.ChangeLooks(Tcont.text, beg, Tcont.text.len, {Books.looksLib}, sectionFonts[0], 0, 0);
			NEW(lF);
			lF.next := printFrames; printFrames := lF;
			Books0.NewLoc();
			lF.frame := Objects.NewObj(Books0.Frame);
			lF.frame.mode := Books.link;
			lF.page := pageNr;
			Books0.AppendFrame(Tcont.text, lF.frame)
		END;
		(* why?
		TextGadgets0.FormatFrame(Tcont)
		*)
	END PreparePrintDoc;
	
	(* print the allready prepared tutorial D *)
	PROCEDURE DoPrintDoc(D: Documents.Document);
		VAR
			p, w: LONGINT;
			m: TextGadgets0.Methods;
			P: Books.Panel;
	BEGIN
		IF Tcont = NIL THEN
			Texts.WriteLn(Wr);
			Texts.WriteString(Wr, "Use BookDocs.PrintDoc to print a tutorial.");
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf);
			RETURN
		END;
		NEW(m);
		m^ := TextGadgets.methods^;
		m.Print := PrintLine;
		P := D.dsc(Books.Panel);
		p := 0; w := 0;
		
		IF T = NIL THEN
			PrintText(Tcont, TRUE, FALSE, p, w);
			RETURN
		END;
				
		IF Printer.res # 0 THEN RETURN END;
		Texts.WriteString(Wr, "contents ");
		Texts.Append(Oberon.Log, Wr.buf);
		printerTab := SHORT(maxWc);
		Tcont.do := m;
		PrintText(Tcont, TRUE, FALSE, p, w);
		
		IF Printer.res # 0 THEN RETURN END;
		Texts.WriteString(Wr, "texts ");
		Texts.Append(Oberon.Log, Wr.buf);
		PrintText(T, TRUE, FALSE, p, w);
		
		IF Printer.res # 0 THEN RETURN END;
		Texts.WriteString(Wr, "index ");
		Texts.Append(Oberon.Log, Wr.buf);
		Tindex.do := m;
		printerTab := SHORT(maxWi);
		PrintText(Tindex, TRUE, FALSE, p, w);
		
		IF Tnotes # NIL THEN
			IF Printer.res # 0 THEN RETURN END;
			Texts.WriteString(Wr, "notes");
			Texts.Append(Oberon.Log, Wr.buf);
			PrintText(Tnotes, TRUE, FALSE, p, w)
		END;
				
		printFrames := NIL; index := NIL;
		Tcont := NIL; T := NIL; Tindex := NIL; Tnotes := NIL;
		pageNr := 0; maxWi := 0; maxWc := 0;
		prMode := {all};
		Books.ResizeControls(P, NIL, oldW-Books.borderL-Books.borderR-Books.scrollBW)
	END DoPrintDoc;
		
	(* handler for tutorial documents *)
	PROCEDURE DocHandler*(D: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, H, butH: INTEGER;
			T, Tn: Books.TGFrame;
			P: Books.Panel;
			il: Books0.ImpList;
	BEGIN
		WITH D: Documents.Document DO
			IF (D.dsc # NIL) & (D.dsc(Books.Panel).doc = NIL) THEN
				D.dsc(Books.Panel).doc := D
			END;
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					P := D.dsc(Books.Panel);
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "BookDocs.NewDoc";
							M.res := 0
						ELSIF M.name = "Adaptive" THEN
							M.class := Objects.Bool;
							M.b := FALSE;
							M.res := 0
						ELSIF M.name = "Icon" THEN
							M.class := Objects.String;
							IF Books.icon IN P.options THEN
								COPY(D.dsc(Books.Panel).iconStr, M.s)
							ELSE
								M.s := defaultIcon
							END;
							M.res := 0
						ELSE Documents.Handler(D, M)
						END
					ELSE Documents.Handler(D, M)
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF (M.name = "SystemMenu") OR (M.name = "UserMenu") OR (M.name = "DeskMenu") THEN
							M.obj := Desktops.NewMenu(Menu); M.res := 0
						ELSE Documents.Handler(D, M)
						END
					ELSE Documents.Handler(D, M)
					END
				END
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = D) THEN
						IF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								P := D.dsc(Books.Panel);
								IF ~(Gadgets.selected IN D.state) & ~(Gadgets.selected IN P.state) & (M.id = Oberon.track) & (M.keys # {}) THEN
									IF Books.twoRow IN P.options THEN
										butH := 2*Books.buttonH
									ELSE
										butH := Books.buttonH
									END;
									x := M.x+D.X+Books.borderL;
									y := M.y+D.Y+(Books.borderB+butH+Books.barH+P.noteH+Books.barH);
									Books.GetText(P, T);
									Books.GetNote(P, Tn);
(* ejz 20.2.95 *)
									IF Effects.Inside(M.X, M.Y, x, y, 12 (* T.left *), T.H) THEN
										M.F := T; M.dlink := P;
										M.x := x-T.X; M.y := y-T.Y-1;
										T.handle(T, M); M.res := 0
									ELSE
										y := M.y+D.Y+(Books.borderB+butH+Books.barH);
(* ejz 20.2.95 *)
										IF Effects.Inside(M.X, M.Y, x, y, 12 (* Tn.left *), Tn.H) THEN
											M.F := Tn; M.dlink := P;
											M.x := x-Tn.X; M.y := y-Tn.Y-1;
											Tn.handle(Tn, M); M.res := 0
										ELSE Documents.Handler(D, M)
										END
									END
								ELSE Documents.Handler(D, M)
								END
							END
						ELSIF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF (M.device = Display.printer) & (D.dsc # NIL) THEN
									IF M.id = Display.contents THEN
										IF prMode = {} THEN
											P := D.dsc(Books.Panel);
											Books.GetText(P, T);
											TextGadgets0.PrintText(T, D.name)
										ELSE DoPrintDoc(D)
										END
									ELSIF M.id = prepare THEN (* prepare the document first *)
										GetPrintMode(D);
										IF prMode # {} THEN
											PreparePrintDoc(D)
										END
									ELSE Documents.Handler(D, M)
									END
								ELSE Documents.Handler(D, M)
								END
							END
						ELSIF (M IS ExistMsg) & (M.F = NIL) THEN
							IF ~(Books.invalid IN D.dsc(Books.Panel).options) & (M(ExistMsg).name = D.name) THEN
								M.F := D;
								M.res := 0
							END
						ELSIF (M IS ExistImpMsg) & (M.F = NIL) & ~(Books.invalid IN D.dsc(Books.Panel).options) THEN
							il := D.dsc(Books.Panel).imps;
							WHILE (il # NIL) & (il.name # M(ExistImpMsg).name) DO
								il := il.next
							END;
							IF il # NIL THEN
								M(ExistImpMsg).il := il;
								M.F := D;
								M.res := 0
							END
						ELSIF (M IS InValMsg) & (M.F = NIL) THEN
							IF ~(Books.invalid IN D.dsc(Books.Panel).options) & (M(InValMsg).name = D.name) THEN
								INCL(D.dsc(Books.Panel).options, Books.invalid)
							ELSIF M(InValMsg).name # D.name THEN
								il := D.dsc(Books.Panel).imps;
								WHILE (il # NIL) & (il.name # M(InValMsg).name) DO
									il := il.next
								END;
								IF il # NIL THEN
									INCL(D.dsc(Books.Panel).options, Books.invalid)
								END
							END
						ELSIF M IS VisibleMsg THEN
							WITH M: VisibleMsg DO
								IF M.F = D THEN
									M.visible := TRUE;
									M.res := 0
								END
							END
						ELSE Documents.Handler(D, M)
						END
					ELSIF (M.F = D.dsc) & (M IS Display.ModifyMsg) THEN
						WITH M: Display.ModifyMsg DO
							IF M.W < (4*Books.buttonW-2) THEN
								M.dW := M.dW + (4*Books.buttonW-M.W);
								M.W := 4*Books.buttonW-2
							END;
							IF M.H < (2*Books.buttonH+3*Books.barH+2*50) THEN
								H := 2*Books.buttonH+3*Books.barH+2*50;
								M.dY := M.dY - (H-M.H);
								M.dH := M.dH + H-M.H;
								M.Y := M.Y - (H-M.H);
								M.H := H
							END
						END;
						Documents.Handler(D, M)
					ELSE Documents.Handler(D, M)
					END
				END
			ELSE Documents.Handler(D, M)
			END
		END
	END DocHandler;

	PROCEDURE NewDoc*;
		VAR D: Documents.Document;
	BEGIN
		NEW(D);
		D.Load := Load;
		D.Store := Store;
		D.handle := DocHandler;
		D.W := W; D.H := H;
		Objects.NewObj := D
	END NewDoc;

(* commands for tutorials *)

	(* Back button *)
	PROCEDURE Pop*;
		VAR P: Books.Panel;
	BEGIN
		Books.GetPanel(P);
		Books.Pop(P)
	END Pop;

	(* Next button *)
	PROCEDURE Next*;
		VAR P: Books.Panel;
	BEGIN
		Books.GetPanel(P);
		IF (P # NIL) & (P.cur.next # NIL) THEN
			Books.Push(P);
			Books.ShowText(P, P.cur.next, 0)
		END
	END Next;
	
	(* Prev button *)
	PROCEDURE Prev*;
		VAR P: Books.Panel;
	BEGIN
		Books.GetPanel(P);
		IF (P # NIL) & (P.cur.prev # NIL) THEN
			Books.Push(P);
			Books.ShowText(P, P.cur.prev, 0)
		END
	END Prev;

	(* Contents button *)
	PROCEDURE Contents*;
		VAR P: Books.Panel;
	BEGIN
		Books.GetPanel(P);
		IF P # NIL THEN
			Books.Push(P);
			Books.ShowText(P, P.texts, 0)
		END
	END Contents;

	(* Index button *)
	PROCEDURE Index*;
		VAR P: Books.Panel;
	BEGIN
		Books.GetPanel(P);
		IF P # NIL THEN
			Books.Push(P);
			Books.ShowText(P, Books.GetIndex(P), 0)
		END
	END Index;

	PROCEDURE RemoveStyles(t: Texts.Text);
		VAR
			Fi: Texts.Finder;
			obj: Objects.Object;
			pos: LONGINT;
	BEGIN
		Texts.OpenFinder(Fi, t, 0);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj);
		WHILE ~Fi.eot DO
			IF obj IS TextGadgets.Style THEN
				Texts.Delete(t, pos, pos+1);
				Texts.OpenFinder(Fi, t, pos)
			END;
			pos := Fi.pos;
			Texts.FindObj(Fi, obj)
		END
	END RemoveStyles;
	
	(* History button *)
	PROCEDURE History*;
		VAR
			P: Books.Panel;
			T: Books.TGFrame;
			t: Texts.Text;
	BEGIN
		Books.GetPanel(P);
		Books.GetNote(P, T);
		IF T # NIL THEN
			NEW(t); Texts.Open(t, "");
			Books.History(P, t);
			Texts.ChangeLooks(t, 0, t.len, {Books.looksLib, Books.looksCol}, linkFont, Books.linkCol, 0);
			RemoveStyles(t);
			Texts.WriteString(Wr, "History");
			Texts.WriteLn(Wr);
			Texts.Insert(t, 0, Wr.buf);
			Texts.ChangeLooks(t, 0, 7, {Books.looksLib}, titleFont, 0, 0);
			Texts.Delete(T.text, 0, T.text.len);
			Texts.Save(t, 0, t.len, B);
			Texts.Append(T.text, B)
		END
	END History;
	
	PROCEDURE GetItem(VAR P: Books.Panel): Books0.ExtLabel;
		VAR
			il: Books0.ImpList;
			el: Books0.ExtLabel;
			S: Texts.Scanner;
	BEGIN
		Books.GetPanel(P);
		IF P = NIL THEN RETURN NIL END;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "*") THEN
			Texts.Scan(S)
		END;
		IF ~(S.class = Texts.Name) THEN RETURN NIL END;
		NEW(il);
		il.next := NIL;
		il.extLabels := NIL;
		COPY(P.doc.name, il.name);
		IF Import(il, FALSE) THEN
			el := il.extLabels;
			WHILE (el # NIL) & (el.name # S.s) DO
				el := el.next
			END;
			IF el = NIL THEN
				Texts.WriteString(Wr, S.s);
				Texts.WriteString(Wr, " ident not found");
				Texts.WriteLn(Wr);
				Texts.Append(Oberon.Log, Wr.buf)
			END
		END;
		RETURN el
	END GetItem;
	
	(* execute a link as command (e.g. from a button) *)
	PROCEDURE DoLink*;
		VAR
			P: Books.Panel;
			el: Books0.ExtLabel;
	BEGIN
		el := GetItem(P);
		IF el = NIL THEN
			RETURN
		ELSIF el.mode # Books.link THEN
			Texts.WriteString(Wr, el.name);
			Texts.WriteString(Wr, " not a label");
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf)
		ELSE
			Books.GotoText(P, el.pos1, el.pos2, TRUE)
		END
	END DoLink;
	
	(* show a footnote as command (e.g. from a button) *)
	PROCEDURE DoNote*;
		VAR
			P: Books.Panel;
			el: Books0.ExtLabel;
	BEGIN
		el := GetItem(P);
		IF el = NIL THEN
			RETURN
		ELSIF el.mode # Books.note THEN
			Texts.WriteString(Wr, el.name);
			Texts.WriteString(Wr, " not a footnote");
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf)
		ELSE
			Books.ShowFootNote(P, el.pos1, el.pos2)
		END
	END DoNote;
	
(* searching on tutorial-documents *)

	(* check if tutorial doc is visible, otherwise reopen it *)
	PROCEDURE ShowDoc(doc: Documents.Document);
		VAR V: VisibleMsg;
	BEGIN
		V.F := doc;
		V.visible := FALSE;
		Display.Broadcast(V);
		IF ~V.visible THEN
			Desktops.ShowDoc(doc)
		END
	END ShowDoc;

	(* mark ordinary text pattern found *)
	PROCEDURE MarkPatPos(P: Books.Panel; tF: TextGadgets.Frame; pos: LONGINT);
	BEGIN
		ShowDoc(P.doc);
		TextGadgets0.Locate(tF, pos);
		TextGadgets0.RemoveCaret(tF);
		TextGadgets0.SetSelection(tF, pos - sPatLen, pos);
		lTime := tF.time
	END MarkPatPos;

	(* mark colored text found *)
	PROCEDURE MarkColPos(P: Books.Panel; tF: TextGadgets.Frame; VAR pos: LONGINT; col: INTEGER);
		VAR
			R: Texts.Reader;
			ch: CHAR;
	BEGIN
		ShowDoc(P.doc);
		TextGadgets0.Locate(tF, pos);
		TextGadgets0.RemoveCaret(tF);
		Texts.OpenReader(R, tF.text, pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.col = col) DO
			Texts.Read(R, ch)
		END;
		TextGadgets0.SetSelection(tF, pos-1, Texts.Pos(R));
		pos := Texts.Pos(R)+1;
		lTime := tF.time
	END MarkColPos;

	(* mark object found *)
	PROCEDURE MarkObj(P: Books.Panel; tF: TextGadgets.Frame; pos: LONGINT; obj: Objects.Object);
	BEGIN
		ShowDoc(P.doc);
		TextGadgets0.Locate(tF, pos);
		TextGadgets0.RemoveCaret(tF);
		IF (obj IS Gadgets.Frame) & (obj(Gadgets.Frame).W = 0) THEN
			TextGadgets0.SetSelection(tF, pos, pos+2)
		ELSE
			TextGadgets0.SetSelection(tF, pos, pos+1)
		END
	END MarkObj;
	
	(* calculate displacement vector *)
	PROCEDURE CalcDispVec(time: LONGINT);
		VAR i, j, d: INTEGER;
	BEGIN
		lTime := time;
		i := 1; d := 1;
		WHILE i <= sPatLen DO
			j := 0;
			WHILE (j + d < sPatLen) & (sPat[j] = sPat[j + d]) DO
				INC(j)
			END;
			WHILE i <= j + d DO
				sDv[i] := d; INC(i)
			END;
			INC(d)
		END
	END CalcDispVec;
	
	(* returns string length *)
	PROCEDURE StrLen(VAR str: ARRAY OF CHAR): INTEGER;
		VAR i: INTEGER;
	BEGIN
		i := 0;
		WHILE (i < LEN(str)) & (str[i] # 0X) DO
			INC(i)
		END;
		RETURN i
	END StrLen;
	
	(* searches the next position for the color col, begining at position pos *)
	PROCEDURE SearchColor(text: Texts.Text; VAR pos: LONGINT; col: INTEGER): BOOLEAN;
		VAR
			R: Texts.Reader;
			ch: CHAR;
	BEGIN
		IF pos > text.len THEN
			RETURN FALSE
		END;
		Texts.OpenReader(R, text, pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.col # col) DO
			Texts.Read(R, ch)
		END;
		IF R.eot THEN
			pos := text.len;
			RETURN FALSE
		ELSE
			pos := Texts.Pos(R);
			RETURN TRUE
		END
	END SearchColor;

	(* searches the next position for the search pattern sPat (and col), begining at position pos *)
	PROCEDURE SPatFound(text: Texts.Text; VAR pos: LONGINT; mode: SET; col: INTEGER): BOOLEAN;
		VAR
			R: Texts.Reader;
			l: LONGINT;
			i: INTEGER;
			ch: CHAR;
	BEGIN
		IF sPatLen > 0 THEN
			Texts.OpenReader(R, text, pos);
			Texts.Read(R, ch);
			INC(pos);
			l := text.len; i := 0;
			WHILE (i # sPatLen) & (pos <= l) DO
				IF ch = sPat[i] THEN
					INC(i);
					IF i < sPatLen THEN Texts.Read(R, ch); INC(pos) END
				ELSIF i = 0 THEN Texts.Read(R, ch); INC(pos)
				ELSE DEC(i, sDv[i])
				END
			END;
		ELSIF col IN mode THEN
			RETURN SearchColor(text, pos, col)
		ELSE i := -1
		END;
		IF ~(color IN mode) THEN
			RETURN i = sPatLen
		ELSE
			IF (i = sPatLen) & (R.col = col) THEN
				RETURN TRUE
			ELSIF pos < l THEN
				RETURN SPatFound(text, pos, mode, col)
			ELSE
				RETURN FALSE
			END
		END
	END SPatFound;
	
	(* searches for the next object (newProc, name, col) in the text, begining at position pos *)
	PROCEDURE SearchObj(T: Texts.Text; VAR pos: LONGINT; mode: SET; VAR newProc, name: ARRAY OF CHAR; col: INTEGER; VAR obj: Objects.Object): BOOLEAN;
		VAR
			Fi: Texts.Finder;
			match: BOOLEAN;
			str: ARRAY 64 OF CHAR;
			A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get;
		A.name := "Gen";
		Texts.OpenFinder(Fi, T, pos);
		pos := Fi.pos;
		Texts.FindObj(Fi,obj);
		LOOP
			IF Fi.eot THEN obj := NIL; RETURN FALSE END;
			IF obj IS Gadgets.Frame THEN
(* jt removed				WITH obj: Gadgets.Frame DO	*)
					match := TRUE;
					IF color IN mode THEN
						match := (* !!! obj.col*) Display.FG = col
					END;
					IF match & (text IN mode) THEN
						Gadgets.GetObjName(obj, str);
						match := str = name
					END;
					IF match & (object IN mode) & (newProc # "") THEN
						A.s := "";
						A.res := -1;
						obj.handle(obj, A);
						match := A.s = newProc
					END;
					IF match THEN
						RETURN TRUE
					END
			END;
			pos := Fi.pos;
			Texts.FindObj(Fi, obj)
		END
	END SearchObj;
	
	(* initiates a normal shallow search *)
	PROCEDURE ShallowSearch(P: Books.Panel; VAR pos: LONGINT): BOOLEAN;
		VAR
			S: Texts.Scanner;
			T: Books.TGFrame;
			tl: Books0.TextList;
			R: Texts.Reader;
			t: Texts.Text;
			beg, end, time: LONGINT;
			i: INTEGER;
			mode: SET;
			Text, Object: ARRAY MaxPatLen OF CHAR;
			Color: INTEGER;
			obj: Objects.Object;
		PROCEDURE TextField(name: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
			VAR obj: Objects.Object;
		BEGIN
			obj := Gadgets.FindObj(Gadgets.context, name);
			IF (obj # NIL) & (obj IS TextFields.TextField) THEN
				COPY(obj(TextFields.TextField).val, text)
			ELSE
				text[0] := 0X
			END
		END TextField;
		PROCEDURE Rect(name: ARRAY OF CHAR): INTEGER;
			VAR obj: Objects.Object;
		BEGIN
			obj := Gadgets.FindObj(Gadgets.context, name);
			IF (obj # NIL) & (obj IS Gadgets.Frame) THEN
				RETURN (* !!! obj(Gadgets.Frame).col *) Display.FG
			ELSE
				RETURN MIN(INTEGER)
			END
		END Rect;
		PROCEDURE Next(VAR tl: Books0.TextList);
		BEGIN
			IF tl.next = NIL THEN
				tl := P.texts.next
			ELSE
				tl := tl.next
			END
		END Next;
		PROCEDURE SelObj(name: ARRAY OF CHAR);
			VAR
				obj: Objects.Object;
				M: Display.SelectMsg;
				A: Objects.AttrMsg;
		BEGIN
			obj := Gadgets.FindObj(Gadgets.context, name);
			M.id := Display.get;
			M.F := NIL;
			M.obj := NIL;
			M.time := -1;
			Display.Broadcast(M);
			IF (M.time > 0) & (M.obj # NIL) & (obj # NIL) & (obj IS TextFields.TextField) THEN
				A.id := Objects.get;
				A.name := "Gen";
				A.res := -1;
				Objects.Stamp(A);
				M.obj.handle(M.obj, A);
				IF A.res >= 0 THEN
					COPY(A.s, obj(TextFields.TextField).val);
					Gadgets.Update(obj)
				END
			END
		END SelObj;
	BEGIN
		Books.GetText(P, T);
		IF T # NIL THEN
			lastDoc := P.doc;
			mode := {};
			Text := ""; Color := MIN(INTEGER); Object := "";
			Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
			Texts.Scan(S);
			IF (S.class = Texts.Char) & (S.c = "*") THEN
				IF CheckBox("object") THEN
					INCL(mode, object);
					TextField("Object", Object);
					IF Object = "" THEN
						SelObj("Object")
					END
				END;
				IF CheckBox("text") THEN
					INCL(mode, text);
					TextField("Text", Text)
				END;
				IF CheckBox("color") THEN
					INCL(mode, color);
					Color := Rect("Color")
				END
			ELSE
				mode := {text}
			END;
			IF object IN mode THEN
				tl := P.cur;
				pos := T.lastPos;
				IF ~(tl.prev = NIL) & SearchObj(tl.text, pos, mode, Object, Text, Color, obj) THEN
					MarkObj(P, T, pos, obj);
					T.lastPos := pos+1;
					RETURN TRUE
				ELSE
					T.lastPos := 0;
					Next(tl);
					pos := 0;
					WHILE (tl # P.cur) & ~SearchObj(tl.text, pos, mode, Object, Text, Color, obj) DO
						Next(tl);
						pos := 0
					END;
					IF tl # P.cur THEN
						Books.Push(P);
						Books.ShowText(P, tl, pos);
						MarkObj(P, T, pos, obj);
						T.lastPos := pos+1;
						RETURN TRUE
					ELSE
						TextGadgets0.RemoveSelection(T)
					END
				END
			ELSIF text IN mode THEN
				IF Text = "" THEN
					t := NIL;
					Oberon.GetSelection(t, beg, end, time);
					IF (t # NIL) & (time > lTime) THEN
						Texts.OpenReader(R, t, beg);
						i := 0; pos := beg;
						REPEAT
							Texts.Read(R, sPat[i]); INC(i); INC(pos)
						UNTIL (i = MaxPatLen) OR (pos = end);
						sPatLen := i;
						CalcDispVec(time)
					END
				ELSE
					COPY(Text, sPat);
					sPatLen := StrLen(sPat);
					CalcDispVec(Oberon.Time())
				END;
				tl := P.cur;
				pos := T.lastPos;
				IF ~(tl.prev = NIL) & SPatFound(tl.text, pos, mode, Color) THEN
					MarkPatPos(P, T, pos);
					T.lastPos := pos;
					RETURN TRUE
				ELSE
					T.lastPos := 0;
					Next(tl);
					pos := 0;
					WHILE (tl # P.cur) & ~SPatFound(tl.text, pos, mode, Color) DO
						Next(tl);
						pos := 0
					END;
					IF tl # P.cur THEN
						Books.Push(P);
						Books.ShowText(P, tl, pos);
						MarkPatPos(P, T, pos);
						T.lastPos := pos;
						RETURN TRUE
					ELSE
						TextGadgets0.RemoveSelection(T)
					END
				END
			ELSIF color IN mode THEN
				tl := P.cur;
				pos := T.lastPos;
				IF ~(tl.prev = NIL) & SearchColor(tl.text, pos, Color) THEN
					MarkColPos(P, T, pos, Color);
					T.lastPos := pos;
					RETURN TRUE
				ELSE
					T.lastPos := 0;
					Next(tl);
					pos := 0;
					WHILE (tl # P.cur) & ~SearchColor(tl.text, pos, Color) DO
						Next(tl);
						pos := 0
					END;
					IF tl # P.cur THEN
						Books.Push(P);
						Books.ShowText(P, tl, pos);
						MarkColPos(P, T, pos, Color);
						T.lastPos := pos;
						RETURN TRUE
					ELSE
						TextGadgets0.RemoveSelection(T)
					END
				END
			END
		END;
		RETURN FALSE
	END ShallowSearch;

	(* initiates a deep search *)
	PROCEDURE DeepSearch(P: Books.Panel);
		VAR pos: LONGINT;
		PROCEDURE Search(name: ARRAY OF CHAR): DocList;
			VAR d: DocList;
		BEGIN
			d := docList;
			WHILE (d # NIL) & (d.doc.name # name) DO
				d := d.next
			END;
			RETURN d
		END Search;
		PROCEDURE Visit(doc: Documents.Document);
			VAR
				d: DocList;
				il: Books0.ImpList;
		BEGIN
			IF Search(doc.name) = NIL THEN
				NEW(d); d.next := docList; docList := d;
				d.doc := doc; d.cur := NIL; d.pos := -1;
				il := doc.dsc(Books.Panel).imps;
				WHILE il # NIL DO
					IF Search(il.name) = NIL THEN
						NEW(d); 
						d.next := docList; docList := d;
						d.cur := NIL; d.pos := -1;
						d.doc := Documents.Open(il.name);
						Visit(d.doc)
					END;
					il := il.next
				END
			END
		END Visit;
	BEGIN
		IF Search(P.doc.name) = NIL THEN
			docList := NIL;
			Visit(P.doc);
			lastDeep := docList
		ELSIF lastDeep = NIL THEN
			lastDeep := docList
		END;
		P := lastDeep.doc.dsc(Books.Panel);
		WHILE (lastDeep # NIL) & ~ShallowSearch(P, pos) DO
			lastDeep := lastDeep.next;
			IF lastDeep # NIL THEN
				P := lastDeep.doc.dsc(Books.Panel)
			ELSE
				P := NIL
			END
		END;
		IF lastDeep = NIL THEN
		ELSIF (P.cur = lastDeep.cur) & (pos = lastDeep.pos) THEN
			lastDeep.pos := -1;
			lastDeep := lastDeep.next
		ELSIF lastDeep.pos <= 0 THEN
			lastDeep.cur := P.cur;
			lastDeep.pos := pos
		ELSE
		END
	END DeepSearch;
	
	(* Search command: initiates either a ShallowSearch or a DeepSearch *)
	PROCEDURE Search*;
		VAR
			P: Books.Panel;
			V: VisibleMsg;
			pos: LONGINT;
	BEGIN
		Books.GetPanel(P);
		IF (P = NIL ) & (lastDoc # NIL) THEN
			V.F := lastDoc;
			V.visible := FALSE;
			Display.Broadcast(V);
			IF V.visible THEN
				P := lastDoc.dsc(Books.Panel)
			ELSE
				lastDoc := NIL
			END
		END;
		IF P = NIL THEN RETURN END;
		IF CheckBox("deep") THEN
			DeepSearch(P)
		ELSE
			docList := NIL; lastDeep := NIL;
			IF ShallowSearch(P, pos) THEN END
		END
	END Search;
	
(* CopyToFile FileName label1 label2 *)
	PROCEDURE CopyToFile*;
		VAR
			S: Texts.Scanner;
			P: Books.Panel;
			fname: ARRAY Books0.nameLen OF CHAR;
			lname1, lname2: ARRAY Books0.identLen OF CHAR;
			pos1, pos2, ind: LONGINT;
			F: Files.File;
			il: Books0.ImpList;
			el: Books0.ExtLabel;
	BEGIN
		Books.GetPanel(P);
		IF (P = NIL) & (Oberon.Par.obj # NIL) & (Oberon.Par.obj IS Books.TGFrame) THEN
			P := Oberon.Par.obj(Books.TGFrame).panel
		END;
		IF P = NIL THEN
			RETURN
		END;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "*") THEN
			Texts.Scan(S)
		END;
		IF S.class = Texts.Name THEN
			COPY(S.s, fname)
		ELSE
			RETURN
		END;
		pos1 := -1; pos2 := -1;
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			COPY(S.s, lname1)
		ELSIF S.class = Texts.Int THEN
			pos1 := S.i
		ELSE
			RETURN
		END;
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			COPY(S.s, lname2)
		ELSIF S.class = Texts.Int THEN
			pos2 := S.i
		ELSE
			RETURN
		END;
		IF (pos1 = -1) & (pos2 = -1) THEN
			NEW(il); COPY(P.doc.name, il.name); il.extLabels := NIL;
			IF Import(il, TRUE) THEN
				ind := Books.GetInd(P, P.cur);
				el := il.extLabels;
				WHILE el # NIL DO
					IF (el.mode = Books.link) & (el.pos1 = ind) THEN
						IF el.name = lname1 THEN
							pos1 := el.pos2
						ELSIF el.name = lname2 THEN
							pos2 := el.pos2
						END
					END;
					el := el.next
				END
			END
		END;
		IF (pos2 > pos1) & (pos1 >= 0) & (pos2 <= P.cur.text.len) THEN
			F := Files.New(fname);
			IF F # NIL THEN
				Texts.Delete(tmpT, 0, tmpT.len);
				Texts.Save(P.cur.text, pos1, pos2, B);
				Texts.Append(tmpT, B);
				Texts.Store(tmpT, F, 0, pos2);
				Files.Register(F)
			END
		END
	END CopyToFile;

(* replacement for Desktops.PrintDoc, sends prepare first*)
	PROCEDURE PrintDoc*;
		VAR
			D: Documents.Document;
			msg: Display.DisplayMsg;
			S: Texts.Scanner;
	BEGIN
		D := Documents.MarkedDoc();
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (D # NIL) & (S.class = Texts.Name) THEN
			Texts.WriteString(Wr, "BookDocs.PrintDoc ");
			Texts.WriteString(Wr, S.s);
			Texts.Write(Wr, " ");
			Texts.WriteString(Wr, D.name);
			Texts.WriteLn(Wr);
			Texts.WriteString(Wr, "preparing: ");
			Texts.Append(Oberon.Log, Wr.buf);
			
			Printer.Open(S.s, "");
			
			TextGadgets0.PrintertopY := Printer.Height DIV 10 * 9;
			TextGadgets0.PrinterbotY := Printer.Height DIV 20;
			TextGadgets0.PrinterleftX := Printer.Width DIV 10;
			TextGadgets0.HeaderY := Printer.Height DIV 20 * 19; TextGadgets0.PagenoX := Printer.Width DIV 10 *  9;

			(* important ! *)
			printerPageW := ((Printer.Width DIV SHORT(Display.Unit DIV Printer.Unit)) DIV 10)*8;
			printerTop := (Printer.Height DIV 20)*19;
			printerRight := (Printer.Width DIV 20)*19;
			printerWMiddle := Printer.Width DIV 2;
			printerTab := printerWMiddle;
	
			msg.F := D;
			msg.device := Display.printer;
			msg.id := prepare;
			msg.res := -1;
			D.handle(D, msg);
			Texts.WriteLn(Wr);
			Texts.WriteString(Wr, "printing: ");
			Texts.Append(Oberon.Log, Wr.buf);
			
			(* too late !!
			Printer.Open(S.s, Oberon.User, Oberon.Password);
			
			TextGadgets0.PrintertopY := Printer.Height DIV 10 * 9;
			TextGadgets0.PrinterbotY := Printer.Height DIV 20;
			TextGadgets0.PrinterleftX := Printer.Width DIV 10;
			TextGadgets0.HeaderY := Printer.Height DIV 20 * 19; TextGadgets0.PagenoX := Printer.Width DIV 10 *  9;
			*)
			msg.F := D;
			msg.device := Display.printer;
			msg.id := Display.contents;
			msg.res := -1;
			D.handle(D, msg);
			IF Printer.res # 0 THEN
				Texts.WriteString(Wr, " printer state: ");
				Texts.WriteInt(Wr, Printer.res, 8)
			ELSE
				Texts.WriteString(Wr, " Ok")
			END;
			Printer.Close();
			Texts.WriteLn(Wr);
			Texts.Append(Oberon.Log, Wr.buf)
		END
	END PrintDoc;

BEGIN
	GetFonts();
	NEW(B);
	Texts.OpenBuf(B);
	Texts.OpenWriter(Wr);
	NEW(tmpT); Texts.Open(tmpT, "");
	lTime := -1; sPatLen := 0; sPat := "";
	lastDoc := NIL;
	lastDeep := NIL;
	docList := NIL;
	printFrames := NIL; index := NIL;
	Tcont := NIL; T := NIL; Tindex := NIL; Tnotes := NIL;
	pageNr := 0; maxWi := 0; maxWc := 0;
	prMode := {all}; oldW := 0
END BookDocs.

System.Free BookDocs
