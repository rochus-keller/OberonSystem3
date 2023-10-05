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

MODULE TextGadgets0; (** portable *)	(* jm 19.1.95 *)

(**
Scaffolding for an extensible text editor. Extension is best attempted when the source code be available.
*)
(* Still to be done:
	- Search and replace, SearchDiff, StoreAscii
	- Better scrolling
	- Set Caret Msg
	- optimize for menuviewers
	- copy over of pictures

	jm 18.03.93

	23.3.94 - Fixed complete disappearence of text gadget contents when the frame is made 2 pixels or so smaller (ModifyFrame)
	24.3.94 - Added Edit.Recall support
	- Added support for the Oberon.CaretMsg
	- Added additional features of the Oberon.SelectMsg
	- Fixed deep copy of text gadget
	- remove caret and selection when selected
	29.3.94 - Added printing of page numbers
	31.3.94 - fixed auto-indent
	- added correct backward scrolling
	1.4.93 - Added Auto-scrolling when adding at end, or typing at the bottom of the viewer
	6.4.94 - ModifyFrame: improved update after size change. Optimized only for the Standard viewer system.
	8.4.94 - Fixed LinesUp
	19.4.94 - Defocus before caret is set with Oberon.CaretMsg
	25.4.94 - Pass ScrollMsg down
	27.4.94 - improved keep font
	3.5.94 - changed Call
	7.7.94 - Improved Locate so that it does not scroll so much
	7.7.94 - Objects in texts are always copied
	20.9.94 - fixed handling of the Oberon.SelectMsg
	12.10.94 - fixed linkmsg handling
	13.10.94 - fixed deleting the selection over multiple frames
	14.11.94 - middle right now tries to open a document
	6.12.94 - fixed too-easy grabbing of objects in a text
	3.2.95 - added drag and drop support
	6.2.95 - remove seletion/caret before setting the link
		- added pagebreak support
	7.2.95 - fixed recall
	9.2.95 - page up/page down and arrow up/down support added
	22.6.95 - added flat attribute for frames
	2.11.95 - fixed InsertObj
	16.11.95 - Fixed cross viewer selection problem
	15.12.96 - Fixed delete problem (thanks pm)
	24.5.96 - fixed for new Panel-behaviour
	4.6.96 - replaced sliderC by Display3.bottomC (ps - 4.6.96)
	6.6.96 - fixed selection if more than one frame with same model
	16.8.96 - selection remains when just updating a text stretch	(ps - 16.8.96)
	29.8.96 - to select a box is not possible anymore when TG is locked (ps - 29.8.96)
	10.9.96 - redo parts of changes from 29.8.96 / allow selection again but no delete in locked TG
	9.4.97 - fixed selection problem with transparent frames
	10.4.97 - fixed problem with Left and Right
	5.5.97 - fixed problem with Display.ConsumeMsg / integrate
	7.5.97 - scrolling to caret position when copy over / consume text strech
	22.5.97 - fixed invertC (thanks mad)
*)

IMPORT
	Display, Display3, Printer3, Effects, Objects, Gadgets, Oberon, Input, Texts, Fonts, Modules, Files, Printer, Strings;

CONST
		Version = 4;
		eolW* = 5;		(** width of a carriage return *)
		LArrow* = 0C4X; RArrow* = 0C3X;		(** keyboard codes for left/right arrow *)
		(* Printer Page coordinates *)
	
	(** Textframe states *)
	mayselect* = 1;		(** TG may select embedded gadgets *)
	mayfocus* = 2;		(** caret can be set *)
	mayexecute* = 3;		(** TG may execute commands *)
	mayscroll* = 4;		(** TG has a scrollbar *)
	maydelegate* = 5;		(** TG may delegate mouse input to embedded gadgets *)
	maymvchildren* = 6;		(** TG may attempt to move embedded gadgets *)
	mayconsume* = 7;		(** TG may consume new frames *)
	keepfont* = 8;		(** inserted characters are in the font before the caret *)
	autoindent* = 9;		(** autoindent on/off *)
	sizeadjust* = 10;		(** TG must adjust its size according to its contents (grow/shrink)*)
	grow* = 11;		(** TG might increase its size if its contents is too big *)
	shrink* = 12;		(** TG might decrease its size if its contents is smaller than itself *)
	caption* = 13;		(** TG caption mode; not yet implemented *)
	deepcopy* = 14;		(** TG always deep copies it contents when copied *)
	blockadj* = 15;		(** always format the line before the current change point *)
	locked* = 16;		(** locked or not *)
	autoscroll* = 17;	(** may scroll automatically in a log fashion *)
	flat* = 18; 	(** frame does not have a 3D border *)
	buflen = 128;  
	sliderW* = 14;
	
	delete = 2; insert = 1; change = 0;
	
TYPE
	(** Reader for reading backwards in a text (uh) *)
	BackRd* = RECORD
		text*: Texts.Text;
		buf: ARRAY buflen OF CHAR;
		start: LONGINT;
		last, next: INTEGER;
		eot: BOOLEAN;
	END;

	Frame* = POINTER TO FrameDesc;
	Line* = POINTER TO LineDesc;	(** for each text line *)
	Box* = POINTER TO BoxDesc;		(** for each frame in a line *)
	Methods* = POINTER TO MethodBlock;
	
	(** used to identify positions in the text *)
	Loc* = RECORD
		org*: LONGINT;		(** start of the line *)
		pos*: LONGINT;		(** actual postition *)
		x*, y*, dx*: INTEGER;		(** rel coords and character width at this point *)
		line*: Line;		(** which line *)
	END;
	
	BoxDesc* = RECORD
		next*: Box;		(** from left to right in line *)
		org*: LONGINT;		(** offset from beginning of line *)
		f*: Display.Frame;		(** the frame itself *)
		x*, voff*: INTEGER;		(** rel x coordinate and verticall offset *)
	END;
	
	LineDesc* = RECORD
		next*: Line;		(** ring from top to bottom, with sentinel	*)
		base*: INTEGER;		(** rel base line position, negative distance from top of TG *)
		w*, h*, dsr*, asr*: INTEGER;		(** true text metrics, no formatting *)
		left*, right*: INTEGER; 		(** area that should be covered by the selection *)
		len*: LONGINT;		(** length of line in characters *)
		box*: Box;		(** list of boxes *)
		eot*: BOOLEAN;		(** last line of text *)
		draw*: LONGINT;
		(* extra info *)
		spaces*: INTEGER;		(** number of spaces in line *)
		obj*: Objects.Object;	(** hang special things on here *)
		extra*: LONGINT;		(** useful dummy field *)
	END;
	
	MethodBlock* = RECORD
		Background*: PROCEDURE (F: Frame; R: Display3.Mask; X, Y, x, y, w, h: INTEGER);
		Format*: PROCEDURE(F: Frame; org: LONGINT; L: Line);
		InSync*: PROCEDURE(F: Frame; L1, L2: Line): BOOLEAN;
		
		Display*: PROCEDURE(F: Frame; M: Display3.Mask; x, y: INTEGER; org: LONGINT; L: Line; dlink: Objects.Object);
		LocateChar*: PROCEDURE(F: Frame; x, y, X, Y: INTEGER; VAR loc: Loc);
		LocatePos*: PROCEDURE(F: Frame; pos: LONGINT; VAR loc: Loc);
		LocateString*: PROCEDURE(F: Frame; x, y, X, Y: INTEGER; VAR loc: Loc);

		PrintFormat*: PROCEDURE(F: Frame; org: LONGINT; L: Line; VAR pagebreak: BOOLEAN);
		Print*: PROCEDURE(F: Frame; M: Display3.Mask; x, y: INTEGER; org: LONGINT; L: Line; dlink: Objects.Object);
		
		Call*: PROCEDURE (F: Frame; pos: LONGINT; keysum: SET; dlink: Objects.Object);
	END;
		
	DrawDesc* = RECORD
		org0, org1, org2, org3, org4, orgL: LONGINT;
		L0, L1, L2, L3, L4, LL: Line;
		Y0, Y1, Y2, Y3, Y4, t: INTEGER;
	END;
	
	FrameDesc* = RECORD (Gadgets.ViewDesc)
		state0*: SET;
		text*: Texts.Text;
		org*, time*, frametime: LONGINT;
		left*, right*, top*, bottom*: INTEGER;
		trailer*: Line;
		do*: Methods;
		
		car*: BOOLEAN; carpos*: Loc; carX: INTEGER;
		sel*: BOOLEAN; selbeg*, selend*: Loc;
		col*, invertC*: INTEGER;
		desc: DrawDesc;
	END;
	
	CaretMsg = RECORD (Gadgets.UpdateMsg)
		loc: Loc;
	END;
	
	SelectMsg = RECORD (Display.FrameMsg)
		beg, end: Loc;
	END;
	
	ScrollMsg = RECORD (Display.FrameMsg)
		pos: LONGINT
	END;
	
VAR
	PrintertopY*, PrinterbotY*, PrinterleftX*, PagenoX*, HeaderY*: INTEGER;
	W, Wmsg: Texts.Writer;
	myfnt: Fonts.Font; mycol, myvoff: INTEGER;
	dummyFrame: Gadgets.Frame;
	scrollhint: BOOLEAN;
	printOpts*: SET; (** 0: page number, 1: document name *)

PROCEDURE^ RestoreFrame*(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER; dlink: Objects.Object);
PROCEDURE^ AdjustSize(F: Frame; w, h: INTEGER);
PROCEDURE^ RemoveSelection*(F: Frame);
PROCEDURE^ ScrollTo*(F: Frame; pos: LONGINT);
PROCEDURE^ OptimalSize(F: Frame; VAR w, h: INTEGER);
PROCEDURE^ InitPagePosition;
PROCEDURE^ FormatFrame*(F: Frame);

PROCEDURE Max(x, y: LONGINT): LONGINT;
BEGIN IF x > y THEN RETURN x ELSE RETURN y END
END Max;

PROCEDURE ConvertMsg(VAR M: Texts.UpdateMsg; VAR id: INTEGER; VAR beg, end: LONGINT);
BEGIN
	IF M.len = 0 THEN id := delete; beg := M.beg; end := M.end
	ELSIF M.end = M.beg THEN id := insert; beg := M.beg; end := M.beg + M.len
	ELSIF M.end - M.beg = M.len THEN id := change; beg := M.beg; end := M.end
	ELSE HALT(99)
	END
END ConvertMsg;

PROCEDURE InSync*(F: Frame; L1, L2: Line): BOOLEAN;
BEGIN RETURN TRUE
END InSync;

(* ---------------------- back reader ---------- *)

PROCEDURE OpenBackRd*(VAR R: BackRd; text: Texts.Text; pos: LONGINT);
VAR R0: Texts.Reader; i: INTEGER; ch: CHAR;
BEGIN
	R.text := text; R.next := buflen - 1; R.eot := FALSE;
	IF pos >= buflen THEN
		R.start := pos - buflen; i := 0; Texts.OpenReader(R0, text, R.start);
	ELSE
		i := SHORT(buflen - pos); R.start := -i; Texts.OpenReader(R0, text, 0);
	END;
	R.last := i;
	Texts.Read(R0, ch);
	WHILE ~R0.eot & (i < buflen) DO
		IF ~(R0.lib IS Fonts.Font) THEN ch := 1X END; (* filter out frames. Thse may have 0DX as ref no too *)
		R.buf[i] := ch;
		INC(i);
		Texts.Read(R0, ch)
	END;
END OpenBackRd;

PROCEDURE Read*(VAR R: BackRd; VAR ch: CHAR);
BEGIN
	IF R.next >= R.last THEN
		ch := R.buf[R.next]; DEC(R.next); R.eot := FALSE;
	ELSIF (R.next = -1) & (R.start > 0) THEN
		OpenBackRd(R, R.text, R.start); Read(R, ch);
	ELSE
		ch := 0X; R.eot := TRUE;
	END;
END Read;

PROCEDURE RdPos*(VAR R: BackRd): LONGINT;
BEGIN
	IF R.next >= 0 THEN
		RETURN R.start + R.next + 1;
	ELSE
		RETURN R.start;
	END;
END RdPos;

PROCEDURE LinesUp*(T: Texts.Text; pos: LONGINT; no: INTEGER): LONGINT;
VAR br: BackRd; ch: CHAR; l: INTEGER; lpos: LONGINT;
BEGIN
	OpenBackRd(br, T, pos); l := 0;
	REPEAT
		Read(br, ch);
		IF (ch = 0DX) THEN INC(l); END;
	UNTIL br.eot OR (l > no);
	lpos := RdPos(br);
	IF ~br.eot THEN INC(lpos); END; 
	RETURN lpos;
END LinesUp;

(* ------------- end back reader --------- *)

PROCEDURE NewMask(F: Frame);
VAR M: Display.ModifyMsg;
BEGIN
	Oberon.FadeCursor(Oberon.Mouse);
	(* F.mask := NIL; F.car := FALSE; F.sel := FALSE; *)
	M.id := Display.move; M.mode := Display.display; M.F := F;
	M.X := F.X; M.Y := F.Y; M.H := F.H; M.W := F.W; M.dX := 0; M.dY := 0; M.dW := 0; M.dH := 0;
	Display.Broadcast(M)
END NewMask;

PROCEDURE ToBoxes*(F: Frame; x, y : INTEGER; VAR M: Objects.ObjMsg);
VAR L, trailer: Line; b, n: Box; u, v, cx: INTEGER;
BEGIN
	IF (F.trailer = NIL) OR (F.trailer.next = NIL) THEN RETURN END;
	IF M IS Display.FrameMsg THEN
		WITH M: Display.FrameMsg DO
			cx := 0;
			u := M.x; v := M.y;
			trailer := F.trailer; (* important *)
			L := trailer.next;
			WHILE (L # trailer) & (L # NIL) & (M.res < 0) DO (* nil test must be there !!! *)
				n := L.box;
				WHILE (n # NIL) & (M.res < 0) DO
					b := n; n := b.next;
					M.x := x + (b.x - b.f.X); M.y := y + F.H - 1 + (L.base - b.f.X) + b.voff;
					Gadgets.Send(F, x, y, b.f, M);
					INC(cx); IF cx > 5000 THEN HALT(95) END;
				END;
				L := L.next;
			END;
			M.x := u; M.y := v;
		END;
	ELSE
		HALT(99)
	END
END ToBoxes;

(* is this a hack *)
PROCEDURE FindLine(F: Frame; y, Y: INTEGER; VAR org: LONGINT; VAR L: Line);
BEGIN
	L := NIL;
	IF F.trailer # NIL THEN 
		L := F.trailer.next; org := F.org;
		WHILE (L.next # F.trailer) & (Y < y + F.H - 1 + L.base - L.dsr) DO org := org + L.len; L := L.next; END
	END
END FindLine;

PROCEDURE LocateBox*(F: Frame; X, Y, x, y, w, h: INTEGER; VAR L: Line): Box;
VAR b: Box; org: LONGINT;
BEGIN
	org := F.org; FindLine(F, y, Y, org, L);
	IF L # NIL THEN
		b := L.box;
		WHILE b # NIL DO
			IF Effects.Inside(X, Y, x + b.x, y + h - 1 + L.base + b.voff, b.f.W, b.f.H) THEN RETURN b; END;
			b := b.next;
		END
	END;
	RETURN NIL;
END LocateBox;

(* --- Caret tracking ---- *)

PROCEDURE FlipCaret(F: Frame; R: Display3.Mask; x, y, w, h: INTEGER; loc: Loc);
BEGIN
	(* Oberon.FadeCursor(Oberon.Mouse); *)
	Oberon.RemoveMarks(x + loc.x, y + h - 1 + loc.y - 10, 10, 10);
	Display3.CopyPattern(R, F.invertC, Display.hook, x + loc.x, y + h - 1 + loc.y - 10, Display.invert);
END FlipCaret;

PROCEDURE FlipCaretMsg(F: Frame; loc: Loc);
VAR C: CaretMsg;
BEGIN C.F := F; C.obj := dummyFrame; C.loc := loc; Display.Broadcast(C);
END FlipCaretMsg;

PROCEDURE RemoveCaret*(F: Frame);
BEGIN
	(* Oberon.FadeCursor(Oberon.Mouse); *)
	IF F.car THEN FlipCaretMsg(F, F.carpos); F.car := FALSE; END;
END RemoveCaret;

PROCEDURE SetFont(text: Texts.Text; cpos: LONGINT);
VAR R: Texts.Reader; tries: INTEGER; ch: CHAR;
BEGIN
	IF cpos < 0 THEN cpos := 0 END;
	Texts.OpenReader(R, text, cpos);
	Texts.Read(R, ch);
	IF (R.lib # NIL) & (R.lib IS Fonts.Font) THEN myfnt := R.lib(Fonts.Font); mycol := R.col; myvoff := R.voff
	ELSE (* inefficient but works *)
		myfnt := NIL; tries := 3;
		WHILE (myfnt = NIL) & (tries > 0) & (cpos > 0) DO
			DEC(cpos); Texts.OpenReader(R, text, cpos); Texts.Read(R, ch);
			IF (R.lib # NIL) & (R.lib IS Fonts.Font) THEN myfnt := R.lib(Fonts.Font); mycol := R.col; myvoff := R.voff END;
			DEC(tries)
		END
	END
END SetFont;

PROCEDURE SetCaretWithScroll0(F: Frame; pos: LONGINT);
VAR oldorg: LONGINT;
BEGIN
	IF F.car THEN FlipCaretMsg(F, F.carpos); F.car := FALSE; END;
	F.do.LocatePos(F, pos, F.carpos);
	LOOP
		IF (F.carpos.line.base - F.carpos.line.dsr <= -F.H + F.bottom) & (F.carpos.org # F.org) THEN
			oldorg := F.org;
			ScrollTo(F, F.org + F.trailer.next.len);
			F.do.LocatePos(F, pos, F.carpos);
			IF F.org = oldorg THEN EXIT END
		ELSE EXIT
		END;
	END;
	
	F.car := TRUE; F.carX := F.carpos.x;
	IF keepfont IN F.state0 THEN SetFont(F.text, F.carpos.pos - 1) END;
	FlipCaretMsg(F, F.carpos)
END SetCaretWithScroll0;

PROCEDURE SetCaretWithScroll(F: Frame; pos: LONGINT);
BEGIN
	IF F.car THEN FlipCaretMsg(F, F.carpos); F.car := FALSE; END;
	F.do.LocatePos(F, pos, F.carpos);
	IF (F.carpos.line.next = F.trailer) & ((pos-F.carpos.org-F.carpos.line.len) > 0) THEN
		ScrollTo(F, pos); F.do.LocatePos(F, pos, F.carpos);
		F.car := TRUE; F.carX := F.carpos.x;
		IF keepfont IN F.state0 THEN SetFont(F.text, F.carpos.pos - 1) END;
		FlipCaretMsg(F, F.carpos)
	ELSE
		SetCaretWithScroll0(F, pos)
	END
END SetCaretWithScroll;

PROCEDURE SetCaret*(F: Frame; pos: LONGINT);
BEGIN
	IF F.car THEN FlipCaretMsg(F, F.carpos); F.car := FALSE; END;
	F.do.LocatePos(F, pos, F.carpos);
	F.car := TRUE; F.carX := F.carpos.x;
	IF keepfont  IN F.state0 THEN SetFont(F.text, F.carpos.pos - 1) END;
	FlipCaretMsg(F, F.carpos)
END SetCaret;

PROCEDURE TrackCaret*(F: Frame; R: Display3.Mask; VAR keysum: SET; x, y, w, h: INTEGER; VAR loc: Loc);
VAR o, l: Loc; X, Y: INTEGER; keys: SET;
BEGIN
	Oberon.FadeCursor(Oberon.Mouse); 
	Input.Mouse(keys, X, Y); keysum := keys;
	F.do.LocateChar(F, x, y, X, Y, o);
	FlipCaret(F, R, x, y, w, h, o);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y); keysum := keysum + keys;
		F.do.LocateChar(F, x, y, X, Y, l);
		IF l.pos # o.pos THEN
			Oberon.FadeCursor(Oberon.Mouse); FlipCaret(F, R, x, y, w, h, o); o := l; FlipCaret(F, R, x, y, w, h, o);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
	END;
	Oberon.FadeCursor(Oberon.Mouse); FlipCaret(F, R, x, y, w, h, o); loc := o;
END TrackCaret;

PROCEDURE TrackWord*(F: Frame; R: Display3.Mask; VAR keysum: SET; x, y, w, h: INTEGER; VAR pos: LONGINT);
VAR o, l: Loc; X, Y: INTEGER; keys: SET;
BEGIN
	Input.Mouse(keys, X, Y); keysum := keys;
	F.do.LocateString(F, x, y, X, Y, o);
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, F.invertC, x + o.x, y + h - 1 + o.y - 3, o.dx, 2, Display.invert);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y); keysum := keysum + keys;
		F.do.LocateString(F, x, y, X, Y, l);
		IF l.pos # o.pos THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(R, F.invertC, x + o.x, y + h - 1 + o.y - 3, o.dx, 2, Display.invert);
			o := l;
			Display3.ReplConst(R, F.invertC, x + o.x, y + h - 1 + o.y - 3, o.dx, 2, Display.invert);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
	END;
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, F.invertC, x + o.x, y + h - 1 + o.y - 3, o.dx, 2, Display.invert);
	pos := o.pos;
END TrackWord;

PROCEDURE TrackLine*(F: Frame; R: Display3.Mask; VAR keysum: SET; x, y: INTEGER; VAR org: LONGINT; VAR L: Line);
VAR keys: SET; X, Y, W, t: INTEGER; oL, nL: Line; pos: LONGINT;
BEGIN
	t := y + F.H - 1;
	Input.Mouse(keys, X, Y);
	FindLine(F, y, Y, pos, oL); keysum := keys;
	W := oL.right - F.left;
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, F.invertC, x + F.left, t + oL.base - 3, W, 2, Display.invert); org := pos;
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y); keysum := keysum + keys;
		FindLine(F, y, Y, pos, nL);
		IF nL # oL THEN org := pos;
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.ReplConst(R, F.invertC, x + F.left, t + oL.base - 3, W, 2, Display.invert);
			oL := nL; W := oL.right - F.left;
			Display3.ReplConst(R, F.invertC, x + F.left, t + oL.base - 3, W, 2, Display.invert);
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
	END;
	Oberon.FadeCursor(Oberon.Mouse);
	Display3.ReplConst(R, F.invertC, x + F.left, t + oL.base - 3, W, 2, Display.invert);
	L := oL;
END TrackLine;

PROCEDURE LinesOf*(F: Frame): INTEGER;
VAR c: INTEGER; L: Line;
BEGIN
	c := 0; L := F.trailer.next;
	WHILE L # F.trailer DO
		INC(c); L := L.next;
	END;
	RETURN c;
END LinesOf;

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

PROCEDURE ScrollTo*(F: Frame; pos: LONGINT);
VAR M: ScrollMsg;
BEGIN
	IF F.org # pos THEN
		RemoveCaret(F); RemoveSelection(F);
		M.F := F; M.pos := pos; Display.Broadcast(M)
	END
END ScrollTo;

PROCEDURE RestoreSlider(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER);
VAR pos: INTEGER;
BEGIN
	IF (F.left > sliderW) & (mayscroll IN F.state0) THEN
		F.do.Background(F, M, x, y, 0, -F.H + 1, sliderW, F.H); (* left border *)
		
		Display3.ReplConst(M, Display3.bottomC, x + sliderW, y + 1, 1, h-2, Display.replace);	(* ps - 4.6.96 *)
		F.do.Background(F, M, x, y, sliderW+1, -F.H + 1, F.left - sliderW-1, F.H); (* right area *)

		(* old bar 
			pos := y + h - 2 - SHORT(F.org * (h - 2) DIV (F.text.len+1));
		Display3.ReplConst(M, Display.FG, x + 2, pos, 5, 1, Display.replace);
		*)
		(* the new bar *)
		pos := y + h - 2 - SHORT(F.org * (h - 4) DIV (F.text.len+1));
		Display3.FilledRect3D(M, Display3.topC, Display3.bottomC, Display3.groupC, x+2, pos - 4, 8, 3, 1, Display.replace)
	ELSE
		F.do.Background(F, M, x, y, 0, -F.H + 1, F.left, F.H); (* left border *)
	END
END RestoreSlider;

(*
	L1 - L2 part to copy to t
	 L3 - L4 part to draw new
	 Y0 - start background restore from here
*)
PROCEDURE DrawScrollChanges(F: Frame; pos, stamp: LONGINT; dlink: Objects.Object; x, y, w, h: INTEGER; VAR d: DrawDesc);
VAR M, clipM: Display3.Mask; copy: BOOLEAN; cx, cy, cw, ch: INTEGER; org: LONGINT; L: Line;
BEGIN
	Oberon.RemoveMarks(x, y, w, h);
	Gadgets.MakeMask(F, x, y, dlink, M);
	
	RestoreSlider(F, M, x, y, w, h);
	
	copy  := Display3.Rectangular(M, cx, cy, cw, ch);  ClipAgainst(cx, cy, cw, ch, M.X, M.Y, M.W, M.H);
	copy := copy & (cx = x) & (cy = y) & (cw = w) & (ch = h);
	(* copy *)
	IF d.L1 # NIL THEN
		IF copy THEN
			Oberon.FadeCursor(Oberon.Mouse);
			Display3.Copy(M, clipM);
			Display3.Intersect(clipM, x + F.left, y + F.H - 1 + d.Y2, F.W - F.left - F.right, d.Y1 - d.Y2);
			Display3.Intersect(clipM, M.X, M.Y, M.W, M.H);
			Display3.CopyMask(clipM, clipM.x, clipM.y + (d.t - d.Y1), Display.replace);
			L := d.L1; org := d.org1;
			WHILE L # d.L2 DO
				L := L.next; INC(org, L.len); 
			END
		ELSE (* draw it *)
			L := d.L1; org := d.org1;
			IF L = F.trailer THEN HALT(99) END;
			F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len); 
			WHILE L # d.L2 DO
				L := L.next;
				IF L = F.trailer THEN HALT(99) END;
				F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len)
			END
		END
	END;
	
	(* display *)
	IF d.L3 # NIL THEN
		L := d.L3; org := d.org3;
		IF L = F.trailer THEN HALT(99) END;
		F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len);
		WHILE L # d.L4 DO
			L := L.next;
			IF L = F.trailer THEN HALT(99) END;
			F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len)
		END
	END;
	
	IF (d.Y0 < 0) & (d.Y0 >= -F.H + 1) THEN
		F.do.Background(F, M, x, y, F.left, -F.H + 1, F.W, d.Y0 - (-F.H + 1))
	END
END DrawScrollChanges;

PROCEDURE ScrollUpdate(F: Frame; pos, stamp: LONGINT; VAR d: DrawDesc);
VAR tY, bY, nY, Y: INTEGER; org, org0: LONGINT; L, L0: Line;

	PROCEDURE FormatFrom(Lx: Line; VAR Y: INTEGER; pos: LONGINT);
	VAR org: LONGINT;
	BEGIN
		NEW(Lx.next); Lx := Lx.next; d.L3 := Lx; d.org3 := pos; d.Y3 := Y; org := pos;
		F.do.Format(F, org, Lx); DEC(Y, Lx.asr); Lx.base := Y; DEC(Y, Lx.dsr); org := org + Lx.len;
		LOOP
			IF Y <= -F.H + F.bottom THEN EXIT END; (* ! *)
			IF Lx.eot THEN EXIT END;
			NEW(Lx.next); Lx := Lx.next;
			F.do.Format(F, org, Lx); DEC(Y, Lx.asr); Lx.base := Y; DEC(Y, Lx.dsr); org := org + Lx.len;
		END;
		d.L4 := Lx; 
		Lx.next := F.trailer
	END FormatFrom;

BEGIN
	IF stamp = F.stamp THEN (* second time around *)
	ELSE (* first time *)
		d.Y0 := 1;
		F.stamp := stamp;
		IF pos < F.org THEN (* have to scroll down *)
			(* format till F.org is reached*)
			d.L1 := F.trailer.next; d.Y1 := -F.top + 1; d.org1 := F.org;
			L := F.trailer; Y := -F.top + 1;
			NEW(L.next); L := L.next; d.L3 := L; d.org3 := pos; d.Y3 := Y; org := pos;
			F.do.Format(F, org, L); DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len;
			LOOP
				IF Y <= -F.H + F.bottom THEN EXIT END; (* ! *)
				IF L.eot THEN EXIT END;
				IF org = F.org THEN (* match! *) EXIT END;
				NEW(L.next); L := L.next;
				F.do.Format(F, org, L); DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len;
			END;
			d.L4 := L;
			IF (org = F.org) & (Y > -F.H + F.bottom) THEN (* match! take existing lines until the end*)
				d.t := Y; nY := d.Y1;
				L.next := d.L1;
				LOOP
					IF Y <= -F.H + F.bottom THEN EXIT END; (* ! *)
					IF L.eot THEN EXIT END;
					L := L.next;
					DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len; DEC(nY, L.h)
				END;
				d.L2 := L; d.Y2 := nY; IF Y <= -F.H + F.bottom THEN INC(d.Y2, -F.H + 2 - Y) END;
			ELSE d.L1 := NIL; (* cannot copy any more *)
			END;
			L.next := F.trailer; F.org := pos;
			d.Y0 := Y;
		ELSE (* have to scroll up *)
			tY := -F.top + 1; org := F.org;
			L := F.trailer.next; 
			WHILE (L # F.trailer) & (pos > org) & (tY - L.h > -F.H + F.bottom) DO INC(org, L.len); DEC(tY, L.h); L := L.next END;
			IF L = F.trailer THEN (* not on the display *)
				d.Y0 := -F.top + 1;
				NEW(F.trailer); FormatFrom(F.trailer, d.Y0, pos); d.L1 := NIL; F.org := pos
			ELSIF (pos = org) & (tY - L.h > -F.H + F.bottom) THEN (* great ! *)
				L0 := L; bY := tY; d.L1 := L; org0 := org; d.org1 := org; d.Y1 := tY; nY := -F.top + 1;
				INC(org0, L0.len); DEC(nY, L0.asr); L0.base := nY; DEC(nY, L0.dsr); DEC(bY, L0.h);
				WHILE (L0.next # F.trailer) & (bY - L0.next.h > -F.H + F.bottom) DO
					L0 := L0.next;
					INC(org0, L0.len); DEC(nY, L0.asr); L0.base := nY; DEC(nY, L0.dsr); DEC(bY, L0.h);
				END;
				
				(* copy the area between bY and tY to the top *)
				F.trailer.next := L;
				d.L2 := L0; d.org2 := org0; d.Y2 := bY; d.t := -F.top + 1;
				(* format from L0 onwards *)
				d.L3 := NIL;
				IF ~L0.eot THEN FormatFrom(L0, nY, org0) END;
				d.Y0 := nY;
				F.org := pos
			ELSE
				d.Y0 := -F.top + 1;
				NEW(F.trailer); FormatFrom(F.trailer, d.Y0, pos); d.L1 := NIL; F.org := pos;
			END 
		END
	END
END ScrollUpdate;

(* ---- Selections ---- *)

PROCEDURE Below(x, y: INTEGER): INTEGER;
BEGIN
	IF x < y THEN RETURN y - x; ELSE RETURN 0 END;
END Below;

PROCEDURE Above(x, y: INTEGER): INTEGER;
BEGIN
	IF x > y THEN RETURN x - y; ELSE RETURN 0 END;
END Above;

PROCEDURE FlipSelection(F: Frame; R: Display3.Mask; x, y: INTEGER; s, e: Loc);
VAR t: INTEGER; l: Line; cx, cy, cw, ch, ex: INTEGER; org: LONGINT;
	
(* forward *)
	PROCEDURE Flip(L: Line; sx, ex: INTEGER; org, beg, end: LONGINT);
	VAR b: Box; e, w: INTEGER; 
	BEGIN
		IF L.h > 0 THEN
			b := L.box;
			WHILE b # NIL DO
				IF (org + b.org >= beg) & (org + b.org < end) & (b.x >= sx) THEN
					e := b.x;
					Display3.ReplConst(R, F.invertC, x + sx, t + L.base - L.dsr, e - sx, L.h, Display.invert);
					w := b.f.W;
					IF e + w > ex THEN w := ex - e END; (* cut off selection if needed *)
					IF (b.f IS Gadgets.Frame) & (Gadgets.transparent IN b.f(Gadgets.Frame).state) THEN (* transparent *)
						Display3.ReplConst(R, F.invertC, x + e, t + L.base + b.voff, w, b.f.H, Display.invert);
					END;
					Display3.ReplConst(R, F.invertC, x + e, t + L.base - L.dsr, w, Below(-L.dsr, b.voff), Display.invert); (* bottom *)
					Display3.ReplConst(R, F.invertC, x + e, t + L.base + b.voff + b.f.H, w, Above(L.asr, b.voff + b.f.H), Display.invert); (* top *)
					sx := e + w;
				END;
				b := b.next;
			END;
			IF ex > sx THEN
				Display3.ReplConst(R, F.invertC, x + sx, t + L.base - L.dsr, ex - sx, L.h, Display.invert);
			END
		END
	END Flip;

BEGIN
	Oberon.FadeCursor(Oberon.Mouse);
	cx := R.X; cy := R.Y; cw := R.W; ch := R.H;
	Display3.AdjustMask(R, x+1, y+2, F.W-2, F.H-2);
	IF e.x > F.W - F.right THEN ex := F.W - F.right ELSE ex := e.x END;
	t := y + F.H - 1;
	IF s.line = e.line THEN Flip(s.line, s.x, ex, s.org, s.pos, e.pos); 
	ELSE
		(* F.do.LocateChar(F, x, y, x + 2000, t + s.line.base, endpos);*)
		Flip(s.line, s.x, s.line.right (*F.W - F.right*) (*endpos.x + endpos.dx*), s.org, s.pos, s.org + s.line.len);
		org := s.org;  org := org + s.line.len;
		l := s.line.next;
		WHILE l # e.line DO
			(* F.do.LocateChar(F, x, y, x, t + l.base, begpos); F.do.LocateChar(F, x, y, x + 2000, t + l.base, endpos); *)
			Flip(l, l.left (*F.left *)(*begpos.x*),  l.right(*F.W - F.right*) (*endpos.x + endpos.dx*), org, org, org + l.len); org := org + l.len;
			l := l.next;
		END;
		(* F.do.LocateChar(F, x, y, x, t + l.base, begpos); *)
		Flip(e.line, e.line.left(*F.left*)(*begpos.x*), ex, e.org, e.org, e.pos); 
	END;
	R.X := cx; R.Y := cy; R.W := cw; R.H := ch;
END FlipSelection;

PROCEDURE FlipSelectionMsg(F: Frame; beg, end: Loc);
VAR S: SelectMsg;
BEGIN S.F := F; S.beg := beg; S.end := end; Display.Broadcast(S)
END FlipSelectionMsg;

PROCEDURE RemoveSelection*(F: Frame);
BEGIN IF F.sel THEN FlipSelectionMsg(F, F.selbeg, F.selend); F.sel := FALSE; END;
END RemoveSelection;

PROCEDURE SetSelection*(F: Frame; beg, end: LONGINT);
BEGIN
	RemoveSelection(F);
	F.do.LocatePos(F, beg, F.selbeg); F.do.LocatePos(F, end, F.selend); F.sel := TRUE;
	FlipSelectionMsg(F, F.selbeg, F.selend);
	F.time := Oberon.Time();
END SetSelection;

PROCEDURE TrackSelection*(F: Frame; VAR keysum: SET; x, y: INTEGER; VAR beg, end: Loc; dlink: Objects.Object);
VAR F0: Frame; s, e, l: Loc; X, Y: INTEGER; keys, modKeys: SET; M: Oberon.SelectMsg;
BEGIN
	Input.Mouse(keys, X, Y); keysum := keys;
	F.do.LocateChar(F, x, y, X, Y, s);

	IF F.sel & (s.pos = F.selbeg.pos) & (F.selend.pos = F.selbeg.pos + 1) THEN
		e := s; F.do.LocateChar(F, x, y, F.left, Y, s)
	ELSE
		e := s
	END;
	(* clear the selection *)
	IF F.sel THEN FlipSelectionMsg(F, F.selbeg, F.selend); F.sel := FALSE; END;

	FlipSelectionMsg(F, s, e);
	WHILE keys # {} DO
		Input.Mouse(keys, X, Y); keysum := keysum + keys;
		F.do.LocateChar(F, x, y, X, Y, l);
		IF l.pos < s.pos THEN l := s; END;
		INC(l.pos); l.x := l.x + l.dx;
		IF l.pos < e.pos THEN FlipSelectionMsg(F, l, e); e := l;
		ELSIF l.pos > e.pos THEN FlipSelectionMsg(F, e, l); e := l;
		END;
		Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y)
	END;
	(* ps - 3.4.98 *)
	Input.KeyState(modKeys);
	IF Input.SHIFT IN modKeys THEN
		M.id := Oberon.get; M.F := NIL; M.sel := NIL; M.text := NIL; M.time := -1; Display.Broadcast(M);
		IF (M.time > 0) & (M.text = F.text) & (M.sel IS Frame) THEN
			IF M.beg < s.pos THEN beg.pos := M.beg ELSE beg := s END;
			IF M.end > e.pos THEN end.pos := M.end ELSE end := e END;
			F0 := M.sel(Frame);
			FlipSelectionMsg(F0, F0.selbeg, F0.selend);
			F0.do.LocatePos(F0, beg.pos, F0.selbeg); F0.do.LocatePos(F0, end.pos, F0.selend);
			FlipSelectionMsg(F0, F0.selbeg, F0.selend);
			
			FlipSelectionMsg(F, s, e);
			F.do.LocatePos(F, beg.pos, s); F.do.LocatePos(F, end.pos, e);
			FlipSelectionMsg(F, s, e)
		END
	END;
	beg := s; end := e
END TrackSelection;

PROCEDURE UnselectSelectedFrames(T: Texts.Text);
VAR F: Texts.Finder; o: Objects.Object; S: Display.SelectMsg;
BEGIN
	Texts.OpenFinder(F, T, 0);
	Texts.FindObj(F, o);
	WHILE ~F.eot DO
		IF (o # NIL) & (o IS Gadgets.Frame) THEN
			WITH o: Gadgets.Frame DO
				IF Gadgets.selected IN o.state THEN
					S.id := Display.reset; S.x := 0; S.y := 0; S.F := o; S.obj := o; S.res := -1; S.dlink := NIL; Objects.Stamp(S); 
					o.handle(o, S); Gadgets.Update(o)
				END
			END
		END;
		Texts.FindObj(F, o);
	END;
END UnselectSelectedFrames;

(* --- *)

PROCEDURE GetSelection(F: Frame; VAR text: Texts.Text; VAR beg, end, time: LONGINT);
VAR loc: Loc;
BEGIN
	IF F.sel & (F.selbeg.pos >= 0) THEN
		IF F.time > time THEN	(* ps - 6.6.96 *)
			time := F.time; text := F.text; beg := F.selbeg.pos; end := F.selend.pos;
			IF end > F.text.len THEN end :=  F.text.len END
		ELSIF F.text = text THEN
			(* 7.4.98 - ps *)
			F.do.LocateChar(F, 0, 0, F.W, 0, loc);
			IF (F.selbeg.pos < beg) & (F.selend.pos >= loc.pos) THEN beg := F.selbeg.pos END;
			IF (F.selend.pos > end) & (F.selbeg.pos = F.org) THEN end := F.selend.pos END;
			IF end > F.text.len THEN end :=  F.text.len END
		END
	END
END GetSelection;

PROCEDURE CopyStretch(text: Texts.Text; beg, end: LONGINT; VAR W: Texts.Writer; F: Frame);
VAR R: Texts.Finder; obj, new: Objects.Object; M: Objects.CopyMsg;
BEGIN
	IF end > text.len THEN end := text.len END;
	Texts.OpenFinder(R, text, beg);
	WHILE R.pos < end DO
		IF beg < R.pos THEN Texts.Save(text, beg, R.pos, W.buf) END;
		beg := R.pos; Texts.FindObj(R, obj);
		IF (obj IS Display.Frame) THEN
			M.id := Objects.shallow; Objects.Stamp(M); obj.handle(obj, M); new := M.obj;	(* copy *)
			Texts.WriteObj(W, new); INC(beg)
		END
	END;
	IF beg < end THEN Texts.Save(text, beg, end, W.buf) END
END CopyStretch;

PROCEDURE CopyOver* (F: Frame; text: Texts.Text; beg, end: LONGINT);
VAR p: LONGINT; R: Texts.Reader; ch: CHAR; obj: Objects.Object; ok: BOOLEAN;
BEGIN
	Texts.OpenReader(R, text, beg); p := beg; ok := TRUE;
	REPEAT
		Texts.Read(R, ch);
		IF (R.lib # NIL) THEN
			R.lib.GetObj(R.lib, ORD(ch), obj);
			IF obj IS Display.Frame THEN
				IF Gadgets.Recursive(F, obj) THEN ok := FALSE END;
			END;
		END;
		INC(p);
	UNTIL R.eot OR (p >= end) OR ~ok;
	IF ok THEN 
		p := F.carpos.pos;
		CopyStretch(text, beg, end, W, F);
		Texts.Insert(F.text, p, W.buf);
		SetCaretWithScroll(F, p + (end - beg))	(* ps - 7.5.97 *)
	ELSE
		Texts.WriteString(Wmsg,"Not allowed, will cause recursive structures"); Texts.WriteLn(Wmsg);
		Texts.Append(Oberon.Log, Wmsg.buf)
	END
END CopyOver;

PROCEDURE CopyList*(obj: Objects.Object; depth: INTEGER; VAR obj0: Objects.Object);
VAR C: Objects.CopyMsg;
BEGIN
	obj0 := NIL; Objects.Stamp(C);
	WHILE obj # NIL DO
		C.id := depth; C.obj := NIL; obj.handle(obj, C);
		IF C.obj # NIL THEN C.obj.slink := obj0; obj0 := C.obj END;
		obj := obj.slink
	END
END CopyList;

PROCEDURE DeleteSelectedFrames*(T: Texts.Text);
VAR F: Texts.Finder; o: Objects.Object; first: LONGINT;
BEGIN
	first := -1;
	LOOP
		Texts.OpenFinder(F, T, 0);
		IF F.eot THEN EXIT END;
		first := F.pos;
		Texts.FindObj(F, o);
		LOOP
			IF F.eot THEN EXIT END;
			IF (o # NIL) & (o IS Gadgets.Frame) &
				(Gadgets.selected IN o(Gadgets.Frame).state) THEN
				EXIT
			ELSE
				first := F.pos;
				Texts.FindObj(F, o)
			END
		END;
		IF F.eot THEN EXIT END;
		IF (o # NIL) & (o IS Gadgets.Frame) & (Gadgets.selected IN o(Gadgets.Frame).state) THEN
			Texts.Delete(T, first, first+1)
		END
	END
END DeleteSelectedFrames;

PROCEDURE GetSelectedFrames*(T: Texts.Text; VAR obj: Objects.Object);
VAR F: Texts.Finder; o, o0: Objects.Object;
BEGIN
	obj := NIL;
	Texts.OpenFinder(F, T, 0);
	Texts.FindObj(F, o);
	WHILE ~F.eot DO
		IF (o # NIL) & (o IS Gadgets.Frame) THEN
			WITH o: Gadgets.Frame DO
				IF Gadgets.selected IN o.state THEN
					o0 := obj;
					WHILE (o0 # NIL) & (o # o0) DO o0 := o0.slink END;
					IF o0 = NIL THEN o.slink := obj; obj := o END
				END
			END
		END;
		Texts.FindObj(F, o)
	END
END GetSelectedFrames;

PROCEDURE HasCmdAttr(F: Frame; attr: ARRAY OF CHAR): BOOLEAN;
VAR A: Objects.AttrMsg;
BEGIN
	A.id := Objects.get; COPY(attr, A.name); A.class := Objects.Inval; A.res := -1; A.dlink := NIL; Objects.Stamp(A);
	F.handle(F, A);
	RETURN (A.res >= 0) & (A.class = Objects.String) & (A.s # "") 
END HasCmdAttr;

  PROCEDURE Call* (F: Frame; pos: LONGINT; keysum: SET; dlink: Objects.Object);
    VAR S: Texts.Scanner; res, i, j: INTEGER; oldcontext, obj: Objects.Object;
    cx, cy, cw, chl: INTEGER; par: Oberon.ParList; A: Objects.AttrMsg;
    R: Texts.Reader; ch: CHAR;
    cmd: ARRAY 256 OF CHAR;
  BEGIN
    Display.GetClip(cx, cy, cw, chl); Display.ResetClip;
    
    (* we want to pass everything that is underlined to the TG Cmd *)
    IF HasCmdAttr(F, "Cmd")  THEN
    	Texts.OpenReader(R, F.text, pos);
    	Texts.Read(R, ch); WHILE ~R.eot & (ch <= " ") DO Texts.Read(R, ch) END;
    	IF ~R.eot THEN
    		 i := 0;
    		 WHILE (i < LEN(cmd) - 1) & (ch > " ") DO cmd[i] := ch; INC(i); Texts.Read(R, ch) END; cmd[i] := 0X;
    		 IF cmd # "" THEN
    		 	A.id := Objects.set; A.name := "Point"; A.class := Objects.String; A.dlink := NIL; Objects.Stamp(A);
				COPY(cmd, A.s); A.res := -1; F.handle(F, A);
				Gadgets.ExecuteAttr(F, "Cmd", dlink, NIL, NIL);
				RETURN
    		 END
    	END
    ELSIF keysum = {0, 1} THEN
    	Texts.OpenReader(R, F.text, pos);
    	Texts.Read(R, ch); WHILE ~R.eot & (ch <= " ") DO Texts.Read(R, ch) END;
    	IF ~R.eot THEN
    		 COPY("Desktops.OpenDoc ", cmd);
    		 i := 0; WHILE cmd[i] # 0X DO INC(i) END;
    		 WHILE (i < LEN(cmd) - 1) & (ch > " ") DO cmd[i] := ch; INC(i); Texts.Read(R, ch) END;
    		 cmd[i] := 0X;
			 Gadgets.Execute(cmd, F, dlink, NIL, NIL);
			 RETURN
    	END
    END;
    
    Texts.OpenScanner(S, F.text, pos); Texts.Scan(S);
    IF (S.line = 0) & (S.class = Texts.Name) THEN
    	NEW(par);
		Gadgets.executorObj := F; Gadgets.context := dlink; Gadgets.senderObj := NIL; Gadgets.receiverObj := NIL;
		par.obj := F; par.text := F.text; par.pos := pos + S.len;
		
		oldcontext := F.dlink; F.dlink := dlink;
		
		IF Gadgets.context = NIL THEN Gadgets.context := F END; (* may be the outside most frame *)
		obj := Gadgets.context;
		LOOP
			IF (obj = NIL) OR (obj.dlink = NIL) THEN EXIT END;
			obj := obj.dlink
		END;
		IF (obj # NIL) & (obj IS Display.Frame) THEN par.frame := obj(Display.Frame)
		ELSE par.frame := Oberon.Par.frame(* hack *)
		END;

		i := 0; WHILE (i < S.len) & (S.s[i] # ".") DO INC(i) END;
		j := i + 1; WHILE (j < S.len) & (S.s[j] # ".") DO INC(j) END;
		IF (j >= S.len) & (S.s[i] = ".") THEN
			Oberon.Call(S.s, par, 2 IN keysum, res);
			IF res # 0 THEN
				Texts.WriteString(Wmsg, "Call error: "); Texts.WriteString(Wmsg, Modules.resMsg);
				Texts.WriteLn(Wmsg); Texts.Append(Oberon.Log, Wmsg.buf)
			END
		END;
		F.dlink := oldcontext

    END;
    Display.SetClip(cx, cy, cw, chl);
    Gadgets.executorObj := NIL; Gadgets.context := NIL; Gadgets.senderObj := NIL; Gadgets.receiverObj := NIL
  END Call;
  
 (* scroll in such a manner that L is at the bottom of the frame *)
PROCEDURE ScrollUp(F: Frame; org: LONGINT);
VAR heightUsed: INTEGER; begpos, startpos, p: LONGINT; K, L: Line;
BEGIN
	IF org >= F.text.len THEN (* last line *)
		org := LinesUp(F.text, F.text.len, 0); (* one line back *)
	END;
	begpos := org; NEW(L); F.do.Format(F, begpos, L); heightUsed := L.h + F.top + F.bottom;
	LOOP
		IF heightUsed >= F.H THEN EXIT END; (* used too much height already *)
		startpos := LinesUp(F.text, begpos, 1); (* lines back *)
		IF startpos = 0 THEN begpos := 0; EXIT END;
		(* format onwards *)
		NEW(L); F.do.Format(F, startpos, L); p := startpos + L.len;
		LOOP
			IF p = begpos THEN EXIT END; (* reached current "top" line *)
			IF p > begpos THEN HALT(99) END;
			IF L.eot THEN HALT(99) END;
			
			NEW(K); F.do.Format(F, p, K); p := p + K.len;
			K.next := L; L := K;
		END;
		
		(* formatted from guess startpos to current begpos. check how many lines fit *)
		K := L; 
		WHILE (K # NIL) & (K.h + heightUsed < F.H) DO
			(* lines fits *)
			INC(heightUsed, K.h); begpos := begpos - K.len;
			K := K.next
		END;
		IF (K # NIL) & (K.h + heightUsed >= F.H) THEN EXIT END;
	END;
	ScrollTo(F, begpos)
END ScrollUp;

PROCEDURE EditSlider*(F: Frame; R: Display3.Mask; VAR M: Oberon.InputMsg; x, y, w, h: INTEGER);
VAR L: Line; keysum, keys: SET; pos, org: LONGINT; X, Y: INTEGER;
BEGIN
	IF M.keys # {} THEN
		IF M.keys = {2} THEN (* scroll up *)
			TrackLine(F, R, keysum, x, y, org, L); M.res := 0;
			IF keysum # {0, 1, 2} THEN
				ScrollTo(F, org)
			END;
		ELSIF M.keys = {0} THEN
			TrackLine(F, R, keysum, x, y, org, L); M.res := 0;
			IF keysum # {0, 1, 2} THEN
				(*
				pos := LinesUp(F.text, org, LinesOf(F) - 1);
				ScrollTo(F, pos)
				*)
				ScrollUp(F, org)
			END;
		ELSIF M.keys = {1} THEN
			Input.Mouse(keys, X, Y); keysum := keys;
			WHILE keys # {} DO
				Input.Mouse(keys, X, Y); keysum := keysum+keys; Oberon.DrawCursor(Oberon.Mouse, Effects.Arrow, X, Y);
			END;
			M.res := 0; pos := F.org;
			IF keysum = {1, 0} THEN ScrollTo(F, 0);
			ELSIF keysum = {1, 2} THEN (* to end *)
				(*IF LinesOf(F) > 1 THEN pos := LinesUp(F.text, F.text.len, LinesOf(F) - 1) END;*)
				ScrollUp(F, F.text.len)
			ELSIF keysum # {0, 1, 2} THEN (* relative positioning *)
				pos := (F.text.len DIV h) * (y + h - Y);
				IF pos < 0 THEN pos := 0 
				ELSE pos := LinesUp(F.text, pos, 1);
				END;
				ScrollTo(F, pos);
			END;
		END;
	ELSE
		Gadgets.framehandle(F, M);
	END;
END EditSlider;

PROCEDURE locate(F: Frame; pos: LONGINT);
VAR p: LONGINT; L: Line; org: LONGINT;
BEGIN
	IF pos >= F.org THEN
		L := F.trailer.next; org := F.org;
		WHILE (L # F.trailer) & (pos >= org + L.len) DO INC(org, L.len); L := L.next END
	ELSE L := F.trailer
	END;
	IF L = F.trailer THEN (* not visible already *)
		IF pos - 50 <= 0 THEN
			ScrollTo(F, 0)
		ELSE
			p := LinesUp(F.text, pos - 50, 1);
			ScrollTo(F, p)
		END
	ELSIF (L.next = F.trailer) & (F.trailer.next # L) & (-L.base > F.H) THEN
		ScrollTo(F, F.org + F.trailer.next.len)
	END
END locate;

PROCEDURE Locate*(F: Frame; pos: LONGINT);
BEGIN
	locate(F, pos);
	SetCaret(F, pos)
END Locate;

PROCEDURE Edit*(F: Frame; R: Display3.Mask; x, y, w, h: INTEGER; VAR M: Oberon.InputMsg);
VAR keysum: SET; text: Texts.Text; tbeg, tend, time, objtime, pos: LONGINT; C: Oberon.ConsumeMsg;
	RR: Texts.Reader; chr: CHAR; g: Gadgets.Frame; S: Display.SelectMsg;
	b: Box; L: Line; I: Oberon.InputMsg; obj, obj0: Objects.Object; PM: Gadgets.PriorityMsg;
BEGIN
	IF (F.left > sliderW) & (M.X < x + sliderW) & (mayscroll IN F.state0) THEN
		EditSlider(F, R, M, x, y, w, h);
		RETURN;
	END;

	IF F.trailer = NIL THEN FormatFrame(F) END;
	b := LocateBox(F, M.X, M.Y, x, y, w, h, L);
	IF (b # NIL) & (maydelegate IN F.state0) THEN
		b.f.X := 0; b.f.Y := 0; I.dlink := M.dlink;
		I.id := M.id; I.keys := M.keys; I.X := M.X; I.Y := M.Y; I.x := x + b.x; I.y := y + h - 1 + L.base + b.voff; I.F := NIL; I.res := M.res;
		Gadgets.Send(F, x, y, b.f, I);
		M.res := I.res;
		IF M.res >= 0 THEN RETURN END
	END;
	IF (M.keys = {2}) & (mayfocus IN F.state0) THEN (* left *)
		IF ~F.car THEN
			IF sizeadjust IN F.state0 THEN (* bring to the front *)
				PM.F := F; PM.id := Gadgets.visible; PM.passon := FALSE; Display.Broadcast(PM)
			END;
			
			IF caption IN F.state0 THEN EXCL(F.state, Gadgets.transparent); NewMask(F) END;
			Oberon.Defocus (* destroys the mask *)
		ELSE
			Oberon.RemoveMarks(x, y, w, h); FlipCaretMsg(F, F.carpos); (* destroys the mask *)
			F.car := FALSE
		END;
		Gadgets.MakeMask(F, x, y, M.dlink, R);
		TrackCaret(F, R, keysum, x, y, w, h, F.carpos);
		pos := F.carpos.pos; SetCaretWithScroll(F, pos); F.car := TRUE; M.res := 0;
		IF (keysum = {2, 1}) & ~(locked IN F.state0) THEN (* copy from selection *)
			Oberon.GetSelection(text, tbeg, tend, time); Gadgets.GetSelection(obj, objtime);
			IF (time >= 0) & (time > objtime) THEN
				CopyStretch(text, tbeg, tend, W, F);
				Texts.Insert(F.text, pos, W.buf);
				SetCaretWithScroll(F, pos + (tend - tbeg))	(* ps - 7.5.97 *)
			ELSIF (objtime >= 0) & (objtime > time) THEN
				CopyList(obj, Objects.shallow, obj0); Gadgets.Integrate(obj0)
			ELSE
				Texts.Recall(W.buf);
				tend := pos + W.buf.len;
				Texts.Insert(F.text, pos, W.buf);
				SetCaretWithScroll(F, tend)
			END
		ELSIF keysum = {2, 0} THEN (* copy looks *)
			Oberon.GetSelection(text, tbeg, tend, time);
			IF (time >= 0) & (pos < F.text.len) THEN
				Texts.OpenReader(RR, F.text, pos); Texts.Read(RR, chr);
				IF (RR.lib # NIL) & (RR.lib IS Fonts.Font) THEN
					Texts.ChangeLooks(text, tbeg, tend, {0, 1, 2}, RR.lib, RR.col, RR.voff)
				END
			END
		END
	ELSIF (M.keys = {0}) & (mayselect IN F.state0) & ~(Gadgets.transparent IN F.state) THEN (* right *)
		IF (b # NIL) & (b.f # NIL) & (b.f IS Gadgets.Frame) THEN (* tracking on a box *)
			g := b.f(Gadgets.Frame);
			WITH g: Gadgets.Frame DO
				Oberon.FadeCursor(Oberon.Mouse);
				IF Gadgets.selected IN g.state THEN S.id := Display.reset ELSE S.id := Display.set END;
				S.F := g; S.res := -1; S.dlink := NIL; S.x := 0; S.y := 0; Objects.Stamp(S); g.handle(g, S);
				Gadgets.Update(g); keysum := M.keys;
				REPEAT Effects.TrackMouse(M.keys, M.X, M.Y, Effects.Arrow); keysum := keysum + M.keys; UNTIL M.keys = {};
				M.res := 0;
				(* ps - 29.8.96 *)
				IF (keysum = {0, 2}) & (S.id = Display.set) & ~(locked IN F.state0) THEN (* RL delete selection *)
					DeleteSelectedFrames(F.text);
				ELSIF keysum = {0, 1} THEN  (* RM copy to focus *)
					GetSelectedFrames(F.text, obj); CopyList(obj, Objects.shallow, obj0); Gadgets.Integrate(obj0);
				ELSE F.frametime := Oberon.Time();
				END
			END
		ELSIF Effects.Inside(M.X, M.Y, x + Effects.gravity, y + Effects.gravity, w - Effects.gravity*2, h - Effects.gravity*2) THEN
			 (* Tracking text *)
			TrackSelection(F, keysum, x, y, F.selbeg, F.selend, M.dlink); M.res := 0;
			(* only needed when no broadcast of flip selection messages:
				FlipSelectionMsg(F, F.selbeg, F.selend); *)
			F.sel := TRUE; F.time := Oberon.Time();
			IF keysum # {0} THEN
				tbeg := F.selbeg.pos; tend := F.selend.pos;
				IF (keysum = {0, 2}) & ~(locked IN F.state0) THEN (* delete *)
					Oberon.GetSelection(text, tbeg, tend, time);
					IF tend > F.text.len THEN tend := F.text.len END;
					Texts.Delete(F.text, tbeg, tend); Oberon.Defocus; SetCaret(F, tbeg); F.car := TRUE;
				ELSIF keysum = {0, 1}  THEN (* copy over *)
					Oberon.GetSelection(text, tbeg, tend, time);
					IF tend > F.text.len THEN tend := F.text.len END;
					C.F := NIL; C.text := text; C.beg := tbeg; C.end := tend; C.res := -1;
					Display.Broadcast(C)
				END
			END
		ELSE Gadgets.framehandle(F, M)
		END
	ELSIF M.keys = {1} THEN (* middle *)
		IF (b # NIL) & (maymvchildren IN F.state0) & Effects.InBorder(M.X, M.Y, x + b.x, y + h - 1 + L.base + b.voff, b.f.W, b.f.H) THEN (* child did not take middle click, so move it *)
			b.f.X := 0; b.f.Y := 0; M.x := x + b.x; M.y := y + h - 1 + L.base + b.voff;
			Gadgets.MoveFrame(b.f, M); M.res := 0;
		ELSIF (b = NIL) & Effects.Inside(M.X, M.Y, x + Effects.gravity, y + Effects.gravity, w - Effects.gravity*2, h - Effects.gravity*2) & (mayexecute IN F.state0) THEN (* execute a text command *)
			TrackWord(F, R, keysum, x, y, w, h, pos); M.res := 0;
			IF (pos >= 0) & (keysum # {0, 1, 2}) THEN F.do.Call(F, pos, keysum, M.dlink) END
		ELSE
			Gadgets.framehandle(F, M)
		END
	ELSE
		Gadgets.framehandle(F, M)
	END
END Edit;

PROCEDURE Right(F: Frame; nbr: SHORTINT);
VAR text: Texts.Text; beg, end, fLine, lLine: LONGINT; nr: SHORTINT; R: Texts.Reader; ch, dh: CHAR;
	tW: Texts.Writer;
	
	PROCEDURE AdjustFont(VAR W: Texts.Writer; VAR R: Texts.Reader);
	BEGIN
		IF (R.lib IS Fonts.Font) & (W.lib # R.lib) THEN Texts.SetFont(tW, R.lib) END
	END AdjustFont;

BEGIN
	Texts.OpenWriter(tW);
	text := F.text; beg := F.selbeg.pos; end := F.selend.pos;
	fLine := LinesUp(text, beg, 0); lLine := LinesUp(text, end - 1, 0);
	Texts.OpenReader(R, text, fLine); Texts.Read(R, ch); AdjustFont(tW, R);
	IF ~R.eot THEN
		IF ~(R.lib IS Fonts.Font) OR (ch # " ") & (ch # 09X) THEN ch := 09X END;
		nr := nbr;
		WHILE nr > 0 DO Texts.Write(tW, ch); DEC(nr); INC(beg); INC(end) END; Texts.Insert(text, lLine, tW.buf);
		WHILE fLine # lLine DO
			lLine := LinesUp(text, lLine - 1, 0);
			Texts.OpenReader(R, text, lLine); Texts.Read(R, dh); AdjustFont(tW, R);
			nr := nbr;
			WHILE nr > 0 DO Texts.Write(tW, ch); DEC(nr); INC(end) END; Texts.Insert(text, lLine, tW.buf)
		END;
		SetSelection(F, beg, end)
	END
END Right;

PROCEDURE Left(F: Frame; nbr: SHORTINT);
VAR text: Texts.Text; beg, end, fLine, lLine: LONGINT; nr: SHORTINT;

	PROCEDURE IsCh(T: Texts.Text; pos: LONGINT): BOOLEAN;
	(* tests if character in text T at position pos is a tabulator or space *)
		VAR R: Texts.Reader;	ch: CHAR;
	BEGIN
		Texts.OpenReader(R, T, pos); Texts.Read(R, ch);
		RETURN (ch = " ") OR (ch = 09X)
	END IsCh;

BEGIN
	text := F.text; beg := F.selbeg.pos; end := F.selend.pos;
	fLine := LinesUp(text, beg, 0); lLine := LinesUp(text, end - 1, 0);
	nr := nbr;
	WHILE (nr > 0) & IsCh(text, lLine) DO Texts.Delete(text, lLine, lLine + 1); DEC(nr); DEC(end) END;
	WHILE fLine < lLine DO
		lLine := LinesUp(text, lLine - 1, 0);
		nr := nbr;
		WHILE (nr > 0) & IsCh(text, lLine) DO Texts.Delete(text, lLine, lLine + 1); DEC(nr); DEC(end) END
	END;
	IF F.selbeg.org <beg THEN beg := beg - nbr + nr END;
	IF beg < end THEN SetSelection(F, beg, end) ELSE F.sel := FALSE END
END Left;

PROCEDURE Write(F: Frame; x, y: INTEGER; ch: CHAR; fnt: Objects.Library; col, voff: INTEGER);
VAR pos, hpos, flushpos, len: LONGINT; loc: Loc; L: Line; carX: INTEGER; setCarX: BOOLEAN;

	PROCEDURE InsertTabs(VAR pos: LONGINT);
	VAR pos0: LONGINT; R: Texts.Reader;
	BEGIN
		pos0 := LinesUp(F.text, pos, 0);
		Texts.OpenReader(R, F.text, pos0); Texts.Read(R, ch);
		WHILE ~R.eot & ((ch = 9X) OR (ch = " ")) DO
			Texts.Write(W, ch); INC(len); INC(pos); Texts.Read(R, ch)
		END;
	END InsertTabs;

	PROCEDURE InsertChar(F: Frame; ch: CHAR; fnt: Objects.Library; col, voff: INTEGER);
	BEGIN
		WITH F: Frame DO
			IF myfnt = NIL THEN W.lib := fnt; W.col := SHORT(col); W.voff := SHORT(voff)
			ELSE W.lib := myfnt; W.col := SHORT(mycol); W.voff := SHORT(myvoff)
			END;
			Texts.Write(W, ch); INC(len)
		END
	END InsertChar;
	
	PROCEDURE Flush;
	BEGIN
		IF len > 0 THEN Texts.Insert(F.text, flushpos, W.buf); INC(flushpos, len); len := 0; END;
	END Flush;
	
BEGIN
	pos := F.carpos.pos; flushpos := pos; len := 0; setCarX := FALSE;
	LOOP
		IF ch = LArrow THEN
			IF F.sel THEN Left(F, 1); pos := F.selend.pos;
			ELSE
				Flush;
				IF pos > F.org THEN pos := pos - 1 END;
			END
		ELSIF ch = RArrow THEN
			IF F.sel THEN Right(F, 1); pos := F.selend.pos;
			ELSE INC(pos)
			END
		ELSIF ch = 0C1X THEN (* up *)
			Flush;
			IF (pos > 0) & (F.carpos.org # 0) THEN
				carX := F.carX; setCarX := TRUE;
				F.do.LocateChar(F, x, y, x + F.carX, y + F.H - 1 + F.carpos.y + F.carpos.line.asr, loc);
				IF (loc.pos = pos) & (F.org > 0) THEN
					hpos := LinesUp(F.text, F.org, 1);
					LOOP
						NEW(L); F.do.Format(F, hpos, L);
						IF hpos + L.len = F.org THEN pos := hpos; EXIT
						ELSE INC(hpos, L.len)
						END;
						IF hpos > F.text.len THEN
							F.org := LinesUp(F.text, F.org, 1);
							F.trailer := NIL; Gadgets.Update(F);
							pos := F.org;
							EXIT
						END
					END;
					ScrollTo(F, pos)
				ELSE pos := loc.pos
				END
			END
		ELSIF ch = 0C2X THEN (* down *)
			Flush;
			IF pos < F.text.len THEN
				carX := F.carX; setCarX := TRUE;
				F.do.LocateChar(F, x, y, x + F.carX, y + F.H - 1 + F.carpos.y - F.carpos.line.dsr - 1, loc);
				IF (loc.pos = pos) & (loc.org + loc.line.len < F.text.len) THEN (* last line and space available*)
					ScrollTo(F, F.org + F.trailer.next.len);
					pos := loc.org + loc.line.len
				ELSE pos := loc.pos 
				END;
			END
		ELSIF ch = 0A2X THEN (* page up *)
			ScrollUp(F, F.org);
			pos := F.org
		ELSIF ch = 0A3X THEN (* page down *)
			Flush;
			L := F.trailer.next;
			hpos := F.org;
			WHILE L.next # F.trailer DO hpos := hpos + L.len; L := L.next END;
			ScrollTo(F, hpos);
			pos := hpos
		ELSIF ch = 0A8X THEN (* HOME *)
			Flush;
			IF pos > 0 THEN
				pos := F.carpos.org
			END
		ELSIF ch = 0A9X THEN (* END *)
			Flush;
			pos := F.carpos.org + F.carpos.line.len - 1;
			carX := MAX(INTEGER) DIV 2; setCarX := TRUE
		ELSIF ~(locked IN F.state0) THEN
			IF ch = 7FX THEN (* Delete *)
				Flush;
				IF pos > 0 THEN
					RemoveCaret(F); RemoveSelection(F);
					Texts.Delete(F.text, pos - 1, pos);
					DEC(pos); flushpos := pos
				END
			ELSIF ch = 0A1X THEN (* Delete right *)
				Flush;
				IF pos < F.text.len THEN
					RemoveCaret(F); RemoveSelection(F);
					Texts.Delete(F.text, pos, pos+1);
				END
			ELSIF ch = 0DX THEN	
				RemoveCaret(F); RemoveSelection(F);
				InsertChar(F, ch, fnt, col, voff);
				IF autoindent IN F.state0 THEN InsertTabs(pos) END;
				INC(pos)
			ELSIF (ch >= " ") OR (ch = 09X) OR (ch = 0DX) THEN
				RemoveCaret(F); RemoveSelection(F);
				InsertChar(F, ch, fnt, col, voff);
				INC(pos)
			END
		END;
		IF Input.Available() > 0 THEN
			Input.Read(ch)
		ELSE
			EXIT
		END
	END;
	Flush;
	SetCaretWithScroll(F, pos);
	IF setCarX THEN F.carX := carX END
END Write;

PROCEDURE Recall (F: Frame);
VAR buf: Texts.Buffer; pos: LONGINT;
BEGIN
	NEW(buf); Texts.OpenBuf(buf);
	Texts.Recall(buf); pos := F.carpos.pos + buf.len;
	Texts.Insert(F.text, F.carpos.pos, buf);
	SetCaret(F, pos)
END Recall;

PROCEDURE Update*(F: Frame; dlink: Objects.Object; id: INTEGER; beg, end: LONGINT; x, y, w, h: INTEGER; stamp: LONGINT;
	VAR d: DrawDesc);
VAR corr: LONGINT;
	prevL: Line; prevorg: LONGINT; prevY: INTEGER;
	(*
		0 - first formatted line/Y0 is top boundary
		1 - last formatted line/Y1 is bottom boundary/org1 on next line
		2 - last line that may be copied/area starts after 1/Y2 is bottom boundary/L2 = L1 if nothing to copy
		3 - sync point
		4 - last line to pour new/L4 = L2 if nothing/starts at L2.next
	*)
BEGIN
	scrollhint := FALSE;
	IF F.trailer = NIL THEN RETURN END;
	
	IF id = 1 THEN (* insert *) corr := end - beg;
	ELSIF id = 2 THEN (* delete *) corr := -(end - beg);
	ELSE corr := 0
	END;

	IF stamp = F.stamp THEN (* second time around *)
		d := F.desc;
		RETURN
	END;
	(* ! *)
	F.stamp := stamp;
	(* ! *)
	
	d.L0 := NIL; d.L1 := NIL; d.L2 := NIL; d.L3 := NIL; d.L4 := NIL;
	(* old IF beg < F.org THEN F.org := F.org + corr *)
	IF end < F.org THEN INC(F.org, corr)
	ELSE
		IF beg < F.org THEN INC(F.org, corr);
			IF F.org < 0 THEN F.org := 0 END;
			corr := 0; beg := F.org
		END;
		d.Y0 := -F.top + 1; d.L0 := F.trailer.next; d.org0 := F.org; prevL := NIL;
		(* find the line that changes *)
		WHILE (d.L0 # F.trailer) & (beg >= d.org0 + d.L0.len) DO
			prevL := d.L0; prevorg := d.org0; prevY := d.Y0;
			DEC(d.Y0, d.L0.h); INC(d.org0, d.L0.len);
			d.L0 := d.L0.next
		END;
		
		IF d.L0 = F.trailer THEN d.L0 := NIL; d.Y4 := MIN(INTEGER);
		ELSE
			(* [org0, Y0, L0] = update starts *)
			d.org3 := d.org0 + d.L0.len; d.Y3 := d.Y0 - d.L0.h; d.L3 := d.L0.next; (* [org3, Y3, L3] = sync point *)
			IF corr <= 0 THEN (* delete or replace: find new sync point *) 
				WHILE (d.L3 # F.trailer) & (d.org3 <= end) DO INC(d.org3, d.L3.len); DEC(d.Y3, d.L3.h); d.L3 := d.L3.next END;
			END;
			
			(* this must be here and not before ^ *)
			IF (blockadj IN F.state0) & (prevL # NIL) THEN (* have to format the previous line *)
			
				(* make a backup of the first line for optimization *)
				NEW(d.LL); d.LL^ := prevL^; d.LL.next := NIL; d.orgL := prevorg;
				(* end of backup *)
				
				F.do.Format(F, prevorg, prevL);  (* does not allocate new box descriptors *)
				IF prevorg + prevL.len # d.org0 THEN (* no sync *)
					d.L0 := prevL; d.org0 := prevorg; d.Y0 := prevY
				ELSE (* conventional backup *)
					d.LL^ := d.L0^; d.LL.next := NIL; d.orgL := d.org0;
				END
			ELSE
				(* make a backup of the first line for optimization *)
				NEW(d.LL); d.LL^ := d.L0^; d.LL.next := NIL; d.orgL := d.org0;
				(* end of backup *)
			END;
			
			(* format the line first line*)
			d.L1 := d.L0; d.Y1 := d.Y0; d.org1 := d.org0;
			
			F.do.Format(F, d.org1, d.L1); DEC(d.Y1, d.L1.asr); d.L1.base := d.Y1; DEC(d.Y1, d.L1.dsr); INC(d.org1, d.L1.len);
			LOOP
				IF d.Y1 <= -h + F.bottom THEN EXIT END; (* ! *)
				IF d.L1.eot THEN EXIT END;
				
					(* special sync *)
					WHILE (d.org3 + corr < d.org1) & (d.L3 # F.trailer) DO INC(d.org3, d.L3.len); DEC(d.Y3, d.L3.h); d.L3 := d.L3.next END;
					
				IF (d.org1 = d.org3 + corr) & F.do.InSync(F, d.L1, d.L3) THEN (* synchronized *) EXIT END;
				NEW(d.L1.next); d.L1 := d.L1.next;
				F.do.Format(F, d.org1, d.L1); DEC(d.Y1, d.L1.asr); d.L1.base := d.Y1; DEC(d.Y1, d.L1.dsr); INC(d.org1, d.L1.len);
			END;
			d.L2 := d.L1; d.Y2 := d.Y1; d.org2 := d.org1; d.L4 := d.L1; d.Y4 := d.Y1;
			IF d.L1.eot OR (d.Y1 <= -h + F.bottom) THEN d.L1.next := F.trailer;
				IF (d.Y1 <= -h + F.bottom) & (id = insert) & (end = F.text.len) THEN scrollhint := TRUE END
			ELSE
				d.L1.next := d.L3; (* hook up sync point *)
				IF d.Y1 # d.Y3 THEN (* format all the rest, copying needed parts *)
					(* L2 is last line formatted, L2.next is possible start of lines that can be copied *)
					d.t := d.Y3; (* sync point *)
					LOOP
						IF d.L2.next = F.trailer THEN EXIT END;
						IF d.Y2 - d.L2.next.h <= -h + F.bottom THEN EXIT END; (* no more space *)
						IF d.t - d.L2.next.h <= -h + F.bottom THEN EXIT END; (* no more space *)
						d.L2 := d.L2.next;
						DEC(d.Y2, d.L2.asr); d.L2.base := d.Y2; DEC(d.Y2, d.L2.dsr); INC(d.org2, d.L2.len);
						DEC(d.t, d.L2.h);
						IF d.L2.eot THEN EXIT END;
					END;
					(* L2 is last line that may be copied *)
					d.L4 := d.L2; d.Y4 := d.Y2; d.org4 := d.org2;
					IF ~d.L2.eot & (d.Y2 > -h + F.bottom) THEN (* add the extra lines at the bottom*)
						(* L2 is last lined copied *)
						LOOP
							IF d.Y4 <= -h + F.bottom THEN EXIT END; (* ! *)
							IF d.L4.eot THEN EXIT END;
							NEW(d.L4.next); d.L4 := d.L4.next;
							F.do.Format(F, d.org4, d.L4); DEC(d.Y4, d.L4.asr); d.L4.base := d.Y4; DEC(d.Y4, d.L4.dsr); INC(d.org4, d.L4.len);
						END;
					END;
					d.L4.next := F.trailer;
				END
			END;
		END
	END
END Update;

PROCEDURE DrawChanges(F: Frame; dlink: Objects.Object; id: INTEGER; beg, end: LONGINT; x, y, w, h: INTEGER; 
	stamp: LONGINT; d: DrawDesc);
VAR L: Line; org: LONGINT; M, clipM: Display3.Mask; cx, cy, cw, ch: INTEGER; copy: BOOLEAN;

BEGIN
	IF F.trailer = NIL THEN RETURN END;
	F.stamp := stamp; Oberon.RemoveMarks(x, y, w, h);
	Gadgets.MakeMask(F, x, y, dlink, M);
	
	copy  := Display3.Rectangular(M, cx, cy, cw, ch);  ClipAgainst(cx, cy, cw, ch, M.X, M.Y, M.W, M.H);
	copy := copy & (cx = x) & (cy = y) & (cw = w) & (ch = h);
	
	IF beg >= F.org THEN
		
		RestoreSlider(F, M, x, y, w, h);
		
		(* Display update operations *)
		(* copy *)
		IF (d.L1 # NIL) & (d.L1 # d.L2) (*& (d.t < d.Y1)*) THEN
			IF copy THEN
				Oberon.FadeCursor(Oberon.Mouse);
				Display3.Copy(M, clipM);
				Display3.Intersect(clipM, x + F.left, y + F.H - 1 + d.t, F.W - F.left - F.right, d.Y3 - d.t);
				Display3.Intersect(clipM, M.X, M.Y, M.W, M.H);
				Display3.CopyMask(clipM, clipM.x, clipM.y + (d.Y2 - d.t), Display.replace);
				L := d.L1; org := d.org1;
				WHILE L # d.L2 DO
					L := L.next; INC(org, L.len); 
				END
			ELSE (* draw it *)
				L := d.L1; org := d.org1;
				WHILE L # d.L2 DO
					L := L.next;
					F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len);
				END
			END
		END;

		(* draw newly formatted part *)
		IF d.L0 # NIL THEN
			L := d.L0; org := d.org0;
			
			(* check for fast display *)
			IF (org = d.orgL) & (L.base =  d.LL.base) & (L.h = d.LL.h) & (L.asr = d.LL.asr) & (L.dsr = d.LL.dsr) & (d.LL.spaces = 0) THEN
				L.draw := beg;
			ELSE L.draw := 0
			END;
			
			F.do.Display(F, M, x, y, org, L, dlink);
			L.draw := 0; (* reset *)
			WHILE L # d.L1 DO
				INC(org, L.len); L := L.next;
				F.do.Display(F, M, x, y, org, L, dlink);
			END
		END;
		
		(* draw newly poured part *)
		IF d.L2 # NIL THEN
			L := d.L2; org := d.org2;
			WHILE L # d.L4 DO
				L := L.next;
				F.do.Display(F, M, x, y, org, L, dlink); INC(org, L.len);
			END
		END;
		
		IF (d.Y4 >= -h) & (d.Y1 # d.Y3) THEN
			F.do.Background(F, M, x, y, F.left, -F.H + 1, F.W, d.Y4 - (-F.H + 1))
		END;
		IF Gadgets.selected IN F.state THEN Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END;
	END
END DrawChanges;

PROCEDURE AdjustChild*(F: Frame; x, y: INTEGER; VAR M: Display.ModifyMsg);
VAR L, trailer: Line; b: Box; org: LONGINT; isChild: BOOLEAN;
	min, max: LONGINT;
	xx, yy, oldmode, fw, fh: INTEGER; 
BEGIN
	isChild := FALSE; min := MAX(LONGINT); max := MIN(LONGINT);
	trailer := F.trailer;
	IF trailer = NIL THEN RETURN END;
	org := F.org; L := trailer.next; (* send to everybody *)
	xx := M.x; yy := M.y; 
	WHILE (L # NIL) & (L # trailer) DO
		b := L.box;
		WHILE b # NIL DO
			M.x := x + (b.x - b.f.X); M.y := y + F.H - 1 + (L.base - b.f.Y) + b.voff;
			IF b.f = M.F THEN oldmode := M.mode; M.mode := Display.state; isChild := TRUE;
			(* ps - 24.5.96
				M.X := 0; M.Y := 0; M.dX := 0; M.dY := 0; (* this works for some mysterious reason *)
			*)
				IF org + b.org < min THEN min := org + b.org END;
				IF org + b.org > max THEN max := org + b.org END;
			END;
			Gadgets.Send(F, x, y, b.f, M);
			b.f.X := 0; b.f.Y := 0;
			IF b.f = M.F THEN M.mode := oldmode END;
			
			b := b.next;
		END;
		org := org + L.len; L := L.next;
	END;
	
	M.x := xx; M.y := yy;
	
	(* because many gadget simply assume that they are automatically drawn after an adjust message. This
	means the line flickers although nothing needs to be redrawn *)
	IF ~(Gadgets.transparent IN F.state) & isChild & (TRUE OR (M.dW # 0) OR (M.dH # 0)) THEN
		RemoveCaret(F); RemoveSelection(F);
		Update(F, M.dlink, change, min, max+1, x, y, F.W, F.H, M.stamp, F.desc);
		IF M.mode = Display.display THEN
			DrawChanges(F, M.dlink, change, min, max+1, x, y, F.W, F.H, M.stamp, F.desc)
		END;
		IF sizeadjust IN F.state0 THEN
			OptimalSize(F, fw, fh);
			IF (fw = F.W) & (fh = F.H) THEN
			ELSE AdjustSize(F, fw, fh);
			END
		END
	END;
END AdjustChild;

PROCEDURE UpdateChild*(F: Frame; x, y: INTEGER; VAR M: Gadgets.UpdateMsg);
VAR L, trailer: Line; b: Box; org: LONGINT; isChild: BOOLEAN;
	min, max: LONGINT;  u, v: INTEGER; o: Objects.Object;
BEGIN
	u := M.x; v := M.y;
	isChild := FALSE; min := MAX(LONGINT); max := MIN(LONGINT);
	trailer := F.trailer;
	IF trailer = NIL THEN RETURN END;
	org := F.org; L := trailer.next; (* send to everybody *)
	WHILE (L # NIL) & (L # trailer) DO
		b := L.box;
		WHILE b # NIL DO
			M.x := x + (b.x - b.f.X); M.y := y + F.H - 1 + (L.base - b.f.Y) + b.voff;
			o := M.obj;
			WHILE (o # NIL) & (o # b.f) DO
				o := o.slink
			END;
			IF (b.f = o) & (b.f IS Gadgets.Frame) & (Gadgets.transparent IN b.f(Gadgets.Frame).state) THEN
				isChild := TRUE;
				IF org + b.org < min THEN min := org + b.org END;
				IF org + b.org > max THEN max := org + b.org END;
			END;
			Gadgets.Send(F, x, y, b.f, M);
			b := b.next;
		END;
		org := org + L.len; L := L.next;
	END;
	IF ~(Gadgets.transparent IN F.state) & isChild THEN
		RemoveCaret(F); RemoveSelection(F);
		Update(F, M.dlink, change, min, max+1, x, y, F.W, F.H, M.stamp, F.desc);
		DrawChanges(F, M.dlink, change, min, max+1, x, y, F.W, F.H, M.stamp, F.desc);
	END;
	M.x := u; M.y := v;
END UpdateChild;

PROCEDURE RemoveChild*(F: Frame; x, y: INTEGER; VAR M: Display.ControlMsg);
VAR f: Texts.Finder; o, obj: Objects.Object; first: LONGINT;
BEGIN
	first := -1;
	LOOP
		Texts.OpenFinder(f, F.text, 0);
		IF f.eot THEN EXIT END;
		LOOP
			first := f.pos;
			Texts.FindObj(f, o);
			IF (o # NIL) & (o IS Display.Frame) & (M.F = o) THEN
				EXIT
			END;
			IF f.eot THEN EXIT END;
		END;
		IF (o # NIL) & (o IS Display.Frame) THEN (* remove of lists of gadgets *)
			obj := M.F;
			WHILE obj # NIL DO
				IF obj = o THEN Texts.Delete(F.text, first, first+1) END;
				obj := obj.slink
			END
		END;
		IF f.eot THEN EXIT END;
	END
END RemoveChild;

PROCEDURE InsertObj(F: Frame; pos: LONGINT; obj: Objects.Object);
VAR W: Texts.Writer; T: Texts.Text;
BEGIN
	T := F.text;
	Texts.OpenWriter(W); Texts.WriteObj(W, obj); Texts.Insert(T, pos, W.buf)
END InsertObj;

PROCEDURE FormatFrame*(F: Frame);
VAR Y: INTEGER; org: LONGINT; L: Line;
BEGIN
	Y := -F.top + 1;
	IF F.org > F.text.len THEN F.org := 0 END;
	org := F.org;
	NEW(F.trailer);
	L := F.trailer; NEW(L.next); L := L.next; 
	F.do.Format(F, org, L); DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len;
	LOOP
		IF Y <= -F.H + F.bottom THEN EXIT END; (* ! *)
		IF L.eot THEN EXIT END;
		NEW(L.next); L := L.next;
		F.do.Format(F, org, L); DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len;
	END;
	L.next := F.trailer;
END FormatFrame;

PROCEDURE RestoreFrame*(F: Frame; M: Display3.Mask; x, y, w, h: INTEGER; dlink: Objects.Object);
VAR Y: INTEGER; org: LONGINT; L: Line;
BEGIN
	IF F.trailer = NIL THEN FormatFrame(F) END;
	F.do.Background(F, M, x, y, 0, -F.H + 1, F.W, F.H);	(* erase background *)
	(* F.do.Background(F, M, x, y, 0, -F.top + 1, F.W, F.top); (* top line *) *)
	RestoreSlider(F, M, x, y, w, h);

	L := F.trailer.next; Y := -F.top + 1; org := F.org;
	WHILE L # F.trailer DO
		F.do.Display(F, M, x, y, org, L, dlink); DEC(Y, L.h); org := org + L.len;
		L := L.next;
	END;
	
	IF Y >= -F.H THEN
		F.do.Background(F, M, x, y, F.left, -F.H + 1, F.W, Y - (-F.H + 1));
	END;
	
	IF F.car THEN FlipCaret(F, M, x, y, w, h, F.carpos) END;
	IF F.sel THEN FlipSelection(F, M, x, y, F.selbeg, F.selend) END;
	
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END;
END RestoreFrame;

PROCEDURE RestoreFrameArea*(F: Frame; M: Display3.Mask; x, y, w, h, U, V, W, H: INTEGER; dlink: Objects.Object);
VAR Y: INTEGER; org: LONGINT; L: Line;
BEGIN
	Oberon.RemoveMarks(x + U, y + F.H - 1 + V, W, H);
	IF F.trailer = NIL THEN FormatFrame(F) END;
	F.do.Background(F, M, x, y, 0, -F.top + 1, F.W, F.top); (* top line *)
	RestoreSlider(F, M, x, y, w, h);

	L := F.trailer.next; Y := -F.top + 1; org := F.org;
	WHILE L # F.trailer DO
		IF Effects.Intersect(U, V, W, H, 0, L.base - L.dsr, w, L.h) THEN
			F.do.Display(F, M, x, y, org, L, dlink);
		END;
		DEC(Y, L.h); org := org + L.len;
		L := L.next;
	END;
	
	IF Y >= -F.H THEN
		F.do.Background(F, M, x, y, F.left, -F.H + 1, F.W, Y - (-F.H + 1));
	END;
	
	IF F.car THEN FlipCaret(F, M, x, y, w, h, F.carpos) END;
	IF F.sel THEN FlipSelection(F, M, x, y, F.selbeg, F.selend) END;
	
	IF Gadgets.selected IN F.state THEN Display3.FillPattern(M, Display3.white, Display3.selectpat, x, y, x, y, w, h, Display.paint) END;
END RestoreFrameArea;

PROCEDURE ChildRestore(F: Frame; VAR M: Display.DisplayMsg; x, y: INTEGER; dlink: Objects.Object);
VAR L: Line; b: Box; R: Display3.Mask;
BEGIN
	IF F.trailer # NIL THEN
		R := NIL; L := F.trailer.next;
		WHILE (L # F.trailer) & (L # NIL) DO
			b := L.box;
			WHILE b # NIL DO
				IF (b.f = M.F) & (b.f IS Gadgets.Frame) & (Gadgets.transparent IN b.f(Gadgets.Frame).state) THEN
					IF R = NIL THEN Gadgets.MakeMask(F, x, y, dlink, R) END;
					(* Oberon.RemoveMarks(x + b.x - b.f.X, y + F.H - 1 + L.base + b.voff, b.f.W, b.f.H); *)
					F.do.Background(F, R, x, y, b.x, L.base + b.voff, b.f.W, b.f.H)
				END;
				b := b.next
			END;
			L := L.next
		END
	END
END ChildRestore;

PROCEDURE ChildRestoreSelection(F: Frame; VAR M: Display.DisplayMsg; x, y: INTEGER; dlink: Objects.Object);
VAR L: Line; b: Box; R: Display3.Mask; org: LONGINT;
BEGIN
	IF F.trailer # NIL THEN
		R := NIL; L := F.trailer.next; org := F.org;
		WHILE (L # F.trailer) & (L # NIL) DO
			b := L.box;
			WHILE b # NIL DO
				IF (b.f = M.F) & (b.f IS Gadgets.Frame) & (Gadgets.transparent IN b.f(Gadgets.Frame).state) THEN
					IF (org + b.org >= F.selbeg.pos) & (org + b.org < F.selend.pos) THEN
						IF R = NIL THEN Gadgets.MakeMask(F, x, y, dlink, R) END;
						Display3.ReplConst(R, F.invertC, x + b.x, y + F.H - 1 + L.base + b.voff, b.f.W, b.f.H, Display.invert) 
					END
				END;
				b := b.next
			END;
			INC(org, L.len); L := L.next
		END
	END
END ChildRestoreSelection;

PROCEDURE ChildUpdate(F: Frame; VAR M: Gadgets.UpdateMsg; x, y: INTEGER; dlink: Objects.Object);
VAR L: Line; b: Box; R: Display3.Mask;
BEGIN
	R := NIL;
	IF F.trailer # NIL THEN
		L := F.trailer.next;
		WHILE (L # F.trailer) & (L # NIL) DO
			b := L.box;
			WHILE b # NIL DO
				IF (b.f = M.obj) & (b.f IS Gadgets.Frame) & (Gadgets.transparent IN b.f(Gadgets.Frame).state) THEN
					IF R = NIL THEN RemoveCaret(F); RemoveSelection(F); Gadgets.MakeMask(F, x, y, dlink, R); END;
					(* Oberon.RemoveMarks(x + b.x - b.f.X, y + F.H - 1 + L.base + b.voff, b.f.W, b.f.H); *)
					F.do.Background(F, R, x, y, b.x, L.base + b.voff, b.f.W, b.f.H);
				END;
				b := b.next;
			END;
			L := L.next
		END
	END
END ChildUpdate;

PROCEDURE CopyFrame*(VAR M: Objects.CopyMsg; from, to: Frame);
VAR W: Texts.Writer;
BEGIN Gadgets.CopyFrame(M, from, to); to.state0 := from.state0;
	to.do := from.do; to.text := from.text; to.org := from.org; to.invertC := from.invertC;
	to.left := from.left; to.right := from.right; to.top := from.top; to.bottom := from.bottom;
	to.border := from.border; to.col := from.col;
	IF (deepcopy IN from.state0) OR (M.id = Objects.deep) THEN
		NEW(to.text); Texts.Open(to.text, "");
		IF from.text.len > 0 THEN
			Texts.OpenWriter(W);
			CopyStretch(from.text, 0, from.text.len, W, to); Texts.Append(to.text, W.buf)
		END
	END;
END CopyFrame;

PROCEDURE StoreFrame(F: Frame; VAR M: Objects.FileMsg);
BEGIN
	Files.WriteNum(M.R, Version);
	Files.WriteSet(M.R, F.state0); Files.WriteLInt(M.R, F.org);
	Files.WriteInt(M.R, F.left); Files.WriteInt(M.R, F.right); Files.WriteInt(M.R, F.bottom); Files.WriteInt(M.R, F.top);
	Gadgets.WriteRef(M.R, F.lib, F.text);
	Files.WriteInt(M.R, F.col);
	Gadgets.framehandle(F, M)
END StoreFrame;

PROCEDURE LoadFrame(F: Frame; VAR M: Objects.FileMsg);
VAR ver: LONGINT; obj: Objects.Object;
BEGIN
	Files.ReadNum(M.R, ver);
	IF (ver # 3) & (ver # 4) THEN HALT(99) END;
	Files.ReadSet(M.R, F.state0); Files.ReadLInt(M.R, F.org);
	Files.ReadInt(M.R, F.left); Files.ReadInt(M.R, F.right); Files.ReadInt(M.R, F.bottom); Files.ReadInt(M.R, F.top);
	Gadgets.ReadRef(M.R, F.lib, obj);
	IF (obj # NIL) & (obj IS Texts.Text) THEN
		F.text := obj(Texts.Text);
		IF F.org > F.text.len THEN F.org := 0 END
	END;
	IF ver = 4 THEN Files.ReadInt(M.R, F.col) END;
	IF F.col < 0 THEN F.col := Display3.textbackC END;
	Gadgets.framehandle(F, M)
END LoadFrame;

PROCEDURE FrameLink (F: Frame; VAR M: Objects.LinkMsg);
BEGIN
	IF (M.id = Objects.get) & (M.name = "Model") THEN M.obj := F.text; M.res := 0
	ELSIF (M.id = Objects.set) & (M.name = "Model") THEN
		IF (M.obj # NIL) & (M.obj IS Texts.Text) THEN
			RemoveCaret(F); RemoveSelection(F);
			F.org := 0; F.trailer := NIL; F.text := M.obj(Texts.Text); Gadgets.Update(F); M.res := 0
		END
	ELSE Gadgets.framehandle(F, M)
	END
END FrameLink;

(** Return the size in which the frame's text will fit exactly *)
PROCEDURE Dimensions*(F: Frame; VAR w, h: INTEGER);
VAR l: Line;  end: LONGINT; R: Texts.Reader;
BEGIN
	h := 0; w := 0; 
	l := F.trailer.next; end := F.org;
	WHILE (l # F.trailer) & (l # NIL) DO INC(h, l.h); 
		w := SHORT(Max(w, l.w + eolW));
		end := end + l.len;
		(* IF (l.next = F.trailer) & (end = F.text.len) & (h = 0) THEN INC(h, 12) END; *)
		l := l.next;
	END;
	IF end < F.text.len THEN NEW(l);
		Texts.OpenReader(R, F.text, end);
		WHILE end < F.text.len DO
			F.do.Format(F, end, l); INC(h, l.h);
			w := SHORT(Max(w, l.w));
			end := end + l.len;
		END;
	END;
	w := w + F.left;
	h := h + F.top + F.bottom + 2; 
END Dimensions;

PROCEDURE OptimalSize(F: Frame; VAR w, h: INTEGER);
VAR W, H: INTEGER;
BEGIN
	w := F.W; h := F.H;
	IF (sizeadjust IN F.state0) & ~(Gadgets.lockedsize IN F.state) THEN
		Dimensions(F, W, H);
		IF (shrink IN F.state0) & ((F.W # W) OR (F.H # H)) THEN
			w := W; h := H;
		END;
		IF grow IN F.state0 THEN
			IF H > F.H THEN h := H END;
			IF W > F.W THEN w := W END;
		END;
	END
END OptimalSize;

PROCEDURE AdjustSize(F: Frame; w, h: INTEGER);
VAR car: BOOLEAN; A: Display.ModifyMsg; pos: LONGINT;
BEGIN
	IF (w # F.W) OR (h # F.H) THEN
		car := F.car; pos := F.carpos.pos; F.car := FALSE;
		A.id := Display.extend; A.F := F; 
		A.Y := F.Y + F.H - h; A.X := F.X; A.W := w; A.H := h;
		A.dX := 0; A.dW := w - F.W; A.dH := h - F.H; A.dY := A.Y - F.Y; A.mode := Display.display;
		Display.Broadcast(A);
		IF car THEN SetCaret(F, pos); END;
	END
END AdjustSize;

PROCEDURE Title(VAR headertext: ARRAY OF CHAR);
BEGIN
	IF headertext # "" THEN
		Printer.UseColor(0, 0, 0);
		Printer.String(PrinterleftX, HeaderY, headertext, Fonts.Default)
	END
END Title;

PROCEDURE Pageno(pageno: INTEGER);
VAR pno: ARRAY 8 OF CHAR;
BEGIN
	Strings.IntToStr(pageno, pno);
	Printer.UseColor(0, 0, 0);
	Printer.String(PagenoX, HeaderY, pno, Fonts.Default)
END Pageno;

PROCEDURE PrintText*(F: Frame; VAR headertext: ARRAY OF CHAR);
VAR org: LONGINT; L: Line; Y: INTEGER; output, pagebreak: BOOLEAN; R: Display3.Mask; pageno: INTEGER;
BEGIN
	InitPagePosition;
	R := NIL; F.mask := NIL; F.absX := 0; F.absY := 0;
	org := 0; pageno := 1;
	(*IF 1 IN printOpts THEN
		Title(headertext)
	END;
	IF 0 IN printOpts THEN
		Pageno(pageno)
	END;*)
	Y := PrintertopY; output := FALSE;
	NEW(L);
	LOOP
		IF L.eot THEN EXIT END;
		F.do.PrintFormat(F, org, L, pagebreak);
		IF (Y - L.h < PrinterbotY) OR pagebreak THEN Printer.Page(1); Y := PrintertopY; output := FALSE; INC(pageno) END;
		DEC(Y, L.asr); L.base := Y;
		IF ~output THEN
			IF 1 IN printOpts THEN
				Title(headertext)
			END;
			IF 0 IN printOpts THEN
				Pageno(pageno)
			END			
		END;
		F.do.Print(F, R, PrinterleftX, 0, org, L, NIL); output := TRUE; DEC(Y, L.dsr); INC(org,  L.len);
	END;
	IF output THEN Printer.Page(1) END;
END PrintText;

PROCEDURE P(x: INTEGER): INTEGER;
BEGIN RETURN SHORT(x * Display.Unit DIV Printer.Unit)
END P;

PROCEDURE PrintTextGadget(F: Frame; VAR M: Display.DisplayMsg);
VAR R: Display3.Mask; L: Line; Y, left, pos: INTEGER; org: LONGINT; pagebreak: BOOLEAN;

BEGIN
	Gadgets.MakePrinterMask(F, M.x, M.y, M.dlink, R);
	F.absX := M.x; F.absY := M.y;
	IF flat IN F.state0 THEN
		Printer3.ReplConst(R, Display3.BG, M.x, M.y, P(F.W), P(F.H), Display.replace)
	ELSE
		Printer3.FilledRect3D(R, Display3.bottomC, Display3.bottomC, Display3.BG, M.x, M.y, P(F.W), P(F.H), 1, Display.replace)
	END;
	
	IF (F.left > sliderW) & (mayscroll IN F.state0) THEN
		Printer3.ReplConst(R, Display.FG, M.x + P(sliderW), M.y + 1, 1, P(F.H)-2, Display.replace);
		pos := M.y + P(F.H) - P(2) - SHORT(F.org * (P(F.H) - 2) DIV (F.text.len+1));
		Printer3.FilledRect3D(R, Display3.topC, Display3.bottomC, Display3.groupC, M.x+2, pos - 4, P(8), P(3), 1, Display.replace);
		left := P(F.left)
	ELSE left := 0
	END;
	
	Y := M.y + P(F.H - 1); org := F.org;
	NEW(L);
	LOOP
		IF L.eot OR (Y < M.y) THEN EXIT END;
		F.do.PrintFormat(F, org, L, pagebreak);
		DEC(Y, L.asr); L.base := Y;
		F.do.Print(F, R, M.x + left, M.y, org, L, M.dlink); DEC(Y, L.dsr); INC(org,  L.len);
	END;
END PrintTextGadget;

PROCEDURE Print(F: Frame; x, y: INTEGER; VAR M: Display.DisplayMsg);
VAR s: ARRAY 2 OF CHAR;
BEGIN
	IF M.id = Display.contents THEN
		s := ""; PrintText(F, s);
	ELSE PrintTextGadget(F, M)
	END
END Print;

PROCEDURE InScrollBar(F: Frame; X, Y, x, y: INTEGER): BOOLEAN;
BEGIN
	RETURN (mayscroll IN F.state0) & Effects.Inside(X, Y, x, y, F.left, F.H);
END InScrollBar;

PROCEDURE LocateMsg(F: Frame; VAR M: Display.LocateMsg);
VAR b: Box; L: Line; x, y: INTEGER;
BEGIN
	b := LocateBox(F, M.X, M.Y, M.x + F.X, M.y + F.Y, F.W, F.H, L);
	IF b # NIL THEN
		x := M.x; y := M.y; b.f.X := 0; b.f.Y := 0;
		M.x := M.x + F.X + b.x; M.y := M.y + F.Y + F.H - 1 + L.base + b.voff;
		Gadgets.Send(F, M.x + F.X, M.y + F.Y, b.f, M);
		M.x := x; M.y := y;
		IF M.F = NIL THEN Gadgets.framehandle(F, M) END;
	ELSE Gadgets.framehandle(F, M)
	END
END LocateMsg;

PROCEDURE ModifyFrame(F: Frame; VAR M: Display.ModifyMsg);
VAR Y, y, h: INTEGER; org: LONGINT; L: Line; D: Display.DisplayMsg; O: Display3.OverlapMsg; mask: Display3.Mask;
BEGIN
	RemoveCaret(F); RemoveSelection(F);
	(* data structure adjust *)
	IF (F.trailer # NIL) & (M.H > 0) & (M.H # F.H) THEN
		Y := -F.top + 1; org := F.org; L := F.trailer.next; 
		IF M.dH > 0 THEN (* got bigger *)
			WHILE L.next # F.trailer DO DEC(Y, L.h); org := org + L.len; L := L.next END;
			org := org + L.len; DEC(Y, L.h);
			LOOP
				IF Y <= -M.H + F.bottom THEN EXIT END; (* ! *)
				IF L.eot THEN EXIT END;
				NEW(L.next); L := L.next;
				F.do.Format(F, org, L); DEC(Y, L.asr); L.base := Y; DEC(Y, L.dsr); org := org + L.len;
			END;
			L.next := F.trailer;
		ELSIF M.dH < 0 THEN (* got smaller *)
			DEC(Y, L.h); org := org + L.len; L := L.next;
			IF L # F.trailer THEN
				LOOP
					IF Y <= -M.H + F.bottom THEN EXIT END; (* ! *)
					IF L.eot OR (L.next = F.trailer) THEN EXIT END; (* added 24.3.94 *)
					L := L.next; DEC(Y, L.h); org := org + L.len
				END;
				L.next := F.trailer
			END
		END;
	END;
	
	(* screen update, can optimize updates, see comment in GadgetsChanges.Text *)
	IF (F.X # M.X) OR (F.Y # M.Y) OR (F.W # M.W) OR (F.H # M.H) THEN (* first adjust *)
		F.X := M.X; F.Y := M.Y; F.W := M.W; F.H := M.H; 
		O.F := F; O.M := NIL; O.x := 0; O.y := 0; O.res := -1; O.dlink := NIL; F.handle(F, O)
	END;
	IF M.mode = Display.display THEN
		y := M.Y - M.dY; h := M.H - M.dH;  (*calculate previous coordinates *)
		
		IF (M.Y + M.H = y + h) & (h > 0) & (M.dW = 0) & (M.dX = 0) THEN
			(* left top most corner is stable, had height, no width change *)

			IF M.dH > 0 THEN (* got bigger *)
				D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.area;
				D.u := 0; D.v := -F.H + 1; D.w := F.W; D.h := ABS(M.dH) + 2;
				D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
				F.handle(F, D)
			ELSIF M.dH < 0 THEN (* got smaller *)
				D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen; D.id := Display.area;
				D.u := 0; D.v := -F.H + 1; D.w := F.W; D.h := 3;
				D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
				F.handle(F, D)
			END;
			Gadgets.MakeMask(F, M.x + F.X, M.y + F.Y, M.dlink, mask);
			RestoreSlider(F, mask, M.x + F.X, M.y + F.Y, F.W, F.H);
			IF (Gadgets.selected IN F.state) THEN
				Display3.FillPattern(mask, Display3.white, Display3.selectpat,
					M.x + F.X, M.y + F.Y, M.x + F.X, M.y + F.Y, F.left, F.H, Display.paint);
			END
		ELSIF (F.H > 0) & (F.W > 0) THEN
			D.x := M.x; D.y := M.y; D.F := F; D.device := Display.screen;D.id := Display.full;
			D.dlink := M.dlink; D.res := -1; Objects.Stamp(D);
			F.handle(F, D)
		END
	END
END ModifyFrame;

PROCEDURE FindObj(F: Frame; VAR M: Objects.FindMsg);
VAR f: Texts.Finder; o: Objects.Object; name: ARRAY 64 OF CHAR;
BEGIN
	Gadgets.framehandle(F, M);
	IF M.obj = NIL THEN
	
		(* look at direct children *)
		Texts.OpenFinder(f, F.text, 0);
		Texts.FindObj(f, o);
		WHILE ~f.eot & (M.obj = NIL) DO
			IF o # NIL THEN
				Gadgets.GetObjName(o, name);
				IF name = M.name THEN M.obj := o END;
			END;
			Texts.FindObj(f, o)
		END;
		
		(* broadcast to all children *)
		IF M.obj = NIL THEN
			Texts.OpenFinder(f, F.text, 0);
			Texts.FindObj(f, o);
			WHILE ~f.eot & (M.obj = NIL) DO
				IF o # NIL THEN o.handle(o, M) END;
				Texts.FindObj(f, o)
			END
		END
	END
END FindObj;

PROCEDURE Consume (F: Frame; x, y: INTEGER; VAR M: Display.ConsumeMsg);
VAR pos: LONGINT; f: Display.Frame; loc: Loc; MM: Display.ModifyMsg; C: Display.ControlMsg;
BEGIN
	pos := -1;
	IF (M.id = Display.integrate) & F.car & (M.obj IS Display.Frame) & (mayconsume IN F.state0) & ~(locked IN F.state0) THEN
		pos := F.carpos.pos
	ELSIF (M.id = Display.drop) & (M.F = F) & (mayconsume IN F.state0) & ~(locked IN F.state0) THEN
		F.do.LocateChar(F, x, y, x + M.u, y + F.H - 1 + M.v, loc);
		pos := loc.pos;
		C.id := Display.remove; C.F := M.obj(Display.Frame); Display.Broadcast(C) (* <<< remove the whole list *)
	ELSE ToBoxes(F, x, y, M)
	END;
	IF pos >= 0 THEN
		f := M.obj(Display.Frame);
		WHILE f # NIL DO
			IF Gadgets.Recursive(F, f) THEN
				Texts.WriteString(Wmsg,"Not allowed, will cause recursive structures"); Texts.WriteLn(Wmsg);
				Texts.Append(Oberon.Log, Wmsg.buf); M.res := 0; RETURN
			END;
			(* ps - 5.5.97 *)
			MM.id := Display.move; MM.mode := Display.state; MM.F := f; MM.res := -1;
			MM.x := 0; MM.y := 0; MM.dlink := NIL; Objects.Stamp(MM);
			MM.X := 0; MM.Y := 0; MM.W := f.W; MM.H := f.H;
			MM.dX := MM.X - f.X; MM.dY := MM.Y - f.Y; MM.dW := 0; MM.dH := 0;
			f.handle(f, MM); f.X := 0; f.Y := 0;
			InsertObj(F, pos, f); INC(pos);
			IF f.slink # NIL THEN f := f.slink(Display.Frame) ELSE f := NIL END
		END; 
		M.res := 0; Oberon.Defocus; SetCaret(F, pos)
	END
END Consume;

PROCEDURE UpdateText (F: Frame; x, y, w, h: INTEGER; VAR M: Texts.UpdateMsg);
VAR beg, end: LONGINT; id, fw, fh: INTEGER; sel: BOOLEAN;
BEGIN
	ToBoxes(F, x, y, M);
	IF M.text = F.text THEN
		sel := F.sel;
		ConvertMsg(M, id, beg, end); (* <--- convert to old style messages *)
		RemoveCaret(F); RemoveSelection(F);
		Update(F, M.dlink, id, beg, end, x, y, w, h, M.stamp, F.desc);
		DrawChanges(F, M.dlink, id, beg, end, x, y, w, h, M.stamp, F.desc);
		IF ~(sizeadjust IN F.state0) THEN
			IF scrollhint & (autoscroll IN F.state0) THEN ScrollUp(F, F.text.len) END
		ELSIF ~Gadgets.IsLocked(F, M.dlink) THEN
			OptimalSize(F, fw, fh);
			IF (fw = F.W) & (fh = F.H) THEN
			ELSE AdjustSize(F, fw, fh);
			END
		END;
		(* ps - 16.8.96 *)
		IF sel & (id = change) THEN SetSelection(F, F.selbeg.pos, F.selend.pos) END
	END
END UpdateText;

PROCEDURE TGSelect (F: Frame; x, y: INTEGER; VAR M: SelectMsg);
VAR R: Display3.Mask;
BEGIN
	IF M.F = F THEN
		Gadgets.MakeMask(F, x, y, M.dlink, R); FlipSelection(F, R, x, y, M.beg, M.end)
	ELSE
		ToBoxes(F, x, y, M)
	END
END TGSelect;

PROCEDURE DSelect (F: Frame; x, y: INTEGER; VAR M: Display.SelectMsg);
VAR obj: Objects.Object;
BEGIN
	IF M.id = Display.get THEN
		IF F.frametime > M.time THEN
			GetSelectedFrames(F.text, obj);
			IF obj # NIL THEN M.time := F.frametime; M.obj := obj; M.sel := F
			ELSE Gadgets.framehandle(F, M); ToBoxes(F, x, y, M)
			END
		ELSE Gadgets.framehandle(F, M); ToBoxes(F, x, y, M)
		END
	ELSIF (M.id = Display.set) & (M.F = F) THEN
		RemoveCaret(F); RemoveSelection(F);
		Gadgets.framehandle(F, M)
	ELSE
		Gadgets.framehandle(F, M); ToBoxes(F, x, y, M);
	END
END DSelect;

PROCEDURE OSelect (F: Frame; x, y: INTEGER; VAR M: Oberon.SelectMsg);
BEGIN
	IF (M.F = NIL) OR (M.F = F) THEN
		IF (M.id = Oberon.get) & F.sel THEN
			GetSelection(F, M.text, M.beg, M.end, M.time);
			IF (M.time = F.time) & (F.text = M.text) THEN M.sel := F END;
			ToBoxes(F, x, y, M)
		ELSIF (M.sel = F) & (M.text = F.text) THEN
			IF M.id = Oberon.set THEN locate(F, M.end); SetSelection(F, M.beg, M.end)
			ELSIF M.id = Oberon.reset THEN RemoveSelection(F)
			ELSE ToBoxes(F, x, y, M)
			END
		ELSE ToBoxes(F, x, y, M)
		END
	ELSE ToBoxes(F, x, y, M)
	END
END OSelect;

PROCEDURE DControl (F: Frame; x, y: INTEGER; VAR M: Display.ControlMsg);
BEGIN
	IF M.id = Display.remove THEN
		IF M.stamp # F.stamp THEN F.stamp := M.stamp; RemoveChild(F, x, y, M) END;
		ToBoxes(F, x, y, M)
	ELSE
		ToBoxes(F, x, y, M);
		IF M.id = Display.restore THEN F.trailer := NIL; F.car := FALSE; F.sel := FALSE END
	END
END DControl;

PROCEDURE OControl (F: Frame; x, y: INTEGER; VAR M: Oberon.ControlMsg);
BEGIN
	IF M.id = Oberon.defocus THEN
		ToBoxes(F, x, y, M);
		IF F.car & (caption IN F.state0) THEN INCL(F.state, Gadgets.transparent); NewMask(F)
		ELSE RemoveCaret(F)
		END
	ELSIF M.id = Oberon.neutralize THEN
		ToBoxes(F, x, y, M);
		IF F.car & (caption IN F.state0) THEN INCL(F.state, Gadgets.transparent); NewMask(F)
		ELSE RemoveCaret(F); RemoveSelection(F); UnselectSelectedFrames(F.text)
		END
	END
END OControl;

PROCEDURE FrameHandler*(F: Objects.Object; VAR M: Objects.ObjMsg);
VAR x, y, w, h, u, v: INTEGER; R: Display3.Mask; 
BEGIN
	WITH F: Frame DO
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN HALT(99)
				ELSE Gadgets.framehandle(F, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.store THEN StoreFrame(F, M)
				ELSIF M.id = Objects.load THEN LoadFrame(F, M)
				END
			END
		ELSIF M IS Objects.CopyMsg THEN HALT(99);
		ELSIF M IS Objects.BindMsg THEN
			Gadgets.framehandle(F, M);
			IF F.text.handle = NIL THEN F.text.handle := Texts.Handle END;
			F.text.handle(F.text, M)
		ELSIF M IS Objects.FindMsg THEN FindObj(F, M(Objects.FindMsg))
		ELSIF M IS Objects.LinkMsg THEN FrameLink(F, M(Objects.LinkMsg))
		ELSIF M IS Display.FrameMsg THEN
			WITH M: Display.FrameMsg DO
				x := M.x + F.X; y := M.y + F.Y; w := F.W; h := F.H; (* calculate display coordinates of this instance *)
				u := M.x; v := M.y; (* store volatile info *)
				IF M IS CaretMsg THEN
					IF M.F = F THEN Gadgets.MakeMask(F, x, y, M.dlink, R); FlipCaret(F, R, x, y, w, h, M(CaretMsg).loc)
					ELSE ToBoxes(F, x, y, M)
					END
				ELSIF M IS SelectMsg THEN TGSelect(F, x, y, M(SelectMsg))
				ELSIF M IS ScrollMsg THEN
					WITH M: ScrollMsg DO
						IF M.F = F THEN
							ScrollUpdate(F, M.pos, M.stamp, F.desc);
							DrawScrollChanges(F, M.pos, M.stamp, M.dlink, x, y, w, h, F.desc)
						ELSE ToBoxes(F, x, y, M)
						END
					END
				ELSIF M IS Display.DisplayMsg THEN
					WITH M: Display.DisplayMsg  DO
						IF M.device = Display.screen THEN
							IF (M.F = NIL) OR ((M.id = Display.full) & (M.F = F)) THEN
								F.trailer := NIL; F.car := FALSE; F.sel := FALSE; (* ejz *)
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								RestoreFrame(F, R, x, y, w, h, M.dlink);
							ELSIF (M.id = Display.area) & (M.F = F) THEN
								Gadgets.MakeMask(F, x, y, M.dlink, R);
								Display3.AdjustMask(R, x + M.u, y + h - 1 + M.v, M.w, M.h);
								RestoreFrameArea(F, R, x, y, w, h, M.u, M.v, M.w, M.h, M.dlink);
							ELSE
								ChildRestore(F, M, x, y, M.dlink);
								ToBoxes(F, x, y, M);
								IF F.sel THEN ChildRestoreSelection(F, M, x, y, M.dlink) END
							END
						ELSIF M.device = Display.printer THEN Print(F, x, y, M)
						ELSE ToBoxes(F, x, y, M)
						END
					END
				ELSIF M IS Display.LocateMsg THEN LocateMsg(F, M(Display.LocateMsg))
				ELSIF M IS Texts.UpdateMsg THEN UpdateText(F, x, y, w, h, M(Texts.UpdateMsg))
				ELSIF M IS Oberon.InputMsg THEN
					WITH M: Oberon.InputMsg DO
						IF (M.id = Oberon.track) & ~(Gadgets.selected IN F.state) &
							(~Effects.InBorder(M.X, M.Y, x, y, w, h) OR InScrollBar(F, M.X, M.Y, x, y)) THEN
							Gadgets.MakeMask(F, x, y, M.dlink, R);
							Edit(F, R, x, y, w, h, M)
						ELSIF M.id = Oberon.consume THEN
							IF F.car THEN Write(F, x, y, M.ch, M.fnt, M.col, M.voff); M.res := 0 ELSE ToBoxes(F, x, y, M) END
						ELSE Gadgets.framehandle(F, M)
						END
					END
				ELSIF M IS Oberon.ControlMsg THEN OControl(F, x, y, M(Oberon.ControlMsg))
				ELSIF M IS Display.ModifyMsg THEN
					WITH M: Display.ModifyMsg DO
						IF (M.F = F) THEN ModifyFrame(F, M);
						ELSE AdjustChild(F, x, y, M);
						END
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg DO
						IF M.obj = F THEN Gadgets.framehandle(F, M)
						ELSE UpdateChild(F, x, y, M)
						END
					END
				ELSIF M IS Display.ControlMsg THEN DControl(F, x, y, M(Display.ControlMsg))
				ELSIF M IS Display.SelectMsg THEN DSelect(F, x, y, M(Display.SelectMsg))
				ELSIF M IS Oberon.ConsumeMsg THEN
					WITH M: Oberon.ConsumeMsg DO
						IF F.car & ~(locked IN F.state0) THEN CopyOver(F, M.text, M.beg, M.end); M.res := 0
						ELSE ToBoxes(F, x, y, M)
						END
					END
				ELSIF M IS Display3.OverlapMsg THEN
					Gadgets.framehandle(F, M);
				ELSIF M IS Display3.UpdateMaskMsg THEN
					WITH M: Display3.UpdateMaskMsg DO
						IF  M.F = F THEN (* panel has to construct its own mask *)
							NEW(F.mask); Display3.Open(F.mask); Display3.Add(F.mask, 0, -F.H+1, F.W, F.H);
							F.mask.x := 0; F.mask.y := 0; M.res := 0;
						ELSE ToBoxes(F, x, y, M)
						END;
					END
				ELSIF M IS Gadgets.UpdateMsg THEN
					WITH M: Gadgets.UpdateMsg DO
						ChildUpdate(F, M, x, y, M.dlink);
						ToBoxes(F, x, y, M);
					END
				ELSIF M IS Display.ConsumeMsg THEN Consume(F, x, y, M(Display.ConsumeMsg))
				ELSIF M IS Oberon.RecallMsg THEN
					IF F.car THEN Recall(F) (* added 24.3.94 *)
					ELSE ToBoxes(F, x, y, M)
					END
				ELSIF M IS Oberon.CaretMsg THEN (* added 24.3.94 *)
					WITH M: Oberon.CaretMsg DO
						IF (M.F = NIL) OR (M.F = F) THEN
							IF M.id = Oberon.get THEN
								IF F.car THEN M.car := F; M.pos := F.carpos.pos; M.text := F.text; M.res := 0
								ELSE ToBoxes(F, x, y, M)
								END
							ELSIF (M.car = F) & (M.text = F.text) THEN
								IF M.id = Oberon.set THEN Oberon.Defocus; Locate(F, M.pos); SetCaret(F, M.pos)
								ELSIF M.id = Oberon.reset THEN RemoveCaret(F)
								END
							ELSE ToBoxes(F, x, y, M)
							END
						ELSE ToBoxes(F, x, y, M)
						END
					END
				ELSIF M IS Oberon.SelectMsg THEN OSelect(F, x, y, M(Oberon.SelectMsg))	(* added 24.3.94 *)
				ELSE
					ToBoxes(F, x, y, M);
					IF M.res < 0 THEN Gadgets.framehandle(F, M) END
				END;
				M.x := u; M.y := v; (* restore volatile info *)
			END
		ELSE
			Gadgets.framehandle(F, M)
		END
	END
END FrameHandler;

PROCEDURE InitFrame*(F: Frame; T: Texts.Text);
BEGIN
	F.W := 100; F.H := 100; F.border := 2; F.left := 20; F.top := 4; F.right := 2; F.bottom := 4;
	IF Display.Depth(0) = 1 THEN F.col := 0 ELSE F.col := Display3.textbackC END;
	F.invertC := SHORT(Max(0, 15 - F.col));
	IF (F.invertC = 0) OR (Display.TrueColor(0)) THEN F.invertC := Display3.invertC END;
	F.handle := FrameHandler; F.state0 := {mayselect .. autoindent};
	F.text := T; F.org := 0
END InitFrame;

PROCEDURE InitPagePosition;
BEGIN
	(* old positioning
	PrintertopY := Printer.Height DIV 10 * 9; PrinterbotY := Printer.Height DIV 20; PrinterleftX := Printer.Width DIV 10;
	HeaderY := Printer.Height DIV 20 * 19; PagenoX := Printer.Width DIV 10 *  9;
	PrintertopY := PrintertopY - Printer.FrameY; PrinterbotY := PrinterbotY - Printer.FrameY
	*)
	(* new positioning *)
	PrintertopY := Printer.FrameY + Printer.FrameH; PrinterbotY := Printer.FrameY; PrinterleftX := Printer.FrameX;
	HeaderY := PrintertopY-P(Fonts.Default.height);
	IF (0 IN printOpts) OR (1 IN printOpts) THEN
		PrintertopY := HeaderY - P(2*Fonts.Default.height)
	ELSE
		PrintertopY := HeaderY - P(Fonts.Default.height)
	END;
	PagenoX := SHORT(LONG(PrinterleftX) + LONG(Printer.FrameW) * 19 DIV 20)
END InitPagePosition;

BEGIN Texts.OpenWriter(W); Texts.OpenWriter(Wmsg);
	printOpts := {0, 1};
	InitPagePosition; NEW(dummyFrame)
END TextGadgets0.

