{$MODE OBJFPC}
(* Simple message logging mechanism output directly to stderr *)
unit log4;
interface
uses globals, sysutils;

const
	LogCritical  = 1;
	LogError = 2;
	LogWarn = 3;
	LogInfo = 4;
	LogDebug = 5;
	DefaultLogLevel = LogError;
	
type
	TLogLevel = 1 .. 5;
	TLogger = object
	private
		fd : TextFile;
		level : TLogLevel;
		procedure print(s : String);
		procedure print(const fmt : String; const Args : array of Const);
	public
		constructor Init;
		destructor Release;
		procedure log(s : String);
		procedure log(const fmt : String; const Args : array of Const);
		procedure error(s : String);
		procedure error(const fmt : String; const Args : array of Const);
		function toHex(num : Word) : String;
		procedure setLogLevel(lvl : TLogLevel);
	end;
	
var
	Logger : TLogger;
	
implementation

constructor TLogger.Init;
begin
	fd := stderr;
	level := DefaultLogLevel;
//	log('Init logger object');
end;

destructor TLogger.Release;
begin
	log('End logger object');
end;

procedure TLogger.setLogLevel(lvl : TLogLevel);
begin
	level := lvl;
end;

procedure TLogger.print(s : String);
begin
	writeln(fd, s);
end;

procedure TLogger.print(const fmt : String; const Args : array of Const);
var
	s : String;
begin
	s := Format(fmt, Args);
	writeln(fd, s);
end;

procedure TLogger.log(s : String);
begin
	if level >= LogInfo then print(s);
end;

procedure TLogger.log(const fmt : String; const Args : array of Const);
begin
	if level >= LogInfo then print(fmt, Args);
end;

(* Error reporting always goto stderr stream *)
procedure TLogger.error(s : String);
begin
	print(s);
end;

procedure TLogger.error(const fmt : String; const Args : array of Const);
begin
	print(fmt, Args);
end;

function toHexNibble(num : Word) : Char;
var
	w : Word;
begin
	w := num and $000F;
	if w < 10 then
		w := ord('0') + w
	else
		w := ord('A') + (w-10);
	toHexNibble := chr(w);
end;

function TLogger.toHex(num : Word) : String;
var
	tmp : array [1..4] of Char;
	w : Word;
begin
	w := num;
	tmp[4] := toHexNibble(w);
	w := w shr 4;
	tmp[3] := toHexNibble(w);
	w := w shr 4;
	tmp[2] := toHexNibble(w);
	w := w shr 4;
	tmp[1] := toHexNibble(w);
	toHex := tmp;
end;

initialization
begin
	Logger.init;
	Logger.log('Logger Initialization done');
end;

finalization
begin
	Logger.log('Finalize logging');
	Logger.Release;
end;

end.
