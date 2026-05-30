{$MODE OBJFPC}
unit log4;
interface
uses sysutils;

type
	TLogger = object
	private
		fd, err : TextFile;
	public
		constructor Init;
		destructor Release;
		procedure log(s : String);
		procedure log(const fmt : String; const Args : array of Const);
		procedure error(s : String);
		procedure error(const fmt : String; const Args : array of Const);
	end;
	
var
	Logger : TLogger;
	
implementation

constructor TLogger.Init;
begin
	fd := stderr;
	err := stderr;
	writeln(fd, 'Init logger object');
end;

destructor TLogger.Release;
begin
	writeln(fd, 'End logger object');
end;

procedure TLogger.log(s : String);
begin
	writeln(fd, s);
end;

procedure TLogger.log(const fmt : String; const Args : array of Const);
var
	s : String;
begin
	s := Format(fmt, Args);
	writeln(fd, s);
end;

(* Error reporting always goto stderr stream *)
procedure TLogger.error(s : String);
begin
	writeln(err, s);
end;

procedure TLogger.error(const fmt : String; const Args : array of Const);
var
	s : String;
begin
	s := Format(fmt, Args);
	writeln(err, s);
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
