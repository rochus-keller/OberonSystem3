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

MODULE PPPMain;	(** non-portable *)	(* Contributed by Martin Aeschlimann, Claude Knaus & Edgar Schwarz *)
(* $VCS   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:26:14 $
    $Log$
$   1, Edgar.Schwarz@z.zgs.de, 28 Feb 99, 22:26:14
version for PPP 1.0.0
*)
(* 
	ToDo:
		SendPacket ueberpruefen, falls nicht alle characters gesendet 
		
		Spaeter: Routing von PacketTools entkoppeln
*)
	IMPORT HDLC:=PPPHDLC, LCP:=PPPLCP, IPCP:=PPPIPCP, FSM:=PPPFSM, 
		PAP := PPPPAP, SYSTEM, Debug := PPPDebug, T:=PPPTools, O:=Objects, 
		PT:=(*es*)NetBase, NetIP, V24, Out, NetSystem, (*PacketTools, *)
		(*es*) Oberon, Texts;
		(* P := Peripherals, XOberon, XTexts, Base; *)

CONST
	PPPIP = 0021H;
	(*es*)IPPROT(*IP*) = 0800H;
	ARP = 0806H;
	
	(* Protocol Constants *)
	DefMRU = HDLC.MTU; MinMRU = 128; MaxMRU = HDLC.MTU;
	
	(* Options Index  for LCP Want-,  AllowOptions *) 
	Silent* = LCP.Silent;
	Passive* = LCP.Passive;
	NegMRU* = LCP.NegMRU;
	NegAsyncMap* = LCP.NegAsyncMap;
	NegMagicNumber* = LCP.NegMagicNumber;
	NegUPap* = LCP.NegUPap;
		
TYPE
	Options* = LCP.Options;
	(*es*)
	PhysAdr = ARRAY 6 OF SYSTEM.BYTE; 
	CommDevice* = POINTER TO RECORD (PT.Device)
		IpAdr*, GwAdr*, NetMask*: NetIP.Adr;
		AdrLen*: INTEGER;
		Start*, Stop*, Reset*: PROCEDURE;
		configurated*, ptp*: BOOLEAN;
		c*: LONGINT; (*COM Port *)
	END;
	
	PPPid* = POINTER TO PPPidDesc;
	PPPidDesc* = RECORD (HDLC.PPPUnitDesc)
		running:BOOLEAN;

		LCPfsm: LCP.LCPfsm;		(* LCP Protocol *)
		IPCPfsm: IPCP.IPCPfsm;	(* IPCP Protocol *)
		PAPStat: PAP.PAPStat;	(* PAP Protocol *)
		me: (*es*)(*PT.*)CommDevice;
	END;
	
VAR ppp:PPPid;	ch: (*es*)LONGINT(*P.SerialChannel*);

	PROCEDURE ^Start*(id:PPPid);	
	PROCEDURE ^Stop*(id:PPPid);	
	PROCEDURE ^SendPacket*(id:PPPid; prno: INTEGER; item: PT.Item);

PROCEDURE * Connect (me: Oberon.Task);
VAR prno: INTEGER; item: PT.Item;
BEGIN
	IF V24.Available(ppp.me.c) > 0 THEN
		prno := 0; NEW(item);
		HDLC.ReceivePacket(ppp, prno, item);
		IF ppp.me.state = PT.open THEN
			Oberon.Remove(ppp.task); ppp.task := NIL;
		END;
	END;
END Connect;		
	
(* --------------------------------------------------------------------------- *)
(* Dummy Procedures - for Packet Tools (needs parameterless procedures!) *)
	
	PROCEDURE StartInst*;
	BEGIN 
		Start(ppp); (* send first request to peer *)
		(* install task to negotiate PPP and finally open device *)
		NEW(ppp.task);
		ppp.task.safe := FALSE; ppp.task.time := 0;
		ppp.task.handle := Connect; Oberon.Install(ppp.task);
	END StartInst;
	
	PROCEDURE StopInst*; 
	BEGIN Stop(ppp);  END StopInst;

	(*es*)
	PROCEDURE * AvailableInst (dev: PT.Device): BOOLEAN;
	BEGIN RETURN V24.Available(dev(CommDevice).c) > 0; END AvailableInst;
	
	PROCEDURE * ReceiveInst (dev: PT.Device; VAR prno: INTEGER;  
							VAR src: ARRAY OF SYSTEM.BYTE; VAR item: PT.Item);
	BEGIN  HDLC.ReceivePacket(ppp, prno, item); END ReceiveInst;
	
	PROCEDURE SendInst* (dev: PT.Device; prno: INTEGER; 
	VAR dest: ARRAY OF  SYSTEM.BYTE; item: PT.Item);
	BEGIN SendPacket(ppp, prno, item) END SendInst;
	
	PROCEDURE ResetInst*; BEGIN END ResetInst;

(* --------------------------------------------------------------------------- *)
(* Real PPP-Procedure-Interface *)
				
	(* Start - Start the PPP-Instance:  active means that PPP starts sending Configure-Requests *)
	PROCEDURE Start*(id:PPPid);
	BEGIN
		IF ~id.running THEN id.running:=TRUE;
			LCP.LowerUp(id.LCPfsm);		
			LCP.Open(id.LCPfsm);
		END
	END Start;
		
	(* Stop - Stop the PPP-Instance *)
	PROCEDURE Stop*(id:PPPid);
	BEGIN
		IF id.running THEN id.running:=FALSE;
			IPCP.Close(id.IPCPfsm);
			LCP.Close(id.LCPfsm);
			(*es, close the device *)
			id.me.state := PT.closed;
			(* hack to signal HDLC.CheckTimer to swallow log output *)
			id.cname := "";
		END
	END Stop;
	
	(* Remove - Remove the PPP-Instance completely *)
	PROCEDURE Remove*(VAR id:PPPid);
	BEGIN Stop(id);
(*es??? no unistall for devices in NetBase found 
		id.task.UnInstall;	(* Remove Task *)
		PT.UnInstallDevice(id.me);
es*)
		id:=NIL;
	END Remove;
	
	
	(* SendPacket - Interface for IP-Client to send Item *)
	PROCEDURE SendPacket*(id:PPPid; prno: INTEGER; item: PT.Item);
		VAR a: ARRAY HDLC.ArrayLength OF CHAR; pos: INTEGER;
	BEGIN
		IF id.running THEN
			IF (*es*)prno(*item.type*) = ARP THEN
				item.data(*.data*)[7] := 2X;
				PT.Copy(item.data(*.data*)[24], item.data(*.data*)[14], NetIP.AdrLen);
				PT.Copy(id.me.IpAdr, item.data(*.data*)[24], NetIP.AdrLen);
				(*es???*)
				Debug.String("PT.arprec:. whatdowedo?");Debug.Ln; HALT(99);
				(* PT.arprec(item) *)
			ELSIF  (*es*)prno(*item.type*) = (*es*)IPPROT(*IP*) THEN 
				(*es*)
				IF id.me.state = PT.open THEN
					pos := HDLC.HDLCHeaderLen + HDLC.StartPos;
	  		  	SYSTEM.MOVE(SYSTEM.ADR(item.data[item.ofs]), 
	  		  	SYSTEM.ADR(a[pos]), item.len);
					HDLC.SendPacket(id, PPPIP, a, pos, item.len)
				ELSE
					Debug.String("IP Packet to send discarded. Device not open.");
					Debug.Ln; 
				END;
				(* pos := HDLC.HDLCHeaderLen + HDLC.StartPos;
				    SYSTEM.MOVE(SYSTEM.ADR(item.data.data[0]), 
					SYSTEM.ADR(a[pos]), item.len);
					HDLC.SendPacket(id, PPPIP, a, pos, item.len)
				*)
			ELSE
				Debug.String("unknown packet. whatdowedo?"); 
				Debug.Hex((*es*)prno(*item.type*)); Debug.Ln
			END
		END;
		(*es*)PT.RecycleItem(item);
		(* PT.PutItem(PT.empty, item) (* dm: 21.10.96 *) *)
END SendPacket;

(* Install- Install a PPP-Instance for Channel c, with specified IP-Adr:  
		Null-IPAdr means no wishes
	    LCPwo: LCPWant-Options, LCPAllow-Options: See Options List
*)
	PROCEDURE Install*(c: (*es*)LONGINT(*P.SerialChannel*); 
		cname: ARRAY OF CHAR; 
		VAR loginuser, loginpasswd, papuser, pappasswd, sstr: ARRAY OF CHAR; 
		OurIP, HisIP, NetMask: NetIP.Adr; LCPwo, LCPao: Options; nretries: INTEGER;
		timeout: LONGINT; VAR id: PPPid);
	VAR i:INTEGER;
	BEGIN
		NEW(id); id.running:=FALSE;
		HDLC.Init(id, c, cname, sstr, loginuser, loginpasswd);
		(*es*)(* Init CommDevice *) 
		NEW(id.me); FOR i:=0 TO NetIP.AdrLen-1 DO id.me.IpAdr[i]:=0X; 
		id.me.GwAdr[i]:=0X; id.me.NetMask[i]:=NetMask[i] END;
		id.me.Start:=StartInst; id.me.Stop:=StopInst; 
		id.me.Reset:=ResetInst; id.me.Send:=SendInst;
(*es*)id.me.Receive := ReceiveInst; id.me.Available := AvailableInst; 
		id.c := c; id.me.c := id.c;
		id.me.typ := PT.nobroadcast; id.me.sndCnt := 0; id.me.recCnt := 0;
(**) id.me.AdrLen:=0; id.me.configurated:=FALSE; id.me.ptp:=TRUE;
		FSM.ActTimeout:=timeout*1000; FSM.ActMaxConfReqs:=nretries;
		LCP.Init(id.LCPfsm, LCPwo, LCPao, id);
		PAP.Init(id.PAPStat, id, papuser, pappasswd);
		IPCP.Init(id.IPCPfsm, id, OurIP, HisIP);
		(* id.task.Install(HDLC.ReceivePacket); 
		id.task.Notify;	(* Install Task *)*)
		(*es*)PT.InstallDevice(id.me);
		id.me.state := PT.pending;
		Out.String(cname); Out.String(" device installed on COM"); 
		Out.Int(c+1, 1); Out.Ln
		(*PT.InsertDevice(id.me);*)
	END Install;

(* --------------------------------------------------------------------------- *)
(* Upcalls from LCP, IPCP, HDLC *)	
	
	(* LCPUp - Called by LCP when LCP is ready *)
	PROCEDURE * LCPUp (U:HDLC.PPPUnit);
	BEGIN
		Debug.String("LCP is finally ready!!"); Debug.Ln;
		IF LCP.NegUPap IN U(PPPid).LCPfsm.ho.O THEN	(* auth is requested by peer *)
			PAP.LowerUp(U(PPPid).PAPStat)
		END;
		IPCP.LowerUp(U(PPPid).IPCPfsm);
		IPCP.Open(U(PPPid).IPCPfsm);
	END LCPUp;
	
	(* LCPDown - Called by LCP when LCP is closed *)
	PROCEDURE * LCPDown (U:HDLC.PPPUnit); 
	BEGIN 
		IPCP.LowerDown(U(PPPid).IPCPfsm);
		IF LCP.NegUPap IN U(PPPid).LCPfsm.ho.O THEN	(* auth is requested by peer *)
			PAP.LowerDown(U(PPPid).PAPStat)
		END
	END LCPDown;
	
	(* LCPProtRej - Called by LCP when a Protocol Reject has arrived *)
	PROCEDURE * LCPProtRej (U:HDLC.PPPUnit; prot:INTEGER);
	BEGIN
		WITH U:PPPid DO
			IF prot=LCP.LCP THEN	FSM.ProtReject(U.LCPfsm);	(* LCP cannot be rejected *)
			ELSIF prot=IPCP.IPCP THEN Debug.String("IPCP Protocol rejected!! Serious Problem!"); Debug.Ln;
			ELSE	Debug.String("Protocol rejected:"); Debug.Int(prot, 8); Debug.Ln;
			END
		END
	END LCPProtRej;
	
	(* IPCPUp - Called by IPCP when IPCP is ready *)
	PROCEDURE * IPCPUp (U:HDLC.PPPUnit);
	BEGIN
		WITH U:PPPid DO 
			U.me.IpAdr:=U.IPCPfsm.go.OurAddress;
			U.me.GwAdr:=U.IPCPfsm.ho.HisAddress;
  (*es*)NetIP.routes[0].adr := U.IPCPfsm.go.OurAddress;
  		  NetSystem.hostIP := SYSTEM.VAL(LONGINT,U.IPCPfsm.go.OurAddress);
  		  NetSystem.ToNum(NetSystem.hostIP, NetSystem.hostName);	(* temporary *)
			NetIP.routes[0].gway := U.IPCPfsm.ho.HisAddress;
			IF U.me.state = PT.open THEN
				Debug.String("Warning: device already open"); Debug.Ln;
			END;
			U.me.state := PT.open; (* open device *)
	 (**)U.me.configurated:=TRUE;
			Debug.String("OurAddress = "); Debug.Hex(SYSTEM.VAL(LONGINT, U.me.IpAdr)); Debug.Ln;
			Debug.String("HisAddress = "); Debug.Hex(SYSTEM.VAL(LONGINT, U.me.GwAdr)); Debug.Ln;
			IF LCP.NegUPap IN U.LCPfsm.ho.O THEN PAP.LowerUp(U.PAPStat) END
		END;
		Debug.String("IPCP is finally ready!!"); Debug.Ln; Debug.Ln;
		(*es*) Out.String("IPCP is finally ready. Device opened."); Out.Ln;
		Debug.rollback := Debug.LogLen;
		(**)
	END IPCPUp;
	
	(* IPCPDown - Called by IPCP when IPCP is closed *)
	PROCEDURE * IPCPDown (U:HDLC.PPPUnit);
	BEGIN
		WITH U: PPPid DO
			U.me.configurated:=FALSE;
	   	PAP.LowerDown(U.PAPStat)
	   END
	END IPCPDown;

(* Receive - Called by HDLC to demultiplex the protocol *)
	PROCEDURE * Receive (U:HDLC.PPPUnit; prot:INTEGER; 
			VAR p: ARRAY OF CHAR; pos, len:INTEGER; 
			VAR prno: INTEGER; VAR item: PT.Item);
	VAR i: INTEGER;
	BEGIN
		WITH U:PPPid DO
			IF prot=LCP.LCP THEN	LCP.Input(U.LCPfsm, p, pos, len);
			ELSE
				IF U.LCPfsm.State=FSM.Opened THEN
					(* No other packets unless LCP is open *)
					IF prot=PAP.PAPProt THEN PAP.Input(U.PAPStat, p, pos, len)
					ELSE
						IF LCP.NegUPap IN U(PPPid).LCPfsm.ho.O THEN
							IF U.PAPStat.state=PAP.Open THEN  
								(* No other packets unless Auth is completed*)
								IF prot=IPCP.IPCP THEN	IPCP.Input(U.IPCPfsm, p, pos, len)
								ELSE
									IF U.IPCPfsm.State=FSM.Opened THEN	
										(* No IP packets unless IPCP is open *)
										IF prot=PPPIP THEN		(* only IP-Packets *)
											(*es*)(* Item provided by NetBase.PollDevices *)
											(* PT.NewItem(item); item.cd:=U.me;*)
											 item.len:=len; 
											(*es*)prno := IPPROT;(*item.type:= IP*);
											SYSTEM.MOVE(SYSTEM.ADR(p[pos]), 
												SYSTEM.ADR(item.data(*.data*)[0]), len);
											(*es???*)Debug.String("PT.iprec 0");
											(*PT.iprec(item)*)
										ELSE Debug.String("Unknown Protocol: "); 
											Debug.Int(prot,8); Debug.Ln;
											LCP.SendProtRej(U.LCPfsm, p, pos-4, len+4); 
											(* dm 11.10.96; pos-2, len+2 *)
										END
									END
								END
							END
						ELSE
							IF prot=IPCP.IPCP THEN IPCP.Input(U.IPCPfsm, p, pos, len)
							ELSE
								IF U.IPCPfsm.State=FSM.Opened THEN
									(* No IP packets unless IPCP is open *)
									IF prot=PPPIP THEN		(* only IP-Packets *)
										(*es*)(* Item provided by NetBase.PollDevices *)
										(* PT.NewItem(item); item.cd:=U.me;*)
										 item.len:=len; 
										(*es*)prno := IPPROT; (*item.type := IP*);
										SYSTEM.MOVE(SYSTEM.ADR(p[pos]), 
											SYSTEM.ADR(item.data(*.data*)[0]), len);
										(*es*)Debug.String("PT.iprec 1");
										Debug.Int(item.ofs, 5); Debug.Ln;
										(*PT.iprec(item)*)
									ELSE Debug.String("Unknown Protocol: "); 
										Debug.Int(prot,8); Debug.Ln;
										LCP.SendProtRej(U.LCPfsm, p, pos-4, len+4); 
										(* dm 11.10.96; pos-2, len+2 *)
									END
								END
							END
						END
					END
				END
			END
		END
	END Receive;	
	
(* --------------------------------------------------------------------------- *)
(* PPP-User-Interface *)
	
	PROCEDURE SetIP(n0,n1,n2,n3:INTEGER; VAR ip:NetIP.Adr);	(* n1.n2.n3.n4 *)
	BEGIN ip[0]:=CHR(n0); ip[1]:=CHR(n1); ip[2]:=CHR(n2); ip[3]:=CHR(n3);
	END SetIP;
	
	PROCEDURE Hex2Set(A: ARRAY OF CHAR):SET;
		VAR d, i, j, k, ch, x:INTEGER; s: SET;
	BEGIN s:={}; i:=0; WHILE A[i]=" " DO INC(i); END;
		x:=31; ch:=ORD(A[i]); j:=0;
		WHILE (j<8) DO
			IF (ch>=ORD("0")) & (ch<=ORD("9")) THEN k:=ch-ORD("0");
			ELSIF (ch>=ORD("A")) & (ch<=ORD("F")) THEN k:=ch+10-ORD("A");
			ELSE RETURN {};
			END;
			d:=8; WHILE d>0 DO  IF d<=k THEN k:=k-d; INCL(s, x) END;   DEC(x); d:=d DIV 2;  END;
			INC(i); INC(j); ch:=ORD(A[i]);
		END;
		IF (ch=0) OR (ch=20H) THEN RETURN s; ELSE RETURN {} END
	END Hex2Set;
				
	(* InstPPP - Start a PPPConnection with Channel162 as Command *)
	(* Options:   /IP  OurIP HisIP												 8 Integers, no ".",  0 0 0 0 means no wish
						/NetMask MyNetMask									 4 Integer, no ".", default: 255 255 255 255
	 					/Silent															 If Silent, PPP does not try to connect himself
	 					/Rtr  nofRetries												Number of Retries when no or bad answer
	  				   /TO  nofTimeOuts											TimeOut Time between Retries in seconds
	  				   /MRUWant  Value (1500 usual) 				 	 Size of packets we want to sent 
	   				  /MRUAllow													 Do we allow him to send smaller packets than 1500 bytes?
	   				  /AsyWant  XHexValue (p.e X00000000)		  Bitarray of ASCII-Char. from 0 to 31 we want to send with ESC-Code
	   				  /AsyAllow  XHexValue (p.e X0000FF00)          Bitarray of ASCII-Char. from 0 to 31 he must send with ESC-Cod
	   				  /MagWant													  MagicNumber wanted (for Loop-Detection)
	   				  /MagAllow													 MagicNumber allowed
	   				  /LoginName "String"										loginname (used by login-procedure on Solaris)
	   				  /LoginPasswd "String"									password (used by login-procedure on Solaris)
	   				  /PAPName "string"										userid for PAP
	   				  /PAPPasswd "string"									  password for PAP
	   				  /SString "string"										    string to send to ppp-server first (Windows NT RAS Server needs it)
	   				  
	     *)

	PROCEDURE InstPPP*;
	VAR ourIP, hisIP, myNetMask: NetIP.Adr; n0,n1,n2,n3, rtr: INTEGER; 
		to: LONGINT;
		wo, ao: Options; InDone:BOOLEAN; S: Texts.Scanner;
		(*es*)devName, (**) s, sstr, loginname, loginpasswd,
		papname, pappasswd:ARRAY 32 OF CHAR; ok: BOOLEAN; i:INTEGER;
		(*es*)(*obj: Base.Object;*)
	
		PROCEDURE Cmp(t:ARRAY OF CHAR):BOOLEAN;
			VAR i,j:INTEGER;
		BEGIN i:=1; j:=0;
			WHILE (s[i]#0X) & (t[j]=s[i]) DO INC(i); INC(j); END;
			RETURN (t[j]=0X)
		END Cmp;
				
		PROCEDURE InInt(VAR n:INTEGER);
		BEGIN
			WHILE (S.class = Texts.Char) & (S.c = 0DX) DO Texts.Scan(S) END; 
			IF S.class=Texts.Int THEN n:=SHORT(S.i); Texts.Scan(S);
			ELSE InDone:=FALSE
			END;
		END InInt;
		
		PROCEDURE InName(VAR u:ARRAY OF CHAR);
		BEGIN 
			WHILE (S.class = Texts.Char) & (S.c = 0DX) DO Texts.Scan(S) END;
			IF S.class=Texts.String THEN COPY(S.s, u); Texts.Scan(S)
			ELSE InDone:=FALSE
			END;
		END InName;
		
	BEGIN
		ao.O:={}; wo.O:={}; ourIP:=IPCP.ZeroIP; hisIP:=IPCP.ZeroIP; 
		rtr:=FSM.DefMaxConfReqs; to:=FSM.DefTimeout; 
		loginname[0] := 0X; loginpasswd[0] := 0X; papname[0] := 0X; 
		pappasswd[0] := 0X; sstr[0] := 0X;
		FOR i := 0 TO NetIP.AdrLen - 1 DO myNetMask[i] := 0FFX END;

(*es*)
		Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
	IF S.class = Texts.Name THEN
		IF S.s[0] # "C" THEN Texts.Scan(S) END;	(* old-style config? *)
		devName := "PPP";
		IF S.class = Texts.Name THEN
			IF S.s = "COM1" THEN ch := V24.COM1
			ELSIF S.s = "COM2" THEN ch := V24.COM2
			ELSIF S.s = "COM3" THEN ch := V24.COM3
			ELSIF S.s = "COM4" THEN ch := V24.COM4
			ELSE HALT(99)
			END;
		ELSE
			HALT(99);
		END;
	ELSE
		HALT(99);
	END;
(*
	Oberon.OpenScanner(S, "PPP");
	IF S.class = Texts.String THEN
		COPY(S.s, NetSystem.hostName);
	END;
*)
	Oberon.OpenScanner(S, "DIAL.PAPName");
	IF S.class = Texts.String THEN
		i := 0;  WHILE S.s[i] # 0X DO INC(i) END;
		IF (S.s[0] # "<") OR (S.s[i-1] # ">") THEN	(* user specified something *)
			COPY(S.s, papname); INCL(ao.O, NegUPap);
			Out.String("PAPName: "); Out.String(papname); Out.Ln;
			IF HDLC.debug THEN
				Debug.String("PAPName: "); Debug.String(papname)
			END
		END
	END;
	Oberon.OpenScanner(S, "DIAL.PAPPassword");
	IF S.class = Texts.String THEN
		i := 0;  WHILE S.s[i] # 0X DO INC(i) END;
		IF (S.s[0] # "<") OR (S.s[i-1] # ">") THEN	(* user specified something *)
			COPY(S.s, pappasswd); INCL(ao.O, NegUPap); 
			IF HDLC.debug THEN
				Debug.String("PAPPassword: **** ")
			END
		END
	END;

(*es*) 
(*MRUWant*)InInt(i); INCL(wo.O, NegMRU); wo.MRU:=1500;
		IF HDLC.debug THEN Debug.String("MRUWant "); Debug.Int(i, 5) END;
(*MRUAllow*)INCL(ao.O, NegMRU); ao.MRU:=MaxMRU;
		IF HDLC.debug THEN Debug.String("MRUAllow") END;
(*AsyWant*) INCL(wo.O, NegAsyncMap); wo.AsyncMap:={};
		IF HDLC.debug THEN Debug.String("AsyWant "); 
		Debug.Hex(SYSTEM.VAL(LONGINT, wo.AsyncMap)); END;
(*AsyAllow*) INCL(ao.O, NegAsyncMap); ao.AsyncMap:={0..31};
		IF HDLC.debug THEN Debug.String("AsyAllow "); 
		Debug.Hex(SYSTEM.VAL(LONGINT, ao.AsyncMap)); END;
(*Silent* INCL(wo.O, Silent); IF HDLC.debug THEN Debug.String("Silent") END; *)
(*TO*) to:=5; IF HDLC.debug THEN Debug.String("TO "); Debug.Int(to, 5) END;
(*IP * SetIP(0,0,0,0, ourIP); IF HDLC.debug THEN Debug.String("ourIP ");  END; *)
(*IP* SetIP(0,0,0,0, hisIP); IF HDLC.debug THEN Debug.String("hisIP ");  END; *)
(*Netmask*) SetIP(255,255,255,0,myNetMask);
		IF HDLC.debug THEN Debug.String("myNetmask "); END;
			
(* alle Parameter oben mal fest gesetzt ???
		Texts.OpenScanner(S ,Oberon.Par.text, Oberon.Par.pos); 
		(*Texts.OpenScanner(S ,XOberon.ParText(), XOberon.ParPos());*) 
		ok:=FALSE; Texts.Scan(S);
		InName(s);
		InDone := TRUE;
		WHILE InDone DO
			IF s[0]="/" THEN
				IF Cmp("MRUWant") THEN 
					InInt(i); INCL(wo.O, NegMRU); wo.MRU:=i;
					IF HDLC.debug THEN Debug.String("MRUWant "); Debug.Int(i, 5) END
				ELSIF Cmp("MRUAllow") THEN 
					INCL(ao.O, NegMRU); ao.MRU:=MaxMRU;
					IF HDLC.debug THEN Debug.String("MRUAllow") END
				ELSIF Cmp("AsyWant") THEN
					InName(s); INCL(wo.O, NegAsyncMap); 
					wo.AsyncMap:=Hex2Set(s);
					IF HDLC.debug THEN Debug.String("AsyWant "); Debug.Hex(SYSTEM.VAL(LONGINT, wo.AsyncMap)) END
				ELSIF Cmp("AsyAllow") THEN
					InName(s); INCL(ao.O, NegAsyncMap); 
					ao.AsyncMap:=(*es*){}(*Hex2Set(s)*);
					IF HDLC.debug THEN Debug.String("AsyAllow "); Debug.Hex(SYSTEM.VAL(LONGINT, ao.AsyncMap)) END
				ELSIF Cmp("MagWant") THEN INCL(wo.O, NegMagicNumber); IF HDLC.debug THEN Debug.String("MagWant") END
				ELSIF Cmp("MagAllow") THEN INCL(ao.O, NegMagicNumber); IF HDLC.debug THEN Debug.String("MagAllow") END
				ELSIF Cmp("Silent") THEN INCL(wo.O, Silent); IF HDLC.debug THEN Debug.String("Silent") END
				ELSIF Cmp("Rtr") THEN InInt(i); rtr:=i; IF HDLC.debug THEN Debug.String("Rtr "); Debug.Int(i, 5) END
				ELSIF Cmp("TO") THEN InInt(i); to:=i; IF HDLC.debug THEN Debug.String("TO "); Debug.Int(i, 5) END
				ELSIF Cmp("IP") THEN
					InInt(n0); InInt(n1); InInt(n2); InInt(n3); SetIP(n0, n1, n2, n3, ourIP);
					IF HDLC.debug THEN Debug.String("ourIP "); Debug.Int(n0, 5); Debug.Int(n1, 5); Debug.Int(n2, 5); Debug.Int(n3, 5); Debug.Ln END;
					InInt(n0); InInt(n1); InInt(n2); InInt(n3); SetIP(n0, n1, n2, n3, hisIP);
					IF HDLC.debug THEN Debug.String("hisIP "); Debug.Int(n0, 5); Debug.Int(n1, 5); Debug.Int(n2, 5); Debug.Int(n3, 5) END
				ELSIF Cmp("Netmask") THEN
					InInt(n0); InInt(n1); InInt(n2); InInt(n3); SetIP(n0, n1, n2, n3, myNetMask);
					IF HDLC.debug THEN Debug.String("myNetmask "); Debug.Int(n0, 5); Debug.Int(n1, 5); Debug.Int(n2, 5); Debug.Int(n3, 5) END
				ELSIF Cmp("LoginName") THEN InName(s); COPY(s, loginname); IF HDLC.debug THEN Debug.String("LoginName: "); Debug.String(loginname) END
				ELSIF Cmp("LoginPasswd") THEN InName(s); COPY(s, loginpasswd); IF HDLC.debug THEN Debug.String("LoginPassword: "); Debug.String(loginpasswd) END
				ELSIF Cmp("PAPName") THEN InName(s); COPY(s, papname); INCL(ao.O, NegUPap); IF HDLC.debug THEN Debug.String("PAPName: "); Debug.String(papname) END
				ELSIF Cmp("PAPPasswd") THEN InName(s); COPY(s, pappasswd); INCL(ao.O, NegUPap); IF HDLC.debug THEN Debug.String("PAPPassword: "); Debug.String(pappasswd) END
				ELSIF Cmp("SString") THEN InName(s); COPY(s, sstr); IF HDLC.debug THEN Debug.String("SString "); Debug.String(sstr) END
				ELSE IF HDLC.debug THEN Debug.String("Illegal Option") END
				END;
				IF HDLC.debug THEN Debug.Ln END
			ELSE IF HDLC.debug THEN Debug.String(" No Option... "); Debug.String(s); Debug.Ln END
			END;
		InName(s);
		END;
es*)
(*es*)(*
		Base.GetObj("V24Channel162", obj);
		IF (obj#NIL) & (obj IS P.SerialChannel) THEN 
		ch:=obj(P.SerialChannel);
*)
(**)
			Install(ch, devName, loginname, loginpasswd,papname,
							pappasswd, (*es*)sstr(*str*),
						 ourIP, hisIP, myNetMask, wo, ao, rtr, to, ppp)
(*es*)(*END*)
	END InstPPP;
	
	(* RemovePPP - Remove PPP Connection completely *)
	PROCEDURE RemovePPP*; BEGIN Remove(ppp) 
	END RemovePPP;
	
	
	(* Stats - Print Out Information in XLog *)
	PROCEDURE Stats*;
		VAR W:Texts.Writer; s: FSM.String; f:LCP.LCPfsm; g:IPCP.IPCPfsm; 
			h: PAP.PAPStat; i:INTEGER; ip: NetIP.Adr;
	BEGIN
		IF ppp # NIL THEN 
			f:=ppp.LCPfsm; g:=ppp.IPCPfsm; h := ppp.PAPStat;
			Texts.OpenWriter(W); Texts.WriteString(W, "PPP-beta on "); 
			Texts.WriteString(W, ppp.cname);Texts.WriteLn(W);
			Texts.WriteString(W, "LCP is in state: "); FSM.GiveState(f.State, s); 
			Texts.WriteString(W, s); Texts.WriteLn(W);
			IF f.State=FSM.Opened THEN
				Texts.WriteString(W, "His MRU wish: "); 
				Texts.WriteInt(W, f.ho.MRU, 5); Texts.WriteLn(W);
				Texts.WriteString(W, "MTU configured to: "); 
				Texts.WriteInt(W, ppp.MTU, 5); Texts.WriteLn(W);
				Texts.WriteString(W, "Our MRU wish: "); 
				Texts.WriteInt(W, f.wo.MRU, 5); Texts.WriteLn(W);
				Texts.WriteString(W, "MRU configured to: "); 
				Texts.WriteInt(W, ppp.MRU, 5); Texts.WriteLn(W);
				Texts.WriteString(W, "SendAsyncMap configured to: "); 
				T.WriteSet(ppp.SendAsyncMap, s);
				Texts.WriteString(W, s); Texts.WriteLn(W);
				IF (NegMagicNumber IN f.ho.O) THEN 
					Texts.WriteString(W, "He wants MagicNumber"); 
					Texts.WriteLn(W);
				ELSE 
					Texts.WriteString(W, "He doesn't want MagicNumber"); 
					Texts.WriteLn(W);
				END;
				IF (NegMagicNumber IN f.go.O) THEN 
					Texts.WriteString(W, "MagicNumber active"); Texts.WriteLn(W);
				ELSE 
					Texts.WriteString(W, "MagicNumber disabled"); 
					Texts.WriteLn(W);
				END;
			END;
			Texts.WriteString(W, "IPCP is in state: "); FSM.GiveState(g.State, s); 
			Texts.WriteString(W, s); Texts.WriteLn(W);
			IF g.State=FSM.Opened THEN
				Texts.WriteString(W, "our Ip-Adr: "); 
				ip:=g.go.OurAddress;
				FOR i:=0 TO 2 DO 
					Texts.WriteInt(W, ORD(SYSTEM.VAL(CHAR, ip[i])),3); 
					Texts.Write(W, "."); 
				END;
				Texts.WriteInt(W, ORD(SYSTEM.VAL(CHAR, ip[3])),3); 
				Texts.WriteLn(W);
				Texts.WriteString(W, "his Ip-Adr: "); 
				ip:=g.ho.HisAddress;
				FOR i:=0 TO 2 DO 
					Texts.WriteInt(W, ORD(SYSTEM.VAL(CHAR, ip[i])),3); 
					Texts.Write(W, "."); 
				END;
				Texts.WriteInt(W, ORD(SYSTEM.VAL(CHAR, ip[3])),3); 
				Texts.WriteLn(W);
	(*			IF (NegVJ IN g.go.O) THEN 
						Texts.WriteString(W, "He wanted VJ:    MaxSlot: "); 
						Texts.WriteInt(W, g.ho.MaxSlot, 4);
					Texts.WriteString(W, "     CFlag: "); 
					Texts.WriteInt(W, g.ho.CFlag, 4); Texts.WriteLn(W); 
					END;
	*)		END;
			Texts.WriteString(W, "PAP is in state: "); PAP.GiveState(h, s); 
			Texts.WriteString(W, s); Texts.WriteLn(W);
			(*es*)Texts.Append(Oberon.Log, W.buf)
			(*Texts.Append(XOberon.XLog(), W.buf)*)
		END
	END Stats;	
	
		
BEGIN
	ppp := NIL;
	LCP.PPPHandleLCPUp:=LCPUp; LCP.PPPHandleLCPDown:=LCPDown; LCP.PPPHandleProtRej:=LCPProtRej;
	IPCP.PPPHandleIPCPUp:=IPCPUp; IPCP.PPPHandleIPCPDown:=IPCPDown;
	HDLC.PPPHandleReceive:=Receive;
END PPPMain.

System.Free PPPMain PPPLCP PPPIPCP PPPFSM PPPHDLC  PPPTools PacketTools ~

XPPCCompiler.Compile  PPPTools.Mod \Ns PPPHDLC.Mod \Ns PPPPAP.Mod \Ns
 PPPFSM.Mod \Ns PPPIPCP.Mod\Ns PPPLCP.Mod\Ns PPPMain.Mod \Ns
	 ~
XSystem.Call Cache40.Disable~

Install fuer Windows NT
XSystem.Call PPPMain.InstPPP "/TO" 5 
												"/IP" 0 0 0 0  0 0 0 0 
												"/Netmask" 255 255 255 224
												"/MRUWant" 1500 
												"/MRUAllow" 
												"/AsyWant" "00000000" 
												"/AsyAllow" "00000000" 
												"/PAPName" "ppp" 
												"/PAPPasswd" "mopsppp" 
												"/SString" "CLIENT" ~

Install fuer SUN
XSystem.Call PPPMain.InstPPP "/TO" 5 
												"/IP" 0 0 0 0  0 0 0 0 
												"/Netmask" 255 255 255 248
												"/MRUWant" 1500 
												"/MRUAllow" 
												"/AsyWant" "00000000" 
												"/AsyAllow" "00000000" 
												"/Silent"
												"/LoginName" "ppp" 
												"/LoginPasswd" "mopsppp" ~

(*es*)
PPPMain.InstPPP "/TO" 5 	     "/IP" 0 0 0 0  0 0 0 0 
"/Netmask" 255 255 255 248   "/MRUWant" 1500 
"/MRUAllow"    						"/AsyWant" "00000000" 
"/AsyAllow" "00000000"          "/Silent" ~

XSystem.Call	PPPMain.Stats ~		
XSystem.Call SetCD.Off "129.132.37.143" "129.132.37.129" ~
XSystem.Call TestCD.List ~

 do some work
 
XSystem.Call SetCD.On"129.132.37.143" "129.132.37.129" ~
XSystem.Call	PPPMain.RemovePPP ~

XSystem.Call RSystem.Free PPPMain ~
XSystem.Call RSystem.Free PPPLCP ~
XSystem.Call RSystem.Free PPPIPCP ~
XSystem.Call RSystem.Free PPPFSM ~
XSystem.Call RSystem.Free PPPPAP ~
XSystem.Call RSystem.Free PPPHDLC ~
XSystem.Call RSystem.Free PPPTools ~

XSystem.Call XMemTool.Dump 7E0000H 4000H T ~
XSystem.Call XMemTool.Dump 3E0000H 4000H T ~

My.Config

