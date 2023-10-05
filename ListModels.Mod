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

MODULE ListModels;	(** portable *)		(* ps,   *)
(** List and Tree are models designed for the access mechanism defined in module Riders. *)

IMPORT Files, Objects, Gadgets, Strings, ListRiders;

CONST
	VersionNo = 1;
	NoKey = MIN(LONGINT);
	
	(* states *)
	sorted = 0; unique = 1; linear = 2;

TYPE
	Node = POINTER TO NodeDesc;
	NodeDesc = RECORD
		prev, next, dsc: Node;	(* prev, next: doubly linked list / dsc: node's desc. or parent for tails *)
		key, stamp, state, pos: LONGINT;
		d: ListRiders.Data;
		s: ARRAY 64 OF CHAR	(* Data value *)
	END;

	List* = POINTER TO ListDesc;
	ListDesc* = RECORD (Gadgets.ObjDesc)
		tail: Node;	(* tail of list (sentinel) *)
		key: LONGINT;	(* next free unique-key *)
		state0: SET	(* diff. settings *)
	END;

	Rider* = POINTER TO RiderDesc;
	RiderDesc* = RECORD( ListRiders.RiderDesc)
		node: Node	(* current node *)
	END;
	
VAR
	method: ListRiders.Method;

(* Key generator *)
PROCEDURE GetKey (obj: List): LONGINT;
VAR key: LONGINT;
BEGIN
	key := obj.key; INC(obj.key);
	RETURN key
END GetKey;

(*========== Node handling ==========*)
(* Allocate new node *)
PROCEDURE NewNode (val: ListRiders.Data; key: LONGINT): Node;
VAR n: Node;
BEGIN
	NEW(n);
	IF val = NIL THEN n.s := ""
	ELSE
		IF val IS ListRiders.String THEN COPY(val(ListRiders.String).s, n.s)
		ELSIF val IS ListRiders.Int THEN Strings.IntToStr(val(ListRiders.Int).i, n.s)
		ELSIF val IS ListRiders.Bool THEN Strings.BoolToStr(val(ListRiders.Bool).b, n.s)
		ELSIF val IS ListRiders.Char THEN n.s[0] := val(ListRiders.Char).c; n.s[1] := 0X
		END
	END;

	n.d := val; n.key := key; n.stamp := NoKey;
	n.next := n; n.prev := n; n.dsc := NIL;
	RETURN n
END NewNode;

(* Set n as the current item of R *)
PROCEDURE SetNode (R: Rider; n: Node);
BEGIN
	R.node := n; R.d := n.d; R.dsc := (n.dsc # NIL) & (n.key # NoKey);
	R.eol := n.key = NoKey
END SetNode;

PROCEDURE DuplicateNode (list: List; n: Node): Node;
VAR new, ndsc: Node;
BEGIN
	new := NewNode(n.d, GetKey(list));
	IF n.dsc # NIL THEN
		ndsc := NewNode(NIL, NoKey); ndsc.pos := -1; ndsc.dsc := new;
		new.dsc := ndsc;
		n := n.dsc.next;
		WHILE n.key # NoKey DO
			ndsc.next := DuplicateNode(list, n);
			ndsc.next.prev := ndsc; ndsc := ndsc.next;
			ndsc.pos := n.pos;
			n := n.next
		END;
		ndsc.next := new.dsc; new.dsc.prev := ndsc
	END;
	RETURN new
END DuplicateNode;

PROCEDURE IsUnique (n: Node; val: ARRAY OF CHAR; acceptSelf: BOOLEAN): BOOLEAN;
VAR cur: Node;
BEGIN
	cur := n;
	REPEAT cur := cur.next UNTIL (cur = n) OR (cur.s = val) & (cur.key # NoKey);
	RETURN (cur = n) & (acceptSelf OR (n.s # val))
END IsUnique;

(*========== Rider handling ==========*)
(* Get the current item's key *)
PROCEDURE *Key (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).node.key
END Key;

(* Position rider R on the item having the given key *)
PROCEDURE *Seek (R: ListRiders.Rider; key: LONGINT);

	PROCEDURE Traverse (tail: Node; key: LONGINT): Node;
	VAR n, found: Node;
	BEGIN
		n := tail.next;
		WHILE (n # tail) & (n.key # key) DO
			IF n.dsc # NIL THEN
				found := Traverse(n.dsc, key);
				IF found.key = key THEN RETURN found END
			END;
			n := n.next 
		END;
		RETURN n
	END Traverse;

BEGIN
	WITH R: Rider DO SetNode(R, Traverse(R.base(List).tail, key)) END
END Seek;

(* Get current position of the rider *)
PROCEDURE *Pos (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).node.pos
END Pos;

(* Position rider R on the item having the given pos *)
PROCEDURE *Set (R: ListRiders.Rider; pos: LONGINT);
VAR n: Node;
BEGIN
	WITH R: Rider DO
		n := R.node;
		IF n.pos < pos THEN REPEAT n := n.next UNTIL (n.pos = pos) OR (n.key = NoKey)
		ELSIF n.pos > pos THEN REPEAT n := n.prev UNTIL (n.pos = pos) OR (n.key = NoKey)
		END;
		SetNode(R, n)
	END
END Set;

(* Insert data at the current position of R *)
PROCEDURE *Write (R: ListRiders.Rider; d: ListRiders.Data);
VAR n, n0: Node; base: List; sort: BOOLEAN;
BEGIN
	IF R # NIL THEN
		WITH R: Rider DO
			base := R.base(List);
			n0 := NewNode(d, GetKey(base)); 			
			sort := sorted IN base.state0;
			IF sort THEN
				IF linear IN base.state0 THEN n := R.base(List).tail
				ELSE	(* Tree *)
					n := R.node;
					WHILE (n.key # NoKey) & (n.s > n0.s) DO n := n.prev END;
				END;
				REPEAT n := n.next UNTIL (n.key = NoKey) OR (n.s > n0.s)
			ELSE n := R.node
			END;

			IF ~(unique IN base.state0) OR IsUnique(n, n0.s, FALSE) THEN
				n0.pos := n.prev.pos;
				n0.next := n; n0.prev := n.prev; n.prev.next := n0; n.prev := n0;
				REPEAT INC(n0.pos); n0 := n0.next UNTIL n0.key = NoKey
			END
		END
	END
END Write;

(* Link the item at the position of linkR to the current position of R *)
PROCEDURE *WriteLink (R, linkR: ListRiders.Rider);
VAR n, n0: Node; base: List;
BEGIN
	IF (linkR # NIL) & (~linkR.eol) & ((R = NIL) OR (R.base = linkR.base)) THEN
		base := linkR(Rider).base(List);
		IF R = NIL THEN	(* insert at top level *)
			n := base.tail
		ELSE
			WITH R: Rider DO
				IF linear IN base.state0 THEN	(* linear list *)
					IF sorted IN base.state0 THEN n := base.tail ELSE n := R.node END
				ELSE	(* tree -> insert in dsc-list *)
					n := R.node.dsc;
					IF n = NIL THEN
						n := NewNode(NIL, NoKey); n.pos := -1; n.dsc := R.node;
						R.node.dsc := n
					END
				END
			END
		END;
		
		IF ~(unique IN base.state0) OR IsUnique(n, linkR(Rider).node.s, FALSE) THEN
			n0 := DuplicateNode(base, linkR(Rider).node);
			IF sorted IN base.state0 THEN REPEAT n := n.next UNTIL (n.key = NoKey) OR (n.s > n0.s) END;
			n0.pos := n.prev.pos;
			n0.next := n; n0.prev := n.prev; n.prev.next := n0; n.prev := n0;
			REPEAT INC(n0.pos); n0 := n0.next UNTIL n0.key = NoKey
		END
	END
END WriteLink;

(* Delete link from R to linkR *)
PROCEDURE *DeleteLink (R, linkR: ListRiders.Rider);
VAR d, n: Node;
BEGIN
	WITH linkR: Rider DO
		d := linkR.node;
		d.prev.next := d.next; d.next.prev := d.prev; n:= d.next; d.next := d; d.prev := d;
		IF (n.next = n) & (n.dsc # NIL) THEN n := n.dsc; n.dsc := NIL (* empty sub-list *)
		ELSE d := n; WHILE d.key # NoKey DO DEC(d.pos); d:= d.next END
		END;
		SetNode(linkR, n)
	END
END DeleteLink;

(* Get stamp value of the node at the current position of R *)
PROCEDURE *GetStamp (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).node.stamp
END GetStamp;

(* Set stamp value of the item at the current position of R *)
PROCEDURE *SetStamp (R: ListRiders.Rider; stamp: LONGINT);
BEGIN R(Rider).node.stamp := stamp
END SetStamp;

(* Get the state of the current item *)
PROCEDURE *State (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).node.state
END State;

(* Set the state of the current item *)
PROCEDURE *SetState (R: ListRiders.Rider; s: LONGINT);
BEGIN R(Rider).node.state := s
END SetState;

PROCEDURE *Desc (R, old: ListRiders.Rider): ListRiders.Rider;
VAR new: Rider; base: List; node: Node;
BEGIN
	WITH R: Rider DO
		IF (old = NIL) OR ~(old IS Rider) THEN NEW(new) ELSE new := old(Rider) END;
		new.do := R.do; new.base := R.base;
		base := R.base(List);
		IF linear IN base.state0 THEN node := base.tail
		ELSE	(* Tree *)
			IF ~R.eol THEN
				node := R.node.dsc;
				IF node = NIL THEN
					node := NewNode(NIL, NoKey); node.pos := -1; node.dsc := R.node;
					R.node.dsc := node
				END;
				node := node.next
			ELSE node := R.node
			END
		END;
		SetNode(new, node)
	END;
	RETURN new
END Desc;
	
PROCEDURE ConnectRider(R: Rider; base: List);
BEGIN
	R.do := method; R.base := base;
	SetNode(R, base.tail.next)
END ConnectRider;

(* =================== list model =================== *)
PROCEDURE Sort (VAR tail: Node);	(* sorts entries in one level *)
VAR n, m, next, ntail: Node; pos: LONGINT;
BEGIN
	IF tail.next # tail THEN
		ntail := NewNode(NIL, NoKey); ntail.pos := -1;
		n := tail.next;
		WHILE n # tail DO
			next := n.next; n.prev.next := next; next.prev := n.prev;
			m := ntail; REPEAT m := m.next UNTIL (m = ntail) OR (m.s > n.s);
			n.next := m; n.prev := m.prev; m.prev.next := n; m.prev := n;
			IF n.dsc # NIL THEN Sort(n.dsc); n.dsc.dsc := n END;
			n := next
		END;
		tail := ntail;
		n := tail.next; pos := 0;
		WHILE n # tail DO n.pos := pos; INC(pos); n := n.next END
	END
END Sort;

PROCEDURE Unify (tail: Node);	(* removes entries with same data in one level *)
VAR n: Node; nr: LONGINT;
BEGIN
	n := tail.prev;
	WHILE n # tail DO
		IF ~IsUnique(n, n.s, TRUE) THEN n.prev.next := n.next; n.next.prev := n.prev
		ELSIF n.dsc # NIL THEN Unify(n.dsc)
		END;
		n := n.prev
	END;
	(* renumber *)
	n := n.next; nr := 0;
	WHILE n # tail DO n.pos := nr; INC(nr); n := n.next END
END Unify;

PROCEDURE CopyList* (VAR M: Objects.CopyMsg; from, to: List);

	PROCEDURE Copy (tail: Node): Node;
	VAR n, new, ntail: Node;
	BEGIN
		ntail := NewNode(NIL, NoKey); ntail.pos := -1;
		n := tail.next;
		WHILE n # tail DO
			NEW(new); new^ := n^;	(* duplicate data *)
			new.next := ntail; new.prev := ntail.prev; ntail.prev.next := new; ntail.prev := new;
			IF n.dsc # NIL THEN new.dsc := Copy(n.dsc); new.dsc.dsc := new END;
			n := n.next
		END;
		RETURN ntail
	END Copy;

BEGIN
	to.handle := from.handle; to.key := from.key;
	to.state0 := from.state0;
	to.tail := Copy(from.tail);
	Gadgets.CopyObject(M, from, to)
END CopyList;

PROCEDURE WriteList (obj: List; VAR M: Objects.FileMsg);

	PROCEDURE WriteNodes (n: Node);
	BEGIN
		n := n.next;
		WHILE n.key # NoKey DO
			Files.WriteLInt(M.R, n.key); Files.WriteString(M.R, n.s); Files.WriteLInt(M.R, n.state);
			IF n.dsc # NIL THEN Files.Write(M.R, 0FFX); WriteNodes(n.dsc)
			ELSE Files.Write(M.R, 0X)
			END;
			n := n.next
		END;
		Files.WriteLInt(M.R, NoKey)
	END WriteNodes;

BEGIN
	Files.WriteNum(M.R, VersionNo);
	Files.WriteSet(M.R, obj.state0);
	Files.WriteLInt(M.R, obj.key);
	WriteNodes(obj.tail);
	Gadgets.objecthandle(obj, M)
END WriteList;

PROCEDURE ReadList (obj: List; VAR M: Objects.FileMsg);
VAR ver: LONGINT;

	PROCEDURE ReadNodes (tail: Node);
	VAR n: Node; key: LONGINT; str: ListRiders.String; ch: CHAR;
	BEGIN
		n := tail;
		Files.ReadLInt(M.R, key);
		WHILE key # NoKey DO
			NEW(n.next); n.next.prev := n; n := n.next;
			n.key := key; n.pos := n.prev.pos + 1;
			Files.ReadString(M.R, n.s); NEW(str); COPY(n.s, str.s); n.d := str;
			Files.ReadLInt(M.R, n.state);
			Files.Read(M.R, ch);
			IF ch = 0FFX THEN
				n.dsc := NewNode(NIL, NoKey); n.dsc.pos := -1; n.dsc.dsc := n;
				ReadNodes(n.dsc)
			END;
			Files.ReadLInt(M.R, key)
		END;
		n.next := tail; tail.prev := n
	END ReadNodes;

BEGIN
	Files.ReadNum(M.R, ver);
	IF ver >= 1 THEN
		Files.ReadSet(M.R, obj.state0);
		Files.ReadLInt(M.R, obj.key);
		ReadNodes(obj.tail)
	END;
	Gadgets.objecthandle(obj, M)
END ReadList;

PROCEDURE ListAttr (obj: List; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN COPY("ListModels.NewList", M.s); M.class := Objects.String; M.res := 0
		ELSIF M.name = "Sorted" THEN M.class := Objects.Bool; M.b := sorted IN obj.state0; M.res := 0
		ELSIF M.name = "Unique" THEN M.class := Objects.Bool; M.b := unique IN obj.state0; M.res := 0
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Sorted" THEN
			IF M.class = Objects.Bool THEN
				IF M.b & ~(sorted IN obj.state0) THEN INCL(obj.state0, sorted); Sort(obj.tail)
				ELSIF ~M.b THEN EXCL(obj.state0, sorted)
				END;
				M.res := 0
			END
		ELSIF M.name = "Unique" THEN
			IF M.class = Objects.Bool THEN
				IF M.b & ~ (unique IN obj.state0) THEN INCL(obj.state0, unique); Unify(obj.tail)
				ELSIF ~M.b THEN EXCL(obj.state0, unique)
				END;
				M.res := 0
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Sorted"); M.Enum("Unique"); Gadgets.objecthandle(obj, M)
	ELSE Gadgets.objecthandle(obj, M)
	END
END ListAttr;

(** Standard handler for list models *)
PROCEDURE ListHandler* (obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR R: Rider; obj0: List;
BEGIN
	WITH obj: List DO
		IF M IS Objects.AttrMsg THEN
			ListAttr(obj, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj0); obj.stamp := M.stamp; obj.dlink := obj0; CopyList(M, obj, obj0); M.obj := obj0
				END
			END
		ELSIF M IS ListRiders.ConnectMsg THEN
			NEW(R); ConnectRider(R, obj); M(ListRiders.ConnectMsg).R := R
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN ReadList(obj, M)
				ELSIF M.id = Objects.store THEN WriteList(obj, M)
				END
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	END
END ListHandler;

(** Initialize a list model *)
PROCEDURE InitList* (obj: List; linearList: BOOLEAN);
VAR tail: Node;
BEGIN
	tail := NewNode(NIL, NoKey); tail.pos := -1;
	obj.handle := ListHandler; obj.key := NoKey+1; obj.tail := tail;
	obj.state0 := {}; IF linearList THEN INCL(obj.state0, linear) END
END InitList;

(** Generator for a linear list *)
PROCEDURE NewList*;
VAR obj: List;
BEGIN NEW(obj); InitList(obj, TRUE); Objects.NewObj := obj
END NewList;

(** Generator for a tree *)
PROCEDURE NewTree*;
VAR obj: List;
BEGIN NEW(obj); InitList(obj, FALSE); Objects.NewObj := obj
END NewTree;

BEGIN
	NEW(method);
	method.Key := Key; method.Seek := Seek; method.Pos := Pos; method.Set := Set;
	method.State := State; method.SetState := SetState;
	method.Write := Write; method.WriteLink := WriteLink; method.DeleteLink := DeleteLink;
	method.GetStamp := GetStamp; method.SetStamp := SetStamp; method.Desc := Desc
END ListModels.
