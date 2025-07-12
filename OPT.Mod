(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* OPT - Oberon Portable Symbol Table (front end) *)
(* NW, RC, tk, prk *)

MODULE OPT;	(* non-portable *)
	IMPORT SYSTEM, OPS, OPM, Files;

	CONST
		TraceFP = FALSE;
	
		MaxConstLen* = OPS.MaxStrLen; 
		DefMaxImport=64; DefMaxStruct=32; DefMaxReimp=32;
		
		HdPtrName* = "@ptr";
		ObjBody = "@Body";
		Delegate* = "@delegate";
		HdPtrStruct* = "@pointer";

	(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; Mod = 11; Head = 12; TProc = 13; Alias=14;
		Operator = 15;	(* used only in exp, when the list is created *)

	(* structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15; 
		HInt = 16;
		
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;

	(* nodes classes *)
		Nconst = 7; Ncall = 13;
		
	(*function number*)
		haltfn = 0; newfn = 1; absfn = 2; capfn = 3; ordfn = 4;
		entierfn = 5; oddfn = 6; minfn = 7; maxfn = 8; chrfn = 9;
		shortfn = 10; longfn = 11; sizefn = 12; incfn = 13; decfn = 14;
		inclfn = 15; exclfn = 16; lenfn = 17; copyfn = 18; ashfn = 19; assertfn = 32;
		
		awaitfn = 64; lockfn = 66;
		
	(*SYSTEM function number*)
		adrfn = 20; ccfn = 21; lshfn = 22; rotfn = 23;
		getfn = 24; putfn = 25; getrfn = 26; putrfn = 27;
		bitfn = 28; valfn = 29; sysnewfn = 30; movefn = 31;
		stifn = 33; clifn = 34; poutfn = 35; pinfn = 36;
		shalt = 37;
		get8fn = 38; get16fn = 39; get32fn = 40;
		put8fn = 41; put16fn = 42; put32fn = 43;
		typefn = 44;
		
	(* module visibility of objects *)
		internal = 0; external = 1; externalR = 2;

	(* Object flags *)
		hasBody = 1; slNeeded = 3; protectedObj = 4; activeObj = 5; locked =6; guarded = 7; safe = 8;
		asmProc = 7;
		typeVisible* = 8;	(*this type can be used and allocated, because exported (though strobj is not)*)
		
		(*object trace modes*)
		used* = 1; param* = 3;

	(*symbol tags*)
		SFtypBool=01H; SFtypChar=02H; SFtypSInt=03H; SFtypInt=04H; SFtypLInt=05H; SFtypHInt=06H;
		SFtypReal=07H; SFtypLReal=08H; SFtypSet=09H; SFtypString=0AH; SFtypNoTyp=0BH; SFtypNilTyp=0CH;
		SFtypByte=0DH; SFtypptr=0EH;
		SFlastStruct = 0EH;
		SFmod1=0FH; SFmod31=2CH; SFmodOther=2DH;
		SFtypOpenArr=2EH; SFtypDynArr=2FH; SFtypArray=30H; SFtypPointer=31H; SFtypRecord=32H; SFtypProcTyp=33H;
		SFsysflag=34H; SFinvisible=35H; SFreadonly=36H;
		SFobjflag = 37H;	(*duplicate, used only for fields, not element of first(Structure) *)
		SFconst=37H; SFvar=38H;
		SFlproc=39H; SFxproc=3AH; SFoperator=3BH; SFtproc=3CH;
		SFcproc=SFtproc;	(* same tag, always used in different contexts *)
		SFalias=3DH; SFtyp=3EH; SFend=3FH;

	(* history *)
		inserted = 0;	same = 1;	removed = 3;	modified = 4;


	TYPE
		Const* = POINTER TO ConstDesc;
		Object* = POINTER TO ObjDesc;
		Module*=POINTER TO ModDesc;
		Struct* = POINTER TO StrDesc;
		Node* = POINTER TO NodeDesc;
		ConstExt* = POINTER TO OPS.String;

		ConstDesc* = RECORD
			ext*: ConstExt;	(* string or code for code proc *)
			intval*: LONGINT;	(* constant value or adr, proc par size, text position or least case label *)
			intval2*: LONGINT;	(* string length, proc var size or larger case label *)
			setval*: SET;	(* constant value, procedure body present or "ELSE" present in case *)
			realval*: LONGREAL	(* real or longreal constant value *)
		END;

		ObjDesc* = RECORD
			left*, right*, link*, scope*: Object;
			myscope*: Object;
			link2*, old: Object;		(* <- old used symbol file comparison *)
			prio*, sysflag*: SHORTINT;
			code*: Node;
			name*: OPS.Name;
			leaf*: BOOLEAN;
			mode*, mnolev*: SHORTINT;	(* mnolev < 0 -> mno = -mnolev *)
			vis*: SHORTINT;	(* 0: internal; 1: external; 2: externalR *)
			typ*: Struct;
			conval*: Const;
			adr*, linkadr*: LONGINT;
			nxtobj*, sibling*: Object; par: BOOLEAN; inited*, used*: BOOLEAN; fp*: LONGINT; history*: SHORTINT;
			txtpos*: LONGINT;
			flag*: SET;
		END ;

(*
  mode   link
------------------------------------------------------------------------
  Head   owner (procedures)
         owner (records, may be anonymous)
         NIL (modules)
         NIL (proctypes)
         
*)

		StructArr=POINTER TO ARRAY OF Struct;
		ModArr=POINTER TO ARRAY OF Module;
		ModDesc*=RECORD (ObjDesc)
			publics*: Object; directImp*: BOOLEAN;
			nofimp: INTEGER; import: ModArr;
			nofstr: INTEGER; struct: StructArr;
			nofreimp: INTEGER; reimp: StructArr;
		END;

		StrDesc* = RECORD
			form*, comp*, mno*, extlev*: SHORTINT;
			ref*: INTEGER;  align*, sysflag*: SHORTINT;
			rectest*, n*, size*, tdadr*, offset*, txtpos*, txtpos2*: LONGINT;
			BaseTyp*: Struct;
			link*, strobj*: Object; fpdone*, sref*, oref*: INTEGER;
			pvused*, pbused*: BOOLEAN; fp*, pvfp*, pbfp*: LONGINT;
			incomplete*: BOOLEAN;	(* structure not checked for consistency *)
			ptr*: Struct;
		END ;
		
		NodeDesc* = RECORD
			left*, right*, link*: Node;
			class*, subcl*: SHORTINT;
			readonly*: BOOLEAN;
			typ*: Struct;
			obj*: Object;
			conval*: Const;
			global*: BOOLEAN; up*, down*: Node; ref*: LONGINT; flag*, subflg*: SHORTINT	(*Backend*)
		END ;
		
	VAR
		topScope*, objects*: Object;
		undftyp*, bytetyp*, booltyp*, chartyp*, sinttyp*, inttyp*, linttyp*, hinttyp*,
		realtyp*, lrltyp*, settyp*, stringtyp*, niltyp*, notyp*, ptrtyp*: Struct;

		SYSimported*: BOOLEAN;
		nofmod*: SHORTINT; modules*: ModArr;	(*global for each module being compiled*)
		nofemod: SHORTINT; emodules: ModArr; modNo*: INTEGER;	(*global for each module being compiled*)
		universe, syslink: Object;
		
		strucForm: ARRAY SFtypProcTyp+1 OF SHORTINT;	(*forms of structures*)
		strucComp: ARRAY SFtypProcTyp+1 OF SHORTINT;	(*forms of structures*)
		predefStruct: ARRAY SFlastStruct+1 OF Struct;	(*predefined types*)
		strucFormSF: ARRAY Comp+1 OF SHORTINT;	(*forms of structures*)
		strucCompSF: ARRAY Comp+1 OF SHORTINT;	(*forms of structures*)

		export: BOOLEAN; exp: ARRAY Operator+1 OF Object; nofstruc: INTEGER;
		newSF, extSF, symNew, symExtended, sfpresent, impSelf, expGlobal: BOOLEAN;
		typSize*: PROCEDURE (typ: Struct; allocDesc: BOOLEAN);
		ToBeFixed*: Struct;

	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;
	
	PROCEDURE Close*;	(* garbage collection *)
		VAR i: INTEGER;
	BEGIN	topScope:=NIL; objects:=NIL; 
		i:=0; WHILE i<LEN(modules^) DO modules[i]:=NIL; INC(i) END;
		i:=0; WHILE i<LEN(emodules^) DO emodules[i]:=NIL; INC(i) END;
		i:=0; WHILE i<Alias+1 DO exp[i]:=NIL; INC(i) END;
		nofmod:=0; nofemod:=0;
	END Close;
	
	PROCEDURE NewMod(): Module;
		VAR M: Module;
	BEGIN
		NEW(M); 
		NEW(M.struct, DefMaxStruct); 
		NEW(M.reimp, DefMaxReimp);
		NEW(M.import, DefMaxImport);
		RETURN M
	END NewMod;

	PROCEDURE NewConst*(): Const;
		VAR const: Const;
	BEGIN NEW(const);  RETURN const
	END NewConst;
	
	PROCEDURE NewObj*(): Object;
		VAR obj: Object;
	BEGIN NEW(obj);  obj.txtpos := OPM.errpos;  RETURN obj
	END NewObj;
	
	PROCEDURE NewStr*(form, comp: SHORTINT): Struct;
		VAR typ: Struct;
	BEGIN NEW(typ); typ.form := form; typ.comp := comp;
		typ.tdadr := OPM.TDAdrUndef; typ.offset := OPM.TDAdrUndef;
		typ.txtpos := OPM.errpos; typ.size := -1; typ.BaseTyp := undftyp; RETURN typ
	END NewStr;
	
	PROCEDURE NewNode*(class: SHORTINT): Node;
		VAR node: Node;
	BEGIN	NEW(node); node.class := class; RETURN node
	END NewNode;
	
	PROCEDURE NewExt*(): ConstExt;
		VAR ext: ConstExt;
	BEGIN	NEW(ext); RETURN ext
	END NewExt;

	PROCEDURE DoubleStructArr(VAR x: StructArr);
		VAR i, n: LONGINT; h: StructArr;
	BEGIN
		i := LEN(x^); h := x; NEW(x, 2*i);
		ASSERT(x # NIL);
		FOR n := 0 TO i - 1 DO
  		x[n] := h[n]
  	END
	END DoubleStructArr;

	PROCEDURE DoubleModArr(VAR x: ModArr);
		VAR i, j: LONGINT; h: ModArr;
	BEGIN
		i := LEN(x^); h := x; NEW(x, 2*i);
		ASSERT(x # NIL);
		FOR j := 0 TO i - 1 DO
  		x[j] := h[j];
  	END
	END DoubleModArr;

	PROCEDURE MarkObj*(obj: Object);
	BEGIN
		IF obj#NIL THEN obj.used:=TRUE;
			IF obj.mnolev<0 THEN modules[-obj.mnolev].used:=TRUE END;
		END;
	END MarkObj;

	PROCEDURE MarkType*(typ: Struct);
	BEGIN typ.pvused:=TRUE; MarkObj(typ.strobj);
	END MarkType;

	PROCEDURE TraverseObjects*(top: Object);
	VAR flag: SET;  type: Struct;
	BEGIN
		IF top # NIL THEN
			TraverseObjects(top.left);
			IF (top.mode IN {Var, VarPar, Fld, Con, Typ, LProc, TProc, CProc, Mod}) & (top.vis = internal) & (top.name # "@SELF") THEN
				flag := top.flag * {used, param};
				IF (flag = {param}) THEN	OPM.Mark(-913, top.txtpos)
				ELSIF (flag = {}) THEN	OPM.Mark(-900, top.txtpos)
				END
			END;
			IF (top.mode IN{LProc, XProc, TProc}) THEN TraverseObjects(top.scope.right) END;
			type := top.typ;
			WHILE (type.form = Pointer) OR (type.comp = StaticArr) DO type := type.BaseTyp  END;
			IF (type.comp = Record) & (type.mno = 0) & (type.rectest # MAX(LONGINT)) THEN
				type.rectest := MAX(LONGINT);		(*avoid double checking*)
				TraverseObjects(type.link)
			END;
			TraverseObjects(top.right);
		END;
	END TraverseObjects;
	
	PROCEDURE FindImport*(mod: Object; VAR res: Object);
		VAR obj: Object;
	BEGIN obj := mod^.scope;
		LOOP
			IF obj = NIL THEN EXIT END ;
			IF OPS.name < obj^.name THEN obj := obj^.left
			ELSIF OPS.name > obj^.name THEN obj := obj^.right
			ELSE (*found*)
				IF (obj^.mode = Typ) & (obj^.vis = internal) THEN obj := NIL 
				ELSE MarkObj(obj) END ;
				EXIT
			END
		END ;
		res := obj
	END FindImport;

	PROCEDURE FindField*(IN name: ARRAY OF CHAR; typ: Struct; VAR res: Object; mark: BOOLEAN);
		VAR obj: Object;
	BEGIN res:=NIL;
		WHILE ((typ # NIL) & (typ # ToBeFixed) & (typ # undftyp)) & (res=NIL) DO obj := typ^.link;
			WHILE obj # NIL DO
				IF name < obj^.name THEN obj := obj^.left
				ELSIF name > obj^.name THEN obj := obj^.right
				ELSE (*found*)
					INCL(obj.flag, used);
					res := obj; obj:=NIL
				END
			END ;
			IF (res # NIL) & (res.mode = TProc) & (res.mnolev <0) & (res.vis = internal) THEN res := NIL END;
			IF res=NIL THEN
				IF (typ.BaseTyp#NIL) & (typ.BaseTyp#ToBeFixed) & (typ.BaseTyp.strobj.vis=internal) & mark THEN MarkObj(typ.strobj) END;	(* mfix *)
				typ := typ^.BaseTyp
			END
		END ;
		IF res = NIL THEN RETURN END;
		IF mark THEN res.used:=TRUE; MarkObj(typ.strobj); typ.pbused:=TRUE END	(* mfix *)
	END FindField;
	
	PROCEDURE FindInScope*(IN name: ARRAY OF CHAR; scope: Object; VAR res: Object);
		VAR obj, head: Object; inRec: BOOLEAN;
	BEGIN
		head := scope; inRec := FALSE;
		LOOP 
			IF (head.link#NIL)&(head.link.mode=Typ) THEN	(*inside a record*)
				FindField(name, head.link.typ, obj, TRUE);
				IF inRec & (obj # NIL) & ~(obj.mode IN {Typ, Con}) THEN  err(200)  END;	(*a record inside a record, cannot access its fields/methods*)
				inRec := TRUE;
				IF (obj # NIL) OR head.link.typ.incomplete THEN  EXIT  END ;
			ELSE
				obj := head^.right;
				LOOP
					IF obj = NIL THEN EXIT END ;
					IF name < obj^.name THEN obj := obj^.left
					ELSIF name > obj^.name THEN obj := obj^.right
					ELSE (*found*)
						IF inRec & (head.link # NIL) & (head.link.mode # Mod) & ~(obj.mode IN {Typ, Con}) THEN err(200) END;	(*record accesses proc vars: illegal*)
						INCL(obj.flag, used);
						EXIT
					END
				END ;
				IF obj # NIL THEN EXIT END;
			END;
			head := head^.left;
			IF head = NIL THEN EXIT END
		END ;
		IF (obj # NIL) & (obj.mode < 0) THEN obj := NIL END;
		res := obj;
	END FindInScope;

	PROCEDURE Find*(VAR res: Object);
	BEGIN	FindInScope (OPS.name, topScope, res)
	END Find;

	PROCEDURE Insert*(IN name: ARRAY OF CHAR; VAR obj: Object);
		VAR ob0, ob1: Object; left: BOOLEAN;
	BEGIN ob0 := topScope; ob1 := ob0.right; left := FALSE;
		LOOP
			IF ob1 # NIL THEN
				IF name < ob1.name THEN ob0 := ob1; ob1 := ob0.left; left := TRUE
				ELSIF name > ob1.name THEN ob0 := ob1; ob1 := ob0.right; left := FALSE
				ELSE
					IF (ob1.prio<126) THEN 	(* not an Operator: obj already exists and not unique*)
						(*double def*) err(1); ob0 := ob1; ob1 := ob0^.right
					ELSE
						EXIT
					END
				END
			ELSE (*insert*) ob1:=NewObj(); ob1.leaf := TRUE;
				IF left THEN ob0.left := ob1 ELSE ob0.right := ob1 END;
				ob1.left:=NIL; ob1.right:=NIL; ob1.name := name;
				ob1.mnolev := topScope.mnolev; EXIT
			END
		END; obj := ob1
	END Insert;

	PROCEDURE CopyOp(VAR new, obj: Object);
	BEGIN
		new.link:=obj.link; new.scope:=obj.scope; new.prio:=obj.prio;
		new.code:=obj.code; new.name:=obj.name; new.leaf:=obj.leaf;
		new.mode:=obj.mode; new.mnolev:=obj.mnolev; new.vis:=obj.vis;
		new.typ:=obj.typ; new.conval:=obj.conval;
	END CopyOp;
	
	PROCEDURE IsExtern(obj: Object): BOOLEAN;
		VAR res: Object;
	BEGIN
		IF obj.typ.strobj # NIL THEN 
			FindInScope(obj.typ.strobj.name, topScope, res);
			FindInScope(obj.typ.strobj.name, universe, obj)
		END;
		RETURN (res # NIL) & (res = obj)
		(*RETURN (res=NIL) OR (obj#NIL);*)
	END IsExtern;

	(* search forward declarations with same operands types, link same types, test cardinality *)
	PROCEDURE Contextualize*(VAR sentinel: Object);
		VAR new, t1, t2, aop, fp, scope: Object;

		PROCEDURE eqptyp( t1, t2 : Struct ) : BOOLEAN;
		BEGIN
			IF t1 = t2 THEN
				RETURN TRUE;
			ELSIF ( t1^.comp = DynArr ) (*& t1^.open*) & ( t2^.comp = DynArr ) (*& t2^.open*) THEN
				WHILE ( t1^.comp = DynArr ) & ( t2^.comp = DynArr ) DO
					t1 := t1^.BaseTyp;
					t2 := t2^.BaseTyp;
				END;
				RETURN t1 = t2;
			ELSE
				RETURN FALSE;
			END;
		END eqptyp;
		
	BEGIN new:=NewObj();
		t1:=sentinel.link;
		IF t1=NIL THEN err(143)	(* Cardinality Check *)
		ELSE
			t2:=t1.link;
			IF (t2=NIL) & ~OPS.CheckCardinality(sentinel.name, 1) THEN err(143)
			ELSIF (t2#NIL) THEN
				IF ~OPS.CheckCardinality(sentinel.name, 2) OR (t2.link#NIL) THEN err(143)
				ELSIF IsExtern(t1)&IsExtern(t2) THEN err(146)
				END
			ELSIF IsExtern(t1) THEN err(146)
			END
		END;
		aop:=sentinel.link2; scope:=sentinel.scope.left;
		WHILE (scope#NIL)& (scope.mnolev>=0) DO
			WHILE aop#NIL DO	(* go along operator list *)
				fp:=aop.link;	
				IF eqptyp( t1^.typ, fp^.typ ) THEN
					IF (t2#NIL) & (fp.link#NIL) & eqptyp( t2^.typ, fp^.link^.typ ) THEN
						err(139)	(* multiply defined binary operator *)
					ELSIF (t2=NIL) & (fp.link=NIL) THEN
						err(139)	(* multiply defined unary operator *)
					END
				END;
				aop:=aop^.left
			END;
			scope:=scope.left;
			IF scope#NIL THEN
				FindInScope(sentinel.name, scope, aop);
				IF aop#NIL THEN aop:=aop.link2 END
			END
		END;
		CopyOp(new, sentinel);
		new.left:=sentinel.link2; sentinel.link2:=new; sentinel.prio:=127; sentinel:=new
	END Contextualize;
	
	PROCEDURE Distance(typ, otyp: Struct; VAR distance: SHORTINT);
		VAR t: Struct;
	BEGIN distance:=MAX(SHORTINT);
		IF (typ.form=Pointer)&(otyp.comp IN {StaticArr, OpenArr, SDynArr, DynArr}) THEN typ:=typ.BaseTyp END;
		IF typ=otyp THEN distance:=0
		ELSIF typ=sinttyp THEN
			IF otyp=inttyp THEN distance:=1 ELSIF otyp=linttyp THEN distance:=2
			ELSIF otyp=realtyp THEN distance:=3 ELSIF otyp=lrltyp THEN distance:=4
			END
		ELSIF typ=inttyp THEN
			IF otyp=linttyp THEN distance:=1
			ELSIF otyp=realtyp THEN distance:=2 ELSIF otyp=lrltyp THEN distance:=3
			END
		ELSIF typ=linttyp THEN
			IF otyp=realtyp THEN distance:=1 ELSIF otyp=lrltyp THEN distance:=2 END
		ELSIF typ=realtyp THEN
			IF otyp=lrltyp THEN distance:=1 END
		ELSIF (typ.comp=otyp.comp) & (typ.comp=Record) THEN
			t:=typ;
			WHILE (t#otyp) & (t#undftyp) & (t#NIL) DO t:=t.BaseTyp END;
			IF t=otyp THEN distance:=typ.extlev-otyp.extlev END
		ELSIF (typ.form=String) & (otyp.comp=OpenArr) & (otyp.BaseTyp.form=Char) THEN
			distance:=1
		ELSIF (typ.comp IN {StaticArr, OpenArr, SDynArr, DynArr}) & (otyp.comp=OpenArr) THEN
			WHILE otyp.comp=OpenArr DO otyp:=otyp.BaseTyp; typ:=typ.BaseTyp END;
			IF typ=otyp THEN distance:=1
			ELSIF (typ.form=Pointer) & (otyp.form=Pointer) THEN Distance(typ.BaseTyp, otyp.BaseTyp, distance)
			END
		ELSIF (typ.form=Pointer)&(otyp.form=Pointer) THEN
			typ:=typ.BaseTyp; otyp:=otyp.BaseTyp;
			IF (typ.comp = Record) & (otyp.comp = Record) THEN t:=typ;
				WHILE (t#otyp) & (t#NIL) & (t#undftyp) DO t:= t.BaseTyp END ;
				IF t=otyp THEN distance:=typ.extlev-otyp.extlev END
			END
		END
	END Distance;
	
	PROCEDURE QualResolve*(VAR obj: Object; VAR x, y: Node; VAR distance: SHORTINT; VAR wrn: BOOLEAN);
		VAR op, yp: Object; d1, d2: SHORTINT;
		PROCEDURE CheckVarPar(act: Node; form: Object): BOOLEAN;
		BEGIN
			RETURN (form.mode # VarPar) OR (act.class < Nconst) OR (act.class = Ncall)	(*allow VAR for temporary values*)
		END CheckVarPar;
		
	BEGIN
		op:=obj.link2; obj:=NIL; distance:=MAX(SHORTINT);
		WHILE op#NIL DO
			IF CheckVarPar(x, op.link) THEN
				Distance(x.typ, op.link.typ, d1);
				IF d1#MAX(SHORTINT) THEN yp:=op.link.link;
					IF y#NIL THEN
						IF yp#NIL THEN
							IF CheckVarPar(y, yp) THEN
								Distance(y.typ, yp.typ, d2);
								IF d2<MAX(SHORTINT) THEN
									d1:=d1+d2;
									IF d1<distance THEN distance:=d1; obj:=op; wrn:=FALSE
									ELSIF d1=distance THEN wrn:=TRUE
									END
								END
							END
						END
					ELSIF (yp=NIL) THEN
						IF d1<distance THEN distance:=d1; obj:=op; wrn:=FALSE
						ELSIF d1=distance THEN wrn:=TRUE
						END
					END
				END
			END;
			op:=op.left
		END
	END QualResolve;
	
	PROCEDURE Resolve*(IN name: ARRAY OF CHAR; VAR x, y: Node): Object;
		VAR op, res, scope: Object; i, d, distance: SHORTINT; wrn, warning: BOOLEAN;
	BEGIN res:=NIL; i:=0; distance:=MAX(SHORTINT); scope:=topScope; wrn:=FALSE; warning:=FALSE;
		WHILE scope#NIL DO
			FindInScope(name, scope, op);
			IF (op#NIL) & (op.scope#NIL) THEN
				scope:=op.scope.left.left;
				QualResolve(op, x, y, d, wrn);
				IF d<distance THEN res:=op; distance:=d; warning:=wrn
				ELSIF d=distance THEN
					IF d=0 THEN HALT(99)	(* BUG *)
					ELSIF d<MAX(SHORTINT) THEN warning:=TRUE
					END
				END
			ELSE scope:=NIL
			END
		END;
		i := 1;
		WHILE (i<nofmod) DO
			FindInScope(name, modules[i], op);
			IF op#NIL THEN
				QualResolve(op, x, y, d, wrn);	(* op=NIL => no op found; op#NIL => distance  *)
				IF d<distance THEN res:=op; distance:=d; warning:=wrn
				ELSIF d=distance THEN
					IF d=0 THEN HALT(99)	(* BUG *)
					ELSIF d<MAX(SHORTINT) THEN warning:=TRUE
					END
				END
			END;
			INC(i)
		END;
		IF warning THEN err(-310) END;	(* ambiguous operator *)
		RETURN res
	END Resolve;

	PROCEDURE OpenScope*(level: SHORTINT; owner: Object);
		VAR head: Object;
	BEGIN
		head:=NewObj();
		head.mode := Head; head.mnolev := level; head.link := owner;
		IF owner # NIL THEN owner.scope := head END;
		head.left := topScope; head.right:=NIL; head.scope:=NIL; topScope := head
	END OpenScope;

	PROCEDURE CloseScope*;
	BEGIN 
		IF topScope # NIL THEN topScope := topScope.left END
	END CloseScope;

	PROCEDURE Init*(VAR name: OPS.Name);
	BEGIN topScope := universe; OpenScope(0, NIL); nofmod := 1; SYSimported := FALSE; impSelf:=FALSE;
		sfpresent:=TRUE;
		newSF := (OPM.newsf IN OPM.options); extSF := newSF OR (OPM.extsf IN OPM.options);
		modules[0]:=NewMod(); 
		modules[0](Object)^ := topScope^;
		modules[0].name:=name;
		topScope:=modules[0]; 
	END Init;

	(* ----- Fingerprinting ----- *)

	PROCEDURE FPrintName(VAR fp: LONGINT; VAR name: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR; 
	BEGIN i:=0; REPEAT ch:=name[i]; OPM.FPrint(fp, ORD(ch)); INC(i) UNTIL ch=0X
	END FPrintName;

	PROCEDURE FPrintSign(VAR fp: LONGINT; result: Struct; par: Object);
	BEGIN 
		FPrintTyp0(result); OPM.FPrint(fp, result.fp);
		WHILE par#NIL DO
			OPM.FPrint(fp, par.mode); 
			IF par.typ # NIL THEN FPrintTyp0(par.typ); OPM.FPrint(fp, par.typ.fp) END;
			par:=par.link;
		END;
	END FPrintSign;

	PROCEDURE FPrintMeth(VAR pbfp, pvfp: LONGINT; fld: Object);
		VAR fp: LONGINT;
	BEGIN
		IF fld#NIL THEN FPrintMeth(pbfp, pvfp, fld.left);
			IF (fld.mode=TProc) & (fld.vis#internal) THEN 
				fp:=0; OPM.FPrint(fp, TProc); FPrintName(fp, fld.name); FPrintSign(fp, fld.typ, fld.link);
				IF fld = fld.link.typ.strobj.link2 THEN OPM.FPrint (fp, -1) END;
				fld.fp:=fp;	(* mfix *)
				OPM.FPrint(fp, fld.adr DIV 10000H); OPM.FPrint(pbfp, fp); OPM.FPrint(pvfp, fp);
			END;
			FPrintMeth(pbfp, pvfp, fld.right);
		END;
	END FPrintMeth;

	PROCEDURE FPrintRecord(typ: Struct);
		VAR fld: Object; fp, pbfp, pvfp: LONGINT;
	BEGIN 
		pvfp:=typ.fp; pbfp:=typ.fp; 
		IF typ.BaseTyp#NIL THEN OPM.FPrint(pvfp, typ.BaseTyp.pvfp);
			OPM.FPrint(pbfp, typ.BaseTyp.pbfp);
		END; 
		IF typ.size<0 THEN typSize(typ, FALSE) END;
		fld:=typ.link; 
		FPrintMeth(pbfp, pvfp, fld);
		WHILE (fld#NIL) & (fld.mode=Fld) DO
			FPrintTyp(fld.typ); 
			IF fld.vis#internal THEN fp:=0; OPM.FPrint(fp, fld.mode);
				FPrintName(fp, fld.name); OPM.FPrint(fp, fld.vis); 
				IF fld.sysflag # 0 THEN  OPM.FPrint(fp, fld.sysflag)  END;
				OPM.FPrint(fp, fld.typ.fp); fld.fp:=fp;
				OPM.FPrint(pbfp, fld.typ.pbfp); OPM.FPrint(pbfp, fld.adr); 
				OPM.FPrint(pvfp, fld.typ.pvfp);  OPM.FPrint(pvfp, fld.adr); 
				OPM.FPrint(pvfp, fp); OPM.FPrint(pbfp, fp);
				fld:=fld.link;
			ELSE 
				fp := 0;
				IF fld.sysflag # 0 THEN  OPM.FPrint(fp, fld.sysflag)  END;
				fld.fp := fp;
				OPM.FPrint(pvfp, fld.fp); fld:=fld.link;
			END;
		END;
		OPM.FPrintSet (pbfp, typ.strobj.conval.setval * {protectedObj, hasBody, activeObj} );
		typ.pbfp := pbfp; typ.pvfp := pvfp;	(* replace typ.pbfp with pbfp and typ.pvfp with pvfp *)
	END FPrintRecord;

	PROCEDURE FPrintTyp0(typ: Struct);
	(* calculate fingerprint without looking at record fields, private and public fingerprints *)
		VAR fp, fp1, fp2: LONGINT; f, c: SHORTINT; btyp: Struct;
	BEGIN 
		IF (typ # NIL) & (typ.fpdone>=0) THEN (* not a built in type *)
			fp:=0; f:=typ.form; c:=typ.comp; OPM.FPrint(fp, f); OPM.FPrint(fp, c); 
			fp1 := fp;
			IF typ.sysflag#0 THEN OPM.FPrint(fp, typ.sysflag) END; 
			IF typ.mno#modNo THEN FPrintName(fp, modules[typ.mno].name); FPrintName(fp, typ.strobj.name);
			END;
			fp2 := fp;
			btyp:=typ.BaseTyp; typ.fp:=fp;
			IF (c=Record) & (btyp#NIL) OR (f=Pointer) THEN FPrintTyp0(btyp); OPM.FPrint(typ.fp, btyp.fp);
			ELSIF c IN {StaticArr, SDynArr, DynArr, OpenArr} THEN FPrintTyp0(btyp); OPM.FPrint(typ.fp, btyp.fp);
				IF c=StaticArr THEN OPM.FPrint(typ.fp, typ.n) END; typ.pbfp:=typ.fp; typ.pvfp:=typ.fp;
			ELSIF f=ProcTyp THEN FPrintSign(typ.fp, btyp, typ.link); typ.pbfp:=typ.fp; typ.pvfp:=typ.fp;
			ELSIF (f=Pointer) THEN OPM.FPrint (typ.fp, 1)
			END;
			IF TraceFP THEN
				OPM.LogWLn; OPM.LogWStr("FPTyp0 - ");
				OPM.LogWHex(fp1); OPM.LogWHex(fp2); OPM.LogWHex(typ.fp);
				IF typ.strobj # NIL THEN OPM.LogWStr(" - "); OPM.LogWStr(typ.strobj.name) END
			END
		END;
	END FPrintTyp0;

	PROCEDURE FPrintTyp*(typ: Struct);	
	(* fpdone  0: not done yet  >0: done for module fpdone-1  =-1: built in type *)
	BEGIN 
		IF (typ # NIL) & (typ.fpdone#modNo+1) & (typ.fpdone>=0) THEN	
			FPrintTyp0(typ);
			IF (typ.comp # Record) THEN typ.fpdone:=modNo+1 END;
			IF typ.BaseTyp#NIL THEN FPrintTyp(typ.BaseTyp) END;
			IF (typ.comp=Record) THEN FPrintRecord(typ) END;
			typ.fpdone:=modNo+1;
			IF TraceFP THEN
				OPM.LogWLn; OPM.LogWStr("FPTyp  - ");
				OPM.LogWHex(typ.fp); OPM.LogWHex(typ.pbfp); OPM.LogWHex(typ.pvfp);
				IF typ.strobj # NIL THEN OPM.LogWStr(" - "); OPM.LogWStr(typ.strobj.name) END
			END
		END;
	END FPrintTyp;

	PROCEDURE FPrintObj*(obj: Object);
		VAR fp, fp1: LONGINT; rval: REAL; f, m: INTEGER; ext: ConstExt;  n: Node;
	BEGIN 
		fp:=0; 
		OPM.FPrint(fp, obj.mode); FPrintName(fp, obj.name); OPM.FPrint(fp, obj.vis);
		IF TraceFP THEN fp1 := fp END;
		IF obj.mode=Con THEN
			f:=obj.typ.form; OPM.FPrint(fp, f); OPM.FPrint(fp, obj.typ.comp);
			CASE f OF
			| Bool, Char, SInt, Int, LInt: OPM.FPrint(fp, obj.conval.intval);
			| Set: OPM.FPrintSet(fp, obj.conval.setval);
			| Real: rval:=SHORT(obj.conval.realval); OPM.FPrintReal(fp, rval);
			| LReal: OPM.FPrintLReal(fp, obj.conval.realval);
			| String: FPrintName(fp, obj.conval.ext^);
			| NilTyp:
			END
		ELSIF obj.mode=Var THEN FPrintTyp(obj.typ); OPM.FPrint(fp, obj.typ.fp);
		ELSIF obj.mode=XProc THEN  FPrintSign(fp, obj.typ, obj.link); 
			IF  obj.sysflag # 0  THEN  OPM.FPrint(fp, obj.sysflag)  END
		ELSIF obj.mode=CProc THEN
			FPrintSign(fp, obj.typ, obj.link);
			n := obj.code.left;
			WHILE n # NIL DO
				ext := n.conval.ext;  m := ORD(ext[0]);
				f := 1; OPM.FPrint(fp, m);
				WHILE  f<=m DO  OPM.FPrint(fp, ORD(ext[f])); INC(f)  END;
				n := n.link
			END;
			(*ext:=obj.conval.ext;
			m:=ORD(ext^[0]); f:=1; OPM.FPrint(fp, m);
			WHILE f<=m DO OPM.FPrint(fp, ORD(ext^[f])); INC(f) END*)
		ELSIF obj.mode=Typ THEN FPrintTyp(obj.typ); OPM.FPrint(fp, obj.typ.fp);
		END;
		obj.fp:=fp;
		IF TraceFP THEN
			OPM.LogWLn; OPM.LogWStr("FPObj  - ");
			OPM.LogWHex(fp1); OPM.LogWHex(fp);
			OPM.LogWStr(" - "); OPM.LogWStr(obj.name)
		END;
	END FPrintObj;
		
	PROCEDURE FPrintErr(obj: Object);
		VAR errNo: INTEGER;
	BEGIN 
		IF	expGlobal	THEN
			IF	obj.history=removed	THEN	errNo:=450
			ELSIF	obj.history=inserted	THEN	errNo:=451
			ELSIF	obj.history=modified	THEN	errNo:=452
			ELSE	RETURN
			END;
			OPM.errName := obj.name;
			IF errNo=451 THEN (* inserted *)
				IF (* ~symNew & ~symExtended & *) ~extSF THEN err(errNo) END;
				symExtended:=TRUE;
			ELSE
				IF (* ~symNew & *) ~newSF THEN err(errNo) END;
				symNew:=TRUE;
			END;
			IF errNo=450 THEN obj.vis:=internal END;
		END
	END FPrintErr;			

(* Import *)
	PROCEDURE MatchOp (op, list: Object): Object;
	BEGIN
		FPrintObj (op);
		list := list.link2;
		WHILE (list # NIL) & (list.old=NIL) DO		(* (list.old#NIL) only for imported elements *)
			IF list.fp = 0 THEN FPrintObj (list) END;
			IF op.fp = list.fp THEN RETURN list END;
			list := list.left
		END;
		RETURN NIL
	END MatchOp;

	PROCEDURE InsertImport(obj: Object; root: Object);
		VAR ob0, ob1: Object; left: BOOLEAN;	(* old in obj.scope *)
	BEGIN	ob0:=root; ob1:=ob0.right; left:=FALSE;
		LOOP
			IF	ob1#NIL	THEN
				IF	obj.name < ob1.name	THEN	ob0:=ob1; ob1:=ob1.left; left:=TRUE
				ELSIF	obj.name > ob1.name	THEN	ob0:=ob1; ob1:=ob1.right; left:=FALSE
				ELSIF	obj.name=""	THEN	obj.scope:=NIL; RETURN
				ELSE	obj.old:=ob1;			(* operators, link to the sentinel. Search not possible because parm aren't read yet! *)
					IF (ob1.prio = 127) & (root.mnolev # 0) THEN	(* append to list, if really imported; 0 is self used for sf check *)
						obj.right := NIL; obj.left := ob1.link2; ob1.link2 := obj;
						obj.mnolev := root.mnolev
					END;
					EXIT
				END
			ELSE
				IF obj.prio=126 THEN	(*Insert first a sentinel *)
					obj.left := NIL;
					ob1 := obj; obj := NewObj(); CopyOp (obj, ob1);
					obj.prio := 127; obj.link2 := ob1;
					ob1.old := NIL; ob1.mnolev := root.mnolev
				END;
				IF	left	THEN	ob0.left:=obj	ELSE	ob0.right:=obj	END;
				obj.left:=NIL; obj.right:=NIL; obj.old:=NIL;
				obj.mnolev:=root.mnolev; 
				RETURN
			END
		END
	END InsertImport;

	PROCEDURE CompOldTyp(typ, oldtyp: Struct): SHORTINT;
	BEGIN
		IF (typ.form=Comp) & (typ.comp#Record) OR (typ.form=Pointer) THEN
			RETURN CompOldTyp(typ.BaseTyp, oldtyp.BaseTyp)
		ELSIF (typ.form=Comp) & (typ.comp=Record) THEN
			IF (typ.pvfp#oldtyp.pvfp) OR (typ.pbfp#oldtyp.pbfp) THEN RETURN modified
			ELSE RETURN same
			END
		ELSE RETURN same END
	END CompOldTyp;

	PROCEDURE CompOldSym(obj: Object);
		VAR old: Object; 
	BEGIN
		WHILE obj#NIL DO old:=obj.old;
			IF (old#NIL)&(old.prio = 127) THEN old := MatchOp (obj, old); obj.old := old END;
			IF old#NIL THEN
				IF obj.prio#126 THEN	 
					FPrintObj(obj); FPrintObj(old)
				END;
				IF obj.fp#old.fp THEN
					IF	(obj.vis#old.vis) & (old.vis=internal)	THEN	obj.history:=removed; FPrintErr(obj)	
					ELSE	old.history:=modified	END
				ELSIF (obj.mode=Typ) OR (obj.typ.form=Comp) & (obj.typ.comp=Record) & (obj.typ.strobj.name="") THEN old.history:=CompOldTyp(obj.typ, old.typ); 
				ELSE old.history:=same END
			ELSE obj.history:=removed END;
			obj:=obj.nxtobj;
		END 
	END CompOldSym;

	(* ----- read sym file ----- *)

	PROCEDURE ReadString(VAR R: Files.Rider; VAR string: ARRAY OF CHAR);
		VAR i: INTEGER; ch: CHAR;
	BEGIN i := 0;
		LOOP Files.ReadChar(R, ch);
			IF ch = 0X THEN string[i] := 0X; RETURN
			ELSIF ch < 7FX THEN string[i]:=ch; INC(i)
			ELSIF ch > 7FX THEN string[i] := CHR(ORD(ch)-80H); string[i+1] := 0X; RETURN
			ELSE (* ch = 7FX *) EXIT END
		END;
		LOOP Files.ReadChar(R, ch);
			IF ch = 0X THEN string[i]:=0X; RETURN
			ELSE string[i]:=ch; INC(i) END
		END
	END ReadString;

	PROCEDURE Imp(VAR impName, modName: OPS.Name; VAR M: Module);
		VAR R: Files.Rider; i: INTEGER; tag: LONGINT; done: BOOLEAN; mode: SHORTINT; obj, last: Object; tdum: Struct;
			new, operator: BOOLEAN;
			
		PROCEDURE^InStruct(VAR typ: Struct; par: BOOLEAN);

		PROCEDURE GetImports;
			VAR name: OPS.Name; TM: Module;
		BEGIN	ReadString(R, name);
			WHILE	name#""	DO	Imp(name, modName, TM);
				M.import[M.nofimp]:=TM; INC(M.nofimp); IF M.nofimp>=LEN(M.import^) THEN DoubleModArr(M.import) END;
				M.nofreimp:=0; ReadString(R, name)
			END
		END GetImports;

		PROCEDURE InParList(VAR first: Object);
			VAR last, par: Object;
		BEGIN	first:=NIL; last:=NIL; Files.ReadNum(R, tag);
			WHILE	tag#SFend	DO	NEW(par);
				IF	last=NIL	THEN	first:=par	ELSE	last.link:=par	END;
				last:=par;
				IF	tag=SFvar	THEN	par.mode:=VarPar; Files.ReadNum(R, tag)	ELSE par.mode:=Var END;
				(*IF	tag=SFleaf	THEN	par.leaf:=TRUE; Files.ReadNum(R, tag)	END;*)
				InStruct(par.typ, TRUE); ReadString(R, par.name); Files.ReadNum(R, tag)
			END
		END InParList;
		
		PROCEDURE SetTypFlags(typ: Struct);
		BEGIN
			IF (typ.extlev = -1) OR (typ.n < 0) THEN 
				IF typ.BaseTyp # NIL THEN SetTypFlags(typ.BaseTyp); 
					typ.extlev := typ.BaseTyp.extlev + 1; 
					typ.n := typ.BaseTyp.n;
					typ.strobj.conval.setval := typ.strobj.conval.setval + (typ.BaseTyp.strobj.conval.setval * {protectedObj})
				ELSE typ.extlev := 0; typ.n := 0;
					typ.strobj.scope.left := topScope
				END;
			END
		END SetTypFlags;
		
		PROCEDURE InRecord(typ: Struct);
			VAR scope, last, fld: Object; btyp: Struct; n: LONGINT; flags: SET;  conval: Const;
		BEGIN	NEW(scope); scope.mode:=Head; scope.mnolev:=-typ.mno; last:=NIL; btyp:=typ.BaseTyp;
			conval := NewConst();  typ.strobj.conval := conval;
			Files.ReadSet (R, flags);
			IF 0 IN flags THEN  INCL(conval.setval, protectedObj)  END;
			IF 1 IN flags THEN  INCL(conval.setval, activeObj)  END;
			IF 2 IN flags THEN  INCL(conval.setval, safe)  END;
			Files.ReadSInt (R, typ.strobj.prio);
			Files.ReadNum(R, tag);
			WHILE	tag<SFtproc	DO	NEW(fld); 
				IF	last#NIL	THEN	last.link:=fld	END;
				last:=fld;
				IF tag=SFobjflag THEN Files.ReadSInt(R, fld.sysflag); Files.ReadNum(R, tag) END;
				IF tag=SFreadonly THEN Files.ReadNum(R, tag); fld.vis:=externalR ELSE fld.vis:=external END;
				fld.mode:=Fld; InStruct(fld.typ, FALSE); ReadString(R, fld.name);
				IF	fld.name=""	THEN	fld.vis:=internal	END;
				InsertImport(fld, scope); Files.ReadNum(R, tag);
			END;
			IF	tag=SFtproc	THEN	Files.ReadNum(R, tag);
				WHILE	tag#SFend	DO	NEW(fld); fld.mode:=TProc; fld.vis:=external; 
					fld.conval:=NewConst(); fld.linkadr := OPM.LANotAlloc;	(* mfix *)
					fld.conval.setval:={hasBody};	(* mfix *)
					InStruct(fld.typ, FALSE); ReadString(R, fld.name); 
					IF fld.name = "" THEN fld.vis:=internal; ReadString(R, fld.name) END;
					InParList(fld.link);
					IF fld.name = ObjBody THEN
						typ.strobj.link := fld.link; fld := typ.strobj; INCL (conval.setval, hasBody)
					ELSE
						IF fld.name[0] = "&" THEN
							n := 0; REPEAT fld.name[n] := fld.name[n+1]; INC (n) UNTIL fld.name[n] = 0X;
							typ.strobj.link2 := fld
						END;
						InsertImport(fld, scope);
					END;
					Files.ReadNum(R, tag)
				END;
			END;
			ASSERT(~(activeObj IN conval.setval) OR (hasBody IN conval.setval));
			typ.strobj.scope := scope;
			typ.link:=scope.right
		END InRecord;
		
		PROCEDURE InStruct(VAR typ: Struct; par: BOOLEAN);
			VAR typtag, typadr: LONGINT; vis: SHORTINT; tobj: Object; btyp: Struct; typname: OPS.Name; mod: Module; i: INTEGER;
		BEGIN
			IF	tag <= 0	THEN	DEC(tag); ASSERT(tag>-LEN(M.struct^)); typ:=M.struct[-tag]
			ELSIF tag <= SFlastStruct THEN typ:=predefStruct[tag]
			ELSIF tag <= SFmodOther THEN
				IF tag = SFmodOther THEN Files.ReadNum(R, tag) ELSE tag:=tag-SFmod1 END;
				mod:=M.import[tag]; ReadString(R, typname); 
				IF typname[0]#0X THEN
					i:=1; WHILE (i<mod.nofstr) & (mod.struct[i].strobj.name#typname) DO INC(i) END;
					IF i<mod.nofstr THEN typ:=mod.struct[i]  ELSE  typ:=niltyp; IF ~impSelf THEN err(150) END END;
					INC(mod.nofreimp); 
					IF mod.nofreimp>=LEN(mod.reimp^) THEN DoubleStructArr(mod.reimp) END;
					mod.reimp[mod.nofreimp]:=typ;  
				ELSE 
					Files.ReadNum(R, typadr); INC(typadr); ASSERT(typadr < LEN(mod.reimp^)); typ:=mod.reimp[typadr]
				END
			ELSE
				NEW(typ); M.struct[M.nofstr]:=typ; typ.tdadr:=OPM.TDAdrUndef; typ.offset:=OPM.TDAdrUndef;
				typ.sref:=-M.nofstr; INC(M.nofstr); 
				IF M.nofstr>=LEN(M.struct^) THEN DoubleStructArr(M.struct) END;
				IF	tag=SFinvisible	THEN	vis:=internal; Files.ReadNum(R, tag)	ELSE	vis:=external	END;
				IF	tag=SFsysflag	THEN	Files.ReadNum(R, tag); typ.sysflag:=SHORT(SHORT(tag)); Files.ReadNum(R, tag)	END;
				typ.form:=strucForm[tag]; typ.comp:=strucComp[tag]; typ.mno:=-M.mnolev; typ.size:=-1; 
				typtag:=tag; Files.ReadNum(R, tag); typ.extlev := -1;
				InStruct(typ.BaseTyp, par);  btyp := typ.BaseTyp;
				IF (typ.comp=Record) & ((btyp = notyp) OR (btyp = niltyp)) THEN	(*PaCo exports the rec.btyp as notyp*)
					typ.BaseTyp := NIL
				ELSIF (typ.comp=Record) & (btyp#NIL) & (btyp.form=Pointer) THEN
					typ.BaseTyp := btyp.BaseTyp
				ELSIF (typ.form=Pointer) & (btyp.comp=Record) & (btyp.strobj.name="") THEN
					btyp.ptr := typ
				END;
				NEW(tobj); tobj.mode:=Typ; tobj.nxtobj:=last; last:=tobj; tobj.typ:=typ; ReadString(R, tobj.name);
				typ.strobj := tobj;
				IF	tobj.name#""	THEN	tobj.vis:=vis; tobj.typ:=typ; InsertImport(tobj, M)	END;
				CASE	typtag	OF
				| SFtypDynArr, SFtypOpenArr:
					IF btyp.comp IN {DynArr, OpenArr} THEN  typ.n := btyp.n + 1  ELSE  typ.n := 0  END;
				| SFtypArray:
					Files.ReadNum(R, typ.n)
				| SFtypPointer:
				| SFtypRecord:	InRecord(typ); typ.n := -1;
				| SFtypProcTyp:	InParList(typ.link)
				END;
				IF impSelf & (tobj.name#"") & (tobj.vis#internal) THEN 
					typ.sref:=0;
				END;
			END
		END InStruct;

		PROCEDURE InObj;
		BEGIN	NEW(obj); obj.mode:=mode; obj.nxtobj:=last; last:=obj;
			IF (tag = SFobjflag) THEN  Files.ReadSInt(R, obj.sysflag); Files.ReadNum(R, tag)  END;
			IF tag=SFreadonly THEN Files.ReadNum(R, tag); obj.vis:=externalR ELSE obj.vis:=external END;
			(*IF tag=SFleaf THEN Files.ReadNum(R, tag); obj.leaf:=TRUE END;*)
			InStruct(obj.typ, FALSE); ReadString(R, obj.name);
			IF operator THEN  obj.prio := 126  END;
			InsertImport(obj, M)
		END InObj;

		PROCEDURE InCProc;
			VAR  n, last: Node;  ext: ConstExt;  ch: CHAR;  i, len: LONGINT;
		BEGIN
			NEW(obj.code);  obj.code.class := 29; (*Nassembler*)
			obj.code.conval := NewConst();	(*OPV takes the code position from it! *)
			obj.code.obj := obj;
			Files.ReadChar(R, ch);
			REPEAT
				NEW(n);  n.conval := NewConst();  ext := NewExt();  n.conval.ext := ext;
				IF  obj.code.left = NIL  THEN  obj.code.left := n  ELSE  last.link := n  END;
				last := n;
				len := ORD(ch);  ext[0] := ch;  i := 1;
				WHILE i <= len DO  Files.ReadChar(R, ext[i]); INC(i)  END;
				Files.ReadChar(R, ch)
			UNTIL ch = 0X
		END InCProc;

		PROCEDURE InConst;
			VAR conval: Const; s: INTEGER; r: REAL; 
		BEGIN	NEW(conval); obj.conval:=conval;
			CASE	tag	OF
			| SFtypBool, SFtypChar, SFtypSInt..SFtypLInt:	Files.ReadNum(R, conval.intval)
			| SFtypSet:	Files.ReadSet(R, conval.setval)
			| SFtypReal:	Files.ReadReal(R, r); conval.realval := r; conval.intval := OPM.ConstNotAlloc
			| SFtypLReal:	Files.ReadLReal(R, conval.realval); conval.intval := OPM.ConstNotAlloc
			| SFtypString:	NEW(conval.ext); ReadString(R, conval.ext^);
				s:=0; WHILE conval.ext[s]#0X DO INC(s) END; conval.intval:=OPM.ConstNotAlloc; conval.intval2:=s+1
			| SFtypNilTyp:
			END
		END InConst;

	BEGIN	i:=0;
		WHILE	(i < nofmod) & (impName#modules[i].name)	DO	INC(i)	END;
		IF	i < nofmod	THEN	M:=modules[i]; new:=FALSE; 
		ELSE	M:=NewMod(); M.name := impName; M.mnolev:=-nofmod; 
			modules[nofmod]:=M; INC(nofmod); 			
			IF nofmod>=LEN(modules^) THEN DoubleModArr(modules) END;
			new:=TRUE 
		END;
		M.nofreimp:=0; 
		IF	new	OR	impSelf&(i=0)	THEN
			M.nofimp:=0; M.struct[0]:=NIL; M.nofstr:=1; operator:=FALSE;
			OPM.OpenSym(R, impName, impSelf, done);
			IF	done	THEN	GetImports;
				IF	OPM.noerr	THEN
					i:=0; WHILE i<nofmod DO modules[i].nofreimp:=0; INC(i) END;
					last:=NIL; Files.ReadNum(R, tag);
					IF	tag=SFconst	THEN	mode:=Con; Files.ReadNum(R, tag);
						WHILE	tag < SFvar	DO	InObj; InConst; Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFvar	THEN	mode:=Var; Files.ReadNum(R, tag);
						WHILE	tag < SFxproc	DO	InObj; Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFxproc	THEN	mode:=XProc; Files.ReadNum(R, tag);
						WHILE	tag < SFoperator	DO
							InObj; InParList(obj.link); Files.ReadNum(R, tag);
							obj.conval:=NewConst(); obj.conval.setval:={};
						END
					END;
					IF	tag=SFoperator	THEN	mode:=XProc; operator:=TRUE;Files.ReadNum(R, tag);
						WHILE	tag < SFcproc(*SFalias*)	DO
							InObj; InParList(obj.link); obj.conval:=NewConst(); obj.conval.setval:={};
							Files.ReadNum(R, tag)
						END;
						operator:=FALSE;
					END;
					IF	tag=SFcproc	THEN	mode:=CProc; Files.ReadNum(R, tag);
						WHILE	tag < SFalias	DO
							InObj; InParList(obj.link); obj.conval:=NewConst(); obj.conval.setval:={hasBody, asmProc};
							InCProc;  Files.ReadNum(R, tag)	END
					END;
					IF	tag=SFalias	THEN	Files.ReadNum(R, tag);
						WHILE	tag < SFtyp	DO	NEW(obj); obj.vis:=external; obj.mode:=Typ;
							InStruct(obj.typ, FALSE); ReadString(R, obj.name); 
							IF obj.typ.strobj.vis = internal THEN  INCL(obj.typ.strobj.flag, typeVisible)  END;
							InsertImport(obj, M); CompOldSym(obj); 
							Files.ReadNum(R, tag)
						END
					END;
					IF	tag=SFtyp	THEN	Files.ReadNum(R, tag);
						WHILE	tag < SFend	DO	InStruct(tdum, FALSE); Files.ReadNum(R, tag)	END
					END;
					M.publics:=last; 
					WHILE last # NIL DO
						IF (last.mode = Typ) & (last.typ.form = Comp) & (last.typ.comp = Record) THEN SetTypFlags(last.typ) END;
						last := last.nxtobj
					END;
					Files.Close(Files.Base(R));
				END;
			ELSE 
				IF impSelf THEN newSF:=TRUE; extSF:=TRUE; sfpresent:=FALSE 
				ELSE err(152);  
				END;
			END
		ELSIF (i = 0) & ~impSelf THEN err(154)
		END;
	END Imp;

	PROCEDURE Import*(VAR aliasName, impName, selfName: OPS.Name);
		VAR ali: Object; M: Module;
	BEGIN
		Insert(aliasName, ali); ali.mode:=Mod; ali.typ:=notyp;
		IF impName="SYSTEM" THEN
			SYSimported:=TRUE; ali.mnolev:=0; ali.scope:=syslink; ali.adr:=0
		ELSE 
			IF (impName=selfName) & (aliasName#"@self") THEN M:=NewMod(); err(49) END;
			impSelf := (impName=modules[0].name);
			Imp(impName, selfName, M); M.directImp:=TRUE; ali.scope:=M.right; ali.mnolev:=M.mnolev
		END
	END Import;

(* Export *)

	PROCEDURE OutMod*(mod: Module);
	BEGIN
		IF	mod.mode=0	THEN
			OPM.SymWMod(mod.name);
			INC(nofemod); 
			IF nofemod>=LEN(emodules^) THEN DoubleModArr(emodules) END;
			emodules[nofemod]:=mod; mod.mode:=nofemod
		END
	END OutMod;

	PROCEDURE ^ OutStruct(typ: Struct);

	PROCEDURE Enumerate(obj: Object);
	VAR p: Object;
	BEGIN
		IF	obj#NIL	THEN
			IF obj.prio=127 THEN
				p := obj.link2;
				WHILE p # NIL DO  p.sibling:=exp[Operator]; exp[Operator]:=p; p:=p.left  END;
				Enumerate(obj.left); Enumerate(obj.right)
			ELSE
				Enumerate(obj.left);
				IF	(obj.vis > internal)=export	THEN
					IF	expGlobal & (obj.history=removed)	THEN	FPrintErr(obj); obj.mode:=Undef
					ELSE
						IF	(obj.mode#Typ) OR (obj.typ.strobj#obj)	THEN	FPrintErr(obj)	END;
						IF	(obj.mode=Typ)&(obj.typ.strobj#obj) 	THEN	
							obj.sibling:=exp[Alias]; exp[Alias]:=obj
						ELSIF	(obj.mode#Var) OR (~obj.par)	THEN
							obj.sibling:=exp[obj.mode]; exp[obj.mode]:=obj;
						END
					END
				END;
				Enumerate(obj.right)
			END
		END
	END Enumerate;

	PROCEDURE OutCProc(n: Node);
	VAR  ext: ConstExt;  i, len: LONGINT;
	BEGIN
		REPEAT
			ext := n.conval.ext;  len := ORD(ext[0]);  i := 0;
			WHILE i <= len DO  OPM.SymW(ext[i]); INC(i)  END;
			n := n.link
		UNTIL n = NIL;
		OPM.SymW(0X)
	END OutCProc;

	PROCEDURE OutParList(par: Object);
	BEGIN	
		WHILE	par#NIL	DO
			IF	par.mode=VarPar	THEN	OPM.SymW(CHR(SFvar))	END;
			(*IF	par.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
			OutStruct(par.typ); OPM.SymWString(par.name); par.par:=TRUE; par.nxtobj:=par.link ; par:=par.link
		END;
		OPM.SymWNum(SFend)	(*OPM.SymW(CHR(SFend))*)
	END OutParList;

	PROCEDURE OutFld(fld: Object);
	BEGIN
		WHILE	fld#NIL	DO
			IF  fld.sysflag # 0 THEN  OPM.SymW(CHR(SFobjflag)); OPM.SymW(CHR(fld.sysflag))  END;
			IF	fld.vis=externalR	THEN	OPM.SymW(CHR(SFreadonly))	END;
			OutStruct(fld.typ);
			IF	fld.vis > internal	THEN	OPM.SymWString(fld.name)	ELSE	OPM.SymW(0X)	END;
			fld:=fld.link
		END
	END OutFld;

	PROCEDURE OutRecord(typ: Struct);
		VAR btyp: Struct; count: LONGINT; flag: SET;

		PROCEDURE TraverseBody (fld: Object);
			VAR str: ARRAY 32 OF CHAR;
		BEGIN
			IF (fld # NIL) & (hasBody IN fld.conval.setval) THEN
				OPM.SymW(CHR(SFtproc));	(* this is the first method!! *)
				str := ObjBody;
				INC (count); OutStruct (notyp); OPM.SymWString (str); OutParList (fld.link)
			END
		END TraverseBody;

		PROCEDURE TraverseT(fld: Object);
		BEGIN
			IF	fld#NIL	THEN	TraverseT(fld.left);
				IF	fld.mode=TProc	THEN	
					IF	count=0	THEN	OPM.SymW(CHR(SFtproc))	END;
					INC(count); OutStruct(fld.typ); 
					IF	fld.vis = internal	THEN	OPM.SymW(0X)	END;
					IF fld = typ.strobj.link2 THEN OPM.SymW ("&") END;
					OPM.SymWString(fld.name); OutParList(fld.link)
				END;
				TraverseT(fld.right)
			END
		END TraverseT;

	BEGIN	btyp:=typ.BaseTyp;
		flag:={};
		IF protectedObj IN typ.strobj.conval.setval THEN  INCL(flag, 0)  END;
		IF activeObj IN typ.strobj.conval.setval THEN  INCL(flag, 1)  END;
		IF safe IN typ.strobj.conval.setval THEN  INCL(flag, 2)  END;
		OPM.SymWSet (flag);
		OPM.SymWCh (CHR (typ.strobj.prio));
		IF	(typ.link#NIL)&(typ.link.mode=Fld)	THEN	OutFld(typ.link)	END;
		count:=0;
		TraverseBody (typ.strobj);
		TraverseT(typ.link);
		OPM.SymWNum(SFend);
	END OutRecord;

	PROCEDURE OutStruct(typ: Struct);
		VAR tag: SHORTINT; mod: Module; tobj: Object; 
	BEGIN
		IF	typ=NIL	THEN	OPM.SymW(0X)
		ELSIF	typ.mno#0	THEN	mod:=modules[typ.mno]; OutMod(mod); 
			IF mod.nofstr>0 THEN mod.nofstr:=0 END;
			IF mod.mode>31 THEN OPM.SymW(CHR(SFmodOther)); OPM.SymWNum(mod.mode-1) ELSE OPM.SymW(CHR(SFmod1-1+mod.mode)) END;
			IF typ.sref<0 THEN DEC(mod.nofstr); typ.sref:=-mod.nofstr; OPM.SymWString(typ.strobj.name); 
			ELSE OPM.SymW(0X); OPM.SymWNum(typ.sref-1) END; 	(*!!!sref > 0*)
		ELSIF	typ.sref>0	THEN	OPM.SymWNum(typ.sref)	(*!!!sref < 0*)
		ELSIF	typ.sref#0	THEN	OPM.SymWNum(typ.sref+1)	(*!!!sref < 0*)
		ELSE	DEC(nofstruc); typ.sref:=nofstruc; tag:=strucFormSF[typ.form]+strucCompSF[typ.comp];
			IF	export&(typ.strobj#NIL)&(typ.strobj.vis=internal)	THEN	OPM.SymW(CHR(SFinvisible))	END;
			IF	typ.sysflag#0	THEN	OPM.SymW(CHR(SFsysflag)); OPM.SymW(CHR(typ.sysflag))	END;
			OPM.SymW(CHR(tag));
			IF (typ.comp=Record) & (typ.BaseTyp#NIL) & (typ.BaseTyp.ptr#NIL) THEN
				OutStruct(typ.BaseTyp.ptr)
			ELSIF (typ.comp=Record) & (typ.BaseTyp=NIL)THEN
				OutStruct(notyp)
			ELSE
				OutStruct(typ.BaseTyp)
			END;
			NEW(tobj); tobj.mode:=Typ; tobj.nxtobj:=objects; objects:=tobj; tobj.typ:=typ;
			IF	(typ.strobj=NIL) OR (typ.strobj.name="")	THEN	OPM.SymW(0X)
			ELSE	FPrintErr(typ.strobj); OPM.SymWString(typ.strobj.name); tobj.name := typ.strobj.name	END;
			CASE	tag	OF
			| SFtypDynArr, SFtypOpenArr:
			| SFtypArray: OPM.SymWNum (typ.n); 
			| SFtypPointer:
			| SFtypRecord:	OutRecord(typ)
			| SFtypProcTyp:	OutParList(typ.link)
			END
		END
	END OutStruct;

	PROCEDURE OutConst(form: SHORTINT; conval: Const);
	BEGIN
		CASE	form	OF
		| Bool, Char, SInt..LInt:	OPM.SymWNum(conval.intval)
		| Set:	OPM.SymWSet(conval.setval)
		| Real:	OPM.SymWReal(SHORT(conval.realval))
		| LReal:	OPM.SymWLReal(conval.realval)
		| String:	OPM.SymWString(conval.ext^)
		| NilTyp:
		END
	END OutConst;

	PROCEDURE OutObj(obj: Object);
	BEGIN	obj.nxtobj:=objects; objects:=obj; OutStruct(obj.typ);
		IF obj = topScope.link.link2 THEN OPM.SymW ("&") END;
		OPM.SymWString(obj.name)
	END OutObj;

	PROCEDURE OutScope*(scope: Object; public: BOOLEAN);
		VAR obj: Object; first: BOOLEAN; i: LONGINT;
	BEGIN	export:=public;
		exp[Con]:=NIL; exp[Var]:=NIL; exp[LProc]:=NIL; exp[XProc]:=NIL; exp[Alias]:=NIL; exp[Typ]:=NIL; exp[Operator]:=NIL;
		Enumerate(scope);
		
		i := 1;
		WHILE (i < LEN(modules)) & (modules[i] # NIL) DO
			IF modules[i].directImp THEN OutMod(modules[i])  END;	(*export those explicitly imported to allow for recursion test*)
			INC(i)
		END;
		
		IF	exp[Con]#NIL	THEN	OPM.SymW(CHR(SFconst)); obj:=exp[Con];
			WHILE	obj#NIL	DO	OutObj(obj); OutConst(obj.typ.form, obj.conval); obj:=obj.sibling	END;
		END;
		IF	exp[Var]#NIL	THEN	OPM.SymW(CHR(SFvar)); obj:=exp[Var];
			WHILE	obj#NIL	DO
				IF	obj.vis=externalR	THEN	OPM.SymW(CHR(SFreadonly))	END;
				(*IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
				OutObj(obj); obj:=obj.sibling
			END;
		END;
		IF	exp[LProc]#NIL	THEN	OPM.SymW(CHR(SFlproc)); obj:=exp[LProc];
			WHILE	obj#NIL	DO	
				(*IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
				OutObj(obj); OutParList(obj.link); obj:=obj.sibling	
			END;
		END;
		IF	exp[XProc]#NIL	THEN	OPM.SymW(CHR(SFxproc)); obj:=exp[XProc];
			WHILE	obj#NIL	DO	
				IF obj.sysflag # 0 THEN
					OPM.SymW(CHR(SFobjflag));
					OPM.SymW(CHR(obj.sysflag))
				END;
				(*IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
				OutObj(obj); OutParList(obj.link); obj:=obj.sibling	
			END;
		END;
		IF	exp[Operator]#NIL	THEN	OPM.SymW(CHR(SFoperator)); obj:=exp[Operator];
			WHILE	obj#NIL	DO	
				(*IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
				OutObj(obj); OutParList(obj.link); obj:=obj.sibling	
			END;
		END;
		IF	exp[CProc]#NIL	THEN	OPM.SymW(CHR(SFcproc)); obj:=exp[CProc];
			WHILE	obj#NIL	DO	
				(*IF	obj.leaf	THEN	OPM.SymW(CHR(SFleaf))	END;*)
				OutObj(obj); OutParList(obj.link); OutCProc(obj.code.left); obj:=obj.sibling	
			END;
		END;
		IF	exp[Alias]#NIL	THEN	OPM.SymW(CHR(SFalias)); obj:=exp[Alias];
			WHILE	obj#NIL	DO	OutStruct(obj.typ); OPM.SymWString(obj.name); obj:=obj.sibling	END;
		END;
		IF	exp[Typ]#NIL	THEN	obj:=exp[Typ]; first:=TRUE;
			WHILE	obj#NIL	DO
				IF	obj.typ.sref=0	THEN
					IF	first	THEN	OPM.SymW(CHR(SFtyp)); first:=FALSE	END;
					IF	~export OR (obj.typ.strobj#NIL) & (obj.typ.strobj.vis#internal)	THEN	OutStruct(obj.typ)	END;
				END;
				obj:=obj.sibling
			END;
		END;
		OPM.SymWNum(SFend)
	END OutScope;

	PROCEDURE Export*(VAR modName: OPS.Name; VAR newsf, extsf: BOOLEAN);
		VAR mods: SHORTINT; aliasName: OPS.Name;
	BEGIN symExtended:=FALSE; symNew:=FALSE; nofstruc:=0; nofemod:=0; objects:=NIL;
		modNo:=0; aliasName := "@self"; mods:=nofmod;
		Import(aliasName, modName, modName); nofmod:=mods;
		IF OPM.noerr THEN expGlobal:=TRUE; CompOldSym(modules[0].publics);
			OutScope(topScope.right, TRUE); expGlobal:=FALSE;
			extsf:=sfpresent & symExtended; newsf:=~sfpresent OR symNew;
			OPM.EndSym; 
			IF ~OPM.noerr THEN err(155); newsf:=FALSE; extsf:=FALSE END;
		ELSE newSF:=FALSE; extSF:=FALSE END;
	END Export;


(* Initialisation *)

	PROCEDURE InitStruct(VAR typ: Struct; form, sref: SHORTINT);
	BEGIN typ := NewStr(form, Basic); typ^.ref := form; typ^.size := OPM.ByteSize; typ^.sref:=sref;
		predefStruct[sref]:=typ; typ^.tdadr := 0; typ^.offset := 0; typ^.strobj := NewObj();
		typ.fpdone:=-1; typ.pvfp:=form; typ.pbfp:=form; typ.fp:=form;
	END InitStruct;

	PROCEDURE EnterIntConst(IN name: ARRAY OF CHAR; value: LONGINT);
		VAR obj: Object;
	BEGIN Insert(name, obj); obj^.conval := NewConst();
		obj^.mode := Con; obj^.typ := sinttyp; obj^.conval^.intval := value
	END EnterIntConst;

	PROCEDURE EnterTyp(IN name: ARRAY OF CHAR; form: SHORTINT; size: INTEGER; VAR res: Struct; sref: SHORTINT);
		VAR obj: Object; typ: Struct;
	BEGIN Insert(name, obj);
		typ := NewStr(form, Basic); obj^.mode := Typ; obj^.typ := typ; obj^.vis := external; typ.sref:=sref; predefStruct[sref]:=typ;
		typ^.strobj := obj; typ^.size := size; typ^.tdadr := 0; typ^.offset := 0; typ^.ref := form; res := typ;
		typ.fpdone:=-1; typ.pvfp:=size; typ.pbfp:=form; typ.fp:=form
	END EnterTyp;

	PROCEDURE EnterTypAlias(IN name: ARRAY OF CHAR; typ: Struct);
		VAR obj: Object;
	BEGIN Insert(name, obj);
		obj^.mode := Typ; obj^.typ := typ; obj^.vis := external
	END EnterTypAlias;
	
	PROCEDURE EnterProc(IN name: ARRAY OF CHAR; num: INTEGER);
		VAR obj: Object;
	BEGIN Insert(name, obj);
		obj.mode := SProc; obj.typ := notyp; obj.adr := num
	END EnterProc;

	PROCEDURE EnterPtr(IN name: ARRAY OF CHAR; num: LONGINT);
		VAR obj: Object;
	BEGIN Insert(name, obj);
		obj^.mode := Var; obj^.typ := ptrtyp; obj^.adr := num; obj^.linkadr := num; obj^.mnolev := 0
	END EnterPtr;


BEGIN
	topScope:=NIL; NEW(modules, DefMaxImport); NEW(emodules, DefMaxImport);
	OpenScope(0, NIL); OPM.errpos:=0;
	
	InitStruct(undftyp, Undef, 0); 
	InitStruct(notyp, NoTyp, SFtypNoTyp); InitStruct(stringtyp, String, SFtypString); InitStruct(niltyp, NilTyp, SFtypNilTyp);
	undftyp^.BaseTyp := undftyp;

	(*initialization of module SYSTEM*)
	EnterTyp("BYTE", Byte, OPM.ByteSize, bytetyp, SFtypByte);
	EnterTyp("PTR", Pointer, OPM.PointerSize, ptrtyp, SFtypptr);
	EnterProc("ADR", adrfn); EnterProc("CC", ccfn);
	EnterProc("LSH", lshfn); EnterProc("ROT", rotfn);
	EnterProc("GET", getfn); EnterProc("PUT", putfn);
	EnterProc("GETREG", getrfn); EnterProc("PUTREG", putrfn);
	EnterProc("BIT", bitfn); EnterProc("VAL", valfn);
	EnterProc("NEW", sysnewfn); EnterProc("MOVE", movefn);
	EnterProc("PORTOUT", poutfn); EnterProc("PORTIN", pinfn);
	EnterProc("STI", stifn); EnterProc("CLI", clifn);
	EnterProc("HALT", shalt);
	EnterProc("GET8", get8fn); EnterProc("GET16", get16fn); EnterProc("GET32", get32fn);
	EnterProc("PUT8", put8fn); EnterProc("PUT16", put16fn); EnterProc("PUT32", put32fn);
	EnterProc("TYPECODE", typefn);
	
	syslink := topScope.right; universe := topScope; topScope.right := NIL;

	EnterTyp("CHAR", Char, OPM.CharSize, chartyp, SFtypChar);
	EnterTyp("SET", Set, OPM.SetSize, settyp, SFtypSet);
	EnterTyp("REAL", Real, OPM.RealSize, realtyp, SFtypReal);
	EnterTyp("INTEGER", Int, OPM.IntSize, inttyp, SFtypInt);
	EnterTyp("LONGINT",  LInt, OPM.LIntSize, linttyp, SFtypLInt);
	EnterTyp("HUGEINT",  HInt, OPM.HIntSize, hinttyp, SFtypHInt);
	EnterTyp("LONGREAL", LReal, OPM.LRealSize, lrltyp, SFtypLReal);
	EnterTyp("SHORTINT", SInt, OPM.SIntSize, sinttyp, SFtypSInt);
	EnterTyp("BOOLEAN", Bool, OPM.BoolSize, booltyp, SFtypBool);
	EnterTypAlias("PTR",  ptrtyp);

	universe := topScope^.right; topScope^.right := syslink;		(*add to SYSTEM*)
	EnterIntConst("EAX", 8); EnterIntConst("ECX", 9);
	EnterIntConst("EDX", 10); EnterIntConst("EBX", 11);
	EnterIntConst("ESP", 12); EnterIntConst("EBP", 13);
	EnterIntConst("ESI", 14); EnterIntConst("EDI", 15);

	EnterIntConst("AX", 16); EnterIntConst("CX", 17);
	EnterIntConst("DX", 18); EnterIntConst("BX", 19);
	EnterIntConst("SP", 20); EnterIntConst("BP", 21);
	EnterIntConst("SI", 22); EnterIntConst("DI", 23);

	EnterIntConst("AL", 24); EnterIntConst("CL", 25);
	EnterIntConst("DL", 26); EnterIntConst("BL", 27);
	EnterIntConst("AH", 28); EnterIntConst("CH", 29);
	EnterIntConst("DH", 30); EnterIntConst("BH", 31);
	topScope^.right := universe; universe := topScope;
	
	EnterProc("HALT", haltfn); EnterProc("NEW", newfn);
	EnterProc("ABS", absfn); EnterProc("CAP", capfn);
	EnterProc("ORD", ordfn); EnterProc("ENTIER", entierfn);
	EnterProc("ODD", oddfn); EnterProc("MIN", minfn);
	EnterProc("MAX", maxfn); EnterProc("CHR", chrfn);
	EnterProc("SHORT", shortfn); EnterProc("LONG", longfn);
	EnterProc("SIZE", sizefn); EnterProc("INC", incfn);
	EnterProc("DEC", decfn); EnterProc("INCL", inclfn); EnterProc("EXCL", exclfn);
	EnterProc("LEN", lenfn);EnterProc("COPY", copyfn);
	EnterProc("ASH", ashfn);EnterProc("ASSERT", assertfn);

	EnterProc("AWAIT", awaitfn);

	EnterPtr("@SELF", 0H);	(* <- Sentinel for the search (it must stop here!! *)
	EnterPtr("SELF", 0H);

	strucForm[SFtypPointer]:=Pointer; strucForm[SFtypRecord]:=Comp; strucForm[SFtypProcTyp]:=ProcTyp;
	strucForm[SFtypDynArr]:=Comp; strucForm[SFtypArray]:=Comp;
	strucForm[SFtypOpenArr]:=Comp;
	strucComp[SFtypPointer]:=Basic; strucComp[SFtypRecord]:=Record; strucComp[SFtypProcTyp]:=Basic;
	strucComp[SFtypDynArr]:=DynArr; strucComp[SFtypArray]:=StaticArr;
	strucComp[SFtypOpenArr]:=OpenArr;
	strucFormSF[Pointer]:=SFtypPointer; strucFormSF[ProcTyp]:=SFtypProcTyp;
	strucCompSF[StaticArr]:=SFtypArray; strucCompSF[DynArr]:=SFtypDynArr; strucCompSF[Record]:=SFtypRecord;
	strucCompSF[OpenArr]:=SFtypOpenArr;
	
	NEW(ToBeFixed); ToBeFixed.incomplete := TRUE;
END OPT.
