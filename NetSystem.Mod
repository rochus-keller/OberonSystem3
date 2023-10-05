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

MODULE NetSystem;	(** portable *)	(* mg 16.08.96 *)

(* A Portable Oberon Interface to Internet Protocols *)

IMPORT SYSTEM, Kernel, NetBase, NetPorts, NetIP, NetUDP, NetTCP, NetDNS, 
	Input, Texts, Oberon, TextFrames, Strings, Fonts;

CONST
	anyport* = 0;	(** any port value *)

(** result values *)
	done* = 0;	(** everything went ok *)
	error* = 1;	(** failure occured *)
	
(** return values of procedure State *)
	closed* = 0;	(** connection is closed (neither sending nor receiving) *)
	listening* = 1;	(** passive connection is listening for a request *)
	in* = 2;	(** receiving only *)
	out* = 3;	(** sending only *)
	inout* = 4;	(** sending and receiving is possible *)
	waitCon* =  5;	(** still waiting to be connected *)
	errorCon* =  6;	(** connecting failed *)

	CR = 0DX;  LF = 0AX;
	
	Trace = FALSE;

TYPE
	Connection* = POINTER TO ConnectionDesc;	(** handle for TCP connections *)
	ConnectionDesc* = RECORD
		port: NetPorts.Port;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER;
		Available: PROCEDURE (C: Connection; VAR res: INTEGER): LONGINT;
		Receive: PROCEDURE (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
		Send: PROCEDURE (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
	END;

	IPAdr* = LONGINT; (** IP address in network byte order *)

	Socket* = POINTER TO SocketDesc;	(** handle for UDP "connections" *)
	SocketDesc* = RECORD
		C: NetUDP.Connection;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER
	END;

	Password = POINTER TO PasswordDesc;
	PasswordDesc = RECORD
		service, user, host, passwd: ARRAY 64 OF CHAR;
		next: Password
	END;

VAR
	anyIP*: IPAdr;	(** "NIL" ip-number *)
	allIP*: IPAdr;	(** broadcast ip-number *)
	hostIP*: IPAdr;	(** main ip-number of local machine *)
	hostName*: ARRAY 64 OF CHAR;	(** main name of local machine *)
	started: BOOLEAN;
	W: Texts.Writer;
	passwords: Password;
	hex: ARRAY 17 OF CHAR;
	task: Oberon.Task;

PROCEDURE GetEntry (key, name: ARRAY OF CHAR; VAR arg0, arg1: ARRAY OF CHAR);
VAR
	S: Texts.Scanner;
	key0: ARRAY 64 OF CHAR;
	i, j: INTEGER;
BEGIN COPY(key, key0);
	i := 0; WHILE key0[i] # 0X DO INC(i) END;
	j := 0; WHILE name[j] # 0X DO key0[i] := name[j]; INC(i); INC(j) END;
	key0[i] := 0X; Oberon.OpenScanner(S, key0);
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, arg0); Texts.Scan(S)
	ELSE COPY("", arg0)
	END;
	IF (S.class = Texts.Char) & (S.c = ",") THEN Texts.Scan(S);
		IF S.class IN {Texts.Name, Texts.String} THEN COPY(S.s, arg1)
		ELSE COPY("", arg1)
		END
	ELSE COPY("", arg1)
	END
END GetEntry;
	
PROCEDURE GetEntry0 (key, name: ARRAY OF CHAR;  VAR arg: ARRAY OF CHAR);
VAR S: Texts.Scanner;  key0: ARRAY 64 OF CHAR;  i, j: INTEGER;
BEGIN
	COPY(key, key0);
	i := 0; WHILE key0[i] # 0X DO INC(i) END;
	j := 0; WHILE name[j] # 0X DO key0[i] := name[j]; INC(i); INC(j) END;
	key0[i] := 0X; Oberon.OpenScanner(S, key0);
	IF S.class IN {Texts.Name, Texts.String} THEN
		COPY(S.s, arg); Texts.Scan(S)
	ELSE
		COPY("", arg)
	END
END GetEntry0;

PROCEDURE ToNum0 (num: ARRAY OF CHAR; VAR n: INTEGER; VAR done: BOOLEAN);
VAR
	i: INTEGER;
BEGIN n := 0; i := 0;
	WHILE ("0" <= num[i]) & (num[i] <= "9") DO
		n := n * 10 + ORD(num[i]) - ORD("0"); INC(i)
	END;
	done := num[i] = 0X
END ToNum0;

PROCEDURE ToHost0 (num: ARRAY OF CHAR; VAR adr: NetIP.Adr; VAR done: BOOLEAN);
VAR
	addr: LONGINT;
	buf: ARRAY 32 OF CHAR;
	i, j, k, n: INTEGER;
BEGIN done := TRUE;
	addr := 0; i := 0; j := 0; 
	WHILE done & (j < 4) & (num[i] # 0X) DO
		k := 0;
		WHILE (num[i] # ".") & (num[i] # 0X) DO
			buf[k] := num[i]; INC(k); INC(i)
		END;
		buf[k] := 0X; ToNum0(buf, n, done);
		addr := ASH(addr, 8) + n; done := done & (n <= 256);
		IF num[i] = "." THEN INC(i) END;
		INC(j)
	END;
	NetBase.Copy(addr, adr, NetIP.AdrLen); NetBase.HostLToNet(adr);
	done := done & (j = 4) & (num[i] = 0X)
END ToHost0;

PROCEDURE AdrToStr(netAdr: ARRAY OF SYSTEM.BYTE;  VAR net: ARRAY OF CHAR);
VAR i, j: LONGINT;
BEGIN
	j := 0;
	FOR i := 0 TO NetBase.AdrLen-1 DO
		net[j] := hex[ORD(netAdr[i]) DIV 10H MOD 10H];
		net[j+1] := hex[ORD(netAdr[i]) MOD 10H];
		net[j+2] := ":";  INC(j, 3)
	END;
	DEC(j);  net[j] := 0X
END AdrToStr;

(* Look up an ethernet address to find ip address and hostname. *)

PROCEDURE FindAddress(key: ARRAY OF CHAR;  netAdr: ARRAY OF SYSTEM.BYTE;  VAR hostname, num: ARRAY OF CHAR);
VAR net: ARRAY 20 OF CHAR;  s: Texts.Scanner;  found: BOOLEAN;
BEGIN
	AdrToStr(netAdr, net);
	num[0] := 0X;  hostname[0] := 0X;
	IF net # "00:00:00:00:00:00" THEN
		Oberon.OpenScanner(s, key);  found := FALSE;
		WHILE (s.class = Texts.String) & ~found DO
			found := s.s = net;
			Texts.Scan(s);
			IF (s.class = Texts.Char) & (s.c = ",") THEN
				Texts.Scan(s);
				IF s.class = Texts.String THEN
					COPY(s.s, hostname);
					Texts.Scan(s);
					IF (s.class = Texts.Char) & (s.c = ",") THEN
						Texts.Scan(s);
						IF s.class = Texts.String THEN
							IF found THEN COPY(s.s, num) END;
							Texts.Scan(s)
						END
					ELSE
						s.class := Texts.Inval
					END
				END
			ELSE
				s.class := Texts.Inval
			END
		END;
		IF num[0] = 0X THEN
			hostname[0] := 0X;
			Texts.WriteString(W, net);  Texts.WriteString(W, " not found in ");
			Texts.WriteString(W, key);  Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	ELSE (* MAC adr all zero, ignore *)
	END
END FindAddress;

(** -- Adressing/Naming section. *)

(** Convert a dotted IP address string (e.g. "1.2.3.4") to an IPAdr value. *)

PROCEDURE ToHost* (num: ARRAY OF CHAR; VAR adr: IPAdr; VAR done: BOOLEAN);
VAR a: NetIP.Adr;
BEGIN
	ToHost0(num, a, done);
	IF done THEN NetBase.Copy(a, adr, NetIP.AdrLen)
	ELSE NetBase.Copy(anyIP, adr, NetIP.AdrLen)
	END
END ToHost;

(** Convert an IPAdr value to a dotted IP address string *)

PROCEDURE ToNum*(adr: IPAdr; VAR num: ARRAY OF CHAR);
	VAR i, j, n: LONGINT;
	PROCEDURE Digit(d: LONGINT);
	BEGIN
		num[j] := CHR(ORD("0")+d); INC(j)
	END Digit;
BEGIN
	j := 0;
	FOR i := 0 TO 3 DO
		n := adr MOD 256; adr := adr DIV 256;
		IF n >= 100 THEN
			Digit(n DIV 100); Digit((n DIV 10) MOD 10)
		ELSIF n >= 10 THEN
			Digit(n DIV 10)
		END;
		Digit(n MOD 10);
		num[j] := "."; INC(j)
	END;
	num[j-1] := 0X
END ToNum;

(** Procedure delivers the ip-number of a named host. If a symbolic name is given, it will be resolved by use of domain name
	servers. *)

PROCEDURE GetIP* (name: ARRAY OF CHAR; VAR IP: IPAdr);
VAR
	hostName, hostIP: ARRAY 64 OF CHAR;
	adr: NetIP.Adr;
	res: INTEGER;
	done: BOOLEAN;
BEGIN
	IF (CAP(name[0]) >= "A") & (CAP(name[0]) <= "Z") THEN
		GetEntry("NetSystem.Hosts.", name, hostName, hostIP);
		IF hostIP # "" THEN
			ToHost0(hostIP, adr, done)
		ELSE
			IF started THEN
				IF hostName # "" THEN
					NetDNS.HostByName(hostName, adr, res)
				ELSE NetDNS.HostByName(name, adr, res)
				END;
				done := (res = NetDNS.Done)
			ELSE
				done := FALSE
			END
		END
	ELSIF (name[0] >= "0") & (name[0] <= "9") THEN
		ToHost0(name, adr, done)
	ELSE done := FALSE
	END;
	IF ~done THEN IP := anyIP
	ELSE NetBase.Copy(adr, IP, NetIP.AdrLen)
	END
END GetIP;

(** GetName is the reverse of GetIP. Given an ip-number, it delivers the name of a host. *)

PROCEDURE GetName* (IP: IPAdr; VAR name: ARRAY OF CHAR);
VAR
	adr: NetIP.Adr;
	res: INTEGER;
BEGIN
	IF started THEN
		NetBase.Copy(IP, adr, NetIP.AdrLen);
		NetDNS.HostByNumber(adr, name, res)
	END;
	IF ~started OR (res # NetDNS.Done) THEN COPY("", name) END
END GetName;

(** -- TCP section. *)

(* Stream oriented communication *)

PROCEDURE TCPSetState (C: Connection);
BEGIN
	IF ~NetTCP.Connected(C.port(NetTCP.Connection)) THEN
		IF C.state = inout THEN C.state := out
		ELSIF C.state = in THEN C.state := closed
		END
	END
END TCPSetState;

PROCEDURE TCPAvailable (C: Connection; VAR res: INTEGER): LONGINT;
VAR
	len: LONGINT;
BEGIN len := NetTCP.Available(C.port(NetTCP.Connection));
	IF len < 0 THEN len := 0; res := error ELSE res := done END;
	TCPSetState(C); RETURN len
END TCPAvailable;

PROCEDURE TCPReceive (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
VAR
	l: LONGINT;
BEGIN l := 0;
	REPEAT l := len;
		NetTCP.Receive(C.port(NetTCP.Connection), buf, beg, l);
		IF l > 0 THEN beg := beg + l; len := len - l END
	UNTIL (len = 0) OR (l < 0);
	IF l < 0 THEN res := error ELSE res := done END;
	TCPSetState(C)
END TCPReceive;

PROCEDURE TCPSend (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN NetTCP.Send(C.port(NetTCP.Connection), buf, beg, len);
	IF len < 0 THEN res := error ELSE res := done END;
	TCPSetState(C)
END TCPSend;

PROCEDURE DmyAvailable (C: Connection; VAR res: INTEGER): LONGINT;
BEGIN res := error; RETURN 0
END DmyAvailable;

PROCEDURE DmyReceive (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN res := error
END DmyReceive;

PROCEDURE DmySend (C: Connection; VAR buf: ARRAY OF SYSTEM.BYTE; beg, len: LONGINT; VAR res: INTEGER);
BEGIN res := error
END DmySend;

PROCEDURE ^Cleanup(c: SYSTEM.PTR);

(** Procedure opens a connection. locPort, remPort, remIP are contained in the quadrupel <locIP, remIP, locPort, remPort>
	which determines a connection uniquely. As locIP is always the current machine, it is omitted. If remPort is equal to
	anyport or remIP is equal to anyIP, a passive connection will be opened. After execution, C is a brand new connection.
	res indicates any error. *)

PROCEDURE OpenConnection* (VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort: INTEGER; VAR res: INTEGER);
VAR
	conC: NetTCP.Connection;
	listC: NetTCP.Listener;
	remAdr: NetIP.Adr;
BEGIN
	IF started THEN
		NetBase.Copy(remIP, remAdr, NetIP.AdrLen); NEW(C);
		IF NetBase.Equal(remIP, NetIP.IPany, NetIP.AdrLen) OR (remPort = NetPorts.anyport) THEN
			NetTCP.Listen(listC, locPort, remAdr, remPort, C.res);
			IF C.res = NetTCP.Done THEN C.port := listC;
				C.state := listening; C.Available := DmyAvailable;
				C.Send := DmySend; C.Receive := DmyReceive;
				Kernel.RegisterObject(C, Cleanup, FALSE)
			ELSIF C.res # NetTCP.Timeout THEN C.res := error
			END;
			res := C.res
		ELSIF ~NetIP.IsBroadcast(remAdr) THEN
			NetTCP.Connect(conC, locPort, remAdr, remPort, C.res);
			IF C.res = NetTCP.Done THEN C.port := conC;
				C.state := inout; C.Available := TCPAvailable;
				C.Send := TCPSend; C.Receive := TCPReceive;
				Kernel.RegisterObject(C, Cleanup, FALSE)
			ELSIF C.res # NetTCP.Timeout THEN C.res := error
			END;
			res := C.res
		ELSE res := error
		END
	ELSE res := error
	END
END OpenConnection;

(** Like OpenConnection, but this procedure may return immediately and delay the actual opening of the connection.  
	In this case State() should be checked to wait for the connection status to change from waitCon. *)

PROCEDURE AsyncOpenConnection*(VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort:INTEGER; VAR res: INTEGER);
BEGIN
	OpenConnection(C, locPort, remIP, remPort, res)	(* currently implemented synchronously *)
END AsyncOpenConnection;

(** Procedure closes the connection. Connection can not be used for send operations afterwards. *)

PROCEDURE CloseConnection* (C: Connection);
BEGIN
	IF C # NIL THEN
		IF C.port IS NetTCP.Listener THEN C.state := closed;
			NetTCP.Close(C.port(NetTCP.Listener))
		ELSIF C.port IS NetTCP.Connection THEN
			IF C.state = inout THEN C.state := in
			ELSIF C.state = out THEN C.state := closed
			END;
			NetTCP.Disconnect(C.port(NetTCP.Connection))
		ELSE HALT(99)
		END;
		C.res := done
	END
END CloseConnection;

PROCEDURE Cleanup(c: SYSTEM.PTR);
VAR s: ARRAY 20 OF CHAR;
BEGIN
	WITH c: Connection DO
		IF c.state # closed THEN
			IF Trace THEN
				Kernel.WriteString("NetSystem: Cleanup ");
				ToNum(SYSTEM.VAL(IPAdr, c.port.rip), s);  Kernel.WriteString(s);
				Kernel.WriteChar(":");  Kernel.WriteInt(c.port.rport, 1);
				Kernel.WriteLn
			END;
			CloseConnection(c)
		END
	END
END Cleanup;

(** Indicates whether there exists a remote machine which wants to connect to the local one. This Procedure is only useful
	on passive connections. For active connections (State(C) # listen), it always delivers FALSE. *)

PROCEDURE Requested* (C: Connection): BOOLEAN;
BEGIN RETURN (C.port IS NetTCP.Listener) & NetTCP.Requested(C.port(NetTCP.Listener))
END Requested;

(** Procedure accepts a new waiting, active connection (newC) on a passive one (State(C) = listen). If no connection is 
	waiting, accept blocks until there is one or an error occurs. If C is not a passive connection, Accept does nothing
	but res is set to Done. *)

PROCEDURE Accept* (C: Connection; VAR newC: Connection; VAR res: INTEGER);
VAR
	conC: NetTCP.Connection;
BEGIN res := NetTCP.NotDone;
	IF C.port IS NetTCP.Listener THEN
		NetTCP.Accept(C.port(NetTCP.Listener), conC, res);
		IF res = NetTCP.Done THEN NEW(newC);
			newC.port := conC; newC.state := inout;
			newC.Available := TCPAvailable;
			newC.Send := TCPSend; newC.Receive := TCPReceive
		END
	END;
	C.res := res
END Accept;

(** Procedure returns the state of a connection (see constant section). *)

PROCEDURE State* (C: Connection): INTEGER;
BEGIN RETURN C.state
END State;

(** Returns the number of bytes which may be read without blocking. *)

PROCEDURE Available* (C: Connection): LONGINT;
BEGIN RETURN C.Available(C, C.res)
END Available;

(** Blocking read a single byte. *)

PROCEDURE Read* (C: Connection; VAR ch: CHAR);
BEGIN C.Receive(C, ch, 0, 1, C.res)
END Read;

(** Blocking read len bytes of data (beginning at pos in buf) to buf. *)

PROCEDURE ReadBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
BEGIN C.Receive(C, buf, pos, len, C.res);
END ReadBytes;

(** Blocking read two bytes in network byte ordering. *)

PROCEDURE ReadInt* (C: Connection; VAR x: INTEGER);
BEGIN C.Receive(C, x, 0, 2, C.res); NetBase.NetToHost(x)
END ReadInt;

(** Blocking read four bytes in network byte ordering. *)

PROCEDURE ReadLInt* (C: Connection; VAR x: LONGINT);
BEGIN C.Receive(C, x, 0, 4, C.res); NetBase.NetLToHost(x);
END ReadLInt;

(** Blocking read a string terminated by ( [CR]LF | 0X ). *)

PROCEDURE ReadString* (C: Connection; VAR s: ARRAY OF CHAR);
VAR
	ch, ch0: CHAR;
	i: INTEGER;
BEGIN i := -1; ch := 0X;
	REPEAT INC(i);
		ch0 := ch; C.Receive(C, ch, 0, 1, C.res); s[i] := ch;
	UNTIL (C.res = error) OR (ch = 0X) OR (ch = LF);
	IF (ch = LF) & (ch0 = CR) THEN
		s[i - 1] := 0X ELSE s[i] := 0X
	END
END ReadString;

(** Blocking write a single byte to C. *)

PROCEDURE Write* (C: Connection; ch: CHAR);
BEGIN C.Send(C, ch, 0, 1, C.res)
END Write;

(** Blocking write len bytes of data (beginning at pos in buf) to C. *)

PROCEDURE WriteBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
BEGIN C.Send(C, buf, pos, len, C.res)
END WriteBytes;

(** Blocking write two bytes in network byte ordering to C. *)

PROCEDURE WriteInt* (C: Connection; x: INTEGER);
BEGIN NetBase.HostToNet(x); C.Send(C, x, 0, 2, C.res)
END WriteInt;

(** Blocking write four bytes in network byte ordering to C. *)

PROCEDURE WriteLInt* (C: Connection; x: LONGINT);
BEGIN NetBase.HostLToNet(x); C.Send(C, x, 0, 4, C.res)
END WriteLInt;

(** Blocking write a string without "0X" and terminated by "CRLF" to C. *)

PROCEDURE WriteString* (C: Connection; s: ARRAY OF CHAR);
VAR
	cs: ARRAY 2 OF CHAR;
	i: INTEGER;
BEGIN  i := 0;
	WHILE s[i] # 0X DO INC(i) END;
	C.Send(C, s, 0, i, C.res);
	cs[0] := CR; cs[1] := LF;
	C.Send(C, cs, 0, 2, C.res)
END WriteString;

(** Procedure delivers the ip-number and port number of a connection's remote partner. *)

PROCEDURE GetPartner* (C: Connection; VAR remIP: IPAdr; VAR remPort: INTEGER);
BEGIN remPort := C.port.rport; NetBase.Copy(C.port.rip, remIP, NetIP.AdrLen)
END GetPartner;

(** -- UDP section. *)

(* Datagram oriented communication *)

(** Opens a socket which is dedicated to datagram services. locPort is registered to receive datagrams
	from any port and any host. *)

PROCEDURE OpenSocket* (VAR S: Socket; locPort: INTEGER; VAR res: INTEGER);
BEGIN
	IF started THEN NEW(S);
		NetUDP.Open(S.C, locPort, NetIP.IPany, NetPorts.anyport, S.res);
		IF S.res = NetUDP.Done THEN S.state := inout
		ELSE S.C := NIL; S.res := error
		END;
		res := S.res
	ELSE res := error
	END
END OpenSocket;

(** Closes the socket. You can not receive datagrams anymore. *)

PROCEDURE CloseSocket* (S: Socket);
BEGIN S.state := closed; NetUDP.Close(S.C); S.C := NIL; S.res := done
END CloseSocket;

(** Sends len bytes of data (beginning at pos in buf) to the host specified by remIP and remPort. *)

PROCEDURE SendDG* (S: Socket; remIP: IPAdr; remPort: INTEGER; pos, len: LONGINT; VAR buf: ARRAY OF SYSTEM.BYTE);
VAR
	radr: NetIP.Adr;
BEGIN NetBase.Copy(remIP, radr, NetIP.AdrLen);
	NetUDP.Send(S.C, radr, remPort, buf, pos, len); S.res := done
END SendDG;

(** Stores an entire datagram in buf beginning at pos. On success (S.res = done), remIP and remPort indicate the sender,
	len indicate the length of valid data. *)

PROCEDURE ReceiveDG*(S: Socket; VAR remIP: IPAdr; VAR remPort: INTEGER; pos: LONGINT; VAR len: LONGINT;
	VAR buf: ARRAY OF SYSTEM.BYTE);
VAR
	radr: NetIP.Adr;
BEGIN NetUDP.Receive(S.C, radr, remPort, buf, pos, len);
	IF len >= 0 THEN NetBase.Copy(radr, remIP, NetIP.AdrLen); S.res := done ELSE S.res := error END
END ReceiveDG;

(** Returns the size of the first available datagram on the socket. *)

PROCEDURE AvailableDG* (S: Socket): LONGINT;
BEGIN RETURN NetUDP.Available(S.C)
END AvailableDG;

(* Conversions *)

(** Write 2 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; x: INTEGER);
BEGIN NetBase.HostToNet(x);
	SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutInt;

(** Write 4 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutLInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; x: LONGINT);
BEGIN NetBase.HostLToNet(x);
	SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutLInt;

(** Read 2 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; VAR x: INTEGER);
BEGIN SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetToHost(x)
END GetInt;

(** Read 4 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetLInt* (VAR buf: ARRAY OF SYSTEM.BYTE; pos: INTEGER; VAR x: LONGINT);
BEGIN SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetLToHost(x)
END GetLInt;

(** -- Passwords section. *)

PROCEDURE WriteURL(VAR service, user, host: ARRAY OF CHAR);
BEGIN
	Texts.WriteString(W, "NetSystem.SetUser ");  Texts.WriteString(W, service);  
	Texts.Write(W, ":");  Texts.WriteString(W, user);  Texts.Write(W, "@");  
	Texts.WriteString(W, host);  Texts.WriteString(W, " ~"); Texts.WriteLn(W)
END WriteURL;

(** Retrieve the password for user using service on host.  Parameters service, host and user must be specified. 
Parameter user is in/out.  If empty, it returns the first (user,password) pair found, otherwise it returns the
specified user's password. *)

PROCEDURE GetPassword*(service, host: ARRAY OF CHAR;  VAR user, password: ARRAY OF CHAR);
VAR pass: Password;  r: Texts.Reader;  ch: CHAR;
BEGIN
	Strings.Lower(service, service);  Strings.Lower(host, host);
	pass := passwords;
	WHILE (pass # NIL) & ~((pass.service = service) & (pass.host = host) & ((user = "") OR (pass.user = user))) DO
		pass := pass.next
	END;
	IF pass # NIL THEN
		COPY(pass.user, user);  COPY(pass.passwd, password)
	ELSE
		IF (service # "") & (user # "") THEN
			IF Oberon.Log.len > 0 THEN
				Texts.OpenReader(r, Oberon.Log, Oberon.Log.len-1);
				Texts.Read(r, ch);
				IF ch # CHR(13) THEN Texts.WriteLn(W) END
			END;
			WriteURL(service, user, host);  Texts.Append(Oberon.Log, W.buf)
		END;
		COPY("", user); COPY("", password)
	END
END GetPassword;

(** Remove password for user using service on host. *)

PROCEDURE DelPassword*(service, user, host: ARRAY OF CHAR);
	VAR ppass, pass: Password;
BEGIN
	Strings.Lower(service, service);  Strings.Lower(host, host);
	ppass := NIL; pass := passwords;
	WHILE (pass # NIL) & ((pass.service # service) & (pass.host # host) & (pass.user # user)) DO
		ppass := pass; pass := pass.next
	END;
	IF pass # NIL THEN
		IF ppass # NIL THEN
			ppass.next := pass.next
		ELSE
			passwords := pass.next
		END
	END
END DelPassword;

(** Command NetSystem.SetUser { service ":" ["//"] user [ ":" password ] "@" host [ "/" ] } "~" <enter password>
		If password is not specified in-line, prompts for the password for the (service, host, user) triple. 
		The (service, host, user, password) 4-tuple is stored in memory for retrieval with GetPassword. 
		Multiple identical passwords may be set with one command. *)
		
PROCEDURE SetUser*;
	VAR
		R: Texts.Reader;
		service, usr, host, pwd: ARRAY 64 OF CHAR;
		pass, list: Password;
		ok, verbose: BOOLEAN;
		ch: CHAR;

	PROCEDURE Next(VAR str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		Texts.Read(R, ch);
		WHILE ~R.eot & ((ch <= " ") OR (ch = ":") OR (ch = "@") OR (ch = "/") OR ~(R.lib IS Fonts.Font)) DO
			Texts.Read(R, ch)
		END;
		i := 0;
		WHILE ~R.eot & (ch > " ") & (ch # ":") & (ch # "@") & (ch # "/") & (ch # "~") & (R.lib IS Fonts.Font) DO
			str[i] := ch; INC(i); Texts.Read(R, ch)
		END;
		str[i] := 0X
	END Next;
	
	PROCEDURE ReadPwd;
		VAR i: LONGINT;
	BEGIN
		Texts.WriteString(W, "Password: ");  Texts.Append(Oberon.Log, W.buf);
		Input.Read(ch); i := 0;
		WHILE ch > " " DO
			IF ch = 7FX THEN
				IF i > 0 THEN
					Texts.Delete(Oberon.Log, Oberon.Log.len-1, Oberon.Log.len);
					DEC(i)
				END
			ELSE
				Texts.Write(W, "*");  Texts.Append(Oberon.Log, W.buf);
				pwd[i] := ch;  INC(i)
			END;
			Input.Read(ch)
		END;
		pwd[i] := 0X;
		Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
	END ReadPwd;
		
	PROCEDURE Replace(p: Password);
	VAR q, prev: Password;  msg: ARRAY 12 OF CHAR;
	BEGIN
		q := passwords;  prev := NIL;
		WHILE (q # NIL) & ~((q.service = p.service) & (q.host = p.host) & (q.user = p.user)) DO
			prev := q;  q := q.next
		END;
		IF q # NIL THEN	(* password exists, delete old one first *)
			IF prev = NIL THEN passwords := passwords.next
			ELSE prev.next := q.next
			END;
			msg := "replaced"
		ELSE
			msg := "set"
		END;
		p.next := passwords;  passwords := p;
		IF verbose THEN
			Texts.WriteString(W, p.service);  Texts.Write(W, ":");  
			Texts.WriteString(W, p.user);  Texts.Write(W, "@");  Texts.WriteString(W, p.host);
			Texts.WriteString(W, " password ");  Texts.WriteString(W, msg);
			Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
		END
	END Replace;
	
BEGIN
	Texts.OpenReader(R, Oberon.Par.text, Oberon.Par.pos);
	ok := TRUE;  verbose := FALSE;  list := NIL;
	WHILE ~R.eot & ok DO
		ok := FALSE;  Next(service);
		IF service = "\v" THEN verbose := TRUE; Next(service) END;
		Strings.Lower(service, service);
		IF ch = ":" THEN
			Next(usr);
			IF ch = "@" THEN	(* no password specified, prompt for password later *)
				Next(host);  Strings.Lower(host, host);
				IF host # "" THEN
					NEW(pass);  pass.next := list;  list := pass;	(* add to temp list *)
					COPY(service, pass.service); COPY(host, pass.host); COPY(usr, pass.user);
					ok := TRUE
				END
			ELSIF ch = ":" THEN	(* password specified in-line *)
				Next(pwd);
				IF ch = "@" THEN
					Next(host);  Strings.Lower(host, host);
					IF host # "" THEN
						NEW(pass);  COPY(service, pass.service); COPY(host, pass.host); 
						COPY(usr, pass.user);  COPY(pwd, pass.passwd);
						Replace(pass);  ok := TRUE
					END
				END
			END
		END
	END;
	IF list # NIL THEN
		ReadPwd;
		IF ch = 0DX THEN	(* password entered *)
			WHILE list # NIL DO
				pass := list;  list := list.next;  COPY(pwd, pass.passwd);  Replace(pass)
			END
		END
	END
END SetUser;

(** Command NetSystem.ClearUser ~  Clear all passwords from memory. *)

PROCEDURE ClearUser*;
BEGIN
	passwords := NIL
END ClearUser;

(** -- Initialisation section. *)

PROCEDURE SetDevices;
VAR
	T: Texts.Text;  device, name, arg: ARRAY 32 OF CHAR;  i: INTEGER;
	F: TextFrames.Frame;
BEGIN
	NEW(T);
	i := 0; device := "Device0"; GetEntry("NetSystem.Hosts.", device, name, arg);
	WHILE (i < NetBase.MaxDevices) & (name # "") & (name[0] # "<") DO
		Texts.Open(T, "");
		Texts.WriteString(W, name);  Texts.Write(W, " ");  Texts.WriteString(W, arg);
		Texts.WriteLn(W);  Texts.Append(T, W.buf);
		F := TextFrames.NewText(T, 0);  TextFrames.Call(F, 0, FALSE);
		INC(i); device[6] := CHR(i+ORD("0"));
		GetEntry("NetSystem.Hosts.", device, name, arg)
	END
END SetDevices;

PROCEDURE SetRoutes;
VAR
	route: NetIP.Route;
	key: ARRAY 64 OF CHAR;
	hostname, num, device, arp, dmy, gateway: ARRAY 64 OF CHAR;
	i, j, devnum: LONGINT;  s: ARRAY 32 OF CHAR;
	done: BOOLEAN;
	dev: NetBase.Device;
BEGIN
	key := "NetSystem.Hosts.Route0.";
	i := 0;  GetEntry0(key, "Device", device);
	WHILE (i < NetIP.MaxRoutes) & (device # "") DO
		Strings.Lower(device, device);
		IF device = "default" THEN devnum := 0
		ELSIF Strings.Prefix("device", device) & (device[6] >= "0") & (device[6] <= "9") & (device[7] = 0X) THEN
			devnum := ORD(device[6])-ORD("0")
		ELSE devnum := -1
		END;
		dev := NetBase.FindDevice(devnum);
		IF dev # NIL THEN
			NEW(route);  route.dev := dev;  (*log := FALSE;*)
			GetEntry0(key, "Mode", arp);
			IF arp = "arp" THEN INCL(route.options, NetIP.arpopt) END;
			GetEntry(key, "Host", hostname, num); ToHost0(num, route.adr, done);
			IF ~done THEN	(* try using table *)
				FindAddress("NetSystem.Hosts.Table", route.dev.hostAdr, hostname, num);
				ToHost0(num, route.adr, done);  (*log := log OR done*)
			END;
			IF ~done THEN
				(* ok if still to be assigned, e.g. PPP *)
				NetBase.Copy(anyIP, route.adr, NetIP.AdrLen)	(* must be assigned later *)
			ELSE
				IF i = 0 THEN	(* first host *)
					COPY(hostname, hostName);
					NetBase.Copy(route.adr, hostIP, NetIP.AdrLen)
				END
			END;
			GetEntry(key, "Gateway", gateway, num); ToHost0(num, route.gway, done);
			IF ~done THEN	(* ok if not arp, e.g. SLIP or PPP *)
				NetBase.Copy(anyIP, route.gway, NetIP.AdrLen)
			END;
			GetEntry(key, "Netmask", dmy, num); ToHost0(num, route.subnet, done);
			IF ~done THEN	(* ok if not arp, e.g. SLIP or PPP *)
				NetBase.Copy(anyIP, route.subnet, NetIP.AdrLen)	(* all destinations local *)
			END;
			IF NetBase.Equal(anyIP, route.gway, NetIP.AdrLen) & ~NetBase.Equal(anyIP, route.adr, NetIP.AdrLen) THEN
					(* gateway not set, but host adr set - attempt auto setting *)
				FOR j := 0 TO NetIP.AdrLen-1 DO	(* take host address AND subnet mask *)
					route.gway[j] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, route.adr[j]) * 
							SYSTEM.VAL(SET, route.subnet[j]))
				END;
					(* add .1 at end (common convention) *)
				route.gway[3] := SYSTEM.VAL(CHAR, SYSTEM.VAL(SET, route.gway[3]) + {0});
				(*log := TRUE*)
			END;
(*
			IF log THEN
				ToNum(SYSTEM.VAL(IPAdr, route.adr), s);
				Texts.WriteString(W, "IP: ");  Texts.WriteString(W, s);
				ToNum(SYSTEM.VAL(IPAdr, route.subnet), s);
				Texts.WriteString(W, ", Subnet: ");  Texts.WriteString(W, s);
				ToNum(SYSTEM.VAL(IPAdr, route.gway), s);
				Texts.WriteString(W, ", Gateway: ");  Texts.WriteString(W, s);
				Texts.WriteLn(W);  Texts.Append(Oberon.Log, W.buf)
			END;
*)
			NetIP.InstallRoute(route)
		ELSE
			Texts.WriteString(W, "Device [");  Texts.WriteString(W, device);  
			Texts.WriteString(W, "] not found"); Texts.WriteLn(W);
			Texts.Append(Oberon.Log, W.buf)
		END;
		INC(i); key[21] := CHR(i+ORD("0"));
		GetEntry0(key, "Device", device)
	END
END SetRoutes;

PROCEDURE SetDns;
VAR
	name, num, dns: ARRAY 64 OF CHAR;
	i, nodns: INTEGER;
	adr: NetIP.Adr;
	done: BOOLEAN;
BEGIN nodns := 0;
	dns := "DNS0";
	FOR i := 0 TO 3 DO
		dns[3] := CHR(i + ORD("0"));
		GetEntry("NetSystem.Hosts.", dns, name, num);
		IF (num # "") & (num[0] # "<") THEN ToHost0(num, adr, done);
			IF done THEN
				NetDNS.InstallDNS(name, adr); INC(nodns)
			END
		END
	END;
	IF nodns = 0 THEN
		ToHost0("129.132.98.12", adr, done); NetDNS.InstallDNS("dns1.ethz.ch", adr)
	END;
END SetDns;

PROCEDURE PollDevices(me: Oberon.Task);
BEGIN
	NetBase.Poll
END PollDevices;

(** Command NetSystem.Start ~  Start up NetSystem. *)

PROCEDURE Start*;
VAR name, num: ARRAY 64 OF CHAR;  pos: LONGINT;  ch: CHAR;
BEGIN
	IF ~started THEN
		SetDevices;
		IF NetBase.FindDevice(0) # NIL THEN
			SetRoutes; NetDNS.Init; GetEntry("NetSystem.Hosts.", "Domain", name, num);
			IF name # "" THEN
				IF hostName # "" THEN	(* check hostname *)
					pos := 0;  Strings.Search(".", hostName, pos);
					IF pos = -1 THEN	(* append domain name *)
						Strings.AppendCh(hostName, ".");
						Strings.Append(hostName, name)
					END
				END;
				NetDNS.InstallDom(name);
			ELSE NetDNS.InstallDom("ethz.ch")
			END;
			SetDns; started := NetIP.nofRoutes > 0;
			IF started THEN NetIP.SetDirectedCast(NetIP.routes[0]);
				NetBase.Start; NetIP.StartIP; NetPorts.Init; NetUDP.Start; NetTCP.Start;
				NEW(task);  task.safe := TRUE; task.time := Oberon.Time();  task.handle := PollDevices;
				Oberon.Install(task);
				IF (hostName = "") & ~(NetBase.Equal(anyIP, hostIP, NetIP.AdrLen)) THEN
					(*Texts.WriteString(W, "Host: ");  Texts.Append(Oberon.Log, W.buf);*)
					GetName(hostIP, hostName);
					pos := 0;
					LOOP
						ch := hostName[pos];
						IF ch = 0X THEN EXIT END;
						IF (ch >= "A") & (ch <= "Z") THEN ch := CHR(ORD(ch)+32) END;
						hostName[pos] := ch;
						INC(pos)
					END;
					IF pos = 0 THEN hostName := "x.oberon.ethz.ch" END;
					(*Texts.WriteString(W, hostName);  Texts.WriteLn(W)*)
				END;
				Texts.WriteString(W, "NetSystem started");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			ELSE
				Texts.WriteString(W, "Oberon.Text - NetSystem not configured");
				Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END
		ELSE
			Texts.WriteString(W, "Oberon.Text - No network driver configured");
			Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
		END
	END
END Start;

(** Command NetSystem.Stop ~  Shut down NetSystem. *)

PROCEDURE Stop*;
BEGIN
	IF task # NIL THEN Oberon.Remove(task); task := NIL END;
	NetTCP.Stop; NetUDP.Stop; NetIP.StopIP; NetBase.Stop;
	hostName := ""; started := FALSE;
	Texts.WriteString(W, "NetSystem stopped");
	Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
END Stop;

(** Command NetSystem.Show ~  Display status. *)

PROCEDURE Show*;
VAR s: ARRAY 32 OF CHAR;  r: NetIP.Route;  dev: NetBase.Device;  i: LONGINT;  p: Password;
BEGIN
	Texts.WriteString(W, "NetSystem.Show");  Texts.WriteLn(W);
	IF started THEN
		Texts.WriteString(W, "  Host: ");  ToNum(hostIP, s);  Texts.WriteString(W, s);  
		Texts.WriteString(W, " / ");  Texts.WriteString(W, hostName);
		Texts.WriteString(W, " / ");  Texts.WriteString(W, NetDNS.dom[0]);
		Texts.WriteLn(W);
		i := 0;
		LOOP
			dev := NetBase.FindDevice(i);
			IF dev = NIL THEN EXIT END;
			Texts.WriteString(W, "  Device");  Texts.WriteInt(W, i, 1);
			Texts.WriteString(W, ": ");
			CASE dev.state OF
				NetBase.closed: Texts.WriteString(W, "closed")
				|NetBase.open: Texts.WriteString(W, "open")
				|NetBase.pending: Texts.WriteString(W, "pending")
				ELSE Texts.WriteInt(W, dev.state, 1)
			END;
			Texts.Write(W, " ");
			AdrToStr(dev.hostAdr, s);  Texts.WriteString(W, s);  Texts.WriteString(W, " / ");
			AdrToStr(dev.castAdr, s);  Texts.WriteString(W, s);
			Texts.WriteLn(W);
			INC(i)
		END;
		FOR i := 0 TO NetIP.nofRoutes-1 DO
			r := NetIP.routes[i];
			Texts.WriteString(W, "  Route");  Texts.WriteInt(W, i, 1);  Texts.WriteString(W, ": ");
			ToNum(SYSTEM.VAL(IPAdr, r.adr), s);  Texts.WriteString(W, s);  Texts.WriteString(W, " / ");
			ToNum(SYSTEM.VAL(IPAdr, r.subnet), s);  Texts.WriteString(W, s);  Texts.WriteString(W, " / ");
			ToNum(SYSTEM.VAL(IPAdr, r.gway), s);  Texts.WriteString(W, s);  Texts.WriteString(W, " -> ");
			Texts.WriteInt(W, r.dev.num, 1);
			IF NetIP.arpopt IN r.options THEN Texts.WriteString(W, " arp")
			ELSE Texts.WriteString(W, " noarp")
			END;
			Texts.WriteLn(W)
		END;
		Texts.WriteString(W, "  DNS: ");
		FOR i := 0 TO NetDNS.nofdns-1 DO
			ToNum(SYSTEM.VAL(IPAdr, NetDNS.server[i].adr), s);  Texts.WriteString(W, s);
			IF i = NetDNS.dns THEN Texts.Write(W, "*") END;
			IF i # NetDNS.nofdns-1 THEN Texts.WriteString(W, " / ") END
		END;
		Texts.WriteLn(W);
		p := passwords;  WHILE p # NIL DO WriteURL(p.service, p.user, p.host); p := p.next END
	END;
	Texts.Append(Oberon.Log, W.buf)
END Show;

BEGIN
	task := NIL;
	NetBase.Copy(NetIP.IPany, anyIP, NetIP.AdrLen);
	NetBase.Copy(NetIP.IPall, allIP, NetIP.AdrLen);
	hostName := "";  hex := "0123456789ABCDEF";
	Texts.OpenWriter(W); started := FALSE; passwords := NIL;
	Start;  Kernel.InstallTermHandler(Stop)
END NetSystem.

Tasks
	NetBase.Poll
		for all devices, if Available then allocate item, Receive, multiplex upcall:
			NetIP.ArpReceive - send arp queued packets & reply to arp request
			NetIP.IPReceive - queue up to 30 packets in NetIP.ipq
	NetIP.IPDemux
		for all items in NetIP.ipq, check header, multiplex upcall:
			NetUDP.Input - find connection c & put up to 20 items to c.rq
			NetTCP.Demux - handle some items or put up to 30 items in c.rq
	NetTCP.TcpReceive
		one task per connection.  for all items in c.rq, call c.handle
	NetIP.Timer
		every 3 seconds, process arp cache
	NetTCP.Timer
		process events in NetTCP.sq (deleteev, sendev, retransev, persistev)

Install
	NetIP.StartTimer
		NetBase.InstallProtocol(ArpReceive, arpid)	(* 806H *)
		timer.handle := Timer; Oberon.Install(timer)
	NetIP.StartIP
		NetBase.InstallProtocol(IPReceive, ipid)	(* 800H *)
	NetUDP.Start
		NetIP.InstallDemux(Input, NetIP.UDP)	(* 17 *)
	NetTCP.Start
		NetIP.InstallDemux(Demux, NetIP.TCP)	(* 6 *)
		timer.handle := Timer; Oberon.Install(timer)
	NetTCP.ProcListen (from NetTCP.Demux)
		T.handle := TcpReceive; Oberon.Install(T)
	NetTCP.Connect
		T.handle := TcpReceive; Oberon.Install(T)

Modification
	NetSystem.TCPSetState fold into State
	bug: NetTCP.Poll does not check window... ?

Other uses of Oberon & Texts
	NetSystem
		Oberon.Par, Oberon.Log, Oberon.OpenScanner, Texts.*
	SLIP.InstallDevice
		Oberon.Par, Texts.Scanner
	PPPHDLC
		Timeout task
	PPPMain
		Oberon.OpenScanner
		Connect task
		
Dialer.Dial
Dialer.Hangup

NetSystem.Stop
System.Free NetSystem SLIP NetTCP NetDNS NetUDP NetPorts NetIP NetBase ~
NetSystem.Start 

Find.All ^  Find.Domain NetBase.Mod NetIP.Mod NetPorts.Mod NetUDP.Mod NetTCP.Mod NetDNS.Mod NetSystem.Mod ~

Compiler.Compile NetBase.Mod\s NetIP.Mod\s NetPorts.Mod\s NetUDP.Mod\s NetTCP.Mod\s NetDNS.Mod\s NetSystem.Mod 
	Net3Com509.Mod ~

Compiler.Compile *\x
