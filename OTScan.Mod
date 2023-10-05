MODULE OTScan;	(** eos   **)

	(**
		Scan conversion for TrueType contours
	**)
	
	IMPORT
		OTInt;
		
	
	CONST
		(** enumeration rules **)
		Round* = 0;	(** if included, coordinates are rounded to integer grid (leave out for grey scales) **)
		Dropouts* = 1;	(** if included, dropouts are detected and fixed **)
		Stubs* = 2;	(** if included, only dropouts which intersect other pixels are fixed **)
		Smart* = 3;	(** if included, dropout pixels are positioned more intelligently **)
		
		X = OTInt.X; Y = OTInt.Y;
		
	
	TYPE
		F26D6 = OTInt.F26D6;
		Fixed = OTInt.Fixed;
		
		Intersection = POINTER TO IntersectionDesc;
		IntersectionDesc = RECORD
			xy: F26D6;	(* coordinate on corresponding scanline *)
			up: INTEGER;	(* contour direction at point *)
			param: Fixed;	(* curve parameter *)
			next: Intersection;	(* next intersection on same scanline *)
			link: Intersection;	(* next intersection on same contour *)
		END;
		
		Scanline = POINTER TO ScanlineDesc;
		ScanlineDesc = RECORD
			next, prev: Scanline;	(* next and previous scanline *)
			yx: F26D6;	(* scanline coordinate *)
			isect: Intersection;	(* list of intersections *)
		END;
		
		Rasterizer* = RECORD
			width*, height*: INTEGER;	(** dimensions of pixel matrix **)
			xmin*, ymin*, xmax*, ymax*: F26D6;	(** bounding box **)
			rules: SET;	(* scan conversion rules *)
			hor, ver: Scanline;	(* horizontal and vertical scanlines *)
		END;
		
		EnumData* = RECORD END;
		Enumerator* = PROCEDURE (rowcol: INTEGER; beg, end: F26D6; VAR data: EnumData);
		(**
			When enumerating rows, 'rowcol' is the row number and 'beg' and 'end' are subpixel values
			representing a horizontal interval in that row.
			When enumerating columns, 'rowcol' is the column number and 'beg' and 'end' are subpixel
			values representing a vertical interval in that column
		**)
		
	
	(*--- Conversion of Outline to Scanlines ---*)
	
	PROCEDURE Init (VAR first: Scanline);
		VAR last: Scanline;
	BEGIN
		NEW(first); NEW(last);
		first.yx := MIN(F26D6); first.next := last; first.prev := last; first.isect := NIL;
		last.yx := MAX(F26D6); last.prev := first; last.next := first; last.isect := NIL
	END Init;
	
	PROCEDURE Insert (VAR scan: Scanline; yx, xy: F26D6; up: INTEGER; hint: Intersection; t: Fixed);
		VAR sl: Scanline; is, prev: Intersection;
	BEGIN
		(* find correct scanline *)
		WHILE scan.next.yx <= yx DO scan := scan.next END;
		WHILE scan.yx > yx DO scan := scan.prev END;
		
		(* allocate new scanline if on new coordinate *)
		IF scan.yx < yx THEN
			NEW(sl); sl.yx := yx;
			sl.next := scan.next; sl.prev := scan;
			sl.next.prev := sl; scan.next := sl;
			NEW(is); is.xy := MAX(F26D6); is.next := is;
			sl.isect := is;
			scan := sl
		END;
		
		(* search place to insert and insert new intersection in scanline *)
		prev := scan.isect; WHILE prev.next.xy < xy DO prev := prev.next END;
		NEW(is); is.xy := xy; is.up := up;
		is.next := prev.next; prev.next := is;
		
		(* insert intersection within contour sequence *)
		is.param := t;
		WHILE hint.link.param < t DO hint := hint.link END;
		is.link := hint.link; hint.link := is
	END Insert;
	
	PROCEDURE IntersectLine (x0, y0, x1, y1: F26D6; VAR scans: Scanline; hint: Intersection; t, dt: Fixed);
		VAR y, yend, ystep, dy, dy0, dy2, dx, xstep, q, r, x, xr: F26D6; up: INTEGER; qt, rt, tr: Fixed;
	BEGIN
		IF y0 # y1 THEN
			y := y0+20H; yend := y1+20H;
			y := y - y MOD 40H + 20H;
			yend := yend - yend MOD 40H + 20H;
			IF y0 < y1 THEN
				up := 1; ystep := 40H; dy := y1 - y0; dy0 := y - y0
			ELSE
				up := -1; ystep := -40H; dy := y0 - y1; DEC(y, 40H); DEC(yend, 40H); dy0 := y0 - y
			END;
			IF y # yend THEN
				dy2 := 2*dy;
				
				IF x0 <= x1 THEN dx := x1 - x0; xstep := 1
				ELSE dx := x0 - x1; xstep := -1
				END;
				q := xstep * (dx DIV dy); r := 2*(dx MOD dy);
				x := x0 + q * dy0; xr := r * dy0;
				WHILE xr >= dy DO INC(x, xstep); DEC(xr, dy2) END;
				q := 40H*q; r := 40H*r;
				WHILE r >= dy DO INC(q, xstep); DEC(r, dy2) END;
				
				qt := dt DIV dy; rt := 2*(dt MOD dy);
				INC(t, qt * dy0); tr := rt * dy0;
				WHILE tr >= dy DO INC(t); DEC(tr, dy2) END;
				qt := 40H*qt; rt := 40H*rt;
				WHILE rt >= dy DO INC(qt); DEC(rt, dy2) END;
				
				REPEAT
					Insert(scans, y, x, up, hint, t);
					INC(x, q); INC(xr, r);
					IF xr >= dy THEN INC(x, xstep); DEC(xr, dy2) END;
					INC(t, qt); INC(tr, rt);
					IF tr >= dy THEN INC(t); DEC(tr, dy2) END;
					INC(y, ystep)
				UNTIL y = yend
			END
		END
	END IntersectLine;
	
	PROCEDURE IntersectBezier (x0, y0, x1, y1, x2, y2: F26D6; VAR scans: Scanline; hint: Intersection; t, dt: Fixed);
		VAR dx, dy, d, x01, y01, x12, y12, xm, ym: F26D6;
	BEGIN
		dx := x1 - x0; dy := y1 - y0;
		d := dx * dx + dy * dy;
		dx := x2 - x1; dy := y2 - y1;
		INC(d, dx * dx + dy * dy);
		IF d < 40H THEN	(* total curve length is smaller than an eighth a pixel *)
			IntersectLine(x0, y0, x2, y2, scans, hint, t, dt)
		ELSE
			dt := dt DIV 2;
			x01 := (x0 + x1 + 1) DIV 2; y01 := (y0 + y1 + 1) DIV 2;
			x12 := (x1 + x2 + 1) DIV 2; y12 := (y1 + y2 + 1) DIV 2;
			xm := (x01 + x12 + 1) DIV 2; ym := (y01 + y12 + 1) DIV 2;
			IntersectBezier(x0, y0, x01, y01, xm, ym, scans, hint, t, dt);
			IntersectBezier(xm, ym, x12, y12, x2, y2, scans, hint, t + dt, dt)
		END
	END IntersectBezier;
	
	(** convert outline to scanlines **)
	PROCEDURE Convert* (outline: OTInt.Zone; rules: SET; VAR r: Rasterizer);
		VAR
			hor, ver: Scanline; last, hint, is: Intersection; pt: OTInt.Points; cont, first, points, i, j, p, q: INTEGER; t: Fixed;
			c0, c2, c1: OTInt.Coord;
	BEGIN
		r.rules := rules;
		IF outline.contours = 0 THEN
			r.width := 0; r.height := 0;
			r.xmin := 0; r.ymin := 0; r.xmax := 0; r.ymax := 0;
			RETURN
		END;
		Init(r.hor); Init(r.ver); hor := r.hor; ver := r.ver;
		NEW(last); last.param := MAX(Fixed);	(* sentinel for contour list *)
		pt := outline.pt;
		cont := 0;
		WHILE cont < outline.contours DO
			first := outline.first[cont]; points := outline.first[cont+1] - first;
			i := 0; WHILE (i < points) & ~pt[first + i].onCurve DO INC(i) END;	(* find first point that is on contour *)
			IF i < points THEN
				j := i; p := first + j;
				hint := last; hint.link := last;
				t := 0;	(* contour parameter *)
				c0 := pt[p].cur;
				REPEAT
					j := (j+1) MOD points; p := first + j;
					IF pt[p].onCurve THEN	(* line *)
						c2 := pt[p].cur;
						IntersectLine(c0[X], c0[Y], c2[X], c2[Y], hor, hint, t, 10000H);
						IntersectLine(c0[Y], c0[X], c2[Y], c2[X], ver, hint, t, 10000H)
					ELSE
						c1 := pt[p].cur;
						q := first + (j+1) MOD points;
						IF pt[q].onCurve THEN	(* Bezier with explicit end point *)
							j := q - first; p := q;
							c2 := pt[p].cur
						ELSE	(* Bezier with implicit end-point *)
							c2[X] := (pt[p].cur[X] + pt[q].cur[X]) DIV 2;
							c2[Y] := (pt[p].cur[Y] + pt[q].cur[Y]) DIV 2
						END;
						IntersectBezier(c0[X], c0[Y], c1[X], c1[Y], c2[X], c2[Y], hor, hint, t, 10000H);
						IntersectBezier(c0[Y], c0[X], c1[Y], c1[X], c2[Y], c2[X], ver, hint, t, 10000H)
					END;
					c0 := c2; INC(t, 10000H);
					WHILE hint.link # last DO hint := hint.link END
				UNTIL j = i;
				hint.link := last.link	(* unlink sentinel of contour list *)
			END;
			INC(cont)
		END;
		
	(*
		r.xmin := r.ver.next.yx DIV 40H * 40H; r.xmax := (r.ver.prev.prev.yx DIV 40H + 1) * 40H;
		r.ymin := r.hor.next.yx DIV 40H * 40H; r.ymax := (r.hor.prev.prev.yx DIV 40H + 1) * 40H;
	*)
	
	(**)
		(* calculate bounding box *)
	(*
		r.xmin := MAX(F26D6); r.ymin := MAX(F26D6);
		r.xmax := MIN(F26D6); r.ymax := MIN(F26D6);
	*)
	(**)
		r.xmin := r.ver.next.yx; r.xmax := r.ver.prev.prev.yx;
		r.ymin := r.hor.next.yx; r.ymax := r.hor.prev.prev.yx;
	(**)
		hor := r.hor.next;
		WHILE hor # r.hor.prev DO
			is := hor.isect.next;
			IF is.xy < r.xmin THEN r.xmin := is.xy END;
			WHILE is.next # hor.isect DO is := is.next END;
			IF is.xy > r.xmax THEN r.xmax := is.xy END;
			hor := hor.next
		END;
		ver := r.ver.next;
		WHILE ver # r.ver.prev DO
			is := ver.isect.next;
			IF is.xy < r.ymin THEN r.ymin := is.xy END;
			WHILE is.next # ver.isect DO is := is.next END;
			IF is.xy > r.ymax THEN r.ymax := is.xy END;
			ver := ver.next
		END;
		r.xmin := r.xmin - r.xmin MOD 40H;
		r.ymin := r.ymin - r.ymin MOD 40H;
		r.xmax := r.xmax + 40H - r.xmax MOD 40H;
		r.ymax := r.ymax + 40H - r.ymax MOD 40H;
	(**)
	
		IF r.xmin < r.xmax THEN r.width := SHORT((r.xmax - r.xmin) DIV 40H) ELSE r.width := 0 END;
		IF r.ymin < r.ymax THEN r.height := SHORT((r.ymax - r.ymin) DIV 40H) ELSE r.height := 0 END
	END Convert;
	
	(** enumerate rows or columns of scan-converted outline **)
	PROCEDURE EnumerateRows* (VAR r: Rasterizer; enum: Enumerator; VAR data: EnumData);
		VAR hor: Scanline; is, is0: Intersection; x0, r0, x1, r1: F26D6; sum: INTEGER;
	BEGIN
		IF r.width * r.height = 0 THEN RETURN END;
		hor := r.hor.next;
		WHILE hor.next # r.hor DO
			is := hor.isect.next;
			WHILE is # hor.isect DO
				is0 := is; x0 := is0.xy;
				IF Round IN r.rules THEN
					r0 := x0 MOD 40H; DEC(x0, r0);
					IF r0 > 20H THEN INC(x0, 40H) END
				END;
				sum := is.up; REPEAT is := is.next; INC(sum, is.up) 
				UNTIL (is = hor.isect) OR (sum = 0);
				IF is # hor.isect THEN	(* found opposite intersection *)
					x1 := is.xy;
					IF Round IN r.rules THEN
						r1 := x1 MOD 40H; DEC(x1, r1);
						IF r1 >= 20H THEN INC(x1, 40H) END	(* greater or equal to include pixel center *)
					END;
					IF (x0 = x1) & (Dropouts IN r.rules) & (~(Stubs IN r.rules) OR (is0.link # is) & (is.link # is0)) THEN
						IF Round IN r.rules THEN
							IF Smart IN r.rules THEN
								r0 := ((is0.xy + is.xy) DIV 2) MOD 40H;	(* use middle of both points to choose pixel *)
								IF (r0 = 0) OR (r0 > 20H) THEN x0 := x1 - 40H	(* midpoint in upper half of lower pixel *)
								ELSE x1 := x0 + 40H	(* midpoint in lower half of upper pixel *)
								END
							ELSE
								x0 := x1 - 40H	(* choose left pixel *)
							END
						ELSE	(* create 1/64 pixel distance between x0 and x1 *)
							IF x0 MOD 40H > 20H THEN DEC(x0) ELSE INC(x1) END
						END
					END;
					IF x0 < x1 THEN
						enum(SHORT((hor.yx - r.ymin) DIV 40H), x0 - r.xmin, x1 - r.xmin, data)
					END;
					is := is.next
				END
			END;
			hor := hor.next
		END
	END EnumerateRows;
	
	PROCEDURE EnumerateColumns* (VAR r: Rasterizer; enum: Enumerator; VAR data: EnumData);
		VAR ver: Scanline; is, is0: Intersection; y0, r0, y1, r1: F26D6; sum: INTEGER;
	BEGIN
		IF r.width * r.height = 0 THEN RETURN END;
		ver := r.ver.next;
		WHILE ver.next # r.ver DO
			is := ver.isect.next;
			WHILE is # ver.isect DO
				is0 := is; y0 := is0.xy;
				IF Round IN r.rules THEN
					r0 := y0 MOD 40H; DEC(y0, r0);
					IF r0 > 20H THEN INC(y0, 40H) END
				END;
				sum := is.up; REPEAT is := is.next; INC(sum, is.up) UNTIL (is = ver.isect) OR (sum = 0);
				IF is # ver.isect THEN	(* found opposite intersection *)
					y1 := is.xy;
					IF Round IN r.rules THEN
						r1 := y1 MOD 40H; DEC(y1, r1);
						IF r1 >= 20H THEN INC(y1, 40H) END	(* greater or equal to include pixel center *)
					END;
					IF (y0 = y1) & (Dropouts IN r.rules) & (~(Stubs IN r.rules) OR (is0.link # is) & (is.link # is0)) THEN
						IF Round IN r.rules THEN
							IF Smart IN r.rules THEN
								r0 := ((is0.xy + is.xy) DIV 2) MOD 40H;	(* use middle of both points to choose pixel *)
								IF (r0 = 0) OR (r0 > 20H) THEN y0 := y1 - 40H	(* midpoint in upper half of lower pixel *)
								ELSE y1 := y0 + 40H	(* midpoint in lower half of upper pixel *)
								END
							ELSE
								y0 := y1 - 40H	(* choose lower pixel *)
							END
						ELSE	(* create 1/64 pixel distance between y0 and y1 *)
							IF y0 MOD 40H > 20H THEN DEC(y0) ELSE INC(y1) END
						END
					END;
					IF y0 < y1 THEN
						enum(SHORT((ver.yx - r.xmin) DIV 40H), y0 - r.ymin, y1 - r.ymin, data)
					END;
					is := is.next
				END
			END;
			ver := ver.next
		END
	END EnumerateColumns;
	
	
END OTScan.
