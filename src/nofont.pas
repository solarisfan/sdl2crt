unit nofont;

{$DEFINE VGAFONT}
{$I renderChar.inc}


initialization
begin
end;

finalization
begin
	writeln(stderr, 'Freetype finalize');
end;

end.
