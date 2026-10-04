use strict;
use DynaLoader;

my $path = shift @ARGV or die "usage: nowplaying.pl <libNowPlayingHelper.dylib>\n";
my $lib = DynaLoader::dl_load_file($path, 0) or die DynaLoader::dl_error();
my $sym = DynaLoader::dl_find_symbol($lib, "notchapp_nowplaying_run") or die DynaLoader::dl_error();
my $run = DynaLoader::dl_install_xsub("main::run", $sym);
&$run;
