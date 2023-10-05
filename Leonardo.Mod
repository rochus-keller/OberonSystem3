MODULE Leonardo;	(** eos   **)

	IMPORT
		Files, Display, Input, Math, Objects, Fonts, Texts, Strings, Pictures, Oberon, Printer, Display3, Effects, Printer3, Attributes,
		Gadgets, BasicGadgets, Documents, Desktops, RembrandtDocs, GfxMatrix, GfxMaps, GfxPictures, Gfx, GfxBuffer, GfxPS,
		Figures, FigureGadgets, LeoFrames;
		
	
	CONST
		MenuBar = "Desktops.Copy[Copy] Leonardo.Undo[Undo] Leonardo.Redo[Redo] Desktops.StoreDoc[Store]";
		ML = 2; MM = 1; MR = 0;
		RulerWidth = 16;
		
	
	TYPE
		(** ruler frame **)
		Ruler* = POINTER TO RulerDesc;
		RulerDesc* = RECORD (Gadgets.FrameDesc)
			ox, oy, scale, unit: REAL;	(* copies of corresponding values in content frame => catch updates of coordinate system *)
		END;
		
		StoreMsg = RECORD (Display.FrameMsg)
			fig: Figures.Figure
		END;
		
	
	VAR
		W: Texts.Writer;
		RulerFont: Fonts.Font;	(* font for rendering ruler ticks *)
		HResize, VResize, HAlign, VAlign: BasicGadgets.Integer;
		
	
	(**--- Rulers ---**)
	
	PROCEDURE ForwardRuler (r: Ruler; fx, fy: INTEGER; VAR msg: Display.FrameMsg);
		VAR tx, ty: INTEGER;
	BEGIN
		tx := msg.x; ty := msg.y;
		msg.x := fx; msg.y := fy + r.H - 1;
		Figures.Forward(r, r.dsc, msg);
		msg.x := tx; msg.y := ty
	END ForwardRuler;
	
	PROCEDURE SetRulerMask (frame: Display.Frame; mask: Display3.Mask);
		VAR om: Display3.OverlapMsg;
	BEGIN
		om.M := mask; om.x := 0; om.y := 0; om.F := frame; om.dlink := NIL; om.res := -1;
		frame.handle(frame, om)
	END SetRulerMask;
	
	PROCEDURE SetRulerContentMask (r: Ruler);
		VAR mask: Display3.Mask;
	BEGIN
		IF r.mask = NIL THEN
			SetRulerMask(r.dsc, NIL)
		ELSE
			Display3.Copy(r.mask, mask);
			mask.x := 0; mask.y := 0;
			Display3.Intersect(mask, r.dsc.X, r.dsc.Y, r.dsc.W, r.dsc.H);
			mask.x := -r.dsc.X; mask.y := -(r.dsc.Y + r.dsc.H - 1);
			Display3.Shift(mask);
			SetRulerMask(r.dsc, mask)
		END
	END SetRulerContentMask;
	
	PROCEDURE TrackRuler (r: Ruler; fx, fy: INTEGER; VAR msg: Oberon.InputMsg);
		VAR ix, iy, iw, ih, mx, x, y, my: INTEGER; keysum, keys: SET; mask: Display3.Mask;
	BEGIN
		ix := fx + RulerWidth; iy := fy + r.H - RulerWidth; iw := r.W - RulerWidth; ih := r.H - RulerWidth;
		IF Effects.Inside(msg.X, msg.Y, ix, iy, iw, RulerWidth) & ((msg.keys = {ML}) OR (msg.keys = {MR})) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Gadgets.MakeMask(r, fx, fy, msg.dlink, mask);
			Display3.ReplConst(mask, Display3.invertC, msg.X, fy, 1, r.H, Display.invert);
			mx := msg.X; keysum := msg.keys;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & (x # mx) & (x >= ix) & (x < ix + iw) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					Display3.ReplConst(mask, Display3.invertC, mx, fy, 1, r.H, Display.invert);
					Display3.ReplConst(mask, Display3.invertC, x, fy, 1, r.H, Display.invert);
					mx := x
				END;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
			UNTIL keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(mask, Display3.invertC, mx, fy, 1, r.H, Display.invert);
			IF keysum = {MR} THEN
				FigureGadgets.ScrollFrame(r.dsc(LeoFrames.Frame), ix + iw - mx, 0)
			ELSIF keysum = {ML} THEN
				FigureGadgets.ScrollFrame(r.dsc(LeoFrames.Frame), ix - mx, 0)
			END
		ELSIF Effects.Inside(msg.X, msg.Y, fx, fy, RulerWidth, ih) & ((msg.keys = {ML}) OR (msg.keys = {MR})) THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Gadgets.MakeMask(r, fx, fy, msg.dlink, mask);
			Display3.ReplConst(mask, Display3.invertC, fx, msg.Y, r.W, 1, Display.invert);
			my := msg.Y; keysum := msg.keys;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & (y # my) & (y >= fy) & (y < iy) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					Display3.ReplConst(mask, Display3.invertC, fx, my, r.W, 1, Display.invert);
					Display3.ReplConst(mask, Display3.invertC, fx, y, r.W, 1, Display.invert);
					my := y
				END;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
			UNTIL keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(mask, Display3.invertC, fx, my, r.W, 1, Display.invert);
			IF keysum = {ML} THEN
				FigureGadgets.ScrollFrame(r.dsc(LeoFrames.Frame), 0, fy + ih - my)
			ELSIF keysum = {MR} THEN
				FigureGadgets.ScrollFrame(r.dsc(LeoFrames.Frame), 0, fy - my)
			END
		ELSIF Effects.Inside(msg.X, msg.Y, fx, iy, RulerWidth, RulerWidth) & ((msg.keys = {ML}) OR (msg.keys = {MR})) THEN
			Oberon.RemoveMarks(fx, iy, RulerWidth, RulerWidth);
			Gadgets.MakeMask(r, fx, fy, msg.dlink, mask);
			Display3.Rect3D(mask, Display3.bottomC, Display3.topC, fx, iy, RulerWidth, RulerWidth, 1, Display.replace);
			Display3.ReplConst(mask, Display3.black, fx + RulerWidth DIV 4, iy + RulerWidth DIV 2, RulerWidth DIV 2, 1, Display.replace);
			IF msg.keys = {2} THEN
				Display3.ReplConst(mask, Display3.black, fx + RulerWidth DIV 2, iy + RulerWidth DIV 4, 1, RulerWidth DIV 2, Display.replace)
			END;
			mx := msg.X; my := msg.Y; keysum := msg.keys;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y)
			UNTIL keys = {};
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, iy, RulerWidth, RulerWidth, 1, Display.replace);
			IF keysum = {MR} THEN	(* zoom out *)
				FigureGadgets.ZoomFrame(r.dsc(LeoFrames.Frame), 0.5)
			ELSIF keysum = {ML} THEN	(* zoom in *)
				FigureGadgets.ZoomFrame(r.dsc(LeoFrames.Frame), 2)
			END
		ELSE
			x := msg.X; y := msg.Y
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, x, y);
		msg.res := 0
	END TrackRuler;
	
	PROCEDURE RestoreRuler (r: Ruler; x, y, w, h, fx, fy: INTEGER; mask: Display3.Mask; dlink: Objects.Object);
		CONST
			rw = RulerWidth - 1;
		VAR
			f: LeoFrames.Frame; ix, iy, iw, ih, lx, rx, by, ty: INTEGER; fig: Figures.Figure; dm: Display.DisplayMsg;
			dtick, xt, yt: REAL; scale, skip, n: LONGINT;
		
		PROCEDURE number (mask: Display3.Mask; x, y: INTEGER; n: LONGINT; down: BOOLEAN);
			VAR dx, cx, cy, cw, ch: INTEGER; pat: Display.Pattern; m: LONGINT;
		BEGIN
			IF n < 0 THEN
				Fonts.GetChar(RulerFont, "-", dx, cx, cy, cw, ch, pat);
				Display3.CopyPattern(mask, Display3.black, pat, x + cx, y + cy, Display.paint);
				IF down THEN DEC(y, RulerFont.height) ELSE INC(x, dx) END;
				n := -n
			END;
			m := 100000;
			WHILE m > n DO m := m DIV 10 END;
			WHILE m > 1 DO
				Fonts.GetChar(RulerFont, CHR(ORD("0") + n DIV m), dx, cx, cy, cw, ch, pat);
				Display3.CopyPattern(mask, Display3.black, pat, x + cx, y + cy, Display.paint);
				IF down THEN DEC(y, RulerFont.height) ELSE INC(x, dx) END;
				n := n MOD m; m := m DIV 10
			END;
			Fonts.GetChar(RulerFont, CHR(ORD("0") + n), dx, cx, cy, cw, ch, pat);
			Display3.CopyPattern(mask, Display3.black, pat, x + cx, y + cy, Display.paint)
		END number;
		
	BEGIN
		f := r.dsc(LeoFrames.Frame);
		ix := fx + RulerWidth; iy := fy + r.H - RulerWidth; iw := r.W - RulerWidth; ih := r.H - RulerWidth;
		Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, iy, RulerWidth, RulerWidth, 1, Display.replace);
		Display3.ReplConst(mask, Display3.groupC, fx, fy, rw, ih, Display.replace);
		Display3.ReplConst(mask, Display3.black, ix - 1, fy, 1, ih, Display.replace);
		Display3.ReplConst(mask, Display3.groupC, ix, iy + 1, iw, rw, Display.replace);
		Display3.ReplConst(mask, Display3.black, ix, iy, iw, 1, Display.replace);
		ASSERT((f.obj # NIL) & (f.obj IS Figures.Figure));
		fig := f.obj(Figures.Figure);
		lx := SHORT(ENTIER(fx + RulerWidth + r.ox + 0.5));
		rx := lx + SHORT(ENTIER(fig.width * r.scale + 0.5));
		by := SHORT(ENTIER(fy + f.H + r.oy + 0.5));
		ty := by + SHORT(ENTIER(fig.height * r.scale + 0.5));
		IF (ix <= lx) & (rx <= ix + iw) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, lx, iy + 1, rx - lx, rw, 1, Display.replace)
		ELSIF (ix <= lx) & (lx < ix + iw) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, lx, iy + 1, ix + iw - lx, rw, 1, Display.replace)
		ELSIF (ix < rx) & (rx <= ix + iw) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, ix, iy + 1, rx - ix, rw, 1, Display.replace)
		ELSIF (lx <= ix) & (ix + iw <= rx) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, ix, iy + 1, iw, rw, 1, Display.replace)
		END;
		IF (fy <= by) & (ty <= iy) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, by, rw, ty - by, 1, Display.replace)
		ELSIF (fy <= by) & (by < iy) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, by, rw, iy - by, 1, Display.replace)
		ELSIF (fy < ty) & (ty <= iy) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, fy, rw, ty - fy, 1, Display.replace)
		ELSIF (by <= fy) & (iy <= ty) THEN
			Display3.FilledRect3D(mask, Display3.topC, Display3.bottomC, Display3.textbackC, fx, fy, rw, ih, 1, Display.replace)
		END;
		
		dtick := r.unit * r.scale; scale := 1;
		WHILE dtick < 10 DO
			dtick := 10*dtick; scale := 10*scale
		END;
		IF dtick < 20 THEN
			skip := 10
		ELSIF dtick < 40 THEN
			skip := 5
		ELSE
			skip := 1
		END;
		n := -ENTIER(r.ox/dtick); xt := lx + n * dtick + 0.5;
		WHILE xt < fx + r.W DO
			IF n MOD skip = 0 THEN
				Display3.ReplConst(mask, Display3.black, SHORT(ENTIER(xt)), iy+3, 1, rw-2, Display.replace);
				number(mask, SHORT(ENTIER(xt))+2, iy+3, n * scale, FALSE)
			ELSE
				Display3.ReplConst(mask, Display3.black, SHORT(ENTIER(xt)), iy+11, 1, rw-11, Display.replace)
			END;
			INC(n);
			xt := xt + dtick
		END;
		n := ENTIER(-r.oy/dtick); yt := by + n * dtick + 0.5;
		WHILE yt > fy DO
			IF n MOD skip = 0 THEN
				Display3.ReplConst(mask, Display3.black, fx+1, SHORT(ENTIER(yt)), rw-2, 1, Display.replace);
				number(mask, fx + 6, SHORT(ENTIER(yt))-10, n * scale, TRUE)
			ELSE
				Display3.ReplConst(mask, Display3.black, fx+1, SHORT(ENTIER(yt)), rw-11, 1, Display.replace)
			END;
			DEC(n);
			yt := yt - dtick
		END;
		
		Objects.Stamp(dm); dm.device := Display.screen; dm.id := Display.full; dm.F := f; dm.dlink := dlink; dm.res := -1;
		IF (x > RulerWidth) OR (x + w < r.W) OR (y > 0) OR (y + h < r.H - RulerWidth) THEN
			dm.id := Display.area;
			dm.u := x - RulerWidth; dm.v := y - ih + 1; dm.w := w; dm.h := h
		END;
		ForwardRuler(r, fx, fy, dm);
		IF Gadgets.selected IN r.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, fx + x, fy + y, w, h, Display.paint)
		END
	END RestoreRuler;
	
	PROCEDURE PrintRuler (r: Ruler; VAR msg: Display.DisplayMsg);
		VAR mask: Display3.Mask; x, y, w, h, tx, ty: INTEGER;
	BEGIN
		Gadgets.MakePrinterMask(r, msg.x, msg.y, msg.dlink, mask);
		x := msg.x + SHORT(LONG(r.X) * 10000 DIV Printer.Unit);
		y := msg.y + SHORT(LONG(r.Y) * 10000 DIV Printer.Unit);
		w := SHORT(LONG(r.W) * 10000 DIV Printer.Unit);
		h := SHORT(LONG(r.H) * 10000 DIV Printer.Unit);
		Printer3.ReplConst(mask, Display3.groupC, x, y, w, h, Display.replace);
		tx := msg.x; ty := msg.y;
		msg.x := msg.x + x; msg.y := msg.y + y;
		Figures.Forward(r, r.dsc, msg);
		msg.x := tx; msg.y := ty
	END PrintRuler;
	
	PROCEDURE ModifyRuler (r: Ruler; VAR msg: Display.ModifyMsg);
		VAR mm: Display.ModifyMsg;
	BEGIN
		Objects.Stamp(mm); mm.id := Display.extend; mm.F := r.dsc; mm.mode := Display.state;
		mm.X := RulerWidth; mm.Y := 1 - msg.H; mm.W := msg.W - RulerWidth; mm.H := msg.H - RulerWidth;
		mm.dX := mm.X - r.dsc.X; mm.dY := mm.Y - r.dsc.Y; mm.dW := mm.W - r.dsc.W; mm.dH := mm.H - r.dsc.H;
		mm.x := 0; mm.y := 0; mm.res := -1;
		r.dsc.handle(r.dsc, mm);
		Gadgets.framehandle(r, msg)
	END ModifyRuler;
	
	PROCEDURE ModifyRulerContent (r: Ruler; VAR msg: Display.ModifyMsg);
		VAR mm: Display.ModifyMsg;
	BEGIN
		IF msg.stamp # r.stamp THEN
			r.stamp := msg.stamp; mm.id := Display.extend; mm.F := r; mm.mode := Display.display;
			mm.X := r.X + msg.dX; mm.Y := r.Y + msg.dY; mm.W := msg.W + RulerWidth; mm.H := msg.H + RulerWidth;
			mm.dX := msg.dX; mm.dY := msg.dY; mm.dW := mm.W - r.W; mm.dH := mm.H - r.H;
			Display.Broadcast(mm)
		END
	END ModifyRulerContent;
	
	PROCEDURE CopyRuler (VAR msg: Objects.CopyMsg; from, to: Ruler);
		VAR cm: Objects.CopyMsg;
	BEGIN
		Gadgets.CopyFrame(msg, from, to);
		Objects.Stamp(cm); cm.id := Objects.shallow;
		from.dsc.handle(from.dsc, cm);
		to.dsc := cm.obj(Gadgets.Frame);
		to.ox := from.ox; to.oy := from.oy; to.scale := from.scale; to.unit := from.unit
	END CopyRuler;
	
	PROCEDURE HandleRuler (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR r, copy: Ruler; fx, fy: INTEGER; mask: Display3.Mask; frame: LeoFrames.Frame; ver: LONGINT;
	BEGIN
		r := obj(Ruler);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = r) THEN
					IF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							fx := msg.x + r.X; fy := msg.y + r.Y;
							IF (msg.id = Oberon.track) & Gadgets.InActiveArea(r, msg) & ~(Gadgets.selected IN r.state) THEN
								IF Effects.Inside(msg.X, msg.Y, fx + RulerWidth, fy, r.W - RulerWidth, r.H - RulerWidth) THEN
									ForwardRuler(r, fx, fy, msg)
								ELSE
									TrackRuler(r, fx, fy, msg)
								END
							ELSIF msg.id = Oberon.consume THEN
								ForwardRuler(r, fx, fy, msg)
							ELSE
								Gadgets.framehandle(r, msg)
							END
						END
					ELSIF msg IS Display.DisplayMsg THEN
						WITH msg: Display.DisplayMsg DO
							fx := msg.x + r.X; fy := msg.y + r.Y;
							IF msg.device = Display.screen THEN
								IF (msg.id = Display.full) OR (msg.F = NIL) THEN
									Gadgets.MakeMask(r, fx, fy, msg.dlink, mask);
									RestoreRuler(r, 0, 0, r.W, r.H, fx, fy, mask, msg.dlink)
								ELSIF msg.id = Display.area THEN
									Gadgets.MakeMask(r, fx, fy, msg.dlink, mask);
									Display3.AdjustMask(mask, fx + msg.u, fy + r.H - 1 + msg.v, msg.w, msg.h);
									RestoreRuler(r, msg.u, msg.v + r.H - 1, msg.w, msg.h, fx, fy, mask, msg.dlink)
								END
							ELSIF msg.device = Display.printer THEN
								IF msg.id = Display.contents THEN
									ForwardRuler(r, fx, fy, msg)
								ELSIF msg.id = Display.full THEN
									PrintRuler(r, msg)
								END
							END
						END
					ELSIF msg IS Display.ModifyMsg THEN
						ModifyRuler(r, msg(Display.ModifyMsg))
					ELSIF msg IS Display.LocateMsg THEN
						WITH msg: Display.LocateMsg DO
							fx := msg.x + r.X; fy := msg.y + r.Y;
							IF (msg.loc = NIL) & Effects.Inside(msg.X, msg.Y, fx, fy, r.W, r.H) THEN
								ForwardRuler(r, fx, fy, msg);
								IF msg.loc = NIL THEN
									msg.loc := r; msg.u := msg.X - fx; msg.v := msg.Y - (fy + r.H - 1); msg.res := 0
								END
							END
						END
					ELSIF msg IS Display3.OverlapMsg THEN
						r.mask := msg(Display3.OverlapMsg).M;
						SetRulerContentMask(r)
					ELSIF msg.F # NIL THEN
						Gadgets.framehandle(r, msg)
					ELSE
						ForwardRuler(r, msg.x + r.X, msg.y + r.Y, msg)
					END
				ELSIF msg.F = r.dsc THEN
					IF msg IS Display3.UpdateMaskMsg THEN
						SetRulerContentMask(r)
					ELSIF msg IS Display.ModifyMsg THEN
						ModifyRulerContent(r, msg(Display.ModifyMsg))
					ELSIF msg IS Display.DisplayMsg THEN
						frame := r.dsc(LeoFrames.Frame);
						IF (frame.ox # r.ox) OR (frame.oy # r.oy) OR (frame.scale # r.scale) OR (frame.unit # r.unit) THEN
							r.ox := frame.ox; r.oy := frame.oy; r.scale := frame.scale; r.unit := frame.unit;
							Gadgets.Update(r);
							msg.res := 0
						ELSE
							ForwardRuler(r, msg.x + r.X, msg.y + r.Y, msg)
						END
					ELSE
						ForwardRuler(r, msg.x + r.X, msg.y + r.Y, msg)
					END
				ELSE
					ForwardRuler(r, msg.x + r.X, msg.y + r.Y, msg)
				END
			END
		ELSIF msg IS Gadgets.UpdateMsg THEN
			WITH msg: Gadgets.UpdateMsg DO
				IF msg.obj = r.dsc(LeoFrames.Frame).obj THEN r.scale := 0 END;	(* force update when content frame is refreshed *)
				ForwardRuler(r, msg.x + r.X, msg.y + r.Y, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			WITH msg: Objects.AttrMsg DO
				Figures.HandleGenAttr(msg, "Leonardo.NewRuler");
				IF msg.res < 0 THEN
					Gadgets.framehandle(r, msg)
				END
			END
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # r.stamp THEN
					NEW(copy); r.dlink := copy; r.stamp := msg.stamp;
					CopyRuler(msg, r, copy)
				END;
				msg.obj := r.dlink
			END
		ELSIF msg IS Objects.BindMsg THEN
			r.dsc.handle(r.dsc, msg);
			Gadgets.framehandle(r.dsc, msg)
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(r, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 1);
					Gadgets.WriteRef(msg.R, r.lib, r.dsc)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 1 THEN
						Gadgets.ReadRef(msg.R, r.lib, obj);
						IF (obj # NIL) & (obj IS LeoFrames.Frame) THEN
							r.dsc := obj(LeoFrames.Frame)
						ELSE
							obj := Gadgets.CreateObject("Leonardo.NewFrame");
							r.dsc := obj(LeoFrames.Frame)
						END
					END
				END
			END
		ELSE
			Gadgets.framehandle(r, msg)
		END
	END HandleRuler;
	
	PROCEDURE InitRuler* (r: Ruler; main: LeoFrames.Frame);
	BEGIN
		r.handle := HandleRuler;
		r.dsc := main;
		IF main # NIL THEN
			r.W := main.W + RulerWidth; r.H := main.H + RulerWidth;
			main.X := RulerWidth; main.Y := -r.H;
			r.ox := main.ox; r.oy := main.oy; r.scale := main.scale; r.unit := main.unit
		END
	END InitRuler;
	
	PROCEDURE NewRuler*;
		VAR r: Ruler;
	BEGIN
		NEW(r); InitRuler(r, NIL);
		Objects.NewObj := r
	END NewRuler;
	
	
	(**--- Document ---**)
	
	PROCEDURE LoadDoc (doc: Documents.Document);
		VAR
			main: LeoFrames.Frame; file: Files.File; r: Files.Rider; tag, ref: INTEGER; name: ARRAY 64 OF CHAR; ch: CHAR;
			lib: Objects.Library; len: LONGINT; obj: Objects.Object; ff: FigureGadgets.Frame; fig: Figures.Figure;
			layer: LeoFrames.Layer; ruler: Ruler;
	BEGIN
		main := NIL;
		file := Files.Old(doc.name);
		IF file # NIL THEN
			Files.Set(r, file, 0);
			Files.ReadInt(r, tag);
			IF tag = Documents.Id THEN
				Files.ReadString(r, name);
				Files.ReadInt(r, doc.X); Files.ReadInt(r, doc.Y);
				Files.ReadInt(r, doc.W); Files.ReadInt(r, doc.H);
				Files.ReadInt(r, ref);
				Files.Read(r, ch);
				IF ch = Objects.LibBlockId THEN
					NEW(lib); Objects.OpenLibrary(lib);
					Objects.LoadLibrary(lib, file, Files.Pos(r), len);
					lib.GetObj(lib, ref, obj);
					IF (obj # NIL) & (obj IS LeoFrames.Frame) THEN
						main := obj(LeoFrames.Frame);
						ASSERT((main.obj # NIL) & (main.obj IS Figures.Figure), 110);
					ELSIF (obj # NIL) & (obj IS FigureGadgets.Frame) THEN
						ff := obj(FigureGadgets.Frame);
						ASSERT((ff.obj # NIL) & (ff.obj IS Figures.Figure), 111);
						NEW(main); LeoFrames.InitFrame(main, ff.obj(Figures.Figure), Figures.cm, 10);
						main.col := ff.col; main.ox := ff.ox; main.oy := ff.oy; main.scale := ff.scale
					END
				END
			END
		END;
		IF main = NIL THEN	(* open with empty figure *)
			IF doc.name = "" THEN doc.name := "Unnamed.Fig" END;
			NEW(fig); Figures.Init(fig, Figures.A4W, Figures.A4H);
			NEW(layer); LeoFrames.InitLayer(layer, "Main", TRUE, TRUE, TRUE, TRUE);
			Figures.Integrate(fig, fig.root, layer);
			NEW(main); LeoFrames.InitFrame(main, fig, Figures.cm, 10)
		END;
		NEW(ruler); InitRuler(ruler, main);
		Documents.Init(doc, ruler)
	END LoadDoc;
	
	PROCEDURE StoreDoc (doc: Documents.Document);
		VAR
			bak: ARRAY 64 OF CHAR; res: INTEGER; frame: Display.Frame; main: LeoFrames.Frame; bm: Objects.BindMsg;
			file: Files.File; r: Files.Rider; len: LONGINT; sm: StoreMsg;
	BEGIN
		Texts.WriteString(W, "Store ");
		Texts.Write(W, 22X); Texts.WriteString(W, doc.name); Texts.Write(W, 22X);
		Texts.Append(Oberon.Log, W.buf);
		
		(* keep backup *)
		COPY(doc.name, bak);
		Strings.Append(bak, ".Bak");
		Files.Rename(doc.name, bak, res);
		
		frame := doc.dsc;
		IF (frame # NIL) & (frame IS Ruler) THEN frame := frame.dsc END;
		IF (frame # NIL) & (frame IS LeoFrames.Frame) THEN
			main := frame(LeoFrames.Frame);
			NEW(bm.lib); Objects.OpenLibrary(bm.lib);
			main.handle(main, bm);
			
			file := Files.New(doc.name);
			IF file # NIL THEN
				Files.Set(r, file, 0);
				Files.WriteInt(r, Documents.Id);
				Files.WriteString(r, "Leonardo.NewDoc");
				Files.WriteInt(r, doc.X); Files.WriteInt(r, doc.Y);
				Files.WriteInt(r, doc.W); Files.WriteInt(r, doc.H);
				Files.WriteInt(r, main.ref);
				Objects.StoreLibrary(bm.lib, file, Files.Pos(r), len);
				Files.Register(file);
				sm.F := NIL; sm.fig := main.obj(Figures.Figure);
				Display.Broadcast(sm)
			ELSE
				Texts.WriteString(W, " - invalid document name")
			END
		ELSE
			Texts.WriteString(W, " - no figure frame")
		END;
		Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
	END StoreDoc;
	
	PROCEDURE HandleDocAttr (doc: Documents.Document; VAR msg: Objects.AttrMsg);
	BEGIN
		IF msg.id = Objects.get THEN
			IF msg.name = "Gen" THEN
				msg.class := Objects.String; msg.s := "Leonardo.NewDoc"; msg.res := 0
			ELSIF msg.name = "Adaptive" THEN
				msg.class := Objects.Bool; msg.b := TRUE; msg.res := 0
			ELSE
				Documents.Handler(doc, msg)
			END
		ELSE
			Documents.Handler(doc, msg)
		END
	END HandleDocAttr;
	
	PROCEDURE HandleDocLink (doc: Documents.Document; VAR msg: Objects.LinkMsg);
	BEGIN
		IF msg.id = Objects.get THEN
			IF msg.name = "DeskMenu" THEN
				msg.obj := Gadgets.CopyPublicObject("Leonardo.DeskMenu", TRUE);
				IF msg.obj = NIL THEN msg.obj := Desktops.NewMenu(MenuBar) END;
				msg.res := 0
			ELSIF msg.name = "SystemMenu" THEN
				msg.obj := Gadgets.CopyPublicObject("Leonardo.SystemMenu", TRUE);
				IF msg.obj = NIL THEN msg.obj := Desktops.NewMenu(MenuBar) END;
				msg.res := 0
			ELSIF msg.name = "UserMenu" THEN
				msg.obj := Gadgets.CopyPublicObject("Leonardo.UserMenu", TRUE);
				IF msg.obj = NIL THEN msg.obj := Desktops.NewMenu(MenuBar) END;
				msg.res := 0
			ELSE
				Documents.Handler(doc, msg)
			END
		ELSE
			Documents.Handler(doc, msg)
		END
	END HandleDocLink;
	
	PROCEDURE HandleDoc* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR doc: Documents.Document; main: LeoFrames.Frame; menu, f: Display.Frame; s: ARRAY 64 OF CHAR;
	BEGIN
		doc := obj(Documents.Document);
		IF msg IS Figures.UpdateMsg THEN
			WITH msg: Figures.UpdateMsg DO
				main := doc.dsc.dsc(LeoFrames.Frame);
				IF (main.obj = msg.fig) & ~(16 IN doc.state) THEN
					INCL(doc.state, 16);
					menu := Desktops.CurMenu(msg.dlink);
					IF menu # NIL THEN
						f := menu.dsc;
						WHILE f # NIL DO
							Attributes.GetString(f, "Caption", s);
							IF s = "Store" THEN
								Attributes.SetString(f, "Caption", "Store!");
								Gadgets.Update(f);
								f := NIL
							ELSE
								f := f.next
							END
						END
					END
				END;
				Documents.Handler(doc, msg)
			END
		ELSIF msg IS StoreMsg THEN
			WITH msg: StoreMsg DO
				main := doc.dsc.dsc(LeoFrames.Frame);
				IF (msg.fig = main.obj) & (16 IN doc.state) THEN
					EXCL(doc.state, 16);
					menu := Desktops.CurMenu(msg.dlink);
					IF menu # NIL THEN
						f := menu.dsc;
						WHILE f # NIL DO
							Attributes.GetString(f, "Caption", s);
							IF s = "Store!" THEN
								Attributes.SetString(f, "Caption", "Store");
								Gadgets.Update(f);
								f := NIL
							ELSE
								f := f.next
							END
						END
					END
				END;
				Documents.Handler(doc, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleDocAttr(doc, msg(Objects.AttrMsg))
		ELSIF msg IS Objects.LinkMsg THEN
			HandleDocLink(doc, msg(Objects.LinkMsg))
		ELSE
			Documents.Handler(doc, msg)
		END
	END HandleDoc;
	
	(** initialize document **)
	PROCEDURE InitDoc* (doc: Documents.Document);
	BEGIN
		doc.handle := HandleDoc;
		doc.Load := LoadDoc; doc.Store := StoreDoc;
		doc.X := 0; doc.W := Display.Width DIV 2; doc.H := Display.Height DIV 2
	END InitDoc;
	
	(** document generator **)
	PROCEDURE NewDoc*;
		VAR doc: Documents.Document;
	BEGIN
		NEW(doc); InitDoc(doc);
		Objects.NewObj := doc
	END NewDoc;
	
	(** open document with figure **)
	PROCEDURE OpenFigure* (fig: Figures.Figure; name: ARRAY OF CHAR);
		VAR frame: LeoFrames.Frame; doc: Documents.Document; ruler: Ruler;
	BEGIN
		NEW(frame); LeoFrames.InitFrame(frame, fig, Figures.cm, 10);
		NEW(doc); InitDoc(doc);
		COPY(name, doc.name);
		NEW(ruler); InitRuler(ruler, frame);
		Documents.Init(doc, ruler);
		Desktops.ShowDoc(doc)
	END OpenFigure;
	
	
	(**--- Editing Commands ---**)
	
	PROCEDURE FindFrame* (VAR frame: LeoFrames.Frame);
		VAR f: Display.Frame; x, y: INTEGER;
	BEGIN
		Gadgets.ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, f, x, y);
		IF (f # NIL) & (f IS LeoFrames.Frame) THEN
			frame := f(LeoFrames.Frame)
		ELSE
			frame := NIL
		END
	END FindFrame;
	
	PROCEDURE FindFigure* (VAR fig: Figures.Figure);
		VAR doc: Documents.Document; f: Display.Frame; x, y: INTEGER; frame: Gadgets.Frame; sm: Display.SelectMsg;
	BEGIN
		fig := NIL;
		doc := Desktops.CurDoc(Gadgets.context);
		IF doc # NIL THEN
			f := doc.dsc;
			IF (f # NIL) & (f IS Gadgets.Frame) THEN
				frame := f(Gadgets.Frame);
				IF (frame.obj # NIL) & (frame.obj IS Figures.Figure) THEN
					fig := frame.obj(Figures.Figure)
				ELSIF (frame.dsc # NIL) & (frame.dsc IS Gadgets.Frame) THEN	(* is probably ruler *)
					frame := frame.dsc(Gadgets.Frame);
					IF (frame.obj # NIL) & (frame.obj IS Figures.Figure) THEN
						fig := frame.obj(Figures.Figure)
					END
				END
			END
		END;
		IF (fig = NIL) & Oberon.Pointer.on THEN
			Gadgets.ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, f, x, y);
			IF (f # NIL) & (f IS Gadgets.Frame) THEN
				frame := f(Gadgets.Frame);
				IF (frame.obj # NIL) & (frame.obj IS Figures.Figure) THEN
					fig := frame.obj(Figures.Figure)
				END
			END
		END;
		IF fig = NIL THEN
			sm.F := NIL; sm.id := Display.get; sm.sel := NIL; sm.obj := NIL; sm.time := -1;
			Display.Broadcast(sm);
			IF (sm.time >= 0) & (sm.sel # NIL) & (sm.sel IS Gadgets.Frame) THEN
				frame := sm.sel(Gadgets.Frame);
				IF (frame.obj # NIL) & (frame.obj IS Figures.Figure) THEN
					fig := frame.obj(Figures.Figure)
				END
			END
		END;
		IF fig = NIL THEN
			Gadgets.ThisFrame(Oberon.Pointer.X, Oberon.Pointer.Y, f, x, y);
			IF (f # NIL) & (f IS Gadgets.Frame) THEN
				frame := f(Gadgets.Frame);
				IF (frame.obj # NIL) & (frame.obj IS Figures.Figure) THEN
					fig := frame.obj(Figures.Figure)
				END
			END
		END
	END FindFigure;
	
	(** undo last operation **)
	PROCEDURE Undo*;
		VAR fig: Figures.Figure;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.Undo(fig)
		END
	END Undo;
	
	(** redo most recently undone operation **)
	PROCEDURE Redo*;
		VAR fig: Figures.Figure;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.Redo(fig)
		END
	END Redo;
	
	(** open marked frame displaying figure as Leonardo document **)
	PROCEDURE Open*;
		VAR s: Attributes.Scanner; fig: Figures.Figure;
	BEGIN
		Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
		Attributes.Scan(s);
		IF (s.class = Attributes.Char) & (s.c = "*") THEN
			FindFigure(fig);
			IF fig # NIL THEN
				Oberon.FadeCursor(Oberon.Pointer);	(* otherwise document is more likely to appear on top of marked figure *)
				OpenFigure(fig, "Unnamed.Fig")
			END
		END
	END Open;
	
	(** integrate marked document in a figure at caret **)
	PROCEDURE Integrate*;
		VAR fig: Figures.Figure; llx, lly, urx, ury, bw: REAL; frame: FigureGadgets.Frame;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetShapeBox(fig.root, llx, lly, urx, ury, bw);
			IF (llx < urx) & (lly < ury) THEN
				NEW(frame); FigureGadgets.InitFrame(frame, NIL);	(* fig = NIL => frame origin remains at (0, 0) *)
				frame.obj := fig;
				frame.ox := -(llx - bw); frame.oy := -(ury + bw);
				frame.W := SHORT(ENTIER(urx - llx + 2*bw)); frame.H := SHORT(ENTIER(ury - lly + 2*bw));
				INCL(frame.state, Gadgets.transparent);
				Gadgets.Integrate(frame)
			END
		END
	END Integrate;
	
	(** open picture containing marked frame **)
	PROCEDURE MakePicture*;
		VAR fig: Figures.Figure; llx, lly, urx, ury, bw: REAL; map: GfxMaps.Map; ctxt: GfxBuffer.Context; pict: Pictures.Picture;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetShapeBox(fig.root, llx, lly, urx, ury, bw);
			IF (llx < urx) & (lly < ury) THEN
				NEW(map); GfxMaps.Create(map, SHORT(ENTIER(urx - llx + 2*bw)), SHORT(ENTIER(ury - lly + 2*bw)), GfxMaps.I8);
				NEW(ctxt); GfxBuffer.Init(ctxt, map);
				GfxBuffer.SetCoordinates(ctxt, -(llx - bw), -(lly - bw), ctxt.scale);
				Gfx.Reset(ctxt);
				Figures.Render(fig, Figures.Print, ctxt);
				NEW(pict); GfxPictures.MapToPict(map, pict, GfxMaps.DisplayPal);
				RembrandtDocs.OpenPict(pict, "")
			END
		END
	END MakePicture;
	
	(** create eps file containing marked figure; optional parameters are: [filename [resolution [level]]] **)
	PROCEDURE MakeEPS*;
		VAR
			fig: Figures.Figure; llx, lly, urx, ury, bw: REAL; s: Attributes.Scanner; name: ARRAY 32 OF CHAR; res: LONGINT;
			level2: BOOLEAN; ctxt: GfxPS.Context;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetShapeBox(fig.root, llx, lly, urx, ury, bw);
			IF (llx < urx) & (lly < ury) THEN
				Attributes.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
				Attributes.Scan(s);
				IF s.class = Attributes.Name THEN COPY(s.s, name); Attributes.Scan(s)
				ELSE name := "Figure.eps"
				END;
				IF s.class = Attributes.Int THEN res := s.i; Attributes.Scan(s)
				ELSE res := 300
				END;
				level2 := (s.class = Attributes.Int) & (s.i = 2);
				Texts.WriteString(W, "creating "); Texts.Write(W, 22X); Texts.WriteString(W, name); Texts.Write(W, 22X);
				Texts.WriteString(W, ", res="); Texts.WriteInt(W, res, 0);
				IF level2 THEN Texts.WriteString(W, ", level=2") ELSE Texts.WriteString(W, ", level=1") END;
				Texts.Append(Oberon.Log, W.buf);
				NEW(ctxt); GfxPS.InitEPS(ctxt, level2, res);
				GfxPS.Open(ctxt, Files.New(name));
				Figures.Render(fig, Figures.Print, ctxt);
				GfxPS.Close(ctxt);
				Texts.WriteString(W, "  done"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		END
	END MakeEPS;
	
	(** delete current figure selection **)
	PROCEDURE Delete*;
		VAR fig: Figures.Figure; sel: Figures.Shape;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF sel # NIL THEN
				Figures.Delete(fig, sel)
			END
		END
	END Delete;
	
	(** copy selection **)
	PROCEDURE Duplicate*;
		VAR fig: Figures.Figure; sel: Figures.Shape; mat: GfxMatrix.Matrix;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF sel # NIL THEN
				Figures.DisableUpdate(fig);
				GfxMatrix.Translate(GfxMatrix.Identity, 5, -5, mat);
				Figures.Transform(fig, sel, mat);
				Figures.CopyShapes(sel, sel);
				Figures.Undo(fig);
				LeoFrames.Integrate(fig, NIL, sel);
				Figures.EnableUpdate(fig)
			END
		END
	END Duplicate;
	
	(** group selected shapes **)
	PROCEDURE Group*;
		VAR fig: Figures.Figure; sel: Figures.Shape; obj, link: Objects.Object; group: Figures.Container;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF sel # NIL THEN
				obj := sel; sel := NIL;
				WHILE obj # NIL DO
					link := obj.slink; obj.slink := sel; sel := obj(Figures.Shape); obj := link
				END;
				NEW(group); Figures.InitGroup(group, NIL, NIL);
				Figures.DisableUpdate(fig);
				Figures.BeginCommand(fig);
				LeoFrames.Integrate(fig, NIL, group);
				LeoFrames.Integrate(fig, group, sel);
				Figures.EndCommand(fig);
				Figures.EnableUpdate(fig)
			END
		END
	END Group;
	
	(** ungroup selected groups **)
	PROCEDURE Ungroup*;
		VAR
			fig: Figures.Figure; sel: Figures.Shape; obj, next: Objects.Object; gen: ARRAY 64 OF CHAR;
			group: Figures.Container; ref: Figures.Reference; comp: Figures.Shape;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			Figures.DisableUpdate(fig);
			Figures.BeginCommand(fig);
			obj := sel;
			WHILE obj # NIL DO
				next := obj.slink;
				IF obj IS Figures.Container THEN
					Attributes.GetString(obj, "Gen", gen);
					IF gen = "Figures.NewGroup" THEN	(* this is not very elegant, ugh *)
						group := obj(Figures.Container);
						ref := group.first; comp := ref.shape;
						WHILE ref # group.last DO ref.shape.slink := ref.next.shape; ref := ref.next END;
						ref.shape.slink := NIL;
						LeoFrames.Integrate(fig, group.cont, comp);
						group.slink := NIL;
						Figures.Delete(fig, group)
					END
				END;
				obj := next
			END;
			Figures.EndCommand(fig);
			Figures.EnableUpdate(fig)
		END
	END Ungroup;
	
	PROCEDURE MoveSelection (id: INTEGER);
		VAR fig: Figures.Figure; pm: Figures.PriorityMsg;
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.DisableUpdate(fig);
			Figures.BeginCommand(fig);
			Objects.Stamp(pm); pm.fig := fig; pm.id := id;
			fig.handle(fig, pm);
			Figures.EndCommand(fig);
			Figures.EnableUpdate(fig)
		END
	END MoveSelection;
	
	(** move selected shapes up **)
	PROCEDURE MoveUp*;
	BEGIN
		MoveSelection(Figures.Up)
	END MoveUp;
	
	(** move selected shapes down **)
	PROCEDURE MoveDown*;
	BEGIN
		MoveSelection(Figures.Down)
	END MoveDown;
	
	(** move selected shapes to the top **)
	PROCEDURE MoveToTop*;
	BEGIN
		MoveSelection(Figures.Top)
	END MoveToTop;
	
	(** move selected shapes to the bottom **)
	PROCEDURE MoveToBottom*;
	BEGIN
		MoveSelection(Figures.Bottom)
	END MoveToBottom;
	
	(** reverse priority of selection **)
	PROCEDURE Reverse*;
	BEGIN
		MoveSelection(Figures.Reverse)
	END Reverse;
	
	(** rearrange selected shapes **)
	PROCEDURE Arrange*;
		CONST
			x = 0; y = 1;
			min = 0; max = 1; mid = 2;
			hResizeMax = 1; hResizeMin = 2;
			vResizeMax = 1; vResizeMin = 2;
			hAlignLeft = 1; hAlignRight = 2; hAlignCenter = 3;
			vAlignBottom = 1; vAlignTop = 2; vAlignCenter = 3;
			hDistribLeft = 4; hDistribRight = 5; hDistribCenter = 6; hDistribSpace = 7;
			vDistribBottom = 4; vDistribTop = 5; vDistribCenter = 6; vDistribSpace = 7;
		
		TYPE
			Reference = POINTER TO RECORD
				shape: Figures.Shape;
				next: Reference;
				c, d: ARRAY 2, 3 OF REAL;
			END;
		
		VAR
			fig: Figures.Figure; sel: Figures.Shape; first, last, ref: Reference; bw: REAL; obj: Objects.Object;
			n: LONGINT; mat: GfxMatrix.Matrix;
		
		PROCEDURE findMax (xy, lo, hi: LONGINT): REAL;
			VAR ref: Reference; max, m: REAL;
		BEGIN
			ref := first; max := ref.c[xy, hi] - ref.c[xy, lo]; ref := ref.next;
			WHILE ref # NIL DO
				m := ref.c[xy, hi] - ref.c[xy, lo];
				IF m > max THEN max := m END;
				ref := ref.next
			END;
			RETURN max
		END findMax;
		
		PROCEDURE setDim (xy: LONGINT; dim: REAL);
			VAR ref: Reference; d: REAL;
		BEGIN
			ref := first;
			WHILE ref # NIL DO
				d := 0.5*(dim - ref.c[xy, max] + ref.c[xy, min]);
				ref.d[xy, min] := -d; ref.d[xy, max] := d;
				ref := ref.next
			END
		END setDim;
		
		PROCEDURE align (xy, m: LONGINT; step: REAL);
			VAR ref: Reference; to, d: REAL;
		BEGIN
			ref := first; to := ref.c[xy, m] + ref.d[xy, m]; ref := ref.next;
			WHILE ref # NIL DO
				to := to + step;
				d := to - ref.c[xy, m] - ref.d[xy, m];
				ref.d[xy, min] := ref.d[xy, min] + d;
				ref.d[xy, max] := ref.d[xy, max] + d;
				ref := ref.next
			END
		END align;
		
		PROCEDURE sort (xy, m: LONGINT);
			VAR sent, cand, ref: Reference; max, t: REAL;
		BEGIN
			NEW(sent); sent.next := first; first := NIL;
			WHILE sent.next # NIL DO
				cand := sent; max := cand.next.c[xy, m] + cand.next.d[xy, m];
				ref := cand.next;
				WHILE ref.next # NIL DO
					t := ref.next.c[xy, m] + ref.next.d[xy, m];
					IF t > max THEN cand := ref; max := t END;
					ref := ref.next
				END;
				ref := cand.next; cand.next := ref.next;
				ref.next := first; first := ref
			END;
			last := first;
			WHILE ref.next # NIL DO last := last.next END
		END sort;
		
		PROCEDURE distribute (xy, m: LONGINT);
			VAR step: REAL;
		BEGIN
			sort(xy, m);
			step := ((last.c[xy, m] + last.d[xy, m]) - (first.c[xy, m] + first.d[xy, m]))/(n-1);
			align(xy, m, step)
		END distribute;
		
		PROCEDURE distribSpace (xy: LONGINT);
			VAR ref: Reference; sum, step, to, d: REAL;
		BEGIN
			sort(xy, mid);
			ref := first; sum := 0;
			WHILE ref # NIL DO
				sum := sum + (ref.c[xy, max] + ref.d[xy, max]) - (ref.c[xy, min] + ref.d[xy, min]);
				ref := ref.next
			END;
			step := ((last.c[xy, max] + last.d[xy, max]) - (first.c[xy, min] + first.d[xy, min]) - sum)/(n-1);
			ref := first; to := ref.c[xy, max] + ref.d[xy, max]; ref := ref.next;
			WHILE ref # NIL DO
				d := to + step - ref.c[xy, min] - ref.d[xy, min];
				ref.d[xy, min] := ref.d[xy, min] + d;
				ref.d[xy, max] := ref.d[xy, max] + d;
				to := ref.c[xy, max] + ref.d[xy, max];
				ref := ref.next
			END
		END distribSpace;
		
	BEGIN
		FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, sel);
			IF (sel # NIL) & (sel.slink # NIL) THEN
				NEW(first); first.shape := sel;
				Figures.GetShapeBox(first.shape, first.c[x, min], first.c[y, min], first.c[x, max], first.c[y, max], bw);
				first.c[x, mid] := 0.5*(first.c[x, min] + first.c[x, max]); first.c[y, mid] := 0.5*(first.c[y, min] + first.c[y, max]);
				first.d[x, min] := 0; first.d[y, min] := 0; first.d[x, max] := 0; first.d[y, max] := 0; first.d[x, mid] := 0; first.d[y, mid] := 0;
				obj := sel.slink; n := 1; last := first;
				WHILE obj # NIL DO
					INC(n);
					NEW(ref); ref.next := first; first := ref; ref.shape := obj(Figures.Shape);
					Figures.GetShapeBox(ref.shape, ref.c[x, min], ref.c[y, min], ref.c[x, max], ref.c[y, max], bw);
					ref.c[x, mid] := 0.5*(ref.c[x, min] + ref.c[x, max]); ref.c[y, mid] := 0.5*(ref.c[y, min] + ref.c[y, max]);
					ref.d[x, min] := 0; ref.d[y, min] := 0; ref.d[x, max] := 0; ref.d[y, max] := 0; ref.d[x, mid] := 0; ref.d[y, mid] := 0;
					obj := obj.slink
				END;
				IF HResize.val = hResizeMax THEN
					setDim(x, findMax(x, min, max))
				ELSIF HResize.val = hResizeMin THEN
					setDim(x, -findMax(x, max, min))
				END;
				IF VResize.val = vResizeMax THEN
					setDim(y, findMax(y, min, max))
				ELSIF VResize.val = vResizeMin THEN
					setDim(y, -findMax(y, max, min))
				END;
				CASE HAlign.val OF
				| hAlignLeft: align(x, min, 0)
				| hAlignRight: align(x, max, 0)
				| hAlignCenter: align(x, mid, 0)
				| hDistribLeft: distribute(x, min)
				| hDistribRight: distribute(x, max)
				| hDistribCenter: distribute(x, mid)
				| hDistribSpace: distribSpace(x)
				ELSE
				END;
				CASE VAlign.val OF
				| vAlignBottom: align(y, min, 0)
				| vAlignTop: align(y, max, 0)
				| vAlignCenter: align(y, mid, 0)
				| vDistribBottom: distribute(y, min)
				| vDistribTop: distribute(y, max)
				| vDistribCenter: distribute(y, mid)
				| vDistribSpace: distribSpace(y)
				ELSE
				END;
				Figures.DisableUpdate(fig);
				Figures.BeginCommand(fig);
				ref := first;
				WHILE ref # NIL DO
					IF (ref.d[x, min] # 0) OR (ref.d[x, max] # 0) OR (ref.d[y, min] # 0) OR (ref.d[y, max] # 0) THEN
						GfxMatrix.Get3PointTransform(
							ref.c[x, min], ref.c[y, min], ref.c[x, min] + ref.d[x, min], ref.c[y, min] + ref.d[y, min],
							ref.c[x, max], ref.c[y, min], ref.c[x, max] + ref.d[x, max], ref.c[y, min] + ref.d[y, min],
							ref.c[x, min], ref.c[y, max], ref.c[x, min] + ref.d[x, min], ref.c[y, max] + ref.d[y, max],
							mat
						);
						ref.shape.slink := NIL;
						Figures.Transform(fig, ref.shape, mat)
					END;
					ref := ref.next
				END;
				Figures.EndCommand(fig);
				Figures.EnableUpdate(fig)
			END
		END
	END Arrange;
	
	
	(**--- (Public) Objects ---**)
	
	PROCEDURE GetObj (VAR name: ARRAY OF CHAR; VAR obj: Objects.Object);
		VAR lib: Objects.Library; ref: INTEGER;
	BEGIN
		lib := Objects.ThisLibrary("Leonardo.Lib");
		IF lib = NIL THEN
			obj := NIL
		ELSE
			Objects.GetRef(lib.dict, name, ref);
			IF ref # MIN(INTEGER) THEN
				lib.GetObj(lib, ref, obj)
			END
		END
	END GetObj;
	
	PROCEDURE GetPublicString* (name: ARRAY OF CHAR; VAR str: BasicGadgets.String);
		VAR obj: Objects.Object;
	BEGIN
		GetObj(name, obj);
		IF (obj # NIL) & (obj IS BasicGadgets.String) THEN
			str := obj(BasicGadgets.String)
		ELSE
			NEW(str)
		END
	END GetPublicString;
	
	PROCEDURE GetPublicBool* (name: ARRAY OF CHAR; VAR bool: BasicGadgets.Boolean);
		VAR obj: Objects.Object;
	BEGIN
		GetObj(name, obj);
		IF (obj # NIL) & (obj IS BasicGadgets.Boolean) THEN
			bool := obj(BasicGadgets.Boolean)
		ELSE
			NEW(bool)
		END
	END GetPublicBool;
	
	PROCEDURE GetPublicInt* (name: ARRAY OF CHAR; VAR int: BasicGadgets.Integer);
		VAR obj: Objects.Object;
	BEGIN
		GetObj(name, obj);
		IF (obj # NIL) & (obj IS BasicGadgets.Integer) THEN
			int := obj(BasicGadgets.Integer)
		ELSE
			NEW(int)
		END
	END GetPublicInt;
	
	PROCEDURE SetStringValue* (obj: Objects.Object; val: ARRAY OF CHAR);
		VAR old: ARRAY 64 OF CHAR;
	BEGIN
		Attributes.GetString(obj, "Value", old);
		IF val # old THEN
			Attributes.SetString(obj, "Value", val);
			Gadgets.Update(obj)
		END
	END SetStringValue;
	
	PROCEDURE SetIntValue* (obj: Objects.Object; val: LONGINT);
		VAR old: LONGINT;
	BEGIN
		Attributes.GetInt(obj, "Value", old);
		IF val # old THEN
			Attributes.SetInt(obj, "Value", val);
			Gadgets.Update(obj)
		END
	END SetIntValue;
	

BEGIN
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Leonardo 1.30/eos 21.4.99"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf);
	RulerFont := Fonts.This("Courier10.Scn.Fnt");
	GetPublicInt("HResize", HResize);
	GetPublicInt("VResize", VResize);
	GetPublicInt("HAlign", HAlign);
	GetPublicInt("VAlign", VAlign)
END Leonardo.
