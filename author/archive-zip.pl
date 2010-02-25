use strict;
use warnings;
use Archive::Zip;

my $ofname = shift or die "Usage: $0 foo.zip files...";

my $zip = Archive::Zip->new();
for my $f (@ARGV) {
    if (-d $f) {
        $zip->addDirectory($f);
    } else {
        $zip->addFile($f);
    }
}
$zip->writeToFileNamed($ofname) == 0 or die;
