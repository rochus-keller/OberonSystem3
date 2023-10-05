MODULE LeoText;	(** eos   **)

	(**
		Leonardo text shapes
	**)
	
	IMPORT
		Files, Math, Objects, Fonts, Display, Input, Texts, Oberon, Strings, Display3, Effects, Attributes, Gadgets, BasicGadgets,
		GfxMatrix, GfxMaps, GfxFonts, Gfx, Solver, Figures, LeoFrames, Leonardo;
		
	
	CONST
		Consume* = 0; Accept* = 1; Release* = 2;	(** focus msg id **)
		
		BaseAlloc = 32;
		CursorLeft = 0C4X; CursorRight = 0C3X; BackSpace = 7FX; Delete = 0A1X; Home = 0A8X; End = 0A9X;
		DefaultSize = 12;
		
		ML = 2; MM = 1; MR = 0;
		
	
	TYPE
		Text = POINTER TO ARRAY OF CHAR;
		
		Caption* = POINTER TO CaptionDesc;
		CaptionDesc* = RECORD (Figures.ShapeDesc)
			text: Text;	(* characters that form the caption *)
			len: LONGINT;	(* number of characters in caption *)
			font: GfxFonts.Font;	(* font used for drawing the caption *)
			size: REAL;	(* point size of caption font *)
			color: Gfx.Color;	(* caption color *)
			mat: GfxMatrix.Matrix;	(* mapping from local to figure coordinates *)
			caret: LONGINT;	(* logical caret position, negative if not holding focus *)
			mfont: GfxFonts.Font;	(* font used for calculating metrics *)
			mlen: REAL;	(* length in figure space along baseline according to metrics *)
			mmat: GfxMatrix.Matrix;	(* transformation from metrics space to figure space *)
		END;
		
		EditAction = POINTER TO EditActionDesc;
		EditActionDesc = RECORD (Figures.ActionDesc)
			cap: Caption;
			pos: LONGINT;
			insert: BOOLEAN;
			char: CHAR;
		END;
		
		StyleAction = POINTER TO StyleActionDesc;
		StyleActionDesc = RECORD (Figures.ActionDesc)
			cap: Caption;
			font: ARRAY 64 OF CHAR;
			size: REAL;
			color: Gfx.Color;
		END;
		
		(** message for managing the focus shape **)
		FocusMsg* = RECORD (Figures.ShapeMsg)
			id*: INTEGER;	(** Consume/Accept/Release **)
			char*: CHAR;	(** character to consume **)
			fx*, fy*: REAL;	(** focus coordinates **)
			shape*: Figures.Shape;	(** shape accepting the focus **)
			res*: INTEGER;	(** result for consume **)
		END;
		
	
	VAR
		FocusVisible: BOOLEAN;
		FocusX, FocusY: INTEGER;
		CX, CY: REAL;
		FontFamily, FontStyle, FontSize: BasicGadgets.String;
		TextColor: BasicGadgets.Integer;
		Caret: Oberon.Marker;
		CaretFG, CaretBG: Display.Pattern;
		FocusFigure: Figures.Figure;	(* figure containing the focus shape *)
		FocusShape: Figures.Shape;	(* shape receiving characters *)
		
	
	(**--- Focus Management ---**)
	
	PROCEDURE SetFocusShape* (fig: Figures.Figure; shape: Figures.Shape);
	BEGIN
		FocusFigure := fig; FocusShape := shape
	END SetFocusShape;
	
	PROCEDURE SetFocus* (fig: Figures.Figure; fx, fy: REAL; VAR done: BOOLEAN);
		VAR fm: FocusMsg;
	BEGIN
		fm.fig := fig; fm.id := Accept; fm.fx := fx; fm.fy := fy; fm.shape := NIL;
		fig.root.handle(fig.root, fm);
		done := fm.shape # NIL;
		IF done THEN
			SetFocusShape(fig, fm.shape)
		END
	END SetFocus;
	
	PROCEDURE RemoveFocus* (fig: Figures.Figure);
		VAR fm: FocusMsg;
	BEGIN
		IF fig = FocusFigure THEN
			fm.fig := fig; fm.id := Release;
			FocusShape.handle(FocusShape, fm);
			FocusFigure := NIL; FocusShape := NIL
		END
	END RemoveFocus;
	
	PROCEDURE ConsumeChar* (fig: Figures.Figure; ch: CHAR; VAR res: INTEGER);
		VAR fm: FocusMsg;
	BEGIN
		IF fig = FocusFigure THEN
			fm.fig := fig; fm.id := Consume; fm.char := ch; fm.res := -1;
			FocusShape.handle(FocusShape, fm);
			res := fm.res
		END
	END ConsumeChar;
	
	
	(**--- Captions ---**)
	
	PROCEDURE ValidateLen (cap: Caption; VAR w, h: REAL);
		VAR len: REAL;
	BEGIN
		GfxFonts.GetStringWidth(cap.mfont, cap.text^, w, h);
		len := w * w + h * h;
		IF len < 0.0001 THEN
			GfxMatrix.ApplyToVector(cap.mat, 1, 0, w, h);
			len := w * w + h * h
		END;
		cap.mlen := Math.sqrt(len)
	END ValidateLen;
	
	PROCEDURE ValidateMatrix (cap: Caption; VAR mat: GfxMatrix.Matrix);
		VAR w, h, len: REAL;
	BEGIN
		ValidateLen(cap, w, h);
		GfxMatrix.Invert(cap.mfont.mat, mat);
		GfxMatrix.Concat(mat, cap.font.mat, mat);
		GfxMatrix.Rotate(mat, h/cap.mlen, w/cap.mlen, mat);
		GfxMatrix.Concat(mat, cap.mat, cap.mmat)
	END ValidateMatrix;
	
	PROCEDURE ValidateCaption* (cap: Caption);
		VAR mat: GfxMatrix.Matrix;
	BEGIN
		ValidateMatrix(cap, mat);
		GfxMatrix.ApplyToRect(cap.mmat, 0, cap.mfont.ymin, cap.mlen, cap.mfont.ymax, cap.llx, cap.lly, cap.urx, cap.ury);
		IF ABS(cap.mfont.xmin) > ABS(cap.mfont.xmax) THEN
			GfxMatrix.ApplyToDist(cap.mmat, ABS(cap.mfont.xmin), cap.bw)
		ELSE
			GfxMatrix.ApplyToDist(cap.mmat, ABS(cap.mfont.xmax), cap.bw)
		END
	END ValidateCaption;
	
	PROCEDURE GetWH (cap: Caption; len: LONGINT; VAR w, h: REAL);
		VAR ch: CHAR;
	BEGIN
		ch := cap.text[len]; cap.text[len] := 0X;
		GfxFonts.GetStringWidth(cap.mfont, cap.text^, w, h);
		cap.text[len] := ch
	END GetWH;
	
	PROCEDURE SetCaption (cap: Caption; VAR text: ARRAY OF CHAR; len: LONGINT);
		VAR size: LONGINT;
	BEGIN
		size := len+1;	(* need space for 0X *)
		IF (cap.text = NIL) OR (size > LEN(cap.text^)) THEN
			NEW(cap.text, -((-size) DIV BaseAlloc) * BaseAlloc)	(* rounds up to next multiple of BaseAlloc *)
		END;
		COPY(text, cap.text^); cap.len := len
	END SetCaption;
	
	PROCEDURE LocateCaption (cap: Caption; VAR lm: Figures.LocateMsg);
		VAR llx, lly, urx, ury: REAL; inv: GfxMatrix.Matrix;
	BEGIN
		IF lm.stamp # cap.stamp THEN
			cap.stamp := lm.stamp;
			IF (lm.id = Figures.Inside) & (lm.llx <= cap.llx) & (cap.urx <= lm.urx) & (lm.lly <= cap.lly) & (cap.ury <= lm.ury) THEN
				cap.slink := lm.shapes; lm.shapes := cap
			ELSIF (lm.llx <= cap.urx) & (cap.llx <= lm.urx) & (lm.lly <= cap.ury) & (cap.lly <= lm.ury) THEN
				IF lm.id = Figures.Overlap THEN
					GfxMatrix.Invert(cap.mmat, inv);
					GfxMatrix.ApplyToRect(inv, lm.llx, lm.lly, lm.urx, lm.ury, llx, lly, urx, ury);
					IF (llx <= cap.mlen) & (0 <= urx) & (lly <= cap.mfont.ymax) & (cap.mfont.ymin <= ury) THEN
						lm.shapes := cap; cap.slink := NIL
					END
				ELSIF lm.id = Figures.Project THEN
					llx := lm.llx; lly := lm.lly; urx := lm.urx; ury := lm.ury;
					GfxMatrix.Invert(cap.mmat, inv);
					GfxMatrix.ApplyToRect(inv, llx, lly, urx, ury, lm.llx, lm.lly, lm.urx, lm.ury);
					Figures.ProjectToHandles(cap, lm, 0, cap.mfont.ymin, cap.mlen, cap.mfont.ymax);
					IF lm.shapes = cap THEN
						GfxMatrix.Apply(cap.mmat, lm.px, lm.py, lm.px, lm.py)
					END;
					lm.llx := llx; lm.lly := lly; lm.urx := urx; lm.ury := ury
					(*
						perhaps it would be better to align to the baseline on the left and right extremes of the caption as well
					*)
				END
			END
		END
	END LocateCaption;
	
	PROCEDURE DrawCaption (cap: Caption; VAR dm: Figures.DrawMsg);
		VAR ctm, mat: GfxMatrix.Matrix; xmin, ymin, xmax, ymax, w, h, len: REAL;
	BEGIN
		IF dm.all OR (cap.stamp = dm.stamp) THEN
			ctm := dm.ctxt.ctm;
			Gfx.Concat(dm.ctxt, cap.mat);
			GfxMatrix.Concat(cap.font.mat, dm.ctxt.ctm, mat);
			cap.mfont := GfxFonts.Open(cap.font.name, cap.font.ptsize, mat);
			ValidateMatrix(cap, mat);	(* determine metrics font from current rendering context *)
			IF (cap.llx - cap.bw < dm.urx) & (dm.llx < cap.urx + cap.bw) & (cap.lly - cap.bw < dm.ury) & (dm.lly < cap.ury + cap.bw) THEN
				Gfx.SetFont(dm.ctxt, cap.font);
				Gfx.SetFillColor(dm.ctxt, cap.color);
				Gfx.DrawStringAt(dm.ctxt, 0, 0, cap.text^);
				Gfx.Concat(dm.ctxt, mat);
				IF GfxMatrix.Rotated(cap.mfont.mat) THEN
					GfxFonts.GetStringWidth(cap.mfont, cap.text^, w, h);
					GfxMatrix.Rotate(GfxMatrix.Identity, -h/cap.mlen, w/cap.mlen, mat);
					GfxMatrix.ApplyToRect(mat, cap.mfont.xmin, cap.mfont.ymin, cap.mfont.xmax, cap.mfont.ymax, xmin, ymin, xmax, ymax);
				ELSE
					ymin := cap.mfont.ymin; ymax := cap.mfont.ymax
				END;
				IF dm.id = Figures.Full THEN
					IF cap.sel THEN
						Figures.DrawHandles(dm, 0, ymin, cap.mlen, ymax)
					END;
					IF cap.caret >= 0 THEN
						Gfx.SetStrokeColor(dm.ctxt, Gfx.Black);
						Gfx.SetLineWidth(dm.ctxt, 0);
						GetWH(cap, cap.caret, w, h);
						len := Math.sqrt(w * w + h * h);
						Gfx.DrawLine(dm.ctxt, len, ymin, len, ymax, {Gfx.Stroke})
					END
				END
			END;
			Gfx.SetCTM(dm.ctxt, ctm)
		END
	END DrawCaption;
	
	PROCEDURE TransformCaption (cap: Caption; VAR tm: Figures.TransformMsg);
		VAR mat: GfxMatrix.Matrix; id: LONGINT; (*w, h, len: REAL;*)
	BEGIN
		IF (tm.id = Figures.Apply) & (tm.stamp = cap.stamp) THEN
			GfxMatrix.Concat(cap.mat, tm.mat, mat);
			Solver.RegisterObj(cap, id);
			Solver.Assign(Solver.Attr(id, "M00"), Solver.Real(mat[0, 0]));
			Solver.Assign(Solver.Attr(id, "M01"), Solver.Real(mat[0, 1]));
			Solver.Assign(Solver.Attr(id, "M10"), Solver.Real(mat[1, 0]));
			Solver.Assign(Solver.Attr(id, "M11"), Solver.Real(mat[1, 1]));
			Solver.Assign(Solver.Attr(id, "M20"), Solver.Real(mat[2, 0]));
			Solver.Assign(Solver.Attr(id, "M21"), Solver.Real(mat[2, 1]))
		(*
		ELSIF tm.id = Figures.Suggest THEN
			GfxFonts.OpenRaster(cap.mfont);
			GetMetricLen(cap, w, h, len);
			GfxMatrix.Invert(cap.mmat, mat);
			GfxMatrix.Apply(mat, tm.x0, tm.y0, tm.x0, tm.y0);
			GfxMatrix.Apply(mat, tm.x1, tm.y1, tm.x1, tm.y1);
			Figures.SuggestHandleTrafo(tm, 0, cap.mfont.ymin, len, cap.mfont.ymax);
			GfxMatrix.Concat(mat, tm.mat, tm.mat); GfxMatrix.Concat(tm.mat, cap.mmat, tm.mat)
		*)
		ELSE
			Figures.HandleShape(cap, tm)
		END
	END TransformCaption;
	
	PROCEDURE Update (fig: Figures.Figure; cap: Caption; from, to: LONGINT);
		VAR w, h, fx, tx, llx, lly, urx, ury, bw: REAL; tm: Figures.TransformMsg; mat: GfxMatrix.Matrix;
	BEGIN
		GetWH(cap, from, w, h);
		fx := Math.sqrt(w * w + h * h);
		IF to = from THEN
			tx := fx + 0.5	(* should prevent update region from becoming empty *)
		ELSE
			GetWH(cap, to, w, h);
			tx := Math.sqrt(w * w + h * h)
		END;
		tm.fig := fig; tm.id := Figures.Get;
		cap.cont.handle(cap.cont, tm);
		GfxMatrix.Concat(cap.mmat, tm.mat, mat);
		GfxMatrix.ApplyToRect(mat, fx, cap.mfont.ymin, tx, cap.mfont.ymax, llx, lly, urx, ury);
		IF ABS(cap.mfont.xmin) > ABS(cap.mfont.xmax) THEN
			GfxMatrix.ApplyToDist(mat, ABS(cap.mfont.xmin), bw)
		ELSE
			GfxMatrix.ApplyToDist(mat, ABS(cap.mfont.xmax), bw)
		END;
		IF cap.sel THEN	(* must update area of middle handle, too *)
			Figures.UpdateRect(fig, llx, lly, urx, ury, bw);
			GfxMatrix.ApplyToRect(mat, 0.5*cap.mlen, cap.mfont.ymin, 0.5*cap.mlen+0.5, cap.mfont.ymax, llx, lly, urx, ury);
			bw := 1
		END;
		Figures.UpdateRect(fig, llx, lly, urx, ury, bw)
	END Update;
	
	PROCEDURE DoEditAction (fig: Figures.Figure; fact: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR act: EditAction; cap: Caption; i, j: LONGINT;
	BEGIN
		act := fact(EditAction);
		cap := act.cap;
		IF cap.caret < 0 THEN
			Oberon.Defocus;
			SetFocusShape(fig, cap)
		END;
		IF undo = act.insert THEN	(* delete character *)
			Update(fig, cap, act.pos, cap.len);	(* must update old bounding box *)
			cap.cont.stamp := stamp;	(* validate container instead *)
			i := act.pos; j := i+1;
			REPEAT
				cap.text[i] := cap.text[j]; i := j; INC(j)
			UNTIL j > cap.len;
			DEC(cap.len); cap.caret := act.pos
		ELSE	(* insert character *)
			j := cap.len; i := j+1; cap.len := i;
			WHILE j >= act.pos DO
				cap.text[i] := cap.text[j]; i := j; DEC(j)
			END;
			cap.text[i] := act.char;
			cap.caret := act.pos+1;
			Update(fig, cap, act.pos, cap.len)
		END;
		ValidateCaption(cap);
		cap.cont.stamp := stamp	(* validate container's bounding box *)
	END DoEditAction;
	
	PROCEDURE AddCommand (fig: Figures.Figure; cap: Caption; pos: LONGINT; insert: BOOLEAN; char: CHAR);
		VAR act: EditAction;
	BEGIN
		Figures.BeginCommand(fig);
		NEW(act); act.cap := cap; act.pos := pos; act.insert := insert; act.char := char;
		Figures.AddAction(fig, act, DoEditAction);
		Figures.EndCommand(fig)
	END AddCommand;
	
	PROCEDURE EditCaption (fig: Figures.Figure; cap: Caption; ch: CHAR);
		VAR text: Text;
	BEGIN
		IF (ch = CursorRight) & (cap.caret < cap.len) THEN
			INC(cap.caret);
			Update(fig, cap, cap.caret-1, cap.caret)
		ELSIF (ch = CursorLeft) & (cap.caret > 0) THEN
			DEC(cap.caret);
			Update(fig, cap, cap.caret, cap.caret+1)
		ELSIF (ch = Home) & (cap.caret > 0) THEN
			Update(fig, cap, cap.caret, cap.caret);
			cap.caret := 0;
			Update(fig, cap, 0, 0)
		ELSIF (ch = End) & (cap.caret < cap.len) THEN
			Update(fig, cap, cap.caret, cap.caret);
			cap.caret := cap.len;
			Update(fig, cap, cap.len, cap.len)
		ELSIF (ch = BackSpace) & (cap.caret > 0) THEN
			DEC(cap.caret);
			AddCommand(fig, cap, cap.caret, FALSE, cap.text[cap.caret])
		ELSIF (ch = Delete) & (cap.caret < cap.len) THEN
			AddCommand(fig, cap, cap.caret, FALSE, cap.text[cap.caret])
		ELSIF (" " <= ch) & (ch < 7FX) OR (80X <= ch) & (ch < 9AX) THEN
			IF cap.len MOD BaseAlloc = BaseAlloc-1 THEN
				NEW(text, cap.len + 1 + BaseAlloc);
				COPY(cap.text^, text^);
				cap.text := text
			END;
			INC(cap.caret);
			AddCommand(fig, cap, cap.caret-1, TRUE, ch)
		END
	END EditCaption;
	
	PROCEDURE FocusCaption (cap: Caption; VAR fm: FocusMsg);
		VAR fx, fy, x0, x1, y1, mx, my: REAL; caret, p0, p1, mp: LONGINT;
	BEGIN
		IF (fm.id = Consume) & (cap.caret >= 0) THEN
			Figures.DisableUpdate(fm.fig);
			EditCaption(fm.fig, cap, fm.char);
			fm.res := 0;
			Figures.EnableUpdate(fm.fig)
		ELSIF fm.id = Accept THEN
			GfxMatrix.Solve(cap.mmat, fm.fx, fm.fy, fx, fy);
			IF (0 <= fx) & (fx <= cap.mlen) & (cap.mfont.ymin <= fy) & (fy <= cap.mfont.ymax) THEN
				IF cap.caret < 0 THEN
					Oberon.Defocus
				END;
				IF cap.len = 0 THEN
					caret := 0
				ELSE
					p0 := 0; x0 := 0;
					p1 := cap.len; GetWH(cap, p1, x1, y1); x1 := Math.sqrt(x1 * x1 + y1 * y1);
					WHILE p0+1 < p1 DO
						mp := (p0 + p1) DIV 2;
						GetWH(cap, mp, mx, my); mx := Math.sqrt(mx * mx + my * my);
						IF mx <= fx THEN p0 := mp; x0 := mx
						ELSE p1 := mp; x1 := mx
						END
					END;
					IF fx - x0 < x1 - fx THEN caret := p0
					ELSE caret := p1
					END
				END;
				IF caret # cap.caret THEN
					Figures.DisableUpdate(fm.fig);
					IF cap.caret >= 0 THEN
						Update(fm.fig, cap, cap.caret, cap.caret)
					END;
					cap.caret := caret;
					Update(fm.fig, cap, caret, caret);
					Figures.EnableUpdate(fm.fig)
				END;
				fm.shape := cap
			END
		ELSIF (fm.id = Release) & (cap.caret >= 0) THEN
			caret := cap.caret; cap.caret := -1;
			IF cap.len = 0 THEN
				cap.slink := NIL;
				Figures.Delete(fm.fig, cap)
			ELSE
				Update(fm.fig, cap, caret, caret)
			END
		END
	END FocusCaption;
	
	PROCEDURE HandleAttr (cap: Caption; VAR am: Objects.AttrMsg);
		VAR len: LONGINT;
	BEGIN
		IF am.id = Objects.enum THEN
			am.Enum("Text"); am.Enum("Font"); am.Enum("Size"); am.Enum("Color");
			am.Enum("M00"); am.Enum("M01"); am.Enum("M10"); am.Enum("M11"); am.Enum("M20"); am.Enum("M21");
			Figures.HandleShape(cap, am)
		ELSIF am.id = Objects.get THEN
			IF am.name = "Gen" THEN
				am.class := Objects.String; am.s := "LeoText.NewCaption"; am.res := 0
			ELSIF am.name = "Text" THEN
				am.class := Objects.String; COPY(cap.text^, am.s); am.res := 0
			ELSIF am.name = "Font" THEN
				am.class := Objects.String; COPY(cap.font.name, am.s); am.res := 0
			ELSIF am.name = "Size" THEN
				am.class := Objects.Real; am.x := cap.size; am.res := 0
			ELSIF am.name = "Color" THEN
				am.class := Objects.Int; am.res := 0;
				am.i := GfxMaps.BestIndex(GfxMaps.DisplayPal, cap.color.r, cap.color.g, cap.color.b)
			ELSIF (am.name[0] = "M") & ("0" <= am.name[1]) & (am.name[1] <= "2") & ("0" <= am.name[2]) &
				(am.name[2] <= "1") & (am.name[3] = 0X)
			THEN
				am.class := Objects.Real; am.x := cap.mat[ORD(am.name[1]) - ORD("0"), ORD(am.name[2]) - ORD("0")];
				am.res := 0
			ELSE
				Figures.HandleShape(cap, am)
			END
		ELSIF am.id = Objects.set THEN
			IF (am.name = "Text") & (am.class = Objects.String) THEN
				len := 0;
				WHILE am.s[len] # 0X DO INC(len) END;
				SetCaption(cap, am.s, len);
				am.res := 0
			ELSIF (am.name = "Font") & (am.class = Objects.String) THEN
				cap.font := GfxFonts.OpenSize(am.s, SHORT(ENTIER(cap.size))); am.res := 0
			ELSIF (am.name = "Size") & (am.class IN {Objects.Int, Objects.Real, Objects.LongReal}) THEN
				IF am.class = Objects.Real THEN am.i := ENTIER(am.x)
				ELSIF am.class = Objects.LongReal THEN am.i := ENTIER(am.y)
				END;
				cap.font := GfxFonts.OpenSize(cap.font.name, SHORT(am.i)); cap.size := am.x; am.res := 0
			ELSIF (am.name = "Color") & (am.class = Objects.Int) & (am.i < 256) THEN
				cap.color := GfxMaps.DisplayPal.col[am.i]; am.res := 0
			ELSIF (am.name[0] = "M") & ("0" <= am.name[1]) & (am.name[1] <= "2") & ("0" <= am.name[2]) &
				(am.name[2] <= "1") & (am.name[3] = 0X) & (am.class IN {Objects.Int, Objects.Real, Objects.LongReal})
			THEN
				IF am.class = Objects.Int THEN am.x := am.i ELSIF am.class = Objects.LongReal THEN am.x := SHORT(am.y) END;
				cap.mat[ORD(am.name[1]) - ORD("0"), ORD(am.name[2]) - ORD("0")] := am.x; am.res := 0
			ELSE
				Figures.HandleShape(cap, am)
			END;
			IF am.res >= 0 THEN
				cap.mfont := cap.font; cap.mmat := cap.mat
			END
		END
	END HandleAttr;
	
	PROCEDURE CopyCaption (VAR msg: Objects.CopyMsg; from, to: Caption);
	BEGIN
		Figures.CopyShape(msg, from, to);
		SetCaption(to, from.text^, from.len);
		to.mat := from.mat; to.font := from.font; to.size := from.size; to.color := from.color;
		to.caret := -1;
		IF to.mfont = NIL THEN NEW(to.mfont) END;
		to.mfont := from.mfont; to.mmat := from.mmat; to.mlen := from.mlen
	END CopyCaption;
	
	PROCEDURE HandleCaption (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR cap, copy: Caption; key: INTEGER; ver, col: LONGINT; name: ARRAY 64 OF CHAR;
	BEGIN
		cap := obj(Caption);
		IF msg IS Figures.ShapeMsg THEN
			IF msg IS Figures.LocateMsg THEN
				LocateCaption(cap, msg(Figures.LocateMsg))
			ELSIF msg IS Figures.DrawMsg THEN
				DrawCaption(cap, msg(Figures.DrawMsg))
			ELSIF (msg IS Figures.ValidateMsg) & (msg.stamp = cap.stamp) THEN
				WITH msg: Figures.ValidateMsg DO
					Figures.UpdateShapeRect(cap, msg.fig, msg.mat);
					ValidateCaption(cap);
					Figures.HandleShape(cap, msg)
				END
			ELSIF msg IS Figures.ControlMsg THEN
				WITH msg: Figures.ControlMsg DO
					IF (msg.id = Figures.Remove) & (msg.stamp = cap.stamp) & (cap.caret >= 0) THEN
						cap.caret := -1
					END
				END
			ELSIF msg IS Figures.TransformMsg THEN
				TransformCaption(cap, msg(Figures.TransformMsg))
			ELSIF msg IS FocusMsg THEN
				FocusCaption(cap, msg(FocusMsg))
			ELSE
				Figures.HandleShape(cap, msg)
			END
		ELSIF msg IS Objects.AttrMsg THEN
			HandleAttr(cap, msg(Objects.AttrMsg))
		ELSIF msg IS Objects.CopyMsg THEN
			WITH msg: Objects.CopyMsg DO
				IF msg.stamp # cap.stamp THEN
					NEW(copy); cap.dlink := copy; cap.stamp := msg.stamp;
					CopyCaption(msg, cap, copy)
				END;
				msg.obj := cap.dlink
			END
		ELSIF msg IS Objects.FileMsg THEN
			WITH msg: Objects.FileMsg DO
				Figures.HandleShape(cap, msg);
				IF msg.id = Objects.store THEN
					Files.WriteNum(msg.R, 2);
					Files.WriteNum(msg.R, cap.len);
					Files.WriteString(msg.R, cap.text^);
					Objects.GetKey(cap.lib.dict, cap.font.name, key);
					Files.WriteInt(msg.R, key);
					Files.WriteReal(msg.R, cap.size);
					Files.WriteLInt(msg.R, ASH(cap.color.r, 16) + ASH(cap.color.g, 8) + cap.color.b);
					GfxMatrix.Write(msg.R, cap.mat)
				ELSIF msg.id = Objects.load THEN
					Files.ReadNum(msg.R, ver);
					IF ver = 2 THEN
						Files.ReadNum(msg.R, cap.len);
						NEW(cap.text, -((-cap.len-1) DIV BaseAlloc) * BaseAlloc);
						Files.ReadString(msg.R, cap.text^);
						Files.ReadInt(msg.R, key);
						Objects.GetName(cap.lib.dict, key, name);
						Files.ReadReal(msg.R, cap.size);
						IF cap.size = 0 THEN cap.size := 10 END;
						cap.font := GfxFonts.OpenSize(name, SHORT(ENTIER(cap.size)));
						Files.ReadLInt(msg.R, col);
						cap.color.r := SHORT(ASH(col, -16) MOD 100H);
						cap.color.g := SHORT(ASH(col, -8) MOD 100H);
						cap.color.b := SHORT(col MOD 100H);
						GfxMatrix.Read(msg.R, cap.mat);
						cap.mfont := cap.font; cap.mmat := cap.mat;
						ValidateCaption(cap)
					ELSIF ver = 1 THEN
						HALT(100)	(* should have been handled by legacy loader *)
					END
				END
			END
		ELSE
			Figures.HandleShape(cap, msg)
		END
	END HandleCaption;
	
	PROCEDURE InitCaption* (cap: Caption; x, y: REAL; text: ARRAY OF CHAR);
		VAR len: LONGINT;
	BEGIN
		cap.handle := HandleCaption;
		len := 0; WHILE text[len] # 0X DO INC(len) END;
		SetCaption(cap, text, len);
		GfxMatrix.Translate(GfxMatrix.Identity, x, y, cap.mat);
		cap.font := GfxFonts.OpenSize(GfxFonts.Default.name, DefaultSize); cap.size := DefaultSize;
		cap.color := Gfx.Black;
		cap.caret := -1;
		cap.mfont := cap.font; cap.mmat := cap.mat;
		ValidateCaption(cap)
	END InitCaption;
	
	PROCEDURE NewCaption*;
		VAR cap: Caption;
	BEGIN
		NEW(cap); InitCaption(cap, 0, 0, "");
		Objects.NewObj := cap
	END NewCaption;
	
	PROCEDURE DoStyleAction (fig: Figures.Figure; fact: Figures.Action; stamp: LONGINT; undo: BOOLEAN);
		VAR act: StyleAction; cap: Caption; font: ARRAY 64 OF CHAR; size: REAL; color: Gfx.Color; sm: Figures.SelectMsg;
	BEGIN
		act := fact(StyleAction); cap := act.cap;
		COPY(cap.font.name, font); size := cap.size; color := cap.color;
		cap.font := GfxFonts.OpenSize(act.font, SHORT(ENTIER(act.size))); cap.size := act.size; cap.color := act.color;
		COPY(font, act.font); act.size := size; act.color := color;
		cap.mfont := cap.font; cap.mmat := cap.mat;
		cap.stamp := stamp;
		sm.fig := fig; sm.id := Figures.Set;
		cap.handle(cap, sm)
	END DoStyleAction;
	
	PROCEDURE ChangeStyle* (fig: Figures.Figure; cap: Caption; font: ARRAY OF CHAR; size: REAL; color: Gfx.Color);
		VAR act: StyleAction;
	BEGIN
		Figures.BeginCommand(fig);
		NEW(act); act.cap := cap; COPY(font, act.font); act.size := size; act.color := color;
		Figures.AddAction(fig, act, DoStyleAction);
		Figures.EndCommand(fig)
	END ChangeStyle;
	
	
	(*--- Caption Tool ---*)
	
	PROCEDURE DrawCaret (x, y: INTEGER);
	BEGIN
		DEC(x, 4); DEC(y, 6);
		Effects.OpenCursor(x, y, 9, 20);
		Display.CopyPattern(Display3.textbackC, CaretBG, x, y, Display.paint);
		Display.CopyPattern(Display3.black, CaretFG, x, y, Display.paint)
	END DrawCaret;
	
	PROCEDURE FadeCaret (x, y: INTEGER);
	BEGIN
		Effects.CloseCursor
	END FadeCaret;
	
	PROCEDURE InitCaret;
		VAR p: ARRAY 20 OF SET; i: LONGINT;
	BEGIN
		p[0] := {}; p[1] := {2..3, 5..6}; p[2] := {1, 4, 7};
		FOR i := 3 TO 16 DO p[i] := {4} END; p[6] := {2..6};
		p[17] := {1, 4, 7}; p[18] := {2..3, 5..6}; p[19] := {};
		CaretFG := Display.NewPattern(9, 20, p);
		p[0] := {2..3, 5..6}; p[1] := {1, 4, 7}; p[2] := {0, 2..3, 5..6, 8};
		FOR i := 3 TO 16 DO p[i] := {3, 5} END; p[6] := {1, 7};
		p[17] := {0, 2..3, 5..6, 8}; p[18] := {1, 4, 7}; p[19] := {2..3, 5..6};
		CaretBG := Display.NewPattern(9, 20, p);
		Caret.Draw := DrawCaret; Caret.Fade := FadeCaret
	END InitCaret;
	
	PROCEDURE SetCaptionStyle (cap: Objects.Object);
		VAR name: ARRAY 64 OF CHAR; size: LONGINT;
	BEGIN
		COPY(FontFamily.val, name);
		IF FontStyle.val # "" THEN
			Strings.AppendCh(name, "-");
			Strings.Append(name, FontStyle.val)
		END;
		Attributes.SetString(cap, "Font", name);
		Strings.StrToInt(FontSize.val, size);
		Attributes.SetInt(cap, "Size", size);
		Attributes.SetInt(cap, "Color", TextColor.val)
	END SetCaptionStyle;
	
	PROCEDURE FlipCaptionMarker (mask: Display3.Mask);
		VAR w, h: INTEGER;
	BEGIN
		Display.GetDim(Display.hook, w, h);
		Display3.CopyPattern(mask, Display3.invertC, Display.hook, FocusX, FocusY - h + 1, Display.invert);
		FocusVisible := ~FocusVisible
	END FlipCaptionMarker;
	
	PROCEDURE HideCaptionMarker (mask: Display3.Mask);
	BEGIN
		IF FocusVisible THEN FlipCaptionMarker(mask) END
	END HideCaptionMarker;
	
	PROCEDURE ShowCaptionMarker (mask: Display3.Mask);
	BEGIN
		IF ~FocusVisible THEN FlipCaptionMarker(mask) END
	END ShowCaptionMarker;
	
	PROCEDURE GetText (text: Texts.Text; beg, end: LONGINT; VAR str: ARRAY OF CHAR);
		VAR r: Texts.Reader; i: LONGINT; ch: CHAR;
	BEGIN
		Texts.OpenReader(r, text, beg);
		Texts.Read(r, ch); i := 0;
		WHILE (beg < end) & (i < LEN(str)) & (r.lib IS Fonts.Font) & (ch >= " ") DO
			str[i] := ch;
			Texts.Read(r, ch);
			INC(i); INC(beg)
		END;
		str[i] := 0X
	END GetText;
	
	PROCEDURE ConsumeText (fig: Figures.Figure; text: Texts.Text; beg, end: LONGINT);
		VAR r: Texts.Reader; ch: CHAR; res: INTEGER;
	BEGIN
		Figures.DisableUpdate(fig);
		Figures.BeginCommand(fig);
		Texts.OpenReader(r, text, beg);
		WHILE beg < end DO
			Texts.Read(r, ch);
			IF (r.lib IS Fonts.Font) & (ch >= " ") THEN
				ConsumeChar(fig, ch, res)
			END;
			INC(beg)
		END;
		Figures.EndCommand(fig);
		Figures.EnableUpdate(fig)
	END ConsumeText;
	
	PROCEDURE IntegrateCaption (fig: Figures.Figure; VAR str: ARRAY OF CHAR);
		VAR cap: Caption; llx, lly, urx, ury, dist: REAL; done: BOOLEAN;
	BEGIN
		Figures.DisableUpdate(fig);
		NEW(cap); InitCaption(cap, CX, CY, str);
		SetCaptionStyle(cap);
		LeoFrames.Integrate(fig, NIL, cap);
		Figures.GetShapeBox(cap, llx, lly, urx, ury, dist);
		SetFocus(fig, urx-0.5, 0.5*(lly + ury), done);
		Figures.EnableUpdate(fig)
	END IntegrateCaption;
	
	PROCEDURE TrackCaption (frame: LeoFrames.Frame; VAR msg: Oberon.InputMsg);
		VAR
			fx, fy, mx, my, x, y: INTEGER; px, py: REAL; fig: Figures.Figure; done: BOOLEAN; mask: Display3.Mask;
			keysum, keys: SET; text: Texts.Text; beg, end, time: LONGINT; str: ARRAY 512 OF CHAR;
	BEGIN
		fx := msg.x + frame.X; fy := msg.y + frame.Y;
		LeoFrames.PixelToPoint(frame, msg.X - fx, msg.Y - fy, px, py);
		fig := frame.obj(Figures.Figure);
		Figures.DisableUpdate(fig);
		SetFocus(fig, px, py, done);
		Figures.EnableUpdate(fig);
		IF done THEN
			mx := msg.X; my := msg.Y; keysum := msg.keys;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & ((x # mx) OR (y # my)) THEN
					LeoFrames.PixelToPoint(frame, x - fx, y - fy, px, py);
					Figures.DisableUpdate(fig);
					SetFocus(fig, px, py, done);
					Figures.EnableUpdate(fig);
					mx := x; my := y;
					Oberon.DrawCursor(Oberon.Mouse, Caret, x, y)
				END
			UNTIL keys = {};
			IF keysum = {ML, MM} THEN
				Oberon.GetSelection(text, beg, end, time);
				IF time >= 0 THEN
					ConsumeText(fig, text, beg, end)
				END
			END
		ELSE
			Oberon.RemoveMarks(fx, fy, frame.W, frame.H);
			Gadgets.MakeMask(frame, fx, fy, msg.dlink, mask);
			IF LeoFrames.ToolFrame # frame THEN
				Oberon.Defocus;
				FocusVisible := FALSE;
				LeoFrames.SetToolFrame(frame)
			END;
			keysum := msg.keys; mx := -1; my := -1;
			REPEAT
				Input.Mouse(keys, x, y);
				keysum := keysum + keys;
				IF (keys # {}) & ((x # mx) OR (y # my)) THEN
					Oberon.FadeCursor(Oberon.Mouse);
					HideCaptionMarker(mask);
					LeoFrames.PixelToPoint(frame, x - fx + 0.5, y - fy + 0.5, CX, CY);
					LeoFrames.AlignPoint(frame, CX, CY, CX, CY);
					LeoFrames.PointToPixel(frame, CX, CY, px, py);
					FocusX := fx + SHORT(ENTIER(px)); FocusY := fy + SHORT(ENTIER(py));
					ShowCaptionMarker(mask);
					mx := x; my := y;
					Oberon.DrawCursor(Oberon.Mouse, Caret, x, y)
				END
			UNTIL keys = {};
			IF keysum = {ML, MM} THEN
				Oberon.GetSelection(text, beg, end, time);
				IF time >= 0 THEN
					Oberon.FadeCursor(Oberon.Mouse);
					HideCaptionMarker(mask);
					LeoFrames.ToolFrame := NIL;
					GetText(text, beg, end, str);
					IntegrateCaption(frame.obj(Figures.Figure), str)
				END
			END
		END;
		msg.res := 0
	END TrackCaption;
	
	PROCEDURE HandleCaptionTool (obj: Objects.Object; VAR msg: Objects.ObjMsg);
		VAR frame: LeoFrames.Frame; mask: Display3.Mask; str: ARRAY 512 OF CHAR;
	BEGIN
		frame := obj(LeoFrames.Frame);
		IF msg IS LeoFrames.ToolMsg THEN
			WITH msg: LeoFrames.ToolMsg DO
				IF (msg.id = LeoFrames.Show) & (frame = LeoFrames.ToolFrame) THEN
					Gadgets.MakeMask(frame, msg.x + frame.X, msg.y + frame.Y, msg.dlink, mask);
					ShowCaptionMarker(mask)
				ELSIF (msg.id = LeoFrames.Hide) & (frame = LeoFrames.ToolFrame) THEN
					Gadgets.MakeMask(frame, msg.x + frame.X, msg.y + frame.Y, msg.dlink, mask);
					HideCaptionMarker(mask)
				ELSIF (msg.id = LeoFrames.Deactivate) & (frame.obj = FocusFigure) THEN
					RemoveFocus(FocusFigure)
				END
			END
		ELSIF msg IS Oberon.InputMsg THEN
			WITH msg: Oberon.InputMsg DO
				IF msg.id = Oberon.track THEN
					IF msg.keys = {ML} THEN
						TrackCaption(frame, msg)
					ELSIF msg.keys = {} THEN
						Oberon.DrawCursor(Oberon.Mouse, Caret, msg.X, msg.Y);
						msg.res := 0
					ELSE
						LeoFrames.HandleTool(frame, msg)
					END
				ELSIF msg.id = Oberon.consume THEN
					IF frame = LeoFrames.ToolFrame THEN	(* create new caption *)
						str[0] := msg.ch; str[1] := 0X;
						IntegrateCaption(frame.obj(Figures.Figure), str);
						msg.res := 0
					ELSIF frame.obj = FocusFigure THEN
						ConsumeChar(FocusFigure, msg.ch, msg.res)
					ELSE
						LeoFrames.HandleTool(frame, msg)
					END
				ELSE
					LeoFrames.HandleTool(frame, msg)
				END
			END
		ELSIF msg IS Oberon.ConsumeMsg THEN
			WITH msg: Oberon.ConsumeMsg DO
				IF frame = LeoFrames.ToolFrame THEN	(* create new caption *)
					LeoFrames.SetToolFrame(NIL);
					GetText(msg.text, msg.beg, msg.end, str);
					IntegrateCaption(frame.obj(Figures.Figure), str)
				ELSE
					ConsumeText(frame.obj(Figures.Figure), msg.text, msg.beg, msg.end)
				END
			END
		ELSIF msg IS Oberon.ControlMsg THEN
			WITH msg: Oberon.ControlMsg DO
				IF (frame = LeoFrames.ToolFrame) & (msg.id = Oberon.defocus) THEN
					LeoFrames.SetToolFrame(NIL)
				ELSIF (frame.obj = FocusFigure) & (msg.id IN {Oberon.neutralize, Oberon.defocus}) THEN
					RemoveFocus(FocusFigure)
				END
			END
		ELSE
			LeoFrames.HandleTool(frame, msg)
		END
	END HandleCaptionTool;
	
	(** install caption tool **)
	PROCEDURE SetCaptionTool*;
	BEGIN
		LeoFrames.SetTool(HandleCaptionTool)
	END SetCaptionTool;
	
	(** apply attributes of current text selection to corresponding public objects **)
	PROCEDURE InspectTextStyle*;
		VAR fig: Figures.Figure; shape: Figures.Shape; name, fam, style, s: ARRAY 64 OF CHAR; i, j, size, color: LONGINT;
	BEGIN
		Leonardo.FindFigure(fig);
		IF fig # NIL THEN
			Figures.GetSelection(fig, shape);
			IF (shape # NIL) & (shape IS Caption) THEN
				Attributes.GetString(shape, "Font", name);
				i := 0;
				WHILE (name[i] # 0X) & (name[i] # "-") DO fam[i] := name[i]; INC(i) END;
				fam[i] := 0X;
				IF name[i] = "-" THEN
					INC(i); j := 0;
					WHILE name[i] # 0X DO style[j] := name[i]; INC(i); INC(j) END;
					style[j] := 0X
				ELSE
					style := ""
				END;
				Leonardo.SetStringValue(FontFamily, fam);
				Leonardo.SetStringValue(FontStyle, style);
				Attributes.GetInt(shape, "Size", size);
				Strings.IntToStr(size, s);
				Leonardo.SetStringValue(FontSize, s);
				Attributes.GetInt(shape, "Color", color);
				Leonardo.SetIntValue(TextColor, color)
			END
		END
	END InspectTextStyle;
	
	(** apply attributes of public objects to current text selection **)
	PROCEDURE ApplyTextStyle*;
		VAR
			fig: Figures.Figure; name: ARRAY 64 OF CHAR; size: LONGINT; color: Gfx.Color; shape: Figures.Shape;
			obj: Objects.Object;
	BEGIN
		Leonardo.FindFigure(fig);
		IF fig # NIL THEN
			COPY(FontFamily.val, name);
			IF FontStyle.val # "" THEN
				Strings.AppendCh(name, "-");
				Strings.Append(name, FontStyle.val)
			END;
			Strings.StrToInt(FontSize.val, size);
			color := GfxMaps.DisplayPal.col[TextColor.val];
			Figures.GetSelection(fig, shape);
			Figures.BeginCommand(fig);
			obj := shape;
			WHILE obj # NIL DO
				IF obj IS Caption THEN
					ChangeStyle(fig, obj(Caption), name, size, color)
				END;
				obj := obj.slink
			END;
			Figures.EndCommand(fig)
		END
	END ApplyTextStyle;
	

BEGIN
	Leonardo.GetPublicString("FontFamily", FontFamily);
	Leonardo.GetPublicString("FontStyle", FontStyle);
	Leonardo.GetPublicString("FontSize", FontSize);
	Leonardo.GetPublicInt("TextColor", TextColor);
	InitCaret
END LeoText.
