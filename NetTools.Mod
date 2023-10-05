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

MODULE NetTools;	(** portable *) (* ejz,   *)
	IMPORT Input, Files, Objects, Strings, Texts, Oberon, NetSystem, Gadgets, Documents, HyperDocs, Attributes, Streams,
		(*Threads,*) SYSTEM;

(** NetTools is a utility module that contains procedures commonly used with TCP services. *)

	CONST
		MaxLine* = 1024; (* Mac = 1000 *)
		MaxTry = 1000;
		BufLen* = MaxLine;
		ServerStrLen* = HyperDocs.ServerStrLen;
		PathStrLen* = HyperDocs.PathStrLen;
		Esc = 01BX; BreakChar = Esc;
		Done* = 0; Failed* = MAX(INTEGER); (** res codes *)

	TYPE
	(** Message send to the http link scheme object, when a service (gopher, ftp) is used via a proxy host.
			key is associated to the requested url. host and port specify the proxy host to be used.
			The resulting document is returned in D. *)
		ProxyMsg* = RECORD (HyperDocs.LinkSchemeMsg)
			host*: ARRAY ServerStrLen OF CHAR;
			D*: Documents.Document;
			port*: INTEGER
		END;
	(** Session with an TCP server, e.g.: FTP, POP, ... *)
		Session* = POINTER TO SessionDesc;
		SessionDesc* = RECORD
			C*: NetSystem.Connection; (** the connection *)
			S*: Streams.Stream; (** a stream for the connection *)
			reply*: ARRAY MaxLine OF CHAR; (** reply-line of the last command sent *)
			status*: INTEGER; (** result code of the TCP-protocoll used *)
			res*: INTEGER (** result code: 0: Done; # 0: Failed *)
		END;
	(** a TCP Stream implementation *)
		TCPStream* = POINTER TO TCPStreamDesc;
		TCPStreamDesc* = RECORD (Streams.StreamDesc)
			C*: NetSystem.Connection;
			avail: LONGINT
		END;

	VAR
		W: Texts.Writer;
		curLen*: LONGINT; (** maximum length of the current blocking transfer *)
		prevPos, curPos*: LONGINT; (** state of the current blocking transfer *)
		TimeOut*: LONGINT; (** typical time-out for blocking transfer *)
		progM: Objects.Object;
		buffer: ARRAY BufLen OF CHAR;
		proxyDomain: ARRAY 64 OF CHAR;

(** TRUE if the BreakChar-key (ESC) has been pressed. *)
	PROCEDURE UserBreak*(): BOOLEAN;
		VAR ch: CHAR;
	BEGIN
		IF Input.Available() > 0 THEN
			Input.Read(ch);
			IF ch = BreakChar THEN
				Texts.WriteString(W, "interrupted");
				Texts.WriteLn(W);
				Texts.Append(Oberon.Log, W.buf);
				RETURN TRUE
			(*ELSE
				Input.Write(ch)*)
			END
		END;
		RETURN FALSE
	END UserBreak;

(* Default notifier for the SendText, ReadText & ReadData procedures. Updates the public integer object Net.Progress
		used by HyperDocs.Panel. *)
	PROCEDURE ProgMNotify*();
	BEGIN
		prevPos := curPos;
		IF (progM # NIL) & (curLen > 0) THEN
			Attributes.SetInt(progM, "Value", (100*curPos) DIV curLen);
			Gadgets.Update(progM)
		ELSIF (progM # NIL) & (curLen <= 0) THEN
			Attributes.SetInt(progM, "Value", ((100*curPos) DIV (16*1024)) MOD 100);
			Gadgets.Update(progM)
		END
	END ProgMNotify;

(** Open a new connection C to host on port. Switch logging of error-messages with log on or off.
		If the connection could be established TRUE is returned. *) 
	PROCEDURE Connect*(VAR C: NetSystem.Connection; port: INTEGER; host: ARRAY OF CHAR; log: BOOLEAN): BOOLEAN;
		VAR
			adr: NetSystem.IPAdr;
			res: INTEGER;
	BEGIN
		IF log THEN
			Texts.WriteString(W, host); Texts.Write(W, ":"); Texts.WriteInt(W, port, 0); Texts.Append(Oberon.Log, W.buf)
		END;
		NetSystem.GetIP(host, adr);
		IF adr = NetSystem.anyIP THEN
			C := NIL;
			IF log THEN
				Texts.WriteString(W, " invalid address"); Texts.WriteLn(W); Texts.Append(Oberon.Log, W.buf)
			END;
			RETURN FALSE
		END;
		IF port > 0 THEN
			NetSystem.OpenConnection(C, NetSystem.anyport, adr, port, res)
		ELSE
			NetSystem.AsyncOpenConnection(C, NetSystem.anyport, adr, -port, res)
		END;
		IF res # NetSystem.done THEN
			C := NIL;
			IF log THEN
				Texts.WriteString(W, " connecting failed"); Texts.WriteLn(W)
			END
		END;
		IF log THEN
			Texts.Append(Oberon.Log, W.buf)
		END;
		prevPos := MIN(INTEGER); curPos := 0; curLen := 0;
		RETURN res = NetSystem.done
	END Connect;

(** Start opening a new connection C to host on port. Switch logging of error-messages with log on or off.
		If the connection could be established TRUE is returned. *)
	PROCEDURE AsyncConnect*(VAR C: NetSystem.Connection; port: INTEGER; host: ARRAY OF CHAR; log: BOOLEAN): BOOLEAN;
	BEGIN
		RETURN Connect(C, -port, host, log)
	END AsyncConnect;

(** Check if connection C is still open for incoming (mode = NetSystem.in) or outgoing (mode = NetSystem.out) data. *)
	PROCEDURE Connected*(C: NetSystem.Connection; mode: INTEGER): BOOLEAN;
		VAR state: INTEGER;
	BEGIN
		state := NetSystem.State(C);
		RETURN state IN {mode, NetSystem.inout}
	END Connected;

(** Close the connection C. *)
	PROCEDURE Disconnect*(VAR C: NetSystem.Connection);
	BEGIN
		IF C # NIL THEN
			NetSystem.CloseConnection(C)
		END;
		C := NIL;
		prevPos := MIN(INTEGER); curPos := 0; ProgMNotify()
	END Disconnect;

(** Send the string str on connection C without any termination characters. *)
	PROCEDURE SendString*(C: NetSystem.Connection; str: ARRAY OF CHAR);
		VAR i: LONGINT;
	BEGIN
		i := 0;
		WHILE str[i] # 0X DO
			INC(i)
		END;
		NetSystem.WriteBytes(C, 0, i, str)
	END SendString;

	PROCEDURE *ReadTCPBytes(S: Streams.Stream; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
		VAR len, pos, time: LONGINT;
	BEGIN
		WITH S: TCPStream DO
			IF n > 0 THEN
				pos := 0; time := Input.Time() + TimeOut;
				REPEAT
					IF S.avail < n THEN
						len := S.Available(S)
					ELSE
						len := S.avail
					END;
					IF len > 0 THEN
						IF len > n THEN
							len := n
						END;
						NetSystem.ReadBytes(S.C, pos, len, x);
						INC(curPos, len);
						IF (curPos-prevPos) >= 32 THEN
							ProgMNotify()
						END;
						INC(pos, len); DEC(n, len); DEC(S.avail, len)
					END
				UNTIL (n <= 0) OR S.eos OR UserBreak() OR (Input.Time() - time > 0);
				IF n > 0 THEN
					S.eos := TRUE; S.res := n
				END
			END
		END
	END ReadTCPBytes;

	PROCEDURE *WriteTCPBytes(S: Streams.Stream; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
	BEGIN
		WITH S: TCPStream DO
			NetSystem.WriteBytes(S.C, 0, n, x); S.res := 0;
			INC(curPos, n);
			IF (curPos-prevPos) >= 32 THEN
				ProgMNotify()
			END
		END
	END WriteTCPBytes;

	PROCEDURE TCPAvailable*(S: Streams.Stream): LONGINT;
		VAR state: INTEGER;
	BEGIN
		WITH S: TCPStream DO
			S.avail := NetSystem.Available(S.C);
			IF S.avail > 0 THEN
				RETURN S.avail
			ELSE
				state := S.State(S);
				IF state # Streams.inout THEN
					S.eos := TRUE
				END;
				RETURN 0
			END
		END
	END TCPAvailable;

	PROCEDURE *TCPState(S: Streams.Stream): INTEGER;
		VAR state: INTEGER;
	BEGIN
		WITH S: TCPStream DO
			state := NetSystem.State(S.C);
			IF state = NetSystem.inout THEN
				RETURN Streams.inout
			ELSE
				S.eos := TRUE;
				RETURN Streams.closed
			END
		END
	END TCPState;

	PROCEDURE *TCPFlush(S: Streams.Stream);
		VAR len: LONGINT;
	BEGIN
		WITH S: TCPStream DO
			len := S.Available(S)
		END
	END TCPFlush;

	PROCEDURE *TCPClose(S: Streams.Stream);
	BEGIN
		WITH S: TCPStream DO
			S.eos := TRUE; Disconnect(S.C); S.C := NIL
		END
	END TCPClose;

(** Opens a stream on connection C. *)
	PROCEDURE OpenStream*(C: NetSystem.Connection): Streams.Stream;
		VAR S: TCPStream;
	BEGIN
		NEW(S); S.mode := Streams.binary; S.eos := FALSE;
		S.C := C; S.res := 0; S.buffer := TRUE;
		S.ReadBytes := ReadTCPBytes;
		S.WriteBytes := WriteTCPBytes;
		S.Available := TCPAvailable;
		S.State := TCPState;
		S.Flush := TCPFlush;
		S.Close := TCPClose;
		RETURN S
	END OpenStream;

(** Write all incoming data on connection C to R, until the connection is closed. notify is called after each
		packet received. *)
	PROCEDURE ReadData*(C: NetSystem.Connection; VAR R: Files.Rider; maxLen: LONGINT);
		VAR len, rlen, try: LONGINT;
	BEGIN
		curPos := 0; ProgMNotify(); try := Input.Time() + TimeOut;
		len := NetSystem.Available(C);
		WHILE (curPos < maxLen) & ((len > 0) OR Connected(C, NetSystem.in)) DO
			IF UserBreak() THEN
				RETURN
			END;
			IF len > BufLen THEN
				rlen := BufLen
			ELSE
				rlen := len
			END;
			NetSystem.ReadBytes(C, 0, rlen, buffer);
			Files.WriteBytes(R, buffer, rlen);
			INC(curPos, rlen);
			ProgMNotify();
			DEC(len, rlen);
			IF len <= 0 THEN
				len := NetSystem.Available(C);
				IF len <= 0 THEN
					IF try - Input.Time() < 0 THEN RETURN END
				ELSE
					try := Input.Time() + TimeOut
				END
			END
		END;
		curPos := 0; ProgMNotify()
	END ReadData;

	PROCEDURE WriteData*(C: NetSystem.Connection; VAR R: Files.Rider);
	BEGIN
		curPos := 0; ProgMNotify();
		Files.ReadBytes(R, buffer, BufLen);
		WHILE ~R.eof DO
			NetSystem.WriteBytes(C, 0, BufLen, buffer);
			INC(curPos, BufLen); ProgMNotify();
			Files.ReadBytes(R, buffer, BufLen)
		END;
		IF R.res > 0 THEN
			NetSystem.WriteBytes(C, 0, BufLen-R.res, buffer)
		END;
		curPos := 0; ProgMNotify()
	END WriteData;

(** Query a string setting in the NetSystem section in Registry. *)
	PROCEDURE QueryString*(key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
		VAR S: Texts.Scanner; lKey: ARRAY 32 OF CHAR;
	BEGIN
		lKey := "NetSystem."; Strings.Append(lKey, key);
		Oberon.OpenScanner(S, lKey);
		IF S.class IN {Texts.Name, Texts.String} THEN
			COPY(S.s, s)
		ELSE
			COPY("", s)
		END;
		RETURN s # ""
	END QueryString;

(** Get host and port of the Registry entry key in section NetSystem. *)
	PROCEDURE GetHostPort*(key: ARRAY OF CHAR; VAR host: ARRAY OF CHAR; VAR port: INTEGER; defPort: INTEGER);
		VAR
			val: LONGINT;
			i: INTEGER;
	BEGIN
		IF QueryString(key, host) & (host[0] # "<") THEN
			i := 0;
			WHILE (host[i] # 0X) & (host[i] # ":") DO
				INC(i)
			END;
			IF host[i] = ":" THEN
				host[i] := 0X; INC(i);
				Strings.StrToIntPos(host, val, i);
				port := SHORT(val)
			ELSE
				port := 0
			END;
			IF port <= 0 THEN
				port := defPort
			END
		ELSE
			COPY("", host); port := 0
		END
	END GetHostPort;

(** Query a boolean setting in the NetSystem section in Registry. *)
	PROCEDURE QueryBool*(key: ARRAY OF CHAR): BOOLEAN;
		VAR
			str: ARRAY 16 OF CHAR;
			b: BOOLEAN;
	BEGIN
		IF QueryString(key, str) THEN
			Strings.StrToBool(str, b);
			RETURN b
		ELSE
			RETURN FALSE
		END
	END QueryBool;

(** Get host and port of an url link. *)
	PROCEDURE SplitHostPort*(VAR url, host: ARRAY OF CHAR; VAR port: INTEGER);
		VAR
			i, j: INTEGER;
			val: LONGINT;
	BEGIN
		i := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") DO
			INC(i)
		END;
		WHILE url[i] = "/" DO
			INC(i)
		END;
		j := i;
		WHILE (url[j] # 0X) & (url[j] # "@") & (url[j] # "/") DO
			INC(j)
		END;
		IF url[j] = "@" THEN
			i := j+1
		END;
		j := 0;
		WHILE (url[i] # 0X) & (url[i] # "/") & (url[i] # ":") DO
			host[j] := url[i]; INC(i); INC(j)
		END;
		host[j] := 0X;
		IF url[i] = ":" THEN
			INC(i); Strings.StrToIntPos(url, val, i);
			port := SHORT(val)
		ELSE
			port := 0
		END
	END SplitHostPort;

(** Checks if a proxy should be used for host. *)
	PROCEDURE UseProxy*(VAR host: ARRAY OF CHAR): BOOLEAN;
		VAR i, j: LONGINT;
	BEGIN
		IF proxyDomain # "" THEN
			i := 0; j := -1;
			WHILE host[i] # 0X DO
				IF host[i] = "." THEN
					j := i
				END;
				INC(i)
			END;
			IF j < 0 THEN
				RETURN FALSE
			END;
			j := 0;
			WHILE proxyDomain[j] # 0X DO
				INC(j)
			END;
			WHILE (i > 0) & (j >= 0) & (CAP(host[i]) = CAP(proxyDomain[j])) DO
				DEC(i); DEC(j)
			END;
			RETURN j >= 0
		ELSE
			RETURN TRUE
		END
	END UseProxy;

	PROCEDURE InitProxy();
	BEGIN
		IF ~QueryString("ProxyDomain", proxyDomain) THEN
			proxyDomain := ""
		END
	END InitProxy;

BEGIN
	Texts.OpenWriter(W);
	progM := Gadgets.FindPublicObj("NetDocs.Progress");
	InitProxy(); TimeOut := 60*Input.TimeUnit
END NetTools.
