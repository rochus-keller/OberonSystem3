(* ETH Oberon, Copyright 1990-2003 Computer Systems Institute, ETH Zurich, CH-8092 Zurich.
Refer to the license.txt file provided with this distribution. *)

MODULE DisplayLinear;	(* pjm *)

(*
Linear framebuffer display driver for Aos. 

Refresh rate setting taken from Peter Ryser's Native Oberon VESA driver.

Config strings:
	Display="Displays."	Generic Oberon display driver
	DDriver="DisplayLinear"	This driver
	DMem=?	Display memory size in bytes (optional)
	
	DMode=105H	Vesa mode (only depths 8, 16 (565), 24 and 32 supported)
	DRefresh=?	Vertical refresh rate in Hz (VESA >= 3.0 only)
		or
	DWidth=1024	Display width
	DHeight=768	Display height
	DDepth=16	Display depth
	Init=?	Init program

The Init program is a 8086 machine code program in hexadecimal.  It has to initialize the specified display mode, possibly by making display BIOS calls, and leave the 32-bit physical address of the frame buffer in DX:CX.
*)

IMPORT SYSTEM, Kernel, Files, MathL, V86, Displays, CLUTs;

CONST
	PalFile = "Displays.Pal";	(* physical palette for 8-bit modes - if missing, use default direct mapping *)

	GTFLockVF = 1;		(* Lock to vertical frequency				*)
	GTFLockHF = 2;		(* Lock to horizontal frequency			*)
	GTFLockPF = 3;		(* Lock to pixel clock frequency			*)
	
TYPE
	GTFConstants = RECORD
		margin: LONGREAL;	(* Margin size as percentage of display *)
		cellGran: LONGREAL;	(* Character cell granularity *)
		minPorch: LONGREAL;	(* Minimum front porch in lines/chars *)
		vSyncRqd: LONGREAL;	(* Width of V sync in lines *)
		hSync: LONGREAL;	(* Width of H sync as percent of total *)
		minVSyncBP: LONGREAL;	(* Minimum vertical sync + back porch (us) *)
		m: LONGREAL;	(* Blanking formula gradient *)
		c: LONGREAL;	(* Blanking formula offset *)
		k: LONGREAL;	(* Blanking formula scaling factor *)
		j: LONGREAL	(* Blanking formula scaling factor weight *)
	END;
	
	GTFHCRTC = RECORD
		hTotal: LONGINT;	(* Horizontal total *)
		hDisp: LONGINT;	(* Horizontal displayed *)
		hSyncStart: LONGINT;	(* Horizontal sync start *)
		hSyncEnd: LONGINT;	(* Horizontal sync end *)
		hFrontPorch: LONGINT;	(* Horizontal front porch *)
		hSyncWidth: LONGINT;	(* Horizontal sync width *)
		hBackPorch: LONGINT	(* Horizontal back porch *)
	END;

	GTFVCRTC = RECORD
		vTotal: LONGINT;	(* Vertical total *)
		vDisp: LONGINT;	(* Vertical displayed *)
		vSyncStart: LONGINT;	(* Vertical sync start *)
		vSyncEnd: LONGINT;	(* Vertical sync end *)
		vFrontPorch: LONGINT;	(* Vertical front porch *)
		vSyncWidth: LONGINT;	(* Vertical sync width *)
		vBackPorch: LONGINT	(* Vertical back porch *)
	END;
	
	GTFTimings = RECORD
		h: GTFHCRTC;	(* Horizontal CRTC paremeters *)
		v: GTFVCRTC;	(* Vertical CRTC parameters *)
		hSyncPol: CHAR;	(* Horizontal sync polarity *)
		vSyncPol: CHAR;	(* Vertical sync polarity *)
		interlace: CHAR;	(* 'I' for Interlace, 'N' for Non *)
		vFreq: LONGREAL;	(* Vertical frequency (Hz) *)
		hFreq: LONGREAL;	(* Horizontal frequency (KHz) *)
		dotClock: LONGREAL	(* Pixel clock (Mhz) *)
	END;

VAR
	display: Display;

TYPE
	Display = OBJECT (Displays.Display)
		VAR clut: POINTER TO CLUTs.CLUT;
		
		PROCEDURE ColorToIndex*(col: LONGINT): LONGINT;
		BEGIN
			IF (format = Displays.index8) & (clut # NIL) THEN
				IF 30 IN SYSTEM.VAL(SET, col) THEN	(* invert *)
					col := CLUTs.Match(clut^, col);
					IF col # 0 THEN RETURN col ELSE RETURN 15 END
				ELSE
					RETURN CLUTs.Match(clut^, col)
				END
			ELSE
				RETURN ColorToIndex^(col)
			END
		END ColorToIndex;
		
		PROCEDURE IndexToColor*(index: LONGINT): LONGINT;
		VAR col: LONGINT;
		BEGIN
			IF (format = Displays.index8) & (clut # NIL) THEN
				CLUTs.Get(clut^, index, col);
				RETURN col MOD 1000000H
			ELSE
				RETURN IndexToColor^(index)
			END
		END IndexToColor;
		
	END Display;
	
(* StrToInt - Convert a string to an integer. *)

PROCEDURE StrToInt(VAR i: LONGINT;  VAR s: ARRAY OF CHAR): LONGINT;
	VAR vd, vh, sgn, d: LONGINT;  hex: BOOLEAN;
BEGIN
	vd := 0;  vh := 0;  hex := FALSE;
	IF s[i] = "-" THEN sgn := -1; INC(i) ELSE sgn := 1 END;
	LOOP
		IF (s[i] >= "0") & (s[i] <= "9") THEN d := ORD(s[i])-ORD("0")
		ELSIF (CAP(s[i]) >= "A") & (CAP(s[i]) <= "F") THEN d := ORD(CAP(s[i]))-ORD("A")+10; hex := TRUE
		ELSE EXIT
		END;
		vd := 10*vd + d;  vh := 16*vh + d;
		INC(i)
	END;
	IF CAP(s[i]) = "H" THEN hex := TRUE; INC(i) END;	(* optional H *)
	IF hex THEN vd := vh END;
	RETURN sgn * vd
END StrToInt;

PROCEDURE GetVal(name: ARRAY OF CHAR;  default: LONGINT): LONGINT;
VAR v: LONGINT;  s: ARRAY 12 OF CHAR;  p: LONGINT;
BEGIN
	Kernel.GetConfig(name, s);
	IF s[0] = 0X THEN
		v := default
	ELSE
		p := 0;  v := StrToInt(p, s)
	END;
	RETURN v
END GetVal;

PROCEDURE Install*;
BEGIN
	IF display # NIL THEN Displays.main := display END
END Install;

PROCEDURE InitPalette(d: Display);
CONST N = 256;
VAR i, col: LONGINT; f: Files.File; r: Files.Rider; ch: CHAR;
BEGIN
	f := Files.Old(PalFile);
	IF f # NIL THEN
		NEW(d.clut);
		Files.Set(r, f, 0);
		CLUTs.Read(r, d.clut^, N);
		CLUTs.Init(d.clut^, N, 6)
	ELSE
		d.clut := NIL
	END;
	SYSTEM.PORTIN(3DAH, ch);
	SYSTEM.PORTOUT(3C0H, 11X);
	SYSTEM.PORTOUT(3C0H, 0X);	(* palette entry 0 is black *)
	SYSTEM.PORTOUT(3C0H, 20X);
	FOR i := 0 TO 255 DO
		col := d.IndexToColor(i);
		SYSTEM.PORTOUT(3C8H, CHR(i));
		SYSTEM.PORTOUT(3C9H, CHR(ASH(col, -16) MOD 100H DIV 4));
		SYSTEM.PORTOUT(3C9H, CHR(ASH(col, -8) MOD 100H DIV 4));
		SYSTEM.PORTOUT(3C9H, CHR(col MOD 100H DIV 4))
	END
END InitPalette;

PROCEDURE pow(x: LONGREAL; n: LONGINT): LONGREAL;
VAR s: LONGREAL;
BEGIN
	s := 1;
	WHILE n > 0 DO s := s * x; DEC(n) END;
	RETURN s
END pow;

PROCEDURE Round(v: LONGREAL): LONGREAL;
BEGIN
	RETURN ENTIER(v + 0.5)
END Round;

PROCEDURE GetInternalConstants(VAR c: GTFConstants);
VAR GC: GTFConstants;
BEGIN
	GC.margin := 1.8; GC.cellGran := 8; GC.minPorch := 1; GC.vSyncRqd := 3;
	GC.hSync := 8; GC.minVSyncBP := 550; GC.m := 600; GC.c := 40; GC.k := 128; GC.j := 20;
	
	c.margin := GC.margin; c.cellGran := Round(GC.cellGran);
	c.minPorch := Round(GC.minPorch); c.vSyncRqd := Round(GC.vSyncRqd);
	c.hSync := GC.hSync; c.minVSyncBP := GC.minVSyncBP;
	IF GC.k = 0 THEN c.k := 0.001 ELSE c.k := GC.k END;
	c.m := (c.k / 256) * GC.m; c.c := (GC.c - GC.j) * (c.k / 256) + GC.j;
	c.j := GC.j
END GetInternalConstants;

(*
Calculate a set of GTF timing parameters given a specified resolution and vertical frequency. The horizontal frequency and dot clock will be automatically generated by this routines.

For interlaced modes the CRTC parameters are calculated for a single field, so will be half what would be used in a non-interlaced mode.

hPixels - X resolution
vLines - Y resolution
freq - Frequency (Hz, KHz or MHz depending on type)
type - 1 - vertical, 2 - horizontal, 3 - dot clock
margins - True if margins should be generated
interlace - True if interlaced timings to be generated
t - Place to store the resulting timings
*)

PROCEDURE GTFCalcTimings(hPixels, vLines, freq: LONGREAL; type: LONGINT; wantMargins, wantInterlace: BOOLEAN; VAR t: GTFTimings);
VAR
	interlace,vFieldRate,hPeriod: LONGREAL;
	topMarginLines,botMarginLines: LONGREAL;
	leftMarginPixels,rightMarginPixels: LONGREAL;
	hPeriodEst,vSyncBP,vBackPorch: LONGREAL;
	vTotalLines,vFieldRateEst: LONGREAL;
	hTotalPixels,hTotalActivePixels,hBlankPixels: LONGREAL;
	idealDutyCycle,hSyncWidth,hSyncBP,hBackPorch: LONGREAL;
	idealHPeriod: LONGREAL;
	vFreq,hFreq,dotClock: LONGREAL;
	c: GTFConstants;
BEGIN
	GetInternalConstants(c);
	vFreq := freq; hFreq := freq; dotClock := freq;

	(* Round pixels to character cell granularity *)
	hPixels := Round(hPixels / c.cellGran) * c.cellGran;

	(* For interlaced mode halve the vertical parameters, and double the required field refresh rate. *)
	IF wantInterlace THEN
		vLines := Round(vLines / 2);
		vFieldRate := vFreq * 2;
		dotClock := dotClock * 2;
		interlace := 0.5;
	ELSE vFieldRate := vFreq; interlace := 0
	END;

	(* Determine the lines for margins *)
	IF wantMargins THEN
		topMarginLines := Round(c.margin / 100 * vLines);
		botMarginLines := Round(c.margin / 100 * vLines)
	ELSE topMarginLines := 0; botMarginLines := 0
	END;

	IF type # GTFLockPF THEN
		IF type = GTFLockVF THEN
			(* Estimate the horizontal period *)
			hPeriodEst := ((1/vFieldRate)-(c.minVSyncBP/1000000))/
					(vLines+(2*topMarginLines)+c.minPorch+interlace)*1000000;

			(* Find the number of lines in vSync + back porch *)
			vSyncBP := Round(c.minVSyncBP / hPeriodEst);
		ELSIF type = GTFLockHF THEN
			(* Find the number of lines in vSync + back porch *)
			vSyncBP := Round((c.minVSyncBP * hFreq) / 1000);
		END;

		(* Find the number of lines in the V back porch alone *)
		vBackPorch := vSyncBP - c.vSyncRqd;

		(* Find the total number of lines in the vertical period *)
		vTotalLines := vLines + topMarginLines + botMarginLines + vSyncBP
				+ interlace + c.minPorch;

		IF type = GTFLockVF THEN
			(* Estimate the vertical frequency *)
			vFieldRateEst := 1000000 / (hPeriodEst * vTotalLines);

			(* Find the actual horizontal period *)
			hPeriod := (hPeriodEst * vFieldRateEst) / vFieldRate;

			(* Find the actual vertical field frequency *)
			vFieldRate := 1000000 / (hPeriod * vTotalLines);
		ELSIF type = GTFLockHF THEN
			(* Find the actual vertical field frequency *)
			vFieldRate := (hFreq / vTotalLines) * 1000;
		END
	END;

	(* Find the number of pixels in the left and right margins *)
	IF wantMargins THEN
		leftMarginPixels := Round(hPixels * c.margin) / (100 * c.cellGran);
		rightMarginPixels := Round(hPixels * c.margin) / (100 * c.cellGran);
	ELSE leftMarginPixels := 0; rightMarginPixels := 0
	END;

	(* Find the total number of active pixels in image + margins *)
	hTotalActivePixels := hPixels + leftMarginPixels + rightMarginPixels;

	IF type = GTFLockVF THEN
		(* Find the ideal blanking duty cycle *)
		idealDutyCycle := c.c - ((c.m * hPeriod) / 1000)
	ELSIF type = GTFLockHF THEN
		(* Find the ideal blanking duty cycle *)
		idealDutyCycle := c.c - (c.m / hFreq);
	ELSIF type = GTFLockPF THEN
		(* Find ideal horizontal period from blanking duty cycle formula *)
		idealHPeriod := (((c.c - 100) + (MathL.sqrt((pow(100-c.c,2)) +
			(0.4 * c.m * (hTotalActivePixels + rightMarginPixels +
			leftMarginPixels) / dotClock)))) / (2 * c.m)) * 1000;

		(* Find the ideal blanking duty cycle *)
		idealDutyCycle := c.c - ((c.m * idealHPeriod) / 1000);
	END;

	(* Find the number of pixels in blanking time *)
	hBlankPixels := Round((hTotalActivePixels * idealDutyCycle) /
		((100 - idealDutyCycle) * c.cellGran)) * c.cellGran;

	(* Find the total number of pixels *)
	hTotalPixels := hTotalActivePixels + hBlankPixels;

	(* Find the horizontal back porch *)
	hBackPorch := Round((hBlankPixels / 2) / c.cellGran) * c.cellGran;

	(* Find the horizontal sync width *)
	hSyncWidth := Round(((c.hSync/100) * hTotalPixels) / c.cellGran) * c.cellGran;

	(* Find the horizontal sync + back porch *)
	hSyncBP := hBackPorch + hSyncWidth;

	IF type = GTFLockPF THEN
		(* Find the horizontal frequency *)
		hFreq := (dotClock / hTotalPixels) * 1000;

		(* Find the number of lines in vSync + back porch *)
		vSyncBP := Round((c.minVSyncBP * hFreq) / 1000);

		(* Find the number of lines in the V back porch alone *)
		vBackPorch := vSyncBP - c.vSyncRqd;

		(* Find the total number of lines in the vertical period *)
		vTotalLines := vLines + topMarginLines + botMarginLines + vSyncBP
			+ interlace + c.minPorch;

		(* Find the actual vertical field frequency *)
		vFieldRate := (hFreq / vTotalLines) * 1000;
	ELSE
		IF type = GTFLockVF THEN
			(* Find the horizontal frequency *)
			hFreq := 1000 / hPeriod;
		ELSIF type = GTFLockHF THEN
			(* Find the horizontal frequency *)
			hPeriod := 1000 / hFreq;
		END;

		(* Find the pixel clock frequency *)
		dotClock := hTotalPixels / hPeriod;
	END;

	(* Find the vertical frame frequency *)
	IF wantInterlace THEN vFreq := vFieldRate / 2; dotClock := dotClock / 2;
	ELSE vFreq := vFieldRate
	END;

	(* Return the computed frequencies *)
	t.vFreq := vFreq;
	t.hFreq := hFreq;
	t.dotClock := dotClock;

	(* Determine the vertical timing parameters *)
	t.h.hTotal := ENTIER(hTotalPixels);
	t.h.hDisp := ENTIER(hTotalActivePixels);
	t.h.hSyncStart := ENTIER(t.h.hTotal - hSyncBP);
	t.h.hSyncEnd := ENTIER(t.h.hTotal - hBackPorch);
	t.h.hFrontPorch := t.h.hSyncStart - t.h.hDisp;
	t.h.hSyncWidth := ENTIER(hSyncWidth);
	t.h.hBackPorch := ENTIER(hBackPorch);

	(* Determine the vertical timing parameters *)
	t.v.vTotal := ENTIER(vTotalLines);
	t.v.vDisp := ENTIER(vLines);
	t.v.vSyncStart := ENTIER(t.v.vTotal - vSyncBP);
	t.v.vSyncEnd := ENTIER(t.v.vTotal - vBackPorch);
	t.v.vFrontPorch := t.v.vSyncStart - t.v.vDisp;
	t.v.vSyncWidth := ENTIER(c.vSyncRqd);
	t.v.vBackPorch := ENTIER(vBackPorch);

	(* Mark as GTF timing using the sync polarities *)
	IF wantInterlace THEN t.interlace := 'I' ELSE t.interlace := 'N' END;
	t.hSyncPol := '-';
	t.vSyncPol := '+'
END GTFCalcTimings;

PROCEDURE SetVesaMode(mode, hz: LONGINT; VAR w, h, d, adr: LONGINT);
VAR width, height, ver: INTEGER; flags: SET; bpp: SHORTINT; reg: V86.Regs; t: GTFTimings;
BEGIN
	V86.Init;
	ASSERT(V86.bufsize >= 512);	(* enough for VESA *)

	SYSTEM.MOVE(SYSTEM.ADR("VBE2"), V86.bufadr, 4);
	reg.EAX := 4F00H;	(* get VESA info *)
	reg.ES := V86.bufadr DIV 16;
	reg.EDI := V86.bufadr MOD 16;
	V86.Video(reg);
	ASSERT(reg.EAX MOD 10000H = 4FH, 100);	(* vesa call ok *)
	SYSTEM.GET(V86.bufadr+4, ver);	(* version *)

	SYSTEM.MOVE(SYSTEM.ADR("VBE2"), V86.bufadr, 4);
	reg.EAX := 4F01H;	(* get mode info *)
	reg.ECX := mode;
	reg.ES := V86.bufadr DIV 16;
	reg.EDI := V86.bufadr MOD 16;
	V86.Video(reg);
	ASSERT(reg.EAX MOD 10000H = 4FH, 101);	(* vesa call ok *)
	
	SYSTEM.GET(V86.bufadr+12H, width);
	SYSTEM.GET(V86.bufadr+14H, height);
	SYSTEM.GET(V86.bufadr+19H, bpp);
	SYSTEM.GET(V86.bufadr+28H, adr);
	IF bpp = 15 THEN bpp := 16 END;	(* 15bpp not really supported currently *)
	w := width; h := height; d := bpp;
	ASSERT((adr # 0) & (adr MOD 4096 = 0), 102);	(* frame buffer address ok *)
	
	IF (ver >= 300H) & (hz > 0) THEN
		GTFCalcTimings(w, h, hz, GTFLockVF, FALSE, FALSE, t);
		reg.EAX := 4F0BH; reg.EBX := 0; reg.EDX := mode;
		reg.ECX := hz * t.h.hTotal * t.v.vTotal;
		V86.Video(reg);
		ASSERT(reg.EAX MOD 10000H = 4FH, 104);	(* vesa call ok *)
		
		SYSTEM.PUT(V86.bufadr, SYSTEM.VAL(INTEGER, t.h.hTotal));
		SYSTEM.PUT(V86.bufadr+2, SYSTEM.VAL(INTEGER, t.h.hSyncStart));
		SYSTEM.PUT(V86.bufadr+4, SYSTEM.VAL(INTEGER, t.h.hSyncEnd));
		SYSTEM.PUT(V86.bufadr+6, SYSTEM.VAL(INTEGER, t.v.vTotal));
		SYSTEM.PUT(V86.bufadr+8, SYSTEM.VAL(INTEGER, t.v.vSyncStart));
		SYSTEM.PUT(V86.bufadr+10, SYSTEM.VAL(INTEGER, t.v.vSyncEnd));
		flags := {};
		IF t.interlace = "I" THEN INCL(flags, 1) END;
		IF t.hSyncPol = "-" THEN INCL(flags, 2) END;
		IF t.vSyncPol = "-" THEN INCL(flags, 3) END;
		SYSTEM.PUT(V86.bufadr+12, SYSTEM.VAL(CHAR, flags));
		SYSTEM.PUT(V86.bufadr+13, reg.ECX);
		SYSTEM.PUT(V86.bufadr+17, SYSTEM.VAL(INTEGER, SHORT(hz*100)));
		reg.EBX := 800H
	ELSE
		reg.EBX := 0
	END;
	
	reg.EAX := 4F02H; 	(* set mode *)
	reg.EBX := reg.EBX + mode + 4000H;	(* enable linear fb *)
	reg.ES := V86.bufadr DIV 16;
	reg.EDI := V86.bufadr MOD 16;
	V86.Video(reg);
	ASSERT(reg.EAX MOD 10000H = 4FH, 103);	(* vesa call ok *)
	
	Kernel.traceConsole := FALSE;
	V86.Cleanup
END SetVesaMode;

PROCEDURE Init;
VAR w, h, d, f, mem, adr, vmode: LONGINT;
BEGIN
	vmode := GetVal("DMode", 0);
	IF vmode # 0 THEN	(* attempt V86 call to VESA BIOS *)
		SetVesaMode(vmode, GetVal("DRefresh", 0), w, h, d, adr)
	ELSE	(* assume mode was set with Init= *)
		w := GetVal("DWidth", 1024);
		h := GetVal("DHeight", 768);
		d := GetVal("DDepth", 16);
		Kernel.GetInit(1, adr);	(* DX:CX from Init code *)
		ASSERT((adr # 0) & (adr MOD 4096 = 0))
	END;
	
	CASE d DIV 8 OF
		1: f := Displays.index8
		|2: f := Displays.color565
		|3: f := Displays.color888
		|4: f := Displays.color8888
	END;
	
	mem := GetVal("DMem", 0)*1024;
	IF mem = 0 THEN mem := w*h*f END;
	Kernel.MapPhysical(adr, mem + (-mem) MOD 4096, adr);
	
	NEW(display);
	display.width := w; display.height := h;
	display.offscreen := mem DIV (w*f) - h;
	display.format := f; display.unit := 10000;
	
	IF f = Displays.index8 THEN InitPalette(display) END;
	
	display.InitFrameBuffer(adr, mem)
END Init;

BEGIN
	Init; Install
END DisplayLinear.

