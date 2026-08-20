unit nofont;

{$DEFINE NOFONT}
{$I renderChar.inc}


initialization
begin
	fontAry[S40x25].fileName := '';
	fontAry[S40x25].ptsize := 0;
	fontAry[S40x25].data := nil;
	fontAry[S40x25].size := 0;
	fontAry[S80x25].fileName := '';
	fontAry[S40x25].ptsize := 0;
	fontAry[S80x25].data := nil;
	fontAry[S80x25].size := 0;
	fontAry[S80x50].fileName := '';
	fontAry[S80x50].ptsize := 0;
	fontAry[S80x50].data := nil;
	fontAry[S80x50].size := 0;
end;

finalization
begin
	Logger.log('Freetype finalize');
end;

end.
