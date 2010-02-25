use strict;
use warnings;
use Test::More tests => 3;
use Test::Requires 'Archive::Zip';
use Archive::Zip::Uncompressed;
use File::Temp;

my $tmp = File::Temp->new(UNLINK => 0, SUFFIX => '.zip');

{
    my $zip = Archive::Zip->new();
    my $member_f = $zip->addFile('README');
    my $member_d = $zip->addDirectory('lib/');
}
