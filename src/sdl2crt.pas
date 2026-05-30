unit sdl2crt;
(* 
	This unit requires TextMode to be called before actual 
	drawing take places, so I would know how to create the window.
	
	Replace module for CRT module using SDL2 in a single window. 
	Module is not designed to sprawn multiple CRT windows.
	Cannot be compiled in Turbo Pascal, since I do not think
	SDL is supported under DOS. The window is limited to a 
	maximum of 80 x 50 characters.
	
	This module assume compatability with Turbo Pascal and not Delphi.
	I am targeting text console application only.
 *)
interface
uses 
{$ifdef unix }
cthreads,
{$endif}
ctypes, math, sdl2, txture, sysutils, log4;

const
	(* IRGB color constant equivalent *)
	Black = 0;
	Blue = 1;
	Green = 2;
	Cyan = 3;
	Red = 4;
	Magenta = 5;
	Brown = 6;
	LightGray = 7;
	DarkGray = 8;
	LightBlue = 9;
	LightGreen = 10;
	LightCyan = 11;
	LightRed = 12;
	LightMagenta = 13;
	Yellow = 14;
	White = 15;
	Blink = 128;
	
	(* TextMode constants *)
	BW40 = 0; (* 40 X 25 *)
	CO40 = 1; (* 40 X 25 *)
	BW80 = 2; (* 80 X 25 *)
	CO80 = 3; (* 80 X 25 *)
	Mono = 7; (* 80 X 25 *)
	Font8x8 = 256; (* 80 X 50 *)
	ReservedTextMode = $F000; (* Reserved for internal use as default mode *)
	
var
	LastMode : Word;
	WindMax, WindMin : Word;
	TextAttr : Byte;
	
(* Extended variable *)
	windowTitle : AnsiString;
	
function KeyPressed : Boolean;
function ReadKey : Char;

procedure TextMode(Mode :Word);
procedure TextColor(Color: Byte);
procedure TextBackground(Color: Byte);

function WhereX : Byte;
function WhereY : Byte;
procedure GotoXY(x, y : Byte);

procedure CursorOn;
procedure CursorOff;

procedure ClrScr;
procedure ClrEol;
procedure Window(x1, y1, x2, y2 : Byte);

procedure Delay(MS : Word);

procedure NormVideo;
procedure HighVideo;
procedure LowVideo;

procedure DelLine;
procedure InsLine;

(* Extended procedures *)
procedure TextModeFont(Mode :Word; font : AnsiString; ptSize : Integer);

implementation
const
	(* For console application 5 frames per second is more that sufficient *)
	FPStime = int(1000 / 10); (* at least this amount of millisecond between present *)
	BlinkTime = int(1000 / 5); (* Cursor refresh rate should be lower than the window refresh rate *)
	BLEED = 1; (* 1 pixel margin *)
	TextBlinkTime = QWord(700);
	
type
	TfnCode = (fnNil, fnWrite, fnAddChar, fnShow, 
				fnWhereX, fnWhereY, fnGotoXY, fnTextColor, 
				fnTextBackGround,
				fnClrScr, fnClrEol,
				fnWindow, fnCursorOff, fnCursorOn,
				fnHighVideo, fnLowVideo, fnNormVideo,
				fnDelLine, fnInsLine);
				
	TKeyBuf = record
		key : TRTLCriticalSection;
		keyPressed : Boolean;
		len : Integer;
		buf : Array[1..10] of Char;
	end;
	
	TKeyArray = record
		len, consumed : Integer;
		buf : Array[1..10] of Char;
	end;
	
	(* Data passing between threads *)
	TCursor = record
		x, y : Byte;
		ready : Boolean;
	end;
		
	TViewPort = record
		x1, y1, x2, y2 : Byte; (* Sub window size in columns and rows *)
		row, col : Integer; (* # of Row and column of the current subwindow *)
		cursorShown : Boolean;
		cursorOn : Boolean;
		ready : Boolean;
	end;
var
	pen : TSDL_Rect; (* Physical pixel location, and font height and width in pixel *)
	term : TSDL_Rect; (* Logical row, column location and physical view size in pixel *)
	consoleSize : TSDL_Rect; (* The main window size in columns and rows *)
	winThread : TThreadID;
	eventID : Uint32;
	keyBuf : TKeyBuf; (* Capture key pressed *)
	keyAry : TKeyArray; (* Array of key cache for ReadKey function *)
	sdlReady : Boolean;
	cursor : TCursor;
	vw : TViewPort;
	lastPresent, lastBlink : QWord; (* Last time present was called *)
	fontFileName : AnsiString = '';
	fontSize : Integer = 0;
	fgColor, bgColor : Byte;
	savedTextAttr : Byte;
	monoChrome : Boolean;
	
	(* Remap sdl scancode to keyboard scancode *)
	scanmap : array [4..29] of Byte =
		(30, 48, 46, 32, 18, 33, 34, 35, 23, 36,
		 37, 38, 50, 49, 24, 25, 16, 19, 31, 20,
		 22, 47, 17, 45, 21, 44);
	
	savedOpenFunc : CodePointer; (* Saved TextRec CodePointer OpenFunc *)
	
	(* Forward declaration *)
	procedure assignOutput(sw :boolean); forward;
	procedure showCursor(show : Boolean); forward;
	
procedure postEvent(fn : TfnCode);
var
	evt : TSDL_Event;
begin
	if not sdlReady then Exit;

	evt.type_ := eventID;
	evt.user.code := ord(fn);
	if SDL_PushEvent(@evt) <> 1 then 
		Logger.error('SDL push event failed');	
end;

procedure postEvent(fn : TfnCode; data1, data2 : Pointer);
var
	evt : TSDL_Event;
begin
	if not sdlReady then Exit;

	evt.type_ := eventID;
	evt.user.code := ord(fn);
	evt.user.data1 := data1;
	evt.user.data2 := data2;
	if SDL_PushEvent(@evt) <> 1 then 
		Logger.error('SDL push event failed');	
end;

procedure NormVideo;
begin
	postEvent(fnNormVideo);
end;

procedure HighVideo;
begin
	postEvent(fnHighVideo);
end;

procedure LowVideo;
begin
	postEvent(fnLowVideo);
end;

procedure ClrScr;
begin
	postEvent(fnClrScr);
end;

procedure ClrEol;
begin
	postEvent(fnClrEol);
end;

function WhereX : Byte;
begin
	WhereX := 0;
	if not sdlReady then Exit(0);
	postEvent(fnWhereX);
	while not cursor.ready do ;
	cursor.ready := false;
	WhereX := cursor.x;
end;

function WhereY : Byte;
begin
	WhereY := 0;
	if not sdlReady then Exit(0);
	postEvent(fnWhereY);
	while not cursor.ready do ;
	cursor.ready := false;
	WhereY := cursor.y;
end;

procedure GotoXY(x, y : Byte);
var
	i, j : PtrUint;
begin
	if not sdlReady then Exit;
	if x < 1 then Exit;
	if y < 1 then Exit;
	if x > vw.col then exit;
	if y > vw.row then exit;
	//Logger.log('GotoXY %d %d', [x,y]);
	i := PtrUint(x);
	j := PtrUint(y);
	postEvent(fnGotoXY, PInteger(i), PInteger(j));
end;

procedure DelLine;
begin
	postEvent(fnDelLine);
end;

procedure InsLine;
begin
	postEvent(fnInsLine);
end;

procedure TextColor(Color : Byte);
var
	i : PtrUint;
	bg : Byte;
begin
	if winThread = 0 then TextMode(CO80);
	if monoChrome then 
		if Color <> Black then Color := LightGray;
	if not sdlReady then begin
		(* Window is not prop up yet, can direct set color *)
		pixmap.setForeColor(Color);
	end;
	bg := TextAttr and $70;
	TextAttr := bg or Color;
	savedTextAttr := TextAttr;
	i := PtrUint(Color);
	postEvent(fnTextColor, PInteger(i), PInteger(0));
end;

procedure TextBackground(Color : Byte);
var
	i : PtrUint;
	fg, bg : Byte;
begin
	if winThread = 0 then TextMode(CO80);
	if monoChrome then 
		if Color <> Black then Color := LightGray;
	if not sdlReady then begin
		(* Window is not prop up yet, can direct set color *)
		pixmap.setBackColor(Color);
	end;
	bg := Color and $07; (* Turbo pascal background color is 0-7 only *)
	fg := TextAttr and $87;
	TextAttr := (bg shl 4) or fg;
	savedTextAttr := TextAttr;
	i := PtrUint(bg);
	postEvent(fnTextBackGround, PInteger(i), PInteger(0));
end;

function KeyPressed : Boolean;
begin
	(* Do not need critical section here. Just a read. *)
	KeyPressed := keyBuf.keyPressed;
end;
	
procedure renderChar(c : Char; x, y : Integer);
var
	texture : PSDL_Texture;
begin
	pixmap.getTexture(@c, texture);
	if texture <> nil then pixmap.copyTexture(texture, x, y);
end;

(* Advance to next line *)
procedure newline;
var
	y : Integer;
begin
	showCursor(false);
	pen.x := 1;
	y := pen.y + pen.h;
	term.x := 1;
	if (term.h - y) < pen.h then begin
		(* After scrolling y position remain as is *)
		pixmap.scrollUp(1, pen.h);
	end else begin
		(* Normal advance *)
		pen.y := y;
		inc(term.y);
	end;
end;

(* Advance one character *)
procedure moveright;
begin
	showCursor(false);
	pen.x := pen.x + pen.w;
	inc(term.x);
	if (term.w - pen.x) < pen.w then newline;
end;

procedure moveTo(evt : TSDL_Event);
var
	x, y : PtrUint;
begin
	showCursor(false);
	x := PtrUint(evt.user.data1);
	y := PtrUint(evt.user.data2);
	//writeln(stderr, 'Move to ', x, ' ', y);
	term.x := x;
	term.y := y;
	pen.x := (x - 1) * pen.w + 1;
	pen.y := (y - 1) * pen.h + 1;
	pixmap.saveCursor(pen.x, pen.y);
end;

procedure drawChar(c : Char; render : Boolean);
begin
	if (c = #10) or (c = #13) then begin
		newLine;
		Exit;
	end;
//	writeln(stderr, c, ' pen.x: ', pen.x, ' pen.y ', pen.y, ' term.w ', term.w);
	renderChar(c, pen.x, pen.y);
	moveright;
end;

procedure clearScreen;
begin
	pixmap.renderClear;
	pen.x := BLEED;
	pen.y := BLEED;
	term.x := 1; (* first col *)
	term.y := 1; (* first row *)
end;

procedure defineWindow(x1, y1, x2, y2 : Byte);
var
	r : TSDL_Rect;
begin
	showCursor(false);
	(* actual x1 and y1 pixel position *)
	r.x := (x1 - 1) * pen.w;
	r.y := (y1 - 1) * pen.h;
	(* Row and column in characters *)
	vw.col := x2 - x1 + 1;
	vw.row := y2 - y1 + 1;
	vw.x1 := x1;
	vw.y1 := y1;
	vw.x2 := x2;
	vw.y2 := y2;
	term.x := 1;
	term.y := 1;
	(* Width and height in pixel *)
	term.w := vw.col * pen.w + 2;
	term.h := vw.row * pen.h + 2;
	r.w := term.w;
	r.h := term.h;
	pen.x := BLEED;
	pen.y := BLEED;
	pixmap.defineView(r);
	WindMax := ((y2 - 1) shl 8) or (x2 - 1);
	WindMin := ((y1 - 1) shl 8) or (x1 - 1);
	vw.ready := true;
end;

procedure clearEol;
var
	r : TSDL_Rect;
begin
	r.x := pen.x;
	r.y := pen.y;
	r.w := term.w - pen.y;
	r.h := pen.h;
	pixmap.fillRect(r);
end;

procedure deleteLine;
begin
	pixmap.deleteLine(pen.y, pen.h);
	pen.x := 0;
end;

procedure insertLine;
begin
	if (term.h - pen.y - pen.h) < pen.h then begin
		showCursor(false);
		pixmap.scrollUp(1, pen.h);
	end else begin
		pixmap.insertLine(pen.y, pen.h);
	end;
end;

procedure decodeUserEvent(evt : TSDL_Event);
var
	i : PtrUint;
	opcode : TfnCode;
begin
	opcode := TfnCode(evt.user.code);
	case opcode of
		fnWrite: begin
			i := PtrUint(evt.user.data1);
			drawChar(char(i), true);
		end;
		fnAddChar: begin
			i := PtrUint(evt.user.data1);
			drawChar(char(i), false);
		end;
		fnShow: begin
			pixmap.present(false);
		end;
		fnTextColor: begin
			i := PtrUint(evt.user.data1);
			fgColor := i;
			pixmap.setForeColor(i);
		end;
		fnTextBackground: begin
			i := PtrUint(evt.user.data1);
			bgColor := i;
			pixmap.setBackColor(i);
		end;
		fnWhereX: begin
			cursor.ready := true;
			cursor.x := term.x;
		end;
		fnWhereY: begin
			cursor.ready := true;
			cursor.y := term.y;
		end;
		fnGotoXY: begin
			moveTo(evt);
		end;
		fnClrScr: clearScreen;
		fnClrEol: clearEol;
		fnWindow: begin
			i := PtrUint(evt.user.data1);
			defineWindow((i shr 24) and $FF, (i shr 16) and $FF, (i shr 8) and $FF, i and $FF);
		end;
		fnHighVideo: pixmap.setIntensity(HighIntensity);
		fnLowVideo: pixmap.setIntensity(LowIntensity);
		fnNormVideo: pixmap.setIntensity(NormalIntensity);
		fnDelLine: deleteLine;
		fnInsLine: insertLine;
	end; (* end case *)
end;

procedure handleInput(evt : TSDL_Event);
var
	i : Integer;
begin
	if keyBuf.keyPressed then exit;
	EnterCriticalSection(keyBuf.key);
	if keyBuf.len > 0 then begin
		LeaveCriticalSection(keyBuf.key);
		exit;
	end;
	keyBuf.len := 0;
	for i := 0 to Length(evt.text.text) do
		if (evt.text.text[i] > chr(0)) then begin
			keyBuf.buf[i+1] := evt.text.text[i];
			inc(keyBuf.len);
			if keyBuf.len >= length(keyBuf.buf) then Break;
		end else Break;
	keyBuf.keyPressed := TRUE;
	LeaveCriticalSection(keyBuf.key);
end;

procedure handleKeyDown(evt : TSDL_Event; modi : TSDL_Keymod);
begin
	if keyBuf.keyPressed then exit;
	EnterCriticalSection(keyBuf.key);
	keyBuf.buf[1] := #0;
	keyBuf.buf[2] := #0;
	if (modi and KMOD_CTRL) > 0 then
	begin
		if (evt.key.keysym.sym > 96) and (evt.key.keysym.sym < 123) then 
			keyBuf.buf[1] := chr(evt.key.keysym.sym - 96);
	end else if (modi and KMOD_ALT) > 0 then begin
		if (evt.key.keysym.sym >= 65) and (evt.key.keysym.sym <= 122) then 
			keyBuf.buf[2] := chr(scanmap[evt.key.keysym.scancode]);
	end else begin
		case evt.key.keysym.sym of
			SDLK_BACKSPACE: keyBuf.buf[1] := #8;
			SDLK_ESCAPE: keyBuf.buf[1] := #27;
			SDLK_RETURN: keyBuf.buf[1] := #13;
			SDLK_INSERT : keyBuf.buf[2] := #82;
			SDLK_DELETE: keyBuf.buf[2] := #83;
			SDLK_UP: keyBuf.buf[2] := #72;
			SDLK_DOWN : keyBuf.buf[2] := #80;
			SDLK_LEFT: keyBuf.buf[2] := #75;
			SDLK_RIGHT: keyBuf.buf[2] := #77;
			SDLK_PAGEUP: keyBuf.buf[2] := #73;
			SDLK_PAGEDOWN: keyBuf.buf[2] := #81;
			else
				if (evt.key.keysym.sym >= SDLK_F1) and
					(evt.key.keysym.sym <= SDLK_F10) then
					keyBuf.buf[2] := chr(evt.key.keysym.sym - SDLK_F1 + 1)
		end; (* end case *)
	end; (* end else begin *)
	if keyBuf.buf[1] > #0 then begin
		keyBuf.len := 1;
		keyBuf.keyPressed := true;
	end;
	if (keyBuf.buf[1] = #0) and (keyBuf.buf[2] > #0) then begin
		keyBuf.len := 2;
		keyBuf.keyPressed := true;
	end;
	LeaveCriticalSection(keyBuf.key);
end;

procedure showCursor(show : Boolean);
begin
	if show then begin
		if vw.cursorOn then begin
			pixmap.drawCursor(pen.x, pen.y);
		end;
	end else begin
		pixmap.hideCursor;
	end;
end;


procedure doblink;
begin
	vw.cursorShown := not vw.cursorShown;
	showCursor(vw.cursorShown);
	lastBlink := SDL_GetTicks64 - 1;
end;

procedure CursorOff;
begin
	vw.cursorOn := false;
end;

procedure CursorOn;
begin
	vw.cursorOn := true;
end;

function getNextEvent : Boolean;
var
	evt : TSDL_Event;
	modi : TSDL_Keymod;
begin
	GetNextEvent := TRUE;
	if SDL_PollEvent(@evt) = 0 then exit(TRUE);
	modi := SDL_GetModState;
	case evt.type_ of
	SDL_QUITEV:
	begin
		GetNextEvent := FALSE;
	end;
	SDL_TEXTINPUT: handleInput(evt);
	SDL_KEYDOWN: handleKeyDown(evt, modi);
	SDL_UserEvent: decodeUserEvent(evt);
	end; (* case *)
end;

procedure waitNextEvent;
var
	cont, toBlink : Boolean;
	tt : QWord;
	flashTime, lastFlash : QWord;
	flashText : Boolean;
begin
	cont := TRUE;
	sdlReady := TRUE; (* SDL window is ready to receive events *)
	toBlink := false;
	flashTime := TextBlinkTime;
	flashText := false;
	lastFlash := 0;
	while (cont) do begin
		tt := SDL_GetTicks64; //GetTickCount64;
		cont := GetNextEvent;
		if ((tt - lastBlink) > BlinkTime) then 
			toBlink := true; (* For visiblity, we only need to flash the cursor on refresh *)
		if (tt - lastFlash) > flashTime then flashText := true;
		(* Only need to refresh the frame at a standard frame rate *)
		if ((tt - lastPresent) > FPStime) and cont then begin
			if toBlink then begin
				doblink;
				toBlink := false;
			end;
			if flashText then begin
				pixmap.present(true);
				flashText := false;
				lastFlash := tt;
			end else pixmap.present(false);
			lastPresent := tt;
		end;

	end;
	sdlReady := FALSE; (* SDL thread is completed *)
end;

procedure Window(x1, y1, x2, y2 : Byte);
var
	i : PtrUint;
	data : DWORD;
begin
	(* Assuming 1 based coordinate system *)
	if x1 < 1 then exit;
	if y1 < 1 then exit;
	(* Legal left and right corner. x2,y2 should > x1,y1 *)
	if x2 <= x1 then exit;
	if y2 <= y1 then exit;
	if x2 > consoleSize.w then exit;
	if y2 > consoleSize.h then exit;
	(* Pack the 4 bytes into the 32bit integer *)
	data := (x1 shl 24) + (y1 shl 16) + (x2 shl 8) + y2;
	i := PtrUint(data);
	if not sdlReady then Exit;
	postEvent(fnWindow, PInteger(i), PInteger(0));
end;

procedure setTerm(col, row : Word);
begin
	pixmap.getFontSize(pen.w, pen.h);
	consoleSize.x := 1;
	consoleSize.y := 1;
	consoleSize.w := col;
	consoleSize.h := row;
	term.x := 1;
	term.y := 1;
	term.w := col * pen.w + 2;
	term.h := row * pen.h + 2;
	vw.col := col;
	vw.row := row;
	pen.x := BLEED; //vw.offset.x * pen.w + 1;
	pen.y := BLEED; //vw.offset.y * pen.h + 1;
end;

procedure windowInit;
begin
(* Setup default color and dimension *)
	fgColor := LightGray;
	bgColor := Black;
	TextAttr := $07;
	savedTextAttr := $07;
	pixmap.setForeColor(fgColor);
	pixmap.setBackColor(bgColor);
(*	backColor.r := $0;
	backColor.g := $0;
	backColor.b := $0;
	backColor.a := $ff;
	foreColor.r := $ff;
	foreColor.g := $ff;
	foreColor.b := $ff;
	foreColor.a := $ff;
*)
	keyAry.len := 0;
	keyAry.consumed := 0;
	pen.x := BLEED;
	pen.y := BLEED;
	pen.w := 0;
	pen.h := 0;
	term.x := 1;
	term.y := 1;
	cursor.ready := false; // Reset data transfer
	vw.cursorShown := false;
	vw.cursorOn := true;
	WindMin := 0;
	vw.x1 := 0;
	vw.x2 := 0;
	vw.y1 := 0;
	vw.y2 := 0;
	
	if (LastMode and Font8x8) = Font8x8 then begin
		if fontFileName <> '' then
			pixmap.setDimensionWith(S80x50, fontFileName, fontSize)
		else pixmap.setDimension(S80x50);
		setTerm(80, 50);
		WindMax := (49 shl 8) or 79;
	end;
	if (LastMode = BW40) or (LastMode = CO40) then begin
		if fontFileName <> '' then
			pixmap.setDimensionWith(S40x25, fontFileName, fontSize)
		else pixmap.setDimension(S40x25);
		setTerm(40, 25);
		WindMax := (24 shl 8) or 39;
	end;
	if (LastMode = BW80) or (LastMode = CO80) or (LastMode = Mono) then begin
		if fontFileName <> '' then
			pixmap.setDimensionWith(S80x25, fontFileName, fontSize)
		else pixmap.setDimension(S80x25);
		setTerm(80,25);
		WindMax := (24 shl 8) or 79;
	end;
	lastPresent := 0; // SDL_GetTicks64;
	lastBlink := 0;
end;

function winmain(p :Pointer) : PtrInt;
var
	win : PSDL_Window;
	dm : TSDL_DisplayMode;
	m : TFPUExceptionMask;
begin
	sdlReady := FALSE;

	windowInit;
	
	(* Work around as suggested to avoid the Invalid floating point operation error *)
	m := GetExceptionMask;
	include(m, exInvalidOp);
	SetExceptionMask(m);
	
	SDL_Init(SDL_INIT_VIDEO);
	eventID := SDL_RegisterEvents(1);
	SDL_GetCurrentDisplayMode(0, @dm);
	Logger.log('Screen %d x %d Pixel: %d x %d %d x %d EST texture mem: %.2fM', 
		[dm.w, dm.h, pen.w, pen.h, term.w, term.h, term.w*term.h*4/1024/1024]);
	if term.w < 1 then Halt(0);
	if term.h < 1 then Halt(0);
	if term.w > dm.w then term.w := dm.w;
	if term.h > dm.h then term.h := dm.h;
	win := SDL_CreateWindow(PChar(windowTitle), SDL_WINDOWPOS_CENTERED,
				SDL_WINDOWPOS_CENTERED,term.w, term.h, 0);
	pixmap.createRenderer(win);
	pixmap.renderClear;
	pixmap.present(false);
	SDL_StartTextInput();
	waitNextEvent;
	pixmap.destroyRenderer;
	SDL_StopTextInput();
	SDL_DestroyWindow(win);	
	SDL_Quit;
	sdlReady := FALSE; (* Should already be set in end of WaitNextEvent *)
	winmain := 0;
end;

procedure TextMode(Mode : Word);
var
	event : TSDL_Event;
begin
	assignOutput(false);
	sdlReady := FALSE;
	event.type_ := SDL_QUITEV;
	(* Close the openned window first *)
	if winThread > 0 then begin
		SDL_PushEvent(@event);
		WaitForThreadTerminate(winThread,-1);
	end;
	LastMode := Mode;
	if (Mode and Mono) = Mono then monoChrome := true
	else monoChrome := false;
	if Mode <> ReservedTextMode then begin
		winThread := BeginThread(@winmain);
		if winThread = 0 then begin	
			Logger.error('System resource problem: Cannot start thread');
			exit;
		end;
		(* Wait for completion of window construction *)
		while (not sdlReady) do begin end; 
		assignOutput(true);
		Logger.log('Window ready');
	end;
end;

procedure TextModeFont(Mode :Word; font : AnsiString; ptSize : Integer);
begin
	fontFileName := font;
	fontSize := ptSize;
	TextMode(Mode);
end;

procedure closeWindow;
var
	event : TSDL_Event;
begin
	Logger.log('Close Window');
	assignOutput(false);
	sdlReady := FALSE;
	event.type_ := SDL_QUITEV;
	(* Close the openned window *)
	if winThread > 0 then begin
		SDL_PushEvent(@event);
		WaitForThreadTerminate(winThread,-1);
		winThread := 0;
	end;
end;


procedure putChar(c : Char; render : Boolean);
var
	evt : TSDL_Event;
	i : PtrUint;
	
begin
	evt.type_ := eventID;
	if render then evt.user.code := ord(fnWrite)
	else evt.user.code := ord(fnAddChar);
	i := PtrUint(c);
	evt.user.data1 := PInteger(i);
	if SDL_PushEvent(@evt) <> 1 then 
		Logger.error('SDL push event failed');
end;

procedure updateWindow;
begin
	postEvent(fnShow);
end;

function ReadKey : Char;
var
	c : Char;
	i : Integer;
begin
	if winThread = 0 then TextMode(CO80);
	if keyAry.len > 0 then begin
	(* This is really for interpreting the ReadKey function returning #0
	   on the first call when special key were registered *)
		inc(keyAry.consumed);
		c := keyAry.buf[keyAry.consumed];
		if keyAry.len <= keyAry.consumed then begin
			keyAry.len := 0;
			keyAry.consumed := 0;
		end;
		ReadKey := c;
		Exit;
	end;
	while (not keyBuf.keyPressed) do begin
		(* If the window is close, stop the program *)
		(* There is really no other way to exit gracefully *)
		if not sdlReady then Halt(0);
		sleep(15);
	end;
	EnterCriticalSection(keyBuf.key);
	keyBuf.keyPressed := FALSE;
	(* When there is more than 1 char, save the buffer for subsequent ReadKey call *)
	if keyBuf.len > 1 then begin
		keyAry.len := keyBuf.len;
		for i := 1 to keyBuf.len do
			keyAry.buf[i] := keyBuf.buf[i];
		keyAry.consumed := 1;
	end;
	keyBuf.len := 0; (* Reset the key buffer *)
	c := keyBuf.buf[1];
	LeaveCriticalSection(keyBuf.key);
	ReadKey := c;
end;

(* Just a simple wrap around the sysutils.sleep procedure *)
procedure Delay(MS : Word);
begin
	sleep(MS);
end;

(* 
	This check eats up compute time for compatibility.
	Just my feeling, beside old CP/M programs, I do not think
	DOS Turbo Pascal program set TextAttr explicitly instead of
	using TextColor and TextBackground.
 *)
procedure checkTextAttr;
var	
	fg, bg : Byte;
begin
	if TextAttr <> savedTextAttr then begin
		fg := TextAttr and $0F;
		bg := (TextAttr and $70) shr 4;
		if bgColor <> bg then TextBackground(bg);
		if fgColor <> fg then TextColor(fg);
		savedTextAttr := TextAttr;
	end;
end;

procedure crtWrite(Var F: TextRec);
var
	Temp : String;
	idx, i, j : LongInt;
	str : AnsiString;
begin
	idx := 0;
	str := '';
	checkTextAttr; 
	while (F.BufPos>0) do begin
		i:=F.BufPos;
		if i > 255 then i := 255;
		SetLength(Temp, i);
		Move(F.BufPTR^[idx],Temp[1],i);
		str := str + Temp;
		if i > 1 then begin
			for j := 1 to i do begin
				if temp[j] <> #13 then
					putChar(temp[j], false);
			end;
			updateWindow;
		end else begin
			putChar(temp[1], true);
		end;
		dec(F.BufPos,i);
		inc(idx,i);
	end;
	SetLength(Temp, 0);
	(* SDL_RenderPresent is called on newline *)
end;
		
(* CRT redirection functions *)
Procedure crtClose(Var F: TextRec);
Begin
	F.Mode:=fmClosed;
End;

(* Reasign the output function *)
procedure crtOpen(Var F : TextRec);
begin
	if F.Mode=fmOutput Then begin
		TextRec(F).InOutFunc:=@crtWrite;
		TextRec(F).FlushFunc:=@crtWrite;
	end;
	TextRec(F).CloseFunc:=@crtClose;
end;

procedure assignCrt(Var F : Text);
begin
	Assign(F,'');
	savedOpenFunc := TextRec(F).OpenFunc;
	TextRec(F).OpenFunc:=@crtOpen;
end;
		
(* Redirect output to render through SDL. *)
procedure assignOutput(sw :boolean);
begin
	if (savedOpenFunc = nil) and sw then begin
		assignCrt(output);
		Rewrite(Output);
		TextRec(Output).Handle:=StdOutputHandle;
	end else if (savedOpenFunc <> nil) then begin
		Assign(Output,'');
		TextRec(Output).OpenFunc:= savedOpenFunc;
		Rewrite(Output);
		TextRec(Output).Handle:=StdOutputHandle;
		savedOpenFunc := nil;
	end;
end;

(* Console prompt is needed on system like the Windows WSL.
   SDL_ShowMessageBox always failed in Windows WSL environment
 *)
function consoleMsg : ShortInt;
var
	c : Char;
begin
	writeln(stderr, 'End program now? (Y or N)');
	c := ReadKey;
	if (c = 'y') or (c = 'Y') then
		consoleMsg := 0
	else begin
		writeln(stderr, 'Click the close box to terminate program');
		consoleMsg := 1;
	end;
end;

procedure closeWinMsg;
var
	data : TSDL_MessageBoxData;
	buttons : array [0..2] of TSDL_MessageBoxButtonData;
	id : ShortInt;
	w : PSDL_Window;
begin
	w := GetActiveWindow;
	data .flags := SDL_MESSAGEBOX_INFORMATION;
	data.window := w;
	data.title := 'End Of Program';
	(* Lengthen the message so the title bar show the full title text *)
	data._message := 'End program now? ' + #10 + 'If No is selected, click on the close box to end program';
	data.numbuttons := 2;
	buttons[0].flags := SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT;
	buttons[0].buttonid := 0;
	buttons[0].text := 'Yes';
	buttons[1].flags := SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT;
	buttons[1].buttonid := 1;
	buttons[1].text := 'No';
	data.buttons := @buttons[0];
	data.colorScheme := nil;
	if (SDL_ShowMessageBox(@data, @id) < 0) then begin
		(* Under Windows WSL, this will always failed *)
		//writeln(stderr, 'Msgbox error ', SDL_GetError);
		id := consoleMsg;
	end;
	if id = 0 then CloseWindow;
end;

initialization
begin	
	Logger.log('Initializing SDL2 unit');
	windowTitle := ApplicationName;
	winThread := 0;
	LastMode := ReservedTextMode;
	sdlReady := FALSE;
	keyBuf.len := 0;
	keyBuf.keyPressed := FALSE;
	savedOpenFunc := nil;
	term.x := 1;
	term.y := 1;
	cursor.ready := false; // No data transfer yet
	InitCriticalSection(keyBuf.key);
	fontFileName := '';
	fontSize := 0 ;
	monoChrome := false; (* assume colour monitor first *)
end;

finalization
begin
	Logger.log('Finalize sdl2');
	if winThread > 0 then begin
		if sdlReady then closeWinMsg;
		WaitForThreadTerminate(winThread,-1);
	end;
	DoneCriticalSection(keyBuf.key);
end;

end.
