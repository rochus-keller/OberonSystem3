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

MODULE Finder;	(** portable *) (* ejz 3.1.95 / jm - adapted for ver 1.6 / ps extended *)

	IMPORT
		Input,  Objects, Fonts, Display, Printer, Display3, Printer3, Pictures, Viewers, Texts, Oberon, Effects,
		Gadgets, Views, ListRiders, ListGadgets, Documents, Desktops;

	CONST
		ListModel = "ListModels.NewList";
		NoName = "Untitled document";
		FinderSection = "FinderTemplates";
		FontName = "Oberon16b.Scn.Fnt";

	TYPE
		Template = POINTER TO TemplateDesc;
		TemplateDesc = RECORD
			next: Template;
			name: ARRAY 32 OF CHAR;
			docName: ARRAY 128 OF CHAR
		END;

		Separator = POINTER TO SeparatorDesc;
		SeparatorDesc = RECORD (ListRiders.StringDesc)
		END;

		Entry = POINTER TO EntryDesc;
		EntryDesc = RECORD (ListRiders.StringDesc)
			doc: Desktops.DocGadget;
			open: BOOLEAN
		END;

		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			R: ListRiders.Rider;
			pict: Pictures.Picture;
			open: BOOLEAN
		END;

		FindMsg = RECORD (Display.FrameMsg)
			desk: Desktops.DocViewer;
			finder: Frame;
			cnt: INTEGER
		END;

	VAR
		pict: Pictures.Picture;
		templates, last: Template;
		methods: ListGadgets.Method;
		W: Texts.Writer;

	PROCEDURE * FormatLine (F: ListGadgets.Frame; R: ListRiders.Rider; L: ListGadgets.Line);
	VAR e: Entry;
	BEGIN
		IF R.d IS Entry THEN
			e := R.d(Entry);
			Display3.StringSize(e.s, F.fnt, L.w, L.h, L.dsr);
			IF (e.doc # NIL) & (L.h < 16 + 2) THEN INC(L.dsr, (16 + 2 - 1 - L.h) DIV 2); L.h := 16 + 2 END;
			L.dx := 16 + 2
		ELSIF R.d IS Separator THEN
			L.w := 0; L.h := 6; L.dsr := 0; L.dx := 0
		ELSE ListGadgets.FormatLine(F, R, L)
		END
	END FormatLine;

	PROCEDURE * DisplayLine (F: ListGadgets.Frame; Q: Display3.Mask; x, y, w, h: INTEGER; R: ListRiders.Rider; L: ListGadgets.Line);
	VAR e: Entry; obj, D: Objects.Object; Y: INTEGER; A: Objects.AttrMsg; LM: Objects.LinkMsg;
	BEGIN
		IF R.d IS Entry THEN
			e := R.d(Entry);
			Display3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
			(* draw an icon *)
			IF e.doc # NIL THEN D := Desktops.Main(e.doc) ELSE D := NIL END;
			IF D # NIL THEN
				A.id := Objects.get; A.name := "Icon"; A.res := -1; D.handle(D, A);
				IF A.res >= 0 THEN
					obj := Gadgets.FindPublicObj(A.s);
					LM.id := Objects.get; LM.name := "Model";
					WHILE (obj # NIL) & ~(obj IS Pictures.Picture) DO
						LM.obj := NIL; LM.res := -1; obj.handle(obj, LM); obj := LM.obj
					END;
					IF (obj # NIL) & (obj IS Pictures.Picture) THEN
						Y := y + (h - 16) DIV 2;
						WITH obj: Pictures.Picture DO
							Pictures.Copy(obj, pict, 0, 0, obj.width, obj.height, 0, 0, 16, 16, Display.replace)
						END;
						Display3.Pict(Q, pict, 0, 0, 16 ,16, x, Y, Display.replace)
					END
				END
			END;
			INC(x, 16 + 2);
			IF e.open THEN Display3.String(Q, 3, x, y + L.dsr, F.fnt, e.s, Display.paint)
			ELSIF e.doc # NIL THEN Display3.String(Q, 8, x, y + L.dsr, F.fnt, e.s, Display.paint)
			ELSE Display3.String(Q, Display3.textC, x, y + L.dsr, F.fnt, e.s, Display.paint)
			END
		ELSIF R.d IS Separator THEN
			Display3.ReplConst(Q, F.backC, x, y, w, h, Display.replace);
			w :=  F.W - 10;
			Display3.ReplConst(Q, Display3.black, x, y+2, w, 1, Display.replace);
			Display3.ReplConst(Q, Display3.white, x, y+3, w, 1, Display.replace)
		ELSE ListGadgets.DisplayLine(F, Q, x, y, w, h, R, L)
		END
	END DisplayLine;

	PROCEDURE GetRider (F: Frame);
	VAR obj: Objects.Object; M: ListRiders.ConnectMsg;
	BEGIN
		obj := Gadgets.CreateObject(ListModel);
		IF obj # NIL THEN M.R := NIL; obj.handle(obj, M); F.R := M.R
		ELSE F.R := NIL
		END
	END GetRider;

	PROCEDURE RemoveFrame (F: Display.Frame);
	VAR C: Display.ControlMsg;
	BEGIN C.F := F; C.id := Display.remove; Display.Broadcast(C)
	END RemoveFrame;

	PROCEDURE InsertFrame (this, context: Display.Frame; u, v: INTEGER);
	VAR C: Display.ControlMsg; D: Display.ConsumeMsg;
	BEGIN
		C.id := Display.restore; C.x := 0; C.y := 0; C.dlink := NIL; C.res := -1; C.F := this;
		this.handle(this, C);
		D.id := Display.drop; D.F := context; D.obj := this; D.u := u; D.v := v; D.res := -1;
		Display.Broadcast(D)
	END InsertFrame;

	PROCEDURE ListDocs (F: Frame; context: Display.Frame): Display.Frame;
		VAR
			list: ListGadgets.Frame;
			doc, frame: Display.Frame;
			e: Entry; s: Separator;
			t: Template;
			W, R: ListRiders.Rider;
			maxW, addW, strW, strH, strDsr: INTEGER;
			inserted: BOOLEAN;
			A: Objects.AttrMsg;
			L: Objects.LinkMsg;
			C: ListRiders.ConnectMsg;
	BEGIN
		ListGadgets.NewFrame;
		list := Objects.NewObj(ListGadgets.Frame); list.do := methods;
		list.H := 200;
		A.id := Objects.set; A.class := Objects.Bool;
		A.name := "MultiSel"; list.handle(list, A);
		A.name := "ExtendSel"; list.handle(list, A);
		A.class := Objects.String; A.name := "Cmd"; A.s := "Finder.BringToFront"; list.handle(list, A);
		L.id := Objects.set; L.name := "Model"; L.obj := Gadgets.CreateObject(ListModel); list.handle(list, L);
		A.id := Objects.set; A.class := Objects.Bool; A.name := "Sorted"; A.b := FALSE; L.obj.handle(L.obj, A);
		C.R := NIL; L.obj.handle(L.obj, C); W := C.R;
		maxW := F.W; addW := 16 + 2 + 2 + list.left + list.right;

		(* add open docs *)
		frame := context.dsc; inserted := FALSE;
		WHILE frame # NIL DO
			IF frame IS Desktops.DocGadget THEN
				inserted := TRUE;
				NEW(e); e.doc := frame(Desktops.DocGadget); e.open := TRUE;
				doc := Desktops.Main(frame(Desktops.DocGadget));
				IF doc(Documents.Document).name = "" THEN e.s := NoName
				ELSE COPY(doc(Documents.Document).name, e.s)
				END;
				Display3.StringSize(e.s, list.fnt, strW, strH, strDsr); INC(strW, addW);
				IF strW > maxW THEN maxW := strW END;
				W.do.Write(W, e)
			END;
			frame := frame.next
		END;
		IF inserted THEN NEW(s); W.do.Write(W, s) END;

		(* add minimized docs *)
		R := F.R; R.do.Set(R, 0); inserted := FALSE;
		WHILE ~R.eol DO
			inserted := TRUE;
			NEW(e);
			e.doc := R.d(Entry).doc; COPY(R.d(Entry).s, e.s); e.open := FALSE;
			Display3.StringSize(e.s, list.fnt, strW, strH, strDsr); INC(strW, addW);
			IF strW > maxW THEN maxW := strW END;
			W.do.Write(W, e);
			R.do.Set(R, R.do.Pos(R)+1)		
		END;
		IF inserted THEN NEW(s); W.do.Write(W, s) END;

		(* add doc templates *)
		t := templates;
		WHILE t # NIL DO
			NEW(e); e.doc := NIL; e.open := FALSE; COPY(t.name, e.s);
			Display3.StringSize(e.s, list.fnt, strW, strH, strDsr); INC(strW, addW);
			IF strW > maxW THEN maxW := strW END;
			W.do.Write(W, e);
			t := t.next
		END;
		list.W := maxW;
		RETURN list
	END ListDocs;

	PROCEDURE CalcPlace (x, y: INTEGER; VAR px, py, w, h: INTEGER);
		VAR cx, cy, cw, ch: INTEGER;
	BEGIN
		cx := 10; cy := 10; cw := Display.Width - 10; ch := Display.Height - 10;
		px := x; py := y - h;
		IF px < cx THEN px := cx; END;
		IF px + w >= cx + cw THEN px := cx + cw - 1 - w; END;
		IF py < cy THEN py := cy; END;
		IF py + h >= cy + ch THEN py := cy + ch - 1 - h END;
	END CalcPlace;

	PROCEDURE PopupList (F: Frame; VAR M: Oberon.InputMsg);
	VAR dlink: Objects.Object; list: Display.Frame; block: Views.Block; keysum: SET; px, py: INTEGER;
		C: Display.ControlMsg; D: Display.DisplayMsg; O: Display3.OverlapMsg;
	BEGIN
		list := ListDocs(F, M.dlink(Display.Frame));

		CalcPlace(M.x + F.X, M.y + F.Y + F.H, px, py, list.W, list.H);
		Views.GetBlock(px, py, list.W, list.H, M.dlink, block);
		C.id := Display.restore; C.F := NIL; C.x := 0; C.y := 0; C.res := -1; C.dlink := NIL;
		list.handle(list, C);
		O.F := list; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL;
		list.handle(list, O);
		D.device := Display.screen; D.id := Display.full; D.F := list; D.res := -1; 
		D.x := px - list.X; D.y := py - list.Y; D.dlink := M.dlink;
		list.handle(list, D);
		dlink := F.dlink; F.dlink := M.dlink;
		Input.Mouse(M.keys, M.X, M.Y); keysum := M.keys;
		WHILE (M.keys # {}) & (M.res < 0) DO
			M.x := px - list.X; M.y := py - list.Y; M.dlink := F; list.handle(list, M);
			Input.Mouse(M.keys, M.X, M.Y); keysum := keysum + M.keys; 
			Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
		END;
		F.dlink := dlink;
		Oberon.FadeCursor(Oberon.Mouse);
		Views.RestoreBlock(block)
	END PopupList;

	PROCEDURE Consume (doc: Desktops.DocGadget);
	VAR D: Objects.Object; t: Template; name: ARRAY 128 OF CHAR;
	BEGIN
		D := Desktops.Main(doc);
		IF D # NIL THEN
			COPY(D(Documents.Document).name, name);
			t := templates;
			WHILE (t # NIL) & (t.name # name) DO t := t.next END;
			IF t = NIL THEN
				NEW(t);
				COPY(name, t.name);
				t.next := templates; templates := t
			END;
			COPY(name, t.docName);
			(*Registry.Set(FinderSection, name, name);
			Texts.WriteString(W, "added "); Texts.Write(W, 22X); Texts.WriteString(W, name);
			Texts.Write(W, 22X); Texts.WriteLn(W);*)
			Texts.WriteString(W, "Edit Gadgets.FinderTemplates section in Oberon.Text");  Texts.WriteLn(W);
			Texts.Write(W, 9X);  Texts.WriteString(W, name);  Texts.WriteString(W, " = ");  Texts.Write(W, 22X);
			Texts.WriteString(W, name);  Texts.Write(W, 22X);  Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END Consume;

	PROCEDURE Restore (F: Frame; Q: Display3.Mask; x, y, w, h: INTEGER);
	VAR X, Y: INTEGER;
	BEGIN
		IF ~F.open THEN
			Display3.Rect3D(Q, Display3.bottomC, Display3.topC, x, y, w, h, 1, Display.replace);
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC, x+1, y+1, w-2, h-2, 1, Display.replace);
			IF F.pict # NIL THEN
				X := x + (w - F.pict.width) DIV 2; Y := y + (h - F.pict.height) DIV 2;
				Display3.Pict(Q, F.pict, 0, 0, F.pict.width, F.pict.height, X, Y, Display.replace)
			ELSE
				Display3.CenterString(Q, 9, x, y, w, h, Fonts.This(FontName), "F", Display.paint)
			END;
			IF Gadgets.selected IN F.state THEN
				Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
			END
		END
	END Restore;

	PROCEDURE Print (F: Frame; VAR M:Display.DisplayMsg);
		VAR w, h: INTEGER; Q: Display3.Mask;
	
		PROCEDURE P(X: INTEGER): INTEGER;
		BEGIN RETURN SHORT(Display.Unit*X DIV Printer.Unit)
		END P;

	BEGIN
		Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, Q);
		w := P(F.W); h := P(F.H);
		Printer3.Rect3D(Q, Display3.bottomC, Display3.topC, M.x, M.y, w, h, P(1), Display.replace);
		Printer3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.groupC,
			M.x + P(1), M.y + P(1), w - P(2), h - P(2), P(1), Display.replace);
		Printer3.CenterString(Q, 9, M.x, M.y, w, h, Fonts.This(FontName), "F", Display.paint)
	END Print;

	PROCEDURE CopyFrame* (VAR M: Objects.CopyMsg; from, to: Frame);
	BEGIN
	      GetRider(to); to.pict := from.pict;
          Gadgets.CopyFrame(M, from, to);
	END CopyFrame;

	PROCEDURE FrameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
	VAR Q: Display3.Mask; dlink: Objects.Object; F1: Frame; x, y, w, h, cnt: INTEGER; 
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y;
						w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Restore(F, Q, x, y, w, h)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										Restore(F, Q, x, y, w, h)
									END
								ELSIF M.device = Display.printer THEN Print(F, M)
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & (M.keys = {1}) & Gadgets.InActiveArea(F, M) & ~(Gadgets.selected IN F.state) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									F.open := TRUE; Oberon.RemoveMarks(x, y, w, h);
									PopupList(F, M);
									F.open := FALSE; 
									Gadgets.MakeMask(F, x, y, M.dlink, Q); Oberon.RemoveMarks(x, y, w, h); 
									Restore(F, Q, x, y, w, h)
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS FindMsg THEN
							WITH M: FindMsg DO
								(* first top most finder *)
								dlink := M.dlink; cnt := 0;
								WHILE (dlink # NIL) & ~(dlink IS Desktops.DocViewer) DO INC(cnt); dlink := dlink.dlink END;
								IF (M.desk = dlink) & (cnt < M.cnt) THEN M.finder := F; M.cnt := cnt END
							END
						ELSIF M IS Display.ConsumeMsg THEN
							WITH M: Display.ConsumeMsg DO
								IF M.id = Display.drop THEN
									IF M.obj IS Desktops.DocGadget THEN
										Consume(M.obj(Desktops.DocGadget));
										M.res := 0;
									ELSE Gadgets.framehandle(F, M)
									END
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String; M.s := "Finder.NewFrame"; M.res := 0
					ELSE
						Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
        			ELSE
          			NEW(F1); F.stamp := M.stamp; F.dlink := F1;
          			CopyFrame(M, F, F1);
          			M.obj := F1
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE NewFrame*;
	VAR F: Frame; obj: Objects.Object; C: Objects.CopyMsg; L: Objects.LinkMsg;
	BEGIN
		NEW(F); F.handle := FrameHandler;
		obj := Gadgets.FindPublicObj("Icons.Library");
		L.id := Objects.get; L.name := "Model";
		WHILE (obj # NIL) & ~(obj IS Pictures.Picture) DO
			L.obj := NIL; obj.handle(obj, L); obj := L.obj
		END;
		IF obj # NIL THEN
			C.id := Objects.shallow; C.obj := NIL; Objects.Stamp(C);
			obj.handle(obj, C);
			F.pict := C.obj(Pictures.Picture);
			F.W := F.pict.width + 4; F.H := F.pict.height + 4;
		ELSE
			F.W := 30; F.H := 30; F.pict := NIL;
		END;
		F.open := FALSE; GetRider(F);
		Objects.NewObj := F
	END NewFrame;

	(** Internal command, used to bring a document to front. *)
	PROCEDURE BringToFront*;
	VAR obj, list: Objects.Object; par: Oberon.ParList; e: Entry; t: Template; R: ListRiders.Rider; res: INTEGER;
			P: Gadgets.PriorityMsg; A: Objects.AttrMsg; L: Objects.LinkMsg; C: ListRiders.ConnectMsg;
	BEGIN
		list := Gadgets.executorObj;
		L.id := Objects.get; L.name := "Model"; L.res := -1; list.handle(list, L);
		C.R := NIL;
		IF L.obj # NIL THEN L.obj.handle(L.obj, C) END;
		IF C.R # NIL THEN
			A.id := Objects.get; A.name := "PointKey"; A.res := -1; list.handle(list, A);
			IF A.res >= 0 THEN
				C.R.do.Seek(C.R, A.i);
				IF (C.R.d # NIL) & (C.R.d IS Entry) THEN
					e := C.R.d(Entry);
					IF e.open THEN	(* already open *)
						P.id := 0; P.F := e.doc; Display.Broadcast(P)
					ELSIF e.doc # NIL THEN	(* open minimized doc *)
						obj := Gadgets.executorObj;
						IF obj # NIL THEN
							IF obj.dlink # NIL THEN
								IF obj.dlink.dlink # NIL THEN
									InsertFrame(e.doc, obj.dlink.dlink(Display.Frame), e.doc.X, e.doc.Y)
								END;
								R := obj.dlink(Frame).R;
								R.do.Set(R, 0);
							LOOP
								IF R.eol THEN EXIT END;
								IF (R.d IS Entry) & (R.d(Entry).doc = e.doc) THEN
									R.do.DeleteLink(NIL, R);
									EXIT
								END;
								R.do.Set(R, R.do.Pos(R) + 1)	
							END	(* LOOP *)
						END	(* IF *)
						END	(* IF *)
					ELSE	(* open a new document *)
						t := templates;
						WHILE (t # NIL) & (t.name # e.s) DO t := t.next END;
						IF t # NIL THEN
							NEW(par);
							par.vwr := Oberon.Par.vwr; par.frame := Oberon.Par.frame; par.obj := Oberon.Par.obj;
							NEW(par.text); Texts.Open(par.text, ""); par.pos := 0;
							Texts.WriteString(W, t.docName); Texts.Append(par.text, W.buf);
							Oberon.Call("Desktops.OpenDoc", par, FALSE, res)
						END
					END	(* IF *)
				END
			END
		END
	END BringToFront;

	(**
		Minimizes a document. In the track system, the document will be moved to the bottom as far
		as possible. In the desktop, the document is removed and an entry (green color) is added to
		the desktops finder. *)
	PROCEDURE Minimize*;
	VAR obj: Objects.Object; V: Viewers.Viewer; Y, cnt: INTEGER; e: Entry; R: ListRiders.Rider;
			N: Display.ControlMsg; F: FindMsg;
	BEGIN
		obj := Gadgets.executorObj;
		WHILE (obj # NIL) & ~((obj IS Desktops.DocViewer) OR (obj IS Desktops.DocGadget)) DO obj := obj.dlink END;
		IF obj # NIL THEN
			IF obj IS Desktops.DocViewer THEN
				WITH obj: Desktops.DocViewer DO
					V := Viewers.This(obj.X, 0); cnt := 0;
					WHILE V.state # 1 DO INC(cnt); V := Viewers.Next(V) END;
					IF cnt > 1 THEN	(* more than one viewer in this track *)
						Viewers.Close(obj);
						Y := 0;
						REPEAT V := Viewers.This(obj.X, Y); INC(Y, V.H) UNTIL V.H > 43;
						Viewers.Open(obj, obj.X, Y - V.H + obj.menuH + 2);
						N.F := NIL; N.id := Display.restore; obj.handle(obj, N)
					ELSE	(* onlyone in this track *)
						Viewers.Change(obj, obj.menuH + 2);
						N.F := NIL; N.id := Display.restore; obj.handle(obj, N)
					END
				END
			ELSIF (Oberon.Par.vwr # NIL) & (Oberon.Par.vwr IS Desktops.DocViewer) THEN
				F.desk := Oberon.Par.vwr(Desktops.DocViewer);
				F.finder := NIL; F.cnt := MAX(INTEGER); Display.Broadcast(F);
				IF F.finder # NIL THEN	(* minimize and append to finders list *)
					R := F.finder.R;
					NEW(e);
					e.doc := obj(Desktops.DocGadget); e.open := FALSE;
					obj := Desktops.Main(obj(Desktops.DocGadget));
					IF obj(Documents.Document).name = "" THEN e.s := NoName
					ELSE COPY(obj(Documents.Document).name, e.s)
					END;
					R.do.Write(R, e);
					RemoveFrame(e.doc)
				END
			END
		END
	END Minimize;

	PROCEDURE * RegEnum (key, value: ARRAY OF CHAR);
	VAR t: Template;
	BEGIN
		NEW(t);  t.next := NIL;
		COPY(key, t.name); COPY(value, t.docName);
		IF templates = NIL THEN templates := t ELSE last.next := t END;
		last := t
	END RegEnum;

(*
	(**
		Reads the [FinderTemplates] section *)
	PROCEDURE UpdateTemplates*;
	BEGIN
		templates := NIL;
		Registry.Enumerate(FinderSection, RegEnum);
	END UpdateTemplates;
*)

	(**
		Reads the Gadgets.FinderTemplates section *)
	PROCEDURE UpdateTemplates*;
	VAR s: Texts.Scanner;  i: LONGINT;  name: ARRAY 64 OF CHAR;
	BEGIN
		templates := NIL;
		Oberon.OpenScanner(s, "Gadgets.FinderTemplates");
		IF s.class = Texts.Inval THEN
			Texts.WriteString(W, "Oberon.Text - Gadgets.FinderTemplates not found");  Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		WHILE s.class IN {Texts.Name, Texts.String} DO
			i := 0;
			WHILE s.s[i] # 0X DO
				IF s.s[i] = ":" THEN name[i] := " " ELSE name[i] := s.s[i] END;
				INC(i)
			END;
			name[i] := 0X;  Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = "=") THEN
				Texts.Scan(s);
				IF (s.class = Texts.Name) OR (s.class = Texts.String) THEN
					RegEnum(name, s.s);
					Texts.Scan(s)
				END
			ELSE s.class := Texts.Inval
			END
		END
	END UpdateTemplates;
	
BEGIN
	Texts.OpenWriter(W);
	NEW(pict); Pictures.Create(pict, 16, 16, 8);
	UpdateTemplates;
	NEW(methods);
	methods^ := ListGadgets.methods^;
	methods.Format := FormatLine; methods.Display := DisplayLine;
	methods.PrintFormat := ListGadgets. PrintFormatLine; methods.Print := ListGadgets.PrintLine
END Finder.

(** A Finder is used to quickly find a document among the many documents piled in a desktop and to place it on top of all others, open and ready. Moving the mouse focus to the finder and pressing the middle mouse key opens the Finder showing a list of document names from which one can be selected by moving the mouse focus up or down. When the mouse key is released, the selected document is brought to the front of the desktop and the finder is closed. Note however, if an open document is only partially visible it can be brought to the front by a simple left mouse click.

An open Finder in principle contains three sections: the top one lists the names of the open documents in blue, the middle one lists the minimized documents in green and the bottom one lists the documents contained in the Gadgets.FinderTemplates section of Oberon.Text. The names of open and minimized documents is taken from their NamePlates. The names include the full path specification and they are are preceded by a ideogram representing the document type. A document having an empty NamePlate appears as "Untitled document".

The names in the three lists have an order. In the list of open documents, the document placed deepest on the desktop appears first, while the document placed right on top appears last. The same order exists for the minimized documents, but that order is not relevant to the user since the documents can only be re-opened with the Finder. In the last list, the names appear in the order of their appearance in the Gadgets.FinderTemplates section, which may be cutomized at will. Each entry in this section must appear in a text line with the following format:

	Name = "documentName" | "documentType"

e.g. 'Gadgets = "Gadgets.Panel"' for the Gadgets.Panel or 'Text="(TextDocs.NewDoc)"' for an untitled text document.
*)
