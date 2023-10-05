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

MODULE LayoutPanels0;	(** portable *)
	
	IMPORT
		Objects, Gadgets, Display, Display3, Effects, Texts, Oberon;
	
	CONST					
		(* format *)
		left = 0; right = 1; bottom = 2; top = 3;	(* for elements *)
		meleft = 12; meright = 13; mebottom = 14; metop = 15;	(* default *)
		samewidth = 4; sameheight = 5;
		hstatic = 6; vstatic = 7;
		innerleft = 8; innerright = 9; innerbottom = 10; innertop = 11;	(* for tables *)
				
	TYPE
		Element* = POINTER TO ElementDesc;
		ElementDesc* = RECORD (Gadgets.FrameDesc)
			format*: SET;
			hfactor*, vfactor*, row*, col*, minx*, miny*, minw*, minh*: INTEGER;
			size*: PROCEDURE (e: Element);
			make*: PROCEDURE (e: Element; x, y, w, h: INTEGER)
		END;
		
		Container* = POINTER TO ContainerDesc;
		ContainerDesc* = RECORD (ElementDesc)
			hborder*, vborder*: INTEGER
		END;
		
		IntArray = POINTER TO ARRAY OF INTEGER;
		Table* = POINTER TO TableDesc;
		TableDesc* = RECORD (ContainerDesc)
			cols*, rows*, hdist*, vdist*, hfill*, vfill*: INTEGER;
			gmaxw*, gmaxh*, hexpand*, vexpand*, hoffset*, voffset*: IntArray
		END;
		
		PanelMsg* = RECORD (Display.FrameMsg) sender, panel*: Gadgets.Frame END;
		ContainerMsg* = RECORD (Display.FrameMsg) sender, container*: Gadgets.Frame END;
		CalcMsg* = RECORD (Objects.ObjMsg) END;
		ConsumeMsg* = RECORD (Display.ConsumeMsg) e*: Element END;		
			
	VAR
		head: Element;	(* dummy *)
		W: Texts.Writer;


	PROCEDURE ^ NewElement* (): Element;
	PROCEDURE ^ NewContainer* (): Container;
	PROCEDURE ^ NewTable* (): Table;
	PROCEDURE ^ EmptyTable* (rows, cols: INTEGER): Table;

	(* --- *)
	
	(* send Display.DisplayMsg with area (u, v, w, h) to receiver *)
	PROCEDURE DisplayArea (receiver: Display.Frame; u, v, w, h: INTEGER);
		VAR M: Display.DisplayMsg;
	BEGIN
		M.F := receiver; (* x, y, res set by Broadcast *)
		M.device := Display.screen; M.id := Display.area;
		M.u := u; M.v := v; M.w := w; M.h := h;
		Display.Broadcast(M)
	END DisplayArea;
	
	(* see LayoutPanels.Mod *)
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
	
	(* similar to ToChildren() in LayoutPanels.Mod *)
	PROCEDURE SimpleToElements (F: Container; VAR M: Display.FrameMsg);
		VAR Mdlink, Fdlink: Objects.Object; f: Display.Frame;
	BEGIN
		Fdlink := F.dlink; Mdlink := M.dlink; 
		F.dlink := M.dlink; M.dlink := F;
		f := F.dsc;
		WHILE f # NIL DO f.handle(f, M); f := f.next END;
		F.dlink := Fdlink; M.dlink := Mdlink
	END SimpleToElements;
	
	(* --- *)

	(** get the container of Element sender, will return NIL if sender is top Element of panel *)
	PROCEDURE GetContainer* (sender: Element): Container;
		VAR M: ContainerMsg;
	BEGIN
		M.dlink := NIL; M.F := NIL;
		M.sender := sender; M.container := NIL; Display.Broadcast(M);
		IF (M.container # NIL) & (M.container IS Container) THEN RETURN M.container(Container) ELSE RETURN NIL END
	END GetContainer;
	
	(** returns the panel which holds this element *)
	PROCEDURE GetPanel* (sender: Element): Gadgets.Frame;
		VAR M: PanelMsg;
	BEGIN
		M.dlink := NIL; M.F := NIL;
		M.sender := sender; M.panel := NIL; Display.Broadcast(M);
		RETURN M.panel
	END GetPanel;

	PROCEDURE DummyHandler (obj: Objects.Object; VAR M: Objects.ObjMsg);
	BEGIN
	END DummyHandler;
	
	PROCEDURE Drop* (obj: Objects.Object; dest: Display.Frame; u, v: INTEGER);
		VAR C: ConsumeMsg; C0: Display.ConsumeMsg; dummy: Objects.Object;
	BEGIN
		IF obj # NIL THEN
			IF obj IS Element THEN
				C.id := Display.drop; C.F := dest; C.u := u; C.v := v;
				IF obj(Element).obj = NIL THEN NEW(dummy); dummy.handle := DummyHandler;
					C.obj := dummy
				ELSE C.obj := obj(Element).obj
				END;
				C.e := obj(Element);
				Display.Broadcast(C)
			ELSE
				C0.id := Display.drop; C0.F := dest; C0.u := u; C0.v := v; C0.obj := obj;
				Display.Broadcast(C0)
			END;
		END
	END Drop;
	
	(** similar to Gadgets.Integrate *)
	PROCEDURE Integrate* (obj: Objects.Object);
		VAR C: ConsumeMsg; dummy: Objects.Object;
	BEGIN
		IF obj # NIL THEN 
			IF obj IS Element THEN
			 	C.id := Display.integrate;  C.F := NIL;
				IF obj(Element).obj = NIL THEN NEW(dummy); dummy.handle := DummyHandler;
					C.obj := dummy
				ELSE C.obj := obj(Element).obj
				END;
				C.e := obj(Element);
				Display.Broadcast(C)
			ELSE
				Gadgets.Integrate(obj)
			END
		END
	END Integrate;

	(* --- *)
	
	PROCEDURE CalcPanelOf (e: Element);
	VAR p: Gadgets.Frame; M: CalcMsg;
	BEGIN p := GetPanel(e); IF p # NIL THEN p.handle(p, M) END	(* should be always the case *)
	END CalcPanelOf;

	(* --- *)
	
	(** returns the element which has obj as model, e is the tree to search in, obj # NIL *)
	PROCEDURE GetElementOf* (obj: Objects.Object; e: Element): Element;
		VAR f: Display.Frame;
	BEGIN
		IF e.obj = obj THEN RETURN e
		ELSIF e IS Container THEN f := e.dsc; e := NIL;
			WHILE (f # NIL) & (e = NIL) DO e := GetElementOf(obj, f(Element)); f := f.next END;
			RETURN e
		ELSE RETURN NIL
		END
	END GetElementOf;
	
	(* --- Edit procedures --- *)

	(* Note: M.id is ignored by Elements (always deep), but not by Leaf-Gadgets *)
	PROCEDURE CopyElements* (f: Display.Frame): Display.Frame;
		VAR M: Objects.CopyMsg;
	BEGIN M.id := Objects.deep; M.obj := NIL; M.dlink := NIL; Objects.Stamp(M); f.handle(f, M); RETURN M.obj(Display.Frame)
	END CopyElements;

	(* call with list := LinkGadgets(e, list) *)
	(* link not VAR paramter because NIL can't be VAR parameter *)
	PROCEDURE LinkGadgets* (e: Element; link: Display.Frame): Display.Frame;
		VAR f: Display.Frame;
	BEGIN
		IF e IS Container THEN f := e.dsc;
			WHILE f # NIL DO link := LinkGadgets(f(Element), link); f := f.next END
		ELSE (* leaf element *)
			IF (e.obj # NIL) & (e.obj IS Display.Frame) THEN e.obj.slink := link; link := e.obj(Display.Frame) END
		END;
		RETURN link
	END LinkGadgets;
	
	(* removes objlist from Panel p *)
	PROCEDURE KillFrames (p: Objects.Object; objlist: Display.Frame);
		VAR M: Display.ControlMsg;
	BEGIN IF objlist # NIL THEN M.F := objlist; (* x, y undef *) M.res := -1; M.id := Display.remove; p.handle(p, M) END
	END KillFrames;

	(* renumbers Elements of Table t *)
	PROCEDURE SetRowCol (t: Table);
		VAR i, j: INTEGER; f: Display.Frame;
	BEGIN f := t.dsc;
		FOR i := 0 TO t.rows - 1 DO
			FOR j := 0 TO t.cols - 1 DO
				f(Element).row := i; f(Element).col := j; f := f.next
			END
		END
	END SetRowCol;

	(** inserts e after e0, e0 # NIL, e # NIL *)
	PROCEDURE InsertElementAfter* (e0, e: Element);
	BEGIN e.next := e0.next; e0.next := e
	END InsertElementAfter;
	
	(** inserts a row at position y in Table tab *)
	PROCEDURE InsertRow* (tab: Table; y: INTEGER; recalc: BOOLEAN);
		VAR i: INTEGER; f: Display.Frame;
	BEGIN
		head.next := tab.dsc; (* dummy head *)
		f := head;
		IF y < 0 THEN y := 0 ELSIF y > tab.rows THEN y := tab.rows END;
		
		(* insert new elements *)
		FOR i := 0 TO y*tab.cols - 1 DO f := f.next END;	(* find pos *)
		FOR i := 0 TO tab.cols - 1 DO
			InsertElementAfter(f(Element), NewElement());
			f.next(Element).hfactor := 1; f.next(Element).vfactor := 1
		END;
		tab.dsc := head.next;
		INC(tab.rows); 
		SetRowCol(tab); (* correct row, col address *)
		NEW(tab.gmaxh, tab.rows); NEW(tab.vexpand, tab.rows); NEW(tab.voffset, tab.rows + 1);
		IF recalc THEN CalcPanelOf(tab) END
	END InsertRow;

	(** inserts col at position x in Table tab *)
	PROCEDURE InsertCol* (tab: Table; x: INTEGER; recalc: BOOLEAN);
	VAR i, j: INTEGER; f: Display.Frame;
	BEGIN
		head.next := tab.dsc; (* dummy head *)
		f := head;
		IF x < 0 THEN x := 0 ELSIF x > tab.cols THEN x := tab.cols END;
		FOR i := 0 TO tab.rows - 1 DO
			FOR j := 0 TO x - 1 DO f := f.next END;
			InsertElementAfter(f(Element), NewElement()); f := f.next;
			WITH f: Element DO f.hfactor := 1; f.vfactor := 1 END;
			FOR j := x TO tab.cols - 1 DO f := f.next END
		END;
		tab.dsc := head.next;
		INC(tab.cols);
		SetRowCol(tab);
		NEW(tab.gmaxw, tab.cols); NEW(tab.hexpand, tab.cols); NEW(tab.hoffset, tab.cols + 1);
		IF recalc THEN CalcPanelOf(tab) END
	END InsertCol;

	(** removes row at position y in Table tab *)
	PROCEDURE RemoveRow* (tab: Table; y: INTEGER; recalc: BOOLEAN);
		VAR i: INTEGER; f, objlist: Display.Frame; p: Objects.Object; CM: CalcMsg;
	BEGIN
		IF tab.rows > 1 THEN head.next := tab.dsc; f := head; (* dummy head *)
			objlist := NIL;
			FOR i := 0 TO y*tab.cols - 1 DO f := f.next END;	(* find pos *)
			FOR i := 0 TO tab.cols - 1 DO 
				objlist := LinkGadgets(f.next(Element), objlist);
				f.next := f.next.next
			END;
			tab.dsc := head.next;
			DEC(tab.rows);
			SetRowCol(tab);
			(* no reallocation in case of fewer rows! *)
			
			p := GetPanel(tab);
			IF p # NIL THEN
				KillFrames(p, objlist);
				IF recalc THEN p.handle(p, CM) END
			END
		END
	END RemoveRow;

	(** removes col at position x in Table tab *)
	PROCEDURE RemoveCol* (tab: Table; x: INTEGER; recalc: BOOLEAN);
		VAR i, j: INTEGER; f, objlist: Display.Frame; p: Objects.Object; CM: CalcMsg;
	BEGIN
		IF tab.cols > 1 THEN head.next := tab.dsc; f := head; (* dummy head *)
			objlist := NIL;
			FOR i := 0 TO tab.rows - 1 DO
				FOR j := 0 TO x - 1 DO f := f.next END;
				objlist := LinkGadgets(f.next(Element), objlist);
				f.next := f.next.next;
				FOR j := x + 1 TO tab.cols - 1 DO f := f.next END
			END;
			tab.dsc := head.next;
			DEC(tab.cols);
			SetRowCol(tab);
			(* no reallocation in case of fewer rows! *)
			
			p := GetPanel(tab);
			IF p # NIL THEN
				KillFrames(p, objlist);
				IF recalc THEN p.handle(p, CM) END
			END
		END
	END RemoveCol;
	
	(* --- *)
	
	(** links obj as model for Element e *)
	PROCEDURE InsertGadget* (e: Element; obj: Gadgets.Frame);
		VAR M: Objects.AttrMsg;
	BEGIN
		EXCL(obj(Gadgets.Frame).state, Gadgets.selected);
		e.obj := obj(Gadgets.Frame);
		
		M.id := Objects.get; M.name := "minw"; M.res := -1; obj.handle(obj, M);
		IF (M.res >= 0) & (M.class = Objects.Int) & (M.i >= 0) THEN e.minw := SHORT(M.i) ELSE e.minw := obj.W END;

		M.id := Objects.get; M.name := "minh"; M.res := -1; obj.handle(obj, M);
		IF (M.res >= 0) & (M.class = Objects.Int) & (M.i >= 0) THEN e.minh := SHORT(M.i) ELSE e.minh := obj.H END
	END InsertGadget;
	
	(** inserts Element e into Place Container c *)
	PROCEDURE InsertPlaceElement* (c: Container; e: Element);
	BEGIN head.next := c.dsc; InsertElementAfter(head, e); c.dsc := head.next
	END InsertPlaceElement;
		
	(** replaces e0 in c with e1. c, e0, e1 # NIL *)
	PROCEDURE ReplaceElement* (c: Container; e0, e1: Element; recalc: BOOLEAN);
		VAR f: Display.Frame;
	BEGIN
		head.next := c.dsc; f := head;
		WHILE (f.next # NIL) & (f.next # e0) DO f := f.next END;
		IF f.next # NIL THEN	(* found *)
			e1.next := e0.next; e0.next := NIL; f.next := e1; c.dsc := head.next;
			IF c IS Table THEN SetRowCol(c(Table)) END;
			IF recalc THEN CalcPanelOf(c) END
		END
	END ReplaceElement;
	
	(**
		container of e IS Table: replaces Element by a virtual Element
		container of e IS Place: removes Element from Container
		e # NIL
	*)
	PROCEDURE ClearElement* (e: Element; VAR objlist: Display.Frame): BOOLEAN;
		VAR c: Container; new: Element; f: Display.Frame;
	BEGIN c := GetContainer(e);
		IF c # NIL THEN
			IF c IS Table THEN
				new := NewElement();
				new.format := e.format; new.hfactor := e.hfactor; new.vfactor := e.vfactor; new.row := e.row; new.col := e.col;
				new.minx := e.minx; new.miny := e.miny; new.minw := e.minw; new.minh := e.minh;
				
				objlist := LinkGadgets(e, NIL);
				ReplaceElement(c, e, new, FALSE);
				RETURN TRUE
			ELSE (* c IS Container *)
				head.next := c.dsc; f := head;
				WHILE (f.next # NIL) & (f.next # e) DO f := f.next END;
				IF f.next # NIL THEN	(* found *)
					objlist := LinkGadgets(e, NIL);
					f.next := f.next.next; c.dsc := head.next
				END;
				RETURN TRUE
			END
		END;
		RETURN FALSE
	END ClearElement;

	(* --- *)
			
	(** get top most selection (if any) or leaf Element, following u, v
	border check if border IS TRUE
	*)
	PROCEDURE Select* (e: Element; u, v: INTEGER; border: BOOLEAN): Display.Frame;
		VAR f, e1: Display.Frame; c: Container;
	BEGIN
		IF ~Effects.Inside(u, v, e.X, e.Y, e.W, e.H) THEN RETURN NIL
		ELSIF border & Effects.InBorder(u, v, e.X, e.Y, e.W, e.H) THEN RETURN e
		ELSIF Gadgets.selected IN e.state THEN RETURN e
		ELSIF (e.obj # NIL) & (e.obj IS Display.Frame) THEN RETURN e.obj(Display.Frame)
		ELSIF e IS Container THEN
			c := e(Container); f := c.dsc; e1 := NIL;
			WHILE (f # NIL) & (e1 = NIL) DO e1 := Select(f(Element), u, v, border); f := f.next END;
			IF e1 # NIL THEN RETURN e1 ELSE RETURN e END
		ELSE RETURN e
		END
	END Select;

	(** returns closest Element in Table t for coordinates x, y *)
	PROCEDURE ClosestTableElement* (t: Table; x, y: INTEGER): Element;
		VAR f: Display.Frame; min: Element;
	BEGIN
		f := t.dsc; min := f(Element); (* table has at least one component *)
		WHILE f # NIL DO
			IF ABS(f.X + f.W DIV 2 - x) + ABS(f.Y + f.H DIV 2 - y) < ABS(min.X + min.W DIV 2 - x) + ABS(min.Y + min.H DIV 2 - y) THEN
				min := f(Element)
			END;
			f := f.next
		END;
		RETURN min
	END ClosestTableElement;

	(* --- Handlers --- *)
	
	PROCEDURE ElementHandler (obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR mask: Display3.Mask; changed: BOOLEAN; A: Objects.AttrMsg; new: Element;  x, y: INTEGER;
	BEGIN
		WITH obj: Element DO
			IF M IS PanelMsg THEN
				WITH M: PanelMsg DO
					IF M.sender = obj THEN
						M.panel := M.dlink(Gadgets.Frame); M.res := 0
					END
				END
			ELSIF M IS ContainerMsg THEN
				WITH M: ContainerMsg DO
					IF M.sender = obj THEN
						M.container := M.dlink(Gadgets.Frame); M.res := 0
					END
				END	
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF M.res >= 0 THEN RETURN END;
					x := M.x + obj.X; y := M.y + obj.Y;
					IF (M.F = NIL) OR (M.F = obj) THEN (* for this Element (or a broadcast) *)
						IF M IS Display.SelectMsg THEN
							WITH M: Display.SelectMsg DO
								Gadgets.MakeMask(obj, M.x + obj.X, M.y + obj.Y, M.dlink, mask);
								IF M.id = Display.set THEN
									IF (obj.obj # NIL) & (obj.obj IS Gadgets.Frame) THEN
										IF ~(Gadgets.selected IN obj.obj(Gadgets.Frame).state) THEN
											M.F := obj.obj(Display.Frame); obj.obj.handle(obj.obj, M);
											DisplayArea(M.dlink(Display.Frame), obj.X, obj.Y, obj.W, obj.H)
										ELSE
											M.F := obj.obj(Display.Frame); M.id := Display.reset; obj.obj.handle(obj.obj, M);
											INCL(obj.state, Gadgets.selected);
											DisplayArea(M.dlink(Display.Frame), obj.X, obj.Y, obj.W, obj.H)
										END
									ELSE
										INCL(obj.state, Gadgets.selected);
										DisplayArea(M.dlink(Display.Frame), obj.X, obj.Y, obj.W, obj.H)
									END
								ELSIF M.id = Display.reset THEN
									EXCL(obj.state, Gadgets.selected);
									Gadgets.MakeMask(obj, M.x + obj.X, M.y + obj.Y, M.dlink, mask);
									DisplayArea(M.dlink(Display.Frame), obj.X, obj.Y, obj.W, obj.H)
								END
							END
						ELSIF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN								
									Gadgets.MakeMask(obj, x, y, M.dlink, mask);
									IF (obj.obj # NIL) & (obj.obj IS Display.Frame) THEN
										M.F := obj.obj(Display.Frame); obj.obj.handle(obj.obj, M)
									ELSE
										Display3.Rect3D(mask, Display3.black, Display3.white, x, y, obj.W, obj.H, 1, Display.replace)
									END;
									IF Gadgets.selected IN obj.state THEN
										Display3.FillPattern(mask, Display3.red, Display3.selectpat, 0, 0, x, y, obj.W, obj.H, Display.replace)
									END
								ELSIF M.device = Display.printer THEN
									IF (obj.obj # NIL) & (obj.obj IS Display.Frame) THEN
										M.F := obj.obj(Display.Frame); obj.obj.handle(obj.obj, M)
									END
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							IF (obj.obj # NIL)  & ~(Gadgets.selected IN obj.state) THEN (* passing to gadget *)
								obj.obj.handle(obj.obj, M);
								(* DisplayArea(M.dlink(Display.Frame), obj.X, obj.Y, obj.W, obj.H) *)	(* not very nice *)
							END
						ELSE
						END
					ELSE (* --- child --- *)
						IF M.F = obj.obj THEN
							IF M IS Display.ModifyMsg THEN
								WITH M: Display.ModifyMsg DO
									IF obj.obj IS Display.Frame THEN obj.obj.handle(obj.obj, M) END
								END
							END
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					CASE M.id OF Objects.get:
						IF M.name = "Gen" THEN M.class := Objects.String; M.s := "LayoutPanels0.NewElement"; M.res := 0
						ELSIF M.name = "hfactor" THEN M.class := Objects.Int; M.i := obj.hfactor;  M.res := 0
						ELSIF M.name = "vfactor" THEN M.class := Objects.Int; M.i := obj.vfactor;  M.res := 0
						ELSIF M.name = "x" THEN M.class := Objects.Int; M.i := obj.minx; M.res := 0
						ELSIF M.name = "y" THEN M.class := Objects.Int; M.i := obj.miny; M.res := 0
						ELSIF M.name = "w" THEN M.class := Objects.Int; M.i := obj.minw; M.res := 0
						ELSIF M.name = "h" THEN M.class := Objects.Int; M.i := obj.minh; M.res := 0
						ELSIF M.name = "left" THEN M.class := Objects.Bool; M.b := meleft IN obj.format; M.res := 0
						ELSIF M.name = "right" THEN M.class := Objects.Bool; M.b := meright IN obj.format; M.res := 0
						ELSIF M.name = "bottom" THEN M.class := Objects.Bool; M.b := mebottom IN obj.format; M.res := 0
						ELSIF M.name = "top" THEN M.class := Objects.Bool; M.b := metop IN obj.format; M.res := 0
						ELSE Gadgets.framehandle(obj, M);
							IF M.res < 0 THEN M.class := Objects.String; M.s := ""; M.res := 0 END
						END
					| Objects.set:	changed := FALSE;
						IF (M.name = "x") & (M.class = Objects.Int) THEN changed := M.i # obj.minx; obj.minx := SHORT(M.i); M.res := 0
						ELSIF (M.name = "y") & (M.class = Objects.Int) THEN changed := M.i # obj.miny; obj.miny := SHORT(M.i); M.res := 0
						ELSIF (M.name = "w") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.minw; obj.minw := SHORT(M.i); M.res := 0;
							IF (obj.obj # NIL) & (obj.obj IS Display.Frame) THEN	(* set gadget attribute *)
								A.id := Objects.set; A.name := "minw"; A.res := -1; A.class := Objects.Int; A.i := M.i;
								obj.obj.handle(obj.obj, A)
							END
						ELSIF (M.name = "h") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.minh; obj.minh := SHORT(M.i); M.res := 0;
							IF (obj.obj # NIL) & (obj.obj IS Display.Frame) THEN	(* set gadget attribute *)
								A.id := Objects.set; A.name := "minh"; A.res := -1; A.class := Objects.Int; A.i := M.i;
								obj.obj.handle(obj.obj, A)
							END
						ELSIF (M.name = "hfactor") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.hfactor; obj.hfactor := SHORT(M.i); M.res := 0
						ELSIF (M.name = "vfactor") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.vfactor; obj.vfactor := SHORT(M.i); M.res := 0
						ELSIF (M.name = "left") & (M.class = Objects.Bool) THEN changed := M.b # (meleft IN obj.format); IF changed THEN obj.format := obj.format/{meleft} END; M.res := 0
						ELSIF (M.name = "right") & (M.class = Objects.Bool) THEN changed := M.b # (meright IN obj.format); IF changed THEN obj.format := obj.format/{meright} END; M.res := 0
						ELSIF (M.name = "bottom") & (M.class = Objects.Bool) THEN changed := M.b # (mebottom IN obj.format); IF changed THEN obj.format := obj.format/{mebottom} END; M.res := 0
						ELSIF (M.name = "top") & (M.class = Objects.Bool) THEN changed := M.b # (metop IN obj.format); IF changed THEN obj.format := obj.format/{metop} END; M.res := 0
						ELSE  Gadgets.framehandle(obj, M); IF M.res >= 0 THEN CalcPanelOf(obj) END
						END;
						IF changed THEN CalcPanelOf(obj) END
					| Objects.enum:	Gadgets.framehandle(obj, M);
						M.Enum("x"); M.Enum("y"); M.Enum("w"); M.Enum("h");
						M.Enum("hfactor"); M.Enum("vfactor");
						M.Enum("left"); M.Enum("right"); M.Enum("bottom"); M.Enum("top")
					ELSE
					END
				END
			ELSIF M IS Objects.FileMsg THEN
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					new := NewElement();
					new.format := obj.format; new.hfactor := obj.hfactor; new.vfactor := obj.vfactor;
					new.row := obj.row; new.col := obj.col;
					new.minx := obj.minx; new.miny := obj.miny; new.minw := obj.minw; new.minh := obj.minh;
					
					IF obj.obj # NIL THEN obj.obj.handle(obj.obj, M);
						IF (M.obj # NIL) & (M.obj IS Display.Frame) THEN new.obj := M.obj(Display.Frame) ELSE new.obj := NIL END
					ELSE new.obj := NIL
					END;
					M.obj := new
				END
			ELSIF M IS Objects.BindMsg THEN
			ELSIF M IS Objects.LinkMsg THEN Gadgets.framehandle(obj, M)
			ELSIF M IS Objects.FindMsg THEN
			ELSIF M IS Display.LocateMsg THEN
			ELSIF M IS Display.ConsumeMsg THEN
			ELSE Gadgets.framehandle(obj, M)
			END
		END
	END ElementHandler;
	
	PROCEDURE ContainerHandler (obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR f, fn, head: Display.Frame; changed: BOOLEAN; mask: Display3.Mask; D: Display.DisplayMsg; new: Container; x, y: INTEGER;
	BEGIN
		WITH obj: Container DO
			IF M IS PanelMsg THEN
				WITH M: PanelMsg DO
					ElementHandler(obj, M);	(* check if obj is sender of message *)
					IF M.panel = NIL THEN f := obj.dsc;
						WHILE (f # NIL) & (M.res < 0) DO f.handle(f, M); f := f.next END
					END
				END
			ELSIF M IS ContainerMsg THEN
				WITH M: ContainerMsg DO
					ElementHandler(obj, M);
					IF M.container = NIL THEN SimpleToElements(obj, M) END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					CASE M.id OF Objects.get:
						IF M.name = "Gen" THEN M.class := Objects.String; M.s := "LayoutPanels0.NewContainer"; M.res := 0
						ELSIF M.name = "hborder" THEN M.class := Objects.Int; M.i := obj.hborder; M.res := 0
						ELSIF M.name = "vborder" THEN M.class := Objects.Int; M.i := obj.vborder; M.res := 0
						ELSE ElementHandler(obj, M)
						END
					| Objects.set:	changed := FALSE;
						IF (M.name = "hborder") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.hborder; obj.hborder := SHORT(M.i); M.res := 0
						ELSIF (M.name = "vborder") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.vborder; obj.vborder := SHORT(M.i); M.res := 0
						ELSE ElementHandler(obj, M)
						END;
						IF changed THEN CalcPanelOf(obj) END
					| Objects.enum:	ElementHandler(obj, M); M.Enum("hborder"); M.Enum("vborder")
					ELSE
					END
				END
			ELSIF M IS Objects.FileMsg THEN
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					new := NewContainer();
					new.format := obj.format; new.hfactor := obj.hfactor; new.vfactor := obj.vfactor;
					new.row := obj.row; new.col := obj.col;
					new.minx := obj.minx; new.miny := obj.miny; new.minw := obj.minw; new.minh := obj.minh;
					new.hborder := obj.hborder; new.vborder := obj.vborder;
					
					NEW(head);
					f := obj.dsc; head.next := NIL; fn := head;
					WHILE f # NIL DO
						f.handle(f, M); fn.next := M.obj(Element);
						fn := fn.next; f := f.next
					END;
					fn.next := NIL; new.dsc := head.next;
					M.obj := new
				END
			ELSIF M IS Objects.BindMsg THEN
			ELSIF M IS Objects.LinkMsg THEN	(* containers have no model *)
			ELSIF M IS Objects.FindMsg THEN
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF M.res >= 0 THEN RETURN END;
					x := M.x + obj.X; y := M.y + obj.Y;
					IF (M.F = NIL) OR (M.F = obj) THEN (* for this Element (or a broadcast) *)
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									Gadgets.MakeMask(obj, x, y, M.dlink, mask);
																		
									IF M.id = Display.area THEN f := obj.dsc;
										WHILE f # NIL DO
											IF Effects.Intersect(M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h, f.X, f.Y, f.W, f.H) THEN
												D.x := M.x; D.y := M.y; D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H;
												ClipAgainst(D.u, D.v, D.w, D.h, M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h);
												D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := M.dlink;
												D.device := Display.screen; D.id := Display.area; D.F := NIL; D.res := -1;
												f.handle(f, D)
											END;
											f := f.next
										END
									ELSE f := obj.dsc;
										WHILE f # NIL DO
											D.x := M.x; D.y := M.y; D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H;
											ClipAgainst(D.u, D.v, D.w, D.h, M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h);
											D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := M.dlink;
											D.device := Display.screen; D.id := Display.area; D.F := NIL; D.res := -1;											
											f.handle(f, D);
											f := f.next
										END
									END;
									
									IF (M.u = 0) OR (M.v = 1 - obj.H) OR (M.u + M.w = obj.W) OR (M.v + M.h - 1 = 0) THEN
										Display3.Rect (mask, Display3.green, Display.solid, x, y, obj.W, obj.H, 1, Display.replace);
									END;

									IF Gadgets.selected IN obj.state THEN
										Display3.FillPattern(mask, Display3.green, Display3.selectpat, 0, 0, x, y, obj.W, obj.H, Display.replace);
									END
								ELSIF M.device = Display.printer THEN	(* delegate to Elements *)
								END
							END
						ELSIF M IS Display.SelectMsg THEN ElementHandler(obj, M)
						ELSE Gadgets.framehandle(obj, M)
						END
					ELSE	(* for Container Element? *)
						IF M IS Display.ModifyMsg THEN f := obj.dsc;
							WHILE (f # NIL) & (M.res < 0) DO f.handle(f, M); f := f.next END
						END
					END
				END
			ELSE Gadgets.framehandle(obj, M)
			END
		END
	END ContainerHandler;

	PROCEDURE TableHandler (obj: Objects.Object; VAR M: Objects.ObjMsg);
		VAR f, fn, head: Display.Frame; i: INTEGER; changed: BOOLEAN; mask: Display3.Mask; D: Display.DisplayMsg; new: Table; x, y: INTEGER;
	BEGIN
		WITH obj: Table DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					CASE M.id OF Objects.get:
						IF       M.name = "Gen" THEN M.class := Objects.String; M.s := "LayoutPanels0.NewTable"; M.res := 0
						ELSIF M.name = "rows" THEN M.class := Objects.Int; M.i := obj.rows; M.res := 0
						ELSIF M.name = "cols" THEN M.class := Objects.Int; M.i := obj.cols; M.res := 0
						ELSIF M.name = "hdist" THEN M.class := Objects.Int; M.i := obj.hdist; M.res := 0
						ELSIF M.name = "vdist" THEN M.class := Objects.Int; M.i := obj.vdist; M.res := 0
						ELSIF M.name = "innerleft" THEN M.class := Objects.Bool; M.b := innerleft IN obj.format; M.res := 0
						ELSIF M.name = "innerright" THEN M.class := Objects.Bool; M.b := innerright IN obj.format; M.res := 0
						ELSIF M.name = "innerbottom" THEN M.class := Objects.Bool; M.b := innerbottom IN obj.format; M.res := 0
						ELSIF M.name = "innertop" THEN M.class := Objects.Bool; M.b := innertop IN obj.format; M.res := 0
						ELSIF M.name = "sameWidth" THEN  M.class := Objects.Bool; M.b := samewidth IN obj.format; M.res := 0
						ELSIF M.name = "sameHeight" THEN M.class := Objects.Bool; M.b := sameheight IN obj.format; M.res := 0
						ELSIF M.name = "hgrid" THEN M.class := Objects.Bool; M.b := hstatic IN obj.format; M.res := 0
						ELSIF M.name = "vgrid" THEN M.class := Objects.Bool; M.b := vstatic IN obj.format; M.res := 0
						ELSE ContainerHandler(obj, M)
						END
					| Objects.set:	changed := FALSE;
						IF (M.name = "rows") & (M.class = Objects.Int) THEN changed := M.i # obj.rows; M.res := 0;
							IF M.i > obj.rows THEN FOR i := 1 TO SHORT(M.i) - obj.rows DO InsertRow(obj, obj.rows, FALSE) END
							ELSIF M.i < obj.rows THEN FOR i := 1 TO obj.rows - SHORT(M.i) DO RemoveRow(obj, obj.rows - 1, FALSE) END
							END
						ELSIF (M.name = "cols") & (M.class = Objects.Int) THEN changed := M.i # obj.cols; M.res := 0;
							IF M.i > obj.cols THEN FOR i := 1 TO SHORT(M.i) - obj.cols DO InsertCol(obj, obj.cols, FALSE) END
							ELSIF M.i < obj.cols THEN FOR i := 1 TO obj.cols - SHORT(M.i) DO RemoveCol(obj, obj.cols - 1, FALSE) END
							END
						ELSIF (M.name = "hdist") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.hdist; obj.hdist := SHORT(M.i); M.res := 0
						ELSIF (M.name = "vdist") & (M.class = Objects.Int) & (M.i >= 0) THEN changed := M.i # obj.vdist; obj.vdist := SHORT(M.i); M.res := 0
						ELSIF (M.name = "innerleft") & (M.class = Objects.Bool) THEN changed := M.b # (innerleft IN obj.format); IF changed THEN obj.format := obj.format/{innerleft} END; M.res := 0
						ELSIF (M.name = "innerright") & (M.class = Objects.Bool) THEN changed := M.b # (innerright IN obj.format); IF changed THEN obj.format := obj.format/{innerright} END; M.res := 0
						ELSIF (M.name = "innerbottom") & (M.class = Objects.Bool) THEN changed := M.b # (innerbottom IN obj.format); IF changed THEN obj.format := obj.format/{innerbottom} END; M.res := 0
						ELSIF (M.name = "innertop") & (M.class = Objects.Bool) THEN changed := M.b # (innertop IN obj.format); IF changed THEN obj.format := obj.format/{innertop} END; M.res := 0
						ELSIF (M.name = "sameWidth") & (M.class = Objects.Bool) THEN changed := M.b # (samewidth IN obj.format); IF changed THEN obj.format := obj.format/{samewidth} END; M.res := 0
						ELSIF (M.name = "sameHeight") & (M.class = Objects.Bool) THEN changed := M.b # (sameheight IN obj.format); IF changed THEN obj.format := obj.format/{sameheight} END; M.res := 0
						ELSIF (M.name = "hgrid") & (M.class = Objects.Bool) THEN changed := M.b # (hstatic IN obj.format); IF changed THEN obj.format := obj.format/{hstatic} END; M.res := 0
						ELSIF (M.name = "vgrid") & (M.class = Objects.Bool) THEN changed :=  M.b # (vstatic IN obj.format); IF changed THEN obj.format := obj.format/{vstatic} END; M.res := 0
						ELSE ContainerHandler(obj, M)
						END;
						IF changed THEN CalcPanelOf(obj) END
					| Objects.enum:	ContainerHandler(obj, M);
						M.Enum("rows"); M.Enum("cols"); M.Enum("hdist"); M.Enum("vdist");
						M.Enum("innerleft"); M.Enum("innerright"); M.Enum("innerbottom"); M.Enum("innertop");
						M.Enum("sameWidth"); M.Enum("sameHeight"); M.Enum("hgrid"); M.Enum("vgrid")
					ELSE				
					END
				END
			ELSIF M IS Objects.FileMsg THEN
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					new := NewTable();
					new.format := obj.format; new.hfactor := obj.hfactor; new.vfactor := obj.vfactor;
					new.row := obj.row; new.col := obj.col;
					new.minx := obj.minx; new.miny := obj.miny; new.minw := obj.minw; new.minh := obj.minh;
					new.hborder := obj.hborder; new.vborder := obj.vborder;
					new.cols := obj.cols; new.rows := obj.rows; new.hdist := obj.hdist; new.vdist := obj.vdist;
					new.hfill := obj.hfill; new.vfill := obj.vfill;
					NEW(new.gmaxw, new.cols); NEW(new.gmaxh, new.rows);
					NEW(new.hexpand, new.cols); NEW(new.vexpand, new.rows);
					NEW(new.hoffset, new.cols + 1); NEW(new.voffset, new.rows + 1);
					
					NEW(head);
					f := obj.dsc; head.next := NIL; fn := head;
					WHILE f # NIL DO
						f.handle(f, M); fn.next := M.obj(Element);
						fn := fn.next; f := f.next
					END;
					fn.next := NIL; new.dsc := head.next;
					SetRowCol(new);

					M.obj := new
				END
			ELSIF M IS Objects.BindMsg THEN
			ELSIF M IS Objects.LinkMsg THEN (* containers have no model *)
			ELSIF M IS Objects.FindMsg THEN
			ELSIF M IS Gadgets.UpdateMsg THEN ContainerHandler(obj, M)
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF M.res >= 0 THEN RETURN END;
					x := M.x + obj.X; y := M.y + obj.Y;
					IF (M.F = NIL) OR (M.F = obj) THEN (* for this Element (or a broadcast) *)
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									Gadgets.MakeMask(obj, x, y, M.dlink, mask);
																												
									IF M.id = Display.area THEN f := obj.dsc;
										WHILE f # NIL DO
											IF Effects.Intersect(M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h, f.X, f.Y, f.W, f.H) THEN
												D.x := M.x; D.y := M.y; D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H;
												ClipAgainst(D.u, D.v, D.w, D.h, M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h);
												D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := M.dlink;
												D.device := Display.screen; D.id := Display.area; D.F := NIL; D.res := -1;
												f.handle(f, D)
											END;
											f := f.next
										END
									ELSE f := obj.dsc;
										WHILE f # NIL DO
											D.x := M.x; D.y := M.y; D.u := f.X; D.v := f.Y; D.w := f.W; D.h := f.H;
											ClipAgainst(D.u, D.v, D.w, D.h, M.u + obj.X, M.v + obj.Y + obj.H - 1, M.w, M.h);
											D.u := D.u - f.X; D.v := D.v - (f.Y + f.H - 1); D.dlink := M.dlink;
											D.device := Display.screen; D.id := Display.area; D.F := NIL; D.res := -1;											
											f.handle(f, D);
											f := f.next
										END
									END;
									
									IF (M.u = 0) OR (M.v = 1 - obj.H) OR (M.u + M.w = obj.W) OR (M.v + M.h  - 1 = 0) THEN
										Display3.Rect(mask, Display3.blue, Display.solid, x, y, obj.W, obj.H, 1, Display.replace);
									END;
									
									IF Gadgets.selected IN obj.state THEN
										Display3.FillPattern(mask, Display3.blue, Display3.selectpat, 0, 0, x, y, obj.W, obj.H, Display.replace);
									END
								ELSIF M.device = Display.printer THEN	(* delegate to Elements *)
								END
							END
						ELSE ContainerHandler(obj, M)
						END
					ELSE ContainerHandler(obj, M)
					END
				END
			ELSE Gadgets.framehandle(obj, M)
			END
		END
	END TableHandler;

	(* --- layout Procedures --- *)

	PROCEDURE SizeElement (e: Element);
		VAR hset, vset: SET;
	
		(* get minw, minh if attributes exist, otherwise set to zero *)
		PROCEDURE MinSize (obj: Display.Frame; VAR w, h: INTEGER);
			VAR M: Objects.AttrMsg;
		BEGIN
			M.id := Objects.get; M.name := "minw"; M.res := -1; obj.handle(obj, M);
			IF (M.res >= 0) & (M.class = Objects.Int) & (M.i >= 0) THEN w := SHORT(M.i)
			ELSE
				M.id := Objects.set; M.name := "minw"; M.res := -1; M.class := Objects.Int; M.i := obj.W; obj.handle(obj, M);
				IF M.res >= 0 THEN w := obj.W ELSE w := 16 END
			END;
			
			M.id := Objects.get; M.name := "minh"; M.res := -1; obj.handle(obj, M);
			IF (M.res >= 0) & (M.class = Objects.Int) & (M.i >= 0) THEN h := SHORT(M.i)
			ELSE
				M.id := Objects.set; M.name := "minh"; M.res := -1; M.class := Objects.Int; M.i := obj.H; obj.handle(obj, M);
				IF M.res >= 0 THEN h := obj.H ELSE h := 16 END
			END
		END MinSize;

	BEGIN
		hset := {}; vset := {};
		IF meleft IN e.format THEN INCL(hset, left) END;
		IF meright IN e.format THEN INCL(hset, right) END;
		IF mebottom IN e.format THEN INCL(vset, bottom) END;
		IF metop IN e.format THEN INCL(vset, top) END;
		
		(* overrider default table constraints *)
		IF hset # {} THEN e.format := (e.format - {left, right}) + hset END;
		IF vset # {} THEN e.format := (e.format - {bottom, top}) + vset END;
		
		IF (e.obj # NIL) & (e.obj IS Display.Frame) THEN MinSize(e.obj(Display.Frame), e.minw, e.minh)
		ELSE (* virtual or something else *)
			IF e.minw < 10 THEN e.minw := 10 END;
			IF e.minh < 10 THEN e.minh := 10 END
		END
	END SizeElement;

	PROCEDURE SizeContainer (c: Element);
		VAR f: Display.Frame;
	BEGIN
		WITH c: Container DO c.minw := 0; c.minh := 0;
			f := c.dsc;
			WHILE f # NIL DO
				WITH f: Element DO f.size(f);
					IF f.minx + f.minw > c.minw THEN c.minw := f.minx + f.minw END;
					IF f.miny + f.minh > c.minh THEN c.minh := f.miny + f.minh END
				END;
				f := f.next
			END;
			SizeElement(c)
			(*
			IF c.minw < 10 THEN c.minw := 10 END;
			IF c.minh < 10 THEN c.minh := 10 END
			*)
		END
	END SizeContainer;

	PROCEDURE SizeTable (t: Element);
		VAR f: Display.Frame; i: INTEGER; set: SET;
	BEGIN
		WITH t: Table DO
			FOR i := 0 TO t.cols - 1 DO t.gmaxw[i] := 0; t.hexpand[i] := 0 END;
			FOR i := 0 TO t.rows - 1 DO t.gmaxh[i] := 0; t.vexpand[i] := 0 END;
			
			set := {};
			IF innerleft IN t.format THEN INCL(set, left) END; IF innerright IN t.format THEN INCL(set, right) END;
			IF innertop IN t.format THEN INCL(set, top) END; IF innerbottom IN t.format THEN INCL(set, bottom) END;
						
			f := t.dsc;
			WHILE f # NIL DO
				WITH f: Element DO
					(* default Table constraints (hjustify, vjustify) *)					
					f.format := (f.format - {left..top}) + set;
					f.size(f);
					
					(* calculate minimal row, col sizes and factors *)
					IF f.minw > t.gmaxw[f.col] THEN t.gmaxw[f.col] := f.minw END;
					IF f.minh > t.gmaxh[f.row] THEN t.gmaxh[f.row] := f.minh END;
					IF f.hfactor > t.hexpand[f.col] THEN t.hexpand[f.col] := f.hfactor END;
					IF f.vfactor > t.vexpand[f.row] THEN t.vexpand[f.row] := f.vfactor END;
				END;
				f := f.next;
			END;
			
			(* calculate minw, minh, hfill, vfill of Table *)
			t.minw := 2*t.hborder + (t.cols - 1)*t.hdist; t.hfill := 0;
			t.minh := 2*t.vborder + (t.rows - 1)*t.vdist; t.vfill := 0;
			FOR i := 0 TO t.cols - 1 DO INC(t.minw, t.gmaxw[i]); INC(t.hfill, t.hexpand[i]) END;
			FOR i := 0 TO t.rows - 1 DO INC(t.minh, t.gmaxh[i]); INC(t.vfill, t.vexpand[i]) END;
			
			SizeElement(t)	(* new *)
		END
	END SizeTable;
	
	(* --- *)

	(* aligns e according to e.format and propagates (if it exists) to Gadget *)
	PROCEDURE MakeElement (e: Element; x, y, w, h: INTEGER);
	
		PROCEDURE SetSize (F: Display.Frame; x, y, w, h: INTEGER);
			VAR M: Display.ModifyMsg;
		BEGIN
			M.id := Display.extend; M.mode := Display.state; M.F := F;
			(* simulated broadcast *)
			Objects.Stamp(M); M.res := -1;
			(* M.dlink := GetPanel(e); M.x := ...; M.y := ...; *)			
			M.X := x; M.Y := y; M.dX := M.X - F.X; M.dY := M.Y - F.Y;
			M.W := w; M.H := h; M.dW := M.W - F.W; M.dH := M.H - F.H;
			F.handle(F, M)	(* Display.Broadcast(M) is not allowed here!!! *)
		END SetSize;

	BEGIN
		e.X := x; e.Y := y;		
		IF e.hfactor > 0 THEN e.W := w	(* fill out space *)
		ELSE (* e.W := e.minw; *)	(* ? *)
			IF right IN e.format THEN
				IF left IN e.format THEN INC(e.X, (w - e.W) DIV 2)
				ELSE INC(e.X, w - e.W)
				END
			ELSE
				IF left IN e.format THEN (* nothing *)
				ELSE	(* default is left *)
				END
			END
		END;
		IF e.vfactor > 0 THEN e.H := h
		ELSE (* e.H := e.minh; *)
			IF top IN e.format THEN
				IF bottom IN e.format THEN INC(e.Y, (h - e.H) DIV 2)
				ELSE INC(e.Y, h - e.H)
				END
			ELSE
				IF bottom IN e.format THEN (* nothing *)
				ELSE	(* default is bottom *)
				END
			END
		END;
		IF (e.obj # NIL) & (e.obj IS Display.Frame) THEN
			SetSize(e.obj(Display.Frame), e.X, e.Y, e.W, e.H)
		END
	END MakeElement;

	PROCEDURE MakePlace (c: Element; x, y, w, h: INTEGER);
		VAR f: Display.Frame;
	BEGIN
		WITH c: Container DO
			MakeElement(c, x, y, w, h);			
			f := c.dsc;
			WHILE f # NIL DO
				WITH f: Element DO
					f.W := f.minw; f.H := f.minh;
					f.make(f, c.X + c.hborder + f.minx, c.Y + c.vborder + f.miny, f.minw, f.minh)	
				END;
				f := f.next
			END
		END
	END MakePlace;
		
	(* FillCols calculates column widths and row heights according to max, expand. result in max *)
	PROCEDURE FillCols (space, cols, fills: INTEGER; expand, max: IntArray; sameSize: BOOLEAN);
		VAR d, m, i: INTEGER; fillList: IntArray;
	BEGIN
		IF sameSize THEN
			d := space DIV cols; m := space MOD cols;
			FOR i := 0 TO cols - 1 DO INC(max[i], d) END;
			FOR i := 0 TO m - 1 DO INC(max[i]) END
		ELSIF space > 0 THEN
			IF fills > 0 THEN
				NEW(fillList, fills); m := 0;
				FOR i := 0 TO cols - 1 DO
					FOR d := 1 TO expand[i] DO fillList[m] := i; INC (m) END
				END;
				i := 0;
				WHILE space > 0 DO d := fillList [i MOD fills];
					IF max[d] < (i DIV fills)*expand[d] THEN INC (max[d]); DEC(space) END;
					INC(i)
				END
			ELSE INC(max[cols-1], space)
			END
		END
	END FillCols;

	PROCEDURE SetOffset (cols, border, dist: INTEGER; max, offset: IntArray);
		VAR i: INTEGER;
	BEGIN offset[0] := border;
		FOR i := 1 TO cols DO offset[i] := offset[i - 1]; INC(offset[i], max[i - 1] + dist) END	(* simplified expression *)
	END SetOffset;

	PROCEDURE MakeTable (t: Element; x, y, w, h: INTEGER);
		VAR f: Display.Frame; x1, y1, w1, h1: INTEGER;
	BEGIN
		WITH t: Table DO
			MakeElement(t, x, y, w, h);
			
			FillCols(t.W - t.minw, t.cols, t.hfill, t.hexpand, t.gmaxw, t.format*{samewidth, hstatic} # {});
			FillCols(t.H - t.minh, t.rows, t.vfill, t.vexpand, t.gmaxh, t.format*{sameheight, vstatic} # {});

			SetOffset(t.cols, t.hborder, t.hdist, t.gmaxw, t.hoffset);
			SetOffset(t.rows, t.vborder, t.vdist, t.gmaxh, t.voffset);
			
			f := t.dsc;
			WHILE f # NIL DO
				WITH f: Element DO
					(* rectangle of each element *)
					x1 := t.hoffset[f.col]; w1 := t.hoffset[f.col + 1] - x1 - t.hdist; INC(x1, t.X);
					y1 := t.voffset[f.row]; h1 := t.voffset[f.row + 1] - y1 - t.vdist; INC(y1, t.Y);
					IF samewidth IN t.format THEN f.W := w1 ELSE f.W := f.minw END;
					IF sameheight IN t.format THEN f.H := h1 ELSE f.H := f.minh END;
					f.make(f, x1, y1, w1, h1)
				END;
				f := f.next
			END
		END
	END MakeTable;

	(* --- Generators for Objects --- *)
	
	PROCEDURE InitElement (obj: Element);
	BEGIN
		obj.handle := ElementHandler; obj.size := SizeElement; obj.make := MakeElement;
		obj.dsc := NIL; obj.next := NIL; obj.obj := NIL;
		obj.format := {left, bottom, innerleft, innerbottom};
		obj.X := 0; obj.Y := 0; obj.W := 0; obj.H := 0;
		obj.minx := 0; obj.miny := 0; obj.minw := 10; obj.minh := 10; obj.hfactor := 0; obj.vfactor := 0;
		obj.row := 0; obj.col := 0
	END InitElement;
	
	PROCEDURE NewElement* (): Element;
		VAR obj: Element;
	BEGIN NEW(obj); InitElement(obj); RETURN obj
	END NewElement;
		
	PROCEDURE InitContainer(obj: Container);
	BEGIN InitElement(obj);
		obj.handle := ContainerHandler; obj.size := SizeContainer; obj.make := MakePlace;
		obj.hborder := 0; obj.vborder := 0
	END InitContainer;
	
	PROCEDURE NewContainer* (): Container;
		VAR obj: Container;
	BEGIN NEW(obj); InitContainer(obj); RETURN obj
	END NewContainer;

	PROCEDURE InitTable (obj: Table);
	BEGIN InitContainer(obj);
		obj.handle := TableHandler; obj.size := SizeTable; obj.make := MakeTable;
		obj.rows := 1; obj.cols := 1; obj.hdist := 5; obj.vdist := 5;
		NEW(obj.gmaxw, obj.cols); NEW(obj.hexpand, obj.cols); NEW(obj.gmaxh, obj.rows); NEW(obj.vexpand, obj.rows);
		NEW(obj.hoffset, obj.cols + 1); NEW(obj.voffset, obj.rows + 1)
	END InitTable;
	
	PROCEDURE NewTable* (): Table;
		VAR obj: Table;
	BEGIN NEW(obj); InitTable(obj); RETURN obj
	END NewTable;
	
	(** creates an empty Table with rows*cols Elements *)
	PROCEDURE EmptyTable* (rows, cols: INTEGER): Table;
		VAR t: Table; f: Display.Frame; t0: Element; i, j: INTEGER;
	BEGIN
		t := NewTable(); t.cols := cols; t.rows := rows; t.hfactor := 1; t.vfactor := 1;
		head.next := NIL; f := head;
		FOR i := 0 TO rows - 1 DO
			FOR j := 0 TO cols - 1 DO
				t0 := NewElement(); f.next := t0; f := f.next;
				WITH f: Element DO f.row := i; f.col := j; f.hfactor := 1; f.vfactor := 1 END
			END
		END;
		f.next := NIL; t.dsc := head.next;
		NEW(t.gmaxw, cols); NEW(t.hexpand, cols); NEW(t.hoffset, cols + 1);
		NEW(t.gmaxh, rows); NEW(t.vexpand, rows); NEW(t.voffset, rows + 1);
		RETURN t
	END EmptyTable;


	(* EBNF:
	Object = "O" "(" ObjBody ")" | Container.
	Container = ("P" | "T") "(" ObjBody {Object} ")".
	
	ObjBody = {Set}.
	Set = Ident "=" Value.
	
	Ident = SmallLetter {SmallLetter}.
	SmallLetter = "a".."z".
	Value = Int.
	
	Virtual: implicitly with id = 0.
	*)

	(** parses Text T and creates datastructure in obj,
	T, lib # NIL
	*)
	PROCEDURE Parse* (T: Texts.Text; VAR obj: Element; lib: Objects.Library);
	CONST
		(* symbols *)
		border = 0; cols = 1; grid = 3;
		h = 4; hborder = 5; hfactor = 6; hdist = 7; hgrid = 8; hjustify = 9; hjustifyMe = 10; id = 11;
		(* orientation = 11 *)
		rows = 12;
		sameHeight = 13; sameWidth = 14; sameSize = 15;
		vborder = 16; vdist = 17; vfactor = 18; vgrid = 19; vjustify = 20; vjustifyMe = 21;
		w = 22; x = 23; y = 24;
		ident = 25;	(* unknown keyword *)

	VAR
		R: Texts.Reader;
		ch: CHAR;	(* last read character *)
	
		PROCEDURE Mark (str: ARRAY OF CHAR);
		BEGIN
			Texts.WriteString(W, "  pos: "); Texts.WriteInt(W, Texts.Pos(R), 11);
			Texts.WriteString(W, "  "); Texts.WriteString(W, str);
			Texts.WriteLn(W)
		END Mark;
	
		PROCEDURE Get (VAR ch: CHAR);
		BEGIN REPEAT Texts.Read(R, ch) UNTIL (ch = 0X) OR (ch > " ")
		END Get;
				
		PROCEDURE Int (VAR x: INTEGER);
			VAR neg: BOOLEAN;
		BEGIN
			neg := ch = "-"; IF neg THEN Get(ch) END;
			x := ORD(ch) - ORD("0"); Get(ch);
			WHILE (ch >= "0") & (ch <= "9") DO x := 10*x + ORD(ch) - ORD("0"); Get(ch) END;
			IF neg THEN x := -x END
		END Int;
		
		PROCEDURE ObjBody(obj: Element);
		VAR
			key, val: INTEGER; t: Objects.Object;
			
			PROCEDURE Ident (): SHORTINT;
				VAR ch1: CHAR;
			BEGIN ch1 := ch; Get(ch);
				CASE ch1 OF
				   "b": RETURN border
				| "c": RETURN cols
				| "g": RETURN grid
				| "h": ch1 := ch;
					CASE ch1 OF
					  "b": Get(ch); RETURN hborder
					| "d": Get(ch); RETURN hdist
					| "f": Get(ch); RETURN hfactor
					| "g": Get(ch); RETURN hgrid
					| "j": Get(ch); RETURN hjustify
					| "m": Get(ch); RETURN hjustifyMe
					ELSE RETURN h
					END
				| "i": RETURN id
				| "r": RETURN rows
				| "s": ch1 := ch; Get(ch);
					CASE ch1 OF
					   "h": RETURN sameHeight
					| "w": RETURN sameWidth
					| "s": RETURN sameSize
					END
				| "v": ch1 := ch; Get(ch);
					CASE ch1 OF
						   "b": RETURN vborder
						| "d": RETURN vdist
						| "f": RETURN vfactor
						| "g": RETURN vgrid
						| "j": RETURN vjustify
						| "m": RETURN vjustifyMe
					ELSE
					END
				| "w": RETURN w
				| "x": RETURN x
				| "y": RETURN y
				ELSE
				END;
				Mark("unknown keyword"); RETURN ident
			END Ident;

		BEGIN
			WHILE (ch >= "a") & (ch <= "z") DO (* Set *)
				key := Ident();
				IF ch = "=" THEN
					Get(ch); Int(val);
					
					IF obj IS Container THEN		
						IF obj IS Table THEN
							WITH obj: Table DO
								CASE key OF
								   cols: obj.cols := val; NEW(obj.gmaxw, val); NEW(obj.hexpand, val); NEW(obj.hoffset, val + 1)
								| rows: obj.rows := val; NEW(obj.gmaxh, val); NEW(obj.vexpand, val); NEW(obj.voffset, val + 1)
								| hdist: obj.hdist := val
								| vdist: obj.vdist := val
								| sameSize:
									IF val = 1 THEN obj.format := obj.format + {samewidth, sameheight}
									ELSE obj.format := obj.format - {samewidth, sameheight}
									END
								| sameHeight: IF val = 1 THEN INCL(obj.format, samewidth) ELSE EXCL(obj.format, samewidth) END
								| sameWidth: IF val = 1 THEN INCL(obj.format, sameheight) ELSE EXCL(obj.format, sameheight) END
								| grid:
									IF val = 1 THEN obj.format := obj.format + {hstatic, vstatic}
									ELSE obj.format := obj.format - {hstatic, vstatic}
									END
								| hgrid: IF val = 1 THEN INCL(obj.format, hstatic) ELSE EXCL(obj.format, hstatic) END
								| vgrid: IF val = 1 THEN INCL(obj.format, vstatic) ELSE EXCL(obj.format, vstatic) END
								| hjustify:
									CASE val OF
									   0: (* undef *) obj.format := obj.format - {innerleft, innerright}	(* unnecessary *)
									| 1: (* left *) INCL(obj.format, innerleft); EXCL(obj.format, innerright)
									| 2: (* right *) INCL(obj.format, innerright); EXCL(obj.format, innerleft)
									| 3: (* center *) obj.format := obj.format + {innerleft, innerright}
									ELSE
									END
								| vjustify:
									CASE val OF
									   0: (* undef *) obj.format := obj.format - {innerbottom, innertop}	(* unnecessary *)
									| 1: (* bottom *) INCL(obj.format, innerbottom); EXCL(obj.format, innertop)
									| 2: (* top *) INCL(obj.format, innertop); EXCL(obj.format, innerbottom)
									| 3: (* center *) obj.format := obj.format + {innerbottom, innertop}
									ELSE
									END
								ELSE
								END
							END
						END;
						WITH obj: Container DO
							CASE key OF
							   border: obj.hborder := val; obj.vborder := val
							| hborder: obj.hborder := val
							| vborder: obj.vborder := val
							ELSE
							END
						END
					END;								
					CASE key OF
					   hjustifyMe:
						CASE val OF
						   0: (* undef *) obj.format := obj.format - {meleft, meright}	(* unnecessary *)
						| 1: (* left *) INCL(obj.format, meleft); EXCL(obj.format, meright)
						| 2: (* right *) INCL(obj.format, meright); EXCL(obj.format, meleft)
						| 3: (* center *) obj.format := obj.format + {meleft, meright}
						ELSE
						END
					| vjustifyMe:
						CASE val OF
							   0: (* undef *) obj.format := obj.format - {mebottom, metop}	(* unnecessary *)
							| 1: (* bottom *) INCL(obj.format, mebottom); EXCL(obj.format, metop)
							| 2: (* top *) INCL(obj.format, metop); EXCL(obj.format, mebottom)
							| 3: (* center *) obj.format := obj.format + {mebottom, metop}
						ELSE (* ignore *)
						END
					| hfactor: obj.hfactor := val
					| vfactor: obj.vfactor := val
					| x: obj.minx := val
					| y: obj.miny := val
					| w: obj.minw := val
					| h: obj.minh := val
					| id: lib.GetObj(lib, val, t); IF t IS Display.Frame THEN obj.obj := t(Display.Frame) END (* get library object for ref = val, change this !!! *)
					ELSE
					END
				ELSE Mark("=?")
				END
			END
		END ObjBody;

		PROCEDURE Object (VAR obj: Element);
			VAR head, f: Display.Frame; t: Element; i, j: INTEGER;
		BEGIN NEW(head); (* new head for each recursion *)
			CASE ch OF
			   "O":	(* Element *)
		   	obj := NewElement(); Get(ch);
		   	IF ch = "(" THEN
			   	Get(ch); ObjBody(obj);
			   	IF ch = ")" THEN Get(ch)
			   	ELSE Mark(")?")
			   	END
			   ELSE Mark("(?")
			   END
			   
			| "P":	(* Place Container *)
				obj := NewContainer(); Get(ch);
				IF ch = "(" THEN
					Get(ch); ObjBody(obj);
					IF ch # ")" THEN
						head.next := NIL; f := head;
						WHILE ch # ")" DO
							Object(t); f.next := t; f := f.next
						END;
						f.next := NIL; obj.dsc := head.next
					ELSE Mark("Object?")
					END;
					Get(ch)
				ELSE Mark("(?")
				END
				
			| "T":	(* Table Container *)
				obj := NewTable(); Get(ch);
				IF ch = "(" THEN
					Get(ch); ObjBody(obj);
					IF ch # ")" THEN
						i := 0; j := 0; head.next := NIL; f := head;
						WHILE ch # ")" DO Object(t); f.next := t; f := f.next; f(Element).row := i; f(Element).col := j;
							INC(j);
							IF j >= obj(Table).cols THEN j := 0; INC(i) END
						END;
						f.next := NIL; obj.dsc := head.next
					ELSE Mark("Object?")
					END;
					Get(ch)
				ELSE Mark("(?")
				END
				
			ELSE Mark("not an Object")
			END
		END Object;
	
	BEGIN
		Texts.OpenReader(R, T, 0);
		 Get(ch); Object(obj)
	END Parse;
	
	(* --- *)

	(** traverses datastructure in e and produces Text T *)
	PROCEDURE Produce* (e: Element; T: Texts.Text);
		VAR W: Texts.Writer;
		
		PROCEDURE Put (ch: CHAR); BEGIN Texts.Write(W, ch) END Put;
		PROCEDURE PutStr (str: ARRAY OF CHAR); BEGIN Texts.WriteString(W, str) END PutStr;

		PROCEDURE PutInt (x: LONGINT);
			VAR a: ARRAY 11 OF CHAR; i: INTEGER;
		BEGIN
			IF x < 0 THEN
				IF x = MIN(LONGINT) THEN PutStr("-2147483648"); RETURN
				ELSE Put("-"); x := -x
				END
			END;
			i := 0;
			REPEAT a[i] := CHR(x MOD 10 + ORD("0")); INC(i); x := x DIV 10 UNTIL x = 0;
			REPEAT DEC(i); Put(a[i]) UNTIL i = 0
		END PutInt;

		PROCEDURE element (e: Element; place: BOOLEAN);
			VAR f: Display.Frame;
		BEGIN
			(* kind *)
			IF e IS Table THEN PutStr("T(")
			ELSIF e IS Container THEN PutStr("P(")
			ELSE PutStr("O(")
			END;
			
			(* --- ObjBody --- *)
			(* table *)
			IF e IS Table THEN
				WITH e: Table DO
					IF e.cols # 1 THEN PutStr("c="); PutInt(e.cols) END;
					IF e.rows # 1 THEN PutStr("r="); PutInt(e.rows) END;
					IF e.hdist # 5 THEN PutStr("hd="); PutInt(e.hdist) END;
					IF e.vdist # 5 THEN PutStr("vd="); PutInt(e.vdist) END;
					IF (samewidth IN e.format) & (sameheight IN e.format) THEN PutStr("ss=1")	(* simplify expression *)
					ELSIF samewidth IN e.format THEN PutStr("sw=1")
					ELSIF sameheight IN e.format THEN PutStr("sh=1")
					END;
					IF (hstatic IN e.format) & (vstatic IN e.format) THEN PutStr("g=1")	(* simplify expression *)
					ELSIF hstatic IN e.format THEN PutStr("hg=1")
					ELSIF vstatic IN e.format THEN PutStr("vg=1")
					END;
					IF innerleft IN e.format THEN
						IF innerright IN e.format THEN PutStr("hj=3")
						ELSE PutStr("hj=1")
						END
					ELSIF innerright IN e.format THEN PutStr("hj=2")
					END;
					IF innerbottom IN e.format THEN
						IF innertop IN e.format THEN PutStr("vj=3")
						ELSE PutStr("vj=1")
						END
					ELSIF innertop IN e.format THEN PutStr("vj=2")
					END
				END
			END;
			
			(* container *)
			IF e IS Container THEN
				WITH e: Container DO
					IF (e.hborder # 0) & (e.hborder = e.vborder) THEN PutStr("b="); PutInt(e.hborder)
					ELSIF e.hborder # 0 THEN PutStr("hb="); PutInt(e.hborder)
					ELSIF e.vborder # 0 THEN PutStr("vb="); PutInt(e.vborder)
					END
				END
			END;
			
			
			(* Element  *)
			
			IF ~(e IS Container) & (e.obj # NIL) THEN PutStr("i="); PutInt(e.obj.ref) END;
		
			IF meleft IN e.format THEN
				IF meright IN e.format THEN PutStr("hm=3")
				ELSE PutStr("hm=1")
				END
			ELSIF meright IN e.format THEN PutStr("hm=2")	
			END;
			
			IF mebottom IN e.format THEN
				IF metop IN e.format THEN PutStr("vm=3")
				ELSE PutStr("vm=1")
				END
			ELSIF metop IN e.format THEN PutStr("vm=2")	
			END;
			
			IF place THEN	(* parent is place *)
				IF e.minx # 0 THEN PutStr("x="); PutInt(e.minx) END;
				IF e.miny # 0 THEN PutStr("y="); PutInt(e.miny) END
			END;
			
			IF ~(e IS Container) THEN
				IF e.minw # 0 THEN PutStr("w="); PutInt(e.minw) END;
				IF e.minh # 0 THEN PutStr("h="); PutInt(e.minh) END
			END;

			IF e.hfactor # 0 THEN PutStr("hf="); PutInt(e.hfactor) END;
			IF e.vfactor # 0 THEN PutStr("vf="); PutInt(e.vfactor) END;
			
			(* Objects *)
			IF e IS Container THEN f := e(Container).dsc;
				WHILE f # NIL DO element(f(Element), ~(e IS Table)); f := f.next END
			END;
			
			Put(")")
		END element;
	
	BEGIN
		Texts.OpenWriter(W);
		element(e, FALSE);
		Texts.Delete(T, 0, T.len); Texts.Append(T, W.buf)
	END Produce;
	
	
	(* --- select procedures --- *)
	
	(** get top most selection *)
	PROCEDURE GetSelection* (e: Element): Display.Frame;
		VAR f, e1: Display.Frame;
	BEGIN
		IF Gadgets.selected IN e.state THEN RETURN e
		ELSIF (e.obj # NIL) & (e.obj IS Gadgets.Frame) & (Gadgets.selected IN e.obj(Gadgets.Frame).state) THEN RETURN e.obj(Display.Frame)
		ELSIF e IS Container THEN f := e(Container).dsc; e1 := NIL;
			WHILE (f # NIL) & (e1 = NIL) DO e1 := GetSelection(f(Element)); f := f.next END;
			RETURN e1
		ELSE RETURN NIL
		END
	END GetSelection;


	(* --- Debugging Procedures --- *)

	PROCEDURE Info* (e: Display.Frame);
	BEGIN
		Texts.WriteString(W, "x = "); Texts.WriteInt(W, e.X, 5);
		Texts.WriteString(W, "  y = "); Texts.WriteInt(W, e.Y, 5);
		Texts.WriteString(W, "  w = "); Texts.WriteInt(W, e.W, 5);
		Texts.WriteString(W, "  h = "); Texts.WriteInt(W, e.H, 5);
		IF e IS Element THEN
			WITH e: Element DO
				Texts.WriteString(W, "  minx = "); Texts.WriteInt(W, e.minx, 5);
				Texts.WriteString(W, "  miny = "); Texts.WriteInt(W, e.miny, 5);
				Texts.WriteString(W, "  minw = "); Texts.WriteInt(W, e.minw, 5);
				Texts.WriteString(W, "  minh = "); Texts.WriteInt(W, e.minh, 5);
				Texts.WriteLn(W);
				IF e IS Container THEN
					WITH e: Container DO
						Texts.WriteString(W, "hborder = "); Texts.WriteInt(W, e.hborder, 5);
						Texts.WriteString(W, "vborder = "); Texts.WriteInt(W, e.vborder, 5);
						Texts.WriteLn(W)
					END;
					IF e IS Table THEN
						WITH e: Table DO
							Texts.WriteString(W, "table  ");
							Texts.WriteString(W, "cols = "); Texts.WriteInt(W, e.cols, 5);
							Texts.WriteString(W, "rows = "); Texts.WriteInt(W, e.rows, 5);
							Texts.WriteString(W, "hdist = "); Texts.WriteInt(W, e.hdist, 5);
							Texts.WriteString(W, "vdist = "); Texts.WriteInt(W, e.vdist, 5);
							Texts.WriteString(W, "hfill = "); Texts.WriteInt(W, e.hfill, 5);
							Texts.WriteString(W, "vfill = "); Texts.WriteInt(W, e.vfill, 5);
							Texts.WriteLn(W)
						END
					END
				END
			END
		END
	END Info;

	(** call with depth = 0 *)
	PROCEDURE DebugElements* (e: Element; depth: INTEGER);
		VAR i: INTEGER; f: Display.Frame;
	BEGIN
		FOR i := 0 TO depth - 1 DO Texts.Write(W, 9X) END;
		Texts.WriteString(W, "x = "); Texts.WriteInt(W, e.X, 5);
		Texts.WriteString(W, "  y = "); Texts.WriteInt(W, e.Y, 5);
		Texts.WriteString(W, "  w = "); Texts.WriteInt(W, e.W, 5);
		Texts.WriteString(W, "  h = "); Texts.WriteInt(W, e.H, 5);
		Texts.WriteString(W, "  minx = "); Texts.WriteInt(W, e.minx, 5);
		Texts.WriteString(W, "  miny = "); Texts.WriteInt(W, e.miny, 5);
		Texts.WriteString(W, "  minw = "); Texts.WriteInt(W, e.minw, 5);
		Texts.WriteString(W, "  minh = "); Texts.WriteInt(W, e.minh, 5);
		Texts.WriteLn(W);
		IF e IS Container THEN f := e(Container).dsc;
			WHILE f # NIL DO DebugElements(f(Element), depth + 1); f := f.next END
		END
	END DebugElements;

BEGIN
	Texts.OpenWriter(W);
	NEW(head)
END LayoutPanels0.
