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

MODULE ListDags;	(** portable *)		(* ps,   *)
(** Dag is a model designed for the access mechanism defined in module Riders. *)

IMPORT Files, Objects, Gadgets, Strings, ListRiders;

CONST
	VersionNo = 1;
	NoKey = MIN(LONGINT);
	
	(* states *)
	unique = 0;

TYPE
	Ref = POINTER TO RefDesc;
	Node = POINTER TO NodeDesc;

	RefDesc = RECORD
		prev, next: Ref;
		node: Node;	(* is acs for tails *)
		key, pos: LONGINT
	END;

	NodeDesc = RECORD
		dsc: Ref;	(* list of children *)
		stamp, state: LONGINT;	(* nodes state and stamp *)
		nr: LONGINT;	(* used to load, store and copy nodes *)
		s: ARRAY 32 OF CHAR;
	END;

	Dag* = POINTER TO DagDesc;
	DagDesc* = RECORD (Gadgets.ObjDesc)
		key: LONGINT;	(* next free unique-key *)
		tail: Ref;
		state0: SET
	END;

	Rider* = POINTER TO RiderDesc;
	RiderDesc* = RECORD( ListRiders.RiderDesc)
		ref: Ref	(* reference to current node *)
	END;
	
VAR
	method: ListRiders.Method;

(* Key generator *)
PROCEDURE GetKey (obj: Dag): LONGINT;
VAR key: LONGINT;
BEGIN
	key := obj.key; INC(obj.key);
	RETURN key
END GetKey;

(*========== Node handling ==========*)
PROCEDURE SetNode (R: Rider; ref: Ref);
VAR d: ListRiders.String;
BEGIN
	R.ref := ref;
	R.dsc := (ref.key # NoKey) & (ref.node.dsc # NIL);
	R.eol := ref.key = NoKey;
	IF R.eol THEN R.d := NIL
	ELSE
		IF (R.d = NIL) OR ~(R.d IS ListRiders.String) THEN NEW(d); R.d := d ELSE d := R.d(ListRiders.String) END;
		COPY(ref.node.s, d.s)
	END
END SetNode;

PROCEDURE MakeNode (d: ListRiders.Data): Node;
VAR new: Node;
BEGIN
	NEW(new);
	new.stamp := MIN(LONGINT); new.state := 0; new.dsc := NIL;
	IF d = NIL THEN new.s := ""
	ELSE
		IF d IS ListRiders.String THEN COPY(d(ListRiders.String).s, new.s)
		ELSIF d IS ListRiders.Int THEN Strings.IntToStr(d(ListRiders.Int).i, new.s)
		ELSIF d IS ListRiders.Bool THEN Strings.BoolToStr(d(ListRiders.Bool).b, new.s)
		ELSIF d IS ListRiders.Char THEN new.s[0] := d(ListRiders.Char).c; new.s[1] := 0X
		END
	END;
	RETURN new
END MakeNode;

PROCEDURE MakeTail (asc: Node): Ref;
VAR new: Ref;
BEGIN
	NEW(new); new.key := NoKey;
	new.prev := new; new.next := new;
	new.pos := -1; new.node := NIL; new.node := asc;
	RETURN new
END MakeTail;

PROCEDURE IsUnique (n: Ref; val: ARRAY OF CHAR; acceptSelf: BOOLEAN): BOOLEAN;
VAR cur: Ref;
BEGIN
	cur := n;
	REPEAT cur := cur.next UNTIL (cur = n) OR (cur.key # NoKey) & (cur.node.s = val);
	RETURN (cur = n) & (acceptSelf OR (cur.node.s # val))
END IsUnique;

(*========== Rider handling ==========*)
(* Get the current item's key *)
PROCEDURE *Key (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).ref.key
END Key;

(* Position rider R on the item having the given key *)
PROCEDURE *Seek (R: ListRiders.Rider; key: LONGINT);

	PROCEDURE Traverse (tail: Ref; key: LONGINT): Ref;
	VAR n, found: Ref;
	BEGIN
		n := tail.next;
		WHILE (n # tail) & (n.key # key) DO
			IF n.node.dsc # NIL THEN
				found := Traverse(n.node.dsc, key);
				IF found.key = key THEN RETURN found END
			END;
			n := n.next 
		END;
		RETURN n
	END Traverse;

BEGIN
	WITH R: Rider DO SetNode(R, Traverse(R.base(Dag).tail, key)) END
END Seek;

(* Get current position of the rider *)
PROCEDURE *Pos (R: ListRiders.Rider): LONGINT;
BEGIN RETURN R(Rider).ref.pos
END Pos;

(* Position rider R on the item having the given pos *)
PROCEDURE *Set (R: ListRiders.Rider; pos: LONGINT);
VAR n: Ref;
BEGIN
	WITH R: Rider DO
		n := R.ref;
		IF n.pos < pos THEN REPEAT n := n.next UNTIL (n.pos = pos) OR (n.key = NoKey)
		ELSIF n.pos > pos THEN REPEAT n := n.prev UNTIL (n.pos = pos) OR (n.key = NoKey)
		END;
		SetNode(R, n)
	END
END Set;

(* Insert data at the current position of R *)
PROCEDURE *Write (R: ListRiders.Rider; d: ListRiders.Data);
VAR new, ref: Ref; node: Node;
BEGIN
	IF R # NIL THEN
		WITH R: Rider DO
			ref := R.ref; node := MakeNode(d);
			IF ~(unique IN R.base(Dag).state0) OR IsUnique(ref, node.s, FALSE) THEN
				NEW(new);
				new.key := GetKey(R.base(Dag)); new.pos := ref.prev.pos; new.node := node;
				new.next := ref; new.prev := ref.prev; ref.prev.next := new; ref.prev := new;
				REPEAT INC(new.pos); new := new.next UNTIL new.key = NoKey
			END
		END
	END
END Write;

(* Link the item at the position of linkR to the current position of R *)
PROCEDURE *WriteLink (R, linkR: ListRiders.Rider);
VAR node: Node; ref, new: Ref; base: Dag;

	PROCEDURE IsCycle (n: Ref; node: Node; stamp: LONGINT): BOOLEAN;
	BEGIN
		IF n # NIL THEN
			n := n.next;
			WHILE (n.key # NoKey) & (n.node # node) DO
				n.node.stamp := stamp;
				IF (n.node.dsc # NIL) & (n.node.stamp # stamp) THEN
					IF IsCycle(n.node.dsc, node, stamp) THEN RETURN TRUE END
				END;
				n := n.next
			END;
			RETURN n.key # NoKey
		ELSE
			RETURN FALSE
		END
	END IsCycle;

BEGIN
	IF (linkR # NIL) & (~linkR.eol) & ((R = NIL) OR (R.base = linkR.base)) THEN
		base := linkR.base(Dag);
		IF (R = NIL) OR R.eol THEN
			ref := base.tail
		ELSE
			node := R(Rider).ref.node;
			IF node.dsc = NIL THEN node.dsc := MakeTail(node) END;
			ref := node.dsc
		END;

		node := linkR(Rider).ref.node;
		REPEAT ref := ref.next UNTIL (ref.key = NoKey) OR (ref.node = node);
		IF (ref.key = NoKey) & (ref.node # node) & ~IsCycle(node.dsc, ref.node, ListRiders.Stamp()) THEN	(* no cycle *)
			IF ~(unique IN base(Dag).state0) OR IsUnique(ref, node.s, FALSE) THEN
				NEW(new);
				new.key := GetKey(base); new.node := node; new.pos := ref.prev.pos;
				new.next := ref; new.prev := ref.prev; new.prev.next := new; ref.prev := new;
				REPEAT INC(new.pos); new := new.next UNTIL new.key = NoKey
			END
		END
	END
END WriteLink;

(* Delete link from R to linkR *)
PROCEDURE *DeleteLink (R, linkR: ListRiders.Rider);
VAR ref, n: Ref; base: Dag;
BEGIN
	IF (linkR # NIL) & (~linkR.eol) & ((R = NIL) OR (R.base = linkR.base)) THEN
		WITH linkR: Rider DO
			base := linkR.base(Dag);
			IF R = NIL THEN ref := base.tail
			ELSIF R.eol THEN ref := R(Rider).ref
			ELSE ref := R(Rider).ref.node.dsc
			END;
			REPEAT ref := ref.next UNTIL (ref.key = NoKey) OR (ref.node = linkR.ref.node);
			IF ref.key # NoKey THEN
				n := ref.next;
				ref.prev.next := ref.next; ref.next.prev := ref.prev;
				ref.next := NIL; ref.prev := NIL;
				IF (n.next = n) & (n.node # NIL) THEN n.node.dsc := NIL; n := base.tail	(* empty sub-list *)
				ELSE WHILE n.key # NoKey DO DEC(n.pos); n:= n.next END	(* renumber pos *)
				END;
				SetNode(linkR, n)
			END
		END
	END
END DeleteLink;

(* Get stamp value of the node at the current position of R *)
PROCEDURE *GetStamp (R: ListRiders.Rider): LONGINT;
BEGIN
	WITH R: Rider DO
		IF R.ref.node # NIL THEN RETURN R.ref.node.stamp
		ELSE RETURN MIN(LONGINT)
		END
	END
END GetStamp;

(* Set stamp value of the item at the current position of R *)
PROCEDURE *SetStamp (R: ListRiders.Rider; stamp: LONGINT);
BEGIN
	WITH R: Rider DO
		IF R.ref.node # NIL THEN R.ref.node.stamp := stamp END
	END
END SetStamp;

(* Get the state of the current item *)
PROCEDURE *State (R: ListRiders.Rider): LONGINT;
BEGIN
	WITH R: Rider DO
		IF R.ref.node # NIL THEN RETURN R.ref.node.state
		ELSE RETURN 0
		END
	END
END State;

(* Set the state of the current item *)
PROCEDURE *SetState (R: ListRiders.Rider; s: LONGINT);
BEGIN
	WITH R: Rider DO
		IF R.ref.node # NIL THEN R.ref.node.state := s END
	END
END SetState;

PROCEDURE *Desc (R, old: ListRiders.Rider): ListRiders.Rider;
VAR new: Rider; ref: Ref; node: Node;
BEGIN
	WITH R: Rider DO
		IF (old = NIL) OR ~(old IS Rider) THEN NEW(new) ELSE new := old(Rider) END;
		new.do := R.do; new.base := R.base;
		ref := R.ref;
		IF ~R.eol & (ref.node # NIL) THEN
			node := ref.node; ref := node.dsc;
			IF ref = NIL THEN
				ref := MakeTail(node);
				node.dsc := ref
			END;
			ref := ref.next
		END;
		SetNode(new, ref)
	END;
	RETURN new
END Desc;
	
PROCEDURE ConnectRider(R: Rider; base: Dag);
BEGIN
	R.do := method; R.base := base;
	SetNode(R, base.tail.next)
END ConnectRider;

(* =================== dag model =================== *)
PROCEDURE Unify (tail: Ref);
VAR n: Ref; nr: LONGINT;
BEGIN
	n := tail.prev;
	WHILE n # tail DO
		IF ~IsUnique(n, n.node.s, TRUE) THEN n.prev.next := n.next; n.next.prev := n.prev
		ELSIF n.node.dsc # NIL THEN Unify(n.node.dsc)
		END;
		n := n.prev
	END;
	(* renumber *)
	n := n.next; nr := 0;
	WHILE n # tail DO n.pos := nr; INC(nr); n := n.next END
END Unify;

PROCEDURE FindNode (nodes: Ref; nr: LONGINT): Node;
VAR n: Ref;
BEGIN
	n := nodes;
	REPEAT n := n.next; DEC(nr) UNTIL nr < 0;
	RETURN n.node
END FindNode;

PROCEDURE InsertNode (nodes: Ref; node: Node);
VAR n: Ref;
BEGIN
	NEW(n); n.node := node;
	n.next := nodes; n.prev := nodes.prev; nodes.prev := n; n.prev.next := n
END InsertNode;

PROCEDURE CopyDag* (VAR M: Objects.CopyMsg; from, to: Dag);
VAR lastNr, stamp: LONGINT; nodes: Ref;

	PROCEDURE CopyLevel (n, n0: Ref);
	VAR tail: Ref; node, node0: Node;
	BEGIN
		n := n.next; tail := n0;
		WHILE n.key # NoKey DO
			NEW(n0.next); n0.next.prev := n0; n0 := n0.next;
			n0.key := n.key; n0.pos := n.pos;
			node := n.node;
			IF node.stamp # stamp THEN
				node.stamp := stamp; node.nr := lastNr; INC(lastNr);
				NEW(node0);
				node0.state := node.state; node0.stamp := MIN(LONGINT);
				COPY(node.s, node0.s);
				InsertNode(nodes, node0);
				IF node.dsc # NIL THEN
					node0.dsc := MakeTail(node0); CopyLevel(node.dsc, node0.dsc)
				END
			ELSE
				node0 := FindNode(nodes, node.nr)
			END;
			n0.node := node0;
			n := n.next
		END;
		tail.prev := n0; n0.next := tail
	END CopyLevel;

BEGIN
	to.handle := from.handle; to.key := from.key;
	lastNr := 0; stamp := ListRiders.Stamp(); nodes := MakeTail(NIL);
	to.tail := MakeTail(NIL); CopyLevel(from.tail, to.tail);
	Gadgets.CopyObject(M, from, to)
END CopyDag;

PROCEDURE WriteDag (obj: Dag; VAR M: Objects.FileMsg);
VAR lastNr, stamp: LONGINT;

	PROCEDURE WriteLevel (n: Ref);
	VAR node: Node;
	BEGIN
		n := n.next;
		WHILE n.key # NoKey DO
			Files.WriteLInt(M.R, n.key); Files.WriteLInt(M.R, n.pos);
			node := n.node;
			IF node.stamp # stamp THEN	(* node not visited yet *)
				node.stamp := stamp; node.nr := lastNr; INC(lastNr);
				Files.WriteLInt(M.R, node.nr);
				Files.WriteLInt(M.R, node.state); Files.WriteString(M.R, node.s);
				IF node.dsc # NIL THEN Files.Write(M.R, 0FFX); WriteLevel(node.dsc)
				ELSE Files.Write(M.R, 0X)
				END
			ELSE
				Files.WriteLInt(M.R, node.nr)
			END;
			n := n.next
		END;
		Files.WriteLInt(M.R, NoKey)
	END WriteLevel;

BEGIN
	Files.WriteNum(M.R, VersionNo);
	Files.WriteSet(M.R, obj.state0);
	lastNr := 0; stamp := ListRiders.Stamp();
	WriteLevel(obj.tail);
	Gadgets.objecthandle(obj, M)
END WriteDag;

PROCEDURE ReadDag (obj: Dag; VAR M: Objects.FileMsg);
VAR ver, lastNr: LONGINT; nodes: Ref;

	PROCEDURE ReadLevel (tail: Ref);
	VAR n: Ref; node: Node; key, nr: LONGINT; ch: CHAR;
	BEGIN
		n := tail;
		Files.ReadLInt(M.R, key);
		WHILE key # NoKey DO
			NEW(n.next); n.next.prev := n; n := n.next;
			n.key := key; Files.ReadLInt(M.R, n.pos);
			Files.ReadLInt(M.R, nr);
			IF nr > lastNr THEN
				INC(lastNr);
				NEW(node); InsertNode(nodes, node);
				node.stamp := MIN(LONGINT);
				Files.ReadLInt(M.R, node.state);
				Files.ReadString(M.R, node.s);
				Files.Read(M.R, ch);
				IF ch = 0FFX THEN node.dsc := MakeTail(node); ReadLevel(node.dsc)
				ELSE node.dsc := NIL
				END
			ELSE
				node := FindNode(nodes, nr)
			END;
			n.node := node;
			Files.ReadLInt(M.R, key)
		END;
		tail.prev := n; n.next := tail
	END ReadLevel;

BEGIN
	Files.ReadNum(M.R, ver);
	IF ver >= 1 THEN
		Files.ReadSet(M.R, obj.state0);
		obj.tail := MakeTail(NIL);
		lastNr := -1; nodes := MakeTail(NIL);
		ReadLevel(obj.tail)
	END;
	Gadgets.objecthandle(obj, M)
END ReadDag;

PROCEDURE DagAttr (obj: Dag; VAR M: Objects.AttrMsg);
BEGIN
	IF M.id = Objects.get THEN
		IF M.name = "Gen" THEN COPY("ListDags.New", M.s); M.class := Objects.String; M.res := 0
		ELSIF M.name = "Unique" THEN M.class := Objects.Bool; M.b := unique IN obj.state0; M.res := 0
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.set THEN
		IF M.name = "Unique" THEN
			IF M.class = Objects.Bool THEN
				IF M.b & ~(unique IN obj.state0) THEN INCL(obj.state0, unique); Unify(obj.tail)
				ELSIF ~M.b THEN EXCL(obj.state0, unique)
				END;
				M.res := 0
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	ELSIF M.id = Objects.enum THEN
		M.Enum("Unique"); Gadgets.objecthandle(obj, M)
	ELSE Gadgets.objecthandle(obj, M)
	END
END DagAttr;

(** Standard handler for Dag models *)
PROCEDURE DagHandler* (obj: Objects.Object; VAR M: Objects.ObjMsg);
VAR R: Rider; obj0: Dag;
BEGIN
	WITH obj: Dag DO
		IF M IS Objects.AttrMsg THEN
			DagAttr(obj, M(Objects.AttrMsg))
		ELSIF M IS Objects.CopyMsg THEN
			WITH M: Objects.CopyMsg DO
				IF M.stamp = obj.stamp THEN M.obj := obj.dlink
				ELSE NEW(obj0); obj.stamp := M.stamp; obj.dlink := obj0; CopyDag(M, obj, obj0); M.obj := obj0
				END
			END
		ELSIF M IS ListRiders.ConnectMsg THEN
			NEW(R); ConnectRider(R, obj); M(ListRiders.ConnectMsg).R := R
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN ReadDag(obj, M)
				ELSIF M.id = Objects.store THEN WriteDag(obj, M)
				END
			END
		ELSE Gadgets.objecthandle(obj, M)
		END
	END
END DagHandler;

(** Initialize a dag model *)
PROCEDURE InitDag* (obj: Dag);
BEGIN
	obj.handle := DagHandler;
	obj.key := NoKey + 1; obj.tail := MakeTail(NIL); obj.state0 := {}
END InitDag;

(** Generator for a dag *)
PROCEDURE New*;
VAR obj: Dag;
BEGIN NEW(obj); InitDag(obj); Objects.NewObj := obj
END New;

BEGIN
	NEW(method);
	method.Key := Key; method.Seek := Seek; method.Pos := Pos; method.Set := Set;
	method.State := State; method.SetState := SetState;
	method.Write := Write; method.WriteLink := WriteLink; method.DeleteLink := DeleteLink;
	method.GetStamp := GetStamp; method.SetStamp := SetStamp; method.Desc := Desc
END ListDags.
