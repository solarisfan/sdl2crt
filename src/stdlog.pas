unit stdlog;
interface
	
procedure LogPrint(s : String);
procedure LogPrintln(s : String);
procedure LogPrintInt(i : Integer);
procedure setLogFile(name : String);

implementation
const
	LOGFILE = 'tmp.log';

var
	fname, msg : String;
	fd : Text;

procedure flush;
var
	i : Integer;
begin
	Assign(fd, fname);
	Append(fd);
	if (msg <> '') then
	begin
		for i := 1 to Length(msg) do
		begin
			if msg[i] = #10 then writeln(fd)
			else if msg[i] = #9 then write(fd, '\t')
			else write(fd, msg[i]);
		end;
	end;
	Close(fd);
	
end;

procedure LogPrint(s : String);
begin
	msg := s;
	flush;
end;

procedure LogPrintInt(i : Integer);
var
	s : String;
begin
	Str(i, s);
	msg := s;
	flush;
end;

procedure LogPrintln(s : String);
begin
	msg := s + #10;
	flush;
end;

procedure Fileinit;
begin
	Assign(fd, fname);
	Rewrite(fd);
	Close(fd);
end;

procedure setLogFile(name : String);
begin
	fname := name;
	Fileinit;
end;

procedure defaultFile;
var
	s : String;
	i : Integer;
begin
	s := ParamStr(0);
	i := Pos('.', s);
	if i > 1 then fname := Copy(s,1, i)
	else fname := s + '.';
	fname := fname + 'err';
end;

begin
	defaultFile;
	Fileinit;
end.
