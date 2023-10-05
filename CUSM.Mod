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

MODULE CUSM;	(** portable *)   (* CU-SeeMe video receiver  /  Luca Balestra 13.7.95 *)
	(* ejz 29.8.95, DOS version *)
IMPORT NetSystem, Texts, Oberon, Out, Objects, Gadgets, BasicGadgets, Pictures, SYSTEM, RembrandtDocs, Display,
	Math, Modules;

(* pjm 01.07.96 - seems to assume Oberon.Time returns ms? *)

CONST

    MAXSNDBUFLEN = 500;	(* max 37 requests 56+37*12=500 *)
    MAXRCVBUFLEN = 2048;
    VPHLEN = 26;	(* VideoPackeHeader length *)
    OCDLEN = 30;	(* OpenContinueData length *)
    CILEN = 12;		(* ClientInfo length *)
       
	(* family*)
		kGroup=0; kClient=1; kReflect=2;
	(* port *)
		VIDPORT=7648; SENDPORT=6666;
	(* message *)
		kOpenConnection=1; kCloseConnection=6;
	(* dataType *)
		kConfigVideoType=101;
		kMessageType1=104; kMessageType2=105;
		kHalfSizeVideoType=1; kFullSizeVideoType=2;
	(* flags *)
		RECAUDIO=1;
		AUDIOCAPABLE=2;
		WANTLURCKERS=4;
		PCCLIENT=8;
		PRIVATEAUDIO=16;
		WANTVERSION=32;		
		
	(* misc *)
		MSECINDAY=86400000;    (* mseconds in a day *)
		
TYPE 

	Addr=RECORD
		family: INTEGER;
		port: INTEGER;
		addr: LONGINT;
	END;
	
	Routing=RECORD
		dest: Addr;
		src: Addr;
	END;
	
	VideoPacketHeader = POINTER TO VideoPacketHeaderDesc;
	VideoPacketHeaderDesc=RECORD
		routing: Routing;
		seqNum: LONGINT;
		message: INTEGER;
		dataType: INTEGER;
		len: INTEGER;
	END;
	
	OpenContinueData = POINTER TO OpenContinueDataDesc;
	OpenContinueDataDesc=RECORD
		clientCount: INTEGER;
		seqNum: LONGINT;
		name: ARRAY 20 OF CHAR;
		sendMode: CHAR;						
		recvMode: CHAR;
		flags: CHAR;
		version: CHAR;
	END;
	
	PacketLossData = RECORD
		packetsSent: INTEGER;
		packetsRecv: INTEGER;
	END;
	
	ClientInfo = RECORD
		clientIp: LONGINT;
		flags: CHAR;
		aux: CHAR;
		iWillRecv: CHAR;
		iWillSend: CHAR;
		loss: PacketLossData;
	END;
	
	Image= POINTER TO ImageDesc;
	ImageDesc = RECORD
		width: INTEGER;
		height: INTEGER;
		picture: Pictures.Picture; 
	END;
	
	Client = POINTER TO ClientDesc;
	ClientDesc = RECORD
	next: Client;
		clAdr: LONGINT;
		clAdrStr: ARRAY 16 OF CHAR;
		name: ARRAY 256 OF CHAR;
		lastSeqNum: LONGINT;
		sndBufOffset: INTEGER;
		sender: BOOLEAN;
		timeOut: SHORTINT;
		wantVideo:BOOLEAN;
		image: Image;
	END;	
	
	Connection = POINTER TO ConnectionDesc;
	ConnectionDesc = RECORD
		reflAdr: LONGINT;
		reflAdrStr: ARRAY 16 OF CHAR;
		confID: INTEGER;
		connected:BOOLEAN;
		timeOut: INTEGER;
		sndBuf: ARRAY MAXSNDBUFLEN OF CHAR;
		sndBufLen: INTEGER;
		vphSeqNum:INTEGER;
		ocdSeqNum:INTEGER;
		timeToSend,timeToUpdate: LONGINT;
		clientsList: Client;
		next: Connection;
	END;	
	
VAR 
	connectionsList:Connection;
	currentConnection: Connection;
	hostAdr, reflAdr: LONGINT;
	rcvBuf: ARRAY MAXRCVBUFLEN OF CHAR; (* buffers to receive *)
	sndTask, rcvTask: Oberon.Task;
	rcvScktStarted, sndScktStarted:BOOLEAN;
	sndSocket,rcvSocket: NetSystem.Socket;
	rcvVPH: VideoPacketHeader;
	rcvOCD: OpenContinueData;
	reflAdrStr: BasicGadgets.String;
	conferenceID: BasicGadgets.Integer;
	hostName: BasicGadgets.String;
	connectionsLog, videosLog*: Texts.Text;
	(* IMAGE DECODE*)
		intraRowBytes: ARRAY 16 OF INTEGER;
		interRowDiff: ARRAY 16 OF LONGINT;
		wordDiff: ARRAY 256 OF  INTEGER;
		longDiff: ARRAY 256 OF LONGINT;
		conv4To8Bit: ARRAY 256 OF INTEGER; 
(*		imAdr,imSize: LONGINT;*)
		lumin,contr: INTEGER; (* luminosity and  contrast *)
		gamma: REAL;
	
	
(******* GADGETS ************)

PROCEDURE ReflAdrStrHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR temp: BasicGadgets.String;
BEGIN
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; COPY("CUSM.NewReflAdrStr", M.s);
					M.res := 0
				ELSE BasicGadgets.StringHandler(F, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					NEW(temp);
					BasicGadgets.StringHandler(temp,M)
				ELSE BasicGadgets.StringHandler(F,M)
				END
			END	
		ELSE BasicGadgets.StringHandler(F, M)
		END
END ReflAdrStrHandler;

PROCEDURE ConfIDHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR temp:BasicGadgets.Integer;
BEGIN
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; COPY("CUSM.NewConfID", M.s);
					M.res := 0
				ELSE BasicGadgets.IntegerHandler(F, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					NEW(temp);
					BasicGadgets.IntegerHandler(temp,M)
				ELSE BasicGadgets.IntegerHandler(F,M)
				END
			END
		ELSE BasicGadgets.IntegerHandler(F, M)
		END
END ConfIDHandler;

PROCEDURE HostNameHandler* (F: Objects.Object; VAR M: Objects.ObjMsg);
VAR temp:BasicGadgets.String;
BEGIN
		IF M IS Objects.AttrMsg THEN
			WITH M: Objects.AttrMsg DO
				IF (M.id = Objects.get) & (M.name = "Gen") THEN
					M.class := Objects.String; COPY("CUSM.NewHostName", M.s);
					M.res := 0
				ELSE BasicGadgets.StringHandler(F, M)
				END
			END
		ELSIF M IS Objects.FileMsg THEN
			WITH M: Objects.FileMsg DO
				IF M.id = Objects.load THEN
					NEW(temp);
					BasicGadgets.StringHandler(temp,M)
				ELSE BasicGadgets.StringHandler(F,M)
				END
			END
		ELSE BasicGadgets.StringHandler(F, M)
		END
END HostNameHandler;

PROCEDURE ConnHandler*(F:Objects.Object; VAR M: Objects.ObjMsg);
VAR temp: Texts.Text;
BEGIN
	IF M IS Objects.AttrMsg THEN
		WITH M: Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN
				M.class := Objects.String; COPY("CUSM.NewConnLog", M.s);
				M.res := 0
			ELSE Texts.Handle(F, M)
			END
		END
	ELSIF M IS Objects.FileMsg THEN
		WITH M: Objects.FileMsg DO
			IF M.id = Objects.load THEN
				NEW(temp);
				Texts.Handle(temp,M)
			ELSE Texts.Handle(F,M)
			END
		END	
	ELSE Texts.Handle(F, M)
	END
END ConnHandler;

PROCEDURE VideosHandler*(F:Objects.Object; VAR M: Objects.ObjMsg);
VAR temp: Texts.Text;
BEGIN
	IF M IS Objects.AttrMsg THEN
		WITH M: Objects.AttrMsg DO
			IF (M.id = Objects.get) & (M.name = "Gen") THEN
				M.class := Objects.String; COPY("CUSM.NewVideosLog", M.s);
				M.res := 0
			ELSE Texts.Handle(F, M)
			END
		END
	ELSIF M IS Objects.FileMsg THEN
		WITH M: Objects.FileMsg DO
			IF M.id = Objects.load THEN
				NEW(temp);
				Texts.Handle(temp,M)
			ELSE Texts.Handle(F,M)
			END
		END	
	ELSE Texts.Handle(F, M)
	END
END VideosHandler;

PROCEDURE NewReflAdrStr*;
BEGIN
	Objects.NewObj:=reflAdrStr
END NewReflAdrStr;

PROCEDURE NewConfID*;
BEGIN
	Objects.NewObj:=conferenceID
END NewConfID;

PROCEDURE NewHostName*;
BEGIN
	Objects.NewObj:=hostName
END NewHostName;

PROCEDURE NewConnLog*;
BEGIN
	Objects.NewObj:=connectionsLog
END NewConnLog;

PROCEDURE NewVideosLog*;
BEGIN
	Objects.NewObj:=videosLog
END NewVideosLog;

(********** END GADGETS ***********)

(********** VIDEO DECODE **********)

PROCEDURE SetPalette;
VAR i,c,d,inc:INTEGER;
BEGIN
	c:=lumin+contr;
	inc:=contr DIV 16;
	i:=20;
	WHILE c > lumin DO
		d:=SHORT(ENTIER((Math.exp(gamma*Math.ln(c)))));
		Display.SetColor(i,d,d,d);
		c:=c-inc;
		INC(i);
	END
END SetPalette;

PROCEDURE InitVideo;
VAR i,j,c,d,m,u:INTEGER;
			a,b:LONGINT;
			digit: ARRAY 8 OF LONGINT;
BEGIN
	(* init intraRowBytes *)
	intraRowBytes[0]:=-1;
	FOR i:=0 TO 4 DO
		intraRowBytes[i*3 + 1]:=-1;
		intraRowBytes[i*3 + 2]:=0;
		intraRowBytes[i*3 + 3]:=1;
	END;
	
	(* init interRowDiff *)
	interRowDiff[0]:=0;
	a:=0DDDDDDDEH;
	FOR  i:= 0 TO 4 DO
		b:=a;
		FOR j:=1 TO 3 DO
			interRowDiff[i*3 + j]:=b; 
			b:= b + 11111111H;
		END;
		a:= a + 11111111H
	END;
	
	(* init wordDiff *)
	u:=0; d:=0; c:=0; m:=0;
	FOR i:=0 TO 255 DO;
		wordDiff[i]:=((m*16 + c)*16 + d)*16 + u;
		INC(u);
		IF u > 3 THEN u:=0; INC(d) END;
		IF d > 3 THEN d:=0; INC(c) END;
		IF c > 3 THEN c:=0; INC(m) END;
	END;
	
	(* init longDiff *)
	FOR j:=0 TO 7 DO digit[j]:=0 END;	(* digit[0] is  MSB *)
	FOR i:=0 TO 255 DO
		longDiff[i]:=0;
		FOR j:=0 TO 7 DO
			longDiff[i] := longDiff[i]*16+digit[j]
		END;
		INC(digit[7]);
		FOR j:=0 TO 6  DO
			IF digit[7-j] > 1 THEN digit[7-j]:=0; INC(digit[7-(j+1)]) END
		END 
	END;
	
	(* init conv4To8Bit and color + 20 *)
	FOR i:=0 TO 15 DO
		FOR j:=0  TO 15 DO
			conv4To8Bit[i*16+j]:= (i+20)+(j+20)*256
		END
	END;
	
	lumin:=0;
	contr:=255;
	gamma:=1;
	SetPalette;	(* sets colors from 20 to 35 *)
END InitVideo;

PROCEDURE Decode*( VAR image: Image; VAR data: ARRAY OF CHAR; pos:INTEGER; imType: INTEGER; name:ARRAY OF CHAR);
VAR 
		dataLim: INTEGER;		
		width,height: INTEGER;
		ok: BOOLEAN;
		rowData: LONGINT;
(*		imPos: LONGINT;*)
x, y, minx, miny, maxx, maxy: INTEGER;
		
	PROCEDURE DecodeRow(code:INTEGER);
	VAR 
			i,col,intra: INTEGER;
			temp:LONGINT;
			cols:INTEGER;	
	BEGIN
		IF code=0 THEN
			rowData:=0;
			FOR i:=0 TO 3 DO
				cols:=ORD(data[pos+i]);
(*SYSTEM.PUT(imPos,conv4To8Bit[cols]);*)
Pictures.Dot(image.picture, conv4To8Bit[cols] MOD 256, x+2*i, y, Display.replace);
Pictures.Dot(image.picture, conv4To8Bit[cols] DIV 256, x+2*i+1, y, Display.replace);
				rowData:=rowData*256 + LONG(cols);
(*				INC(imPos,2);*)
			END;
			INC(pos,4);
DEC(y);
(*			imPos:=imPos-image.width-8 *)
		ELSE
			rowData:=rowData-interRowDiff[code];
			intra:=intraRowBytes[code];
			IF intra > 0 THEN
				rowData:=rowData + LONG( wordDiff[ORD(data[pos])] )* 65536 + LONG( wordDiff[ORD(data[pos+1])]);
				INC(pos,2);
			ELSIF  intra = 0 THEN
				rowData:=rowData+ longDiff[ORD(data[pos])];
				INC(pos)
			END;
			temp:=rowData;
(*			INC(imPos,6);*)
			FOR i:=0 TO 3 DO
				col:=SHORT(temp MOD 256); 
				IF temp < 0 THEN
					temp := MAX(LONGINT)+temp+1;	(* put away sign bit *)
					temp := temp DIV 256 + 800000H;  (* shift,    800000H = sign bit shifted of 8 bit  *)
				ELSE	
					temp:=temp DIV 256
				END;
Pictures.Dot(image.picture, conv4To8Bit[col] MOD 256, x+7-2*i-1, y, Display.replace);
Pictures.Dot(image.picture, conv4To8Bit[col] DIV 256, x+7-2*i, y, Display.replace);
(*SYSTEM.PUT(imPos,conv4To8Bit[col]); DEC(imPos,2) *)
			END;
DEC(y);
(*			imPos:=imPos-image.width+2 *)		
		END		
	END DecodeRow;	
	
	PROCEDURE DecodeSquare( );
	VAR 
		square: INTEGER;
(*		x,y: INTEGER; (* square coord. *)*)
		codePos,code: INTEGER;
		i: INTEGER;		
	BEGIN
    	IF dataLim - pos < 6 THEN ok:=FALSE END;
		square:= ORD(data[pos])*256 + ORD(data[pos+1]); INC(pos,2);  (* square number *)
		IF square > LONG(image.height) * LONG(image.width) DIV 64 THEN ok:=FALSE END; (* 300 or 1200 square/image *)
		x:=square MOD (image.width DIV 8);
		y:=square DIV (image.width DIV 8);
(*		imPos:=imAdr + x*8 + imSize - y*8*LONG(image.width);     (* position in memory bitmap *)*)
x := x*8;
IF x < minx THEN
	minx := x
END;
IF x > maxx THEN
	maxx := x
END;
y := image.height-y*8-1;
IF y < miny THEN
	miny := y
END;
IF y > maxy THEN
	maxy := y
END;
		codePos:=pos;
		INC(pos,4);
		rowData:=88888888H;
		FOR i:=1 TO 4 DO
			code:=ORD(data[codePos]); INC(codePos);
			DecodeRow(code DIV 16);
			DecodeRow(code MOD 16)
		END
	END DecodeSquare;
	
BEGIN
	IF imType = 1 THEN	
		width:=160;
		height:=120
	ELSIF imType = 2 THEN		
		width:=320;
		height:=240
	ELSE
		Out.String("imType not found in Video.Decode"); Out.Ln
	END;
	IF image= NIL THEN
		NEW(image);
		NEW(image.picture);
		image.width:=width;
		image.height:=height;
		Pictures.Create(image.picture,width,height,8);
		RembrandtDocs.OpenPict(image.picture,name)
	ELSE
		IF (width # image.width) OR (height # image.height) THEN 
			Pictures.Create(image.picture,width,height,8);
			HALT(99)
		END
	END;	
	dataLim:=ORD(data[pos])*256 + ORD(data[pos+1]) + 2 + pos;
	pos:=pos+2;
	ok:=TRUE;
(*	imAdr:=Pictures.Address(image.picture);
	imSize:=LONG(image.width)*(LONG(image.height)-1);*)
minx := image.width;
maxx := 0;
miny := image.height;
maxy := 0;
	WHILE ok & (pos  < dataLim) DO
		DecodeSquare()
	END;
	IF pos # dataLim THEN Out.String("Video data error") END;
Pictures.Update(image.picture, minx, miny-8, maxx+8, maxy)
END Decode;		

PROCEDURE BlackPicture(im: Image);
BEGIN
	IF (im # NIL) & (im.picture # NIL) THEN
		Pictures.ReplConst(im.picture, Display.FG, 0, 0, im.width, im.height, Display.replace);
		Pictures.Update(im.picture, 0, 0, im.width, im.height)
	END
END BlackPicture;	

PROCEDURE SetLum*;
VAR s:Texts.Scanner;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Int THEN
		IF contr+s.i > 255 THEN 
			Out.String("Invalid value of luminosity"); Out.Ln
		ELSE
			lumin:=SHORT(s.i);
			SetPalette;
		 END
	END 
END SetLum;

PROCEDURE SetContr*;
VAR s:Texts.Scanner;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Int THEN
		IF lumin+s.i > 255 THEN 
			Out.String("Invalid value of contrast"); Out.Ln
		ELSE
			contr:=SHORT(s.i);
			SetPalette
		END
	END	
END SetContr;

PROCEDURE SetGamma*;
VAR s:Texts.Scanner;
BEGIN
	Texts.OpenScanner(s, Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.Real THEN
		IF (s.x >=  0.6) & (s.x <= 1.1) THEN 
			gamma:=s.x;
			SetPalette
		ELSE
			Out.String("Invalid value of gamma correction"); Out.Ln
		END
	ELSE
		Out.String("Value must be Real"); Out.Ln
	END		
END SetGamma;

(*********** END  VIDEO ********)

PROCEDURE StartSndTask;
VAR res: INTEGER;
BEGIN
	IF ~sndScktStarted THEN 
		NetSystem.OpenSocket(sndSocket, SENDPORT, res);
		IF res # NetSystem.done THEN;
			Out.String("Error in StartSndSocket"); Out.Ln;
			HALT(99)
		END;
		Oberon.Install(sndTask);
		sndScktStarted:=TRUE
	END	
END StartSndTask;

PROCEDURE StopSndTask;
BEGIN
	IF sndScktStarted THEN
		NetSystem.CloseSocket(sndSocket);
		Oberon.Remove(sndTask);
		sndScktStarted:=FALSE
	END
END StopSndTask;	

PROCEDURE  StartRcvTask;
VAR res: INTEGER;
BEGIN
	IF ~ rcvScktStarted THEN
		NetSystem.OpenSocket(rcvSocket, VIDPORT, res);
		IF res # NetSystem.done THEN;
			Out.String("Error in StartRcvSocket"); Out.Ln;
			HALT(99)
		END;
		Oberon.Install(rcvTask);
		rcvScktStarted:=TRUE
	END
END StartRcvTask;

PROCEDURE StopRcvTask;
BEGIN
	IF rcvScktStarted THEN
		NetSystem.CloseSocket(rcvSocket);
		Oberon.Remove(rcvTask);
		rcvScktStarted:=FALSE
	END
END StopRcvTask;

PROCEDURE ConvIpAdrLtoS(adr: LONGINT; VAR ip: ARRAY OF CHAR);
	VAR k: INTEGER;
	PROCEDURE Write(i: LONGINT);
	VAR 
			p, n: LONGINT;
			notFirstZero: BOOLEAN;
	BEGIN
		notFirstZero:=FALSE;
		p := 100;
		WHILE p > 0 DO
			n := i DIV p; i := i MOD p;
			IF ((n # 0) OR notFirstZero) OR (p = 1) THEN
				notFirstZero:=TRUE;
				ip[k] := CHR(n + ORD("0")); 
				INC(k)
			END;
			p := p DIV 10
		END
	END Write;

BEGIN
	k := 0;
	Write(adr MOD 256); adr := adr DIV 256; ip[k] := "."; INC(k);
	Write(adr MOD 256); adr := adr DIV 256; ip[k] := "."; INC(k);
	Write(adr MOD 256); adr := adr DIV 256; ip[k] := "."; INC(k);
	Write(adr MOD 256); ip[k] := 0X
END ConvIpAdrLtoS;

PROCEDURE UpdateConnLog;
VAR
		cur: Connection;
		w: Texts.Writer;
BEGIN
	Texts.OpenWriter(w);
	IF connectionsList # NIL THEN
		cur:= connectionsList;
		WHILE cur # NIL DO
			IF cur.connected  THEN
				IF cur = currentConnection THEN 
					Texts.SetColor(w,1)
				ELSE
					Texts.SetColor(w,15)
				END;		
				Texts.Write(w, 22X);
				Texts.WriteString(w,cur.reflAdrStr);  Texts.Write(w, 22X);
				Texts.WriteLn(w)
			END;	
				cur:=cur.next
			END
	END;	
	Texts.Delete(connectionsLog,0,connectionsLog.len);
	Texts.Append(connectionsLog, w.buf)
END UpdateConnLog;

PROCEDURE UpdateVideoStreamsLog;
VAR 
		w1,w2:Texts.Writer;
		cur: Client;
BEGIN
	Texts.OpenWriter(w1);
	Texts.OpenWriter(w2);
	IF currentConnection # NIL THEN
		cur:=currentConnection.clientsList;
		IF cur = NIL THEN 
			Texts.WriteString(w1,"NO SENDERS"); Texts.WriteLn(w1)
		ELSE
			WHILE cur # NIL DO
				IF cur.sender THEN
					IF cur.image # NIL  THEN
						Texts.SetColor(w1,15); 
						Texts.WriteString(w1,cur.name); Texts.WriteString(w1," :  ");
						Texts.SetColor(w1,1);
						Texts.Write(w1, 22X); Texts.WriteString(w1,cur.clAdrStr); Texts.Write(w1, 22X);
						Texts.WriteLn(w1)
					ELSE
						Texts.SetColor(w2,15);
						Texts.WriteString(w2,cur.name); Texts.WriteString(w2," :  ");
						Texts.SetColor(w2,15);
						Texts.Write(w2, 22X); Texts.WriteString(w2,cur.clAdrStr); Texts.Write(w2, 22X);
						Texts.WriteLn(w2)
					END			
				END;
				cur:=cur.next
			END	
		END
	END;		
	Texts.Delete(videosLog,0,videosLog.len);
	Texts.Append(videosLog,w1.buf);
	Texts.Append(videosLog,w2.buf)
END UpdateVideoStreamsLog;

PROCEDURE SearchConnection(rAddr: LONGINT): Connection;
VAR cur: Connection;
BEGIN
	IF connectionsList # NIL THEN
		cur:=connectionsList;
		WHILE cur # NIL DO
			IF cur.reflAdr = rAddr THEN RETURN cur END;
			cur:=cur.next
		END
	END;
	RETURN NIL
END SearchConnection;
				
PROCEDURE RemoveConnection(con: Connection);
VAR 
		cur:Connection;
		curCl: Client;
BEGIN
	curCl:=con.clientsList;
	WHILE curCl # NIL DO
		IF curCl.image# NIL THEN BlackPicture(curCl.image) END;
		curCl:=curCl.next
	END;	
	IF con = currentConnection THEN 
		currentConnection:=NIL;
		UpdateVideoStreamsLog
	END;
	cur:=connectionsList;
	IF cur=con THEN 
		connectionsList:=con.next
	ELSE
		WHILE cur.next # con DO cur:=cur.next END;
		cur.next:=cur.next.next
	END;
	UpdateConnLog;
	IF connectionsList = NIL THEN
		StopSndTask; StopRcvTask
	END
END RemoveConnection;
		
PROCEDURE SearchClientByAdr(con:Connection; ipAdr: LONGINT): Client;
VAR cur: Client;
BEGIN
	cur:=con.clientsList;
	WHILE cur # NIL DO
		IF cur.clAdr = ipAdr THEN RETURN cur END;
		cur:=cur.next
	END;
	RETURN NIL
END SearchClientByAdr;

PROCEDURE SearchClientByStrAdr(con:Connection; adr:ARRAY OF CHAR): Client;
VAR cur: Client;
BEGIN
	IF con # NIL THEN
		cur:=con.clientsList;
		WHILE cur # NIL DO
			IF cur.clAdrStr= adr THEN RETURN cur END; 			
			cur:=cur.next
		END
	END;	
	RETURN NIL
END SearchClientByStrAdr;

PROCEDURE RemoveClient(con: Connection; cl: Client);
VAR cur:Client;
BEGIN
	IF con#NIL THEN
		cur:=con.clientsList;
		IF cur=cl THEN 
			con.clientsList:=cl.next
		ELSE
			WHILE cur.next # cl DO cur:=cur.next END;
			IF cur.next.image # NIL THEN
					BlackPicture(cur.next.image)
			END;
			IF cur.next.sender THEN 
				IF con = currentConnection THEN
					cur.next:=cur.next.next;
					UpdateVideoStreamsLog
				ELSE
					cur.next:=cur.next.next
				END	
			END
		END
	END;	
END RemoveClient;
	
PROCEDURE Turn(ipAdr:LONGINT):LONGINT;
VAR 
		buf:ARRAY 4 OF CHAR;
		pos:INTEGER;
BEGIN
	pos:=0;
	NetSystem.PutLInt(buf,pos,ipAdr); INC(pos, 4);
	ipAdr:=ORD(buf[3])*256+ ORD(buf[2]);
	ipAdr:=(ipAdr*256 + ORD(buf[1]))*256  + ORD(buf[0]);
	RETURN ipAdr
END Turn;

PROCEDURE FullSndBuf(con: Connection; conferenceID: INTEGER; VAR hostName: ARRAY OF CHAR);
VAR 
		pos,i: INTEGER;
		ch:CHAR;
BEGIN
	pos:= 0;
	NetSystem.PutInt(con.sndBuf,pos,kReflect); INC(pos, 2);						(* dest.family *)
	NetSystem.PutInt(con.sndBuf,pos,conferenceID); INC(pos, 2);				(*  dest.port *)
	NetSystem.PutLInt(con.sndBuf,pos,0); INC(pos, 4);									(* dest.addr -> used only to send to a particular client *)
	NetSystem.PutInt(con.sndBuf,pos,kClient); INC(pos, 2);							(* src.family *) 
	NetSystem.PutInt(con.sndBuf,pos,VIDPORT); INC(pos, 2);						(* src.port for receiving packets *)
	NetSystem.PutLInt(con.sndBuf,pos,hostAdr); INC(pos, 4);						(* src.addr *)
	NetSystem.PutLInt(con.sndBuf,pos,0);	INC(pos, 4);		 						(* sequence number of sended packe *)
	NetSystem.PutInt(con.sndBuf,pos,kOpenConnection); INC(pos, 2);			(* message *)
	NetSystem.PutInt(con.sndBuf,pos,kConfigVideoType);	INC(pos, 2);		(* dataType *) 
	NetSystem.PutInt(con.sndBuf,pos,VPHLEN + OCDLEN);	INC(pos, 2);		(* length *)
	NetSystem.PutInt(con.sndBuf,pos,0); INC(pos, 2);									(* clientCount *)
	NetSystem.PutLInt(con.sndBuf,pos,0); INC(pos, 4);									(* seqNum of OpenContinueData *)
	i:=0;																			(* name *)
	ch:=hostName[i];
	WHILE (ch # 0X) & (i < 19) DO
		con.sndBuf[pos+i+1]:=ch;
		INC(i);
		ch:=hostName[i]
	END;
	pos:=32;
	con.sndBuf[pos]:=CHR(i);
	pos:=52;	
	con.sndBuf[pos]:=CHR(0); INC(pos);						(* sendMode *)
	con.sndBuf[pos]:=CHR(10); INC(pos);						(* recvMode *)
	con.sndBuf[pos]:=CHR(PCCLIENT); INC(pos);			(* flags *)
	con.sndBuf[pos]:=CHR(5);											(* version 5 *)
	con.sndBufLen:=VPHLEN+OCDLEN
END FullSndBuf;

PROCEDURE InsertClientInfo(con:Connection; ipAdr: LONGINT ;recv: BOOLEAN);
VAR 
		ccl: LONGINT;
		pos,p,cci:INTEGER;
		src: Client;
BEGIN
	src:=SearchClientByAdr(con,ipAdr);
	IF src # NIL THEN
		IF src.sender THEN
			IF src.sndBufOffset = 0 THEN
				pos:=con.sndBufLen;
				src.sndBufOffset:=pos;
				INC(con.sndBufLen,12);
				p:=24; NetSystem.PutInt(con.sndBuf,p,con.sndBufLen);  INC(p, 2); (* update length in sndBuf *)
				p:=VPHLEN;															(* inc clientCount *)
				NetSystem.GetInt(con.sndBuf,p,cci); INC(p, 2);
				INC(cci);
				p:=VPHLEN;
				NetSystem.PutInt(con.sndBuf,p,cci); INC(p, 2)
			ELSE 
				pos:=src.sndBufOffset
			END;
			NetSystem.PutLInt(con.sndBuf,pos,ipAdr); INC(pos, 4);
			con.sndBuf[pos]:=CHR(1); INC(pos);  	 (* flags -> 1: update video *)
			con.sndBuf[pos]:=CHR(0); INC(pos);		(* aux *)
			IF recv THEN con.sndBuf[pos]:=CHR(1) ELSE con.sndBuf[pos]:=CHR(0) END; INC(pos);	(* i WillRecv *)
			con.sndBuf[pos]:=CHR(0); INC(pos);	(* iWillSend *)
			NetSystem.PutInt(con.sndBuf,pos,0); INC(pos, 2);			(*  packets sent *)
			NetSystem.PutInt(con.sndBuf,pos,1000); INC(pos, 2);		(* packets received *)   
		ELSE
			Out.String("This source is not a sender"); Out.Ln	
		END;
		p:=VPHLEN+2;								(* inc OCDSeqNum *)									
		NetSystem.GetLInt(con.sndBuf,p,ccl); INC(p, 4);
		INC(ccl);
		p:=VPHLEN+2;
		NetSystem.PutLInt(con.sndBuf,p,ccl); INC(p, 4)
	ELSE
		Out.String("Client not found"); Out.Ln	
	END	
END InsertClientInfo;

PROCEDURE ReadVPH(VAR vph: VideoPacketHeader; VAR pos: INTEGER);
BEGIN
	NetSystem.GetInt(rcvBuf,pos,vph.routing.dest.family); INC(pos, 2);
	NetSystem.GetInt(rcvBuf,pos,vph.routing.dest.port); INC(pos, 2);
	NetSystem.GetLInt(rcvBuf,pos,vph.routing.dest.addr); INC(pos, 4);
	NetSystem.GetInt(rcvBuf,pos,vph.routing.src.family); INC(pos, 2);
	NetSystem.GetInt(rcvBuf,pos,vph.routing.src.port); INC(pos, 2);
	NetSystem.GetLInt(rcvBuf,pos,vph.routing.src.addr); INC(pos, 4);
	NetSystem.GetLInt(rcvBuf,pos,vph.seqNum); INC(pos, 4);
	NetSystem.GetInt(rcvBuf,pos,vph.message); INC(pos, 2);
	NetSystem.GetInt(rcvBuf,pos,vph.dataType); INC(pos, 2);
	NetSystem.GetInt(rcvBuf,pos,vph.len); INC(pos, 2)
END ReadVPH;	

PROCEDURE ReadOCD(VAR ocd: OpenContinueData; VAR pos: INTEGER);
VAR i:INTEGER;
BEGIN
	NetSystem.GetInt(rcvBuf,pos,ocd.clientCount); INC(pos, 2);
	NetSystem.GetLInt(rcvBuf,pos,ocd.seqNum); INC(pos, 4);
	ocd.name[0]:=rcvBuf[pos];
	FOR i:=1 TO ORD(ocd.name[0]) DO 
		ocd.name[i]:=rcvBuf[pos+i]
	END;
	pos:=pos+20;
	ocd.sendMode:=rcvBuf[pos]; INC(pos);
	ocd.recvMode:=rcvBuf[pos]; INC(pos);
	ocd.version:=rcvBuf[pos]; INC(pos)
END ReadOCD;
	
PROCEDURE UpdateClientsList(con:Connection);
VAR cur: Client;		
BEGIN
	cur:=con.clientsList;
	WHILE cur # NIL DO
		INC(cur.timeOut);
		IF cur.timeOut > 10 THEN RemoveClient(con,cur) END;
		cur:=cur.next
	END;
END UpdateClientsList;	

PROCEDURE Sender(me: Oberon.Task);
VAR 
		t:LONGINT;
		pos:INTEGER;
		curCon: Connection;
BEGIN
	t:=Oberon.Time();
	curCon:=connectionsList;
	WHILE curCon # NIL DO 
		IF (t > curCon.timeToSend) & (ABS(curCon.timeToSend - t) < 50000) THEN     (* ! midnight ! *)
			curCon.timeToSend:=(t+3000) MOD MSECINDAY ;
			NetSystem.SendDG(sndSocket, SYSTEM.VAL(NetSystem.IPAdr, curCon.reflAdr), VIDPORT, 0, curCon.sndBufLen, curCon.sndBuf);
			INC(curCon.vphSeqNum);
			pos:=16;
			NetSystem.PutLInt(curCon.sndBuf,pos,curCon.vphSeqNum); INC(pos, 4)
		END;
		IF (t > curCon.timeToUpdate) & ( ABS(curCon.timeToUpdate - t) < 50000) THEN  (* ! midnight ! *)
			UpdateClientsList(curCon);
			INC(curCon.timeOut);
			IF curCon.timeOut > 10 THEN 
				RemoveConnection(curCon);
				Out.String("No respons from reflector "); Out.String(curCon.reflAdrStr); Out.Ln
			END;
			curCon.timeToUpdate := (curCon.timeToUpdate + 1000) MOD MSECINDAY	
		END;	
		curCon:=curCon.next
	END;	
END Sender;

PROCEDURE OutMsg(mLen: INTEGER; pos: INTEGER);
VAR 
		w: Texts.Writer;
		i:INTEGER;
BEGIN
	Texts.OpenWriter(w);
	FOR i := 0 TO mLen-1 DO
		Texts.Write(w,rcvBuf[pos+i])
	END;
	Texts.WriteLn(w); Texts.WriteLn(w);
	Texts.Append(Oberon.Log,w.buf)
END OutMsg;

PROCEDURE Receiver(me: Oberon.Task);
	VAR	
		rAddr,len,t: LONGINT;
		i, msgLen, pos, rPort: INTEGER;
		src: Client;
		curCon:Connection;
BEGIN
	IF NetSystem.AvailableDG(rcvSocket) > 0 THEN
		len:=MAXRCVBUFLEN;
		t := 0;
		NetSystem.ReceiveDG(rcvSocket, SYSTEM.VAL(NetSystem.IPAdr, rAddr), rPort, t, len, rcvBuf);
		pos:=0;
		curCon:=SearchConnection(rAddr);
		IF curCon # NIL THEN
			curCon.timeOut:=0;
			ReadVPH(rcvVPH,pos);
			CASE rcvVPH.dataType OF
				kMessageType2:  INC(pos,2);
											NetSystem.GetInt(rcvBuf,pos,msgLen); INC(pos, 2);
											OutMsg(msgLen,pos);
											IF curCon.connected = FALSE THEN
												curCon.connected:=TRUE;
												UpdateConnLog	
											END; 	
				|kMessageType1: INC(pos,2);
											msgLen:=ORD(rcvBuf[pos]); INC(pos);
											OutMsg(msgLen,pos);
											RemoveConnection(curCon);
				|kConfigVideoType:
											IF curCon.connected = FALSE THEN
												curCon.connected:=TRUE;
												UpdateConnLog	
											END; 
											ReadOCD(rcvOCD,pos);
											src:=SearchClientByAdr(curCon,rcvVPH.routing.src.addr);
											IF src=NIL THEN
												NEW(src);
												src.clAdr:=rcvVPH.routing.src.addr;
												ConvIpAdrLtoS(Turn(src.clAdr),src.clAdrStr);
												FOR  i:=0 TO ORD(rcvOCD.name[0])-1 DO
													src.name[i]:=rcvOCD.name[i+1]
												END;
												src.name[ORD(rcvOCD.name[0])]:=0X;
												src.lastSeqNum:=rcvVPH.seqNum;
												src.sndBufOffset:=0;
												IF ORD(rcvOCD.sendMode) # 0 THEN 
													src.sender:=TRUE
												ELSE
													src.sender:=FALSE
												END;		
												src.timeOut:=0;
												src.image:=NIL;
												src.next:=curCon.clientsList;
												curCon.clientsList:=src;
												IF (curCon = currentConnection) & (src.sender) THEN UpdateVideoStreamsLog END
											ELSE
												src.timeOut:=0;
												IF ((src.sender=TRUE) & (ORD(rcvOCD.sendMode)=0)) OR ((src.sender=FALSE) & (ORD(rcvOCD.sendMode)#0)) THEN
													IF ORD(rcvOCD.sendMode) # 0 THEN 
													src.sender:=TRUE
													ELSE
													src.sender:=FALSE
													END;
													IF (curCon = currentConnection) & (src.sender) THEN UpdateVideoStreamsLog END
												END	
											END			
				|kHalfSizeVideoType , kFullSizeVideoType:
											src:=SearchClientByAdr(curCon,rcvVPH.routing.src.addr);
											IF src # NIL THEN
												src.timeOut:=0;
												IF src.wantVideo & (rcvVPH.seqNum > src.lastSeqNum) THEN
													IF len > VPHLEN+2 THEN
														IF src.image # NIL THEN
															Decode(src.image,rcvBuf,pos,rcvVPH.dataType,src.name) 
														ELSE
															Decode(src.image,rcvBuf,pos,rcvVPH.dataType,src.name);	
															IF curCon = currentConnection THEN
																UpdateVideoStreamsLog
															END	
														END	
													END
												END	
											END										
				ELSE (* Out.String("UNKNOWN MESSAGE TYPE !"); Out.Ln;
						Out.String("from: "); ConvIpAdrLtoS(raddr,ipadr); Out.String(ipadr); Out.Ln;
						Out.String("lenght: "); Out.Int(len,4); Out.Ln;
						Out.String("source: "); ConvIpAdrLtoS(rcvVPH.routing.src.addr,ipadr); Out.String(ipadr); Out.Ln;
						Out.String("message: "); Out.Int(rcvVPH.message,3); Out.Ln;
						Out.String("dataType: "); Out.Int(rcvVPH.dataType,3); Out.Ln;*)
			END
		END
	END
END Receiver;
	
PROCEDURE Connect*;
VAR 
		con:Connection;
BEGIN
	con:=SearchConnection(reflAdr);
	IF (con = NIL) & (reflAdrStr.val # "") THEN
		Out.String("Connecting ..."); Out.Ln;
		NEW(con);
		con.reflAdr:=reflAdr;
		COPY(reflAdrStr.val,con.reflAdrStr);
		con.connected:=FALSE;
		con.timeOut:=0;
		con.vphSeqNum:=0;
		con.ocdSeqNum:=0;
		con.clientsList:=NIL; 
		FullSndBuf(con,SHORT(conferenceID.val),hostName.val);
		con.timeToSend:=Oberon.Time();
		con.timeToUpdate:=con.timeToSend;
		con.next:=connectionsList;
		connectionsList:=con;
		IF con.next  = NIL THEN
			StartRcvTask; StartSndTask
		END	
	ELSE
		IF con # NIL THEN 
			Out.String("Already connected")
		ELSE 
			Out.String("Refector address muss be setted")
		END;
		Out.Ln
	END		
END Connect;

PROCEDURE GetHostAdr;
	VAR ipAdr: ARRAY 16 OF CHAR;
BEGIN
	IF NetSystem.hostIP # NetSystem.anyIP THEN
		SYSTEM.MOVE(SYSTEM.ADR(NetSystem.hostIP), SYSTEM.ADR(hostAdr), 4);
		ConvIpAdrLtoS(hostAdr,ipAdr);
		Out.String("Host address: "); Out.String(ipAdr); Out.Ln
	ELSE 
		Out.String("Error in GetMyAdr"); Out.Ln;
		HALT(99)
	END;
	hostAdr:=Turn(hostAdr)
END GetHostAdr;


PROCEDURE SetHostName*; 
BEGIN
	 Out.String("Host name: "); Out.String(hostName.val); Out.Ln
END SetHostName;

PROCEDURE SetReflAdr*;
	VAR
		adr: NetSystem.IPAdr;
		ipAdr: ARRAY 16 OF CHAR;
BEGIN
	NetSystem.GetIP(reflAdrStr.val, adr);
	IF adr # NetSystem.anyIP THEN
		SYSTEM.MOVE(SYSTEM.ADR(adr), SYSTEM.ADR(reflAdr), 4);
		ConvIpAdrLtoS(reflAdr, ipAdr);
		Out.String("Reflector address: "); Out.String(ipAdr); Out.Ln
	ELSE 
		Out.String("Invalid reflector address"); Out.Ln;
	END
END SetReflAdr;

PROCEDURE SetReflAdrFromList*;
	VAR 
		s: Texts.Scanner;
		oldRA: LONGINT;
		ipAdrS: ARRAY 16 OF CHAR;
		adr: NetSystem.IPAdr;
BEGIN
	oldRA:=reflAdr;
	Texts.OpenScanner(s,Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.String THEN
		NetSystem.GetIP(s.s, adr);
		IF adr # NetSystem.anyIP THEN
			SYSTEM.MOVE(SYSTEM.ADR(adr), SYSTEM.ADR(reflAdr), 4);
			COPY(s.s,reflAdrStr.val);
			Gadgets.Update(reflAdrStr);
			ConvIpAdrLtoS(reflAdr,ipAdrS);
			Out.String("Reflector address: "); Out.String(ipAdrS); Out.Ln
		ELSE 
			reflAdr := oldRA;
			Out.String("Reflector adress not valid"); Out.Ln
		END
	END
END SetReflAdrFromList;

PROCEDURE SetConferenceID*;
BEGIN
	Out.String("Conference ID : "); Out.Int(conferenceID.val,6); Out.Ln
END SetConferenceID;
	
PROCEDURE HandleReflectorLogClick*;
	VAR
		pos: INTEGER;
		s:Texts.Scanner;
		con: Connection;
		reflAdr: LONGINT;
		adr: NetSystem.IPAdr;
BEGIN
	Texts.OpenScanner(s,Oberon.Par.text, Oberon.Par.pos);
	Texts.Scan(s);
	IF s.class = Texts.String THEN
		NetSystem.GetIP(s.s, adr);
		IF adr # NetSystem.anyIP THEN
			SYSTEM.MOVE(SYSTEM.ADR(adr), SYSTEM.ADR(reflAdr), 4);
			con:=SearchConnection(reflAdr);
			IF con # NIL THEN 
				IF con = currentConnection THEN (* Disconnect *)
					IF con.connected THEN
						Out.String("Disconnecting from reflector at address: "); Out.String(con.reflAdrStr); Out.Ln;
						pos:=20;
						NetSystem.PutInt(con.sndBuf,pos,kCloseConnection); INC(pos, 2);
						NetSystem.SendDG(sndSocket, SYSTEM.VAL(NetSystem.IPAdr, con.reflAdr), VIDPORT, 0, con.sndBufLen, con.sndBuf);
						RemoveConnection(con)
					END
				ELSE	(* Show Videos *)
					currentConnection:=con;
					UpdateConnLog;
					UpdateVideoStreamsLog
				END	
			ELSE 
				Out.String("Invalid reflector address"); Out.Ln
			END	
		END
	END	
END HandleReflectorLogClick;

PROCEDURE OutLurckersList*;
VAR 
		cur: Client;
		senders: BOOLEAN;
		w: Texts.Writer;
BEGIN
	Texts.OpenWriter(w);
	senders:=FALSE;
	IF currentConnection # NIL THEN
		cur:=currentConnection.clientsList;
		WHILE cur # NIL DO
			IF ~cur.sender THEN
				IF ~senders THEN
					Texts.WriteString(w,"LURCKERS LIST: "); Texts.WriteLn(w);
					senders:=TRUE
				END;	
				Texts.WriteString(w," ");
				Texts.WriteString(w,cur.name); Texts.WriteString(w," ");
				Texts.WriteString(w,":  ");
				Texts.WriteString(w,cur.clAdrStr);  Texts.WriteLn(w)
			END;
			cur:=cur.next
		END;
		IF ~senders THEN 	
			Texts.WriteString(w,"NO LURCKERS"); Texts.WriteLn(w)
		END	
	ELSE 
		Texts.WriteString(w,"No connection selected"); Texts.WriteLn(w)
	END;
	Texts.WriteLn(w);
	Texts.Append(Oberon.Log,w.buf)
END OutLurckersList;

PROCEDURE StartStopVideo*;
VAR 
		s:Texts.Scanner;
		cur:Client;	
BEGIN
	IF currentConnection # NIL THEN
		Texts.OpenScanner(s,Oberon.Par.text, Oberon.Par.pos);
		Texts.Scan(s);
		IF s.class = Texts.String THEN
			cur:=SearchClientByStrAdr(currentConnection,s.s);
			IF cur # NIL THEN
				IF (cur.image = NIL) & (cur.wantVideo = FALSE) THEN	(* START *)
					Out.String("Video request from "); Out.String(s.s); Out.Ln;
					cur.wantVideo:=TRUE;
					InsertClientInfo(currentConnection,cur.clAdr,TRUE)
				ELSE	(* STOP *)
					Out.String("Stopping video from "); Out.String(s.s); Out.Ln;
					cur.wantVideo:=FALSE;
					BlackPicture(cur.image);
					cur.image:=NIL;
					InsertClientInfo(currentConnection,cur.clAdr,FALSE)
				END;
				currentConnection.timeToSend:=Oberon.Time();
				UpdateVideoStreamsLog
			ELSE 
				Out.String("Client not found"); Out.Ln
			END	
		END
	END
END StartStopVideo;						
		
	
PROCEDURE Init;
BEGIN	
	Out.String("CUSM  lb 13.7.95"); Out.Ln;
	
	(***** GADGETS *****)
	NEW(reflAdrStr); BasicGadgets.InitString(reflAdrStr); reflAdrStr.handle:=ReflAdrStrHandler;
	NEW(conferenceID); BasicGadgets.InitInteger(conferenceID); conferenceID.handle:=ConfIDHandler;
	NEW(hostName); BasicGadgets.InitString(hostName); hostName.handle:=HostNameHandler; 
	NEW(connectionsLog); Texts.Open(connectionsLog, ""); connectionsLog.handle:= ConnHandler;
	NEW(videosLog); Texts.Open(videosLog, ""); videosLog.handle:= VideosHandler;
	(***** END GADGETS *****)
	
	InitVideo;
	
	Texts.Delete(videosLog,0,videosLog.len);
	Texts.Delete(connectionsLog,0,connectionsLog.len);
	connectionsList:=NIL;
	currentConnection:=NIL;
	hostName.val:="My Name";
	Gadgets.Update(hostName); 
	conferenceID.val:=0;
	Gadgets.Update(conferenceID);
	reflAdr:=0;
	reflAdrStr.val:="";
	Gadgets.Update(reflAdrStr);
	NEW(sndTask); sndTask.handle:=Sender;
	NEW(rcvTask); rcvTask.handle:=Receiver;
	sndScktStarted:=FALSE;
	rcvScktStarted:=FALSE;
	NEW(rcvVPH); NEW(rcvOCD);
	GetHostAdr; 
END Init;

PROCEDURE End*;
VAR cur:Connection;
BEGIN
	cur:=connectionsList;
	WHILE cur # NIL DO
		RemoveConnection(cur);
		cur:=cur.next
	END;	
	connectionsList:=NIL;
	currentConnection:=NIL;
	UpdateConnLog;
	UpdateVideoStreamsLog;
	Out.String("All connections closed");Out.Ln
END End;	
	 
BEGIN
	Init;  Modules.InstallTermHandler(End)
END CUSM.


System.Free CUSM ~ 

CUSM.End

VIDEO CONTROLS:
CUSM.SetLum 10							(* luminosity *)
CUSM.SetContr 190						(* contrast *)
CUSM.SetGamma 0.9					(* gamma correction *)

GADGETS CREATION:
Gadgets.Insert TextField CUSM.NewReflAdrStr ~
Gadgets.Insert TextField CUSM.NewConfID ~
Gadgets.Insert TextField CUSM.NewHostName ~
Gadgets.Insert TextGadget CUSM.NewConnLog ~
Gadgets.Insert TextGadget CUSM.NewVideosLog ~

Desktops.OpenDoc S3CUSeeMe.Panel

Compiler.Compile S3CUSeeMe.Mod/ocs ~
