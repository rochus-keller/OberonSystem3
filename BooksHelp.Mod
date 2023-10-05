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

MODULE BooksHelp;	(** portable *)
	IMPORT Texts, Display, Objects, Effects, Gadgets, Oberon, Display3;
	
	CONST
		qmW = 8; qmH = 13;
		bookW = 32; bookH = 32;

	TYPE
		(* the help icon gadget *)
		Frame = POINTER TO FrameDesc;
		FrameDesc = RECORD (Gadgets.FrameDesc)
		END;
	
	VAR
		W: Texts.Writer;
		(* patterns *)
		MagnifyHand*: Oberon.Marker;
		qm: ARRAY qmH OF SET;
		qmp: Display.Pattern;
		book: ARRAY 5, bookH OF SET;
		bookp: ARRAY 5 OF Display.Pattern;
	
(* initialize pattern for question mark *)
	PROCEDURE InitQM();
	BEGIN
		qm[0] := {3, 4};
		qm[1] := {3, 4};
		qm[2] := {};
		qm[3] := {};
		qm[4] := {3, 4};
		qm[5] := {3, 4};
		qm[6] := {4, 5};
		qm[7] := {5, 6};
		qm[8] := {6, 7};
		qm[9] := {0, 1, 6, 7};
		qm[10] := {0, 1, 6, 7};
		qm[11] := {1, 2, 5, 6};
		qm[12] := {2, 3, 4, 5};
		qmp := Display.NewPattern(qmW, qmH, qm)
	END InitQM;

(* initialize the patterns for the icon *)
	PROCEDURE InitBook();
	BEGIN
		book[0, 0] := {};
		book[0, 1] := {};
		book[0, 2] := {};
		book[0, 3] := {};
		book[0, 4] := {};
		book[0, 5] := {};
		book[0, 6] := {};
		book[0, 7] := {};
		book[0, 8] := {14, 15};
		book[0, 9] := {14, 15};
		book[0, 10] := {};
		book[0, 11] := {};
		book[0, 12] := {14, 15};
		book[0, 13]:= {14, 15};
		book[0, 14] := {14, 15};
		book[0, 15] := {15, 16};
		book[0, 16] := {16, 17};
		book[0, 17] := {11, 12, 17, 18};
		book[0, 18] := {11, 12, 17, 18};
		book[0, 19] := {12, 13, 16, 17};
		book[0, 20] := {13, 14, 15, 16};
		book[0, 21] := {};
		book[0, 22] := {};
		book[0, 23] := {};
		book[0, 24] := {};
		book[0, 25] := {};
		book[0, 26] := {};
		book[0, 27] := {};
		book[0, 28] := {};
		book[0, 29] := {};
		book[0, 30] := {};
		book[0, 31] := {};
		bookp[0] := Display.NewPattern(bookW, bookH, book[0]);

		book[1, 0] := {5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23};
		book[1, 1] := {4, 23};
		book[1, 2] := {4, 23};
		book[1, 3] := {3, 23};
		book[1, 4] := {3, 23};
		book[1, 5] := {3, 23};
		book[1, 6] := {3, 23};
		book[1, 7] := {3, 23};
		book[1, 8] := {3, 23};
		book[1, 9] := {3, 23};
		book[1, 10] := {3, 23};
		book[1, 11] := {3, 23};
		book[1, 12] := {3, 23};
		book[1, 13] := {3, 23};
		book[1, 14] := {3, 23};
		book[1, 15] := {3, 23};
		book[1, 16] := {3, 23};
		book[1, 17] := {3, 23};
		book[1, 18] := {3, 23};
		book[1, 19] := {3, 23};
		book[1, 20] := {3, 23};
		book[1, 21] := {3, 23};
		book[1, 22] := {3, 23};
		book[1, 23] := {3, 23};
		book[1, 24] := {3, 23};
		book[1, 25] := {3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23};
		book[1, 26] := {3, 4};
		book[1, 27] := {3};
		book[1, 28] := {3};
		book[1, 29] := {3};
		book[1, 30] := {3};
		book[1, 31] := {4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20};
		bookp[1] := Display.NewPattern(bookW, bookH, book[1]);

		book[2, 0] := {};
		book[2, 1] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 2] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 3] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 4] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 5] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 6] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 7] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 8] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 9] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 10] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 11] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 12] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 13] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 14] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 15] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 16] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 17] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 18] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 19] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 20] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 21] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 22] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 23] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 24] := {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[2, 25] := {};
		book[2, 26] := {};
		book[2, 27] := {};
		book[2, 28] := {};
		book[2, 29] := {};
		book[2, 30] := {};
		book[2, 31] := {};
		bookp[2] := Display.NewPattern(bookW, bookH, book[2]);

		book[3, 0] := {};
		book[3, 1] := {5};
		book[3, 2] := {5};
		book[3, 3] := {4, 5};
		book[3, 4] := {4, 5};
		book[3, 5] := {4, 5};
		book[3, 6] := {4, 5};
		book[3, 7] := {4, 5};
		book[3, 8] := {4, 5};
		book[3, 9] := {4, 5};
		book[3, 10] := {4, 5};
		book[3, 11] := {4, 5};
		book[3, 12] := {4, 5};
		book[3, 13] := {4, 5};
		book[3, 14] := {4, 5};
		book[3, 15] := {4, 5};
		book[3, 16] := {4, 5};
		book[3, 17] := {4, 5};
		book[3, 18] := {4, 5};
		book[3, 19] := {4, 5};
		book[3, 20] := {4, 5};
		book[3, 21] := {4, 5};
		book[3, 22] := {4, 5};
		book[3, 23] := {4, 5};
		book[3, 24] := {4, 5};
		book[3, 25] := {4};
		book[3, 26] := {};
		book[3, 27] := {6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22};
		book[3, 28] := {};
		book[3, 29] := {5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21};
		book[3, 30] := {};
		book[3, 31] := {};
		bookp[3] := Display.NewPattern(bookW, bookH, book[3]);

		book[4, 0] := {};
		book[4, 1] := {};
		book[4, 2] := {};
		book[4, 3] := {6};
		book[4, 4] := {6};
		book[4, 5] := {6};
		book[4, 6] := {6};
		book[4, 7] := {6};
		book[4, 8] := {6};
		book[4, 9] := {6};
		book[4, 10] := {6};
		book[4, 11] := {6};
		book[4, 12] := {6};
		book[4, 13] := {6};
		book[4, 14] := {6};
		book[4, 15] := {6};
		book[4, 16] := {6};
		book[4, 17] := {6};
		book[4, 18] := {6};
		book[4, 19] := {6};
		book[4, 20] := {6};
		book[4, 21] := {6};
		book[4, 22] := {6};
		book[4, 23] := {6};
		book[4, 24] := {6};
		book[4, 25] := {};
		book[4, 26] := {};
		book[4, 27] := {};
		book[4, 28] := {};
		book[4, 29] := {};
		book[4, 30] := {};
		book[4, 31] := {};
		bookp[4] := Display.NewPattern(bookW, bookH, book[4])
	END InitBook;

(* set Tutorial attribute to be used by the help icon *)
	PROCEDURE SetTutorial*(obj: Objects.Object; val: ARRAY OF CHAR);
		VAR A: Objects.AttrMsg;
	BEGIN
		A.id := Objects.set;
		A.name := "Tutorial";
		COPY(val, A.s);
		A.class := Objects.String;
		A.res := -1;
		Objects.Stamp(A);
		obj.handle(obj, A)
	END SetTutorial;

(* Fade and Draw for the new marker *)

	PROCEDURE *DrawHand (x, y: INTEGER);
	BEGIN
		Effects.PointHand.Draw(x, y);
		IF x < 2 THEN
			x := 2
		ELSIF ((x-2) > Display.Width-qmW) & ((x-2) < Display.Width) THEN
			x := Display.Width-qmW
		END;
		IF y < qmH+10 THEN
			y := qmH
		ELSIF y >= Display.Height-10 THEN
			y := Display.Height - 11
		END;
		Effects.OpenMenu(x-2, y-qmH+10, qmW, qmH);
		Display.CopyPattern(Display3.red, qmp, x-2, y-qmH+10, Display.paint)
	END DrawHand;

	PROCEDURE *Fade(x, y: INTEGER);
	BEGIN
		Effects.CloseMenu();
		(* Effects.CloseCursor() *)
		Effects.PointHand.Fade(x, y)	(* tk *)
	END Fade;
	
(* show the tutorial for the tutorial attribute activator *)
	PROCEDURE ShowDoc(activator: ARRAY OF CHAR);
		VAR
			T: Texts.Text;
			S: Texts.Scanner;
			cmd: ARRAY 32 OF CHAR;
			par: Oberon.ParList;
			res: INTEGER;
	BEGIN
		NEW(T); Texts.Open(T, "");
		Texts.WriteString(W, activator);
		Texts.Append(T, W.buf);
		Texts.OpenScanner(S, T, 0);
		Texts.Scan(S);
		IF S.class = Texts.Name THEN
			NEW(par);
			par^ := Oberon.Par^;
			par.pos := 0;
			par.text := T;
			Texts.Scan(S);
			IF S.class = Texts.Name THEN
				cmd := "Desktops.OpenDoc";
				Oberon.Call(cmd, par, FALSE, res)
			END
		END
	END ShowDoc;

(* definition of the help icon gadget *)

	PROCEDURE RestoreFrame(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
	BEGIN
		Display3.CopyPattern(M, Display3.black, bookp[1], x, y, Display.paint);
		Display3.CopyPattern(M, 14, bookp[2], x, y, Display.paint);
		Display3.CopyPattern(M, 13, bookp[4], x, y, Display.paint);
		Display3.CopyPattern(M, 12, bookp[3], x, y, Display.paint);
		Display3.CopyPattern(M, Display3.red, bookp[0], x, y, Display.paint);
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END RestoreFrame;

	(* mouse tracking, on execute checks for the tutorial attribute of Gadgets.ThisFrame *)
	PROCEDURE Track(VAR M: Oberon.InputMsg);
		VAR
			keysum: SET;
			u, v: INTEGER;
			DF: Display.Frame;
			A: Objects.AttrMsg;
	BEGIN
		(*!!
		EXCL(F.state, Gadgets.nomove);
		*)
		keysum := M.keys;
		WHILE M.keys # {} DO
			keysum := keysum*M.keys;
			Effects.TrackMouse(M.keys, M.X, M.Y, MagnifyHand)
		END;
		IF keysum = {1} THEN
			Gadgets.ThisFrame(M.X + 5, M.Y - 5, DF, u, v);
			IF DF = NIL THEN RETURN END;
			A.id := Objects.get;
			A.name := "Tutorial";
			A.class := Objects.Inval;
			A.s := "";
			A.res := -1;
			Objects.Stamp(A);
			DF.handle(DF, A);
			IF (A.res >= 0) & (A.s # "") THEN
				ShowDoc(A.s)
			END
		END
	END Track;

	PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h, u, v: INTEGER;
			F0: Frame;
			R: Display3.Mask;
	BEGIN
		WITH F: Frame DO
			IF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF  M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "BooksHelp.NewIcon";
							M.res := 0
						ELSE Gadgets.framehandle(F, M)
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F0);
						F.stamp := M.stamp;
						F.dlink := F0;
						Gadgets.CopyFrame(M, F, F0);
						M.obj := F0
					END
				END
			ELSIF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
					u := M.x; v := M.y;
					IF M IS Display.DisplayMsg THEN
						WITH M: Display.DisplayMsg  DO
							IF M.device = Display.screen THEN
								IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									RestoreFrame(F, R, x, y, w, h)
								ELSIF (M.id = Display.area) & (M.F = F) THEN
									Gadgets.MakeMask(F, x, y, M.dlink, R);
									Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
									RestoreFrame(F, R, x, y, w, h)
								END
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSIF M IS Oberon.InputMsg THEN
						WITH M: Oberon.InputMsg DO
							IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) & (M.keys = {1}) THEN
								Track(M);
								M.res := 0
							ELSE Gadgets.framehandle(F, M)
							END
						END
					ELSE Gadgets.framehandle(F, M)
					END;
					M.x := u; M.y := v
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE NewIcon*;
		VAR F: Frame;
	BEGIN
		NEW(F);
		F.handle := FrameHandler;

		F.W := 32; F.H := 32;

		INCL(F.state, Gadgets.lockedsize);
		INCL(F.state, Gadgets.transparent);
		SetTutorial(F, "Tutorials.Book DragHelp");
		Objects.NewObj := F
	END NewIcon;

BEGIN
	Texts.OpenWriter(W);
	InitQM();
	InitBook();
	MagnifyHand.Draw := DrawHand;
	MagnifyHand.Fade := Fade
END BooksHelp.

Gadgets.Insert BooksHelp.NewIcon ~
System.Free BooksHelp ~