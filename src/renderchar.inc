interface
uses sdl2, freetypeh, sysutils, log4, globals
{$if defined(VGAFONT)}
,vgadata
{$endif}
;

var
	tty_console : TScreenMode;
	tty_useFontFile : Boolean;
	
procedure tty_init(Mode : TScreenMode);
procedure tty_initWith(Mode : TScreenMode; fontFile : AnsiString; ptSize :Integer);
procedure tty_Done;
procedure tty_renderChar(c : LongInt; foreColor, backColor : TSDL_Color; var surface : PSDL_Surface);
procedure tty_SetPixelSize(var width, height : LongInt);
procedure tty_GetPixelSize(var width, height : LongInt);
procedure tty_SetMode(mode : TScreenMode);

implementation

const
	FT_PIXEL_MODE_MONO = #1;
	FT_PIXEL_MODE_LCD = Byte(#5);
type
	TSize = record
		w, h : Integer;
	end;
	TFontFace = record
		fileName : AnsiString;
		ptsize : Integer; (* Font size on loading fotn file *)
		data : Pointer;
		size : Int64;
	end;
	
var
	lib : PFT_Library;
	face : PFT_Face;
	err : FT_Error;
	fontAry : array[TScreenMode] of TFontFace;
	pen, req : TSize;
	leading : Integer;
	renderMode : FT_Render_Mode;
	ttyMode : TScreenMode;
	rawData : Pointer;
	
	function FT_Render_Glyph(glyph : PFT_GlyphSlot; load_flags: FT_Render_Mode): integer; cdecl; external FreeTypeDLL Name 'FT_Render_Glyph';
	function FT_New_Memory_Face(alibrary: PFT_Library; filebase: Pointer; size: FT_LONG; face_index: integer; var aface: PFT_Face): integer; cdecl; external FreeTypeDLL Name 'FT_New_Memory_Face';

procedure tty_Done;
begin
	Logger.log('Unload freetype library');
	FT_Done_Face(face);
	if rawData <> nil then FreeMem(rawData);
	rawData := nil;
	FT_Done_FreeType(lib);
end;

function setPixelMask(c : TSDL_Color) : UInt32;
var
	i : UInt32;
begin
	i := c.r;
	i := i shl 8;
	i := i or c.g;
	i := i shl 8;
	i := i or c.b;
	setPixelMask := i;
end;

(* Borrowed from SDL_ttf DIVIDE_BY_255 *)
function divBy255(x : Integer) : Integer;
begin
	divBy255 := (((x) + (1) + ((x)>>8)) >> 8);
end;

function blend(fg :UInt8; bg :UInt8; alpha :UInt8) : UInt8;
var
	y : LongWord;
begin
(*
	x := alpha * fg;
	x := divBy255(x);
	x := x and $FF;
	*)
	y := ((fg * (alpha + 1)) + (bg * (256 - alpha))) >> 8;
	blend := y;
end;

procedure LoadGlyph(c : FT_ULong);
var
	idx : FT_UInt;
begin
	if face = nil then begin
		Logger.error('Font is not initialized');
		Halt(2);
	end;
	idx := FT_Get_Char_Index(face, c);
	FT_Load_Glyph(face, idx, FT_LOAD_DEFAULT);
	FT_Render_Glyph(face^.glyph, renderMode);
end;

procedure newSurface(w, h : Integer; backColor: TSDL_Color; var surface : PSDL_Surface);
begin
	surface := SDL_CreateRGBSurface(0, w, h, 32, 0, 0, 0, 0);
	SDL_FillRect(surface, nil, SDL_MapRGB(surface^.format, backColor.r, backColor.g, backColor.b));
end;

procedure renderLCD(foreColor, backColor : TSDL_Color; var surface : PSDL_Surface; offset : Integer);
var
	i, width, diff, pxWidth, pitches, trail, left : Integer;
	bits : FT_Bitmap;
	p : pointer;
	fg, bg : UInt32;
	pixel : ^Uint32;
	dst : TSDL_Color;
	px : Byte;
begin
	fg := setPixelMask(foreColor);
	bg := setPixelMask(backColor);
	bits := face^.glyph^.bitmap;
	p := bits.buffer;
	diff := bits.pitch - bits.width; (* # of bytes for alignment *)
	pxWidth := Trunc(bits.width/3);
	if (pxWidth > pen.w) then pxWidth := pen.w;
	trail := pen.w - pxWidth;
	if trail < 0 then trail := 0;
	left := face^.glyph^.metrics.horiBearingX>>6;
	if left < 0 then left := 0;
	newSurface(pen.w, pen.h, backColor, surface);
	SDL_LockSurface(surface);
	pixel := surface^.pixels;
	(* Non monspace font has different font height outside of ASCII alphabets *)
	if (surface^.h - bits.rows) >= offset then begin
		if left > 0 then pixel := pixel + left;
		for i:=1 to offset do begin
			pixel := pixel + pen.w;
		end;
	end;
(*	Logger.log('bits.row: %d bits.width: %d pxWidth: %d pitch: %d trail: %d left: %d pen.h: %d offset: %d', 
		[bits.rows, bits.width, pxWidth, bits.pitch, trail, left, pen.h, offset]);
*)	
	for i:=1 to bits.rows do begin
		width := pxWidth;
		pitches := bits.pitch - diff; (* Alignment adjustment *)
		p := p + diff;
		while (pitches > 0) do begin
			if width > 0 then begin
				px := Byte(p^);
				if (px = 0) then begin
					pixel^ := bg;
					p := p + 3;
				end else if (px = $ff) then begin
					pixel^ := fg;
					p := p + 3;
				end else begin
					dst.r := blend(foreColor.r, backColor.r, px);
					inc(p);
					px := Byte(p^);
					dst.g := blend(foreColor.g, backColor.g, px);
					inc(p);
					px := Byte(p^);
					dst.b := blend(foreColor.b, backColor.b, px);
					inc(p);
					dst.a := $FF;
					pixel^ := setPixelMask(dst);
				end;
				inc(pixel);
				dec(width);
			end else begin
				p := p+3;
			end; (* end if  width > 0 *)
			pitches := pitches - 3;
		end; (* while *)
		pixel := pixel + trail;
	end; (* for i *)
	SDL_UnlockSurface(surface);
end;

procedure renderNormal(foreColor, backColor : TSDL_Color; var surface : PSDL_Surface; offset : Integer);
var
	i, j, width, pxWidth, trail : Integer;
	bits : FT_Bitmap;
	p : pointer;
	fg, bg : UInt32;
	pixel : ^Uint32;
	dst : TSDL_Color;
	px : Byte;
begin
	fg := setPixelMask(foreColor);
	bg := setPixelMask(backColor);
	bits := face^.glyph^.bitmap;
	p := bits.buffer;
	pxWidth := bits.width;
	trail := pen.w - pxWidth;
	newSurface(pen.w, pen.h, backColor, surface);
	SDL_LockSurface(surface);
	pixel := surface^.pixels;
	for i:=1 to offset do begin
		pixel := pixel + pen.w;
	end;
	//Logger.log('width: %d pitch: %d', [bits.width, bits.pitch]);
	for i:=1 to bits.rows do begin
		width := bits.width;
		for j := 1 to bits.pitch do begin
			if width > 0 then begin
				px := Byte(p^);
				if (px = 0) then pixel^ := bg
				else if (px = $ff) then pixel^ := fg
				else begin
					dst.r := blend(foreColor.r, backColor.r, px);
					dst.g := blend(foreColor.g, backColor.g, px);
					dst.b := blend(foreColor.b, backColor.b, px);
					dst.a := $FF;
					pixel^ := setPixelMask(dst);
				end;
				inc(pixel);
				dec(width);
			end;
			inc(p);
		end; (* for j *)
		pixel := pixel + trail;
	end; (* for i *)
	SDL_UnlockSurface(surface);
end;

procedure tty_renderChar(c : LongInt; foreColor, backColor : TSDL_Color; var surface : PSDL_Surface);
var
	offset : Integer;
	mode : Byte;
	bits : FT_Bitmap;
begin
	LoadGlyph(c);
	bits := face^.glyph^.bitmap;
	
	mode := Byte(bits.pixel_mode);
	offset := pen.h - (face^.glyph^.metrics.height >> 6);
	offset := offset + (face^.glyph^.metrics.height - face^.glyph^.metrics.horiBearingY) >> 6;
	offset := offset - leading;
(*
	Logger.log('%s height: %d offset: %d leading: %d bearing: %d', 
		[char(c), face^.glyph^.metrics.height >> 6, offset, leading,
		face^.glyph^.metrics.horiBearingY >> 6]);
*)
	if (mode = FT_PIXEL_MODE_LCD) then renderLCD(foreColor, backColor, surface, offset)
	else renderNormal(foreColor, backColor, surface, offset);
end;

procedure resolveBaseline;
var
	i, margin, baseline : Integer;
	maxHeight, maxWidth : Integer;
	h, fontHeight, fontWidth : LongInt;
	scale : Extended;
begin
	margin := 0;
	maxHeight := 0;
	maxWidth := 0;
	baseline := 0;
	i := ord('A');
	LoadGlyph(i);
	scale := face^.size^.metrics.y_scale;
	(* Default font size, scale is 0, we just set it to 1 *)
	if scale <= 0 then scale := 1
	else scale := scale/$10000; (* Normalized the scale *)
	maxWidth := face^.glyph^.bitmap.width;
	h := Trunc((face^.ascender - face^.descender)*scale);
	fontHeight := Trunc((h and -64)/64);
	Logger.log('Scale: %d %.4f h:%d metrics.max_advance:%d ', [face^.size^.metrics.y_scale, scale,  
		Trunc((face^.ascender - face^.descender)*scale), face^.size^.metrics.max_advance>>6]);
	(* When font size is not set, metrics.max_advance is 0, so use face max_advance_width *)
	if face^.size^.metrics.max_advance > 0 then
		fontWidth := face^.size^.metrics.max_advance >> 6
	else 
		fontWidth := face^.max_advance_width >> 6;
	Logger.log('Ascender: %d Descender: %d scale: %.4n face Height: %d x-scale: %d', 
		[face^.ascender, face^.descender, face^.size^.metrics.y_scale/$10000,
		face^.height >> 6, face^.size^.metrics.x_scale]);
	Logger.log('Scalable: %d face Max advance Width: %d face Max advance Height: %d Font Height: %d width: %d', 
		[face^.face_flags and FT_FACE_FLAG_SCALABLE, face^.max_advance_width  >> 6, 
		face^.max_advance_height >> 6, fontHeight, fontWidth]);
	for i:=65 to 122 do begin
		LoadGlyph(i);
		if (face^.glyph^.metrics.height > maxHeight) then begin
			maxHeight := face^.glyph^.metrics.height;
		end;
		if (face^.glyph^.bitmap.width > maxWidth) then begin
			maxWidth := face^.glyph^.bitmap.width;
			//Logger.log('%s %d',[char(i), maxWidth]);
		end;
		if ((face^.glyph^.metrics.height - face^.glyph^.metrics.horiBearingY) > 0) then begin
			if ((face^.glyph^.metrics.height - face^.glyph^.metrics.horiBearingY) > baseline) then begin
				if face^.glyph^.metrics.horiBearingY > 0 then begin
					baseline := face^.glyph^.metrics.height - face^.glyph^.metrics.horiBearingY;
				end;
			end;
		end;
	end;
	if ord(face^.glyph^.bitmap.pixel_mode) = FT_PIXEL_MODE_LCD then maxWidth := Trunc(maxWidth/3);
	Logger.log('Pixel Mode: %d Surveyed: Max Height: %d Max Width: %d', 
		[ord(face^.glyph^.bitmap.pixel_mode), maxHeight >> 6, maxWidth]);
	maxHeight := maxHeight >> 6;
	if maxHeight < fontHeight then maxHeight := fontHeight;
	if maxWidth < fontWidth then maxWidth := fontWidth;
	baseline := baseline >> 6;
	maxHeight := maxHeight + baseline;
	margin := (req.h - maxHeight)>>1;
	if (margin < 0) then margin := 0;
	leading := baseline + margin;
	pen.w := maxWidth;
	pen.h := maxHeight;
	if ((req.w > 0) and (req.w > maxWidth)) then pen.w := req.w;
	if req.h > maxHeight then pen.h := req.h;
	Logger.log('Eff height: %d margin: %d Width: %d maxHeight: %d Baseline adjustment: %d maxWidth: %d', 
			[pen.h, margin, pen.w, maxHeight, baseline, maxWidth]);
end;

procedure load_from_file;
var
	f : AnsiString;
	h : LongInt;
begin
	if fontAry[ttyMode].fileName = '' then begin
		Logger.error('No font file specified. ');
		Logger.error('Consider using the extended procedure TextModeFont(mode, font file, point size)');
		Halt(3);
	end;
	f := fontAry[ttyMode].fileName;
	Logger.log('Using %s', [f]);
	if Length(f) < 1 then begin
		Logger.error('Missing font file name');
		Halt(2);
	end;
	if not FileExists(f) then begin
		Logger.error('Font file %s does not exist', [f]);
		Halt(3);
	end;
	err := FT_New_Face(lib, PChar(f), 0, face);
	if err > 0 then begin
		Logger.error('Error loading font file (%d)', [err]);
		Halt(1);
	end;
	if fontAry[ttyMode].ptsize > 0 then
		FT_Set_Char_Size(face, 0, fontAry[ttyMode].ptsize * 64, 0, 0)
	else begin
		h := (face^.ascender - face^.descender)>>6;
		Logger.log('Font size not set using native height: %d', [h]);
		FT_Set_Pixel_Sizes(face, 0, h);	
	end;
end;

procedure load_from_memory;
var
	h : LongInt;
begin
	err := FT_New_Memory_Face(lib, fontAry[ttyMode].data, fontAry[ttyMode].size, 0, face);
	if err > 0 then begin
		Logger.error('Internal error font info corrupted %d', [err]);
		Halt(1);
	end;
	(* Use the default font size in the embedded font *)
	h := (face^.ascender - face^.descender)>>6;
	Logger.log('ptsize: %d mode: %d h: %d', [fontAry[ttyMode].ptsize, ttyMode, h]);
	//if fontAry[ttyMode].ptsize > 0 then FT_Set_Char_Size(face, 0, 16 * 64, 96, 96) //fontAry[ttyMode].ptsize * 64, 0, 0)
	//else FT_Set_Pixel_Sizes(face, 0, h);
	FT_Set_Pixel_Sizes(face, 0, h);
end;

(* Really for debugging purpose *)
procedure read_and_load;
var
	f : AnsiString;
	fp : file of Byte;
	nbytes, total : Int64;
begin
	f := fontAry[ttyMode].fileName;
	if rawData <> nil then begin
		FreeMem(rawData);
		rawData := nil;
	end;
	if Length(f) < 1 then begin
		Logger.error('Missing font file name');
		Halt(2);
	end;
	if not FileExists(f) then begin
		Logger.error('Font file %s does not exist', [f]);
		Halt(3);
	end;
	Assign(fp, f);
	Reset(fp, 1);
	nbytes := FileSize(fp);
	GetMem(rawData, nbytes+1);
	total := 0;
	
	BlockRead(fp, rawData^, nbytes, total);
	Close(fp);
	err := FT_New_Memory_Face(lib, rawData, nbytes, 0, face);
	if err > 0 then begin
		Logger.error('%s %d', ['Error loading font info ', err]);
		FreeMem(rawData);
		Halt(1);
	end;
end;

procedure load_face;
begin
	if fontAry[ttyMode].data = nil then load_from_file
	else load_from_memory;
	resolveBaseline;
end;

procedure useFont(fontFile :PChar; size:Integer);
var
	h : LongInt;
begin
	FT_Done_Face(face);
	err := FT_New_Face(lib, fontFile, 0, face);
	if err > 0 then begin
		Logger.error('Cannot load file %s', [fontFile]);
		exit;
	end;
	Logger.log('num faces %d num glyphs %d point size:%d', 
		[face^.num_faces, face^.num_glyphs, size]);
	if size > 0 then FT_Set_Char_Size(face, 0, size * 64, 0, 0)
	else begin
		h := (face^.ascender - face^.descender)>>6;
		Logger.log('Font size not set using native height: %d', [h]);
		FT_Set_Pixel_Sizes(face, 0, h);	
	end;
(*	pen.w := 0;
	if req.h > 0 then pen.h := req.h
	else if pen.h = 0 then pen.h := (face^.ascender - face^.descender)>>6;
*)
	resolveBaseline;
end;

procedure tty_SetPixelSize(var width, height : LongInt);
begin
	req.w := width;
	req.h := height;
	FT_Set_Pixel_Sizes(face, req.w, req.h);
	resolveBaseline;
	width := pen.w;
	height := pen.h;
end;

procedure tty_GetPixelSize(var width, height : LongInt);
begin
	height := pen.h;
	width := pen.w;
end;

procedure SetMode(mode :TScreenMode);
begin
	if ttyMode = mode then exit;
	ttyMode := mode;
	case mode of
		S40x25:
		begin
			req.w := 0;
			req.h := 0;
		end;
		S80x25:
		begin
			req.w := 0;
			req.h := 0;
		end;
		S80x50:
		begin
			req.w := 0;
			req.h := 9;
		end;
	end; (* End case *)
end;

procedure tty_SetMode(mode :TScreenMode);
begin
	SetMode(mode);
	FT_Done_Face(face);
	load_face;
end;

procedure localInit(mode : TScreenMode);
begin
	face := nil;
	pen.w := 0;
	pen.h := 0;
	req.w := 0;
	req.h := 0;
	rawData := nil;
	SetMode(mode);
	renderMode := FT_RENDER_MODE_LCD;
	err := FT_Init_FreeType(lib);
	if err > 0 then begin
		Logger.error('Error loading freetype');
		Halt(3);
	end;
end;

procedure tty_init(mode : TScreenMode);
begin
	if (not tty_useFontFile) or (fontAry[mode].fileName = '') then begin
		Logger.log('Load freetype library');
		localInit(mode);
		load_face;
	end else tty_initWith(mode, fontAry[mode].fileName, fontAry[mode].ptsize);
	//FT_Set_Pixel_Sizes(face, pen.w, pen.h);
end;

procedure tty_initWith(Mode : TScreenMode; fontFile : AnsiString; ptSize :Integer);
begin
	if fontFile = '' then exit;
	Logger.log('Load freetype library with %s', [fontFile]);
	localInit(mode);
	useFont(PChar(fontFile), ptSize);
end;
