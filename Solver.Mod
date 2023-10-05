MODULE Solver;	(** eos   **)

	(**
		Simple constraint solver
	**)
	
	IMPORT
		Objects;
		
	
	CONST
		MaxObjID = 4095;
		
	
	TYPE
		Reference = POINTER TO ReferenceDesc;
		
		Node* = POINTER TO NodeDesc;
		NodeDesc* = RECORD
			link: Node;
			refCount: INTEGER;	(* number of other nodes referencing this node *)
			ref: Reference;	(* first in list of references to other nodes depending on this one *)
		END;
		
		ReferenceDesc = RECORD
			next: Reference;
			node: Node;
		END;
		
		RealNode = POINTER TO RealNodeDesc;
		RealNodeDesc = RECORD (NodeDesc)
			val: REAL;
		END;
		
		AttrNode* = POINTER TO AttrNodeDesc;
		AttrNodeDesc* = RECORD (NodeDesc)
			next*: AttrNode;	(** next attribute of same object **)
			name*: ARRAY 32 OF CHAR;	(** attribute name **)
			val*: REAL;	(** value computed by solver **)
		END;
		
	
	VAR
		NextObjID: INTEGER;
		Obj: POINTER TO ARRAY MaxObjID+1 OF Objects.Object;
		Att: POINTER TO ARRAY MaxObjID+1 OF AttrNode;
		NodeList: Node;
		
	
	(** initialize solver **)
	PROCEDURE Init*;
	BEGIN
		NextObjID := 0; NodeList.link := NodeList;
	END Init;
	
	(** register an object **)
	PROCEDURE RegisterObj* (obj: Objects.Object; VAR id: LONGINT);
	BEGIN
		id := 0;
		WHILE (id < NextObjID) & (obj # Obj[id]) DO INC(id) END;
		IF (id = NextObjID) & (NextObjID <= MaxObjID) THEN
			Obj[id] := obj; Att[id] := NIL;
			INC(NextObjID)
		END
	END RegisterObj;
	
	(** return node for object attribute **)
	PROCEDURE Attr* (id: LONGINT; name: ARRAY OF CHAR): AttrNode;
		VAR attr: AttrNode;
	BEGIN
		IF id < NextObjID THEN
			attr := Att[id];
			WHILE (attr # NIL) & (attr.name # name) DO attr := attr.next END;
			IF attr = NIL THEN
				NEW(attr); COPY(name, attr.name);
				attr.next := Att[id]; Att[id] := attr
			END;
			RETURN attr
		END;
		RETURN NIL
	END Attr;
	
	(** return number node **)
	PROCEDURE Real* (val: REAL): RealNode;
		VAR real: RealNode;
	BEGIN
		NEW(real); real.val := val;
		RETURN real
	END Real;
	
	(** establish an assignment between two nodes **)
	PROCEDURE Assign* (to, val: Node);
		VAR ref: Reference;
	BEGIN
		IF (val # NIL) & (to # NIL) THEN
			NEW(ref); ref.node := to; ref.next := val.ref; val.ref := ref;
			INC(to.refCount);
			IF val.link = NIL THEN
				val.link := NodeList.link; NodeList.link := val
			END
		END
	END Assign;
	
	(** solve equations **)
	PROCEDURE Solve*;
		VAR prev, node, rnode: Node; n: LONGINT; ref: Reference;
	BEGIN
		WHILE NodeList.link # NodeList DO
			prev := NodeList; node := prev.link; n := 0;
			WHILE node # NodeList DO
				IF node.refCount = 0 THEN
					INC(n);
					ref := node.ref;
					WHILE ref # NIL DO
						rnode := ref.node;
						DEC(rnode.refCount);
						IF (node IS RealNode) & (rnode IS AttrNode) THEN
							rnode(AttrNode).val := node(RealNode).val
						END;
						ref := ref.next
					END;
					node := node.link; prev.link := node
				ELSE
					prev := node; node := node.link
				END
			END;
			IF n = 0 THEN	(* need to break cycle *)
				NodeList.link.refCount := 0
			END
		END
	END Solve;
	
	(** return object and its attribute list **)
	PROCEDURE GetObject* (id: LONGINT; VAR obj: Objects.Object; VAR attr: AttrNode);
	BEGIN
		IF id < NextObjID THEN
			obj := Obj[id]; attr := Att[id]
		ELSE
			obj := NIL; attr := NIL
		END
	END GetObject;
	
	(** exchange current with calculated attribute values **)
	PROCEDURE ApplyAttr* (obj: Objects.Object; attr: AttrNode);
		VAR am: Objects.AttrMsg; val: REAL;
	BEGIN
		WHILE attr # NIL DO
			am.id := Objects.get; COPY(attr.name, am.name); am.class := Objects.Real; am.x := attr.val; am.res := -1;
			obj.handle(obj, am);
			val := am.x; am.x := attr.val; attr.val := val;
			am.id := Objects.set; am.class := Objects.Real; am.res := -1;
			obj.handle(obj, am);
			attr := attr.next
		END
	END ApplyAttr;
	

BEGIN
	NEW(NodeList); NodeList.link := NodeList;
	NEW(Obj); NEW(Att)
END Solver.
