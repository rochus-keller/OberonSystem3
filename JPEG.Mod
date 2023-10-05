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

(* 
	J P E G														David Ulrich, Juni 1995 
	
	JPEG Konvertierungsprogramm: JPEG --> Oberon Picture Format
	
	
	Diese Software basiert auf JPEG Software der "Independent JPEG Group"
	
	12.12.95 / tk	bit ordering problem eliminated
*)

MODULE JPEG;	(** portable *)

IMPORT 
	F:=Files, T:=Texts, P:=Pictures, D:=Display, BIT, Files, Oberon, Objects, Pictures;
	
CONST
(* set this constants befor compiling *)
	AnzResFarben = 20;	(* unchangeable colors (0 .. AnzResFarben-1) *)
	
	AnzFarben = 256 - AnzResFarben;
	
	ColorsOld* = 0;		(* Alte, vorhandene Farbtabelle benuetzen *)
	ColorsNew* = 1;	   (* Neue orthogonale Farbtabelle erstellen *)
	
	DitherNone* = 0;	(* Kein Dithering *)
	DitherFS* = 1;		 (* Floyd-Steinberg Dithering *)
	
	Float* = 0;				(* Floating-Point IDCT *)
	Integer* = 1;			 (* Integer IDCT *)
	Scale* = 2;				(* Integer IDCT mit ScalingFaktoren 2,4 und 8 *)


	DCTSIZE = 8;
	DCTSIZE2 = 64;
	NUMQUANTTBLS = 4;
	NUMHUFFTBLS = 4;
	NUMARITHTBLS = 16;
	MAXCOMPSINSCAN = 4;
	MAXSAMPFACTOR = 4;
	MAXBLOCKSINMCU = 10;
	BITSINJSAMPLE = 8;
	MAXCOMPONENTS = 4;  (* nach JFIF bis 10 *)
	MAXJSAMPLE = 255;
	CENTERJSAMPLE = 128;
	JPEGMAXDIMENSION = 1024;  (* nach JFIF bis 65500 *)
	MAXQCOMPS = 4;
	HUFFLOOKAHEAD = 8;
	MINGETBITS = 25;
	
	JPEGHEADEROK = 0;
	JPEGHEADERTABLESONLY = 1;
	JPEGSUSPENDED = 2;
	
	JCSUNKNOWN = 0;
	JCSGRAYSCALE = 1;
	JCSRGB = 2;
	JCSYCBCR = 3;
	JCSCMYK = 4;
	JCSYCCK =5;
	
	JPEGEOI = 0D9X;
	JPEGFF = 0FFX;
	
	DSTATESTART = 200;
	DSTATEINHEADER = 201;
	DSTATEREADY = 202;
	DSTATESCANNING = 203;
	DSTATERAWOK = 204;
	DSTATESTOPPING = 205;
	
	RGBRED = 0;
	RGBGREEN = 1;
	RGBBLUE = 2;
	RGBPIXELSIZE = 3;
	
	JBUFPASSTHRU = 1;
	
	(* Konstanten des Mainkontrollers *)
	MainPass = 0;
	PrereadPass = 1;
	OutputPass = 2;
	PostPass = 3;

	(* Konstanten fuers Marker Lesen *)
	MSOF0 = 0C0X;
	MSOF1 = 0C1X;
	MSOF2 = 0C2X;
	MSOF3 = 0C3X;
	MSOF5 = 0C5X;
	MSOF6 = 0C6X;
	MSOF7 = 0C7X;
	MJPG   = 0C8X;
	MSOF9 = 0C9X;
	MSOF10 = 0CAX;
	MSOF11 = 0CBX;
	MSOF13 = 0CDX;
	MSOF14 = 0CEX;
	MSOF15 = 0CFX;
	
	MDHT  = 0C4X;
	MDAC  = 0CCX;
	MRST0 = 0D0X;
	MRST1 = 0D1X;
	MRST2 = 0D2X;
	MRST3 = 0D3X;
	MRST4 = 0D4X;
	MRST5 = 0D5X;
	MRST6 = 0D6X;
	MRST7 = 0D7X;
	
	MSOI = 0D8X;
	MEOI = 0D9X;
	MSOS = 0DAX;
	MDQT = 0DBX;
	MDNL = 0DCX;
	MDRI = 0DDX;
	
	MAPP0 = 0E0X;
	MAPP1 = 0E1X;
	MAPP2 = 0E2X;
	MAPP3 = 0E3X;
	MAPP4 = 0E4X;
	MAPP5 = 0E5X;
	MAPP6 = 0E6X;
	MAPP7 = 0E7X;
	MAPP8 = 0E8X;
	MAPP9 = 0E9X;
	MAPP10 = 0EAX;
	MAPP11 = 0EBX;
	MAPP12 = 0ECX;
	MAPP13 = 0EDX;
	MAPP14 = 0EEX;
	MAPP15 = 0EFX;
	
	MCOM = 0FEX;
	MTEM = 001X;
	
	Max = 0FFFFFH;
	
TYPE

	CInfoPtr = POINTER TO CInfoDesc;

	SrcPtr = POINTER TO SrcDesc;
	SrcDesc = RECORD
			startOfFile: BOOLEAN;
			rider: F.Rider;
			file: F.File;
	END;
	
	JSampRow = POINTER TO ARRAY (JPEGMAXDIMENSION * RGBPIXELSIZE) OF CHAR;
	
	JSampArray = POINTER TO JSADesc;
	JSADesc = RECORD
		row: ARRAY (BITSINJSAMPLE * MAXSAMPFACTOR) OF JSampRow;
	END;
	
	JSampImage = POINTER TO JSIDesc;
	JSIDesc = RECORD
		comp: ARRAY MAXCOMPONENTS OF JSampArray;
	END;
	
	JBlock = POINTER TO ARRAY DCTSIZE2 OF INTEGER;
	
	DCTTablePtr = POINTER TO ARRAY DCTSIZE2 OF REAL;
	DCTITablePtr = POINTER TO ARRAY DCTSIZE2 OF LONGINT;
	DCTSTablePtr = POINTER TO ARRAY DCTSIZE2 OF LONGINT;
	
	JPEGCompInfoPtr = POINTER TO JPEGCompInfoDesc;
	JPEGCompInfoDesc = RECORD
			componentID: INTEGER;			(* ID fuer diesen Komponenten 0..255 *)
			componentIndex: INTEGER;        (* Index in SOF-Marker *)
			hSampFactor: SHORTINT;		    (* Horizontaler Sampling Faktor 1..4 *)
			vSampFactor: SHORTINT;			(* Vertikaler Sampling Faktor 1..4 *)
			quantTblNo: INTEGER;			   (* Nummer der Quantisierungstabelle 0..3 *)
			dcTblNo: SHORTINT;				  (* Nummer der DC Entropy Tabelle 0..3 *)
			acTblNo: SHORTINT;				  (* Nummer der AC Entropy Tabelle 0..3 *)
			widthInBlocks: LONGINT;		   (* Breite in Blocks *)
			heightInBlocks: LONGINT;		  (* Hoehe in Blocks *)
			DCTScaledSize: INTEGER;			 (* Groesse eines DCT Blocks in Samples *)
			downSampledWidth: LONGINT;	(* aktuelle Breite in Samples *)
			downSampledHeight: LONGINT;    (* aktuelle Hoehe in Samples *)
			componentNeeded: BOOLEAN;      (* Brauchen wir den Wert dieses Farbkomponenten ? *)
			MCUWidth: INTEGER;     			(* # Bloecke per MCU, horizontal *)
			MCUHeight: INTEGER; 				(* # Bloecke per MCU, vertikal *)
			MCUBlocks: INTEGER; 				(* MCUWidth * MCUHeight *)
			MCUSampleWidth: INTEGER;		(* MCUWidth in Samples *)
			lastColWidth: INTEGER;			   (* # von nicht Dummy Blocks in der letzten MCU Zeile *)
			lastRowHeight: INTEGER;			 (* # von nicht Dummy Blocks in der letzten MCU Reihe *)
			dctTable: DCTTablePtr;				 (* Zeiger auf die DCTTabelle bei IDCTFLOAT *)
			dctITable: DCTITablePtr;			   (* Zeiger auf die DCTTabelle bei IDCTINT *)
			dctSTable: DCTSTablePtr;			  (* Zeiger auf die DCTTabelle bei IDCTSCALE *)
			IDCTMethod: PROCEDURE(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	END;
	
	FSErrPtr = POINTER TO ARRAY (JPEGMAXDIMENSION + 2) OF INTEGER;
	
	ColIndexPtr = POINTER TO ColIndex;
	ColIndex = ARRAY 3, (MAXJSAMPLE + 1) OF INTEGER;
	
	MarkerPtr = POINTER TO MarkerDesc;
	MarkerDesc = RECORD
			sawSOI: BOOLEAN;
			sawSOF: BOOLEAN;
			nextRestartNum: INTEGER;	(* Nummer des naechsten Restart Intervalls *)
			discardedBytes: INTEGER;	  (* Anzahl ueberlesener Bytes *)
	END;
	
	MasterPtr = POINTER TO MasterDesc;
	MasterDesc = RECORD
			usingMergedUpsample: BOOLEAN;	(* im Moment nur FALSE implementiert *)
			passType: SHORTINT;					 (* in welchem Pass sind wir? *)
			passNumber: INTEGER;				  (* der wievielte Pass ist es ? *)
			totalPasses: INTEGER;					 (* Totale Anzahl Passe *)
			needPostPass: BOOLEAN;				(* Braucht es eine Nachbearbeitung: nur FALSE *)
			isLastPass: BOOLEAN;					(* ist es der letzte Pass? *)
			eoiProcessed: BOOLEAN;				 (* EOI schon erreicht *)
	END;
	
	JHuffTblPtr = POINTER TO JHuffTbl;			(* Huffman Tabelle *)
	JHuffTbl = RECORD
			bits: ARRAY 17 OF INTEGER;
			huffVal: ARRAY 256 OF INTEGER;
	END;
	
	JQuantTblPtr = POINTER TO JQuantTbl;		(* Quantisierungs Tabelle *)
	JQuantTbl = RECORD
			quantVal: ARRAY DCTSIZE2 OF LONGINT;
	END;
	
	SavableState = RECORD							  (* Status beim Entropy Dekodieren *)
			getBuffer : LONGINT;
			bitsLeft: INTEGER;
			lastDcVal: ARRAY MAXCOMPSINSCAN OF INTEGER;
	END;
	
	WorkingStatePtr = POINTER TO WorkingState;
	WorkingState = RECORD
			unreadMarker: CHAR;
			cur: SavableState;
			cInfo: CInfoPtr;
	END;
	
	DDerivedTblPtr = POINTER TO DDerivedTbl;
	DDerivedTbl = RECORD
			mincode: ARRAY 17 OF LONGINT;
			maxcode: ARRAY 18 OF LONGINT;
			valptr: ARRAY 17 OF INTEGER;
			pub: JHuffTblPtr;
			lookNBits: ARRAY 256 OF INTEGER;
			lookSym: ARRAY 256 OF INTEGER;
	END;
	
	EntropyPtr = POINTER TO EntropyDesc;
	EntropyDesc = RECORD
			saved: SavableState;
			restartsToGo: INTEGER;
			printedEod: BOOLEAN;
			dcDerivedTbls: ARRAY NUMHUFFTBLS OF DDerivedTblPtr;
			acDerivedTbls: ARRAY NUMHUFFTBLS OF DDerivedTblPtr;
	END;
	
	DestPtr = POINTER TO DestDesc;
	DestDesc = RECORD
			buffer : JSampArray;				(* Zwischenspeicher: mehere Zeilen *)
			bufferHeight: LONGINT;
			pict: P.Picture;
			curOutputRow: LONGINT;
			padBytes: INTEGER;				(* # padding Bytes pro Zeile *)
			rowWidth: LONGINT;			 (* Zeilen Breite mit Padding *)
			dataWidth: LONGINT;	         (* Zeilen Breite ohne Padding *)
			colors: ARRAY 256 OF INTEGER;
	END;
	
	CQuantPtr = POINTER TO CQuantDesc;
	CQuantDesc = RECORD
			onOddRow: BOOLEAN;
			colorQuantize: PROCEDURE(cInfo:CInfoPtr; inputBuf: JSampArray; 
									outputBuf: JSampArray; outRowCtr: INTEGER; numRows: INTEGER);
			fsErrors: ARRAY MAXQCOMPS OF FSErrPtr;	(* Abweichungstabelle fuer Floyd Steinberg Dithering *)
			colorIndex: ColIndex; 								(* bearbeitender Farbkomponent *)
	END;

	UpsampleProc = PROCEDURE(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
											
	UpsamplePtr = POINTER TO UpsampleDesc;
	UpsampleDesc = RECORD
			needContextRows: BOOLEAN;
			upsample: PROCEDURE(cInfo: CInfoPtr; inputBuf: JSampImage; VAR inRowGroupCtr: LONGINT;
											inRowGroupsAvail: LONGINT; outputBuf: JSampArray; 
											VAR outRowCtr: LONGINT; outRowsAvail: LONGINT);
			colorBuf: ARRAY MAXCOMPONENTS OF JSampArray;	(* Zwischenspeicher *)
			nextRowOut: INTEGER;
			rowsToGo: LONGINT;
			rowGroupHeight: ARRAY MAXCOMPONENTS OF INTEGER;  (* Anzahl Zeilen pro Groupe *)
			hExpand: ARRAY MAXCOMPONENTS OF INTEGER;			(* Pixel Expansionsfaktoren horizontal *)
			vExpand: ARRAY MAXCOMPONENTS OF INTEGER;			(* Pixel Expansionsfaktoren vertikal *)
			methods: ARRAY MAXCOMPONENTS OF UpsampleProc;	 (* geeigente Upsampling Routine *)
	END;
	
	MainPtr = POINTER TO MainDesc;
	MainDesc = RECORD
			numChunks :LONGINT; 	(* # Chunks die pro Pass gemacht werden muessen *)
			buffer: JSampImage;		  (* Zwischenspeicher *)
			bufferFull: BOOLEAN;		(* Zwischenspeicher gefuellt ? *)
			rowGroupCtr: LONGINT;	(* Zaehler fuer die Zeilengruppen*)
			processData: PROCEDURE(cInfo:CInfoPtr; outputBuf:JSampArray;
												VAR outRowCtr:LONGINT; outRowsAvail:LONGINT);
	END;

	CoefPtr = POINTER TO CoefDesc;
	CoefDesc = RECORD
			decompressData: PROCEDURE(cInfo:CInfoPtr;outputBuf:JSampImage):BOOLEAN;
			MCUColNum: LONGINT;	(* aktuelle Kolonne *)
			MCURowNum: LONGINT;  (* aktuelle Zeile *)
			MCUBuffer: ARRAY MAXBLOCKSINMCU OF JBlock;	(* Zwischenspeicher *)
			wholeImage: BOOLEAN;	 (* ganzes Bild zwischenspeichern? FALSE *)
	END;
	
	PostPtr = POINTER TO PostDesc;
	PostDesc = RECORD
			postProcessData: PROCEDURE(cInfo:CInfoPtr; inputBuf:JSampImage; 
													VAR inRowGroupCtr, inRowGroupsAvail: LONGINT;
													outputBuf: JSampArray; VAR outRowCtr: LONGINT;
													VAR outRowsAvail: LONGINT);
			buffer: JSampArray;			 (* Zwischenspeicher *)
			stripHeight: LONGINT;		(* # moegliche Zeilen im Zwischenspeicher *)
			wholeImage: BOOLEAN;	  (* ganzes Bild zwischenspeichern? FALSE *) 
	END;
	
	CConvertPtr = POINTER TO CConvertDesc;
	CConvertDesc = RECORD
			colorConvert: PROCEDURE(cInfo:CInfoPtr; inputBuf:ARRAY OF JSampArray;
												inputRow: LONGINT; outputBuf:JSampArray;
												outRowCtr: LONGINT; numRows:INTEGER);
	END;
	
	CInfoDesc = RECORD
			globalState: INTEGER; 		  		(* Globaler Status der Dekomprimierung *)
			imageWidth: LONGINT;				(* nominale Bildbreite, aus SOF Marker *)
			imageHeight: LONGINT;				(* nominale Bildhoehe, aus SOF Marker *)
			numComponents: SHORTINT;	 	(* Anzahl Farbkomponenten des Bildes *)
			selectIDCT: SHORTINT;			  	(* gewuenschte IDCT Routine *)
			jpegColorSpace: INTEGER;		 	 (* Farbformat des JPEG Bildes *)
			outColorSpace: INTEGER;		   	(* gewuenschtes Farbformat des Output *)
			scaleNum, scaleDenom: INTEGER;   (* im Moment nicht implementiert *)
			outputGamma: LONGREAL;	   	(* im Moment nicht implementiert *)
			rawDataOut: BOOLEAN;				(* rawDataOut=TRUE -> nicht sinnvoll *)
			doFancyUpsampling :BOOLEAN; 	(* TRUE -> Fancy Upsampling anwenden *)
			sawJFIFMarker: BOOLEAN;			(* Kontoll-Flag *)
			sawAdobeMarker: BOOLEAN;	 	(* Kontoll-Flag *)
			AdobeTransform: INTEGER;		   (* Farb Transformations Code des Adobe Markers *)
			compInfo: ARRAY MAXCOMPONENTS OF JPEGCompInfoPtr; (* Pointer auf Farbkomponenten *)
			unreadMarker: CHAR;					(* angetroffener aber noch nicht bearbeiteter Marker *)
			restartInterval: LONGINT;			   (* MCUs per Restart interval, oder 0 fuer kein Restart *)
			arithDcL: ARRAY NUMARITHTBLS OF INTEGER;	(*L Werte fuer DC arith.coding Tabellen *)
			arithDcU: ARRAY NUMARITHTBLS OF INTEGER;	(*U Werte fuer DC arith.coding Tabellen *)
			arithAcK: ARRAY NUMARITHTBLS OF INTEGER;	(*Kx Werte fuer AC arith.coding Tabellen *)
			arithCode: BOOLEAN;					(* TRUE= arith. Kodierung, FALSE=Huffman Kodierung *)
			CCIR601Sampling: BOOLEAN;	 	(* TRUE=first samples are cosited, nicht implementiert *)
			densityUnit: INTEGER;				   (* JFIF Code fuer die Pixeleinheiten *)
			XDensity, YDensity: LONGINT;	 	(* Horizontale, Vertikale Aufloesung *)
			dataPrecision: SHORTINT;			   (* Bildgenauigkeit *)
			compsInScan: SHORTINT;			   (* Anzahl Farbkomponenten im JPEG File *)
			curCompInfo: ARRAY MAXCOMPSINSCAN OF JPEGCompInfoPtr;	(*Farbkomponente an i.ter Stelle in SOS*)
			dcHuffTbl: ARRAY NUMHUFFTBLS OF JHuffTblPtr;    	(* Zeiger auf Huffman Tabellen *)
			acHuffTbl: ARRAY NUMHUFFTBLS OF JHuffTblPtr;    	(* Zeiger auf Huffman Tabellen *)
			quantTbl: ARRAY NUMQUANTTBLS OF JQuantTblPtr; 	(* Zeiger auf Quantisierungs Tabellen *)
			outputWidth: LONGINT;				(* Breite des Output Bildes *)			
			outputHeight: LONGINT;				(* Hoehe des Output Bildes *)
			outputScanline: LONGINT;			  (* 0 .. outputHeight -1 *)
			totaliMCURows: LONGINT;			 (* # iMCU Zeilen, JPEGCoef *)
			MCUsPerRow: LONGINT;			   (* # MCU in einer Zeile *)
			MCURowsInScan: LONGINT;		   (* # MCU Zeilen im Bild *)
			outColorComponents: INTEGER;	  (* # Farbkomponenten im Output File *)
			outputComponents: INTEGER;         (* # Farbkomponenten die Ausgegeben werden *)
			maxHSampFactor: INTEGER;		   (* groesster HSampFactor *)
			maxVSampFactor: INTEGER;			(* groesster VSampFactor *)
			recOutbufHeight: INTEGER;			 (* Minimale Hoehe des Scanline Buffers *)
			blocksInMCU: INTEGER;				 (* # DCT Bloecke in einer MCU *)
			MCUMembership: ARRAY MAXBLOCKSINMCU OF INTEGER; (* Farbkomponentenzugehoerigkeit *)
			twoPassQuantize: BOOLEAN;           (* nur FALSE implementiert *)
			ditherMode: SHORTINT;				  (* gewuenschtes Dithering Verfahrens *)
			desiredNumberOfColors: INTEGER;	(* gewuenschte Anzahl Farben im Output *)
			actualNumberOfColors: INTEGER;	 (* berechnete Anzahl Farben im Output *)
			minDCTScaledSize: INTEGER;			(* kleinste DCTScaledSize fuer jeden Farbkomponenten *)
			colorMap: ColIndexPtr;					(* Zeiger auf die Farbtabelle *)
			colorMode: INTEGER;					(* Alte ode neue Farbtabelle ? *)
			post: PostPtr;								(* Zeiger auf das Postkontroller Objekt *)
			coef: CoefPtr;								(* Zeiger auf den Koeffizientenkontroller *)
			cconvert: CConvertPtr;					 (* Zeiger auf das ColorConvert Objekt *)
			cquant: CQuantPtr;						 (* Zeiger auf das ColorQuantisierungs Objekt *)
			upsample: UpsamplePtr;				  (* Zeiger auf das Upsample Objekt *)
			entropy: EntropyPtr;						(* Zeiger auf das Entropy Objekt (Huffman) *)
			src: SrcPtr;									(* Zeiger auf das src Objekt *)
			marker: MarkerPtr;						 (* Zeiger auf das Markerleser Objekt *)
			master: MasterPtr;						  (* Zeiger auf das Masterkontroll Objekt *)
			main: MainPtr;							   (* Zeiger auf das Mainkontroll Objekt *)
	END;
	
VAR
	W: T.Writer;
	ZAG: ARRAY (DCTSIZE2 + 16) OF SHORTINT;
	ZIG : ARRAY DCTSIZE2 OF SHORTINT;
	RL: ARRAY 1024 OF INTEGER;
	i,x: INTEGER;
	crRTab,cbBTab: ARRAY 257 OF INTEGER;
	crGTab,cbGTab: ARRAY 257 OF LONGINT;
	fix14,fix17,fix07,fix03: LONGINT;
	extendTest: ARRAY 16 OF INTEGER;
	extendOff: ARRAY 16 OF INTEGER;
	dots: POINTER TO ARRAY OF INTEGER;
	err: INTEGER;
	
	PROCEDURE ^ Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);

(* *****     Start Data Source Proceduren      ***** *)

	(* Auf Input File positionieren *)
	PROCEDURE initSource(cInfo: CInfoPtr);
	BEGIN
		cInfo.src.startOfFile := TRUE;
		F.Set(cInfo.src.rider,cInfo.src.file,0);
	END initSource;
	
	(* numBytes Daten auf InputFile ueberspringen *)
	PROCEDURE skipInputData(cInfo: CInfoPtr; numBytes:LONGINT);
	VAR
		pos: LONGINT;
	BEGIN
		IF numBytes > 0 THEN
			pos:=F.Pos(cInfo.src.rider);
			F.Set(cInfo.src.rider,cInfo.src.file,pos + numBytes);
		END;
	END skipInputData;
	
	(* Initialisieren des Leseobjektes *)
	PROCEDURE jpegInitSrc(cInfo: CInfoPtr; file:F.File);
	BEGIN
		IF cInfo.src = NIL THEN NEW(cInfo.src) END;
		cInfo.src.file:=file;
	END jpegInitSrc;
	
(* *****     Ende Data Source Proceduren      ***** *)
	
	
(* *****     Start Marker Prozeduren     ***** *)

	PROCEDURE ErrMsg(msg: ARRAY OF CHAR; num: INTEGER);
	BEGIN
		IF err = 0 THEN	(* first error *)
			T.WriteString(W, "JPEG: ");  T.WriteString(W, msg);  T.WriteString(W, " (");  
			T.WriteInt(W, num, 1);  T.Write(W, ")");  T.WriteLn(W);
			T.Append(Oberon.Log,W.buf);
		END;
		err := num
	END ErrMsg;

	(* Fehlerbehandlung wenn File Ende des InputFile erreicht wird *)	
	PROCEDURE fileEnd(cInfo: CInfoPtr);
	VAR
		pos: LONGINT;
	BEGIN
		IF cInfo.src.startOfFile THEN
			ErrMsg("no image data found", 1)
		END;
		pos := F.Pos(cInfo.src.rider);
		F.Write(cInfo.src.rider,JPEGFF);
		F.Write(cInfo.src.rider,JPEGEOI);
		F.Set(cInfo.src.rider,cInfo.src.file,pos);
	END fileEnd;
	
	(* Lesen eines CHAR vom InputFile, 1 Byte *)
	PROCEDURE ReadChar(cInfo: CInfoPtr; VAR char:CHAR):BOOLEAN;
	BEGIN
		F.Read(cInfo.src.rider,char);
		IF ~cInfo.src.rider.eof THEN
			cInfo.src.startOfFile:=FALSE;
			RETURN TRUE;
		ELSE
			fileEnd(cInfo);
			RETURN FALSE;
		END;
	END ReadChar;

	(* Lesen eines SHORTINT vom InputFile, 1 Byte *)
	PROCEDURE ReadShort(cInfo: CInfoPtr; VAR short:SHORTINT):BOOLEAN;
	BEGIN
		F.Read(cInfo.src.rider,short);
		IF ~cInfo.src.rider.eof THEN
			cInfo.src.startOfFile:=FALSE;
			RETURN TRUE;
		ELSE
			fileEnd(cInfo);
			RETURN FALSE;
		END;
	END ReadShort;
	
	(* Lesen eines INTEGER vom InputFile, 2 Byte  *)
	PROCEDURE ReadInt(cInfo: CInfoPtr; VAR int:INTEGER):BOOLEAN;
	BEGIN
		F.ReadInt(cInfo.src.rider, int);
		int := BIT.ISWAP(int);
		IF ~cInfo.src.rider.eof THEN
			cInfo.src.startOfFile:= FALSE;
			RETURN TRUE;
		ELSE
			fileEnd(cInfo);
			RETURN FALSE;
		END;
	END ReadInt;
	
	(* Lesen eines unsigned INTEGER vom InputFile, 1 Byte  *)
	PROCEDURE ReadUINT8(cInfo: CInfoPtr; VAR int:INTEGER):BOOLEAN;
	VAR
		char:CHAR;
	BEGIN
		F.Read(cInfo.src.rider,char);
		IF ~cInfo.src.rider.eof THEN
			int:=ORD(char);
			cInfo.src.startOfFile:=FALSE;
			RETURN TRUE;
		ELSE
			fileEnd(cInfo);
			RETURN FALSE;
		END;
	END ReadUINT8;
	
	(* Lesen eines unsigned LONGINT vom InputFile, 2 Byte  *)
	PROCEDURE ReadUINT16(cInfo: CInfoPtr; VAR long:LONGINT):BOOLEAN;
	VAR
		int1,int0: INTEGER;
		ch: CHAR;
	BEGIN
		F.Read(cInfo.src.rider,ch);
		int1 := ORD(ch);
		F.Read(cInfo.src.rider,ch);
		int0 := ORD(ch);
		long := 256 * LONG(int1) + int0;
		
		IF ~cInfo.src.rider.eof THEN
			cInfo.src.startOfFile:=FALSE;
			RETURN TRUE;
		ELSE
			fileEnd(cInfo);
			RETURN FALSE;
		END;
	END ReadUINT16;
	
	(* Aufteilen eines Bytes in obere und untere 4 Bit *)
	PROCEDURE ByteSplit(int:INTEGER; VAR byte03,byte47:SHORTINT);
	BEGIN
		byte03 := SHORT(int MOD 10H);
		byte47 := SHORT((int DIV 10H) MOD 10H);
	END ByteSplit;
	
	(* Lesen des SOI-Markers vom InputFile: Start der Graphik*)
	PROCEDURE getSOI(cInfo: CInfoPtr):BOOLEAN;
	VAR
		i:INTEGER;
	BEGIN
		IF cInfo.marker.sawSOI THEN HALT(82) END;
		i:=0;
		WHILE i< NUMARITHTBLS DO
			cInfo.arithDcL[i] :=0;
			cInfo.arithDcU[i] :=1;
			cInfo.arithAcK[i] :=5;
			INC(i);
		END;
		cInfo.restartInterval := 0;
		cInfo.jpegColorSpace := JCSUNKNOWN;
		cInfo.CCIR601Sampling := FALSE;
		cInfo.sawJFIFMarker := FALSE;
		cInfo.densityUnit := 0;
		cInfo.XDensity := 1;
		cInfo.YDensity := 1;
		cInfo.sawAdobeMarker := FALSE;
		cInfo.AdobeTransform:=0;
		
		cInfo.marker.sawSOI :=TRUE;
		RETURN TRUE;
	END getSOI;
	
	(* Lesen eines SOF-Markers vom InputFile: Definition der Bilddaten*)
	PROCEDURE getSOF(cInfo: CInfoPtr):BOOLEAN;
	VAR
		c,ci:INTEGER;
		length:INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		IF ~ReadShort(cInfo,cInfo.dataPrecision) THEN RETURN FALSE END;
		IF ~ReadUINT16(cInfo,cInfo.imageHeight) THEN RETURN FALSE END;
		IF ~ReadUINT16(cInfo,cInfo.imageWidth) THEN RETURN FALSE END;
		IF ~ReadShort(cInfo,cInfo.numComponents) THEN RETURN FALSE END;
		DEC(length,8);

		IF cInfo.marker.sawSOF THEN 
			ErrMsg("SOF-block found twice", 2); RETURN FALSE
		END;

		IF (cInfo.imageHeight <=0) 
			OR (cInfo.imageWidth<=0) 
			OR (cInfo.numComponents <=0) 
		THEN
			ErrMsg("bad size", 3)
		END;
		
		IF (cInfo.imageHeight > JPEGMAXDIMENSION) 
			OR (cInfo.imageWidth > JPEGMAXDIMENSION)
		THEN
			ErrMsg("image too large", 4)
		END;
		
		IF cInfo.dataPrecision # BITSINJSAMPLE THEN
			ErrMsg("data-precision # 8", 5)
		END;
		
		IF cInfo.numComponents > MAXCOMPONENTS THEN
			ErrMsg("too many components", 6)
		END;
		
		IF length # (cInfo.numComponents * 3) THEN
			ErrMsg("wrong block length", 7)
		END;
		
		ci:=0;
		WHILE ci < cInfo.numComponents DO
			IF cInfo.compInfo[ci] = NIL THEN NEW(cInfo.compInfo[ci]) END;
			cInfo.compInfo[ci].componentIndex := ci;
			IF ~ReadUINT8(cInfo,cInfo.compInfo[ci].componentID) THEN RETURN FALSE END;
			IF ~ReadUINT8(cInfo,c) THEN RETURN FALSE END;
			ByteSplit(c,cInfo.compInfo[ci].vSampFactor,cInfo.compInfo[ci].hSampFactor);
			IF ~ReadUINT8(cInfo,cInfo.compInfo[ci].quantTblNo) THEN RETURN FALSE END;
			INC(ci);
		END;
		
		cInfo.marker.sawSOF:=TRUE;
		RETURN TRUE;
		
	END getSOF;
	
	(* Lesen eines SOS-Markers vom InputFile: Start of Scan*)
	PROCEDURE getSOS(cInfo: CInfoPtr):BOOLEAN;
	VAR
		c,ci,cc,ccc:INTEGER;
		i,n:SHORTINT;
		length:INTEGER;
		fehler: BOOLEAN;
		compptr: JPEGCompInfoPtr;
	BEGIN
		IF ~cInfo.marker.sawSOF THEN
			ErrMsg("no SOF block found", 8); RETURN FALSE
		END;
		
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		IF ~ReadShort(cInfo,n) THEN RETURN FALSE END;
		IF (length # (n*2 + 6)) OR (n<1) OR (n> MAXCOMPSINSCAN) THEN
			ErrMsg("wrong data length", 9); RETURN FALSE
		END;
		cInfo.compsInScan:=n;
		i:=0;
		WHILE i<n DO
			IF ~ReadUINT8(cInfo,cc) THEN RETURN FALSE END;
			IF ~ReadUINT8(cInfo,c) THEN RETURN FALSE END;
			fehler := TRUE;
			
			ci:=0;
			WHILE (ci < cInfo.numComponents) & fehler DO
				compptr := cInfo.compInfo[ci];
				IF cc = compptr.componentID THEN
					fehler := FALSE;
				END;
				INC(ci);
			END;
			IF fehler THEN
				ErrMsg("wrong ComponentID", 10); RETURN FALSE
			END;
			cInfo.curCompInfo[i]:= compptr;
			ByteSplit(c,compptr.acTblNo,compptr.dcTblNo);
			INC(i);
		END;

		IF ~ReadUINT8(cInfo,c) OR ~ReadUINT8(cInfo,cc) OR ~ReadUINT8(cInfo,ccc)
		THEN 
			RETURN FALSE 
		END;
		IF (c # 0) OR (cc # DCTSIZE2 -1) OR (ccc # 0) THEN
			ErrMsg("JWRN not sequential", 11); RETURN FALSE
		END;
		cInfo.marker.nextRestartNum:=0;
		
		RETURN TRUE;	
	END getSOS;
	
	(* Lesen eines App0-Markers vom InputFile: Block fuer JFIF Kennung *)
	PROCEDURE getApp0(cInfo: CInfoPtr):BOOLEAN;
	VAR
		b : ARRAY 5 OF CHAR;
		length,buffp,version,help:INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		IF length >= 14 THEN
			FOR buffp := 0 TO 4 DO 
				IF ~ReadChar(cInfo,b[buffp]) THEN RETURN FALSE END;
			END;
			IF ~ReadUINT8(cInfo,version) THEN RETURN FALSE END;
			IF ~ReadUINT8(cInfo,help) THEN RETURN FALSE END;
			DEC(length,12);
			IF (b[0] = 4AX) & (b[1] = 46X) & (b[2] = 49X) &  (b[3] = 46X) & (b[4] = 0X) THEN
				IF version # 1 THEN
					ErrMsg("wrong JFIF version", 12); RETURN FALSE
				END;
				cInfo.sawJFIFMarker:=TRUE;
				IF ~ReadUINT8(cInfo,cInfo.densityUnit) THEN RETURN FALSE END;
				IF ~ReadUINT16(cInfo,cInfo.XDensity) THEN RETURN FALSE END;
				IF ~ReadUINT16(cInfo,cInfo.YDensity) THEN RETURN FALSE END;
			END;
		END;
		IF length > 0 THEN skipInputData(cInfo,length) END;
		RETURN TRUE;	
	END getApp0;
	
	(* Lesen eines App14-Markers vom InputFile: Adobe Marker *)
	PROCEDURE getApp14(cInfo: CInfoPtr):BOOLEAN;
	VAR
		b : ARRAY 5 OF CHAR;
		length,dummy,buffp :INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		
		IF length >= 12 THEN
			FOR buffp := 0 TO 4 DO 
				IF ~ReadChar(cInfo,b[buffp]) THEN RETURN FALSE END;
			END;
			IF ~ReadInt(cInfo,dummy) THEN RETURN FALSE END;
			IF ~ReadInt(cInfo,dummy) THEN RETURN FALSE END;
			IF ~ReadInt(cInfo,dummy) THEN RETURN FALSE END;
			IF ~ReadUINT8(cInfo,cInfo.AdobeTransform) THEN RETURN FALSE END;
			DEC(length,12);
			IF (b[0] = 41X) & (b[1] = 64X) & (b[2] = 6FX) &  (b[3] = 62X) & (b[4] = 65X) THEN
				cInfo.sawAdobeMarker:=TRUE;
			ELSE
				ErrMsg("bad Adobe marker", 13); RETURN FALSE
			END;
		ELSE
			ErrMsg("bad Adobe marker", 14); RETURN FALSE
		END;
		IF length > 0 THEN skipInputData(cInfo,length) END;
		
		RETURN TRUE;	
	END getApp14;
	
	(* Lesen eines DAC-Markers vom InputFile: Block fuer Arithmetik Kodierung *)
	PROCEDURE getDAC(cInfo: CInfoPtr):BOOLEAN;
	VAR
		index,help1,help2: SHORTINT;
		length,val :INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		
		WHILE length > 0 DO
			IF ~ReadShort(cInfo,index) THEN RETURN FALSE END;
			IF ~ReadUINT8(cInfo,val) THEN RETURN FALSE END;
			DEC(length,2);
			
			IF (index < 0) OR (index >= (2*NUMARITHTBLS)) THEN
				ErrMsg("bad DAC index", 15); RETURN FALSE
			END;
			
			IF index >= NUMARITHTBLS THEN
				cInfo.arithAcK[index - NUMARITHTBLS] := val;
			ELSE
				ByteSplit(val,help1,help2);
				cInfo.arithDcL[index]:=help1;
				cInfo.arithDcU[index]:=help2;
				IF cInfo.arithDcL[index] > cInfo.arithDcU[index] THEN
					ErrMsg("bad DAC value", 16); RETURN FALSE
				END;
			END;
		END;
		
		RETURN TRUE;	
	END getDAC;
	
	(* Lesen eines DHT-Markers vom InputFile: Block fuer Huffman Kodierung *)
	PROCEDURE getDHT(cInfo: CInfoPtr):BOOLEAN;
	VAR
		bits: ARRAY 17 OF INTEGER;
		huffVal: ARRAY 256 OF INTEGER;
		length,i,index,count :INTEGER;
		htblptr: JHuffTblPtr;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		
		WHILE length > 0 DO
			IF ~ReadUINT8(cInfo,index) THEN RETURN FALSE END;
			bits[0] :=0;
			count:=0;
			FOR i:=1 TO 16 DO
				IF ~ReadUINT8(cInfo,bits[i]) THEN RETURN FALSE END;
				INC(count,bits[i]);
			END;
			DEC(length,17);
			
			IF (count > 256) OR (count > length) THEN
				ErrMsg("bad DHT sum", 17);  RETURN FALSE
			END;
			
			FOR i:=0 TO count -1 DO 
				IF ~ReadUINT8(cInfo,huffVal[i]) THEN RETURN FALSE END;
			END;
			DEC(length,count);
			
			IF index >= NUMARITHTBLS THEN
				DEC(index,NUMARITHTBLS);
				IF cInfo.acHuffTbl[index] = NIL THEN NEW(cInfo.acHuffTbl[index]) END;
				htblptr:= cInfo.acHuffTbl[index];
			ELSE
				IF cInfo.dcHuffTbl[index] = NIL THEN NEW(cInfo.dcHuffTbl[index]) END;
				htblptr:= cInfo.dcHuffTbl[index];
			END;
			
			IF (index < 0) OR (index >= NUMHUFFTBLS) THEN
				ErrMsg("bad DHT index", 18);  RETURN FALSE
			END;
			
			FOR i:=0 TO 16 DO htblptr.bits[i]:=bits[i] END;
			FOR i:=0 TO count -1 DO htblptr.huffVal[i]:=huffVal[i] END;
		END;		
		
		RETURN TRUE;	
	END getDHT;
	
	(* Lesen eines DQT-Markers vom InputFile: Definition der Quantisierungstabellen *)
	PROCEDURE getDQT(cInfo: CInfoPtr):BOOLEAN;
	VAR
		quantptr: JQuantTblPtr;
		length,i,n,tmp :INTEGER;
		prec,index :SHORTINT;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		
		WHILE length > 0 DO
			IF ~ReadUINT8(cInfo,n) THEN RETURN FALSE END;
			ByteSplit(n,index,prec);
			
			IF cInfo.quantTbl[index] = NIL THEN NEW(cInfo.quantTbl[index]) END;
			quantptr:=cInfo.quantTbl[index];
			
			FOR i:=0 TO DCTSIZE2 - 1 DO
				IF prec # 0 THEN
					IF ~ReadUINT16(cInfo,quantptr.quantVal[i]) THEN RETURN FALSE END;
				ELSE
					IF ~ReadUINT8(cInfo,tmp) THEN RETURN FALSE END;
					quantptr.quantVal[i]:=tmp;
				END;
			END;
			
			DEC(length,DCTSIZE2 + 1);
			IF prec # 0 THEN DEC(length,DCTSIZE2) END;
		END;		
		
		RETURN TRUE;	
	END getDQT;
	
	(* Lesen eines DRI-Markers vom InputFile: Definition des Restart Intervalls *)
	PROCEDURE getDRI(cInfo: CInfoPtr):BOOLEAN;
	VAR
		length :INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		IF length # 4 THEN
			ErrMsg("wrong DRI length", 19);  RETURN FALSE
		END;	
		
		IF ~ReadUINT16(cInfo,cInfo.restartInterval) THEN RETURN FALSE END;
			
		RETURN TRUE;	
	END getDRI;

	(* Ueberlesen eines Markers vom InputFile *)
	PROCEDURE skipVariable(cInfo: CInfoPtr):BOOLEAN;
	VAR
		length :INTEGER;
	BEGIN
		IF ~ReadInt(cInfo,length) THEN RETURN FALSE END;
		DEC(length,2);
		
		skipInputData(cInfo,length);
					
		RETURN TRUE;	
	END skipVariable;
	
	(* Auf InputFile bis zum naechsten Marker weiterlesen *)
	PROCEDURE nextMarker(cInfo: CInfoPtr):BOOLEAN;
	VAR
		c:CHAR;
	BEGIN
		LOOP
			IF ~ReadChar(cInfo,c) THEN RETURN FALSE END;
			
			WHILE c # 0FFX DO
				INC(cInfo.marker.discardedBytes);
				IF ~ReadChar(cInfo,c) THEN RETURN FALSE END;
			END;
			
			REPEAT
				IF ~ReadChar(cInfo,c) THEN RETURN FALSE END;
			UNTIL c # 0FFX;
			
			IF c # 0X THEN EXIT END;
			
			INC(cInfo.marker.discardedBytes,2);
		END; (*Loop*)
		
		IF cInfo.marker.discardedBytes # 0 THEN
			(* T.WriteInt(W,cInfo.marker.discardedBytes,10);
			T.WriteString(W,"(nextMarker) bytes discared"); 
			T.WriteLn(W);
			T.Append(Oberon.Log,W.buf); *)
			cInfo.marker.discardedBytes:=0;
		END;
		
		cInfo.unreadMarker := c;
					
		RETURN TRUE;	
	END nextMarker;
	
	(* Erster Marker vom InputFile lesen *)
	PROCEDURE firstMarker(cInfo: CInfoPtr):BOOLEAN;
	VAR
		c,c2:CHAR;
	BEGIN
		IF ~ReadChar(cInfo,c) THEN RETURN FALSE END;
		IF ~ReadChar(cInfo,c2) THEN RETURN FALSE END;
		
		(*IF (c # 0FFX) OR (c2 # MSOI) THEN
			ErrMsg("no MSOI marker", 1); RETURN FALSE
		END;*)
		cInfo.unreadMarker := c2;
					
		RETURN TRUE;	
	END firstMarker;

	(* Steuerung des Lesens der Marker bis und mit SOS-Block oder EOI wenn keine 
		Bilddaten vorhanden sind *)
	PROCEDURE readMarkers(cInfo: CInfoPtr):INTEGER;
	BEGIN
		LOOP
			IF cInfo.unreadMarker = 0X THEN
				IF ~cInfo.marker.sawSOI THEN
					IF ~ firstMarker(cInfo) THEN RETURN JPEGSUSPENDED END;
				ELSE
					IF ~ nextMarker(cInfo) THEN RETURN JPEGSUSPENDED END;
				END;
			END;
			CASE cInfo.unreadMarker OF
				MSOI: 
					IF ~getSOI(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MSOF0: 
					cInfo.arithCode:=FALSE;
					IF ~getSOF(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MSOF1: 
					cInfo.arithCode:=FALSE;
					IF ~getSOF(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MSOF9: 
					cInfo.arithCode:=TRUE;
					IF ~getSOF(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MSOF2:
					ErrMsg("Progressive Huffmann not supported", 20)
			| MSOF3: 
					ErrMsg("Lossless Huffmann not supported", 21)
			| MSOF5: 
					ErrMsg("Differential seq. Huffmann not supported", 22)
			| MSOF6: 
					ErrMsg("Differential prog. Huffmann not supported", 23)
			| MSOF7: 
					ErrMsg("Differential loss. Huffmann not supported", 24)
			| MJPG: 
					ErrMsg("MJPG not supported", 25)
			| MSOF10: 
					ErrMsg("Progressive arithmetic not supported", 26)
			| MSOF11: 
					ErrMsg("Lossless arithmetic not supported", 27)
			| MSOF13: 
					ErrMsg("Differential seq. arithmetic not supported", 28)
			| MSOF14: 
					ErrMsg("Differential prog. arithmetic not supported", 29)
			| MSOF15: 
					ErrMsg("Differential loss. arithmetic not supported", 30)
			| MSOS: 
					IF ~getSOS(cInfo) THEN RETURN JPEGSUSPENDED END;
					cInfo.unreadMarker := 0X;
					RETURN JPEGHEADEROK;
			| MEOI: 
					cInfo.unreadMarker := 0X;
					RETURN JPEGHEADERTABLESONLY;
			| MDAC: 
					IF ~getDAC(cInfo) THEN RETURN JPEGSUSPENDED END
			| MDHT: 
					IF ~getDHT(cInfo) THEN RETURN JPEGSUSPENDED END
			| MDQT: 
					IF ~getDQT(cInfo) THEN RETURN JPEGSUSPENDED END
			| MDRI: 
					IF ~getDRI(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP0: 
					IF ~getApp0(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP1: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP2: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP3: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP4: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP5: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MAPP6: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP7: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP8: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP9: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP10: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP11: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP12: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP13: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP14: 
					IF ~getApp14(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MAPP15: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			| MCOM: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END
			| MRST0: 
					(* nothing to do *)
			| MRST1: 
					(* nothing to do *)
			| MRST2: 
					(* nothing to do *)
			| MRST3: 
					(* nothing to do *)
			| MRST4: 
					(* nothing to do *)
			| MRST5: 
					(* nothing to do *)
			| MRST6: 
					(* nothing to do *)
			| MRST7: 
					(* nothing to do *)
			| MTEM: 
					(* nothing to do *)
			| MDNL: 
					IF ~skipVariable(cInfo) THEN RETURN JPEGSUSPENDED END;
			ELSE
					ErrMsg("unknown marker", 31)
			END;

			cInfo.unreadMarker:=0X;

			IF err # 0 THEN RETURN JPEGSUSPENDED END
		END (* Loop *);	
	END readMarkers;

	(* Lesen eines Restart Markers vom InputFile, falls der Marker nicht vorhanden ist, 
		werden Rettungsmassnahmen zur weiteren Dekodierung getroffen *)
	PROCEDURE resyncToRestart(cInfo: CInfoPtr):BOOLEAN;
	VAR
		marker:CHAR;
		desired,action:INTEGER;
	BEGIN
		action:=1;
		desired := cInfo.marker.nextRestartNum;
		marker := cInfo.unreadMarker;
		LOOP
			IF marker < MSOF0 THEN action:=2
			ELSIF (marker < MRST0) OR (marker > MRST7) THEN action := 3
			ELSE 
				IF (ORD(marker) = (208 + ((desired + 1) MOD 8)))
				OR (ORD(marker) = (208 + ((desired + 2) MOD 8))) THEN action:=3
				ELSIF (ORD(marker) = (208 + ((desired - 1) MOD 8)))
				OR (ORD(marker) = (208 + ((desired - 2) MOD 8))) THEN action:=2
				ELSE action := 1
				END;
			END;
			
			CASE action OF
				1:
					cInfo.unreadMarker := 0X;
					RETURN TRUE;
			|   2:
					IF ~nextMarker(cInfo) THEN RETURN FALSE END;
					marker := cInfo.unreadMarker;
			|   3:
					RETURN TRUE;
			END;
		END; (* Loop *)
	END resyncToRestart;
	
	(* Lesen eines Restart Markers vom InputFile, falls der Marker nicht vorhanden ist, 
		werden Rettungsmassnahmen zur weiteren Dekodierung getroffen *)
	PROCEDURE readRestartMarker(cInfo: CInfoPtr):BOOLEAN;
	BEGIN
		IF cInfo.unreadMarker = 0X THEN
			IF ~nextMarker(cInfo) THEN RETURN FALSE END;
		END;
		
		IF ORD(cInfo.unreadMarker) = (208 + cInfo.marker.nextRestartNum) THEN
			cInfo.unreadMarker:= 0X;
		ELSE
			IF ~resyncToRestart(cInfo) THEN RETURN FALSE END;
		END;
		
		cInfo.marker.nextRestartNum := (cInfo.marker.nextRestartNum + 1) MOD 8;
		
		RETURN TRUE;
	END readRestartMarker;
	
	(* Marker Reader fuer neues InputFile initialisieren *)
	PROCEDURE resetMarkerReader(cInfo: CInfoPtr);
	BEGIN
		cInfo.unreadMarker := 0X;
		cInfo.marker.sawSOI := FALSE;
		cInfo.marker.sawSOF := FALSE;
		cInfo.marker.discardedBytes := 0;
	END resetMarkerReader;
	
	(* Marker Reader anlegen und initialisieren *)
	PROCEDURE jinitMarkerReader(cInfo: CInfoPtr);
	BEGIN
		IF cInfo.marker = NIL THEN NEW(cInfo.marker) END;
		cInfo.unreadMarker := 0X;
		cInfo.marker.sawSOI := FALSE;
		cInfo.marker.sawSOF := FALSE;
		cInfo.marker.discardedBytes := 0
	END  jinitMarkerReader;
	
	(* *****      Ende Proceduren von JPEGMarker      ***** *)
	
	(* ******************************************************** *)
	
	(* *****     Start Prozeduren von JPEGHuff      ***** *)
	(* Dieser Abschnitt beinhaltet Prozeduren fuer die Huffman Entropy Dekodierung *)
	
	(* Berechnen der "Derived Values" fuer die Huffman Tabelle *)
	PROCEDURE fixHuffTbl(cInfo: CInfoPtr;htbl: JHuffTblPtr; pdtbl: DDerivedTblPtr);
	VAR
		p,i,I,si,k: INTEGER;
		lookbits: LONGINT;
		huffsize: ARRAY 257 OF INTEGER;
		huffcode: ARRAY 257 OF LONGINT;
		code,ctr: LONGINT;
	BEGIN
		pdtbl.pub := htbl;
		
		p := 0;
		FOR I := 1 TO 16 DO
			i := 1;
			WHILE i <= htbl.bits[I] DO
				huffsize[p] := I;
				INC(p);
				INC(i);
			END;
		END;
		huffsize[p] := 0;
		
		code := 0;
		si := huffsize[0];
		p:= 0;
		WHILE huffsize[p] # 0 DO
			WHILE huffsize[p] = si DO
				huffcode[p] := code;
				INC(p);
				INC(code);
			END;
			code := code * 2;
			INC(si);
		END;
		
		p := 0;
		FOR I := 1 TO 16 DO
			IF htbl.bits[I] # 0 THEN
				pdtbl.valptr[I] := p;
				pdtbl.mincode[I] := huffcode[p];
				p := htbl.bits[I] + p;
				pdtbl.maxcode[I] := huffcode[p-1];
			ELSE
				pdtbl.maxcode[I] := -1;
			END;
		END;
		pdtbl.maxcode[17] := Max;
		
		FOR p:=0 TO 255 DO pdtbl.lookNBits[p] := 0 END;
		
		p:= 0;
		FOR k:=1 TO HUFFLOOKAHEAD DO
			i:= 1;
			WHILE i<= htbl.bits[k] DO
				lookbits:= ASH(huffcode[p],(HUFFLOOKAHEAD - k));
				ctr := ASH(1,(HUFFLOOKAHEAD - k));
				WHILE ctr > 0 DO
					pdtbl.lookNBits[lookbits] := k;
					pdtbl.lookSym[lookbits] := htbl.huffVal[p];
					INC(lookbits);
					DEC(ctr);
				END;
				INC(p);
				INC(i);
			END;
		END;
	END fixHuffTbl;
	
	(* Initialisierung der Huffman Dekodierung fuer einen Scan Durchgang *)
	PROCEDURE startPassHuff(cInfo: CInfoPtr);
	VAR
		ci,dctbl,actbl: INTEGER;
		compptr: JPEGCompInfoPtr;
	BEGIN
		FOR ci:= 0 TO cInfo.compsInScan - 1 DO
			compptr := cInfo.curCompInfo[ci];
			dctbl := compptr.dcTblNo;
			actbl := compptr.acTblNo;
			IF (dctbl < 0) OR (dctbl >= NUMHUFFTBLS) OR (cInfo.dcHuffTbl[dctbl] = NIL) THEN
				ErrMsg("bad Huffman dc table", 32);  RETURN
			END;
			IF (actbl < 0) OR (actbl >= NUMHUFFTBLS) OR (cInfo.acHuffTbl[actbl] = NIL) THEN
				ErrMsg("bad Huffman ac table", 33);  RETURN
			END;
			IF cInfo.entropy.dcDerivedTbls[dctbl] = NIL THEN 
				NEW(cInfo.entropy.dcDerivedTbls[dctbl]);
			END;
			IF cInfo.entropy.acDerivedTbls[actbl] = NIL THEN 
				NEW(cInfo.entropy.acDerivedTbls[actbl]);
			END;
			fixHuffTbl(cInfo,cInfo.dcHuffTbl[dctbl],cInfo.entropy.dcDerivedTbls[dctbl]);
			fixHuffTbl(cInfo,cInfo.acHuffTbl[actbl],cInfo.entropy.acDerivedTbls[actbl]);
			cInfo.entropy.saved.lastDcVal[ci] := 0;
		END;
		cInfo.entropy.saved.bitsLeft := 0;
		cInfo.entropy.printedEod := FALSE;
		cInfo.entropy.restartsToGo := SHORT(cInfo.restartInterval);
	END startPassHuff;
	
	(* Fuellen des BitBuffers(max. 4Bytes) mit Bytes vom InputFile *)
	PROCEDURE fillBitBuffer(state: WorkingStatePtr; nbits: INTEGER):BOOLEAN;
	VAR
		getBuffer: LONGINT;
		bitsLeft,x,i,k: INTEGER;
		c: CHAR;
	BEGIN
		bitsLeft := state.cur.bitsLeft;
		getBuffer := state.cur.getBuffer;
		
		LOOP
			IF bitsLeft >= MINGETBITS THEN EXIT END;
			IF state.unreadMarker # 0X THEN
				IF bitsLeft >= nbits THEN EXIT END;
				IF ~state.cInfo.entropy.printedEod THEN
					(* T.WriteString(W, "Huff-fillBitBuffer: unexpected marker found"); T.WriteLn(W);
					T.Append(Oberon.Log,W.buf); *)
					state.cInfo.entropy.printedEod := TRUE;
				END;
				c := 0X;
			ELSE
				IF ~ReadChar(state.cInfo,c) THEN RETURN FALSE END;
				IF c = 0FFX THEN
					REPEAT
						IF ~ReadChar(state.cInfo,c) THEN RETURN FALSE END;
					UNTIL c # 0FFX;
					
					IF c = 0X THEN
						c:= 0FFX;
					ELSE
						state.unreadMarker := c;
						IF bitsLeft >= nbits THEN EXIT END;
						IF ~state.cInfo.entropy.printedEod THEN
							(* T.WriteString(W,"Huff-fillBitBuffer: unexpected marker found"); T.WriteLn(W);
							T.Append(Oberon.Log,W.buf); *)
							state.cInfo.entropy.printedEod := TRUE;
						END;
						c := 0X;
					END;
				END;
			END;
			
			getBuffer := BIT.LLSH(getBuffer, 8);
			x := ORD(c);
			k := 128;
			i := 8;
			WHILE i > 0 DO
				DEC(i);
				IF (x DIV k) > 0 THEN 
					BIT.LSETBIT(getBuffer, SHORT(i))
				END;
				x := x MOD k;
				k := k DIV 2;
			END;
			INC(bitsLeft,8);
		END;
		state.cur.getBuffer := getBuffer;
		state.cur.bitsLeft := bitsLeft;
		RETURN TRUE;
	END fillBitBuffer;
	
	(* Ueberpruefen ob noch nbits im BitBuffer vorhanden sind *)
	PROCEDURE checkBitBuffer(state: WorkingStatePtr; nbits: INTEGER):BOOLEAN;
	BEGIN
		IF state.cur.bitsLeft < nbits THEN
			IF ~fillBitBuffer(state,nbits) THEN RETURN FALSE END;
		END;
		RETURN TRUE;
	END checkBitBuffer;
	
	(* nbits vom BitBuffer lesen und als INTEGER zurueckgeben *)
	PROCEDURE getBits(state: WorkingStatePtr; nbits: INTEGER):INTEGER;
	VAR
		i: INTEGER;
		helpSet,helpSet2: LONGINT;
	BEGIN
		helpSet := BIT.LLSH(state.cur.getBuffer,SHORT(-(state.cur.bitsLeft-nbits)));
		helpSet2 := 0;
		FOR i:=0 TO nbits - 1 DO BIT.LSETBIT(helpSet2, SHORT(i)) END;
		helpSet := BIT.LAND(helpSet, helpSet2);
		DEC(state.cur.bitsLeft,nbits);
		RETURN SHORT(helpSet);
	END getBits;
	
	(* nbits vom BitBuffer vorauslesen, Bits aber nicht vom BitBuffer loeschen *)
	PROCEDURE peekBits(state: WorkingStatePtr; nbits: INTEGER):INTEGER;
	VAR
		i: INTEGER;
		helpSet,helpSet2: LONGINT;
	BEGIN
		helpSet := BIT.LLSH(state.cur.getBuffer,SHORT(-(state.cur.bitsLeft-nbits)));
		helpSet2 := 0;
		FOR i:=0 TO nbits - 1 DO BIT.LSETBIT(helpSet2, SHORT(i)) END;
		helpSet := BIT.LAND(helpSet, helpSet2);
		RETURN SHORT(helpSet);
	END peekBits;
	
	(* nbits im BitBuffer ueberlesen *)
	PROCEDURE dropBits(state: WorkingStatePtr; nbits: INTEGER);
	BEGIN
		DEC(state.cur.bitsLeft,nbits);
	END dropBits;
	
	(* Dekodierung des Huffman Codes falls der Code laenger als 8 Bit ist, ca. 5% der Faelle *)
	PROCEDURE slowDECODE(state: WorkingStatePtr; htbl: DDerivedTblPtr; minBits:INTEGER):INTEGER;
	VAR
		i: INTEGER;
		code: LONGINT;
		codeset: LONGINT;
	BEGIN
		i := minBits;
		IF ~checkBitBuffer(state,i) THEN RETURN -1 END;
		code := getBits(state,i);
		WHILE code > htbl.maxcode[i] DO
			codeset := code*2;
			IF ~checkBitBuffer(state,1) THEN RETURN -1 END;
			IF  getBits(state,1) = 1 THEN BIT.LSETBIT(codeset,0) END;
			code := codeset;
			INC(i);
		END;
		
		IF i > 16 THEN
			(* T.WriteString(W,"Huff-slowDecode: bad huffman code, i := "); 
			T.WriteInt(W, i,6);T.WriteLn(W); T.Append(Oberon.Log,W.buf); *)
			RETURN 0;
		END;
		RETURN htbl.pub.huffVal[htbl.valptr[i] + code - htbl.mincode[i]];
	END slowDECODE;
	
	(* Schnelle Dekodierung des Huffman Codes, falls Code <= 8Bits ist *)
	PROCEDURE huffDECODE(VAR result: INTEGER; state: WorkingStatePtr; htbl: DDerivedTblPtr):BOOLEAN;
	VAR
		nb,look: INTEGER;
	BEGIN
		IF state.cur.bitsLeft < HUFFLOOKAHEAD THEN
			IF ~fillBitBuffer(state,0) THEN RETURN FALSE END;
			IF state.cur.bitsLeft < HUFFLOOKAHEAD THEN
				result := slowDECODE(state,htbl,1);
				IF result < 0 THEN RETURN FALSE END;
				RETURN TRUE;
			END;
		END;
		look := peekBits(state,HUFFLOOKAHEAD);
		nb := htbl.lookNBits[look];
		IF nb # 0 THEN
			dropBits(state,nb);
			result := htbl.lookSym[look];
		ELSE
			result := slowDECODE(state,htbl,HUFFLOOKAHEAD + 1);
			IF result < 0 THEN RETURN FALSE END;
		END;
		RETURN TRUE;
	END huffDECODE;
	
	(* Einfuegen des Sign-Bits falls noetig: Umwandlung unsigned -> signed *)
	PROCEDURE huffEXTEND(x,s:INTEGER):INTEGER;
	BEGIN
		IF x < extendTest[s] THEN RETURN x + extendOff[s] ELSE RETURN x END;
	END huffEXTEND;
	
	(* Lesen eines Restart Markers und darauffolgend erneutes Starten der Huffman Dekodierung *)
	PROCEDURE processRestart(cInfo: CInfoPtr):BOOLEAN;
	VAR
		ci: INTEGER;
	BEGIN
		INC(cInfo.marker.discardedBytes,(cInfo.entropy.saved.bitsLeft DIV 8));
		cInfo.entropy.saved.bitsLeft := 0;
		
		IF ~readRestartMarker(cInfo) THEN RETURN FALSE END;
		FOR ci := 0 TO cInfo.compsInScan - 1 DO
			cInfo.entropy.saved.lastDcVal[ci] := 0;
		END;
		cInfo.entropy.restartsToGo := SHORT(cInfo.restartInterval);
		cInfo.entropy.printedEod := FALSE;
		RETURN TRUE;
	END processRestart;
	
	(* Steuerung der Huffman Dekodierung:
		Dekodierung und Rueckgabe eines MCU Blocks von Huffman-Komprimierten Koeffizienten.
		Die Koeffizienten werden von ZIG-ZAG Anordnung in natuerliche Anordnung ueberfuehrt.
		Die Koeffizienten werden aber nicht dequantisiert *)
	PROCEDURE decodeMCU(cInfo: CInfoPtr; VAR MCUData: ARRAY OF JBlock):BOOLEAN;
	VAR
		s,k,r,blkn,ci: INTEGER;
		set: LONGINT;
		block: JBlock;
		state: WorkingStatePtr;
		dctbl,actbl: DDerivedTblPtr;
		compptr: JPEGCompInfoPtr;
	BEGIN
		set := 15;
		NEW(state);
		IF cInfo.restartInterval # 0 THEN
			IF cInfo.entropy.restartsToGo = 0 THEN
				IF ~processRestart(cInfo) THEN RETURN FALSE END;
			END;
		END;
		state.unreadMarker := cInfo.unreadMarker;
		state.cur := cInfo.entropy.saved;
		state.cInfo := cInfo;
		
		FOR blkn := 0 TO cInfo.blocksInMCU -1 DO
			block := MCUData[blkn];
			ci := cInfo.MCUMembership[blkn];
			compptr := cInfo.curCompInfo[ci];
			dctbl := cInfo.entropy.dcDerivedTbls[compptr.dcTblNo];
			actbl := cInfo.entropy.acDerivedTbls[compptr.acTblNo];
			
			IF ~huffDECODE(s,state,dctbl) THEN RETURN FALSE END;
			IF s#0 THEN
				IF ~checkBitBuffer(state,s) THEN RETURN FALSE END;
				r := getBits(state,s);
				s := huffEXTEND(r,s);
			END;
			
			IF compptr.componentNeeded THEN
				INC(s,state.cur.lastDcVal[ci]);
				state.cur.lastDcVal[ci] := s;
				block[0] := s;
			END;
			IF (compptr.DCTScaledSize > 1) & (compptr.componentNeeded) THEN
				k := 1;
				WHILE k < DCTSIZE2 DO
					IF ~huffDECODE(s,state,actbl) THEN RETURN FALSE END;
					r := BIT.ILSH(s, -4);
					s := SHORT(BIT.LAND(LONG(s), set));
					IF s#0 THEN
						INC(k,r);
						IF ~checkBitBuffer(state,s) THEN RETURN FALSE END;
						r := getBits(state,s);
						s := huffEXTEND(r,s);
						block[ZAG[k]] := s;
					ELSE
						IF r # 15 THEN
							k:=DCTSIZE2
						ELSE
							INC(k,15);
						END;
					END;
					INC(k);
				END;
			ELSE
				k := 1;
				WHILE k < DCTSIZE2 DO
					IF ~huffDECODE(s,state,actbl) THEN RETURN FALSE END;
					r := BIT.ILSH(s, -4);
					s := SHORT(BIT.LAND(LONG(s), set));
					IF s#0 THEN
						INC(k,r);
						IF ~checkBitBuffer(state,s) THEN RETURN FALSE END;
						dropBits(state,s);
					ELSE
						IF r # 15 THEN
							k:=DCTSIZE2
						ELSE
							INC(k,15);
						END;
					END;
					INC(k);
				END;
			END;
		END;
		cInfo.unreadMarker := state.unreadMarker;
		cInfo.entropy.saved := state.cur;
		DEC(cInfo.entropy.restartsToGo);
		RETURN  TRUE;
	END decodeMCU;

	(* Initialisierung des Huffman Dekodierungs Prozesses *)
	PROCEDURE jinitHuffDecoder(cInfo: CInfoPtr);
	VAR
		i: INTEGER;
	BEGIN
		NEW(cInfo.entropy);
		FOR i:= 0 TO NUMHUFFTBLS -1 DO
			cInfo.entropy.dcDerivedTbls[i] := NIL;
			cInfo.entropy.acDerivedTbls[i] := NIL;
		END;
	END jinitHuffDecoder;
	
	(* *****      Ende Prozeduren von JPEGHuff       ***** *)
	
	
	(* *****      Start Prozeduren von JPEGIDCT      ***** *)
	(* Dieser Abschnitt beinhaltet die Prozeduren zur IDCT(inverse discrete Cosine Transform)
		Die Koeffizieten werden dequanitfiziert und darauf die IDCT angewendet *)
	
	(* Initialisierung fuer einen Input-Scan *)
	PROCEDURE startInputPassIDCT(cInfo: CInfoPtr);
	VAR
		ci,qtblno,i,row,col : INTEGER;
		compptr: JPEGCompInfoPtr;
		qtbl: JQuantTblPtr;
		sf: ARRAY DCTSIZE OF REAL;
		si: ARRAY DCTSIZE2 OF INTEGER;
	BEGIN
		sf[0] := 1.0;
		sf[1] := 1.387039845;
		sf[2] := 1.306562965;
		sf[3] := 1.175875602;
		sf[4] := 1.0;
		sf[5] := 0.785694958;
		sf[6] := 0.541196100;
		sf[7] := 0.275899379;
		
		si[0] := 16384; si[1] := 22725; si[2] := 21407; si[3] := 19266;
		si[4] := 16384; si[5] := 12873; si[6] := 8867; si[7] := 4520;
		
		si[8] := 22725; si[9] := 31521; si[10] := 29692; si[11] := 26722;
		si[12] := 22725; si[13] := 17855; si[14] := 12299; si[15] := 6270;
			
		si[16] := 21407; si[17] := 29692; si[18] := 27969; si[19] := 25172;
		si[20] := 21407; si[21] := 16819; si[22] := 11585; si[23] := 5906;
		
		si[24] := 19266; si[25] := 26722; si[26] := 25172; si[27] := 22654;
		si[28] := 19266; si[29] := 15137; si[30] := 10426; si[31] := 5315;
		
		si[32] := 16384; si[33] := 22725; si[34] := 21407; si[35] := 19266;
		si[36] := 16384; si[37] := 12873; si[38] := 8867; si[39] := 4520;
		
		si[40] := 12873; si[41] := 17855; si[42] := 16819; si[43] := 15137;
		si[44] := 12873; si[45] := 10114; si[46] := 6967; si[47] := 3552;
		
		si[48] := 8867; si[49] := 12299; si[50] := 11585; si[51] := 10426;
		si[52] := 8867; si[53] := 6967; si[54] := 4799; si[55] := 2446;
		
		si[56] := 4520; si[57] := 6270; si[58] := 5906; si[59] := 5315;
		si[60] := 4520; si[61] := 3552; si[62] := 2446; si[63] := 1247;
		
		FOR ci:=0 TO cInfo.compsInScan - 1 DO
			compptr := cInfo.curCompInfo[ci];
			qtblno := compptr.quantTblNo;
			IF (qtblno < 0) OR (qtblno >= NUMQUANTTBLS) OR (cInfo.quantTbl[qtblno] = NIL) THEN
				ErrMsg("bad qtbl index", 34); RETURN
			END;
			qtbl := cInfo.quantTbl[qtblno];
			IF cInfo.selectIDCT = Scale THEN
				IF compptr.dctSTable = NIL THEN
					NEW(compptr.dctSTable);
					FOR i:=0 TO DCTSIZE2 -1 DO
						compptr.dctSTable[i] := qtbl.quantVal[ZIG[i]];
					END;
				END;
			END;
			IF cInfo.selectIDCT = Float THEN
				IF compptr.dctTable = NIL THEN
					NEW(compptr.dctTable);
					i := 0;
					FOR row:=0 TO DCTSIZE -1 DO
						FOR col:=0 TO DCTSIZE -1 DO
							compptr.dctTable[i] := qtbl.quantVal[ZIG[i]] * sf[row] * sf[col];
							INC(i);
						END;
					END;
				END;
			ELSIF (cInfo.selectIDCT = Integer) OR (cInfo.selectIDCT = Scale) THEN
				IF compptr.dctITable = NIL THEN
					NEW(compptr.dctITable);
					FOR i:= 0 TO DCTSIZE2 -1 DO
						compptr.dctITable[i] := ASH(qtbl.quantVal[ZIG[i]] * si[i] + 2048,-12);
					END;
				END;
			END;
		END;
	END startInputPassIDCT;
	
	(* weitere Ueberpruefungen zur Durchfuehrung der IDCT *)
	PROCEDURE startOutputPassIDCT(cInfo: CInfoPtr);
	VAR
		ci: INTEGER;
		compptr: JPEGCompInfoPtr;
	BEGIN
		FOR ci:=0 TO cInfo.numComponents - 1 DO
			compptr := cInfo.compInfo[ci];
			IF compptr.componentNeeded THEN
				IF cInfo.selectIDCT = Float THEN
					IF compptr.dctTable = NIL THEN
						ErrMsg("component not found", 35)
					END;
				ELSIF cInfo.selectIDCT = Integer THEN
					IF compptr.dctITable = NIL THEN
						ErrMsg("component not found", 36)
					END;
				ELSIF cInfo.selectIDCT = Scale THEN
					IF compptr.dctSTable = NIL THEN
						ErrMsg("component not found", 37)
					END;
				END;
			END;
		END;
	END startOutputPassIDCT;
	
	(* Ueberfuehrung der IDCT Resultatwerte in den gueltigkeitsbereich 0..255
		Achtung: zusaetzlich werden hier die Werte von signed in unsigned Werte. Dazu wird
		CENTERJSAMPLE zum Wert addiert und aus der RL-Tabelle der entsprechende Wert
		zurueckgegeben *)
	PROCEDURE rangeLimit(x:INTEGER):INTEGER;
	BEGIN
		x := x MOD 400H;	(* nur die ersten 10 Bits von x, Rest 0 *)
		
		RETURN RL[x];
	END rangeLimit;
	
	(* Schnelle INTEGER Implementation der IDCT
		Dieser Algorithmus basiert auf dem Algorithmus von Arai, Agui und Nakajima fuer
		skalierte DCT *)
	PROCEDURE jpegIDCTIFast(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	VAR
		tmp0,tmp1,tmp2,tmp3,tmp4,tmp5,tmp6,tmp7,tmp10,tmp11,tmp12,tmp13: LONGINT;
		z5,z10,z11,z12,z13,dcval1: LONGINT;
		dcval: CHAR;
		inptr: JBlock;
		quantptr,wsptr: DCTITablePtr;
		inws,ctr: INTEGER;
		outptr: JSampRow;
	BEGIN
		inptr :=coefBlock;
		quantptr := compptr.dctITable;
		NEW(wsptr);
		
		FOR ctr:=0 TO DCTSIZE -1 DO
			IF (inptr[DCTSIZE * 1 + ctr] = 0) & (inptr[DCTSIZE * 2 + ctr] = 0) & 
				(inptr[DCTSIZE * 3 + ctr] = 0) & (inptr[DCTSIZE * 4 + ctr] = 0) &
				(inptr[DCTSIZE * 5 + ctr] = 0) & (inptr[DCTSIZE * 6 + ctr] = 0) &
				(inptr[DCTSIZE * 7 + ctr] = 0) 
			THEN
				dcval1 := LONG(inptr[ctr]) * quantptr[ctr];
				wsptr[ctr] := dcval1;
				wsptr[DCTSIZE * 1 +ctr] := dcval1;
				wsptr[DCTSIZE * 2 +ctr] := dcval1;
				wsptr[DCTSIZE * 3 +ctr] := dcval1;
				wsptr[DCTSIZE * 4 +ctr] := dcval1;
				wsptr[DCTSIZE * 5 +ctr] := dcval1;
				wsptr[DCTSIZE * 6 +ctr] := dcval1;
				wsptr[DCTSIZE * 7 +ctr] := dcval1;
			ELSE
				tmp0 := LONG(inptr[ctr]) * quantptr[ctr];
				tmp1 := LONG(inptr[DCTSIZE * 2 + ctr]) * quantptr[DCTSIZE * 2 + ctr];
				tmp2 := LONG(inptr[DCTSIZE * 4 + ctr]) * quantptr[DCTSIZE * 4 + ctr];
				tmp3 := LONG(inptr[DCTSIZE * 6 + ctr]) * quantptr[DCTSIZE * 6 + ctr];
				tmp10 := tmp0 + tmp2;
				tmp11 := tmp0 - tmp2;
				tmp13 := tmp1 + tmp3;
				tmp12 := ASH((tmp1 - tmp3) * 362, -8)  - tmp13;
				tmp0 := tmp10 + tmp13;
				tmp3 := tmp10 - tmp13;
				tmp1 := tmp11 + tmp12;
				tmp2 := tmp11 - tmp12;

				tmp4 := LONG(inptr[DCTSIZE * 1 + ctr]) * quantptr[DCTSIZE * 1 + ctr];
				tmp5 := LONG(inptr[DCTSIZE * 3 + ctr]) * quantptr[DCTSIZE * 3 + ctr];
				tmp6 := LONG(inptr[DCTSIZE * 5 + ctr]) * quantptr[DCTSIZE * 5 + ctr];
				tmp7 := LONG(inptr[DCTSIZE * 7 + ctr]) * quantptr[DCTSIZE * 7 + ctr];
				z13 := tmp6 + tmp5;
				z10 := tmp6 - tmp5;
				z11 := tmp4 + tmp7;
				z12 := tmp4 - tmp7;
				tmp7 := z11 + z13;
				tmp11 := ASH((z11 - z13) * 362, -8);
				z5 := ASH((z10 + z12) * 473, -8);
				tmp10 := ASH(277 * z12, -8) - z5;
				tmp12 := ASH(-669 * z10, -8) + z5;
				tmp6 := tmp12 - tmp7;
				tmp5 := tmp11 - tmp6;
				tmp4 := tmp10 + tmp5;
				
				wsptr[ctr] := tmp0 + tmp7;
				wsptr[DCTSIZE * 7 +ctr] := tmp0 - tmp7;
				wsptr[DCTSIZE * 1 +ctr] := tmp1 + tmp6;
				wsptr[DCTSIZE * 6 +ctr] := tmp1 - tmp6;
				wsptr[DCTSIZE * 2 +ctr] := tmp2 + tmp5;
				wsptr[DCTSIZE * 5 +ctr] := tmp2 - tmp5;
				wsptr[DCTSIZE * 4 +ctr] := tmp3 + tmp4;
				wsptr[DCTSIZE * 3 +ctr] := tmp3 - tmp4;
			END;
		END;
		
		inws := 0;
		FOR ctr := 0 TO DCTSIZE -1 DO
			outptr := outputBuf.row[ctr + outputRow];
			
			IF (wsptr[1 + inws] = 0) & (wsptr[2 + inws] = 0) & 
				(wsptr[3 + inws] = 0) & (wsptr[4 + inws] = 0) &
				(wsptr[5 + inws] = 0) & (wsptr[6 + inws] = 0) &
				(wsptr[7 + inws] = 0) 
			THEN
				dcval := CHR(rangeLimit(SHORT(ASH(wsptr[inws] + 16, -5))));
				outptr[0 + outputCol] := dcval;
				outptr[1 + outputCol] := dcval;
				outptr[2 + outputCol] := dcval;
				outptr[3 + outputCol] := dcval;
				outptr[4 + outputCol] := dcval;
				outptr[5 + outputCol] := dcval;
				outptr[6 + outputCol] := dcval;
				outptr[7 + outputCol] := dcval;
				
			ELSE
				tmp10 := wsptr[inws] + wsptr[4 + inws];
				tmp11 := wsptr[inws] - wsptr[4 + inws]; 
				tmp13 := wsptr[2 + inws] + wsptr[6 + inws];
				tmp12 := ASH((wsptr[2 + inws] - wsptr[6 + inws]) * 362, -8) - tmp13;
				tmp0 := tmp10 + tmp13;
				tmp3 := tmp10 - tmp13;
				tmp1 := tmp11 + tmp12;
				tmp2 := tmp11 - tmp12;
			
				z13 := wsptr[5 + inws] + wsptr[3 + inws];
				z10 := wsptr[5 + inws] - wsptr[3 + inws];
				z11 := wsptr[1 + inws] + wsptr[7 + inws];
				z12 := wsptr[1 + inws] - wsptr[7 + inws];
				tmp7 := z11 + z13;
				tmp11 := ASH((z11 -z13) * 362, -8);
				z5 := ASH((z10 + z12) * 473, -8);
				tmp10 := ASH(277 * z12, -8) - z5;
				tmp12 := ASH(-669 * z10, -8) + z5;
				tmp6 := tmp12 - tmp7;
				tmp5 := tmp11 - tmp6;
				tmp4 := tmp10 + tmp5;
				
				outptr[0 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp0 + tmp7 + 16, -5))));
				outptr[7 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp0 - tmp7 + 16, -5))));
				outptr[1 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp1 + tmp6 + 16, -5))));
				outptr[6 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp1 - tmp6 + 16, -5))));
				outptr[2 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp2 + tmp5 + 16, -5))));
				outptr[5 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp2 - tmp5 + 16, -5))));
				outptr[4 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp3 + tmp4 + 16, -5))));
				outptr[3 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp3 - tmp4 + 16, -5))));
			END;
			
			INC(inws,DCTSIZE);
		END;
	END jpegIDCTIFast;
	
	(* Scaling um Faktor 2, Integer IDCT Methode *)
	PROCEDURE jpegIDCT4X4(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	VAR
		tmp0,tmp2,tmp10,tmp12,z1,z2,z3,z4,dcval: LONGINT;
		inptr: JBlock;
		quantptr,wsptr: DCTSTablePtr;
		inws,hctr,ctr: INTEGER;
		outptr: JSampRow;
		dcChar: CHAR;
	BEGIN
		inptr :=coefBlock;
		quantptr := compptr.dctSTable;
		NEW(wsptr);
		
		hctr := DCTSIZE +1;
		FOR ctr:=0 TO DCTSIZE -1 DO
			DEC(hctr);
			IF hctr # 4 THEN
				IF (inptr[DCTSIZE * 1 + ctr] = 0) & (inptr[DCTSIZE * 2 + ctr] = 0) & 
					(inptr[DCTSIZE * 3 + ctr] = 0) & 
					(inptr[DCTSIZE * 5 + ctr] = 0) & (inptr[DCTSIZE * 6 + ctr] = 0) &
					(inptr[DCTSIZE * 7 + ctr] = 0) 
				THEN
					dcval := BIT.LLSH(LONG(inptr[ctr]) * quantptr[ctr],2);
					wsptr[ctr] := dcval;
					wsptr[DCTSIZE * 1 +ctr] := dcval;
					wsptr[DCTSIZE * 2 +ctr] := dcval;
					wsptr[DCTSIZE * 3 +ctr] := dcval;
				ELSE
					tmp0 := BIT.LLSH(LONG(inptr[ctr]) * quantptr[ctr],14);
					z2 := LONG(inptr[DCTSIZE * 2 + ctr]) * quantptr[DCTSIZE * 2 + ctr];
					z3 := LONG(inptr[DCTSIZE * 6 + ctr]) * quantptr[DCTSIZE * 6 + ctr];
					tmp2 := z2 * 15137 - z3 * 6270;
					tmp10 := tmp0 + tmp2;
					tmp12 := tmp0 - tmp2;

					z4 := LONG(inptr[DCTSIZE * 1 + ctr]) * quantptr[DCTSIZE * 1 + ctr];
					z3 := LONG(inptr[DCTSIZE * 3 + ctr]) * quantptr[DCTSIZE * 3 + ctr];
					z2 := LONG(inptr[DCTSIZE * 5 + ctr]) * quantptr[DCTSIZE * 5 + ctr];
					z1 := LONG(inptr[DCTSIZE * 7 + ctr]) * quantptr[DCTSIZE * 7 + ctr];
					tmp0 := -z1 * 1730 + z2 * 11893 - z3 * 17799 + z4 * 8697;
					tmp2 := -z1 * 4176 - z2 * 4926 + z3 * 7373 + z4 * 20995;
				
					wsptr[ctr] := ASH(tmp10 + tmp2 + 2024,-12);
					wsptr[DCTSIZE * 3 +ctr] := ASH(tmp10 - tmp2 + 2024,-12);
					wsptr[DCTSIZE * 1 +ctr] := ASH(tmp12 + tmp0 + 2024,-12);
					wsptr[DCTSIZE * 2 +ctr] := ASH(tmp12 - tmp0 + 2024,-12);
				END;
			END;
		END;
		
		inws := 0;
		FOR ctr := 0 TO 3 DO
			outptr := outputBuf.row[ctr + outputRow];
			
			IF (wsptr[1 + inws] = 0) & (wsptr[2 + inws] = 0) & 
				(wsptr[3 + inws] = 0) & 
				(wsptr[5 + inws] = 0) & (wsptr[6 + inws] = 0) &
				(wsptr[7 + inws] = 0) 
			THEN
				dcChar := CHR(rangeLimit(SHORT(ASH(wsptr[inws] + 16, -5))));
				outptr[0 + outputCol] := dcChar;
				outptr[1 + outputCol] := dcChar;
				outptr[2 + outputCol] := dcChar;
				outptr[3 + outputCol] := dcChar;
			ELSE
				tmp0 := ASH(wsptr[inws],14);
				tmp2 := wsptr[2 + inws] * 15137 - wsptr[6 + inws] * 6270;
				tmp10 := tmp0 + tmp2;
				tmp12 := tmp0 - tmp2;
				z1 := wsptr[7 + inws];
				z2 := wsptr[5 + inws];
				z3 := wsptr[3 + inws];
				z4 := wsptr[1 + inws];
				tmp0 := -z1 * 1730 + z2 * 11893 - z3 * 17799 + z4 * 8697;
				tmp2 := -z1 * 4176 - z2 * 4926 + z3 * 7373 + z4 * 20995;
								
				outptr[0 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp10 + tmp2 + 524288, -19))));
				outptr[3 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp10 - tmp2 + 524288, -19))));
				outptr[1 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp12 + tmp0 + 524288, -19))));
				outptr[2 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp12 - tmp0 + 524288, -19))));
			END;
			
			INC(inws,DCTSIZE);
		END;
	END jpegIDCT4X4;
	
	(* Scaling um Faktor 4, Integer IDCT Methode *)
	PROCEDURE jpegIDCT2X2(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	VAR
		tmp0,tmp10,z1,dcval: LONGINT;
		inptr: JBlock;
		quantptr,wsptr: DCTSTablePtr;
		inws,hctr,ctr: INTEGER;
		outptr: JSampRow;
		dcChar: CHAR;
	BEGIN
		inptr :=coefBlock;
		quantptr := compptr.dctSTable;
		NEW(wsptr);
		
		hctr := DCTSIZE +1;
		FOR ctr:=0 TO DCTSIZE -1 DO
			DEC(hctr);
			IF (hctr = 6)  OR (hctr = 4) OR (hctr = 2) THEN
			ELSE
				IF (inptr[DCTSIZE * 1 + ctr] = 0) &  
					(inptr[DCTSIZE * 3 + ctr] = 0) & 
					(inptr[DCTSIZE * 5 + ctr] = 0) & 
					(inptr[DCTSIZE * 7 + ctr] = 0) 
				THEN
					dcval := BIT.LLSH(LONG(inptr[ctr]) * quantptr[ctr],2);
					wsptr[ctr] := dcval;
					wsptr[DCTSIZE * 1 +ctr] := dcval;
				ELSE
					z1 := LONG(inptr[ctr]) * quantptr[ctr];
					tmp10 := BIT.LLSH(z1,15);
				
					z1 := LONG(inptr[DCTSIZE * 7 + ctr]) * quantptr[DCTSIZE * 7 + ctr];
					tmp0 := -z1 * 5906;
					z1 := LONG(inptr[DCTSIZE * 5 + ctr]) * quantptr[DCTSIZE * 5 + ctr];
					tmp0 := tmp0 + z1 * 6967;
					z1 := LONG(inptr[DCTSIZE * 3 + ctr]) * quantptr[DCTSIZE * 3 + ctr];
					tmp0 := tmp0 - z1 * 10426;
					z1 := LONG(inptr[DCTSIZE * 1 + ctr]) * quantptr[DCTSIZE * 1 + ctr];
					tmp0 := tmp0 + z1 * 29692;
					
					wsptr[ctr] := ASH(tmp10 + tmp0 + 4096,-13);
					wsptr[DCTSIZE * 1 +ctr] := ASH(tmp10 - tmp0 + 4096,-13);
				END;
			END;
		END;
		
		inws := 0;
		FOR ctr := 0 TO 1 DO
			outptr := outputBuf.row[ctr + outputRow];
			
			IF (wsptr[1 + inws] = 0) &  
				(wsptr[3 + inws] = 0) & 
				(wsptr[5 + inws] = 0) & 
				(wsptr[7 + inws] = 0) 
			THEN
				dcChar := CHR(rangeLimit(SHORT(ASH(wsptr[inws] + 16, -5))));
				outptr[0 + outputCol] := dcChar;
				outptr[1 + outputCol] := dcChar;
			ELSE
				tmp10 := ASH(wsptr[inws],15);
				tmp0 := -wsptr[7 + inws] * 5906 + wsptr[5 + inws] * 6967
						   -wsptr[3 + inws] * 10426 + wsptr[1 + inws] * 29692;
								
				outptr[0 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp10 + tmp0 + 1048576, -20))));
				outptr[1 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(tmp10 - tmp0 + 1048576, -20))));
			END;
			
			INC(inws,DCTSIZE);
		END;
	END jpegIDCT2X2;
	
	(* Scaling um Faktor 8, Integer IDCT Methode *)
	PROCEDURE jpegIDCT1X1(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	VAR
		quantptr: DCTSTablePtr;
		dcval: LONGINT;
	BEGIN
		quantptr := compptr.dctSTable;
		dcval := LONG(coefBlock[0]) * quantptr[0];
		dcval := ASH(dcval + 8,-3);
		outputBuf.row[0 + outputRow][outputCol] := CHR(rangeLimit(SHORT(dcval)));
	END jpegIDCT1X1;
	
	
	(* Floating-Point Implementation des Algorithmus von Arai, Agui und Nakajima *)
	PROCEDURE jpegIDCTFloat(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr; 
											coefBlock: JBlock; outputBuf: JSampArray; 
											outputRow, outputCol: LONGINT);
	VAR
		tmp0,tmp1,tmp2,tmp3,tmp4,tmp5,tmp6,tmp7,tmp10,tmp11,tmp12,tmp13: REAL;
		z5,z10,z11,z12,z13,dcval: REAL;
		inptr: JBlock;
		quantptr,wsptr: DCTTablePtr;
		inws,ctr: INTEGER;
		outptr: JSampRow;
	BEGIN
		inptr :=coefBlock;
		quantptr := compptr.dctTable;
		NEW(wsptr);
		
		FOR ctr:=0 TO DCTSIZE -1 DO
			IF (inptr[DCTSIZE * 1 + ctr] = 0) & (inptr[DCTSIZE * 2 + ctr] = 0) & 
				(inptr[DCTSIZE * 3 + ctr] = 0) & (inptr[DCTSIZE * 4 + ctr] = 0) &
				(inptr[DCTSIZE * 5 + ctr] = 0) & (inptr[DCTSIZE * 6 + ctr] = 0) &
				(inptr[DCTSIZE * 7 + ctr] = 0) 
			THEN
				dcval := inptr[ctr] * quantptr[ctr];
				wsptr[ctr] := dcval;
				wsptr[DCTSIZE * 1 +ctr] := dcval;
				wsptr[DCTSIZE * 2 +ctr] := dcval;
				wsptr[DCTSIZE * 3 +ctr] := dcval;
				wsptr[DCTSIZE * 4 +ctr] := dcval;
				wsptr[DCTSIZE * 5 +ctr] := dcval;
				wsptr[DCTSIZE * 6 +ctr] := dcval;
				wsptr[DCTSIZE * 7 +ctr] := dcval;
			ELSE
				tmp0 := inptr[ctr] * quantptr[ctr];
				tmp1 := inptr[DCTSIZE * 2 + ctr] * quantptr[DCTSIZE * 2 + ctr];
				tmp2 := inptr[DCTSIZE * 4 + ctr] * quantptr[DCTSIZE * 4 + ctr];
				tmp3 := inptr[DCTSIZE * 6 + ctr] * quantptr[DCTSIZE * 6 + ctr];
				tmp10 := tmp0 + tmp2;
				tmp11 := tmp0 - tmp2;
				tmp13 := tmp1 + tmp3;
				tmp12 := (tmp1 - tmp3) * 1.414213562 - tmp13;
				tmp0 := tmp10 + tmp13;
				tmp3 := tmp10 - tmp13;
				tmp1 := tmp11 + tmp12;
				tmp2 := tmp11 - tmp12;
				
				tmp4 := inptr[DCTSIZE * 1 + ctr] * quantptr[DCTSIZE * 1 + ctr];
				tmp5 := inptr[DCTSIZE * 3 + ctr] * quantptr[DCTSIZE * 3 + ctr];
				tmp6 := inptr[DCTSIZE * 5 + ctr] * quantptr[DCTSIZE * 5 + ctr];
				tmp7 := inptr[DCTSIZE * 7 + ctr] * quantptr[DCTSIZE * 7 + ctr];
				z13 := tmp6 + tmp5;
				z10 := tmp6 - tmp5;
				z11 := tmp4 + tmp7;
				z12 := tmp4 - tmp7;
				tmp7 := z11 + z13;
				tmp11 := (z11 - z13) * 1.414213562;
				z5 := (z10 + z12) * 1.847759065;
				tmp10 := 1.082392200 * z12 - z5;
				tmp12 := -2.613125930 * z10 + z5;
				tmp6 := tmp12 - tmp7;
				tmp5 := tmp11 - tmp6;
				tmp4 := tmp10 + tmp5;
				
				wsptr[ctr] := tmp0 + tmp7;
				wsptr[DCTSIZE * 7 +ctr] := tmp0 - tmp7;
				wsptr[DCTSIZE * 1 +ctr] := tmp1 + tmp6;
				wsptr[DCTSIZE * 6 +ctr] := tmp1 - tmp6;
				wsptr[DCTSIZE * 2 +ctr] := tmp2 + tmp5;
				wsptr[DCTSIZE * 5 +ctr] := tmp2 - tmp5;
				wsptr[DCTSIZE * 4 +ctr] := tmp3 + tmp4;
				wsptr[DCTSIZE * 3 +ctr] := tmp3 - tmp4;
			END;
		END;
		
		inws := 0;
		FOR ctr := 0 TO DCTSIZE -1 DO
			outptr := outputBuf.row[ctr + outputRow];
			
			tmp10 := wsptr[inws] + wsptr[4 + inws];
			tmp11 := wsptr[inws] - wsptr[4 + inws]; 
			tmp13 := wsptr[2 + inws] + wsptr[6 + inws];
			tmp12 := (wsptr[2 + inws] - wsptr[6 + inws]) * 1.414213562 - tmp13;
			tmp0 := tmp10 + tmp13;
			tmp3 := tmp10 - tmp13;
			tmp1 := tmp11 + tmp12;
			tmp2 := tmp11 - tmp12;
			
			z13 := wsptr[5 + inws] + wsptr[3 + inws];
			z10 := wsptr[5 + inws] - wsptr[3 + inws];
			z11 := wsptr[1 + inws] + wsptr[7 + inws];
			z12 := wsptr[1 + inws] - wsptr[7 + inws];
			tmp7 := z11 + z13;
			tmp11 := (z11 -z13) * 1.414213562;
			z5 := (z10 + z12) * 1.847759065;
			tmp10 := 1.082392200 * z12 - z5;
			tmp12 := -2.613125930 * z10 + z5;
			tmp6 := tmp12 - tmp7;
			tmp5 := tmp11 - tmp6;
			tmp4 := tmp10 + tmp5;
			
			outptr[0 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp0 + tmp7) + 4, -3))));
			outptr[7 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp0 - tmp7) + 4, -3))));
			outptr[1 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp1 + tmp6) + 4, -3))));
			outptr[6 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp1 - tmp6) + 4, -3))));
			outptr[2 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp2 + tmp5) + 4, -3))));
			outptr[5 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp2 - tmp5) + 4, -3))));
			outptr[4 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp3 + tmp4) + 4, -3))));
			outptr[3 + outputCol] := 
					CHR(rangeLimit(SHORT(ASH(ENTIER(tmp3 - tmp4) + 4, -3))));
			INC(inws,DCTSIZE);
		END; 
	END jpegIDCTFloat;
	
	(* Auswahl der IDCT Methode pro Farbkomponenten *)
	PROCEDURE jinitIDCT(cInfo: CInfoPtr);
	VAR
		compptr: JPEGCompInfoPtr;
		ci: INTEGER;
	BEGIN
		FOR ci := 0 TO cInfo.numComponents - 1 DO
			compptr := cInfo.compInfo[ci];
			compptr.dctTable := NIL;
			compptr.dctITable := NIL;
			compptr.dctSTable := NIL; 
			IF cInfo.selectIDCT = Float THEN compptr.IDCTMethod := jpegIDCTFloat;
			ELSIF cInfo.selectIDCT = Integer THEN compptr.IDCTMethod := jpegIDCTIFast;
			ELSIF cInfo.selectIDCT = Scale THEN
				IF compptr.DCTScaledSize = 1 THEN compptr.IDCTMethod := jpegIDCT1X1;
				ELSIF compptr.DCTScaledSize = 2 THEN compptr.IDCTMethod := jpegIDCT2X2;
				ELSIF compptr.DCTScaledSize = 4 THEN compptr.IDCTMethod := jpegIDCT4X4;
				ELSE compptr.IDCTMethod := jpegIDCTIFast;
				END;
			END;
		END;
	END jinitIDCT;

	(* *****      Ende Prozeduren von JPEGIDCT       ***** *)
	
	
	(* *****      Start Prozeduren von JPEGCoef       ***** *)
	(* Dieser Abschnitt beinhaltet Routinen fuer die Steuerung der eigentlichen JPEG-Dekodierung
		1.1	Huffman Dekodierung
		1.2	ZICK-ZACK Anordnung der Koeffizienten -> natuerliche Anordnung
		2.1	Dequantisierung der Koeffizienten
		2.2	IDCT *)

	(* Steuerung der Dekodierung einer ganzen iMCU Reihe. Der Output wird fuer jeden
		Farbkomponenten separat ausgegeben *)
	PROCEDURE decompressData(cInfo: CInfoPtr; outputBuf: JSampImage):BOOLEAN;
	VAR
		MCUColNum, lastMCUCol, lastMCURow, startCol, outputCol, outputRow: LONGINT;
		blkn, ci, i, j, xindex, yindex, usefulWidth: INTEGER;
		compptr: JPEGCompInfoPtr;
		outputPtr: JSampArray;
	BEGIN
		lastMCUCol := cInfo.MCUsPerRow - 1;
		lastMCURow := cInfo.MCURowsInScan - 1;
		
		FOR MCUColNum :=cInfo.coef.MCUColNum TO lastMCUCol DO
			FOR j:=0 TO MAXBLOCKSINMCU - 1 DO
				FOR i:=0 TO DCTSIZE2 - 1 DO
					cInfo.coef.MCUBuffer[j][i]:=0;
				END;
			END;
			IF ~decodeMCU(cInfo,cInfo.coef.MCUBuffer) THEN
				cInfo.coef.MCUColNum := MCUColNum;
				RETURN FALSE;
			END;
			
			blkn := 0;
			FOR ci:= 0 TO cInfo.compsInScan - 1 DO
				compptr := cInfo.curCompInfo[ci];
				IF ~compptr.componentNeeded THEN
					INC(blkn,compptr.MCUBlocks);
				ELSE
					IF MCUColNum < lastMCUCol THEN
						usefulWidth := compptr.MCUWidth;
					ELSE
						usefulWidth := compptr.lastColWidth;
					END;
					outputPtr := outputBuf.comp[ci];
					outputRow := 0;
					startCol := MCUColNum * compptr.MCUSampleWidth;
					FOR yindex := 0 TO compptr.MCUHeight - 1 DO
						IF (cInfo.coef.MCURowNum < lastMCURow) OR (yindex < compptr.lastRowHeight) THEN
							outputCol := startCol;
							FOR xindex:=0 TO usefulWidth - 1 DO
								compptr.IDCTMethod(cInfo, compptr,cInfo.coef.MCUBuffer[blkn + xindex],
															outputPtr,outputRow,outputCol);
								outputCol:=outputCol + compptr.DCTScaledSize;
							END;
						END;
						INC(blkn,compptr.MCUWidth);
						outputRow := outputRow + compptr.DCTScaledSize;
					END;
				END;
			END;
		END;
		cInfo.coef.MCUColNum := 0;
		INC(cInfo.coef.MCURowNum);
		RETURN TRUE;
	END decompressData;
	
	PROCEDURE startPassCoef(cInfo: CInfoPtr; passMode:SHORTINT);
	BEGIN
		cInfo.coef.MCUColNum := 0;
		cInfo.coef.MCURowNum := 0;
		
		IF passMode = JBUFPASSTHRU THEN
			IF cInfo.coef.wholeImage THEN
				ErrMsg("wholeimage mode not implemented", 38)
			END;
			cInfo.coef.decompressData := decompressData;
		ELSE
			ErrMsg("unknown mode", 39)
		END;
	END startPassCoef;
	
	(* Initialisierung des Koeffizienten Dekodierungs Kontrollers *)
	PROCEDURE jinitDCoefController(cInfo: CInfoPtr; needFullBuffer:BOOLEAN);
	VAR
		i: INTEGER;
	BEGIN
		NEW(cInfo.coef);
		cInfo.coef.wholeImage := FALSE;
		IF needFullBuffer THEN
			ErrMsg("fullbuffer mode not implemented", 40)
		ELSE
			FOR i:=0 TO MAXBLOCKSINMCU -1 DO
				NEW(cInfo.coef.MCUBuffer[i]);
			END;
		END;
	END jinitDCoefController;
	
	(* *****       Ende Proceduren von JPEGCoef      ***** *)
	
	(* ******************************************************** *)

	(* *****       Start Prozeduren von JPEGCConvert        ***** *)
	(* Dieser Abschnitt beinhaltet Routinen fuer die Konvertierung von einer Farbdarstellung 
		in eine andere. Am haeufigsten ist der Fall: YCbCr in RGB *)
	
	(* Wert muss im Bereich 0..255 liegen *)
	PROCEDURE rangeLimit2(x:INTEGER):INTEGER;
	BEGIN
		IF x<0 THEN RETURN 0
		ELSIF x > MAXJSAMPLE THEN RETURN MAXJSAMPLE
		ELSE RETURN x
		END;
	END rangeLimit2;
	
	(* Kopieren von ganzen Sample Zeilen *)
	PROCEDURE jcopySampleRows(inputArray: JSampArray; sourceRow:INTEGER; 
											outputArray: JSampArray; destRow: INTEGER;
											numRows:INTEGER; numCols: LONGINT);
	VAR
		outptr,inptr: JSampRow;
		row,i,j: INTEGER;
		x: LONGINT;
	BEGIN
		i:= sourceRow;
		j:= destRow;
		row := numRows;
		WHILE row >= 1 DO
			inptr := inputArray.row[i]; INC(i);
			outptr := outputArray.row[j]; INC(j);
			FOR x:= 0 TO numCols - 1 DO
				outptr[x] := inptr[x];
			END;
			DEC(row);
		END;
	END jcopySampleRows;
	
	(* Konvertierung YCbCr nach RGB. Es wird folgende Formel benuetzt:
		R := Y + 1.40200 * Cr;	G:= Y - 0.344414 * Cb - 0.71414 * Cr;	B:=Y + 1.77200 * Cb
		Dabei sind Cb und Cr die gelesenen Werte minus CENTERJSAMPLE.
		Speziell: Hier wird Floating-Point Arithmetik vermieden und mit Tabellen gearbeitet *)
	PROCEDURE yccRGBConvert(cInfo: CInfoPtr; inputBuf:ARRAY OF JSampArray;
												inputRow: LONGINT; outputBuf: JSampArray;
												outRowCtr: LONGINT; numRows:INTEGER);
	VAR
		y,cb,cr,x,test: INTEGER;
		outptr,inptr0,inptr1,inptr2: JSampRow;
		col,numCols,out: LONGINT;
	BEGIN
		out := 0;
		numCols := cInfo.outputWidth;
		DEC(numRows);
		WHILE numRows >= 0 DO
			inptr0 := inputBuf[0].row[inputRow];
			inptr1 := inputBuf[1].row[inputRow];
			inptr2 := inputBuf[2].row[inputRow];
			INC(inputRow);
			outptr := outputBuf.row[out];
			INC(out);
			x := 0;
			FOR col:=0 TO numCols -1 DO
				y := ORD(inptr0[col]);
				cb := ORD(inptr1[col]);
				cr := ORD(inptr2[col]);
				
				test := y + crRTab[cr];
				outptr[RGBRED +x] := CHR(rangeLimit2(test));
				test := y + cbBTab[cb];
				outptr[RGBBLUE +x] := CHR(rangeLimit2(test));
				test := y + SHORT(ASH(cbGTab[cb] + crGTab[cr],-16));
				outptr[RGBGREEN +x] := CHR(rangeLimit2(test));
							
				INC(x, RGBPIXELSIZE);
			END;
			DEC(numRows);
		END;
	END yccRGBConvert;
	
	(* Keine Umwandlung der Farbdarstellung notwenig, nur Kopieren der Werte
		Die Darstellung der Farbkomponenten wechselt von separaten Zeilen pro Farbkomponent
		zur gemischten Darstellung *)
	PROCEDURE nullConvert(cInfo: CInfoPtr; inputBuf:ARRAY OF JSampArray;
												inputRow: LONGINT; outputBuf: JSampArray;
												outRowCtr: LONGINT; numRows:INTEGER);
	VAR
		x: INTEGER;
		outptr,inptr: JSampRow;
		numCols,count,out: LONGINT;
	BEGIN
		out := 0;
		numCols := cInfo.outputWidth;
		DEC(numRows);
		WHILE numRows >= 0 DO
			inptr := inputBuf[0].row[inputRow];
			outptr := outputBuf.row[out];
			x:=0;
			FOR count:=0 TO numCols -1 DO
				outptr[x] := inptr[count];
				INC(x);
			END;
			INC(inputRow);
			INC(out);
			DEC(numRows);
		END;
	END nullConvert;

	(* Konvertierung fuer Graustufen Darstellung: reines Kopieren der Daten *)
	PROCEDURE grayscaleConvert(cInfo: CInfoPtr; inputBuf:ARRAY OF JSampArray;
												inputRow: LONGINT; outputBuf: JSampArray;
												outRowCtr: LONGINT; numRows:INTEGER);
	BEGIN
		jcopySampleRows(inputBuf[0],SHORT(inputRow),outputBuf,0,numRows,cInfo.outputWidth);
	END grayscaleConvert;
	
	(* Initialisierung des Farbkonverters *)
	PROCEDURE jinitColorDeconverter(cInfo: CInfoPtr);
	VAR
		ci: INTEGER;
	BEGIN
		NEW(cInfo.cconvert);
		IF (cInfo.jpegColorSpace # JCSRGB) & (cInfo.jpegColorSpace # JCSYCBCR) & 
			(cInfo.jpegColorSpace # JCSGRAYSCALE)  THEN
			ErrMsg("bad jpegColorSpace", 41); RETURN
		END;
		IF cInfo.outColorSpace = JCSGRAYSCALE THEN
			cInfo.outColorComponents := 1;
			IF (cInfo.jpegColorSpace = JCSYCBCR) OR (cInfo.jpegColorSpace = JCSGRAYSCALE) THEN
				cInfo.cconvert.colorConvert := grayscaleConvert;
				FOR ci := 1 TO cInfo.numComponents - 1 DO
					cInfo.compInfo[ci].componentNeeded := FALSE;
				END;
			ELSE
				ErrMsg("bad jpegColorSpace", 42);  RETURN
			END;
		ELSIF cInfo.outColorSpace = JCSRGB THEN
			cInfo.outColorComponents := RGBPIXELSIZE;
			IF cInfo.jpegColorSpace = JCSYCBCR THEN
				cInfo.cconvert.colorConvert := yccRGBConvert;
			ELSIF (cInfo.jpegColorSpace = JCSRGB) & (RGBPIXELSIZE = 3) THEN
				cInfo.cconvert.colorConvert := nullConvert;
			ELSE
				ErrMsg("bad jpegColorSpace", 43);  RETURN
			END;
		ELSE
			ErrMsg("bad jpegColorSpace", 44);  RETURN
		END;
		cInfo.outputComponents := 1;
	END jinitColorDeconverter;

	(* *****       Ende Prozeduren von JPEGCConvert       ***** *)
	
	
	(* *****       Start Prozeduren von JPEGUpsample      ***** *)
	(* Dieser Abschnitt beinhaltet Upsampling Prozeduren. Input Data wird in "rowGroups" gerechnet
		Eine rowGroup ist vSampFactor * DCTScaledSize / minDCTScaledSize Sample Zeilen von 
		jedem Farbkomponenten *)
	
	(* Initialisierung fuer einen Upsampling Pass *)
	PROCEDURE startPassUpsample(cInfo: CInfoPtr);
	BEGIN
		cInfo.upsample.nextRowOut := cInfo.maxVSampFactor;
		cInfo.upsample.rowsToGo := cInfo.outputHeight;
	END startPassUpsample;
	
	(* Control Routine fuers Upsampling. Jeder Farbkomponent wird separat behandelt.
		Upsampling wird mit einer rowGroup aufsmal  gemacht, danach wird je Zeile die
		Farbkonvertierung durchgefuehrt. *)
	PROCEDURE sepUpsample(cInfo: CInfoPtr; inputBuf: JSampImage; VAR inRowGroupCtr: LONGINT;
											inRowGroupsAvail: LONGINT; outputBuf: JSampArray; 
											VAR outRowCtr: LONGINT; outRowsAvail: LONGINT);
	VAR
		ci: INTEGER;
		compptr: JPEGCompInfoPtr;
		numRows,inRowCtr: LONGINT;
	BEGIN
		IF cInfo.upsample.nextRowOut >= cInfo.maxVSampFactor THEN
			FOR ci := 0 TO cInfo.numComponents -1 DO
				compptr := cInfo.compInfo[ci];
				inRowCtr := inRowGroupCtr * cInfo.upsample.rowGroupHeight[ci];
				IF cInfo.upsample.colorBuf[ci] = NIL THEN NEW(cInfo.upsample.colorBuf[ci]) END;
				cInfo.upsample.methods[ci](cInfo,compptr,inputBuf.comp[ci],inRowCtr,
													cInfo.upsample.colorBuf[ci]);
			END;
			cInfo.upsample.nextRowOut := 0;
		END;
		
		numRows := cInfo.maxVSampFactor - cInfo.upsample.nextRowOut;
		IF numRows > cInfo.upsample.rowsToGo THEN
			numRows := cInfo.upsample.rowsToGo
		END;
		DEC(outRowsAvail,outRowCtr);
		IF numRows > outRowsAvail THEN numRows := outRowsAvail END;
		
		cInfo.cconvert.colorConvert(cInfo,cInfo.upsample.colorBuf,cInfo.upsample.nextRowOut,
											outputBuf,outRowCtr,SHORT(numRows));
		
		INC(outRowCtr,numRows);
		DEC(cInfo.upsample.rowsToGo,numRows);
		cInfo.upsample.nextRowOut := SHORT(cInfo.upsample.nextRowOut + numRows);
		IF cInfo.upsample.nextRowOut >= cInfo.maxVSampFactor THEN INC(inRowGroupCtr) END;
	END sepUpsample;
	
	(* Kein Upsampling notwendig. Output Zeiger zeigen auf Werte der Input Zeiger *)
	PROCEDURE fullsizeUpsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		x: INTEGER;
	BEGIN
		x:=0;
		WHILE x < cInfo.maxVSampFactor DO
			outputData.row[x] := inputData.row[x + inRowCtr];
			
			INC(x);
		END;
	END fullsizeUpsample;
	
	(* nicht erwuenschte Farbkomponenten werden ausgelassen und keine Farbkonvertierung
		durchgefuehrt *)
	PROCEDURE noopUpsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		x: INTEGER;
	BEGIN
		x:=0;
		WHILE x < cInfo.maxVSampFactor DO
			outputData.row[x] := NIL;
			INC(x);
		END;
	END noopUpsample;
	
	(* Behandelt seltene Scaling Raten wie 3:1 oder 4:1 *)
	PROCEDURE intUpsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		inptr,outptr : JSampRow;
		invalue: CHAR;
		h,outOffset,inOffset,outend,hExpand,vExpand,inrow,outrow : INTEGER;
	BEGIN
		hExpand := cInfo.upsample.hExpand[compptr.componentIndex];
		vExpand := cInfo.upsample.vExpand[compptr.componentIndex];
		inrow := SHORT(inRowCtr);
		outrow := 0;
		WHILE outrow < (cInfo.maxVSampFactor) DO
			inptr := inputData.row[inrow];
			outptr := outputData.row[outrow];
			outend := SHORT(cInfo.outputWidth);
			outOffset := 0;
			inOffset := 0;
			WHILE outOffset < outend DO
				invalue := inptr[inOffset];
				INC(inOffset);
				FOR h := 0 TO hExpand -1 DO
					outptr[outOffset] := invalue;
					INC(outOffset);
				END;
			END;
			IF vExpand > 1 THEN
				jcopySampleRows(outputData,outrow,outputData,outrow + 1,vExpand - 1,cInfo.outputWidth);
			END;
			INC(inrow);
			INC(outrow,vExpand);
		END;
	END intUpsample;
	
	(* Schnelle Behandlung von 2:1 Horizontal und 1:1 Vertikal *)
	PROCEDURE h2v1Upsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		inptr,outptr : JSampRow;
		invalue: CHAR;
		h,outOffset,inOffset,outend,inrow : INTEGER;
	BEGIN
		inrow := SHORT(inRowCtr);
		FOR h := 0 TO cInfo.maxVSampFactor - 1 DO
			inptr := inputData.row[inrow];
			outptr := outputData.row[h];
			outend := SHORT(cInfo.outputWidth);
			outOffset := 0;
			inOffset := 0;
			WHILE outOffset < outend DO
				invalue := inptr[inOffset];
				INC(inOffset);
				outptr[outOffset] := invalue;
				INC(outOffset);
				outptr[outOffset] := invalue;
				INC(outOffset);
			END;
			INC(inrow);
		END;
	END h2v1Upsample;
	
	(* Schnelle Behandlung von 2:1 Horizontal und 2:1 Vertikal *)
	PROCEDURE h2v2Upsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		inptr,outptr : JSampRow;
		invalue: CHAR;
		outOffset,inOffset,outend,inrow,outrow : INTEGER;
	BEGIN
		inrow := SHORT(inRowCtr);
		outrow := 0;
		WHILE outrow < (cInfo.maxVSampFactor) DO
			inptr := inputData.row[inrow];
			outptr := outputData.row[outrow];
			outend := SHORT(cInfo.outputWidth);
			outOffset := 0;
			inOffset := 0;
			WHILE outOffset < outend DO
				invalue := inptr[inOffset];
				INC(inOffset);
				outptr[outOffset] := invalue;
				INC(outOffset);
				outptr[outOffset] := invalue;
				INC(outOffset);
			END;
			jcopySampleRows(outputData,outrow,outputData,outrow + 1,1,cInfo.outputWidth);
			INC(inrow);
			INC(outrow,2);
		END;
	END h2v2Upsample;
	
	(* Fancy Behandlung von 2:1 Horizontal und 1:1 Vertikal. Hier wird eine lineare Interpolation
		zwischen Pixelzentren angewendet -> "Triangle Filter" *)
	PROCEDURE h2v1FancyUpsample(cInfo: CInfoPtr; compptr: JPEGCompInfoPtr;
											 inputData: JSampArray; inRowCtr: LONGINT;
											 outputData: JSampArray);
	VAR
		inptr,outptr : JSampRow;
		invalue: CHAR;
		outOffset,inOffset,inrow,invalueb : INTEGER;
		colctr: LONGINT;
	BEGIN
		inrow := SHORT(inRowCtr);
		WHILE inrow < (cInfo.maxVSampFactor + inRowCtr) DO
			inptr := inputData.row[inrow];
			outptr := outputData.row[inrow - inRowCtr];
			outOffset := 0;
			inOffset := 0;
			invalue := inptr[inOffset];
			INC(inOffset);
			outptr[outOffset] := invalue;
			INC(outOffset);
			outptr[outOffset] := 
					CHR(BIT.LLSH(ORD(invalue)*3 + ORD(inptr[inOffset]) + 2, -2));
			INC(outOffset);
			
			FOR colctr := 0 TO compptr.downSampledWidth - 3 DO
				invalueb := ORD(inptr[inOffset]) * 3;
				INC(inOffset);
				outptr[outOffset] := 
						CHR(BIT.LLSH(invalueb + ORD(inptr[inOffset-2]) + 1, -2));
				INC(outOffset);
				outptr[outOffset] := 
						CHR(BIT.LLSH(invalueb + ORD(inptr[inOffset]) + 2, -2));
				INC(outOffset);
			END;
			
			invalue := inptr[inOffset];
			INC(inOffset);
			outptr[outOffset] := 
					CHR(BIT.LLSH(ORD(invalue)*3 + ORD(inptr[inOffset-1]) + 1, -2));
			INC(outOffset);
			outptr[outOffset] := invalue;
			INC(outOffset);
			
			INC(inrow);
		END;
	END h2v1FancyUpsample;
	
	(* Initialisierung des Upsampling Vorganges *)
	PROCEDURE jinitUpsampler(cInfo: CInfoPtr);
	VAR
		i,ci,hInGroup,vInGroup,hOutGroup,vOutGroup: INTEGER;
		needBuffer,doFancy: BOOLEAN;
		compptr: JPEGCompInfoPtr;
	BEGIN
		NEW(cInfo.upsample);
		cInfo.upsample.upsample := sepUpsample;
		cInfo.upsample.needContextRows := FALSE;
		IF cInfo.CCIR601Sampling THEN
			ErrMsg("CCIR601 not implemented", 45);  RETURN
		END;
		doFancy := (cInfo.doFancyUpsampling) & (cInfo.minDCTScaledSize > 1);
 
		FOR ci:=0 TO cInfo.numComponents -1 DO
			compptr := cInfo.compInfo[ci];
			hInGroup := (LONG(compptr.hSampFactor) * compptr.DCTScaledSize) 
								DIV cInfo.minDCTScaledSize;
			vInGroup := (LONG(compptr.vSampFactor) * compptr.DCTScaledSize) 
								DIV cInfo.minDCTScaledSize;
			hOutGroup := cInfo.maxHSampFactor;
			vOutGroup := cInfo.maxVSampFactor;
			cInfo.upsample.rowGroupHeight[ci] := vInGroup;
			needBuffer := TRUE;
			
			IF ~compptr.componentNeeded THEN
				cInfo.upsample.methods[ci] := noopUpsample;
				needBuffer := FALSE;
			ELSIF (hInGroup = hOutGroup) & (vInGroup = vOutGroup) THEN
				cInfo.upsample.methods[ci] := fullsizeUpsample;
				needBuffer := FALSE;
			ELSIF ((hInGroup * 2) = hOutGroup) & (vInGroup = vOutGroup) THEN
				IF doFancy & (compptr.downSampledWidth >2) THEN
					cInfo.upsample.methods[ci] := h2v1FancyUpsample;
				ELSE
					cInfo.upsample.methods[ci] := h2v1Upsample;
				END;
			ELSIF ((hInGroup * 2) = hOutGroup) & ((vInGroup * 2) = vOutGroup) THEN
				cInfo.upsample.methods[ci] := h2v2Upsample;
			ELSIF ((hOutGroup MOD hInGroup) = 0) & ((vOutGroup MOD vInGroup) = 0) THEN
				cInfo.upsample.methods[ci] := intUpsample;
				cInfo.upsample.hExpand[ci] := hOutGroup DIV hInGroup;
				cInfo.upsample.vExpand[ci] := vOutGroup DIV vInGroup;
			ELSE
				ErrMsg("Upsampling not possible", 46);  RETURN
			END;
			
			IF needBuffer THEN
				NEW(cInfo.upsample.colorBuf[ci]);
				FOR i:= 0 TO cInfo.maxVSampFactor DO
					NEW(cInfo.upsample.colorBuf[ci].row[i]);
				END;
			END;
		END;
	END jinitUpsampler;

	(* *****       Ende Prozeduren von JPEGUpsample       ***** *)
	
	
	(* *****       Start Prozeduren von JPEGQuant1        ***** *)
	(* Dieser Abschnitt beinhaltet eine 1-Pass Farbquantisierung. Dazu wird eine Farbtabelle mit
		gleichmaessig verteilten Farbwerten aufgebaut. Optional ist ein Floyd-Steinberg Dithering. *)

	(* Teilt die vorhandenen Farben auf die einzelnen Farbkomponenten auf *)
	PROCEDURE selectNColors(cInfo: CInfoPtr; VAR Ncolors: ARRAY OF INTEGER):INTEGER;
	VAR
		nc,maxColors,totalColors,iroot,i,j : LONGINT;
		temp: LONGINT;
		RGBOrder: ARRAY 3 OF SHORTINT;
	BEGIN
		RGBOrder[0] := RGBGREEN;
		RGBOrder[1] := RGBRED;
		RGBOrder[2] := RGBBLUE;
		maxColors := cInfo.desiredNumberOfColors;
		nc :=cInfo.outColorComponents;
		iroot := 1;
		
		REPEAT
			INC(iroot);
			temp := iroot;
			FOR i:=1 TO nc -1 DO
				temp := temp * iroot;
			END;
		UNTIL temp > maxColors;
		
		DEC(iroot);
		IF iroot < 2 THEN
			ErrMsg("not enough color values", 47);  RETURN 0
		END;
		
		totalColors := 1;
		FOR i:=0 TO nc -1 DO
			Ncolors[i] := SHORT(iroot);
			totalColors := iroot * totalColors;
		END;
		
		FOR i:=0 TO nc -1 DO
			IF cInfo.outColorSpace = JCSRGB THEN j:= RGBOrder[i] ELSE j:=i END;
			temp := totalColors DIV Ncolors[j];
			temp:= temp * (Ncolors[j] + 1);
			IF temp > maxColors THEN i:=nc
			ELSE
				INC(Ncolors[j]);
				totalColors := temp;
			END;
		END;
		RETURN SHORT(totalColors);
	END selectNColors;
	
	PROCEDURE largestInputValue(j, maxj: LONGINT): LONGINT;
	BEGIN
		RETURN ((2*j + 1) * MAXJSAMPLE + maxj) DIV (2*maxj);
	END largestInputValue;

	(* Erstellen der Farbtabelle und der Farbindex-Tabelle fuer die spaetere Quantifizierung der Farben *)
	PROCEDURE createColormap(cInfo: CInfoPtr);
	VAR
		totalColors, i, j, k, nci, blksize, blkdist, ptr, val: LONGINT;
		Ncolors: ARRAY MAXQCOMPS OF INTEGER;
	BEGIN
		totalColors := selectNColors(cInfo,Ncolors);
		NEW(cInfo.colorMap);
		blkdist := totalColors;
		
		FOR i:= 0 TO cInfo.outColorComponents - 1 DO
			nci := Ncolors[i];
			blksize := blkdist DIV  nci;
			FOR j:= 0 TO nci - 1 DO
				val := ENTIER(j * MAXJSAMPLE + (nci-1)/2) DIV (nci-1);
				ptr := j*blksize;
				WHILE ptr < totalColors DO
					FOR k:= 0 TO blksize - 1 DO
						cInfo.colorMap[i][ptr + k] := SHORT(val);
					END;
					INC(ptr,blkdist);
				END;
			END;
			
			blkdist := blksize;
			val := 0;
			k := largestInputValue(0,nci -1);
			FOR j:= 0 TO MAXJSAMPLE DO
				WHILE j > k DO
					INC(val);
					k := largestInputValue(val,nci - 1) 
				END;
				cInfo.cquant.colorIndex[i][j] := SHORT(val * blksize);
			END;
		END;
		cInfo.actualNumberOfColors := SHORT(totalColors);
	END createColormap;
	
	(* Farb Quantifizierung bei n-Farbkomponenten ohne Dithering *)
	PROCEDURE colorQuantize(cInfo: CInfoPtr; inputBuf: JSampArray; outputBuf: JSampArray; 
											outRowCtr:INTEGER; numRows: INTEGER);
	VAR
		pixcode,nc,ci,row,inOffset,outOffset: INTEGER;
		ptrin,ptrout: JSampRow;
		col,width: LONGINT;
	BEGIN
		nc := cInfo.outColorComponents;
		width := cInfo.outputWidth;
		FOR row := 0 TO numRows -1 DO
			ptrin := inputBuf.row[row];
			inOffset := 0;
			ptrout := outputBuf.row[row + outRowCtr];
			outOffset := 0;
			FOR col := 0 TO width -1 DO
				pixcode := 0;
				FOR ci := 0 TO nc -1 DO
					pixcode := pixcode + cInfo.cquant.colorIndex[ci][ORD(ptrin[inOffset])];
					INC(inOffset);
				END;
				ptrout[outOffset] := CHR(pixcode);
				INC(outOffset);
			END;
		END;
	END colorQuantize;
	
	(* Schnelle Farb Quantifizierung bei 3-Farbkomponenten ohne Dithering *)
	PROCEDURE colorQuantize3(cInfo: CInfoPtr; inputBuf: JSampArray; outputBuf: JSampArray; 
											outRowCtr:INTEGER; numRows: INTEGER);
	VAR
		pixcode,row,inOffset,outOffset: INTEGER;
		ptrin,ptrout: JSampRow;
		col,width: LONGINT;
	BEGIN
		width := cInfo.outputWidth;
		FOR row := 0 TO numRows -1 DO
			ptrin := inputBuf.row[row];
			inOffset := 0;
			ptrout := outputBuf.row[row + outRowCtr];
			outOffset := 0;
			FOR col := 0 TO width -1 DO
				pixcode := cInfo.cquant.colorIndex[0][ORD(ptrin[inOffset])];
				INC(inOffset);
				pixcode := pixcode + cInfo.cquant.colorIndex[1][ORD(ptrin[inOffset])];
				INC(inOffset);
				pixcode := pixcode + cInfo.cquant.colorIndex[2][ORD(ptrin[inOffset])];
				INC(inOffset);
				ptrout[outOffset] := CHR(pixcode);
				INC(outOffset);
			END;
		END;
	END colorQuantize3;
	
	(* Farbquantifizierung bei n Farbkomponenten mit Floyd-Steinberg Dithering *)
	PROCEDURE quantizeFSDither(cInfo: CInfoPtr; inputBuf: JSampArray; outputBuf: JSampArray; 
											outRowCtr:INTEGER; numRows: INTEGER);
	VAR
		cur,belowerr,bpreverr,bnexterr,delta,pixcode,nc,dir,dirnc,ci,row,inOffset,outOffset,errOffset: INTEGER;
		errorPtr: FSErrPtr;
		inputPtr,outputPtr: JSampRow;
		col,width,j: LONGINT;
		help: INTEGER;
	BEGIN
		nc := cInfo.outColorComponents;
		width := cInfo.outputWidth;
		FOR row := 0 TO numRows - 1 DO
			FOR j:= 0 TO width -1 DO 
				outputBuf.row[row + outRowCtr][j] := CHR(0);
			END;
			FOR ci:= 0 TO nc - 1 DO
				inputPtr := inputBuf.row[row];
				inOffset := ci;
				outputPtr := outputBuf.row[row + outRowCtr];
				outOffset := 0;
				IF cInfo.cquant.onOddRow THEN
					inOffset := SHORT(LONG(inOffset) + (width - 1) *nc);
					outOffset := SHORT(LONG(outOffset) + width -1);
					dir := -1;
					dirnc := -nc;
					errorPtr := cInfo.cquant.fsErrors[ci];
					errOffset := SHORT(width + 1);
				ELSE
					dir := 1;
					dirnc := nc;
					errorPtr := cInfo.cquant.fsErrors[ci];
					errOffset := 0;
				END;
				
				cur := 0;
				belowerr := 0;
				bpreverr := 0;
				col := width;
				WHILE col > 0 DO
					cur := SHORT(ASH(cur + errorPtr[dir + errOffset] + 8,-4));
					cur := cur + ORD(inputPtr[inOffset]);
					cur := rangeLimit2(cur);
					pixcode := cInfo.cquant.colorIndex[ci][cur];
					help := ORD(outputPtr[outOffset]);
					outputPtr[outOffset] := CHR(help + pixcode);
					cur := cur - cInfo.colorMap[ci][pixcode];
					bnexterr := cur;
					delta := cur * 2;
					INC(cur,delta);
					errorPtr[errOffset] := bpreverr + cur;
					INC(cur,delta);
					bpreverr := belowerr + cur;
					belowerr := bnexterr;
					INC(cur,delta);
					INC(inOffset,dirnc);
					INC(outOffset,dir);
					INC(errOffset,dir);
					DEC(col);
				END;
				
				errorPtr[errOffset] := bpreverr;
			END;
			cInfo.cquant.onOddRow := ~cInfo.cquant.onOddRow;
		END;
	END quantizeFSDither;
	
	(* Initialisierung fuer die 1-Pass Quantifizierung *)
	PROCEDURE jinit1PassQuantizer(cInfo: CInfoPtr);
	VAR
		i,j: INTEGER;
	BEGIN
		NEW(cInfo.cquant);
		IF cInfo.ditherMode = DitherFS THEN
			cInfo.cquant.colorQuantize := quantizeFSDither;
			cInfo.cquant.onOddRow := FALSE;
			FOR i:= 0 TO cInfo.outColorComponents - 1 DO
				NEW(cInfo.cquant.fsErrors[i]);
				FOR j:= 0 TO JPEGMAXDIMENSION + 1 DO
					cInfo.cquant.fsErrors[i][j] := 0;
				END;
			END;
		ELSIF cInfo.ditherMode = DitherNone THEN
			IF cInfo.outColorComponents = 3 THEN
				cInfo.cquant.colorQuantize := colorQuantize3;
			ELSE
				cInfo.cquant.colorQuantize := colorQuantize;
			END;
		ELSE
			ErrMsg("unknown dither mode", 48);  RETURN
		END;
		createColormap(cInfo);
	END jinit1PassQuantizer;
	
	(* *****        Ende Prozeduren von JPEGQuant1      ***** *)
	
	
	(* *****       Start Prozeduren von JPEGPost        ***** *)
	(* Dieser Abschnitt behandelt den Kontroller fuer die Schritte, die nach dem eigentlichen
		Dekomprimieren anfallen. Diese Umfassen:
		1. Upsamling
		2. Farbkonvertierung
		3. Farbquantifizierung *)
	
	(* Steuerung des Post-Kontrollers *)	
	PROCEDURE postProcess1Pass(cInfo: CInfoPtr; inputBuf: JSampImage; VAR inRowGroupCtr,
											 inRowGroupsAvail: LONGINT; outputBuf: JSampArray; 
											 VAR outRowCtr: LONGINT;VAR outRowsAvail: LONGINT);
	VAR
		numRows,maxRows : LONGINT;
	BEGIN
		maxRows := outRowsAvail - outRowCtr;
		IF maxRows > cInfo.post.stripHeight THEN maxRows := cInfo.post.stripHeight END;
		numRows := 0;
		cInfo.upsample.upsample(cInfo, inputBuf, inRowGroupCtr, inRowGroupsAvail, cInfo.post.buffer, numRows, maxRows);
		cInfo.cquant.colorQuantize(cInfo,cInfo.post.buffer,outputBuf,SHORT(outRowCtr),SHORT(numRows));
		INC(outRowCtr,numRows);
	END postProcess1Pass;
	
	(* Initialisierung fuer einen Pass des Post-Kontrollers *)
	PROCEDURE startPassPost(cInfo: CInfoPtr; passMode:SHORTINT);
	BEGIN
		IF passMode = JBUFPASSTHRU THEN
			cInfo.post.postProcessData := postProcess1Pass;
		ELSE
			ErrMsg("unknown pass mode", 49)
		END;
	END startPassPost;
	
	(* Initialisierung des Post-Kontrollers *)
	PROCEDURE jinitDPostController(cInfo: CInfoPtr; needFullBuffer:BOOLEAN);
	VAR
		i: INTEGER;
	BEGIN
		NEW(cInfo.post);
		cInfo.post.wholeImage := FALSE;
		cInfo.post.stripHeight := cInfo.maxVSampFactor;
		IF needFullBuffer THEN
			ErrMsg("2-pass mode not implemented", 50)
		ELSE
			NEW(cInfo.post.buffer);
			FOR i:=0 TO cInfo.maxVSampFactor -1 DO
				NEW(cInfo.post.buffer.row[i]);
			END;
		END;
	END jinitDPostController;
	
	(* *****      Ende Prozeduren von JPEGPost      ***** *)

	(* ******************************************************** *)
	
	(* *****      Start Proceduren von JPEGMain        ***** *)
	(* Dieser Abschnitt ist die Schnittstelle zwischen Koeffizienten-Kontroller und Post-Kontroller.
		Von hier aus werden beide aufgerufen *)
	
	(* Steuerung des Main-Kontrollers *)
	PROCEDURE processDataSimpleMain(cInfo: CInfoPtr; outputBuf: JSampArray; 
													VAR outRowCtr:LONGINT; outRowsAvail:LONGINT);
	VAR
		rowGroupsAvail: LONGINT;
	BEGIN
		IF ~cInfo.main.bufferFull THEN
			IF ~cInfo.coef.decompressData(cInfo,cInfo.main.buffer) THEN RETURN END;
			cInfo.main.bufferFull := TRUE;
		END;
		
		rowGroupsAvail := cInfo.minDCTScaledSize;
		cInfo.post.postProcessData(cInfo,cInfo.main.buffer,cInfo.main.rowGroupCtr,rowGroupsAvail,
											outputBuf,outRowCtr,outRowsAvail);
		IF cInfo.main.rowGroupCtr >= rowGroupsAvail THEN
			cInfo.main.bufferFull := FALSE;
			cInfo.main.rowGroupCtr :=0;
		END;
	END processDataSimpleMain;

	(* Intitialisierung des Main-Contollers fuer einen Pass *)
	PROCEDURE startPassMain(cInfo: CInfoPtr; passMode:SHORTINT);
	BEGIN
		cInfo.main.numChunks := cInfo.outputHeight;
		
		CASE passMode OF
			JBUFPASSTHRU:
				IF cInfo.rawDataOut THEN RETURN END;
				IF cInfo.upsample.needContextRows THEN
					ErrMsg("context rows not implemented", 51)
				ELSE
					cInfo.main.processData := processDataSimpleMain;
				END;
				cInfo.main.bufferFull:= FALSE;
				cInfo.main.rowGroupCtr := 0;
		ELSE
			ErrMsg("unknown buffer mode", 52)
		END;
	END startPassMain;

	(* Generelle Initialisierung des Main-Kontrollers *)
	PROCEDURE jinitDMainController(cInfo: CInfoPtr; needFullBuffer:BOOLEAN);
	VAR
		ci,rgroup,ngroups : INTEGER;
		compptr : JPEGCompInfoPtr;
		t, i : LONGINT;
	BEGIN
		NEW(cInfo.main);
		IF needFullBuffer THEN
			ErrMsg("full buffer mode not implemented", 53);  RETURN
		END;
		
		IF cInfo.rawDataOut THEN RETURN END;
		
		IF cInfo.upsample.needContextRows THEN
			ErrMsg("context rows not implemented", 54);  RETURN
		ELSE
			ngroups := cInfo.minDCTScaledSize;
		END;
		NEW(cInfo.main.buffer);
		FOR ci := 0 TO cInfo.numComponents - 1 DO
			compptr := cInfo.compInfo[ci];
			t := (LONG(LONG(compptr.vSampFactor)) * LONG(compptr.DCTScaledSize))
							DIV LONG(cInfo.minDCTScaledSize);
			rgroup := SHORT(t);
			NEW(cInfo.main.buffer.comp[ci]);
			FOR i:=0 TO LONG(rgroup) * LONG(ngroups) -1 DO
				NEW(cInfo.main.buffer.comp[ci].row[i]);
			END
		END;
	END jinitDMainController;
	
	(* *****       Ende Proceduren von JPEGMain       ***** *)
	
	
	(* *****       Start Prozeduren von JPEGMaster       ***** *)
	(* Dieser Abschnitt beinhaltet die Hauptkontrolllogik der Dekomprimierung *)
	
	(* Hilfsprozedur fuers richtige Aufrunden *)
	PROCEDURE roundUp(a,b: LONGINT):LONGINT;
	BEGIN
		RETURN ENTIER((a + b -1) / b);
	END roundUp;
	
	(* Hier werden wichtige Berechnungen ueber Hoehe, Breite etc des Bildes gemacht, ebenfalls
		wird die Anzahl der Output-Farbkomponenten bestimmt *)
	PROCEDURE jpegCalcOutputDim(cInfo: CInfoPtr);
	VAR
		ci,ssize: INTEGER;
		compptr: JPEGCompInfoPtr;
	BEGIN
		IF cInfo.numComponents = 1 THEN
			cInfo.compInfo[0].hSampFactor := 1;
			cInfo.compInfo[0].vSampFactor := 1;
		END;
		cInfo.maxHSampFactor := 1;
		cInfo.maxVSampFactor := 1;
		FOR ci:=0 TO cInfo.numComponents -1 DO
			compptr:= cInfo.compInfo[ci];
			IF (compptr.hSampFactor <= 0) OR (compptr.hSampFactor > MAXSAMPFACTOR)
			OR (compptr.vSampFactor <= 0) OR (compptr.vSampFactor > MAXSAMPFACTOR) 
			THEN
				ErrMsg("bad sample factor", 55); RETURN
			END;
			IF cInfo.maxHSampFactor < compptr.hSampFactor THEN
				cInfo.maxHSampFactor :=compptr.hSampFactor
			END;
			IF cInfo.maxVSampFactor < compptr.vSampFactor THEN
				cInfo.maxVSampFactor :=compptr.vSampFactor
			END;
		END;

		IF (cInfo.scaleNum * 8) <= cInfo.scaleDenom THEN
			cInfo.outputWidth := roundUp(cInfo.imageWidth,8);
			cInfo.outputHeight := roundUp(cInfo.imageHeight,8);
			cInfo.minDCTScaledSize := 1;
		ELSIF (cInfo.scaleNum * 4) <= cInfo.scaleDenom THEN
			cInfo.outputWidth := roundUp(cInfo.imageWidth,4);
			cInfo.outputHeight := roundUp(cInfo.imageHeight,4);
			cInfo.minDCTScaledSize := 2;
		ELSIF (cInfo.scaleNum * 2) <= cInfo.scaleDenom THEN
			cInfo.outputWidth := roundUp(cInfo.imageWidth,2);
			cInfo.outputHeight := roundUp(cInfo.imageHeight,2);
			cInfo.minDCTScaledSize := 4;
		ELSE
			cInfo.outputWidth := cInfo.imageWidth;
			cInfo.outputHeight := cInfo.imageHeight;
			cInfo.minDCTScaledSize := DCTSIZE;
		END;
		FOR ci:=0 TO cInfo.numComponents -1 DO
			compptr:= cInfo.compInfo[ci];
			ssize := cInfo.minDCTScaledSize;
			WHILE (ssize < DCTSIZE) & 
					  ((LONG(compptr.hSampFactor) * ssize * 2) <= 
					  (cInfo.maxHSampFactor * cInfo.minDCTScaledSize)) &
					  ((LONG(compptr.vSampFactor) * ssize * 2) <= 
					  (cInfo.maxVSampFactor * cInfo.minDCTScaledSize)) DO
				ssize := ssize * 2;
			END;
			compptr.DCTScaledSize := ssize;
		END;
		
		CASE cInfo.outColorSpace OF
			JCSGRAYSCALE:
				cInfo.outColorComponents := 1;
		| JCSRGB:
				cInfo.outColorComponents := 3;
		| JCSYCBCR:
				cInfo.outColorComponents := 3;
		| JCSCMYK:
				cInfo.outColorComponents := 4;
		| JCSYCCK:
				cInfo.outColorComponents := 4;
		ELSE
				cInfo.outColorComponents := cInfo.numComponents;
		END;
		cInfo.outputComponents := 1;
		cInfo.recOutbufHeight := 1;
		
		FOR ci:=0 TO cInfo.numComponents -1 DO
			compptr:= cInfo.compInfo[ci];
			compptr.widthInBlocks := roundUp(cInfo.imageWidth * LONG(compptr.hSampFactor), 
														  cInfo.maxHSampFactor * DCTSIZE);
			compptr.heightInBlocks := roundUp(cInfo.imageHeight * LONG(compptr.vSampFactor), 
														   cInfo.maxVSampFactor * DCTSIZE); 
			compptr.downSampledWidth := 
					roundUp(cInfo.imageWidth * LONG(compptr.hSampFactor) * compptr.DCTScaledSize, 
								cInfo.maxHSampFactor * DCTSIZE);
			compptr.downSampledHeight := 
					roundUp(cInfo.imageHeight * LONG(compptr.vSampFactor) * compptr.DCTScaledSize, 
								cInfo.maxVSampFactor * DCTSIZE);
			compptr.componentNeeded := TRUE;
		END;
		
		cInfo.totaliMCURows := 
					roundUp(cInfo.imageHeight, cInfo.maxVSampFactor * DCTSIZE);
		
	END jpegCalcOutputDim;

	(* Initialisierungen pro JPEG Scan *)
	PROCEDURE perScanSetup(cInfo:CInfoPtr);
	VAR
		ci,mcublks,tmp: INTEGER;
		compptr: JPEGCompInfoPtr;
	BEGIN
		IF cInfo.compsInScan = 1 THEN
			compptr := cInfo.curCompInfo[0];
			cInfo.MCUsPerRow := compptr.widthInBlocks;
			cInfo.MCURowsInScan := compptr.heightInBlocks;
			
			compptr.MCUWidth := 1;
			compptr.MCUHeight := 1;
			compptr.MCUBlocks := 1;
			compptr.MCUSampleWidth := compptr.DCTScaledSize;
			compptr.lastColWidth := 1;
			compptr.lastRowHeight := 1;
			cInfo.blocksInMCU := 1;
			cInfo.MCUMembership[0] := 0;
		ELSE
			IF (cInfo.compsInScan <= 0) OR (cInfo.compsInScan > MAXCOMPSINSCAN) THEN
				ErrMsg("bad scan number", 56);  RETURN
			END;
			cInfo.MCUsPerRow := 
					roundUp(cInfo.imageWidth, LONG(cInfo.maxHSampFactor) * DCTSIZE);
			cInfo.MCURowsInScan := 
					roundUp(cInfo.imageHeight, LONG(cInfo.maxVSampFactor) * DCTSIZE);
			cInfo.blocksInMCU := 0;
			
			FOR ci := 0 TO cInfo.compsInScan - 1 DO
				compptr := cInfo.curCompInfo[ci];
				compptr.MCUWidth := compptr.hSampFactor;
				compptr.MCUHeight := compptr.vSampFactor;
				compptr.MCUBlocks := SHORT(LONG(compptr.MCUWidth) * LONG(compptr.MCUHeight));
				compptr.MCUSampleWidth := SHORT(LONG(compptr.MCUWidth) * LONG(compptr.DCTScaledSize));
				
				tmp :=SHORT(compptr.widthInBlocks MOD compptr.MCUWidth);
				IF tmp = 0 THEN tmp := compptr.MCUWidth END;
				compptr.lastColWidth := tmp;
				
				tmp :=SHORT(compptr.heightInBlocks MOD compptr.MCUHeight);
				IF tmp = 0 THEN tmp := compptr.MCUHeight END;
				compptr.lastRowHeight := tmp;
				mcublks := compptr.MCUBlocks;
				
				IF (cInfo.blocksInMCU + mcublks) > MAXBLOCKSINMCU THEN
					ErrMsg("bad MCU size", 57);  RETURN
				END;
				
				WHILE (mcublks) > 0 DO
					DEC(mcublks);
					cInfo.MCUMembership[cInfo.blocksInMCU] := ci;
					INC(cInfo.blocksInMCU);
				END;
			END;
		END;
	END perScanSetup;
	
	(* Auswahl der zu benuetzenden Dekomprimierungsroutinen *)
	PROCEDURE masterSelection(cInfo: CInfoPtr);
	BEGIN
		
		cInfo.master.eoiProcessed:= FALSE;
		cInfo.master.passNumber := 0;
		cInfo.master.needPostPass := FALSE;
		IF cInfo.compsInScan = cInfo.numComponents THEN
			cInfo.master.passType := MainPass;
			cInfo.master.totalPasses := 1;
		ELSE
			ErrMsg("multiscan not implemented", 58); RETURN
		END;
		
		cInfo.master.usingMergedUpsample := FALSE; (* Merge nicht implementiert *)
		
		IF cInfo.rawDataOut THEN
			ErrMsg("rawdataout not implemented", 59); RETURN
		END;
		
		cInfo.twoPassQuantize := FALSE;
		jinit1PassQuantizer(cInfo);
		jinitColorDeconverter(cInfo);
		jinitUpsampler(cInfo);
		jinitDPostController(cInfo,cInfo.master.needPostPass);
		jinitIDCT(cInfo);
		IF cInfo.arithCode THEN
			ErrMsg("arith. decoding not implemented", 60); RETURN
		ELSE
			jinitHuffDecoder(cInfo);
		END;
		jinitDCoefController(cInfo,(cInfo.master.passType = PrereadPass));
		jinitDMainController(cInfo,FALSE);
	END masterSelection;

	(* weitere Initialisierungen pro Pass *)
	PROCEDURE prepareForPass(cInfo: CInfoPtr);
	BEGIN
		CASE cInfo.master.passType OF
			MainPass:
				perScanSetup(cInfo);
				cInfo.master.isLastPass := ~ cInfo.master.needPostPass;
				IF (~ cInfo.rawDataOut) THEN
					startPassUpsample(cInfo);
					startPassPost(cInfo, JBUFPASSTHRU)
				END;
				startInputPassIDCT(cInfo);
				startOutputPassIDCT(cInfo);
				startPassHuff(cInfo);
				startPassCoef(cInfo, JBUFPASSTHRU);
				startPassMain(cInfo, JBUFPASSTHRU);
		ELSE
			ErrMsg("unknown pass mode", 61)
		END;
	END prepareForPass;
	
	(* Abschliessen des Dekomprimierens *)
	PROCEDURE finishPass(cInfo: CInfoPtr);
	BEGIN
		CASE cInfo.master.passType OF
			MainPass:
				INC(cInfo.master.passNumber);
				cInfo.master.passType := PostPass;
		| OutputPass:
				INC(cInfo.master.passNumber);
				cInfo.master.passType := PostPass;
		ELSE
			ErrMsg("unknown pass mode", 62)
		END;
	END finishPass;
	
	(* Initialisierung des MasterKonrollers *)
	PROCEDURE jinitMasterDecompress(cInfo: CInfoPtr);
	BEGIN
		NEW(cInfo.master);
		masterSelection(cInfo);
	END jinitMasterDecompress;
	
	(* *****       Ende Prozeduren von JPEGMaster       ***** *)
	
	(* ******************************************************* *)
	
	(* *****       Start Prozeduren von JPEGOut         ***** *)
	
	(* numScanLines Zeilen im Picture schreiben *)
	PROCEDURE putPixelRows(cInfo: CInfoPtr; dest: DestPtr; numScanLines:LONGINT);
	VAR
		col,i,zeile: LONGINT;
		color: INTEGER;
	BEGIN
		i:=0;
		WHILE i < numScanLines DO
			zeile := dest.pict.height - dest.curOutputRow -1;
			FOR col := 0 TO cInfo.outputWidth - 1 DO
				color := ORD(dest.buffer.row[i][col]) + AnzResFarben;
				IF cInfo.colorMode = ColorsOld THEN
					color := dest.colors[color - AnzResFarben];
				END;
				dots[col] := color;
				(* P.Dot(dest.pict,color,SHORT(col),SHORT(zeile),D.replace); *)
			END;
			P.PutLine(dest.pict, dots^, 0, SHORT(zeile), SHORT(cInfo.outputWidth));
			INC(i);
			INC(dest.curOutputRow); 
		END;
	END putPixelRows;
	
	(* ColorMap des Pictures im Oberon Pict Format schreiben *)
	PROCEDURE writeColorMap(cInfo: CInfoPtr; dest: DestPtr);
	VAR
		numColors,i: INTEGER;
	BEGIN
		numColors := cInfo.actualNumberOfColors - 1;
		IF cInfo.colorMap # NIL THEN
			IF cInfo.outColorComponents = 3 THEN
				FOR i:=0 TO numColors DO
					P.SetColor(dest.pict,i + AnzResFarben,cInfo.colorMap[0][i],cInfo.colorMap[1][i],cInfo.colorMap[2][i]);
				END;
			ELSE
				FOR i:=0 TO numColors DO
					P.SetColor(dest.pict,i + AnzResFarben,cInfo.colorMap[0][i],cInfo.colorMap[0][i],cInfo.colorMap[0][i]);
				END;
			END;
		ELSE
			FOR i:=0 TO numColors DO
				P.SetColor(dest.pict,i + AnzResFarben,i,i,i);
			END;
		END;
		
		IF i > AnzFarben THEN
			ErrMsg("too many colors", 99);
		END;
		
		WHILE i < AnzFarben DO
			P.SetColor(dest.pict,i + AnzResFarben,0,0,0);
			INC(i);
		END;
	END writeColorMap;
	
	PROCEDURE Max3(m1,m2,m3:INTEGER):INTEGER;
	BEGIN
		IF m1>m2 THEN
			IF m1 > m3 THEN
				RETURN m1
			ELSE
				RETURN m3
			END;
		ELSE
			IF m2 > m3 THEN
				RETURN m2
			ELSE
				RETURN m3
			END;
		END;
	END Max3;
	
	(* ColorMap des Pictures der vorhandenen Farbtabelle anpassen *)
	PROCEDURE adjustColorMap(cInfo: CInfoPtr; dest: DestPtr);
	VAR
		C,i, j ,minj, red,green,blue,x,y,z: INTEGER;
		r, g, b : ARRAY 256 OF INTEGER;
		min, d : LONGINT;
	BEGIN
		C := SHORT(ASH(1,D.Depth(0)));
		i := 0;
		WHILE i < C DO
			dest.colors[i] := i; D.GetColor(i,r[i],g[i],b[i]); 
			INC(i);
		END;
		i := 0;
		WHILE i < C DO
			red := cInfo.colorMap[0][i]; green := cInfo.colorMap[1][i];  blue := cInfo.colorMap[2][i];
			IF cInfo.outColorSpace = JCSGRAYSCALE THEN green := red; blue := red END;
			j := 0; min := MAX(LONGINT);
			WHILE j < C DO
				x := red - r[j]; y := green - g[j]; z := blue - b[j];  
				d := Max3(ABS(x),ABS(y),ABS(z));
				d := d*d + (LONG(x) * x + LONG(y)* y + LONG(z) * z);
				IF d < min THEN min := d; minj := j END;
				INC(j)
			END;
			dest.colors[i] := minj; INC(i);
		END;
	END adjustColorMap;
	
	(* Initialisieren des Output Files und der Output Datenstruktur *)
	PROCEDURE jinitDest(cInfo: CInfoPtr; dest: DestPtr);
	VAR
		rowWidth: LONGINT;
	BEGIN
		jpegCalcOutputDim(cInfo);  IF err # 0 THEN RETURN END;
		P.Create(dest.pict,SHORT(cInfo.outputWidth),SHORT(cInfo.outputHeight),8);
		dest.pict.handle := Handle; NEW(dots, cInfo.outputWidth);
		(* T.WriteString(W,"Width: ");T.WriteInt(W,cInfo.outputWidth,10);
		T.WriteString(W,"Height: ");T.WriteInt(W,cInfo.outputHeight,10); 
		T.WriteLn(W); T.Append(Oberon.Log,W.buf); *)
		dest.bufferHeight := 1;
		dest.curOutputRow := 0;
		rowWidth := cInfo.outputWidth;
		dest.dataWidth := rowWidth;
		WHILE (rowWidth MOD 4) # 0 DO INC(rowWidth) END;
		dest.rowWidth := rowWidth;
		dest.padBytes := SHORT(rowWidth - dest.dataWidth);
		
		NEW(dest.buffer);
		NEW(dest.buffer.row[0]);
	END jinitDest;
	
	(* *****        Ende Prozeduren von JPEGOut        ***** *)
	
	(* ********************************************************* *)

	(* *****        Prozeduren von JPEG Haupprogramm        ***** *)
	(* Dieser Abschnitt uebernimmt die Default Initialisationen des Dekompressions Objektes *)
	
	(* Initialisieren des Dekompressions Objektes: cInfo *)
	PROCEDURE jpegCreateDecompress(cInfo: CInfoPtr);
	VAR
		i:INTEGER;
	BEGIN
		cInfo.src := NIL;
		FOR i:=0 TO NUMQUANTTBLS -1 DO
			cInfo.quantTbl[i] := NIL;
		END;
		FOR i:=0 TO NUMHUFFTBLS -1 DO
			cInfo.dcHuffTbl[i]:=NIL;
			cInfo.acHuffTbl[i]:=NIL;
		END;
		cInfo.marker:=NIL;
		jinitMarkerReader(cInfo);
		cInfo.globalState:= DSTATESTART;
	END jpegCreateDecompress;
	
	(* Defaultwerte setzen *)
	PROCEDURE defaultDecompressParams(cInfo: CInfoPtr);
	VAR
		cid0,cid1,cid2:INTEGER;
	BEGIN
		CASE cInfo.numComponents OF
			1:
				cInfo.jpegColorSpace:= JCSGRAYSCALE;
				cInfo.outColorSpace := JCSGRAYSCALE;
		| 3:	
				IF cInfo.sawJFIFMarker THEN
					cInfo.jpegColorSpace:= JCSYCBCR;
				ELSIF cInfo.sawAdobeMarker THEN
					CASE cInfo.AdobeTransform OF
						0:
							cInfo.jpegColorSpace:= JCSRGB;
					| 1:	
							cInfo.jpegColorSpace:= JCSYCBCR;
					ELSE
							cInfo.jpegColorSpace:= JCSYCBCR;
					END;
				ELSE
					cid0:=cInfo.compInfo[0].componentID;
					cid1:=cInfo.compInfo[1].componentID;
					cid2:=cInfo.compInfo[2].componentID;
					IF (cid0=1) & (cid1=2) & (cid2=3) THEN
						cInfo.jpegColorSpace:= JCSYCBCR;
					ELSIF (cid0=82) & (cid1=71) & (cid2=66) THEN
						cInfo.jpegColorSpace:= JCSRGB;
					ELSE
						cInfo.jpegColorSpace:= JCSYCBCR;
					END;
				END;
				cInfo.outColorSpace := JCSRGB;
		| 4: ErrMsg("too many components", 63)
		ELSE
			ErrMsg("too many components", 64)
		END;
		
		cInfo.scaleNum:=1;
		cInfo.scaleDenom:=1;
		cInfo.outputGamma:=1.0;
		cInfo.rawDataOut:=FALSE;
		cInfo.twoPassQuantize:= FALSE;
		cInfo.ditherMode:= DitherFS; 
		cInfo.selectIDCT := Integer;
		cInfo.desiredNumberOfColors:= AnzFarben;
		cInfo.colorMap:= NIL;
		cInfo.doFancyUpsampling := TRUE;
					
	END defaultDecompressParams;
	
	(* Steuerung zum Lesen des InputFile Kopfes *)
	PROCEDURE jpegReadHeader(cInfo: CInfoPtr);
	VAR
		retcode:INTEGER;
	BEGIN
		IF cInfo.globalState = DSTATESTART THEN
			resetMarkerReader(cInfo);
			initSource(cInfo);
			cInfo.globalState := DSTATEINHEADER;
		ELSIF cInfo.globalState # DSTATEINHEADER THEN
			ErrMsg("unknown header state", 65);  RETURN
		END;
		
		retcode := readMarkers(cInfo);
		
		CASE retcode OF
			JPEGHEADEROK:
				defaultDecompressParams(cInfo);
				cInfo.globalState:= DSTATEREADY;
		| JPEGHEADERTABLESONLY:
				ErrMsg("no SOS blocks", 71);
		| JPEGSUSPENDED:
				ErrMsg("header block error", 71);
		END;
	END jpegReadHeader;
	
	(* Startender Dekomprimierung: Parameter setzen, pruefen ob Bilddaten im InputFile sind *)
	PROCEDURE jpegStartDecompress(cInfo: CInfoPtr);
	VAR
		chunkCtr,lastChunkCtr: LONGINT;
	BEGIN
		IF cInfo.globalState # DSTATEREADY THEN
			ErrMsg("bad state", 72);  RETURN
		END;
		jinitMasterDecompress(cInfo);
		IF err # 0 THEN RETURN END;
		
		LOOP
			prepareForPass(cInfo);
			IF cInfo.master.isLastPass THEN EXIT END;
			chunkCtr:=0;
			WHILE chunkCtr < cInfo.main.numChunks DO
				lastChunkCtr := chunkCtr;
				processDataSimpleMain(cInfo,NIL,chunkCtr,0);
				IF chunkCtr = lastChunkCtr THEN 
					ErrMsg("loop", 72);  RETURN
				END;
			END;
			finishPass(cInfo);
		END; (* Loop *)
		cInfo.outputScanline := 0;
		IF cInfo.rawDataOut THEN
			cInfo.globalState := DSTATERAWOK;
		ELSE
			cInfo.globalState := DSTATESCANNING;
		END;
	END jpegStartDecompress;
	
	(* maxLines Bildzeilen dekomprimieren und ausgeben *)
	PROCEDURE jpegReadScanlines(cInfo: CInfoPtr; scanlines: JSampArray; VAR maxLines:LONGINT):LONGINT;
	VAR
		rowCtr: LONGINT;
	BEGIN
		IF cInfo.globalState # DSTATESCANNING THEN
			ErrMsg("bad state", 73);  RETURN 0
		END;
		
		rowCtr:=0;
		cInfo.main.processData(cInfo,scanlines,rowCtr,maxLines);
		INC(cInfo.outputScanline,rowCtr);
		
		RETURN rowCtr;
	END jpegReadScanlines;
	
	(* Dekomprimieren beenden *)
	PROCEDURE jpegFinishDecompress(cInfo: CInfoPtr);
	BEGIN
		IF (cInfo.globalState = DSTATESCANNING)  OR (cInfo.globalState = DSTATERAWOK) THEN
			IF cInfo.outputScanline < cInfo.outputHeight THEN
				ErrMsg("unexpected end of file", 74);  RETURN
			END;
			finishPass(cInfo);
			cInfo.globalState := DSTATESTOPPING;
		ELSIF cInfo.globalState # DSTATESTOPPING THEN
			ErrMsg("bad state", 74);  RETURN
		END;
		
		IF ~cInfo.master.eoiProcessed THEN
			CASE readMarkers(cInfo) OF
				JPEGHEADEROK:
					ErrMsg("EOI expected", 74);
			| JPEGHEADERTABLESONLY:
			| JPEGSUSPENDED:
				ErrMsg("read error", 74)
			END;
		END;
	END jpegFinishDecompress;
	
	(* JPEG Hauptprozedur: Files oeffnen, Dekompressions und Outputobjekte generieren, Files schliessen *)
	(** JPEG.Decode Decode file to pict
		idct: Integer: use fast integer arithmetics
				Float: use (slow) Floatingpoint arithmetics
				Scale: use fast integer arithmetics and scale image by a factor of 2, 4 or 8
		factor: Scaling-factor for idct = Scale
		dither: DitherNone: no dithering
					DitheFS: Floyd Steinberg dithering
		colorMode: ColorsOld: use current display palette
							ColorsNew: build a new (orthogonal) palette
	*)
	PROCEDURE Decode*(file: F.File; VAR pict: P.Picture; idct, factor, dither, colorMode: INTEGER);
	VAR
		cInfo: CInfoPtr;
		dest: DestPtr;
		numScanlines: LONGINT;
		zaehler: LONGINT;
	BEGIN
		err := 0;
		NEW(cInfo);
		NEW(dest);
		dest.pict := pict;
		jpegCreateDecompress(cInfo);
		jpegInitSrc(cInfo,file);
		jpegReadHeader(cInfo);
		IF err#0 THEN RETURN END;
		IF idct =  Integer THEN cInfo.selectIDCT := Integer
		ELSIF idct = Scale THEN 
			cInfo.selectIDCT := Scale;
			cInfo.scaleDenom := factor;
		ELSE cInfo.selectIDCT := Float;
		END;
		IF dither = DitherNone THEN cInfo.ditherMode := DitherNone END;
				
		(*
		IF idct = Integer THEN
			T.WriteString(W,"IDCT Methode: Integer"); 
		ELSIF idct = Scale THEN
			T.WriteString(W,"IDCT Methode: Scale um Faktor: "); T.WriteInt(W,cInfo.scaleDenom,4); 
		ELSE
			T.WriteString(W,"IDCT Methode: Float");
		END;
		IF dither = DitherNone THEN
			T.WriteString(W,"   Kein Dithering ");
		ELSE
			T.WriteString(W,"   Floyd Steinberg Dithering ");
		END;
		*)
		cInfo.colorMode := colorMode;
		(*
		IF colorMode = ColorsNew THEN
			T.WriteString(W,"   Neue Farbtabelle ");
		ELSE
			T.WriteString(W,"   Alte Farbtabelle ");
		END;
		T.WriteLn(W); T.Append(Oberon.Log,W.buf);
		*)
		
		jinitDest(cInfo,dest);
		IF err # 0 THEN RETURN END;
		
		jpegStartDecompress(cInfo);
		
		IF colorMode = ColorsNew THEN
			writeColorMap(cInfo,dest);
		ELSE
			adjustColorMap(cInfo,dest);
		END;
		
		zaehler := 0;
		WHILE cInfo.outputScanline < cInfo.outputHeight DO
			numScanlines := jpegReadScanlines(cInfo,dest.buffer,dest.bufferHeight);
			zaehler := zaehler + numScanlines;
			putPixelRows(cInfo,dest,numScanlines);
		END;
		
		jpegFinishDecompress(cInfo);
	END Decode;
	
	(** JPEG.Pict [ "\" opts ] infile outfile
		opts:
			I: Integer idct
			F: Floatingpoint idct
			S: Integer idct with scaling
				2, 4, 8: Scaling factor
			Y: use Floyd Steinberg dithering
				C: build a new (orthogonal) palette
				O: use current display palette
			N: no dithering
	*)
	PROCEDURE Pict*;
	VAR
		inName,outName: ARRAY 32 OF CHAR;
		idct,dither,factor,colorMode,i: INTEGER;
		pict: P.Picture;
		fileOut,fileIn: F.File;
		len: LONGINT;
		S: T.Scanner;
		par: Oberon.ParList;
		doit: BOOLEAN;
	BEGIN
		dither := DitherFS;
		idct := Integer;
		factor := 2;
		colorMode := ColorsNew;
		doit := TRUE;
		
		par := Oberon.Par;
		T.OpenScanner(S,par.text,par.pos);
		T.Scan(S);
		
		IF (S.class = T.Char) & (S.c = Oberon.OptionChar) THEN
			T.Scan(S);
			IF S.class = T.Name THEN
				i := 0;
				WHILE i < S.len DO
					IF CAP(S.s[i]) = "I" THEN
						idct := Integer;
					ELSIF CAP(S.s[i]) = "F" THEN 
						idct := Float;
					ELSIF CAP(S.s[i]) = "S" THEN 
						idct := Scale;
					ELSIF S.s[i] = "2"  THEN 
						factor := 2;
					ELSIF S.s[i] = "4" THEN 
						factor := 4;
					ELSIF S.s[i] = "8" THEN 
						factor := 8;
					ELSIF CAP(S.s[i]) = "Y" THEN 
						dither := DitherFS;
					ELSIF CAP(S.s[i]) = "N" THEN 
						dither := DitherNone;
					ELSIF CAP(S.s[i]) = "C" THEN 
						colorMode := ColorsNew;
					ELSIF CAP(S.s[i]) = "O" THEN 
						colorMode := ColorsOld;
					END;
					INC(i);
				END;
			ELSE
				doit := FALSE;
			END;
			T.Scan(S);
		END;

		IF S.class = T.Name THEN
			COPY(S.s,inName);
		ELSE
			doit := FALSE;
		END;
		T.Scan(S);
		
		IF S.class = T.Name THEN
			COPY(S.s,outName);
		ELSE
			doit := FALSE;
		END;
		
		IF ~doit THEN
			(* T.WriteString(W, "JPEG: Ungueltige Eingabe");
			T.WriteLn(W); T.Append(Oberon.Log,W.buf); *)
		ELSE
			fileIn:=F.Old(inName);
			IF fileIn = NIL THEN
				(* T.WriteString(W, "Kein File unter folgendem Namen vorhanden: ");
				T.WriteString(W, inName);
				T.WriteLn(W);
				T.Append(Oberon.Log,W.buf); *)
			ELSE
				NEW(pict); Decode(fileIn,pict,idct,factor,dither,colorMode);
		
				IF pict # NIL THEN
					fileOut:=F.New(outName);
					(* T.WriteString(W,"OberonPicture - File:  "); *)
					P.Store(pict,fileOut,0,len); 
					(* T.WriteString(W,"Laenge: "); 
					T.WriteInt(W, len,10);
					T.WriteLn(W);
					T.Append(Oberon.Log,W.buf); *)
					F.Register(fileOut);
				END;
				F.Close(fileIn);
			END;
		END;
	END Pict;

	PROCEDURE Handle* (obj: Objects.Object; VAR msg: Objects.ObjMsg);
	BEGIN
		WITH obj: Pictures.Picture DO
			IF msg IS Objects.AttrMsg THEN
				WITH msg: Objects.AttrMsg DO 
					IF (msg.id = Objects.get) & (msg.name = "Gen") THEN
						msg.class := Objects.String; COPY("Pictures.NewPicture", msg.s); msg.res:=0 
					END;
				END;
			ELSIF msg IS Objects.FileMsg THEN
				WITH msg: Objects.FileMsg DO
					IF (msg.id = Objects.load) THEN
						Decode(Files.Base(msg.R), obj, Integer, 1, DitherFS, ColorsOld); 
						IF err = 0 THEN msg.len := Files.Length(Files.Base(msg.R)) ELSE msg.len := 0 END;
					ELSE
						Pictures.Handle(obj, msg)
					END;
				END
			ELSE 
				Pictures.Handle(obj, msg)
			END
		END
	END Handle;

	PROCEDURE InitPicture*;
	BEGIN Objects.NewObj.handle := Handle;
	END InitPicture;

	PROCEDURE NewPicture*;
		VAR P: Pictures.Picture;
	BEGIN NEW(P); P.handle := Handle; Objects.NewObj := P
	END NewPicture;

BEGIN
	ZAG[0] := 0; ZAG[1] := 1; ZAG[2] := 8; ZAG[3] := 16;
	ZAG[4] := 9; ZAG[5] := 2; ZAG[6] := 3; ZAG[7] := 10;
	
	ZAG[8] := 17; ZAG[9] := 24; ZAG[10] := 32; ZAG[11] := 25;
	ZAG[12] := 18; ZAG[13] := 11; ZAG[14] := 4; ZAG[15] := 5;
	
	ZAG[16] := 12; ZAG[17] := 19; ZAG[18] := 26; ZAG[19] := 33;
	ZAG[20] := 40; ZAG[21] := 48; ZAG[22] := 41; ZAG[23] := 34;
	
	ZAG[24] := 27; ZAG[25] := 20; ZAG[26] := 13; ZAG[27] := 6;
	ZAG[28] := 7; ZAG[29] := 14; ZAG[30] := 21; ZAG[31] := 28;
	
	ZAG[32] := 35; ZAG[33] := 42; ZAG[34] := 49; ZAG[35] := 56;
	ZAG[36] := 57; ZAG[37] := 50; ZAG[38] := 43; ZAG[39] := 36;
	
	ZAG[40] := 29; ZAG[41] := 22; ZAG[42] := 15; ZAG[43] := 23;
	ZAG[44] := 30; ZAG[45] := 37; ZAG[46] := 44; ZAG[47] := 51;
	
	ZAG[48] := 58; ZAG[49] := 59; ZAG[50] := 52; ZAG[51] := 45;
	ZAG[52] := 38; ZAG[53] := 31; ZAG[54] := 39; ZAG[55] := 46;
	
	ZAG[56] := 53; ZAG[57] := 60; ZAG[58] := 61; ZAG[59] := 54;
	ZAG[60] := 47; ZAG[61] := 55; ZAG[62] := 62; ZAG[63] := 63;
	
	ZAG[64] := 0; ZAG[65] := 0; ZAG[66] := 0; ZAG[67] := 0;
	ZAG[68] := 0; ZAG[69] := 0; ZAG[70] := 0; ZAG[71] := 0;
	
	ZAG[72] := 0; ZAG[73] := 0; ZAG[74] := 0; ZAG[75] := 0;
	ZAG[76] := 0; ZAG[77] := 0; ZAG[78] := 0; ZAG[79] := 0;
	

	ZIG[0] := 0; ZIG[1] := 1; ZIG[2] := 5; ZIG[3] := 6; 
	ZIG[4] := 14; ZIG[5] := 15; ZIG[6] := 27; ZIG[7] := 28;
	
	ZIG[8] := 2; ZIG[9] := 4; ZIG[10] := 7; ZIG[11] := 13; 
	ZIG[12] := 16; ZIG[13] := 26; ZIG[14] := 29; ZIG[15] := 42;
	
	ZIG[16] := 3; ZIG[17] := 8; ZIG[18] := 12; ZIG[19] := 17; 
	ZIG[20] := 25; ZIG[21] := 30; ZIG[22] := 41; ZIG[23] := 43;
	
	ZIG[24] := 9; ZIG[25] := 11; ZIG[26] := 18; ZIG[27] := 24; 
	ZIG[28] := 31; ZIG[29] := 40; ZIG[30] := 44; ZIG[31] := 53;
	
	ZIG[32] := 10; ZIG[33] := 19; ZIG[34] := 23; ZIG[35] := 32; 
	ZIG[36] := 39; ZIG[37] := 45; ZIG[38] := 52; ZIG[39] := 54;
	
	ZIG[40] := 20; ZIG[41] := 22; ZIG[42] := 33; ZIG[43] := 38; 
	ZIG[44] := 46; ZIG[45] := 51; ZIG[46] := 55; ZIG[47] := 60;
	
	ZIG[48] := 21; ZIG[49] := 34; ZIG[50] := 37; ZIG[51] := 47; 
	ZIG[52] := 50; ZIG[53] := 56; ZIG[54] := 59; ZIG[55] := 61;
	
	ZIG[56] := 35; ZIG[57] := 36; ZIG[58] := 48; ZIG[59] := 49; 
	ZIG[60] := 57; ZIG[61] := 58; ZIG[62] := 62; ZIG[63] := 63;
	
	
	FOR i:= 0 TO CENTERJSAMPLE - 1 DO RL[i] := i + CENTERJSAMPLE END;
	FOR i:= CENTERJSAMPLE TO 511 DO RL[i] :=  MAXJSAMPLE END;
	FOR i:= 512 TO 895 DO RL[i] :=  0 END;
	FOR i:= 896 TO 1023 DO RL[i] :=  i - 896 END;
	
	fix14 := ENTIER(1.40200 * 65536 +0.5);
	fix17 := ENTIER(1.77200 * 65536 +0.5);
	fix07 := ENTIER(0.71414 * 65536 +0.5);
	fix03 := ENTIER(0.34414 * 65536 +0.5);
	x := - CENTERJSAMPLE;
	FOR i := 0 TO MAXJSAMPLE DO
		crRTab[i] := SHORT(ASH(fix14 * x + 32768,-16));
		cbBTab[i] := SHORT(ASH(fix17 * x + 32768,-16));
		crGTab[i] := -fix07 * x;
		cbGTab[i] := -fix03 * x + 32768;
		INC(x);
	END;
	
	extendTest[0] := 0;
	extendTest[1] := 1;
	extendTest[2] := 2;
	extendTest[3] := 4;
	extendTest[4] := 8;
	extendTest[5] := 16;
	extendTest[6] := 32;
	extendTest[7] := 64;
	extendTest[8] := 128;
	extendTest[9] := 256;
	extendTest[10] := 512;
	extendTest[11] := 1024;
	extendTest[12] := 2048;
	extendTest[13] := 4096;
	extendTest[14] := 8192;
	extendTest[15] := 16384;
	
	i:= -1;
	extendOff[0] := 0;
	extendOff[1] := BIT.ILSH(i,1) + 1;
	extendOff[2] := BIT.ILSH(i,2) + 1;
	extendOff[3] := BIT.ILSH(i,3) + 1;
	extendOff[4] := BIT.ILSH(i,4) + 1;
	extendOff[5] := BIT.ILSH(i,5) + 1;
	extendOff[6] := BIT.ILSH(i,6) + 1;
	extendOff[7] := BIT.ILSH(i,7) + 1;
	extendOff[8] := BIT.ILSH(i,8) + 1;
	extendOff[9] := BIT.ILSH(i,9) + 1;
	extendOff[10] := BIT.ILSH(i,10) + 1;
	extendOff[11] := BIT.ILSH(i,11) + 1;
	extendOff[12] := BIT.ILSH(i,12) + 1;
	extendOff[13] :=  BIT.ILSH(i,13) + 1;
	extendOff[14] := BIT.ILSH(i,14) + 1;
	extendOff[15] := BIT.ILSH(i,15) + 1;
	
	T.OpenWriter(W);

END JPEG.
