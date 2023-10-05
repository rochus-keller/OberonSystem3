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

MODULE Attributes; (** portable *) (* jm 14.3.95 *)

(** Module Attributes manages the attribute lists of the gadgets, provides an improved scanner with macro substitution facilities for executing commands, and supplies type conversion routines.
*)
(*
	jm 10.2.93 - Added DeleteAttr
	jm 9.3.93 - real support
	19.4.94 - Removed aliasing from the Scanner
	27.5.94 - added len support for scanner
	16.2.95 - @ scan support
	21.6.95 - fixed Attributes.Read*
	28.6.95 - bug fix in InsertAttr
	20.2.96 - added conversion attribute setting and getting routines
	14.3.96 - fix in get sym
	14.5.97 - added escape char "_" in Read
*)

IMPORT
	Objects, Oberon, Texts, Files, Reals, Fonts, Strings;

CONST
	 (** Scanner symbol classes. *)
    Inval* = Texts.Inval;           (** Invalid symbol. *)
    Name* = Texts.Name;        (** Name. *)
    String* = Texts.String;        (** Literal string. *)
    Int* = Texts.Int;             (** Integer i. *)
    Real* = Texts.Real;          (** Real number x. *)
    LongReal* = Texts.LongReal;  (** Long real number y. *)
    Char* = Texts.Char;          (** Special character c. *)
	Obj* = Texts.Object; 		   (** Object o. *)

(* Attr classes older values: used for saving now *)
     Sboolean = 1; Sstring = 2;  Sint = 3; Sreal = 4; Schar = 6;  

	MaxLen = 128;
	TAB = 9X; CR = 0DX; LF = 0AX;

TYPE
	Reader* = POINTER TO ReaderDesc;		(** Macro substituting reader. *)
	ReaderDesc* = RECORD
		substitute*: BOOLEAN;		(** Is substitution on or off? *)
		text*: Texts.Text;		(** Current text read. *)
		eot*: BOOLEAN;		(** End of text reached? *)
		lib*: Objects.Library;	(** Library of last character/object read. *)
		R: Texts.Reader;
		next: Reader
	END;
	
(** Upcall for macro substitution. Ch is the character to be substituted, res is the substitution text and beg is the starting position inside of the text.*)
	MacroHandler* = PROCEDURE (ch: CHAR; VAR T: Reader; VAR res: Texts.Text; VAR beg: LONGINT);

	Macro = POINTER TO MacroDesc;
	MacroDesc = RECORD
		ch: CHAR;
		handle: MacroHandler;
		next: Macro;
	END;
	
	Scanner* = RECORD	(** Macro substituting scanner *)
		R*: Reader;		(** Scanner operates with this reader. *)
		eot*: BOOLEAN;	(** End of text reached? *)
		nextCh*: CHAR;	(** Character located immediately after scanned token. *)
		class*: INTEGER;		(** Scanner classes. Scanned tokens are returned in the record fields below. *)
		i*: LONGINT;
		x*: REAL;
		y*: LONGREAL;
		c*: CHAR;
		len*: SHORTINT;
		s*: ARRAY MaxLen OF CHAR;
		o*: Objects.Object;
	END ;

	(** Data structures for storing attribute lists. *)
	Attr* = POINTER TO AttrDesc;
	AttrDesc* = RECORD
		next*: Attr;
		name*: ARRAY 32 OF CHAR;
	END;
	
	BoolAttr* = POINTER TO BoolDesc;
	BoolDesc* = RECORD (AttrDesc) b*: BOOLEAN END;
	
	CharAttr* = POINTER TO CharDesc;
	CharDesc* = RECORD (AttrDesc) c*: CHAR END;
	
	IntAttr* = POINTER TO IntDesc;
	IntDesc* = RECORD (AttrDesc) i*: LONGINT END;
	
	RealAttr* = POINTER TO RealDesc;
	RealDesc* = RECORD (AttrDesc) r*: LONGREAL END;
	
	StringAttr* = POINTER TO StringDesc;
	StringDesc* = RECORD (AttrDesc) s*: ARRAY 64 OF CHAR; END;
	
VAR
	W: Texts.Writer;	
	macros: Macro;
	uparrowdone: BOOLEAN;

(* --- Conversion handling --- *)

(** Convert a string to a text. *)
PROCEDURE StrToTxt*(s: ARRAY OF CHAR; VAR T: Texts.Text);
VAR newtext :Texts.Text; i:INTEGER;
BEGIN		
	i := 0;
	WHILE (s[i] # 0X) DO Texts.Write(W, s[i]); INC(i); END;
	NEW(newtext); Texts.Open(newtext, ""); Texts.Append(newtext, W.buf);
	T := newtext;
END StrToTxt;

(** Convert a text to a string. The string might be terminated early if the text is too long to fit. *)
PROCEDURE TxtToStr*(T: Texts.Text; VAR s: ARRAY OF CHAR);
VAR R:Texts.Reader; i:INTEGER; ch:CHAR;
BEGIN
	i:= 0;
	IF T # NIL THEN
		Texts.OpenReader(R, T, 0);
		WHILE ~R.eot  & (i < LEN(s) - 1) DO Texts.Read(R,ch); s[i] := ch; INC(i); END;
	END;
	s[i] := 0X;
END TxtToStr;

(* --- Scanning routines --- *)

PROCEDURE OpenR(VAR R: Reader; text: Texts.Text; pos: LONGINT);
VAR nR: Reader;
BEGIN
	NEW(nR); nR.next := R; R := nR; R.substitute := TRUE;
	Texts.OpenReader(R.R, text, pos); R.text := text; R.eot := R.R.eot;
END OpenR;

(** Read character ch from the Reader. Registered character macros are automatically substituted by making upcalls to the installed macro handlers. *)
PROCEDURE Read*(VAR R: Reader; VAR ch: CHAR);
VAR m: Macro; nT: Texts.Text; beg: LONGINT;
BEGIN
	IF R.eot THEN ch := 0X; RETURN END;
	Texts.Read(R.R, ch);
	R.eot := R.R.eot;  R.lib := R.R.lib;
	IF ~R.eot THEN
		IF ch = "_" THEN (* escape char *)
			IF R.substitute THEN
				beg := Texts.Pos(R.R); Texts.Read(R.R, ch);
				IF ~R.R.eot THEN
					m := macros;
					WHILE (m # NIL) & (m.ch # ch) DO m := m.next END;
					IF m # NIL THEN (* return macro char and do not execute macro *)
						R.lib := R.R.lib; R.eot := FALSE
					ELSE (* no escape *)
						Texts.OpenReader(R.R, R.text, beg-1); Texts.Read(R.R, ch)
					END
				ELSE (* no escape *)
					Texts.OpenReader(R.R, R.text, beg-1); Texts.Read(R.R, ch)
				END
			END
		ELSE
			m := macros;
			WHILE m # NIL DO
				IF R.substitute & (m.ch = ch) & (m.handle # NIL) THEN
					m.handle(ch, R, nT, beg);
					IF nT # NIL THEN
						IF nT.len > 0 THEN OpenR(R, nT, beg); Read(R, ch)
						ELSE Read(R, ch)
						END
					ELSE (* return macro character itself *)
					END
				END;
				m := m.next
			END
		END
	ELSE
		IF R.next # NIL THEN
			R := R.next;
			Read(R, ch)
		END
	END
END Read;

(** Open reader R at position pos in text. *)
PROCEDURE OpenReader*(VAR R: Reader; text: Texts.Text; pos: LONGINT);
VAR m: Macro; nT: Texts.Text; beg: LONGINT;
BEGIN
	NEW(R); R.substitute := TRUE;
	Texts.OpenReader(R.R, text, pos); R.text := text; R.eot := R.R.eot;
	
	(* Reset all macros *)
	m := macros;
	WHILE m # NIL DO
		m.handle(0X, R, nT, beg); m := m.next
	END
END OpenReader;

(** Return current position of Reader R in text R.text. Note that R.text may change as macro characters are being substituted. *)
PROCEDURE Pos*(VAR R: Reader): LONGINT;
BEGIN RETURN Texts.Pos(R.R);
END Pos;

PROCEDURE IsAscii(ch: CHAR): BOOLEAN;
BEGIN
	RETURN ("A" <= CAP(ch)) & (CAP(ch) <= "Z") OR ("0" <= ch) & (ch <= "9") OR
			(ch = "_") OR (ch = ":") OR (ch = "/") OR (ch = ".") OR (ch = "@") OR 
			((ch >= 80X) & (ch <= 96X)) (* german characters *)
END IsAscii;

(** Open Scanner S at position pos in text T. *)
PROCEDURE OpenScanner*(VAR S: Scanner; T: Texts.Text; pos: LONGINT);
BEGIN
	S.R := NIL;
	OpenReader(S.R, T, pos); Read(S.R, S.nextCh)
END OpenScanner;

(** Read the next symbol or object in the text. White space is ignored. *)
  PROCEDURE Scan* (VAR S: Scanner);
    CONST maxD = 32;
    VAR ch, E: CHAR;
      neg, negE, hex, old: BOOLEAN;
      i, j, h: SHORTINT;
      e: INTEGER; k: LONGINT;
      y: LONGREAL;
      d: ARRAY maxD OF CHAR;
	  k1, k2, k3: LONGINT;

  BEGIN ch := S.nextCh; i := 0;
    LOOP
      IF (S.R.lib # NIL) & ~(S.R.lib IS Fonts.Font) THEN EXIT
  	ELSIF ch = CR THEN 
      ELSIF (ch # " ") & (ch # TAB) & (ch # LF) THEN EXIT
      END ;
      Read(S.R, ch);
      IF S.R.eot THEN EXIT END;
    END;
    S.eot := S.R.eot;
    IF S.eot THEN S.class := Inval; RETURN END;
    IF ~(S.eot) &  ~(S.R.R.lib IS Fonts.Font) THEN
    	S.R.R.lib.GetObj(S.R.R.lib, ORD(ch), S.o);
    	S.class := Obj; Read(S.R, ch)
    ELSIF (("A" <= CAP(ch)) & (CAP(ch) <= "Z")) OR (ch = ":") OR (ch = "/") OR (ch = ".") OR
    	((ch >= 80X) & (ch <= 96X)) (* german characters *) THEN (*name*)
      old := S.R.substitute;
      REPEAT S.s[i] := ch; INC(i); Read(S.R, ch)
      UNTIL ~IsAscii(ch) OR (i = MaxLen-1);
      S.s[i] := 0X;
      IF (i = 1) & ((CAP(S.s[0]) < "A") OR (CAP(S.s[0]) > "Z")) THEN
      	S.c := S.s[0]; S.class := Char
      ELSE
      	S.len := i; S.class := Name
      END
    ELSIF ch = 22X THEN (*literal string*)
      old := S.R.substitute; S.R.substitute := FALSE;
      Read(S.R, ch);
      WHILE ~S.R.eot & (ch # 22X) & (ch >= " ") & (i < MaxLen - 1) DO
        S.s[i] := ch; INC(i); Read(S.R, ch)
      END;
      S.s[i] := 0X; S.len := i; Read(S.R, ch); S.R.substitute := old; S.class := String
    ELSIF ch = "'" THEN (*literal string with macro substition*)
      (*old := S.R.substitute; S.R.substitute := FALSE;*)
      Read(S.R, ch);
      WHILE (ch # "'") & (ch >= " ") & (i  < MaxLen - 1) DO
        S.s[i] := ch; INC(i); Read(S.R, ch)
      END;
      S.s[i] := 0X; S.len := i; Read(S.R, ch); (*S.R.substitute := old;*) S.class := String
    ELSE
      IF ch = "-" THEN neg := TRUE; Read(S.R, ch) ELSE neg := FALSE END ;
      IF ("0" <= ch) & (ch <= "9") THEN (*number*)
        hex := FALSE; j := 0;
        LOOP d[i] := ch; INC(i); Read(S.R, ch);
          IF ch < "0" THEN EXIT END;
          IF "9" < ch THEN
            IF ("A" <= ch) & (ch <= "F") THEN hex := TRUE; ch := CHR(ORD(ch)-7)
            ELSIF ("a" <= ch) & (ch <= "f") THEN hex := TRUE; ch := CHR(ORD(ch)-27H)
            ELSE EXIT
            END
          END
        END;
        IF ch = "H" THEN (*hex number*)
          Read(S.R, ch); S.class := Int;
          IF i-j > 8 THEN j := i-8 END ;
          k := ORD(d[j]) - 30H; INC(j);
          IF (i-j = 7) & (k >= 8) THEN DEC(k, 16) END ;
          WHILE j < i DO k := k*10H + (ORD(d[j]) - 30H); INC(j) END ;
          IF neg THEN S.i := -k ELSE S.i := k END 
        ELSIF ch = "." THEN (*read real*)
          Read(S.R, ch); h := i;
          WHILE ("0" <= ch) & (ch <= "9") DO d[i] := ch; INC(i); Read(S.R, ch) END ;
                    (*-------- floating-point handling BM -----------------------------------*)
          WHILE i MOD 8 # 0 DO d[i] := "0"; INC(i) END;
          j := 0; k := 0; k1 := 0; k2 := 0; k3 := 0; (* store digits 0..7, 8..15, 16..23, 24..31 in k, k1, k2, k3 *)
          WHILE j < 8 DO k := k*10 + ORD(d[j]) - ORD("0"); INC(j) END;
          IF 8 < i THEN
            WHILE j < 16 DO k1 := k1*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          IF 16 < i THEN
            WHILE j < 24 DO k2 := k2*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          IF 24 < i THEN
            WHILE j < 32 DO k3 := k3*10 + ORD(d[j]) - ORD("0"); INC(j) END
          END;
          e := 0; E := ch;
          IF (E = "D") OR (E = "E") THEN Read(S.R, ch);
            IF ch = "-" THEN negE := TRUE; Read(S.R, ch)
            ELSE negE := FALSE;
              IF ch = "+" THEN Read(S.R, ch) END
            END;
            WHILE ("0" <= ch) & (ch <= "9") DO e := e*10 + ORD(ch) - ORD("0"); Read(S.R, ch) END;
            IF negE THEN e := - e END
          END;
          y := k3*Reals.Ten(-32) + k2*Reals.Ten(-24); y := y + k1*Reals.Ten(-16);
          IF ABS(e+h) < 308 THEN y := (y + k*Reals.Ten(-8)) / Reals.Ten(-e-h)
          ELSE y := (y + k*Reals.Ten(-8)) * Reals.Ten(h);
            IF (e <= 308-32) OR (e <= 308) & (y < MAX(LONGREAL) / Reals.Ten(e)) THEN y := y * Reals.Ten(e)
              ELSE y := MAX(LONGREAL)
            END
          END;
          IF E = "D" THEN S.class:= LongReal;
            IF y = MAX(LONGREAL) THEN S.y := Reals.RealL(-1, -1)
              ELSIF neg THEN S.y := - y
              ELSE S.y := y
            END;
            IF Reals.ExpoL(S.y) = 0 THEN S.y:= 0 END
          ELSE S.class := Real;
            IF MAX(REAL) < y THEN S.x:= Reals.Real(-1)
            ELSIF neg THEN S.x := SHORT(- y)
            ELSE S.x := SHORT(y)
            END;
            IF Reals.Expo(S.x) = 0 THEN S.x:= 0 END;
			IF hex THEN S.class := Inval END
		  END
        ELSE (*decimal integer*)
          S.class := Int; k := 0;
          REPEAT k := k*10 + (ORD(d[j]) - 30H); INC(j) UNTIL j = i;
          IF neg THEN S.i := -k ELSE S.i := k END;
          IF hex THEN S.class := Inval ELSE S.class := Int END
        END
      ELSE S.class := Char; IF neg THEN S.c := "-" ELSE S.c := ch; Read(S.R, ch) END
      END
    END;
    S.nextCh := ch
  END Scan;

(** Register a macro handler for a character. This handler is called when character ch is read using the reader/scanner, and must return a text with the substitution. *)
PROCEDURE AddMacro*(ch: CHAR; handler: MacroHandler);
VAR M: Macro;
BEGIN
	NEW(M); M.ch := ch; M.handle := handler; M.next := macros; macros := M;
END AddMacro;

PROCEDURE *StandardMacros(ch: CHAR; VAR T: Reader; VAR res: Texts.Text; VAR beg: LONGINT);
VAR text: Texts.Text; bg, end, time: LONGINT;
BEGIN
	IF ch = 0X THEN (* Reset *)
		uparrowdone := FALSE;
	ELSIF (ch = "^") THEN (* getselection *)
		IF ~uparrowdone THEN
			Oberon.GetSelection(text, bg, end, time);
			IF time > 0 THEN
				res := text; beg := bg;
			ELSE
				res := NIL;
			END;
			uparrowdone := TRUE;
		ELSE
			res := NIL; beg := 0;
		END;
	END;
END StandardMacros;

(* Attribute management *)

(** Store the atttribute list A. *)
PROCEDURE StoreAttributes*(VAR R: Files.Rider; A: Attr);
BEGIN
	Files.Write(R, 43X); (* magic number *)
	WHILE A # NIL DO
		Files.WriteString(R, A.name);
		IF A IS BoolAttr THEN Files.Write(R, Sboolean);
			IF A(BoolAttr).b THEN Files.Write(R, 1X) ELSE Files.Write(R, 0X) END;
		ELSIF A IS CharAttr THEN Files.Write(R, Schar); Files.Write(R, A(CharAttr).c);
		ELSIF A IS IntAttr THEN Files.Write(R, Sint); Files.WriteLInt(R, A(IntAttr).i);
		ELSIF A IS RealAttr THEN Files.Write(R, Sreal); Files.WriteLReal(R, A(RealAttr).r);
		ELSIF A IS StringAttr THEN Files.Write(R, Sstring); Files.WriteString(R, A(StringAttr).s);
		ELSE HALT(42)
		END;
		A := A.next
	 END;
	 Files.Write(R, 0X);
END StoreAttributes;

(** Load attribute list resulting in a list A. *)
PROCEDURE LoadAttributes*(VAR R: Files.Rider; VAR A: Attr);
VAR ch: CHAR; name: ARRAY 32 OF CHAR; b: BoolAttr; c: CharAttr; i: IntAttr; r: RealAttr; s: StringAttr; a, a0: Attr;
BEGIN
	A := NIL;
	Files.Read(R, ch);
	IF ch = 43X THEN (* new format *)
		Files.ReadString(R, name);
		WHILE name # "" DO
			Files.Read(R, ch);
			IF ORD(ch) = Sboolean THEN
				Files.Read(R, ch); NEW(b); COPY(name, b.name); b.b := (ch = 1X); a := b;
			ELSIF ORD(ch) = Schar THEN
				NEW(c); COPY(name, c.name); Files.Read(R, c.c); a := c;
			ELSIF ORD(ch) = Sint THEN
				NEW(i); COPY(name, i.name); Files.ReadLInt(R, i.i); a := i;
			ELSIF ORD(ch) = Sreal THEN
				NEW(r); COPY(name, r.name); Files.ReadLReal(R, r.r); a := r;
			ELSIF ORD(ch) = Sstring THEN
				NEW(s); COPY(name, s.name); Files.ReadString(R, s.s); a := s;
			ELSE HALT(42)
			END;
			IF A = NIL THEN A := a; a0 := A ELSE a0.next := a; a0 := a END;
			Files.ReadString(R, name);
		END;
	ELSIF ch = 42X THEN (* just string format *)
		Files.ReadString(R, name);
		WHILE name # "" DO
			NEW(s); COPY(name, s.name); Files.ReadString(R, s.s); a := s;
			IF A = NIL THEN A := a; a0 := A ELSE a0.next := a; a0 := a END;
			Files.ReadString(R, name);
		END;
	ELSE HALT(42)
	END;
END LoadAttributes;

(** Copy an attribute list. *)
PROCEDURE CopyAttributes*(in: Attr; VAR out: Attr);
VAR A: Attr; b: BoolAttr; c: CharAttr; i: IntAttr; r: RealAttr; s: StringAttr; a, a0: Attr;
BEGIN
	A := in; out := NIL;
	WHILE A # NIL DO
		IF A IS BoolAttr THEN  NEW(b); b^ := A(BoolAttr)^; a := b;
		ELSIF A IS CharAttr THEN NEW(c); c^ := A(CharAttr)^; a := c;
		ELSIF A IS IntAttr THEN NEW(i); i^ := A(IntAttr)^; a := i;
		ELSIF A IS RealAttr THEN NEW(r); r^ := A(RealAttr)^; a := r;
		ELSIF A IS StringAttr THEN NEW(s); s^ := A(StringAttr)^; a := s;
		ELSE HALT(42)
		END;
		 IF out = NIL THEN out := a; a0 := out ELSE a0.next := a; a0 := a END;
		A := A.next
	 END;
END CopyAttributes;

(** Insert an attribute in a list. An existing attribute with the same name is discarded. *)
PROCEDURE InsertAttr*(VAR list: Attr; name: ARRAY OF CHAR; val: Attr);
VAR l, p0: Attr;
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
END InsertAttr;

(** Search for an attribute name in list. *)
PROCEDURE FindAttr*(name: ARRAY OF CHAR; list: Attr): Attr;
BEGIN
	WHILE list # NIL DO
		IF name = list.name THEN RETURN list END;
		list := list.next
	END;
	RETURN NIL;
END FindAttr;

(** Delete an attribute. *)
PROCEDURE DeleteAttr*(VAR list: Attr; name: ARRAY OF CHAR);
VAR a, p: Attr;
BEGIN
	a := list; p := NIL; 
	WHILE (a # NIL) & (name # a.name) DO p := a; a := a.next END;
	IF a # NIL THEN (* found *)
		IF p = NIL THEN (* first *) list := a.next
		ELSE p.next := a.next
		END
	END
END DeleteAttr;

(** Write the attribute attr of object obj to the writer W. Format conversion to strings are automatic.*)
PROCEDURE WriteAttr*(obj: Objects.Object; attr: ARRAY OF CHAR; VAR W: Texts.Writer);
VAR A: Objects.AttrMsg; s: ARRAY 64 OF CHAR;
BEGIN
	IF obj # NIL THEN
		A.id := Objects.get; COPY(attr, A.name); A.class := 0; A.res := -1; obj.handle(obj, A);
		IF A.class # 0 THEN
			IF A.class = Objects.Bool THEN Strings.BoolToStr(A.b, s); Texts.WriteString(W, s)
			ELSIF A.class = Objects.Char THEN Texts.Write(W, A.c)
			ELSIF A.class = Objects.Int THEN Strings.IntToStr(A.i, s); Texts.WriteString(W, s)
			ELSIF A.class = Objects.Real THEN Strings.RealToStr(A.x, s); Texts.WriteString(W, s)
			ELSIF A.class = Objects.LongReal THEN Strings.RealToStr(A.y, s); Texts.WriteString(W, s)
			ELSIF A.class = Objects.String THEN Texts.WriteString(W, A.s)
			END
		END
	END
END WriteAttr;

(** GetXXX(obj: Objects.Object; name: ARRAY OF CHAR; VAR x: T);
		Retrieve object attribute name and convert it to type T.
		The following conversions are done by GetType:
	Type	T	Attribute classes converted

	Bool	BOOLEAN	Bool, String, Char
	Int	LONGINT	Int, String, Real, LongReal
	Real	REAL	Real, String, LongReal, Int
	LongReal	LONGREAL	LongReal, String, Real, Int
	String	ARRAY OF CHAR	String, Int, Bool, Real, LongReal, Bool
*)

	PROCEDURE GetBool*(obj: Objects.Object; name: ARRAY OF CHAR; VAR b: BOOLEAN);
		VAR A: Objects.AttrMsg;
	BEGIN
		b := FALSE;
		IF obj # NIL THEN
			A.id := Objects.get; A.res := -1;
			COPY(name, A.name);
			obj.handle(obj, A);
			IF A.res = 0 THEN
				CASE A.class OF
					Objects.Bool: b := A.b
					|Objects.String: Strings.StrToBool(A.s, b)
					|Objects.Char: A.s[0] := A.c; A.s[1] := 0X; Strings.StrToBool(A.s, b)
				ELSE
				END
			END
		END
	END GetBool;

	PROCEDURE GetInt*(obj: Objects.Object; name: ARRAY OF CHAR; VAR i: LONGINT);
		VAR A: Objects.AttrMsg;
	BEGIN
		i := 0;
		IF obj # NIL THEN
			A.id := Objects.get; A.res := -1;
			COPY(name, A.name);
			obj.handle(obj, A);
			IF A.res = 0 THEN
				CASE A.class OF
					Objects.Int: i := A.i
					|Objects.String: Strings.StrToInt(A.s, i)
					|Objects.Real: i := ENTIER(A.x)
					|Objects.LongReal: i := ENTIER(A.y)
				ELSE
				END
			END
		END
	END GetInt;

	PROCEDURE GetReal*(obj: Objects.Object; name: ARRAY OF CHAR; VAR x: REAL);
		VAR A: Objects.AttrMsg;
	BEGIN
		x := 0.0;
		IF obj # NIL THEN
			A.id := Objects.get; A.res := -1;
			COPY(name, A.name);
			obj.handle(obj, A);
			IF A.res = 0 THEN
				CASE A.class OF
					Objects.Real: x := A.x
					|Objects.String: Strings.StrToReal(A.s, A.y); x := SHORT(A.y)
					|Objects.LongReal: x := SHORT(A.y)
					|Objects.Int: x := A.i
				ELSE
				END
			END
		END
	END GetReal;

	PROCEDURE GetLongReal*(obj: Objects.Object; name: ARRAY OF CHAR; VAR y: LONGREAL);
		VAR A: Objects.AttrMsg;
	BEGIN
		y := 0.0;
		IF obj # NIL THEN
			A.id := Objects.get; A.res := -1;
			COPY(name, A.name);
			obj.handle(obj, A);
			IF A.res = 0 THEN
				CASE A.class OF
					Objects.LongReal: y := A.y
					|Objects.String: Strings.StrToReal(A.s, y)
					|Objects.Real: y := A.x
					|Objects.Int: y := A.i
				ELSE
				END
			END
		END
	END GetLongReal;

	PROCEDURE GetString*(obj: Objects.Object; name: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
		VAR A: Objects.AttrMsg;
	BEGIN
		COPY("", s);
		IF obj # NIL THEN
			A.id := Objects.get; A.res := -1;
			COPY(name, A.name);
			obj.handle(obj, A);
			IF A.res = 0 THEN
				CASE A.class OF
					Objects.String: COPY(A.s, s)
					|Objects.Int: Strings.IntToStr(A.i, s)
					|Objects.Bool: Strings.BoolToStr(A.b, s)
					|Objects.Real: Strings.RealToStr(A.x, s)
					|Objects.LongReal: Strings.RealToStr(A.y, s)
					|Objects.Char: s[0] := A.c; s[1] := 0X
				ELSE
				END
			END
		END
	END GetString;

(** SetXXX(obj: Objects.Object; name: ARRAY OF CHAR; x: T);
		Set object attribute name and convert it to the the attribute class understood by obj.
		The following conversions are done by SetType:
	Type	T	Attribute classes converted

	Bool	BOOLEAN	Bool, String, Char
	Int	LONGINT	Int, String, Real, LongReal
	Real	REAL	Real, String, LongReal, Int
	LongReal	LONGREAL	LongReal, String, Real, Int
	String	ARRAY OF CHAR	String, Int, Bool, Real, LongReal, Bool
*)

	PROCEDURE SetBool*(obj: Objects.Object; name: ARRAY OF CHAR; b: BOOLEAN);
		VAR A: Objects.AttrMsg;
	BEGIN
		IF obj # NIL THEN
			A.id := Objects.set; A.res := -1; A.class := Objects.Bool;
			COPY(name, A.name); A.b := b;
			obj.handle(obj, A);
			IF A.res # 0 THEN
				A.id := Objects.get; obj.handle(obj, A);
				CASE A.class OF
					Objects.String: Strings.BoolToStr(b, A.s)
					|Objects.Char: Strings.BoolToStr(b, A.s); A.c := A.s[0]
				ELSE
					RETURN
				END;
				A.id := Objects.set; obj.handle(obj, A)
			END
		END
	END SetBool;

	PROCEDURE SetInt*(obj: Objects.Object; name: ARRAY OF CHAR; i: LONGINT);
		VAR A: Objects.AttrMsg;
	BEGIN
		IF obj # NIL THEN
			A.id := Objects.set; A.res := -1; A.class := Objects.Int;
			COPY(name, A.name); A.i := i;
			obj.handle(obj, A);
			IF A.res # 0 THEN
				A.id := Objects.get; obj.handle(obj, A);
				CASE A.class OF
					Objects.String: Strings.IntToStr(i, A.s)
					|Objects.Real: A.x := i
					|Objects.LongReal: A.y := i
				ELSE
					RETURN
				END;
				A.id := Objects.set; obj.handle(obj, A)
			END
		END
	END SetInt;

	PROCEDURE SetReal*(obj: Objects.Object; name: ARRAY OF CHAR; x: REAL);
		VAR A: Objects.AttrMsg;
	BEGIN
		IF obj # NIL THEN
			A.id := Objects.set; A.res := -1; A.class := Objects.Real;
			COPY(name, A.name); A.x := x;
			obj.handle(obj, A);
			IF A.res # 0 THEN
				A.id := Objects.get; obj.handle(obj, A);
				CASE A.class OF
					Objects.String: Strings.RealToStr(x, A.s)
					|Objects.Int: A.i := ENTIER(x)
					|Objects.LongReal: A.y := x
				ELSE
					RETURN
				END;
				A.id := Objects.set; obj.handle(obj, A)
			END
		END
	END SetReal;

	PROCEDURE SetLongReal*(obj: Objects.Object; name: ARRAY OF CHAR; y: LONGREAL);
		VAR A: Objects.AttrMsg;
	BEGIN
		IF obj # NIL THEN
			A.id := Objects.set; A.res := -1; A.class := Objects.LongReal;
			COPY(name, A.name); A.y := y;
			obj.handle(obj, A);
			IF A.res # 0 THEN
				A.id := Objects.get; obj.handle(obj, A);
				CASE A.class OF
					Objects.String: Strings.RealToStr(y, A.s)
					|Objects.Int: A.i := ENTIER(y)
					|Objects.Real: A.x := SHORT(y)
				ELSE
					RETURN
				END;
				A.id := Objects.set; obj.handle(obj, A)
			END
		END
	END SetLongReal;

	PROCEDURE SetString*(obj: Objects.Object; name, s: ARRAY OF CHAR);
		VAR A: Objects.AttrMsg;
	BEGIN
		IF obj # NIL THEN
			A.id := Objects.set; A.res := -1; A.class := Objects.String;
			COPY(name, A.name); COPY(s, A.s);
			obj.handle(obj, A);
			IF A.res # 0 THEN
				A.id := Objects.get; obj.handle(obj, A);
				CASE A.class OF
					Objects.Int: Strings.StrToInt(s, A.i)
					|Objects.Bool: Strings.StrToBool(s, A.b)
					|Objects.Real: Strings.StrToReal(s, A.y); A.x := SHORT(A.y)
					|Objects.LongReal: Strings.StrToReal(s, A.y)
					|Objects.Char: A.c := A.s[0]
				ELSE
					RETURN
				END;
				A.id := Objects.set; obj.handle(obj, A)
			END
		END
	END SetString;

(** Write all parameters of command. *)
PROCEDURE Echo*;
VAR r: Texts.Reader; ch: CHAR;
BEGIN
	Texts.OpenReader(r, Oberon.Par.text, Oberon.Par.pos);
	Texts.Read(r, ch);
	IF ch = " " THEN Texts.Read(r, ch) END;
	WHILE ~r.eot & (ch # "~") DO
		Texts.Write(W, ch);
		Texts.Read(r, ch)
	END;
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Echo;

BEGIN
	Texts.OpenWriter(W); AddMacro("^", StandardMacros);
END Attributes.

(**
Remarks:

1. Reader and Scanner
The reader and scanner operate in the same fashion as that of the Text module. There are however a few exceptions. First, the reader does macro substitution as texts are read. Some macros are predefined, and the programmer has the capability to add his or her own macros by identifying special symbols for macros and a handler for that macro symbol. While reading or scanning a text, upcalls are made to the registered macro handler to return a substitution text for the macro symbol. New macros are registered with the AddMacro procedure. The macro handler has to return a text and a position in the text where reading/scanning should continue. Reading/scanning will continue in the original text after the end of the substitution text is reached. The macro might take parameters (letters that follow immediately after the macro symbol), which are read by the macro handler using the passed Reader. Note that no substitution is made when no text (= NIL) is returned. By default, the up arrow ("^"), which expands to the current selection, is installed as a macro in the Attributes module. In contrast to the Texts.Scanner, the Attributes.Scanner scan words containing letters like ä, ü, ö, ß etc, and (non-character) objects embedded inside of the text.

2. Attribute Message and Attribute Storage
Most gadgets employ two strategies for storing attribute values. The first is by allocating own storage space for the attributes in the object definition and by responding on the Objects.AttrMsg when these attributes are accessed. The second way is having the default message handlers of module Gadgets take care of attributes. This is called the default or standard handling of attributes. The default message handlers manage lists of gadgets with the types defined in module Attributes. Such an attribute list is always identified by its first component, which might change when attributes are inserted or deleted. Many gadgets uses a hybrid approach to attribute handling, where own attributes are handled in a special way, and all other attributes are handled by the default message handlers. For example, the "Name" of a gadget is typically handled by the default message handlers. This has the advantage that storage space is only used when the attribute has a value (remember that many gadgets don't have names, and allocating space inside your own gadget record descriptor for a name, makes you pay the storage price for each gadget, even if it is not named).

*)