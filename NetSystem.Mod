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

IMPORT SYSTEM, Kernel, NetBase, Input, Texts, Oberon, TextFrames, Strings, Fonts;

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

TYPE
	Connection* = POINTER TO ConnectionDesc;	(** handle for TCP connections *)
	ConnectionDesc* = RECORD
		// port: NetPorts.Port;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER;
		Available: PROCEDURE (C: Connection; VAR res: INTEGER): LONGINT;
		Receive: PROCEDURE (C: Connection; VAR buf: ARRAY OF BYTE; beg, len: LONGINT; VAR res: INTEGER);
		Send: PROCEDURE (C: Connection; VAR buf: ARRAY OF BYTE; beg, len: LONGINT; VAR res: INTEGER);
	END;

	IPAdr* = LONGINT; (** IP address in network byte order *)

	Socket* = POINTER TO SocketDesc;	(** handle for UDP "connections" *)
	SocketDesc* = RECORD
		// C: NetUDP.Connection;
		res*: INTEGER;	(** result of last operation on a connection (error indication) *)
		state: INTEGER
	END;

VAR
	anyIP*: IPAdr;	(** "NIL" ip-number *)
	allIP*: IPAdr;	(** broadcast ip-number *)
	hostIP*: IPAdr;	(** main ip-number of local machine *)
	hostName*: ARRAY 64 OF CHAR;	(** main name of local machine *)


(** -- Adressing/Naming section. *)

(** Convert a dotted IP address string (e.g. "1.2.3.4") to an IPAdr value. *)

PROCEDURE ToHost* (num: ARRAY OF CHAR; VAR adr: IPAdr; VAR done: BOOLEAN);

END ToHost;

(** Convert an IPAdr value to a dotted IP address string *)

PROCEDURE ToNum*(adr: IPAdr; VAR num: ARRAY OF CHAR);

END ToNum;

(** Procedure delivers the ip-number of a named host. If a symbolic name is given, it will be resolved by use of domain name
	servers. *)

PROCEDURE GetIP* (name: ARRAY OF CHAR; VAR IP: IPAdr);

END GetIP;

(** GetName is the reverse of GetIP. Given an ip-number, it delivers the name of a host. *)

PROCEDURE GetName* (IP: IPAdr; VAR name: ARRAY OF CHAR);

END GetName;

(** -- TCP section. *)

(** Procedure opens a connection. locPort, remPort, remIP are contained in the quadrupel <locIP, remIP, locPort, remPort>
	which determines a connection uniquely. As locIP is always the current machine, it is omitted. If remPort is equal to
	anyport or remIP is equal to anyIP, a passive connection will be opened. After execution, C is a brand new connection.
	res indicates any error. *)

PROCEDURE OpenConnection* (VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort: INTEGER; VAR res: INTEGER);

END OpenConnection;

(** Like OpenConnection, but this procedure may return immediately and delay the actual opening of the connection.  
	In this case State() should be checked to wait for the connection status to change from waitCon. *)

PROCEDURE AsyncOpenConnection*(VAR C: Connection; locPort: INTEGER; remIP: IPAdr; remPort:INTEGER; VAR res: INTEGER);
BEGIN
	OpenConnection(C, locPort, remIP, remPort, res)	(* currently implemented synchronously *)
END AsyncOpenConnection;

(** Procedure closes the connection. Connection can not be used for send operations afterwards. *)

PROCEDURE CloseConnection* (C: Connection);

END CloseConnection;

(** Indicates whether there exists a remote machine which wants to connect to the local one. This Procedure is only useful
	on passive connections. For active connections (State(C) # listen), it always delivers FALSE. *)

PROCEDURE Requested* (C: Connection): BOOLEAN;

END Requested;

(** Procedure accepts a new waiting, active connection (newC) on a passive one (State(C) = listen). If no connection is 
	waiting, accept blocks until there is one or an error occurs. If C is not a passive connection, Accept does nothing
	but res is set to Done. *)

PROCEDURE Accept* (C: Connection; VAR newC: Connection; VAR res: INTEGER);

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

PROCEDURE ReadBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF BYTE);
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

END ReadString;

(** Blocking write a single byte to C. *)

PROCEDURE Write* (C: Connection; ch: CHAR);

END Write;

(** Blocking write len bytes of data (beginning at pos in buf) to C. *)

PROCEDURE WriteBytes* (C: Connection; pos, len: LONGINT; VAR buf: ARRAY OF BYTE);

END WriteBytes;

(** Blocking write two bytes in network byte ordering to C. *)

PROCEDURE WriteInt* (C: Connection; x: INTEGER);

END WriteInt;

(** Blocking write four bytes in network byte ordering to C. *)

PROCEDURE WriteLInt* (C: Connection; x: LONGINT);

END WriteLInt;

(** Blocking write a string without "0X" and terminated by "CRLF" to C. *)

PROCEDURE WriteString* (C: Connection; s: ARRAY OF CHAR);

END WriteString;

(** Procedure delivers the ip-number and port number of a connection's remote partner. *)

PROCEDURE GetPartner* (C: Connection; VAR remIP: IPAdr; VAR remPort: INTEGER);

END GetPartner;

(** -- UDP section. *)

(* Datagram oriented communication *)

(** Opens a socket which is dedicated to datagram services. locPort is registered to receive datagrams
	from any port and any host. *)

PROCEDURE OpenSocket* (VAR S: Socket; locPort: INTEGER; VAR res: INTEGER);

END OpenSocket;

(** Closes the socket. You can not receive datagrams anymore. *)

PROCEDURE CloseSocket* (S: Socket);

END CloseSocket;

(** Sends len bytes of data (beginning at pos in buf) to the host specified by remIP and remPort. *)

PROCEDURE SendDG* (S: Socket; remIP: IPAdr; remPort: INTEGER; pos, len: LONGINT; 
  VAR buf: ARRAY OF BYTE);

END SendDG;

(** Stores an entire datagram in buf beginning at pos. On success (S.res = done), remIP and remPort indicate the sender,
	len indicate the length of valid data. *)

PROCEDURE ReceiveDG*(S: Socket; VAR remIP: IPAdr; VAR remPort: INTEGER; pos: LONGINT; 
  VAR len: LONGINT; VAR buf: ARRAY OF BYTE)

END ReceiveDG;

(** Returns the size of the first available datagram on the socket. *)

PROCEDURE AvailableDG* (S: Socket): LONGINT;

END AvailableDG;

(* Conversions *)

(** Write 2 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutInt* (VAR buf: ARRAY OF BYTE; pos: INTEGER; x: INTEGER);
BEGIN NetBase.HostToNet(x);
	//SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutInt;

(** Write 4 bytes in network byte ordering to buf[pos]. *)

PROCEDURE PutLInt* (VAR buf: ARRAY OF BYTE; pos: INTEGER; x: LONGINT);
BEGIN NetBase.HostLToNet(x);
	//SYSTEM.PUT(SYSTEM.ADR(buf[pos]), x)
END PutLInt;

(** Read 2 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetInt* (VAR buf: ARRAY OF BYTE; pos: INTEGER; VAR x: INTEGER);
BEGIN // SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetToHost(x)
END GetInt;

(** Read 4 bytes in network byte ordering from buf[pos]. *)

PROCEDURE GetLInt* (VAR buf: ARRAY OF BYTE; pos: INTEGER; VAR x: LONGINT);
BEGIN // SYSTEM.GET(SYSTEM.ADR(buf[pos]), x);
	NetBase.NetLToHost(x)
END GetLInt;

(** Retrieve the password for user using service on host.  Parameters service, host and user must be specified. 
Parameter user is in/out.  If empty, it returns the first (user,password) pair found, otherwise it returns the
specified user's password. *)

PROCEDURE GetPassword*(service, host: ARRAY OF CHAR;  VAR user, password: ARRAY OF CHAR);

END GetPassword;

(** Remove password for user using service on host. *)

PROCEDURE DelPassword*(service, user, host: ARRAY OF CHAR);

END DelPassword;

(** Command NetSystem.SetUser { service ":" ["//"] user [ ":" password ] "@" host [ "/" ] } "~" <enter password>
		If password is not specified in-line, prompts for the password for the (service, host, user) triple. 
		The (service, host, user, password) 4-tuple is stored in memory for retrieval with GetPassword. 
		Multiple identical passwords may be set with one command. *)
		
PROCEDURE SetUser*;

END SetUser;

(** Command NetSystem.ClearUser ~  Clear all passwords from memory. *)

PROCEDURE ClearUser*;
BEGIN

END ClearUser;

(** Command NetSystem.Start ~  Start up NetSystem. *)

PROCEDURE Start*;

END Start;

(** Command NetSystem.Stop ~  Shut down NetSystem. *)

PROCEDURE Stop*;

END Stop;

(** Command NetSystem.Show ~  Display status. *)

PROCEDURE Show*;

END Show;

BEGIN
(*
	task := NIL;
	NetBase.Copy(NetIP.IPany, anyIP, NetIP.AdrLen);
	NetBase.Copy(NetIP.IPall, allIP, NetIP.AdrLen);
	hostName := "";  hex := "0123456789ABCDEF";
	Texts.OpenWriter(W); started := FALSE; passwords := NIL;
	Start;  Kernel.InstallTermHandler(Stop)
	*)
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
