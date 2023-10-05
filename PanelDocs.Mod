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

MODULE PanelDocs;	(** portable *)	(* jm 1.2.95 *)

(** Implementation of a document for the panel gadgets.
*)

(*
	jm 7.11.94 - removed PublicPanel support
	ps 16.07.96 - added commads to support 'dynamic' panels (thanks eos)
	ps 4.8.96 - changed to Printer.Frame
	ps 8.10.96 - improved Detach
*)

IMPORT
	Objects, Display, Display3, Files, Strings, Attributes, Links, Oberon, Panels, Texts, Gadgets, Documents, Desktops, Printer, Modules;

CONST
	Menu = "Desktops.StoreDoc[Store]";

VAR
	W: Texts.Writer;

PROCEDURE Explain;
BEGIN
	IF (Modules.res # 0) & (Modules.resMsg # "") THEN
		Texts.WriteString(W, " (");  Texts.WriteString(W, Modules.resMsg);  Texts.Write(W, ")")
	END
END Explain;

(** Loads a panel from disk. VW, VH indicate the prefered size of the panel. *)
PROCEDURE OpenPanel*(D: Documents.Document; name: ARRAY OF CHAR; VAR VW, VH: INTEGER): Gadgets.Frame;
TYPE EmptyMsg = RECORD (Display.FrameMsg) END;
VAR lib: Objects.Library; root: Objects.Object; J: EmptyMsg; fp: Files.File; R: Files.Rider; ch: CHAR;
	len: LONGINT; i, x, y: INTEGER; s: ARRAY 64 OF CHAR; old: BOOLEAN;
	CM: Gadgets.CmdMsg;
BEGIN
	VW := 266; VH := 200;
	fp := Files.Old(name);
	IF fp # NIL THEN
		Files.Set(R, fp, 0);
		Files.ReadInt(R, i);
		IF (i = Documents.Id) OR (i = 0727H) THEN
			Files.ReadString(R, s); (* skip over tag *)
			Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, VW); Files.ReadInt(R, VH);
			Files.Read(R, ch);
			IF (ch = 0F7X) THEN (* attachments *)
				Documents.LoadAttachments(R, D.attr, D.link);
				IF D.link # NIL THEN
					CM.cmd := "PREPARE"; CM.res := -1; CM.dlink := D; Objects.Stamp(CM);
					Links.Broadcast(D.link, CM)
				END;
				Files.Read(R, ch)
			END;
			old := FALSE
		ELSE
			Files.Set(R, fp, 0); Files.Read(R, ch);
			old := TRUE
		END;

		IF (ch = 04X) OR (ch = 02X) THEN (* super or drawings format *)
			Files.Read(R, ch);
			IF (ch = Objects.LibBlockId) OR (ch = 0DBX) THEN
				NEW(lib); Objects.OpenLibrary(lib);
				Objects.LoadLibrary(lib, fp, Files.Pos(R), len);
				lib.GetObj(lib, 0, root); (* by default *)
				
				IF (root # NIL) & (root IS Objects.Dummy) THEN
					Texts.WriteString(W, "  discarding "); Texts.WriteString(W, root(Objects.Dummy).GName);
					Explain;
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
					root := NIL
				ELSIF (root # NIL) & (root IS Display.Frame) THEN
					WITH root: Display.Frame DO
						J.dlink := NIL; J.F := NIL; J.x := 0; J.y := 0;
						root.handle(root, J); (* send a dummy message down, so that traps are caused early *)
						IF old THEN VW := root.W; VH := root.H END;
						RETURN root(Gadgets.Frame)
					END
				ELSE RETURN NIL
				END
			ELSE
				Texts.WriteString(W, "  panel format corrupt"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			END
		ELSE
			Texts.WriteString(W, "  not a panel"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		END
	END;
	RETURN NIL
END OpenPanel;

(** Document method. *)
PROCEDURE LoadPanel*(D: Documents.Document);
VAR obj: Objects.Object; main: Gadgets.Frame; gen: ARRAY 64 OF CHAR;
BEGIN
	main := OpenPanel(D, D.name, D.W, D.H);
	IF main = NIL THEN
		Attributes.GetString(D, "MainGen", gen);
		obj := Gadgets.CreateObject(gen);
		main := obj(Gadgets.Frame)
	END;
	Documents.Init(D, main)
END LoadPanel;

(** Document method. *)
PROCEDURE StorePanel*(D: Documents.Document);
VAR lib: Objects.Library; f: Files.File; len: LONGINT; P: Display.Frame;
	new, gen: ARRAY 64 OF CHAR; i: INTEGER; B: Objects.BindMsg; R: Files.Rider;
BEGIN
	Texts.WriteString(W, "Store "); Texts.Append(Oberon.Log, W.buf);
	IF D.name # "" THEN
		P := D.dsc;
		IF P # NIL THEN
			NEW(lib); Objects.OpenLibrary(lib);
			B.lib := lib;  P.handle(P, B);
			
			f := Files.New(D.name); IF f = NIL THEN HALT(99) END;
			
			COPY(D.name, new); i := 0; WHILE new[i] # 0X DO INC(i) END;
			new[i] := "."; new[i+1] := "B"; new[i+2] := "a"; new[i+3] := "k"; new[i+4] := 0X;
			Files.Rename(D.name, new, i); (* rename file *)
			
			Attributes.GetString(D, "Gen", gen);
			Files.Set(R, f, 0); Files.WriteInt(R, Documents.Id); Files.WriteString(R, gen);
			Files.WriteInt(R, 0); Files.WriteInt(R, 0); Files.WriteInt(R, P.W); Files.WriteInt(R, P.H);
			IF (D.attr # NIL) OR (D.link # NIL) THEN (* attachments *)
				Documents.StoreAttachments(R, D.attr, D.link)
			END;
			Files.Write(R, (* SuperId *) 02X);
			Objects.StoreLibrary(lib, f, Files.Pos(R), len);
			Files.Register(f);
			
			Texts.Write(W, 22X); Texts.WriteString(W, D.name); Texts.Write(W, 22X)
		END
	ELSE Texts.WriteString(W, "[Untitled document]");
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END StorePanel;

PROCEDURE PrintPanelDoc(F: Panels.Panel);
VAR P: Display.DisplayMsg; O: Display3.OverlapMsg;

	PROCEDURE Dev(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit);
	END Dev;
	
BEGIN
	IF (F # NIL) THEN
		NEW(O.M); Display3.Open(O.M);
		Display3.Add(O.M, 0, -F.H+1, F.W, F.H); O.x := 0; O.y := 0; O.F := F; O.res := -1;
		F.handle(F, O);
		P.device := Display.printer; P.id := Display.full; Objects.Stamp(P);
		P.x := Printer.FrameX + Printer.FrameW DIV 2 - Dev(F.W) DIV 2;
		IF P.x < 0 THEN P.x := SHORT(36000 * 5 DIV Printer.Unit) END;
		P.y := Printer.FrameY + Printer.FrameH DIV 2 - Dev(F.H) DIV 2;
		IF P.y < 0 THEN P.y := Printer.FrameY + Printer.FrameH - SHORT(36000 * 5 DIV Printer.Unit) - Dev(F.H) END;
		
		P.res := -1; P.dlink := NIL; F.handle(F, P);
		IF Printer.res = 0 THEN Printer.Page(1) END
	END
END PrintPanelDoc;

PROCEDURE DocHandle*(D: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	WITH D: Documents.Document DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF M.id = Objects.get THEN
					IF M.name = "Gen" THEN M.class := Objects.String; M.s := "PanelDocs.NewDoc"; M.res := 0
					ELSIF M.name = "MainGen" THEN M.class := Objects.String; M.s := "Panels.NewPanel"; M.res := 0
					ELSIF M.name = "Adaptive" THEN M.class := Objects.Bool; M.b := FALSE; M.res := 0
					ELSIF M.name = "Icon" THEN M.class := Objects.String; M.s := "Icons.Panel"; M.res := 0
					ELSE Documents.Handler(D, M)
					END
				ELSE Documents.Handler(D, M)
				END
			END
		ELSIF M IS Objects.LinkMsg THEN
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
		ELSIF M IS Display.DisplayMsg THEN
			WITH M: Display.DisplayMsg DO
				IF (M.device = Display.printer) & (M.id = Display.contents) & (D.dsc # NIL) THEN
					PrintPanelDoc(D.dsc(Panels.Panel))
				ELSE Documents.Handler(D, M)
				END
			END
		ELSE Documents.Handler(D, M)
		END
	END
END DocHandle;

PROCEDURE InitDoc*(D: Documents.Document; W, H: INTEGER);
VAR main: Objects.Object; gen: ARRAY 64 OF CHAR;
BEGIN D.Load := LoadPanel; D.Store := StorePanel; D.handle := DocHandle; D.name := "";
	D.W := W; D.H := H;
	Attributes.GetString(D, "MainGen", gen);
	main := Gadgets.CreateObject(gen);
	Documents.Init(D, main(Gadgets.Frame))
END InitDoc;

PROCEDURE NewDoc*;
VAR D: Documents.Document;
BEGIN NEW(D); InitDoc(D, 266, 200); Objects.NewObj := D
END NewDoc;

(** append public panel to context panel **)
PROCEDURE AppendPanel*;
	VAR
		s: Texts.Scanner; obj: Objects.Object; ctxt, new: Display.Frame; locked: BOOLEAN; h: INTEGER;
		cm: Display.ConsumeMsg; mm: Display.ModifyMsg; ctrl: Display.ControlMsg;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(s);
	IF s.class = Texts.Name THEN
		obj := Gadgets.CopyPublicObject(s.s, FALSE);
		IF (obj # NIL) & (obj IS Display.Frame) & (Gadgets.context # NIL) & (Gadgets.context IS Display.Frame) THEN
			ctxt := Gadgets.context(Display.Frame);
			Attributes.GetBool(ctxt, "Locked", locked);
			Attributes.SetBool(ctxt, "Locked", FALSE);
			new := obj(Display.Frame);
			h := new.H;
			cm.F := ctxt; cm.id := Display.drop; cm.obj := new; cm.u := 0; cm.v := -(ctxt.H + h);
			Display.Broadcast(cm);
			Attributes.SetBool(ctxt, "Locked", locked);
			Objects.Stamp(ctrl); ctrl.dlink := NIL; ctrl.F := NIL; ctrl.x := 0; ctrl.y := 0; ctrl.id := Display.restore; ctrl.res := -1;
			new.handle(new, ctrl);
			mm.F := ctxt; mm.id := Display.move; mm.mode := Display.display;
			mm.X := ctxt.X; mm.Y := ctxt.Y - h; mm.W := ctxt.W; mm.H := ctxt.H + h;
			mm.dX := 0; mm.dY := -h; mm.dW := 0; mm.dH := h;
			Display.Broadcast(mm)
		END
	END
END AppendPanel;

(** remove context panel from its own context **)
PROCEDURE RemovePanel*;
	VAR f, ctxt, dsc: Display.Frame; list: Objects.Object; mm: Display.ModifyMsg; cm: Display.ControlMsg;
BEGIN
	IF (Gadgets.context # NIL) & (Gadgets.context IS Display.Frame) THEN
		f := Gadgets.context(Display.Frame);
		IF (f.dlink # NIL) & (f.dlink IS Display.Frame) THEN
			ctxt := f.dlink(Display.Frame);
			dsc := ctxt.dsc; list := NIL;
			WHILE dsc # NIL DO
				IF dsc.Y < f.Y THEN
					dsc.slink := list; list := dsc
				END;
				dsc := dsc.next
			END;
			mm.id := Display.move; mm.mode := Display.state;
			WHILE list # NIL DO
				dsc := list(Display.Frame); mm.F := dsc;
				mm.X := dsc.X; mm.Y := dsc.Y + f.H; mm.W := dsc.W; mm.H := dsc.H;
				mm.dX := 0; mm.dY := f.H; mm.dW := 0; mm.dH := 0;
				Display.Broadcast(mm);
				list := list.slink; dsc.slink := NIL
			END;
			(* dsc := ctxt.dsc;
			WHILE dsc # NIL DO
				IF dsc.Y < f.Y THEN
					mm.F := dsc;
					mm.X := dsc.X; mm.Y := dsc.Y + f.H; mm.W := dsc.W; mm.H := dsc.H;
					mm.dX := 0; mm.dY := dsc.Y - mm.Y; mm.dW := 0; mm.dH := 0;
					Display.Broadcast(mm)
				END;
				dsc := dsc.next
			END; *)
			mm.F := ctxt; mm.id := Display.move; mm.mode := Display.display;
			mm.X := ctxt.X; mm.Y := ctxt.Y + f.H; mm.W := ctxt.W; mm.H := ctxt.H - f.H;
			mm.dX := 0; mm.dY := f.H; mm.dW := 0; mm.dH := -f.H;
			Display.Broadcast(mm)
		END;
		cm.F := f; cm.id := Display.remove;
		Display.Broadcast(cm)
	END
END RemovePanel;

(** remove context panel from its context and open as separate document **)
PROCEDURE DetachPanel*;
	VAR f: Gadgets.Frame; doc: Documents.Document;
BEGIN
	IF (Gadgets.context # NIL) & (Gadgets.context IS Gadgets.Frame) THEN
		f := Gadgets.context(Gadgets.Frame);
		IF (f.dlink # NIL) & (f.dlink IS Panels.Panel) THEN	(* ps - 8.10.96 *)
			RemovePanel;
			NEW(doc);
			doc.W := f.W; doc.H := f.H;
			doc.Load := LoadPanel; doc.Store := StorePanel; doc.handle := DocHandle;
			Gadgets.GetObjName(f, doc.name); Strings.Append(doc.name, ".Panel");
			Documents.Init(doc, f);
			Desktops.ShowDoc(doc)
		END
	END
END DetachPanel;

BEGIN Texts.OpenWriter(W)
END PanelDocs.
