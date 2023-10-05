MODULE GfxRegions;	(** eos   **)

	(**
		Implements arbitrarily shaped two_dimensional regions
	**)
	
	(*
		17.2.97 - eliminated rectangle type, added shift offsets, made enumerator extensible
		2.5.97 - prevent dropouts when validating
		17.7.97 - fixed bug in Validate (trying to copy filler spans if data was reallocated)
		17.7.97 - eliminated size field
		12.3.98 - eliminated shifted operations, fixed Shift to treat boundary cases correctly
		5.5.98 - fixed bug in Intersect (wrong index into arg region)
	*)
	
	CONST
		(** mode for reducing regions to non_overlapping areas **)
		Winding* = 0;	(** non_zero winding rule **)
		EvenOdd* = 1;	(** exclusive_or rule **)
		
		(** interval of valid region coordinates (UBound - LBound is still representable within INTEGER **)
		UBound* = MAX(INTEGER) DIV 2;
		LBound* = MIN(INTEGER) DIV 2;
		
		BlockSize = 512;	(* size increment for region data blocks *)
		Enter = 1; Exit = -1;	(* direction of bounding curve at scanline intersection *)
		FirstSlice = 2;	(* index of first slice *)
		Bottom = MIN(INTEGER); Top = MAX(INTEGER);	(* sentinel values *)
		
	
	TYPE
		RegionData = POINTER TO ARRAY OF LONGINT;
		
		(** regions of arbitrary shape **)
		Region* = POINTER TO RegionDesc;
		RegionDesc* = RECORD
			llx*, lly*, urx*, ury*: INTEGER;	(** bounding box **)
			mode*: INTEGER;	(** mode for reducing region to non_overlapping areas (Winding/EvenOdd) **)
			valid: BOOLEAN;	(* flag if points in data array are consistent (i.e. sorted & compacted) *)
			data: RegionData;	(* points defining region boundary *)
			points: LONGINT;	(* number of data points actually used *)
		END;
		
		(** region enumeration **)
		EnumData* = RECORD END;
		Enumerator* = PROCEDURE (llx, lly, urx, ury: INTEGER; VAR edata: EnumData);
		
	
	VAR
		Data: RegionData;	(* temporary region data for merging *)
		DataSize: LONGINT;	(* number of points allocated for Data *)
		RectRegion: Region;	(* temporary rectangular region for boolean operations *)
		
	
	(**--- Rectangles ---**)
	
	(** make rectangle large enough to include a point **)
	PROCEDURE IncludePoint* (VAR llx, lly, urx, ury: INTEGER; x, y: INTEGER);
	BEGIN
		IF x < llx THEN llx := x END;
		IF x > urx THEN urx := x END;
		IF y < lly THEN lly := y END;
		IF y > ury THEN ury := y END
	END IncludePoint;
	
	(** make rectangle large enough to include other rectangle **)
	PROCEDURE IncludeRect* (VAR llx, lly, urx, ury: INTEGER; illx, illy, iurx, iury: INTEGER);
	BEGIN
		IF illx < llx THEN llx := illx END;
		IF iurx > urx THEN urx := iurx END;
		IF illy < lly THEN lly := illy END;
		IF iury > ury THEN ury := iury END
	END IncludeRect;
	
	(** shrink rectangle to area within other rectangle **)
	PROCEDURE ClipRect* (VAR llx, lly, urx, ury: INTEGER; cllx, clly, curx, cury: INTEGER);
	BEGIN
		IF cllx > llx THEN llx := cllx END;
		IF curx < urx THEN urx := curx END;
		IF clly > lly THEN lly := clly END;
		IF cury < ury THEN ury := cury END
	END ClipRect;
	
	(** return whether rectangle is empty **)
	PROCEDURE RectEmpty* (llx, lly, urx, ury: INTEGER): BOOLEAN;
	BEGIN
		RETURN (llx >= urx) OR (lly >= ury)
	END RectEmpty;
	
	(** return whether (non_empty) rectangle is completely inside other rectangle **)
	PROCEDURE RectInRect* (llx, lly, urx, ury, illx, illy, iurx, iury: INTEGER): BOOLEAN;
	BEGIN
		RETURN (llx >= illx) & (urx <= iurx) & (lly >= illy) & (ury <= iury)
	END RectInRect;
	
	(** return whether (non_empty) rectangle intersects other rectangle **)
	PROCEDURE RectsIntersect* (llx, lly, urx, ury, illx, illy, iurx, iury: INTEGER): BOOLEAN;
	BEGIN
		RETURN (llx < iurx) & (urx > illx) & (lly < iury) & (ury > illy)
	END RectsIntersect;
	
	(** return whether rectangle contains point **)
	PROCEDURE PointInRect* (x, y: INTEGER; llx, lly, urx, ury: INTEGER): BOOLEAN;
	BEGIN
		RETURN (x >= llx) & (x < urx) & (y >= lly) & (y < ury)
	END PointInRect;
	
	
	(*--- Auxiliary Routines For Managing Regions ---*)

	(*
		Implementation notes:
		
		Regions are managed by slicing them horizontally. For each scanline y, a set of spans on the scanline defines which
		parts of the scanline are part of the region. The spans are defined through the x_coordinates of their end points.
		Every point on a scanline has a direction attribute, which specifies whether the point starts a span (Enter) or ends
		one (Exit), allowing spans to nest or overlap.
		
		The x_ and y_coordinates of a point along with its direction are encoded into a LONGINT. The chosen encoding
		weights the y_coordinate most, followed by the x_coordinate and the direction of an intersection. Visiting all
		encoded points in ascending order therefore traverses all spans of the region from the bottom left corner to the
		top right corner.
		
		In order to save space, identical slices adjacent to each other are stored only once. The bottommost scanline of
		an identical sequence of scanlines serves as a representant for the whole sequence; all others are eliminated.
		This means that if no points exist for a certain y_coordinate, the spans of the corresponding scanline are identical
		to those of the one below it. As a consequence, scanlines that are completely outside the region need an empty
		filler span to distinguish them from eliminated scanlines. A filler span consists of two points located at UBound,
		one entering the region and the other leaving it.
		
		Most operations modifying regions append new points in ascending order to the sequence of existing points and
		then merge the two sequences again. If points cannot be appended in order, the whole set of points has to be
		sorted before any other operation can be executed. Doing this immediately after the sequence of points has been
		invalidated can decrease performance significantly if a lot of invalidating operations are issued in sequence, as is
		typically the case with AddPoint. This is why regions have a valid flag, indicating whether encoded points are sorted
		or not. Invalidating operations only have to set valid to FALSE, other operations will eventually validate the region
		again, at the same time eliminating multiple points and overlapping spans.
	*)
	
	PROCEDURE Min (x, y: INTEGER): INTEGER;
	BEGIN
		IF x <= y THEN RETURN x ELSE RETURN y END
	END Min;
	
	PROCEDURE Max (x, y: INTEGER): INTEGER;
	BEGIN
		IF x >= y THEN RETURN x ELSE RETURN y END
	END Max;
	
	(* encode point coordinates and curve direction into a LONGINT *)
	PROCEDURE Encode (VAR item: LONGINT; u, v, dir: LONGINT);
	BEGIN
		item := ASH(v, 16) + ASH((u + 4000H) MOD 8000H, 1) + ASH(1 + dir, -1)
	END Encode;
	
	(* restore point coordinates and curve direction from an encoded LONGINT *)
	PROCEDURE Decode (item: LONGINT; VAR u, v, dir: INTEGER);
	BEGIN
		v := SHORT(ASH(item, -16));
		u := SHORT(ASH(item, -1) MOD 8000H - 4000H);
		dir := SHORT(ASH(item MOD 2, 1) - 1)
	END Decode;
	
	(* copy points between region data blocks *)
	PROCEDURE CopyPoints (src, dst: RegionData; points: LONGINT);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE i < points DO
			dst[i] := src[i];
			INC(i)
		END
	END CopyPoints;
	
	(* append point to region data *)
	PROCEDURE Append (reg: Region; u, v, dir: INTEGER);
		VAR size: LONGINT; data: RegionData;
	BEGIN
		IF reg.data = NIL THEN
			NEW(reg.data, BlockSize)
		ELSIF reg.points >= LEN(reg.data^) THEN	(* grow data array *)
			size := LEN(reg.data^) + BlockSize;
			NEW(data, size);
			CopyPoints(reg.data, data, reg.points);
			reg.data := data
		END;
		Encode(reg.data[reg.points], u, v, dir);
		INC(reg.points)
	END Append;
	
	(* copy region data *)
	PROCEDURE CopyData (src, dst: Region);
		VAR size: LONGINT;
	BEGIN
		IF src.points > 0 THEN
			IF (dst.data = NIL) OR (LEN(dst.data^) < src.points) THEN
				size := src.points + (-src.points) MOD BlockSize;	(* round up to multiple of BlockSize *)
				NEW(dst.data, size)
			END;
			CopyPoints(src.data, dst.data, src.points)
		END;
		dst.points := src.points;
		dst.llx := src.llx; dst.lly := src.lly;
		dst.urx := src.urx; dst.ury := src.ury;
		dst.valid := src.valid
	END CopyData;
	
	(* re_calculate bounding box of (valid!) region *)
	PROCEDURE CalcRect (reg: Region);
		VAR data: RegionData; n: LONGINT; u, v, dir, x: INTEGER;
	BEGIN
		ASSERT(reg.valid);
		IF reg.points > 0 THEN
			data := reg.data;
			n := FirstSlice;
			Decode(data[n], u, v, dir);
			reg.llx := u; reg.urx := u; reg.lly := v;
			REPEAT
				reg.ury := v; x := u;
				REPEAT
					IF (dir = Enter) & (u < reg.llx) THEN
						reg.llx := u; x := u
					ELSIF (dir = Exit) & (u > reg.urx) & (u > x) THEN	(* last term excludes filler spans *)
						reg.urx := u
					END;
					INC(n);
					Decode(data[n], u, v, dir)
				UNTIL v > reg.ury;
			UNTIL v = Top
		END
	END CalcRect;
	
	(* sort region data points in ascending y and x order *)
	PROCEDURE SortRange (data: RegionData; lo, hi: LONGINT);
		CONST limit = 8;
		VAR i, x, j, t: LONGINT;
	BEGIN
		IF hi - lo < limit THEN	(* use straight insertion for less than limit entries... *)
			i := lo + 1;
			WHILE i <= hi DO
				x := data[i];
				j := i;
				WHILE (j > lo) & (x < data[j - 1]) DO
					data[j] := data[j - 1];
					DEC(j)
				END;
				data[j] := x;
				INC(i)
			END
		
		ELSE	(* ...otherwise partition and recurse *)
			i := lo; j := hi;
			x := data[(lo + hi) DIV 2];
			REPEAT
				WHILE data[i] < x DO INC(i) END;
				WHILE data[j] > x DO DEC(j) END;
				IF i <= j THEN
					t := data[i]; data[i] := data[j]; data[j] := t;
					INC(i); DEC(j)
				END
			UNTIL i > j;
			IF lo < j THEN SortRange(data, lo, j) END;
			IF i < hi THEN SortRange(data, i, hi) END
		END
	END SortRange;
	
	(*	haven't needed this in a long time but better keep my fingers crossed
	PROCEDURE Show* (data: RegionData; points: LONGINT);
		VAR n: LONGINT; y, x, dir, v: INTEGER;
	BEGIN
		n := 0;
		Decode(data[n], x, y, dir);
		INC(n);
		WHILE n < points DO
			Out.Int(y, 0); Out.String(": "); Out.Int(x, 0); IF dir = Enter THEN Out.Char("+") ELSE Out.Char("-") END;
			LOOP
				Decode(data[n], x, v, dir);
				INC(n);
				IF (n >= points) OR (v # y) THEN EXIT END;
				Out.Char(" "); Out.Int(x, 0); IF dir = Enter THEN Out.Char("+") ELSE Out.Char("-") END
			END;
			y := v;
			Out.Ln
		END;
		Out.Int(y, 0); Out.String(": "); Out.Int(x, 0); IF dir = Enter THEN Out.Char("+") ELSE Out.Char("-") END; Out.Ln;
		Out.String("---"); Out.Ln
	END Show;
	
	PROCEDURE ShowReg* (reg: Region);
	BEGIN
		IF reg.points = 0 THEN
			Out.String("["); Out.Int(reg.llx, 5); Out.Int(reg.lly, 5); Out.Int(reg.urx, 5); Out.Int(reg.ury, 5); Out.Char("]"); Out.Ln
		ELSE
			Show(reg.data, reg.points)
		END
	END ShowReg;
	*)
	
	(* eliminate duplicate slices *)
	PROCEDURE Compact (reg: Region; src: RegionData);
		VAR rslice, dslice, sn, rn, dn: LONGINT; dst: RegionData; su, sv, sdir, ru, rv, rdir, sy, ry: INTEGER;
	BEGIN
		rslice := 0;	(* start of current reference slice is the bottom sentinel slice *)
		dslice := FirstSlice;	(* start of current destination slice *)
		sn := FirstSlice;	(* current reading position *)
		dst := reg.data;
		Decode(src[sn], su, sv, sdir);
		
		REPEAT
			(* compare next source slice to current reference slice *)
			rn := rslice; dn := dslice;
			Decode(dst[rn], ru, rv, rdir);
			sy := sv; ry := rv;
			WHILE (sv = sy) & (rv = ry) & (su = ru) & (sdir = rdir) DO	(* copy while slices are equal *)
				dst[dn] := src[sn];
				INC(dn); INC(sn); INC(rn);
				Decode(src[sn], su, sv, sdir);
				Decode(dst[rn], ru, rv, rdir)
			END;
			
			IF (sv = sy) OR (rv = ry) THEN	(* slices are different => copy rest of source slice to destination *)
				WHILE sv = sy DO
					dst[dn] := src[sn];
					INC(dn); INC(sn);
					Decode(src[sn], su, sv, sdir)
				END;
				
				(* the slice just written becomes the new reference slice *)
				rslice := dslice;
				dslice := dn
			END
		UNTIL sv = Top;
		
		IF dn = 6 THEN	(* region contains only one rectangle *)
			Decode(dst[FirstSlice], reg.llx, reg.lly, rdir);
			Decode(dst[FirstSlice + 1], reg.urx, reg.lly, rdir);
			Decode(dst[FirstSlice + 2], ru, reg.ury, rdir);
			reg.points := 0
		ELSE
			Encode(dst[dn], UBound, Top, Exit);
			reg.points := dn + 1
		END
	END Compact;
	
	(* merge two runs of data points *)
	PROCEDURE Merge (reg: Region; split: LONGINT);
		VAR data: RegionData; n, N, m, M, p, tmp: LONGINT; nu, nv, ndir, mu, mv, mdir, sum, u, v, inc, nsum: INTEGER;
	BEGIN
		data := reg.data;
		n := 0; N := split;
		Decode(data[n], nu, nv, ndir);
		m := split; M := reg.points;
		Decode(data[m], mu, mv, mdir);
		p := 0;
		Append(reg, UBound, Top, Exit);	(* sentinel for upper part *)
		
		IF DataSize <= M THEN	(* reallocate temporary buffer *)
			DataSize := M - M MOD BlockSize + BlockSize;
			NEW(Data, DataSize)
		END;
		
		WHILE (n < N) & (m < M) DO
			tmp := p;
			v := Min(nv, mv);
			
			(* eliminate overlapping spans before copying them *)
			sum := 0;
			REPEAT
				(* get next point *)
				IF (nv < mv) OR (nv = mv) & (nu <= mu) THEN
					u := nu; inc := ndir;
					INC(n);
					Decode(data[n], nu, nv, ndir)
				ELSE
					u := mu; inc := mdir;
					INC(m);
					Decode(data[m], mu, mv, mdir)
				END;
				
				(* accumulate directions of coincident points *)
				WHILE (nv = v) & (nu = u) DO
					INC(inc, ndir); INC(n);
					Decode(data[n], nu, nv, ndir)
				END;
				WHILE (mv = v) & (mu = u) DO
					INC(inc, mdir); INC(m);
					Decode(data[m], mu, mv, mdir)
				END;
				
				IF inc # 0 THEN	(* append point to merged data *)
					nsum := sum + inc;
					IF reg.mode = Winding THEN
						IF (sum <= 0) & (nsum > 0) THEN
							Encode(Data[p], u, v, Enter); INC(p)
						ELSIF (sum > 0) & (nsum <= 0) THEN
							Encode(Data[p], u, v, Exit); INC(p)
						END
					ELSIF (reg.mode = EvenOdd) & ((sum > 0) & ODD(sum) # (nsum > 0) & ODD(nsum)) THEN
						IF ODD(sum) THEN
							Encode(Data[p], u, v, Exit)
						ELSE
							Encode(Data[p], u, v, Enter)
						END;
						INC(p)
					END;
					sum := nsum
				END
			UNTIL (nv > v) & (mv > v);
			
			IF p = tmp THEN	(* line is empty => append filler slice *)
				Encode(Data[p], UBound, v, Enter); INC(p);
				Encode(Data[p], UBound, v, Exit); INC(p)
			END
		END;
		
		(* copy remaining points *)
		WHILE n < N DO
			Data[p] := data[n];
			INC(p); INC(n)
		END;
		WHILE m < M DO
			Data[p] := data[m];
			INC(p); INC(m)
		END;
		
		(* copy merged data back and eliminate duplicate scanlines *)
		Compact(reg, Data)
	END Merge;
	
	(* bring region data into consistent state *)
	PROCEDURE Validate (reg: Region);
		VAR data: RegionData; points, rn, wn, tmp: LONGINT; u, v, dir, y, sum, x, inc: INTEGER;
	BEGIN
		IF ~reg.valid THEN
			data := reg.data;
			SortRange(data, 0, reg.points - 1);
			points := reg.points;
			rn := FirstSlice; wn := FirstSlice;	(* read and write position *)
			Decode(data[rn], u, v, dir);
			
			REPEAT
				tmp := wn;
				y := v;
				sum := 0;
				REPEAT
					(* accumulate directions of coincident points *)
					x := u; inc := 0;
					REPEAT
						INC(inc, dir); INC(rn);
						Decode(data[rn], u, v, dir)
					UNTIL (v > y) OR (u > x);
					
					IF x < UBound THEN
						IF reg.mode = Winding THEN
							IF sum = 0 THEN
								Encode(data[wn], x, y, Enter); INC(wn);
								INC(x)	(* prevent dropouts *)
							END;
							INC(sum, inc);
							IF sum = 0 THEN
								Encode(data[wn], x, y, Exit); INC(wn)
							END
						ELSIF reg.mode = EvenOdd THEN
							IF ~ODD(sum) THEN
								Encode(data[wn], x, y, Enter); INC(wn);
								INC(x)	(* prevent dropouts *)
							END;
							INC(sum, inc);
							IF ~ODD(sum) THEN
								Encode(data[wn], x, y, Exit); INC(wn)
							END
						END
					END
				UNTIL v > y;
				
				IF wn = tmp THEN	(* insert filler span if all slices have been eliminated *)
					Encode(data[wn], UBound, y, Enter); INC(wn);
					Encode(data[wn], UBound, y, Exit); INC(wn)
				ELSIF v > y + 1 THEN	(* add filler slice for disconnected regions *)
					INC(y);
					Append(reg, UBound, y, Enter);
					Append(reg, UBound, y, Exit)
				END
			UNTIL v = Top;
			
			Encode(data[wn], UBound, Top, Exit); INC(wn);
			IF reg.points > points THEN	(* added filler slices => must merge *)
				IF wn < points THEN	(* some points have been discarded => move filler slices *)
					rn := points; points := wn;
					REPEAT
						data[wn] := reg.data[rn];	(* data may have been reallocated! *)
						INC(wn); INC(rn)
					UNTIL rn = reg.points;
					reg.data := data;
					reg.points := wn
				END;
				Merge(reg, points)
			ELSE	(* points are still sorted *)
				reg.points := wn;
				Compact(reg, reg.data)
			END;
			reg.valid := TRUE
		END
	END Validate;
	
	(* find first point on line y or higher *)
	PROCEDURE FindUpper (reg: Region; y: INTEGER; VAR n: LONGINT);
		VAR item, i, j, m: LONGINT;
	BEGIN
		item := ASH(LONG(y), 16);	(* leftmost possible point on line y *)
		i := 0; j := reg.points;
		WHILE i + 1 < j DO
			m := (i + j) DIV 2;
			IF reg.data[m] < item THEN
				i := m
			ELSE
				j := m
			END
		END;
		n := j
	END FindUpper;
	
	(* find first point on line y or lower *)
	PROCEDURE FindLower (reg: Region; y: INTEGER; VAR n: LONGINT);
		VAR v: INTEGER;
	BEGIN
		FindUpper(reg, y, n);
		v := SHORT(ASH(reg.data[n], -16));
		IF v > y THEN	(* => find leftmost point on lower slice *)
			DEC(n);
			y := SHORT(ASH(reg.data[n], -16));
			REPEAT
				DEC(n)
			UNTIL (n < 0) OR (ASH(reg.data[n], -16) < y);
			INC(n)
		END
	END FindLower;
	
	(* enumerate (inverted) region within rectangle *)
	PROCEDURE Enum (reg: Region; llx, lly, urx, ury: INTEGER; enum: Enumerator; VAR edata: EnumData; enter: INTEGER);
		VAR data: RegionData; n, lo, hi: LONGINT; u, v, dir, y, top, x: INTEGER;
	BEGIN
		Validate(reg);
		ClipRect(llx, lly, urx, ury, LBound, LBound, UBound, UBound);
		data := reg.data;
		FindLower(reg, lly, n);
		Decode(data[n], u, v, dir);
		y := lly;
		
		REPEAT
			(* calculate height of slice *)
			lo := n;
			REPEAT
				INC(n);
				IF u < llx THEN
					lo := n
				END;
				Decode(data[n], u, v, dir)
			UNTIL v > y;
			hi := n;
			top := Min(v, ury);
			
			(* enumerate spans of current slice *)
			n := lo;
			Decode(data[n], u, v, dir);
			x := llx;
			WHILE (v <= y) & ((u < urx) OR (dir # enter)) DO
				IF u > x THEN
					IF dir = enter THEN
						x := u
					ELSE
						enum(x, y, Min(u, urx), top, edata)
					END
				END;
				INC(n);
				Decode(data[n], u, v, dir)
			END;
			
			IF n < hi THEN
				n := hi;
				Decode(data[n], u, v, dir)
			END;
			y := v
		UNTIL v >= ury
	END Enum;
	
	(* create data points for rectangular region *)
	PROCEDURE MakeData (reg: Region);
	BEGIN
		IF reg.points = 0 THEN
			Append(reg, UBound, Bottom, Enter);
			Append(reg, UBound, Bottom, Exit);
			IF (reg.llx <= reg.urx) & (reg.lly <= reg.ury) THEN
				Append(reg, reg.llx, reg.lly, Enter);
				Append(reg, reg.urx, reg.lly, Exit);
				Append(reg, UBound, reg.ury, Enter);
				Append(reg, UBound, reg.ury, Exit)
			END;
			Append(reg, UBound, Top, Enter)
		END
	END MakeData;
	
	
	(**--- Region Queries ---**)
	
	(** return whether region is empty **)
	PROCEDURE Empty* (reg: Region): BOOLEAN;
	BEGIN
		RETURN (reg.llx >= reg.urx) OR (reg.lly >= reg.ury)
	END Empty;
	
	(** return whether (non_empty) region is rectangular **)
	PROCEDURE IsRect* (reg: Region): BOOLEAN;
	BEGIN
		Validate(reg);
		RETURN reg.points = 0
	END IsRect;
	
	(** return whether point is inside (non_empty) region **)
	PROCEDURE PointInside* (x, y: INTEGER; reg: Region): BOOLEAN;
		VAR data: RegionData; n: LONGINT; u, v, dir: INTEGER;
	BEGIN
		IF ~PointInRect(x, y, reg.llx, reg.lly, reg.urx, reg.ury) THEN	(* point not even within region rectangle *)
			RETURN FALSE
		ELSIF IsRect(reg) THEN	(* region is rectangular *)
			RETURN TRUE
		END;
		
		(* find span containing point *)
		data := reg.data;
		FindLower(reg, y, n);
		Decode(data[n], u, v, dir);
		WHILE u < x DO
			INC(n);
			Decode(data[n], u, v, dir)
		END;
		RETURN (u = x) & (dir = Enter) OR (u > x) & (dir = Exit)
	END PointInside;
	
	(** return whether (non_empty) rectangle is completely inside (non_empty) region **)
	PROCEDURE RectInside* (llx, lly, urx, ury: INTEGER; reg: Region): BOOLEAN;
		VAR data: RegionData; n: LONGINT; u, v, dir, y: INTEGER;
	BEGIN
		IF ~RectInRect(llx, lly, urx, ury, reg.llx, reg.lly, reg.urx, reg.ury) THEN	(* not even within bounding rectangle *)
			RETURN FALSE
		ELSIF IsRect(reg) THEN	(* region is rectangular *)
			RETURN TRUE
		END;
		
		data := reg.data;
		FindLower(reg, lly, n);
		Decode(data[n], u, v, dir);
		REPEAT
			y := v;
			WHILE (v = y) & (u <= llx) DO
				INC(n);
				Decode(data[n], u, v, dir)
			END;
			IF (v > y) OR (u < urx) OR (dir = Enter) THEN	(* rectangle not covered by span *)
				RETURN FALSE
			END;
			
			(* skip to next line *)
			WHILE v = y DO
				INC(n);
				Decode(data[n], u, v, dir)
			END
		UNTIL v >= ury;
		
		RETURN TRUE	(* rectangle is fully covered by spans *)
	END RectInside;
	
	(** return whether (non_empty) rectangle overlaps (non_empty) region **)
	PROCEDURE RectOverlaps* (llx, lly, urx, ury: INTEGER; reg: Region): BOOLEAN;
		VAR data: RegionData; n: LONGINT; u, v, dir, y: INTEGER;
	BEGIN
		IF ~RectsIntersect(llx, lly, urx, ury, reg.llx, reg.lly, reg.urx, reg.ury) THEN
			RETURN FALSE	(* rect does not even intersect region rectangle *)
		ELSIF IsRect(reg) THEN	(* region is rectangular *)
			RETURN TRUE
		END;
		
		ClipRect(llx, lly, urx, ury, reg.llx, reg.lly, reg.urx, reg.ury);
		data := reg.data;
		FindLower(reg, lly, n);
		Decode(data[n], u, v, dir);
		REPEAT
			y := v;
			WHILE (v = y) & (u <= llx) DO
				INC(n);
				Decode(data[n], u, v, dir)
			END;
			IF (v = y) & ((u < urx) OR (dir = Exit)) THEN
				RETURN TRUE
			END;
			
			(* skip to next line *)
			WHILE v = y DO
				INC(n);
				Decode(data[n], u, v, dir)
			END
		UNTIL v >= ury;
		
		RETURN FALSE	(* rectangle does not intersect any span *)
	END RectOverlaps;
	
	(** return whether region is completely within another region **)
	PROCEDURE RegionInside* (inner, outer: Region): BOOLEAN;
		VAR idata, odata: RegionData; in, on, is, os: LONGINT; iu, iv, idir, ou, ov, odir, iy, oy: INTEGER;
	BEGIN
		IF ~RectInRect(inner.llx, inner.lly, inner.urx, inner.ury, outer.llx, outer.lly, outer.urx, outer.ury) THEN
			RETURN FALSE	(* inner rect not even within outer rect *)
		ELSIF IsRect(outer) THEN
			RETURN TRUE	(* outer region fully covers inner region *)
		ELSIF IsRect(inner) THEN
			RETURN RectInside(inner.llx, inner.lly, inner.urx, inner.ury, outer)
		END;
		
		idata := inner.data; odata := outer.data;
		in := FirstSlice;
		FindLower(outer, inner.lly, on);
		Decode(idata[in], iu, iv, idir);
		Decode(odata[on], ou, ov, odir);
		is := in; os := on;
		REPEAT
			iy := iv; oy := ov;
			
			(* skip empty slices *)
			WHILE (iv = iy) & (iu = UBound) DO
				INC(in);
				Decode(idata[in], iu, iv, idir)
			END;
			
			(* compare slices *)
			WHILE (iv = iy) OR (ov = oy) DO
				IF (ov > oy) OR (iv = iy) & (idir = Exit) & (odir = Enter) THEN
					RETURN FALSE
				END;
				IF (iv > iy) OR (ou <= iu) THEN
					INC(on);
					Decode(odata[on], ou, ov, odir)
				ELSE
					INC(in);
					Decode(idata[in], iu, iv, idir)
				END
			END;
			
			(* reset to begin of slice if not on same line *)
			IF iv > ov THEN
				in := is; os := on;
				Decode(idata[in], iu, iv, idir)
			ELSIF ov > iv THEN
				on := os; is := in;
				Decode(odata[on], ou, ov, odir)
			ELSE
				is := in; os := on
			END
		UNTIL iv = inner.ury;
		
		RETURN TRUE	(* all spans were covered by enclosing region *)
	END RegionInside;
	
	(** return whether two regions intersect each other **)
	PROCEDURE RegionOverlaps* (reg, arg: Region): BOOLEAN;
		VAR rdata, adata: RegionData; bot, top, ru, rv, rdir, au, av, adir, ry, ay: INTEGER; rn, an, rs, as: LONGINT;
	BEGIN
		IF ~RectsIntersect(reg.llx, reg.lly, reg.urx, reg.ury, arg.llx, arg.lly, arg.urx, arg.ury) THEN
			RETURN FALSE	(* rect does not even intersect arg's bounding box *)
		ELSIF IsRect(reg) THEN
			RETURN RectOverlaps(reg.llx, reg.lly, reg.urx, reg.ury, arg)
		ELSIF IsRect(arg) THEN
			RETURN RectOverlaps(arg.llx, arg.lly, arg.urx, arg.ury, reg)
		END;
		
		rdata := reg.data; adata := arg.data;
		bot := Max(reg.lly, arg.lly);
		top := Min(reg.ury, arg.ury);
		FindLower(reg, bot, rn);
		FindLower(arg, bot, an);
		Decode(rdata[rn], ru, rv, rdir);
		Decode(adata[an], au, av, adir);
		rs := rn; as := an;
		REPEAT
			ry := rv; ay := av;
			
			(* compare slices *)
			WHILE (rv = ry) OR (av = ay) DO
				IF (rv = ry) & (av = ay) & (rdir = Exit) & (adir = Exit) THEN
					RETURN TRUE
				END;
				IF (av > ay) OR (rv = ry) & (ru <= au) THEN
					INC(rn);
					Decode(rdata[rn], ru, rv, rdir)
				ELSE
					INC(an);
					Decode(adata[an], au, av, adir)
				END
			END;
			
			(* reset to begin of line if not on same line *)
			IF rv > av THEN
				rn := rs; as := an;
				Decode(rdata[rn], ru, rv, rdir)
			ELSIF av > rv THEN
				an := as; rs := rn;
				Decode(adata[an], au, av, adir)
			ELSE
				rs := rn; as := an
			END
		UNTIL (rv = top) OR (av = top);
		
		RETURN FALSE	(* no pair of spans intersected *)
	END RegionOverlaps;
	
	(** enumerate region within rectangle **)
	PROCEDURE Enumerate* (reg: Region; llx, lly, urx, ury: INTEGER; enum: Enumerator; VAR edata: EnumData);
	BEGIN
		IF RectsIntersect(reg.llx, reg.lly, reg.urx, reg.ury, llx, lly, urx, ury) THEN
			ClipRect(llx, lly, urx, ury, reg.llx, reg.lly, reg.urx, reg.ury);
			IF ~RectEmpty(llx, lly, urx, ury) THEN
				IF IsRect(reg) THEN
					enum(llx, lly, urx, ury, edata)
				ELSE
					Enum(reg, llx, lly, urx, ury, enum, edata, Enter)
				END
			END
		END
	END Enumerate;
	
	(** enumerate parts of rectangle not within region **)
	PROCEDURE EnumerateInv* (reg: Region; llx, lly, urx, ury: INTEGER; enum: Enumerator; VAR edata: EnumData);
	BEGIN
		IF RectsIntersect(reg.llx, reg.lly, reg.urx, reg.ury, llx, lly, urx, ury) THEN
			IF IsRect(reg) & RectInRect(reg.llx, reg.lly, reg.urx, reg.ury, llx, lly, urx, ury) THEN
				IF lly < reg.lly THEN enum(llx, lly, urx, reg.lly, edata) END;
				IF llx < reg.llx THEN enum(llx, reg.lly, reg.llx, reg.ury, edata) END;
				IF urx > reg.urx THEN enum(reg.urx, reg.lly, urx, reg.ury, edata) END;
				IF ury > reg.ury THEN enum(llx, reg.ury, urx, ury, edata) END
			ELSE
				Enum(reg, llx, lly, urx, ury, enum, edata, Exit)
			END
		ELSE
			enum(llx, lly, urx, ury, edata)
		END
	END EnumerateInv;
	
	
	(**--- Region Construction ---**)
	
	(** make region empty **)
	PROCEDURE Clear* (reg: Region);
	BEGIN
		reg.llx := UBound; reg.lly := UBound;
		reg.urx := LBound; reg.ury := LBound;
		reg.valid := TRUE;
		reg.points := 0
	END Clear;
	
	(** set region mode **)
	PROCEDURE SetMode* (reg: Region; mode: INTEGER);
	BEGIN
		reg.mode := mode
	END SetMode;
	
	(** initialize region **)
	PROCEDURE Init* (reg: Region; mode: INTEGER);
	BEGIN
		reg.mode := mode;
		reg.data := NIL;
		Clear(reg)
	END Init;
	
	(** make region rectangular **)
	PROCEDURE SetToRect* (reg: Region; llx, lly, urx, ury: INTEGER);
	BEGIN
		IF RectEmpty(llx, lly, urx, ury) THEN
			Clear(reg)
		ELSE
			ClipRect(llx, lly, urx, ury, LBound, LBound, UBound, UBound);
			reg.llx := llx; reg.lly := lly; reg.urx := urx; reg.ury := ury;
			reg.valid := TRUE;
			reg.points := 0
		END
	END SetToRect;
	
	(** shift region **)
	PROCEDURE Shift* (reg: Region; dx, dy: INTEGER);
		VAR rdata: RegionData; rn: LONGINT; ru, rv, rdir: INTEGER;
	BEGIN
		IF (dx # 0) OR (dy # 0) THEN
			INC(reg.llx, dx); INC(reg.lly, dy); INC(reg.urx, dx); INC(reg.ury, dy);
			IF reg.points > 0 THEN
				rdata := reg.data; rn := FirstSlice;
				Decode(rdata[rn], ru, rv, rdir);
				WHILE rv < Top DO
					IF (ru <= LBound) OR (ru + dx <= LBound) THEN ru := LBound
					ELSIF (ru >= UBound) OR (ru + dx >= UBound) THEN ru := UBound
					ELSE INC(ru, dx)
					END;
					IF (dy < 0) & (rv < Bottom - dy) THEN rv := Bottom
					ELSIF (dy > 0) & (rv > Top - dy) THEN rv := Top
					ELSE INC(rv, dy)
					END;
					Encode(rdata[rn], ru, rv, rdir);
					INC(rn);
					Decode(rdata[rn], ru, rv, rdir)
				END
			END
		END
	END Shift;
	
	(** copy region **)
	PROCEDURE Copy* (from, to: Region);
	BEGIN
		to.mode := from.mode;
		CopyData(from, to)
	END Copy;
	
	(** add second region to first **)
	PROCEDURE Add* (reg, arg: Region);
		VAR rdata, adata: RegionData; points, aslice, an, rn, rslice: LONGINT; au, av, adir, ru, rv, rdir, top, ry, ay, y: INTEGER;
	BEGIN
		IF ~RectEmpty(arg.llx, arg.lly, arg.urx, arg.ury) THEN
			IF RectEmpty(reg.llx, reg.lly, reg.urx, reg.ury) THEN
				CopyData(arg, reg)
			ELSIF IsRect(arg) & RectInside(arg.llx, arg.lly, arg.urx, arg.ury, reg) THEN
				(* do nothing *)
			ELSIF IsRect(reg) & RectInside(reg.llx, reg.lly, reg.urx, reg.ury, arg) THEN
				CopyData(arg, reg)
			ELSE
				Validate(reg); Validate(arg);
				MakeData(reg); MakeData(arg);
				rdata := reg.data; adata := arg.data;
				points := reg.points;
				
				IF arg.lly < reg.lly THEN
					(* copy scanlines below reg *)
					FindUpper(arg, reg.lly, aslice);
					an := FirstSlice;
					WHILE an < aslice DO
						Decode(adata[an], au, av, adir);
						Append(reg, au, av, adir);
						INC(an)
					END;
					rn := FirstSlice;
					FindLower(arg, reg.lly, an)
				ELSE
					FindLower(reg, arg.lly, rn);
					an := FirstSlice
				END;
				
				Decode(rdata[rn], ru, rv, rdir);
				Decode(adata[an], au, av, adir);
				rslice := rn; aslice := an;
				top := Min(reg.ury, arg.ury);
				
				WHILE (av < top) OR (rv < top) DO
					(* merge slices *)
					ry := rv; ay := av; y := Max(ry, ay);
					REPEAT
						IF (av > ay) OR (rv = ry) & (ru <= au) THEN
							IF rv # y THEN	(* do not duplicate points *)
								Append(reg, ru, y, rdir)
							END;
							INC(rn);
							Decode(rdata[rn], ru, rv, rdir)
						ELSE
							Append(reg, au, y, adir);
							INC(an);
							Decode(adata[an], au, av, adir)
						END
					UNTIL (rv > ry) & (av > ay);
					
					(* advance to next slice *)
					IF rv < av THEN
						an := aslice; rslice := rn;
						Decode(adata[an], au, av, adir)
					ELSIF av < rv THEN
						rn := rslice; aslice := an;
						Decode(rdata[rn], ru, rv, rdir)
					ELSE
						rslice := rn; aslice := an
					END
				END;
				
				(* copy slices above reg *)
				IF arg.ury > reg.ury THEN
					REPEAT
						Append(reg, au, av, adir);
						INC(an);
						Decode(adata[an], au, av, adir)
					UNTIL av = Top
				END;
				
				Merge(reg, points);
				IncludeRect(reg.llx, reg.lly, reg.urx, reg.ury, arg.llx, arg.lly, arg.urx, arg.ury)
			END
		END
	END Add;
	
	(** add rectangle to region **)
	PROCEDURE AddRect* (reg: Region; llx, lly, urx, ury: INTEGER);
	BEGIN
		SetToRect(RectRegion, llx, lly, urx, ury);
		Add(reg, RectRegion)
	END AddRect;
	
	(** subtract second region from first **)
	PROCEDURE Subtract* (reg, arg: Region);
		VAR rdata, adata: RegionData; points, rn, an, rslice, aslice: LONGINT; ru, rv, rdir, au, av, adir, top, ry, ay, y: INTEGER;
	BEGIN
		IF ~RectEmpty(arg.llx, arg.lly, arg.urx, arg.ury) THEN
			IF RectEmpty(reg.llx, reg.lly, reg.urx, reg.ury) OR RegionInside(reg, arg) THEN
				Clear(reg)
			ELSIF RectsIntersect(reg.llx, reg.lly, reg.urx, reg.ury, arg.llx, arg.lly, arg.urx, arg.ury) THEN
				Validate(reg); Validate(arg);
				MakeData(reg); MakeData(arg);
				rdata := reg.data; adata := arg.data;
				points := reg.points;
				IF reg.lly <= arg.lly THEN
					FindLower(reg, arg.lly, rn);
					an := FirstSlice
				ELSE
					rn := FirstSlice;
					FindLower(arg, reg.lly, an)
				END;
				Decode(rdata[rn], ru, rv, rdir);
				Decode(adata[an], au, av, adir);
				
				rslice := rn; aslice := an;
				top := Min(reg.ury, arg.ury);
				WHILE (rv < top) OR (av < top) DO
					(* merge slices *)
					ry := rv; ay := av; y := Max(ry, ay);
					REPEAT
						IF (av > ay) OR (rv = ry) & (ru <= au) THEN
							IF rv # y THEN	(* do not duplicate points *)
								Append(reg, ru, y, rdir)
							END;
							INC(rn);
							Decode(rdata[rn], ru, rv, rdir)
						ELSE
							Append(reg, au, y, -adir);
							INC(an);
							Decode(adata[an], au, av, adir)
						END
					UNTIL (rv > ry) & (av > ay);
					
					(* advance to next slice *)
					IF rv < av THEN
						an := aslice; rslice := rn;
						Decode(adata[an], au, av, adir)
					ELSIF av < rv THEN
						rn := rslice; aslice := an;
						Decode(rdata[rn], ru, rv, rdir)
					ELSE
						rslice := rn; aslice := an
					END
				END;
				
				Merge(reg, points);
				CalcRect(reg)
			END
		END
	END Subtract;
	
	(** subtract rectangle from region **)
	PROCEDURE SubtractRect* (reg: Region; llx, lly, urx, ury: INTEGER);
	BEGIN
		SetToRect(RectRegion, llx, lly, urx, ury);
		Subtract(reg, RectRegion)
	END SubtractRect;
	
	(** intersect first region with second region **)
	PROCEDURE Intersect* (reg, arg: Region);
		VAR rdata, adata: RegionData; points, rn, an, rslice, aslice: LONGINT; ru, rv, rdir, au, av, adir, ry, ay, y: INTEGER;
	BEGIN
		IF ~RectsIntersect(reg.llx, reg.lly, reg.urx, reg.ury, arg.llx, arg.lly, arg.urx, arg.ury) THEN
			Clear(reg)
		
		ELSIF ~RectInside(reg.llx, reg.lly, reg.urx, reg.ury, arg) THEN
			Validate(reg); Validate(arg);
			MakeData(reg); MakeData(arg);
			rdata := reg.data; adata := arg.data;
			points := reg.points;
			
			(* cut off slices above arg *)
			IF reg.ury > arg.ury THEN
				FindUpper(reg, arg.ury, points);
				Encode(rdata[points], UBound, arg.ury, Enter); INC(points);
				Encode(rdata[points], UBound, arg.ury, Exit); INC(points);
				Encode(rdata[points], UBound, Top, Exit); INC(points);
				reg.points := points
			END;
			
			(* delete slices below arg *)
			IF reg.lly < arg.lly THEN
				FindLower(reg, arg.lly, rn);
				IF rn > FirstSlice THEN
					points := FirstSlice;
					WHILE rn < reg.points DO
						rdata[points] := rdata[rn];
						INC(points); INC(rn)
					END;
					reg.points := points
				END;
				
				rn := FirstSlice;
				Decode(rdata[rn], ru, rv, rdir);
				ry := rv;
				REPEAT
					Encode(rdata[rn], ru, arg.lly, rdir);
					INC(rn);
					Decode(rdata[rn], ru, rv, rdir)
				UNTIL rv > ry;
				
				rn := FirstSlice; an := FirstSlice
			ELSE
				rn := FirstSlice;
				FindLower(arg, reg.lly, an)
			END;
			
			Decode(rdata[rn], ru, rv, rdir);
			Decode(adata[an], au, av, adir);
			rslice := rn; aslice := an;
			
			WHILE rv < reg.ury DO
				(* merge intersecting slices *)
				ry := rv; ay := av; y := Max(ry, ay);
				Append(reg, LBound, y, Exit);
				REPEAT
					IF (av > ay) OR (rv = ry) & (ru <= au) THEN
						IF rv # y THEN	(* do not duplicate existing points *)
							Append(reg, ru, y, rdir)
						END;
						INC(rn);
						Decode(rdata[rn], ru, rv, rdir)
					ELSE
						Append(reg, au, y, adir);
						INC(an);
						Decode(adata[an], au, av, adir)
					END
				UNTIL (rv > ry) & (av > ay);
				Append(reg, UBound, y, Enter);
				
				(* advance to next slice *)
				IF rv < av THEN
					an := aslice; rslice := rn;
					Decode(adata[an], au, av, adir)
				ELSIF av < rv THEN
					rn := rslice; aslice := an;
					Decode(rdata[rn], ru, rv, rdir)
				ELSE
					rslice := rn; aslice := an
				END
			END;
			
			Merge(reg, points);
			CalcRect(reg)
		END
	END Intersect;
	
	(** intersect region with rectangle **)
	PROCEDURE IntersectRect* (reg: Region; llx, lly, urx, ury: INTEGER);
	BEGIN
		SetToRect(RectRegion, llx, lly, urx, ury);
		Intersect(reg, RectRegion)
	END IntersectRect;
	
	(** invert region **)
	PROCEDURE Invert* (reg: Region);
		VAR data: RegionData; points, n: LONGINT; u, v, dir, y: INTEGER;
	BEGIN
		IF RectEmpty(reg.llx, reg.lly, reg.urx, reg.ury) THEN
			SetToRect(reg, LBound, LBound, UBound, UBound)
		ELSE
			Validate(reg);
			MakeData(reg);
			data := reg.data;
			points := reg.points;
			n := FirstSlice;
			Decode(data[n], u, v, dir);
			
			IF reg.lly > LBound THEN
				Append(reg, LBound, LBound, Enter);
				Append(reg, UBound, LBound, Exit)
			END;
			
			REPEAT
				y := v;
				Append(reg, LBound, y, Enter);
				REPEAT
					Encode(data[n], u, y, -dir);
					INC(n);
					Decode(data[n], u, y, dir)
				UNTIL v > y;
				Append(reg, UBound, y, Exit)
			UNTIL v >= UBound;
			
			IF y < UBound THEN
				Append(reg, LBound, y, Enter);
				Append(reg, UBound, y, Exit)
			END;
			
			Merge(reg, points);
			CalcRect(reg)
		END
	END Invert;
	
	(**
		In addition to creating rectangular regions and using Boolean operations to combine several regions, a region
		can also be built by tracing its outline with AddPoint. In order to allow the correct handling of self_intersecting
		contours, a direction parameter is needed which indicates whether the curve is going up (dy = 1) or down
		(dy = -1) at the given point.
		
		When performing Boolean operations upon regions or when building regions from self_intersecting contours,
		it is possible that some areas in the resulting region get "covered" more than once. Since most query operations
		reduce regions to non_overlapping areas, a rule which decides whether a point is inside a region or not is needed.
		Imagine a ray originating at such a point and counting every intersection of the ray with the boundary curve of the
		region as +1 if the curve crosses the ray from right to left and as -1 otherwise.
			- for mode Winding (the default), a point is inside the region if the resulting sum is non_zero
			- for mode EvenOdd, a point is inside the region if the resulting sum is odd
	
		Behaviour of all region queries and region operations is undefined for contours which are not closed.
	**)
	
	(** add a scanline intersection to a region **)
	PROCEDURE AddPoint* (reg: Region; x, y, dy: INTEGER);
	BEGIN
		IF (dy # 0) & (y >= LBound) & (y <= UBound) THEN
			IF x < LBound THEN x := LBound
			ELSIF x > UBound THEN x := UBound
			END;
			MakeData(reg);
			IncludePoint(reg.llx, reg.lly, reg.urx, reg.ury, x, y);
			Append(reg, x, y + (-dy) DIV 2, dy);	(* dy = -1 => y, dy = 1 => y - 1 *)
			reg.valid := FALSE
		END
	END AddPoint;
	

BEGIN
	NEW(RectRegion);
	Init(RectRegion, Winding)
END GfxRegions.
