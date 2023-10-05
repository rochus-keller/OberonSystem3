MODULE ColorWells;	(** eos   **)

(**
	Color wells are gadgets for visualizing a current color value. Unlike color pickers, they support a model object
	and have drag_and_drop capabilities.
**)

(*
	17.7.96 - Initial version
	23.7.96 - increased border width (suggested by ps)
	23.1.97 - eliminated Display.PrintMsg
	16.2.98 - made load more tolerant by allowing version numbers > 1
	27.3.98 - included color picker functionality when ML is pressed (procedure TrackColor)
	27.3.98 - added "TargetAttr" for selecting which attribute to change when drag-and-dropping (suggested by pm)
	6.5.98 - made MM+ML behaviour the same as ML alone to allow editing within document title bars
*)

	IMPORT
		Files, Objects, Display, Input, Printer, Oberon, Display3, Printer3, Effects, Gadgets, Views;
		
	CONST
		ML = 2; MM = 1; MR = 0;	(* mouse buttons *)
		
	TYPE
		ColorWell* = POINTER TO ColorWellDesc;
		ColorWellDesc* = RECORD (Gadgets.FrameDesc)
			col*: INTEGER;	(** current value **)
		END;
		
	VAR
		DragColor: Oberon.Marker;
		FGPattern, BGPattern: Display.Pattern;
	
	
	(*--- Drag Marker ---*)
	
	PROCEDURE DrawMarker (x, y: INTEGER);
	BEGIN
		DEC(x, 3); DEC(y);
		Effects.OpenCursor(x, y, 16, 17);
		Display.CopyPattern(Display3.white, BGPattern, x, y, Display.paint);
		Display.CopyPattern(Display3.black, FGPattern, x, y, Display.paint)
	END DrawMarker;
	
	PROCEDURE FadeMarker (x, y: INTEGER);
	BEGIN
		Effects.CloseCursor
	END FadeMarker;
	
	PROCEDURE InitMarker;
		VAR p: ARRAY 17 OF SET;
	BEGIN
		p[0] := {}; p[1] := {1, 2, 5, 6}; p[2] := {3, 4}; p[3] := {3, 4, 9, 10}; p[4] := {3, 4, 8, 11}; p[5] := {3, 4, 7, 12};
		p[6] := {3, 4, 6, 13}; p[7] := {3..5, 14}; p[8] := {3, 4, 9, 14}; p[9] := {3..5, 8, 10, 13}; p[10] := {4..6, 9, 12};
		p[11] := {6, 7, 9, 11, 13}; p[12] := {8..10, 12}; p[13] := {9, 12}; p[14] := {9, 12}; p[15] := {10, 11}; p[16] := {};
		FGPattern := Display.NewPattern(16, 17, p);
		p[0] := {1..6}; p[1] := {0..7}; p[2] := {2..5}; p[3] := {2..5, 8..11}; p[4] := {2..5, 7..12}; p[5] := {2..13};
		p[6] := {2..7, 12..14}; p[7] := {2..6, 13..15}; p[8] := {2..5, 8..10, 13..15}; p[9] := {2..14}; p[10] := {3..13};
		p[11] := {5..14}; p[12] := {7..13}; p[13] := {8..13}; p[14] := {8..13}; p[15] := {9..12}; p[16] := {10, 11};
		BGPattern := Display.NewPattern(16, 17, p);
		DragColor.Draw := DrawMarker; DragColor.Fade := FadeMarker
	END InitMarker;
	
	
	(*--- Color Wells ---*)
	
	PROCEDURE TrackColor (well: ColorWell; fx, fy: INTEGER; VAR msg: Oberon.InputMsg);
		CONST
			highlightCol = 0; borderCol = 15;
			border = 3; size = 6; ww = 16*size; hh = 16*size;
		
		VAR
			cx, cy, cw, ch: INTEGER; ctxt: Objects.Object; view: Gadgets.View;
			col, xx, yy, y, c, x, mx, my: INTEGER;
			block: Views.Block;
			keysum, keys: SET;
			am: Objects.AttrMsg;
		
		PROCEDURE frameCol (no, drawCol: INTEGER);
			VAR xc, yc: INTEGER;
		BEGIN
			IF no >= 0 THEN
				xc := xx + no MOD 16 * size;
				yc := yy + hh - (1 + no DIV 16) * size;
				Display3.Rect(block.mask, drawCol, Display.solid, xc, yc, size, size, 1, Display.replace)
			END
		END frameCol;
		
	BEGIN
		(* get clip rectangle *)
		cx := Display.ColLeft; cy := Display.Bottom; cw := Display.Width; ch := Display.Height;
		ctxt := msg.dlink;
		WHILE ctxt # NIL DO
			IF ctxt IS Gadgets.View THEN
				view := ctxt(Gadgets.View);
				IF cx < view.absX THEN DEC(cw, view.absX - cx); cx := view.absX END;
				IF cx + cw > view.absX + view.W THEN cw := view.absX + view.W - cx END;
				IF cy < view.absY THEN DEC(ch, view.absY - cy); cy := view.absY END;
				IF cy + ch > view.absY + view.H THEN ch := view.absY + view.H - cy END
			END;
			ctxt := ctxt.dlink
		END;
		
		(* calculate origin for color grid *)
		col := well.col;
		xx := msg.X - size DIV 2 - (col MOD 16) * size;
		yy := msg.Y - size DIV 2 - (15 - col DIV 16) * size;
		IF xx - border < cx THEN xx := cx + border
		ELSIF xx + ww + border > cx + cw THEN xx := cx + cw - ww - border
		END;
		IF yy - border < cy THEN yy := cy + border
		ELSIF yy + hh + border > cy + ch THEN yy := cy + ch - hh - border
		END;
		
		(* save area and draw color grid on top of it *)
		Oberon.RemoveMarks(xx - border, yy - border, ww + 2*border, hh + 2*border);
		Views.GetBlock(xx - border, yy - border, ww + 2*border, hh + 2*border, msg.dlink, block);
		y := yy + hh; c := 0;
		Display3.ReplConst(block.mask, borderCol, xx - border, y, ww + 2*border, border, Display.replace);
		Display3.ReplConst(block.mask, borderCol, xx - border, yy, border, hh, Display.replace);
		Display3.ReplConst(block.mask, borderCol, xx + ww, yy, border, hh, Display.replace);
		Display3.ReplConst(block.mask, borderCol, xx - border, yy - border, ww + 2*border, border, Display.replace);
		WHILE y > yy DO
			DEC(y, size); x := xx;
			WHILE x < xx + ww DO
				Display3.ReplConst(block.mask, c, x, y, size, size, Display.replace);
				INC(x, size); INC(c)
			END
		END;
		
		(* track and highlight color under mouse *)
		frameCol(col, highlightCol);
		mx := msg.X; my := msg.Y; keysum := msg.keys;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, mx, my);
		REPEAT
			Input.Mouse(keys, x, y);
			keysum := keysum + keys;
			IF (keys # {}) & ((x # mx) OR (y # my)) THEN
				IF Effects.Inside(x, y, xx, yy, ww, hh) THEN
					c := (yy + hh - 1 - y) DIV size * 16 + (x - xx) DIV size
				ELSE
					c := -1
				END;
				IF c # col THEN
					Oberon.FadeCursor(Oberon.Mouse);
					frameCol(col, col); frameCol(c, highlightCol);
					col := c
				END;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y);
				mx := x; my := y
			END
		UNTIL keys = {};
		Oberon.FadeCursor(Oberon.Mouse);
		frameCol(col, col);
		
		IF (keysum # {ML, MM, MR}) & (col >= 0) THEN
			well.col := col	(* set before restoring block *)
		END;
		Views.RestoreBlock(block);
		IF (keysum # {ML, MM, MR}) & (col >= 0) THEN	(* now make sure that model is updated *)
			am.id := Objects.set; am.name := "Color"; am.class := Objects.Int; am.i := col; am.res := -1;
			well.handle(well, am);
			Gadgets.Update(well)
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
	END TrackColor;
	
	PROCEDURE TrackMiddle (well: ColorWell; fx, fy: INTEGER; VAR msg: Oberon.InputMsg);
		VAR
			marker: Oberon.Marker; mask: Display3.Mask; keysum, keys: SET; x, y, u, v: INTEGER; frame: Display.Frame;
			am: Objects.AttrMsg;
	BEGIN
		marker := Effects.Arrow;
		Oberon.FadeCursor(Oberon.Mouse);
		Gadgets.MakeMask(well, fx, fy, msg.dlink, mask);
		Display3.Rect3D(mask, Display3.bottomC, Display3.topC, fx, fy, well.W, well.H, 1, Display.replace);
		keysum := msg.keys;
		Input.Mouse(keys, x, y);
		Oberon.DrawCursor(Oberon.Mouse, marker, x, y);
		WHILE (keys # {}) & (keysum # {ML, MM}) DO
			IF keys - keysum # {} THEN	(* new key pressed *)
				keysum := keysum + keys;
				IF keysum = {ML, MM, MR} THEN
					marker := Effects.Arrow
				ELSE
					marker := DragColor
				END;
				Oberon.FadeCursor(Oberon.Mouse);
				Display3.Rect3D(mask, Display3.topC, Display3.bottomC, fx, fy, well.W, well.H, 1, Display.replace);
			END;
			Oberon.DrawCursor(Oberon.Mouse, marker, x, y);
			Input.Mouse(keys, x, y)
		END;
		IF keysum = {ML, MM} THEN
			Display3.Rect3D(mask, Display3.topC, Display3.bottomC, fx, fy, well.W, well.H, 1, Display.replace);
			TrackColor(well, fx, fy, msg)
		ELSIF keysum = {MM} THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Gadgets.ExecuteAttr(well, "Cmd", msg.dlink, NIL, NIL);
			Display3.Rect3D(mask, Display3.topC, Display3.bottomC, fx, fy, well.W, well.H, 1, Display.replace)
		ELSIF keysum = {MM, MR} THEN
			Gadgets.ThisFrame(x, y, frame, u, v);
			IF frame # NIL THEN
				am.id := Objects.get; am.name := "TargetAttr"; am.res := -1;
				well.handle(well, am);
				IF (am.res >= 0) & (am.class = Objects.String) & (am.s # "") THEN
					COPY(am.s, am.name)
				ELSE
					am.name := "Color"
				END;
				am.id := Objects.set; am.class := Objects.Int; am.i := well.col; am.res := -1;
				frame.handle(frame, am);
				IF am.res >= 0 THEN
					Gadgets.Update(frame)
				END
			END
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
	END TrackMiddle;
	
	PROCEDURE Restore (well: ColorWell; fx, fy: INTEGER; mask: Display3.Mask);
		VAR w, h: INTEGER;
	BEGIN
		w := well.W; h := well.H;
		Oberon.RemoveMarks(fx, fy, w, h);
		Display3.Rect3D(mask, Display3.topC, Display3.bottomC, fx, fy, w, h, 1, Display.replace);
		Display3.Rect3D(mask, Display3.groupC, Display3.groupC, fx + 1, fy + 1, w - 2, h - 2, 1, Display.replace);
		Display3.FilledRect3D(mask, Display3.bottomC, Display3.topC, well.col, fx + 2, fy + 2, w - 4, h - 4, 1, Display.replace);
		IF Gadgets.selected IN well.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, fx, fy, w, h, Display.paint)
		END
	END Restore;
	
	PROCEDURE DisplayWell (well: ColorWell; fx, fy: INTEGER; VAR msg: Display.DisplayMsg);
		VAR
			mask: Display3.Mask; x, y, w, h, one, two: INTEGER;
		
		PROCEDURE P (x: LONGINT): INTEGER;
		BEGIN
			RETURN SHORT(x * LONG(10000) DIV Printer.Unit)
		END P;
	
	BEGIN
		IF msg.device = Display.screen THEN
			IF (msg.id = Display.full) OR (msg.F = NIL) THEN
				Gadgets.MakeMask(well, fx, fy, msg.dlink, mask);
				Restore(well, fx, fy, mask)
			ELSIF msg.id = Display.area THEN
				Gadgets.MakeMask(well, fx, fy, msg.dlink, mask);
				Display3.AdjustMask(mask, fx + msg.u, fy + well.H - 1 + msg.v, msg.w, msg.h);
				Restore(well, fx, fy, mask)
			END
		ELSIF msg.device = Display.printer THEN
			Gadgets.MakePrinterMask(well, msg.x, msg.y, msg.dlink, mask);
			x := msg.x; y := msg.y; w := P(well.W); h := P(well.H); one := P(1); two := P(2);
			Printer3.Rect3D(mask, Display3.topC, Display3.bottomC, x, y, w, h, one, Display.replace);
			Printer3.FilledRect3D(mask, Display3.bottomC, Display3.topC, well.col, x+one, y+one, w-two, h-two, one, Display.replace)
		END
	END DisplayWell;
	
	PROCEDURE Field (frame: Gadgets.Frame; VAR name: ARRAY OF CHAR);
		VAR am: Objects.AttrMsg;
	BEGIN
		am.id := Objects.get; am.name := "Field"; am.res := -1;
		frame.handle(frame, am);
		IF (am.res >= 0) & (am.class = Objects.String) & (am.s # "") THEN
			COPY(am.s, name)
		ELSE
			COPY("Value", name)
		END
	END Field;
	
	PROCEDURE SetModel (well: ColorWell);
		VAR am: Objects.AttrMsg;
	BEGIN
		IF well.obj # NIL THEN
			am.id := Objects.set; Field(well, am.name); am.class := Objects.Int; am.i := well.col; am.res := -1;
			well.obj.handle(well.obj, am)
		END
	END SetModel;
	
	PROCEDURE UpdateModel (well: ColorWell);
		VAR am: Objects.AttrMsg;
	BEGIN
		IF well.obj # NIL THEN
			am.id := Objects.get; Field(well, am.name); am.class := Objects.Inval; am.res := -1;
			well.obj.handle(well.obj, am);
			IF (am.res >= 0) & (am.class = Objects.Int) THEN
				well.col := SHORT(am.i)
			END
		END
	END UpdateModel;
	
	PROCEDURE HandleAttr (well: ColorWell; VAR msg: Objects.AttrMsg);
	BEGIN
		IF msg.id = Objects.get THEN
			IF msg.name = "Gen" THEN
				msg.class := Objects.String; msg.s := "ColorWells.NewColorWell"; msg.res := 0
			ELSIF (msg.name = "Color") OR (msg.name = "Value") THEN
				msg.class := Objects.Int; msg.i := well.col; msg.res := 0
			ELSIF (msg.name = "Cmd") OR (msg.name = "Field") OR (msg.name = "TargetAttr") THEN
				Gadgets.framehandle(well, msg);
				IF msg.res < 0 THEN
					msg.class := Objects.String; msg.s := ""; msg.res := 0
				END
			ELSE
				Gadgets.framehandle(well, msg)
			END
		ELSIF (msg.id = Objects.set) & ((msg.name = "Color") OR (msg.name = "Value")) & (msg.class = Objects.Int) THEN
			well.col := SHORT(msg.i); msg.res := 0;
			IF well.obj # NIL THEN
				SetModel(well);
				Gadgets.Update(well.obj)
			END
		ELSIF msg.id = Objects.enum THEN
			msg.Enum("Color"); msg.Enum("Cmd"); msg.Enum("Field"); msg.Enum("TargetAttr");
			Gadgets.framehandle(well, msg)
		ELSE
			Gadgets.framehandle(well, msg)
		END
	END HandleAttr;
	
	PROCEDURE Copy* (VAR msg: Objects.CopyMsg; from, to: ColorWell);
	BEGIN
		Gadgets.CopyFrame(msg, from, to);
		to.col := from.col
	END Copy;
	
	PROCEDURE Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR well, copy: ColorWell; fx, fy: INTEGER; mask: Display3.Mask; am: Objects.AttrMsg; ver: LONGINT;
	BEGIN
		well := obj(ColorWell);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = well) THEN
					fx := msg.x + well.X; fy := msg.y + well.Y;
					IF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							IF (msg.id = Oberon.track) & ~(Gadgets.selected IN well.state) & Gadgets.InActiveArea(well, msg) THEN
								IF msg.keys = {ML} THEN
									TrackColor(well, fx, fy, msg);
									msg.res := 0
								ELSIF msg.keys = {MM} THEN
									TrackMiddle(well, fx, fy, msg);
									msg.res := 0
								ELSE
									Gadgets.framehandle(well, msg)
								END
							ELSE
								Gadgets.framehandle(well, msg)
							END
						END
					
					ELSIF msg IS Display.DisplayMsg THEN
						DisplayWell(well, fx, fy, msg(Display.DisplayMsg))
					
					ELSIF msg IS Gadgets.UpdateMsg THEN
						WITH msg: Gadgets.UpdateMsg DO
							IF well.obj # NIL THEN
								well.obj.handle(well.obj, msg)
							END;
							IF msg.obj = well.obj THEN
								IF msg.stamp # well.stamp THEN
									well.stamp := msg.stamp;
									UpdateModel(well)
								END;
								Gadgets.MakeMask(well, fx, fy, msg.dlink, mask);
								Restore(well, fx, fy, mask)
							ELSE
								Gadgets.framehandle(well, msg)
							END
						END
					
					ELSIF msg IS Display.ControlMsg THEN
						WITH msg: Display.ControlMsg DO
							IF well.obj # NIL THEN
								well.obj.handle(well.obj, msg)
							END;
							IF (msg.id = Display.restore) & (msg.stamp # well.stamp) THEN
								well.stamp := msg.stamp;
								UpdateModel(well)
							END
						END
					
					ELSIF msg IS Display.ConsumeMsg THEN
						WITH msg: Display.ConsumeMsg DO
							IF msg.id = Display.drop THEN
								am.id := Objects.get; am.name := "Color"; am.class := Objects.Inval; am.res := -1;
								msg.obj.handle(msg.obj, am);
								IF (am.res >= 0) & (am.class = Objects.Int) THEN
									well.col := SHORT(am.i);
									IF well.obj # NIL THEN
										SetModel(well);
										Gadgets.Update(well.obj)
									ELSE
										Gadgets.Update(well)
									END;
									msg.res := 0
								END
							END
						END
					
					ELSE
						Gadgets.framehandle(well, msg)
					END
				ELSE
					Gadgets.framehandle(well, msg)
				END
			END
		
		ELSIF msg IS Objects.AttrMsg THEN
			HandleAttr(well, msg(Objects.AttrMsg))
		
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # well.stamp THEN
					NEW(copy); well.dlink := copy; well.stamp := msg.stamp;
					Copy(msg, well, copy)
				END;
				msg.obj := well.dlink
			END
		
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(well, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Files.WriteInt(msg.R, well.col)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver >= 1 THEN
						Files.ReadInt(msg.R, well.col)
					END
				END
			END
		ELSE
			Gadgets.framehandle(well, msg)
		END
	END Handle;
	
	PROCEDURE InitColorWell* (well: ColorWell; col: INTEGER);
	BEGIN
		well.handle := Handle;
		well.W := 20; well.H := 20;
		well.col := col
	END InitColorWell;
	
	PROCEDURE NewColorWell*;
		VAR well: ColorWell;
	BEGIN
		NEW(well);
		InitColorWell(well, Display3.white);
		Objects.NewObj := well
	END NewColorWell;
	

BEGIN
	InitMarker
END ColorWells.

System.Free ColorWells ~

Gadgets.Insert ColorWells.NewColorWell ~
Gadgets.Insert ColorWells.NewColorWell BasicGadgets.NewInteger ~
