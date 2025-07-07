(* ETH Oberon, Copyright 2001 ETH Zuerich Institut fuer Computersysteme, ETH Zentrum, CH-8092 Zuerich.
Refer to the "General ETH Oberon System Source License" contract available at: http://www.oberon.ethz.ch/ *)

(* Oberon Portable Scanner (front end) *)
(* NW, RC, ejz, rml, pjm, prk*)

MODULE OPS;	(** non-portable *)
	IMPORT OPM;

	CONST
		MaxStrLen* = 256;
		MaxIdLen = 32;
	
	TYPE
		Name* = ARRAY MaxIdLen OF CHAR;
		String* = ARRAY MaxStrLen OF CHAR;

		GetProc* = PROCEDURE (VAR sym: SHORTINT);
		
		Token = POINTER TO RECORD	pos: LONGINT; sym: SHORTINT; next: Token	END;
		IntToken = POINTER TO RECORD (Token)	intval: LONGINT; typ: INTEGER	END;
		RealToken = POINTER TO RECORD (Token)	realval: REAL	END;
		LRealToken = POINTER TO RECORD (Token)	lrlval: LONGREAL	END;
		StrToken = POINTER TO RECORD (Token)	str: String; len: LONGINT	END;
		NameToken = POINTER TO RECORD (Token)	name: Name	END;
		
		TokenStream* = Token;

	(* name, str, numtyp, intval, realval, lrlval are implicit results of Get *)

	VAR
		name*: Name;
		str*: String;
		numtyp*: INTEGER; (* 1 = char, 2 = integer, 3 = real, 4 = longreal *)
		intval*: LONGINT;	(* integer value or string length *)
		realval*: REAL;
		lrlval*: LONGREAL;
		Get*: GetProc;
		ch*: CHAR;     (*current character*)
		stream, last: TokenStream;

	(*symbols:
	    |  0          1          2          3          4
	 ---|--------------------------------------------------------
	  0 |  null       *          /          DIV        MOD
	  5 |  &          +          -          OR         =
	 10 |  #          <          <=         >          >=
	 15 |  IN         IS         ^          .          ,
	 20 |  :          ..         )          ]          }
	 25 |  OF         THEN       DO         TO         BY
	 30 |  (          [          {          ~          :=
	 35 |  number     NIL        TRUE       FALSE      string
	 40 |  ident      ;          |          END        ELSE
	 45 |  ELSIF      UNTIL      IF         CASE       WHILE
	 50 |  REPEAT     FOR        LOOP       WITH       EXIT
	 55 |  RETURN     ARRAY      OBJECT     RECORD     POINTER
	 60 |  BEGIN      CONST      TYPE       VAR        PROCEDURE
	 65 |  IMPORT     MODULE     CODE       eof        **
	 *)

	CONST
		(* numtyp values *)
		char = 1; integer = 2; real = 3; longreal = 4;

		(*symbol values*)
		null* =   0; times* =   1; slash* =   2; div* =   3; mod* =   4; and* =   5; 
		plus* =   6; minus* =   7; or* =   8; eql* =   9; neq* =  10; lss* =  11; 
		leq* =  12; gtr* =  13; geq* =  14; in* =  15; is* =  16; arrow* =  17; 
		period* =  18; comma* =  19; colon* =  20; upto* =  21; rparen* =  22; 
		rbrak* =  23; rbrace* =  24; of* =  25; then* =  26; do* =  27; to* =  28; 
		by* =  29; lparen* =  30; lbrak* =  31; lbrace* =  32; not* =  33; 
		becomes* =  34; number* =  35; nil* =  36; true* =  37; false* =  38; 
		string* =  39; ident* =  40; semicolon* =  41; bar* =  42; end* =  43; 
		else* =  44; elsif* =  45; until* =  46; if* =  47; case* =  48; while* =  49; 
		repeat* =  50; for* =  51; loop* =  52; with* =  53; exit* =  54; 
		return* =  55; array* =  56; object* =  57; record* =  58; pointer* =  59; 
		begin* =  60; code* =  61; const* =  62; type* =  63; var* =  64; 
		procedure* =  65; import* =  66; module* =  67; eof* =  68; 

	PROCEDURE err(n: INTEGER);
	BEGIN OPM.err(n)
	END err;
	
	PROCEDURE StreamGet (VAR sym: SHORTINT);
	BEGIN
		IF (stream # NIL) & (stream.next # NIL) THEN
			stream := stream.next;
			sym := stream.sym; OPM.errpos := stream.pos;
			IF stream IS IntToken THEN intval := stream(IntToken).intval; numtyp := stream(IntToken).typ
			ELSIF stream IS RealToken THEN realval := stream(RealToken).realval; numtyp := 3
			ELSIF stream IS LRealToken THEN lrlval := stream(LRealToken).lrlval; numtyp := 4
			ELSIF stream IS StrToken THEN str := stream(StrToken).str; intval := stream(StrToken).len
			ELSIF stream IS NameToken THEN name := stream(NameToken).name
			ELSIF ((times<=sym) & (sym<=arrow)) OR (sym=not) OR (sym=becomes) THEN
				name := stream(NameToken).name
			END
		ELSE sym := eof
		END
	END StreamGet;
	
	PROCEDURE RecToken (sym: SHORTINT);
		VAR s: Token; r: RealToken; lr: LRealToken; i: IntToken; st: StrToken; nam: NameToken;
	BEGIN
		IF sym = number THEN
			IF numtyp = 3 THEN NEW (r); r.realval := realval; s := r
			ELSIF numtyp = 4 THEN NEW (lr); lr.lrlval := lrlval; s := lr
			ELSE NEW (i); i.intval := intval; i.typ := numtyp; s := i
			END
		ELSIF sym = string THEN NEW (st); st.str := str; st.len := intval; s := st
		ELSIF sym = ident THEN NEW (nam); nam.name := name; s := nam
		ELSIF ((times<=sym) & (sym<=arrow)) OR (sym=not) OR (sym=becomes) THEN
			NEW (nam); nam.name := name; s := nam
		ELSE NEW (s)
		END;
		s.pos := OPM.errpos; s.sym := sym; s.next := last.next; last.next := s; last := s
	END RecToken;

	PROCEDURE StartRecording* (sym: SHORTINT);
	BEGIN NEW (stream); last := stream; RecToken (sym)
	END StartRecording;
	
	PROCEDURE StopRecording* (VAR s: TokenStream);
	BEGIN s := stream; stream := NIL; last := NIL
	END StopRecording;
	
	PROCEDURE StartPlaying* (s: TokenStream);
	BEGIN stream := s; Get := StreamGet
	END StartPlaying;

	PROCEDURE Str(VAR sym: SHORTINT);
		VAR i: INTEGER; och: CHAR;
	BEGIN i := 0; och := ch;
		LOOP OPM.Get(ch);
			IF ch = och THEN EXIT END ;
			IF ch < " " THEN err(3); EXIT END ;
			IF i = MaxStrLen-1 THEN err(241); EXIT END ;
			str[i] := ch; INC(i)
		END ;
		OPM.Get(ch); str[i] := 0X; intval := i + 1;
		IF intval = 2 THEN
			sym := number; numtyp := 1; intval := ORD(str[0])
		ELSE sym := string
		END
	END Str;

	PROCEDURE Identifier(VAR sym: SHORTINT);
		VAR i: INTEGER;
	BEGIN i := 0;
		REPEAT
			name[i] := ch; INC(i); OPM.Get(ch)
		UNTIL (ch < "0") OR ("9" < ch) & (CAP(ch) < "A") OR ("Z" < CAP(ch)) OR (i = MaxIdLen);
		IF i = MaxIdLen THEN err(240); DEC(i) END ;
		name[i] := 0X; sym := ident
	END Identifier;

	PROCEDURE CheckCardinality*(VAR name: Name; nofp: SHORTINT): BOOLEAN;
	BEGIN
		CASE name[0] OF
		| "+", "-": RETURN (nofp=1) OR (nofp=2)
		| "~": RETURN (name[1]=0X)&(nofp=1)
		ELSE RETURN nofp=2
		END
	END CheckCardinality;
	
	PROCEDURE CheckOperator*(VAR id: SHORTINT);
		VAR ch0, ch1, ch2: CHAR;
	BEGIN id:=126; COPY(str, name);
		ch0:=str[0]; ch1:=str[1]; ch2:=str[2];
		CASE ch0 OF
		| "=", "#", "&": IF ch1=0X THEN RETURN END
		| "<", ">": IF (ch1=0X) OR ((ch1="=") & (ch2=0X)) THEN RETURN END	(* < , <=,  > , >= *)
		| "I": IF (ch1="N") & (ch2=0X) THEN RETURN END	(* IN *)
		| "D": IF str="DIV" THEN RETURN END	(* DIV *)
		| "M": IF str="MOD" THEN RETURN END	(* MOD *)
		| "O": IF str="OR" THEN RETURN END	(* OR *)
		| "+", "-", "*", "/" : IF (ch1=0X) OR ((ch2=0X) & (ch1="*")) THEN RETURN END;
		| "~": IF (ch1=0X) THEN RETURN END;
		| ":": IF str=":=" THEN RETURN END;
		ELSE
		END;
		id:=0
	END CheckOperator;

		PROCEDURE Number*;
		VAR i, m, n, d, e: INTEGER; dig: ARRAY 24 OF CHAR; f: LONGREAL; expCh: CHAR; neg: BOOLEAN;

		PROCEDURE Ten(e: INTEGER): LONGREAL;
			VAR x, p: LONGREAL;
		BEGIN x := 1; p := 10;
			WHILE e > 0 DO
				IF ODD(e) THEN x := x*p END;
				e := e DIV 2;
				IF e > 0 THEN p := p*p END (* prevent overflow *)
			END;
			RETURN x
		END Ten;

		PROCEDURE Ord(ch: CHAR; hex: BOOLEAN): INTEGER;
		BEGIN (* ("0" <= ch) & (ch <= "9") OR ("A" <= ch) & (ch <= "F") *)
			IF ch <= "9" THEN RETURN ORD(ch) - ORD("0")
			ELSIF hex THEN RETURN ORD(ch) - ORD("A") + 10
			ELSE err(2); RETURN 0
			END
		END Ord;
		
	BEGIN (* ("0" <= ch) & (ch <= "9") *)
		i := 0; m := 0; n := 0; d := 0;
		LOOP (* read mantissa *)
			IF ("0" <= ch) & (ch <= "9") OR (d = 0) & ("A" <= ch) & (ch <= "F") THEN
				IF (m > 0) OR (ch # "0") THEN (* ignore leading zeros *)
					IF n < LEN(dig) THEN dig[n] := ch; INC(n) END;
					INC(m)
				END;
				OPM.Get(ch); INC(i)
			ELSIF ch = "." THEN OPM.Get(ch);
				IF ch = "." THEN (* ellipsis *) ch := 7FX; EXIT
				ELSIF d = 0 THEN (* i > 0 *) d := i
				ELSE err(2)
				END
			ELSE EXIT
			END
		END; (* 0 <= n <= m <= i, 0 <= d <= i *)
		IF d = 0 THEN (* integer *)
			IF n = m THEN intval := 0; i := 0;
				IF ch = "X" THEN (* character *) OPM.Get(ch); numtyp := char;
					IF n <= 2 THEN
						WHILE i < n DO intval := intval*10H + Ord(dig[i], TRUE); INC(i) END
					ELSE err(203)
					END
				ELSIF ch = "H" THEN (* hexadecimal *) OPM.Get(ch); numtyp := integer;
					IF n <= OPM.MaxHDig THEN
						IF (n = OPM.MaxHDig) & (dig[0] > "7") THEN (* prevent overflow *) intval := -1 END;
						WHILE i < n DO intval := intval*10H + Ord(dig[i], TRUE); INC(i) END
					ELSE err(203)
					END
				ELSE (* decimal *) numtyp := integer;
					WHILE i < n DO d := Ord(dig[i], FALSE); INC(i);
						IF intval <= (MAX(LONGINT) - d) DIV 10 THEN intval := intval*10 + d
						ELSE err(203)
						END
					END
				END
			ELSE err(203)
			END
		ELSE (* fraction *)
			f := 0; e := 0; expCh := "E";
			WHILE n > 0 DO (* 0 <= f < 1 *) DEC(n); f := (Ord(dig[n], FALSE) + f)/10 END;
			IF (ch = "E") OR (ch = "D") THEN expCh := ch; OPM.Get(ch); neg := FALSE;
				IF ch = "-" THEN neg := TRUE; OPM.Get(ch)
				ELSIF ch = "+" THEN OPM.Get(ch)
				END;
				IF ("0" <= ch) & (ch <= "9") THEN
					REPEAT n := Ord(ch, FALSE); OPM.Get(ch);
						IF e <= (MAX(INTEGER) - n) DIV 10 THEN e := e*10 + n
						ELSE err(203)
						END
					UNTIL (ch < "0") OR ("9" < ch);
					IF neg THEN e := -e END
				ELSE err(2)
				END
			END;
			DEC(e, i-d-m); (* decimal point shift *)
			IF expCh = "E" THEN numtyp := real;
				IF (1-OPM.MaxRExp < e) & (e <= OPM.MaxRExp) THEN
					IF e < 0 THEN realval := SHORT(f / Ten(-e))
					ELSE realval := SHORT(f * Ten(e))
					END
				ELSE err(203)
				END
			ELSE numtyp := longreal;
				IF (1-OPM.MaxLExp < e) & (e <= OPM.MaxLExp) THEN
					IF e < 0 THEN lrlval := f / Ten(-e)
					ELSE lrlval := f * Ten(e)
					END
				ELSE err(203)
				END
			END
		END
	END Number;

	PROCEDURE DefaultGet(VAR sym: SHORTINT);
		VAR s: SHORTINT;

		PROCEDURE Comment;	(* do not read after end of file *)
			VAR dump: BOOLEAN;
		BEGIN OPM.Get(ch);
			IF ch = "@" THEN dump := TRUE; OPM.LogWLn END;
			LOOP
				LOOP
					WHILE ch = "(" DO OPM.Get(ch);
						IF ch = "*" THEN Comment ELSIF dump THEN OPM.LogW ("(") END
					END ;
					IF ch = "*" THEN OPM.Get(ch); EXIT END ;
					IF ch = OPM.Eot THEN EXIT END ;
					IF dump THEN OPM.LogW (ch) END;
					OPM.Get(ch)
				END ;
				IF ch = ")" THEN OPM.Get(ch); EXIT END ;
				IF dump THEN OPM.LogW ("*") END;
				IF ch = OPM.Eot THEN err(5); EXIT END
			END
		END Comment;

	BEGIN
		WHILE ch <= " " DO (*ignore control characters*)
			IF ch = OPM.Eot THEN sym := eof; RETURN
			ELSE OPM.Get(ch)
			END
		END ;
		OPM.errpos := OPM.curpos-1;
		CASE ch OF   (* ch > " " *)
			| 22X, 27X  : Str(s)
			| "#"  : s := neq; name:="#"; OPM.Get(ch)
			| "&"  : s :=  and; name:="&"; OPM.Get(ch)
			| "("  : OPM.Get(ch);
							 IF ch = "*" THEN Comment; Get(sym); RETURN	(*dont' record twice!*)
								 ELSE s := lparen
							 END
			| ")"  : s := rparen; OPM.Get(ch)
			| "*"  : name:="*"; s :=  times; OPM.Get(ch)
			| "+"  : name:="+"; s :=  plus; OPM.Get(ch)
			| ","  : s := comma; OPM.Get(ch)
			| "-"  : name:="-"; s :=  minus; OPM.Get(ch)
			| "."  : OPM.Get(ch);
							 IF ch = "." THEN OPM.Get(ch); s := upto ELSE s := period END
			| "/"  : name:="/"; OPM.Get(ch); s :=  slash
			| "0".."9": Number; s := number
			| ":"  : OPM.Get(ch);
							 IF ch = "=" THEN OPM.Get(ch); s := becomes; name:=":="  ELSE s := colon END
			| ";"  : s := semicolon; OPM.Get(ch)
			| "<"  : OPM.Get(ch);
							 IF ch = "=" THEN OPM.Get(ch); s := leq; name:="<=" ELSE s := lss; name:="<" END
			| "="  : s :=  eql; name:="="; OPM.Get(ch)
			| ">"  : OPM.Get(ch);
							 IF ch = "=" THEN OPM.Get(ch); s := geq; name:=">=" ELSE s := gtr; name:=">" END
			| "A": Identifier(s); IF name = "ARRAY" THEN s := array END
			| "B": Identifier(s);
						IF name = "BEGIN" THEN s := begin
						ELSIF name = "BY" THEN s := by
						END
			| "C": Identifier(s);
						IF name = "CASE" THEN s := case
						ELSIF name = "CODE" THEN s := code
						ELSIF name = "CONST" THEN s := const
						END
			| "D": Identifier(s);
						IF name = "DO" THEN s := do
						ELSIF name = "DIV" THEN s := div
						END
			| "E": Identifier(s);
						IF name = "END" THEN s := end
						ELSIF name = "ELSE" THEN s := else
						ELSIF name = "ELSIF" THEN s := elsif
						ELSIF name = "EXIT" THEN s := exit
						END
			| "F": Identifier(s);
						IF name = "FALSE" THEN s := false
						ELSIF name = "FOR" THEN s := for
						END
			| "I": Identifier(s);
						IF name = "IF" THEN s := if
						ELSIF name = "IN" THEN s := in
						ELSIF name = "IS" THEN s := is
						ELSIF name = "IMPORT" THEN s := import
						END
			| "L": Identifier(s); IF name = "LOOP" THEN s := loop END
			| "M": Identifier(s);
						IF name = "MOD" THEN s := mod
						ELSIF name = "MODULE" THEN s := module
						END
			| "N": Identifier(s); IF name = "NIL" THEN s := nil END
			| "O": Identifier(s);
						IF name = "OR" THEN s := or
						ELSIF name = "OF" THEN s := of
						ELSIF name = "OBJECT" THEN s := object
						END
			| "P": Identifier(s);
						IF name = "PROCEDURE" THEN s := procedure
						ELSIF name = "POINTER" THEN s := pointer
						END
			| "R": Identifier(s);
						IF name = "RECORD" THEN s := record
						ELSIF name = "REPEAT" THEN s := repeat
						ELSIF name = "RETURN" THEN s := return
						END
			| "T": Identifier(s);
						IF name = "THEN" THEN s := then
						ELSIF name = "TO" THEN s := to
						ELSIF name = "TRUE" THEN s := true
						ELSIF name = "TYPE" THEN s := type
						END
			| "U": Identifier(s); IF name = "UNTIL" THEN s := until END
			| "V": Identifier(s); IF name = "VAR" THEN s := var END
			| "W": Identifier(s);
						IF name = "WHILE" THEN s := while
						ELSIF name = "WITH" THEN s := with
						END
			| "G".."H", "J", "K", "Q", "S", "X".."Z": Identifier(s)
			| "["  : s := lbrak; OPM.Get(ch)
			| "]"  : s := rbrak; OPM.Get(ch)
			| "^"  : s := arrow; OPM.Get(ch)
			| "a".."z": Identifier(s)
			| "{"  : s := lbrace; OPM.Get(ch)
			| "|"  : s := bar; OPM.Get(ch)
			| "}"  : s := rbrace; OPM.Get(ch)
			| "~"  : s := not; name:="~"; OPM.Get(ch)
			| 7FX  : s := upto; OPM.Get(ch)
		ELSE s :=  null; OPM.Get(ch)
		END ;
		IF stream # NIL THEN RecToken (s) END;
		sym := s
	END DefaultGet;

	PROCEDURE Init*;
	BEGIN
		ch := " ";
		stream := NIL; last := NIL;
		Get := DefaultGet
	END Init;

BEGIN
	Init
END OPS.

(*
	Generate Enumeration:
	ProgTools.Enum 0 *
		null
		times slash div mod and 
		plus minus or eql neq  lss leq gtr geq in is 
		arrow period comma
		colon upto rparen rbrak rbrace
		of then do to by
		lparen lbrak lbrace
		not
		becomes
		number nil true false string
		ident semicolon bar end else
		elsif until if case while
		repeat for loop with exit
		return array object record pointer begin code
		const type var procedure import
		module eof
		~
		
	Generate Import List
	ProgTools.Enum OPS
		null
		times slash div mod and 
		plus minus or eql neq  lss leq gtr geq in is 
		arrow period comma
		colon upto rparen rbrak rbrace
		of then do to by
		lparen lbrak lbrace
		not
		becomes
		number nil true false string
		ident semicolon bar end else
		elsif until if case while
		repeat for loop with exit
		return array object record pointer begin code
		const type var procedure import
		module eof
		~

*)
