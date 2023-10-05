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

MODULE AudioGadgets;	(** portable *) (* EJZ,   *)
	IMPORT Files, Objects, Input, Display, Fonts, Texts, Display3, Oberon, Strings, Effects, Gadgets, BasicGadgets;

	CONST
		CurVer = 0;
		middle = 1;

	TYPE
		LCDFrame* = POINTER TO LCDFrameDesc;
		LCDFrameDesc* = RECORD (Gadgets.FrameDesc)
			val: LONGINT;
			backCol, digiCol, shadowCol: INTEGER;
			digits, width: INTEGER;
			border: INTEGER
		END;
		TrackFrame* = POINTER TO TrackFrameDesc;
		TrackFrameDesc* = RECORD (Gadgets.FrameDesc)
			tobj: Objects.Object;
			tracks, first, val, point, rows, cols: INTEGER
		END;

	PROCEDURE RestoreLCD(F: LCDFrame; Q: Display3.Mask; x, y, w, h: INTEGER; back: BOOLEAN);
		VAR
			ledh, ledw, i, ox, oy: INTEGER;
			val, digi: LONGINT;
			A: Objects.AttrMsg;
		PROCEDURE HLed(x, y: INTEGER; on: BOOLEAN);
			VAR j, col: INTEGER;
		BEGIN
			IF on THEN
				col := F.digiCol
			ELSE
				col := F.shadowCol
			END;
			Display3.ReplConst(Q, col, x+F.width+1, y+(F.width DIV 2)+1, ledw, 1, Display.replace);
			FOR j := 1 TO F.width DIV 2 DO
				Display3.ReplConst(Q, col, x+F.width+1+j, y+(F.width DIV 2)+1-j, ledw-2*j, 1, Display.replace);
				Display3.ReplConst(Q, col, x+F.width+1+j, y+(F.width DIV 2)+1+j, ledw-2*j, 1, Display.replace)
			END
		END HLed;
		PROCEDURE VLed(x, y: INTEGER; on: BOOLEAN);
			VAR j, col: INTEGER;
		BEGIN
			IF on THEN
				col := F.digiCol
			ELSE
				col := F.shadowCol
			END;
			Display3.ReplConst(Q, col, x+(F.width DIV 2)+1, y+F.width+1, 1, ledh, Display.replace);
			FOR j := 1 TO F.width DIV 2 DO
				Display3.ReplConst(Q, col, x+(F.width DIV 2)+1-j, y+F.width+1+j, 1, ledh-2*j, Display.replace);
				Display3.ReplConst(Q, col, x+(F.width DIV 2)+1+j, y+F.width+1+j, 1, ledh-2*j, Display.replace)
			END
		END VLed;
	BEGIN
		IF back THEN
			IF F.obj # NIL THEN
				A.id := Objects.get;
				A.name := "Value";
				A.i := F.val;
				F.obj.handle(F.obj, A);
				F.val := A.i
			END;
			Display3.ReplConst(Q, F.backCol, x, y, w, h, Display.replace);
			IF F.border > 0 THEN
				Display3.Rect3D(Q, Display3.downC, Display3.topC, x, y, w, h, F.border, Display.replace)
			END
		END;
		x := x+F.border;
		y := y+F.border;
		w := w-2*F.border;
		h := h-2*F.border;
		ledh := (h-3*F.width-2) DIV 2;
		ledw := ((w-2*F.digits) DIV F.digits)-2*F.width;
		IF (ledh > 0) & (ledw > 0) THEN
			ox := x+(F.digits-1)*(2*F.width+2+ledw)+(w-F.digits*(2*F.width+2+ledw)) DIV 2;
			oy := y;
			val := F.val;
			FOR i := 0 TO F.digits-1 DO
				digi := val MOD 10;
				HLed(ox, oy, digi IN {0, 2, 3, 5, 6, 8, 9});
				HLed(ox, oy+F.width+ledh, digi IN {2, 3, 4, 5, 6, 8, 9});
				HLed(ox, oy+2*(F.width+ledh), digi IN {0, 2, 3, 5, 6, 7, 8, 9});
				VLed(ox, oy, digi IN {0, 2, 6, 8});
				VLed(ox, oy+F.width+ledh, digi IN {0, 4, 5, 6, 8, 9});
				VLed(ox+(F.width DIV 2)+2+ledw, oy, digi IN {0, 1, 3, 4, 5, 6, 7, 8, 9});
				VLed(ox+(F.width DIV 2)+2+ledw, oy+F.width+ledh, digi IN {0, 1, 2, 3, 4, 7, 8, 9});
				ox := ox-2*F.width-2-ledw;
				val := val DIV 10
			END
		END;
		IF back & (Gadgets.selected IN F.state) THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END RestoreLCD;

	PROCEDURE CopyLCD*(VAR M: Objects.CopyMsg; from, to: LCDFrame);
	BEGIN
		to.val := from.val;
		to.digits := from.digits;
		to.backCol := from.backCol;
		to.digiCol := from.digiCol;
		to.shadowCol := from.shadowCol;
		to.width := from.width;
		to.border := from.border;
		Gadgets.CopyFrame(M, from, to)
	END CopyLCD;

	PROCEDURE LCDHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			Q: Display3.Mask;
			F1: LCDFrame;
			A: Objects.AttrMsg;
	BEGIN
		WITH F: LCDFrame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y;
						w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										RestoreLCD(F, Q, x, y, w, h, TRUE)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										RestoreLCD(F, Q, x, y, w, h, TRUE)
									END
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Gadgets.UpdateMsg THEN
							WITH M: Gadgets.UpdateMsg DO
								IF M.obj = F.obj THEN
									A.id := Objects.get;
									A.name := "Value";
									A.i := F.val;
									M.obj.handle(M.obj, A);
									F.val := A.i;
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreLCD(F, Q, x, y, w, h, FALSE)
								END
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "AudioGadgets.NewLCD";
							M.res := 0
						ELSIF M.name = "Value" THEN
							M.class := Objects.Int;
							M.i := F.val;
							M.res := 0
						ELSIF M.name = "Digits" THEN
							M.class := Objects.Int;
							M.i := F.digits;
							M.res := 0
						ELSIF M.name = "Width" THEN
							M.class := Objects.Int;
							M.i := F.width;
							M.res := 0
						ELSIF M.name = "Border" THEN
							M.class := Objects.Int;
							M.i := F.border;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF M.class = Objects.Int THEN
							IF M.name = "Value" THEN
								F.val := M.i;
								M.res := 0
							ELSIF (M.name = "Digits") & (M.i > 0) & (M.i < 16) THEN
								F.digits := SHORT(M.i);
								M.res := 0
							ELSIF (M.name = "Width") & (M.i > 0) & (M.i < 10) THEN
								F.width := SHORT(M.i + 1 - (M.i MOD 2));
								M.res := 0
							ELSIF (M.name = "Border") & (M.i > 0) & (M.i < 10) THEN
								F.border := SHORT(M.i);
								M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Value");
						M.Enum("Digits");
						M.Enum("Width");
						M.Enum("Border");
						M.res := 0
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						M.obj := F.obj;
						M.res := 0
					ELSIF M.id = Objects.set THEN
						F.obj := M.obj;
						M.res := 0
					ELSE
						Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp;
						F.dlink := F1;
						CopyLCD(M, F, F1);
						M.obj := F1
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					Gadgets.framehandle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteLInt(M.R, F.val);
						Files.WriteInt(M.R, F.digits);
						Files.WriteInt(M.R, F.backCol);
						Files.WriteInt(M.R, F.digiCol);
						Files.WriteInt(M.R, F.shadowCol);
						Files.WriteInt(M.R, F.width);
						Files.WriteInt(M.R, F.border)
					ELSIF M.id = Objects.load THEN
						Files.ReadLInt(M.R, F.val);
						Files.ReadInt(M.R, F.digits);
						Files.ReadInt(M.R, F.backCol);
						Files.ReadInt(M.R, F.digiCol);
						Files.ReadInt(M.R, F.shadowCol);
						Files.ReadInt(M.R, F.width);
						Files.ReadInt(M.R, F.border)
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END LCDHandler;

	PROCEDURE InitLCD*(F: LCDFrame);
	BEGIN
		F.obj := NIL;
		F.W := 40;
		F.H := 40;
		F.val := 0;
		F.digits := 2;
		F.backCol := Display3.black;
		F.digiCol := Display3.green;
		F.shadowCol := F.backCol;
		F.width := 3;
		F.border := 2;
		F.handle := LCDHandler
	END InitLCD;

	PROCEDURE NewLCD*;
		VAR F: LCDFrame;
	BEGIN
		NEW(F);
		InitLCD(F);
		Objects.NewObj := F
	END NewLCD;

	PROCEDURE Calc(F: TrackFrame; VAR x, y, w, h, law, raw, hb, track: INTEGER);
	BEGIN
		INC(x, 1);
		INC(y, 1);
		DEC(w, 2);
		DEC(h, 2);
		F.rows := h DIV 20;
		IF F.rows = 0 THEN
			F.rows := 1
		END;
		hb := h DIV F.rows;
		F.cols := (w-hb) DIV hb;
		law := (w-F.cols*hb) DIV 2;
		raw := w-F.cols*hb-law
	END Calc;

	PROCEDURE UpdateValue(F: TrackFrame; scroll: BOOLEAN): BOOLEAN;
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get;
		A.name := "Value";
		A.class := Objects.Inval;
		A.i := 0;
		A.res := -1;
		F.obj.handle(F.obj, A);
		A.res := -1;
		IF A.class = Objects.Real THEN
			A.i := ENTIER(A.x)
		ELSIF A.class = Objects.LongReal THEN
			A.i := ENTIER(A.y)
		ELSIF A.class = Objects.String THEN
			Strings.StrToInt(A.s, A.i)
		ELSIF A.class # Objects.Int THEN
			RETURN FALSE
		END;
		IF A.i <= 0 THEN
			F.val := 0
		ELSE
			F.val := SHORT(A.i);
			IF scroll & (F.val <= F.tracks) THEN
				IF F.val < F.first THEN
					F.first := F.val
				ELSIF F.val >= (F.first+F.rows*F.cols) THEN
					INC(F.first, F.val-(F.first+F.rows*F.cols)+1)
				END
			END
		END;
		RETURN TRUE
	END UpdateValue;

	PROCEDURE UpdateTracks(F: TrackFrame): BOOLEAN;
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.get;
		A.name := "Value";
		A.class := Objects.Inval;
		A.i := 0;
		A.res := -1;
		F.tobj.handle(F.tobj, A);
		A.res := -1;
		IF A.class = Objects.Real THEN
			A.i := ENTIER(A.x)
		ELSIF A.class = Objects.LongReal THEN
			A.i := ENTIER(A.y)
		ELSIF A.class = Objects.String THEN
			Strings.StrToInt(A.s, A.i)
		ELSIF A.class # Objects.Int THEN
			RETURN FALSE
		END;
		IF A.i >= 0 THEN
			F.tracks := SHORT(A.i);
			IF F.first > F.tracks THEN
				F.first := 1
			END
		ELSE
			RETURN FALSE
		END;
		RETURN TRUE
	END UpdateTracks;

	PROCEDURE RestoreTrack(F: TrackFrame; Q: Display3.Mask; x, y, w, h: INTEGER; update: BOOLEAN);
		VAR
			law, raw, i, j, hb, track: INTEGER;
			cap: ARRAY 4 OF CHAR;
	BEGIN
		IF ~update THEN
			IF (F.obj # NIL) & UpdateValue(F, FALSE) THEN
			END;
			IF (F.tobj # NIL) & UpdateTracks(F) THEN
			END
		END;
		Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, w, h, 1, Display.replace);
		Calc(F, x, y, w, h, law, raw, hb, track);
		IF F.first > 1 THEN
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC, x, y, law, h, 1, Display.replace);
			Display3.CenterString(Q, Display3.FG, x, y, law, h, Fonts.Default, "<", Display.paint)
		ELSE
			Display3.ReplConst(Q, Display3.groupC, x, y, law, h, Display.replace)
		END;
		IF (F.first+F.cols*F.rows) <= F.tracks THEN
			Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC, x+w-raw, y, raw, h, 1, Display.replace);
			Display3.CenterString(Q, Display3.FG, x+w-raw, y, raw, h, Fonts.Default, ">", Display.paint)
		ELSE
			Display3.ReplConst(Q, Display3.groupC, x+w-raw, y, raw, h, Display.replace)
		END;
		track := F.first;
		FOR j := F.rows-1 TO 0 BY-1 DO
			FOR i := 0 TO F.cols-1 DO
				IF track <= F.tracks THEN
					IF track # F.val THEN
						Display3.FilledRect3D(Q, Display3.topC, Display3.bottomC, Display3.textbackC, x+law+i*hb, y+j*hb, hb, hb, 1, Display.replace)
					ELSE
						Display3.FilledRect3D(Q, Display3.bottomC, Display3.topC, Display3.textbackC, x+law+i*hb, y+j*hb, hb, hb, 1, Display.replace)
					END;
					Strings.IntToStr(track, cap);
					Display3.CenterString(Q, Display3.FG, x+law+i*hb, y+j*hb, hb, hb, Fonts.Default, cap, Display.paint)
				ELSE
					Display3.ReplConst(Q, Display3.textbackC, x+law+i*hb, y+j*hb, hb, hb, Display.replace)
				END;
				INC(track)
			END
		END;
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(Q, Display3.white, Display3.selectpat, x, y, x-1, y-1, w+2, h+2, Display.paint)
		END
	END RestoreTrack;

	PROCEDURE Track(F: TrackFrame; x, y: INTEGER; VAR M: Oberon.InputMsg);
		VAR
			keysum: SET;
			w, h, law, raw, hb, track, mx, my, exec: INTEGER;
			Q: Display3.Mask;
		PROCEDURE DrawEffect(mx, my: INTEGER);
			VAR px, py, i, j: INTEGER;
		BEGIN
			exec := -1;
			Oberon.FadeCursor(Oberon.Mouse);
			px := mx-x;
			py := my-y;
			IF px <= law THEN
				IF F.first > 1 THEN
					exec := 0;
					Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x, y, law, h, 1, Display.invert)
				END
			ELSIF px >= (w-raw) THEN
				IF (F.first+F.cols*F.rows) <= F.tracks THEN
					exec := F.tracks+1;
					Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x+w-raw, y, raw, h, 1, Display.invert)
				END
			ELSE
				i := (px-law) DIV hb;
				j := py DIV hb;
				exec := F.first+i+(F.rows-j-1)*F.cols;
				IF (exec >= F.first) & (exec <= F.tracks) THEN
					Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x+law+i*hb, y+j*hb, hb, hb, 1, Display.invert)
				ELSE
					exec := -1
				END
			END
		END DrawEffect;
	BEGIN
		exec := -1;
		Gadgets.MakeMask(F, x, y, M.dlink, Q);
		w := F.W;
		h := F.H;
		Calc(F, x, y, w, h, law, raw, hb, track);
		DrawEffect(M.X, M.Y);
		mx := M.X;
		my := M.Y;
		keysum := M.keys;
		REPEAT
			Effects.TrackMouse(M.keys, M.X, M.Y, Effects.PointHand);
			DrawEffect(mx, my);
			DrawEffect(M.X, M.Y);
			mx := M.X;
			my := M.Y;
			keysum := keysum + M.keys
		UNTIL M.keys = {};
		DrawEffect(mx, my);
		IF keysum = {middle} THEN
			IF (exec >= F.first) & (exec <= F.tracks) THEN
				F.point := exec;
				Gadgets.ExecuteAttr(F, "Cmd", M.dlink, NIL, NIL)
			ELSIF (exec = 0) & (F.first > 1) THEN
				DEC(F.first);
				Gadgets.Update(F)
			ELSIF (exec = (F.tracks+1)) & ((F.first+F.cols*F.rows) <= F.tracks) THEN
				INC(F.first);
				Gadgets.Update(F)
			END;
			M.res := 0
		END
	END Track;

	PROCEDURE CopyTrack*(VAR C: Objects.CopyMsg; VAR F, F1: TrackFrame);
		VAR C1: Objects.CopyMsg;
	BEGIN
		Gadgets.CopyFrame(C, F, F1);
		F1.tracks := F.tracks;
		F1.first := F.first;
		F1.val := F.val;
		F1.point := F.point;
		IF F.tobj # NIL THEN
			IF C.id = Objects.shallow THEN
				F1.tobj := F.tobj
			ELSE
				C1.obj := NIL;
				C1.dlink := NIL;
				C1.id := C.id;
				Objects.Stamp(C1);
				F.tobj.handle(F.tobj, C1);
				F1.tobj := C1.obj
			END
		ELSE
			F1.tobj := NIL
		END
	END CopyTrack;

	PROCEDURE TrackHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			F1: TrackFrame; 
			Q: Display3.Mask;
	BEGIN
		WITH F: TrackFrame DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X;
						y := M.y + F.Y;
						w := F.W;
						h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										RestoreTrack(F, Q, x, y, w, h, FALSE)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, Q);
										Display3.AdjustMask(Q, x + M.u, y + h - 1 + M.v, M.w, M.h);
										RestoreTrack(F, Q, x, y, w, h, FALSE)
									END
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSIF M IS Gadgets.UpdateMsg THEN
							WITH M: Gadgets.UpdateMsg DO
								IF (M.obj = F.obj) & UpdateValue(F, TRUE) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreTrack(F, Q, x, y, w, h, TRUE)
								ELSIF (M.obj = F.tobj) & UpdateTracks(F) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, Q);
									RestoreTrack(F, Q, x, y, w, h, TRUE)
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & (M.keys = {middle}) & Gadgets.InActiveArea(F, M) THEN
									Track(F, x, y, M)
								ELSE
									Gadgets.framehandle(F, M)
								END
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "AudioGadgets.NewTrack";
							M.res := 0
						ELSIF M.name = "Cmd" THEN
							Gadgets.framehandle(F, M);
							IF M.res < 0 THEN
								M.class := Objects.String;
								M.s := "";
								M.res := 0
							END
						ELSIF M.name = "Value" THEN
							M.class := Objects.Int;
							M.i := F.val;
							M.res := 0
						ELSIF M.name = "Tracks" THEN
							M.class := Objects.Int;
							M.i := F.tracks;
							M.res := 0
						ELSIF M.name = "Point" THEN
							M.class := Objects.Int;
							M.i := F.point;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF M.class = Objects.Int THEN
							IF (M.name = "Value") & (M.i >= 0) THEN
								F.val := SHORT(M.i);
								M.res := 0
							ELSIF (M.name = "Tracks") & (M.i > 0) THEN
								F.tracks := SHORT(M.i);
								M.res := 0
							ELSE
								Gadgets.framehandle(F, M)
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Value");
						M.Enum("Tracks");
						M.Enum("Point");
						M.Enum("Cmd");
						M.res := 0
					ELSE
						Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F1);
						F.stamp := M.stamp;
						F.dlink := F1;
						CopyTrack(M, F, F1);
						M.obj := F1
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M:Objects.FileMsg DO
					Gadgets.framehandle(F, M);
					IF M.id = Objects.store THEN
						Files.WriteInt(M.R, CurVer);
						Files.WriteInt(M.R, F.tracks);
						Files.WriteInt(M.R, F.first);
						Files.WriteInt(M.R, F.val);
						Files.WriteInt(M.R, F.point);
						Gadgets.WriteRef(M.R, F.lib, F.tobj)
					ELSIF M.id = Objects.load THEN
						Files.ReadInt(M.R, x);
						IF x # CurVer THEN
							HALT(99)
						END;
						Files.ReadInt(M.R, F.tracks);
						Files.ReadInt(M.R, F.first);
						Files.ReadInt(M.R, F.val);
						Files.ReadInt(M.R, F.point);
						Gadgets.ReadRef(M.R, F.lib, F.tobj)
					END
				END
			ELSIF M IS Objects.LinkMsg THEN
				WITH M: Objects.LinkMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Model" THEN
							M.obj := F.obj;
							M.res := 0
						ELSIF M.name = "Tracks" THEN
							M.obj := F.tobj;
							M.res := 0
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.set THEN
						IF M.name = "Model" THEN
							F.obj := M.obj;
							IF UpdateValue(F, TRUE) THEN
								M.res := 0
							END
						ELSIF M.name = "Tracks" THEN
							F.tobj := M.obj;
							IF UpdateTracks(F) THEN
								M.res := 0
							END
						ELSE
							Gadgets.framehandle(F, M)
						END
					ELSIF M.id = Objects.enum THEN
						Gadgets.framehandle(F, M);
						M.Enum("Tracks");
						M.res := 0
					END
				END
			ELSE
				Gadgets.framehandle(F, M)
			END
		END
	END TrackHandler;

	PROCEDURE InitTrack*(F: TrackFrame);
	BEGIN
		F.handle := TrackHandler;
		F.H := 42;
		F.W := 128;
		F.tracks := 20;
		F.first := 1;
		F.val := 0;
		F.point := 0;
		F.rows := 0;
		F.cols := 0;
		F.obj := NIL;
		F.tobj := NIL
	END InitTrack;

	PROCEDURE NewTrack*;
		VAR F: TrackFrame;
	BEGIN
		NEW(F);
		InitTrack(F);
		Objects.NewObj := F
	END NewTrack;

	PROCEDURE InsertTrack*;
		VAR
			S: Texts.Scanner;
			F: Objects.Object;
			L: Objects.LinkMsg;
	BEGIN
		NewTrack();
		F := Objects.NewObj;
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN
			L.id := Objects.set;
			L.name := "Model";
			L.obj := Gadgets.CreateObject(S.s);
			IF L.obj # NIL THEN
				F.handle(F, L)
			END;
			Texts.Scan(S);
			IF S.class IN {Texts.Name, Texts.String} THEN
				L.name := "Tracks";
				L.obj := Gadgets.CreateObject(S.s);
				IF L.obj # NIL THEN
					F.handle(F, L)
				END
			END
		END;
		Gadgets.Integrate(F);
	END InsertTrack;

	PROCEDURE SeekButtonHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			Q: Display3.Mask;
			keysum: SET;
			A: Objects.AttrMsg;
	BEGIN
		WITH F: BasicGadgets.Button DO
			IF M IS Oberon.InputMsg THEN
				WITH M: Oberon.InputMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						IF (M.id = Oberon.track) & (M.keys = {middle}) & Gadgets.InActiveArea(F, M) THEN
							A.id := Objects.get;
							A.name := "Cmd";
							A.s := "";
							F.handle(F, A);
							x := M.x + F.X;
							y := M.y + F.Y;
							w := F.W;
							h := F.H;
							Gadgets.MakeMask(F, x, y, M.dlink, Q);
							Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x+1, y+1, w-2, h-2, 1, Display.invert);
							keysum := M.keys;
							REPEAT
								Input.Mouse(M.keys, M.X, M.Y);
								Gadgets.Execute(A.s, F, M.dlink, NIL, NIL);
								keysum := keysum + M.keys
							UNTIL M.keys = {};
							Display3.Rect3D(Q, Display3.topC, Display3.bottomC, x+1, y+1, w-2, h-2, 1, Display.invert);
							M.res := 0
						ELSE
							BasicGadgets.ButtonHandler(F, M)
						END
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "AudioGadgets.NewSeekButton";
						M.res := 0
					ELSE
						BasicGadgets.ButtonHandler(F, M)
					END
				END
			ELSE
				BasicGadgets.ButtonHandler(F, M)
			END
		END
	END SeekButtonHandler;

	PROCEDURE NewSeekButton*;
		VAR obj: Objects.Object;
	BEGIN
		obj := Gadgets.CreateObject("BasicGadgets.NewButton");
		obj.handle := SeekButtonHandler;
		Objects.NewObj := obj
	END NewSeekButton;

END AudioGadgets.
