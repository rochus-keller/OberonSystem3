MODULE OTInt;	(** eos   **)

	(**
		Interpreter for grid-fitting TrueType font instructions
	**)
	
	CONST
		X* = 1; Y* = 0;	(** indices for coordinates into Coord structure **)
		
	
	TYPE
		F26D6* = LONGINT;	(** fixed point format 26.6 used for fractional pixel coordinates **)
		F2D14* = INTEGER;	(** fixed point format 2.14 used for unit vectors **)
		FUnit* = INTEGER;	(** unscaled point coordinates **)
		Fixed* = LONGINT;	(** fixed point format 16.16 used for scalar fixed point numbers **)
		
		INT64 = ARRAY 8 OF CHAR;	(* huge integers for extended precision arithmetic *)
		
		(** program code **)
		Code* = POINTER TO ARRAY OF CHAR;
		
		(** program stack **)
		Stack* = POINTER TO ARRAY OF LONGINT;
		
		(** addresses within code blocks **)
		Address* = RECORD
			code*: Code;	(** instruction sequence **)
			len*: LONGINT;	(** code length **)
			pc*: LONGINT;	(** location within code **)
		END;
		
		(** user defined functions **)
		Functions* = POINTER TO ARRAY OF Address;
		
		(** user defined instructions **)
		Instruction* = RECORD
			beg*: Address;	(* starting point *)
			opcode*: CHAR;	(* instruction opcode *)
		END;
		Instructions* = POINTER TO ARRAY OF Instruction;
		
		(** call stack **)
		Frame* = RECORD
			ret*: Address;	(* return address *)
			start*: LONGINT;	(* starting pc of function (within context.code) *)
			count*: INTEGER;	(* number of times the function has to be evaluated *)
		END;
		CallStack* = POINTER TO ARRAY OF Frame;
		
		(** program store **)
		Store* = POINTER TO ARRAY OF LONGINT;
		
		(** control value table **)
		CVT* = POINTER TO ARRAY OF F26D6;
		
		(** glyph zone **)
		Contours* = POINTER TO ARRAY OF INTEGER;
		Coord* = ARRAY 2 OF F26D6;
		Point* = RECORD
			org*, cur*: Coord;	(** original and current point coordinates **)
			onCurve*: BOOLEAN;	(** is point on or off the curve? **)
			touched*: ARRAY 2 OF BOOLEAN;	(** is point touched in x/y direction? **)
		END;
		Points* = POINTER TO ARRAY OF Point;
		
		Zone* = POINTER TO ZoneDesc;
		ZoneDesc* = RECORD
			contours*: INTEGER;	(** number of contours in this zone **)
			first*: Contours;	(** starting points of each contour; first[contours] contains total number of points in zone **)
			pt*: Points;	(** points in this zone **)
		END;
		
		(** unit vector **)
		Vector* = RECORD
			x*, y*: F2D14;
		END;
		
		(** execution context **)
		Context* = RECORD
			code*: Code;	(** program code **)
			codeLen*: LONGINT;	(* code length *)
			stack*: Stack;	(** program stack **)
			callStack*: CallStack;	(** call stack of program **)
			pc*: LONGINT;	(* current position within code *)
			tos*: INTEGER;	(* stack pointer *)
			ctos*: INTEGER;	(* call stack pointer *)
			
			func*: Functions;	(** user defined functions **)
			instr*: Instructions;	(** user defined instructions **)
			store*: Store;	(** program store **)
			cvt*: CVT;	(** control value table **)
			zone*: ARRAY 2 OF Zone;	(** twilight and glyph zone **)
			
			ptsize*: F26D6;	(** current point size **)
			xppm*, yppm*, ppm: F26D6;	(** number of pixels per Em in x/y direction **)
			upm*: INTEGER;	(** units per Em **)
			rotated*, stretched*: BOOLEAN;	(* glyph transformation info *)
			xratio, yratio, ratio*: Fixed;	(** aspect ratio **)
			
			minDist*: F26D6;	(** feature preserving minimum distance **)
			cvtCutIn*: F26D6;	(** control value table cut in **)
			swVal*, swCutIn*: F26D6;	(** single width cut in and single width value **)
			deltaBase*, deltaShift*: INTEGER;	(** delta exception parameters **)
			autoFlip*: BOOLEAN;	(** whether to make CVT entries sign independent **)
			inhibitFit*, ignorePrep*: BOOLEAN;	(** instruction control flags **)
			fixDropouts*: BOOLEAN;	(** scan control flag **)
			scanType*: INTEGER;	(** current scan type **)
			
			rp0*, rp1*, rp2*: INTEGER;	(** reference points **)
			gep0*, gep1*, gep2*: INTEGER;	(** zone indices **)
			zp0, zp1, zp2: Zone;	(* zone pointers, equal to zone[gepN] *)
			free*, proj*, proj2*: Vector;	(** freedom vector, projection vector, and dual projection vector **)
			period*, phase*, threshold*: F26D6;	(** parameters of current round state **)
			loop*: INTEGER;	(** number of times to execute the next loop-aware instruction **)
		END;
		
		(** static part of graphics state **)
		State* = RECORD
			minDist: F26D6;
			cvtCutIn: F26D6;
			swVal, swCutIn: F26D6;
			deltaBase, deltaShift: INTEGER;
			autoFlip: BOOLEAN;
			inhibitFit, ignorePrep: BOOLEAN;
			fixDropouts: BOOLEAN;
			scanType: INTEGER;
		END;
		
		(** debug upcalls **)
		NotifierData* = POINTER TO NotifierDesc;
		NotifierDesc* = RECORD END;
		Notifier* = PROCEDURE (VAR c: Context; data: NotifierData);
		
		Primitive = PROCEDURE (VAR c: Context);
		
	
	VAR
		EmptyZone*: Zone;	(** zone containing zero contours and zero points **)
		Builtin: ARRAY 256 OF Primitive;	(* instruction for each opcode *)
		Zero64: INT64;
		Notify: Notifier;
		NotifyData: NotifierData;
		
	
	(*--- 64bit Arithmetic ---*)
	
	PROCEDURE ToINT64 (x: LONGINT; VAR y: INT64);
	BEGIN
		y[0] := CHR(x MOD 100H);
		y[1] := CHR(ASH(x, -8) MOD 100H);
		y[2] := CHR(ASH(x, -16) MOD 100H);
		y[3] := CHR(ASH(x, -24) MOD 100H);
		y[4] := CHR(ASH(x, -31) MOD 100H);
		y[5] := y[4]; y[6] := y[4]; y[7] := y[4]
	END ToINT64;
	
	PROCEDURE FromINT64 (x: INT64; VAR y: LONGINT);
	BEGIN
		y := ASH(ORD(x[3]), 24) + ASH(ORD(x[2]), 16) + ASH(ORD(x[1]), 8) + ORD(x[0])
	END FromINT64;
	
	PROCEDURE AddINT64 (a, b: INT64; VAR c: INT64);
		VAR sum, i: LONGINT;
	BEGIN
		sum := 0;
		FOR i := 0 TO 7 DO
			sum := ORD(a[i]) + ORD(b[i]) + ASH(sum, -8) MOD 100H;
			c[i] := CHR(sum MOD 100H)
		END
	END AddINT64;
	
	PROCEDURE SubINT64 (a, b: INT64; VAR c: INT64);
		VAR sum, i: LONGINT;
	BEGIN
		sum := 256;
		FOR i := 0 TO 7 DO
			sum := 255 + ORD(a[i]) - ORD(b[i]) + ASH(sum, -8) MOD 100H;
			c[i] := CHR(sum MOD 100H)
		END
	END SubINT64;
	
	PROCEDURE LeqINT64 (a, b: INT64): BOOLEAN;
		VAR i: LONGINT;
	BEGIN
		IF (a[7] >= 80X) & (b[7] < 80X) THEN
			RETURN TRUE
		ELSIF (a[7] < 80X) & (b[7] >= 80X) THEN
			RETURN FALSE
		ELSE
			FOR i := 7 TO 0 BY -1 DO
				IF a[i] < b[i] THEN RETURN TRUE
				ELSIF a[i] > b[i] THEN RETURN FALSE
				END
			END;
			RETURN TRUE	(* equal *)
		END
	END LeqINT64;
	
	PROCEDURE ShiftINT64 (VAR a: INT64; n: LONGINT);
		VAR c, i, j, b: LONGINT;
	BEGIN
		c := 0;
		IF n > 0 THEN
			n := n MOD 64;
			i := 7; j := 7 - n DIV 8; n := n MOD 8;
			c := ASH(ORD(a[j]), n) MOD 100H;
			WHILE j > 0 DO
				DEC(j); b := ORD(a[j]);
				a[i] := CHR(c + ASH(b, n-8)); DEC(i);
				c := ASH(b, n) MOD 100H
			END;
			WHILE i >= 0 DO
				a[i] := CHR(c); c := 0; DEC(i)
			END
		ELSIF n < 0 THEN
			n := (-n) MOD 64;
			i := 0; j := n DIV 8; n := n MOD 8;
			c := ASH(ORD(a[j]), -n);
			WHILE j < 7 DO
				INC(j); b := ORD(a[j]);
				a[i] := CHR(c + ASH(b, 8-n) MOD 100H); INC(i);
				c := ASH(b, -n)
			END;
			WHILE i < 8 DO
				a[i] := CHR(c); c := ASH(c, -8); INC(i)
			END
		END
	END ShiftINT64;
	
	PROCEDURE MulINT64 (a, b: INT64; VAR c: INT64);
		VAR i, sum, j: LONGINT;
	BEGIN
		FOR i := 0 TO 7 DO c[i] := 0X END;
		FOR i := 0 TO 7 DO
			sum := 0;
			FOR j := 0 TO 7-i DO
				sum := LONG(ORD(a[i])) * LONG(ORD(b[j])) + ASH(sum, -8) MOD 100H + ORD(c[i+j]);
				c[i+j] := CHR(sum MOD 100H)
			END
		END
	END MulINT64;
	
	PROCEDURE DivINT64 (a, b: INT64; VAR q: INT64);
		VAR positive: BOOLEAN; i: LONGINT; e: INT64;
	BEGIN
		positive := TRUE;
		IF ~LeqINT64(Zero64, a) THEN positive := ~positive; SubINT64(Zero64, a, a) END;
		IF ~LeqINT64(Zero64, b) THEN positive := ~positive; SubINT64(Zero64, b, b) END;
		FOR i := 0 TO 7 DO q[i] := 0X; e[i] := 0X END; e[0] := 1X;
		ShiftINT64(b, 32);
		i := 0;
		REPEAT
			ShiftINT64(q, 1); ShiftINT64(b, -1);
			IF LeqINT64(b, a) THEN
				SubINT64(a, b, a); AddINT64(q, e, q)
			END;
			INC(i)
		UNTIL i = 32;
		IF ~positive THEN SubINT64(Zero64, q, q) END
	END DivINT64;
	
	
	(**--- Arithmetic ---**)
	
	PROCEDURE ShiftDiv* (a, n, d: LONGINT): LONGINT;
		VAR b, r: LONGINT; a64, d64, h64: INT64;
	BEGIN
		b := ASH(1, 31-n);
		IF (-b <= a) & (a < b) THEN
			r := (ASH(a, n) + d DIV 2) DIV d
		ELSE
			ToINT64(a, a64); ShiftINT64(a64, n);
			ToINT64(d, d64); h64 := d64; ShiftINT64(h64, -1);
			AddINT64(a64, h64, a64);
			DivINT64(a64, d64, a64);
			FromINT64(a64, r)
		END;
		RETURN r
	END ShiftDiv;
	
	PROCEDURE MulShift* (a, b, n: LONGINT): LONGINT;
		VAR a64, b64, c64: INT64; c: LONGINT;
	BEGIN
		IF (-10000H <= a) & (a < 10000H) & (-8000H <= b) & (b < 8000H) THEN
			RETURN ASH(a * b, n)
		ELSE
			ToINT64(a, a64); ToINT64(b, b64);
			MulINT64(a64, b64, c64); ShiftINT64(c64, n);
			FromINT64(c64, c);
			RETURN c
		END
	END MulShift;
	
	PROCEDURE MulDiv* (a, b, c: LONGINT): LONGINT;
		VAR a64, b64, m64, c64, d64: INT64; d: LONGINT;
	BEGIN
		IF (-10000H <= a) & (a < 10000H) & (-8000H <= b) & (b < 8000H) THEN
			IF c > 0 THEN
				RETURN (a * b + c DIV 2) DIV c
			ELSIF c < 0 THEN
				c := -c;
				RETURN -((a * b + c DIV 2) DIV c)
			END
		ELSE
			ToINT64(a, a64); ToINT64(b, b64);
			MulINT64(a64, b64, m64);
			ToINT64(c, c64); DivINT64(m64, c64, d64);
			FromINT64(d64, d);
			RETURN d
		END
	END MulDiv;
	
	PROCEDURE Norm* (x, y: F26D6): F26D6;
		VAR n, r, b, t, i: LONGINT; x64, y64, n64, r64, b64, t64: INT64;
	BEGIN
		IF (-8000H <= x) & (x < 8000H) & (-8000H <= y) & (y < 8000H) THEN	(* x*x + y*y representable in 32 bits *)
			n := x * x + y * y;
			r := 0; b := 40000000H;
			REPEAT
				t := r + b;
				IF t <= n THEN
					DEC(n, t);
					r := t + b
				END;
				r := r DIV 2; b := b DIV 4
			UNTIL b = 0
		ELSE
			ToINT64(x, x64); ToINT64(y, y64);
			MulINT64(x64, x64, x64); MulINT64(y64, y64, y64);
			AddINT64(x64, y64, n64);
			FOR i := 0 TO 7 DO r64[i] := 0X; b64[i] := 0X END; b64[7] := 40X;
			REPEAT
				AddINT64(r64, b64, t64);
				IF LeqINT64(t64, n64) THEN
					SubINT64(n64, t64, n64);
					AddINT64(t64, b64, r64)
				END;
				ShiftINT64(r64, -1); ShiftINT64(b64, -2);
				i := 0; WHILE (i < 8) & (b64[i] = 0X) DO INC(i) END
			UNTIL i = 8;
			FromINT64(r64, r)
		END;
		RETURN r
	END Norm;
	
	
	(*--- Auxiliary Routines ---*)
	
	PROCEDURE Ratio (VAR c: Context): Fixed;
		VAR x, y: Fixed;
	BEGIN
		IF c.ratio = 0 THEN
			IF c.proj.y = 0 THEN
				c.ratio := c.xratio
			ELSIF c.proj.x = 0 THEN
				c.ratio := c.yratio
			ELSE
				x := ASH(c.proj.x * c.xratio, -14);
				y := ASH(c.proj.y * c.yratio, -14);
				c.ratio := Norm(x, y)
			END
		END;
		RETURN c.ratio
	END Ratio;
	
	PROCEDURE PPEm (VAR c: Context): F26D6;
	BEGIN
		RETURN MulShift(c.ppm, Ratio(c), -16)
	END PPEm;
	
	PROCEDURE FUnitToPixel (fu: FUnit; VAR c: Context): F26D6;
	BEGIN
		RETURN (LONG(fu) * PPEm(c) + c.upm DIV 2) DIV c.upm
	END FUnitToPixel;
	
	PROCEDURE CVTValue (n: LONGINT; VAR c: Context): F26D6;
		VAR ratio: F26D6;
	BEGIN
		IF n < 0 THEN
			RETURN 0	(* some fonts use CVT[-1]; FreeType and TTI return 0, too *)
		ELSE
			ratio := Ratio(c);
			IF ratio = 10000H THEN RETURN c.cvt[n]
			ELSE RETURN MulShift(c.cvt[n], ratio, -16)
			END
		END
	END CVTValue;
	
	PROCEDURE Round (x, period, phase, threshold: F26D6): F26D6;
		VAR sign: F26D6;
	BEGIN
		sign := x; x := ABS(x);
		x := x - phase + threshold;
		x := x - x MOD period + phase;
		IF x < 0 THEN INC(x, period) END;
		IF sign < 0 THEN x := -x END;
		RETURN x
	END Round;
	
	PROCEDURE Project (crd: Coord; proj: Vector): F26D6;
	BEGIN
		RETURN MulShift(crd[X], proj.x, -14) + MulShift(crd[Y], proj.y, -14)	(* dot product of point and unit vector *)
	END Project;
	
	PROCEDURE GetDistance (from, to: Coord; VAR dx, dy: F26D6);
	BEGIN
		dx := to[X] - from[X]; dy := to[Y] - from[Y]
	END GetDistance;
	
	PROCEDURE Move (VAR p: Point; free, proj: Vector; dist: F26D6);
		VAR dot: LONGINT;
	BEGIN
		IF proj.x = 4000H THEN
			IF free.x # 0 THEN
				INC(p.cur[X], dist); p.touched[X] := TRUE;
				IF free.x # 4000H THEN
					INC(p.cur[Y], MulDiv(free.y, dist, free.x)); p.touched[Y] := TRUE
				END
			END
		ELSIF proj.y = 4000H THEN
			IF free.y # 0 THEN
				INC(p.cur[Y], dist); p.touched[Y] := TRUE;
				IF free.y # 4000H THEN
					INC(p.cur[X], MulDiv(free.x, dist, free.y)); p.touched[X] := TRUE
				END
			END
		ELSE
			dot := LONG(proj.x) * LONG(free.x) + LONG(proj.y) * LONG(free.y);
			INC(p.cur[X], MulDiv(4000H*LONG(free.x), dist, dot)); p.touched[X] := TRUE;
			INC(p.cur[Y], MulDiv(4000H*LONG(free.y), dist, dot)); p.touched[Y] := TRUE
		END
	END Move;
	
	PROCEDURE GetRefDist (VAR c: Context; flag: BOOLEAN; VAR zone: Zone; VAR ref: LONGINT; VAR dx, dy: F26D6);
		VAR dot: LONGINT; dist: F26D6;
	BEGIN
		IF flag THEN	(* rp1 in zp0 *)
			ref := c.rp1; zone := c.zp0
		ELSE	(* use rp2 in zp1 *)
			ref := c.rp2; zone := c.zp1
		END;
		dist := Project(zone.pt[ref].cur, c.proj) - Project(zone.pt[ref].org, c.proj);
		dot := LONG(c.proj.x) * LONG(c.free.x) + LONG(c.proj.y) * LONG(c.free.y);
		IF dot # 0 THEN
			IF (c.free.x # 0) & (c.free.y # 0) THEN
				dx := MulDiv(c.free.x, dist, dot);
				dy := MulDiv(c.free.y, dist, dot)
			ELSIF c.free.x # 0 THEN
				dx := dist; dy := 0
			ELSIF c.free.y # 0 THEN
				dy := dist; dx := 0
			END
		ELSE
			dx := 0; dy := 0
		END
	END GetRefDist;
	
	
	(*--- Pushing Data onto the Interpreter Stack ---*)
	
	(* push n bytes *)
	PROCEDURE NPUSHB (VAR c: Context);
		VAR n: LONGINT;
	BEGIN
		INC(c.pc); n := ORD(c.code[c.pc]);
		WHILE n > 0 DO
			INC(c.pc); INC(c.tos); c.stack[c.tos] := ORD(c.code[c.pc]);
			DEC(n)
		END;
		INC(c.pc)
	END NPUSHB;
	
	(* push n words *)
	PROCEDURE NPUSHW (VAR c: Context);
		VAR n, hi, lo: LONGINT;
	BEGIN
		INC(c.pc); n := ORD(c.code[c.pc]);
		WHILE n > 0 DO
			INC(c.pc); hi := ORD(c.code[c.pc]);
			IF hi >= 128 THEN DEC(hi, 256) END;
			INC(c.pc); lo := ORD(c.code[c.pc]);
			INC(c.tos); c.stack[c.tos] := 256*hi + lo;
			DEC(n)
		END;
		INC(c.pc)
	END NPUSHW;
	
	(* push bytes *)
	PROCEDURE PUSHB (VAR c: Context);
		VAR n: LONGINT;
	BEGIN
		n := ORD(c.code[c.pc]) - 0B0H;
		WHILE n >= 0 DO
			INC(c.pc); INC(c.tos); c.stack[c.tos] := ORD(c.code[c.pc]);
			DEC(n)
		END;
		INC(c.pc)
	END PUSHB;
	
	(* push words *)
	PROCEDURE PUSHW (VAR c: Context);
		VAR n, hi, lo: LONGINT;
	BEGIN
		n := ORD(c.code[c.pc]) - 0B8H;
		WHILE n >= 0 DO
			INC(c.pc); hi := ORD(c.code[c.pc]);
			IF hi >= 128 THEN DEC(hi, 256) END;
			INC(c.pc); lo := ORD(c.code[c.pc]);
			INC(c.tos); c.stack[c.tos] := 256*hi + lo;
			DEC(n)
		END;
		INC(c.pc)
	END PUSHW;
	
	
	(*--- Managing the Storage Area ---*)
	
	(* read store *)
	PROCEDURE RS (VAR c: Context);
	BEGIN
		c.stack[c.tos] := c.store[c.stack[c.tos]]; INC(c.pc)
	END RS;
	
	(* write store *)
	PROCEDURE WS (VAR c: Context);
		VAR value: LONGINT;
	BEGIN
		value := c.stack[c.tos]; DEC(c.tos);
		c.store[c.stack[c.tos]] := value; DEC(c.tos);
		INC(c.pc)
	END WS;
	
	
	(*--- Managing the Control Value Table ---*)
	
	(* write control value table in pixels or FUnits *)
	PROCEDURE WCVT (VAR c: Context);
		VAR value: F26D6;
	BEGIN
		value := c.stack[c.tos]; DEC(c.tos);
		IF c.code[c.pc] = 70X THEN
			value := FUnitToPixel(SHORT(value), c)
		END;
		c.cvt[c.stack[c.tos]] := ShiftDiv(value, 16, Ratio(c)); DEC(c.tos);
		INC(c.pc)
	END WCVT;
	
	(* read control value table *)
	PROCEDURE RCVT (VAR c: Context);
	BEGIN
		c.stack[c.tos] := CVTValue(c.stack[c.tos], c); INC(c.pc)
	END RCVT;
	
	
	(*--- Managing the Graphics State ---*)
	
	(* set freedom and projection vectors to coordinate axis *)
	PROCEDURE SVTCA (VAR c: Context);
	BEGIN
		IF ODD(ORD(c.code[c.pc])) THEN	(* set to x-axis *)
			c.proj.x := 4000H; c.proj.y := 0
		ELSE	(* set to y-axis *)
			c.proj.x := 0; c.proj.y := 4000H
		END;
		c.free := c.proj; c.proj2 := c.proj;
		c.ratio := 0;
		INC(c.pc)
	END SVTCA;
	
	(* set projection vector to coordinate axis *)
	PROCEDURE SPVTCA (VAR c: Context);
	BEGIN
		IF ODD(ORD(c.code[c.pc])) THEN	(* set to x-axis *)
			c.proj.x := 4000H; c.proj.y := 0
		ELSE	(* set to y-axis *)
			c.proj.x := 0; c.proj.y := 4000H
		END;
		c.proj2 := c.proj;
		c.ratio := 0;
		INC(c.pc)
	END SPVTCA;
	
	(* set freedom vector to coordinate axis *)
	PROCEDURE SFVTCA (VAR c: Context);
	BEGIN
		IF ODD(ORD(c.code[c.pc])) THEN	(* set to x-axis *)
			c.free.x := 4000H; c.free.y := 0
		ELSE	(* set to y-axis *)
			c.free.x := 0; c.free.y := 4000H
		END;
		INC(c.pc)
	END SFVTCA;
	
	(* set projection vector to line *)
	PROCEDURE SPVTL (VAR c: Context);
		VAR p1, p2: LONGINT; dx, dy, d: F26D6;
	BEGIN
		p1 := c.stack[c.tos]; DEC(c.tos);
		p2 := c.stack[c.tos]; DEC(c.tos);
		GetDistance(c.zp2.pt[p1].cur, c.zp1.pt[p2].cur, dx, dy);	(* note: TTI had zp1 and zp2 swapped *)
		d := Norm(dx, dy);
		IF d = 0 THEN
			dx := 0; dy := 0
		ELSE
			dx := ShiftDiv(dx, 14, d);
			dy := ShiftDiv(dy, 14, d)
		END;
		IF ODD(ORD(c.code[c.pc])) THEN	(* rotate by 90 degrees *)
			c.proj.x := SHORT(-dy); c.proj.y := SHORT(dx)
		ELSE
			c.proj.x := SHORT(dx); c.proj.y := SHORT(dy)
		END;
		c.proj2 := c.proj;
		c.ratio := 0;
		INC(c.pc)
	END SPVTL;
	
	(* set freedom vector to line *)
	PROCEDURE SFVTL (VAR c: Context);
		VAR p1, p2: LONGINT; dx, dy, d: F26D6;
	BEGIN
		p1 := c.stack[c.tos]; DEC(c.tos);
		p2 := c.stack[c.tos]; DEC(c.tos);
		GetDistance(c.zp2.pt[p1].cur, c.zp1.pt[p2].cur, dx, dy);	(* note: TTI had zp1 and zp2 swapped *)
		d := Norm(dx, dy);
		IF d = 0 THEN
			dx := 0; dy := 0
		ELSE
			dx := ShiftDiv(dx, 14, d);
			dy := ShiftDiv(dy, 14, d)
		END;
		IF ODD(ORD(c.code[c.pc])) THEN	(* rotate by 90 degrees *)
			c.free.x := SHORT(-dy); c.free.y := SHORT(dx)
		ELSE
			c.free.x := SHORT(dx); c.free.y := SHORT(dy)
		END;
		INC(c.pc)
	END SFVTL;
	
	(* set freedom vector to projection vector *)
	PROCEDURE SFVTPV (VAR c: Context);
	BEGIN
		c.free := c.proj; INC(c.pc)
	END SFVTPV;
	
	(* set dual projection vector to line *)
	PROCEDURE SDPVTL (VAR c: Context);
		VAR p1, p2: LONGINT; dx, dy, d: F26D6;
	BEGIN
		p1 := c.stack[c.tos]; DEC(c.tos);
		p2 := c.stack[c.tos]; DEC(c.tos);
		GetDistance(c.zp2.pt[p1].org, c.zp1.pt[p2].org, dx, dy);	(* note: TTI had zp1 and zp2 swapped *)
		d := Norm(dx, dy);
		dx := ShiftDiv(dx, 14, d);
		dy := ShiftDiv(dy, 14, d);
		IF ODD(ORD(c.code[c.pc])) THEN	(* rotate by 90 degrees *)
			c.proj2.x := SHORT(-dy); c.proj2.y := SHORT(dx)
		ELSE
			c.proj2.x := SHORT(dx); c.proj2.y := SHORT(dy)
		END;
		
		(* projection vector must be set as well, but with current coordinates (FreeType agrees on this) *)
		GetDistance(c.zp2.pt[p1].cur, c.zp1.pt[p2].cur, dx, dy);	(* note: TTI had zp1 and zp2 swapped *)
		d := Norm(dx, dy);
		dx := ShiftDiv(dx, 14, d);
		dy := ShiftDiv(dy, 14, d);
		IF ODD(ORD(c.code[c.pc])) THEN	(* rotate by 90 degrees *)
			c.proj.x := SHORT(-dy); c.proj.y := SHORT(dx)
		ELSE
			c.proj.x := SHORT(dx); c.proj.y := SHORT(dy)
		END;
		c.ratio := 0;
		INC(c.pc)
	END SDPVTL;
	
	(* set projection vector from stack *)
	PROCEDURE SPVFS (VAR c: Context);
	BEGIN
		c.proj.y := SHORT(c.stack[c.tos]); DEC(c.tos);
		c.proj.x := SHORT(c.stack[c.tos]); DEC(c.tos);
		c.proj2 := c.proj;
		c.ratio := 0;
		INC(c.pc)
	END SPVFS;
	
	(* set freedom vector from stack *)
	PROCEDURE SFVFS (VAR c: Context);
	BEGIN
		c.free.y := SHORT(c.stack[c.tos]); DEC(c.tos);
		c.free.x := SHORT(c.stack[c.tos]); DEC(c.tos);
		INC(c.pc)
	END SFVFS;
	
	(* get projection vector *)
	PROCEDURE GPV (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := c.proj.x;
		INC(c.tos); c.stack[c.tos] := c.proj.y;
		INC(c.pc)
	END GPV;
	
	(* get freedom vector *)
	PROCEDURE GFV (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := c.free.x;
		INC(c.tos); c.stack[c.tos] := c.free.y;
		INC(c.pc)
	END GFV;
	
	(* set reference point i *)
	PROCEDURE SRPi (VAR c: Context);
		VAR rp: INTEGER;
	BEGIN
		rp := SHORT(c.stack[c.tos]); DEC(c.tos);
		CASE c.code[c.pc] OF
		| 10X: c.rp0 := rp
		| 11X: c.rp1 := rp
		| 12X: c.rp2 := rp
		END;
		INC(c.pc)
	END SRPi;
	
	(* set zone pointer i *)
	PROCEDURE SZPi (VAR c: Context);
		VAR gep: INTEGER;
	BEGIN
		gep := SHORT(c.stack[c.tos]); DEC(c.tos);
		CASE c.code[c.pc] OF
		| 13X: c.gep0 := gep; c.zp0 := c.zone[gep]
		| 14X: c.gep1 := gep; c.zp1 := c.zone[gep]
		| 15X: c.gep2 := gep; c.zp2 := c.zone[gep]
		END;
		INC(c.pc)
	END SZPi;
	
	(* set zone pointers *)
	PROCEDURE SZPS (VAR c: Context);
	BEGIN
		c.gep0 := SHORT(c.stack[c.tos]); DEC(c.tos); c.gep1 := c.gep0; c.gep2 := c.gep2;
		c.zp0 := c.zone[c.gep0]; c.zp1 := c.zp0; c.zp2 := c.zp0;
		INC(c.pc)
	END SZPS;
	
	(* round to half grid *)
	PROCEDURE RTHG (VAR c: Context);
	BEGIN
		c.period := 40H; c.phase := 20H; c.threshold := 20H; INC(c.pc)
	END RTHG;
	
	(* round to grid *)
	PROCEDURE RTG (VAR c: Context);
	BEGIN
		c.period := 40H; c.phase := 0; c.threshold := 20H; INC(c.pc)
	END RTG;
	
	(* round to double grid *)
	PROCEDURE RTDG (VAR c: Context);
	BEGIN
		c.period := 20H; c.phase := 0; c.threshold := 10H; INC(c.pc)
	END RTDG;
	
	(* round down to grid *)
	PROCEDURE RDTG (VAR c: Context);
	BEGIN
		c.period := 40H; c.phase := 0; c.threshold := 0; INC(c.pc)
	END RDTG;
	
	(* round up to grid *)
	PROCEDURE RUTG (VAR c: Context);
	BEGIN
		c.period := 40H; c.phase := 0; c.threshold := 3FH; INC(c.pc)
	END RUTG;
	
	(* round off *)
	PROCEDURE ROFF (VAR c: Context);
	BEGIN
		c.period := 1; c.phase := 0; c.threshold := 0; INC(c.pc)
	END ROFF;
	
	(* super round and super round 45 degrees *)
	PROCEDURE SROUND (VAR c: Context);
		VAR gridPeriod: F26D6; code, cd: LONGINT;
	BEGIN
		IF ODD(ORD(c.code[c.pc])) THEN	(* super round 45 degrees *)
			gridPeriod := 45	(* funnily enough, this is really 64*(1/sqrt(2)) *)
		ELSE
			gridPeriod := 64
		END;
		code := c.stack[c.tos]; DEC(c.tos);
		cd := ASH(code, -6) MOD 4;
		CASE cd OF
		| 0: c.period := gridPeriod DIV 2
		| 1: c.period := gridPeriod
		| 2: c.period := 2*gridPeriod
		END;
		cd := ASH(code, -4) MOD 2;
		c.phase := cd * c.period DIV 4;
		cd := code MOD 16;
		IF cd = 0 THEN
			c.threshold := c.period-1
		ELSE
			c.threshold := c.period * (cd-4) DIV 8
		END;
		INC(c.pc)
	END SROUND;
	
	(* set loop variable *)
	PROCEDURE SLOOP (VAR c: Context);
	BEGIN
		c.loop := SHORT(c.stack[c.tos]); DEC(c.tos); INC(c.pc)
	END SLOOP;
	
	(* set minimum distance *)
	PROCEDURE SMD (VAR c: Context);
	BEGIN
		c.minDist := c.stack[c.tos]; DEC(c.tos); INC(c.pc)
	END SMD;
	
	(* instruction execution control *)
	PROCEDURE INSTCTRL (VAR c: Context);
		VAR sel, val: LONGINT;
	BEGIN
		sel := c.stack[c.tos]; DEC(c.tos);
		IF sel = 1 THEN c.inhibitFit := FALSE
		ELSIF sel = 2 THEN c.ignorePrep := FALSE
		END;
		val := c.stack[c.tos]; DEC(c.tos);
		IF val # 0 THEN val := sel END;
		IF val = 1 THEN c.inhibitFit := TRUE
		ELSIF val = 2 THEN c.ignorePrep := TRUE
		END;
		INC(c.pc)
	END INSTCTRL;
	
	(* scan conversion control *)
	PROCEDURE SCANCTRL (VAR c: Context);
		VAR n, thold: LONGINT;
	BEGIN
		n := c.stack[c.tos] MOD 10000H; DEC(c.tos);
		thold := n MOD 256;
		IF thold = 0FFH THEN
			c.fixDropouts := TRUE
		ELSIF thold = 0 THEN
			c.fixDropouts := FALSE
		ELSE
			(* should there be a default value in case no condition holds? FreeType doesn't have one *)
			thold := 40H * thold;
			IF ODD(n DIV 100H) & (PPEm(c) <= thold) THEN c.fixDropouts := TRUE END;
			IF ODD(n DIV 200H) & c.rotated THEN c.fixDropouts := TRUE END;
			IF ODD(n DIV 400H) & c.stretched THEN c.fixDropouts := TRUE END;
			IF ODD(n DIV 800H) & (PPEm(c) > thold) THEN c.fixDropouts := FALSE END;
			IF ODD(n DIV 1000H) & ~c.rotated THEN c.fixDropouts := FALSE END;
			IF ODD(n DIV 2000H) & ~c.stretched THEN c.fixDropouts := FALSE END
		END;
		INC(c.pc)
	END SCANCTRL;
	
	(* scan type *)
	PROCEDURE SCANTYPE (VAR c: Context);
		VAR st: INTEGER;
	BEGIN
		st := SHORT(c.stack[c.tos]); DEC(c.tos);
		IF st IN {3, 6, 7} THEN st := 2 END;
		IF (0 <= st) & (st <= 5) THEN
			c.scanType := st
		END;
		INC(c.pc)
	END SCANTYPE;
	
	(* set control value table cut in *)
	PROCEDURE SCVTCI (VAR c: Context);
	BEGIN
		c.cvtCutIn := c.stack[c.tos]; DEC(c.tos); INC(c.pc)
	END SCVTCI;
	
	(* set single width cut in *)
	PROCEDURE SSWCI (VAR c: Context);
	BEGIN
		c.swCutIn := c.stack[c.tos]; DEC(c.tos); INC(c.pc)
	END SSWCI;
	
	(* set single width *)
	PROCEDURE SSW (VAR c: Context);
	BEGIN
		(* FreeType says that the Windows engine seems to interpret this as a Fixed value (not FUnits as in Spec) *)
		c.swVal := ASH(c.stack[c.tos], -10); DEC(c.tos); INC(c.pc)
	END SSW;
	
	(* set the auto flip flag *)
	PROCEDURE FLIPON (VAR c: Context);
	BEGIN
		c.autoFlip := TRUE; INC(c.pc)
	END FLIPON;
	
	(* clear the auto flip flag *)
	PROCEDURE FLIPOFF (VAR c: Context);
	BEGIN
		c.autoFlip := FALSE; INC(c.pc)
	END FLIPOFF;
	
	(* set angle weight *)
	PROCEDURE SANGW (VAR c: Context);
	BEGIN
		DEC(c.tos); INC(c.pc)	(* corresponding instruction AA is obsolete *)
	END SANGW;
	
	(* set delta base *)
	PROCEDURE SDB (VAR c: Context);
	BEGIN
		c.deltaBase := SHORT(c.stack[c.tos]); DEC(c.tos); INC(c.pc)
	END SDB;
	
	(* set delta shift *)
	PROCEDURE SDS (VAR c: Context);
	BEGIN
		c.deltaShift := SHORT(c.stack[c.tos]); DEC(c.tos); INC(c.pc)
	END SDS;
	
	
	(*--- Reading and Writing Data ---*)
	
	(* get coordinate projected onto the projection vector *)
	PROCEDURE GC (VAR c: Context);
		VAR p: LONGINT; dist: F26D6;
	BEGIN
		p := c.stack[c.tos];
		IF ODD(ORD(c.code[c.pc])) THEN	(* use original coordinates *)
			(* both TTI and FreeType use the dual projection vector with original coordinates *)
			dist := Project(c.zp2.pt[p].org, c.proj2)
		ELSE	(* use current coordinates *)
			dist := Project(c.zp2.pt[p].cur, c.proj)
		END;
		c.stack[c.tos] := dist;
		INC(c.pc)
	END GC;
	
	(* set coordinate from stack using projection and freedom vector *)
	PROCEDURE SCFS (VAR c: Context);
		VAR dist, d: F26D6; p: LONGINT;
	BEGIN
		dist := c.stack[c.tos]; DEC(c.tos);
		p := c.stack[c.tos]; DEC(c.tos);
		d := Project(c.zp2.pt[p].cur, c.proj);
		Move(c.zp2.pt[p], c.free, c.proj, dist - d);
		INC(c.pc)
	END SCFS;
	
	(* measure distance *)
	PROCEDURE MD (VAR c: Context);
		VAR p1, p2: LONGINT; d1, d2: F26D6;
	BEGIN
		(*
			- original implementation used zone 0 for p1 and zone 1 for p2
			- both TTI and FreeType swap opcode semantics (probably bug in spec since odd opcode comes first)
			- spec doesn't mention that dual projection vector has to be used with original coordinates
		*)
		p1 := c.stack[c.tos]; DEC(c.tos);
		p2 := c.stack[c.tos];
		IF ODD(ORD(c.code[c.pc])) THEN	(* use current coordinates *)
			d1 := Project(c.zp1.pt[p1].cur, c.proj);
			d2 := Project(c.zp0.pt[p2].cur, c.proj)
		ELSE	(* use original coordinates *)
			d1 := Project(c.zp1.pt[p1].org, c.proj2);
			d2 := Project(c.zp0.pt[p2].org, c.proj2)
		END;
		c.stack[c.tos] := d2 - d1;
		INC(c.pc)
	END MD;
	
	(* measure pixels per em *)
	PROCEDURE MPPEM (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := ASH(PPEm(c) + 20H, -6); INC(c.pc)
	END MPPEM;
	
	(* measure point size *)
	PROCEDURE MPS (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := ASH(c.ptsize + 20H, -6); INC(c.pc)
	END MPS;
	
	
	(*--- Managing Outlines ---*)
	
	(* flip point *)
	PROCEDURE FLIPPT (VAR c: Context);
		VAR p: LONGINT; pt: Points;
	BEGIN
		(* both TTI and FreeType don't use zp0; instead they work in zone 1 directly *)
		pt := c.zone[1].pt;
		WHILE c.loop > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			pt[p].onCurve := ~pt[p].onCurve;
			DEC(c.loop)
		END;
		c.loop := 1;
		INC(c.pc)
	END FLIPPT;
	
	(* flip range on/off *)
	PROCEDURE FLIPRG (VAR c: Context);
		VAR on: BOOLEAN; hi, lo: LONGINT; pt: Points;
	BEGIN
		on := ODD(ORD(c.code[c.pc]));
		hi := c.stack[c.tos]; DEC(c.tos);
		lo := c.stack[c.tos]; DEC(c.tos);
		pt := c.zone[1].pt;
		WHILE lo <= hi DO
			pt[lo].onCurve := on;
			INC(lo)
		END;
		INC(c.pc)
	END FLIPRG;
	
	(* shift point by the last point *)
	PROCEDURE SHP (VAR c: Context);
		VAR zone: Zone; p: LONGINT; dx, dy: F26D6; pt: Points;
	BEGIN
		GetRefDist(c, ODD(ORD(c.code[c.pc])), zone, p, dx, dy);
		pt := c.zp2.pt;
		WHILE c.loop > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			IF c.free.x # 0 THEN
				INC(pt[p].cur[X], dx); pt[p].touched[X] := TRUE
			END;
			IF c.free.y # 0 THEN
				INC(pt[p].cur[Y], dy); pt[p].touched[Y] := TRUE
			END;
			DEC(c.loop)
		END;
		c.loop := 1;
		INC(c.pc)
	END SHP;
	
	(* shift contour by the last point *)
	PROCEDURE SHC (VAR c: Context);
		VAR zone: Zone; ref, cont, cur, last: LONGINT; dx, dy: F26D6; pt: Points;
	BEGIN
		(*
			- TTI uses original coordinates (which is probably wrong)
			- FreeType says that points aren't touched (so I don't)
		*)
		GetRefDist(c, ODD(ORD(c.code[c.pc])), zone, ref, dx, dy);
		pt := c.zp2.pt;
		cont := c.stack[c.tos]; DEC(c.tos);
		cur := c.zp2.first[cont]; last := c.zp2.first[cont+1]-1;
		WHILE cur <= last DO
			IF (zone # c.zp2) OR (cur # ref) THEN
				IF c.free.x # 0 THEN
					INC(pt[cur].cur[X], dx)
				END;
				IF c.free.y # 0 THEN
					INC(pt[cur].cur[Y], dy)
				END
			END;
			INC(cur)
		END;
		INC(c.pc)
	END SHC;
	
	(* shift zone by the last point *)
	PROCEDURE SHZ (VAR c: Context);
		VAR zone, z: Zone; ref, cur, last: LONGINT; dx, dy: F26D6; pt: Points;
	BEGIN
		(*
			- TTI uses original coordinates (which is probably wrong)
			- FreeType says that points aren't touched (so I don't)
			- FreeType ignores the argument on the stack and always uses zp2
		*)
		GetRefDist(c, ODD(ORD(c.code[c.pc])), zone, ref, dx, dy);
		z := c.zone[c.stack[c.tos]]; DEC(c.tos);
		pt := z.pt;
		cur := 0; last := z.first[z.contours]-1;
		WHILE cur <= last DO
			IF (zone # z) OR (cur # ref) THEN
				IF c.free.x # 0 THEN
					INC(pt[cur].cur[X], dx)
				END;
				IF c.free.y # 0 THEN
					INC(pt[cur].cur[Y], dy)
				END
			END;
			INC(cur)
		END;
		INC(c.pc)
	END SHZ;
	
	(* shift point by a pixel amount *)
	PROCEDURE SHPIX (VAR c: Context);
		VAR dist, dx, dy: F26D6; pt: Points; p: LONGINT;
	BEGIN
		dist := c.stack[c.tos]; DEC(c.tos);
		dx := MulShift(dist, c.free.x, -14);
		dy := MulShift(dist, c.free.y, -14);
		pt := c.zp2.pt;
		WHILE c.loop > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			IF c.free.x # 0 THEN
				INC(pt[p].cur[X], dx); pt[p].touched[X] := TRUE
			END;
			IF c.free.y # 0 THEN
				INC(pt[p].cur[Y], dy); pt[p].touched[Y] := TRUE
			END;
			DEC(c.loop)
		END;
		c.loop := 1;
		INC(c.pc)
	END SHPIX;
	
	(* move stack indirect relative point *)
	PROCEDURE MSIRP (VAR c: Context);
		VAR dist, d: F26D6; p: LONGINT; org: Coord; pt: Points;
	BEGIN
		dist := c.stack[c.tos]; DEC(c.tos);
		p := c.stack[c.tos]; DEC(c.tos);
		
		(* undocumented behaviour, suggested by FreeType *)
		IF c.gep0 = 0 THEN
			org := c.zp0.pt[c.rp0].org;
			pt := c.zp1.pt; pt[p].org := org; pt[p].cur := org
		END;
		
		d := Project(c.zp1.pt[p].cur, c.proj) - Project(c.zp0.pt[c.rp0].cur, c.proj);
		Move(c.zp1.pt[p], c.free, c.proj, dist - d);
		c.rp1 := c.rp0; c.rp2 := SHORT(p);	(* TTI didn't implement this *)
		IF ODD(ORD(c.code[c.pc])) THEN
			c.rp0 := SHORT(p)
		END;
		INC(c.pc)
	END MSIRP;
	
	(* move direct absolute point *)
	PROCEDURE MDAP (VAR c: Context);
		VAR p: LONGINT; d, dist: F26D6;
	BEGIN
		p := c.stack[c.tos]; DEC(c.tos);
		IF ODD(ORD(c.code[c.pc])) THEN
			d := Project(c.zp0.pt[p].cur, c.proj);
			dist := Round(d, c.period, c.phase, c.threshold) - d
		ELSE
			dist := 0
		END;
		Move(c.zp0.pt[p], c.free, c.proj, dist);
		c.rp0 := SHORT(p); c.rp1 := SHORT(p);
		INC(c.pc)
	END MDAP;
	
	(* move indirect absolute point *)
	PROCEDURE MIAP (VAR c: Context);
		VAR cvt, p: LONGINT; dist, d: F26D6; pt: Points; xy: Coord;
	BEGIN
		cvt := c.stack[c.tos]; DEC(c.tos);
		p := c.stack[c.tos]; DEC(c.tos);
		dist := CVTValue(cvt, c);
		pt := c.zp0.pt;
		IF c.gep0 = 0 THEN	(* twilight zone *)
			(* why does FreeType use the freedom vector for this? The spec explicitly mentions the projection vector *)
			xy[X] := MulShift(dist, c.proj.x, -14); xy[Y] := MulShift(dist, c.proj.y, -14);
			pt[p].org := xy; pt[p].cur := xy
		END;
		d := Project(pt[p].cur, c.proj);
		IF ODD(ORD(c.code[c.pc])) THEN	(* round and apply cvt cutin *)
			IF c.autoFlip & (dist * d < 0) THEN dist := -dist END;	(* got this from TTI; FreeType does nothing similar *)
			IF ABS(dist - d) > c.cvtCutIn THEN dist := d END;
			dist := Round(dist, c.period, c.phase, c.threshold)
		END;
		Move(pt[p], c.free, c.proj, dist - d);
		c.rp0 := SHORT(p); c.rp1 := SHORT(p);
		INC(c.pc)
	END MIAP;
	
	(* move direct relative point *)
	PROCEDURE MDRP (VAR c: Context);
		VAR p: LONGINT; d, dist: F26D6;
	BEGIN
		p := c.stack[c.tos]; DEC(c.tos);
		d := Project(c.zp1.pt[p].org, c.proj2) - Project(c.zp0.pt[c.rp0].org, c.proj2);
		(* why does FreeType use the absolute value of 'd' for the single width cutin test? *)
		IF (d >= 0) & (ABS(d - c.swVal) < c.swCutIn) THEN d := c.swVal
		ELSIF (d < 0) & (ABS(-d - c.swVal) < c.swCutIn) THEN d := -c.swVal
		END;
		IF ODD(ORD(c.code[c.pc]) DIV 4) THEN	(* round distance *)
			dist := Round(d, c.period, c.phase, c.threshold)
		ELSE
			dist := d
		END;
		IF ODD(ORD(c.code[c.pc]) DIV 8) THEN	(* keep distance greater than minimum distance *)
			IF (d >= 0) & (dist < c.minDist) THEN dist := c.minDist
			ELSIF (d < 0) & (dist > -c.minDist) THEN dist := -c.minDist
			END
		END;
		d := Project(c.zp1.pt[p].cur, c.proj) - Project(c.zp0.pt[c.rp0].cur, c.proj);
		Move(c.zp1.pt[p], c.free, c.proj, dist - d);
		c.rp1 := c.rp0; c.rp2 := SHORT(p);
		IF ODD(ORD(c.code[c.pc]) DIV 16) THEN
			c.rp0 := SHORT(p)
		END;
		INC(c.pc)
	END MDRP;
	
	(* move indirect relative point *)
	PROCEDURE MIRP (VAR c: Context);
		VAR cvt, p: LONGINT; dcvt, od, cd, dist: F26D6; pt: Points; xy: Coord;
	BEGIN
		cvt := c.stack[c.tos]; DEC(c.tos);
		p := c.stack[c.tos]; DEC(c.tos);
		dcvt := CVTValue(cvt, c);
		pt := c.zp1.pt;
		IF c.gep1 = 0 THEN	(* according to FreeType, MIRP can be used to create twilight points *)
			xy[X] := c.zp0.pt[c.rp0].org[X] + MulShift(dcvt, c.free.x, -14);
			xy[Y] := c.zp0.pt[c.rp0].org[Y] + MulShift(dcvt, c.free.y, -14);
			pt[p].org := xy; pt[p].cur := xy
		END;
		od := Project(pt[p].org, c.proj2) - Project(c.zp0.pt[c.rp0].org, c.proj2);
		cd := Project(pt[p].cur, c.proj) - Project(c.zp0.pt[c.rp0].cur, c.proj);
		IF ODD(ORD(c.code[c.pc]) DIV 4) THEN	(* perform cvtCutIn test and round *)
			IF c.autoFlip & (od * dcvt < 0) THEN
				dcvt := -dcvt
			END;
			IF c.zp0 = c.zp1 THEN	(* according to FreeType, both points have to be in the same zone *)
				IF ABS(od - dcvt) >= c.cvtCutIn THEN
					dcvt := od
				END;
				(* for the single width cut in test, FreeType uses again the value of dcvt directly !? *)
				IF (dcvt >= 0) & (ABS(dcvt - c.swVal) < c.swCutIn) THEN dcvt := c.swVal
				ELSIF (dcvt < 0) & (ABS(-dcvt - c.swVal) < c.swCutIn) THEN dcvt := -c.swVal
				END
			END;
			dist := Round(dcvt, c.period, c.phase, c.threshold)
		ELSE
			dist := dcvt	(* TTI used the original distance, which is almost certainly wrong *)
		END;
		IF ODD(ORD(c.code[c.pc]) DIV 8) THEN	(* perform minimum distance test *)
			IF (od >= 0) & (dist < c.minDist) THEN dist := c.minDist
			ELSIF (od < 0) & (dist > -c.minDist) THEN dist := -c.minDist
			END
		END;
		Move(pt[p], c.free, c.proj, dist - cd);
		c.rp1 := c.rp0; c.rp2 := SHORT(p);
		IF ODD(ORD(c.code[c.pc]) DIV 16) THEN
			c.rp0 := SHORT(p)
		END;
		INC(c.pc)
	END MIRP;
	
	(* align relative point *)
	PROCEDURE ALIGNRP (VAR c: Context);
		VAR p: LONGINT; dist: F26D6;
	BEGIN
		WHILE c.loop > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			dist := Project(c.zp1.pt[p].cur, c.proj) - Project(c.zp0.pt[c.rp0].cur, c.proj);
			Move(c.zp1.pt[p], c.free, c.proj, -dist);
			DEC(c.loop)
		END;
		c.loop := 1;
		INC(c.pc)
	END ALIGNRP;
	
	(* move point to intersection of two lines *)
	PROCEDURE ISECT (VAR c: Context);
		VAR
			b1, b0, a1, a0, p: LONGINT; pt: Points; ax0, ay0, ax1, ay1, bx0, by0, bx1, by1, d, rx, ry: F26D6;
			dxa, dya, dxb, dyb, dx, dy, u, v, det: INT64;
	BEGIN
		b1 := c.stack[c.tos]; DEC(c.tos);
		b0 := c.stack[c.tos]; DEC(c.tos);
		a1 := c.stack[c.tos]; DEC(c.tos);
		a0 := c.stack[c.tos]; DEC(c.tos);
		p := c.stack[c.tos]; DEC(c.tos);
		pt := c.zp2.pt;
		pt[p].touched[X] := TRUE; pt[p].touched[Y] := TRUE;
		ax0 := c.zp1.pt[a0].cur[X]; ay0 := c.zp1.pt[a0].cur[Y];
		ax1 := c.zp1.pt[a1].cur[X]; ay1 := c.zp1.pt[a1].cur[Y];
		bx0 := c.zp0.pt[b0].cur[X]; by0 := c.zp0.pt[b0].cur[Y];
		bx1 := c.zp0.pt[b1].cur[X]; by1 := c.zp0.pt[b1].cur[Y];
		ToINT64(ax1 - ax0, dxa); ToINT64(ay1 - ay0, dya);
		ToINT64(bx1 - bx0, dxb); ToINT64(by1 - by0, dyb);
		MulINT64(dya, dxb, u); MulINT64(dyb, dxa, v);
		SubINT64(u, v, det);
		FromINT64(det, d);
		IF ABS(d) >= 80H THEN
			ToINT64(bx0 - ax0, dx); ToINT64(by0 - ay0, dy);
			SubINT64(Zero64, dyb, dyb);
			MulINT64(dx, dyb, u); MulINT64(dy, dxb, v); AddINT64(u, v, v);
			MulINT64(v, dxa, u); DivINT64(u, det, u); FromINT64(u, rx);
			MulINT64(v, dya, u); DivINT64(u, det, u); FromINT64(u, ry);
			pt[p].cur[X] := ax0 + rx;
			pt[p].cur[Y] := ay0 + ry
		ELSE	(* lines are (almost) parallel *)
			pt[p].cur[X] := (ax0 + ax1 + bx0 + bx1) DIV 4;
			pt[p].cur[Y] := (ay0 + ay1 + by0 + by1) DIV 4
		END;
		INC(c.pc)
	END ISECT;
	
	(* align points *)
	PROCEDURE ALIGNPTS (VAR c: Context);
		VAR p1, p2: LONGINT; dist: F26D6;
	BEGIN
		p1 := c.stack[c.tos]; DEC(c.tos);
		p2 := c.stack[c.tos]; DEC(c.tos);
		(* both TTI and FreeType swap use p1 with zp0 and p2 with zp1 (contrary to spec) *)
		dist := (Project(c.zp0.pt[p1].cur, c.proj) - Project(c.zp1.pt[p2].cur, c.proj)) DIV 2;
		Move(c.zp0.pt[p1], c.free, c.proj, -dist);
		Move(c.zp1.pt[p2], c.free, c.proj, dist);
		INC(c.pc)
	END ALIGNPTS;
	
	(* interpolate point by the last relative stretch *)
	PROCEDURE IP (VAR c: Context);
		VAR od1, od2, cd1, cd2, od, cd, dist: F26D6; pt: Points; p: LONGINT;
	BEGIN
		od1 := Project(c.zp0.pt[c.rp1].org, c.proj2);
		od2 := Project(c.zp1.pt[c.rp2].org, c.proj2);
		cd1 := Project(c.zp0.pt[c.rp1].cur, c.proj);
		cd2 := Project(c.zp1.pt[c.rp2].cur, c.proj);
		pt := c.zp2.pt;
		WHILE c.loop > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			od := Project(pt[p].org, c.proj2);
			cd := Project(pt[p].cur, c.proj);
			IF (od1 <= od2) & (od <= od1) OR (od1 > od2) & (od >= od1) THEN
				dist := cd1 - od1 + od - cd
			ELSIF (od1 <= od2) & (od2 <= od) OR (od1 > od2) & (od2 >= od) THEN
				dist := cd2 - od2 + od - cd
			ELSE
				dist := MulDiv(cd2 - cd1, od - od1, od2 - od1) + cd1 - cd
			END;
			Move(pt[p], c.free, c.proj, dist);
			DEC(c.loop)
		END;
		c.loop := 1;
		INC(c.pc)
	END IP;
	
	(* untouch point *)
	PROCEDURE UTP (VAR c: Context);
		VAR p: LONGINT;
	BEGIN
		p := c.stack[c.tos]; DEC(c.tos);
		IF c.free.x # 0 THEN
			c.zp2.pt[p].touched[X] := FALSE
		END;
		IF c.free.y # 0 THEN
			c.zp2.pt[p].touched[Y] := FALSE
		END;
		INC(c.pc)
	END UTP;
	
	(* interpolate untouched points through the outline *)
	PROCEDURE IUP (VAR c: Context);
		VAR
			z: Zone; pt: Points; n, xy, beg, nil, first, end, cur: LONGINT; dxy: F26D6;
		
		PROCEDURE interpol (p0, p1, rp0, rp1: LONGINT);
			VAR oxy0, cxy0, dxy0, oxy1, cxy1, dxy1, cxy: F26D6;
		BEGIN
			IF p0 <= p1 THEN
				oxy0 := pt[rp0].org[xy]; cxy0 := pt[rp0].cur[xy]; dxy0 := cxy0 - oxy0;
				oxy1 := pt[rp1].org[xy]; cxy1 := pt[rp1].cur[xy]; dxy1 := cxy1 - oxy1;
				IF oxy0 < oxy1 THEN
					WHILE p0 <= p1 DO
						cxy := pt[p0].org[xy];
						IF cxy <= oxy0 THEN INC(cxy, dxy0)
						ELSIF oxy1 <= cxy THEN INC(cxy, dxy1)
						ELSE cxy := cxy0 + MulDiv(cxy - oxy0, cxy1 - cxy0, oxy1 - oxy0)
						END;
						pt[p0].cur[xy] := cxy;
						INC(p0)
					END
				ELSIF oxy1 < oxy0 THEN
					WHILE p0 <= p1 DO
						cxy := pt[p0].org[xy];
						IF cxy <= oxy1 THEN INC(cxy, dxy1)
						ELSIF oxy0 <= cxy THEN INC(cxy, dxy0)
						ELSE cxy := cxy0 + MulDiv(cxy - oxy0, cxy1 - cxy0, oxy1 - oxy0)
						END;
						pt[p0].cur[xy] := cxy;
						INC(p0)
					END
				ELSE
					WHILE p0 <= p1 DO
						cxy := pt[p0].org[xy];
						IF cxy <= oxy0 THEN INC(cxy, dxy0)
						ELSE INC(cxy, dxy1)
						END;
						pt[p0].cur[xy] := cxy;
						INC(p0)
					END
				END
			END
		END interpol;
		
	BEGIN
		z := c.zp2; pt := z.pt; n := 0;
		xy := ORD(c.code[c.pc]) MOD 2;
		WHILE n < z.contours DO
			beg := z.first[n]; nil := z.first[n+1];
			WHILE (beg < nil) & ~pt[beg].touched[xy] DO INC(beg) END;
			IF beg < nil THEN
				first := beg;
				REPEAT
					end := beg+1;
					WHILE (end < nil) & ~pt[end].touched[xy] DO INC(end) END;
					IF end < nil THEN
						interpol(beg+1, end-1, beg, end);
						beg := end+1;
						WHILE (beg < nil) & pt[beg].touched[xy] DO INC(beg) END;
						DEC(beg)
					END
				UNTIL end = nil;
				IF beg = first THEN	(* only one touched point in whole contour => FreeType applies shift here *)
					dxy := pt[beg].cur[xy] - pt[beg].org[xy];
					cur := z.first[n];
					WHILE cur < beg DO INC(pt[cur].cur[xy], dxy); INC(cur) END;
					cur := beg+1;
					WHILE cur < nil DO INC(pt[cur].cur[xy], dxy); INC(cur) END
				ELSE
					interpol(beg+1, nil-1, beg, first);
					IF first > z.first[n] THEN interpol(z.first[n], first-1, beg, first) END
				END
			END;
			INC(n)
		END;
		INC(c.pc)
	END IUP;
	
	
	(*--- Managing Exceptions ---*)
	
	(* delta exception Pn *)
	PROCEDURE DELTAP (VAR c: Context);
		VAR base, ppm, n, p, arg: LONGINT;
	BEGIN
		base := c.deltaBase;
		IF c.code[c.pc] = 71X THEN INC(base, 16)	(* DELTAP2 *)
		ELSIF c.code[c.pc] = 72X THEN INC(base, 32)	(* DELTAP3 *)
		END;
		ppm := ASH(PPEm(c) + 20H, -6);
		n := c.stack[c.tos]; DEC(c.tos);
		WHILE n > 0 DO
			p := c.stack[c.tos]; DEC(c.tos);
			arg := c.stack[c.tos]; DEC(c.tos);
			IF (base + arg DIV 10H MOD 10H = ppm) & (0 <= p) & (p < LEN(c.zp0.pt^)) THEN
				arg := arg MOD 10H - 8;
				IF arg >= 0 THEN INC(arg) END;
				arg := 40H * arg DIV ASH(1, c.deltaShift);
				Move(c.zp0.pt[p], c.free, c.proj, arg)
			END;
			DEC(n)
		END;
		INC(c.pc)
	END DELTAP;
	
	(* delta exception Cn *)
	PROCEDURE DELTAC (VAR c: Context);
		VAR base, ppm, n, cvt, arg: LONGINT;
	BEGIN
		base := c.deltaBase;
		IF c.code[c.pc] = 74X THEN INC(base, 16)	(* DELTAC2 *)
		ELSIF c.code[c.pc] = 75X THEN INC(base, 32)	(* DELTAC3 *)
		END;
		ppm := ASH(PPEm(c) + 20H, -6);
		n := c.stack[c.tos]; DEC(c.tos);
		WHILE n > 0 DO
			cvt := c.stack[c.tos]; DEC(c.tos);
			arg := c.stack[c.tos]; DEC(c.tos);
			IF base + arg DIV 10H MOD 10H = ppm THEN
				arg := arg MOD 10H - 8;
				IF arg >= 0 THEN INC(arg) END;
				arg := 40H * arg DIV ASH(1, c.deltaShift);
				INC(c.cvt[cvt], ShiftDiv(arg, 16, Ratio(c)))
			END;
			DEC(n)
		END;
		INC(c.pc)
	END DELTAC;
	
	
	(*--- Managing the Stack ---*)
	
	(* duplicate top stack element *)
	PROCEDURE DUP (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := c.stack[c.tos-1]; INC(c.pc)
	END DUP;
	
	(* pop top stack element *)
	PROCEDURE POP (VAR c: Context);
	BEGIN
		DEC(c.tos); INC(c.pc)
	END POP;
	
	(* clear the entire stack *)
	PROCEDURE CLEAR (VAR c: Context);
	BEGIN
		c.tos := -1; INC(c.pc)
	END CLEAR;
	
	(* swap the top two elements on the stack *)
	PROCEDURE SWAP (VAR c: Context);
		VAR tmp: LONGINT;
	BEGIN
		tmp := c.stack[c.tos]; c.stack[c.tos] := c.stack[c.tos-1]; c.stack[c.tos-1] := tmp; INC(c.pc)
	END SWAP;
	
	(* return depth of the stack *)
	PROCEDURE DEPTH (VAR c: Context);
	BEGIN
		INC(c.tos); c.stack[c.tos] := c.tos; INC(c.pc)
	END DEPTH;
	
	(* copy the indexed element to the top of the stack *)
	PROCEDURE CINDEX (VAR c: Context);
		VAR idx: LONGINT;
	BEGIN
		idx := c.stack[c.tos]; c.stack[c.tos] := c.stack[c.tos - idx]; INC(c.pc)
	END CINDEX;
	
	(* move the indexed element to the top of the stack *)
	PROCEDURE MINDEX (VAR c: Context);
		VAR idx, pos, elem: LONGINT;
	BEGIN
		idx := c.stack[c.tos];
		pos := c.tos - idx; elem := c.stack[pos];
		WHILE idx > 1 DO
			c.stack[pos] := c.stack[pos+1]; INC(pos); DEC(idx)
		END;
		c.stack[pos] := elem; DEC(c.tos);
		INC(c.pc)
	END MINDEX;
	
	(* roll the top three stack elements *)
	PROCEDURE ROLL (VAR c: Context);
		VAR elem: LONGINT;
	BEGIN
		elem := c.stack[c.tos-2]; c.stack[c.tos-2] := c.stack[c.tos-1]; c.stack[c.tos-1] := c.stack[c.tos]; c.stack[c.tos] := elem;
		INC(c.pc)
	END ROLL;
	
	
	(*--- Managing the Flow of Control ---*)
	
	PROCEDURE Skip (VAR c: Context);
	BEGIN
		CASE c.code[c.pc] OF
		| 40X: INC(c.pc, LONG(2 + ORD(c.code[c.pc+1])))	(* NPUSHB *)
		| 41X: INC(c.pc, LONG(2 + 2*ORD(c.code[c.pc+1])))	(* NPUSHW *)
		| 0B0X..0B7X: INC(c.pc, LONG(2 + ORD(c.code[c.pc]) MOD 8))	(* PUSHBx *)
		| 0B8X..0BFX: INC(c.pc, LONG(3 + 2*(ORD(c.code[c.pc]) MOD 8)))	(* PUSHWx *)
		| 58X: INC(c.pc); REPEAT Skip(c) UNTIL c.code[c.pc] = 59X; INC(c.pc)	(* IF..EIF *)
		ELSE INC(c.pc)
		END
	END Skip;
	
	(* if test *)
	PROCEDURE iF (VAR c: Context);
	BEGIN
		IF c.stack[c.tos] = 0 THEN
			INC(c.pc);
			WHILE (c.code[c.pc] # 1BX) & (c.code[c.pc] # 59X) DO	(* terminated by ELSE or EIF *)
				Skip(c)
			END
		END;
		DEC(c.tos); INC(c.pc)
	END iF;
	
	(* else part of if-clause *)
	PROCEDURE eLSE (VAR c: Context);
	BEGIN
		(* only executed if previous IF-test was successful => skip until EIF *)
		REPEAT Skip(c) UNTIL c.code[c.pc] = 59X;
		INC(c.pc)
	END eLSE;
	
	(* end mark of if-clause *)
	PROCEDURE EIF (VAR c: Context);
	BEGIN
		INC(c.pc)
	END EIF;
	
	(* jump relative on true *)
	PROCEDURE JROT (VAR c: Context);
		VAR true: BOOLEAN;
	BEGIN
		true := c.stack[c.tos] # 0; DEC(c.tos);
		IF true THEN
			INC(c.pc, c.stack[c.tos])
		ELSE
			INC(c.pc)
		END;
		DEC(c.tos)
	END JROT;
	
	(* jump relative *)
	PROCEDURE JUMPR (VAR c: Context);
	BEGIN
		INC(c.pc, c.stack[c.tos]); DEC(c.tos)
	END JUMPR;
	
	(* jump relative on false *)
	PROCEDURE JROF (VAR c: Context);
		VAR false: BOOLEAN;
	BEGIN
		false := c.stack[c.tos] = 0; DEC(c.tos);
		IF false THEN
			INC(c.pc, c.stack[c.tos])
		ELSE
			INC(c.pc)
		END;
		DEC(c.tos)
	END JROF;
	
	
	(*--- Logical Functions ---*)
	
	(* comparison *)
	PROCEDURE COMPARE (VAR c: Context);
		VAR b, a: LONGINT; res: BOOLEAN;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		CASE c.code[c.pc] OF
		| 50X: res := a < b
		| 51X: res := a <= b
		| 52X: res := a > b
		| 53X: res := a >= b
		| 54X: res := a = b
		| 55X: res := a # b
		END;
		IF res THEN c.stack[c.tos] := 1
		ELSE c.stack[c.tos] := 0
		END;
		INC(c.pc)
	END COMPARE;
	
	(* odd *)
	PROCEDURE oDD (VAR c: Context);
		VAR r: LONGINT;
	BEGIN
		r := Round(c.stack[c.tos], c.period, c.phase, c.threshold) DIV 40H;
		IF ODD(r) THEN c.stack[c.tos] := 1 ELSE c.stack[c.tos] := 0 END;
		INC(c.pc)
	END oDD;
	
	(* even *)
	PROCEDURE EVEN (VAR c: Context);
		VAR r: LONGINT;
	BEGIN
		r := Round(c.stack[c.tos], c.period, c.phase, c.threshold) DIV 40H;
		IF ODD(r) THEN c.stack[c.tos] := 0 ELSE c.stack[c.tos] := 1 END;
		INC(c.pc)
	END EVEN;
	
	(* logical and *)
	PROCEDURE AND (VAR c: Context);
		VAR b, a: LONGINT;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		IF a * b # 0 THEN c.stack[c.tos] := 1 ELSE c.stack[c.tos] := 0 END;
		INC(c.pc)
	END AND;
	
	(* logical or *)
	PROCEDURE oR (VAR c: Context);
		VAR b, a: LONGINT;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		IF (a # 0) OR (b # 0) THEN c.stack[c.tos] := 1 ELSE c.stack[c.tos] := 0 END;
		INC(c.pc)
	END oR;
	
	(* logical not *)
	PROCEDURE NOT (VAR c: Context);
	BEGIN
		IF c.stack[c.tos] = 0 THEN c.stack[c.tos] := 1 ELSE c.stack[c.tos] := 0 END;
		INC(c.pc)
	END NOT;
	
	
	(*--- Arithmetic and Math Instructions ---*)
	
	PROCEDURE ADD (VAR c: Context);
		VAR b: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); INC(c.stack[c.tos], b); INC(c.pc)
	END ADD;
	
	PROCEDURE SUB (VAR c: Context);
		VAR b: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); DEC(c.stack[c.tos], b); INC(c.pc)
	END SUB;
	
	PROCEDURE dIV (VAR c: Context);
		VAR b, a: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		IF b > 0 THEN c.stack[c.tos] := ShiftDiv(a, 6, b)
		ELSIF b < 0 THEN c.stack[c.tos] := ShiftDiv(-a, 6, -b)
		ELSE c.stack[c.tos] := 0	(* division by zero *)
		END;
		INC(c.pc)
	END dIV;
	
	PROCEDURE MUL (VAR c: Context);
		VAR b, a: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		c.stack[c.tos] := MulShift(a, b, -6);
		INC(c.pc)
	END MUL;
	
	PROCEDURE aBS (VAR c: Context);
	BEGIN
		c.stack[c.tos] := ABS(c.stack[c.tos]); INC(c.pc)
	END aBS;
	
	PROCEDURE NEG (VAR c: Context);
	BEGIN
		c.stack[c.tos] := -c.stack[c.tos]; INC(c.pc)
	END NEG;
	
	PROCEDURE FLOOR (VAR c: Context);
		VAR x: F26D6;
	BEGIN
		x := c.stack[c.tos];
		c.stack[c.tos] := x - x MOD 40H;
		INC(c.pc)
	END FLOOR;
	
	PROCEDURE CEILING (VAR c: Context);
		VAR x: F26D6;
	BEGIN
		x := c.stack[c.tos] + 3FH;
		c.stack[c.tos] := x - x MOD 40H;
		INC(c.pc)
	END CEILING;
	
	PROCEDURE mAX (VAR c: Context);
		VAR b, a: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		IF a < b THEN c.stack[c.tos] := b END;
		INC(c.pc)
	END mAX;
	
	PROCEDURE mIN (VAR c: Context);
		VAR b, a: F26D6;
	BEGIN
		b := c.stack[c.tos]; DEC(c.tos); a := c.stack[c.tos];
		IF a > b THEN c.stack[c.tos] := b END;
		INC(c.pc)
	END mIN;
	
	
	(*--- Compensating for the Engine Characteristics ---*)
	
	(* round value *)
	PROCEDURE ROUND (VAR c: Context);
	BEGIN
		(* no engine characteristics are implemented *)
		c.stack[c.tos] := Round(c.stack[c.tos], c.period, c.phase, c.threshold);
		INC(c.pc)
	END ROUND;
	
	(* compensate without rounding value *)
	PROCEDURE NROUND (VAR c: Context);
	BEGIN
		INC(c.pc)	(* nothing happens *)
	END NROUND;
	
	
	(*--- Defining and Using Functions and Instructions ---*)
	
	(* function definition *)
	PROCEDURE FDEF (VAR c: Context);
		VAR n: LONGINT;
	BEGIN
		n := c.stack[c.tos]; DEC(c.tos);
		c.func[n].code := c.code; c.func[n].len := c.codeLen; c.func[n].pc := c.pc;
		REPEAT Skip(c) UNTIL c.code[c.pc] = 2DX;	(* skip until ENDF *)
		INC(c.pc)
	END FDEF;
	
	(* end function definition *)
	PROCEDURE ENDF (VAR c: Context);
	BEGIN
		DEC(c.callStack[c.ctos].count);
		IF c.callStack[c.ctos].count = 0 THEN
			c.code := c.callStack[c.ctos].ret.code; c.codeLen := c.callStack[c.ctos].ret.len; c.pc := c.callStack[c.ctos].ret.pc;
			DEC(c.ctos)
		ELSE
			c.pc := c.callStack[c.ctos].start	(* code remains the same *)
		END;
		INC(c.pc)	(* make PC point to instruction after FDEF/IDEF/(LOOP)CALL *)
	END ENDF;
	
	(* call function *)
	PROCEDURE CALL (VAR c: Context);
		VAR n: LONGINT;
	BEGIN
		n := c.stack[c.tos]; DEC(c.tos);
		INC(c.ctos);
		c.callStack[c.ctos].ret.code := c.code; c.callStack[c.ctos].ret.len := c.codeLen;
		c.callStack[c.ctos].ret.pc := c.pc; c.callStack[c.ctos].count := 1;
		c.code := c.func[n].code; c.codeLen := c.func[n].len; c.pc := c.func[n].pc+1	(* make PC point to first instruction after FDEF *)
	END CALL;
	
	(* loop and call function *)
	PROCEDURE LOOPCALL (VAR c: Context);
		VAR n, count: LONGINT;
	BEGIN
		n := c.stack[c.tos]; DEC(c.tos);
		count := c.stack[c.tos]; DEC(c.tos);
		INC(c.ctos);
		c.callStack[c.ctos].ret.code := c.code; c.callStack[c.ctos].ret.len := c.codeLen; c.callStack[c.ctos].ret.pc := c.pc;
		c.callStack[c.ctos].count := SHORT(count); c.callStack[c.ctos].start := c.func[n].pc;
		c.code := c.func[n].code; c.codeLen := c.func[n].len; c.pc := c.func[n].pc+1	(* make PC point to first instruction after FDEF *)
	END LOOPCALL;
	
	(* instruction definition *)
	PROCEDURE IDEF (VAR c: Context);
		VAR op: CHAR; i: LONGINT;
	BEGIN
		op := CHR(c.stack[c.tos]); DEC(c.tos);
		i := 0; WHILE (c.instr[i].beg.code # NIL) & (c.instr[i].opcode # op) DO INC(i) END;
		IF c.instr[i].beg.code = NIL THEN
			c.instr[i].opcode := op; c.instr[i].beg.code := c.code; c.instr[i].beg.len := c.codeLen; c.instr[i].beg.pc := c.pc
		END;
		REPEAT Skip(c) UNTIL c.code[c.pc] = 2DX;	(* skip until ENDF *)
		INC(c.pc)
	END IDEF;
	
	(* user defined instructions *)
	PROCEDURE UNDEF (VAR c: Context);
		VAR i: LONGINT;
	BEGIN
		i := 0; WHILE (c.instr[i].beg.code # NIL) & (c.instr[i].opcode # c.code[c.pc]) DO INC(i) END;
		IF c.instr[i].beg.code # NIL THEN	(* found instruction *)
			INC(c.ctos);
			c.callStack[c.ctos].ret.code := c.code; c.callStack[c.ctos].ret.len := c.codeLen;
			c.callStack[c.ctos].ret.pc := c.pc; c.callStack[c.ctos].count := 1;
			c.code := c.instr[i].beg.code; c.pc := c.instr[i].beg.pc
		END;
		INC(c.pc)
	END UNDEF;
	
	
	(*--- Miscellaneous Instructions ---*)
	
	(* debug call *)
	PROCEDURE DEBUG (VAR c: Context);
	BEGIN
		DEC(c.tos); INC(c.pc);	(* pop the value off the stack *)
		IF Notify # NIL THEN Notify(c, NotifyData) END
	END DEBUG;
	
	(* get information *)
	PROCEDURE GETINFO (VAR c: Context);
		VAR sel, val: LONGINT;
	BEGIN
		sel := c.stack[c.tos]; val := 0;
		IF ODD(sel) THEN END;	(* give back version number 0 *)
		IF ODD(sel DIV 2) & c.rotated THEN INC(val, 100H) END;	(* glyph rotation status *)
		IF ODD(sel DIV 4) & c.stretched THEN INC(val, 200H) END;	(* glyph scale status *)
		c.stack[c.tos] := val;
		INC(c.pc)
	END GETINFO;
	
	
	(*--- Initialization ---*)
	
	PROCEDURE InitBuiltins;
		VAR i: LONGINT;
	BEGIN
		FOR i := 0 TO 0FFH DO Builtin[i] := UNDEF END;
		
		(* pushing data onto the interpreter stack *)
		Builtin[40H] := NPUSHB; Builtin[41H] := NPUSHW;
		FOR i := 0B0H TO 0B7H DO Builtin[i] := PUSHB END;
		FOR i := 0B8H TO 0BFH DO Builtin[i] := PUSHW END;
		
		(* managing the storage area *)
		Builtin[43H] := RS; Builtin[42H] := WS;
		
		(* managing the control value table *)
		Builtin[44H] := WCVT; Builtin[70H] := WCVT; Builtin[45H] := RCVT;
		
		(* managing the graphics state *)
		Builtin[0] := SVTCA; Builtin[1] := SVTCA;
		Builtin[2] := SPVTCA; Builtin[3] := SPVTCA;
		Builtin[4] := SFVTCA; Builtin[5] := SFVTCA;
		Builtin[6] := SPVTL; Builtin[7] := SPVTL;
		Builtin[8] := SFVTL; Builtin[9] := SFVTL;
		Builtin[0EH] := SFVTPV;
		Builtin[86H] := SDPVTL; Builtin[87H] := SDPVTL;
		Builtin[0AH] := SPVFS; Builtin[0BH] := SFVFS;
		Builtin[0CH] := GPV; Builtin[0DH] := GFV;
		
		Builtin[10H] := SRPi; Builtin[11H] := SRPi; Builtin[12H] := SRPi;
		Builtin[13H] := SZPi; Builtin[14H] := SZPi; Builtin[15H] := SZPi; Builtin[16H] := SZPS;
		
		Builtin[19H] := RTHG; Builtin[18H] := RTG; Builtin[3DH] := RTDG; Builtin[7DH] := RDTG; Builtin[7CH] := RUTG;
		Builtin[7AH] := ROFF; Builtin[76H] := SROUND; Builtin[77H] := SROUND;
		
		Builtin[17H] := SLOOP; Builtin[1AH] := SMD; Builtin[8EH] := INSTCTRL;
		Builtin[85H] := SCANCTRL; Builtin[8DH] := SCANTYPE;
		Builtin[1DH] := SCVTCI; Builtin[1EH] := SSWCI; Builtin[1FH] := SSW;
		Builtin[4DH] := FLIPON; Builtin[4EH] := FLIPOFF;
		Builtin[7EH] := SANGW; Builtin[5EH] := SDB; Builtin[5FH] := SDS;
		
		(* reading and writing data *)
		Builtin[46H] := GC; Builtin[47H] := GC; Builtin[48H] := SCFS; Builtin[49H] := MD; Builtin[4AH] := MD;
		Builtin[4BH] := MPPEM; Builtin[4CH] := MPS;
		
		(* managing outlines *)
		Builtin[80H] := FLIPPT; Builtin[81H] := FLIPRG; Builtin[82H] := FLIPRG;
		Builtin[32H] := SHP; Builtin[33H] := SHP; Builtin[34H] := SHC; Builtin[35H] := SHC;
		Builtin[36H] := SHZ; Builtin[37H] := SHZ; Builtin[38H] := SHPIX;
		Builtin[3AH] := MSIRP; Builtin[3BH] := MSIRP; Builtin[2EH] := MDAP; Builtin[2FH] := MDAP;
		Builtin[3EH] := MIAP; Builtin[3FH] := MIAP;
		FOR i := 0C0H TO 0DFH DO Builtin[i] := MDRP END;
		FOR i := 0E0H TO 0FFH DO Builtin[i] := MIRP END;
		Builtin[3CH] := ALIGNRP; Builtin[0FH] := ISECT; Builtin[27H] := ALIGNPTS;
		Builtin[39H] := IP; Builtin[29H] := UTP; Builtin[30H] := IUP; Builtin[31H] := IUP;
		
		(* managing exceptions *)
		Builtin[5DH] := DELTAP; Builtin[71H] := DELTAP; Builtin[72H] := DELTAP;
		Builtin[73H] := DELTAC; Builtin[74H] := DELTAC; Builtin[75H] := DELTAC;
		
		(* managing the stack *)
		Builtin[20H] := DUP; Builtin[21H] := POP; Builtin[22H] := CLEAR; Builtin[23H] := SWAP;
		Builtin[24H] := DEPTH; Builtin[25H] := CINDEX; Builtin[26H] := MINDEX; Builtin[8AH] := ROLL;
		
		(* managing the flow of control *)
		Builtin[58H] := iF; Builtin[1BH] := eLSE; Builtin[59H] := EIF;
		Builtin[78H] := JROT; Builtin[1CH] := JUMPR; Builtin[79H] := JROF;
		
		(* logical functions *)
		Builtin[50H] := COMPARE; Builtin[51H] := COMPARE; Builtin[52H] := COMPARE;
		Builtin[53H] := COMPARE; Builtin[54H] := COMPARE; Builtin[55H] := COMPARE;
		Builtin[56H] := oDD; Builtin[57H] := EVEN;
		Builtin[5AH] := AND; Builtin[5BH] := oR; Builtin[5CH] := NOT;
		
		(* arithmetic and math instructions *)
		Builtin[60H] := ADD; Builtin[61H] := SUB; Builtin[62H] := dIV; Builtin[63H] := MUL;
		Builtin[64H] := aBS; Builtin[65H] := NEG; Builtin[66H] := FLOOR; Builtin[67H] := CEILING;
		Builtin[8BH] := mAX; Builtin[8CH] := mIN;
		
		(* compensating for the engine characteristics *)
		FOR i := 68H TO 6BH DO Builtin[i] := ROUND END;
		FOR i := 6CH TO 6FH DO Builtin[i] := NROUND END;
		
		(* defining and using functions and instructions *)
		Builtin[2CH] := FDEF; Builtin[2DH] := ENDF; Builtin[2BH] := CALL; Builtin[2AH] := LOOPCALL; Builtin[89H] := IDEF;
		
		(* miscellaneous instructions *)
		Builtin[4FH] := DEBUG; Builtin[88H] := GETINFO
	END InitBuiltins;
	
	
	(*--- Exported Interface ---*)
	
	(** allocation procedures for all dynamically sized memory structures **)
	PROCEDURE NewCode* (VAR code: Code; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(code, size) ELSE code := NIL END
	END NewCode;
	
	PROCEDURE NewStack* (VAR stack: Stack; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(stack, size) ELSE stack := NIL END
	END NewStack;
	
	PROCEDURE NewCallStack* (VAR stack: CallStack; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(stack, size) ELSE stack := NIL END
	END NewCallStack;
	
	PROCEDURE NewFunctions* (VAR func: Functions; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(func, size) ELSE func := NIL END
	END NewFunctions;
	
	PROCEDURE NewInstructions* (VAR instr: Instructions; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(instr, size) ELSE instr := NIL END
	END NewInstructions;
	
	PROCEDURE NewStore* (VAR store: Store; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(store, size) ELSE store := NIL END
	END NewStore;
	
	PROCEDURE NewCVT* (VAR cvt: CVT; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(cvt, size) ELSE cvt := NIL END
	END NewCVT;
	
	PROCEDURE NewContours (VAR contours: Contours; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(contours, size) ELSE contours := NIL END
	END NewContours;
	
	PROCEDURE NewPoints (VAR points: Points; size: LONGINT);
	BEGIN
		IF size > 0 THEN NEW(points, size) ELSE points := NIL END
	END NewPoints;
	
	PROCEDURE NewZone* (VAR zone: Zone; contours, points: INTEGER);
	BEGIN
		NEW(zone); zone.contours := contours;
		NEW(zone.first, contours+1);
		IF points > 0 THEN NEW(zone.pt, points) ELSE zone.pt := NIL END;
		zone.first[contours] := points
	END NewZone;
	
	(** set context stacks **)
	PROCEDURE SetStacks* (VAR c: Context; stack: Stack; callStack: CallStack);
	BEGIN
		c.stack := stack; c.callStack := callStack
	END SetStacks;
	
	(** set context structures **)
	PROCEDURE SetStructures* (VAR c: Context; func: Functions; instr: Instructions; store: Store; cvt: CVT);
	BEGIN
		c.func := func; c.instr := instr; c.store := store; c.cvt := cvt
	END SetStructures;
	
	(** set instance specific context parameters **)
	PROCEDURE SetResolution* (VAR c: Context; ptsize, xppm, yppm: F26D6; upm: INTEGER; rotated, stretched: BOOLEAN);
	BEGIN
		c.ptsize := ptsize; c.xppm := xppm; c.yppm := yppm;
		IF xppm >= yppm THEN
			c.ppm := xppm; c.xratio := 10000H; c.yratio := ShiftDiv(yppm, 10H, xppm)
		ELSE
			c.ppm := yppm; c.xratio := ShiftDiv(xppm, 10H, yppm); c.yratio := 10000H
		END;
		c.upm := upm; c.rotated := rotated; c.stretched := stretched
	END SetResolution;
	
	(** initialize graphic state default values **)
	PROCEDURE InitState* (VAR c: Context);
	BEGIN
		c.cvtCutIn := 40H * 17 DIV 16;
		c.swCutIn := 0; c.swVal := 0;
		c.minDist := 40H;
		c.deltaBase := 9; c.deltaShift := 3;
		c.autoFlip := TRUE;
		c.inhibitFit := FALSE; c.ignorePrep := FALSE;
		c.fixDropouts := FALSE
	END InitState;
	
	(** save static part of graphic state (e.g. after executing CVT program) **)
	PROCEDURE SaveState* (VAR c: Context; VAR s: State);
	BEGIN
		s.cvtCutIn := c.cvtCutIn;
		s.swCutIn := c.swCutIn; s.swVal := c.swVal;
		s.minDist := c.minDist;
		s.deltaBase := c.deltaBase; s.deltaShift := c.deltaShift;
		s.autoFlip := c.autoFlip;
		s.inhibitFit := c.inhibitFit; s.ignorePrep := c.ignorePrep;
		s.fixDropouts := c.fixDropouts; s.scanType := c.scanType
	END SaveState;
	
	(** restore static part of graphic state (e.g. before executing a glyph program) **)
	PROCEDURE RestoreState* (VAR c: Context; VAR s: State);
	BEGIN
		c.cvtCutIn := s.cvtCutIn;
		c.swCutIn := s.swCutIn; c.swVal := s.swVal;
		c.minDist := s.minDist;
		c.deltaBase := s.deltaBase; c.deltaShift := s.deltaShift;
		c.autoFlip := s.autoFlip;
		c.inhibitFit := s.inhibitFit; c.ignorePrep := s.ignorePrep;
		c.fixDropouts := s.fixDropouts; c.scanType := s.scanType
	END RestoreState;
	
	(** execute program **)
	PROCEDURE Execute* (VAR c: Context; code: Code; len: LONGINT; z0, z1: Zone);
	BEGIN
		c.code := code; c.codeLen := len; c.pc := 0; c.tos := -1; c.ctos := -1;
		c.zone[0] := z0; c.zone[1] := z1;
		c.free.x := 4000H; c.free.y := 0;
		c.proj := c.free; c.proj2 := c.free;
		c.gep0 := 1; c.gep1 := 1; c.gep2 := 1;
		c.zp0 := c.zone[c.gep0]; c.zp1 := c.zone[c.gep1]; c.zp2 := c.zone[c.gep2];
		c.rp0 := 0; c.rp1 := 0; c.rp2 := 0;
		c.period := 40H; c.phase := 0; c.threshold := 20H;
		c.loop := 1;
		c.ratio := 0;
		IF Notify # NIL THEN Notify(c, NotifyData) END;
		WHILE c.pc < c.codeLen DO
			Builtin[ORD(c.code[c.pc])](c)	(* call primitive for current instruction *)
		END;
		IF Notify # NIL THEN Notify(c, NotifyData) END
	END Execute;
	
	(** install notify procedure for debug events **)
	PROCEDURE InstallNotifier* (notify: Notifier; data: NotifierData);
	BEGIN
		Notify := notify; NotifyData := data
	END InstallNotifier;
	

BEGIN
	InitBuiltins;
	Zero64[0] := 0X; Zero64[1] := 0X; Zero64[2] := 0X; Zero64[3] := 0X;
	Zero64[4] := 0X; Zero64[5] := 0X; Zero64[6] := 0X; Zero64[7] := 0X;
	NewZone(EmptyZone, 0, 0);
	Notify := NIL; NotifyData := NIL
END OTInt.
