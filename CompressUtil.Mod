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

MODULE CompressUtil;	(* pjm - based on Compress by ejz *)

IMPORT SYSTEM;

	CONST
		IndexBitCount = 12;
		LengthBitCount = 4;
		WindowSize = 4096;
		RawLookAheadSize = 16;
		BreakEven = 1;
		LookAheadSize = RawLookAheadSize + BreakEven;
		TreeRoot = WindowSize;
		EndOfStream = 0;
		Unused = 0;
		
	TYPE
		InputProc* = PROCEDURE (VAR ch: CHAR;  VAR eof: BOOLEAN);
		OutputProc* = PROCEDURE (ch: CHAR);

		Node = RECORD
			parent, smallerChild, largerChild: INTEGER
		END;
		
	VAR
		Read: InputProc;
		Write: OutputProc;
		CurBitNr: LONGINT;
		CurByte: LONGINT;
		Window: POINTER TO ARRAY WindowSize+RawLookAheadSize+1 OF CHAR;
		Tree: POINTER TO ARRAY WindowSize+1 OF Node;
		help: INTEGER;
		Err: BOOLEAN;
		i, currentPosition, matchLength, matchPosition: INTEGER;
		
	PROCEDURE FlushBits();
	BEGIN
		IF CurBitNr # 7 THEN Write(CHR(CurByte)) END;
	END FlushBits;

	PROCEDURE InputBit(): LONGINT;
		VAR h: LONGINT;  ch: CHAR;  eof: BOOLEAN;
	BEGIN
		IF CurBitNr = 7 THEN
			Read(ch, eof);
			IF eof THEN Err := TRUE; RETURN 1 END;
			CurByte := ORD(ch)
		END;
		h := ASH(CurByte, -CurBitNr) MOD 2;
		DEC(CurBitNr);
		IF CurBitNr < 0 THEN CurBitNr := 7 END;
		RETURN h
	END InputBit;

	PROCEDURE InputBits(count: LONGINT): LONGINT;
		VAR i, h: LONGINT;  eof: BOOLEAN;  ch: CHAR;
	BEGIN
		h := 0;
		i := count-1;
		WHILE i >= 0 DO
			IF CurBitNr = 7 THEN
				Read(ch, eof);
				IF eof THEN Err := TRUE; RETURN 1 END;
				CurByte := ORD(ch)
			END;
			IF ASH(CurByte, -CurBitNr) MOD 2 = 1 THEN
				h := h+ASH(1, i)
			END;
			DEC(CurBitNr);
			IF CurBitNr < 0 THEN CurBitNr := 7 END;
			DEC(i)
		END;
		RETURN h
	END InputBits;

	PROCEDURE OutputBit(bit: LONGINT);
	BEGIN
		IF bit = 1 THEN
			CurByte := CurByte+ASH(1, CurBitNr)
		END;
		DEC(CurBitNr);
		IF CurBitNr < 0 THEN
			Write(CHR(CurByte));
			CurBitNr := 7;
			CurByte := 0
		END
	END OutputBit;

	PROCEDURE OutputBits(bits, count: LONGINT);
		VAR i, h: LONGINT;
	BEGIN
		h := bits;
		i := count-1;
		WHILE i >= 0 DO
			IF ASH(h, -i) MOD 2 = 1 THEN
				CurByte := CurByte+ASH(1, CurBitNr)
			END;
			DEC(CurBitNr);
			IF CurBitNr < 0 THEN
				Write(CHR(CurByte));
				CurBitNr := 7;
				CurByte := 0
			END;
			DEC(i)
		END
	END OutputBits;

	PROCEDURE Init();
		VAR i: LONGINT;
	BEGIN
		IF Window = NIL THEN NEW(Window);  NEW(Tree) END;
		CurBitNr := 7; CurByte := 0;
		i := 0;
		WHILE i < WindowSize DO
			Tree[i].parent := Unused;
			Tree[i].smallerChild := Unused;
			Tree[i].largerChild := Unused;
			Window[i] := CHR(0);
			INC(i)
		END;
		Tree[i].parent := Unused;
		Tree[i].smallerChild := Unused;
		Tree[i].largerChild := Unused;
		WHILE i < WindowSize+RawLookAheadSize+1 DO
			Window[i] := CHR(0);
			INC(i)
		END
	END Init;

	PROCEDURE InitTree(r: INTEGER);
	BEGIN
		Tree[TreeRoot].largerChild := r;
		Tree[r].parent := TreeRoot;
		Tree[r].largerChild := Unused;
		Tree[r].smallerChild := Unused
	END InitTree;

	PROCEDURE ContractNode(oldNode, newNode: INTEGER);
	BEGIN
		help := Tree[oldNode].parent;
		Tree[newNode].parent := help;
		help := Tree[oldNode].parent;
		IF Tree[help].largerChild = oldNode THEN
			Tree[help].largerChild := newNode
		ELSE
			Tree[help].smallerChild := newNode
		END;
		Tree[oldNode].parent := Unused
	END ContractNode;

	PROCEDURE ReplaceNode(oldNode, newNode: INTEGER);
		VAR parent: INTEGER;
	BEGIN
		parent := Tree[oldNode].parent;
		IF Tree[parent].smallerChild = oldNode THEN
			Tree[parent].smallerChild := newNode
		ELSE
			Tree[parent].largerChild := newNode
		END;
		Tree[newNode] := Tree[oldNode];
		help := Tree[newNode].smallerChild;
		Tree[help].parent := newNode;
		help := Tree[newNode].largerChild;
		Tree[help].parent := newNode;
		Tree[oldNode].parent := Unused
	END ReplaceNode;

	PROCEDURE FindNextNode(node: INTEGER): INTEGER;
		VAR next: INTEGER;
	BEGIN
		next := Tree[node].smallerChild;
		WHILE Tree[next].largerChild # Unused DO
			next := Tree[next].largerChild
		END;
		RETURN next
	END FindNextNode;
	
	PROCEDURE DeleteString(p: INTEGER);
		VAR replacement: INTEGER;
	BEGIN
		IF Tree[p].parent = Unused THEN
			RETURN
		END;
		IF Tree[p].largerChild = Unused THEN
			ContractNode(p, Tree[p].smallerChild)
		ELSIF Tree[p].smallerChild = Unused THEN
			ContractNode(p, Tree[p].largerChild)
		ELSE
			replacement := FindNextNode(p);
			DeleteString(replacement);
			ReplaceNode(p, replacement)
		END
	END DeleteString;

	PROCEDURE AddString(newNode: INTEGER; VAR matchPosition: INTEGER): INTEGER;
		VAR i, testNode, delta, matchLength, child: INTEGER;
	BEGIN
		IF newNode = EndOfStream THEN
			RETURN 0
		END;
		testNode := Tree[TreeRoot].largerChild;
		matchLength := 0;
		LOOP
			i := 0;
			delta := 0;
			WHILE (i < LookAheadSize) & (delta = 0) DO
				delta := ORD(Window[newNode+i]) - ORD(Window[testNode+i]);
				INC(i)
			END;
			IF delta # 0 THEN DEC(i) END;
			IF i >= matchLength THEN
				matchLength := i;
				matchPosition := testNode;
				IF matchLength >= LookAheadSize THEN
					ReplaceNode(testNode, newNode);
					RETURN matchLength
				END;
			END;
			IF delta >= 0 THEN
				child := Tree[testNode].largerChild
			ELSE
				child := Tree[testNode].smallerChild
			END;
			IF child = Unused THEN
				IF delta >= 0 THEN
					Tree[testNode].largerChild := newNode
				ELSE
					Tree[testNode].smallerChild := newNode
				END;
				Tree[newNode].parent := testNode;
				Tree[newNode].largerChild := Unused;
				Tree[newNode].smallerChild := Unused;
				RETURN matchLength
			END;
			testNode := child
		END
	END AddString;

(** Compress - Compress a stream of bytes. *)

	PROCEDURE Compress*(Input: InputProc;  Output: OutputProc);
		VAR
			i, lookAheadBytes, currentPosition, replaceCount, matchLength, matchPosition: INTEGER;
			ch: CHAR;  eof: BOOLEAN;
	BEGIN
		Read := Input; Write := Output; eof := FALSE;
		Init();
		currentPosition := 1;
		i := 0;
		WHILE (i < LookAheadSize) & ~eof DO
			Read(ch, eof);
			Window[currentPosition+i] := ch;
			IF currentPosition+i < RawLookAheadSize+1 THEN
				Window[currentPosition+i+WindowSize-1] := ch
			END;
			INC(i)
		END;
		IF eof THEN DEC(i) END;
		lookAheadBytes := i;
		InitTree(currentPosition);
		matchLength := 0;
		matchPosition := 0;
		WHILE lookAheadBytes > 0 DO
			IF matchLength > lookAheadBytes THEN
				matchLength := lookAheadBytes
			END;
			IF matchLength <= BreakEven THEN
				replaceCount := 1;
				OutputBit(1);
				OutputBits(ORD(Window[currentPosition]), 8)
			ELSE
				OutputBit(0);
				OutputBits(matchPosition, IndexBitCount);
				OutputBits(matchLength-(BreakEven+1), LengthBitCount);
				replaceCount := matchLength
			END;
			i := 0;
			WHILE i < replaceCount DO
				DeleteString((currentPosition+LookAheadSize) MOD (WindowSize-1));
				Read(ch, eof);
				IF eof THEN
					DEC(lookAheadBytes)
				ELSE
					Window[currentPosition+LookAheadSize] := ch;
					Window[(currentPosition+LookAheadSize) MOD (WindowSize-1)] := ch
				END;
				currentPosition := (currentPosition+1) MOD (WindowSize-1);
				IF lookAheadBytes # 0 THEN
					matchLength := AddString(currentPosition, matchPosition)
				END;
				INC(i)
			END
		END;
		OutputBit(0);
		OutputBits(EndOfStream, IndexBitCount);
		FlushBits()
	END Compress;

(*
	PROCEDURE Expand*(Input: InputProc;  Output: OutputProc;  VAR ok: BOOLEAN);
		VAR
			i, currentPosition, matchLength, matchPosition: INTEGER;
			ch: CHAR;
	BEGIN
		Read := Input; Write := Output;
		Err := FALSE;
		Init;
		currentPosition := 1;
		LOOP
			IF InputBit() # 0 THEN
				ch := CHR(InputBits(8));
				IF Err THEN EXIT END;
				Write(ch);
				Window[currentPosition] := ch;
				IF currentPosition < RawLookAheadSize+1 THEN
					Window[currentPosition+WindowSize-1] := ch
				END;
				currentPosition := (currentPosition+1) MOD (WindowSize-1)
			ELSE
				matchPosition := SHORT(InputBits(IndexBitCount));
				IF matchPosition = EndOfStream THEN EXIT END;
				matchLength := SHORT(InputBits(LengthBitCount));
				IF Err THEN EXIT END;
				INC(matchLength, BreakEven);
				i := 0;
				WHILE i <= matchLength DO
					ch := Window[matchPosition+i];
					Write(ch);
					Window[currentPosition] := ch;
					IF currentPosition < RawLookAheadSize+1 THEN
						Window[currentPosition+WindowSize-1] := ch;
					END;
					currentPosition := (currentPosition+1) MOD (WindowSize-1);
					INC(i)
				END
			END
		END;
		ok := ~Err
	END Expand;
*)

(** InitExpand - Initialize expanding of a stream. *)

	PROCEDURE InitExpand*(Input: InputProc);
	BEGIN
		Read := Input; Write := NIL;
		Err := FALSE;
		Init;
		currentPosition := 1; i := -1
	END InitExpand;

(** ExpandBlock - Expand a block of maximum len bytes of the stream.  outLen is actual number of bytes
expanded, and is -1 on error.  eof is set when attempting to read past the end-of-file the first time. *)

	PROCEDURE ExpandBlock*(VAR buf: ARRAY OF SYSTEM.BYTE;  len: LONGINT;  VAR outLen: LONGINT;  VAR eof: BOOLEAN);
		VAR
			ch: CHAR; count: LONGINT;
	BEGIN
		count := 0; eof := FALSE;
		LOOP
			IF i < 0 THEN
				IF InputBit() # 0 THEN
					ch := CHR(InputBits(8));
					IF Err THEN len := -1; EXIT END;
					buf[count] := ch; INC(count);
					Window[currentPosition] := ch;
					IF currentPosition < RawLookAheadSize+1 THEN
						Window[currentPosition+WindowSize-1] := ch
					END;
					currentPosition := (currentPosition+1) MOD (WindowSize-1)
				ELSE
					matchPosition := SHORT(InputBits(IndexBitCount));
					IF matchPosition = EndOfStream THEN eof := TRUE; len := count; EXIT END;
					matchLength := SHORT(InputBits(LengthBitCount));
					IF Err THEN len := -1; EXIT END;
					INC(matchLength, BreakEven);
					i := 0
				END
			ELSE	(* i >= 0 *)
				IF i <= matchLength THEN
					ch := Window[matchPosition+i];
					buf[count] := ch; INC(count);
					Window[currentPosition] := ch;
					IF currentPosition < RawLookAheadSize+1 THEN
						Window[currentPosition+WindowSize-1] := ch
					END;
					currentPosition := (currentPosition+1) MOD (WindowSize-1);
					INC(i)
				ELSE
					i := -1
				END
			END;
			IF count = len THEN EXIT END
		END;
		outLen := len
	END ExpandBlock;
	
BEGIN
	Window := NIL
END CompressUtil.
