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

MODULE Books;	(** portable *) (* ejz, further hacked by jm *)
	IMPORT Books0, Panels, Objects, Documents, Gadgets, Display, Display3, TextGadgets, TextGadgets0, BasicGadgets,
		Texts, Fonts, Oberon, Modules, Desktops, Effects;

	CONST
		(* some other special characters *)
		EOL* = 0DX; Tab* = 09X; quote* = CHR(34);

		(* constants used by Texts.ChangeLooks *)
		looksLib* = 0; looksCol* = 1;

		(* limit for chapter nesting *)
		maxSect* = 4;

		(* colors for special text *)
		linkCol* = 3 (*Display3.blue*); callCol* = 1(*Display3.red*); noteCol* = 8;
		(* more modes for Books0.Frame *)
		link* = 1; call* = 2; note* = 3;

		(* options for Panel *)
		formated* = 0; resize* = 1; icon* = 2; usesnotes* = 3; formatText* = 4; twoRow*= 5;
		invalid* = 15; left* = 16; middle* = 17; right* = 18; pad* = 19;
		(* constants used to draw a tutorial *)
		border* = 4;
		borderL* = 1; borderR* = 0;
		borderT* = 0; borderB* = 1;
		barH* = 4;
		buttonW* = 50; buttonH* = 20;
		scrollBW* = 25;
		
	TYPE
		TGFrame* = POINTER TO TGFrameDesc;
		Panel* = POINTER TO PanelDesc;
		Chain = POINTER TO ChainDesc;
		
		(* extended TextGadgets.Frame: lastPos: for searching; panel: easy find the owning panel *)
		TGFrameDesc* = RECORD (TextGadgets.FrameDesc)
			focus: BOOLEAN;
			lastPos*: LONGINT;
			panel*: Panel
		END;
		
		(* extended Panels.Panel: contains all data needed for a tutorial at runtime *)
		PanelDesc* = RECORD (Panels.PanelDesc)
			doc*: Documents.Document;
			iconStr*: ARRAY 2*Books0.nameLen OF CHAR;
			texts*, cur*: Books0.TextList;
			cmds*, notes*: Texts.Text;
			useStack*: Chain;
			imps*: Books0.ImpList;
			options*: SET;
			curC: Books0.ContElem;
			noteH*: INTEGER
		END;
		
		(* stack of changes to a tutorial *)
		ChainDesc = RECORD
			old: Books0.TextList;
			pos: LONGINT;
			next: Chain
		END;

	VAR
		Wr: Texts.Writer;
		B: Texts.Buffer;
		tmpT: Texts.Text;
		(* new methods for TGFrame *)
		m: TextGadgets0.Methods;
		(* set to open a tutorial at any position *)
		newPos*, newInd*: LONGINT;
		
(* retrieve Text/Note-Gadgets from a panel *)

	PROCEDURE GetText*(P: Panel; VAR T: TGFrame);
		VAR obj: Objects.Object;
	BEGIN
		T := NIL;
		IF P # NIL THEN
			obj := Gadgets.FindObj(P, "Text");
			IF (obj # NIL) & (obj IS TGFrame) THEN
				T := obj(TGFrame)
			END
		END
	END GetText;

	PROCEDURE GetNote*(P: Panel; VAR T: TGFrame);
		VAR obj: Objects.Object;
	BEGIN
		T := NIL;
		IF P # NIL THEN
			obj := Gadgets.FindObj(P, "Note");
			IF (obj # NIL) & (obj IS TGFrame) THEN
				T := obj(TGFrame)
			END
		END
	END GetNote;

(* resize all TextGadgets.Style to w in a tutorial (P) *)
	PROCEDURE ResizeControls*(P: Panel; T: TGFrame; w: INTEGER);
		VAR
			Fi: Texts.Finder;
			t: Books0.TextList;
			obj: Objects.Object;
	BEGIN
		IF T # NIL THEN
			Texts.OpenFinder(Fi, T.text, 0);
			Texts.FindObj(Fi, obj);
			WHILE ~Fi.eot DO
				IF (obj # NIL) & (obj IS TextGadgets.Style) THEN
					obj(TextGadgets.Style).width := w
				END;
				Texts.FindObj(Fi, obj)
			END
		END;
		t := P.texts;
		WHILE t # NIL DO
			Texts.OpenFinder(Fi, t.text, 0);
			Texts.FindObj(Fi, obj);
			WHILE ~Fi.eot DO
				IF (obj # NIL) & (obj IS TextGadgets.Style) THEN
					obj(TextGadgets.Style).width := w
				END;
				Texts.FindObj(Fi, obj)
			END;
			t := t.next
		END
	END ResizeControls;

(* redisplay a tutorial panel *)

	PROCEDURE MoveBar(P: Panel; M: Display.ModifyMsg; name: ARRAY OF CHAR; Y, mode: INTEGER; broadcast: BOOLEAN);
		VAR 
			obj: Objects.Object;
			msg: Display.ModifyMsg;
	BEGIN
		obj := Gadgets.FindObj(P, name);
		IF obj # NIL THEN
			msg.id := Display.move;
			msg.mode := mode;
			msg.W := M.W-borderL-borderR+1;
			msg.H := obj(Books0.Bar).H;
			msg.dW := 0; msg.dH := 0;
			msg.dX := 0; msg.dY := 0;
			msg.x := 0; msg.y := 0;
			msg.X := obj(Books0.Bar).X;
			msg.Y := Y;
			msg.F := obj(Books0.Bar);
			msg.res := -1; msg.dlink := P;
			msg.stamp := M.stamp;
			IF broadcast THEN
				Display.Broadcast(msg)
			ELSE
				obj.handle(obj, msg)
			END
		END
	END MoveBar;

	PROCEDURE ReDisplay*(VAR M: Display.ModifyMsg; mode: INTEGER; broadcast: BOOLEAN);
		VAR
			butH: INTEGER;
			T, Tn: TGFrame;
			P: Panel;
			msg: Display.ModifyMsg;
	BEGIN
		P := M.F(Panel);
		GetText(P, T);
		IF twoRow IN P.options THEN
			butH := 2*buttonH
		ELSE
			butH := buttonH
		END;
		MoveBar(P, M, "bar1", (*M.Y*) - M.H + 1 +borderB+butH+barH+P.noteH-1, mode, broadcast);
		msg.id := M.id; msg.mode := mode;
		msg.dX := 0; msg.dY := 0;
		msg.W := M.W-borderL-borderR+1;
		msg.H := M.H-borderB-butH-barH-P.noteH-barH-barH-borderT+1;
		msg.dW := M.dW; msg.dH := msg.H-T.H;
		msg.X := T.X; msg.Y := T.Y-msg.dH;
		msg.F := T;
		msg.res := -1;
		msg.x := 0; msg.y := 0;
		msg.dlink := P; msg.stamp := M.stamp;
		IF broadcast THEN
			Display.Broadcast(msg)
		ELSE
			T.handle(T, msg)
		END;
		GetNote(P, Tn);
		msg.id := M.id; msg.mode := mode;
		msg.dX := 0; msg.dY := 0;
		msg.W := M.W-borderL-borderR+1;
		msg.H := P.noteH;
		msg.Y := Tn.Y-msg.dH;
		msg.dW := M.dW; msg.dH := msg.H-Tn.H;
		msg.X := Tn.X; msg.Y := msg.Y-msg.dH;
		msg.F := Tn;
		msg.res := -1;
		msg.x := 0; msg.y := 0;
		msg.dlink := P; msg.stamp := M.stamp;
		IF broadcast THEN
			Display.Broadcast(msg)
		ELSE
			Tn.handle(Tn, msg)
		END
	END ReDisplay;

(* make a copy of a given (from) text, replace styles by new ones *)
	PROCEDURE CopyText*(from: Texts.Text; VAR to: Texts.Text);
		VAR
			B: Texts.Buffer;
			F: Texts.Finder;
			obj, obj2: Objects.Object;
			beg, pos: LONGINT;
			C: Objects.CopyMsg;
	BEGIN
		IF to = NIL THEN
			NEW(to); Texts.Open(to, "")
		ELSE
			Texts.Delete(to, 0, to.len)
		END;
		NEW(B); Texts.OpenBuf(B);
		beg := 0;
		Texts.OpenFinder(F, from, 0);
		pos := F.pos;
		Texts.FindObj(F, obj);
		WHILE ~F.eot DO
			IF obj IS TextGadgets.Style THEN
				IF pos >= beg THEN
					Texts.Save(from, beg, pos, B);
					Texts.Append(to, B)
				END;
				C.id := Objects.deep;
				C.obj := NIL;
				Objects.Stamp(C);
				obj.handle(obj, C);
				obj2 := C.obj;
				Books0.AppendFrame(to, obj2(Gadgets.Frame));
				beg := to.len
			END;
			pos := F.pos;
			Texts.FindObj(F, obj)
		END;
		Texts.Save(from, beg, from.len, B);
		Texts.Append(to, B)
	END CopyText;
	
(* definiton of the Panel extension *)

	PROCEDURE *PanelHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			obj: Objects.Object;
			P, F0: Panel;
			T, T0, Tn: TGFrame;
			butH, x, y, h: INTEGER;
			R: Display3.Mask;
			tl, tl2: Books0.TextList;
			PROCEDURE MoveButton(name: ARRAY OF CHAR; dX, dY, nH: INTEGER);
				VAR msg: Display.ModifyMsg;
			BEGIN
				obj := Gadgets.FindObj(P, name);
				IF obj # NIL THEN
					msg.id := Display.move; msg.mode := Display.state;
					msg.W := buttonW; msg.H := buttonH;
					msg.dW := 0; msg.dH := 0;
					msg.dX := 0; msg.dY := 0;
					msg.x := 0; msg.y := 0;
					msg.X := obj(BasicGadgets.Button).X+dX;
					(*
					msg.Y := obj(BasicGadgets.Button).Y-M(Display.ModifyMsg).dH+dY;
					*)
					WITH obj: BasicGadgets.Button DO
						msg.Y := (obj.Y - (-F(Display.Frame).H + 1)) + dY + (-nH + 1)
					END;
					msg.F := obj(BasicGadgets.Button);
					msg.res := -1; msg.dlink := P;
					msg.stamp := M.stamp;
					obj.handle(obj, msg)
				END
			END MoveButton;
	BEGIN
		WITH F: Panel DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "Books.NewPanel";
							M.res := 0
						ELSE Panels.PanelHandler(F, M)
						END
					ELSE Panels.PanelHandler(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F0);
						F.stamp := M.stamp; F.dlink := F0;
						Panels.CopyPanel(M, F, F0);
						COPY(F.iconStr, F0.iconStr);
						F0.cur := NIL;
						F0.texts := NIL;
						tl := F.texts;
						WHILE tl # NIL DO
							NEW(tl2);
							tl2.next := NIL;
							tl2.prev := F0.cur;
							IF F0.cur = NIL THEN
								F0.texts := tl2
							ELSE
								F0.cur.next := tl2
							END;
							F0.cur := tl2;
							tl2.text := NIL;
							CopyText(tl.text, tl2.text);
							tl := tl.next
						END;
						F0.cur := F0.texts;
						F0.doc := NIL;
						F0.cmds := F.cmds;
						F0.notes := F.notes;
						F0.useStack := NIL;
						F0.imps := F.imps;
						F0.options := F.options;
						F0.curC := NIL;
						F0.noteH := F.noteH;
						GetText(F, T); GetText(F0, T0);
						CopyText(T.text, T0.text);
						T0.panel := F0;
						GetNote(F, T); GetNote(F0, T0);
						CopyText(T.text, T0.text);
						T0.panel := F0;
						M.obj := F0
					END
				END
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = F) OR (M.F = NIL) THEN
						IF M IS Display.ModifyMsg THEN
							WITH M: Display.ModifyMsg DO
								P := F;
								GetText(P, T);
								GetNote(P, Tn);
								IF (T # NIL) & (Tn # NIL) THEN
									IF (twoRow IN P.options) = (M.W < (8*buttonW-2)) THEN
										MoveButton("prev", 0, 0, M.H);
										MoveButton("next", 0, 0, M.H);
										MoveButton("cont", 0, 0, M.H);
										MoveButton("ind", 0, 0, M.H);
										MoveButton("old", 0, 0, M.H);
										MoveButton("hist", 0, 0, M.H);
										MoveButton("down", 0, 0, M.H);
										MoveButton("up", 0, 0, M.H)
									ELSE
										IF M.W < (8*buttonW-2) THEN
											INCL(P.options, twoRow)
										ELSE
											EXCL(P.options, twoRow)
										END;
										IF twoRow IN P.options THEN
											DEC(P.noteH, buttonH);
											MoveButton("prev", 0, buttonH, M.H);
											MoveButton("next", 0, buttonH, M.H);
											MoveButton("cont", 0, buttonH, M.H);
											MoveButton("ind", 0, buttonH, M.H);
											MoveButton("old", -4*buttonW, 0, M.H);
											MoveButton("hist", -4*buttonW, 0, M.H);
											MoveButton("down", -4*buttonW, 0, M.H);
											MoveButton("up", -4*buttonW, 0, M.H)
										ELSE
											INC(P.noteH, buttonH);
											MoveButton("prev", 0, -buttonH, M.H);
											MoveButton("next", 0, -buttonH, M.H);
											MoveButton("cont", 0, -buttonH, M.H);
											MoveButton("ind", 0, -buttonH, M.H);
											MoveButton("old", 4*buttonW, 0, M.H);
											MoveButton("hist", 4*buttonW, 0, M.H);
											MoveButton("down", 4*buttonW, 0, M.H);
											MoveButton("up", 4*buttonW, 0, M.H)
										END
									END;
									IF twoRow IN P.options THEN
										butH := 2*buttonH
									ELSE
										butH := buttonH
									END;
									WHILE ((M.H-borderB-butH-barH-P.noteH-barH-barH-borderT) < 3) & (P.noteH > 3) DO
										DEC(P.noteH)
									END;
									IF P.noteH < 3 THEN
										P.noteH := 3
									END;
									MoveBar(P, M, "bar2", (*M.Y*) -M.H + 1+borderB+butH-1, Display.state, FALSE);
									ReDisplay(M, Display.state, FALSE);
									MoveBar(P, M, "bar0", (*M.Y+M.H*)-barH + 1, Display.state, FALSE);
									IF resize IN P.options THEN
										ResizeControls(P, T, M.W-borderL-borderR-scrollBW);
										TextGadgets0.FormatFrame(T);
										ResizeControls(P, Tn, M.W-borderL-borderR-scrollBW);
										TextGadgets0.FormatFrame(Tn)
									END;	
									Panels.PanelHandler(F, M)
								ELSE Panels.PanelHandler(F, M)
								END
							END
						ELSIF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								Panels.PanelHandler(F, M);
								IF M.device = Display.screen THEN
									x := M.x + F.X; y := M.y + F.Y; h := F.H;
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.ReplConst(R, Display3.white, x, y, 1, h, Display.replace)
								END
							END
						ELSE Panels.PanelHandler(F, M)
						END
					ELSE Panels.PanelHandler(F, M)	
					END
				END
			ELSE Panels.PanelHandler(F, M)	
			END
		END
	END PanelHandler;

	PROCEDURE NewPanel*;
		VAR
			F: Panel;
			C: Objects.CopyMsg;
	BEGIN
		NEW(F);
		Panels.NewPanel();
		C.id := Objects.deep;
		Objects.Stamp(C);
		Panels.CopyPanel(C, Objects.NewObj(Panels.Panel), F);
		F.texts := NIL; F.cur := NIL; F.useStack := NIL;
		F.imps := NIL; F.cmds := NIL; F.notes := NIL;
		F.options := {}; F.doc := NIL; F.curC := NIL;
		F.handle := PanelHandler; F.noteH := 75;
		F.borderW := 0;
		Objects.NewObj := F
	END NewPanel;

(* definiton of the TextGadget extension *)
	
	PROCEDURE ^ShowText*(P: Panel; t: Books0.TextList; pos: LONGINT);
	
	(* quick search on the index page *)
	PROCEDURE HandleKey(F: TGFrame; M: Oberon.InputMsg);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			P: Panel;
	BEGIN
		IF M.ch <= " " THEN
			RETURN
		END;
		IF F.org < 8 THEN
			Texts.OpenReader(R, F.text, 8)
		ELSE
			Texts.OpenReader(R, F.text, F.org+1)
		END;
		Texts.Read(R, ch);
		IF ~R.eot THEN
			WHILE ~R.eot & (CAP(ch) # CAP(M.ch)) DO
				WHILE ~R.eot & ~((R.lib IS Fonts.Font) & (ch = EOL)) DO
					Texts.Read(R, ch)
				END;
				IF ~R.eot THEN
					Texts.Read(R, ch)
				END
			END;
			P := M.dlink(Panel);
			IF ~R.eot THEN
				ShowText(P, P.cur, Texts.Pos(R))
			ELSE
				ShowText(P, P.cur, 0)
			END
		END
	END HandleKey;
	
	PROCEDURE ^Push*(P: Panel);
	
	PROCEDURE *TextHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			F0: TGFrame;
			name: ARRAY 64 OF CHAR;
			obj: Objects.Object;
			x, y: INTEGER;
	BEGIN
		WITH F: TGFrame DO
			IF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F0);
						F.stamp := M.stamp; F.dlink := F0;
						TextGadgets.CopyFrame(M, F, F0);
						F0.focus := FALSE;
						F0.lastPos := 0;
						F0.panel := NIL;
						M.obj := F0
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "Books.NewText";
							M.res := 0
						ELSE TextGadgets.FrameHandler(F, M)
						END
					ELSE TextGadgets.FrameHandler(F, M)
					END
				END
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						IF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
									Gadgets.GetObjName(F, name);
									x := M.x+F.X; y := M.y+F.Y;
									IF (name = "Text") & (M.dlink(Panel).cur.next = NIL) & ~Effects.Inside(M.X, M.Y, x, y, F.left, F.H) THEN
										IF ~F.focus & (M.keys = {2}) THEN
											Oberon.Defocus();
											F.focus := TRUE;
											obj := Gadgets.FindObj(M.dlink, "bar0");
											IF (obj # NIL) & (obj IS Books0.Bar) THEN
												Books0.ColorBar(obj(Books0.Bar), Display3.red)
											END
										ELSE TextGadgets.FrameHandler(F, M)
										END;
										M.res := 0
									ELSE TextGadgets.FrameHandler(F, M)
									END
								ELSIF F.focus & (M.id = Oberon.consume) THEN
									HandleKey(F, M)
								ELSE TextGadgets.FrameHandler(F, M);
								END
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH M: Oberon.ControlMsg DO
								IF M.id IN {Oberon.defocus, Oberon.neutralize} THEN
									IF F.focus THEN
										F.focus := FALSE;
										obj := Gadgets.FindObj(M.dlink, "bar0");
										IF (obj # NIL) & (obj IS Books0.Bar) THEN
											Books0.ColorBar(obj(Books0.Bar), Display3.black)
										END
									END
								END;
								TextGadgets.FrameHandler(F, M)
							END
						ELSE TextGadgets.FrameHandler(F, M)
						END
					ELSE TextGadgets.FrameHandler(F, M)
					END
				END
			ELSE TextGadgets.FrameHandler(F, M)
			END
		END
	END TextHandler;
	
	PROCEDURE NewText*(P: Panel);
		VAR
			obj: TextGadgets.Frame;
			T: TGFrame;
			C: Objects.CopyMsg;
	BEGIN
		TextGadgets.New();
		obj := Objects.NewObj(TextGadgets.Frame);
		EXCL(obj.state0, TextGadgets0.mayfocus);
		EXCL(obj.state0, TextGadgets0.mayconsume);
		EXCL(obj.state0, TextGadgets0.maymvchildren);
		INCL(obj.state0, TextGadgets0.deepcopy);
		INCL(obj.state0, TextGadgets0.locked);
		INCL(obj.control, TextGadgets.nocontrol);
		(* !! *)
		INCL(obj.state, Gadgets.lockedcontents);
		obj.do := m;
		NEW(T);
		C.id := Objects.deep; Objects.Stamp(C);
		TextGadgets.CopyFrame(C, obj, T);
		T.focus := FALSE;
		T.lastPos := 0;
		T.panel := P;
		T.handle := TextHandler;
		Objects.NewObj := T
	END NewText;

(* try to retrieve a Panel in the current context *)
	PROCEDURE GetPanel*(VAR P: Panel);
		VAR
			S: Texts.Scanner;
			doc: Documents.Document;
			obj: Objects.Object;
		PROCEDURE SearchPanel(VAR obj: Objects.Object);
		BEGIN
			WHILE (obj # NIL) & ~(obj IS Panel) DO
				obj := obj.dlink
			END
		END SearchPanel;
	BEGIN
		P := NIL;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF (S.class = Texts.Char) & (S.c = "*") THEN
			doc := Documents.MarkedDoc();
			IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Panel) THEN
				P := doc.dsc(Panel);
				RETURN
			END
		END;
		IF (Gadgets.context # NIL) & (Gadgets.context IS Panel) THEN
			P := Gadgets.context(Panel)
		ELSIF Gadgets.context # NIL THEN
			obj := Gadgets.context;
			SearchPanel(obj);
			IF obj # NIL THEN
				P := obj(Panel)
			END
		END;
		IF P = NIL THEN
			IF (Oberon.Par # NIL) & (Oberon.Par.obj # NIL) & (Oberon.Par.obj IS TGFrame) THEN
				P := Oberon.Par.obj(TGFrame).panel
			ELSIF Documents.MarkedDoc() # NIL THEN
				doc := Documents.MarkedDoc();
				IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Panel) THEN
					P := doc.dsc(Panel)
				END
			ELSIF Desktops.CurDoc(Gadgets.context) # NIL THEN
				doc := Desktops.CurDoc(Gadgets.context);
				IF (doc # NIL) & (doc.dsc # NIL) & (doc.dsc IS Panel) THEN
					P := doc.dsc(Panel)
				END
			END
		END
	END GetPanel;

(* show this tutorial (P) on page t at position pos *)
	PROCEDURE ShowText*(P: Panel; t: Books0.TextList; pos: LONGINT);
		VAR
			T: TGFrame;
			Fi: Texts.Finder;
			obj: Objects.Object;
			lCont: Books0.ContElem;
			fPos, cPos: LONGINT;
			C: Oberon.ControlMsg;
			
			THETEXT: Texts.Text;
			
	BEGIN
		GetText(P, T);
		IF T # NIL THEN
			IF T.focus & (t.next # NIL) THEN
				C.F := T;
				C.id := Oberon.defocus;
				C.dlink := P;
				C.res := -1;
				Objects.Stamp(C);
				T.handle(T, C)
			END;
			IF  (P.cur # t) OR (t.prev = NIL) THEN
				T.org := 0;
				THETEXT := T.text; NEW(T.text); Texts.Open(T.text, "");
				Texts.Delete(THETEXT, 0, THETEXT.len);
				IF t.prev = NIL THEN
				(* special handling for contents page reqired*)
					lCont := NIL;
					Texts.OpenFinder(Fi, t.text, 0);
					fPos := Fi.pos; cPos := -1;
					Texts.FindObj(Fi, obj);
					WHILE ~Fi.eot & (cPos < pos) DO
						IF (obj IS Books0.ContElem) & (obj(Books0.ContElem).mode = Books0.node) THEN
							cPos := fPos;
							lCont := obj(Books0.ContElem)
						END;
						fPos := Fi.pos;
						Texts.FindObj(Fi, obj)
					END;
					Texts.OpenFinder(Fi, t.text, cPos+1);
					fPos := Fi.pos;
					Texts.FindObj(Fi, obj);
					IF (obj # NIL) & (obj IS Books0.Frame) THEN
						Texts.Save(t.text, cPos+1, fPos+1, B);
						Texts.Append(THETEXT, B);
						Texts.WriteLn(Wr);
						Texts.Append(THETEXT, Wr.buf)
					ELSE
						Texts.Save(t.text, cPos+1, fPos, B);
						Texts.Append(THETEXT, B)
					END;
					Texts.Save(t.text, lCont.beg, lCont.end, B);
					Texts.Append(THETEXT, B);
					P.curC := lCont;
					pos := 0
				ELSE
					Texts.Save(t.text, 0, t.text.len, B);
					Texts.Append(THETEXT, B)
				END;
				T.text := THETEXT; T.trailer := NIL;
				T.lastPos := 0;
				P.cur := t;
				IF T.trailer = NIL THEN
					T.org := pos; T.car := FALSE; T.sel := FALSE; Gadgets.Update(T);
				ELSE
					TextGadgets0.ScrollTo(T, TextGadgets0.LinesUp(T.text, pos, 0))
				END
			ELSE
				(*
				IF pos < T.org THEN
					TextGadgets0.Locate(T, pos);
					TextGadgets0.RemoveCaret(T)
				END;
				*)
				TextGadgets0.ScrollTo(T, TextGadgets0.LinesUp(T.text, pos, 0))
			END
		END
	END ShowText;

(* get position of obj in t *)
	PROCEDURE GetPos(t: Texts.Text; obj: Objects.Object): LONGINT;
		VAR
			Fi: Texts.Finder;
			obj2: Objects.Object;
			pos: LONGINT;
	BEGIN
		Texts.OpenFinder(Fi, t, 0);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj2);
		WHILE ~Fi.eot & (obj # obj2) DO
			pos := Fi.pos;
			Texts.FindObj(Fi, obj2)
		END;
		IF obj = obj2 THEN
			RETURN pos
		ELSE
			RETURN 0
		END
	END GetPos;

(* save current state of P *)
	PROCEDURE Push*(P: Panel);
		VAR
			c: Chain;
			T: TGFrame;
		PROCEDURE OnTop(pos: LONGINT): BOOLEAN;
		BEGIN
			RETURN (P.useStack # NIL) & (P.useStack.old = P.cur) & (P.useStack.pos = pos)
		END OnTop;
	BEGIN
		GetText(P, T);
		IF T # NIL THEN
			IF P.cur = NIL THEN RETURN END;
			IF (P.cur.prev = NIL) & ~OnTop(GetPos(P.cur.text, P.curC)) THEN
				NEW(c);
				c.old := P.cur;
				IF P.curC # NIL THEN
					c.pos := GetPos(P.cur.text, P.curC)
				ELSE
					c.pos := 0
				END;
				c.next := P.useStack;
				P.useStack := c
			ELSIF ~OnTop(T.org) THEN
				NEW(c);
				c.old := P.cur;
				c.pos := T.org;
				c.next := P.useStack;
				P.useStack := c
			END
		END
	END Push;

(* retrieve page-number of cur in P *)
	PROCEDURE GetInd*(P: Panel; cur: Books0.TextList): LONGINT;
		VAR
			t: Books0.TextList;
			ind: LONGINT;
	BEGIN
		ind := 0;
		t := P.texts;
		WHILE (t # NIL) & (t # cur) DO
			INC(ind);
			t := t.next
		END;
		RETURN ind
	END GetInd;

(* go to the next/previous subchapter of the current tutorial *)

	PROCEDURE ChapUp*;
		VAR
			P: Panel;
			T: TGFrame;
			Fi: Texts.Finder;
			obj: Objects.Object;
			pos, Ind, Pos: LONGINT;
	BEGIN
		GetPanel(P);
		GetText(P, T);
		IF T # NIL THEN
			Ind := GetInd(P, P.cur);
			Pos := T.org;
			pos := MAX(LONGINT);
			Texts.OpenFinder(Fi, P.texts.text, 0);
			Texts.FindObj(Fi, obj);
			WHILE ~Fi.eot DO
				IF (obj # NIL) & (obj IS Books0.LocFrame) THEN
					WITH obj: Books0.LocFrame DO
						IF (obj.pos1 = Ind) & (obj.pos2 > Pos) & ((obj.pos2-Pos) < (pos-Pos)) THEN
							pos := obj.pos2
						END
					END
				END;
				Texts.FindObj(Fi, obj)
			END;
			IF pos < MAX(LONGINT) THEN
				Push(P);
				ShowText(P, P.cur, pos)
			ELSIF P.cur.next # NIL THEN
				Push(P);
				ShowText(P, P.cur.next, 0)
			END
		END
	END ChapUp;
	
	PROCEDURE ChapDown*;
		VAR
			P: Panel;
			T: TGFrame;
			Fi: Texts.Finder;
			obj: Objects.Object;
			pos, Ind, Pos: LONGINT;
	BEGIN
		GetPanel(P);
		GetText(P, T);
		IF T # NIL THEN
			Ind := GetInd(P, P.cur);
			Pos := T.org;
			pos := -1;
			Texts.OpenFinder(Fi, P.texts.text, 0);
			Texts.FindObj(Fi, obj);
			WHILE ~Fi.eot DO
				IF (obj # NIL) & (obj IS Books0.LocFrame) THEN
					WITH obj: Books0.LocFrame DO
						IF (obj.pos1 = Ind) & (obj.pos2 < Pos) & ((Pos-obj.pos2) < (Pos-pos)) THEN
							pos := obj.pos2
						END
					END
				END;
				Texts.FindObj(Fi, obj)
			END;
			IF pos >= 0 THEN
				Push(P);
				ShowText(P, P.cur, pos)
			ELSIF P.cur.prev # NIL THEN
				Push(P);
				ShowText(P, P.cur.prev, 0)
			END
		END
	END ChapDown;

(* save the usage-stack of P to a text (t) *)
	PROCEDURE History*(P: Panel; t: Texts.Text);
		VAR
			cl: Chain;
			R: Texts.Reader;
			Fi: Texts.Finder;
			ch: CHAR;
			locF: Books0.LocFrame;
			obj: Objects.Object;
			pos, Pos, Ind: LONGINT;
	BEGIN
		cl := P.useStack;
		WHILE cl # NIL DO
			Books0.NewLoc();
			locF := Objects.NewObj(Books0.LocFrame);
			locF.mode := link;
			locF.pos1 := GetInd(P, cl.old);
			locF.pos2 := cl.pos;
			Books0.InsertFrame(t, 0, locF);
			IF cl.old.prev # NIL THEN
				Texts.OpenReader(R, P.texts.text, 0);
				Ind := GetInd(P, cl.old);
				Pos := cl.pos;
				pos := -1;
				Texts.Read(R, ch);
				WHILE ~R.eot DO
					IF ~(R.lib IS Fonts.Font) THEN
						Texts.OpenFinder(Fi, P.texts.text, Texts.Pos(R)-1);
						Texts.FindObj(Fi, obj);
						IF (obj # NIL) & (obj IS Books0.LocFrame) THEN
							WITH obj: Books0.LocFrame DO
								IF (obj.pos1 = Ind) & (obj.pos2 <= Pos) & ((Pos-obj.pos2) < (Pos-pos)) THEN
									pos := obj.pos2
								END
							END
						END
					END;
					Texts.Read(R, ch)
				END;
				Texts.OpenReader(R, cl.old.text, pos);
				Texts.Read(R, ch);
				WHILE ~R.eot & ~((R.lib IS Fonts.Font) & (ch = EOL)) DO
					Texts.Read(R, ch)
				END;
				Texts.Save(cl.old.text, pos, Texts.Pos(R), B)
			ELSE
				Texts.OpenReader(R, cl.old.text, cl.pos);
				Texts.Read(R, ch);
				WHILE ~R.eot & ~((R.lib IS Fonts.Font) & (ch = EOL)) DO
					Texts.Read(R, ch)
				END;
				Texts.Save(cl.old.text, cl.pos, Texts.Pos(R), B)
			END;
			Texts.Insert(t, 0, B);
			cl := cl.next
		END
	END History;
	
(* go one step deeper in the contents-tree *)
	PROCEDURE *OpenCont(F: Books0.ContElem);
		VAR P: Panel;
	BEGIN
		IF (F.dlink # NIL) & (F.dlink IS TGFrame) THEN
			P := F.dlink(TGFrame).panel;
			Push(P);
			ShowText(P, P.texts, GetPos(P.texts.text, F))
		END
	END OpenCont;

(* get the position of the line-end of the line containing pos *)
	PROCEDURE EndOfLine(T: TGFrame; pos: LONGINT): LONGINT;
		VAR
			beg: LONGINT;
			line: TextGadgets0.Line;
	BEGIN
		IF T.trailer = NIL THEN
			RETURN pos
		END;
		beg := T.org;
		line := T.trailer.next;
		WHILE (line.next # T.trailer) & (beg <= pos) DO
			INC(beg, line.len);
			line := line.next
		END;
		IF beg > pos THEN
			RETURN beg-1
		ELSE
			RETURN T.text.len
		END
	END EndOfLine;
	
(* show this tutorial (P) on page ind at position pos *)
	PROCEDURE GotoText*(P: Panel; ind, pos: LONGINT; sel: BOOLEAN);
		VAR
			t: Books0.TextList;
			i: INTEGER;
			T: TGFrame;
	BEGIN
		i := 0;
		t := P.texts;
		WHILE (t # NIL) & (i < ind) DO
			t := t.next;
			INC(i)
		END;
		IF (t # NIL) & (i = ind) THEN
			Push(P);
			ShowText(P, t, pos);
			IF sel THEN
				GetText(P, T);
				TextGadgets0.SetSelection(T, pos, EndOfLine(T, pos))
			END
		END
	END GotoText;

(* get the index page of P *)
	PROCEDURE GetIndex*(P: Panel): Books0.TextList;
		VAR t: Books0.TextList;
	BEGIN
		t := P.cur;
		WHILE t.next # NIL DO
			t := t.next
		END;
		RETURN t
	END GetIndex;

(* show the book referenced by e (usually a exported label) *)
	PROCEDURE ShowBook(e: Books0.ExtFrame);
	BEGIN
		newInd := e.imp.pos1;
		newPos := e.imp.pos2;
		Desktops.ShowDoc(Documents.Open(e.imp.book.name))
	END ShowBook;

(* show local footnote of P *)
	PROCEDURE ShowFootNote*(P: Panel; pos1, pos2: LONGINT);
		VAR
			T: TGFrame;
			style: TextGadgets.Style;
	BEGIN
		Texts.Save(P.notes, pos1, pos2, B);
		GetNote(P, T);
		IF T # NIL THEN
			Texts.Delete(T.text, 0, T.text.len);
			IF formated IN P.options THEN
				style := TextGadgets.newStyle();
				style.width := P.W-borderL-borderR-scrollBW;
				style.mode := {};
				IF left IN P.options THEN
					INCL(style.mode, TextGadgets.left)
				END;
				IF middle IN P.options THEN
					INCL(style.mode, TextGadgets.middle)
				END;
				IF right IN P.options THEN
					INCL(style.mode, TextGadgets.right)
				END;
				IF pad IN P.options THEN
					INCL(style.mode, TextGadgets.pad)
				END;
				Books0.AppendFrame(T.text, style)
			END;
			Texts.Append(T.text, B)
		END
	END ShowFootNote;
	
(* calc par.frame for Oberon.Call *)
	PROCEDURE GetFrame(dlink: Objects.Object): Display.Frame;
	BEGIN
		WHILE (dlink # NIL) & (dlink.dlink # NIL) DO
			dlink := dlink.dlink;
		END;
		IF (dlink # NIL) & (dlink IS Display.Frame) THEN
			RETURN dlink(Display.Frame)
		ELSE
			RETURN Oberon.Par.frame
		END
	END GetFrame;
	
(* display error-messages for return-value of Oberon.Call *)
	PROCEDURE ShowCallErr(res: INTEGER; s: ARRAY OF CHAR);
	BEGIN
		Texts.WriteString(Wr, "Call error: ");
		Texts.WriteString(Wr, s); Texts.WriteString(Wr, Modules.resMsg);
		Texts.WriteLn(Wr);
		Texts.Append(Oberon.Log, Wr.buf)
	END ShowCallErr;
	
(* overridden Call-"method" for TGFrame, handels: links, notes & calls *)
	PROCEDURE *Call(F: TextGadgets0.Frame; pos: LONGINT; keysum: SET; dlink: Objects.Object);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			Fi: Texts.Finder;
			obj: Objects.Object;
			P: Panel;
			S: Texts.Scanner;
			par: Oberon.ParList;
			res: INTEGER;
			beg, pos2: LONGINT;
			T: TGFrame;
			style: TextGadgets.Style;
	BEGIN
		Texts.OpenScanner(S, F.text, pos);
		Texts.Scan(S);
		IF (dlink = NIL) OR ~(dlink IS Panel) OR (S.line # 0) OR ((S.class = Texts.Char) & (S.c < " ")) THEN
			TextGadgets.methods.Call(F, pos, keysum, dlink);
			RETURN
		END;
		Texts.OpenReader(R, F.text, pos+1);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.lib IS Fonts.Font) & (R.col IN {linkCol, callCol, noteCol}) DO
			Texts.Read(R, ch)
		END;
		Texts.OpenFinder(Fi, F.text, Texts.Pos(R)-1);
		pos2 := Fi.pos;
		Texts.FindObj(Fi, obj);
		IF (pos2+1 # Texts.Pos(R)) OR (obj = NIL) OR ~(obj IS Books0.Frame) THEN
			TextGadgets.methods.Call(F, pos, keysum, dlink);
			RETURN
		END;
		P := dlink(Panel);
		IF obj IS Books0.LocFrame THEN
			WITH obj: Books0.LocFrame DO
				IF obj.mode = link THEN
					GotoText(P, obj.pos1, obj.pos2, TRUE)
				ELSIF obj.mode = call THEN
					NEW(par);
					par.obj := F;
					par.frame := GetFrame(dlink);
					Texts.OpenReader(R, P.cmds, obj.pos1);
					WHILE ~R.eot & (Texts.Pos(R) < obj.pos2) DO
						beg := Texts.Pos(R);
						Texts.Read(R, ch);
						WHILE ~R.eot & (ch # EOL) DO
							Texts.Read(R, ch)
						END;
						Texts.Save(P.cmds, beg, Texts.Pos(R), B);
						Texts.Delete(tmpT, 0, tmpT.len);
						Texts.Append(tmpT, B);
						Texts.OpenScanner(S, tmpT, 0);
						par.text := tmpT;
						Texts.Scan(S);
						par.pos := Texts.Pos(S);
						Oberon.Call(S.s, par, 2 IN keysum, res);
						IF res # 0 THEN
							ShowCallErr(res, S.s)
						END
					END
				ELSIF obj.mode = note THEN
					ShowFootNote(P, obj.pos1, obj.pos2)
				END
			END
		ELSIF obj IS Books0.ExtFrame THEN
			WITH obj: Books0.ExtFrame DO
				IF obj.mode = link THEN
					ShowBook(obj)
				ELSIF obj.mode = note THEN
					Texts.Save(obj.imp.book.notes, obj.imp.pos1, obj.imp.pos2, B);
					GetNote(P, T);
					IF T # NIL THEN
						Texts.Delete(T.text, 0, T.text.len);
						IF formated IN P.options THEN
							style := TextGadgets.newStyle();
							style.width := P.W-borderL-borderR-scrollBW;
							Books0.AppendFrame(T.text, style)
						END;
						Texts.Append(T.text, B)
					END
				END
			END
		END
	END Call;

(* overridden LocateString-"method" for TGFrame, handels underlining of strings *)
	PROCEDURE *LocateString(F: TextGadgets0.Frame; x, y, X, Y: INTEGER; VAR loc: TextGadgets0.Loc);
		VAR
			R: Texts.Reader;
			ch: CHAR;
			Fi: Texts.Finder;
			obj: Objects.Object;
			loc1, loc2: TextGadgets0.Loc;
			line: TextGadgets0.Line;
			pos, beg, end: LONGINT;
	BEGIN
		TextGadgets.methods.LocateChar(F, x, y, X, Y, loc);
		Texts.OpenReader(R, F.text, loc.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (R.lib IS Fonts.Font) & (R.col IN {linkCol, callCol, noteCol}) DO
			Texts.Read(R, ch)
		END;
		Texts.OpenFinder(Fi, F.text, Texts.Pos(R)-1);
		pos := Fi.pos;
		Texts.FindObj(Fi, obj);
		IF (pos+1 # Texts.Pos(R)) OR (obj = NIL) OR ~(obj IS Books0.Frame) THEN
			TextGadgets.methods.LocateString(F, x, y, X, Y, loc);
			RETURN
		END;
		pos := loc.pos;
		beg := F.org;
		line := F.trailer.next;
		WHILE (line.next # F.trailer) & ((beg+line.len) <= pos) DO
			INC(beg, line.len);
			line := line.next
		END;
		end := beg+loc.line.len;
		Texts.OpenReader(R, F.text, pos);
		Texts.Read(R, ch);
		WHILE (pos >= beg) & ((R.col IN {linkCol, callCol, noteCol}) & (R.lib IS Fonts.Font)) DO
			DEC(pos);
			Texts.OpenReader(R, F.text, pos);
			Texts.Read(R, ch)
		END;
		Texts.OpenReader(R, F.text, loc.pos);
		Texts.Read(R, ch);
		WHILE ~R.eot & (Texts.Pos(R) < end) & ((R.col IN {linkCol, callCol, noteCol}) & (R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch)
		END;
		F.do.LocatePos(F, pos+1, loc1);
		F.do.LocatePos(F, Texts.Pos(R)-1, loc2);
		loc.x := loc1.x; loc.pos := pos+1;
		loc.dx := loc2.x-loc1.x
	END LocateString;

(* undo last change to a tutorial (P) *)
	PROCEDURE Pop*(P: Panel);
	BEGIN
		IF (P # NIL) & (P.useStack # NIL) THEN
			ShowText(P, P.useStack.old, P.useStack.pos);
			P.useStack := P.useStack.next
		END
	END Pop;
		
BEGIN
	Texts.OpenWriter(Wr);
	NEW(B); Texts.OpenBuf(B);
	NEW(tmpT); Texts.Open(tmpT, "");
	NEW(m);
	m^ := TextGadgets.methods^;
	m.Call := Call;
	m.LocateString := LocateString;
	newPos := -1; newInd := -1;
	Books0.Action := OpenCont
END Books.