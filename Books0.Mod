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

MODULE Books0;	(** portable *)
	IMPORT Oberon, Files, Texts, Objects, Display, Display3, Effects, Gadgets;
	
	CONST
		(* modes for Frame *)
		none* = 0;
		(* max. length of (file-) names and identifiers *)
		nameLen* = 32;
		identLen* = 32;
		(* size of contents-Gadget (ContElem) *)
		contElemW = 10; contElemH = 11;
		(* modes for contents-Gadget *)
		node* = 0; leaf* = 1; open = 2; noOpen = 3;
		
	TYPE
		Frame* = POINTER TO FrameDesc;
		LocFrame* = POINTER TO LocFrameDesc;
		ExtFrame* = POINTER TO ExtFrameDesc;
		ExtLabel* = POINTER TO ExtLabelDesc;
		ImpList* = POINTER TO ImpListDesc;
		TextList* = POINTER TO TextListDesc;
		ContElem* = POINTER TO ContElemDesc;
		Bar* = POINTER TO BarDesc;
		
		(* invisible Gadgets for links, notes & calls *)
			(* abstract base type *)
		FrameDesc* = RECORD (Gadgets.FrameDesc)
			mode*: SHORTINT
		END;
			(* local to a given tutorial *)
		LocFrameDesc* = RECORD (FrameDesc)
			pos1*, pos2*: LONGINT
		END;
			(* external to a given tutorial *)
		ExtFrameDesc* = RECORD (FrameDesc)
			imp*: ExtLabel
		END;
		
		(* list of imported tutorials *)
		ImpListDesc* = RECORD
			name*: ARRAY nameLen OF CHAR;
			notes*: Texts.Text;
			ind*: LONGINT;
			extLabels*: ExtLabel;
			next*: ImpList
		END;
		
		(* list of imported labels & notes from one tutorial *)
		ExtLabelDesc* = RECORD
			frame*: Frame;
			book*: ImpList;
			name*: ARRAY identLen OF CHAR;
			mode*: SHORTINT;
			pos1*, pos2*: LONGINT;
			next*: ExtLabel
		END;
		
		(* list of pages *)
		TextListDesc* = RECORD
			text*: Texts.Text;
			prev*, next*: TextList
		END;
		
		(* contents-Gadget *)
		ContElemDesc* = RECORD (Gadgets.FrameDesc)
			mode*: SHORTINT;
			beg*, end*: LONGINT;
			col: INTEGER;
		END;
		
		(* simple single color rectangle Gadget *)
		BarDesc = RECORD (Gadgets.FrameDesc)
			col: INTEGER;
		END;

	VAR
		W: Texts.Writer;
		(* ImpList of the tutorial currently beeing loaded, otherwise NIL *)
		loading*: ImpList;
		(* error on fixup, in FrameHandler *)
		error*: BOOLEAN;
		(* action to be done by ContElem *)
		Action*: PROCEDURE (F: ContElem);
				
(* an invisible Gadget for links, notes & calls *)
	
	PROCEDURE *FrameHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			lF: LocFrame;
			eF: ExtFrame;
			ind: LONGINT;
			name: ARRAY identLen OF CHAR;
		(* fixup an external frame, ind = index into import-list *)
		PROCEDURE Fixup(E: ExtFrame);
			VAR
				il: ImpList;
				el: ExtLabel;
		BEGIN
			il := loading;
			WHILE (il # NIL) & (il.ind # ind) DO
				il := il.next
			END;
			IF il # NIL THEN
				el := il.extLabels;
				WHILE (el # NIL) & (el.name # name) DO
					el := el.next
				END;
				IF (el # NIL) & (E.mode = el.mode) THEN
					E.imp := el
				ELSE
					error := TRUE
				END
			ELSE
				error := TRUE
			END
		END Fixup;
	BEGIN
		WITH F: Frame DO
			IF M IS Display.FrameMsg THEN
			(* this is a invisible displayable gadget *)
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						IF F IS LocFrame THEN
							M.s := "Books0.NewLoc"
						ELSIF F IS ExtFrame THEN
							M.s := "Books0.NewExt"
						ELSE HALT(99)
						END;
						M.res := 0
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSIF F IS LocFrame THEN
						NEW(lF);
						F.stamp := M.stamp; F.dlink := lF;
						Gadgets.CopyFrame(M, F, lF);
						WITH F: LocFrame DO
							lF.mode := F.mode;
							lF.pos1 := F.pos1; lF.pos2 := F.pos2
						END;
						M.obj := lF
					ELSIF F IS ExtFrame THEN
						NEW(eF);
						F.stamp := M.stamp; F.dlink := eF;
						Gadgets.CopyFrame(M, F, eF);
						WITH F: ExtFrame DO
							eF.mode := F.mode;
							eF.imp := F.imp
						END;
						M.obj := eF
					ELSE HALT(99)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.load THEN
						Files.Read(M.R, F.mode);
						IF F IS LocFrame THEN
							Files.ReadLInt(M.R, F(LocFrame).pos1);
							Files.ReadLInt(M.R, F(LocFrame).pos2)
						ELSIF F IS ExtFrame THEN
							Files.ReadLInt(M.R, ind);
							Files.ReadString(M.R, name);
							Fixup(F(ExtFrame))
						ELSE HALT(99)
						END
					ELSIF M.id = Objects.store THEN
						Files.Write(M.R, F.mode);
						IF F IS LocFrame THEN
							Files.WriteLInt(M.R, F(LocFrame).pos1);
							Files.WriteLInt(M.R, F(LocFrame).pos2)
						ELSIF F IS ExtFrame THEN
							Files.WriteLInt(M.R, F(ExtFrame).imp.book.ind);
							Files.WriteString(M.R, F(ExtFrame).imp.name)
						ELSE HALT(99)
						END
					END;
					Gadgets.framehandle(F, M)
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END FrameHandler;

	PROCEDURE NewLoc*;
		VAR F: LocFrame;
	BEGIN
		NEW(F);
		INCL(F.state, Gadgets.lockedsize);
		(*!!!
		INCL(F.state, Gadgets.nomove);
		INCL(F.state, Gadgets.noresize);
		INCL(F.state, Gadgets.nodelete);
		INCL(F.state, Gadgets.noselect);
		INCL(F.state, Gadgets.noinput);
		INCL(F.state, Gadgets.noupdate);
		INCL(F.state, Gadgets.noadjust);
		*)
		F.W := 0; F.H := 0;
		F.mode := none;
		F.pos1 := -1; F.pos2 := -1;
		F.handle := FrameHandler;
		Objects.NewObj := F
	END NewLoc;

	PROCEDURE NewExt*;
		VAR F: ExtFrame;
	BEGIN
		NEW(F);
		INCL(F.state, Gadgets.lockedsize);
		(*!!!
		INCL(F.state, Gadgets.nomove);
		INCL(F.state, Gadgets.noresize);
		INCL(F.state, Gadgets.nodelete);
		INCL(F.state, Gadgets.noselect);
		INCL(F.state, Gadgets.noinput);
		INCL(F.state, Gadgets.noupdate);
		INCL(F.state, Gadgets.noadjust);
		*)
		F.W := 0; F.H := 0;
		F.mode := none;
		F.imp := NIL;
		F.handle := FrameHandler;
		Objects.NewObj := F
	END NewExt;

(* a Gadget for contents-nodes *)
	
	PROCEDURE RestoreContElem(F: ContElem; M: Display3.Mask; x, y, w, h: INTEGER);
		VAR dw, dh, i: INTEGER;
	BEGIN
		IF h >= 40 THEN dh := h DIV 10
		ELSE dh := 3
		END;
		dw := w DIV 15;
		IF dw = 0 THEN dw := 1 END;
		Display3.ReplConst(M, F.col, x, y, w, h, Display.replace);
		IF F.mode = open THEN
			Display3.ReplConst(M, Display3.BG, x+dw+1, y+1, w-2*dw-2, h-dh-1, Display.replace);
			Display3.ReplConst(M, Display3.FG, x+dw, y, w-2*dw, 1, Display.replace);
			Display3.ReplConst(M, Display3.FG, x+dw, y, 1, h-dh, Display.replace);
			Display3.ReplConst(M, Display3.FG, x+w-dw-1, y, 1, h-dh, Display.replace);
			i := y+2;
			WHILE i < (y+h-dh-1) DO
				Display3.ReplConst(M, Display3.FG, x+2*dw+1, i, w-5*dw-1, 1, Display.replace);
				INC(i, 2)
			END
		ELSIF F.mode = noOpen THEN
			Display3.Line(M, Display3.FG, Display.solid, x, y, x+w-1, y+h-dh, 1, Display.replace);
			Display3.Line(M, Display3.FG, Display.solid, x+w-1, y, x, y+h-dh, 1, Display.replace)
		ELSIF F.mode = node THEN
			Display3.Circle(M, Display3.red, Display.solid, x+(w DIV 2), y+h-dh, dw+2, 1, {Display3.filled}, Display.replace)
		END;
		Display3.ReplConst(M, Display3.FG, x, y+h-dh, w, dh, Display.replace);
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END RestoreContElem;

	PROCEDURE TrackMouse(F: ContElem; M: Oberon.InputMsg);
		VAR sum: SET;
	BEGIN
		sum := M.keys;
		IF F.mode = node THEN
			F.mode := open
		ELSIF F.mode = leaf THEN
			F.mode := noOpen
		END;
		Oberon.FadeCursor(Oberon.Mouse);
		Gadgets.Update(F);
		WHILE M.keys # {} DO
			sum := sum*M.keys;
			Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow)
		END;
		IF F.mode = open THEN
			F.mode := node;
			IF (sum = {1}) & (Action # NIL) THEN
				F.dlink := M.dlink;
				Action(F)
			END
		ELSIF F.mode = noOpen THEN
			F.mode := leaf
		END;
		Oberon.FadeCursor(Oberon.Mouse);
		Gadgets.Update(F)
	END TrackMouse;
	
	PROCEDURE *ContElemHandler(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			F0: ContElem;
			R: Display3.Mask;
	BEGIN
		WITH F: ContElem DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg  DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R);
										RestoreContElem(F, R, x, y, w, h)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R);
										Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
										RestoreContElem(F, R, x, y, w, h)
									END
								ELSIF M.device = Display.printer THEN (* not printable *)
								END
							END
						ELSIF M IS Oberon.InputMsg THEN
							WITH M: Oberon.InputMsg DO
								IF (M.id = Oberon.track) & Gadgets.InActiveArea(F, M) THEN
									IF M(Oberon.InputMsg).keys = {1} THEN
										TrackMouse(F, M);
										M.res := 0
									ELSE Gadgets.framehandle(F, M)
									END
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSE Gadgets.framehandle(F, M)
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF (M.id = Objects.get) & (M.name = "Gen") THEN
						M.class := Objects.String;
						M.s := "Books0.NewContElem";
						M.res := 0
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.FileMsg THEN
				WITH M: Objects.FileMsg DO
					IF M.id = Objects.store THEN
						Files.Write(M.R, F.mode);
						Files.WriteLInt(M.R, F.beg);
						Files.WriteLInt(M.R, F.end)
					ELSIF M.id = Objects.load THEN
						Files.Read(M.R, F.mode);
						Files.ReadLInt(M.R, F.beg);
						Files.ReadLInt(M.R, F.end)
					END;
					Gadgets.framehandle(F, M);
					(* !! *)
					IF F.col < 0 THEN F.col := Display3.groupC END;
				END
			ELSIF M IS Objects.CopyMsg THEN
				WITH M: Objects.CopyMsg DO
					IF M.stamp = F.stamp THEN
						M.obj := F.dlink
					ELSE
						NEW(F0);
						F.stamp := M.stamp; F.dlink := F0;
						Gadgets.CopyFrame(M, F, F0);
						F0.mode := F.mode;
						F0.beg := F.beg;
						F0.end := F.end;
						M.obj := F0
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END ContElemHandler;

	PROCEDURE NewContElem*;
		VAR F: ContElem;
	BEGIN
		NEW(F);
		INCL(F.state, Gadgets.lockedsize);
		(*!!
		INCL(F.state, Gadgets.nomove);
		INCL(F.state, Gadgets.noresize);
		INCL(F.state, Gadgets.noselect);
		INCL(F.state, Gadgets.nodelete);
		*)
		F.col := Display3.groupC;
		F.X := 0; F.Y := 0;
		F.W := contElemW; F.H := contElemH;
		F.mode := leaf;
		F.beg := -1; F.end := -1;
		F.handle := ContElemHandler;
		Objects.NewObj := F
	END NewContElem;

(* insert or append any Gadgets.Frame to a Texts.Text *)
	
	PROCEDURE InsertFrame*(T: Texts.Text; pos: LONGINT; obj: Gadgets.Frame);
		VAR
			W: Texts.Writer;
	BEGIN
		Texts.OpenWriter(W);
		Texts.WriteObj(W, obj);
		Texts.Insert(T, pos, W.buf)
	END InsertFrame;
	
	PROCEDURE AppendFrame*(T: Texts.Text; obj: Gadgets.Frame);
		VAR
			W: Texts.Writer;
	BEGIN
		Texts.OpenWriter(W);
		Texts.WriteObj(W, obj);
		Texts.Append(T, W.buf)
	END AppendFrame;

(* string operations*)

	PROCEDURE StrConcat*(VAR str0: ARRAY OF CHAR; str1: ARRAY OF CHAR);
			VAR i, j: INTEGER;
	BEGIN
		i := 0;
		WHILE str0[i] # 0X DO
			INC(i)
		END;
		j := 0;
		WHILE str1[j] # 0X DO
			str0[j+i] := str1[j];
			INC(j)
		END;
		str0[j+i] := 0X
	END StrConcat;
	
	PROCEDURE CutSuffix*(VAR str: ARRAY OF CHAR);
		VAR i, dot: INTEGER;
	BEGIN
		dot := -1;
		i := 0;
		WHILE str[i] # 0X DO
			IF str[i] = "." THEN
				dot := i
			END;
			INC(i)
		END;
		IF dot > 0 THEN
			str[dot] := 0X
		END
	END CutSuffix;

(* a simple single color rectangle Gadget *)
	
	PROCEDURE ColorBar*(F: Bar; col: INTEGER);
	BEGIN
		F.col := col;
		Gadgets.Update(F)
	END ColorBar;
	
	PROCEDURE RestoreBarFrame(F: Bar; M: Display3.Mask; x, y, w, h: INTEGER);
		(*VAR dw: INTEGER;*)
	BEGIN
		Display3.ReplConst(M, F.col, x, y, w, h, Display.replace);
		(* (* show "button" *)
		IF F.but THEN
			dw := w DIV 10;
			Display3.ReplConst(M, (15-F.col) MOD 16, x+(w-dw) DIV 2, y+1, dw, h-1, Display.replace)
		END;*)
		IF Gadgets.selected IN F.state THEN
			Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint)
		END
	END RestoreBarFrame;

	PROCEDURE BarFrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
		VAR
			x, y, w, h: INTEGER;
			F0: Bar;
			R: Display3.Mask;
	BEGIN
		WITH F: Bar DO
			IF M IS Display.FrameMsg THEN
				WITH M: Display.FrameMsg DO
					IF (M.F = NIL) OR (M.F = F) THEN
						x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H;
						IF M IS Display.DisplayMsg THEN
							WITH M: Display.DisplayMsg  DO
								IF M.device = Display.screen THEN
									IF (M.id = Display.full) OR (M.F = NIL) THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R);
										RestoreBarFrame(F, R, x, y, w, h)
									ELSIF M.id = Display.area THEN
										Gadgets.MakeMask(F, x, y, M.dlink, R);
										Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
										RestoreBarFrame(F, R, x, y, w, h)
									END
								ELSE Gadgets.framehandle(F, M)
								END
							END
						ELSE Gadgets.framehandle(F, M)
						END
					ELSE Gadgets.framehandle(F, M)
					END
				END
			ELSIF M IS Objects.AttrMsg THEN
				WITH M: Objects.AttrMsg DO
					IF M.id = Objects.get THEN
						IF M.name = "Gen" THEN
							M.class := Objects.String;
							M.s := "Books0.NewBar";
							M.res := 0
						ELSE Gadgets.framehandle(F, M)
						END
					ELSE Gadgets.framehandle(F, M);
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
(* ejz 21.2.95 *)
						F0.col := F.col;
						Gadgets.CopyFrame(M, F, F0);
						M.obj := F0
					END
				END
			ELSE Gadgets.framehandle(F, M)
			END
		END
	END BarFrameHandler;

	PROCEDURE NewBar*;
		VAR F: Bar;
	BEGIN
		NEW(F);
		F.col := Display3.FG;
		F.W := 20; F.H := 20;
		F.handle := BarFrameHandler;
		Objects.NewObj := F
	END NewBar;

BEGIN
	Texts.OpenWriter(W);
	Texts.WriteString(W, "Tutorials for Gadgets, EJZ 17.2.94");
	Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf);
	error := FALSE;
	loading := NIL;
	Action := NIL
END Books0.