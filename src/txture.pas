unit txture;
interface
uses sdl2, vgafont, sysutils, log4;

const
	(* Constant masking the High, Low and Norm Video call *)
	NormalIntensity = 1;
	LowIntensity = 2;
	HighIntensity = 3;
type
	TScreenMode = (S40x25, S80x25, S80x50);
	TPixArray = array of array of PSDL_Texture;
	TCursorMap = object
		pic : array [1..2] of PSDL_Texture;
		last : TSDL_Rect;
		valid : Boolean;
	end;
	TPixMap = object
	private
		(* 1 and 2 are the window's texture map. 1 is positive plane, 2 is inverse plane
		   3 and 4 are the user defined window, view's texture map *)
		pix : array [1..4] of PSDL_Texture;
		viewIdx, canvasIdx : Byte; (* index to the active texture *)
		canvas : PSDL_Texture; (* texture for the whole window *)
		view : PSDL_Texture; (* texture of the segment set in the Window call *)
		scratch : PSDL_Texture; (* temporary texture for copying *)
		cursor : TCursorMap;
		size : TSDL_Rect;
		blinkText : Boolean;
	public
		constructor Init;
		destructor Release;
		procedure getFontSize(var w, h : LongInt);
		procedure setDimension(x : TScreenMode);
		procedure setDimensionWith(x : TScreenMode; fontFile : AnsiString; ptSize : Integer);
		function createRenderer(w : PSDL_Window) : PSDL_Renderer;
		procedure setForeColor(Color : Byte);
		procedure setBackColor(Color : Byte);
		procedure setIntensity(video : Byte);
		procedure getTexture(s: PChar; var texture : PSDL_Texture);
		procedure renderClear;
		procedure fillRect(r : TSDL_RECT);
		procedure drawLine(x1, y1, x2, y2 : Integer);
		procedure hideLine(x1, y1, x2, y2 : Integer);
		procedure drawCursor(x, y : Integer);
		procedure hideCursor;
		procedure cacheCursor;		
		procedure saveCursor(x, y : Integer);
		procedure present(switch : Boolean);
		procedure copyTexture(texture : PSDL_Texture; x, y : Integer);
		procedure createTexture(s: PChar; var texture : PSDL_Texture);
		procedure defineView(r :TSDL_Rect);
		procedure destroyRenderer;
		procedure scrollUp(offset, h : Integer);
		procedure deleteLine(y, h : Integer);
		procedure copyDelete(idx: Byte; y, h : Integer);
		procedure copyInsert(idx, y, h : Integer);
		procedure insertLine(y, h : Integer);
		procedure scrollScratch(idx : Integer; offset, h : Integer);
		procedure flush;
	end;
var	
	pixmap : TPixMap;
	
function getActiveWindow : PSDL_Window;
	
implementation

type
	PCacheTexture = ^TCacheTexture;
	TCacheTexture = record
		ch : UInt32;
		fg, bg : Byte;
		intensity : Byte;
		ptr : PSDL_TEXTURE;
		next : PCacheTexture;
	end;

const CacheSize = 256;
	
var
	foreColor, backColor : TSDL_Color;
	fgColor, bgColor : Byte;
	intensity : Byte;
	render : PSDL_Renderer;
	TextureCache : array [0 .. CacheSize-1] of TCacheTexture;
	
{$I cgacolor.inc }

	(* Zero based index. Caller should do w-1 and h-1 if necessary *)
	procedure ZeroCache(map : TPixArray;  w, h : Integer);
	var 
		i, j : Integer;
	begin
		for i := 0 to h do begin
			for j := 0 to w do begin
				map[i, j] := nil;
			end; (* for j *)
		end; (* for i *)
	end;
	
	function GetActiveWindow : PSDL_Window;
	begin
		GetActiveWindow := SDL_RenderGetWindow(render);
	end;

	procedure TPixMap.scrollScratch(idx : Integer; offset, h : Integer);
	var
		tmp : Integer;
		r, r2 : TSDL_Rect;
	begin
		tmp := h + offset;
		r.x := 0;
		r.y := tmp;
		SDL_QueryTexture(pix[idx], nil, nil, @r.w, @r.h);
		r.h := r.h - tmp;
		r2.x := 0;
		r2.y := offset;
		r2.w := r.w;
		r2.h := r.h;
		SDL_SetRenderTarget(render, scratch);
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		SDL_RenderClear(render);
		(* Copy view to scratch *)
		SDL_RenderCopy(render, pix[idx], @r, @r2);
		(* Copy scratch back to view *)
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderCopy(render, scratch, nil, nil);
		SDL_SetRenderTarget(render, cursor.pic[(idx mod 2) + 1]);
		SDL_RenderCopy(render, pix[idx], @cursor.last, nil);
	end;
	
	(* Scroll up by h pixel starting from offset *)
	procedure TPixMap.scrollUp(offset, h : integer);
	begin
		if view <> nil then begin
			scrollScratch(3, offset, h);
			scrollScratch(4, offset, h);
		end else begin
			scrollScratch(1, offset, h);
			scrollScratch(2, offset, h);
		end;
	end;
	
	procedure TPixMap.copyDelete(idx: Byte; y, h : Integer);
	var
		r, r2 : TSDL_Rect;
	begin
		SDL_QueryTexture(pix[idx], nil, nil, @r.w, @r.h);
		r.x := 0;
		r.y := y + h;
		r.h := r.h - r.y;
		r2.x := 0;
		r2.y := y;
		r2.w := r.w;
		r2.h := r.h;
		SDL_SetRenderTarget(render, scratch);
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		SDL_RenderClear(render);
		(* Copy view content to scratch *)
		SDL_RenderCopy(render, pix[idx], @r, @r2);
		SDL_SetRenderTarget(render, pix[idx]);
		r2.h := r2.h + h;
		SDL_RenderCopy(render, scratch, @r2, @r2);
	end;
	
	procedure TPixMap.deleteLine(y, h : Integer);
	begin
		(* Clear the content in cursor *)
		SDL_SetRenderTarget(render, cursor.pic[1]);
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		SDL_RenderClear(render);
		SDL_SetRenderTarget(render, cursor.pic[2]);
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		SDL_RenderClear(render);
		if view <> nil then begin
			copyDelete(3, y, h);
			copyDelete(4, y, h);
		end else begin
			copyDelete(1, y, h);
			copyDelete(2, y, h);
		end;
		cacheCursor;
	end;
	
	procedure TPixMap.copyInsert(idx, y, h : Integer);
	var
		r, r2 : TSDL_Rect;
	begin
		SDL_QueryTexture(pix[idx], nil, nil, @r.w, @r.h);
		r.x := 0;
		r.y := y + h;
		r.h := r.h - r.y - h;
		r2.x := 0;
		r2.y := r.y+h;
		r2.w := r.w;
		r2.h := r.h;
		SDL_SetRenderTarget(render, scratch);
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		SDL_RenderClear(render);
		(* Copy view content to scratch *)
		SDL_RenderCopy(render, pix[idx], @r, @r2);
		SDL_SetRenderTarget(render, pix[idx]);
		r2.y := r2.y - h;
		r2.h := r2.h + h;
		SDL_RenderCopy(render, scratch, @r2, @r2);
	end;
	
	procedure TPixMap.insertLine(y, h : Integer);
	begin
		if view <> nil then begin
			copyInsert(3, y, h);
			copyInsert(4, y, h);
		end else begin
			copyInsert(1, y, h);
			copyInsert(2, y, h);
		end;
	end;
	
	procedure TPixMap.createTexture(s: PChar; var texture : PSDL_Texture);
	var
		surface : PSDL_Surface;
(*		background : PSDL_Surface;
		r : TSDL_Rect; *)
	begin
		tty_renderChar(s[0], foreColor, backColor, surface);
		texture := SDL_CreateTextureFromSurface(render, surface);
(*
		r.x := 0;
		r.y := 0;
		surface := TTF_RenderUTF8_Shaded(ttfFont, s, foreColor, backColor);
		r.w := surface^.w;
		r.h := surface^.h;
		with surface^.format^ do begin
			background := SDL_CreateRGBSurface(0, chWidth, chHeight, 32, Rmask, Gmask, Bmask, Amask);
		end;
		SDL_FillRect(background, nil, SDL_MapRGB(background^.format, backColor.r, backColor.g, backColor.b));
		SDL_BlitSurface(surface, @r, background, nil);
		texture := SDL_CreateTextureFromSurface(render, background); //surface);
		SDL_FreeSurface(background);
*)
		SDL_FreeSurface(surface);
	end;

	procedure findTexture(s: PChar; var elem : PCacheTexture);
	var
		uc : UInt32;
		len, i, hash : Integer;
		p, q : PCacheTexture;
		x : Byte;
		cont : Boolean;
	begin
		len := 0;
		uc := 0;
		elem := nil;
		x := Byte(s[0]);
		if x < $80 then begin
			if (x > 1) and (x < 127) then
			(* Printable ASCII Code *)
				len := 1;
		end
		else if (x and $F0) = $F0 then len := 4
		else if (x and $E0) = $E0 then len := 3
		else if (x and $C0) = $C0 then len := 2;
		if len > 0 then 
		begin
			for i := 0 to len - 1 do
			begin
				uc := uc shl 8;
				uc := uc or Byte(s[i]);
			end;
			hash := uc mod 256;
			cont := true;
			p := @TextureCache[hash];
			(* First texture *)
			if (p^.ch = 0) then begin
				p^.ch := uc;
				p^.ptr := nil;
				p^.fg := fgColor;
				p^.bg := bgColor;
				p^.intensity := intensity;
				p^.next := nil;
				cont := false;
			end;
			q := p;
			(* Walk down the link list to find the matching texture *)
			while cont do
			begin
				if (p = nil) then cont := false
				else if ((p^.ch = uc) and (p^.fg = fgColor) 
						and (p^.bg = bgColor) and (p^.intensity = intensity)) 
					then cont := false;
				if cont then begin
					q := p;
					p := p^.next;
				end;
			end;
			if p = nil then begin (* add new texture *)
				new(p);
				p^.ch := uc;
				p^.ptr := nil;
				p^.fg := fgColor;
				p^.bg := bgColor;
				p^.next := nil;
				q^.next := p;
			end;
			elem := p;
		end;
	end;
	
	procedure TPixMap.getTexture(s: PChar; var texture : PSDL_Texture);
	var
		e : PCacheTexture;
	begin
		SDL_SetRenderDrawColor(render, foreColor.r, foreColor.g, foreColor.b, foreColor.a);
		findTexture(s, e);
		if e = nil then 
			texture := nil
		else if (e^.ptr = nil) then begin
			createTexture(s, texture);
			e^.ptr := texture;
		end else begin
			texture := e^.ptr;
		end;
	end;
	
	constructor TPixMap.Init;
	var
		i : Integer;
	begin
		intensity := NormalIntensity;
		canvas := nil;
		cursor.valid := false;
		cursor.pic[1] := nil;
		cursor.pic[2] := nil;		
		for i := 0 to CacheSize-1 do begin
			TextureCache[i].ptr := nil;
			TextureCache[i].fg := 0;
			TextureCache[i].bg := 0;
			TextureCache[i].ch := 0;
			TextureCache[i].next := nil;
		end;
		for i := 1 to 4 do pix[i] := nil;
		view := nil;
		blinkText := false;
	end;
	
	procedure releaseCache(p : PCacheTexture);
	begin
//	writeln(stderr, 'Release: ', format('%p', [p]));
		if p <> nil then
		begin
			SDL_DestroyTexture(p^.ptr);
			releaseCache(p^.next);
			dispose(p);
		end;
	end;
	
	destructor TPixMap.Release;
	var
		i : Integer;
	begin
		Logger.log('Freeing texture cache');
		for i := 0 to CacheSize - 1 do begin
			if TextureCache[i].ptr <> nil then begin
				SDL_DestroyTexture(TextureCache[i].ptr);
				TextureCache[i].ptr := nil;
			end;
			releaseCache(TextureCache[i].next);
		end;
		for i := 1 to 4 do begin
			if pix[i] <> nil then SDL_DestroyTexture(pix[i]);
			pix[i] := nil;
		end;
		
		SDL_SetRenderTarget(render, nil);
		canvas := nil;
		view := nil;
		if scratch <> nil then SDL_DestroyTexture(scratch);
		scratch := nil;
		for i := 1 to 2 do begin
			if cursor.pic[i] <> nil then SDL_DestroyTexture(cursor.pic[i]);
			cursor.pic[i] := nil;
		end;
		cursor.valid := false; (* Really useless, just peace of mind *)
	end;

	procedure TPixMap.setForeColor(Color : Byte);
	var	
		c : LongInt;
		colour : Byte;
	begin
		c := 0;
		fgColor := 0;
		if (Color and $80) > 0 then blinkText := true
		else blinkText := false;
		colour := color and $0f;
		if colour < 16 then begin
			case intensity of
				NormalIntensity: c := colorMap[Colour];
				LowIntensity: c := LoColorMap[Colour];
				HighIntensity: c := HiColorMap[Colour];
			end;
			fgColor := Color;
		end;
		foreColor.r := c shr 16;
		foreColor.g := (c shr 8) and $FF;
		foreColor.b := c and $FF;
		foreColor.a := 255;
	end;
	
	procedure TPixMap.setBackColor(Color : Byte);
	var	
		c : LongInt;
		colour : Byte;
	begin
		c := 0;
		bgColor := 0;
		if (intensity = HighIntensity) and (Color < 8) then
			colour := Color + 8
		else colour := Color;
		if Color < 16 then begin
			c := bgcolorMap[colour];
			bgColor := Color;
		end;
		backColor.r := c shr 16;
		backColor.g := (c shr 8) and $FF;
		backColor.b := c and $FF;
		backColor.a := 255;
	end;

	procedure TPixMap.setIntensity(video : Byte);
	begin
		if (video > 0) and (video < 4) then intensity := video;
		setForeColor(fgColor);
	end;
	
	function TPixMap.createRenderer(w : PSDL_Window) : PSDL_Renderer;
	begin
		Logger.log('create renderer');
		SDL_GetWindowSize(w, @size.w, @size.h);
		size.x := 0;
		size.y := 0;
		render := SDL_CreateRenderer(w, -1, SDL_RENDERER_ACCELERATED);
		pix[1] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		pix[2] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		canvas := pix[1];
		canvasIdx := 1;
		scratch := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		view := nil; (* No window defined yet *)
		viewIdx := 0;
		tty_GetPixelSize(cursor.last.w, cursor.last.h);
		
		cursor.pic[1] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, cursor.last.w, cursor.last.h);
		cursor.pic[2] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, cursor.last.w, cursor.last.h);
		cursor.valid := false;
		createRenderer := render;
	end;
	
	procedure TPixMap.defineView(r : TSDL_Rect);
	var
		x, y : Integer;
		w : PSDL_Window;
	begin
		if canvas = nil then exit; // Skip the initializing window
		(* Flush the current view the the buffered texture first *)
		if view <> nil then begin
			SDL_SetRenderTarget(render, pix[1]);
			SDL_RenderCopy(render, pix[3], nil, @size);
			SDL_DestroyTexture(pix[3]);
			pix[3] := nil;
			SDL_SetRenderTarget(render, pix[2]);
			SDL_RenderCopy(render, pix[4], nil, @size);
			SDL_DestroyTexture(pix[4]);
			pix[4] := nil;
		end;
		SDL_SetRenderTarget(render, nil); (* Set the default rendering texture 1st *)
		view := nil;
		w := SDL_RenderGetWindow(render);
		SDL_GetWindowSize(w, @x, @y);
		size.x := r.x;
		size.y := r.y;
		size.w := r.w;
		size.h := r.h;
		if scratch <> nil then SDL_DestroyTexture(scratch);
		scratch := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		canvas := pix[1]; // Reset canvas to the 1st frame
		SDL_SetRenderTarget(render, canvas);
		(* If window is restore to original size, just skip the view part *)
		if (x = size.w) and (y = size.h) then exit;
		
		pix[3] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		pix[4] := SDL_CreateTexture(render, SDL_PIXELFORMAT_RGB888,
						SDL_TEXTUREACCESS_TARGET, size.w, size.h);
		view := pix[3];
		viewIdx := 3;
		//Logger.log('Texture view x: %d y: %d w: %d h: %d',[size.x, size.y, size.w, size.h]);
		SDL_SetRenderTarget(render, pix[3]);
		SDL_RenderCopy(render, pix[1], @size, nil); (* Copy what is on the canvas to the new view *)
		SDL_SetRenderTarget(render, pix[4]);
		SDL_RenderCopy(render, pix[2], @size, nil); (* Copy what is on the canvas to the new view *)
	end;
	
	procedure TPixMap.renderClear;
	var
		idx : Integer;
	begin
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		if view <> nil then idx := 3
		else idx := 1;
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderClear(render);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderClear(render);
	end;
	
	procedure TPixMap.fillRect(r : TSDL_RECT);
	var
		idx : Integer;
	begin
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		if view <> nil then idx := 3
		else idx := 1;
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderFillRect(render, @r);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderFillRect(render, @r);
	end;
	
	procedure TPixMap.hideLine(x1, y1, x2, y2 : Integer);
	var
		idx : Integer;
	begin
		(* Drawing is done to our own cached backbuffer *)
		SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
		if view <> nil then idx := 3
		else idx := 1;
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderDrawLine(render, x1, y1, x2, y2);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderDrawLine(render, x1, y1, x2, y2);
	end;
	
	procedure TPixMap.drawLine(x1, y1, x2, y2 : Integer);
	var
		idx : Integer;
	begin
		if view <> nil then idx := 3
		else idx := 1;
		(* Drawing is done to our own cached backbuffer *)
		SDL_SetRenderDrawColor(render, foreColor.r, foreColor.g, foreColor.b, foreColor.a);
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderDrawLine(render, x1, y1, x2, y2);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderDrawLine(render, x1, y1, x2, y2);
	end;

	procedure TPixMap.cacheCursor;
	var
		idx : Integer;
	begin
		if view <> nil then idx := 3
		else idx := 1;
		(* Save the content first *)
		SDL_SetRenderTarget(render, cursor.pic[1]);
		SDL_RenderCopy(render, pix[idx], @cursor.last, nil);
		SDL_SetRenderTarget(render, cursor.pic[2]);
		SDL_RenderCopy(render, pix[idx+1], @cursor.last, nil);
	end;
	
	(* Update the cursor.last position *)
	procedure TPixMap.saveCursor(x, y : Integer);
	begin
		cursor.last.x := x;
		cursor.last.y := y;
		cacheCursor;
		cursor.valid := true;
	end;
	
	procedure TPixMap.drawCursor(x, y : Integer);
	var
		idx : Integer;
		r : TSDL_Rect;
	begin
		if view <> nil then idx := 3 
		else idx := 1;
		if (cursor.last.x <> x) or (cursor.last.y <> y) then 
			saveCursor(x, y);
		(* Calc from the updated cursor position *)
		r.x := cursor.last.x;
		r.w := cursor.last.w;
		r.y := cursor.last.y + cursor.last.h - 3;
		r.h := 3;
		SDL_SetRenderDrawColor(render, foreColor.r, foreColor.g, foreColor.b, foreColor.a);
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderFillRect(render, @r);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderFillRect(render, @r);
		cursor.valid := true;
	end;
	
	procedure TPixMap.hideCursor;
	var
		idx : Integer;
	begin
		if view <> nil then idx := 3 
		else idx := 1;
		if (cursor.valid) and (cursor.pic[1] <> nil) then begin
			SDL_SetRenderTarget(render, pix[idx]);
			SDL_RenderCopy(render, cursor.pic[1], nil, @cursor.last);
			SDL_SetRenderTarget(render, pix[idx+1]);
			SDL_RenderCopy(render, cursor.pic[2], nil, @cursor.last);
			cursor.valid := false;
		end;
	end;
	
	(* Copy subwindow to main window *)
	procedure TPixMap.flush;
	begin
		if view <> nil then begin
			SDL_SetRenderTarget(render, pix[1]);
			SDL_RenderCopy(render, pix[3], nil, @size);
			SDL_SetRenderTarget(render, pix[2]);
			SDL_RenderCopy(render, pix[4], nil, @size);
		end;
	end;
	
	(* 
		Upon frame refresh, copy our own cached backbuffer to the 
		real backbuffer for presentation
    *)
	procedure TPixMap.present(switch : Boolean);
	begin
		flush; (* Copy subwindow to main window first *)
		SDL_SetRenderTarget(render, nil);
		SDL_RenderCopy(render, canvas, nil, nil);
		SDL_RenderPresent(render);
		if switch then begin
			if viewIdx > 0 then begin
				if viewIdx = 3 then viewIdx := 4
				else viewIdx := 3;
				view := pix[viewIdx];
			end;
			if canvasIdx = 1 then canvasIdx := 2
			else canvasIdx := 1;
			canvas := pix[canvasIdx];
		end;
	end;
	
	procedure TPixMap.copyTexture(texture : PSDL_Texture; x, y : Integer);
	var
		idx : Integer;
		destR : TSDL_Rect;
	begin
		SDL_QueryTexture(texture, nil, nil, @destR.w, @destR.h);
		destR.x := x;
		destR.y := y;
		(* Need to update the image at the current cursor position *)
		SDL_SetRenderTarget(render, cursor.pic[1]);
		SDL_RenderCopy(render, texture, nil, nil);
		SDL_SetRenderTarget(render, cursor.pic[2]);
		(* Text flashing effect is just blanking character in the 2nd frame *)
		if blinkText then begin
			SDL_SetRenderDrawColor(render, backColor.r, backColor.g, backColor.b, backColor.a);
			SDL_RenderClear(render);
		end else SDL_RenderCopy(render, texture, nil, nil);
		(* Drawing is done to our own cached backbuffer *)
		if view <> nil then idx := 3
		else idx := 1;
		SDL_SetRenderTarget(render, pix[idx]);
		SDL_RenderCopy(render, texture, nil, @destR);
		SDL_SetRenderTarget(render, pix[idx+1]);
		SDL_RenderCopy(render, cursor.pic[2], nil, @destR);
	end;
	
	procedure TPixMap.getFontSize(var w, h : LongInt);
	begin
		tty_GetPixelSize(w, h);
	end;
	
	procedure TPixMap.setDimension(x : TScreenMode);
	begin
		case x of
			S80x50: tty_init(M80x50);
			S40x25: tty_init(M40x25);
			S80x25: tty_init(M80x25);
		end;
	end;
	
	procedure TPixMap.setDimensionWith(x : TScreenMode; fontFile : AnsiString; ptSize : Integer);
	begin
		case x of
			S80x50: tty_initWith(M80x50, fontFile, ptSize);
			S40x25: tty_initWith(M40x25, fontFile, ptSize);
			S80x25: tty_initWith(M80x25, fontFile, ptSize);
		end;
	end;
	
	procedure TPixMap.destroyRenderer;
	begin
		Logger.log('Destroy renderer');
		Release;
		SDL_DestroyRenderer(render);
		tty_done;
		render := nil;
	end;

initialization
begin
	Logger.log('Initializing texture management unit');
	pixmap.Init;
end;

finalization
begin
	Logger.log('Finalize texture management');
end;

end.
