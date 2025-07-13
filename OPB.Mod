(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* Oberon Portable build parse tree (front end) *)
(* RC, rml, pjm, prk*)


(*
	References:
	1. N. Wirth Oberon Language Report
	2. Wirth/Mössenböck, Oberon-2 Langauge Report
*)

MODULE OPB;	(** non-portable *)
	IMPORT OPT, OPS, OPM;

	CONST
		AwaitIF* = TRUE;
		
		(* symbol values or ops *)
		times = 1; slash = 2; div = 3; mod = 4;
		and = 5; plus = 6; minus = 7; or = 8; eql = 9;
		neq = 10; lss = 11; leq = 12; gtr = 13; geq = 14;
		in = 15; is = 16; ash = 17; msk = 18; len = 19;
		conv = 20; abs = 21; cap = 22; odd = 23; not = 33;
 		
		(*SYSTEM*)
		adr = 24; cc = 25; bit = 26; lsh = 27; rot = 28; val = 29;
		get8 = 30; get16 = 31; get32 = 32; type = 34;
		
		(* object modes *)
		Var = 1; VarPar = 2; Con = 3; Fld = 4; Typ = 5; LProc = 6; XProc = 7;
		SProc = 8; CProc = 9; IProc = 10; Mod = 11; Head = 12; TProc = 13;

		(* Structure forms *)
		Undef = 0; Byte = 1; Bool = 2; Char = 3; SInt = 4; Int = 5; LInt = 6;
		Real = 7; LReal = 8; Set = 9; String = 10; NilTyp = 11; NoTyp = 12;
		Pointer = 13; ProcTyp = 14; Comp = 15;
		HInt = 16;
		intSet = {SInt..LInt}; realSet = {Real, LReal};
		
		(* composite structure forms *)
		Basic = 1; StaticArr = 2; SDynArr = 3; DynArr = 4; OpenArr = 5; Record = 6;
		ArraySet = {StaticArr, SDynArr, DynArr, OpenArr};
		
		(* nodes classes *)
		Nvar = 0; Nvarpar = 1; Nfield = 2; Nderef = 3; Nindex = 4; Nguard = 5; Neguard = 6;
		Nconst = 7; Ntype = 8; Nproc = 9; Nupto = 10; Nmop = 11; Ndop = 12; Ncall = 13;
		Ninittd = 14; Nif = 15; Ncaselse = 16; Ncasedo = 17; Nenter = 18; Nassign = 19;
		Nifelse = 20; Ncase = 21; Nwhile = 22; Nrepeat = 23; Nloop = 24; Nexit = 25;
		Nreturn = 26; Nwith = 27; Ntrap = 28; Nfixup = 31;

		(*function number*)
		assign = 0;
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

		(* procedure flags (conval^.setval) *)
		hasBody = 1; isRedef = 2; slNeeded = 3;
		
		(* options *)
		ovflchk = 1;	(* overflow check *)
		
		AssertTrap = 8;	(* default trap number *)

		(* sysflag *) (* ejz *)
		notag = 1; stdcall = 2; cdecl = 3; delegate = 5;

	VAR
		typSize*: PROCEDURE(typ: OPT.Struct; allocDesc: BOOLEAN);
		verify*: PROCEDURE(VAR obj: OPT.Object);
		exp: INTEGER;	(*side effect of log*)
		maxExp: LONGINT;	(* max n in ASH(1, n) on this machine *)
		InitPar: OPT.Object;		(* list of parameters in the current initialiser, used by NEW, only for active compiler *)

	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;

	PROCEDURE InitInsert*(VAR stat: OPT.Node);
		VAR t: OPT.Node;
	BEGIN
		IF OPT.topScope^.code=NIL THEN
			OPT.topScope^.code:=stat
		ELSE t:=OPT.topScope^.code;
			WHILE t^.link#NIL DO t:=t^.link END;
			t^.link:=stat; stat^.link:=NIL
		END
	END InitInsert;
	
	PROCEDURE CodeInsert*(VAR stat: OPT.Node);
		VAR t: OPT.Node;
	BEGIN
		IF OPT.topScope^.link^.code=NIL THEN
			OPT.topScope^.link^.code:=stat
		ELSE t:=OPT.topScope^.link^.code;
			WHILE t^.link#NIL DO t:=t^.link END;
			t^.link:=stat; stat^.link:=NIL
		END
	END CodeInsert;
	
	PROCEDURE InitAppend(VAR x: OPT.Node);
		VAR t: OPT.Node;
	BEGIN (* smistare il contenuto -> per Head forse non necessario *)
		t:=OPT.topScope.code;
		IF t#NIL THEN
			WHILE t^.link#NIL DO t:=t^.link END;
			t^.link:=x;
			x:=OPT.topScope.code; OPT.topScope.code:=NIL
		END
	END InitAppend;
	
	PROCEDURE NewLeaf*(obj: OPT.Object): OPT.Node;
		VAR node: OPT.Node; self: OPT.Object;
	BEGIN
		IF verify#NIL THEN verify(obj) END;
		CASE obj^.mode OF
		  Var:
				node := OPT.NewNode(Nvar); node^.readonly := (obj^.vis = externalR) & (obj^.mnolev < 0)
		| VarPar:
				node := OPT.NewNode(Nvarpar)
		| Con:
				node := OPT.NewNode(Nconst); node^.conval := OPT.NewConst();
				node^.conval^ := obj^.conval^	(* string is not copied, only its ref *)
		| Typ:
				node := OPT.NewNode(Ntype)
		| LProc..IProc:
				node := OPT.NewNode(Nproc)
		| Fld, TProc:
				OPT.FindInScope("@SELF", OPT.topScope, self); node := NewLeaf(self);
				IF node.typ.form = Pointer THEN DeRef(node) END;
				Field(node, obj);
				RETURN node
		ELSE err(127); node := OPT.NewNode(Nvar)
		END ;
		node^.obj := obj; node^.typ := obj^.typ;
		RETURN node
	END NewLeaf;
	
	PROCEDURE Construct*(class: SHORTINT; VAR x: OPT.Node;  y: OPT.Node);
		VAR node: OPT.Node;
	BEGIN
		node := OPT.NewNode(class); node^.typ := OPT.notyp;
		node^.left := x; node^.right := y; x := node
	END Construct;
	
	PROCEDURE Link*(VAR x, last: OPT.Node; y: OPT.Node);
	BEGIN
		IF x = NIL THEN x := y ELSE last^.link := y END ;
		WHILE y^.link # NIL DO y := y^.link END ;
		last := y
	END Link;
	
	PROCEDURE BoolToInt(b: BOOLEAN): LONGINT;
	BEGIN
		IF b THEN RETURN 1 ELSE RETURN 0 END
	END BoolToInt;
	
	PROCEDURE IntToBool(i: LONGINT): BOOLEAN;
	BEGIN
		IF i = 0 THEN RETURN FALSE ELSE RETURN TRUE END
	END IntToBool;
	
	PROCEDURE NewBoolConst*(boolval: BOOLEAN): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.typ := OPT.booltyp;
		x^.conval := OPT.NewConst(); x^.conval^.intval := BoolToInt(boolval); RETURN x
	END NewBoolConst;

	PROCEDURE OptIf*(VAR x: OPT.Node);	(* x^.link = NIL *)
		VAR if, pred: OPT.Node;
	BEGIN
		if := x^.left;
		WHILE if^.left^.class = Nconst DO
			IF IntToBool(if^.left^.conval^.intval) THEN x := if^.right; RETURN
			ELSIF if^.link = NIL THEN x := x^.right; RETURN
			ELSE if := if^.link; x^.left := if
			END
		END ;
		pred := if; if := if^.link;
		WHILE if # NIL DO
			IF if^.left^.class = Nconst THEN
				IF IntToBool(if^.left^.conval^.intval) THEN
					pred^.link := NIL; x^.right := if^.right; RETURN
				ELSE if := if^.link; pred^.link := if
				END
			ELSE pred := if; if := if^.link
			END
		END
	END OptIf;

	PROCEDURE Nil*(): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.typ := OPT.niltyp;
		x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.nilval; RETURN x
	END Nil;

	PROCEDURE BoolConst*(value: INTEGER): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.typ := OPT.booltyp;
		x^.conval := OPT.NewConst(); x^.conval^.intval := value;
		RETURN x
	END BoolConst;

	PROCEDURE EmptySet*(): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.typ := OPT.settyp;
		x^.conval := OPT.NewConst(); x^.conval^.setval := {}; RETURN x
	END EmptySet;

	PROCEDURE SetIntType(node: OPT.Node);
		VAR v: LONGINT;
	BEGIN v := node^.conval^.intval;
		IF (OPM.MinSInt <= v) & (v <= OPM.MaxSInt) THEN node^.typ := OPT.sinttyp
		ELSIF (OPM.MinInt <= v) & (v <= OPM.MaxInt) THEN node^.typ := OPT.inttyp
		ELSIF (OPM.MinLInt <= v) & (v <= OPM.MaxLInt) (*bootstrap or cross*) THEN
			node^.typ := OPT.linttyp
		ELSE err(203); node^.typ := OPT.sinttyp; node^.conval^.intval := 1
		END
	END SetIntType;

	PROCEDURE NewIntConst*(intval: LONGINT): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.conval := OPT.NewConst();
		x^.conval^.intval := intval; SetIntType(x); RETURN x
	END NewIntConst;
	
	PROCEDURE NewRealConst*(realval: LONGREAL; typ: OPT.Struct): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.conval := OPT.NewConst();
		x^.conval^.realval := realval; x^.typ := typ; x^.conval^.intval := OPM.ConstNotAlloc;
		RETURN x
	END NewRealConst;

	PROCEDURE NewString*(VAR str: OPS.String; len: LONGINT): OPT.Node;
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nconst); x^.conval := OPT.NewConst(); x^.typ := OPT.stringtyp;
		x^.conval^.intval := OPM.ConstNotAlloc; x^.conval^.intval2 := len;
		x^.conval^.ext := OPT.NewExt();  
		x^.conval^.ext^ := str;
		RETURN x
	END NewString;
	
	PROCEDURE CharToString(n: OPT.Node);
		VAR ch: CHAR;
	BEGIN
		n^.typ := OPT.stringtyp; ch := CHR(n^.conval^.intval); n^.conval^.ext := OPT.NewExt();
		IF ch = 0X THEN n^.conval^.intval2 := 1 ELSE n^.conval^.intval2 := 2;
		n^.conval^.ext[1] := 0X END ; n^.conval^.ext[0] := ch;
		n^.conval^.intval := OPM.ConstNotAlloc; n^.obj := NIL
	END CharToString;

	PROCEDURE BindNodes(class: SHORTINT; typ: OPT.Struct; VAR x: OPT.Node; y: OPT.Node);
		VAR node: OPT.Node;
	BEGIN
		node := OPT.NewNode(class); node^.typ := typ;
		node^.left := x; node^.right := y; x := node
	END BindNodes;

	PROCEDURE NotVar(x: OPT.Node): BOOLEAN;
	BEGIN 
		IF x.obj#NIL THEN x.obj.used:=TRUE END;
		RETURN (x^.class >= Nconst) & ((x^.class # Nmop) OR (x^.subcl # val) OR (x^.left^.class >= Nconst))
	END NotVar;

	PROCEDURE DeRef*(VAR x: OPT.Node);
	BEGIN
		IF (x^.class >= Nconst) & (x.class#Ncall) THEN err(78)
		ELSIF x^.typ^.form = Pointer THEN BindNodes(Nderef, x^.typ^.BaseTyp, x, NIL)
		ELSE err(84)
		END
	END DeRef;

	PROCEDURE Index*(VAR x: OPT.Node; y: OPT.Node);
		VAR f: INTEGER; typ: OPT.Struct;
	BEGIN
		f := y^.typ^.form;
		IF x^.class >= Nconst THEN err(79)
		ELSIF ~(f IN intSet) OR (y^.class IN {Nproc, Ntype}) THEN err(80); y^.typ := OPT.inttyp END;	(* JT, 25.08.96 *)
		IF x^.typ^.comp = StaticArr THEN typ := x^.typ^.BaseTyp;
			IF (y^.class = Nconst) & ((y^.conval^.intval < 0) OR ((y^.conval^.intval >= x^.typ^.n))) THEN err(81) END
		ELSIF x^.typ^.comp IN {SDynArr, DynArr, OpenArr} THEN typ := x^.typ^.BaseTyp;
			IF (y^.class = Nconst) & (y^.conval^.intval < 0) THEN err(81) END
		ELSE err(82); typ := OPT.undftyp
		END ;
		BindNodes(Nindex, typ, x, y); x^.readonly := x^.left^.readonly
	END Index;

	PROCEDURE Field*(VAR x: OPT.Node; y: OPT.Object);
	BEGIN (*x^.typ^.comp = Record*)
		ASSERT(x.typ.comp = Record);
		IF x^.class >= Nconst THEN err(77)
		ELSIF (y # NIL) & (y^.mode IN {Fld, TProc}) THEN
			BindNodes(Nfield, y^.typ, x, NIL); x^.obj := y;
			x^.readonly := x^.left^.readonly OR ((y^.vis = externalR) & (y^.mnolev < 0))
		ELSIF (y # NIL) & (y^.mode IN {Con}) THEN
			x := NewLeaf (y)
		ELSE err(83); x^.typ := OPT.undftyp
		END
	END Field;
	
	PROCEDURE TypTest*(VAR x: OPT.Node; obj: OPT.Object; guard: BOOLEAN);

		PROCEDURE GTT(t0, t1: OPT.Struct);
			VAR node: OPT.Node; t: OPT.Struct;
		BEGIN
			 OPT.MarkType(t1);
			t := t0;
			IF (t0.sysflag = notag) OR (t1.sysflag = notag) THEN err(200) END;
			WHILE (t # NIL) & (t # t1) & (t # OPT.undftyp) DO t := t^.BaseTyp END ;
			IF t # t1 THEN
				WHILE (t1 # NIL) & (t1 # t0) & (t1 # OPT.undftyp) DO t1 := t1^.BaseTyp END ;
				IF (t1 = t0) OR (x^.typ = OPT.ptrtyp) THEN
					IF guard THEN BindNodes(Nguard, NIL, x, NIL); x^.readonly := x^.left^.readonly
					ELSE node := OPT.NewNode(Nmop); node^.subcl := is; node^.left := x;
						node^.obj := obj; x := node
					END
				ELSE err(85)
				END
			ELSIF t0 # t1 THEN err(85)
			ELSIF ~guard THEN
				IF x^.class = Nguard THEN	(* cannot skip guard *)
					node := OPT.NewNode(Nmop); node^.subcl := is; node^.left := x;
					node^.obj := obj; x := node
				ELSE x := NewBoolConst(TRUE)
				END
			END
		END GTT;

	BEGIN
		OPT.MarkObj(obj);
		IF NotVar(x) THEN err(112)
		ELSIF x^.typ^.form = Pointer THEN
			IF obj^.typ^.form # Pointer THEN err(86)
			ELSIF obj^.typ^.BaseTyp^.comp # Record THEN err(85)
			ELSIF x^.typ = OPT.ptrtyp THEN GTT(x^.typ, obj^.typ^.BaseTyp)
			ELSIF x^.typ^.BaseTyp^.comp # Record THEN err(85)
			ELSE GTT(x^.typ^.BaseTyp, obj^.typ^.BaseTyp)
			END
		ELSIF (x^.typ^.comp = Record) & ((x^.class = Nvarpar)OR(x^.class = Nderef)) & (obj^.typ^.comp = Record) THEN
			GTT(x^.typ, obj^.typ)
		ELSE err(87)
		END ;
		IF guard THEN x^.typ := obj^.typ ELSE x^.typ := OPT.booltyp END
	END TypTest;

	PROCEDURE In*(VAR x: OPT.Node; y: OPT.Node);
		VAR f: INTEGER; k: LONGINT;
	BEGIN f := x^.typ^.form;
		IF (x^.class = Ntype) OR (x^.class = Nproc) OR (y^.class = Ntype) OR (y^.class = Nproc) THEN err(126)
		ELSIF (f IN intSet) & (y^.typ^.form = Set) THEN
			IF x^.class = Nconst THEN
				k := x^.conval^.intval;
				IF (k < 0) OR (k > OPM.MaxSet) THEN err(202)
				ELSIF y^.class = Nconst THEN x^.conval^.intval := BoolToInt(k IN y^.conval^.setval); x^.obj := NIL
				ELSE BindNodes(Ndop, OPT.booltyp, x, y); x^.subcl := in
				END
			ELSE BindNodes(Ndop, OPT.booltyp, x, y); x^.subcl := in
			END
		ELSE err(92)
		END ;
		x^.typ := OPT.booltyp
	END In;

	PROCEDURE log(x: LONGINT): LONGINT;
	BEGIN exp := 0;
		IF x > 0 THEN
			WHILE ~ODD(x) DO x := x DIV 2; INC(exp) END
		END ;
		RETURN x
	END log;

	PROCEDURE CheckRealType(f, nr: INTEGER; x: OPT.Const);
		VAR min, max, r: LONGREAL;
	BEGIN
		IF f = Real THEN min := OPM.MinReal; max := OPM.MaxReal
		ELSE min := OPM.MinLReal; max := OPM.MaxLReal
		END ;
		r := ABS(x^.realval);
		IF (r > max) OR (r < min) THEN
				err(nr); x^.realval := 1.0
		ELSIF f = Real THEN x^.realval := SHORT(x^.realval)	(* single precision only *)
		END ;
		x^.intval := OPM.ConstNotAlloc
	END CheckRealType;
	
	PROCEDURE MOp*(op: SHORTINT; VAR x: OPT.Node);
		VAR f: INTEGER; typ: OPT.Struct; z: OPT.Node;
		
		PROCEDURE NewOp(op: SHORTINT; typ: OPT.Struct; z: OPT.Node): OPT.Node;
			VAR node: OPT.Node;
		BEGIN
			node := OPT.NewNode(Nmop); node^.subcl := op; node^.typ := typ;
			node^.left := z; RETURN node
		END NewOp;

	BEGIN z := x;
		IF ((z^.class = Ntype) OR (z^.class = Nproc))  & (op # type) THEN err(126)
		ELSIF (z.class = Nfield) & (z.obj.mode = TProc) THEN err(OPS.lparen)
		ELSE typ := z^.typ; f := typ^.form;
			CASE op OF
			  not:
					IF f = Bool THEN
						IF z^.class = Nconst THEN
							z^.conval^.intval := BoolToInt(~IntToBool(z^.conval^.intval)); z^.obj := NIL
						ELSE z := NewOp(op, typ, z)
						END
					ELSE err(98)
					END
			| plus:
					IF ~(f IN intSet + realSet) THEN err(96) END
			| minus:
					IF f IN intSet + realSet +{Set}THEN
						IF z^.class = Nconst THEN
							IF f IN intSet THEN
								IF z^.conval^.intval = MIN(LONGINT) THEN err(203)
								ELSE z^.conval^.intval := -z^.conval^.intval; SetIntType(z)
								END
							ELSIF f IN realSet THEN z^.conval^.realval := -z^.conval^.realval
							ELSE z^.conval^.setval := -z^.conval^.setval
							END ;
							z^.obj := NIL
						ELSE z := NewOp(op, typ, z)
						END
					ELSE err(97)
					END
			| abs:
					IF f IN intSet + realSet THEN
						IF z^.class = Nconst THEN
							IF f IN intSet THEN
								IF z^.conval^.intval = MIN(LONGINT) THEN err(203)
								ELSE z^.conval^.intval := ABS(z^.conval^.intval); SetIntType(z)
								END
							ELSE z^.conval^.realval := ABS(z^.conval^.realval)
							END ;
							z^.obj := NIL
						ELSE z := NewOp(op, typ, z)
						END
					ELSE err(111)
					END
			| cap:
					IF f = Char THEN
						IF z^.class = Nconst THEN
							z^.conval^.intval := ORD(CAP(CHR(z^.conval^.intval))); z^.obj := NIL
						ELSE z := NewOp(op, typ, z)
						END
					ELSE err(111); z^.typ := OPT.chartyp
					END
			| odd:
					IF f IN intSet THEN
						IF z^.class = Nconst THEN
							z^.conval^.intval := BoolToInt(ODD(z^.conval^.intval)); z^.obj := NIL
						ELSE z := NewOp(op, typ, z)
						END
					ELSE err(111)
					END ;
					z^.typ := OPT.booltyp
			| adr: (*SYSTEM.ADR*)
					IF (z^.class < Nconst) OR (f = String) THEN z := NewOp(op, typ, z)
					ELSE err(127)
					END ;
					z^.typ := OPT.linttyp
			| cc: (*SYSTEM.CC*)
					IF (f IN intSet) & (z^.class = Nconst) THEN
						IF (0 <= z^.conval^.intval) & (z^.conval^.intval <= OPM.MaxCC) THEN z := NewOp(op, typ, z) ELSE err(219) END
					ELSE err(69)
					END ;
					z^.typ := OPT.booltyp
			| get8:
					z := NewOp(op, OPT.sinttyp, z)
			| get16:
					z := NewOp(op, OPT.inttyp, z)
			| get32:
					z := NewOp(op, OPT.linttyp, z)
			| type:
					OPT.MarkType(z.typ);
					z := NewOp(op, OPT.linttyp, z)
			END
		END ;
		x := z
	END MOp;

	PROCEDURE CheckPtr(VAR x, y: OPT.Node);
		VAR g: INTEGER; p, q, t: OPT.Struct;
	BEGIN g := y^.typ^.form;	(* x.typ # y.typ , x is pointer, otherwise it wouldn't enter here! *)
		IF g = Pointer THEN
			p := x^.typ^.BaseTyp; q := y^.typ^.BaseTyp;
			IF (x.typ = OPT.ptrtyp) OR (y.typ = OPT.ptrtyp) THEN (* allowed *)
			ELSIF (p^.comp = Record) & (q^.comp = Record) THEN
				IF p^.extlev < q^.extlev THEN t := p; p := q; q := t END ;
				WHILE (p # q) & (p # NIL) & (p # OPT.undftyp) DO p := p^.BaseTyp END ;
				IF p = NIL THEN err(100) END
			ELSE err(100)
			END
		ELSIF x.typ.BaseTyp.comp IN ArraySet THEN
			IF y.typ.comp IN ArraySet THEN DeRef(x)
			ELSIF y.typ.form = String THEN DeRef(x)
			ELSIF g = NilTyp THEN (* allow nil test *)
			ELSE err(100)
			END
		ELSIF (y.typ.comp = Record) & (y.obj # NIL) & (y.obj.name = "@SELF") THEN err(170)
		ELSIF g # NilTyp THEN err(100)
		END
	END CheckPtr;
	
	PROCEDURE CheckParameters*(fp, ap: OPT.Object; checkNames: BOOLEAN);
		VAR ft, at: OPT.Struct;
	BEGIN
		WHILE fp # NIL DO
			IF ap # NIL THEN
				ft := fp^.typ; at := ap^.typ;
				IF ft.sysflag # at.sysflag THEN
					err(115)
				END;
				WHILE (ft^.comp = OpenArr) & (at^.comp = OpenArr) DO
					ft := ft^.BaseTyp; at := at^.BaseTyp
				END ;
				IF ft # at THEN
					IF (ft^.form = ProcTyp) & (at^.form = ProcTyp) THEN
						IF ft^.BaseTyp = at^.BaseTyp THEN CheckParameters(ft^.link, at^.link, FALSE)
						ELSE err(117)
						END
					ELSE err(115)
					END
				END ;
				IF (fp^.mode # ap^.mode) OR checkNames & (fp^.name # ap^.name) THEN err(115) END ;
				ap := ap^.link
			ELSE err(116)
			END ;
			fp := fp^.link
		END ;
		IF ap # NIL THEN err(116) END
	END CheckParameters;

	PROCEDURE CheckProc(x: OPT.Struct; y: OPT.Object);	(* proc var x := proc y, check compatibility *)
	BEGIN
		IF (x.sysflag = delegate) & (y.mode = TProc) THEN
			IF x^.BaseTyp = y^.typ THEN CheckParameters(x^.link, y^.link.link, FALSE)
			ELSE err(117)
			END;
			IF y.sysflag # 0 THEN err(113) END
		ELSE
			IF y^.mode IN {XProc, IProc, LProc} THEN
				IF y^.mode = LProc THEN
					IF y^.mnolev = 0 THEN y^.mode := XProc
					ELSE err(73)
					END
				END ;
				IF x^.BaseTyp = y^.typ THEN CheckParameters(x^.link, y^.link, FALSE)
				ELSE err(117)
				END;
				IF (x.sysflag = delegate) THEN
					IF y.sysflag # 0 THEN err(113) END
				ELSIF x.sysflag # y.sysflag THEN
					IF x.sysflag # 0 THEN
						err(113)
					ELSIF y.sysflag = cdecl THEN
						err(113)
					END
				END
			ELSE err(113)
			END
		END
	END CheckProc;

	PROCEDURE ConstOp(op: INTEGER; x, y: OPT.Node);
		VAR f, g: INTEGER; xval, yval: OPT.Const; xv, yv: LONGINT;
				temp: BOOLEAN; (* temp avoids err 215 *)

		PROCEDURE ConstCmp(): INTEGER;
			VAR res: INTEGER;
		BEGIN
			CASE f OF
			  Undef:
					res := eql
			| Byte, Char..LInt:
					IF xval^.intval < yval^.intval THEN res := lss
					ELSIF xval^.intval > yval^.intval THEN res := gtr
					ELSE res := eql
					END
			| Real, LReal:
					IF xval^.realval < yval^.realval THEN res := lss
					ELSIF xval^.realval > yval^.realval THEN res := gtr
					ELSE res := eql
					END
			| Bool:
					IF xval^.intval # yval^.intval THEN res := neq
					ELSE res := eql
					END
			| Set:
					IF xval^.setval # yval^.setval THEN res := neq
					ELSE res := eql
					END
			| String:
					IF xval^.ext^ < yval^.ext^ THEN res := lss
					ELSIF xval^.ext^ > yval^.ext^ THEN res := gtr
					ELSE res := eql
					END
			| NilTyp, Pointer, ProcTyp:
					IF xval^.intval # yval^.intval THEN res := neq
					ELSE res := eql
					END
			END ;
			x^.typ := OPT.booltyp; RETURN res
		END ConstCmp;

	BEGIN
		f := x^.typ^.form; g := y^.typ^.form; xval := x^.conval; yval := y^.conval;
		IF f # g THEN
			CASE f OF
			  Char:
					IF g = String THEN CharToString(x)
					ELSE err(100); y^.typ := x^.typ; yval^ := xval^
					END ;
			| SInt:
					IF g IN intSet THEN x^.typ := y^.typ
					ELSIF g = Real THEN x^.typ := OPT.realtyp; xval^.realval := xval^.intval
					ELSIF g = LReal THEN x^.typ := OPT.lrltyp; xval^.realval := xval^.intval
					ELSE  err(100); y^.typ := x^.typ; yval^ := xval^
					END
			| Int:
					IF g = SInt THEN y^.typ := OPT.inttyp
					ELSIF g IN intSet THEN x^.typ := y^.typ
					ELSIF g = Real THEN x^.typ := OPT.realtyp; xval^.realval := xval^.intval
					ELSIF g = LReal THEN x^.typ := OPT.lrltyp; xval^.realval := xval^.intval
					ELSE  err(100); y^.typ := x^.typ; yval^ := xval^
					END
			| LInt:
					IF g IN intSet THEN y^.typ := OPT.linttyp
					ELSIF g = Real THEN x^.typ := OPT.realtyp; xval^.realval := xval^.intval
					ELSIF g = LReal THEN x^.typ := OPT.lrltyp; xval^.realval := xval^.intval
					ELSE  err(100); y^.typ := x^.typ; yval^ := xval^
					END
			| Real:
					IF g IN intSet THEN y^.typ := x^.typ; yval^.realval := yval^.intval
					ELSIF g = LReal THEN x^.typ := OPT.lrltyp
					ELSE  err(100); y^.typ := x^.typ; yval^ := xval^
					END
			| LReal:
					IF g IN intSet THEN y^.typ := x^.typ; yval^.realval := yval^.intval
					ELSIF g = Real THEN y^.typ := OPT.lrltyp
					ELSE  err(100); y^.typ := x^.typ; yval^ := xval^
					END
			| String:
					IF g = Char THEN CharToString(y); g := String
					ELSE err(100); y^.typ := x^.typ; yval^ := xval^
					END ;
			| NilTyp:
					IF ~(g IN {Pointer, ProcTyp}) THEN err(100) END
			| Pointer:
					CheckPtr(x, y)
			| ProcTyp:
					IF g # NilTyp THEN err(100) END
			ELSE err(100); y^.typ := x^.typ; yval^ := xval^
			END ;
			f := x^.typ^.form
		END ;	(* {x^.typ = y^.typ} *)
		CASE op OF
		  times:
				IF f IN intSet THEN xv := xval^.intval; yv := yval^.intval;
					IF (xv = 0) OR (yv = 0) OR	(* division with negative numbers is not defined *)
						(xv > 0) & (yv > 0) & (yv <= MAX(LONGINT) DIV xv) OR
						(xv > 0) & (yv < 0) & (yv >= MIN(LONGINT) DIV xv) OR
						(xv < 0) & (yv > 0) & (xv >= MIN(LONGINT) DIV yv) OR
						(xv < 0) & (yv < 0) & (xv # MIN(LONGINT)) & (yv # MIN(LONGINT)) & (-xv <= MAX(LONGINT) DIV (-yv)) THEN
						xval^.intval := xv * yv; SetIntType(x)
					ELSE err(204)
					END
				ELSIF f IN realSet THEN
					temp := ABS(yval^.realval) <= 1.0;
					IF temp OR (ABS(xval^.realval) <= MAX(LONGREAL) / ABS(yval^.realval)) THEN
						xval^.realval := xval^.realval * yval^.realval; CheckRealType(f, 204, xval)
					ELSE err(204)
					END
				ELSIF f = Set THEN
					xval^.setval := xval^.setval * yval^.setval
				ELSIF f # Undef THEN err(101)
				END
		| slash:
				IF f IN intSet THEN
					IF yval^.intval # 0 THEN
						xval^.realval := xval^.intval / yval^.intval; CheckRealType(Real, 205, xval)
					ELSE err(205); xval^.realval := 1.0
					END ;
					x^.typ := OPT.realtyp
				ELSIF f IN realSet THEN
					temp := ABS(yval^.realval) >= 1.0;
					IF temp OR (ABS(xval^.realval) <= MAX(LONGREAL) * ABS(yval^.realval)) THEN
						xval^.realval := xval^.realval / yval^.realval; CheckRealType(f, 205, xval)
					ELSE err(205)
					END
				ELSIF f = Set THEN
					xval^.setval := xval^.setval / yval^.setval
				ELSIF f # Undef THEN err(102)
				END
		| div:
				IF f IN intSet THEN
					IF yval^.intval # 0 THEN
						xval^.intval := xval^.intval DIV yval^.intval; SetIntType(x)
					ELSE err(205)
					END
				ELSIF f # Undef THEN err(103)
				END
		| mod:
				IF f IN intSet THEN
					IF yval^.intval # 0 THEN
						xval^.intval := xval^.intval MOD yval^.intval; SetIntType(x)
					ELSE err(205)
					END
				ELSIF f # Undef THEN err(104)
				END
		| and:
				IF f = Bool THEN
					xval^.intval := BoolToInt(IntToBool(xval^.intval) & IntToBool(yval^.intval))
				ELSE err(94)
				END
		| plus:
				IF f IN intSet THEN
					temp := (yval^.intval >= 0) & (xval^.intval <= MAX(LONGINT) - yval^.intval);
					IF temp OR (yval^.intval < 0) & (xval^.intval >= MIN(LONGINT) - yval^.intval) THEN 
							INC(xval^.intval, yval^.intval); SetIntType(x)
					ELSE err(206)
					END
				ELSIF f IN realSet THEN
					temp := (yval^.realval >= 0.0) & (xval^.realval <= MAX(LONGREAL) - yval^.realval);
					IF temp OR (yval^.realval < 0.0) & (xval^.realval >= -MAX(LONGREAL) - yval^.realval) THEN
							xval^.realval := xval^.realval + yval^.realval; CheckRealType(f, 206, xval)
					ELSE err(206)
					END
				ELSIF f = Set THEN
					xval^.setval := xval^.setval + yval^.setval
				ELSIF f # Undef THEN err(105)
				END
		| minus:
				IF f IN intSet THEN
					IF (yval^.intval >= 0) & (xval^.intval >= MIN(LONGINT) + yval^.intval) OR
						(yval^.intval < 0) & (xval^.intval <= MAX(LONGINT) + yval^.intval) THEN 
							DEC(xval^.intval, yval^.intval); SetIntType(x)
					ELSE err(207)
					END
				ELSIF f IN realSet THEN
					temp := (yval^.realval >= 0.0) & (xval^.realval >= -MAX(LONGREAL) + yval^.realval);
					IF temp OR (yval^.realval < 0.0) & (xval^.realval <= MAX(LONGREAL) + yval^.realval) THEN
							xval^.realval := xval^.realval - yval^.realval; CheckRealType(f, 207, xval)
					ELSE err(207)
					END
				ELSIF f = Set THEN
					xval^.setval := xval^.setval - yval^.setval
				ELSIF f # Undef THEN err(106)
				END
		| or:
				IF f = Bool THEN
					xval^.intval := BoolToInt(IntToBool(xval^.intval) OR IntToBool(yval^.intval))
				ELSE err(95)
				END
		| eql:
				xval^.intval := BoolToInt(ConstCmp() = eql)
		| neq:
				xval^.intval := BoolToInt(ConstCmp() # eql)
		| lss:
				IF f IN {Bool, Set, NilTyp, Pointer} THEN err(108)
				ELSE xval^.intval := BoolToInt(ConstCmp() = lss)
				END
		| leq:
				IF f IN {Bool, Set, NilTyp, Pointer} THEN err(108)
				ELSE xval^.intval := BoolToInt(ConstCmp() # gtr)
				END
		| gtr:
				IF f IN {Bool, Set, NilTyp, Pointer} THEN err(108)
				ELSE xval^.intval := BoolToInt(ConstCmp() = gtr)
				END
		| geq:
				IF f IN {Bool, Set, NilTyp, Pointer} THEN err(108)
				ELSE xval^.intval := BoolToInt(ConstCmp() # lss)
				END
		END
	END ConstOp;

	PROCEDURE Convert(VAR x: OPT.Node; typ: OPT.Struct);
		VAR node: OPT.Node; f, g: INTEGER; k: LONGINT; r: LONGREAL;
	BEGIN f := x^.typ^.form; g := typ^.form;
		IF x^.class = Nconst THEN
			IF f IN intSet THEN
				IF g IN intSet THEN
					IF f > g THEN SetIntType(x);
						IF x^.typ^.form > g THEN err(203); x^.conval^.intval := 1 END
					END
				ELSIF g IN realSet THEN x^.conval^.realval := x^.conval^.intval; x^.conval^.intval := OPM.ConstNotAlloc
				ELSE (*g = Char*) k := x^.conval^.intval;
					IF (0 > k) OR (k > 0FFH) THEN err(220) END
				END
			ELSIF f IN realSet THEN
				IF g IN realSet THEN CheckRealType(g, 203, x^.conval)
				ELSE (*g = LInt*)
					r := x^.conval^.realval;
					IF (r < MIN(LONGINT)) OR (r > MAX(LONGINT)) THEN err(203); r := 1 END ;
					x^.conval^.intval := ENTIER(r); SetIntType(x)
				END
			ELSE (* (f IN {Char, Byte}) & (g IN {Byte} + intSet) OR (f = Undef) *)
			END ;
			x^.obj := NIL
		ELSIF (x^.class = Nmop) & (x^.subcl = conv) & ((x^.left^.typ^.form < f) OR (f > g)) THEN
			(* don't create new node *)
			IF x^.left^.typ = typ THEN (* and suppress existing node *) x := x^.left END
		ELSE node := OPT.NewNode(Nmop); node^.subcl := conv; node^.left := x; x := node
		END ;
		x^.typ := typ
	END Convert;

	PROCEDURE Val(VAR x: OPT.Node;  typ: OPT.Struct);	(*SYSTEM.VAL, change type, no convertion only projection*)
	VAR  t: OPT.Node;  f: INTEGER;  r, rr: REAL; tmp: ARRAY 4 OF BYTE; l: LONGINT;
	BEGIN
		f := x.typ.form;
		IF (x^.class = Ntype) OR (x^.class = Nproc) OR
			(f IN {Undef, String, NoTyp}) THEN err(126)
		END ;
		IF (x^.class = Nconst) & (typ.comp = Basic) THEN
			IF (typ.form = Real) & (f IN intSet) THEN
  			BYTES(tmp, x.conval.intval); NUMBER(rr, tmp);
				x := NewRealConst(rr, typ);
			ELSIF (typ.form IN intSet) & (f = Real) THEN
				r := SHORT(x.conval.realval);  BYTES(tmp, r); NUMBER(l, tmp); x := NewIntConst(l)
			ELSIF (typ.form IN {SInt, Int}) & (f IN intSet) THEN	(*force sign extension*)
				IF typ.form = SInt THEN
					x := NewIntConst (SHORT(SHORT(x.conval.intval)))
				ELSIF typ.form = Int THEN
					x := NewIntConst (SHORT(x.conval.intval))
				END
			ELSIF (typ.form IN intSet) & (f = Set) THEN
				x.conval.intval := ORD(x.conval.setval)
			ELSIF (typ.form = Set) & (f IN intSet) THEN
				x.conval.setval := BITS(x.conval.intval)
			ELSE
				t := OPT.NewNode(Nmop); t^.subcl := val; t^.left := x; x := t
			END
		ELSIF (x^.class >= Nconst) THEN
			t := OPT.NewNode(Nmop); t^.subcl := val; t^.left := x; x := t
		ELSE
			IF (f IN realSet) THEN
				IF (typ^.form IN realSet) THEN x^.readonly := FALSE
				ELSE t := OPT.NewNode(Nmop); t^.subcl := val; t^.left := x; x := t
				END
			ELSIF (typ^.form IN realSet) THEN t := OPT.NewNode(Nmop); t^.subcl := val; t^.left := x; x := t
			ELSIF OPM.OptimizeSelf & (typ.sysflag = delegate) & (typ^.form = ProcTyp) & (f # ProcTyp) THEN t := OPT.NewNode(Nmop); t^.subcl := val; t^.left := x; x := t
			ELSE x^.readonly := FALSE
			END
		END ;
		x.typ := typ
	END Val;
	
	PROCEDURE Op*(op: SHORTINT; VAR x: OPT.Node; y: OPT.Node);
		VAR f, g: INTEGER; t, z: OPT.Node; typ: OPT.Struct; do: BOOLEAN; val: LONGINT;

		PROCEDURE NewOp(op: SHORTINT; typ: OPT.Struct; VAR x: OPT.Node; y: OPT.Node);
			VAR node: OPT.Node;
		BEGIN
			node := OPT.NewNode(Ndop); node^.subcl := op; node^.typ := typ;
			node^.left := x; node^.right := y; x := node
		END NewOp;

		PROCEDURE strings(VAR x, y: OPT.Node): BOOLEAN;
			VAR ok, xCharArr, yCharArr: BOOLEAN;
		BEGIN
			xCharArr := ((x^.typ^.comp IN ArraySet) & (x^.typ^.BaseTyp^.form=Char)) OR (f=String);
			yCharArr := (((y^.typ^.comp IN ArraySet) & (y^.typ^.BaseTyp^.form=Char)) OR (g=String));
			IF xCharArr & (g = Char) & (y^.class = Nconst) THEN CharToString(y); g := String; yCharArr := TRUE END ;
			IF yCharArr & (f = Char) & (x^.class = Nconst) THEN CharToString(x); f := String; xCharArr := TRUE END ;
			ok := xCharArr & yCharArr;
			IF ok THEN	(* replace ""-string compare with 0X-char compare, if possible *)
				IF (f=String) & (x^.conval^.intval2 = 1) THEN	(* y is array of char *)
					x^.typ := OPT.chartyp; x^.conval^.intval := 0;
					Index(y, NewIntConst(0))
				ELSIF (g=String) & (y^.conval^.intval2 = 1) THEN	(* x is array of char *)
					y^.typ := OPT.chartyp; y^.conval^.intval := 0;
					Index(x, NewIntConst(0))
				END
			END ;
			RETURN ok
		END strings;

	BEGIN z := x;
		IF (z^.class = Ntype) OR (z^.class = Nproc) OR (y^.class = Ntype) OR (y^.class = Nproc) THEN err(126)
		ELSIF (z.class = Nfield) & (z.obj.mode = TProc) OR (y.class = Nfield) & (y.obj.mode = TProc) THEN err(100)
		ELSIF (z^.class = Nconst) & (y^.class = Nconst) THEN ConstOp(op, z, y); z^.obj := NIL
		ELSE
			IF z^.typ # y^.typ THEN
				g := y^.typ^.form;
				CASE z^.typ^.form OF
				   Char: IF z^.class = Nconst THEN CharToString(z) ELSE err(100) END
				| SInt:
						IF g IN intSet + realSet THEN Convert(z, y^.typ)
						ELSE  err(100)
						END
				| Int:
						IF g = SInt THEN Convert(y, z^.typ)
						ELSIF g IN intSet + realSet THEN Convert(z, y^.typ)
						ELSE  err(100)
						END
				| LInt:
						IF g IN intSet THEN Convert(y, z^.typ)
						ELSIF g IN realSet THEN Convert(z, y^.typ)
						ELSE  err(100)
						END
				| Real:
						IF g IN intSet THEN Convert(y, z^.typ)
						ELSIF g IN realSet THEN Convert(z, y^.typ)
						ELSE  err(100)
						END
				| LReal:
						IF g IN intSet + realSet THEN Convert(y, z^.typ)
						ELSIF g IN realSet THEN Convert(y, z^.typ)
						ELSE  err(100)
						END
				| NilTyp:
						IF ~(g IN {Pointer, ProcTyp}) THEN err(100) END
				| Pointer:
						CheckPtr(z, y)
				| ProcTyp:
						IF g # NilTyp THEN err(100) END
				| String:
				| Comp:
						IF z^.typ^.comp = Record THEN
							IF (g = Pointer) & (z.obj # NIL) & (z.obj.name = "@SELF") THEN err(170) ELSE err(100) END
						END
				ELSE err(100)
				END
			END ;	(* {z^.typ = y^.typ} *)
			typ := z^.typ; f := typ^.form; g := y^.typ^.form;
			CASE op OF
			  times:
					do := TRUE;
					IF f IN intSet THEN
						IF z^.class = Nconst THEN val := z^.conval^.intval;
							IF val = 1 THEN do := FALSE; z := y
							ELSIF val = 0 THEN do := FALSE
							ELSIF log(val) = 1 THEN
								t := y; y := z; z := t;
								op := ash; y^.typ := OPT.sinttyp; y^.conval^.intval := exp; y^.obj := NIL
							END
						ELSIF y^.class = Nconst THEN val := y^.conval^.intval;
							IF val = 1 THEN do := FALSE
							ELSIF val = 0 THEN do := FALSE; z := y
							ELSIF (log(val) = 1) & ~(ovflchk IN OPM.options) THEN
								op := ash; y^.typ := OPT.sinttyp; y^.conval^.intval := exp; y^.obj := NIL
							END
						END
					ELSIF ~(f IN {Undef, Real..Set}) THEN err(105); typ := OPT.undftyp
					END ;
					IF do THEN NewOp(op, typ, z, y) END
			| slash:
					IF f IN intSet THEN
						IF (y^.class = Nconst) & (y^.conval^.intval = 0) THEN err(205) END ;
						Convert(z, OPT.realtyp); Convert(y, OPT.realtyp);
						typ := OPT.realtyp
					ELSIF f IN realSet THEN
						IF (y^.class = Nconst) & (y^.conval^.realval = 0.0) THEN err(205) END
					ELSIF (f # Set) & (f # Undef) THEN err(102); typ := OPT.undftyp
					END ;
					NewOp(op, typ, z, y)
			| div:
					do := TRUE;
					IF f IN intSet THEN
						IF y^.class = Nconst THEN val := y^.conval^.intval;
							IF val = 0 THEN err(205)
							ELSIF val = 1 THEN do := FALSE
							ELSIF log(val) = 1 THEN
								op := ash; y^.typ := OPT.sinttyp; y^.conval^.intval := -exp; y^.obj := NIL
							END
						END
					ELSIF f # Undef THEN err(103); typ := OPT.undftyp
					END ;
					IF do THEN NewOp(op, typ, z, y) END
			| mod:
					IF f IN intSet THEN
						IF y^.class = Nconst THEN
							IF y^.conval^.intval = 0 THEN err(205)
							ELSIF y^.conval^.intval = 1 THEN               (* <== optimize x MOD 1 = 0 *)
								x := OPT.NewNode(Nconst); x^.typ := typ;
								x^.conval := OPT.NewConst(); x^.conval^.intval := 0;
								RETURN
							ELSIF log(y^.conval^.intval) = 1 THEN
								op := msk; y^.conval^.intval := ASH(-1, exp); y^.obj := NIL
							END
						END
					ELSIF f # Undef THEN err(104); typ := OPT.undftyp
					END ;
					NewOp(op, typ, z, y)
			| and:
					IF f = Bool THEN
						IF z^.class = Nconst THEN
							IF IntToBool(z^.conval^.intval) THEN z := y END
						ELSIF (y^.class = Nconst) & IntToBool(y^.conval^.intval) THEN (* optimize z & TRUE -> z *)
				(*	ELSIF (y^.class = Nconst) & ~IntToBool(y^.conval^.intval) THEN
							don't optimize z & FALSE -> FALSE: side effects possible	*)
						ELSE NewOp(op, typ, z, y)
						END
					ELSIF f # Undef THEN err(94); z^.typ := OPT.undftyp
					END
			| plus:
					IF ~(f IN {Undef, SInt..Set}) THEN err(105); typ := OPT.undftyp END ;
					do := TRUE;
					IF f IN intSet THEN
						IF (z^.class = Nconst) & (z^.conval^.intval = 0) THEN do := FALSE; z := y END ;
						IF (y^.class = Nconst) & (y^.conval^.intval = 0) THEN do := FALSE END
					END ;
					IF do THEN NewOp(op, typ, z, y) END
			| minus:
					IF ~(f IN {Undef, SInt..Set}) THEN err(106); typ := OPT.undftyp END ;
					IF ~(f IN intSet) OR (y^.class # Nconst) OR (y^.conval^.intval # 0) THEN NewOp(op, typ, z, y) END
			| or:
					IF f = Bool THEN
						IF z^.class = Nconst THEN
							IF ~IntToBool(z^.conval^.intval) THEN z := y END
						ELSIF (y^.class = Nconst) & ~IntToBool(y^.conval^.intval) THEN (* optimize z OR FALSE -> z *)
				(*	ELSIF (y^.class = Nconst) & IntToBool(y^.conval^.intval) THEN
							don't optimize z OR TRUE -> TRUE: side effects possible	*)
						ELSE NewOp(op, typ, z, y)
						END
					ELSIF f # Undef THEN err(95); z^.typ := OPT.undftyp
					END
			| eql, neq:
					IF (f IN {Undef..Set, NilTyp, Pointer, ProcTyp}) OR strings(z, y) THEN typ := OPT.booltyp
					ELSE err(107); typ := OPT.undftyp
					END ;
					NewOp(op, typ, z, y)
			| lss, leq, gtr, geq:
					IF (f IN {Undef, Char..LReal}) OR strings(z, y) THEN typ := OPT.booltyp
					ELSE err(108); typ := OPT.undftyp
					END ;
					NewOp(op, typ, z, y)
			END
		END ;
		x := z
	END Op;

	PROCEDURE SetRange*(VAR x: OPT.Node; y: OPT.Node);
		VAR k, l: LONGINT;
	BEGIN
		IF (x^.class = Ntype) OR (x^.class = Nproc) OR (y^.class = Ntype) OR (y^.class = Nproc) THEN err(126)	
		ELSIF (x^.typ^.form IN intSet) & (y^.typ^.form IN intSet) THEN
			IF x^.class = Nconst THEN
				k := x^.conval^.intval;
				IF (0 > k) OR (k > OPM.MaxSet) THEN err(202) END
			END ;
			IF y^.class = Nconst THEN
				l := y^.conval^.intval;
				IF (0 > l) OR (l > OPM.MaxSet) THEN err(202) END
			END ;
			IF (x^.class = Nconst) & (y^.class = Nconst) THEN
				IF k <= l THEN
					x^.conval^.setval := {k..l}
				ELSE err(201); x^.conval^.setval := {l..k}
				END ;
				x^.obj := NIL
			ELSE BindNodes(Nupto, OPT.settyp, x, y)
			END
		ELSE err(93)
		END ;
		x^.typ := OPT.settyp
	END SetRange;

	PROCEDURE SetElem*(VAR x: OPT.Node);
		VAR k: LONGINT;
	BEGIN
		IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
		ELSIF ~(x^.typ^.form IN intSet) THEN err(93)
		ELSIF x^.class = Nconst THEN
			k := x^.conval^.intval;
			IF (0 <= k) & (k <= OPM.MaxSet) THEN x^.conval^.setval := {k}
			ELSE err(202)
			END ;
			x^.obj := NIL
		ELSE Convert(x, OPT.settyp)
		END ;
		x^.typ := OPT.settyp
	END SetElem;
	
	PROCEDURE CheckAssign(x: OPT.Struct; ynode: OPT.Node);	(* x := y *)
		VAR f, g: INTEGER; y, p, q: OPT.Struct;
	BEGIN
		y := ynode^.typ; f := x^.form; g := y^.form;
		IF (ynode^.class = Ntype) OR (ynode^.class = Nproc) & (f # ProcTyp) THEN err(126) 
		ELSIF (ynode.class = Nfield) & (ynode.obj.mode = TProc) & (f # ProcTyp) THEN err(OPS.lparen)
		END ;
		CASE f OF
		  Undef, String:
		| Byte:
				IF ~(g IN {Byte, Char, SInt}) THEN err(113) END
		| Bool, Char, SInt, Set, HInt:
				IF g # f THEN err(113) END
		| Int:
				IF ~(g IN {SInt, Int}) THEN err(113) END
		| LInt:
				IF ~(g IN intSet) THEN err(113) END
		| Real:
				IF ~(g IN {SInt..Real}) THEN err(113) END
		| LReal:
				IF ~(g IN {SInt..LReal}) THEN err(113) END
		| Pointer:
				IF (x = y) OR (g = NilTyp) OR (x = OPT.ptrtyp) & (g = Pointer) THEN (* ok *)
				ELSIF g = Pointer THEN
					p := x^.BaseTyp; q := y^.BaseTyp;
					IF (p^.comp = Record) & (q^.comp = Record) THEN
						WHILE (q # p) & (q # NIL) & (q # OPT.undftyp) DO q := q^.BaseTyp END ;
						IF q = NIL THEN err(113) END
					ELSE err(113)
					END
				ELSIF (y.comp = Record) & (ynode.obj # NIL) & (ynode.obj.name = "@SELF") THEN err(170)
				ELSE err(113)
				END
		| ProcTyp:
				IF ynode^.class = Nproc THEN CheckProc(x, ynode^.obj)
				ELSIF (x = y) OR (g = NilTyp) THEN (* ok *)
				ELSIF OPM.OptimizeSelf & (x.sysflag = delegate) & (ynode^.class = Nfield) THEN CheckProc(x, ynode^.obj)
				ELSE err(113)
				END
		| NoTyp, NilTyp:
				err(113)
		| Comp:
				OPT.MarkType(x);
				IF x^.comp = StaticArr THEN
					IF (ynode^.class = Nconst) & (g = Char) THEN CharToString(ynode); y := ynode^.typ; g := String END ;
					IF x = y THEN (* ok *)
					ELSIF (ynode.typ.form=Pointer) & (x=ynode.typ.BaseTyp) THEN (* ok *)
					ELSIF (g = String) & (x^.BaseTyp = OPT.chartyp) THEN (*check length of string*)
						IF ynode^.conval^.intval2 > x^.n THEN err(114) END ;
					ELSE err(113)
					END
				ELSIF (x^.comp IN {SDynArr, DynArr}) THEN
					IF x # y THEN err(113)  END
				ELSIF x^.comp = Record THEN
					IF x = y THEN (* ok *)
					ELSIF y^.comp = Record THEN
						q := y^.BaseTyp;
						WHILE (q # NIL) & (q # x) & (q # OPT.undftyp) DO q := q^.BaseTyp END ;
						IF q = NIL THEN err(113) END
					ELSE err(113)
					END
				ELSE (*DynArr*) err(113)
				END
		END ;
		IF (ynode^.class = Nconst) & (g < f) & (g IN {SInt..Real}) & (f IN {Int..LReal}) THEN
			Convert(ynode, x)
		END
	END CheckAssign;
	
	PROCEDURE CheckLeaf(x: OPT.Node; dynArrToo: BOOLEAN);
	VAR obj: OPT.Object;
	BEGIN
		IF (x^.class = Nmop) & (x^.subcl = val) THEN x := x^.left END ;
		IF x^.class = Nguard THEN x := x^.left END ;	(* skip last (and unique) guard *)
		IF (x.class = Nvar) & (dynArrToo OR (x.typ.comp # OpenArr)) THEN 
			obj := x.obj;
			WHILE obj # NIL DO obj.leaf := FALSE;  obj := obj.scope END
		END 
	END CheckLeaf;

	PROCEDURE StPar0*(VAR par0: OPT.Node; fctno: INTEGER);	(* par0: first param of standard proc *)
		VAR f: INTEGER; t, ptr, typ: OPT.Struct; x: OPT.Node;
	BEGIN x := par0; f := x^.typ^.form;
		CASE fctno OF
		  haltfn, shalt: (*HALT*)
				IF (f IN intSet) & (x^.class = Nconst) THEN
					IF (fctno = shalt) OR (OPM.MinHaltNr <= x^.conval^.intval) & (x^.conval^.intval <= OPM.MaxHaltNr) THEN
						BindNodes(Ntrap, OPT.notyp, x, x)
					ELSE err(218)
					END
				ELSE err(69)
				END ;
				x^.typ := OPT.notyp
		| typefn:
				IF (x.class # Ntype) OR (x.typ.comp # Record) & ((f # Pointer) OR (x.typ.BaseTyp.comp # Record)) THEN  err(53)
				ELSE MOp(type, x) END;
		| newfn: (*NEW*)
				typ := OPT.notyp; InitPar := NIL;
				IF NotVar(x) THEN err(112)
				ELSIF (f = Pointer) OR (x.typ.comp = DynArr) THEN
					IF OPM.NEWusingAdr THEN CheckLeaf(x, TRUE) END ;
					IF x^.readonly THEN err(76) END;
					f := x^.typ^.BaseTyp^.comp;
					IF (f IN {Record, DynArr, OpenArr, StaticArr}) OR (x.typ.comp = DynArr) THEN
						IF x.typ.comp = DynArr THEN
							typ := x.typ
						ELSIF f # Record THEN
							typ:=x.typ.BaseTyp
						END;
						t := x.typ; ptr := NIL;	(* check if type needs and has a type desc *)
						WHILE (t.form = Pointer) OR (t.comp IN ArraySet) DO
							IF t.form = Pointer THEN ptr := t END;
							t := t.BaseTyp
						END;
						IF (t.mno # 0) & (t.comp = Record) THEN
							IF (t.strobj.vis # internal) OR (OPT.typeVisible IN t.strobj.flag) THEN
								(*ok*)
							ELSIF (ptr # NIL) & (ptr.BaseTyp = t) & (ptr.mno # 0) & (ptr.strobj.vis # internal) OR (OPT.typeVisible IN ptr.strobj.flag) THEN
								(*ok*)
							ELSE	
								err(200)	(* invisible -> td not accessible *)
							END
						END;
						OPT.MarkType(x.typ);
						BindNodes(Nassign, OPT.notyp, x, NIL); x^.subcl := SHORT(fctno);
						IF (f = Record) & (x^.left^.typ^.BaseTyp^.strobj # NIL) THEN	(* set the initialiser parameter list *)
							(* Pre: typ(x) = POINTER TO RECORD *)
							t := x^.left^.typ^.BaseTyp;
							WHILE (t#NIL) & (t.strobj.link2=NIL) DO t := t.BaseTyp END;
							IF t # NIL THEN InitPar := t.strobj.link2 ELSE InitPar := NIL END;
							IF InitPar # NIL THEN
								CopyAndSubst(par0, x^.left);			(* make a copy of the object, this is the SELF for the call *)
								(* par0 is a pointer, but the hidden self parameter can be a VAR x: Record !! *)
								IF InitPar.link.typ.comp = Record THEN		(* deref par0 *)
									DeRef (par0)
								END;
								par0^.link := OPT.NewNode(Nproc); par0^.link^.obj := InitPar; par0^.link^.typ := InitPar^.typ;
								InitPar := InitPar^.link^.link;	(* parameter list, skip the SELF, the list is in reverse order *)
								x^.left^.link := par0;
							END
						END
					ELSE err(111)
					END
				ELSE err(111)
				END ;
				x^.typ := typ
		| absfn: (*ABS*)
				MOp(abs, x)
		| capfn: (*CAP*)
				MOp(cap, x)
		| ordfn: (*ORD*) 
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN {Byte, Char} THEN Convert(x, OPT.inttyp)
				ELSE err(111)
				END ;
				x^.typ := OPT.inttyp
		| entierfn: (*ENTIER*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN realSet THEN Convert(x, OPT.linttyp)
				ELSE err(111)
				END ;
				x^.typ := OPT.linttyp
		| oddfn: (*ODD*)
				MOp(odd, x)
		| minfn: (*MIN*)
				IF x^.class = Ntype THEN
					CASE f OF
					  Bool:  x := NewBoolConst(FALSE)
					| Char:  x := NewIntConst(0); x^.typ := OPT.chartyp
					| SInt:  x := NewIntConst(OPM.MinSInt)
					| Int:   x := NewIntConst(OPM.MinInt)
					| LInt:  x := NewIntConst(OPM.MinLInt)
					| Set:   x := NewIntConst(0); x^.typ := OPT.inttyp
					| Real:  x := NewRealConst(OPM.MinReal, OPT.realtyp)
					| LReal: x := NewRealConst(OPM.MinLReal, OPT.lrltyp)
					ELSE err(111)
					END
				ELSE err(110)
				END
		| maxfn: (*MAX*)
				IF x^.class = Ntype THEN
					CASE f OF
					  Bool:  x := NewBoolConst(TRUE)
					| Char:  x := NewIntConst(0FFH); x^.typ := OPT.chartyp
					| SInt:  x := NewIntConst(OPM.MaxSInt)
					| Int:   x := NewIntConst(OPM.MaxInt)
					| LInt:  x := NewIntConst(OPM.MaxLInt)
					| Set:   x := NewIntConst(OPM.MaxSet); x^.typ := OPT.inttyp
					| Real:  x := NewRealConst(OPM.MaxReal, OPT.realtyp)
					| LReal: x := NewRealConst(OPM.MaxLReal, OPT.lrltyp)
					ELSE err(111)
					END
				ELSE err(110)
				END
		| chrfn: (*CHR*) 
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN {Undef, Byte, SInt..LInt} THEN Convert(x, OPT.chartyp)
				ELSE err(111); x^.typ := OPT.chartyp
				END
		| shortfn: (*SHORT*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f = Int THEN Convert(x, OPT.sinttyp)
				ELSIF f = LInt THEN Convert(x, OPT.inttyp)
				ELSIF f = LReal THEN Convert(x, OPT.realtyp)
				ELSE err(111)
				END
		| longfn: (*LONG*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f = SInt THEN Convert(x, OPT.inttyp)
				ELSIF f = Int THEN Convert(x, OPT.linttyp)
				ELSIF f = Real THEN Convert(x, OPT.lrltyp)
				ELSIF f = Char THEN Convert(x, OPT.linttyp)
				ELSE err(111)
				END
		| incfn, decfn: (*INC, DEC*) 
				IF NotVar(x) THEN err(112)
				ELSIF ~(f IN intSet) THEN err(111)
				ELSIF x^.readonly THEN err(76)
				END
		| inclfn, exclfn: (*INCL, EXCL*)
				IF NotVar(x) THEN err(112)
				ELSIF x^.typ # OPT.settyp THEN err(111); x^.typ := OPT.settyp
				ELSIF x^.readonly THEN err(76)
				END
		| lenfn: (*LEN*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126) END;
				IF x.typ.form=Pointer THEN DeRef(x) END;
				IF ~(x^.typ^.comp IN ArraySet) THEN err(131)
(*ELSIF x^.typ.sysflag = notag THEN err(200)*)
				END
		| copyfn: (*COPY*)
				IF (x^.class = Nconst) & (f = Char) THEN CharToString(x); f := String END ;
				IF (x.typ.form=Pointer) THEN DeRef(x) END;
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (~(x^.typ^.comp IN ArraySet) OR (x^.typ^.BaseTyp^.form # Char)) & (f # String) THEN err(111)
(*ELSIF x^.typ.sysflag = notag THEN err(200)*)
				END
		| ashfn: (*ASH*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN intSet THEN
					IF f # LInt THEN Convert(x, OPT.linttyp) END
				ELSE err(111); x^.typ := OPT.linttyp
				END
		| adrfn: (*SYSTEM.ADR*)
				CheckLeaf(x, FALSE);
				IF (x.obj # NIL) & (x.obj.mode = TProc) THEN err(126)
				ELSE MOp(adr, x)
				END
		| sizefn: (*SIZE*)	(* SIZE doesn't work for SDynArr too *)
				IF (f=Pointer)&(x.typ.BaseTyp.comp IN {StaticArr, DynArr, OpenArr}) THEN err(111)
				ELSIF x.typ.comp = DynArr THEN err(111)
				END;
				IF x^.class # Ntype THEN err(110); x := NewIntConst(1)
				ELSIF (f IN {Byte..Set, Pointer, ProcTyp, HInt}) OR (x^.typ^.comp=Record) OR (x.typ.comp=StaticArr) THEN
					typSize(x^.typ, FALSE);
					OPT.MarkType(x.typ);
					x := NewIntConst(x^.typ^.size)
				ELSE err(111); x := NewIntConst(1)
				END
		| ccfn: (*SYSTEM.CC*)
				MOp(cc, x)
		| lshfn, rotfn: (*SYSTEM.LSH, SYSTEM.ROT*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF ~(f IN intSet + {Byte, Char, Set}) THEN err(111)
				END
		| getfn, putfn, bitfn, movefn, get8fn..get32fn, put8fn..put32fn: (*SYSTEM.GET, SYSTEM.PUT, SYSTEM.BIT, SYSTEM.MOVE*)
				IF OPM.WarnUnsafe THEN
					IF (fctno = putfn) OR (fctno = movefn) OR (fctno >= put8fn) & (fctno <= put32fn) THEN err(-666) END
				END;
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (x^.class = Nconst) & (f IN {SInt, Int}) THEN Convert(x, OPT.linttyp)
				ELSIF (f=Pointer) & (x.typ.BaseTyp.comp IN {StaticArr, DynArr, OpenArr}) THEN err(111); x^.typ := OPT.linttyp
				ELSIF ~(f IN {LInt, Pointer}) THEN err(111); x^.typ := OPT.linttyp
				END;
				IF (get8fn<=fctno) & (fctno<=get32fn) THEN  MOp(SHORT(fctno-get8fn+get8), x)  END;
		| getrfn, putrfn: (*SYSTEM.GETREG, SYSTEM.PUTREG*)
				IF OPM.WarnUnsafe THEN
					IF fctno = putrfn THEN err(-666) END
				END;
				IF (f IN intSet) & (x^.class = Nconst) THEN
					IF (x^.conval^.intval < OPM.MinRegNr) OR (x^.conval^.intval > OPM.MaxRegNr) THEN err(220) END
				ELSE err(69)
				END
		| valfn: (*SYSTEM.VAL*)
				IF x^.class # Ntype THEN err(110)
				ELSIF (f IN {Undef, String, NoTyp}) OR (x^.typ^.comp IN {SDynArr, OpenArr}) THEN err(111)
				END;
				IF OPM.WarnUnsafe THEN
					IF f IN {Pointer, ProcTyp, Comp} THEN err(-666) END	(* Comp check is very conservative *)
				END
		| sysnewfn: (*SYSTEM.NEW*)
				IF NotVar(x) THEN err(112)
				ELSIF f = Pointer THEN
					IF OPM.NEWusingAdr THEN CheckLeaf(x, TRUE) END
				ELSE err(111)
				END
		| assertfn: (*ASSERT*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126); x := NewBoolConst(FALSE)
				ELSIF f # Bool THEN err(120); x := NewBoolConst(FALSE)
				ELSE MOp(not, x)
				END
		| poutfn, pinfn:		(* SYSTEM.PORTOUT, SYSTEM.PORTIN *)
				IF OPM.WarnUnsafe THEN err(-666) END;
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (x^.class = Nconst) & (f = LInt) THEN
					IF (x^.conval.intval < 0) OR (x^.conval.intval > 65535) THEN OPM.err(203) END;
					x^.typ := OPT.inttyp
				ELSIF (f IN {LInt, SInt}) THEN Convert(x, OPT.inttyp)
				ELSIF (f IN {Int}) THEN ;
				ELSE err(111); x^.typ := OPT.inttyp
				END
		| awaitfn:
				IF f # Bool THEN err(120) END
		ELSE err(64)
		END ;
		par0 := x
	END StPar0;

	PROCEDURE StPar1*(VAR par0: OPT.Node; x: OPT.Node; fctno: SHORTINT);	(* x: second parameter of standard proc *)
		VAR f, L: INTEGER; typ: OPT.Struct; p, t: OPT.Node; i: LONGINT;
		
		PROCEDURE NewOp(class, subcl: SHORTINT; left, right: OPT.Node): OPT.Node;
			VAR node: OPT.Node;
		BEGIN
			node := OPT.NewNode(class); node^.subcl := subcl;
			node^.left := left; node^.right := right; RETURN node
		END NewOp;
		
	BEGIN p := par0; f := x^.typ^.form;
		CASE fctno OF
		  incfn, decfn: (*INC DEC*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126); p^.typ := OPT.notyp
				ELSE
					IF x^.typ # p^.typ THEN
						IF (f IN intSet) & (f < p.typ.form) THEN Convert(x, p^.typ)
						ELSE err(111)
						END
					END ;
					p := NewOp(Nassign, fctno, p, x);
					p^.typ := OPT.notyp
				END
		| inclfn, exclfn: (*INCL, EXCL*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN intSet THEN
					IF (x^.class = Nconst) & ((0 > x^.conval^.intval) OR (x^.conval^.intval > OPM.MaxSet)) THEN err(202)
					END ;
					p := NewOp(Nassign, fctno, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| lenfn: (*LEN*)
				IF ~(f IN intSet) OR (x^.class # Nconst) THEN err(69)
				ELSIF f = SInt THEN
					L := SHORT(x^.conval^.intval); typ := p^.typ;
					WHILE (L > 0) & (typ^.comp IN ArraySet) DO typ := typ^.BaseTyp; DEC(L) END ;
					IF (L # 0) OR ~(typ^.comp IN ArraySet) THEN err(132)
					ELSE x^.obj := NIL;
						IF (typ^.comp IN {DynArr, OpenArr}) THEN
							WHILE p^.class = Nindex DO p := p^.left; INC(x^.conval^.intval) END ;	(* possible side effect ignored *)
							p := NewOp(Ndop, len, p, x); p^.typ := OPT.linttyp
						ELSIF typ.comp=SDynArr THEN p:=NewLeaf(typ^.link); p^.typ := OPT.linttyp
						ELSE p := x; p^.conval^.intval := typ^.n; SetIntType(p)
						END
					END
				ELSE err(132)
				END
		| copyfn: (*COPY*)
				IF (x.typ.form=Pointer) THEN DeRef(x) END;
				IF NotVar(x) THEN err(112)
				ELSIF (x^.typ^.comp IN ArraySet) & (x^.typ^.BaseTyp^.form = Char) THEN
					IF x^.readonly THEN err(76) END ;
					t := x; x := p; p := t; p := NewOp(Nassign, copyfn, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| ashfn: (*ASH*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN intSet THEN
					IF (p^.class = Nconst) & (x^.class = Nconst) THEN
						IF (-maxExp > x^.conval^.intval) OR (x^.conval^.intval > maxExp) THEN err(208); p^.conval^.intval := 1
						ELSIF x^.conval^.intval >= 0 THEN
							IF ABS(p^.conval^.intval) <= MAX(LONGINT) DIV ASH(1, x^.conval^.intval) THEN
								p^.conval^.intval := p^.conval^.intval * ASH(1, x^.conval^.intval)
							ELSE err(208); p^.conval^.intval := 1
							END
						ELSE p^.conval^.intval := ASH(p^.conval^.intval, x^.conval^.intval)
						END ;
						p^.obj := NIL
					ELSIF (x^.class = Nconst) & (x^.conval^.intval = 0) THEN		(*skip, p is not changed!*)
					ELSE p := NewOp(Ndop, ash, p, x); p^.typ := OPT.linttyp
					END
				ELSE err(111)
				END
		| newfn: (*NEW(p, x...)*)
				IF InitPar # NIL THEN
						Param(x, InitPar); InitPar := InitPar^.link;
						x^.link := p^.left^.link; p^.left^.link := x
				ELSIF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF p^.typ^.comp IN {DynArr, OpenArr} THEN
					IF f IN intSet THEN
						IF (x^.class = Nconst) & ((x^.conval^.intval < 0) OR (x^.conval^.intval > OPM.MaxIndex)) THEN err(63) END
					ELSE err(111)
					END ;
					p^.right := x; p^.typ := p^.typ^.BaseTyp;
				ELSE err(64)
				END
		| lshfn, rotfn: (*SYSTEM.LSH, SYSTEM.ROT*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF ~(f IN intSet) THEN err(111)
				ELSE
					IF fctno = lshfn THEN p := NewOp(Ndop, lsh, p, x) ELSE p := NewOp(Ndop, rot, p, x) END ;
					p^.typ := p^.left^.typ
				END
		| getfn, putfn, poutfn, pinfn: (*SYSTEM.GET, SYSTEM.PUT *)
							(* SYSTEM.PORTOUT, SYSTEM.PORTIN *)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN {Undef..Set, NilTyp, Pointer, ProcTyp} THEN
					IF (fctno = getfn) OR (fctno = getrfn) OR (fctno = pinfn) THEN
						IF NotVar(x) THEN err(112) END ;
						t := x; x := p; p := t
					ELSIF x.class = Nconst THEN err(-306)
					END ;
					p := NewOp(Nassign, fctno, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| put8fn:
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN {Undef..LInt} THEN
					IF f IN {Int..LInt} THEN  Val(x, OPT.sinttyp)  END;
					p := NewOp(Nassign, putfn, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| put16fn:
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (f IN {Undef, SInt..LInt}) THEN
					IF f IN {SInt, LInt} THEN  Convert(x, OPT.inttyp)  END;
					p := NewOp(Nassign, putfn, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| put32fn:
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (f IN {Undef, SInt..LInt, Set, Pointer, ProcTyp, NilTyp}) THEN
					IF f IN {SInt, Int} THEN  Convert(x, OPT.linttyp)  END;
					p := NewOp(Nassign, putfn, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| getrfn, putrfn: (*SYSTEM.GETREG, SYSTEM.PUTREG*)
				IF p.conval # NIL THEN i := p.conval.intval;  p.conval.intval := i MOD 8  END;
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (0<=i) & (i < 8) & ~(f IN {Undef..Real, Set, NilTyp, Pointer, ProcTyp}) THEN err(111)		(*old definition*)
				ELSIF (8<=i) & (i < 16) & ~(f IN {LInt, Real, Set, Pointer, ProcTyp}) THEN err(111)		(*EAX .. EDI*)
				ELSIF (16<=i) & (i < 24) & ~(f IN {Int}) THEN err(111)		(*AX .. DI*)
				ELSIF (24<=i) & (i < 32) & ~(f IN {Byte, Bool, Char, SInt}) THEN err(111)		(*AL .. BH*)
				ELSE
					IF fctno = getrfn THEN
						IF NotVar(x) THEN err(112) END ;
						t := x; x := p; p := t
					ELSIF (0<=i) & (i < 8) & (x.class = Nconst) THEN err(-306)
					END ;
					p := NewOp(Nassign, fctno, p, x)
				END ;
				p^.typ := OPT.notyp
		| bitfn: (*SYSTEM.BIT*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN intSet THEN
					p := NewOp(Ndop, bit, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.booltyp
		| valfn: (*SYSTEM.VAL*)	(* type is changed without considering the byte ordering on the target machine *)
				Val(x, p.typ);  p := x
		| sysnewfn: (*SYSTEM.NEW*)
				IF (p.typ.form=Pointer) & (p.typ.BaseTyp.comp IN ArraySet) THEN err(111)
				ELSIF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF f IN intSet THEN
					p := NewOp(Nassign, sysnewfn, p, x)
				ELSE err(111)
				END ;
				p^.typ := OPT.notyp
		| movefn: (*SYSTEM.MOVE*)
				IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
				ELSIF (x^.class = Nconst) & (f IN {SInt, Int}) THEN Convert(x, OPT.linttyp)
				ELSIF ~(f IN {LInt, Pointer}) THEN err(111); x^.typ := OPT.linttyp
				END ;
				p^.link := x
		| assertfn: (*ASSERT*)
				IF (f IN intSet) & (x^.class = Nconst) THEN
					IF (OPM.MinHaltNr <= x^.conval^.intval) & (x^.conval^.intval <= OPM.MaxHaltNr) THEN
						BindNodes(Ntrap, OPT.notyp, x, x);
						x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.errpos;
						Construct(Nif, p, x); p^.conval := OPT.NewConst(); p^.conval^.intval := OPM.errpos;
						Construct(Nifelse, p, NIL); OptIf(p);
						IF p = NIL THEN	(* ASSERT(TRUE) *)
						ELSIF p^.class = Ntrap THEN err(99)
						ELSE p^.subcl := assertfn
						END
					ELSE err(218)
					END
				ELSE err(69)
				END
		ELSE err(64)
		END ;
		par0 := p
	END StPar1;

	PROCEDURE StParN*(VAR par0: OPT.Node; x: OPT.Node; fctno, n: INTEGER);	(* x: n+1-th param of standard proc *)
		VAR node: OPT.Node; f: INTEGER; p: OPT.Node;
	BEGIN p := par0; f := x^.typ^.form;
		IF fctno = newfn THEN (*NEW(p, ..., x...*)
			IF InitPar # NIL THEN
					Param(x, InitPar); InitPar := InitPar^.link; x^.link := p^.left^.link; p^.left^.link := x
			ELSIF ~(p^.typ^.comp IN {DynArr, OpenArr}) THEN err(64)
			ELSIF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
			ELSIF f IN intSet THEN
				IF (x^.class = Nconst) & ((x^.conval^.intval <0) OR (x^.conval^.intval > OPM.MaxIndex)) THEN err(63) END;
				node := p^.right; WHILE node^.link # NIL DO node := node^.link END;
				node^.link := x; p^.typ := p^.typ^.BaseTyp;
			ELSE err(111)
			END
		ELSIF (fctno = movefn) & (n = 2) THEN (*SYSTEM.MOVE*)
			IF (x^.class = Ntype) OR (x^.class = Nproc) THEN err(126)
			ELSIF f IN intSet THEN
				node := OPT.NewNode(Nassign); node^.subcl := movefn; node^.right := p;
				node^.left := p^.link; p^.link := x; p := node
			ELSE err(111)
			END ;
			p^.typ := OPT.notyp
		ELSE err(64)
		END ;
		par0 := p
	END StParN;

	PROCEDURE StFct*(VAR par0: OPT.Node; fctno: SHORTINT; parno: INTEGER);
		VAR dim: INTEGER; x, p, r: OPT.Node;
				obj: OPT.Object; typ: OPT.Struct;
	BEGIN p := par0;
		IF (fctno <= ashfn) OR (fctno = shalt) THEN
			IF fctno = newfn THEN
				IF parno < 1 THEN err(65)
				ELSIF p^.typ # OPT.notyp THEN
					IF p^.typ^.comp IN {DynArr, OpenArr} THEN err(65) END ;
					p^.typ := OPT.notyp
				ELSE
					IF InitPar # NIL THEN InitPar := NIL; err(65) END;
					x := NIL;
					IF p^.left = NIL THEN RETURN END;	(* error in StPar0 *)
					IF p^.left^.link # NIL THEN
						p := p^.left^.link;
						WHILE p # NIL DO	(* reverse the list in p^.left^.link *)
							r := p^.link; p^.link := x; x := p; p := r
						END;
						r := x^.link; x^.link := NIL;	(* parameter list *)
						BindNodes(Ncall, OPT.notyp, x, r); x.obj := x.left.obj.link;
						p := par0; p^.left^.link := x
					END;
					(* insert reference to the body *)
					IF (p^.left # NIL) & (p^.left^.typ # NIL) & (p^.left^.typ^.BaseTyp # NIL) THEN typ := p^.left^.typ^.BaseTyp END;
					r := NIL;
					WHILE (typ # NIL) & (typ.comp = Record) DO
						IF (typ.strobj # NIL) & (hasBody IN typ.strobj.conval.setval) THEN
							x := NIL; Construct(Nproc, x, NIL); x.obj := typ.strobj;
							x.link := r; r := x;
						END;
						typ := typ.BaseTyp
					END;
					p.right := r
				END
			ELSIF (fctno <= sizefn) OR (fctno = shalt) THEN (* 1 param *)
				IF parno < 1 THEN err(65) END
			ELSE (* more than 1 param *)
				IF ((fctno = incfn) OR (fctno = decfn)) & (parno = 1) THEN (*INC, DEC*)
					BindNodes(Nassign, OPT.notyp, p, NewIntConst(1)); p^.subcl := fctno; p^.right^.typ := p^.left^.typ
				ELSIF (fctno = lenfn) & (parno = 1) THEN (*LEN*)
					IF p^.typ^.comp IN {DynArr, OpenArr} THEN dim := 0;
						WHILE p^.class = Nindex DO p := p^.left; INC(dim) END ;	(* possible side effect ignored *)
						BindNodes(Ndop, OPT.linttyp, p, NewIntConst(dim)); p^.subcl := len
					ELSIF p.typ.comp=SDynArr THEN p:=NewLeaf(p.typ^.link); p^.typ := OPT.linttyp
					ELSE
						p := NewIntConst(p^.typ^.n)
					END
				ELSIF parno < 2 THEN err(65)
				END
			END
		ELSIF fctno = awaitfn THEN
			IF AwaitIF THEN	(*Await Call: IF ~cond THEN AWAIT(cond) END*)
				x := p;
				BindNodes(Nassign, OPT.notyp, x, x^.link); x^.left^.link := NIL; x.subcl := awaitfn;
				x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.errpos;
					(*Create the condition*)
				PrepCall(p, obj);  Call(p, NIL, obj);
				MOp(not, p);
					(*build if*)
				Construct(Nif, p, x); p^.conval := OPT.NewConst(); p^.conval^.intval := OPM.errpos;
				Construct(Nifelse, p, NIL); OptIf(p)
			ELSE
				BindNodes(Nassign, OPT.notyp, p, p^.link); p^.left^.link := NIL; p.subcl := awaitfn;
				p^.conval := OPT.NewConst(); p^.conval^.intval := OPM.errpos
			END
		ELSIF fctno = assertfn THEN
			IF parno = 1 THEN x := NIL;
				BindNodes(Ntrap, OPT.notyp, x, NewIntConst(AssertTrap));
				x^.conval := OPT.NewConst(); x^.conval^.intval := OPM.errpos;
				Construct(Nif, p, x); p^.conval := OPT.NewConst(); p^.conval^.intval := OPM.errpos;
				Construct(Nifelse, p, NIL); OptIf(p);
				IF p = NIL THEN	(* ASSERT(TRUE) *)
				ELSIF p^.class = Ntrap THEN err(99)
				ELSE p^.subcl := assertfn
				END
			ELSIF parno < 1 THEN err(65)
			END
		ELSE (*SYSTEM*)
			IF (fctno = stifn) OR (fctno = clifn) THEN 
				IF OPM.WarnUnsafe THEN err(-666) END;
				p := NIL; Construct(Nassign, p, NIL); p.subcl := fctno
			ELSIF (fctno # stifn) & (fctno # clifn) & (parno < 1) OR
				(fctno # stifn) & (fctno # clifn) & (fctno > ccfn) & (fctno < get8fn) & (parno < 2) OR
				(fctno = movefn) & (parno < 3) THEN err(65)
			END
		END ;
		par0 := p
	END StFct;
	
	PROCEDURE OpenArrParCheck(ftyp, atyp: OPT.Struct; fvarpar: BOOLEAN);
		VAR f: INTEGER;
	BEGIN (* ftyp^.comp = OpenArr *)
		f := atyp^.comp; ftyp := ftyp^.BaseTyp; atyp := atyp^.BaseTyp;
		IF (*fvarpar &*) (ftyp = OPT.bytetyp) THEN (* ok, but ... *)	(* 2. Appendix C, 2nd paragraph *)
			IF OPM.WarnUnsafe THEN
				IF (f = Basic) & (atyp^.form IN {Pointer, ProcTyp, Comp}) THEN err(-666) END	(* Comp check is very conservative *)
			END;
			IF ~(f IN ArraySet) OR ~(atyp^.form IN {Byte..SInt}) THEN err(-301) END (* ... warning 301 *)
		ELSIF f IN ArraySet THEN
			IF ftyp^.comp = OpenArr THEN OpenArrParCheck(ftyp, atyp, fvarpar)
			ELSIF ftyp # atyp THEN
				IF (ftyp.form = Pointer) & (atyp.form = Pointer) THEN
					ftyp := ftyp^.BaseTyp; atyp := atyp^.BaseTyp;
					IF (ftyp.comp=OpenArr) & (atyp.comp IN ArraySet) THEN OpenArrParCheck(ftyp, atyp, fvarpar)
					ELSIF ~fvarpar & (ftyp^.comp = Record) & (atyp^.comp = Record) THEN
						WHILE (ftyp # atyp) & (atyp # NIL) & (atyp # OPT.undftyp) DO atyp := atyp^.BaseTyp END ;
						IF atyp = NIL THEN err(113) END
					ELSE err(66)
					END
				ELSE err(66)
				END
			END ;
		ELSE err(67)
		END
	END OpenArrParCheck;

	PROCEDURE CheckReceiver(VAR x: OPT.Node; fp: OPT.Object);
	BEGIN
		IF fp^.typ^.form = Pointer THEN
			IF x^.class = Nderef THEN x := x^.left (*undo DeRef*)
			ELSIF x^.typ^.form # Pointer THEN err(71) END
		END
	END CheckReceiver;
	
	PROCEDURE PrepCall*(VAR x: OPT.Node; VAR fpar: OPT.Object);
	BEGIN
		IF (x^.obj # NIL) & (x^.obj^.mode IN {LProc, XProc, TProc, CProc}) THEN
			fpar := x^.obj^.link;
			IF x^.obj^.mode = TProc THEN CheckReceiver(x^.left, fpar); fpar := fpar^.link END
		ELSIF (x^.class # Ntype) & (x^.typ # NIL) & (x^.typ^.form = ProcTyp) THEN
			fpar := x^.typ^.link
		ELSE err(121); fpar := NIL; x^.typ := OPT.undftyp
		END
	END PrepCall;

	PROCEDURE Param*(VAR ap: OPT.Node; fp: OPT.Object);
		VAR q: OPT.Struct;
	BEGIN
		IF fp.typ.form # Undef THEN
			IF (fp^.typ^.sysflag = 0) & (ap^.typ^.sysflag = notag) THEN
				err(59)
			END;
			IF (fp.typ.comp = OpenArr) & (fp.typ.BaseTyp = OPT.bytetyp) & (ap.typ.form = Pointer) THEN err(113)
			ELSIF (ap^.typ^.form = NilTyp) & OPT.SYSimported THEN
				IF (fp^.typ^.form = Pointer) OR (fp^.typ^.form = ProcTyp) OR (fp^.mode = VarPar) OR (fp^.typ^.sysflag = notag) THEN
				ELSE err(113)
				END
			ELSIF fp^.mode = VarPar THEN
				IF NotVar(ap) THEN err(122)
				ELSE CheckLeaf(ap, FALSE)
				END ;
				IF ap^.readonly THEN err(76) END ;
				IF fp^.typ^.comp = OpenArr THEN 
					OpenArrParCheck(fp^.typ, ap^.typ, TRUE)
				ELSIF (fp^.typ^.comp = Record) & (ap^.typ^.comp = Record) THEN
					q := ap^.typ; OPT.MarkType(q);
					WHILE (q # fp^.typ) & (q # NIL) & (q # OPT.undftyp) DO q := q^.BaseTyp END ;
					IF q = NIL THEN err(111) END
(*
				ELSIF (fp^.typ = OPT.ptrtyp) & (ap^.typ^.form = Pointer) THEN (* ok *)
*)
				ELSIF (ap^.typ # fp^.typ) & ~((fp^.typ^.form = Byte) & (ap^.typ^.form IN {Char, SInt})) THEN err(123)
				ELSIF (fp^.typ^.form = Pointer) & (ap^.class = Nguard) THEN err(123)
				END
			ELSIF fp^.typ^.comp = OpenArr THEN
				IF (ap^.class = Nconst) & (ap^.typ^.form = Char) THEN CharToString(ap) END ;
				IF (ap^.typ^.form = String) & (fp^.typ^.BaseTyp^.form = Char) THEN (* ok *)
				ELSIF (ap^.class >= Nconst) & (ap.class#Ncall) THEN err(59)
				ELSE OpenArrParCheck(fp^.typ, ap^.typ, FALSE)
				END
			ELSE CheckAssign(fp^.typ, ap)
			END
		END
	END Param;
	
	PROCEDURE StaticLink*(dlev: SHORTINT);
		VAR scope: OPT.Object;
	BEGIN
		scope := OPT.topScope;
		WHILE dlev > 0 DO DEC(dlev);
			INCL(scope^.link^.conval^.setval, slNeeded);
			scope := scope^.left
		END
	END StaticLink;

	PROCEDURE Call*(VAR x: OPT.Node; apar: OPT.Node; fp: OPT.Object);
		VAR typ: OPT.Struct; p: OPT.Node; lev: SHORTINT;
	BEGIN
		IF x^.class = Nproc THEN typ := x^.typ;
			lev := x^.obj^.mnolev;
			IF lev > 0 THEN StaticLink(OPT.topScope^.mnolev-lev) END ;
			IF x^.obj^.mode = IProc THEN err(121) END
		ELSIF (x^.class = Nfield) & (x^.obj^.mode = TProc) THEN typ := x^.typ;
			x^.class := Nproc; p := x^.left; x^.left := NIL;
			p^.link := apar; apar := p;
			fp := x^.obj^.link
		ELSE typ := x^.typ^.BaseTyp
		END ;
		BindNodes(Ncall, typ, x, apar); x^.obj := fp;
		x.subcl := 0  (* 0 = no assign call *)
	END Call;
	
	PROCEDURE CopyAndSubst*(VAR new: OPT.Node; old: OPT.Node);
	BEGIN
		IF old = NIL THEN
			new := NIL; RETURN
		ELSIF (old^.obj # NIL) & (old^.obj^.link2 # NIL) & ((old^.obj^.mode = Var) OR (old^.obj^.mode = VarPar)) THEN
			new := NewLeaf(old.obj.link2); new^.conval := old^.conval;
			IF (new^.class = Nfixup) & (old.obj.link2.mnolev <= 0) THEN err(261) END
		ELSE
			new := OPT.NewNode(old^.class);
			new^ := old^;
		END;
		IF (old.class = 29) & (old.conval.intval = 0) THEN	(*imported inline, set errpos*)
			new.conval := OPT.NewConst();
			new.conval^ := old.conval^;
			new.conval.intval := OPM.errpos
		END;
		CopyAndSubst(new^.left, old^.left); CopyAndSubst(new^.right, old^.right);
		CopyAndSubst(new^.link, old^.link)
	END CopyAndSubst;

	PROCEDURE Lock*(VAR x: OPT.Node; self: OPT.Object; excl: BOOLEAN);
		VAR n: OPT.Node;
	BEGIN
		IF self#NIL THEN
			BindNodes(Nassign, OPT.notyp, x, NewLeaf(self)); x.subcl := lockfn; x^.obj := self;
			n := NewBoolConst (excl); x.right.link := n
		END
	END Lock;

	PROCEDURE Enter*(VAR procdec: OPT.Node; stat: OPT.Node; proc: OPT.Object);
		VAR x: OPT.Node;
	BEGIN
		x := OPT.NewNode(Nenter); x^.typ := OPT.notyp; x^.obj := proc;
		x^.left := procdec; x^.right := stat; InitAppend(x^.right);	
		procdec := x
	END Enter;
	
	PROCEDURE Return*(VAR x: OPT.Node; proc: OPT.Object);
		VAR node: OPT.Node;
	BEGIN
		IF proc = NIL THEN (* return from module *)
			IF x # NIL THEN err(124) END
		ELSE
			IF x # NIL THEN
				IF proc^.typ^.comp = OpenArr THEN		(* same as Param *)
					IF x.typ.form=Pointer THEN DeRef(x) END;
					IF (x^.class = Nconst) & (x^.typ^.form = Char) THEN CharToString(x) END ;
					IF (x^.typ^.form = String) & (proc^.typ^.BaseTyp^.form = Char) THEN (* ok *)
					ELSIF (x^.class >= Nconst) & (x.class#Ncall) THEN err(59)
					ELSE OpenArrParCheck(proc^.typ, x^.typ, FALSE)
					END
				ELSE  CheckAssign(proc^.typ, x)
				END
			ELSIF proc^.typ # OPT.notyp THEN err(124)
			END
		END ;
		node := OPT.NewNode(Nreturn); node^.typ := OPT.notyp; node^.obj := proc; node^.left := x; x := node
	END Return;

	PROCEDURE Assign*(VAR x: OPT.Node; y: OPT.Node);	(* x := y *)
		VAR z: OPT.Node; struct: BOOLEAN;
	BEGIN
		struct := x.typ.form = Comp;
		IF x^.class >= Nconst THEN err(56) END ;
(*		IF (x.typ.comp=DynArr) & (x.class > Nfield) THEN err(113) END;	*)
		CheckAssign(x^.typ, y);
		IF x^.readonly THEN err(76) END ;
		OPT.MarkType(x.typ);
		IF x^.typ^.comp = Record THEN
			IF x^.class = Nguard THEN z := x^.left ELSE z := x END ;
			IF (z^.class = Nderef) & (z^.left^.class = Nguard) THEN
				z^.left := z^.left^.left	(* skip guard before dereferencing *)
			END ;
			IF (x^.typ^.strobj # NIL) & ((z^.class = Nderef) OR (z^.class = Nvarpar)) THEN
				IF x.typ.sysflag # notag THEN
					BindNodes(Neguard, x^.typ, z, NIL)
				END;
				x := z
			END
		ELSIF (x^.typ^.comp IN {StaticArr, SDynArr}) & (x^.typ^.BaseTyp = OPT.chartyp) &
				(y^.typ^.form = String) & (y^.conval^.intval2 = 1) THEN	(* replace array := "" with array[0] := 0X *)
			y^.typ := OPT.chartyp; y^.conval^.intval := 0;
			Index(x, NewIntConst(0))
		END ;
		BindNodes(Nassign, OPT.notyp, x, y); x^.subcl := assign;
		IF struct & (y.class = Ncall) THEN y.subcl := 1 END  (* 1 = assign call *)
	END Assign;
	
	PROCEDURE Inittd*(VAR inittd, last: OPT.Node; typ: OPT.Struct);
		VAR node: OPT.Node;
	BEGIN
		node := OPT.NewNode(Ninittd); node^.typ := typ;
		node^.conval := OPT.NewConst(); node^.conval^.intval := typ^.txtpos;
		IF inittd = NIL THEN inittd := node ELSE last^.link := node END ;
		last := node
	END Inittd;
	
BEGIN
	maxExp := log(MAX(LONGINT) DIV 2 + 1); maxExp := exp;
	verify:=NIL

END OPB.
