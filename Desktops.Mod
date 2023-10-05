(* OBERON System 3, Release 2.3.

Copyright 1999 ETH Zürich Institute for Computer Systems, 
ETH Center, CH-8092 Zürich.  e-mail: oberon@inf.ethz.ch.

This module may be used under the conditions of the general Oberon 
System 3 license contract.  The full text can be downloaded from

	"ftp://ftp.inf.ethz.ch/pub/software/Oberon/System3/license.txt;type=A"

Under the license terms stated it is in particular (a) prohibited to modify
the interface of this module in any way that disagrees with the style
or content of the system and (b) requested to provide all conversions
of the source code to another platform with the name OBERON. *)

MODULE Desktops; (** portable *)	(**  , jm 1.2.95 *)

(**Implementation of the Oberon Desktop, with Viewers for displaying documents in the tiled and overlapping windowing systems of Oberon.
 *)
(*
	25.3.94 - Added support for Documents.LocateMsg
	5.4.94 - fixed the size of the grab area on top of the Viewer to 6 pixels
	6.4.94 - changed from jg style modifyMsg's to gadget style messages for Viewers
	19.4.94 - left key in DocGadget Menu bar takes it to behind, left + middle to the front
	20.4.94 - left key in document prints it to front
	22.4.94 - Send restore msg on ShowDoc
	27.4.94 - improved to front
	2.5.94 - Added copy over for docgadgets\
	24.5.94 - Remove dynamic buttons in the menu-bars
	30.5.94 - added "loading failed" messages
	27.7.94 - improved document placement
	12.10.94 - improved opening of non desktop tjings
	12.10.94 - fixed button on opening new desktop
	19.10.94 - Added Recall.
			this module is very much an hack now. Compatibility with classic Oberon and old gadgets
		applications makes it difficult to change. The whole flag business should be fixed (difficult when everything
		is not a gadget).
	8.11.94 - Viewers now respond on Locked attribute. used together with Gadgets.IsLocked
	8.11.94 - flag business simplified drastically. 31 flag not used any more.
		- removed OpenView plus modified signature of ShowDoc
	30.11.94 - renamed Viewer to DocViewer
	21.12.94 - added alias support for Document generators
	3.1.95 - simplified MakeIcon, renamed from MakeIcons
	24.1.95 - fixed cursor in DocViewer menubar
	19.4.95 - increased the height where the DocViewer can be grabbed with the left key
	15.5.95 - LoadDoc now checks on a NIL dsc
	21.6.95 - Removed setting of Views.View border
	7.6.96 - fixed parsing of menustring	(* ps - 7.6.96 *)
	21.9.96 - bugfix in ModifyFrame (* ps - 21.9.96 *)
	11.12.96 - changed Grow
	12.12.96 - added Copy, changed Init, newMenu
	7.1.97 - default width on desktop (set to 250) introduced
*)

IMPORT
	Input, Objects, Display, Viewers, Oberon, Gadgets, Attributes, Files, Documents, Texts, Display3, Views, 
	Printer, Printer3, Effects, Fonts, Pictures, Strings;

CONST
	leftBorder = 0; frameColor = 12;
	extend = Display.extend; reduce = Display.reduce;
	AvoidLostViewer = TRUE;

TYPE
	(** Viewer for displaying documents in a desktop. *)
	DocGadget* = POINTER TO DocGadgetDesc;
	DocGadgetDesc* = RECORD (Gadgets.FrameDesc)
		time: LONGINT;
	END;

	(** Viewers.Viewer for displaying documents in the tiled viewer system. *)
	DocViewer* = POINTER TO DocViewerDesc;
	DocViewerDesc* = RECORD (Viewers.ViewerDesc)
		menuH*: INTEGER;	(** Menubar height. *)
		time: LONGINT;
	END;

	Dummy = POINTER TO RECORD (Display.FrameDesc) END;

	UpdateNameMsg* = RECORD (Display.FrameMsg)
		obj*: Objects.Object
	END;

	ParentMsg = RECORD (Display.FrameMsg)
		parent: Objects.Object
	END;

VAR
	menuH*: INTEGER;	(** Default menubar heigth of DocGadget and DocViewer *)
	menuC*: INTEGER;	(** Default menubar panel color *)
	menuButtonW*: INTEGER;	(** Default menu button width *)
	namePlateW*: INTEGER;	(** Default nameplate width *)
	recDocWidth*: INTEGER;	(** recommended minimal document width *)
	W: Texts.Writer;
	recall: Display.Frame;

PROCEDURE ^NewMenu*(menubar: ARRAY OF CHAR): Display.Frame;

(* ===================== Own Viewer code ================ *)
PROCEDURE ^NewDummy(): Dummy;
PROCEDURE ^ViewerDoc(V: DocViewer): Documents.Document;

PROCEDURE DummyHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
BEGIN
	IF M IS Objects.CopyMsg THEN
		M(Objects.CopyMsg).obj := NewDummy();
	END
END DummyHandler;

PROCEDURE NewDummy(): Dummy;
VAR F: Dummy;
BEGIN NEW(F); F.handle := DummyHandler; RETURN F
END NewDummy;

(** Does the DocViewer have a menubar? Only the desktops are DocViewers without menubars. *)
PROCEDURE HasMenu*(V: DocViewer): BOOLEAN;
BEGIN RETURN ~(V.dsc IS Dummy)
END HasMenu;

  PROCEDURE CopyDocViewer (V: DocViewer; VAR V1: DocViewer);
    VAR Menu, Main: Display.Frame; M: Objects.CopyMsg;
  BEGIN
    Menu := V.dsc; Main := V.dsc.next;
    NEW(V1); V1^ := V^; V1.state := 0;
    M.id := Objects.shallow; Objects.Stamp(M);
    Menu.handle(Menu, M); V1.dsc := M.obj(Display.Frame);
    Main.handle(Main, M); V1.dsc.next := M.obj(Display.Frame) 
  END CopyDocViewer;

  PROCEDURE ModifyFrame(V: DocViewer; F: Display.Frame; id, Y, H: INTEGER);
    VAR M: Display.ModifyMsg;
  BEGIN
    M.F := F; M.id := id; M.dlink := V; V.dlink := NIL;
    IF (F.Y + F.H # Y + H) & (F.H # H) THEN (* move main first and then resize *)	(* ps - 21.9.96 *)
        IF H < F.H THEN (* reduce *)
        	M.X := F.X; M.Y := F.Y + (F.H - H); M.W := F.W; M.H := H;
            M.dX := 0; M.dY := M.Y - F.Y; M.dW := 0; M.dH := M.H - F.H;
        	M.mode := Display.state; M.res := MIN(INTEGER); M.x := 0; M.y := 0; Objects.Stamp(M);
        	F.handle(F, M); F.Y := M.Y
        ELSE (* extend *)
        	M.X := F.X; M.Y := Y + H - F.H; M.W := F.W; M.H := F.H;
            M.dX := 0; M.dY := M.Y - F.Y; M.dW := 0; M.dH := 0;
            M.mode := Display.display; M.res := MIN(INTEGER); M.x := 0; M.y := 0; Objects.Stamp(M);
        	F.handle(F, M); F.Y := M.Y
        END
    END;
    M.X := F.X; M.Y := Y; M.W := F.W; M.H := H;
    M.dX := 0; M.dY := M.Y - F.Y; M.dW := 0; M.dH := M.H - F.H;
	M.mode := Display.display; M.res := MIN(INTEGER); M.x := 0; M.y := 0; Objects.Stamp(M);
	F.handle(F, M); F.Y := Y; F.H := H
  END ModifyFrame;

  PROCEDURE Restore (V: DocViewer);
    VAR Menu, Main: Display.Frame; M: Display.ControlMsg;
  BEGIN
    Menu := V.dsc; Main := V.dsc.next;
    Oberon.RemoveMarks(V.X, V.Y, V.W, V.H);
    Menu.X := V.X; Menu.Y := V.Y + V.H; Menu.W := V.W; Menu.H := 0;
    Main.X := V.X; Main.Y := V.Y + V.H - V.menuH; Main.W := V.W; Main.H := 0;
    M.F := NIL; M.id := Display.restore; M.res := -1; Objects.Stamp(M); M.dlink := V; V.dlink := NIL;
    M.x := 0; M.y := 0;
    Menu.handle(Menu, M); Main.handle(Main, M);
    IF V.H > V.menuH + 1 THEN
      ModifyFrame(V, Menu, extend, V.Y + V.H - V.menuH, V.menuH);
      ModifyFrame(V, Main, extend, V.Y, V.H - V.menuH)
    ELSE ModifyFrame(V, Menu, extend, V.Y, V.H)
    END
  END Restore;

  PROCEDURE ModifyDocViewer (V: DocViewer; id, Y, H: INTEGER);
    VAR Menu, Main: Display.Frame;
  BEGIN
    Menu := V.dsc; Main := V.dsc.next;
    IF id = extend THEN
      Oberon.RemoveMarks(V.X, Y, V.W, V.Y - Y);
      IF H > V.menuH + 1 THEN
        ModifyFrame(V, Menu, extend, Y + H - V.menuH, V.menuH);
        ModifyFrame(V, Main, extend, Y , H - V.menuH)
      ELSE 
      	ModifyFrame(V, Menu, extend, Y, H);
      	ModifyFrame(V, Main, extend, Y + H - V.menuH, 0)
      END
    ELSIF id = reduce THEN
      Oberon.RemoveMarks(V.X, Y, V.W, Y - V.Y);
      IF H > V.menuH + 1 THEN
        ModifyFrame(V, Main, reduce, Y, H - V.menuH);
        ModifyFrame(V, Menu, reduce, Y + H - V.menuH, V.menuH)
      ELSE
        ModifyFrame(V, Main, reduce, Y + H - V.menuH, 0);
        ModifyFrame(V, Menu, reduce, Y, H)
      END;
    END
  END ModifyDocViewer;

  PROCEDURE Change (V: DocViewer; X, Y: INTEGER; Keys: SET);
    VAR Menu, Main: Display.Frame;
      V1: Viewers.Viewer; keysum: SET; Y0, dY, H: INTEGER;
  BEGIN (*Keys # {}*)
    Menu := V.dsc; Main := V.dsc.next;
    IF Menu IS Dummy THEN V.dsc.H := 5 END;
    
    Oberon.FadeCursor(Oberon.Mouse);
    
    Display.ReplConst(3, V.X, V.Y + V.H - V.dsc.H, V.W, V.dsc.H, Display.invert);
    Y0 := Y; 
    keysum := Keys;
    LOOP
      Input.Mouse(Keys, X, Y);
      IF Keys = {} THEN EXIT END;
      keysum := keysum + Keys;
      Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
    END;
    Oberon.FadeCursor(Oberon.Mouse);
    Display.ReplConst(3, V.X, V.Y + V.H - V.dsc.H, V.W, V.dsc.H, Display.invert);
    IF Menu IS Dummy THEN V.dsc.H := 0 END;
    IF ~(0 IN keysum) THEN
      IF 1 IN keysum THEN V1 := Viewers.This(X, Y);
        IF (V1 IS DocViewer) & (Y > V1.Y + V1.H - V1(DocViewer).menuH) THEN
          Y := V1.Y + V1.H
        END;
        Viewers.Close(V); Viewers.Open(V, X, Y); Restore(V)
      ELSE
        IF Y > Y0 THEN (*extend*) dY := Y - Y0;
          V1 := Viewers.Next(V);
          IF V1.state > 1 THEN
            IF V1 IS DocViewer THEN
              IF V1.H < V1(DocViewer).menuH + 2 THEN dY := 0
                ELSIF V1.H < V1(DocViewer).menuH + 2 + dY THEN dY := V1.H - V1(DocViewer).menuH - 2
              END
            ELSIF V1.H < 1 + dY THEN dY := V1.H - 1
            END
          ELSIF V1.H < dY THEN dY := V1.H
          END;
          Viewers.Change(V, V.Y + V.H + dY);
          Oberon.RemoveMarks(V.X, V.Y, V.W, V.H);
          IF V.H > V.menuH + 1 THEN
            ModifyFrame(V, Menu, extend, V.Y + V.H - V.menuH, V.menuH);
            ModifyFrame(V, Main, extend, V.Y, V.H - V.menuH)
          ELSE (*V.H > 1*)
            ModifyFrame(V, Menu, extend, V.Y, V.H);
            ModifyFrame(V, Main, extend, V.Y + V.H - V.menuH, 0)
          END
        ELSIF Y < Y0 THEN (*reduce*) dY := Y0 - Y;
          IF V.H >= V.menuH + 2 THEN
            IF V.H < V.menuH + 2 + dY THEN dY := V.H - V.menuH - 2 END;
            Oberon.RemoveMarks(V.X, V.Y, V.W, V.H);
            H := V.H - dY;
            ModifyFrame(V, Main, reduce, V.Y, H - V.menuH);
            ModifyFrame(V, Menu, reduce, V.Y + H - V.menuH, V.menuH);
            Viewers.Change(V, V.Y + H)
          END
        END
      END
    END;
    IF AvoidLostViewer & (V.Y+V.H < 20) THEN
		Viewers.Change(V, 20); Restore(V)
	END
  END Change;

  PROCEDURE Suspend (V: DocViewer);
    VAR Menu, Main: Display.Frame;
  BEGIN
    Menu := V.dsc; Main := V.dsc.next;
    ModifyFrame(V, Main, reduce, V.Y + V.H - V.menuH, 0);
    ModifyFrame(V, Menu, reduce, V.Y + V.H (* ps - 1 *), 0)
  END Suspend;
  
PROCEDURE DocViewerNeutralize(F: DocViewer);
VAR main: Gadgets.Frame; S: Display.SelectMsg;
BEGIN
	main := F.dsc.next(Gadgets.Frame);
	IF Gadgets.selected IN main.state THEN
		S.F := main; S.res := -1; S.x := 0; S.y := 0;
		S.id := Display.reset; F.time := 0;
		main.handle(main, S);
		Gadgets.Update(main)
	END
END DocViewerNeutralize;

PROCEDURE DocViewerHandleSelect(F: DocViewer; VAR M: Oberon.InputMsg);
VAR main: Gadgets.Frame; S: Display.SelectMsg; keysum: SET; C: Objects.CopyMsg;
BEGIN
	main := F.dsc.next(Gadgets.Frame);
	S.F := main; S.res := -1; S.x := 0; S.y := 0;
	IF Gadgets.selected IN main.state THEN
		S.id := Display.reset; F.time := 0
	ELSE
		S.id := Display.set; F.time := Oberon.Time()
	END;
	main.handle(main, S);
	Gadgets.Update(main); keysum := M.keys;
	REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {};
	M.res := 0;
	IF (keysum = {0, 2}) & (S.id = Display.set) THEN (* RL delete selection *)
			(* nothing *)
	ELSIF (keysum = {0, 1}) & (S.id = Display.set) THEN  (* RM copy to focus *)
		C.id := Objects.deep; C.obj := NIL; Objects.Stamp(C); main.handle(main, C);
		IF C.obj # NIL THEN
			Gadgets.Integrate(C.obj)
		END
	END
END DocViewerHandleSelect;

  PROCEDURE DocViewerHandle* (V: Objects.Object; VAR M: Objects.ObjMsg);
    VAR Menu, Main: Display.Frame; V1: DocViewer;
  BEGIN
    WITH V: DocViewer DO
      Menu := V.dsc; Main := V.dsc.next; M.dlink := V; V.dlink := NIL;
      IF M IS Oberon.InputMsg THEN
        WITH M: Oberon.InputMsg DO
          IF M.id = Oberon.track THEN
            IF (M.Y > V.Y + V.H - 5) & (Menu IS Dummy) & (2 IN M.keys) THEN Change(V, M.X, M.Y, M.keys)
            ELSIF M.Y < V.Y + V.H - V.menuH THEN Main.handle(Main, M);
            	IF (M.res < 0) & (M.keys = {0}) & Effects.InBorder(M.X, M.Y, V.X, V.Y, V.W, V.H - V.menuH) THEN
            		DocViewerHandleSelect(V, M)
            	END
            ELSIF M.Y < V.Y + V.H - 1 THEN
              Menu.handle(Menu, M);
              IF (M.res < 0) & (2 IN M.keys) THEN Change(V, M.X, M.Y, M.keys) END
            END;
            IF M.res < 0 THEN Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y) END
          ELSE Menu.handle(Menu, M); Main.handle(Main, M);
          END
        END
      ELSIF M IS Oberon.ControlMsg THEN
        WITH M: Oberon.ControlMsg DO
          IF M.id = Oberon.mark THEN
          	IF (M.X >= V.X) & (M.X < V.X + V.W) & (M.Y >= V.Y) & (M.Y < V.Y + V.H) THEN
          		Oberon.FadeCursor(Oberon.Mouse);
                 Oberon.DrawCursor(Oberon.Pointer, Oberon.Star, M.X, M.Y);
                 Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, M.X, M.Y);
              END
          ELSE Menu.handle(Menu, M); Main.handle(Main, M)
          END;
          IF M.id = Oberon.neutralize THEN DocViewerNeutralize(V) END
        END
	ELSIF M IS Display.SelectMsg THEN
		WITH M: Display.SelectMsg DO
			IF M.id = Display.get THEN
				IF (V.time > M.time) & (Gadgets.selected IN Main(Gadgets.Frame).state) THEN
					M.time := V.time; M.sel := V; M.obj := Main
				END
			END;
			Menu.handle(Menu, M); Main.handle(Main, M)
		END

       ELSIF M IS Display.LocateMsg THEN
         WITH M: Display.LocateMsg DO
           IF M.F = NIL THEN Menu.handle(Menu, M); Main.handle(Main, M) END
         END
       ELSIF M IS Display.ModifyMsg THEN
         WITH M: Display.ModifyMsg DO
            IF M.F = V THEN ModifyDocViewer(V, M.id, M.Y, M.H)
            ELSE
              IF M.F # Menu THEN Menu.handle(Menu, M) END;
              IF M.F # Main THEN Main.handle(Main, M) END
            END
         END
       ELSIF M IS Objects.CopyMsg THEN
         WITH M: Objects.CopyMsg DO CopyDocViewer(V(DocViewer), V1); M.obj := V1 END
      ELSIF M IS Objects.LinkMsg THEN
      	WITH M: Objects.LinkMsg DO
      		IF (M.id = Objects.get) & (M.name = "Model") THEN M.obj := V.dsc.next; M.res := 0 END
      	END
      ELSIF M IS Objects.AttrMsg THEN
      	WITH M: Objects.AttrMsg DO
      		IF (M.id = Objects.get) THEN
      			IF M.name = "Locked" THEN M.res := 0; M.class := Objects.Bool; M.b := TRUE
      			ELSIF M.name = "Absolute" THEN M.res := 0; M.class := Objects.Bool; M.b := TRUE
      			END
      		END
      	END
       ELSIF M IS Display.ControlMsg THEN
         WITH M: Display.ControlMsg DO
           IF M.id = Display.restore THEN Restore(V)
           ELSIF M.id = Display.suspend THEN Suspend(V)
           ELSE Menu.handle(Menu, M); Main.handle(Main, M)
           END
         END
	ELSIF M IS Documents.LocateMsg THEN (* added 25.3.94 *)
		WITH M: Documents.LocateMsg DO
			Main.handle(Main, M);
			IF (M.doc = NIL) & Effects.Inside(M.X, M.Y, V.X, V.Y, V.W, V.H) THEN
				M.doc := ViewerDoc(V);
			END
		END
      ELSE Menu.handle(Menu, M); Main.handle(Main, M)
      END
    END
  END DocViewerHandle;

  (** Create and open a new DocViewer. Analogue to  old-fashioned MenuViewers.New. X, Y indicate the opening position. *)
  PROCEDURE NewDocViewer*(Menu, Main: Display.Frame; menuH, X, Y: INTEGER): DocViewer; 
    VAR V: DocViewer;
  BEGIN NEW(V);
    IF Menu = NIL THEN menuH := 0; Menu := NewDummy() END;
    V.handle := DocViewerHandle; V.dsc := Menu; V.dsc.next := Main; V.menuH := menuH;
    Viewers.Open(V, X, Y); Restore(V);
    RETURN V
  END NewDocViewer;

(* ===================== default handler for document frames ================ *)

PROCEDURE^ Init*(F: DocGadget; menu, main: Gadgets.Frame; adjust: BOOLEAN);

(** Returns the menubar of a DocGadget. *)
PROCEDURE Menu*(F: DocGadget): Gadgets.Frame;
BEGIN
	IF F.dsc # NIL THEN RETURN F.dsc(Gadgets.Frame)
	ELSE RETURN NIL
	END
END Menu;

(** Returns the contents of a DocGadget. *)
PROCEDURE Main*(F: DocGadget): Gadgets.Frame;
BEGIN
	IF F.dsc.next # NIL THEN RETURN F.dsc.next(Gadgets.Frame)
	ELSE RETURN NIL
	END
END Main;

PROCEDURE SetMask(F: Gadgets.Frame; M: Display3.Mask);
VAR O: Display3.OverlapMsg;
BEGIN O.M := M; O.x := 0; O.y := 0; O.F := F; O.dlink := NIL; O.res := -1; F.handle(F, O);
END SetMask;

PROCEDURE SetMainMask(F: DocGadget);
VAR main: Gadgets.Frame; R: Display3.Mask;
BEGIN
	main := Main(F);
	IF main # NIL THEN
		IF F.mask = NIL THEN SetMask(main, NIL)
		ELSE
			Display3.Copy(F.mask, R); R.x := 0; R.y := 0;
			Display3.Intersect(R, main.X,  main.Y, main.W,  main.H);
			R.x := -main.X; R.y := -(main.Y + main.H - 1); Display3.Shift(R);
			SetMask(main, R)
		END
	END
END SetMainMask;

PROCEDURE SetMenuMask(F: DocGadget);
VAR menu: Gadgets.Frame; R: Display3.Mask;
BEGIN
	menu := Menu(F);
	IF menu # NIL THEN
		IF F.mask = NIL THEN SetMask(menu, NIL)
		ELSE
			Display3.Copy(F.mask, R); R.x := 0; R.y := 0;
			Display3.Intersect(R, menu.X,  menu.Y, menu.W,  menu.H);
			R.x := -menu.X; R.y := -(menu.Y + menu.H - 1); Display3.Shift(R);
			SetMask(menu, R)
		END
	END
END SetMenuMask;

PROCEDURE ToMain(F: DocGadget; x, y: INTEGER; VAR M: Display.FrameMsg);
VAR main: Gadgets.Frame; Mdlink, Fdlink: Objects.Object; tx, ty: INTEGER;
BEGIN
	main := Main(F);
	IF main # NIL THEN
		tx := M.x; ty := M.y; M.x := x; M.y := y + F.H - 1;
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F; main.handle(main, M);
		F.dlink := Fdlink; M.dlink := Mdlink;
		M.x := tx; M.y := ty
	END
END ToMain;

PROCEDURE ToMenu(F: DocGadget; x, y: INTEGER; VAR M: Display.FrameMsg);
VAR menu: Gadgets.Frame; Mdlink, Fdlink: Objects.Object; tx, ty: INTEGER;
BEGIN
	menu := Menu(F);
	IF menu # NIL THEN
		tx := M.x; ty := M.y; M.x := x; M.y := y + F.H - 1;
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F; menu.handle(menu, M);
		F.dlink := Fdlink; M.dlink := Mdlink;
		M.x := tx; M.y := ty
	END
END ToMenu;

PROCEDURE PositionMain(F: DocGadget; VAR X, Y, W, H: INTEGER);
VAR border: INTEGER; menu: Gadgets.Frame;
BEGIN
	menu := Menu(F);
	IF menu # NIL THEN border := menu.H ELSE border := 0 END;
	X := leftBorder; Y := -F.H + 1; W := F.W - leftBorder; H := F.H - border
END PositionMain;

PROCEDURE AdjustDocGadget(F: DocGadget; VAR M: Display.ModifyMsg);
VAR main, menu: Gadgets.Frame; A: Display.ModifyMsg; border: INTEGER;
BEGIN
	menu := Menu(F); main := Main(F);
	IF menu # NIL THEN border := menu.H ELSE border := 0 END;
	
	IF main # NIL THEN
		(* Adjust main *)
		A.id := Display.extend; A.F := main; A.mode := Display.state;
		A.X := leftBorder; A.Y := -M.H + 1; A.W := M.W - leftBorder; A.H := M.H - border;
		A.dX := A.X - main.X; A.dY := A.Y - main.Y; A.dW := A.W - main.W; A.dH := A.H - main.H;
		A.dlink := M.dlink; A.res := -1; Objects.Stamp(A);
		ToMain(F, M.x + F.X, M.y + F.Y, A)
	END;
	
	IF menu # NIL THEN
		(* Adjust menu *)
		A.id := Display.extend; A.F := menu; A.mode := Display.state;
		A.X := leftBorder; A.Y := -border + 1; A.W := M.W - leftBorder; A.H := border;
		A.dX := A.X - menu.X; A.dY := A.Y - menu.Y; A.dW := A.W - menu.W; A.dH := A.H - menu.H;
		A.dlink := M.dlink; A.res := -1; Objects.Stamp(A);
		ToMenu(F, M.x + F.X, M.y + F.Y, A)
	END;
	Gadgets.framehandle(F, M)
END AdjustDocGadget;

(* -- docviewer main frame changed; have to adjust docviewer size *)
PROCEDURE AdjustChildDocGadget(F: DocGadget; VAR M: Display.ModifyMsg);
VAR menu: Gadgets.Frame; A: Display.ModifyMsg;
BEGIN
	IF M.stamp # F.stamp THEN
		F.stamp := M.stamp; menu := Menu(F);

		A.id := Display.extend; A.F := F; A.mode := M.mode;
		A.W := leftBorder + M.W; A.H := M.H;
		IF menu # NIL THEN INC(A.H, menu.H) END;
		A.dW := A.W - F.W; A.dH := A.H - F.H;

		A.X := F.X + M.dX; A.Y := F.Y + M.dY;
		A.dX := A.X - F.X; A.dY := A.Y - F.Y;
		Display.Broadcast(A)
	END
END AdjustChildDocGadget;

PROCEDURE RestoreDocGadget(F: DocGadget; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Display.DisplayMsg);
VAR menu, main: Gadgets.Frame; D: Display.DisplayMsg; b: INTEGER;

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
	
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	menu := Menu(F); main := Main(F);
	IF menu # NIL THEN b := menu.H ELSE b := 0 END;
	IF leftBorder > 0 THEN
		Display3.ReplConst(R, frameColor, x, y, leftBorder, h, Display.replace)
	END;
	IF M.id = Display.area THEN
		IF main # NIL THEN
			(* display main frame *)
			D.device := Display.screen; D.id := Display.area; D.F := main; D.u := M.u - leftBorder;
			D.v :=  M.v + b; D.w := M.w; D.h := M.h;
			ClipAgainst(D.u, D.v, D.w, D.h, 0, -main.H +1, main.W, main.H);
			D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMain(F, x, y, D);
		ELSE
			Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x + leftBorder, y, w-leftBorder, h - b, 1, Display.replace);
			Display3.String(R, Display3.FG,  x + leftBorder + 5, y + h - b - 20, Fonts.Default, "Document not found", Display.paint);
		END;
		IF menu # NIL THEN
			D.device := Display.screen; D.id := Display.area; D.F := menu; D.u := M.u - leftBorder;
			D.v := M.v; D.w := M.w; D.h := M.h;
			ClipAgainst(D.u, D.v, D.w, D.h, 0, -menu.H +1, menu.W, menu.H);
			D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMenu(F, x, y, D)
		END
	ELSE
		IF main # NIL THEN
			D.device := Display.screen; D.id := Display.full; D.F := main; D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMain(F, x, y, D)
		ELSE
			Display3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x + leftBorder, y, w-leftBorder, h - b, 1, Display.replace);
			Display3.String(R, Display3.FG,  x + leftBorder + 5, y + h - b -  20, Fonts.Default, "Document not found", Display.paint);
		END;
		IF menu # NIL THEN
			D.device := Display.screen; D.id := Display.full; D.F := menu; D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			ToMenu(F, x, y, D)
		END
	END;
	IF Gadgets.selected IN F.state THEN
		Display3.FillPattern(R, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
	END
END RestoreDocGadget;

PROCEDURE PrintDocGadget(F: DocGadget; VAR M: Display.DisplayMsg);
VAR menu, main: Display.Frame; b, x, y, w, h: INTEGER; PM: Display.DisplayMsg; R: Display3.Mask;

	PROCEDURE P(x: INTEGER): INTEGER;
	BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
	END P;

BEGIN
	IF M.id = Display.full THEN
		menu := Menu(F); main := Main(F);
		IF menu # NIL THEN b := menu.H ELSE b := 0 END;
		IF main # NIL THEN
			PM.device := Display.printer; PM.id := Display.full; PM.x := M.x; PM.y := M.y;
			PM.res := -1; PM.F := main; PM.dlink := M.dlink;
			main.handle(main, PM)
		ELSE
			Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
			x := M.x; y := M.y; w := P(F.W); h := P(F.H);
			Printer3.FilledRect3D(R, Display3.FG, Display3.FG, Display3.BG, x, y, w, h - P(b), 1, Display.replace);
			Printer3.String(R, Display3.FG,  x + 5, y + h - P(b +  20), Fonts.Default, "Document not found", Display.paint);
		END;
		IF menu # NIL THEN
			PM.device := Display.printer; PM.id := Display.full; PM.x := M.x; PM.y := M.y + P(F.H - b);
			PM.res := -1; PM.F := menu; PM.dlink := M.dlink;
			menu.handle(menu, PM)
		END
	END
END PrintDocGadget;

PROCEDURE CopyDocGadget*(VAR M: Objects.CopyMsg; from, to: DocGadget);
VAR menu, main, menu0, main0: Gadgets.Frame; C: Objects.CopyMsg;
BEGIN
	Gadgets.CopyFrame(M, from, to);
	
	menu := Menu(from); main := Main(from);
	IF main # NIL THEN
		C.id := Objects.shallow; Objects.Stamp(C); main.handle(main, C);
		main0 := C.obj(Gadgets.Frame)
	ELSE main0 := NIL
	END;
	
	IF menu # NIL THEN
		C.id := Objects.shallow; Objects.Stamp(C); menu.handle(menu, C);
		menu0 := C.obj(Gadgets.Frame)
	ELSE menu0 := NIL
	END;
	IF menu0 = NIL THEN to.dsc := main0
	ELSE to.dsc := menu0; menu0.next := main0
	END;
END CopyDocGadget;
	
PROCEDURE StoreDocGadget(F: DocGadget; VAR M: Objects.FileMsg);
BEGIN
	Files.WriteInt(M.R, 1);
	Files.WriteSet(M.R, {});
	Gadgets.WriteRef(M.R, F.lib, Main(F));
	Gadgets.framehandle(F, M)
END StoreDocGadget;

PROCEDURE LoadDocGadget(F: DocGadget; VAR M: Objects.FileMsg);
VAR x, i, j: INTEGER; tmp: SET; obj: Objects.Object; main: Gadgets.Frame;  title: ARRAY 128 OF CHAR;
		L: Objects.LinkMsg; A: Objects.AttrMsg;
BEGIN
	Files.ReadInt(M.R, x);
	IF x # 1 THEN HALT(99) END;
	Files.ReadSet(M.R, tmp);
	Gadgets.ReadRef(M.R, F.lib, obj);
	Gadgets.framehandle(F, M);
	
	IF (obj # NIL) & (obj IS Gadgets.Frame) THEN main := obj(Gadgets.Frame);
	ELSE main := NIL
	END;
	
	(* Menu *)
	L.obj := NIL; L.res := -1;
	IF main # NIL THEN
		L.id := Objects.get; L.name := "DeskMenu"; main.handle(main, L)
	END; 
	IF (L.obj # NIL) & (L.obj IS Gadgets.Frame) & (L.res >= 0) THEN obj :=  L.obj
	ELSE
		title := "Desktops.CloseDoc[Close] ";
		IF (main # NIL) THEN
			A.id := Objects.get; A.name := "Menu"; A.res := -1; A.s := ""; obj.handle(obj, A);
			IF (A.res >= 0) & (A.class = Objects.String) & (A.s # "") THEN
				i := 0; WHILE title[i] # 0X DO INC(i) END;
				j := 0; WHILE A.s[j] # 0X DO title[i] := A.s[j]; INC(i); INC(j) END;
				title[i] := 0X
			END
		END;
		obj := NewMenu(title)
	END;
	(* F.Y := F.Y + F.H - main.H - menuH; *)
	Init(F, obj(Gadgets.Frame), main, FALSE)
END LoadDocGadget;

PROCEDURE DocGadgetAttr(F: DocGadget; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN M.s := "Desktops.NewDocGadget"; M.class := Objects.String; M.res := 0
		ELSE Gadgets.framehandle(F, M)
		END
	ELSE Gadgets.framehandle(F, M)
	END
END DocGadgetAttr;

PROCEDURE LinkMenu(F: DocGadget; obj: Objects.Object);
VAR new, main, menu: Gadgets.Frame; h: INTEGER;
BEGIN
	IF (obj # NIL) & (obj IS Gadgets.Frame) THEN
		new := obj(Gadgets.Frame); h := new.H
	ELSE new := NIL; h := 0;
	END;
	
	main := Main(F); menu := Menu(F);
	IF menu = NIL THEN INC(F.H, h)
	ELSE F.H := F.H - menu.H + h
	END;
	Init(F, new, main, FALSE)
END LinkMenu;

PROCEDURE DocGadgetLink(F: DocGadget; VAR M: Objects.LinkMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Model" THEN M.obj := Main(F); M.res := 0
		ELSIF M.name = "Menu" THEN M.obj := Menu(F); M.res := 0
		END
	ELSIF M.id = Objects.set THEN
		IF (M.name = "Menu") THEN LinkMenu(F, M.obj); M.res := 0 END
	END
END DocGadgetLink;

PROCEDURE Neutralize(F: DocGadget);
VAR main: Gadgets.Frame; S: Display.SelectMsg;
BEGIN
	main := Main(F);
	IF (main # NIL) & (Gadgets.selected IN main.state) THEN
		S.F := main; S.res := -1; S.x := 0; S.y := 0;
		S.id := Display.reset; F.time := 0;
		ToMain(F, 0, 0, S);
		Gadgets.Update(main)
	END
END Neutralize;

PROCEDURE HandleSelect(F: DocGadget; VAR M: Oberon.InputMsg);
VAR main: Gadgets.Frame; S: Display.SelectMsg; keysum: SET; C: Objects.CopyMsg;
BEGIN
	main := Main(F);
	IF main # NIL THEN
		S.F := main; S.res := -1; S.x := 0; S.y := 0;
		IF Gadgets.selected IN main.state THEN S.id := Display.reset; F.time := 0; ELSE S.id := Display.set; F.time := Oberon.Time() END;
		ToMain(F, M.x + F.X, M.y + F.Y, S);
		Gadgets.Update(main); keysum := M.keys;
		REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys UNTIL M.keys = {};
		M.res := 0;
		IF (keysum = {0, 2}) & (S.id = Display.set) THEN (* RL delete selection *)
			(* nothing *)
		ELSIF (keysum = {0, 1}) & (S.id = Display.set) THEN  (* RM copy to focus *)
			C.id := Objects.deep; C.obj := NIL; Objects.Stamp(C); main.handle(main, C);
			IF C.obj # NIL THEN
				Gadgets.Integrate(C.obj)
			END
		END
	END
END HandleSelect;

PROCEDURE TrackDocGadget(F: DocGadget; x, y, w, h, border: INTEGER; VAR M: Oberon.InputMsg);
VAR PM: Gadgets.PriorityMsg;
BEGIN
	IF M.Y >= y + h - border THEN
		IF M.keys = {2} THEN (* to front first *)
			PM.id :=  Gadgets.visible; PM.passon := TRUE; PM.F := F; Display.Broadcast(PM)
		END;

		ToMenu(F, x, y, M);
		IF (M.res < 0) & ~Gadgets.InActiveArea(F, M) THEN Gadgets.framehandle(F, M) END
	ELSE
		IF M.keys = {2} THEN (* to front first *)
			PM.id :=  Gadgets.visible; PM.passon := TRUE; PM.F := F; Display.Broadcast(PM)
		END;
		IF ~Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
			Gadgets.framehandle(F, M)
		ELSE
			ToMain(F, x, y, M);
			IF (M.res < 0) & (M.keys = {0}) THEN HandleSelect(F, M) END;
			IF (M.res < 0) & ~Gadgets.InActiveArea(F, M) THEN Gadgets.framehandle(F, M) END
		END
	END
END TrackDocGadget;

PROCEDURE DocGadgetHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h: INTEGER; F0: DocGadget; R: Display3.Mask; obj: Objects.Object; main, menu: Gadgets.Frame;
	border: INTEGER; N: Oberon.ControlMsg; tM: Display.DisplayMsg;
BEGIN
	WITH F: DocGadget DO
		IF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				IF (M.F = NIL) OR (M.F = F) THEN	(* message addressed to this frame *)
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates *)
					menu := Menu(F); main := Main(F);
					IF menu # NIL THEN border := menu.H ELSE border := 0 END;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.id = Display.full) OR (M.F = NIL) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreDocGadget(F, R, x, y, w, h, M)
								ELSIF M.id = Display.area THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreDocGadget(F, R, x, y, w, h, M)
								END
							ELSIF M.device = Display.printer THEN PrintDocGadget(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) THEN TrackDocGadget(F, x, y, w, h, border, M)
							ELSIF ~(Gadgets.selected IN F.state) THEN ToMain(F, x, y, M); ToMenu(F, x, y, M)
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						IF M.F = F THEN AdjustDocGadget(F, M(Display.ModifyMsg));
						ELSE Gadgets.framehandle(F, M)
						END
					ELSIF M IS Display.LocateMsg THEN
						WITH M: Display.LocateMsg DO
							IF (M.loc = NIL) & Effects.Inside(M.X, M.Y, x, y, w, h) THEN
								IF M.Y >= y + h - border THEN ToMenu(F, x, y, M)
								ELSE ToMain(F, x, y, M)
								END;
								IF M.loc = NIL THEN M.loc := F; M.u := M.X - x; M.v := M.Y - (y + h - 1); M.res := 0 END;
							END
						END
					ELSIF M IS Display.SelectMsg THEN
						WITH M: Display.SelectMsg DO
							IF M.id = Display.set THEN
								Neutralize(F);
								N.id := Oberon.neutralize; N.F := NIL; N.res := -1; ToMain(F, x, y, N); ToMenu(F, x, y, N);
							ELSIF M.id = Display.reset THEN
							ELSIF M.id = Display.get THEN
								main := Main(F);
								IF (F.time > M.time) & (Gadgets.selected IN main.state) THEN
									M.time := F.time; M.sel := F; M.obj := main
								END
							END;
							IF M.F # NIL THEN Gadgets.framehandle(F, M) 
							ELSE ToMain(F, x, y, M); ToMenu(F, x, y, M)
							END
						END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF M.F = F THEN (* have to create own mask *)
								NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
								SetMainMask(F); SetMenuMask(F);
								M.res := 0;
							END
						END
					ELSIF M IS Display3.OverlapMsg THEN
						WITH M: Display3.OverlapMsg DO
							IF (M.F = F) OR (M.F = NIL) THEN F.mask := M.M; SetMainMask(F); SetMenuMask(F) END
						END
					ELSIF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF F.mask = NIL THEN Gadgets.MakeMask(F, x, y, M.dlink, R) END;
							SetMainMask(F); SetMenuMask(F);
						END
					ELSIF M IS Oberon.ControlMsg THEN
						WITH M: Oberon.ControlMsg DO
							ToMain(F, x, y, M); ToMenu(F, x, y, M);
							IF M.id = Oberon.neutralize THEN Neutralize(F) END
						END
					ELSIF M IS Documents.LocateMsg THEN (* added 25.3.94 *)
						WITH M: Documents.LocateMsg DO
							ToMain(F, x, y, M);
							obj := Main(F);
							IF M.doc # obj THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								IF Effects.Inside(M.X, M.Y, x, y, w, h) & Display3.Visible(R, M.X, M.Y, 1, 1) & (obj IS Documents.Document) THEN
									M.doc := obj(Documents.Document);
								END
							END
						END
					ELSIF M IS Gadgets.UpdateMsg THEN
						WITH M: Gadgets.UpdateMsg DO
							IF M.obj = main THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								tM.device := Display.screen; tM.id := Display.full; tM.dlink := M.dlink;
								RestoreDocGadget(F, R, x, y, w, h, tM);
							ELSE ToMain(F, x, y, M); ToMenu(F, x, y, M)
							END;
							IF Gadgets.lockedsize IN main.state THEN INCL(F.state, Gadgets.lockedsize)
							ELSE EXCL(F.state, Gadgets.lockedsize)
							END
						END
					ELSIF M.F # NIL THEN Gadgets.framehandle(F, M) 
					ELSE ToMain(F, x, y, M); ToMenu(F, x, y, M)
					END
				ELSE (* not for this frame but perhaps for a child *)	
					main := Main(F);
					IF M IS Display3.UpdateMaskMsg THEN
						WITH M: Display3.UpdateMaskMsg DO
							IF M.F = main THEN
								IF F.mask = NIL THEN Gadgets.MakeMask(F, x, y, M.dlink, R) END;
								SetMainMask(F); SetMenuMask(F)
							ELSE ToMain(F, M.x + F.X, M.y + F.Y, M)
							END
						END
					ELSIF M IS Display.ConsumeMsg THEN
						WITH M: Display.ConsumeMsg DO
							IF (M.obj IS DocGadget) THEN (* prevent consumption *)
							ELSE ToMain(F, M.x + F.X, M.y + F.Y, M)
							END
						END
					ELSIF M IS Display.ModifyMsg THEN
						IF M.F = main THEN AdjustChildDocGadget(F, M(Display.ModifyMsg))
						ELSE ToMain(F, M.x + F.X, M.y + F.Y, M); ToMenu(F, M.x + F.X, M.y + F.Y, M)
						END
					ELSIF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg DO
							IF (M.device = Display.screen) & (M.F = main) THEN
								Oberon.RemoveMarks(M.x + F.X, M.y + F.Y, F.W, F.H)
							END;
							ToMain(F, M.x + F.X, M.y + F.Y, M); ToMenu(F, M.x + F.X, M.y + F.Y, M)
						END
					ELSE ToMain(F, M.x + F.X, M.y + F.Y, M); ToMenu(F, M.x + F.X, M.y + F.Y, M)
					END
				END
			END
			
		(* Object messages *)
		ELSIF M IS Objects.AttrMsg THEN DocGadgetAttr(F, M(Objects.AttrMsg))
		ELSIF M IS Objects.LinkMsg THEN DocGadgetLink(F, M(Objects.LinkMsg))
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN StoreDocGadget(F, M)
				ELSIF M.id = Objects.load THEN LoadDocGadget(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = F.stamp THEN M.obj := F.dlink	(* copy msg arrives again *)
				ELSE	(* first time copy message arrives *)
					NEW(F0); F.stamp := M.stamp; F.dlink := F0; CopyDocGadget(M, F, F0); M.obj := F0
				END
			END
		ELSIF M IS Objects.BindMsg THEN
			main := Main(F); IF main # NIL THEN main.handle(main, M) END;
			Gadgets.framehandle(F, M);
		ELSE	(* unknown msg, framehandler might know it *)
			Gadgets.framehandle(F, M)
		END
	END
END DocGadgetHandler;

PROCEDURE NewDocGadget*;
VAR F: DocGadget;
BEGIN
	NEW(F); F.handle := DocGadgetHandler; F.W := Display.Width DIV 8 * 3; F.H := 200; Objects.NewObj := F;
END NewDocGadget;

(** Initialize a DocGadget with a menu and main frame. The adjust flag is TRUE if the DocGadget should determine its
size according to the combined size of the menu and main frames. This is the default case. *)
PROCEDURE Init*(F: DocGadget; menu, main: Gadgets.Frame; adjust: BOOLEAN);
VAR A: Display.ModifyMsg; oldH: INTEGER;
BEGIN
	IF menu = NIL THEN HALT(99) END;
	
	IF adjust THEN
		F.W := 0; F.H := 0;
		INC(F.H, menu.H);
		IF (main # NIL) & (main.H > 0) THEN
			INC(F.H, main.H); INC(F.W, main.W)
		ELSE
			INC(F.W, Display.Width DIV 8 * 3); INC(F.H, 200)
		END;
	END;
	
	F.dsc := menu; menu.next := main;
	
	A.id := Display.extend; A.mode := Display.state; A.F := menu; A.res := -1; A.x := 0; A.y := 0;
	A.dlink := NIL; Objects.Stamp(A);
	(* ps - 12.12.96 *)
	oldH := menu.H;
	A.X := menu.X; A.Y := menu.Y + oldH - 1; A.W := menu.W; A.H := 0;
	A.dX := A.X - menu.X; A.dY := A.Y - menu.Y; A.dW := A.W - menu.W; A.dH := A.H - menu.H;
	menu.handle(menu, A);
	menu.X := leftBorder; menu.Y := 0;
	A.res := -1; Objects.Stamp(A);
	A.X := leftBorder; A.Y := -oldH + 1; A.W := F.W - leftBorder; A.H := oldH;
	A.dX := A.X - menu.X; A.dY := A.Y - menu.Y; A.dW := A.W - menu.W; A.dH := A.H - menu.H;
	menu.handle(menu, A);
	
	IF main # NIL THEN
		A.id := Display.extend; A.mode := Display.state; A.F := main; A.res := -1; A.x := 0; A.y := 0;
		A.dlink := NIL; Objects.Stamp(A);
		PositionMain(F, A.X, A.Y, A.W, A.H);
		A.dX := A.X - main.X; A.dY := A.Y - main.Y; A.dW := A.W - main.W; A.dH := A.H - main.H;
		IF Gadgets.lockedsize IN main.state THEN INCL(F.state, Gadgets.lockedsize) END;
		main.handle(main, A);
	END;
	INCL(F.state, Gadgets.lockedcontents)
END Init;

(* ===================== Menu bar =================================*)

PROCEDURE newMenu(name, menubar: ARRAY OF CHAR): Display.Frame;
VAR obj, list: Objects.Object; P, f: Gadgets.Frame; X, p: INTEGER; cmd, title: ARRAY 64 OF CHAR;
	C: Display.ConsumeMsg; i: LONGINT;
	
	PROCEDURE Button(caption, command: ARRAY OF CHAR);
	BEGIN
		obj := Gadgets.CreateObject("BasicGadgets.NewButton"); f := obj(Gadgets.Frame);
		f.X := X; f.Y := p; f.H := menuH - 2*p; f.W := menuButtonW;
		f.slink := list; list := f;
		
		Attributes.SetString(f, "Caption", caption);
		Attributes.SetString(f, "Cmd", command);
		Attributes.SetBool(f, "Popout", TRUE);
		INC(X, f.W);
	END Button;

	PROCEDURE GetString(VAR s: ARRAY OF CHAR);
	VAR term: CHAR;  j: LONGINT;
	BEGIN
		WHILE menubar[i] = " " DO INC(i) END;
		IF menubar[i] = "'" THEN
			INC(i);  term := "'"
		ELSIF menubar[i] = "[" THEN
			INC(i);  term := "]"
		ELSE
			term := 0X
		END;
		j := 0;
		IF term = 0X THEN
			WHILE (menubar[i] # 0X) & (menubar[i] # " ") & (menubar[i] # "[") & (menubar[i] # "'") DO
				s[j] := menubar[i];  INC(i);  INC(j)
			END
		ELSE
			WHILE (menubar[i] # 0X) & (menubar[i] # term) DO
				s[j] := menubar[i];  INC(i);  INC(j)
			END;
			IF menubar[i] = term THEN INC(i) END
		END;
		s[j] := 0X;
		WHILE menubar[i] = " " DO INC(i) END
	END GetString;

	PROCEDURE GenTitle(VAR cmd, title: ARRAY OF CHAR);
	VAR j, k: LONGINT;
	BEGIN
		j := 0; WHILE (cmd[j] # ".") & (cmd[j] # 0X) & (cmd[j] # " ") DO INC(j) END;
		IF cmd[j] = "." THEN
			k := 0; INC(j);
			WHILE (cmd[j] # 0X) & (cmd[j] # " ") DO title[k] := cmd[j]; INC(k); INC(j) END;
			title[k] := 0X
		ELSE
			COPY(cmd, title)
		END
	END GenTitle;

BEGIN
	p := 1; list := NIL; X := 0;
	obj := Gadgets.CreateObject("Panels.NewPanel"); P := obj(Gadgets.Frame);
	P.W := Display.Width; P.H := menuH;
	(* PanelHandler := P.handle; (* cache *) (deactivated - ps) *)
	
	(* name plate *)
	obj := Gadgets.CreateObject("NamePlates.NewNamePlate"); f := obj(Gadgets.Frame);
	f.X := X; f.Y := 0; f.H := menuH; f.W := namePlateW;
	INC(X, f.W);
	f.slink := list; list := f;
	IF name # "" THEN Attributes.SetString(f, "Value", name) END;

	Button("Close", "Desktops.CloseDoc");
	Button("Hide", "Finder.Minimize");
	Button("Grow", "Desktops.Grow");

	i := 0;
	WHILE menubar[i] # 0X DO
		GetString(cmd);
		IF menubar[i] = "[" THEN
			GetString(title)
		ELSE
			GenTitle(cmd, title)
		END;
		Button(title, cmd)
	END;

	C.id := Display.drop; C.obj := list; C.x := 0; C.y := 0; C.F := P; C.u := 0; C.v := -P.H + 1; C.res := -1; C.dlink := NIL;
	P.handle(P, C);
	
	Attributes.SetBool(P, "Locked", TRUE);
	Attributes.SetInt(P, "Color", menuC);
	Attributes.SetInt(P, "Border", 0);
(*
	P.handle := MenuHandler;
*)
	RETURN P
END newMenu;

(** Create a new menubar from the menu string. Menu strings are sequences of names. The caption
of a menu button can be set by following the name by the caption text in square brackets, for example
"MyDoc.Do[Do] MyDoc.Undo[Undo]" etc. The complete syntax is: { cmd [ title ] } . cmd = name | string . string = "'" chars "'" . title = "[" chars "]" . *)
PROCEDURE NewMenu*(menubar: ARRAY OF CHAR): Display.Frame;
BEGIN RETURN newMenu("", menubar)
END NewMenu;

(*
(** Only for compatibility with older, non-document based applications. *)
PROCEDURE NewMenuFrame*(title, menubar: ARRAY OF CHAR): Display.Frame;
BEGIN (* RETURN newMenu(title, menubar, 2, 0) OLD*)
	RETURN newMenu(title, menubar)
END NewMenuFrame;
*)

PROCEDURE ViewerDoc(V: DocViewer): Documents.Document;
VAR main: Display.Frame; d: Documents.Document; obj: Objects.Object;
BEGIN
	d := NIL;
	main := V.dsc.next;
	IF main IS Views.View THEN
		IF main(Views.View).obj # NIL THEN
			obj := main(Views.View).obj;
			IF obj IS Documents.Document THEN d := obj(Documents.Document) END
		END
	ELSIF main IS Documents.Document THEN d := main(Documents.Document)
	END;
	RETURN d
END ViewerDoc;

PROCEDURE DocGadgetDoc(F: DocGadget): Documents.Document;
VAR d: Documents.Document; main: Gadgets.Frame;
BEGIN
	d := NIL;
	main := Main(F);
	IF main # NIL THEN
		IF main IS Documents.Document THEN d := main(Documents.Document)
		END
	END;
	RETURN d
END DocGadgetDoc;

(** Document gadget enclosing the current context. *)
PROCEDURE CurDoc*(context: Objects.Object): Documents.Document;
VAR doc: Documents.Document; obj, old: Objects.Object;
BEGIN
	doc := NIL;
	IF (Oberon.Par.frame = Oberon.Par.vwr.dsc) & (Oberon.Par.vwr IS DocViewer) THEN (* in menu of DocViewer *)
		doc := ViewerDoc(Oberon.Par.vwr(DocViewer));
	ELSE
		obj := context; old := NIL;
		WHILE (obj # NIL) & (obj # old) & ~(obj IS Documents.Document) & ~(obj IS DocGadget) DO
			old := obj; obj := obj.dlink
		END;
		IF obj # NIL THEN
			IF obj IS Documents.Document THEN doc := obj(Documents.Document)
			ELSIF obj IS DocGadget THEN doc := DocGadgetDoc(obj(DocGadget));
			END
		END
	END;
	RETURN doc
END CurDoc;

(** Menu bar of the document enclosing the current context. *)
PROCEDURE CurMenu*(context: Objects.Object): Display.Frame;
VAR  obj: Objects.Object;
BEGIN
	obj := context;
	WHILE (obj # NIL) & ~((obj IS DocGadget) OR (obj IS DocViewer)) DO obj := obj.dlink END;
	IF obj # NIL THEN
		IF obj IS DocGadget THEN RETURN Menu(obj(DocGadget))
		ELSIF (obj IS DocViewer) & HasMenu(obj(DocViewer)) THEN RETURN obj(DocViewer).dsc
		ELSE RETURN NIL
		END
	ELSE RETURN NIL
	END
END CurMenu;

(** TRUE if context is within a Document-Menu. *)
PROCEDURE IsInMenu*(context: Objects.Object): BOOLEAN;
	VAR obj, L: Objects.Object;
BEGIN
	obj := context; L := NIL;
	WHILE (obj # NIL) & ~((obj IS DocGadget) OR (obj IS DocViewer)) DO
		L := obj; obj := obj.dlink
	END;
	IF obj # NIL THEN
		IF obj IS DocGadget THEN
			RETURN L = Menu(obj(DocGadget))
		ELSIF (obj IS DocViewer) & HasMenu(obj(DocViewer)) THEN
			RETURN L = obj(DocViewer).dsc
		ELSE
			RETURN FALSE
		END
	ELSE
		RETURN FALSE
	END
END IsInMenu;

(* ========Desk top commands ========== *)

PROCEDURE AddStandardThings(F: Display.Frame);
VAR list: Display.Frame; X, Y: INTEGER;C: Display.ConsumeMsg;

	PROCEDURE Title;
	VAR obj: Objects.Object; f: Display.Frame;
	BEGIN
		obj := Gadgets.CreateObject("NamePlates.NewNamePlate"); f := obj(Gadgets.Frame);
		DEC(Y, f.H + 4);
		f.X := X; f.Y := Y;
		f.slink := list; list := f;
	END Title;
	
	PROCEDURE Button(caption, command: ARRAY OF CHAR);
	VAR obj: Objects.Object; f: Display.Frame; A: Objects.AttrMsg;
	BEGIN
		obj := Gadgets.CreateObject("BasicGadgets.NewButton"); f := obj(Gadgets.Frame);
		f.H := 31; f.W := 36;
		DEC(Y, f.H + 4);
		f.X := X; f.Y := Y;
		f.slink := list; list := f;
		
		A.id := Objects.set; A.name := "Caption"; A.class := Objects.String; COPY(caption, A.s); A.res := -1;
		f.handle(f, A);
		
		A.id := Objects.set; A.name := "Cmd"; A.class := Objects.String; COPY(command, A.s); A.res := -1;
		f.handle(f, A);
		
		A.id := Objects.set; A.name := "Popout"; A.class := Objects.Bool; A.b := TRUE; A.res := -1;
		f.handle(f, A);
	END Button;
	
	PROCEDURE Finder;
	VAR obj: Objects.Object; f: Display.Frame;
	BEGIN
		obj := Gadgets.CreateObject("Finder.NewFrame"); f := obj(Gadgets.Frame);
		DEC(Y, f.H + 4);
		f.X := X; f.Y := Y;
		f.slink := list; list := f;
	END Finder;

	PROCEDURE Navigator;
	VAR obj: Objects.Object; f: Display.Frame;
	BEGIN
		obj := Gadgets.CreateObject("Navigators.NewNavigator"); f := obj(Gadgets.Frame);
		f.H := 31; f.W := 36;
		DEC(Y, f.H + 4);
		(*Y := -Display.Height + X + obj(Gadgets.Frame).H DIV 2;*)
		f.X := X; f.Y := Y;
		f.slink := list; list := f;
	END Navigator;

BEGIN
	list := NIL; X := 0; Y := 0;
	
	Title;
	INC(X,10);
	Navigator;
	Button("Close", "Desktops.Close");
	Button("Grow", "Desktops.Grow");
	Button("Copy", "System.Copy");
	Button("Store", "Desktops.Store");
	
	Finder;
	DEC(X,10);

	C.id := Display.drop; C.obj := list; C.x := 0; C.y := 0; C.F := F; C.u := 10; C.v := -(ABS(Y) + 5); C.res := -1; C.dlink := NIL;
	F.handle(F, C);
END AddStandardThings;

(** Used in the form: Desktops.Open <filename>
Tries to open <filename> as a desktop; on failure a new desktop is created. *)
PROCEDURE Open*;
VAR S: Attributes.Scanner; F: Gadgets.Frame; B: Objects.BindMsg; X, Y: INTEGER;
	obj: Objects.Object; f: Files.File; doc: Documents.Document; filename: ARRAY 64 OF CHAR; v: Views.View;
	V: DocViewer; main: Gadgets.Frame; A: Objects.AttrMsg; L: Objects.LinkMsg; P: Pictures.Picture;
	
	PROCEDURE IsDesktop(VAR f: Files.File): BOOLEAN;
	VAR R: Files.Rider; i, x, y, w, h: INTEGER; s: ARRAY 64 OF CHAR;
	BEGIN
		s := ""; h := 0; w := 0;
		Files.Set(R, f, 0);
		Files.ReadInt(R, i);
		IF (i = Documents.Id) OR (i = 0727H) THEN
			Files.ReadString(R, s);
			Files.ReadInt(R, x); Files.ReadInt(R, y); Files.ReadInt(R, w); Files.ReadInt(R, h);
		END;
		RETURN (s = "PanelDocs.NewDoc") & (w > Display.Width) & (h > Display.Height)
	END IsDesktop;
	
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		COPY(S.s, filename); f := Files.Old(filename);
		v := NIL;
		IF f = NIL THEN
			obj := Gadgets.CreateObject("PanelDocs.NewDoc");
			doc := obj(Documents.Document);
			doc.W := 2*Display.Width; doc.H := 2*Display.Height;
			
			obj := Gadgets.CreateObject("Panels.NewPanel");
			F := obj(Gadgets.Frame);
			F.W := doc.W; F.H := doc.H;
			Attributes.SetInt(F, "Border", 0);
			
			f := Files.Old("Backdrop.Pict");
			IF f # NIL THEN
				NEW(P); Pictures.Open(P, "Backdrop.Pict", TRUE);
				L.id := Objects.set; L.name := "Picture"; L.obj := P; L.res := -1;
				F.handle(F, L);
			END;
			A.id := Objects.set; A.name := "Texture"; A.b := TRUE; A.class := Objects.Bool; A.res := -1;
			F.handle(F, A);
			A.id := Objects.set; A.name := "Color"; A.i := Display3.textbackC; A.class := Objects.Int; A.res := -1;
			F.handle(F, A);
			
			NEW(B.lib); Objects.OpenLibrary(B.lib); F.handle(F, B);
			
			AddStandardThings(F);
			INCL(doc.state, 30); (* allow document consumption *)
			main := F; COPY(S.s, doc.name);
			Documents.Init(doc, main);
			
			v := Views.ViewOf(doc);
			INCL(v.state, Gadgets.lockedcontents)
		ELSIF IsDesktop(f) THEN
			obj := Gadgets.CreateObject("PanelDocs.NewDoc");
			doc := obj(Documents.Document);
			COPY(S.s, doc.name);
			doc.Load(doc);
			(*doc.W := 2*Display.Width; doc.H := 2*Display.Height;*)
			Documents.Init(doc, doc.dsc(Gadgets.Frame));
			INCL(doc.state, 30); (* allow document consumption *)
			v := Views.ViewOf(doc);
			v.W := 0; v.H := 0;
			INCL(v.state, Gadgets.lockedcontents);
		ELSE
			Texts.WriteString(W, S.s); Texts.WriteString(W,  "  not a desktop"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		IF v # NIL THEN
			Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y);
			V := NewDocViewer(NIL, v, 0, X, Y)
		END
	END
END Open;

PROCEDURE SyncPlate(doc: Documents.Document);
	VAR M: Oberon.CaretMsg;
BEGIN
	M.id := Oberon.get; M.F := NIL; M.car := NIL; M.res := -1;
	Objects.Stamp(M); Display.Broadcast(M);
	IF (M.car # NIL) & (M.car IS Gadgets.Frame) & (M.car(Gadgets.Frame).obj = doc) THEN
		Oberon.Defocus()
	END
END SyncPlate;

(** Stores the desktop from which this command is activated. *)
PROCEDURE Store*;
VAR V: Viewers.Viewer; doc: Documents.Document;
BEGIN
	V := Oberon.Par.vwr;
	IF (V # NIL) & (V IS DocViewer) THEN
		WITH V: DocViewer DO
			doc := ViewerDoc(V);
			IF doc # NIL THEN
				SyncPlate(doc);
				doc.Store(doc);
			ELSE Texts.WriteString(W, "[Desktop not found]");  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END Store;

(** Used in the form: Desktops.ChangeBackdrop <picturename>
	Changes the backdrop of the marked desktop. *)
PROCEDURE ChangeBackdrop*;
VAR S: Attributes.Scanner; V: Viewers.Viewer; doc: Documents.Document;
	A: Objects.AttrMsg;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		V := Oberon.MarkedViewer();
		IF (V # NIL) & (V IS DocViewer) THEN
			doc := ViewerDoc(V(DocViewer));
			IF doc # NIL THEN A.id := Objects.set; A.name := "Picture"; A.class := Objects.String; A.res := -1;
				COPY(S.s, A.s); doc.dsc.handle(doc.dsc, A); Gadgets.Update(doc);
			END
		END
	END
END ChangeBackdrop;

(** Grow the current DocViewer or size DocGadgets to its default size. *)
PROCEDURE Grow*;
VAR V1: Viewers.Viewer; D, D1: Documents.Document; obj: Objects.Object; cnt, DW, DH: INTEGER;
		MM: Display.ModifyMsg; M: Objects.CopyMsg; N: Display.ControlMsg;
BEGIN
	obj := Gadgets.executorObj;
	WHILE (obj # NIL ) & ~((obj IS DocViewer) OR (obj IS DocGadget)) DO obj := obj.dlink END;
	
	IF obj # NIL THEN
		IF obj IS DocViewer THEN
			WITH obj: DocViewer DO
				DH := Oberon.DisplayHeight(obj.X);
				IF obj.H < DH THEN
					V1 := Viewers.This(obj.X, 0); cnt := 0;
					WHILE (V1.state # 1) DO INC(cnt); V1 := Viewers.Next(V1) END
				ELSE
					cnt := 2
				END;
				IF cnt > 1 THEN
					DW := Oberon.DisplayWidth(obj.X);
					IF obj.H < DH - Viewers.minH THEN Oberon.OpenTrack(obj.X, obj.W)
					ELSIF obj.W < DW THEN Oberon.OpenTrack(Oberon.UserTrack(obj.X), DW)
					END;
					IF (obj.H < DH - Viewers.minH) OR (obj.W < DW) THEN
						M.id := Objects.shallow;
						obj.handle(obj, M); V1 := M.obj(Viewers.Viewer);
						Viewers.Open(V1, obj.X, DH);
						N.F := NIL; N.id := Display.restore; V1.handle(V1, N)
					END
				ELSE
					Viewers.Change(obj, DH);
					N.F := NIL; N.id := Display.restore; obj.handle(obj, N)
				END
			END
		ELSE
			WITH obj: DocGadget DO
				IF (obj.dsc # NIL) & (obj.dsc.next # NIL) THEN
					D := obj.dsc.next(Documents.Document); NEW(D1); D1^ := D^; D1.name := "";
					D1.Load(D1);
					IF D.W < D1.W THEN DW := D1.W - D.W ELSE DW := 0 END;
					IF D.H < D1.H THEN DH := D1.H - D.H ELSE DH := 0 END;
					MM.X := obj.X; MM.Y := obj.Y - DH; MM.W := obj.W + DW; MM.H := obj.H + DH;
					MM.dX := 0; MM.dY := MM.Y - obj.Y; MM.dW := MM.W - obj.W; MM.dH := MM.H - obj.H;
					MM.F := obj; Display.Broadcast(MM)
				END
			END
		END
	END
END Grow;

PROCEDURE ^ AllocateDocGadget(V: DocViewer; w, h: INTEGER; VAR F: Display.Frame; VAR u, v: INTEGER);

(** Copy the current DocViewer. *)
PROCEDURE Copy*;
VAR V1: DocViewer; D1: DocGadget; obj: Objects.Object; M: Objects.CopyMsg; N: Display.ControlMsg;
		C: Display.ConsumeMsg;
BEGIN
	obj := Gadgets.executorObj;
	WHILE (obj # NIL ) & ~((obj IS DocViewer) OR (obj IS DocGadget)) DO obj := obj.dlink END;
	IF obj # NIL THEN
		IF obj IS DocViewer THEN
			WITH obj: DocViewer DO
				M.id := Objects.shallow; Objects.Stamp(M); obj.handle(obj, M);
				V1 := M.obj(DocViewer);
				Viewers.Open(V1, obj.X, obj.Y + obj.H DIV 2);
				N.F := NIL; N.id := Display.restore; V1.handle(V1, N)
			END
		ELSE
			M.id := Objects.shallow; Objects.Stamp(M); obj.handle(obj, M);
			D1 := M.obj(DocGadget);
			IF (Oberon.Par.vwr # NIL) & (Oberon.Par.vwr IS DocViewer) THEN
				C.id := Display.drop; C.obj := D1;
				AllocateDocGadget(Oberon.Par.vwr(DocViewer), D1.W, D1.H, C.F, C.u, C.v);
				IF C.F # NIL THEN
					Display.Broadcast(C);
					N.F := NIL; N.id := Display.restore; D1.handle(D1, N)
				END
			END
		END
	END
END Copy;

(** Close the current DocViewer. *)
PROCEDURE Close*;
BEGIN Viewers.Close(Oberon.Par.vwr)
END Close;

(* ======== Doc Viewer commands ========== *)

(* work out where to put a document in the desktop *)
PROCEDURE AllocateDocGadget(V: DocViewer; w, h: INTEGER; VAR F: Display.Frame; VAR u, v: INTEGER);
VAR obj: Objects.Object; P: Gadgets.Frame; view: Views.View;
	f: Display.Frame;
BEGIN
	view := V.dsc.next(Views.View);
	obj := view.obj;
	WITH obj: Documents.Document DO P := obj.dsc(Gadgets.Frame) END;
	F := P;
	IF Oberon.Pointer.on THEN (* use hint *)
		u := Oberon.Pointer.X - V.X - view.vx; v := Oberon.Pointer.Y - (V.Y + V.H) - view.vy - h;
		
	ELSE
		u := 75;  v := -50;
		(* improve placement by making the left top corner visible *)
		IF u <= -view.vx + 50 THEN u := -view.vx + 50 END;
		IF v + h >= - view.vy - 50 THEN v := - view.vy - 50 - h END;
		
		f := P.dsc; (* check overlapping *)
		WHILE f # NIL DO
			IF (u = f.X) & (v + h = f.Y + f.H) THEN (* overlap left corner *)
				INC(u, 20);  DEC(v, 30)
			END;
			f := f.next
		END;
	END
END AllocateDocGadget;

PROCEDURE CreateMenu(D: Documents.Document; desktop, system: BOOLEAN): Display.Frame;
VAR L: Objects.LinkMsg;
BEGIN
	(* special menus *)
	L.id := Objects.get; L.obj := NIL; L.res := -1; 
	IF desktop THEN L.name := "DeskMenu";
	ELSIF system THEN L.name := "SystemMenu"
	ELSE L.name := "UserMenu"
	END;
	D.handle(D, L);
	IF (L.obj =NIL) OR ~(L.obj IS Display.Frame) OR (L.res < 0) THEN L.obj := NewMenu("") END;
	RETURN L.obj(Display.Frame)
END CreateMenu;

(** Open a document in the viewer system or in the desktop, depending on the context and the marker. *)
PROCEDURE ShowDoc*(D: Documents.Document);
VAR C: Display.ConsumeMsg; open, menu: Display.Frame; X, Y: INTEGER; v: Viewers.Viewer; V: DocViewer;
	A: Objects.AttrMsg; DF: DocGadget; CM: Display.ControlMsg;
	viewerSystem, adaptive: BOOLEAN;
BEGIN
	IF Oberon.Pointer.on THEN (* placement hint *)
		v := Oberon.MarkedViewer();
		IF (v IS DocViewer) & ~(HasMenu(v(DocViewer))) THEN (* in the desktop *)
			V := v(DocViewer);
			viewerSystem := FALSE
		ELSE (* in viewer system *)
			viewerSystem := TRUE
		END
	ELSE (* no placement hint *)
		IF Oberon.Par.vwr = NIL THEN Oberon.Par.vwr := Viewers.This(0, 0) END;
		IF (Oberon.Par.vwr IS DocViewer) & ~(HasMenu(Oberon.Par.vwr(DocViewer))) THEN (* in the desktop *)
			V := Oberon.Par.vwr(DocViewer);
			viewerSystem := FALSE
		ELSE
			viewerSystem := TRUE
		END
	END;
	(* post: ~viewerSystem & (V # NIL) *)
	
	IF ~viewerSystem THEN (* in the desktop *)
		NewDocGadget; DF := Objects.NewObj(DocGadget);
		menu := CreateMenu(D, TRUE, FALSE);
		
		IF (D.lib # NIL) & (D.lib.name # "") THEN (* uh-uh, public object *)
			HALT(99)
		END;
		(* private *)
		Init(DF, menu(Gadgets.Frame), D, TRUE);
		open := DF;
		
		CM.id := Display.restore; CM.F := NIL; CM.x := 0; CM.y := 0; CM.dlink := NIL; CM.res := -1; open.handle(open, CM);
		
		C.id := Display.drop; C.obj := open;
		AllocateDocGadget(V, open.W, open.H, C.F, C.u, C.v);  C.x := 0;  C.y := 0;
		IF C.F # NIL THEN Display.Broadcast(C); viewerSystem := C.res < 0 ELSE viewerSystem := TRUE END
	END;
	IF viewerSystem THEN (* in the viewer system, or desktop integration failed *)
		IF D.W <= Display.Width DIV 8 * 3 THEN Oberon.AllocateSystemViewer(Oberon.Par.vwr.X, X, Y)
		ELSE Oberon.AllocateUserViewer(Oberon.Par.vwr.X, X, Y)
		END;
		
		A.id := Objects.get; A.name := "Adaptive"; A.class := Objects.Inval; A.b := FALSE; A.res := -1; D.handle(D, A);
		adaptive := (A.res >= 0) & (A.class = Objects.Bool) & A.b;

		IF (D.lib # NIL) & (D.lib.name # "") THEN (* uh-uh, public object *)
			HALT(99)
		END;
		
		IF ~adaptive THEN
			open := Views.ViewOf(D); open.W := D.W; open.H := D.H;
			(*Attributes.SetBool(open, "Locked", TRUE)*)
		ELSE open := D
		END;
		menu := CreateMenu(D, FALSE, X >= Display.Width DIV 8 * 5);
		V := NewDocViewer(menu, open, menu.H,  X, Y)
	END
END ShowDoc;

(** Replace the document enclosing the current context with the document D. *)
PROCEDURE ReplaceCurrentDoc*(D: Documents.Document);
VAR V: DocViewer; obj: Objects.Object; A: Display.ModifyMsg; menu, open: Display.Frame;
	x, y, w, h: INTEGER; AM: Objects.AttrMsg; addview: BOOLEAN;
BEGIN
	obj := Gadgets.context;
	WHILE (obj # NIL) & ~(obj IS DocGadget) & ~(obj IS DocViewer) DO obj := obj.dlink END;
	IF obj # NIL THEN
		IF obj IS DocGadget THEN
			WITH obj: DocGadget DO
				x := obj.X; y := obj.Y; w := obj.W; h := obj.H;
				menu := CreateMenu(D, TRUE, FALSE);
				Init(obj, menu(Gadgets.Frame), D, TRUE);
				A.id := Display.extend; A.mode := Display.display; A.F := obj;
				A.X := x; A.Y := y + h - obj.H; A.W := obj.W; A.H := obj.H;
				A.dX := A.X - x; A.dY := A.Y - y; A.dW := A.W - w; A.dH := A.H - h;
				Display.Broadcast(A)
			END
		ELSE
			V := obj(DocViewer);
			IF HasMenu(V) THEN menu := CreateMenu(D, FALSE, V.X >= Display.Width DIV 8 * 5)
			ELSE menu := NewDummy()
			END;
			AM.id := Objects.get; AM.name := "Adaptive"; AM.class := Objects.Inval; AM.b := FALSE; AM.res := -1; D.handle(D, AM);
			addview := (AM.res >= 0) & (AM.class = Objects.Bool) & ~AM.b;
			IF addview THEN
				open := Views.ViewOf(D);
				open.W := D.W; open.H := D.H
			ELSE open := D
			END;
			V.dsc := menu; V.dsc.next := open; V.menuH := menu.H; Restore(V)
		END
	END
END ReplaceCurrentDoc;

PROCEDURE ParentHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR obj: Objects.Object;
BEGIN
	IF (M IS ParentMsg) & (M(Display.FrameMsg).F = F) THEN
		WITH M: ParentMsg DO
			obj := M.dlink;
			WHILE (obj # NIL) & ~(obj IS DocViewer) & ~(obj IS DocGadget) DO obj := obj.dlink END;
			M.parent := obj; M.res := 0
		END
	END
END ParentHandler;

(** Close the document D. *)
PROCEDURE CloseThisDoc*(D: Documents.Document);
VAR handle: Objects.Handler; V: DocViewer; P: ParentMsg; R: Display.ControlMsg;
BEGIN
	handle := D.handle; D.handle := ParentHandler;
	P.F := D; P.parent := NIL; Display.Broadcast(P);
	D.handle := handle;
	IF P.parent # NIL THEN
		IF P.parent IS DocViewer THEN
			V := P.parent(DocViewer);
			IF ~(V.dsc IS Dummy) THEN Viewers.Close(V) END	(* do not close dekstops *)
		ELSE R.id := Display.remove; R.F := P.parent(Display.Frame); Display.Broadcast(R)
		END
	END
END CloseThisDoc;

PROCEDURE Option(VAR S: Attributes.Scanner; VAR s: ARRAY OF CHAR; scan: BOOLEAN);
VAR name: ARRAY 64 OF CHAR;
BEGIN
	s[0]  := 0X;
	IF scan THEN Attributes.Scan(S) END;
	IF (S.class = Attributes.Char) & (S.c = "(") THEN
		Attributes.Scan(S);
		IF S.class = Attributes.Name THEN
			COPY(S.s, name);
			Attributes.Scan(S);
			IF (S.class = Attributes.Char) & (S.c = ")") THEN COPY(name, s);
			END
		END
	END
END Option;

PROCEDURE LoadDoc(VAR name: ARRAY OF CHAR): Documents.Document;
VAR S: Attributes.Scanner; type, alias: ARRAY 64 OF CHAR; d: Documents.Document;
BEGIN
	name[0] := 0X;
	d := NIL;
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF (S.class = Attributes.Char) & (S.c = "(") THEN
		Option(S, type, FALSE);
		Gadgets.GetAlias(type, alias); IF alias # "" THEN COPY(alias, type) END;
		IF type # "" THEN
			Gadgets.Execute(type, Gadgets.executorObj, Gadgets.context, NIL, NIL);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Documents.Document) THEN
				d := Objects.NewObj(Documents.Document); d.name[0] := 0X; d.Load(d);
				COPY(d.name, name);
			END
		END
	ELSIF (S.class = Attributes.Name) OR (S.class = Attributes.String) THEN
		COPY(S.s, name);
		Option(S, type, TRUE);
		Gadgets.GetAlias(type, alias); IF alias # "" THEN COPY(alias, type) END;
		IF type # "" THEN
			Gadgets.Execute(type, Gadgets.executorObj, Gadgets.context, NIL, NIL);
			IF (Objects.NewObj # NIL) & (Objects.NewObj IS Documents.Document) THEN
				d := Objects.NewObj(Documents.Document); COPY(name, d.name); d.Load(d)
			END
		ELSE
			d := Documents.Open(name);
			IF (d = NIL) OR (d.dsc = NIL) THEN
				Texts.WriteString(W, Documents.errMsg);
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END;
	IF (d # NIL) & (d.dsc # NIL) THEN RETURN d ELSE RETURN NIL END
END LoadDoc;

(** Used in the forms:
	Desktops.OpenDoc <documentname>		(* open an existing document *)
	Desktops.OpenDoc (<document-generator>)		(* create a new document *)
	Desktops.OpenDoc <document-name>(<document-generator>)		(* cast existing document to new type *)

The document is loaded, and opened in the desktop or viewer system depending on the context and the marker.
*)
PROCEDURE OpenDoc*;
VAR name: ARRAY 128 OF CHAR; d: Documents.Document;
BEGIN
	d := LoadDoc(name);	
	IF (d # NIL) THEN ShowDoc(d)
	END;
	Objects.NewObj := NIL;
END OpenDoc;

(** Same usage as Desktops.OpenDoc. Document is inserted without menubar at the caret. *)
PROCEDURE InsertDoc*;
VAR name: ARRAY 128 OF CHAR; d: Documents.Document;
BEGIN
	d := LoadDoc(name);	
	IF (d # NIL) THEN Gadgets.Integrate(d)
	END;
	Objects.NewObj := NIL;
END InsertDoc;

(** Same usage as Desktops.OpenDoc. Current document is exchanged with the new document. *)
PROCEDURE ReplaceDoc*;
VAR name: ARRAY 128 OF CHAR; d: Documents.Document;
BEGIN
	d := LoadDoc(name);	
	IF (d # NIL) THEN ReplaceCurrentDoc(d)
	END;
	Objects.NewObj := NIL;
END ReplaceDoc;

(** Used in the forms:
	Desktops.StoreDoc		(* in menubar, or inside of a document *)
	Desktops.StoreDoc *	(* for a marked document *)
Stores a document under its given name.
 *)
PROCEDURE StoreDoc*;
VAR V: DocViewer; doc: Documents.Document; S: Attributes.Scanner; M: Display.SelectMsg; obj: Objects.Object;

	PROCEDURE StoreDoc(doc: Documents.Document);
	BEGIN
		IF doc # NIL THEN
			SyncPlate(doc);
			doc.Store(doc)
		ELSE
			Texts.WriteString(W, "[Document not found]");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
	END StoreDoc;
	
BEGIN
	doc := NIL;
	IF (Oberon.Par.frame = Oberon.Par.vwr.dsc) & (Oberon.Par.vwr IS DocViewer) THEN (* in menu of DocViewer *)
		V := Oberon.Par.vwr(DocViewer);
		doc := ViewerDoc(V);
		StoreDoc(doc)
	ELSE
		Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(S);
		IF (S.class = Attributes.Char) & (S.c = "*") THEN (* marked document *)
			doc := Documents.MarkedDoc();
			StoreDoc(doc);
		ELSIF (S.class = Attributes.Char) & (S.c = "@") THEN (* Objects selection *)
			M.id := Display.get; M.F := NIL; M.sel := NIL; M.obj := NIL; M.time := 0; Display.Broadcast(M);
			IF M.time > 0 THEN
				obj := M.obj;
				WHILE obj # NIL DO
					IF obj IS Documents.Document THEN StoreDoc(obj(Documents.Document)) END;
					obj := obj.slink;
				END
			ELSE Texts.WriteString(W, "[No selection]"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
			END
		ELSE (* current doc *)
			obj := Gadgets.context;
			WHILE (obj # NIL) & ~(obj IS Documents.Document) & ~(obj IS DocGadget) DO obj := obj.dlink END;
			IF obj # NIL THEN
				IF obj IS Documents.Document THEN StoreDoc(obj(Documents.Document))
				ELSE
					doc := DocGadgetDoc(obj(DocGadget));
					StoreDoc(doc)
				END
			ELSE Texts.WriteString(W, "[Document not found]"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END
END StoreDoc;

(** Closes the current document. Works both in the viewer and desktop systems. *)
PROCEDURE CloseDoc*;
VAR obj, obj0: Objects.Object; R: Display.ControlMsg;
BEGIN
	IF (Oberon.Par.frame = Oberon.Par.vwr.dsc) & (Oberon.Par.vwr IS DocViewer) THEN (* in menu of DocViewer *)
		recall := Oberon.Par.vwr;
		Viewers.Close(Oberon.Par.vwr(DocViewer))
	ELSE
		obj := Gadgets.context;
		WHILE (obj # NIL) & ~(obj IS Documents.Document) & ~(obj IS DocGadget) DO obj := obj.dlink END;
		IF (obj # NIL) THEN
			obj0 := obj;
			WHILE (obj0 # NIL) & ~((obj0 IS DocViewer)  & HasMenu(obj0(DocViewer))) & ~(obj0 IS DocGadget) DO
				obj0 := obj0.dlink
			END;
			IF obj0 # NIL THEN obj := obj0 END;
		END;
		IF obj # NIL THEN
			IF obj IS DocViewer THEN recall := obj(Display.Frame); Viewers.Close(obj(DocViewer))
			ELSE R.id := Display.remove; R.F := obj(Display.Frame); recall := R.F; Display.Broadcast(R)
			END
		ELSE Texts.WriteString(W, "[Document not found]"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
		END
	END
END CloseDoc;

(** Recalls last closed document. *)
PROCEDURE Recall*;
VAR V: Viewers.Viewer; M: Display.ControlMsg; doc: Documents.Document;
BEGIN
	IF recall # NIL THEN
		IF recall IS DocViewer THEN
			doc := ViewerDoc(recall(DocViewer));
			IF doc # NIL THEN ShowDoc(doc) END;
		ELSIF recall IS DocGadget THEN
			doc := DocGadgetDoc(recall(DocGadget));
			IF doc # NIL THEN ShowDoc(doc) END;
		END
	ELSE
		Viewers.Recall(V);
		IF (V # NIL) & (V.state = 0) THEN 
			Viewers.Open(V, V.X, V.Y + V.H); M.F := NIL; M.id := Display.restore; V.handle(V, M)
		END
	END;
END Recall;

(** Used in the form:
	Desktops.PrintDoc <printer-name> [ "\" options ] <list-of files> ~
	Desktops.PrintDoc <printer-name> [ "\" options ] *	(* Marked document *)
Prints a document.
*)
PROCEDURE PrintDoc*;
VAR S: Attributes.Scanner; M: Display.SelectMsg; obj: Objects.Object;
	D: Documents.Document; printer, options: ARRAY 64+LEN(D.name) OF CHAR;

	PROCEDURE PrinterErr;
	VAR err: ARRAY 32 OF CHAR;
	BEGIN
		IF Printer.res # 0 THEN
			IF Printer.res = 1 THEN err := " no such printer"
			ELSIF Printer.res = 2 THEN err := " no link"
			ELSIF Printer.res = 3 THEN err := " printer not ready"
			ELSIF Printer.res = 4 THEN err := " no permission"
			ELSE err := " unknown error"
			END;
			Texts.WriteString(W, err); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);	
		END
	END PrinterErr;

	PROCEDURE printDoc(doc: Documents.Document);
	VAR P: Display.DisplayMsg;
	BEGIN
		IF doc # NIL THEN
			Texts.WriteString(W, doc.name);
			P.device := Display.printer; P.id := Display.contents; P.F := NIL; P.x := 0; P.y := 0; P.dlink := NIL;
			doc.handle(doc, P);
			IF Printer.res # 0 THEN PrinterErr
			ELSE Texts.WriteString(W, " Ok")
			END
		ELSE Texts.WriteString(W, "[Document not found]")
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END printDoc;

	PROCEDURE PrintSelectedDocViewers;
	BEGIN
		M.id := Display.get; M.F := NIL; M.sel := NIL; M.obj := NIL; M.time := 0; Display.Broadcast(M);
		IF M.time > 0 THEN
			obj := M.obj;
			WHILE obj # NIL DO
				IF obj IS Documents.Document THEN
					printDoc(obj(Documents.Document));
				END;
				obj := obj.slink;
			END
		ELSE Texts.WriteString(W, " [no selection]"); Texts.Append(Oberon.Log, W.buf)
		END
	END PrintSelectedDocViewers;

	PROCEDURE OpenPrinter(name, options: ARRAY OF CHAR);
		VAR S: Texts.Scanner;
	BEGIN
		IF name = "Default" THEN
			Oberon.OpenScanner(S, "Printer.DefaultName");
			IF ~(S.class IN {Texts.Name, Texts.String}) THEN COPY(name, S.s) END
		ELSE
			COPY(name, S.s)
		END;
		Strings.AppendCh(options, Oberon.OptionChar);
		Strings.Append(options, D.name);
		Texts.WriteString(W, S.s); Texts.Write(W, " "); Texts.Append(Oberon.Log, W.buf);
		Printer.Open(S.s, options)
	END OpenPrinter;
	
BEGIN
	Texts.WriteString(W, "Desktops.PrintDoc "); Texts.Append(Oberon.Log, W.buf);
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class IN {Attributes.Name, Attributes.String} THEN (* printer name *)
		COPY(S.s, printer); Attributes.Scan(S);
		IF (S.class = Attributes.Char) & (S.c = Oberon.OptionChar) THEN
			Attributes.Scan(S);
			IF (S.class # Texts.Name) & (S.class # Texts.String) THEN options := ""
			ELSE COPY(S.s, options)
			END;
			Attributes.Scan(S)
		ELSE options := ""
		END;
		IF (S.class = Attributes.Char) & (S.c = "*") THEN
			D := Documents.MarkedDoc();
			IF D # NIL THEN
				OpenPrinter(printer, options);
				IF Printer.res = 0 THEN
					printDoc(D); Printer.Close
				END;
				IF Printer.res # 0 THEN PrinterErr END
			END
		ELSIF (S.class = Attributes.Char) & (S.c = "@") THEN (* Selection *)
			OpenPrinter(printer, options);
			IF Printer.res = 0 THEN
				PrintSelectedDocViewers; Printer.Close
			END;
			IF Printer.res # 0 THEN PrinterErr END
		ELSIF S.class = Attributes.Name THEN
			Printer.res := 0;
			WHILE (S.class = Attributes.Name) & (Printer.res = 0) DO
				D := Documents.Open(S.s);
				IF (D # NIL) & (D.dsc # NIL) THEN
					OpenPrinter(printer, options);
					IF Printer.res = 0 THEN
						printDoc(D); Printer.Close
					END;
					IF Printer.res # 0 THEN PrinterErr END
				ELSE
					Texts.WriteString(W, Documents.errMsg);
					Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
				END;
				Attributes.Scan(S)
			END
		ELSE
			D := CurDoc(Gadgets.context);
			IF D # NIL THEN
				OpenPrinter(printer, options);
				IF Printer.res = 0 THEN
					printDoc(D); Printer.Close
				END;
				IF Printer.res # 0 THEN PrinterErr END
			END
		END;
	ELSE Texts.WriteString(W, " unknown printer"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END
END PrintDoc;

(** Desktops.MenuCmd docgadget cmd *)
PROCEDURE MenuCmd*;
	VAR
		S: Attributes.Scanner;
		obj: Objects.Object;
BEGIN
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
	Attributes.Scan(S);
	IF S.class IN {Attributes.Name, Attributes.String} THEN
		obj := Gadgets.FindObj(Gadgets.context, S.s);
		IF (obj # NIL) & (obj IS Documents.Document) THEN
			Attributes.Scan(S);
			IF S.class IN {Attributes.Name, Attributes.String} THEN
				Gadgets.Execute(S.s, Gadgets.executorObj, obj, NIL, NIL)
			END
		END
	END
END MenuCmd;

BEGIN
	Texts.OpenWriter(W);
	menuH := 20; menuC := 13;
	IF Display.Width <= 800 THEN
		menuButtonW := 36;  namePlateW := 75
	ELSE
		menuButtonW := 39;  namePlateW := 110
	END;
	recDocWidth := namePlateW + 3*menuButtonW
END Desktops.

(** Remarks:

1. The gadgets defined in the desktop module act as wrappers for documents. They also manage the menubar for the document. This allows a degree of compatibility between the older viewer system and the the newer desktop system. The new Viewers manage the documents in the viewer system while the DocGadgets does it in the desktop. In fact, the desktop itself is also managed in one of the new Viewers with an empty menubar.

2. Viewer structure
Each Viewer (both DocViewer of DocGadget) have a menubar and a main frame. The main frame is typically a document or a camera-view on a document.
*)
