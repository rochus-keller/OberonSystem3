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

MODULE Layouts;	(** portable *)	(*	Jörg Derungs, 31.7.1996	*)

IMPORT Objects, Gadgets, Display, Out;

CONST	(** Node id constants *)
		Inval* = Objects.Inval;

		(** data types *)
		Int* = Objects.Int; Real* = Objects.Real; Bool* = Objects.Bool;
		Char* = Objects.Char; String* = Objects.String;
		Format* = 8;	Ident* =  9;

		(** operators *)
		Def* =  20; Set* =  21;
		Params* =  22; Layout* =  23; Attributes* =  24; Links* =  25;
		Instance* = 26; Obj* = 27; Break* = 28;
		
		(** special layout constants used in NewFormat *)
		Left* = 60; Right* = 61; Bottom* = 62; Top* = 63; Center* = 64;
		Static* = 65; Dynamic* = 66; Hor* = 67; Vert* = 68;
		
		
		(* format ids *)
		left = 0; right = 1; bottom = 3; top = 4;
		sameWidth = 6; sameHeight = 7;
		hstatic = 9; vstatic = 10;
		vert = 12;
		innerleft = 14; innerright = 15; innerbottom = 17; innertop = 18;
		
		(* ObjNode ids *)
		leaf = 0; place = 1; list = 2; table = 3;
		
TYPE
		Node* = POINTER TO NodeDesc;
		NodeDesc* = RECORD
			id* : INTEGER;
			copy : PROCEDURE (node : Node) : Node;
			dsc, last, next : Node
		END;
		
		ValNode = POINTER TO ValNodeDesc;
		ValNodeDesc = RECORD (NodeDesc)
			str : POINTER TO ARRAY OF CHAR;
			char : CHAR;
			int, fills : LONGINT;
			real : REAL;
			bool : BOOLEAN;
			format : INTEGER;
			node : Node;
		END;
		
		AssignNode = POINTER TO AssignNodeDesc;
		AssignNodeDesc = RECORD (NodeDesc)
			name : Objects.Name;
			link : AssignNode;
		END;
		
		ObjNode = POINTER TO ObjNodeDesc;

		SizeProc = PROCEDURE (node : ObjNode);
		MakeProc = PROCEDURE (node : ObjNode; hfill, vfill : INTEGER);
		
		IntLine = POINTER TO ARRAY OF INTEGER;

		ObjNodeDesc = RECORD (NodeDesc)
			obj : Objects.Object;
			type : INTEGER;
			sized, made : BOOLEAN;
			x, y, w, h : INTEGER;
			row, col, spanw, spanh : INTEGER;
			minx, miny, minw, minh : INTEGER;	(*  bounding box of components *)
			hFactor, vFactor : INTEGER;	(* expansion factor *)
			gmaxw, gmaxh, hexpand, vexpand : IntLine;
			hfill, vfill : INTEGER;			(* number of fills in components *)
			hdist, vdist, hborder, vborder : INTEGER;	(* border *)
			cols, rows : INTEGER;				(* rows and columns in TABLE *)
			format : SET;							(* special formatting *)
			def, lastdef : AssignNode;		(* definitions in Configs *)
			size : SizeProc;
			make : MakeProc
		END;
		
VAR Definitions : AssignNode;

PROCEDURE Insert* (node, dsc : Node);
			(**	insert dsc into node	*)
BEGIN
	IF (node=NIL) OR (dsc = NIL) THEN RETURN END;
	IF node.last = NIL THEN node.dsc := dsc; node.last := dsc
	ELSE node.last.next := dsc; node.last := dsc; dsc.next := NIL END;
END Insert;

PROCEDURE SetParams* (node, params : Node);
			(**	set parameters when a Config is used	*)
BEGIN
	IF (node = NIL) OR (params = NIL) THEN RETURN END;
	params.next := node.dsc; node.dsc := params;
	IF node.last = NIL THEN node.last := params END
END SetParams;

PROCEDURE CopyDsc (new, node : Node);		(* new, node # NIL *)
VAR dsc : Node;
BEGIN
	new.dsc := NIL;	new.last := NIL;	new.next := NIL;	dsc := node.dsc;
	WHILE dsc # NIL DO Insert (new, dsc.copy (dsc)); dsc := dsc.next END;
END CopyDsc;

PROCEDURE CopyNode (node : Node) : Node;		(* Type guaranteed by not exporting *)
VAR new : Node;
BEGIN
	NEW (new); new^ := node^; CopyDsc (new, node);
	RETURN new
END CopyNode;

PROCEDURE CopyValNode (node : Node) : Node;		(* Type guaranteed by not exporting *)
VAR new : ValNode;
BEGIN
	NEW (new); new^ := node(ValNode)^; CopyDsc (new, node); new.node := NIL;
	IF new.node # NIL THEN new.node := new.node.copy (new.node) END;
	RETURN new
END CopyValNode;

PROCEDURE CopyAssignNode (node : Node) : Node;		(* Type guaranteed by not exporting *)
VAR new : AssignNode;
BEGIN
	NEW (new); new^ := node(AssignNode)^; CopyDsc (new, node);
	RETURN new;
END CopyAssignNode;

PROCEDURE CopyObjNode (node : Node) : Node;		(* Type guaranteed by not exporting *)
VAR new : ObjNode;
		copy : Objects.CopyMsg;
BEGIN
	NEW (new); new^ := node(ObjNode)^; CopyDsc (new, node);
	new.sized := FALSE; new.made := FALSE; new.def := NIL; new.lastdef := NIL;
	IF new.obj # NIL THEN
		copy.dlink := NIL; copy.id := Objects.deep; Objects.Stamp (copy);
		new.obj.handle (new.obj, copy); new.obj := copy.obj
	END;
	RETURN new
END CopyObjNode;

PROCEDURE CopyOf* (node : Node) : Node;
			(**	make a deep copy of node	*)
BEGIN	RETURN node.copy (node)	END CopyOf;

PROCEDURE IsVirtual* (node : Node) : BOOLEAN;
			(**	TRUE if node is an object and virtual	*)
BEGIN	RETURN (node # NIL) & (node IS ObjNode) & (node(ObjNode).obj # NIL)
END IsVirtual;

PROCEDURE Realize* (node : Node) : Objects.Object;
			(**	once an object is realized, it can't be changed anymore	*)
BEGIN
	IF (node # NIL) & (node IS ObjNode) THEN WITH node : ObjNode DO
		Definitions := NIL;
		node.size (node);
		node.make (node, 0, 0);
		RETURN node.obj
	END ELSE RETURN NIL END
END Realize;

PROCEDURE GetNodeRec (cur : AssignNode; val : Node) : Node;
VAR node : Node;
BEGIN
	WHILE (cur # NIL) & (cur.name # val(ValNode).str^) DO cur := cur.link END;
	IF cur = NIL THEN Out.String (val(ValNode).str^); Out.String (" not found"); Out.Ln; node := NIL
	ELSE
		IF (cur.dsc # NIL) & ((cur.dsc.id = Instance) OR (cur.dsc.id = Ident))
		THEN
			IF cur.dsc(ValNode).node = NIL THEN 
				node := GetNodeRec (cur.link, cur.dsc)
			ELSE node := cur.dsc(ValNode).node END
		ELSE node := cur.dsc END;
		IF (val.id = Instance) & (node # NIL) THEN
			node := node.copy (node);
			IF node.dsc # NIL THEN SetParams (node, val.dsc) END;
		END;
	END;
	val(ValNode).node := node;
	RETURN node
END GetNodeRec;

PROCEDURE GetNode (val : Node; firstTime : BOOLEAN) : Node;
BEGIN
	IF (val = NIL) OR ((val.id # Ident) & (val.id # Instance)) THEN RETURN val END;
	IF firstTime THEN RETURN GetNodeRec (Definitions, val) ELSE RETURN val(ValNode).node END
END GetNode;

PROCEDURE NewValNode (type : INTEGER) : ValNode;
VAR node : ValNode;
BEGIN	NEW (node);
	node.dsc := NIL; node.next := NIL; node.last := NIL;
	node.id := type; node.node := NIL; node.copy := CopyValNode;
	RETURN node
END NewValNode;

(**	Nodes for values	*)
			
PROCEDURE NewString* (str : ARRAY OF CHAR) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (String); NEW (node.str, LEN (str)); COPY (str, node.str^);
	RETURN node
END NewString;

PROCEDURE NewIdent* (str : ARRAY OF CHAR) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Ident); NEW (node.str, LEN (str)); COPY (str, node.str^);
	RETURN node
END NewIdent;

PROCEDURE NewChar* (ch : CHAR) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Char); node.char := ch;
	RETURN node;
END NewChar;

PROCEDURE NewInt* (int : LONGINT) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Int); node.int := int; node.fills := 0;
	RETURN node
END NewInt;

PROCEDURE NewSize* (MinSize, ExpandFactor : INTEGER) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Int); node.int := MinSize; node.fills := ExpandFactor;
	RETURN node
END NewSize;

PROCEDURE NewReal* (real : REAL) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Real); node.real := real;
	RETURN node
END NewReal;

PROCEDURE NewBool* (bool : BOOLEAN) : Node;
VAR node : ValNode;
BEGIN
	node := NewValNode (Bool); node.bool := bool;
	RETURN node
END NewBool;

PROCEDURE NewFormat* (sym : INTEGER) : Node;	(**	sym = Left | Right | Bottom | Top | Center | Static ...	*)
VAR node : ValNode;
BEGIN
	node := NewValNode (Format); node.format := sym;
	RETURN node
END NewFormat;

(**	create new Nodes	*)
			
PROCEDURE NewNode* (id : INTEGER) : Node;		(**	LAYOUT, ATTR, LINKS, PARAMS	*)
			(**	id = Layout | Attributes | Links | Params.											 *)
			(**	Params are not inserted but set with "SetParams (node, params)".	*)
VAR node : Node;
BEGIN	NEW (node);
	node.dsc := NIL;	node.next := NIL;	node.last := NIL;
	node.id := id;	node.copy := CopyNode;
	RETURN node
END NewNode;

PROCEDURE NewAssignNode (id : INTEGER; name : ARRAY OF CHAR; val : Node) : Node;
VAR node : AssignNode;
BEGIN	NEW (node);
	node.dsc := NIL;	node.next := NIL;	node.last := NIL;
	node.id := id;	node.copy := CopyAssignNode;
	COPY (name, node.name);	Insert (node, val);	node.link := NIL;
	RETURN node
END NewAssignNode;

PROCEDURE NewSet* (Name : ARRAY OF CHAR; Value : Node) : Node;		(**	SET	*)
BEGIN	RETURN NewAssignNode (Set, Name, Value)
END NewSet;

PROCEDURE NewDef* (Name : ARRAY OF CHAR; Value : Node) : Node;		(**	DEF	*)
VAR node : Node;
BEGIN	
	node := NewAssignNode (Def, Name, Value);
	node(AssignNode).link := Definitions; Definitions := node(AssignNode);
	RETURN node
END NewDef;

PROCEDURE NewObj (size : SizeProc; make : MakeProc; id : ARRAY OF CHAR) : Node;
VAR node : ObjNode;
		alias : ARRAY 64 OF CHAR;
BEGIN	NEW (node);
	node.dsc := NIL; node.next := NIL; node.last := NIL; node.id := Obj; node.copy := CopyObjNode;		(* Node *)
	Gadgets.GetAlias (id, alias); IF alias = "" THEN COPY (id, alias) END;
	IF alias # "" THEN node.obj := Gadgets.CreateObject (alias) ELSE node.obj := NIL END;	(* ObjNode *)
	node.sized := FALSE; node.made := FALSE; node.size := size; node.make := make;
	node.x := 0; node.y := 0; node.w := 0; node.h := 0;
	node.col := 0; node.row := 0; node.spanw := 1; node.spanh := 1;
	node.minx := MAX(INTEGER); node.miny := MAX(INTEGER); node.minw := 0; node.minh := 0;
	IF node.obj = NIL THEN node.hFactor := 1; node.vFactor := 1 ELSE node.hFactor := 0; node.vFactor := 0 END;
	node.hfill := 0; node.vfill := 0; node.cols := 1; node.rows := 1;
	node.gmaxw := NIL; node.gmaxh := NIL; node.hexpand := NIL; node.vexpand := NIL;
	node.hdist := 5; node.vdist := 5; node.hborder := 0; node.vborder := 0;
	node.format := {left, bottom, innerleft, innerbottom};
	RETURN node
END NewObj;

PROCEDURE SetAttributes (obj : Objects.Object; node : Node);		(* obj # NIL *)
VAR assign, val : Node;
		attrMsg : Objects.AttrMsg;
BEGIN
	WHILE node # NIL DO
		assign := GetNode (node, TRUE);
		IF (assign # NIL) & (assign IS AssignNode) THEN WITH assign : AssignNode DO
			val := GetNode (assign.dsc, TRUE);
			IF (val # NIL) & (val IS ValNode) THEN WITH val : ValNode DO
				attrMsg.id := Objects.set; attrMsg.class := val.id;
				COPY (assign.name, attrMsg.name);
				CASE val.id OF
					String : COPY (val.str^, attrMsg.s)
					| Int : attrMsg.i := val.int
					| Real : attrMsg.x := val.real
					| Bool : attrMsg.b := val.bool
					| Char : attrMsg.c := val.char
				ELSE Out.String ("invalid attribute type in "); Out.String (assign.name); Out.String (": "); Out.Int (val.id, 0); Out.Ln
				END;
				attrMsg.res := -1;	obj.handle (obj, attrMsg);
				IF attrMsg.res < 0 THEN
					Out.String ("Attribute "); Out.String (assign.name); Out.String (" not accepted"); Out.Ln
				END
			END ELSE Out.String ("Attribute "); Out.String (assign.name); Out.String (" has no valid value"); Out.Ln END
		END END;
		node := node.next
	END
END SetAttributes;

PROCEDURE SetLinks (obj : Objects.Object; node : Node);		(* obj # NIL *)
VAR assign, val : Node;
		linkMsg : Objects.LinkMsg;
BEGIN
	WHILE node # NIL DO
		assign := GetNode (node, TRUE);
		IF (assign # NIL) & (assign IS AssignNode) THEN WITH assign : AssignNode DO
			val := GetNode (assign.dsc, TRUE);
			IF (val # NIL) & (val IS ObjNode) THEN WITH val : ObjNode DO
				linkMsg.id := Objects.set;	COPY (assign.name, linkMsg.name);	linkMsg.res := -1;
				val.size (val); val.make (val, 0, 0);
				linkMsg.obj := val.obj;
				obj.handle (obj, linkMsg);
				IF linkMsg.res < 0 THEN
					Out.String ("Link "); Out.String (assign.name); Out.String (" not accepted"); Out.Ln
				END;
			END END;
		END END;
		node := node.next;
	END;
END SetLinks;

PROCEDURE Settings (node : ObjNode);
VAR dsc, list : Node;
BEGIN
	IF node.obj # NIL THEN
		dsc := node.dsc;
		WHILE dsc # NIL DO
			list := GetNode (dsc, FALSE);
			IF list # NIL THEN
				IF list.id = Attributes THEN SetAttributes (node.obj, list.dsc)
				ELSIF list.id = Links THEN SetLinks (node.obj, list.dsc) END
			END;
			dsc := dsc.next
		END;
	END;
END Settings;

PROCEDURE SetLayout (node : ObjNode; layout : Node);
VAR assign, val : Node;
BEGIN
	WHILE layout # NIL DO
		assign := GetNode (layout, TRUE);
		IF (assign # NIL) & (assign IS AssignNode) THEN WITH assign : AssignNode DO
			val := GetNode (assign.dsc, TRUE);
			IF (val # NIL) & (val IS ValNode) THEN WITH val : ValNode DO
				IF val # NIL THEN
					IF (assign.name = "w") THEN node.w := SHORT (val.int);
						IF (node.w < 0) & (node.obj # NIL) & (node.obj IS Display.Frame) THEN
							node.w := node.obj(Display.Frame).W
						END;	node.hFactor := SHORT (val.fills)
					ELSIF (assign.name = "h") THEN node.h := SHORT (val.int);
						IF (node.h < 0) & (node.obj # NIL) & (node.obj IS Display.Frame) THEN
							node.h := node.obj(Display.Frame).H
						END;	node.vFactor := SHORT (val.fills)
					ELSIF (assign.name = "x") & (val.id = Int) THEN node.x := SHORT (val.int)
					ELSIF (assign.name = "y") & (val.id = Int) THEN node.y := SHORT (val.int)
					ELSIF (assign.name = "hjustifyMe") & (val.id = Format) THEN
						IF val.format = Left THEN INCL (node.format, left); EXCL (node.format, right)
						ELSIF val.format = Right THEN INCL (node.format, right); EXCL (node.format, left)
						ELSIF val.format = Center THEN INCL (node.format, left); INCL (node.format, right)
						ELSE Out.String ("unknown hjustify: "); Out.Int (val.format, 0); Out.Ln END
					ELSIF (assign.name = "vjustifyMe") & (val.id = Format) THEN
						IF val.format = Bottom THEN INCL (node.format, bottom); EXCL (node.format, top)
						ELSIF val.format = Top THEN INCL (node.format, top); EXCL (node.format, bottom)
						ELSIF val.format = Center THEN INCL (node.format, bottom); INCL (node.format, top)
						ELSE Out.String ("unknown vjustify: "); Out.Int (val.format, 0); Out.Ln END
					ELSIF node.type > leaf THEN
						IF (assign.name = "hborder") & (val.id = Int) THEN node.hborder := SHORT (val.int)
						ELSIF (assign.name = "vborder") & (val.id = Int) THEN node.vborder := SHORT (val.int)
						ELSIF (assign.name = "border") & (val.id = Int) THEN
							node.hborder := SHORT (val.int); node.vborder := SHORT (val.int)
						ELSIF node.type > place THEN
							IF (assign.name = "hdist") & (val.id = Int) THEN node.hdist := SHORT (val.int);
							ELSIF (assign.name = "vdist") & (val.id = Int) THEN node.vdist := SHORT (val.int);
							ELSIF (assign.name = "dist") & (val.id = Int) THEN node.hdist := SHORT (val.int); node.vdist := SHORT (val.int)
							ELSIF (assign.name = "hjustify") & (val.id = Format) THEN
								IF val.format = Left THEN INCL (node.format, innerleft); EXCL (node.format, innerright)
								ELSIF val.format = Right THEN INCL (node.format, innerright); EXCL (node.format, innerleft)
								ELSIF val.format = Center THEN INCL (node.format, innerleft); INCL (node.format, innerright)
								ELSE Out.String ("unknown hjustify: "); Out.Int (val.format, 0); Out.Ln END
							ELSIF (assign.name = "vjustify") & (val.id = Format) THEN
								IF val.format = Bottom THEN INCL (node.format, innerbottom); EXCL (node.format, innertop)
								ELSIF val.format = Top THEN INCL (node.format, innertop); EXCL (node.format, innerbottom)
								ELSIF val.format = Center THEN INCL (node.format, innerbottom); INCL (node.format, innertop)
								ELSE Out.String ("unknown vjustify: "); Out.Int (val.format, 0); Out.Ln END
							ELSIF (assign.name = "hgrid") & (val.id = Format) THEN
								IF val.format = Static THEN INCL (node.format, hstatic)
								ELSIF val.format = Dynamic THEN EXCL (node.format, hstatic)
								ELSE Out.String ("unknown hgrid: "); Out.Int (val.format, 0); Out.Ln END
							ELSIF (assign.name = "vgrid") & (val.id = Format) THEN
								IF val.format = Static THEN INCL (node.format, vstatic)
								ELSIF val.format = Dynamic THEN EXCL (node.format, vstatic)
								ELSE Out.String ("unknown vgrid: "); Out.Int (val.format, 0); Out.Ln END
							ELSIF (assign.name = "grid") & (val.id = Format) THEN
								IF val.format = Static THEN INCL (node.format, hstatic); INCL (node.format, vstatic)
								ELSIF val.format = Dynamic THEN EXCL (node.format, hstatic); EXCL (node.format, vstatic)
								ELSE Out.String ("unknown grid: "); Out.Int (val.format, 0); Out.Ln END
							ELSIF (assign.name = "sameWidth") & (val.id = Bool) THEN
								IF val.bool THEN INCL (node.format, sameWidth) ELSE EXCL (node.format, sameWidth) END
							ELSIF (assign.name = "sameHeight") & (val.id = Bool) THEN
								IF val.bool THEN INCL (node.format, sameHeight) ELSE EXCL (node.format, sameHeight) END
							ELSIF (assign.name = "sameSize") & (val.id = Bool) THEN
								IF val.bool THEN INCL (node.format, sameWidth); INCL (node.format, sameHeight)
								ELSE EXCL (node.format, sameWidth); EXCL (node.format, sameHeight) END
							ELSIF node.type > list THEN
								IF (assign.name = "cols") & (val.id = Int) THEN node.cols := SHORT (val.int)
								ELSIF (assign.name = "rows") & (val.id = Int) THEN node.rows := SHORT (val.int)
								ELSIF (assign.name = "orientation") & (val.id = Format) THEN
									IF val.format = Hor THEN EXCL (node.format, vert)
									ELSIF val.format = Vert THEN INCL (node.format, vert)
									ELSE Out.String ("unknown orientation: "); Out.Int (val.format, 0); Out.Ln END
								ELSE Out.String ("TABLE: unknown layout primitive '"); Out.String (assign.name);
									Out.String ("' or wrong argument type"); Out.Ln
								END
							ELSE Out.String ("HLIST/VLIST: unknown layout primitive '"); Out.String (assign.name);
								Out.String ("' or wrong argument type"); Out.Ln
							END
						ELSE Out.String ("PLACE: unknown layout primitive '"); Out.String (assign.name);
							Out.String ("' or wrong argument type"); Out.Ln
						END
					ELSE Out.String ("Object: unknown layout primitive '"); Out.String (assign.name);
						Out.String ("' or wrong argument type"); Out.Ln
					END
				END
			END END
		END END;
		layout := layout.next
	END
END SetLayout;

PROCEDURE SizeOf (node : ObjNode);		(* node # NIL *)
VAR dsc, list : Node;
BEGIN
	dsc := node.dsc; list := GetNode (dsc, FALSE);
	WHILE (dsc # NIL) & ((list = NIL) OR (list.id # Layout)) DO dsc := dsc.next; list := GetNode (dsc, FALSE) END;
	IF list # NIL THEN SetLayout (node, list.dsc) END;
END SizeOf;

PROCEDURE Reset (node : ObjNode);		(*	node # NIL	*)
BEGIN
	IF node.obj # NIL THEN
		IF node.obj IS Display.Frame THEN
			node.obj(Display.Frame).X := node.x; node.obj(Display.Frame).Y := node.y
		END;
		node.obj.slink := NIL
	END
END Reset;

PROCEDURE FindIdents (node : Node);
VAR dmy : Node;
BEGIN	WHILE node # NIL DO dmy := GetNode (node, TRUE); node := node.next END
END FindIdents;

PROCEDURE SizeOfNew (node : ObjNode);		(* node # NIL *)
BEGIN
	IF node.sized THEN Reset (node); RETURN
	ELSE node.sized := TRUE END;
	FindIdents (node.dsc);
	Settings (node);
	IF (node.obj # NIL) & (node.obj IS Display.Frame) THEN
		node.w := node.obj(Display.Frame).W;	node.h := node.obj(Display.Frame).H
	END;
	SizeOf (node);
END SizeOfNew;

PROCEDURE MakeNew (node : ObjNode; hfill, vfill : INTEGER);		(* node # NIL *)
VAR obj : Display.Frame; M: Display.ModifyMsg;
BEGIN
	IF node.made THEN Reset (node); RETURN ELSE node.made := TRUE END;
	(* re-evaluate width and height *)
	IF node.hFactor > 0 THEN node.w := node.w + hfill END;
	IF node.vFactor > 0 THEN node.h := node.h + vfill END;
	IF (node.x = 0) & (node.hFactor = 0) THEN
		IF right IN node.format THEN node.x := hfill END;
		IF left IN node.format THEN node.x := node.x DIV 2 END
	END;
	IF (node.y = 0) & (node.vFactor = 0) THEN
		IF top IN node.format THEN node.y := vfill END;
		IF bottom IN node.format THEN node.y := node.y DIV 2 END
	END;
	IF (node.obj # NIL) & (node.obj IS Display.Frame) THEN
		obj := node.obj(Display.Frame);
		M.F := obj; M.id := Display.extend; M.mode := Display.state; M.x := 0; M.y := 0;
		M.X := node.x; M.Y := node.y; M.W := node.w; M.H := node.h;
		M.dX := M.X - obj.X; M.dY := M.Y - obj.Y; M.dW := M.W - obj.W; M.dH := M.H - obj.H;
		M.res := -1; Objects.Stamp(M);
		obj.handle(obj, M)
	END;
END MakeNew;

PROCEDURE SizeOfPlace (node : ObjNode);		(* node # NIL *)
VAR dsc, obj : Node;
BEGIN
	IF node.sized THEN Reset (node); RETURN END;
	node.hFactor := 0; node.vFactor := 0;
	FindIdents (node.dsc); SizeOf (node);
	dsc := node.dsc;
	WHILE dsc # NIL DO
		obj := GetNode (dsc, FALSE);
		IF (obj # NIL) & (obj IS ObjNode) THEN WITH obj : ObjNode DO
			obj.size (obj);
			IF node.minw < obj.x+obj.w THEN node.minw := obj.x+obj.w END;
			IF node.minh < obj.y+obj.h THEN node.minh := obj.y+obj.h END;
		END END;
		dsc := dsc.next;
	END;
	IF node.hFactor+node.w = 0 THEN node.w := node.minw+2*node.hborder END;
	IF node.vFactor+node.h = 0 THEN node.h := node.minh+2*node.vborder END;
END SizeOfPlace;

PROCEDURE PlaceObjects (VAR last, obj : Objects.Object; w, h : INTEGER; VAR minx, miny : INTEGER);		(* last # NIL *)
BEGIN
	last.slink := obj;
	WHILE last.slink # NIL DO
		last := last.slink;
		IF last IS Display.Frame THEN WITH last : Display.Frame DO
			last.X := last.X+w;	last.Y := last.Y-h;
			IF minx > last.X THEN minx := last.X END;
			IF miny > last.Y THEN miny := last.Y END
		END END;
	END;
END PlaceObjects;

PROCEDURE InsertObjects (node : ObjNode; obj : Objects.Object);		(* obj # NIL, node # NIL *)
VAR msg : Display.ConsumeMsg;
BEGIN
	obj := obj.slink;
	IF node.obj = NIL THEN node.obj := obj;
		WHILE obj # NIL DO
			IF obj IS Display.Frame THEN INC (obj(Display.Frame).X, node.x); INC (obj(Display.Frame).Y, node.y) END;
			obj := obj.slink
		END
	ELSIF node.obj IS Display.Frame THEN
		msg.F := node.obj(Display.Frame);									(* Display.FrameMsg *)
		msg.x := 0;	msg.y := 0;	msg.res := -1;
		msg.id := Display.drop;	(* Display.ConsumeMsg *)
		msg.u := node.minx;	msg.v := -node.h+node.miny+1;	msg.obj := obj;
		msg.dlink := NIL;	Objects.Stamp (msg);						(* Objects.ObjMsg *)
		node.obj.handle (node.obj, msg);
		IF msg.res < 0 THEN Out.String ("inserting failed"); Out.Ln END
	END
END InsertObjects;

PROCEDURE MakePlace (node : ObjNode; hfill, vfill : INTEGER);		(* node # NIL *)
VAR dsc, objnode : Node;
		obj, last : Objects.Object;
		dh, dv : INTEGER;
BEGIN
	IF node.made THEN Reset (node); RETURN END;
	MakeNew (node, hfill, vfill);
	dh := node.w-2*node.hborder;
	dv := node.h-2*node.vborder;
	NEW (last); obj := last; obj.slink := NIL;	dsc := node.dsc;
	WHILE dsc # NIL DO
		objnode := GetNode (dsc, FALSE);
		IF (objnode # NIL) & (objnode IS ObjNode) THEN WITH objnode : ObjNode DO
			objnode.make (objnode, dh-objnode.x-objnode.w, dv-objnode.y-objnode.h);
			PlaceObjects (last, objnode.obj, node.hborder, -node.vborder, node.minx, node.miny);
		END END;
		dsc := dsc.next
	END;
	InsertObjects (node, obj);
	Settings (node)
END MakePlace;

PROCEDURE CountRows (vert : BOOLEAN; obj : Node; cols : INTEGER; VAR rows : INTEGER);
TYPE Line = POINTER TO RECORD
			cell : POINTER TO ARRAY OF BOOLEAN;
			next : Line
		END;

VAR row, col : INTEGER;
		free : Line;
		node : Node;

		PROCEDURE NewLine (n : INTEGER) : Line;
		VAR line : Line;
		BEGIN	NEW (line);	NEW (line.cell, n);
			WHILE n # 0 DO DEC (n); line.cell[n] := TRUE END;
			RETURN line
		END NewLine;

		PROCEDURE Mark (VAR sw, sh, myrow, mycol : INTEGER);
		VAR cur : Line;
				i, j : INTEGER;
		BEGIN	myrow := row;	mycol := col;
			IF col+sw > cols THEN Out.String ("Span too wide"); Out.Ln; sw := cols-col END;
			FOR i := 0 TO sw-1 DO free.cell[col+i] := FALSE END;
			cur := free;
			FOR j := 2 TO sh DO
				IF cur.next = NIL THEN cur.next := NewLine (cols); INC (rows) END;
				cur := cur.next;
				FOR i := 0 TO sw-1 DO cur.cell[col+i] := FALSE END
			END;
		END Mark;

BEGIN	row := 0;	col := 0;	free := NIL;
	rows := 0;
	WHILE obj # NIL DO
		node := GetNode (obj, FALSE);
		IF (node # NIL) & (node IS ObjNode) THEN WITH node : ObjNode DO
			IF node.id = Obj THEN
				IF (col = 0) & (free = NIL) THEN
					free := NewLine (cols); INC (rows)
				END;
				IF vert THEN Mark (node.spanh, node.spanw, node.col, node.row)
				ELSE Mark (node.spanw, node.spanh, node.row, node.col) END;
				REPEAT col := (col+1) MOD cols;
					IF col = 0 THEN free := free.next; INC (row) END
				UNTIL (free = NIL) OR free.cell[col]
			ELSIF (node.id = Break) THEN col := 0;
				WHILE free # NIL DO free := free.next; INC (row) END;
				node.col := row; node.row := row
			END
		END END;
		obj := obj.next
	END
END CountRows;

PROCEDURE CalcSize (node : ObjNode; VAR minSize : INTEGER; VAR break : BOOLEAN);		(* node # NIL *)
TYPE WideCell = POINTER TO RECORD
			key : LONGINT;
			col, span : INTEGER;
			size, fills : INTEGER;
			next : WideCell
		END;
VAR dsc, obj : Node;
		wanchor, hanchor : WideCell;
		set : SET;

		PROCEDURE Adjust (w, fill, col, span : INTEGER; max, expand : IntLine; anchor : WideCell);		(* max, expand # NIL *)
		VAR cur, new : WideCell;
				key : LONGINT;
		BEGIN
			IF span = 1 THEN
				IF fill = 0 THEN expand[col] := MAX(INTEGER)
				ELSIF fill > expand[col] THEN expand[col] := fill END;
				IF max[col] < w THEN max[col] := w END;
			ELSE	cur := anchor; key := LONG(col+span)*LONG(MAX(INTEGER)) - col;
				WHILE key > cur.next.key DO cur := cur.next END;
				IF key = cur.next.key THEN cur := cur.next;
					IF cur.size < w THEN cur.size := w END;
					IF fill = 0 THEN cur.fills := MAX(INTEGER)
					ELSIF cur.fills < fill THEN cur.fills := fill END
				ELSE	(* key < cur.next.key *)
					NEW (new); new.key := key;
					new.col := col; new.span := span; new.size := w;
					IF fill = 0 THEN new.fills := MAX(INTEGER) ELSE new.fills := fill END;
					new.next := cur.next; cur.next := new;
				END;
			END;
		END Adjust;
		
		PROCEDURE EvalSpan (anchor : WideCell; dist : INTEGER; VAR nodefills : INTEGER; VAR max, expand : IntLine;
											sameSize : BOOLEAN);
		VAR cur : WideCell;
				fillList : IntLine;
				col, fills, cf, m, d : INTEGER;
		BEGIN	cur := anchor.next;
			WHILE cur # anchor DO
				DEC (cur.size, (cur.span-1)*dist);
				IF sameSize THEN
					m := cur.size DIV cur.span; IF cur.size MOD cur.span > 0 THEN INC (m) END;
					IF m > max[cur.col] THEN max[cur.col] := m END
				ELSE fills := 0; IF cur.fills = MAX(INTEGER) THEN cur.fills := 0 END; cf := cur.fills;
					FOR col := cur.col TO cur.col+cur.span-1 DO
						IF expand[col] = MAX(INTEGER) THEN expand[col] := 0 END;
						INC (fills, expand[col]); DEC (cur.fills, expand[col]);
						DEC (cur.size, max[col]);
						d := col
					END;
					IF fills > 0 THEN
						IF cur.fills > 0 THEN INC (expand[d], cur.fills); INC (nodefills, cur.fills); INC (fills, cur.fills) END;
						NEW (fillList, fills); m := 0;
						FOR col := cur.col TO cur.col+cur.span-1 DO
							FOR d := 1 TO expand[col] DO fillList[m] := col; INC (m) END
						END;
						col := 0;
						WHILE cur.size > 0 DO	d := fillList [col MOD fills];
							IF max[d] < (col DIV fills) * expand[d] THEN INC (max[d]); DEC (cur.size) END;
							INC (col)
						END
					ELSIF cur.size > 0 THEN INC (max[cur.col+cur.span-1], cur.size)
					END;
					IF cf = 0 THEN FOR col := cur.col TO cur.col+cur.span-1 DO expand[col] := 0 END END
				END;
				cur := cur.next
			END
		END EvalSpan;

BEGIN
	dsc := node.dsc;	minSize := 0;	break := FALSE;
	NEW (wanchor); wanchor.key := MAX(LONGINT); wanchor.next := wanchor;
	NEW (hanchor); hanchor.key := MAX(LONGINT); hanchor.next := hanchor;
	node.minw := 2*node.hborder + (node.cols-1)*node.hdist;
	node.minh := 2*node.vborder + (node.rows-1)*node.vdist;
	WHILE dsc # NIL DO
		obj := GetNode (dsc, FALSE);
		IF (obj # NIL) & (obj IS ObjNode) THEN WITH obj : ObjNode DO
			IF obj.id = Obj THEN
				set := {};
				IF innerleft IN node.format THEN INCL (set, left) END; IF innerright IN node.format THEN INCL (set, right) END;
				IF innertop IN node.format THEN INCL (set, top) END; IF innerbottom IN node.format THEN INCL (set, bottom) END;
				obj.format := (obj.format - {left..top}) + set;
				obj.size (obj);
				Adjust (obj.w, obj.hFactor, obj.col, obj.spanw, node.gmaxw, node.hexpand, wanchor);
				Adjust (obj.h, obj.vFactor, obj.row, obj.spanh, node.gmaxh, node.vexpand, hanchor);
				break := FALSE;
			ELSIF obj.id = Break THEN
				obj.size (obj);
				IF vert IN node.format THEN
					INC (node.minw, obj.w); IF minSize < obj.h THEN minSize := obj.h; END;
					IF ~break THEN IF obj.col = 0 THEN DEC (node.minw, node.hborder) ELSE DEC (node.minw, node.hdist) END END
				ELSE INC (node.minh, obj.h); IF minSize < obj.w THEN minSize := obj.w END;
					IF ~break THEN IF obj.row = 0 THEN DEC (node.minh, node.vborder) ELSE DEC (node.minh, node.vdist) END END
				END;
				break := TRUE;
			END;
		END END;
		dsc := dsc.next
	END;
	IF break THEN
		IF vert IN node.format THEN DEC (node.minw, node.hborder-node.hdist)
		ELSE DEC (node.minh, node.vborder-node.vdist) END;
	END;
	EvalSpan (wanchor, node.hdist, node.hfill, node.gmaxw, node.hexpand, node.format*{sameWidth, hstatic} # {});
	EvalSpan (hanchor, node.vdist, node.vfill, node.gmaxh, node.vexpand, node.format*{sameHeight, vstatic} # {})
END CalcSize;

PROCEDURE SetSize (VAR hfill, min, w : INTEGER; cols, minSize : INTEGER; VAR expand, max : IntLine;
									hor, sameWidth, setSize : BOOLEAN);
VAR col, n : INTEGER;
BEGIN
	IF sameWidth THEN	hfill := 0;
		FOR col := 0 TO cols-1 DO
			IF expand[col] = MAX(INTEGER) THEN expand[col] := 0 END;
			INC (hfill, expand[col]);
			INC (min, max[col])
		END;
		IF setSize THEN w := min;
			IF hor & (w < minSize) THEN w := minSize END
		END
	ELSIF setSize THEN	n := 0;
		FOR col := 0 TO cols-1 DO IF n < max[col] THEN n := max[col] END END;
		w := cols*n + min;
		IF hor & (w < minSize) THEN w := minSize END;
	END;
END SetSize;

PROCEDURE SizeOfTable (node : ObjNode);		(* node # NIL *)
VAR n, minSize : INTEGER;
		break : BOOLEAN;
BEGIN
	IF node.sized THEN Reset (node); RETURN END;
	node.hFactor := 0; node.vFactor := 0;
	FindIdents (node.dsc); SizeOf (node);
	IF vert IN node.format THEN CountRows (vert IN node.format, node.dsc, node.rows, node.cols)
	ELSE CountRows (vert IN node.format, node.dsc, node.cols, node.rows) END;
	IF node.rows * node.cols = 0 THEN node.w := 2*node.hborder; node.h := 2*node.vborder
	ELSE
		NEW (node.gmaxw, node.cols);	NEW (node.hexpand, node.cols);
		NEW (node.gmaxh, node.rows);	NEW (node.vexpand, node.rows);
		FOR n := 0 TO node.cols-1 DO node.gmaxw[n] := 0; node.hexpand[n] := 1 END;
		FOR n := 0 TO node.rows-1 DO node.gmaxh[n] := 0; node.vexpand[n] := 1 END;
		CalcSize (node, minSize, break);
		SetSize (node.hfill, node.minw, node.w, node.cols, minSize, node.hexpand, node.gmaxw,
					~(vert IN node.format), node.format*{sameWidth, hstatic} = {}, node.hFactor+node.w = 0);
		SetSize (node.vfill, node.minh, node.h, node.rows, minSize, node.vexpand, node.gmaxh,
					vert IN node.format, node.format*{sameHeight, vstatic} = {}, node.vFactor+node.h = 0);
	END
END SizeOfTable;

PROCEDURE FillCols (space, cols, fills : INTEGER; expand, max : IntLine; sameSize : BOOLEAN);		(* expand, max # NIL *)
VAR fillList : IntLine;
		d, m, col : INTEGER;
BEGIN
	IF sameSize THEN
		d := space DIV cols;	m := space MOD cols;
		FOR col := 0 TO cols-1 DO max[col] := d END;
		FOR col := 0 TO m-1 DO INC (max[col]) END;
	ELSIF space > 0 THEN
		IF fills > 0 THEN
			NEW (fillList, fills);	m := 0;
			FOR col := 0 TO cols-1 DO
				FOR d := 1 TO expand[col] DO fillList[m] := col; INC (m) END
			END;
			col := 0;
			WHILE space > 0 DO	d := fillList [col MOD fills];
				IF max[d] < (col DIV fills) * expand[d] THEN INC (max[d]); DEC (space) END;
				INC (col)
			END
		ELSE INC (max[cols-1], space) END;
	END;
END FillCols;

PROCEDURE SetOffset (cols, border, dist : INTEGER; VAR max, offset : IntLine);		(* max # NIL *)
VAR col : INTEGER;
BEGIN	NEW (offset, cols+1);
	offset[0] := border;
	FOR col := 0 TO cols-1 DO offset[col+1] := offset[col]; INC (offset[col+1], max[col] + dist) END
END SetOffset;

PROCEDURE MakeTable (node : ObjNode; hfill, vfill : INTEGER);		(* node # NIL *)
VAR dsc, objnode : Node;
		obj, last : Objects.Object;
		row, col, w, h : INTEGER;
		hoffset, voffset : IntLine;
		break : BOOLEAN;
BEGIN
	IF node.made THEN Reset (node); RETURN END;
	MakeNew (node, hfill, vfill);
	IF node.cols * node.rows = 0 THEN Settings (node); RETURN END;
	FillCols (node.w-node.minw, node.cols, node.hfill, node.hexpand, node.gmaxw, node.format*{sameWidth, hstatic} # {});
	FillCols (node.h-node.minh, node.rows, node.vfill, node.vexpand, node.gmaxh, node.format*{sameHeight, vstatic} # {});
	SetOffset (node.cols, node.hborder, node.hdist, node.gmaxw, hoffset);
	SetOffset (node.rows, node.vborder, node.vdist, node.gmaxh, voffset);

	NEW (last); obj := last; obj.slink := NIL; dsc := node.dsc; break := FALSE;
	WHILE dsc # NIL DO
		objnode := GetNode (dsc, FALSE);
		IF (objnode # NIL) & (objnode IS ObjNode) THEN WITH objnode : ObjNode DO
			IF objnode.id = Obj THEN
				objnode.x := 0; objnode.y := 0;
				w := hoffset[objnode.col+objnode.spanw] - hoffset[objnode.col] - node.hdist;
				h := voffset[objnode.row+objnode.spanh] - voffset[objnode.row] - node.vdist;
				IF sameWidth IN node.format THEN objnode.w := w END;
				IF sameHeight IN node.format THEN objnode.h := h END;
				objnode.make (objnode, w-objnode.w, h-objnode.h);
				PlaceObjects (last, objnode.obj, hoffset[objnode.col], voffset[objnode.row+objnode.spanh]-node.vdist-node.h,
						node.minx, node.miny);
				break := FALSE
			ELSIF objnode.id = Break THEN
				IF vert IN node.format THEN
					objnode.make (objnode, 0, node.h-objnode.h);
					IF break THEN w := 0 ELSIF objnode.col = 0 THEN w := node.hborder ELSE w := node.hdist END;
					PlaceObjects (last, objnode.obj, hoffset[objnode.col]-w, objnode.h-node.h, node.minx, node.miny);
					FOR col := objnode.col TO node.cols DO INC (hoffset[col], objnode.w-w) END
				ELSE
					objnode.make (objnode, node.w-objnode.w, 0);
					IF break THEN h := 0 ELSIF objnode.row = 0 THEN h := node.vborder ELSE h := node.vdist END;
					PlaceObjects (last, objnode.obj, 0, voffset[objnode.row]-h+objnode.h-node.h, node.minx, node.miny);
					FOR row := objnode.row TO node.rows DO INC (voffset[row], objnode.h-h) END
				END;
				break := TRUE;
			END
		END END;
		dsc := dsc.next
	END;
	InsertObjects (node, obj);
	Settings (node)
END MakeTable;

PROCEDURE SizeOfTransient (node : ObjNode);		(* node # NIL *)
VAR obj : Node;
BEGIN
	IF node.sized THEN Reset (node); RETURN END;
	node.sized := TRUE;
	obj := GetNode (node.last, TRUE);
	IF (obj = NIL) OR ~(obj IS ObjNode) THEN
		obj := NewObj (SizeOfNew, MakeNew, "");
		Out.String ("invalid object replaced by VIRTUAL"); Out.Ln
	END;
	WITH obj : ObjNode DO
		obj.format := (obj.format - {left..top}) + (node.format * {left..top});
		obj.size (obj);
		node.x := obj.x; node.y := obj.y; node.w := obj.w; node.h := obj.h;
		node.hFactor := obj.hFactor; node.vFactor := obj.vFactor; node.format := obj.format
	END;
END SizeOfTransient;

PROCEDURE MakeTransient (node : ObjNode; hfill, vfill : INTEGER);		(* node # NIL *)
VAR obj : Node;
BEGIN
	IF node.made THEN Reset (node); RETURN END;
	node.made := TRUE;
	obj := GetNode (node.last, FALSE);
	IF (obj = NIL) OR ~(obj IS ObjNode) THEN obj := NewObj (SizeOfNew, MakeNew, "") END;
	WITH obj : ObjNode DO
		obj.x := node.x; obj.y := node.y; obj.w := node.w; obj.h := node.h;
		obj.make (obj, hfill, vfill);
		node.x := obj.x; node.y := obj.y; node.w := obj.w; node.h := obj.h;
		node.obj := obj.obj
	END
END MakeTransient;

PROCEDURE SizeOfConfig (node : ObjNode);		(* node # NIL *)
VAR oldDefinitions, def : AssignNode;
		dsc, params, cur, assign : Node;
BEGIN
	IF node.sized THEN Reset (node); RETURN END;
	(* copy DEF nodes to node.def *)
	dsc := node.dsc;
	WHILE dsc # node.last DO
		assign := GetNode (dsc, TRUE);
		IF (assign # NIL) & (assign.id = Def) THEN
			NEW (def); def^ := assign(AssignNode)^;
			def.link := node.def; node.def := def;
		END;
		dsc := dsc.next;
	END;
	IF node.def # NIL THEN
		def := node.def;
		WHILE def.link # NIL DO def := def.link END;
		node.lastdef := def
	END;
	(* end copy DEF nodes to node.def *)
	(* set parameters *)
	dsc := node.dsc;
	WHILE (dsc # node.last) DO
		params := GetNode (dsc, FALSE);
		IF (params # NIL) & (params.id = Params) THEN
			cur := params.dsc;
			WHILE cur # NIL DO
				assign := GetNode (cur, TRUE);
				IF (assign # NIL) & (assign.id = Set) THEN WITH assign : AssignNode DO
					def := node.def;
					WHILE (def # NIL) & (def.name # assign.name) DO def := def.link END;
					IF def # NIL THEN def.dsc := assign.dsc; def.last := assign.last
					ELSE Out.String (assign.name); Out.String (" is no parameter"); Out.Ln END
				END END;
				cur := cur.next
			END
		END;
		dsc := dsc.next
	END;
	(* end set parameters *)
	oldDefinitions := Definitions;
	IF node.def # NIL THEN node.lastdef.link := Definitions; Definitions := node.def END;
	SizeOfTransient (node);
	Definitions := oldDefinitions;
END SizeOfConfig;

PROCEDURE MakeConfig (node : ObjNode; hfill, vfill : INTEGER);		(* node # NIL *)
VAR oldDefinitions : AssignNode;
BEGIN
	IF node.made THEN Reset (node); RETURN END;
	oldDefinitions := Definitions;
	IF node.def # NIL THEN node.lastdef.link := Definitions; Definitions := node.def END;
	MakeTransient (node, hfill, vfill);
	Definitions := oldDefinitions;
END MakeConfig;

PROCEDURE NewObject* (NewProc : ARRAY OF CHAR) : Node;		(**	NEW NewProc	*)
			(**	NewProc = "": virtual object	*)
BEGIN	RETURN NewObj (SizeOfNew, MakeNew, NewProc)
END NewObject;

PROCEDURE NewInstance* (Ident : ARRAY OF CHAR) : Node;		(**	NEW Ident	*)
VAR node : Node;
BEGIN	node := NewIdent (Ident); node.id := Instance; RETURN node
END NewInstance;

PROCEDURE NewPlace* (NewProc : ARRAY OF CHAR) : Node;		(**	PLACE	*)
VAR node : Node;
BEGIN
	node := NewObj (SizeOfPlace, MakePlace, NewProc); node(ObjNode).type := place;
	RETURN node
END NewPlace;

PROCEDURE NewHList* (NewProc : ARRAY OF CHAR) : Node;		(**	HLIST	*)
VAR node : Node;
BEGIN
	node := NewObj (SizeOfTable, MakeTable, NewProc);
	INCL (node(ObjNode).format, vert); node(ObjNode).type := list;
	RETURN node
END NewHList;

PROCEDURE NewVList* (NewProc : ARRAY OF CHAR) : Node;		(**	VLIST	*)
VAR node : Node;
BEGIN
	node := NewObj (SizeOfTable, MakeTable, NewProc); node(ObjNode).type := list;
	RETURN node
END NewVList;

PROCEDURE NewTable* (NewProc : ARRAY OF CHAR) : Node;		(**	TABLE	*)
VAR node : Node;
BEGIN
	node := NewObj (SizeOfTable, MakeTable, NewProc); node(ObjNode).type := table;
	RETURN node
END NewTable;

PROCEDURE NewSpan* (rows, cols : INTEGER) : Node;		(**	SPAN	*)
VAR span : Node;
BEGIN
	IF rows < 1 THEN rows := 1 END; IF cols < 1 THEN cols := 1 END;
	span := NewObj (SizeOfTransient, MakeTransient, "");
	span(ObjNode).spanh := rows; span(ObjNode).spanw := cols;
	RETURN span
END NewSpan;

PROCEDURE NewBreak* () : Node;		(**	BREAK	*)
VAR break : Node;
BEGIN
	break := NewObj (SizeOfTransient, MakeTransient, "");
	break.id := Break;
	RETURN break
END NewBreak;

PROCEDURE NewConfig* () : Node;		(**	CONFIG	*)
BEGIN	RETURN NewObj (SizeOfConfig, MakeConfig, "")
END NewConfig;

PROCEDURE CopyPublicObj* (name : ARRAY OF CHAR; deep : BOOLEAN) : Node;		(**	SCOPY, DCOPY	*)
			(**	if name can't be found, a virtual object is returned	*)
VAR obj : Objects.Object;
		copyMsg : Objects.CopyMsg;
		node : Node;
BEGIN
	node := NewObj (SizeOfNew, MakeNew, ""); node(ObjNode).hFactor := 0; node(ObjNode).vFactor := 0;
	obj := Gadgets.FindPublicObj (name);
	IF obj = NIL THEN Out.String ("Public Object "); Out.String (name); Out.String (" not found"); Out.Ln
	ELSE
		IF deep THEN copyMsg.id := Objects.deep ELSE copyMsg.id := Objects.shallow END;
		copyMsg.dlink := NIL; Objects.Stamp (copyMsg); obj.handle (obj, copyMsg);
		WITH node : ObjNode DO
			node.obj := copyMsg.obj;
			IF node.obj IS Display.Frame THEN
				node.w := node.obj(Display.Frame).W; node.h := node.obj(Display.Frame).H
			END
		END;
	END;
	RETURN node
END CopyPublicObj;

PROCEDURE WrappedObject* (obj : Objects.Object) : Node;
			(**	obj = NIL: make virtual object	*)
VAR node : Node;
BEGIN	node := NewObj (SizeOfNew, MakeNew, ""); node(ObjNode).hFactor := 0; node(ObjNode).vFactor := 0;
	WITH node : ObjNode DO
		node.obj := obj;
		IF (obj # NIL) & (node.obj IS Display.Frame) THEN
			node.x := obj(Display.Frame).X;	node.y := obj(Display.Frame).Y;
			node.w := obj(Display.Frame).W;	node.h := obj(Display.Frame).H
		END
	END;
	RETURN node
END WrappedObject;

END Layouts.

(**
		Create a Node for each operator and each argument except those specified when creating the operator node.
		Arguments are inserted with 'Insert', except for parameter list, which are set with 'SetParams'.
		To get the object from the layout structure, use Realize (node).

		Example for using a configuration and setting parameters:

		VAR container, newconfig, params : Layouts.Node;
		...
			newconfig := Layouts.NewInstance ("TheName"); Layouts.Insert (container, newconfig);
			params := Layouts.NewNode (Layouts.Params); Layouts.SetParams (newconfig, params);
			Layouts.Insert (params, NewSet ("FirstParam", NewString ("Value")));
			Layouts.Insert (params, NewSet ("SecondParam", NewFormat (Layouts.Center)));
		...
*)