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

MODULE Links;	(** portable *)

(** The Links module manage a set of named references to objects for the gadgets.
*)

IMPORT
	Files, Objects;

TYPE
	Link* = POINTER TO LinkDesc;
	LinkDesc* = RECORD
		next*: Link;
		name*: ARRAY 32 OF CHAR;
		obj*: Objects.Object
	END;

PROCEDURE Atom(lib: Objects.Library; name: ARRAY OF CHAR): INTEGER;
VAR ref: INTEGER;
BEGIN
	Objects.GetKey(lib.dict, name, ref); RETURN ref
END Atom;

PROCEDURE WriteRef(VAR r: Files.Rider; lib: Objects.Library; obj: Objects.Object);
BEGIN
	IF obj = NIL THEN Files.WriteInt(r, -1)
	ELSE
		IF obj.lib # NIL THEN
			IF obj.lib # lib THEN
				IF obj.lib.name = "" THEN (* private library *)
					Files.WriteInt(r, -1);
					(* Warning: Object belonging to private library referenced in *)
				ELSE
					Files.WriteInt(r, obj.ref); Files.WriteInt(r, Atom(lib, obj.lib.name));
				END
			ELSE
				Files.WriteInt(r, obj.ref);
				Files.WriteInt(r, Atom(lib, "")); (* belongs to this library *)
			END
		ELSE Files.WriteInt(r, -1)
			(* Warning: Object without library referenced in lib.name *)
		END
	END
END WriteRef;

PROCEDURE ReadRef(VAR r: Files.Rider; lib: Objects.Library; VAR obj: Objects.Object);
VAR i, l: INTEGER; F: Objects.Library; name: ARRAY 32 OF CHAR;
BEGIN
	Files.ReadInt(r, i);
	IF i = -1 THEN obj := NIL
	ELSE
		Files.ReadInt(r, l);
		Objects.GetName(lib.dict, l, name);
		IF name[0] = 0X THEN F := lib; COPY(lib.name, name); ELSE F := Objects.ThisLibrary(name); END;
		IF F # NIL THEN
			F.GetObj(F, i, obj);
			IF obj = NIL THEN (* Warning: Object imported from does not exist (NIL pointer) *)
			END
		ELSE (* Warning: not found *)
			obj := NIL
		END
	END
END ReadRef;

(** Store links to a file. Only (ref, lib) references to links are written. *)
PROCEDURE StoreLinks*(VAR R: Files.Rider; lib: Objects.Library; list: Link);
BEGIN
	Files.Write(R, 33X); (* magic number *)
	WHILE list # NIL DO
		Files.WriteString(R, list.name); WriteRef(R, lib, list.obj);
		list := list.next
	END;
	Files.WriteString(R, "")
END StoreLinks;

(** Load links from a file. *)
PROCEDURE LoadLinks*(VAR R: Files.Rider; lib: Objects.Library; VAR list: Link);
VAR ch: CHAR; s: ARRAY 32 OF CHAR; a, a0: Link;
BEGIN list := NIL;
	Files.Read(R, ch);
	ASSERT(ch = 33X);
	Files.ReadString(R, s);
	WHILE s # "" DO
		NEW(a); COPY(s, a.name); 
		ReadRef(R, lib, a.obj);
		IF (a.obj # NIL) & (a.obj IS Objects.Dummy) THEN a.obj := NIL END;
		IF list = NIL THEN list := a ELSE a0.next := a END;
		a0 := a;
		Files.ReadString(R, s)
	END
END LoadLinks;

PROCEDURE CopyPtr(VAR M: Objects.CopyMsg; obj: Objects.Object): Objects.Object;
BEGIN
	IF obj = NIL THEN RETURN NIL
	ELSE
		IF M.id = Objects.deep THEN
			M.obj := NIL; obj.handle(obj, M); RETURN M.obj
		ELSE (* shallow *)
			RETURN obj
		END;
	END;
END CopyPtr;

(** Copy links.  Both shallow and deep copies are supported. *)
PROCEDURE CopyLinks*(VAR M: Objects.CopyMsg; in: Link; VAR out: Link);
VAR L, a, a0: Link;
BEGIN
	L := in; out := NIL;
	WHILE L # NIL DO
		NEW(a); COPY(L.name, a.name); 
		a.obj := CopyPtr(M, L.obj);
		IF out = NIL THEN out := a ELSE a0.next := a END;
		a0 := a;
		L := L.next
	END
END CopyLinks;

(** Bind all linked objects. *)
PROCEDURE BindLinks*(list: Link; VAR M: Objects.BindMsg);
BEGIN
	WHILE list # NIL DO
		IF list.obj # NIL THEN
			list.obj.handle(list.obj, M)
		END;
		list := list.next
	END
END BindLinks;

(** Insert a link in a list. An existing link with the same name is discarded. *)
PROCEDURE InsertLink*(VAR list: Link; name: ARRAY OF CHAR; val: Link);
VAR l, p0: Link;
BEGIN
	IF val # NIL THEN
		COPY(name, val.name);
		val.next := NIL;
		IF list = NIL THEN
			list := val
		ELSE
			p0 := NIL; l := list;
			WHILE (l # NIL) & (l.name # name) DO p0 := l; l := l.next END;
			IF l = NIL THEN (* at end of list *)
				p0.next := val;
			ELSE
				IF p0 = NIL THEN (* in beginning of list *)
					val.next := list.next; list := val
				ELSE (* in middle of list *)
					p0.next := val; val.next := l.next
				END;
			END;
		END
	END;
END InsertLink;

(** Link Locate. *)
PROCEDURE FindLink*(name: ARRAY OF CHAR; list: Link): Link;
BEGIN
	WHILE list # NIL DO
		IF name = list.name THEN RETURN list END;
		list := list.next
	END;
	RETURN NIL;
END FindLink;

(** Delete a link. *)
PROCEDURE DeleteLink*(VAR list: Link; name: ARRAY OF CHAR);
VAR a, p: Link;
BEGIN
	a := list; p := NIL; 
	WHILE (a # NIL) & (name # a.name) DO p := a; a := a.next END;
	IF a # NIL THEN (* found *)
		IF p = NIL THEN (* first *) list := a.next
		ELSE p.next := a.next
		END
	END
END DeleteLink;

(** Default handling of setting, retrieving and enumerating a list of links. Parameter list might be modified
during a set operation. *)
PROCEDURE HandleLinkMsg*(VAR list: Link; VAR M: Objects.LinkMsg);
VAR p: Link;
BEGIN
	IF M.id = Objects.enum THEN
		p := list;
		WHILE p # NIL DO
			M.Enum(p.name);
			p := p.next
		END
	ELSIF M.id = Objects.set THEN
		p := list;
		WHILE (p # NIL) & (p.name # M.name) DO p := p.next END;
		IF p # NIL THEN p.obj := M.obj
		ELSE
			NEW(p); p.next := list; list := p;
			COPY(M.name, p.name);
			p.obj := M.obj
		END;
		M.res := 0;
	ELSIF M.id = Objects.get THEN
		p := list;
		WHILE (p # NIL) & (p.name # M.name) DO p := p.next END;
		IF p # NIL THEN M.obj := p.obj; M.res := 0 END
	END
END HandleLinkMsg;

(** Forward a message to all linked objects in the list. USE WITH CARE, MESSAGE CYCLES! *)
PROCEDURE Broadcast*(list: Link; VAR M: Objects.ObjMsg);
BEGIN
	WHILE (list # NIL) DO
		IF list.obj # NIL THEN
			list.obj.handle(list.obj, M)
		END;
		list := list.next
	END;
END Broadcast;

(** Get the named link of obj. *)
PROCEDURE GetLink*(obj: Objects.Object; name: ARRAY OF CHAR; VAR ob1: Objects.Object);
	VAR L: Objects.LinkMsg;
BEGIN
	IF obj # NIL THEN
		L.id := Objects.get; L.res := -1; 
		COPY(name, L.name); L.obj := NIL;
		obj.handle(obj, L);
		ob1 := L.obj
	ELSE
		ob1 := NIL
	END
END GetLink;

(** Set the named link of obj. *)
PROCEDURE SetLink*(obj: Objects.Object; name: ARRAY OF CHAR; ob1: Objects.Object);
	VAR L: Objects.LinkMsg;
BEGIN
	IF obj # NIL THEN
		L.id := Objects.set; L.res := -1; 
		COPY(name, L.name); L.obj := ob1;
		obj.handle(obj, L)
	END
END SetLink;

END Links.

(** Remarks:

1. The links of gadgets (both Gadgets.Object and Gadgets.Frame) are managed by module Gadgets. Module Gadgets use the utility procedures defined in module Links.

*)
