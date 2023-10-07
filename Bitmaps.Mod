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

MODULE Bitmaps;	(** non-portable *)

(* as 20.02.99, ported to Shark Oberon *)

(* to do: 
o get rid of buffer
o ASSERT bounds everywhere
*)

// TODO: the original version of this and some other modules are representative examples how
// in Oberon despite static typing people do low-level byte fiddling and pointer arithmetics
// (even assuming 32 bit width) evading the type checker without necessity; worth an article.

IMPORT Display, Displays;

CONST
	BufSize = 10000H;
	
TYPE	
  Data* = POINTER TO ARRAY OF CHAR;
	Bitmap* = POINTER TO BitmapDesc;
	BitmapDesc* = RECORD	(* cf. Display.DisplayBlock  *)
		width*, height*, depth*: INTEGER;	(* offset 0, 2, 4 *)
		wth*: LONGINT;	(* offset 8 *)
		data*: Data; (* offset 12 *) 
		// size is just LEN(data) which is just width*height
	END;

	Buffer = RECORD bytes: ARRAY BufSize OF CHAR END;

VAR
	buffer: POINTER TO Buffer;
	
PROCEDURE Define*(B: Bitmap; width, height, depth: INTEGER; data: Data);
BEGIN 
	B.width := width;
	B.wth := width;
	B.height := height;
	B.depth := depth;
	B.data := data;
END Define;

PROCEDURE Get*(B: Bitmap; X, Y: INTEGER): INTEGER;
VAR ofs: LONGINT; ch: CHAR;
BEGIN
	ofs := Y*B.wth + X;  ASSERT((ofs >= 0) & (ofs < LEN(B.data)));
	ch := B.data[ofs];
	RETURN ORD(ch)
END Get;

PROCEDURE Clear*(B: Bitmap);
VAR i: LONGINT;
BEGIN 
  FOR i := 0 TO LEN(B.data)-1 DO B.data[i] := 0X END;
END Clear;

PROCEDURE Dot*(B: Bitmap; col, X, Y, mode: INTEGER);
VAR i: LONGINT;  ch: CHAR;
BEGIN
	i := Y*B.wth + X;  ASSERT((i >= 0) & (i < LEN(B.data)));
	IF mode = Display.invert THEN
  	ch := B.data[i];
		B.data[i] := CHR(ORD(BITS( LONG(ORD(ch))) / BITS( LONG(col))))
	ELSE
		B.data[i] := CHR(col)
	END
END Dot;

PROCEDURE CopyBlock0(n, w: LONGINT; VAR src: ARRAY OF CHAR; srcoff: LONGINT; 
                                    VAR dest: ARRAY OF CHAR; destoff,width: LONGINT;  from: BOOLEAN);
BEGIN
	IF from THEN
		REPEAT Displays.Move(src, srcoff, dest, destoff, w); DEC(n); INC(srcoff, width); INC(destoff, w) UNTIL n = 0
	ELSE
		REPEAT Displays.Move(dest, destoff, src, srcoff, w); DEC(n); INC(srcoff, width); INC(destoff, w) UNTIL n = 0
	END
END CopyBlock0;

PROCEDURE CopyBlock*(sB, dB: Bitmap; SX, SY, W, H, DX, DY, mode: INTEGER);
VAR SourceWth, DestWth, sx, sy, w, h, dx, dy, w0, h0, dx0, dy0, src, dst, n, bufLines: LONGINT;
BEGIN	(* only the destination block is clipped *)
	SourceWth := sB.wth; DestWth := dB.wth;
	sx := SX;  sy := SY;  w := W;  h := H;  dx := DX;  dy := DY;
	w0 := w;  h0 := h;  dx0 := dx;  dy0 := dy;
	IF dx < 0 THEN dx := 0;  DEC(w, dx-dx0) END;
	IF dy < 0 THEN dy := 0;  DEC(h, dy-dy0) END;
	IF (w > 0) & (h > 0) & (w <= w0) & (h <= h0) THEN
		IF dx+w-1 > dB.width-1 THEN DEC(w, dx+w-1 - (dB.width-1)) END;
		IF dy+h-1 > dB.height-1 THEN DEC(h, dy+h-1 - (dB.height-1)) END;
		IF (w > 0) & (h > 0) & (w <= w0) & (h <= h0) THEN
			src := sy*SourceWth + sx;  ASSERT((src >= 0) & (src < LEN(sB.data)));
			dst := dy*DestWth + dx;  ASSERT((dst >= 0) & (dst < LEN(dB.data)));
			bufLines := BufSize DIV w;	(* lines to copy at a time *)
			IF bufLines > h THEN bufLines := h END;
				(* adjust direction for overlap *)
			IF (dy-h+1 < sy) & (sy < dy) THEN	(* start at bottom *)
				n := h-bufLines;
				INC(src, SourceWth*n);  INC(dst, DestWth*n);
				REPEAT
					CopyBlock0(bufLines, w, sB.data, src, buffer.bytes, 0, SourceWth, TRUE);
					CopyBlock0(bufLines, w, dB.data, dst, buffer.bytes, 0, DestWth, FALSE);
					DEC(h, bufLines);
					IF bufLines > h THEN bufLines := h END;
					DEC(src, bufLines * SourceWth);  DEC(dst, bufLines * DestWth)
				UNTIL h = 0
			ELSE	(* start at top *)
				REPEAT
					CopyBlock0(bufLines, w, sB.data, src, buffer.bytes, 0, SourceWth, TRUE);
					CopyBlock0(bufLines, w, dB.data, dst, buffer.bytes, 0, DestWth, FALSE);
					INC(src, bufLines * SourceWth);  INC(dst, bufLines * DestWth);
					DEC(h, bufLines);
					IF bufLines > h THEN bufLines := h END
				UNTIL h = 0
			END
		END
	END
END CopyBlock;

PROCEDURE CopyPattern0(ofs: LONGINT; VAR src: ARRAY OF CHAR; srcoff: LONGINT;
                                      VAR dst: ARRAY OF CHAR; dstoff, w, col, mode: LONGINT);
VAR ch,tmp: CHAR;  m, i: LONGINT;  s: SET;
BEGIN
	IF mode = Display.invert THEN
		REPEAT	(* loop over w pixels *)
			ch := src[srcoff];
			i := ofs;	(* start bit *)
			m := 8;	(* stop bit *)
			IF m > ofs+w THEN m := ofs+w END;
			REPEAT	(* loop over bits *)
				IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				  // NOTE: the original uses SYSTEM.GET/PUT(dst,SET), i.e. 4 byte operations, but
				  // dst is only incremented by one byte per iteration, so apparently the 3 upper bytes are ignored!
					tmp := dst[dstoff]; s := BITS(ORD(tmp));
					dst[dstoff] := CHR(ORD( BITS(col) / s))
				END;	
				INC(dstoff);  INC(i)
			UNTIL i = m;
			INC(srcoff);  DEC(w, m-ofs);  ofs := 0
		UNTIL w = 0
	ELSE (* paint, replace *)
		REPEAT	(* loop over w pixels *)
			ch := src[srcoff];
			i := ofs;	(* start bit *)
			m := 8;	(* stop bit *)
			IF m > ofs+w THEN m := ofs+w END;
			REPEAT	(* loop over bits *)
				IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
					(* paint & replace *) 
					dst[dstoff] := CHR(col)
				ELSIF mode = Display.replace THEN	(* pixel off *)
					dst[dstoff] := CHR(Display.BG)
				ELSE (* skip *)
				END;	
				INC(dstoff);  INC(i)
			UNTIL i = m;
			INC(srcoff);  DEC(w, m-ofs);  ofs := 0
		UNTIL w = 0
	END;
END CopyPattern0;

PROCEDURE CopyPattern1(B: Bitmap; VAR src: ARRAY OF CHAR; srcoff, x, y, w, col, mode: LONGINT); 
VAR ch: CHAR;  m, i: LONGINT;
BEGIN
	IF (y < 0) OR (y > B.height-1) THEN RETURN END;
	REPEAT	(* loop over w pixels *)
		ch := src[srcoff];
		i := 0;	(* start bit *)
		m := 8;	(* stop bit *)
		IF m > w THEN m := w END;
		REPEAT	(* loop over bits *)
			IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				Dot(B,SHORT(col), SHORT(x), SHORT(y), SHORT(mode))
			ELSIF mode = Display.replace THEN	(* pixel off *)
				Dot(B,Display.BG, SHORT(x), SHORT(y), Display.replace)
			ELSE (* skip *)
			END;
			INC(x);  INC(i)
		UNTIL i = m;
		INC(srcoff);  DEC(w, m)
	UNTIL w = 0
END CopyPattern1;

PROCEDURE CopyPattern*(B: Bitmap; col: INTEGER; pat: Display.Pattern; X, Y, mode: INTEGER);
VAR x, y, x2, y2, w, w0, h, src, dst: LONGINT;  ch: CHAR;
BEGIN
	w := ORD(pat[0]);
	h := ORD(pat[1]);
	IF (w > 0) & (h > 0) THEN
		x := X;  y := Y;  x2 := x+w-1;  y2 := y+h-1;	(* (x,y) bottom left & (x2,y2) top right *)
		src := 2;	(* first line of pattern *)
		w0 := (w+7) DIV 8;	(* bytes in pattern line *)
		IF (x >= 0) & (y >= 0) & (x2 < B.width) & (y2 < B.height) THEN	(* fully visible - common case *)
			dst := y * B.wth + x;
			REPEAT	(* loop over h lines *)
				CopyPattern0(0, pat, src, B.data, dst, w, col, mode);
				DEC(h);  INC(dst, B.wth);  INC(src, w0)
			UNTIL h = 0
		ELSIF (x2 >= 0) & (y2 >= 0) & (x < B.width) & (y < B.height) THEN	(* partially visible *)
			REPEAT	(* loop over h lines *)
				CopyPattern1(B, pat, src, x, y, w, col, mode);
				INC(y);  INC(src, w0);  DEC(h)
			UNTIL h = 0
		ELSE (* invisible *)
		END
	END
END CopyPattern;

PROCEDURE ReplConst*(B: Bitmap; col, X, Y, W, H, mode: INTEGER);
VAR boff, boff0, pat, w: LONGINT; s: SET; ch: CHAR;
BEGIN 
	boff := B.wth*Y + X;
	pat := col + ASH(col, 8) + ASH(col, 16) + ASH(col, 24);
	IF mode = Display.invert THEN
		WHILE H > 0 DO w := W; boff0 := boff;
			WHILE w # 0 DO
  			// again in original SYSTEM.GET/PUT(addr0,SET) is used, i.e. a 4 byte operation,
  			// but col only has 2 bytes and addr0 is incremented bytewise; from that
  			// we conclude that it's actually a one byte operation 
  			ch := B.data[boff0];
  			s := BITS(ORD(ch));
				B.data[boff0] := CHR(ORD( s/BITS( col)));
				DEC(w); INC(boff0)
			END;
			INC(boff, B.wth); DEC(H)
		END
	ELSE
		WHILE H > 0 DO w := W; boff0 := boff;
			WHILE w # 0 DO B.data[boff0] := CHR(col); DEC(w); INC(boff0) END;
			INC(boff, B.wth); DEC(H)
		END
	END;
END ReplConst;

PROCEDURE FillPattern0(ofs: LONGINT; VAR src: ARRAY OF CHAR; srcoff: LONGINT;
                        VAR dst: ARRAY OF CHAR; dstoff, w, pw, col, mode: LONGINT);
VAR ch, tmp: CHAR;  m, i, src0, left: LONGINT;  s: SET;
BEGIN
	left := pw-ofs;	(* pixels left to do in pattern *)
	src0 := srcoff;  INC(srcoff, ofs DIV 8);  ofs := ofs MOD 8;	(* start position *)
	IF mode = Display.invert THEN
		REPEAT	(* loop over w pixels *)
			ch := src[srcoff];
			i := ofs;	(* start bit *)
			m := 8;	(* stop bit *)
			IF m > ofs+left THEN m := ofs+left END;	(* max left times *)
			IF m > ofs+w THEN m := ofs+w END;	(* max w times *)
			REPEAT	(* loop over bits *)
				IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
				  // dito concerning actual number of bytes involved in the operation (see above)
				  tmp := dst[dstoff];
				  s := BITS(ORD(tmp));
					dst[dstoff] := CHR(ORD(BITS(col) / s))
				END;
				INC(dstoff);  INC(i)
			UNTIL i = m;
			INC(srcoff);  DEC(left, m-ofs);  DEC(w, m-ofs);  ofs := 0;
			IF left = 0 THEN srcoff := src0;  left := pw END	(* wrap to start of pattern *)
		UNTIL w = 0
	ELSIF mode = Display.paint THEN
		REPEAT	(* loop over w pixels *)
			ch := src[srcoff];
			i := ofs;	(* start bit *)
			m := 8;	(* stop bit *)
			IF m > ofs+left THEN m := ofs+left END;	(* max left times *)
			IF m > ofs+w THEN m := ofs+w END;	(* max w times *)
			REPEAT	(* loop over bits *)
				IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
					dst[dstoff] := CHR(col)
				END;
				INC(dstoff);  INC(i)
			UNTIL i = m;
			INC(srcoff);  DEC(left, m-ofs);  DEC(w, m-ofs);  ofs := 0;
			IF left = 0 THEN srcoff := src0;  left := pw END	(* wrap to start of pattern *)
		UNTIL w = 0
	ELSE (* replace *)
		REPEAT	(* loop over w pixels *)
			ch := src[srcoff];
			i := ofs;	(* start bit *)
			m := 8;	(* stop bit *)
			IF m > ofs+left THEN m := ofs+left END;	(* max left times *)
			IF m > ofs+w THEN m := ofs+w END;	(* max w times *)
			REPEAT	(* loop over bits *)
				IF ODD(ASH(ORD(ch), -i)) THEN	(* pixel on *)
					dst[dstoff] := CHR(col)
				ELSE (* pixel off *)
					dst[dstoff] := CHR(Display.BG)
				END;
				INC(dstoff);  INC(i)
			UNTIL i = m;
			INC(srcoff);  DEC(left, m-ofs);  DEC(w, m-ofs);  ofs := 0;
			IF left = 0 THEN srcoff := src0;  left := pw END	(* wrap to start of pattern *)
		UNTIL w = 0
	END
END FillPattern0;

PROCEDURE ReplPattern*(B: Bitmap; col: INTEGER; pat: Display.Pattern; X, Y, W, H, mode: INTEGER);
VAR px, pw, ph, x, y, x2, y2, w, w0, h, src0, src, dst: LONGINT;  ch: CHAR;
BEGIN
	x := X;  y := Y;  w := W;  h := H;
	x2 := x+w-1;  y2 := y+h-1;	(* (x,y) bottom left & (x2,y2) top right *)
	IF (w > 0) & (h > 0) THEN
		ch := pat[0];  pw := ORD(ch);
		ch := pat[1];  ph := ORD(ch);
		IF (pw > 0) & (ph > 0) THEN
			w0 := (pw+7) DIV 8;	(* bytes in pattern line *)
			src0 := (ph-1)*w0;	(* last line of pat *)
			src := 2;	(* start line of pat *)
			px := x MOD pw;	(* start pixel offset *)
			dst := y * B.wth + x; // index into B.data
			REPEAT	(* loop over h lines *)
				FillPattern0(px, pat, src, B.data, dst, w, pw, col, mode);
				DEC(h);  INC(dst, B.wth);
				IF src = src0 THEN src := 0 ELSE INC(src, w0) END
			UNTIL h = 0
		END
	END
END ReplPattern;

PROCEDURE DisplayBlock*(B: Bitmap; SX, SY, W, H, DX, DY, mode: INTEGER);
BEGIN 
	Display.DisplayBlock(B.data, B.depth, B.wth, SX, SY, W, H, DX, DY, mode);
END DisplayBlock;

PROCEDURE GetPix*(addr: Data; i: LONGINT; VAR buf: BYTE; depth: INTEGER);
VAR s1, s2, s3: SHORTINT; 
BEGIN 
	IF depth = 8 THEN buf := ORD(addr[i]); INC(i)
	ELSIF depth = 4 THEN 
		s1 := ORD(addr[i]); INC(i); s2 := ORD(addr[i]); INC(i); buf := s2*16 + (s1 MOD 16)
	ELSE (* depth = 1 *)
		s1 := 0; s2 := 0;
		WHILE s1 < 8 DO s3 := ORD(addr[i]); INC(i); INC(s1); s2 := s2*2 + s3 MOD 2 END; buf := s2
	END;
END GetPix;

PROCEDURE PutPix*(addr: Data; i: LONGINT; border: LONGINT; buf: BYTE; depth: INTEGER);
VAR s1: SHORTINT; 
BEGIN 
	IF (depth = 8) & (i < border) THEN addr[i] := CHR(buf); INC(i)
	ELSIF depth = 4 THEN 
		IF i < border THEN addr[i] := CHR(buf MOD 16); INC(i) END; 
		IF i < border THEN addr[i] := CHR(buf DIV 16 MOD 16); INC(i) END; 
	ELSE (* depth = 1 *)
		s1 := 0;
		WHILE s1 < 8 DO 
			IF i < border THEN 
				IF ODD(buf) THEN addr[i] := CHR(15) ELSE addr[i] := CHR(0) END
			END;
			INC(s1); INC(i); buf := buf DIV 2;
		END
	END;
END PutPix;

BEGIN
	NEW(buffer)
END Bitmaps.