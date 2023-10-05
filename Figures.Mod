MODULE Figures;	(** eos   **)

	IMPORT
		Files, Display, Math, Objects, Oberon, Gadgets, GfxMatrix, GfxMaps, GfxRegions, Gfx, Solver;
		
	
	CONST
		(** units **)
		Inch* = 91.44; cm* = Inch/2.54;
		A4W* = 21 * cm; A4H* = 29.7 * cm;
		LetterW* = 8.5 * Inch; LetterH* = 11 * Inch;
		
		(** shape message ids **)
		Get* = 0;
		Set* = 3; Reset* = 4;
		Consume* = 6; Remove* = 7;
		Up* = 8; Down* = 9; Top* = 21; Bottom* = 22; Reverse* = 10;
		Inside* = 11; Overlap* = 12; Project* = 13;
		Full* = 14; Print* = 15;
		Apply* = 16; Notify* = 17; Suggest* = 20;
		
		BorderWidth* = 12;	(** number of extra units in default context coordinates available for rendering selection hints **)
		
		MaxCommands = 20;
		
	
	TYPE
		(** graphical objects **)
		Shape* = POINTER TO ShapeDesc;
		ShapeDesc* = RECORD (Objects.ObjDesc)
			cont*: Shape;	(** shape containing this shape **)
			llx*, lly*, urx*, ury*: REAL;	(** exact bounding box **)
			bw*: REAL;	(** width of border around shape affected by rendering **)
			sel*: BOOLEAN;	(** set if shape or one of its components is selected **)
		END;
		
		(** lists of references to shapes **)
		Reference* = POINTER TO ReferenceDesc;
		ReferenceDesc* = RECORD
			shape*: Shape;	(** referenced shape **)
			next*, prev*: Reference;	(** links to next and previous shape reference within list **)
		END;
		
		(** shapes containing others **)
		Container* = POINTER TO ContainerDesc;
		ContainerDesc* = RECORD (ShapeDesc)
			first*, last*: Reference;	(** first (bottommost) and last (topmost) element in list of components **)
		END;
		
		(** collection of shapes **)
		Command = POINTER TO CommandDesc;
		
		Figure* = POINTER TO FigureDesc;
		FigureDesc* = RECORD (Objects.ObjDesc)
			root*: Container;	(** container holding all shapes **)
			width*, height*: REAL;	(** figure dimensions **)
			selTime*: LONGINT;	(** time of current selection (<0 if no shapes selected) **)
			damage: GfxRegions.Region;	(* accumulated area that should be updated *)
			border: REAL;	(* maximum border width within damage region *)
			lockLevel: INTEGER;	(* enables updates if not positive *)
			cmdLevel: INTEGER;	(* number of nested commands *)
			maxCmds, nofCmds: INTEGER;	(* maximal and current number of undoable commands retained *)
			curCmd: Command;	(* current command *)
			firstCmd: Command;	(* first command that can still be undone *)
			undoCmd: Command;	(* command to undo next *)
		END;
		
		(** undoable commands **)
		Action* = POINTER TO ActionDesc;
		ActionProc* = PROCEDURE (fig: Figure; act: Action; stamp: LONGINT; undo: BOOLEAN);
		ActionDesc* = RECORD
			do: ActionProc;	(* handler for executing and undoing actions *)
			link: Action;	(* link to next action *)
		END;
		
		CommandDesc = RECORD
			next, prev: Command;	(* links to next and previous command *)
			actions, done, last: Action;	(* list of actions *)
		END;
		
		ControlAction* = POINTER TO ControlActionDesc;
		ControlActionDesc* = RECORD (ActionDesc)
			id: INTEGER;
			prev, first, last, next: Reference;
			cont: Container;
		END;
		
		AttrAction = POINTER TO AttrActionDesc;
		AttrActionDesc = RECORD (ActionDesc)
			obj: Objects.Object;
			attr: Solver.AttrNode;
		END;
		
		(** broadcast of model changes **)
		UpdateMsg* = RECORD (Display.FrameMsg)
			fig*: Figure;	(** affected figure **)
			reg*: GfxRegions.Region;	(** affected area **)
			bw*: INTEGER;	(** border to add around region **)
		END;
		
		(** shape message base type **)
		ShapeMsg* = RECORD (Objects.ObjMsg)
			fig*: Figure;	(** containing figure **)
		END;
		
		(** message for changing or querying the selection state of shapes **)
		SelectMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Get/Set/Reset **)
			shapes*: Shape;	(** linked list of shapes which handled Get **)
		END;
		
		(** message for locating shapes **)
		LocateMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Inside/Overlap/Project **)
			llx*, lly*, urx*, ury*: REAL;	(** rectangle within which to locate **)
			shapes*: Shape;	(** linked list of shapes which handled message (in top-down order) **)
			px*, py*: REAL;	(** projected coordinates **)
		END;
		
		(** message asking a shape to validate its bounding box and update the containing figure **)
		ValidateMsg* = RECORD (ShapeMsg)
			mat*: GfxMatrix.Matrix;	(** local to global transformation **)
		END;
		
		(** message for rendering shapes on a graphics context **)
		DrawMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Full/Print **)
			all*: BOOLEAN;	(** set if all shapes should render themselves, otherwise only stamped shapes should **)
			ctxt*: Gfx.Context;	(** associated context **)
			mat*: GfxMatrix.Matrix;	(** transformation from default to current context space **)
			llx*, lly*, urx*, ury*: REAL;	(** clip rectangle **)
		END;
		
		(** message for changing the shape hierarchy **)
		ControlMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Consume/Remove **)
			dest*: Shape;	(** shape that should handle the message **)
			shapes*: Shape;	(** shape(s) parameter **)
		END;
		
		(** message for reordering selected shapes **)
		PriorityMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Up/Down/Top/Bottom/Reverse **)
		END;
		
		(** message for applying transformations to shapes or querying a local transformation **)
		TransformMsg* = RECORD (ShapeMsg)
			id*: INTEGER;	(** Get/Apply/Notify/Suggest **)
			mat*: GfxMatrix.Matrix;	(** transformation matrix **)
			x0*, y0*, x1*, y1*: REAL;	(** original and moved point coordinates for transformation suggestion **)
		END;
		
	
	VAR
		Dummy*: Shape;	(** replacement for shapes with missing generator **)
		
	
	(**--- Basic Object Functionality ---**)
	
	PROCEDURE Forward* (from, to: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR dlink, mlink: Objects.Object;
	BEGIN
		dlink := from.dlink; mlink := msg.dlink;
		from.dlink := mlink; msg.dlink := from;
		to.handle(to, msg);
		from.dlink := dlink; msg.dlink := mlink
	END Forward;
	
	PROCEDURE HandleGenAttr* (VAR msg: Objects.AttrMsg; s: ARRAY OF CHAR);
	BEGIN
		IF (msg.id = Objects.get) & (msg.name = "Gen") & (msg.res < 0) THEN
			msg.class := Objects.String; COPY(s, msg.s); msg.res := 0
		END
	END HandleGenAttr;
	
	PROCEDURE HandleStringAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.String; COPY(s, msg.s); msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.String) THEN
				COPY(msg.s, s); msg.res := 0
			END
		END
	END HandleStringAttr;
	
	PROCEDURE HandleIntAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR i: INTEGER; lo, hi: INTEGER);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Int; msg.i := i; msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.Int) THEN
				IF msg.i < lo THEN i := lo
				ELSIF hi < msg.i THEN i := hi
				ELSE i := SHORT(msg.i)
				END;
				msg.res := 0
			END
		END
	END HandleIntAttr;
	
	PROCEDURE HandleLongIntAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR l: LONGINT; lo, hi: LONGINT);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Int; msg.i := l; msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.Int) THEN
				IF msg.i < lo THEN l := lo
				ELSIF hi < msg.i THEN l := hi
				ELSE l := msg.i
				END;
				msg.res := 0
			END
		END
	END HandleLongIntAttr;
	
	PROCEDURE HandleRealAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR r: REAL);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Real; msg.x := r; msg.res := 0
			ELSIF msg.id = Objects.set THEN
				IF msg.class = Objects.Int THEN
					r := msg.i; msg.res := 0
				ELSIF msg.class = Objects.Real THEN
					r := msg.x; msg.res := 0
				ELSIF msg.class = Objects.LongReal THEN
					r := SHORT(msg.y); msg.res := 0
				END
			END
		END
	END HandleRealAttr;
	
	PROCEDURE HandleBoolAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR b: BOOLEAN);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Bool; msg.b := b; msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.Bool) THEN
				b := msg.b; msg.res := 0
			END
		END
	END HandleBoolAttr;
	
	PROCEDURE HandleColorAttr* (VAR msg: Objects.AttrMsg; name: ARRAY OF CHAR; VAR col: Gfx.Color);
	BEGIN
		IF msg.id = Objects.enum THEN
			msg.Enum(name)
		ELSIF (msg.res < 0) & (msg.name = name) THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Int; msg.i := GfxMaps.BestIndex(GfxMaps.DisplayPal, col.r, col.g, col.b); msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.Int) & (0 <= msg.i) & (msg.i < GfxMaps.DisplayPal.used) THEN
				col := GfxMaps.DisplayPal.col[msg.i]; msg.res := 0
			END
		END
	END HandleColorAttr;
	
	
	(**--- Shape Bounds ---**)
	
	PROCEDURE GetShapeBox* (shape: Shape; VAR llx, lly, urx, ury, bw: REAL);
		VAR tm: TransformMsg;
	BEGIN
		llx := shape.llx; lly := shape.lly; urx := shape.urx; ury := shape.ury; bw := 0;
		IF (urx >= llx) & (ury >= lly) THEN
			tm.fig := NIL; tm.id := Get;
			shape.handle(shape, tm);
			GfxMatrix.ApplyToRect(tm.mat, llx, lly, urx, ury, llx, lly, urx, ury);
			GfxMatrix.ApplyToDist(tm.mat, shape.bw, bw)
		END
	END GetShapeBox;
	
	
	(**--- Figure Updates ---**)
	
	PROCEDURE UpdateFigure (fig: Figure);
		VAR um: UpdateMsg;
	BEGIN
		um.F := NIL; um.fig := fig; um.reg := fig.damage; um.bw := -SHORT(ENTIER(fig.border));
		Display.Broadcast(um);
		GfxRegions.Clear(fig.damage);
		fig.border := 0
	END UpdateFigure;
	
	PROCEDURE DisableUpdate* (fig: Figure);
	BEGIN
		INC(fig.lockLevel)
	END DisableUpdate;
	
	PROCEDURE EnableUpdate* (fig: Figure);
	BEGIN
		DEC(fig.lockLevel);
		IF (fig.lockLevel = 0) & ~GfxRegions.Empty(fig.damage) THEN
			UpdateFigure(fig)
		END
	END EnableUpdate;
	
	PROCEDURE UpdateRect* (fig: Figure; llx, lly, urx, ury, bw: REAL);
		VAR llu, llv, uru, urv: INTEGER;
	BEGIN
		llu := SHORT(ENTIER(llx)); llv := SHORT(ENTIER(lly));
		uru := -SHORT(ENTIER(-urx)); urv := -SHORT(ENTIER(-ury));
		IF fig.lockLevel > 0 THEN
			GfxRegions.AddRect(fig.damage, llu, llv, uru, urv);
			IF bw > fig.border THEN fig.border := bw END
		ELSE
			GfxRegions.SetToRect(fig.damage, llu, llv, uru, urv);
			fig.border := bw;
			UpdateFigure(fig)
		END
	END UpdateRect;
	
	
	(**--- Selection ---**)
	
	PROCEDURE GetSelection* (fig: Figure; VAR shapes: Shape);
		VAR sm: SelectMsg;
	BEGIN
		Objects.Stamp(sm); sm.fig := fig; sm.id := Get; sm.shapes := NIL;
		Forward(fig, fig.root, sm);
		shapes := sm.shapes
	END GetSelection;
	
	PROCEDURE Select* (fig: Figure; shapes: Shape);
		VAR sm: SelectMsg; obj: Objects.Object;
	BEGIN
		DisableUpdate(fig);
		sm.fig := fig; sm.id := Set;
		obj := shapes;
		WHILE obj # NIL DO
			obj.handle(obj, sm);
			obj := obj.slink
		END;
		fig.selTime := Oberon.Time();
		EnableUpdate(fig)
	END Select;
	
	PROCEDURE Deselect* (fig: Figure; shapes: Shape);
		VAR sm: SelectMsg; obj: Objects.Object;
	BEGIN
		DisableUpdate(fig);
		sm.fig := fig; sm.id := Reset;
		obj := shapes;
		WHILE obj # NIL DO
			obj.handle(obj, sm);
			obj := obj.slink
		END;
		fig.selTime := Oberon.Time();
		EnableUpdate(fig)
	END Deselect;
	
	PROCEDURE ClearSelection* (fig: Figure);
		VAR sm: SelectMsg;
	BEGIN
		DisableUpdate(fig);
		sm.fig := fig; sm.id := Reset;
		fig.root.handle(fig.root, sm);
		EnableUpdate(fig)
	END ClearSelection;
	
	
	(**--- Undoable Commands ---**)
	
	PROCEDURE InvertActions (cmd: Command);
		VAR cur, link: Action;
	BEGIN
		cur := cmd.actions; cmd.actions := NIL;
		WHILE cur # NIL DO
			link := cur.link; cur.link := cmd.actions; cmd.actions := cur; cur := link
		END
	END InvertActions;
	
	PROCEDURE CallActions (fig: Figure; cmd: Command; undo: BOOLEAN);
		VAR vm: ValidateMsg; cur: Action;
	BEGIN
		InvertActions(cmd);
		DisableUpdate(fig);
		ClearSelection(fig);
		Objects.Stamp(vm);
		cur := cmd.actions;
		WHILE cur # NIL DO
			cur.do(fig, cur, vm.stamp, undo);
			cur := cur.link
		END;
		vm.fig := fig;
		Forward(fig, fig.root, vm);
		EnableUpdate(fig)
	END CallActions;
	
	PROCEDURE AddAction* (fig: Figure; action: Action; do: ActionProc);
		VAR cmd: Command;
	BEGIN
		ASSERT(fig.cmdLevel > 0);
		action.do := do; action.link := NIL;
		cmd := fig.curCmd;
		IF cmd.last = NIL THEN cmd.actions := action ELSE cmd.last.link := action END;
		cmd.last := action
	END AddAction;
	
	PROCEDURE BeginCommand* (fig: Figure);
		VAR cmd: Command;
	BEGIN
		INC(fig.cmdLevel);
		IF (fig.cmdLevel = 1) & (fig.curCmd = NIL) THEN
			NEW(fig.curCmd)
		END
	END BeginCommand;
	
	PROCEDURE CancelCommand* (fig: Figure);
		VAR cmd: Command;
	BEGIN
		cmd := fig.curCmd;
		IF cmd.actions # NIL THEN
			IF cmd.done # NIL THEN
				cmd.done.link := NIL; cmd.last := cmd.done
			ELSE
				cmd.actions := NIL; cmd.last := NIL
			END
		END;
		IF (fig.cmdLevel = 1) & (cmd.actions # NIL) THEN
			CallActions(fig, cmd, TRUE);
			cmd.actions := NIL; cmd.done := NIL; cmd.last := NIL
		END;
		DEC(fig.cmdLevel)
	END CancelCommand;
	
	PROCEDURE EndCommand* (fig: Figure);
		VAR cmd: Command; vm: ValidateMsg; cur: Action;
	BEGIN
		cmd := fig.curCmd;
		IF cmd.actions # NIL THEN
			DisableUpdate(fig);
			Objects.Stamp(vm);
			IF cmd.done # NIL THEN cur := cmd.done.link ELSE cur := cmd.actions END;
			WHILE cur # NIL DO
				cur.do(fig, cur, vm.stamp, FALSE);
				cur := cur.link
			END;
			cmd.done := cmd.last;
			fig.selTime := Oberon.Time();
			vm.fig := fig;
			Forward(fig, fig.root, vm);
			IF fig.cmdLevel = 1 THEN
				fig.undoCmd.next := cmd; cmd.prev := fig.undoCmd; cmd.next := NIL;
				fig.undoCmd := cmd; fig.curCmd := NIL;
				IF fig.nofCmds = fig.maxCmds THEN fig.firstCmd := fig.firstCmd.next; fig.firstCmd.prev := NIL
				ELSE INC(fig.nofCmds)
				END
			END;
			EnableUpdate(fig)
		END;
		DEC(fig.cmdLevel)
	END EndCommand;
	
	PROCEDURE Undo* (fig: Figure);
		VAR cmd: Command;
	BEGIN
		cmd := fig.undoCmd;
		IF (fig.cmdLevel =  0) & (cmd.prev # NIL) THEN
			fig.undoCmd := cmd.prev;
			CallActions(fig, cmd, TRUE);
			DEC(fig.nofCmds)
		END
	END Undo;
	
	PROCEDURE Redo* (fig: Figure);
		VAR cmd: Command;
	BEGIN
		cmd := fig.undoCmd.next;
		IF (fig.cmdLevel =  0) & (cmd # NIL) THEN
			fig.undoCmd := cmd;
			CallActions(fig, cmd, FALSE);
			INC(fig.nofCmds)
		END
	END Redo;
	
	
	(**--- Locating ---**)
	
	PROCEDURE ProjectToHandles* (shape: Shape; VAR lm: LocateMsg; llx, lly, urx, ury: REAL);
		VAR mx, my: REAL;
	BEGIN
		mx := 0.5*(llx + urx); my := 0.5*(lly + ury);
		IF (lm.llx <= mx) & (mx <= lm.urx) THEN
			IF (lm.lly <= my) & (my <= lm.ury) THEN lm.px := mx; lm.py := my; lm.shapes := shape
			ELSIF (lm.lly <= lly) & (lly <= lm.ury) THEN lm.px := mx; lm.py := lly; lm.shapes := shape
			ELSIF (lm.lly <= ury) & (ury <= lm.ury) THEN lm.px := mx; lm.py := ury; lm.shapes := shape
			END
		ELSIF (lm.llx <= llx) & (llx <= lm.urx) THEN
			IF (lm.lly <= my) & (my <= lm.ury) THEN lm.px := llx; lm.py := my; lm.shapes := shape
			ELSIF (lm.lly <= lly) & (lly <= lm.ury) THEN lm.px := llx; lm.py := lly; lm.shapes := shape
			ELSIF (lm.lly <= ury) & (ury <= lm.ury) THEN lm.px := llx; lm.py := ury; lm.shapes := shape
			END
		ELSIF (lm.llx <= urx) & (urx <= lm.urx) THEN
			IF (lm.lly <= my) & (my <= lm.ury) THEN lm.px := urx; lm.py := my; lm.shapes := shape
			ELSIF (lm.lly <= lly) & (lly <= lm.ury) THEN lm.px := urx; lm.py := lly; lm.shapes := shape
			ELSIF (lm.lly <= ury) & (ury <= lm.ury) THEN lm.px := urx; lm.py := ury; lm.shapes := shape
			END
		END
	END ProjectToHandles;
	
	
	(**--- Rendering ---**)
	
	(** render figure on given context **)
	PROCEDURE Render* (fig: Figure; id: INTEGER; ctxt: Gfx.Context);
		VAR dm: DrawMsg; ctm, inv: GfxMatrix.Matrix;
	BEGIN
		Objects.Stamp(dm); dm.dlink := NIL; dm.fig := fig; dm.id := id; dm.all := TRUE; dm.ctxt := ctxt;
		ctm := ctxt.ctm;
		Gfx.ResetCTM(ctxt);
		GfxMatrix.Invert(ctm, inv);
		GfxMatrix.Concat(inv, ctxt.ctm, dm.mat);
		Gfx.SetCTM(ctxt, ctm);
		Forward(fig, fig.root, dm)
	END Render;
	
	PROCEDURE DrawHandles* (VAR dm: DrawMsg; llx, lly, urx, ury: REAL);
		VAR ctm, mat: GfxMatrix.Matrix; col: Gfx.Color; mx, my: REAL;
		
		PROCEDURE draw (x, y: REAL);
		BEGIN
			GfxMatrix.Apply(mat, x, y, x, y);
			Gfx.DrawRect(dm.ctxt, x-2, y-2, x+2, y+2, {Gfx.Fill})
		END draw;
		
	BEGIN
		ctm := dm.ctxt.ctm; col := dm.ctxt.fillCol;
		Gfx.ResetCTM(dm.ctxt);
		GfxMatrix.Invert(dm.ctxt.ctm, mat);
		GfxMatrix.Concat(ctm, mat, mat);	(* mat now maps from local to default context coords *)
		Gfx.SetFillColor(dm.ctxt, Gfx.DGrey);
		mx := 0.5*(llx + urx); my := 0.5*(lly + ury);
		draw(llx, ury); draw(mx, ury); draw(urx, ury);
		draw(llx, my); draw(urx, my);
		draw(llx, lly); draw(mx, lly); draw(urx, lly);
		Gfx.SetFillColor(dm.ctxt, col);
		Gfx.SetCTM(dm.ctxt, ctm)
	END DrawHandles;
	
	
	(**--- Control ---**)
	
	PROCEDURE Integrate* (fig: Figure; target, shapes: Shape);
		VAR cm: ControlMsg;
	BEGIN
		cm.fig := fig; cm.id := Consume; cm.dest := target; cm.shapes := shapes;
		BeginCommand(fig);
		Forward(fig, fig.root, cm);
		EndCommand(fig)
	END Integrate;
	
	PROCEDURE Delete* (fig: Figure; shapes: Shape);
		VAR cm: ControlMsg; obj: Objects.Object;
	BEGIN
		Objects.Stamp(cm); cm.fig := fig; cm.id := Remove;
		obj := shapes;
		WHILE obj # NIL DO
			obj.stamp := cm.stamp; obj := obj.slink
		END;
		BeginCommand(fig);
		Forward(fig, fig.root, cm);
		EndCommand(fig)
	END Delete;
	
	
	(**--- Transformations ---**)
	
	PROCEDURE SuggestHandleTrafo* (VAR tm: TransformMsg; llx, lly, urx, ury: REAL);
		CONST tol = 0.1;
		VAR x0, y0: REAL;
	BEGIN
		IF (llx < urx) & (lly < ury) THEN
			x0 := (tm.x0 - llx)/(urx - llx); y0 := (tm.y0 - lly)/(ury - lly);
			IF (-tol <= x0) & (x0 <= tol) THEN
				IF (-tol <= y0) & (y0 <= tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, urx, ury, (tm.x1 - urx)/(tm.x0 - urx), (tm.y1 - ury)/(tm.y0 - ury), tm.mat)
				ELSIF (1-tol <= y0) & (y0 <= 1+tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, urx, lly, (tm.x1 - urx)/(tm.x0 - urx), (tm.y1 - lly)/(tm.y0 - lly), tm.mat)
				ELSIF (0.5-tol <= y0) & (y0 <= 0.5+tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, urx, 0.5*(lly + ury), (tm.x1 - urx)/(tm.x0 - urx), 1, tm.mat)
				ELSE
					GfxMatrix.Translate(GfxMatrix.Identity, tm.x1 - tm.x0, tm.y1 - tm.y0, tm.mat)
				END
			ELSIF (1-tol <= x0) & (x0 <= 1+tol) THEN
				IF (-tol <= y0) & (y0 <= tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, llx, ury, (tm.x1 - llx)/(tm.x0 - llx), (tm.y1 - ury)/(tm.y0 - ury), tm.mat)
				ELSIF (1-tol <= y0) & (y0 <= 1+tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, llx, lly, (tm.x1 - llx)/(tm.x0 - llx), (tm.y1 - lly)/(tm.y0 - lly), tm.mat)
				ELSIF (0.5-tol <= y0) & (y0 <= 0.5+tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, llx, 0.5*(lly + ury), (tm.x1 - llx)/(tm.x0 - llx), 1, tm.mat)
				ELSE
					GfxMatrix.Translate(GfxMatrix.Identity, tm.x1 - tm.x0, tm.y1 - tm.y0, tm.mat)
				END
			ELSIF (0.5-tol <= x0) & (x0 <= 0.5+tol) THEN
				IF (-tol <= y0) & (y0 <= tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, 0.5*(llx + urx), ury, 1, (tm.y1 - ury)/(tm.y0 - ury), tm.mat)
				ELSIF (1-tol <= y0) & (y0 <= 1+tol) THEN
					GfxMatrix.ScaleAt(GfxMatrix.Identity, 0.5*(llx + urx), lly, 1, (tm.y1 - lly)/(tm.y0 - lly), tm.mat)
				ELSE
					GfxMatrix.Translate(GfxMatrix.Identity, tm.x1 - tm.x0, tm.y1 - tm.y0, tm.mat)
				END
			ELSE GfxMatrix.Translate(GfxMatrix.Identity, tm.x1 - tm.x0, tm.y1 - tm.y0, tm.mat)
			END
		END
	END SuggestHandleTrafo;
	
	PROCEDURE ComputeTrafo* (fig: Figure; shapes: Shape; VAR mat: GfxMatrix.Matrix);
		VAR tm: TransformMsg; obj: Objects.Object;
	BEGIN
		Solver.Init;
		Objects.Stamp(tm); tm.fig := fig; tm.id := Apply; tm.mat := mat;
		obj := shapes;
		WHILE obj # NIL DO
			obj.stamp := tm.stamp; obj := obj.slink
		END;
		fig.handle(fig, tm);
		Solver.Solve
	END ComputeTrafo;
	
	PROCEDURE DoAttrAction (fig: Figure; act: Action; stamp: LONGINT; undo: BOOLEAN);
		VAR obj: Objects.Object; sm: SelectMsg;
	BEGIN
		obj := act(AttrAction).obj;
		IF obj IS Shape THEN
			Solver.ApplyAttr(obj, act(AttrAction).attr);
			obj.stamp := stamp;	(* make sure that new position is updated during validate phase *)
			sm.fig := fig; sm.id := Set;
			obj.handle(obj, sm)
		END
	END DoAttrAction;
	
	PROCEDURE CommitTrafo* (fig: Figure);
		VAR id: LONGINT; obj: Objects.Object; attr: Solver.AttrNode; act: AttrAction;
	BEGIN
		BeginCommand(fig);
		id := 0; Solver.GetObject(0, obj, attr);
		WHILE obj # NIL DO
			NEW(act); act.obj := obj; act.attr := attr;
			AddAction(fig, act, DoAttrAction);
			INC(id); Solver.GetObject(id, obj, attr)
		END;
		EndCommand(fig)
	END CommitTrafo;
	
	PROCEDURE Transform* (fig: Figure; shapes: Shape; VAR mat: GfxMatrix.Matrix);
	BEGIN
		ComputeTrafo(fig, shapes, mat);
		CommitTrafo(fig)
	END Transform;
	
	
	(**--- Shapes ---**)
	
	(** return whether shape is present in a linked list of shapes **)
	PROCEDURE InList* (shape, list: Shape): BOOLEAN;
		VAR obj: Objects.Object;
	BEGIN
		obj := list;
		WHILE obj # NIL DO
			IF shape = obj THEN RETURN TRUE END;
			obj := obj.slink
		END;
		RETURN FALSE
	END InList;
	
	(** update figure within shape box **)
	PROCEDURE UpdateShapeRect* (shape: Shape; fig: Figure; VAR mat: GfxMatrix.Matrix);
		VAR llx, lly, urx, ury, bw: REAL;
	BEGIN
		GfxMatrix.ApplyToRect(mat, shape.llx, shape.lly, shape.urx, shape.ury, llx, lly, urx, ury);
		GfxMatrix.ApplyToDist(mat, shape.bw, bw);
		UpdateRect(fig, llx, lly, urx, ury, bw)
	END UpdateShapeRect;
	
	(** copy shape contents **)
	PROCEDURE CopyShape* (VAR msg: Objects.CopyMsg; from, to: Shape);
	BEGIN
		to.handle := from.handle;
		to.llx := from.llx; to.lly := from.lly; to.urx := from.urx; to.ury := from.ury;
		to.bw := from.bw
	END CopyShape;
	
	(** default message handler for shapes **)
	PROCEDURE HandleShape* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR shape: Shape; llx, lly, urx, ury, bw, rdummy: REAL; ver: LONGINT; idummy: INTEGER;
	BEGIN
		shape := obj(Shape);
		IF msg IS ShapeMsg THEN
			WITH msg: ShapeMsg DO
				IF msg IS SelectMsg THEN
					WITH msg: SelectMsg DO
						IF (msg.id = Get) & shape.sel & (msg.stamp # shape.stamp) THEN
							shape.slink := msg.shapes; msg.shapes := shape; shape.stamp := msg.stamp
						ELSIF (msg.id = Set) & ~shape.sel THEN
							shape.sel := TRUE;
							GetShapeBox(shape, llx, lly, urx, ury, bw);
							UpdateRect(msg.fig, llx, lly, urx, ury, bw);
							Forward(shape, shape.cont, msg)
						ELSIF (msg.id = Reset) & shape.sel THEN
							shape.sel := FALSE;
							GetShapeBox(shape, llx, lly, urx, ury, bw);
							UpdateRect(msg.fig, llx, lly, urx, ury, bw)
						END
					END
				ELSIF (msg IS ValidateMsg) & (msg.stamp = shape.stamp) THEN
					WITH msg: ValidateMsg DO
						UpdateShapeRect(shape, msg.fig, msg.mat);
						IF shape.cont # NIL THEN shape.cont.stamp := msg.stamp END
					END
				ELSIF (msg IS TransformMsg) & (msg(TransformMsg).id = Get) THEN
					shape.cont.handle(shape.cont, msg)
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleBoolAttr(msg(Objects.AttrMsg), "Selected", shape.sel)
		ELSIF msg IS Objects.BindMsg THEN
			Gadgets.BindObj(shape, msg(Objects.BindMsg).lib)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Files.ReadInt(msg.R, idummy); Files.ReadInt(msg.R, idummy);
						Files.ReadInt(msg.R, idummy); Files.ReadInt(msg.R, idummy);
						Files.ReadReal(msg.R, rdummy)
					ELSIF ver = 2 THEN
						(* nothing stored *)
					END
				END
			END
		END
	END HandleShape;
	
	(** initialize shape **)
	PROCEDURE InitShape* (shape: Shape);
	BEGIN
		shape.handle := HandleShape; shape.cont := NIL; shape.sel := FALSE;
		shape.llx := MAX(REAL); shape.lly := MAX(REAL); shape.urx := MIN(REAL); shape.ury := MIN(REAL);
		shape.bw := 0
	END InitShape;
	
	(** copy linked list of shapes **)
	PROCEDURE CopyShapes* (shapes: Shape; VAR copies: Shape);
		VAR obj, cur: Objects.Object; cm: Objects.CopyMsg;
	BEGIN
		obj := shapes; copies := NIL;
		IF obj # NIL THEN
			Objects.Stamp(cm); cm.dlink := NIL; cm.id := Objects.shallow; cm.obj := NIL;
			obj.handle(obj, cm);
			copies := cm.obj(Shape); cur := copies;
			WHILE obj.slink # NIL DO
				obj := obj.slink;
				cm.obj := NIL;
				obj.handle(obj, cm);
				cur.slink := cm.obj;
				cur := cur.slink
			END;
			cur.slink := NIL
		END
	END CopyShapes;
	
	
	(**--- References ---**)
	
	(** build list of references from linked list of shapes **)
	PROCEDURE MakeRefs* (shapes: Shape; VAR first, last: Reference);
		VAR obj: Objects.Object;
	BEGIN
		IF shapes = NIL THEN
			first := NIL; last := NIL
		ELSE
			NEW(first); last := first; last.shape := shapes;
			obj := shapes.slink;
			WHILE obj # NIL DO
				NEW(last.next); last.next.prev := last; last := last.next;
				last.shape := obj(Shape);
				obj := obj.slink
			END
		END
	END MakeRefs;
	
	(** store list of references to file **)
	PROCEDURE WriteRefs* (VAR r: Files.Rider; lib: Objects.Library; first: Reference);
	BEGIN
		WHILE first # NIL DO
			Gadgets.WriteRef(r, lib, first.shape);
			first := first.next
		END;
		Gadgets.WriteRef(r, lib, NIL)
	END WriteRefs;
	
	(** load list of references from file **)
	PROCEDURE ReadRefs* (VAR r: Files.Rider; lib: Objects.Library; VAR first, last: Reference);
		VAR obj: Objects.Object; cur: Reference;
	BEGIN
		first := NIL; last := NIL;
		Gadgets.ReadRef(r, lib, obj);
		IF obj # NIL THEN
			NEW(first); cur := first;
			REPEAT
				IF (obj # NIL) & (obj IS Shape) THEN cur.shape := obj(Shape) ELSE cur.shape := Dummy END;
				Gadgets.ReadRef(r, lib, obj);
				IF obj # NIL THEN
					NEW(cur.next); cur.next.prev := cur;
					cur := cur.next
				END
			UNTIL obj = NIL;
			last := cur
		END
	END ReadRefs;
	
	(** copy a list of shape references **)
	PROCEDURE CopyRefs* (VAR msg: Objects.CopyMsg; from: Reference; VAR to, last: Reference);
		VAR cm: Objects.CopyMsg; fref, tref: Reference;
	BEGIN
		to := NIL; last := NIL;
		IF from # NIL THEN
			cm.stamp := msg.stamp; cm.dlink := NIL; cm.id := msg.id;
			fref := from;
			NEW(to); tref := to;
			LOOP
				fref.shape.handle(fref.shape, cm);
				tref.shape := cm.obj(Shape);
				fref := fref.next;
				IF fref = NIL THEN EXIT END;
				NEW(tref.next); tref.next.prev := tref;
				tref := tref.next
			END;
			last := tref
		END
	END CopyRefs;
	
	(** forward message to list of shape references, starting with first reference **)
	PROCEDURE HandleRefs* (cont: Container; VAR msg: Objects.ObjMsg);
		VAR clink, mlink: Objects.Object; ref: Reference;
	BEGIN
		clink := cont.dlink; mlink := msg.dlink;
		cont.dlink := mlink; msg.dlink := cont;
		ref := cont.first;
		WHILE ref # NIL DO
			ref.shape.handle(ref.shape, msg);
			ref := ref.next
		END;
		cont.dlink := clink; msg.dlink := mlink
	END HandleRefs;
	
	
	(**--- Containers ---**)
	
	PROCEDURE ValidateContainer* (cont: Container);
		VAR ref: Reference; s: Shape;
	BEGIN
		cont.llx := MAX(REAL); cont.lly := MAX(REAL); cont.urx := MIN(REAL); cont.ury := MIN(REAL); cont.bw := 0;
		ref := cont.first;
		WHILE ref # NIL DO
			s := ref.shape;
			IF s.llx < cont.llx THEN cont.llx := s.llx END;
			IF s.lly < cont.lly THEN cont.lly := s.lly END;
			IF s.urx > cont.urx THEN cont.urx := s.urx END;
			IF s.ury > cont.ury THEN cont.ury := s.ury END;
			IF s.bw > cont.bw THEN cont.bw := s.bw END;
			ref := ref.next
		END
	END ValidateContainer;
	
	PROCEDURE SelectContainer (cont: Container; VAR sm: SelectMsg);
		VAR shapes: Shape; ref: Reference;
	BEGIN
		IF (sm.id = Get) & cont.sel & (sm.stamp # cont.stamp) THEN
			cont.stamp := sm.stamp;
			shapes := sm.shapes;
			ref := cont.last;
			WHILE ref # NIL DO	(* handle shapes top-to-bottom to get correct order *)
				Forward(cont, ref.shape, sm);
				ref := ref.prev
			END;
			IF sm.shapes = shapes THEN	(* no component is selected *)
				cont.slink := shapes; sm.shapes := cont
			END
		ELSIF (sm.id = Reset) & cont.sel THEN
			HandleRefs(cont, sm);
			HandleShape(cont, sm)
		ELSE
			HandleShape(cont, sm)
		END
	END SelectContainer;
	
	PROCEDURE LocateContainer (cont: Container; VAR lm: LocateMsg);
		VAR shapes: Shape;
	BEGIN
		IF (lm.llx <= cont.urx) & (cont.llx <= lm.urx) & (lm.lly <= cont.ury) & (cont.lly <= lm.ury) & (lm.stamp # cont.stamp) THEN
			cont.stamp := lm.stamp;
			IF lm.id = Inside THEN
				IF (lm.llx <= cont.llx) & (cont.urx <= lm.urx) & (lm.lly <= cont.lly) & (cont.ury <= lm.ury) THEN
					cont.slink := lm.shapes; lm.shapes := cont
				ELSE
					HandleRefs(cont, lm)
				END
			ELSIF lm.id = Overlap THEN
				shapes := lm.shapes;
				HandleRefs(cont, lm);
				IF (lm.shapes # shapes) & ~cont.sel THEN	(* can only locate components if container is selected *)
					lm.shapes := cont; cont.slink := NIL
				END
			ELSIF lm.id = Project THEN
				ProjectToHandles(cont, lm, cont.llx, cont.lly, cont.urx, cont.ury);
				HandleRefs(cont, lm)
			END
		ELSE
			HandleRefs(cont, lm)
		END
	END LocateContainer;
	
	PROCEDURE DrawContainer (cont: Container; VAR dm: DrawMsg);
	BEGIN
		IF ~dm.all OR (dm.stamp # cont.stamp) THEN
			IF dm.all THEN cont.stamp := dm.stamp END;
			IF (dm.llx <= cont.urx + cont.bw) & (cont.llx - cont.bw <= dm.urx) &
				(dm.lly <= cont.ury + cont.bw) & (cont.lly - cont.bw <= dm.ury)
			THEN
				IF (dm.id = Full) & cont.sel & (dm.stamp = cont.stamp) THEN
					DrawHandles(dm, cont.llx, cont.lly, cont.urx, cont.ury)
				END;
				HandleRefs(cont, dm)
			END
		END
	END DrawContainer;
	
	PROCEDURE DoControlAction* (fig: Figure; act: Action; stamp: LONGINT; undo: BOOLEAN);
		VAR ctrl: ControlAction; ref: Reference; sm: SelectMsg; llx, lly, urx, ury, bw: REAL;
	BEGIN
		ctrl := act(ControlAction);
		IF ~undo & (ctrl.id = Consume) OR undo & (ctrl.id = Remove) THEN
			ctrl.first.prev := ctrl.prev; ctrl.last.next := ctrl.next;
			IF ctrl.prev # NIL THEN ctrl.prev.next := ctrl.first ELSE ctrl.cont.first := ctrl.first END;
			IF ctrl.next # NIL THEN ctrl.next.prev := ctrl.last ELSE ctrl.cont.last := ctrl.last END;
			ref := ctrl.first; sm.fig := fig; sm.id := Set;
			REPEAT
				ref.shape.cont := ctrl.cont; ref.shape.stamp := stamp;
				ref.shape.handle(ref.shape, sm);
				ref := ref.next
			UNTIL ref = ctrl.next
		ELSIF ~undo & (ctrl.id = Remove) OR undo & (ctrl.id = Consume) THEN
			ctrl.first.prev := NIL; ctrl.last.next := NIL;
			IF ctrl.prev # NIL THEN ctrl.prev.next := ctrl.next ELSE ctrl.cont.first := ctrl.next END;
			IF ctrl.next # NIL THEN ctrl.next.prev := ctrl.prev ELSE ctrl.cont.last := ctrl.prev END;
			ref := ctrl.first; sm.fig := fig; sm.id := Reset;
			REPEAT
				IF ref.shape.cont # NIL THEN	(* may be NIL if already removed by previous action *)
					IF ref.shape.sel THEN
						ref.shape.handle(ref.shape, sm)
					ELSE
						GetShapeBox(ref.shape, llx, lly, urx, ury, bw);
						UpdateRect(fig, llx, lly, urx, ury, bw)
					END
				END;
				ref.shape.cont := NIL; ref := ref.next
			UNTIL ref = NIL;
			sm.fig := fig; sm.id := Set;
			ctrl.cont.handle(ctrl.cont, sm);
			ctrl.cont.stamp := stamp
		END
	END DoControlAction;
	
	PROCEDURE InitControlAction* (act: ControlAction; id: INTEGER; prev, first, last, next: Reference; cont: Container);
	BEGIN
		act.id := id;
		act.prev := prev; act.first := first; act.last := last; act.next := next;
		act.cont := cont
	END InitControlAction;
	
	PROCEDURE AddControlAction (fig: Figure; id: INTEGER; prev, first, last, next: Reference; cont: Container);
		VAR act: ControlAction;
	BEGIN
		NEW(act); InitControlAction(act, id, prev, first, last, next, cont);
		AddAction(fig, act, DoControlAction)
	END AddControlAction;
	
	PROCEDURE ControlContainer (cont: Container; VAR cm: ControlMsg);
		VAR first, last, ref: Reference;
	BEGIN
		IF cm.id = Consume THEN
			IF cont = cm.dest THEN
				MakeRefs(cm.shapes, first, last);
				ref := first;
				WHILE (ref # NIL) & (ref.shape.cont = NIL) DO ref := ref.next END;
				IF ref # NIL THEN
					Delete(cm.fig, cm.shapes)	(* delete shapes from whereever they are now *)
				END;
				AddControlAction(cm.fig, Consume, cont.last, first, last, NIL, cont)
			ELSE
				HandleRefs(cont, cm)
			END
		ELSIF cm.id = Remove THEN
			HandleRefs(cont, cm);
			first := cont.first;
			WHILE first # NIL DO
				IF first.shape.stamp = cm.stamp THEN
					last := first;
					WHILE (last # cont.last) & (last.next.shape.stamp = cm.stamp) DO last := last.next END;
					AddControlAction(cm.fig, Remove, first.prev, first, last, last.next, cont);
					first := last.next
				ELSE
					first := first.next
				END
			END
		END
	END ControlContainer;
	
	PROCEDURE ShuffleContainer (cont: Container; VAR pm: PriorityMsg);
		VAR first, last, next: Reference;
		
		PROCEDURE affected (shape: Shape): BOOLEAN;
			VAR sm: SelectMsg;
		BEGIN
			IF shape.sel THEN
				Objects.Stamp(sm); sm.id := Get; sm.shapes := NIL;
				shape.handle(shape, sm);
				RETURN sm.shapes = shape
			ELSE
				RETURN FALSE
			END
		END affected;
		
	BEGIN
		HandleRefs(cont, pm);
		IF cont.sel THEN
			first := cont.first;
			WHILE (first # NIL) & ~affected(first.shape) DO first := first.next END;
			WHILE first # NIL DO
				last := first; next := last;
				WHILE (last.next # NIL) & affected(last.next.shape) DO last := last.next END;
				IF (pm.id = Up) & (last.next # NIL) THEN
					BeginCommand(pm.fig);
					AddControlAction(pm.fig, Remove, first.prev, first, last, last.next, cont);
					AddControlAction(pm.fig, Consume, last.next, first, last, last.next.next, cont);
					EndCommand(pm.fig);
					next := last
				ELSIF (pm.id = Down) & (first.prev # NIL) THEN
					next := first.prev;
					BeginCommand(pm.fig);
					AddControlAction(pm.fig, Remove, first.prev, first, last, last.next, cont);
					AddControlAction(pm.fig, Consume, first.prev.prev, first, last, first.prev, cont);
					EndCommand(pm.fig)
				ELSIF (pm.id = Top) & (last.next # NIL) THEN
					next := last.next;
					BeginCommand(pm.fig);
					AddControlAction(pm.fig, Remove, first.prev, first, last, last.next, cont);
					AddControlAction(pm.fig, Consume, cont.last, first, last, NIL, cont);
					EndCommand(pm.fig)
				ELSIF (pm.id = Bottom) & (first.prev # NIL) THEN
					next := first.prev;
					BeginCommand(pm.fig);
					AddControlAction(pm.fig, Remove, first.prev, first, last, last.next, cont);
					AddControlAction(pm.fig, Consume, NIL, first, last, cont.first, cont);
					EndCommand(pm.fig)
				ELSIF pm.id = Reverse THEN
					IF last.next # NIL THEN next := last.next END;
					WHILE (first # last) & (first.next # last) DO
						BeginCommand(pm.fig);
						AddControlAction(pm.fig, Remove, first.prev, first, first, first.next, cont);
						AddControlAction(pm.fig, Remove, last.prev, last, last, last.next, cont);
						AddControlAction(pm.fig, Consume, first.prev, last, last, first.next, cont);
						AddControlAction(pm.fig, Consume, last.prev, first, first, last.next, cont);
						first := first.next; last := last.prev;
						EndCommand(pm.fig)
					END;
					IF first.next = last THEN
						AddControlAction(pm.fig, Remove, first.prev, first, first, last, cont);
						AddControlAction(pm.fig, Consume, last, first, first, last.next, cont)
					END
				END;
				first := next;
				REPEAT first := first.next UNTIL (first = NIL) OR affected(first.shape)
			END
		END
	END ShuffleContainer;
	
	(** copy container shape **)
	PROCEDURE CopyContainer* (VAR msg: Objects.CopyMsg; from, to: Container);
		VAR ref: Reference;
	BEGIN
		CopyShape(msg, from, to);
		CopyRefs(msg, from.first, to.first, to.last);
		ref := to.first;
		WHILE ref # NIL DO
			ref.shape.cont := to; ref := ref.next
		END
	END CopyContainer;
	
	(** default handler for container shapes **)
	PROCEDURE HandleContainer* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR cont, copy: Container; ver: LONGINT; ref: Reference; am: Objects.AttrMsg; bdummy: BOOLEAN;
	BEGIN
		cont := obj(Container);
		IF msg IS ShapeMsg THEN
			IF msg IS SelectMsg THEN
				SelectContainer(cont, msg(SelectMsg))
			ELSIF msg IS LocateMsg THEN
				LocateContainer(cont, msg(LocateMsg))
			ELSIF msg IS DrawMsg THEN
				DrawContainer(cont, msg(DrawMsg))
			ELSIF msg IS ValidateMsg THEN
				HandleRefs(cont, msg);
				IF cont.stamp = msg.stamp THEN
					ValidateContainer(cont);
					IF cont.cont # NIL THEN cont.cont.stamp := msg.stamp END
				END
			ELSIF msg IS ControlMsg THEN
				ControlContainer(cont, msg(ControlMsg))
			ELSIF msg IS PriorityMsg THEN
				ShuffleContainer(cont, msg(PriorityMsg))
			ELSIF msg IS TransformMsg THEN
				IF msg(TransformMsg).id = Get THEN
					HandleShape(cont, msg)
				ELSE
					HandleRefs(cont, msg)
				END
			ELSE	(* unknown shape message is forwarded to components *)
				HandleRefs(cont, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleGenAttr(msg(Objects.AttrMsg), "Figures.NewContainer")
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # cont.stamp THEN
					NEW(copy); cont.dlink := copy; cont.stamp := msg.stamp;
					CopyContainer(msg, cont, copy)
				END;
				msg.obj := cont.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			HandleRefs(cont, msg);
			HandleShape(cont, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				HandleShape(cont, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					WriteRefs(msg.R, cont.lib, cont.first)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						ReadRefs(msg.R, cont.lib, cont.first, cont.last);
						ref := cont.first;
						WHILE ref # NIL DO
							IF (ref.shape = Dummy) OR (ref.shape.cont # NIL) THEN	(* shape not loaded or part of another shape *)
								am.id := Objects.get; am.name := "Gen"; am.res := -1;
								ref.shape.handle(ref.shape, am);
								IF am.s # "LeoPaths.NewPoint" THEN	(* probably shared point *)
									IF ref.prev = NIL THEN cont.first := ref.next ELSE ref.prev.next := ref.next END;
									IF ref.next = NIL THEN cont.last := ref.prev ELSE ref.next.prev := ref.prev END
								END
							ELSE
								ref.shape.cont := cont
							END;
							ref := ref.next
						END;
						ValidateContainer(cont)
					END;
					IF ver = 1 THEN
						Files.ReadBool(msg.R, bdummy)
					END
				END
			END
		ELSE
			HandleShape(cont, msg)
		END
	END HandleContainer;
	
	(** initialize empty container **)
	PROCEDURE InitContainer* (cont: Container);
	BEGIN
		InitShape(cont); cont.handle := HandleContainer;
		cont.first := NIL; cont.last := NIL
	END InitContainer;
	
	
	(**--- Groups ---**)
	
	PROCEDURE HandleGroup (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR group: Container; sm: SelectMsg; ref: Reference;
	BEGIN
		group := obj(Container);
		IF msg IS SelectMsg THEN
			WITH msg: SelectMsg DO
				IF msg.id = Set THEN
					HandleShape(group, msg);
					IF group.sel & (msg.dlink # NIL) & (msg.dlink IS Shape) & (msg.dlink(Shape).cont = group) THEN	(* ??? *)
						sm.id := Reset; sm.fig := msg.fig; sm.dlink := group;
						msg.dlink.handle(msg.dlink, sm)
					END
				ELSIF (msg.id = Reset) & group.sel THEN
					HandleContainer(group, msg)
				ELSE
					HandleShape(group, msg)
				END
			END
		ELSIF msg IS LocateMsg THEN
			WITH msg: LocateMsg DO
				IF msg.stamp # group.stamp THEN
					group.stamp := msg.stamp;
					IF (msg.id = Inside) & (msg.llx <= group.llx) & (group.urx <= msg.urx) & (msg.lly <= group.lly) & (group.ury <= msg.ury) THEN
						group.slink := msg.shapes; msg.shapes := group
					ELSIF (msg.id = Overlap) & (msg.llx <= group.urx) & (group.llx <= msg.urx) & (msg.lly <= group.ury) & (group.lly <= msg.ury) THEN
						group.slink := msg.shapes; msg.shapes := group
					ELSE
						HandleContainer(group, msg)
					END
				END
			END
		ELSIF msg IS ValidateMsg THEN
			HandleRefs(group, msg);
			IF group.stamp = msg.stamp THEN
				WITH msg: ValidateMsg DO
					UpdateShapeRect(group, msg.fig, msg.mat);
					ValidateContainer(group);
					UpdateShapeRect(group, msg.fig, msg.mat);
					group.cont.stamp := msg.stamp
				END
			END
		ELSIF msg IS TransformMsg THEN
			WITH msg: TransformMsg DO
				IF (msg.id = Apply) & (msg.stamp = group.stamp) THEN
					ref := group.first;
					WHILE ref # NIL DO
						ref.shape.stamp := msg.stamp; ref := ref.next
					END
				END;
				IF msg.id = Suggest THEN
					SuggestHandleTrafo(msg, group.llx, group.lly, group.urx, group.ury)
				ELSE
					HandleContainer(group, msg)
				END
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleGenAttr(msg(Objects.AttrMsg), "Figures.NewGroup")
		ELSE
			HandleContainer(group, msg)
		END
	END HandleGroup;
	
	PROCEDURE InitGroup* (group: Container; first, last: Reference);
	BEGIN
		InitShape(group);
		group.handle := HandleGroup;
		group.first := first; group.last := last;
		WHILE first # NIL DO
			first.shape.cont := group; first := first.next
		END
	END InitGroup;
	
	PROCEDURE NewGroup*;
		VAR group: Container;
	BEGIN
		NEW(group); InitGroup(group, NIL, NIL);
		Objects.NewObj := group
	END NewGroup;
	
	
	(**--- Root Container ---**)
	
	PROCEDURE HandleRoot (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR root: Container;
	BEGIN
		root := obj(Container);
		IF msg IS ShapeMsg THEN
			IF (msg IS SelectMsg) & (msg(SelectMsg).id IN {Get, Reset}) THEN
				HandleRefs(root, msg)
			ELSIF msg IS LocateMsg THEN
				HandleRefs(root, msg)
			ELSIF msg IS DrawMsg THEN
				WITH msg: DrawMsg DO
					Gfx.GetClipRect(msg.ctxt, msg.llx, msg.lly, msg.urx, msg.ury);
					HandleRefs(root, msg)
				END
			ELSIF msg IS ValidateMsg THEN
				msg(ValidateMsg).mat := GfxMatrix.Identity;
				HandleContainer(root, msg)
			ELSIF msg IS TransformMsg THEN
				WITH msg: TransformMsg DO
					IF msg.id = Get THEN
						msg.mat := GfxMatrix.Identity
					ELSE
						HandleContainer(root, msg)
					END
				END
			ELSE
				HandleContainer(root, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleGenAttr(msg(Objects.AttrMsg), "Figures.NewRoot")
		ELSE
			HandleContainer(root, msg)
		END
	END HandleRoot;
	
	PROCEDURE InitRoot (root: Container);
	BEGIN
		InitContainer(root);
		root.handle := HandleRoot; root.cont := root
	END InitRoot;
	
	PROCEDURE NewRoot*;
		VAR root: Container;
	BEGIN
		NEW(root); InitRoot(root);
		Objects.NewObj := root
	END NewRoot;

	
	(**--- Figures ---**)
	
	PROCEDURE InitFigure (fig: Figure; width, height: REAL);
	BEGIN
		fig.selTime := MIN(LONGINT);
		fig.width := width; fig.height := height;
		NEW(fig.damage); GfxRegions.Init(fig.damage, GfxRegions.Winding);
		fig.border := 0;
		fig.lockLevel := 0;
		fig.cmdLevel := 0;
		NEW(fig.undoCmd);
		fig.firstCmd := fig.undoCmd;
		fig.maxCmds := MaxCommands; fig.nofCmds := 0
	END InitFigure;
	
	PROCEDURE Copy* (VAR msg: Objects.CopyMsg; from, to: Figure);
	BEGIN
		to.handle := from.handle;
		InitFigure(to, from.width, from.height);
		NEW(to.root); CopyContainer(msg, from.root, to.root);
		to.maxCmds := from.maxCmds
	END Copy;
	
	PROCEDURE Write* (VAR r: Files.Rider; fig: Figure);
		VAR bm: Objects.BindMsg; len: LONGINT;
	BEGIN
		Files.WriteNum(r, 2);
		NEW(bm.lib); Objects.OpenLibrary(bm.lib);
		Forward(fig, fig.root, bm);
		Files.WriteInt(r, fig.root.ref);
		Objects.StoreLibrary(bm.lib, Files.Base(r), Files.Pos(r), len);
		Files.Set(r, Files.Base(r), Files.Pos(r) + len);
		Files.WriteInt(r, fig.maxCmds);
		Files.WriteReal(r, fig.width); Files.WriteReal(r, fig.height)
	END Write;
	
	PROCEDURE Read* (VAR r: Files.Rider; fig: Figure);
		VAR ver, len: LONGINT; ref: INTEGER; id: CHAR; lib: Objects.Library; obj: Objects.Object;
	BEGIN
		Files.ReadNum(r, ver);
		IF ver IN {1, 2} THEN
			Files.ReadInt(r, ref);
			Files.Read(r, id);
			NEW(lib); Objects.OpenLibrary(lib);
			Objects.LoadLibrary(lib, Files.Base(r), Files.Pos(r), len);
			Files.Set(r, Files.Base(r), Files.Pos(r) + len);
			lib.GetObj(lib, ref, obj);
			fig.root := obj(Container);
			IF ver = 2 THEN
				Files.ReadInt(r, fig.maxCmds);
				Files.ReadReal(r, fig.width); Files.ReadReal(r, fig.height)
			END
		END
	END Read;
	
	PROCEDURE Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR fig, copy: Figure;
	BEGIN
		fig := obj(Figure);
		IF msg IS ShapeMsg THEN
			msg(ShapeMsg).fig := fig;
			Forward(fig, fig.root, msg)
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				HandleGenAttr(msg, "Figures.New");
				HandleIntAttr(msg, "UndoLevel", fig.maxCmds, 1, MAX(INTEGER));
				HandleRealAttr(msg, "Width", fig.width);
				HandleRealAttr(msg, "Height", fig.height)
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # fig.stamp THEN
					NEW(copy); fig.dlink := copy; fig.stamp := msg.stamp;
					Copy(msg, fig, copy)
				END;
				msg.obj := fig.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			Gadgets.BindObj(fig, msg(Objects.BindMsg).lib)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				IF msg.id = Objects.store THEN
					Write(msg.R, fig)
				ELSIF msg.id = Objects.load THEN
					Read(msg.R, fig)
				END
			END
		END
	END Handle;
	
	(** initialize figure **)
	PROCEDURE Init* (fig: Figure; width, height: REAL);
	BEGIN
		fig.handle := Handle;
		InitFigure(fig, width, height);
		NEW(fig.root); InitRoot(fig.root)
	END Init;
	
	(** figure generator **)
	PROCEDURE New*;
		VAR fig: Figure;
	BEGIN
		NEW(fig); Init(fig, A4W, A4H);
		Objects.NewObj := fig
	END New;
	

BEGIN
	NEW(Dummy);
	InitShape(Dummy)
END Figures.
