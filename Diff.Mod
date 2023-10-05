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

MODULE Diff;	(** portable *)	(** PS   **)

(* to do
	?handle hash-structure in a tree?
*)

	(** options
		s: produce statistic output
		S: produce more stat. output
		n: do not open a document
	*)

	IMPORT BIT, Objects, Display, Fonts, Texts, Attributes, Oberon, TextGadgets, DiffGadgets, Out;

	CONST
		stat = 0; smallStat = 1; noOutput = 2;

		(* special characters *)
		CR = 0DX; TAB = 09X;
	
		(* max. # lines to look ahead *)
		Treshold = 10;

	TYPE
		Line = POINTER TO LineDesc;
		HashEntry = POINTER TO HashEntryDesc;

		LineDesc = RECORD
			pos: LONGINT;
			hash: HashEntry;
			next, list, corr: Line;
			nr, absNr: INTEGER
		END;

		HashEntryDesc = RECORD
			next: HashEntry;
			hash: LONGINT;
			list: Line
		END;

		Text = POINTER TO TextDesc;
		TextDesc = RECORD
			text: Texts.Text;
			root: HashEntry;
			line: Line;
			name: ARRAY 64 OF CHAR;
			total, inserted: INTEGER
		END;

	VAR
		R: Texts.Reader;
		W: Texts.Writer;
		opts: SET;
		nrSyncs: INTEGER;
	

(* *************** STATISTIC OUTPUT *************** *)

PROCEDURE HashStat (T: Text);
VAR cur: HashEntry; curL: Line; same, nrVals, perVal, corr: INTEGER;
BEGIN
	Texts.WriteString(W, "Statistic for text '"); Texts.WriteString(W, T.name); Texts.Write(W, "'"); Texts.WriteLn(W);
	cur := T.root.next;
	same := 0; nrVals := 0;
	WHILE cur # NIL DO INC(nrVals);
		perVal := 0; curL := cur.list; WHILE curL # NIL DO INC(perVal); curL := curL.list END;
		IF perVal > 1 THEN INC(same);
			IF ~(smallStat IN opts) THEN
				Texts.Write(W, TAB); Texts.Write(W, TAB);
				Texts.WriteString(W, "hash:"); Texts.WriteInt(W, cur.hash, 8);
				Texts.WriteString(W, " | {"); Texts.WriteInt(W, cur.list.nr, 5); curL := cur.list.list;
				WHILE curL # NIL DO Texts.Write(W, ","); Texts.WriteInt(W, curL.nr, 5); curL := curL.list END;
				Texts.WriteString(W, "} | # lines:"); Texts.WriteInt(W, perVal, 5); Texts.WriteLn(W)
			END
		END;
		cur := cur.next
	END;
	
	Texts.Write(W, TAB); Texts.WriteString(W, "# lines:"); Texts.WriteInt(W, T.total, 6); Texts.WriteLn(W);
	Texts.Write(W, TAB); Texts.WriteString(W, "# hashed lines:"); Texts.WriteInt(W, T.inserted, 6); Texts.WriteLn(W);
	Texts.Write(W, TAB); Texts.WriteString(W, "# different values:"); Texts.WriteInt(W, nrVals, 6); Texts.WriteString(W, " (");
	Texts.WriteReal(W, nrVals/T.inserted*100, 0); Texts.WriteString(W, "% )"); Texts.WriteLn(W);
	Texts.Write(W, TAB); Texts.WriteString(W, "# values with more than one line:"); Texts.WriteInt(W, same, 6);
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END HashStat;

PROCEDURE DiffStat (T1, T2: Text);
VAR curL: Line; corr: INTEGER;
BEGIN
	Texts.WriteString(W, "Comparing text '"); Texts.WriteString(W, T1.name);
	Texts.WriteString(W, "' to '"); Texts.WriteString(W, T2.name); Texts.Write(W, "'"); Texts.WriteLn(W);
	curL := T1.line; corr := 0;
	WHILE curL # NIL DO IF curL.corr = NIL THEN INC(corr) END; curL := curL.next END;
	Texts.Write(W, TAB); Texts.WriteString(W, "# correlated lines:"); Texts.WriteInt(W, T1.inserted-corr, 6);
	curL := T2.line; corr := 0;
	WHILE curL # NIL DO IF curL.corr = NIL THEN INC(corr) END; curL := curL.next END;
	Texts.WriteString(W, " |"); Texts.WriteInt(W, T2.inserted-corr, 6); Texts.WriteLn(W);
	Texts.Write(W, TAB); Texts.WriteString(W, "# syncs:"); Texts.WriteInt(W, nrSyncs, 5); Texts.WriteLn(W);
	Texts.Append(Oberon.Log, W.buf)
END DiffStat;


(* *************** HASHING *************** *)

PROCEDURE HashLine (L: Line; VAR hash: LONGINT; VAR done: BOOLEAN);
VAR obj: Objects.Object; ch: CHAR;

	PROCEDURE HashObj (obj: Objects.Object; VAR hash: LONGINT);
	VAR gen: ARRAY 64 OF CHAR; i: INTEGER;
	BEGIN
		Attributes.GetString(obj, "Gen", gen);
		IF gen[0] # 0X THEN
			i := 0;
			WHILE gen[i] # 0X DO hash := BIT.LROT(hash, 3) + ORD(gen[i]); INC(i) END
		END
	END HashObj;

BEGIN
	done := FALSE; hash := 0; L.pos := Texts.Pos(R);
	REPEAT Texts.Read(R, ch) UNTIL (ch > " ") OR (ch = CR) OR R.eot OR ~(R.lib IS Fonts.Font);
	WHILE (ch # CR) & ~R.eot DO
		IF R.lib # NIL THEN
			done := TRUE;
			IF R.lib IS Fonts.Font THEN hash := BIT.LROT(hash, 3) + ORD(ch)
			ELSE R.lib.GetObj(R.lib, ORD(ch), obj); HashObj(obj, hash)
			END
		ELSE
			Texts.WriteString(W, "lib is NIL"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END;
		REPEAT Texts.Read(R, ch) UNTIL (ch > " ") OR (ch = CR) OR R.eot OR ~(R.lib IS Fonts.Font)
	END
END HashLine;

PROCEDURE Insert (root: HashEntry; line: Line; hash: LONGINT);
VAR cur, new: HashEntry; curL: Line;
BEGIN cur := root; line.list := NIL;
	WHILE (cur.next # NIL) & (cur.next.hash <= hash) DO cur := cur.next END;
	IF cur.hash # hash THEN NEW(new);
		new.next := cur.next; cur.next := new; new.hash := hash;
		new.list := line; line.hash := new
	ELSE curL:= cur.list;
		WHILE curL.list # NIL DO curL := curL.list END;
		curL.list := line; line.hash := cur
	END
END Insert;

PROCEDURE HashText (T: Text);
VAR old, line: Line; hash: LONGINT; inserted, total: INTEGER; done: BOOLEAN;
BEGIN
	NEW(T.root); T.root.next := NIL; NEW(line);
	T.line := line; old := NIL;
	total := 0; inserted := 0;
	Texts.OpenReader(R, T.text, 0);
	REPEAT
		HashLine(line, hash, done); INC(total);
		IF done THEN
			INC(inserted);
			line.nr := inserted; line.absNr := total;
			Insert(T.root, line, hash);
			old := line; NEW(line); old.next := line
		END
	UNTIL R.eot;
	IF line.hash = NIL THEN
		IF old = NIL THEN T.line := NIL ELSE line := old END
	END;
	line.next := NIL; T.total := total; T.inserted := inserted
END HashText;


(* *************** COMPARE *************** *)

PROCEDURE Compare (T1, T2: Text);
VAR L1, L2: Line;
	
	PROCEDURE RemoveLine (root: HashEntry; L: Line);
	VAR cur: HashEntry;
	BEGIN
		(* remove line from hash entry *)
		L.hash.list := L.hash.list.list;
		(* remove hash entry when empty *)
		IF L.hash.list = NIL THEN
			cur := root;
			WHILE cur.next # L.hash DO cur := cur.next END;
			cur.next := cur.next.next
		END;
		L.hash := NIL
	END RemoveLine;

	PROCEDURE SkipSingleLines (rFrom, rIn: HashEntry; VAR L: Line);
	VAR curH: HashEntry; hash: LONGINT;
	BEGIN
		curH := NIL;
		LOOP
			IF (curH # NIL) OR (L = NIL) THEN EXIT END;
			
			(* find correlated line in other text *)
			curH := rFrom.next; hash := L.hash.hash;
			WHILE (curH # NIL) & (curH.hash # hash) DO curH := curH.next END;
			IF curH = NIL THEN L.corr := NIL; RemoveLine(rIn, L); L := L.next END
			(* there is no line => continue *)
		END;
		(* correlate lines, if there is one *)
		IF L # NIL THEN L.corr := curH.list END
	END SkipSingleLines;

	PROCEDURE LookAhead (L: Line; VAR nrL: INTEGER);
	VAR l: Line; 
	BEGIN
		nrL := 0; l := L.corr;
		WHILE (L # NIL) & (l # NIL) & (l.hash.hash = L.hash.hash) & (nrL <= Treshold) DO
			L := L.next; l :=l.next; INC(nrL)
		END
	END LookAhead;

	PROCEDURE SyncLines;
	VAR nrL1, nrL2: INTEGER;
	BEGIN
		LookAhead(L1, nrL1); LookAhead(L2, nrL2);
		IF nrL1 = nrL2 THEN	(* sync to shortest distance *)
			IF nrL1 = 1 THEN	(* skip both, because block is too small *)
				RemoveLine(T1.root, L1); L1.corr := NIL; L1 := L1.next;
				RemoveLine(T2.root, L2); L2.corr := NIL; L2 := L2.next;
			ELSIF L1.corr.nr - L2.nr > L2.corr.nr - L1.nr THEN	(* sync to L2 *)
				WHILE L1 # L2.corr DO L1.corr := NIL; RemoveLine(T1.root, L1); L1 := L1.next END
			ELSE	(* sync to L1 *)
				WHILE L2 # L1.corr DO L2.corr := NIL; RemoveLine(T2.root, L2); L2 := L2.next END
			END
		ELSIF nrL1 > nrL2 THEN	(* sync to larger block -> L1 *)
			WHILE L2 # L1.corr DO L2.corr := NIL; RemoveLine(T2.root, L2); L2 := L2.next END
		ELSE	(* sync to larger block -> L2 *)
			WHILE L1 # L2.corr DO L1.corr := NIL; RemoveLine(T1.root, L1); L1 := L1.next END
		END
	END SyncLines;

BEGIN
	nrSyncs:= 0;
	L1 := T1.line; L2 := T2.line;
	LOOP
		WHILE (L1 # NIL) & (L2 # NIL) & (L1.hash.hash = L2.hash.hash) DO
			L1.corr := L2; L2.corr := L1;	(* correlate lines *)
			RemoveLine(T1.root, L1); RemoveLine(T2.root, L2);
			L1 := L1.next; L2 := L2.next
		END;
		SkipSingleLines(T2.root, T1.root, L1);
		SkipSingleLines(T1.root, T2.root, L2);

		IF (L1 = NIL) OR (L2 = NIL) THEN EXIT END;

		ASSERT ((L1.corr = L2) & (L2.corr = L1) OR (L1.corr # L2) & (L2.corr # L1));
		IF (L1.corr # L2) & (L2.corr # L1) THEN INC(nrSyncs); SyncLines END
	END
END Compare;


(* *************** PREPARE TEXTS TO SHOW *************** *)

PROCEDURE PrepareTexts (d1, d2: Text);
VAR l1, l2: Line; dL, dL1, dL2: INTEGER; F: Texts.Finder;
	
	PROCEDURE InsertCR (text: Texts.Text; pos, dPos, cnt: LONGINT);
	BEGIN
		REPEAT Texts.Write(W, CR); DEC(cnt) UNTIL cnt = 0;
		Texts.Insert(text, pos+dPos, W.buf)
	END InsertCR;

	PROCEDURE ColorText (text: Texts.Text; p1, p2, dPos: LONGINT);
	BEGIN Texts.ChangeLooks(text, p1+dPos, p2+dPos, {1}, NIL, 3, 0)
	END ColorText;

	PROCEDURE GrowStyles (text: Texts.Text);
	VAR F: Texts.Finder; obj: Objects.Object;
	BEGIN
		Texts.OpenFinder(F, text, 0); Texts.FindObj(F, obj);
		WHILE obj # NIL  DO
			IF obj IS TextGadgets.Style THEN
				obj(TextGadgets.Style).width := 9000;
				obj(TextGadgets.Style).leftM := 0;
				obj(TextGadgets.Style).mode := {TextGadgets.left};
			END;
			Texts.FindObj(F, obj)
		END
	END GrowStyles; 

BEGIN
	GrowStyles(d1.text); GrowStyles(d2.text);
	Texts.ChangeLooks(d1.text, 0, d1.text.len, {1}, NIL, 15, 0);
	Texts.ChangeLooks(d2.text, 0, d2.text.len, {1}, NIL, 15, 0);
	l1 := d1.line; l2 := d2.line; dL1 := 0; dL2 := 0;
	WHILE (l1.next # NIL) & (l2.next # NIL) DO
		dL:= (l1.absNr + dL1) - (l2.absNr + dL2);
		IF (l1.corr = l2) & (l2.corr = l1) THEN
			IF dL < 0 THEN InsertCR(d1.text, l1.pos-1,dL1, -dL); INC(dL1, -dL)
			ELSIF dL > 0 THEN InsertCR(d2.text, l2.pos-1,dL2, dL); INC(dL2, dL)
			END;
			l1 := l1.next; l2:= l2.next
		ELSIF (l1.corr # NIL) & (l2.corr = NIL) THEN 
			IF dL = 0 THEN InsertCR(d1.text, l1.pos-1,dL1, 1); INC(dL1) END;
			ColorText(d2.text, l2.pos, l2.next.pos, dL2);
			l2 := l2.next
		ELSIF (l1.corr = NIL) & (l2.corr # NIL) THEN
			IF dL = 0 THEN InsertCR(d2.text, l2.pos-1,dL2, 1); INC(dL2) END;
			ColorText(d1.text, l1.pos, l1.next.pos, dL1);
			l1 := l1.next
		ELSE	(* (l1.corr = NIL) & (l2.corr = NIL) *)
			ColorText(d1.text, l1.pos, l1.next.pos, dL1);
			ColorText(d2.text, l2.pos, l2.next.pos, dL2);
			l1 := l1.next; l2 := l2.next
		END
	END;
	IF l1 # NIL THEN ColorText(d1.text, l1.pos, d1.text.len-dL1, dL1) END;	(* pjm *)
	IF l2 # NIL THEN ColorText(d2.text, l2.pos, d2.text.len-dL2, dL2) END
END PrepareTexts;

PROCEDURE ShowTexts (T1, T2: Text);
BEGIN
	PrepareTexts(T1, T2);
	DiffGadgets.OpenDoc(T1.text, T2.text, T1.name, T2.name)
END ShowTexts;


(* *************** USER INTERFACE *************** *)

PROCEDURE SetScanner (VAR S: Attributes.Scanner);
VAR beg, end, time: LONGINT; T: Texts.Text; L: Display.LocateMsg; M: Objects.LinkMsg;
BEGIN
	opts := {};
	Attributes.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Attributes.Scan(S);
	IF (S.class = Attributes.Char) & (S.c = Oberon.OptionChar) THEN
		Attributes.Scan(S);
		IF (S.class = Attributes.Name) THEN
			beg := 0;
			WHILE S.s[beg] # 0X DO
				IF S.s[beg] = "S" THEN INCL(opts, stat)
				ELSIF S.s[beg] = "s" THEN INCL(opts, smallStat); INCL(opts, stat)
				ELSIF S.s[beg] = "n" THEN INCL(opts, noOutput)
				END;
				INC(beg)
			END
		END;
		Attributes.Scan(S)
	END;
	IF S.class = Attributes.Char THEN
		IF S.c = "^" THEN
			Oberon.GetSelection(T, beg, end, time);
			IF time >= 0 THEN
				Attributes.OpenScanner(S, T, beg); Attributes.Scan(S)
			END
		END
	END
END SetScanner;

(** looks for differences in two texts: Diff.Do [%options] text1 text2 ~ *)
PROCEDURE Do*;
VAR T1, T2: Text; T: Texts.Text; S: Attributes.Scanner;
BEGIN
	SetScanner(S); T1:= NIL; T2:= NIL;
	IF S.class = Attributes.Name THEN
		NEW(T); Texts.Open(T, S.s);
		IF T.len > 0 THEN NEW(T1); T1.text := T; COPY(S.s, T1.name)
		ELSE
			Texts.WriteString(W, "could not open "); Texts.WriteString(W, S.s); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		Attributes.Scan(S)
	END;
	IF S.class = Attributes.Name THEN
		NEW(T); Texts.Open(T, S.s);
		IF T.len > 0 THEN NEW(T2); T2.text := T; COPY(S.s, T2.name)
		ELSE
			Texts.WriteString(W, "could not open "); Texts.WriteString(W, S.s); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END
	END;

	IF (T1 # NIL) & (T2 # NIL) THEN
		HashText(T1); HashText(T2);
		IF stat IN opts THEN HashStat(T1); HashStat(T2) END;
		Compare(T1, T2);
		IF stat IN opts THEN DiffStat(T1, T2) END;
		IF ~(noOutput IN opts) THEN ShowTexts(T1, T2) END
	END;
	Oberon.Collect
END Do;

(** locates a line in the marked document (line number from stat. output) *)
PROCEDURE LocateLine*;
VAR T: Texts.Text; cnt: INTEGER; ch: CHAR; newL: BOOLEAN; S: Attributes.Scanner;
		L: Display.LocateMsg; M: Objects.LinkMsg; Sel: Oberon.SelectMsg;
BEGIN
	SetScanner(S);
	IF S.class = Attributes.Int THEN T:= NIL;
		L.X := Oberon.Pointer.X; L.Y := Oberon.Pointer.Y; L.F := NIL; L.loc := NIL;
		Display.Broadcast(L);
		IF L.loc # NIL THEN
			M.id := Objects.get; M.name := "Model"; M.obj := NIL; M.res := -1; L.loc.handle(L.loc, M);
			IF M.obj IS Texts.Text THEN T:= M.obj(Texts.Text) END
		END;
		IF T # NIL THEN
			Texts.OpenReader(R, T, 0); cnt := 1; newL := TRUE; Sel.beg := 0;
			LOOP
				REPEAT Texts.Read(R, ch) UNTIL (ch > " ") OR (ch = CR) OR R.eot;
				IF (cnt = S.i) OR R.eot THEN EXIT END;
				IF (ch = CR) & ~newL THEN newL:= TRUE; INC(cnt); Sel.beg:= Texts.Pos(R)
				ELSE newL := FALSE
				END
			END;
			IF cnt = S.i THEN
				Objects.Stamp(Sel); Sel.res := -1; Sel.id := Oberon.set; 
				Sel.F:= L.loc; Sel.sel := Sel.F; Sel.text := T;
				REPEAT Texts.Read(R, ch) UNTIL ch = CR; Sel.end := Texts.Pos(R) - 1;
				Display.Broadcast(Sel)
			END
		END	
	END
END LocateLine;

(** hashes a line, starts at begin of selection *)
PROCEDURE HashThis*;
VAR beg, end, time, hash: LONGINT; T: Texts.Text; l: Line; done: BOOLEAN;
BEGIN
	Oberon.GetSelection(T, beg, end, time);
	IF time >= 0 THEN
		Texts.OpenReader(R, T, beg);
		NEW(l); HashLine(l, hash, done);
		Texts.WriteString(W, "hash value: "); Texts.WriteInt(W, hash, 0); Texts.WriteLn(W);
		Texts.Append(Oberon.Log, W.buf)
	END
END HashThis;

BEGIN
	Texts.OpenWriter(W)
END Diff.
