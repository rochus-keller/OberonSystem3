MODULE FigureGadgets;	(** eos   **)

	(**
		Frames for displaying and editing figures
	**)

	IMPORT
		Files, Display, Printer, Objects, Oberon, Pictures, Display3, Effects, Gadgets, GfxMatrix, GfxMaps, GfxPictures, GfxPaths,
		GfxRegions, Gfx, GfxRaster, GfxDisplay, GfxBuffer, GfxPrinter, Figures;
		
	
	CONST
		MinFrameScale = 1/16; MaxFrameScale = 16;
		
	
	TYPE
		(** gadgets for displaying and editing figures **)
		Frame* = POINTER TO FrameDesc;
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			col*: Gfx.Color;	(** background color **)
			ox*, oy*: REAL;	(** vector from upper left corner of frame to figure origin in screen space **)
			scale*: REAL;	(** viewport scale factor **)
			buffer: Pictures.Picture;	(* shadow bitmap *)
			bufWidth, bufHeight: INTEGER;	(* used part of shadow bitmap *)
		END;
		
		RegData = RECORD (GfxRegions.EnumData)
			reg: GfxRegions.Region;
			scale: REAL;
			border: INTEGER;
			frame: Frame;
		END;
		
	
	VAR
		ClipPath: GfxPaths.Path;
		ClipReg, ScaleReg, EnumReg: GfxRegions.Region;
		Map: GfxMaps.Map;
		BC: GfxBuffer.Context;
		DC: GfxDisplay.Context;
		PC: GfxPrinter.Context;
		
	
	(*--- Regions ---*)
	
	PROCEDURE AddScaledRect (llx, lly, urx, ury: INTEGER; VAR data: GfxRegions.EnumData);
	BEGIN
		WITH data: RegData DO
			llx := SHORT(ENTIER(llx * data.scale)) - data.border;
			lly := SHORT(ENTIER(lly * data.scale)) - data.border;
			urx := -SHORT(ENTIER(- urx * data.scale)) + data.border;
			ury := -SHORT(ENTIER(- ury * data.scale)) + data.border;
			GfxRegions.AddRect(data.reg, llx, lly, urx, ury)
		END
	END AddScaledRect;
	
	(* convert region from figure space to frame space *)
	PROCEDURE ScaleRegion (src, dst: GfxRegions.Region; scale: REAL; border: INTEGER);
		VAR rdata: RegData;
	BEGIN
		border := -SHORT(ENTIER(-scale * border));
		IF border < Figures.BorderWidth THEN border := Figures.BorderWidth END;
		GfxRegions.Clear(dst);
		rdata.reg := dst; rdata.scale := scale; rdata.border := border;
		GfxRegions.Enumerate(src, src.llx, src.lly, src.urx, src.ury, AddScaledRect, rdata)
	END ScaleRegion;
	
	PROCEDURE AddMaskRect (x, y, w, h: INTEGER);
	BEGIN
		GfxRegions.AddRect(EnumReg, x, y, x + w, y + h)
	END AddMaskRect;
	
	(* convert mask to region *)
	PROCEDURE GetMaskRegion (mask: Display3.Mask; reg: GfxRegions.Region);
	BEGIN
		EnumReg := reg;
		GfxRegions.Clear(EnumReg);
		Display3.EnumRect(mask, mask.X, mask.Y, mask.W, mask.H, AddMaskRect)
	END GetMaskRegion;
	
	
	(*--- Rendering ---*)
	
	(* restore frame background unless transparent *)
	PROCEDURE RestoreBackground (frame: Frame; ctxt: GfxRaster.Context);
		VAR llx, lly, urx, ury: REAL; col: Gfx.Color; fig: Figures.Figure;
	BEGIN
		IF ~(Gadgets.transparent IN frame.state) THEN
			GfxMatrix.Solve(ctxt.ctm, ctxt.clipReg.llx, ctxt.clipReg.lly, llx, lly);
			GfxMatrix.Solve(ctxt.ctm, ctxt.clipReg.urx, ctxt.clipReg.ury, urx, ury);
			Gfx.SetFillColor(ctxt, frame.col);
			Gfx.DrawRect(ctxt, llx, lly, urx, ury, {Gfx.Fill});
			col.r := frame.col.r DIV 2; col.g := frame.col.g DIV 2; col.b := frame.col.b DIV 2;
			Gfx.SetFillColor(ctxt, col);
			fig := frame.obj(Figures.Figure);
			Gfx.DrawRect(ctxt, 3, -3, fig.width, 0, {Gfx.Fill});
			Gfx.DrawRect(ctxt, fig.width, -3, fig.width+3, fig.height-3, {Gfx.Fill});
			Gfx.DrawRect(ctxt, 0, 0, fig.width, fig.height, {Gfx.Stroke})
		END
	END RestoreBackground;
	
	PROCEDURE RestoreDisplay (frame: Frame; fx, fy: INTEGER; clip: GfxRegions.Region);
	BEGIN
		GfxDisplay.SetClipRegion(DC, clip);
		GfxDisplay.SetCoordinates(DC, fx + frame.ox, fy + frame.H + frame.oy, 1.0);	(* default scale uses figure units *)
		GfxDisplay.SetBGColor(DC, frame.col);
		Gfx.Reset(DC);
		Gfx.Scale(DC, frame.scale, frame.scale);	(* now scale to current zoom level *)
		RestoreBackground(frame, DC);
		Figures.Render(frame.obj(Figures.Figure), Figures.Full, DC)
	END RestoreDisplay;
	
	PROCEDURE RestoreBuffer (frame: Frame; clip: GfxRegions.Region);
	BEGIN
		IF (clip.llx > 0) OR (clip.urx < frame.buffer.width) OR (clip.lly > 0) OR (clip.ury < frame.buffer.height) THEN
			GfxPictures.PictToMap(frame.buffer, Map)
		END;
		GfxBuffer.SetCoordinates(BC, frame.ox, frame.H + frame.oy, 1.0);	(* default scale uses figure units *)
		GfxBuffer.SetBGColor(BC, frame.col);
		Gfx.Reset(BC);
		GfxRegions.SetToRect(BC.clipReg, clip.llx, clip.lly, clip.urx, clip.ury);
		Gfx.Scale(BC, frame.scale, frame.scale);
		RestoreBackground(frame, BC);
		Figures.Render(frame.obj(Figures.Figure), Figures.Full, BC);
		GfxPictures.MapToPict(Map, frame.buffer, GfxMaps.DisplayPal)
	END RestoreBuffer;
	
	PROCEDURE RestorePrinter (frame: Frame; fx, fy: INTEGER; clip: GfxRegions.Region);
	BEGIN
		GfxPrinter.Init(PC);
		GfxPrinter.SetClipRegion(PC, clip);
		GfxPrinter.SetCoordinates(PC, fx + PC.scale * frame.ox, fy + PC.scale * (frame.H + frame.oy), 1.0);
		Gfx.Reset(PC);
		Gfx.Scale(PC, frame.scale, frame.scale);
		RestoreBackground(frame, PC);
		Figures.Render(frame.obj(Figures.Figure), Figures.Full, PC)
	END RestorePrinter;
	
	
	(**--- Frame Handler ---**)
	
	PROCEDURE UpdateFrame (frame: Frame; VAR msg: Figures.UpdateMsg);
		VAR fx, fy, x, y, w, h: INTEGER; mask: Display3.Mask; dm: Display.DisplayMsg;
	BEGIN
		IF msg.fig = frame.obj THEN
			fx := msg.x + frame.X; fy := msg.y + frame.Y;
			Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
			ScaleRegion(msg.reg, ScaleReg, frame.scale, msg.bw);
			IF frame.buffer = NIL THEN
				GfxRegions.Shift(ScaleReg, fx + SHORT(ENTIER(frame.ox)), fy + frame.H + SHORT(ENTIER(frame.oy)));
				GetMaskRegion(mask, ClipReg);
				GfxRegions.Intersect(ClipReg, ScaleReg);
				x := ClipReg.llx; y := ClipReg.lly; w := ClipReg.urx - x; h := ClipReg.ury - y;
				IF Gadgets.transparent IN frame.state THEN	(* container must restore background *)
					dm.F := frame; dm.device := Display.screen; dm.id := Display.area;
					dm.u := x - fx; dm.v := y - (fy + frame.H - 1); dm.w := w; dm.h := h;
					Display.Broadcast(dm)
				ELSE
					Oberon.RemoveMarks(x, y, w, h);
					RestoreDisplay(frame, fx, fy, ClipReg)
				END
			ELSE
				GfxRegions.Shift(ScaleReg, SHORT(ENTIER(frame.ox)), frame.H + SHORT(ENTIER(frame.oy)));
				GfxRegions.IntersectRect(ScaleReg, 0, 0, frame.W, frame.H);
				IF msg.stamp # frame.stamp THEN
					frame.stamp := msg.stamp;
					RestoreBuffer(frame, ScaleReg)
				END;
				x := ScaleReg.llx; y := ScaleReg.lly; w := ScaleReg.urx - x; h := ScaleReg.ury - y;
				Oberon.RemoveMarks(fx + x, fy + y, w, h);
				Display3.Pict(mask, frame.buffer, x, y, w, h, fx + x, fy + y, Display.replace);
				INC(x, fx); INC(y, fy)
			END;
			IF Gadgets.selected IN frame.state THEN
				Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, x, y, w, h, Display.paint)
			END
		END
	END UpdateFrame;
	
	PROCEDURE RestoreFrame (frame: Frame; x, y, w, h, fx, fy: INTEGER; mask: Display3.Mask);
	BEGIN
		Oberon.RemoveMarks(fx + x, fy + y, w, h);
		IF frame.buffer = NIL THEN
			GetMaskRegion(mask, ClipReg);
			RestoreDisplay(frame, fx, fy, ClipReg)
		ELSE
			Display3.Pict(mask, frame.buffer, x, y, w, h, fx + x, fy + y, Display.replace)
		END;
		IF Gadgets.selected IN frame.state THEN
			Display3.FillPattern(mask, Display3.white, Display3.selectpat, fx, fy, fx + x, fy + y, w, h, Display.paint)
		END
	END RestoreFrame;
	
	PROCEDURE DisplayFrame (frame: Frame; VAR msg: Display.DisplayMsg);
		VAR fx, fy: INTEGER; mask: Display3.Mask; scale: REAL;
	BEGIN
		IF msg.device = Display.screen THEN
			fx := msg.x + frame.X; fy := msg.y + frame.Y;
			IF (msg.id = Display.full) OR (msg.F = NIL) THEN
				Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
				RestoreFrame(frame, 0, 0, frame.W, frame.H, fx, fy, mask)
			ELSIF msg.id = Display.area THEN
				Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
				Display3.AdjustMask(mask, fx + msg.u, fy + frame.H - 1 + msg.v, msg.w, msg.h);
				RestoreFrame(frame, msg.u, msg.v + frame.H - 1, msg.w, msg.h, fx, fy, mask)
			END
		ELSIF msg.device = Display.printer THEN
			IF msg.id = Display.contents THEN
				GfxPrinter.Init(PC);
				Gfx.Reset(PC);
				Figures.Render(frame.obj(Figures.Figure), Figures.Print, PC);
				Printer.Page(1)
			ELSIF msg.id = Display.full THEN
				Gadgets.MakePrinterMask(frame, msg.x, msg.y, msg.dlink, mask);
				GetMaskRegion(mask, ClipReg);
				RestorePrinter(frame, msg.x, msg.y, ClipReg)
			END
		END
	END DisplayFrame;
	
	PROCEDURE ModifyFrame (frame: Frame; VAR msg: Display.ModifyMsg);
		VAR fw, fh, w, sx, sy, dx, dy, pw, ph: INTEGER; mask: Display3.Mask; visible: BOOLEAN; dst: Pictures.Picture;
	BEGIN
		fw := frame.W; fh := frame.H;
		IF (frame.X # msg.X) OR (frame.Y # msg.Y) OR (fw # msg.W) OR (fh # msg.H) THEN
			IF msg.W > fw THEN w := fw ELSE w := msg.W END;
			IF (frame.buffer = NIL) & (msg.mode = Display.display) THEN
				sx := msg.x + frame.X; sy := msg.y + frame.Y;
				Gadgets.MakeMask(frame, sx, sy, msg.dlink, mask);
				IF (msg.H > fh) & (fh > 0) THEN
					visible := Display3.Visible(mask, sx, sy, w, fh)
				ELSIF (fh > msg.H) & (msg.H > 0) THEN
					visible := Display3.Visible(mask, sx, sy + fh - msg.H, w, msg.H)
				ELSE
					visible := FALSE
				END;
				visible := visible & ~(Gadgets.selected IN frame.state)
			END;
			frame.X := msg.X; frame.Y := msg.Y; frame.W := msg.W; frame.H := msg.H;
			frame.mask := NIL;	(* invalidate mask *)
			IF (msg.W > 0) & (msg.H > 0) THEN
				dx := msg.x + frame.X; dy := msg.y + frame.Y;
				Gadgets.MakeMask(frame, dx, dy, msg.dlink, mask);
				IF (frame.buffer = NIL) & (msg.mode = Display.display) THEN
					GetMaskRegion(mask, ClipReg);
					IF visible & (fh > 0) & (msg.H > 0) THEN	(* copy existing part *)
						IF (msg.H > fh) & Display3.Visible(mask, dx, dy, w, fh) THEN
							Display.CopyBlock(sx, sy, w, fh, dx, dy + msg.H - fh, Display.replace);
							GfxRegions.SubtractRect(ClipReg, dx, dy + msg.H - fh, dx + w, dy + fh)
						ELSIF (msg.H < fh) & Display3.Visible(mask, dx, dy, w, msg.H) THEN
							Display.CopyBlock(sx, sy + fh - msg.H, w, msg.H, dx, dy, Display.replace);
							GfxRegions.SubtractRect(ClipReg, dx, dy, dx + w, dy + msg.H)
						END
					END;
					RestoreDisplay(frame, dx, dy, ClipReg)
				ELSIF (frame.buffer # NIL) & ((msg.W # fw) OR (msg.H # fh)) THEN
					IF (msg.W > frame.buffer.width) OR (msg.H > frame.buffer.height) THEN	(* reallocate buffer *)
						pw := -(-msg.W DIV 32 * 32); ph := -(-msg.H DIV 16 * 16);
						NEW(dst); Pictures.Create(dst, pw, ph, Pictures.colorD)
					ELSE
						dst := frame.buffer
					END;
					IF (fh > 0) & (msg.H > 0) THEN	(* copy existing part *)
						IF msg.H > fh THEN
							Pictures.CopyBlock(frame.buffer, dst, 0, 0, w, fh, 0, msg.H - fh, Display.replace)
						ELSIF msg.H < fh THEN
							Pictures.CopyBlock(frame.buffer, dst, 0, fh - msg.H, w, msg.H, 0, 0, Display.replace)
						END
					END;
					frame.buffer := dst;
					IF (msg.W > fw) OR (msg.H > fh) THEN
						GfxRegions.SetToRect(ClipReg, 0, 0, msg.W, msg.H);
						GfxRegions.SubtractRect(ClipReg, 0, msg.H - fh, fw, fh);
						RestoreBuffer(frame, ClipReg)
					END;
					IF msg.mode = Display.display THEN
						Display3.Pict(mask, frame.buffer, 0, 0, msg.W, msg.H, dx, dy, Display.replace)
					END
				END;
				IF Gadgets.selected IN frame.state THEN
					Display3.FillPattern(mask, Display3.white, Display3.selectpat, dx, dy, dx, dy, msg.W, msg.H, Display.paint)
				END
			END
		END
	END ModifyFrame;
	
	PROCEDURE SelectFrame (frame: Frame; VAR msg: Display.SelectMsg);
		VAR fig: Figures.Figure; sel: Figures.Shape;
	BEGIN
		IF msg.id = Display.get THEN
			fig := frame.obj(Figures.Figure);
			IF fig.selTime > msg.time THEN
				Figures.GetSelection(fig, sel);
				IF sel # NIL THEN
					msg.obj := sel; msg.time := fig.selTime; msg.sel := frame
				END
			END
		ELSE
			Gadgets.framehandle(frame, msg)
		END
	END SelectFrame;
	
	PROCEDURE FrameAttr (frame: Frame; VAR msg: Objects.AttrMsg);
		VAR buffered: BOOLEAN;
	BEGIN
		Figures.HandleGenAttr(msg, "FigureGadgets.NewFrame");
		Figures.HandleColorAttr(msg, "Color", frame.col);
		Figures.HandleRealAttr(msg, "Scale", frame.scale);
		buffered := frame.buffer # NIL;
		Figures.HandleBoolAttr(msg, "Buffered", buffered);
		IF (msg.id = Objects.set) & (msg.res >= 0) THEN
			IF (msg.name = "Scale") & (frame.buffer # NIL) THEN
				frame.bufWidth := 0; frame.bufHeight := 0
			ELSIF msg.name = "Buffered" THEN
				IF buffered & (frame.buffer = NIL) THEN
					NEW(frame.buffer);
					frame.bufWidth := 0; frame.bufHeight := 0
				ELSIF ~buffered & (frame.buffer # NIL) THEN
					frame.buffer := NIL
				END
			END
		ELSIF msg.id = Objects.enum THEN
			msg.Enum("Transparent");
			Gadgets.framehandle(frame, msg)	
		ELSIF msg.name = "Transparent" THEN
			IF msg.id = Objects.get THEN
				msg.class := Objects.Bool; msg.b := Gadgets.transparent IN frame.state; msg.res := 0
			ELSIF (msg.id = Objects.set) & (msg.class = Objects.Bool) THEN
				IF msg.b THEN INCL(frame.state, Gadgets.transparent) ELSE EXCL(frame.state, Gadgets.transparent) END;
				msg.res := 0
			END
		ELSIF msg.res < 0 THEN
			Gadgets.framehandle(frame, msg)
		END
	END FrameAttr;
	
	(** copy frame contents **)
	PROCEDURE CopyFrame* (VAR msg: Objects.CopyMsg; from, to: Frame);
	BEGIN
		Gadgets.CopyFrame(msg, from, to);
		to.col := from.col; to.ox := from.ox; to.oy := from.oy; to.scale := from.scale;
		IF from.buffer # NIL THEN
			IF to.buffer = NIL THEN
				NEW(to.buffer)
			END;
			to.bufWidth := 0; to.bufHeight := 0
		END
	END CopyFrame;
	
	(** frame I/O **)
	PROCEDURE WriteFrame* (VAR r: Files.Rider; frame: Frame);
		VAR m: GfxMatrix.Matrix;
	BEGIN
		Files.WriteNum(r, 3);
		Files.WriteBool(r, frame.buffer # NIL);
		Files.WriteInt(r, frame.col.r); Files.WriteInt(r, frame.col.g); Files.WriteInt(r, frame.col.b);
		Files.WriteReal(r, frame.scale);
		Files.WriteReal(r, frame.ox);
		Files.WriteReal(r, frame.oy)
	END WriteFrame;
	
	PROCEDURE ReadFrame* (VAR r: Files.Rider; frame: Frame);
		VAR ver, col: LONGINT; set: SET; buffered: BOOLEAN; dummy: REAL; int: INTEGER;
	BEGIN
		Files.ReadNum(r, ver);
		IF ver = 1 THEN
			Files.ReadSet(r, set);
			buffered := (2 IN set);
			Files.ReadReal(r, dummy);
			Files.ReadInt(r, int);
			frame.col := GfxMaps.DisplayPal.col[int]
		ELSIF ver >= 2 THEN
			Files.ReadBool(r, buffered);
			IF ver = 2 THEN
				Files.ReadLInt(r, col);
				frame.col.r := SHORT(ASH(col, -16) MOD 100H);
				frame.col.g := SHORT(ASH(col, -8) MOD 100H);
				frame.col.b := SHORT(col MOD 100H)
			ELSIF ver >= 3 THEN
				Files.ReadInt(r, frame.col.r); Files.ReadInt(r, frame.col.g); Files.ReadInt(r, frame.col.b)
			END
		END;
		IF ver >= 1 THEN
			Files.ReadReal(r, frame.scale);
			Files.ReadReal(r, frame.ox);
			Files.ReadReal(r, frame.oy)
		END;
		IF buffered THEN
			NEW(frame.buffer);
			frame.bufWidth := 0; frame.bufHeight := 0
		ELSE
			frame.buffer := NIL
		END
	END ReadFrame;
	
	(** default frame handler **)
	PROCEDURE HandleFrame* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame, copy: Frame; fig: Figures.Figure;
	BEGIN
		frame := obj(Frame);
		IF msg IS Display.FrameMsg THEN
			WITH msg: Display.FrameMsg DO
				IF (msg.F = NIL) OR (msg.F = frame) THEN
					IF msg IS Oberon.InputMsg THEN
						WITH msg: Oberon.InputMsg DO
							IF (msg.id = Oberon.track) & Gadgets.InActiveArea(frame, msg) THEN
								Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, msg.X, msg.Y);
								msg.res := 0
							ELSE
								Gadgets.framehandle(frame, msg)
							END
						END
					ELSIF msg IS Oberon.ControlMsg THEN
						WITH msg: Oberon.ControlMsg DO
							IF msg.id = Oberon.neutralize THEN
								fig := frame.obj(Figures.Figure);
								Figures.DisableUpdate(fig);
								Figures.ClearSelection(fig);
								Figures.EnableUpdate(fig)
							END;
							Gadgets.framehandle(frame, msg)
						END
					ELSIF msg IS Figures.UpdateMsg THEN
						UpdateFrame(frame, msg(Figures.UpdateMsg))
					ELSIF msg IS Display.DisplayMsg THEN
						DisplayFrame(frame, msg(Display.DisplayMsg))
					ELSIF msg IS Display.ModifyMsg THEN
						ModifyFrame(frame, msg(Display.ModifyMsg))
					ELSIF msg IS Display.SelectMsg THEN
						SelectFrame(frame, msg(Display.SelectMsg))
					ELSE
						Gadgets.framehandle(frame, msg)
					END
				END
			END
		
		ELSIF msg IS Objects.AttrMsg THEN
			FrameAttr(frame, msg(Objects.AttrMsg))
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # frame.stamp THEN
					NEW(copy); frame.dlink := copy; frame.stamp := msg.stamp;
					CopyFrame(msg, frame, copy)
				END;
				msg.obj := frame.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Gadgets.framehandle(frame, msg);
				IF msg.id = Objects.store THEN
					WriteFrame(msg.R, frame)
				ELSIF msg.id = Objects.load THEN
					ReadFrame(msg.R, frame)
				END
			END
		ELSE
			Gadgets.framehandle(frame, msg)
		END
	END HandleFrame;
	
	(** initialize frame to default values **)
	PROCEDURE InitFrame* (frame: Frame; fig: Figures.Figure);
	BEGIN
		frame.handle := HandleFrame;
		frame.W := 100; frame.H := 100;
		frame.obj := fig;
		frame.col := GfxMaps.DisplayPal.col[Display3.textbackC];
		frame.ox := 0; frame.oy := 0; frame.scale := 1;
		IF fig # NIL THEN
			frame.oy := -(fig.height + 1)
		END
	END InitFrame;
	
	PROCEDURE NewFrame*;
		VAR frame: Frame;
	BEGIN
		NEW(frame); InitFrame(frame, NIL);
		Objects.NewObj := frame
	END NewFrame;
	
	PROCEDURE Update* (frame: Frame);
		VAR cm: Oberon.ControlMsg;
	BEGIN
		cm.F := frame; cm.id := Oberon.defocus;
		Display.Broadcast(cm);
		Gadgets.Update(frame)
	END Update;
	
	PROCEDURE ScrollFrame* (frame: Frame; dx, dy: INTEGER);
	BEGIN
		frame.ox := frame.ox + dx; frame.oy := frame.oy + dy;
		IF frame.buffer # NIL THEN
			frame.bufHeight := 0	(* force buffer redraw *)
		END;
		Update(frame)
	END ScrollFrame;
	
	PROCEDURE ZoomFrame* (frame: Frame; scale: REAL);
		VAR ox, oy: REAL;
	BEGIN
		ox := frame.ox/frame.scale; oy := frame.oy/frame.scale;
		frame.scale := frame.scale * scale;
		IF frame.scale < MinFrameScale THEN frame.scale := MinFrameScale
		ELSIF frame.scale > MaxFrameScale THEN frame.scale := MaxFrameScale
		END;
		frame.ox := ox * frame.scale; frame.oy := oy * frame.scale;
		IF frame.buffer # NIL THEN
			frame.bufHeight := 0	(* force buffer redraw *)
		END;
		Update(frame)
	END ZoomFrame;
	

BEGIN
	NEW(ClipPath);
	NEW(ClipReg); GfxRegions.Init(ClipReg, GfxRegions.Winding);
	NEW(ScaleReg); GfxRegions.Init(ScaleReg, GfxRegions.Winding);
	NEW(DC); GfxDisplay.Init(DC, 0, 0, Display.Width, Display.Height);
	NEW(Map); NEW(BC); GfxBuffer.Init(BC, Map);
	NEW(PC)
END FigureGadgets.
