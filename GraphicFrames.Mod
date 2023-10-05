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

MODULE GraphicFrames;	(** portable *) (*NW 18.4.88 / 30.6.93 / JG 27.6.94 ported to System 3*)
	IMPORT Objects, Display, Input, Fonts, Texts, Graphics, Oberon;

	CONST (*update message ids*)
		restore = 0;
		drawobj = 1; drawobjs = 2; drawobjd = 3;
		drawnorm = 4; drawsel = 5; drawdel = 6;

		markW = 5;

	TYPE
		Frame* = POINTER TO FrameDesc;
		Location* = POINTER TO LocDesc;

		LocDesc* = RECORD
				x*, y*: INTEGER;
				next*: Location
			END ;

		FrameDesc* = RECORD (Display.FrameDesc)
				graph*: Graphics.Graph;
				Xg*, Yg*: INTEGER;  (*pos rel to graph origin*)
				X1*, Y1*: INTEGER;  (*right and upper margins*)
				x*, y*, col*: INTEGER;  (*x = X + Xg, y = Y + Yg*)
				marked*, ticked*, focused*: BOOLEAN;
				mark*: LocDesc
			END ;

		DrawMsg* = RECORD (Graphics.Msg)
				f*: Frame;
				x*, y*, col*, mode*: INTEGER
			END ;

		CtrlMsg* = RECORD (Graphics.Msg)
				f*: Frame;
				res*: INTEGER
			END ;

		UpdateMsg = RECORD (Display.FrameMsg)
				id: INTEGER;
				graph: Graphics.Graph;
				obj: Graphics.Object
			END ;

		SelQuery = RECORD (Display.FrameMsg)
				f: Frame; time: LONGINT
			END ;

		FocusQuery = RECORD (Display.FrameMsg)
				f: Frame
			END ;

		PosQuery = RECORD (Display.FrameMsg)
				f: Frame; X, Y: INTEGER
			END ;

		DispMsg = RECORD (Display.FrameMsg)
				x1, y1, w: INTEGER;
				pat: Display.Pattern;
				graph: Graphics.Graph
			END ;

	VAR Crosshair*: Oberon.Marker;
		newcap: Graphics.Caption;
		W: Texts.Writer;

	(*Exported procedures:
		Restore, Focus, Selected, This, Draw, DrawNorm, Erase,
		DrawObj, EraseObj, Change, Defocus, Deselect, Macro, New*)

	PROCEDURE Restore*(F: Frame);
		VAR x, x0, y: INTEGER; M: DrawMsg;
	BEGIN F.X1 := F.X + F.W; F.Y1 := F.Y + F.H;
		F.x := F.X + F.Xg; F.y := F.Y1 + F.Yg; F.marked := FALSE; F.mark.next := NIL;
		Oberon.RemoveMarks(F.X, F.Y, F.W, F.H); Display.ReplConst(F.col, F.X, F.Y, F.W, F.H, 0);
		IF F.ticked THEN
			y := F.Yg MOD 16 + F.Y1 - 16; x0 := F.Xg MOD 16 + F.X;
			WHILE y >= F.Y DO
				x := x0;
				WHILE x < F.X1 DO Display.Dot(Display.FG, x, y, 0); INC(x, 16) END ;
				DEC(y, 16)
			END
		END ;
		M.f := F; M.x := F.x; M.y := F.y; M.col := 0; M.mode := 0; Graphics.Draw(F.graph, M)
	END Restore;

	PROCEDURE Focus*(): Frame;
		VAR FQ: FocusQuery;
	BEGIN FQ.f := NIL; FQ.F := NIL; Display.Broadcast(FQ); RETURN FQ.f
	END Focus;

	PROCEDURE Selected*(): Frame;
		VAR SQ: SelQuery;
	BEGIN SQ.f := NIL; SQ.time := 0; SQ.F := NIL; Display.Broadcast(SQ); RETURN SQ.f
	END Selected;

	PROCEDURE This*(x, y: INTEGER): Frame;
		VAR PQ: PosQuery;
	BEGIN PQ.f := NIL; PQ.X := x; PQ.Y := y; PQ.F := NIL; Display.Broadcast(PQ); RETURN PQ.f
	END This;

	PROCEDURE Draw*(F: Frame);
		VAR UM: UpdateMsg;
	BEGIN UM.id := drawsel; UM.graph := F.graph; UM.F := F; Display.Broadcast(UM)
	END Draw;

	PROCEDURE DrawNorm(F: Frame);
		VAR UM: UpdateMsg;
	BEGIN UM.id := drawnorm; UM.graph := F.graph; UM.F := F; Display.Broadcast(UM)
	END DrawNorm;

	PROCEDURE Erase*(F: Frame);
		VAR UM: UpdateMsg;
	BEGIN UM.id := drawdel; UM.graph := F.graph; UM.F := F; Display.Broadcast(UM)
	END Erase;

	PROCEDURE DrawObj*(F: Frame; obj: Graphics.Object);
		VAR UM: UpdateMsg;
	BEGIN UM.id := drawobj; UM.graph := F.graph; UM.obj := obj; UM.F := F; Display.Broadcast(UM)
	END DrawObj;

	PROCEDURE EraseObj*(F: Frame; obj: Graphics.Object);
		VAR UM: UpdateMsg;
	BEGIN UM.id := drawobjd; UM.graph := F.graph; UM.obj := obj; UM.F := F; Display.Broadcast(UM)
	END EraseObj;

	PROCEDURE Change*(F: Frame; VAR msg: Graphics.Msg);
	BEGIN
		IF F # NIL THEN Erase(F); Graphics.Handle(F.graph, msg); Draw(F) END
	END Change;

	PROCEDURE FlipMark(x, y: INTEGER);
	BEGIN
		Display.ReplConst(Display.FG, x-7, y, 15, 1, 2);
		Display.ReplConst(Display.FG, x, y-7, 1, 15, 2)
	END FlipMark;

	PROCEDURE Unmark*(F: Frame);
		VAR m: Location;
	BEGIN newcap := NIL;
		IF F.marked THEN
			FlipMark(F.mark.x, F.mark.y); m := F.mark.next;
			WHILE m # NIL DO FlipMark(m.x, m.y); m := m.next END ;
			F.marked := FALSE; F.mark.next := NIL
		END
	END Unmark;
	
	PROCEDURE Defocus*(F: Frame);
	BEGIN
		Unmark(F);
		F.focused := FALSE
	END Defocus;

	PROCEDURE Deselect*(F: Frame);
		VAR UM: UpdateMsg;
	BEGIN
		IF F # NIL THEN
			UM.id := drawnorm; UM.graph := F.graph; UM.F := F; Display.Broadcast(UM);
			Graphics.Deselect(F.graph)
		END
	END Deselect;

	PROCEDURE Macro*(VAR Lname, Mname: ARRAY OF CHAR);
		VAR x, y: INTEGER;
			F: Frame;
			mac: Graphics.Macro; mh: Graphics.MacHead;
			L: Graphics.Library;
	BEGIN F := Focus();
		IF F # NIL THEN
			x := F.mark.x - F.x; y := F.mark.y - F.y;
			L := Graphics.ThisLib(Lname, FALSE);
			IF L # NIL THEN
				mh := Graphics.ThisMac(L, Mname);
				IF mh # NIL THEN
					Deselect(F); Defocus(F);
					NEW(mac); mac.x := x; mac.y := y; mac.w := mh.w; mac.h := mh.h;
					mac.mac := mh; mac.do := Graphics.MacMethod; mac.col := Oberon.CurCol;
					Graphics.Add(F.graph, mac); DrawObj(F, mac)
				END
			END
		END
	END Macro;

	PROCEDURE CaptionCopy(F: Frame;
			x1, y1: INTEGER; T: Texts.Text; beg, end: LONGINT): Graphics.Caption;
		VAR ch: CHAR;
			dx, w, x2, y2, w1, h1: INTEGER;
			cap: Graphics.Caption;
			pat: Display.Pattern;
			R: Texts.Reader;
	BEGIN Texts.Write(W, 0DX);
		NEW(cap); cap.len := SHORT(end - beg);
		cap.pos := SHORT(Graphics.T.len)+1; cap.do := Graphics.CapMethod;
		Texts.OpenReader(R, T, beg); Texts.Read(R, ch); W.lib := R.lib; W.col := R.col; w := 0;
		cap.x := x1 - F.x; cap.y := y1 - F.y + R.lib(Fonts.Font).minY;
		WHILE beg < end DO
			Fonts.GetChar(R.lib(Fonts.Font), ch, dx, x2, y2, w1, h1, pat);
			INC(w, dx); INC(beg); Texts.Write(W, ch); Texts.Read(R, ch)
		END ;
		cap.w := w; cap.h := W.lib(Fonts.Font).height; cap.col := W.col;
		Texts.Append(Graphics.T, W.buf); Graphics.Add(F.graph, cap); RETURN cap
	END CaptionCopy;

	PROCEDURE SendCaption(cap: Graphics.Caption);
		VAR M: Oberon.ConsumeMsg;
	BEGIN
		M. text := Graphics.T; M.beg := cap.pos; M.end := M.beg + cap.len; Display.Broadcast(M)
	END SendCaption;

	PROCEDURE Edit(F: Frame; x0, y0: INTEGER; k0: SET);
		VAR obj: Graphics.Object;
			x1, y1, w, h, t: INTEGER;
			beg, end, time: LONGINT;
			k1, k2: SET;
			mark, newmark: Location;
			T: Texts.Text;
			Fd: Frame;
			G: Graphics.Graph;
			CM: CtrlMsg;

		PROCEDURE NewLine(x, y, w, h: INTEGER);
			VAR line: Graphics.Line;
		BEGIN NEW(line); line.col := Oberon.CurCol; line.x := x - F.x; line.y := y - F.y;
			line.w := w; line.h := h; line.do := Graphics.LineMethod; Graphics.Add(G, line)
		END NewLine;

	BEGIN k1 := k0; G := F.graph;
		IF k0 = {1} THEN
			obj := Graphics.ThisObj(G, x0 - F.x, y0 - F.y);
			IF (obj # NIL) & ~obj.selected THEN
				CM.f := F; CM.res := 0; obj.do.handle(obj, CM);
				IF CM.res # 0 THEN (*done*) k0 := {} END
			END
		END ;
		REPEAT Input.Mouse(k2, x1, y1); k1 := k1 + k2;
			DEC(x1, (x1-F.x) MOD 4); DEC(y1, (y1-F.y) MOD 4);
			(*INC(x1, (F.x-x1) MOD 4); INC(y1, (F.y-y1) MOD 4);*)
			Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x1, y1)
		UNTIL  k2 = {};
		Oberon.FadeCursor(Oberon.Mouse);
		IF k0 = {2} THEN (*left key*)
			IF ~F.focused THEN Oberon.Defocus; F.focused := TRUE END;
			w := ABS(x1-x0); h := ABS(y1-y0);
			IF k1 = {2} THEN
				IF (w < 7) & (h < 7) THEN (*set mark*)
					IF (x1 - markW >= F.X) & (x1 + markW < F.X1) &
						(y1 - markW >= F.Y) & (y1 + markW < F.Y1) THEN
						Unmark(F);
						F.mark.x := x1; F.mark.y := y1; F.marked := TRUE; FlipMark(x1, y1)
					END
				ELSE (*draw line*) Deselect(F);
					IF w < h THEN
						IF y1 < y0 THEN y0 := y1 END ;
						NewLine(x0, y0, Graphics.width, h)
					ELSE
						IF x1 < x0 THEN x0 := x1 END ;
						NewLine(x0, y0, w, Graphics.width)
					END ;
					Draw(F)
				END
			ELSIF k1 = {2, 1} THEN (*copy selection to caret mark*)
				Deselect(F); Oberon.GetSelection(T, beg, end, time);
				IF time >= 0 THEN DrawObj(F, CaptionCopy(F, x1, y1, T, beg, end)) END
			ELSIF k1 = {2, 0} THEN
				IF F.marked THEN (*set secondary mark*)
						NEW(newmark); newmark.x := x1; newmark.y := y1; newmark.next := NIL;
					FlipMark(x1, y1); mark := F.mark.next;
					IF mark = NIL THEN F.mark.next := newmark ELSE
						WHILE mark.next # NIL DO mark := mark.next END ;
						mark.next := newmark
					END
				END
			END
		ELSIF k0 = {1} THEN (*middle key*)
			IF k1 = {1} THEN (*move*)
				IF (x0 # x1) OR (y0 # y1) THEN
					Fd := This(x1, y1); Erase(F);
					IF Fd = F THEN  Graphics.Move(G, x1-x0, y1-y0)
					ELSIF (Fd # NIL) & (Fd.graph = G) THEN
						Graphics.Move(G, (x1-Fd.x-x0+F.x) DIV 4 * 4, (y1-Fd.y-y0+F.y) DIV 4 * 4)
					END ;
					Draw(F)
				END
			ELSIF k1 = {1, 2} THEN (*copy*)
				Fd := This(x1, y1);
				IF Fd # NIL THEN DrawNorm(F);
					IF Fd = F THEN Graphics.Copy(G, G, x1-x0, y1-y0)
					ELSE Deselect(Fd);
						Graphics.Copy(G, Fd.graph, (x1-Fd.x-x0+F.x) DIV 4 * 4, (y1-Fd.y-y0+F.y) DIV 4 * 4)
					END ;
					Draw(Fd)
				END
			ELSIF k1 = {1, 0} THEN (*shift graph origin*)
				INC(F.Xg, x1-x0); INC(F.Yg, y1-y0); Restore(F)
			END
		ELSIF k0 = {0} THEN (*right key: select*)
			newcap := NIL;
			IF (ABS(x0-x1) < 7) & (ABS(y0-y1) < 7) THEN
				IF ~(2 IN k1) THEN Deselect(F) END ;
				obj := Graphics.ThisObj(G, x1 - F.x, y1 - F.y);
				IF obj # NIL THEN
					Graphics.SelectObj(G, obj); DrawObj(F, obj);
					IF (k1 = {0, 1}) & (obj IS Graphics.Caption) THEN
						SendCaption(obj(Graphics.Caption))
					END
				END
			ELSE Deselect(F);
				IF x1 < x0 THEN t := x0; x0 := x1; x1 := t END ;
				IF y1 < y0 THEN t := y0; y0 := y1; y1 := t END ;
				Graphics.SelectArea(G, x0 - F.x, y0 - F.y, x1 - F.x, y1 - F.y); Draw(F)
			END
		END
	END Edit;

	PROCEDURE NewCaption(F: Frame; col: INTEGER; font: Fonts.Font);
	BEGIN Texts.Write(W, 0DX);
		NEW(newcap); newcap.x := F.mark.x - F.x; newcap.y := F.mark.y - F.y + font.minY;
		newcap.w := 0; newcap.h := font.height; newcap.col := col;
		newcap.pos := SHORT(Graphics.T.len + 1); newcap.len := 0;
		newcap.do := Graphics.CapMethod; Graphics.Add(F.graph, newcap); W.lib := font
	END NewCaption;

	PROCEDURE InsertChar(F: Frame; ch: CHAR);
		VAR w1, h1: INTEGER; DM: DispMsg; fnt: Fonts.Font;
	BEGIN
        DM.graph := F.graph; fnt := W.lib(Fonts.Font);
		Fonts.GetChar(fnt, ch, DM.w, DM.x1, DM.y1, w1, h1, DM.pat); DEC(DM.y1, fnt.minY);
		IF newcap.x + newcap.w + DM.w + F.x < F.X1 THEN
			DM.F := F; Display.Broadcast(DM); INC(newcap.w, DM.w); INC(newcap.len); Texts.Write(W, ch)
		END ;
		Texts.Append(Graphics.T, W.buf)
	END InsertChar;

	PROCEDURE DeleteChar(F: Frame);
		VAR w1, h1: INTEGER; ch: CHAR; pos: LONGINT;
			DM: DispMsg; R: Texts.Reader; fnt: Fonts.Font;
	BEGIN DM.graph := F.graph;
		IF newcap.len > 0 THEN
			pos := Graphics.T.len; Texts.OpenReader(R, Graphics.T, pos-1);  (*backspace*)
			Texts.Read(R, ch);
			IF ch >= " " THEN fnt := R.lib(Fonts.Font);
				Fonts.GetChar(fnt, ch, DM.w, DM.x1, DM.y1, w1, h1, DM.pat);
				DEC(newcap.w, DM.w); DEC(newcap.len); DEC(DM.y1, fnt.minY);
				DM.F := F; Display.Broadcast(DM); Texts.Delete(Graphics.T, pos-1, pos)
			END
		END
	END DeleteChar;

	PROCEDURE GetSelection(F: Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
		VAR obj: Graphics.Object;
	BEGIN obj := F.graph.sel;
		IF (obj # NIL) & (obj IS Graphics.Caption) & (F.graph.time >= time) THEN
			WITH obj: Graphics.Caption DO beg := obj.pos; end := obj.pos + obj.len END ;
			text := Graphics.T; time := F.graph.time
		END
	END GetSelection;

	PROCEDURE Handle*(G: Objects.Object; VAR M: Objects.ObjMsg);
		VAR x, y: INTEGER;
			DM: DispMsg; dM: DrawMsg;
			G1: Frame;

		PROCEDURE move(G: Frame; dx, dy: INTEGER);
			VAR M: UpdateMsg;
		BEGIN Defocus(G); G.focused := TRUE; Oberon.FadeCursor(Oberon.Mouse);
			M.id := drawdel; M.graph := G.graph;  M.F := G; Display.Broadcast(M);
			Graphics.Move(G.graph, dx, dy); M.id := drawsel; Display.Broadcast(M)
		END move;

	BEGIN
		WITH G: Frame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = G) OR (M.F = NIL) THEN
						IF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF M.id = Oberon.track THEN
									x := M.X - (M.X - G.x) MOD 4; y := M.Y - (M.Y - G.y) MOD 4;
									IF M.keys # {} THEN Edit(G, x, y, M.keys)
									ELSE Oberon.DrawCursor(Oberon.Mouse, Oberon.Arrow, x, y)
									END
								ELSIF (M.id = Oberon.consume) & G.focused THEN
									IF M.ch = 7FX THEN
										IF newcap # NIL THEN DeleteChar(G)
										ELSE Oberon.FadeCursor(Oberon.Mouse); Unmark(G); Erase(G); Graphics.Delete(G.graph)
										END
									ELSIF M.ch = 0A6X THEN Restore(G)
									ELSIF M.ch = 0A7X THEN G.Xg := -1; G.Yg := 0; Restore(G)  (*reset*)
									ELSIF M.ch = 0C1X THEN move(G, 0, 1)
									ELSIF M.ch = 0C2X THEN move(G, 0, -1)
									ELSIF M.ch = 0C3X THEN move(G, 1, 0)
									ELSIF M.ch = 0C4X THEN move(G, -1, 0)
									ELSIF (M.ch >= 20X) & (M.ch <0B0X) THEN
										IF newcap # NIL THEN InsertChar(G, M.ch)
										ELSIF G.marked THEN
											Unmark(G); Deselect(G); NewCaption(G, M.col, M.fnt); InsertChar(G, M.ch)
										END
									END
								END
							END
						ELSIF M IS UpdateMsg THEN
							WITH M: UpdateMsg DO
								IF M.graph = G.graph THEN
									dM.f := G; dM.x := G.x; dM.y := G.y; dM.col := 0;
									CASE M.id OF
									  restore: Restore(G)
									| drawobj:  dM.mode := 0; M.obj.do.draw(M.obj, dM)
									| drawobjs: dM.mode := 1; M.obj.do.draw(M.obj, dM)
									| drawobjd: dM.mode := 3; M.obj.do.draw(M.obj, dM)
									| drawsel:  dM.mode := 0; Graphics.DrawSel(G.graph, dM)
									| drawnorm: dM.mode := 2; Graphics.DrawSel(G.graph, dM)
									| drawdel:  dM.mode := 3; Graphics.DrawSel(G.graph, dM)
									END
								END
							END
						ELSIF M IS SelQuery THEN
							WITH M: SelQuery DO
								IF (G.graph.sel # NIL) & (M.time < G.graph.time) THEN
									M.f := G; M.time := G.graph.time
								END
							END
						ELSIF M IS FocusQuery THEN
							IF G.marked THEN M(FocusQuery).f := G END
						ELSIF M IS PosQuery THEN
							WITH M: PosQuery DO
								IF (G.X <= M.X) & (M.X < G.X1) & (G.Y <= M.Y) & (M.Y < G.Y1) THEN M.f := G END
							END
						ELSIF M IS DispMsg THEN
							DM := M(DispMsg);
							x := G.x + newcap.x + newcap.w; y := G.y + newcap.y;
							IF (DM.graph = G.graph) & (x >= G.X) & (x + DM.w < G.X1) & (y >= G.Y) & (y < G.Y1) THEN
								Display.CopyPattern(Oberon.CurCol, DM.pat, x + DM.x1, y + DM.y1, 2);
								Display.ReplConst(Display.FG, x, y, DM.w, newcap.h, 2)
							END
						ELSIF M IS Oberon.ControlMsg THEN
							WITH M: Oberon.ControlMsg DO
								IF M.id = Oberon.neutralize THEN
									Oberon.RemoveMarks(G.X, G.Y, G.W, G.H); Defocus(G);
									DrawNorm(G); Graphics.Deselect(G.graph)
								ELSIF M.id = Oberon.defocus THEN Defocus(G)
								END
							END
						ELSIF M IS Oberon.SelectMsg THEN
							WITH M: Oberon.SelectMsg DO GetSelection(G, M.text, M.beg, M.end, M.time) END
						ELSIF M IS Display.ModifyMsg THEN
							WITH M: Display.ModifyMsg DO G.Y := M.Y; G.H := M.H; Restore(G) END
						ELSIF M IS Oberon.ConsumeMsg THEN
							WITH M: Oberon.ConsumeMsg DO
								IF G.marked THEN
									DrawObj(G, CaptionCopy(G, G.mark.x, G.mark.y, M.text, M.beg, M.end))
								END
							END
						END
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				Oberon.RemoveMarks(G.X, G.Y, G.W, G.H); Defocus(G);
				NEW(G1); G1^ := G^; M(Objects.CopyMsg).obj := G1
			END
		END
	END Handle;

	(*------------------- Methods -----------------------*)

	PROCEDURE DrawLine(obj: Graphics.Object; VAR M: Graphics.Msg);
		(*M.mode = 0: draw according to state,
				= 1: normal -> selected,
				= 2: selected -> normal,
				= 3: erase*)
		VAR x, y, w, h, col: INTEGER; f: Frame;
	BEGIN 
		WITH M: DrawMsg DO
			x := obj.x + M.x; y := obj.y + M.y; w := obj.w; h := obj.h; f := M.f;
			IF (x+w > f.X) & (x < f.X1) & (y+h > f.Y) & (y < f.Y1) THEN
                Display.SetClip(f.X, f.Y, f.W, f.H);
				IF M.col = Display.BG THEN col := obj.col ELSE col := M.col (*macro*) END ;
				IF (M.mode = 0) & obj.selected OR (M.mode = 1) THEN
					Display.FillPattern(col, Display.grey2, x, y, x, y, w, h, 0)
				ELSIF M.mode = 3 THEN
                    Display.ReplConst(f.col, x, y, w, h, 0)  (*erase*)
				ELSE Display.ReplConst(col, x, y, w, h, 0)
				END;
                Display.ResetClip
			END
		END
	END DrawLine;

	PROCEDURE DrawCaption(obj: Graphics.Object; VAR M: Graphics.Msg);
		VAR x, y, dx, x0, x1, y0, y1, w, h, w1, h1, col: INTEGER;
			f: Frame;
			ch: CHAR; pat: Display.Pattern; fnt: Fonts.Font;
			R: Texts.Reader;
	BEGIN
		WITH M: DrawMsg DO
			x := obj.x + M.x; y := obj.y + M.y; w := obj.w; h := obj.h; f := M.f;
			IF (f.X <= x) & (x <= f.X1) & (f.Y <= y) & (y+h <= f.Y1) THEN
				IF x+w > f.X1 THEN w := f.X1-x END ;
				Texts.OpenReader(R, Graphics.T, obj(Graphics.Caption).pos); Texts.Read(R, ch);
				IF M.mode IN {2, 3} THEN Display.ReplConst(Display.FG, x, y, w, h, 2) END;
				IF M.mode IN {0, 2} THEN
					IF ch >= " " THEN
						IF M.col = Display.BG THEN col := obj.col ELSE col := M.col (*macro*) END ;
						fnt := R.lib(Fonts.Font); x0 := x; y0 := y - fnt.minY;
						LOOP
							Fonts.GetChar(fnt, ch, dx, x1, y1, w1, h1, pat);
							IF x0+x1+w1 <= f.X1 THEN Display.CopyPattern(col, pat, x0+x1, y0+y1, 1) ELSE EXIT END ;
							INC(x0, dx); Texts.Read(R, ch);
							IF ch < " " THEN EXIT END
						END ;
						IF (M.mode = 0) & obj.selected THEN Display.ReplConst(Display.FG, x, y, w, h, 2) END
					END
				ELSIF M.mode = 3 THEN Display.ReplConst(f.col, x, y, w, h, 0)
				END
			END
		END
	END DrawCaption;

	PROCEDURE DrawMacro(obj: Graphics.Object; VAR M: Graphics.Msg);
		VAR x, y, w, h: INTEGER;
			f: Frame; M1: DrawMsg;
	BEGIN
		WITH M: DrawMsg DO
			x := obj.x + M.x; y := obj.y + M.y; w := obj.w; h := obj.h; f := M.f;
			IF (x+w > f.X) & (x < f.X1) & (y+h > f.Y) & (y < f.Y1) THEN
                Display.SetClip(f.X, f.Y, f.W, f.H);
				M1.x := x; M1.y := y;
				IF M.mode = 0 THEN
					M1.f := f; M1.col := obj.col; M1.mode := 0; Graphics.DrawMac(obj(Graphics.Macro).mac, M1);
					IF obj.selected THEN
                      Display.ReplConst(Display.FG, x, y, w, h, 2)
                    END
				ELSIF M.mode < 3 THEN
                  Display.ReplConst(Display.FG, x, y, w, h, 2)
				ELSE Display.ReplConst(f.col, x, y, w, h, 0)
				END;
                Display.ResetClip
			END
		END
	END DrawMacro;

	(*---------------------------------------------------------------*)

	PROCEDURE Open*(G: Frame; graph: Graphics.Graph; X, Y, col: INTEGER; ticked: BOOLEAN); 
	BEGIN G.graph := graph; G.Xg := X; G.Yg := Y; G.col := col; G.marked := FALSE; G.focused := FALSE;
		G.mark.next := NIL; G.ticked := ticked; G.handle := Handle
	END Open;

BEGIN
	Texts.OpenWriter(W);
	Graphics.LineMethod.draw := DrawLine; Graphics.CapMethod.draw := DrawCaption;
	Graphics.MacMethod.draw := DrawMacro
END GraphicFrames.
